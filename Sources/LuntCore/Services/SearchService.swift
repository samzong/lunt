import Foundation
import os

@Observable
@MainActor
public class SearchService {
    public private(set) var items: [SearchResultItem] = []
    public private(set) var savedSearches: [SavedSearch] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var lastSyncedAt: Date?
    public private(set) var errorsBySearchId: [UUID: String] = [:]
    public private(set) var resultsBySearchId: [UUID: [SearchResultItem]] = [:]

    public weak var monitorStore: MonitorStore?
    public weak var notificationManager: NotificationManager?

    private let session: GitHubSession
    private let defaults: UserDefaults
    private let storageKey: String
    private let logger = Logger(subsystem: "com.samzong.lunt", category: "SearchService")

    private var knownMatchIdsBySearchId: [UUID: Set<String>] = [:]
    private var refreshInterval: TimeInterval = 300

    @ObservationIgnored private nonisolated(unsafe) var autoRefreshTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var activeFetchTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var activeSingleSyncTasks: [UUID: Task<Void, Never>] = [:]

    private var knownMatchIdsKey: String {
        "\(storageKey).knownMatchIds"
    }

    public init(
        session: GitHubSession,
        defaults: UserDefaults = .standard,
        storageKey: String = "savedSearches"
    ) {
        self.session = session
        self.defaults = defaults
        self.storageKey = storageKey
        loadFromStorage()
    }

    deinit {
        autoRefreshTask?.cancel()
        activeFetchTask?.cancel()
        for task in activeSingleSyncTasks.values {
            task.cancel()
        }
    }

    public func configure(interval: TimeInterval? = nil) {
        if let interval {
            refreshInterval = max(1, interval)
        }
        startAutoRefresh()
    }

    public func updateRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = max(1, interval)
        if autoRefreshTask != nil {
            startAutoRefresh()
        }
    }

    public func clearToken() {
        stopAutoRefresh()
        activeFetchTask?.cancel()
        activeFetchTask = nil
        for task in activeSingleSyncTasks.values {
            task.cancel()
        }
        activeSingleSyncTasks.removeAll()
        items = []
        resultsBySearchId = [:]
        errorsBySearchId = [:]
        errorMessage = nil
        lastSyncedAt = nil
        isLoading = false
    }

    public func addSearch(
        name: String,
        query: String,
        type: SearchType = .all,
        isPinned: Bool = false,
        watchAlerts: Bool = false
    ) {
        let search = SavedSearch(
            name: name,
            query: query,
            isPinned: isPinned,
            type: type,
            watchAlerts: watchAlerts
        )
        savedSearches.append(search)
        saveToStorage()
    }

    @discardableResult
    public func addOrEnableWatchSearch(name: String, query: String, isEnabled: Bool) -> UUID {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = savedSearches.firstIndex(where: {
            $0.query.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(trimmedQuery) == .orderedSame
        }) {
            savedSearches[index].watchAlerts = true
            if isEnabled {
                savedSearches[index].isEnabled = true
            }
            saveToStorage()
            return savedSearches[index].id
        }

        let search = SavedSearch(
            name: name,
            query: trimmedQuery,
            isEnabled: isEnabled,
            isPinned: false,
            type: .all,
            watchAlerts: true
        )
        savedSearches.append(search)
        saveToStorage()
        return search.id
    }

    public struct UpdateOptions: Sendable {
        public var name: String?
        public var query: String?
        public var isEnabled: Bool?
        public var isPinned: Bool?
        public var type: SearchType?
        public var watchAlerts: Bool?

        public init(
            name: String? = nil,
            query: String? = nil,
            isEnabled: Bool? = nil,
            isPinned: Bool? = nil,
            type: SearchType? = nil,
            watchAlerts: Bool? = nil
        ) {
            self.name = name
            self.query = query
            self.isEnabled = isEnabled
            self.isPinned = isPinned
            self.type = type
            self.watchAlerts = watchAlerts
        }
    }

    public func updateSearch(id: UUID, options: UpdateOptions) {
        guard let index = savedSearches.firstIndex(where: { $0.id == id }) else { return }
        let previousQuery = savedSearches[index].query.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousType = savedSearches[index].type

        if let name = options.name {
            savedSearches[index].name = name
        }
        if let query = options.query {
            savedSearches[index].query = query
        }
        if let isEnabled = options.isEnabled {
            savedSearches[index].isEnabled = isEnabled
        }
        if let isPinned = options.isPinned {
            savedSearches[index].isPinned = isPinned
        }
        if let type = options.type {
            savedSearches[index].type = type
        }

        let updatedQuery = savedSearches[index].query.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedType = savedSearches[index].type
        let definitionChanged = updatedQuery != previousQuery || updatedType != previousType

        if let watchAlerts = options.watchAlerts {
            savedSearches[index].watchAlerts = watchAlerts
            if !watchAlerts {
                knownMatchIdsBySearchId.removeValue(forKey: id)
                saveKnownMatchIds()
            }
        }

        if definitionChanged {
            knownMatchIdsBySearchId.removeValue(forKey: id)
            saveKnownMatchIds()
            errorsBySearchId.removeValue(forKey: id)
            resultsBySearchId.removeValue(forKey: id)
            monitorStore?.clearEvents(forMonitorId: id)
            aggregateResults()
        }

        saveToStorage()
    }

    public func deleteSearch(id: UUID) {
        savedSearches.removeAll { $0.id == id }
        resultsBySearchId.removeValue(forKey: id)
        errorsBySearchId.removeValue(forKey: id)
        knownMatchIdsBySearchId.removeValue(forKey: id)
        saveToStorage()
        saveKnownMatchIds()
        monitorStore?.clearEvents(forMonitorId: id)
        aggregateResults()
    }

    public func toggleSearch(id: UUID) {
        guard let index = savedSearches.firstIndex(where: { $0.id == id }) else { return }
        savedSearches[index].isEnabled.toggle()
        saveToStorage()
        aggregateResults()
    }

    public func fetchAll() async {
        if let activeFetchTask {
            await activeFetchTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.activeFetchTask = nil }
            await self.performFetchAll()
        }
        activeFetchTask = task
        await task.value
    }

    public func syncSearch(id: UUID) async {
        activeSingleSyncTasks[id]?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.activeSingleSyncTasks.removeValue(forKey: id) }
            await self.performSyncSearch(id: id)
        }
        activeSingleSyncTasks[id] = task
        await task.value
    }

    private func performSyncSearch(id: UUID) async {
        guard let search = savedSearches.first(where: { $0.id == id }) else { return }
        guard let graphqlClient = session.graphqlClient else {
            errorMessage = "Not authenticated"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let results = try await graphqlClient.search(
                query: effectiveQuery(query: search.query, type: search.type),
                first: 30
            )
            guard !Task.isCancelled, session.isAuthenticated else { return }
            resultsBySearchId[search.id] = results
            errorsBySearchId.removeValue(forKey: search.id)
            if search.watchAlerts {
                await processWatchAlerts(for: search, results: results)
            }
            guard !Task.isCancelled, session.isAuthenticated else { return }
            aggregateResults()
            lastSyncedAt = Date()
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, session.isAuthenticated, !(error is CancellationError) else { return }
            let description = error.localizedDescription
            logger.error("Failed to fetch search \(search.name, privacy: .public): \(description, privacy: .public)")
            errorsBySearchId[search.id] = description
        }
    }

    private func performFetchAll() async {
        guard let graphqlClient = session.graphqlClient else {
            errorMessage = "Not authenticated"
            return
        }

        isLoading = true
        errorMessage = nil

        let enabledSearches = savedSearches.filter(\.isEnabled)

        var succeededCount = 0
        var firstError: String?

        for search in enabledSearches {
            guard !Task.isCancelled, session.isAuthenticated else { break }
            do {
                let results = try await graphqlClient.search(
                    query: effectiveQuery(query: search.query, type: search.type),
                    first: 30
                )
                guard !Task.isCancelled, session.isAuthenticated else { break }
                resultsBySearchId[search.id] = results
                errorsBySearchId.removeValue(forKey: search.id)
                if search.watchAlerts {
                    await processWatchAlerts(for: search, results: results)
                }
                guard !Task.isCancelled, session.isAuthenticated else { break }
                succeededCount += 1
            } catch {
                guard !Task.isCancelled, session.isAuthenticated, !(error is CancellationError) else { break }
                let description = error.localizedDescription
                logger.error("Failed to fetch search \(search.name, privacy: .public): \(description, privacy: .public)")
                errorsBySearchId[search.id] = description
                if firstError == nil {
                    firstError = description
                }
            }
        }

        guard !Task.isCancelled, session.isAuthenticated else {
            isLoading = false
            return
        }

        aggregateResults()

        if enabledSearches.isEmpty || succeededCount > 0 {
            lastSyncedAt = Date()
        }

        if let firstError, items.isEmpty {
            errorMessage = firstError
        } else {
            errorMessage = nil
        }

        isLoading = false
    }

    private func processWatchAlerts(for search: SavedSearch, results: [SearchResultItem]) async {
        let currentIds = Set(results.map(\.id))
        guard let knownIds = knownMatchIdsBySearchId[search.id] else {
            knownMatchIdsBySearchId[search.id] = currentIds
            saveKnownMatchIds()
            return
        }

        let newMatches = results.filter { !knownIds.contains($0.id) }
        let updatedIds = knownIds.union(currentIds)
        if updatedIds != knownIds {
            knownMatchIdsBySearchId[search.id] = updatedIds
            saveKnownMatchIds()
        }

        guard !newMatches.isEmpty else { return }

        let newEvents = newMatches.map { item in
            MonitorEvent(
                id: "query:\(search.id.uuidString):\(item.id)",
                kind: item.itemType == .pullRequest ? "pr" : "issue",
                targetId: search.id,
                actor: "query: \(search.name)",
                repo: item.repositoryFullName,
                title: item.title,
                url: item.webURL?.absoluteString ?? "",
                occurredAt: item.updatedAt,
                number: item.number,
                isRead: false
            )
        }

        monitorStore?.addEvents(newEvents)
        if let notificationManager {
            for event in newEvents {
                guard !Task.isCancelled, session.isAuthenticated else { return }
                await notificationManager.sendMonitorNotification(for: event)
            }
        }
    }

    private func effectiveQuery(query: String, type: SearchType) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let tokens = trimmed.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        switch type {
        case .all:
            return trimmed
        case .issue:
            if tokens.contains("is:issue") || tokens.contains("type:issue") {
                return trimmed
            }
            return "\(trimmed) is:issue"
        case .pr:
            if tokens.contains("is:pr") || tokens.contains("type:pr") {
                return trimmed
            }
            return "\(trimmed) is:pr"
        }
    }

    private func startAutoRefresh() {
        autoRefreshTask?.cancel()
        let interval = refreshInterval
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await self?.fetchAll()
            }
        }
    }

    private func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    public func fetchPreview(query: String, type: SearchType = .all) async -> [SearchResultItem] {
        guard let graphqlClient = session.graphqlClient else {
            return []
        }

        do {
            return try await graphqlClient.search(
                query: effectiveQuery(query: query, type: type),
                first: 20
            )
        } catch {
            logger.error("Failed to fetch search preview: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func aggregateResults() {
        let enabledIds = Set(savedSearches.filter(\.isEnabled).map(\.id))

        var seenIds = Set<String>()
        var merged: [SearchResultItem] = []

        for (searchId, results) in resultsBySearchId where enabledIds.contains(searchId) {
            for item in results where !seenIds.contains(item.id) {
                seenIds.insert(item.id)
                merged.append(item)
            }
        }

        items = merged.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func loadFromStorage() {
        if let data = defaults.data(forKey: storageKey) {
            do {
                let decoded = try JSONDecoder().decode([LossySavedSearchElement].self, from: data)
                savedSearches = decoded.compactMap(\.search)
            } catch {
                logger.error("Failed to load saved searches: \(error.localizedDescription, privacy: .public)")
            }
        }

        if let data = defaults.data(forKey: knownMatchIdsKey),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            knownMatchIdsBySearchId = Dictionary(
                decoded.compactMap { entry in
                    guard let uuid = UUID(uuidString: entry.key) else { return nil }
                    return (uuid, Set(entry.value))
                },
                uniquingKeysWith: { _, latest in latest }
            )
        }
    }

    private func saveToStorage() {
        do {
            let data = try JSONEncoder().encode(savedSearches)
            defaults.set(data, forKey: storageKey)
        } catch {
            logger.error("Failed to save searches: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func saveKnownMatchIds() {
        let encoded = Dictionary(uniqueKeysWithValues: knownMatchIdsBySearchId.map { ($0.key.uuidString, Array($0.value)) })
        if let data = try? JSONEncoder().encode(encoded) {
            defaults.set(data, forKey: knownMatchIdsKey)
        }
    }
}

private struct LossySavedSearchElement: Decodable {
    let search: SavedSearch?

    init(from decoder: Decoder) throws {
        search = try? SavedSearch(from: decoder)
    }
}

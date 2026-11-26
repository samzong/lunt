import Foundation
import os

@Observable
@MainActor
public class SearchService {
    public private(set) var items: [SearchResultItem] = []
    public private(set) var repositoryItems: [RepositorySearchItem] = []
    public private(set) var savedSearches: [SavedSearch] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var lastSyncedAt: Date?
    public private(set) var errorsBySearchId: [UUID: String] = [:]

    public private(set) var resultsBySearchId: [UUID: [SearchResultItem]] = [:]
    public private(set) var repositoryResultsBySearchId: [UUID: [RepositorySearchItem]] = [:]

    private let session: GitHubSession
    private let defaults: UserDefaults
    private let storageKey: String
    private let logger = Logger(subsystem: "com.samzong.lunt", category: "SearchService")

    @ObservationIgnored private nonisolated(unsafe) var autoRefreshTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var activeFetchTask: Task<Void, Never>?

    private let refreshInterval: TimeInterval = 300

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
    }

    public func configure() {
        startAutoRefresh()
    }

    public func clearToken() {
        stopAutoRefresh()
        activeFetchTask?.cancel()
        activeFetchTask = nil
        items = []
        repositoryItems = []
        resultsBySearchId = [:]
        repositoryResultsBySearchId = [:]
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
        if let watchAlerts = options.watchAlerts {
            savedSearches[index].watchAlerts = watchAlerts
        }
        saveToStorage()
    }

    public func deleteSearch(id: UUID) {
        savedSearches.removeAll { $0.id == id }
        resultsBySearchId.removeValue(forKey: id)
        repositoryResultsBySearchId.removeValue(forKey: id)
        errorsBySearchId.removeValue(forKey: id)
        saveToStorage()
        aggregateResults()
        aggregateRepositoryResults()
    }

    public func toggleSearch(id: UUID) {
        guard let index = savedSearches.firstIndex(where: { $0.id == id }) else { return }
        savedSearches[index].isEnabled.toggle()
        saveToStorage()
        aggregateResults()
        aggregateRepositoryResults()
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

    private func performFetchAll() async {
        guard let graphqlClient = session.graphqlClient else {
            errorMessage = "Not authenticated"
            return
        }

        isLoading = true
        errorMessage = nil

        let enabledSearches = savedSearches.filter(\.isEnabled)
        let issueSearches = enabledSearches.filter { $0.type != .repository }
        let repoSearches = enabledSearches.filter { $0.type == .repository }

        var succeededCount = 0
        var firstError: String?

        for search in issueSearches {
            guard !Task.isCancelled else { break }
            do {
                let results = try await graphqlClient.search(query: search.query, first: 30)
                guard !Task.isCancelled, session.isAuthenticated else { break }
                resultsBySearchId[search.id] = results
                errorsBySearchId.removeValue(forKey: search.id)
                succeededCount += 1
            } catch {
                let description = error.localizedDescription
                logger.error("Failed to fetch search \(search.name, privacy: .public): \(description, privacy: .public)")
                errorsBySearchId[search.id] = description
                if firstError == nil {
                    firstError = description
                }
            }
        }

        for search in repoSearches {
            guard !Task.isCancelled else { break }
            do {
                let results = try await graphqlClient.searchRepositories(query: search.query, first: 30)
                guard !Task.isCancelled, session.isAuthenticated else { break }
                repositoryResultsBySearchId[search.id] = results
                errorsBySearchId.removeValue(forKey: search.id)
                succeededCount += 1
            } catch {
                let description = error.localizedDescription
                logger.error("Failed to fetch repository search \(search.name, privacy: .public): \(description, privacy: .public)")
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
        aggregateRepositoryResults()

        if enabledSearches.isEmpty || succeededCount > 0 {
            lastSyncedAt = Date()
        }

        if let firstError, items.isEmpty, repositoryItems.isEmpty {
            errorMessage = firstError
        } else {
            errorMessage = nil
        }

        isLoading = false
    }

    private func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.refreshInterval ?? 300))
                guard !Task.isCancelled else { break }
                await self?.fetchAll()
            }
        }
    }

    private func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    public func fetchPreview(query: String) async -> [SearchResultItem] {
        guard let graphqlClient = session.graphqlClient else {
            return []
        }

        do {
            return try await graphqlClient.search(query: query, first: 20)
        } catch {
            logger.error("Failed to fetch search preview: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func fetchRepositoryPreview(query: String) async -> [RepositorySearchItem] {
        guard let graphqlClient = session.graphqlClient else {
            return []
        }

        do {
            return try await graphqlClient.searchRepositories(query: query, first: 20)
        } catch {
            logger.error("Failed to fetch repository preview: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func aggregateResults() {
        let enabledSearches = savedSearches.filter { $0.isEnabled && $0.type != .repository }
        let enabledIds = Set(enabledSearches.map(\.id))

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

    private func aggregateRepositoryResults() {
        let enabledSearches = savedSearches.filter { $0.isEnabled && $0.type == .repository }
        let enabledIds = Set(enabledSearches.map(\.id))

        var seenIds = Set<String>()
        var merged: [RepositorySearchItem] = []

        for (searchId, results) in repositoryResultsBySearchId where enabledIds.contains(searchId) {
            for item in results where !seenIds.contains(item.id) {
                seenIds.insert(item.id)
                merged.append(item)
            }
        }

        repositoryItems = merged.sorted { $0.createdAt > $1.createdAt }
    }

    private func loadFromStorage() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        do {
            savedSearches = try JSONDecoder().decode([SavedSearch].self, from: data)
        } catch {
            logger.error("Failed to load saved searches: \(error.localizedDescription, privacy: .public)")
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
}

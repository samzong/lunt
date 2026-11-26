import Foundation

@Observable
@MainActor
public final class MonitorStore {
    public private(set) var monitors: [MonitorDefinition] = []
    public private(set) var events: [MonitorEvent] = []
    public private(set) var cursors: [UUID: String] = [:]
    public private(set) var lastSyncedAt: [UUID: Date] = [:]

    private let defaults: UserDefaults
    private let keyPrefix: String
    private var pendingLegacySearchMonitors: [PendingLegacySearchMonitor] = []
    private var droppedLegacyMonitorIds: Set<UUID> = []

    private var monitorsKey: String {
        "\(keyPrefix)monitor_definitions"
    }

    private var eventsKey: String {
        "\(keyPrefix)monitor_events"
    }

    private var cursorsKey: String {
        "\(keyPrefix)monitor_cursors"
    }

    private var lastSyncedAtKey: String {
        "\(keyPrefix)monitor_last_synced_at"
    }

    private func normalizedName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    public init(defaults: UserDefaults = .standard, keyPrefix: String = "") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
        loadFromStorage()
    }

    @discardableResult
    public func addMonitor(_ definition: MonitorDefinition) -> Bool {
        let targetId = definition.target.idString
        if monitors.contains(where: { $0.target.idString == targetId }) {
            return false
        }
        monitors.append(definition)
        saveMonitors()
        return true
    }

    public func removeMonitor(id: UUID) {
        monitors.removeAll { $0.id == id }
        events.removeAll { $0.targetId == id }
        cursors.removeValue(forKey: id)
        lastSyncedAt.removeValue(forKey: id)
        saveMonitors()
        saveEvents()
        saveCursors()
        saveLastSyncedAt()
    }

    public func updateMonitor(id: UUID, isEnabled: Bool) {
        if let index = monitors.firstIndex(where: { $0.id == id }) {
            monitors[index].isEnabled = isEnabled
            saveMonitors()
        }
    }

    public func updateMonitorToggles(id: UUID, toggles: [String: Bool]) {
        if let index = monitors.firstIndex(where: { $0.id == id }) {
            monitors[index].eventToggles = toggles
            saveMonitors()
        }
    }

    @discardableResult
    public func updateMonitorDetails(id: UUID, target: MonitorTarget, name: String?) -> Bool {
        guard let index = monitors.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let targetId = target.idString
        if monitors.contains(where: { $0.id != id && $0.target.idString == targetId }) {
            return false
        }

        let targetChanged = monitors[index].target.idString != targetId
        monitors[index].target = target
        monitors[index].name = normalizedName(name)
        saveMonitors()

        if targetChanged {
            events.removeAll { $0.targetId == id }
            cursors.removeValue(forKey: id)
            lastSyncedAt.removeValue(forKey: id)
            saveEvents()
            saveCursors()
            saveLastSyncedAt()
        }

        return true
    }

    public func saveCursor(_ cursor: String, forMonitorId monitorId: UUID) {
        cursors[monitorId] = cursor
        saveCursors()
    }

    public func recordSync(forMonitorId monitorId: UUID, at date: Date = Date()) {
        lastSyncedAt[monitorId] = date
        saveLastSyncedAt()
    }

    public func addEvents(_ newEvents: [MonitorEvent]) {
        guard !newEvents.isEmpty else { return }

        var existingIds = Set(events.map(\.id))
        var added = false

        for event in newEvents where !existingIds.contains(event.id) {
            events.append(event)
            existingIds.insert(event.id)
            added = true
        }

        if added {
            events.sort { $0.occurredAt > $1.occurredAt }
            if events.count > 500 {
                events = Array(events.prefix(500))
            }
            saveEvents()
        }
    }

    public func repairEvents(using canonicalEvents: [MonitorEvent]) {
        guard !canonicalEvents.isEmpty, !events.isEmpty else { return }

        var exactMatches: [String: MonitorEvent] = [:]
        for canonicalEvent in canonicalEvents {
            exactMatches[canonicalEvent.id] = canonicalEvent
        }

        var repairedEvents: [MonitorEvent] = []
        var didRepair = false

        for event in events {
            guard let canonical = exactMatches[event.id] else {
                repairedEvents.append(event)
                continue
            }

            let repaired = MonitorEvent(
                id: canonical.id,
                kind: canonical.kind,
                targetId: canonical.targetId,
                actor: canonical.actor,
                repo: canonical.repo,
                title: canonical.title,
                url: canonical.url,
                occurredAt: canonical.occurredAt,
                number: canonical.number,
                isRead: event.isRead
            )
            repairedEvents.append(repaired)
            didRepair = didRepair || repaired != event
        }

        if didRepair {
            events = repairedEvents.sorted { $0.occurredAt > $1.occurredAt }
            saveEvents()
        }
    }

    public func markEventRead(id: String) {
        if let index = events.firstIndex(where: { $0.id == id }) {
            events[index].isRead = true
            saveEvents()
        }
    }

    public func toggleEventRead(id: String) {
        if let index = events.firstIndex(where: { $0.id == id }) {
            events[index].isRead.toggle()
            saveEvents()
        }
    }

    public func markEventsRead(forTargetIds targetIds: Set<UUID>) {
        guard !targetIds.isEmpty else { return }
        var changed = false
        for index in events.indices where targetIds.contains(events[index].targetId) && !events[index].isRead {
            events[index].isRead = true
            changed = true
        }
        if changed {
            saveEvents()
        }
    }

    public func markAllEventsRead() {
        for index in events.indices {
            events[index].isRead = true
        }
        saveEvents()
    }

    public func clearEvents() {
        events = []
        saveEvents()
    }

    public func clearEvents(forMonitorId monitorId: UUID) {
        events.removeAll { $0.targetId == monitorId }
        saveEvents()
    }

    public func migrateLegacyMonitors(into searchService: SearchService) {
        guard !pendingLegacySearchMonitors.isEmpty || !droppedLegacyMonitorIds.isEmpty else {
            return
        }

        var targetIdMap: [UUID: UUID] = [:]
        for legacy in pendingLegacySearchMonitors {
            let searchId = searchService.addOrEnableWatchSearch(
                name: legacy.name,
                query: legacy.query,
                isEnabled: legacy.isEnabled
            )
            targetIdMap[legacy.id] = searchId
        }

        var eventsChanged = false
        if !droppedLegacyMonitorIds.isEmpty {
            let originalCount = events.count
            events.removeAll { droppedLegacyMonitorIds.contains($0.targetId) }
            if events.count != originalCount {
                eventsChanged = true
            }
        }

        for index in events.indices {
            if let newTargetId = targetIdMap[events[index].targetId] {
                let event = events[index]
                events[index] = MonitorEvent(
                    id: event.id,
                    kind: event.kind,
                    targetId: newTargetId,
                    actor: event.actor,
                    repo: event.repo,
                    title: event.title,
                    url: event.url,
                    occurredAt: event.occurredAt,
                    number: event.number,
                    isRead: event.isRead
                )
                eventsChanged = true
            }
        }

        for legacyId in targetIdMap.keys {
            cursors.removeValue(forKey: legacyId)
            lastSyncedAt.removeValue(forKey: legacyId)
        }
        for droppedId in droppedLegacyMonitorIds {
            cursors.removeValue(forKey: droppedId)
            lastSyncedAt.removeValue(forKey: droppedId)
        }

        saveMonitors()
        if eventsChanged {
            saveEvents()
        }
        saveCursors()
        saveLastSyncedAt()

        pendingLegacySearchMonitors = []
        droppedLegacyMonitorIds = []
    }

    private func saveMonitors() {
        if let data = try? JSONEncoder().encode(monitors) {
            defaults.set(data, forKey: monitorsKey)
        }
    }

    private func saveEvents() {
        if let data = try? JSONEncoder().encode(events) {
            defaults.set(data, forKey: eventsKey)
        }
    }

    private func saveCursors() {
        let stringKeyed = Dictionary(uniqueKeysWithValues: cursors.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyed) {
            defaults.set(data, forKey: cursorsKey)
        }
    }

    private func saveLastSyncedAt() {
        let stringKeyed = Dictionary(uniqueKeysWithValues: lastSyncedAt.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyed) {
            defaults.set(data, forKey: lastSyncedAtKey)
        }
    }

    private func loadFromStorage() {
        if let data = defaults.data(forKey: monitorsKey),
           let decoded = try? JSONDecoder().decode([LossyDecodable<LegacyMonitorDefinition>].self, from: data) {
            var loadedMonitors: [MonitorDefinition] = []
            var legacySearches: [PendingLegacySearchMonitor] = []
            var droppedIds: Set<UUID> = []

            for item in decoded.compactMap(\.value) {
                switch item.target {
                case let .account(login):
                    loadedMonitors.append(MonitorDefinition(
                        id: item.id,
                        target: .account(login: login),
                        name: item.name,
                        isEnabled: item.isEnabled,
                        eventToggles: item.eventToggles
                    ))
                case let .repository(owner, name):
                    loadedMonitors.append(MonitorDefinition(
                        id: item.id,
                        target: .repository(owner: owner, name: name),
                        name: item.name,
                        isEnabled: item.isEnabled,
                        eventToggles: item.eventToggles
                    ))
                case let .search(query, targetName):
                    let resolvedName = normalizedName(item.name) ?? normalizedName(targetName) ?? query
                    legacySearches.append(PendingLegacySearchMonitor(
                        id: item.id,
                        name: resolvedName,
                        query: query,
                        isEnabled: item.isEnabled
                    ))
                case .code:
                    droppedIds.insert(item.id)
                }
            }

            monitors = loadedMonitors
            pendingLegacySearchMonitors = legacySearches
            droppedLegacyMonitorIds = droppedIds
        }

        if let data = defaults.data(forKey: eventsKey),
           let decoded = try? JSONDecoder().decode([LossyDecodable<MonitorEvent>].self, from: data) {
            events = decoded.compactMap(\.value)
        }

        if let data = defaults.data(forKey: cursorsKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            cursors = Dictionary(
                decoded.compactMap { item in
                    guard let uuid = UUID(uuidString: item.key) else { return nil }
                    return (uuid, item.value)
                },
                uniquingKeysWith: { _, latest in latest }
            )
        }

        if let data = defaults.data(forKey: lastSyncedAtKey),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            lastSyncedAt = Dictionary(
                decoded.compactMap { item in
                    guard let uuid = UUID(uuidString: item.key) else { return nil }
                    return (uuid, item.value)
                },
                uniquingKeysWith: { _, latest in latest }
            )
        }
    }
}

private struct PendingLegacySearchMonitor {
    let id: UUID
    let name: String
    let query: String
    let isEnabled: Bool
}

private enum LegacyMonitorTarget: Decodable {
    case account(login: String)
    case repository(owner: String, name: String)
    case search(query: String, name: String)
    case code(query: String, name: String)
}

private struct LegacyMonitorDefinition: Decodable {
    let id: UUID
    let target: LegacyMonitorTarget
    let name: String?
    let isEnabled: Bool
    let eventToggles: [String: Bool]
}

private struct LossyDecodable<Element: Decodable>: Decodable {
    let value: Element?

    init(from decoder: Decoder) throws {
        value = try? Element(from: decoder)
    }
}

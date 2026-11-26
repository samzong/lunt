import Foundation

/// Stores and manages monitor definitions, sync cursors, and local monitor events.
@Observable
@MainActor
public final class MonitorStore {
    public private(set) var monitors: [MonitorDefinition] = []
    public private(set) var events: [MonitorEvent] = []
    public private(set) var cursors: [UUID: String] = [:]
    public private(set) var lastSyncedAt: [UUID: Date] = [:]

    private let defaults: UserDefaults
    private let keyPrefix: String

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

    /// Adds a new monitor definition.
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

    /// Removes a monitor definition and its associated cursor and events.
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

    /// Updates the enabled state of a monitor.
    public func updateMonitor(id: UUID, isEnabled: Bool) {
        if let index = monitors.firstIndex(where: { $0.id == id }) {
            monitors[index].isEnabled = isEnabled
            saveMonitors()
        }
    }

    /// Updates event filters toggle configurations.
    public func updateMonitorToggles(id: UUID, toggles: [String: Bool]) {
        if let index = monitors.firstIndex(where: { $0.id == id }) {
            monitors[index].eventToggles = toggles
            saveMonitors()
        }
    }

    /// Updates editable monitor metadata and clears stale state when the watched target changes.
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

    /// Saves the sync cursor/checkpoint for a given monitor.
    public func saveCursor(_ cursor: String, forMonitorId monitorId: UUID) {
        cursors[monitorId] = cursor
        saveCursors()
    }

    /// Records the time a monitor sync request completed successfully.
    public func recordSync(forMonitorId monitorId: UUID, at date: Date = Date()) {
        lastSyncedAt[monitorId] = date
        saveLastSyncedAt()
    }

    /// Appends new events, filtering duplicates.
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
            // Cap local inbox history
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

    /// Marks an event as read.
    public func markEventRead(id: String) {
        if let index = events.firstIndex(where: { $0.id == id }) {
            events[index].isRead = true
            saveEvents()
        }
    }

    /// Marks all events as read.
    public func markAllEventsRead() {
        for index in events.indices {
            events[index].isRead = true
        }
        saveEvents()
    }

    /// Clears all events.
    public func clearEvents() {
        events = []
        saveEvents()
    }

    /// Clears events collected for a single monitor.
    public func clearEvents(forMonitorId monitorId: UUID) {
        events.removeAll { $0.targetId == monitorId }
        saveEvents()
    }

    // MARK: - Persistence

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
           let decoded = try? JSONDecoder().decode([MonitorDefinition].self, from: data) {
            self.monitors = decoded
        }

        if let data = defaults.data(forKey: eventsKey),
           let decoded = try? JSONDecoder().decode([MonitorEvent].self, from: data) {
            self.events = decoded
        }

        if let data = defaults.data(forKey: cursorsKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            self.cursors = Dictionary(uniqueKeysWithValues: decoded.compactMap { item in
                guard let uuid = UUID(uuidString: item.key) else { return nil }
                return (uuid, item.value)
            })
        }

        if let data = defaults.data(forKey: lastSyncedAtKey),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            self.lastSyncedAt = Dictionary(uniqueKeysWithValues: decoded.compactMap { item in
                guard let uuid = UUID(uuidString: item.key) else { return nil }
                return (uuid, item.value)
            })
        }
    }
}

import Foundation
import Observation
import os

@Observable
@MainActor
public final class MonitorEngine {
    private let session: GitHubSession
    private let store: MonitorStore
    private let notificationManager: NotificationManager?
    private let sourceFactory: @MainActor (MonitorTarget) -> MonitorSource?
    private let logger = Logger(subsystem: "com.samzong.lunt", category: "MonitorEngine")

    private var timer: Task<Void, Never>?
    private var activeSingleSyncTasks: [UUID: Task<Void, Never>] = [:]
    public private(set) var isSyncing = false
    public private(set) var errorsByMonitorId: [UUID: String] = [:]

    public init(
        session: GitHubSession,
        store: MonitorStore,
        notificationManager: NotificationManager? = nil,
        sourceFactory: (@MainActor (MonitorTarget) -> MonitorSource?)? = nil
    ) {
        self.session = session
        self.store = store
        self.notificationManager = notificationManager
        self.sourceFactory = sourceFactory ?? Self.defaultSource(for:)
    }

    public func start(interval: TimeInterval = 300) {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncAll()
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    break
                }
            }
        }
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        for task in activeSingleSyncTasks.values {
            task.cancel()
        }
        activeSingleSyncTasks.removeAll()
        errorsByMonitorId.removeAll()
        isSyncing = false
    }

    public func syncAll() async {
        guard session.isAuthenticated, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let activeMonitors = store.monitors.filter(\.isEnabled)
        for monitor in activeMonitors {
            guard !Task.isCancelled, session.isAuthenticated else { break }
            await performSync(monitor: monitor)
        }
    }

    public func sync(monitor: MonitorDefinition) async {
        activeSingleSyncTasks[monitor.id]?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.activeSingleSyncTasks.removeValue(forKey: monitor.id) }
            await self.performSync(monitor: monitor)
        }
        activeSingleSyncTasks[monitor.id] = task
        await task.value
    }

    private func performSync(monitor: MonitorDefinition) async {
        guard !Task.isCancelled, session.isAuthenticated, let source = makeSource(for: monitor.target) else { return }

        let cursor = store.cursors[monitor.id]
        let isFirstSync = (cursor == nil)

        do {
            let (events, fetchedEvents, nextCursor) = try await source.fetchEvents(
                definition: monitor,
                cursor: cursor,
                session: session
            )
            guard !Task.isCancelled, session.isAuthenticated else { return }

            store.repairEvents(using: fetchedEvents)
            store.recordSync(forMonitorId: monitor.id)
            errorsByMonitorId.removeValue(forKey: monitor.id)

            if let nextCursor {
                store.saveCursor(nextCursor, forMonitorId: monitor.id)
            }

            if isFirstSync {
                logger.info("Baseline initialized for \(monitor.displayName, privacy: .public)")
            } else if !events.isEmpty {
                store.addEvents(events)
                if let notificationManager {
                    for event in events {
                        guard !Task.isCancelled, session.isAuthenticated else { return }
                        await notificationManager.sendMonitorNotification(for: event)
                    }
                }
            }
        } catch {
            guard !Task.isCancelled, session.isAuthenticated, !(error is CancellationError) else { return }
            let description = error.localizedDescription
            errorsByMonitorId[monitor.id] = description
            logger.error("Failed to sync monitor \(monitor.displayName, privacy: .public): \(description, privacy: .public)")
        }
    }

    private func makeSource(for target: MonitorTarget) -> MonitorSource? {
        sourceFactory(target)
    }

    private static func defaultSource(for target: MonitorTarget) -> MonitorSource? {
        switch target {
        case .account:
            AccountEventsMonitorSource()
        case .repository:
            RepositoryEventsMonitorSource()
        }
    }
}

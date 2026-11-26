@testable import LuntCore
import XCTest

final class MonitorTests: XCTestCase {
    func testMonitorTargetParsing() {
        XCTAssertEqual(MonitorTarget.parse(input: "samzong", type: "account"), .account(login: "samzong"))
        XCTAssertEqual(MonitorTarget.parse(input: "@google", type: "account"), .account(login: "google"))
        XCTAssertEqual(MonitorTarget.parse(input: "https://github.com/apple", type: "account"), .account(login: "apple"))
        XCTAssertEqual(MonitorTarget.parse(input: "samzong/lunt", type: "repository"), .repository(owner: "samzong", name: "lunt"))
        XCTAssertEqual(
            MonitorTarget.parse(input: "https://github.com/apple/swift", type: "repository"),
            .repository(owner: "apple", name: "swift")
        )
        XCTAssertNil(MonitorTarget.parse(input: "is:pr is:open", type: "search", name: "My PRs"))
        XCTAssertNil(MonitorTarget.parse(input: "TODO: fix", type: "code", name: "Fix Todo"))
        XCTAssertNil(MonitorTarget.parse(input: "https://google.com/apple/swift", type: "repository"))
        XCTAssertEqual(MonitorTarget.account(login: "samzong").badgeLabel, "account:samzong")
        XCTAssertEqual(MonitorTarget.repository(owner: "apple", name: "swift").badgeLabel, "repository:apple/swift")
    }

    func testMonitorDefinitionUsesCustomDisplayName() {
        let definition = MonitorDefinition(target: .account(login: "samzong"), name: "Release Watch")
        XCTAssertEqual(definition.displayName, "Release Watch")
    }

    func testGitHubEventDecodesPullRequestURLForNotificationClick() throws {
        let json = """
        {"id":"event_123","type":"PullRequestEvent","actor":{"login":"octocat"},"repo":{"name":"owner/repo"},"created_at":"2026-05-21T06:30:00Z","payload":{"action":"opened","pull_request":{"title":"Fix notification URL","html_url":"https://github.com/owner/repo/pull/42"}}}
        """

        let event = try decodeGitHubEvent(json)
        XCTAssertEqual(event.monitorKind, "pr")
        XCTAssertEqual(event.monitorURL, "https://github.com/owner/repo/pull/42")
        XCTAssertEqual(event.monitorTitle, "Opened PR: Fix notification URL")
        XCTAssertEqual(event.monitorNumber, 42)
    }

    func testGitHubEventBuildsPushCommitURLForNotificationClick() throws {
        let json = """
        {"id":"event_456","type":"PushEvent","actor":{"login":"octocat"},"repo":{"name":"owner/repo"},"created_at":"2026-05-21T06:35:00Z","payload":{"commits":[{"sha":"abc123","message":"Fix monitor click target"}]}}
        """

        let event = try decodeGitHubEvent(json)
        XCTAssertEqual(event.monitorKind, "commit")
        XCTAssertEqual(event.monitorURL, "https://github.com/owner/repo/commit/abc123")
        XCTAssertEqual(event.monitorTitle, "Pushed commit: Fix monitor click target")
        XCTAssertNil(event.monitorNumber)
    }

    func testGitHubEventUsesIssueCommentURLForNotificationClick() throws {
        let json = """
        {"id":"event_789","type":"IssueCommentEvent","actor":{"login":"octocat"},"repo":{"name":"owner/repo"},"created_at":"2026-05-21T06:40:00Z","payload":{"action":"created","issue":{"title":"Fix monitor links","html_url":"https://github.com/owner/repo/issues/7"},"comment":{"body":"The notification should open this comment.","html_url":"https://github.com/owner/repo/issues/7#issuecomment-123"}}}
        """

        let event = try decodeGitHubEvent(json)
        XCTAssertEqual(event.monitorKind, "comment")
        XCTAssertEqual(event.monitorURL, "https://github.com/owner/repo/issues/7#issuecomment-123")
        XCTAssertEqual(event.monitorTitle, "Commented on: Fix monitor links")
        XCTAssertEqual(event.monitorNumber, 7)
    }

    func testGitHubEventBuildsPushHeadURLWhenCommitsAreMissing() throws {
        let json = """
        {"id":"event_999","type":"PushEvent","actor":{"login":"octocat"},"repo":{"name":"owner/repo"},"created_at":"2026-05-21T06:45:00Z","payload":{"head":"def456"}}
        """

        let event = try decodeGitHubEvent(json)
        XCTAssertEqual(event.monitorKind, "commit")
        XCTAssertEqual(event.monitorURL, "https://github.com/owner/repo/commit/def456")
        XCTAssertEqual(event.monitorTitle, "Pushed commits to repository")
    }

    func testRawEventsSinceCursorProcessesFetchedEventsWhenCursorIsMissing() {
        let events = [
            makeGitHubEvent(id: "event_newest", occurredAt: Date(timeIntervalSince1970: 200)),
            makeGitHubEvent(id: "event_older", occurredAt: Date(timeIntervalSince1970: 100)),
        ]

        let result = rawEventsSinceCursor(events, cursor: "event_missing")
        XCTAssertEqual(result.events.map(\.id), ["event_newest", "event_older"])
        XCTAssertEqual(result.nextCursor, "event_newest")
    }

    @MainActor
    func testMonitorStoreLifecycle() throws {
        let (store, cleanup) = try makeIsolatedStore()
        defer { cleanup() }

        XCTAssertTrue(store.monitors.isEmpty)

        let def1 = MonitorDefinition(target: .account(login: "samzong"))
        let def2 = MonitorDefinition(target: .repository(owner: "apple", name: "swift"))

        store.addMonitor(def1)
        XCTAssertEqual(store.monitors.count, 1)

        store.addMonitor(MonitorDefinition(target: .account(login: "samzong")))
        XCTAssertEqual(store.monitors.count, 1)

        store.addMonitor(def2)
        XCTAssertEqual(store.monitors.count, 2)

        store.updateMonitor(id: def1.id, isEnabled: false)
        XCTAssertFalse(store.monitors.first(where: { $0.id == def1.id })?.isEnabled ?? true)

        store.removeMonitor(id: def1.id)
        XCTAssertEqual(store.monitors.count, 1)
        XCTAssertNil(store.monitors.first(where: { $0.id == def1.id }))

        store.removeMonitor(id: def2.id)
    }

    @MainActor
    func testMonitorStoreEventsAndCursors() throws {
        let (store, cleanup) = try makeIsolatedStore()
        defer { cleanup() }

        let monitorId = UUID()
        store.saveCursor("cursor_123", forMonitorId: monitorId)
        XCTAssertEqual(store.cursors[monitorId], "cursor_123")

        let syncedAt = Date(timeIntervalSince1970: 1_779_350_100)
        store.recordSync(forMonitorId: monitorId, at: syncedAt)
        XCTAssertEqual(store.lastSyncedAt[monitorId], syncedAt)

        let event1 = makeMonitorEvent(id: "event_1", kind: "commit", targetId: monitorId)
        let event2 = makeMonitorEvent(
            id: "event_2",
            kind: "issue",
            targetId: monitorId,
            actor: "tester",
            title: "Opened issue",
            url: "https://github.com/org/repo/issues/2",
            occurredAt: Date().addingTimeInterval(10)
        )

        store.addEvents([event1, event2])
        XCTAssertEqual(store.events.count, 2)
        XCTAssertEqual(store.events.first?.id, "event_2")

        store.addEvents([event1])
        XCTAssertEqual(store.events.count, 2)

        XCTAssertFalse(store.events[0].isRead)
        store.markEventRead(id: "event_2")
        XCTAssertTrue(store.events.first(where: { $0.id == "event_2" })?.isRead ?? false)

        store.toggleEventRead(id: "event_2")
        XCTAssertFalse(store.events.first(where: { $0.id == "event_2" })?.isRead ?? true)

        store.markEventsRead(forTargetIds: [monitorId])
        XCTAssertTrue(store.events.allSatisfy(\.isRead))

        store.markAllEventsRead()
        XCTAssertTrue(store.events.allSatisfy(\.isRead))

        store.clearEvents()
        XCTAssertTrue(store.events.isEmpty)
    }

    @MainActor
    func testMonitorStorePersistsLastSyncedAt() throws {
        let suiteName = "MonitorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let monitorId = UUID()
        let syncedAt = Date(timeIntervalSince1970: 1_779_350_200)

        let store = MonitorStore(defaults: defaults)
        store.recordSync(forMonitorId: monitorId, at: syncedAt)

        let reloadedStore = MonitorStore(defaults: defaults)
        XCTAssertEqual(reloadedStore.lastSyncedAt[monitorId], syncedAt)
    }

    @MainActor
    func testMonitorEngineRecordsLastSyncedAfterSuccessfulSingleSync() async throws {
        let (store, cleanup) = try makeIsolatedStore()
        defer { cleanup() }

        let monitor = MonitorDefinition(target: .account(login: "samzong"))
        store.addMonitor(monitor)

        let session = GitHubSession()
        session.configure(token: "test-token")

        let fetchedEvent = makeMonitorEvent(
            id: "\(monitor.id.uuidString):event_1",
            kind: "commit",
            targetId: monitor.id,
            actor: "octocat",
            repo: "owner/repo",
            url: "https://github.com/owner/repo/commit/1",
            occurredAt: Date(timeIntervalSince1970: 1_779_350_600)
        )
        let engine = MonitorEngine(
            session: session,
            store: store,
            sourceFactory: { target in
                XCTAssertEqual(target, monitor.target)
                return StubMonitorSource(
                    events: [fetchedEvent],
                    fetchedEvents: [fetchedEvent],
                    nextCursor: "cursor_after_sync"
                )
            }
        )

        await engine.sync(monitor: monitor)

        XCTAssertNotNil(store.lastSyncedAt[monitor.id])
        XCTAssertEqual(store.cursors[monitor.id], "cursor_after_sync")
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertTrue(engine.errorsByMonitorId.isEmpty)
    }

    @MainActor
    func testMonitorStoreClearsEventsForSingleMonitor() throws {
        let (store, cleanup) = try makeIsolatedStore()
        defer { cleanup() }

        let monitorId = UUID()
        let otherMonitorId = UUID()

        store.addEvents([
            makeMonitorEvent(id: "event_1", kind: "commit", targetId: monitorId),
            makeMonitorEvent(
                id: "event_2",
                kind: "issue",
                targetId: otherMonitorId,
                actor: "tester",
                repo: "org/other",
                title: "Opened issue",
                url: "https://github.com/org/other/issues/2",
                occurredAt: Date().addingTimeInterval(10)
            ),
        ])

        store.clearEvents(forMonitorId: monitorId)
        XCTAssertEqual(store.events.map(\.id), ["event_2"])
    }

    @MainActor
    func testMonitorStoreRemoveMonitorClearsEventsAndCursor() throws {
        let (store, cleanup) = try makeIsolatedStore()
        defer { cleanup() }

        let monitor = MonitorDefinition(target: .account(login: "samzong"))
        let otherMonitor = MonitorDefinition(target: .account(login: "octocat"))
        store.addMonitor(monitor)
        store.addMonitor(otherMonitor)
        store.saveCursor("cursor_123", forMonitorId: monitor.id)
        store.recordSync(forMonitorId: monitor.id, at: Date(timeIntervalSince1970: 1_779_350_300))
        store.addEvents([
            makeMonitorEvent(id: "event_1", kind: "commit", targetId: monitor.id),
            makeMonitorEvent(
                id: "event_2",
                kind: "issue",
                targetId: otherMonitor.id,
                actor: "tester",
                repo: "org/other",
                title: "Opened issue",
                url: "https://github.com/org/other/issues/2",
                occurredAt: Date().addingTimeInterval(10)
            ),
        ])

        store.removeMonitor(id: monitor.id)

        XCTAssertNil(store.monitors.first { $0.id == monitor.id })
        XCTAssertNil(store.cursors[monitor.id])
        XCTAssertNil(store.lastSyncedAt[monitor.id])
        XCTAssertEqual(store.events.map(\.id), ["event_2"])
    }

    @MainActor
    func testMonitorStoreUpdatesNameWithoutClearingState() throws {
        let (store, cleanup) = try makeIsolatedStore()
        defer { cleanup() }

        let monitor = MonitorDefinition(target: .account(login: "samzong"))
        store.addMonitor(monitor)
        let syncedAt = Date(timeIntervalSince1970: 1_779_350_400)
        store.saveCursor("cursor_123", forMonitorId: monitor.id)
        store.recordSync(forMonitorId: monitor.id, at: syncedAt)
        store.addEvents([makeMonitorEvent(id: "event_1", kind: "commit", targetId: monitor.id)])

        XCTAssertTrue(store.updateMonitorDetails(id: monitor.id, target: monitor.target, name: "Core Watch"))

        XCTAssertEqual(store.monitors.first?.displayName, "Core Watch")
        XCTAssertEqual(store.cursors[monitor.id], "cursor_123")
        XCTAssertEqual(store.lastSyncedAt[monitor.id], syncedAt)
        XCTAssertEqual(store.events.map(\.id), ["event_1"])
    }

    @MainActor
    func testMonitorStoreUpdatesTargetAndClearsStaleState() throws {
        let (store, cleanup) = try makeIsolatedStore()
        defer { cleanup() }

        let monitor = MonitorDefinition(target: .account(login: "samzong"))
        store.addMonitor(monitor)
        store.saveCursor("cursor_123", forMonitorId: monitor.id)
        store.recordSync(forMonitorId: monitor.id, at: Date(timeIntervalSince1970: 1_779_350_500))
        store.addEvents([makeMonitorEvent(id: "event_1", kind: "commit", targetId: monitor.id)])

        XCTAssertTrue(store.updateMonitorDetails(
            id: monitor.id,
            target: .repository(owner: "apple", name: "swift"),
            name: "Swift Watch"
        ))

        XCTAssertEqual(store.monitors.first?.target, .repository(owner: "apple", name: "swift"))
        XCTAssertEqual(store.monitors.first?.displayName, "Swift Watch")
        XCTAssertNil(store.cursors[monitor.id])
        XCTAssertNil(store.lastSyncedAt[monitor.id])
        XCTAssertTrue(store.events.isEmpty)
    }

    @MainActor
    func testMonitorStoreRejectsDuplicateTargetUpdates() throws {
        let (store, cleanup) = try makeIsolatedStore()
        defer { cleanup() }

        let monitor = MonitorDefinition(target: .account(login: "samzong"))
        let otherMonitor = MonitorDefinition(target: .repository(owner: "apple", name: "swift"))
        store.addMonitor(monitor)
        store.addMonitor(otherMonitor)

        XCTAssertFalse(store.updateMonitorDetails(
            id: monitor.id,
            target: .repository(owner: "apple", name: "swift"),
            name: nil
        ))
        XCTAssertEqual(store.monitors.first { $0.id == monitor.id }?.target, .account(login: "samzong"))
    }

    @MainActor
    func testMonitorStoreUpdatesExistingEventFromCanonicalEventPreservingReadState() throws {
        let (store, cleanup) = try makeIsolatedStore()
        defer { cleanup() }

        let monitorId = UUID()
        let initialOccurredAt = Date(timeIntervalSince1970: 1_779_349_500)
        let updatedOccurredAt = Date(timeIntervalSince1970: 1_779_350_000)
        let eventId = "\(monitorId.uuidString):pr_999"
        let storedEvent = makeMonitorEvent(
            id: eventId,
            kind: "pr",
            targetId: monitorId,
            actor: "octocat",
            repo: "owner/repo",
            title: "Initial PR title",
            url: "https://github.com/owner/repo/pull/999",
            occurredAt: initialOccurredAt,
            isRead: true
        )
        let canonicalEvent = makeMonitorEvent(
            id: eventId,
            kind: "pr",
            targetId: monitorId,
            actor: "octocat",
            repo: "owner/repo",
            title: "Updated PR title",
            url: "https://github.com/owner/repo/pull/999",
            occurredAt: updatedOccurredAt,
            number: 999
        )

        store.addEvents([storedEvent])
        store.repairEvents(using: [canonicalEvent])

        XCTAssertEqual(store.events.count, 1)
        XCTAssertEqual(store.events[0].id, eventId)
        XCTAssertEqual(store.events[0].title, "Updated PR title")
        XCTAssertEqual(store.events[0].occurredAt, updatedOccurredAt)
        XCTAssertEqual(store.events[0].number, 999)
        XCTAssertTrue(store.events[0].isRead)
    }

    @MainActor
    private func makeIsolatedStore() throws -> (MonitorStore, () -> Void) {
        let suiteName = "MonitorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = MonitorStore(defaults: defaults)
        return (store, {
            defaults.removePersistentDomain(forName: suiteName)
        })
    }

    private func decodeGitHubEvent(_ json: String) throws -> GitHubEvent {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GitHubEvent.self, from: Data(json.utf8))
    }

    private func makeMonitorEvent(
        id: String,
        kind: String,
        targetId: UUID,
        actor: String = "developer",
        repo: String = "org/repo",
        title: String = "Pushed commit",
        url: String = "https://github.com/org/repo/commit/1",
        occurredAt: Date = Date(),
        number: Int? = nil,
        isRead: Bool = false
    ) -> MonitorEvent {
        MonitorEvent(
            id: id,
            kind: kind,
            targetId: targetId,
            actor: actor,
            repo: repo,
            title: title,
            url: url,
            occurredAt: occurredAt,
            number: number,
            isRead: isRead
        )
    }

    private func makeGitHubEvent(id: String, occurredAt: Date) -> GitHubEvent {
        GitHubEvent(
            id: id,
            type: "PushEvent",
            actor: .init(login: "octocat"),
            repo: .init(name: "owner/repo"),
            createdAt: occurredAt,
            payload: nil
        )
    }

    private struct StubMonitorSource: MonitorSource {
        let events: [MonitorEvent]
        let fetchedEvents: [MonitorEvent]
        let nextCursor: String?

        @MainActor
        func fetchEvents(
            definition _: MonitorDefinition,
            cursor _: String?,
            session _: GitHubSession
        ) async throws -> (events: [MonitorEvent], fetchedEvents: [MonitorEvent], nextCursor: String?) {
            (events, fetchedEvents, nextCursor)
        }
    }
}

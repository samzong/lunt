import Foundation
@testable import LuntCore
import XCTest

final class WatchAlertMigrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MigrationMockURLProtocol.reset()
    }

    override func tearDown() {
        MigrationMockURLProtocol.reset()
        super.tearDown()
    }

    @MainActor
    func testLegacyMonitorsMigrationIsIdempotentAndRewritesEvents() throws {
        let suite = "WatchAlertMigrationTests.Migrate.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let accountId = UUID()
        let repoId = UUID()
        let searchId = UUID()
        let codeId = UUID()

        let monitorsJSON = """
        [
          {"id":"\(accountId.uuidString)","target":{"account":{"login":"samzong"}},"isEnabled":true,"eventToggles":{}},
          {"id":"\(repoId.uuidString)","target":{"repository":{"owner":"apple","name":"swift"}},"isEnabled":true,"eventToggles":{}},
          {"id":"\(searchId.uuidString)","target":{"search":{"query":"is:pr is:open author:samzong","name":"Sam PRs"}},"name":"Custom Search Watch","isEnabled":true,"eventToggles":{}},
          {"id":"\(codeId.uuidString)","target":{"code":{"query":"SECRET_KEY","name":"Secret Watch"}},"isEnabled":true,"eventToggles":{}}
        ]
        """

        let eventsJSON = """
        [
          {"id":"acc-1","kind":"commit","targetId":"\(accountId.uuidString)","actor":"samzong","repo":"samzong/lunt","title":"Commit","url":"https://github.com/samzong/lunt/commit/abc","occurredAt":1000,"isRead":false},
          {"id":"srch-1","kind":"pr","targetId":"\(searchId.uuidString)","actor":"octocat","repo":"samzong/lunt","title":"Legacy PR","url":"https://github.com/samzong/lunt/pull/123","occurredAt":2000,"isRead":true},
          {"id":"code-1","kind":"code_match","targetId":"\(codeId.uuidString)","actor":"","repo":"samzong/lunt","title":"Code Match","url":"https://github.com/samzong/lunt/blob/main/a.swift","occurredAt":3000,"isRead":false}
        ]
        """

        defaults.set(Data(monitorsJSON.utf8), forKey: "monitor_definitions")
        defaults.set(Data(eventsJSON.utf8), forKey: "monitor_events")

        let store = MonitorStore(defaults: defaults)
        XCTAssertEqual(store.monitors.count, 2)
        XCTAssertEqual(Set(store.monitors.map(\.id)), [accountId, repoId])

        let searchService = SearchService(session: GitHubSession(), defaults: defaults, storageKey: "savedSearches")
        store.migrateLegacyMonitors(into: searchService)

        XCTAssertEqual(searchService.savedSearches.count, 1)
        let migratedSearch = try XCTUnwrap(searchService.savedSearches.first)
        XCTAssertEqual(migratedSearch.name, "Custom Search Watch")
        XCTAssertEqual(migratedSearch.query, "is:pr is:open author:samzong")
        XCTAssertEqual(migratedSearch.watchAlerts, true)
        XCTAssertEqual(migratedSearch.isEnabled, true)

        XCTAssertEqual(store.events.count, 2)
        let migratedEvent = try XCTUnwrap(store.events.first(where: { $0.id == "srch-1" }))
        XCTAssertEqual(migratedEvent.targetId, migratedSearch.id)
        XCTAssertEqual(migratedEvent.number, 123)
        XCTAssertTrue(migratedEvent.isRead)
        XCTAssertNil(store.events.first(where: { $0.id == "code-1" }))

        store.migrateLegacyMonitors(into: searchService)
        XCTAssertEqual(searchService.savedSearches.count, 1)
        XCTAssertEqual(store.events.count, 2)

        let reloadedStore = MonitorStore(defaults: defaults)
        reloadedStore.migrateLegacyMonitors(into: searchService)
        XCTAssertEqual(searchService.savedSearches.count, 1)
        XCTAssertEqual(reloadedStore.monitors.count, 2)
    }

    @MainActor
    func testTolerantSavedSearchDecodingDropsLegacyRepositoryEntries() throws {
        let suite = "WatchAlertMigrationTests.Tolerant.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let prId = UUID()
        let repoId = UUID()
        let issueId = UUID()
        let json = """
        [
          {"id":"\(prId.uuidString)","name":"PRs","query":"is:open","isEnabled":true,"isPinned":false,"type":"pr","createdAt":0},
          {"id":"\(repoId.uuidString)","name":"Repos","query":"language:swift","isEnabled":true,"isPinned":false,"type":"repository","createdAt":0},
          {"id":"\(issueId.uuidString)","name":"Issues","query":"is:open","isEnabled":true,"isPinned":false,"type":"issue","createdAt":0}
        ]
        """
        defaults.set(Data(json.utf8), forKey: "savedSearches")

        let service = SearchService(session: GitHubSession(), defaults: defaults, storageKey: "savedSearches")
        XCTAssertEqual(service.savedSearches.map(\.id), [prId, issueId])
        XCTAssertEqual(service.savedSearches.map(\.type), [.pr, .issue])
    }

    @MainActor
    func testSearchServiceWatchAlertLifecycle() async throws {
        let suite = "WatchAlertMigrationTests.Watch.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let session = GitHubSession()
        session.configure(token: "test-token", urlSession: MigrationMockURLProtocol.makeSession())

        let store = MonitorStore(defaults: defaults)
        let service = SearchService(session: session, defaults: defaults, storageKey: "savedSearches")
        service.monitorStore = store

        service.addSearch(name: "Lunt PRs", query: "repo:samzong/lunt", type: .pr, watchAlerts: true)
        let search = try XCTUnwrap(service.savedSearches.first)

        let syncPhase = MigrationLockBox(1)
        let capturedQuery = MigrationLockBox<String?>(nil)

        MigrationMockURLProtocol.setHandler { request in
            if let data = request.bodyData,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let vars = obj["variables"] as? [String: Any],
               let query = vars["query"] as? String {
                capturedQuery.value = query
            }

            let nodes: [(String, Int, String, String)] = if syncPhase.value == 1 {
                [("node-10", 10, "Baseline PR", "2026-05-20T10:00:00Z")]
            } else {
                [
                    ("node-10", 10, "Baseline PR", "2026-05-20T10:00:00Z"),
                    ("node-11", 11, "New Watch PR", "2026-05-20T11:00:00Z"),
                ]
            }
            let json = Self.searchGraphQLResponse(nodes: nodes)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        await service.fetchAll()
        XCTAssertEqual(capturedQuery.value, "repo:samzong/lunt is:pr")
        XCTAssertTrue(store.events.isEmpty)

        syncPhase.value = 2
        await service.fetchAll()
        XCTAssertEqual(store.events.count, 1)

        let event = try XCTUnwrap(store.events.first)
        XCTAssertEqual(event.id, "query:\(search.id.uuidString):node-11")
        XCTAssertEqual(event.targetId, search.id)
        XCTAssertEqual(event.actor, "query: Lunt PRs")
        XCTAssertEqual(event.number, 11)
        XCTAssertEqual(event.kind, "pr")
        XCTAssertEqual(event.repo, "samzong/lunt")
        XCTAssertEqual(event.title, "New Watch PR")

        service.deleteSearch(id: search.id)
        XCTAssertTrue(store.events.isEmpty)
    }

    @MainActor
    func testUpdatingWatchedSearchQueryResetsBaselineAndClearsStaleAlerts() async throws {
        let suite = "WatchAlertMigrationTests.QueryChange.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let session = GitHubSession()
        session.configure(token: "test-token", urlSession: MigrationMockURLProtocol.makeSession())

        let store = MonitorStore(defaults: defaults)
        let service = SearchService(session: session, defaults: defaults, storageKey: "savedSearches")
        service.monitorStore = store

        service.addSearch(name: "Watch PRs", query: "repo:samzong/lunt", type: .pr, watchAlerts: true)
        let search = try XCTUnwrap(service.savedSearches.first)

        MigrationMockURLProtocol.setHandler { request in
            let json = Self.searchGraphQLResponse(nodes: [("node-1", 1, "First", "2026-05-20T10:00:00Z")])
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        await service.fetchAll()

        MigrationMockURLProtocol.setHandler { request in
            let json = Self.searchGraphQLResponse(nodes: [("node-2", 2, "Second", "2026-05-20T11:00:00Z")])
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        await service.syncSearch(id: search.id)
        XCTAssertEqual(store.events.count, 1)

        service.updateSearch(id: search.id, options: .init(query: "repo:samzong/combe"))
        XCTAssertTrue(store.events.isEmpty)

        MigrationMockURLProtocol.setHandler { request in
            let json = Self.searchGraphQLResponse(nodes: [("node-99", 99, "Baseline Only", "2026-05-20T12:00:00Z")])
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        await service.syncSearch(id: search.id)
        XCTAssertTrue(store.events.isEmpty)
    }

    @MainActor
    func testSecurityHardeningURLValidationTargetParsingAndDuplicateUUIDStorage() throws {
        XCTAssertNil(URL.validatedGitHubWebURL(from: "file:///etc/passwd"))
        XCTAssertNil(URL.validatedGitHubWebURL(from: "vscode://file/tmp/a"))
        XCTAssertNil(URL.validatedGitHubWebURL(from: "https://github.com.evil.com/org/repo"))
        XCTAssertEqual(
            URL.validatedGitHubWebURL(from: "https://github.com/samzong/lunt/pull/48")?.absoluteString,
            "https://github.com/samzong/lunt/pull/48"
        )
        XCTAssertEqual(
            URL.validatedGitHubAPISubjectWebURL(from: "https://api.github.com/repos/samzong/lunt/pulls/48")?.absoluteString,
            "https://github.com/samzong/lunt/pull/48"
        )

        XCTAssertNil(MonitorTarget.parse(input: "https://github.com.evil.com/samzong/lunt", type: "repository"))
        XCTAssertNil(MonitorTarget.parse(input: "../etc/passwd", type: "account"))
        XCTAssertNil(MonitorTarget.parse(input: "samzong/../other", type: "repository"))
        XCTAssertEqual(
            MonitorTarget.parse(input: "https://github.com/samzong/lunt", type: "repository"),
            .repository(owner: "samzong", name: "lunt")
        )

        let suite = "WatchAlertMigrationTests.DupUUID.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let lower = UUID().uuidString.lowercased()
        let upper = lower.uppercased()
        defaults.set(Data(#"{"\#(lower)":"c1","\#(upper)":"c2"}"#.utf8), forKey: "monitor_cursors")
        defaults.set(Data(#"{"\#(lower)":100,"\#(upper)":200}"#.utf8), forKey: "monitor_last_synced_at")
        defaults.set(Data(#"{"\#(lower)":["n1"],"\#(upper)":["n2"]}"#.utf8), forKey: "savedSearches.knownMatchIds")

        let store = MonitorStore(defaults: defaults)
        let service = SearchService(session: GitHubSession(), defaults: defaults, storageKey: "savedSearches")
        XCTAssertEqual(store.cursors.count, 1)
        XCTAssertEqual(store.lastSyncedAt.count, 1)
        XCTAssertTrue(service.savedSearches.isEmpty)
    }

    private static func searchGraphQLResponse(nodes: [(String, Int, String, String)]) -> String {
        let items = nodes.map { id, number, title, updatedAt in
            #"{"__typename":"PullRequest","id":"\#(id)","number":\#(number),"title":"\#(title)","state":"OPEN","repository":{"owner":{"login":"samzong"},"name":"lunt"},"author":{"login":"samzong","avatarUrl":"https://example.com/a.png"},"updatedAt":"\#(updatedAt)"}"#
        }.joined(separator: ",")
        return #"{"data":{"search":{"nodes":[\#(items)]}}}"#
    }
}

private final class MigrationLockBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storage = newValue
        }
    }

    func update<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&storage)
    }
}

private final class MigrationMockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private struct State: @unchecked Sendable {
        var handler: Handler?
        var requests: [URLRequest] = []
    }

    private static let state = MigrationLockBox(State())

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MigrationMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func setHandler(_ handler: @escaping Handler) {
        state.update { $0.handler = handler }
    }

    static func reset() {
        state.value = State()
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let handler = Self.state.update { current -> Handler? in
            current.requests.append(request)
            return current.handler
        }

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension URLRequest {
    fileprivate var bodyData: Data? {
        if let httpBody {
            return httpBody
        }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}

import Foundation
@testable import LuntCore
import XCTest

final class CoreServicesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testGitHubAPIErrorMapping() async {
        let api = GitHubAPI(token: "test-token", session: MockURLProtocol.makeSession())
        let reset = Int(Date().addingTimeInterval(300).timeIntervalSince1970)

        let hdr403Limit = ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "\(reset)"]
        let hdr403OK = ["X-RateLimit-Remaining": "4999", "X-RateLimit-Reset": "\(reset)"]

        await checkAPIError(api, status: 401) { error in
            guard case .unauthorized = error else { return XCTFail("Expected unauthorized, got \(error)") }
        }
        await checkAPIError(api, status: 403, headers: hdr403Limit) { error in
            guard case let .rateLimited(resetTime) = error else { return XCTFail("Expected rateLimited, got \(error)") }
            XCTAssertNotNil(resetTime)
        }
        await checkAPIError(api, status: 403, headers: hdr403OK) { error in
            guard case .httpError(statusCode: 403) = error else { return XCTFail("Expected httpError(403), got \(error)") }
        }
        await checkAPIError(api, status: 429, headers: ["Retry-After": "120"]) { error in
            guard case let .rateLimited(resetTime) = error else { return XCTFail("Expected rateLimited, got \(error)") }
            XCTAssertNotNil(resetTime)
        }
        await checkAPIError(api, status: 429) { error in
            guard case let .rateLimited(resetTime) = error else { return XCTFail("Expected rateLimited, got \(error)") }
            XCTAssertNil(resetTime)
        }

        MockURLProtocol.respond(status: 200, body: "{invalid json")
        await assertThrows(DecodingError.self) {
            _ = try await api.fetchNotifications()
        }
    }

    func testGitHubGraphQLClientErrorMapping() async {
        let client = GitHubGraphQLClient(token: "test-token", session: MockURLProtocol.makeSession())
        let reset = Int(Date().addingTimeInterval(600).timeIntervalSince1970)
        let hdr403Limit = ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "\(reset)"]
        let hdr403OK = ["X-RateLimit-Remaining": "4999", "X-RateLimit-Reset": "\(reset)"]

        await checkGraphQLError(client, status: 401) { error in
            XCTAssertEqual(error, .unauthorized)
            XCTAssertTrue(error.localizedDescription.contains("Unauthorized"))
        }
        await checkGraphQLError(client, status: 403, headers: hdr403Limit) { error in
            guard case let .rateLimited(resetTime) = error else { return XCTFail("Expected rateLimited, got \(error)") }
            XCTAssertNotNil(resetTime)
            XCTAssertTrue(error.localizedDescription.contains("rate limit"))
        }
        await checkGraphQLError(client, status: 403, headers: hdr403OK) { error in
            XCTAssertEqual(error, .httpError(statusCode: 403))
        }
        await checkGraphQLError(client, status: 429, headers: ["Retry-After": "90"]) { error in
            guard case let .rateLimited(resetTime) = error else { return XCTFail("Expected rateLimited, got \(error)") }
            XCTAssertNotNil(resetTime)
        }
        await checkGraphQLError(client, status: 429) { error in
            XCTAssertEqual(error, .rateLimited(resetTime: nil))
        }
        await checkGraphQLError(
            client,
            status: 200,
            body: #"{"data":null,"errors":[{"message":"API rate limit exceeded in GraphQL"}]}"#
        ) { error in
            XCTAssertEqual(error, .graphQLErrors(["API rate limit exceeded in GraphQL"]))
            XCTAssertTrue(error.localizedDescription.contains("API rate limit exceeded in GraphQL"))
        }

        MockURLProtocol.respond(status: 200, body: "not-json")
        await assertThrows(DecodingError.self) {
            _ = try await client.fetchViewer()
        }
    }

    private func checkAPIError(
        _ api: GitHubAPI,
        status: Int,
        headers: [String: String]? = nil,
        verify: (APIError) -> Void
    ) async {
        MockURLProtocol.respond(status: status, headers: headers)
        await assertThrows(APIError.self, operation: { _ = try await api.fetchNotifications() }, verify: verify)
    }

    private func checkGraphQLError(
        _ client: GitHubGraphQLClient,
        status: Int,
        headers: [String: String]? = nil,
        body: String = "",
        verify: (GraphQLError) -> Void
    ) async {
        MockURLProtocol.respond(status: status, headers: headers, body: body)
        await assertThrows(GraphQLError.self, operation: { _ = try await client.search(query: "is:open") }, verify: verify)
    }

    @MainActor
    private func makeIsolatedDefaults(prefix: String) throws -> (UserDefaults, () -> Void) {
        let suite = "\(prefix).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    @MainActor
    func testSearchServiceCRUDAndLegacyDecoding() throws {
        let (defaults, cleanup) = try makeIsolatedDefaults(prefix: "CoreServicesTests.Search")
        defer { cleanup() }

        let legacyId = UUID()
        let legacyJSON = #"[{"id":"\#(legacyId.uuidString)","name":"Legacy","query":"is:open","isEnabled":true,"isPinned":true,"type":"pr","createdAt":0}]"#
        defaults.set(Data(legacyJSON.utf8), forKey: "savedSearches")

        let service = SearchService(session: GitHubSession(), defaults: defaults, storageKey: "savedSearches")
        XCTAssertEqual(service.savedSearches.count, 1)
        XCTAssertEqual(service.savedSearches.first?.id, legacyId)
        XCTAssertEqual(service.savedSearches.first?.watchAlerts, false)

        service.addSearch(name: "Bugs", query: "is:issue is:open", type: .issue, isPinned: true, watchAlerts: true)
        let added = try XCTUnwrap(service.savedSearches.last)
        XCTAssertEqual(service.savedSearches.count, 2)
        XCTAssertEqual(added.watchAlerts, true)

        service.updateSearch(id: added.id, options: SearchService.UpdateOptions(name: "Critical Bugs", watchAlerts: false))
        XCTAssertEqual(service.savedSearches.last?.name, "Critical Bugs")
        XCTAssertEqual(service.savedSearches.last?.watchAlerts, false)

        service.toggleSearch(id: added.id)
        XCTAssertEqual(service.savedSearches.last?.isEnabled, false)

        service.deleteSearch(id: legacyId)
        XCTAssertEqual(service.savedSearches.map(\.id), [added.id])
    }

    private static func jsonResponse(_ url: URL, _ body: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
    }

    @MainActor
    func testSearchServiceDeduplicationDisabledFilteringAndPerSearchErrors() async throws {
        let (defaults, cleanup) = try makeIsolatedDefaults(prefix: "CoreServicesTests.SearchFetch")
        defer { cleanup() }

        let session = GitHubSession()
        session.configure(token: "test-token", urlSession: MockURLProtocol.makeSession())

        let service = SearchService(session: session, defaults: defaults, storageKey: "savedSearches")
        service.addSearch(name: "First", query: "query-one", type: .pr)
        service.addSearch(name: "Second", query: "query-two", type: .pr)
        service.addSearch(name: "Disabled", query: "query-disabled", type: .pr)

        let firstId = service.savedSearches[0].id
        let secondId = service.savedSearches[1].id
        let disabledId = service.savedSearches[2].id
        service.toggleSearch(id: disabledId)

        let failFirstSearch = LockBox(false)

        MockURLProtocol.setHandler { request in
            let body = request.bodyString ?? ""
            let url = request.url!

            if body.contains("query-one") {
                if failFirstSearch.value {
                    return (HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
                }
                return Self.jsonResponse(url, Self.searchGraphQLResponse(nodes: [
                    ("item-shared", 1, "Shared PR", "2026-05-20T10:00:00Z"),
                    ("item-one", 2, "First Only", "2026-05-20T09:00:00Z"),
                ]))
            }

            if body.contains("query-two") {
                return Self.jsonResponse(url, Self.searchGraphQLResponse(nodes: [
                    ("item-shared", 1, "Shared PR", "2026-05-20T10:00:00Z"),
                    ("item-two", 3, "Second Only", "2026-05-20T11:00:00Z"),
                ]))
            }

            XCTFail("Disabled search should not be fetched")
            return (HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!, Data())
        }

        await service.fetchAll()

        XCTAssertNotNil(service.lastSyncedAt)
        XCTAssertNil(service.errorMessage)
        XCTAssertTrue(service.errorsBySearchId.isEmpty)
        XCTAssertEqual(Set(service.items.map(\.id)), ["item-shared", "item-one", "item-two"])
        XCTAssertEqual(service.items.count, 3)
        XCTAssertEqual(service.items.first?.id, "item-two")
        XCTAssertNil(service.resultsBySearchId[disabledId])

        failFirstSearch.value = true
        await service.fetchAll()

        XCTAssertNotNil(service.errorsBySearchId[firstId])
        XCTAssertNil(service.errorsBySearchId[secondId])
        XCTAssertEqual(service.resultsBySearchId[firstId]?.count, 2)
        XCTAssertEqual(Set(service.items.map(\.id)), ["item-shared", "item-one", "item-two"])
        XCTAssertNil(service.errorMessage)

        service.deleteSearch(id: firstId)
        XCTAssertNil(service.errorsBySearchId[firstId])
    }

    @MainActor
    func testNotificationServiceStartupCoalescingAndRules() async throws {
        let rulesKey = "notificationRules"
        let savedRules = UserDefaults.standard.data(forKey: rulesKey)
        UserDefaults.standard.removeObject(forKey: rulesKey)
        defer {
            if let savedRules {
                UserDefaults.standard.set(savedRules, forKey: rulesKey)
            } else {
                UserDefaults.standard.removeObject(forKey: rulesKey)
            }
        }

        let session = GitHubSession()
        session.configure(token: "test-token", urlSession: MockURLProtocol.makeSession())

        let baselineJSON = Self.notificationsJSON([("notif-1", "octo/repo", "Baseline PR", "PullRequest", "mention")])
        MockURLProtocol.respond(status: 200, body: baselineJSON, delay: 0.05)

        let service = NotificationService(session: session)
        service.configure()

        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 0)

        async let first: Void = service.fetchNotifications()
        async let second: Void = service.fetchNotifications()
        _ = await (first, second)

        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 1)
        XCTAssertNotNil(service.lastSyncedAt)
        XCTAssertEqual(service.notifications.map(\.id), ["notif-1"])

        let ruleStorage = RuleStorage()
        ruleStorage.addRule(.init(
            name: "Auto Read Bot Repo",
            priority: 0,
            conditions: [.init(field: .repository, operator: .equals, value: "bot/noisy")],
            actions: [.init(type: .markAsRead)]
        ))
        ruleStorage.addRule(.init(
            name: "Mute Muted Repo",
            priority: 1,
            conditions: [.init(field: .repository, operator: .equals, value: "org/muted")],
            actions: [.init(type: .suppressSystemNotification)]
        ))
        service.ruleStorage = ruleStorage

        MockURLProtocol.resetRequests()
        MockURLProtocol.respond(status: 200, body: baselineJSON)
        await service.fetchNotifications(isAutoRefresh: true)
        XCTAssertEqual(service.notifications.map(\.id), ["notif-1"])

        MockURLProtocol.resetRequests()
        let updatedJSON = Self.notificationsJSON([
            ("notif-1", "octo/repo", "Baseline PR", "PullRequest", "mention"),
            ("notif-read", "bot/noisy", "Noisy CI", "Issue", "subscribed"),
            ("notif-muted", "org/muted", "Muted Issue", "Issue", "mention"),
        ])
        MockURLProtocol.setHandler { request in
            if request.httpMethod == "PATCH" {
                return Self.jsonResponse(request.url!, "")
            }
            return Self.jsonResponse(request.url!, updatedJSON)
        }

        await service.fetchNotifications(isAutoRefresh: true)

        let patchRequests = MockURLProtocol.recordedRequests.filter { $0.httpMethod == "PATCH" }
        XCTAssertEqual(patchRequests.count, 1)
        XCTAssertEqual(patchRequests.first?.url?.path, "/notifications/threads/notif-read")
        XCTAssertEqual(Set(service.notifications.map(\.id)), ["notif-1", "notif-muted"])
    }

    private func assertThrows<E: Error>(
        _ type: E.Type,
        operation: () async throws -> Void,
        verify: (E) -> Void = { _ in }
    ) async {
        do {
            try await operation()
            XCTFail("Expected error of type \(type)")
        } catch let error as E {
            verify(error)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static func searchGraphQLResponse(nodes: [(String, Int, String, String)]) -> String {
        let items = nodes.map { id, number, title, updatedAt in
            #"{"__typename":"PullRequest","id":"\#(id)","number":\#(number),"title":"\#(title)","state":"OPEN","repository":{"owner":{"login":"samzong"},"name":"lunt"},"author":{"login":"samzong","avatarUrl":"https://example.com/a.png"},"updatedAt":"\#(updatedAt)"}"#
        }.joined(separator: ",")
        return #"{"data":{"search":{"nodes":[\#(items)]}}}"#
    }

    private static func notificationsJSON(_ items: [(String, String, String, String, String)]) -> String {
        let rows = items.map { id, repo, title, type, reason in
            let parts = repo.split(separator: "/")
            return #"{"id":"\#(id)","unread":true,"reason":"\#(reason)","updated_at":"2026-05-20T12:00:00Z","last_read_at":null,"subject":{"title":"\#(title)","url":null,"latest_comment_url":null,"type":"\#(type)"},"repository":{"id":1,"name":"\#(parts.last ?? "repo")","full_name":"\#(repo)","html_url":"https://github.com/\#(repo)","owner":{"login":"\#(parts.first ?? "owner")"}},"url":"https://api.github.com/notifications/threads/\#(id)"}"#
        }.joined(separator: ",")
        return "[\(rows)]"
    }
}

private final class LockBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value
    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }

    func update<T>(_ body: (inout Value) -> T) -> T {
        lock.withLock { body(&storage) }
    }
}

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    private struct State: @unchecked Sendable {
        var handler: Handler?
        var delay: TimeInterval = 0
        var requests: [URLRequest] = []
    }

    private static let state = LockBox(State())
    static var recordedRequests: [URLRequest] {
        state.value.requests
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func respond(status: Int, headers: [String: String]? = nil, body: String = "", delay: TimeInterval = 0) {
        let data = Data(body.utf8)
        setHandler(delay: delay) { req in
            (HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, data)
        }
    }

    static func setHandler(delay: TimeInterval = 0, _ handler: @escaping Handler) {
        state.update { $0.handler = handler
            $0.delay = delay
        }
    }

    static func resetRequests() {
        state.update { $0.requests = [] }
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
        let (handler, delay) = Self.state.update { current -> (Handler?, TimeInterval) in
            current.requests.append(request)
            return (current.handler, current.delay)
        }
        let deliver: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            guard let handler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            do {
                let (res, data) = try handler(request)
                client?.urlProtocol(self, didReceive: res, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
        if delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: deliver)
        } else {
            deliver()
        }
    }

    override func stopLoading() {}
}

extension URLRequest {
    fileprivate var bodyString: String? {
        if let httpBody {
            return String(data: httpBody, encoding: .utf8)
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
        return String(data: data, encoding: .utf8)
    }
}

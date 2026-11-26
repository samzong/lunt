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
        let session = MockURLProtocol.makeSession()
        let api = GitHubAPI(token: "test-token", session: session)

        MockURLProtocol.respond(status: 401)
        await assertThrows(APIError.self) {
            _ = try await api.fetchNotifications()
        } verify: { error in
            guard case .unauthorized = error else { return XCTFail("Expected unauthorized, got \(error)") }
        }

        let reset = Int(Date().addingTimeInterval(300).timeIntervalSince1970)
        MockURLProtocol.respond(status: 403, headers: ["X-RateLimit-Reset": "\(reset)"])
        await assertThrows(APIError.self) {
            _ = try await api.fetchNotifications()
        } verify: { error in
            guard case let .rateLimited(resetTime) = error else { return XCTFail("Expected rateLimited, got \(error)") }
            XCTAssertNotNil(resetTime)
        }

        MockURLProtocol.respond(status: 429, headers: ["X-RateLimit-Remaining": "0"])
        await assertThrows(APIError.self) {
            _ = try await api.fetchNotifications()
        } verify: { error in
            guard case let .rateLimited(resetTime) = error else { return XCTFail("Expected rateLimited, got \(error)") }
            XCTAssertNil(resetTime)
        }

        MockURLProtocol.respond(status: 200, body: "{invalid json")
        await assertThrows(DecodingError.self) {
            _ = try await api.fetchNotifications()
        }
    }

    func testGitHubGraphQLClientErrorMapping() async {
        let session = MockURLProtocol.makeSession()
        let client = GitHubGraphQLClient(token: "test-token", session: session)

        MockURLProtocol.respond(status: 401)
        await assertThrows(GraphQLError.self) {
            _ = try await client.fetchViewer()
        } verify: { error in
            XCTAssertEqual(error, .unauthorized)
            XCTAssertTrue(error.localizedDescription.contains("Unauthorized"))
        }

        let reset = Int(Date().addingTimeInterval(600).timeIntervalSince1970)
        MockURLProtocol.respond(status: 403, headers: ["X-RateLimit-Reset": "\(reset)"])
        await assertThrows(GraphQLError.self) {
            _ = try await client.search(query: "is:open")
        } verify: { error in
            guard case let .rateLimited(resetTime) = error else { return XCTFail("Expected rateLimited, got \(error)") }
            XCTAssertNotNil(resetTime)
            XCTAssertTrue(error.localizedDescription.contains("rate limit"))
        }

        MockURLProtocol.respond(status: 429, headers: ["X-RateLimit-Remaining": "0"])
        await assertThrows(GraphQLError.self) {
            _ = try await client.search(query: "is:open")
        } verify: { error in
            XCTAssertEqual(error, .rateLimited(resetTime: nil))
        }

        MockURLProtocol.respond(
            status: 200,
            body: #"{"data":null,"errors":[{"message":"API rate limit exceeded in GraphQL"}]}"#
        )
        await assertThrows(GraphQLError.self) {
            _ = try await client.fetchViewer()
        } verify: { error in
            XCTAssertEqual(error, .graphQLErrors(["API rate limit exceeded in GraphQL"]))
            XCTAssertTrue(error.localizedDescription.contains("API rate limit exceeded in GraphQL"))
        }

        MockURLProtocol.respond(status: 200, body: "not-json")
        await assertThrows(DecodingError.self) {
            _ = try await client.fetchViewer()
        }
    }

    @MainActor
    func testSearchServiceCRUDAndLegacyDecoding() throws {
        let suite = "CoreServicesTests.Search.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

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

    @MainActor
    func testSearchServiceDeduplicationDisabledFilteringAndPerSearchErrors() async throws {
        let suite = "CoreServicesTests.SearchFetch.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

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
                let json = Self.searchGraphQLResponse(nodes: [
                    ("item-shared", 1, "Shared PR", "2026-05-20T10:00:00Z"),
                    ("item-one", 2, "First Only", "2026-05-20T09:00:00Z"),
                ])
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
            }

            if body.contains("query-two") {
                let json = Self.searchGraphQLResponse(nodes: [
                    ("item-shared", 1, "Shared PR", "2026-05-20T10:00:00Z"),
                    ("item-two", 3, "Second Only", "2026-05-20T11:00:00Z"),
                ])
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
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
        ruleStorage.addRule(NotificationRule(
            name: "Auto Read Bot Repo",
            priority: 0,
            conditions: [RuleCondition(field: .repository, operator: .equals, value: "bot/noisy")],
            actions: [RuleAction(type: .markAsRead)]
        ))
        ruleStorage.addRule(NotificationRule(
            name: "Mute Muted Repo",
            priority: 1,
            conditions: [RuleCondition(field: .repository, operator: .equals, value: "org/muted")],
            actions: [RuleAction(type: .suppressSystemNotification)]
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
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.httpMethod == "PATCH" {
                return (response, Data())
            }
            return (response, Data(updatedJSON.utf8))
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
            let owner = String(parts.first ?? "owner")
            let name = String(parts.last ?? "repo")
            return #"{"id":"\#(id)","unread":true,"reason":"\#(reason)","updated_at":"2026-05-20T12:00:00Z","last_read_at":null,"subject":{"title":"\#(title)","url":null,"latest_comment_url":null,"type":"\#(type)"},"repository":{"id":1,"name":"\#(name)","full_name":"\#(repo)","html_url":"https://github.com/\#(repo)","owner":{"login":"\#(owner)"}},"url":"https://api.github.com/notifications/threads/\#(id)"}"#
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
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private struct State: @unchecked Sendable {
        var handler: Handler?
        var delay: TimeInterval = 0
        var requests: [URLRequest] = []
    }

    private static let lock = NSLock()
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
        setHandler(delay: delay) { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            return (response, data)
        }
    }

    static func setHandler(delay: TimeInterval = 0, _ handler: @escaping Handler) {
        lock.lock()
        defer { lock.unlock() }
        var current = state.value
        current.handler = handler
        current.delay = delay
        state.value = current
    }

    static func resetRequests() {
        lock.lock()
        defer { lock.unlock() }
        var current = state.value
        current.requests = []
        state.value = current
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        state.value = State()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        var current = Self.state.value
        current.requests.append(request)
        let handler = current.handler
        let delay = current.delay
        Self.state.value = current
        Self.lock.unlock()

        let deliver: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
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

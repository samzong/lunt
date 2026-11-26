@testable import LuntCore
import XCTest

final class RuleEngineTests: XCTestCase {
    private let engine = RuleEngine()

    func testEqualsAndNotEqualsAcrossAllFieldsCaseInsensitive() {
        let notification = makeNotification(
            owner: "Kubernetes",
            repo: "Minikube",
            type: "PullRequest",
            reason: "review_requested"
        )

        let repositoryMatch = makeRule(
            name: "Repo equals",
            conditions: [
                RuleCondition(field: .repository, operator: .equals, value: "KUBERNETES/minikube"),
            ]
        )
        XCTAssertEqual(engine.evaluate(notification: notification, rules: [repositoryMatch]).matchedRule?.id, repositoryMatch.id)

        let repositoryNotEqualsMatch = makeRule(
            name: "Repo not equals",
            conditions: [
                RuleCondition(field: .repository, operator: .notEquals, value: "apple/swift"),
            ]
        )
        XCTAssertEqual(
            engine.evaluate(notification: notification, rules: [repositoryNotEqualsMatch]).matchedRule?.id,
            repositoryNotEqualsMatch.id
        )

        let repositoryNotEqualsMiss = makeRule(
            name: "Repo not equals miss",
            conditions: [
                RuleCondition(field: .repository, operator: .notEquals, value: "kubernetes/MINIKUBE"),
            ]
        )
        XCTAssertNil(engine.evaluate(notification: notification, rules: [repositoryNotEqualsMiss]).matchedRule)

        let orgMatch = makeRule(
            name: "Org equals",
            conditions: [
                RuleCondition(field: .organization, operator: .equals, value: "kubernetes"),
            ]
        )
        XCTAssertEqual(engine.evaluate(notification: notification, rules: [orgMatch]).matchedRule?.id, orgMatch.id)

        let orgNotEqualsMatch = makeRule(
            name: "Org not equals",
            conditions: [
                RuleCondition(field: .organization, operator: .notEquals, value: "apple"),
            ]
        )
        XCTAssertEqual(engine.evaluate(notification: notification, rules: [orgNotEqualsMatch]).matchedRule?.id, orgNotEqualsMatch.id)

        let typeMatch = makeRule(
            name: "Type equals",
            conditions: [
                RuleCondition(field: .notificationType, operator: .equals, value: "pullrequest"),
            ]
        )
        XCTAssertEqual(engine.evaluate(notification: notification, rules: [typeMatch]).matchedRule?.id, typeMatch.id)

        let typeNotEqualsMatch = makeRule(
            name: "Type not equals",
            conditions: [
                RuleCondition(field: .notificationType, operator: .notEquals, value: "Issue"),
            ]
        )
        XCTAssertEqual(engine.evaluate(notification: notification, rules: [typeNotEqualsMatch]).matchedRule?.id, typeNotEqualsMatch.id)

        let reasonMatch = makeRule(
            name: "Reason equals",
            conditions: [
                RuleCondition(field: .reason, operator: .equals, value: "REVIEW_REQUESTED"),
            ]
        )
        XCTAssertEqual(engine.evaluate(notification: notification, rules: [reasonMatch]).matchedRule?.id, reasonMatch.id)

        let reasonNotEqualsMatch = makeRule(
            name: "Reason not equals",
            conditions: [
                RuleCondition(field: .reason, operator: .notEquals, value: "mention"),
            ]
        )
        XCTAssertEqual(engine.evaluate(notification: notification, rules: [reasonNotEqualsMatch]).matchedRule?.id, reasonNotEqualsMatch.id)
    }

    func testWildcardPatterns() {
        let notification = makeNotification(
            owner: "samzong",
            repo: "lunt-desktop-app",
            type: "Issue",
            reason: "subscribed"
        )

        let starRule = makeRule(
            name: "Universal",
            conditions: [RuleCondition(field: .repository, operator: .matches, value: "*")]
        )
        XCTAssertEqual(engine.evaluate(notification: notification, rules: [starRule]).matchedRule?.id, starRule.id)

        let prefixRule = makeRule(
            name: "Prefix",
            conditions: [RuleCondition(field: .repository, operator: .matches, value: "SAMZONG/*")]
        )
        XCTAssertEqual(engine.evaluate(notification: notification, rules: [prefixRule]).matchedRule?.id, prefixRule.id)

        let suffixRule = makeRule(
            name: "Suffix",
            conditions: [RuleCondition(field: .repository, operator: .matches, value: "*-app")]
        )
        XCTAssertEqual(engine.evaluate(notification: notification, rules: [suffixRule]).matchedRule?.id, suffixRule.id)

        let containsRule = makeRule(
            name: "Contains",
            conditions: [RuleCondition(field: .repository, operator: .matches, value: "*desktop*")]
        )
        XCTAssertEqual(engine.evaluate(notification: notification, rules: [containsRule]).matchedRule?.id, containsRule.id)

        let multiPartRule = makeRule(
            name: "Multi-part",
            conditions: [RuleCondition(field: .repository, operator: .matches, value: "sam*lunt*app")]
        )
        XCTAssertEqual(engine.evaluate(notification: notification, rules: [multiPartRule]).matchedRule?.id, multiPartRule.id)

        let nonMatchingRule = makeRule(
            name: "Non-matching",
            conditions: [RuleCondition(field: .repository, operator: .matches, value: "sam*other*app")]
        )
        XCTAssertNil(engine.evaluate(notification: notification, rules: [nonMatchingRule]).matchedRule)
    }

    func testAndVsAnyLogicOperators() {
        let notification = makeNotification(
            owner: "apple",
            repo: "swift",
            type: "PullRequest",
            reason: "ci_activity"
        )

        let failingAndRule = makeRule(
            name: "Failing AND",
            conditions: [
                RuleCondition(field: .organization, operator: .equals, value: "apple"),
                RuleCondition(field: .reason, operator: .equals, value: "mention"),
            ],
            logicOperator: .and
        )
        XCTAssertNil(engine.evaluate(notification: notification, rules: [failingAndRule]).matchedRule)

        let passingAndRule = makeRule(
            name: "Passing AND",
            conditions: [
                RuleCondition(field: .organization, operator: .equals, value: "apple"),
                RuleCondition(field: .reason, operator: .equals, value: "ci_activity"),
            ],
            logicOperator: .and
        )
        XCTAssertEqual(engine.evaluate(notification: notification, rules: [passingAndRule]).matchedRule?.id, passingAndRule.id)

        let passingAnyRule = makeRule(
            name: "Passing ANY",
            conditions: [
                RuleCondition(field: .organization, operator: .equals, value: "google"),
                RuleCondition(field: .reason, operator: .equals, value: "ci_activity"),
            ],
            logicOperator: .any
        )
        XCTAssertEqual(engine.evaluate(notification: notification, rules: [passingAnyRule]).matchedRule?.id, passingAnyRule.id)

        let failingAnyRule = makeRule(
            name: "Failing ANY",
            conditions: [
                RuleCondition(field: .organization, operator: .equals, value: "google"),
                RuleCondition(field: .reason, operator: .equals, value: "mention"),
            ],
            logicOperator: .any
        )
        XCTAssertNil(engine.evaluate(notification: notification, rules: [failingAnyRule]).matchedRule)
    }

    func testPriorityOrderingAndFirstMatchStopsEvaluation() {
        let notification = makeNotification(
            owner: "org",
            repo: "service",
            type: "Issue",
            reason: "subscribed"
        )

        let lowerPriorityNumber = makeRule(
            name: "High precedence",
            priority: 0,
            conditions: [RuleCondition(field: .organization, operator: .equals, value: "org")],
            actions: [RuleAction(type: .suppressSystemNotification)]
        )
        let higherPriorityNumber = makeRule(
            name: "Low precedence",
            priority: 5,
            conditions: [RuleCondition(field: .organization, operator: .equals, value: "org")],
            actions: [RuleAction(type: .markAsRead)]
        )

        let result = engine.evaluate(notification: notification, rules: [higherPriorityNumber, lowerPriorityNumber])
        XCTAssertEqual(result.matchedRule?.id, lowerPriorityNumber.id)
        XCTAssertFalse(result.shouldMarkAsRead)
        XCTAssertTrue(result.shouldSuppressNotification)
    }

    func testDisabledRulesAreSkipped() {
        let notification = makeNotification(
            owner: "org",
            repo: "service",
            type: "Issue",
            reason: "subscribed"
        )

        let disabledHighPriority = makeRule(
            name: "Disabled rule",
            isEnabled: false,
            priority: 0,
            conditions: [RuleCondition(field: .organization, operator: .equals, value: "org")],
            actions: [RuleAction(type: .markAsRead)]
        )
        let enabledFallback = makeRule(
            name: "Enabled fallback",
            isEnabled: true,
            priority: 1,
            conditions: [RuleCondition(field: .organization, operator: .equals, value: "org")],
            actions: [RuleAction(type: .suppressSystemNotification)]
        )

        let result = engine.evaluate(notification: notification, rules: [disabledHighPriority, enabledFallback])
        XCTAssertEqual(result.matchedRule?.id, enabledFallback.id)
        XCTAssertFalse(result.shouldMarkAsRead)
        XCTAssertTrue(result.shouldSuppressNotification)
    }

    func testActionsAndNoMatch() {
        let notification = makeNotification(
            owner: "org",
            repo: "repo",
            type: "Commit",
            reason: "author"
        )

        let markAsReadRule = makeRule(
            name: "Mark read",
            conditions: [RuleCondition(field: .reason, operator: .equals, value: "author")],
            actions: [RuleAction(type: .markAsRead)]
        )
        let markReadResult = engine.evaluate(notification: notification, rules: [markAsReadRule])
        XCTAssertEqual(markReadResult.matchedRule?.id, markAsReadRule.id)
        XCTAssertTrue(markReadResult.shouldMarkAsRead)
        XCTAssertFalse(markReadResult.shouldSuppressNotification)

        let suppressRule = makeRule(
            name: "Suppress",
            conditions: [RuleCondition(field: .reason, operator: .equals, value: "author")],
            actions: [RuleAction(type: .suppressSystemNotification)]
        )
        let suppressResult = engine.evaluate(notification: notification, rules: [suppressRule])
        XCTAssertEqual(suppressResult.matchedRule?.id, suppressRule.id)
        XCTAssertFalse(suppressResult.shouldMarkAsRead)
        XCTAssertTrue(suppressResult.shouldSuppressNotification)

        let combinedRule = makeRule(
            name: "Both actions",
            conditions: [RuleCondition(field: .reason, operator: .equals, value: "author")],
            actions: [RuleAction(type: .markAsRead), RuleAction(type: .suppressSystemNotification)]
        )
        let combinedResult = engine.evaluate(notification: notification, rules: [combinedRule])
        XCTAssertEqual(combinedResult.matchedRule?.id, combinedRule.id)
        XCTAssertTrue(combinedResult.shouldMarkAsRead)
        XCTAssertTrue(combinedResult.shouldSuppressNotification)

        let unmatchedRule = makeRule(
            name: "Unmatched",
            conditions: [RuleCondition(field: .reason, operator: .equals, value: "mention")],
            actions: [RuleAction(type: .markAsRead)]
        )
        let noMatchResult = engine.evaluate(notification: notification, rules: [unmatchedRule])
        XCTAssertNil(noMatchResult.matchedRule)
        XCTAssertFalse(noMatchResult.shouldMarkAsRead)
        XCTAssertFalse(noMatchResult.shouldSuppressNotification)
    }

    @MainActor
    func testRuleStorageCRUDReindexAndPersistence() throws {
        let suiteName = "RuleEngineTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storage = RuleStorage(defaults: defaults)
        XCTAssertTrue(storage.rules.isEmpty)

        var rule1 = makeRule(
            name: "First",
            priority: 0,
            conditions: [RuleCondition(field: .reason, operator: .equals, value: "subscribed")]
        )
        let rule2 = makeRule(
            name: "Second",
            priority: 1,
            conditions: [RuleCondition(field: .reason, operator: .equals, value: "ci_activity")]
        )
        let rule3 = makeRule(name: "Third", priority: 2, conditions: [RuleCondition(field: .reason, operator: .equals, value: "mention")])

        storage.addRule(rule1)
        storage.addRule(rule2)
        storage.addRule(rule3)
        XCTAssertEqual(storage.rules.map(\.name), ["First", "Second", "Third"])

        rule1.name = "First Updated"
        storage.updateRule(rule1)
        XCTAssertEqual(storage.rules.first(where: { $0.id == rule1.id })?.name, "First Updated")

        storage.toggleRule(rule2)
        XCTAssertFalse(storage.rules.first(where: { $0.id == rule2.id })?.isEnabled ?? true)

        storage.moveRule(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(storage.rules.map(\.id), [rule3.id, rule1.id, rule2.id])
        XCTAssertEqual(storage.rules.map(\.priority), [0, 1, 2])

        let reloadedStorage = RuleStorage(defaults: defaults)
        XCTAssertEqual(reloadedStorage.rules.map(\.id), [rule3.id, rule1.id, rule2.id])
        XCTAssertEqual(reloadedStorage.rules.map(\.name), ["Third", "First Updated", "Second"])
        XCTAssertEqual(reloadedStorage.rules.map(\.priority), [0, 1, 2])
        XCTAssertFalse(reloadedStorage.rules[2].isEnabled)

        reloadedStorage.deleteRule(rule1)
        XCTAssertEqual(reloadedStorage.rules.map(\.id), [rule3.id, rule2.id])

        let finalReload = RuleStorage(defaults: defaults)
        XCTAssertEqual(finalReload.rules.map(\.id), [rule3.id, rule2.id])
    }

    @MainActor
    func testApplyActiveRulesMarksMatchingNotificationsAndHandlesFailures() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let suiteName = "RuleEngineTests.Apply.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storage = RuleStorage(defaults: defaults)
        storage.addRule(
            makeRule(
                name: "Auto-read CI",
                isEnabled: true,
                conditions: [RuleCondition(field: .reason, operator: .equals, value: "ci_activity")],
                actions: [RuleAction(type: .markAsRead)]
            )
        )
        storage.addRule(
            makeRule(
                name: "Suppress Subscribed Only",
                isEnabled: true,
                conditions: [RuleCondition(field: .reason, operator: .equals, value: "subscribed")],
                actions: [RuleAction(type: .suppressSystemNotification)]
            )
        )
        storage.addRule(
            makeRule(
                name: "Disabled Mention Rule",
                isEnabled: false,
                conditions: [RuleCondition(field: .reason, operator: .equals, value: "mention")],
                actions: [RuleAction(type: .markAsRead)]
            )
        )

        let session = GitHubSession()
        session.configure(token: "test-token", urlSession: MockURLProtocol.makeSession())

        let service = NotificationService(session: session)
        service.ruleStorage = storage

        let ciSuccess = makeNotification(id: "notif-ci-1", owner: "acme", repo: "app", type: "PullRequest", reason: "ci_activity")
        let ciFailure = makeNotification(id: "notif-ci-fail", owner: "acme", repo: "app", type: "PullRequest", reason: "ci_activity")
        let subscribed = makeNotification(id: "notif-sub", owner: "acme", repo: "app", type: "Issue", reason: "subscribed")
        let mention = makeNotification(id: "notif-mention", owner: "acme", repo: "app", type: "Issue", reason: "mention")
        service.notifications = [ciSuccess, ciFailure, subscribed, mention]

        MockURLProtocol.setHandler { request in
            let url = try XCTUnwrap(request.url)
            if url.path.hasSuffix("/notif-ci-fail") {
                return (HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
            }
            return (HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }

        let summary = await service.applyActiveRules()
        XCTAssertEqual(summary.evaluatedCount, 4)
        XCTAssertEqual(summary.markedAsReadCount, 1)
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(service.notifications.map(\.id), ["notif-ci-fail", "notif-sub", "notif-mention"])
        XCTAssertNotNil(service.errorMessage)
        XCTAssertEqual(
            MockURLProtocol.recordedRequests.compactMap { $0.url?.lastPathComponent },
            ["notif-ci-1", "notif-ci-fail"]
        )
    }

    private func makeNotification(
        id: String = "notif_\(UUID().uuidString)",
        owner: String,
        repo: String,
        type: String,
        reason: String
    ) -> GitHubNotification {
        GitHubNotification(
            id: id,
            unread: true,
            reason: reason,
            updatedAt: Date(timeIntervalSince1970: 1_779_350_000),
            lastReadAt: nil,
            subject: GitHubNotification.Subject(
                title: "Test Subject",
                url: "https://api.github.com/repos/\(owner)/\(repo)/issues/1",
                latestCommentUrl: nil,
                type: type
            ),
            repository: GitHubNotification.Repository(
                id: 1,
                name: repo,
                fullName: "\(owner)/\(repo)",
                htmlUrl: "https://github.com/\(owner)/\(repo)",
                owner: GitHubNotification.Repository.Owner(login: owner)
            ),
            url: "https://api.github.com/notifications/threads/1"
        )
    }

    private func makeRule(
        name: String,
        isEnabled: Bool = true,
        priority: Int = 0,
        conditions: [RuleCondition],
        logicOperator: RuleLogicOperator = .and,
        actions: [RuleAction] = [RuleAction(type: .markAsRead)]
    ) -> NotificationRule {
        NotificationRule(
            name: name,
            isEnabled: isEnabled,
            priority: priority,
            conditions: conditions,
            logicOperator: logicOperator,
            actions: actions
        )
    }
}

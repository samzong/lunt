import XCTest
@testable import Lunt

final class AppConfigurationTests: XCTestCase {
    func test_init_parsesGitHubOAuthClientID() {
        let configuration = AppConfiguration(infoDictionary: [
            "GitHubOAuthClientID": "test-client-id",
        ])

        XCTAssertEqual(configuration.githubOAuthClientID, "test-client-id")
    }
}

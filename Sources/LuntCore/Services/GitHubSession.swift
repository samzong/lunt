import Foundation

/// Manages the authenticated session for GitHub APIs.
/// Provides unified access to REST and GraphQL clients.
@Observable
@MainActor
public final class GitHubSession {
    public private(set) var token: String?
    public private(set) var graphqlClient: GitHubGraphQLClient?
    public private(set) var restClient: GitHubAPI?

    public var isAuthenticated: Bool {
        token != nil
    }

    public init() {}

    public func configure(token: String, urlSession: URLSession? = nil) {
        self.token = token
        self.graphqlClient = GitHubGraphQLClient(token: token, session: urlSession)
        self.restClient = GitHubAPI(token: token, session: urlSession)
    }

    /// Clears the active session and cancels references to API clients.
    public func clear() {
        self.token = nil
        self.graphqlClient = nil
        self.restClient = nil
    }
}

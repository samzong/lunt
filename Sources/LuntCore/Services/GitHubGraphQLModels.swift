import Foundation

extension GitHubGraphQLClient {
    public struct ViewerInfo: Decodable, Sendable {
        public let login: String
        public let avatarUrl: String
    }
}

struct ViewerData: Decodable {
    let viewer: GitHubGraphQLClient.ViewerInfo
}

struct GraphQLRequest: Encodable {
    let query: String
    let variables: [String: Any]

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(query, forKey: .query)
        try container.encode(AnyCodable(variables), forKey: .variables)
    }

    private enum CodingKeys: String, CodingKey {
        case query, variables
    }
}

struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLErrorDetail]?
}

struct GraphQLErrorDetail: Decodable {
    let message: String
}

public struct NotificationDetails: Sendable {
    public let title: String
    public let state: String
    public let author: Author?
    public let updatedAt: Date
    public let latestComment: Comment?
    public let ciStatus: CIStatus?
    public let reviews: [Review]?
}

public struct Author: Codable, Sendable {
    public let login: String
    public let avatarUrl: String?
}

public struct Comment: Codable, Sendable {
    public let author: Author?
    public let body: String
    public let createdAt: Date
}

public struct CIStatus: Sendable, Hashable {
    public let state: String
    public let checks: [CheckResult]
}

public struct CheckResult: Sendable, Hashable {
    public let name: String
    public let status: String
    public let conclusion: String?
}

public struct Review: Codable, Sendable {
    public let author: Author?
    public let state: String
}

public enum NotificationSubjectType: Sendable {
    case pullRequest
    case issue
}

struct NotificationDetailsData: Decodable {
    let repository: RepositoryDetails
}

struct RepositoryDetails: Decodable {
    let pullRequest: PullRequestDetails?
    let issue: IssueDetails?
}

struct PullRequestDetails: Decodable {
    let title: String
    let state: String
    let author: Author?
    let updatedAt: Date
    let comments: CommentConnection
    let commits: CommitConnection?
    let reviews: ReviewConnection?

    func toDetails() -> NotificationDetails {
        NotificationDetails(
            title: title,
            state: state,
            author: author,
            updatedAt: updatedAt,
            latestComment: comments.nodes.first,
            ciStatus: commits?.nodes.first?.commit.statusCheckRollup?.toCIStatus(),
            reviews: reviews?.nodes
        )
    }
}

struct IssueDetails: Decodable {
    let title: String
    let state: String
    let author: Author?
    let updatedAt: Date
    let comments: CommentConnection

    func toDetails() -> NotificationDetails {
        NotificationDetails(
            title: title,
            state: state,
            author: author,
            updatedAt: updatedAt,
            latestComment: comments.nodes.first,
            ciStatus: nil,
            reviews: nil
        )
    }
}

struct CommentConnection: Decodable {
    let nodes: [Comment]
}

struct CommitConnection: Decodable {
    let nodes: [CommitNode]
}

struct CommitNode: Decodable {
    let commit: CommitDetails
}

struct CommitDetails: Decodable {
    let statusCheckRollup: StatusCheckRollup?
}

struct StatusCheckRollup: Decodable {
    let state: String
    let contexts: ContextConnection

    func toCIStatus() -> CIStatus {
        let checks = contexts.nodes.compactMap { node -> CheckResult? in
            if let checkRun = node.checkRun {
                return CheckResult(
                    name: checkRun.name,
                    status: checkRun.status,
                    conclusion: checkRun.conclusion
                )
            } else if let statusContext = node.statusContext {
                return CheckResult(
                    name: statusContext.context,
                    status: "COMPLETED",
                    conclusion: statusContext.state
                )
            }
            return nil
        }

        return CIStatus(state: state, checks: checks)
    }
}

struct ContextConnection: Decodable {
    let nodes: [ContextNode]
}

struct ContextNode: Decodable {
    let checkRun: CheckRun?
    let statusContext: StatusContext?

    private enum CodingKeys: String, CodingKey {
        case checkRun, statusContext
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        checkRun = try? container.decode(CheckRun.self, forKey: .checkRun)
        statusContext = try? container.decode(StatusContext.self, forKey: .statusContext)
    }
}

struct CheckRun: Decodable {
    let name: String
    let conclusion: String?
    let status: String
}

struct StatusContext: Decodable {
    let context: String
    let state: String
}

struct ReviewConnection: Decodable {
    let nodes: [Review]
}

struct SearchData: Decodable {
    let search: SearchConnection
}

struct SearchConnection: Decodable {
    let nodes: [SearchNode]
}

struct SearchNode: Decodable {
    let typename: String?
    let id: String?
    let number: Int?
    let title: String?
    let state: String?
    let repository: SearchRepository?
    let author: Author?
    let updatedAt: Date?
    let commits: CommitConnection?

    private enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case id, number, title, state, repository, author, updatedAt, commits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        typename = try container.decodeIfPresent(String.self, forKey: .typename)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        number = try container.decodeIfPresent(Int.self, forKey: .number)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        repository = try container.decodeIfPresent(SearchRepository.self, forKey: .repository)
        author = try container.decodeIfPresent(Author.self, forKey: .author)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        commits = try container.decodeIfPresent(CommitConnection.self, forKey: .commits)
    }
}

struct SearchRepository: Decodable {
    let owner: RepositoryOwner
    let name: String
}

struct RepositoryOwner: Decodable {
    let login: String
}

public enum GraphQLError: Error, LocalizedError, Sendable, Equatable {
    case invalidResponse
    case unauthorized
    case rateLimited(resetTime: Date?)
    case httpError(statusCode: Int)
    case graphQLErrors([String])
    case noData
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid GraphQL response"
        case .unauthorized:
            return "Unauthorized: Invalid or expired token. Please check your GitHub token in Settings."
        case let .rateLimited(resetTime):
            if let resetTime {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .full
                let relativeTime = formatter.localizedString(for: resetTime, relativeTo: Date())
                return "GitHub API rate limit exceeded. Resets \(relativeTime)."
            }
            return "GitHub API rate limit exceeded. Please try again later."
        case let .httpError(statusCode):
            return "HTTP error: \(statusCode)"
        case let .graphQLErrors(errors):
            return "GraphQL errors: \(errors.joined(separator: ", "))"
        case .noData:
            return "No data returned from GraphQL"
        case let .notFound(message):
            return message
        }
    }
}

struct AnyCodable: Encodable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Invalid JSON value"
                )
            )
        }
    }
}

import Foundation

public actor GitHubGraphQLClient {
    private let graphqlEndpoint: URL
    private let token: String
    private let session: URLSession

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public init(
        token: String,
        graphqlEndpoint: URL = URL(string: "https://api.github.com/graphql")!,
        session: URLSession? = nil
    ) {
        self.token = token
        self.graphqlEndpoint = graphqlEndpoint

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: configuration)
        }
    }

    public func fetchViewer() async throws -> ViewerInfo {
        let query = """
        query {
          viewer {
            login
            avatarUrl
          }
        }
        """

        let result: ViewerData = try await execute(query: query)
        return result.viewer
    }

    private func execute<T: Decodable>(query: String, variables: [String: Any] = [:]) async throws -> T {
        let body = GraphQLRequest(query: query, variables: variables)

        var request = URLRequest(url: graphqlEndpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GraphQLError.invalidResponse
        }

        if http.statusCode == 401 {
            throw GraphQLError.unauthorized
        }

        if http.isGitHubRateLimited {
            throw GraphQLError.rateLimited(resetTime: http.gitHubRateLimitResetDate)
        }

        guard http.statusCode == 200 else {
            throw GraphQLError.httpError(statusCode: http.statusCode)
        }

        let result = try decoder.decode(GraphQLResponse<T>.self, from: data)

        if let errors = result.errors, !errors.isEmpty {
            throw GraphQLError.graphQLErrors(errors.map(\.message))
        }

        guard let data = result.data else {
            throw GraphQLError.noData
        }

        return data
    }

    public func fetchNotificationDetails(
        owner: String,
        repo: String,
        number: Int,
        type: NotificationSubjectType
    ) async throws -> NotificationDetails {
        let query = switch type {
        case .pullRequest:
            """
            query($owner: String!, $repo: String!, $number: Int!) {
              repository(owner: $owner, name: $repo) {
                pullRequest(number: $number) {
                  title
                  state
                  author { login avatarUrl }
                  updatedAt
                  comments(last: 1) {
                    nodes {
                      author { login avatarUrl }
                      body
                      createdAt
                    }
                  }
                  commits(last: 1) {
                    nodes {
                      commit {
                        statusCheckRollup {
                          state
                          contexts(last: 100) {
                            nodes {
                              ... on CheckRun {
                                name
                                conclusion
                                status
                              }
                              ... on StatusContext {
                                context
                                state
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                  reviews(last: 5, states: [APPROVED, CHANGES_REQUESTED]) {
                    nodes {
                      author { login }
                      state
                    }
                  }
                }
              }
            }
            """
        case .issue:
            """
            query($owner: String!, $repo: String!, $number: Int!) {
              repository(owner: $owner, name: $repo) {
                issue(number: $number) {
                  title
                  state
                  author { login avatarUrl }
                  updatedAt
                  comments(last: 1) {
                    nodes {
                      author { login avatarUrl }
                      body
                      createdAt
                    }
                  }
                }
              }
            }
            """
        }

        let variables: [String: Any] = [
            "owner": owner,
            "repo": repo,
            "number": number,
        ]

        let result: NotificationDetailsData = try await execute(query: query, variables: variables)

        if type == .pullRequest {
            guard let pr = result.repository.pullRequest else {
                throw GraphQLError.notFound("Pull request not found or inaccessible")
            }
            return pr.toDetails()
        } else {
            guard let issue = result.repository.issue else {
                throw GraphQLError.notFound("Issue not found or inaccessible")
            }
            return issue.toDetails()
        }
    }

    public func search(query: String, first: Int = 50) async throws -> [SearchResultItem] {
        let graphqlQuery = """
        query($query: String!, $first: Int!) {
          search(query: $query, type: ISSUE, first: $first) {
            nodes {
              __typename
              ... on PullRequest {
                id
                number
                title
                state
                repository {
                  owner { login }
                  name
                }
                author { login avatarUrl }
                updatedAt
                commits(last: 1) {
                  nodes {
                    commit {
                      statusCheckRollup {
                        state
                        contexts(last: 100) {
                          nodes {
                            ... on CheckRun {
                              name
                              conclusion
                              status
                            }
                            ... on StatusContext {
                              context
                              state
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
              ... on Issue {
                id
                number
                title
                state
                repository {
                  owner { login }
                  name
                }
                author { login avatarUrl }
                updatedAt
              }
            }
          }
        }
        """

        let variables: [String: Any] = [
            "query": query,
            "first": first,
        ]

        let result: SearchData = try await execute(query: graphqlQuery, variables: variables)
        return result.search.nodes.compactMap { node -> SearchResultItem? in
            guard let id = node.id,
                  let number = node.number,
                  let title = node.title,
                  let state = node.state,
                  let repositoryOwner = node.repository?.owner.login,
                  let repositoryName = node.repository?.name,
                  let updatedAt = node.updatedAt else {
                return nil
            }

            let itemType: SearchResultItem.ItemType = node.typename == "PullRequest" ? .pullRequest : .issue

            return SearchResultItem(
                id: id,
                number: number,
                title: title,
                state: state,
                repositoryOwner: repositoryOwner,
                repositoryName: repositoryName,
                authorLogin: node.author?.login,
                authorAvatarUrl: node.author?.avatarUrl,
                updatedAt: updatedAt,
                itemType: itemType,
                ciStatus: node.commits?.nodes.first?.commit.statusCheckRollup?.toCIStatus()
            )
        }
    }

    public func searchRepositories(query: String, first: Int = 30) async throws -> [RepositorySearchItem] {
        let graphqlQuery = """
        query($query: String!, $first: Int!) {
          search(query: $query, type: REPOSITORY, first: $first) {
            nodes {
              ... on Repository {
                id
                name
                owner { login }
                description
                stargazerCount
                primaryLanguage { name }
                createdAt
                updatedAt
                isPrivate
                isFork
              }
            }
          }
        }
        """

        let variables: [String: Any] = ["query": query, "first": first]
        let result: RepoSearchData = try await execute(query: graphqlQuery, variables: variables)
        return result.search.nodes.compactMap { node -> RepositorySearchItem? in
            guard let id = node.id,
                  let name = node.name,
                  let owner = node.owner?.login,
                  let createdAt = node.createdAt,
                  let updatedAt = node.updatedAt else { return nil }

            return RepositorySearchItem(
                id: id,
                name: name,
                owner: owner,
                description: node.description,
                stargazerCount: node.stargazerCount ?? 0,
                language: node.primaryLanguage?.name,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isPrivate: node.isPrivate ?? false,
                isFork: node.isFork ?? false
            )
        }
    }
}

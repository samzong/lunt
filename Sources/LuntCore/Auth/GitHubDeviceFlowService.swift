import Foundation

public struct GitHubDeviceFlowService: Sendable {
    private static let deviceCodeURL = URL(string: "https://github.com/login/device/code")!
    private static let accessTokenURL = URL(string: "https://github.com/login/oauth/access_token")!
    private static let oauthScopes = "notifications read:user"

    private let urlSession: URLSession

    public init(urlSession: URLSession? = nil) {
        if let urlSession {
            self.urlSession = urlSession
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            self.urlSession = URLSession(configuration: configuration)
        }
    }

    public func requestDeviceCode(clientId: String) async throws -> DeviceCodeResponse {
        var request = URLRequest(url: Self.deviceCodeURL)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "client_id": clientId,
            "scope": Self.oauthScopes,
        ])

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DeviceFlowError.unexpectedResponse("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }

        return try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
    }

    public func pollForToken(
        clientId: String,
        deviceCode: String,
        currentInterval: Int = 5
    ) async throws -> PollTokenResult {
        var request = URLRequest(url: Self.accessTokenURL)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "client_id": clientId,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ])

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DeviceFlowError.unexpectedResponse("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }

        let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        if let errorCode = body["error"] as? String {
            switch errorCode {
            case "authorization_pending":
                return .pending
            case "slow_down":
                let serverInterval = body["interval"] as? Int
                return .slowDown(newInterval: max(serverInterval ?? 0, currentInterval + 5))
            case "expired_token":
                return .failed(.expiredToken)
            case "access_denied":
                return .failed(.accessDenied)
            case "device_flow_disabled":
                return .failed(.deviceFlowDisabled)
            case "incorrect_client_credentials":
                return .failed(.invalidClientId)
            default:
                return .failed(.unexpectedResponse(errorCode))
            }
        }

        let tokenResponse = try JSONDecoder().decode(AccessTokenResponse.self, from: data)
        return .token(tokenResponse)
    }
}

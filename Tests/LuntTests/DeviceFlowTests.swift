import Foundation
@testable import LuntCore
import XCTest

final class DeviceFlowTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testGitHubDeviceFlowServiceRequestAndPollStates() async throws {
        let service = GitHubDeviceFlowService(urlSession: MockURLProtocol.makeSession())

        MockURLProtocol.resetRequests()
        MockURLProtocol.respond(
            status: 200,
            body: #"{"device_code":"dev-123","user_code":"ABCD-1234","verification_uri":"https://github.com/login/device","verification_uri_complete":"https://github.com/login/device?user_code=ABCD-1234","expires_in":900,"interval":5}"#
        )
        let codeResponse = try await service.requestDeviceCode(clientId: "cid-1")
        XCTAssertEqual(codeResponse.deviceCode, "dev-123")
        XCTAssertEqual(codeResponse.userCode, "ABCD-1234")
        XCTAssertEqual(codeResponse.expiresIn, 900)
        XCTAssertEqual(codeResponse.interval, 5)
        XCTAssertEqual(MockURLProtocol.recordedRequests.first?.url?.absoluteString, "https://github.com/login/device/code")

        MockURLProtocol.respond(status: 200, body: #"{"error":"authorization_pending"}"#)
        let pendingResult = try await service.pollForToken(clientId: "cid-1", deviceCode: "dev-123", currentInterval: 5)
        guard case .pending = pendingResult else {
            return XCTFail("Expected pending")
        }

        MockURLProtocol.respond(status: 200, body: #"{"error":"slow_down"}"#)
        let slowDownDefault = try await service.pollForToken(clientId: "cid-1", deviceCode: "dev-123", currentInterval: 5)
        guard case let .slowDown(defaultInterval) = slowDownDefault else {
            return XCTFail("Expected slowDown")
        }
        XCTAssertEqual(defaultInterval, 10)

        MockURLProtocol.respond(status: 200, body: #"{"error":"slow_down","interval":2}"#)
        let slowDownLow = try await service.pollForToken(clientId: "cid-1", deviceCode: "dev-123", currentInterval: 5)
        guard case let .slowDown(lowInterval) = slowDownLow else {
            return XCTFail("Expected slowDown")
        }
        XCTAssertEqual(lowInterval, 10)

        MockURLProtocol.respond(status: 200, body: #"{"error":"slow_down","interval":20}"#)
        let slowDownServer = try await service.pollForToken(clientId: "cid-1", deviceCode: "dev-123", currentInterval: 5)
        guard case let .slowDown(serverInterval) = slowDownServer else {
            return XCTFail("Expected slowDown")
        }
        XCTAssertEqual(serverInterval, 20)

        MockURLProtocol.respond(status: 200, body: #"{"error":"expired_token"}"#)
        let expiredResult = try await service.pollForToken(clientId: "cid-1", deviceCode: "dev-123", currentInterval: 5)
        guard case .failed(.expiredToken) = expiredResult else {
            return XCTFail("Expected expiredToken")
        }

        MockURLProtocol.respond(status: 200, body: #"{"error":"access_denied"}"#)
        let deniedResult = try await service.pollForToken(clientId: "cid-1", deviceCode: "dev-123", currentInterval: 5)
        guard case .failed(.accessDenied) = deniedResult else {
            return XCTFail("Expected accessDenied")
        }

        MockURLProtocol.respond(
            status: 200,
            body: #"{"access_token":"gho_test_value","token_type":"bearer","scope":"notifications read:user"}"#
        )
        let tokenResult = try await service.pollForToken(clientId: "cid-1", deviceCode: "dev-123", currentInterval: 5)
        guard case let .token(tokenResponse) = tokenResult else {
            return XCTFail("Expected token")
        }
        XCTAssertEqual(tokenResponse.accessToken, "gho_test_value")

        MockURLProtocol.respond(status: 500, body: "server error")
        do {
            _ = try await service.pollForToken(clientId: "cid-1", deviceCode: "dev-123", currentInterval: 5)
            XCTFail("Expected DeviceFlowError")
        } catch is DeviceFlowError {
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }
}

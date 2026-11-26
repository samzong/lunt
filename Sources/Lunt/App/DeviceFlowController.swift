import AppKit
import LuntCore
import SwiftUI

struct DeviceFlowServices {
    let session: GitHubSession
    let notificationService: NotificationService
    let activityService: ActivityService
    let searchService: SearchService
    let monitorStore: MonitorStore
    let monitorEngine: MonitorEngine
}

enum DeviceFlowUIState: Equatable {
    case idle
    case requestingCode
    case showingCode(DeviceCodeResponse, secondsRemaining: Int)
    case success(username: String)
    case error(String)

    static func == (lhs: DeviceFlowUIState, rhs: DeviceFlowUIState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.requestingCode, .requestingCode):
            true
        case let (.showingCode(lhsCode, lhsSeconds), .showingCode(rhsCode, rhsSeconds)):
            lhsCode.userCode == rhsCode.userCode && lhsSeconds == rhsSeconds
        case let (.success(lhsUser), .success(rhsUser)):
            lhsUser == rhsUser
        case let (.error(lhsMessage), .error(rhsMessage)):
            lhsMessage == rhsMessage
        default:
            false
        }
    }
}

@Observable
@MainActor
final class DeviceFlowController {
    private(set) var state: DeviceFlowUIState = .idle
    private(set) var statusNotice: String?

    private let oauthClientID: String
    private let services: DeviceFlowServices
    private let deviceFlowService: GitHubDeviceFlowService
    private var pollingTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    init(
        oauthClientID: String,
        services: DeviceFlowServices,
        deviceFlowService: GitHubDeviceFlowService = GitHubDeviceFlowService()
    ) {
        self.oauthClientID = oauthClientID
        self.services = services
        self.deviceFlowService = deviceFlowService
    }

    func syncAuthenticatedUserIfNeeded() async {
        guard services.notificationService.isAuthenticated else { return }
        if let user = services.notificationService.currentUser {
            state = .success(username: user.login)
            return
        }
        await services.notificationService.fetchCurrentUser()
        if let user = services.notificationService.currentUser {
            state = .success(username: user.login)
        }
    }

    func startFlow() {
        cancelTasks()
        state = .requestingCode

        pollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let codeResponse = try await deviceFlowService.requestDeviceCode(clientId: oauthClientID)
                guard !Task.isCancelled else { return }

                copyCode(codeResponse.userCode)
                openVerificationURL(response: codeResponse)

                state = .showingCode(codeResponse, secondsRemaining: codeResponse.expiresIn)
                startCountdown(expiresIn: codeResponse.expiresIn)

                var interval = max(1, codeResponse.interval)
                let clock = ContinuousClock()
                let deadline = clock.now + .seconds(codeResponse.expiresIn)

                while !Task.isCancelled, clock.now < deadline {
                    try await Task.sleep(for: .seconds(interval))
                    guard !Task.isCancelled else { return }

                    let result = try await deviceFlowService.pollForToken(
                        clientId: oauthClientID,
                        deviceCode: codeResponse.deviceCode,
                        currentInterval: interval
                    )
                    guard !Task.isCancelled else { return }

                    switch result {
                    case let .token(tokenResponse):
                        await completeAuthorization(token: tokenResponse.accessToken)
                        return
                    case .pending:
                        break
                    case let .slowDown(newInterval):
                        interval = newInterval
                    case let .failed(flowError):
                        countdownTask?.cancel()
                        state = .error(flowError.localizedDescription)
                        return
                    }
                }

                if !Task.isCancelled {
                    countdownTask?.cancel()
                    state = .error(DeviceFlowError.expiredToken.localizedDescription)
                }
            } catch {
                guard !Task.isCancelled, (error as? URLError)?.code != .cancelled else { return }
                countdownTask?.cancel()
                state = .error(DeviceFlowError.networkError(underlying: error).localizedDescription)
            }
        }
    }

    func copyCode(_ userCode: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(userCode, forType: .string)
        showNotice(formattedLocalized(key: "welcome.oauth.code_copied", argument: userCode))
    }

    func openVerificationURL(response: DeviceCodeResponse) {
        let urlString = response.verificationUriComplete ?? response.verificationUri
        if let url = URL.validatedGitHubWebURL(from: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    func cancelFlow() {
        cancelTasks()
        noticeTask?.cancel()
        statusNotice = nil
        state = .idle
    }

    func resetToIdle() {
        cancelTasks()
        state = .idle
    }

    func signOut() {
        cancelTasks()
        noticeTask?.cancel()
        statusNotice = nil
        Task {
            await AuthStore.shared.clearToken()
        }
        services.session.clear()
        services.notificationService.clearToken()
        services.activityService.clearToken()
        services.searchService.clearToken()
        services.monitorEngine.stop()
        services.monitorStore.clearEvents()
        state = .idle
    }

    func formattedRemainingTime(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let minutes = clamped / 60
        let remainingSeconds = clamped % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func completeAuthorization(token: String) async {
        countdownTask?.cancel()
        guard !Task.isCancelled else { return }
        await AuthStore.shared.saveToken(token)
        guard !Task.isCancelled else {
            await AuthStore.shared.clearToken()
            return
        }

        let configuredInterval = UserDefaults.standard.double(forKey: UserPreferences.refreshIntervalKey)
        let interval = configuredInterval > 0 ? configuredInterval : 60

        services.session.configure(token: token)
        services.notificationService.startAutoRefresh(interval: interval)
        services.activityService.configure(interval: interval)
        services.searchService.configure(interval: interval)
        services.monitorEngine.start(interval: interval)

        await services.notificationService.fetchCurrentUser()
        guard !Task.isCancelled, services.session.isAuthenticated else { return }

        let username = services.notificationService.currentUser?.login ?? ""
        state = .success(username: username)
        if !username.isEmpty {
            showNotice(formattedLocalized(key: "welcome.oauth.signed_in_as", argument: username))
        }

        await services.notificationService.fetchNotifications()
        guard !Task.isCancelled, services.session.isAuthenticated else { return }
        await services.activityService.fetchMyItems()
        guard !Task.isCancelled, services.session.isAuthenticated else { return }
        await services.searchService.fetchAll()
    }

    private func startCountdown(expiresIn: Int) {
        countdownTask?.cancel()
        countdownTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var remaining = expiresIn
            while remaining > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                remaining -= 1
                if case let .showingCode(response, _) = state {
                    state = .showingCode(response, secondsRemaining: remaining)
                }
            }
        }
    }

    private func cancelTasks() {
        pollingTask?.cancel()
        pollingTask = nil
        countdownTask?.cancel()
        countdownTask = nil
    }

    private func showNotice(_ message: String) {
        statusNotice = message
        noticeTask?.cancel()
        noticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.statusNotice = nil
        }
    }

    private func formattedLocalized(key: String, argument: String) -> String {
        let template = key.localized
        return template.contains("%@") ? String(format: template, argument) : "\(template) \(argument)"
    }
}

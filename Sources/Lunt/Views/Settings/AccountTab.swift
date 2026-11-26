import AppKit
import LuntCore
import SwiftUI

struct AccountTab: View {
    @Environment(DeviceFlowController.self) private var deviceFlowController

    let settingsWidth: CGFloat

    var body: some View {
        Form {
            Section {
                webAuthView
            } header: {
                Text("account.auth.header".localized)
            }
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth)
        .task {
            await deviceFlowController.syncAuthenticatedUserIfNeeded()
        }
    }

    @ViewBuilder private var webAuthView: some View {
        switch deviceFlowController.state {
        case .idle:
            webAuthIdleView
        case .requestingCode:
            webAuthRequestingView
        case let .showingCode(response, seconds):
            webAuthCodeView(response: response, secondsRemaining: seconds)
        case let .success(username):
            webAuthSuccessView(username: username)
        case let .error(message):
            webAuthErrorView(message: message)
        }
    }

    private var webAuthIdleView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.badge.key.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            Text("account.webauth.description".localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("account.webauth.signin".localized) {
                deviceFlowController.startFlow()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private var webAuthRequestingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("account.webauth.requesting".localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("common.cancel".localized) {
                deviceFlowController.cancelFlow()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func webAuthCodeView(response: DeviceCodeResponse, secondsRemaining: Int) -> some View {
        VStack(spacing: 16) {
            Text("account.webauth.code_prompt".localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(response.userCode)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .tracking(4)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .liquidGlassSurface(cornerRadius: 10)

            HStack(spacing: 8) {
                Button("account.webauth.open_browser".localized) {
                    deviceFlowController.openVerificationURL(response: response)
                }
                .buttonStyle(.borderedProminent)

                Button("account.webauth.copy_code".localized) {
                    deviceFlowController.copyCode(response.userCode)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("account.webauth.waiting".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(
                String(
                    format: "account.webauth.expires_in".localized,
                    deviceFlowController.formattedRemainingTime(secondsRemaining)
                )
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)

            Button("common.cancel".localized) {
                deviceFlowController.cancelFlow()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func webAuthSuccessView(username: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("@\(username)")
                    .font(.headline)

                Text("account.webauth.signed_in".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let url = URL(string: "https://github.com/settings/apps/authorizations") {
                Link("account.webauth.manage_apps".localized, destination: url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("account.webauth.signout".localized) {
                deviceFlowController.signOut()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 8)
    }

    private func webAuthErrorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("account.webauth.retry".localized) {
                deviceFlowController.resetToIdle()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

#Preview {
    let session = GitHubSession()
    let store = MonitorStore()
    let services = DeviceFlowServices(
        session: session,
        notificationService: NotificationService(session: session),
        activityService: ActivityService(session: session),
        searchService: SearchService(session: session),
        monitorStore: store,
        monitorEngine: MonitorEngine(session: session, store: store)
    )
    AccountTab(settingsWidth: 450)
        .environment(DeviceFlowController(oauthClientID: "preview-client-id", services: services))
}

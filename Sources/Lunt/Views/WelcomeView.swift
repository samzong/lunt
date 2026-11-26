import LuntCore
import SwiftUI

struct WelcomeView: View {
    @Environment(DeviceFlowController.self) private var deviceFlowController

    let onOpenAccountSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            glyphView

            switch deviceFlowController.state {
            case .idle:
                idleContent
            case .requestingCode:
                requestingContent
            case let .showingCode(response, secondsRemaining):
                codeContent(response: response, secondsRemaining: secondsRemaining)
            case let .success(username):
                successContent(username: username)
            case let .error(message):
                errorContent(message: message)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var glyphView: some View {
        Group {
            switch deviceFlowController.state {
            case .requestingCode, .success:
                ProgressView()
                    .controlSize(.small)
            case .error:
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.red)
            case .idle, .showingCode:
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: 38, height: 38)
        .background(
            Color.primary.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder private var idleContent: some View {
        Text("welcome.oauth.title".localized)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)

        Text("welcome.oauth.subtitle".localized)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 270)

        Button("account.webauth.signin".localized) {
            deviceFlowController.startFlow()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .padding(.top, 4)
    }

    @ViewBuilder private var requestingContent: some View {
        Text("account.webauth.requesting".localized)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)

        Button("common.cancel".localized) {
            deviceFlowController.cancelFlow()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func codeContent(response: DeviceCodeResponse, secondsRemaining: Int) -> some View {
        Text("welcome.oauth.authorize_title".localized)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)

        Text("welcome.oauth.authorize_subtitle".localized)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 270)

        Text(response.userCode)
            .font(.system(size: 24, weight: .bold, design: .monospaced))
            .tracking(3)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .liquidGlassSurface(cornerRadius: 10)
            .padding(.top, 2)

        Text(
            String(
                format: "account.webauth.expires_in".localized,
                deviceFlowController.formattedRemainingTime(secondsRemaining)
            )
        )
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)

        HStack(spacing: 8) {
            Button("account.webauth.open_browser".localized) {
                deviceFlowController.openVerificationURL(response: response)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button("account.webauth.copy_code".localized) {
                deviceFlowController.copyCode(response.userCode)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("common.cancel".localized) {
                deviceFlowController.cancelFlow()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func successContent(username: String) -> some View {
        let message = username.isEmpty
            ? "account.webauth.signed_in".localized
            : String(format: "welcome.oauth.signed_in_as".localized, username)
        Text(message)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func errorContent(message: String) -> some View {
        Text("menubar.error.title".localized)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)

        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .frame(maxWidth: 280)

        HStack(spacing: 8) {
            Button("account.webauth.retry".localized) {
                deviceFlowController.startFlow()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button("menubar.error.account_settings".localized, action: onOpenAccountSettings)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.top, 4)
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
    WelcomeView(onOpenAccountSettings: {})
        .environment(DeviceFlowController(oauthClientID: "preview-client-id", services: services))
        .frame(width: 420, height: 420)
}

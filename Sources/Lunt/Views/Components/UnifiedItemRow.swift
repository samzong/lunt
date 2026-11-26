import Foundation
import LuntCore
import SwiftUI

enum UnifiedRowGlyph: Sendable, Hashable {
    case prOpen
    case prMerged
    case prClosed
    case prDraft
    case issueOpen
    case issueCompleted
    case issueNotPlanned
    case release
    case commit
    case comment
    case discussion
    case vulnerability
    case generic

    var assetName: String? {
        switch self {
        case .prOpen: "PullRequestOpen"
        case .prMerged: "PullRequestMerged"
        case .prClosed: "PullRequestClosed"
        case .prDraft: "PullRequestDraft"
        case .issueOpen: "IssueOpen"
        case .issueCompleted: "IssueClosed"
        case .issueNotPlanned: "IssueNotPlanned"
        default: nil
        }
    }

    var systemSymbolName: String {
        switch self {
        case .release: "tag"
        case .commit: "arrow.triangle.branch"
        case .comment: "text.bubble"
        case .discussion: "bubble.left.and.bubble.right"
        case .vulnerability: "shield.lefthalf.filled.trianglebadge.exclamationmark"
        default: "bell"
        }
    }

    var color: Color {
        switch self {
        case .prOpen, .issueOpen: .green
        case .prMerged, .issueCompleted: .purple
        case .prClosed, .vulnerability: .red
        case .prDraft, .issueNotPlanned, .commit, .generic: .secondary
        case .release: .blue
        case .comment: .teal
        case .discussion: .indigo
        }
    }
}

struct UnifiedRowModel: Identifiable, Sendable {
    enum Source: Sendable {
        case notification(NotificationGroup)
        case searchResult(SearchResultItem)
        case monitorEvent(MonitorEvent)
    }

    let id: String
    let glyph: UnifiedRowGlyph
    let repo: String
    let number: Int?
    let threadCount: Int
    let tag: String?
    let ciStatus: CIStatus?
    let title: String
    let date: Date
    let isUnread: Bool?
    let isPullRequest: Bool
    let url: URL?
    let source: Source

    var shortLabel: String {
        if let number {
            return "\(repo)#\(number)"
        }
        return repo
    }

    static func fromNotificationGroup(
        _ group: NotificationGroup,
        prState: PRState?,
        issueState: IssueState?,
        ciStatus: CIStatus?
    ) -> UnifiedRowModel {
        let notification = group.latestNotification
        return UnifiedRowModel(
            id: group.id,
            glyph: glyph(for: notification, prState: prState, issueState: issueState),
            repo: notification.repository.fullName,
            number: notification.issueOrPRNumber,
            threadCount: group.notifications.count,
            tag: localizedReason(notification.reason),
            ciStatus: ciStatus,
            title: notification.subject.title,
            date: notification.updatedAt,
            isUnread: notification.unread,
            isPullRequest: notification.notificationType == .pullRequest,
            url: webURL(for: notification),
            source: .notification(group)
        )
    }

    static func fromSearchResult(_ item: SearchResultItem, tag: String? = nil) -> UnifiedRowModel {
        UnifiedRowModel(
            id: item.id,
            glyph: glyph(for: item),
            repo: item.repositoryFullName,
            number: item.number,
            threadCount: 1,
            tag: tag,
            ciStatus: item.ciStatus,
            title: item.title,
            date: item.updatedAt,
            isUnread: nil,
            isPullRequest: item.itemType == .pullRequest,
            url: item.webURL,
            source: .searchResult(item)
        )
    }

    static func fromMonitorEvent(_ event: MonitorEvent) -> UnifiedRowModel {
        let formattedActor: String? = if event.actor.isEmpty {
            nil
        } else if event.actor.hasPrefix("query:") || event.actor.hasPrefix("@") {
            event.actor
        } else {
            "@\(event.actor)"
        }

        return UnifiedRowModel(
            id: event.id,
            glyph: glyph(for: event),
            repo: event.repo,
            number: event.number,
            threadCount: 1,
            tag: formattedActor,
            ciStatus: nil,
            title: event.title,
            date: event.occurredAt,
            isUnread: !event.isRead,
            isPullRequest: event.kind.lowercased() == "pr",
            url: URL.validatedGitHubWebURL(from: event.url),
            source: .monitorEvent(event)
        )
    }

    private static func glyph(
        for notification: GitHubNotification,
        prState: PRState?,
        issueState: IssueState?
    ) -> UnifiedRowGlyph {
        if let prState {
            switch prState {
            case .open: return .prOpen
            case .merged: return .prMerged
            case .closed: return .prClosed
            case .draft: return .prDraft
            }
        }
        if let issueState {
            switch issueState {
            case .open: return .issueOpen
            case .closedCompleted: return .issueCompleted
            case .closedNotPlanned: return .issueNotPlanned
            }
        }
        switch notification.notificationType {
        case .pullRequest: return .prOpen
        case .issue: return .issueOpen
        case .release: return .release
        case .commit: return .commit
        case .discussion: return .discussion
        case .repositoryVulnerabilityAlert: return .vulnerability
        case .checkSuite, .repositoryInvitation, .unknown: return .generic
        }
    }

    private static func glyph(for item: SearchResultItem) -> UnifiedRowGlyph {
        if item.itemType == .pullRequest {
            switch item.state.uppercased() {
            case "MERGED": .prMerged
            case "CLOSED": .prClosed
            case "DRAFT": .prDraft
            default: .prOpen
            }
        } else {
            switch item.state.uppercased() {
            case "CLOSED": .issueCompleted
            case "NOT_PLANNED": .issueNotPlanned
            default: .issueOpen
            }
        }
    }

    private static func glyph(for event: MonitorEvent) -> UnifiedRowGlyph {
        switch event.kind.lowercased() {
        case "pr": .prOpen
        case "issue": .issueOpen
        case "release": .release
        case "commit": .commit
        case "comment": .comment
        default: .generic
        }
    }

    private static func localizedReason(_ reason: String) -> String {
        switch reason {
        case "assign": "notification.reason.assign".localized
        case "author": "notification.reason.author".localized
        case "comment": "notification.reason.comment".localized
        case "ci_activity": "notification.reason.ci_activity".localized
        case "invitation": "notification.reason.invitation".localized
        case "manual": "notification.reason.manual".localized
        case "mention": "notification.reason.mention".localized
        case "review_requested": "notification.reason.review_requested".localized
        case "security_alert": "notification.reason.security_alert".localized
        case "state_change": "notification.reason.state_change".localized
        case "subscribed": "notification.reason.subscribed".localized
        case "team_mention": "notification.reason.team_mention".localized
        default: reason.replacingOccurrences(of: "_", with: " ")
        }
    }

    private static func webURL(for notification: GitHubNotification) -> URL? {
        if let number = notification.issueOrPRNumber {
            let baseURL = notification.repository.htmlUrl
            switch notification.notificationType {
            case .pullRequest:
                return URL.validatedGitHubWebURL(from: "\(baseURL)/pull/\(number)")
            case .issue:
                return URL.validatedGitHubWebURL(from: "\(baseURL)/issues/\(number)")
            default:
                break
            }
        }

        if let apiURLString = notification.subject.url {
            return URL.validatedGitHubAPISubjectWebURL(from: apiURLString)
        }

        return URL.validatedGitHubWebURL(from: notification.repository.htmlUrl)
    }
}

struct UnifiedItemRow: View {
    let model: UnifiedRowModel
    let isActive: Bool
    let isCommandHeld: Bool
    let shortcutNumber: Int?
    let onOpen: () -> Void
    let onToggleRead: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 8) {
                    leadingGlyph
                    mainBody
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            trailingSlot
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovered || isActive ? Color.primary.opacity(0.06) : Color.clear)
        }
        .overlay(alignment: .leading) {
            if isActive {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 2)
                    .padding(.vertical, 6)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var leadingGlyph: some View {
        Group {
            if let assetName = model.glyph.assetName {
                Image(assetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: model.glyph.systemSymbolName)
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .foregroundStyle(model.glyph.color)
        .frame(width: 18, height: 18)
        .padding(.top, 1)
    }

    private var mainBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(model.repo)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let number = model.number {
                    Text("#\(number.formatted(.number.grouping(.never)))")
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }

                if model.threadCount > 1 {
                    metaBadge("×\(model.threadCount)")
                }

                if let tag = model.tag, !tag.isEmpty {
                    metaBadge(tag)
                }

                if let ciBadge = ciBadgeInfo(model.ciStatus) {
                    Text(ciBadge.text)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ciBadge.color)
                        .fixedSize()
                }
            }
            .font(.system(size: 12))

            Text(model.title)
                .font(.system(size: 13, weight: model.isUnread == false ? .regular : .medium))
                .foregroundStyle(model.isUnread == false ? .secondary : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var trailingSlot: some View {
        ZStack(alignment: .topTrailing) {
            if isCommandHeld, let shortcut = shortcutNumber {
                Text("\(shortcut)")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(minWidth: 22)
                    .frame(height: 20)
                    .padding(.horizontal, 5)
                    .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.16), lineWidth: 1))
            } else if isHovered {
                HStack(spacing: 4) {
                    if let onToggleRead {
                        trailingActionButton(
                            systemName: "checkmark",
                            helpText: "menubar.action.toggle_read".localized,
                            action: onToggleRead
                        )
                    }

                    trailingActionButton(
                        systemName: "arrow.up.right",
                        helpText: "menubar.action.open_github".localized,
                        action: onOpen
                    )
                }
            } else {
                HStack(spacing: 5) {
                    TimeAgoText(date: model.date)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if model.isUnread == true {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        .frame(width: 58, alignment: .trailing)
        .frame(minHeight: 36, alignment: .topTrailing)
    }

    private func metaBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .fixedSize()
    }

    private func trailingActionButton(
        systemName: String,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Color(nsColor: .controlBackgroundColor), in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private func ciBadgeInfo(_ status: CIStatus?) -> (text: String, color: Color)? {
        guard let status else { return nil }
        switch status.state.uppercased() {
        case "SUCCESS":
            return ("✓ CI", .green)
        case "FAILURE", "ERROR":
            return ("✕ CI", .red)
        case "PENDING":
            return ("● CI", .orange)
        default:
            return nil
        }
    }
}

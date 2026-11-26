import LuntCore
import SwiftUI

enum PopoverCalmMode: Equatable {
    case loading
    case empty(isWatch: Bool, isFiltered: Bool)
    case error(String)
}

struct PopoverCalmStateView: View {
    let mode: PopoverCalmMode
    let onRetry: () -> Void
    let onAccountSettings: () -> Void
    let onManageWatch: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            glyphView

            switch mode {
            case .loading:
                Text("menubar.loading".localized)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

            case let .empty(isWatch, isFiltered):
                Text(emptyTitle(isWatch: isWatch, isFiltered: isFiltered))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(emptySubtitle(isWatch: isWatch, isFiltered: isFiltered))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)

                if isWatch {
                    HStack(spacing: 8) {
                        Button("menubar.empty.watch.manage".localized, action: onManageWatch)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    .padding(.top, 4)
                }

            case let .error(message):
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
                    Button("menubar.error.retry".localized, action: onRetry)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                    Button("menubar.error.account_settings".localized, action: onAccountSettings)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var glyphView: some View {
        Group {
            switch mode {
            case .loading:
                ProgressView()
                    .controlSize(.small)
            case let .empty(isWatch, _):
                Image(systemName: isWatch ? "waveform.path.ecg" : "checkmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            case .error:
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.red)
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

    private func emptyTitle(isWatch: Bool, isFiltered: Bool) -> String {
        if isWatch {
            return "menubar.empty.watch.title".localized
        }
        return isFiltered ? "menubar.empty.filtered.title".localized : "menubar.no_items".localized
    }

    private func emptySubtitle(isWatch: Bool, isFiltered: Bool) -> String {
        if isWatch {
            return "menubar.empty.watch.subtitle".localized
        }
        return isFiltered ? "menubar.empty.filtered.subtitle".localized : "menubar.empty.subtitle".localized
    }
}

extension PopoverFeedProjection {
    static func inboxCounts(from notificationService: NotificationService) -> [InboxScope: Int] {
        let groups = notificationService.groupedNotifications
        return [
            .all: groups.count,
            .prs: groups.count { $0.notificationType == .pullRequest },
            .issues: groups.count { $0.notificationType == .issue },
        ]
    }

    static func workRoleCounts(
        from activityService: ActivityService,
        workType: WorkItemTypeFilter
    ) -> [ActivityFilter: Int] {
        Dictionary(uniqueKeysWithValues: ActivityFilter.allCases.map { role in
            let filtered = filterByWorkType(activityService.items(for: role), workType: workType)
            return (role, filtered.count)
        })
    }

    static func pinnedSearchCounts(
        from searchService: SearchService,
        pinnedSearches: [SavedSearch],
        workType: WorkItemTypeFilter
    ) -> [UUID: Int] {
        Dictionary(uniqueKeysWithValues: pinnedSearches.map { search in
            let filtered = filterByWorkType(
                searchService.resultsBySearchId[search.id] ?? [],
                workType: workType
            )
            return (search.id, filtered.count)
        })
    }

    static func lastSyncedAt(for context: PopoverFeedContext) -> Date? {
        switch context.tab {
        case .inbox:
            return context.notificationService.lastSyncedAt
        case .work:
            let scope = validatedWorkScope(context.workScope, pinnedSearches: context.pinnedSearches)
            if case .search = scope {
                return context.searchService.lastSyncedAt
            }
            return context.activityService.lastSyncedAt
        case .watch:
            return context.monitorStore.lastSyncedAt.values.max()
        }
    }

    static func errorMessage(
        for context: PopoverFeedContext,
        monitorEngine: MonitorEngine
    ) -> String? {
        switch context.tab {
        case .inbox:
            return context.notificationService.errorMessage
        case .work:
            let scope = validatedWorkScope(context.workScope, pinnedSearches: context.pinnedSearches)
            if case let .search(id) = scope {
                return context.searchService.errorsBySearchId[id] ?? context.searchService.errorMessage
            }
            return context.activityService.errorMessage
        case .watch:
            let scope = validatedWatchScope(
                context.watchScope,
                activeMonitors: context.activeMonitors,
                alertSearches: context.alertSearches
            )
            return watchErrorMessage(
                scope: scope,
                activeMonitors: context.activeMonitors,
                alertSearches: context.alertSearches,
                monitorEngine: monitorEngine,
                searchService: context.searchService
            )
        }
    }
}

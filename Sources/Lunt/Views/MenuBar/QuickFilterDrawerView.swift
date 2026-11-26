import LuntCore
import SwiftUI

struct QuickFilterDrawerView: View {
    @Binding var selectedMode: QuickFilterMode
    let onClose: () -> Void

    private let modes: [QuickFilterMode] = [.all, .unread, .prs, .ciAttention]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(modes, id: \.self) { mode in
                            filterPill(mode)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("common.cancel".localized)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))

            Divider()
        }
    }

    private func filterPill(_ mode: QuickFilterMode) -> some View {
        let isSelected = selectedMode == mode
        return Button {
            selectedMode = mode
        } label: {
            Text(title(for: mode))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(height: 24)
                .padding(.horizontal, 8)
                .background(
                    isSelected ? Color.primary.opacity(0.08) : Color.clear,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.primary.opacity(0.14) : Color.clear,
                            lineWidth: 1
                        )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func title(for mode: QuickFilterMode) -> String {
        switch mode {
        case .all: "menubar.quick_filter.all".localized
        case .unread: "menubar.quick_filter.unread".localized
        case .prs: "menubar.quick_filter.prs".localized
        case .ciAttention: "menubar.quick_filter.ci_fail".localized
        }
    }
}

extension QuickFilterMode {
    func apply(to rows: [UnifiedRowModel], isOpen: Bool) -> [UnifiedRowModel] {
        guard isOpen else { return rows }
        switch self {
        case .all:
            return rows
        case .unread:
            return rows.filter { $0.isUnread == true }
        case .prs:
            return rows.filter(\.isPullRequest)
        case .ciAttention:
            return rows.filter { row in
                guard let state = row.ciStatus?.state.uppercased() else { return false }
                return state == "FAILURE" || state == "ERROR" || state == "PENDING"
            }
        }
    }
}

extension PopoverFeedProjection {
    static func initialLoad(
        notificationService: NotificationService,
        activityService: ActivityService,
        searchService: SearchService,
        monitorStore: MonitorStore,
        monitorEngine: MonitorEngine
    ) async {
        if notificationService.currentUser == nil {
            await notificationService.fetchCurrentUser()
        }
        if notificationService.lastSyncedAt == nil {
            await notificationService.fetchNotifications()
        }
        if activityService.lastSyncedAt == nil {
            await activityService.fetchMyItems()
        }
        if searchService.lastSyncedAt == nil {
            await searchService.fetchAll()
        }
        if monitorStore.lastSyncedAt.isEmpty {
            await monitorEngine.syncAll()
        }
    }

    static func shouldAutoRefresh(context: PopoverFeedContext) -> Bool {
        switch context.tab {
        case .inbox: context.notificationService.lastSyncedAt == nil
        case .work: context.activityService.lastSyncedAt == nil || context.searchService.lastSyncedAt == nil
        case .watch: context.monitorStore.lastSyncedAt.isEmpty
        }
    }

    static func refresh(
        context: PopoverFeedContext,
        monitorEngine: MonitorEngine
    ) async {
        switch context.tab {
        case .inbox:
            await context.notificationService.fetchNotifications()
        case .work:
            let scope = validatedWorkScope(context.workScope, pinnedSearches: context.pinnedSearches)
            if case .search = scope {
                await context.searchService.fetchAll()
            } else {
                switch context.workType {
                case .all: await context.activityService.fetchMyItems()
                case .issues: await context.activityService.fetchMyItems(type: .issue)
                case .prs: await context.activityService.fetchMyItems(type: .pullRequest)
                }
            }
        case .watch:
            await monitorEngine.syncAll()
        }
    }

    static func markCurrentTabRead(context: PopoverFeedContext) async -> String? {
        switch context.tab {
        case .inbox:
            let groups = context.notificationService.groupedNotifications.filter { group in
                switch context.inboxScope {
                case .all: true
                case .prs: group.notificationType == .pullRequest
                case .issues: group.notificationType == .issue
                }
            }
            for group in groups {
                await context.notificationService.markGroupAsRead(group)
            }
            return "menubar.status.inbox_cleared".localized

        case .watch:
            let scope = validatedWatchScope(
                context.watchScope,
                activeMonitors: context.activeMonitors,
                alertSearches: context.alertSearches
            )
            let targetIds: Set<UUID> = switch scope {
            case .all: Set(context.activeMonitors.map(\.id) + context.alertSearches.map(\.id))
            case let .monitor(id), let .query(id): [id]
            }
            context.monitorStore.markEventsRead(forTargetIds: targetIds)
            return "menubar.status.watch_cleared".localized

        case .work:
            return nil
        }
    }
}

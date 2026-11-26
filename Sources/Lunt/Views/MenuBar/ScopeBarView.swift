import LuntCore
import SwiftUI

enum WorkScopeSelection: Equatable, Hashable, Sendable {
    case role(ActivityFilter)
    case search(UUID)
}

enum WatchScopeSelection: Equatable, Hashable, Sendable {
    case all
    case monitor(UUID)
    case query(UUID)
}

@MainActor
struct PopoverFeedContext {
    let tab: MenuBarMainTab
    let inboxScope: InboxScope
    let workScope: WorkScopeSelection
    let workType: WorkItemTypeFilter
    let watchScope: WatchScopeSelection
    let quickFilterOpen: Bool
    let quickFilterMode: QuickFilterMode
    let notificationService: NotificationService
    let activityService: ActivityService
    let searchService: SearchService
    let monitorStore: MonitorStore
    let pinnedSearches: [SavedSearch]
    let activeMonitors: [MonitorDefinition]
    let alertSearches: [SavedSearch]
}

@MainActor
enum PopoverFeedProjection {
    static func filterByWorkType(
        _ items: [SearchResultItem],
        workType: WorkItemTypeFilter
    ) -> [SearchResultItem] {
        switch workType {
        case .all:
            items
        case .prs:
            items.filter { $0.itemType == .pullRequest }
        case .issues:
            items.filter { $0.itemType == .issue }
        }
    }

    static func validatedWorkScope(
        _ scope: WorkScopeSelection,
        pinnedSearches: [SavedSearch]
    ) -> WorkScopeSelection {
        if case let .search(id) = scope,
           !pinnedSearches.contains(where: { $0.id == id }) {
            return .role(.all)
        }
        return scope
    }

    static func validatedWatchScope(
        _ scope: WatchScopeSelection,
        activeMonitors: [MonitorDefinition],
        alertSearches: [SavedSearch]
    ) -> WatchScopeSelection {
        switch scope {
        case .all:
            .all
        case let .monitor(id):
            activeMonitors.contains(where: { $0.id == id }) ? .monitor(id) : .all
        case let .query(id):
            alertSearches.contains(where: { $0.id == id }) ? .query(id) : .all
        }
    }

    static func watchEvents(
        from events: [MonitorEvent],
        scope: WatchScopeSelection,
        activeMonitors: [MonitorDefinition],
        alertSearches: [SavedSearch]
    ) -> [MonitorEvent] {
        let monitorsById = Dictionary(activeMonitors.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let alertIds = Set(alertSearches.map(\.id))

        return events.filter { event in
            if let monitor = monitorsById[event.targetId] {
                if monitor.eventToggles[event.kind] == false {
                    return false
                }
                switch scope {
                case .all:
                    return true
                case let .monitor(id):
                    return monitor.id == id
                case .query:
                    return false
                }
            }
            if alertIds.contains(event.targetId) {
                switch scope {
                case .all:
                    return true
                case .monitor:
                    return false
                case let .query(id):
                    return event.targetId == id
                }
            }
            return false
        }
    }

    static func buildRows(from context: PopoverFeedContext) -> [UnifiedRowModel] {
        let rows: [UnifiedRowModel]
        switch context.tab {
        case .inbox:
            let groups = context.notificationService.groupedNotifications.filter { group in
                switch context.inboxScope {
                case .all: true
                case .prs: group.notificationType == .pullRequest
                case .issues: group.notificationType == .issue
                }
            }
            rows = groups.map { group in
                UnifiedRowModel.fromNotificationGroup(
                    group,
                    prState: context.notificationService.getPRState(for: group.latestNotification),
                    issueState: context.notificationService.getIssueState(for: group.latestNotification),
                    ciStatus: context.notificationService.getNotificationDetails(for: group.latestNotification)?.ciStatus
                )
            }

        case .work:
            let resolvedScope = validatedWorkScope(context.workScope, pinnedSearches: context.pinnedSearches)
            let sourceItems: [SearchResultItem] = switch resolvedScope {
            case let .role(filter):
                filterByWorkType(context.activityService.items(for: filter), workType: context.workType)
            case let .search(id):
                filterByWorkType(context.searchService.resultsBySearchId[id] ?? [], workType: context.workType)
            }
            rows = sourceItems.map { UnifiedRowModel.fromSearchResult($0) }

        case .watch:
            let resolvedScope = validatedWatchScope(
                context.watchScope,
                activeMonitors: context.activeMonitors,
                alertSearches: context.alertSearches
            )
            let events = watchEvents(
                from: context.monitorStore.events,
                scope: resolvedScope,
                activeMonitors: context.activeMonitors,
                alertSearches: context.alertSearches
            )
            rows = events.map { UnifiedRowModel.fromMonitorEvent($0) }
        }

        return context.quickFilterMode.apply(to: rows, isOpen: context.quickFilterOpen)
    }

    static func watchErrorMessage(
        scope: WatchScopeSelection,
        activeMonitors: [MonitorDefinition],
        alertSearches: [SavedSearch],
        monitorEngine: MonitorEngine,
        searchService: SearchService
    ) -> String? {
        var messages: [String] = []
        for monitor in activeMonitors {
            if case let .monitor(selectedId) = scope, selectedId != monitor.id {
                continue
            }
            if case .query = scope {
                continue
            }
            if let error = monitorEngine.errorsByMonitorId[monitor.id] {
                messages.append("\(monitor.displayName): \(error)")
            }
        }
        for search in alertSearches {
            if case let .query(selectedId) = scope, selectedId != search.id {
                continue
            }
            if case .monitor = scope {
                continue
            }
            if let error = searchService.errorsBySearchId[search.id] {
                messages.append("\(search.name): \(error)")
            }
        }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }
}

struct ScopeBarView: View {
    let mainTab: MenuBarMainTab

    @Binding var inboxScope: InboxScope
    let inboxCounts: [InboxScope: Int]
    let inboxUnread: Int

    @Binding var workScope: WorkScopeSelection
    @Binding var workType: WorkItemTypeFilter
    let workRoleCounts: [ActivityFilter: Int]
    let pinnedSearches: [SavedSearch]
    let pinnedSearchCounts: [UUID: Int]

    @Binding var watchScope: WatchScopeSelection
    let watchUnread: Int
    let activeMonitors: [MonitorDefinition]
    let alertSearches: [SavedSearch]

    let isMarkingRead: Bool
    let onMarkRead: () -> Void
    let onManageWork: () -> Void
    let onManageWatch: () -> Void

    private let workRoleOrder: [ActivityFilter] = [
        .all,
        .reviewRequested,
        .assigned,
        .created,
        .mentioned,
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        scopePills
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 2) {
                    trailingActions
                }
            }
            .frame(minHeight: 36)
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 6)

            Divider()
        }
    }

    @ViewBuilder private var scopePills: some View {
        switch mainTab {
        case .inbox:
            ForEach(InboxScope.allCases, id: \.self) { scope in
                scopePill(
                    title: inboxTitle(scope),
                    count: inboxCounts[scope] ?? 0,
                    isSelected: inboxScope == scope
                ) {
                    inboxScope = scope
                }
            }

        case .work:
            ForEach(workRoleOrder, id: \.self) { role in
                scopePill(
                    title: role.displayName,
                    count: workRoleCounts[role] ?? 0,
                    isSelected: workScope == .role(role)
                ) {
                    workScope = .role(role)
                }
            }

            if !pinnedSearches.isEmpty {
                Rectangle()
                    .fill(Color.primary.opacity(0.14))
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, 3)

                ForEach(pinnedSearches) { search in
                    scopePill(
                        title: search.name,
                        count: pinnedSearchCounts[search.id] ?? 0,
                        isSelected: workScope == .search(search.id)
                    ) {
                        workScope = .search(search.id)
                    }
                }
            }

        case .watch:
            scopePill(
                title: "menubar.tab.all".localized,
                count: watchUnread,
                isSelected: watchScope == .all
            ) {
                watchScope = .all
            }

            ForEach(activeMonitors) { monitor in
                scopePill(
                    title: monitor.displayName,
                    count: nil,
                    isSelected: watchScope == .monitor(monitor.id)
                ) {
                    watchScope = .monitor(monitor.id)
                }
            }

            ForEach(alertSearches) { search in
                scopePill(
                    title: search.name,
                    count: nil,
                    isSelected: watchScope == .query(search.id)
                ) {
                    watchScope = .query(search.id)
                }
            }
        }
    }

    @ViewBuilder private var trailingActions: some View {
        switch mainTab {
        case .inbox:
            if inboxUnread > 0 {
                readButton
            }

        case .work:
            compactButton(action: { workType = workType.next }) {
                HStack(spacing: 3) {
                    Text(workTypeTitle(workType))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
            }

            compactButton(action: onManageWork) {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11))
                    Text("menubar.action.manage".localized)
                }
            }

        case .watch:
            if watchUnread > 0 {
                readButton
            }

            compactButton(action: onManageWatch) {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11))
                    Text("menubar.action.manage".localized)
                }
            }
        }
    }

    private var readButton: some View {
        compactButton(action: onMarkRead) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                Text("menubar.action.read".localized)
            }
        }
        .disabled(isMarkingRead)
    }

    private func scopePill(
        title: String,
        count: Int?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                if let count {
                    Text("\(count)")
                        .fontWeight(.regular)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .frame(height: 24)
            .padding(.horizontal, 7)
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

    private func compactButton(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> some View
    ) -> some View {
        Button(action: action) {
            label()
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(height: 24)
                .padding(.horizontal, 8)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func inboxTitle(_ scope: InboxScope) -> String {
        switch scope {
        case .all: "menubar.tab.all".localized
        case .prs: "menubar.tab.prs".localized
        case .issues: "menubar.tab.issues".localized
        }
    }

    private func workTypeTitle(_ filter: WorkItemTypeFilter) -> String {
        switch filter {
        case .all: "menubar.work.type.all".localized
        case .prs: "menubar.work.type.prs".localized
        case .issues: "menubar.work.type.issues".localized
        }
    }
}

extension ActivityFilter {
    var displayName: String {
        switch self {
        case .all: "menubar.filter.all".localized
        case .assigned: "menubar.filter.assigned".localized
        case .created: "menubar.filter.created".localized
        case .mentioned: "menubar.filter.mentioned".localized
        case .reviewRequested: "menubar.filter.review_requested".localized
        }
    }
}

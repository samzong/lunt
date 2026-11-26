import AppKit
import LuntCore
import SwiftUI

struct MenuBarView: View {
    @Environment(NotificationService.self) private var notificationService
    @Environment(ActivityService.self) private var activityService
    @Environment(SearchService.self) private var searchService
    @Environment(MonitorStore.self) private var monitorStore
    @Environment(MonitorEngine.self) private var monitorEngine
    @Environment(SettingsNavigationState.self) private var settingsNavigationState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    @AppStorage("menubar.selectedMainTab") private var selectedMainTabRawValue = MenuBarMainTab.activity.rawValue
    @AppStorage("menubar.selectedSubTab") private var selectedSubTabRawValue = MenuBarSubTab.issues.rawValue
    @AppStorage("menubar.selectedActivityFilter") private var selectedActivityFilterRawValue = ActivityFilter.all.rawValue
    @AppStorage("searchList.selectedFilterId") private var selectedSearchFilterIdString: String?

    @State private var isMarkingAsRead = false
    @State private var visibleMainTabs = MenuBarMainTab.visibleTabs()

    private var hasToken: Bool {
        notificationService.isAuthenticated
    }

    private var selectedMainTab: MenuBarMainTab {
        get { MenuBarMainTab(rawValue: selectedMainTabRawValue) ?? .activity }
        nonmutating set { selectedMainTabRawValue = newValue.rawValue }
    }

    private var selectedSubTab: MenuBarSubTab {
        get { MenuBarSubTab(rawValue: selectedSubTabRawValue) ?? .issues }
        nonmutating set { selectedSubTabRawValue = newValue.rawValue }
    }

    private var selectedActivityFilter: ActivityFilter {
        get { ActivityFilter(rawValue: selectedActivityFilterRawValue) ?? .all }
        nonmutating set { selectedActivityFilterRawValue = newValue.rawValue }
    }

    private var selectedSearchFilterId: UUID? {
        get { selectedSearchFilterIdString.flatMap { UUID(uuidString: $0) } }
        nonmutating set { selectedSearchFilterIdString = newValue?.uuidString }
    }

    private var effectiveMainTab: MenuBarMainTab {
        if visibleMainTabs.contains(selectedMainTab) {
            return selectedMainTab
        }
        return visibleMainTabs.first ?? .notifications
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasToken {
                HeaderView(
                    selectedTab: rawBinding($selectedMainTabRawValue, default: .activity),
                    visibleTabs: visibleMainTabs,
                    unreadCount: notificationService.unreadCount,
                    currentUserLogin: notificationService.currentUser?.login,
                    onOpenSettings: { openSettingsAndActivate() },
                    onQuit: { NSApplication.shared.terminate(nil) }
                )

                Divider()

                SubTabPickerView(
                    selectedSubTab: rawBinding($selectedSubTabRawValue, default: .issues),
                    mainTab: effectiveMainTab,
                    allCount: currentAllCount,
                    issuesCount: currentIssuesCount,
                    prsCount: currentPrsCount,
                    isMarkingAsRead: isMarkingAsRead,
                    isLoading: notificationService.isLoading || activityService.isLoading || searchService.isLoading || monitorEngine
                        .isSyncing,
                    pinnedSearches: searchService.savedSearches.filter { $0.isEnabled && $0.isPinned },
                    selectedSearchId: Binding(
                        get: { selectedSearchFilterId },
                        set: { selectedSearchFilterId = $0 }
                    ),
                    onMarkAsRead: markFilteredAsRead,
                    onRefresh: refreshCurrentTab,
                    onManage: manageAction
                )

                if effectiveMainTab == .activity {
                    FilterBarView(
                        selectedFilter: rawBinding($selectedActivityFilterRawValue, default: .all),
                        filterCounts: filterCounts
                    )
                    Divider()
                }

                Divider()

                contentView
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                WelcomeView(onOpenSettings: { openSettingsAndActivate(tab: .account) })
            }
        }
        .frame(width: 380, height: 520)
        .liquidReadableWindowBackground()
        .liquidAutomaticScrollEdgeEffect(for: .top)
        .task {
            normalizeSelectedMainTabIfNeeded()
            clearInitialFocus()
            await initialLoad()
        }
        .onChange(of: selectedMainTab) { _, newTab in
            guard visibleMainTabs.contains(newTab) else {
                normalizeSelectedMainTabIfNeeded()
                return
            }
            if newTab == .activity, selectedSubTab == .all {
                selectedSubTab = .issues
            }
            if shouldAutoRefreshOnTabSelect(newTab) {
                Task { await refreshCurrentTab() }
            }
        }
    }

    @ViewBuilder private var contentView: some View {
        switch effectiveMainTab {
        case .activity:
            ActivityListView(
                subTab: selectedSubTab,
                filter: selectedActivityFilter
            ) { item in
                closeMenuBarWindow()
                openActivityItem(item)
            }
            .environment(activityService)

        case .notifications:
            NotificationListView(subTab: selectedSubTab) { group in
                closeMenuBarWindow()
                openNotificationGroup(group)
            }
            .environment(notificationService)

        case .search:
            SearchListView(
                selectedSearchId: Binding(
                    get: { selectedSearchFilterId },
                    set: { selectedSearchFilterId = $0 }
                )
            ) { item in
                closeMenuBarWindow()
                openActivityItem(item)
            }
            .environment(searchService)

        case .watching:
            if monitorStore.monitors.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)

                    Text("menubar.watching.empty.title".localized)
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text("menubar.watching.empty.description".localized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Button("monitor.management.title".localized) {
                        openWindowAndActivate(.monitorManagement)
                    }
                    .liquidGlassButtonStyle(prominent: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if monitorStore.events.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "circle.dashed")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                            Text("monitor.management.events.empty".localized)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(monitorStore.events) { event in
                            MenuBarEventRow(event: event) {
                                monitorStore.markEventRead(id: event.id)
                                if let url = URL(string: event.url) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var currentAllCount: Int {
        switch effectiveMainTab {
        case .notifications:
            notificationService.unreadCount
        case .activity:
            activityService.items(for: .all).count
        case .search:
            searchService.items.count
        case .watching:
            monitorStore.events.count
        }
    }

    private var currentIssuesCount: Int {
        switch effectiveMainTab {
        case .notifications:
            notificationService.notifications.count { $0.notificationType == .issue }
        case .activity:
            activityService.issues(for: .all).count
        case .search:
            searchService.items.count(where: { $0.itemType == .issue })
        case .watching:
            0
        }
    }

    private var currentPrsCount: Int {
        switch effectiveMainTab {
        case .notifications:
            notificationService.notifications.count { $0.notificationType == .pullRequest }
        case .activity:
            activityService.pullRequests(for: .all).count
        case .search:
            searchService.items.count(where: { $0.itemType == .pullRequest })
        case .watching:
            0
        }
    }

    private var filterCounts: [ActivityFilter: Int] {
        switch selectedSubTab {
        case .all:
            [
                .all: activityService.items(for: .all).count,
                .assigned: activityService.items(for: .assigned).count,
                .created: activityService.items(for: .created).count,
                .mentioned: activityService.items(for: .mentioned).count,
                .reviewRequested: activityService.items(for: .reviewRequested).count,
            ]
        case .issues:
            [
                .created: activityService.issues(for: .created).count,
                .assigned: activityService.issues(for: .assigned).count,
                .mentioned: activityService.issues(for: .mentioned).count,
            ]
        case .prs:
            [
                .created: activityService.pullRequests(for: .created).count,
                .reviewRequested: activityService.pullRequests(for: .reviewRequested).count,
                .assigned: activityService.pullRequests(for: .assigned).count,
                .mentioned: activityService.pullRequests(for: .mentioned).count,
            ]
        }
    }

    @MainActor
    private func initialLoad() async {
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

    private func shouldAutoRefreshOnTabSelect(_ tab: MenuBarMainTab) -> Bool {
        switch tab {
        case .notifications:
            notificationService.lastSyncedAt == nil
        case .activity:
            activityService.lastSyncedAt == nil
        case .search:
            searchService.lastSyncedAt == nil
        case .watching:
            monitorStore.lastSyncedAt.isEmpty
        }
    }

    @MainActor
    private func refreshCurrentTab() async {
        switch effectiveMainTab {
        case .notifications:
            await notificationService.fetchNotifications()
        case .activity:
            switch selectedSubTab {
            case .all:
                await activityService.fetchMyItems()
            case .issues:
                await activityService.fetchMyItems(type: .issue)
            case .prs:
                await activityService.fetchMyItems(type: .pullRequest)
            }
        case .search:
            await searchService.fetchAll()
        case .watching:
            await monitorEngine.syncAll()
        }
    }

    private func normalizeSelectedMainTabIfNeeded() {
        if !visibleMainTabs.contains(selectedMainTab) {
            selectedMainTab = visibleMainTabs.first ?? .notifications
        }
    }

    @MainActor
    private func markFilteredAsRead() async {
        guard !isMarkingAsRead else { return }
        isMarkingAsRead = true
        defer { isMarkingAsRead = false }

        if effectiveMainTab == .watching {
            monitorStore.markAllEventsRead()
            return
        }

        let notificationsToMark: [GitHubNotification] = switch selectedSubTab {
        case .all:
            notificationService.notifications
        case .issues:
            notificationService.notifications.filter { $0.notificationType == .issue }
        case .prs:
            notificationService.notifications.filter { $0.notificationType == .pullRequest }
        }

        for notification in notificationsToMark {
            await notificationService.markAsRead(notification: notification)
        }
    }

    private func openActivityItem(_ item: SearchResultItem) {
        if let url = item.webURL {
            NSWorkspace.shared.open(url)
        }
    }

    private func openNotificationGroup(_ group: NotificationGroup) {
        let notification = group.latestNotification
        if let url = webURL(for: notification) {
            NSWorkspace.shared.open(url)
            Task {
                for notification in group.notifications {
                    await notificationService.markAsRead(notification: notification)
                }
            }
        }
    }

    private func webURL(for notification: GitHubNotification) -> URL? {
        if let number = notification.issueOrPRNumber {
            let baseURL = notification.repository.htmlUrl
            switch notification.notificationType {
            case .pullRequest:
                return URL(string: "\(baseURL)/pull/\(number)")
            case .issue:
                return URL(string: "\(baseURL)/issues/\(number)")
            default:
                break
            }
        }

        if let apiURLString = notification.subject.url {
            return URL(string: apiURLString
                .replacingOccurrences(of: "api.github.com/repos", with: "github.com")
                .replacingOccurrences(of: "/pulls/", with: "/pull/")
            )
        }

        return URL(string: notification.repository.htmlUrl)
    }

    private func rawBinding<T: RawRepresentable>(
        _ storage: Binding<String>,
        default fallback: T
    ) -> Binding<T> where T.RawValue == String {
        Binding(
            get: { T(rawValue: storage.wrappedValue) ?? fallback },
            set: { storage.wrappedValue = $0.rawValue }
        )
    }

    private var manageAction: (() -> Void)? {
        switch effectiveMainTab {
        case .search:
            { openWindowAndActivate(.searchManagement) }
        case .watching:
            { openWindowAndActivate(.monitorManagement) }
        default:
            nil
        }
    }

    private func clearInitialFocus() {
        Task { @MainActor in
            NSApplication.shared.keyWindow?.makeFirstResponder(nil)
        }
    }

    private func openSettingsAndActivate(tab: SettingsTab? = nil) {
        settingsNavigationState.open(tab: tab)
        closeMenuBarWindow()
        openSettings()
        activateApp()
    }

    private func openWindowAndActivate(_ window: WindowIdentifier) {
        closeMenuBarWindow()
        openWindow(id: window.rawValue)
        activateApp()
    }

    private func activateApp() {
        Task { @MainActor in
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    @MainActor
    private func closeMenuBarWindow() {
        dismiss()
        if let keyWindow = NSApplication.shared.keyWindow {
            keyWindow.performClose(nil)
        }
    }
}

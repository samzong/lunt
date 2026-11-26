import AppKit
import LuntCore
import SwiftUI

struct MenuBarView: View {
    @Environment(NotificationService.self) private var notificationService
    @Environment(ActivityService.self) private var activityService
    @Environment(SearchService.self) private var searchService
    @Environment(MonitorStore.self) private var monitorStore
    @Environment(MonitorEngine.self) private var monitorEngine
    @Environment(WorkspaceNavigationState.self) private var workspaceNavigationState
    @Environment(SettingsNavigationState.self) private var settingsNavigationState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    @AppStorage("menubar.selectedMainTab") private var selectedMainTabRawValue = MenuBarMainTab.inbox.rawValue
    @AppStorage("menubar.inboxScope") private var inboxScopeRawValue = InboxScope.all.rawValue
    @AppStorage("menubar.workTypeFilter") private var workTypeRawValue = WorkItemTypeFilter.all.rawValue
    @AppStorage(UserPreferences.menubarShowInboxTabKey) private var showInboxTab = true
    @AppStorage(UserPreferences.menubarShowWorkTabKey) private var showWorkTab = true
    @AppStorage(UserPreferences.menubarShowWatchTabKey) private var showWatchTab = true

    @State private var workScope: WorkScopeSelection = .role(.all)
    @State private var watchScope: WatchScopeSelection = .all
    @State private var quickFilterOpen = false
    @State private var quickFilterMode: QuickFilterMode = .all
    @State private var activeRowIndex = 0
    @State private var isCommandHeld = false
    @State private var isMarkingAsRead = false
    @State private var popoverNotice: String?
    @State private var noticeTask: Task<Void, Never>?
    @State private var popoverWindow: NSWindow?
    @State private var keyMonitor = PopoverKeyMonitor()

    private enum WorkspaceTarget {
        case monitors
        case searches
    }

    private var visibleTabs: [MenuBarMainTab] {
        var tabs: [MenuBarMainTab] = []
        if showInboxTab {
            tabs.append(.inbox)
        }
        if showWorkTab {
            tabs.append(.work)
        }
        if showWatchTab {
            tabs.append(.watch)
        }
        return tabs.isEmpty ? [.inbox] : tabs
    }

    private var effectiveMainTab: MenuBarMainTab {
        let migrated = MenuBarMainTab.migrating(rawValue: selectedMainTabRawValue)
        return visibleTabs.contains(migrated) ? migrated : (visibleTabs.first ?? .inbox)
    }

    private var inboxScope: InboxScope {
        InboxScope(rawValue: inboxScopeRawValue) ?? .all
    }

    private var workType: WorkItemTypeFilter {
        WorkItemTypeFilter(rawValue: workTypeRawValue) ?? .all
    }

    private var pinnedSearches: [SavedSearch] {
        searchService.savedSearches.filter { $0.isEnabled && $0.isPinned }
    }

    private var activeMonitors: [MonitorDefinition] {
        monitorStore.monitors.filter(\.isEnabled)
    }

    private var alertSearches: [SavedSearch] {
        searchService.savedSearches.filter { $0.isEnabled && $0.watchAlerts }
    }

    private var feedContext: PopoverFeedContext {
        PopoverFeedContext(
            tab: effectiveMainTab,
            inboxScope: inboxScope,
            workScope: workScope,
            workType: workType,
            watchScope: watchScope,
            quickFilterOpen: quickFilterOpen,
            quickFilterMode: quickFilterMode,
            notificationService: notificationService,
            activityService: activityService,
            searchService: searchService,
            monitorStore: monitorStore,
            pinnedSearches: pinnedSearches,
            activeMonitors: activeMonitors,
            alertSearches: alertSearches
        )
    }

    private var scopeResetToken: String {
        "\(inboxScopeRawValue)-\(workScope)-\(workTypeRawValue)-\(watchScope)-\(quickFilterMode)"
    }

    var body: some View {
        VStack(spacing: 0) {
            if notificationService.isAuthenticated {
                HeaderView(
                    selectedTab: mainTabBinding,
                    visibleTabs: visibleTabs,
                    inboxUnread: notificationService.unreadCount,
                    watchUnread: watchUnreadCount,
                    quickFilterOpen: quickFilterOpen,
                    isSyncing: isCurrentTabSyncing,
                    currentUserLogin: notificationService.currentUser?.login,
                    onToggleQuickFilter: toggleQuickFilter,
                    onSync: { Task { await refreshCurrentTab() } },
                    onOpenWorkspace: { openWorkspace(.monitors) },
                    onOpenSettings: { openSettingsAndActivate() },
                    onQuit: { NSApplication.shared.terminate(nil) }
                )

                ScopeBarView(
                    mainTab: effectiveMainTab,
                    inboxScope: rawBinding($inboxScopeRawValue, default: .all),
                    inboxCounts: PopoverFeedProjection.inboxCounts(from: notificationService),
                    inboxUnread: notificationService.unreadCount,
                    workScope: $workScope,
                    workType: rawBinding($workTypeRawValue, default: .all),
                    workRoleCounts: PopoverFeedProjection.workRoleCounts(from: activityService, workType: workType),
                    pinnedSearches: pinnedSearches,
                    pinnedSearchCounts: PopoverFeedProjection.pinnedSearchCounts(
                        from: searchService,
                        pinnedSearches: pinnedSearches,
                        workType: workType
                    ),
                    watchScope: $watchScope,
                    watchUnread: watchUnreadCount,
                    activeMonitors: activeMonitors,
                    alertSearches: alertSearches,
                    isMarkingRead: isMarkingAsRead,
                    onMarkRead: { Task { await markCurrentTabRead() } },
                    onManageWork: { openWorkspace(.searches) },
                    onManageWatch: { openWorkspace(.monitors) }
                )

                if quickFilterOpen {
                    QuickFilterDrawerView(selectedMode: $quickFilterMode, onClose: closeQuickFilter)
                }

                contentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                WelcomeView(onOpenSettings: { openSettingsAndActivate(tab: .account) })
            }

            StatusStripView(
                notice: popoverNotice,
                isSyncing: isCurrentTabSyncing,
                lastSyncedAt: PopoverFeedProjection.lastSyncedAt(for: feedContext),
                isAuthenticated: notificationService.isAuthenticated
            )
        }
        .frame(width: 420, height: 500)
        .background(PopoverWindowAccessor { window in
            popoverWindow = window
            keyMonitor.handler = { handleLocalEvent($0) }
        })
        .liquidReadableWindowBackground()
        .liquidAutomaticScrollEdgeEffect(for: .top)
        .task {
            normalizeSelectedMainTabIfNeeded()
            clearInitialFocus()
            await PopoverFeedProjection.initialLoad(
                notificationService: notificationService,
                activityService: activityService,
                searchService: searchService,
                monitorStore: monitorStore,
                monitorEngine: monitorEngine
            )
        }
        .onAppear {
            keyMonitor.handler = { handleLocalEvent($0) }
            keyMonitor.start()
        }
        .onDisappear {
            keyMonitor.stop()
            isCommandHeld = false
            noticeTask?.cancel()
        }
        .onChange(of: visibleTabs) { _, _ in normalizeSelectedMainTabIfNeeded() }
        .onChange(of: selectedMainTabRawValue) { _, _ in
            activeRowIndex = 0
            if PopoverFeedProjection.shouldAutoRefresh(context: feedContext) {
                Task { await refreshCurrentTab() }
            }
        }
        .onChange(of: scopeResetToken) { _, _ in activeRowIndex = 0 }
        .onChange(of: currentRows.map(\.id)) { _, ids in
            if activeRowIndex >= ids.count {
                activeRowIndex = max(0, ids.count - 1)
            }
        }
    }

    @ViewBuilder private var contentView: some View {
        let rows = currentRows
        let errorMessage = PopoverFeedProjection.errorMessage(for: feedContext, monitorEngine: monitorEngine)
        if isCurrentTabSyncing, rows.isEmpty {
            calmStateView(.loading)
        } else if !rows.isEmpty {
            VStack(spacing: 0) {
                if let errorMessage {
                    InlineErrorBanner(message: errorMessage)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                UnifiedItemRow(
                                    model: row,
                                    isActive: index == activeRowIndex,
                                    isCommandHeld: isCommandHeld,
                                    shortcutNumber: index < 9 ? index + 1 : nil,
                                    onOpen: { openRow(row, at: index) },
                                    onToggleRead: canToggleRead(row) ? { toggleRead(row) } : nil
                                )
                                .id(row.id)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .onChange(of: activeRowIndex) { _, newIndex in
                        guard rows.indices.contains(newIndex) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(rows[newIndex].id, anchor: .center)
                        }
                    }
                }
            }
        } else if let errorMessage {
            calmStateView(.error(errorMessage))
        } else {
            calmStateView(
                .empty(
                    isWatch: effectiveMainTab == .watch,
                    isFiltered: quickFilterOpen && quickFilterMode != .all
                )
            )
        }
    }

    private func calmStateView(_ mode: PopoverCalmMode) -> some View {
        PopoverCalmStateView(
            mode: mode,
            onRetry: { Task { await refreshCurrentTab() } },
            onAccountSettings: { openSettingsAndActivate(tab: .account) },
            onManageWatch: { openWorkspace(.monitors) }
        )
    }

    private var currentRows: [UnifiedRowModel] {
        PopoverFeedProjection.buildRows(from: feedContext)
    }

    private var watchUnreadCount: Int {
        PopoverFeedProjection.watchEvents(
            from: monitorStore.events,
            scope: .all,
            activeMonitors: activeMonitors,
            alertSearches: alertSearches
        ).count { !$0.isRead }
    }

    private var isCurrentTabSyncing: Bool {
        switch effectiveMainTab {
        case .inbox: notificationService.isLoading
        case .work: activityService.isLoading || searchService.isLoading
        case .watch: monitorEngine.isSyncing
        }
    }
}

extension MenuBarView {
    private func canToggleRead(_ row: UnifiedRowModel) -> Bool {
        switch row.source {
        case .notification, .monitorEvent: true
        case .searchResult: false
        }
    }

    private func openRow(_ row: UnifiedRowModel, at index: Int) {
        activeRowIndex = index
        if let url = row.url {
            NSWorkspace.shared.open(url)
        }
        showNotice(formattedNotice(key: "menubar.status.opened", argument: row.shortLabel))
        switch row.source {
        case let .notification(group):
            Task { await notificationService.markGroupAsRead(group) }
        case let .monitorEvent(event) where !event.isRead:
            monitorStore.toggleEventRead(id: event.id)
        default:
            break
        }
        closeMenuBarWindow()
    }

    private func toggleRead(_ row: UnifiedRowModel) {
        switch row.source {
        case let .notification(group):
            Task { await notificationService.markGroupAsRead(group) }
        case let .monitorEvent(event):
            monitorStore.toggleEventRead(id: event.id)
        case .searchResult:
            showNotice("menubar.status.ready".localized)
        }
    }

    @MainActor
    private func markCurrentTabRead() async {
        guard !isMarkingAsRead else { return }
        isMarkingAsRead = true
        defer { isMarkingAsRead = false }

        if let message = await PopoverFeedProjection.markCurrentTabRead(context: feedContext) {
            showNotice(message)
        }
    }

    @MainActor
    private func refreshCurrentTab() async {
        await PopoverFeedProjection.refresh(context: feedContext, monitorEngine: monitorEngine)
    }

    private func normalizeSelectedMainTabIfNeeded() {
        let migrated = MenuBarMainTab.migrating(rawValue: selectedMainTabRawValue)
        if visibleTabs.contains(migrated) {
            if selectedMainTabRawValue != migrated.rawValue {
                selectedMainTabRawValue = migrated.rawValue
            }
        } else if let fallback = visibleTabs.first {
            selectedMainTabRawValue = fallback.rawValue
        }
    }

    private func toggleQuickFilter() {
        quickFilterOpen.toggle()
        if !quickFilterOpen {
            quickFilterMode = .all
        }
    }

    private func closeQuickFilter() {
        quickFilterOpen = false
        quickFilterMode = .all
    }

    private func showNotice(_ message: String) {
        popoverNotice = message
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            popoverNotice = nil
        }
    }

    private func formattedNotice(key: String, argument: String) -> String {
        let template = key.localized
        return template.contains("%@") ? String(format: template, argument) : "\(template) \(argument)"
    }

    private var mainTabBinding: Binding<MenuBarMainTab> {
        Binding(get: { effectiveMainTab }, set: { selectedMainTabRawValue = $0.rawValue })
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

    private func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
        guard let popoverWindow, popoverWindow.isKeyWindow else {
            if event.type == .flagsChanged {
                isCommandHeld = false
            }
            return event
        }
        if event.type == .flagsChanged {
            isCommandHeld = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
            return event
        }
        guard event.type == .keyDown, !(popoverWindow.firstResponder is NSTextView) else { return event }

        let rows = currentRows
        guard let action = PopoverKeyMonitor.action(
            for: event,
            quickFilterOpen: quickFilterOpen,
            hasRows: !rows.isEmpty
        ) else {
            return event
        }

        switch action {
        case .closeQuickFilter:
            closeQuickFilter()
        case let .openShortcut(index):
            guard rows.indices.contains(index) else { return event }
            openRow(rows[index], at: index)
        case .refresh:
            Task { await refreshCurrentTab() }
        case .toggleQuickFilter:
            toggleQuickFilter()
        case let .moveSelection(delta):
            activeRowIndex = max(0, min(rows.count - 1, activeRowIndex + delta))
        case .openSelected:
            guard rows.indices.contains(activeRowIndex) else { return event }
            openRow(rows[activeRowIndex], at: activeRowIndex)
        case .toggleReadSelected:
            guard rows.indices.contains(activeRowIndex) else { return event }
            toggleRead(rows[activeRowIndex])
        }
        return nil
    }

    private func clearInitialFocus() {
        Task { @MainActor in NSApplication.shared.keyWindow?.makeFirstResponder(nil) }
    }

    private func openSettingsAndActivate(tab: SettingsTab? = nil) {
        settingsNavigationState.open(tab: tab)
        closeMenuBarWindow()
        openSettings()
        activateApp()
    }

    private func openWorkspace(_ target: WorkspaceTarget) {
        switch target {
        case .monitors: workspaceNavigationState.open(mode: .monitors)
        case .searches: workspaceNavigationState.open(mode: .searches)
        }
        closeMenuBarWindow()
        openWindow(id: WindowIdentifier.workspace.rawValue)
        activateApp()
    }

    private func activateApp() {
        Task { @MainActor in NSApplication.shared.activate(ignoringOtherApps: true) }
    }

    @MainActor
    private func closeMenuBarWindow() {
        dismiss()
        if let keyWindow = NSApplication.shared.keyWindow {
            keyWindow.performClose(nil)
        }
    }
}

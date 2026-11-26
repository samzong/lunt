import AppKit
import LuntCore
import Sparkle
import SwiftUI

@main
struct LuntApp: App {
    @State private var session: GitHubSession
    @State private var notificationService: NotificationService
    @State private var activityService: ActivityService
    @State private var searchService: SearchService
    @State private var ruleStorage = RuleStorage()
    @State private var settingsNavigationState = SettingsNavigationState()
    @State private var workspaceNavigationState = WorkspaceNavigationState()
    @State private var monitorStore: MonitorStore
    @State private var monitorEngine: MonitorEngine
    @State private var deviceFlowController: DeviceFlowController
    @State private var startupTask: Task<Void, Never>?
    private let appConfiguration: AppConfiguration
    private let updaterController: SPUStandardUpdaterController

    init() {
        let configuration = AppConfiguration.load()
        appConfiguration = configuration

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        let sessionInstance = GitHubSession()
        _session = State(initialValue: sessionInstance)

        let service = NotificationService(session: sessionInstance)
        _notificationService = State(initialValue: service)

        let itemsService = ActivityService(session: sessionInstance)
        _activityService = State(initialValue: itemsService)

        let search = SearchService(session: sessionInstance)
        _searchService = State(initialValue: search)

        let storage = RuleStorage()
        _ruleStorage = State(initialValue: storage)

        let store = MonitorStore()
        _monitorStore = State(initialValue: store)

        let engine = MonitorEngine(session: sessionInstance, store: store, notificationManager: NotificationManager.shared)
        _monitorEngine = State(initialValue: engine)

        let flowServices = DeviceFlowServices(
            session: sessionInstance,
            notificationService: service,
            activityService: itemsService,
            searchService: search,
            monitorStore: store,
            monitorEngine: engine
        )
        _deviceFlowController = State(
            initialValue: DeviceFlowController(
                oauthClientID: configuration.githubOAuthClientID,
                services: flowServices
            )
        )

        NotificationManager.shared.notificationService = service
        NotificationManager.shared.monitorStore = store
        service.ruleStorage = storage
        search.monitorStore = store
        search.notificationManager = NotificationManager.shared
        store.migrateLegacyMonitors(into: search)
        MenuBarMainTab.migrateLegacyVisibilityKeysIfNeeded()

        let configuredInterval = UserDefaults.standard.double(forKey: UserPreferences.refreshIntervalKey)
        let interval = configuredInterval > 0 ? configuredInterval : 60

        _startupTask = State(initialValue: Task { @MainActor in
            if let token = await AuthStore.shared.currentToken() {
                guard !Task.isCancelled else { return }
                sessionInstance.configure(token: token)
                service.startAutoRefresh(interval: interval)
                itemsService.configure(interval: interval)
                search.configure()
                search.updateRefreshInterval(interval)

                await service.fetchCurrentUser()
                guard !Task.isCancelled, sessionInstance.isAuthenticated else { return }
                await service.fetchNotifications()
                guard !Task.isCancelled, sessionInstance.isAuthenticated else { return }
                await itemsService.fetchMyItems()
                guard !Task.isCancelled, sessionInstance.isAuthenticated else { return }
                await search.fetchAll()
                guard !Task.isCancelled, sessionInstance.isAuthenticated else { return }

                engine.start(interval: interval)
            }

            if UserDefaults.standard.bool(forKey: "enableSystemNotifications") {
                _ = await NotificationManager.shared.requestAuthorization()
            }
        })
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(session)
                .environment(notificationService)
                .environment(activityService)
                .environment(searchService)
                .environment(monitorStore)
                .environment(monitorEngine)
                .environment(deviceFlowController)
                .environment(workspaceNavigationState)
                .environment(settingsNavigationState)
        } label: {
            MenuBarLabel(unreadCount: notificationService.unreadCount)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: session.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                let configured = UserDefaults.standard.double(forKey: UserPreferences.refreshIntervalKey)
                monitorEngine.start(interval: configured > 0 ? configured : 60)
            } else {
                startupTask?.cancel()
                startupTask = nil
                monitorEngine.stop()
                monitorStore.clearEvents()
            }
        }

        Settings {
            SettingsView(
                updater: updaterController.updater
            )
            .environment(session)
            .environment(notificationService)
            .environment(activityService)
            .environment(searchService)
            .environment(ruleStorage)
            .environment(monitorStore)
            .environment(monitorEngine)
            .environment(deviceFlowController)
            .environment(settingsNavigationState)
        }

        Window(WindowIdentifier.workspace.title, id: WindowIdentifier.workspace.rawValue) {
            WorkspaceWindowView()
                .environment(session)
                .environment(searchService)
                .environment(monitorStore)
                .environment(monitorEngine)
                .environment(workspaceNavigationState)
        }
        .defaultSize(
            width: WindowIdentifier.workspace.defaultSize.width,
            height: WindowIdentifier.workspace.defaultSize.height
        )
    }
}

struct MenuBarLabel: View {
    let unreadCount: Int

    @AppStorage(UserPreferences.showNotificationCountKey) private var showCount = true

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: menuBarIcon)
            if unreadCount > 0, showCount {
                Text("\(unreadCount)")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
        }
    }

    private var menuBarIcon: NSImage {
        let imageName = unreadCount > 0 ? "GitHubLogoUnread" : "GitHubLogo"
        guard let image = NSImage(named: imageName) else {
            return NSImage()
        }
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }
}

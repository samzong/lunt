import LuntCore
import os
import ServiceManagement
import SwiftUI

struct GeneralTab: View {
    @Environment(NotificationService.self) private var notificationService
    @Environment(ActivityService.self) private var activityService
    @Environment(SearchService.self) private var searchService
    @Environment(MonitorEngine.self) private var monitorEngine

    @AppStorage(UserPreferences.refreshIntervalKey) private var refreshInterval: Double = 60
    @AppStorage(UserPreferences.showNotificationCountKey) private var showNotificationCount = true
    @AppStorage(UserPreferences.launchAtLoginKey) private var launchAtLogin = false
    @AppStorage(UserPreferences.menubarShowInboxTabKey) private var showInboxTab = true
    @AppStorage(UserPreferences.menubarShowWorkTabKey) private var showWorkTab = true
    @AppStorage(UserPreferences.menubarShowWatchTabKey) private var showWatchTab = true
    @AppStorage("enableSystemNotifications") private var enableSystemNotifications = false

    @State private var isTestingNotification = false

    let settingsWidth: CGFloat

    private let logger = Logger(subsystem: "com.samzong.lunt", category: "GeneralTab")

    private let refreshOptions: [(seconds: Double, label: String)] = [
        (60, "settings.refresh.1min".localized),
        (120, "settings.refresh.2min".localized),
        (300, "settings.refresh.5min".localized),
        (600, "settings.refresh.10min".localized),
    ]

    private var enabledMainTabCount: Int {
        [showInboxTab, showWorkTab, showWatchTab].count(where: { $0 })
    }

    var body: some View {
        Form {
            Section {
                Picker("settings.refresh.title".localized, selection: $refreshInterval) {
                    ForEach(refreshOptions, id: \.seconds) { option in
                        Text(option.label).tag(option.seconds)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: refreshInterval) { _, newValue in
                    notificationService.startAutoRefresh(interval: newValue)
                    activityService.updateRefreshInterval(newValue)
                    searchService.updateRefreshInterval(newValue)
                    monitorEngine.start(interval: newValue)
                }

                Toggle("settings.menubar.show_count".localized, isOn: $showNotificationCount)

                Toggle("settings.startup.launch".localized, isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }

            Section {
                Toggle("settings.notifications.enable".localized, isOn: $enableSystemNotifications)
                    .onChange(of: enableSystemNotifications) { _, newValue in
                        if newValue {
                            requestNotificationPermission()
                        }
                    }

                if enableSystemNotifications {
                    HStack {
                        Button("settings.notifications.test".localized) {
                            sendTestNotification()
                        }
                        .disabled(isTestingNotification)

                        if isTestingNotification {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.leading, 4)
                        }
                    }

                    Text("settings.notifications.description".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("settings.notifications.section".localized)
            }

            Section {
                Toggle("settings.menubar.tabs.inbox".localized, isOn: $showInboxTab)
                    .disabled(showInboxTab && enabledMainTabCount == 1)

                Toggle("settings.menubar.tabs.work".localized, isOn: $showWorkTab)
                    .disabled(showWorkTab && enabledMainTabCount == 1)

                Toggle("settings.menubar.tabs.watch".localized, isOn: $showWatchTab)
                    .disabled(showWatchTab && enabledMainTabCount == 1)

                Text("settings.menubar.tabs.description".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("settings.menubar.tabs.minimum_one".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("settings.menubar.tabs.section".localized)
            }
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth)
        .onAppear {
            normalizeMainTabVisibilityIfNeeded()
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let action = enabled ? "enable" : "disable"
            let message = error.localizedDescription
            logger.error("Failed to \(action, privacy: .public) launch at login: \(message, privacy: .public)")
        }
    }

    private func requestNotificationPermission() {
        Task {
            let granted = await NotificationManager.shared.requestAuthorization()
            if !granted {
                await MainActor.run {
                    enableSystemNotifications = false
                }
            }
        }
    }

    private func sendTestNotification() {
        isTestingNotification = true
        Task {
            await NotificationManager.shared.sendTestNotification()
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                isTestingNotification = false
            }
        }
    }

    private func normalizeMainTabVisibilityIfNeeded() {
        if !showInboxTab, !showWorkTab, !showWatchTab {
            showInboxTab = true
        }
    }
}

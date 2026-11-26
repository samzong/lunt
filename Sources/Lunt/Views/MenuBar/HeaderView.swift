import LuntCore
import SwiftUI

struct HeaderView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var tabAnimation

    @Binding var selectedTab: MenuBarMainTab
    let visibleTabs: [MenuBarMainTab]
    let inboxUnread: Int
    let watchUnread: Int
    let quickFilterOpen: Bool
    let isSyncing: Bool
    let isAuthenticated: Bool
    let currentUserLogin: String?

    let onToggleQuickFilter: () -> Void
    let onSync: () -> Void
    let onOpenWorkspace: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            tabPlatter
                .disabled(!isAuthenticated)
                .opacity(isAuthenticated ? 1 : 0.45)

            Spacer(minLength: 4)

            HStack(spacing: 2) {
                quickFilterButton
                    .disabled(!isAuthenticated)
                    .opacity(isAuthenticated ? 1 : 0.45)
                syncButton
                    .opacity(isAuthenticated ? 1 : 0.45)
                settingsMenu
            }
        }
        .frame(height: 48)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .animation(
            reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78),
            value: selectedTab
        )
    }

    private var tabPlatter: some View {
        HStack(spacing: 2) {
            ForEach(visibleTabs, id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private func tabButton(for tab: MenuBarMainTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            switchTab(to: tab)
        } label: {
            HStack(spacing: 5) {
                Text(tab.titleKey.localized)
                    .font(.system(size: 12, weight: .medium))

                if shouldShowDot(for: tab) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(height: 28)
            .padding(.horizontal, 11)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                        .matchedGeometryEffect(id: "activeHeaderTab", in: tabAnimation)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var quickFilterButton: some View {
        Button(action: onToggleQuickFilter) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(quickFilterOpen ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    quickFilterOpen ? Color(nsColor: .controlBackgroundColor) : Color.clear,
                    in: Circle()
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            quickFilterOpen ? Color.primary.opacity(0.14) : Color.clear,
                            lineWidth: 1
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("menubar.quick_filter".localized)
        .accessibilityLabel(Text("menubar.quick_filter".localized))
    }

    private var syncButton: some View {
        Button(action: onSync) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isSyncing && !reduceMotion ? 360 : 0))
                .animation(
                    isSyncing && !reduceMotion
                        ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                        : .default,
                    value: isSyncing
                )
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isAuthenticated || isSyncing)
        .help("menubar.refresh".localized)
        .accessibilityLabel(Text("menubar.refresh".localized))
    }

    private var settingsMenu: some View {
        Menu {
            if let login = currentUserLogin {
                Text("settings.user".localized + ": @\(login)")
                Divider()
            }

            Button {
                onOpenWorkspace()
            } label: {
                Label("workspace.title".localized, systemImage: "square.grid.2x2")
            }
            .disabled(!isAuthenticated)

            Button {
                onOpenSettings()
            } label: {
                Label("settings.title".localized, systemImage: "gearshape")
            }

            Divider()

            Button(role: .destructive) {
                onQuit()
            } label: {
                Label("menubar.quit".localized, systemImage: "xmark.circle")
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .controlSize(.small)
        .liquidGlassIconButtonStyle()
        .help("settings.title".localized)
    }

    private func shouldShowDot(for tab: MenuBarMainTab) -> Bool {
        switch tab {
        case .inbox:
            inboxUnread > 0
        case .work:
            false
        case .watch:
            watchUnread > 0
        }
    }

    private func switchTab(to tab: MenuBarMainTab) {
        guard selectedTab != tab else { return }
        if reduceMotion {
            selectedTab = tab
        } else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                selectedTab = tab
            }
        }
    }
}

import Foundation
import LuntCore

public enum MenuBarMainTab: String, CaseIterable, Identifiable, Sendable {
    case inbox
    case work
    case watch

    public static let displayOrder: [MenuBarMainTab] = [.inbox, .work, .watch]

    public var id: String {
        rawValue
    }

    public var titleKey: String {
        switch self {
        case .inbox:
            "menubar.tab.inbox"
        case .work:
            "menubar.tab.work"
        case .watch:
            "menubar.tab.watch"
        }
    }

    public var visibilityPreferenceKey: String {
        switch self {
        case .inbox:
            UserPreferences.menubarShowInboxTabKey
        case .work:
            UserPreferences.menubarShowWorkTabKey
        case .watch:
            UserPreferences.menubarShowWatchTabKey
        }
    }

    public static func migrating(rawValue: String) -> MenuBarMainTab {
        switch rawValue {
        case "notifications":
            .inbox
        case "activity", "search":
            .work
        case "watching":
            .watch
        default:
            MenuBarMainTab(rawValue: rawValue) ?? .inbox
        }
    }

    public func isVisible(in defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: visibilityPreferenceKey) != nil {
            return defaults.bool(forKey: visibilityPreferenceKey)
        }

        switch self {
        case .inbox:
            if defaults.object(forKey: UserPreferences.menubarShowNotificationsTabKey) != nil {
                return defaults.bool(forKey: UserPreferences.menubarShowNotificationsTabKey)
            }
            return true
        case .work:
            let hasActivityKey = defaults.object(forKey: UserPreferences.menubarShowActivityTabKey) != nil
            let hasSearchKey = defaults.object(forKey: UserPreferences.menubarShowSearchTabKey) != nil
            if hasActivityKey || hasSearchKey {
                let showActivity = hasActivityKey ? defaults.bool(forKey: UserPreferences.menubarShowActivityTabKey) : true
                let showSearch = hasSearchKey ? defaults.bool(forKey: UserPreferences.menubarShowSearchTabKey) : true
                return showActivity || showSearch
            }
            return true
        case .watch:
            if defaults.object(forKey: UserPreferences.menubarShowWatchingTabKey) != nil {
                return defaults.bool(forKey: UserPreferences.menubarShowWatchingTabKey)
            }
            return true
        }
    }

    public static func visibleTabs(from defaults: UserDefaults = .standard) -> [MenuBarMainTab] {
        let tabs = displayOrder.filter { $0.isVisible(in: defaults) }
        return tabs.isEmpty ? [fallbackTab(from: defaults)] : tabs
    }

    public static func fallbackTab(from defaults: UserDefaults = .standard) -> MenuBarMainTab {
        displayOrder.first(where: { $0.isVisible(in: defaults) }) ?? .inbox
    }

    public static func migrateLegacyVisibilityKeysIfNeeded(in defaults: UserDefaults = .standard) {
        for tab in displayOrder where defaults.object(forKey: tab.visibilityPreferenceKey) == nil {
            defaults.set(tab.isVisible(in: defaults), forKey: tab.visibilityPreferenceKey)
        }
    }
}

public enum InboxScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case prs
    case issues

    public var id: String {
        rawValue
    }
}

public enum WorkItemTypeFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case prs
    case issues

    public var id: String {
        rawValue
    }

    public var next: WorkItemTypeFilter {
        switch self {
        case .all:
            .prs
        case .prs:
            .issues
        case .issues:
            .all
        }
    }
}

public enum QuickFilterMode: String, CaseIterable, Identifiable, Sendable {
    case all
    case unread
    case prs
    case ciAttention = "ci-fail"

    public var id: String {
        rawValue
    }
}

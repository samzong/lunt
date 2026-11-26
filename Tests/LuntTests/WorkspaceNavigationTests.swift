import Foundation
@testable import Lunt
import LuntCore
import XCTest

final class WorkspaceNavigationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "WorkspaceNavigationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_migratingRawValue_mapsLegacyAndCurrentValues() {
        XCTAssertEqual(MenuBarMainTab.migrating(rawValue: "notifications"), .inbox)
        XCTAssertEqual(MenuBarMainTab.migrating(rawValue: "activity"), .work)
        XCTAssertEqual(MenuBarMainTab.migrating(rawValue: "search"), .work)
        XCTAssertEqual(MenuBarMainTab.migrating(rawValue: "watching"), .watch)
        XCTAssertEqual(MenuBarMainTab.migrating(rawValue: "inbox"), .inbox)
        XCTAssertEqual(MenuBarMainTab.migrating(rawValue: "work"), .work)
        XCTAssertEqual(MenuBarMainTab.migrating(rawValue: "watch"), .watch)
        XCTAssertEqual(MenuBarMainTab.migrating(rawValue: "unknown"), .inbox)
    }

    func test_visibleTabs_defaultsToAllThreeTabs() {
        XCTAssertEqual(MenuBarMainTab.visibleTabs(from: defaults), [.inbox, .work, .watch])
    }

    func test_visibleTabs_respectsNewVisibilityKeys() {
        defaults.set(false, forKey: UserPreferences.menubarShowInboxTabKey)
        defaults.set(true, forKey: UserPreferences.menubarShowWorkTabKey)
        defaults.set(false, forKey: UserPreferences.menubarShowWatchTabKey)

        XCTAssertEqual(MenuBarMainTab.visibleTabs(from: defaults), [.work])
    }

    func test_visibleTabs_migratesLegacyVisibilityKeysWhenNewKeysAbsent() {
        defaults.set(false, forKey: UserPreferences.menubarShowNotificationsTabKey)
        defaults.set(false, forKey: UserPreferences.menubarShowActivityTabKey)
        defaults.set(false, forKey: UserPreferences.menubarShowSearchTabKey)
        defaults.set(true, forKey: UserPreferences.menubarShowWatchingTabKey)

        XCTAssertEqual(MenuBarMainTab.visibleTabs(from: defaults), [.watch])
    }

    func test_visibleTabs_workRemainsVisibleWhenOnlyOneLegacyWorkTabWasHidden() {
        defaults.set(false, forKey: UserPreferences.menubarShowActivityTabKey)
        defaults.set(true, forKey: UserPreferences.menubarShowSearchTabKey)

        XCTAssertEqual(MenuBarMainTab.visibleTabs(from: defaults), [.inbox, .work, .watch])
    }

    func test_visibleTabs_newKeysOverrideLegacyKeys() {
        defaults.set(false, forKey: UserPreferences.menubarShowNotificationsTabKey)
        defaults.set(true, forKey: UserPreferences.menubarShowInboxTabKey)
        defaults.set(false, forKey: UserPreferences.menubarShowWorkTabKey)
        defaults.set(false, forKey: UserPreferences.menubarShowWatchTabKey)

        XCTAssertEqual(MenuBarMainTab.visibleTabs(from: defaults), [.inbox])
    }

    func test_visibleTabs_fallsBackToInboxWhenAllDisabled() {
        defaults.set(false, forKey: UserPreferences.menubarShowInboxTabKey)
        defaults.set(false, forKey: UserPreferences.menubarShowWorkTabKey)
        defaults.set(false, forKey: UserPreferences.menubarShowWatchTabKey)

        XCTAssertEqual(MenuBarMainTab.visibleTabs(from: defaults), [.inbox])
        XCTAssertEqual(MenuBarMainTab.fallbackTab(from: defaults), .inbox)
    }

    func test_workItemTypeFilter_cyclesInOrder() {
        XCTAssertEqual(WorkItemTypeFilter.all.next, .prs)
        XCTAssertEqual(WorkItemTypeFilter.prs.next, .issues)
        XCTAssertEqual(WorkItemTypeFilter.issues.next, .all)
    }

    @MainActor
    func test_workspaceNavigationState_openAndConsumePendingNavigation() {
        let state = WorkspaceNavigationState()
        XCTAssertEqual(state.selectedMode, .monitors)
        XCTAssertNil(state.consumePendingNavigation())

        state.open(mode: .searches, createNew: true)
        XCTAssertEqual(state.selectedMode, .searches)

        let pending = state.consumePendingNavigation()
        XCTAssertEqual(pending?.mode, .searches)
        XCTAssertEqual(pending?.createNew, true)
        XCTAssertNil(state.consumePendingNavigation())

        state.open(mode: .monitors)
        let secondPending = state.consumePendingNavigation()
        XCTAssertEqual(secondPending?.mode, .monitors)
        XCTAssertEqual(secondPending?.createNew, false)
    }
}

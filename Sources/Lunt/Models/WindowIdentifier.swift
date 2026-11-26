import Foundation

public enum WindowIdentifier: String, CaseIterable, Identifiable, Sendable {
    case searchManagement = "search-management"
    case monitorManagement = "monitor-management"

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .searchManagement:
            "search.management.title".localized
        case .monitorManagement:
            "monitor.management.title".localized
        }
    }

    public var defaultSize: (width: CGFloat, height: CGFloat) {
        switch self {
        case .searchManagement:
            (720, 520)
        case .monitorManagement:
            (760, 560)
        }
    }
}

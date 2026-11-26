import Foundation

public enum WindowIdentifier: String, CaseIterable, Identifiable, Sendable {
    case workspace

    public var id: String {
        rawValue
    }

    public var title: String {
        "workspace.title".localized
    }

    public var defaultSize: (width: CGFloat, height: CGFloat) {
        (900, 520)
    }
}

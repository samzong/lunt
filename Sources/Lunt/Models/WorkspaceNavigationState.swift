import Observation

public enum WorkspaceMode: String, CaseIterable, Identifiable, Sendable {
    case monitors
    case searches

    public var id: String {
        rawValue
    }
}

@MainActor
@Observable
public final class WorkspaceNavigationState {
    public var selectedMode: WorkspaceMode = .monitors
    public private(set) var pendingMode: WorkspaceMode?
    public private(set) var pendingCreateNew = false

    public init() {}

    public func open(mode: WorkspaceMode, createNew: Bool = false) {
        selectedMode = mode
        pendingMode = mode
        pendingCreateNew = createNew
    }

    public func consumePendingNavigation() -> (mode: WorkspaceMode, createNew: Bool)? {
        guard let mode = pendingMode else { return nil }
        let createNew = pendingCreateNew
        pendingMode = nil
        pendingCreateNew = false
        return (mode, createNew)
    }
}

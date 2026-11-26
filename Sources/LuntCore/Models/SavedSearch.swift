import Foundation

public enum SearchType: String, Codable, CaseIterable, Sendable, Identifiable {
    case all
    case issue
    case pr
    case repository

    public var id: String {
        rawValue
    }

    public var icon: String {
        switch self {
        case .all: "magnifyingglass"
        case .issue: "dot.circle"
        case .pr: "arrow.triangle.pull"
        case .repository: "folder"
        }
    }

    public var displayName: String {
        switch self {
        case .all: "All"
        case .issue: "Issues"
        case .pr: "Pull Requests"
        case .repository: "Repositories"
        }
    }
}

public struct SavedSearch: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var query: String
    public var isEnabled: Bool
    public var isPinned: Bool
    public var type: SearchType
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        query: String,
        isEnabled: Bool = true,
        isPinned: Bool = false,
        type: SearchType = .all,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.query = query
        self.isEnabled = isEnabled
        self.isPinned = isPinned
        self.type = type
        self.createdAt = createdAt
    }
}

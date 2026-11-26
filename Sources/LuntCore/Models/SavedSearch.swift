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
    public var watchAlerts: Bool
    public var createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case query
        case isEnabled
        case isPinned
        case type
        case watchAlerts
        case createdAt
    }

    public init(
        id: UUID = UUID(),
        name: String,
        query: String,
        isEnabled: Bool = true,
        isPinned: Bool = false,
        type: SearchType = .all,
        watchAlerts: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.query = query
        self.isEnabled = isEnabled
        self.isPinned = isPinned
        self.type = type
        self.watchAlerts = watchAlerts
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        query = try container.decode(String.self, forKey: .query)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        type = try container.decode(SearchType.self, forKey: .type)
        watchAlerts = try container.decodeIfPresent(Bool.self, forKey: .watchAlerts) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

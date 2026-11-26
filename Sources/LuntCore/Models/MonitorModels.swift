import Foundation

public enum MonitorTarget: Codable, Equatable, Sendable {
    case account(login: String)
    case repository(owner: String, name: String)

    public var idString: String {
        switch self {
        case let .account(login):
            "account:\(login.lowercased())"
        case let .repository(owner, name):
            "repo:\(owner.lowercased())/\(name.lowercased())"
        }
    }

    public var displayName: String {
        switch self {
        case let .account(login):
            "@\(login)"
        case let .repository(owner, name):
            "\(owner)/\(name)"
        }
    }

    public var badgeLabel: String {
        switch self {
        case let .account(login):
            "account:\(login)"
        case let .repository(owner, name):
            "repository:\(owner)/\(name)"
        }
    }
}

public struct MonitorDefinition: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var target: MonitorTarget
    public var name: String?
    public var isEnabled: Bool
    public var eventToggles: [String: Bool]

    public init(
        id: UUID = UUID(),
        target: MonitorTarget,
        name: String? = nil,
        isEnabled: Bool = true,
        eventToggles: [String: Bool] = [:]
    ) {
        self.id = id
        self.target = target
        self.name = name
        self.isEnabled = isEnabled
        self.eventToggles = eventToggles
    }

    public var displayName: String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return target.displayName
    }
}

public struct MonitorEvent: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: String
    public let targetId: UUID
    public let actor: String
    public let repo: String
    public let title: String
    public let url: String
    public let occurredAt: Date
    public let number: Int?
    public var isRead: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case targetId
        case actor
        case repo
        case title
        case url
        case occurredAt
        case number
        case isRead
    }

    public init(
        id: String,
        kind: String,
        targetId: UUID,
        actor: String,
        repo: String,
        title: String,
        url: String,
        occurredAt: Date,
        number: Int? = nil,
        isRead: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.targetId = targetId
        self.actor = actor
        self.repo = repo
        self.title = title
        self.url = url
        self.occurredAt = occurredAt
        self.number = number
        self.isRead = isRead
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(String.self, forKey: .kind)
        targetId = try container.decode(UUID.self, forKey: .targetId)
        actor = try container.decode(String.self, forKey: .actor)
        repo = try container.decode(String.self, forKey: .repo)
        title = try container.decode(String.self, forKey: .title)
        url = try container.decode(String.self, forKey: .url)
        occurredAt = try container.decode(Date.self, forKey: .occurredAt)
        let decodedNumber = try container.decodeIfPresent(Int.self, forKey: .number)
        number = decodedNumber ?? Self.parseNumber(from: url)
        isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
    }

    static func parseNumber(from urlString: String) -> Int? {
        let pathComponents: [String]
        if let parsedURL = URL(string: urlString) {
            pathComponents = parsedURL.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        } else {
            let pathOnly = urlString.split(separator: "#", maxSplits: 1).first?
                .split(separator: "?", maxSplits: 1).first ?? ""
            pathComponents = pathOnly.split(separator: "/").map(String.init)
        }
        guard pathComponents.count >= 2 else { return nil }
        let kindSegment = pathComponents[pathComponents.count - 2]
        guard kindSegment == "pull" || kindSegment == "issues" else { return nil }
        return Int(pathComponents[pathComponents.count - 1])
    }
}

extension MonitorTarget {
    public static func parse(input: String, type: String, name _: String = "") -> MonitorTarget? {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }

        if clean.lowercased().hasPrefix("http://") || clean.lowercased().hasPrefix("https://") {
            guard let url = URL(string: clean),
                  let host = url.host,
                  host.contains("github.com") else {
                return nil
            }
            let pathComponents = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            if pathComponents.count == 1 {
                return .account(login: pathComponents[0])
            } else if pathComponents.count >= 2 {
                return .repository(owner: pathComponents[0], name: pathComponents[1])
            }
            return nil
        }

        switch type {
        case "account":
            let login = clean.hasPrefix("@") ? String(clean.dropFirst()) : clean
            guard !login.isEmpty else { return nil }
            return .account(login: login)
        case "repository":
            let parts = clean.split(separator: "/")
            if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
                return .repository(owner: String(parts[0]), name: String(parts[1]))
            }
            return nil
        default:
            return nil
        }
    }
}

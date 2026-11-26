import Foundation

extension String {
    public var localized: String {
        NSLocalizedString(self, comment: "")
    }
}

extension URL {
    public static func validatedGitHubWebURL(from rawString: String) -> URL? {
        let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              let host = url.host?.lowercased(),
              host == "github.com" || host == "www.github.com" || host.hasSuffix(".github.com")
        else {
            return nil
        }
        return url
    }

    public static func validatedGitHubAPISubjectWebURL(from rawString: String) -> URL? {
        let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let apiURL = URL(string: trimmed),
              let scheme = apiURL.scheme?.lowercased(),
              scheme == "https",
              apiURL.host?.lowercased() == "api.github.com"
        else {
            return validatedGitHubWebURL(from: trimmed)
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        var segments = apiURL.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        if segments.first == "repos" {
            segments.removeFirst()
        }
        if segments.count >= 4, segments[2] == "pulls" {
            segments[2] = "pull"
        }
        components.path = "/" + segments.joined(separator: "/")
        return components.url
    }
}

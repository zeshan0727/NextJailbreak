import Foundation

struct PopupRequest {
    var sourceHost: String
    var targetURL: URL?
    var isUserInitiated: Bool
}

enum PopupDecision: Equatable {
    case allow
    case block
}

enum PopupPolicy {
    // Milestone 1 records the decision seam without applying blocking rules.
    static func decide(_ request: PopupRequest, settings: ResolvedSiteSettings) -> PopupDecision {
        .allow
    }
}

enum NavigationRouter {
    static func resolve(_ raw: String, searchEngine: SearchEngine) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil {
            return url
        }
        let looksLikeHost = !text.contains(where: { $0.isWhitespace }) &&
            (text.lowercased() == "localhost" || text.contains(".")) &&
            !text.hasPrefix(".") && !text.hasSuffix(".")
        if looksLikeHost, let url = URL(string: "https://" + text), url.host != nil {
            return url
        }
        let query = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=#?"))) ?? ""
        return URL(string: searchEngine.baseURL + query)
    }
}

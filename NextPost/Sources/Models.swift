import Foundation

struct ArticleManifest: Decodable {
    let entries: [PublishedArticle]
}

struct ArticleCategory: Decodable {
    let id: String?
    let label: String?
}

struct PublishedArticle: Decodable, Identifiable, Hashable {
    let name: String
    let title: String
    let description: String
    let href: String
    let version: String?
    let category: ArticleCategory?

    var id: String { canonicalID }

    var publishedURL: URL {
        if var components = URLComponents(string: href), components.scheme != nil {
            let host = components.host?.lowercased()
            let legacyBrand = "next" + "solution"
            let legacyHosts = [legacyBrand + ".cc", "www." + legacyBrand + ".cc", legacyBrand + ".app", "www." + legacyBrand + ".app", "www.nextjailbreak.com"]
            if let host, legacyHosts.contains(host) {
                components.scheme = "https"
                components.host = "nextjailbreak.com"
            }
            if let normalized = components.url { return normalized }
        }
        let trimmed = href.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "https://nextjailbreak.com/\(trimmed)")!
    }

    var cleanURL: URL { Self.cleaned(url: publishedURL) }

    /// Domain-independent article identity. This survives nextsolution.cc -> nextjailbreak.com
    /// migrations and ignores tracking query strings.
    var canonicalID: String { Self.canonicalID(from: publishedURL.absoluteString) }

    var socialShareURL: URL {
        guard var components = URLComponents(url: publishedURL, resolvingAgainstBaseURL: false) else { return publishedURL }
        var items = components.queryItems ?? []
        items.removeAll { ["utm_source", "utm_medium", "utm_campaign", "v", "card"].contains($0.name) }
        items.append(URLQueryItem(name: "utm_source", value: "nextpost"))
        items.append(URLQueryItem(name: "utm_medium", value: "x"))
        items.append(URLQueryItem(name: "utm_campaign", value: "article_share"))
        items.append(URLQueryItem(name: "card", value: "article-v3"))
        if let version, !version.isEmpty { items.append(URLQueryItem(name: "v", value: version)) }
        components.queryItems = items
        return components.url ?? publishedURL
    }

    static func canonicalID(from raw: String) -> String {
        let fallback = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: fallback) else { return fallback.lowercased() }
        components.query = nil
        components.fragment = nil
        var path = components.path
        if path.hasSuffix(".html") { path = String(path.dropLast(5)) }
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty { path = "home" }
        return path.lowercased()
    }

    private static func cleaned(url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.query = nil
        components.fragment = nil
        components.scheme = "https"
        components.host = "nextjailbreak.com"
        var path = components.path
        if path.hasSuffix(".html") { path = String(path.dropLast(5)) + "/" }
        else if !path.hasSuffix("/") { path += "/" }
        components.path = path
        return components.url ?? url
    }

    static func == (lhs: PublishedArticle, rhs: PublishedArticle) -> Bool { lhs.canonicalID == rhs.canonicalID }
    func hash(into hasher: inout Hasher) { hasher.combine(canonicalID) }
}

extension ArticleCategory {
    static let empty = ArticleCategory(id: nil, label: nil)
}

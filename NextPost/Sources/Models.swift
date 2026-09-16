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

    var id: String { cleanURL.absoluteString }

    /// The exact URL published by the website manifest/feed.
    /// Legacy Next Solution URLs are normalized to the current Next Jailbreak domain
    /// so stale manifests or cached article data can never generate an old-domain post.
    var publishedURL: URL {
        if var components = URLComponents(string: href), components.scheme != nil {
            let host = components.host?.lowercased()
            let legacyBrand = "next" + "solution"
            let legacyHosts = [
                legacyBrand + "." + "cc",
                "www." + legacyBrand + "." + "cc",
                legacyBrand + "." + "app",
                "www." + legacyBrand + "." + "app",
                "www.nextjailbreak.com"
            ]
            if let host, legacyHosts.contains(host) {
                components.scheme = "https"
                components.host = "nextjailbreak.com"
            }
            if let normalized = components.url {
                return normalized
            }
        }

        let trimmed = href.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "https://nextjailbreak.com/\(trimmed)")!
    }

    /// Clean canonical-style URL retained for deduplication/history.
    var cleanURL: URL {
        Self.cleaned(url: publishedURL)
    }

    /// Dedicated sharing URL for X/Twitter cards.
    ///
    /// Use the exact published route as the crawl target, then add a small
    /// query string so X can refresh a previously cached card. This avoids
    /// forcing a `/slug/` route that may not exist yet for brand-new articles.
    var socialShareURL: URL {
        guard var components = URLComponents(url: publishedURL, resolvingAgainstBaseURL: false) else {
            return publishedURL
        }

        var items = components.queryItems ?? []
        items.removeAll { ["utm_source", "utm_medium", "utm_campaign", "v", "card"].contains($0.name) }
        items.append(URLQueryItem(name: "utm_source", value: "nextpost"))
        items.append(URLQueryItem(name: "utm_medium", value: "x"))
        items.append(URLQueryItem(name: "utm_campaign", value: "article_share"))
        items.append(URLQueryItem(name: "card", value: "article-v2"))
        if let version, !version.isEmpty {
            items.append(URLQueryItem(name: "v", value: version))
        }
        components.queryItems = items
        return components.url ?? publishedURL
    }

    private static func cleaned(url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.query = nil
        components.fragment = nil

        var path = components.path
        if path.hasSuffix(".html") {
            path = String(path.dropLast(5)) + "/"
        } else if !path.hasSuffix("/") {
            path += "/"
        }
        components.path = path
        return components.url ?? url
    }

    static func == (lhs: PublishedArticle, rhs: PublishedArticle) -> Bool {
        lhs.cleanURL == rhs.cleanURL
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(cleanURL.absoluteString)
    }
}

extension ArticleCategory {
    static let empty = ArticleCategory(id: nil, label: nil)
}

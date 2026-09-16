import Foundation

enum ArticleServiceError: LocalizedError {
    case invalidResponse
    case noArticles

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Next Jailbreak returned an invalid response."
        case .noArticles:
            return "No published articles were found."
        }
    }
}

struct ArticleService {
    private let manifestURL = URL(string: "https://nextjailbreak.com/automation/published-articles.json")!
    private let feedURL = URL(string: "https://nextjailbreak.com/feed.xml")!

    func fetchArticles(forceRefresh: Bool = false) async throws -> [PublishedArticle] {
        do {
            var request = URLRequest(url: requestURL(manifestURL, forceRefresh: forceRefresh))
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if forceRefresh {
                request.setValue("no-cache, no-store, max-age=0", forHTTPHeaderField: "Cache-Control")
                request.setValue("no-cache", forHTTPHeaderField: "Pragma")
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw ArticleServiceError.invalidResponse
            }

            let manifest = try JSONDecoder().decode(ArticleManifest.self, from: data)
            let articles = unique(manifest.entries)
            if !articles.isEmpty { return articles }
        } catch {
            // Fall back to the public RSS feed if the automation manifest is unavailable.
        }

        return try await fetchFeedArticles(forceRefresh: forceRefresh)
    }

    private func fetchFeedArticles(forceRefresh: Bool) async throws -> [PublishedArticle] {
        var request = URLRequest(url: requestURL(feedURL, forceRefresh: forceRefresh))
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 15
        request.setValue("application/rss+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")
        if forceRefresh {
            request.setValue("no-cache, no-store, max-age=0", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ArticleServiceError.invalidResponse
        }

        let delegate = RSSFeedParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? ArticleServiceError.invalidResponse
        }

        let articles = unique(delegate.articles)
        guard !articles.isEmpty else { throw ArticleServiceError.noArticles }
        return articles
    }

    private func requestURL(_ baseURL: URL, forceRefresh: Bool) -> URL {
        guard forceRefresh,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }

        var items = components.queryItems ?? []
        items.removeAll { $0.name == "nextpost_refresh" }
        items.append(URLQueryItem(name: "nextpost_refresh", value: String(Int(Date().timeIntervalSince1970))))
        components.queryItems = items
        return components.url ?? baseURL
    }

    private func unique(_ articles: [PublishedArticle]) -> [PublishedArticle] {
        var seen = Set<String>()
        return articles.filter { article in
            let key = article.cleanURL.absoluteString.lowercased()
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
}

private final class RSSFeedParserDelegate: NSObject, XMLParserDelegate {
    private struct Draft {
        var title = ""
        var link = ""
        var description = ""
        var category = ""
    }

    private var current: Draft?
    private var buffer = ""

    var articles: [PublishedArticle] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        buffer = ""
        if elementName == "item" {
            current = Draft()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard current != nil else { return }
        buffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard var draft = current else { return }
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "title":
            draft.title = value
        case "link":
            draft.link = value
        case "description":
            draft.description = value
        case "category":
            draft.category = value
        case "item":
            let name = Self.inferName(from: draft.title)
            if !draft.link.isEmpty {
                articles.append(
                    PublishedArticle(
                        name: name,
                        title: draft.title,
                        description: draft.description,
                        href: draft.link,
                        version: nil,
                        category: ArticleCategory(id: nil, label: draft.category.isEmpty ? nil : draft.category)
                    )
                )
            }
            current = nil
            buffer = ""
            return
        default:
            break
        }

        current = draft
        buffer = ""
    }

    private static func inferName(from title: String) -> String {
        if let colon = title.firstIndex(of: ":") {
            return String(title[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let words = title.split(separator: " ")
        return words.prefix(3).joined(separator: " ")
    }
}

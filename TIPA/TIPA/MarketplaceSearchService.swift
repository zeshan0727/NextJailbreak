import Foundation

actor MarketplaceSearchService {
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 12
        c.timeoutIntervalForResource = 18
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    func search(_ raw: String) async -> (query: String, listings: [MarketplaceListing], sort: ListingSort) {
        let intent = SearchIntent.parse(raw)
        let query = intent.itemQuery
        guard query.count > 1 else { return (query, [], intent.preferredSort) }

        var combined: [MarketplaceListing] = []
        await withTaskGroup(of: [MarketplaceListing].self) { group in
            for (sourceIndex, source) in MarketplaceSource.all.enumerated() {
                group.addTask { [session] in
                    await Self.fetchSource(source, sourceIndex: sourceIndex, query: query, session: session)
                }
            }
            for await batch in group { combined.append(contentsOf: batch) }
        }

        var seen = Set<String>()
        combined = combined.filter { seen.insert($0.url.absoluteString).inserted }
        return (query, combined, intent.preferredSort)
    }

    private static func fetchSource(_ source: MarketplaceSource, sourceIndex: Int, query: String, session: URLSession) async -> [MarketplaceListing] {
        let searchText = "site:\(source.siteQuery) \(query) Qatar QAR"
        var components = URLComponents(string: "https://www.bing.com/search")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "rss"),
            URLQueryItem(name: "count", value: "25"),
            URLQueryItem(name: "cc", value: "QA"),
            URLQueryItem(name: "setlang", value: "en"),
            URLQueryItem(name: "q", value: searchText)
        ]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 TIPA/0.1", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            let parser = RSSParser(data: data)
            let items = parser.parse()
            return items.enumerated().compactMap { offset, item in
                guard let link = URL(string: item.link), isExpected(link, for: source) else { return nil }
                let searchable = "\(item.title) \(item.description)"
                guard matches(searchable, query: query) else { return nil }
                return MarketplaceListing(
                    title: clean(item.title),
                    url: link,
                    source: source,
                    priceQAR: extractPrice(searchable),
                    snippet: clean(item.description),
                    order: sourceIndex * 100 + offset
                )
            }
        } catch {
            return []
        }
    }

    private static func isExpected(_ url: URL, for source: MarketplaceSource) -> Bool {
        let host = (url.host ?? "").lowercased()
        switch source.id {
        case "mzad": return host.contains("mzadqatar.com")
        case "ql": return host.contains("qatarliving.com")
        case "opensooq": return host.contains("opensooq.com")
        case "qatarsale": return host.contains("qatarsale.com")
        case "dubizzle": return host.contains("dubizzle.qa")
        case "facebook": return host.contains("facebook.com") && url.path.lowercased().contains("marketplace")
        default: return false
        }
    }

    private static func matches(_ text: String, query: String) -> Bool {
        let hay = text.lowercased()
        let tokens = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 2 || Int($0) != nil }
        guard !tokens.isEmpty else { return true }
        let hits = tokens.filter { hay.contains($0) }.count
        return tokens.count <= 2 ? hits == tokens.count : hits >= tokens.count - 1
    }

    private static func extractPrice(_ text: String) -> Int? {
        let patterns = [
            #"(?i)QAR\s*[:\-]?\s*([0-9][0-9,. ]*)"#,
            #"(?i)([0-9][0-9,. ]*)\s*(?:QAR|Q\.?\s*R\.?)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: text) else { continue }
            let digits = text[r].filter(\.isNumber)
            if let value = Int(digits), (20...10_000_000).contains(value) { return value }
        }
        return nil
    }

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct RSSItem { let title: String; let link: String; let description: String }

private final class RSSParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var items: [RSSItem] = []
    private var currentElement = ""
    private var inItem = false
    private var title = ""
    private var link = ""
    private var desc = ""

    init(data: Data) { self.data = data }

    func parse() -> [RSSItem] {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName.lowercased()
        if currentElement == "item" { inItem = true; title = ""; link = ""; desc = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem else { return }
        switch currentElement {
        case "title": title += string
        case "link": link += string
        case "description": desc += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let element = elementName.lowercased()
        if element == "item" {
            items.append(.init(title: title, link: link.trimmingCharacters(in: .whitespacesAndNewlines), description: desc))
            inItem = false
        }
        currentElement = ""
    }
}

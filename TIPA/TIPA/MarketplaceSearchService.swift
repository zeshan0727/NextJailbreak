import Foundation

actor MarketplaceSearchService {
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 14
        c.timeoutIntervalForResource = 20
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpMaximumConnectionsPerHost = 4
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
            for await batch in group {
                combined.append(contentsOf: batch)
            }
        }

        var seen = Set<String>()
        combined = combined.filter { seen.insert(Self.canonicalKey($0.url)).inserted }
        return (query, combined, intent.preferredSort)
    }

    private static func fetchSource(
        _ source: MarketplaceSource,
        sourceIndex: Int,
        query: String,
        session: URLSession
    ) async -> [MarketplaceListing] {
        let searchText = "site:\(source.siteQuery) \(query) Qatar QAR"

        let duck = await fetchDuckDuckGo(
            source: source,
            sourceIndex: sourceIndex,
            query: query,
            searchText: searchText,
            session: session
        )
        if !duck.isEmpty { return duck }

        return await fetchBrave(
            source: source,
            sourceIndex: sourceIndex,
            query: query,
            searchText: searchText,
            session: session
        )
    }

    private static func fetchDuckDuckGo(
        source: MarketplaceSource,
        sourceIndex: Int,
        query: String,
        searchText: String,
        session: URLSession
    ) async -> [MarketplaceListing] {
        var components = URLComponents(string: "https://html.duckduckgo.com/html/")!
        components.queryItems = [URLQueryItem(name: "q", value: searchText)]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue(safariUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let html = String(data: data, encoding: .utf8),
                  html.localizedCaseInsensitiveContains("result__a") else {
                return []
            }
            return parseDuckDuckGo(
                html,
                source: source,
                sourceIndex: sourceIndex,
                query: query
            )
        } catch {
            return []
        }
    }

    private static func parseDuckDuckGo(
        _ html: String,
        source: MarketplaceSource,
        sourceIndex: Int,
        query: String
    ) -> [MarketplaceListing] {
        let pattern = #"(?is)<a(?=[^>]*class=["'][^"']*result__a[^"']*["'])(?=[^>]*href=["']([^"']+)["'])[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, range: fullRange)
        guard !matches.isEmpty else { return [] }

        var output: [MarketplaceListing] = []
        for (index, match) in matches.enumerated() {
            guard
                match.numberOfRanges >= 3,
                let hrefRange = Range(match.range(at: 1), in: html),
                let titleRange = Range(match.range(at: 2), in: html)
            else { continue }

            let rawHref = decodeEntities(String(html[hrefRange]))
            guard let target = resolveSearchURL(rawHref), isExpected(target, for: source) else { continue }

            let title = clean(String(html[titleRange]))
            let contextStart = match.range.location + match.range.length
            let contextEnd: Int
            if index + 1 < matches.count {
                contextEnd = min(matches[index + 1].range.location, contextStart + 2400)
            } else {
                contextEnd = min((html as NSString).length, contextStart + 2400)
            }

            var snippet = ""
            if contextEnd > contextStart {
                let ns = html as NSString
                snippet = clean(ns.substring(with: NSRange(location: contextStart, length: contextEnd - contextStart)))
            }

            let searchable = "\(title) \(snippet)"
            guard matchesQuery(searchable, query: query) else { continue }

            output.append(
                MarketplaceListing(
                    title: title.isEmpty ? query : title,
                    url: target,
                    source: source,
                    priceQAR: extractPrice(searchable),
                    snippet: String(snippet.prefix(320)),
                    order: sourceIndex * 100 + index
                )
            )
        }
        return output
    }

    private static func fetchBrave(
        source: MarketplaceSource,
        sourceIndex: Int,
        query: String,
        searchText: String,
        session: URLSession
    ) async -> [MarketplaceListing] {
        var components = URLComponents(string: "https://search.brave.com/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: searchText),
            URLQueryItem(name: "source", value: "web")
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue(safariUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else {
                return []
            }
            return parseGenericAnchors(
                html,
                source: source,
                sourceIndex: sourceIndex,
                query: query
            )
        } catch {
            return []
        }
    }

    private static func parseGenericAnchors(
        _ html: String,
        source: MarketplaceSource,
        sourceIndex: Int,
        query: String
    ) -> [MarketplaceListing] {
        let pattern = #"(?is)<a\b[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, range: fullRange)
        var output: [MarketplaceListing] = []
        var seen = Set<String>()

        for (index, match) in matches.enumerated() {
            guard
                match.numberOfRanges >= 3,
                let hrefRange = Range(match.range(at: 1), in: html),
                let titleRange = Range(match.range(at: 2), in: html)
            else { continue }

            let rawHref = decodeEntities(String(html[hrefRange]))
            guard let target = resolveSearchURL(rawHref), isExpected(target, for: source) else { continue }

            let key = canonicalKey(target)
            guard seen.insert(key).inserted else { continue }

            let title = clean(String(html[titleRange]))
            let contextStart = match.range.location + match.range.length
            let contextEnd = min((html as NSString).length, contextStart + 1400)
            let snippet: String
            if contextEnd > contextStart {
                snippet = clean((html as NSString).substring(
                    with: NSRange(location: contextStart, length: contextEnd - contextStart)
                ))
            } else {
                snippet = ""
            }

            let searchable = "\(title) \(snippet)"
            guard matchesQuery(searchable, query: query) else { continue }

            output.append(
                MarketplaceListing(
                    title: title.isEmpty ? query : title,
                    url: target,
                    source: source,
                    priceQAR: extractPrice(searchable),
                    snippet: String(snippet.prefix(320)),
                    order: sourceIndex * 100 + index
                )
            )

            if output.count >= 18 { break }
        }
        return output
    }

    private static func resolveSearchURL(_ raw: String) -> URL? {
        var value = decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("//") { value = "https:" + value }

        guard let url = URL(string: value) else { return nil }
        let host = (url.host ?? "").lowercased()

        if host.contains("duckduckgo.com"),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let uddg = components.queryItems?.first(where: { $0.name == "uddg" })?.value,
           let decoded = uddg.removingPercentEncoding ?? uddg,
           let target = URL(string: decoded) {
            return target
        }

        return url
    }

    private static func isExpected(_ url: URL, for source: MarketplaceSource) -> Bool {
        let host = (url.host ?? "").lowercased()
        switch source.id {
        case "mzad":
            return host == "mzadqatar.com" || host.hasSuffix(".mzadqatar.com")
        case "ql":
            return host == "qatarliving.com" || host.hasSuffix(".qatarliving.com")
        case "opensooq":
            return host == "qa.opensooq.com" || host.hasSuffix(".opensooq.com")
        case "qatarsale":
            return host == "qatarsale.com" || host.hasSuffix(".qatarsale.com")
        case "dubizzle":
            return host == "dubizzle.qa" || host.hasSuffix(".dubizzle.qa")
        case "facebook":
            return (host == "facebook.com" || host.hasSuffix(".facebook.com"))
                && url.path.lowercased().contains("marketplace")
        default:
            return false
        }
    }

    private static func matchesQuery(_ text: String, query: String) -> Bool {
        let hay = text.lowercased()
        let tokens = query.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 2 || Int($0) != nil }

        guard !tokens.isEmpty else { return true }
        let hits = tokens.filter { hay.contains($0) }.count

        if tokens.count <= 2 {
            return hits == tokens.count
        }
        return hits >= max(2, tokens.count - 1)
    }

    private static func extractPrice(_ text: String) -> Int? {
        let patterns = [
            #"(?i)QAR\s*[:\-]?\s*([0-9][0-9,. ]*)"#,
            #"(?i)([0-9][0-9,. ]*)\s*(?:QAR|Q\.?\s*R\.?)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard
                let match = regex.firstMatch(in: text, range: range),
                match.numberOfRanges > 1,
                let r = Range(match.range(at: 1), in: text)
            else { continue }

            let digits = text[r].filter(\.isNumber)
            if let value = Int(digits), (20...10_000_000).contains(value) {
                return value
            }
        }
        return nil
    }

    private static func canonicalKey(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.url?.absoluteString.lowercased() ?? url.absoluteString.lowercased()
    }

    private static func decodeEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private static func clean(_ text: String) -> String {
        decodeEntities(text)
            .replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let safariUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
}

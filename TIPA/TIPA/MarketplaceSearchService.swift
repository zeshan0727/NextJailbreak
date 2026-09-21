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
                    await Self.fetchSource(
                        source,
                        sourceIndex: sourceIndex,
                        query: query,
                        session: session
                    )
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
        var searchText = "site:\(source.siteQuery) \(query) Qatar QAR"

        if looksLikePhoneQuery(query) && !queryRequestsAccessory(query) {
            searchText += " -cover -case -protector -charger -cable -accessory -parts"
        }

        let duck = await fetchDuckDuckGo(
            source: source,
            sourceIndex: sourceIndex,
            query: query,
            searchText: searchText,
            session: session
        )

        if !duck.isEmpty {
            return Array(duck.prefix(15))
        }

        // Brave is only a fallback. Its candidates are subjected to the exact
        // same direct-post URL checks; generic marketplace pages never pass.
        let brave = await fetchBrave(
            source: source,
            sourceIndex: sourceIndex,
            query: query,
            searchText: searchText,
            session: session
        )
        return Array(brave.prefix(10))
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
            guard
                (response as? HTTPURLResponse)?.statusCode == 200,
                let html = String(data: data, encoding: .utf8),
                html.localizedCaseInsensitiveContains("result__a")
            else {
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
        let anchorPattern = #"(?is)<a(?=[^>]*class=["'][^"']*result__a[^"']*["'])(?=[^>]*href=["']([^"']+)["'])[^>]*>(.*?)</a>"#
        guard let anchorRegex = try? NSRegularExpression(pattern: anchorPattern) else { return [] }

        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let anchors = anchorRegex.matches(in: html, range: fullRange)
        guard !anchors.isEmpty else { return [] }

        var output: [MarketplaceListing] = []

        for (index, match) in anchors.enumerated() {
            guard
                match.numberOfRanges >= 3,
                let hrefRange = Range(match.range(at: 1), in: html),
                let titleRange = Range(match.range(at: 2), in: html)
            else { continue }

            let rawHref = decodeEntities(String(html[hrefRange]))
            guard
                let target = resolveSearchURL(rawHref),
                isExactListingURL(target, for: source)
            else { continue }

            let title = clean(String(html[titleRange]))
            guard !title.isEmpty else { continue }

            // Match the requested item against the title + exact URL slug only.
            // We intentionally do NOT use surrounding page text for relevance.
            let identityText = "\(title) \(target.path)"
            guard matchesQuery(identityText, query: query) else { continue }
            guard !isAccessoryMismatch(title: title, query: query) else { continue }

            let contextStart = match.range.location + match.range.length
            let contextEnd: Int
            if index + 1 < anchors.count {
                contextEnd = min(anchors[index + 1].range.location, contextStart + 2200)
            } else {
                contextEnd = min((html as NSString).length, contextStart + 2200)
            }

            var context = ""
            if contextEnd > contextStart {
                context = (html as NSString).substring(
                    with: NSRange(location: contextStart, length: contextEnd - contextStart)
                )
            }

            let snippet = extractDuckSnippet(context) ?? clean(context)
            let price = extractPrice("\(title) \(snippet)")

            output.append(
                MarketplaceListing(
                    title: title,
                    url: target,
                    source: source,
                    priceQAR: price,
                    snippet: String(snippet.prefix(320)),
                    order: sourceIndex * 100 + index
                )
            )
        }

        return output
    }

    private static func extractDuckSnippet(_ html: String) -> String? {
        let pattern = #"(?is)<(?:a|div|span)[^>]*class=["'][^"']*result__snippet[^"']*["'][^>]*>(.*?)</(?:a|div|span)>"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
            match.numberOfRanges > 1,
            let range = Range(match.range(at: 1), in: html)
        else {
            return nil
        }

        let value = clean(String(html[range]))
        return value.isEmpty ? nil : value
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
            guard
                (response as? HTTPURLResponse)?.statusCode == 200,
                let html = String(data: data, encoding: .utf8)
            else {
                return []
            }

            return parseBraveAnchors(
                html,
                source: source,
                sourceIndex: sourceIndex,
                query: query
            )
        } catch {
            return []
        }
    }

    private static func parseBraveAnchors(
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
            guard
                let target = resolveSearchURL(rawHref),
                isExactListingURL(target, for: source)
            else { continue }

            let key = canonicalKey(target)
            guard seen.insert(key).inserted else { continue }

            let title = clean(String(html[titleRange]))
            guard !title.isEmpty else { continue }

            let identityText = "\(title) \(target.path)"
            guard matchesQuery(identityText, query: query) else { continue }
            guard !isAccessoryMismatch(title: title, query: query) else { continue }

            // Brave page layout changes frequently. To avoid assigning a nearby
            // ad's price to this ad, only trust a price printed inside the link title.
            let safePrice = extractPrice(title)

            output.append(
                MarketplaceListing(
                    title: title,
                    url: target,
                    source: source,
                    priceQAR: safePrice,
                    snippet: "",
                    order: sourceIndex * 100 + index
                )
            )

            if output.count >= 10 { break }
        }

        return output
    }

    private static func isExactListingURL(_ url: URL, for source: MarketplaceSource) -> Bool {
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let absolute = url.absoluteString

        switch source.id {
        case "mzad":
            guard host == "mzadqatar.com" || host.hasSuffix(".mzadqatar.com") else { return false }
            guard path.contains("/products/") else { return false }
            return regexMatches(#"-[0-9]{6,}/?$"#, in: path)

        case "ql":
            guard host == "qatarliving.com" || host.hasSuffix(".qatarliving.com") else { return false }
            guard path.contains("/classifieds/items/") else { return false }
            guard !path.contains("/category/") else { return false }
            return regexMatches(#"-[0-9a-f]{8}/?$"#, in: path)

        case "qatarsale":
            guard host == "qatarsale.com" || host.hasSuffix(".qatarsale.com") else { return false }
            guard path.contains("/product/") else { return false }
            return regexMatches(#"-[0-9]{4,}/?$"#, in: path)

        case "dubizzle":
            guard host == "dubizzle.qa" || host.hasSuffix(".dubizzle.qa") else { return false }
            guard path.contains("/ad/") else { return false }
            return regexMatches(#"-id[0-9]+\.html/?$"#, in: absolute.lowercased())

        case "facebook":
            guard host == "facebook.com" || host.hasSuffix(".facebook.com") else { return false }
            return regexMatches(#"/marketplace/item/[0-9]+/?$"#, in: path)

        case "opensooq":
            // OpenSooq's public index currently exposes category/model result pages
            // rather than stable individual Qatar ad URLs. Accuracy wins over count:
            // do not pretend a category page is an individual listing.
            return false

        default:
            return false
        }
    }

    private static func matchesQuery(_ text: String, query: String) -> Bool {
        let hay = normalizeForMatch(text)
        let tokens = normalizedTokens(query)
        guard !tokens.isEmpty else { return true }

        let numericTokens = tokens.filter { Int($0) != nil }
        for token in numericTokens where !hay.contains(token) {
            return false
        }

        let words = tokens.filter { Int($0) == nil }
        if words.isEmpty { return true }

        let hits = words.filter { hay.contains($0) }.count
        if words.count <= 2 {
            return hits == words.count
        }
        return hits >= words.count - 1
    }

    private static func normalizedTokens(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { token in
                switch String(token) {
                case "samsungs": return "samsung"
                case "iphones": return "iphone"
                case "galaxys", "galaxies": return "galaxy"
                default: return String(token)
                }
            }
            .filter { $0.count >= 2 || Int($0) != nil }
    }

    private static func normalizeForMatch(_ text: String) -> String {
        normalizedTokens(text).joined(separator: " ")
    }

    private static func looksLikePhoneQuery(_ query: String) -> Bool {
        let q = " " + normalizeForMatch(query) + " "
        let phoneWords = [
            " iphone ", " samsung ", " galaxy ", " pixel ", " fold ", " flip ",
            " vivo ", " oppo ", " xiaomi ", " oneplus ", " huawei ", " honor ",
            " nokia ", " redmagic ", " phone "
        ]
        if phoneWords.contains(where: { q.contains($0) }) {
            return true
        }
        return regexMatches(#"\b[0-9]{1,2}\s+pro\s+max\b"#, in: q)
    }

    private static func queryRequestsAccessory(_ query: String) -> Bool {
        let q = normalizeForMatch(query)
        return accessoryTerms.contains(where: { q.contains($0) })
    }

    private static func isAccessoryMismatch(title: String, query: String) -> Bool {
        guard looksLikePhoneQuery(query), !queryRequestsAccessory(query) else { return false }
        let t = normalizeForMatch(title)
        return accessoryTerms.contains(where: { t.contains($0) })
    }

    private static let accessoryTerms = [
        "cover", "case", "protector", "screen protector", "tempered", "glass",
        "charger", "charging cable", "cable", "adapter", "accessory", "accessories",
        "spare part", "parts", "lens protector", "skin"
    ]

    private static func extractPrice(_ text: String) -> Int? {
        let patterns = [
            #"(?i)\bfor\s+(?:QAR|QR|Q\.?R\.?)?\s*([0-9][0-9,. ]*)\s*(?:QAR|QR|Q\.?R\.?)"#,
            #"(?i)\b(?:price|asking\s+price)\s*(?:is|:|-)?\s*(?:QAR|QR|Q\.?R\.?)?\s*([0-9][0-9,. ]*)"#,
            #"(?i)\b(?:QAR|QR|Q\.?R\.?)\s*[:\-]?\s*([0-9][0-9,. ]*)"#,
            #"(?i)\b([0-9][0-9,. ]*)\s*(?:QAR|QR|Q\.?R\.?)\b"#
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

    private static func regexMatches(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private static func resolveSearchURL(_ raw: String) -> URL? {
        var value = decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("//") {
            value = "https:" + value
        }

        guard let url = URL(string: value) else { return nil }
        let host = (url.host ?? "").lowercased()

        if host.contains("duckduckgo.com"),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let uddg = components.queryItems?.first(where: { $0.name == "uddg" })?.value {
            let decoded = uddg.removingPercentEncoding ?? uddg
            if let target = URL(string: decoded) {
                return target
            }
        }

        return url
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
            .replacingOccurrences(
                of: #"<script[\s\S]*?</script>"#,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"<style[\s\S]*?</style>"#,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let safariUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
}

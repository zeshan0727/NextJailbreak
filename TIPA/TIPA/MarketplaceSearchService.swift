import Foundation

actor MarketplaceSearchService {
    func search(_ raw: String) async -> (query: String, listings: [MarketplaceListing], sort: ListingSort) {
        let intent = SearchIntent.parse(raw)
        let query = intent.itemQuery
        guard query.count > 1 else { return (query, [], intent.preferredSort) }

        var combined: [MarketplaceListing] = []

        await withTaskGroup(of: [MarketplaceListing].self) { group in
            for (sourceIndex, source) in MarketplaceSource.all.enumerated() {
                group.addTask {
                    await Self.fetchSource(
                        source,
                        sourceIndex: sourceIndex,
                        query: query
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
        query: String
    ) async -> [MarketplaceListing] {
        // OpenSooq's public index exposes model/category result pages rather than
        // stable individual ad URLs. Keep it out until a reliable direct-ad route exists.
        if source.id == "opensooq" {
            return []
        }

        var searchText = "site:\\(source.siteQuery) \"\\(query)\" Qatar QAR"

        if looksLikePhoneQuery(query) && !queryRequestsAccessory(query) {
            searchText += " -cover -case -protector -charger -cable -accessory -parts -screen"
        }

        var components = URLComponents(string: "https://search.brave.com/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: searchText),
            URLQueryItem(name: "source", value: "web")
        ]

        guard let url = components.url else { return [] }

        let candidates = await BrowserSearchBridge.fetch(url: url)
        if candidates.isEmpty {
            return []
        }

        var output: [MarketplaceListing] = []
        var seen = Set<String>()

        for (index, candidate) in candidates.enumerated() {
            guard let target = URL(string: candidate.href) else { continue }
            guard isExactListingURL(target, for: source) else { continue }

            let key = canonicalKey(target)
            guard seen.insert(key).inserted else { continue }

            let title = clean(candidate.title)
            let context = clean(candidate.context)
            guard !title.isEmpty else { continue }

            let identityText = "\(title) \(target.path)"
            guard matchesQuery(identityText, query: query) else { continue }
            guard !isAccessoryMismatch(title: title, query: query) else { continue }

            let price = extractPrice("\(title) \(context)")

            output.append(
                MarketplaceListing(
                    title: title,
                    url: target,
                    source: source,
                    priceQAR: price,
                    snippet: String(context.prefix(320)),
                    order: sourceIndex * 100 + index
                )
            )

            if output.count >= 15 {
                break
            }
        }

        return output
    }

    private static func isExactListingURL(_ url: URL, for source: MarketplaceSource) -> Bool {
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let absolute = url.absoluteString.lowercased()

        switch source.id {
        case "mzad":
            guard host == "mzadqatar.com" || host.hasSuffix(".mzadqatar.com") else { return false }
            guard path.contains("/products/") else { return false }
            let slug = url.lastPathComponent.lowercased()
            return regexMatches(#"^[0-9]{6,}$"#, in: slug)
                || regexMatches(#"-[0-9]{6,}$"#, in: slug)

        case "ql":
            guard host == "qatarliving.com" || host.hasSuffix(".qatarliving.com") else { return false }
            guard path.contains("/classifieds/items/") else { return false }
            guard !path.contains("/category/"), !path.contains("/profile/") else { return false }
            return regexMatches(#"-[0-9a-f]{8}/?$"#, in: path)

        case "qatarsale":
            guard host == "qatarsale.com" || host.hasSuffix(".qatarsale.com") else { return false }
            guard path.contains("/product/") else { return false }
            return regexMatches(#"-[0-9]{4,}/?$"#, in: path)

        case "dubizzle":
            guard host == "dubizzle.qa" || host.hasSuffix(".dubizzle.qa") else { return false }
            guard path.contains("/ad/") else { return false }
            return regexMatches(#"-id[0-9]+\.html/?$"#, in: absolute)

        case "facebook":
            guard host == "facebook.com" || host.hasSuffix(".facebook.com") else { return false }
            return regexMatches(#"/marketplace/item/[0-9]+/?$"#, in: path)

        case "opensooq":
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

        let modelLetters = Set(["x", "s", "z"])
        for token in tokens where modelLetters.contains(token) {
            let pattern = #"(^|\s)"# + NSRegularExpression.escapedPattern(for: token) + #"(\s|$)"#
            if !regexMatches(pattern, in: hay) {
                return false
            }
        }

        let words = tokens.filter { Int($0) == nil && !modelLetters.contains($0) }
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
            .filter {
                let modelLetters = Set(["x", "s", "z"])
                return $0.count >= 2 || Int($0) != nil || modelLetters.contains($0)
            }
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
        "spare part", "parts", "lcd screen", "screen replacement", "lens protector", "skin"
    ]

    private static func extractPrice(_ text: String) -> Int? {
        let patterns = [
            #"(?i)\b(?:QAR|QR|Q\.?R\.?)\s*[:\-]?\s*([0-9][0-9,. ]*)"#,
            #"(?i)\b([0-9][0-9,. ]*)\s*(?:QAR|QR|Q\.?R\.?)\b"#,
            #"(?i)\b(?:price|asking\s+price)\s*(?:is|:|-)?\s*(?:QAR|QR|Q\.?R\.?)?\s*([0-9][0-9,. ]*)"#
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

    private static func canonicalKey(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.url?.absoluteString.lowercased() ?? url.absoluteString.lowercased()
    }

    private static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

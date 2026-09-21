import Foundation

private struct BackendSearchResponse: Decodable {
    let query: String
    let listings: [BackendListing]
    let engine: String?
    let searched_at: String?
}

private struct BackendListing: Decodable {
    let title: String
    let url: String
    let source: String
    let price_qar: Int?
    let snippet: String
}

actor MarketplaceSearchService {
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 75
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    func search(_ raw: String) async -> (
        query: String,
        listings: [MarketplaceListing],
        sort: ListingSort,
        error: String?
    ) {
        let intent = SearchIntent.parse(raw)
        let query = intent.itemQuery
        guard query.count > 1 else {
            return (query, [], intent.preferredSort, "Enter a more specific search.")
        }

        var components = URLComponents(string: "https://search.nextjailbreak.com/api/tipa/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]

        guard let url = components.url else {
            return (query, [], intent.preferredSort, "Could not build the search request.")
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("TIPA/0.4 iOS", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                return (query, [], intent.preferredSort, "Search backend returned an invalid response.")
            }

            guard (200...299).contains(http.statusCode) else {
                let message = Self.decodeBackendError(data) ?? "Search backend error (HTTP \(http.statusCode))."
                return (query, [], intent.preferredSort, message)
            }

            let decoded = try JSONDecoder().decode(BackendSearchResponse.self, from: data)

            var result: [MarketplaceListing] = []
            var seen = Set<String>()

            for (index, item) in decoded.listings.enumerated() {
                guard let listingURL = URL(string: item.url),
                      let source = Self.sourceFor(name: item.source, url: listingURL),
                      Self.isDirectListingURL(listingURL, source: source) else {
                    continue
                }

                let key = Self.canonicalKey(listingURL)
                guard seen.insert(key).inserted else { continue }

                result.append(
                    MarketplaceListing(
                        title: item.title.trimmingCharacters(in: .whitespacesAndNewlines),
                        url: listingURL,
                        source: source,
                        priceQAR: item.price_qar,
                        snippet: item.snippet.trimmingCharacters(in: .whitespacesAndNewlines),
                        order: index
                    )
                )
            }

            return (decoded.query.isEmpty ? query : decoded.query, result, intent.preferredSort, nil)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                return (query, [], intent.preferredSort, "The marketplace search timed out. Please try again.")
            case .notConnectedToInternet, .networkConnectionLost:
                return (query, [], intent.preferredSort, "No internet connection.")
            default:
                return (query, [], intent.preferredSort, "Search connection failed: \(error.localizedDescription)")
            }
        } catch {
            return (query, [], intent.preferredSort, "Could not read the marketplace search results.")
        }
    }

    private static func decodeBackendError(_ data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let value = object["error"] as? String,
            !value.isEmpty
        else {
            return nil
        }
        return value
    }

    private static func sourceFor(name: String, url: URL) -> MarketplaceSource? {
        let normalized = name.lowercased()
        if normalized.contains("mzad") {
            return MarketplaceSource.all.first(where: { $0.id == "mzad" })
        }
        if normalized.contains("qatar living") {
            return MarketplaceSource.all.first(where: { $0.id == "ql" })
        }
        if normalized.contains("opensooq") {
            return MarketplaceSource.all.first(where: { $0.id == "opensooq" })
        }
        if normalized.contains("dubizzle") {
            return MarketplaceSource.all.first(where: { $0.id == "dubizzle" })
        }
        if normalized.contains("qatar sale") {
            return MarketplaceSource.all.first(where: { $0.id == "qatarsale" })
        }
        if normalized.contains("facebook") {
            return MarketplaceSource.all.first(where: { $0.id == "facebook" })
        }

        let host = (url.host ?? "").lowercased()
        if host.contains("mzadqatar.com") {
            return MarketplaceSource.all.first(where: { $0.id == "mzad" })
        }
        if host.contains("qatarliving.com") {
            return MarketplaceSource.all.first(where: { $0.id == "ql" })
        }
        if host.contains("opensooq.com") {
            return MarketplaceSource.all.first(where: { $0.id == "opensooq" })
        }
        if host.contains("dubizzle.qa") {
            return MarketplaceSource.all.first(where: { $0.id == "dubizzle" })
        }
        if host.contains("qatarsale.com") {
            return MarketplaceSource.all.first(where: { $0.id == "qatarsale" })
        }
        if host.contains("facebook.com") {
            return MarketplaceSource.all.first(where: { $0.id == "facebook" })
        }
        return nil
    }

    private static func canonicalKey(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.url?.absoluteString.lowercased() ?? url.absoluteString.lowercased()
    }

    private static func isDirectListingURL(_ url: URL, source: MarketplaceSource) -> Bool {
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let absolute = url.absoluteString.lowercased()

        switch source.id {
        case "ql":
            guard host.contains("qatarliving.com") else { return false }
            if path.contains("/classifieds/items/") {
                guard !path.contains("/category/"), !path.contains("/profile/") else { return false }
                return regex(#"-[0-9a-f]{8}/?$"#, matches: path)
            }
            if path.contains("/vehicles/cars/") {
                return regex(#"/vehicles/cars/[0-9]+_[^/]+/?$"#, matches: path)
            }
            return false

        case "mzad":
            guard host.contains("mzadqatar.com") else { return false }
            return path.contains("/products/") && regex(#"[0-9]{6,}/?$"#, matches: path)

        case "dubizzle":
            guard host.contains("dubizzle.qa") else { return false }
            return path.contains("/ad/") && regex(#"-id[0-9]+\.html/?$"#, matches: absolute)

        case "qatarsale":
            guard host.contains("qatarsale.com") else { return false }
            return path.contains("/product/") && regex(#"-[0-9]{4,}/?$"#, matches: path)

        case "facebook":
            guard host.contains("facebook.com") else { return false }
            return regex(#"/marketplace/item/[0-9]+/?$"#, matches: path)

        case "opensooq":
            // Keep OpenSooq disabled until the backend can consistently provide
            // a stable individual-ad URL rather than a model/category page.
            return false

        default:
            return false
        }
    }

    private static func regex(_ pattern: String, matches text: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.firstMatch(in: text, range: range) != nil
    }
}

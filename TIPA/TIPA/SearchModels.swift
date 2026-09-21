import Foundation

struct MarketplaceSource: Identifiable, Hashable {
    let id: String
    let name: String
    let siteQuery: String
    let symbol: String

    static let all: [MarketplaceSource] = [
        .init(id: "mzad", name: "Mzad Qatar", siteQuery: "mzadqatar.com", symbol: "m.circle.fill"),
        .init(id: "ql", name: "Qatar Living", siteQuery: "qatarliving.com", symbol: "q.circle.fill"),
        .init(id: "opensooq", name: "OpenSooq", siteQuery: "qa.opensooq.com", symbol: "o.circle.fill"),
        .init(id: "qatarsale", name: "Qatar Sale", siteQuery: "qatarsale.com", symbol: "tag.circle.fill"),
        .init(id: "dubizzle", name: "Dubizzle Qatar", siteQuery: "dubizzle.qa", symbol: "d.circle.fill"),
        .init(id: "facebook", name: "Facebook Marketplace", siteQuery: "facebook.com/marketplace", symbol: "f.circle.fill")
    ]
}

struct MarketplaceListing: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let url: URL
    let source: MarketplaceSource
    let priceQAR: Int?
    let snippet: String
    let order: Int
}

enum ListingSort: String, CaseIterable, Identifiable {
    case low = "Lowest Price"
    case high = "Highest Price"
    case relevance = "Relevance"
    var id: String { rawValue }
}

struct SearchIntent {
    let itemQuery: String
    let preferredSort: ListingSort

    static func parse(_ raw: String) -> SearchIntent {
        let lower = raw.lowercased()
        let sort: ListingSort
        if lower.contains("highest") || lower.contains("most expensive") || lower.contains("high to low") {
            sort = .high
        } else {
            sort = .low
        }

        let stop = Set(["find", "show", "me", "please", "cheapest", "cheap", "lowest", "highest", "price", "prices", "qatar", "doha", "marketplace", "marketplaces", "the"])
        let cleaned = raw
            .replacingOccurrences(of: "low to high", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "high to low", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "most expensive", with: "", options: .caseInsensitive)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !stop.contains($0.lowercased()) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(itemQuery: cleaned.isEmpty ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : cleaned, preferredSort: sort)
    }
}

import SwiftUI

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @State private var query = ""
    @State private var resolvedQuery = ""
    @State private var listings: [MarketplaceListing] = []
    @State private var sort: ListingSort = .low
    @State private var selectedSource: MarketplaceSource?
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var errorText: String?

    private let service = MarketplaceSearchService()
    private let accent = Color(red: 0.45, green: 0.22, blue: 0.91)

    private var filtered: [MarketplaceListing] {
        let sourceFiltered = selectedSource.map { source in listings.filter { $0.source == source } } ?? listings
        switch sort {
        case .low:
            return sourceFiltered.sorted { a, b in
                switch (a.priceQAR, b.priceQAR) {
                case let (x?, y?): return x == y ? a.order < b.order : x < y
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a.order < b.order
                }
            }
        case .high:
            return sourceFiltered.sorted { a, b in
                switch (a.priceQAR, b.priceQAR) {
                case let (x?, y?): return x == y ? a.order < b.order : x > y
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a.order < b.order
                }
            }
        case .relevance:
            return sourceFiltered.sorted { $0.order < $1.order }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(.systemBackground), accent.opacity(0.08)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        hero
                        searchCard
                        sourceStrip
                        resultsHeader
                        results
                        footer
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 30)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(accent)
    }

    private var hero: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [accent, Color(red: 0.72, green: 0.20, blue: 0.46)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 62, height: 62)
                    .shadow(color: accent.opacity(0.28), radius: 12, y: 7)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("TIPA").font(.system(size: 34, weight: .black, design: .rounded))
                Text("Find it all in Qatar").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text("v0.3.1")
                .font(.caption.bold()).foregroundStyle(accent)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(accent.opacity(0.10), in: Capsule())
        }
        .padding(.top, 12)
    }

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("One search. All marketplaces.").font(.title3.bold())
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(accent)
                TextField("Find 15 Pro Max cheapest", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { runSearch() }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                }
            }
            .padding(14)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button(action: runSearch) {
                HStack {
                    if isSearching { ProgressView().tint(.white) }
                    Image(systemName: isSearching ? "sparkles" : "bolt.fill")
                    Text(isSearching ? "Searching Qatar…" : "Search Marketplaces").fontWeight(.bold)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .foregroundStyle(.white)
                .background(LinearGradient(colors: [accent, Color(red: 0.66, green: 0.16, blue: 0.48)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(isSearching || query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
        }
        .padding(17)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(accent.opacity(0.10)))
    }

    private var sourceStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                sourceChip(nil, title: "All")
                ForEach(MarketplaceSource.all) { source in sourceChip(source, title: source.name) }
            }
        }
    }

    private func sourceChip(_ source: MarketplaceSource?, title: String) -> some View {
        let selected = selectedSource == source
        return Button { selectedSource = source } label: {
            HStack(spacing: 6) {
                if let source { Image(systemName: source.symbol) }
                Text(title).lineLimit(1)
            }
            .font(.caption.bold())
            .padding(.horizontal, 12).padding(.vertical, 9)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? accent : Color(.secondarySystemBackground), in: Capsule())
        }
    }

    @ViewBuilder private var resultsHeader: some View {
        if hasSearched || isSearching {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isSearching ? "Searching…" : "\(filtered.count) listings").font(.headline)
                    if !resolvedQuery.isEmpty { Text(resolvedQuery).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Menu {
                    Picker("Sort", selection: $sort) { ForEach(ListingSort.allCases) { Text($0.rawValue).tag($0) } }
                } label: {
                    Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                        .font(.caption.bold()).padding(.horizontal, 11).padding(.vertical, 9)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                }
            }
        }
    }

    @ViewBuilder private var results: some View {
        if let errorText {
            messageCard(icon: "exclamationmark.triangle.fill", title: "Search issue", text: errorText)
        } else if hasSearched && !isSearching && filtered.isEmpty {
            messageCard(icon: "checkmark.shield", title: "No verified direct ad found", text: "TIPA now rejects home pages, category pages and generic marketplace feeds. Try an exact model such as “iPhone 14 Pro Max”, “Samsung Fold 5”, or “Patrol 2012”.")
        } else {
            LazyVStack(spacing: 12) {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, listing in
                    listingCard(listing, best: sort == .low && index == 0 && listing.priceQAR != nil)
                }
            }
        }
    }

    private func listingCard(_ listing: MarketplaceListing, best: Bool) -> some View {
        Button { openURL(listing.url) } label: {
            HStack(alignment: .top, spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.10)).frame(width: 48, height: 48)
                    Image(systemName: listing.source.symbol).font(.title2).foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        if best { Text("LOWEST").font(.caption2.weight(.black)).foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 3).background(Color.green, in: Capsule()) }
                        Text("DIRECT").font(.caption2.weight(.bold)).foregroundStyle(accent).padding(.horizontal, 7).padding(.vertical, 3).background(accent.opacity(0.10), in: Capsule())
                        Spacer()
                        if let price = listing.priceQAR { Text("QAR \(price.formatted())").font(.headline).foregroundStyle(.green) }
                        else { Text("Price n/a").font(.caption.bold()).foregroundStyle(.secondary) }
                    }
                    Text(listing.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading).lineLimit(2)
                    HStack {
                        Text(listing.source.name).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Label("Exact ad", systemImage: "arrow.up.right.square").font(.caption.bold()).foregroundStyle(accent)
                    }
                }
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }

    private func messageCard(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title).foregroundStyle(accent)
            Text(title).font(.headline)
            Text(text).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(24)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var footer: some View {
        VStack(spacing: 5) {
            Text("TIPA does not host or sell listings.").font(.caption.bold())
            Text("Only individual ad URLs are shown. Marketplace home pages, category pages and generic feeds are discarded. Always verify the live price, seller and availability before buying.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private func runSearch() {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count > 1, !isSearching else { return }
        isSearching = true; hasSearched = true; errorText = nil; selectedSource = nil
        Task {
            let result = await service.search(raw)
            await MainActor.run {
                resolvedQuery = result.query
                listings = result.listings
                sort = result.sort
                isSearching = false
            }
        }
    }
}

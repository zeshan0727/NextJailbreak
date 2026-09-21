import Foundation
import UIKit

@MainActor
final class NextPostStore: ObservableObject {
    @Published var generatedPost = ""
    @Published var selectedArticle: PublishedArticle?
    @Published var selectedRemainingArticle: PublishedArticle?
    @Published var remainingArticles: [PublishedArticle] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var statusText = "Ready"
    @Published var refreshResult = ""
    @Published var errorMessage: String?
    @Published var totalArticles = 0
    @Published var remainingThisCycle = 0
    @Published var generatedCount = 0
    @Published var cycleNumber = 1
    @Published var copied = false

    private let service = ArticleService()
    private let composer = PostComposer()
    private let defaults = UserDefaults.standard

    private var usedLinks = Set<String>()
    private var knownLinks = Set<String>()
    private var lastArticleLink: String?

    private enum Key {
        static let usedLinks = "NextPost.usedLinks"
        static let knownLinks = "NextPost.knownLinks"
        static let lastArticleLink = "NextPost.lastArticleLink"
        static let generatedCount = "NextPost.generatedCount"
        static let cycleNumber = "NextPost.cycleNumber"
        static let generatedPost = "NextPost.generatedPost"
        static let selectedTitle = "NextPost.selectedTitle"
        static let selectedURL = "NextPost.selectedURL"
    }

    init() {
        usedLinks = Set((defaults.stringArray(forKey: Key.usedLinks) ?? []).map(Self.articleKey(from:)))
        knownLinks = Set((defaults.stringArray(forKey: Key.knownLinks) ?? []).map(Self.articleKey(from:)))
        lastArticleLink = defaults.string(forKey: Key.lastArticleLink).map(Self.articleKey(from:))
        generatedCount = defaults.integer(forKey: Key.generatedCount)
        cycleNumber = max(1, defaults.integer(forKey: Key.cycleNumber))
        generatedPost = defaults.string(forKey: Key.generatedPost) ?? ""

        if let title = defaults.string(forKey: Key.selectedTitle),
           let url = defaults.string(forKey: Key.selectedURL) {
            selectedArticle = PublishedArticle(
                name: title,
                title: title,
                description: "",
                href: url,
                version: nil,
                category: .empty
            )
        }
    }

    func refreshStats(manual: Bool = false) async {
        if manual {
            guard !isRefreshing else { return }
            isRefreshing = true
            refreshResult = "Checking for new articles…"
        }
        defer {
            if manual { isRefreshing = false }
        }

        do {
            let articles = try await service.fetchArticles(forceRefresh: manual)
            let currentLinks = Set(articles.map(articleKey))
            let newLinks = knownLinks.isEmpty ? Set<String>() : currentLinks.subtracting(knownLinks)

            totalArticles = articles.count
            knownLinks = currentLinks
            defaults.set(Array(knownLinks), forKey: Key.knownLinks)
            updateRemainingArticles(from: articles)

            if manual {
                if newLinks.isEmpty {
                    refreshResult = "Up to date — no new articles"
                    statusText = "Refreshed from nextjailbreak.com"
                } else {
                    refreshResult = "\(newLinks.count) new article\(newLinks.count == 1 ? "" : "s") added to Remaining"
                    statusText = "Refreshed — \(newLinks.count) new"
                }
            } else {
                statusText = articles.isEmpty ? "No articles found" : "Connected to nextjailbreak.com"
            }
        } catch {
            if manual {
                refreshResult = "Refresh failed"
                errorMessage = error.localizedDescription
            }
            statusText = "Could not refresh articles"
        }
    }

    func selectRemainingArticle(_ article: PublishedArticle) {
        guard !usedLinks.contains(articleKey(article)) else { return }
        selectedRemainingArticle = article
        statusText = "Selected \(article.name) — tap Generate Next Post"
    }

    func clearRemainingSelection() {
        selectedRemainingArticle = nil
    }

    func generate() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        copied = false
        statusText = "Fetching latest articles…"

        defer { isLoading = false }

        do {
            let articles = try await service.fetchArticles(forceRefresh: true)
            guard !articles.isEmpty else { throw ArticleServiceError.noArticles }

            totalArticles = articles.count
            knownLinks.formUnion(articles.map(articleKey))
            defaults.set(Array(knownLinks), forKey: Key.knownLinks)

            let candidates = articles.filter { !usedLinks.contains(articleKey($0)) }

            if candidates.isEmpty {
                selectedRemainingArticle = nil
                updateRemainingArticles(from: articles)
                statusText = "All published articles generated — waiting for new articles"
                refreshResult = "No repeats — refresh after a new article is published"
                persist()
                return
            }

            let article: PublishedArticle
            if let requested = selectedRemainingArticle,
               let selected = candidates.first(where: { $0.cleanURL == requested.cleanURL }) {
                article = selected
            } else if let random = candidates.randomElement() {
                article = random
            } else {
                throw ArticleServiceError.noArticles
            }

            let post = composer.compose(for: article, variation: generatedCount + 1)
            let link = articleKey(article)

            usedLinks.insert(link)
            lastArticleLink = link
            generatedCount += 1
            generatedPost = post
            selectedArticle = article
            selectedRemainingArticle = nil
            remainingThisCycle = max(0, articles.count - usedLinks.count)
            updateRemainingArticles(from: articles)
            statusText = remainingThisCycle == 0
                ? "All published articles generated — waiting for new articles"
                : "\(remainingThisCycle) ungenerated article\(remainingThisCycle == 1 ? "" : "s") remaining"

            persist()
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Generation failed"
        }
    }

    func copyPost() {
        guard !generatedPost.isEmpty else { return }
        UIPasteboard.general.string = generatedPost
        copied = true

        Task {
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            if !Task.isCancelled {
                copied = false
            }
        }
    }

    func openInX() {
        guard !generatedPost.isEmpty else { return }

        guard let article = selectedArticle else {
            openXWebIntent(text: generatedPost, url: nil)
            return
        }

        let shareURL = article.socialShareURL
        let linkedLine = "🔗 \(shareURL.absoluteString)\n"
        let textOnly = generatedPost
            .replacingOccurrences(of: linkedLine, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        openXWebIntent(text: textOnly, url: shareURL)
    }

    func openArticle() {
        guard let url = selectedArticle?.publishedURL else { return }
        UIApplication.shared.open(url)
    }

    private func openXWebIntent(text: String, url: URL?) {
        var components = URLComponents(string: "https://twitter.com/intent/tweet")
        var items = [URLQueryItem(name: "text", value: text)]
        if let url {
            items.append(URLQueryItem(name: "url", value: url.absoluteString))
        }
        components?.queryItems = items
        guard let intentURL = components?.url else { return }
        UIApplication.shared.open(intentURL)
    }

    private func articleKey(_ article: PublishedArticle) -> String {
        Self.articleKey(from: article.cleanURL.absoluteString)
    }

    private static func articleKey(from raw: String) -> String {
        guard let components = URLComponents(string: raw) else {
            return raw.lowercased()
        }

        var path = components.path
        if path.hasSuffix(".html") {
            path = String(path.dropLast(5))
        }
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? "home" : path.lowercased()
    }

    private func updateRemainingArticles(from articles: [PublishedArticle]) {
        // published-articles.json is newest-first; filtering preserves that order.
        remainingArticles = articles.filter { !usedLinks.contains(articleKey($0)) }
        remainingThisCycle = remainingArticles.count

        if let selectedRemainingArticle,
           !remainingArticles.contains(where: { $0.cleanURL == selectedRemainingArticle.cleanURL }) {
            self.selectedRemainingArticle = nil
        }
    }

    private func persist() {
        defaults.set(Array(usedLinks), forKey: Key.usedLinks)
        defaults.set(Array(knownLinks), forKey: Key.knownLinks)
        defaults.set(lastArticleLink, forKey: Key.lastArticleLink)
        defaults.set(generatedCount, forKey: Key.generatedCount)
        defaults.set(cycleNumber, forKey: Key.cycleNumber)
        defaults.set(generatedPost, forKey: Key.generatedPost)
        defaults.set(selectedArticle?.title, forKey: Key.selectedTitle)
        defaults.set(selectedArticle?.publishedURL.absoluteString, forKey: Key.selectedURL)
    }
}

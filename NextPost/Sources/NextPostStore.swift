import Foundation
import UIKit

@MainActor
final class NextPostStore: ObservableObject {
    @Published var generatedPost = ""
    @Published var selectedArticle: PublishedArticle?
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
        usedLinks = Set(defaults.stringArray(forKey: Key.usedLinks) ?? [])
        knownLinks = Set(defaults.stringArray(forKey: Key.knownLinks) ?? [])
        lastArticleLink = defaults.string(forKey: Key.lastArticleLink)
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
            let currentLinks = Set(articles.map { $0.cleanURL.absoluteString })
            let newLinks = knownLinks.isEmpty ? Set<String>() : currentLinks.subtracting(knownLinks)

            reconcileUsedLinks(with: articles)
            totalArticles = articles.count
            remainingThisCycle = max(0, articles.count - usedLinks.count)
            knownLinks = currentLinks
            defaults.set(Array(knownLinks), forKey: Key.knownLinks)

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

            reconcileUsedLinks(with: articles)
            totalArticles = articles.count
            knownLinks.formUnion(articles.map { $0.cleanURL.absoluteString })
            defaults.set(Array(knownLinks), forKey: Key.knownLinks)

            var candidates = articles.filter { !usedLinks.contains($0.cleanURL.absoluteString) }

            if candidates.isEmpty {
                usedLinks.removeAll()
                cycleNumber += 1
                defaults.set(cycleNumber, forKey: Key.cycleNumber)

                if articles.count > 1, let lastArticleLink {
                    candidates = articles.filter { $0.cleanURL.absoluteString != lastArticleLink }
                } else {
                    candidates = articles
                }
            }

            guard let article = candidates.randomElement() else {
                throw ArticleServiceError.noArticles
            }

            let post = composer.compose(for: article, variation: generatedCount + 1)
            let link = article.cleanURL.absoluteString

            usedLinks.insert(link)
            lastArticleLink = link
            generatedCount += 1
            generatedPost = post
            selectedArticle = article
            remainingThisCycle = max(0, articles.count - usedLinks.count)
            statusText = remainingThisCycle == 0
                ? "All articles used — next tap starts a fresh cycle"
                : "\(remainingThisCycle) article\(remainingThisCycle == 1 ? "" : "s") left before repeats"

            persist()
            AdsManager.shared.recordSuccessfulGeneration()
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

    private func reconcileUsedLinks(with articles: [PublishedArticle]) {
        let currentLinks = Set(articles.map { $0.cleanURL.absoluteString })
        let cleaned = usedLinks.intersection(currentLinks)
        if cleaned != usedLinks {
            usedLinks = cleaned
            defaults.set(Array(usedLinks), forKey: Key.usedLinks)
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

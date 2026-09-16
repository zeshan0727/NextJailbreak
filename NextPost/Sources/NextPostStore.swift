import Foundation
import UIKit

@MainActor
final class NextPostStore: ObservableObject {
    @Published var generatedPost = ""
    @Published var selectedArticle: PublishedArticle?
    @Published var userTake = "" { didSet { rebuildPost() } }
    @Published var verifiedContext = ""
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
    @Published var historyProtected = false

    private let service = ArticleService()
    private let composer = PostComposer()
    private let defaults = UserDefaults.standard

    private var pendingIDs = Set<String>()
    private var knownIDs = Set<String>()
    private var lastArticleID: String?
    private var queueInitialized = false

    private enum Key {
        static let pendingIDs = "NextPost.pendingArticleIDs.v12"
        static let knownIDs = "NextPost.knownArticleIDs.v12"
        static let queueInitialized = "NextPost.queueInitialized.v12"
        static let historyProtected = "NextPost.historyProtected.v12"
        static let migrationVersion = "NextPost.migrationVersion"
        static let legacyUsedLinks = "NextPost.usedLinks"
        static let legacyKnownLinks = "NextPost.knownLinks"
        static let lastArticleLink = "NextPost.lastArticleLink"
        static let lastArticleID = "NextPost.lastArticleID.v12"
        static let generatedCount = "NextPost.generatedCount"
        static let cycleNumber = "NextPost.cycleNumber"
        static let selectedTitle = "NextPost.selectedTitle"
        static let selectedURL = "NextPost.selectedURL"
    }

    init() {
        pendingIDs = Set(defaults.stringArray(forKey: Key.pendingIDs) ?? [])
        knownIDs = Set(defaults.stringArray(forKey: Key.knownIDs) ?? [])
        queueInitialized = defaults.bool(forKey: Key.queueInitialized)
        historyProtected = defaults.bool(forKey: Key.historyProtected)
        lastArticleID = defaults.string(forKey: Key.lastArticleID)
            ?? defaults.string(forKey: Key.lastArticleLink).map(PublishedArticle.canonicalID(from:))
        generatedCount = defaults.integer(forKey: Key.generatedCount)
        cycleNumber = max(1, defaults.integer(forKey: Key.cycleNumber))

        if let title = defaults.string(forKey: Key.selectedTitle), let url = defaults.string(forKey: Key.selectedURL) {
            selectedArticle = PublishedArticle(name: title, title: title, description: "", href: url, version: nil, category: .empty)
        }
    }

    var canOpenInX: Bool {
        selectedArticle != nil && userTake.trimmingCharacters(in: .whitespacesAndNewlines).count >= PostComposer.minimumUserTakeCharacters && !generatedPost.isEmpty
    }

    func refreshStats(manual: Bool = false) async {
        if manual {
            guard !isRefreshing else { return }
            isRefreshing = true
            refreshResult = "Checking for new articles…"
        }
        defer { if manual { isRefreshing = false } }

        do {
            let articles = try await service.fetchArticles(forceRefresh: manual)
            guard !articles.isEmpty else { throw ArticleServiceError.noArticles }
            let currentIDs = Set(articles.map(\.canonicalID))

            migrateIfNeeded(currentIDs: currentIDs)

            let newIDs = knownIDs.isEmpty ? Set<String>() : currentIDs.subtracting(knownIDs)
            pendingIDs.formIntersection(currentIDs)
            pendingIDs.formUnion(newIDs)
            knownIDs = currentIDs
            totalArticles = articles.count
            remainingThisCycle = pendingIDs.count
            persistQueue()

            if manual {
                if historyProtected && newIDs.isEmpty {
                    refreshResult = "History protected — old repeats blocked; new articles will be added here"
                } else if newIDs.isEmpty {
                    refreshResult = "Up to date — no new articles"
                } else {
                    refreshResult = "\(newIDs.count) new article\(newIDs.count == 1 ? "" : "s") added to Remaining"
                }
                statusText = "Refreshed from nextjailbreak.com"
            } else {
                statusText = historyProtected ? "Connected — old repeats blocked" : "Connected to nextjailbreak.com"
            }
        } catch {
            if manual { refreshResult = "Refresh failed"; errorMessage = error.localizedDescription }
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
            let currentIDs = Set(articles.map(\.canonicalID))
            migrateIfNeeded(currentIDs: currentIDs)

            let newIDs = knownIDs.isEmpty ? Set<String>() : currentIDs.subtracting(knownIDs)
            pendingIDs.formIntersection(currentIDs)
            pendingIDs.formUnion(newIDs)
            knownIDs = currentIDs
            totalArticles = articles.count

            if pendingIDs.isEmpty {
                if historyProtected {
                    remainingThisCycle = 0
                    statusText = "Waiting for new articles — old repeats blocked"
                    refreshResult = "Your exact old remaining queue was erased by 1.0.11, so 1.0.12 will not repeat old articles. Refresh will add only newly published articles."
                    persistQueue()
                    return
                }

                pendingIDs = currentIDs
                if let lastArticleID, pendingIDs.count > 1 { pendingIDs.remove(lastArticleID) }
                cycleNumber += 1
            }

            let candidates = articles.filter { pendingIDs.contains($0.canonicalID) }
            guard let article = candidates.randomElement() else { throw ArticleServiceError.noArticles }

            selectedArticle = article
            verifiedContext = composer.context(for: article)
            userTake = ""
            generatedPost = ""
            remainingThisCycle = pendingIDs.count
            statusText = "Write your take, then open in X"
            persistSelection()
            persistQueue()
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
            if !Task.isCancelled { copied = false }
        }
    }

    func openInX() {
        guard canOpenInX, let article = selectedArticle else {
            errorMessage = "Write at least \(PostComposer.minimumUserTakeCharacters) characters in Your Take before opening X."
            return
        }

        let shareURL = article.socialShareURL
        let linkedLine = "🔗 \(shareURL.absoluteString)\n"
        let textOnly = generatedPost.replacingOccurrences(of: linkedLine, with: "").trimmingCharacters(in: .whitespacesAndNewlines)

        pendingIDs.remove(article.canonicalID)
        lastArticleID = article.canonicalID
        generatedCount += 1
        remainingThisCycle = pendingIDs.count
        persistQueue()
        persistSelection()
        AdsManager.shared.recordSuccessfulGeneration()
        openXWebIntent(text: textOnly, url: shareURL)
    }

    func openArticle() {
        guard let url = selectedArticle?.publishedURL else { return }
        UIApplication.shared.open(url)
    }

    private func rebuildPost() {
        guard let article = selectedArticle else { generatedPost = ""; return }
        let take = userTake.trimmingCharacters(in: .whitespacesAndNewlines)
        generatedPost = take.isEmpty ? "" : composer.compose(for: article, userTake: take)
    }

    private func migrateIfNeeded(currentIDs: Set<String>) {
        guard !queueInitialized else { return }

        let legacyUsed = Set((defaults.stringArray(forKey: Key.legacyUsedLinks) ?? []).map(PublishedArticle.canonicalID(from:)))
        let legacyKnown = Set((defaults.stringArray(forKey: Key.legacyKnownLinks) ?? []).map(PublishedArticle.canonicalID(from:)))

        if !legacyUsed.isEmpty {
            pendingIDs = currentIDs.subtracting(legacyUsed.intersection(currentIDs))
            knownIDs = legacyKnown.isEmpty ? currentIDs : legacyKnown.intersection(currentIDs)
            historyProtected = false
        } else if generatedCount > 0 {
            pendingIDs = []
            knownIDs = currentIDs
            historyProtected = true
        } else {
            pendingIDs = currentIDs
            knownIDs = currentIDs
            historyProtected = false
        }

        queueInitialized = true
        defaults.set(12, forKey: Key.migrationVersion)
        persistQueue()
    }

    private func openXWebIntent(text: String, url: URL?) {
        var components = URLComponents(string: "https://twitter.com/intent/tweet")
        var items = [URLQueryItem(name: "text", value: text)]
        if let url { items.append(URLQueryItem(name: "url", value: url.absoluteString)) }
        components?.queryItems = items
        guard let intentURL = components?.url else { return }
        UIApplication.shared.open(intentURL)
    }

    private func persistQueue() {
        defaults.set(Array(pendingIDs), forKey: Key.pendingIDs)
        defaults.set(Array(knownIDs), forKey: Key.knownIDs)
        defaults.set(queueInitialized, forKey: Key.queueInitialized)
        defaults.set(historyProtected, forKey: Key.historyProtected)
        defaults.set(lastArticleID, forKey: Key.lastArticleID)
        defaults.set(generatedCount, forKey: Key.generatedCount)
        defaults.set(cycleNumber, forKey: Key.cycleNumber)
    }

    private func persistSelection() {
        defaults.set(selectedArticle?.title, forKey: Key.selectedTitle)
        defaults.set(selectedArticle?.publishedURL.absoluteString, forKey: Key.selectedURL)
    }
}

import Foundation

/// Turns published article metadata into a clean four-line X post.
/// Format: emoji + title, article summary, hashtags, original article URL.
struct PostComposer {
    static let maximumCharacters = 280

    func compose(for article: PublishedArticle, variation: Int = 0) -> String {
        // Never vary an article's wording with generic editorial templates.
        _ = variation

        let url = article.publishedURL.absoluteString
        let sourceTitle = clean(article.title)
        var headline = "\(emoji(for: article)) \(sourceTitle.isEmpty ? clean(article.name) : sourceTitle)"
        var tags = hashtags(for: article)
        let originalSummary = summary(for: article)

        // Protect the headline, hashtags, and actual URL; shorten only when
        // necessary to stay within X's 280-character text limit.
        func summaryRoom() -> Int {
            Self.maximumCharacters - headline.count - tags.joined(separator: " ").count - url.count - 3
        }

        while tags.count > 1 && summaryRoom() < 45 {
            tags.removeLast()
        }
        if summaryRoom() < 35 {
            let budget = max(12, headline.count + summaryRoom() - 45)
            headline = trim(headline, to: budget)
        }

        let summaryLine = trim(originalSummary, to: max(1, min(160, summaryRoom())))
        let hashtagLine = tags.joined(separator: " ")
        return "\(headline)\n\(summaryLine)\n\(hashtagLine)\n\(url)"
    }

    private func summary(for article: PublishedArticle) -> String {
        var value = clean(article.description)
        let genericLeads = [
            "Quick context:", "Quick context —", "Update context:",
            "Update context —", "Why this matters:", "What matters:",
            "What matters here:", "Worth knowing:", "In short:"
        ]
        for lead in genericLeads where value.lowercased().hasPrefix(lead.lowercased()) {
            value = String(value.dropFirst(lead.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        // Keep only the first complete sentence if the source has several.
        // Dots inside version numbers (e.g. 1.0.7) are not sentence breaks.
        let characters = Array(value)
        if characters.count > 50 {
            for index in 40..<(characters.count - 1) {
                if ".!?".contains(characters[index]) && characters[index + 1].isWhitespace {
                    return String(characters[...index])
                }
            }
        }
        return value.isEmpty ? clean(article.title) : value
    }

    private func emoji(for article: PublishedArticle) -> String {
        let text = "\(article.title) \(article.category?.label ?? "")".lowercased()
        if text.contains("ps5") || text.contains("playstation") { return "🎮" }
        if text.contains("guide") || text.contains("how to") || text.contains("tutorial") { return "📌" }
        if text.contains("compare") || text.contains("comparison") || text.contains(" vs ") { return "🔍" }
        if text.contains("release") || text.contains("update") { return "🆕" }
        if text.contains("tweak") || text.contains("jailbreak") { return "⚡" }
        return "📰"
    }

    private func hashtags(for article: PublishedArticle) -> [String] {
        let text = "\(article.title) \(article.description) \(article.category?.label ?? "")".lowercased()
        var tags: [String] = []
        if let specific = hashtag(article.name), specific.count <= 28 {
            tags.append(specific)
        }
        tags.append(text.contains("jailbreak") || text.contains("tweak") || text.contains("rootless") ? "#Jailbreak" : "#iOS")
        if text.contains("iphone") { tags.append("#iPhone") }
        else if text.contains("ios 26") { tags.append("#iOS26") }
        else if text.contains("ios 17") { tags.append("#iOS17") }
        else if text.contains("ios 16") { tags.append("#iOS16") }

        var seen = Set<String>()
        return Array(tags.filter { seen.insert($0.lowercased()).inserted }.prefix(3))
    }

    private func hashtag(_ value: String) -> String? {
        let word = String(value.filter { $0.isLetter || $0.isNumber })
        return word.count >= 2 ? "#\(word)" : nil
    }

    private func trim(_ text: String, to limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard text.count > limit else { return text }
        guard limit > 1 else { return "…" }
        let prefix = String(text.prefix(limit - 1))
        let lastWord = prefix.lastIndex(of: " ").map { String(prefix[..<$0]) } ?? prefix
        let clipped = (lastWord.count >= limit / 2 ? lastWord : prefix)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return clipped + "…"
    }

    private func clean(_ text: String) -> String {
        let decoded = text
            .replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        return decoded.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

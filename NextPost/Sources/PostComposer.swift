import Foundation

/// Turns published article metadata into a clean four-line X post.
/// Format: emoji + title, article summary, hashtags, original article URL.
struct PostComposer {
    static let maximumCharacters = 280

    func compose(for article: PublishedArticle, variation: Int = 0) -> String {
        _ = variation // No editorial filler or random changes.
        let url = article.publishedURL.absoluteString
        var title = clean(article.title)
        if title.isEmpty { title = clean(article.name) }
        let suffix = " on a Jailbroken iPhone"
        if title.lowercased().hasSuffix(suffix.lowercased()) {
            title = String(title.dropLast(suffix.count))
        }
        var heading = "\(emoji(for: article)) \(title)"
        var tags = hashtags(for: article)

        // Three blank-line separators plus the link emoji belong in the budget.
        func summaryRoom() -> Int {
            Self.maximumCharacters - heading.count - tags.joined(separator: " ").count
                - "🔗 ".count - url.count - 6
        }
        while tags.count > 1 && summaryRoom() < 50 {
            tags.removeLast()
        }
        if summaryRoom() < 40 {
            heading = trim(heading, to: max(30, heading.count + summaryRoom() - 40))
        }

        let summaryLine = tidySummary(summary(for: article),
                                      to: max(1, min(130, summaryRoom())))
        return "\(heading)\n\n\(summaryLine)\n\n\(tags.joined(separator: " "))\n\n🔗 \(url)"
    }

    /// X appends the separate url parameter after text. Keep a visible link
    /// marker as its own paragraph, so the URL cannot stick to the hashtags.
    static func xIntentText(generatedPost: String, articleURL: URL) -> String {
        let url = articleURL.absoluteString
        let newSuffix = "\n\n🔗 \(url)"
        if generatedPost.hasSuffix(newSuffix) {
            return String(generatedPost.dropLast(url.count + 1))
        }
        let oldSuffix = "\n\(url)"
        if generatedPost.hasSuffix(oldSuffix) {
            let text = String(generatedPost.dropLast(oldSuffix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text + "\n\n🔗"
        }
        return generatedPost.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n🔗"
    }

    private func tidySummary(_ input: String, to maxLength: Int) -> String {
        guard maxLength > 0 else { return "" }
        var summary = input
        if summary.count > maxLength {
            let prefix = String(summary.prefix(maxLength))
            if let lastSpace = prefix.lastIndex(of: " "),
               prefix.distance(from: prefix.startIndex, to: lastSpace) > maxLength / 2 {
                summary = String(prefix[..<lastSpace])
            } else {
                summary = prefix
            }
        }

        summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty,
           !summary.hasSuffix("."), !summary.hasSuffix("!"), !summary.hasSuffix("?") {
            summary = summary.trimmingCharacters(in: .punctuationCharacters)
            let dangling = ["and", "or", "with", "the", "a", "for", "of", "in", "to", "by"]
            while let last = summary.split(separator: " ").last,
                  dangling.contains(last.lowercased()),
                  let space = summary.lastIndex(of: " ") {
                summary = String(summary[..<space])
            }
            if summary.count >= maxLength { summary = String(summary.prefix(max(1, maxLength - 1))) }
            summary += "."
        }
        return summary
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
        if text.contains("trollstore") { return "📲" }
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
        if text.contains("trollstore") {
            tags.append("#TrollStore")
        } else if text.contains("husk") {
            tags.append("#Husk")
        } else if let specific = hashtag(article.name), specific.count <= 22 {
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

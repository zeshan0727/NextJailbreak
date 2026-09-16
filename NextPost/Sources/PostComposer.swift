import Foundation

struct PostComposer {
    static let maximumCharacters = 280
    static let minimumUserTakeCharacters = 20

    func context(for article: PublishedArticle) -> String {
        let subject = productLabel(for: article)
        var title = clean(article.title)
        let name = clean(article.name)
        let version = article.version.map(clean) ?? ""
        let prefixes = [version.isEmpty ? "" : "\(name) v\(version)", version.isEmpty ? "" : "\(name) \(version)", name]
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
        for prefix in prefixes where title.lowercased().hasPrefix(prefix.lowercased()) {
            title = String(title.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":–—-")))
            break
        }
        return title.isEmpty ? "\(subject) has a newly documented update." : "\(subject): \(lowercaseFirstCharacter(title))."
    }

    func compose(for article: PublishedArticle, userTake: String) -> String {
        let take = clean(userTake)
        let link = article.socialShareURL.absoluteString
        var tags = hashtags(for: article)
        var footer = footerText(link: link, tags: tags)
        var available = Self.maximumCharacters - footer.count - 2
        while available < 60 && tags.count > 2 {
            tags.removeLast()
            footer = footerText(link: link, tags: tags)
            available = Self.maximumCharacters - footer.count - 2
        }
        let body = trim(take, to: max(0, available))
        return "\(body)\n\n\(footer)"
    }

    private func productLabel(for article: PublishedArticle) -> String {
        let name = clean(article.name)
        guard let version = article.version.map(clean), !version.isEmpty else { return name }
        return name.lowercased().contains(version.lowercased()) ? name : "\(name) \(version)"
    }

    private func footerText(link: String, tags: [String]) -> String {
        "🔗 \(link)\n\(tags.joined(separator: " "))"
    }

    private func hashtags(for article: PublishedArticle) -> [String] {
        let combined = "\(article.title) \(article.description) \(article.category?.label ?? "")".lowercased()
        var tags: [String] = []
        if let nameTag = hashtag(article.name), nameTag.count <= 28 { tags.append(nameTag) }
        tags.append(combined.contains("jailbreak") || combined.contains("tweak") || combined.contains("rootless") ? "#Jailbreak" : "#iOS")
        if combined.contains("ios 27") || combined.contains("ios27") { tags.append("#iOS27") }
        else if combined.contains("ios 26") || combined.contains("ios26") { tags.append("#iOS26") }
        else if combined.contains("ios 17") || combined.contains("ios17") { tags.append("#iOS17") }
        else if combined.contains("ios 16") || combined.contains("ios16") { tags.append("#iOS16") }
        else { tags.append("#iPhone") }
        if !tags.contains("#iPhone") && tags.count < 4 { tags.append("#iPhone") }
        var seen = Set<String>()
        return tags.filter { seen.insert($0.lowercased()).inserted }.prefix(4).map { $0 }
    }

    private func hashtag(_ value: String) -> String? {
        let result = String(value.filter { $0.isLetter || $0.isNumber })
        return result.count >= 2 ? "#\(result)" : nil
    }

    private func lowercaseFirstCharacter(_ value: String) -> String {
        guard let first = value.first else { return value }
        return first.lowercased() + value.dropFirst()
    }

    private func trim(_ value: String, to maxLength: Int) -> String {
        guard maxLength > 0 else { return "" }
        guard value.count > maxLength else { return value }
        guard maxLength > 1 else { return "…" }
        var cut = String(value.prefix(maxLength - 1))
        if let lastSpace = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: lastSpace) > maxLength / 2 {
            cut = String(cut[..<lastSpace])
        }
        return cut.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) + "…"
    }

    private func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

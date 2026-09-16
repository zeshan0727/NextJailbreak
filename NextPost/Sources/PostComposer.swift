import Foundation

struct PostComposer {
    static let maximumCharacters = 280

    func compose(for article: PublishedArticle, variation: Int = 0) -> String {
        let link = article.socialShareURL.absoluteString
        var tags = hashtags(for: article)
        let header = editorialHeader(for: article, variation: variation)
        let originalCommentary = commentary(for: article, variation: variation)

        var footer = footerText(link: link, tags: tags)
        var available = Self.maximumCharacters - header.count - footer.count - 4

        while available < 72 && tags.count > 2 {
            tags.removeLast()
            footer = footerText(link: link, tags: tags)
            available = Self.maximumCharacters - header.count - footer.count - 4
        }

        let commentary = trim(originalCommentary, to: max(0, available))
        var result = "\(header)\n\n\(commentary)\n\n\(footer)"

        if result.count > Self.maximumCharacters {
            let overflow = result.count - Self.maximumCharacters
            let shortened = trim(commentary, to: max(0, commentary.count - overflow - 1))
            result = "\(header)\n\n\(shortened)\n\n\(footer)"
        }

        return result
    }

    private func editorialHeader(for article: PublishedArticle, variation: Int) -> String {
        let labels = [
            "🧭 Next Jailbreak take",
            "🔎 What matters",
            "⚡ Quick context",
            "📌 Update context"
        ]
        let index = positiveModulo(stableSeed(for: article) + variation, labels.count)
        return "\(labels[index]) — \(productLabel(for: article))"
    }

    private func commentary(for article: PublishedArticle, variation: Int) -> String {
        let factLine = headlineFact(for: article)
        let templates = [
            "What matters here: \(factLine). Before updating, check the compatibility and install notes against your exact setup.",
            "\(factLine). The headline is useful, but the compatibility details are the part to verify before you install.",
            "Quick context: \(factLine). If this affects your setup, read the compatibility section first rather than updating from the headline alone.",
            "Why this matters: \(factLine). We broke down the release details and the compatibility points worth checking before you make changes.",
            "Using \(clean(article.name))? \(factLine). Check the documented requirements for your exact iOS and jailbreak setup before updating."
        ]
        let index = positiveModulo(stableSeed(for: article) + variation, templates.count)
        return templates[index]
    }

    private func headlineFact(for article: PublishedArticle) -> String {
        let subject = productLabel(for: article)
        var title = clean(article.title)
        let name = clean(article.name)
        let version = article.version.map(clean) ?? ""

        let removablePrefixes = [
            version.isEmpty ? "" : "\(name) v\(version)",
            version.isEmpty ? "" : "\(name) \(version)",
            name
        ]
        .filter { !$0.isEmpty }
        .sorted { $0.count > $1.count }

        for prefix in removablePrefixes {
            if title.lowercased().hasPrefix(prefix.lowercased()) {
                title = String(title.dropFirst(prefix.count))
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":–—-")))
                break
            }
        }

        if title.isEmpty {
            return "\(subject) has a newly documented update"
        }

        return "\(subject) \(lowercaseFirstCharacter(title))"
    }

    private func productLabel(for article: PublishedArticle) -> String {
        let name = clean(article.name)
        guard let version = article.version.map(clean), !version.isEmpty else {
            return name
        }

        let loweredName = name.lowercased()
        let loweredVersion = version.lowercased()
        if loweredName.contains(loweredVersion) {
            return name
        }
        return "\(name) \(version)"
    }

    private func footerText(link: String, tags: [String]) -> String {
        "🔗 \(link)\n\(tags.joined(separator: " "))"
    }

    private func hashtags(for article: PublishedArticle) -> [String] {
        let combined = "\(article.title) \(article.description) \(article.category?.label ?? "")".lowercased()
        var tags: [String] = []

        if let nameTag = hashtag(article.name), nameTag.count <= 28 {
            tags.append(nameTag)
        }

        if combined.contains("jailbreak") || combined.contains("tweak") || combined.contains("rootless") {
            tags.append("#Jailbreak")
        } else {
            tags.append("#iOS")
        }

        if combined.contains("ios 27") || combined.contains("ios27") {
            tags.append("#iOS27")
        } else if combined.contains("ios 26") || combined.contains("ios26") {
            tags.append("#iOS26")
        } else if combined.contains("ios 17") || combined.contains("ios17") {
            tags.append("#iOS17")
        } else if combined.contains("ios 16") || combined.contains("ios16") {
            tags.append("#iOS16")
        } else {
            tags.append("#iPhone")
        }

        if combined.contains("rootless") {
            tags.append("#Rootless")
        } else if combined.contains("home screen") {
            tags.append("#HomeScreen")
        } else if combined.contains("lock screen") {
            tags.append("#LockScreen")
        } else if combined.contains("control center") {
            tags.append("#ControlCenter")
        } else if combined.contains("airpods") {
            tags.append("#AirPods")
        } else if combined.contains("keyboard") {
            tags.append("#Keyboard")
        }

        if !tags.contains("#iPhone") && tags.count < 4 {
            tags.append("#iPhone")
        }

        var seen = Set<String>()
        return tags.filter { seen.insert($0.lowercased()).inserted }.prefix(4).map { $0 }
    }

    private func hashtag(_ value: String) -> String? {
        let result = String(value.filter { $0.isLetter || $0.isNumber })
        guard result.count >= 2 else { return nil }
        return "#\(result)"
    }

    private func stableSeed(for article: PublishedArticle) -> Int {
        article.cleanURL.absoluteString.unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 31) &+ Int(scalar.value)
        }
    }

    private func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        guard divisor > 0 else { return 0 }
        let remainder = value % divisor
        return remainder >= 0 ? remainder : remainder + divisor
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
        cut = cut.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return cut + "…"
    }

    private func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: "##?", with: "details")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

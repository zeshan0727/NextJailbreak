import Foundation

@main
enum PostComposerSmokeTests {
    static func main() {
        let examples: [PublishedArticle] = [
            .init(
                name: "BandLock",
                title: "BandLock 1.3 Brings LTE, 5G NR and Country-Based Modem Controls",
                description: "BandLock 1.3 adds LTE, 5G NR and country-based modem controls to compatible iPhones.",
                href: "https://nextjailbreak.com/bandlock-1-3-update/",
                version: "1.3",
                category: ArticleCategory(id: "tweak", label: "Jailbreak Tweak")
            ),
            .init(
                name: "Enable JIT in Husk",
                title: "How to Enable JIT in Husk 0.7.0 with StikJIT, StikDebug or TrollStore",
                description: "Enable JIT in Husk using StikJIT, StikDebug or TrollStore on a compatible iPhone.",
                href: "https://nextjailbreak.com/how-to-enable-jit-husk-stikjit-trollstore/",
                version: nil,
                category: ArticleCategory(id: "guide", label: "Guide")
            ),
            .init(
                name: "Very Long Product Name",
                title: String(repeating: "Long jailbreak guide title ", count: 8),
                description: "This is a concise original summary describing the release and its compatibility.",
                href: "https://nextjailbreak.com/article-with-a-much-longer-link-to-test-how-the-budgeting-behaves-in-practice/",
                version: nil,
                category: ArticleCategory(id: "guide", label: "Guide")
            )
        ]

        let composer = PostComposer()
        for example in examples {
            let output = composer.compose(for: example, variation: 5)
            let lines = output.components(separatedBy: "\n")
            precondition(lines.count == 4, "Only the agreed four lines may appear")
            precondition(output.count <= PostComposer.maximumCharacters, "280-character limit exceeded")
            precondition(lines[0].count > 4 && !lines[1].isEmpty)
            precondition(lines[1].count >= 5)
            precondition(lines[2].hasPrefix("#"))
            precondition(lines[2].split(separator: " ").count <= 3)
            precondition(lines[3] == example.publishedURL.absoluteString)
            precondition(!output.localizedCaseInsensitiveContains("quick context"))
            precondition(!output.localizedCaseInsensitiveContains("update context"))
            precondition(!output.localizedCaseInsensitiveContains("what matters"))
            precondition(!output.localizedCaseInsensitiveContains("why this matters"))
            precondition(!output.localizedCaseInsensitiveContains("next jailbreak take"))
            precondition(composer.compose(for: example, variation: 17) == output, "No editorial randomization")
            print("PASS: \(output.count) characters for \(example.name)")
        }
    }
}

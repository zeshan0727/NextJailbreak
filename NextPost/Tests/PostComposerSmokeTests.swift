import Foundation

@main
enum PostComposerSmokeTests {
    static func main() {
        let samples: [PublishedArticle] = [
            .init(
                name: "TrollStore Lite migration",
                title: "How to Move TrollStore Apps to TrollStore Lite on a Jailbroken iPhone",
                description: "Move apps from full TrollStore to TrollStore Lite 2.1.1, understand AppSync registration, and avoid conflicts with existing installations.",
                href: "https://nextjailbreak.com/move-trollstore-apps-to-trollstore-lite-guide/",
                version: "2.1.1",
                category: ArticleCategory(id: "guide", label: "Guide")
            ),
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
                version: "0.7.0",
                category: ArticleCategory(id: "guide", label: "Guide")
            )
        ]

        let composer = PostComposer()
        for article in samples {
            let output = composer.compose(for: article, variation: 5)
            let sections = output.components(separatedBy: "\n\n")
            precondition(sections.count == 4, "Four distinct paragraphs required")
            precondition(output.count <= PostComposer.maximumCharacters, "280-character limit exceeded")
            precondition(sections[0].first?.isASCII == false, "Expected title emoji")
            precondition(!sections[1].isEmpty && (sections[1].hasSuffix(".") || sections[1].hasSuffix("!")))
            precondition(sections[2].hasPrefix("#") && sections[2].split(separator: " ").count <= 3)
            precondition(sections[3] == "🔗 \(article.publishedURL.absoluteString)")
            for banned in ["quick context", "update context", "what matters", "why this matters"] {
                precondition(!output.localizedCaseInsensitiveContains(banned))
            }
            precondition(composer.compose(for: article, variation: 91) == output)
            let xText = PostComposer.xIntentText(generatedPost: output, articleURL: article.publishedURL)
            precondition(xText.hasSuffix("\n\n🔗"), "X url marker must be in own paragraph")
            precondition(xText + " " + article.publishedURL.absoluteString == output,
                         "X prefill should exactly preserve formatted preview")
            precondition(!output.contains("utm_source="), "Tracking clutter should be absent")
            print("PASS: \(article.name): \(output.count) chars\n\(output)\n")
        }
    }
}

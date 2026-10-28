import Foundation

struct PasswordBreakdown {
    let cleanedSite: String
    let letterCount: Int
    let firstLetter: Character?
    let firstPosition: Int
    let lastLetter: Character?
    let lastPosition: Int

    var password: String {
        guard letterCount > 0 else { return "MpMr@" }
        return String(format: "MpMr@%d%02d%02d", letterCount, firstPosition, lastPosition)
    }
}

enum PasswordGenerator {
    static func breakdown(site: String) -> PasswordBreakdown {
        let letters = site
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter { $0.isLetter }

        let first = letters.first
        let last = letters.last

        return PasswordBreakdown(
            cleanedSite: letters,
            letterCount: letters.count,
            firstLetter: first,
            firstPosition: alphabetPosition(first),
            lastLetter: last,
            lastPosition: alphabetPosition(last)
        )
    }

    static func websiteBased(site: String) -> String {
        breakdown(site: site).password
    }

    private static func alphabetPosition(_ character: Character?) -> Int {
        guard let character,
              let scalar = String(character).unicodeScalars.first else { return 0 }
        let value = Int(scalar.value)
        guard value >= 65, value <= 90 else { return 0 }
        return value - 64
    }
}

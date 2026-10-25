import Foundation

// Mirror the authoritative Windows AccountantsNext
// Services/OperationalEntityPolicy.cs (6.1.25).
// Historical/non-operational entity rows are retained in SQLite and never deleted.
enum MobileOperationalEntityPolicy {
    private static let canonicalKeys = [
        "barjous", "atelierhome", "eradafitness", "northsports",
        "thegraphitees", "stonecafe", "levantebags"
    ]

    private static func normalized(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return String(folded.lowercased().unicodeScalars.filter {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        })
    }

    private static func key(_ name: String) -> String? {
        switch normalized(name) {
        case "barjous", "barjousarchitects":
            return "barjous"
        case "atelier", "atelierhome":
            return "atelierhome"
        case "erada", "eradafitness", "cferada":
            return "eradafitness"
        case "northsports", "northsport":
            return "northsports"
        case "graphitees", "thegraphitees", "graphite":
            return "thegraphitees"
        case "stonecafe", "stonecaf":
            return "stonecafe"
        case "levantebags", "levantebag", "levante":
            return "levantebags"
        default:
            return nil
        }
    }

    static func filter(_ entries: [EntityRow]) -> [EntityRow] {
        // Preserve canonical ordering and, for aliases, the first matching
        // active entity. Never add an unknown database entity to the UI.
        let mapped = entries.compactMap { entry -> (EntityRow, String)? in
            guard let canonical = key(entry.name) else { return nil }
            return (entry, canonical)
        }
        var seenIDs = Set<Int64>()
        var result: [EntityRow] = []
        for canonical in canonicalKeys {
            for (entry, key) in mapped where key == canonical {
                if seenIDs.insert(entry.id).inserted { result.append(entry) }
            }
        }
        return result
    }
}

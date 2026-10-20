import Foundation
import ZIPFoundation

/// Reads the original identity from a source IPA/TIPA without extracting the
/// complete application, loading executables or guessing from staged filenames.
struct IPAIdentity {
    let appName: String
    let bundleID: String
}

enum IPAIdentityReaderError: LocalizedError {
    case unreadableArchive
    case missingMainInfoPlist
    case oversizedInfoPlist
    case invalidInfoPlist
    case invalidBundleIdentifier

    var errorDescription: String? {
        switch self {
        case .unreadableArchive:
            return "The selected IPA/TIPA is not a readable ZIP archive."
        case .missingMainInfoPlist:
            return "No main Payload/*.app/Info.plist was found in the IPA."
        case .oversizedInfoPlist:
            return "The IPA's main Info.plist exceeds the safe metadata limit."
        case .invalidInfoPlist:
            return "The IPA's main app Info.plist is not a valid property list."
        case .invalidBundleIdentifier:
            return "The IPA has no usable CFBundleIdentifier. Select a valid application IPA."
        }
    }
}

struct IPAIdentityReader {
    static func read(from url: URL) throws -> IPAIdentity {
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw IPAIdentityReaderError.unreadableArchive
        }
        guard let entry = archive.first(where: { entry in
            let parts = entry.path.split(separator: "/", omittingEmptySubsequences: true)
            return parts.count == 3 &&
                parts[0] == "Payload" &&
                parts[1].lowercased().hasSuffix(".app") &&
                parts[2] == "Info.plist"
        }) else {
            throw IPAIdentityReaderError.missingMainInfoPlist
        }
        guard entry.uncompressedSize > 0, entry.uncompressedSize <= 2_000_000 else {
            throw IPAIdentityReaderError.oversizedInfoPlist
        }

        var infoData = Data()
        _ = try archive.extract(entry, consumer: { chunk in
            infoData.append(chunk)
        })
        guard let info = try PropertyListSerialization.propertyList(
            from: infoData, format: nil) as? [String: Any] else {
            throw IPAIdentityReaderError.invalidInfoPlist
        }
        let bundleID = ((info["CFBundleIdentifier"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        guard bundleID.contains("."), !bundleID.hasPrefix("."),
              !bundleID.hasSuffix("."), !bundleID.contains(".."),
              bundleID.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw IPAIdentityReaderError.invalidBundleIdentifier
        }

        // Prefer the real display name over a UUID-prefixed cached filename.
        let candidates = [
            info["CFBundleDisplayName"] as? String,
            info["CFBundleName"] as? String,
            String(entry.path.split(separator: "/")[1].dropLast(4))
        ].compactMap { $0 }
        let appName = candidates.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && !$0.contains("$(") }) ?? "Signed App"
        return IPAIdentity(appName: appName, bundleID: bundleID)
    }
}

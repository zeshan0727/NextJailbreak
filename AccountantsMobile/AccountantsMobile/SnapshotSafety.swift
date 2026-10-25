import Foundation
import GRDB
import ZIPFoundation

struct ImportedSnapshotInfo: Codable {
    let sourceName: String
    let importedAt: String
    let databaseBytes: Int64
    let fileCount: Int
    let validation: String

    static func load(at root: URL) -> ImportedSnapshotInfo? {
        let file = root.appendingPathComponent("MobileSnapshotInfo.json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(ImportedSnapshotInfo.self, from: data)
    }
}

enum SnapshotSafetyError: LocalizedError {
    case wrongFileType
    case oversized
    case unsafeArchive
    case tooManyFiles
    case corruptDatabase
    case missingEntities
    case missingDatabase
    case noPreviousSnapshot

    var errorDescription: String? {
        switch self {
        case .wrongFileType: return "Select the full AccountantsNext Windows backup ZIP or AccountantsNext.db."
        case .oversized: return "The backup exceeds the safe mobile import size limit. Use a smaller Windows recovery package."
        case .unsafeArchive: return "The ZIP contains unsafe file paths or unsupported links. Import cancelled without changing existing data."
        case .tooManyFiles: return "The ZIP contains too many files. Import cancelled to protect device storage."
        case .corruptDatabase: return "SQLite integrity checks failed. The existing mobile snapshot was left unchanged."
        case .missingEntities: return "The selected SQLite file is not a compatible AccountantsNext database (Entities table missing)."
        case .missingDatabase: return "Data/AccountantsNext.db was not found inside the backup."
        case .noPreviousSnapshot: return "No previous verified mobile snapshot is available to restore."
        }
    }
}

enum SnapshotSafety {
    // Conservative limits for a managed on-device HR / finance archive.
    static let maximumArchiveBytes: Int64 = 1_500_000_000
    static let maximumUnpackedBytes: Int64 = 3_000_000_000
    static let maximumFiles = 30_000

    static func checkSource(_ source: URL) throws {
        let ext = source.pathExtension.lowercased()
        guard ["zip", "db", "sqlite", "sqlite3"].contains(ext)
                || source.lastPathComponent.lowercased() == "accountantsnext.db"
        else { throw SnapshotSafetyError.wrongFileType }

        let bytes = Int64((try source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard bytes > 0 && bytes <= maximumArchiveBytes else { throw SnapshotSafetyError.oversized }

        if ext == "zip" {
            guard let archive = Archive(url: source, accessMode: .read) else {
                throw SnapshotSafetyError.unsafeArchive
            }
            var count = 0
            var total: Int64 = 0
            var foundDatabase = false
            for entry in archive {
                count += 1
                guard count <= maximumFiles else { throw SnapshotSafetyError.tooManyFiles }
                let path = entry.path.replacingOccurrences(of: "\\", with: "/")
                let parts = path.split(separator: "/", omittingEmptySubsequences: false)
                guard !path.hasPrefix("/"),
                      !path.hasPrefix("~"),
                      !path.contains(":"),
                      path.count < 700,
                      !parts.contains(".."),
                      !parts.contains("."),
                      entry.type != .symlink else {
                    throw SnapshotSafetyError.unsafeArchive
                }
                guard UInt64(entry.uncompressedSize) <= UInt64(maximumUnpackedBytes) else {
                    throw SnapshotSafetyError.oversized
                }
                let size = Int64(entry.uncompressedSize)
                guard size >= 0 && total <= maximumUnpackedBytes - size else {
                    throw SnapshotSafetyError.oversized
                }
                total += size
                if path.hasSuffix("/Data/AccountantsNext.db") || path == "Data/AccountantsNext.db" {
                    foundDatabase = true
                }
            }
            guard foundDatabase else { throw SnapshotSafetyError.missingDatabase }
        }
    }

    static func validateDatabase(_ dbURL: URL) throws {
        var options = Configuration()
        options.readonly = true
        let queue = try DatabaseQueue(path: dbURL.path, configuration: options)
        let results = try queue.read { db -> (String, Int) in
            let integrity = try String.fetchOne(db, sql: "PRAGMA quick_check(1)") ?? "invalid"
            let entities = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'Entities'") ?? 0
            return (integrity, entities)
        }
        guard results.0.lowercased() == "ok" else { throw SnapshotSafetyError.corruptDatabase }
        guard results.1 > 0 else { throw SnapshotSafetyError.missingEntities }
    }

    static func safeDatabaseCandidate(under directory: URL) throws -> URL {
        let direct = directory.appendingPathComponent("Data/AccountantsNext.db")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        guard let walker = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { throw SnapshotSafetyError.missingDatabase }
        var candidates: [URL] = []
        for case let file as URL in walker {
            if file.lastPathComponent != "AccountantsNext.db" { continue }
            let vals = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if vals.isRegularFile == true, vals.isSymbolicLink != true, file.deletingLastPathComponent().lastPathComponent == "Data" {
                candidates.append(file)
            }
            if candidates.count > 1 { throw SnapshotSafetyError.unsafeArchive }
        }
        guard let db = candidates.first else { throw SnapshotSafetyError.missingDatabase }
        return db
    }

    static func protect(_ root: URL) throws {
        let fm = FileManager.default
        guard let walker = fm.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { throw SnapshotSafetyError.unsafeArchive }

        // Protect every restored document, not just AccountantsNext.db.
        for case let path as URL in walker {
            try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path.path)
        }
        try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: root.path)
    }
}

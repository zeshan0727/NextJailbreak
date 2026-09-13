import Foundation
import ZIPFoundation

struct LocalSignedApp: Identifiable, Codable, Equatable {
    let id: UUID
    let filename: String
    let appName: String
    let bundleID: String
    let version: String
    let build: String
    let minimumOS: String
    let signedAt: Date

    var ipaURL: URL {
        LocalSignedAppsRepository.folderURL.appendingPathComponent(filename)
    }

    var sizeBytes: Int64 {
        let values = try? ipaURL.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}

enum LocalSignedAppsRepository {
    static var folderURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Signed IPAs", isDirectory: true)
    }

    private static var legacyFolderURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NextSigner Signed", isDirectory: true)
    }

    private static var indexURL: URL {
        folderURL.appendingPathComponent("signed-apps.json")
    }

    static func load() -> [LocalSignedApp] {
        do {
            try prepareFolderAndMigrateLegacy()
            var records: [LocalSignedApp] = []
            if FileManager.default.fileExists(atPath: indexURL.path) {
                let data = try Data(contentsOf: indexURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                records = try decoder.decode([LocalSignedApp].self, from: data)
                    .filter { FileManager.default.fileExists(atPath: $0.ipaURL.path) }
            }

            let known = Set(records.map { $0.filename })
            let files = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
            for url in files where url.pathExtension.lowercased() == "ipa" && !known.contains(url.lastPathComponent) {
                if let record = inspectIPA(url) {
                    records.append(record)
                }
            }

            records.sort { $0.signedAt > $1.signedAt }
            try save(records)
            return records
        } catch {
            return []
        }
    }

    static func register(_ result: SignedAppResult) throws -> LocalSignedApp {
        let fm = FileManager.default
        let safeName = result.ipaURL.lastPathComponent.replacingOccurrences(of: "/", with: "-")
        let destination = folderURL.appendingPathComponent(safeName)

        // prepareFolderAndMigrateLegacy() may move the just-created IPA from the
        // legacy output folder into Signed IPAs. Do not delete that migrated copy
        // and then try to move a source file that no longer exists.
        try prepareFolderAndMigrateLegacy()

        if result.ipaURL.standardizedFileURL != destination.standardizedFileURL {
            let sourceExists = fm.fileExists(atPath: result.ipaURL.path)
            let destinationExists = fm.fileExists(atPath: destination.path)

            if sourceExists {
                if destinationExists {
                    try fm.removeItem(at: destination)
                }
                try fm.moveItem(at: result.ipaURL, to: destination)
            } else if !destinationExists {
                throw CocoaError(.fileNoSuchFile)
            }
        }

        let record = LocalSignedApp(
            id: UUID(),
            filename: destination.lastPathComponent,
            appName: result.appName,
            bundleID: result.bundleID,
            version: result.version,
            build: result.build,
            minimumOS: result.minimumOS,
            signedAt: Date()
        )

        var records = load().filter { $0.filename != record.filename }
        records.insert(record, at: 0)
        try save(records)
        return record
    }

    static func delete(_ app: LocalSignedApp) throws {
        if FileManager.default.fileExists(atPath: app.ipaURL.path) {
            try FileManager.default.removeItem(at: app.ipaURL)
        }
        let records = load().filter { $0.id != app.id && $0.filename != app.filename }
        try save(records)
    }

    private static func prepareFolderAndMigrateLegacy() throws {
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )

        guard FileManager.default.fileExists(atPath: legacyFolderURL.path) else { return }
        let legacyFiles = (try? FileManager.default.contentsOfDirectory(
            at: legacyFolderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        for source in legacyFiles where source.pathExtension.lowercased() == "ipa" {
            let destination = folderURL.appendingPathComponent(source.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            try? FileManager.default.moveItem(at: source, to: destination)
        }
    }

    private static func save(_ records: [LocalSignedApp]) throws {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(records).write(to: indexURL, options: .atomic)
    }

    private static func inspectIPA(_ ipaURL: URL) -> LocalSignedApp? {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("NextSigner-Inspect-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: temp) }

        do {
            try fm.createDirectory(at: temp, withIntermediateDirectories: true)
            try fm.unzipItem(at: ipaURL, to: temp)
            let payload = temp.appendingPathComponent("Payload", isDirectory: true)
            let apps = try fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            guard let app = apps.first(where: { $0.pathExtension.lowercased() == "app" }) else { return nil }
            let plistData = try Data(contentsOf: app.appendingPathComponent("Info.plist"))
            guard let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else { return nil }

            let name = (plist["CFBundleDisplayName"] as? String)
                ?? (plist["CFBundleName"] as? String)
                ?? ipaURL.deletingPathExtension().lastPathComponent
            let bundleID = (plist["CFBundleIdentifier"] as? String) ?? "unknown.bundle"
            let version = (plist["CFBundleShortVersionString"] as? String) ?? ""
            let build = (plist["CFBundleVersion"] as? String) ?? ""
            let minimumOS = (plist["MinimumOSVersion"] as? String) ?? "iOS"
            let signedAt = (try? ipaURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()

            return LocalSignedApp(
                id: UUID(),
                filename: ipaURL.lastPathComponent,
                appName: name,
                bundleID: bundleID,
                version: version,
                build: build,
                minimumOS: minimumOS,
                signedAt: signedAt
            )
        } catch {
            return nil
        }
    }
}

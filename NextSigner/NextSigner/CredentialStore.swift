import Foundation

enum CredentialStore {
    enum Kind {
        case p12
        case provisioning

        var filename: String {
            switch self {
            case .p12: return "signing.p12"
            case .provisioning: return "signing.mobileprovision"
            }
        }
    }

    static func url(for kind: Kind) -> URL {
        credentialsDirectory.appendingPathComponent(kind.filename)
    }

    static func exists(_ kind: Kind) -> Bool {
        FileManager.default.fileExists(atPath: url(for: kind).path)
    }

    static func importFile(from source: URL, as kind: Kind) throws {
        let accessed = source.startAccessingSecurityScopedResource()
        defer {
            if accessed { source.stopAccessingSecurityScopedResource() }
        }

        try FileManager.default.createDirectory(
            at: credentialsDirectory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )

        let destination = url(for: kind)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destination.path
        )
    }

    static func remove(_ kind: Kind) {
        try? FileManager.default.removeItem(at: url(for: kind))
    }

    private static var credentialsDirectory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("NextSignerCredentials", isDirectory: true)
    }
}

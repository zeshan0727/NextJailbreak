import Foundation
import ZIPFoundation

struct ImportedIPA {
    let name: String
    let identifier: String
    let version: String
    let sourceURL: URL
    let executableRelativePath: String
    let imports: [ImportRecord]
}

struct PatchExport {
    let ipa: URL
    let receipt: PatchReceipt
}

struct IPAService {
    private let fm = FileManager.default

    private func withExtracted<T>(_ source: URL, _ body: (URL, URL, [String: Any]) throws -> T) throws -> T {
        let workspace = fm.temporaryDirectory.appendingPathComponent("nextcompat-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workspace) }
        let root = workspace.appendingPathComponent("Unpacked", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = try Archive(url: source, accessMode: .read)
        var unpacked: UInt64 = 0
        for entry in archive {
            let path = entry.path
            let pieces = path.split(separator: "/")
            guard !path.hasPrefix("/"), !path.contains("\\"), !pieces.contains(".."),
                  !path.contains("\0"), !pieces.isEmpty else {
                throw MachOError.invalid("Unsafe archive entry: \(path)")
            }
            unpacked += UInt64(entry.uncompressedSize)
            guard unpacked < 2_000_000_000 else { throw MachOError.invalid("IPA expanded size exceeds 2 GB limit") }
        }
        try fm.unzipItem(at: source, to: root)
        let payload = root.appendingPathComponent("Payload")
        guard let contents = try? fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil),
              let app = contents.first(where: { $0.pathExtension == "app" }),
              let plist = NSDictionary(contentsOf: app.appendingPathComponent("Info.plist")) as? [String: Any],
              let exeName = plist["CFBundleExecutable"] as? String,
              !exeName.contains("/"), !exeName.contains("..") else {
            throw MachOError.invalid("IPA is missing its app bundle or executable metadata")
        }
        return try body(root, app.appendingPathComponent(exeName), plist)
    }

    func inspect(_ source: URL) throws -> ImportedIPA {
        try withExtracted(source) { root, binary, plist in
            let reader = try MachOPatcher(url: binary)
            return ImportedIPA(
                name: (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String) ?? "Imported App",
                identifier: (plist["CFBundleIdentifier"] as? String) ?? "Unknown",
                version: (plist["CFBundleShortVersionString"] as? String) ?? "—",
                sourceURL: source,
                executableRelativePath: String(binary.path.dropFirst(root.path.count + 1)),
                imports: reader.imports
            )
        }
    }

    func patch(source: URL, symbol: String, outputFolder: URL) throws -> PatchExport {
        try withExtracted(source) { root, binary, _ in
            var editor = try MachOPatcher(url: binary)
            let change = try editor.makeWeak(symbol: symbol)
            try editor.write(to: binary)
            let verification = try MachOPatcher(url: binary)
            guard verification.imports.contains(where: { $0.symbol == symbol && $0.weak }) else {
                throw MachOError.invalid("Patch verification failed")
            }
            try fm.createDirectory(at: outputFolder, withIntermediateDirectories: true)
            let output = outputFolder.appendingPathComponent("NextCompat-\(UUID().uuidString.prefix(8)).ipa")
            try fm.zipItem(at: root, to: output, shouldKeepParent: false, compressionMethod: .deflate)
            return PatchExport(ipa: output, receipt: change)
        }
    }
}


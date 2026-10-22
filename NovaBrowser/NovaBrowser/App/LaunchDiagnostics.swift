import Foundation

/// Minimal, offline launch breadcrumbs that remain readable in Files > NovaBrowser.
/// Records no browsing URLs, page contents, credentials, or private-tab activity.
enum LaunchDiagnostics {
    private static let lock = NSLock()

    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NovaBrowserDiagnostics.txt")
    }

    static func record(_ event: String) {
        lock.lock()
        defer { lock.unlock() }
        let file = fileURL
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: file.path) {
                try Data().write(to: file)
            }
            let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(event)\n"
            let handle = try FileHandle(forWritingTo: file)
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
        } catch {
            NSLog("NovaBrowser diagnostics unavailable: %@", error.localizedDescription)
        }
    }

    static func read() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "No launch diagnostics available."
    }
}

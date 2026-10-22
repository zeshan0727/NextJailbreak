import Foundation

/// Bounded, content-free WebKit diagnostics. No URLs, tokens, chat contents or request headers.
enum WebDiagnostics {
    private static let lock = NSLock()
    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NovaBrowserWebDiagnostics.txt")
    }

    static func record(host: String, event: String) {
        lock.lock()
        defer { lock.unlock() }
        let safeHost = String(host.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }.prefix(100))
        let safeEvent = String(event.filter { $0.isASCII && ($0.isLetter || $0.isNumber || " .:-_=".contains($0)) }.prefix(140))
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(safeHost): \(safeEvent)\n"
        do {
            let url = fileURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let previous = (try? Data(contentsOf: url)) ?? Data()
            let data = previous.count > 80_000 ? Data(previous.suffix(60_000)) : previous
            try (data + Data(line.utf8)).write(to: url, options: .atomic)
        } catch {
            NSLog("Web diagnostics write failed")
        }
    }

    static func read() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "No web diagnostics captured yet."
    }
}

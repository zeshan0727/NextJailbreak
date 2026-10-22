import Foundation
import Combine

/// GitHub release downloader with IPA validation and public-link fallback.
@MainActor
final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var progress: Double = 0
    @Published var busy = false
    @Published var files: [StoredDownload] = []
    @Published var error: String?
    @Published var completedFile: URL?
    @Published var currentName = ""

    override init() { super.init(); reload() }

    private var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func reload() {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: documents, includingPropertiesForKeys: nil)) ?? []
        files = contents.filter { $0.pathExtension.lowercased() == "ipa" }
            .map(StoredDownload.init)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func start(asset: GitHubAsset, releaseTag: String, token: String, owner: String, repo: String) async {
        guard !busy else { return }
        busy = true; progress = 0; error = nil; completedFile = nil; currentName = asset.name
        defer { busy = false; reload() }

        let name = URL(fileURLWithPath: asset.name).lastPathComponent
        guard !name.isEmpty, URL(fileURLWithPath: name).pathExtension.lowercased() == "ipa" else {
            error = "Select an IPA release asset."
            return
        }
        var failures: [String] = []
        if let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/assets/\(asset.id)") {
            var request = URLRequest(url: url)
            if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.timeoutInterval = 120
            do {
                try await retrieve(request, asset: asset, filename: name, tag: releaseTag)
                return
            } catch {
                failures.append("GitHub API: \(error.localizedDescription)")
            }
        }

        // Public GitHub release assets can be downloaded directly without API authentication.
        if let url = URL(string: asset.browser_download_url),
           url.scheme == "https" && url.host == "github.com" {
            var request = URLRequest(url: url)
            request.timeoutInterval = 120
            progress = 0
            do {
                try await retrieve(request, asset: asset, filename: name, tag: releaseTag)
                return
            } catch {
                failures.append("Direct release: \(error.localizedDescription)")
            }
        }
        error = failures.joined(separator: "\n")
    }

    private func retrieve(_ request: URLRequest, asset: GitHubAsset, filename: String,
                          tag: String) async throws {
        let (temporary, response) = try await URLSession.shared.download(for: request, delegate: self)
        guard let http = response as? HTTPURLResponse else {
            throw ForgeError.message("GitHub did not return an HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw ForgeError.message("HTTP \(http.statusCode). Check repository access and token permissions.")
        }
        try Self.validateIPA(at: temporary, expectedSize: asset.size)
        let safeTag = String(tag.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "-" }.prefix(50))
        let destination = documents.appendingPathComponent("\(safeTag)-\(filename)")
        let staging = documents.appendingPathComponent(UUID().uuidString + ".download")
        do {
            try FileManager.default.copyItem(at: temporary, to: staging)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: staging, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        progress = 1
        completedFile = destination
    }

    /// Verify a real ZIP central directory and the iOS Payload/*.app layout.
    /// A GitHub metadata JSON response must never be saved with an .ipa extension.
    private static func validateIPA(at url: URL, expectedSize: Int64) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        guard size >= 22 else { throw ForgeError.message("Downloaded file is too small to be an IPA") }
        if expectedSize > 0 && UInt64(expectedSize) != size {
            throw ForgeError.message("Incomplete download: expected \(expectedSize) bytes, got \(size)")
        }
        try handle.seek(toOffset: 0)
        guard try handle.read(upToCount: 4) == Data([0x50, 0x4B, 0x03, 0x04]) else {
            throw ForgeError.message("GitHub returned HTML or JSON instead of an IPA")
        }
        let tailSize = Int(min(size, 65_557))
        try handle.seek(toOffset: size - UInt64(tailSize))
        let tail = try handle.read(upToCount: tailSize) ?? Data()
        func number(_ data: Data, at offset: Int, count: Int) -> UInt64 {
            guard offset >= 0, count > 0, offset + count <= data.count else { return .max }
            return (0..<count).reduce(UInt64(0)) { sum, index in
                sum | (UInt64(data[offset + index]) << (8 * index))
            }
        }
        var endRecord: Int?
        if tail.count >= 22 {
            for i in stride(from: tail.count - 22, through: 0, by: -1) {
                if number(tail, at: i, count: 4) == 0x06054b50,
                   number(tail, at: i + 20, count: 2) == UInt64(tail.count - i - 22) {
                    endRecord = i
                    break
                }
            }
        }
        guard let eocd = endRecord else {
            throw ForgeError.message("Incomplete ZIP: missing end-of-central-directory record")
        }
        let cdSize = number(tail, at: eocd + 12, count: 4)
        let cdStart = number(tail, at: eocd + 16, count: 4)
        guard cdSize > 0, cdSize <= 32 * 1024 * 1024,
              cdSize != 0xffff_ffff, cdStart != 0xffff_ffff,
              cdStart <= size, cdSize <= size - cdStart else {
            throw ForgeError.message("IPA ZIP directory is invalid or unsupported")
        }
        try handle.seek(toOffset: cdStart)
        let directory = try handle.read(upToCount: Int(cdSize)) ?? Data()
        guard directory.count == Int(cdSize),
              directory.range(of: Data("Payload/".utf8)) != nil,
              directory.range(of: Data(".app/".utf8)) != nil else {
            throw ForgeError.message("The downloaded ZIP does not contain Payload/*.app")
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in
            if totalBytesExpectedToWrite > 0 {
                self.progress = min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
            }
        }
    }

    func delete(_ file: StoredDownload) throws {
        try FileManager.default.removeItem(at: file.url)
        if completedFile == file.url { completedFile = nil }
        reload()
    }
}

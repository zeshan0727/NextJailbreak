import Foundation
import Combine

/// URLSession delegate exposes actual network byte progress to SwiftUI.
@MainActor
final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var progress: Double = 0
    @Published var busy = false
    @Published var files: [StoredDownload] = []
    @Published var error: String?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<Void, Never>?

    override init() { super.init(); reload() }

    private var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func reload() {
        let contents = (try? FileManager.default.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil)) ?? []
        files = contents.filter { ["ipa", "tipa"].contains($0.pathExtension.lowercased()) }
            .map(StoredDownload.init).sorted { $0.name > $1.name }
    }

    func start(asset: GitHubAsset, token: String, owner: String, repo: String) async {
        guard !busy else { return }
        busy = true; progress = 0; error = nil
        do {
            let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/assets/\(asset.id)")!
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
            req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForResource = 300
            let localSession = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
            session = localSession
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                task = localSession.downloadTask(with: req)
                task?.taskDescription = URL(fileURLWithPath: asset.name).lastPathComponent
                task?.resume()
            }
        }
        session?.invalidateAndCancel(); session = nil; task = nil
        busy = false
        reload()
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

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        // Copy synchronously inside this callback: URLSession removes the temporary file afterward.
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        let mime = downloadTask.response?.mimeType ?? ""
        let name = downloadTask.taskDescription ?? "download.ipa"
        guard status == 200, mime != "application/json" else {
            Task { @MainActor in self.error = "Download failed: HTTP \(status), \(mime)" }
            return
        }
        do {
            let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destination = base.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.copyItem(at: location, to: destination)
            Task { @MainActor in self.progress = 1; self.reload() }
        } catch {
            let details = error.localizedDescription
            Task { @MainActor in self.error = details }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let message = error?.localizedDescription
        Task { @MainActor in
            if let message { self.error = message }
            self.continuation?.resume()
            self.continuation = nil
        }
    }

    func delete(_ file: StoredDownload) throws {
        try FileManager.default.removeItem(at: file.url)
        reload()
    }

    func saveAsTIPA(_ file: StoredDownload) throws {
        let name = file.url.deletingPathExtension().lastPathComponent
        let output = documents.appendingPathComponent(name + ".tipa")
        if output == file.url { return }
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        try FileManager.default.copyItem(at: file.url, to: output)
        reload()
    }
}

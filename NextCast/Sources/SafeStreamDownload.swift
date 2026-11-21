import Foundation

/// Compatibility downloader for installations where the system-managed
/// CFNetworkDownload_*.tmp file is inaccessible to a TrollStore-installed app.
/// Unlike URLSessionDownloadTask, the data task delivers network chunks and
/// writes them directly into the app's own private file. No large Data object
/// is retained. The app must remain active for this foreground-only fallback.
final class SafeStreamDownload: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    let id: UUID
    let destination: URL
    private let request: URLRequest
    private let progress: (Int64, Int64) -> Void
    private let completed: (Result<URL, Error>) -> Void
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "NextCast Safe Stream"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var handle: FileHandle?
    private var received: Int64 = 0
    private var expected: Int64 = -1
    private var serverError: Error?
    private var finished = false

    init(id: UUID, request: URLRequest, destination: URL,
         progress: @escaping (Int64, Int64) -> Void,
         completed: @escaping (Result<URL, Error>) -> Void) {
        self.id = id
        self.request = request
        self.destination = destination
        self.progress = progress
        self.completed = completed
        super.init()
    }

    func start() throws {
        let folder = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        // Verify writable access BEFORE the HTTP request starts, not after
        // multiple gigabytes have reached 100%. A zero-byte atomic write
        // avoids the misleading success of FileManager.createFile().
        do {
            try Data().write(to: destination, options: .atomic)
            handle = try FileHandle(forWritingTo: destination)
        } catch {
            throw NSError(domain: "NextCast.SafeStream", code: 101,
                          userInfo: [NSLocalizedDescriptionKey:
                            "Cannot create a video file in Movies. No download data was used. \(error.localizedDescription)"])
        }
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 120
        let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    func suspend() { task?.suspend() }
    func resume() { task?.resume() }
    func cancel() {
        task?.cancel()
        session?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            serverError = NSError(domain: "NextCast.SafeStream", code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey:
                    "Server returned HTTP \(http.statusCode). Please refresh the download URL."])
            completionHandler(.cancel)
            return
        }
        if let mime = response.mimeType?.lowercased(),
           mime.contains("text/html") || mime.contains("application/json") {
            serverError = NSError(domain: "NextCast.SafeStream", code: 102,
                userInfo: [NSLocalizedDescriptionKey:
                    "The server returned a webpage instead of a video file."])
            completionHandler(.cancel)
            return
        }
        expected = response.expectedContentLength
        // Check usable free space before receiving the large response body.
        // The movie is streamed in-place, without a second full-size copy.
        if expected > 0,
           let available = try? destination.deletingLastPathComponent()
              .resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity,
           Int64(available) < expected + 128 * 1024 * 1024 {
            serverError = NSError(domain: "NextCast.SafeStream", code: 104,
                userInfo: [NSLocalizedDescriptionKey:
                    "Not enough free iPhone storage for this movie. Free space before retrying."])
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        guard !finished else { return }
        do {
            try handle?.write(contentsOf: data)
            received += Int64(data.count)
            let bytes = received
            let total = expected
            DispatchQueue.main.async { [progress] in progress(bytes, total) }
        } catch {
            serverError = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard !finished else { return }
        finished = true
        do { try handle?.close() }
        catch { serverError = serverError ?? error }
        handle = nil
        self.task = nil
        self.session = nil
        session.finishTasksAndInvalidate()

        if let failure = serverError ?? error {
            DispatchQueue.main.async { [completed] in completed(.failure(failure)) }
            return
        }
        guard received > 0, expected <= 0 || received == expected else {
            let failure = NSError(domain: "NextCast.SafeStream", code: 103,
                userInfo: [NSLocalizedDescriptionKey: "The downloaded file was incomplete."])
            DispatchQueue.main.async { [completed] in completed(.failure(failure)) }
            return
        }
        let file = destination
        // The file already resides in the app-owned Movies directory.
        // Finalization only renames it and updates the library manifest.
        DispatchQueue.main.async { [completed] in completed(.success(file)) }
    }
}

import Foundation
import SwiftUI
import Combine
import UIKit

/// Real iOS background downloads. Foreground UI is not required for transfers
/// to continue; the OS manages network service and launch events.
struct DownloadRecord: Codable, Identifiable {
    var id: UUID
    var name: String
    var url: String
    var status: String
    var created: Date
    var received: Int64 = 0
    var expected: Int64 = 0
    var speed: Double = 0
    var mode: String = "Single connection"
    var origin: String = "Direct"
    var savedPath: String?
    var segmentCount: Int = 1
    var runToken: String? = nil

    var fraction: Double { expected > 0 ? min(1, Double(received) / Double(expected)) : 0 }
    var remaining: TimeInterval? {
        guard speed > 1024, expected > received else { return nil }
        return Double(expected - received) / speed
    }
    var isActive: Bool { status == "Downloading" || status == "Checking server" || status == "Finalizing" }
    var isPaused: Bool { status == "Paused" }
    var canRetry: Bool { status != "Finalizing" && status != "Added to Movies" && status != "Saved to Downloads" }
}

@MainActor
final class TransferStore: NSObject, ObservableObject, @preconcurrency URLSessionDownloadDelegate {
    static let shared = TransferStore()
    static let sessionID = "uk.zeshanbarvi.nextcast.background.downloads"
    @Published private(set) var items: [DownloadRecord] = []
    @Published var error: String?
    weak var library: MovieLibrary?
    var backgroundEventsCompletion: (() -> Void)?
    private let storeKey = "nextcast.background.records.v1"
    private var requestByID: [UUID: URLRequest] = [:]
    private var taskBytes: [UUID: [Int: Int64]] = [:]
    private var samples: [UUID: (Date, Int64)] = [:]
    private var segmentFallbackIDs = Set<UUID>()
    private var finishedParts: [UUID: Set<Int>] = [:]
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionID)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    // Isolate incomplete transfers from the user-visible Documents area.
    // The former Documents/Transfer Staging directory can have restrictive
    // ownership after TrollStore updates or Files-provider operations.
    // A fresh, privately owned Application Support directory prevents that
    // permission issue and is suitable for secure background file assembly.
    private static var stagingFolder: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("NextCastTransferWork-v2", isDirectory: true)
    }

    private static func prepareWorkingDirectory() throws {
        let directory = stagingFolder
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        var resource = URLResourceValues()
        resource.isExcludedFromBackup = true
        var directoryURL = directory
        try? directoryURL.setResourceValues(resource)
    }

    private static func safeStage(_ source: URL, at destination: URL) throws {
        try prepareWorkingDirectory()
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            // Background URLSession uses a transient download location.
            // A copy is safer when a file-provider denies moving the source.
            try FileManager.default.copyItem(at: source, to: destination)
        }
        guard FileManager.default.isReadableFile(atPath: destination.path) else {
            throw NSError(domain: "NextCast.TransferStorage", code: 13, userInfo: [
                NSLocalizedDescriptionKey: "Downloaded file could not be read after staging."
            ])
        }
    }

    override private init() {
        super.init()
        do {
            try Self.prepareWorkingDirectory()
        } catch {
            self.error = "Download storage setup failed: \(error.localizedDescription)"
        }
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let records = try? JSONDecoder().decode([DownloadRecord].self, from: data) {
            items = records
            for item in records where item.isActive { taskBytes[item.id] = [:] }
        }
        // Do NOT instantiate a background URLSession during application
        // startup. The former eager connection could terminate the app before
        // any screen appeared on affected devices. The session starts lazily
        // when transfers are requested or iOS delivers background events.
    }

    func attach(_ library: MovieLibrary) { self.library = library }

    func reconnectBackgroundEvents(_ completion: @escaping () -> Void) {
        backgroundEventsCompletion = completion
        _ = session
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    func start(_ request: URLRequest, name: String? = nil, origin: String = "Direct",
               allowParallel: Bool = true) {
        guard let url = request.url, ["http","https"].contains(url.scheme?.lowercased() ?? "") else {
            error = "Only direct HTTP and HTTPS files can use the background downloader."
            return
        }
        do {
            try Self.prepareWorkingDirectory()
        } catch {
            self.error = "Cannot access private download workspace: \(error.localizedDescription)"
            return
        }
        let suggested = name ?? url.lastPathComponent
        let label = suggested.isEmpty ? (url.host ?? "File") : suggested
        let id = UUID()
        var record = DownloadRecord(id: id, name: label, url: url.absoluteString,
                                    status: "Checking server", created: Date(), origin: origin)
        record.runToken = UUID().uuidString
        items.insert(record, at: 0)
        requestByID[id] = request
        persist()
        beginTransfer(id, allowParallel: allowParallel)
    }

    private func beginTransfer(_ id: UUID, allowParallel: Bool = true) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].isActive else { return }
        let request = requestByID[id] ?? URLRequest(url: URL(string: items[i].url)!)
        requestByID[id] = request
        guard allowParallel else { startSingle(id); return }
        let startingToken = items[i].runToken
        var head = request
        head.httpMethod = "HEAD"
        head.setValue(nil, forHTTPHeaderField: "Range")
        let check = URLSession.shared.dataTask(with: head) { [weak self] _, response, _ in
            Task { @MainActor in
                guard let self, let current = self.items.first(where: { $0.id == id }),
                      current.isActive, current.runToken == startingToken else { return }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    self.startSingle(id); return
                }
                let size = http.expectedContentLength
                let acceptsRange = (http.value(forHTTPHeaderField: "Accept-Ranges") ?? "")
                    .lowercased().contains("bytes")
                let mime = (http.mimeType ?? "").lowercased()
                if mime.contains("html") || mime.contains("json") {
                    self.markFailed(id, "The link is a webpage, not a downloadable file.")
                    return
                }
                // Bounded acceleration, not unbounded aggressive requests.
                // For small files, chunking adds overhead and is slower.
                if acceptsRange && size > 32 * 1024 * 1024 {
                    self.startSegments(id, total: size)
                } else {
                    self.startSingle(id)
                }
            }
        }
        check.resume()
    }

    private func startSingle(_ id: UUID) {
        guard let request = requestByID[id], let index = items.firstIndex(where: { $0.id == id }),
              items[index].isActive else { return }
        items[index].status = "Downloading"
        items[index].mode = "Background · single"
        items[index].segmentCount = 1
        taskBytes[id] = [:]
        persist()
        let task = session.downloadTask(with: request)
        task.taskDescription = taskTag(id, part: 0)
        task.resume()
    }

    private func startSegments(_ id: UUID, total: Int64) {
        guard let request = requestByID[id], let index = items.firstIndex(where: { $0.id == id }),
              items[index].isActive else { return }
        let count = 3
        items[index].status = "Downloading"
        items[index].expected = total
        items[index].mode = "Background · 3 connections"
        items[index].segmentCount = count
        taskBytes[id] = [:]
        finishedParts[id] = []
        persist()
        for part in 0..<count {
            let start = Int64(part) * total / Int64(count)
            let end = (Int64(part + 1) * total / Int64(count)) - 1
            var ranged = request
            ranged.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
            // Accept-Encoding identity keeps byte ranges aligned with file offsets.
            ranged.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            let task = session.downloadTask(with: ranged)
            task.taskDescription = taskTag(id, part: part)
            task.resume()
        }
    }

    private func taskTag(_ id: UUID, part: Int) -> String {
        let token = items.first(where: { $0.id == id })?.runToken ?? "legacy"
        return "\(id.uuidString)#\(part)#\(token)"
    }

    private func decode(_ task: URLSessionTask) -> (UUID, Int)? {
        guard let parts = task.taskDescription?.split(separator: "#"),
              (parts.count == 2 || parts.count == 3),
              let id = UUID(uuidString: String(parts[0])),
              let part = Int(parts[1]),
              let entry = items.first(where: { $0.id == id }) else { return nil }
        // Ignore late callbacks from a cancelled or refreshed URL generation.
        if parts.count == 3 {
            guard String(parts[2]) == (entry.runToken ?? "legacy") else { return nil }
        } else if entry.runToken != nil {
            return nil
        }
        return (id, part)
    }
    private func partFile(_ id: UUID, part: Int) -> URL {
        Self.stagingFolder.appendingPathComponent("\(id.uuidString)-\(part).part")
    }
    private func markFailed(_ id: UUID, _ reason: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].status = "Failed: " + reason
        items[i].speed = 0
        persist()
    }

    // Pause is implemented by suspending existing URLSession tasks rather
    // than cancelling them. Their already-received bytes remain with iOS.
    func pause(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }),
              items[i].status == "Downloading" || items[i].status == "Checking server" else { return }
        items[i].status = "Paused"
        items[i].speed = 0
        persist()
        session.getAllTasks { [weak self] tasks in
            DispatchQueue.main.async {
                guard let self else { return }
                for task in tasks where self.decode(task)?.0 == id {
                    task.suspend()
                }
            }
        }
    }

    func resume(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].isPaused else { return }
        session.getAllTasks { [weak self] tasks in
            DispatchQueue.main.async {
                guard let self, let i = self.items.firstIndex(where: { $0.id == id }),
                      self.items[i].isPaused else { return }
                let matching = tasks.filter { self.decode($0)?.0 == id }
                if !matching.isEmpty {
                    self.items[i].status = "Downloading"
                    self.items[i].speed = 0
                    self.samples.removeValue(forKey: id)
                    self.persist()
                    for task in matching { task.resume() }
                } else {
                    // The OS no longer has the suspended task (for example after
                    // termination). It is unsafe to pretend the bytes survived.
                    self.retry(id)
                    self.error = "The previous transfer was no longer available. Download restarted safely."
                }
            }
        }
    }

    // Retry preserves the Movies list ID and download entry. Refresh Link
    // replaces an expired signed URL, cancels older tasks, and starts a new
    // verified transfer. Partial data is reset intentionally to avoid mixing
    // bytes from two different server resources.
    func retry(_ id: UUID, replacementURL: String? = nil) {
        guard let i = items.firstIndex(where: { $0.id == id }),
              items[i].canRetry else { return }
        let original = items[i].url
        let newText = (replacementURL ?? original).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: newText),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else {
            error = "Enter a valid HTTP or HTTPS download URL."
            return
        }

        // Invalidate generation FIRST so cancelled callbacks cannot affect
        // the next transfer, then terminate any previous tasks.
        items[i].runToken = UUID().uuidString
        items[i].url = newText
        items[i].status = "Checking server"
        items[i].received = 0
        items[i].expected = 0
        items[i].speed = 0
        items[i].segmentCount = 1
        items[i].mode = "Reconnecting · validating link"
        taskBytes[id] = [:]
        samples.removeValue(forKey: id)
        finishedParts.removeValue(forKey: id)
        segmentFallbackIDs.remove(id)
        requestByID[id] = URLRequest(url: url)
        persist()

        session.getAllTasks { [weak self] tasks in
            DispatchQueue.main.async {
                guard let self else { return }
                for task in tasks where task.taskDescription?.hasPrefix(id.uuidString + "#") == true {
                    task.cancel()
                }
                for part in 0..<3 { try? FileManager.default.removeItem(at: self.partFile(id, part: part)) }
                try? FileManager.default.removeItem(at:
                    Self.stagingFolder.appendingPathComponent(id.uuidString + ".complete"))
                self.beginTransfer(id)
            }
        }
    }

    func cancel(_ id: UUID) {
        if let i = items.firstIndex(where: { $0.id == id }) {
            items[i].status = "Cancelled"
            items[i].speed = 0
            persist()
        }
        session.getAllTasks { tasks in
            for task in tasks where task.taskDescription?.hasPrefix(id.uuidString + "#") == true {
                task.cancel()
            }
        }
    }
    func delete(_ id: UUID) {
        cancel(id)
        if let url = items.first(where: { $0.id == id })?.savedPath.flatMap(URL.init(fileURLWithPath:)) {
            try? FileManager.default.removeItem(at: url)
        }
        items.removeAll { $0.id == id }
        persist()
    }

    func refresh() {
        session.getAllTasks { [weak self] tasks in
            DispatchQueue.main.async {
                guard let self else { return }
                for task in tasks {
                    guard let (id, part) = self.decode(task),
                          let i = self.items.firstIndex(where: { $0.id == id }),
                          self.items[i].isActive else { continue }
                    let bytes = max(0, task.countOfBytesReceived)
                    self.taskBytes[id, default: [:]][part] = bytes
                }
                self.updateSpeedForActiveItems()
            }
        }
    }

    private func updateSpeedForActiveItems() {
        let now = Date()
        for i in items.indices where items[i].status == "Downloading" {
            let id = items[i].id
            let total = taskBytes[id, default: [:]].values.reduce(Int64(0), +)
            let oldReceived = items[i].received
            items[i].received = max(oldReceived, total)
            if let prev = samples[id], now.timeIntervalSince(prev.0) >= 0.8 {
                let dt = now.timeIntervalSince(prev.0)
                let measured = max(0, Double(items[i].received - prev.1) / dt)
                items[i].speed = items[i].speed == 0 ? measured :
                    0.5 * items[i].speed + 0.5 * measured
                samples[id] = (now, items[i].received)
            } else if samples[id] == nil {
                samples[id] = (now, items[i].received)
            }
        }
        persist()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let (id, part) = decode(downloadTask),
              let i = items.firstIndex(where: { $0.id == id }),
              items[i].status == "Downloading" else { return }
        taskBytes[id, default: [:]][part] = totalBytesWritten
        if items[i].segmentCount == 1, totalBytesExpectedToWrite > 0 {
            items[i].expected = totalBytesExpectedToWrite
        }
        updateSpeedForActiveItems()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let (id, part) = decode(downloadTask),
              let i = items.firstIndex(where: { $0.id == id }),
              items[i].status == "Downloading" else { return }
        let pieces = items[i].segmentCount
        let http = downloadTask.response as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        let mime = (http?.mimeType ?? "").lowercased()
        // Signed URLs may hide extensions in query parameters. Prefer the
        // response's Content-Disposition filename, then the media MIME type.
        if let suggested = http?.suggestedFilename,
           VideoFormats.supported(URL(fileURLWithPath: suggested)),
           !VideoFormats.supported(URL(fileURLWithPath: items[i].name)) {
            items[i].name = suggested
        }
        if !VideoFormats.supported(URL(fileURLWithPath: items[i].name)) {
            let videoExtension: String?
            switch mime {
            case "video/mp4": videoExtension = "mp4"
            case "video/quicktime": videoExtension = "mov"
            case "video/webm": videoExtension = "webm"
            case "video/x-matroska": videoExtension = "mkv"
            case "video/x-msvideo": videoExtension = "avi"
            default: videoExtension = nil
            }
            if let videoExtension {
                items[i].name += "." + videoExtension
            }
        }
        guard !mime.contains("html") && !mime.contains("json"),
              !mime.contains("text/plain") else {
            markFailed(id, "The server delivered a webpage or text, not media.")
            return
        }
        if pieces > 1 {
            let expected = items[i].expected
            let start = Int64(part) * expected / Int64(pieces)
            let end = Int64(part + 1) * expected / Int64(pieces) - 1
            let rangeHeader = http?.value(forHTTPHeaderField: "Content-Range") ?? ""
            let expectedPrefix = "bytes \(start)-\(end)/\(expected)"
            let size = ((try? FileManager.default.attributesOfItem(atPath: location.path)[.size]) as? NSNumber)?.int64Value ?? -1
            guard code == 206, rangeHeader == expectedPrefix, size == end - start + 1 else {
                // Server ignored or mangled byte ranges. One regular download
                // is safer than joining corrupt segments.
                fallbackToSingle(id)
                return
            }
        } else if part != 0 || code != 200 {
            // Ignore late range callbacks from cancelled chunk tasks; never
            // save a partial file as a successful single-file download.
            if part == 0 { markFailed(id, "Server returned HTTP \(code)") }
            return
        }
        do {
            let staged = partFile(id, part: part)
            try Self.safeStage(location, at: staged)
            finishedParts[id, default: []].insert(part)
            if pieces == 1 || finishedParts[id]?.count == pieces {
                items[i].status = "Finalizing"
                items[i].speed = 0
                persist()
                finalize(id, pieces: pieces)
            }
        } catch { markFailed(id, error.localizedDescription) }
    }

    private func fallbackToSingle(_ id: UUID) {
        guard !segmentFallbackIDs.contains(id) else { return }
        segmentFallbackIDs.insert(id)
        session.getAllTasks { tasks in
            for task in tasks where task.taskDescription?.hasPrefix(id.uuidString + "#") == true {
                task.cancel()
            }
        }
        for part in 0..<3 { try? FileManager.default.removeItem(at: partFile(id, part: part)) }
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].received = 0
        items[i].speed = 0
        items[i].segmentCount = 1
        items[i].mode = "Background · fallback"
        items[i].status = "Checking server"
        taskBytes[id] = [:]
        samples.removeValue(forKey: id)
        // Kick off fresh task after cancelled segmented responses are ignored.
        startSingle(id)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let (id, _) = decode(task), let error,
              let i = items.firstIndex(where: { $0.id == id }),
              items[i].isActive else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        markFailed(id, error.localizedDescription)
    }

    private func finalize(_ id: UUID, pieces: Int) {
        let paths = (0..<pieces).map { partFile(id, part: $0) }
        let result = Self.stagingFolder.appendingPathComponent(id.uuidString + ".complete")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            do {
                try Self.prepareWorkingDirectory()
                if FileManager.default.fileExists(atPath: result.path) {
                    try FileManager.default.removeItem(at: result)
                }
                guard FileManager.default.createFile(atPath: result.path, contents: nil) else {
                    throw NSError(domain: "NextCast.TransferStorage", code: 14, userInfo: [
                        NSLocalizedDescriptionKey: "Unable to create assembled download."
                    ])
                }
                let destination = try FileHandle(forWritingTo: result)
                defer { try? destination.close() }
                for part in paths {
                    let source = try FileHandle(forReadingFrom: part)
                    defer { try? source.close() }
                    while true {
                        let block = try source.read(upToCount: 512 * 1024) ?? Data()
                        if block.isEmpty { break }
                        try destination.write(contentsOf: block)
                    }
                }
                Task { @MainActor [weak self] in
                    self?.finishMerged(id, result: result)
                    for part in paths { try? FileManager.default.removeItem(at: part) }
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.markFailed(id, error.localizedDescription)
                }
            }
        }
    }

    private func finishMerged(_ id: UUID, result: URL) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let entry = items[index]
        do {
            // Classify the REAL assembled file by name, video MIME and magic
            // bytes, not the temporary UUID filename. Signed direct links
            // commonly omit the .mp4/.mkv extension altogether.
            if let video = try VideoFileInspector.preparedVideoURL(result, name: entry.name) {
                let targetLibrary = library ?? MovieLibrary()
                try targetLibrary.addDownloadedFile(
                    video,
                    suggestedName: VideoFileInspector.cleanTitle(entry.name)
                )
                items[index].status = "Added to Movies"
                items[index].savedPath = nil
            } else {
                try FileManager.default.createDirectory(
                    at: BrowserDownloadStore.folder,
                    withIntermediateDirectories: true
                )
                let safeName = URL(fileURLWithPath: entry.name).lastPathComponent
                let destination = BrowserDownloadStore.folder.appendingPathComponent(
                    id.uuidString + "-" + (safeName.isEmpty ? "download.bin" : safeName)
                )
                try Self.safeStage(result, at: destination)
                items[index].savedPath = destination.path
                items[index].status = "Saved to Downloads"
            }
            items[index].speed = 0
            if items[index].expected > 0 { items[index].received = items[index].expected }
            persist()
        } catch {
            markFailed(id, "Unable to move download into Movies: \(error.localizedDescription)")
            // Keep assembled file for recovery when transfer finalization fails.
        }
        requestByID.removeValue(forKey: id)
        taskBytes.removeValue(forKey: id)
        samples.removeValue(forKey: id)
        finishedParts.removeValue(forKey: id)
    }

    // Import an already downloaded item into Movies without downloading again.
    func moveToMovies(_ id: UUID, library targetLibrary: MovieLibrary) {
        guard let i = items.firstIndex(where: { $0.id == id }),
              let path = items[i].savedPath,
              FileManager.default.fileExists(atPath: path) else {
            error = "The downloaded file is not available in storage."
            return
        }
        do {
            guard let video = try VideoFileInspector.preparedVideoURL(
                URL(fileURLWithPath: path), name: items[i].name
            ) else {
                error = "The saved file is not recognized as a video."
                return
            }
            try targetLibrary.addDownloadedFile(
                video,
                suggestedName: VideoFileInspector.cleanTitle(items[i].name)
            )
            items[i].savedPath = nil
            items[i].status = "Added to Movies"
            persist()
        } catch {
            error = "Could not add to Movies: \(error.localizedDescription)"
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = backgroundEventsCompletion
        backgroundEventsCompletion = nil
        completion?()
    }
}

/// UIApplication gets a chance to reconnect background URLSession callbacks
/// after iOS has relaunched the process to deliver completed files.
final class NextCastBackgroundDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Background session is constructed only on demand, not at startup.
        return true
    }
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == TransferStore.sessionID else {
            completionHandler()
            return
        }
        Task { @MainActor in
            TransferStore.shared.reconnectBackgroundEvents(completionHandler)
        }
    }
}

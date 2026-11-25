import SwiftUI
import AVKit
import GoogleCast
import UniformTypeIdentifiers
import Combine

// MARK: - App
@main
struct NextCastApp: App {
    @UIApplicationDelegateAdaptor(NextCastBackgroundDelegate.self) private var backgroundDelegate
    @AppStorage("appearance") private var appearance = "system"
    init() {
        let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        GCKCastContext.setSharedInstanceWith(options)
    }
    var body: some Scene {
        WindowGroup {
            NextCastTabs()
                .preferredColorScheme(appearance == "dark" ? .dark : (appearance == "light" ? .light : nil))
        }
    }
}

// MARK: - Movie library and file import
struct Movie: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let fileName: String
    let importedAt: Date
    let fileSize: Int64
    static func == (lhs: Movie, rhs: Movie) -> Bool { lhs.id == rhs.id }

    var localURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent(fileName)
    }
    var isConverted: Bool { fileName.hasPrefix("Converted/") }
    var format: String { localURL.pathExtension.uppercased() }
    var fileSizeLabel: String { ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file) }
    var castCompatible: Bool {
        ["mp4", "m4v", "webm", "mov", "ts", "m2ts"].contains(localURL.pathExtension.lowercased())
    }
    /// Allows an unchanged MKV file to be offered to a Cast receiver as an
    /// experimental direct stream. This does not imply receiver compatibility.
    var canAttemptDirectCast: Bool {
        castCompatible || localURL.pathExtension.lowercased() == "mkv"
    }
    var mimeType: String {
        switch localURL.pathExtension.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "mkv": return "video/x-matroska"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        case "ts", "m2ts": return "video/mp2t"
        default: return "application/octet-stream"
        }
    }
}

enum VideoFormats {
    static let extensions: Set<String> = [
        "mp4","m4v","mov","mkv","avi","flv","wmv","webm",
        "mpg","mpeg","m2v","ts","m2ts","mts","3gp","3g2",
        "vob","ogv","asf","divx","f4v","rm","rmvb"
    ]
    static func supported(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }
}

@MainActor
final class MovieLibrary: ObservableObject {
    @Published private(set) var movies: [Movie] = []
    @Published var errorMessage: String?
    @Published var isImporting = false
    @Published var importStatus = ""
    private let fileQueue = DispatchQueue(label: "uk.zeshanbarvi.nextcast.import", qos: .userInitiated)
    private let deletionQueue = DispatchQueue(label: "uk.zeshanbarvi.nextcast.delete", qos: .utility)
    private var pendingDeletions: [Movie] = []
    private var deletionsInFlight = Set<UUID>()
    private var activeConversionSources = Set<UUID>()
    private var deletionJournal: URL { Self.folder.appendingPathComponent("pending-deletions.json") }

    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Movies", isDirectory: true)
    }
    static var convertedFolder: URL {
        folder.appendingPathComponent("Converted", isDirectory: true)
    }
    static var imports: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Imports", isDirectory: true)
    }
    private var manifest: URL { Self.folder.appendingPathComponent("library.json") }

    init() {
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: Self.imports, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: Self.convertedFolder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: manifest.path) {
                movies = try JSONDecoder().decode([Movie].self, from: Data(contentsOf: manifest))
            }
            if FileManager.default.fileExists(atPath: deletionJournal.path) {
                pendingDeletions = try JSONDecoder().decode([Movie].self, from: Data(contentsOf: deletionJournal))
            }
            let pendingIDs = Set(pendingDeletions.map(\.id))
            movies.removeAll { pendingIDs.contains($0.id) }
            recoverPreparedFiles()
            movies.removeAll { !FileManager.default.fileExists(atPath: $0.localURL.path) }
            movies.sort { $0.importedAt > $1.importedAt }
            try JSONEncoder().encode(movies).write(to: manifest, options: .atomic)
            // No conversion survives process termination. Remove only known
            // unfinished output names that are not registered library items.
            let savedNames = Set(movies.map(\.fileName))
            let fm = FileManager.default
            let cleanupFolder = Self.folder.appendingPathComponent(".Cleanup", isDirectory: true)
            try? fm.createDirectory(at: cleanupFolder, withIntermediateDirectories: true)
            let files = (try? fm.contentsOfDirectory(at: Self.convertedFolder, includingPropertiesForKeys: nil)) ?? []
            for url in files {
                let name = url.lastPathComponent
                guard !savedNames.contains("Converted/" + name),
                      UUID(uuidString: name.components(separatedBy: ".").first ?? "") != nil,
                      name.hasSuffix(".nativebuilding.mp4") || name.hasSuffix(".building.mp4") else { continue }
                // Same-volume rename isolates abandoned files before a new
                // conversion can reuse the original temporary filename.
                try? fm.moveItem(at: url, to: cleanupFolder.appendingPathComponent(UUID().uuidString))
            }
            deletionQueue.async {
                let fm = FileManager.default
                let files = (try? fm.contentsOfDirectory(at: cleanupFolder, includingPropertiesForKeys: nil)) ?? []
                for url in files where UUID(uuidString: url.lastPathComponent) != nil {
                    try? fm.removeItem(at: url)
                }
            }
            let validIDs = Set(movies.map(\.id))
            ArtworkCache.shared.prune(keeping: validIDs)
            PlaybackHistory.prune(keeping: validIDs)
            for movie in pendingDeletions { scheduleDeletion(movie) }
        } catch {
            errorMessage = "Library load failed: \(error.localizedDescription)"
        }
        scanImports()
    }

    /// Recover prepared files from older installations, including files made
    /// by the one-time converter in v1.4.5–1.4.7. No video data is copied.
    private func recoverPreparedFiles() {
        let fm = FileManager.default
        let legacy = (try? fm.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        for url in legacy where url.lastPathComponent.hasSuffix(".native.cast.mp4") {
            let destination = Self.convertedFolder.appendingPathComponent(url.lastPathComponent)
            if !fm.fileExists(atPath: destination.path) {
                try? fm.moveItem(at: url, to: destination)
            }
        }
        let files = (try? fm.contentsOfDirectory(at: Self.convertedFolder,
                                                  includingPropertiesForKeys: nil)) ?? []
        for url in files where url.lastPathComponent.hasSuffix(".native.cast.mp4") {
            let relative = "Converted/" + url.lastPathComponent
            guard !pendingDeletions.contains(where: { $0.fileName == relative }),
                  !movies.contains(where: { $0.fileName == relative }),
                  let size = ((try? fm.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value,
                  size > 4096 else { continue }
            let sourceID = url.lastPathComponent.components(separatedBy: ".").first ?? ""
            let name = movies.first(where: { $0.id.uuidString.caseInsensitiveCompare(sourceID) == .orderedSame })?.name
                ?? "Recovered TV video"
            movies.append(Movie(id: UUID(), name: name + " · TV Ready",
                                fileName: relative, importedAt: Date(), fileSize: size))
        }
    }

    /// Add or update a prepared MP4 as its own movie, never reusing the
    /// original's UUID. The HTTP server keys each stream independently.
    func registerPreparedFile(_ url: URL, source: Movie) -> Movie {
        let relative = "Converted/" + url.lastPathComponent
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size])
                    as? NSNumber)?.int64Value ?? 0
        if let i = movies.firstIndex(where: { $0.fileName == relative }) {
            let current = movies[i]
            let updated = Movie(id: current.id, name: current.name, fileName: relative,
                                importedAt: current.importedAt, fileSize: size)
            movies[i] = updated
            persist()
            return updated
        }
        let item = Movie(id: UUID(), name: source.name + " · TV Ready",
                         fileName: relative, importedAt: Date(), fileSize: size)
        movies.insert(item, at: 0)
        persist()
        return item
    }

    // Never copy a multi-GB file on the main thread. Avoid NSFileCoordinator,
    // which can stall on certain file providers. Start security-scope on worker.
    func importVideos(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isImporting = true
        importStatus = "Importing \(urls.count) file(s)…"
        let queue = fileQueue
        queue.async { [weak self] in
            var imported: [Movie] = []
            var errors: [String] = []
            for url in urls {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    guard VideoFormats.supported(url) else {
                        throw NSError(domain: "NextCast", code: 1, userInfo: [
                            NSLocalizedDescriptionKey: "Not a supported video type: \(url.pathExtension)"
                        ])
                    }
                    let id = UUID()
                    let filename = id.uuidString + "." + url.pathExtension.lowercased()
                    let destination = MovieLibrary.folder.appendingPathComponent(filename)
                    try FileManager.default.copyItem(at: url, to: destination)
                    let size = (try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
                    let movie = Movie(id: id, name: url.deletingPathExtension().lastPathComponent,
                                      fileName: filename, importedAt: Date(), fileSize: size)
                    imported.append(movie)
                    // The explicit Imports inbox is a handoff folder, not a
                    // permanent second copy. Remove only after successful copy.
                    if url.deletingLastPathComponent().standardizedFileURL ==
                        MovieLibrary.imports.standardizedFileURL {
                        try? FileManager.default.removeItem(at: url)
                    }
                    DispatchQueue.main.async { self?.importStatus = "Imported \(imported.count) of \(urls.count)…" }
                } catch {
                    errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.movies.insert(contentsOf: imported, at: 0)
                self.movies.sort { $0.importedAt > $1.importedAt }
                self.persist()
                self.isImporting = false
                self.importStatus = imported.isEmpty ? "No videos imported" : "Added \(imported.count) videos"
                if !errors.isEmpty { self.errorMessage = errors.joined(separator: "\n") }
            }
        }
    }

    func addDownloadedFile(_ url: URL, suggestedName: String? = nil) throws {
        guard VideoFormats.supported(url) else {
            throw NSError(domain: "NextCast", code: 2, userInfo: [NSLocalizedDescriptionKey:"Unsupported video format."])
        }
        let id = UUID()
        let stored = id.uuidString + "." + url.pathExtension.lowercased()
        let dest = Self.folder.appendingPathComponent(stored)
        try FileManager.default.moveItem(at: url, to: dest)
        let size = (try FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.int64Value ?? 0
        let title = (suggestedName ?? url.deletingPathExtension().lastPathComponent)
            .replacingOccurrences(of: "_", with: " ")
        movies.insert(Movie(id: id, name: title, fileName: stored,
                            importedAt: Date(), fileSize: size), at: 0)
        persist()
    }

    func scanImports() {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: Self.imports,
                                              includingPropertiesForKeys: nil),
              !urls.isEmpty else { return }
        importVideos(urls.filter { VideoFormats.supported($0) })
    }

    func beginConversion(_ movie: Movie) -> Bool {
        let prefix = "Converted/" + movie.id.uuidString + "."
        guard movies.contains(movie), !activeConversionSources.contains(movie.id),
              !pendingDeletions.contains(where: { $0.id == movie.id || $0.fileName.hasPrefix(prefix) }) else { return false }
        activeConversionSources.insert(movie.id)
        return true
    }

    func endConversion(_ id: UUID) {
        activeConversionSources.remove(id)
    }

    func delete(_ movie: Movie) {
        guard movies.contains(movie) else { return }
        let sourceID = UUID(uuidString: movie.localURL.lastPathComponent.components(separatedBy: ".").first ?? "")
        guard !activeConversionSources.contains(movie.id),
              sourceID.map({ !activeConversionSources.contains($0) }) ?? true else {
            errorMessage = "Wait for the conversion to finish or cancel it before deleting this video."
            return
        }
        // Journal first: a crash or forced quit cannot resurrect a deleted
        // converted movie through the legacy recovery scan.
        pendingDeletions.append(movie)
        do {
            try JSONEncoder().encode(pendingDeletions).write(to: deletionJournal, options: .atomic)
        } catch {
            pendingDeletions.removeAll { $0.id == movie.id }
            errorMessage = "Cannot queue deletion: \(error.localizedDescription)"
            return
        }
        movies.removeAll { $0.id == movie.id }
        persist()
        ArtworkCache.shared.remove(movie.id)
        PlaybackHistory.clear(movie.id)
        scheduleDeletion(movie)
    }

    private func scheduleDeletion(_ movie: Movie) {
        guard deletionsInFlight.insert(movie.id).inserted else { return }
        let url = movie.localURL
        let convertedFolder = Self.convertedFolder
        let savedNames = Set(movies.map(\.fileName))
        let sourcePrefix = movie.id.uuidString + "."
        let isConverted = movie.isConverted
        let sharedFile = savedNames.contains(movie.fileName)
        deletionQueue.async { [weak self] in
            let fm = FileManager.default
            var failures: [String] = []
            func removeIfPresent(_ item: URL) {
                do { try fm.removeItem(at: item) }
                catch {
                    if (error as NSError).code != NSFileNoSuchFileError &&
                        (error as NSError).code != NSFileReadNoSuchFileError {
                        failures.append(error.localizedDescription)
                    }
                }
            }
            if !sharedFile { removeIfPresent(url) }
            if !isConverted {
                let files = (try? fm.contentsOfDirectory(at: convertedFolder, includingPropertiesForKeys: nil)) ?? []
                for item in files {
                    let name = item.lastPathComponent
                    guard name.hasPrefix(sourcePrefix),
                          !savedNames.contains("Converted/" + name),
                          name.hasSuffix(".nativebuilding.mp4") || name.hasSuffix(".building.mp4") else { continue }
                    removeIfPresent(item)
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.deletionsInFlight.remove(movie.id)
                guard failures.isEmpty else {
                    self.errorMessage = "Video removed from library, but storage cleanup will retry on next launch: " + failures.joined(separator: "; ")
                    return
                }
                // Keep the journal until the manifest is durably saved.
                guard self.persist() else { return }
                let remaining = self.pendingDeletions.filter { $0.id != movie.id }
                do {
                    try JSONEncoder().encode(remaining).write(to: self.deletionJournal, options: .atomic)
                    self.pendingDeletions = remaining
                } catch {
                    self.errorMessage = "Deletion cleanup journal will retry on next launch."
                }
            }
        }
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try JSONEncoder().encode(movies).write(to: manifest, options: .atomic)
            return true
        } catch {
            errorMessage = "Cannot save library: \(error.localizedDescription)"
            return false
        }
    }
}

// MARK: - Google Cast
@MainActor
final class CastController: NSObject, ObservableObject, GCKSessionManagerListener, GCKRemoteMediaClientListener, GCKRequestDelegate {
    @Published private(set) var isConnected = false
    @Published private(set) var tvName = "No TV connected"
    @Published private(set) var tvModelName = ""
    @Published private(set) var tvIPAddress = ""
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var remoteVolume: Double = 0.5
    @Published private(set) var remoteMuted = false
    @Published var errorMessage: String?
    @Published private(set) var castStatus = "No TV media playing"
    @Published private(set) var nowCastingMovie: Movie?
    @Published private(set) var pendingCastMovie: Movie?
    @Published private(set) var nowCastingWebTitle: String?
    @Published private(set) var pendingWebTitle: String?
    @Published private(set) var didReceiveMediaGET = false
    var selectedMovie: Movie?
    private var streamAttempt = 0
    private var activeLoadRequest: GCKRequest?
    private var expectedMediaURL: URL?
    private var expectedStreamID: UUID?

    private let server = LocalMediaServer()
    private let lockStreamKeeper = TVLockStreamKeeper()
    private var localStreamLoaded = false
    private var hasStartedTVPlayback = false

    func sceneDidChange(_ phase: ScenePhase) {
        if phase == .active { lockStreamKeeper.becameActive() }
        else if localStreamLoaded { lockStreamKeeper.willLeaveForeground() }
    }
    private var activeClient: GCKRemoteMediaClient?
    private var lastLoadedMovieID: UUID?

    private var manager: GCKSessionManager { GCKCastContext.sharedInstance().sessionManager }
    private var client: GCKRemoteMediaClient? { manager.currentCastSession?.remoteMediaClient }

    override init() {
        super.init()
        manager.add(self)
        server.onMediaRequest = { [weak self] streamID in
            Task { @MainActor [weak self] in
                guard let self, self.pendingCastMovie != nil,
                      self.expectedStreamID == streamID else { return }
                self.didReceiveMediaGET = true
                if self.pendingCastMovie?.format == "MKV" {
                    self.castStatus = "TV requested original MKV bytes · checking playback…"
                    NextCastPlaybackLog.shared.append("cast-mkv-http-get",
                        "stream=\(streamID.uuidString) mode=original")
                } else {
                    self.castStatus = "TV requested movie bytes · starting playback…"
                }
            }
        }
        attachIfConnected()
    }

    deinit {
        // This listener is weakly held by the SDK; CastController normally lives
        // as long as the scene, and SDK teardown does not require explicit removal.
    }

    func select(_ movie: Movie) {
        selectedMovie = movie
        // Selection alone never starts casting; local playback is the default.
    }

    func load(_ movie: Movie) {
        selectedMovie = movie
        guard isConnected else {
            castStatus = "Connect a Chromecast receiver first."
            errorMessage = castStatus
            return
        }
        guard movie.canAttemptDirectCast else {
            errorMessage = "This container cannot be sent directly to the selected Cast receiver. Use TV-compatible MP4 preparation instead."
            return
        }
        streamAttempt += 1
        let attempt = streamAttempt
        didReceiveMediaGET = false
        pendingCastMovie = movie
        pendingWebTitle = nil
        nowCastingWebTitle = nil
        nowCastingMovie = nil
        activeLoadRequest = nil
        expectedMediaURL = nil
        expectedStreamID = nil
        let isOriginalMKV = movie.format == "MKV"
        castStatus = isOriginalMKV
            ? "Preparing original MKV stream · no conversion…"
            : "Preparing local video stream…"
        if isOriginalMKV {
            NextCastPlaybackLog.shared.append("cast-mkv-direct",
                "mode=original mime=\(movie.mimeType) bytes=\(movie.fileSize) receiver=\(tvModelName)")
        }
        server.makeURL(for: movie) { [weak self] result in
            guard let self, self.streamAttempt == attempt else { return }
            switch result {
            case .failure(let error):
                self.castStatus = "Cannot serve movie: \(error.localizedDescription)"
                self.errorMessage = self.castStatus
                self.pendingCastMovie = nil
            case .success(let mediaURL):
                guard let client = self.client, self.isConnected,
                      self.selectedMovie?.id == movie.id else {
                    self.pendingCastMovie = nil
                    self.castStatus = "Cast connection changed. Reconnect and try again."
                    return
                }
                let builder = GCKMediaInformationBuilder(contentURL: mediaURL)
                builder.streamType = .buffered
                builder.contentType = movie.mimeType
                let info = builder.build()
                self.lastLoadedMovieID = movie.id
                self.localStreamLoaded = true
                self.hasStartedTVPlayback = false
                self.lockStreamKeeper.setCasting(true)
                self.castStatus = isOriginalMKV
                    ? "Sending original MKV to \(self.tvName) · no conversion…"
                    : "Sending video URL to \(self.tvName)…"
                self.expectedMediaURL = mediaURL
                self.expectedStreamID = UUID(uuidString: mediaURL.lastPathComponent)
                let request = client.loadMedia(info)
                self.activeLoadRequest = request
                request.delegate = self
                UIApplication.shared.isIdleTimerDisabled = true
                // A connected Cast device is not proof of media playback.
                // Surface a failed delivery rather than silently switching UI.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    guard let self, self.streamAttempt == attempt,
                          self.pendingCastMovie != nil else { return }
                    if isOriginalMKV {
                        self.castStatus = self.didReceiveMediaGET
                            ? "TV received the original MKV but did not start playback. This receiver may not support Matroska or one of its codecs."
                            : "TV did not request the original MKV. Check Wi-Fi/client isolation."
                    } else {
                        self.castStatus = self.didReceiveMediaGET
                            ? "TV received video but did not start playback. Check TV media session."
                            : "TV did not request the video from the iPhone. Check Wi-Fi/client isolation."
                    }
                    self.errorMessage = self.castStatus
                    self.pendingCastMovie = nil
                }
            }
        }
    }


    /// Cast a remote website's direct media URL without requiring iPhone decoding.
    /// The TV requests the media itself; DRM, cookies, referer-protected streams
    /// and receiver-unsupported formats can still fail.
    func loadWebStream(_ mediaURL: URL, contentType: String, title: String) {
        guard isConnected, let client else {
            castStatus = "Connect a Chromecast or Google Cast TV first."
            errorMessage = castStatus
            return
        }
        guard mediaURL.scheme?.lowercased() == "https" ||
              mediaURL.scheme?.lowercased() == "http" else {
            errorMessage = "Only direct HTTP/HTTPS streams can be sent to the TV."
            return
        }
        guard ["video/mp4", "video/webm", "application/x-mpegurl",
               "application/vnd.apple.mpegurl", "application/dash+xml",
               "video/mp2t", "video/quicktime"].contains(contentType.lowercased()) else {
            errorMessage = "Unsupported or unknown video format for Google Cast: \(contentType)."
            return
        }
        streamAttempt += 1
        let attempt = streamAttempt
        pendingCastMovie = nil
        nowCastingMovie = nil
        pendingWebTitle = String(title.prefix(100))
        nowCastingWebTitle = nil
        expectedStreamID = nil
        didReceiveMediaGET = false
        activeLoadRequest = nil
        localStreamLoaded = false
        hasStartedTVPlayback = false
        lockStreamKeeper.stop()
        server.stop()
        let builder = GCKMediaInformationBuilder(contentURL: mediaURL)
        builder.streamType = .buffered
        builder.contentType = contentType
        expectedMediaURL = mediaURL
        castStatus = "Sending website video to \(tvName)…"
        NextCastPlaybackLog.shared.append("cast-web-request",
            "host=\(mediaURL.host ?? "-") format=\(contentType)")
        let request = client.loadMedia(builder.build())
        activeLoadRequest = request
        request.delegate = self
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            guard let self, self.streamAttempt == attempt,
                  self.pendingWebTitle != nil else { return }
            self.castStatus = "TV has not confirmed video playback. Stream may require login, a different format, or CORS."
            self.errorMessage = self.castStatus
            self.pendingWebTitle = nil
            self.activeLoadRequest = nil
            NextCastPlaybackLog.shared.append("cast-web-timeout",
                "host=\(mediaURL.host ?? "-")")
        }
    }

    func requestDidComplete(_ request: GCKRequest) {
        guard activeLoadRequest === request,
              (pendingCastMovie != nil || pendingWebTitle != nil) else { return }
        castStatus = "TV acknowledged media request · checking playback…"
    }

    func request(_ request: GCKRequest, didFailWithError error: GCKError) {
        guard activeLoadRequest === request else { return }
        if pendingCastMovie?.format == "MKV" {
            castStatus = "This Cast receiver rejected the original MKV stream. Try TV-compatible MP4 preparation for this receiver."
        } else {
            castStatus = "Chromecast rejected the video: " + error.localizedDescription
        }
        errorMessage = castStatus
        NextCastPlaybackLog.shared.append("cast-load-failed", "code=\(error.code)")
        pendingWebTitle = nil
        pendingCastMovie = nil
        activeLoadRequest = nil
        expectedMediaURL = nil
    }

    func togglePlay() {
        guard let client else { return }
        if isPlaying { _ = client.pause() }
        else { _ = client.play() }
    }

    func seek(to seconds: TimeInterval) {
        guard let client else { return }
        let options = GCKMediaSeekOptions()
        options.interval = max(0, min(seconds, duration > 0 ? duration : seconds))
        options.relative = false
        _ = client.seek(with: options)
        position = options.interval
    }
    func skip(_ seconds: TimeInterval) { seek(to: position + seconds) }
    func changeVolume(_ value: Double) {
        let next = max(0, min(1, value))
        remoteVolume = next
        _ = client?.setStreamVolume(Float(next))
    }

    func toggleRemoteMute() {
        remoteMuted.toggle()
        _ = client?.setStreamMuted(remoteMuted)
    }

    func stopRemotePlayback() {
        _ = client?.stop()
        localStreamLoaded = false
        hasStartedTVPlayback = false
        streamAttempt += 1
        pendingCastMovie = nil
        nowCastingMovie = nil
        pendingWebTitle = nil
        nowCastingWebTitle = nil
        activeLoadRequest = nil
        expectedMediaURL = nil
        expectedStreamID = nil
        didReceiveMediaGET = false
        castStatus = "TV playback stopped"
        lockStreamKeeper.stop()
        server.stop()
        lastLoadedMovieID = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func attachIfConnected() {
        guard manager.hasConnectedCastSession() else { return }
        isConnected = true
        tvName = manager.currentCastSession?.device.friendlyName ?? "Chromecast TV"
        tvModelName = manager.currentCastSession?.device.modelName ?? ""
        tvIPAddress = manager.currentCastSession?.device.ipAddress ?? ""
        if activeClient !== client {
            if let activeClient { activeClient.remove(self) }
            activeClient = client
            activeClient?.add(self)
        }
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKSession) {
        attachIfConnected()
        // Connection is not consent to play: the user explicitly presses Play on TV.
    }
    func sessionManager(_ sessionManager: GCKSessionManager, didResume session: GCKSession) {
        attachIfConnected()
    }
    func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
        activeClient?.remove(self)
        activeClient = nil
        isConnected = false
        isPlaying = false
        position = 0
        tvName = "No TV connected"
        UIApplication.shared.isIdleTimerDisabled = false
        server.stop()
        lastLoadedMovieID = nil
        localStreamLoaded = false
        streamAttempt += 1
        pendingCastMovie = nil
        nowCastingMovie = nil
        pendingWebTitle = nil
        nowCastingWebTitle = nil
        didReceiveMediaGET = false
        castStatus = "Chromecast disconnected"
        lockStreamKeeper.stop()
        if let error { errorMessage = error.localizedDescription }
    }
    func sessionManager(_ sessionManager: GCKSessionManager, didFailToStart session: GCKSession, withError error: Error) {
        errorMessage = error.localizedDescription
    }
    func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?) {
        let receivedDuration = mediaStatus?.mediaInformation?.streamDuration ?? 0
        duration = receivedDuration.isFinite ? max(0, receivedDuration) : 0
        position = max(0, client.approximateStreamPosition())
        if (pendingCastMovie != nil || pendingWebTitle != nil), let expectedMediaURL,
           let receiverURL = mediaStatus?.mediaInformation?.contentURL,
           receiverURL != expectedMediaURL {
            // Stale status from a previous Cast item must not mark the new
            // movie as playing before the receiver loads its unique URL.
            return
        }
        isPlaying = mediaStatus?.playerState == .playing
        switch mediaStatus?.playerState {
        case .playing, .paused:
            if let movie = pendingCastMovie {
                nowCastingMovie = movie
                pendingCastMovie = nil
                activeLoadRequest = nil
            }
            if let webTitle = pendingWebTitle {
                nowCastingWebTitle = webTitle
                pendingWebTitle = nil
                activeLoadRequest = nil
                NextCastPlaybackLog.shared.append("cast-web-playback",
                    "state=\(isPlaying ? "playing" : "paused")")
            }
            if nowCastingMovie != nil || nowCastingWebTitle != nil {
                hasStartedTVPlayback = true
                castStatus = isPlaying ? "Playing on \(tvName)" : "Paused on \(tvName)"
            }
        case .buffering:
            if pendingCastMovie != nil || pendingWebTitle != nil {
                castStatus = "TV buffering video…"
            } else if nowCastingMovie != nil || nowCastingWebTitle != nil {
                castStatus = "TV buffering…"
            }
        case .idle:
            // The default Cast receiver can send a transient idle status during
            // a new LOAD. Never tear down the HTTP listener on that update.
            if nowCastingMovie != nil || nowCastingWebTitle != nil {
                castStatus = "Receiver idle · resume or stop"
            }
        default:
            break
        }
    }

    func refreshProgress() {
        guard isConnected, let client else { return }
        let time = client.approximateStreamPosition()
        if time.isFinite { position = max(0, time) }
    }
}

// MARK: - Cast button
struct CastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> GCKUICastButton {
        let button = GCKUICastButton(frame: .init(x: 0, y: 0, width: 44, height: 44))
        button.tintColor = UIColor.white
        return button
    }
    func updateUIView(_ uiView: GCKUICastButton, context: Context) {}
}


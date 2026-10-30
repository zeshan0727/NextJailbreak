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
    var mimeType: String {
        switch localURL.pathExtension.lowercased() {
        case "mp4", "m4v": return "video/mp4"
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
            recoverPreparedFiles()
            movies.removeAll { !FileManager.default.fileExists(atPath: $0.localURL.path) }
            movies.sort { $0.importedAt > $1.importedAt }
            try? JSONEncoder().encode(movies).write(to: manifest, options: .atomic)
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
        for url in files where url.pathExtension.lowercased() == "mp4" {
            let relative = "Converted/" + url.lastPathComponent
            guard !movies.contains(where: { $0.fileName == relative }),
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

    func delete(_ movie: Movie) {
        do {
            try FileManager.default.removeItem(at: movie.localURL)
            movies.removeAll { $0.id == movie.id }
            persist()
        } catch { errorMessage = error.localizedDescription }
    }

    private func persist() {
        do { try JSONEncoder().encode(movies).write(to: manifest, options: .atomic) }
        catch { errorMessage = "Cannot save library: \(error.localizedDescription)" }
    }
}

// MARK: - Google Cast
@MainActor
final class CastController: NSObject, ObservableObject, GCKSessionManagerListener, GCKRemoteMediaClientListener {
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
    @Published private(set) var didReceiveMediaGET = false
    var selectedMovie: Movie?
    private var streamAttempt = 0

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
        server.onMediaRequest = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.pendingCastMovie != nil else { return }
                self.didReceiveMediaGET = true
                self.castStatus = "TV requested movie bytes · starting playback…"
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
        guard movie.castCompatible else {
            errorMessage = "The TV cannot directly decode this container. Play it on iPhone, or use MP4 (H.264/AAC) for Chromecast. MKV playback on iPhone is supported."
            return
        }
        streamAttempt += 1
        let attempt = streamAttempt
        didReceiveMediaGET = false
        pendingCastMovie = movie
        nowCastingMovie = nil
        castStatus = "Preparing local video stream…"
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
                self.castStatus = "Sending video URL to \(self.tvName)…"
                _ = client.loadMedia(info)
                UIApplication.shared.isIdleTimerDisabled = true
                // A connected Cast device is not proof of media playback.
                // Surface a failed delivery rather than silently switching UI.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    guard let self, self.streamAttempt == attempt,
                          self.pendingCastMovie != nil else { return }
                    self.castStatus = self.didReceiveMediaGET
                        ? "TV received video but did not start playback. Check TV media session."
                        : "TV did not request the video from the iPhone. Check Wi-Fi/client isolation."
                    self.errorMessage = self.castStatus
                    self.pendingCastMovie = nil
                }
            }
        }
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
        isPlaying = mediaStatus?.playerState == .playing
        switch mediaStatus?.playerState {
        case .playing, .paused:
            if let movie = pendingCastMovie {
                nowCastingMovie = movie
                pendingCastMovie = nil
            }
            if nowCastingMovie != nil {
                hasStartedTVPlayback = true
                castStatus = isPlaying ? "Playing on \(tvName)" : "Paused on \(tvName)"
            }
        case .buffering:
            if pendingCastMovie != nil { castStatus = "TV buffering video…" }
            else if nowCastingMovie != nil { castStatus = "TV buffering…" }
        case .idle:
            // The default Cast receiver can send a transient idle status during
            // a new LOAD. Never tear down the HTTP listener on that update.
            if nowCastingMovie != nil { castStatus = "Receiver idle · resume or stop" }
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


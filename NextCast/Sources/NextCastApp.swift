import SwiftUI
import AVKit
import GoogleCast
import UniformTypeIdentifiers
import Combine

// MARK: - App
@main
struct NextCastApp: App {
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
    static var imports: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Imports", isDirectory: true)
    }
    private var manifest: URL { Self.folder.appendingPathComponent("library.json") }

    init() {
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: Self.imports, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: manifest.path) {
                movies = try JSONDecoder().decode([Movie].self, from: Data(contentsOf: manifest))
            }
            movies.removeAll { !FileManager.default.fileExists(atPath: $0.localURL.path) }
            movies.sort { $0.importedAt > $1.importedAt }
        } catch {
            errorMessage = "Library load failed: \(error.localizedDescription)"
        }
        scanImports()
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
        // Scanned files are already inside app Documents, so access is unrestricted.
        importVideos(urls.filter { VideoFormats.supported($0) })
        // Avoid scanning same files repeatedly after a successful copy:
        fileQueue.async {
            for url in urls where VideoFormats.supported(url) {
                // Original remains available in Imports for manual recovery.
                // Users may delete it via Files after confirming import.
                _ = url
            }
        }
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
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published var errorMessage: String?
    var selectedMovie: Movie?

    private let server = LocalMediaServer()
    private var activeClient: GCKRemoteMediaClient?
    private var lastLoadedMovieID: UUID?

    private var manager: GCKSessionManager { GCKCastContext.sharedInstance().sessionManager }
    private var client: GCKRemoteMediaClient? { manager.currentCastSession?.remoteMediaClient }

    override init() {
        super.init()
        manager.add(self)
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
        guard isConnected else { return }
        guard movie.castCompatible else {
            errorMessage = "The TV cannot directly decode this container. Play it on iPhone, or use MP4 (H.264/AAC) for Chromecast. MKV playback on iPhone is supported."
            return
        }
        server.makeURL(for: movie) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.errorMessage = "Local Wi-Fi server: \(error.localizedDescription)"
            case .success(let mediaURL):
                guard let client = self.client, self.isConnected, self.selectedMovie?.id == movie.id else { return }
                let builder = GCKMediaInformationBuilder(contentURL: mediaURL)
                builder.streamType = .buffered
                builder.contentType = movie.mimeType
                let info = builder.build()
                self.lastLoadedMovieID = movie.id
                _ = client.loadMedia(info)
                UIApplication.shared.isIdleTimerDisabled = true
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
    func changeVolume(_ value: Double) { _ = client?.setStreamVolume(Float(value)) }

    private func attachIfConnected() {
        guard manager.hasConnectedCastSession() else { return }
        isConnected = true
        tvName = manager.currentCastSession?.device.friendlyName ?? "Chromecast TV"
        if activeClient !== client {
            if let activeClient { activeClient.remove(self) }
            activeClient = client
            activeClient?.add(self)
        }
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKSession) {
        attachIfConnected()
        if let movie = selectedMovie { load(movie) }
    }
    func sessionManager(_ sessionManager: GCKSessionManager, didResume session: GCKSession) {
        attachIfConnected()
        if let movie = selectedMovie, lastLoadedMovieID != movie.id { load(movie) }
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


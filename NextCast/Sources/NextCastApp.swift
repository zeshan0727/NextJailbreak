import SwiftUI
import AVKit
import GoogleCast
import UniformTypeIdentifiers
import Combine

// MARK: - Bootstrap
@main
struct NextCastApp: App {
    init() {
        let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        GCKCastContext.setSharedInstanceWith(options)
    }

    var body: some Scene {
        WindowGroup {
            LibraryScreen()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Persisted imported videos
struct Movie: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var fileName: String
    var importedAt: Date
    var fileSize: Int64

    static func == (lhs: Movie, rhs: Movie) -> Bool { lhs.id == rhs.id }

    var localURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    var format: String { localURL.pathExtension.uppercased() }
    var fileSizeLabel: String { ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file) }
    var castCompatible: Bool { ["mp4", "m4v", "mov", "webm"].contains(localURL.pathExtension.lowercased()) }

    var mimeType: String {
        switch localURL.pathExtension.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        default: return "application/octet-stream"
        }
    }
}

@MainActor
final class MovieLibrary: ObservableObject {
    @Published private(set) var movies: [Movie] = []
    @Published var errorMessage: String?

    private var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Movies", isDirectory: true)
    }
    private var manifest: URL { folder.appendingPathComponent("library.json") }

    init() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: manifest.path) {
                movies = try JSONDecoder().decode([Movie].self, from: Data(contentsOf: manifest))
            }
            movies.removeAll { !FileManager.default.fileExists(atPath: $0.localURL.path) }
            movies.sort { $0.importedAt > $1.importedAt }
        } catch {
            errorMessage = "Unable to read your library: \(error.localizedDescription)"
        }
    }

    func importVideos(_ urls: [URL]) {
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let ext = url.pathExtension.lowercased()
                guard ["mp4", "mov", "m4v", "webm", "mkv", "avi"].contains(ext) else {
                    throw NSError(domain: "NextCast", code: 1, userInfo: [NSLocalizedDescriptionKey:
                        "Unsupported file extension: .\(ext). Import MP4, MOV, M4V, WEBM, MKV or AVI."])
                }
                let id = UUID()
                let storedName = id.uuidString + "." + ext
                let destination = folder.appendingPathComponent(storedName)
                try FileManager.default.copyItem(at: url, to: destination)
                let attrs = try FileManager.default.attributesOfItem(atPath: destination.path)
                let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                let originalTitle = url.deletingPathExtension().lastPathComponent
                let movie = Movie(id: id, name: originalTitle, fileName: storedName,
                                  importedAt: Date(), fileSize: size)
                movies.insert(movie, at: 0)
                save()
            } catch {
                errorMessage = "Could not import \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    func delete(_ movie: Movie) {
        do {
            try FileManager.default.removeItem(at: movie.localURL)
            movies.removeAll { $0.id == movie.id }
            save()
        } catch { errorMessage = error.localizedDescription }
    }

    private func save() {
        do { try JSONEncoder().encode(movies).write(to: manifest, options: .atomic) }
        catch { errorMessage = "Library could not be saved: \(error.localizedDescription)" }
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
        if isConnected && lastLoadedMovieID != movie.id { load(movie) }
    }

    func load(_ movie: Movie) {
        selectedMovie = movie
        guard isConnected else { return }
        guard movie.castCompatible else {
            errorMessage = "This file format is not supported for direct casting. For reliable playback use an MP4 encoded with H.264 and AAC."
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

// MARK: - Local playback
@MainActor
final class LocalPlayer: ObservableObject {
    let player: AVPlayer
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isPlaying = false
    private var observer: Any?

    init(url: URL) {
        player = AVPlayer(url: url)
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
                                                  queue: .main) { [weak self] _ in
            guard let self else { return }
            let position = self.player.currentTime().seconds
            let length = self.player.currentItem?.duration.seconds ?? 0
            self.currentTime = position.isFinite ? position : 0
            self.duration = length.isFinite ? max(length, 0) : 0
            self.isPlaying = self.player.timeControlStatus == .playing
        }
    }
    func toggle() {
        if player.timeControlStatus == .playing { player.pause() }
        else { player.play() }
        isPlaying = player.timeControlStatus == .playing
    }
    func pause() { player.pause(); isPlaying = false }
    func seek(to value: TimeInterval) {
        player.seek(to: CMTime(seconds: max(0, value), preferredTimescale: 600))
    }
    deinit {
        if let observer { player.removeTimeObserver(observer) }
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

// MARK: - Library screen
struct LibraryScreen: View {
    @StateObject private var library = MovieLibrary()
    @StateObject private var cast = CastController()
    @State private var importing = false
    @State private var searchText = ""
    @State private var selected: Movie?

    private var visible: [Movie] {
        searchText.isEmpty ? library.movies :
          library.movies.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.045, green: 0.075, blue: 0.15),
                                        Color(red: 0.07, green: 0.08, blue: 0.12)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        intro
                        connectionCard
                        if library.movies.isEmpty { emptyState }
                        else {
                            HStack {
                                Text("My Videos").font(.title3.bold())
                                Spacer()
                                Text("\(library.movies.count) FILES")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(visible) { movie in
                                Button {
                                    cast.select(movie)
                                    selected = movie
                                } label: { movieRow(movie) }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) { library.delete(movie) } label: {
                                            Label("Delete from library", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Next Cast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CastButton().frame(width: 44, height: 44)
                        .accessibilityLabel("Choose Chromecast TV")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { importing = true } label: {
                        Image(systemName: "plus").font(.headline)
                            .frame(width: 40, height: 40)
                    }
                    .accessibilityLabel("Import video files")
                }
            }
            .searchable(text: $searchText, prompt: "Search your videos")
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.movie, .video, .item],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): library.importVideos(urls)
                case .failure(let error): library.errorMessage = error.localizedDescription
                }
            }
            .sheet(item: $selected) { movie in
                PlayerScreen(movie: movie, cast: cast)
            }
            .alert("Next Cast", isPresented: Binding(
                get: { library.errorMessage != nil || cast.errorMessage != nil },
                set: { if !$0 { library.errorMessage = nil; cast.errorMessage = nil } }
            )) {
                Button("OK") { library.errorMessage = nil; cast.errorMessage = nil }
            } message: {
                Text(library.errorMessage ?? cast.errorMessage ?? "")
            }
        }
        .tint(.cyan)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR MOVIES. YOUR TV.")
                .font(.caption.bold()).tracking(2.5).foregroundStyle(.cyan)
            Text("Watch anywhere.\nCast everywhere.")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Keep videos on your iPhone. Stream directly to a TV on the same Wi-Fi.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.6))
        }
        .padding(.vertical, 8)
    }
    private var connectionCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "tv.and.hifispeaker.fill")
                .font(.title2).foregroundStyle(.cyan)
                .frame(width: 50, height: 50)
                .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(cast.isConnected ? "Connected to TV" : "Ready to cast")
                    .font(.subheadline.bold())
                Text(cast.isConnected ? cast.tvName : "Tap the Cast icon to find devices")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(cast.isConnected ? Color.green : Color.gray)
                .frame(width: 9, height: 9)
        }
        .padding(16)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 20))
    }
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundStyle(.cyan)
            Text("Your library starts here").font(.title3.bold())
            Text("Import movies from the Files app. Nothing is uploaded to the cloud.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { importing = true } label: {
                Label("Import Videos", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .frame(maxWidth: .infinity).padding(15)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .foregroundStyle(.black)
        }
        .padding(26)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24))
    }
    private func movieRow(_ movie: Movie) -> some View {
        HStack(spacing: 15) {
            Image(systemName: "film.stack.fill")
                .font(.title2).foregroundStyle(.cyan)
                .frame(width: 64, height: 64)
                .background(.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 6) {
                Text(movie.name)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                    .foregroundStyle(.white)
                Text("\(movie.format)  •  \(movie.fileSizeLabel)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            Image(systemName: "play.circle.fill")
                .font(.system(size: 30)).foregroundStyle(.cyan)
        }
        .padding(10)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Player screen with 15s seeking
struct PlayerScreen: View {
    let movie: Movie
    @ObservedObject var cast: CastController
    @StateObject private var local: LocalPlayer
    @State private var dragging = false
    @State private var sliderValue = 0.0
    @Environment(\.dismiss) private var dismiss
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    init(movie: Movie, cast: CastController) {
        self.movie = movie
        self.cast = cast
        _local = StateObject(wrappedValue: LocalPlayer(url: movie.localURL))
    }

    private var currentTime: TimeInterval { cast.isConnected ? cast.position : local.currentTime }
    private var duration: TimeInterval { cast.isConnected ? cast.duration : local.duration }
    private var playing: Bool { cast.isConnected ? cast.isPlaying : local.isPlaying }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.065, blue: 0.12).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 23) {
                        if cast.isConnected {
                            VStack(spacing: 15) {
                                Image(systemName: "tv.fill")
                                    .font(.system(size: 64))
                                    .foregroundStyle(.cyan)
                                Text("Playing on \(cast.tvName)")
                                    .font(.headline)
                                Text("Keep this app open and your iPhone awake during local-file casting.")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 230)
                        } else {
                            VideoPlayer(player: local.player)
                                .frame(height: 240)
                                .background(.black, in: RoundedRectangle(cornerRadius: 16))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(movie.name).font(.title2.bold())
                            Text("\(movie.format)  •  \(movie.fileSizeLabel)")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        VStack(spacing: 12) {
                            Slider(value: $sliderValue, in: 0...max(duration, 1), onEditingChanged: { editing in
                                dragging = editing
                                if !editing {
                                    if cast.isConnected { cast.seek(to: sliderValue) }
                                    else { local.seek(to: sliderValue) }
                                }
                            })
                            HStack {
                                Text(formatTime(dragging ? sliderValue : currentTime))
                                Spacer()
                                Text(formatTime(duration))
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 35) {
                            Spacer()
                            Button { skip(-15) } label: {
                                Image(systemName: "gobackward.15").font(.system(size: 35))
                            }
                            Button {
                                if cast.isConnected { cast.togglePlay() } else { local.toggle() }
                            } label: {
                                Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 66))
                                    .foregroundStyle(.cyan)
                            }
                            Button { skip(15) } label: {
                                Image(systemName: "goforward.15").font(.system(size: 35))
                            }
                            Spacer()
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 12)

                        HStack {
                            Image(systemName: "wifi").foregroundStyle(.cyan)
                            VStack(alignment: .leading) {
                                Text(cast.isConnected ? "Chromecast connected" : "Watch on TV")
                                    .font(.subheadline.bold())
                                Text(cast.isConnected ? cast.tvName : "Tap to choose a TV on your Wi-Fi")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            CastButton().frame(width: 50, height: 44)
                        }
                        .padding(16)
                        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 17))

                        if !movie.castCompatible {
                            Label("Local playback only: this format needs conversion for Chromecast.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .font(.footnote)
                        } else {
                            Text("For best TV compatibility, use MP4 files with H.264 video and AAC audio. The video is transferred locally, without a Google account.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            cast.select(movie)
            if cast.isConnected { local.pause() }
        }
        .onChange(of: cast.isConnected) { connected in
            if connected { local.pause() }
        }
        .onReceive(timer) { _ in
            if cast.isConnected { cast.refreshProgress() }
            if !dragging { sliderValue = currentTime.isFinite ? max(0, currentTime) : 0 }
        }
        .onDisappear { local.pause() }
    }
    private func skip(_ seconds: TimeInterval) {
        if cast.isConnected { cast.skip(seconds) }
        else { local.seek(to: min(max(local.currentTime + seconds, 0), max(local.duration, 0))) }
    }
    private func formatTime(_ time: TimeInterval) -> String {
        let t = Int(max(0, time.isFinite ? time : 0))
        return String(format: "%02d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }
}

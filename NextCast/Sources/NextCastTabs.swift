import SwiftUI
import UniformTypeIdentifiers
import GoogleCast

struct NextCastTabs: View {
    @StateObject private var library = MovieLibrary()
    @StateObject private var cast = CastController()
    @StateObject private var downloads = VideoDownloads()
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            MoviesTab(library: library, cast: cast)
                .tabItem { Label("Movies", systemImage: "film.stack") }.tag(0)
            DownloadsTab(library: library, downloads: downloads) {
                tab = 0
            }
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }.tag(1)
            BrowserTab()
                .tabItem { Label("Browser", systemImage: "globe") }.tag(2)
            SettingsTab(library: library)
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag(3)
        }
        .tint(.cyan)
    }
}

private struct Surface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .padding(15)
            .background(scheme == .dark ? Color.white.opacity(0.075) : Color.black.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
extension View {
    func nextSurface() -> some View { modifier(Surface()) }
}

struct MoviesTab: View {
    @ObservedObject var library: MovieLibrary
    @ObservedObject var cast: CastController
    @State private var showPicker = false
    @State private var showAlternatePicker = false
    @State private var search = ""
    @State private var selected: Movie?

    private var visible: [Movie] {
        library.movies.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("YOUR PRIVATE VIDEO LIBRARY")
                            .font(.caption.bold()).tracking(1.8).foregroundStyle(.cyan)
                        Text("Watch here. Cast to TV.")
                            .font(.title2.bold())
                        Text("Stored on this iPhone · no cloud upload")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.top, 5)

                    HStack(spacing: 12) {
                        Image(systemName: "tv")
                            .font(.title2).foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cast.isConnected ? "TV connected" : "Ready to cast")
                                .font(.subheadline.bold())
                            Text(cast.isConnected ? cast.tvName : "Choose a Chromecast on your Wi-Fi")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        CastButton().frame(width: 46, height: 46)
                    }.nextSurface()

                    if library.isImporting {
                        HStack(spacing: 10) {
                            ProgressView().tint(.cyan)
                            Text(library.importStatus).font(.subheadline)
                        }.nextSurface()
                    }

                    Button { showPicker = true } label: {
                        Label("Import Video Files", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .foregroundStyle(.black)
                    .disabled(library.isImporting)

                    HStack {
                        Text("Movies").font(.title3.bold())
                        Spacer()
                        Text("\(library.movies.count) saved").font(.caption).foregroundStyle(.secondary)
                    }
                    if library.movies.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "play.rectangle.on.rectangle")
                                .font(.system(size: 55)).foregroundStyle(.cyan)
                            Text("No movies yet").font(.headline)
                            Text("Import videos with Files, or download a direct video link in Downloads.")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(26).nextSurface()
                    } else if visible.isEmpty {
                        Text("No matching videos").foregroundStyle(.secondary).padding()
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(visible) { movie in
                                Button { selected = movie } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: "play.rectangle.fill")
                                            .font(.title2).foregroundStyle(.cyan)
                                            .frame(width: 58, height: 58)
                                            .background(.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(movie.name).font(.subheadline.bold()).lineLimit(2)
                                                .foregroundStyle(.primary)
                                            Text("\(movie.format) · \(movie.fileSizeLabel)")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "play.circle.fill")
                                            .font(.title2).foregroundStyle(.cyan)
                                    }.nextSurface()
                                }.buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { library.delete(movie) } label: {
                                        Label("Remove from iPhone", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }

                    Button { showAlternatePicker = true } label: {
                        Label("Alternate Files Picker", systemImage: "folder")
                    }
                    .buttonStyle(.plain).font(.footnote).foregroundStyle(.secondary)

                    Text("If a cloud provider fails, use Files → On My iPhone → Next Cast → Imports, then Settings → Scan Imports. The original file remains untouched.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(18)
            }
            .navigationTitle("Next Cast")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CastButton().frame(width: 40, height: 40)
                }
            }
            .searchable(text: $search, prompt: "Find a movie")
            .fileImporter(isPresented: $showPicker, allowedContentTypes: [.item],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): library.importVideos(urls)
                case .failure(let error): library.errorMessage = error.localizedDescription
                }
            }
            .sheet(isPresented: $showAlternatePicker) {
                AlternateFilesPicker { urls in
                    library.importVideos(urls)
                    showAlternatePicker = false
                }
            }
            .sheet(item: $selected) { movie in
                MoviePlayerScreen(movie: movie, cast: cast)
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
    }
}

// Secondary import route for file providers that misbehave with .fileImporter.
// Mode .import copies to an app-readable location rather than opening in place.
struct AlternateFilesPicker: UIViewControllerRepresentable {
    let onSelection: ([URL]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onSelection: onSelection) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelection: ([URL]) -> Void
        init(onSelection: @escaping ([URL]) -> Void) { self.onSelection = onSelection }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onSelection(urls)
        }
    }
}

struct MoviePlayerScreen: View {
    let movie: Movie
    @ObservedObject var cast: CastController
    @StateObject private var player = VLCPlayback()
    @State private var broadcast = false
    @State private var requestedCast = false
    @State private var dragging = false
    @State private var sliderValue = 0.0
    @State private var remoteVolume = 0.6
    @Environment(\.dismiss) private var dismiss
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var duration: Double { broadcast ? cast.duration : player.duration }
    private var elapsed: Double { broadcast ? cast.position : player.currentTime }
    private var playing: Bool { broadcast ? cast.isPlaying : player.playing }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if broadcast {
                        VStack(spacing: 14) {
                            Image(systemName: "tv.fill").font(.system(size: 65)).foregroundStyle(.cyan)
                            Text("Playing on \(cast.tvName)").font(.headline)
                            Text("Keep your iPhone open while sending a local movie.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(height: 225).frame(maxWidth: .infinity)
                    } else {
                        VLCVideoSurface(player: player)
                            .frame(height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(movie.name).font(.title3.bold())
                        Text("\(movie.format) · \(movie.fileSizeLabel)")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 8) {
                        Slider(value: $sliderValue, in: 0...max(1, duration), onEditingChanged: { editing in
                            dragging = editing
                            if !editing {
                                if broadcast { cast.seek(to: sliderValue) }
                                else { player.seek(to: sliderValue) }
                            }
                        }).tint(.cyan)
                        HStack {
                            Text(timeLabel(dragging ? sliderValue : elapsed))
                            Spacer()
                            Text(timeLabel(duration))
                        }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 30) {
                        Button { skip(-15) } label: {
                            Image(systemName: "gobackward.15").font(.system(size: 32))
                        }
                        Button {
                            if broadcast { cast.togglePlay() } else { player.togglePlay() }
                        } label: {
                            Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 66))
                        }
                        Button { skip(15) } label: {
                            Image(systemName: "goforward.15").font(.system(size: 32))
                        }
                    }.buttonStyle(.plain).foregroundStyle(.cyan)
                        .frame(maxWidth: .infinity)
                        .padding(12)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "iphone").foregroundStyle(.cyan)
                            VStack(alignment: .leading) {
                                Text("Play on this iPhone").font(.headline)
                                Text("Supports MKV and more with VLC").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !broadcast { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                        }
                        Button("Switch to iPhone") {
                            broadcast = false
                            player.play()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!broadcast)
                        Divider()
                        HStack {
                            Image(systemName: "tv").foregroundStyle(.cyan)
                            VStack(alignment: .leading) {
                                Text("Cast to TV").font(.headline)
                                Text(cast.isConnected ? cast.tvName : "Select a Chromecast device")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            CastButton().frame(width: 45, height: 44)
                        }
                        Button(broadcast ? "Casting to TV" : "Play on TV") {
                            requestedCast = true
                            if cast.isConnected { playOnTV() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!movie.castCompatible || broadcast)
                        if broadcast {
                            HStack {
                                Image(systemName: "speaker.wave.2")
                                Slider(value: $remoteVolume, in: 0...1) { _ in
                                    cast.changeVolume(remoteVolume)
                                }
                            }
                        }
                        if !movie.castCompatible {
                            Text("This container plays locally. Chromecast does not support MKV / AVI directly; MP4 with H.264/AAC is recommended.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }.nextSurface()
                }.padding(18)
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
            player.open(movie.localURL)
            player.play()
        }
        .onChange(of: cast.isConnected) { connected in
            if connected && requestedCast && !broadcast { playOnTV() }
            if !connected && broadcast {
                broadcast = false
                player.play()
            }
        }
        .onReceive(ticker) { _ in
            if broadcast { cast.refreshProgress() }
            else { player.refresh() }
            if !dragging { sliderValue = elapsed.isFinite ? max(0, elapsed) : 0 }
        }
        .onDisappear {
            player.stop()
            requestedCast = false
        }
    }
    private func playOnTV() {
        guard movie.castCompatible, cast.isConnected else { return }
        player.pause()
        cast.load(movie)
        broadcast = true
    }
    private func skip(_ seconds: Double) {
        if broadcast { cast.skip(seconds) }
        else { player.skip(seconds) }
    }
    private func timeLabel(_ seconds: Double) -> String {
        let n = Int(max(0, seconds.isFinite ? seconds : 0))
        return String(format: "%02d:%02d:%02d", n / 3600, (n % 3600) / 60, n % 60)
    }
}

struct SettingsTab: View {
    @ObservedObject var library: MovieLibrary
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("browserBlockAds") private var browserBlockAds = true
    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("Follow System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }.pickerStyle(.segmented)
                }
                Section("Browser protection") {
                    Toggle("Block common ad networks", isOn: $browserBlockAds)
                    Text("Pop-ups require explicit approval. Ad filtering is best-effort and cannot remove all advertising.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("File Imports") {
                    Button {
                        library.scanImports()
                    } label: {
                        Label("Scan Imports folder", systemImage: "folder.badge.plus")
                    }
                    Text("Alternative: copy videos into On My iPhone / Next Cast / Imports from Files, then tap Scan Imports.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("About") {
                    LabeledContent("App", value: "Next Cast 1.1.0")
                    LabeledContent("Playback", value: "MobileVLCKit")
                    LabeledContent("Casting", value: "Google Cast")
                    Text("Movies remain on the device. The iPhone streams bytes across your local network when casting; it is not cloud storage.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

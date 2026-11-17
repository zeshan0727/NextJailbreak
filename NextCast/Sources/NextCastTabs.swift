import SwiftUI
import UniformTypeIdentifiers
import GoogleCast

struct NextCastTabs: View {
    @StateObject private var library = MovieLibrary()
    @StateObject private var cast = CastController()
    @StateObject private var remote = RemoteControlModel()
    @StateObject private var downloads = VideoDownloads()
    @StateObject private var browserDownloads = BrowserDownloadStore()
    @StateObject private var transfers = TransferStore.shared
    @State private var tab = 0
    @State private var showDownloads = false
    @State private var showConverter = false
    @State private var homeMovie: Movie?
    @AppStorage("appearance") private var appearance = "system"
    @State private var showTVControls = false
    @State private var showMiniCastBar = true
    @Environment(\.scenePhase) private var scenePhase

    private var selectedColorScheme: ColorScheme? {
        if appearance == "dark" { return .dark }
        if appearance == "light" { return .light }
        return nil
    }

    var body: some View {
        TabView(selection: $tab) {
            NexaHomeScreen(
                library: library, cast: cast,
                browse: { tab = 2 },
                videos: { tab = 1 },
                downloads: { showDownloads = true },
                converter: { showConverter = true },
                devices: { tab = 3 },
                files: { tab = 1 },
                settings: { tab = 4 },
                play: { movie in homeMovie = movie }
            )
            .tabItem { Label("Home", systemImage: "house.fill") }.tag(0)

            MoviesTab(library: library, cast: cast, remote: remote)
                .tabItem { Label("Library", systemImage: "film.stack.fill") }.tag(1)

            BrowserTab(library: library, downloads: browserDownloads, cast: cast) {
                showDownloads = true
            }
            .tabItem { Label("Browser", systemImage: "globe") }.tag(2)

            NexaCastDashboard(cast: cast, remote: remote)
                .tabItem { Label("Cast", systemImage: "airplay.video") }.tag(3)

            SettingsTab(library: library)
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }.tag(4)
        }
        .tint(NexaPalette.orange)
        .preferredColorScheme(selectedColorScheme)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let movie = cast.nowCastingMovie {
                HStack(spacing: 10) {
                    if showMiniCastBar {
                        Button {
                            showTVControls = true
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "tv.fill").foregroundStyle(NexaPalette.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(movie.name).lineLimit(1).font(.caption.bold())
                                    Text(cast.castStatus).lineLimit(1).font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.up")
                            }
                        }.buttonStyle(.plain)
                        Button { cast.togglePlay() } label: {
                            Image(systemName: cast.isPlaying ? "pause.fill" : "play.fill")
                        }.accessibilityLabel(cast.isPlaying ? "Pause TV" : "Play TV")
                        Button { showMiniCastBar = false } label: {
                            Image(systemName: "eye.slash")
                        }.accessibilityLabel("Hide mini player")
                    } else {
                        Spacer()
                        Button {
                            showMiniCastBar = true
                            showTVControls = true
                        } label: {
                            Label("Show TV Player", systemImage: "tv.fill")
                                .font(.caption.bold())
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 15).padding(.vertical, 11)
                .background(.regularMaterial)
            } else if let webTitle = cast.nowCastingWebTitle {
                HStack(spacing: 12) {
                    Button {
                        tab = 2
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "tv.fill").foregroundStyle(NexaPalette.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(webTitle).lineLimit(1).font(.caption.bold())
                                Text(cast.castStatus).lineLimit(1).font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 3)
                        }
                    }.buttonStyle(.plain)
                    Button { cast.togglePlay() } label: {
                        Image(systemName: cast.isPlaying ? "pause.fill" : "play.fill")
                    }.accessibilityLabel(cast.isPlaying ? "Pause TV" : "Play TV")
                    Button { cast.stopRemotePlayback() } label: {
                        Image(systemName: "stop.fill")
                    }.accessibilityLabel("Stop web video on TV")
                }
                .padding(.horizontal, 15).padding(.vertical, 11)
                .background(.regularMaterial)
            }
        }
        .sheet(isPresented: $showTVControls) {
            if let movie = cast.nowCastingMovie {
                MoviePlayerScreen(movie: movie, cast: cast, library: library)
            }
        }
        .sheet(item: $homeMovie) { movie in
            MoviePlayerScreen(movie: movie, cast: cast, library: library)
        }
        .sheet(isPresented: $showConverter) {
            VideoConverterScreen(library: library, cast: cast)
        }
        .sheet(isPresented: $showDownloads) {
            DownloadsTab(library: library, downloads: downloads,
                         browserDownloads: browserDownloads, transfers: transfers) {
                showDownloads = false
                tab = 1
            }
        }
        .onAppear { transfers.attach(library) }
        .onChange(of: scenePhase) { phase in
            cast.sceneDidChange(phase)
        }
        .onOpenURL { url in
            tab = 1
            library.importVideos([url])
        }
    }
}

private struct Surface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .padding(15)
            .background(NexaPalette.card(scheme),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20)
                .strokeBorder(NexaPalette.stroke(scheme), lineWidth: 1))
    }
}
extension View {
    func nextSurface() -> some View { modifier(Surface()) }
}

/// Swipe-to-reveal actions for ScrollView/LazyVStack rows on iOS 16.
/// The file is not deleted or converted by the gesture itself: the revealed
/// buttons require a deliberate tap.
private struct MovieSwipeActionRow<Content: View>: View {
    let onDelete: () -> Void
    let onConvert: (() -> Void)?
    let content: Content
    @State private var revealedOffset: CGFloat = 0
    private let actionWidth: CGFloat = 104

    init(onDelete: @escaping () -> Void,
         onConvert: (() -> Void)? = nil,
         @ViewBuilder content: () -> Content) {
        self.onDelete = onDelete
        self.onConvert = onConvert
        self.content = content()
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if let onConvert {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { revealedOffset = 0 }
                        onConvert()
                    } label: {
                        Label("Convert", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: actionWidth)
                            .frame(maxHeight: .infinity)
                    }
                    .background(Color.blue)
                    .accessibilityLabel("Convert video")
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { revealedOffset = 0 }
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: actionWidth)
                        .frame(maxHeight: .infinity)
                }
                .background(Color.red)
                .accessibilityLabel("Delete video")
            }
            .frame(maxHeight: .infinity)

            content
                .offset(x: revealedOffset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 18)
                        .onChanged { value in
                            guard abs(value.translation.width) >
                                    abs(value.translation.height) * 1.25 else { return }
                            let minimum: CGFloat = -actionWidth
                            let maximum: CGFloat = onConvert == nil ? 0 : actionWidth
                            revealedOffset = min(maximum, max(minimum, value.translation.width))
                        }
                        .onEnded { value in
                            guard abs(value.translation.width) >
                                    abs(value.translation.height) * 1.25 else { return }
                            let target: CGFloat
                            if value.translation.width < -50 {
                                target = -actionWidth
                            } else if value.translation.width > 50 && onConvert != nil {
                                target = actionWidth
                            } else {
                                target = 0
                            }
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.87)) {
                                revealedOffset = target
                            }
                        }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct MoviesTab: View {
    @ObservedObject var library: MovieLibrary
    @ObservedObject var cast: CastController
    @ObservedObject var remote: RemoteControlModel
    @State private var showRemote = false
    @State private var showConverter = false
    @State private var convertRequestedMovie: Movie?
    @State private var pendingDeleteMovie: Movie?
    @State private var showDeleteConfirmation = false
    @StateObject private var covers = ArtworkCache.shared
    @State private var showPicker = false
    @State private var showMultiPicker = false
    @State private var showSwiftUIFallback = false
    @State private var search = ""
    @State private var libraryFilter = "All"
    @Environment(\.colorScheme) private var scheme
    @State private var selected: Movie?

    private var visible: [Movie] {
        library.movies.filter { movie in
            let matchesSearch = search.isEmpty || movie.name.localizedCaseInsensitiveContains(search)
            let matchesFilter = libraryFilter == "All" ||
                (libraryFilter == "Originals" && !movie.isConverted) ||
                (libraryFilter == "Converted" && movie.isConverted)
            return matchesSearch && matchesFilter
        }
    }
    private var originals: [Movie] { visible.filter { !$0.isConverted } }
    private var converted: [Movie] { visible.filter(\.isConverted) }

    @ViewBuilder
    private var movieLibrarySection: some View {
        HStack {
            Text("Saved videos").font(.title3.bold())
            Spacer()
            Text("\(library.movies.count) saved")
                .font(.caption).foregroundStyle(.secondary)
        }
        if !originals.isEmpty {
            Text("Swipe right to convert  ·  Swipe left to delete")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        if library.movies.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "play.rectangle.on.rectangle")
                    .font(.system(size: 55)).foregroundStyle(NexaPalette.orange)
                Text("Your library is empty").font(.headline)
                Text("Import videos with Files, or download a direct video link in Downloads.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(26).nextSurface()
        } else if visible.isEmpty {
            Text("No videos match your search or filter").foregroundStyle(.secondary).padding()
        } else {
            if !converted.isEmpty { convertedSection }
            if !originals.isEmpty { originalsSection }
        }
    }

    private var convertedSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Converted Movies · \(converted.count)", systemImage: "folder.fill")
                .font(.headline).foregroundStyle(NexaPalette.orange)
            ForEach(converted) { movie in
                MovieSwipeActionRow(onDelete: { requestDelete(movie) }) {
                    Button { selected = movie } label: {
                        convertedRow(movie)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { requestDelete(movie) } label: {
                            Label("Delete converted movie", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func convertedRow(_ movie: Movie) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "tv.fill").foregroundStyle(NexaPalette.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(movie.name).font(.subheadline.bold()).lineLimit(2)
                Text("TV Ready · \(movie.fileSizeLabel)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "play.circle.fill")
        }
        .nextSurface()
    }

    private var originalsSection: some View {
        LazyVStack(spacing: 10) {
            ForEach(originals) { movie in
                MovieSwipeActionRow(
                    onDelete: { requestDelete(movie) },
                    onConvert: { openConverter(for: movie) }
                ) {
                    Button { selected = movie } label: { originalRow(movie) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                openConverter(for: movie)
                            } label: {
                                Label("Convert Video", systemImage: "arrow.triangle.2.circlepath")
                            }
                            Button { covers.regenerate(movie) } label: {
                                Label("Regenerate Cover", systemImage: "photo.on.rectangle.angled")
                            }
                            Button(role: .destructive) { requestDelete(movie) } label: {
                                Label("Remove from iPhone", systemImage: "trash")
                            }
                        }
                }
                .onAppear { covers.load(movie) }
            }
        }
    }

    private func openConverter(for movie: Movie) {
        guard !movie.isConverted else { return }
        convertRequestedMovie = movie
        showConverter = true
    }

    private func requestDelete(_ movie: Movie) {
        pendingDeleteMovie = movie
        showDeleteConfirmation = true
    }

    private func originalRow(_ movie: Movie) -> some View {
        HStack(spacing: 14) {
            ZStack {
                if let image = covers.images[movie.id] {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 93, height: 91).clipped()
                } else {
                    ZStack {
                        Color.cyan.opacity(0.1)
                        Image(systemName: "film").font(.title2).foregroundStyle(NexaPalette.orange)
                    }.frame(width: 93, height: 91)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(movie.name).font(.subheadline.bold())
                    .lineLimit(2).foregroundStyle(.primary)
                if let info = covers.details[movie.id] {
                    Text(info.durationLabel).font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(info.resolutionLabel).font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("\(movie.format) · \(movie.fileSizeLabel)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(NexaPalette.orange)
        }
        .nextSurface()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("YOUR COLLECTION")
                            .font(.caption.weight(.heavy))
                            .tracking(1.8)
                            .foregroundStyle(NexaPalette.orange)
                        Text("My Library")
                            .font(.largeTitle.weight(.bold))
                        Text("Play, convert, and send videos to your TV.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)

                    HStack(spacing: 8) {
                        ForEach(["All", "Originals", "Converted"], id: \.self) { value in
                            Button {
                                withAnimation(.easeOut(duration: 0.18)) { libraryFilter = value }
                            } label: {
                                Text(value)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(libraryFilter == value ? .white : .primary)
                                    .padding(.horizontal, 15)
                                    .padding(.vertical, 9)
                                    .background(libraryFilter == value ?
                                        NexaPalette.orange : NexaPalette.card(scheme),
                                        in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "tv")
                            .font(.title2).foregroundStyle(NexaPalette.orange)
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
                            ProgressView().tint(NexaPalette.orange)
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
                    .tint(NexaPalette.orange)
                    .foregroundStyle(.black)
                    .disabled(library.isImporting)

                    Button {
                        convertRequestedMovie = nil
                        showConverter = true
                    } label: {
                        Label("Media Converter", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.bordered)
                    .disabled(library.movies.isEmpty)

                    movieLibrarySection

                    HStack(spacing: 14) {
                        Button { showMultiPicker = true } label: {
                            Label("Import Multiple", systemImage: "square.stack.3d.up")
                        }
                        Button { showSwiftUIFallback = true } label: {
                            Label("Alternate Picker", systemImage: "folder.badge.plus")
                        }
                    }
                    .buttonStyle(.bordered)
                    .font(.subheadline)
                    .disabled(library.isImporting)

                    if !library.importStatus.isEmpty && !library.isImporting {
                        Label(library.importStatus, systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Text("Importing from Files preserves the originals. Existing stored videos stay in the same app container.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(18)
            }
            .background(NexaPalette.canvas(scheme))
            .navigationTitle("Library")
            .overlay(alignment: .bottomTrailing) {
                Button {
                    showPicker = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(NexaPalette.warmGradient, in: Circle())
                        .shadow(color: NexaPalette.orange.opacity(0.3), radius: 11, y: 5)
                }
                .disabled(library.isImporting)
                .accessibilityLabel("Import video")
                .padding(.trailing, 19).padding(.bottom, 18)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CastButton().frame(width: 40, height: 40)
                }
            }
            .searchable(text: $search, prompt: "Find a movie")
            .sheet(isPresented: $showPicker) {
                ReliableVideoPicker(multiple: false) { urls in
                    showPicker = false
                    library.importVideos(urls)
                } didCancel: {
                    showPicker = false
                    library.importStatus = "Selection cancelled"
                }
            }
            .sheet(isPresented: $showMultiPicker) {
                ReliableVideoPicker(multiple: true) { urls in
                    showMultiPicker = false
                    library.importVideos(urls)
                } didCancel: {
                    showMultiPicker = false
                    library.importStatus = "Selection cancelled"
                }
            }
            .fileImporter(isPresented: $showSwiftUIFallback,
                          allowedContentTypes: [.data, .movie],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    library.importVideos(urls)
                case .failure(let error):
                    library.errorMessage = "Alternate picker: \(error.localizedDescription)"
                }
            }
            .sheet(isPresented: $showRemote) {
                RemoteTab(remote: remote, cast: cast)
            }
            .sheet(isPresented: $showConverter, onDismiss: {
                convertRequestedMovie = nil
            }) {
                VideoConverterScreen(library: library, cast: cast,
                                     initialMovie: convertRequestedMovie)
            }
            .confirmationDialog("Delete video?", isPresented: $showDeleteConfirmation,
                                titleVisibility: .visible) {
                Button("Delete from iPhone", role: .destructive) {
                    if let movie = pendingDeleteMovie {
                        library.delete(movie)
                        if selected?.id == movie.id { selected = nil }
                    }
                    pendingDeleteMovie = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteMovie = nil
                }
            } message: {
                Text("Delete \(pendingDeleteMovie?.name ?? "this video")? This removes the stored file from Next Cast. Other copies and converted files are not deleted.")
            }
            .sheet(item: $selected) { movie in
                MoviePlayerScreen(movie: movie, cast: cast, library: library)
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

struct SettingsTab: View {
    @ObservedObject var library: MovieLibrary
    @Environment(\.colorScheme) private var scheme
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("browserBlockAds") private var browserBlockAds = true
    @AppStorage("nextcast.blockPopups") private var blockPopups = true
    @AppStorage("nextcast.keepLocalCastWhileLocked") private var keepLocalCastWhileLocked = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.title2).foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(NexaPalette.warmGradient, in: RoundedRectangle(cornerRadius: 15))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("NexaPlay").font(.title2.bold())
                            Text("by NEXT").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("v" + version).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }.nexaCard()

                    section("APPEARANCE") {
                        Picker("Theme", selection: $appearance) {
                            Text("System").tag("system")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }.pickerStyle(.segmented)
                    }
                    section("BROWSER") {
                        Toggle(isOn: $blockPopups) {
                            row("Ask before pop-ups", "rectangle.on.rectangle", NexaPalette.blue)
                        }
                        Divider()
                        Toggle(isOn: $browserBlockAds) {
                            row("Block ad networks", "shield.lefthalf.filled", NexaPalette.purple)
                        }
                    }
                    section("PLAYBACK") {
                        Toggle(isOn: $keepLocalCastWhileLocked) {
                            row("Stream while locked", "tv", NexaPalette.blue)
                        }
                        Text("Experimental · iOS may pause streaming")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    section("FILES") {
                        Button {
                            library.scanImports()
                        } label: {
                            HStack {
                                row("Scan Imports", "folder.badge.plus", NexaPalette.orange)
                                Spacer()
                                if library.isImporting { ProgressView() }
                                else { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                            }
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(library.isImporting)
                    }
                    Text("NexaPlay " + version + " (" + build + ")  ·  by NEXT")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(NexaPalette.canvas(scheme).ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
    private func section<Content: View>(_ title: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.caption2.bold()).tracking(1.4)
                .foregroundStyle(.secondary).padding(.leading, 10)
            VStack(alignment: .leading, spacing: 12) { content() }
                .tint(NexaPalette.orange)
                .padding(14)
                .background(NexaPalette.card(scheme),
                            in: RoundedRectangle(cornerRadius: 18))
        }
    }
    private func row(_ title: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 17))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
        }
    }
}

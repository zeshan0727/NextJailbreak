import SwiftUI
import UniformTypeIdentifiers
import GoogleCast

struct NextCastTabs: View {
    @StateObject private var library = MovieLibrary()
    @StateObject private var cast = CastController()
    @StateObject private var downloads = VideoDownloads()
    @StateObject private var browserDownloads = BrowserDownloadStore()
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            MoviesTab(library: library, cast: cast)
                .tabItem { Label("Movies", systemImage: "film.stack") }.tag(0)
            DownloadsTab(library: library, downloads: downloads, browserDownloads: browserDownloads) {
                tab = 0
            }
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }.tag(1)
            BrowserTab(library: library, downloads: browserDownloads) {
                tab = 1
            }
                .tabItem { Label("Browser", systemImage: "globe") }.tag(2)
            SettingsTab(library: library)
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag(3)
        }
        .tint(.cyan)
        .onOpenURL { url in
            tab = 0
            library.importVideos([url])
        }
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
    @State private var showMultiPicker = false
    @State private var showSwiftUIFallback = false
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

                    Text("If a cloud provider fails, use Files → On My iPhone → Next Cast → Imports, then Settings → Scan Imports. A copy is imported and the Imports inbox is cleared after success.")
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

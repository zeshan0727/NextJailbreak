import SwiftUI

/// NexaPlay's adaptive design tokens. No external artwork or runtime services.
enum NexaPalette {
    static let orange = Color(red: 1, green: 0.52, blue: 0.02)
    static let red = Color(red: 1, green: 0.22, blue: 0.13)
    static let blue = Color(red: 0.08, green: 0.54, blue: 1)
    static let purple = Color(red: 0.58, green: 0.30, blue: 1)
    static let green = Color(red: 0.13, green: 0.82, blue: 0.52)
    static let midnight = Color(red: 0.031, green: 0.051, blue: 0.098)
    static let navy = Color(red: 0.071, green: 0.102, blue: 0.17)
    static let warmGradient = LinearGradient(
        colors: [orange, red], startPoint: .topLeading, endPoint: .bottomTrailing)
    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? midnight : Color(red: 0.969, green: 0.975, blue: 0.99)
    }
    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? navy : .white
    }
    static func stroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.085) : .black.opacity(0.055)
    }
}

private struct NexaCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var inset: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(inset)
            .background(NexaPalette.card(scheme),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(NexaPalette.stroke(scheme), lineWidth: 1))
    }
}
extension View {
    func nexaCard(inset: CGFloat = 16) -> some View {
        modifier(NexaCardModifier(inset: inset))
    }
}

struct NexaGradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(NexaPalette.warmGradient,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: NexaPalette.orange.opacity(0.18), radius: 9, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct NexaFeatureTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 46, height: 46)
                    .background(tint.opacity(0.13),
                                in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 105, alignment: .leading)
            .nexaCard(inset: 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + ", " + subtitle)
    }
}

struct NexaHomeScreen: View {
    @ObservedObject var library: MovieLibrary
    @ObservedObject var cast: CastController
    let browse: () -> Void
    let videos: () -> Void
    let downloads: () -> Void
    let converter: () -> Void
    let devices: () -> Void
    let files: () -> Void
    let settings: () -> Void
    let play: (Movie) -> Void

    @StateObject private var artwork = ArtworkCache.shared
    @State private var showImportPicker = false
    @Environment(\.colorScheme) private var scheme

    private var resumeMovie: Movie? {
        library.movies.first { PlaybackHistory.position(for: $0.id) >= 5 }
    }

    private var recent: [Movie] { Array(library.movies.prefix(12)) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                    .background(NexaPalette.canvas(scheme))
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        hero
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Your media").font(.title3.weight(.bold))
                            Spacer()
                            Button("See all", action: videos)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(NexaPalette.orange)
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                            GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            NexaFeatureTile(title: "Videos", subtitle: "My library",
                                            symbol: "play.rectangle.fill", tint: NexaPalette.purple, action: videos)
                            NexaFeatureTile(title: "Browser", subtitle: "Stream & explore",
                                            symbol: "globe", tint: NexaPalette.blue, action: browse)
                            NexaFeatureTile(title: "Downloads", subtitle: "Offline files",
                                            symbol: "arrow.down.circle.fill", tint: NexaPalette.green, action: downloads)
                            NexaFeatureTile(title: "Converter", subtitle: "TV-ready media",
                                            symbol: "arrow.triangle.2.circlepath", tint: NexaPalette.orange,
                                            action: converter)
                            NexaFeatureTile(title: "Cast", subtitle: "TV & devices",
                                            symbol: "tv.fill", tint: NexaPalette.blue, action: devices)
                            NexaFeatureTile(title: "Files", subtitle: "Manage videos",
                                            symbol: "folder.fill", tint: Color(red: 1, green: 0.72, blue: 0.12),
                                            action: files)
                        }
                    }
                    if !recent.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Recently added").font(.title3.weight(.bold))
                                Spacer()
                                Button("See all", action: videos)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(NexaPalette.orange)
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 12) {
                                    ForEach(recent) { movie in
                                        Button { play(movie) } label: {
                                            VStack(alignment: .leading, spacing: 7) {
                                                movieArtwork(movie)
                                                    .frame(width: 146, height: 90)
                                                    .clipShape(RoundedRectangle(cornerRadius: 13))
                                                Text(movie.name)
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                Text(movie.format.uppercased() + " · " + movie.fileSizeLabel)
                                                    .font(.caption2).foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 146, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)
                                        .onAppear { artwork.load(movie) }
                                    }
                                }
                            }
                        }
                    }
                    Label("Your videos stay on this iPhone", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 100)
                }
            }
            .background(NexaPalette.canvas(scheme).ignoresSafeArea())
            .overlay(alignment: .bottomTrailing) {
                Button { showImportPicker = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 57, height: 57)
                        .background(NexaPalette.warmGradient, in: Circle())
                        .shadow(color: NexaPalette.orange.opacity(0.26), radius: 11, y: 6)
                }
                .disabled(library.isImporting)
                .accessibilityLabel("Import videos")
                .padding(.trailing, 18).padding(.bottom, 16)
            }
            .sheet(isPresented: $showImportPicker) {
                ReliableVideoPicker(multiple: true) { urls in
                    showImportPicker = false
                    library.importVideos(urls)
                } didCancel: {
                    showImportPicker = false
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [NexaPalette.blue, NexaPalette.purple,
                                                  NexaPalette.orange],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "play.fill")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 0) {
                Text("NexaPlay")
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                Text("by NEXT")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if cast.isConnected {
                Button(action: devices) {
                    Label(cast.tvName, systemImage: "tv.fill")
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                }
                .tint(NexaPalette.green)
                .frame(maxWidth: 118)
            } else {
                CastButton().frame(width: 38, height: 38)
            }
            Button(action: settings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 19, weight: .medium))
            }
            .tint(.primary)
            .accessibilityLabel("Settings")
        }
    }

    private var hero: some View {
        Group {
            if let movie = resumeMovie {
                Button { play(movie) } label: {
                    heroContent(movie: movie,
                                eyebrow: "CONTINUE WATCHING",
                                headline: movie.name,
                                detail: "Resume from " + timeLabel(PlaybackHistory.position(for: movie.id)))
                }
                .buttonStyle(.plain)
                .onAppear { artwork.load(movie) }
            } else if let movie = recent.first {
                Button { play(movie) } label: {
                    heroContent(movie: movie, eyebrow: "READY TO WATCH",
                                headline: movie.name, detail: "Play on iPhone or Cast to TV")
                }
                .buttonStyle(.plain)
                .onAppear { artwork.load(movie) }
            } else {
                Button(action: files) {
                    heroContent(movie: nil, eyebrow: "WELCOME TO NEXAPLAY",
                                headline: "Your cinema. Anywhere.",
                                detail: "Import a video to get started")
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityLabel("Featured video")
    }

    /// Display a readable movie title; keep the untouched full filename in Library.
    private func shortMovieTitle(_ fileName: String) -> String {
        let normalized = fileName.replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let words = normalized.split(separator: " ")
        let cutoff = words.firstIndex(where: { word in
            let token = word.lowercased()
            let isReleaseYear = word.count == 4 &&
                word.allSatisfy { $0.isNumber } &&
                (Int(word).map { (1900...2099).contains($0) } ?? false)
            return isReleaseYear || ["1080p", "720p", "2160p", "4k", "webrip", "webdl",
                                     "web-dl", "bluray", "h264", "h265", "x264", "x265"].contains(token)
        })
        let title = words.prefix(cutoff ?? words.count).joined(separator: " ")
        return title.isEmpty ? fileName : title
    }

    private func heroContent(movie: Movie?, eyebrow: String,
                             headline: String, detail: String) -> some View {
        GeometryReader { bounds in
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let movie, let image = artwork.images[movie.id] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: bounds.size.width, height: bounds.size.height)
                            .clipped()
                    } else {
                        LinearGradient(colors: [NexaPalette.purple.opacity(0.78),
                                                NexaPalette.navy, NexaPalette.orange.opacity(0.65)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .frame(width: bounds.size.width, height: bounds.size.height)
                LinearGradient(colors: [.black.opacity(0.04), .black.opacity(0.78)],
                               startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 9) {
                    Text(eyebrow)
                        .font(.caption2.weight(.bold))
                        .tracking(1.3)
                        .foregroundStyle(.white.opacity(0.87))
                    Text(shortMovieTitle(headline))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Label(detail, systemImage: "play.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.96))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .frame(width: bounds.size.width, height: bounds.size.height)
            .clipped()
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(.white.opacity(0.1), lineWidth: 1))
    }

    @ViewBuilder
    private func movieArtwork(_ movie: Movie) -> some View {
        if let image = artwork.images[movie.id] {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(colors: [NexaPalette.navy, NexaPalette.purple.opacity(0.75)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "play.fill").foregroundStyle(.white).font(.title2)
            }
        }
    }

    private func timeLabel(_ time: Double) -> String {
        let seconds = max(0, Int(time))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// A cinematic, actionable media-casting surface. The existing multi-brand
/// TV remote remains available through the Full TV Remote button.
struct NexaCastDashboard: View {
    @ObservedObject var cast: CastController
    @ObservedObject var remote: RemoteControlModel
    @State private var showRemote = false
    @State private var seekPosition: Double = 0
    @Environment(\.colorScheme) private var scheme

    private var activeTitle: String {
        cast.nowCastingMovie?.name ?? cast.nowCastingWebTitle ?? "No media playing"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Casting").font(.largeTitle.weight(.bold))
                        Spacer()
                        CastButton().frame(width: 42, height: 42)
                    }
                    HStack(spacing: 11) {
                        Image(systemName: "tv.fill")
                            .font(.title2).foregroundStyle(NexaPalette.blue)
                            .frame(width: 48, height: 48)
                            .background(NexaPalette.blue.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(cast.isConnected ? cast.tvName : "Select a TV")
                                .font(.headline).lineLimit(1)
                            Text(cast.isConnected ? cast.castStatus : "Connect a Google Cast receiver")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Circle()
                            .fill(cast.isConnected ? NexaPalette.green : .orange)
                            .frame(width: 9, height: 9)
                    }
                    .nexaCard()

                    ZStack {
                        LinearGradient(colors: [NexaPalette.purple.opacity(0.75),
                                                NexaPalette.navy, NexaPalette.orange.opacity(0.75)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "airplay.video")
                            .font(.system(size: 66, weight: .ultraLight))
                            .foregroundStyle(.white)
                    }
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    VStack(alignment: .leading, spacing: 14) {
                        Text(activeTitle).font(.title3.weight(.bold)).lineLimit(2)
                        Text(cast.castStatus).font(.subheadline).foregroundStyle(.secondary)
                        if cast.nowCastingMovie != nil || cast.nowCastingWebTitle != nil {
                            Slider(value: $seekPosition, in: 0...max(cast.duration, 1),
                                   onEditingChanged: { editing in
                                       if !editing { cast.seek(to: seekPosition) }
                                   })
                                .tint(NexaPalette.orange)
                                .onChange(of: cast.position) { position in
                                    seekPosition = position
                                }
                            HStack {
                                Text(timeLabel(cast.position))
                                Spacer()
                                Text(timeLabel(cast.duration))
                            }
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            HStack(spacing: 28) {
                                Spacer()
                                Button { cast.skip(-15) } label: {
                                    Image(systemName: "gobackward.15").font(.title2)
                                }
                                Button { cast.togglePlay() } label: {
                                    Image(systemName: cast.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.title2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 64, height: 64)
                                        .background(NexaPalette.warmGradient, in: Circle())
                                }
                                Button { cast.skip(15) } label: {
                                    Image(systemName: "goforward.15").font(.title2)
                                }
                                Spacer()
                            }
                            .tint(.primary)
                            Button(role: .destructive) {
                                cast.stopRemotePlayback()
                            } label: {
                                Label("Stop Casting", systemImage: "stop.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Text("Choose a receiver above, then start a movie from Library or Browser.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .nexaCard()
                    Button { showRemote = true } label: {
                        Label("Full TV Remote", systemImage: "appletvremote.gen4.fill")
                    }
                    .buttonStyle(NexaGradientButtonStyle())
                    Text("Media controls require a compatible connected receiver. Navigation and TV pairing options remain in the full remote.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .background(NexaPalette.canvas(scheme))
            .navigationBarHidden(true)
            .sheet(isPresented: $showRemote) {
                RemoteTab(remote: remote, cast: cast)
            }
        }
    }

    private func timeLabel(_ time: Double) -> String {
        let seconds = time.isFinite ? max(0, Int(time)) : 0
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

import SwiftUI
import UIKit
import Combine

/// Stores a movie's last meaningful playback position under its persistent
/// library UUID. The same saved position survives app updates/relaunches.
enum PlaybackHistory {
    private static func key(_ id: UUID) -> String {
        "nextcast.playback.\(id.uuidString)"
    }

    static func position(for id: UUID) -> Double {
        let value = UserDefaults.standard.double(forKey: key(id))
        return value.isFinite && value > 0 ? value : 0
    }

    static func save(_ seconds: Double, duration: Double, id: UUID) {
        guard seconds.isFinite, duration.isFinite, duration > 0 else { return }
        // Finished movies start from the beginning on the next opening.
        if duration - seconds < 20 {
            UserDefaults.standard.removeObject(forKey: key(id))
        } else if seconds >= 5 {
            UserDefaults.standard.set(seconds, forKey: key(id))
        }
    }

    static func clear(_ id: UUID) {
        UserDefaults.standard.removeObject(forKey: key(id))
    }
}

struct MoviePlayerScreen: View {
    let movie: Movie
    @ObservedObject var cast: CastController
    @StateObject private var player = VLCPlayback()
    @StateObject private var castPreparer = MKVCastPreparer()
    @State private var broadcast = false
    @State private var requestedCast = false
    @State private var dragging = false
    @State private var sliderValue: Double = 0
    @State private var remoteVolume = 0.6
    @State private var fullScreen = false
    @State private var showResumeAlert = false
    @State private var savedResumeTime = 0.0
    @State private var lastProgressSaved = Date.distantPast
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var duration: Double { broadcast ? cast.duration : player.duration }
    private var elapsed: Double { broadcast ? cast.position : player.currentTime }
    private var playing: Bool { broadcast ? cast.isPlaying : player.playing }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 17) {
                    if broadcast {
                        VStack(spacing: 14) {
                            Image(systemName: "tv.fill")
                                .font(.system(size: 62))
                                .foregroundStyle(.cyan)
                            Text("Playing on \(cast.tvName)").font(.headline)
                            Text("Keep the iPhone awake while streaming a local video.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(height: 230).frame(maxWidth: .infinity)
                    } else {
                        ZStack(alignment: .bottomTrailing) {
                            VLCVideoSurface(player: player, role: .inline)
                                .frame(height: 245)
                                .background(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            Button {
                                player.activate(.fullscreen)
                            fullScreen = true
                            } label: {
                                Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right")
                                    .labelStyle(.iconOnly)
                                    .font(.title3.bold())
                                    .foregroundStyle(.white)
                                    .padding(13)
                                    .background(.black.opacity(0.7), in: Circle())
                            }
                            .accessibilityLabel("Enter full-screen player")
                            .padding(12)
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(movie.name)
                            .font(.title3.bold())
                            .lineLimit(3)
                        Text("\(movie.format) · \(movie.fileSizeLabel)")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 8) {
                        Slider(value: $sliderValue, in: 0...max(1, duration), onEditingChanged: { editing in
                            dragging = editing
                            if !editing {
                                if broadcast { cast.seek(to: sliderValue) }
                                else {
                                    player.seek(to: sliderValue)
                                    persistPlayback()
                                }
                            }
                        }).tint(.cyan)
                        HStack {
                            Text(timeLabel(dragging ? sliderValue : elapsed))
                            Spacer()
                            Text(timeLabel(duration))
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 32) {
                        Button { skip(-15) } label: {
                            Image(systemName: "gobackward.15").font(.system(size: 32))
                        }
                        Button {
                            if broadcast { cast.togglePlay() }
                            else { player.togglePlay(); persistPlayback() }
                        } label: {
                            Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 64))
                        }
                        Button { skip(15) } label: {
                            Image(systemName: "goforward.15").font(.system(size: 32))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.cyan)
                    .frame(maxWidth: .infinity).padding(11)

                    if !broadcast {
                        Button {
                            player.activate(.fullscreen)
                            fullScreen = true
                        } label: {
                            Label("Watch Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .foregroundStyle(.black)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "iphone").foregroundStyle(.cyan)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Local player").font(.headline)
                                Text("VLC · MP4 / MKV / AVI / more")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !broadcast {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                        if broadcast {
                            Button("Return to iPhone") {
                                broadcast = false
                                player.play()
                            }
                            .buttonStyle(.bordered)
                        }
                        Divider()
                        HStack {
                            Image(systemName: "tv").foregroundStyle(.cyan)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Chromecast").font(.headline)
                                Text(cast.isConnected ? cast.tvName : "Choose a TV on the same Wi-Fi")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            CastButton().frame(width: 46, height: 46)
                        }
                        Button(broadcast ? "Playing on TV" :
                               castPreparer.preparing ? "Preparing TV MP4…" :
                               movie.format == "MKV" ? "MKV requires MP4" : "Play on TV") {
                            requestedCast = true
                            if cast.isConnected { playOnTV() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(broadcast || castPreparer.preparing)
                        if castPreparer.preparing {
                            VStack(alignment: .leading, spacing: 7) {
                                ProgressView()
                                Text(castPreparer.status)
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("Apple native conversion · copying H.264 video and encoding stereo AAC. Keep Next Cast open.")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Button("Cancel preparation", role: .destructive) {
                                    castPreparer.cancel()
                                }.font(.caption)
                            }
                        }
                        if broadcast {
                            HStack {
                                Image(systemName: "speaker.wave.2")
                                Slider(value: $remoteVolume, in: 0...1) { _ in
                                    cast.changeVolume(remoteVolume)
                                }
                            }
                        }
                        if movie.format == "MKV" {
                            Text("MKV playback in VLC is supported. MKV-to-MP4 conversion is temporarily disabled because the old FFmpeg engine crashed on iOS 16. Use a compatible MP4 for TV.")
                                .font(.caption).foregroundStyle(.orange)
                        } else if !movie.castCompatible {
                            Text("Native MP4 preparation supports MP4, M4V and MOV containing H.264 video. Other containers can still play locally through VLC.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    .nextSurface()
                }.padding(18)
            }
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        persistPlayback()
                        player.stop()
                        dismiss()
                    }
                }
            }
        }
        .alert("TV Cast preparation", isPresented: Binding(
            get: { castPreparer.errorMessage != nil },
            set: { if !$0 { castPreparer.errorMessage = nil } }
        )) {
            Button("OK") { castPreparer.errorMessage = nil }
        } message: {
            Text(castPreparer.errorMessage ?? "")
        }
        .alert("Continue watching?", isPresented: $showResumeAlert) {
            Button("Resume from \(timeLabel(savedResumeTime))") {
                player.resumeWhenReady(at: savedResumeTime)
                player.play()
            }
            Button("Start Over") {
                PlaybackHistory.clear(movie.id)
                player.resumeWhenReady(at: 0)
                player.play()
            }
        } message: {
            Text("You previously stopped \(movie.name) at \(timeLabel(savedResumeTime)).")
        }
        .fullScreenCover(isPresented: $fullScreen, onDismiss: {
            // Reparent the SAME VLC drawable, not a second video surface.
            player.activate(.inline)
            persistPlayback()
        }) {
            FullScreenVLCPlayer(player: player, movieName: movie.name) {
                fullScreen = false
            }
        }
        .onAppear {
            player.open(movie.localURL)
            savedResumeTime = PlaybackHistory.position(for: movie.id)
            if savedResumeTime >= 15 {
                showResumeAlert = true
            } else {
                player.play()
            }
        }
        .onChange(of: cast.isConnected) { connected in
            if connected && requestedCast && !broadcast { playOnTV() }
            if !connected && broadcast {
                broadcast = false
                player.play()
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { persistPlayback() }
        }
        .onReceive(ticker) { _ in
            if broadcast { cast.refreshProgress() }
            else {
                player.refresh()
                if Date().timeIntervalSince(lastProgressSaved) >= 4 {
                    persistPlayback()
                    lastProgressSaved = Date()
                }
            }
            if !dragging {
                sliderValue = elapsed.isFinite ? max(0, elapsed) : 0
            }
        }
        .onDisappear {
            if !fullScreen {
                persistPlayback()
                player.stop()
                castPreparer.cancel()
                requestedCast = false
            }
        }
    }

    private func persistPlayback() {
        if !broadcast {
            PlaybackHistory.save(player.currentTime, duration: player.duration, id: movie.id)
        }
    }
    private func playOnTV() {
        guard cast.isConnected, !broadcast else { return }
        castPreparer.prepare(movie) { readyMovie in
            guard cast.isConnected, requestedCast else { return }
            persistPlayback()
            player.pause()
            cast.load(readyMovie)
            broadcast = true
        }
    }
    private func skip(_ seconds: Double) {
        if broadcast { cast.skip(seconds) }
        else { player.skip(seconds); persistPlayback() }
    }
}

struct FullScreenVLCPlayer: View {
    @ObservedObject var player: VLCPlayback
    let movieName: String
    let dismiss: () -> Void
    @State private var showControls = true
    @State private var seeking = false
    @State private var seekValue = 0.0
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                VLCVideoSurface(player: player, role: .fullscreen)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color.black)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() } }
                if showControls {
                    VStack(spacing: 0) {
                        HStack {
                            Button {
                                dismiss()
                            } label: {
                                Label("Exit full screen", systemImage: "arrow.down.right.and.arrow.up.left")
                                    .font(.headline)
                            }
                            Spacer()
                            Text(movieName)
                                .lineLimit(1)
                                .font(.subheadline.bold())
                            Spacer()
                            Button {
                                requestLandscape()
                            } label: {
                                Image(systemName: "rotate.right")
                                    .font(.headline)
                            }
                            .accessibilityLabel("Rotate to landscape")
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 16)
                        .background(.black.opacity(0.63))

                        Spacer()

                        HStack(spacing: 44) {
                            Button { player.skip(-15) } label: {
                                Image(systemName: "gobackward.15").font(.system(size: 34))
                            }
                            Button { player.togglePlay() } label: {
                                Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 64))
                            }
                            Button { player.skip(15) } label: {
                                Image(systemName: "goforward.15").font(.system(size: 34))
                            }
                        }
                        .padding(18)
                        Spacer()

                        VStack(spacing: 7) {
                            Slider(value: $seekValue,
                                   in: 0...max(1, player.duration),
                                   onEditingChanged: { editing in
                                seeking = editing
                                if !editing { player.seek(to: seekValue) }
                            }).tint(.cyan)
                            HStack {
                                Text(timeLabel(seeking ? seekValue : player.currentTime))
                                Spacer()
                                Text(timeLabel(player.duration))
                            }
                            .font(.caption.monospacedDigit())
                        }
                        .padding(.horizontal, 25)
                        .padding(.vertical, 14)
                        .background(.black.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .transition(.opacity)
                }
            }
        }
        .statusBarHidden()
        .onAppear { player.activate(.fullscreen) }
        .onReceive(ticker) { _ in
            player.refresh()
            if !seeking { seekValue = player.currentTime }
        }
        .onDisappear {
            // The dismiss callback reattaches the persistent drawable inline.
            restorePortrait()
        }
    }

    private func requestLandscape() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in
            // Manual device rotation remains supported if geometry request is denied.
        }
    }

    private func restorePortrait() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
    }
}

private func timeLabel(_ seconds: Double) -> String {
    let t = Int(max(0, seconds.isFinite ? seconds : 0))
    return String(format: "%02d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
}

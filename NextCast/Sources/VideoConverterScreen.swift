import SwiftUI

/// First-party TV converter. Settings are intentionally familiar to users of
/// professional media converters, without copying any third-party interface.
/// Uses verified FFmpeg 8.1.2 "min" binaries for MKV/audio-track support.
struct VideoConverterScreen: View {
    @ObservedObject var library: MovieLibrary
    @ObservedObject var cast: CastController
    @StateObject private var preparer = MKVCastPreparer()
    @State private var selected: Movie?
    @State private var ready: Movie?
    @State private var details: TVSourceDetails?
    @State private var inspecting = false
    @State private var inspectionError: String?
    @State private var settingsTab = 0
    @State private var showsAdvanced = false
    @State private var options = TVConversionOptions()
    @Environment(\.dismiss) private var dismiss

    init(library: MovieLibrary, cast: CastController, initialMovie: Movie? = nil) {
        self.library = library
        self.cast = cast
        _selected = State(initialValue: initialMovie)
    }

    private var originals: [Movie] { library.movies.filter { !$0.isConverted } }
    private var requiresEncoding: Bool {
        guard let details else { return false }
        return options.requiresVideoEncode(details)
    }

    private let accent = Color(red: 0.04, green: 0.40, blue: 0.98)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if preparer.preparing {
                            progressPanel
                        } else if let ready {
                            readyPanel(ready)
                        } else {
                            introduction
                            sourcePanel

                            if let details {
                                encodingModePanel(details)
                                outputPanel(details)
                                advancedSettings(details)
                            } else if inspecting {
                                HStack(spacing: 12) {
                                    ProgressView().tint(accent)
                                    Text("Checking video format and audio tracks…")
                                        .font(.subheadline)
                                }
                                .nextSurface()
                            } else if let inspectionError {
                                Label(inspectionError, systemImage: "exclamationmark.triangle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.orange)
                                    .nextSurface()
                            }

                            Label("Your original video is never changed. Finished MP4 files appear under Movies → Converted.",
                                  systemImage: "lock.shield")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 22)
                }

                if !preparer.preparing && ready == nil {
                    Button(action: beginConversion) {
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill")
                            Text(options.videoMode == .remux ? "Create MP4 Without Re-encoding" : "Convert Video")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .disabled(selected == nil || details == nil || inspecting)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Media Converter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.disabled(preparer.preparing)
                }
            }
            .onAppear {
                if selected == nil { selected = originals.first }
                inspectSelected()
            }
            .onChange(of: selected?.id) { _ in inspectSelected() }
            .onChange(of: options.audioOrdinal) { _ in
                if let details, options.videoMode == .remux,
                   !details.supportsNoReencoding(audioOrdinal: options.audioOrdinal) {
                    options.videoMode = .automatic
                }
            }
            .alert("Media Converter", isPresented: Binding(
                get: { preparer.errorMessage != nil },
                set: { if !$0 { preparer.errorMessage = nil } }
            )) {
                Button("OK") { preparer.errorMessage = nil }
            } message: {
                Text(preparer.errorMessage ?? "")
            }
        }
    }

    private var introduction: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath.video")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 54, height: 54)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text("Make your video TV-ready")
                    .font(.title3.weight(.bold))
                Text("Choose a movie, select a mode, and create an MP4.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18))
    }

    private var sourcePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Video").font(.headline)
            if originals.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No videos imported", systemImage: "film.stack")
                        .font(.subheadline.weight(.semibold))
                    Text("Go to Movies to import a video. Then return here to convert it.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .nextSurface()
            } else {
                Menu {
                    ForEach(originals) { movie in
                        Button(movie.name) {
                            selected = movie
                            ready = nil
                            showsAdvanced = false
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(accent)
                            .frame(width: 66, height: 60)
                            .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(selected?.name ?? "Choose a video")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            if let selected {
                                Text("\(selected.format.uppercased()) • \(selected.fileSizeLabel)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let info = details {
                                Text("\(info.width) × \(info.height) • \(info.videoCodec.uppercased())")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 2)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 16))
                }
                .disabled(preparer.preparing)
            }
        }
    }

    private func shortDescription(_ mode: TVVideoMode) -> String {
        switch mode {
        case .remux: return "Copy original tracks, no quality loss"
        case .automatic: return "Keep H.264 video when possible; convert audio to AAC"
        case .gpuH264: return "Encode H.264 with Apple VideoToolbox"
        case .gpuHEVC: return "Encode HEVC with Apple VideoToolbox"
        case .cpuMPEG4: return "Software MPEG-4 Part 2 encoding"
        }
    }

    private func modeIcon(_ mode: TVVideoMode) -> String {
        switch mode {
        case .remux: return "square.on.square"
        case .automatic: return "bolt.fill"
        case .gpuH264, .gpuHEVC: return "cpu"
        case .cpuMPEG4: return "desktopcomputer"
        }
    }

    private func encodingModePanel(_ info: TVSourceDetails) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Conversion Mode").font(.headline)
                Spacer()
                Text("FAST TV RECOMMENDED")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent)
            }
            VStack(spacing: 0) {
                ForEach(TVVideoMode.allCases) { mode in
                    let available = mode != .remux ||
                        info.supportsNoReencoding(audioOrdinal: options.audioOrdinal)
                    Button {
                        options.videoMode = mode
                        if mode == .remux {
                            options.resolution = .source
                            options.frameRate = .source
                        }
                        ready = nil
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: options.videoMode == mode ?
                                  "largecircle.fill.circle" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(options.videoMode == mode ? accent : .secondary)
                            Image(systemName: modeIcon(mode))
                                .font(.system(size: 19))
                                .foregroundStyle(accent)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mode.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(available ? shortDescription(mode) : "Unavailable for this video/audio track")
                                    .font(.caption)
                                    .foregroundStyle(available ? Color.secondary : Color.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            if mode == .automatic {
                                Text("Best for TV")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(accent)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(options.videoMode == mode ?
                                    accent.opacity(0.07) : Color.clear)
                    }
                    .buttonStyle(.plain)
                    .disabled(!available)
                    .opacity(available ? 1 : 0.55)
                    if mode != TVVideoMode.allCases.last {
                        Divider().padding(.leading, 46)
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16))
            Text("Copy mode is available only for compatible MP4 video and AAC audio. Other modes can change quality or take longer.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func outputPanel(_ info: TVSourceDetails) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Output").font(.headline)
            VStack(spacing: 0) {
                outputRow("doc", title: "Format", value: "MP4")
                Divider().padding(.leading, 42)
                outputRow("folder", title: "Save to", value: "Movies / Converted")
                Divider().padding(.leading, 42)
                let codec = options.expectedOutputVideoCodec(info)
                outputRow("film", title: "Video", value: codec.uppercased())
                Divider().padding(.leading, 42)
                outputRow("waveform", title: "Audio", value: options.copiesAudio ? "AAC (copy)" : "AAC stereo")
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func outputRow(_ symbol: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(title).font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(13)
    }

    private func advancedSettings(_ info: TVSourceDetails) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showsAdvanced.toggle() }
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(accent)
                    Text("Advanced Settings")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: showsAdvanced ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            if showsAdvanced {
                Picker("Stream settings", selection: $settingsTab) {
                    Text("Video").tag(0)
                    Text("Audio").tag(1)
                }
                .pickerStyle(.segmented)
                if settingsTab == 0 { videoSettings(info) }
                else { audioSettings(info) }
            }
        }
    }

    private func videoSettings(_ info: TVSourceDetails) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("VIDEO SETTINGS", systemImage: "film").font(.headline)
            HStack {
                Text("Output format")
                Spacer()
                Text("MP4").foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text("Video output codec")
                Spacer()
                Text(options.videoMode == .remux ? info.videoCodec.uppercased() :
                     options.videoMode == .cpuMPEG4 ? "MPEG-4 Part 2" :
                     options.videoMode == .gpuHEVC ? "HEVC (H.265)" : "H.264 / AVC")
                    .foregroundStyle(.secondary)
            }
            Text(options.videoMode == .remux ? "Original video and AAC audio will be copied unchanged." :
                 options.videoMode.summary)
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Picker("Resolution", selection: $options.resolution) {
                ForEach(TVResolution.allCases) { res in
                    Text(res.rawValue).tag(res)
                }
            }.disabled(options.videoMode == .remux)
            Picker("Frame rate", selection: $options.frameRate) {
                ForEach(TVFrameRate.allCases) { rate in
                    Text(rate.rawValue).tag(rate)
                }
            }.disabled(options.videoMode == .remux)
            if requiresEncoding {
                Picker("Video bitrate", selection: $options.videoBitrateKbps) {
                    Text("1,880 kbps").tag(1880)
                    Text("2,500 kbps").tag(2500)
                    Text("4,000 kbps").tag(4000)
                    Text("8,000 kbps").tag(8000)
                }
                HStack {
                    Text("Output pixel format")
                    Spacer()
                    Text("yuv420p").foregroundStyle(.secondary)
                }
            }
            Text("Source duration: \(String(format: "%.0f", info.duration / 60)) min")
                .font(.caption).foregroundStyle(.secondary)
        }.nextSurface()
    }

    private func audioSettings(_ info: TVSourceDetails) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AUDIO SETTINGS", systemImage: "waveform").font(.headline)
            Text("Choose the language/audio stream to keep in your converted TV movie.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Source audio track", selection: $options.audioOrdinal) {
                ForEach(info.audio) { track in
                    Text(track.label).tag(track.id)
                }
            }
            .pickerStyle(.menu)
            Divider()
            HStack {
                Text("Output audio codec")
                Spacer()
                Text(options.copiesAudio ? "AAC (original)" : "AAC-LC")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Channels")
                Spacer()
                Text(options.copiesAudio ? "Original" : "Stereo (2)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Sample rate")
                Spacer()
                Text(options.copiesAudio ? "Original" : "48,000 Hz")
                    .foregroundStyle(.secondary)
            }
            Picker("Audio bitrate", selection: $options.audioBitrateKbps) {
                Text("128 kbps").tag(128)
                Text("192 kbps · Recommended").tag(192)
                Text("256 kbps").tag(256)
            }.disabled(options.copiesAudio)
            Text(options.copiesAudio ?
                 "The selected AAC audio is copied bit-for-bit. Audio bitrate and channel settings do not apply." :
                 "AAC stereo is the preferred default for most Chromecast receivers.")
                .font(.caption).foregroundStyle(.secondary)
        }.nextSurface()
    }

    private var progressPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 80, height: 80)
                    .background(accent.opacity(0.10), in: Circle())
                Text("Converting Video")
                    .font(.title2.bold())
                Text("Keep Next Cast open while your video is processed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .nextSurface()

            if let selected {
                HStack(spacing: 12) {
                    Image(systemName: "film.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(accent)
                        .frame(width: 58, height: 58)
                        .background(accent.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(selected.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Text("Creating TV-ready MP4 • \(selected.fileSizeLabel) source")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .nextSurface()
            }

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("Progress").font(.headline)
                    Spacer()
                    if preparer.hasTimeline {
                        Text(String(format: "%.1f%%", preparer.progressFraction * 100))
                            .font(.headline.monospacedDigit())
                    } else {
                        Text("Preparing…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if preparer.hasTimeline {
                    ProgressView(value: preparer.progressFraction, total: 1)
                        .tint(accent)
                } else {
                    ProgressView().tint(accent)
                }
                Text(preparer.status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Label("\(preparer.elapsedSeconds / 60)m \(preparer.elapsedSeconds % 60)s elapsed",
                          systemImage: "clock")
                    Spacer()
                    if let eta = preparer.estimatedRemainingSeconds {
                        Text("~ \(eta / 60)m \(eta % 60)s left")
                    } else {
                        Text("Estimating…")
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                Text("Processed: \(ByteCountFormatter.string(fromByteCount: preparer.bytesProcessed, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .nextSurface()

            VStack(alignment: .leading, spacing: 12) {
                outputRow("gearshape", title: "Mode", value: options.videoMode.rawValue)
                if let details {
                    outputRow("film", title: "Video",
                              value: options.expectedOutputVideoCodec(details).uppercased())
                }
                outputRow("waveform", title: "Audio",
                          value: options.copiesAudio ? "AAC (copy)" : "AAC stereo")
                outputRow("doc", title: "Output", value: "MP4")
            }
            .nextSurface()

            Button(role: .destructive) { preparer.cancel() } label: {
                Label("Cancel Conversion", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func readyPanel(_ movie: Movie) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(.green)
                Text("Video Ready")
                    .font(.title2.bold())
                Text("Your MP4 has been saved in Movies → Converted.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("\(movie.name) • \(movie.fileSizeLabel)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(3)
            }
            .padding(.vertical, 25)
            .frame(maxWidth: .infinity)
            .nextSurface()

            Button { cast.load(movie) } label: {
                Label("Cast to Connected TV", systemImage: "tv")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(!cast.isConnected)

            ShareLink(item: movie.localURL) {
                Label("Save MP4 to Files", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                ready = nil
                showsAdvanced = false
            } label: {
                Label("Convert Another Video", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Text("HEVC and MPEG-4 Part 2 may not play on all TVs. H.264/AAC is generally the safest Google Cast choice.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func beginConversion() {
        guard let movie = selected, let details else { return }
        if let issue = options.validate(with: details) {
            preparer.errorMessage = issue
            return
        }
        ready = nil
        var preset = options
        preset.useFFmpeg = true
        preparer.prepare(movie, library: library, options: preset) { result in
            ready = result
        }
    }

    private func inspectSelected() {
        guard let movie = selected else {
            details = nil
            return
        }
        inspecting = true
        details = nil
        inspectionError = nil
        let id = movie.id
        TVFFmpegEngine.inspect(movie.localURL) { result in
            guard selected?.id == id else { return }
            inspecting = false
            switch result {
            case .success(let info):
                details = info
                options.audioOrdinal = 0
                options.resolution = .source
                options.frameRate = .source
                options.videoMode = info.supportsNoReencoding(audioOrdinal: 0) ?
                    .remux : .automatic
            case .failure(let error):
                inspectionError = error.localizedDescription
            }
        }
    }
}

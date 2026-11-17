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
    @State private var options = TVConversionOptions()
    @Environment(\.dismiss) private var dismiss

    private var originals: [Movie] { library.movies.filter { !$0.isConverted } }
    private var requiresEncoding: Bool {
        guard let details else { return false }
        return options.requiresVideoEncode(details)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    introduction
                    sourcePanel

                    if let details {
                        encodingModePanel(details)
                        Picker("Stream settings", selection: $settingsTab) {
                            Text("Video Stream").tag(0)
                            Text("Audio Stream").tag(1)
                        }
                        .pickerStyle(.segmented)
                        if settingsTab == 0 { videoSettings(details) }
                        else { audioSettings(details) }
                    } else if inspecting {
                        HStack {
                            ProgressView()
                            Text("Reading source codecs, duration and audio tracks…")
                                .font(.subheadline)
                        }.nextSurface()
                    } else if let inspectionError {
                        Label(inspectionError, systemImage: "exclamationmark.triangle")
                            .font(.subheadline).foregroundStyle(.orange).nextSurface()
                    }

                    Button(action: beginConversion) {
                        Label(preparer.preparing ? "Processing…" :
                              (options.videoMode == .remux ? "Start Fast Remux" : "Start Conversion"),
                              systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline).frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan).foregroundStyle(.black)
                    .disabled(preparer.preparing || selected == nil || details == nil)

                    if preparer.preparing { progressPanel }
                    if let ready { readyPanel(ready) }

                    Text("Your originals stay unchanged. Converted movies are kept permanently in Movies / Converted, and can be cast again without conversion.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(18)
            }
            .navigationTitle("TV Video Converter")
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
            .alert("Video Converter", isPresented: Binding(
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
        VStack(alignment: .leading, spacing: 6) {
            Label("Next Cast · TV-ready MP4", systemImage: "tv.and.mediabox")
                .font(.title3.bold()).foregroundStyle(.cyan)
            Text("Convert MKV, AVI, MOV, MP4 and other FFmpeg-readable videos into H.264 video with stereo AAC sound.")
                .font(.subheadline)
            Text("Choose a real processing preset below. Stream copy is fastest when the original video and AAC audio are compatible. Hardware modes use Apple VideoToolbox, and CPU mode uses FFmpeg's software MPEG-4 encoder.")
                .font(.caption).foregroundStyle(.secondary)
        }.nextSurface()
    }

    private var sourcePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SOURCE VIDEO").font(.caption.bold()).foregroundStyle(.secondary)
            if originals.isEmpty {
                Text("Import a video into Movies to begin.")
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    ForEach(originals) { movie in
                        Button(movie.name) {
                            selected = movie
                            ready = nil
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "film.stack").foregroundStyle(.cyan)
                        Text(selected?.name ?? "Choose movie").lineLimit(2)
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                .disabled(preparer.preparing)
                if let selected {
                    Text("\(selected.format) · \(selected.fileSizeLabel)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let details {
                    Text("Source: \(details.videoCodec.uppercased()) · \(details.width)×\(details.height) · \(String(format: "%.2f", details.fps)) fps · \(details.audio.count) audio track(s)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.nextSurface()
    }


    private func encodingModePanel(_ info: TVSourceDetails) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("ENCODING TYPE", systemImage: "bolt.horizontal.circle")
                    .font(.headline)
                Spacer()
                Text(options.videoMode == .remux ? "FASTEST" : "CUSTOM")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.cyan)
            }
            ForEach(TVVideoMode.allCases) { mode in
                let copyAvailable = info.supportsNoReencoding(audioOrdinal: options.audioOrdinal)
                let available = mode != .remux || copyAvailable
                Button {
                    options.videoMode = mode
                    if mode == .remux {
                        options.resolution = .source
                        options.frameRate = .source
                    }
                    ready = nil
                } label: {
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: options.videoMode == mode ?
                              "checkmark.circle.fill" : "circle")
                            .foregroundStyle(options.videoMode == mode ? .cyan : .secondary)
                            .font(.system(size: 21))
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.rawValue)
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                            Text(mode.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !available {
                                Text("Unavailable for selected source/audio track")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(options.videoMode == mode ? Color.cyan.opacity(0.10) :
                                Color.secondary.opacity(0.055),
                                in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(options.videoMode == mode ? Color.cyan.opacity(0.65) :
                                          Color.secondary.opacity(0.1), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(preparer.preparing || !available)
                .opacity(available ? 1 : 0.55)
            }
            Text("Stream copy preserves the original quality and usually finishes much faster because no frames are decoded or encoded. It cannot change resolution, frame rate, or repair incompatible codecs.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }.nextSurface()
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Preparing TV movie").font(.headline)
                Spacer()
                if preparer.hasTimeline {
                    Text(String(format: "%.1f%%", preparer.progressFraction * 100))
                        .font(.subheadline.monospacedDigit())
                }
            }
            if preparer.hasTimeline {
                ProgressView(value: preparer.progressFraction, total: 1).tint(.cyan)
            } else {
                ProgressView().tint(.cyan)
            }
            Text(preparer.status).font(.subheadline)
            HStack {
                Text("Elapsed: \(preparer.elapsedSeconds / 60)m \(preparer.elapsedSeconds % 60)s")
                Spacer()
                if let eta = preparer.estimatedRemainingSeconds {
                    Text("Est. left: \(eta / 60)m \(eta % 60)s")
                } else {
                    Text("Estimating…")
                }
            }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text("Output processed: \(ByteCountFormatter.string(fromByteCount: preparer.bytesProcessed, countStyle: .file))")
                .font(.caption).foregroundStyle(.secondary)
            Button("Cancel conversion", role: .destructive) { preparer.cancel() }
        }.nextSurface()
    }

    private func readyPanel(_ movie: Movie) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Converted MP4 ready", systemImage: "checkmark.circle.fill")
                .font(.headline).foregroundStyle(.green)
            Text("\(movie.name) · \(movie.fileSizeLabel)")
                .font(.subheadline).lineLimit(2)
            Text("Saved under Movies → Converted. HEVC and CPU MPEG-4 outputs may not play on every TV; H.264/AAC is the recommended casting format.")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                cast.load(movie)
            } label: {
                Label("Cast saved MP4", systemImage: "tv")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!cast.isConnected)
            ShareLink(item: movie.localURL) {
                Label("Export MP4 to Files", systemImage: "square.and.arrow.up")
            }.buttonStyle(.bordered)
        }.nextSurface()
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

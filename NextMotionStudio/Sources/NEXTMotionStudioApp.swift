import SwiftUI
import AVFoundation
import AVKit
import PhotosUI
import UniformTypeIdentifiers

private enum Studio {
    static let tint = Color(red: 0.53, green: 0.34, blue: 0.98)
    static let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let inputs = root.appendingPathComponent("Media", isDirectory: true)
    static let outputs = root.appendingPathComponent("Exports", isDirectory: true)
}

struct MediaClip: Identifiable, Hashable {
    let id: String
    let url: URL
    let duration: Double
    let width: Int
    let height: Int
    let bytes: Int64
    var title: String { url.deletingPathExtension().lastPathComponent }
    var detail: String {
        let durationText = String(format: "%02d:%02d", Int(duration)/60, Int(duration)%60)
        return "\(width)×\(height) · \(durationText) · " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

@MainActor final class StudioLibrary: ObservableObject {
    @Published var clips: [MediaClip] = []
    @Published var exports: [URL] = []
    @Published var error: String?
    @Published var importing = false

    init() {
        try? FileManager.default.createDirectory(at: Studio.inputs, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: Studio.outputs, withIntermediateDirectories: true)
        Task { await reload() }
    }
    func reload() async {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Studio.inputs, includingPropertiesForKeys: nil)) ?? []
        var result: [MediaClip] = []
        for url in urls {
            if let info = try? await inspect(url: url) { result.append(info) }
        }
        clips = result.sorted { $0.url.lastPathComponent > $1.url.lastPathComponent }
        exports = ((try? FileManager.default.contentsOfDirectory(at: Studio.outputs, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
    func importVideo(_ url: URL) async {
        importing = true
        defer { importing = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension.lowercased()
        let destination = Studio.inputs.appendingPathComponent(UUID().uuidString + "." + ext)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            guard let clip = try? await inspect(url: destination) else {
                try? FileManager.default.removeItem(at: destination)
                error = "This video cannot be decoded by iOS."
                return
            }
            clips.insert(clip, at: 0)
        } catch {
            self.error = error.localizedDescription
        }
    }
    func registerExport(_ url: URL) { exports.insert(url, at: 0) }
    func removeClip(_ clip: MediaClip) {
        try? FileManager.default.removeItem(at: clip.url)
        clips.removeAll { $0.id == clip.id }
    }
    func removeExport(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        exports.removeAll { $0 == url }
    }
    private func inspect(url: URL) async throws -> MediaClip {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw StudioFailure.noVideo }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let frame = CGRect(origin: .zero, size: size).applying(transform).standardized
        let bytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return MediaClip(id: url.lastPathComponent, url: url, duration: max(0, CMTimeGetSeconds(duration)),
                         width: Int(abs(frame.width)), height: Int(abs(frame.height)), bytes: bytes)
    }
}

struct PickedVideo: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            try FileManager.default.copyItem(at: received.file, to: url)
            return PickedVideo(url: url)
        }
    }
}

struct ImportToolbar: View {
    @EnvironmentObject var library: StudioLibrary
    @State private var photoItem: PhotosPickerItem?
    @State private var filePicker = false
    var body: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $photoItem, matching: .videos) {
                Label("Import Photos", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent)
            Button { filePicker = true } label: {
                Label("Import Files", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)
        }
        .controlSize(.large)
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task {
                do {
                    if let video = try await item.loadTransferable(type: PickedVideo.self) {
                        await library.importVideo(video.url)
                        try? FileManager.default.removeItem(at: video.url)
                    } else {
                        library.error = "Could not import this Photos video."
                    }
                } catch { library.error = error.localizedDescription }
                photoItem = nil
            }
        }
        .fileImporter(isPresented: $filePicker, allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task { for url in urls { await library.importVideo(url) } }
            case .failure(let err): library.error = err.localizedDescription
            }
        }
    }
}

enum StudioFailure: LocalizedError {
    case noVideo, noEncoder, incompatibleContainer, invalidTrim, cancelled, failed(String)
    var errorDescription: String? {
        switch self {
        case .noVideo: return "Video track unavailable."
        case .noEncoder: return "This device cannot encode the selected format."
        case .incompatibleContainer: return "Selected file container is unsupported for this codec."
        case .invalidTrim: return "Invalid trimming range."
        case .cancelled: return "Export cancelled."
        case .failed(let reason): return "Export failed: " + reason
        }
    }
}

enum OutputContainer: String, CaseIterable { case mp4 = "MP4", mov = "MOV"
    var fileType: AVFileType { self == .mp4 ? .mp4 : .mov }
    var ext: String { rawValue.lowercased() }
}
enum OutputCodec: String, CaseIterable { case h264 = "H.264", hevc = "HEVC"
    var preset: String { self == .hevc ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality }
}
enum OutputSize: String, CaseIterable {
    case original = "Original", p480 = "480p", p720 = "720p", p1080 = "1080p", p1440 = "1440p", p2160 = "4K"
    var edge: Int? {
        switch self {
        case .original: return nil
        case .p480: return 480
        case .p720: return 720
        case .p1080: return 1080
        case .p1440: return 1440
        case .p2160: return 2160
        }
    }
}
enum OutputQuality: String, CaseIterable { case compact = "Smaller", balanced = "Balanced", high = "Highest"
    var preset: String {
        switch self {
        case .compact: return AVAssetExportPresetLowQuality
        case .balanced: return AVAssetExportPresetMediumQuality
        case .high: return AVAssetExportPresetHighestQuality
        }
    }
}
struct RenderOptions {
    var format: OutputContainer = .mp4
    var codec: OutputCodec = .h264
    var resolution: OutputSize = .p1080
    var quality: OutputQuality = .high
    var fps = 30
    var trimStart = 0.0
    var trimEnd: Double? = nil
    var mute = false
}

@MainActor final class RenderJob: ObservableObject {
    @Published var processing = false
    @Published var progress: Float = 0
    @Published var error: String?
    @Published var result: URL?
    private var session: AVAssetExportSession?
    private var poll: Timer?

    func cancel() { session?.cancelExport() }

    func run(_ clip: MediaClip, settings: RenderOptions, library: StudioLibrary) {
        guard !processing else { return }
        processing = true
        error = nil
        result = nil
        progress = 0
        Task {
            do {
                let output = try await export(clip, settings: settings)
                library.registerExport(output)
                result = output
                progress = 1
            } catch {
                self.error = error.localizedDescription
            }
            poll?.invalidate()
            poll = nil
            session = nil
            processing = false
        }
    }

    func extractAudio(_ clip: MediaClip, library: StudioLibrary) {
        guard !processing else { return }
        processing = true
        progress = 0
        error = nil
        result = nil
        Task {
            do {
                let asset = AVURLAsset(url: clip.url)
                guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else { throw StudioFailure.failed("No audio track") }
                guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw StudioFailure.noEncoder }
                let output = Studio.outputs.appendingPathComponent(UUID().uuidString + ".m4a")
                export.outputURL = output
                export.outputFileType = .m4a
                session = export
                poll = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self, weak export] _ in
                    Task { @MainActor in self?.progress = export?.progress ?? 0 }
                }
                try await execute(export)
                library.registerExport(output)
                result = output
            } catch { self.error = error.localizedDescription }
            poll?.invalidate()
            poll = nil
            session = nil
            processing = false
        }
    }

    private func execute(_ export: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            export.exportAsynchronously {
                switch export.status {
                case .completed: continuation.resume(returning: ())
                case .cancelled: continuation.resume(throwing: StudioFailure.cancelled)
                default: continuation.resume(throwing: StudioFailure.failed(export.error?.localizedDescription ?? "Unknown encoder error"))
                }
            }
        }
    }

    private func export(_ clip: MediaClip, settings: RenderOptions) async throws -> URL {
        let asset = AVURLAsset(url: clip.url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let video = tracks.first else { throw StudioFailure.noVideo }
        let start = max(0, min(settings.trimStart, clip.duration))
        let end = min(clip.duration, settings.trimEnd ?? clip.duration)
        guard end - start > 0.05 else { throw StudioFailure.invalidTrim }
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                duration: CMTime(seconds: end-start, preferredTimescale: 600))
        let composition = AVMutableComposition()
        guard let cVideo = composition.addMutableTrack(withMediaType: .video,
                                                       preferredTrackID: kCMPersistentTrackID_Invalid) else { throw StudioFailure.noVideo }
        try cVideo.insertTimeRange(range, of: video, at: .zero)
        let transform = try await video.load(.preferredTransform)
        let natural = try await video.load(.naturalSize)
        cVideo.preferredTransform = transform
        if !settings.mute, let audio = try await asset.loadTracks(withMediaType: .audio).first {
            let cAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try cAudio?.insertTimeRange(range, of: audio, at: .zero)
        }

        let preset: String = settings.codec == .hevc ? settings.codec.preset : settings.quality.preset
        guard let exporter = AVAssetExportSession(asset: composition, presetName: preset) else { throw StudioFailure.noEncoder }
        guard exporter.supportedFileTypes.contains(settings.format.fileType) else { throw StudioFailure.incompatibleContainer }
        let rect = CGRect(origin: .zero, size: natural).applying(transform).standardized
        let srcW = max(2, abs(rect.width)), srcH = max(2, abs(rect.height))
        let sourceShort = min(srcW, srcH)
        let scale = CGFloat(settings.resolution.edge ?? Int(sourceShort)) / sourceShort
        let w = max(2, (Int(srcW * scale) / 2) * 2)
        let h = max(2, (Int(srcH * scale) / 2) * 2)
        let normalized = transform.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            .concatenating(CGAffineTransform(scaleX: CGFloat(w)/srcW, y: CGFloat(h)/srcH))
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: cVideo)
        layer.setTransform(normalized, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        instruction.layerInstructions = [layer]
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(settings.fps))
        videoComposition.renderSize = CGSize(width: w, height: h)
        videoComposition.instructions = [instruction]
        exporter.videoComposition = videoComposition

        let output = Studio.outputs.appendingPathComponent(UUID().uuidString + "." + settings.format.ext)
        exporter.outputURL = output
        exporter.outputFileType = settings.format.fileType
        exporter.shouldOptimizeForNetworkUse = true
        session = exporter
        poll = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self, weak exporter] _ in
            Task { @MainActor in self?.progress = exporter?.progress ?? 0 }
        }
        do {
            try await execute(exporter)
            guard FileManager.default.fileExists(atPath: output.path) else { throw StudioFailure.failed("No output file") }
            return output
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
}

struct VideoPreview: View {
    let url: URL
    @State private var player = AVPlayer()
    var body: some View {
        VideoPlayer(player: player)
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .onAppear { player.replaceCurrentItem(with: AVPlayerItem(url: url)) }
            .onChange(of: url) { newURL in player.pause(); player.replaceCurrentItem(with: AVPlayerItem(url: newURL)) }
            .onDisappear { player.pause() }
    }
}

struct StudioCard<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline).foregroundStyle(Studio.tint)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct ExportFeedback: View {
    @ObservedObject var job: RenderJob
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if job.processing {
                ProgressView(value: job.progress)
                HStack {
                    Text("Encoding on device")
                    Spacer()
                    Text("\(Int(job.progress * 100))%")
                }.font(.caption)
                Button("Cancel Export", role: .destructive) { job.cancel() }
            }
            if let error = job.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red)
            }
            if let result = job.result {
                Label("Export completed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                ShareLink(item: result) {
                    Label("Share or Save Video", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
            }
        }
    }
}

struct ChooseClip: View {
    @EnvironmentObject var library: StudioLibrary
    @Binding var selection: String?
    var body: some View {
        if library.clips.isEmpty {
            Text("Import your first video from Photos or Files.").foregroundStyle(.secondary)
        } else {
            Picker("Video", selection: $selection) {
                Text("Select video").tag(String?.none)
                ForEach(library.clips) { clip in Text(clip.title).tag(Optional(clip.id)) }
            }
            .pickerStyle(.menu)
            .onAppear { if selection == nil { selection = library.clips.first?.id } }
            .onChange(of: library.clips.count) { _ in
                if selection == nil { selection = library.clips.first?.id }
            }
        }
    }
}

struct ConvertScreen: View {
    @EnvironmentObject var library: StudioLibrary
    @StateObject var job = RenderJob()
    @State private var selection: String?
    @State private var format = OutputContainer.mp4
    @State private var codec = OutputCodec.h264
    @State private var resolution = OutputSize.p1080
    @State private var quality = OutputQuality.high
    @State private var fps = 30
    @State private var mute = false
    private var clip: MediaClip? { library.clips.first { $0.id == selection } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("CONVERSION STUDIO").font(.caption.bold()).tracking(2).foregroundStyle(Studio.tint)
                Text("Convert Video").font(.largeTitle.bold())
                StudioCard("Media") { ChooseClip(selection: $selection); ImportToolbar() }
                if let clip {
                    VideoPreview(url: clip.url)
                    Text(clip.detail).font(.caption).foregroundStyle(.secondary)
                    StudioCard("Format") {
                        Picker("Container", selection: $format) { ForEach(OutputContainer.allCases, id: \.self) { Text($0.rawValue) } }
                        Picker("Codec", selection: $codec) { ForEach(OutputCodec.allCases, id: \.self) { Text($0.rawValue) } }
                    }
                    StudioCard("Picture & Compression") {
                        Picker("Resolution", selection: $resolution) { ForEach(OutputSize.allCases, id: \.self) { Text($0.rawValue) } }
                        Picker("Quality", selection: $quality) { ForEach(OutputQuality.allCases, id: \.self) { Text($0.rawValue) } }
                        Picker("Frame rate", selection: $fps) {
                            ForEach([24,30,60], id: \.self) { Text("\($0) FPS").tag($0) }
                        }
                        Toggle("Remove sound", isOn: $mute)
                        if codec == .hevc { Text("HEVC currently uses its highest-quality Apple export preset. Quality preset is ignored for HEVC.").font(.caption).foregroundStyle(.secondary) }
                    }
                    StudioCard("Export") {
                        Button {
                            var options = RenderOptions()
                            options.format = format; options.codec = codec
                            options.resolution = resolution; options.quality = quality
                            options.fps = fps; options.mute = mute
                            job.run(clip, settings: options, library: library)
                        } label: { Label("Convert Video", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(job.processing)
                        Button {
                            job.extractAudio(clip, library: library)
                        } label: { Label("Extract Audio (M4A)", systemImage: "waveform").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).disabled(job.processing)
                        ExportFeedback(job: job)
                    }
                }
            }.padding()
        }.navigationTitle("Converter")
    }
}

struct EditorScreen: View {
    @EnvironmentObject var library: StudioLibrary
    @StateObject var job = RenderJob()
    @State private var selection: String?
    @State private var start = 0.0
    @State private var end = 0.0
    @State private var mute = false
    private var clip: MediaClip? { library.clips.first { $0.id == selection } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("EDITOR").font(.caption.bold()).tracking(2).foregroundStyle(Studio.tint)
                Text("Trim & Export").font(.largeTitle.bold())
                StudioCard("Video") { ChooseClip(selection: $selection); ImportToolbar() }
                if let clip {
                    VideoPreview(url: clip.url)
                    StudioCard("Trim range") {
                        HStack { Text("Start"); Spacer(); Text("\(start, specifier: "%.1f") s") }
                        Slider(value: $start, in: 0...max(0.01, end - 0.1))
                        HStack { Text("End"); Spacer(); Text("\(end, specifier: "%.1f") s") }
                        Slider(value: $end, in: min(clip.duration, start+0.1)...max(clip.duration, start+0.1))
                        Button("Reset") { start = 0; end = clip.duration }
                        Toggle("Remove original audio", isOn: $mute)
                    }
                    StudioCard("Render") {
                        Button {
                            var options = RenderOptions()
                            options.trimStart = start
                            options.trimEnd = end
                            options.mute = mute
                            job.run(clip, settings: options, library: library)
                        } label: { Label("Export Edited Video", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(job.processing || end-start < 0.1)
                        ExportFeedback(job: job)
                    }
                }
            }.padding()
        }
        .navigationTitle("Editor")
        .onChange(of: selection) { _ in start = 0; end = clip?.duration ?? 0 }
        .onAppear { if selection == nil { selection = library.clips.first?.id }; end = clip?.duration ?? 0 }
    }
}

struct HomeScreen: View {
    @EnvironmentObject var library: StudioLibrary
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("NEXT / VIDEO LAB").font(.caption.bold()).tracking(2).foregroundStyle(Studio.tint)
                Text("Motion Studio").font(.largeTitle.bold())
                Text("Your video editing and conversion workspace").foregroundStyle(.secondary)
                StudioCard("Quick start") { ImportToolbar() }
                StudioCard("Workspace") {
                    Label("Format conversion · MP4 / MOV", systemImage: "arrow.left.arrow.right")
                    Label("Native video trimming", systemImage: "scissors")
                    Label("Resize, quality & frame rate", systemImage: "slider.horizontal.3")
                    Label("Extract audio to M4A", systemImage: "waveform")
                }
                HStack {
                    StudioCard("Imported videos") { Text("\(library.clips.count)").font(.largeTitle.bold()) }
                    StudioCard("Completed exports") { Text("\(library.exports.count)").font(.largeTitle.bold()) }
                }
            }.padding()
        }.navigationTitle("Home")
    }
}

struct LibraryScreen: View {
    @EnvironmentObject var library: StudioLibrary
    var body: some View {
        List {
            Section("Imported videos") {
                ForEach(library.clips) { clip in
                    HStack {
                        Image(systemName: "film").foregroundStyle(Studio.tint)
                        VStack(alignment: .leading) {
                            Text(clip.title).lineLimit(1)
                            Text(clip.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.onDelete { indexes in
                    for index in indexes { library.removeClip(library.clips[index]) }
                }
                if library.clips.isEmpty { Text("No imported videos yet").foregroundStyle(.secondary) }
            }
            Section("Exports") {
                ForEach(library.exports, id: \.self) { url in
                    ShareLink(item: url) {
                        Label(url.lastPathComponent, systemImage: "square.and.arrow.up")
                    }
                }.onDelete { indexes in
                    for index in indexes { library.removeExport(library.exports[index]) }
                }
                if library.exports.isEmpty { Text("No exports yet").foregroundStyle(.secondary) }
            }
        }.navigationTitle("Library").toolbar { EditButton() }
    }
}

struct SettingsScreen: View {
    @AppStorage("motion.appearance") private var appearance = "System"
    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(["System","Light","Dark"], id: \.self) { Text($0) }
                }
            }
            Section("About") {
                LabeledContent("App", value: "NEXT Motion Studio")
                LabeledContent("Version", value: "0.1.0 · Build 1")
                LabeledContent("Minimum iOS", value: "16.0")
                Text("First test: conversion, trim, resolution, compression presets, audio extraction. More editing features will follow.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Settings")
    }
}

struct RootStudioView: View {
    @EnvironmentObject var library: StudioLibrary
    @AppStorage("motion.appearance") private var appearance = "System"
    var colorScheme: ColorScheme? { appearance == "Dark" ? .dark : (appearance == "Light" ? .light : nil) }
    var body: some View {
        TabView {
            NavigationStack { HomeScreen() }.tabItem { Label("Home", systemImage: "house") }
            NavigationStack { EditorScreen() }.tabItem { Label("Editor", systemImage: "slider.horizontal.3") }
            NavigationStack { ConvertScreen() }.tabItem { Label("Convert", systemImage: "arrow.left.arrow.right") }
            NavigationStack { LibraryScreen() }.tabItem { Label("Library", systemImage: "square.stack") }
            NavigationStack { SettingsScreen() }.tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Studio.tint)
        .preferredColorScheme(colorScheme)
        .alert("Media Error", isPresented: Binding(
            get: { library.error != nil },
            set: { if !$0 { library.error = nil } }
        )) {
            Button("OK", role: .cancel) { library.error = nil }
        } message: { Text(library.error ?? "") }
    }
}

@main struct NEXTMotionStudioApp: App {
    @StateObject private var library = StudioLibrary()
    var body: some Scene {
        WindowGroup { RootStudioView().environmentObject(library) }
    }
}
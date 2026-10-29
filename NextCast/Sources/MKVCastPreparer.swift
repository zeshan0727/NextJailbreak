import Foundation
import Combine
import AVFoundation
import AudioToolbox
import CoreMedia

// 1.4.5: The previous embedded FFmpeg CLI crashed with SIGBUS in
// av_format_init_next on iOS 16. This module deliberately never calls it.
// MP4/MOV processing uses Apple's system encoders and muxer instead.
private enum NativeCastCompatibility {
    static let containers: Set<String> = ["mp4", "m4v", "mov"]

    static func h264Track(_ asset: AVURLAsset) -> AVAssetTrack? {
        guard let video = asset.tracks(withMediaType: .video).first,
              let raw = video.formatDescriptions.first else { return nil }
        let description = raw as! CMFormatDescription
        guard CMFormatDescriptionGetMediaSubType(description) == kCMVideoCodecType_H264 else { return nil }
        return video
    }

    static func directPlayable(_ url: URL) -> Bool {
        guard ["mp4", "m4v"].contains(url.pathExtension.lowercased()) else { return false }
        let asset = AVURLAsset(url: url)
        guard h264Track(asset) != nil,
              let audio = asset.tracks(withMediaType: .audio).first,
              let raw = audio.formatDescriptions.first else { return false }
        let description = raw as! CMFormatDescription
        let codec = CMFormatDescriptionGetMediaSubType(description)
        let channels = CMAudioFormatDescriptionGetStreamBasicDescription(description)?
            .pointee.mChannelsPerFrame ?? 0
        return codec == kAudioFormatMPEG4AAC && channels >= 1 && channels <= 2
    }
}

/// NSLock-backed cancellation can be checked from the conversion worker
/// without accessing the SwiftUI main actor or blocking the UI thread.
private final class ConversionStopToken {
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

private enum NativeAudioMuxer {
    static func error(_ message: String) -> NSError {
        NSError(domain: "NextCast.NativeConverter", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func convert(source: URL, output: URL, token: ConversionStopToken) throws {
        guard NativeCastCompatibility.containers.contains(source.pathExtension.lowercased()) else {
            throw error("Native TV conversion supports MP4, M4V and MOV. MKV remains playable in VLC on your iPhone, but its unstable FFmpeg converter has been disabled to prevent the iOS 16 crash.")
        }
        let asset = AVURLAsset(url: source)
        guard let videoTrack = NativeCastCompatibility.h264Track(asset) else {
            throw error("Fast TV conversion requires an H.264 video track readable by iOS. This video needs a separate full video transcode.")
        }
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            throw error("The source has no audio track. A silent video cannot gain sound through conversion.")
        }
        guard let rawFormat = videoTrack.formatDescriptions.first else {
            throw error("The H.264 video format could not be inspected.")
        }
        let formatHint = rawFormat as! CMFormatDescription

        // Compressed H.264 is copied, not decoded or re-encoded.
        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw error("Cannot read the H.264 video stream.") }
        reader.add(videoOutput)

        // Decode source AC3/E-AC3/AAC/etc through the system codec, downmix
        // to stereo PCM, then encode AAC-LC 192 kb/s into the MP4.
        let pcm: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: pcm)
        audioOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(audioOutput) else {
            throw error("The system cannot decode this audio track. The original video is unchanged.")
        }
        reader.add(audioOutput)

        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        // MP4 requires a source format hint for H.264 passthrough.
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil,
                                             sourceFormatHint: formatHint)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = videoTrack.preferredTransform
        guard writer.canAdd(videoInput) else { throw error("MP4 does not accept this H.264 video stream.") }
        writer.add(videoInput)

        let aac: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192000
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: aac)
        audioInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(audioInput) else { throw error("AAC encoder is unavailable on this device.") }
        writer.add(audioInput)

        if token.isCancelled { throw error("Cancelled.") }
        guard writer.startWriting() else {
            throw writer.error ?? error("Unable to start MP4 writer.")
        }
        guard reader.startReading() else {
            writer.cancelWriting()
            throw reader.error ?? error("Unable to read this video or audio codec.")
        }
        writer.startSession(atSourceTime: .zero)

        var videoFinished = false
        var audioFinished = false
        // Pump both tracks on one worker. Keep packets small and memory bounded.
        // Never block the main thread or invoke the crashing FFmpeg registry.
        while !videoFinished || !audioFinished {
            if token.isCancelled {
                reader.cancelReading()
                writer.cancelWriting()
                throw error("Cancelled.")
            }
            if writer.status == .failed || reader.status == .failed {
                let failure = writer.error ?? reader.error
                writer.cancelWriting()
                throw failure ?? error("Native media conversion failed.")
            }
            var madeProgress = false
            if !videoFinished && videoInput.isReadyForMoreMediaData {
                if let sample = videoOutput.copyNextSampleBuffer() {
                    guard videoInput.append(sample) else {
                        reader.cancelReading()
                        writer.cancelWriting()
                        throw writer.error ?? error("Unable to write H.264 video.")
                    }
                } else {
                    videoInput.markAsFinished()
                    videoFinished = true
                }
                madeProgress = true
            }
            if !audioFinished && audioInput.isReadyForMoreMediaData {
                if let sample = audioOutput.copyNextSampleBuffer() {
                    guard audioInput.append(sample) else {
                        reader.cancelReading()
                        writer.cancelWriting()
                        throw writer.error ?? error("Unable to write AAC audio.")
                    }
                } else {
                    audioInput.markAsFinished()
                    audioFinished = true
                }
                madeProgress = true
            }
            if !madeProgress { Thread.sleep(forTimeInterval: 0.01) }
        }
        if reader.status == .failed {
            writer.cancelWriting()
            throw reader.error ?? error("The audio decoder failed.")
        }
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        if token.isCancelled { throw error("Cancelled.") }
        guard writer.status == .completed else {
            throw writer.error ?? error("MP4 writer did not finish successfully.")
        }
    }
}

@MainActor
final class MKVCastPreparer: ObservableObject {
    @Published private(set) var preparing = false
    @Published private(set) var status = ""
    @Published private(set) var bytesWritten: Int64 = 0
    @Published private(set) var elapsedSeconds = 0
    @Published var errorMessage: String?

    private static let conversionQueue = DispatchQueue(
        label: "uk.zeshanbarvi.nextcast.nativeconversion", qos: .userInitiated)
    private var stopToken: ConversionStopToken?
    private var monitor: Timer?

    func prepare(_ movie: Movie, forceConversion: Bool = false,
                 completion: @escaping (Movie) -> Void) {
        guard !preparing else { return }
        errorMessage = nil
        status = "Checking iOS native codec support…"
        preparing = true
        bytesWritten = 0
        elapsedSeconds = 0
        let source = movie.localURL
        let folder = MovieLibrary.folder
        // Different cache key from 1.4.3/1.4.4's potentially bad FFmpeg output.
        let finalURL = folder.appendingPathComponent(movie.id.uuidString + ".native.cast.mp4")
        let temporaryURL = folder.appendingPathComponent(movie.id.uuidString + ".nativebuilding.mp4")
        let token = ConversionStopToken()
        stopToken = token
        let started = Date()
        monitor?.invalidate()
        monitor = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.elapsedSeconds = Int(Date().timeIntervalSince(started))
                self.bytesWritten = ((try? FileManager.default.attributesOfItem(
                    atPath: temporaryURL.path)[.size]) as? NSNumber)?.int64Value ?? 0
            }
        }
        Self.conversionQueue.async { [weak self] in
            func prepared(_ url: URL) -> Movie {
                let bytes = ((try? FileManager.default.attributesOfItem(
                    atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
                return Movie(id: movie.id, name: movie.name, fileName: url.lastPathComponent,
                             importedAt: movie.importedAt, fileSize: bytes)
            }
            func finish(_ movie: Movie?, _ issue: String?, _ success: String) {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.monitor?.invalidate()
                    self.monitor = nil
                    self.preparing = false
                    self.stopToken = nil
                    if token.isCancelled {
                        self.status = "Conversion cancelled"
                        try? FileManager.default.removeItem(at: temporaryURL)
                    } else if let issue {
                        self.status = "Cannot convert this file"
                        self.errorMessage = issue
                    } else if let movie {
                        self.status = success
                        completion(movie)
                    }
                }
            }
            guard FileManager.default.fileExists(atPath: source.path) else {
                finish(nil, "Video file is no longer available.", "")
                return
            }
            guard NativeCastCompatibility.containers.contains(source.pathExtension.lowercased()) else {
                finish(nil, "For safety, the crashing FFmpeg converter has been disabled. Convert MKV/AVI to MP4 H.264 in another app, then import it here. Native conversion currently supports MP4, M4V and MOV.", "")
                return
            }
            if !forceConversion && NativeCastCompatibility.directPlayable(source) {
                finish(movie, nil, "Already compatible H.264 video + stereo AAC sound")
                return
            }
            if let attr = try? FileManager.default.attributesOfItem(atPath: finalURL.path),
               (attr[.size] as? NSNumber)?.int64Value ?? 0 > 4096,
               NativeCastCompatibility.directPlayable(finalURL) {
                finish(prepared(finalURL), nil, "Using previously prepared native TV MP4")
                return
            }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let required = max(movie.fileSize, 128 * 1024 * 1024) + 128 * 1024 * 1024
                if let available = try folder.resourceValues(
                    forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity,
                   Int64(available) < required {
                    finish(nil, "Not enough free space for a second MP4. Free at least " +
                        ByteCountFormatter.string(fromByteCount: required, countStyle: .file) +
                        ". Your original is not modified.", "")
                    return
                }
                if FileManager.default.fileExists(atPath: temporaryURL.path) {
                    try FileManager.default.removeItem(at: temporaryURL)
                }
                DispatchQueue.main.async { [weak self] in
                    self?.status = "Native fast copy · H.264 untouched · AAC stereo audio"
                }
                try NativeAudioMuxer.convert(source: source, output: temporaryURL, token: token)
                if token.isCancelled {
                    try? FileManager.default.removeItem(at: temporaryURL)
                    finish(nil, "Cancelled.", "")
                    return
                }
                let size = ((try? FileManager.default.attributesOfItem(
                    atPath: temporaryURL.path)[.size]) as? NSNumber)?.int64Value ?? 0
                guard size > 4096, NativeCastCompatibility.directPlayable(temporaryURL) else {
                    throw NativeAudioMuxer.error("The output failed MP4/H.264/AAC verification.")
                }
                if FileManager.default.fileExists(atPath: finalURL.path) {
                    try FileManager.default.removeItem(at: finalURL)
                }
                try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
                finish(prepared(finalURL), nil, "Native MP4 with TV-compatible stereo AAC ready")
            } catch {
                try? FileManager.default.removeItem(at: temporaryURL)
                finish(nil, "Native conversion: \(error.localizedDescription)", "")
            }
        }
    }

    func cancel() {
        guard preparing else { return }
        stopToken?.cancel()
        status = "Stopping native conversion…"
    }

    deinit { monitor?.invalidate() }
}

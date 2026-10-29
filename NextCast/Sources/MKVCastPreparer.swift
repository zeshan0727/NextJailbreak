import Foundation
import Combine
import AVFoundation
import AudioToolbox
import FFmpegSupport

/// Inspects the *contained audio codec*, not merely the filename extension.
/// AAC-LC stereo in MP4 is the conservative default for Cast receivers.
private enum CastAudioCompatibility {
    static func canCastDirectly(_ url: URL) -> Bool {
        guard ["mp4", "m4v"].contains(url.pathExtension.lowercased()) else { return false }
        let asset = AVURLAsset(url: url)
        guard let audio = asset.tracks(withMediaType: .audio).first,
              let rawDescription = audio.formatDescriptions.first else {
            return false
        }
        // AVFoundation exposes an array of Any here. Track format descriptions
        // are CoreMedia CMFormatDescription objects; a conditional CF downcast
        // is rejected by the Swift compiler, whereas an explicit bridge is valid.
        let description = rawDescription as! CMFormatDescription
        let codec = CMFormatDescriptionGetMediaSubType(description)
        let channels = CMAudioFormatDescriptionGetStreamBasicDescription(description)?
            .pointee.mChannelsPerFrame ?? 0
        return codec == kAudioFormatMPEG4AAC && channels > 0 && channels <= 2
    }
}

/// Shared fast path for imported MP4, MKV and other video files.
/// Never touches the original. Copies the video packets and encodes AAC-LC
/// stereo audio only; a video requiring H.264 re-encoding is NOT silently
/// claimed compatible. All embedded FFmpeg CLI calls are serialized.
@MainActor
final class MKVCastPreparer: ObservableObject {
    @Published private(set) var preparing = false
    @Published private(set) var status = ""
    @Published private(set) var bytesWritten: Int64 = 0
    @Published private(set) var elapsedSeconds = 0
    @Published var errorMessage: String?
    private static let conversionQueue = DispatchQueue(label: "uk.zeshanbarvi.nextcast.ffmpeg.serial", qos: .userInitiated)
    private var cancelRequested = false
    private var monitor: Timer?

    func prepare(_ movie: Movie, forceConversion: Bool = false,
                 completion: @escaping (Movie) -> Void) {
        guard !preparing else { return }
        errorMessage = nil
        preparing = true
        cancelRequested = false
        bytesWritten = 0
        elapsedSeconds = 0
        status = "Checking TV audio compatibility…"
        let folder = MovieLibrary.folder
        let finalURL = folder.appendingPathComponent(movie.id.uuidString + ".cast.mp4")
        let temporaryURL = folder.appendingPathComponent(movie.id.uuidString + ".castbuilding.mp4")
        let original = movie.localURL
        let started = Date()
        monitor?.invalidate()
        monitor = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.elapsedSeconds = Int(Date().timeIntervalSince(started))
                self.bytesWritten = ((try? FileManager.default.attributesOfItem(atPath: temporaryURL.path)[.size])
                    as? NSNumber)?.int64Value ?? 0
            }
        }
        Self.conversionQueue.async { [weak self] in
            func preparedMovie(_ file: URL) -> Movie {
                let bytes = ((try? FileManager.default.attributesOfItem(atPath: file.path)[.size])
                    as? NSNumber)?.int64Value ?? 0
                return Movie(id: movie.id, name: movie.name,
                             fileName: file.lastPathComponent,
                             importedAt: movie.importedAt, fileSize: bytes)
            }
            func finish(_ output: Movie?, _ error: String?, _ message: String) {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.monitor?.invalidate()
                    self.monitor = nil
                    self.preparing = false
                    if self.cancelRequested {
                        self.status = "Preparation cancelled"
                        try? FileManager.default.removeItem(at: temporaryURL)
                    } else if let error {
                        self.status = "Preparation failed"
                        self.errorMessage = error
                    } else if let output {
                        self.status = message
                        completion(output)
                    }
                }
            }
            guard FileManager.default.fileExists(atPath: original.path) else {
                finish(nil, "Source video is no longer available.", "")
                return
            }
            // Fastest path: already-playable H.264/AAC-style MP4 with AAC stereo.
            // This check is deliberately restricted to known AAC stereo MP4 files.
            if !forceConversion && CastAudioCompatibility.canCastDirectly(original) {
                finish(movie, nil, "MP4 contains compatible stereo AAC · no conversion needed")
                return
            }
            // Reuse a verified finished output. Never recode a 5+ GB movie twice.
            if let attrs = try? FileManager.default.attributesOfItem(atPath: finalURL.path),
               (attrs[.size] as? NSNumber)?.int64Value ?? 0 > 4096 {
                finish(preparedMovie(finalURL), nil, "Using previously prepared TV MP4")
                return
            }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let required = max(movie.fileSize, 256 * 1024 * 1024) + 256 * 1024 * 1024
                if let available = try folder.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity,
                   Int64(available) < required {
                    finish(nil, "Not enough free storage. Allow approximately " +
                        ByteCountFormatter.string(fromByteCount: required, countStyle: .file) +
                        " for a separate MP4. Your original is preserved.", "")
                    return
                }
                if FileManager.default.fileExists(atPath: temporaryURL.path) {
                    try FileManager.default.removeItem(at: temporaryURL)
                }
            } catch {
                finish(nil, "Cannot prepare output: \(error.localizedDescription)", "")
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.status = "Fast conversion: copying video · AAC stereo audio"
            }
            // Video stream copy is typically dramatically faster than transcoding.
            // -map 0:a:0 makes a silent source a clear error, not a silent TV MP4.
            // The output is generated on-device; no uploading or extra download.
            let args = [
                "ffmpeg", "-hide_banner", "-nostdin", "-loglevel", "error", "-y",
                "-i", original.path, "-map", "0:v:0", "-map", "0:a:0",
                "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
                "-ac", "2", "-ar", "48000", "-threads", "0",
                "-sn", "-dn", "-max_muxing_queue_size", "1024",
                "-movflags", "+faststart", temporaryURL.path
            ]
            let code = ffmpeg(args)
            if code != 0 {
                try? FileManager.default.removeItem(at: temporaryURL)
                finish(nil, "Conversion failed (FFmpeg exit \(code)). The video track may not be MP4-compatible, or the file may lack an audio track. Video re-encoding is not part of Fast Copy mode.", "")
                return
            }
            do {
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: temporaryURL.path),
                      (attrs[.size] as? NSNumber)?.int64Value ?? 0 > 4096 else {
                    throw NSError(domain: "NextCast.Converter", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Output file was empty."])
                }
                // Only publish a fully completed MP4, never an unfinished temp file.
                try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
                finish(preparedMovie(finalURL), nil, "TV-ready MP4 with stereo AAC sound")
            } catch {
                finish(nil, "Cannot save converted MP4: \(error.localizedDescription)", "")
            }
        }
    }

    func cancel() {
        guard preparing else { return }
        cancelRequested = true
        status = "Cancellation requested · output will be discarded when FFmpeg returns"
    }

    deinit { monitor?.invalidate() }
}

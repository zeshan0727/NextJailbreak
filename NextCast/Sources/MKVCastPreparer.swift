import Foundation
import Combine
import ffmpegkit

/// Local MKV -> Cast-compatible MP4 preparation. Video packets are remuxed
/// without quality loss; audio is converted to AAC when necessary. No file
/// is uploaded to a third-party server. A complete MP4 is created before
/// Chromecast receives the media URL, avoiding incomplete-range playback.
@MainActor
final class MKVCastPreparer: ObservableObject {
    @Published private(set) var preparing = false
    @Published private(set) var status = ""
    @Published var errorMessage: String?
    private var session: FFmpegSession?

    func prepare(_ movie: Movie, completion: @escaping (Movie) -> Void) {
        guard !preparing else { return }
        guard movie.localURL.pathExtension.lowercased() == "mkv" else {
            completion(movie)
            return
        }
        let folder = MovieLibrary.folder
        let final = folder.appendingPathComponent(movie.id.uuidString + ".cast.mp4")
        let temp = folder.appendingPathComponent(movie.id.uuidString + ".castbuilding.mp4")

        func preparedMovie(_ file: URL) -> Movie {
            let bytes = ((try? FileManager.default.attributesOfItem(atPath: file.path)[.size]) as? NSNumber)?.int64Value ?? 0
            return Movie(id: movie.id, name: movie.name, fileName: file.lastPathComponent,
                         importedAt: movie.importedAt, fileSize: bytes)
        }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: final.path),
           ((attributes[.size] as? NSNumber)?.int64Value ?? 0) > 1024 * 1024 {
            status = "Prepared for Chromecast"
            completion(preparedMovie(final))
            return
        }

        // An MKV copy requires extra storage; never unexpectedly fill the phone.
        let estimatedSize = max(movie.fileSize, 512 * 1024 * 1024)
        if let capacity = try? folder.resourceValues(
            forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity,
           Int64(capacity) < estimatedSize + 256 * 1024 * 1024 {
            errorMessage = "Not enough free storage to prepare the MKV for casting. Free at least \(ByteCountFormatter.string(fromByteCount: estimatedSize + 256 * 1024 * 1024, countStyle: .file)) and try again. Your original MKV will remain untouched."
            return
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: temp.path) {
                try FileManager.default.removeItem(at: temp)
            }
        } catch {
            errorMessage = "Cannot prepare video output: \(error.localizedDescription)"
            return
        }
        preparing = true
        status = "Preparing MKV for Chromecast · copying video and converting audio to AAC"
        let arguments = [
            "-hide_banner", "-nostdin", "-loglevel", "error", "-y",
            "-i", movie.localURL.path,
            "-map", "0:v:0", "-map", "0:a:0?",
            "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
            "-sn", "-dn", "-movflags", "+faststart",
            temp.path
        ]
        session = FFmpegKit.executeWithArgumentsAsync(arguments, withCompleteCallback: {
            [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.session = nil
                self.preparing = false
                if ReturnCode.isSuccess(result.getReturnCode()) {
                    do {
                        guard let attrs = try? FileManager.default.attributesOfItem(atPath: temp.path),
                              ((attrs[.size] as? NSNumber)?.int64Value ?? 0) > 1024 * 1024 else {
                            throw NSError(domain: "NextCast.MKVCast", code: 1,
                                          userInfo: [NSLocalizedDescriptionKey: "Prepared file was empty."])
                        }
                        if FileManager.default.fileExists(atPath: final.path) {
                            try FileManager.default.removeItem(at: final)
                        }
                        try FileManager.default.moveItem(at: temp, to: final)
                        self.status = "MKV prepared successfully"
                        completion(preparedMovie(final))
                    } catch {
                        self.errorMessage = "Cannot save prepared MP4: \(error.localizedDescription)"
                    }
                } else {
                    let message = result.getOutput() ?? ""
                    self.errorMessage = "This MKV could not be prepared for Chromecast. Its video/audio codecs may be unsupported by MP4, or the file may be damaged. \(String(message.suffix(220)))"
                    try? FileManager.default.removeItem(at: temp)
                }
            }
        })
    }

    func cancel() {
        session?.cancel()
        preparing = false
        status = "Preparation cancelled"
    }
}
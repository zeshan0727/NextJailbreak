import SwiftUI
import AVFoundation
import MobileVLCKit
import UIKit
import Combine

struct VideoDetails: Codable {
    var seconds: Double?
    var width: Int?
    var height: Int?

    var durationLabel: String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "Duration pending" }
        let t = Int(seconds)
        return t >= 3600 ? String(format: "%dh %02dm", t/3600, t%3600/60) :
            String(format: "%dm %02ds", t/60, t%60)
    }
    var resolutionLabel: String {
        guard let width, let height, width > 0, height > 0 else { return "Resolution unknown" }
        return "\(width) × \(height)"
    }
}

/// Creates and stores original frame previews from imported videos.
/// For MKV/AVI or other non-AVFoundation containers, use the existing
/// MobileVLCKit decoder rather than guessing third-party movie posters.
@MainActor
final class ArtworkCache: NSObject, ObservableObject {
    static let shared = ArtworkCache()
    @Published private(set) var images: [UUID: UIImage] = [:]
    @Published private(set) var details: [UUID: VideoDetails] = [:]
    private var processing = Set<UUID>()
    // Only one decoder is allowed at once to prevent a startup burst.
    private let renderingQueue = DispatchQueue(label: "nextcast.artwork.serial", qos: .utility)

    private static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NextCast Covers", isDirectory: true)
    }
    private func artURL(_ id: UUID) -> URL {
        Self.folder.appendingPathComponent(id.uuidString + ".jpg")
    }
    private func detailURL(_ id: UUID) -> URL {
        Self.folder.appendingPathComponent(id.uuidString + ".json")
    }

    private override init() {
        super.init()
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
    }

    func load(_ movie: Movie) {
        guard images[movie.id] == nil && !processing.contains(movie.id) else { return }
        processing.insert(movie.id)
        let file = artURL(movie.id)
        if let image = UIImage(contentsOfFile: file.path) {
            images[movie.id] = image
            if let data = try? Data(contentsOf: detailURL(movie.id)),
               let metadata = try? JSONDecoder().decode(VideoDetails.self, from: data) {
                details[movie.id] = metadata
            }
            processing.remove(movie.id)
            return
        }
        // Avoid invoking Apple's image generator on MKV/AVI containers and
        // do not launch VLCMediaThumbnailer automatically: some iOS 16
        // configurations crash while constructing its decoder.
        guard ["mp4", "m4v", "mov", "3gp"].contains(movie.localURL.pathExtension.lowercased()) else {
            details[movie.id] = VideoDetails()
            processing.remove(movie.id)
            return
        }
        renderingQueue.async { [weak self] in
            let asset = AVURLAsset(url: movie.localURL)
            let length = CMTimeGetSeconds(asset.duration)
            let seconds = length.isFinite && length > 0 ? length : nil
            let track = asset.tracks(withMediaType: .video).first
            var width: Int?
            var height: Int?
            if let track {
                let transform = track.preferredTransform
                let dimensions = track.naturalSize.applying(transform)
                width = Int(abs(dimensions.width))
                height = Int(abs(dimensions.height))
            }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 650, height: 400)
            let previewTime = CMTime(seconds: min(4, max(0.5, (seconds ?? 10) * 0.15)),
                                     preferredTimescale: 600)
            let frame = try? generator.copyCGImage(at: previewTime, actualTime: nil)
            let metadata = VideoDetails(seconds: seconds, width: width, height: height)
            DispatchQueue.main.async {
                guard let self else { return }
                if let frame {
                    self.finish(movie.id, image: UIImage(cgImage: frame), metadata: metadata)
                } else {
                    self.details[movie.id] = metadata
                    self.processing.remove(movie.id)
                }
            }
        }
    }

    private func finish(_ id: UUID, image: UIImage, metadata: VideoDetails) {
        images[id] = image
        details[id] = metadata
        if let jpeg = image.jpegData(compressionQuality: 0.78) {
            try? jpeg.write(to: artURL(id), options: .atomic)
        }
        if let data = try? JSONEncoder().encode(metadata) {
            try? data.write(to: detailURL(id), options: .atomic)
        }
        processing.remove(id)
    }
}

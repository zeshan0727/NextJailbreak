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
        return t >= 3600 ? String(format: "%dh %02dm", t / 3600, (t % 3600) / 60) :
            String(format: "%dm %02ds", t / 60, t % 60)
    }

    var resolutionLabel: String {
        guard let width, let height, width > 0, height > 0 else { return "Resolution unknown" }
        return "\(width) × \(height)"
    }
}

/// A small disk-backed artwork pipeline. At most one decoder is active.
/// MP4/MOV use AVFoundation first; every other container (and failures) use
/// MobileVLCKit asynchronously, one item at a time. If decoding fails,
/// generate a readable title cover instead of an empty placeholder.
@MainActor
final class ArtworkCache: NSObject, ObservableObject, VLCMediaThumbnailerDelegate {
    static let shared = ArtworkCache()
    @Published private(set) var images: [UUID: UIImage] = [:]
    @Published private(set) var details: [UUID: VideoDetails] = [:]

    private var queued: [Movie] = []
    private var queuedIDs = Set<UUID>()
    private var activeMovie: Movie?
    private var thumbnailer: VLCMediaThumbnailer?
    private var lastMetadata = VideoDetails()
    private let worker = DispatchQueue(label: "nextcast.artwork.one-at-a-time", qos: .utility)

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
        if images[movie.id] != nil || queuedIDs.contains(movie.id) || activeMovie?.id == movie.id {
            return
        }
        if let image = UIImage(contentsOfFile: artURL(movie.id).path) {
            images[movie.id] = image
            if let data = try? Data(contentsOf: detailURL(movie.id)),
               let metadata = try? JSONDecoder().decode(VideoDetails.self, from: data) {
                details[movie.id] = metadata
            }
            return
        }
        guard FileManager.default.fileExists(atPath: movie.localURL.path) else { return }
        queuedIDs.insert(movie.id)
        queued.append(movie)
        beginNext()
    }

    func regenerate(_ movie: Movie) {
        // Give the user a recovery route if the source was temporarily
        // unavailable or a previous thumbnail was a black frame.
        guard activeMovie?.id != movie.id else { return }
        images.removeValue(forKey: movie.id)
        details.removeValue(forKey: movie.id)
        try? FileManager.default.removeItem(at: artURL(movie.id))
        try? FileManager.default.removeItem(at: detailURL(movie.id))
        queued.removeAll { $0.id == movie.id }
        queuedIDs.remove(movie.id)
        load(movie)
    }

    private func beginNext() {
        guard activeMovie == nil, !queued.isEmpty else { return }
        let movie = queued.removeFirst()
        queuedIDs.remove(movie.id)
        activeMovie = movie
        lastMetadata = VideoDetails()

        // Delay decoder work until after the tab has finished constructing.
        // This avoids concurrent multimedia initialization during app startup.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            guard let self, self.activeMovie?.id == movie.id else { return }
            if ["mp4", "m4v", "mov", "3gp"].contains(movie.localURL.pathExtension.lowercased()) {
                self.generateAppleFrame(for: movie)
            } else {
                self.generateVLCFrame(for: movie)
            }
        }
    }

    private func generateAppleFrame(for movie: Movie) {
        worker.async { [weak self] in
            let asset = AVURLAsset(url: movie.localURL)
            let seconds = CMTimeGetSeconds(asset.duration)
            let duration: Double? = seconds.isFinite && seconds > 0 ? seconds : nil
            let track = asset.tracks(withMediaType: .video).first
            var width: Int?
            var height: Int?
            if let track {
                let rect = track.naturalSize.applying(track.preferredTransform)
                width = Int(abs(rect.width))
                height = Int(abs(rect.height))
            }
            let metadata = VideoDetails(seconds: duration, width: width, height: height)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 540, height: 480)
            // Several positions help with dark introductory frames and short clips.
            let positions: [Double] = [
                min(max(1, (duration ?? 30) * 0.2), 120),
                0.5,
                min(max(3, (duration ?? 30) * 0.5), 300)
            ]
            var frame: CGImage?
            for p in positions {
                frame = try? generator.copyCGImage(at: CMTime(seconds: p, preferredTimescale: 600),
                                                    actualTime: nil)
                if frame != nil { break }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.activeMovie?.id == movie.id else { return }
                self.lastMetadata = metadata
                if let frame {
                    self.finish(movie, image: UIImage(cgImage: frame), metadata: metadata)
                } else {
                    self.generateVLCFrame(for: movie)
                }
            }
        }
    }

    private func generateVLCFrame(for movie: Movie) {
        guard activeMovie?.id == movie.id else { return }
        // Only one thumbnailer instance is ever retained at a time.
        let media = VLCMedia(url: movie.localURL)
        let decoder = VLCMediaThumbnailer()
        decoder.media = media
        decoder.delegate = self
        decoder.thumbnailWidth = 540
        decoder.thumbnailHeight = 400
        decoder.snapshotPosition = 0.25
        thumbnailer = decoder
        decoder.fetchThumbnail()
        // A misbehaving file may never send its delegate callback.
        // Bound the time spent on a single file so subsequent covers progress.
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self, weak decoder] in
            guard let self, let decoder, self.thumbnailer === decoder,
                  let pending = self.activeMovie, pending.id == movie.id else { return }
            self.thumbnailer = nil
            self.finish(pending, image: self.createTitleCover(pending), metadata: self.lastMetadata)
        }
    }

    func mediaThumbnailer(_ mediaThumbnailer: VLCMediaThumbnailer,
                          didFinishThumbnail thumbnail: CGImage) {
        guard thumbnailer === mediaThumbnailer, let movie = activeMovie else { return }
        let duration = Double(mediaThumbnailer.media.length.intValue) / 1000.0
        var info = lastMetadata
        if duration.isFinite && duration > 0 { info.seconds = duration }
        thumbnailer = nil
        finish(movie, image: UIImage(cgImage: thumbnail), metadata: info)
    }

    func mediaThumbnailerDidTimeOut(_ mediaThumbnailer: VLCMediaThumbnailer) {
        guard thumbnailer === mediaThumbnailer, let movie = activeMovie else { return }
        thumbnailer = nil
        finish(movie, image: createTitleCover(movie), metadata: lastMetadata)
    }

    private func finish(_ movie: Movie, image: UIImage, metadata: VideoDetails) {
        images[movie.id] = image
        details[movie.id] = metadata
        if let data = image.jpegData(compressionQuality: 0.77) {
            try? data.write(to: artURL(movie.id), options: .atomic)
        }
        if let data = try? JSONEncoder().encode(metadata) {
            try? data.write(to: detailURL(movie.id), options: .atomic)
        }
        activeMovie = nil
        // Space out decoder jobs, including after a timeout.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.beginNext()
        }
    }

    private func createTitleCover(_ movie: Movie) -> UIImage {
        let size = CGSize(width: 480, height: 680)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let colors = [
                UIColor(red: 0.055, green: 0.12, blue: 0.18, alpha: 1).cgColor,
                UIColor(red: 0.10, green: 0.27, blue: 0.34, alpha: 1).cgColor
            ] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors, locations: [0, 1])
            if let gradient {
                cg.drawLinearGradient(gradient, start: .zero,
                                      end: CGPoint(x: size.width, y: size.height),
                                      options: [])
            }
            let symbol = UIImage(systemName: "film.stack.fill")?
                .withTintColor(.white.withAlphaComponent(0.6), renderingMode: .alwaysOriginal)
            symbol?.draw(in: CGRect(x: 180, y: 125, width: 120, height: 110))
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineBreakMode = .byTruncatingTail
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 36, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: style
            ]
            (movie.name as NSString).draw(in: CGRect(x: 28, y: 370, width: 424, height: 174),
                                          withAttributes: titleAttributes)
            let formatAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .semibold),
                .foregroundColor: UIColor.cyan,
                .paragraphStyle: style
            ]
            (movie.format as NSString).draw(in: CGRect(x: 30, y: 580, width: 420, height: 42),
                                            withAttributes: formatAttributes)
        }
    }
}

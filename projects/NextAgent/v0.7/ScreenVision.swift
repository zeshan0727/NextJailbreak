import Foundation
import UIKit
import Vision
import ImageIO
import Darwin

struct NAOCRMatch {
    let text: String
    let confidence: Float
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var centerX: Double { x + width / 2.0 }
    var centerY: Double { y + height / 2.0 }

    var dictionary: [String: Any] {
        [
            "text": text,
            "confidence": confidence,
            "box": [
                "x": x,
                "y": y,
                "width": width,
                "height": height
            ],
            "center": [
                "x": centerX,
                "y": centerY
            ]
        ]
    }
}

final class NAScreenVision {
    static let shared = NAScreenVision()

    private let captureDirectory = "/var/mobile/Library/NextAgent/Captures"

    private init() {}

    func captureScreen() -> UIImage? {
        var result: UIImage?
        let block = {
            result = self.captureOnMainThread()
        }
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.sync(execute: block)
        }
        return result
    }

    private func captureOnMainThread() -> UIImage? {
        // Private system capture. On a TrollStore platform app this can capture the current display,
        // including another foreground app, instead of only Next Agent's own window.
        if let process = dlopen(nil, RTLD_NOW),
           let symbol = dlsym(process, "_UICreateScreenUIImage") {
            typealias Fn = @convention(c) () -> Unmanaged<AnyObject>?
            let fn = unsafeBitCast(symbol, to: Fn.self)
            if let object = fn()?.takeRetainedValue(),
               let image = object as? UIImage {
                return image
            }
        }

        // QuartzCore render-server fallback.
        if let qc = dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore", RTLD_LAZY),
           let symbol = dlsym(qc, "CARenderServerCaptureDisplay") {
            typealias Fn = @convention(c) (UInt32, CFString, CFDictionary?) -> Unmanaged<CGImage>?
            let fn = unsafeBitCast(symbol, to: Fn.self)
            for name in ["LCD", "Main"] {
                if let cg = fn(0, name as CFString, nil)?.takeRetainedValue() {
                    return UIImage(cgImage: cg, scale: UIScreen.main.scale, orientation: .up)
                }
            }
        }

        // Final fallback captures the Next Agent window only.
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow }) ?? scenes.flatMap(\.windows).first
        guard let window else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    func saveCapture(_ image: UIImage, quality: CGFloat = 0.78) -> [String: Any]? {
        guard let data = image.jpegData(compressionQuality: max(0.25, min(0.95, quality))) else { return nil }
        do {
            try FileManager.default.createDirectory(
                atPath: captureDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let path = "\(captureDirectory)/screen-\(stamp).jpg"
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            return [
                "path": path,
                "bytes": data.count,
                "pixel_width": Int(image.size.width * image.scale),
                "pixel_height": Int(image.size.height * image.scale),
                "point_width": image.size.width,
                "point_height": image.size.height
            ]
        } catch {
            return nil
        }
    }

    func recognizeText(
        image: UIImage,
        languages: [String] = [],
        fast: Bool = false,
        maxItems: Int = 160
    ) -> [NAOCRMatch] {
        guard let cgImage = image.cgImage else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = fast ? .fast : .accurate
        request.usesLanguageCorrection = !fast
        if !languages.isEmpty {
            request.recognitionLanguages = Array(languages.prefix(6))
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        let observations = request.results ?? []
        var matches: [NAOCRMatch] = []
        matches.reserveCapacity(min(observations.count, maxItems))

        for observation in observations.prefix(maxItems) {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let box = observation.boundingBox

            // Vision coordinates are normalized with origin at bottom-left.
            // Next Agent touch coordinates use normalized top-left origin.
            let x = Double(box.origin.x)
            let y = 1.0 - Double(box.origin.y + box.height)
            let width = Double(box.width)
            let height = Double(box.height)

            matches.append(
                NAOCRMatch(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    x: x,
                    y: y,
                    width: width,
                    height: height
                )
            )
        }

        return matches.sorted {
            if abs($0.y - $1.y) > 0.025 { return $0.y < $1.y }
            return $0.x < $1.x
        }
    }

    func findText(_ query: String, in matches: [NAOCRMatch]) -> [NAOCRMatch] {
        let needle = normalized(query)
        guard !needle.isEmpty else { return [] }

        return matches.filter { item in
            let hay = normalized(item.text)
            return hay == needle || hay.contains(needle) || needle.contains(hay)
        }
        .sorted {
            let aExact = normalized($0.text) == needle
            let bExact = normalized($1.text) == needle
            if aExact != bExact { return aExact && !bExact }
            return $0.confidence > $1.confidence
        }
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

import Foundation

/// Identifies videos downloaded from opaque, signed or redirecting URLs.
/// Never infer a video solely because a file was downloaded.
enum VideoFileInspector {
    static func videoExtension(for file: URL, name: String, mimeType: String? = nil) -> String? {
        let suggestedExt = URL(fileURLWithPath: name).pathExtension.lowercased()
        if VideoFormats.extensions.contains(suggestedExt) { return suggestedExt }

        let mime = (mimeType ?? "").lowercased().split(separator: ";").first.map(String.init) ?? ""
        let fromMime: [String: String] = [
            "video/mp4": "mp4", "video/x-m4v": "m4v",
            "video/quicktime": "mov", "video/x-matroska": "mkv",
            "video/webm": "webm", "video/x-msvideo": "avi",
            "video/x-flv": "flv", "video/x-ms-wmv": "wmv",
            "video/mpeg": "mpeg", "video/mp2t": "ts",
            "video/3gpp": "3gp", "video/ogg": "ogv",
            "application/x-matroska": "mkv"
        ]
        if let known = fromMime[mime] { return known }

        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let bytes = try? handle.read(upToCount: 4096), bytes.count >= 12 else { return nil }
        let d = [UInt8](bytes)
        let prefix = Array(d.prefix(12))
        func ascii(_ start: Int, _ str: String) -> Bool {
            let pattern = Array(str.utf8)
            guard d.count >= start + pattern.count else { return false }
            return Array(d[start..<(start+pattern.count)]) == pattern
        }
        if prefix[0...3].elementsEqual([0x1A,0x45,0xDF,0xA3]) {
            let first = String(data: bytes.prefix(400), encoding: .isoLatin1)?.lowercased() ?? ""
            return first.contains("webm") ? "webm" : "mkv"
        }
        if ascii(4, "ftyp") {
            if ascii(8, "qt  ") { return "mov" }
            if ascii(8, "3gp") { return "3gp" }
            return "mp4"
        }
        if ascii(0,"RIFF") && ascii(8,"AVI ") { return "avi" }
        if ascii(0,"FLV") { return "flv" }
        if ascii(0,"OggS") { return "ogv" }
        if ascii(0,".RMF") { return "rm" }
        if d.count >= 188 * 2 && d[0] == 0x47 && d[188] == 0x47 { return "ts" }
        if d[0..<4].elementsEqual([0x00,0x00,0x01,0xBA]) { return "mpeg" }
        let asfHeader: [UInt8] = [0x30,0x26,0xB2,0x75,0x8E,0x66,0xCF,0x11,0xA6,0xD9,0x00,0xAA]
        if Array(d.prefix(asfHeader.count)) == asfHeader { return "wmv" }
        return nil
    }

    static func preparedVideoURL(_ source: URL, name: String, mimeType: String? = nil) throws -> URL? {
        guard let ext = videoExtension(for: source, name: name, mimeType: mimeType) else { return nil }
        if source.pathExtension.lowercased() == ext { return source }
        let destination = source.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + "." + ext)
        try FileManager.default.moveItem(at: source, to: destination)
        return destination
    }

    static func cleanTitle(_ name: String) -> String {
        let base = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        return (base.isEmpty ? "Downloaded Movie" : base).replacingOccurrences(of: "_", with: " ")
    }
}

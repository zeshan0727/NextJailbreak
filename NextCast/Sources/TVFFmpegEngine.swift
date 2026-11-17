import Foundation

/// Non-proprietary, source-derived settings for the FFmpeg-based TV converter.
/// FFmpeg 8.1.2 "min" supplies Matroska/AVI demuxing, AAC conversion and
/// VideoToolbox H.264 encoding. Input formats/codecs are capability-checked.
struct TVAudioTrack: Identifiable {
    let id: Int                 // 0:a:<ordinal>
    let codec: String
    let channels: Int
    let language: String
    let title: String
    var label: String {
        let lang = language.isEmpty ? "Audio \(id + 1)" : language.uppercased()
        let details = [codec.uppercased(), channels > 0 ? "\(channels) ch" : ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        return [lang, title, details].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct TVSourceDetails {
    let videoCodec: String
    let width: Int
    let height: Int
    let fps: Double
    let duration: Double
    let audio: [TVAudioTrack]
    var supportsVideoCopy: Bool { videoCodec.lowercased() == "h264" }
    // The fast, truly lossless MP4 remux is offered only for a tested
    // TV-friendly pairing. A container copy cannot repair AC3/DTS audio.
    func supportsNoReencoding(audioOrdinal: Int) -> Bool {
        guard audio.indices.contains(audioOrdinal) else { return false }
        return ["h264", "hevc"].contains(videoCodec.lowercased()) &&
               audio[audioOrdinal].codec.lowercased() == "aac"
    }
}

enum TVVideoMode: String, CaseIterable, Identifiable {
    case remux = "Without re-encoding"
    case automatic = "Fast TV (copy video when possible)"
    case gpuH264 = "GPU acceleration mode 1"
    case gpuHEVC = "GPU acceleration mode 2"
    case cpuMPEG4 = "CPU encoding"
    var id: String { rawValue }

    var summary: String {
        switch self {
        case .remux:
            return "Fastest: copy the selected original video and audio without changing quality. Available for H.264/HEVC video with AAC audio."
        case .automatic:
            return "Recommended for TV: copy compatible H.264 video and convert only audio to AAC, or use hardware H.264 when video conversion is necessary."
        case .gpuH264:
            return "VideoToolbox hardware H.264/AVC + AAC stereo. Fast encoding for most Chromecast-compatible TVs."
        case .gpuHEVC:
            return "VideoToolbox hardware H.265/HEVC + AAC stereo. Some TVs and older Chromecast models cannot play HEVC."
        case .cpuMPEG4:
            return "FFmpeg software MPEG-4 Part 2 + AAC. More CPU intensive; not universally supported on Chromecast. Software H.264 requires an encoder not bundled with the LGPL min package."
        }
    }
    var expectedVideoCodec: String {
        switch self {
        case .remux: return "copy"
        case .automatic, .gpuH264: return "h264"
        case .gpuHEVC: return "hevc"
        case .cpuMPEG4: return "mpeg4"
        }
    }
}

enum TVResolution: String, CaseIterable, Identifiable {
    case source = "Source"
    case hd1080 = "Up to 1080p"
    case hd720 = "Up to 720p"
    var id: String { rawValue }
}

enum TVFrameRate: String, CaseIterable, Identifiable {
    case source = "Source"
    case fps24 = "24 fps"
    case fps30 = "30 fps"
    var id: String { rawValue }
}

struct TVConversionOptions {
    var audioOrdinal = 0
    var videoMode: TVVideoMode = .automatic
    var resolution: TVResolution = .source
    var frameRate: TVFrameRate = .source
    var videoBitrateKbps = 1880
    var audioBitrateKbps = 192
    /// Converter UI opts into explicit FFmpeg settings even for MP4 inputs.
    var useFFmpeg = false

    var fingerprint: String {
        "a\(audioOrdinal).v\(videoMode.expectedVideoCodec)-\(videoMode.id).r\(resolution == .source ? "src" : resolution == .hd1080 ? "1080" : "720").f\(frameRate == .source ? "src" : frameRate == .fps24 ? "24" : "30").b\(videoBitrateKbps).ab\(audioBitrateKbps)"
            .replacingOccurrences(of: " ", with: "_")
    }

    func requiresVideoEncode(_ source: TVSourceDetails) -> Bool {
        switch videoMode {
        case .remux: return false
        case .automatic:
            return !source.supportsVideoCopy || resolution != .source || frameRate != .source
        case .gpuH264, .gpuHEVC, .cpuMPEG4: return true
        }
    }

    func expectedOutputVideoCodec(_ source: TVSourceDetails) -> String {
        videoMode == .remux ? source.videoCodec.lowercased() : videoMode.expectedVideoCodec
    }
    var copiesAudio: Bool { videoMode == .remux }

    func validate(with source: TVSourceDetails) -> String? {
        guard source.audio.indices.contains(audioOrdinal) else {
            return "Choose an available audio track."
        }
        if videoMode == .remux {
            guard resolution == .source && frameRate == .source else {
                return "Without re-encoding must keep the original resolution and frame rate."
            }
            guard source.supportsNoReencoding(audioOrdinal: audioOrdinal) else {
                return "Stream copy requires H.264 or HEVC video and AAC audio to create an MP4 without re-encoding. Choose Fast TV for other sources."
            }
        }
        return nil
    }
}

enum TVFFmpegEngine {
    static func inspect(_ url: URL, completion: @escaping (Result<TVSourceDetails, Error>) -> Void) {
        NCFFmpegBridge.probeFile(url.path) { json, message in
            guard let json, let raw = json.data(using: .utf8) else {
                completion(.failure(NSError(domain: "NextCast.FFprobe", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message ?? "Cannot inspect the selected video."])))
                return
            }
            do {
                guard let body = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
                      let streams = body["streams"] as? [[String: Any]] else {
                    throw NSError(domain: "NextCast.FFprobe", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "Missing source media streams."])
                }
                let video = streams.first { ($0["codec_type"] as? String) == "video" } ?? [:]
                let audioStreams = streams.filter { ($0["codec_type"] as? String) == "audio" }
                let audio = audioStreams.enumerated().map { ordinal, stream -> TVAudioTrack in
                    let tags = stream["tags"] as? [String: String] ?? [:]
                    return TVAudioTrack(id: ordinal,
                        codec: stream["codec_name"] as? String ?? "unknown",
                        channels: stream["channels"] as? Int ?? 0,
                        language: tags["language"] ?? "",
                        title: tags["title"] ?? "")
                }
                let format = body["format"] as? [String: Any] ?? [:]
                let seconds = Double(format["duration"] as? String ?? "") ??
                    (format["duration"] as? NSNumber)?.doubleValue ?? 0
                let fpsString = (video["avg_frame_rate"] as? String) ?? "0/1"
                let nums = fpsString.split(separator: "/").compactMap { Double($0) }
                let fps = nums.count == 2 && nums[1] != 0 ? nums[0] / nums[1] : 0
                let details = TVSourceDetails(
                    videoCodec: video["codec_name"] as? String ?? "",
                    width: video["width"] as? Int ?? 0,
                    height: video["height"] as? Int ?? 0,
                    fps: fps,
                    duration: seconds,
                    audio: audio)
                guard !details.videoCodec.isEmpty, !details.audio.isEmpty else {
                    throw NSError(domain: "NextCast.FFprobe", code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "The video needs at least one video track and one audio track."])
                }
                completion(.success(details))
            } catch {
                completion(.failure(error))
            }
        }
    }

    static func conversionArgs(source: URL, target: URL, details: TVSourceDetails,
                               options: TVConversionOptions) -> [String] {
        let audio = min(max(0, options.audioOrdinal), max(0, details.audio.count - 1))
        var args = ["-hide_banner", "-nostdin", "-y", "-loglevel", "warning",
                    "-fflags", "+genpts", "-i", source.path,
                    "-map", "0:v:0", "-map", "0:a:\(audio)",
                    "-sn", "-dn", "-map_metadata", "-1", "-map_chapters", "-1"]
        if options.requiresVideoEncode(details) {
            switch options.videoMode {
            case .cpuMPEG4:
                // LGPL min FFmpeg has a software MPEG-4 Part 2 encoder,
                // not GPL libx264. Do not silently claim software H.264.
                args += ["-c:v", "mpeg4", "-b:v", "\(max(500, options.videoBitrateKbps))k",
                         "-pix_fmt", "yuv420p"]
            case .gpuHEVC:
                args += ["-c:v", "hevc_videotoolbox",
                         "-b:v", "\(max(500, options.videoBitrateKbps))k",
                         "-pix_fmt", "yuv420p", "-tag:v", "hvc1"]
            case .automatic, .gpuH264, .remux:
                // VideoToolbox is the Apple hardware video encoder.
                args += ["-c:v", "h264_videotoolbox",
                         "-b:v", "\(max(500, options.videoBitrateKbps))k",
                         "-pix_fmt", "yuv420p"]
            }
            switch options.resolution {
            case .source: break
            case .hd1080:
                if details.width > 1920 || details.height > 1080 {
                    args += ["-vf", "scale=1920:1080:force_original_aspect_ratio=decrease:force_divisible_by=2"]
                }
            case .hd720:
                if details.width > 1280 || details.height > 720 {
                    args += ["-vf", "scale=1280:720:force_original_aspect_ratio=decrease:force_divisible_by=2"]
                }
            }
            switch options.frameRate {
            case .source: break
            case .fps24: args += ["-r", "24"]
            case .fps30: args += ["-r", "30"]
            }
        } else {
            // The important fast path for MKV H.264. No video quality loss.
            args += ["-c:v", "copy"]
        }
        if options.copiesAudio {
            args += ["-c:a", "copy"]
        } else {
            args += ["-c:a", "aac",
                     "-b:a", "\(max(96, options.audioBitrateKbps))k",
                     "-ar", "48000", "-ac", "2"]
        }
        args += ["-max_muxing_queue_size", "1024",
                 "-avoid_negative_ts", "make_zero",
                 "-movflags", "+faststart",
                 "-f", "mp4", target.path]
        return args
    }
}

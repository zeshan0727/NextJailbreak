from pathlib import Path
import plistlib

root = Path(".")
swift_path = root / "NextAgent/NextAgent.swift"
screen_path = root / "NextAgent/ScreenVision.swift"
router_path = root / "NextAgent/V071Router.swift"
v07_path = root / "NextAgent/V07Tools.swift"
modern_ui_path = root / "NextAgent/ModernUI.swift"

s = swift_path.read_text()
screen = screen_path.read_text()
router = router_path.read_text()
v07 = v07_path.read_text()
modern_ui = modern_ui_path.read_text()

s = s.replace(
    "Next Agent 0.7.5 is ready with IOSurface real-screen capture, a system-level progress pill, and stricter background vision.",
    "Next Agent 0.7.6 is ready with validated CoreVideo screen capture and a foreground-app progress HUD."
)
s = s.replace(
    'private static let currentToolSchemaVersion = "0.7.5-iosurface1"',
    'private static let currentToolSchemaVersion = "0.7.6-capturehud1"'
)
s = s.replace('"client_version": "0.7.5"', '"client_version": "0.7.6"')

# Persist the complete SpringBoard bridge metadata so every screen tool can
# report whether the frame really came from the compositor and passed quality
# validation.
old_prop = '    private(set) var lastCaptureSource = "none"\n'
new_prop = '''    private(set) var lastCaptureSource = "none"
    private(set) var lastCaptureMetadata: [String: Any] = [:]
'''
if old_prop not in screen:
    raise SystemExit("v0.7.6 capture property marker missing")
screen = screen.replace(old_prop, new_prop, 1)

old_bridge = '''    private func captureFromSpringBoard() -> UIImage? {
        let result = RootDaemonClient.request(action: "screen_capture_real")
        guard result.success,
              let data = result.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["success"] as? Bool) == true,
              let path = json["path"] as? String,
              let image = UIImage(contentsOfFile: path) else {
            return nil
        }

        lastCaptureSource = (json["source"] as? String) ?? "springboard"
        return image
    }
'''
new_bridge = '''    private func captureFromSpringBoard() -> UIImage? {
        let result = RootDaemonClient.request(action: "screen_capture_real")

        guard let data = result.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            lastCaptureMetadata = [
                "success": false,
                "error": String(result.output.prefix(1200))
            ]
            lastCaptureSource = "springboard_bridge_invalid_response"
            return nil
        }

        lastCaptureMetadata = json
        lastCaptureSource = (json["source"] as? String) ?? "springboard"

        guard result.success,
              (json["success"] as? Bool) == true,
              let quality = json["quality"] as? [String: Any],
              (quality["valid"] as? Bool) == true,
              let path = json["path"] as? String,
              let image = UIImage(contentsOfFile: path) else {
            if (json["success"] as? Bool) == true {
                lastCaptureSource = "springboard_bridge_unusable_frame"
            }
            return nil
        }

        return image
    }
'''
if old_bridge not in screen:
    raise SystemExit("v0.7.6 SpringBoard bridge marker missing")
screen = screen.replace(old_bridge, new_bridge, 1)

old_save = '''    func saveCapture(_ image: UIImage, quality: CGFloat = 0.78) -> [String: Any]? {
        guard let data = image.jpegData(compressionQuality: max(0.25, min(0.95, quality))) else { return nil }
        do {
            try FileManager.default.createDirectory(
                atPath: captureDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let path = "\\(captureDirectory)/screen-\\(stamp).jpg"
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
'''
new_save = '''    func saveCapture(_ image: UIImage, quality: CGFloat = 0.78) -> [String: Any]? {
        _ = quality
        guard let data = image.pngData() else { return nil }
        do {
            try FileManager.default.createDirectory(
                atPath: captureDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let path = "\\(captureDirectory)/screen-\\(stamp).png"
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            return [
                "path": path,
                "format": "png",
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
'''
if old_save not in screen:
    raise SystemExit("v0.7.6 saveCapture marker missing")
screen = screen.replace(old_save, new_save, 1)

needle = '        request.usesLanguageCorrection = !fast\n'
replacement = '''        request.usesLanguageCorrection = !fast
        request.minimumTextHeight = 0.0075
'''
if needle not in screen:
    raise SystemExit("v0.7.6 OCR request marker missing")
screen = screen.replace(needle, replacement, 1)

old_return = '''        return matches.sorted {
            if abs($0.y - $1.y) > 0.025 { return $0.y < $1.y }
            return $0.x < $1.x
        }
'''
new_return = '''        if matches.isEmpty && fast {
            return recognizeText(
                image: image,
                languages: languages,
                fast: false,
                maxItems: maxItems
            )
        }

        return matches.sorted {
            if abs($0.y - $1.y) > 0.025 { return $0.y < $1.y }
            return $0.x < $1.x
        }
'''
if old_return not in screen:
    raise SystemExit("v0.7.6 OCR retry marker missing")
screen = screen.replace(old_return, new_return, 1)

old_capture_result = '''        return v07JSON([
            "success": true,
            "source": NAScreenVision.shared.lastCaptureSource,
            "capture": metadata
        ])
'''
new_capture_result = '''        return v07JSON([
            "success": true,
            "source": NAScreenVision.shared.lastCaptureSource,
            "bridge": NAScreenVision.shared.lastCaptureMetadata,
            "capture": metadata
        ])
'''
if old_capture_result not in v07:
    raise SystemExit("v0.7.6 screen capture result marker missing")
v07 = v07.replace(old_capture_result, new_capture_result, 1)

old_ocr = '''        let matches = NAScreenVision.shared.recognizeText(image: image, languages: languages, fast: fast)
        return v07JSON([
            "success": true,
            "coordinate_space": "normalized top-left; x/y range 0...1",
            "items": matches.map(\\.dictionary)
        ])
'''
new_ocr = '''        let matches = NAScreenVision.shared.recognizeText(image: image, languages: languages, fast: fast)
        guard !matches.isEmpty else {
            return v07JSON([
                "success": false,
                "message": "Capture passed compositor validation but OCR found no visible text.",
                "source": NAScreenVision.shared.lastCaptureSource,
                "bridge": NAScreenVision.shared.lastCaptureMetadata,
                "coordinate_space": "normalized top-left; x/y range 0...1",
                "items": []
            ])
        }
        return v07JSON([
            "success": true,
            "source": NAScreenVision.shared.lastCaptureSource,
            "bridge": NAScreenVision.shared.lastCaptureMetadata,
            "coordinate_space": "normalized top-left; x/y range 0...1",
            "items": matches.map(\\.dictionary)
        ])
'''
if old_ocr not in v07:
    raise SystemExit("v0.7.6 OCR result marker missing")
v07 = v07.replace(old_ocr, new_ocr, 1)

old_describe = '''        let compact = matches.prefix(100).map { item in
            [
                "text": item.text,
                "confidence": item.confidence,
                "center": ["x": item.centerX, "y": item.centerY]
            ] as [String: Any]
        }
        return v07JSON([
            "success": true,
            "capture": capture,
            "visible_text": compact,
            "coordinate_space": "normalized top-left; x/y range 0...1"
        ])
'''
new_describe = '''        let compact = matches.prefix(100).map { item in
            [
                "text": item.text,
                "confidence": item.confidence,
                "center": ["x": item.centerX, "y": item.centerY]
            ] as [String: Any]
        }
        guard !compact.isEmpty else {
            return v07JSON([
                "success": false,
                "message": "Current compositor frame passed validation, but no readable text was detected. Do not guess coordinates.",
                "source": NAScreenVision.shared.lastCaptureSource,
                "bridge": NAScreenVision.shared.lastCaptureMetadata,
                "capture": capture,
                "visible_text": [],
                "coordinate_space": "normalized top-left; x/y range 0...1"
            ])
        }
        return v07JSON([
            "success": true,
            "source": NAScreenVision.shared.lastCaptureSource,
            "bridge": NAScreenVision.shared.lastCaptureMetadata,
            "capture": capture,
            "visible_text": compact,
            "coordinate_space": "normalized top-left; x/y range 0...1"
        ])
'''
if old_describe not in v07:
    raise SystemExit("v0.7.6 describe result marker missing")
v07 = v07.replace(old_describe, new_describe, 1)

# Tool copy now accurately describes the lossless capture used for OCR.
v07 = v07.replace(
    'Capture the current iPhone display and save a JPEG under /var/mobile/Library/NextAgent/Captures. Read-only.',
    'Capture the current iPhone display and save a lossless PNG under /var/mobile/Library/NextAgent/Captures. Read-only.'
)

instruction = '''              When phone_screen reports source=springboard_capture_failed_background or a real-screen bridge failure, stop coordinate interaction for that step and report the capture failure rather than guessing. A screenshot from Next Agent's own backgrounded window is never valid evidence of another foreground app.
'''
replacement = instruction + '''              A phone_screen result is usable for coordinate planning only when its SpringBoard bridge reports success=true and quality.valid=true. Empty OCR is a real failure for text-driven UI steps such as Notes; do not guess a Compose button position after an empty OCR result.
'''
if instruction not in s:
    raise SystemExit("v0.7.6 agent instruction marker missing")
s = s.replace(instruction, replacement, 1)

modern_ui = modern_ui.replace(
    "Full Toolset 0.7.0 • RootHide • GPT-6 Astra",
    "0.7.6 • RootHide • GPT-6 Astra"
)

swift_path.write_text(s)
screen_path.write_text(screen)
router_path.write_text(router)
v07_path.write_text(v07)
modern_ui_path.write_text(modern_ui)

project = root / "project.yml"
y = project.read_text()
y = y.replace("MARKETING_VERSION: 0.7.5", "MARKETING_VERSION: 0.7.6")
y = y.replace("CURRENT_PROJECT_VERSION: 13", "CURRENT_PROJECT_VERSION: 14")
project.write_text(y)

plist_path = root / "NextAgent/Info.plist"
d = plistlib.loads(plist_path.read_bytes())
d["CFBundleShortVersionString"] = "0.7.6"
d["CFBundleVersion"] = "14"
plist_path.write_bytes(plistlib.dumps(d))

assert 'currentToolSchemaVersion = "0.7.6-capturehud1"' in swift_path.read_text()
assert "lastCaptureMetadata" in screen_path.read_text()
assert "minimumTextHeight = 0.0075" in screen_path.read_text()
assert '"bridge": NAScreenVision.shared.lastCaptureMetadata' in v07_path.read_text()
assert "MARKETING_VERSION: 0.7.6" in project.read_text()

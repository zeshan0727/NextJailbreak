import AppKit
import Foundation

// Build-time icon renderer. Input is text-only JSON so the iPhone can publish
// it through the existing source manifest; output is a real 1024x1024 PNG.
struct IconStyle: Decodable {
    var background: String?
    var highlight: String?
    var foreground: String?
    var glyph: String?
}
func color(_ value: String?, fallback: NSColor) -> NSColor {
    guard let raw = value?.trimmingCharacters(in: CharacterSet(charactersIn: "# ")),
          raw.count == 6, let rgb = Int(raw, radix: 16) else { return fallback }
    return NSColor(
        calibratedRed: CGFloat((rgb >> 16) & 255) / 255,
        green: CGFloat((rgb >> 8) & 255) / 255,
        blue: CGFloat(rgb & 255) / 255, alpha: 1)
}
guard CommandLine.arguments.count >= 3 else {
    fputs("Usage: swift make-app-icon.swift PROJECT_DIRECTORY APP_SLUG\n", stderr)
    exit(2)
}
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let slug = CommandLine.arguments[2]
let specURL = root.appendingPathComponent("Sources/AppIconSpec.json")
let spec = (try? Data(contentsOf: specURL)).flatMap {
    try? JSONDecoder().decode(IconStyle.self, from: $0)
}
let background = color(spec?.background, fallback: NSColor(calibratedRed: 0.27, green: 0.28, blue: 0.79, alpha: 1))
let highlight = color(spec?.highlight, fallback: NSColor(calibratedRed: 0.12, green: 0.72, blue: 0.84, alpha: 1))
let foreground = color(spec?.foreground, fallback: .white)
let defaultGlyph = slug.split(separator: "-").first.map { String($0.prefix(1)).uppercased() } ?? "A"
let requestedGlyph = spec?.glyph?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
let glyph = requestedGlyph.isEmpty ? defaultGlyph : String(requestedGlyph.prefix(2))

let n = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0),
    let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Unable to allocate app icon bitmap")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
let canvas = NSRect(x: 0, y: 0, width: n, height: n)
NSGradient(starting: background, ending: highlight).draw(in: NSBezierPath(rect: canvas), angle: 32)
NSColor.white.withAlphaComponent(0.15).setFill()
NSBezierPath(roundedRect: NSRect(x: 140, y: 140, width: 744, height: 744), xRadius: 176, yRadius: 176).fill()
let style = NSMutableParagraphStyle()
style.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 465, weight: .bold),
    .foregroundColor: foreground,
    .paragraphStyle: style
]
(glyph as NSString).draw(in: NSRect(x: 110, y: 257, width: 804, height: 536), withAttributes: attributes)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

let directory = root.appendingPathComponent("Sources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Failed to encode app icon PNG")
}
try png.write(to: directory.appendingPathComponent("AppIcon.png"), options: .atomic)
let catalog = """
{
  "images": [
    {"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}
  ],
  "info": {"author": "xcode", "version": 1}
}
"""
try Data(catalog.utf8).write(to: directory.appendingPathComponent("Contents.json"), options: .atomic)
print("Generated 1024x1024 AppIcon.png for \(slug), from " + (spec == nil ? "default brand style" : "AppIconSpec.json"))

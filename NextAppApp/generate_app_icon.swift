import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "NextApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let canvas = NSSize(width: 1024, height: 1024)
let image = NSImage(size: canvas)

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else { fatalError("No graphics context") }

let colors = [
    NSColor(calibratedRed: 0.08, green: 0.18, blue: 0.52, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.39, green: 0.12, blue: 0.70, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.02, green: 0.62, blue: 0.78, alpha: 1).cgColor
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0,0.56,1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 70, y: 950), end: CGPoint(x: 950, y: 60), options: [])

let outer = NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832), xRadius: 220, yRadius: 220)
context.saveGState()
context.setShadow(offset: .zero, blur: 48, color: NSColor.black.withAlphaComponent(0.28).cgColor)
NSColor.white.withAlphaComponent(0.13).setFill()
outer.fill()
context.restoreGState()

let border = NSBezierPath(roundedRect: NSRect(x: 108, y: 108, width: 808, height: 808), xRadius: 208, yRadius: 208)
border.lineWidth = 10
NSColor.white.withAlphaComponent(0.42).setStroke()
border.stroke()

let tileSize: CGFloat = 210
let gap: CGFloat = 46
let startX: CGFloat = 279
let startY: CGFloat = 279
for row in 0..<2 {
    for col in 0..<2 {
        let rect = NSRect(
            x: startX + CGFloat(col) * (tileSize + gap),
            y: startY + CGFloat(row) * (tileSize + gap),
            width: tileSize,
            height: tileSize
        )
        let tile = NSBezierPath(roundedRect: rect, xRadius: 58, yRadius: 58)
        NSColor.white.withAlphaComponent(row == 1 && col == 1 ? 0.94 : 0.82).setFill()
        tile.fill()
    }
}

let spark = NSBezierPath()
spark.move(to: NSPoint(x: 792, y: 760))
spark.line(to: NSPoint(x: 814, y: 818))
spark.line(to: NSPoint(x: 872, y: 840))
spark.line(to: NSPoint(x: 814, y: 862))
spark.line(to: NSPoint(x: 792, y: 920))
spark.line(to: NSPoint(x: 770, y: 862))
spark.line(to: NSPoint(x: 712, y: 840))
spark.line(to: NSPoint(x: 770, y: 818))
spark.close()
NSColor.white.setFill()
spark.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode icon")
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
let contents = """
{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try contents.write(to: outputURL.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try png.write(to: outputURL, options: .atomic)
print("Generated Next App icon at \(outputURL.path)")

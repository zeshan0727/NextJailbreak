import AppKit
import Foundation

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "TIPA/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let rect = NSRect(origin: .zero, size: size)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.30, green: 0.10, blue: 0.75, alpha: 1),
    NSColor(calibratedRed: 0.76, green: 0.13, blue: 0.43, alpha: 1)
])!
gradient.draw(in: NSBezierPath(roundedRect: rect.insetBy(dx: 25, dy: 25), xRadius: 220, yRadius: 220), angle: -35)

NSColor.white.withAlphaComponent(0.98).setStroke()
let lens = NSBezierPath(ovalIn: NSRect(x: 235, y: 315, width: 450, height: 450))
lens.lineWidth = 86
lens.stroke()
let handle = NSBezierPath()
handle.move(to: NSPoint(x: 625, y: 360))
handle.line(to: NSPoint(x: 790, y: 195))
handle.lineWidth = 86
handle.lineCapStyle = .round
handle.stroke()

let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 150, weight: .black),
    .foregroundColor: NSColor.white
]
let text = "TIPA" as NSString
let ts = text.size(withAttributes: attrs)
text.draw(at: NSPoint(x: (1024-ts.width)/2, y: 78), withAttributes: attrs)
image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: output))
print("Generated \(output)")

import AppKit
import CoreGraphics

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "NextTweaks/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

let rect = CGRect(x: 0, y: 0, width: size, height: size)
let bg = CGGradient(colorsSpace: colorSpace, colors: [c(0.02,0.025,0.08), c(0.18,0.06,0.36), c(0.03,0.21,0.36)] as CFArray, locations: [0,0.52,1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 70, y: 980), end: CGPoint(x: 950, y: 40), options: [])

func orb(x: CGFloat, y: CGFloat, radius: CGFloat, color: CGColor) {
    let colors = [color, CGColor(red: color.components![0], green: color.components![1], blue: color.components![2], alpha: 0)] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0,1])!
    ctx.drawRadialGradient(gradient, startCenter: CGPoint(x:x,y:y), startRadius: 0, endCenter: CGPoint(x:x,y:y), endRadius: radius, options: [])
}
orb(x: 220, y: 800, radius: 440, color: c(0.20,0.48,1.0,0.72))
orb(x: 820, y: 520, radius: 430, color: c(0.68,0.24,1.0,0.62))
orb(x: 500, y: 180, radius: 390, color: c(0.08,0.84,0.92,0.34))

let glassRect = CGRect(x: 190, y: 190, width: 644, height: 644)
let path = CGPath(roundedRect: glassRect, cornerWidth: 168, cornerHeight: 168, transform: nil)
ctx.saveGState()
ctx.addPath(path)
ctx.clip()
let glass = CGGradient(colorsSpace: colorSpace, colors: [c(1,1,1,0.24), c(1,1,1,0.055), c(0.65,0.76,1,0.09)] as CFArray, locations: [0,0.55,1])!
ctx.drawLinearGradient(glass, start: CGPoint(x:220,y:820), end: CGPoint(x:800,y:210), options: [])
ctx.restoreGState()

ctx.addPath(path)
ctx.setStrokeColor(c(1,1,1,0.42))
ctx.setLineWidth(8)
ctx.strokePath()

ctx.setFillColor(c(1,1,1,0.97))
let font = NSFont.systemFont(ofSize: 360, weight: .black)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white
]
let text = NSAttributedString(string: "N", attributes: attrs)
let textSize = text.size()
let nsctx = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsctx
text.draw(at: CGPoint(x: (CGFloat(size)-textSize.width)/2, y: 320))
NSGraphicsContext.restoreGraphicsState()

ctx.setFillColor(c(1,1,1,0.95))
let star = CGMutablePath()
star.move(to: CGPoint(x: 760, y: 790))
star.addLine(to: CGPoint(x: 782, y: 736))
star.addLine(to: CGPoint(x: 836, y: 714))
star.addLine(to: CGPoint(x: 782, y: 692))
star.addLine(to: CGPoint(x: 760, y: 638))
star.addLine(to: CGPoint(x: 738, y: 692))
star.addLine(to: CGPoint(x: 684, y: 714))
star.addLine(to: CGPoint(x: 738, y: 736))
star.closeSubpath()
ctx.addPath(star)
ctx.fillPath()

let fm = FileManager.default
let dir = URL(fileURLWithPath: output).deletingLastPathComponent()
try fm.createDirectory(at: dir, withIntermediateDirectories: true)
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
try contents.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
let png = rep.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: output))
print("Generated glossy Next Tweaks icon: \(output)")

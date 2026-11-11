import AppKit
import CoreGraphics
import Foundation

// App Bucket • NEXT Jailbreak studio identity.
// Deterministic, original 1024 × 1024 iOS icon rendered during every build.
let outputPath = CommandLine.arguments.dropFirst().first
    ?? "NextApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let canvas = NSSize(width: 1024, height: 1024)
let image = NSImage(size: canvas)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
func polygon(_ points: [NSPoint], fill: NSColor) {
    let path = NSBezierPath()
    guard let first = points.first else { return }
    path.move(to: first)
    points.dropFirst().forEach { path.line(to: $0) }
    path.close()
    fill.setFill()
    path.fill()
}
func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("Cannot create the App Bucket icon graphics context")
}

// Full-bleed, opaque midnight-blue / violet background. iOS supplies the mask.
let background = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        rgb(6, 14, 39).cgColor,
        rgb(24, 21, 77).cgColor,
        rgb(52, 10, 99).cgColor
    ] as CFArray,
    locations: [0, 0.55, 1]
)!
context.drawLinearGradient(
    background,
    start: CGPoint(x: 0, y: 990),
    end: CGPoint(x: 1024, y: 0),
    options: []
)

func glow(x: CGFloat, y: CGFloat, radius: CGFloat, color: NSColor) {
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color.withAlphaComponent(0.40).cgColor, color.withAlphaComponent(0).cgColor] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        gradient,
        startCenter: CGPoint(x: x, y: y),
        startRadius: 0,
        endCenter: CGPoint(x: x, y: y),
        endRadius: radius,
        options: []
    )
}
glow(x: 170, y: 720, radius: 525, color: rgb(0, 150, 255))
glow(x: 825, y: 250, radius: 525, color: rgb(187, 40, 255))

// Inset frame, designed to remain visible beneath the home-screen icon mask.
let panel = NSBezierPath(
    roundedRect: NSRect(x: 68, y: 68, width: 888, height: 888),
    xRadius: 218,
    yRadius: 218
)
rgb(5, 8, 28, 0.37).setFill()
panel.fill()
panel.lineWidth = 8
rgb(116, 101, 255, 0.70).setStroke()
panel.stroke()

// NEXT Jailbreak's prominent NJ monogram.
let logoShadow = NSShadow()
logoShadow.shadowColor = rgb(12, 119, 255, 0.70)
logoShadow.shadowBlurRadius = 25
logoShadow.shadowOffset = NSSize(width: 0, height: -5)
let logoFont = NSFont.systemFont(ofSize: 340, weight: .black)
NSAttributedString(
    string: "N",
    attributes: [
        .font: logoFont,
        .foregroundColor: rgb(245, 250, 255),
        .shadow: logoShadow
    ]
).draw(in: NSRect(x: 202, y: 525, width: 380, height: 385))
logoShadow.shadowColor = rgb(171, 68, 255, 0.70)
NSAttributedString(
    string: "J",
    attributes: [
        .font: logoFont,
        .foregroundColor: rgb(156, 84, 255),
        .shadow: logoShadow
    ]
).draw(in: NSRect(x: 492, y: 525, width: 290, height: 385))

// Orbital sweep around the J is part of the NEXT monogram.
let swoosh = NSBezierPath()
swoosh.move(to: pt(500, 705))
swoosh.curve(to: pt(767, 814), controlPoint1: pt(623, 824), controlPoint2: pt(748, 866))
swoosh.curve(to: pt(683, 660), controlPoint1: pt(789, 764), controlPoint2: pt(746, 704))
swoosh.lineWidth = 19
swoosh.lineCapStyle = .round
rgb(169, 91, 255).setStroke()
swoosh.stroke()

// Floating open-box silhouette: a recognizable app bucket at small icon sizes.
context.saveGState()
context.setShadow(offset: NSSize(width: 0, height: -18), blur: 35,
                  color: rgb(8, 5, 40, 0.85).cgColor)
polygon([pt(292, 433), pt(509, 377), pt(509, 239), pt(292, 296)],
        fill: rgb(106, 207, 255))
polygon([pt(509, 377), pt(726, 433), pt(726, 296), pt(509, 239)],
        fill: rgb(159, 73, 229))
context.restoreGState()

// Illuminated center opening.
polygon([pt(292, 433), pt(509, 512), pt(726, 433), pt(509, 377)],
        fill: rgb(8, 16, 45))
polygon([pt(292, 433), pt(509, 512), pt(509, 464), pt(366, 407)],
        fill: rgb(19, 41, 96))
polygon([pt(509, 512), pt(726, 433), pt(648, 405), pt(509, 464)],
        fill: rgb(36, 20, 88))

// Lifted flaps (cyan and orchid), crisp for iPhone home-screen rendering.
polygon([pt(292, 433), pt(509, 377), pt(438, 313), pt(223, 374)],
        fill: rgb(139, 223, 255))
polygon([pt(509, 377), pt(726, 433), pt(798, 374), pt(581, 313)],
        fill: rgb(202, 139, 255))
polygon([pt(292, 433), pt(509, 377), pt(509, 357), pt(297, 412)],
        fill: rgb(239, 248, 255, 0.80))

// Short studio wordmark under the symbol; matches in-app brand attribution.
let brand = NSAttributedString(
    string: "NEXT JAILBREAK",
    attributes: [
        .font: NSFont.systemFont(ofSize: 45, weight: .heavy),
        .foregroundColor: rgb(229, 233, 255),
        .kern: 5.5
    ]
)
brand.draw(in: NSRect(x: 235, y: 127, width: 650, height: 65))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode the App Bucket icon")
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
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
try contents.write(
    to: outputURL.deletingLastPathComponent().appendingPathComponent("Contents.json"),
    atomically: true,
    encoding: .utf8
)
try png.write(to: outputURL, options: .atomic)
print("Generated App Bucket • NEXT Jailbreak iOS icon at \(outputURL.path)")

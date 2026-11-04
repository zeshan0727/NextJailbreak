import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 3 else { fputs("Usage: GenerateIcon.swift <logo-path> <output-path>\n", stderr); exit(2) }
guard let logo = NSImage(contentsOfFile: arguments[1]) else { fputs("Unable to load Aspire logo\n", stderr); exit(3) }
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let canvas = NSRect(origin: .zero, size: size)
NSColor(calibratedRed: 0.97, green: 0.985, blue: 0.965, alpha: 1).setFill(); canvas.fill()
let border = NSBezierPath(roundedRect: canvas.insetBy(dx: 38, dy: 38), xRadius: 180, yRadius: 180)
border.lineWidth = 24; NSColor(calibratedRed: 0.10, green: 0.48, blue: 0.29, alpha: 1).setStroke(); border.stroke()
let target = NSRect(x: 92, y: 132, width: 840, height: 760)
let sourceRatio = logo.size.width / max(logo.size.height, 1); let targetRatio = target.width / target.height
let drawRect: NSRect
if sourceRatio > targetRatio { let height = target.width / sourceRatio; drawRect = NSRect(x: target.minX, y: target.midY - height / 2, width: target.width, height: height) }
else { let width = target.height * sourceRatio; drawRect = NSRect(x: target.midX - width / 2, y: target.minY, width: width, height: target.height) }
logo.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
image.unlockFocus()
guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { fputs("Unable to generate Aspire app icon\n", stderr); exit(4) }
try png.write(to: URL(fileURLWithPath: arguments[2]), options: .atomic)

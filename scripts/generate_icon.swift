import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: swift generate_icon.swift <output.iconset>\n", stderr)
    exit(1)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let entries: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func drawIcon(pixelSize: Int) -> Data? {
    let s = CGFloat(pixelSize)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    let inset = s * 0.08
    let box = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let corner = box.width * 0.22
    let bgPath = CGPath(roundedRect: box, cornerWidth: corner, cornerHeight: corner, transform: nil)

    // Obsidian Slate background
    ctx.setFillColor(CGColor(red: 0.071, green: 0.082, blue: 0.102, alpha: 1.0))
    ctx.addPath(bgPath)
    ctx.fillPath()

    ctx.setStrokeColor(CGColor(red: 0.176, green: 0.208, blue: 0.259, alpha: 1.0))
    ctx.setLineWidth(max(1.0, s * 0.02))
    ctx.addPath(bgPath)
    ctx.strokePath()

    // Geometric Shield outline (CoreGraphics origin is bottom-left)
    let sw = s * 0.46
    let sh = s * 0.52
    let sx = (s - sw) / 2.0
    let sy = (s - sh) / 2.0
    let shield = CGMutablePath()
    shield.move(to: CGPoint(x: sx + sw * 0.5, y: sy + sh))
    shield.addLine(to: CGPoint(x: sx + sw, y: sy + sh * 0.82))
    shield.addLine(to: CGPoint(x: sx + sw, y: sy + sh * 0.46))
    shield.addQuadCurve(to: CGPoint(x: sx + sw * 0.5, y: sy), control: CGPoint(x: sx + sw * 0.94, y: sy + sh * 0.14))
    shield.addQuadCurve(to: CGPoint(x: sx, y: sy + sh * 0.46), control: CGPoint(x: sx + sw * 0.06, y: sy + sh * 0.14))
    shield.addLine(to: CGPoint(x: sx, y: sy + sh * 0.82))
    shield.closeSubpath()

    ctx.setStrokeColor(CGColor(red: 0.949, green: 0.957, blue: 0.973, alpha: 0.92))
    ctx.setLineWidth(max(1.2, s * 0.036))
    ctx.setLineJoin(.round)
    ctx.addPath(shield)
    ctx.strokePath()

    // Emerald Charge Arc
    let center = CGPoint(x: s / 2.0, y: s / 2.0)
    let arcRadius = s * 0.15
    ctx.setStrokeColor(CGColor(red: 0.063, green: 0.725, blue: 0.506, alpha: 1.0))
    ctx.setLineWidth(max(1.5, s * 0.048))
    ctx.setLineCap(.round)
    ctx.addArc(center: center, radius: arcRadius, startAngle: -.pi * 0.28, endAngle: .pi * 1.28, clockwise: false)
    ctx.strokePath()

    // Geometric Bolt Cut
    let bw = s * 0.14
    let bh = s * 0.22
    let bx = (s - bw) / 2.0
    let by = (s - bh) / 2.0
    let bolt = CGMutablePath()
    bolt.move(to: CGPoint(x: bx + bw * 0.62, y: by + bh))
    bolt.addLine(to: CGPoint(x: bx + bw * 0.15, y: by + bh * 0.45))
    bolt.addLine(to: CGPoint(x: bx + bw * 0.48, y: by + bh * 0.45))
    bolt.addLine(to: CGPoint(x: bx + bw * 0.36, y: by))
    bolt.addLine(to: CGPoint(x: bx + bw * 0.86, y: by + bh * 0.56))
    bolt.addLine(to: CGPoint(x: bx + bw * 0.52, y: by + bh * 0.56))
    bolt.closeSubpath()

    ctx.setFillColor(CGColor(red: 0.063, green: 0.725, blue: 0.506, alpha: 1.0))
    ctx.addPath(bolt)
    ctx.fillPath()

    guard let cgImage = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .png, properties: [:])
}

for (filename, size) in entries {
    if let data = drawIcon(pixelSize: size) {
        try data.write(to: iconsetURL.appendingPathComponent(filename))
    }
}

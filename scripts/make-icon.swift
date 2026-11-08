// Draws the Pullie app icon and writes Resources/AppIcon.icns.
// Run with: swift scripts/make-icon.swift
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Draws the icon on a 1024×1024 canvas (origin bottom-left), scaled to `size` pixels.
func render(size: Int) -> Data {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    // Background tile, using the standard macOS icon grid (824pt body, 100pt margin).
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.3))
    ctx.addPath(bodyPath); ctx.setFillColor(color(0x4F6BF5)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    let gradient = CGGradient(colorsSpace: nil, colors: [color(0x56A8FF), color(0x5B5BF0), color(0x7A3BE0)] as CFArray,
                              locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 300, y: 924), end: CGPoint(x: 724, y: 100),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // Ghost window: where the window came from.
    let ghost = CGRect(x: 190, y: 480, width: 400, height: 300)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: ghost, cornerWidth: 36, cornerHeight: 36, transform: nil))
    ctx.setFillColor(color(0xFFFFFF, 0.12)); ctx.fillPath()
    ctx.addPath(CGPath(roundedRect: ghost, cornerWidth: 36, cornerHeight: 36, transform: nil))
    ctx.setStrokeColor(color(0xFFFFFF, 0.7)); ctx.setLineWidth(14)
    ctx.setLineDash(phase: 0, lengths: [34, 22]); ctx.setLineCap(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // Curved arrow from the ghost window down into the front window.
    ctx.saveGState()
    ctx.setStrokeColor(color(0xFFFFFF)); ctx.setFillColor(color(0xFFFFFF))
    ctx.setLineCap(.round); ctx.setLineWidth(26)
    ctx.move(to: CGPoint(x: 290, y: 450))
    ctx.addCurve(to: CGPoint(x: 340, y: 345), control1: CGPoint(x: 280, y: 390), control2: CGPoint(x: 300, y: 355))
    ctx.strokePath()
    ctx.move(to: CGPoint(x: 395, y: 345))
    ctx.addLine(to: CGPoint(x: 320, y: 395))
    ctx.addLine(to: CGPoint(x: 320, y: 295))
    ctx.closePath()
    ctx.setLineJoin(.round); ctx.setLineWidth(12)
    ctx.drawPath(using: .fillStroke)
    ctx.restoreGState()

    // Front window: where it lands.
    let front = CGRect(x: 410, y: 210, width: 430, height: 330)
    let frontPath = CGPath(roundedRect: front, cornerWidth: 40, cornerHeight: 40, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x1A1060, 0.45))
    ctx.addPath(frontPath); ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(frontPath); ctx.clip()
    ctx.setFillColor(color(0xE6E9F5))
    ctx.fill(CGRect(x: front.minX, y: front.maxY - 72, width: front.width, height: 72))
    ctx.restoreGState()

    for (i, hex) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        ctx.setFillColor(color(UInt32(hex)))
        ctx.fillEllipse(in: CGRect(x: front.minX + 34 + CGFloat(i) * 46, y: front.maxY - 50, width: 28, height: 28))
    }

    // A few content lines inside the front window.
    ctx.setFillColor(color(0xC9CEE6))
    for (y, w) in [(410.0, 300.0), (360.0, 240.0), (310.0, 270.0)] {
        ctx.addPath(CGPath(roundedRect: CGRect(x: front.minX + 40, y: y, width: w, height: 22),
                           cornerWidth: 11, cornerHeight: 11, transform: nil))
    }
    ctx.fillPath()

    let image = ctx.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try render(size: 1024).write(to: root.appendingPathComponent("Resources/AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")

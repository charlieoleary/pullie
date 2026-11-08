import AppKit

/// The menu bar icon: a simplified, single-color version of the app icon.
/// A dashed ghost window, an arrow, and the solid window it was pulled to.
enum StatusIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)

            // Ghost window: where the window came from.
            let ghost = CGRect(x: 1.25, y: 1.25, width: 10.5, height: 7)
            ctx.saveGState()
            ctx.setLineWidth(1.3)
            ctx.setLineDash(phase: 0, lengths: [2.2, 1.4])
            ctx.addPath(CGPath(roundedRect: ghost, cornerWidth: 2, cornerHeight: 2, transform: nil))
            ctx.strokePath()
            ctx.restoreGState()

            // Front window: clear a gap around it so it stands apart from the ghost, then fill it.
            let front = CGRect(x: 7.5, y: 7, width: 10, height: 9.5)
            let frontPath = CGPath(roundedRect: front, cornerWidth: 2, cornerHeight: 2, transform: nil)
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            ctx.setLineWidth(2.4)
            ctx.addPath(frontPath)
            ctx.strokePath()
            ctx.restoreGState()

            ctx.addPath(frontPath)
            ctx.fillPath()

            // Title bar divider, cut out of the solid window.
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            ctx.fill(CGRect(x: front.minX, y: front.minY + 2.6, width: front.width, height: 1))
            ctx.restoreGState()

            // Arrow curving from the ghost down into the front window.
            ctx.saveGState()
            ctx.setLineWidth(1.3)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: 2.7, y: 10.4))
            ctx.addQuadCurve(to: CGPoint(x: 4.0, y: 14.5), control: CGPoint(x: 2.7, y: 14.5))
            ctx.strokePath()
            ctx.move(to: CGPoint(x: 6.3, y: 14.5))
            ctx.addLine(to: CGPoint(x: 3.6, y: 12.3))
            ctx.addLine(to: CGPoint(x: 3.6, y: 16.7))
            ctx.closePath()
            ctx.fillPath()
            ctx.restoreGState()

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Pullie"
        return image
    }
}

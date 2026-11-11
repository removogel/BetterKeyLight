import AppKit

/// Menu bar glyph: a light panel on a stand. Filled while the light is on, outlined while off.
/// Drawn in code as a template image so it adapts to light and dark menu bars.
enum MenuBarIcon {
    static let on = make(on: true, size: 18)
    static let off = make(on: false, size: 18)

    private static let largeOn = make(on: true, size: 26)
    private static let largeOff = make(on: false, size: 26)

    static func image(on isOn: Bool) -> NSImage { isOn ? on : off }

    /// Larger version for the header of the menu.
    static func header(on isOn: Bool) -> NSImage { isOn ? largeOn : largeOff }

    static func make(on isOn: Bool, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            // All coordinates are on an 18 × 18 grid, origin bottom-left.
            let s = rect.width / 18
            func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
                NSRect(x: x * s, y: y * s, width: w * s, height: h * s)
            }
            NSColor.black.setFill()
            NSColor.black.setStroke()

            // Round base and pole
            NSBezierPath(roundedRect: box(5, 1, 8, 1.6), xRadius: 0.8 * s, yRadius: 0.8 * s).fill()
            NSBezierPath(rect: box(8.35, 2.4, 1.3, 3.4)).fill()

            // Panel
            let panel = box(3.5, 5.5, 11, 11)
            let radius = 2.7 * s
            if isOn {
                NSBezierPath(roundedRect: panel, xRadius: radius, yRadius: radius).fill()
            } else {
                let line = 1.3 * s
                let path = NSBezierPath(roundedRect: panel.insetBy(dx: line / 2, dy: line / 2),
                                        xRadius: radius - line / 2, yRadius: radius - line / 2)
                path.lineWidth = line
                path.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

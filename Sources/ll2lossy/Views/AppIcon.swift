import AppKit

enum AppIcon {
    static func make(size: CGFloat = 1024) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let cornerRadius = size * 0.22
        let iconPath = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.04, dy: size * 0.04),
                                    xRadius: cornerRadius,
                                    yRadius: cornerRadius)

        NSGraphicsContext.current?.imageInterpolation = .high

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.025)
        shadow.shadowBlurRadius = size * 0.04
        shadow.set()
        NSColor.black.withAlphaComponent(0.20).setFill()
        iconPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.07, green: 0.35, blue: 0.95, alpha: 1),
            NSColor(calibratedRed: 0.00, green: 0.63, blue: 0.65, alpha: 1)
        ])
        gradient?.draw(in: iconPath, angle: 35)

        drawWaveform(in: rect, size: size)
        drawMP3Badge(in: rect, size: size)

        return image
    }

    private static func drawWaveform(in rect: NSRect, size: CGFloat) {
        let centerY = rect.midY + size * 0.04
        let barWidth = size * 0.045
        let gap = size * 0.035
        let heights: [CGFloat] = [0.24, 0.40, 0.58, 0.34, 0.48, 0.30]
        let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
        var x = rect.midX - totalWidth / 2

        NSColor.white.withAlphaComponent(0.94).setFill()
        for height in heights {
            let h = size * height
            let bar = NSBezierPath(roundedRect: NSRect(x: x, y: centerY - h / 2, width: barWidth, height: h),
                                   xRadius: barWidth / 2,
                                   yRadius: barWidth / 2)
            bar.fill()
            x += barWidth + gap
        }
    }

    private static func drawMP3Badge(in rect: NSRect, size: CGFloat) {
        let badgeRect = NSRect(x: rect.midX - size * 0.20,
                               y: size * 0.16,
                               width: size * 0.40,
                               height: size * 0.14)
        let badge = NSBezierPath(roundedRect: badgeRect,
                                 xRadius: badgeRect.height / 2,
                                 yRadius: badgeRect.height / 2)
        NSColor(calibratedRed: 1.0, green: 0.70, blue: 0.18, alpha: 1).setFill()
        badge.fill()

        let text = "MP3" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size * 0.072, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1),
            .kern: size * 0.002
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: badgeRect.midX - textSize.width / 2,
                              y: badgeRect.midY - textSize.height / 2),
                  withAttributes: attributes)
    }
}

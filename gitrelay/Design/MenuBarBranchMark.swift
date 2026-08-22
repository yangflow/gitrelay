import AppKit

/// Draws the shared merge-arrow mark for the menu-bar status item.
///
/// The AppIcon is full-color raster artwork; a filled 16 pt square sitting
/// between system menu extras reads as a badge, so the menu bar gets the
/// monochrome merge-arrow on its own (#92). The geometry comes from
/// ``GitRelayMark`` — not from the AppIcon PNG.
///
/// Nonisolated on purpose: AppKit re-runs the drawing handler whenever the
/// backing scale or the menu-bar appearance changes, and it does not promise to
/// do that on the main actor.
nonisolated enum MenuBarBranchMark {
    /// - Parameters:
    ///   - pointSize: Fitted extent of the mark, in points.
    ///   - color: `nil` draws a template image that follows the menu-bar
    ///     appearance. Any other color draws the same shape opaquely, which is
    ///     how the failure and divergence state tints the mark red.
    static func image(
        pointSize: CGFloat,
        color: NSColor?,
        strokeScale: CGFloat = 1
    ) -> NSImage {
        let strokeColor = color ?? .black
        let image = NSImage(
            size: NSSize(width: pointSize, height: pointSize),
            flipped: false
        ) { rect in
            draw(in: rect, color: strokeColor, strokeScale: strokeScale)
            return true
        }
        image.isTemplate = color == nil
        image.accessibilityDescription = String(localized: "GitRelay")
        return image
    }

    private static func draw(in rect: NSRect, color: NSColor, strokeScale: CGFloat) {
        let bounds = GitRelayMark.markBounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let scale = min(rect.width / CGFloat(bounds.width), rect.height / CGFloat(bounds.height))
        let drawnWidth = CGFloat(bounds.width) * scale
        let drawnHeight = CGFloat(bounds.height) * scale
        let originX = rect.minX + (rect.width - drawnWidth) / 2
        let originY = rect.minY + (rect.height - drawnHeight) / 2

        // Mark coordinates are y-down; AppKit draws y-up.
        func canvasPoint(_ point: GitRelayMarkPoint) -> NSPoint {
            NSPoint(
                x: originX + CGFloat(point.x - bounds.minX) * scale,
                y: originY + drawnHeight - CGFloat(point.y - bounds.minY) * scale
            )
        }

        let lineWidth = CGFloat(GitRelayMark.strokeWidth) * scale * strokeScale

        color.setStroke()
        let paths = NSBezierPath()
        paths.lineWidth = lineWidth
        paths.lineCapStyle = .round
        paths.lineJoinStyle = .round

        for curve in GitRelayMark.mergeCurves {
            paths.move(to: canvasPoint(curve.start))
            paths.curve(
                to: canvasPoint(curve.end),
                controlPoint1: canvasPoint(curve.control1),
                controlPoint2: canvasPoint(curve.control2)
            )
        }

        let shaft = GitRelayMark.shaft
        paths.move(to: canvasPoint(shaft.start))
        paths.line(to: canvasPoint(shaft.end))
        paths.stroke()

        color.setFill()

        for node in GitRelayMark.nodes {
            let center = canvasPoint(node)
            let radius = CGFloat(GitRelayMark.nodeRadius) * scale * strokeScale
            NSBezierPath(ovalIn: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )).fill()
        }

        let arrow = NSBezierPath()
        let head = GitRelayMark.arrowHead
        arrow.move(to: canvasPoint(head[0]))
        arrow.line(to: canvasPoint(head[1]))
        arrow.line(to: canvasPoint(head[2]))
        arrow.close()
        arrow.fill()

        let notch = GitRelayMark.notchPoints
        let disc = NSBezierPath()
        disc.windingRule = .evenOdd
        let center = canvasPoint(GitRelayMark.discCenter)
        let discRadius = CGFloat(GitRelayMark.discRadius) * scale * strokeScale
        disc.appendOval(in: NSRect(
            x: center.x - discRadius,
            y: center.y - discRadius,
            width: discRadius * 2,
            height: discRadius * 2
        ))
        let cutout = NSBezierPath()
        cutout.move(to: canvasPoint(notch.tip))
        cutout.line(to: canvasPoint(notch.top))
        cutout.line(to: canvasPoint(notch.bottom))
        cutout.close()
        disc.append(cutout)
        disc.fill()
    }
}

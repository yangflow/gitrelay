import AppKit

/// Draws the shared Y-branch mark for the menu-bar status item.
///
/// The purple plate stays behind in the AppIcon. A filled 16 pt square sitting
/// between system menu extras reads as a badge, so the menu bar gets the branch
/// on its own (#92). The geometry still comes from ``GitRelayMark``, so the
/// status item and the Dock icon can only ever show the same shape.
///
/// Nonisolated on purpose: AppKit re-runs the drawing handler whenever the
/// backing scale or the menu-bar appearance changes, and it does not promise to
/// do that on the main actor.
nonisolated enum MenuBarBranchMark {
    /// - Parameters:
    ///   - pointSize: Fitted extent of the branch, in points.
    ///   - color: `nil` draws a template image that follows the menu-bar
    ///     appearance. Any other color draws the same shape opaquely, which is
    ///     how the failure and divergence state tints the mark red.
    static func image(pointSize: CGFloat, color: NSColor?) -> NSImage {
        let strokeColor = color ?? .black
        let image = NSImage(
            size: NSSize(width: pointSize, height: pointSize),
            flipped: false
        ) { rect in
            draw(in: rect, color: strokeColor)
            return true
        }
        image.isTemplate = color == nil
        image.accessibilityDescription = String(localized: "GitRelay")
        return image
    }

    private static func draw(in rect: NSRect, color: NSColor) {
        let bounds = GitRelayMark.branchBounds
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

        color.setStroke()
        let lines = NSBezierPath()
        lines.lineWidth = CGFloat(GitRelayMark.strokeWidth) * scale
        lines.lineCapStyle = .round
        lines.lineJoinStyle = .round
        for segment in GitRelayMark.segments {
            lines.move(to: canvasPoint(segment.start))
            lines.line(to: canvasPoint(segment.end))
        }
        lines.stroke()

        // One even-odd path so every hollow core stays punched out.
        color.setFill()
        let rings = NSBezierPath()
        rings.windingRule = .evenOdd
        for node in GitRelayMark.nodes {
            let center = canvasPoint(node)
            for radius in [GitRelayMark.outerRadius, GitRelayMark.innerRadius] {
                let scaled = CGFloat(radius) * scale
                rings.appendOval(in: NSRect(
                    x: center.x - scaled,
                    y: center.y - scaled,
                    width: scaled * 2,
                    height: scaled * 2
                ))
            }
        }
        rings.fill()
    }
}

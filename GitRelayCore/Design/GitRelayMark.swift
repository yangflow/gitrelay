import Foundation

/// A point on the GitRelay mark, normalized to a unit square whose origin is the
/// top-left corner and whose y axis grows downward.
nonisolated struct GitRelayMarkPoint: Equatable, Sendable {
    var x: Double
    var y: Double
}

/// A straight run of the mark, drawn with a round cap at each end.
nonisolated struct GitRelayMarkSegment: Equatable, Sendable {
    var start: GitRelayMarkPoint
    var end: GitRelayMarkPoint
}

/// A cubic Bézier curve in the mark's unit square, y-down.
nonisolated struct GitRelayMarkCurve: Equatable, Sendable {
    var start: GitRelayMarkPoint
    var control1: GitRelayMarkPoint
    var control2: GitRelayMarkPoint
    var end: GitRelayMarkPoint
}

/// An axis-aligned box in the mark's unit square, y-down.
nonisolated struct GitRelayMarkRect: Equatable, Sendable {
    var minX: Double
    var minY: Double
    var width: Double
    var height: Double

    var maxX: Double { minX + width }
    var maxY: Double { minY + height }
}

/// The GitRelay mark: two source nodes on the left whose paths merge into an
/// arrow that meets a notched destination disc on the right.
///
/// One source of truth for the menu-bar status template (#92). The AppIcon is
/// raster artwork exported from `scripts/assets/gitrelay-status-first-01.png`;
/// `MenuBarBranchMark` reads these normalized numbers so the monochrome
/// merge-arrow in the menu bar stays stable.
///
/// Coordinates are unit-square, y-down. AppKit draws y-up by default, so an
/// AppKit renderer flips y when it maps a point onto its canvas.
nonisolated enum GitRelayMark {
    // MARK: - Merge arrow

    /// Stroke weight of the merge paths and shaft.
    static let strokeWidth: Double = 0.068

    /// Radius of each solid source node.
    static let nodeRadius: Double = 0.072

    /// Outer edge of a node — where a connecting path starts.
    static var outerRadius: Double { nodeRadius + strokeWidth / 2 }

    /// Top and bottom source nodes on the left.
    static let topNode = GitRelayMarkPoint(x: 0.165, y: 0.265)
    static let bottomNode = GitRelayMarkPoint(x: 0.165, y: 0.665)

    /// Where the two incoming paths join before the shaft.
    static let mergePoint = GitRelayMarkPoint(x: 0.385, y: 0.475)

    /// Base of the arrowhead, at the end of the horizontal shaft.
    static let shaftEnd = GitRelayMarkPoint(x: 0.555, y: 0.475)

    /// Tip of the arrowhead, sitting in the destination disc notch.
    static let arrowTip = GitRelayMarkPoint(x: 0.635, y: 0.475)

    /// Half-height of the filled arrowhead triangle.
    static let arrowHalfHeight: Double = 0.065

    /// Center of the notched destination disc.
    static let discCenter = GitRelayMarkPoint(x: 0.778, y: 0.475)

    /// Radius of the destination disc.
    static let discRadius: Double = 0.112

    /// Angular spread of the disc notch opening, in radians (y-down, clockwise).
    static let notchSpread: Double = 0.62

    static var nodes: [GitRelayMarkPoint] { [topNode, bottomNode] }

    /// Curved paths from each source node into the merge point.
    static var mergeCurves: [GitRelayMarkCurve] {
        [
            GitRelayMarkCurve(
                start: edgePoint(from: topNode, towards: mergePoint),
                control1: GitRelayMarkPoint(x: 0.220, y: 0.300),
                control2: GitRelayMarkPoint(x: 0.320, y: 0.420),
                end: mergePoint
            ),
            GitRelayMarkCurve(
                start: edgePoint(from: bottomNode, towards: mergePoint),
                control1: GitRelayMarkPoint(x: 0.220, y: 0.630),
                control2: GitRelayMarkPoint(x: 0.320, y: 0.530),
                end: mergePoint
            ),
        ]
    }

    /// Horizontal shaft from the merge point to the arrow base.
    static var shaft: GitRelayMarkSegment {
        GitRelayMarkSegment(start: mergePoint, end: shaftEnd)
    }

    /// The three corners of the filled arrowhead triangle: tip, base-top, base-bottom.
    static var arrowHead: [GitRelayMarkPoint] {
        [
            arrowTip,
            GitRelayMarkPoint(x: shaftEnd.x, y: shaftEnd.y - arrowHalfHeight),
            GitRelayMarkPoint(x: shaftEnd.x, y: shaftEnd.y + arrowHalfHeight),
        ]
    }

    /// The notch tip and the two points where the notch meets the disc edge.
    /// In y-down coordinates, ``top`` sits above ``discCenter`` and ``bottom`` below it.
    static var notchPoints: (tip: GitRelayMarkPoint, top: GitRelayMarkPoint, bottom: GitRelayMarkPoint) {
        let topAngle = Double.pi + notchSpread
        let bottomAngle = Double.pi - notchSpread
        return (
            tip: GitRelayMarkPoint(
                x: discCenter.x - discRadius * 0.55,
                y: discCenter.y
            ),
            top: pointOnDisc(angle: topAngle),
            bottom: pointOnDisc(angle: bottomAngle)
        )
    }

    /// Ink extent of the whole mark, used to fit the menu-bar status item.
    static var markBounds: GitRelayMarkRect {
        let xs = nodes.map(\.x) + [arrowTip.x, discCenter.x + discRadius]
        let ys = nodes.map(\.y) + [
            discCenter.y - discRadius,
            discCenter.y + discRadius,
            arrowTip.y - arrowHalfHeight,
            arrowTip.y + arrowHalfHeight,
        ]
        let minX = (xs.min() ?? 0) - outerRadius
        let minY = (ys.min() ?? 0) - outerRadius
        let maxX = (xs.max() ?? 0) + outerRadius
        let maxY = (ys.max() ?? 0) + outerRadius
        return GitRelayMarkRect(
            minX: minX,
            minY: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    /// The point on `node`'s outer edge that faces `target`.
    static func edgePoint(
        from node: GitRelayMarkPoint,
        towards target: GitRelayMarkPoint
    ) -> GitRelayMarkPoint {
        let dx = target.x - node.x
        let dy = target.y - node.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return node }
        return GitRelayMarkPoint(
            x: node.x + dx / length * outerRadius,
            y: node.y + dy / length * outerRadius
        )
    }

    private static func pointOnDisc(angle: Double) -> GitRelayMarkPoint {
        GitRelayMarkPoint(
            x: discCenter.x + discRadius * cos(angle),
            y: discCenter.y + discRadius * sin(angle)
        )
    }
}

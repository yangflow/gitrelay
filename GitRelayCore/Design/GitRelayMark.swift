import Foundation

/// A point on the GitRelay mark, normalized to a unit square whose origin is the
/// top-left corner and whose y axis grows downward.
nonisolated struct GitRelayMarkPoint: Equatable, Sendable {
    var x: Double
    var y: Double
}

/// A straight run of the branch, drawn with a round cap at each end.
nonisolated struct GitRelayMarkSegment: Equatable, Sendable {
    var start: GitRelayMarkPoint
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

/// The GitRelay mark: a Y-shaped git branch of three hollow nodes — a trunk node
/// at the bottom feeding two branch nodes above it.
///
/// One source of truth for every place the mark ships (#92): the AppIcon plate
/// drawn by `scripts/generate-icon.swift`, and the menu-bar status item drawn by
/// `MenuBarBranchMark`. Both read these normalized numbers and scale them, so the
/// Dock, About, and menu bar can never drift apart.
///
/// Coordinates are unit-square, y-down. AppKit draws y-up by default, so an
/// AppKit renderer flips y when it maps a point onto its canvas.
nonisolated enum GitRelayMark {
    // MARK: - Branch

    /// Stroke weight of both the node rings and the lines between them.
    static let strokeWidth: Double = 0.044

    /// Radius of a ring's centerline. The hollow core is ``innerRadius`` wide.
    static let nodeRadius: Double = 0.072

    /// Outer edge of a ring — where a connecting line starts.
    static var outerRadius: Double { nodeRadius + strokeWidth / 2 }

    /// Inner edge of a ring — the hollow core punched out of the plate.
    static var innerRadius: Double { nodeRadius - strokeWidth / 2 }

    /// Where the two branch lines meet the trunk.
    static let fork = GitRelayMarkPoint(x: 0.5, y: 0.505)

    /// Trunk node, at the bottom of the Y.
    static let trunkNode = GitRelayMarkPoint(x: 0.5, y: 0.69)

    /// Branch nodes, above and to either side of the fork.
    static let leftBranchNode = GitRelayMarkPoint(x: 0.293, y: 0.283)
    static let rightBranchNode = GitRelayMarkPoint(x: 0.707, y: 0.283)

    /// Every hollow node, trunk first.
    static var nodes: [GitRelayMarkPoint] { [trunkNode, leftBranchNode, rightBranchNode] }

    /// One line per node, running from that node's outer ring edge to the fork.
    ///
    /// Starting at the outer edge rather than the center keeps the hollow core
    /// clear; the round cap tucks back under the ring stroke so the join reads as
    /// one continuous branch.
    static var segments: [GitRelayMarkSegment] {
        nodes.map { node in
            GitRelayMarkSegment(start: edgePoint(from: node, towards: fork), end: fork)
        }
    }

    /// The branch alone, without the plate.
    ///
    /// The node rings enclose everything else: the fork sits between them, and a
    /// line's round cap only ever reaches back to the ring it started from. So
    /// the union of the three outer rings is the whole ink extent, which is what
    /// the menu-bar status item fits to the bar.
    static var branchBounds: GitRelayMarkRect {
        let xs = nodes.map(\.x)
        let ys = nodes.map(\.y)
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

    /// The point on `node`'s outer ring edge that faces `target`.
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

    // MARK: - Plate

    /// Superellipse exponent for the icon plate. macOS rounded-rect icons read as
    /// continuous curvature, which a circular-corner rounded rect does not give.
    static let plateExponent: Double = 5

    /// Sample count of ``plateOutline(sampleCount:)``. High enough that the
    /// polygon is indistinguishable from the curve at 1024 px.
    static let plateSampleCount = 720

    /// Purple plate gradient, top to bottom, as sRGB components in 0...1.
    static let plateTopColor = (red: 0.443, green: 0.400, blue: 0.831)
    static let plateBottomColor = (red: 0.357, green: 0.306, blue: 0.745)

    /// The plate outline, sampled once around the superellipse.
    static func plateOutline(sampleCount: Int = plateSampleCount) -> [GitRelayMarkPoint] {
        guard sampleCount > 2 else { return [] }
        let exponent = 2 / plateExponent
        return (0..<sampleCount).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(sampleCount)
            return GitRelayMarkPoint(
                x: 0.5 + 0.5 * signedPower(cos(angle), exponent),
                y: 0.5 + 0.5 * signedPower(sin(angle), exponent)
            )
        }
    }

    private static func signedPower(_ value: Double, _ exponent: Double) -> Double {
        let magnitude = pow(abs(value), exponent)
        return value < 0 ? -magnitude : magnitude
    }
}

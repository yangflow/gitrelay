#!/usr/bin/env swift
//
// generate-icon.swift — Produce the GitRelay AppIcon asset from scratch.
//
// Run once from the repo root, on a Mac:
//     swift scripts/generate-icon.swift
//
// Writes 10 PNG files into gitrelay/Assets.xcassets/AppIcon.appiconset/
// at exact pixel dimensions (no Retina-doubling).
//
// The mark is a deep ink squircle plate carrying a white Y-shaped git branch of
// three hollow nodes (#92 / #121). Its geometry mirrors `GitRelayMark` in
// GitRelayCore/Design/GitRelayMark.swift, which is what the menu-bar status item
// draws from. A standalone `swift` script cannot import the app module, so the
// numbers below are duplicated; `GitRelayMarkTests` pins the same values so a
// change on either side fails the test suite instead of drifting silently.

import AppKit
import Foundation

let assetPath = "gitrelay/Assets.xcassets/AppIcon.appiconset"

let sizes: [(filename: String, pixels: Int)] = [
    ("icon_16.png",        16),
    ("icon_16@2x.png",     32),
    ("icon_32.png",        32),
    ("icon_32@2x.png",     64),
    ("icon_128.png",      128),
    ("icon_128@2x.png",   256),
    ("icon_256.png",      256),
    ("icon_256@2x.png",   512),
    ("icon_512.png",      512),
    ("icon_512@2x.png",  1024),
]

// MARK: - Mark geometry (mirrors GitRelayCore/Design/GitRelayMark.swift)

struct MarkPoint {
    var x: Double
    var y: Double
}

enum Mark {
    static let strokeWidth = 0.044
    static let nodeRadius = 0.072
    static var outerRadius: Double { nodeRadius + strokeWidth / 2 }
    static var innerRadius: Double { nodeRadius - strokeWidth / 2 }

    static let fork = MarkPoint(x: 0.5, y: 0.505)
    static let nodes = [
        MarkPoint(x: 0.5, y: 0.69),     // trunk
        MarkPoint(x: 0.293, y: 0.283),  // left branch
        MarkPoint(x: 0.707, y: 0.283),  // right branch
    ]

    static let plateExponent = 5.0
    static let plateSampleCount = 720

    static func edgePoint(from node: MarkPoint, towards target: MarkPoint) -> MarkPoint {
        let dx = target.x - node.x
        let dy = target.y - node.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return node }
        return MarkPoint(
            x: node.x + dx / length * outerRadius,
            y: node.y + dy / length * outerRadius
        )
    }

    static func plateOutline() -> [MarkPoint] {
        let exponent = 2 / plateExponent
        return (0..<plateSampleCount).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(plateSampleCount)
            return MarkPoint(
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

// MARK: - Palette

let plateTop = NSColor(srgbRed: 0.204, green: 0.204, blue: 0.216, alpha: 1)
let plateBottom = NSColor(srgbRed: 0.129, green: 0.129, blue: 0.141, alpha: 1)
let branchColor = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

// MARK: - Drawing

/// Unit-square, y-down mark coordinates onto an AppKit y-up canvas.
func canvasPoint(_ point: MarkPoint, size: CGFloat) -> NSPoint {
    NSPoint(x: CGFloat(point.x) * size, y: (1 - CGFloat(point.y)) * size)
}

func platePath(size: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    for (index, point) in Mark.plateOutline().enumerated() {
        let canvas = canvasPoint(point, size: size)
        if index == 0 {
            path.move(to: canvas)
        } else {
            path.line(to: canvas)
        }
    }
    path.close()
    return path
}

/// One even-odd path holding all three rings, so each hollow core stays clear.
func ringsPath(size: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.windingRule = .evenOdd
    for node in Mark.nodes {
        let center = canvasPoint(node, size: size)
        for radius in [Mark.outerRadius, Mark.innerRadius] {
            let scaled = CGFloat(radius) * size
            path.appendOval(in: NSRect(
                x: center.x - scaled,
                y: center.y - scaled,
                width: scaled * 2,
                height: scaled * 2
            ))
        }
    }
    return path
}

/// Lines from each ring's outer edge to the fork. Round caps tuck the ends back
/// under the ring stroke without reaching into the hollow core.
func branchLinesPath(size: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.lineWidth = CGFloat(Mark.strokeWidth) * size
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    for node in Mark.nodes {
        let start = Mark.edgePoint(from: node, towards: Mark.fork)
        path.move(to: canvasPoint(start, size: size))
        path.line(to: canvasPoint(Mark.fork, size: size))
    }
    return path
}

func iconPNG(pixelSize px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: px, height: px)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = ctx
    ctx.shouldAntialias = true
    ctx.imageInterpolation = .high

    let size = CGFloat(px)

    // Ink plate, slightly lighter at the top.
    let plate = platePath(size: size)
    if let gradient = NSGradient(starting: plateBottom, ending: plateTop) {
        gradient.draw(in: plate, angle: 90)
    } else {
        plateBottom.setFill()
        plate.fill()
    }

    // White Y branch.
    branchColor.setStroke()
    branchLinesPath(size: size).stroke()
    branchColor.setFill()
    ringsPath(size: size).fill()

    let tagged = rep.converting(to: .sRGB, renderingIntent: .default) ?? rep
    return tagged.representation(using: .png, properties: [:])
}

// MARK: - Main

func warn(_ message: String) {
    if let data = (message + "\n").data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

let fm = FileManager.default
if !fm.fileExists(atPath: assetPath) {
    try fm.createDirectory(atPath: assetPath, withIntermediateDirectories: true)
}

for (filename, px) in sizes {
    guard let data = iconPNG(pixelSize: px) else {
        warn("failed to encode \(filename)")
        continue
    }
    let url = URL(fileURLWithPath: "\(assetPath)/\(filename)")
    try data.write(to: url)
    let bytes = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    print("  \(filename.padding(toLength: 20, withPad: " ", startingAt: 0))  \(px)×\(px)  \(bytes)")
}

print("")
print("Wrote \(sizes.count) icon PNGs to \(assetPath)")

#!/usr/bin/env swift
//
// generate-icon.swift — Produce the GitRelay AppIcon asset from scratch.
//
// Run once from the repo root:
//     swift scripts/generate-icon.swift
//
// Writes 10 PNG files into gitrelay/Assets.xcassets/AppIcon.appiconset/
// at exact pixel dimensions (no Retina-doubling).

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

// MARK: - Palette

let canvas    = NSColor(calibratedRed: 0.082, green: 0.094, blue: 0.114, alpha: 1) // dark navy
let highlight = NSColor(calibratedRed: 0.118, green: 0.137, blue: 0.165, alpha: 1) // panel
let teal      = NSColor(calibratedRed: 0.196, green: 0.745, blue: 0.820, alpha: 1) // hairline accent
let symbol    = NSColor(calibratedRed: 0.875, green: 0.953, blue: 1.000, alpha: 1) // near-white blue

// MARK: - Drawing

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

    let size = CGFloat(px)
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let corner = size * 0.22

    // Base fill
    canvas.setFill()
    NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner).fill()

    // Inner highlight panel
    let inner = rect.insetBy(dx: size * 0.07, dy: size * 0.07)
    let innerCorner = corner * 0.70
    highlight.setFill()
    NSBezierPath(roundedRect: inner, xRadius: innerCorner, yRadius: innerCorner).fill()

    // Teal hairline inside the panel
    teal.withAlphaComponent(0.55).setStroke()
    let ring = NSBezierPath(
        roundedRect: inner.insetBy(dx: size * 0.015, dy: size * 0.015),
        xRadius: innerCorner * 0.92,
        yRadius: innerCorner * 0.92
    )
    ring.lineWidth = max(1, size * 0.01)
    ring.stroke()

    // SF Symbol: arrow.triangle.2.circlepath — relay / sync concept
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [symbol]))
    if let base = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil),
       let sym = base.withSymbolConfiguration(config) {
        let ss = sym.size
        let symbolRect = NSRect(
            x: (size - ss.width)  / 2,
            y: (size - ss.height) / 2,
            width: ss.width,
            height: ss.height
        )
        sym.draw(in: symbolRect)
    }

    return rep.representation(using: .png, properties: [:])
}

// MARK: - Main

let fm = FileManager.default
if !fm.fileExists(atPath: assetPath) {
    try fm.createDirectory(atPath: assetPath, withIntermediateDirectories: true)
}

for (filename, px) in sizes {
    guard let data = iconPNG(pixelSize: px) else {
        FileHandle.standardError.write("failed to encode \(filename)\n".data(using: .utf8)!)
        continue
    }
    let url = URL(fileURLWithPath: "\(assetPath)/\(filename)")
    try data.write(to: url)
    let bytes = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    print("  \(filename.padding(toLength: 20, withPad: " ", startingAt: 0))  \(px)×\(px)  \(bytes)")
}

print("")
print("Wrote \(sizes.count) icon PNGs to \(assetPath)")

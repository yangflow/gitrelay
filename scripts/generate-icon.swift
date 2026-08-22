#!/usr/bin/env swift
//
// generate-icon.swift — Export GitRelay AppIcon PNGs from the committed source artwork.
//
// Run from the repo root, on a Mac:
//     swift scripts/generate-icon.swift
//
// Writes 10 PNG files into gitrelay/Assets.xcassets/AppIcon.appiconset/
// at exact pixel dimensions (no Retina-doubling).
//
// The AppIcon is a raster 3D merge-arrow mark. The menu-bar status item still
// draws the monochrome Y-branch template from GitRelayMark — not this artwork.

import AppKit
import Foundation

let sourcePath = "scripts/assets/gitrelay-status-first-01.png"
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

func warn(_ message: String) {
    if let data = (message + "\n").data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

func resizeIcon(source: NSImage, pixels: Int) -> Data? {
    let target = NSSize(width: pixels, height: pixels)
    let image = NSImage(size: target)
    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(
        in: NSRect(origin: .zero, size: target),
        from: NSRect(origin: .zero, size: source.size),
        operation: .copy,
        fraction: 1
    )

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        return nil
    }
    return png
}

let fm = FileManager.default
guard fm.fileExists(atPath: sourcePath) else {
    warn("error: source artwork not found at \(sourcePath)")
    exit(1)
}

guard let source = NSImage(contentsOfFile: sourcePath) else {
    warn("error: could not load \(sourcePath)")
    exit(1)
}

if source.size != NSSize(width: 1024, height: 1024) {
    warn("warning: expected 1024×1024 source, got \(Int(source.size.width))×\(Int(source.size.height))")
}

if !fm.fileExists(atPath: assetPath) {
    try fm.createDirectory(atPath: assetPath, withIntermediateDirectories: true)
}

for (filename, px) in sizes {
    guard let data = resizeIcon(source: source, pixels: px) else {
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

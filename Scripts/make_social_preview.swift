#!/usr/bin/env swift

import AppKit

guard CommandLine.arguments.count == 4 else {
    fputs("usage: make_social_preview.swift <graph.png> <icon.png> <output.png>\n", stderr)
    exit(2)
}

let screenshotURL = URL(fileURLWithPath: CommandLine.arguments[1])
let iconURL = URL(fileURLWithPath: CommandLine.arguments[2])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])

guard let screenshot = NSImage(contentsOf: screenshotURL),
      let icon = NSImage(contentsOf: iconURL) else {
    fputs("unable to load source image\n", stderr)
    exit(1)
}

let size = NSSize(width: 1280, height: 640)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    exit(1)
}
bitmap.size = size

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    exit(1)
}
NSGraphicsContext.current = context

NSGradient(colors: [
    NSColor(calibratedRed: 0.035, green: 0.043, blue: 0.063, alpha: 1),
    NSColor(calibratedRed: 0.055, green: 0.082, blue: 0.135, alpha: 1)
])!.draw(in: NSRect(origin: .zero, size: size), angle: 0)

let glow = NSGradient(colors: [
    NSColor(calibratedRed: 0.13, green: 0.42, blue: 1.0, alpha: 0.34),
    NSColor(calibratedRed: 0.13, green: 0.42, blue: 1.0, alpha: 0)
])!
glow.draw(fromCenter: NSPoint(x: 420, y: 520), radius: 0,
          toCenter: NSPoint(x: 420, y: 520), radius: 460,
          options: [.drawsAfterEndingLocation])

icon.draw(
    in: NSRect(x: 72, y: 470, width: 92, height: 92),
    from: .zero,
    operation: .sourceOver,
    fraction: 1
)

let title = "LoopForge" as NSString
title.draw(at: NSPoint(x: 72, y: 378), withAttributes: [
    .font: NSFont.systemFont(ofSize: 58, weight: .bold),
    .foregroundColor: NSColor.white
])

let tagline = "Autonomous coding that stays\nobservable, recoverable, and verified." as NSString
tagline.draw(
    with: NSRect(x: 72, y: 250, width: 410, height: 110),
    options: [.usesLineFragmentOrigin, .usesFontLeading],
    attributes: [
        .font: NSFont.systemFont(ofSize: 26, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.88, alpha: 1)
    ]
)

let caption = "Single Loop   ·   Auto Graph   ·   Continuum Watcher" as NSString
caption.draw(at: NSPoint(x: 73, y: 178), withAttributes: [
    .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
    .foregroundColor: NSColor(calibratedRed: 0.39, green: 0.68, blue: 1, alpha: 1)
])

let footnote = "Native macOS control plane for Codex, APIs, and local models" as NSString
footnote.draw(at: NSPoint(x: 73, y: 106), withAttributes: [
    .font: NSFont.systemFont(ofSize: 15, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.62, alpha: 1)
])

let frame = NSRect(x: 510, y: 62, width: 710, height: 516)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
shadow.shadowBlurRadius = 34
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor.black.withAlphaComponent(0.2).setFill()
NSBezierPath(roundedRect: frame, xRadius: 22, yRadius: 22).fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
NSBezierPath(roundedRect: frame, xRadius: 22, yRadius: 22).addClip()

let sourceRatio = screenshot.size.width / screenshot.size.height
let targetRatio = frame.width / frame.height
var destination = frame
if sourceRatio > targetRatio {
    destination.size.width = frame.height * sourceRatio
    destination.origin.x -= (destination.width - frame.width) / 2
} else {
    destination.size.height = frame.width / sourceRatio
    destination.origin.y -= (destination.height - frame.height) / 2
}
screenshot.draw(in: destination, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

NSColor.white.withAlphaComponent(0.13).setStroke()
let border = NSBezierPath(roundedRect: frame, xRadius: 22, yRadius: 22)
border.lineWidth = 1
border.stroke()

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    exit(1)
}
try png.write(to: outputURL, options: .atomic)

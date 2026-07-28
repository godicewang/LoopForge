#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: make_icon.swift OUTPUT.png\n", stderr)
    exit(2)
}

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let outer = NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 220, yRadius: 220)
outer.addClip()
let gradient = NSGradient(colorsAndLocations:
    (NSColor(calibratedRed: 0.23, green: 0.16, blue: 0.72, alpha: 1), 0.0),
    (NSColor(calibratedRed: 0.43, green: 0.29, blue: 0.98, alpha: 1), 0.48),
    (NSColor(calibratedRed: 0.06, green: 0.76, blue: 0.80, alpha: 1), 1.0)
)!
gradient.draw(in: outer, angle: -42)

NSGraphicsContext.saveGraphicsState()
let glow = NSShadow()
glow.shadowColor = NSColor.white.withAlphaComponent(0.34)
glow.shadowBlurRadius = 42
glow.shadowOffset = .zero
glow.set()
let loop = NSBezierPath()
loop.move(to: NSPoint(x: 202, y: 512))
loop.curve(to: NSPoint(x: 512, y: 512), controlPoint1: NSPoint(x: 255, y: 690), controlPoint2: NSPoint(x: 410, y: 690))
loop.curve(to: NSPoint(x: 822, y: 512), controlPoint1: NSPoint(x: 614, y: 334), controlPoint2: NSPoint(x: 769, y: 334))
loop.curve(to: NSPoint(x: 512, y: 512), controlPoint1: NSPoint(x: 769, y: 690), controlPoint2: NSPoint(x: 614, y: 690))
loop.curve(to: NSPoint(x: 202, y: 512), controlPoint1: NSPoint(x: 410, y: 334), controlPoint2: NSPoint(x: 255, y: 334))
loop.lineWidth = 76
loop.lineCapStyle = .round
NSColor.white.setStroke()
loop.stroke()
NSGraphicsContext.restoreGraphicsState()

let spark = NSBezierPath()
spark.move(to: NSPoint(x: 776, y: 744))
spark.line(to: NSPoint(x: 796, y: 796))
spark.line(to: NSPoint(x: 848, y: 816))
spark.line(to: NSPoint(x: 796, y: 836))
spark.line(to: NSPoint(x: 776, y: 888))
spark.line(to: NSPoint(x: 756, y: 836))
spark.line(to: NSPoint(x: 704, y: 816))
spark.line(to: NSPoint(x: 756, y: 796))
spark.close()
NSColor.white.withAlphaComponent(0.93).setFill()
spark.fill()

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to render icon\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)

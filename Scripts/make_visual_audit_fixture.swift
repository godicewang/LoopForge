import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: make_visual_audit_fixture.swift <output.png>\n", stderr)
    exit(2)
}

let size = NSSize(width: 1280, height: 800)
let image = NSImage(size: size)
image.lockFocus()

NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.095, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
NSColor(calibratedRed: 0.085, green: 0.095, blue: 0.135, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 260, height: 800).fill()

func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
    text.draw(
        at: NSPoint(x: x, y: y),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color
        ]
    )
}

let primary = NSColor(calibratedRed: 0.46, green: 0.36, blue: 0.98, alpha: 1)
let bright = NSColor(calibratedWhite: 0.94, alpha: 1)
let muted = NSColor(calibratedWhite: 0.56, alpha: 1)
label("LOOPFORGE", x: 30, y: 735, size: 20, color: bright, weight: .bold)
label("Local audit · official Codex", x: 30, y: 705, size: 12, color: muted)
label("New autonomous task", x: 30, y: 640, size: 15, color: primary, weight: .semibold)
label("TASKS", x: 30, y: 575, size: 11, color: muted, weight: .semibold)
label("Repair invoice totals", x: 30, y: 530, size: 14, color: bright)
label("Build dashboard", x: 30, y: 490, size: 14, color: bright)

label("Choose where Codex will work", x: 335, y: 650, size: 32, color: bright, weight: .bold)
label("Every autonomous task starts in an explicit project folder.", x: 335, y: 610, size: 15, color: muted)

for (index, title) in ["Open existing project", "Create new project"].enumerated() {
    let x = CGFloat(335 + index * 405)
    NSColor(calibratedRed: 0.095, green: 0.11, blue: 0.16, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: 300, width: 370, height: 245), xRadius: 18, yRadius: 18).fill()
    primary.setFill()
    NSBezierPath(roundedRect: NSRect(x: x + 24, y: 463, width: 50, height: 50), xRadius: 12, yRadius: 12).fill()
    label(title, x: x + 24, y: 420, size: 19, color: bright, weight: .semibold)
    label(index == 0 ? "Select a project already on this Mac." : "Name and create a clean project folder.", x: x + 24, y: 380, size: 13, color: muted)
    label(index == 0 ? "Choose folder  →" : "Name project  →", x: x + 24, y: 330, size: 14, color: primary, weight: .semibold)
}

label("TEST FIXTURE · intentionally representative, not a product screenshot", x: 335, y: 90, size: 11, color: muted)
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode PNG\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)

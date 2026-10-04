// Draws the app icon and writes Resources/AppIcon.icns.
// Run from the repo root: swift tools/make-icon.swift
import AppKit

let side = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
let cg = ctx.cgContext
// Work top-down like the app's SwiftUI layout.
cg.translateBy(x: 0, y: CGFloat(side))
cg.scaleBy(x: 1, y: -1)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

// macOS icon grid: an 824pt rounded square centered on a 1024 canvas.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let drop = NSShadow()
drop.shadowColor = .black.withAlphaComponent(0.35)
drop.shadowBlurRadius = 24
drop.shadowOffset = NSSize(width: 0, height: 12)   // flipped: positive is down
drop.set()
color(0x1A1F33).setFill()
squircle.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
squircle.addClip()
NSGradient(starting: color(0x46558A), ending: color(0x131728))!.draw(in: body, angle: 90)
// Soft glow low in the frame, like light from the cover art.
NSGradient(starting: color(0x8A5CFF, 0.45), ending: color(0x8A5CFF, 0))!
    .draw(fromCenter: NSPoint(x: 512, y: 960), radius: 0, toCenter: NSPoint(x: 512, y: 960), radius: 520, options: [])

// The notch player, hanging from the top edge.
let panel = NSRect(x: 252, y: 100, width: 520, height: 400)
let ear: CGFloat = 28, bottom: CGFloat = 72
let shape = NSBezierPath()
shape.move(to: NSPoint(x: panel.minX, y: panel.minY))
shape.appendArc(from: NSPoint(x: panel.minX + ear, y: panel.minY),
                to: NSPoint(x: panel.minX + ear, y: panel.maxY), radius: ear)
shape.appendArc(from: NSPoint(x: panel.minX + ear, y: panel.maxY),
                to: NSPoint(x: panel.maxX, y: panel.maxY), radius: bottom)
shape.appendArc(from: NSPoint(x: panel.maxX - ear, y: panel.maxY),
                to: NSPoint(x: panel.maxX - ear, y: panel.minY), radius: bottom)
shape.appendArc(from: NSPoint(x: panel.maxX - ear, y: panel.minY),
                to: NSPoint(x: panel.maxX, y: panel.minY), radius: ear)
shape.close()

NSGraphicsContext.saveGraphicsState()
let lift = NSShadow()
lift.shadowColor = .black.withAlphaComponent(0.45)
lift.shadowBlurRadius = 40
lift.shadowOffset = NSSize(width: 0, height: 18)
lift.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

// Cover art.
let art = NSBezierPath(roundedRect: NSRect(x: 302, y: 200, width: 140, height: 140), xRadius: 28, yRadius: 30)
NSGraphicsContext.saveGraphicsState()
art.addClip()
NSGradient(starting: color(0xFF5F8F), ending: color(0x7B4DFF))!.draw(in: art.bounds, angle: -45)
NSGraphicsContext.restoreGraphicsState()

// Title and artist.
color(0xFFFFFF, 0.95).setFill()
NSBezierPath(roundedRect: NSRect(x: 468, y: 228, width: 160, height: 28), xRadius: 15, yRadius: 15).fill()
color(0xFFFFFF, 0.42).setFill()
NSBezierPath(roundedRect: NSRect(x: 468, y: 278, width: 110, height: 22), xRadius: 11, yRadius: 11).fill()

// Visualizer.
color(0x1ED760).setFill()
let heights: [CGFloat] = [42, 84, 58, 28]
for (i, h) in heights.enumerated() {
    let x = 652 + CGFloat(i) * 20
    NSBezierPath(roundedRect: NSRect(x: x, y: 270 - h / 2, width: 11, height: h), xRadius: 6, yRadius: 6).fill()
}

// Progress bar.
color(0xFFFFFF, 0.18).setFill()
NSBezierPath(roundedRect: NSRect(x: 302, y: 392, width: 420, height: 13), xRadius: 7, yRadius: 7).fill()
color(0xFFFFFF, 0.9).setFill()
NSBezierPath(roundedRect: NSRect(x: 302, y: 392, width: 255, height: 13), xRadius: 7, yRadius: 7).fill()

NSGraphicsContext.restoreGraphicsState()   // squircle clip
NSGraphicsContext.restoreGraphicsState()

// Write an .iconset and convert it.
let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
let master = NSImage(size: NSSize(width: side, height: side))
master.addRepresentation(rep)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        NSGraphicsContext.current?.imageInterpolation = .high
        master.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! out.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
try! fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/dev/null"))
print(iconutil.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")

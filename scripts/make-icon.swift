// Renders Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // macOS icon grid: 824/1024 body with ~185 corner radius.
    let inset = s * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let shape = NSBezierPath(roundedRect: body, xRadius: s * 185 / 1024, yRadius: s * 185 / 1024)
    NSGradient(colors: [NSColor(srgbRed: 0.20, green: 0.24, blue: 0.36, alpha: 1),
                        NSColor(srgbRed: 0.09, green: 0.10, blue: 0.16, alpha: 1)])!.draw(in: shape, angle: -90)

    let n = 4, pad = body.width * 0.14, gap = body.width * 0.035
    let area = body.insetBy(dx: pad, dy: pad)
    let cell = (area.width - gap * CGFloat(n - 1)) / CGFloat(n)
    for row in 0..<n {
        for col in 0..<n {
            let r = NSRect(x: area.minX + CGFloat(col) * (cell + gap), y: area.maxY - CGFloat(row + 1) * cell - CGFloat(row) * gap,
                           width: cell, height: cell)
            NSColor.white.withAlphaComponent(0.13).setFill()
            NSBezierPath(roundedRect: r, xRadius: cell * 0.18, yRadius: cell * 0.18).fill()
        }
    }
    // Highlighted 2x2 selection, upper left.
    let sel = NSRect(x: area.minX, y: area.maxY - cell * 2 - gap, width: cell * 2 + gap, height: cell * 2 + gap)
    NSGradient(colors: [NSColor(srgbRed: 0.35, green: 0.70, blue: 1.0, alpha: 1),
                        NSColor(srgbRed: 0.16, green: 0.45, blue: 0.98, alpha: 1)])!
        .draw(in: NSBezierPath(roundedRect: sel, xRadius: cell * 0.18, yRadius: cell * 0.18), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")

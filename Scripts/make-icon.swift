import AppKit

func render(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = s * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    shape.addClip()
    NSGradient(colors: [NSColor(red: 0.06, green: 0.06, blue: 0.13, alpha: 1),
                        NSColor(red: 0.16, green: 0.10, blue: 0.30, alpha: 1)])!.draw(in: rect, angle: -60)

    let glow = NSGradient(colors: [NSColor(red: 0.55, green: 0.42, blue: 1, alpha: 0.55), .clear])!
    glow.draw(fromCenter: NSPoint(x: rect.midX, y: rect.midY + rect.height * 0.05), radius: 0,
              toCenter: NSPoint(x: rect.midX, y: rect.midY + rect.height * 0.05), radius: rect.width * 0.55, options: [])

    let hills = NSBezierPath()
    hills.move(to: NSPoint(x: rect.minX, y: rect.minY + rect.height * 0.30))
    hills.curve(to: NSPoint(x: rect.maxX, y: rect.minY + rect.height * 0.24),
                controlPoint1: NSPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + rect.height * 0.48),
                controlPoint2: NSPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.08))
    hills.line(to: NSPoint(x: rect.maxX, y: rect.minY))
    hills.line(to: NSPoint(x: rect.minX, y: rect.minY))
    hills.close()
    NSColor.white.withAlphaComponent(0.10).setFill()
    hills.fill()

    let triangleHeight = rect.width * 0.34
    let center = NSPoint(x: rect.midX + rect.width * 0.03, y: rect.midY + rect.height * 0.05)
    let play = NSBezierPath()
    play.move(to: NSPoint(x: center.x - triangleHeight * 0.45, y: center.y + triangleHeight * 0.52))
    play.line(to: NSPoint(x: center.x + triangleHeight * 0.55, y: center.y))
    play.line(to: NSPoint(x: center.x - triangleHeight * 0.45, y: center.y - triangleHeight * 0.52))
    play.close()
    play.lineJoinStyle = .round
    play.lineWidth = rect.width * 0.03
    NSColor.white.setFill()
    NSColor.white.setStroke()
    play.fill()
    play.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (name, size) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                     ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try render(size: size).representation(using: .png, properties: [:])!
        .write(to: out.appendingPathComponent("icon_\(name).png"))
}

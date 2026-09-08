import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let size = CGFloat(pixels)
    let inset = size * 0.045
    let background = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2), xRadius: size * 0.22, yRadius: size * 0.22)
    NSColor(calibratedRed: 0.09, green: 0.14, blue: 0.19, alpha: 1).setFill()
    background.fill()
    let ring = NSBezierPath(ovalIn: NSRect(x: size * 0.23, y: size * 0.23, width: size * 0.54, height: size * 0.54))
    ring.lineWidth = size * 0.038
    NSColor(calibratedRed: 0.34, green: 0.87, blue: 0.71, alpha: 1).setStroke()
    ring.stroke()
    let bolt = NSBezierPath()
    bolt.move(to: NSPoint(x: size * 0.55, y: size * 0.78))
    bolt.line(to: NSPoint(x: size * 0.35, y: size * 0.47))
    bolt.line(to: NSPoint(x: size * 0.49, y: size * 0.47))
    bolt.line(to: NSPoint(x: size * 0.44, y: size * 0.22))
    bolt.line(to: NSPoint(x: size * 0.66, y: size * 0.55))
    bolt.line(to: NSPoint(x: size * 0.52, y: size * 0.55))
    bolt.close()
    NSColor(calibratedRed: 0.62, green: 0.99, blue: 0.82, alpha: 1).setFill()
    bolt.fill()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

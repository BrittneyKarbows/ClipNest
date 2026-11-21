import AppKit

// Vector-drawn original icon; no external image dependencies.
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
func draw(size: Int) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let outer = NSBezierPath(roundedRect: NSRect(x: 50, y: 50, width: 924, height: 924), xRadius: 211, yRadius: 211)
    NSGradient(starting: NSColor(calibratedRed: 1, green: 0.80, blue: 0.25, alpha: 1), ending: NSColor(calibratedRed: 0.96, green: 0.40, blue: 0.08, alpha: 1))!.draw(in: outer, angle: -55)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor(calibratedRed: 0.57, green: 0.20, blue: 0.03, alpha: 0.30); shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width: 0, height: -22); shadow.set()
    NSColor(calibratedRed: 1, green: 0.89, blue: 0.62, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 241, y: 195, width: 543, height: 626), xRadius: 64, yRadius: 64).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor(calibratedRed: 1, green: 0.985, blue: 0.94, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 277, y: 235, width: 471, height: 542), xRadius: 38, yRadius: 38).fill()
    NSColor(calibratedRed: 0.85, green: 0.40, blue: 0.12, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 389, y: 742, width: 247, height: 104), xRadius: 34, yRadius: 34).fill()
    NSColor(calibratedRed: 1, green: 0.82, blue: 0.32, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 413, y: 771, width: 199, height: 54), xRadius: 19, yRadius: 19).fill()
    let lineColor = NSColor(calibratedRed: 0.92, green: 0.62, blue: 0.27, alpha: 1)
    for (y, width) in [(623.0, 313.0), (529.0, 313.0), (435.0, 223.0)] {
        lineColor.setFill(); NSBezierPath(roundedRect: NSRect(x: 356, y: y, width: width, height: 26), xRadius: 13, yRadius: 13).fill()
    }
    NSColor(calibratedRed: 1, green: 0.66, blue: 0.13, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 629, y: 190, width: 182, height: 182)).fill()
    let check = NSBezierPath(); check.move(to: NSPoint(x: 678, y: 283)); check.line(to: NSPoint(x: 708, y: 253)); check.line(to: NSPoint(x: 765, y: 313)); check.lineWidth = 17; check.lineCapStyle = .round; check.lineJoinStyle = .round; NSColor.white.setStroke(); check.stroke()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("Cannot render icon") }
    try png.write(to: directory.appendingPathComponent("\(size).png"))
}
for size in [16, 32, 64, 128, 256, 512, 1024] { try draw(size: size) }

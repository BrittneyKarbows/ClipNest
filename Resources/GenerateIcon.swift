import AppKit

// Packages the approved black-and-white artwork into macOS icon sizes.
// Usage: xcrun swift Resources/GenerateIcon.swift OUTPUT_DIRECTORY [SOURCE_PNG]
let arguments = CommandLine.arguments
if arguments.count < 2 {
    fputs("Usage: swift GenerateIcon.swift OUTPUT_DIRECTORY [SOURCE_PNG]\n", stderr)
    exit(1)
}
let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let sourceURL = arguments.count > 2
    ? URL(fileURLWithPath: arguments[2])
    : URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("AppIcon-source.png")
guard let source = NSImage(contentsOf: sourceURL) else {
    fputs("Cannot read source artwork.\n", stderr)
    exit(1)
}
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
func draw(size: Int) throws {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
        fatalError("Cannot allocate icon bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    NSGraphicsContext.current?.imageInterpolation = .high
    let tile = NSRect(x: 50, y: 50, width: 924, height: 924)
    let mask = NSBezierPath(roundedRect: tile, xRadius: 211, yRadius: 211)
    mask.addClip()
    NSColor.white.setFill(); mask.fill()
    source.draw(in: tile, from: .zero, operation: .sourceOver, fraction: 1,
        respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Cannot encode icon PNG")
    }
    try png.write(to: directory.appendingPathComponent("\(size).png"))
}
for size in [16, 32, 64, 128, 256, 512, 1024] { try draw(size: size) }

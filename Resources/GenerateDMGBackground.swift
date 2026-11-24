import AppKit

// Native, editable installer artwork; no generated photo or user data is embedded.
// Usage: swift GenerateDMGBackground.swift OUTPUT_DIRECTORY VERSION
let args = CommandLine.arguments
if args.count < 3 { fputs("Usage: swift GenerateDMGBackground.swift OUTPUT_DIRECTORY VERSION\n", stderr); exit(1) }
let output = URL(fileURLWithPath: args[1], isDirectory: true)
let version = args[2]
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let icon = NSImage(contentsOf: resources.appendingPathComponent("AppIcon.png"))
let size = NSSize(width: 800, height: 600)
let ink = NSColor(white: 0.10, alpha: 1)
let secondary = NSColor(white: 0.43, alpha: 1)
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: size.height - y - h, width: w, height: h)
}
func text(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat, font: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = NSColor(white: 0.10, alpha: 1), alignment: NSTextAlignment = .left) {
    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = alignment
    (value as NSString).draw(in: rect(x, y, width, font * 1.7), withAttributes: [
        .font: NSFont.systemFont(ofSize: font, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph
    ])
}
func card(x: CGFloat, label: String) {
    let frame = NSBezierPath(roundedRect: rect(x, 205, 220, 172), xRadius: 20, yRadius: 20)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.035); shadow.shadowBlurRadius = 20; shadow.shadowOffset = NSSize(width: 0, height: -7); shadow.set()
    NSColor.white.setFill(); frame.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor(white: 0.88, alpha: 1).setStroke(); frame.lineWidth = 1; frame.stroke()
    text(label, x: x + 18, y: 219, width: 184, font: 10, weight: .medium, color: secondary)
}
for scale in [1, 2] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800 * scale, pixelsHigh: 600 * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor(white: 0.965, alpha: 1).setFill(); NSRect(origin: .zero, size: size).fill()
    icon?.draw(in: rect(48, 43, 34, 34), from: .zero, operation: .sourceOver, fraction: 1)
    text("剪藏 · ClipNest", x: 92, y: 49, width: 390, font: 16, weight: .semibold)
    text("把剪藏，放进你的 Mac。", x: 52, y: 108, width: 700, font: 29, weight: .semibold)
    text("将剪藏拖入「应用程序」，让每一次复制都有归处。", x: 53, y: 152, width: 695, font: 14, color: secondary)
    card(x: 118, label: "01  /  随手复制")
    card(x: 462, label: "02  /  好好收藏")
    // A restrained paper trail joins the two real Finder icons.
    let trail = NSBezierPath()
    trail.move(to: NSPoint(x: 353, y: size.height - 284)); trail.line(to: NSPoint(x: 447, y: size.height - 284))
    trail.lineWidth = 1.3; trail.setLineDash([3, 5], count: 2, phase: 0)
    NSColor(white: 0.64, alpha: 1).setStroke(); trail.stroke()
    let arrow = NSBezierPath(); arrow.move(to: NSPoint(x: 441, y: size.height - 279)); arrow.line(to: NSPoint(x: 447, y: size.height - 284)); arrow.line(to: NSPoint(x: 441, y: size.height - 289)); arrow.lineWidth = 1.3; arrow.stroke()
    let paper = NSBezierPath(roundedRect: rect(386, 267, 27, 34), xRadius: 5, yRadius: 5)
    NSColor.white.setFill(); paper.fill(); NSColor(white: 0.56, alpha: 1).setStroke(); paper.lineWidth = 1; paper.stroke()
    for y in [277.0, 284.0, 291.0] {
        let line = NSBezierPath(); line.move(to: NSPoint(x: 392, y: size.height - y)); line.line(to: NSPoint(x: y == 291 ? 402 : 407, y: size.height - y)); line.lineWidth = 1.3; line.lineCapStyle = .round; line.stroke()
    }
    text("拖动安装", x: 353, y: 316, width: 94, font: 11, color: secondary, alignment: .center)
    let divider = NSBezierPath(); divider.move(to: NSPoint(x: 52, y: size.height - 427)); divider.line(to: NSPoint(x: 748, y: size.height - 427)); divider.lineWidth = 1; NSColor(white: 0.87, alpha: 1).setStroke(); divider.stroke()
    text("\(version)  ·  Apple Silicon  ·  macOS 13+", x: 53, y: 443, width: 450, font: 11, color: secondary)
    text("本地保存 · 无需账号", x: 518, y: 443, width: 230, font: 11, color: secondary, alignment: .right)
    text("完成后，在「应用程序」中打开剪藏。", x: 53, y: 472, width: 690, font: 12, color: secondary)
    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "installer.png" : "installer@2x.png"
    try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}

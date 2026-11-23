import AppKit

extension NSImage {
    // Read bundled artwork directly so an OS icon cache cannot show an older release.
    static let clipNestIcon: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon-BlackWhite", withExtension: "icns"),
           let image = NSImage(contentsOf: url) { return image }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }()
}

struct IconPalette {
    let background: NSColor
    let foreground: NSColor

    static let neutral = IconPalette(background: NSColor(srgbRed: 0.47, green: 0.49, blue: 0.52, alpha: 1))

    init(background: NSColor) {
        self.background = background
        let rgb = background.usingColorSpace(.sRGB) ?? .gray
        func linear(_ value: CGFloat) -> CGFloat { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        foreground = 1.05 / (luminance + 0.05) >= 4.5 ? .white : NSColor(srgbRed: 0.10, green: 0.12, blue: 0.15, alpha: 1)
    }

    static func extract(from image: NSImage) -> IconPalette {
        let size = 48
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return .neutral }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        // A hue histogram avoids mixing a multicolored icon into a muddy average.
        // Favor the center emblem and ignore transparent pixels, white paper,
        // dark outlines, and shadows around macOS app icons.
        struct Bucket { var weight: CGFloat = 0; var red: CGFloat = 0; var green: CGFloat = 0; var blue: CGFloat = 0 }
        var buckets = Array(repeating: Bucket(), count: 24)
        for y in 0..<size {
            for x in 0..<size {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), color.alphaComponent > 0.7 else { continue }
                var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
                color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                guard saturation > 0.25, brightness > 0.28 else { continue }
                let dx = (CGFloat(x) + 0.5) / CGFloat(size) - 0.5
                let dy = (CGFloat(y) + 0.5) / CGFloat(size) - 0.5
                let center = 1 + 12 * exp(-60 * (dx * dx + dy * dy))
                let weight = saturation * saturation * alpha * center
                let index = min(23, Int(hue * 24))
                buckets[index].weight += weight
                buckets[index].red += color.redComponent * weight
                buckets[index].green += color.greenComponent * weight
                buckets[index].blue += color.blueComponent * weight
            }
        }
        guard let winner = buckets.max(by: { $0.weight < $1.weight }), winner.weight > 8 else { return .neutral }
        let dominant = NSColor(srgbRed: winner.red / winner.weight, green: winner.green / winner.weight, blue: winner.blue / winner.weight, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        dominant.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return IconPalette(background: NSColor(hue: hue, saturation: min(0.93, max(0.64, saturation)), brightness: min(0.94, max(0.64, brightness)), alpha: 1))
    }
}

import AppKit

// Build-time only: reuse the same SF Symbol as the app's Ethernet indicator.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let symbol = NSImage(systemSymbolName: "display", accessibilityDescription: nil)!
    .withSymbolConfiguration(.init(pointSize: 16, weight: .regular)
        .applying(.preferringMonochrome())
        .applying(.init(paletteColors: [.white, .clear])))!

for (name, pixels) in [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256),
    ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)
] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(pixels) / 1024)
    scale.concat()

    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
                            xRadius: 186, yRadius: 186)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.systemBlue.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(srgbRed: 0.12, green: 0.65, blue: 1, alpha: 1),
               ending: NSColor(srgbRed: 0, green: 0.34, blue: 0.91, alpha: 1))!
        .draw(in: tile, angle: -90)
    let width: CGFloat = 574
    let height = width * symbol.size.height / symbol.size.width
    symbol.draw(in: NSRect(x: (1024 - width) / 2, y: (1024 - height) / 2,
                           width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()

    let png = bitmap.representation(using: .png, properties: [:])!
    precondition(NSBitmapImageRep(data: png)?.pixelsWide == pixels)
    try png.write(to: output.appendingPathComponent("icon_\(name).png"))
}

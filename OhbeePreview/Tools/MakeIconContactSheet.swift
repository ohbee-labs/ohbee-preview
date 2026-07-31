import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: MakeIconContactSheet <iconset-directory> <output.png>\n", stderr)
    exit(2)
}

let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let samples: [(String, String)] = [
    ("16×16", "icon_16x16.png"),
    ("32×32", "icon_32x32.png"),
    ("64×64", "icon_32x32@2x.png"),
    ("128×128", "icon_128x128.png"),
    ("256×256", "icon_256x256.png"),
    ("512×512", "icon_512x512.png"),
    ("1024×1024", "icon_512x512@2x.png")
]

let canvasSize = NSSize(width: 1_400, height: 560)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("unable to allocate contact sheet\n", stderr)
    exit(3)
}

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("unable to create drawing context\n", stderr)
    exit(4)
}
NSGraphicsContext.current = context
NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
NSRect(origin: .zero, size: canvasSize).fill()

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
    .foregroundColor: NSColor.white
]
let labelAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .medium),
    .foregroundColor: NSColor.white
]
NSAttributedString(
    string: "Ohbee Preview — AppIcon v1.0.1",
    attributes: titleAttributes
).draw(at: NSPoint(x: 28, y: 510))

let tileWidth: CGFloat = 186
for (index, sample) in samples.enumerated() {
    guard let image = NSImage(contentsOf: iconset.appendingPathComponent(sample.1)) else {
        fputs("unable to load \(sample.1)\n", stderr)
        exit(5)
    }
    let x = 28 + CGFloat(index) * (tileWidth + 10)
    NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
    NSBezierPath(
        roundedRect: NSRect(x: x, y: 245, width: tileWidth, height: 230),
        xRadius: 18,
        yRadius: 18
    ).fill()
    image.draw(
        in: NSRect(x: x + 18, y: 275, width: 150, height: 150),
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.none]
    )
    NSAttributedString(
        string: sample.0,
        attributes: labelAttributes.merging(
            [.foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 1)],
            uniquingKeysWith: { _, new in new }
        )
    ).draw(at: NSPoint(x: x + 18, y: 255))

    NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
    NSBezierPath(
        roundedRect: NSRect(x: x, y: 45, width: tileWidth, height: 170),
        xRadius: 18,
        yRadius: 18
    ).fill()
    let nativeSize = min(CGFloat(image.representations.first?.pixelsWide ?? 0), 96)
    image.draw(
        in: NSRect(
            x: x + (tileWidth - nativeSize) / 2,
            y: 92 + (96 - nativeSize) / 2,
            width: nativeSize,
            height: nativeSize
        ),
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    NSAttributedString(
        string: "native ≤96 px",
        attributes: labelAttributes
    ).draw(at: NSPoint(x: x + 18, y: 62))
}

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("unable to encode contact sheet\n", stderr)
    exit(6)
}
try png.write(to: output, options: .atomic)

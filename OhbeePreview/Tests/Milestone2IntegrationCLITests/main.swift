import AppKit
import Foundation

enum Milestone2IntegrationFailure: Error {
    case expectation(String)
    case timeout(String)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw Milestone2IntegrationFailure.expectation(message)
    }
}

private func makePNG(at url: URL, color: NSColor) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 32,
        pixelsHigh: 16,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw Milestone2IntegrationFailure.expectation("Could not create bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    color.withAlphaComponent(0.5).setFill()
    NSRect(x: 0, y: 0, width: 32, height: 16).fill()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw Milestone2IntegrationFailure.expectation("Could not encode PNG")
    }
    try data.write(to: url)
}

@MainActor
private func waitUntil(
    _ description: String,
    predicate: @escaping @MainActor () -> Bool
) async throws {
    for _ in 0..<200 {
        if predicate() {
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw Milestone2IntegrationFailure.timeout(description)
}

@main
@MainActor
enum Milestone2IntegrationCLITests {
    static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohbee-milestone2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let image1 = root.appendingPathComponent("image1.png")
        let image2 = root.appendingPathComponent("image2.png")
        let corrupt = root.appendingPathComponent("image3.png")
        try makePNG(at: image1, color: .systemOrange)
        try makePNG(at: image2, color: .systemBlue)
        try Data("corrupt".utf8).write(to: corrupt)
        let originalBytes = try Data(contentsOf: image1)
        let originalAttributes = try FileManager.default.attributesOfItem(
            atPath: image1.path
        )

        let coldLaunchDelegate = AppDelegate()
        let coldLaunchModel = AppModel()
        coldLaunchDelegate.application(NSApplication.shared, open: [image1])
        coldLaunchDelegate.application(NSApplication.shared, open: [image2])
        coldLaunchDelegate.attach(model: coldLaunchModel)
        try await waitUntil("latest pending cold-launch URL") {
            coldLaunchModel.displayedImage?.sourceURL
                == image2.standardizedFileURL
        }
        try expect(
            coldLaunchModel.displayedImage?.sourceURL
                == image2.standardizedFileURL,
            "Cold launch delivered an obsolete pending URL"
        )

        let model = AppModel()
        try expect(!model.canInspectImage, "Inspection began enabled without an image")

        model.open(url: image1)
        try await waitUntil("initial image") {
            model.displayedImage?.sourceURL == image1.standardizedFileURL
                && model.canInspectImage
        }
        try await waitUntil("folder discovery") {
            model.canNavigateNext
        }
        try expect(model.viewportState.mode == .fit, "Initial image was not Fit")
        let displayedTIFF = model.displayedImage?.image.tiffRepresentation
        let displayedBitmap = displayedTIFF.flatMap(NSBitmapImageRep.init(data:))
        try expect(
            displayedBitmap?.hasAlpha == true,
            "Transparent PNG alpha was not preserved"
        )

        for _ in 0..<10 {
            model.navigateNext()
            model.zoomIn()
            model.navigatePrevious()
            model.rotateRight()
        }
        try await waitUntil("rapid navigation with inspection commands") {
            model.displayedImage?.sourceURL == image1.standardizedFileURL
                && model.canInspectImage
        }
        try expect(
            model.viewportState.mode == .fit
                && model.viewportState.rotation == .zero,
            "Rapid navigation corrupted current viewport state"
        )

        model.showActualSize()
        try expect(
            model.viewportState.mode == .actualSize,
            "Actual Size command failed"
        )
        model.zoomIn()
        try expect(
            model.viewportState.mode == .manual
                && model.viewportState.scale == 1.25,
            "Zoom In command failed"
        )
        model.zoomOut()
        try expect(model.viewportState.scale == 1, "Zoom Out command failed")
        model.fitToWindow()
        try expect(model.viewportState.mode == .fit, "Fit command failed")

        model.rotateRight()
        try expect(
            model.viewportState.rotation == .right90,
            "Rotate Right command failed"
        )
        model.rotateLeft()
        try expect(
            model.viewportState.rotation == .zero,
            "Rotate Left command failed"
        )
        for _ in 0..<4 {
            model.rotateRight()
        }
        try expect(
            model.viewportState.rotation == .zero,
            "Four rotations did not return to the original orientation"
        )

        model.rotateRight()
        model.navigateNext()
        try await waitUntil("second image") {
            model.displayedImage?.sourceURL == image2.standardizedFileURL
                && model.canInspectImage
        }
        try expect(
            model.viewportState.mode == .fit
                && model.viewportState.rotation == .zero,
            "Viewport state leaked to a newly selected image"
        )

        model.navigatePrevious()
        try await waitUntil("return to first image") {
            model.displayedImage?.sourceURL == image1.standardizedFileURL
                && model.canInspectImage
        }
        try expect(
            model.viewportState.mode == .fit
                && model.viewportState.rotation == .right90,
            "Per-image session rotation was not restored in Fit mode"
        )

        model.navigateNext()
        try await waitUntil("second image before corrupt item") {
            model.displayedImage?.sourceURL == image2.standardizedFileURL
                && model.canInspectImage
        }
        model.navigateNext()
        try await waitUntil("corrupt image failure") {
            !model.canInspectImage && model.canNavigatePrevious
        }
        try expect(
            model.displayedImage?.sourceURL == image2.standardizedFileURL,
            "Decode failure discarded the previously displayed image"
        )

        let finalBytes = try Data(contentsOf: image1)
        let finalAttributes = try FileManager.default.attributesOfItem(
            atPath: image1.path
        )
        try expect(
            finalBytes == originalBytes,
            "Inspection controls modified source bytes"
        )
        try expect(
            finalAttributes[.modificationDate] as? Date
                == originalAttributes[.modificationDate] as? Date,
            "Inspection controls modified source metadata"
        )

        print("PASS: 18 Image Inspection Controls integration checks")
    }
}

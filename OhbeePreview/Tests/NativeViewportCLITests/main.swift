import AppKit
import Foundation
import OhbeeStage2Core

enum NativeViewportTestFailure: Error {
    case expectation(String)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw NativeViewportTestFailure.expectation(message)
    }
}

@MainActor
private func expectCentered(
    _ scrollView: InspectionScrollView,
    axis: NSLayoutConstraint.Orientation,
    _ message: String
) throws {
    let clipBounds = scrollView.contentView.bounds
    let canvasFrame = scrollView.canvas.frame
    let difference: CGFloat
    switch axis {
    case .horizontal:
        difference = abs(clipBounds.midX - canvasFrame.midX)
    case .vertical:
        difference = abs(clipBounds.midY - canvasFrame.midY)
    @unknown default:
        difference = .infinity
    }
    try expect(difference < 0.01, message)
}

@main
@MainActor
enum NativeViewportCLITests {
    static func main() throws {
        _ = NSApplication.shared
        let scrollView = InspectionScrollView(
            frame: NSRect(x: 0, y: 0, width: 1_000, height: 800)
        )
        let image = NSImage(size: NSSize(width: 4_000, height: 2_000))

        scrollView.canvas.configure(
            image: image,
            pixelSize: CGSize(width: 4_000, height: 2_000),
            backingScale: 2,
            rotation: .zero,
            accessibilityLabel: "Test image"
        )
        try expect(
            scrollView.canvas.frame.width == 2_000
                && scrollView.canvas.frame.height == 1_000,
            "Actual-size document geometry was incorrect"
        )

        scrollView.applyMagnification(0.5, preserveCenter: false)
        try expect(
            abs(scrollView.magnification - 0.5) < 0.0001,
            "Fit magnification was not applied"
        )

        scrollView.applyMagnification(1, preserveCenter: true)
        try expect(
            abs(scrollView.magnification - 1) < 0.0001,
            "Actual Size magnification was not applied"
        )

        scrollView.canvas.configure(
            image: image,
            pixelSize: CGSize(width: 4_000, height: 2_000),
            backingScale: 2,
            rotation: .right90,
            accessibilityLabel: "Rotated test image"
        )
        try expect(
            scrollView.canvas.frame.width == 1_000
                && scrollView.canvas.frame.height == 2_000,
            "Rotation did not swap document dimensions"
        )

        scrollView.applyMagnification(100, preserveCenter: false)
        try expect(
            scrollView.magnification == CGFloat(ViewportState.maximumScale),
            "Native viewport exceeded maximum magnification"
        )
        scrollView.applyMagnification(0.001, preserveCenter: false)
        try expect(
            scrollView.magnification == CGFloat(ViewportState.minimumScale),
            "Native viewport exceeded minimum magnification"
        )

        try expect(
            scrollView.canvas.accessibilityRole() == .image,
            "Canvas did not expose the image accessibility role"
        )

        for index in 0..<1_000 {
            autoreleasepool {
                let rotation = QuarterTurn(rawValue: index % 4) ?? .zero
                scrollView.canvas.configure(
                    image: image,
                    pixelSize: CGSize(width: 4_000, height: 2_000),
                    backingScale: 2,
                    rotation: rotation,
                    accessibilityLabel: "Stress image"
                )
                let scale = CGFloat((index % 20) + 1) / 10
                scrollView.applyMagnification(scale, preserveCenter: true)
            }
        }
        try expect(
            scrollView.magnification.isFinite,
            "Repeated zoom/rotation produced an invalid transform"
        )

        // Regression: replacement image must not shift to the leading edge
        // after navigation. Exercise the real NSScrollView/documentView seam,
        // including stale frame and clip origins left by a prior image.
        let replacementCases: [(CGSize, QuarterTurn, String)] = [
            (CGSize(width: 800, height: 400), .zero, "landscape"),
            (CGSize(width: 300, height: 900), .zero, "portrait"),
            (CGSize(width: 120, height: 80), .zero, "small"),
            (CGSize(width: 2_400, height: 400), .zero, "wide"),
            (CGSize(width: 400, height: 2_400), .zero, "tall"),
            (CGSize(width: 1_200, height: 600), .right90, "rotated")
        ]
        for (pixelSize, rotation, label) in replacementCases {
            scrollView.canvas.frame.origin = NSPoint(x: 317, y: 149)
            scrollView.contentView.scroll(to: NSPoint(x: 211, y: 97))
            scrollView.installContent(
                image: NSImage(size: pixelSize),
                pixelSize: pixelSize,
                backingScale: 1,
                rotation: rotation,
                accessibilityLabel: label
            )
            let fit = CGFloat(
                ViewportGeometry.fitScale(
                    imagePixels: ViewportDimensions(
                        width: pixelSize.width,
                        height: pixelSize.height
                    ),
                    viewportPoints: ViewportDimensions(
                        width: scrollView.contentSize.width,
                        height: scrollView.contentSize.height
                    ),
                    backingScale: 1,
                    rotation: rotation
                )
            )
            scrollView.applyMagnification(fit, preserveCenter: false)
            scrollView.resetViewportForReplacement()
            try expect(
                scrollView.canvas.frame.origin == .zero,
                "Replacement \(label) retained stale document origin"
            )
            try expectCentered(
                scrollView,
                axis: .horizontal,
                "Replacement \(label) was not horizontally centered"
            )
            try expectCentered(
                scrollView,
                axis: .vertical,
                "Replacement \(label) was not vertically centered"
            )
        }

        scrollView.frame.size = CGSize(width: 1_280, height: 720)
        scrollView.layoutSubtreeIfNeeded()
        let resizedFit = CGFloat(
            ViewportGeometry.fitScale(
                imagePixels: ViewportDimensions(width: 1_200, height: 600),
                viewportPoints: ViewportDimensions(
                    width: scrollView.contentSize.width,
                    height: scrollView.contentSize.height
                ),
                backingScale: 1,
                rotation: .right90
            )
        )
        scrollView.applyMagnification(resizedFit, preserveCenter: false)
        scrollView.centerDocument()
        try expectCentered(
            scrollView,
            axis: .horizontal,
            "Replacement image lost horizontal centering after resize"
        )
        try expectCentered(
            scrollView,
            axis: .vertical,
            "Replacement image lost vertical centering after resize"
        )

        print("PASS: 22 native AppKit viewport checks")
    }
}

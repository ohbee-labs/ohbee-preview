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
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 800),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        scrollView.layoutSubtreeIfNeeded()
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

        // Installed-app regression: a replacement was centered synchronously,
        // then a later AppKit clip-bounds/layout update restored a zero origin
        // without changing the viewport size. The committed generation must
        // reassert centering after that real NSScrollView lifecycle event.
        let lifecycleCases: [(CGSize, QuarterTurn, String)] = [
            (CGSize(width: 320, height: 180), .zero, "first landscape"),
            (CGSize(width: 4_000, height: 2_000), .zero, "large landscape"),
            (CGSize(width: 600, height: 1_600), .zero, "portrait"),
            (CGSize(width: 160, height: 120), .zero, "small"),
            (CGSize(width: 2_400, height: 800), .right90, "rotated")
        ]
        var committedGeneration: UInt64 = 100
        for cycle in 0..<3 {
            for (pixelSize, rotation, label) in lifecycleCases {
                committedGeneration += 1
                let applied = scrollView.applyViewport(
                    image: NSImage(size: pixelSize),
                    pixelSize: pixelSize,
                    backingScale: 1,
                    rotation: rotation,
                    mode: .fit,
                    requestedScale: 1,
                    generation: committedGeneration,
                    accessibilityLabel: label,
                    resetsPreviousGeometry: true
                )
                try expect(applied != nil, "Generation \(committedGeneration) was not applied")
                try expectCentered(
                    scrollView,
                    axis: .horizontal,
                    "Cycle \(cycle) \(label) was not initially centered"
                )
                try expectCentered(
                    scrollView,
                    axis: .vertical,
                    "Cycle \(cycle) \(label) was not initially centered"
                )

                // Model the later AppKit/SwiftUI geometry write that caused
                // the installed Release app to expose leading alignment.
                scrollView.contentView.bounds.origin = .zero
                scrollView.layout()
                try expectCentered(
                    scrollView,
                    axis: .horizontal,
                    "Later layout moved \(label) to the leading edge"
                )
                try expectCentered(
                    scrollView,
                    axis: .vertical,
                    "Later layout moved \(label) to the bottom edge"
                )
            }
        }

        // Zoom/pan state from the previous image must not affect the next
        // committed Fit generation.
        scrollView.applyMagnification(3, preserveCenter: false)
        scrollView.contentView.bounds.origin = NSPoint(x: 175, y: 90)
        committedGeneration += 1
        _ = scrollView.applyViewport(
            image: NSImage(size: CGSize(width: 480, height: 1_200)),
            pixelSize: CGSize(width: 480, height: 1_200),
            backingScale: 1,
            rotation: .left90,
            mode: .fit,
            requestedScale: 1,
            generation: committedGeneration,
            accessibilityLabel: "navigation after zoom pan rotation",
            resetsPreviousGeometry: true
        )
        try expectCentered(
            scrollView,
            axis: .horizontal,
            "Zoom/pan geometry leaked into replacement"
        )
        try expectCentered(
            scrollView,
            axis: .vertical,
            "Rotation geometry leaked into replacement"
        )

        // A stale representable callback must not replace or mutate the newer
        // committed generation.
        let frameBeforeStaleUpdate = scrollView.canvas.frame
        let staleResult = scrollView.applyViewport(
            image: NSImage(size: CGSize(width: 50, height: 50)),
            pixelSize: CGSize(width: 50, height: 50),
            backingScale: 1,
            rotation: .zero,
            mode: .fit,
            requestedScale: 1,
            generation: committedGeneration - 1,
            accessibilityLabel: "stale",
            resetsPreviousGeometry: true
        )
        try expect(staleResult == nil, "Stale generation was accepted")
        try expect(
            scrollView.canvas.frame == frameBeforeStaleUpdate,
            "Stale generation changed document geometry"
        )

        // Resize immediately after navigation and repeat layout. Fit mode must
        // recompute from the final clip size and remain centered.
        scrollView.frame.size = CGSize(width: 760, height: 980)
        scrollView.layoutSubtreeIfNeeded()
        scrollView.layout()
        try expectCentered(
            scrollView,
            axis: .horizontal,
            "Immediate resize lost horizontal centering"
        )
        try expectCentered(
            scrollView,
            axis: .vertical,
            "Immediate resize lost vertical centering"
        )

        // Exercise the real coordinator path used by repeated
        // NSViewRepresentable.updateNSView calls, not only the native view API.
        func representable(
            size: CGSize,
            generation: UInt64,
            contentRevision: UInt64 = 0
        ) -> ImageInspectionView {
            ImageInspectionView(
                image: NSImage(size: size),
                filename: "private",
                generation: generation,
                contentRevision: contentRevision,
                state: ViewportState(),
                onEffectiveScaleChanged: { _ in },
                onPinchScaleChanged: { _ in },
                onPrevious: {},
                onNext: {},
                onCommit: {},
                onFitCalculated: { _ in },
                onInvalidTransform: {}
            )
        }
        let representableScrollView = InspectionScrollView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 700)
        )
        let representableWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        representableWindow.contentView = representableScrollView
        let coordinator = representable(
            size: CGSize(width: 1_600, height: 900),
            generation: 500
        ).makeCoordinator()
        coordinator.connect(to: representableScrollView)
        coordinator.apply(to: representableScrollView)
        coordinator.parent = representable(
            size: CGSize(width: 500, height: 1_500),
            generation: 501
        )
        coordinator.apply(to: representableScrollView)
        representableScrollView.contentView.bounds.origin = .zero
        representableScrollView.layout()
        try expectCentered(
            representableScrollView,
            axis: .horizontal,
            "Repeated representable update lost horizontal centering"
        )
        try expectCentered(
            representableScrollView,
            axis: .vertical,
            "Repeated representable update lost vertical centering"
        )

        let frameBeforeAnimatedReplacement = representableScrollView.canvas.frame
        let originBeforeAnimatedReplacement = representableScrollView.contentView.bounds.origin
        let scaleBeforeAnimatedReplacement = representableScrollView.magnification
        coordinator.parent = representable(
            size: CGSize(width: 500, height: 1_500),
            generation: 501,
            contentRevision: 1
        )
        coordinator.apply(to: representableScrollView)
        try expect(
            representableScrollView.canvas.frame == frameBeforeAnimatedReplacement,
            "Animated frame replacement changed document geometry"
        )
        try expect(
            representableScrollView.contentView.bounds.origin
                == originBeforeAnimatedReplacement,
            "Animated frame replacement reset pan or centering"
        )
        try expect(
            representableScrollView.magnification == scaleBeforeAnimatedReplacement,
            "Animated frame replacement reset magnification"
        )

        print("PASS: 73 native AppKit viewport checks")
    }
}

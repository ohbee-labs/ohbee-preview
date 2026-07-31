import AppKit
import OhbeeStage2Core
import SwiftUI

struct ImageInspectionView: NSViewRepresentable {
    let image: NSImage
    let filename: String
    let generation: UInt64
    let state: ViewportState
    let onEffectiveScaleChanged: @MainActor (CGFloat) -> Void
    let onPinchScaleChanged: @MainActor (CGFloat) -> Void
    let onPrevious: @MainActor () -> Void
    let onNext: @MainActor () -> Void
    let onCommit: @MainActor () -> Void
    let onFitCalculated: @MainActor (Duration) -> Void
    let onInvalidTransform: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> InspectionScrollView {
        let scrollView = InspectionScrollView()
        context.coordinator.connect(to: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: InspectionScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(to: scrollView)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ImageInspectionView
        private weak var scrollView: InspectionScrollView?
        private var appliedGeneration: UInt64?
        private var appliedState: ViewportState?
        private var appliedBackingScale: CGFloat?
        private var appliedViewportSize: CGSize?
        private var isApplyingState = false

        init(parent: ImageInspectionView) {
            self.parent = parent
        }

        func connect(to scrollView: InspectionScrollView) {
            self.scrollView = scrollView
            scrollView.onLayout = { [weak self] in
                guard let self, let scrollView = self.scrollView else { return }
                self.apply(to: scrollView)
            }
            scrollView.onPrevious = { [weak self] in
                self?.parent.onPrevious()
            }
            scrollView.onNext = { [weak self] in
                self?.parent.onNext()
            }
            scrollView.onMagnification = { [weak self] scale in
                guard let self, !self.isApplyingState else { return }
                let clamped = CGFloat(
                    ViewportState.clampedScale(Double(scale))
                )
                self.parent.onEffectiveScaleChanged(clamped)
                self.parent.onPinchScaleChanged(clamped)
            }
        }

        func apply(to scrollView: InspectionScrollView) {
            guard !isApplyingState else { return }
            let backingScale = scrollView.window?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor
                ?? 1
            let viewportSize = scrollView.contentSize
            guard viewportSize.width > 0, viewportSize.height > 0 else { return }
            let imageChanged = appliedGeneration != parent.generation
            let stateChanged = appliedState != parent.state
            let displayScaleChanged = appliedBackingScale != backingScale
            let viewportChanged =
                appliedViewportSize?.width != viewportSize.width
                || appliedViewportSize?.height != viewportSize.height
            guard
                imageChanged
                    || stateChanged
                    || displayScaleChanged
                    || viewportChanged
            else {
                return
            }

            isApplyingState = true
            defer { isApplyingState = false }

            let pixelSize = parent.image.representations.first.map {
                CGSize(width: $0.pixelsWide, height: $0.pixelsHigh)
            } ?? parent.image.size
            guard
                pixelSize.width > 0,
                pixelSize.height > 0,
                backingScale > 0
            else {
                parent.onInvalidTransform()
                return
            }

            scrollView.installContent(
                image: parent.image,
                pixelSize: pixelSize,
                backingScale: backingScale,
                rotation: parent.state.rotation,
                accessibilityLabel: "Image \(parent.filename)"
            )
            scrollView.viewportMode = parent.state.mode

            let scale: CGFloat
            switch parent.state.mode {
            case .fit:
                let clock = ContinuousClock()
                let start = clock.now
                scale = CGFloat(
                    ViewportGeometry.fitScale(
                        imagePixels: ViewportDimensions(
                            width: pixelSize.width,
                            height: pixelSize.height
                        ),
                        viewportPoints: ViewportDimensions(
                            width: viewportSize.width,
                            height: viewportSize.height
                        ),
                        backingScale: Double(backingScale),
                        rotation: parent.state.rotation
                    )
                )
                parent.onFitCalculated(start.duration(to: clock.now))
            case .actualSize:
                scale = 1
            case .manual:
                scale = CGFloat(
                    ViewportState.clampedScale(parent.state.scale)
                )
            }

            scrollView.applyMagnification(
                scale,
                preserveCenter: !imageChanged
            )
            parent.onEffectiveScaleChanged(scale)

            if imageChanged {
                // Replacement is one ordered geometry transaction: canonical
                // document origin, completed layout, magnification, then a
                // constrained clip origin based on the new document.
                scrollView.resetViewportForReplacement()
                appliedGeneration = parent.generation
                let committedGeneration = parent.generation
                DispatchQueue.main.async { [weak self] in
                    guard self?.parent.generation == committedGeneration else {
                        return
                    }
                    self?.parent.onCommit()
                }
            } else if parent.state.mode == .fit {
                scrollView.centerDocument()
            }

            appliedState = parent.state
            appliedBackingScale = backingScale
            appliedViewportSize = viewportSize
        }

    }
}

private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return constrained }

        if documentView.frame.width < constrained.width {
            constrained.origin.x = -(constrained.width - documentView.frame.width) / 2
        }
        if documentView.frame.height < constrained.height {
            constrained.origin.y = -(constrained.height - documentView.frame.height) / 2
        }
        return constrained
    }
}

final class InspectionCanvasView: NSView {
    private var image: NSImage?
    private var pixelSize: CGSize = .zero
    private var backingScale: CGFloat = 1
    private var rotation: QuarterTurn = .zero

    override var isFlipped: Bool {
        false
    }

    func configure(
        image: NSImage,
        pixelSize: CGSize,
        backingScale: CGFloat,
        rotation: QuarterTurn,
        accessibilityLabel: String
    ) {
        self.image = image
        self.pixelSize = pixelSize
        self.backingScale = backingScale
        self.rotation = rotation

        let rotated = ViewportGeometry.rotatedPixelSize(
            imagePixels: ViewportDimensions(
                width: pixelSize.width,
                height: pixelSize.height
            ),
            rotation: rotation
        )
        frame = NSRect(
            origin: .zero,
            size: CGSize(
                width: CGFloat(rotated.width) / backingScale,
                height: CGFloat(rotated.height) / backingScale
            )
        )
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(accessibilityLabel)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image, let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        context.saveGState()
        context.interpolationQuality = .high
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.rotate(
            by: -CGFloat(rotation.rawValue) * .pi / 2
        )

        let logicalSize = CGSize(
            width: pixelSize.width / backingScale,
            height: pixelSize.height / backingScale
        )
        image.draw(
            in: NSRect(
                x: -logicalSize.width / 2,
                y: -logicalSize.height / 2,
                width: logicalSize.width,
                height: logicalSize.height
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        context.restoreGState()
    }
}

final class InspectionScrollView: NSScrollView {
    let canvas = InspectionCanvasView()
    var viewportMode: ViewportMode = .fit
    var onLayout: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onMagnification: ((CGFloat) -> Void)?

    private var dragStartInWindow: NSPoint?
    private var dragStartBoundsOrigin: NSPoint?
    private var horizontalGestureDistance: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        borderType = .noBorder
        allowsMagnification = true
        minMagnification = CGFloat(ViewportState.minimumScale)
        maxMagnification = CGFloat(ViewportState.maximumScale)
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        contentView = CenteringClipView()
        documentView = canvas
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func layout() {
        super.layout()
        onLayout?()
    }

    func installContent(
        image: NSImage,
        pixelSize: CGSize,
        backingScale: CGFloat,
        rotation: QuarterTurn,
        accessibilityLabel: String
    ) {
        canvas.configure(
            image: image,
            pixelSize: pixelSize,
            backingScale: backingScale,
            rotation: rotation,
            accessibilityLabel: accessibilityLabel
        )
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func applyMagnification(_ scale: CGFloat, preserveCenter: Bool) {
        let clamped = CGFloat(
            ViewportState.clampedScale(Double(scale))
        )
        if preserveCenter {
            let center = NSPoint(
                x: contentView.bounds.midX,
                y: contentView.bounds.midY
            )
            setMagnification(clamped, centeredAt: center)
        } else {
            magnification = clamped
        }
        reflectScrolledClipView(contentView)
    }

    func centerDocument() {
        let proposed = NSRect(origin: .zero, size: contentView.bounds.size)
        let centered = contentView.constrainBoundsRect(proposed)
        contentView.scroll(to: centered.origin)
        reflectScrolledClipView(contentView)
    }

    func resetViewportForReplacement() {
        canvas.frame.origin = .zero
        needsLayout = true
        layoutSubtreeIfNeeded()
        centerDocument()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123:
            onPrevious?()
        case 124:
            onNext?()
        default:
            super.keyDown(with: event)
        }
    }

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        onMagnification?(magnification)
    }

    override func mouseDown(with event: NSEvent) {
        let hasOverflow =
            canvas.frame.width > contentView.bounds.width
            || canvas.frame.height > contentView.bounds.height
        guard viewportMode != .fit, hasOverflow else {
            super.mouseDown(with: event)
            return
        }
        dragStartInWindow = event.locationInWindow
        dragStartBoundsOrigin = contentView.bounds.origin
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            let start = dragStartInWindow,
            let boundsOrigin = dragStartBoundsOrigin
        else {
            super.mouseDragged(with: event)
            return
        }
        let deltaX = (event.locationInWindow.x - start.x) / magnification
        let deltaY = (event.locationInWindow.y - start.y) / magnification
        contentView.scroll(
            to: NSPoint(
                x: boundsOrigin.x - deltaX,
                y: boundsOrigin.y - deltaY
            )
        )
        reflectScrolledClipView(contentView)
    }

    override func mouseUp(with event: NSEvent) {
        if dragStartInWindow != nil {
            NSCursor.pop()
        }
        dragStartInWindow = nil
        dragStartBoundsOrigin = nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard viewportMode == .fit else {
            super.scrollWheel(with: event)
            return
        }

        guard
            event.hasPreciseScrollingDeltas,
            abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        else {
            return
        }

        if event.phase == .began {
            horizontalGestureDistance = 0
        }
        horizontalGestureDistance += event.scrollingDeltaX

        if event.phase == .ended || event.momentumPhase == .ended {
            let threshold: CGFloat = 80
            if horizontalGestureDistance >= threshold {
                onPrevious?()
            } else if horizontalGestureDistance <= -threshold {
                onNext?()
            }
            horizontalGestureDistance = 0
        }
    }
}

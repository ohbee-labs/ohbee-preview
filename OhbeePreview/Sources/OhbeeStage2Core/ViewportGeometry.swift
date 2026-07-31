import Foundation

public struct ViewportDimensions: Sendable, Equatable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct ViewportPoint: Sendable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum QuarterTurn: Int, Sendable, CaseIterable {
    case zero = 0
    case right90 = 1
    case half = 2
    case left90 = 3

    public var rotatesDimensions: Bool {
        self == .right90 || self == .left90
    }

    public func rotatedRight() -> QuarterTurn {
        QuarterTurn(rawValue: (rawValue + 1) % 4) ?? .zero
    }

    public func rotatedLeft() -> QuarterTurn {
        QuarterTurn(rawValue: (rawValue + 3) % 4) ?? .zero
    }
}

public enum ViewportMode: Sendable, Equatable {
    case fit
    case actualSize
    case manual
}

public struct ViewportState: Sendable, Equatable {
    public static let minimumScale = 0.05
    public static let maximumScale = 16.0
    public static let zoomStep = 1.25

    public var mode: ViewportMode
    public var scale: Double
    public var rotation: QuarterTurn

    public init(
        mode: ViewportMode = .fit,
        scale: Double = 1,
        rotation: QuarterTurn = .zero
    ) {
        self.mode = mode
        self.scale = Self.clampedScale(scale)
        self.rotation = rotation
    }

    public static func clampedScale(_ proposed: Double) -> Double {
        guard proposed.isFinite, proposed > 0 else {
            return minimumScale
        }
        return min(max(proposed, minimumScale), maximumScale)
    }

    public mutating func zoomIn(from effectiveScale: Double) {
        mode = .manual
        scale = Self.clampedScale(effectiveScale * Self.zoomStep)
    }

    public mutating func zoomOut(from effectiveScale: Double) {
        mode = .manual
        scale = Self.clampedScale(effectiveScale / Self.zoomStep)
    }

    public mutating func resetToFit() {
        mode = .fit
        scale = 1
    }

    public mutating func showActualSize() {
        mode = .actualSize
        scale = 1
    }
}

public struct PanBounds: Sendable, Equatable {
    public let horizontal: Double
    public let vertical: Double

    public init(horizontal: Double, vertical: Double) {
        self.horizontal = max(0, horizontal)
        self.vertical = max(0, vertical)
    }
}

public enum ViewportGeometry {
    public static func rotatedPixelSize(
        imagePixels: ViewportDimensions,
        rotation: QuarterTurn
    ) -> ViewportDimensions {
        guard rotation.rotatesDimensions else { return imagePixels }
        return ViewportDimensions(
            width: imagePixels.height,
            height: imagePixels.width
        )
    }

    public static func fitScale(
        imagePixels: ViewportDimensions,
        viewportPoints: ViewportDimensions,
        backingScale: Double,
        rotation: QuarterTurn
    ) -> Double {
        guard
            imagePixels.width > 0,
            imagePixels.height > 0,
            viewportPoints.width > 0,
            viewportPoints.height > 0,
            backingScale.isFinite,
            backingScale > 0
        else {
            return ViewportState.minimumScale
        }

        let rotated = rotatedPixelSize(
            imagePixels: imagePixels,
            rotation: rotation
        )
        let actualWidth = rotated.width / backingScale
        let actualHeight = rotated.height / backingScale
        let widthScale = viewportPoints.width / actualWidth
        let heightScale = viewportPoints.height / actualHeight
        return ViewportState.clampedScale(min(1, widthScale, heightScale))
    }

    public static func displayedPointSize(
        imagePixels: ViewportDimensions,
        backingScale: Double,
        scale: Double,
        rotation: QuarterTurn
    ) -> ViewportDimensions {
        guard backingScale.isFinite, backingScale > 0 else {
            return ViewportDimensions(width: 0, height: 0)
        }
        let rotated = rotatedPixelSize(
            imagePixels: imagePixels,
            rotation: rotation
        )
        let clampedScale = ViewportState.clampedScale(scale)
        return ViewportDimensions(
            width: rotated.width / backingScale * clampedScale,
            height: rotated.height / backingScale * clampedScale
        )
    }

    public static func panBounds(
        imagePixels: ViewportDimensions,
        viewportPoints: ViewportDimensions,
        backingScale: Double,
        scale: Double,
        rotation: QuarterTurn
    ) -> PanBounds {
        let displayed = displayedPointSize(
            imagePixels: imagePixels,
            backingScale: backingScale,
            scale: scale,
            rotation: rotation
        )
        return PanBounds(
            horizontal: (displayed.width - viewportPoints.width) / 2,
            vertical: (displayed.height - viewportPoints.height) / 2
        )
    }

    public static func centeredOrigin(
        contentSize: ViewportDimensions,
        viewportSize: ViewportDimensions
    ) -> ViewportPoint {
        ViewportPoint(
            x: max(0, (viewportSize.width - contentSize.width) / 2),
            y: max(0, (viewportSize.height - contentSize.height) / 2)
        )
    }

    public static func clampedPanOffset(
        _ proposed: ViewportPoint,
        bounds: PanBounds
    ) -> ViewportPoint {
        ViewportPoint(
            x: min(max(proposed.x, -bounds.horizontal), bounds.horizontal),
            y: min(max(proposed.y, -bounds.vertical), bounds.vertical)
        )
    }
}

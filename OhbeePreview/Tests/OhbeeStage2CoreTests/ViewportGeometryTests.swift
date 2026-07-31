import Foundation
import OhbeeStage2Core
import XCTest

final class ViewportGeometryTests: XCTestCase {
    private let viewport = ViewportDimensions(width: 1_000, height: 800)

    func testFitScales() {
        XCTAssertEqual(
            ViewportGeometry.fitScale(
                imagePixels: ViewportDimensions(width: 4_000, height: 2_000),
                viewportPoints: viewport,
                backingScale: 2,
                rotation: .zero
            ),
            0.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ViewportGeometry.fitScale(
                imagePixels: ViewportDimensions(width: 2_000, height: 4_000),
                viewportPoints: viewport,
                backingScale: 2,
                rotation: .zero
            ),
            0.4,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ViewportGeometry.fitScale(
                imagePixels: ViewportDimensions(width: 800, height: 600),
                viewportPoints: viewport,
                backingScale: 2,
                rotation: .zero
            ),
            1
        )
        XCTAssertEqual(
            ViewportGeometry.fitScale(
                imagePixels: ViewportDimensions(width: 4_000, height: 2_000),
                viewportPoints: viewport,
                backingScale: 2,
                rotation: .right90
            ),
            0.4,
            accuracy: 0.0001
        )
    }

    func testActualSizeAndZoomCommands() {
        var state = ViewportState()
        state.showActualSize()
        XCTAssertEqual(state.mode, .actualSize)
        XCTAssertEqual(state.scale, 1)

        state.zoomIn(from: 1)
        XCTAssertEqual(state.mode, .manual)
        XCTAssertEqual(state.scale, 1.25)

        state.zoomOut(from: state.scale)
        XCTAssertEqual(state.scale, 1)

        state.resetToFit()
        XCTAssertEqual(state.mode, .fit)
        XCTAssertEqual(state.scale, 1)
    }

    func testZoomClamping() {
        XCTAssertEqual(
            ViewportState.clampedScale(0.0001),
            ViewportState.minimumScale
        )
        XCTAssertEqual(
            ViewportState.clampedScale(1_000),
            ViewportState.maximumScale
        )
    }

    func testRotationNormalizesAfterFourTurns() {
        var rotation = QuarterTurn.zero
        for _ in 0..<4 {
            rotation = rotation.rotatedRight()
        }
        XCTAssertEqual(rotation, .zero)

        for _ in 0..<4 {
            rotation = rotation.rotatedLeft()
        }
        XCTAssertEqual(rotation, .zero)
    }

    func testPanBoundsAndCentering() {
        XCTAssertEqual(
            ViewportGeometry.panBounds(
                imagePixels: ViewportDimensions(width: 4_000, height: 2_000),
                viewportPoints: viewport,
                backingScale: 2,
                scale: 1,
                rotation: .zero
            ),
            PanBounds(horizontal: 500, vertical: 100)
        )
        let centered = ViewportGeometry.centeredOrigin(
            contentSize: ViewportDimensions(width: 400, height: 300),
            viewportSize: viewport
        )
        XCTAssertEqual(centered.x, 300)
        XCTAssertEqual(centered.y, 250)

        let clamped = ViewportGeometry.clampedPanOffset(
            ViewportPoint(x: 900, y: -500),
            bounds: PanBounds(horizontal: 500, vertical: 100)
        )
        XCTAssertEqual(clamped.x, 500)
        XCTAssertEqual(clamped.y, -100)
    }

    func testResizeRecalculatesFit() {
        let image = ViewportDimensions(width: 4_000, height: 2_000)
        let compact = ViewportGeometry.fitScale(
            imagePixels: image,
            viewportPoints: ViewportDimensions(width: 800, height: 600),
            backingScale: 2,
            rotation: .zero
        )
        let expanded = ViewportGeometry.fitScale(
            imagePixels: image,
            viewportPoints: ViewportDimensions(width: 1_600, height: 1_200),
            backingScale: 2,
            rotation: .zero
        )
        XCTAssertEqual(compact, 0.4, accuracy: 0.0001)
        XCTAssertEqual(expanded, 0.8, accuracy: 0.0001)
    }

    func testViewportStateIsolation() {
        var staleState = ViewportState()
        staleState.zoomIn(from: 1)
        staleState.rotation = .right90

        let currentState = ViewportState()
        XCTAssertEqual(currentState.mode, .fit)
        XCTAssertEqual(currentState.scale, 1)
        XCTAssertEqual(currentState.rotation, .zero)
    }
}

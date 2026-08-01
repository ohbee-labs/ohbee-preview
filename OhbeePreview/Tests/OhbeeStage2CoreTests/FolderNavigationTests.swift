import Foundation
import OhbeeStage2Core
import XCTest

final class FolderNavigationTests: XCTestCase {
    func testDiscoveryFilteringNaturalSortMatchingAndBoundaries() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohbee-navigation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let selected = root.appendingPathComponent("image2.JPG")
        for name in ["image10.jpg", "image1.png", "image2.JPG"] {
            try Data([0]).write(to: root.appendingPathComponent(name))
        }
        try Data([0]).write(to: root.appendingPathComponent(".hidden.jpg"))
        try Data([0]).write(to: root.appendingPathComponent("notes.txt"))

        let child = root.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        try Data([0]).write(to: child.appendingPathComponent("nested.jpg"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("duplicate.jpg"),
            withDestinationURL: selected
        )

        let result = try await FolderNavigationService.discover(
            folderURL: root,
            selectedURL: selected
        )

        XCTAssertEqual(result.eligibleImageCount, 3)
        var snapshot = try XCTUnwrap(result.snapshot)
        XCTAssertEqual(
            snapshot.entries.map(\.filename),
            ["image1.png", "image2.JPG", "image10.jpg"]
        )
        XCTAssertEqual(snapshot.current.url, selected.standardizedFileURL)
        XCTAssertEqual(snapshot.position, 2)

        XCTAssertEqual(snapshot.selectPrevious()?.filename, "image1.png")
        XCTAssertFalse(snapshot.canNavigatePrevious)
        XCTAssertNil(snapshot.selectPrevious())

        _ = snapshot.selectNext()
        XCTAssertEqual(snapshot.selectNext()?.filename, "image10.jpg")
        XCTAssertFalse(snapshot.canNavigateNext)
        XCTAssertNil(snapshot.selectNext())

        XCTAssertEqual(snapshot.select(url: selected)?.url, selected.standardizedFileURL)
        XCTAssertEqual(snapshot.position, 2)
        XCTAssertNil(snapshot.select(url: root.appendingPathComponent("missing.jpg")))
    }

    func testUnmatchedSelectionDoesNotCreateFolderSession() {
        let entries = [
            NavigationEntry(
                url: URL(fileURLWithPath: "/tmp/image1.jpg"),
                filename: "image1.jpg"
            )
        ]
        XCTAssertNil(
            NavigationSnapshot(
                entries: entries,
                selectedURL: URL(fileURLWithPath: "/tmp/missing.jpg")
            )
        )
    }
}

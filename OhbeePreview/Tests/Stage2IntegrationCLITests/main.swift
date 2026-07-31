import AppKit
import Foundation

enum IntegrationTestFailure: Error {
    case expectation(String)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw IntegrationTestFailure.expectation(message) }
}

private func makeTIFF(at url: URL) throws {
    let image = NSImage(size: NSSize(width: 2, height: 2))
    image.lockFocus()
    NSColor.systemOrange.setFill()
    NSRect(x: 0, y: 0, width: 2, height: 2).fill()
    image.unlockFocus()
    guard let data = image.tiffRepresentation else {
        throw IntegrationTestFailure.expectation("Could not create TIFF fixture")
    }
    try data.write(to: url)
}

@main
enum Stage2IntegrationCLITests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohbee-stage2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let selected = root.appendingPathComponent("selected.tiff")
        try makeTIFF(at: selected)

        let loaded = try await SelectedImageLoader.load(url: selected)
        try expect(
            loaded.image.tiffRepresentation != nil,
            "Materialized image was unavailable after loader scope ended"
        )

        let unrelated = root.appendingPathComponent("notes.txt")
        try Data("not an image".utf8).write(to: unrelated)
        let withoutSibling = await ParentAccessAssessor.assess(selectedURL: selected)
        try expect(withoutSibling.canEnumerate, "Parent folder was not enumerable")
        try expect(
            withoutSibling.canReadRepresentativeSibling,
            "An unrelated file was incorrectly treated as a failed image sibling"
        )

        let sibling = root.appendingPathComponent("sibling.TIFF")
        try makeTIFF(at: sibling)
        let withSibling = await ParentAccessAssessor.assess(selectedURL: selected)
        try expect(withSibling.canEnumerate, "Parent folder became unavailable")
        try expect(
            withSibling.canReadRepresentativeSibling,
            "Readable supported sibling was not detected"
        )

        print("PASS: 3 Stage 2 integration checks")
    }
}

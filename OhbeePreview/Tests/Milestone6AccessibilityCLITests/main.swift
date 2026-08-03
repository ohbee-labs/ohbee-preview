import Foundation

@MainActor private var passed = 0

@MainActor private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
    passed += 1
}

@main
enum Milestone6AccessibilityCLITests {
    @MainActor
    static func main() throws {
        expect(ViewerShortcut.hasUniqueBindings, "primary shortcuts collide")
        expect(ViewerShortcut.primary.count == 13, "shortcut map is incomplete")
        expect(Set(ViewerShortcut.primary.map(\.command)).count == 13, "commands are duplicated")

        let requiredIDs = [
            AccessibilityID.viewport, AccessibilityID.previous,
            AccessibilityID.next, AccessibilityID.thumbnailSidebar,
            AccessibilityID.sidebarToggle, AccessibilityID.fit,
            AccessibilityID.actualSize, AccessibilityID.zoomIn,
            AccessibilityID.zoomOut, AccessibilityID.rotateLeft,
            AccessibilityID.rotateRight, AccessibilityID.reveal,
            AccessibilityID.trash, AccessibilityID.folderAccess,
            AccessibilityID.trashConfirmation, AccessibilityID.trashCancel,
            AccessibilityID.emptyFolder, AccessibilityID.error
        ]
        expect(Set(requiredIDs).count == requiredIDs.count, "accessibility identifiers collide")
        expect(requiredIDs.allSatisfy { !$0.contains("/") }, "identifier exposes a path")

        let identity = Data([0x01, 0x02, 0x03])
        expect(
            AccessibilityID.thumbnail(identity: identity, ordinal: 9)
                == AccessibilityID.thumbnail(identity: identity, ordinal: 1),
            "stable thumbnail identity depends on array position"
        )
        expect(
            AccessibilityID.thumbnail(identity: nil, ordinal: 4) == "thumbnail.ordinal-4",
            "thumbnail fallback identity is unstable"
        )

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(
            contentsOf: root.appendingPathComponent("Sources/OhbeePreview/ContentView.swift"),
            encoding: .utf8
        )
        let app = try String(
            contentsOf: root.appendingPathComponent("Sources/OhbeePreview/OhbeePreviewApp.swift"),
            encoding: .utf8
        )
        let sidebar = try String(
            contentsOf: root.appendingPathComponent("Sources/OhbeePreview/ThumbnailSidebar.swift"),
            encoding: .utf8
        )
        let finder = try String(
            contentsOf: root.appendingPathComponent("Sources/OhbeePreview/FinderActionController.swift"),
            encoding: .utf8
        )

        expect(content.contains("accessibilityReduceMotion"), "Reduce Motion is not observed")
        expect(content.contains("focused($focusedArea, equals: .viewport)"), "viewer focus intent is absent")
        expect(content.contains("AccessibilityID.emptyFolder"), "empty state identifier is absent")
        expect(content.contains("AccessibilityID.error"), "error state identifier is absent")
        expect(sidebar.contains("accessibilityAddTraits(selected ? [.isSelected]"), "selected trait is absent")
        expect(sidebar.contains("transaction.disablesAnimations = true"), "Reduce Motion branch animates")
        expect(app.contains("OpenImagePanel.present(onOpen: model.open)"), "standard Open command is absent")
        expect(app.contains("keyboardShortcut(\"o\", modifiers: .command)"), "Open shortcut is absent")
        expect(finder.contains("buttons[0].keyEquivalent = \"\\r\""), "Trash does not default to Cancel")
        expect(finder.contains("AccessibilityID.trashCancel"), "Trash cancel identifier is absent")
        expect(!content.contains(".onChange(of: animation.presentationRevision)"), "GIF frames churn focus")

        print("PASS: \(passed) Milestone 6 accessibility and command checks")
    }
}

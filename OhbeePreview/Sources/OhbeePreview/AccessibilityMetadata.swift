import Foundation

enum ViewerFocusTarget: Hashable {
    case viewport
    case thumbnails
    case folderAccess
    case error
    case emptyState
}

enum AccessibilityID {
    static let viewport = "viewer.viewport"
    static let previous = "command.previous"
    static let next = "command.next"
    static let thumbnailSidebar = "sidebar.thumbnails"
    static let sidebarToggle = "command.sidebar.toggle"
    static let fit = "command.fit"
    static let actualSize = "command.actual-size"
    static let zoomIn = "command.zoom-in"
    static let zoomOut = "command.zoom-out"
    static let rotateLeft = "command.rotate-left"
    static let rotateRight = "command.rotate-right"
    static let reveal = "command.reveal"
    static let trash = "command.trash"
    static let folderAccess = "command.folder-access"
    static let trashConfirmation = "dialog.trash-confirmation"
    static let trashCancel = "dialog.trash-cancel"
    static let emptyFolder = "state.empty-folder"
    static let error = "state.error"

    static func thumbnail(identity: Data?, ordinal: Int) -> String {
        if let identity, !identity.isEmpty {
            var hash: UInt64 = 14_695_981_039_346_656_037
            for byte in identity {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
            return "thumbnail.identity-\(String(hash, radix: 16))"
        }
        // A folder-session ordinal is the only available identity on file
        // systems that do not expose a resource identifier. It contains no path.
        return "thumbnail.ordinal-\(ordinal)"
    }
}

struct ViewerShortcut: Hashable {
    let command: String
    let key: String
    let modifiers: Set<String>

    static let primary: [ViewerShortcut] = [
        .init(command: "Open", key: "o", modifiers: ["command"]),
        .init(command: "Reveal in Finder", key: "r", modifiers: ["command", "shift"]),
        .init(command: "Move to Trash", key: "delete", modifiers: ["command"]),
        .init(command: "Previous Image", key: "leftArrow", modifiers: []),
        .init(command: "Next Image", key: "rightArrow", modifiers: []),
        .init(command: "Fit to Window", key: "9", modifiers: ["command"]),
        .init(command: "Actual Size", key: "0", modifiers: ["command"]),
        .init(command: "Zoom In", key: "=", modifiers: ["command"]),
        .init(command: "Zoom Out", key: "-", modifiers: ["command"]),
        .init(command: "Rotate Left", key: "l", modifiers: ["command"]),
        .init(command: "Rotate Right", key: "r", modifiers: ["command"]),
        .init(command: "Toggle Thumbnails", key: "t", modifiers: ["command", "option"]),
        .init(command: "Toggle Full Screen", key: "f", modifiers: ["command", "control"])
    ]

    static var hasUniqueBindings: Bool {
        Set(primary.map { "\($0.key)|\($0.modifiers.sorted().joined(separator: ","))" }).count
            == primary.count
    }
}

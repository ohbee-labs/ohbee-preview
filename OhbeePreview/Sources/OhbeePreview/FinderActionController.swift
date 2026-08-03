import AppKit
import Darwin
import Foundation

struct FinderActionTarget: Sendable, Equatable {
    let sessionID: UUID
    let url: URL
    let filename: String
    let imageGeneration: UInt64
    let fileIdentity: Data?
    let fileSize: Int?
    let modificationDate: Date?

    init(
        sessionID: UUID,
        url: URL,
        filename: String,
        imageGeneration: UInt64,
        fileIdentity: Data?,
        fileSize: Int?,
        modificationDate: Date?
    ) {
        self.sessionID = sessionID
        self.url = url.standardizedFileURL
        self.filename = filename
        self.imageGeneration = imageGeneration
        self.fileIdentity = fileIdentity
        self.fileSize = fileSize
        self.modificationDate = modificationDate
    }
}

enum FinderActionError: Error, Equatable {
    case missing
    case permissionDenied
    case targetChanged
    case revealFailed
    case trashFailed(domain: String, code: Int)

    var userMessage: String {
        switch self {
        case .missing:
            "The image is no longer available."
        case .permissionDenied:
            "Ohbee Preview does not have permission to modify this image."
        case .targetChanged:
            "The file changed before it could be moved to Trash."
        case .revealFailed:
            "The image could not be revealed in Finder."
        case let .trashFailed(domain, code):
            "The image could not be moved to Trash (\(domain) \(code))."
        }
    }
}

protocol FinderActionServicing: Sendable {
    func reveal(_ target: FinderActionTarget) async throws
    func moveToTrash(_ target: FinderActionTarget) async throws
}

@MainActor
protocol TrashConfirming {
    func confirmTrash(of target: FinderActionTarget) async -> Bool
}

struct NativeTrashConfirmation: TrashConfirming {
    func confirmTrash(of target: FinderActionTarget) async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(localized: "Move “\(target.filename)” to Trash?")
        alert.informativeText = String(localized: "The image will be moved to the macOS Trash and can usually be recovered there.")
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.addButton(withTitle: String(localized: "Move to Trash"))
        alert.window.setAccessibilityIdentifier(AccessibilityID.trashConfirmation)
        alert.buttons[0].setAccessibilityIdentifier(AccessibilityID.trashCancel)
        alert.buttons[1].setAccessibilityIdentifier(AccessibilityID.trash)
        alert.buttons[1].hasDestructiveAction = true
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = ""

        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            return alert.runModal() == .alertSecondButtonReturn
        }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .alertSecondButtonReturn)
            }
        }
    }
}

struct NativeFinderActionService: FinderActionServicing {
    func reveal(_ target: FinderActionTarget) async throws {
        try await Task.detached(priority: .userInitiated) {
            try Self.validate(target)
        }.value
        await MainActor.run {
            NSWorkspace.shared.activateFileViewerSelecting([target.url])
        }
    }

    func moveToTrash(_ target: FinderActionTarget) async throws {
        try await Task.detached(priority: .userInitiated) {
            let didStart = target.url.startAccessingSecurityScopedResource()
            defer {
                if didStart { target.url.stopAccessingSecurityScopedResource() }
            }
            try Task.checkCancellation()
            try Self.validate(target)
            do {
                var resultingURL: NSURL?
                try FileManager.default.trashItem(
                    at: target.url,
                    resultingItemURL: &resultingURL
                )
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSCocoaErrorDomain,
                   nsError.code == NSFileNoSuchFileError {
                    throw FinderActionError.missing
                }
                if (nsError.domain == NSCocoaErrorDomain
                        && nsError.code == NSFileWriteNoPermissionError)
                    || (nsError.domain == NSPOSIXErrorDomain
                        && (nsError.code == EACCES || nsError.code == EPERM)) {
                    throw FinderActionError.permissionDenied
                }
                throw FinderActionError.trashFailed(
                    domain: nsError.domain,
                    code: nsError.code
                )
            }
        }.value
    }

    static func validate(_ target: FinderActionTarget) throws {
        guard FileManager.default.fileExists(atPath: target.url.path) else {
            throw FinderActionError.missing
        }
        let values = try? target.url.resourceValues(forKeys: [
            .fileResourceIdentifierKey,
            .fileSizeKey,
            .contentModificationDateKey
        ])
        if let expected = target.fileIdentity {
            let actual = values?.fileResourceIdentifier as? Data
            guard actual == expected else { throw FinderActionError.targetChanged }
        } else {
            guard
                values?.fileSize == target.fileSize,
                values?.contentModificationDate == target.modificationDate
            else { throw FinderActionError.targetChanged }
        }
    }
}

@MainActor
final class FinderActionController {
    enum TrashOutcome: Equatable {
        case cancelled
        case succeeded
    }

    private let service: any FinderActionServicing
    private let confirmation: any TrashConfirming

    init(
        service: any FinderActionServicing = NativeFinderActionService(),
        confirmation: any TrashConfirming = NativeTrashConfirmation()
    ) {
        self.service = service
        self.confirmation = confirmation
    }

    func reveal(_ target: FinderActionTarget) async throws {
        try await service.reveal(target)
    }

    func confirmAndTrash(
        _ target: FinderActionTarget,
        validate: @escaping @MainActor () -> Bool
    ) async throws -> TrashOutcome {
        Diagnostics.recordTrashConfirmationShown()
        guard await confirmation.confirmTrash(of: target) else {
            Diagnostics.recordTrashConfirmationCancelled()
            return .cancelled
        }
        try Task.checkCancellation()
        guard validate() else { throw FinderActionError.targetChanged }
        try await service.moveToTrash(target)
        return .succeeded
    }
}

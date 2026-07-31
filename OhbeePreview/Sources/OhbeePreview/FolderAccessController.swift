import AppKit
import Foundation
import OhbeeStage2Core

@MainActor
final class FolderAccessController {
    private struct HeldScope {
        let url: URL
        let didStart: Bool
    }

    private var memory = SessionAuthorizationMemory()
    private var heldScopes: [URL: HeldScope] = [:]
    private var selectedFileScope: HeldScope?

    deinit {
        if let selectedFileScope, selectedFileScope.didStart {
            selectedFileScope.url.stopAccessingSecurityScopedResource()
        }
        for scope in heldScopes.values where scope.didStart {
            scope.url.stopAccessingSecurityScopedResource()
        }
    }

    func replaceSelectedFileAccess(with fileURL: URL) {
        if let selectedFileScope, selectedFileScope.didStart {
            selectedFileScope.url.stopAccessingSecurityScopedResource()
        }
        let normalized = fileURL.standardizedFileURL
        selectedFileScope = HeldScope(
            url: normalized,
            didStart: normalized.startAccessingSecurityScopedResource()
        )
    }

    func hasAuthorized(_ folderURL: URL) -> Bool {
        memory.isAuthorized(folderURL: folderURL)
    }

    func wasDeclined(for imageURL: URL) -> Bool {
        memory.wasDeclined(imageURL: imageURL)
    }

    func markDeclined(for imageURL: URL) {
        memory.decline(imageURL: imageURL)
    }

    func retainAuthorization(for folderURL: URL) {
        let normalized = folderURL.standardizedFileURL
        guard heldScopes[normalized] == nil else { return }
        let didStart = normalized.startAccessingSecurityScopedResource()
        heldScopes[normalized] = HeldScope(url: normalized, didStart: didStart)
        memory.authorize(folderURL: normalized)
        Diagnostics.authorization.notice(
            "Folder authorized for current process scopeStarted=\(didStart)"
        )
    }

    func chooseFolder(
        expectedParent: URL,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = "Allow Folder Access"
        panel.message = "Choose the folder containing the image to browse nearby images."
        panel.prompt = "Allow Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = expectedParent

        panel.begin { response in
            Task { @MainActor in
                completion(response == .OK ? panel.url : nil)
            }
        }
    }
}

import AppKit
import Foundation
import OhbeeStage2Core
import OSLog

@MainActor
final class AppModel: ObservableObject {
    enum Presentation {
        case empty
        case loading(filename: String)
        case ready(filename: String, image: NSImage, generation: UInt64)
        case failed(filename: String, message: String)
    }

    @Published private(set) var presentation: Presentation = .empty
    @Published private(set) var authorization: FolderAuthorizationState = .notAssessed
    @Published private(set) var folderAccessMessage =
        "Allow Folder Access to browse nearby images."

    private let requestCoordinator = OpenRequestCoordinator()
    private let folderAccess = FolderAccessController()
    private var currentRequest: OpenRequest?
    private var currentTask: Task<Void, Never>?
    private var currentURL: URL?
    private var openPresentationIntervals: [UInt64: OSSignpostIntervalState] = [:]

    func open(url: URL) {
        currentTask?.cancel()
        endPendingPresentationIntervals(outcome: "superseded")

        currentTask = Task {
            let request = await requestCoordinator.begin(url: url)
            currentRequest = request
            currentURL = url
            authorization = .assessing
            folderAccessMessage = "Allow Folder Access to browse nearby images."
            presentation = .loading(filename: url.lastPathComponent)
            Diagnostics.logReceivedURL(url, generation: request.generation)

            let openID = Diagnostics.openSignposter.makeSignpostID()
            let openState = Diagnostics.openSignposter.beginInterval(
                "OpenToPresentationCommit",
                id: openID
            )
            openPresentationIntervals[request.generation] = openState

            async let loadedResult = loadSelectedImage(url: url, request: request)
            async let assessmentResult = assessParentAccess(url: url, request: request)
            _ = await loadedResult
            _ = await assessmentResult
        }
    }

    func imageDidCommitToView(generation: UInt64) {
        guard let state = openPresentationIntervals.removeValue(forKey: generation) else {
            return
        }
        Diagnostics.openSignposter.endInterval(
            "OpenToPresentationCommit",
            state,
            "outcome=displayed"
        )
        Diagnostics.open.notice(
            "Selected image committed to view generation=\(generation)"
        )
    }

    func allowFolderAccess() {
        guard let currentURL else { return }
        authorization = .pickerPresented
        let parent = currentURL.deletingLastPathComponent()
        folderAccess.chooseFolder(expectedParent: parent) { [weak self] chosenURL in
            guard let self, self.currentURL == currentURL else { return }
            guard let chosenURL else {
                self.folderAccess.markDeclined(for: currentURL)
                self.authorization = .declinedForImageSession
                Diagnostics.authorization.notice("Folder picker cancelled")
                return
            }
            guard chosenURL.standardizedFileURL == parent.standardizedFileURL else {
                self.authorization = .actionAvailable
                self.folderAccessMessage =
                    "Choose the exact folder containing \(currentURL.lastPathComponent)."
                Diagnostics.authorization.notice(
                    "Folder picker selection rejected because it was not the expected parent"
                )
                return
            }
            self.folderAccess.retainAuthorization(for: chosenURL)
            self.authorization = .authorizedForSession(chosenURL)
            self.folderAccessMessage = "Folder access granted for this app session."
        }
    }

    func manuallyBrowseFolder() {
        allowFolderAccess()
    }

    var showsFolderAccessAction: Bool {
        if case .actionAvailable = authorization {
            return true
        }
        return false
    }

    private func loadSelectedImage(url: URL, request: OpenRequest) async {
        let signpostID = Diagnostics.imageSignposter.makeSignpostID()
        let state = Diagnostics.imageSignposter.beginInterval(
            "SelectedImageDecode",
            id: signpostID
        )
        defer {
            Diagnostics.imageSignposter.endInterval("SelectedImageDecode", state)
        }

        do {
            let loaded = try await SelectedImageLoader.load(url: url)
            guard await requestCoordinator.isCurrent(request), !Task.isCancelled else {
                endPresentationInterval(
                    generation: request.generation,
                    outcome: "stale"
                )
                Diagnostics.open.notice(
                    "Rejected stale selected-image result generation=\(request.generation)"
                )
                return
            }
            presentation = .ready(
                filename: url.lastPathComponent,
                image: loaded.image,
                generation: request.generation
            )
            Diagnostics.image.notice(
                "Selected image ready generation=\(request.generation)"
            )
        } catch is CancellationError {
            endPresentationInterval(
                generation: request.generation,
                outcome: "cancelled"
            )
            Diagnostics.image.debug(
                "Selected image load cancelled generation=\(request.generation)"
            )
        } catch {
            guard await requestCoordinator.isCurrent(request), !Task.isCancelled else {
                endPresentationInterval(
                    generation: request.generation,
                    outcome: "stale"
                )
                return
            }
            endPresentationInterval(generation: request.generation, outcome: "failed")
            presentation = .failed(
                filename: url.lastPathComponent,
                message: "The selected image could not be displayed."
            )
            Diagnostics.image.error(
                "Selected image failed category=\(Diagnostics.privacySafeError(error), privacy: .public)"
            )
        }
    }

    private func assessParentAccess(url: URL, request: OpenRequest) async {
        let signpostID = Diagnostics.authorizationSignposter.makeSignpostID()
        let state = Diagnostics.authorizationSignposter.beginInterval(
            "AutomaticParentAccessAssessment",
            id: signpostID
        )
        defer {
            Diagnostics.authorizationSignposter.endInterval(
                "AutomaticParentAccessAssessment",
                state
            )
        }

        let parent = url.deletingLastPathComponent()
        if folderAccess.hasAuthorized(parent) {
            guard await requestCoordinator.isCurrent(request), !Task.isCancelled else { return }
            authorization = .authorizedForSession(parent)
            return
        }
        if folderAccess.wasDeclined(for: url) {
            guard await requestCoordinator.isCurrent(request), !Task.isCancelled else { return }
            authorization = .declinedForImageSession
            return
        }

        let result = await ParentAccessAssessor.assess(selectedURL: url)
        guard await requestCoordinator.isCurrent(request), !Task.isCancelled else {
            Diagnostics.authorization.debug(
                "Rejected stale authorization result generation=\(request.generation)"
            )
            return
        }

        if result.canEnumerate && result.canReadRepresentativeSibling {
            authorization = .automaticAccessAvailable
            Diagnostics.authorization.notice("Automatic parent access available")
        } else {
            authorization = .actionAvailable
            if let failure = result.failure {
                Diagnostics.authorization.notice(
                    "Automatic parent access unavailable domain=\(failure.domain, privacy: .public) code=\(failure.code)"
                )
            } else {
                Diagnostics.authorization.notice("Automatic parent access unavailable")
            }
        }
    }

    private func endPresentationInterval(generation: UInt64, outcome: StaticString) {
        guard let state = openPresentationIntervals.removeValue(forKey: generation) else {
            return
        }
        Diagnostics.openSignposter.endInterval(
            "OpenToPresentationCommit",
            state,
            "outcome=\(outcome)"
        )
    }

    private func endPendingPresentationIntervals(outcome: StaticString) {
        let intervals = openPresentationIntervals
        openPresentationIntervals.removeAll()
        for state in intervals.values {
            Diagnostics.openSignposter.endInterval(
                "OpenToPresentationCommit",
                state,
                "outcome=\(outcome)"
            )
        }
    }
}

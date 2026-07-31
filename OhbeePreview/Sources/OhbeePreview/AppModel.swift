import AppKit
import Foundation
import OhbeeStage2Core
import OSLog

@MainActor
final class AppModel: ObservableObject {
    struct DisplayedImage {
        let filename: String
        let image: NSImage
        let generation: UInt64
    }

    enum LoadState {
        case empty
        case loading(filename: String)
        case ready
        case failed(filename: String, message: String)
    }

    @Published private(set) var displayedImage: DisplayedImage?
    @Published private(set) var loadState: LoadState = .empty
    @Published private(set) var authorization: FolderAuthorizationState = .notAssessed
    @Published private(set) var folderAccessMessage =
        "Allow Folder Access to browse nearby images."
    @Published private var navigationSnapshot: NavigationSnapshot?

    private let requestCoordinator = OpenRequestCoordinator()
    private let folderAccess = FolderAccessController()
    private var currentURL: URL?
    private var currentSessionID = UUID()
    private var decodeTask: Task<Void, Never>?
    private var discoveryTask: Task<Void, Never>?
    private var displayIntervals: [UInt64: OSSignpostIntervalState] = [:]

    var canNavigatePrevious: Bool {
        navigationSnapshot?.canNavigatePrevious == true
    }

    var canNavigateNext: Bool {
        navigationSnapshot?.canNavigateNext == true
    }

    var navigationPosition: String? {
        guard let snapshot = navigationSnapshot else { return nil }
        return "\(snapshot.position) of \(snapshot.entries.count)"
    }

    var hasImageSession: Bool {
        currentURL != nil
    }

    var showsFolderAccessAction: Bool {
        if case .actionAvailable = authorization {
            return true
        }
        return false
    }

    func open(url: URL) {
        cancelSessionWork()

        let sessionID = UUID()
        folderAccess.replaceSelectedFileAccess(with: url)
        currentSessionID = sessionID
        currentURL = url
        navigationSnapshot = nil
        displayedImage = nil
        loadState = .loading(filename: url.lastPathComponent)
        authorization = .assessing
        folderAccessMessage = "Allow Folder Access to browse nearby images."
        updateWindowTitle(filename: url.lastPathComponent)

        startDecode(url: url, sessionID: sessionID, isNavigation: false)
        startAccessAssessment(url: url, sessionID: sessionID)
    }

    func navigatePrevious() {
        navigate(previous: true)
    }

    func navigateNext() {
        navigate(previous: false)
    }

    func imageDidCommitToView(generation: UInt64) {
        guard let state = displayIntervals.removeValue(forKey: generation) else {
            return
        }
        Diagnostics.navigationSignposter.endInterval(
            "SelectionToDisplay",
            state,
            "outcome=displayed"
        )
        Diagnostics.navigation.notice(
            "Image committed generation=\(generation)"
        )
    }

    func allowFolderAccess() {
        guard let currentURL else { return }
        authorization = .pickerPresented
        let parent = currentURL.deletingLastPathComponent()
        let sessionID = currentSessionID

        folderAccess.chooseFolder(expectedParent: parent) { [weak self] chosenURL in
            guard
                let self,
                self.currentSessionID == sessionID,
                self.currentURL == currentURL
            else {
                return
            }
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
                    "Folder selection rejected because it was not the expected parent"
                )
                return
            }

            self.folderAccess.retainAuthorization(for: chosenURL)
            self.authorization = .authorizedForSession(chosenURL)
            self.folderAccessMessage = "Folder access granted for this app session."
            self.startDiscovery(
                folderURL: chosenURL,
                selectedURL: currentURL,
                sessionID: sessionID
            )
        }
    }

    func manuallyBrowseFolder() {
        allowFolderAccess()
    }

    private func navigate(previous: Bool) {
        guard var snapshot = navigationSnapshot else { return }
        let target = previous ? snapshot.selectPrevious() : snapshot.selectNext()
        guard let target else { return }

        navigationSnapshot = snapshot
        currentURL = target.url
        loadState = .loading(filename: target.filename)
        updateWindowTitle(filename: target.filename)
        startDecode(
            url: target.url,
            sessionID: currentSessionID,
            isNavigation: true
        )
    }

    private func startDecode(url: URL, sessionID: UUID, isNavigation: Bool) {
        decodeTask?.cancel()
        decodeTask = Task { [weak self] in
            guard let self else { return }
            let request = await requestCoordinator.begin(url: url)
            guard currentSessionID == sessionID, currentURL == url else { return }
            Diagnostics.logReceivedURL(url, generation: request.generation)

            let state = Diagnostics.navigationSignposter.beginInterval(
                "SelectionToDisplay",
                id: Diagnostics.navigationSignposter.makeSignpostID(),
                "navigation=\(isNavigation)"
            )
            displayIntervals[request.generation] = state
            await loadImage(url: url, request: request, sessionID: sessionID)
        }
    }

    private func loadImage(url: URL, request: OpenRequest, sessionID: UUID) async {
        let decodeState = Diagnostics.imageSignposter.beginInterval(
            "CurrentImageDecode",
            id: Diagnostics.imageSignposter.makeSignpostID()
        )
        defer {
            Diagnostics.imageSignposter.endInterval("CurrentImageDecode", decodeState)
        }

        do {
            let loaded = try await SelectedImageLoader.load(url: url)
            guard
                currentSessionID == sessionID,
                currentURL == url,
                await requestCoordinator.isCurrent(request),
                !Task.isCancelled
            else {
                Diagnostics.recordStaleResult()
                endDisplayInterval(generation: request.generation, outcome: "stale")
                return
            }

            displayedImage = DisplayedImage(
                filename: url.lastPathComponent,
                image: loaded.image,
                generation: request.generation
            )
            loadState = .ready
            updateWindowTitle(filename: url.lastPathComponent)
        } catch is CancellationError {
            Diagnostics.recordDecodeCancellation()
            endDisplayInterval(generation: request.generation, outcome: "cancelled")
        } catch {
            guard
                currentSessionID == sessionID,
                currentURL == url,
                await requestCoordinator.isCurrent(request),
                !Task.isCancelled
            else {
                Diagnostics.recordStaleResult()
                endDisplayInterval(generation: request.generation, outcome: "stale")
                return
            }

            Diagnostics.recordDecodeFailure(error)
            endDisplayInterval(generation: request.generation, outcome: "failed")
            let message = (error as? SelectedImageLoadError)?.userMessage
                ?? "The image could not be displayed."
            loadState = .failed(
                filename: url.lastPathComponent,
                message: message
            )
        }
    }

    private func startAccessAssessment(url: URL, sessionID: UUID) {
        discoveryTask?.cancel()
        discoveryTask = Task { [weak self] in
            guard let self else { return }
            let parent = url.deletingLastPathComponent()

            if folderAccess.hasAuthorized(parent) {
                guard currentSessionID == sessionID, !Task.isCancelled else { return }
                authorization = .authorizedForSession(parent)
                await discover(
                    folderURL: parent,
                    selectedURL: url,
                    sessionID: sessionID
                )
                return
            }
            if folderAccess.wasDeclined(for: url) {
                guard currentSessionID == sessionID, !Task.isCancelled else { return }
                authorization = .declinedForImageSession
                return
            }

            let assessmentState = Diagnostics.authorizationSignposter.beginInterval(
                "AutomaticParentAccessAssessment",
                id: Diagnostics.authorizationSignposter.makeSignpostID()
            )
            let result = await ParentAccessAssessor.assess(selectedURL: url)
            Diagnostics.authorizationSignposter.endInterval(
                "AutomaticParentAccessAssessment",
                assessmentState
            )
            guard currentSessionID == sessionID, !Task.isCancelled else { return }

            if result.canEnumerate && result.canReadRepresentativeSibling {
                authorization = .automaticAccessAvailable
                await discover(
                    folderURL: parent,
                    selectedURL: url,
                    sessionID: sessionID
                )
            } else {
                showFolderAccessFallback(failure: result.failure)
            }
        }
    }

    private func startDiscovery(
        folderURL: URL,
        selectedURL: URL,
        sessionID: UUID
    ) {
        discoveryTask?.cancel()
        discoveryTask = Task { [weak self] in
            await self?.discover(
                folderURL: folderURL,
                selectedURL: selectedURL,
                sessionID: sessionID
            )
        }
    }

    private func discover(
        folderURL: URL,
        selectedURL: URL,
        sessionID: UUID
    ) async {
        let state = Diagnostics.folderSignposter.beginInterval(
            "FolderDiscovery",
            id: Diagnostics.folderSignposter.makeSignpostID()
        )
        defer {
            Diagnostics.folderSignposter.endInterval("FolderDiscovery", state)
        }

        do {
            let didStart = selectedURL.startAccessingSecurityScopedResource()
            defer {
                if didStart {
                    selectedURL.stopAccessingSecurityScopedResource()
                }
            }

            let result = try await FolderNavigationService.discover(
                folderURL: folderURL,
                selectedURL: selectedURL
            )
            guard currentSessionID == sessionID, !Task.isCancelled else { return }

            Diagnostics.recordFolderDiscovery(result)
            guard let snapshot = result.snapshot else {
                navigationSnapshot = nil
                Diagnostics.folder.notice(
                    "Selected image did not match discovered folder entries"
                )
                return
            }
            navigationSnapshot = snapshot
            updateWindowTitle(filename: snapshot.current.filename)
        } catch is CancellationError {
            Diagnostics.folder.debug("Folder discovery cancelled")
        } catch {
            guard currentSessionID == sessionID, !Task.isCancelled else { return }
            showFolderAccessFallback(
                failure: FolderAccessAssessmentFailure(
                    domain: (error as NSError).domain,
                    code: (error as NSError).code
                )
            )
        }
    }

    private func showFolderAccessFallback(
        failure: FolderAccessAssessmentFailure?
    ) {
        authorization = .actionAvailable
        Diagnostics.recordFolderAccessFailure(failure)
    }

    private func updateWindowTitle(filename: String) {
        if let navigationPosition {
            NSApp.mainWindow?.title = "\(filename) — \(navigationPosition)"
        } else {
            NSApp.mainWindow?.title = filename
        }
    }

    private func cancelSessionWork() {
        decodeTask?.cancel()
        discoveryTask?.cancel()
        endPendingDisplayIntervals(outcome: "superseded")
    }

    private func endDisplayInterval(generation: UInt64, outcome: StaticString) {
        guard let state = displayIntervals.removeValue(forKey: generation) else {
            return
        }
        Diagnostics.navigationSignposter.endInterval(
            "SelectionToDisplay",
            state,
            "outcome=\(outcome)"
        )
    }

    private func endPendingDisplayIntervals(outcome: StaticString) {
        let intervals = displayIntervals
        displayIntervals.removeAll()
        for state in intervals.values {
            Diagnostics.navigationSignposter.endInterval(
                "SelectionToDisplay",
                state,
                "outcome=\(outcome)"
            )
        }
    }
}

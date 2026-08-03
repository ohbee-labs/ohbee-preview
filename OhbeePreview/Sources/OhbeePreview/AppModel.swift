import AppKit
import Foundation
import OhbeeStage2Core
import OSLog

@MainActor
final class AppModel: ObservableObject {
    struct DisplayedImage {
        let sourceURL: URL
        let filename: String
        let image: NSImage
        let generation: UInt64
        let fileIdentity: Data?
        let fileSize: Int?
        let modificationDate: Date?
    }


    enum LoadState {
        case empty
        case emptyFolder
        case loading(filename: String)
        case ready
        case failed(filename: String, message: String)
    }

    @Published private(set) var displayedImage: DisplayedImage?
    @Published private(set) var loadState: LoadState = .empty
    @Published private(set) var authorization: FolderAuthorizationState = .notAssessed
    @Published private(set) var folderAccessMessage =
        "Allow access to this folder to browse nearby images."
    @Published private(set) var viewportState = ViewportState()
    @Published private(set) var effectiveViewportScale: CGFloat = 1
    @Published private var navigationSnapshot: NavigationSnapshot?
    @Published private(set) var folderGeneration: UInt64 = 0
    @Published private(set) var trashActionTarget: FinderActionTarget?
    @Published private(set) var finderActionError: String?
    @Published private(set) var thumbnailEviction: ThumbnailEvictionRequest?
    @Published private(set) var isFinderActionPending = false

    private let requestCoordinator = OpenRequestCoordinator()
    private let folderAccess = FolderAccessController()
    private let finderActions: FinderActionController
    private var currentURL: URL?
    private var currentSessionID = UUID()
    private var decodeTask: Task<Void, Never>?
    private var discoveryTask: Task<Void, Never>?
    private var displayIntervals: [UInt64: OSSignpostIntervalState] = [:]
    private var rotationsByURL: [URL: QuarterTurn] = [:]
    private var rotationOrder: [URL] = []
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var finderActionTask: Task<Void, Never>?
    private var finderActionID: UUID?
    private var thumbnailEvictionGeneration: UInt64 = 0

    init(finderActions: FinderActionController = FinderActionController()) {
        self.finderActions = finderActions
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler {
            Task { @MainActor [weak self] in
                guard self != nil else { return }
                Diagnostics.recordMemoryPressure()
            }
        }
        source.resume()
        memoryPressureSource = source
    }

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

    var thumbnailEntries: [NavigationEntry] {
        navigationSnapshot?.entries ?? []
    }

    var selectedThumbnailURL: URL? {
        navigationSnapshot?.current.url ?? displayedImage?.sourceURL
    }

    var hasImageSession: Bool {
        currentURL != nil
    }

    var canInspectImage: Bool {
        guard displayedImage != nil else { return false }
        if case .ready = loadState {
            return true
        }
        return false
    }

    var canRevealCurrentFile: Bool {
        currentFinderActionTarget != nil && !isFinderActionPending
    }

    var canMoveCurrentFileToTrash: Bool {
        currentFinderActionTarget != nil && !isFinderActionPending
    }

    var zoomPercentage: String {
        "\(Int((effectiveViewportScale * 100).rounded()))%"
    }

    var showsFolderAccessAction: Bool {
        guard displayedImage?.sourceURL == currentURL?.standardizedFileURL else {
            return false
        }
        guard case .ready = loadState else { return false }
        guard case .actionAvailable = authorization else { return false }
        return true
    }

    var canManuallyRequestFolderAccess: Bool {
        guard displayedImage?.sourceURL == currentURL?.standardizedFileURL else {
            return false
        }
        guard case .ready = loadState else { return false }
        switch authorization {
        case .actionAvailable, .declinedForImageSession:
            return true
        default:
            return false
        }
    }

    func open(url: URL) {
        cancelSessionWork()
        folderGeneration &+= 1

        let sessionID = UUID()
        folderAccess.replaceSelectedFileAccess(with: url)
        currentSessionID = sessionID
        currentURL = url
        navigationSnapshot = nil
        displayedImage = nil
        rotationsByURL.removeAll()
        rotationOrder.removeAll()
        viewportState = ViewportState()
        effectiveViewportScale = 1
        loadState = .loading(filename: url.lastPathComponent)
        authorization = .assessing
        folderAccessMessage =
            "Allow access to this folder to browse nearby images."
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

    func selectThumbnail(_ entry: NavigationEntry) {
        guard var snapshot = navigationSnapshot else { return }
        guard snapshot.current.url != entry.url else { return }
        guard let target = snapshot.select(url: entry.url) else { return }
        navigationSnapshot = snapshot
        navigate(to: target)
    }

    func fitToWindow() {
        guard canInspectImage else { return }
        let start = ContinuousClock.now
        viewportState.resetToFit()
        Diagnostics.recordViewportReset()
        Diagnostics.recordZoomCommand(
            name: "FitToWindow",
            duration: start.duration(to: .now)
        )
    }

    func showActualSize() {
        guard canInspectImage else { return }
        let start = ContinuousClock.now
        viewportState.showActualSize()
        Diagnostics.recordViewportReset()
        Diagnostics.recordZoomCommand(
            name: "ActualSize",
            duration: start.duration(to: .now)
        )
    }

    func zoomIn() {
        guard canInspectImage else { return }
        let start = ContinuousClock.now
        let baseScale = viewportState.mode == .manual
            ? viewportState.scale
            : Double(effectiveViewportScale)
        viewportState.zoomIn(from: baseScale)
        Diagnostics.recordZoomCommand(
            name: "ZoomIn",
            duration: start.duration(to: .now)
        )
    }

    func zoomOut() {
        guard canInspectImage else { return }
        let start = ContinuousClock.now
        let baseScale = viewportState.mode == .manual
            ? viewportState.scale
            : Double(effectiveViewportScale)
        viewportState.zoomOut(from: baseScale)
        Diagnostics.recordZoomCommand(
            name: "ZoomOut",
            duration: start.duration(to: .now)
        )
    }

    func rotateLeft() {
        rotate(right: false)
    }

    func rotateRight() {
        rotate(right: true)
    }

    func toggleFullScreen() {
        guard hasImageSession, let window = NSApp.mainWindow else { return }
        let start = ContinuousClock.now
        window.toggleFullScreen(nil)
        Diagnostics.recordFullscreenCommand(
            duration: start.duration(to: .now)
        )
    }

    func revealCurrentInFinder() {
        guard let target = currentFinderActionTarget else { return }
        finderActionError = nil
        isFinderActionPending = true
        let actionID = UUID()
        finderActionID = actionID
        Diagnostics.recordRevealRequested()
        let started = ContinuousClock.now
        finderActionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if finderActionID == actionID {
                    finderActionID = nil
                    isFinderActionPending = false
                }
            }
            do {
                try await finderActions.reveal(target)
                Diagnostics.recordRevealSucceeded(
                    duration: started.duration(to: .now)
                )
            } catch is CancellationError {
                return
            } catch {
                guard finderActionID == actionID else { return }
                finderActionError = (error as? FinderActionError)?.userMessage
                    ?? "The image could not be revealed in Finder."
                Diagnostics.recordRevealFailed(error)
            }
        }
    }

    func moveCurrentToTrash() {
        // This value is deliberately immutable. Neither confirmation nor the
        // eventual file operation reads currentURL again.
        guard let target = currentFinderActionTarget else { return }
        finderActionError = nil
        isFinderActionPending = true
        let actionID = UUID()
        finderActionID = actionID
        trashActionTarget = target
        let started = ContinuousClock.now
        finderActionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if finderActionID == actionID {
                    finderActionID = nil
                    isFinderActionPending = false
                    trashActionTarget = nil
                }
            }
            do {
                let outcome = try await finderActions.confirmAndTrash(target) {
                    self.isValidFinderActionTarget(target)
                }
                guard outcome == .succeeded else { return }
                Diagnostics.recordTrashSucceeded(
                    duration: started.duration(to: .now)
                )
                guard target.sessionID == currentSessionID else {
                    Diagnostics.recordStaleFinderAction()
                    return
                }
                reconcileSuccessfulTrash(target)
            } catch is CancellationError {
                return
            } catch {
                guard finderActionID == actionID else { return }
                finderActionError = (error as? FinderActionError)?.userMessage
                    ?? "The image could not be moved to Trash."
                if case let FinderActionError.trashFailed(domain, code) = error {
                    Diagnostics.recordTrashFailed(domain: domain, code: code)
                } else {
                    Diagnostics.recordTrashFailed(error)
                }
            }
        }
    }

    func dismissFinderActionError() {
        finderActionError = nil
    }

    func viewportEffectiveScaleChanged(_ scale: CGFloat) {
        guard scale.isFinite, scale > 0 else {
            Diagnostics.recordInvalidTransform()
            return
        }
        let clamped = CGFloat(
            ViewportState.clampedScale(Double(scale))
        )
        guard abs(effectiveViewportScale - clamped) > .ulpOfOne else { return }
        effectiveViewportScale = clamped
    }

    func viewportPinchScaleChanged(_ scale: CGFloat) {
        guard canInspectImage, scale.isFinite, scale > 0 else {
            Diagnostics.recordInvalidTransform()
            return
        }
        let clamped = ViewportState.clampedScale(Double(scale))
        guard
            viewportState.mode != .manual
                || abs(viewportState.scale - clamped) > Double.ulpOfOne
        else {
            return
        }
        viewportState.mode = .manual
        viewportState.scale = clamped
    }

    func viewportFitCalculated(duration: Duration) {
        Diagnostics.recordFitCalculation(duration: duration)
    }

    func viewportRejectedInvalidTransform() {
        Diagnostics.recordInvalidTransform()
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

    func dismissFolderAccessPrompt() {
        guard let currentURL else { return }
        folderAccess.markDeclined(for: currentURL)
        authorization = .declinedForImageSession
    }

    private func navigate(previous: Bool) {
        guard var snapshot = navigationSnapshot else { return }
        let target = previous ? snapshot.selectPrevious() : snapshot.selectNext()
        guard let target else { return }

        navigationSnapshot = snapshot
        navigate(to: target)
    }

    private func navigate(to target: NavigationEntry) {
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
                sourceURL: url.standardizedFileURL,
                filename: url.lastPathComponent,
                image: loaded.image,
                generation: request.generation,
                fileIdentity: loaded.fileIdentity,
                fileSize: loaded.fileSize,
                modificationDate: loaded.modificationDate
            )
            viewportState = ViewportState(
                mode: .fit,
                scale: 1,
                rotation: rotationsByURL[url.standardizedFileURL] ?? .zero
            )
            effectiveViewportScale = 1
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

    private func rotate(right: Bool) {
        guard canInspectImage, let displayedImage else { return }
        let start = ContinuousClock.now
        let current = viewportState.rotation
        let updated = right ? current.rotatedRight() : current.rotatedLeft()
        viewportState.rotation = updated
        storeRotation(updated, for: displayedImage.sourceURL)
        Diagnostics.recordRotationCommand(
            duration: start.duration(to: .now)
        )
    }

    private func storeRotation(_ rotation: QuarterTurn, for url: URL) {
        let normalized = url.standardizedFileURL
        rotationsByURL[normalized] = rotation
        rotationOrder.removeAll(where: { $0 == normalized })
        if rotation == .zero {
            rotationsByURL.removeValue(forKey: normalized)
            return
        }

        rotationOrder.append(normalized)
        let maximumRememberedRotations = 512
        if rotationOrder.count > maximumRememberedRotations {
            let evicted = rotationOrder.removeFirst()
            rotationsByURL.removeValue(forKey: evicted)
        }
    }

    private func updateWindowTitle(filename: String) {
        if let navigationPosition {
            NSApp.mainWindow?.title = "\(filename) — \(navigationPosition)"
        } else {
            NSApp.mainWindow?.title = filename
        }
    }

    private var currentFinderActionTarget: FinderActionTarget? {
        guard
            case .ready = loadState,
            let displayedImage,
            let currentURL,
            displayedImage.sourceURL == currentURL.standardizedFileURL
        else { return nil }
        return FinderActionTarget(
            sessionID: currentSessionID,
            url: displayedImage.sourceURL,
            filename: displayedImage.filename,
            imageGeneration: displayedImage.generation,
            fileIdentity: displayedImage.fileIdentity,
            fileSize: displayedImage.fileSize,
            modificationDate: displayedImage.modificationDate
        )
    }

    private func isValidFinderActionTarget(_ target: FinderActionTarget) -> Bool {
        guard target.sessionID == currentSessionID else {
            Diagnostics.recordStaleFinderAction()
            return false
        }
        if let snapshot = navigationSnapshot {
            let exists = snapshot.entries.contains { entry in
                entry.url == target.url
                    && (target.fileIdentity == nil
                        || entry.fileIdentity == nil
                        || entry.fileIdentity == target.fileIdentity)
            }
            if !exists { Diagnostics.recordStaleFinderAction() }
            return exists
        }
        let valid = currentURL?.standardizedFileURL == target.url
            && displayedImage?.generation == target.imageGeneration
        if !valid { Diagnostics.recordStaleFinderAction() }
        return valid
    }

    private func reconcileSuccessfulTrash(_ target: FinderActionTarget) {
        let updateStarted = ContinuousClock.now
        folderAccess.releaseSelectedFileAccess(ifMatching: target.url)
        rotationsByURL.removeValue(forKey: target.url)
        rotationOrder.removeAll(where: { $0 == target.url })
        thumbnailEvictionGeneration &+= 1
        thumbnailEviction = ThumbnailEvictionRequest(
            url: target.url,
            generation: thumbnailEvictionGeneration
        )
        let evictionGeneration = thumbnailEvictionGeneration
        DispatchQueue.main.async { [weak self] in
            guard self?.thumbnailEviction?.generation == evictionGeneration else {
                return
            }
            self?.thumbnailEviction = nil
        }
        Diagnostics.recordThumbnailTrashEviction()

        if let snapshot = navigationSnapshot,
           let removal = snapshot.removing(
               url: target.url,
               fileIdentity: target.fileIdentity
           ) {
            navigationSnapshot = removal.selectedEntry.flatMap {
                NavigationSnapshot(
                    entries: removal.remainingEntries,
                    selectedURL: $0.url,
                    selectedIdentity: $0.fileIdentity
                )
            }
            if !removal.removedWasCurrent,
               currentURL?.standardizedFileURL != target.url {
                if let current = removal.selectedEntry {
                    updateWindowTitle(filename: current.filename)
                }
                Diagnostics.recordPostTrashCollectionUpdate(
                    duration: updateStarted.duration(to: .now),
                    becameEmpty: false
                )
                return
            }
            transitionAfterTrashingCurrent(to: removal.selectedEntry)
        } else if currentURL?.standardizedFileURL == target.url {
            navigationSnapshot = nil
            transitionAfterTrashingCurrent(to: nil)
        } else {
            Diagnostics.recordStaleFinderAction()
            return
        }
        Diagnostics.recordPostTrashCollectionUpdate(
            duration: updateStarted.duration(to: .now),
            becameEmpty: currentURL == nil
        )
    }

    private func transitionAfterTrashingCurrent(to entry: NavigationEntry?) {
        decodeTask?.cancel()
        displayedImage = nil
        effectiveViewportScale = 1
        viewportState = ViewportState()
        if let entry {
            currentURL = entry.url
            loadState = .loading(filename: entry.filename)
            updateWindowTitle(filename: entry.filename)
            startDecode(
                url: entry.url,
                sessionID: currentSessionID,
                isNavigation: true
            )
        } else {
            currentURL = nil
            loadState = .emptyFolder
            NSApp.mainWindow?.title = "Ohbee Preview"
            Diagnostics.recordEmptyFolderTransition()
        }
    }

    private func cancelSessionWork() {
        decodeTask?.cancel()
        discoveryTask?.cancel()
        finderActionTask?.cancel()
        finderActionTask = nil
        finderActionID = nil
        isFinderActionPending = false
        trashActionTarget = nil
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

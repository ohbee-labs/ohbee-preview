import Foundation
import OhbeeStage2Core
import OSLog

@MainActor
enum Diagnostics {
    static let subsystem = "com.ohbee.preview"

    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let open = Logger(subsystem: subsystem, category: "open")
    static let authorization = Logger(subsystem: subsystem, category: "authorization")
    static let folder = Logger(subsystem: subsystem, category: "folder")
    static let image = Logger(subsystem: subsystem, category: "image")
    static let navigation = Logger(subsystem: subsystem, category: "navigation")
    static let viewport = Logger(subsystem: subsystem, category: "viewport")
    static let thumbnail = Logger(subsystem: subsystem, category: "thumbnail")
    static let cache = Logger(subsystem: subsystem, category: "cache")
    static let gif = Logger(subsystem: subsystem, category: "gif")
    static let finderAction = Logger(subsystem: subsystem, category: "finder-action")

    static let lifecycleSignposter = OSSignposter(
        subsystem: subsystem,
        category: "lifecycle"
    )
    static let openSignposter = OSSignposter(
        subsystem: subsystem,
        category: "open"
    )
    static let authorizationSignposter = OSSignposter(
        subsystem: subsystem,
        category: "authorization"
    )
    static let imageSignposter = OSSignposter(
        subsystem: subsystem,
        category: "image"
    )
    static let folderSignposter = OSSignposter(
        subsystem: subsystem,
        category: "folder"
    )
    static let navigationSignposter = OSSignposter(
        subsystem: subsystem,
        category: "navigation"
    )
    static let viewportSignposter = OSSignposter(
        subsystem: subsystem,
        category: "viewport"
    )
    static let thumbnailSignposter = OSSignposter(
        subsystem: subsystem,
        category: "thumbnail"
    )
    static let gifSignposter = OSSignposter(
        subsystem: subsystem,
        category: "gif"
    )
    static let finderActionSignposter = OSSignposter(
        subsystem: subsystem,
        category: "finder-action"
    )

    private static let applicationEnteredAt = ContinuousClock.now
    private static var cancelledDecodeCount = 0
    private static var staleResultCount = 0
    private static var folderAccessFailureCount = 0
    private static var decodeFailureCount = 0
    private static var viewportResetCount = 0
    private static var invalidTransformCount = 0
    private static var memoryPressureCount = 0
    private static var gifFramesDisplayed = 0
    private static var gifFramesSkipped = 0
    private static var gifPlaybackStarts = 0
    private static var gifPlaybackStops = 0
    private static var gifPauses = 0
    private static var gifResumes = 0
    private static var gifLoopCompletions = 0
    private static var gifDecodeCancellations = 0
    private static var gifStaleFrames = 0
    private static var gifFailures = 0
    private static var gifMemoryPurges = 0
    private static var revealRequests = 0
    private static var trashConfirmations = 0
    private static var trashCancellations = 0
    private static var trashSuccesses = 0
    private static var trashFailures = 0
    private static var staleFinderActions = 0
    private static var emptyFolderTransitions = 0

    static func markApplicationEntry() {
        _ = applicationEnteredAt
    }

    static func privacySafeError(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain):\(nsError.code)"
    }

    #if DEBUG
    static let permitsDetailedPaths =
        ProcessInfo.processInfo.environment["OHBEE_DEBUG_PATHS"] == "1"
    #else
    static let permitsDetailedPaths = false
    #endif

    static func logReceivedURL(_ url: URL, generation: UInt64) {
        let sinceStart = applicationEnteredAt.duration(to: .now)
        if permitsDetailedPaths {
            open.debug(
                "Received open request generation=\(generation) sinceStart=\(String(describing: sinceStart), privacy: .public) path=\(url.path, privacy: .private)"
            )
        } else {
            open.notice(
                "Received open request generation=\(generation) sinceStart=\(String(describing: sinceStart), privacy: .public) extension=\(url.pathExtension, privacy: .private(mask: .hash))"
            )
        }
    }

    static func primaryWindowReady() {
        let duration = applicationEnteredAt.duration(to: .now)
        lifecycle.notice(
            "Primary window ready sinceStart=\(String(describing: duration), privacy: .public)"
        )
        lifecycleSignposter.emitEvent("PrimaryWindowReady")
    }

    static func recordFolderDiscovery(_ result: FolderNavigationResult) {
        folder.notice(
            """
            Folder discovery completed eligible=\(result.eligibleImageCount) \
            enumeration=\(String(describing: result.enumerationDuration), privacy: .public) \
            sort=\(String(describing: result.sortingDuration), privacy: .public) \
            match=\(String(describing: result.matchingDuration), privacy: .public)
            """
        )
    }

    static func recordDecodeCancellation() {
        cancelledDecodeCount += 1
        image.debug("Decode cancelled total=\(cancelledDecodeCount)")
    }

    static func recordStaleResult() {
        staleResultCount += 1
        navigation.notice("Stale result rejected total=\(staleResultCount)")
    }

    static func recordFolderAccessFailure(
        _ failure: FolderAccessAssessmentFailure?
    ) {
        folderAccessFailureCount += 1
        if let failure {
            authorization.notice(
                """
                Folder access unavailable total=\(folderAccessFailureCount) \
                domain=\(failure.domain, privacy: .public) code=\(failure.code)
                """
            )
        } else {
            authorization.notice(
                "Folder access unavailable total=\(folderAccessFailureCount)"
            )
        }
    }

    static func recordDecodeFailure(_ error: Error) {
        decodeFailureCount += 1
        image.error(
            """
            Decode failed total=\(decodeFailureCount) \
            category=\(privacySafeError(error), privacy: .public)
            """
        )
    }

    static func recordFitCalculation(duration: Duration) {
        viewport.debug(
            "Fit calculated duration=\(String(describing: duration), privacy: .public)"
        )
        viewportSignposter.emitEvent(
            "FitCalculated",
            "duration=\(String(describing: duration))"
        )
    }

    #if DEBUG
    static func recordStaleViewportCallback(
        generation: UInt64,
        committedGeneration: UInt64
    ) {
        viewport.debug(
            "Stale viewport callback rejected generation=\(generation) committed=\(committedGeneration)"
        )
    }

    static func recordViewportGeometry(
        source: StaticString,
        generation: UInt64,
        pixelSize: CGSize,
        rotation: QuarterTurn,
        magnification: CGFloat,
        clipBounds: CGRect,
        documentFrame: CGRect,
        contentInsets: NSEdgeInsets,
        viewportSize: CGSize,
        constrainedOrigin: CGPoint
    ) {
        viewport.debug(
            """
            Geometry source=\(source) generation=\(generation) \
            pixels=\(String(describing: pixelSize), privacy: .public) \
            rotation=\(rotation.rawValue) magnification=\(magnification) \
            clip=\(String(describing: clipBounds), privacy: .public) \
            document=\(String(describing: documentFrame), privacy: .public) \
            insets=\(String(describing: contentInsets), privacy: .public) \
            viewport=\(String(describing: viewportSize), privacy: .public) \
            constrainedOrigin=\(String(describing: constrainedOrigin), privacy: .public)
            """
        )
    }
    #endif

    static func recordZoomCommand(name: String, duration: Duration) {
        viewport.notice(
            """
            Zoom command=\(name, privacy: .public) \
            duration=\(String(describing: duration), privacy: .public)
            """
        )
        viewportSignposter.emitEvent(
            "ZoomCommand",
            "command=\(name) duration=\(String(describing: duration))"
        )
    }

    static func recordRotationCommand(duration: Duration) {
        viewport.notice(
            "Rotation command duration=\(String(describing: duration), privacy: .public)"
        )
        viewportSignposter.emitEvent(
            "RotationCommand",
            "duration=\(String(describing: duration))"
        )
    }

    static func recordFullscreenCommand(duration: Duration) {
        viewport.notice(
            "Fullscreen command duration=\(String(describing: duration), privacy: .public)"
        )
        viewportSignposter.emitEvent(
            "FullscreenCommand",
            "duration=\(String(describing: duration))"
        )
    }

    static func recordViewportReset() {
        viewportResetCount += 1
        viewport.debug("Viewport reset total=\(viewportResetCount)")
    }

    static func recordInvalidTransform() {
        invalidTransformCount += 1
        viewport.error("Invalid transform rejected total=\(invalidTransformCount)")
    }

    static func recordThumbnailCache(
        hit: Bool,
        snapshot: ThumbnailCache.Snapshot
    ) {
        cache.debug(
            """
            Thumbnail cache result=\(hit ? "hit" : "miss", privacy: .public) \
            count=\(snapshot.count) cost=\(snapshot.cost) limit=\(snapshot.costLimit) \
            hits=\(snapshot.hits) misses=\(snapshot.misses) hitRate=\(snapshot.hitRate) \
            insertions=\(snapshot.insertions) evictions=\(snapshot.evictions)
            """
        )
    }

    static func recordThumbnailGenerated(
        duration: Duration,
        cache: ThumbnailCache.Snapshot,
        scheduler: ThumbnailScheduler.Snapshot,
        generated: Int,
        averageSeconds: Double
    ) {
        thumbnail.debug(
            """
            Thumbnail generated duration=\(String(describing: duration), privacy: .public) \
            total=\(generated) averageSeconds=\(averageSeconds) \
            active=\(scheduler.activeDecodes) waiting=\(scheduler.waiting) \
            cacheCount=\(cache.count) cacheCost=\(cache.cost)
            """
        )
        thumbnailSignposter.emitEvent(
            "ThumbnailGenerated",
            "active=\(scheduler.activeDecodes) cost=\(cache.cost)"
        )
    }

    static func recordThumbnailCancellation(
        scheduler: ThumbnailScheduler.Snapshot
    ) {
        thumbnail.debug(
            "Thumbnail cancelled total=\(scheduler.cancellations) active=\(scheduler.activeDecodes) waiting=\(scheduler.waiting)"
        )
    }

    static func recordThumbnailFailure(_ error: Error) {
        thumbnail.error(
            "Thumbnail failed category=\(privacySafeError(error), privacy: .public)"
        )
    }

    static func recordMemoryPressure() {
        memoryPressureCount += 1
        viewport.notice("Memory pressure observed total=\(memoryPressureCount)")
    }

    static func recordGIFClassification(
        kind: AnimatedImageKind,
        duration: Duration
    ) {
        let classification: StaticString
        let frameCount: Int
        let invalidTiming: Int
        switch kind {
        case .notGIF:
            classification = "static"
            frameCount = 0
            invalidTiming = 0
        case .singleFrameGIF:
            classification = "single-frame"
            frameCount = 1
            invalidTiming = 0
        case let .animated(descriptor):
            classification = "animated"
            frameCount = descriptor.frameCount
            invalidTiming = descriptor.invalidTimingCount
        }
        gif.notice(
            "GIF classified kind=\(classification) frames=\(frameCount) invalidTiming=\(invalidTiming) duration=\(String(describing: duration), privacy: .public)"
        )
        gifSignposter.emitEvent(
            "GIFClassified",
            "frames=\(frameCount) duration=\(String(describing: duration))"
        )
    }

    static func recordGIFPlaybackStart(descriptor: AnimatedImageDescriptor) {
        gifPlaybackStarts += 1
        gif.notice(
            "GIF playback started total=\(gifPlaybackStarts) frames=\(descriptor.frameCount)"
        )
    }

    static func recordGIFStop(reason: StaticString) {
        gifPlaybackStops += 1
        gif.notice("GIF playback stopped total=\(gifPlaybackStops) reason=\(reason)")
    }

    static func recordGIFPause() {
        gifPauses += 1
        gif.notice("GIF playback paused total=\(gifPauses)")
    }

    static func recordGIFResume() {
        gifResumes += 1
        gif.notice("GIF playback resumed total=\(gifResumes)")
    }

    static func recordGIFFrameDecode(duration: Duration) {
        gif.debug(
            "GIF frame decoded duration=\(String(describing: duration), privacy: .public)"
        )
        gifSignposter.emitEvent(
            "GIFFrameDecoded",
            "duration=\(String(describing: duration))"
        )
    }

    static func recordGIFFrameDisplayed(lateness: Duration) {
        gifFramesDisplayed += 1
        gif.debug(
            "GIF frame displayed total=\(gifFramesDisplayed) lateness=\(String(describing: lateness), privacy: .public)"
        )
    }

    static func recordGIFFirstFrameDisplay(duration: Duration) {
        gif.notice(
            "GIF first frame displayed duration=\(String(describing: duration), privacy: .public)"
        )
        gifSignposter.emitEvent(
            "GIFFirstFrameDisplayed",
            "duration=\(String(describing: duration))"
        )
    }

    static func recordGIFFramesSkipped(_ count: Int) {
        gifFramesSkipped += count
        gif.notice("GIF frames skipped count=\(count) total=\(gifFramesSkipped)")
    }

    static func recordGIFLoopCompletion() {
        gifLoopCompletions += 1
        gif.debug("GIF loop completed total=\(gifLoopCompletions)")
    }

    static func recordGIFDecodeCancellation() {
        gifDecodeCancellations += 1
        gif.debug("GIF decode cancelled total=\(gifDecodeCancellations)")
    }

    static func recordGIFStaleFrame() {
        gifStaleFrames += 1
        gif.notice("Stale GIF frame rejected total=\(gifStaleFrames)")
    }

    static func recordGIFFailure(_ error: Error) {
        gifFailures += 1
        gif.error(
            "GIF decode failed total=\(gifFailures) category=\(privacySafeError(error), privacy: .public)"
        )
    }

    static func recordGIFFrameCache(
        hit: Bool,
        store: AnimatedFrameStore
    ) async {
        let snapshot = await store.snapshot()
        gif.debug(
            "GIF frame cache result=\(hit ? "hit" : "miss", privacy: .public) count=\(snapshot.count) cost=\(snapshot.cost) hits=\(snapshot.hits) misses=\(snapshot.misses) evictions=\(snapshot.evictions)"
        )
    }

    static func recordGIFMemoryPurge(store: AnimatedFrameStore) async {
        gifMemoryPurges += 1
        let snapshot = await store.snapshot()
        gif.notice(
            "GIF frame memory purged total=\(gifMemoryPurges) retained=\(snapshot.count) cost=\(snapshot.cost)"
        )
    }

    static func recordRevealRequested() {
        revealRequests += 1
        finderAction.notice("Reveal requested total=\(revealRequests)")
    }

    static func recordRevealSucceeded(duration: Duration) {
        finderAction.notice(
            "Reveal succeeded duration=\(String(describing: duration), privacy: .public)"
        )
    }

    static func recordRevealFailed(_ error: Error) {
        finderAction.error(
            "Reveal failed category=\(privacySafeError(error), privacy: .public)"
        )
    }

    static func recordTrashConfirmationShown() {
        trashConfirmations += 1
        finderAction.notice("Trash confirmation shown total=\(trashConfirmations)")
    }

    static func recordTrashConfirmationCancelled() {
        trashCancellations += 1
        finderAction.notice("Trash confirmation cancelled total=\(trashCancellations)")
    }

    static func recordTrashSucceeded(duration: Duration) {
        trashSuccesses += 1
        finderAction.notice(
            "Trash succeeded total=\(trashSuccesses) duration=\(String(describing: duration), privacy: .public)"
        )
        finderActionSignposter.emitEvent(
            "TrashSucceeded",
            "duration=\(String(describing: duration))"
        )
    }

    static func recordTrashFailed(_ error: Error) {
        trashFailures += 1
        finderAction.error(
            "Trash failed total=\(trashFailures) category=\(privacySafeError(error), privacy: .public)"
        )
    }

    static func recordTrashFailed(domain: String, code: Int) {
        trashFailures += 1
        finderAction.error(
            "Trash failed total=\(trashFailures) domain=\(domain, privacy: .public) code=\(code)"
        )
    }

    static func recordPostTrashCollectionUpdate(
        duration: Duration,
        becameEmpty: Bool
    ) {
        finderAction.notice(
            "Post-Trash collection updated empty=\(becameEmpty) duration=\(String(describing: duration), privacy: .public)"
        )
    }

    static func recordThumbnailTrashEviction() {
        finderAction.debug("Thumbnail eviction requested after Trash")
    }

    static func recordThumbnailEviction(removed: Int) {
        finderAction.debug("Thumbnail eviction completed entries=\(removed)")
    }

    static func recordStaleFinderAction() {
        staleFinderActions += 1
        finderAction.notice("Stale Finder action rejected total=\(staleFinderActions)")
    }

    static func recordEmptyFolderTransition() {
        emptyFolderTransitions += 1
        finderAction.notice("Empty-folder transition total=\(emptyFolderTransitions)")
    }
}

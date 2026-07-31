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

    private static let applicationEnteredAt = ContinuousClock.now
    private static var cancelledDecodeCount = 0
    private static var staleResultCount = 0
    private static var folderAccessFailureCount = 0
    private static var decodeFailureCount = 0

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
}

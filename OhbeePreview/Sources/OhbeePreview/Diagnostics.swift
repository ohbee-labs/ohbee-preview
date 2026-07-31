import Foundation
import OSLog

enum Diagnostics {
    static let subsystem = "com.ohbee.preview"

    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let open = Logger(subsystem: subsystem, category: "open")
    static let authorization = Logger(subsystem: subsystem, category: "authorization")
    static let image = Logger(subsystem: subsystem, category: "image")

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

    private static let applicationEnteredAt = ContinuousClock.now

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
}

import AppKit

@MainActor
final class AccessibilityCoordinator {
    private var lastAnnouncement: String?
    private var lastAnnouncementAt: ContinuousClock.Instant?

    func announce(_ message: String, priority: NSAccessibilityPriorityLevel = .medium) {
        let now = ContinuousClock.now
        if message == lastAnnouncement,
           let lastAnnouncementAt,
           lastAnnouncementAt.duration(to: now) < .seconds(1) {
            Diagnostics.recordDuplicateAccessibilityAnnouncementSuppressed()
            return
        }
        lastAnnouncement = message
        lastAnnouncementAt = now
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: priority.rawValue
            ]
        )
    }
}

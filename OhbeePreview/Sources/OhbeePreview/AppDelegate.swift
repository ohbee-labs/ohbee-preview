import AppKit
import OhbeeStage2Core

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    private var pendingURL: URL?

    func attach(model: AppModel) {
        self.model = model
        if let pendingURL {
            self.pendingURL = nil
            deliver(pendingURL)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diagnostics.lifecycle.notice("Application finished launching")
        Diagnostics.lifecycleSignposter.emitEvent("ApplicationDidFinishLaunching")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let first = OpenURLPolicy.firstSupported(in: urls) else { return }
        if model == nil {
            pendingURL = first
        } else {
            deliver(first)
        }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map(URL.init(fileURLWithPath:))
        guard let first = OpenURLPolicy.firstSupported(in: urls) else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }
        if model == nil {
            pendingURL = first
        } else {
            deliver(first)
        }
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        return true
    }

    private func deliver(_ url: URL) {
        model?.open(url: url)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
}

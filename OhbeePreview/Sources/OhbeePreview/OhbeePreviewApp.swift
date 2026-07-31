import SwiftUI

@main
struct OhbeePreviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    init() {
        Diagnostics.markApplicationEntry()
    }

    var body: some Scene {
        WindowGroup("Ohbee Preview", id: "viewer") {
            ContentView(model: model)
                .onAppear {
                    appDelegate.attach(model: model)
                    Diagnostics.primaryWindowReady()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Allow Folder Access…") {
                    model.manuallyBrowseFolder()
                }
                .disabled({
                    if case .empty = model.presentation { return true }
                    return false
                }())
            }
        }
    }
}

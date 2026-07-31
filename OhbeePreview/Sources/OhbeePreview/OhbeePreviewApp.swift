import SwiftUI

@main
struct OhbeePreviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @State private var didFinishInitialAppearance = false

    init() {
        Diagnostics.markApplicationEntry()
    }

    var body: some Scene {
        WindowGroup("Ohbee Preview", id: "viewer") {
            ContentView(model: model)
                .onAppear {
                    guard !didFinishInitialAppearance else { return }
                    didFinishInitialAppearance = true
                    appDelegate.attach(model: model)
                    Diagnostics.primaryWindowReady()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Allow Folder Access…") {
                    model.manuallyBrowseFolder()
                }
                .disabled(!model.hasImageSession)
            }
            CommandMenu("Navigate") {
                Button("Previous Image") {
                    model.navigatePrevious()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(!model.canNavigatePrevious)

                Button("Next Image") {
                    model.navigateNext()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(!model.canNavigateNext)
            }
        }
    }
}

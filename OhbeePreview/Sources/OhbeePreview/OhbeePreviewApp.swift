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
                .disabled(!model.canManuallyRequestFolderAccess)
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
            CommandMenu("Image") {
                Button("Fit to Window") {
                    model.fitToWindow()
                }
                .keyboardShortcut("9", modifiers: .command)
                .disabled(!model.canInspectImage)

                Button("Actual Size") {
                    model.showActualSize()
                }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(!model.canInspectImage)

                Divider()

                Button("Zoom In") {
                    model.zoomIn()
                }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(!model.canInspectImage)

                Button("Zoom Out") {
                    model.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!model.canInspectImage)

                Divider()

                Button("Rotate Left") {
                    model.rotateLeft()
                }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(!model.canInspectImage)

                Button("Rotate Right") {
                    model.rotateRight()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!model.canInspectImage)
            }
            CommandGroup(after: .help) {
                Button("Make Ohbee Preview the Default Viewer…") {
                    DefaultViewerHelp.show()
                }
            }
        }
    }
}

@MainActor
private enum DefaultViewerHelp {
    static func show() {
        let alert = NSAlert()
        alert.messageText = "Make Ohbee Preview Your Default Viewer"
        alert.informativeText = """
        In Finder, select an image and choose File > Get Info. Under Open with, choose Ohbee Preview, then select Change All.

        macOS may store this choice separately for JPEG, PNG, HEIC/HEIF, GIF, and TIFF files.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

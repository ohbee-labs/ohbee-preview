import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            switch model.presentation {
            case .empty:
                ContentUnavailableView(
                    "Open an Image",
                    systemImage: "photo",
                    description: Text("Open a supported image from Finder.")
                )
            case let .loading(filename):
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading \(filename)…")
                        .foregroundStyle(.secondary)
                }
            case let .ready(filename, image, generation):
                VStack(spacing: 0) {
                    if model.showsFolderAccessAction {
                        folderAccessBanner
                    }
                    CommittedImageView(
                        image: image,
                        accessibilityLabel: "Image \(filename)"
                    ) {
                        model.imageDidCommitToView(generation: generation)
                    }
                        .accessibilityLabel("Image \(filename)")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(20)
                }
            case let .failed(filename, message):
                ContentUnavailableView(
                    "Unable to Open \(filename)",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            }
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    private var folderAccessBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
            Text(model.folderAccessMessage)
            Spacer()
            Button("Allow Folder Access") {
                model.allowFolderAccess()
            }
        }
        .padding(10)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }
}

private struct CommittedImageView: NSViewRepresentable {
    let image: NSImage
    let accessibilityLabel: String
    let onCommit: @MainActor () -> Void

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        view.setAccessibilityLabel(accessibilityLabel)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        view.image = image
        view.setAccessibilityLabel(accessibilityLabel)
        DispatchQueue.main.async {
            onCommit()
        }
    }
}

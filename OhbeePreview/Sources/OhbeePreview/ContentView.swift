import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.showsFolderAccessAction {
                folderAccessBanner
            }

            viewer

            if model.hasImageSession {
                navigationBar
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 640, minHeight: 480)
    }

    @ViewBuilder
    private var viewer: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            if let displayed = model.displayedImage {
                CommittedImageView(
                    image: displayed.image,
                    accessibilityLabel: "Image \(displayed.filename)"
                ) {
                    model.imageDidCommitToView(generation: displayed.generation)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            } else {
                emptyViewerState
            }

            if model.displayedImage != nil {
                retainedImageStatus
            }
        }
    }

    @ViewBuilder
    private var emptyViewerState: some View {
        switch model.loadState {
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
            .accessibilityElement(children: .combine)
        case .ready:
            EmptyView()
        case let .failed(filename, message):
            ContentUnavailableView(
                "Unable to Open \(filename)",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        }
    }

    @ViewBuilder
    private var retainedImageStatus: some View {
        switch model.loadState {
        case let .loading(filename):
            statusPill {
                ProgressView()
                    .controlSize(.small)
                Text("Loading \(filename)…")
            }
            .accessibilityLabel("Loading \(filename)")
        case let .failed(filename, message):
            statusPill {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("\(filename): \(message)")
            }
            .accessibilityLabel("Unable to open \(filename). \(message)")
        case .empty, .ready:
            EmptyView()
        }
    }

    private func statusPill<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8, content: content)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 4, y: 2)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 16)
    }

    private var navigationBar: some View {
        HStack {
            Button {
                model.navigatePrevious()
            } label: {
                Label("Previous Image", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
            }
            .disabled(!model.canNavigatePrevious)
            .help("Previous Image (Left Arrow)")

            Spacer()

            if let position = model.navigationPosition {
                Text(position)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Image \(position)")
            } else {
                Text("Single Image")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.navigateNext()
            } label: {
                Label("Next Image", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
            }
            .disabled(!model.canNavigateNext)
            .help("Next Image (Right Arrow)")
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(.bar)
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

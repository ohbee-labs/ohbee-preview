import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Binding var thumbnailSidebarVisible: Bool
    @StateObject private var animation = AnimatedImageController()

    var body: some View {
        VStack(spacing: 0) {
            if model.showsFolderAccessAction {
                folderAccessBanner
            }

            if thumbnailSidebarVisible {
                HSplitView {
                    ThumbnailSidebar(
                        entries: model.thumbnailEntries,
                        selectedURL: model.selectedThumbnailURL,
                        folderGeneration: model.folderGeneration,
                        onSelect: model.selectThumbnail
                    )
                    viewerDetail
                }
            } else {
                viewerDetail
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 640, minHeight: 480)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            animation.setActive(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            animation.setActive(true)
        }
        .onDisappear {
            animation.stop(reason: "view-disappeared")
        }
    }

    private var viewerDetail: some View {
        VStack(spacing: 0) {
            viewer
            if model.hasImageSession {
                inspectionBar
                navigationBar
            }
        }
    }

    @ViewBuilder
    private var viewer: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            if let displayed = model.displayedImage {
                ImageInspectionView(
                    image: animation.presentedImage ?? displayed.image,
                    filename: displayed.filename,
                    generation: displayed.generation,
                    contentRevision: animation.presentationRevision,
                    state: model.viewportState,
                    onEffectiveScaleChanged: model.viewportEffectiveScaleChanged,
                    onPinchScaleChanged: model.viewportPinchScaleChanged,
                    onPrevious: model.navigatePrevious,
                    onNext: model.navigateNext,
                    onCommit: {
                        model.imageDidCommitToView(
                            generation: displayed.generation
                        )
                    },
                    onFitCalculated: model.viewportFitCalculated,
                    onInvalidTransform: model.viewportRejectedInvalidTransform
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task(id: displayed.generation) {
                    animation.select(
                        url: displayed.sourceURL,
                        generation: displayed.generation
                    )
                }
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

    private var inspectionBar: some View {
        HStack(spacing: 14) {
            Button {
                model.rotateLeft()
            } label: {
                Label("Rotate Left", systemImage: "rotate.left")
                    .labelStyle(.iconOnly)
            }
            .help("Rotate Left (Command-L)")

            Button {
                model.fitToWindow()
            } label: {
                Label(
                    "Fit to Window",
                    systemImage: "arrow.down.right.and.arrow.up.left"
                )
                .labelStyle(.iconOnly)
            }
            .help("Fit to Window (Command-9)")

            Button("1:1") {
                model.showActualSize()
            }
            .help("Actual Size (Command-0)")
            .accessibilityLabel("Actual Size")

            Button {
                model.zoomOut()
            } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            .help("Zoom Out (Command-Minus)")

            Text(model.zoomPercentage)
                .font(.callout.monospacedDigit())
                .frame(minWidth: 52)
                .accessibilityLabel("Zoom \(model.zoomPercentage)")

            Button {
                model.zoomIn()
            } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            .help("Zoom In (Command-Equals)")

            Button {
                model.rotateRight()
            } label: {
                Label("Rotate Right", systemImage: "rotate.right")
                    .labelStyle(.iconOnly)
            }
            .help("Rotate Right (Command-R)")

            Spacer()

            Button {
                model.toggleFullScreen()
            } label: {
                Label(
                    "Toggle Full Screen",
                    systemImage: "arrow.up.left.and.arrow.down.right"
                )
                .labelStyle(.iconOnly)
            }
            .help("Toggle Full Screen (Control-Command-F)")
        }
        .buttonStyle(.borderless)
        .disabled(!model.canInspectImage)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(.bar)
    }

    private var folderAccessBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
            Text(model.folderAccessMessage)
            Spacer()
            Button("Allow Access") {
                model.allowFolderAccess()
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(.bar)
    }
}

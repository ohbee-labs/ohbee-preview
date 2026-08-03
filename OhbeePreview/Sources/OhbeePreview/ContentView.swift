import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Binding var thumbnailSidebarVisible: Bool
    @StateObject private var animation = AnimatedImageController()
    @State private var accessibility = AccessibilityCoordinator()
    @FocusState private var focusedArea: ViewerFocusTarget?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        eviction: model.thumbnailEviction,
                        onSelect: model.selectThumbnail,
                        focus: $focusedArea,
                        reduceMotion: reduceMotion
                    )
                    viewerDetail
                }
            } else {
                viewerDetail
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 640, minHeight: 480)
        .onAppear { focusedArea = .viewport }
        .onChange(of: thumbnailSidebarVisible) { _, isVisible in
            focusedArea = isVisible ? .thumbnails : .viewport
            Diagnostics.recordAccessibilityFocusChange(
                destination: isVisible ? "thumbnails" : "viewport"
            )
        }
        .onChange(of: model.displayedImage?.generation) { _, generation in
            guard generation != nil, let filename = model.displayedImage?.filename else { return }
            focusedArea = .viewport
            let position = model.navigationPosition.map { ", \($0)" } ?? ""
            accessibility.announce("\(filename)\(position)")
        }
        .onChange(of: model.authorization) { oldValue, newValue in
            guard oldValue != newValue else { return }
            if case .authorizedForSession = newValue {
                accessibility.announce("Folder navigation is available")
            }
        }
        .onChange(of: model.finderActionError) { _, error in
            guard let error else {
                if focusedArea == .error { focusedArea = .viewport }
                return
            }
            focusedArea = .error
            accessibility.announce(error, priority: .high)
        }
        .onChange(of: model.trashActionTarget) { oldTarget, newTarget in
            guard oldTarget != nil, newTarget == nil, model.finderActionError == nil else { return }
            focusedArea = model.displayedImage == nil ? .emptyState : .viewport
        }
        .onChange(of: model.loadState.accessibilityStateKey) { _, state in
            if state == "empty-folder" {
                focusedArea = .emptyState
                accessibility.announce("No images remain", priority: .high)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            animation.setActive(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            animation.setActive(true)
        }
        .onDisappear {
            animation.stop(reason: "view-disappeared")
            model.viewerDidClose()
        }
        .onChange(of: model.trashActionTarget) { _, target in
            animation.setFileActionSuspended(target != nil)
        }
        .alert(
            "File Action Failed",
            isPresented: Binding(
                get: { model.finderActionError != nil },
                set: { if !$0 { model.dismissFinderActionError() } }
            )
        ) {
            Button("OK") {
                model.dismissFinderActionError()
                focusedArea = .viewport
            }
        } message: {
            Text(model.finderActionError ?? "The file action failed.")
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
                .focusable()
                .focusEffectDisabled()
                .focused($focusedArea, equals: .viewport)
                .accessibilityIdentifier(AccessibilityID.viewport)
                .accessibilityLabel(displayed.filename)
                .accessibilityValue(model.navigationPosition ?? "Single image")
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
            .accessibilityIdentifier("state.open-image")
        case .emptyFolder:
            ContentUnavailableView(
                "No Images Remain",
                systemImage: "photo.on.rectangle.angled",
                description: Text("Open another image to continue browsing.")
            )
            .focusable()
            .focused($focusedArea, equals: .emptyState)
            .accessibilityIdentifier(AccessibilityID.emptyFolder)
        case let .loading(filename):
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading \(filename)…")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading \(filename)")
        case .ready:
            EmptyView()
        case let .failed(filename, message):
            ContentUnavailableView(
                "Unable to Open \(filename)",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
            .accessibilityIdentifier(AccessibilityID.error)
            .accessibilityLabel("Unable to open \(filename). \(message)")
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
            .accessibilityIdentifier(AccessibilityID.error)
        case .empty, .emptyFolder, .ready:
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
            .accessibilityIdentifier(AccessibilityID.previous)

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
                thumbnailSidebarVisible.toggle()
            } label: {
                Label(
                    thumbnailSidebarVisible ? "Hide Thumbnails" : "Show Thumbnails",
                    systemImage: "sidebar.left"
                )
                .labelStyle(.iconOnly)
            }
            .help(thumbnailSidebarVisible ? "Hide Thumbnails" : "Show Thumbnails")
            .accessibilityIdentifier(AccessibilityID.sidebarToggle)

            Button {
                model.navigateNext()
            } label: {
                Label("Next Image", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
            }
            .disabled(!model.canNavigateNext)
            .help("Next Image (Right Arrow)")
            .accessibilityIdentifier(AccessibilityID.next)
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
            .accessibilityIdentifier(AccessibilityID.rotateLeft)

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
            .accessibilityIdentifier(AccessibilityID.fit)

            Button("1:1") {
                model.showActualSize()
            }
            .help("Actual Size (Command-0)")
            .accessibilityLabel("Actual Size")
            .accessibilityIdentifier(AccessibilityID.actualSize)

            Button {
                model.zoomOut()
            } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            .help("Zoom Out (Command-Minus)")
            .accessibilityIdentifier(AccessibilityID.zoomOut)

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
            .accessibilityIdentifier(AccessibilityID.zoomIn)

            Button {
                model.rotateRight()
            } label: {
                Label("Rotate Right", systemImage: "rotate.right")
                    .labelStyle(.iconOnly)
            }
            .help("Rotate Right (Command-R)")
            .accessibilityIdentifier(AccessibilityID.rotateRight)

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
            .accessibilityIdentifier("command.fullscreen")
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
            Button("Not Now") {
                model.dismissFolderAccessPrompt()
                focusedArea = .viewport
            }
            .buttonStyle(.borderless)
            Button("Allow Access") {
                model.allowFolderAccess()
            }
            .buttonStyle(.bordered)
            .focused($focusedArea, equals: .folderAccess)
            .accessibilityIdentifier(AccessibilityID.folderAccess)
        }
        .padding(10)
        .background(.bar)
    }
}

private extension AppModel.LoadState {
    var accessibilityStateKey: String {
        switch self {
        case .empty: "empty"
        case .emptyFolder: "empty-folder"
        case .loading: "loading"
        case .ready: "ready"
        case .failed: "failed"
        }
    }
}

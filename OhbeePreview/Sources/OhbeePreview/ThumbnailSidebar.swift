import AppKit
import OhbeeStage2Core
import SwiftUI

@MainActor
final class ThumbnailSidebarModel: ObservableObject {
    let controller: ThumbnailController
    @Published private(set) var session: UInt64 = 0

    private var sessionTask: Task<Void, Never>?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var visibleIndices: Set<Int> = []
    private var prefetchTasks: [ThumbnailRequestKey: Task<Void, Never>] = [:]

    init(controller: ThumbnailController = ThumbnailController()) {
        self.controller = controller
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.controller.handleMemoryPressure() }
        }
        source.resume()
        memoryPressureSource = source
    }

    func beginFolderSession() {
        sessionTask?.cancel()
        cancelPrefetch()
        visibleIndices.removeAll()
        session = 0
        sessionTask = Task { [weak self] in
            guard let self else { return }
            let newSession = await controller.beginFolderSession()
            guard !Task.isCancelled else { return }
            session = newSession
        }
    }

    func stop() {
        sessionTask?.cancel()
        sessionTask = nil
        cancelPrefetch()
        visibleIndices.removeAll()
        session = 0
        Task { await controller.cancelAll() }
    }

    func evict(url: URL) {
        let normalized = url.standardizedFileURL
        for key in Array(prefetchTasks.keys) where key.url == normalized {
            prefetchTasks.removeValue(forKey: key)?.cancel()
        }
        Task { await controller.evict(url: normalized) }
    }

    func rowVisibilityChanged(
        index: Int,
        visible: Bool,
        entries: [NavigationEntry],
        maximumPixelSize: Int
    ) {
        if visible {
            visibleIndices.insert(index)
        } else {
            visibleIndices.remove(index)
        }
        reconcilePrefetch(
            entries: entries,
            maximumPixelSize: maximumPixelSize
        )
    }

    private func reconcilePrefetch(
        entries: [NavigationEntry],
        maximumPixelSize: Int
    ) {
        guard session != 0 else { return }
        let nearbyIndices = Set(visibleIndices.flatMap { index in
            [index - 2, index - 1, index + 1, index + 2]
        }.filter(entries.indices.contains))
        let desired = Set(nearbyIndices.map { index in
            ThumbnailRequestKey(
                url: entries[index].url,
                maximumPixelSize: maximumPixelSize
            )
        })
        let visibleKeys = Set(visibleIndices.compactMap { index -> ThumbnailRequestKey? in
            guard entries.indices.contains(index) else { return nil }
            return ThumbnailRequestKey(
                url: entries[index].url,
                maximumPixelSize: maximumPixelSize
            )
        })

        for key in Array(prefetchTasks.keys) where !desired.contains(key) {
            guard !visibleKeys.contains(key) else { continue }
            let operation = prefetchTasks.removeValue(forKey: key)
            operation?.cancel()
            Task { await controller.cancel(key) }
        }

        for key in desired where prefetchTasks[key] == nil {
            let requestedSession = session
            let task = Task { [controller] in
                _ = try? await controller.thumbnail(
                    for: key,
                    priority: .nearby,
                    session: requestedSession
                )
            }
            prefetchTasks[key] = task
        }
    }

    private func cancelPrefetch() {
        for operation in prefetchTasks.values {
            operation.cancel()
        }
        prefetchTasks.removeAll()
    }
}

@MainActor
final class ThumbnailViewModel: ObservableObject {
    enum State {
        case placeholder
        case ready(CGImage)
        case failed
    }

    @Published private(set) var state: State = .placeholder

    private let controller: ThumbnailController
    private let key: ThumbnailRequestKey
    private let session: UInt64
    private var task: Task<Void, Never>?
    private var loadGeneration: UInt64 = 0

    init(
        controller: ThumbnailController,
        key: ThumbnailRequestKey,
        session: UInt64
    ) {
        self.controller = controller
        self.key = key
        self.session = session
    }

    func load(priority: ThumbnailRequestPriority = .visible) {
        guard task == nil, session != 0 else { return }
        loadGeneration &+= 1
        let generation = loadGeneration
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let payload = try await controller.thumbnail(
                    for: key,
                    priority: priority,
                    session: session
                )
                try Task.checkCancellation()
                guard generation == loadGeneration else { return }
                state = .ready(payload.image)
            } catch is CancellationError {
                return
            } catch {
                guard generation == loadGeneration else { return }
                state = .failed
            }
            if generation == loadGeneration {
                task = nil
            }
        }
    }

    func cancel() {
        loadGeneration &+= 1
        task?.cancel()
        task = nil
        // Lazy stacks may retain off-screen row state. Release the row-owned
        // CGImage so the controller cache remains the only bounded thumbnail
        // retention policy.
        state = .placeholder
        Task { await controller.cancel(key) }
    }
}

struct ThumbnailSidebar: View {
    let entries: [NavigationEntry]
    let selectedURL: URL?
    let folderGeneration: UInt64
    let eviction: ThumbnailEvictionRequest?
    let onSelect: (NavigationEntry) -> Void
    let focus: FocusState<ViewerFocusTarget?>.Binding
    let reduceMotion: Bool

    @StateObject private var model = ThumbnailSidebarModel()

    private let logicalThumbnailSize: CGFloat = 112

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if model.session == 0 {
                    ProgressView()
                        .controlSize(.small)
                        .padding()
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(entries.indices, id: \.self) { index in
                            let entry = entries[index]
                            ThumbnailRow(
                                entry: entry,
                                ordinal: index + 1,
                                total: entries.count,
                                selected: entry.url == selectedURL,
                                controller: model.controller,
                                session: model.session,
                                maximumPixelSize: maximumPixelSize,
                                onSelect: { onSelect(entry) },
                                onVisibilityChange: { visible in
                                    model.rowVisibilityChanged(
                                        index: index,
                                        visible: visible,
                                        entries: entries,
                                        maximumPixelSize: maximumPixelSize
                                    )
                                }
                            )
                            .id(entry.url)
                        }
                    }
                    .padding(8)
                }
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            .overlay {
                if focus.wrappedValue == .thumbnails {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: 1.5)
                        .padding(2)
                        .allowsHitTesting(false)
                }
            }
            .focusable()
            .focused(focus, equals: .thumbnails)
            .onMoveCommand(perform: moveSelection)
            .onChange(of: selectedURL) { _, newValue in
                guard let newValue else { return }
                scrollToSelection(newValue, proxy: proxy)
            }
            .onChange(of: model.session) { _, newSession in
                guard newSession != 0, let selectedURL else { return }
                proxy.scrollTo(selectedURL, anchor: .center)
            }
            .onAppear {
                model.beginFolderSession()
                if let selectedURL {
                    proxy.scrollTo(selectedURL, anchor: .center)
                }
            }
            .onChange(of: folderGeneration) { _, _ in
                model.beginFolderSession()
            }
            .onChange(of: eviction) { _, request in
                guard let request else { return }
                model.evict(url: request.url)
            }
            .onDisappear {
                model.stop()
            }
        }
        .frame(minWidth: 170, idealWidth: 220, maxWidth: 380)
        .accessibilityLabel("Thumbnails")
        .accessibilityIdentifier(AccessibilityID.thumbnailSidebar)
    }

    private var maximumPixelSize: Int {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return Int((logicalThumbnailSize * scale).rounded(.up))
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard
            !entries.isEmpty,
            let selectedURL,
            let index = entries.firstIndex(where: { $0.url == selectedURL })
        else { return }

        let target: Int
        switch direction {
        case .up:
            target = max(entries.startIndex, index - 1)
        case .down:
            target = min(entries.index(before: entries.endIndex), index + 1)
        default:
            return
        }
        guard target != index else { return }
        onSelect(entries[target])
    }

    private func scrollToSelection(
        _ url: URL,
        proxy: ScrollViewProxy
    ) {
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(url, anchor: .center)
            }
            Diagnostics.recordReducedMotionBranch()
        } else {
            proxy.scrollTo(url, anchor: .center)
        }
    }

}

private struct ThumbnailRow: View {
    let entry: NavigationEntry
    let ordinal: Int
    let total: Int
    let selected: Bool
    let onSelect: () -> Void
    let onVisibilityChange: (Bool) -> Void

    @StateObject private var model: ThumbnailViewModel

    init(
        entry: NavigationEntry,
        ordinal: Int,
        total: Int,
        selected: Bool,
        controller: ThumbnailController,
        session: UInt64,
        maximumPixelSize: Int,
        onSelect: @escaping () -> Void,
        onVisibilityChange: @escaping (Bool) -> Void
    ) {
        self.entry = entry
        self.ordinal = ordinal
        self.total = total
        self.selected = selected
        self.onSelect = onSelect
        self.onVisibilityChange = onVisibilityChange
        _model = StateObject(
            wrappedValue: ThumbnailViewModel(
                controller: controller,
                key: ThumbnailRequestKey(
                    url: entry.url,
                    maximumPixelSize: maximumPixelSize
                ),
                session: session
            )
        )
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                preview
                    .frame(width: 76, height: 60)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                Text(entry.filename)
                    .font(.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(6)
            .contentShape(Rectangle())
            .background(
                selected ? Color.accentColor.opacity(0.22) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.accentColor, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.filename)
        .accessibilityValue("\(ordinal) of \(total)\(selected ? ", selected" : "")")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(
            AccessibilityID.thumbnail(identity: entry.fileIdentity, ordinal: ordinal)
        )
        .onAppear {
            model.load()
            onVisibilityChange(true)
        }
        .onDisappear {
            model.cancel()
            onVisibilityChange(false)
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch model.state {
        case .placeholder:
            ProgressView()
                .controlSize(.small)
        case let .ready(image):
            Image(image, scale: 1, label: Text(entry.filename))
                .resizable()
                .scaledToFit()
        case .failed:
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Thumbnail unavailable")
        }
    }
}

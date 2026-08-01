import AppKit
import Foundation

@MainActor
final class AnimatedImageController: ObservableObject {
    enum PlaybackState: Equatable {
        case idle
        case classifying
        case playing
        case paused
        case completed
        case failed
    }

    @Published private(set) var presentedImage: NSImage?
    @Published private(set) var presentationRevision: UInt64 = 0
    @Published private(set) var playbackState: PlaybackState = .idle
    private(set) var presentedFrameIndex: Int?

    private let loader: any AnimatedImageLoading
    private let scheduler: AnimatedFrameScheduler
    private let store: AnimatedFrameStore
    private var playbackTask: Task<Void, Never>?
    private var sessionID = UUID()
    private var currentURL: URL?
    private var currentGeneration: UInt64?
    private var currentFrameIndex: Int?
    private var isActive = true
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    init(
        loader: any AnimatedImageLoading = ImageIOAnimatedImageLoader(),
        byteLimit: Int = 64 * 1_024 * 1_024,
        frameLimit: Int = 8
    ) {
        self.loader = loader
        scheduler = AnimatedFrameScheduler(loader: loader)
        store = AnimatedFrameStore(byteLimit: byteLimit, frameLimit: frameLimit)
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.handleMemoryPressure() }
        }
        source.resume()
        memoryPressureSource = source
    }

    func select(url: URL, generation: UInt64) {
        stop(reason: "selection")
        sessionID = UUID()
        currentURL = url.standardizedFileURL
        currentGeneration = generation
        playbackState = .classifying
        let identity = sessionID
        playbackTask = Task { [weak self] in
            await self?.classifyAndPlay(
                url: url.standardizedFileURL,
                generation: generation,
                identity: identity
            )
        }
    }

    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        if active {
            guard let url = currentURL, let generation = currentGeneration else { return }
            select(url: url, generation: generation)
            Diagnostics.recordGIFResume()
        } else {
            playbackTask?.cancel()
            let identity = sessionID
            Task { await scheduler.cancel(sessionID: identity) }
            if playbackState == .playing { playbackState = .paused }
            Diagnostics.recordGIFPause()
        }
    }

    func stop(reason: StaticString = "lifecycle") {
        let identity = sessionID
        playbackTask?.cancel()
        playbackTask = nil
        sessionID = UUID()
        Task { await scheduler.cancel(sessionID: identity) }
        Task { await store.remove(sessionID: identity) }
        presentedImage = nil
        presentedFrameIndex = nil
        currentFrameIndex = nil
        if playbackState != .idle { Diagnostics.recordGIFStop(reason: reason) }
        playbackState = .idle
    }

    func handleMemoryPressure() {
        let retained = currentFrameIndex.map {
            AnimatedFrameStore.Key(sessionID: sessionID, frameIndex: $0)
        }
        Task { [store] in
            await store.purge(keeping: retained)
            await Diagnostics.recordGIFMemoryPurge(store: store)
        }
    }

    private func classifyAndPlay(
        url: URL,
        generation: UInt64,
        identity: UUID
    ) async {
        let started = ContinuousClock.now
        do {
            let kind = try await loader.classify(url: url)
            guard isCurrent(url: url, generation: generation, identity: identity) else {
                Diagnostics.recordGIFStaleFrame()
                return
            }
            Diagnostics.recordGIFClassification(
                kind: kind,
                duration: started.duration(to: .now)
            )
            guard case let .animated(descriptor) = kind else {
                playbackState = .idle
                return
            }
            guard isActive else {
                playbackState = .paused
                return
            }
            Diagnostics.recordGIFPlaybackStart(descriptor: descriptor)
            playbackState = .playing
            await play(
                url: url,
                generation: generation,
                identity: identity,
                descriptor: descriptor
            )
        } catch is CancellationError {
            Diagnostics.recordGIFDecodeCancellation()
        } catch {
            guard isCurrent(url: url, generation: generation, identity: identity) else {
                Diagnostics.recordGIFStaleFrame()
                return
            }
            playbackState = .failed
            Diagnostics.recordGIFFailure(error)
        }
    }

    private func play(
        url: URL,
        generation: UInt64,
        identity: UUID,
        descriptor: AnimatedImageDescriptor
    ) async {
        let clock = ContinuousClock()
        var frameIndex = 0
        var completedLoops = 0
        var deadline = clock.now
        let playbackStarted = deadline
        var didRecordFirstFrame = false

        while isCurrent(url: url, generation: generation, identity: identity), isActive {
            do {
                let decodeStarted = clock.now
                let frame: AnimatedFrame
                let storeKey = AnimatedFrameStore.Key(
                    sessionID: identity,
                    frameIndex: frameIndex
                )
                if let cached = await store.frame(for: storeKey) {
                    frame = cached
                    await Diagnostics.recordGIFFrameCache(hit: true, store: store)
                } else {
                    await Diagnostics.recordGIFFrameCache(hit: false, store: store)
                    frame = try await scheduler.frame(
                        sessionID: identity,
                        url: url,
                        descriptor: descriptor,
                        index: frameIndex
                    )
                    await store.insert(frame, for: storeKey)
                    Diagnostics.recordGIFFrameDecode(
                        duration: decodeStarted.duration(to: clock.now)
                    )
                }
                guard isCurrent(url: url, generation: generation, identity: identity) else {
                    Diagnostics.recordGIFStaleFrame()
                    return
                }
                presentedImage = frame.image
                presentedFrameIndex = frame.index
                currentFrameIndex = frame.index
                presentationRevision &+= 1
                Diagnostics.recordGIFFrameDisplayed(lateness: deadline.duration(to: clock.now))
                if !didRecordFirstFrame {
                    didRecordFirstFrame = true
                    Diagnostics.recordGIFFirstFrameDisplay(
                        duration: playbackStarted.duration(to: clock.now)
                    )
                }

                let delay = descriptor.frameDelays[frameIndex]
                deadline += .seconds(delay)
                frameIndex += 1
                if frameIndex == descriptor.frameCount {
                    frameIndex = 0
                    completedLoops += 1
                    Diagnostics.recordGIFLoopCompletion()
                    if let loopCount = descriptor.loopCount,
                       loopCount > 0,
                       completedLoops > loopCount {
                        playbackState = .completed
                        return
                    }
                }

                var skipped = 0
                while clock.now > deadline, skipped < descriptor.frameCount - 1 {
                    deadline += .seconds(descriptor.frameDelays[frameIndex])
                    frameIndex = (frameIndex + 1) % descriptor.frameCount
                    skipped += 1
                    if frameIndex == 0 {
                        completedLoops += 1
                        Diagnostics.recordGIFLoopCompletion()
                        if let loopCount = descriptor.loopCount,
                           loopCount > 0,
                           completedLoops > loopCount {
                            playbackState = .completed
                            return
                        }
                    }
                }
                if skipped > 0 { Diagnostics.recordGIFFramesSkipped(skipped) }
                try await clock.sleep(until: deadline, tolerance: .milliseconds(2))
            } catch is CancellationError {
                Diagnostics.recordGIFDecodeCancellation()
                return
            } catch {
                guard isCurrent(url: url, generation: generation, identity: identity) else {
                    Diagnostics.recordGIFStaleFrame()
                    return
                }
                Diagnostics.recordGIFFailure(error)
                // Preserve the last valid frame and keep navigation available.
                playbackState = .failed
                return
            }
        }
    }

    private func isCurrent(url: URL, generation: UInt64, identity: UUID) -> Bool {
        !Task.isCancelled
            && sessionID == identity
            && currentURL == url
            && currentGeneration == generation
    }
}

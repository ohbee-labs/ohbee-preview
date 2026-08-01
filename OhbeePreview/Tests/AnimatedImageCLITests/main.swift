import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum TestFailure: Error {
    case failed(String)
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure.failed(message) }
}

func makeImage(width: Int = 8, height: Int = 8) -> NSImage {
    NSImage(size: NSSize(width: width, height: height))
}

func makeFrame(index: Int, cost: Int = 256) -> AnimatedFrame {
    AnimatedFrame(image: makeImage(), index: index, decodedByteCost: cost)
}

actor FakeAnimatedLoader: AnimatedImageLoading {
    var kinds: [URL: AnimatedImageKind]
    var decodeCount = 0
    var delay: Duration
    var failingFrames: Set<Int>

    init(
        kinds: [URL: AnimatedImageKind],
        delay: Duration = .zero,
        failingFrames: Set<Int> = []
    ) {
        self.kinds = kinds
        self.delay = delay
        self.failingFrames = failingFrames
    }

    func classify(url: URL) async throws -> AnimatedImageKind {
        kinds[url] ?? .notGIF
    }

    func decodeFrame(
        url: URL,
        descriptor: AnimatedImageDescriptor,
        index: Int
    ) async throws -> AnimatedFrame {
        decodeCount += 1
        if delay > .zero { try await ContinuousClock().sleep(for: delay) }
        try Task.checkCancellation()
        if failingFrames.contains(index) { throw AnimatedImageError.frameDecodeFailed }
        return makeFrame(index: index)
    }

    func decoded() -> Int { decodeCount }
}

func descriptor(
    count: Int = 3,
    delay: Double = 0.03,
    loopCount: Int? = nil
) -> AnimatedImageDescriptor {
    AnimatedImageDescriptor(
        frameCount: count,
        pixelWidth: 8,
        pixelHeight: 8,
        frameDelays: Array(repeating: delay, count: count),
        loopCount: loopCount,
        invalidTimingCount: 0
    )
}

@MainActor
func waitUntil(
    timeout: Duration = .seconds(2),
    _ predicate: @escaping @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !predicate() {
        guard clock.now < deadline else { throw TestFailure.failed("Timed out") }
        await Task.yield()
    }
}

func writeGIF(
    at url: URL,
    frames: Int,
    delays: [Double],
    loopCount: Int? = nil
) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.gif.identifier as CFString,
        frames,
        nil
    ) else { throw TestFailure.failed("GIF destination unavailable") }
    if let loopCount {
        CGImageDestinationSetProperties(
            destination,
            [kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: loopCount
            ]] as CFDictionary
        )
    }
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    for index in 0..<frames {
        let bytes = [UInt8](repeating: UInt8(30 + index * 40), count: 8 * 8 * 4)
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 32,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        let properties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delays[index]
            ]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    }
    guard CGImageDestinationFinalize(destination) else {
        throw TestFailure.failed("GIF finalization failed")
    }
}

@main
struct AnimatedImageTests {
    static func main() async throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let loader = ImageIOAnimatedImageLoader()
        let staticURL = temporary.appendingPathComponent("still.png")
        try Data([0]).write(to: staticURL)
        let staticKind = try await loader.classify(url: staticURL)
        try expect(staticKind == .notGIF, "Static classification")

        let singleURL = temporary.appendingPathComponent("single.gif")
        try writeGIF(at: singleURL, frames: 1, delays: [0.1])
        let singleKind = try await loader.classify(url: singleURL)
        try expect(singleKind == .singleFrameGIF, "Single-frame GIF")

        let animatedURL = temporary.appendingPathComponent("animated.gif")
        try writeGIF(at: animatedURL, frames: 3, delays: [0.04, 0.05, 0.06], loopCount: 2)
        let measurementClock = ContinuousClock()
        let classificationStarted = measurementClock.now
        guard case let .animated(metadata) = try await loader.classify(url: animatedURL) else {
            throw TestFailure.failed("Animated classification")
        }
        let classificationDuration = classificationStarted.duration(to: measurementClock.now)
        try expect(metadata.frameCount == 3, "Frame count")
        try expect(metadata.frameDelays.allSatisfy { $0 >= 0.02 }, "Valid delays")
        try expect(metadata.loopCount == 2, "Loop count")
        let frameDecodeStarted = measurementClock.now
        let decoded = try await loader.decodeFrame(url: animatedURL, descriptor: metadata, index: 1)
        let frameDecodeDuration = frameDecodeStarted.duration(to: measurementClock.now)
        try expect(decoded.index == 1 && decoded.decodedByteCost > 0, "Frame decode")

        let shortURL = temporary.appendingPathComponent("short.gif")
        try writeGIF(at: shortURL, frames: 2, delays: [0.001, 0])
        guard case let .animated(shortMetadata) = try await loader.classify(url: shortURL) else {
            throw TestFailure.failed("Short-delay classification")
        }
        try expect(shortMetadata.frameDelays.allSatisfy { $0 >= 0.02 }, "Delay clamp")
        try expect(shortMetadata.invalidTimingCount > 0, "Invalid timing count")

        let excessiveDescriptor = AnimatedImageDescriptor(
            frameCount: 2,
            pixelWidth: 16_384,
            pixelHeight: 16_384,
            frameDelays: [0.1, 0.1],
            loopCount: nil,
            invalidTimingCount: 0
        )
        do {
            _ = try await loader.decodeFrame(
                url: animatedURL,
                descriptor: excessiveDescriptor,
                index: 0
            )
            throw TestFailure.failed("Excessive frame accepted")
        } catch AnimatedImageError.excessiveFrameCost {}

        let corruptURL = temporary.appendingPathComponent("corrupt.gif")
        try Data("GIF89a broken".utf8).write(to: corruptURL)
        do {
            _ = try await loader.classify(url: corruptURL)
            throw TestFailure.failed("Corrupt GIF accepted")
        } catch is AnimatedImageError {}

        let store = AnimatedFrameStore(byteLimit: 600, frameLimit: 2)
        let storeSession = UUID()
        let key0 = AnimatedFrameStore.Key(sessionID: storeSession, frameIndex: 0)
        let key1 = AnimatedFrameStore.Key(sessionID: storeSession, frameIndex: 1)
        let key2 = AnimatedFrameStore.Key(sessionID: storeSession, frameIndex: 2)
        await store.insert(makeFrame(index: 0), for: key0)
        await store.insert(makeFrame(index: 1), for: key1)
        _ = await store.frame(for: key0)
        await store.insert(makeFrame(index: 2), for: key2)
        let evictedFrame = await store.frame(for: key1)
        try expect(evictedFrame == nil, "LRU eviction")
        var snapshot = await store.snapshot()
        try expect(snapshot.count == 2 && snapshot.cost <= 600, "Bounded frame cost")
        await store.purge(keeping: key0)
        snapshot = await store.snapshot()
        try expect(snapshot.count == 1 && snapshot.purges == 1, "Memory pressure purge")
        let otherSessionKey = AnimatedFrameStore.Key(
            sessionID: UUID(),
            frameIndex: 0
        )
        let crossSessionFrame = await store.frame(for: otherSessionKey)
        try expect(crossSessionFrame == nil, "Frame-store session isolation")

        let schedulerLoader = FakeAnimatedLoader(kinds: [:], delay: .milliseconds(20))
        let scheduler = AnimatedFrameScheduler(loader: schedulerLoader)
        let schedulerSession = UUID()
        async let first = scheduler.frame(sessionID: schedulerSession, url: animatedURL, descriptor: metadata, index: 0)
        async let duplicate = scheduler.frame(sessionID: schedulerSession, url: animatedURL, descriptor: metadata, index: 0)
        _ = try await (first, duplicate)
        let schedulerDecodeCount = await schedulerLoader.decoded()
        try expect(schedulerDecodeCount == 1, "Duplicate decode suppression")
        let schedulerSnapshot = await scheduler.snapshot()
        try expect(
            schedulerSnapshot.duplicates == 1 && schedulerSnapshot.peak == 1,
            "Duplicate metric and bounded decode concurrency"
        )
        async let firstURLFrame = scheduler.frame(
            sessionID: schedulerSession,
            url: animatedURL,
            descriptor: metadata,
            index: 1
        )
        async let secondURLFrame = scheduler.frame(
            sessionID: schedulerSession,
            url: shortURL,
            descriptor: shortMetadata,
            index: 1
        )
        _ = try await (firstURLFrame, secondURLFrame)
        let crossURLDecodeCount = await schedulerLoader.decoded()
        try expect(crossURLDecodeCount == 3, "Scheduler URL identity")
        async let firstSessionFrame = scheduler.frame(
            sessionID: UUID(),
            url: animatedURL,
            descriptor: metadata,
            index: 2
        )
        async let secondSessionFrame = scheduler.frame(
            sessionID: UUID(),
            url: animatedURL,
            descriptor: metadata,
            index: 2
        )
        _ = try await (firstSessionFrame, secondSessionFrame)
        let crossSessionDecodeCount = await schedulerLoader.decoded()
        try expect(crossSessionDecodeCount == 5, "Scheduler session identity")

        let cancellationLoader = FakeAnimatedLoader(kinds: [:], delay: .seconds(1))
        let cancellationScheduler = AnimatedFrameScheduler(loader: cancellationLoader)
        let cancellationSession = UUID()
        let activeCancellation = Task {
            try await cancellationScheduler.frame(
                sessionID: cancellationSession,
                url: animatedURL,
                descriptor: metadata,
                index: 0
            )
        }
        let queuedCancellation = Task {
            try await cancellationScheduler.frame(
                sessionID: cancellationSession,
                url: animatedURL,
                descriptor: metadata,
                index: 1
            )
        }
        while await cancellationScheduler.snapshot().waiting == 0 { await Task.yield() }
        await cancellationScheduler.cancel(sessionID: cancellationSession)
        activeCancellation.cancel()
        queuedCancellation.cancel()
        _ = try? await activeCancellation.value
        _ = try? await queuedCancellation.value
        let cancellationSnapshot = await cancellationScheduler.snapshot()
        try expect(
            cancellationSnapshot.inFlight == 0
                && cancellationSnapshot.waiting == 0
                && cancellationSnapshot.cancellations == 2,
            "Active and queued playback cancellation"
        )

        let infiniteURL = temporary.appendingPathComponent("infinite.gif")
        let finiteURL = temporary.appendingPathComponent("finite.gif")
        let stillURL = temporary.appendingPathComponent("next.png")
        let fake = FakeAnimatedLoader(kinds: [
            infiniteURL: .animated(descriptor(count: 2, loopCount: nil)),
            finiteURL: .animated(descriptor(count: 2, loopCount: 1)),
            stillURL: .notGIF
        ])
        let controller = await MainActor.run { AnimatedImageController(loader: fake) }
        await MainActor.run { controller.select(url: infiniteURL, generation: 1) }
        try await waitUntil { controller.presentationRevision >= 2 }
        let playing = await MainActor.run { controller.playbackState == .playing }
        try expect(playing, "Infinite playback")
        await MainActor.run { controller.setActive(false) }
        let paused = await MainActor.run { controller.playbackState == .paused }
        try expect(paused, "Pause")
        let pausedRevision = await MainActor.run { controller.presentationRevision }
        await Task.yield()
        let remainedPaused = await MainActor.run {
            controller.presentationRevision == pausedRevision
        }
        try expect(remainedPaused, "Paused advancement")
        await MainActor.run { controller.setActive(true) }
        try await waitUntil { controller.presentationRevision > pausedRevision }

        await MainActor.run { controller.select(url: finiteURL, generation: 2) }
        try await waitUntil { controller.playbackState == .completed }
        let stoppedOnLastFrame = await MainActor.run {
            controller.presentedFrameIndex == 1
        }
        try expect(stoppedOnLastFrame, "Finite-loop completion")

        await MainActor.run { controller.select(url: infiniteURL, generation: 3) }
        try await waitUntil { controller.playbackState == .playing }
        await MainActor.run { controller.select(url: stillURL, generation: 4) }
        try await waitUntil { controller.playbackState == .idle }
        let clearedAfterNavigation = await MainActor.run {
            controller.presentedImage == nil
        }
        try expect(clearedAfterNavigation, "Navigation invalidation")
        let finalRevision = await MainActor.run { controller.presentationRevision }
        await Task.yield()
        let rejectedStale = await MainActor.run {
            controller.presentationRevision == finalRevision
        }
        try expect(rejectedStale, "Stale frame rejection")
        let staticDecodeCount = await fake.decoded()
        await Task.yield()
        let decodeCountAfterStatic = await fake.decoded()
        try expect(decodeCountAfterStatic == staticDecodeCount, "No animation decode for static image")

        let failing = FakeAnimatedLoader(
            kinds: [infiniteURL: .animated(descriptor(count: 2))],
            failingFrames: [0]
        )
        let failingController = await MainActor.run { AnimatedImageController(loader: failing) }
        await MainActor.run { failingController.select(url: infiniteURL, generation: 1) }
        try await waitUntil { failingController.playbackState == .failed }
        let noCorruptPresentation = await MainActor.run {
            failingController.presentedImage == nil
        }
        try expect(noCorruptPresentation, "Corrupt frame isolation")
        await MainActor.run { failingController.stop() }

        print(
            "METRIC: gifFrames=\(metadata.frameCount) pixels=\(metadata.pixelWidth)x\(metadata.pixelHeight) classification=\(classificationDuration) frameDecode=\(frameDecodeDuration) frameStoreLimitBytes=67108864 frameStoreLimitCount=8"
        )
        print("PASS: 31 animated image pipeline checks")
    }
}

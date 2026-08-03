import CoreGraphics
import Foundation
import ImageIO

enum ThumbnailPipelineTestFailure: Error {
    case expectation(String)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw ThumbnailPipelineTestFailure.expectation(message)
    }
}

@MainActor
private func waitUntil(
    _ message: String,
    predicate: () async -> Bool
) async throws {
    for _ in 0..<500 {
        if await predicate() { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    throw ThumbnailPipelineTestFailure.expectation(message)
}

private func image(width: Int, height: Int) -> CGImage {
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

private actor FakeThumbnailLoader: ThumbnailLoading {
    private let delay: Duration
    private var loads = 0
    private var active = 0
    private var peak = 0
    private var cancellations = 0
    private var starts: [String] = []

    init(delay: Duration = .milliseconds(25)) {
        self.delay = delay
    }

    func loadThumbnail(
        from url: URL,
        maximumPixelSize: Int
    ) async throws -> ThumbnailPayload {
        loads += 1
        active += 1
        peak = max(peak, active)
        starts.append(url.lastPathComponent)
        do {
            try await Task.sleep(for: delay)
            active -= 1
            if url.lastPathComponent.contains("failure") {
                throw ThumbnailLoadError.generationFailed
            }
            return ThumbnailPayload(
                image: image(
                    width: min(32, maximumPixelSize),
                    height: min(24, maximumPixelSize)
                )
            )
        } catch {
            active -= 1
            cancellations += 1
            throw error
        }
    }

    func snapshot() -> (
        loads: Int,
        active: Int,
        peak: Int,
        cancellations: Int,
        starts: [String]
    ) {
        (loads, active, peak, cancellations, starts)
    }
}

@main
@MainActor
enum ThumbnailPipelineCLITests {
    static func main() async throws {
        let base = URL(fileURLWithPath: "/private/tmp/ohbee-thumbnail-tests")
        let keyA = ThumbnailRequestKey(
            url: base.appendingPathComponent("a.jpg"),
            maximumPixelSize: 128
        )
        let keyB = ThumbnailRequestKey(
            url: base.appendingPathComponent("b.jpg"),
            maximumPixelSize: 128
        )
        let payload = ThumbnailPayload(image: image(width: 32, height: 32))

        let cache = ThumbnailCache(costLimit: payload.cost + 1)
        let initialCacheValue = await cache.value(for: keyA)
        try expect(initialCacheValue == nil, "Initial cache lookup was not a miss")
        await cache.insert(payload, for: keyA)
        let cacheHit = await cache.value(for: keyA)
        try expect(cacheHit === payload, "Cache hit did not return payload")
        await cache.insert(ThumbnailPayload(image: image(width: 32, height: 32)), for: keyB)
        let bounded = await cache.snapshot()
        try expect(bounded.count == 1, "Cache did not evict to its cost bound")
        try expect(bounded.cost <= bounded.costLimit, "Cache exceeded byte-cost limit")
        try expect(bounded.evictions == 1, "Cache eviction was not recorded")

        let duplicateLoader = FakeThumbnailLoader()
        let duplicateScheduler = ThumbnailScheduler(
            loader: duplicateLoader,
            concurrencyLimit: 2
        )
        async let duplicateOne = duplicateScheduler.thumbnail(for: keyA, priority: .visible)
        async let duplicateTwo = duplicateScheduler.thumbnail(for: keyA, priority: .visible)
        _ = try await (duplicateOne, duplicateTwo)
        let duplicateMetrics = await duplicateLoader.snapshot()
        let duplicateSchedulerMetrics = await duplicateScheduler.snapshot()
        try expect(duplicateMetrics.loads == 1, "Duplicate request was decoded twice")
        try expect(
            duplicateSchedulerMetrics.duplicateRequests == 1,
            "Duplicate suppression was not recorded"
        )

        let boundedLoader = FakeThumbnailLoader(delay: .milliseconds(20))
        let boundedScheduler = ThumbnailScheduler(
            loader: boundedLoader,
            concurrencyLimit: 2
        )
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask {
                    let key = ThumbnailRequestKey(
                        url: base.appendingPathComponent("rapid-\(index).jpg"),
                        maximumPixelSize: 128
                    )
                    _ = try await boundedScheduler.thumbnail(for: key, priority: .nearby)
                }
            }
            try await group.waitForAll()
        }
        let boundedLoaderMetrics = await boundedLoader.snapshot()
        let boundedSchedulerMetrics = await boundedScheduler.snapshot()
        try expect(boundedLoaderMetrics.peak <= 2, "Rapid scrolling exceeded decode bound")
        try expect(
            boundedSchedulerMetrics.peakActiveDecodes <= 2,
            "Scheduler active gauge exceeded configured bound"
        )

        let priorityLoader = FakeThumbnailLoader(delay: .milliseconds(35))
        let priorityScheduler = ThumbnailScheduler(
            loader: priorityLoader,
            concurrencyLimit: 1
        )
        let blocker = ThumbnailRequestKey(
            url: base.appendingPathComponent("blocker.jpg"),
            maximumPixelSize: 128
        )
        let nearby = ThumbnailRequestKey(
            url: base.appendingPathComponent("nearby.jpg"),
            maximumPixelSize: 128
        )
        let visible = ThumbnailRequestKey(
            url: base.appendingPathComponent("visible.jpg"),
            maximumPixelSize: 128
        )
        let blockerTask = Task { try await priorityScheduler.thumbnail(for: blocker, priority: .nearby) }
        try await waitUntil("Priority blocker did not start") {
            await priorityLoader.snapshot().active == 1
        }
        let nearbyTask = Task { try await priorityScheduler.thumbnail(for: nearby, priority: .nearby) }
        let visibleTask = Task { try await priorityScheduler.thumbnail(for: visible, priority: .visible) }
        _ = try await (blockerTask.value, nearbyTask.value, visibleTask.value)
        let priorityStarts = await priorityLoader.snapshot().starts
        try expect(
            priorityStarts == ["blocker.jpg", "visible.jpg", "nearby.jpg"],
            "Visible work did not outrank queued nearby work: \(priorityStarts)"
        )

        let cancellationLoader = FakeThumbnailLoader(delay: .seconds(2))
        let cancellationScheduler = ThumbnailScheduler(
            loader: cancellationLoader,
            concurrencyLimit: 1
        )
        let cancellationTask = Task {
            try await cancellationScheduler.thumbnail(for: keyA, priority: .visible)
        }
        try await waitUntil("Cancellable decode did not start") {
            await cancellationLoader.snapshot().active == 1
        }
        await cancellationScheduler.cancel(keyA)
        do {
            _ = try await cancellationTask.value
            throw ThumbnailPipelineTestFailure.expectation("Cancellation published a thumbnail")
        } catch is CancellationError {
            // Expected.
        }
        let cancellationMetrics = await cancellationLoader.snapshot()
        try expect(
            cancellationMetrics.cancellations == 1,
            "Active loader did not observe cancellation"
        )

        let queuedLoader = FakeThumbnailLoader(delay: .seconds(2))
        let queuedScheduler = ThumbnailScheduler(
            loader: queuedLoader,
            concurrencyLimit: 1
        )
        let queuedBlocker = Task {
            try await queuedScheduler.thumbnail(for: keyA, priority: .visible)
        }
        try await waitUntil("Queued-test blocker did not start") {
            await queuedLoader.snapshot().active == 1
        }
        let queuedTask = Task {
            try await queuedScheduler.thumbnail(for: keyB, priority: .nearby)
        }
        try await waitUntil("Second request did not enter scheduler queue") {
            await queuedScheduler.snapshot().waiting == 1
        }
        await queuedScheduler.cancel(keyB)
        do {
            _ = try await queuedTask.value
            throw ThumbnailPipelineTestFailure.expectation("Queued cancellation published a thumbnail")
        } catch is CancellationError {
            // Expected.
        }
        await queuedScheduler.cancel(keyA)
        _ = await queuedBlocker.result
        try await waitUntil("Cancelled queue did not drain") {
            let snapshot = await queuedScheduler.snapshot()
            return snapshot.waiting == 0 && snapshot.inFlight == 0
        }
        let queuedSnapshot = await queuedScheduler.snapshot()
        try expect(queuedSnapshot.waiting == 0, "Cancelled queued request leaked a waiter")
        try expect(queuedSnapshot.inFlight == 0, "Cancelled queued request leaked an operation")

        let sessionLoader = FakeThumbnailLoader(delay: .milliseconds(60))
        let controller = ThumbnailController(
            loader: sessionLoader,
            cacheCostLimit: 1_024 * 1_024,
            concurrencyLimit: 2
        )
        let firstSession = await controller.beginFolderSession()
        let staleTask = Task {
            try await controller.thumbnail(
                for: keyA,
                priority: .visible,
                session: firstSession
            )
        }
        try await waitUntil("Folder-session thumbnail did not start") {
            await controller.metrics().scheduler.inFlight == 1
        }
        let secondSession = await controller.beginFolderSession()
        do {
            _ = try await staleTask.value
            throw ThumbnailPipelineTestFailure.expectation("Folder switch published stale result")
        } catch is CancellationError {
            // Expected.
        }
        do {
            _ = try await controller.thumbnail(
                for: keyB,
                priority: .visible,
                session: firstSession
            )
            throw ThumbnailPipelineTestFailure.expectation("Old session request was accepted")
        } catch is CancellationError {
            // Expected.
        }
        _ = try await controller.thumbnail(
            for: keyB,
            priority: .visible,
            session: secondSession
        )
        let staleMetrics = await controller.metrics()
        try expect(
            staleMetrics.staleResults >= 1,
            "Stale session rejection was not counted"
        )
        await controller.evict(url: keyB.url)
        let evictedMetrics = await controller.metrics()
        try expect(
            evictedMetrics.cache.count == 0 && evictedMetrics.cache.cost == 0,
            "Targeted Trash eviction retained thumbnail data"
        )
        await controller.handleMemoryPressure()
        let purgedMetrics = await controller.metrics()
        try expect(
            purgedMetrics.cache.cost == 0,
            "Memory pressure did not purge thumbnail cache"
        )

        let fixtureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: fixtureDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }
        let orientedURL = fixtureDirectory.appendingPathComponent("oriented.jpg")
        let type = "public.jpeg" as CFString
        guard let destination = CGImageDestinationCreateWithURL(
            orientedURL as CFURL,
            type,
            1,
            nil
        ) else {
            throw ThumbnailPipelineTestFailure.expectation("Could not create orientation fixture")
        }
        CGImageDestinationAddImage(
            destination,
            image(width: 120, height: 40),
            [kCGImagePropertyOrientation: 6] as CFDictionary
        )
        try expect(CGImageDestinationFinalize(destination), "Could not write orientation fixture")
        let oriented = try await ImageIOThumbnailLoader().loadThumbnail(
            from: orientedURL,
            maximumPixelSize: 120
        )
        try expect(
            oriented.image.height > oriented.image.width,
            "ImageIO thumbnail did not honor EXIF orientation"
        )

        let corruptURL = fixtureDirectory.appendingPathComponent("corrupt.jpg")
        try Data("not an image".utf8).write(to: corruptURL)
        do {
            _ = try await ImageIOThumbnailLoader().loadThumbnail(
                from: corruptURL,
                maximumPixelSize: 128
            )
            throw ThumbnailPipelineTestFailure.expectation("Corrupt thumbnail unexpectedly decoded")
        } catch is ThumbnailLoadError {
            // Expected and isolated.
        }

        let cancelledImageIOTask = Task {
            try await ImageIOThumbnailLoader().loadThumbnail(
                from: orientedURL,
                maximumPixelSize: 120
            )
        }
        cancelledImageIOTask.cancel()
        do {
            _ = try await cancelledImageIOTask.value
            throw ThumbnailPipelineTestFailure.expectation("Cancelled ImageIO task published")
        } catch is CancellationError {
            // Expected.
        }

        let rowLoader = FakeThumbnailLoader(delay: .milliseconds(10))
        let rowController = ThumbnailController(
            loader: rowLoader,
            cacheCostLimit: 1_024 * 1_024,
            concurrencyLimit: 1
        )
        let rowSession = await rowController.beginFolderSession()
        let rowModel = ThumbnailViewModel(
            controller: rowController,
            key: keyA,
            session: rowSession
        )
        rowModel.load()
        try await waitUntil("Visible row did not publish thumbnail") {
            if case .ready = rowModel.state { return true }
            return false
        }
        guard case .ready = rowModel.state else {
            throw ThumbnailPipelineTestFailure.expectation("Visible row did not publish thumbnail")
        }
        rowModel.cancel()
        guard case .placeholder = rowModel.state else {
            throw ThumbnailPipelineTestFailure.expectation("Off-screen row retained CGImage")
        }

        // A 100K navigation index must not imply 100K thumbnail requests. Model
        // a visible LazyVStack working set of 20 items and verify request volume
        // and decode concurrency remain proportional to that window only.
        let visibleWindowURLs = (0..<100_000).prefix(20).map {
            base.appendingPathComponent("large-folder-\($0).jpg")
        }
        let windowLoader = FakeThumbnailLoader(delay: .milliseconds(1))
        let windowController = ThumbnailController(
            loader: windowLoader,
            cacheCostLimit: 2 * 1_024 * 1_024,
            concurrencyLimit: 3
        )
        let windowSession = await windowController.beginFolderSession()
        let windowStart = ContinuousClock.now
        try await withThrowingTaskGroup(of: Void.self) { group in
            for url in visibleWindowURLs {
                group.addTask {
                    _ = try await windowController.thumbnail(
                        for: ThumbnailRequestKey(
                            url: url,
                            maximumPixelSize: 128
                        ),
                        priority: .visible,
                        session: windowSession
                    )
                }
            }
            try await group.waitForAll()
        }
        let windowDuration = windowStart.duration(to: .now)
        let windowLoads = await windowLoader.snapshot()
        let windowMetrics = await windowController.metrics()
        try expect(windowLoads.loads == 20, "100K folder triggered eager thumbnail work")
        try expect(windowLoads.peak <= 3, "100K visible window exceeded concurrency bound")
        try expect(
            windowMetrics.cache.cost <= windowMetrics.cache.costLimit,
            "100K visible window exceeded cache bound"
        )
        print(
            "METRIC: entries=100000 requested=20 duration=\(windowDuration) "
                + "peakDecodes=\(windowLoads.peak) cacheCost=\(windowMetrics.cache.cost)"
        )

        let jpegData = try Data(contentsOf: orientedURL)
        let imageIOURLs = try (0..<100).map { index in
            let url = fixtureDirectory.appendingPathComponent("benchmark-\(index).jpg")
            try jpegData.write(to: url)
            return url
        }
        let imageIOController = ThumbnailController(
            cacheCostLimit: 8 * 1_024 * 1_024,
            concurrencyLimit: 3
        )
        let imageIOSession = await imageIOController.beginFolderSession()
        let imageIOStart = ContinuousClock.now
        try await withThrowingTaskGroup(of: Void.self) { group in
            for url in imageIOURLs {
                group.addTask {
                    _ = try await imageIOController.thumbnail(
                        for: ThumbnailRequestKey(
                            url: url,
                            maximumPixelSize: 224
                        ),
                        priority: .visible,
                        session: imageIOSession
                    )
                }
            }
            try await group.waitForAll()
        }
        let imageIODuration = imageIOStart.duration(to: .now)
        let imageIOMetrics = await imageIOController.metrics()
        try expect(imageIOMetrics.generated == 100, "ImageIO benchmark lost thumbnails")
        try expect(
            imageIOMetrics.scheduler.peakActiveDecodes <= 3,
            "ImageIO benchmark exceeded concurrency limit"
        )
        print(
            "METRIC: imageIOThumbnails=100 duration=\(imageIODuration) "
                + "averageSeconds=\(imageIOMetrics.averageGenerationSeconds) "
                + "peakDecodes=\(imageIOMetrics.scheduler.peakActiveDecodes) "
                + "cacheCost=\(imageIOMetrics.cache.cost)"
        )

        print("PASS: 35 thumbnail pipeline checks")
    }
}

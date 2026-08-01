import Foundation

struct ThumbnailEvictionRequest: Sendable, Equatable {
    let url: URL
    let generation: UInt64
}

struct ThumbnailControllerMetrics: Sendable, Equatable {
    let cache: ThumbnailCache.Snapshot
    let scheduler: ThumbnailScheduler.Snapshot
    let generated: Int
    let staleResults: Int
    let averageGenerationSeconds: Double
}

actor ThumbnailController {
    private let cache: ThumbnailCache
    private let scheduler: ThumbnailScheduler
    private var session: UInt64 = 0
    private var generated = 0
    private var staleResults = 0
    private var totalGenerationSeconds: Double = 0

    init(
        loader: any ThumbnailLoading = ImageIOThumbnailLoader(),
        cacheCostLimit: Int = 64 * 1_024 * 1_024,
        concurrencyLimit: Int = 3
    ) {
        cache = ThumbnailCache(costLimit: cacheCostLimit)
        scheduler = ThumbnailScheduler(
            loader: loader,
            concurrencyLimit: concurrencyLimit
        )
    }

    func beginFolderSession() async -> UInt64 {
        session &+= 1
        await scheduler.cancelAll()
        return session
    }

    func thumbnail(
        for key: ThumbnailRequestKey,
        priority: ThumbnailRequestPriority,
        session requestedSession: UInt64
    ) async throws -> ThumbnailPayload {
        guard requestedSession == session else {
            staleResults += 1
            throw CancellationError()
        }

        if let cached = await cache.value(for: key) {
            guard requestedSession == session, !Task.isCancelled else {
                staleResults += 1
                throw CancellationError()
            }
            let cacheSnapshot = await cache.snapshot()
            await MainActor.run {
                Diagnostics.recordThumbnailCache(
                    hit: true,
                    snapshot: cacheSnapshot
                )
            }
            return cached
        }

        let cacheSnapshot = await cache.snapshot()
        await MainActor.run {
            Diagnostics.recordThumbnailCache(hit: false, snapshot: cacheSnapshot)
        }
        guard requestedSession == session, !Task.isCancelled else {
            staleResults += 1
            throw CancellationError()
        }

        let clock = ContinuousClock()
        let started = clock.now
        do {
            let payload = try await scheduler.thumbnail(
                for: key,
                priority: priority
            )
            guard requestedSession == session, !Task.isCancelled else {
                staleResults += 1
                throw CancellationError()
            }
            let elapsed = started.duration(to: clock.now)
            generated += 1
            totalGenerationSeconds += elapsed.seconds
            await cache.insert(payload, for: key)
            let updatedCache = await cache.snapshot()
            let schedulerSnapshot = await scheduler.snapshot()
            let generatedCount = generated
            let averageSeconds = totalGenerationSeconds / Double(generatedCount)
            await MainActor.run {
                Diagnostics.recordThumbnailGenerated(
                    duration: elapsed,
                    cache: updatedCache,
                    scheduler: schedulerSnapshot,
                    generated: generatedCount,
                    averageSeconds: averageSeconds
                )
            }
            return payload
        } catch is CancellationError {
            let schedulerSnapshot = await scheduler.snapshot()
            await MainActor.run {
                Diagnostics.recordThumbnailCancellation(
                    scheduler: schedulerSnapshot
                )
            }
            throw CancellationError()
        } catch {
            await MainActor.run {
                Diagnostics.recordThumbnailFailure(error)
            }
            throw error
        }
    }

    func cancel(_ key: ThumbnailRequestKey) async {
        await scheduler.cancel(key)
    }

    func cancelAll() async {
        session &+= 1
        await scheduler.cancelAll()
    }

    func evict(url: URL) async {
        await scheduler.cancel(url: url)
        let removed = await cache.remove(url: url)
        await MainActor.run {
            Diagnostics.recordThumbnailEviction(removed: removed)
        }
    }

    func handleMemoryPressure() async {
        await scheduler.cancelAll()
        await cache.removeAll()
    }

    func metrics() async -> ThumbnailControllerMetrics {
        ThumbnailControllerMetrics(
            cache: await cache.snapshot(),
            scheduler: await scheduler.snapshot(),
            generated: generated,
            staleResults: staleResults,
            averageGenerationSeconds: generated == 0
                ? 0
                : totalGenerationSeconds / Double(generated)
        )
    }
}

private extension Duration {
    var seconds: Double {
        let components = self.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

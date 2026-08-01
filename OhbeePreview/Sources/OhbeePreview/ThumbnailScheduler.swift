import Foundation

enum ThumbnailRequestPriority: Int, Sendable {
    case nearby = 0
    case visible = 1

    var taskPriority: TaskPriority {
        switch self {
        case .visible: .userInitiated
        case .nearby: .utility
        }
    }
}

private actor ThumbnailPermitPool {
    private struct Waiter {
        let priority: ThumbnailRequestPriority
        let continuation: CheckedContinuation<Void, Error>
    }

    private let limit: Int
    private var available: Int
    private var waiters: [UUID: Waiter] = [:]
    private var holders: Set<UUID> = []
    private var peakActive = 0

    init(limit: Int) {
        self.limit = max(1, limit)
        available = max(1, limit)
    }

    func acquire(
        id: UUID,
        priority: ThumbnailRequestPriority
    ) async throws {
        try Task.checkCancellation()
        if available > 0 {
            available -= 1
            holders.insert(id)
            peakActive = max(peakActive, holders.count)
            return
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters[id] = Waiter(
                    priority: priority,
                    continuation: continuation
                )
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    func release(id: UUID) {
        guard holders.remove(id) != nil else { return }
        if let next = waiters.max(by: {
            $0.value.priority.rawValue < $1.value.priority.rawValue
        }) {
            waiters.removeValue(forKey: next.key)
            holders.insert(next.key)
            peakActive = max(peakActive, holders.count)
            next.value.continuation.resume()
        } else {
            available = min(limit, available + 1)
        }
    }

    func cancel(id: UUID) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume(throwing: CancellationError())
    }

    func raisePriority(
        id: UUID,
        to priority: ThumbnailRequestPriority
    ) {
        guard let waiter = waiters[id], priority.rawValue > waiter.priority.rawValue else {
            return
        }
        waiters[id] = Waiter(
            priority: priority,
            continuation: waiter.continuation
        )
    }

    func snapshot() -> (active: Int, waiting: Int, peakActive: Int) {
        (holders.count, waiters.count, peakActive)
    }
}

actor ThumbnailScheduler {
    struct Snapshot: Sendable, Equatable {
        let inFlight: Int
        let activeDecodes: Int
        let waiting: Int
        let peakActiveDecodes: Int
        let cancellations: Int
        let duplicateRequests: Int
    }

    private struct Operation {
        let id: UUID
        let task: Task<ThumbnailPayload, Error>
        var priority: ThumbnailRequestPriority
    }

    private let loader: any ThumbnailLoading
    private let permits: ThumbnailPermitPool
    private var operations: [ThumbnailRequestKey: Operation] = [:]
    private var cancellations = 0
    private var duplicateRequests = 0

    init(
        loader: any ThumbnailLoading = ImageIOThumbnailLoader(),
        concurrencyLimit: Int = 3
    ) {
        self.loader = loader
        permits = ThumbnailPermitPool(limit: concurrencyLimit)
    }

    func thumbnail(
        for key: ThumbnailRequestKey,
        priority: ThumbnailRequestPriority
    ) async throws -> ThumbnailPayload {
        if var existing = operations[key] {
            duplicateRequests += 1
            if priority.rawValue > existing.priority.rawValue {
                existing.priority = priority
                operations[key] = existing
                await permits.raisePriority(id: existing.id, to: priority)
            }
            return try await existing.task.value
        }

        let id = UUID()
        let loader = self.loader
        let permits = self.permits
        let task = Task(priority: priority.taskPriority) {
            do {
                try await permits.acquire(id: id, priority: priority)
                try Task.checkCancellation()
                let result = try await loader.loadThumbnail(
                    from: key.url,
                    maximumPixelSize: key.maximumPixelSize
                )
                await permits.release(id: id)
                return result
            } catch {
                await permits.release(id: id)
                throw error
            }
        }
        operations[key] = Operation(id: id, task: task, priority: priority)

        do {
            let result = try await task.value
            finish(key: key, id: id)
            return result
        } catch {
            finish(key: key, id: id)
            throw error
        }
    }

    func cancel(_ key: ThumbnailRequestKey) {
        guard let operation = operations.removeValue(forKey: key) else { return }
        cancellations += 1
        operation.task.cancel()
    }

    func cancelAll() {
        let active = operations.values
        operations.removeAll(keepingCapacity: true)
        cancellations += active.count
        for operation in active {
            operation.task.cancel()
        }
    }

    func snapshot() async -> Snapshot {
        let permits = await permits.snapshot()
        return Snapshot(
            inFlight: operations.count,
            activeDecodes: permits.active,
            waiting: permits.waiting,
            peakActiveDecodes: permits.peakActive,
            cancellations: cancellations,
            duplicateRequests: duplicateRequests
        )
    }

    private func finish(key: ThumbnailRequestKey, id: UUID) {
        guard operations[key]?.id == id else { return }
        operations.removeValue(forKey: key)
    }
}

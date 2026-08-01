import Foundation

private actor AnimatedDecodeGate {
    private var holder: UUID?
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var peakActive = 0

    func acquire(id: UUID) async throws {
        try Task.checkCancellation()
        if holder == nil {
            holder = id
            peakActive = max(peakActive, 1)
            return
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters[id] = continuation
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    func release(id: UUID) {
        guard holder == id else { return }
        if let next = waiters.first {
            waiters.removeValue(forKey: next.key)
            holder = next.key
            next.value.resume()
        } else {
            holder = nil
        }
    }

    func cancel(id: UUID) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.resume(throwing: CancellationError())
    }

    func snapshot() -> (active: Int, waiting: Int, peak: Int) {
        (holder == nil ? 0 : 1, waiters.count, peakActive)
    }
}

actor AnimatedFrameScheduler {
    private struct Key: Hashable {
        let sessionID: UUID
        let url: URL
        let index: Int
    }

    private struct Operation {
        let task: Task<AnimatedFrame, Error>
    }

    private let loader: any AnimatedImageLoading
    private let gate = AnimatedDecodeGate()
    private var operations: [Key: Operation] = [:]
    private var cancellations = 0
    private var duplicates = 0

    init(loader: any AnimatedImageLoading = ImageIOAnimatedImageLoader()) {
        self.loader = loader
    }

    func frame(
        sessionID: UUID,
        url: URL,
        descriptor: AnimatedImageDescriptor,
        index: Int
    ) async throws -> AnimatedFrame {
        let key = Key(
            sessionID: sessionID,
            url: url.standardizedFileURL,
            index: index
        )
        if let existing = operations[key] {
            duplicates += 1
            return try await existing.task.value
        }
        let loader = self.loader
        let gate = self.gate
        let operationID = UUID()
        let task = Task(priority: .userInitiated) {
            do {
                try await gate.acquire(id: operationID)
                try Task.checkCancellation()
                let frame = try await loader.decodeFrame(
                    url: url,
                    descriptor: descriptor,
                    index: index
                )
                await gate.release(id: operationID)
                return frame
            } catch {
                await gate.release(id: operationID)
                throw error
            }
        }
        operations[key] = Operation(task: task)
        defer { operations.removeValue(forKey: key) }
        return try await task.value
    }

    func cancelAll() {
        cancellations += operations.count
        for operation in operations.values { operation.task.cancel() }
        operations.removeAll(keepingCapacity: true)
    }

    func cancel(sessionID: UUID) {
        let matching = operations.filter { $0.key.sessionID == sessionID }
        cancellations += matching.count
        for (key, operation) in matching {
            operations.removeValue(forKey: key)
            operation.task.cancel()
        }
    }

    func snapshot() async -> (
        inFlight: Int,
        active: Int,
        waiting: Int,
        peak: Int,
        cancellations: Int,
        duplicates: Int
    ) {
        let gate = await gate.snapshot()
        return (
            operations.count,
            gate.active,
            gate.waiting,
            gate.peak,
            cancellations,
            duplicates
        )
    }
}

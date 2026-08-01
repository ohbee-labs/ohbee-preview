import Foundation

actor AnimatedFrameStore {
    struct Key: Hashable, Sendable {
        let sessionID: UUID
        let frameIndex: Int
    }

    struct Snapshot: Sendable, Equatable {
        let count: Int
        let cost: Int
        let hits: Int
        let misses: Int
        let evictions: Int
        let purges: Int
    }

    private struct Entry {
        let frame: AnimatedFrame
        var sequence: UInt64
    }

    private let byteLimit: Int
    private let frameLimit: Int
    private var entries: [Key: Entry] = [:]
    private var totalCost = 0
    private var sequence: UInt64 = 0
    private var hits = 0
    private var misses = 0
    private var evictions = 0
    private var purges = 0

    init(byteLimit: Int = 64 * 1_024 * 1_024, frameLimit: Int = 8) {
        self.byteLimit = max(1, byteLimit)
        self.frameLimit = max(1, frameLimit)
    }

    func frame(for key: Key) -> AnimatedFrame? {
        guard var entry = entries[key] else {
            misses += 1
            return nil
        }
        hits += 1
        sequence &+= 1
        entry.sequence = sequence
        entries[key] = entry
        return entry.frame
    }

    func insert(_ frame: AnimatedFrame, for key: Key) {
        guard frame.decodedByteCost <= byteLimit else { return }
        if let previous = entries.removeValue(forKey: key) {
            totalCost -= previous.frame.decodedByteCost
        }
        sequence &+= 1
        entries[key] = Entry(frame: frame, sequence: sequence)
        totalCost += frame.decodedByteCost
        evictIfNeeded()
    }

    func purge(keeping key: Key?) {
        let retained = key.flatMap { entries[$0] }
        entries.removeAll(keepingCapacity: true)
        totalCost = 0
        if let key, let retained {
            entries[key] = retained
            totalCost = retained.frame.decodedByteCost
        }
        purges += 1
    }

    func removeAll() {
        entries.removeAll(keepingCapacity: true)
        totalCost = 0
    }

    func remove(sessionID: UUID) {
        let matching = entries.filter { $0.key.sessionID == sessionID }
        for (key, entry) in matching {
            entries.removeValue(forKey: key)
            totalCost -= entry.frame.decodedByteCost
        }
    }

    func snapshot() -> Snapshot {
        Snapshot(
            count: entries.count,
            cost: totalCost,
            hits: hits,
            misses: misses,
            evictions: evictions,
            purges: purges
        )
    }

    private func evictIfNeeded() {
        while entries.count > frameLimit || totalCost > byteLimit {
            guard let victim = entries.min(by: { $0.value.sequence < $1.value.sequence }) else {
                return
            }
            entries.removeValue(forKey: victim.key)
            totalCost -= victim.value.frame.decodedByteCost
            evictions += 1
        }
    }
}

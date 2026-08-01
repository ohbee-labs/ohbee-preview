import Foundation

actor ThumbnailCache {
    struct Snapshot: Sendable, Equatable {
        let count: Int
        let cost: Int
        let costLimit: Int
        let hits: Int
        let misses: Int
        let insertions: Int
        let evictions: Int

        var hitRate: Double {
            let lookups = hits + misses
            return lookups == 0 ? 0 : Double(hits) / Double(lookups)
        }
    }

    private struct Entry {
        let payload: ThumbnailPayload
        var access: UInt64
    }

    private let costLimit: Int
    private var entries: [ThumbnailRequestKey: Entry] = [:]
    private var totalCost = 0
    private var clock: UInt64 = 0
    private var hits = 0
    private var misses = 0
    private var insertions = 0
    private var evictions = 0

    init(costLimit: Int = 64 * 1_024 * 1_024) {
        self.costLimit = max(1, costLimit)
    }

    func value(for key: ThumbnailRequestKey) -> ThumbnailPayload? {
        guard var entry = entries[key] else {
            misses += 1
            return nil
        }
        hits += 1
        clock &+= 1
        entry.access = clock
        entries[key] = entry
        return entry.payload
    }

    func insert(_ payload: ThumbnailPayload, for key: ThumbnailRequestKey) {
        guard payload.cost <= costLimit else { return }
        if let old = entries.removeValue(forKey: key) {
            totalCost -= old.payload.cost
        }
        clock &+= 1
        entries[key] = Entry(payload: payload, access: clock)
        totalCost += payload.cost
        insertions += 1
        evictIfNeeded()
    }

    func removeAll() {
        entries.removeAll(keepingCapacity: true)
        totalCost = 0
    }

    func remove(url: URL) -> Int {
        let normalized = url.standardizedFileURL
        let matching = entries.filter { $0.key.url == normalized }
        for (key, entry) in matching {
            entries.removeValue(forKey: key)
            totalCost -= entry.payload.cost
        }
        return matching.count
    }

    func snapshot() -> Snapshot {
        Snapshot(
            count: entries.count,
            cost: totalCost,
            costLimit: costLimit,
            hits: hits,
            misses: misses,
            insertions: insertions,
            evictions: evictions
        )
    }

    private func evictIfNeeded() {
        while totalCost > costLimit,
              let victim = entries.min(by: { $0.value.access < $1.value.access }) {
            entries.removeValue(forKey: victim.key)
            totalCost -= victim.value.payload.cost
            evictions += 1
        }
    }
}

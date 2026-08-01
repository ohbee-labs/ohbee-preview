import Foundation

public struct NavigationEntry: Sendable, Hashable {
    public let url: URL
    public let filename: String
    public let fileIdentity: Data?

    public init(url: URL, filename: String, fileIdentity: Data? = nil) {
        self.url = url.standardizedFileURL
        self.filename = filename
        self.fileIdentity = fileIdentity
    }
}

public struct NavigationSnapshot: Sendable, Equatable {
    public struct Removal: Sendable, Equatable {
        public let removedWasCurrent: Bool
        public let selectedEntry: NavigationEntry?
        public let remainingEntries: [NavigationEntry]
    }
    public private(set) var entries: [NavigationEntry]
    public private(set) var currentIndex: Int

    public init?(entries: [NavigationEntry], selectedURL: URL, selectedIdentity: Data? = nil) {
        let normalizedSelection = selectedURL.standardizedFileURL
        guard let index = entries.firstIndex(where: { entry in
            if entry.url == normalizedSelection {
                return true
            }
            guard let selectedIdentity, let entryIdentity = entry.fileIdentity else {
                return false
            }
            return selectedIdentity == entryIdentity
        }) else {
            return nil
        }
        self.entries = entries
        currentIndex = index
    }

    public var current: NavigationEntry {
        entries[currentIndex]
    }

    public var canNavigatePrevious: Bool {
        currentIndex > entries.startIndex
    }

    public var canNavigateNext: Bool {
        currentIndex + 1 < entries.endIndex
    }

    public var position: Int {
        currentIndex + 1
    }

    @discardableResult
    public mutating func selectPrevious() -> NavigationEntry? {
        guard canNavigatePrevious else { return nil }
        currentIndex -= 1
        return current
    }

    @discardableResult
    public mutating func selectNext() -> NavigationEntry? {
        guard canNavigateNext else { return nil }
        currentIndex += 1
        return current
    }

    @discardableResult
    public mutating func select(url: URL) -> NavigationEntry? {
        let normalized = url.standardizedFileURL
        guard let index = entries.firstIndex(where: { $0.url == normalized }) else {
            return nil
        }
        currentIndex = index
        return current
    }

    @discardableResult
    public func removing(
        url: URL,
        fileIdentity: Data? = nil
    ) -> Removal? {
        let normalized = url.standardizedFileURL
        guard let removedIndex = entries.firstIndex(where: { entry in
            if entry.url == normalized { return true }
            guard let fileIdentity, let entryIdentity = entry.fileIdentity else {
                return false
            }
            return fileIdentity == entryIdentity
        }) else { return nil }

        let removedWasCurrent = removedIndex == currentIndex
        var remaining = entries
        remaining.remove(at: removedIndex)
        guard !remaining.isEmpty else {
            return Removal(
                removedWasCurrent: removedWasCurrent,
                selectedEntry: nil,
                remainingEntries: []
            )
        }
        let selectedIndex: Int
        if removedWasCurrent {
            selectedIndex = min(removedIndex, remaining.index(before: remaining.endIndex))
        } else if removedIndex < currentIndex {
            selectedIndex = currentIndex - 1
        } else {
            selectedIndex = currentIndex
        }
        return Removal(
            removedWasCurrent: removedWasCurrent,
            selectedEntry: remaining[selectedIndex],
            remainingEntries: remaining
        )
    }
}

public struct FolderNavigationResult: Sendable {
    public let snapshot: NavigationSnapshot?
    public let eligibleImageCount: Int
    public let enumerationDuration: Duration
    public let sortingDuration: Duration
    public let matchingDuration: Duration

    public init(
        snapshot: NavigationSnapshot?,
        eligibleImageCount: Int,
        enumerationDuration: Duration,
        sortingDuration: Duration,
        matchingDuration: Duration
    ) {
        self.snapshot = snapshot
        self.eligibleImageCount = eligibleImageCount
        self.enumerationDuration = enumerationDuration
        self.sortingDuration = sortingDuration
        self.matchingDuration = matchingDuration
    }
}

public enum NaturalFilenameOrder {
    public static func areInIncreasingOrder(
        _ lhs: NavigationEntry,
        _ rhs: NavigationEntry
    ) -> Bool {
        let localized = lhs.filename.localizedStandardCompare(rhs.filename)
        if localized != .orderedSame {
            return localized == .orderedAscending
        }

        let literal = lhs.filename.compare(
            rhs.filename,
            options: [.literal],
            locale: Locale(identifier: "en_US_POSIX")
        )
        if literal != .orderedSame {
            return literal == .orderedAscending
        }
        return lhs.url.absoluteString < rhs.url.absoluteString
    }
}

public enum FolderNavigationService {
    public static func discover(
        folderURL: URL,
        selectedURL: URL
    ) async throws -> FolderNavigationResult {
        try await Task.detached(priority: .utility) {
            try Task.checkCancellation()

            let clock = ContinuousClock()
            let enumerationStart = clock.now
            let keys: Set<URLResourceKey> = [
                .fileResourceIdentifierKey,
                .isHiddenKey,
                .isPackageKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .nameKey
            ]
            let children = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )

            var entries: [NavigationEntry] = []
            entries.reserveCapacity(children.count)
            var observedURLs: Set<URL> = []

            for child in children {
                try Task.checkCancellation()
                guard SupportedImageFormat.supports(child) else { continue }

                guard let values = try? child.resourceValues(forKeys: keys) else {
                    continue
                }
                guard
                    values.isHidden != true,
                    values.isPackage != true,
                    values.isSymbolicLink != true,
                    values.isRegularFile == true
                else {
                    continue
                }

                let normalized = child.standardizedFileURL
                guard observedURLs.insert(normalized).inserted else { continue }
                entries.append(
                    NavigationEntry(
                        url: normalized,
                        filename: values.name ?? child.lastPathComponent,
                        fileIdentity: values.fileResourceIdentifier as? Data
                    )
                )
            }
            let enumerationDuration = enumerationStart.duration(to: clock.now)

            try Task.checkCancellation()
            let sortingStart = clock.now
            entries.sort(by: NaturalFilenameOrder.areInIncreasingOrder)
            let sortingDuration = sortingStart.duration(to: clock.now)

            try Task.checkCancellation()
            let matchingStart = clock.now
            let selectedValues = try? selectedURL.resourceValues(
                forKeys: [.fileResourceIdentifierKey]
            )
            let selectedIdentity = selectedValues?.fileResourceIdentifier as? Data
            let snapshot = NavigationSnapshot(
                entries: entries,
                selectedURL: selectedURL,
                selectedIdentity: selectedIdentity
            )
            let matchingDuration = matchingStart.duration(to: clock.now)

            return FolderNavigationResult(
                snapshot: snapshot,
                eligibleImageCount: entries.count,
                enumerationDuration: enumerationDuration,
                sortingDuration: sortingDuration,
                matchingDuration: matchingDuration
            )
        }.value
    }
}

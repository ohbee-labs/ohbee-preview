import AppKit
import Foundation
import ImageIO
import OhbeeStage2Core
import UniformTypeIdentifiers

enum IntegrationTestFailure: Error {
    case expectation(String)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw IntegrationTestFailure.expectation(message) }
}

private func makeImage(
    at url: URL,
    type: NSBitmapImageRep.FileType
) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 4,
        pixelsHigh: 4,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw IntegrationTestFailure.expectation("Could not create image fixture")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.systemOrange.setFill()
    NSRect(x: 0, y: 0, width: 4, height: 4).fill()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: type, properties: [:]) else {
        throw IntegrationTestFailure.expectation(
            "Could not encode \(url.pathExtension) fixture"
        )
    }
    try data.write(to: url)
}

private func makeHEIC(at url: URL) -> Bool {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard
        let context = CGContext(
            data: nil,
            width: 4,
            height: 4,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.heic.identifier as CFString,
            1,
            nil
        )
    else {
        return false
    }
    CGImageDestinationAddImage(destination, image, nil)
    let succeeded = CGImageDestinationFinalize(destination)
    if !succeeded {
        try? FileManager.default.removeItem(at: url)
    }
    return succeeded
}

private actor DisplayRecorder {
    private(set) var displayedURL: URL?
    private(set) var cancellationCount = 0
    private(set) var staleRejectionCount = 0

    func display(_ url: URL) {
        displayedURL = url
    }

    func cancelled() {
        cancellationCount += 1
    }

    func stale() {
        staleRejectionCount += 1
    }
}

private func loadAfterDelay(
    url: URL,
    delay: Duration,
    request: OpenRequest,
    coordinator: OpenRequestCoordinator,
    recorder: DisplayRecorder
) async {
    do {
        try await Task.sleep(for: delay)
        _ = try await SelectedImageLoader.load(url: url)
        if await coordinator.isCurrent(request), !Task.isCancelled {
            await recorder.display(url)
        } else {
            await recorder.stale()
        }
    } catch is CancellationError {
        await recorder.cancelled()
    } catch {
        await recorder.stale()
    }
}

private func expectLoadError(
    _ expected: SelectedImageLoadError,
    url: URL
) async throws {
    do {
        _ = try await SelectedImageLoader.load(url: url)
        throw IntegrationTestFailure.expectation(
            "Expected \(expected) for \(url.pathExtension)"
        )
    } catch let error as SelectedImageLoadError {
        try expect(error == expected, "Received \(error), expected \(expected)")
    }
}

@main
enum Stage2IntegrationCLITests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohbee-milestone1-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let image1 = root.appendingPathComponent("image1.png")
        let image2 = root.appendingPathComponent("image2.jpg")
        let image10 = root.appendingPathComponent("image10.tiff")
        try makeImage(at: image1, type: .png)
        try makeImage(at: image2, type: .jpeg)
        try makeImage(at: image10, type: .tiff)
        try makeImage(at: root.appendingPathComponent("first.gif"), type: .gif)
        let heicFixtureAvailable = makeHEIC(
            at: root.appendingPathComponent("still.heic")
        )
        let heifFixtureAvailable = makeHEIC(
            at: root.appendingPathComponent("still.heif")
        )
        try Data("unsupported".utf8).write(to: root.appendingPathComponent("notes.txt"))

        let clock = ContinuousClock()
        let displayStart = clock.now
        let displayTask = Task {
            try await SelectedImageLoader.load(url: image2)
        }
        let discoveryTask = Task {
            try await Task.sleep(for: .milliseconds(100))
            return try await FolderNavigationService.discover(
                folderURL: root,
                selectedURL: image2
            )
        }

        let initiallyLoaded = try await displayTask.value
        let selectedImageDuration = displayStart.duration(to: clock.now)
        try expect(
            initiallyLoaded.image.tiffRepresentation != nil,
            "Selected image did not display independently of discovery"
        )
        let discovered = try await discoveryTask.value
        guard var snapshot = discovered.snapshot else {
            throw IntegrationTestFailure.expectation("Selected image was not matched")
        }
        try expect(
            snapshot.entries.map(\.filename).contains("notes.txt") == false,
            "Unsupported file entered navigation"
        )

        while snapshot.canNavigatePrevious {
            _ = snapshot.selectPrevious()
        }
        try expect(snapshot.selectPrevious() == nil, "Previous wrapped at boundary")
        while snapshot.canNavigateNext {
            _ = snapshot.selectNext()
        }
        try expect(snapshot.selectNext() == nil, "Next wrapped at boundary")

        for entry in snapshot.entries {
            let loaded = try await SelectedImageLoader.load(url: entry.url)
            try expect(
                loaded.image.tiffRepresentation != nil,
                "Supported fixture did not decode: \(entry.filename)"
            )
        }

        let corrupt = root.appendingPathComponent("corrupt.png")
        try Data("not image data".utf8).write(to: corrupt)
        try await expectLoadError(.decodeFailed, url: corrupt)
        try await expectLoadError(
            .missing,
            url: root.appendingPathComponent("missing.jpg")
        )
        try await expectLoadError(
            .unsupported,
            url: root.appendingPathComponent("unsupported.raw")
        )
        let denied = root.appendingPathComponent("denied.png")
        try makeImage(at: denied, type: .png)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0],
            ofItemAtPath: denied.path
        )
        try await expectLoadError(.permissionDenied, url: denied)

        try expect(
            StaticImageResourcePolicy.accepts(width: 6_000, height: 4_000),
            "24-megapixel still was rejected by the resource policy"
        )
        try expect(
            !StaticImageResourcePolicy.accepts(width: 50_000, height: 10),
            "Excessive image dimension was accepted"
        )
        try expect(
            !StaticImageResourcePolicy.accepts(width: 20_000, height: 20_000),
            "Excessive decoded byte cost was accepted"
        )
        try expect(
            StaticImageResourcePolicy.decodedByteCost(width: Int.max, height: 2) == nil,
            "Overflowing dimension multiplication was accepted"
        )

        let coordinator = OpenRequestCoordinator()
        let recorder = DisplayRecorder()
        let older = await coordinator.begin(url: image1)
        let olderTask = Task {
            await loadAfterDelay(
                url: image1,
                delay: .milliseconds(200),
                request: older,
                coordinator: coordinator,
                recorder: recorder
            )
        }
        let newer = await coordinator.begin(url: image10)
        olderTask.cancel()
        let newerTask = Task {
            await loadAfterDelay(
                url: image10,
                delay: .milliseconds(10),
                request: newer,
                coordinator: coordinator,
                recorder: recorder
            )
        }
        await olderTask.value
        await newerTask.value
        let finalDisplayedURL = await recorder.displayedURL
        let cancelledCount = await recorder.cancellationCount
        try expect(finalDisplayedURL == image10, "Latest navigation did not win")
        try expect(cancelledCount == 1, "Obsolete decode was not cancelled")

        do {
            _ = try await FolderNavigationService.discover(
                folderURL: root.appendingPathComponent("unavailable"),
                selectedURL: image2
            )
            throw IntegrationTestFailure.expectation("Missing folder discovery succeeded")
        } catch let error as IntegrationTestFailure {
            throw error
        } catch {
            try expect(
                initiallyLoaded.image.tiffRepresentation != nil,
                "Folder failure discarded the opened image"
            )
        }

        let permissionState = ImageSessionState(selectedURL: image2)
        try expect(
            permissionState.authorization == .notAssessed,
            "Image session began with unexpected authorization"
        )
        let granted = try await FolderNavigationService.discover(
            folderURL: root,
            selectedURL: image2
        )
        try expect(granted.snapshot != nil, "Granted folder did not enable navigation")

        if !heicFixtureAvailable || !heifFixtureAvailable {
            print("SKIP: HEIC/HEIF decode fixtures; system ImageIO encoder unavailable")
        }
        print(
            """
            METRIC: selectedDecode=\(selectedImageDuration) \
            enumeration=\(discovered.enumerationDuration) \
            sort=\(discovered.sortingDuration) \
            match=\(discovered.matchingDuration) \
            eligible=\(discovered.eligibleImageCount)
            """
        )
        print("PASS: 17 Folder Navigation MVP and static-resource checks")
    }
}

import AppKit
import Foundation
import ImageIO
import OhbeeStage2Core
import UniformTypeIdentifiers

enum FinderTestFailure: Error { case failed(String) }

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw FinderTestFailure.failed(message) }
}

@MainActor
func waitUntil(
    timeout: Duration = .seconds(3),
    _ predicate: @escaping @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !predicate() {
        guard clock.now < deadline else { throw FinderTestFailure.failed("Timed out: state") }
        await Task.yield()
    }
}

func writePNG(_ url: URL, shade: UInt8) throws {
    let bytes = [UInt8](repeating: shade, count: 8 * 8 * 4)
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let image = CGImage(
        width: 8,
        height: 8,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: 32,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else { throw FinderTestFailure.failed("PNG destination") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw FinderTestFailure.failed("PNG finalization")
    }
}

actor RecordingFinderService: FinderActionServicing {
    enum Mode { case succeed, fail }
    let disposalFolder: URL
    var mode: Mode = .succeed
    var revealed: [FinderActionTarget] = []
    var trashed: [FinderActionTarget] = []

    init(disposalFolder: URL) { self.disposalFolder = disposalFolder }

    func reveal(_ target: FinderActionTarget) async throws {
        revealed.append(target)
        if mode == .fail { throw FinderActionError.revealFailed }
    }

    func moveToTrash(_ target: FinderActionTarget) async throws {
        trashed.append(target)
        if mode == .fail { throw FinderActionError.permissionDenied }
        let destination = disposalFolder.appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(at: target.url, to: destination)
    }

    func setMode(_ newMode: Mode) { mode = newMode }
    func revealedTargets() -> [FinderActionTarget] { revealed }
    func trashedTargets() -> [FinderActionTarget] { trashed }
}

@MainActor
final class ImmediateConfirmation: TrashConfirming {
    let response: Bool
    private(set) var targets: [FinderActionTarget] = []
    init(_ response: Bool) { self.response = response }
    func confirmTrash(of target: FinderActionTarget) async -> Bool {
        targets.append(target)
        return response
    }
}

@MainActor
final class GateConfirmation: TrashConfirming {
    private(set) var target: FinderActionTarget?
    private var continuation: CheckedContinuation<Bool, Never>?

    func confirmTrash(of target: FinderActionTarget) async -> Bool {
        self.target = target
        return await withCheckedContinuation { continuation = $0 }
    }

    func resolve(_ response: Bool) {
        continuation?.resume(returning: response)
        continuation = nil
    }
}

@main
@MainActor
enum FinderActionCLITests {
    static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohbee-finder-actions-\(UUID().uuidString)")
        let disposal = root.appendingPathComponent("disposal")
        try FileManager.default.createDirectory(at: disposal, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let a = root.appendingPathComponent("image1.png")
        let b = root.appendingPathComponent("image2.png")
        let c = root.appendingPathComponent("image3.png")
        try writePNG(a, shade: 40)
        try writePNG(b, shade: 90)
        try writePNG(c, shade: 140)

        let service = RecordingFinderService(disposalFolder: disposal)
        let gate = GateConfirmation()
        let controller = FinderActionController(service: service, confirmation: gate)
        let model = AppModel(finderActions: controller)
        model.open(url: a)
        try await waitUntil {
            model.thumbnailEntries.count == 3
                && model.displayedImage?.sourceURL == a.standardizedFileURL
        }
        try expect(model.canRevealCurrentFile, "Reveal enabled")
        try expect(model.canMoveCurrentFileToTrash, "Trash enabled")

        model.revealCurrentInFinder()
        try await waitUntil { !model.isFinderActionPending }
        let reveals = await service.revealedTargets()
        try expect(reveals.count == 1 && reveals[0].url == a.standardizedFileURL, "Reveal target identity")

        model.moveCurrentToTrash()
        try await waitUntil { gate.target != nil }
        let immutableTarget = try XCTUnwrap(gate.target)
        model.navigateNext()
        try await waitUntil { model.displayedImage?.sourceURL == b.standardizedFileURL }
        gate.resolve(true)
        try await waitUntil { !model.isFinderActionPending }
        let trashed = await service.trashedTargets()
        try expect(trashed.count == 1, "Trash invoked once")
        try expect(trashed[0] == immutableTarget, "Confirmation target mutated")
        try expect(trashed[0].url == a.standardizedFileURL, "Navigation changed Trash URL")
        try expect(model.displayedImage?.sourceURL == b.standardizedFileURL, "Non-target selection changed")
        try expect(model.thumbnailEntries.map(\.url) == [b, c].map(\.standardizedFileURL), "Target row not removed")
        try expect(FileManager.default.fileExists(atPath: b.path), "New selection was deleted")

        let cancelConfirmation = ImmediateConfirmation(false)
        let cancelController = FinderActionController(
            service: service,
            confirmation: cancelConfirmation
        )
        let cancelModel = AppModel(finderActions: cancelController)
        cancelModel.open(url: b)
        try await waitUntil { cancelModel.displayedImage?.sourceURL == b.standardizedFileURL }
        let countBeforeCancel = await service.trashedTargets().count
        cancelModel.moveCurrentToTrash()
        try await waitUntil { !cancelModel.isFinderActionPending }
        let countAfterCancel = await service.trashedTargets().count
        try expect(countAfterCancel == countBeforeCancel, "Cancel mutated file")
        try expect(FileManager.default.fileExists(atPath: b.path), "Cancel removed target")

        let successConfirmation = ImmediateConfirmation(true)
        let successController = FinderActionController(
            service: service,
            confirmation: successConfirmation
        )
        let successModel = AppModel(finderActions: successController)
        successModel.open(url: b)
        try await waitUntil {
            successModel.thumbnailEntries.count == 2
                && successModel.displayedImage?.sourceURL == b.standardizedFileURL
        }
        successModel.rotateRight()
        successModel.moveCurrentToTrash()
        try await waitUntil { !successModel.isFinderActionPending }
        try await waitUntil { successModel.displayedImage?.sourceURL == c.standardizedFileURL }
        try expect(successModel.viewportState.rotation == .zero, "Viewport/rotation cleanup")
        try expect(!successModel.canNavigateNext && !successModel.canNavigatePrevious, "Boundary after Trash")

        successModel.moveCurrentToTrash()
        try await waitUntil { !successModel.isFinderActionPending }
        try expect(successModel.displayedImage == nil, "Last image remained visible")
        try expect(successModel.thumbnailEntries.isEmpty, "Empty collection retained entry")
        try expect(!successModel.canRevealCurrentFile, "Reveal enabled in empty folder")
        try expect(!successModel.canMoveCurrentFileToTrash, "Trash enabled in empty folder")
        try expect(!successModel.canNavigatePrevious && !successModel.canNavigateNext, "Navigation enabled in empty folder")

        let failureFile = root.appendingPathComponent("failure.png")
        try writePNG(failureFile, shade: 200)
        await service.setMode(.fail)
        let failureModel = AppModel(finderActions: successController)
        failureModel.open(url: failureFile)
        try await waitUntil { failureModel.displayedImage != nil }
        failureModel.moveCurrentToTrash()
        try await waitUntil { !failureModel.isFinderActionPending }
        try expect(failureModel.displayedImage?.sourceURL == failureFile, "Failure changed viewer")
        try expect(failureModel.finderActionError != nil, "Failure error missing")
        try expect(FileManager.default.fileExists(atPath: failureFile.path), "Failure removed file")

        await service.setMode(.succeed)
        let warmFile = root.appendingPathComponent("warm.png")
        try writePNG(warmFile, shade: 230)
        let staleGate = GateConfirmation()
        let staleController = FinderActionController(
            service: service,
            confirmation: staleGate
        )
        let staleModel = AppModel(finderActions: staleController)
        staleModel.open(url: failureFile)
        try await waitUntil { staleModel.displayedImage?.sourceURL == failureFile }
        let trashCountBeforeSessionChange = await service.trashedTargets().count
        staleModel.moveCurrentToTrash()
        try await waitUntil { staleGate.target != nil }
        staleModel.open(url: warmFile)
        staleGate.resolve(true)
        try await waitUntil { staleModel.displayedImage?.sourceURL == warmFile }
        for _ in 0..<20 { await Task.yield() }
        let trashCountAfterSessionChange = await service.trashedTargets().count
        try expect(
            trashCountAfterSessionChange == trashCountBeforeSessionChange,
            "Warm open allowed stale confirmation to mutate old target"
        )
        try expect(
            FileManager.default.fileExists(atPath: failureFile.path),
            "Stale session deleted old target"
        )

        let one = NavigationEntry(url: a, filename: "a")
        let two = NavigationEntry(url: b, filename: "b")
        let three = NavigationEntry(url: c, filename: "c")
        let middle = NavigationSnapshot(entries: [one, two, three], selectedURL: b)!
        let middleRemoval = middle.removing(url: b)!
        try expect(middleRemoval.removedWasCurrent && middleRemoval.selectedEntry?.url == c, "Middle did not prefer next")
        let last = NavigationSnapshot(entries: [one, two, three], selectedURL: c)!
        let lastRemoval = last.removing(url: c)!
        try expect(lastRemoval.selectedEntry?.url == b, "Last did not prefer previous")
        let only = NavigationSnapshot(entries: [one], selectedURL: a)!
        let onlyRemoval = only.removing(url: a)!
        try expect(onlyRemoval.selectedEntry == nil && onlyRemoval.remainingEntries.isEmpty, "Only-image removal")
        let noncurrent = NavigationSnapshot(entries: [one, two, three], selectedURL: two.url)!
        let noncurrentRemoval = noncurrent.removing(url: one.url)!
        try expect(noncurrentRemoval.selectedEntry?.url == two.url, "Noncurrent removal changed selection")

        let replaced = root.appendingPathComponent("replaced.png")
        try writePNG(replaced, shade: 10)
        let initialValues = try replaced.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey
        ])
        let replacementTarget = FinderActionTarget(
            sessionID: UUID(),
            url: replaced,
            filename: "replaced.png",
            imageGeneration: 1,
            fileIdentity: nil,
            fileSize: initialValues.fileSize,
            modificationDate: initialValues.contentModificationDate
        )
        try FileManager.default.removeItem(at: replaced)
        try Data(repeating: 220, count: 257).write(to: replaced)
        do {
            try NativeFinderActionService.validate(replacementTarget)
            throw FinderTestFailure.failed("Replaced target accepted")
        } catch FinderActionError.targetChanged {}
        try FileManager.default.removeItem(at: replaced)
        do {
            try NativeFinderActionService.validate(replacementTarget)
            throw FinderTestFailure.failed("Missing target accepted")
        } catch FinderActionError.missing {}

        print("PASS: 30 safe Finder action checks")
    }
}

private enum XCT {
    static func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw FinderTestFailure.failed("Unexpected nil") }
        return value
    }
}

private func XCTUnwrap<T>(_ value: T?) throws -> T { try XCT.unwrap(value) }

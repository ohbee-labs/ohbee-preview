import Foundation

enum TestFailure: Error {
    case expectation(String)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure.expectation(message) }
}

private actor DelayedCommitRecorder {
    private(set) var committedURL: URL?
    private(set) var cancellationCount = 0
    private(set) var staleRejectionCount = 0

    func commit(_ url: URL) {
        committedURL = url
    }

    func cancelled() {
        cancellationCount += 1
    }

    func rejectedStale() {
        staleRejectionCount += 1
    }
}

private func testDelayedLatestRequestWins() async throws {
    let coordinator = OpenRequestCoordinator()
    let recorder = DelayedCommitRecorder()
    let olderURL = URL(fileURLWithPath: "/tmp/older.png")
    let newerURL = URL(fileURLWithPath: "/tmp/newer.png")
    let older = await coordinator.begin(url: olderURL)

    let olderTask = Task {
        do {
            try await Task.sleep(for: .milliseconds(150))
            if await coordinator.isCurrent(older) {
                await recorder.commit(olderURL)
            } else {
                await recorder.rejectedStale()
            }
        } catch is CancellationError {
            await recorder.cancelled()
        }
    }

    let newer = await coordinator.begin(url: newerURL)
    olderTask.cancel()
    let newerTask = Task {
        try await Task.sleep(for: .milliseconds(10))
        if await coordinator.isCurrent(newer) {
            await recorder.commit(newerURL)
        } else {
            await recorder.rejectedStale()
        }
    }

    _ = await olderTask.result
    _ = try await newerTask.value
    let committedURL = await recorder.committedURL
    let cancellationCount = await recorder.cancellationCount
    try expect(
        committedURL == newerURL,
        "Latest delayed request did not win"
    )
    try expect(
        cancellationCount == 1,
        "Obsolete delayed request was not cancelled"
    )
}

private func testFolderNavigation() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohbee-navigation-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let selected = root.appendingPathComponent("image2.JPG")
    let supported = [
        root.appendingPathComponent("image10.jpg"),
        root.appendingPathComponent("image1.png"),
        selected
    ]
    for url in supported {
        try Data([0]).write(to: url)
    }
    try Data([0]).write(to: root.appendingPathComponent(".hidden.jpg"))
    try Data([0]).write(to: root.appendingPathComponent("notes.txt"))

    let childFolder = root.appendingPathComponent("child")
    try FileManager.default.createDirectory(at: childFolder, withIntermediateDirectories: false)
    try Data([0]).write(to: childFolder.appendingPathComponent("nested.jpg"))

    try FileManager.default.createSymbolicLink(
        at: root.appendingPathComponent("duplicate.jpg"),
        withDestinationURL: selected
    )

    let result = try await FolderNavigationService.discover(
        folderURL: root,
        selectedURL: selected
    )
    try expect(result.eligibleImageCount == 3, "Filtering or duplicate prevention failed")
    guard var snapshot = result.snapshot else {
        throw TestFailure.expectation("Current image was not matched")
    }
    try expect(
        snapshot.entries.map(\.filename) == ["image1.png", "image2.JPG", "image10.jpg"],
        "Natural filename sorting failed"
    )
    try expect(snapshot.current.url == selected.standardizedFileURL, "Selection moved")
    try expect(snapshot.position == 2, "Matched position was incorrect")

    let previous = snapshot.selectPrevious()
    try expect(previous?.filename == "image1.png", "Previous navigation failed")
    try expect(!snapshot.canNavigatePrevious, "First-image boundary failed")
    try expect(snapshot.selectPrevious() == nil, "Previous wrapped at first image")

    _ = snapshot.selectNext()
    let next = snapshot.selectNext()
    try expect(next?.filename == "image10.jpg", "Next navigation failed")
    try expect(!snapshot.canNavigateNext, "Last-image boundary failed")
    try expect(snapshot.selectNext() == nil, "Next wrapped at last image")

    let unmatched = NavigationSnapshot(
        entries: snapshot.entries,
        selectedURL: root.appendingPathComponent("missing.jpg")
    )
    try expect(unmatched == nil, "Unmatched image created a folder session")
}

@main
enum Stage2CoreCLITests {
    static func main() async throws {
        var authorization = ImageSessionState(
            selectedURL: URL(fileURLWithPath: "/tmp/folder/image.png")
        )
        authorization.beginAssessment()
        try expect(authorization.authorization == .assessing, "Assessment did not start")
        authorization.automaticAccessFailed()
        try expect(
            authorization.authorization == .actionAvailable,
            "Folder fallback action missing"
        )
        authorization.presentPicker()
        authorization.cancelPicker()
        try expect(
            authorization.authorization == .declinedForImageSession,
            "Folder-picker cancellation was not retained"
        )

        var memory = SessionAuthorizationMemory()
        let folder = URL(fileURLWithPath: "/tmp/folder")
        let image = folder.appendingPathComponent("image.png")
        memory.authorize(folderURL: folder)
        memory.decline(imageURL: image)
        try expect(memory.isAuthorized(folderURL: folder), "Folder authorization missing")
        try expect(memory.wasDeclined(imageURL: image), "Decline state was not retained")
        try expect(
            memory.wasDeclined(imageURL: image),
            "Repeated permission check changed decline state"
        )

        for fileExtension in [
            "jpg", "JPE", "JPEG", "png", "HEIC", "heif", "gif", "tif", "TIFF"
        ] {
            try expect(
                SupportedImageFormat.supports(
                    URL(fileURLWithPath: "/tmp/image.\(fileExtension)")
                ),
                "Supported format rejected: \(fileExtension)"
            )
        }
        try expect(
            !SupportedImageFormat.supports(URL(fileURLWithPath: "/tmp/readme.txt")),
            "Unsupported format accepted"
        )

        let urls = [
            URL(fileURLWithPath: "/tmp/readme.txt"),
            URL(fileURLWithPath: "/tmp/first.png"),
            URL(fileURLWithPath: "/tmp/second.jpg")
        ]
        try expect(
            OpenURLPolicy.firstSupported(in: urls) == urls[1],
            "Finder URL policy did not choose the first supported URL"
        )

        try await testFolderNavigation()
        try await testDelayedLatestRequestWins()
        print("PASS: 19 Folder Navigation MVP core checks")
    }
}

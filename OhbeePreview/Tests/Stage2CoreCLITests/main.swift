import Foundation

enum TestFailure: Error {
    case expectation(String)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure.expectation(message) }
}

@main
enum Stage2CoreCLITests {
    static func main() async throws {
        let coordinator = OpenRequestCoordinator()
        let older = await coordinator.begin(url: URL(fileURLWithPath: "/tmp/older.png"))
        let newer = await coordinator.begin(url: URL(fileURLWithPath: "/tmp/newer.png"))
        let olderIsCurrent = await coordinator.isCurrent(older)
        let newerIsCurrent = await coordinator.isCurrent(newer)
        try expect(!olderIsCurrent, "Older request remained current")
        try expect(newerIsCurrent, "Newer request was not current")

        var state = ImageSessionState(
            selectedURL: URL(fileURLWithPath: "/tmp/folder/image.png")
        )
        state.beginAssessment()
        try expect(state.authorization == .assessing, "Assessment did not start")
        state.automaticAccessFailed()
        try expect(state.authorization == .actionAvailable, "Fallback action missing")
        state.presentPicker()
        state.cancelPicker()
        try expect(
            state.authorization == .declinedForImageSession,
            "Picker cancellation was not retained"
        )

        var memory = SessionAuthorizationMemory()
        let folder = URL(fileURLWithPath: "/tmp/folder")
        memory.authorize(folderURL: folder)
        try expect(memory.isAuthorized(folderURL: folder), "Folder authorization missing")

        for fileExtension in ["jpg", "JPEG", "png", "HEIC", "heif", "gif", "tif", "TIFF"] {
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
        print("PASS: 7 Stage 2 core checks")
    }
}

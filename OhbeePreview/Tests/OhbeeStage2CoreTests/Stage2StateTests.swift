import Foundation
import OhbeeStage2Core
import XCTest

final class Stage2StateTests: XCTestCase {
    func testNewerOpenRequestWins() async {
        let coordinator = OpenRequestCoordinator()
        let older = await coordinator.begin(url: URL(fileURLWithPath: "/tmp/older.png"))
        let newer = await coordinator.begin(url: URL(fileURLWithPath: "/tmp/newer.png"))

        let olderIsCurrent = await coordinator.isCurrent(older)
        let newerIsCurrent = await coordinator.isCurrent(newer)
        XCTAssertFalse(olderIsCurrent)
        XCTAssertTrue(newerIsCurrent)
    }

    func testAuthorizationTransitions() {
        let image = URL(fileURLWithPath: "/tmp/folder/image.png")
        var state = ImageSessionState(selectedURL: image)

        state.beginAssessment()
        XCTAssertEqual(state.authorization, .assessing)
        state.automaticAccessFailed()
        XCTAssertEqual(state.authorization, .actionAvailable)
        state.presentPicker()
        XCTAssertEqual(state.authorization, .pickerPresented)
        state.cancelPicker()
        XCTAssertEqual(state.authorization, .declinedForImageSession)
    }

    func testSessionAuthorizationMemory() {
        let folder = URL(fileURLWithPath: "/tmp/folder")
        let image = folder.appendingPathComponent("image.png")
        var memory = SessionAuthorizationMemory()

        XCTAssertFalse(memory.isAuthorized(folderURL: folder))
        memory.authorize(folderURL: folder)
        XCTAssertTrue(memory.isAuthorized(folderURL: folder))
        XCTAssertFalse(memory.wasDeclined(imageURL: image))
        memory.decline(imageURL: image)
        XCTAssertTrue(memory.wasDeclined(imageURL: image))
    }

    func testAutomaticAccessSuccess() {
        var state = ImageSessionState(
            selectedURL: URL(fileURLWithPath: "/tmp/folder/image.png")
        )
        state.beginAssessment()
        state.automaticAccessSucceeded()
        XCTAssertEqual(state.authorization, .automaticAccessAvailable)
    }

    func testSupportedImageFormatsAreCaseInsensitive() {
        for fileExtension in [
            "jpg", "JPE", "JPEG", "png", "HEIC", "heif", "gif", "tif", "TIFF"
        ] {
            XCTAssertTrue(
                SupportedImageFormat.supports(
                    URL(fileURLWithPath: "/tmp/image.\(fileExtension)")
                )
            )
        }
        XCTAssertFalse(
            SupportedImageFormat.supports(URL(fileURLWithPath: "/tmp/readme.txt"))
        )
    }

    func testOpenURLPolicySelectsFirstSupportedURL() {
        let urls = [
            URL(fileURLWithPath: "/tmp/readme.txt"),
            URL(fileURLWithPath: "/tmp/first.png"),
            URL(fileURLWithPath: "/tmp/second.jpg")
        ]
        XCTAssertEqual(OpenURLPolicy.firstSupported(in: urls), urls[1])
    }

    func testOpenURLPolicyRejectsUnsupportedURLs() {
        XCTAssertNil(
            OpenURLPolicy.firstSupported(
                in: [
                    URL(fileURLWithPath: "/tmp/readme.txt"),
                    URL(fileURLWithPath: "/tmp/movie.mov")
                ]
            )
        )
    }
}

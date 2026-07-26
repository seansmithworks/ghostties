import XCTest
@testable import Ghostty

final class SessionTitleSanitizerTests: XCTestCase {

    func testNormalAgentTitle() {
        let result = SessionTitleSanitizer.sanitize(
            title: "Refactoring the auth module",
            currentName: "Session 1"
        )
        XCTAssertEqual(result, "Refactoring the auth module")
    }

    func testEmptyTitleRejected() {
        XCTAssertNil(SessionTitleSanitizer.sanitize(title: "", currentName: "Session 1"))
    }

    func testWhitespaceOnlyTitleRejected() {
        XCTAssertNil(SessionTitleSanitizer.sanitize(title: "   \n\t  ", currentName: "Session 1"))
    }

    func testBarePathRejected() {
        XCTAssertNil(SessionTitleSanitizer.sanitize(
            title: "/Users/sean/Code/ghostties",
            currentName: "Session 1"
        ))
        XCTAssertNil(SessionTitleSanitizer.sanitize(
            title: "~/Code/ghostties",
            currentName: "Session 1"
        ))
    }

    func testBareShellNameRejected() {
        XCTAssertNil(SessionTitleSanitizer.sanitize(title: "claude", currentName: "Session 1"))
        XCTAssertNil(SessionTitleSanitizer.sanitize(title: "zsh", currentName: "Session 1"))
        XCTAssertNil(SessionTitleSanitizer.sanitize(title: "-zsh", currentName: "Session 1"))
        XCTAssertNil(SessionTitleSanitizer.sanitize(title: "bash", currentName: "Session 1"))
    }

    func testProjectDirectoryNameRejected() {
        XCTAssertNil(SessionTitleSanitizer.sanitize(
            title: "ghostties",
            currentName: "Session 1",
            projectDirectoryName: "ghostties"
        ))
    }

    func testShellPromptRejected() {
        XCTAssertNil(SessionTitleSanitizer.sanitize(
            title: "sean@Seans-MacBook-Pro ghostties %",
            currentName: "Session 1"
        ))
        XCTAssertNil(SessionTitleSanitizer.sanitize(
            title: "user@host:~/project$",
            currentName: "Session 1"
        ))
    }

    func testOverlongTitleTruncatesOnWordBoundary() {
        let title = "Implementing the new session name sync feature across the whole sidebar and coordinator layer"
        let result = SessionTitleSanitizer.sanitize(title: title, currentName: "Session 1")
        XCTAssertNotNil(result)
        guard let result else { return }
        XCTAssertLessThanOrEqual(result.count, SessionTitleSanitizer.maxLength)
        XCTAssertFalse(result.hasSuffix(" "))
        // Must not cut mid-word — the truncated result should be a prefix of
        // the original title up to (and not including) a space boundary.
        XCTAssertTrue(title.hasPrefix(result))
        XCTAssertFalse(title.hasPrefix(result + "x")) // sanity: result isn't the whole title
    }

    func testTitleIdenticalToCurrentNameWritesNothing() {
        XCTAssertNil(SessionTitleSanitizer.sanitize(
            title: "Refactoring the auth module",
            currentName: "Refactoring the auth module"
        ))
    }
}

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
        // The truncation must actually have happened (result isn't the whole
        // title) AND must have landed on a real word boundary — the character
        // immediately following the result in the original title is a space,
        // not a continuation of the same word. (The previous version of this
        // assertion, `!title.hasPrefix(result + "x")`, passed trivially
        // because "x" never appears in the original text at that position —
        // it wasn't actually checking the boundary.)
        XCTAssertLessThan(result.count, title.count, "sanity: result isn't the whole title")
        let boundaryIndex = title.index(title.startIndex, offsetBy: result.count)
        XCTAssertEqual(title[boundaryIndex], " ", "truncation must land exactly on a space boundary, not mid-word")
    }

    func testTitleIdenticalToCurrentNameWritesNothing() {
        XCTAssertNil(SessionTitleSanitizer.sanitize(
            title: "Refactoring the auth module",
            currentName: "Refactoring the auth module"
        ))
    }

    // MARK: - FIX 2: character filtering

    func testEmbeddedNewlineIsStripped() {
        let result = SessionTitleSanitizer.sanitize(
            title: "Refactoring\nrm -rf /",
            currentName: "Session 1"
        )
        XCTAssertEqual(result, "Refactoringrm -rf /")
    }

    func testCarriageReturnIsStripped() {
        let result = SessionTitleSanitizer.sanitize(
            title: "Safe title\rEVIL",
            currentName: "Session 1"
        )
        XCTAssertEqual(result, "Safe titleEVIL")
    }

    func testAnsiEscapeBytesAreStripped() {
        let result = SessionTitleSanitizer.sanitize(
            title: "\u{1B}[31mRed title\u{1B}[0m",
            currentName: "Session 1"
        )
        XCTAssertEqual(result, "[31mRed title[0m")
    }

    func testBelBackspaceNulAreStripped() {
        let result = SessionTitleSanitizer.sanitize(
            title: "Title\u{07}\u{08}\u{00}x",
            currentName: "Session 1"
        )
        XCTAssertEqual(result, "Titlex")
    }

    func testRtlOverrideIsStripped() {
        let result = SessionTitleSanitizer.sanitize(
            title: "Deleting \u{202E}txt.exe",
            currentName: "Session 1"
        )
        XCTAssertEqual(result, "Deleting txt.exe")
    }

    func testZeroWidthSpacesAreStripped() {
        let padding = String(repeating: "\u{200B}", count: 100)
        let result = SessionTitleSanitizer.sanitize(
            title: "A" + padding + "B",
            currentName: "Session 1"
        )
        XCTAssertEqual(result, "AB")
    }

    func testPlaceholderGhostTitleRejected() {
        XCTAssertNil(SessionTitleSanitizer.sanitize(title: "👻", currentName: "Session 1"))
    }

    func testPunctuationOnlyTitleRejected() {
        XCTAssertNil(SessionTitleSanitizer.sanitize(title: "...", currentName: "Session 1"))
        XCTAssertNil(SessionTitleSanitizer.sanitize(title: "!!!", currentName: "Session 1"))
    }

    // MARK: - FIX 3: percent-terminated progress reports must pass

    func testPercentTerminatedProgressReportAccepted() {
        let result = SessionTitleSanitizer.sanitize(
            title: "Compacting conversation 45%",
            currentName: "Session 1"
        )
        XCTAssertEqual(result, "Compacting conversation 45%")
    }

    // MARK: - FIX 6: bare-path rule tightening

    func testBarePathWithSpacesInDirectoryNameRejected() {
        XCTAssertNil(SessionTitleSanitizer.sanitize(
            title: "/Users/sean/My Code/thing",
            currentName: "Session 1"
        ))
        XCTAssertNil(SessionTitleSanitizer.sanitize(
            title: "~/Code/my project",
            currentName: "Session 1"
        ))
    }
}

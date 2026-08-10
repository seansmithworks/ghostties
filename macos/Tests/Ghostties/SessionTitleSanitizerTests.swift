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

    // MARK: - Directory-name-echo rejection (title is just the dir name plus
    // boilerplate, e.g. Claude Code's "<repo> | Claude Code" terminal title)

    func testProjectDirectoryNamePlusClaudeCodeSuffixRejected() {
        // The reported bug: Claude Code emits "<repo> | Claude Code" and the
        // old exact-equality check let it straight through.
        XCTAssertNil(SessionTitleSanitizer.sanitize(
            title: "invented-project | Claude Code",
            currentName: "Session 1",
            projectDirectoryName: "invented-project"
        ))
    }

    func testProjectDirectoryNameWithEmDashShellSuffixRejected() {
        XCTAssertNil(SessionTitleSanitizer.sanitize(
            title: "invented-project — zsh",
            currentName: "Session 1",
            projectDirectoryName: "invented-project"
        ))
    }

    func testProjectDirectoryNameWithSpacedHyphenInformativeSuffixKept() {
        // A spaced hyphen introduces a genuinely informative segment — must
        // survive, and the full title (not just the surviving segment) is
        // what gets returned.
        let result = SessionTitleSanitizer.sanitize(
            title: "invented-project - fix the sidebar",
            currentName: "Session 1",
            projectDirectoryName: "invented-project"
        )
        XCTAssertEqual(result, "invented-project - fix the sidebar")
    }

    func testInformativeTitleMentioningUnrelatedDirNameKept() {
        XCTAssertEqual(
            SessionTitleSanitizer.sanitize(
                title: "Refactoring the auth module",
                currentName: "Session 1",
                projectDirectoryName: "invented-project"
            ),
            "Refactoring the auth module"
        )
    }

    func testHyphenatedDirectoryNameWithNoSeparatorKept() {
        // Regression guard: a hyphenated project directory name that merely
        // appears as a prefix, with no separator, must not be shredded into
        // fragments by a bare (unspaced) hyphen — the whole string is one
        // segment and it isn't equal to the bare directory name, so it's
        // informative and must be kept.
        XCTAssertEqual(
            SessionTitleSanitizer.sanitize(
                title: "invented-hyphenated auth refactor",
                currentName: "Session 1",
                projectDirectoryName: "invented-hyphenated"
            ),
            "invented-hyphenated auth refactor"
        )
    }

    func testHyphenatedDirectoryNamePlusClaudeCodeSuffixRejected() {
        // Same shape as the reported bug, but with a project directory name
        // that itself contains bare hyphens — proves splitting on " - "
        // (spaced) rather than "-" (bare) doesn't cause a false negative.
        XCTAssertNil(SessionTitleSanitizer.sanitize(
            title: "invented-hyphenated-project | Claude Code",
            currentName: "Session 1",
            projectDirectoryName: "invented-hyphenated-project"
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

    // MARK: - FIX 3: digit-before-suffix no longer exempts "$" or "#", and a
    // `user@host` token is rejected regardless of trailing character.

    func testDigitPrecededDollarPromptStillRejected() {
        // bash's default `\u@\h:\w\$` prompt, with a directory name that
        // happens to end in a digit — this must NOT be exempted by a
        // trailing-digit check.
        XCTAssertNil(SessionTitleSanitizer.sanitize(
            title: "sean@mbp:~/Code/ghostties2$",
            currentName: "Session 1"
        ))
    }

    func testDigitPrecededHashPromptStillRejected() {
        // A root prompt on a numbered host — "server1", "node2", "box3" are
        // ubiquitous hostnames.
        XCTAssertNil(SessionTitleSanitizer.sanitize(
            title: "root@server1#",
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

    func testEmbeddedNewlineIsRejected() {
        // A title with an embedded newline isn't a meaningful session name —
        // must be rejected outright, not spliced into "Refactoringrm -rf /".
        XCTAssertNil(SessionTitleSanitizer.sanitize(
            title: "Refactoring\nrm -rf /",
            currentName: "Session 1"
        ))
    }

    func testCarriageReturnIsRejected() {
        XCTAssertNil(SessionTitleSanitizer.sanitize(
            title: "Safe title\rEVIL",
            currentName: "Session 1"
        ))
    }

    func testAnsiEscapeSequenceIsRejected() {
        // Splicing out just the ESC byte would leave the visible garbage
        // "[31mRed title[0m" — worse than the original unsanitized string.
        // Must reject the whole title instead.
        XCTAssertNil(SessionTitleSanitizer.sanitize(
            title: "\u{1B}[31mRed title\u{1B}[0m",
            currentName: "Session 1"
        ))
    }

    func testBelBackspaceNulAreRejected() {
        XCTAssertNil(SessionTitleSanitizer.sanitize(
            title: "Title\u{07}\u{08}\u{00}x",
            currentName: "Session 1"
        ))
    }

    func testZwjEmojiSequencesSurviveIntact() {
        // U+200D (ZERO WIDTH JOINER) must NOT be blocklisted — it's what
        // stitches multi-codepoint emoji into one glyph.
        XCTAssertEqual(
            SessionTitleSanitizer.sanitize(title: "👨‍💻 pairing session", currentName: "Session 1"),
            "👨‍💻 pairing session"
        )
        XCTAssertEqual(
            SessionTitleSanitizer.sanitize(title: "👨‍👩‍👧‍👦 family review", currentName: "Session 1"),
            "👨‍👩‍👧‍👦 family review"
        )
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

import Testing
import GhosttiesCore

/// Variant G Pass B: `footerOperators`'s matrix — the pure decision the
/// contextual operator footer strip reads, tested directly. Each test
/// asserts against `SessionComposerCommandParser.FooterOperatorHint`, a
/// real production symbol, never a re-declared local literal.
struct SessionComposerFooterOperatorsTests {
    private typealias Hint = SessionComposerCommandParser.FooterOperatorHint

    private static let allLive = SessionComposerCommandParser.footerOperators(
        hasSelection: true,
        hasGhostRemainder: true,
        hasMultipleOptions: true,
        hasPendingChipUndo: true
    )

    private static let noneLive = SessionComposerCommandParser.footerOperators(
        hasSelection: false,
        hasGhostRemainder: false,
        hasMultipleOptions: false,
        hasPendingChipUndo: false
    )

    // MARK: - Empty list when nothing is live

    @Test func emptyWhenNothingLive() {
        #expect(Self.noneLive.isEmpty)
    }

    // MARK: - Each operator toggles independently

    @Test func openPresentOnlyWhenSelectionExists() {
        let with = SessionComposerCommandParser.footerOperators(
            hasSelection: true, hasGhostRemainder: false,
            hasMultipleOptions: false, hasPendingChipUndo: false
        )
        #expect(with.contains(Hint(glyph: "↵", label: "open")))

        let without = SessionComposerCommandParser.footerOperators(
            hasSelection: false, hasGhostRemainder: false,
            hasMultipleOptions: false, hasPendingChipUndo: false
        )
        #expect(!without.contains(Hint(glyph: "↵", label: "open")))
    }

    @Test func acceptPresentOnlyWhenGhostRemainderNonEmpty() {
        let with = SessionComposerCommandParser.footerOperators(
            hasSelection: false, hasGhostRemainder: true,
            hasMultipleOptions: false, hasPendingChipUndo: false
        )
        #expect(with.contains(Hint(glyph: "⇥", label: "accept")))

        let without = SessionComposerCommandParser.footerOperators(
            hasSelection: false, hasGhostRemainder: false,
            hasMultipleOptions: false, hasPendingChipUndo: false
        )
        #expect(!without.contains(Hint(glyph: "⇥", label: "accept")))
    }

    @Test func navigatePresentOnlyWhenMoreThanOneOption() {
        let with = SessionComposerCommandParser.footerOperators(
            hasSelection: false, hasGhostRemainder: false,
            hasMultipleOptions: true, hasPendingChipUndo: false
        )
        #expect(with.contains(Hint(glyph: "↑↓", label: "navigate")))

        let without = SessionComposerCommandParser.footerOperators(
            hasSelection: false, hasGhostRemainder: false,
            hasMultipleOptions: false, hasPendingChipUndo: false
        )
        #expect(!without.contains(Hint(glyph: "↑↓", label: "navigate")))
    }

    @Test func undoPresentOnlyWhenChipUndoPending() {
        let with = SessionComposerCommandParser.footerOperators(
            hasSelection: false, hasGhostRemainder: false,
            hasMultipleOptions: false, hasPendingChipUndo: true
        )
        #expect(with.contains(Hint(glyph: "⌘Z", label: "undo")))

        let without = SessionComposerCommandParser.footerOperators(
            hasSelection: false, hasGhostRemainder: false,
            hasMultipleOptions: false, hasPendingChipUndo: false
        )
        #expect(!without.contains(Hint(glyph: "⌘Z", label: "undo")))
    }

    // MARK: - Fixed order: open, accept, navigate, undo

    @Test func orderIsPrimaryThenAcceptThenNavigateThenUndo() {
        #expect(Self.allLive == [
            Hint(glyph: "↵", label: "open"),
            Hint(glyph: "⇥", label: "accept"),
            Hint(glyph: "↑↓", label: "navigate"),
            Hint(glyph: "⌘Z", label: "undo")
        ])
    }

    // MARK: - ⌥↵ "new worktree" does not exist

    @Test func neverIncludesOptionReturnNewWorktree() {
        for hint in Self.allLive {
            #expect(!hint.glyph.contains("⌥"))
            #expect(hint.label != "new worktree")
        }
    }

}

/// `footerSlot`'s three-way precedence matrix — the pure decision the
/// footer position's `switch` in `SessionComposerPalette.composerCard`
/// reads, tested directly so "never doubled" is provable independent of
/// SwiftUI rendering.
struct SessionComposerFooterSlotTests {
    private typealias Slot = SessionComposerCommandParser.FooterSlot
    private typealias Hint = SessionComposerCommandParser.FooterOperatorHint

    private static let sampleOperators = [Hint(glyph: "↵", label: "open")]

    @Test func newTemplateNameWinsOverAnActiveError() {
        let slot = SessionComposerCommandParser.footerSlot(
            errorMessage: "branch \"x\" not found",
            isAddingTemplate: true,
            operators: Self.sampleOperators
        )
        #expect(slot == .newTemplateName)
    }

    @Test func errorWinsOverOperatorsWhenNotAddingTemplate() {
        let slot = SessionComposerCommandParser.footerSlot(
            errorMessage: "branch \"x\" not found",
            isAddingTemplate: false,
            operators: Self.sampleOperators
        )
        #expect(slot == .error("branch \"x\" not found"))
    }

    @Test func operatorsRenderOnlyWhenNeitherErrorNorNaming() {
        let slot = SessionComposerCommandParser.footerSlot(
            errorMessage: nil,
            isAddingTemplate: false,
            operators: Self.sampleOperators
        )
        #expect(slot == .operators(Self.sampleOperators))
    }

    @Test func emptyOperatorListRendersNoStripRatherThanAnEmptyOne() {
        let slot = SessionComposerCommandParser.footerSlot(
            errorMessage: nil,
            isAddingTemplate: false,
            operators: []
        )
        #expect(slot == .none)
    }
}

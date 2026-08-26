import Testing
@testable import Ghostty

/// Step 3 (Composer UI 11 plan §3): `SessionComposerCommandParser.ghostPlaceholder`
/// is a pure function over `ResolutionLineSegments` — every test here
/// constructs `ResolutionLineSegments` directly rather than mounting a
/// view, matching the repo's usual view-test-harness gap
/// (`resolutionLineSegments`'s own doc comment).
struct SessionComposerGhostPlaceholderTests {
    private typealias Segments = SessionComposerCommandParser.ResolutionLineSegments

    // MARK: - Rule 1: real project resolved + selection

    @Test func realProjectAndSelectionRendersFullPath() {
        let segments = Segments(
            projectLabel: "Ghostties",
            isProjectClickable: true,
            branchLabel: "Default",
            branchIsError: false,
            templateLabel: "Orchestrator"
        )
        let result = SessionComposerCommandParser.ghostPlaceholder(
            segments: segments, hasSelection: true, projectsExist: true
        )
        #expect(result == "Ghostties > Default > Orchestrator")
    }

    @Test func realProjectAndSelectionOmitsBranchSegmentWhenIneligible() {
        let segments = Segments(
            projectLabel: "Ghostties",
            isProjectClickable: true,
            branchLabel: nil, // !isBranchSegmentEligible
            branchIsError: false,
            templateLabel: "Orchestrator"
        )
        let result = SessionComposerCommandParser.ghostPlaceholder(
            segments: segments, hasSelection: true, projectsExist: true
        )
        #expect(result == "Ghostties > Orchestrator")
    }

    // MARK: - Rule 2: locked and unresolvable

    @Test func lockedUnresolvableRendersProjectUnavailable() {
        let segments = Segments(
            projectLabel: "Project unavailable",
            isProjectClickable: false, // .locked
            branchLabel: nil,
            branchIsError: false,
            templateLabel: "No match"
        )
        let result = SessionComposerCommandParser.ghostPlaceholder(
            segments: segments, hasSelection: false, projectsExist: true
        )
        #expect(result == "Project unavailable")
    }

    /// Fix 9 (review): the test above constructs `Segments` as a LOCAL
    /// LITERAL (`projectLabel: "Project unavailable"`) — hand-copied from
    /// `resolutionLineSegments`'s own literal (`SessionComposerCommandParser.swift:1176`),
    /// which `ghostPlaceholder` in turn compares against a SECOND
    /// hand-copied literal (`lockedUnresolvableProjectLabel`, `:1210`).
    /// Nothing enforces the three stay in sync — this repo already burned
    /// on exactly this shape twice (`feedback_vacuous-tests-pass-green`).
    /// This test instead calls the REAL `resolutionLineSegments(...)` and
    /// feeds its ACTUAL output into `ghostPlaceholder`, so a change to
    /// EITHER literal (the one `resolutionLineSegments` emits, or the one
    /// `ghostPlaceholder` compares against) breaks the round trip.
    /// Mutant-verified: temporarily changing `resolutionLineSegments`'s
    /// `"Project unavailable"` literal (`:1176`) to `"Project MUTANT"`
    /// (leaving `ghostPlaceholder`'s comparison literal at `:1210`
    /// untouched — exactly the divergence this test exists to catch) failed
    /// with `Expectation failed: (result → "Type a project, branch, and
    /// command…") == "Project unavailable"` — the mismatched literal no
    /// longer matched `ghostPlaceholder`'s `lockedUnresolvableProjectLabel`
    /// comparison, so it silently fell through to rule 4's generic hint
    /// instead of rule 2's locked-status message. Reverted immediately
    /// after confirming the failure.
    @Test func lockedUnresolvableRoundTripsThroughTheRealResolutionLineSegments() {
        let segments = SessionComposerCommandParser.resolutionLineSegments(
            projectName: nil,
            isProjectLocked: true,
            isBranchSegmentEligible: false,
            isCreatingWorktree: false,
            typedBranchResolution: .notTyped,
            currentBranchLabel: nil,
            templateTitle: nil
        )
        let result = SessionComposerCommandParser.ghostPlaceholder(
            segments: segments, hasSelection: false, projectsExist: true
        )
        #expect(result == "Project unavailable")
    }

    // MARK: - Rule 3: zero projects exist

    @Test func zeroProjectsRendersAddProjectPrompt() {
        let segments = Segments(
            projectLabel: "Select project",
            isProjectClickable: true,
            branchLabel: nil,
            branchIsError: false,
            templateLabel: "No match"
        )
        let result = SessionComposerCommandParser.ghostPlaceholder(
            segments: segments, hasSelection: false, projectsExist: false
        )
        #expect(result == "Add a project to begin")
    }

    // MARK: - Rule 4: otherwise, generic hint

    @Test func noProjectNoSelectionRendersGenericPlaceholder() {
        let segments = Segments(
            projectLabel: "Select project",
            isProjectClickable: true,
            branchLabel: nil,
            branchIsError: false,
            templateLabel: "No match"
        )
        let result = SessionComposerCommandParser.ghostPlaceholder(
            segments: segments, hasSelection: false, projectsExist: true
        )
        #expect(result == "Type a project, branch, and command…")
    }

    /// A resolved project with NO selection (e.g. the results list is
    /// genuinely empty) also falls to rule 4 — a resolved project alone is
    /// not enough to state a destination; `hasSelection` must be true too.
    @Test func realProjectNoSelectionRendersGenericPlaceholder() {
        let segments = Segments(
            projectLabel: "Ghostties",
            isProjectClickable: true,
            branchLabel: "Default",
            branchIsError: false,
            templateLabel: "No match"
        )
        let result = SessionComposerCommandParser.ghostPlaceholder(
            segments: segments, hasSelection: false, projectsExist: true
        )
        #expect(result == "Type a project, branch, and command…")
    }

    // MARK: - Arrow-move changes the template segment

    @Test func arrowMoveChangesTemplateSegment() {
        let beforeArrow = Segments(
            projectLabel: "Ghostties",
            isProjectClickable: true,
            branchLabel: nil,
            branchIsError: false,
            templateLabel: "Orchestrator"
        )
        let afterArrow = Segments(
            projectLabel: "Ghostties",
            isProjectClickable: true,
            branchLabel: nil,
            branchIsError: false,
            templateLabel: "Cco"
        )
        let before = SessionComposerCommandParser.ghostPlaceholder(
            segments: beforeArrow, hasSelection: true, projectsExist: true
        )
        let after = SessionComposerCommandParser.ghostPlaceholder(
            segments: afterArrow, hasSelection: true, projectsExist: true
        )
        #expect(before == "Ghostties > Orchestrator")
        #expect(after == "Ghostties > Cco")
        #expect(before != after)
    }

    // MARK: - Empty-recents rest state

    /// A fresh composer with no recents still seeds `selectedIndex` to the
    /// project's default template (`onAppear`'s S5 seed) — the rest-state
    /// ghost renders the full path exactly as it would with recents
    /// present. Empty recents must not fall back to the generic hint.
    @Test func emptyRecentsRestStateStillRendersFullPath() {
        let segments = Segments(
            projectLabel: "Ghostties",
            isProjectClickable: true,
            branchLabel: "Default",
            branchIsError: false,
            templateLabel: "Default Shell" // project's default template, no recents involved
        )
        let result = SessionComposerCommandParser.ghostPlaceholder(
            segments: segments, hasSelection: true, projectsExist: true
        )
        #expect(result == "Ghostties > Default > Default Shell")
    }

    // MARK: - Critical property (acceptance criterion 4): the placeholder's
    // template segment is sourced from `segments.templateLabel` alone —
    // which is `selectedOption?.title` at the real call site
    // (`SessionComposerPalette.ghostPlaceholder`'s `templateTitle:`
    // argument to `resolutionLineSegments`), never anything else (e.g. the
    // recents-lane head, which can differ from the current selection after
    // an arrow move). Mutant-verified: temporarily changing the
    // implementation to append a hardcoded string instead of
    // `segments.templateLabel` fails this test with
    // `Expectation failed: (result → "Ghostties > main > MUTANT") == "Ghostties > main > Orchestrator"`;
    // restored immediately after confirming the failure.

    @Test func placeholderTemplateSegmentIsSourcedFromSelectedOptionAlone() {
        let segments = Segments(
            projectLabel: "Ghostties",
            isProjectClickable: true,
            branchLabel: "main",
            branchIsError: false,
            // Stands in for `selectedOption?.title` — the same value Return
            // would commit — deliberately distinct from any other template
            // name (e.g. a recents-lane head) so a wrong source is visible.
            templateLabel: "Orchestrator"
        )
        let result = SessionComposerCommandParser.ghostPlaceholder(
            segments: segments, hasSelection: true, projectsExist: true
        )
        #expect(result == "Ghostties > main > Orchestrator")
    }
}

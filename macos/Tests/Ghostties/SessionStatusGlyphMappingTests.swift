import Testing
@testable import Ghostty

/// Pure mapping coverage for `SessionIndicatorState.statusGlyphKind`
/// (BACKLOG J, K — pattern D "type is the icon" replaces the ghost as a
/// session row's status signal). Names the real production symbol, not a
/// re-declared local: flip any case in `statusGlyphKind` and one of these
/// goes red.
struct SessionStatusGlyphMappingTests {

    @Test func processingReadsAsWorking() {
        #expect(SessionIndicatorState.processing.statusGlyphKind == .working)
    }

    @Test func longRunningReadsAsWorking() {
        #expect(SessionIndicatorState.longRunning.statusGlyphKind == .working)
    }

    @Test func waitingReadsAsDone() {
        // `.waiting` is the fallback SessionCoordinator returns when there's
        // no observed evidence either way, not confirmed work — it must not
        // spin. If `statusGlyphKind` regresses `.waiting` back to `.working`,
        // this assertion is the one that goes red.
        #expect(SessionIndicatorState.waiting.statusGlyphKind == .done)
    }

    @Test func needsAttentionReadsAsNeedsInput() {
        #expect(SessionIndicatorState.needsAttention.statusGlyphKind == .needsInput)
    }

    @Test func idleReadsAsDone() {
        #expect(SessionIndicatorState.idle.statusGlyphKind == .done)
    }

    @Test func errorReadsAsError() {
        #expect(SessionIndicatorState.error.statusGlyphKind == .error)
    }

    @Test func inactiveReadsAsStopped() {
        #expect(SessionIndicatorState.inactive.statusGlyphKind == .stopped)
    }

    // MARK: - Every case is covered, none collide with a wrong kind

    @Test func allSevenStatesMapToExactlyOneOfFiveKinds() {
        let mapping: [(SessionIndicatorState, SessionStatusGlyphKind)] = [
            (.processing, .working),
            (.longRunning, .working),
            (.waiting, .done),
            (.needsAttention, .needsInput),
            (.idle, .done),
            (.error, .error),
            (.inactive, .stopped),
        ]
        for (state, expectedKind) in mapping {
            #expect(state.statusGlyphKind == expectedKind)
        }
    }

    // MARK: - Spoken status

    @Test func everyGlyphKindHasANonEmptySpokenStatus() {
        let kinds: [SessionStatusGlyphKind] = [.working, .needsInput, .done, .error, .stopped]
        for kind in kinds {
            #expect(!kind.spokenStatus.isEmpty)
        }
    }

    @Test func waitingAndIdleSpeakTheSameStatus() {
        // Both collapse to `.done` — a silent fallback and a confirmed idle
        // session must not be distinguishable to VoiceOver, since neither
        // is blocked on the user.
        #expect(SessionIndicatorState.waiting.statusGlyphKind.spokenStatus
                == SessionIndicatorState.idle.statusGlyphKind.spokenStatus)
    }

    // MARK: - Trailing slot draws type glyphs, not a ghost (2026-10-04)

    @Test func needsInputRowDrawsAQuestionMark() {
        // The expanded row's trailing slot is `SessionStatusGlyph`, which
        // draws `kind.symbol`. A ghost-for-every-row regression has no symbol.
        #expect(SessionIndicatorState.needsAttention.statusGlyphKind.symbol == "?")
    }

    @Test func idleWaitingAndErrorDrawTheirOwnSymbols() {
        #expect(SessionIndicatorState.idle.statusGlyphKind.symbol == "✓")
        #expect(SessionIndicatorState.waiting.statusGlyphKind.symbol == "✓")
        #expect(SessionIndicatorState.error.statusGlyphKind.symbol == "✕")
    }

    @Test func workingIsDrawnSpinnerAndStoppedIsEmpty() {
        #expect(SessionIndicatorState.processing.statusGlyphKind.symbol == nil)
        #expect(SessionIndicatorState.inactive.statusGlyphKind.symbol == nil)
        #expect(!SpinnerDotFrame.litDots.isEmpty)
    }
}

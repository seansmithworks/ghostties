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

    @Test func waitingReadsAsWorking() {
        #expect(SessionIndicatorState.waiting.statusGlyphKind == .working)
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
            (.waiting, .working),
            (.needsAttention, .needsInput),
            (.idle, .done),
            (.error, .error),
            (.inactive, .stopped),
        ]
        for (state, expectedKind) in mapping {
            #expect(state.statusGlyphKind == expectedKind)
        }
    }
}

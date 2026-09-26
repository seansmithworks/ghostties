import Foundation
import Testing
@testable import Ghostty

/// Regression coverage for Flow 01 (sidebar-presence): the collapsed rail
/// mode and the toggle cycle that reaches it. See
/// `docs/design/sidebar-presence/flow-01-sidebar-presence.md`.
struct SidebarPresenceTests {

    // MARK: - Toggle Cycle Order

    /// Decision 1 (spec): the toggle cycles `pinned → collapsed → closed →
    /// pinned`. Extracted as a static function (`nextSidebarMode(after:)`,
    /// same pattern as `newSessionOpensComposer(in:)`) so the cycle order is
    /// covered directly rather than only through full UI interaction.
    @Test func toggleCyclesPinnedToCollapsedToClosedToPinned() {
        #expect(WorkspaceViewContainer.nextSidebarMode(after: .pinned) == .collapsed)
        #expect(WorkspaceViewContainer.nextSidebarMode(after: .collapsed) == .closed)
        #expect(WorkspaceViewContainer.nextSidebarMode(after: .closed) == .pinned)
    }

    /// Overlay isn't part of the persisted-width cycle — it's a transient
    /// hover state — so the toggle promotes it straight to pinned, same
    /// behavior as before Flow 01 added the rail.
    @Test func toggleFromOverlayPromotesToPinned() {
        #expect(WorkspaceViewContainer.nextSidebarMode(after: .overlay) == .pinned)
    }

    /// A full lap of the cycle starting from any mode must return to that
    /// mode within the three persisted-width steps (pinned/collapsed/closed),
    /// proving there's no dead end or skip.
    @Test func fullCycleReturnsToStartWithinThreeSteps() {
        for start: SidebarMode in [.pinned, .collapsed, .closed] {
            var mode = start
            for _ in 0..<3 {
                mode = WorkspaceViewContainer.nextSidebarMode(after: mode)
            }
            #expect(mode == start)
        }
    }
}

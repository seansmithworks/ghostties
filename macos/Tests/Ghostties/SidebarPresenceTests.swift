import Foundation
import Testing
@testable import Ghostty

/// Regression coverage for Flow 01 (sidebar-presence): the collapsed rail
/// mode and the toggle cycle that reaches it. See
/// `docs/design/sidebar-presence/flow-01-sidebar-presence.md`.
struct SidebarPresenceTests {

    // MARK: - Toggle Cycle Order

    /// Sean's review: the toggle flips full width ↔ rail — `pinned ↔
    /// collapsed` — instead of walking all the way to fully closed.
    /// Extracted as a static function (`nextSidebarMode(after:)`, same
    /// pattern as `newSessionOpensComposer(in:)`) so the cycle order is
    /// covered directly rather than only through full UI interaction.
    @Test func toggleFlipsPinnedToCollapsed() {
        #expect(WorkspaceViewContainer.nextSidebarMode(after: .pinned) == .collapsed)
    }

    @Test func toggleFlipsCollapsedToPinned() {
        #expect(WorkspaceViewContainer.nextSidebarMode(after: .collapsed) == .pinned)
    }

    /// `.closed` is left in the model (persistence, the hot zone, and the
    /// overlay reveal all still function) but is no longer reachable from
    /// the toggle — a persisted `closed` state (raw value 1) must still
    /// load and, if the toggle somehow fires from it, land on `.pinned`
    /// rather than dead-ending or cycling back into `.closed`.
    @Test func toggleFromClosedGoesToPinned() {
        #expect(WorkspaceViewContainer.nextSidebarMode(after: .closed) == .pinned)
    }

    /// Overlay isn't part of the persisted-width cycle — it's a transient
    /// hover state — so the toggle promotes it straight to pinned, same
    /// behavior as before Flow 01 added the rail.
    @Test func toggleFromOverlayPromotesToPinned() {
        #expect(WorkspaceViewContainer.nextSidebarMode(after: .overlay) == .pinned)
    }

    /// A full lap of the two-step pinned/collapsed cycle must return to the
    /// start, proving the toggle is a clean flip with no dead end.
    @Test func pinnedCollapsedCycleReturnsToStartWithinTwoSteps() {
        for start: SidebarMode in [.pinned, .collapsed] {
            var mode = start
            for _ in 0..<2 {
                mode = WorkspaceViewContainer.nextSidebarMode(after: mode)
            }
            #expect(mode == start)
        }
    }

    // MARK: - Tray Items — Single Source of Truth

    /// `sidebarTrayItems` is the one ordered list both `SidebarBottomTray`
    /// (expanded/overlay) and `RailTray` (collapsed) render from. Cover its
    /// order/ids directly — adding a Settings entry later should only ever
    /// require inserting into this list, not touching two views.
    @Test func trayItemsAreOrderedNewSessionThenToggle() {
        let items = WorkspaceViewContainer.sidebarTrayItems(container: nil, toggleLabel: "Collapse Sidebar")
        #expect(items.map(\.id) == ["newSession", "toggleSidebar"])
        #expect(items.map(\.systemName) == ["plus", "sidebar.left"])
    }

    /// The toggle item's label is the one piece of state callers still
    /// supply — the list itself doesn't hardcode wording, since it's shared
    /// across surfaces that word it differently ("Collapse Sidebar",
    /// "Open Sidebar", "Expand Sidebar").
    @Test func trayToggleItemUsesSuppliedLabel() {
        let items = WorkspaceViewContainer.sidebarTrayItems(container: nil, toggleLabel: "Expand Sidebar")
        #expect(items.last?.label == "Expand Sidebar")
    }

    // MARK: - Collapsed Rail Width Clears Traffic Lights

    /// macOS 26's traffic-light cluster reaches ~78pt from the window's left
    /// edge — wider than the original fixed 72pt rail, so the buttons
    /// overran into the terminal card. The rail width must grow to clear
    /// whatever the live cluster measures, with a trailing gap matching its
    /// leading inset.
    @Test func railWidthClearsAWideTrafficLightCluster() {
        // Cluster spans x=20...78 (macOS 26-shaped): leading inset 20, maxX 78.
        let width = WorkspaceLayout.collapsedRailWidth(zoomButtonMaxX: 78, leadingInset: 20)
        #expect(width == 98)
    }

    /// A cluster narrower than the floor (e.g. an older macOS layout) must
    /// not shrink the rail below the original 72pt design width.
    @Test func railWidthFloorsAtSeventyTwo() {
        let width = WorkspaceLayout.collapsedRailWidth(zoomButtonMaxX: 40, leadingInset: 8)
        #expect(width == 72)
    }

    /// A cluster that lands exactly on the floor's boundary still floors at 72.
    @Test func railWidthAtExactFloorBoundary() {
        let width = WorkspaceLayout.collapsedRailWidth(zoomButtonMaxX: 62, leadingInset: 10)
        #expect(width == 72)
    }
}

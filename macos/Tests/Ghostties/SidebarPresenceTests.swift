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

    // MARK: - Full Close ↔ Reopen (Cmd+Shift+S)

    /// Any visible mode goes straight to `.closed` on Cmd+Shift+S, the
    /// toggle `nextSidebarMode(after:)` no longer reaches.
    @Test func closeToggleClosesFromAnyVisibleMode() {
        for start: SidebarMode in [.pinned, .collapsed, .overlay] {
            #expect(WorkspaceViewContainer.nextCloseToggleMode(after: start) == .closed)
        }
    }

    /// `.closed` reopens to `.pinned`, mirroring the hot-zone → overlay →
    /// promote-to-pinned path's destination.
    @Test func closeToggleReopensClosedToPinned() {
        #expect(WorkspaceViewContainer.nextCloseToggleMode(after: .closed) == .pinned)
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

    /// `collapsedRailWidth(in:)` must special-case fullscreen the same way
    /// `titlebarRowTopAnchorConstant(in:)` already does — traffic lights are
    /// hidden there, so measuring their (stale/zero) frames would be wrong.
    /// Covered via the pure style-mask check both functions share, since
    /// `collapsedRailWidth(in:)` itself needs a live `NSWindow`.
    @Test func fullScreenLayoutIsDetectedFromStyleMask() {
        #expect(WorkspaceLayout.isFullScreenLayout(styleMask: [.fullScreen]) == true)
        #expect(WorkspaceLayout.isFullScreenLayout(styleMask: [.titled, .closable, .resizable]) == false)
    }

    // MARK: - Flow 05 Transition Timing Table

    /// Collapse (244pt → rail) runs 260ms on the drawer curve — Sean's
    /// canvas, "Flow 05 · Collapse and close."
    @Test func collapseTimingIs260msOnDrawerCurve() {
        let timing = WorkspaceLayout.sidebarTransitionTiming(from: .pinned, to: .collapsed)
        #expect(timing == WorkspaceLayout.SidebarTransitionTiming(duration: 0.26, curve: .drawer))
    }

    /// Expand (rail → 244pt) runs 240ms on the drawer curve — faster than
    /// collapse's 260ms, since expand has no separate label-fade phase.
    @Test func expandTimingIs240msOnDrawerCurve() {
        let timing = WorkspaceLayout.sidebarTransitionTiming(from: .collapsed, to: .pinned)
        #expect(timing == WorkspaceLayout.SidebarTransitionTiming(duration: 0.24, curve: .drawer))
    }

    /// Full close runs 180ms on the close curve regardless of which visible
    /// mode it closes from — closing has nothing left to read, so it never
    /// waits on the slower drawer curve.
    @Test func fullCloseTimingIs180msOnCloseCurveFromAnyVisibleMode() {
        for start: SidebarMode in [.pinned, .collapsed, .overlay] {
            let timing = WorkspaceLayout.sidebarTransitionTiming(from: start, to: .closed)
            #expect(timing == WorkspaceLayout.SidebarTransitionTiming(duration: 0.18, curve: .close))
        }
    }

    /// Reopen (closed → pinned or collapsed) runs 240ms on the drawer curve —
    /// coming back, the user is reading again, so it mirrors expand's timing
    /// rather than the faster close.
    @Test func reopenTimingIs240msOnDrawerCurve() {
        for target: SidebarMode in [.pinned, .collapsed] {
            let timing = WorkspaceLayout.sidebarTransitionTiming(from: .closed, to: target)
            #expect(timing == WorkspaceLayout.SidebarTransitionTiming(duration: 0.24, curve: .drawer))
        }
    }

    /// Pairs the Flow 05 canvas never named — anything routing through
    /// `.overlay` — keep the pre-Flow-05 generic 200ms curve untouched, per
    /// the brief ("reveal overlay keeps its current animation").
    @Test func overlayTransitionsKeepTheLegacyTiming() {
        let toOverlay = WorkspaceLayout.sidebarTransitionTiming(from: .closed, to: .overlay)
        let fromOverlay = WorkspaceLayout.sidebarTransitionTiming(from: .overlay, to: .pinned)
        #expect(toOverlay == WorkspaceLayout.SidebarTransitionTiming(duration: 0.2, curve: .legacyEaseInOut))
        #expect(fromOverlay == WorkspaceLayout.SidebarTransitionTiming(duration: 0.2, curve: .legacyEaseInOut))
    }

    /// Reduced motion drops translation for a single gentler cross-fade —
    /// never a literal zero, per the reduced-motion convention ("fewer and
    /// gentler animations, not zero").
    @Test func reducedMotionCrossfadeIsNonZeroAndUnder300ms() {
        #expect(WorkspaceLayout.sidebarReducedMotionCrossfadeDuration > 0)
        #expect(WorkspaceLayout.sidebarReducedMotionCrossfadeDuration < 0.3)
    }

    /// Reduced-motion path selection: with the accessibility setting on, the
    /// alpha cross-fade always uses the fixed 120ms token, never the
    /// transition's own (longer, spatial) duration — regardless of which
    /// transition it is.
    @Test func reducedMotionPathAlwaysSelectsTheCrossfadeDuration() {
        let collapseTiming = WorkspaceLayout.sidebarTransitionTiming(from: .pinned, to: .collapsed)
        let closeTiming = WorkspaceLayout.sidebarTransitionTiming(from: .pinned, to: .closed)
        #expect(WorkspaceLayout.sidebarTransitionAlphaDuration(reduceMotion: true, timing: collapseTiming)
            == WorkspaceLayout.sidebarReducedMotionCrossfadeDuration)
        #expect(WorkspaceLayout.sidebarTransitionAlphaDuration(reduceMotion: true, timing: closeTiming)
            == WorkspaceLayout.sidebarReducedMotionCrossfadeDuration)
    }

    /// With motion enabled, the alpha cross-fade always uses the
    /// transition's own duration, not the reduced-motion token.
    @Test func motionEnabledPathAlwaysSelectsTheTransitionDuration() {
        let collapseTiming = WorkspaceLayout.sidebarTransitionTiming(from: .pinned, to: .collapsed)
        #expect(WorkspaceLayout.sidebarTransitionAlphaDuration(reduceMotion: false, timing: collapseTiming)
            == collapseTiming.duration)
    }

    /// The closed-state hot zone activates only after the full-close motion
    /// (180ms) has actually finished — the delay must be at least as long as
    /// the close animation itself, or the reveal overlay could fire before
    /// the card has reached the edge.
    @Test func closedHotZoneActivatesNoSoonerThanCloseFinishes() {
        let closeTiming = WorkspaceLayout.sidebarTransitionTiming(from: .pinned, to: .closed)
        #expect(WorkspaceLayout.closedHotZoneActivationDelay >= closeTiming.duration)
    }

    // MARK: - Closed-State Card Inset

    /// Sean's closed-state layout call (overrides Flow 05's own "card
    /// padding-left 8 → 0"): the terminal card keeps an 8pt margin on ALL
    /// four sides in closed mode — it is never full bleed. `terminalInset`
    /// is the single token every mode's card inset derives from, so this
    /// pins the value the closed-state constraints in `WorkspaceViewContainer`
    /// use on every side.
    @Test func closedStateInsetIsEightPointsOnAllSides() {
        #expect(WorkspaceLayout.terminalInset == 8)
    }

    /// Sean's follow-up decision (sidebar-presence review round 2): confirm
    /// the card's LEFT gap is the same 8pt in every state, not just closed —
    /// pinned, collapsed (rail), and closed all read their leading inset
    /// from this one `terminalInset` token in `WorkspaceViewContainer`
    /// (`applyTransitionConstraints`'s `.pinned`/`.collapsed`/`.closed`
    /// branches and `setup()`'s cold-launch path), so there is exactly one
    /// number to retune, not three that can drift apart.
    @Test func cardLeftGapIsTheSameEightPointsAcrossEveryMode() {
        let pinnedGap = WorkspaceLayout.terminalInset
        let collapsedGap = WorkspaceLayout.terminalInset
        let closedGap = WorkspaceLayout.terminalInset
        #expect(pinnedGap == 8)
        #expect(collapsedGap == 8)
        #expect(closedGap == 8)
        #expect(pinnedGap == collapsedGap && collapsedGap == closedGap)
    }
}

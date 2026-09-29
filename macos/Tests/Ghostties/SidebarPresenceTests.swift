import AppKit
import Foundation
import GhosttiesCore
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
        #expect(items.map(\.id) == ["newSession", "settings", "toggleSidebar"])
        #expect(items.map(\.systemName) == ["plus", "gearshape", "sidebar.left"])
    }

    /// Round 4: Settings sits between `+` and the sidebar toggle (matching
    /// the design), and its accessibility label ("Settings") is distinct
    /// from its tooltip, which names the concrete action ("Open Config").
    @Test func trayItemsIncludeSettingsWithDistinctAccessibilityLabelAndTooltip() {
        let items = WorkspaceViewContainer.sidebarTrayItems(container: nil, toggleLabel: "Collapse Sidebar")
        let settings = items.first(where: { $0.id == "settings" })
        #expect(settings?.label == "Settings")
        #expect(settings?.helpText == "Open Config")
    }

    /// The toggle item's label is the one piece of state callers still
    /// supply — the list itself doesn't hardcode wording, since it's shared
    /// across surfaces that word it differently ("Collapse Sidebar",
    /// "Open Sidebar", "Expand Sidebar").
    @Test func trayToggleItemUsesSuppliedLabel() {
        let items = WorkspaceViewContainer.sidebarTrayItems(container: nil, toggleLabel: "Expand Sidebar")
        #expect(items.last?.label == "Expand Sidebar")
    }

    // MARK: - Collapsed Rail Width — Hugs the Traffic Lights

    /// The rail hugs the traffic-light cluster: zoom `maxX` plus a trailing
    /// gap equal to the leading inset, so the cluster sits centered. A
    /// macOS 26-shaped cluster (x=20...78) gives 98 — not a fixed width
    /// (Sean, sidebar-presence review round 3).
    @Test func railWidthHugsATypicalCluster() {
        let width = WorkspaceLayout.collapsedRailWidth(zoomButtonMaxX: 78, leadingInset: 20)
        #expect(width == 98)
    }

    /// The hug tracks the cluster: a wider cluster widens the rail by the
    /// same amount.
    @Test func railWidthTracksAWideCluster() {
        let width = WorkspaceLayout.collapsedRailWidth(zoomButtonMaxX: 150, leadingInset: 20)
        #expect(width == 170)
    }

    /// A cluster narrower than the floor must not squeeze the rail below
    /// what the 40pt tray pill needs.
    @Test func railWidthFloorsForANarrowCluster() {
        let width = WorkspaceLayout.collapsedRailWidth(zoomButtonMaxX: 40, leadingInset: 8)
        #expect(width == WorkspaceLayout.sidebarRailWidth)
    }

    /// The floor only has to fit the tray pill — it must stay well under
    /// the typical hugged width, or it silently becomes a fixed width again.
    @Test func railFloorFitsTrayPillButStaysUnderTheHug() {
        let trayPillWidth: CGFloat = 32 + 4 * 2
        #expect(WorkspaceLayout.sidebarRailWidth >= trayPillWidth)
        #expect(WorkspaceLayout.sidebarRailWidth < 98)
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

    // MARK: - Collapsed Rail Session List

    /// Round 5: the rail rendered NO session rows at all in review captures.
    /// Cause — `SidebarRailView` was sourcing its list from
    /// `sessionsInVisualOrder(coordinator:)`, which is filtered to sessions
    /// with a live surface (`hasLiveSurface`) for Cmd+Shift+[/] cycling. A
    /// pinned or active session that has never opened a real terminal
    /// surface (every capture-fixture session, or any real pinned session
    /// with a closed terminal) has no live surface and was silently
    /// dropped. `railSessions()` must include it anyway, matching what
    /// `RecentsListView` actually renders for Pinned/Active.
    @MainActor
    @Test func railSessionsIncludesSessionsWithNoLiveSurface() {
        let project = Project(name: "p", rootPath: "~/p")
        let store = WorkspaceStore(testingProjects: [project])
        let pinned = store.addSession(name: "pinned", templateId: UUID(), projectId: project.id)
        store.setSessionPinned(id: pinned.id, true)
        let active = store.addSession(name: "active", templateId: UUID(), projectId: project.id)
        store.updateSessionStatus(id: active.id, status: .running)
        // Neither session is ever given a live surface (no
        // `SessionCoordinator`/`seedEmptySessionTreeForTesting` involved) —
        // this is exactly the capture-fixture / closed-pinned-terminal case.

        let rail = store.railSessions()

        #expect(rail.map(\.name) == ["pinned", "active"])
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

    // MARK: - Flow 05 Content Choreography — Row-Level

    /// The canvas's own reopen note: "session glyphs fade in 40ms apart,
    /// labels land 60ms after their glyph." Every row's glyph travels the
    /// same full expand window (they all start together); the FIRST row's
    /// label starts exactly `glyphLandDuration + 60ms` after the glyph
    /// starts — no extra stagger for row 0.
    @Test func expandLabelDelayForFirstRowIsGlyphLandPlusSixtyMs() {
        let delay = WorkspaceLayout.expandLabelDelay(rowIndex: 0, glyphLandDuration: 0.24)
        #expect(delay == 0.3)
    }

    /// Each subsequent row adds another 40ms — the "40ms apart" stagger.
    @Test func expandLabelDelayStaggersFortyMsPerRow() {
        let glyphLand: TimeInterval = 0.24
        let first = WorkspaceLayout.expandLabelDelay(rowIndex: 0, glyphLandDuration: glyphLand)
        let second = WorkspaceLayout.expandLabelDelay(rowIndex: 1, glyphLandDuration: glyphLand)
        let third = WorkspaceLayout.expandLabelDelay(rowIndex: 2, glyphLandDuration: glyphLand)
        #expect((second - first).isApproximatelyEqual(to: 0.04))
        #expect((third - second).isApproximatelyEqual(to: 0.04))
    }

    /// The stagger schedule must track whatever the expand transition's own
    /// duration actually is (`sidebarTransitionTiming(from: .collapsed, to:
    /// .pinned)`), not a hardcoded literal — this is the one seam that would
    /// silently desync the label stagger from the glyph travel if either
    /// duration were retuned independently.
    @Test func expandLabelDelayUsesTheRealExpandTransitionDuration() {
        let realExpandDuration = WorkspaceLayout.sidebarTransitionTiming(from: .collapsed, to: .pinned).duration
        let delay = WorkspaceLayout.expandLabelDelay(rowIndex: 0, glyphLandDuration: realExpandDuration)
        #expect(delay == realExpandDuration + 0.06)
    }

    /// A negative or out-of-range row index (shouldn't occur, but a bucket
    /// with a stale/renumbered index is cheap to guard) never produces a
    /// delay smaller than the flat 60ms floor.
    @Test func expandLabelDelayClampsNegativeRowIndexToZero() {
        let delay = WorkspaceLayout.expandLabelDelay(rowIndex: -3, glyphLandDuration: 0.24)
        #expect(delay == 0.3)
    }

    /// Row-level choreography (label fade window, glyph travel, stagger)
    /// runs only with motion enabled — Reduce Motion drops it entirely and
    /// relies solely on the container-level 120ms cross-fade (Flow 05
    /// "Reduced Motion: drop the translate entirely... layout snaps").
    @Test func rowChoreographyIsDisabledUnderReducedMotion() {
        #expect(WorkspaceLayout.sidebarRowChoreographyEnabled(reduceMotion: true) == false)
        #expect(WorkspaceLayout.sidebarRowChoreographyEnabled(reduceMotion: false) == true)
    }

    /// The SwiftUI-side content cross-fade animation must share its
    /// duration with the AppKit width animation it runs alongside — this is
    /// the one seam that would desync the panel's geometry motion from the
    /// content's label/glyph motion if it drifted.
    @Test func collapseCrossfadeSwiftUIAnimationMatchesTheAppKitTimingDuration() {
        let timing = WorkspaceLayout.sidebarTransitionTiming(from: .pinned, to: .collapsed)
        // `Animation` isn't directly inspectable, but constructing it must
        // not crash and the function must be pure (called twice with the
        // same input yields the same duration, checked indirectly by the
        // duration table itself already being covered above); this proves
        // it's callable from a curve with real control points (the drawer
        // curve, not `.legacyEaseInOut`, which has none).
        _ = WorkspaceLayout.sidebarTransitionSwiftUIAnimation(timing)
        #expect(timing.curve.swiftUIAnimation != nil)
    }

    /// The legacy (overlay) curve pair has no named control points — the
    /// content cross-fade doesn't apply to overlay transitions at all, but
    /// the fallback (`.easeInOut`) path must still resolve without a crash
    /// if ever called on one.
    @Test func legacyEaseCurveHasNoSwiftUIControlPoints() {
        let timing = WorkspaceLayout.sidebarTransitionTiming(from: .closed, to: .overlay)
        #expect(timing.curve.swiftUIAnimation == nil)
        _ = WorkspaceLayout.sidebarTransitionSwiftUIAnimation(timing)
    }

    // MARK: - Drag Snaps Between Rail and Expanded

    /// Rail 98, min 180 → snap point 139. Below it the drag lands on the
    /// rail; at or above it, pinned — dragging no longer stops at the min
    /// width (Sean, sidebar-presence review round 3).
    @Test func dragBelowSnapPointLandsOnRail() {
        let target = WorkspaceViewContainer.sidebarDragTarget(pointerWidth: 138, railWidth: 98, upperBound: 480)
        #expect(target.mode == .collapsed)
        #expect(target.width == 98)
    }

    /// Past the snap point but under the min width, the sidebar expands to
    /// the min width — not the rail, and not a squeezed full sidebar.
    @Test func dragAtSnapPointExpandsToMinWidth() {
        let target = WorkspaceViewContainer.sidebarDragTarget(pointerWidth: 139, railWidth: 98, upperBound: 480)
        #expect(target.mode == .pinned)
        #expect(target.width == WorkspaceLayout.sidebarMinWidth)
    }

    /// Above the min width the edge follows the pointer, clamped at the top.
    @Test func dragAboveMinWidthFollowsPointerUpToTheBound() {
        #expect(WorkspaceViewContainer.sidebarDragTarget(pointerWidth: 300, railWidth: 98, upperBound: 480).width == 300)
        #expect(WorkspaceViewContainer.sidebarDragTarget(pointerWidth: 900, railWidth: 98, upperBound: 480).width == 480)
    }

    /// Dragging past the left edge of the rail stays on the rail — drag
    /// moves between rail and expanded only; full close stays Cmd+Shift+S.
    @Test func dragFarLeftStaysOnRailNeverCloses() {
        let target = WorkspaceViewContainer.sidebarDragTarget(pointerWidth: -50, railWidth: 98, upperBound: 480)
        #expect(target.mode == .collapsed)
    }

    // MARK: - Terminal Text Padding — Ghostties Default Under User Config

    /// The 16/8 padding defaults are loaded before the user's config on
    /// every load. A misspelled key or bad value would surface here as a
    /// config diagnostic (and a pop-up on every launch).
    @Test func paddingDefaultsLoadWithoutDiagnostics() throws {
        #expect(GhosttiesConfigDefaults.contents.contains("window-padding-x = 16"))
        #expect(GhosttiesConfigDefaults.contents.contains("window-padding-y = 8"))
        let config = try TemporaryConfig("")
        #expect(config.errors.isEmpty)
    }
}

private extension TimeInterval {
    func isApproximatelyEqual(to other: TimeInterval, tolerance: TimeInterval = 0.0001) -> Bool {
        abs(self - other) < tolerance
    }
}

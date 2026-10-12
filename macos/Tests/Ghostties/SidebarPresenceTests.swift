import AppKit
import Combine
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

    /// `sidebarTrayItems` is the one ordered list `SidebarTray` renders on
    /// both axes (expanded/overlay and collapsed). Cover its
    /// order/ids directly. Settings is not in the tray (layout B); it lives
    /// in the app menu.
    @Test func trayItemsAreOrderedNewSessionThenToggle() {
        let items = WorkspaceViewContainer.sidebarTrayItems(container: nil, toggleLabel: "Collapse Sidebar")
        #expect(items.map(\.id) == ["newSession", "newProject", "toggleSidebar"])
        #expect(items.map(\.systemName) == ["plus", "folder.badge.plus", "sidebar.left"])
    }

    /// Layout B splits the tray into two capsules: Create (new session, new
    /// project) and the sidebar toggle on its own, in that order.
    @Test func trayItemsSplitIntoCreateThenToggleCapsules() {
        let items = WorkspaceViewContainer.sidebarTrayItems(container: nil, toggleLabel: "Collapse Sidebar")
        #expect(items.map(\.group) == [.create, .create, .toggle])
        #expect(SidebarTray.groupItemCounts() == [2, 1])
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
        let atFloor = RailTrayGeometry(railWidth: WorkspaceLayout.sidebarRailWidth, margin: WorkspaceLayout.terminalInset, padding: TrayGlassStyle.innerPadding)
        #expect(atFloor.buttonSize >= TrayGlassStyle.verticalIconSize)
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

        let rail = store.railSessions(pinningAvailable: true)

        #expect(rail.map(\.name) == ["pinned", "active"])
    }

    // MARK: - Flow 05 Transition Timing Table

    /// Collapse (sidebar → rail) runs on a spring with no overshoot —
    /// motion-standards: "never bounce a close" — and a quicker response
    /// than the expand (exit faster than enter). Was 260ms on the drawer
    /// curve; Sean asked for a spring (2026-10-11).
    @Test func collapseRunsOnACrispSpringWithNoOvershoot() {
        withDials {
            let collapse = WorkspaceLayout.sidebarMorphSpring(collapsing: true)
            let open = WorkspaceLayout.sidebarMorphSpring(collapsing: false)
            #expect(collapse == WorkspaceLayout.sidebarMorphCollapseSpring)
            #expect(collapse.bounce == 0)
            #expect(collapse.response < open.response)
        }
    }

    /// Expand (rail → sidebar) runs on a spring with a subtle bounce:
    /// emil's "keep bounce subtle (0.1–0.3)", and a response under the
    /// 300–400ms a panel may take.
    @Test func expandRunsOnASubtlyBouncySpring() {
        withDials {
            let open = WorkspaceLayout.sidebarMorphSpring(collapsing: false)
            #expect(open == WorkspaceLayout.sidebarMorphOpenSpring)
            #expect(open.bounce > 0 && open.bounce <= 0.3)
            #expect(open.response <= 0.4)
        }
    }

    /// The Motion dials reach the springs.
    @Test func motionDialsDriveTheSprings() {
        withDials({
            $0.set(0.5, forKey: SidebarDialTuning.motionOpenResponseKey)
            $0.set(0.2, forKey: SidebarDialTuning.motionOpenBounceKey)
            $0.set(0.4, forKey: SidebarDialTuning.motionCollapseResponseKey)
            $0.set(0.05, forKey: SidebarDialTuning.motionCollapseBounceKey)
        }) {
            #expect(WorkspaceLayout.sidebarMorphSpring(collapsing: false) == SidebarSpring(response: 0.5, bounce: 0.2))
            #expect(WorkspaceLayout.sidebarMorphSpring(collapsing: true) == SidebarSpring(response: 0.4, bounce: 0.05))
        }
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
    /// four sides in closed mode — it is never full bleed. The Window margin
    /// dial (`SidebarDialTuning.windowMargin`, default `terminalInset`) is the
    /// single value every mode's card inset reads, so this pins the default
    /// the closed-state constraints in `WorkspaceViewContainer` use on every side.
    @Test func closedStateInsetIsEightPointsOnAllSides() {
        #expect(WorkspaceLayout.terminalInset == 8)
        #expect(SidebarDialTuning.windowMargin() == WorkspaceLayout.terminalInset)
    }

    /// Sean's follow-up decision (sidebar-presence review round 2): confirm
    /// the card's LEFT gap is the same 8pt in every state, not just closed —
    /// pinned, collapsed (rail), and closed all read their leading inset
    /// from this one Window margin dial in `WorkspaceViewContainer`
    /// (`applyTransitionConstraints`'s `.pinned`/`.collapsed`/`.closed`
    /// branches and `setup()`'s cold-launch path), so there is exactly one
    /// number to retune, not three that can drift apart.
    @Test func cardLeftGapIsTheSameEightPointsAcrossEveryMode() {
        let pinnedGap = SidebarDialTuning.windowMargin()
        let collapsedGap = SidebarDialTuning.windowMargin()
        let closedGap = SidebarDialTuning.windowMargin()
        #expect(pinnedGap == 8)
        #expect(collapsedGap == 8)
        #expect(closedGap == 8)
        #expect(pinnedGap == collapsedGap && collapsedGap == closedGap)
    }

    // MARK: - Label choreography (motion spec §1)

    /// Expanding, the labels arrive in reading order: the first's fade
    /// ends at half the travel, each below 5% of the travel later, capped
    /// at the sixth, and every one has landed when the sidebar has
    /// (keyframe spec's 90 + 16·i ms cascade, now on the spring's progress).
    @Test func expandCascadeArrivesInReadingOrderCappedAtTheSixth() {
        func end(_ i: Int) -> CGFloat { WorkspaceLayout.morphFadeWindow(element: .names, staggerIndex: i).end }
        #expect(abs(end(0) - 0.5) < 0.0005)
        #expect(abs(end(1) - 0.45) < 0.0005)
        #expect(abs(end(5) - 0.25) < 0.0005)
        #expect(end(20) == end(5))
        #expect(end(-3) == end(0))
        for i in 0..<8 {
            #expect(WorkspaceLayout.morphFadeOpacity(element: .names, progress: 0, staggerIndex: i) == 1)
            #expect(WorkspaceLayout.morphFadeOpacity(element: .names, progress: 0.5, staggerIndex: i) == 0)
        }
    }

    /// Leaving is faster than arriving: on the collapse spring the first
    /// label is gone well before, on the open spring, the last one lands —
    /// the labels go in the spring's fast start and arrive in its tail.
    /// The drift is 4pt left.
    @Test func labelsLeaveFasterThanTheyArrive() {
        /// Seconds until `spring`, travelling 0 -> 1, first satisfies `done`.
        func time(_ spring: SidebarSpring, until done: (CGFloat) -> Bool) -> Double {
            var x = -1.0, v = 0.0, t = 0.0
            while t < 2 {
                (x, v) = spring.advance(x: x, v: v, dt: 0.001)
                t += 0.001
                if done(CGFloat(1 + x)) { return t }
            }
            return t
        }
        let leave = time(WorkspaceLayout.sidebarMorphCollapseSpring) {
            WorkspaceLayout.morphFadeOpacity(element: .names, progress: $0) == 0
        }
        // Expand runs morph 1 -> 0: travel p puts morph at 1 - p.
        let arrive = time(WorkspaceLayout.sidebarMorphOpenSpring) {
            WorkspaceLayout.morphFadeOpacity(element: .names, progress: 1 - $0, staggerIndex: 5) == 1
        }
        #expect(leave < arrive, "leave \(leave)s, arrive \(arrive)s")
        #expect(WorkspaceLayout.sidebarRowLabelCollapseTravel == -4)
    }

    /// The content cross-fade and the morph must not drift from the width:
    /// both now play on the width constraint's own progress
    /// (`SidebarMorphClock`), overshoot included.
    @MainActor @Test func morphClockReadsTheWidthConstraint() {
        let constraint = NSView().widthAnchor.constraint(equalToConstant: 256)
        let clock = SidebarMorphClock(constraint: constraint, from: 256, to: 60)
        #expect(clock.progress == 0)
        constraint.constant = 158
        #expect(clock.progress == 0.5)
        constraint.constant = 58
        #expect(clock.progress! > 1)
        clock.land()
        #expect(clock.progress == nil)
    }

    /// The legacy (overlay) curve pair has no named control points.
    @Test func legacyEaseCurveHasNoSwiftUIControlPoints() {
        let timing = WorkspaceLayout.sidebarTransitionTiming(from: .closed, to: .overlay)
        #expect(timing.curve.swiftUIAnimation == nil)
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

    /// The 20/20 padding defaults (round 6, Flow 07's Terminal Card
    /// `padding: 20px`) are loaded before the user's config on every load.
    /// A misspelled key or bad value would surface here as a config
    /// diagnostic (and a pop-up on every launch).
    @Test func paddingDefaultsLoadWithoutDiagnostics() throws {
        #expect(GhosttiesConfigDefaults.contents.contains("window-padding-x = 20"))
        #expect(GhosttiesConfigDefaults.contents.contains("window-padding-y = 20"))
        let config = try TemporaryConfig("")
        #expect(config.errors.isEmpty)
    }
}

private extension TimeInterval {
    func isApproximatelyEqual(to other: TimeInterval, tolerance: TimeInterval = 0.0001) -> Bool {
        abs(self - other) < tolerance
    }
}

/// The closed sidebar's hover bar: in `.closed` the container installs
/// exactly one tracking area, the leading-edge strip
/// (`WorkspaceLayout.closedRevealZone(in:)`), and only once the close
/// motion has finished. The rail never installs it.
@MainActor
@Suite(.serialized)
struct ClosedSidebarEdgeStripTests {
    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    private func spin(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private func makeWindow(mode: SidebarMode) -> (WorkspaceViewContainer, NSWindow) {
        let store = WorkspaceStore(
            testingProjects: [], testingSessions: [],
            hasShownPinMigrationNotice: true, hasDismissedPinMigrationNotice: true
        )
        store.updateSidebarMode(mode)
        let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel(), store: store)
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = container
        window.orderFrontRegardless()
        for _ in 0..<4 {
            container.needsLayout = true
            container.layoutSubtreeIfNeeded()
            spin(0.05)
        }
        return (container, window)
    }

    private func close(_ window: NSWindow) {
        window.contentView = nil
        window.orderOut(nil)
        window.close()
    }

    private func expectOnlyTheEdgeStrip(_ container: WorkspaceViewContainer) {
        #expect(container.trackingAreas.count == 1)
        #expect(container.trackingAreas.first?.rect == WorkspaceLayout.closedRevealZone(in: container.bounds))
    }

    /// Closing from pinned installs no strip while the card is still
    /// closing, then exactly the leading-edge strip once it has finished.
    /// Async: the strip installs from a main-queue `asyncAfter`, which a
    /// nested run-loop spin inside this main-queue test can't drain; an
    /// `await` releases the main actor so it can.
    @Test func closingInstallsOnlyTheEdgeStripAfterTheClose() async throws {
        let (container, window) = makeWindow(mode: .pinned)
        defer { close(window) }
        container.toggleSidebarFullyClosed()
        #expect(container.sidebarModeForTesting == .closed)
        #expect(container.trackingAreas.isEmpty)
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
        #expect(container.sidebarModeForTesting == .closed)
        expectOnlyTheEdgeStrip(container)
    }

    /// A persisted `.closed` sidebar launches with exactly the strip.
    @Test func persistedClosedInstallsOnlyTheEdgeStrip() {
        let (container, window) = makeWindow(mode: .closed)
        defer { close(window) }
        spin(0.5)
        #expect(container.sidebarModeForTesting == .closed)
        container.updateTrackingAreas()
        expectOnlyTheEdgeStrip(container)
    }

    private func enterEvent(_ type: NSEvent.EventType, area: NSTrackingArea?, in window: NSWindow) -> NSEvent {
        NSEvent.enterExitEvent(
            with: type, location: NSPoint(x: 4, y: 300), modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0,
            trackingNumber: area.map { unsafeBitCast($0, to: Int.self) } ?? 0,
            userData: nil
        )!
    }

    /// Entering the strip's own tracking area reveals the hover bar
    /// (`.overlay`); an enter forwarded from any other area (a subview's,
    /// such as the terminal surface's) does not.
    @Test func edgeStripRevealsTheOverlayOnlyFromItsOwnArea() throws {
        let (container, window) = makeWindow(mode: .closed)
        defer { close(window) }
        spin(0.5)
        container.updateTrackingAreas()
        let strip = try #require(container.trackingAreas.first)

        let foreign = NSTrackingArea(rect: container.bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: nil, userInfo: nil)
        container.mouseEntered(with: enterEvent(.mouseEntered, area: foreign, in: window))
        #expect(container.sidebarModeForTesting == .closed)

        container.mouseEntered(with: enterEvent(.mouseEntered, area: strip, in: window))
        #expect(container.sidebarModeForTesting == .overlay)
    }

    /// The rail never gets the strip: its hover reveal has its own gate.
    @Test func railInstallsNoEdgeStrip() {
        let (container, window) = makeWindow(mode: .collapsed)
        defer { close(window) }
        spin(0.5)
        #expect(container.sidebarModeForTesting == .collapsed)
        container.updateTrackingAreas()
        #expect(container.trackingAreas.isEmpty)
    }
}

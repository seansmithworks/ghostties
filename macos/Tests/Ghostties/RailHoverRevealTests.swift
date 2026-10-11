import AppKit
import Combine
import Foundation
import GhosttiesCore
import SwiftUI
import Testing
@testable import Ghostty

/// Rail hover-reveal's decisions (`RailHoverReveal`) on an injected clock:
/// dwell, exit grace, re-entry, pin, click-to-dismiss and the on/off dial.
@MainActor
struct RailHoverRevealTests {
    /// A manual clock for `RailHoverReveal.Schedule`: timers fire only when
    /// `advance` passes their due time.
    @MainActor private final class Clock {
        private var now: TimeInterval = 0
        private var nextId = 0
        private var timers: [(id: Int, due: TimeInterval, action: @MainActor @Sendable () -> Void)] = []

        var schedule: RailHoverReveal.Schedule {
            { [unowned self] delay, action in
                let id = self.nextId
                self.nextId += 1
                self.timers.append((id, self.now + delay, action))
                return { [weak self] in self?.timers.removeAll { $0.id == id } }
            }
        }

        func advance(_ seconds: TimeInterval) {
            let end = now + seconds
            while let next = timers.filter({ $0.due <= end }).min(by: { $0.due < $1.due }) {
                timers.removeAll { $0.id == next.id }
                now = next.due
                next.action()
            }
            now = end
        }
    }

    private struct Rig {
        let reveal: RailHoverReveal
        let clock: Clock
        let counts: Counts
    }

    @MainActor private final class Counts {
        var reveals = 0
        var collapses = 0
    }

    private func makeRig(enabled: Bool = true, dwell: TimeInterval = 1.2, grace: TimeInterval = 0.3, canReveal: @escaping () -> Bool = { true }) -> Rig {
        let clock = Clock()
        let counts = Counts()
        let reveal = RailHoverReveal(
            settings: { .init(isEnabled: enabled, dwell: dwell, exitGrace: grace) },
            schedule: clock.schedule
        )
        reveal.onReveal = { counts.reveals += 1 }
        reveal.onCollapse = { counts.collapses += 1 }
        reveal.canReveal = canReveal
        return Rig(reveal: reveal, clock: clock, counts: counts)
    }

    private func revealed(_ rig: Rig) {
        rig.reveal.pointerEntered()
        rig.clock.advance(1.2)
        #expect(rig.counts.reveals == 1)
    }

    @Test func restingForTheDwellReveals() {
        let rig = makeRig()
        rig.reveal.pointerEntered()
        rig.clock.advance(1.19)
        #expect(rig.counts.reveals == 0)
        #expect(rig.reveal.phase == .dwelling)
        rig.clock.advance(0.02)
        #expect(rig.counts.reveals == 1)
        #expect(rig.reveal.isRevealed)
    }

    @Test func crossingTheRailWithoutDwellingDoesNothing() {
        let rig = makeRig()
        rig.reveal.pointerEntered()
        rig.clock.advance(1.0)
        rig.reveal.pointerExited()
        rig.clock.advance(5)
        #expect(rig.counts.reveals == 0)
        #expect(rig.reveal.phase == .idle)
    }

    @Test func leavingCollapsesAfterTheExitGrace() {
        let rig = makeRig()
        revealed(rig)
        rig.reveal.pointerExited()
        rig.clock.advance(0.29)
        #expect(rig.counts.collapses == 0)
        #expect(rig.reveal.isRevealed)
        rig.clock.advance(0.02)
        #expect(rig.counts.collapses == 1)
        #expect(rig.reveal.phase == .idle)
    }

    @Test func reenteringDuringTheGraceKeepsItOut() {
        let rig = makeRig()
        revealed(rig)
        rig.reveal.pointerExited()
        rig.clock.advance(0.2)
        rig.reveal.pointerEntered()
        rig.clock.advance(5)
        #expect(rig.counts.collapses == 0)
        #expect(rig.reveal.phase == .revealed)
    }

    @Test func pinningWhileRevealedIsNeverCollapsed() {
        let rig = makeRig()
        revealed(rig)
        // Mid-grace, the worst case: a collapse is already scheduled.
        rig.reveal.pointerExited()
        #expect(rig.reveal.pin())
        rig.clock.advance(5)
        #expect(rig.counts.collapses == 0)
        #expect(!rig.reveal.isRevealed)
    }

    /// A dwell that completes mid-transition doesn't reveal; it re-arms
    /// and reveals on the next dwell once the transition has landed.
    @Test func aDwellDuringATransitionWaitsForItToLand() {
        var animating = true
        let rig = makeRig(canReveal: { !animating })
        rig.reveal.pointerEntered()
        rig.clock.advance(1.2)
        #expect(rig.counts.reveals == 0)
        #expect(rig.reveal.phase == .dwelling)
        animating = false
        rig.clock.advance(1.2)
        #expect(rig.counts.reveals == 1)
    }

    @Test func switchedOffNothingReveals() {
        let rig = makeRig(enabled: false)
        rig.reveal.pointerEntered()
        rig.clock.advance(10)
        #expect(rig.counts.reveals == 0)
        #expect(rig.reveal.phase == .idle)
    }

    @Test func zeroGraceCollapsesOnExit() {
        let rig = makeRig(grace: 0)
        revealed(rig)
        rig.reveal.pointerExited()
        #expect(rig.counts.collapses == 1)
    }

    /// An item click collapses at once and, with the pointer still on the
    /// rail, doesn't dwell again until it has left.
    @Test func clickingAnItemCollapsesAndHoldsUntilThePointerLeaves() {
        let rig = makeRig()
        revealed(rig)
        rig.reveal.dismiss(pointerInside: true)
        #expect(rig.counts.collapses == 1)
        rig.reveal.pointerEntered()
        rig.clock.advance(5)
        #expect(rig.counts.reveals == 1)
        rig.reveal.pointerExited()
        rig.reveal.pointerEntered()
        rig.clock.advance(1.2)
        #expect(rig.counts.reveals == 2)
    }

    @Test func dialDefaultsAreOnWithA1200msDwellAnd300msGrace() throws {
        let suite = "RailHoverRevealTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(RailHoverReveal.Settings.current(defaults: defaults) == .init(isEnabled: true, dwell: 1.2, exitGrace: 0.3))
        #expect(SidebarDialTuning.hoverRevealStyle(defaults: defaults) == .push)
        defaults.set(false, forKey: SidebarDialTuning.hoverRevealEnabledKey)
        defaults.set(2.0, forKey: SidebarDialTuning.hoverRevealDwellKey)
        defaults.set(0.5, forKey: SidebarDialTuning.hoverRevealExitGraceKey)
        #expect(RailHoverReveal.Settings.current(defaults: defaults) == .init(isEnabled: false, dwell: 2.0, exitGrace: 0.5))
    }
}

/// The reveal on a real `WorkspaceViewContainer`, on a persistence-disabled
/// store. Overlay: the full sidebar comes out over the terminal card without
/// moving or resizing it. Push: the card narrows exactly as on Cmd+S and
/// comes back on collapse. Either way Cmd+S pins it in place.
@MainActor
@Suite(.serialized)
struct RailHoverRevealContainerTests {
    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    private struct Rig {
        let container: WorkspaceViewContainer
        let window: NSWindow

        @MainActor func close() {
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
    }

    /// Starts a reveal in `style` (the style is read once, as it starts).
    private func reveal(_ container: WorkspaceViewContainer, _ style: RailRevealStyle) {
        withDials({ $0.set(style.rawValue, forKey: SidebarDialTuning.hoverRevealStyleKey) }) {
            container.railHoverForTesting.revealNow()
        }
    }

    private func spin(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private func makeRig() -> Rig {
        let project = Project(name: "atlas-api", rootPath: "~/Code/atlas-api")
        let session = AgentSession(name: "auth refactor", templateId: AgentTemplate.claudeCode.id, projectId: project.id)
        let store = WorkspaceStore(
            testingProjects: [project], testingSessions: [session],
            hasShownPinMigrationNotice: true, hasDismissedPinMigrationNotice: true
        )
        store.updateSessionStatus(id: session.id, status: .running)
        store.updateSidebarMode(.collapsed)
        let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel(), store: store)
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = container
        window.orderFrontRegardless()
        // Forced passes: the rail hugs the traffic lights
        // (`collapsedRailWidth(in:)`), which only have their frames once the
        // window is up, and `layout()` is what re-reads them.
        for _ in 0..<10 {
            container.needsLayout = true
            container.layoutSubtreeIfNeeded()
            spin(0.05)
        }
        return Rig(container: container, window: window)
    }

    /// Samples the card through the whole reveal and the whole collapse:
    /// it never moves or resizes, while the sidebar goes out to its full
    /// width and back to the rail.
    @Test func revealOverlaysTheCardWithoutResizingIt() {
        let rig = makeRig()
        defer { rig.close() }
        let container = rig.container
        #expect(container.sidebarModeForTesting == .collapsed)
        let card = container.cardFrameForTesting
        let rail = container.sidebarFrameForTesting.width

        reveal(container, .overlay)
        for _ in 0..<50 {
            spin(0.02)
            #expect(container.cardFrameForTesting == card)
        }
        #expect(container.isRailRevealedForTesting)
        #expect(container.sidebarModeForTesting == .collapsed)
        #expect(!container.isCollapsedPresentationForTesting)
        #expect(container.sidebarFrameForTesting.width > rail + 100)
        #expect(container.sidebarFrameForTesting.maxX > card.minX)

        container.railHoverForTesting.dismiss(pointerInside: false)
        for _ in 0..<50 {
            spin(0.02)
            #expect(container.cardFrameForTesting == card)
        }
        #expect(!container.isRailRevealedForTesting)
        #expect(container.isCollapsedPresentationForTesting)
        #expect(abs(container.sidebarFrameForTesting.width - rail) < 0.5)
        #expect(container.cardFrameForTesting == card)
    }

    /// Cmd+S while revealed: the sidebar stays exactly where it is, the
    /// mode becomes pinned, and the card ends beside it.
    @Test func toggleWhileRevealedPinsWithoutMovingTheSidebar() {
        let rig = makeRig()
        defer { rig.close() }
        let container = rig.container
        reveal(container, .overlay)
        spin(1.0)
        let revealedSidebar = container.sidebarFrameForTesting

        container.toggleSidebar()
        spin(0.05)
        #expect(container.sidebarFrameForTesting == revealedSidebar)
        spin(1.0)
        #expect(container.sidebarModeForTesting == .pinned)
        #expect(container.sidebarFrameForTesting == revealedSidebar)
        #expect(!container.isRailRevealedForTesting)
        // Pinned: never auto-collapsed, and the card sits past the sidebar.
        container.railHoverForTesting.pointerExited()
        spin(1.0)
        #expect(container.sidebarModeForTesting == .pinned)
        #expect(container.cardFrameForTesting.minX >= revealedSidebar.maxX)
    }

    /// Push: the card narrows with the sidebar as on Cmd+S, ending the
    /// pinned gutter past it, and returns to its exact rail frame.
    @Test func pushRevealNarrowsTheCardAndRestoresItOnCollapse() {
        let rig = makeRig()
        defer { rig.close() }
        let container = rig.container
        let card = container.cardFrameForTesting
        let rail = container.sidebarFrameForTesting.width

        reveal(container, .push)
        spin(1.0)
        let sidebar = container.sidebarFrameForTesting
        let pushed = container.cardFrameForTesting
        #expect(container.isRailRevealedForTesting)
        #expect(container.sidebarModeForTesting == .collapsed)
        #expect(sidebar.width > rail + 100)
        #expect(abs(pushed.minX - (sidebar.maxX + SidebarDialTuning.windowMargin())) < 0.5)
        #expect(abs(pushed.maxX - card.maxX) < 0.5)
        #expect(pushed.width < card.width - 100)

        container.railHoverForTesting.dismiss(pointerInside: false)
        spin(1.0)
        #expect(!container.isRailRevealedForTesting)
        #expect(abs(container.sidebarFrameForTesting.width - rail) < 0.5)
        #expect(container.cardFrameForTesting == card)
    }

    /// Push: already the pinned geometry, so Cmd+S changes nothing on screen.
    @Test func toggleWhilePushRevealedPinsWithNoVisualChange() {
        let rig = makeRig()
        defer { rig.close() }
        let container = rig.container
        reveal(container, .push)
        spin(1.0)
        let sidebar = container.sidebarFrameForTesting
        let card = container.cardFrameForTesting

        container.toggleSidebar()
        for _ in 0..<20 {
            spin(0.02)
            #expect(container.sidebarFrameForTesting == sidebar)
            #expect(container.cardFrameForTesting == card)
        }
        #expect(container.sidebarModeForTesting == .pinned)
        #expect(!container.isRailRevealedForTesting)
    }
}

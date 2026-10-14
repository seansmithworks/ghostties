#if DEBUG
import AppKit
import Combine
import DialkitmacOS
import Foundation
import GhosttiesCore
import SwiftUI
import Testing
import XCTest
@testable import Ghostty

/// The sidebar's small-motion springs (`SidebarUISpring`): the "UI springs"
/// dials reach the animations, bounce 0 is a no-overshoot spring, closes and
/// fades never overshoot, and Reduce Motion gets no spring at all.
@MainActor
struct SidebarUISpringTests {
    @Test("Unset dials read the token defaults")
    func defaults() {
        withDials {
            #expect(SidebarUISpring.fold.parameters() == .init(response: SidebarUISpring.defaultResponse, bounce: SidebarUISpring.defaultBounce))
            #expect(SidebarUISpring.move.parameters() == .init(response: SidebarUISpring.defaultResponse, bounce: SidebarUISpring.defaultBounce))
            #expect(SidebarUISpring.hover.parameters() == .init(response: SidebarUISpring.defaultHoverResponse, bounce: SidebarUISpring.defaultBounce))
            #expect(SidebarUISpring.fold.animation(reduceMotion: false)
                == .spring(response: SidebarUISpring.defaultResponse, dampingFraction: 1 - SidebarUISpring.defaultBounce))
        }
    }

    /// The inspector's route: values set on the Sidebar panel's state
    /// persist their keys and change the spring every caller builds.
    @Test("UI springs dials reach the animations")
    func dialsReachTheAnimations() {
        withDials {
            let defaults = SidebarDialTuning.store
            let coordinator = FocusedDialKitCoordinator<SidebarListDialPanel>(defaults: defaults, onChange: {})
            coordinator.state.values.uiSpringResponse = 0.42
            coordinator.state.values.uiSpringBounce = 0.27
            coordinator.state.values.uiSpringHoverResponse = 0.11

            #expect(defaults.object(forKey: SidebarDialTuning.uiSpringResponseKey) as? Double == 0.42)
            #expect(defaults.object(forKey: SidebarDialTuning.uiSpringBounceKey) as? Double == 0.27)
            #expect(defaults.object(forKey: SidebarDialTuning.uiSpringHoverResponseKey) as? Double == 0.11)

            #expect(SidebarUISpring.fold.animation(reduceMotion: false) == .spring(response: 0.42, dampingFraction: 1 - 0.27))
            #expect(SidebarUISpring.move.animation(reduceMotion: false) == .spring(response: 0.42, dampingFraction: 1 - 0.27))
            #expect(SidebarUISpring.hover.animation(reduceMotion: false) == .spring(response: 0.11, dampingFraction: 1 - 0.27))
            // A close / fade keeps the response and drops the overshoot.
            #expect(SidebarUISpring.fold.settle(reduceMotion: false) == .spring(response: 0.42, dampingFraction: 1))
            #expect(SidebarUISpring.hover.settle(reduceMotion: false) == .spring(response: 0.11, dampingFraction: 1))
            // The panel reads back what it wrote.
            let reread = SidebarListDialPanel.read(defaults)
            #expect(reread.uiSpringResponse == 0.42 && reread.uiSpringBounce == 0.27 && reread.uiSpringHoverResponse == 0.11)
        }
    }

    @Test("Bounce 0 is a critically damped spring, the same as settle")
    func zeroBounceIsNoOvershoot() {
        withDials({ $0.set(0.0, forKey: SidebarDialTuning.uiSpringBounceKey) }) {
            for spring in [SidebarUISpring.fold, .move, .hover] {
                let response = spring.parameters().response
                #expect(spring.parameters().dampingFraction == 1)
                #expect(spring.animation(reduceMotion: false) == .spring(response: response, dampingFraction: 1))
                #expect(spring.animation(reduceMotion: false) == spring.settle(reduceMotion: false))
            }
        }
    }

    @Test("A dial can't reach an undamped spring")
    func bounceIsClamped() {
        withDials({ $0.set(5.0, forKey: SidebarDialTuning.uiSpringBounceKey) }) {
            #expect(abs(SidebarUISpring.fold.parameters().dampingFraction - 0.1) < 1e-9)
        }
    }

    /// The drag-reflow gap never overshoots at any Bounce, at the hover
    /// response; unset, it is the 0.2s critically damped spring it ran on
    /// before.
    @Test("The reflow gap settles at the hover response")
    func reflowNeverOvershoots() {
        withDials {
            #expect(SidebarUISpring.reflow.animation(reduceMotion: false) == .spring(response: 0.2, dampingFraction: 1))
        }
        withDials({
            $0.set(0.4, forKey: SidebarDialTuning.uiSpringBounceKey)
            $0.set(0.15, forKey: SidebarDialTuning.uiSpringHoverResponseKey)
        }) {
            #expect(SidebarUISpring.reflow.animation(reduceMotion: false) == .spring(response: 0.15, dampingFraction: 1))
            #expect(SidebarUISpring.reflow.animation(reduceMotion: false) == SidebarUISpring.reflow.settle(reduceMotion: false))
        }
    }

    @Test("Reduce Motion: no spring anywhere")
    func reduceMotionHasNoSpring() {
        withDials {
            for spring in [SidebarUISpring.fold, .move, .hover, .reflow] {
                #expect(spring.animation(reduceMotion: true) == nil)
                #expect(spring.settle(reduceMotion: true) == nil)
                #expect(spring.animation(entering: true, reduceMotion: true) == nil)
                #expect(spring.animation(entering: false, reduceMotion: true) == nil)
            }
        }
    }

    @Test("Entering overshoots, leaving settles")
    func directionPicksTheCurve() {
        withDials {
            #expect(SidebarUISpring.fold.animation(entering: true, reduceMotion: false) == SidebarUISpring.fold.animation(reduceMotion: false))
            #expect(SidebarUISpring.fold.animation(entering: false, reduceMotion: false) == SidebarUISpring.fold.settle(reduceMotion: false))
            #expect(SidebarUISpring.fold.animation(reduceMotion: false) != SidebarUISpring.fold.settle(reduceMotion: false))
        }
    }

    /// The accordion: unfolding is an entrance (bounce), folding a close
    /// (no bounce), on the "UI springs" dials. Reduce Motion is read from
    /// the system here, so only the motion-on case is asserted when it's on.
    @Test("The accordion folds on the fold spring")
    func accordionFoldUsesTheFoldSpring() {
        withDials({ $0.set(0.37, forKey: SidebarDialTuning.uiSpringResponseKey) }) {
            let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            #expect(ProjectAccordionState.toggleAnimation(unfolding: true) == SidebarUISpring.fold.animation(entering: true, reduceMotion: reduce))
            #expect(ProjectAccordionState.toggleAnimation(unfolding: false) == SidebarUISpring.fold.animation(entering: false, reduceMotion: reduce))
            if !reduce {
                #expect(ProjectAccordionState.toggleAnimation(unfolding: false) == .spring(response: 0.37, dampingFraction: 1))
            }
        }
    }
}

/// The selection chip travels between rows, read off rendered pixels.
///
/// Not a single timed snapshot (a loaded machine shifts when frames land):
/// every frame from the selection change until it settles is sampled, and
/// the chip must be exactly one chip-sized run on every frame (a crossfade
/// between the rows draws two), at least one frame must catch it between
/// the rows (a snap never does), and it must come to rest on the new row.
@MainActor
final class SelectionChipTravelTests: XCTestCase {
    private final class Selection: ObservableObject {
        @Published var index = 0
    }

    private struct Harness: View {
        @ObservedObject var selection: Selection
        @Namespace private var namespace
        static let rowHeight: CGFloat = 100
        static let chip: CGFloat = 40

        var body: some View {
            VStack(spacing: 0) {
                ForEach(0..<2, id: \.self) { row in
                    SidebarRowChipBackground(size: Self.chip, isActive: selection.index == row, isHovered: false)
                        .frame(width: 60, height: Self.rowHeight)
                }
            }
            .environment(\.sidebarSelectionChipNamespace, namespace)
            .frame(width: 60, height: Self.rowHeight * 2, alignment: .top)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        }
    }

    /// Every tinted run down `x`, in points from the top. "Tinted" is any
    /// drop below `base` from a sixth of the chip's tint up to twice it,
    /// so a chip fading in or out still counts and text ink doesn't.
    private func runs(_ hosting: NSView, x: CGFloat, base: NSColor) throws -> [ClosedRange<CGFloat>] {
        hosting.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let scale = CGFloat(rep.pixelsHigh) / hosting.bounds.height
        let base = try XCTUnwrap(base.usingColorSpace(.sRGB))
        let baseSum = base.redComponent + base.greenComponent + base.blueComponent
        let chipDrop = baseSum * RailProjectColumn.selectedChipTintOpacity
        let px = Int(x * scale)
        var found: [ClosedRange<Int>] = []
        var start: Int?
        for y in 0...rep.pixelsHigh {
            var tinted = false
            if y < rep.pixelsHigh, let c = rep.colorAt(x: px, y: y)?.usingColorSpace(.sRGB) {
                let drop = baseSum - (c.redComponent + c.greenComponent + c.blueComponent)
                tinted = drop > chipDrop / 6 && drop < chipDrop * 2
            }
            if tinted, start == nil { start = y }
            if !tinted, let s = start { found.append(s...(y - 1)); start = nil }
        }
        return found.map { CGFloat($0.lowerBound) / scale...CGFloat($0.upperBound + 1) / scale }
    }

    /// Flips the selection and samples every frame until the chip settles.
    private func assertTravels(
        _ hosting: NSView, x: CGFloat, base: NSColor, chip: CGFloat,
        from: CGFloat, to: CGFloat, flip: () -> Void
    ) throws {
        func centre(_ r: ClosedRange<CGFloat>) -> CGFloat { (r.lowerBound + r.upperBound) / 2 }
        let before = try runs(hosting, x: x, base: base)
        XCTAssertEqual(before.count, 1, "before: one chip, got \(before)")
        XCTAssertEqual(before.first.map(centre) ?? -1, from, accuracy: 1, "before: on the old row")

        flip()
        var caughtBetween = false
        var frames = 0
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.008))
            let now = try runs(hosting, x: x, base: base)
            frames += 1
            guard now.count == 1, let run = now.first else {
                XCTFail("frame \(frames): one chip, not \(now.count) (\(now))")
                return
            }
            XCTAssertEqual(run.upperBound - run.lowerBound, chip, accuracy: 4, "frame \(frames): one chip's height")
            let c = centre(run)
            if c > min(from, to) + 5 && c < max(from, to) - 5 { caughtBetween = true }
        }
        XCTAssertTrue(caughtBetween, "no frame of \(frames) caught the chip between the rows: it snapped")
        let after = try runs(hosting, x: x, base: base)
        XCTAssertEqual(after.first.map(centre) ?? -1, to, accuracy: 1, "after: at rest on the new row")
    }

    private func host<V: View>(_ view: V, size: NSSize) -> (NSHostingView<V>, NSWindow) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        return (hosting, window)
    }

    func testSelectionChipTravelsToTheNewRow() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "Reduce Motion is on: the chip snaps by design")
        try withDials {
            let selection = Selection()
            let (hosting, window) = host(Harness(selection: selection), size: NSSize(width: 60, height: Harness.rowHeight * 2))
            defer { window.orderOut(nil) }
            try assertTravels(
                hosting, x: 30, base: .white, chip: Harness.chip,
                from: Harness.rowHeight / 2, to: Harness.rowHeight * 1.5
            ) { selection.index = 1 }
        }
    }

    /// The real list: `RecentsListView` hands its rows the namespace, so a
    /// selection change in the coordinator moves the chip from one session
    /// row to the next instead of crossfading.
    func testRealListRowsShareTheSelectionChip() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "Reduce Motion is on: the chip snaps by design")
        try withDials {
            let project = Project(name: "atlas-api", rootPath: "~/Code/atlas-api")
            let sessions = (0..<3).map { i in
                AgentSession(
                    name: "Session \(i)", templateId: AgentTemplate.claudeCode.id, projectId: project.id,
                    sortOrder: i, lastActiveAt: Date(), lastOutputAt: Date(), isNamePinned: true
                )
            }
            let store = WorkspaceStore(
                testingProjects: [project], testingSessions: sessions,
                hasShownPinMigrationNotice: true, hasDismissedPinMigrationNotice: true
            )
            for s in sessions {
                store.updateIndicatorState(id: s.id, state: .inactive)
                store.updateSessionStatus(id: s.id, status: .running)
            }
            let coordinator = SessionCoordinator()
            coordinator.setActiveSessionIdForTesting(sessions[0].id)

            let width: CGFloat = 260
            let chrome = try XCTUnwrap(ChromeTheme.ghostties(.light).chrome.usingColorSpace(.sRGB))
            let tabSuiteName = "com.seansmithdesign.ghostties.tests.sidebar-tab.\(UUID().uuidString)"
            let tabSuite = try XCTUnwrap(UserDefaults(suiteName: tabSuiteName))
            defer { tabSuite.removePersistentDomain(forName: tabSuiteName) }
            tabSuite.set(SidebarTab.sessions.rawValue, forKey: "ghostties.sidebarTab")
            let root = VStack(spacing: 0) {
                RecentsListView()
                Spacer(minLength: 0)
            }
                .frame(width: width, height: 400)
                .environment(\.sidebarTrailingGutter, 0)
                .environmentObject(store)
                .environmentObject(coordinator)
                .environmentObject(SidebarWidthModel(width: width))
                .defaultAppStorage(tabSuite)
                .background(Color(nsColor: chrome))
            let (hosting, window) = host(root, size: NSSize(width: width, height: 400))
            defer { window.orderOut(nil) }

            let chip = RailProjectColumn.chipSize(.sidebar)
            let slotMidX = SidebarDialTuning.windowMargin() + SidebarDialTuning.contentPaddingLeading()
                + SidebarDialTuning.rowLeadingPadding() + SidebarListRowChrome<EmptyView, EmptyView>.glyphSlotWidth / 2
            let x = slotMidX - chip / 2 + 8
            // Where the rows' chips sit: render each selection at rest.
            let first = try XCTUnwrap(try runs(hosting, x: x, base: chrome).first, "no chip on the first session")
            coordinator.setActiveSessionIdForTesting(sessions[1].id)
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))
            let second = try XCTUnwrap(try runs(hosting, x: x, base: chrome).first, "no chip on the second session")
            XCTAssertGreaterThan(second.lowerBound - first.lowerBound, 20, "the two rows' chips are apart")

            try assertTravels(
                hosting, x: x, base: chrome, chip: chip,
                from: (second.lowerBound + second.upperBound) / 2, to: (first.lowerBound + first.upperBound) / 2
            ) { coordinator.setActiveSessionIdForTesting(sessions[0].id) }
        }
    }
}
#endif

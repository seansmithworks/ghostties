#if DEBUG
import AppKit
import Combine
import DialkitmacOS
import Foundation
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

    @Test("Reduce Motion: no spring anywhere")
    func reduceMotionHasNoSpring() {
        withDials {
            for spring in [SidebarUISpring.fold, .move, .hover] {
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

/// The selection chip travels between rows: caught mid-flight on pixels,
/// strictly between the old row and the new one, then at rest on the new.
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

    /// Every tinted run down the column's centre, in points from the top.
    /// The threshold is low, so a chip fading in or out still counts: a
    /// crossfade between two rows reads as two runs, a travelling chip as
    /// one.
    private func chipRuns(_ hosting: NSView) throws -> [ClosedRange<CGFloat>] {
        hosting.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let scale = CGFloat(rep.pixelsHigh) / hosting.bounds.height
        let x = Int(30 * scale)
        var runs: [ClosedRange<Int>] = []
        var start: Int?
        for y in 0...rep.pixelsHigh {
            var tinted = false
            if y < rep.pixelsHigh, let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                tinted = 3 - (c.redComponent + c.greenComponent + c.blueComponent) > 0.015
            }
            if tinted, start == nil { start = y }
            if !tinted, let s = start { runs.append(s...(y - 1)); start = nil }
        }
        return runs.map { CGFloat($0.lowerBound) / scale...CGFloat($0.upperBound + 1) / scale }
    }

    /// The one chip's run; fails when there isn't exactly one.
    private func chip(_ hosting: NSView, _ moment: String) throws -> (centre: CGFloat, height: CGFloat) {
        let runs = try chipRuns(hosting)
        XCTAssertEqual(runs.count, 1, "\(moment): one chip, not \(runs.count) (\(runs))")
        let run = try XCTUnwrap(runs.first, "\(moment): no chip")
        return ((run.lowerBound + run.upperBound) / 2, run.upperBound - run.lowerBound)
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testSelectionChipTravelsToTheNewRow() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "Reduce Motion is on: the chip snaps by design")
        try withDials {
            let selection = Selection()
            let hosting = NSHostingView(rootView: Harness(selection: selection))
            hosting.frame = NSRect(x: 0, y: 0, width: 60, height: Harness.rowHeight * 2)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = hosting
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            spin(0.1)

            let from = Harness.rowHeight / 2
            let to = Harness.rowHeight * 1.5
            let start = try chip(hosting, "before")
            XCTAssertEqual(start.centre, from, accuracy: 1)
            XCTAssertEqual(start.height, Harness.chip, accuracy: 2)

            selection.index = 1
            // About a third of the spring's response: well inside the travel.
            spin(SidebarUISpring.defaultResponse * 0.3)
            // One chip-sized chip between the rows: travelling, not a
            // fade out of one row and into the other.
            let midway = try chip(hosting, "mid-travel")
            XCTAssertEqual(midway.height, Harness.chip, accuracy: 4, "mid-travel: one chip's height")
            XCTAssertGreaterThan(midway.centre, from + 5, "the chip left the first row")
            XCTAssertLessThan(midway.centre, to - 5, "the chip is still travelling, not already on the new row")

            spin(1.5)
            let end = try chip(hosting, "after")
            XCTAssertEqual(end.centre, to, accuracy: 1)
            XCTAssertEqual(end.height, Harness.chip, accuracy: 2)
        }
    }
}
#endif

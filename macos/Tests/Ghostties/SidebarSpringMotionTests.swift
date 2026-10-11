import AppKit
import Foundation
import Testing
@testable import Ghostty

/// The sidebar's spring (`SidebarSpring`) and the driver that plays every
/// constraint of a toggle or a reveal on it (`SidebarMotionDriver`), stepped
/// by hand: no display link, no sleeps.
@MainActor
struct SidebarSpringMotionTests {
    private func constraint(_ constant: CGFloat) -> NSLayoutConstraint {
        NSView().widthAnchor.constraint(equalToConstant: constant)
    }

    /// The largest overshoot past the target, as a share of the travel,
    /// running `spring` from 0 to 1.
    private func overshoot(_ spring: SidebarSpring) -> Double {
        var x = -1.0, v = 0.0, peak = 0.0
        for _ in 0..<3000 {
            (x, v) = spring.advance(x: x, v: v, dt: 0.001)
            peak = max(peak, x)
        }
        #expect(abs(x) < 0.001, "unsettled at 3s: \(x)")
        return peak
    }

    @Test func criticallyDampedNeverOvershoots() {
        #expect(overshoot(WorkspaceLayout.sidebarMorphCollapseSpring) <= 0)
        #expect(overshoot(SidebarSpring(response: 0.3, bounce: 0)) <= 0)
    }

    /// The open spring's overshoot is visible but not cartoony: a few
    /// percent of the travel (bounce 0.3, about 4.6%).
    @Test func openSpringOvershootsVisiblyButSubtly() {
        let peak = overshoot(WorkspaceLayout.sidebarMorphOpenSpring)
        #expect(peak > 0.02 && peak < 0.07, "overshoot \(peak)")
    }

    /// Stepping in one go or in many small frames lands in the same place:
    /// the solution is closed-form, so frame length never changes the curve.
    @Test func stepsAreExactAtAnyFrameLength() {
        let spring = WorkspaceLayout.sidebarMorphOpenSpring
        let once = spring.advance(x: -1, v: 0, dt: 0.2)
        var x = -1.0, v = 0.0
        for _ in 0..<200 { (x, v) = spring.advance(x: x, v: v, dt: 0.001) }
        #expect(abs(once.x - x) < 1e-9 && abs(once.v - v) < 1e-6)
    }

    /// A reversal mid-flight (hover out during a reveal, Cmd+S spam) starts
    /// from exactly where the constraint is and keeps its speed: no jump in
    /// position, no jump in velocity.
    @Test func retargetKeepsPositionAndVelocity() {
        let driver = SidebarMotionDriver(view: nil)
        let width = constraint(60)
        driver.animate([(width, 256)], spring: WorkspaceLayout.sidebarMorphOpenSpring) {}
        for _ in 0..<6 { driver.step(1.0 / 60) }
        let before = width.constant
        driver.step(0.001)
        let speedBefore = (width.constant - before) / 0.001
        let atRetarget = width.constant

        driver.animate([(width, 60)], spring: WorkspaceLayout.sidebarMorphCollapseSpring) {}
        #expect(width.constant == atRetarget)
        driver.step(0.001)
        let speedAfter = (width.constant - atRetarget) / 0.001
        // 1ms on, it has moved what its speed says, not more.
        let expected = speedBefore * 0.001
        #expect(abs((width.constant - atRetarget) - expected) < 0.1, "moved \(width.constant - atRetarget)pt, expected \(expected)")
        #expect(speedBefore > 100, "test needs a moving spring: \(speedBefore)pt/s")
        #expect(abs(speedAfter - speedBefore) / speedBefore < 0.05, "speed \(speedBefore) -> \(speedAfter)")
    }

    /// A retarget that adds a constraint at rest (Cmd+S pinning an overlay
    /// reveal mid-flight: the card's gap joins while the width is still
    /// moving) keeps the running width's speed instead of restarting the
    /// whole motion from rest.
    @Test func retargetKeepsVelocityWhenAChannelJoinsAtRest() {
        let driver = SidebarMotionDriver(view: nil)
        let width = constraint(60), gap = constraint(-200)
        driver.animate([(width, 256)], spring: WorkspaceLayout.sidebarMorphOpenSpring) {}
        for _ in 0..<4 { driver.step(1.0 / 60) }
        let before = width.constant
        driver.step(0.001)
        let speedBefore = (width.constant - before) / 0.001
        let atRetarget = width.constant
        // The joining gap travels further than what is left of the width.
        driver.animate([(width, 256), (gap, 8)], spring: WorkspaceLayout.sidebarMorphOpenSpring) {}
        driver.step(0.001)
        let speedAfter = (width.constant - atRetarget) / 0.001
        #expect(speedBefore > 100, "test needs a moving spring: \(speedBefore)pt/s")
        #expect(abs(speedAfter - speedBefore) / speedBefore < 0.05, "speed \(speedBefore) -> \(speedAfter)")
    }

    /// A window closed mid-spring: once the driver is gone, the display
    /// link and the backstop timer stop, rather than ticking forever.
    @Test func tickerStopsWhenTheDriverGoesMidSpring() {
        // The driver holds its view weakly; the window would own it.
        let view = NSView()
        var driver: SidebarMotionDriver? = SidebarMotionDriver(view: view)
        driver?.animate([(constraint(60), 256)], spring: WorkspaceLayout.sidebarMorphOpenSpring) {}
        weak var ticker = driver?.tickerForTesting
        weak var timer = ticker?.timerForTesting
        #expect(ticker != nil && timer != nil && timer?.isValid == true)
        driver = nil
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        #expect(timer == nil, "the timer is still scheduled")
        #expect(ticker == nil, "the ticker is still retained (display link or timer)")
        withExtendedLifetime(view) {}
    }

    /// Constraints keep moving together on a retarget that names only some
    /// of them: the others keep their targets.
    @Test func retargetCarriesUnnamedConstraints() {
        let driver = SidebarMotionDriver(view: nil)
        let width = constraint(60), gap = constraint(0)
        driver.animate([(width, 256), (gap, 8)], spring: WorkspaceLayout.sidebarMorphOpenSpring) {}
        for _ in 0..<4 { driver.step(1.0 / 60) }
        driver.animate([(width, 256)], spring: WorkspaceLayout.sidebarMorphOpenSpring) {}
        for _ in 0..<240 { driver.step(1.0 / 60) }
        #expect(width.constant == 256 && gap.constant == 8)
    }

    /// Completions fire when the spring settles, not after a nominal
    /// duration: still running at the response time, done (once, exactly on
    /// target) only once it is at rest.
    @Test func completionFiresWhenTheSpringSettles() {
        let driver = SidebarMotionDriver(view: nil)
        let width = constraint(256)
        var completed = 0
        let spring = WorkspaceLayout.sidebarMorphCollapseSpring
        driver.animate([(width, 60)], spring: spring) { completed += 1 }
        var t = 0.0
        while t < spring.response {
            driver.step(1.0 / 120)
            t += 1.0 / 120
        }
        #expect(completed == 0 && driver.isRunning, "done at \(t)s, \(width.constant)pt")
        while driver.isRunning && t < 3 {
            driver.step(1.0 / 120)
            t += 1.0 / 120
        }
        #expect(completed == 1)
        #expect(width.constant == 60)
        #expect(!driver.isRunning)
    }

    /// Every segment's completion fires, in order, when the last one
    /// settles: the container's generation guard decides which still count.
    @Test func supersededCompletionsFireOnSettleInOrder() {
        let driver = SidebarMotionDriver(view: nil)
        let width = constraint(60)
        var order: [Int] = []
        driver.animate([(width, 256)], spring: WorkspaceLayout.sidebarMorphOpenSpring) { order.append(1) }
        driver.step(1.0 / 60)
        driver.animate([(width, 60)], spring: WorkspaceLayout.sidebarMorphCollapseSpring) { order.append(2) }
        for _ in 0..<600 where driver.isRunning { driver.step(1.0 / 60) }
        #expect(order == [1, 2])
    }

    /// `cancel` hands the constraints over where they are, with no
    /// completion.
    @Test func cancelStopsInPlaceWithoutCompleting() {
        let driver = SidebarMotionDriver(view: nil)
        let width = constraint(60)
        var completed = false
        driver.animate([(width, 256)], spring: WorkspaceLayout.sidebarMorphOpenSpring) { completed = true }
        driver.step(1.0 / 60)
        let at = width.constant
        driver.cancel()
        driver.step(1.0 / 60)
        #expect(width.constant == at && !completed && !driver.isRunning)
    }
}

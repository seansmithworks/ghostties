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
#endif

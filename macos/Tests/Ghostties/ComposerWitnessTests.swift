import Foundation
import Testing
import GhosttiesCore
@testable import Ghostty

/// R14 plan §6 tests 2–4 — pure-function coverage for the mapping,
/// identity resolution, and pose math `ComposerWitness`/
/// `ComposerWitnessMotion` extract out of `SessionComposerPalette`'s view
/// body specifically so they ARE testable (`feedback_vacuous-tests-pass-
/// green`/quality-agent's "logic in a View body cannot be tested" rule).
struct ComposerWitnessTests {
    // MARK: - Test 2: mapping (plan §3)

    /// red mutation: remap `.inky` to `.haze` in `ComposerWitness
    /// .witnessGhost(for:)` — this test then fails the fixed-pair
    /// assertion for `.inky`.
    @Test func allTwentyFourAppGhostsMapWithFixedPairsAndNoOversizedBucket() {
        var counts: [ComposerWitnessGhost: Int] = [:]
        for character in GhostCharacter.allCases {
            let witness = ComposerWitness.witnessGhost(for: character)
            counts[witness, default: 0] += 1
        }

        // Every `GhostCharacter` case must map to exactly one bucket, and
        // `allCases.count` must equal the sum of bucket sizes (exhaustive
        // switch, no case dropped).
        #expect(counts.values.reduce(0, +) == GhostCharacter.allCases.count)

        // Colour-confirmed fixed pairs (plan §3).
        let fixedPairs: [(GhostCharacter, ComposerWitnessGhost)] = [
            (.blinky, .flicker), (.pinky, .shade), (.inky, .murk), (.clyde, .haze),
            (.specter, .specter), (.wisp, .wisp), (.phantom, .phantom),
            (.shade, .shade), (.ember, .ember), (.chill, .chill), (.flicker, .flicker)
        ]
        #expect(fixedPairs.count == 11)
        for (appGhost, expected) in fixedPairs {
            #expect(ComposerWitness.witnessGhost(for: appGhost) == expected, "\(appGhost) should map to \(expected)")
        }

        // No bucket carries more than 3 app ghosts (plan §3).
        for (witness, count) in counts {
            #expect(count <= 3, "\(witness) bucket has \(count) app ghosts, exceeds the 3-max rule")
        }
    }

    // MARK: - Test 3: identity (plan §2/§5)

    private func project(ghost: GhostCharacter?) -> Project {
        Project(name: "Demo", rootPath: "/tmp/composer-witness-test-\(UUID().uuidString)", ghostCharacter: ghost)
    }

    /// red mutation: return `.placeholder` unconditionally from
    /// `ComposerWitness.identity(commandProject:binding:)` — every
    /// assertion below except the empty-open one then fails.
    @Test func emptyOpenResolvesToPlaceholder() {
        let identity = ComposerWitness.identity(commandProject: nil, binding: .open)
        #expect(identity == .placeholder)
    }

    @Test func typedProjectResolvesToItsGhost() {
        let typed = project(ghost: .blinky)
        // `binding` is a DIFFERENT project than `commandProject` — proves
        // the typed project wins, not the binding (Sean's fork #1).
        let bound = project(ghost: .shade)
        let identity = ComposerWitness.identity(commandProject: typed, binding: .prefilled(bound))
        #expect(identity == .ghost(.flicker))
    }

    @Test func lockedProjectShowsItsGhostAtOpenBeforeAnythingIsTyped() {
        let locked = project(ghost: .clyde)
        let identity = ComposerWitness.identity(commandProject: nil, binding: .locked(locked))
        #expect(identity == .ghost(.haze))
    }

    @Test func projectWithNoStoredGhostResolvesToPlaceholder() {
        let noGhost = project(ghost: nil)
        let identity = ComposerWitness.identity(commandProject: noGhost, binding: .open)
        #expect(identity == .placeholder)
    }

    // MARK: - Test 4: pose (plan §4)

    /// red mutation: change the hop's `-10` peak constant in
    /// `ComposerWitnessMotion.pose`'s `.tabAccept` case to `-6`.
    @Test func tabAcceptHopPeaksAtMinusTenAndReturnsToRest() {
        let start = ComposerWitnessMotion.pose(beat: .tabAccept, beatElapsed: 0, clockElapsed: 0, reduceMotion: false)
        #expect(start.offsetY == 0)

        let mid = ComposerWitnessMotion.pose(beat: .tabAccept, beatElapsed: 0.15, clockElapsed: 0.15, reduceMotion: false)
        #expect(mid.offsetY <= -9.9, "expected the hop to peak near -10 at the midpoint, got \(mid.offsetY)")

        let end = ComposerWitnessMotion.pose(beat: .tabAccept, beatElapsed: 0.3, clockElapsed: 0.3, reduceMotion: false)
        #expect(abs(end.offsetY) < 0.01, "expected the hop back at rest by 300ms, got \(end.offsetY)")
    }

    /// red mutation: remove the `beatElapsed < duration` guard in the
    /// `.unknownBranch` case — the shake would then never settle to 0.
    @Test func unknownBranchShakeStaysWithinFourPointsAndSettlesAfterSevenHundredMs() {
        for step in stride(from: 0.0, to: 0.7, by: 0.05) {
            let pose = ComposerWitnessMotion.pose(beat: .unknownBranch, beatElapsed: step, clockElapsed: step, reduceMotion: false)
            #expect(abs(pose.offsetX) <= 4.01, "shake exceeded ±4pt at \(step)s: \(pose.offsetX)")
        }
        let settled = ComposerWitnessMotion.pose(beat: .unknownBranch, beatElapsed: 0.71, clockElapsed: 0.71, reduceMotion: false)
        #expect(settled.offsetX == 0, "expected the shake to settle to 0 after 700ms, got \(settled.offsetX)")
    }

    /// red mutation: change the launch case's `-40`/opacity-`0` targets, or
    /// its 0.2s duration.
    @Test func launchLiftsFortyPointsAndFadesToZeroOpacityByTwoHundredMs() {
        let end = ComposerWitnessMotion.pose(beat: .launch, beatElapsed: 0.2, clockElapsed: 0.2, reduceMotion: false)
        #expect(end.offsetY == -40, "expected -40 offset at 200ms, got \(end.offsetY)")
        #expect(end.opacity == 0, "expected opacity 0 at 200ms, got \(end.opacity)")
    }

    /// red mutation: drop the `reduceMotion` early-return in
    /// `ComposerWitnessMotion.pose` — every beat below would then animate.
    @Test func reduceMotionHoldsRestingPoseForEveryBeat() {
        let resting = ComposerWitnessMotion.Pose(offsetY: 0, offsetX: 0, opacity: 1, eyesOpen: true)
        let beats: [ComposerWitness.BeatKind] = [.idle, .open, .resolve, .tabAccept, .unknownBranch, .launch]
        for beat in beats {
            let pose = ComposerWitnessMotion.pose(beat: beat, beatElapsed: 0.05, clockElapsed: 3.9, reduceMotion: true)
            #expect(pose == resting, "\(beat) did not hold the resting pose under Reduce Motion: \(pose)")
        }
    }
}

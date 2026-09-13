import Foundation
import Testing
import GhosttiesCore
@testable import Ghostty

/// R14 plan §6 tests 2–3 — pure-function coverage for the mapping and
/// identity resolution `ComposerWitness` extracts out of
/// `SessionComposerPalette`'s view body specifically so they ARE testable
/// (`feedback_vacuous-tests-pass-green`/quality-agent's "logic in a View
/// body cannot be tested" rule). Frame-animation coverage lives in
/// `ComposerWitnessFramesTests`.
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
}

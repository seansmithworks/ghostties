import Foundation
import SwiftUI
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

    // MARK: - R2 review: identity transitions mid-playback

    private static let identityA = ComposerWitness.Identity.ghost(.flicker)
    private static let identityB = ComposerWitness.Identity.ghost(.shade)
    private static let identityC = ComposerWitness.Identity.ghost(.murk)

    /// Distinct, deterministic colours per identity — not the real
    /// `bodyColor(for:)` (private to `ComposerWitnessView`), just enough to
    /// prove which identity's colour landed on which cell.
    private static func testColor(for identity: ComposerWitness.Identity) -> Color {
        switch identity {
        case .placeholder: return .gray
        case .ghost(.flicker): return .red
        case .ghost(.shade): return .blue
        case .ghost(.murk): return .green
        default: return .black
        }
    }

    /// red mutation (the ef496f46d bug): `onChange(of: identity)` rebuilt
    /// `buildResolveFrames` from `pixels(for: previousIdentity)` — the
    /// interrupted beat's full named grid — discarding whatever fraction of
    /// the in-flight morph had already played. A second identity change
    /// arriving mid-morph must instead start from EXACTLY the on-screen
    /// grid at that instant.
    @Test func identityChangeMidMorphStartsFromTheOnScreenFrameNotTheNamedTarget() {
        let gridA = ComposerWitnessGhost.flicker.pixels
        let gridB = ComposerWitnessGhost.shade.pixels
        let gridC = ComposerWitnessGhost.murk.pixels

        // Simulate "midway through an A→B morph": a real dither frame that
        // is neither A nor B verbatim.
        let midMorph = ComposerWitnessFrames.dither(gridA: gridA, gridB: gridB, progress: 0.5, seed: 11)
        let onScreen: (grid: [String], cellOffsetY: Int, sourceIsB: [[Bool]]?) =
            (midMorph.grid, 0, midMorph.sourceIsB)

        let resolved = ComposerWitnessTransition.identityChanged(
            to: Self.identityC,
            currentDisplayedIdentity: Self.identityB,
            currentPreviousIdentity: Self.identityA,
            onScreen: onScreen,
            targetGrid: gridC,
            isLaunchLocked: false,
            colorFor: Self.testColor(for:),
            seed: 11
        )
        let fromNamedTarget = ComposerWitnessFrames.buildResolveFrames(gridA: gridB, gridB: gridC, seed: 11)
        let fromOnScreen = ComposerWitnessFrames.buildResolveFrames(gridA: midMorph.grid, gridB: gridC, seed: 11)

        #expect(resolved?.beatFrames.first?.grid == fromOnScreen.first?.grid)
        #expect(resolved?.beatFrames.first?.grid != fromNamedTarget.first?.grid,
                "restarting from B's full grid instead of the on-screen mid-morph frame is exactly the bug being fixed")
    }

    /// The captured per-cell colours must reflect what was ACTUALLY on
    /// screen (a mix of the outgoing and incoming ghost's colours mid-morph),
    /// not a single flat colour.
    @Test func identityChangeMidMorphCapturesEachCellsActualOnScreenColor() {
        let onScreen: (grid: [String], cellOffsetY: Int, sourceIsB: [[Bool]]?) = (
            ["XX", "XX"],
            0,
            [[true, false], [false, true]]
        )
        let resolved = ComposerWitnessTransition.identityChanged(
            to: Self.identityC,
            currentDisplayedIdentity: Self.identityB,
            currentPreviousIdentity: Self.identityA,
            onScreen: onScreen,
            targetGrid: ["XX", "XX"],
            isLaunchLocked: false,
            colorFor: Self.testColor(for:),
            seed: 11
        )
        let colors = resolved?.resolveFromColors
        #expect(colors?[0][0] == .blue, "true (fromB) cells were already B's (shade) colour")
        #expect(colors?[0][1] == .red, "false cells were still A's (flicker) colour")
        #expect(colors?[1][0] == .red)
        #expect(colors?[1][1] == .blue)
    }

    /// A resolve interrupting a beat that had shifted the sprite (e.g.
    /// mid tab-accept hop) must blend that offset back to 0 across the new
    /// morph, never snap to 0 on frame one.
    @Test func identityChangeMidShiftedBeatBlendsTheOffsetBackToZeroWithoutSnapping() {
        let onScreen: (grid: [String], cellOffsetY: Int, sourceIsB: [[Bool]]?) = (
            ["XX", "XX"], -2, nil
        )
        let resolved = ComposerWitnessTransition.identityChanged(
            to: Self.identityC,
            currentDisplayedIdentity: Self.identityB,
            currentPreviousIdentity: nil,
            onScreen: onScreen,
            targetGrid: ["XX", "XX"],
            isLaunchLocked: false,
            colorFor: Self.testColor(for:),
            seed: 11
        )
        let offsets = resolved?.beatFrames.map(\.cellOffsetY) ?? []
        #expect(offsets.first != 0, "the first frame must not snap straight to 0")
        #expect(offsets.first! < 0, "the first frame should still read close to the captured -2 start")
        #expect(offsets.last == 0, "the morph must still land on 0 by its final frame")
    }

    /// red mutation (the ef496f46d bug): `onChange(of: identity)` always
    /// rearmed a `.resolve` beat unconditionally, even while `.launch` was
    /// playing/held — overriding "ends empty and stays empty". Once locked,
    /// every identity change must be a no-op.
    @Test func identityChangeWhileLaunchLockedIsIgnored() {
        let onScreen: (grid: [String], cellOffsetY: Int, sourceIsB: [[Bool]]?) = (
            ["..", ".."], 0, nil
        )
        let resolved = ComposerWitnessTransition.identityChanged(
            to: Self.identityC,
            currentDisplayedIdentity: Self.identityB,
            currentPreviousIdentity: Self.identityA,
            onScreen: onScreen,
            targetGrid: ["XX", "XX"],
            isLaunchLocked: true,
            colorFor: Self.testColor(for:),
            seed: 11
        )
        #expect(resolved == nil, "launch is terminal — an identity change must not re-arm a resolve while locked")
    }
}

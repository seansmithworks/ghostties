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

    // MARK: - Identity transitions: the blend (a project change never flips)

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

    private static func pixelsFor(_ identity: ComposerWitness.Identity) -> [String] {
        switch identity {
        case .placeholder: return ComposerWitnessPlaceholder.pixels
        case .ghost(let ghost): return ghost.pixels
        }
    }

    private static func resting(_ identity: ComposerWitness.Identity) -> ComposerWitnessTransition.OnScreen {
        (pixelsFor(identity), 0, nil)
    }

    private static func next(
        _ state: ComposerWitnessTransition.ViewState,
        identity: ComposerWitness.Identity,
        beat: ComposerWitness.Beat? = nil,
        onScreen: ComposerWitnessTransition.OnScreen? = nil,
        pixelsFor: ((ComposerWitness.Identity) -> [String])? = nil,
        reduceMotion: Bool = false
    ) -> ComposerWitnessTransition.ViewState {
        ComposerWitnessTransition.next(
            state: state,
            newIdentity: identity,
            newBeat: beat ?? state.currentBeat,
            onScreen: onScreen ?? resting(state.displayedIdentity),
            pixelsFor: pixelsFor ?? Self.pixelsFor(_:),
            colorFor: Self.testColor(for:),
            reduceMotion: reduceMotion,
            seed: 11
        )
    }

    private static let openBeat = ComposerWitness.Beat.idle.next(.open)

    /// red mutation: drop the blend arming in `ComposerWitnessTransition
    /// .next` — the ghost then swaps with no frames and this fails.
    @Test func identityChangeBlendsFromTheGhostOnScreen() {
        let start = ComposerWitnessTransition.ViewState(currentBeat: Self.openBeat, displayedIdentity: Self.identityA)
        let blended = Self.next(start, identity: Self.identityB)
        let expected = ComposerWitnessFrames.buildResolveFrames(
            gridA: Self.pixelsFor(Self.identityA), gridB: Self.pixelsFor(Self.identityB), seed: 11
        )
        #expect(blended.displayedIdentity == Self.identityB)
        #expect(blended.previousIdentity == Self.identityA)
        #expect(blended.beatFrames == expected)
        #expect(blended.beatFrames.last?.grid == Self.pixelsFor(Self.identityB))
        #expect(blended.beatFrames.reduce(0) { $0 + $1.ms } == 240, "the blend is 240ms")
        #expect(blended.framesSeq == start.framesSeq + 1, "the blend restarts the frame clock")
        #expect(blended.resolveFromColors?.first?.first == .red, "cells start in the outgoing ghost's colour")
    }

    /// Sean's decision (2026-11-14): changing project no longer flips. The
    /// flip and the drop run off the open beat alone (`ComposerWitnessView
    /// .openedAt` is set only when `currentBeat` changes to an open beat),
    /// so an identity change must leave the beat exactly as the palette
    /// sent it — however many changes follow.
    ///
    /// red mutation: rewrite `currentBeat` on an identity change (as the
    /// old `.resolve` beat did) — the second change then reads as a fresh
    /// open beat and the ghost drops in and flips again.
    @Test func projectChangesNeverReArmTheOpenBeatSoTheyNeverFlip() {
        let opened = ComposerWitnessTransition.ViewState(currentBeat: Self.openBeat, displayedIdentity: .placeholder)
        let first = Self.next(opened, identity: Self.identityA)
        let second = Self.next(first, identity: Self.identityB)
        let third = Self.next(second, identity: .placeholder)
        for state in [first, second, third] {
            #expect(state.currentBeat == Self.openBeat, "a project change is not a beat")
            #expect(!state.beatFrames.isEmpty, "it blends instead")
        }
    }

    /// Placeholder (grey) ↔ a project's ghost blends too.
    @Test func placeholderToAGhostBlends() {
        let start = ComposerWitnessTransition.ViewState(currentBeat: Self.openBeat, displayedIdentity: .placeholder)
        let blended = Self.next(start, identity: Self.identityA)
        #expect(blended.previousIdentity == .placeholder)
        #expect(blended.beatFrames.last?.grid == Self.pixelsFor(Self.identityA))
    }

    /// red mutation (the ef496f46d bug): rebuilding the blend from the
    /// interrupted one's full named target grid discards whatever fraction
    /// had already played. A second identity change arriving mid-blend must
    /// start from EXACTLY the on-screen grid at that instant.
    @Test func identityChangeMidBlendStartsFromTheOnScreenFrameNotTheNamedTarget() {
        let gridA = ComposerWitnessGhost.flicker.pixels
        let gridB = ComposerWitnessGhost.shade.pixels
        let gridC = ComposerWitnessGhost.murk.pixels
        let midBlend = ComposerWitnessFrames.dither(gridA: gridA, gridB: gridB, progress: 0.5, seed: 11)
        let start = ComposerWitnessTransition.ViewState(
            currentBeat: Self.openBeat, displayedIdentity: Self.identityB, previousIdentity: Self.identityA
        )

        let resolved = Self.next(start, identity: Self.identityC, onScreen: (midBlend.grid, 0, midBlend.sourceIsB))
        let fromNamedTarget = ComposerWitnessFrames.buildResolveFrames(gridA: gridB, gridB: gridC, seed: 11)
        let fromOnScreen = ComposerWitnessFrames.buildResolveFrames(gridA: midBlend.grid, gridB: gridC, seed: 11)

        #expect(resolved.beatFrames.first?.grid == fromOnScreen.first?.grid)
        #expect(resolved.beatFrames.first?.grid != fromNamedTarget.first?.grid,
                "restarting from B's full grid instead of the on-screen mid-blend frame is exactly the bug")
    }

    /// The captured per-cell colours must reflect what was ACTUALLY on
    /// screen (a mix of the outgoing and incoming ghost's colours
    /// mid-blend), not a single flat colour.
    @Test func identityChangeMidBlendCapturesEachCellsActualOnScreenColor() {
        let start = ComposerWitnessTransition.ViewState(
            currentBeat: Self.openBeat, displayedIdentity: Self.identityB, previousIdentity: Self.identityA
        )
        let resolved = Self.next(
            start,
            identity: Self.identityC,
            onScreen: (["XX", "XX"], 0, [[true, false], [false, true]]),
            pixelsFor: { _ in ["XX", "XX"] }
        )
        let colors = resolved.resolveFromColors
        #expect(colors?[0][0] == .blue, "true (fromB) cells were already B's (shade) colour")
        #expect(colors?[0][1] == .red, "false cells were still A's (flicker) colour")
        #expect(colors?[1][0] == .red)
        #expect(colors?[1][1] == .blue)
    }

    /// A blend interrupting a beat that had shifted the sprite (e.g. mid
    /// tab-accept hop) must ease that offset back to 0, never snap.
    @Test func identityChangeMidShiftedBeatBlendsTheOffsetBackToZeroWithoutSnapping() {
        let start = ComposerWitnessTransition.ViewState(
            currentBeat: ComposerWitness.Beat.idle.next(.tabAccept), displayedIdentity: Self.identityB
        )
        let resolved = Self.next(
            start, identity: Self.identityC, onScreen: (["XX", "XX"], -2, nil), pixelsFor: { _ in ["XX", "XX"] }
        )
        let offsets = resolved.beatFrames.map(\.cellOffsetY)
        #expect(offsets.first != 0, "the first frame must not snap straight to 0")
        #expect(offsets.first! < 0, "the first frame should still read close to the captured -2 start")
        #expect(offsets.last == 0, "the blend must still land on 0 by its final frame")
    }

    /// Reduce Motion: no blend frames, no mixed colours — the new ghost is
    /// simply there.
    @Test func identityChangeUnderReduceMotionSwapsInstantly() {
        let start = ComposerWitnessTransition.ViewState(currentBeat: Self.openBeat, displayedIdentity: Self.identityA)
        let swapped = Self.next(start, identity: Self.identityB, reduceMotion: true)
        #expect(swapped.displayedIdentity == Self.identityB)
        #expect(swapped.beatFrames.isEmpty)
        #expect(swapped.resolveFromColors == nil)
        #expect(swapped.currentBeat == Self.openBeat)
    }

    /// red mutation (the ef496f46d bug): once launch locks, every identity
    /// change with no fresh beat this update must be a no-op.
    @Test func identityChangeWhileLaunchLockedAndNoFreshBeatIsIgnored() {
        let locked = ComposerWitnessTransition.ViewState(
            currentBeat: ComposerWitness.Beat.idle.next(.launch), displayedIdentity: Self.identityB, isLaunchLocked: true
        )
        let resolved = Self.next(locked, identity: Self.identityC, onScreen: (["..", ".."], 0, nil))
        #expect(resolved == locked, "launch is terminal — an identity change must not blend while locked")
    }

    // MARK: - R3 review: identity and beatTrigger racing in one SwiftUI update

    /// red mutation (the 204fc5bdb bug): launch arriving in the same update
    /// as an identity change must dissolve what was on screen, never the
    /// identity it was about to swap to.
    @Test func identityAndLaunchInTheSameUpdateDissolveFromOnScreenNotTheNewIdentity() {
        let onScreenGrid = ComposerWitnessGhost.flicker.pixels
        let start = ComposerWitnessTransition.ViewState(currentBeat: .idle, displayedIdentity: Self.identityA)
        let resolved = Self.next(
            start,
            identity: .placeholder, // identity ALSO changed in the same update
            beat: start.currentBeat.next(.launch),
            onScreen: (onScreenGrid, 0, nil)
        )

        #expect(resolved.isLaunchLocked == true)
        #expect(resolved.displayedIdentity == Self.identityA, "launch must not apply the bundled identity swap")
        let expectedFirstFrame = ComposerWitnessFrames.dither(
            gridA: onScreenGrid, gridB: ComposerWitnessFrames.emptyGridLike(onScreenGrid), progress: 0.25, seed: 11
        )
        #expect(resolved.beatFrames.first?.grid == expectedFirstFrame.grid,
                "the dissolve must start from what was on screen (ghost A), not the placeholder it was about to swap to")
    }

    /// The dissolve depends only on what's on screen, never on whether an
    /// identity change happened to land in the same update.
    @Test func launchDissolveIsIdenticalWhetherOrNotIdentityAlsoChangedInTheSameUpdate() {
        let onScreen: ComposerWitnessTransition.OnScreen = (ComposerWitnessGhost.flicker.pixels, 0, nil)
        let start = ComposerWitnessTransition.ViewState(currentBeat: .idle, displayedIdentity: Self.identityA)
        let launch = start.currentBeat.next(.launch)

        let withIdentityChange = Self.next(start, identity: .placeholder, beat: launch, onScreen: onScreen)
        let withoutIdentityChange = Self.next(start, identity: Self.identityA, beat: launch, onScreen: onScreen)

        #expect(withIdentityChange.beatFrames == withoutIdentityChange.beatFrames)
        #expect(withIdentityChange.isLaunchLocked == true)
        #expect(withoutIdentityChange.isLaunchLocked == true)
    }

    /// Launch arming while a blend is mid-flight must dissolve from the
    /// partially-blended frame, not from either ghost's pristine grid.
    @Test func launchArmedMidBlendDissolvesFromThePartiallyBlendedFrame() {
        let gridA = ComposerWitnessGhost.flicker.pixels
        let gridB = ComposerWitnessGhost.shade.pixels
        let midBlend = ComposerWitnessFrames.dither(gridA: gridA, gridB: gridB, progress: 0.5, seed: 11)
        let start = ComposerWitnessTransition.ViewState(
            currentBeat: Self.openBeat, displayedIdentity: Self.identityB, previousIdentity: Self.identityA
        )
        let resolved = Self.next(
            start,
            identity: Self.identityB,
            beat: start.currentBeat.next(.launch),
            onScreen: (midBlend.grid, 0, midBlend.sourceIsB)
        )

        let expectedFirstFrame = ComposerWitnessFrames.dither(
            gridA: midBlend.grid, gridB: ComposerWitnessFrames.emptyGridLike(midBlend.grid), progress: 0.25, seed: 11
        )
        let fromNamedTarget = ComposerWitnessFrames.dither(
            gridA: gridB, gridB: ComposerWitnessFrames.emptyGridLike(gridB), progress: 0.25, seed: 11
        )
        #expect(resolved.beatFrames.first?.grid == expectedFirstFrame.grid)
        #expect(resolved.beatFrames.first?.grid != fromNamedTarget.grid, "must not restart from B's pristine grid")
    }

    // MARK: - R4 review: non-launch beat + identity change in one update

    /// Sean's decision (2026-09-13), "always have transitions": a Tab
    /// accept that completes a project name changes the identity in the
    /// SAME update as the beat. The blend plays first, then the hop on the
    /// new, settled grid, as one sequence.
    @Test func tabPlusIdentityChangeInOneUpdateBlendsThenHops() {
        let start = ComposerWitnessTransition.ViewState(currentBeat: .idle, displayedIdentity: Self.identityA)
        let resolved = Self.next(start, identity: Self.identityB, beat: start.currentBeat.next(.tabAccept))

        let blend = ComposerWitnessFrames.buildResolveFrames(
            gridA: Self.pixelsFor(Self.identityA), gridB: Self.pixelsFor(Self.identityB), seed: 11
        )
        let hop = ComposerWitnessFrames.buildTabFrames(grid: Self.pixelsFor(Self.identityB))
        #expect(resolved.displayedIdentity == Self.identityB)
        #expect(resolved.beatFrames == blend + hop)
        #expect(resolved.resolveFromColors != nil, "blend colours carry through the blend portion")
        #expect(resolved.currentBeat.kind == .tabAccept)
    }

    @Test func unknownBranchPlusIdentityChangeInOneUpdateBlendsThenLeans() {
        let start = ComposerWitnessTransition.ViewState(currentBeat: .idle, displayedIdentity: Self.identityA)
        let resolved = Self.next(start, identity: Self.identityB, beat: start.currentBeat.next(.unknownBranch))

        let blend = ComposerWitnessFrames.buildResolveFrames(
            gridA: Self.pixelsFor(Self.identityA), gridB: Self.pixelsFor(Self.identityB), seed: 11
        )
        let lean = ComposerWitnessFrames.buildErrorFrames(grid: Self.pixelsFor(Self.identityB))
        #expect(resolved.beatFrames == blend + lean)
    }

    /// Reduce Motion: a beat bundled with an identity change is an instant
    /// swap — the beat itself still plays, on the new identity, with no
    /// blend ahead of it.
    @Test func tabPlusIdentityChangeUnderReduceMotionIsAnInstantSwapWithNoBlend() {
        let start = ComposerWitnessTransition.ViewState(currentBeat: .idle, displayedIdentity: Self.identityA)
        let resolved = Self.next(start, identity: Self.identityB, beat: start.currentBeat.next(.tabAccept), reduceMotion: true)

        #expect(resolved.displayedIdentity == Self.identityB, "identity swaps instantly")
        #expect(resolved.resolveFromColors == nil)
        #expect(resolved.beatFrames.allSatisfy { $0.sourceIsB == nil }, "nothing mixes two identities' colours")
        #expect(resolved.beatFrames == ComposerWitnessFrames.buildTabFrames(grid: Self.pixelsFor(Self.identityB)))
    }

    /// The open beat is its own transition (the drop): an identity change
    /// bundled with it swaps instantly, and it ends a blend in flight.
    @Test func openSwapsIdentityInstantlyWithNoBlend() {
        let blending = Self.next(
            ComposerWitnessTransition.ViewState(currentBeat: .idle, displayedIdentity: Self.identityA),
            identity: Self.identityB
        )
        let opened = Self.next(blending, identity: Self.identityC, beat: blending.currentBeat.next(.open))
        #expect(opened.currentBeat.kind == .open)
        #expect(opened.displayedIdentity == Self.identityC)
        #expect(opened.beatFrames.isEmpty, "the drop is a transform, not grid frames")
        #expect(opened.resolveFromColors == nil)
        #expect(opened.previousIdentity == nil)
    }

    // MARK: - R4 review: initial-mount beat (onAppear feeding `next()`)

    /// `ComposerWitnessView` feeds its mount-time `(identity, beatTrigger)`
    /// through the same `next(...)` its `onChange` uses. Applying the SAME
    /// already-current `(identity, beat)` a second time must be a no-op, so
    /// whichever of `onAppear`/`onChange` fires first does the real work and
    /// the other can never double-play it (or restart a clock).
    @Test func reapplyingTheSameIdentityAndBeatIsANoOp() {
        let armed = Self.next(
            ComposerWitnessTransition.ViewState(currentBeat: .idle, displayedIdentity: .placeholder),
            identity: Self.identityA,
            beat: Self.openBeat
        )
        #expect(Self.next(armed, identity: Self.identityA, beat: armed.currentBeat) == armed,
                "re-delivering the same (identity, beat) must not re-arm or reset anything")

        let blended = Self.next(armed, identity: Self.identityB)
        #expect(Self.next(blended, identity: Self.identityB) == blended)
    }

    // MARK: - Witness sprite geometry (gray mesh-line fix)

    /// red mutation: drop the `.rounded()` pixel-snap in
    /// `WitnessSpriteGeometry.cellRect` (or widen a cell independently of
    /// its neighbour's shared edge) — adjacent cells stop sharing an exact
    /// edge and these tests fail.
    private static let meshFixSizes: [CGFloat] = [12, 18, 24, 30, 36, 42, 48, 54, 60, 66, 72]
    private static let gridDimension = 12

    private static func isMultiple(of edge: CGFloat, scale: CGFloat, tolerance: CGFloat = 1e-9) -> Bool {
        let scaled = edge * scale
        return abs(scaled - scaled.rounded()) < tolerance
    }

    @Test func adjacentCellsShareExactEdgesAtEveryWitnessSize() {
        for size in Self.meshFixSizes {
            for scale: CGFloat in size == 30 || size == 48 ? [1, 2] : [2] {
                let dim = Self.gridDimension
                let sizeCG = CGSize(width: size, height: size)

                // Horizontal adjacency, and every edge on the pixel grid.
                for row in 0..<dim {
                    for col in 0..<(dim - 1) {
                        let a = WitnessSpriteGeometry.cellRect(
                            row: row, col: col, rows: dim, cols: dim,
                            size: sizeCG, cellOffsetY: 0, scale: scale
                        )
                        let b = WitnessSpriteGeometry.cellRect(
                            row: row, col: col + 1, rows: dim, cols: dim,
                            size: sizeCG, cellOffsetY: 0, scale: scale
                        )
                        #expect(a.maxX == b.minX, "size \(size) scale \(scale) row \(row) col \(col): horizontal seam gap/overlap")
                        #expect(Self.isMultiple(of: a.minX, scale: scale))
                        #expect(Self.isMultiple(of: a.maxX, scale: scale))
                    }
                }

                // Vertical adjacency.
                for row in 0..<(dim - 1) {
                    for col in 0..<dim {
                        let a = WitnessSpriteGeometry.cellRect(
                            row: row, col: col, rows: dim, cols: dim,
                            size: sizeCG, cellOffsetY: 0, scale: scale
                        )
                        let b = WitnessSpriteGeometry.cellRect(
                            row: row + 1, col: col, rows: dim, cols: dim,
                            size: sizeCG, cellOffsetY: 0, scale: scale
                        )
                        #expect(a.maxY == b.minY, "size \(size) scale \(scale) row \(row) col \(col): vertical seam gap/overlap")
                        #expect(Self.isMultiple(of: a.minY, scale: scale))
                        #expect(Self.isMultiple(of: a.maxY, scale: scale))
                    }
                }

                // Union spans exactly 0...size on both axes.
                let first = WitnessSpriteGeometry.cellRect(
                    row: 0, col: 0, rows: dim, cols: dim, size: sizeCG, cellOffsetY: 0, scale: scale
                )
                let last = WitnessSpriteGeometry.cellRect(
                    row: dim - 1, col: dim - 1, rows: dim, cols: dim, size: sizeCG, cellOffsetY: 0, scale: scale
                )
                #expect(first.minX == 0)
                #expect(first.minY == 0)
                #expect(last.maxX == size)
                #expect(last.maxY == size)
            }
        }
    }

    /// The default 48pt ghost: every cell is exactly 4pt square, on whole
    /// pixels at 1x and 2x, so it draws crisp at rest.
    @Test func size48CellsAreExactlyFourPointsAtOneXAndTwoX() {
        let dim = Self.gridDimension
        let size = ComposerWitnessSize.defaultSize
        #expect(size == 48)
        for scale: CGFloat in [1, 2] {
            for row in 0..<dim {
                for col in 0..<dim {
                    let rect = WitnessSpriteGeometry.cellRect(
                        row: row, col: col, rows: dim, cols: dim,
                        size: CGSize(width: size, height: size), cellOffsetY: 0, scale: scale
                    )
                    #expect(rect == CGRect(x: CGFloat(col * 4), y: CGFloat(row * 4), width: 4, height: 4))
                }
            }
        }
    }

    /// At size 24 (24pt / 12 cols = exactly 2pt cells), snapping must be a
    /// no-op — this pins pixel-for-pixel parity with the pre-fix output at
    /// the one size that already happened to land on the pixel grid.
    @Test func size24CellsAreExactlyTwoByTwoAtScaleTwo() {
        let dim = Self.gridDimension
        let sizeCG = CGSize(width: 24, height: 24)
        for row in 0..<dim {
            for col in 0..<dim {
                let rect = WitnessSpriteGeometry.cellRect(
                    row: row, col: col, rows: dim, cols: dim,
                    size: sizeCG, cellOffsetY: 0, scale: 2
                )
                #expect(rect == CGRect(x: CGFloat(col * 2), y: CGFloat(row * 2), width: 2, height: 2))
            }
        }
    }
}

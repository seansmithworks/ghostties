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

    // MARK: - Identity transitions: the flip

    private static let identityA = ComposerWitness.Identity.ghost(.flicker)
    private static let identityB = ComposerWitness.Identity.ghost(.shade)
    private static let identityC = ComposerWitness.Identity.ghost(.murk)
    private static let flipMs = ComposerWitnessFrames.flipDurationMs
    /// No flip running (any value at or past the flip's end).
    private static let noFlip = 10_000

    private static func pixelsFor(_ identity: ComposerWitness.Identity) -> [String] {
        switch identity {
        case .placeholder: return ComposerWitnessPlaceholder.pixels
        case .ghost(let ghost): return ghost.pixels
        }
    }

    private static func resting(_ identity: ComposerWitness.Identity) -> (grid: [String], cellOffsetY: Int) {
        (pixelsFor(identity), 0)
    }

    private static func next(
        _ state: ComposerWitnessTransition.ViewState,
        identity: ComposerWitness.Identity,
        beat: ComposerWitness.Beat? = nil,
        onScreen: (grid: [String], cellOffsetY: Int)? = nil,
        flipElapsedMs: Int = noFlip,
        reduceMotion: Bool = false
    ) -> ComposerWitnessTransition.ViewState {
        ComposerWitnessTransition.next(
            state: state,
            newIdentity: identity,
            newBeat: beat ?? state.currentBeat,
            onScreen: onScreen ?? resting(state.displayedIdentity),
            flipElapsedMs: flipElapsedMs,
            pixelsFor: Self.pixelsFor(_:),
            reduceMotion: reduceMotion,
            seed: 11
        )
    }

    /// red mutation: drop the `identityChanged` flip arming in
    /// `ComposerWitnessTransition.next` — the ghost then swaps with no flip
    /// and every assertion below fails.
    @Test func identityChangeFlipsFromTheOutgoingIdentity() {
        let start = ComposerWitnessTransition.ViewState(currentBeat: .idle, displayedIdentity: Self.identityA)
        let flipped = Self.next(start, identity: Self.identityB)
        #expect(flipped.displayedIdentity == Self.identityB)
        #expect(flipped.flipFrom == Self.identityA)
        #expect(flipped.flipSeq == start.flipSeq + 1, "a new flip restarts the flip clock")
        #expect(flipped.flipStartMs == 0)
        #expect(flipped.currentBeat == start.currentBeat, "a flip is not a beat")
        #expect(ComposerWitnessTransition.visibleIdentity(state: flipped, flipElapsedMs: 0, reduceMotion: false) == Self.identityA)
        #expect(ComposerWitnessTransition.visibleIdentity(state: flipped, flipElapsedMs: Self.flipMs / 2, reduceMotion: false) == Self.identityB)
    }

    /// Placeholder (grey) ↔ a project's ghost flips too.
    @Test func placeholderToAGhostFlips() {
        let start = ComposerWitnessTransition.ViewState(currentBeat: .idle, displayedIdentity: .placeholder)
        let flipped = Self.next(start, identity: Self.identityA)
        #expect(flipped.flipFrom == .placeholder)
        let back = Self.next(flipped, identity: .placeholder, flipElapsedMs: Self.noFlip)
        #expect(back.flipFrom == Self.identityA)
        #expect(back.flipSeq == flipped.flipSeq + 1)
    }

    /// A second change while the old ghost is still turning away keeps the
    /// same clock and shows the newest ghost at the midpoint — no jump.
    @Test func identityChangeInTheFlipsFirstHalfRetargetsWithoutRestarting() {
        let flipping = ComposerWitnessTransition.ViewState(
            currentBeat: .idle, displayedIdentity: Self.identityB, flipFrom: Self.identityA, flipSeq: 1
        )
        let retargeted = Self.next(flipping, identity: Self.identityC, flipElapsedMs: Self.flipMs / 4)
        #expect(retargeted.displayedIdentity == Self.identityC)
        #expect(retargeted.flipFrom == Self.identityA)
        #expect(retargeted.flipSeq == 1, "the flip clock keeps running")
    }

    /// A change while the new ghost is turning back in restarts the flip at
    /// the mirrored time, where the width is the same, so nothing jumps.
    @Test func identityChangeInTheFlipsSecondHalfRestartsAtTheSameWidth() {
        let elapsed = Self.flipMs * 3 / 4
        let flipping = ComposerWitnessTransition.ViewState(
            currentBeat: .idle, displayedIdentity: Self.identityB, flipFrom: Self.identityA, flipSeq: 1
        )
        let restarted = Self.next(flipping, identity: Self.identityC, flipElapsedMs: elapsed)
        #expect(restarted.displayedIdentity == Self.identityC)
        #expect(restarted.flipFrom == Self.identityB, "B was on screen; it turns away now")
        #expect(restarted.flipSeq == 2)
        let widthBefore = ComposerWitnessFrames.flipTransform(elapsedMs: elapsed, reduceMotion: false).scaleX
        let widthAfter = ComposerWitnessFrames.flipTransform(elapsedMs: restarted.flipStartMs, reduceMotion: false).scaleX
        #expect(abs(widthBefore - widthAfter) < 1e-6)
        #expect(ComposerWitnessTransition.visibleIdentity(state: restarted, flipElapsedMs: restarted.flipStartMs, reduceMotion: false) == Self.identityB)
    }

    @Test func identityChangeUnderReduceMotionSwapsInstantlyWithNoFlip() {
        let start = ComposerWitnessTransition.ViewState(currentBeat: .idle, displayedIdentity: Self.identityA)
        let swapped = Self.next(start, identity: Self.identityB, reduceMotion: true)
        #expect(swapped.displayedIdentity == Self.identityB)
        #expect(swapped.flipFrom == nil)
        #expect(ComposerWitnessTransition.visibleIdentity(state: swapped, flipElapsedMs: 0, reduceMotion: true) == Self.identityB)
    }

    /// red mutation (the ef496f46d bug): once launch locks, every identity
    /// change with no fresh beat this update must be a no-op.
    @Test func identityChangeWhileLaunchLockedAndNoFreshBeatIsIgnored() {
        let locked = ComposerWitnessTransition.ViewState(
            currentBeat: ComposerWitness.Beat.idle.next(.launch), displayedIdentity: Self.identityB, isLaunchLocked: true
        )
        let resolved = Self.next(locked, identity: Self.identityC, onScreen: (["..", ".."], 0))
        #expect(resolved == locked, "launch is terminal — an identity change must not flip while locked")
    }

    // MARK: - R3 review: identity and beatTrigger racing in one SwiftUI update

    /// red mutation (the 204fc5bdb bug): launch arriving in the same update
    /// as an identity change must dissolve what was on screen, never the
    /// identity it was about to swap to — and must not flip.
    @Test func identityAndLaunchInTheSameUpdateDissolveFromOnScreenAndDoNotFlip() {
        let onScreenGrid = ComposerWitnessGhost.flicker.pixels
        let start = ComposerWitnessTransition.ViewState(currentBeat: .idle, displayedIdentity: Self.identityA)
        let resolved = Self.next(
            start,
            identity: .placeholder, // identity ALSO changed in the same update
            beat: start.currentBeat.next(.launch),
            onScreen: (onScreenGrid, 0)
        )

        #expect(resolved.isLaunchLocked == true)
        #expect(resolved.displayedIdentity == Self.identityA, "launch must not apply the bundled identity swap")
        #expect(resolved.flipFrom == nil, "launch must not flip")
        #expect(resolved.flipSeq == start.flipSeq)
        let expectedFirstFrame = ComposerWitnessFrames.dither(
            gridA: onScreenGrid, gridB: ComposerWitnessFrames.emptyGridLike(onScreenGrid), progress: 0.25, seed: 11
        )
        #expect(resolved.beatFrames.first?.grid == expectedFirstFrame.grid,
                "the dissolve must start from what was on screen (ghost A), not the placeholder it was about to swap to")
    }

    /// The dissolve depends only on what's on screen, never on whether an
    /// identity change happened to land in the same update.
    @Test func launchDissolveIsIdenticalWhetherOrNotIdentityAlsoChangedInTheSameUpdate() {
        let onScreen = (grid: ComposerWitnessGhost.flicker.pixels, cellOffsetY: 0)
        let start = ComposerWitnessTransition.ViewState(currentBeat: .idle, displayedIdentity: Self.identityA)
        let launch = start.currentBeat.next(.launch)

        let withIdentityChange = Self.next(start, identity: .placeholder, beat: launch, onScreen: onScreen)
        let withoutIdentityChange = Self.next(start, identity: Self.identityA, beat: launch, onScreen: onScreen)

        #expect(withIdentityChange.beatFrames == withoutIdentityChange.beatFrames)
        #expect(withIdentityChange.isLaunchLocked == true)
        #expect(withoutIdentityChange.isLaunchLocked == true)
    }

    /// Launch during a flip's first half launches the ghost that is on
    /// screen (the outgoing one), and the turn finishes on that same ghost
    /// instead of swapping mid-dissolve.
    @Test func launchMidFlipLaunchesTheGhostOnScreenAndNeverSwaps() {
        let flipping = ComposerWitnessTransition.ViewState(
            currentBeat: .idle, displayedIdentity: Self.identityB, flipFrom: Self.identityA, flipSeq: 1
        )
        let launched = Self.next(
            flipping,
            identity: Self.identityB,
            beat: flipping.currentBeat.next(.launch),
            onScreen: Self.resting(Self.identityA),
            flipElapsedMs: Self.flipMs / 4
        )
        #expect(launched.isLaunchLocked)
        #expect(launched.displayedIdentity == Self.identityA)
        #expect(launched.flipFrom == Self.identityA, "the turn finishes on the same ghost")
        #expect(launched.flipSeq == 1, "launch never starts a flip")
        for ms in [Self.flipMs / 4, Self.flipMs / 2, Self.flipMs] {
            #expect(ComposerWitnessTransition.visibleIdentity(state: launched, flipElapsedMs: ms, reduceMotion: false) == Self.identityA)
        }
    }

    // MARK: - R4 review: non-launch beat + identity change in one update

    /// Sean's decision (2026-09-13), "always have transitions": a Tab
    /// accept that completes a project name changes the identity in the
    /// SAME update as the beat. The flip plays first; the hop's frames wait
    /// on the new resting grid until the flip ends.
    @Test func tabPlusIdentityChangeInOneUpdateFlipsThenHops() {
        let start = ComposerWitnessTransition.ViewState(currentBeat: .idle, displayedIdentity: Self.identityA)
        let resolved = Self.next(start, identity: Self.identityB, beat: start.currentBeat.next(.tabAccept))

        let hop = ComposerWitnessFrames.buildTabFrames(grid: Self.pixelsFor(Self.identityB))
        #expect(resolved.displayedIdentity == Self.identityB)
        #expect(resolved.flipFrom == Self.identityA)
        #expect(resolved.beatFrames.count == hop.count + 1)
        #expect(resolved.beatFrames.first == ComposerWitnessFrames.WitnessFrame(
            grid: Self.pixelsFor(Self.identityB), cellOffsetY: 0, ms: Self.flipMs
        ), "the hop waits out the flip on the new resting grid")
        #expect(Array(resolved.beatFrames.dropFirst()) == hop)
    }

    @Test func unknownBranchPlusIdentityChangeInOneUpdateFlipsThenLeans() {
        let start = ComposerWitnessTransition.ViewState(currentBeat: .idle, displayedIdentity: Self.identityA)
        let resolved = Self.next(start, identity: Self.identityB, beat: start.currentBeat.next(.unknownBranch))

        let lean = ComposerWitnessFrames.buildErrorFrames(grid: Self.pixelsFor(Self.identityB))
        #expect(resolved.flipFrom == Self.identityA)
        #expect(resolved.beatFrames.first?.ms == Self.flipMs)
        #expect(Array(resolved.beatFrames.dropFirst()) == lean)
    }

    /// Reduce Motion: a beat bundled with an identity change is an instant
    /// swap — the beat itself still plays, on the new identity, with no wait.
    @Test func tabPlusIdentityChangeUnderReduceMotionIsAnInstantSwapWithNoFlip() {
        let start = ComposerWitnessTransition.ViewState(currentBeat: .idle, displayedIdentity: Self.identityA)
        let resolved = Self.next(start, identity: Self.identityB, beat: start.currentBeat.next(.tabAccept), reduceMotion: true)

        #expect(resolved.displayedIdentity == Self.identityB, "identity swaps instantly")
        #expect(resolved.flipFrom == nil)
        #expect(resolved.beatFrames == ComposerWitnessFrames.buildTabFrames(grid: Self.pixelsFor(Self.identityB)))
    }

    /// The open beat is its own transition (the drop): an identity change
    /// bundled with it swaps instantly, and it cancels a flip in flight.
    @Test func openSwapsIdentityInstantlyAndCancelsAFlip() {
        let flipping = ComposerWitnessTransition.ViewState(
            currentBeat: .idle, displayedIdentity: Self.identityB, flipFrom: Self.identityA, flipSeq: 1
        )
        let opened = Self.next(
            flipping, identity: Self.identityC, beat: flipping.currentBeat.next(.open), flipElapsedMs: Self.flipMs / 4
        )
        #expect(opened.currentBeat.kind == .open)
        #expect(opened.displayedIdentity == Self.identityC)
        #expect(opened.flipFrom == nil)
        #expect(opened.beatFrames.isEmpty, "the drop is a transform, not grid frames")
    }

    // MARK: - R4 review: initial-mount beat (onAppear feeding `next()`)

    /// `ComposerWitnessView` feeds its mount-time `(identity, beatTrigger)`
    /// through the same `next(...)` its `onChange` uses. Applying the SAME
    /// already-current `(identity, beat)` a second time must be a no-op, so
    /// whichever of `onAppear`/`onChange` fires first does the real work and
    /// the other can never double-play it.
    @Test func reapplyingTheSameIdentityAndBeatIsANoOp() {
        let armed = Self.next(
            ComposerWitnessTransition.ViewState(currentBeat: .idle, displayedIdentity: .placeholder),
            identity: Self.identityA,
            beat: ComposerWitness.Beat.idle.next(.open)
        )
        let reapplied = Self.next(armed, identity: Self.identityA, beat: armed.currentBeat, flipElapsedMs: 0)
        #expect(reapplied == armed, "re-delivering the same (identity, beat) must not re-arm or reset anything")

        let flipped = Self.next(armed, identity: Self.identityB)
        #expect(Self.next(flipped, identity: Self.identityB, flipElapsedMs: 30) == flipped)
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

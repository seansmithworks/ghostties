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

    private static func pixelsFor(_ identity: ComposerWitness.Identity) -> [String] {
        switch identity {
        case .placeholder: return ComposerWitnessPlaceholder.pixels
        case .ghost(let ghost): return ghost.pixels
        }
    }

    private static func makeState(
        beat: ComposerWitness.Beat = .idle,
        displayed: ComposerWitness.Identity,
        previous: ComposerWitness.Identity? = nil,
        frames: [ComposerWitnessFrames.WitnessFrame] = [],
        colors: [[Color]]? = nil,
        locked: Bool = false
    ) -> ComposerWitnessTransition.ViewState {
        ComposerWitnessTransition.ViewState(
            currentBeat: beat,
            displayedIdentity: displayed,
            previousIdentity: previous,
            beatFrames: frames,
            resolveFromColors: colors,
            isLaunchLocked: locked
        )
    }

    /// red mutation (the ef496f46d bug): the identity handler rebuilt
    /// `buildResolveFrames` from the interrupted beat's full named target
    /// grid, discarding whatever fraction of the in-flight morph had
    /// already played. A second identity change arriving mid-morph must
    /// instead start from EXACTLY the on-screen grid at that instant.
    @Test func identityChangeMidMorphStartsFromTheOnScreenFrameNotTheNamedTarget() {
        let gridA = ComposerWitnessGhost.flicker.pixels
        let gridB = ComposerWitnessGhost.shade.pixels
        let gridC = ComposerWitnessGhost.murk.pixels

        // Simulate "midway through an A→B morph": a real dither frame that
        // is neither A nor B verbatim.
        let midMorph = ComposerWitnessFrames.dither(gridA: gridA, gridB: gridB, progress: 0.5, seed: 11)
        let onScreen: (grid: [String], cellOffsetY: Int, sourceIsB: [[Bool]]?) =
            (midMorph.grid, 0, midMorph.sourceIsB)
        let startState = Self.makeState(beat: .idle.next(.resolve), displayed: Self.identityB, previous: Self.identityA)

        let resolved = ComposerWitnessTransition.next(
            state: startState,
            newIdentity: Self.identityC,
            newBeat: startState.currentBeat, // beat unchanged — only identity changes
            onScreen: onScreen,
            pixelsFor: Self.pixelsFor(_:),
            colorFor: Self.testColor(for:),
            reduceMotion: false,
            seed: 11
        )
        let fromNamedTarget = ComposerWitnessFrames.buildResolveFrames(gridA: gridB, gridB: gridC, seed: 11)
        let fromOnScreen = ComposerWitnessFrames.buildResolveFrames(gridA: midMorph.grid, gridB: gridC, seed: 11)

        #expect(resolved.beatFrames.first?.grid == fromOnScreen.first?.grid)
        #expect(resolved.beatFrames.first?.grid != fromNamedTarget.first?.grid,
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
        let startState = Self.makeState(beat: .idle.next(.resolve), displayed: Self.identityB, previous: Self.identityA)

        let resolved = ComposerWitnessTransition.next(
            state: startState,
            newIdentity: Self.identityC,
            newBeat: startState.currentBeat,
            onScreen: onScreen,
            pixelsFor: { _ in ["XX", "XX"] },
            colorFor: Self.testColor(for:),
            reduceMotion: false,
            seed: 11
        )
        let colors = resolved.resolveFromColors
        #expect(colors?[0][0] == .blue, "true (fromB) cells were already B's (shade) colour")
        #expect(colors?[0][1] == .red, "false cells were still A's (flicker) colour")
        #expect(colors?[1][0] == .red)
        #expect(colors?[1][1] == .blue)
    }

    /// A resolve interrupting a beat that had shifted the sprite (e.g.
    /// mid tab-accept hop) must blend that offset back to 0 across the new
    /// morph, never snap to 0 on frame one.
    @Test func identityChangeMidShiftedBeatBlendsTheOffsetBackToZeroWithoutSnapping() {
        let onScreen: (grid: [String], cellOffsetY: Int, sourceIsB: [[Bool]]?) = (["XX", "XX"], -2, nil)
        let startState = Self.makeState(beat: .idle.next(.tabAccept), displayed: Self.identityB)

        let resolved = ComposerWitnessTransition.next(
            state: startState,
            newIdentity: Self.identityC,
            newBeat: startState.currentBeat,
            onScreen: onScreen,
            pixelsFor: { _ in ["XX", "XX"] },
            colorFor: Self.testColor(for:),
            reduceMotion: false,
            seed: 11
        )
        let offsets = resolved.beatFrames.map(\.cellOffsetY)
        #expect(offsets.first != 0, "the first frame must not snap straight to 0")
        #expect(offsets.first! < 0, "the first frame should still read close to the captured -2 start")
        #expect(offsets.last == 0, "the morph must still land on 0 by its final frame")
    }

    /// red mutation (the ef496f46d bug): the identity handler always
    /// rearmed a `.resolve` beat unconditionally, even while `.launch` was
    /// playing/held — overriding "ends empty and stays empty". Once locked,
    /// every identity change with no fresh beat this update must be a no-op.
    @Test func identityChangeWhileLaunchLockedAndNoFreshBeatIsIgnored() {
        let startState = Self.makeState(beat: .idle.next(.launch), displayed: Self.identityB, previous: Self.identityA, locked: true)
        let onScreen: (grid: [String], cellOffsetY: Int, sourceIsB: [[Bool]]?) = (["..", ".."], 0, nil)

        let resolved = ComposerWitnessTransition.next(
            state: startState,
            newIdentity: Self.identityC,
            newBeat: startState.currentBeat, // no fresh beat this update
            onScreen: onScreen,
            pixelsFor: { _ in ["XX", "XX"] },
            colorFor: Self.testColor(for:),
            reduceMotion: false,
            seed: 11
        )
        #expect(resolved == startState, "launch is terminal — an identity change must not re-arm a resolve while locked")
    }

    // MARK: - R3 review: identity and beatTrigger racing in one SwiftUI update

    /// red mutation (the 204fc5bdb bug): two separate `onChange` handlers
    /// had no defined order when `identity` and `beatTrigger` changed in the
    /// SAME transaction (the real launch path —
    /// `SessionComposerStore.precommit` clears `searchText`, then
    /// `SessionComposerPalette.commit` arms `.launch`). If identity's
    /// handler ran first, launch built its dissolve from the JUST-SWAPPED
    /// identity instead of what was actually on screen.
    @Test func identityAndLaunchInTheSameUpdateDissolveFromOnScreenNotTheNewIdentity() {
        let onScreenGrid = ComposerWitnessGhost.flicker.pixels
        let onScreen: (grid: [String], cellOffsetY: Int, sourceIsB: [[Bool]]?) = (onScreenGrid, 0, nil)
        let startState = Self.makeState(beat: .idle, displayed: Self.identityA)
        let launchBeat = startState.currentBeat.next(.launch)

        let resolved = ComposerWitnessTransition.next(
            state: startState,
            newIdentity: .placeholder, // identity ALSO changed in the same update
            newBeat: launchBeat,
            onScreen: onScreen,
            pixelsFor: Self.pixelsFor(_:),
            colorFor: Self.testColor(for:),
            reduceMotion: false,
            seed: 11
        )

        #expect(resolved.isLaunchLocked == true)
        #expect(resolved.displayedIdentity == Self.identityA, "launch must not apply the bundled identity swap")
        let expectedFirstFrame = ComposerWitnessFrames.dither(
            gridA: onScreenGrid, gridB: ComposerWitnessFrames.emptyGridLike(onScreenGrid), progress: 0.25, seed: 11
        )
        #expect(resolved.beatFrames.first?.grid == expectedFirstFrame.grid,
                "the dissolve must start from what was on screen (ghost A), not the placeholder it was about to swap to")
    }

    /// Same on-screen state and the same launch arming, once with a bundled
    /// identity change and once without — the dissolve itself must be
    /// identical either way, proving it depends only on what's on screen,
    /// never on whether an identity change happened to land in the same
    /// update.
    @Test func launchDissolveIsIdenticalWhetherOrNotIdentityAlsoChangedInTheSameUpdate() {
        let onScreenGrid = ComposerWitnessGhost.flicker.pixels
        let onScreen: (grid: [String], cellOffsetY: Int, sourceIsB: [[Bool]]?) = (onScreenGrid, 0, nil)
        let startState = Self.makeState(beat: .idle, displayed: Self.identityA)
        let launchBeat = startState.currentBeat.next(.launch)

        let withIdentityChange = ComposerWitnessTransition.next(
            state: startState, newIdentity: .placeholder, newBeat: launchBeat,
            onScreen: onScreen, pixelsFor: Self.pixelsFor(_:), colorFor: Self.testColor(for:),
            reduceMotion: false, seed: 11
        )
        let withoutIdentityChange = ComposerWitnessTransition.next(
            state: startState, newIdentity: startState.displayedIdentity, newBeat: launchBeat,
            onScreen: onScreen, pixelsFor: Self.pixelsFor(_:), colorFor: Self.testColor(for:),
            reduceMotion: false, seed: 11
        )

        #expect(withIdentityChange.beatFrames == withoutIdentityChange.beatFrames)
        #expect(withIdentityChange.isLaunchLocked == true)
        #expect(withoutIdentityChange.isLaunchLocked == true)
    }

    /// Launch arming while a resolve morph is already mid-flight must
    /// dissolve from the partially-morphed frame, not from either ghost's
    /// pristine named grid.
    @Test func launchArmedMidResolveMorphDissolvesFromThePartiallyMorphedFrame() {
        let gridA = ComposerWitnessGhost.flicker.pixels
        let gridB = ComposerWitnessGhost.shade.pixels
        let midMorph = ComposerWitnessFrames.dither(gridA: gridA, gridB: gridB, progress: 0.5, seed: 11)
        let onScreen: (grid: [String], cellOffsetY: Int, sourceIsB: [[Bool]]?) =
            (midMorph.grid, 0, midMorph.sourceIsB)
        let startState = Self.makeState(beat: .idle.next(.resolve), displayed: Self.identityB, previous: Self.identityA)
        let launchBeat = startState.currentBeat.next(.launch)

        let resolved = ComposerWitnessTransition.next(
            state: startState,
            newIdentity: startState.displayedIdentity,
            newBeat: launchBeat,
            onScreen: onScreen,
            pixelsFor: Self.pixelsFor(_:),
            colorFor: Self.testColor(for:),
            reduceMotion: false,
            seed: 11
        )

        let expectedFirstFrame = ComposerWitnessFrames.dither(
            gridA: midMorph.grid, gridB: ComposerWitnessFrames.emptyGridLike(midMorph.grid), progress: 0.25, seed: 11
        )
        let fromNamedTarget = ComposerWitnessFrames.dither(
            gridA: gridB, gridB: ComposerWitnessFrames.emptyGridLike(gridB), progress: 0.25, seed: 11
        )
        #expect(resolved.beatFrames.first?.grid == expectedFirstFrame.grid)
        #expect(resolved.beatFrames.first?.grid != fromNamedTarget.grid, "must not restart from B's pristine grid")
    }

    // MARK: - R4 review: non-launch beat + identity change in one update

    /// The real trigger: `ComposerGhostTextField.swift:1018` sets
    /// `parent.query` synchronously, then `:1024` fires
    /// `.acceptedGhost` — `SessionComposerPalette.swift:3018` arms
    /// `.tabAccept` from that same call, so a Tab-accept that completes a
    /// project name changes `commandProject` (and so `identity`) in the
    /// SAME update as the beat. Rule: a non-launch beat plays IMMEDIATELY
    /// on the NEW identity — no queued morph, no added latency on a
    /// keyboard action.
    @Test func tabPlusIdentityChangeInOneUpdatePlaysOnTheNewIdentityImmediately() {
        let startState = Self.makeState(beat: .idle, displayed: Self.identityA)
        let onScreen: (grid: [String], cellOffsetY: Int, sourceIsB: [[Bool]]?) =
            (Self.pixelsFor(Self.identityA), 0, nil)

        let resolved = ComposerWitnessTransition.next(
            state: startState,
            newIdentity: Self.identityB,
            newBeat: startState.currentBeat.next(.tabAccept),
            onScreen: onScreen,
            pixelsFor: Self.pixelsFor(_:),
            colorFor: Self.testColor(for:),
            reduceMotion: false,
            seed: 11
        )

        let expectedFrames = ComposerWitnessFrames.buildTabFrames(grid: Self.pixelsFor(Self.identityB))
        #expect(resolved.displayedIdentity == Self.identityB)
        #expect(resolved.beatFrames.first?.grid == expectedFrames.first?.grid, "frame 0 must be squash(newGrid)")
        #expect(resolved.beatFrames.last?.grid == Self.pixelsFor(Self.identityB), "the rest frame must be the new grid")
        #expect(resolved.resolveFromColors == nil, "no queued morph — a single flat colour (the new identity's) via primaryColor")
    }

    /// Same rule for `.unknownBranch`.
    @Test func unknownBranchPlusIdentityChangeInOneUpdatePlaysOnTheNewIdentityImmediately() {
        let startState = Self.makeState(beat: .idle, displayed: Self.identityA)
        let onScreen: (grid: [String], cellOffsetY: Int, sourceIsB: [[Bool]]?) =
            (Self.pixelsFor(Self.identityA), 0, nil)

        let resolved = ComposerWitnessTransition.next(
            state: startState,
            newIdentity: Self.identityB,
            newBeat: startState.currentBeat.next(.unknownBranch),
            onScreen: onScreen,
            pixelsFor: Self.pixelsFor(_:),
            colorFor: Self.testColor(for:),
            reduceMotion: false,
            seed: 11
        )

        let expectedFrames = ComposerWitnessFrames.buildErrorFrames(grid: Self.pixelsFor(Self.identityB))
        #expect(resolved.displayedIdentity == Self.identityB)
        #expect(resolved.beatFrames.first?.grid == expectedFrames.first?.grid, "frame 0 must be lean(squint(newGrid))")
        #expect(resolved.beatFrames.last?.grid == Self.pixelsFor(Self.identityB), "the rest frame must be the new grid")
        #expect(resolved.resolveFromColors == nil)
    }

    // MARK: - R4 review: initial-mount beat (onAppear feeding `next()`)

    /// `ComposerWitnessView` now feeds its mount-time `(identity,
    /// beatTrigger)` through the same `next(...)` its `onChange` uses (see
    /// `ComposerWitnessView.apply(_:)`), covering the case where
    /// `beatTrigger` is already `.open` the very first time the view's body
    /// runs (the palette's `onAppear` — `SessionComposerPalette.swift
    /// :1452` — can run before this view's subtree is even inserted).
    /// Can't construct a View in a pure test, so this proves the property
    /// that makes doing so at BOTH `onAppear` and `onChange` safe: applying
    /// the SAME already-current `(identity, beat)` a second time is a
    /// no-op, so whichever of the two call sites fires first does the real
    /// work and the other can never double-play it.
    ///
    /// red mutation: hardcode `isLaunchLocked: false` unconditionally on
    /// the shared (no beat/identity changed) return path instead of leaving
    /// it — this test's second `#expect` would still pass (`false ==
    /// false`), but drop the `!beatChanged` guard on the earlier
    /// launch-locked early return and the FIRST `#expect` below fails
    /// instead (a locked idle state stops being idempotent).
    @Test func reapplyingTheSameIdentityAndBeatIsANoOp() {
        let armed = ComposerWitnessTransition.next(
            state: Self.makeState(beat: .idle, displayed: .placeholder),
            newIdentity: Self.identityA,
            newBeat: ComposerWitness.Beat.idle.next(.open),
            onScreen: (Self.pixelsFor(.placeholder), 0, nil),
            pixelsFor: Self.pixelsFor(_:),
            colorFor: Self.testColor(for:),
            reduceMotion: false,
            seed: 11
        )

        let reapplied = ComposerWitnessTransition.next(
            state: armed,
            newIdentity: Self.identityA, // same identity `armed` already shows
            newBeat: armed.currentBeat, // same beat `armed` already has
            onScreen: (armed.beatFrames.first?.grid ?? Self.pixelsFor(Self.identityA), 0, nil),
            pixelsFor: Self.pixelsFor(_:),
            colorFor: Self.testColor(for:),
            reduceMotion: false,
            seed: 11
        )

        #expect(reapplied == armed, "re-delivering the same (identity, beat) must not re-arm or reset anything")
    }
}

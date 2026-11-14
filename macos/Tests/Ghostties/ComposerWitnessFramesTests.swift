import Foundation
import Testing
@testable import Ghostty

/// Board B frame-animation port (`ComposerWitnessFrames.swift`) — pure
/// generator, dither, beat-builder, and playback-clock coverage. Grids below
/// are synthetic fixtures chosen to make each generator's effect visible,
/// not the real ghost cast (that's `ComposerWitnessCastParityTests`).
struct ComposerWitnessFramesTests {
    /// 6 rows × 8 cols: a body with a widening base (rows 0/5 narrower than
    /// the middle) and two eye rows (3, 4) — enough shape to exercise
    /// squash/stretch/blink/squint without being the real cast.
    private static let grid: [String] = [
        "..XXXX..",
        ".XXXXXX.",
        "XXXXXXXX",
        "XX.ee.XX",
        "XX.ee.XX",
        "..XXXX.."
    ]

    // MARK: - Generators

    @Test func squashClearsRowZeroAndWidensTheLastRowByOneEachSide() {
        let result = ComposerWitnessFrames.squash(Self.grid)
        #expect(result[0] == "........")
        #expect(result[5] == ".XXXXXX.")
    }

    @Test func stretchClearsTheLastRowAndNarrowsTheRowAboveIt() {
        let result = ComposerWitnessFrames.stretch(Self.grid)
        #expect(result[5] == "........")
        #expect(result[4] == ".X.ee.X.")
    }

    @Test func leanRotatesOnlyTheTopHalf() {
        let grid = ["ABCD", "EFGH", "IJKL", "MNOP"]
        let result = ComposerWitnessFrames.lean(grid, 1)
        #expect(result[0] == "DABC")
        #expect(result[1] == "HEFG")
        #expect(result[2] == "IJKL", "bottom half must be untouched")
        #expect(result[3] == "MNOP", "bottom half must be untouched")
    }

    @Test func skirtRipplePhaseZeroIsIdentity() {
        #expect(ComposerWitnessFrames.skirtRipple(Self.grid, phase: 0) == Self.grid)
    }

    @Test func blinkGridTurnsEyeCellsToBody() {
        let result = ComposerWitnessFrames.blinkGrid(Self.grid)
        #expect(result[3] == "XX.XX.XX")
        #expect(result[4] == "XX.XX.XX")
        #expect(result[0] == Self.grid[0], "rows without eyes are untouched")
    }

    @Test func squintKeepsTheFirstEyeRowOpen() {
        let result = ComposerWitnessFrames.squint(Self.grid)
        #expect(result[3] == Self.grid[3], "first eye row stays open")
        #expect(result[4] == "XX.XX.XX", "second eye row closes")
    }

    @Test func glanceMovesEyesOnlyIntoXCells() {
        #expect(ComposerWitnessFrames.glance(["XeXXXX"], 1) == ["XXeXXX"])
        #expect(ComposerWitnessFrames.glance(["XeXXXX"], -1) == ["eXXXXX"])
        // Eye at the left edge can't glance left — the neighbour is out of
        // bounds, not an `X` cell, so the row is unchanged.
        #expect(ComposerWitnessFrames.glance(["eXXXXX"], -1) == ["eXXXXX"])
    }

    // MARK: - Dither

    private static let ditherA = ["XXXX", "XXXX"]
    private static let ditherB = ["....", "...."]

    @Test func ditherAtProgressOneEqualsGridB() {
        let result = ComposerWitnessFrames.dither(gridA: Self.ditherA, gridB: Self.ditherB, progress: 1, seed: 11)
        #expect(result.grid == Self.ditherB)
    }

    @Test func ditherAtProgressZeroDiffersFromGridB() {
        let result = ComposerWitnessFrames.dither(gridA: Self.ditherA, gridB: Self.ditherB, progress: 0, seed: 11)
        #expect(result.grid == Self.ditherA)
        #expect(result.grid != Self.ditherB)
    }

    @Test func ditherIsDeterministicForTheSameSeed() {
        let first = ComposerWitnessFrames.dither(gridA: Self.ditherA, gridB: Self.ditherB, progress: 0.5, seed: 11)
        let second = ComposerWitnessFrames.dither(gridA: Self.ditherA, gridB: Self.ditherB, progress: 0.5, seed: 11)
        #expect(first.grid == second.grid)
        #expect(first.sourceIsB == second.sourceIsB)
    }

    @Test func bottomFirstDitherFavoursTheBottomRowAtMidProgress() {
        let rows = 6
        let gridA = Array(repeating: String(repeating: ".", count: 8), count: rows)
        let gridB = Array(repeating: String(repeating: "X", count: 8), count: rows)
        let result = ComposerWitnessFrames.dither(gridA: gridA, gridB: gridB, progress: 0.5, seed: 11, bottomFirst: true)
        let topCount = result.sourceIsB[0].filter { $0 }.count
        let bottomCount = result.sourceIsB[rows - 1].filter { $0 }.count
        #expect(bottomCount > topCount, "bottomFirst should resolve the bottom row to B before the top row")
    }

    // MARK: - Beat frame sequences

    @Test func tabFramesHaveFourSixtyMsStepsAndARestAtTheOriginalGrid() {
        let frames = ComposerWitnessFrames.buildTabFrames(grid: Self.grid)
        #expect(frames.count == 5)
        #expect(frames.map(\.ms) == [60, 60, 60, 60, 0])
        #expect(frames.last?.grid == Self.grid)
    }

    @Test func errorFramesHaveThreeSeventyMsStepsAndARestAtTheOriginalGrid() {
        let frames = ComposerWitnessFrames.buildErrorFrames(grid: Self.grid)
        #expect(frames.count == 4)
        #expect(frames.map(\.ms) == [70, 70, 70, 0])
        #expect(frames.last?.grid == Self.grid)
    }

    @Test func launchFramesEndOnAnEmptyGrid() {
        let frames = ComposerWitnessFrames.buildLaunchFrames(grid: Self.grid, seed: 11)
        #expect(frames.count == 5)
        #expect(frames.map(\.ms) == [80, 50, 50, 50, 50])
        #expect(frames.last?.grid == ComposerWitnessFrames.emptyGridLike(Self.grid))
    }

    // MARK: - Frame-at-elapsed boundaries

    @Test func tabFrameIndexBoundaries() {
        let frames = ComposerWitnessFrames.buildTabFrames(grid: Self.grid)
        #expect(ComposerWitnessFrames.frameIndex(frames: frames, elapsedMs: 0) == 0)
        #expect(ComposerWitnessFrames.frameIndex(frames: frames, elapsedMs: 59) == 0)
        #expect(ComposerWitnessFrames.frameIndex(frames: frames, elapsedMs: 60) == 1)
        #expect(ComposerWitnessFrames.frameIndex(frames: frames, elapsedMs: 239) == 3)
        #expect(ComposerWitnessFrames.frameIndex(frames: frames, elapsedMs: 240) == 4)
    }

    // MARK: - Idle loop

    @Test func idleBlinksAtZeroAndOneNineteenMsButOpensAtOneTwentyMs() {
        let blinkExpected = ComposerWitnessFrames.blinkGrid(Self.grid)
        #expect(ComposerWitnessFrames.idleFrame(base: Self.grid, atMs: 0).grid == blinkExpected)
        #expect(ComposerWitnessFrames.idleFrame(base: Self.grid, atMs: 119).grid == blinkExpected)
        #expect(ComposerWitnessFrames.idleFrame(base: Self.grid, atMs: 120).grid == Self.grid)
    }

    // MARK: - Reduce Motion

    @Test func reduceMotionReturnsTheBaseGridForEveryBeat() {
        let someFrames = ComposerWitnessFrames.buildTabFrames(grid: Self.grid)
        // Every combination of idle/launch flags a beat could report —
        // Reduce Motion must hold the base grid regardless.
        let combos: [(isIdleBeat: Bool, isLaunchBeat: Bool)] = [
            (true, false), (false, false), (false, true)
        ]
        for combo in combos {
            let result = ComposerWitnessFrames.displayGrid(
                identityGrid: Self.grid,
                isIdleBeat: combo.isIdleBeat,
                isLaunchBeat: combo.isLaunchBeat,
                beatFrames: someFrames,
                beatElapsedMs: 30,
                idleClockMs: 4050,
                reduceMotion: true
            )
            #expect(result.grid == Self.grid, "combo \(combo) did not hold the base grid under Reduce Motion")
            #expect(result.cellOffsetY == 0)
        }
    }

    // MARK: - Float (round 14, session-7)

    @Test func floatOffsetIsZeroAtTimeZero() {
        #expect(ComposerWitnessFrames.floatOffset(clockMs: 0, amplitude: 2, periodMs: 3000, reduceMotion: false) == 0)
    }

    @Test func floatOffsetIsNegativeAmplitudeAtOneQuarterPeriod() {
        let result = ComposerWitnessFrames.floatOffset(clockMs: 750, amplitude: 2, periodMs: 3000, reduceMotion: false)
        #expect(abs(result - (-2)) < 0.0001)
    }

    @Test func floatOffsetIsZeroUnderReduceMotion() {
        #expect(ComposerWitnessFrames.floatOffset(clockMs: 750, amplitude: 2, periodMs: 3000, reduceMotion: true) == 0)
    }

    @Test func floatOffsetIsZeroAtZeroAmplitude() {
        #expect(ComposerWitnessFrames.floatOffset(clockMs: 750, amplitude: 0, periodMs: 3000, reduceMotion: false) == 0)
    }

    // MARK: - Float horizontal (round 15)

    @Test func floatOffsetXIsZeroAtTimeZero() {
        #expect(ComposerWitnessFrames.floatOffsetX(clockMs: 0, amplitude: 2, periodMs: 3000, reduceMotion: false) == 0)
    }

    /// Half the vertical float's frequency — a quarter of the DOUBLED
    /// cycle (2 · periodMs) lands at periodMs / 2.
    @Test func floatOffsetXIsPositiveAmplitudeAtOneQuarterOfDoubledPeriod() {
        let result = ComposerWitnessFrames.floatOffsetX(clockMs: 1500, amplitude: 2, periodMs: 3000, reduceMotion: false)
        #expect(abs(result - 2) < 0.0001)
    }

    @Test func floatOffsetXIsZeroUnderReduceMotion() {
        #expect(ComposerWitnessFrames.floatOffsetX(clockMs: 1500, amplitude: 2, periodMs: 3000, reduceMotion: true) == 0)
    }

    @Test func floatOffsetXIsZeroAtZeroAmplitude() {
        #expect(ComposerWitnessFrames.floatOffsetX(clockMs: 1500, amplitude: 0, periodMs: 3000, reduceMotion: false) == 0)
    }

    // MARK: - Entrance (the open drop)

    private static func openSamples() -> [ComposerWitnessFrames.WitnessTransform] {
        (0...ComposerWitnessFrames.openDurationMs + 20).map {
            ComposerWitnessFrames.openTransform(elapsedMs: $0, reduceMotion: false)
        }
    }

    @Test func entranceStartsTwelvePointsAboveAndInvisible() {
        let start = ComposerWitnessFrames.openTransform(elapsedMs: 0, reduceMotion: false)
        #expect(start.offsetY == -12)
        #expect(start.opacity == 0)
        #expect(start.scaleX == 1)
        #expect(start.scaleY == 1)
    }

    @Test func entranceEndsExactlyAtTheIdentityTransformWithin250Ms() {
        #expect(ComposerWitnessFrames.openDurationMs <= 250)
        let end = ComposerWitnessFrames.openTransform(elapsedMs: ComposerWitnessFrames.openDurationMs, reduceMotion: false)
        #expect(end == .identity)
        #expect(ComposerWitnessFrames.openTransform(elapsedMs: 10_000, reduceMotion: false) == .identity)
    }

    @Test func entranceDropOnlyEverMovesDownAndIsEasedOut() {
        let samples = Self.openSamples()
        for (a, b) in zip(samples, samples.dropFirst()) {
            #expect(b.offsetY >= a.offsetY, "the drop must never move back up")
        }
        // A strong ease-out covers most of the distance in the first third.
        let third = ComposerWitnessFrames.openTransform(elapsedMs: ComposerWitnessFrames.openDropMs / 3, reduceMotion: false)
        #expect(third.offsetY > -12 * 0.3)
    }

    /// Exactly one squash: scale y dips below 1 in one unbroken run, never
    /// rises above 1, and the squash's scale x never shrinks below 1.
    @Test func entranceSquashesExactlyOnce() {
        let samples = Self.openSamples()
        let dipping = samples.map { $0.scaleY < 1 }
        let runs = zip([false] + dipping, dipping).filter { !$0 && $1 }.count
        #expect(runs == 1, "expected one squash, saw \(runs)")
        #expect(samples.allSatisfy { $0.scaleY <= 1 }, "scale y must never stretch past 1")
        #expect(samples.allSatisfy { $0.scaleX >= 1 })
        #expect(samples.map(\.scaleY).min()! < 0.95, "the squash should be visible")
    }

    @Test func dropIsOffUnderReduceMotion() {
        for ms in [0, 40, 120, 200, 239] {
            #expect(ComposerWitnessFrames.openTransform(elapsedMs: ms, reduceMotion: true) == .identity)
        }
    }

    // MARK: - Flip (identity change)

    @Test func flipLastsAbout240Ms() {
        #expect(ComposerWitnessFrames.flipDurationMs == 240)
    }

    @Test func flipHitsZeroWidthAndSwapsTheSpriteAtTheMidpoint() {
        let half = ComposerWitnessFrames.flipDurationMs / 2
        let before = ComposerWitnessFrames.flipTransform(elapsedMs: half - 1, reduceMotion: false)
        let mid = ComposerWitnessFrames.flipTransform(elapsedMs: half, reduceMotion: false)
        #expect(mid.scaleX < 1e-6)
        #expect(!before.showsNewIdentity)
        #expect(mid.showsNewIdentity)
        #expect(ComposerWitnessFrames.flipTransform(elapsedMs: 0, reduceMotion: false) == (1, false))
    }

    @Test func flipEndsAtFullWidthOnTheNewIdentity() {
        let end = ComposerWitnessFrames.flipTransform(elapsedMs: ComposerWitnessFrames.flipDurationMs, reduceMotion: false)
        #expect(end.scaleX == 1)
        #expect(end.showsNewIdentity)
    }

    @Test func flipIsSymmetric() {
        let total = ComposerWitnessFrames.flipDurationMs
        for ms in stride(from: 0, through: total, by: 10) {
            let a = ComposerWitnessFrames.flipTransform(elapsedMs: ms, reduceMotion: false).scaleX
            let b = ComposerWitnessFrames.flipTransform(elapsedMs: total - ms, reduceMotion: false).scaleX
            #expect(abs(a - b) < 1e-6, "\(ms)ms: \(a) vs \(b)")
        }
    }

    @Test func flipIsOffUnderReduceMotion() {
        for ms in [0, 60, 120, 180] {
            let flip = ComposerWitnessFrames.flipTransform(elapsedMs: ms, reduceMotion: true)
            #expect(flip.scaleX == 1)
            #expect(flip.showsNewIdentity)
        }
    }

    @Test func floatIsOffUnderReduceMotion() {
        let amplitude = ComposerWitnessFloatAmplitude.defaultAmplitude
        for ms in [750, 1500, 2250] {
            #expect(ComposerWitnessFrames.floatOffset(clockMs: ms, amplitude: amplitude, periodMs: 3000, reduceMotion: true) == 0)
            #expect(ComposerWitnessFrames.floatOffsetX(clockMs: ms, amplitude: amplitude, periodMs: 3000, reduceMotion: true) == 0)
        }
    }

    // MARK: - Pixel snapping

    @Test func pixelSnappedOffsetsLandOnWholePixels() {
        #expect(ComposerWitnessFrames.pixelSnapped(1.3, scale: 1) == 1)
        #expect(ComposerWitnessFrames.pixelSnapped(1.3, scale: 2) == 1.5)
        #expect(ComposerWitnessFrames.pixelSnapped(-3.8, scale: 2) == -4)
    }

    @Test func cubicBezierHitsItsEndpoints() {
        #expect(ComposerWitnessFrames.cubicBezier(0, 0.23, 1, 0.32, 1) == 0)
        #expect(ComposerWitnessFrames.cubicBezier(1, 0.23, 1, 0.32, 1) == 1)
        #expect(abs(ComposerWitnessFrames.cubicBezier(0.5, 0.65, 0, 0.35, 1) - 0.5) < 1e-9)
    }
}

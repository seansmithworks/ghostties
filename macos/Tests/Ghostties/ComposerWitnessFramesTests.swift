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

    @Test func resolveFramesHaveSixFortyMsStepsAndEndOnGridB() {
        let gridB = ComposerWitnessFrames.emptyGridLike(Self.grid)
        let frames = ComposerWitnessFrames.buildResolveFrames(gridA: Self.grid, gridB: gridB, seed: 11)
        #expect(frames.count == 6)
        #expect(frames.map(\.ms) == [40, 40, 40, 40, 40, 40])
        #expect(frames.last?.grid == gridB)
    }

    @Test func openFramesHaveSixFortyMsStepsAndEndOnTheBaseGrid() {
        let frames = ComposerWitnessFrames.buildOpenFrames(grid: Self.grid, seed: 11)
        #expect(frames.count == 6)
        #expect(frames.map(\.ms) == [40, 40, 40, 40, 40, 40])
        #expect(frames.last?.grid == Self.grid)
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
            #expect(result.sourceIsB == nil)
        }
    }
}

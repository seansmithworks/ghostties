import Foundation

/// Board B ("Frames") — pure Swift port of the Ghost Motion artifact Sean
/// approved 2026-09-13 (`board-b-spec.js`). Foundation-only, no SwiftUI —
/// every function here operates on `[String]` 12×12 grids (`.` empty, `X`
/// body, `e` eye, `l` lit) so it's directly testable and reusable by
/// `ComposerWitnessView`. `floatOn` from the spec is NOT approved and is not
/// ported.
enum ComposerWitnessFrames {
    // MARK: - Pure grid generators

    static func rowBounds(_ row: String) -> (min: Int, max: Int)? {
        let chars = Array(row)
        var minIndex = -1
        var maxIndex = -1
        for i in 0..<chars.count where chars[i] != "." {
            if minIndex < 0 { minIndex = i }
            maxIndex = i
        }
        return minIndex < 0 ? nil : (minIndex, maxIndex)
    }

    static func rotateRowSegment(_ row: String, _ bounds: (min: Int, max: Int)?, _ dir: Int) -> String {
        guard let bounds else { return row }
        var chars = Array(row)
        let segment = Array(chars[bounds.min...bounds.max])
        let n = segment.count
        let d = ((dir % n) + n) % n
        let rotated = Array(segment[(n - d)...]) + Array(segment[..<(n - d)])
        chars.replaceSubrange(bounds.min...bounds.max, with: rotated)
        return String(chars)
    }

    static func skirtRipple(_ grid: [String], phase: Int) -> [String] {
        var g = grid
        let n = g.count
        let rows = [n - 2, n - 1].filter { $0 >= 0 }
        for (idx, r) in rows.enumerated() {
            if phase == 0 { continue }
            let dir = idx % 2 == 0 ? 1 : -1
            let b = rowBounds(g[r])
            g[r] = rotateRowSegment(g[r], b, dir)
        }
        return g
    }

    static func blinkGrid(_ grid: [String]) -> [String] {
        grid.map { row in String(row.map { $0 == "e" ? "X" : $0 }) }
    }

    static func squint(_ grid: [String]) -> [String] {
        var seenEyeRow = false
        return grid.map { row -> String in
            guard row.contains("e") else { return row }
            if !seenEyeRow {
                seenEyeRow = true
                return row
            }
            return String(row.map { $0 == "e" ? "X" : $0 })
        }
    }

    static func glance(_ grid: [String], _ dir: Int) -> [String] {
        var g = grid
        for r in 0..<g.count {
            var chars = Array(g[r])
            var cols: [Int] = []
            for c in 0..<chars.count where chars[c] == "e" { cols.append(c) }
            if cols.isEmpty { continue }
            var ok = true
            let order = dir > 0 ? Array(cols.reversed()) : cols
            for c in order {
                let nc = c + dir
                if nc < 0 || nc >= chars.count || chars[nc] != "X" { ok = false }
            }
            if !ok { continue }
            for c in order {
                let nc = c + dir
                chars[nc] = "e"
                chars[c] = "X"
            }
            g[r] = String(chars)
        }
        return g
    }

    static func squash(_ grid: [String]) -> [String] {
        var out = grid
        let cols = grid[0].count
        out[0] = String(repeating: ".", count: cols)
        let last = out.count - 1
        if let b = rowBounds(out[last]) {
            var chars = Array(out[last])
            if b.min > 0 { chars[b.min - 1] = "X" }
            if b.max < chars.count - 1 { chars[b.max + 1] = "X" }
            out[last] = String(chars)
        }
        return out
    }

    static func stretch(_ grid: [String]) -> [String] {
        var out = grid
        let n = out.count
        out[n - 1] = String(repeating: ".", count: grid[n - 1].count)
        let narrowRow = n - 2
        if let b = rowBounds(out[narrowRow]) {
            var chars = Array(out[narrowRow])
            if chars[b.min] == "X" && chars[b.max] == "X" {
                chars[b.min] = "."
                chars[b.max] = "."
                out[narrowRow] = String(chars)
            }
        }
        return out
    }

    static func lean(_ grid: [String], _ dir: Int) -> [String] {
        var g = grid
        let half = Int(ceil(Double(g.count) / 2))
        for r in 0..<half {
            let b = rowBounds(g[r])
            g[r] = rotateRowSegment(g[r], b, dir)
        }
        return g
    }

    /// Explicit 32-bit wrapping arithmetic (`&*`, `truncatingIfNeeded`,
    /// unsigned right shift via `UInt32(bitPattern:)`) so the dither pattern
    /// is deterministic across runs — matching JS's implicit 32-bit int
    /// overflow (`^`, `Math.imul`, `>>>`).
    static func hashUnit(row: Int, col: Int, seed: Int32) -> Double {
        var h: Int32 = (Int32(row) &* 73856093) ^ (Int32(col) &* 19349663) ^ (seed &* 83492791)
        h = Int32(bitPattern: UInt32(bitPattern: h) >> 13) ^ h
        let product = Int64(h) &* Int64(1274126177)
        h = Int32(truncatingIfNeeded: product)
        h = Int32(bitPattern: UInt32(bitPattern: h) >> 16) ^ h
        let u = Double(UInt32(bitPattern: h)) / 4294967296.0
        return min(0.999999, max(0.000001, u))
    }

    static func emptyGridLike(_ grid: [String]) -> [String] {
        grid.map { String(repeating: ".", count: $0.count) }
    }

    /// `sourceIsB[row][col] == true` means that cell was taken from `gridB`
    /// this frame — used to colour a resolve morph per-source-ghost rather
    /// than in a single colour.
    static func dither(
        gridA: [String],
        gridB: [String]?,
        progress: Double,
        seed: Int32,
        bottomFirst: Bool = false
    ) -> (grid: [String], sourceIsB: [[Bool]]) {
        let n = gridA.count
        let bRows = gridB ?? emptyGridLike(gridA)
        var outRows: [String] = []
        var source: [[Bool]] = []
        for r in 0..<n {
            let rowA = Array(gridA[r])
            let rowB = Array(bRows[r])
            var chars: [Character] = []
            var srcRow: [Bool] = []
            for c in 0..<rowA.count {
                let u = hashUnit(row: r, col: c, seed: seed)
                let order = bottomFirst ? (Double(n - 1 - r) / Double(n)) * 0.7 + u * 0.3 : u
                let fromB = progress > order
                chars.append(fromB ? rowB[c] : rowA[c])
                srcRow.append(fromB)
            }
            outRows.append(String(chars))
            source.append(srcRow)
        }
        return (outRows, source)
    }

    // MARK: - Timing

    static func isPeriodic(t: Int, period: Int, dur: Int, offset: Int = 0) -> Bool {
        let p = (((t + offset) % period) + period) % period
        return p < dur
    }

    // MARK: - Beats (t/ms in milliseconds; seed 11 on the board)

    static func idleFrame(base grid: [String], atMs t: Int) -> (grid: [String], cellOffsetY: Int) {
        let phase = (t / 450) % 2
        var g = skirtRipple(grid, phase: phase)
        if isPeriodic(t: t, period: 4000, dur: 120) {
            g = blinkGrid(g)
        } else if isPeriodic(t: t, period: 6000, dur: 400, offset: 1500) {
            let dir = (t / 6000) % 2 == 0 ? -1 : 1
            g = glance(g, dir)
        }
        return (g, 0)
    }

    struct WitnessFrame: Equatable {
        var grid: [String]
        var cellOffsetY: Int
        var ms: Int
        var sourceIsB: [[Bool]]?
    }

    static func buildTabFrames(grid: [String]) -> [WitnessFrame] {
        [
            WitnessFrame(grid: squash(grid), cellOffsetY: 0, ms: 60, sourceIsB: nil),
            WitnessFrame(grid: stretch(grid), cellOffsetY: -2, ms: 60, sourceIsB: nil),
            WitnessFrame(grid: grid, cellOffsetY: -2, ms: 60, sourceIsB: nil),
            WitnessFrame(grid: squash(grid), cellOffsetY: 0, ms: 60, sourceIsB: nil),
            WitnessFrame(grid: grid, cellOffsetY: 0, ms: 0, sourceIsB: nil)
        ]
    }

    static func buildErrorFrames(grid: [String]) -> [WitnessFrame] {
        let sq = squint(grid)
        return [
            WitnessFrame(grid: lean(sq, -1), cellOffsetY: 0, ms: 70, sourceIsB: nil),
            WitnessFrame(grid: lean(sq, 1), cellOffsetY: 0, ms: 70, sourceIsB: nil),
            WitnessFrame(grid: lean(sq, -1), cellOffsetY: 0, ms: 70, sourceIsB: nil),
            WitnessFrame(grid: grid, cellOffsetY: 0, ms: 0, sourceIsB: nil)
        ]
    }

    static func buildLaunchFrames(grid: [String], seed: Int32) -> [WitnessFrame] {
        let stretched = stretch(grid)
        let empty = emptyGridLike(grid)
        let steps = 4
        let stepMs = 50
        var frames = [WitnessFrame(grid: stretched, cellOffsetY: 0, ms: 80, sourceIsB: nil)]
        for i in 0..<steps {
            let progress = Double(i + 1) / Double(steps)
            let d = dither(gridA: stretched, gridB: empty, progress: progress, seed: seed)
            frames.append(WitnessFrame(grid: d.grid, cellOffsetY: -Int(progress.rounded()), ms: stepMs, sourceIsB: nil))
        }
        return frames
    }

    static func buildResolveFrames(gridA: [String], gridB: [String], seed: Int32) -> [WitnessFrame] {
        let steps = 6
        let stepMs = 40
        var frames: [WitnessFrame] = []
        for i in 0..<steps {
            let progress = Double(i + 1) / Double(steps)
            let d = dither(gridA: gridA, gridB: gridB, progress: progress, seed: seed)
            frames.append(WitnessFrame(grid: d.grid, cellOffsetY: 0, ms: stepMs, sourceIsB: d.sourceIsB))
        }
        return frames
    }

    static func buildOpenFrames(grid: [String], seed: Int32) -> [WitnessFrame] {
        let empty = emptyGridLike(grid)
        let steps = 6
        let stepMs = 40
        var frames: [WitnessFrame] = []
        for i in 0..<steps {
            let progress = Double(i + 1) / Double(steps)
            let d = dither(gridA: empty, gridB: grid, progress: progress, seed: seed, bottomFirst: true)
            frames.append(WitnessFrame(grid: d.grid, cellOffsetY: 0, ms: stepMs, sourceIsB: nil))
        }
        return frames
    }

    /// Which frame (by index) is showing at `elapsedMs` since the beat
    /// armed. A frame with `ms == 0` is the beat's held end-state — once
    /// reached it stays forever (until the beat kind is reconsidered by the
    /// caller, e.g. back to idle).
    static func frameIndex(frames: [WitnessFrame], elapsedMs: Int) -> Int {
        guard !frames.isEmpty else { return 0 }
        var acc = 0
        for (i, f) in frames.enumerated() {
            if f.ms == 0 { return i }
            acc += f.ms
            if elapsedMs < acc { return i }
        }
        return frames.count - 1
    }

    /// The single source of truth for what's on screen at any instant:
    /// Reduce Motion collapses to the static base grid; an idle beat (or a
    /// beat with no frames) runs the idle loop; the launch beat freezes on
    /// its last (empty) frame once its frames are exhausted; every other
    /// beat falls back to the idle loop once its frames are exhausted.
    /// Takes `isIdleBeat`/`isLaunchBeat` rather than `ComposerWitness
    /// .BeatKind` directly so this file stays Foundation-only and
    /// standalone-compilable, with no dependency on the SwiftUI-importing
    /// `ComposerWitness.swift`.
    static func displayGrid(
        identityGrid: [String],
        isIdleBeat: Bool,
        isLaunchBeat: Bool,
        beatFrames: [WitnessFrame],
        beatElapsedMs: Int,
        idleClockMs: Int,
        reduceMotion: Bool
    ) -> (grid: [String], cellOffsetY: Int, sourceIsB: [[Bool]]?) {
        if reduceMotion {
            return (identityGrid, 0, nil)
        }
        if isIdleBeat || beatFrames.isEmpty {
            let idle = idleFrame(base: identityGrid, atMs: idleClockMs)
            return (idle.grid, idle.cellOffsetY, nil)
        }
        let totalMs = beatFrames.reduce(0) { $0 + $1.ms }
        if isLaunchBeat {
            let index = beatElapsedMs >= totalMs
                ? beatFrames.count - 1
                : frameIndex(frames: beatFrames, elapsedMs: beatElapsedMs)
            let f = beatFrames[index]
            return (f.grid, f.cellOffsetY, f.sourceIsB)
        }
        if beatElapsedMs >= totalMs {
            let idle = idleFrame(base: identityGrid, atMs: idleClockMs)
            return (idle.grid, idle.cellOffsetY, nil)
        }
        let index = frameIndex(frames: beatFrames, elapsedMs: beatElapsedMs)
        let f = beatFrames[index]
        return (f.grid, f.cellOffsetY, f.sourceIsB)
    }
}

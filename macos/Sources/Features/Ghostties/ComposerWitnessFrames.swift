import Foundation

/// Board B ("Frames") — pure Swift port of the Ghost Motion artifact Sean
/// approved 2026-09-13 (`board-b-spec.js`). Foundation-only, no SwiftUI —
/// every function here operates on `[String]` 12×12 grids (`.` empty, `X`
/// body, `e` eye, `l` lit) so it's directly testable and reusable by
/// `ComposerWitnessView`. The spec's `floatOn` was not ported at the time —
/// round 14 (session-7 live-look round) adds an independent `floatOffset`
/// below, a Sean-tunable dial (default off), not a revival of that spec
/// function.
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
        /// Set only on a resolve morph's frames (`buildResolveFrames`).
        var sourceIsB: [[Bool]]?
    }

    static func buildTabFrames(grid: [String]) -> [WitnessFrame] {
        [
            WitnessFrame(grid: squash(grid), cellOffsetY: 0, ms: 60),
            WitnessFrame(grid: stretch(grid), cellOffsetY: -2, ms: 60),
            WitnessFrame(grid: grid, cellOffsetY: -2, ms: 60),
            WitnessFrame(grid: squash(grid), cellOffsetY: 0, ms: 60),
            WitnessFrame(grid: grid, cellOffsetY: 0, ms: 0)
        ]
    }

    static func buildErrorFrames(grid: [String]) -> [WitnessFrame] {
        let sq = squint(grid)
        return [
            WitnessFrame(grid: lean(sq, -1), cellOffsetY: 0, ms: 70),
            WitnessFrame(grid: lean(sq, 1), cellOffsetY: 0, ms: 70),
            WitnessFrame(grid: lean(sq, -1), cellOffsetY: 0, ms: 70),
            WitnessFrame(grid: grid, cellOffsetY: 0, ms: 0)
        ]
    }

    static func buildLaunchFrames(grid: [String], seed: Int32) -> [WitnessFrame] {
        let stretched = stretch(grid)
        let empty = emptyGridLike(grid)
        let steps = 4
        let stepMs = 50
        var frames = [WitnessFrame(grid: stretched, cellOffsetY: 0, ms: 80)]
        for i in 0..<steps {
            let progress = Double(i + 1) / Double(steps)
            let d = dither(gridA: stretched, gridB: empty, progress: progress, seed: seed)
            frames.append(WitnessFrame(grid: d.grid, cellOffsetY: -Int(progress.rounded()), ms: stepMs))
        }
        return frames
    }

    /// The project-change blend: the outgoing ghost dithers into the new
    /// one over six 40ms steps (240ms).
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

    /// Round 14 (session-7): a gentle vertical bob, a sine wave —
    /// `-amplitude * sin(2π · clockMs / periodMs)`. Pure and Foundation-only
    /// so `ComposerWitnessView` can apply it as a transform/offset inside
    /// its `TimelineView`, never a layout or frame change. Driven off the
    /// idle clock, not the beat clock, so it runs continuously, including
    /// during beats — the beat's own `cellOffsetY` hop stacks on top.
    /// Returns 0 under Reduce Motion or when the amplitude/period dial is 0.
    static func floatOffset(clockMs: Int, amplitude: Double, periodMs: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion, amplitude != 0, periodMs > 0 else { return 0 }
        return -amplitude * sin(2 * Double.pi * Double(clockMs) / periodMs)
    }

    /// Round 15 (Sean's DialKit Copy output): a sideways sway at HALF the
    /// vertical float's frequency (`periodMs` is the SAME period dial
    /// `floatOffset` uses, not a separate one) — combined with the vertical
    /// bob above, this traces a lazy figure-8 rather than a diagonal line.
    /// Pure and Foundation-only, same shape as `floatOffset`, so
    /// `ComposerWitnessView` can apply both as a single `.offset(x:y:)`
    /// transform inside its `TimelineView`. Returns 0 under Reduce Motion or
    /// when the amplitude/period dial is 0.
    static func floatOffsetX(clockMs: Int, amplitude: Double, periodMs: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion, amplitude != 0, periodMs > 0 else { return 0 }
        return amplitude * sin(2 * Double.pi * Double(clockMs) / (2 * periodMs))
    }

    // MARK: - Entrance, flip and tip (transforms, never grid frames)

    /// A transform on the whole sprite: a vertical offset in points, a scale
    /// anchored at the sprite's bottom edge, and an opacity.
    struct WitnessTransform: Equatable {
        var offsetY: Double
        var scaleX: Double
        var scaleY: Double
        var opacity: Double

        static let identity = WitnessTransform(offsetY: 0, scaleX: 1, scaleY: 1, opacity: 1)
    }

    /// CSS `cubic-bezier(x1, y1, x2, y2)` evaluated at time `x` (0...1).
    /// Bisection on the curve's x, which is monotonic for x1/x2 in 0...1.
    static func cubicBezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        func sample(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        var lo = 0.0
        var hi = 1.0
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if sample(mid, x1, x2) < x { lo = mid } else { hi = mid }
        }
        return sample((lo + hi) / 2, y1, y2)
    }

    /// The open beat: the ghost drops in from `openDropDistance` above on a
    /// strong ease-out, fading in over the first `openFadeMs`, then settles
    /// with one squash anchored at its bottom edge. 240ms in all.
    static let openDropDistance: Double = 12
    static let openDropMs = 150
    static let openSquashMs = 90
    static let openFadeMs = 80
    static var openDurationMs: Int { openDropMs + openSquashMs }
    /// The squash's deepest point: 8% shorter, 4% wider.
    static let openSquashDepth: Double = 0.08
    static let openSquashWiden: Double = 0.04

    /// `elapsedMs` is the open beat's (speed-scaled) clock. Reduce Motion:
    /// no drop, no squash, no fade — the ghost is simply there.
    static func openTransform(elapsedMs: Int, reduceMotion: Bool) -> WitnessTransform {
        guard !reduceMotion, elapsedMs < openDurationMs else { return .identity }
        let t = Double(max(elapsedMs, 0))
        let opacity = min(1, t / Double(openFadeMs))
        if t < Double(openDropMs) {
            // Emil's strong ease-out, cubic-bezier(0.23, 1, 0.32, 1).
            let progress = cubicBezier(t / Double(openDropMs), 0.23, 1, 0.32, 1)
            return WitnessTransform(offsetY: -openDropDistance * (1 - progress), scaleX: 1, scaleY: 1, opacity: opacity)
        }
        // One half-sine: down to the deepest squash and back to exactly 1,
        // never past it, so it can't read as a second bounce.
        let hump = sin(Double.pi * (t - Double(openDropMs)) / Double(openSquashMs))
        return WitnessTransform(
            offsetY: 0,
            scaleX: 1 + openSquashWiden * hump,
            scaleY: 1 - openSquashDepth * hump,
            opacity: opacity
        )
    }

    /// The flip is the ghost's own motion: scale x 1 -> 0 -> 1, as a card
    /// turning once about its vertical axis. The turn angle runs on a
    /// symmetric ease-in-out, cubic-bezier(0.65, 0, 0.35, 1), so the two
    /// halves mirror exactly. It plays once as the ghost lands and then as
    /// an idle habit while the composer stays open (`selfFlipElapsedMs`);
    /// a project change never flips.
    static let flipDurationMs = 240

    /// The landing flip starts as the drop touches down (`openDropMs`),
    /// over the squash. Not earlier: the composer itself fades in over its
    /// first 200ms (`WorkspaceViewContainer.installComposerOverlayIfNeeded`),
    /// which would hide a flip that ran with the drop.
    static var landingFlipStartMs: Int { openDropMs }

    /// The idle flip repeats this often, in real time, counted from the
    /// landing flip.
    static let idleFlipIntervalMs = 10_000

    /// `elapsedMs` is the flip's own (speed-scaled) clock. Past the end, or
    /// under Reduce Motion, the sprite is at full width.
    static func flipScaleX(elapsedMs: Int, reduceMotion: Bool) -> Double {
        guard !reduceMotion, elapsedMs >= 0, elapsedMs < flipDurationMs else { return 1 }
        let progress = Double(elapsedMs) / Double(flipDurationMs)
        return abs(cos(Double.pi * cubicBezier(progress, 0.65, 0, 0.35, 1)))
    }

    /// How far into a flip the ghost is, on the flip's speed-scaled clock,
    /// `sinceOpenMs` real milliseconds after the open beat armed — `nil`
    /// between flips. `beatSpeed` scales the landing and each flip, never
    /// the interval. Reduce Motion: never flips, landing or idle.
    static func selfFlipElapsedMs(sinceOpenMs: Int, beatSpeed: Double, reduceMotion: Bool) -> Int? {
        guard !reduceMotion, beatSpeed > 0 else { return nil }
        let firstStartMs = Int((Double(landingFlipStartMs) / beatSpeed).rounded())
        guard sinceOpenMs >= firstStartMs else { return nil }
        let intoCycleMs = (sinceOpenMs - firstStartMs) % idleFlipIntervalMs
        let scaled = Int(Double(intoCycleMs) * beatSpeed)
        return scaled < flipDurationMs ? scaled : nil
    }

    // MARK: - Tip (short windows)

    /// The tip between standing above the field and lying beside it: one
    /// move on screen, so a strong ease-in-out, cubic-bezier(0.77, 0, 0.175,
    /// 1), the same both ways.
    static let tipDurationMs = 240

    /// How far the tip has run, 0...1, `elapsedMs` (real time) after it
    /// started. Reduce Motion: 1 at once, so the ghost appears in place
    /// with no tipping.
    static func tipProgress(elapsedMs: Int, reduceMotion: Bool) -> Double {
        guard !reduceMotion, elapsedMs < tipDurationMs else { return 1 }
        return cubicBezier(Double(max(elapsedMs, 0)) / Double(tipDurationMs), 0.77, 0, 0.175, 1)
    }

    /// Where the tip is, 0 (standing) ... 1 (lying), part-way from `from`
    /// to `to`. A tip that turns round mid-way starts from where it is.
    static func tipPosition(from: Double, to: Double, elapsedMs: Int, reduceMotion: Bool) -> Double {
        from + (to - from) * tipProgress(elapsedMs: elapsedMs, reduceMotion: reduceMotion)
    }

    /// Rounds an offset in points to the display's pixel grid, so the sprite
    /// never sits between pixels.
    static func pixelSnapped(_ points: Double, scale: Double) -> Double {
        guard scale > 0 else { return points }
        return (points * scale).rounded() / scale
    }
}

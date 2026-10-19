import AppKit
import SwiftUI

/// The selected session row's "drawn outline" (r7 card 06, with every curve
/// ease-in-out; contract `docs/plans/selected-row-outline-contract.md`): a
/// 1pt `inkSecondary` outline traced once around the row on a click, over
/// the selected-row tint, settling to a quiet outline at rest. The rail
/// draws it round the chip, the expanded list round the whole row, and the
/// morph between them is a straight line (`box`).
///
/// The model is pure: one `Frame` per instant of a `Mode`. The view
/// (`SelectedRowOutlineSurface`) runs a clock only while a mode plays, so a
/// resting list never ticks.
enum SelectedRowOutline {
    /// One instant of the effect. `traceProgress` 0...1 is the drawn fraction
    /// of the path; `tintOpacity` 0...1 scales the selected-row tint.
    struct Frame: Equatable {
        var traceProgress: Double
        var outlineOpacity: Double
        var tintOpacity: Double
    }

    static let hidden = Frame(traceProgress: 0, outlineOpacity: 0, tintOpacity: 0)
    static let rest = Frame(traceProgress: 1, outlineOpacity: restOpacity, tintOpacity: 1)

    enum Mode: Equatable {
        /// 300ms: from `.hidden` for a fresh pick, the live frame for a retarget.
        case click(from: Frame)
        /// Keys: the resting frame, at once.
        case rest
        /// 100ms fade of outline and tint; the drawn length is left as it was.
        case leaving(from: Frame)
        /// Reduce Motion: 120ms fade in, no trace.
        case reduceMotionIn(from: Frame)
        /// Reduce Motion: 100ms fade out, no trace.
        case reduceMotionOut(from: Frame)
    }

    /// The trace's length and the outline's settle, in ms.
    static let traceEnd: Double = 260
    static let clickDuration: Double = 300
    /// The tint starts once the outline is drawing.
    static let tintStart: Double = 80
    static let drawOpacity: Double = 0.6
    static let restOpacity: Double = 0.4

    static let strokeWidth: CGFloat = 1
    static let inset: CGFloat = 1
    static let cornerRadius: CGFloat = 8

    static func duration(_ mode: Mode) -> Double {
        switch mode {
        case .click: clickDuration
        case .rest: 0
        case .leaving: 100
        case .reduceMotionIn: 120
        case .reduceMotionOut: 100
        }
    }

    static func frame(elapsedMs: Double, mode: Mode) -> Frame {
        let t = min(max(elapsedMs, 0), duration(mode))
        switch mode {
        case .rest:
            return rest
        case .click(let f):
            let op = t <= traceEnd
                ? lerp(f.outlineOpacity, drawOpacity, curve(seg(t, 0, tintStart)))
                : lerp(drawOpacity, restOpacity, curve(seg(t, traceEnd, clickDuration)))
            return Frame(
                traceProgress: lerp(f.traceProgress, 1, curve(seg(t, 0, traceEnd))),
                outlineOpacity: op,
                tintOpacity: lerp(f.tintOpacity, 1, curve(seg(t, tintStart, traceEnd)))
            )
        case .leaving(let f):
            let k = 1 - curve(t / 100)
            return Frame(traceProgress: f.traceProgress, outlineOpacity: f.outlineOpacity * k, tintOpacity: f.tintOpacity * k)
        case .reduceMotionIn(let f):
            let e = curve(t / 120)
            return Frame(traceProgress: 1, outlineOpacity: lerp(f.outlineOpacity, restOpacity, e), tintOpacity: lerp(f.tintOpacity, 1, e))
        case .reduceMotionOut(let f):
            let e = curve(t / 100)
            return Frame(traceProgress: 1, outlineOpacity: lerp(f.outlineOpacity, 0, e), tintOpacity: lerp(f.tintOpacity, 0, e))
        }
    }

    /// What a mode leaves behind once it has played: the resting outline, or
    /// nothing (a row that has finished leaving starts its next trace from 0).
    static func settled(_ mode: Mode) -> Frame {
        switch mode {
        case .click, .rest, .reduceMotionIn: rest
        case .leaving, .reduceMotionOut: hidden
        }
    }

    /// `bezier(0.77, 0, 0.175, 1)` on 0...1, clamped: Newton on x(t), with a
    /// bisection fallback where the slope flattens.
    static func curve(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        let (p1x, p1y, p2x, p2y) = (0.77, 0.0, 0.175, 1.0)
        let cx = 3 * p1x, bx = 3 * (p2x - p1x) - cx, ax = 1 - cx - bx
        let cy = 3 * p1y, by = 3 * (p2y - p1y) - cy, ay = 1 - cy - by
        func sx(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
        func sy(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
        func dx(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }
        var t = x
        for _ in 0..<8 {
            let e = sx(t) - x
            if abs(e) < 1e-7 { return sy(t) }
            let d = dx(t)
            if abs(d) < 1e-6 { break }
            t -= e / d
        }
        var lo = 0.0, hi = 1.0
        t = x
        for _ in 0..<40 {
            let v = sx(t)
            if abs(v - x) < 1e-7 { break }
            if v < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return sy(t)
    }

    /// Closed rounded rect, y-down, centreline inset by `inset`, radius
    /// min(8, w/2, h/2) after the inset: from the leading edge's middle, up,
    /// clockwise on screen, back to that point. Each corner is one cubic.
    static func outlinePath(rowRect: CGRect) -> Path {
        let x = rowRect.minX + inset, y = rowRect.minY + inset
        let w = max(0, rowRect.width - 2 * inset), h = max(0, rowRect.height - 2 * inset)
        let r = min(cornerRadius, w / 2, h / 2)
        let right = x + w, bottom = y + h
        // Control-point distance for a quarter circle as one cubic.
        let k = r * 0.5522847498
        var p = Path()
        p.move(to: CGPoint(x: x, y: y + h / 2))
        p.addLine(to: CGPoint(x: x, y: y + r))
        p.addCurve(to: CGPoint(x: x + r, y: y), control1: CGPoint(x: x, y: y + r - k), control2: CGPoint(x: x + r - k, y: y))
        p.addLine(to: CGPoint(x: right - r, y: y))
        p.addCurve(to: CGPoint(x: right, y: y + r), control1: CGPoint(x: right - r + k, y: y), control2: CGPoint(x: right, y: y + r - k))
        p.addLine(to: CGPoint(x: right, y: bottom - r))
        p.addCurve(to: CGPoint(x: right - r, y: bottom), control1: CGPoint(x: right, y: bottom - r + k), control2: CGPoint(x: right - r + k, y: bottom))
        p.addLine(to: CGPoint(x: x + r, y: bottom))
        p.addCurve(to: CGPoint(x: x, y: bottom - r), control1: CGPoint(x: x + r - k, y: bottom), control2: CGPoint(x: x, y: bottom - r + k))
        p.addLine(to: CGPoint(x: x, y: y + h / 2))
        p.closeSubpath()
        return p
    }

    /// The card's `box()`: the row's rect at morph 0, the chip's at 1,
    /// linear between.
    static func box(row: CGRect, chip: CGRect, morph: Double) -> CGRect {
        if morph <= 0 { return row }
        if morph >= 1 { return chip }
        let m = CGFloat(morph)
        return CGRect(
            x: SidebarMorphMetrics.lerp(row.minX, chip.minX, m),
            y: SidebarMorphMetrics.lerp(row.minY, chip.minY, m),
            width: SidebarMorphMetrics.lerp(row.width, chip.width, m),
            height: SidebarMorphMetrics.lerp(row.height, chip.height, m)
        )
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    private static func seg(_ t: Double, _ a: Double, _ b: Double) -> Double { min(max((t - a) / (b - a), 0), 1) }

    // MARK: - Click origin

    /// The last row clicked, by its row key, and when. A selection change
    /// traces only on the row that was just clicked; anything else (the
    /// session shortcuts, Cmd+1-9, a session opening or closing) snaps, as
    /// the card's keys do. The leaving row fades only when another row was
    /// just clicked.
    @MainActor private static var lastClick: (key: String, at: Date)?
    /// Long enough for the store write to reach the rows (one update), short
    /// enough that a shortcut pressed after a click still snaps.
    private static let clickWindow: TimeInterval = 0.3

    /// Call from a row's tap, before it changes the selection.
    @MainActor static func recordClick(_ key: String) {
        lastClick = (key, Date())
    }

    /// How a row whose selection just changed should move.
    @MainActor static func mode(for key: String, becameActive: Bool, from current: Frame, reduceMotion: Bool, now: Date = Date()) -> Mode {
        if reduceMotion {
            return becameActive ? .reduceMotionIn(from: current) : .reduceMotionOut(from: current)
        }
        let fresh = lastClick.flatMap { now.timeIntervalSince($0.at) <= clickWindow ? $0.key : nil }
        if becameActive {
            return fresh == key ? .click(from: current) : .rest
        }
        // A key press leaves nothing behind: `.leaving` from nothing is nothing.
        return .leaving(from: fresh != nil && fresh != key ? current : hidden)
    }
}

// MARK: - Clock

/// One row's playing mode and when it started. Settled (not running), it
/// reads the mode's end state whatever the time, so a paused timeline's
/// stale date can never show a mid-trace frame.
struct SelectedRowOutlineClock: Equatable {
    var mode: SelectedRowOutline.Mode
    var start: Date
    var running: Bool
    /// Bumped on every start, so a finished clock's stop never ends a newer one.
    var generation: Int = 0

    init(isActive: Bool) {
        mode = isActive ? .rest : .leaving(from: SelectedRowOutline.hidden)
        start = .distantPast
        running = false
    }

    func frame(at date: Date) -> SelectedRowOutline.Frame {
        guard running else { return SelectedRowOutline.settled(mode) }
        let elapsed = date.timeIntervalSince(start) * 1000
        if elapsed >= SelectedRowOutline.duration(mode) { return SelectedRowOutline.settled(mode) }
        return SelectedRowOutline.frame(elapsedMs: elapsed, mode: mode)
    }

    mutating func play(_ mode: SelectedRowOutline.Mode, at date: Date) {
        self.mode = mode
        start = date
        // Nothing to play when it starts where it ends (a key press leaving).
        running = SelectedRowOutline.duration(mode) > 0
            && SelectedRowOutline.frame(elapsedMs: 0, mode: mode) != SelectedRowOutline.settled(mode)
        generation += 1
    }
}

// MARK: - Surface

/// The selected-row tint and outline behind a sidebar list row
/// (`SidebarListRowChrome`), the whole row in the expanded list and the
/// hover panel, the chip on the rail, morphing between the two with the
/// row's chip (`MorphGlyphSlot`, `MorphTravel`). Draws nothing on an
/// unselected row at rest. Colours are resolved per render from the chrome
/// scheme, so an appearance flip repaints.
struct SelectedRowOutlineSurface: View {
    let isActive: Bool
    /// The row's click key (`SelectedRowOutline.recordClick`).
    let key: String
    let progress: CGFloat
    /// The chip's centre x in the row at progress 0, and how far it travels by 1.
    let chipCenterX: CGFloat
    let chipTravel: CGFloat
    let chipSizes: (from: CGFloat, to: CGFloat)

    @State private var clock: SelectedRowOutlineClock

    init(isActive: Bool, key: String, progress: CGFloat, chipCenterX: CGFloat, chipTravel: CGFloat, chipSizes: (from: CGFloat, to: CGFloat)) {
        self.isActive = isActive
        self.key = key
        self.progress = progress
        self.chipCenterX = chipCenterX
        self.chipTravel = chipTravel
        self.chipSizes = chipSizes
        // A row already selected when it appears rests: no trace.
        _clock = State(initialValue: SelectedRowOutlineClock(isActive: isActive))
    }

    var body: some View {
        // Only the playing row's timeline ticks; every other row is paused.
        TimelineView(.animation(minimumInterval: nil, paused: !clock.running)) { context in
            let frame = clock.frame(at: context.date)
            if frame.outlineOpacity > 0 || frame.tintOpacity > 0 {
                SelectedRowOutlineShape(
                    progress: progress, frame: frame,
                    chipCenterX: chipCenterX, chipTravel: chipTravel, chipSizes: chipSizes
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: isActive) { active in
            let now = Date()
            let mode = SelectedRowOutline.mode(
                for: key, becameActive: active, from: clock.frame(at: now),
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, now: now
            )
            clock.play(mode, at: now)
        }
        .task(id: clock.generation) {
            guard clock.running else { return }
            let ms = SelectedRowOutline.duration(clock.mode)
            try? await Task.sleep(nanoseconds: UInt64((ms + 16) * 1_000_000))
            guard !Task.isCancelled else { return }
            clock.running = false
        }
    }
}

/// One frame of the outline and tint, at this step of the morph (animatable,
/// so it rides the morph's spring with the chip).
private struct SelectedRowOutlineShape: View, Animatable {
    var progress: CGFloat
    let frame: SelectedRowOutline.Frame
    let chipCenterX: CGFloat
    let chipTravel: CGFloat
    let chipSizes: (from: CGFloat, to: CGFloat)

    @ChromeScheme private var colorScheme

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let tint = SidebarColors.selectedRowTint(colorScheme)
        let ink = ChromeTheme.active(colorScheme).inkSecondaryColor
        GeometryReader { proxy in
            let row = CGRect(origin: .zero, size: proxy.size)
            let side = SidebarMorphMetrics.lerp(chipSizes.from, chipSizes.to, progress)
            let chip = CGRect(
                x: chipCenterX + chipTravel * progress - side / 2, y: (row.height - side) / 2,
                width: side, height: side
            )
            let box = SelectedRowOutline.box(row: row, chip: chip, morph: Double(progress))
            let outline = SelectedRowOutline.outlinePath(rowRect: box)
            ZStack {
                RoundedRectangle(cornerRadius: SelectedRowOutline.cornerRadius, style: .circular)
                    .fill(tint)
                    .frame(width: box.width, height: box.height)
                    .position(x: box.midX, y: box.midY)
                    .opacity(frame.tintOpacity)
                (frame.traceProgress >= 1 ? outline : outline.trimmedPath(from: 0, to: frame.traceProgress))
                    .stroke(ink, style: StrokeStyle(lineWidth: SelectedRowOutline.strokeWidth, lineCap: .butt, lineJoin: .round))
                    .opacity(frame.outlineOpacity)
            }
        }
    }
}

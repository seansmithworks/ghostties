import CoreGraphics
import SwiftUI
import Testing
@testable import Ghostty

/// The selected-row outline's pure model (`SelectedRowOutline`), checked
/// numerically against `docs/plans/selected-row-outline-reference.js`, which
/// holds card 06's JS (r7 "Drawn outline", with every curve ease-in-out
/// `bezier(0.77, 0, 0.175, 1)`). Contract: `docs/plans/selected-row-outline-contract.md`.
///
/// Expected numbers below are that script's output (`node
/// docs/plans/selected-row-outline-reference.js`); the tolerance covers the
/// Newton solver's own 1e-5 stop in the JS.
struct SelectedRowOutlineModelTests {
    private typealias S = SelectedRowOutline
    private let tol = 1e-3

    private func expectFrame(_ f: S.Frame, _ trace: Double, _ op: Double, _ tint: Double, _ label: String, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(f.traceProgress - trace) < tol, "\(label): traceProgress \(f.traceProgress) != \(trace)", sourceLocation: sourceLocation)
        #expect(abs(f.outlineOpacity - op) < tol, "\(label): outlineOpacity \(f.outlineOpacity) != \(op)", sourceLocation: sourceLocation)
        #expect(abs(f.tintOpacity - tint) < tol, "\(label): tintOpacity \(f.tintOpacity) != \(tint)", sourceLocation: sourceLocation)
    }

    // MARK: - Curve

    @Test("The curve is the card's ease-in-out, not ease-out", arguments: [
        (0.0, 0.0), (0.1, 0.006445), (0.25, 0.052889), (0.5, 0.596005), (0.75, 0.956282), (0.9, 0.994468), (1.0, 1.0),
    ])
    func curveMatchesTheReference(x: Double, y: Double) {
        #expect(abs(S.curve(x) - y) < tol)
    }

    @Test("Slow at both ends: a quarter in is under a quarter, three quarters in is past three quarters")
    func curveIsEaseInOut() {
        #expect(S.curve(0.25) < 0.25)
        #expect(S.curve(0.75) > 0.75)
        // The ease-out it replaces (0.23, 1, 0.32, 1) is already above 0.5 at a quarter.
        #expect(S.curve(0.25) < 0.1)
        #expect(S.curve(0) == 0 && S.curve(1) == 1)
        #expect(S.curve(-1) == 0 && S.curve(2) == 1)
        var last = 0.0
        for i in 0...100 {
            let y = S.curve(Double(i) / 100)
            #expect(y >= last - 1e-9, "monotonic at \(i)%")
            last = y
        }
    }

    // MARK: - Click

    @Test("Click from nothing, checkpoints 0/40/80/130/200/260/300ms", arguments: [
        (0.0, 0.0, 0.0, 0.0),
        (40.0, 0.016624, 0.357603, 0.0),
        (80.0, 0.092434, 0.6, 0.0),
        (130.0, 0.596005, 0.6, 0.06968),
        (200.0, 0.964029, 0.6, 0.907184),
        (260.0, 1.0, 0.6, 1.0),
        (300.0, 1.0, 0.4, 1.0),
    ])
    func clickCheckpoints(ms: Double, trace: Double, op: Double, tint: Double) {
        expectFrame(S.frame(elapsedMs: ms, mode: .click(from: S.hidden)), trace, op, tint, "click @\(ms)ms")
    }

    @Test("Click runs 300ms and holds the rest frame after it")
    func clickEndsAtRest() {
        #expect(S.duration(.click(from: S.hidden)) == 300)
        expectFrame(S.frame(elapsedMs: 900, mode: .click(from: S.hidden)), 1, 0.4, 1, "click past the end")
        expectFrame(S.frame(elapsedMs: -50, mode: .click(from: S.hidden)), 0, 0, 0, "click before the start")
        #expect(S.frame(elapsedMs: 300, mode: .click(from: S.hidden)) == S.rest)
    }

    @Test("The tint starts only after the outline is drawing: nothing before 80ms")
    func tintWaitsForTheOutline() {
        for ms in stride(from: 0.0, through: 80.0, by: 10.0) {
            #expect(S.frame(elapsedMs: ms, mode: .click(from: S.hidden)).tintOpacity == 0, "tint @\(ms)ms")
        }
        #expect(S.frame(elapsedMs: 100, mode: .click(from: S.hidden)).tintOpacity > 0)
    }

    @Test("Retarget mid-trace continues from the current frame, never restarts", arguments: [
        (0.0, 0.5, 0.5, 0.25),
        (100.0, 0.593627, 0.6, 0.25607),
        (260.0, 1.0, 0.6, 1.0),
        (300.0, 1.0, 0.4, 1.0),
    ])
    func retargetContinues(ms: Double, trace: Double, op: Double, tint: Double) {
        let live = S.Frame(traceProgress: 0.5, outlineOpacity: 0.5, tintOpacity: 0.25)
        expectFrame(S.frame(elapsedMs: ms, mode: .click(from: live)), trace, op, tint, "retarget @\(ms)ms")
    }

    @Test("Clicking a row mid-way through a click carries its 130ms frame forward")
    func retargetFromARealFrame() {
        let mid = S.frame(elapsedMs: 130, mode: .click(from: S.hidden))
        #expect(S.frame(elapsedMs: 0, mode: .click(from: mid)) == mid)
        // The drawn length never retreats.
        var last = mid.traceProgress
        for ms in stride(from: 0.0, through: 300.0, by: 20.0) {
            let t = S.frame(elapsedMs: ms, mode: .click(from: mid)).traceProgress
            #expect(t >= last - 1e-9)
            last = t
        }
    }

    // MARK: - Leaving

    @Test("Leaving from rest: outline and tint fade together over 100ms", arguments: [
        (0.0, 0.4, 1.0), (25.0, 0.378845, 0.947111), (50.0, 0.161598, 0.403995), (75.0, 0.017487, 0.043718), (100.0, 0.0, 0.0),
    ])
    func leavingFromRest(ms: Double, op: Double, tint: Double) {
        let f = S.frame(elapsedMs: ms, mode: .leaving(from: S.rest))
        expectFrame(f, 1, op, tint, "leaving @\(ms)ms")
    }

    @Test("Leaving from mid-trace starts where it is and leaves the drawn length alone")
    func leavingFromMid() {
        let mid = S.Frame(traceProgress: 0.596005, outlineOpacity: 0.6, tintOpacity: 0.06968)
        expectFrame(S.frame(elapsedMs: 0, mode: .leaving(from: mid)), 0.596005, 0.6, 0.06968, "leaving mid @0")
        expectFrame(S.frame(elapsedMs: 50, mode: .leaving(from: mid)), 0.596005, 0.242397, 0.02815, "leaving mid @50")
        expectFrame(S.frame(elapsedMs: 100, mode: .leaving(from: mid)), 0.596005, 0, 0, "leaving mid @100")
    }

    @Test("Leaving is 100ms and clamps past it")
    func leavingDuration() {
        #expect(S.duration(.leaving(from: S.rest)) == 100)
        let end = S.frame(elapsedMs: 100, mode: .leaving(from: S.rest))
        #expect(S.frame(elapsedMs: 250, mode: .leaving(from: S.rest)) == end)
        #expect(end.outlineOpacity == 0 && end.tintOpacity == 0)
    }

    // MARK: - Keys

    @Test("Up/Down snaps to rest instantly, whatever the clock says", arguments: [0.0, 1.0, 130.0, 5000.0])
    func keysSnapToRest(ms: Double) {
        #expect(S.duration(.rest) == 0)
        #expect(S.frame(elapsedMs: ms, mode: .rest) == S.rest)
        #expect(S.rest == S.Frame(traceProgress: 1, outlineOpacity: 0.4, tintOpacity: 1))
    }

    // MARK: - Reduce Motion

    @Test("Reduce Motion in: 120ms fade of the resting outline and tint", arguments: [
        (0.0, 0.0, 0.0), (60.0, 0.238402, 0.596005), (120.0, 0.4, 1.0),
    ])
    func reduceMotionIn(ms: Double, op: Double, tint: Double) {
        #expect(S.duration(.reduceMotionIn(from: S.hidden)) == 120)
        expectFrame(S.frame(elapsedMs: ms, mode: .reduceMotionIn(from: S.hidden)), 1, op, tint, "RM in @\(ms)ms")
    }

    @Test("Reduce Motion out: 100ms fade", arguments: [
        (0.0, 0.4, 1.0), (50.0, 0.161598, 0.403995), (100.0, 0.0, 0.0),
    ])
    func reduceMotionOut(ms: Double, op: Double, tint: Double) {
        #expect(S.duration(.reduceMotionOut(from: S.rest)) == 100)
        expectFrame(S.frame(elapsedMs: ms, mode: .reduceMotionOut(from: S.rest)), 1, op, tint, "RM out @\(ms)ms")
    }

    @Test("Reduce Motion never draws a partial trace")
    func reduceMotionHasNoTrace() {
        for ms in stride(from: 0.0, through: 150.0, by: 10.0) {
            #expect(S.frame(elapsedMs: ms, mode: .reduceMotionIn(from: S.hidden)).traceProgress == 1, "in @\(ms)")
            #expect(S.frame(elapsedMs: ms, mode: .reduceMotionOut(from: S.rest)).traceProgress == 1, "out @\(ms)")
        }
        // And it never overshoots the draw opacity the click uses.
        for ms in stride(from: 0.0, through: 120.0, by: 10.0) {
            #expect(S.frame(elapsedMs: ms, mode: .reduceMotionIn(from: S.hidden)).outlineOpacity <= 0.4 + 1e-9)
        }
    }

    // MARK: - Path

    private enum El: Equatable { case move(CGPoint), line(CGPoint), curve(CGPoint), close }

    private func elements(_ path: Path) -> [El] {
        var out: [El] = []
        path.forEach { e in
            switch e {
            case .move(let p): out.append(.move(p))
            case .line(let p): out.append(.line(p))
            case .quadCurve(let p, _): out.append(.curve(p))
            case .curve(let p, _, _): out.append(.curve(p))
            case .closeSubpath: out.append(.close)
            }
        }
        return out
    }

    private func near(_ a: CGPoint, _ b: CGPoint, _ eps: CGFloat = 0.01) -> Bool { abs(a.x - b.x) < eps && abs(a.y - b.y) < eps }

    /// Row at (10, 20), 200 x 36. Inset 1pt: x 11...209, y 21...55; r = 8.
    private let row = CGRect(x: 10, y: 20, width: 200, height: 36)

    @Test("Constants: 1pt stroke, inset 1pt, r8")
    func constants() {
        #expect(S.strokeWidth == 1)
        #expect(S.inset == 1)
        #expect(S.cornerRadius == 8)
    }

    @Test("The path starts at the leading edge's middle, then runs up (clockwise on screen)")
    func pathStartsAtLeadingMiddle() throws {
        let els = elements(S.outlinePath(rowRect: row))
        guard case .move(let start) = try #require(els.first) else { Issue.record("first element is not a move"); return }
        #expect(near(start, CGPoint(x: 11, y: 38)), "start \(start): leading edge (x = 10 + 1), vertical middle (20 + 18)")
        guard case .line(let up) = els[1] else { Issue.record("second element is not a line"); return }
        #expect(near(up, CGPoint(x: 11, y: 29)), "first leg climbs the leading edge to where the r8 corner begins: \(up)")
    }

    @Test("The path is closed and ends back at its start")
    func pathIsClosedAtItsStart() throws {
        let els = elements(S.outlinePath(rowRect: row))
        #expect(els.last == .close)
        #expect(els.filter { $0 == .close }.count == 1)
        #expect(els.filter { if case .move = $0 { return true } else { return false } }.count == 1, "one subpath")
        guard case .line(let last) = els[els.count - 2] else { Issue.record("the leg before close is not a line"); return }
        #expect(near(last, CGPoint(x: 11, y: 38)), "the final leg returns to the leading-edge middle: \(last)")
    }

    @Test("r8 corners at 1pt inset: every tangent point sits 8pt along its edge")
    func pathHasR8CornersInsetOnePoint() {
        let pts = elements(S.outlinePath(rowRect: row)).compactMap { e -> CGPoint? in
            switch e { case .move(let p), .line(let p), .curve(let p): return p; case .close: return nil }
        }
        // x 11...209, y 21...55
        let tangents = [
            CGPoint(x: 11, y: 29), CGPoint(x: 19, y: 21),      // top-leading
            CGPoint(x: 201, y: 21), CGPoint(x: 209, y: 29),    // top-trailing
            CGPoint(x: 209, y: 47), CGPoint(x: 201, y: 55),    // bottom-trailing
            CGPoint(x: 19, y: 55), CGPoint(x: 11, y: 47),      // bottom-leading
        ]
        for t in tangents { #expect(pts.contains { near($0, t) }, "missing tangent point \(t)") }
        // Nothing strays outside the inset rect.
        for p in pts {
            #expect(p.x >= 11 - 0.01 && p.x <= 209 + 0.01 && p.y >= 21 - 0.01 && p.y <= 55 + 0.01, "\(p) outside the 1pt inset")
        }
    }

    @Test("The traced path's tight bounds are the row inset by 1pt on every side")
    func pathBoundsAreTheInsetRow() {
        let box = S.outlinePath(rowRect: row).cgPath.boundingBox
        #expect(abs(box.minX - 11) < 0.01 && abs(box.minY - 21) < 0.01)
        #expect(abs(box.maxX - 209) < 0.01 && abs(box.maxY - 55) < 0.01)
    }

    @Test("A tile-sized rect (the rail's 40pt chip) keeps r8 and starts at its leading middle")
    func pathAroundTheTile() throws {
        let tile = CGRect(x: 4, y: 4, width: 40, height: 40)
        let els = elements(S.outlinePath(rowRect: tile))
        guard case .move(let start) = try #require(els.first) else { return }
        #expect(near(start, CGPoint(x: 5, y: 24)))
        guard case .line(let up) = els[1] else { Issue.record("second element is not a line"); return }
        #expect(near(up, CGPoint(x: 5, y: 13)), "r8 on a 38pt inset square: the corner starts at y = 5 + 8")
    }

    @Test("box(): the row at morph 0, the chip at 1, linear between")
    func boxMorphs() {
        let chip = CGRect(x: 4, y: 8, width: 40, height: 40)
        #expect(S.box(row: row, chip: chip, morph: 0) == row)
        #expect(S.box(row: row, chip: chip, morph: 1) == chip)
        let half = S.box(row: row, chip: chip, morph: 0.5)
        #expect(abs(half.minX - 7) < 1e-9 && abs(half.minY - 14) < 1e-9 && abs(half.width - 120) < 1e-9 && abs(half.height - 38) < 1e-9)
    }
}

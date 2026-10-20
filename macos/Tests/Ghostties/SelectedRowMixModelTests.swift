import Foundation
import Testing
@testable import Ghostty

/// The selected-row mix's pure timeline (`SelectedRowMix`, contract
/// `docs/plans/selected-row-mix-contract.md`): row motion 04 Hand-off,
/// project switch P1 Cross-fade, new tab N4 Outline first, Switch 300ms,
/// New tab 600ms (Sean, 2026-10-19).
///
/// Every expected number is the output of
/// `node docs/plans/selected-row-mix-reference.js`, a port of the r9 engine
/// at the board's Mix values. Do not edit these to match a build; if the
/// build measures differently, the build is wrong or the contract changes
/// first. Tolerance covers the bezier solver's own stop.
///
/// Fixture: projects "A" (holding the active session a1, plus a2), "B" (b1),
/// "C" folded, "E" folded. Times are ms on the timeline's own clock.
struct SelectedRowMixModelTests {
    private typealias M = SelectedRowMix
    private let tol = 1e-3

    private let a1 = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private let a2 = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
    private let b1 = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
    private let n1 = UUID(uuidString: "00000000-0000-0000-0000-0000000000F1")!
    private let n2 = UUID(uuidString: "00000000-0000-0000-0000-0000000000F2")!

    private func fresh() -> M.Timeline {
        M.Timeline(active: a1, activeGroup: "A", collapsed: ["C", "E"])
    }

    private func near(_ a: Double, _ b: Double, _ t: Double? = nil) -> Bool { abs(a - b) < (t ?? tol) }

    private func expectRow(
        _ got: M.RowLook, _ outline: Double, _ tint: Double, _ height: Double, _ content: Double, _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(near(got.outline, outline), "\(label): outline \(got.outline) != \(outline)", sourceLocation: sourceLocation)
        #expect(near(got.tint, tint), "\(label): tint \(got.tint) != \(tint)", sourceLocation: sourceLocation)
        #expect(near(got.height, height), "\(label): height \(got.height) != \(height)", sourceLocation: sourceLocation)
        #expect(near(got.content, content), "\(label): content \(got.content) != \(content)", sourceLocation: sourceLocation)
    }

    private func expectGroup(
        _ got: M.GroupLook, _ card: Double, _ open: Double, _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(near(got.card, card), "\(label): card \(got.card) != \(card)", sourceLocation: sourceLocation)
        #expect(near(got.open, open), "\(label): open \(got.open) != \(open)", sourceLocation: sourceLocation)
    }

    // MARK: - Constants and curves

    @Test("The picked totals, Reduce Motion fades, resting outline and overshoot constant")
    func constants() {
        #expect(M.switchMs == 300)
        #expect(M.newTabMs == 600)
        #expect(M.reduceMotionInMs == 120)
        #expect(M.reduceMotionOutMs == 100)
        #expect(M.restOutlineOpacity == 0.4)
        #expect(M.overshootY2 == 1.2)
    }

    @Test("Opacity curve: bezier(0.77, 0, 0.175, 1)", arguments: [
        (0.0, 0.0), (0.1, 0.006445), (0.25, 0.052889), (0.5, 0.595971), (0.75, 0.956282), (0.9, 0.994468), (1.0, 1.0),
    ])
    func easeMatchesTheReference(x: Double, y: Double) {
        #expect(near(M.ease(x), y), "ease(\(x)) = \(M.ease(x))")
    }

    @Test("Size curve: bezier(0.77, 0, 0.175, overshootY2)", arguments: [
        (0.0, 0.0), (0.1, 0.007713), (0.25, 0.062925), (0.5, 0.67922), (0.75, 1.014076),
        (0.8, 1.021255), (0.85, 1.022214), (0.9, 1.018386), (0.95, 1.010749), (1.0, 1.0),
    ])
    func easeOvershootMatchesTheReference(x: Double, y: Double) {
        #expect(near(M.easeOvershoot(x), y), "easeOvershoot(\(x)) = \(M.easeOvershoot(x))")
    }

    @Test("Slow start on both; only the size curve passes its target, slightly, late, and lands exactly")
    func curveShapes() {
        #expect(M.ease(0.25) < 0.1 && M.easeOvershoot(0.25) < 0.1, "ease-in: slow start")
        var peak = 0.0
        for i in 0...1000 {
            let x = Double(i) / 1000
            #expect(M.ease(x) <= 1 + 1e-9, "opacity curve never overshoots (x \(x))")
            peak = max(peak, M.easeOvershoot(x))
        }
        #expect(peak > 1.015 && peak <= 1.03, "size overshoot peak \(peak): visible (about 1pt on a 48pt row), never more than 3%")
        #expect(M.easeOvershoot(0.75) > 1 && M.easeOvershoot(0.9) > 1, "past the target late in the segment")
        #expect(M.easeOvershoot(0.65) < 1, "not before about 70%")
        #expect(M.easeOvershoot(1) == 1 && M.ease(1) == 1 && M.easeOvershoot(0) == 0)
        #expect(M.ease(-1) == 0 && M.ease(2) == 1 && M.easeOvershoot(2) == 1)
    }

    // MARK: - Resting state

    @Test("At rest: the active row is outline 0.4 + tint, its group holds the card, folds are as given")
    func restingState() {
        let tl = fresh()
        expectRow(tl.row(a1, at: 0), 0.4, 1, 1, 1, "active row")
        expectRow(tl.row(a2, at: 0), 0, 0, 1, 1, "other row")
        expectGroup(tl.group("A", at: 0), 1, 1, "A")
        expectGroup(tl.group("B", at: 0), 0, 1, "B")
        expectGroup(tl.group("C", at: 0), 0, 0, "C folded")
        #expect(tl.collapsed == ["C", "E"])
        #expect(tl.active == a1 && tl.activeGroup == "A")
    }

    @Test("Selecting the row that is already active does nothing")
    func reselectIsANoOp() {
        var tl = fresh()
        tl.select(a1, in: "A", via: .click, reduceMotion: false, at: 50)
        expectRow(tl.row(a1, at: 60), 0.4, 1, 1, 1, "still resting")
        #expect(tl.settledAt <= 50)
    }

    // MARK: - Row switch (same project) @ 300

    @Test("Row switch, click: 04 hand-off over 300ms", arguments: [
        // t, from (outline, tint), to (outline, tint)
        (0.0, 0.4, 1.0, 0.0, 0.0),
        (75.0, 0.378845, 0.871391, 0.021155, 0.0),
        (150.0, 0.161612, 0.077666, 0.238388, 0.096638),
        (225.0, 0.017487, 0.0, 0.382513, 0.898687),
        (300.0, 0.0, 0.0, 0.4, 1.0),
    ])
    func rowSwitch(t: Double, fo: Double, ft: Double, to: Double, tt: Double) {
        var tl = fresh()
        tl.select(a2, in: "A", via: .click, reduceMotion: false, at: 0)
        expectRow(tl.row(a1, at: t), fo, ft, 1, 1, "from @\(t)")
        expectRow(tl.row(a2, at: t), to, tt, 1, 1, "to @\(t)")
        expectGroup(tl.group("A", at: t), 1, 1, "card stays on A @\(t)")
    }

    @Test("Row switch: the old tint is gone by 218ms, the new tint waits until 82ms, all done at 300")
    func rowSwitchOffsets() {
        var tl = fresh()
        tl.select(a2, in: "A", via: .click, reduceMotion: false, at: 0)
        #expect(tl.settledAt == 300)
        #expect(tl.row(a2, at: 81).tint == 0, "new tint has not started at 81ms")
        #expect(tl.row(a2, at: 100).tint > 1e-3, "new tint is under way by 100ms")
        #expect(near(tl.row(a1, at: 160 * 300 / 220).tint, 0), "old tint done at 218.2ms")
    }

    // MARK: - Project switch @ 300

    @Test("Project switch A -> B, click: card cross-fades in place over 300; hand-off inside it ends at 275", arguments: [
        // t, from (o, tint), to (o, tint), card A, card B
        (0.0, 0.4, 1.0, 0.0, 0.0, 1.0, 0.0),
        (75.0, 0.373461, 0.828791, 0.026539, 0.0, 0.947111, 0.052889),
        (150.0, 0.103449, 0.043718, 0.296551, 0.171209, 0.404029, 0.595971),
        (225.0, 0.008232, 0.0, 0.391768, 0.956282, 0.043718, 0.956282),
        (300.0, 0.0, 0.0, 0.4, 1.0, 0.0, 1.0),
    ])
    func projectSwitch(t: Double, fo: Double, ft: Double, to: Double, tt: Double, ca: Double, cb: Double) {
        var tl = fresh()
        tl.select(b1, in: "B", via: .click, reduceMotion: false, at: 0)
        expectRow(tl.row(a1, at: t), fo, ft, 1, 1, "from @\(t)")
        expectRow(tl.row(b1, at: t), to, tt, 1, 1, "to @\(t)")
        expectGroup(tl.group("A", at: t), ca, 1, "A @\(t)")
        expectGroup(tl.group("B", at: t), cb, 1, "B @\(t)")
        expectGroup(tl.group("C", at: t), 0, 0, "C @\(t)")
    }

    @Test("Project switch: the row lands at 275, the card at 300")
    func projectSwitchLanding() {
        var tl = fresh()
        tl.select(b1, in: "B", via: .click, reduceMotion: false, at: 0)
        #expect(tl.settledAt == 300)
        expectRow(tl.row(b1, at: 275), 0.4, 1, 1, 1, "hand-off done at 275")
        #expect(tl.group("B", at: 275).card < 1 - 1e-4, "card still landing at 275")
        // Cross-fade, in place: the two cards always sum to one card.
        for t in stride(from: 0.0, through: 300, by: 10) {
            #expect(near(tl.group("A", at: t).card + tl.group("B", at: t).card, 1), "one card's worth @\(t)")
        }
    }

    @Test("A project switch never folds or unfolds any group: click, key and Reduce Motion")
    func projectSwitchNeverChangesFolds() {
        for (via, rm) in [(M.Input.click, false), (.key, false), (.click, true)] {
            var tl = fresh()
            tl.select(b1, in: "B", via: via, reduceMotion: rm, at: 0)
            #expect(tl.collapsed == ["C", "E"], "\(via) rm=\(rm): collapsed set changed")
            for t in stride(from: 0.0, through: 400, by: 25) {
                #expect(tl.group("A", at: t).open == 1 && tl.group("B", at: t).open == 1, "\(via) rm=\(rm) open groups @\(t)")
                #expect(tl.group("C", at: t).open == 0 && tl.group("E", at: t).open == 0, "\(via) rm=\(rm) folded groups @\(t)")
            }
        }
    }

    // MARK: - New tab @ 600

    @Test("New tab into the active project: outline first, the slot grows under it, content fills after", arguments: [
        // t, from (o, tint), new (o, tint, height, content)
        (0.0, 0.4, 1.0, 0.0, 0.0, 0.0, 0.0),
        (150.0, 0.161612, 0.077666, 0.238388, 0.096638, 0.31905, 0.0),
        (300.0, 0.0, 0.0, 0.4, 1.0, 1.022325, 0.0),
        (450.0, 0.0, 0.0, 0.4, 1.0, 1.0, 0.36372),
        (600.0, 0.0, 0.0, 0.4, 1.0, 1.0, 1.0),
    ])
    func newTabActiveProject(t: Double, fo: Double, ft: Double, no: Double, nt: Double, nh: Double, nc: Double) {
        var tl = fresh()
        tl.newTab(n1, in: "A", reduceMotion: false, at: 0)
        expectRow(tl.row(a1, at: t), fo, ft, 1, 1, "from @\(t)")
        expectRow(tl.row(n1, at: t), no, nt, nh, nc, "new @\(t)")
        expectGroup(tl.group("A", at: t), 1, 1, "card never leaves A @\(t)")
        expectGroup(tl.group("C", at: t), 0, 0, "C untouched @\(t)")
        #expect(tl.active == n1 && tl.activeGroup == "A")
    }

    @Test("New tab: the row's height overshoots about 2% late in its 354.5ms segment and lands exactly on 1")
    func newTabHeightOvershoots() {
        var tl = fresh()
        tl.newTab(n1, in: "A", reduceMotion: false, at: 0)
        let end = 260.0 * 600 / 440
        for (pct, want) in [(80.0, 1.021255), (85.0, 1.022214), (90.0, 1.018386), (95.0, 1.010749)] {
            let h = tl.row(n1, at: end * pct / 100).height
            #expect(near(h, want), "height @\(pct)% = \(h)")
        }
        #expect(tl.row(n1, at: end * 0.85).height > 1.015, "visible overshoot (about 1pt on 48pt) at 85%")
        #expect(tl.row(n1, at: end).height == 1, "lands exactly at 100%")
        #expect(tl.row(n1, at: 600).height == 1)
        #expect(tl.settledAt == 600)
        // Content waits for the slot: nothing before 327.3ms.
        #expect(tl.row(n1, at: 327).content == 0)
        #expect(tl.row(n1, at: 350).content > 1e-3, "content under way by 350ms")
    }

    @Test("New tab into a folded project: only it unfolds (overshoot curve), the card cross-fades over 327ms", arguments: [
        // t, card A, card C, open C, new height
        (0.0, 1.0, 0.0, 0.0, 0.0),
        (150.0, 0.600893, 0.399107, 0.31905, 0.31905),
        (300.0, 0.003759, 0.996241, 1.022325, 1.022325),
        (450.0, 0.0, 1.0, 1.0, 1.0),
        (600.0, 0.0, 1.0, 1.0, 1.0),
    ])
    func newTabFoldedProject(t: Double, ca: Double, cc: Double, oc: Double, nh: Double) {
        var tl = fresh()
        tl.newTab(n1, in: "C", reduceMotion: false, at: 0)
        expectGroup(tl.group("A", at: t), ca, 1, "A @\(t)")
        expectGroup(tl.group("C", at: t), cc, oc, "C @\(t)")
        expectGroup(tl.group("E", at: t), 0, 0, "E stays folded @\(t)")
        expectGroup(tl.group("B", at: t), 0, 1, "B untouched @\(t)")
        #expect(near(tl.row(n1, at: t).height, nh), "new row height @\(t)")
    }

    @Test("New tab into a folded project removes only that project from the folded set")
    func newTabUnfoldsOnlyItsProject() {
        var tl = fresh()
        tl.newTab(n1, in: "C", reduceMotion: false, at: 0)
        #expect(tl.collapsed == ["E"])
        var rm = fresh()
        rm.newTab(n1, in: "C", reduceMotion: true, at: 0)
        #expect(rm.collapsed == ["E"])
    }

    @Test("A second new tab lands the first at once, then plays its own")
    func secondNewTabLandsTheFirst() {
        var tl = fresh()
        tl.newTab(n1, in: "A", reduceMotion: false, at: 0)
        tl.newTab(n2, in: "A", reduceMotion: false, at: 100)
        let first = tl.row(n1, at: 100)
        #expect(first.height == 1 && first.content == 1, "first insert landed: \(first)")
        expectRow(tl.row(n2, at: 100), 0, 0, 0, 0, "second starts from nothing")
        #expect(tl.settledAt == 700)
    }

    // MARK: - Keys snap

    @Test("Cmd+Shift+] / [ across projects: the end state at once, no frame in between")
    func keysSnap() {
        var tl = fresh()
        tl.select(b1, in: "B", via: .key, reduceMotion: false, at: 0)
        expectRow(tl.row(a1, at: 0), 0, 0, 1, 1, "old row gone")
        expectRow(tl.row(b1, at: 0), 0.4, 1, 1, 1, "new row at rest")
        expectGroup(tl.group("A", at: 0), 0, 1, "A")
        expectGroup(tl.group("B", at: 0), 1, 1, "B")
        #expect(tl.settledAt <= 0)
    }

    @Test("A key press mid-motion lands everything in flight and snaps to the new row")
    func keyMidMotionSnaps() {
        var tl = fresh()
        tl.newTab(n1, in: "C", reduceMotion: false, at: 0)
        tl.select(a2, in: "A", via: .key, reduceMotion: false, at: 100)
        expectRow(tl.row(n1, at: 100), 0, 0, 1, 1, "inserted row landed, not selected")
        expectGroup(tl.group("C", at: 100), 0, 1, "C finished opening")
        expectRow(tl.row(a2, at: 100), 0.4, 1, 1, 1, "key target at rest")
        expectRow(tl.row(a1, at: 100), 0, 0, 1, 1, "earlier row cleared")
        expectGroup(tl.group("A", at: 100), 1, 1, "card on A")
        #expect(tl.settledAt <= 100)
    }

    // MARK: - Retarget

    @Test("Retarget mid-switch (A -> B @0, back to A @100): continues from the live frame, never restarts, never queues", arguments: [
        // t, card A, card B, a1 (o, tint), b1 (o, tint)
        (100.0, 0.883032, 0.116968, 0.338321, 0.404029, 0.061679, 0.010467),
        (175.0, 0.889219, 0.110781, 0.342413, 0.404029, 0.057587, 0.008675),
        (250.0, 0.952742, 0.047258, 0.384048, 0.506065, 0.015952, 0.000458),
        (325.0, 0.994886, 0.005114, 0.398731, 0.973945, 0.001269, 0.0),
        (400.0, 1.0, 0.0, 0.4, 1.0, 0.0, 0.0),
    ])
    func retarget(t: Double, ca: Double, cb: Double, ao: Double, at: Double, bo: Double, bt: Double) {
        var tl = fresh()
        tl.select(b1, in: "B", via: .click, reduceMotion: false, at: 0)
        tl.select(a1, in: "A", via: .click, reduceMotion: false, at: 100)
        expectGroup(tl.group("A", at: t), ca, 1, "A @\(t)")
        expectGroup(tl.group("B", at: t), cb, 1, "B @\(t)")
        expectRow(tl.row(a1, at: t), ao, at, 1, 1, "a1 @\(t)")
        expectRow(tl.row(b1, at: t), bo, bt, 1, 1, "b1 @\(t)")
    }

    @Test("Retarget: no jump at the retarget instant, monotonic after it, done 300ms after it")
    func retargetIsContinuous() {
        var live = fresh()
        live.select(b1, in: "B", via: .click, reduceMotion: false, at: 0)
        let cardA: M.GroupLook = live.group("A", at: 100)
        let cardB: M.GroupLook = live.group("B", at: 100)
        let rowA: M.RowLook = live.row(a1, at: 100)
        let rowB: M.RowLook = live.row(b1, at: 100)
        live.select(a1, in: "A", via: .click, reduceMotion: false, at: 100)
        #expect(live.group("A", at: 100) == cardA, "A's card jumped at the retarget")
        #expect(live.group("B", at: 100) == cardB, "B's card jumped at the retarget")
        #expect(live.row(a1, at: 100) == rowA, "a1 jumped at the retarget")
        #expect(live.row(b1, at: 100) == rowB, "b1 jumped at the retarget")
        #expect(live.settledAt == 400, "300ms from the retarget, not after the first switch's tail (no queue)")
        var lastB: Double = cardB.card
        var lastA: Double = rowA.outline
        for t in stride(from: 100.0, through: 400, by: 5) {
            let b = live.group("B", at: t).card, a = live.row(a1, at: t).outline
            #expect(b <= lastB + 1e-9, "B's card only leaves after the retarget (@\(t))")
            #expect(a >= lastA - 1e-9, "a1's outline only returns after the retarget (@\(t))")
            lastB = b; lastA = a
        }
    }

    @Test("A project switch during a new tab's unfold never stops the unfold half-way")
    func switchDuringUnfold() {
        var tl = fresh()
        tl.newTab(n1, in: "C", reduceMotion: false, at: 0)
        tl.select(b1, in: "B", via: .click, reduceMotion: false, at: 150)
        expectGroup(tl.group("C", at: 450), 0, 1, "C finished opening, card moved on to B (switch @150 + 300)")
        #expect(tl.row(n1, at: 600).height == 1 && tl.row(n1, at: 600).content == 1, "the insert finished")
        #expect(tl.collapsed == ["E"])
    }

    // MARK: - Reduce Motion

    @Test("Reduce Motion, project switch: opacity only, out 100ms, in 120ms, ease-in-out", arguments: [
        // t, from (o, tint), to (o, tint), card A, card B
        (0.0, 0.4, 1.0, 0.0, 0.0, 1.0, 0.0),
        (50.0, 0.161612, 0.404029, 0.102164, 0.255411, 0.404029, 0.255411),
        (60.0, 0.064605, 0.161512, 0.238388, 0.595971, 0.161512, 0.595971),
        (100.0, 0.0, 0.0, 0.393243, 0.983108, 0.0, 0.983108),
        (120.0, 0.0, 0.0, 0.4, 1.0, 0.0, 1.0),
    ])
    func reduceMotionSwitch(t: Double, fo: Double, ft: Double, to: Double, tt: Double, ca: Double, cb: Double) {
        var tl = fresh()
        tl.select(b1, in: "B", via: .click, reduceMotion: true, at: 0)
        expectRow(tl.row(a1, at: t), fo, ft, 1, 1, "from @\(t)")
        expectRow(tl.row(b1, at: t), to, tt, 1, 1, "to @\(t)")
        expectGroup(tl.group("A", at: t), ca, 1, "A @\(t)")
        expectGroup(tl.group("B", at: t), cb, 1, "B @\(t)")
    }

    @Test("Reduce Motion, new tab into a folded project: it opens at once, the row is full height, only opacity fades", arguments: [
        // t, new (o, tint, content), card C
        (0.0, 0.0, 0.0, 0.0, 0.0),
        (60.0, 0.238388, 0.595971, 0.595971, 0.595971),
        (120.0, 0.4, 1.0, 1.0, 1.0),
    ])
    func reduceMotionNewTab(t: Double, no: Double, nt: Double, nc: Double, cc: Double) {
        var tl = fresh()
        tl.newTab(n1, in: "C", reduceMotion: true, at: 0)
        expectRow(tl.row(n1, at: t), no, nt, 1, nc, "new @\(t)")
        expectGroup(tl.group("C", at: t), cc, 1, "C @\(t)")
    }

    @Test("Reduce Motion: nothing changes size, and every event is over within 120ms", arguments: [0, 1, 2, 3])
    func reduceMotionIsOpacityOnly(scenario: Int) {
        var tl = fresh()
        switch scenario {
        case 0: tl.select(a2, in: "A", via: .click, reduceMotion: true, at: 0)
        case 1: tl.select(b1, in: "B", via: .click, reduceMotion: true, at: 0)
        case 2: tl.newTab(n1, in: "A", reduceMotion: true, at: 0)
        default: tl.newTab(n1, in: "C", reduceMotion: true, at: 0)
        }
        #expect(tl.settledAt <= 120, "scenario \(scenario) runs \(tl.settledAt)ms")
        for t in stride(from: 0.0, through: 200, by: 4) {
            for id in [a1, a2, b1, n1] { #expect(tl.row(id, at: t).height == 1, "scenario \(scenario): row height moves @\(t)") }
            for g in ["A", "B", "C", "E"] {
                let open = tl.group(g, at: t).open
                #expect(open == 0 || open == 1, "scenario \(scenario): \(g) open \(open) mid-way @\(t)")
            }
        }
    }

    // MARK: - Ranges

    @Test("Opacities stay in 0...1 (outline 0...0.4) on every frame of every event; size overshoot stays under 3%")
    func channelRanges() {
        var scenarios: [M.Timeline] = []
        var s = fresh(); s.select(a2, in: "A", via: .click, reduceMotion: false, at: 0); scenarios.append(s)
        s = fresh(); s.select(b1, in: "B", via: .click, reduceMotion: false, at: 0); s.select(a1, in: "A", via: .click, reduceMotion: false, at: 100); scenarios.append(s)
        s = fresh(); s.newTab(n1, in: "C", reduceMotion: false, at: 0); scenarios.append(s)
        s = fresh(); s.newTab(n1, in: "A", reduceMotion: false, at: 0); s.select(b1, in: "B", via: .click, reduceMotion: false, at: 200); scenarios.append(s)
        for (i, tl) in scenarios.enumerated() {
            for t in stride(from: 0.0, through: 900, by: 3) {
                for id in [a1, a2, b1, n1] {
                    let r = tl.row(id, at: t)
                    #expect(r.outline >= 0 && r.outline <= 0.4 + 1e-9, "#\(i) outline \(r.outline) @\(t)")
                    #expect(r.tint >= 0 && r.tint <= 1, "#\(i) tint \(r.tint) @\(t)")
                    #expect(r.content >= 0 && r.content <= 1, "#\(i) content \(r.content) @\(t)")
                    #expect(r.height >= 0 && r.height <= 1.03, "#\(i) height \(r.height) @\(t)")
                }
                for g in ["A", "B", "C", "E"] {
                    let x = tl.group(g, at: t)
                    #expect(x.card >= 0 && x.card <= 1, "#\(i) \(g) card \(x.card) @\(t)")
                    #expect(x.open >= 0 && x.open <= 1.03, "#\(i) \(g) open \(x.open) @\(t)")
                }
            }
        }
    }
}

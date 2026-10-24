import Foundation

/// The selected row's motion (Sean, 2026-10-19, r9 board Mix; contract
/// `docs/plans/selected-row-mix-contract.md`): row motion 04 Hand-off,
/// project switch P1 Cross-fade, new tab N4 Outline first, Switch 300ms,
/// New tab 600ms. At rest the selected row is a 1pt `inkSecondary` outline
/// at 0.4 over the selected-row tint, and one group card sits behind the
/// project holding it.
///
/// A pure timeline: every input is explicit, there is no clock inside. The
/// views (`SelectedRowMixDriver`) feed it events on their own clock and
/// read each row's and group's look at the current ms, ticking only while
/// `ms < settledAt`. A port of the r9 engine at the board's Mix values
/// (`docs/plans/selected-row-mix-reference.js`).
enum SelectedRowMix {
    static let switchMs: Double = 300
    static let newTabMs: Double = 600
    static let reduceMotionInMs: Double = 120
    static let reduceMotionOutMs: Double = 100
    static let restOutlineOpacity: Double = 0.4
    /// The size curve's second control point's y: 1.2 passes the target
    /// late and peaks about 2.25% over (Sean picked it over 1.1's 0.6%).
    static let overshootY2: Double = 1.2

    /// Opacity channels and every Reduce Motion fade.
    static func ease(_ x: Double) -> Double { bezier(x, y2: 1) }
    /// Size channels (a new row's height, a folded target's unfold).
    static func easeOvershoot(_ x: Double) -> Double { bezier(x, y2: overshootY2) }

    /// `bezier(0.77, 0, 0.175, y2)`, clamped 0...1 in x: Newton on x(t),
    /// eight steps, as the engine solves it.
    private static func bezier(_ x: Double, y2: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        let (p1x, p1y, p2x) = (0.77, 0.0, 0.175)
        let cx = 3 * p1x, bx = 3 * (p2x - p1x) - cx, ax = 1 - cx - bx
        let cy = 3 * p1y, by = 3 * (y2 - p1y) - cy, ay = 1 - cy - by
        func sx(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
        func sy(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
        func dx(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }
        var t = x
        for _ in 0..<8 {
            let e = sx(t) - x
            if abs(e) < 1e-7 { break }
            let d = dx(t)
            if abs(d) < 1e-6 { break }
            t -= e / d
        }
        return sy(t)
    }

    /// One session row. `outline`: the outline's opacity (0...0.4); `tint`:
    /// the selected-row tint's opacity scale (0...1); `height`: the row's
    /// height as a fraction of its natural height (1 except a growing new
    /// row; may pass 1 by < 3%); `content`: the row's glyph and label
    /// opacity (1 except a new row filling in).
    struct RowLook: Equatable {
        var outline, tint, height, content: Double

        static let rest = RowLook(outline: restOutlineOpacity, tint: 1, height: 1, content: 1)
        static let clear = RowLook(outline: 0, tint: 0, height: 1, content: 1)
    }

    /// One project group. `card`: the active-group card's opacity behind
    /// it, and its tile's ink fill; `open`: how unfolded it is, 0...1 (may
    /// pass 1 by < 3% while unfolding).
    struct GroupLook: Equatable { var card, open: Double }

    // MARK: - Variant numbers

    /// The variants' own (unscaled) numbers; one factor per event scales
    /// them to the picked total.
    private enum Row04 { static let dur = 220.0, fromTint = (0.0, 160.0), toTint = (60.0, 220.0) }
    private enum P1 { static let dur = 240.0 }
    private enum N4 { static let height = (0.0, 260.0), content = (240.0, 440.0), open = (0.0, 260.0), dur = 440.0 }
    private static let kRow = switchMs / Row04.dur
    private static let kSwitch = switchMs / P1.dur
    private static let kNewTab = newTabMs / N4.dur

    // MARK: - Channel

    /// One animated value: holds `from` until `a`, then runs to `to` by `b`
    /// on its curve. A new event replaces the track from the channel's
    /// value at that instant: never from 0, never queued.
    struct Channel: Equatable {
        enum Curve: Equatable { case ease, overshoot }
        let isSize: Bool
        private(set) var from: Double
        private(set) var to: Double
        private(set) var a: Double = 0
        private(set) var b: Double = 0
        private(set) var curve: Curve = .ease

        init(_ value: Double, size: Bool = false) {
            isSize = size
            from = value
            to = value
        }

        func value(_ t: Double) -> Double {
            let p = b <= a ? (t >= a ? 1 : 0) : min(max((t - a) / (b - a), 0), 1)
            let e = curve == .ease ? SelectedRowMix.ease(p) : SelectedRowMix.easeOvershoot(p)
            let v = from + (to - from) * e
            return isSize ? v : min(max(v, 0), 1)
        }

        mutating func run(_ t: Double, to target: Double, _ a: Double, _ b: Double, curve: Curve? = nil) {
            from = value(t)
            to = target
            self.a = t + a
            self.b = t + b
            self.curve = curve ?? (isSize ? .overshoot : .ease)
        }

        mutating func snap(_ t: Double, _ target: Double) {
            from = target
            to = target
            a = t
            b = t
            curve = .ease
        }

        mutating func finish(_ t: Double) { snap(t, to) }

        var end: Double { b }
    }

    private struct RowChannels: Equatable {
        var outline = Channel(0), tint = Channel(0), height = Channel(1, size: true), content = Channel(1)
        var all: [Channel] { [outline, tint, height, content] }
    }

    private struct GroupChannels: Equatable {
        var card: Channel, open: Channel
        var all: [Channel] { [card, open] }
    }

    // MARK: - Timeline

    struct Timeline: Equatable {
        private(set) var active: UUID?
        private(set) var activeGroup: String?
        /// The folds to persist (`ProjectAccordionState`).
        private(set) var collapsed: Set<String>
        private var rows: [UUID: RowChannels] = [:]
        private var groups: [String: GroupChannels] = [:]
        private var inserting: UUID?

        init(active: UUID?, activeGroup: String?, collapsed: Set<String>) {
            self.active = active
            self.activeGroup = activeGroup
            self.collapsed = collapsed
            if let active {
                ensureRow(active)
                rows[active]!.outline.snap(0, restOutlineOpacity)
                rows[active]!.tint.snap(0, 1)
            }
            if let activeGroup {
                ensureGroup(activeGroup)
                groups[activeGroup]!.card.snap(0, 1)
            }
        }

        private mutating func ensureRow(_ id: UUID) {
            if rows[id] == nil { rows[id] = RowChannels() }
        }

        private mutating func ensureGroup(_ id: String) {
            if groups[id] == nil {
                groups[id] = GroupChannels(card: Channel(0), open: Channel(collapsed.contains(id) ? 0 : 1, size: true))
            }
        }

        /// 04: the old row's outline and tint out, the new row's in, on factor `k`.
        private mutating func handOff(from: UUID?, to: UUID, _ t: Double, k: Double) {
            if let from, from != to {
                ensureRow(from)
                rows[from]!.outline.run(t, to: 0, 0, Row04.dur * k)
                rows[from]!.tint.run(t, to: 0, Row04.fromTint.0 * k, Row04.fromTint.1 * k)
            }
            ensureRow(to)
            rows[to]!.outline.run(t, to: restOutlineOpacity, 0, Row04.dur * k)
            rows[to]!.tint.run(t, to: 1, Row04.toTint.0 * k, Row04.toTint.1 * k)
        }

        /// P1: every other group's card out, the target's in, in place, on factor `k`.
        private mutating func crossFade(to target: String, _ t: Double, k: Double) {
            ensureGroup(target)
            for id in groups.keys {
                groups[id]!.card.run(t, to: id == target ? 1 : 0, 0, P1.dur * k)
            }
        }

        /// Reduce Motion: timed fades from the current value, nothing changes size.
        private mutating func reduceMotionFade(from: UUID?, to: UUID, target: String, _ t: Double) {
            if let from, from != to {
                ensureRow(from)
                rows[from]!.outline.run(t, to: 0, 0, reduceMotionOutMs, curve: .ease)
                rows[from]!.tint.run(t, to: 0, 0, reduceMotionOutMs, curve: .ease)
            }
            ensureRow(to)
            rows[to]!.outline.run(t, to: restOutlineOpacity, 0, reduceMotionInMs, curve: .ease)
            rows[to]!.tint.run(t, to: 1, 0, reduceMotionInMs, curve: .ease)
            if target != activeGroup {
                ensureGroup(target)
                for id in groups.keys {
                    let incoming = id == target
                    groups[id]!.card.run(t, to: incoming ? 1 : 0, 0, incoming ? reduceMotionInMs : reduceMotionOutMs, curve: .ease)
                }
            }
            for id in groups.keys { groups[id]!.open.finish(t) }
            if let inserting {
                ensureRow(inserting)
                rows[inserting]!.height.finish(t)
                rows[inserting]!.content.run(t, to: 1, 0, reduceMotionInMs, curve: .ease)
            }
        }

        mutating func select(_ session: UUID, in group: String, reduceMotion: Bool, at t: Double) {
            guard session != active else { return }
            let from = active, sameGroup = group == activeGroup
            if reduceMotion {
                reduceMotionFade(from: from, to: session, target: group, t)
            } else {
                if !sameGroup { crossFade(to: group, t, k: kSwitch) }
                handOff(from: from, to: session, t, k: sameGroup ? kRow : kSwitch)
            }
            active = session
            activeGroup = group
        }

        mutating func newTab(_ session: UUID, in group: String, reduceMotion: Bool, at t: Double) {
            // A new tab while another is still growing: the earlier one lands at once.
            if let inserting {
                ensureRow(inserting)
                rows[inserting]!.height.finish(t)
                rows[inserting]!.content.finish(t)
            }
            let from = active, wasCollapsed = collapsed.contains(group)
            ensureGroup(group) // created while still folded: its open starts at 0
            ensureRow(session)
            collapsed.remove(group) // only the target unfolds
            inserting = session
            if reduceMotion {
                rows[session]!.height.snap(t, 1)
                rows[session]!.content.snap(t, 0)
                if wasCollapsed { groups[group]!.open.snap(t, 1) }
                reduceMotionFade(from: from, to: session, target: group, t)
            } else {
                rows[session]!.height.snap(t, 0)
                rows[session]!.content.snap(t, 0)
                if wasCollapsed { groups[group]!.open.run(t, to: 1, N4.open.0 * kNewTab, N4.open.1 * kNewTab) }
                let settled = groups.allSatisfy { id, g in g.card.value(t) == (id == group ? 1 : 0) }
                if !settled { crossFade(to: group, t, k: kNewTab) }
                rows[session]!.height.run(t, to: 1, N4.height.0 * kNewTab, N4.height.1 * kNewTab)
                rows[session]!.content.run(t, to: 1, N4.content.0 * kNewTab, N4.content.1 * kNewTab)
                handOff(from: from, to: session, t, k: kNewTab)
            }
            active = session
            activeGroup = group
        }

        /// The ms an unknown row reads `(0, 0, 1, 1)`.
        func row(_ session: UUID, at t: Double) -> RowLook {
            guard let r = rows[session] else { return .clear }
            return RowLook(outline: r.outline.value(t), tint: r.tint.value(t), height: r.height.value(t), content: r.content.value(t))
        }

        func group(_ group: String, at t: Double) -> GroupLook {
            guard let g = groups[group] else {
                return GroupLook(card: group == activeGroup ? 1 : 0, open: collapsed.contains(group) ? 0 : 1)
            }
            return GroupLook(card: g.card.value(t), open: g.open.value(t))
        }

        /// The ms the last channel lands.
        var settledAt: Double {
            max(0, (rows.values.flatMap(\.all) + groups.values.flatMap(\.all)).map(\.end).max() ?? 0)
        }

        // MARK: View support

        /// The ms this row's last channel lands (0 for an unknown row), so
        /// only the rows in motion tick.
        func rowSettledAt(_ session: UUID) -> Double {
            rows[session]?.all.map(\.end).max() ?? 0
        }

        /// The ms this group's card lands.
        func cardSettledAt(_ group: String) -> Double {
            groups[group]?.card.end ?? 0
        }

        /// The groups whose card is lit, or fading, at `t` or after it.
        func litGroups(at t: Double) -> Set<String> {
            var lit = Set(groups.compactMap { id, g in g.card.value(t) > 0 || g.card.end > t ? id : nil })
            if let activeGroup { lit.insert(activeGroup) }
            return lit
        }

        /// A chevron fold or unfold, which the model does not animate (it
        /// keeps `SidebarUISpring.fold`): the folded set follows the
        /// persisted one, and a group not mid-unfold takes its new state.
        mutating func syncCollapsed(_ folded: Set<String>, at t: Double) {
            guard folded != collapsed else { return }
            collapsed = folded
            for id in groups.keys where groups[id]!.open.end <= t {
                groups[id]!.open.snap(t, folded.contains(id) ? 0 : 1)
            }
        }
    }
}

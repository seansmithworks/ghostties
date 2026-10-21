import AppKit
import Combine
import SwiftUI

/// One list's `SelectedRowMix.Timeline` on a clock (the sidebar list, the
/// rail and the hover panel each own one). The list feeds it a `Snapshot`
/// on every change; a change of selection becomes one event, its input read
/// from `SessionCoordinator.selectionCause`. Rows, cards and tiles read
/// their look through `SelectedRowMixRowReader` / `SelectedRowMixGroupReader`,
/// which tick only while their own channels are in motion, so a resting
/// list never ticks.
@MainActor
final class SelectedRowMixDriver: ObservableObject {
    /// What the list shows that the timeline needs.
    struct Snapshot: Equatable {
        /// The selected row: a session, the History row, or nothing.
        var selected: UUID?
        /// Its project group's id (`SidebarProjectGroup.ID`), or `noGroup`.
        var group: String
        /// Every session row the list shows, so a new tab is a row that
        /// was not there before.
        var rows: Set<UUID>
        /// The folded groups (`ProjectAccordionState`).
        var collapsed: Set<String>
    }

    /// The rows and groups an event started moving.
    struct Touched {
        var rows: Set<UUID>
        var groups: Set<String>
    }

    private(set) var timeline: SelectedRowMix.Timeline?
    private var last: Snapshot?
    private let epoch: Date
    let events = PassthroughSubject<Touched, Never>()

    init(epoch: Date = Date()) {
        self.epoch = epoch
    }

    /// The timeline's ms at `date`.
    func ms(_ date: Date = Date()) -> Double {
        #if DEBUG
        if let frozen = CaptureFixture.mixFreezeMs, let lastEventMs { return min(date.timeIntervalSince(epoch) * 1000, lastEventMs + frozen) }
        #endif
        return date.timeIntervalSince(epoch) * 1000
    }

    #if DEBUG
    private var lastEventMs: Double?
    #endif

    /// The first snapshot: the timeline at rest on it. A no-op once primed,
    /// so the list can call it from every body pass.
    func prime(_ snapshot: Snapshot) {
        guard timeline == nil else { return }
        timeline = Self.resting(snapshot)
        last = snapshot
    }

    private static func resting(_ s: Snapshot) -> SelectedRowMix.Timeline {
        SelectedRowMix.Timeline(active: s.selected, activeGroup: s.selected == nil ? nil : s.group, collapsed: s.collapsed)
    }

    /// A list change. A new selection is one event: a new tab (a session
    /// created into a row that was not there before), otherwise the
    /// hand-off, whatever caused it (a click, a key, a session closing).
    func update(_ snapshot: Snapshot, cause: SessionCoordinator.SelectionCause?, reduceMotion: Bool, now: Date = Date()) {
        guard var tl = timeline, let last else {
            prime(snapshot)
            return
        }
        let t = ms(now)
        tl.syncCollapsed(snapshot.collapsed, at: t)
        var touched = Touched(rows: [], groups: [])
        if snapshot.selected != last.selected {
            touched.groups = tl.litGroups(at: t)
            if let id = snapshot.selected {
                if cause?.id == id, cause?.kind == .newTab, !last.rows.contains(id) {
                    tl.newTab(id, in: snapshot.group, reduceMotion: reduceMotion, at: t)
                } else {
                    tl.select(id, in: snapshot.group, reduceMotion: reduceMotion, at: t)
                }
            } else {
                // Nothing selected (the last session closed): at rest on nothing.
                tl = Self.resting(snapshot)
            }
            touched.rows = Set([last.selected, snapshot.selected].compactMap { $0 })
            touched.groups.formUnion(tl.litGroups(at: t))
            #if DEBUG
            lastEventMs = t
            #endif
        }
        timeline = tl
        self.last = snapshot
        if !touched.rows.isEmpty || !touched.groups.isEmpty { events.send(touched) }
    }

    /// The groups whose card is drawn now: lit, fading, or `selected`.
    func cardGroups(selected: String?) -> Set<String> {
        var lit = timeline?.litGroups(at: ms()) ?? []
        if let selected { lit.insert(selected) }
        return lit
    }
}

extension SelectedRowMix {
    /// The group of a row outside any project group (Pinned, the Sessions
    /// tab, History): no card.
    static let noGroup = ""
    /// The History row's id on the timeline.
    static let historyRowID = UUID(uuidString: "00000000-0000-0000-0000-00000000F15E")!

    /// A new tab's unfold of a folded project, on the size curve (N4's
    /// 260ms at the 600ms total). Reduce Motion: at once.
    static func unfoldAnimation(reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) -> Animation? {
        reduceMotion ? nil : .timingCurve(0.77, 0, 0.175, overshootY2, duration: 260 * newTabMs / 440 / 1000)
    }
}

// MARK: - Environment

private struct SelectedRowMixDriverKey: EnvironmentKey {
    static let defaultValue: SelectedRowMixDriver? = nil
}

private struct SelectedRowMixGroupKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The enclosing list's driver; nil outside a list (a lone row in a
    /// test), where every reader shows its resting look.
    var selectedRowMixDriver: SelectedRowMixDriver? {
        get { self[SelectedRowMixDriverKey.self] }
        set { self[SelectedRowMixDriverKey.self] = newValue }
    }

    /// The project group a header belongs to, so its tile's ink follows
    /// the group's card.
    var selectedRowMixGroup: String? {
        get { self[SelectedRowMixGroupKey.self] }
        set { self[SelectedRowMixGroupKey.self] = newValue }
    }
}

// MARK: - Readers

/// Where a reader stands: ticking while its channels move, settled after.
private struct SelectedRowMixClock: ViewModifier {
    let driver: SelectedRowMixDriver?
    let isTouched: (SelectedRowMixDriver.Touched) -> Bool
    let settledAt: () -> Double
    @Binding var generation: Int
    @Binding var settleTick: Int

    func body(content: Content) -> some View {
        content
            .onReceive(driver?.events.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { touched in
                if isTouched(touched) { generation &+= 1 }
            }
            .task(id: generation) {
                guard generation > 0, let driver else { return }
                let remaining = settledAt() - driver.ms()
                guard remaining > 0 else { return }
                try? await Task.sleep(nanoseconds: UInt64((remaining + 16) * 1_000_000))
                guard !Task.isCancelled else { return }
                settleTick &+= 1
            }
    }
}

/// A session (or History) row's look at this instant: the timeline's while
/// its row is in motion, its resting look otherwise.
struct SelectedRowMixRowReader<Content: View>: View {
    let id: UUID?
    let isActive: Bool
    @ViewBuilder let content: (SelectedRowMix.RowLook) -> Content

    @Environment(\.selectedRowMixDriver) private var driver
    @State private var generation = 0
    @State private var settleTick = 0

    var body: some View {
        // An event that touched this reader (`generation`) or the end of its
        // motion (`settleTick`) re-reads the timeline, so `running` unpauses
        // the clock at the event and pauses it again at rest.
        let _ = (generation, settleTick)
        let end = id.flatMap { driver?.timeline?.rowSettledAt($0) } ?? 0
        let running = driver.map { $0.ms() < end } ?? false
        TimelineView(.animation(minimumInterval: nil, paused: !running)) { context in
            content(look(at: running ? context.date : .distantFuture))
        }
        .modifier(SelectedRowMixClock(
            driver: driver,
            isTouched: { [id] in id.map($0.rows.contains) ?? false },
            settledAt: { [id, driver] in id.flatMap { driver?.timeline?.rowSettledAt($0) } ?? 0 },
            generation: $generation, settleTick: $settleTick
        ))
    }

    private func look(at date: Date) -> SelectedRowMix.RowLook {
        guard let id, let driver, let timeline = driver.timeline else { return isActive ? .rest : .clear }
        return timeline.row(id, at: driver.ms(date))
    }
}

/// A project group's card level (the card's opacity and its tile's ink) at
/// this instant.
struct SelectedRowMixGroupReader<Content: View>: View {
    let id: String?
    /// The level outside a list, or before the list has a timeline.
    let fallback: Double
    @ViewBuilder let content: (Double) -> Content

    @Environment(\.selectedRowMixDriver) private var driver
    @State private var generation = 0
    @State private var settleTick = 0

    var body: some View {
        // An event that touched this reader (`generation`) or the end of its
        // motion (`settleTick`) re-reads the timeline, so `running` unpauses
        // the clock at the event and pauses it again at rest.
        let _ = (generation, settleTick)
        let end = id.flatMap { driver?.timeline?.cardSettledAt($0) } ?? 0
        let running = driver.map { $0.ms() < end } ?? false
        TimelineView(.animation(minimumInterval: nil, paused: !running)) { context in
            content(level(at: running ? context.date : .distantFuture))
        }
        .modifier(SelectedRowMixClock(
            driver: driver,
            isTouched: { [id] in id.map($0.groups.contains) ?? false },
            settledAt: { [id, driver] in id.flatMap { driver?.timeline?.cardSettledAt($0) } ?? 0 },
            generation: $generation, settleTick: $settleTick
        ))
    }

    private func level(at date: Date) -> Double {
        guard let id, let driver, let timeline = driver.timeline else { return fallback }
        return timeline.group(id, at: driver.ms(date)).card
    }
}

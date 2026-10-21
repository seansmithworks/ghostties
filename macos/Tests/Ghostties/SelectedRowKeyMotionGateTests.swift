import AppKit
import Combine
import SwiftUI
import Testing
@testable import Ghostty

/// Amendment 4 (`docs/plans/selected-row-mix-contract.md`): every selection
/// change animates the click hand-off, about 300ms. A key-driven change
/// (Cmd+Shift+] / [, Cmd+1-9, a session closing) reaches the list as an
/// untagged `activeSessionId` change: `focusSession` and `switchToNextSession`
/// never call `noteSelectionCause`. These gates drive exactly that, through
/// `SessionCoordinator.setActiveSessionIdForTesting` and the same live
/// driver / reader slice as `SelectedRowMixMotionGateTests`, and require
/// intermediate presented values, not a one-frame jump.
///
/// A rapid second press retargets from the presented value: never from 0 or
/// the rest value, never queued. If a build measures outside a band, report
/// the measurement; do not edit the band.
@MainActor
struct SelectedRowKeyMotionGateTests {
    private static let rowA = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000A1")!
    private static let rowB = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000B2")!
    private static let rowC = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000C3")!
    private static let g1 = "group-one"
    private static let g2 = "group-two"
    private static let all: Set<UUID> = [rowA, rowB, rowC]

    private typealias Snapshot = SelectedRowMixDriver.Snapshot

    private final class Probe {
        var rows: [UUID: [SelectedRowMix.RowLook]] = [:]
        var cards: [String: [Double]] = [:]
        func lastRow(_ id: UUID) -> SelectedRowMix.RowLook? { rows[id]?.last }
        func lastCard(_ id: String) -> Double? { cards[id]?.last }
    }

    private final class Stage: ObservableObject {
        @Published var snapshot: Snapshot
        init(_ snapshot: Snapshot) { self.snapshot = snapshot }
    }

    private static let cellW: CGFloat = 40
    private static let cellH: CGFloat = 20

    private struct Harness: View {
        @ObservedObject var stage: Stage
        let driver: SelectedRowMixDriver
        let coordinator: SessionCoordinator
        let probe: Probe

        var body: some View {
            let snapshot = stage.snapshot
            VStack(spacing: 0) {
                rowCell(SelectedRowKeyMotionGateTests.rowA)
                rowCell(SelectedRowKeyMotionGateTests.rowB)
                rowCell(SelectedRowKeyMotionGateTests.rowC)
                groupCell(SelectedRowKeyMotionGateTests.g1)
                groupCell(SelectedRowKeyMotionGateTests.g2)
            }
            .frame(width: SelectedRowKeyMotionGateTests.cellW, height: SelectedRowKeyMotionGateTests.cellH * 5, alignment: .top)
            .background(Color.black)
            .environment(\.selectedRowMixDriver, driver)
            .onChange(of: snapshot) { snapshot in
                driver.update(snapshot, cause: coordinator.selectionCause, reduceMotion: false)
            }
        }

        private func rowCell(_ id: UUID) -> some View {
            SelectedRowMixRowReader(id: id, isActive: stage.snapshot.selected == id) { look in
                let _ = probe.rows[id, default: []].append(look)
                Rectangle().fill(Color.white)
                    .opacity(look.outline / SelectedRowMix.restOutlineOpacity)
                    .frame(width: SelectedRowKeyMotionGateTests.cellW, height: SelectedRowKeyMotionGateTests.cellH)
            }
        }

        private func groupCell(_ id: String) -> some View {
            SelectedRowMixGroupReader(id: id, fallback: 0) { card in
                let _ = probe.cards[id, default: []].append(card)
                Rectangle().fill(Color.white).opacity(card)
                    .frame(width: SelectedRowKeyMotionGateTests.cellW, height: SelectedRowKeyMotionGateTests.cellH)
            }
        }
    }

    @MainActor private struct Live {
        let stage: Stage
        let coordinator: SessionCoordinator
        let probe: Probe
        let window: NSWindow
        let hosting: NSHostingView<Harness>

        /// A key press: the coordinator's active session changes with no
        /// `noteSelectionCause`, then the list's snapshot follows it.
        func keySelect(_ id: UUID, group: String) {
            coordinator.setActiveSessionIdForTesting(id)
            stage.snapshot = Snapshot(selected: id, group: group, rows: SelectedRowKeyMotionGateTests.all, collapsed: [])
        }
    }

    private func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Row A selected in group one; rows A, B, C all exist (no new tab).
    private func makeLive() -> Live {
        let start = Snapshot(selected: Self.rowA, group: Self.g1, rows: Self.all, collapsed: [])
        let stage = Stage(start)
        let driver = SelectedRowMixDriver()
        driver.prime(start)
        let coordinator = SessionCoordinator()
        coordinator.setActiveSessionIdForTesting(Self.rowA)
        let probe = Probe()
        let hosting = NSHostingView(rootView: Harness(stage: stage, driver: driver, coordinator: coordinator, probe: probe))
        hosting.frame = NSRect(x: 0, y: 0, width: Self.cellW, height: Self.cellH * 5)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        pump(0.05)
        return Live(stage: stage, coordinator: coordinator, probe: probe, window: window, hosting: hosting)
    }

    private func strictlyBetween(_ x: Double, _ lo: Double, _ hi: Double, margin: Double = 0.03) -> Bool {
        x > min(lo, hi) + margin && x < max(lo, hi) - margin
    }

    // MARK: - Cmd+Shift+] / [ (same project)

    @Test func nextSessionKeyHandsOffOver300ms() throws {
        let live = makeLive()
        defer { live.window.orderOut(nil) }
        let rest = SelectedRowMix.restOutlineOpacity

        // Vacuity guard: the cause really is absent, and A starts drawn.
        #expect(live.coordinator.selectionCause == nil, "a key press carries no selection cause")
        #expect(abs((live.probe.lastRow(Self.rowA)?.outline ?? 0) - rest) < 0.001, "start: A drawn")

        live.keySelect(Self.rowB, group: Self.g1)
        pump(0.15)

        let a = try #require(live.probe.lastRow(Self.rowA)), b = try #require(live.probe.lastRow(Self.rowB))
        #expect(strictlyBetween(a.outline, rest, 0), "mid-flight: A's outline \(a.outline) should be between \(rest) and 0")
        #expect(strictlyBetween(b.outline, 0, rest), "mid-flight: B's outline \(b.outline) should be between 0 and \(rest)")
        #expect(strictlyBetween(b.tint, 0, 1, margin: 0.01), "mid-flight: B's tint \(b.tint) should be between 0 and 1")

        // Not a one-frame jump: B passes through several distinct values.
        let distinct = Set((live.probe.rows[Self.rowB] ?? []).map { ($0.outline * 1000).rounded() })
        #expect(distinct.count >= 4, "B's outline took \(distinct.count) distinct values, a jump rather than a fade")

        pump(0.45)
        let a2 = try #require(live.probe.lastRow(Self.rowA)), b2 = try #require(live.probe.lastRow(Self.rowB))
        #expect(abs(a2.outline) < 0.001 && abs(b2.outline - rest) < 0.001, "settled: A \(a2.outline), B \(b2.outline)")
    }

    @Test func aSecondKeyPressRetargetsFromThePresentedValue() throws {
        let live = makeLive()
        defer { live.window.orderOut(nil) }
        let rest = SelectedRowMix.restOutlineOpacity

        live.keySelect(Self.rowB, group: Self.g1)
        pump(0.12)
        let bBefore = try #require(live.probe.lastRow(Self.rowB)).outline
        // Vacuity guard: B is genuinely mid-fade-in when the second press lands.
        #expect(strictlyBetween(bBefore, 0, rest), "before the second press B's outline \(bBefore) should be mid-flight")

        live.keySelect(Self.rowC, group: Self.g1)
        pump(0.02)
        // B now fades out from where it stood: not snapped to 0, not restarted at rest.
        let bAfter = try #require(live.probe.lastRow(Self.rowB)).outline
        #expect(abs(bAfter - bBefore) < 0.12, "B jumped from \(bBefore) to \(bAfter) at the retarget; it should continue from the presented value")
        #expect(bAfter > 0.001, "B snapped clear at the retarget (\(bAfter))")

        pump(0.13)
        let c = try #require(live.probe.lastRow(Self.rowC))
        #expect(strictlyBetween(c.outline, 0, rest), "mid-flight after the retarget: C's outline \(c.outline)")

        // Never queued: C lands about 300ms after the second press.
        pump(0.35)
        let c2 = try #require(live.probe.lastRow(Self.rowC)), b2 = try #require(live.probe.lastRow(Self.rowB))
        #expect(abs(c2.outline - rest) < 0.001 && abs(b2.outline) < 0.001, "settled: B \(b2.outline), C \(c2.outline)")
    }

    // MARK: - Cmd+1-9 (can cross projects)

    @Test func jumpToSessionKeyCrossFadesTheCardOver300ms() throws {
        let live = makeLive()
        defer { live.window.orderOut(nil) }
        let rest = SelectedRowMix.restOutlineOpacity

        live.keySelect(Self.rowB, group: Self.g2)
        pump(0.15)

        let c1 = try #require(live.probe.lastCard(Self.g1)), c2 = try #require(live.probe.lastCard(Self.g2))
        #expect(strictlyBetween(c1, 1, 0), "mid-flight: old card \(c1) should be between 1 and 0")
        #expect(strictlyBetween(c2, 0, 1), "mid-flight: new card \(c2) should be between 0 and 1")
        let b = try #require(live.probe.lastRow(Self.rowB))
        #expect(strictlyBetween(b.outline, 0, rest), "mid-flight: B's outline \(b.outline)")

        pump(0.45)
        let end1 = try #require(live.probe.lastCard(Self.g1)), end2 = try #require(live.probe.lastCard(Self.g2))
        #expect(abs(end2 - 1) < 0.001 && abs(end1) < 0.001, "settled cards: old \(end1), new \(end2)")
    }
}

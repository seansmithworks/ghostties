import AppKit
import Combine
import SwiftUI
import Testing
@testable import Ghostty

/// The selected-row motion in the live view tree (contract
/// `docs/plans/selected-row-mix-contract.md`, "Timing tables" and "Rules").
///
/// `SelectedRowMixModelTests` proves the timeline interpolates; this proves the
/// views draw it. The harness is the smallest real slice of `RecentsListView`:
/// a real `SelectedRowMixDriver` in the environment, fed by the same
/// `.onChange(of: snapshot) { driver.update(...) }` the list uses, a real
/// `SessionCoordinator` carrying the selection cause, and the real
/// `SelectedRowMixRowReader` / `SelectedRowMixGroupReader` inside an
/// `NSHostingView` in a window. Each reader's content draws its look as white
/// on black, so the gate reads both what the reader produced (`Probe`) and
/// the pixels that landed.
///
/// A mid-flight sample must sit strictly between the start and the end; a
/// view that jumps to the final value when the animation ends fails it. The
/// end of every case is asserted too, and a vacuity guard proves the start and
/// end states differ before any "between" is trusted. If a build measures
/// outside a band, report the measurement; do not edit the band.
@MainActor
struct SelectedRowMixMotionGateTests {
    // MARK: - Fixture

    private static let rowA = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000A1")!
    private static let rowB = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000B2")!
    private static let rowC = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000C3")!
    private static let g1 = "group-one"
    private static let g2 = "group-two"

    private typealias Snapshot = SelectedRowMixDriver.Snapshot

    /// Every look a reader's content closure was handed, in order.
    private final class Probe {
        var rows: [UUID: [SelectedRowMix.RowLook]] = [:]
        var cards: [String: [Double]] = [:]
        func row(_ id: UUID, _ look: SelectedRowMix.RowLook) { rows[id, default: []].append(look) }
        func card(_ id: String, _ level: Double) { cards[id, default: []].append(level) }
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
                rowCell(SelectedRowMixMotionGateTests.rowA)
                rowCell(SelectedRowMixMotionGateTests.rowB)
                rowCell(SelectedRowMixMotionGateTests.rowC)
                groupCell(SelectedRowMixMotionGateTests.g1)
                groupCell(SelectedRowMixMotionGateTests.g2)
            }
            .frame(width: cellW, height: cellH * 5, alignment: .top)
            .background(Color.black)
            .environment(\.selectedRowMixDriver, driver)
            // The list's wiring (RecentsListView): the driver sees every snapshot
            // change, with the cause the coordinator recorded for it.
            .onChange(of: snapshot) { snapshot in
                driver.update(snapshot, cause: coordinator.selectionCause, reduceMotion: false)
            }
        }

        private var cellW: CGFloat { SelectedRowMixMotionGateTests.cellW }
        private var cellH: CGFloat { SelectedRowMixMotionGateTests.cellH }

        private func rowCell(_ id: UUID) -> some View {
            SelectedRowMixRowReader(id: id, isActive: stage.snapshot.selected == id) { look in
                let _ = probe.row(id, look)
                ZStack(alignment: .top) {
                    Rectangle().fill(Color.white)
                        .opacity(look.outline / SelectedRowMix.restOutlineOpacity)
                        .frame(height: cellH * look.height)
                }
                .frame(width: cellW, height: cellH, alignment: .top)
            }
        }

        private func groupCell(_ id: String) -> some View {
            SelectedRowMixGroupReader(id: id, fallback: 0) { card in
                let _ = probe.card(id, card)
                Rectangle().fill(Color.white).opacity(card)
                    .frame(width: cellW, height: cellH)
            }
        }
    }

    private struct Live {
        let stage: Stage
        let driver: SelectedRowMixDriver
        let coordinator: SessionCoordinator
        let probe: Probe
        let hosting: NSHostingView<Harness>
        let window: NSWindow
    }

    private func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Row A selected in group one; rows A and B exist; group two holds B.
    private func makeLive() -> Live {
        let start = Snapshot(selected: Self.rowA, group: Self.g1, rows: [Self.rowA, Self.rowB], collapsed: [])
        let stage = Stage(start)
        let driver = SelectedRowMixDriver()
        driver.prime(start) // the list primes from its first body pass
        let coordinator = SessionCoordinator()
        let probe = Probe()
        let size = CGSize(width: Self.cellW, height: Self.cellH * 5)
        let hosting = NSHostingView(rootView: Harness(stage: stage, driver: driver, coordinator: coordinator, probe: probe))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        pump(0.05)
        return Live(stage: stage, driver: driver, coordinator: coordinator, probe: probe, hosting: hosting, window: window)
    }

    /// White-on-black luminance (0...1) at the centre of cell `index`, raw bytes.
    private func luminance(_ live: Live, cell index: Int) throws -> Double {
        live.hosting.layoutSubtreeIfNeeded()
        let rep = try #require(live.hosting.bitmapImageRepForCachingDisplay(in: live.hosting.bounds))
        live.hosting.cacheDisplay(in: live.hosting.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / live.hosting.bounds.width
        let px = Int(Self.cellW / 2 * scale), py = Int((Self.cellH * CGFloat(index) + Self.cellH / 2) * scale)
        let data = try #require(rep.bitmapData)
        let o = py * rep.bytesPerRow + px * (rep.bitsPerPixel / 8)
        return (Double(data[o]) + Double(data[o + 1]) + Double(data[o + 2])) / (3 * 255)
    }

    private let rowA = 0, rowB = 1, group1 = 3, group2 = 4

    private func strictlyBetween(_ x: Double, _ lo: Double, _ hi: Double, margin: Double = 0.03) -> Bool {
        x > min(lo, hi) + margin && x < max(lo, hi) - margin
    }

    // MARK: - 04 Hand-off (row click, same project)

    @Test func clickHandoffInterpolatesInTheLiveTree() throws {
        let live = makeLive()
        defer { live.window.orderOut(nil) }
        let rest = SelectedRowMix.restOutlineOpacity

        // Vacuity guard: before the click A is drawn, B is not.
        #expect(try luminance(live, cell: rowA) > 0.9, "start: A's outline should be drawn")
        #expect(try luminance(live, cell: rowB) < 0.1, "start: B's outline should be clear")

        live.stage.snapshot = Snapshot(selected: Self.rowB, group: Self.g1, rows: [Self.rowA, Self.rowB], collapsed: [])
        pump(0.15) // about half of the 300ms switch

        let a = try #require(live.probe.lastRow(Self.rowA))
        let b = try #require(live.probe.lastRow(Self.rowB))
        #expect(strictlyBetween(a.outline, rest, 0), "mid-flight: A's outline \(a.outline) should be between \(rest) and 0")
        #expect(strictlyBetween(b.outline, 0, rest), "mid-flight: B's outline \(b.outline) should be between 0 and \(rest)")
        #expect(strictlyBetween(b.tint, 0, 1, margin: 0.01), "mid-flight: B's tint \(b.tint) should be between 0 and 1")
        let la = try luminance(live, cell: rowA), lb = try luminance(live, cell: rowB)
        #expect(strictlyBetween(la, 1, 0, margin: 0.05), "mid-flight pixels: A \(la) should be between 1 and 0")
        #expect(strictlyBetween(lb, 0, 1, margin: 0.05), "mid-flight pixels: B \(lb) should be between 0 and 1")

        pump(0.45)
        let a2 = try #require(live.probe.lastRow(Self.rowA)), b2 = try #require(live.probe.lastRow(Self.rowB))
        #expect(abs(a2.outline) < 0.001 && abs(b2.outline - rest) < 0.001, "settled: A \(a2.outline), B \(b2.outline)")
        #expect(try luminance(live, cell: rowA) < 0.05 && luminance(live, cell: rowB) > 0.95, "settled pixels")
    }

    // MARK: - P1 Cross-fade (project switch)

    @Test func projectSwitchCrossFadesInTheLiveTree() throws {
        let live = makeLive()
        defer { live.window.orderOut(nil) }
        let rest = SelectedRowMix.restOutlineOpacity

        // Vacuity guard: the card sits on group one before the click.
        #expect(try luminance(live, cell: group1) > 0.9, "start: group one's card should be lit")
        #expect(try luminance(live, cell: group2) < 0.1, "start: group two's card should be clear")

        live.stage.snapshot = Snapshot(selected: Self.rowB, group: Self.g2, rows: [Self.rowA, Self.rowB], collapsed: [])
        pump(0.15)

        let c1 = try #require(live.probe.lastCard(Self.g1)), c2 = try #require(live.probe.lastCard(Self.g2))
        #expect(strictlyBetween(c1, 1, 0), "mid-flight: old card \(c1) should be between 1 and 0")
        #expect(strictlyBetween(c2, 0, 1), "mid-flight: new card \(c2) should be between 0 and 1")
        let b = try #require(live.probe.lastRow(Self.rowB))
        #expect(strictlyBetween(b.outline, 0, rest), "mid-flight: B's outline \(b.outline) should be between 0 and \(rest)")
        let l1 = try luminance(live, cell: group1), l2 = try luminance(live, cell: group2)
        #expect(strictlyBetween(l1, 1, 0, margin: 0.05), "mid-flight pixels: old card \(l1)")
        #expect(strictlyBetween(l2, 0, 1, margin: 0.05), "mid-flight pixels: new card \(l2)")

        pump(0.45)
        #expect(try luminance(live, cell: group1) < 0.05 && luminance(live, cell: group2) > 0.95, "settled card pixels")
        #expect(abs(try #require(live.probe.lastCard(Self.g2)) - 1) < 0.001)
    }

    // MARK: - N4 Outline first (new tab)

    @Test func newTabGrowsInTheLiveTree() throws {
        let live = makeLive()
        defer { live.window.orderOut(nil) }

        live.coordinator.noteSelectionCause(.newTab, for: Self.rowC)
        live.stage.snapshot = Snapshot(selected: Self.rowC, group: Self.g1, rows: [Self.rowA, Self.rowB, Self.rowC], collapsed: [])
        pump(0.15) // a quarter of the 600ms

        let c = try #require(live.probe.lastRow(Self.rowC))
        // Vacuity guard: the new row starts undrawn and ends drawn.
        #expect(live.probe.rows[Self.rowC]?.first?.outline == 0, "the new row should start with no outline")
        #expect(strictlyBetween(c.height, 0, 1, margin: 0.02), "mid-flight: new row height \(c.height) should be between 0 and 1")
        #expect(strictlyBetween(c.outline, 0, SelectedRowMix.restOutlineOpacity), "mid-flight: new row outline \(c.outline)")

        pump(0.75)
        let end = try #require(live.probe.lastRow(Self.rowC))
        #expect(abs(end.height - 1) < 0.001 && abs(end.content - 1) < 0.001 && abs(end.outline - SelectedRowMix.restOutlineOpacity) < 0.001,
                "settled: \(end)")
    }
}

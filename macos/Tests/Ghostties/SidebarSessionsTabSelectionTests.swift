import XCTest
import SwiftUI
import GhosttiesCore
@testable import Ghostty

/// The Sessions tab selects a row the way the Projects tab does: in the
/// expanded list the row-wide tint inside its drawn outline (r7 card 06), in
/// the rail a tile-sized chip centred on the rail. Read off rendered pixels of the real `RecentsListView`
/// and `SidebarRailView` with the tab pinned to Sessions, for a selected
/// active row and a selected pinned row (Pinned renders through the same
/// flat path in both tabs).
///
/// The mark is a 10% ink tint on the chrome; there is no group card behind
/// it here. Measured down a line 8pt inside the glyph tile's leading edge
/// (past the row's corner curve; the stopped glyph draws nothing) and across
/// the row 4pt below its top (inside the outline, above the title).
@MainActor
final class SidebarSessionsTabSelectionTests: XCTestCase {
    private struct Render {
        let rep: NSBitmapImageRep
        let scale: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    private func railWidth() throws -> CGFloat {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        let close = try XCTUnwrap(window.standardWindowButton(.closeButton))
        let zoom = try XCTUnwrap(window.standardWindowButton(.zoomButton))
        return WorkspaceLayout.collapsedRailWidth(
            zoomButtonMaxX: zoom.convert(zoom.bounds, to: nil).maxX,
            leadingInset: close.convert(close.bounds, to: nil).minX
        )
    }

    private func render(selectPinned: Bool, rail: Bool = false) throws -> Render {
        try withDials({ $0.set(SidebarTab.sessions.rawValue, forKey: "ghostties.sidebarTab") }) {
            let project = Project(name: "atlas-api", rootPath: "~/Code/atlas-api")
            let sessions = (0..<3).map { i in
                AgentSession(
                    name: "Session \(i)", templateId: AgentTemplate.claudeCode.id, projectId: project.id,
                    sortOrder: i, lastActiveAt: Date(), lastOutputAt: Date(), isNamePinned: true,
                    isPinned: i == 0
                )
            }
            let store = WorkspaceStore(
                testingProjects: [project], testingSessions: sessions,
                hasShownPinMigrationNotice: true, hasDismissedPinMigrationNotice: true
            )
            for s in sessions {
                store.updateIndicatorState(id: s.id, state: .inactive)
                store.updateSessionStatus(id: s.id, status: .running)
            }
            let coordinator = SessionCoordinator()
            coordinator.setActiveSessionIdForTesting(selectPinned ? sessions[0].id : sessions[2].id)

            let width: CGFloat = rail ? try railWidth() : 260
            let height: CGFloat = 400
            let chrome = try XCTUnwrap(ChromeTheme.ghostties(.light).chrome.usingColorSpace(.sRGB))
            let column = rail ? AnyView(SidebarRailColumn().asRail(width: width)) : AnyView(VStack(spacing: 0) {
                RecentsListView()
                Spacer(minLength: 0)
            })
            let root = column
                .frame(width: width, height: height)
                .environment(\.sidebarTrailingGutter, 0)
                .environmentObject(store)
                .environmentObject(coordinator)
                .environmentObject(SidebarWidthModel(width: width))
                .background(Color(nsColor: chrome))
            let hosting = NSHostingView(rootView: root)
            hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = hosting
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            hosting.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            return Render(rep: rep, scale: CGFloat(rep.pixelsWide) / width, width: width, height: height)
        }
    }

    /// Darker than the chrome by a tint (selected chip or row surface),
    /// lighter than text ink. The ceiling clears the selected outline's
    /// stroke (about 1.9x the tint's drop at its resting 0.4), which is part
    /// of the selected surface.
    private func isTint(_ r: Render, px x: Int, _ y: Int) -> Bool {
        guard let chrome = ChromeTheme.ghostties(.light).chrome.usingColorSpace(.sRGB),
              x >= 0, y >= 0, x < r.rep.pixelsWide, y < r.rep.pixelsHigh,
              let c = r.rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
        let base = chrome.redComponent + chrome.greenComponent + chrome.blueComponent
        let drop = base - (c.redComponent + c.greenComponent + c.blueComponent)
        let chipDrop = base * RailProjectColumn.selectedChipTintOpacity
        return drop > chipDrop / 3 && drop < chipDrop * 3
    }

    /// Contiguous tint runs, in points.
    private func runs(_ r: Render, alongX: Bool, at fixed: CGFloat) -> [ClosedRange<CGFloat>] {
        let count = alongX ? r.rep.pixelsWide : r.rep.pixelsHigh
        let f = Int(fixed * r.scale)
        var runs: [(Int, Int)] = []
        for i in 0..<count where isTint(r, px: alongX ? i : f, alongX ? f : i) {
            if let last = runs.last, i - last.1 <= 1 { runs[runs.count - 1].1 = i } else { runs.append((i, i)) }
        }
        return runs.map { CGFloat($0.0) / r.scale...CGFloat($0.1 + 1) / r.scale }
    }

    func testSelectedSessionsTabRowIsTheRowWideSurface() throws {
        for selectPinned in [false, true] {
            let tag = selectPinned ? "pinned" : "active"
            let r = try render(selectPinned: selectPinned)
            let chip = RailProjectColumn.chipSize(.sidebar)
            let rowMinX = SidebarDialTuning.windowMargin() + SidebarDialTuning.contentPaddingLeading()
            let probeX = rowMinX + SidebarDialTuning.rowLeadingPadding() + SidebarListRowChrome<EmptyView, EmptyView>.glyphSlotWidth / 2 - chip / 2 + 8
            // Exactly one tint run down the glyph column: the selected row's
            // surface, row-tall (the old chip was chip-tall).
            let down = runs(r, alongX: false, at: probeX)
            XCTAssertEqual(down.count, 1, "\(tag): one selected surface down the glyph column, got \(down)")
            let mark = try XCTUnwrap(down.first, "\(tag): no selected surface")
            XCTAssertEqual(mark.upperBound - mark.lowerBound, SidebarDialTuning.rowHeight(), accuracy: 1.0, "\(tag): selected surface is row-tall, not chip-tall (\(chip)pt)")
            // Across the row near its top: one run from the row's leading edge, far wider than a chip.
            let across = runs(r, alongX: true, at: mark.lowerBound + 4)
            let run = try XCTUnwrap(across.first { $0.contains(probeX) }, "\(tag): no surface across the row")
            XCTAssertGreaterThan(run.upperBound - run.lowerBound, chip * 3, "\(tag): selected surface is row-wide, not chip-wide (~\(chip)pt)")
            XCTAssertEqual(run.lowerBound, rowMinX, accuracy: 1.0, "\(tag): surface starts at the row's leading edge")
        }
    }

    /// The rail's Sessions tab marks the selected row with the rail chip,
    /// centred on the rail, not the rail-wide row card.
    func testSelectedRailSessionsTabRowIsTheChipNotTheRowCard() throws {
        for selectPinned in [false, true] {
            let tag = selectPinned ? "rail pinned" : "rail active"
            let r = try render(selectPinned: selectPinned, rail: true)
            let chip = RailProjectColumn.chipSize(.rail)
            let midX = r.width / 2
            let probeX = midX - chip / 2 + 8
            let down = runs(r, alongX: false, at: probeX)
            XCTAssertEqual(down.count, 1, "\(tag): one selected mark down the rail, got \(down)")
            let mark = try XCTUnwrap(down.first, "\(tag): no selected mark")
            XCTAssertEqual(mark.upperBound - mark.lowerBound, chip, accuracy: 1.0, "\(tag): selected mark is chip-tall, not a \(SidebarDialTuning.rowHeight())pt row card")
            let across = runs(r, alongX: true, at: (mark.lowerBound + mark.upperBound) / 2)
            let run = try XCTUnwrap(across.first { $0.contains(probeX) }, "\(tag): no mark across the rail")
            XCTAssertEqual(run.upperBound - run.lowerBound, chip, accuracy: 1.0, "\(tag): selected mark is chip-wide (~\(chip)pt), not the rail's width")
            XCTAssertEqual((run.lowerBound + run.upperBound) / 2, midX, accuracy: 1.0, "\(tag): chip centred on the rail")
        }
    }
}

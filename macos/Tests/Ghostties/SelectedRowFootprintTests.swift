import XCTest
import SwiftUI
import GhosttiesCore
@testable import Ghostty

/// The selected row is the option D chip, in the rail and the expanded list
/// alike (one piece in both modes): a tile-sized, flat 10% ink chip behind
/// the glyph, the hover's own footprint (`SidebarRowChipBackground` draws
/// both), never a row-wide card. Asserted on pixels: the selected surface is
/// chip-tall and chip-wide, centred on the glyph slot (the rail's centre in
/// the rail), and nothing marks the row card's corner.
@MainActor
final class SelectedRowFootprintTests: XCTestCase {
    private let height: CGFloat = 100

    // MARK: - Harness

    private func railWidth() throws -> CGFloat {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        let close = try XCTUnwrap(window.standardWindowButton(.closeButton))
        let zoom = try XCTUnwrap(window.standardWindowButton(.zoomButton))
        return WorkspaceLayout.collapsedRailWidth(
            zoomButtonMaxX: zoom.convert(zoom.bounds, to: nil).maxX,
            leadingInset: close.convert(close.bounds, to: nil).minX
        )
    }

    /// Rendered with the rim off, set in a private dial suite bound around
    /// the render (`withDials`).
    private func render<V: View>(_ view: V, width: CGFloat) throws -> (NSBitmapImageRep, CGFloat) {
        try withDials({ $0.set(0.0, forKey: SidebarDialTuning.lightGlassKeys.chromaticIntensity) }) {
            try renderInScope(view, width: width)
        }
    }

    private func renderInScope<V: View>(_ view: V, width: CGFloat) throws -> (NSBitmapImageRep, CGFloat) {
        let chrome = try XCTUnwrap(WorkspaceLayout.chromeBackgroundLight.usingColorSpace(.sRGB))
        let hosting = NSHostingView(rootView: view
            .frame(width: width, height: height, alignment: .top)
            .background(Color(nsColor: chrome)))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return (rep, CGFloat(rep.pixelsWide) / width)
    }

    /// True where the selected surface's tint darkens the pixel below the
    /// chrome.
    private func isSurface(_ rep: NSBitmapImageRep, scale: CGFloat, x: CGFloat, y: CGFloat) throws -> Bool {
        let chrome = try XCTUnwrap(WorkspaceLayout.chromeBackgroundLight.usingColorSpace(.sRGB))
        guard let c = rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB) else { return false }
        let tint = (chrome.redComponent + chrome.greenComponent + chrome.blueComponent)
            - (c.redComponent + c.greenComponent + c.blueComponent)
        return tint > 0.06
    }

    /// Asserts the selected surface is the chip of `side` centred at
    /// (`midX`, `midY`), probed down a line 8pt inside its leading edge (past
    /// its corner curve) and across the row there, and that the row card's
    /// corner (`rowMinX`, top) is unmarked.
    private func assertIsChip(_ rep: NSBitmapImageRep, scale: CGFloat, side chip: CGFloat, midX: CGFloat, midY: CGFloat, rowMinX: CGFloat, _ name: String) throws {
        let probe = CGPoint(x: midX - chip / 2 + 8, y: midY)
        let down = try XCTUnwrap(try surfaceRun(rep, scale: scale, alongX: false, through: probe), "\(name): no chip down the slot")
        XCTAssertEqual(down.upperBound - down.lowerBound, chip, accuracy: 1.0, "\(name): selected surface is chip-tall, not row-tall")
        XCTAssertEqual((down.lowerBound + down.upperBound) / 2, midY, accuracy: 1.0, "\(name): chip centred in the row")
        let across = try XCTUnwrap(try surfaceRun(rep, scale: scale, alongX: true, through: probe), "\(name): no chip across the slot")
        XCTAssertEqual(across.lowerBound, midX - chip / 2, accuracy: 1.0, "\(name): chip leading edge")
        XCTAssertEqual(across.upperBound, midX + chip / 2, accuracy: 1.0, "\(name): chip trailing edge")
        XCTAssertFalse(try isSurface(rep, scale: scale, x: rowMinX + 3, y: 3), "\(name): no row card")
    }

    // MARK: - Rail

    /// A rail row outside any project column (a Pinned or Sessions-tab row)
    /// selects with the rail chip, centred on the rail.
    func testRailSelectedRowIsTheChip() throws {
        let width = try railWidth()
        let column = VStack(spacing: 0) {
            RailSessionRow(sessionId: UUID(), name: "Claude Code 6", projectName: "atlas-api", indicatorState: .inactive, isActive: true, onTap: {})
        }
            .modifier(SidebarRailView.columnPadding)
            .environment(\.sidebarTrailingGutter, 0)
            .environmentObject(SessionCoordinator())
        let (rep, scale) = try render(column, width: width)
        try assertIsChip(
            rep, scale: scale, side: RailProjectColumn.chipSize(.rail),
            midX: width / 2, midY: SidebarDialTuning.contentPaddingTop() + SidebarDialTuning.rowHeight() / 2,
            rowMinX: SidebarDialTuning.windowMargin(), "rail"
        )
    }

    /// History in the rail selects with the same chip; the clock's ink sits
    /// inside it, so the chip's runs stay contiguous.
    func testRailHistorySelectedRowIsTheChip() throws {
        let width = try railWidth()
        let column = VStack(spacing: 0) {
            RailHistoryRow(subtitle: "3 sessions", isActive: true, onTap: {})
        }
            .modifier(SidebarRailView.columnPadding)
            .environment(\.sidebarTrailingGutter, 0)
        let (rep, scale) = try render(column, width: width)
        try assertIsChip(
            rep, scale: scale, side: RailProjectColumn.chipSize(.rail),
            midX: width / 2, midY: SidebarDialTuning.contentPaddingTop() + SidebarDialTuning.rowHeight() / 2,
            rowMinX: SidebarDialTuning.windowMargin(), "history"
        )
    }

    // MARK: - Expanded

    private struct ExpandedHarness: View {
        @FocusState private var focus: Bool
        @State private var name = ""
        var body: some View {
            RecentsRowView(
                session: AgentSession(
                    id: UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000EE")!,
                    name: "Claude Code 6", templateId: AgentTemplate.claudeCode.id,
                    projectId: UUID(), sortOrder: 0, lastActiveAt: Date(), lastOutputAt: Date(),
                    isNamePinned: true, ghostCharacter: .hex
                ),
                projectName: "atlas-api",
                indicatorState: .inactive,
                isActive: true,
                editingName: $name,
                isRenameFocused: $focus,
                onTap: {}
            )
            .equatable()
        }
    }

    /// Expanded list (option D, one rule): the selected row is the
    /// tile-sized chip behind the leading glyph slot, the hover's own
    /// footprint (`SidebarRowChipBackground` draws both), not a row card.
    func testExpandedSelectedRowIsTheChipBehindTheGlyphSlot() throws {
        let width: CGFloat = 220
        let inset: CGFloat = 10
        let row = ExpandedHarness()
            .padding(.horizontal, inset)
            .environmentObject(SidebarWidthModel(width: width))
            .environmentObject(SessionCoordinator())
        let (rep, scale) = try render(row, width: width)
        let chip = RailProjectColumn.chipSize(.sidebar)
        let slotMidX = inset + SidebarDialTuning.rowLeadingPadding() + SidebarListRowChrome<EmptyView, EmptyView>.glyphSlotWidth / 2
        let rowMidY = SidebarDialTuning.rowHeight() / 2
        // Down a line 8pt inside the chip (past its corner curve; the
        // stopped glyph draws nothing), and across the row's centre line
        // from there: contiguous runs, so the title ink can't join in.
        let down = try XCTUnwrap(try surfaceRun(rep, scale: scale, alongX: false, through: CGPoint(x: slotMidX - chip / 2 + 8, y: rowMidY)), "expanded: no chip down the slot")
        XCTAssertEqual(down.upperBound - down.lowerBound, chip, accuracy: 1.0, "expanded: selected surface is chip-tall, not row-tall")
        XCTAssertEqual((down.lowerBound + down.upperBound) / 2, rowMidY, accuracy: 1.0, "expanded: chip centred in the row")
        let across = try XCTUnwrap(try surfaceRun(rep, scale: scale, alongX: true, through: CGPoint(x: slotMidX - chip / 2 + 8, y: rowMidY)), "expanded: no chip across the slot")
        XCTAssertEqual(across.lowerBound, slotMidX - chip / 2, accuracy: 1.0, "expanded: chip leading edge")
        XCTAssertEqual(across.upperBound, slotMidX + chip / 2, accuracy: 1.0, "expanded: chip trailing edge")
        // Nothing at the row card's corner: no wide card is drawn.
        XCTAssertFalse(try isSurface(rep, scale: scale, x: inset + 3, y: 3), "expanded: no row card")
    }

    /// The contiguous run of surface pixels along one line through `point`.
    private func surfaceRun(_ rep: NSBitmapImageRep, scale: CGFloat, alongX: Bool, through point: CGPoint) throws -> ClosedRange<CGFloat>? {
        let count = alongX ? rep.pixelsWide : rep.pixelsHigh
        let start = Int((alongX ? point.x : point.y) * scale)
        func hit(_ i: Int) throws -> Bool {
            let p = CGFloat(i) / scale
            return try isSurface(rep, scale: scale, x: alongX ? p : point.x, y: alongX ? point.y : p)
        }
        guard start >= 0, start < count, try hit(start) else { return nil }
        var lo = start, hi = start
        while lo > 0, try hit(lo - 1) { lo -= 1 }
        while hi < count - 1, try hit(hi + 1) { hi += 1 }
        return CGFloat(lo) / scale...CGFloat(hi + 1) / scale
    }
}

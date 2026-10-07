import XCTest
import SwiftUI
import GhosttiesCore
@testable import Ghostty

/// The selected row card occupies exactly the hover card's footprint, in the
/// rail and the expanded list (Sean, 2026-10-07: "the size of the hover feels
/// good to me, filling the space").
///
/// The hover fill is the row frame's own background, a
/// `RoundedRectangle(cornerRadius: sidebarRowCornerRadiusResting)` filling the
/// row card (the column's content width × `rowHeight`). So "selected = hover
/// footprint" is asserted on pixels: the selected surface spans that whole
/// card, top to bottom and edge to edge, and its corner is the hover's radius
/// (a pixel 2.5pt in from the card corner is filled, one 0.5pt in is not).
/// Rendered with the flat selected style, since `cacheDisplay` can't capture
/// glass; the footprint is the same either way.
@MainActor
final class SelectedRowFootprintTests: XCTestCase {
    private let height: CGFloat = 100

    override func setUp() {
        super.setUp()
        XCTAssertTrue(SidebarDialTuning.store !== UserDefaults.standard, "dial store must be the isolated suite")
        SidebarDialTuning.store.set(TrayGlassStyle.SelectedRowStyle.flat.rawValue, forKey: SidebarDialTuning.selectedRowStyleKey)
    }

    override func tearDown() {
        SidebarDialTuning.store.removeObject(forKey: SidebarDialTuning.selectedRowStyleKey)
        super.tearDown()
    }

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

    private func render<V: View>(_ view: V, width: CGFloat) throws -> (NSBitmapImageRep, CGFloat) {
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

    /// True where the selected surface's light fill lifts the pixel above the
    /// chrome; the shadow only darkens, so it never counts.
    private func isSurface(_ rep: NSBitmapImageRep, scale: CGFloat, x: CGFloat, y: CGFloat) throws -> Bool {
        let chrome = try XCTUnwrap(WorkspaceLayout.chromeBackgroundLight.usingColorSpace(.sRGB))
        guard let c = rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB) else { return false }
        let lift = (c.redComponent + c.greenComponent + c.blueComponent)
            - (chrome.redComponent + chrome.greenComponent + chrome.blueComponent)
        return lift > 0.06
    }

    /// The single run of surface pixels along one line, in points.
    private func surfaceSpan(_ rep: NSBitmapImageRep, scale: CGFloat, alongX: Bool, at fixed: CGFloat) throws -> ClosedRange<CGFloat>? {
        let count = alongX ? rep.pixelsWide : rep.pixelsHigh
        var lo = Int.max, hi = -1
        for i in 0..<count {
            let p = CGFloat(i) / scale
            if try isSurface(rep, scale: scale, x: alongX ? p : fixed, y: alongX ? fixed : p) {
                lo = min(lo, i); hi = max(hi, i)
            }
        }
        return hi >= 0 ? CGFloat(lo) / scale...CGFloat(hi + 1) / scale : nil
    }

    /// Asserts the selected surface fills `card` (points) with the hover's
    /// corner radius.
    private func assertFillsHoverCard(_ rep: NSBitmapImageRep, scale: CGFloat, card: CGRect, _ name: String) throws {
        let across = try XCTUnwrap(try surfaceSpan(rep, scale: scale, alongX: true, at: card.midY), "\(name): no selected surface across the row")
        let down = try XCTUnwrap(try surfaceSpan(rep, scale: scale, alongX: false, at: card.midX), "\(name): no selected surface down the row")
        XCTAssertEqual(across.lowerBound, card.minX, accuracy: 1.0, "\(name): selected leading edge = hover leading edge")
        XCTAssertEqual(across.upperBound, card.maxX, accuracy: 1.0, "\(name): selected trailing edge = hover trailing edge")
        XCTAssertEqual(down.lowerBound, card.minY, accuracy: 1.0, "\(name): selected top = hover top")
        XCTAssertEqual(down.upperBound, card.maxY, accuracy: 1.0, "\(name): selected bottom = hover bottom")
        // Hover's corner radius (6): 2.5pt in on the diagonal is inside the
        // curve, 0.5pt in is outside it. A larger radius leaves 2.5pt empty.
        XCTAssertEqual(WorkspaceLayout.sidebarRowCornerRadiusResting, 6)
        for (cx, cy, dx, dy) in [(card.minX, card.minY, 1.0, 1.0), (card.maxX, card.maxY, -1.0, -1.0)] {
            XCTAssertTrue(try isSurface(rep, scale: scale, x: cx + 2.5 * dx, y: cy + 2.5 * dy), "\(name): corner at hover radius is filled")
            XCTAssertFalse(try isSurface(rep, scale: scale, x: cx + 0.5 * dx, y: cy + 0.5 * dy), "\(name): corner is rounded")
        }
    }

    // MARK: - Rail

    func testRailSelectedCardFillsTheHoverFootprint() throws {
        let width = try railWidth()
        let column = VStack(spacing: 0) {
            RailSessionRow(sessionId: UUID(), name: "Claude Code 6", projectName: "atlas-api", indicatorState: .inactive, isActive: true, onTap: {})
        }
            .modifier(SidebarRailView.columnPadding)
            .environment(\.sidebarTrailingGutter, 0)
            .environmentObject(SessionCoordinator())
        let (rep, scale) = try render(column, width: width)
        let margin = SidebarDialTuning.windowMargin()
        let card = CGRect(x: margin, y: SidebarDialTuning.contentPaddingTop(), width: width - 2 * margin, height: SidebarDialTuning.rowHeight())
        try assertFillsHoverCard(rep, scale: scale, card: card, "rail")
    }

    func testRailHistorySelectedCardFillsTheHoverFootprint() throws {
        let width = try railWidth()
        let column = VStack(spacing: 0) {
            RailHistoryRow(subtitle: "3 sessions", isActive: true, onTap: {})
        }
            .modifier(SidebarRailView.columnPadding)
            .environment(\.sidebarTrailingGutter, 0)
        let (rep, scale) = try render(column, width: width)
        let margin = SidebarDialTuning.windowMargin()
        let card = CGRect(x: margin, y: SidebarDialTuning.contentPaddingTop(), width: width - 2 * margin, height: SidebarDialTuning.rowHeight())
        // The clock glyph sits in the middle; the span check samples the
        // row's centre lines, so measure down a column clear of it.
        let down = try XCTUnwrap(try surfaceSpan(rep, scale: scale, alongX: false, at: card.minX + 8), "history: no selected surface")
        XCTAssertEqual(down.lowerBound, card.minY, accuracy: 1.0, "history: selected top = hover top")
        XCTAssertEqual(down.upperBound, card.maxY, accuracy: 1.0, "history: selected bottom = hover bottom")
        let across = try XCTUnwrap(try surfaceSpan(rep, scale: scale, alongX: true, at: card.minY + 4), "history: no selected surface across")
        XCTAssertEqual(across.lowerBound, card.minX, accuracy: 1.0, "history: selected leading edge = hover leading edge")
        XCTAssertEqual(across.upperBound, card.maxX, accuracy: 1.0, "history: selected trailing edge = hover trailing edge")
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

    func testExpandedSelectedCardFillsTheHoverFootprint() throws {
        let width: CGFloat = 220
        let inset: CGFloat = 10
        let row = ExpandedHarness()
            .padding(.horizontal, inset)
            .environmentObject(SidebarWidthModel(width: width))
            .environmentObject(SessionCoordinator())
        let (rep, scale) = try render(row, width: width)
        let card = CGRect(x: inset, y: 0, width: width - 2 * inset, height: SidebarDialTuning.rowHeight())
        // Title/subtitle ink sits mid-row on the leading side; the trailing
        // half is clear (stopped glyph draws nothing), so sample there.
        let across = try XCTUnwrap(try surfaceSpan(rep, scale: scale, alongX: true, at: card.minY + 4), "expanded: no selected surface across")
        XCTAssertEqual(across.lowerBound, card.minX, accuracy: 1.0, "expanded: selected leading edge = hover leading edge")
        XCTAssertEqual(across.upperBound, card.maxX, accuracy: 1.0, "expanded: selected trailing edge = hover trailing edge")
        let down = try XCTUnwrap(try surfaceSpan(rep, scale: scale, alongX: false, at: card.maxX - 12), "expanded: no selected surface down")
        XCTAssertEqual(down.lowerBound, card.minY, accuracy: 1.0, "expanded: selected top = hover top")
        XCTAssertEqual(down.upperBound, card.maxY, accuracy: 1.0, "expanded: selected bottom = hover bottom")
        for (cx, cy, dx, dy) in [(card.minX, card.minY, 1.0, 1.0), (card.maxX, card.maxY, -1.0, -1.0)] {
            XCTAssertTrue(try isSurface(rep, scale: scale, x: cx + 2.5 * dx, y: cy + 2.5 * dy), "expanded: corner at hover radius is filled")
            XCTAssertFalse(try isSurface(rep, scale: scale, x: cx + 0.5 * dx, y: cy + 0.5 * dy), "expanded: corner is rounded")
        }
    }
}

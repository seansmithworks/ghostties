import XCTest
import SwiftUI
import GhosttiesCore
@testable import Ghostty

/// Pixel coverage for the status-glyph slot of the expanded Sessions row
/// (`RecentsRowView`) and the collapsed-rail row (`RailSessionRow`).
///
/// The old ghost draws the same silhouette for every state, so "the slot
/// shows the glyph for this state" is asserted as "two different states
/// render different pixels in the trailing slot" — a revert to the ghost
/// makes them identical and fails. Rendering is pinned to light/dark by
/// window appearance, so the result doesn't depend on the system setting.
@MainActor
final class SessionRowGlyphSlotTests: XCTestCase {
    private let width: CGFloat = 220
    private let rowHeight: CGFloat = 48

    // MARK: - Harness

    private struct ExpandedHarness: View {
        let state: SessionIndicatorState
        @FocusState private var focus: Bool
        @State private var name = ""
        init(state: SessionIndicatorState) { self.state = state }
        var body: some View {
            RecentsRowView(
                session: AgentSession(
                    id: UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000BB")!,
                    name: "Claude Code 6", templateId: AgentTemplate.claudeCode.id,
                    projectId: UUID(), sortOrder: 0, lastActiveAt: Date(), lastOutputAt: Date(),
                    isNamePinned: true, ghostCharacter: .hex
                ),
                projectName: "atlas-api",
                indicatorState: state,
                isActive: false,
                editingName: $name,
                isRenameFocused: $focus,
                onTap: {}
            )
            .equatable()
        }
    }

    /// Both rows sit inside the same horizontal margins the real lists apply
    /// (`contentPaddingLeading/Trailing`), so the inset measured is the one a
    /// user sees.
    private func renderExpanded(_ state: SessionIndicatorState, appearance: NSAppearance.Name) -> NSBitmapImageRep? {
        render(
            ExpandedHarness(state: state)
                .environmentObject(SidebarWidthModel(width: width))
                .environmentObject(SessionCoordinator()),
            appearance: appearance
        )
    }

    private func renderRail(_ state: SessionIndicatorState, appearance: NSAppearance.Name) -> NSBitmapImageRep? {
        render(
            RailSessionRow(sessionId: UUID(), indicatorState: state, isActive: false, onTap: {})
                .environmentObject(SessionCoordinator()),
            appearance: appearance
        )
    }

    private func render<V: View>(_ row: V, appearance: NSAppearance.Name) -> NSBitmapImageRep? {
        let framed = row
            .padding(.leading, SidebarDialTuning.contentPaddingLeading())
            .padding(.trailing, SidebarDialTuning.contentPaddingTrailing())
            .frame(width: width, height: rowHeight)
            .background(Color(nsColor: appearance == .darkAqua ? .black : .white))
        let hosting = NSHostingView(rootView: framed)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: rowHeight)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }

    /// Pixels in the trailing 60pt of the row whose colour differs from the
    /// background, as (minX, maxX, minY, maxY) in points; nil if blank.
    private func inkBounds(_ rep: NSBitmapImageRep) -> (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat)? {
        let scale = CGFloat(rep.pixelsWide) / width
        let start = Int((width - 60) * scale)
        guard let bg = rep.colorAt(x: rep.pixelsWide - 1, y: 0)?.usingColorSpace(.sRGB) else { return nil }
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in 0..<rep.pixelsHigh {
            for x in start..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let d = abs(c.redComponent - bg.redComponent) + abs(c.greenComponent - bg.greenComponent) + abs(c.blueComponent - bg.blueComponent)
                if d > 0.45 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
            }
        }
        guard maxX >= 0 else { return nil }
        return (CGFloat(minX) / scale, CGFloat(maxX + 1) / scale, CGFloat(minY) / scale, CGFloat(maxY + 1) / scale)
    }

    private func trailingPixels(_ rep: NSBitmapImageRep) -> [UInt8] {
        let scale = CGFloat(rep.pixelsWide) / width
        let start = Int((width - 60) * scale)
        var out: [UInt8] = []
        for y in 0..<rep.pixelsHigh {
            for x in start..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                out.append(UInt8(c.redComponent * 255)); out.append(UInt8(c.greenComponent * 255))
            }
        }
        return out
    }

    // MARK: - The slot draws the state's glyph, not a ghost

    func testExpandedRowSlotDiffersByState() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let needs = try XCTUnwrap(renderExpanded(.needsAttention, appearance: appearance))
            let idle = try XCTUnwrap(renderExpanded(.idle, appearance: appearance))
            let error = try XCTUnwrap(renderExpanded(.error, appearance: appearance))
            let stopped = try XCTUnwrap(renderExpanded(.inactive, appearance: appearance))
            XCTAssertNotEqual(trailingPixels(needs), trailingPixels(idle), "? and check must differ (\(appearance))")
            XCTAssertNotEqual(trailingPixels(idle), trailingPixels(error), "check and x must differ (\(appearance))")
            XCTAssertNil(inkBounds(stopped), "a stopped row draws nothing in the slot (\(appearance))")
            XCTAssertNotNil(inkBounds(needs))
        }
    }

    func testRailRowSlotDiffersByState() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let needs = try XCTUnwrap(renderRail(.needsAttention, appearance: appearance))
            let idle = try XCTUnwrap(renderRail(.idle, appearance: appearance))
            let error = try XCTUnwrap(renderRail(.error, appearance: appearance))
            let stopped = try XCTUnwrap(renderRail(.inactive, appearance: appearance))
            XCTAssertNotEqual(trailingPixels(needs), trailingPixels(idle), "rail: ? and check must differ (\(appearance))")
            XCTAssertNotEqual(trailingPixels(idle), trailingPixels(error), "rail: check and x must differ (\(appearance))")
            XCTAssertNil(inkBounds(stopped), "rail: a stopped row draws nothing (\(appearance))")
            XCTAssertNotNil(inkBounds(needs))
        }
    }

    // MARK: - Same trailing inset and vertical position, expanded vs rail

    func testGlyphTrailingInsetAndVerticalPositionMatchBetweenExpandedAndRail() throws {
        for state in [SessionIndicatorState.needsAttention, .idle, .error] {
            let e = try XCTUnwrap(inkBounds(try XCTUnwrap(renderExpanded(state, appearance: .aqua))))
            let r = try XCTUnwrap(inkBounds(try XCTUnwrap(renderRail(state, appearance: .aqua))))
            XCTAssertEqual(width - e.maxX, width - r.maxX, accuracy: 0.6, "trailing inset, \(state)")
            XCTAssertEqual(e.minY, r.minY, accuracy: 0.6, "glyph top, \(state)")
            XCTAssertEqual(e.maxY, r.maxY, accuracy: 0.6, "glyph bottom, \(state)")
        }
    }
}

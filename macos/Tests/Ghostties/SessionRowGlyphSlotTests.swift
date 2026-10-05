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

    /// The Projects-tab session row (`SessionRow`, nested under a project).
    private struct ProjectRowHarness: View {
        let state: SessionIndicatorState
        @FocusState private var focus: Bool
        @State private var name = ""
        var body: some View {
            SessionRow(
                session: AgentSession(
                    id: UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000DD")!,
                    name: "Claude Code 6", templateId: AgentTemplate.claudeCode.id,
                    projectId: UUID(), sortOrder: 0, lastActiveAt: Date(), lastOutputAt: Date(),
                    isNamePinned: true, ghostCharacter: .hex
                ),
                indicatorState: state,
                editingName: $name,
                isRenameFocused: $focus,
                onCommitRename: {},
                onCancelRename: {}
            )
        }
    }

    private func renderProjectRow(_ state: SessionIndicatorState, appearance: NSAppearance.Name) -> NSBitmapImageRep? {
        render(ProjectRowHarness(state: state), appearance: appearance)
    }

    private func renderRail(_ state: SessionIndicatorState, appearance: NSAppearance.Name) -> NSBitmapImageRep? {
        render(
            RailSessionRow(sessionId: UUID(), name: "Claude Code 6", projectName: "atlas-api", indicatorState: state, isActive: false, onTap: {})
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

    func testProjectTabSessionRowSlotDrawsTheGlyphNotAGhost() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let needs = try XCTUnwrap(renderProjectRow(.needsAttention, appearance: appearance))
            let idle = try XCTUnwrap(renderProjectRow(.idle, appearance: appearance))
            let error = try XCTUnwrap(renderProjectRow(.error, appearance: appearance))
            let stopped = try XCTUnwrap(renderProjectRow(.inactive, appearance: appearance))
            XCTAssertNotEqual(trailingPixels(needs), trailingPixels(idle), "project row: ? and check must differ (\(appearance))")
            XCTAssertNotEqual(trailingPixels(idle), trailingPixels(error), "project row: check and x must differ (\(appearance))")
            XCTAssertNil(inkBounds(stopped), "project row: a stopped row draws nothing (\(appearance))")
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

    // MARK: - Rail rows sit at the expanded rows' y

    /// A store with one running session in `state`, so it lands in Active.
    private func store(state: SessionIndicatorState) -> WorkspaceStore {
        let project = Project(name: "atlas-api", rootPath: "~/Code/atlas-api")
        let session = AgentSession(
            id: UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000CC")!,
            name: "Claude Code 6", templateId: AgentTemplate.claudeCode.id,
            projectId: project.id, sortOrder: 0, lastActiveAt: Date(), lastOutputAt: Date(),
            isNamePinned: true, ghostCharacter: .hex
        )
        let store = WorkspaceStore(
            testingProjects: [project], testingSessions: [session],
            hasShownPinMigrationNotice: true, hasDismissedPinMigrationNotice: true
        )
        store.updateIndicatorState(id: session.id, state: state)
        store.updateSessionStatus(id: session.id, status: .running)
        return store
    }

    private func renderWholeSidebar(expanded: Bool, state: SessionIndicatorState, appearance: NSAppearance.Name) -> NSBitmapImageRep? {
        let s = store(state: state)
        let coordinator = SessionCoordinator()
        let size = CGSize(width: width, height: 260)
        let content: AnyView
        if expanded {
            // Mirrors `WorkspaceSidebarView`'s Sessions tab: the titlebar
            // toolbar band (`toolbarRowTopAnchorConstant * 2`), then the list.
            content = AnyView(
                VStack(spacing: 0) {
                    Color.clear.frame(height: s.toolbarRowTopAnchorConstant * 2)
                    RecentsListView()
                }
                .environmentObject(s).environmentObject(coordinator)
                .environmentObject(SidebarWidthModel(width: width))
            )
        } else {
            content = AnyView(
                SidebarRailView()
                    .environmentObject(s).environmentObject(coordinator)
                    .environmentObject(SidebarWidthModel(width: width))
            )
        }
        let hosting = NSHostingView(rootView: content.frame(width: size.width, height: size.height, alignment: .top)
            .background(Color(nsColor: appearance == .darkAqua ? .black : .white)))
        hosting.frame = NSRect(origin: .zero, size: size)
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

    /// Bounds (points) of pixels that differ between two renders, within the
    /// trailing 60pt and the top 150pt — the glyph slot, found by diffing a
    /// `?` row against a check row so the section chevron (identical in both)
    /// cancels out.
    private func diffBounds(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> (minY: CGFloat, maxY: CGFloat)? {
        let scale = CGFloat(a.pixelsWide) / width
        var minY = Int.max, maxY = -1
        for y in 0..<Int(150 * scale) {
            for x in Int((width - 60) * scale)..<a.pixelsWide {
                guard let p = a.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      let q = b.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if abs(p.redComponent - q.redComponent) + abs(p.greenComponent - q.greenComponent) > 0.3 {
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        return maxY >= 0 ? (CGFloat(minY) / scale, CGFloat(maxY + 1) / scale) : nil
    }

    private func topInkY(_ rep: NSBitmapImageRep) -> CGFloat? {
        let scale = CGFloat(rep.pixelsWide) / width
        guard let bg = rep.colorAt(x: rep.pixelsWide - 1, y: 0)?.usingColorSpace(.sRGB) else { return nil }
        for y in 0..<Int(150 * scale) {
            for x in Int((width - 60) * scale)..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if abs(c.redComponent - bg.redComponent) + abs(c.greenComponent - bg.greenComponent) > 0.2 { return CGFloat(y) / scale }
            }
        }
        return nil
    }

    func testFirstSessionGlyphAndSectionChevronSitAtTheSameYInExpandedAndRail() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let eNeeds = try XCTUnwrap(renderWholeSidebar(expanded: true, state: .needsAttention, appearance: appearance))
            let eIdle = try XCTUnwrap(renderWholeSidebar(expanded: true, state: .idle, appearance: appearance))
            let rNeeds = try XCTUnwrap(renderWholeSidebar(expanded: false, state: .needsAttention, appearance: appearance))
            let rIdle = try XCTUnwrap(renderWholeSidebar(expanded: false, state: .idle, appearance: appearance))
            let e = try XCTUnwrap(diffBounds(eNeeds, eIdle), "expanded glyph not found")
            let r = try XCTUnwrap(diffBounds(rNeeds, rIdle), "rail glyph not found")
            XCTAssertEqual(e.minY, r.minY, accuracy: 0.6, "first session glyph top (\(appearance))")
            XCTAssertEqual(e.maxY, r.maxY, accuracy: 0.6, "first session glyph bottom (\(appearance))")
            // Topmost ink in the trailing column is the section chevron.
            let ec = try XCTUnwrap(topInkY(eNeeds)), rc = try XCTUnwrap(topInkY(rNeeds))
            XCTAssertEqual(ec, rc, accuracy: 0.6, "section chevron top (\(appearance))")
        }
    }

    func testRailChevronColumnMatchesTheGlyphColumnOfTheExpandedHeader() throws {
        // Chevron right edge = the expanded header's, not centred in a 52pt column.
        let eNeeds = try XCTUnwrap(renderWholeSidebar(expanded: true, state: .needsAttention, appearance: .aqua))
        let rNeeds = try XCTUnwrap(renderWholeSidebar(expanded: false, state: .needsAttention, appearance: .aqua))
        func chevronRightX(_ rep: NSBitmapImageRep) -> CGFloat? {
            let scale = CGFloat(rep.pixelsWide) / width
            guard let bg = rep.colorAt(x: rep.pixelsWide - 1, y: 0)?.usingColorSpace(.sRGB) else { return nil }
            var maxX = -1
            // Only the header band: chevron top to bottom, above the first row.
            let headerTop = (WorkspaceStore(testingProjects: []).toolbarRowTopAnchorConstant * 2 + SidebarDialTuning.contentPaddingTop() + SidebarDialTuning.headerTopPadding()) * scale
            let headerBottom = headerTop + SidebarDialTuning.headerChevronSize() * scale
            for y in Int(headerTop)..<Int(headerBottom) {
                for x in 0..<rep.pixelsWide {
                    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    if abs(c.redComponent - bg.redComponent) + abs(c.greenComponent - bg.greenComponent) > 0.2, x > maxX { maxX = x }
                }
            }
            return maxX >= 0 ? CGFloat(maxX + 1) / scale : nil
        }
        // Expanded header also has "Active (1)" text on the left; only the right edge is compared.
        XCTAssertEqual(try XCTUnwrap(chevronRightX(eNeeds)), try XCTUnwrap(chevronRightX(rNeeds)), accuracy: 0.6)
    }

    // MARK: - Rail VoiceOver label

    func testRailRowLabelNamesTheSessionAndItsStatus() {
        XCTAssertEqual(
            RailSessionRow.accessibilityLabel(name: "Claude Code 6", projectName: "atlas-api", kind: SessionIndicatorState.needsAttention.statusGlyphKind, isActive: false),
            "Claude Code 6, in atlas-api, needs your input"
        )
        XCTAssertEqual(
            RailSessionRow.accessibilityLabel(name: "A", projectName: "p", kind: .done, isActive: true),
            "A, in p, idle, active"
        )
    }
}

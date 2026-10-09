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
    /// (the window margin plus the inner `contentPaddingLeading/Trailing`,
    /// with no gutter outside), so the inset measured is the one a user sees.
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
            .padding(.leading, SidebarDialTuning.windowMargin() + SidebarDialTuning.contentPaddingLeading())
            .padding(.trailing, SidebarDialTuning.windowMargin() + SidebarDialTuning.contentPaddingTrailing())
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
    /// `fromX` defaults to the trailing slot; the centered rail scans the full width.
    /// The expanded row's leading status slot, from the row's leading edge
    /// to just past the glyph column (option D), short of the title, which
    /// starts the label gap further on.
    private var leadingSlot: (from: CGFloat, to: CGFloat) {
        (0, SidebarDialTuning.windowMargin() + SidebarDialTuning.contentPaddingLeading()
            + SidebarDialTuning.rowLeadingPadding() + SidebarListRowChrome<EmptyView, EmptyView>.glyphSlotWidth + 4)
    }

    /// The glyph column's centre x in a row rendered by `render`.
    private var glyphColumnCentreX: CGFloat {
        SidebarDialTuning.windowMargin() + SidebarDialTuning.contentPaddingLeading()
            + SidebarDialTuning.rowLeadingPadding() + SidebarListRowChrome<EmptyView, EmptyView>.glyphSlotWidth / 2
    }

    private func inkBounds(_ rep: NSBitmapImageRep, fromX: CGFloat? = nil, toX: CGFloat? = nil) -> (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat)? {
        let scale = CGFloat(rep.pixelsWide) / width
        let start = Int((fromX ?? (width - 60)) * scale)
        let end = min(rep.pixelsWide, Int((toX ?? width) * scale))
        guard let bg = rep.colorAt(x: rep.pixelsWide - 1, y: 0)?.usingColorSpace(.sRGB) else { return nil }
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in 0..<rep.pixelsHigh {
            for x in start..<end {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let d = abs(c.redComponent - bg.redComponent) + abs(c.greenComponent - bg.greenComponent) + abs(c.blueComponent - bg.blueComponent)
                if d > 0.45 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
            }
        }
        guard maxX >= 0 else { return nil }
        return (CGFloat(minX) / scale, CGFloat(maxX + 1) / scale, CGFloat(minY) / scale, CGFloat(maxY + 1) / scale)
    }

    private func trailingPixels(_ rep: NSBitmapImageRep, fromX: CGFloat? = nil, toX: CGFloat? = nil) -> [UInt8] {
        let scale = CGFloat(rep.pixelsWide) / width
        let start = Int((fromX ?? (width - 60)) * scale)
        let end = min(rep.pixelsWide, Int((toX ?? width) * scale))
        var out: [UInt8] = []
        for y in 0..<rep.pixelsHigh {
            for x in start..<end {
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
            let slot = leadingSlot
            XCTAssertNotEqual(trailingPixels(needs, fromX: slot.from, toX: slot.to), trailingPixels(idle, fromX: slot.from, toX: slot.to), "? and check must differ (\(appearance))")
            XCTAssertNotEqual(trailingPixels(idle, fromX: slot.from, toX: slot.to), trailingPixels(error, fromX: slot.from, toX: slot.to), "check and x must differ (\(appearance))")
            XCTAssertNil(inkBounds(stopped, fromX: slot.from, toX: slot.to), "a stopped row draws nothing in the slot (\(appearance))")
            XCTAssertNotNil(inkBounds(needs, fromX: slot.from, toX: slot.to))
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
            XCTAssertNotEqual(trailingPixels(needs, fromX: 0), trailingPixels(idle, fromX: 0), "rail: ? and check must differ (\(appearance))")
            XCTAssertNotEqual(trailingPixels(idle, fromX: 0), trailingPixels(error, fromX: 0), "rail: check and x must differ (\(appearance))")
            XCTAssertNil(inkBounds(stopped, fromX: 0), "rail: a stopped row draws nothing (\(appearance))")
            XCTAssertNotNil(inkBounds(needs, fromX: 0))
        }
    }

    // MARK: - Expanded glyph leads, under the tile column; rail glyph is centered; same vertical position

    /// Option D: the expanded row's glyph sits in the leading slot, centred
    /// in the 30pt tile column (row leading padding in from the list
    /// margin), where the one-view headers draw their monogram tiles.
    func testExpandedGlyphCentresInTheLeadingTileColumnAndRailGlyphIsCentered() throws {
        let slot = leadingSlot
        for state in [SessionIndicatorState.needsAttention, .idle, .error] {
            let e = try XCTUnwrap(inkBounds(try XCTUnwrap(renderExpanded(state, appearance: .aqua)), fromX: slot.from, toX: slot.to))
            let r = try XCTUnwrap(inkBounds(try XCTUnwrap(renderRail(state, appearance: .aqua)), fromX: 0))
            XCTAssertEqual((e.minX + e.maxX) / 2, glyphColumnCentreX, accuracy: 1.0, "expanded glyph centre x, \(state)")
            XCTAssertLessThanOrEqual(e.maxX - e.minX, SidebarDialTuning.rowGhostSize() + 0.6, "expanded glyph fits its box, \(state)")
            // Rail: ink center x == rail center x.
            XCTAssertEqual((r.minX + r.maxX) / 2, width / 2, accuracy: 0.5, "rail glyph center x, \(state)")
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
    /// `?` row against a check row so everything else (identical in both)
    /// cancels out.
    private func diffBounds(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, fromX: CGFloat? = nil, toX: CGFloat? = nil) -> (minY: CGFloat, maxY: CGFloat)? {
        let scale = CGFloat(a.pixelsWide) / width
        var minY = Int.max, maxY = -1
        for y in 0..<Int(150 * scale) {
            for x in Int((fromX ?? (width - 60)) * scale)..<min(a.pixelsWide, Int((toX ?? width) * scale)) {
                guard let p = a.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      let q = b.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if abs(p.redComponent - q.redComponent) + abs(p.greenComponent - q.greenComponent) > 0.3 {
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        return maxY >= 0 ? (CGFloat(minY) / scale, CGFloat(maxY + 1) / scale) : nil
    }

    func testFirstSessionGlyphSitsAtTheSameYInExpandedAndRail() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let eNeeds = try XCTUnwrap(renderWholeSidebar(expanded: true, state: .needsAttention, appearance: appearance))
            let eIdle = try XCTUnwrap(renderWholeSidebar(expanded: true, state: .idle, appearance: appearance))
            let rNeeds = try XCTUnwrap(renderWholeSidebar(expanded: false, state: .needsAttention, appearance: appearance))
            let rIdle = try XCTUnwrap(renderWholeSidebar(expanded: false, state: .idle, appearance: appearance))
            let e = try XCTUnwrap(diffBounds(eNeeds, eIdle, fromX: leadingSlot.from, toX: leadingSlot.to), "expanded glyph not found")
            let r = try XCTUnwrap(diffBounds(rNeeds, rIdle, fromX: 0), "rail glyph not found")
            XCTAssertEqual(e.minY, r.minY, accuracy: 0.6, "first session glyph top (\(appearance))")
            XCTAssertEqual(e.maxY, r.maxY, accuracy: 0.6, "first session glyph bottom (\(appearance))")
        }
    }

    // MARK: - Tray capsules (layout B: Create capsule, gap, Toggle capsule)

    /// Renders the tray alone, bottom-aligned in a chrome-coloured column,
    /// with the plain (non-glass) capsules, since `cacheDisplay` can't
    /// capture glass. Expected geometry below reads the same live dial
    /// accessors the tray does, so it holds at any saved dial value.
    /// `gutter`: the space outside the column's trailing edge, injected the
    /// way `SidebarHostRoot` does (`WorkspaceLayout.sidebarTrailingGutter`).
    /// The rail's width (`sidebarRailWidth`) is the canvas width on the rail.
    private func renderTray(vertical: Bool, size: CGSize, gutter: CGFloat = 0) throws -> (NSBitmapImageRep, CGFloat) {
        let chrome = try XCTUnwrap(WorkspaceLayout.chromeBackgroundLight.usingColorSpace(.sRGB))
        let hosting = NSHostingView(rootView: SidebarTray(
            isVertical: vertical,
            toggleLabel: vertical ? "Expand Sidebar" : "Collapse Sidebar",
            forceOpaque: true
        )
            .environment(\.sidebarTrailingGutter, gutter)
            .environment(\.sidebarRailWidth, vertical ? size.width : WorkspaceLayout.sidebarRailWidth)
            .environmentObject(SessionCoordinator())
            .frame(width: size.width, height: size.height, alignment: .bottomLeading)
            .background(Color(nsColor: chrome)))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return (rep, CGFloat(rep.pixelsWide) / size.width)
    }

    /// Capsule spans (in points) along one pixel line. A pixel is capsule if
    /// it is lighter than the chrome (the near-white fill) or clearly darker
    /// (icon ink, including the toggle glyph's divider, which this SDK draws
    /// at about -0.43); the shadow only darkens slightly, so it never counts.
    /// Gaps of up to 3px (anti-aliased icon edges) are bridged.
    private func capsuleSpans(_ rep: NSBitmapImageRep, scale: CGFloat, alongX: Bool, at fixed: CGFloat) throws -> [ClosedRange<CGFloat>] {
        let chrome = try XCTUnwrap(WorkspaceLayout.chromeBackgroundLight.usingColorSpace(.sRGB))
        let chromeSum = chrome.redComponent + chrome.greenComponent + chrome.blueComponent
        let count = alongX ? rep.pixelsWide : rep.pixelsHigh
        let fixedPx = Int(fixed * scale)
        var runs: [(Int, Int)] = []
        for i in 0..<count {
            guard let c = (alongX ? rep.colorAt(x: i, y: fixedPx) : rep.colorAt(x: fixedPx, y: i))?.usingColorSpace(.sRGB) else { continue }
            let lift = c.redComponent + c.greenComponent + c.blueComponent - chromeSum
            guard lift > 0.06 || lift < -0.3 else { continue }
            if let last = runs.last, i - last.1 <= 4 {
                runs[runs.count - 1].1 = i
            } else {
                runs.append((i, i))
            }
        }
        return runs.map { CGFloat($0.0) / scale...CGFloat($0.1 + 1) / scale }
    }

    // MARK: - Rail A2 geometry

    /// The stock traffic-light cluster of a titled window, in window
    /// coordinates, and the collapsed-rail width and centre derived from it:
    /// nothing hard-coded, so it holds on any macOS titlebar layout.
    private func realRailGeometry() throws -> (railWidth: CGFloat, clusterCentre: CGFloat) {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        let close = try XCTUnwrap(window.standardWindowButton(.closeButton))
        let zoom = try XCTUnwrap(window.standardWindowButton(.zoomButton))
        let closeMinX = close.convert(close.bounds, to: nil).minX
        let zoomMaxX = zoom.convert(zoom.bounds, to: nil).maxX
        let railWidth = WorkspaceLayout.collapsedRailWidth(zoomButtonMaxX: zoomMaxX, leadingInset: closeMinX)
        return (railWidth, (closeMinX + zoomMaxX) / 2)
    }

    /// The rail tray's geometry as pure values (option D, 2026-10-09): square
    /// pills of the pill-size dial, capped at the rail less a margin each
    /// side; the stacked Create buttons abutting, `icon + gap` tall, with
    /// the capsule padding above and below; one margin between the pills and
    /// below them. Checked at the real rail width and at off-default dials.
    func testRailTrayGeometryIsSquareCellsStackedWithTheCapsulePadding() throws {
        let (railWidth, _) = try realRailGeometry()
        let live = (SidebarDialTuning.windowMargin(), SidebarDialTuning.trayInnerPadding(),
                    SidebarDialTuning.trayVerticalIconSize(), SidebarDialTuning.railTrayIconGap(),
                    SidebarDialTuning.railTrayPillSize())
        for (margin, padding, icon, gap, pill) in [live, (11, 5, 18, 12, 44), (4, 12, 20, 0, 200), (8, 8, 16, 20, 40)] as [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] {
            let g = RailTrayGeometry(railWidth: railWidth, margin: margin, padding: padding, iconSize: icon, iconGap: gap, pillSize: pill)
            let tag = "margin \(margin), padding \(padding), icon \(icon), gap \(gap), pill \(pill)"
            XCTAssertEqual(g.cell, min(pill, railWidth - 2 * margin), accuracy: 0.001, tag)
            XCTAssertEqual(g.buttonSize, g.cell, accuracy: 0.001, "buttons fill the pill across the rail (\(tag))")
            XCTAssertEqual(g.pillHeight(items: 1), g.cell, accuracy: 0.001, "toggle pill is square (\(tag))")
            XCTAssertEqual(g.stackedPadding, padding, accuracy: 0.001, tag)
            XCTAssertEqual(g.pillHeight(items: 2), padding + 2 * (icon + gap) + padding, accuracy: 0.001, "create pill height (\(tag))")
            XCTAssertEqual(g.stackedButtonHeight + g.itemGap, icon + gap, accuracy: 0.001, "icon centre spacing (\(tag))")
            XCTAssertEqual(g.groupGap, margin, tag)
            XCTAssertEqual(g.bottomMargin, margin, tag)
            XCTAssertEqual(g.trayHeight(groupItemCounts: [2, 1]), g.pillHeight(items: 2) + g.cell + 2 * margin, accuracy: 0.001, tag)
        }
        // Shipped (option D `emGcV`): 48pt square pills and buttons, Create
        // 2 + 48 + 48 + 2 = 100 tall, the tray 100 + 8 + 48 + 8 = 164.
        let shipped = RailTrayGeometry(railWidth: 98, margin: WorkspaceLayout.terminalInset, padding: TrayGlassStyle.innerPadding)
        XCTAssertEqual(shipped.cell, 48)
        XCTAssertEqual(shipped.stackedButtonHeight, 48, "the stacked buttons are square")
        XCTAssertEqual(shipped.pillHeight(items: 2), 100)
        XCTAssertEqual(shipped.trayHeight(groupItemCounts: [2, 1]), 164)
        // What the rail reserves is that tray, at the live dials.
        XCTAssertEqual(
            SidebarTray.reservedHeight(isVertical: true, railWidth: railWidth),
            RailTrayGeometry.current(railWidth: railWidth).trayHeight(groupItemCounts: SidebarTray.groupItemCounts()),
            accuracy: 0.001
        )
    }

    /// Tray hover, Finder's toolbar rule: the chip is the button's cell
    /// inset by the "Hover inset" dial on every side, its corner concentric
    /// with the pill's: pill radius less the chip's distance from the pill
    /// edge. A sole button is its capsule, so that distance is the inset; a
    /// button in a grouped pill sits the capsule padding inside the pill, so
    /// it is padding + inset. Checked for an expanded (square) cell and a
    /// rail stacked (short) cell, each grouped and sole. Pixels: the band
    /// between the cell edge and the chip stays background on all four
    /// sides, the chip's inside is tinted, and a point 2.4pt in along the
    /// chip's corner diagonal is tinted for the grouped chip's small corner
    /// (r 3, curve within ~1pt of the corner) but background for the sole
    /// chip's large one (r 13, ~3.8pt), so the corner rendered is the one
    /// the rule picks. Off-default dials (margin 0 → pill radius 16, inset 3,
    /// padding 10) so the dials, not constants, drive it and the two radii
    /// sit far apart.
    func testTrayHoverChipIsTheCellInsetByTheDialWithAConcentricCorner() throws {
        let configure: (UserDefaults) -> Void = {
            $0.set(3.0, forKey: SidebarDialTuning.trayHoverInsetKey)
            $0.set(0.0, forKey: SidebarDialTuning.windowMarginKey)
            $0.set(10.0, forKey: SidebarDialTuning.trayInnerPaddingKey)
        }
        let cases: [(Bool, CGSize, Bool)] = [
            (false, CGSize(width: 48, height: 48), false),
            (false, CGSize(width: 48, height: 48), true),
            (true, CGSize(width: 48, height: 40), false),
            (true, CGSize(width: 48, height: 48), true),
        ]
        for (vertical, cell, sole) in cases {
            let tag = (vertical ? "rail cell" : "expanded cell") + (sole ? ", sole" : ", grouped")
            try withDials(configure) {
                let inset = SidebarDialTuning.trayHoverInset()
                let padding = SidebarDialTuning.trayInnerPadding()
                let pillRadius = TrayGlassStyle.pillCornerRadius()
                XCTAssertEqual(inset, 3, tag)
                XCTAssertEqual(padding, 10, tag)
                XCTAssertEqual(pillRadius, 16, tag)
                let chip = TrayGlassStyle.hoverChip(cell: CGRect(origin: .zero, size: cell), soleInCapsule: sole)
                XCTAssertEqual(chip.frame, CGRect(origin: .zero, size: cell).insetBy(dx: inset, dy: inset), tag)
                XCTAssertEqual(chip.cornerRadius, sole ? 13 : 3, accuracy: 0.001, tag)
                XCTAssertEqual(chip.cornerRadius, pillRadius - (sole ? 0 : padding) - inset, accuracy: 0.001, tag)

                let hosting = NSHostingView(rootView: TrayIconButton(
                    systemName: "plus", label: "New Session", isVertical: vertical,
                    cellSize: cell.width, cellHeight: vertical ? cell.height : nil,
                    fillsCapsule: sole, forceHover: true, action: {}
                )
                    .frame(width: cell.width, height: cell.height)
                    .background(Color.white))
                hosting.frame = NSRect(origin: .zero, size: cell)
                let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: .aqua)
                window.contentView = hosting
                window.orderFrontRegardless()
                defer { window.orderOut(nil) }
                hosting.layoutSubtreeIfNeeded()
                let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                let scale = CGFloat(rep.pixelsWide) / cell.width
                func sum(_ x: CGFloat, _ y: CGFloat) throws -> CGFloat {
                    let c = try XCTUnwrap(rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB))
                    return c.redComponent + c.greenComponent + c.blueComponent
                }
                let midX = cell.width / 2, midY = cell.height / 2
                let band = inset / 2, inside = inset + 1.5
                // (point in the band, point just inside the chip), per side.
                let sides: [(String, (CGFloat, CGFloat), (CGFloat, CGFloat))] = [
                    ("top", (midX, band), (midX, inside)),
                    ("bottom", (midX, cell.height - band), (midX, cell.height - inside)),
                    ("leading", (band, midY), (inside, midY)),
                    ("trailing", (cell.width - band, midY), (cell.width - inside, midY)),
                ]
                for (side, out, inn) in sides {
                    XCTAssertGreaterThan(try sum(out.0, out.1), 2.95, "\(side) band outside the chip is untinted (\(tag))")
                    XCTAssertLessThan(try sum(inn.0, inn.1), 2.85, "\(side) inside the chip is tinted (\(tag))")
                }
                // 2.4pt in along the chip's top-leading corner diagonal:
                // inside a r3 corner, outside a r13 one.
                let probe = try sum(chip.frame.minX + 2.4, chip.frame.minY + 2.4)
                if sole {
                    XCTAssertGreaterThan(probe, 2.95, "sole chip's corner is the large concentric radius (\(tag))")
                } else {
                    XCTAssertLessThan(probe, 2.85, "grouped chip's corner is the small concentric radius (\(tag))")
                }
                // Just inside the chip frame's corner, outside either rounded corner.
                XCTAssertGreaterThan(try sum(chip.frame.minX + 0.25, chip.frame.minY + 0.25), 2.95, "chip corner is rounded (\(tag))")
            }
        }
        // Capsule style: the pill is a capsule, and so is the chip, grouped
        // or sole, at the default dials.
        for sole in [false, true] {
            let chip = withDials {
                TrayGlassStyle.hoverChip(
                    cell: CGRect(x: 0, y: 0, width: 48, height: 48),
                    soleInCapsule: sole,
                    pillCornerRadius: TrayGlassStyle.capsuleCornerRadius
                )
            }
            XCTAssertGreaterThanOrEqual(chip.cornerRadius, min(chip.frame.width, chip.frame.height) / 2, "capsule chip (sole: \(sole))")
        }
    }

    /// Vertical runs of icon ink (darker than the chrome by more than the
    /// shadow ever is) anywhere in the columns `xs`, in points, bridging
    /// anti-aliasing gaps of up to 3px.
    private func inkRows(_ rep: NSBitmapImageRep, scale: CGFloat, xs: ClosedRange<CGFloat>, ys: ClosedRange<CGFloat>) throws -> [ClosedRange<CGFloat>] {
        let chrome = try XCTUnwrap(WorkspaceLayout.chromeBackgroundLight.usingColorSpace(.sRGB))
        let chromeSum = chrome.redComponent + chrome.greenComponent + chrome.blueComponent
        var runs: [(Int, Int)] = []
        for y in Int(ys.lowerBound * scale)..<Int(ys.upperBound * scale) {
            let hasInk = (Int(xs.lowerBound * scale)..<Int(xs.upperBound * scale)).contains { x in
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
                return c.redComponent + c.greenComponent + c.blueComponent - chromeSum < -0.3
            }
            guard hasInk else { continue }
            if let last = runs.last, y - last.1 <= 4 {
                runs[runs.count - 1].1 = y
            } else {
                runs.append((y, y))
            }
        }
        return runs.map { CGFloat($0.0) / scale...CGFloat($0.1 + 1) / scale }
    }

    /// The rendered rail tray (option D): square pills centred on the
    /// traffic-light cluster, one margin between them and below them, the
    /// Create pill's icons each centred in its square button.
    func testRailTrayRendersSquarePillsCentredOnTheRail() throws {
        let (railWidth, clusterCentre) = try realRailGeometry()
        XCTAssertEqual(railWidth / 2, clusterCentre, accuracy: 0.01, "rail centre is the cluster centre")
        let size = CGSize(width: railWidth, height: 400)
        let g = RailTrayGeometry.current(railWidth: railWidth)
        let margin = SidebarDialTuning.windowMargin()
        let createHeight = g.pillHeight(items: 2)

        let (rep, scale) = try renderTray(vertical: true, size: size, gutter: WorkspaceLayout.sidebarTrailingGutter(for: .collapsed))
        let toggleBottom = size.height - margin
        let toggleMidY = toggleBottom - g.cell / 2
        let createMidY = toggleBottom - g.cell - margin - createHeight / 2

        for (name, midY) in [("create", createMidY), ("toggle", toggleMidY)] {
            let spans = try capsuleSpans(rep, scale: scale, alongX: true, at: midY)
            XCTAssertEqual(spans.count, 1, "\(name) capsule: one span across the rail, got \(spans)")
            let span = try XCTUnwrap(spans.first)
            XCTAssertEqual(span.upperBound - span.lowerBound, g.cell, accuracy: 1.0, "\(name) capsule width")
            XCTAssertEqual((span.lowerBound + span.upperBound) / 2, clusterCentre, accuracy: 0.5, "\(name) capsule centred on the cluster")
        }

        let spans = try capsuleSpans(rep, scale: scale, alongX: false, at: railWidth / 2)
        XCTAssertEqual(spans.count, 2, "two capsules stacked, got \(spans)")
        guard spans.count == 2 else { return }
        let create = spans[0], toggle = spans[1]
        XCTAssertEqual(create.upperBound - create.lowerBound, createHeight, accuracy: 1.0, "create capsule height")
        XCTAssertEqual(toggle.upperBound - toggle.lowerBound, g.cell, accuracy: 1.0, "toggle capsule is square")
        XCTAssertEqual(toggle.lowerBound - create.upperBound, margin, accuracy: 1.0, "gap between the capsules = the window margin")
        XCTAssertEqual(size.height - toggle.upperBound, margin, accuracy: 1.0, "bottom margin = the window margin")

        // Each Create icon sits at its button's centre: the capsule padding
        // plus half a button from the pill's top (and bottom).
        let xs = (railWidth / 2 - g.cell / 2 + 2)...(railWidth / 2 + g.cell / 2 - 2)
        let createIcons = try inkRows(rep, scale: scale, xs: xs, ys: (create.lowerBound + 2)...(create.upperBound - 2))
        XCTAssertEqual(createIcons.count, 2, "two icons in the create capsule, got \(createIcons)")
        guard createIcons.count == 2 else { return }
        let plusMid = (createIcons[0].lowerBound + createIcons[0].upperBound) / 2
        let folderMid = (createIcons[1].lowerBound + createIcons[1].upperBound) / 2
        XCTAssertEqual(plusMid - create.lowerBound, g.stackedPadding + g.stackedButtonHeight / 2, accuracy: 1.5, "+ icon centred in its button")
        XCTAssertEqual(create.upperBound - folderMid, g.stackedPadding + g.stackedButtonHeight / 2, accuracy: 2.0, "folder icon centred in its button")
        XCTAssertEqual(folderMid - plusMid, g.iconSize + g.iconGap, accuracy: 2.0, "icon centres one button apart")
        let toggleIcon = try inkRows(rep, scale: scale, xs: xs, ys: (toggle.lowerBound + 2)...(toggle.upperBound - 2))
        XCTAssertEqual(toggleIcon.count, 1, "one icon in the toggle capsule, got \(toggleIcon)")
        if let icon = toggleIcon.first {
            XCTAssertEqual((icon.lowerBound + icon.upperBound) / 2 - toggle.lowerBound, g.cell / 2, accuracy: 1.5, "toggle icon centred")
        }
    }

    /// The rail column (`SidebarRailView.columnPadding`) with one row, under
    /// the rail's real trailing gutter, on white. Returns the row glyph's
    /// ink centre x in points.
    private func railRowGlyphCenterX(railWidth: CGFloat, gutter: CGFloat) throws -> CGFloat {
        let column = VStack(spacing: 0) {
            RailSessionRow(sessionId: UUID(), name: "Claude Code 6", projectName: "atlas-api", indicatorState: .needsAttention, isActive: false, onTap: {})
        }
            .modifier(SidebarRailView.columnPadding)
            .frame(width: railWidth, height: 100, alignment: .top)
            .environment(\.sidebarTrailingGutter, gutter)
            .environmentObject(SessionCoordinator())
            .background(Color.white)
        let hosting = NSHostingView(rootView: column)
        hosting.frame = NSRect(x: 0, y: 0, width: railWidth, height: 100)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / railWidth
        var minX = Int.max, maxX = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if c.redComponent + c.greenComponent + c.blueComponent < 1.5 { minX = min(minX, x); maxX = max(maxX, x) }
            }
        }
        XCTAssertGreaterThanOrEqual(maxX, 0, "no glyph ink found in the rail row")
        return (CGFloat(minX) + CGFloat(maxX + 1)) / 2 / scale
    }

    /// The rail's row glyphs, its tray pill and the rail itself share one
    /// centre, the traffic-light cluster's, with no gutter outside the rail,
    /// and whatever the leading/trailing content-padding dials hold.
    func testRailRowGlyphAndTrayPillShareTheRailCentre() throws {
        // Rail A2: the rail adds no trailing gutter, and everything centres
        // on the traffic-light cluster, derived from real button frames.
        let (railWidth, clusterCentre) = try realRailGeometry()
        let gutter = WorkspaceLayout.sidebarTrailingGutter(for: .collapsed)
        XCTAssertEqual(gutter, 0, "the rail has no trailing gutter")

        let glyphX = try railRowGlyphCenterX(railWidth: railWidth, gutter: gutter)
        let (rep, scale) = try renderTray(vertical: true, size: CGSize(width: railWidth, height: 400), gutter: gutter)
        let toggleMidY = 400 - SidebarTray.bottomPadding(isVertical: true)
            - RailTrayGeometry.current(railWidth: railWidth).cell / 2
        let pill = try XCTUnwrap(try capsuleSpans(rep, scale: scale, alongX: true, at: toggleMidY).first)
        let pillX = (pill.lowerBound + pill.upperBound) / 2

        XCTAssertEqual(glyphX, clusterCentre, accuracy: 0.5, "rail row glyph centre x vs cluster centre")
        XCTAssertEqual(pillX, clusterCentre, accuracy: 0.5, "rail tray pill centre x vs cluster centre")
        XCTAssertEqual(glyphX, pillX, accuracy: 0.5, "rail row glyph and tray pill share a centre")

        // Asymmetric content-padding dials (Sean's Dev holds leading 8,
        // trailing unset) must not move the rail's centre.
        try withDials({ $0.set(8.0, forKey: SidebarDialTuning.contentPaddingLeadingKey) }) {
            XCTAssertEqual(try railRowGlyphCenterX(railWidth: railWidth, gutter: gutter), clusterCentre, accuracy: 0.5, "rail glyph centre x with leading padding 8")
        }
    }

    /// Renders the expanded tray under one "Tray width" mode and returns the
    /// capsule spans on the shared baseline. The dial is set only in a
    /// private suite bound around the render (`withDials`).
    private func expandedTraySpans(mode: TrayGlassStyle.TrayWidth, columnWidth: CGFloat, height: CGFloat, gutter: CGFloat = 0) throws -> (rep: NSBitmapImageRep, scale: CGFloat, spans: [ClosedRange<CGFloat>], bottom: CGFloat) {
        try withDials({ $0.set(mode.rawValue, forKey: SidebarDialTuning.trayWidthKey) }) {
            XCTAssertEqual(SidebarDialTuning.trayWidth(), mode)
            let size = CGSize(width: columnWidth, height: 120)
            let (rep, scale) = try renderTray(vertical: false, size: size, gutter: gutter)
            let bottom = size.height - SidebarTray.bottomPadding(isVertical: false)
            let spans = try capsuleSpans(rep, scale: scale, alongX: true, at: bottom - height / 2)
            return (rep, scale, spans, bottom)
        }
    }

    private func assertSharedBaseline(_ spans: [ClosedRange<CGFloat>], rep: NSBitmapImageRep, scale: CGFloat, height: CGFloat, bottom: CGFloat) throws {
        for (name, span) in [("create", spans[0]), ("toggle", spans[1])] {
            let column = try capsuleSpans(rep, scale: scale, alongX: false, at: (span.lowerBound + span.upperBound) / 2)
            let capsule = try XCTUnwrap(column.last, "\(name) capsule not found vertically")
            XCTAssertEqual(capsule.upperBound - capsule.lowerBound, height, accuracy: 1.5, "\(name) capsule height")
            XCTAssertEqual(capsule.upperBound, bottom, accuracy: 1.0, "\(name) capsule bottom")
        }
    }

    func testExpandedTrayFillStretchesCreateToTheGroupGapBeforeToggle() throws {
        let columnWidth: CGFloat = 300
        let button = SidebarDialTuning.trayHorizontalButtonSize()
        let gap = SidebarDialTuning.trayGroupGap()
        let margin = SidebarDialTuning.windowMargin()
        // The gutter the pinned app really has outside the column: the card's
        // leading inset. The column is `columnWidth` wide; the card starts
        // `gutter` past its edge.
        let gutter = WorkspaceLayout.sidebarTrailingGutter(for: .pinned)
        // Option D: no capsule padding across the bar; a one-button capsule
        // is its button.
        let toggleWidth = button
        let height = button

        let (rep, scale, spans, bottom) = try expandedTraySpans(mode: .fill, columnWidth: columnWidth, height: height, gutter: gutter)
        XCTAssertEqual(spans.count, 2, "one span per capsule, got \(spans)")
        guard spans.count == 2 else { return }
        XCTAssertEqual(spans[0].lowerBound, margin, accuracy: 1.0, "create capsule starts at the leading margin")
        XCTAssertEqual(spans[0].upperBound + gap, spans[1].lowerBound, accuracy: 1.0, "create's right edge plus the group gap meets toggle's left edge")
        XCTAssertEqual(spans[1].upperBound - spans[1].lowerBound, toggleWidth, accuracy: 1.0, "toggle capsule stays button size")
        // Visible trailing margin = the column's own trailing padding plus the
        // gutter outside it, up to the card: the window margin, like the leading side.
        XCTAssertEqual(columnWidth + gutter - spans[1].upperBound, margin, accuracy: 1.0, "toggle's visible trailing margin to the card is the window margin")
        XCTAssertEqual(bottom, 120 - margin, accuracy: 0.01, "tray bottom margin is the window margin")
        try assertSharedBaseline(spans, rep: rep, scale: scale, height: height, bottom: bottom)
    }

    func testExpandedTrayHugCapsulesHugTheirIconsAndSitLeadingSideBySide() throws {
        let columnWidth: CGFloat = 300
        let button = SidebarDialTuning.trayHorizontalButtonSize()
        let padding = SidebarDialTuning.trayInnerPadding()
        let gap = SidebarDialTuning.trayGroupGap()
        let createWidth = 2 * button + TrayGlassStyle.horizontalItemGap + 2 * padding
        let toggleWidth = button
        let height = button

        let (rep, scale, spans, bottom) = try expandedTraySpans(mode: .hug, columnWidth: columnWidth, height: height)
        XCTAssertEqual(spans.count, 2, "two capsules side by side, got \(spans)")
        guard spans.count == 2 else { return }
        XCTAssertEqual(spans[0].lowerBound, SidebarDialTuning.windowMargin(), accuracy: 1.0, "create capsule starts at the window margin")
        XCTAssertEqual(spans[0].upperBound - spans[0].lowerBound, createWidth, accuracy: 1.0, "create capsule width")
        XCTAssertEqual(spans[1].lowerBound - spans[0].upperBound, gap, accuracy: 1.0, "gap between the capsules")
        XCTAssertEqual(spans[1].upperBound - spans[1].lowerBound, toggleWidth, accuracy: 1.0, "toggle capsule width")
        try assertSharedBaseline(spans, rep: rep, scale: scale, height: height, bottom: bottom)
    }

    /// Option D (`WhwIC`): "split" hugs both capsules, Create at the leading
    /// margin (2 square buttons plus the capsule padding along the bar) and
    /// Toggle at the trailing one, both 48pt tall on one baseline.
    func testExpandedTraySplitPutsCreateLeadingAndToggleTrailing() throws {
        let columnWidth: CGFloat = 256
        let button = SidebarDialTuning.trayHorizontalButtonSize()
        let padding = SidebarDialTuning.trayInnerPadding()
        let margin = SidebarDialTuning.windowMargin()
        let gutter = WorkspaceLayout.sidebarTrailingGutter(for: .pinned)
        let createWidth = 2 * button + TrayGlassStyle.horizontalItemGap + 2 * padding

        let (rep, scale, spans, bottom) = try expandedTraySpans(mode: .split, columnWidth: columnWidth, height: button, gutter: gutter)
        XCTAssertEqual(spans.count, 2, "two capsules, got \(spans)")
        guard spans.count == 2 else { return }
        XCTAssertEqual(spans[0].lowerBound, margin, accuracy: 1.0, "create capsule starts at the window margin")
        XCTAssertEqual(spans[0].upperBound - spans[0].lowerBound, createWidth, accuracy: 1.0, "create capsule hugs its buttons")
        XCTAssertEqual(spans[1].upperBound - spans[1].lowerBound, button, accuracy: 1.0, "toggle capsule is its button")
        XCTAssertEqual(columnWidth + gutter - spans[1].upperBound, margin, accuracy: 1.0, "toggle sits the window margin from the card")
        try assertSharedBaseline(spans, rep: rep, scale: scale, height: button, bottom: bottom)
        // Shipped values: 100 x 48 and 48 x 48.
        XCTAssertEqual(TrayGlassStyle.horizontalButtonSize, 48)
        XCTAssertEqual(2 * TrayGlassStyle.horizontalButtonSize + TrayGlassStyle.horizontalItemGap + 2 * TrayGlassStyle.innerPadding, 100)
        XCTAssertEqual(TrayGlassStyle.trayWidth, .split)
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

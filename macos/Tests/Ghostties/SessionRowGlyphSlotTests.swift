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
    private func inkBounds(_ rep: NSBitmapImageRep, fromX: CGFloat? = nil) -> (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat)? {
        let scale = CGFloat(rep.pixelsWide) / width
        let start = Int((fromX ?? (width - 60)) * scale)
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

    private func trailingPixels(_ rep: NSBitmapImageRep, fromX: CGFloat? = nil) -> [UInt8] {
        let scale = CGFloat(rep.pixelsWide) / width
        let start = Int((fromX ?? (width - 60)) * scale)
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
            XCTAssertNotEqual(trailingPixels(needs, fromX: 0), trailingPixels(idle, fromX: 0), "rail: ? and check must differ (\(appearance))")
            XCTAssertNotEqual(trailingPixels(idle, fromX: 0), trailingPixels(error, fromX: 0), "rail: check and x must differ (\(appearance))")
            XCTAssertNil(inkBounds(stopped, fromX: 0), "rail: a stopped row draws nothing (\(appearance))")
            XCTAssertNotNil(inkBounds(needs, fromX: 0))
        }
    }

    // MARK: - Expanded glyph stays trailing; rail glyph is centered; same vertical position

    func testExpandedGlyphSitsAtTheTrailingInsetAndRailGlyphIsCentered() throws {
        for state in [SessionIndicatorState.needsAttention, .idle, .error] {
            let e = try XCTUnwrap(inkBounds(try XCTUnwrap(renderExpanded(state, appearance: .aqua))))
            let r = try XCTUnwrap(inkBounds(try XCTUnwrap(renderRail(state, appearance: .aqua)), fromX: 0))
            // Expanded: the ink stays inside the glyph's box, which ends at the list
            // margin + row trailing padding (measured: ink sits up to ~5pt inside it).
            let boxMaxX = width - SidebarDialTuning.windowMargin() - SidebarDialTuning.contentPaddingTrailing() - SidebarDialTuning.rowTrailingPadding()
            let boxMinX = boxMaxX - SidebarDialTuning.rowGhostSize()
            XCTAssertLessThanOrEqual(e.maxX, boxMaxX + 0.6, "expanded glyph ink right edge, \(state)")
            XCTAssertGreaterThanOrEqual(e.minX, boxMinX - 0.6, "expanded glyph ink left edge, \(state)")
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
    private func diffBounds(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, fromX: CGFloat? = nil) -> (minY: CGFloat, maxY: CGFloat)? {
        let scale = CGFloat(a.pixelsWide) / width
        var minY = Int.max, maxY = -1
        for y in 0..<Int(150 * scale) {
            for x in Int((fromX ?? (width - 60)) * scale)..<a.pixelsWide {
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
            let e = try XCTUnwrap(diffBounds(eNeeds, eIdle), "expanded glyph not found")
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
    private func renderTray(vertical: Bool, size: CGSize, gutter: CGFloat = 0) throws -> (NSBitmapImageRep, CGFloat) {
        let chrome = try XCTUnwrap(WorkspaceLayout.chromeBackgroundLight.usingColorSpace(.sRGB))
        let hosting = NSHostingView(rootView: SidebarTray(
            isVertical: vertical,
            toggleLabel: vertical ? "Expand Sidebar" : "Collapse Sidebar",
            forceOpaque: true
        )
            .environment(\.sidebarTrailingGutter, gutter)
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

    func testRailTrayCapsulesHugTheirIconsAndStackCenteredOnTheRail() throws {
        let railWidth: CGFloat = 98
        let size = CGSize(width: railWidth, height: 260)
        let button = SidebarDialTuning.trayVerticalButtonSize()
        let padding = SidebarDialTuning.trayInnerPadding()
        let gap = SidebarDialTuning.trayGroupGap()
        let capsuleWidth = button + 2 * padding
        let createHeight = 2 * button + TrayGlassStyle.verticalItemGap + 2 * padding
        let toggleHeight = button + 2 * padding

        // Hugging: the tray's own ideal width is one capsule (the rail pads
        // no sides, so the pill centres on the full rail).
        let alone = NSHostingView(rootView: SidebarTray(isVertical: true, toggleLabel: "Expand Sidebar").environmentObject(SessionCoordinator()))
        XCTAssertEqual(alone.fittingSize.width, capsuleWidth, accuracy: 0.5, "tray width = icon + 2 x padding")

        // The gutter the rail really has outside its column: the card's inset.
        let (rep, scale) = try renderTray(vertical: true, size: size, gutter: WorkspaceLayout.sidebarTrailingGutter(for: .collapsed))
        let toggleBottom = size.height - SidebarTray.bottomPadding(isVertical: true)
        let toggleMidY = toggleBottom - toggleHeight / 2
        let createMidY = toggleBottom - toggleHeight - gap - createHeight / 2

        // Each capsule: its width, centred on the rail.
        for (name, midY) in [("create", createMidY), ("toggle", toggleMidY)] {
            let spans = try capsuleSpans(rep, scale: scale, alongX: true, at: midY)
            XCTAssertEqual(spans.count, 1, "\(name) capsule: one span across the rail, got \(spans)")
            let span = try XCTUnwrap(spans.first)
            XCTAssertEqual(span.upperBound - span.lowerBound, capsuleWidth, accuracy: 1.0, "\(name) capsule width")
            XCTAssertEqual((span.lowerBound + span.upperBound) / 2, railWidth / 2, accuracy: 0.5, "\(name) capsule centred on the rail")
        }

        // Down the rail's centre: Create above Toggle, their heights, the gap.
        let spans = try capsuleSpans(rep, scale: scale, alongX: false, at: railWidth / 2)
        XCTAssertEqual(spans.count, 2, "two capsules stacked, got \(spans)")
        guard spans.count == 2 else { return }
        XCTAssertEqual(spans[0].upperBound - spans[0].lowerBound, createHeight, accuracy: 1.0, "create capsule height")
        XCTAssertEqual(spans[1].upperBound - spans[1].lowerBound, toggleHeight, accuracy: 1.0, "toggle capsule height")
        XCTAssertEqual(spans[1].lowerBound - spans[0].upperBound, gap, accuracy: 1.0, "gap between the capsules")
        XCTAssertEqual(spans[1].upperBound, toggleBottom, accuracy: 1.0, "toggle capsule sits on the bottom padding")
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
    /// centre, under the rail's real gutter (the window margin outside it)
    /// and whatever the leading/trailing content-padding dials hold.
    func testRailRowGlyphAndTrayPillShareTheRailCentre() throws {
        let railWidth: CGFloat = 98
        let gutter = WorkspaceLayout.sidebarTrailingGutter(for: .collapsed)
        XCTAssertGreaterThan(gutter, 0, "the rail has a gutter: the card's inset")

        let glyphX = try railRowGlyphCenterX(railWidth: railWidth, gutter: gutter)
        let (rep, scale) = try renderTray(vertical: true, size: CGSize(width: railWidth, height: 260), gutter: gutter)
        let toggleMidY = 260 - SidebarTray.bottomPadding(isVertical: true)
            - (SidebarDialTuning.trayVerticalButtonSize() + 2 * SidebarDialTuning.trayInnerPadding()) / 2
        let pill = try XCTUnwrap(try capsuleSpans(rep, scale: scale, alongX: true, at: toggleMidY).first)
        let pillX = (pill.lowerBound + pill.upperBound) / 2

        XCTAssertEqual(glyphX, railWidth / 2, accuracy: 0.5, "rail row glyph centre x")
        XCTAssertEqual(pillX, railWidth / 2, accuracy: 0.5, "rail tray pill centre x")
        XCTAssertEqual(glyphX, pillX, accuracy: 0.5, "rail row glyph and tray pill share a centre")

        // Asymmetric content-padding dials (Sean's Dev holds leading 8,
        // trailing unset) must not move the rail's centre.
        let store = SidebarDialTuning.store
        store.set(8.0, forKey: SidebarDialTuning.contentPaddingLeadingKey)
        defer { store.removeObject(forKey: SidebarDialTuning.contentPaddingLeadingKey) }
        XCTAssertEqual(try railRowGlyphCenterX(railWidth: railWidth, gutter: gutter), railWidth / 2, accuracy: 0.5, "rail glyph centre x with leading padding 8")
    }

    /// Renders the expanded tray under one "Tray width" mode and returns the
    /// capsule spans on the shared baseline. The dial is set only through the
    /// isolated `SidebarDialTuning.store`, and cleared afterward.
    private func expandedTraySpans(mode: TrayGlassStyle.TrayWidth, columnWidth: CGFloat, height: CGFloat, gutter: CGFloat = 0) throws -> (rep: NSBitmapImageRep, scale: CGFloat, spans: [ClosedRange<CGFloat>], bottom: CGFloat) {
        XCTAssertTrue(SidebarDialTuning.store !== UserDefaults.standard, "dial store must be the isolated suite")
        let store = SidebarDialTuning.store
        store.set(mode.rawValue, forKey: SidebarDialTuning.trayWidthKey)
        defer { store.removeObject(forKey: SidebarDialTuning.trayWidthKey) }
        XCTAssertEqual(SidebarDialTuning.trayWidth(), mode)

        let size = CGSize(width: columnWidth, height: 120)
        let (rep, scale) = try renderTray(vertical: false, size: size, gutter: gutter)
        let bottom = size.height - SidebarTray.bottomPadding(isVertical: false)
        let spans = try capsuleSpans(rep, scale: scale, alongX: true, at: bottom - height / 2)
        return (rep, scale, spans, bottom)
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
        let padding = SidebarDialTuning.trayInnerPadding()
        let gap = SidebarDialTuning.trayGroupGap()
        let margin = SidebarDialTuning.windowMargin()
        // The gutter the pinned app really has outside the column: the card's
        // leading inset. The column is `columnWidth` wide; the card starts
        // `gutter` past its edge.
        let gutter = WorkspaceLayout.sidebarTrailingGutter(for: .pinned)
        let toggleWidth = button + 2 * padding
        let height = button + 2 * padding

        let (rep, scale, spans, bottom) = try expandedTraySpans(mode: .fill, columnWidth: columnWidth, height: height, gutter: gutter)
        XCTAssertEqual(spans.count, 2, "one span per capsule, got \(spans)")
        guard spans.count == 2 else { return }
        XCTAssertEqual(spans[0].lowerBound, margin, accuracy: 1.0, "create capsule starts at the leading margin")
        XCTAssertEqual(spans[0].upperBound + gap, spans[1].lowerBound, accuracy: 1.0, "create's right edge plus the group gap meets toggle's left edge")
        XCTAssertEqual(spans[1].upperBound - spans[1].lowerBound, toggleWidth, accuracy: 1.0, "toggle capsule stays button size plus padding")
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
        let toggleWidth = button + 2 * padding
        let height = button + 2 * padding

        let (rep, scale, spans, bottom) = try expandedTraySpans(mode: .hug, columnWidth: columnWidth, height: height)
        XCTAssertEqual(spans.count, 2, "two capsules side by side, got \(spans)")
        guard spans.count == 2 else { return }
        XCTAssertEqual(spans[0].lowerBound, SidebarDialTuning.windowMargin(), accuracy: 1.0, "create capsule starts at the window margin")
        XCTAssertEqual(spans[0].upperBound - spans[0].lowerBound, createWidth, accuracy: 1.0, "create capsule width")
        XCTAssertEqual(spans[1].lowerBound - spans[0].upperBound, gap, accuracy: 1.0, "gap between the capsules")
        XCTAssertEqual(spans[1].upperBound - spans[1].lowerBound, toggleWidth, accuracy: 1.0, "toggle capsule width")
        try assertSharedBaseline(spans, rep: rep, scale: scale, height: height, bottom: bottom)
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

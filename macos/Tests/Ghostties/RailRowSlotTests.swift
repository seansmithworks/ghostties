import XCTest
import Combine
import SwiftUI
import GhosttiesCore
@testable import Ghostty

/// A row's slot on the rail is its row in the sidebar: 32pt for a one-line
/// row, 48pt for one with a second line (plus a needs-you row's action
/// line). So every thread row, project header and the Idle fold's row
/// keeps its y and height at each step of the collapse/expand morph and in
/// the hover reveal, and a click lands on the row the pointer was over.
///
/// Harness from `NeedsYouRowRailHeightTests`: the real
/// `WorkspaceViewContainer`, held at each morph progress with
/// `applyMorphStep`, frames from `redlineRegistryForTesting`. Each run
/// prints its measurements as `RAILSLOT|` lines.
@MainActor
final class RailRowSlotTests: PrivateDefaultsTestCase {
    private let needsYouId = UUID(uuidString: "5C1D7A20-1234-4A11-8B00-0000000000A1")!
    private let errorId = UUID(uuidString: "5C1D7A20-1234-4A11-8B00-0000000000A2")!
    private let workingId = UUID(uuidString: "5C1D7A20-1234-4A11-8B00-0000000000A3")!
    private let doneId = UUID(uuidString: "5C1D7A20-1234-4A11-8B00-0000000000A4")!
    private let otherId = UUID(uuidString: "5C1D7A20-1234-4A11-8B00-0000000000A5")!
    private let idleId = UUID(uuidString: "5C1D7A20-1234-4A11-8B00-0000000000A6")!
    private let firstProjectId = UUID(uuidString: "5C1D7A20-1234-4A11-8B00-0000000000B1")!
    private let secondProjectId = UUID(uuidString: "5C1D7A20-1234-4A11-8B00-0000000000B2")!
    private let idleProjectId = UUID(uuidString: "5C1D7A20-1234-4A11-8B00-0000000000B3")!

    private let bashPermission = #"{"cwd":"/tmp","hook_event_name":"PermissionRequest","session_id":"c-1","tool_name":"Bash","tool_input":{"command":"npm test"}}"#
    private let busyTool = #"{"cwd":"/tmp","hook_event_name":"PreToolUse","session_id":"c-5","tool_name":"Bash","tool_use_id":"tu-5","tool_input":{"command":"ls"}}"#

    private var tempDirs: [URL] = []

    override func tearDown() {
        for dir in tempDirs { try? FileManager.default.removeItem(at: dir) }
        tempDirs = []
        super.tearDown()
    }

    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    private func spin(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    }

    /// The frames compared, in reading order, with what each is. A
    /// project header reports no frame of its own, so its tile stands for
    /// it: the tile grows from 32 to 40pt about its centre, so only its
    /// centre is compared.
    private var slots: [(id: String, name: String)] {
        [
            (RedlineID.header(firstProjectId.uuidString) + ".tile", "header atlas-api (tile centre)"),
            (RedlineID.row(needsYouId), "row needs you (2 lines + actions)"),
            (RedlineID.row(errorId), "row error (2 lines)"),
            (RedlineID.row(workingId), "row working (1 line)"),
            (RedlineID.row(doneId), "row done (1 line)"),
            (RedlineID.header(secondProjectId.uuidString) + ".tile", "header field-notes (tile centre)"),
            (RedlineID.row(otherId), "row working (1 line)"),
            (RedlineID.header(SidebarIdleFold.rowId), "Idle fold row"),
        ]
    }

    /// atlas-api: a needs-you row, an error row, a working row, a done row.
    /// field-notes: one working row. pendulum: one stopped thread, so it
    /// sits behind the Idle fold's row.
    private func makeWorld() -> (WorkspaceStore, ClaudeStateStore, [AgentSession]) {
        let first = Project(id: firstProjectId, name: "atlas-api", rootPath: "/Users/example/work/atlas-api")
        let second = Project(id: secondProjectId, name: "field-notes", rootPath: "/Users/example/work/field-notes")
        let idle = Project(id: idleProjectId, name: "pendulum", rootPath: "/Users/example/work/pendulum")
        func session(_ id: UUID, _ name: String, _ project: Project) -> AgentSession {
            AgentSession(
                id: id, name: name, templateId: UUID(), projectId: project.id,
                lastActiveAt: Date(), lastOutputAt: Date(), isNamePinned: true
            )
        }
        let sessions = [
            session(needsYouId, "deploy preview", first),
            session(errorId, "schema notes", first),
            session(workingId, "auth refactor", first),
            session(doneId, "flaky test", first),
            session(otherId, "layout pass", second),
            session(idleId, "old spike", idle),
        ]
        let store = WorkspaceStore(
            testingProjects: [first, second, idle], testingSessions: sessions,
            hasShownPinMigrationNotice: true, hasDismissedPinMigrationNotice: true
        )
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RailRowSlot-\(UUID().uuidString)", isDirectory: true)
        tempDirs.append(dir)
        let claude = ClaudeStateStore(directoryURL: dir)
        claude.resumeWriterForTesting = { _, _ in }
        let rows: [(UUID, String, SessionIndicatorState)] = [
            (needsYouId, bashPermission, .needsAttention),
            (errorId, busyTool, .error),
            (workingId, busyTool, .processing),
            (doneId, busyTool, .idle),
            (otherId, busyTool, .processing),
        ]
        for (id, hook, indicator) in rows {
            let json = #"{"ghosttiesSessionId":"\#(id.uuidString)","updatedAt":\#(Int(Date().timeIntervalSince1970)),"hook":\#(hook)}"#
            try? json.write(to: dir.appendingPathComponent("\(id.uuidString).json"), atomically: true, encoding: .utf8)
            claude.refreshForTesting()
            store.updateIndicatorState(id: id, state: indicator)
            store.updateSessionStatus(id: id, status: .running)
        }
        return (store, claude, sessions)
    }

    /// The real sidebar over the world. `reveal` starts the store closed
    /// and opens the hover reveal through the store; otherwise it is pinned
    /// and held at each step in `steps`.
    private func withSidebar(reveal: Bool = false, morph steps: [CGFloat], _ body: (CGFloat, [String: CGRect], SidebarMode) throws -> Void) throws {
        try withDials({
            $0.set(true, forKey: SidebarDialTuning.redlinesKey)
            $0.set(true, forKey: SidebarDialTuning.hoverBarPushesCanvasKey)
        }) {
            let (store, claude, sessions) = makeWorld()
            store.updateSidebarMode(reveal ? .closed : .pinned)
            let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel(), store: store)
            container.coordinatorForTesting.claudeStateStoreForTesting = claude
            container.coordinatorForTesting.setActiveSessionIdForTesting(sessions[2].id)
            let window = NSWindow(
                contentRect: .init(x: 0, y: 0, width: 900, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = container
            window.orderFrontRegardless()
            defer {
                window.contentView = nil
                window.orderOut(nil)
                window.close()
            }
            for _ in 0..<10 { container.layoutSubtreeIfNeeded(); spin(0.05) }
            if reveal {
                // The way `SidebarPresenceTests` opens it: the strip's own
                // tracking area gets an enter, delivered in-process.
                spin(0.5)
                container.updateTrackingAreas()
                if let strip = container.trackingAreas.first {
                    container.mouseEntered(with: NSEvent.enterExitEvent(
                        with: .mouseEntered, location: NSPoint(x: 4, y: 300), modifierFlags: [],
                        timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                        trackingNumber: unsafeBitCast(strip, to: Int.self), userData: nil
                    )!)
                }
                spin(1.0)
            }
            for p in steps {
                if !reveal { container.applyMorphStep(p) }
                for _ in 0..<6 { container.layoutSubtreeIfNeeded(); spin(0.05) }
                try body(p, container.redlineRegistryForTesting.rects, container.sidebarModeForTesting)
            }
        }
    }

    private func assertSameSlots(_ frames: [String: CGRect], as base: [String: CGRect], _ label: String) {
        for slot in slots {
            guard let b = base[slot.id], let f = frames[slot.id] else {
                XCTFail("\(label): \(slot.name) is not drawn; frames \(frames.keys.sorted())")
                continue
            }
            if slot.id.hasSuffix(".tile") {
                print(String(
                    format: "RAILSLOT|%@|%@|base midY %.1f|here midY %.1f|dy %.1f",
                    label, slot.name, b.midY, f.midY, f.midY - b.midY
                ))
                XCTAssertEqual(f.midY, b.midY, accuracy: 0.5, "\(label): \(slot.name) moves \(f.midY - b.midY)pt in y")
                continue
            }
            print(String(
                format: "RAILSLOT|%@|%@|base y %.1f h %.1f|here y %.1f h %.1f|dy %.1f dh %.1f",
                label, slot.name, b.minY, b.height, f.minY, f.height, f.minY - b.minY, f.height - b.height
            ))
            XCTAssertEqual(f.minY, b.minY, accuracy: 0.5, "\(label): \(slot.name) moves \(f.minY - b.minY)pt in y")
            XCTAssertEqual(f.height, b.height, accuracy: 0.5, "\(label): \(slot.name) changes height by \(f.height - b.height)pt")
        }
    }

    /// The expanded sidebar's frames: the base everything is compared to.
    private func expandedFrames() throws -> [String: CGRect] {
        var base: [String: CGRect] = [:]
        try withSidebar(morph: [0]) { _, frames, _ in base = frames }
        return base
    }

    /// Control: the fixture draws the rows this file is about, at the
    /// sidebar's heights.
    func testTheExpandedSidebarDrawsOneLineTwoLineAndNeedsYouRows() throws {
        let base = try expandedFrames()
        XCTAssertEqual(try XCTUnwrap(base[RedlineID.row(workingId)]).height, 32, accuracy: 0.5, "a working row is one line")
        XCTAssertEqual(try XCTUnwrap(base[RedlineID.row(doneId)]).height, 32, accuracy: 0.5, "a done row is one line")
        XCTAssertEqual(try XCTUnwrap(base[RedlineID.row(errorId)]).height, 48, accuracy: 0.5, "an error row is two lines")
        XCTAssertEqual(
            try XCTUnwrap(base[RedlineID.row(needsYouId)]).height, 48 + SessionRowActionLine.addedHeight, accuracy: 0.5,
            "a needs-you row is two lines and its action line"
        )
        XCTAssertNotNil(base[RedlineID.header(SidebarIdleFold.rowId)], "the Idle fold's row is drawn; frames \(base.keys.sorted())")
    }

    /// No row, header or the Idle fold's row moves or changes height at
    /// any step between the sidebar and the rail.
    func testEveryRowKeepsItsYAndHeightAcrossTheMorph() throws {
        var base: [String: CGRect] = [:]
        try withSidebar(morph: [0, 0.25, 0.5, 0.75, 1]) { p, frames, _ in
            if p == 0 { base = frames }
            assertSameSlots(frames, as: base, p == 1 ? "rail vs expanded" : "morph \(p) vs expanded")
        }
    }

    /// The hover reveal draws every row where the rail had it, so a click
    /// lands on the row the pointer was over.
    func testEveryRowKeepsItsYAndHeightInTheHoverReveal() throws {
        var rail: [String: CGRect] = [:]
        try withSidebar(morph: [1]) { _, frames, _ in rail = frames }
        try withSidebar(reveal: true, morph: [0]) { _, frames, mode in
            XCTAssertEqual(mode, .hoverRevealed, "control: the sidebar is in the hover reveal")
            assertSameSlots(frames, as: rail, "hover reveal vs rail")
        }
    }

    /// The selected project's column on the rail ends its inset below the
    /// chip of its last row, whatever that row's height: here a one-line
    /// row, whose chip fills its 32pt slot.
    func testTheRailColumnEndsItsInsetBelowTheLastRowsChip() throws {
        try withSidebar(morph: [1]) { _, frames, _ in
            let column = try XCTUnwrap(frames[RedlineID.groupCard], "the selected project's column")
            let lastChip = try XCTUnwrap(frames[RedlineID.row(doneId) + ".chip"], "the last row's chip")
            let tile = try XCTUnwrap(frames[RedlineID.header(firstProjectId.uuidString) + ".tile"], "the project's tile")
            let inset = RailProjectColumn.columnInset
            print(String(
                format: "RAILSLOT|rail column|y %.1f to %.1f|tile top %.1f|last chip bottom %.1f|inset %.1f",
                column.minY, column.maxY, tile.minY, lastChip.maxY, inset
            ))
            XCTAssertEqual(column.maxY - lastChip.maxY, inset, accuracy: 0.5, "the column's bottom inset below the last chip")
            XCTAssertEqual(tile.minY - column.minY, inset, accuracy: 0.5, "the column's top inset above the tile")
        }
    }

    /// On the rail a row's chip (its hover and selection mark) sits whole
    /// inside the row's slot, and its glyph on the slot's centre.
    func testTheRailsChipAndGlyphFitInsideTheRowsSlot() throws {
        try withSidebar(morph: [1]) { _, frames, _ in
            for id in [needsYouId, errorId, workingId, doneId, otherId] {
                let row = try XCTUnwrap(frames[RedlineID.row(id)], "row \(id)")
                let chip = try XCTUnwrap(frames[RedlineID.row(id) + ".chip"], "chip \(id)")
                let glyph = try XCTUnwrap(frames[RedlineID.row(id) + ".glyph"], "glyph \(id)")
                print(String(
                    format: "RAILSLOT|rail chip|%@|row y %.1f h %.1f|chip y %.1f h %.1f w %.1f|glyph midY %.1f",
                    String(id.uuidString.suffix(2)), row.minY, row.height, chip.minY, chip.height, chip.width, glyph.midY
                ))
                XCTAssertGreaterThanOrEqual(chip.minY, row.minY - 0.5, "the chip starts inside its row")
                XCTAssertLessThanOrEqual(chip.maxY, row.maxY + 0.5, "the chip ends inside its row")
                XCTAssertEqual(chip.midY, glyph.midY, accuracy: 0.5, "the glyph is centred in its chip")
                XCTAssertEqual(chip.height.truncatingRemainder(dividingBy: 8), 0, accuracy: 0.01, "the chip is on the 8pt grid")
            }
        }
    }
}

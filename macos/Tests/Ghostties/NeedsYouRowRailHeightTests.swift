import XCTest
import Combine
import SwiftUI
import GhosttiesCore
@testable import Ghostty

/// A needs-you row's extra height on the beta-26 rail.
///
/// On beta 26 a session row is one height in the sidebar and on the rail
/// (the rail keeps every row's slot; only its labels fade), so a needs-you
/// row's action line has to keep its room on the rail too, or every tile
/// and glyph below it jumps up as the sidebar closes and down as it opens
/// (and again on the hover reveal). The beta-26 morph moves tiles on its
/// own (they travel to the rail's centre and change size), so this compares
/// each frame's movement against a control world whose two needs-you rows
/// are working rows instead: a needs-you row may add no movement of its
/// own. Only y and height are compared; x travel is beta 26's design.
///
/// Harness from the rail-05 vertical gate (`RailStaysPutVerticalGateTests`
/// on sidebar/6-approvals): the real `WorkspaceViewContainer`, held at each
/// morph progress with `applyMorphStep`, frames from
/// `redlineRegistryForTesting`.
@MainActor
final class NeedsYouRowRailHeightTests: XCTestCase {
    private let bashId = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000E1")!
    private let askId = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000E2")!
    private let workingId = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000E3")!
    private let otherId = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000E4")!

    private let bashPermission = #"{"cwd":"/tmp","hook_event_name":"PermissionRequest","session_id":"c-1","tool_name":"Bash","tool_input":{"command":"npm test"}}"#
    private let askQuestion = #"{"cwd":"/tmp","hook_event_name":"PreToolUse","session_id":"c-2","tool_name":"AskUserQuestion","tool_use_id":"tu-1","tool_input":{"questions":[{"question":"Which env name?","header":"Env","options":[{"label":"staging"},{"label":"prod"}],"multiSelect":false}]}}"#
    private let busyTool = #"{"cwd":"/tmp","hook_event_name":"PreToolUse","session_id":"c-5","tool_name":"Bash","tool_use_id":"tu-5","tool_input":{"command":"ls"}}"#

    private var tempDirs: [URL] = []

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: ApprovalFlag.defaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: ApprovalFlag.defaultsKey)
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

    /// Project 1: a bounded needs-you row, a freeform needs-you row, a
    /// working row. Project 2 below it: one working row. `needsYou` false
    /// makes the first two working rows too: the control world.
    private func makeWorld(needsYou: Bool) -> (WorkspaceStore, ClaudeStateStore, [AgentSession]) {
        // Fixed ids so a tile's redline key (`header.<group id>.tile`) is
        // the same in every world this file builds.
        let first = Project(id: UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000F1")!, name: "atlas-api", rootPath: "/Users/example/work/atlas-api")
        let second = Project(id: UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000F2")!, name: "field-notes", rootPath: "/Users/example/work/field-notes")
        func session(_ id: UUID, _ name: String, _ project: Project) -> AgentSession {
            AgentSession(
                id: id, name: name, templateId: UUID(), projectId: project.id,
                lastActiveAt: Date(), lastOutputAt: Date(), isNamePinned: true
            )
        }
        let sessions = [
            session(bashId, "deploy preview", first),
            session(askId, "schema notes", first),
            session(workingId, "auth refactor", first),
            session(otherId, "layout pass", second),
        ]
        let store = WorkspaceStore(
            testingProjects: [first, second], testingSessions: sessions,
            hasShownPinMigrationNotice: true, hasDismissedPinMigrationNotice: true
        )
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeedsYouRowRailHeight-\(UUID().uuidString)", isDirectory: true)
        tempDirs.append(dir)
        let claude = ClaudeStateStore(directoryURL: dir)
        claude.resumeWriterForTesting = { _, _ in }
        let rows: [(UUID, String, SessionIndicatorState)] = [
            (bashId, needsYou ? bashPermission : busyTool, needsYou ? .needsAttention : .processing),
            (askId, needsYou ? askQuestion : busyTool, needsYou ? .needsAttention : .processing),
            (workingId, busyTool, .processing),
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

    /// Every project tile's and session glyph's frame, by redline id.
    private func tileAndGlyphFrames(_ container: WorkspaceViewContainer) -> [String: CGRect] {
        container.redlineRegistryForTesting.rects.filter { $0.key.hasSuffix(".tile") || $0.key.hasSuffix(".glyph") }
    }

    /// The real sidebar over the fixture. `reveal` starts the store closed
    /// and opens the hover reveal through the store; otherwise it is
    /// pinned. `body` runs once per step in `steps` with that step's frames
    /// and the container's mode.
    private func withSidebar(needsYou: Bool, reveal: Bool = false, morph steps: [CGFloat], _ body: (CGFloat, [String: CGRect], SidebarMode) throws -> Void) throws {
        try withDials({
            $0.set(true, forKey: SidebarDialTuning.redlinesKey)
            $0.set(true, forKey: SidebarDialTuning.hoverBarPushesCanvasKey)
        }) {
            let tabKey = "ghostties.sidebarTab"
            let previousTab = UserDefaults.standard.object(forKey: tabKey)
            UserDefaults.standard.set(SidebarTab.projects.rawValue, forKey: tabKey)
            defer {
                if let previousTab { UserDefaults.standard.set(previousTab, forKey: tabKey) } else { UserDefaults.standard.removeObject(forKey: tabKey) }
            }
            let (store, claude, sessions) = makeWorld(needsYou: needsYou)
            store.updateSidebarMode(reveal ? .closed : .pinned)
            let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel(), store: store)
            container.coordinatorForTesting.claudeStateStoreForTesting = claude
            container.coordinatorForTesting.setActiveSessionIdForTesting(sessions[0].id)
            let window = NSWindow(
                contentRect: .init(x: 0, y: 0, width: 900, height: 620),
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
                try body(p, tileAndGlyphFrames(container), container.sidebarModeForTesting)
            }
        }
    }

    private struct Move: Equatable {
        let dy: CGFloat
        let dh: CGFloat
    }

    /// Each frame's movement from `base` to `frames`, by redline id.
    private func moves(_ frames: [String: CGRect], from base: [String: CGRect]) -> [String: Move] {
        var out: [String: Move] = [:]
        for (id, b) in base {
            guard let f = frames[id] else { continue }
            out[id] = Move(dy: f.minY - b.minY, dh: f.height - b.height)
        }
        return out
    }

    private func assertSameMoves(_ moves: [String: Move], as control: [String: Move], _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(control.isEmpty, "\(label): control: frames are drawn", file: file, line: line)
        for (id, c) in control.sorted(by: { $0.key < $1.key }) {
            guard let m = moves[id] else {
                XCTFail("\(label): \(id) is drawn in the control world but not beside a needs-you row", file: file, line: line)
                continue
            }
            XCTAssertEqual(m.dy, c.dy, accuracy: 0.5, "\(label): \(id) moves \(m.dy)pt in y beside a needs-you row, \(c.dy)pt without", file: file, line: line)
            XCTAssertEqual(m.dh, c.dh, accuracy: 0.5, "\(label): \(id) changes height by \(m.dh)pt beside a needs-you row, \(c.dh)pt without", file: file, line: line)
        }
    }

    private let steps: [CGFloat] = [0, 0.25, 0.5, 0.75, 1]
    private let lowerTile = "header.9B2A6E10-1234-4A11-8B00-0000000000F2.tile"

    /// Every frame's movement from progress 0, at each step.
    private func morphMoves(needsYou: Bool) throws -> [CGFloat: [String: Move]] {
        var base: [String: CGRect] = [:]
        var out: [CGFloat: [String: Move]] = [:]
        try withSidebar(needsYou: needsYou, morph: steps) { p, frames, _ in
            if p == 0 {
                base = frames
                XCTAssertTrue(frames.keys.contains { $0.hasPrefix("header.") && $0.hasSuffix(".tile") }, "control: project tiles are drawn; frames \(frames.keys.sorted())")
                XCTAssertNotNil(frames[RedlineID.row(otherId) + ".glyph"], "control: the row below the needs-you rows draws its glyph; frames \(frames.keys.sorted())")
            }
            out[p] = moves(frames, from: base)
        }
        return out
    }

    /// Closing and opening the sidebar moves no tile or glyph more beside a
    /// needs-you row than beside a working one, flag off and on.
    func testANeedsYouRowAddsNoVerticalMoveAcrossTheMorph() throws {
        for flag in [false, true] {
            if flag { UserDefaults.standard.set(true, forKey: ApprovalFlag.defaultsKey) } else { UserDefaults.standard.removeObject(forKey: ApprovalFlag.defaultsKey) }
            let control = try morphMoves(needsYou: false)
            let needsYou = try morphMoves(needsYou: true)
            XCTAssertNotNil(needsYou[1]?[lowerTile], "flag \(flag): control: the lower project's tile is drawn on the rail")
            for p in steps where p > 0 {
                assertSameMoves(needsYou[p] ?? [:], as: control[p] ?? [:], "flag \(flag), progress \(p)")
            }
        }
    }

    /// The hover reveal draws every tile and glyph where the rail had it,
    /// relative to the control world, with Approve/Deny on.
    func testTheHoverRevealAddsNoVerticalMoveBesideANeedsYouRow() throws {
        UserDefaults.standard.set(true, forKey: ApprovalFlag.defaultsKey)
        func revealMoves(needsYou: Bool) throws -> [String: Move] {
            var rail: [String: CGRect] = [:]
            try withSidebar(needsYou: needsYou, morph: [1]) { _, frames, _ in rail = frames }
            var out: [String: Move] = [:]
            try withSidebar(needsYou: needsYou, reveal: true, morph: [0]) { _, frames, mode in
                XCTAssertEqual(mode, .hoverRevealed, "control: the sidebar is in the hover reveal")
                out = moves(frames, from: rail)
            }
            XCTAssertNotNil(out[lowerTile], "control: the lower project's tile is drawn on the rail and in the reveal")
            return out
        }
        let needsYou = try revealMoves(needsYou: true)
        let control = try revealMoves(needsYou: false)
        assertSameMoves(needsYou, as: control, "hover reveal")
    }
}

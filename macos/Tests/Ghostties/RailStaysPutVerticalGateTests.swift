import XCTest
import Combine
import SwiftUI
import GhosttiesCore
@testable import Ghostty

/// Vertical no-shift gate. Sean: "Shifting/moving the app icon is a concern
/// as the sidebar scales... dont want to have unintended shifts in the ui."
///
/// A needs-you row grows an inline action line in the sidebar (about 32pt)
/// that the rail never draws, so every tile and glyph below it moves
/// vertically across the morph and the hover reveal. The existing gates
/// (`HoverApprovalsInlineGateTests` (l), the morph gates) only read x.
///
/// Same harness as `HoverApprovalsInlineGateTests`: the real
/// `WorkspaceViewContainer` pinned, held at each morph progress with
/// `applyMorphStep`, frames read from `redlineRegistryForTesting`. No text
/// is read, so Redlines stays on throughout.
@MainActor
final class RailStaysPutVerticalGateTests: XCTestCase {
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
    /// working row. Project 2 below it: one working row.
    private func makeWorld() -> (WorkspaceStore, ClaudeStateStore, [AgentSession]) {
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
            .appendingPathComponent("RailStaysPutGate-\(UUID().uuidString)", isDirectory: true)
        tempDirs.append(dir)
        let claude = ClaudeStateStore(directoryURL: dir)
        claude.resumeWriterForTesting = { _, _ in }
        let rows: [(UUID, String, SessionIndicatorState)] = [
            (bashId, bashPermission, .needsAttention),
            (askId, askQuestion, .needsAttention),
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
    private func withSidebar(reveal: Bool = false, morph steps: [CGFloat], _ body: (CGFloat, [String: CGRect], SidebarMode) throws -> Void) throws {
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
            let (store, claude, sessions) = makeWorld()
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

    private func assertSameY(_ frames: [String: CGRect], as base: [String: CGRect], _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        for (id, b) in base.sorted(by: { $0.key < $1.key }) {
            guard let f = frames[id] else {
                XCTFail("\(label): \(id) is not drawn (it was at y \(b.minY))", file: file, line: line)
                continue
            }
            XCTAssertEqual(f.minY, b.minY, accuracy: 0.5, "\(label): \(id) minY \(f.minY) vs base \(b.minY)", file: file, line: line)
            XCTAssertEqual(f.height, b.height, accuracy: 0.5, "\(label): \(id) height \(f.height) vs base \(b.height)", file: file, line: line)
        }
    }

    // (m) no vertical shift across the morph, with the approval flag on and off.
    func testTilesAndGlyphsKeepTheirYAcrossTheMorph() throws {
        for flag in [false, true] {
            if flag { UserDefaults.standard.set(true, forKey: ApprovalFlag.defaultsKey) } else { UserDefaults.standard.removeObject(forKey: ApprovalFlag.defaultsKey) }
            var base: [String: CGRect] = [:]
            try withSidebar(morph: [0, 0.25, 0.5, 0.75, 1]) { p, frames, _ in
                if p == 0 {
                    base = frames
                    XCTAssertTrue(base.keys.contains { $0.hasPrefix("header.") && $0.hasSuffix(".tile") }, "flag \(flag): control: project tiles are drawn; frames \(base.keys.sorted())")
                    XCTAssertNotNil(base[RedlineID.row(bashId) + ".glyph"], "flag \(flag): control: the needs-you row's glyph is drawn")
                } else {
                    assertSameY(frames, as: base, "flag \(flag), progress \(p)")
                }
            }
        }
    }

    // (n) the hover reveal puts every tile at the rail's y, flag on.
    func testHoverRevealPutsEveryTileAtTheRailsY() throws {
        UserDefaults.standard.set(true, forKey: ApprovalFlag.defaultsKey)
        var rail: [String: CGRect] = [:]
        try withSidebar(morph: [1]) { _, frames, _ in rail = frames }
        XCTAssertFalse(rail.isEmpty, "control: the rail draws tiles and glyphs")

        try withSidebar(reveal: true, morph: [0]) { _, frames, mode in
            XCTAssertEqual(mode, .hoverRevealed, "control: the sidebar is in the hover reveal")
            assertSameY(frames, as: rail, "hover reveal")
        }
    }
}

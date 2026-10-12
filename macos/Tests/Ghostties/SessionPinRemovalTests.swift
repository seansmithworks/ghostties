import XCTest
import GhosttiesCore
@testable import Ghostty

/// Pin is a project-only concept: no session surface offers Pin/Unpin, and
/// a workspace file that still carries a pinned session loads, keeps the
/// flag on disk, and shows the session in its normal place. The load test
/// injects its state directory; nothing here sets `GHOSTTIES_STATE_DIR`.
@MainActor
final class SessionPinRemovalTests: XCTestCase {
    func testSessionRowMenuHasNoPinInAnyState() {
        let states = [(true, true), (true, false), (false, true), (false, false)]
        for (isRunning, canResume) in states {
            let titles = SessionRowMenu.actions(isRunning: isRunning, canResume: canResume).compactMap { $0?.title }
            XCTAssertFalse(titles.contains("Pin"), "running \(isRunning), resume \(canResume)")
            XCTAssertFalse(titles.contains("Unpin"), "running \(isRunning), resume \(canResume)")
        }
        // The rest of the menu is unchanged.
        XCTAssertEqual(SessionRowMenu.actions(isRunning: true, canResume: true), [.rename, nil, .stop])
        XCTAssertEqual(SessionRowMenu.actions(isRunning: false, canResume: true), [.rename, nil, .resume, .startFresh, .delete])
        XCTAssertEqual(SessionRowMenu.actions(isRunning: false, canResume: false), [.rename, nil, .startFresh, .delete])
    }

    func testOldWorkspaceWithAPinnedSessionStillLoads() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionPinRemovalTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let projectId = UUID()
        let sessionId = UUID()
        // A built-in template, so load's validation keeps the session.
        let templateId = try XCTUnwrap(AgentTemplate.defaults.first).id
        let json = """
        {
            "projects": [
                { "id": "\(projectId.uuidString)", "name": "atlas-api", "rootPath": "/tmp/atlas-api", "isPinned": false }
            ],
            "sessions": [
                {
                    "id": "\(sessionId.uuidString)",
                    "name": "orchestrator",
                    "templateId": "\(templateId.uuidString)",
                    "projectId": "\(projectId.uuidString)",
                    "isPinned": true
                }
            ],
            "templates": [],
            "sidebarMode": 0,
            "hasShownPinMigrationNotice": true
        }
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("workspace.json"))

        let store = WorkspaceStore(testingStateDirectory: dir)
        XCTAssertEqual(store.sessions.map(\.id), [sessionId])
        // The user's data is kept...
        XCTAssertEqual(store.sessions.first?.isPinned, true)
        // ...but nothing renders it as pinned: no Pinned section, and the
        // closed session sits in History like any other.
        let sections = SidebarSessionSections.make(sessions: store.sessions, statuses: [:], sessionIdsStartedThisLaunch: [])
        XCTAssertTrue(sections.pinned.isEmpty)
        XCTAssertEqual(sections.history.map(\.id), [sessionId])
    }
}

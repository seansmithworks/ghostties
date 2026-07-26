// IDE-ONLY: not currently exercised in CI macos job (build-only).
// Run via Xcode Cmd+U or xcodebuild test locally.
import XCTest
@testable import Ghostty

/// Tests for `WorkspaceStore.syncSessionNameFromTitle` / `renameSession` /
/// `resetNamePin` — the Claude Code → sidebar name-sync direction and its pin
/// semantics.
@MainActor
final class SessionNameSyncTests: XCTestCase {

    private func makeProject() -> Project {
        Project(name: "ghostties", rootPath: "/Users/sean/Code/ghostties", isPinned: true)
    }

    private func makeStore(session: AgentSession, project: Project) -> WorkspaceStore {
        WorkspaceStore(testingProjects: [project], testingSessions: [session])
    }

    func testSyncUpdatesUnpinnedSessionName() {
        let project = makeProject()
        let session = AgentSession(name: "Session 1", templateId: UUID(), projectId: project.id)
        let store = makeStore(session: session, project: project)

        store.syncSessionNameFromTitle(id: session.id, title: "Refactoring the auth module")

        XCTAssertEqual(store.sessions(for: project.id).first?.name, "Refactoring the auth module")
    }

    func testManualRenamePinsTheName() {
        let project = makeProject()
        let session = AgentSession(name: "Session 1", templateId: UUID(), projectId: project.id)
        let store = makeStore(session: session, project: project)

        store.renameSession(id: session.id, name: "My Custom Name")

        XCTAssertTrue(store.sessions(for: project.id).first?.isNamePinned ?? false)
        XCTAssertEqual(store.sessions(for: project.id).first?.name, "My Custom Name")
    }

    func testPinnedSessionIgnoresIncomingTitles() {
        let project = makeProject()
        let session = AgentSession(name: "Session 1", templateId: UUID(), projectId: project.id)
        let store = makeStore(session: session, project: project)

        store.renameSession(id: session.id, name: "My Custom Name")
        store.syncSessionNameFromTitle(id: session.id, title: "Refactoring the auth module")

        XCTAssertEqual(
            store.sessions(for: project.id).first?.name,
            "My Custom Name",
            "A pinned session must ignore incoming agent title updates"
        )
    }

    func testResetNamePinResumesAutomaticSync() {
        let project = makeProject()
        let session = AgentSession(name: "Session 1", templateId: UUID(), projectId: project.id)
        let store = makeStore(session: session, project: project)

        store.renameSession(id: session.id, name: "My Custom Name")
        store.resetNamePin(id: session.id)

        XCTAssertFalse(store.sessions(for: project.id).first?.isNamePinned ?? true)

        store.syncSessionNameFromTitle(id: session.id, title: "Refactoring the auth module")
        XCTAssertEqual(store.sessions(for: project.id).first?.name, "Refactoring the auth module")
    }
}

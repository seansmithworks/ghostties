import Combine
import XCTest
import GhosttiesCore
@testable import Ghostty

/// Tests for working directory → sidebar project sync: a session's project
/// follows its terminal's pwd (OSC 7 → `SurfaceView.$pwd`), the way an
/// unpinned session's name follows its terminal title. Synthetic paths and
/// isolated stores only — nothing here touches a real `workspace.json`.
@MainActor
final class SessionProjectSyncTests: XCTestCase {

    private let projectA = Project(name: "alpha", rootPath: "/tmp/ghostties-fixture/alpha", isPinned: true)
    private let projectB = Project(name: "beta", rootPath: "/tmp/ghostties-fixture/beta", isPinned: true)

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    private func session(in project: Project) -> AgentSession {
        AgentSession(name: "Session 1", templateId: AgentTemplate.defaults[0].id, projectId: project.id)
    }

    private func projectId(of id: UUID, in store: WorkspaceStore) -> UUID? {
        store.sessions.first { $0.id == id }?.projectId
    }

    /// The bug: a session created in A whose terminal `cd`s into B stayed
    /// under A. Driven through the coordinator's real pwd subscription, the
    /// same one `subscribeToOutput` wires to `surface.$pwd`.
    func testPwdIntoAnotherProjectMovesTheSession() {
        let s = session(in: projectA)
        let store = WorkspaceStore(testingProjects: [projectA, projectB], testingSessions: [s])
        let coordinator = SessionCoordinator()
        let pwd = PassthroughSubject<String?, Never>()
        coordinator.subscribeProjectSync(sessionId: s.id, pwdPublisher: pwd, store: store)

        pwd.send("/tmp/ghostties-fixture/alpha")
        pwd.send("/tmp/ghostties-fixture/beta/src/components")

        XCTAssertEqual(projectId(of: s.id, in: store), projectB.id)
        XCTAssertEqual(store.sessions(for: projectB.id).map(\.id), [s.id])
        XCTAssertTrue(store.sessions(for: projectA.id).isEmpty)
    }

    func testPwdOutsideEveryProjectLeavesTheSessionWhereItIs() {
        let s = session(in: projectA)
        let store = WorkspaceStore(testingProjects: [projectA, projectB], testingSessions: [s])

        store.syncSessionProjectFromWorkingDirectory(id: s.id, workingDirectory: "/Users/someone/Downloads")
        // A sibling whose name merely starts with a project's name is outside it.
        store.syncSessionProjectFromWorkingDirectory(id: s.id, workingDirectory: "/tmp/ghostties-fixture/beta-old")

        XCTAssertEqual(projectId(of: s.id, in: store), projectA.id)
    }

    func testDeepestContainingRootWins() {
        let web = Project(name: "web", rootPath: "/tmp/ghostties-fixture/beta/web/", isPinned: true)
        let s = session(in: projectA)
        // Order the outer root last so a first-match lookup would pick it.
        let store = WorkspaceStore(testingProjects: [projectA, web, projectB], testingSessions: [s])

        store.syncSessionProjectFromWorkingDirectory(id: s.id, workingDirectory: "/tmp/ghostties-fixture/beta/web/app")
        XCTAssertEqual(projectId(of: s.id, in: store), web.id)

        store.syncSessionProjectFromWorkingDirectory(id: s.id, workingDirectory: "/tmp/ghostties-fixture/beta/docs")
        XCTAssertEqual(projectId(of: s.id, in: store), projectB.id)
    }

    /// A `cd` within the same project (and the shell's per-prompt re-report
    /// of an unchanged pwd) must fire neither `objectWillChange` nor
    /// `persist()`.
    func testPwdWithinTheCurrentProjectIsANoOp() {
        let s = session(in: projectA)
        let store = WorkspaceStore(testingProjects: [projectA, projectB], testingSessions: [s])
        let coordinator = SessionCoordinator()
        let pwd = PassthroughSubject<String?, Never>()
        coordinator.subscribeProjectSync(sessionId: s.id, pwdPublisher: pwd, store: store)

        var willChangeCount = 0
        store.objectWillChange.sink { willChangeCount += 1 }.store(in: &cancellables)
        let persistBefore = store.persistCallCount

        pwd.send("/tmp/ghostties-fixture/alpha")
        pwd.send("/tmp/ghostties-fixture/alpha")
        pwd.send("/tmp/ghostties-fixture/alpha/Sources")
        pwd.send("")
        pwd.send(nil)

        XCTAssertEqual(projectId(of: s.id, in: store), projectA.id)
        XCTAssertEqual(willChangeCount, 0, "an unchanged project must not fire objectWillChange")
        XCTAssertEqual(store.persistCallCount, persistBefore, "an unchanged project must not call persist()")
    }

    func testMovedSessionAppendsAfterTheTargetProjectsSessions() {
        var existing = session(in: projectB)
        existing.sortOrder = 4
        let s = session(in: projectA)
        let store = WorkspaceStore(testingProjects: [projectA, projectB], testingSessions: [existing, s])

        store.syncSessionProjectFromWorkingDirectory(id: s.id, workingDirectory: "/tmp/ghostties-fixture/beta")

        XCTAssertEqual(store.sessions(for: projectB.id).map(\.id), [existing.id, s.id])
        XCTAssertEqual(store.sessions.first { $0.id == s.id }?.sortOrder, 5)
    }

    /// The move goes through the store's real `persist()` and survives a
    /// fresh store loaded from the same (injected, temporary) state dir.
    func testMovePersistsAcrossReload() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionProjectSyncTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let s = session(in: projectA)
        WorkspacePersistence.save(
            WorkspacePersistence.State(projects: [projectA, projectB], sessions: [s]),
            to: dir
        )
        let store = WorkspaceStore(testingStateDirectory: dir)
        XCTAssertEqual(projectId(of: s.id, in: store), projectA.id)

        store.syncSessionProjectFromWorkingDirectory(id: s.id, workingDirectory: "/tmp/ghostties-fixture/beta")
        await store.flushPersistenceForTesting()

        let reloaded = WorkspaceStore(testingStateDirectory: dir)
        XCTAssertEqual(projectId(of: s.id, in: reloaded), projectB.id)
    }

    /// A `workspace.json` written before this feature (session records with
    /// only the original required keys) still loads, and its sessions follow
    /// pwd like any other.
    func testLegacyWorkspaceFileLoadsAndFollowsPwd() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionProjectSyncTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let sessionId = UUID()
        let legacy = """
        {
          "projects": [
            {"id": "\(projectA.id)", "name": "alpha", "rootPath": "\(projectA.rootPath)", "isPinned": true},
            {"id": "\(projectB.id)", "name": "beta", "rootPath": "\(projectB.rootPath)", "isPinned": true}
          ],
          "sessions": [
            {"id": "\(sessionId)", "name": "Old", "templateId": "\(AgentTemplate.defaults[0].id)", "projectId": "\(projectA.id)"}
          ],
          "templates": [],
          "sidebarVisible": true
        }
        """
        try Data(legacy.utf8).write(to: dir.appendingPathComponent("workspace.json"))

        let store = WorkspaceStore(testingStateDirectory: dir)
        XCTAssertEqual(projectId(of: sessionId, in: store), projectA.id)

        store.syncSessionProjectFromWorkingDirectory(id: sessionId, workingDirectory: "/tmp/ghostties-fixture/beta")
        XCTAssertEqual(projectId(of: sessionId, in: store), projectB.id)
    }
}

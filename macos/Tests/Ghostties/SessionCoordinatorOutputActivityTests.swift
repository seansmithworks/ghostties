// IDE-ONLY: not currently exercised in CI macos job (build-only).
// Run via Xcode Cmd+U or xcodebuild test locally.
import Combine
import XCTest
import GhosttiesCore
@testable import Ghostty

/// Pins `SessionCoordinator.subscribeToOutput`'s `isOutput: true` argument —
/// the single call site that is allowed to advance `lastOutputAt` on a real
/// output-activity signal (see `WorkspaceStoreLastOutputAtTests` for the
/// store-level guard coverage, and `reference_lastactiveat-written-on-focus.md`
/// for why this split exists).
///
/// Drives the testable, injectable core of `subscribeToOutput` (generic
/// output publisher + `store:`) directly with a `PassthroughSubject<Void,
/// Never>` and an isolated `WorkspaceStore`, mirroring the pattern already
/// used for `subscribeNameSync` in `SessionNameSyncTests`.
@MainActor
final class SessionCoordinatorOutputActivityTests: XCTestCase {

    private func makeProject() -> Project {
        Project(name: "ghostties", rootPath: "/Users/sean/Code/ghostties")
    }

    private func makeStore(session: AgentSession, project: Project) -> WorkspaceStore {
        WorkspaceStore(testingProjects: [project], testingSessions: [session])
    }

    /// The regression this test exists to catch: deleting the `isOutput:
    /// true` argument inside `subscribeToOutput`'s sink would leave every
    /// other test in the suite green (nothing else exercises that code path)
    /// while silently disabling the entire `lastOutputAt` feature. Confirmed
    /// by temporarily removing the argument and re-running this single test
    /// — it fails (`lastOutputAt` stays nil) — then restoring it.
    func testOutputSignalAdvancesLastOutputAt() {
        let project = makeProject()
        let session = AgentSession(name: "Session 1", templateId: UUID(), projectId: project.id)
        let store = makeStore(session: session, project: project)
        let coordinator = SessionCoordinator()

        XCTAssertNil(store.sessions(for: project.id).first?.lastOutputAt)

        let outputSubject = PassthroughSubject<Void, Never>()
        coordinator.subscribeToOutput(sessionId: session.id, outputPublisher: outputSubject, store: store)

        outputSubject.send(())

        XCTAssertNotNil(
            store.sessions(for: project.id).first?.lastOutputAt,
            "a real output-activity signal must advance lastOutputAt"
        )
    }

    /// Same signal must also advance `lastActiveAt` (output is still activity
    /// for project bucketing purposes) — the output sink writes through both
    /// fields in one call.
    func testOutputSignalAlsoAdvancesLastActiveAt() {
        let project = makeProject()
        let session = AgentSession(name: "Session 1", templateId: UUID(), projectId: project.id)
        let store = makeStore(session: session, project: project)
        let coordinator = SessionCoordinator()

        let outputSubject = PassthroughSubject<Void, Never>()
        coordinator.subscribeToOutput(sessionId: session.id, outputPublisher: outputSubject, store: store)

        outputSubject.send(())

        XCTAssertNotNil(store.sessions(for: project.id).first?.lastActiveAt)
    }
}

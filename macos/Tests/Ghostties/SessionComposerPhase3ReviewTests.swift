import Foundation
import Testing
@testable import Ghostty

/// Regression coverage for the Phase 3 review pass of session-creation-unified
/// (F11). Two things are covered directly:
///
/// - `WorkspaceViewContainer.newSessionOpensComposer(in:)` — the exact
///   absent/true/false resolution the review flagged as "precisely the
///   class of bug this pass was chartered to find."
/// - `SessionComposerStore.resolveCascadeProject(workspaceStore:)` — the
///   smart-default cascade backing both instant-create paths
///   (Cmd+Shift+T, and Cmd+T with the preference off).
@MainActor
struct SessionComposerPhase3ReviewTests {

    // MARK: - Fixtures

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ghostties.phase3review.test.\(UUID().uuidString)")!
    }

    private func makeProject(name: String = "Proj", lastActiveAt: Date? = nil) -> Project {
        Project(name: name, rootPath: "/tmp/\(name)-\(UUID().uuidString)", lastActiveAt: lastActiveAt)
    }

    // MARK: - newSessionOpensComposer(in:)

    @Test func newSessionOpensComposerDefaultsToComposerWhenAbsent() {
        let defaults = makeDefaults()
        #expect(WorkspaceViewContainer.newSessionOpensComposer(in: defaults) == true)
    }

    @Test func newSessionOpensComposerIsComposerWhenExplicitlyTrue() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "ghostties.newSessionOpensComposer")
        #expect(WorkspaceViewContainer.newSessionOpensComposer(in: defaults) == true)
    }

    @Test func newSessionOpensComposerIsInstantWhenExplicitlyFalse() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "ghostties.newSessionOpensComposer")
        #expect(WorkspaceViewContainer.newSessionOpensComposer(in: defaults) == false)
    }

    // MARK: - SessionComposerStore.resolveCascadeProject

    @Test func resolveCascadeProjectReturnsNilWithNoProjects() {
        let store = WorkspaceStore(testingProjects: [], testingSessions: [])
        let composerStore = SessionComposerStore(isolatedForTesting: ())

        #expect(composerStore.resolveCascadeProject(workspaceStore: store) == nil)
    }

    /// No frontmost-terminal match (no key window in a test process) and no
    /// recorded MRU — falls through to step 3, most-recently-touched.
    @Test func resolveCascadeProjectFallsBackToMostRecentlyTouched() {
        let older = makeProject(name: "Older", lastActiveAt: Date(timeIntervalSince1970: 100))
        let newer = makeProject(name: "Newer", lastActiveAt: Date(timeIntervalSince1970: 200))
        let store = WorkspaceStore(testingProjects: [older, newer], testingSessions: [])
        let composerStore = SessionComposerStore(isolatedForTesting: ())

        #expect(composerStore.resolveCascadeProject(workspaceStore: store) == newer.id)
    }

    /// A single project with no timestamp still resolves — the cascade's
    /// last-resort `sorted.first` must not silently return nil just because
    /// nothing has a `lastActiveAt` yet.
    @Test func resolveCascadeProjectResolvesSingleProjectWithNoTimestamp() {
        let onlyProject = makeProject(name: "Solo")
        let store = WorkspaceStore(testingProjects: [onlyProject], testingSessions: [])
        let composerStore = SessionComposerStore(isolatedForTesting: ())

        #expect(composerStore.resolveCascadeProject(workspaceStore: store) == onlyProject.id)
    }
}

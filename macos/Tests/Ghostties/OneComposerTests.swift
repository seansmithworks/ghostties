import Foundation
import Testing
import GhosttiesCore
@testable import Ghostty

/// There is exactly one composer: the centered single-line overlay. A
/// project row's "+" opens it with that project pre-filled; no anchored
/// popover composer exists to open alongside it.
@MainActor
struct OneComposerTests {

    private func makeProject(name: String, defaultTemplateId: UUID? = nil) -> Project {
        Project(
            name: name,
            rootPath: "/tmp/\(name)-\(UUID().uuidString)",
            defaultTemplateId: defaultTemplateId
        )
    }

    // MARK: - Project row "+" routing

    /// A plain click on a project row's "+" (header plus or the bottom
    /// "New Session" button) yields a request for the centered composer
    /// with THAT project pre-filled — not a locked project, not `.open`.
    @Test func projectRowPlusOpensTheComposerPrefilledWithThatProject() {
        let project = makeProject(name: "Demo")
        let action = ProjectRowNewSession.action(
            for: project,
            optionHeld: false,
            templates: AgentTemplate.defaults
        )
        guard case .openComposer(let binding) = action,
              case .prefilled(let prefilled) = binding else {
            Issue.record("expected .openComposer(.prefilled(project)), got \(action)")
            return
        }
        #expect(prefilled.id == project.id)
    }

    /// A plain click opens the composer even when the project has a default
    /// template — only Option-click takes the instant-create shortcut.
    @Test func projectWithADefaultTemplateStillOpensTheComposerOnAPlainClick() {
        let template = AgentTemplate.defaults[0]
        let project = makeProject(name: "Demo", defaultTemplateId: template.id)
        let action = ProjectRowNewSession.action(for: project, optionHeld: false, templates: AgentTemplate.defaults)
        guard case .openComposer = action else {
            Issue.record("expected .openComposer, got \(action)")
            return
        }
    }

    @Test func optionClickKeepsInstantCreateWhenTheProjectHasADefaultTemplate() {
        let template = AgentTemplate.defaults[0]
        let project = makeProject(name: "Demo", defaultTemplateId: template.id)
        let action = ProjectRowNewSession.action(for: project, optionHeld: true, templates: AgentTemplate.defaults)
        guard case .instantCreate(let created) = action else {
            Issue.record("expected .instantCreate, got \(action)")
            return
        }
        #expect(created.id == template.id)
    }

    /// Option-click on a project with NO default template has nothing to
    /// instant-create, so it opens the composer like a plain click.
    @Test func optionClickWithoutADefaultTemplateOpensTheComposer() {
        let project = makeProject(name: "Demo")
        let action = ProjectRowNewSession.action(for: project, optionHeld: true, templates: AgentTemplate.defaults)
        guard case .openComposer = action else {
            Issue.record("expected .openComposer, got \(action)")
            return
        }
    }

    // MARK: - One composer, never two

    /// A row "+" pressed while the tray's composer is already open does not
    /// stack a second composer: both openers share the one
    /// `SessionComposerStore`, so the open composer is re-targeted to the
    /// row's project (state reset) and re-focused.
    @Test func rowPlusWhileTheComposerIsOpenRetargetsItInsteadOfStacking() {
        let projectA = makeProject(name: "A")
        let projectB = makeProject(name: "B")
        let workspaceStore = WorkspaceStore(testingProjects: [projectA, projectB], testingSessions: [])
        let composerStore = SessionComposerStore(isolatedForTesting: ())

        // Tray "New Session": no project pre-selected.
        composerStore.open(projectBinding: .open, workspaceStore: workspaceStore)
        composerStore.searchText = "half-typed"
        #expect(composerStore.isOpen)

        // Project B's row "+".
        guard case .openComposer(let binding) = ProjectRowNewSession.action(
            for: projectB, optionHeld: false, templates: AgentTemplate.defaults
        ) else {
            Issue.record("expected the row to open the composer")
            return
        }
        composerStore.open(projectBinding: binding, workspaceStore: workspaceStore)

        #expect(composerStore.isOpen)
        #expect(composerStore.selectedProjectId == projectB.id)
        #expect(composerStore.searchText == "")
        #expect(composerStore.focusSearchFieldTrigger == true)
    }
}

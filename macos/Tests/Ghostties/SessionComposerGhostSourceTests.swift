import Testing
import GhosttiesCore
@testable import Ghostty

/// The composer field's ghost source for a highlighted PROJECT row:
/// `SessionComposerPalette.destination(for:)`. Return on a project row
/// opens a Shell at that project's root (Sean, 2026-10-12), so the ghost
/// names exactly that — the field and the list can't disagree about what
/// Return launches. Before that, Return only switched to the project, and
/// this resolved the project's default, recent, or first template instead.
///
/// The `selectedOption`-kind dispatch (`ghostFullPathForField`) stays a
/// `private` computed property on the View;
/// `SessionComposerSnapshotTests.workedExampleGhostsADifferentProjectsFullPath`
/// covers the rendering half against the same `"Brukas > Default > Shell"`.
struct SessionComposerGhostSourceTests {
    @Test func aProjectRowGhostsAShellAtItsRoot() {
        let project = Project(name: "Brukas", rootPath: "/tmp/brukas")
        #expect(SessionComposerPalette.destination(for: project) == "Brukas > Default > Shell")
    }

    /// A project's own default template doesn't change what Return on its
    /// row opens, so it doesn't change the ghost either.
    @Test func aProjectDefaultTemplateDoesNotChangeTheRowsGhost() {
        let project = Project(name: "Brukas", rootPath: "/tmp/brukas", defaultTemplateId: AgentTemplate.claudeCode.id)
        #expect(SessionComposerPalette.destination(for: project) == "Brukas > Default > \(AgentTemplate.shell.name)")
    }
}

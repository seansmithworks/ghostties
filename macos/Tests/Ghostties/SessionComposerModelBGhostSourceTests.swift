import Testing
import GhosttiesCore
@testable import Ghostty

/// Model B's ghost source (Spotlight-inline-completion + Raycast-Tab-drill
/// rewrite): `SessionComposerPalette.destination(for:store:recentSelections:)`
/// is the half of `ghostFullPathForModelB` that resolves a HIGHLIGHTED
/// PROJECT row's own destination — the fix for defect 1 ("ghost welded to
/// the current project"). It's a `static` pure function over explicit
/// `Project`/`WorkspaceStore`/`[RecentComposerSelection]` inputs
/// deliberately, so it's testable without mounting
/// `SessionComposerPalette` (the repo's usual private-computed-property-
/// on-a-View gap, `SessionComposerGhostPlaceholderTests`' own doc comment).
///
/// `ghostFullPathForModelB` itself (the `selectedOption`-kind dispatch —
/// "is the highlighted row a project, a template, or nothing?") stays a
/// `private` computed property on the View, same gap as `ghostPlaceholder`
/// always had; `SessionComposerSnapshotTests.workedExampleGhostsADifferentProjectsFullPath`
/// covers that half by rendering `ComposerGhostTextField` directly against
/// the brief's own worked-example string (`"Brukas > Default > Shell"`) —
/// a literal chosen to match that example exactly for the rendering proof,
/// NOT the live output of `destination(for:)` below, which (correctly)
/// defers to `SessionTemplateResolver`'s real ordering and lands on
/// `Browser` for a vanilla fixture project — see this file's own tests.
@MainActor
struct SessionComposerModelBGhostSourceTests {
    /// `WorkspaceStore(testingProjects:testingSessions:)` always seeds
    /// `templates` with `AgentTemplate.defaults` (`templates` is
    /// `private(set)`, so tests can't substitute a different set without
    /// touching `WorkspaceStore` itself — out of scope here).
    private func makeStore() -> WorkspaceStore {
        WorkspaceStore(testingProjects: [], testingSessions: [])
    }

    /// The worked example: a project with no `defaultTemplateId` and no
    /// recent selection lands on `SessionTemplateResolver.templates(for:
    /// store:)`'s own first entry, with `"Default"` for the branch segment
    /// (deliberately NOT a real git branch — see the function's own doc
    /// comment for why that's out of scope here). That first entry is
    /// `Browser`, not `Shell` — `SessionTemplateResolver` sorts `.preset`
    /// templates ahead of `.builtin` ones, and `AgentTemplate.browser` is
    /// the only one of `AgentTemplate.defaults` carrying a
    /// `templateDescription` (`SessionTemplateResolver.group(for:)`
    /// classifies on that field alone), so it's the one `.preset` among
    /// four `.builtin`s and sorts first even though `AgentTemplate
    /// .defaults`'s own declared order puts `Shell` first. This function
    /// makes no ordering decision of its own — it defers entirely to
    /// `SessionTemplateResolver`, the single source of truth for template
    /// order everywhere else in the composer.
    @Test func projectWithNoDefaultOrRecentLandsOnTheFirstAvailableTemplate() {
        let project = Project(name: "Brukas", rootPath: "/tmp/brukas")
        let store = makeStore()
        let result = SessionComposerPalette.destination(for: project, store: store, recentSelections: [])
        #expect(result == "Brukas > Default > \(AgentTemplate.browser.name)")
    }

    @Test func projectWithADefaultTemplateIdUsesItOverTheFirstAvailable() {
        let project = Project(name: "Brukas", rootPath: "/tmp/brukas", defaultTemplateId: AgentTemplate.claudeCode.id)
        let store = makeStore()
        let result = SessionComposerPalette.destination(for: project, store: store, recentSelections: [])
        #expect(result == "Brukas > Default > \(AgentTemplate.claudeCode.name)")
    }

    /// No `defaultTemplateId`, but a recent selection for THIS project
    /// exists — recency wins over the plain first-available fallback.
    @Test func projectWithARecentSelectionUsesItOverTheFirstAvailable() {
        let project = Project(name: "Brukas", rootPath: "/tmp/brukas")
        let store = makeStore()
        let recents = [RecentComposerSelection(projectId: project.id, templateId: AgentTemplate.orchestrator.id)]
        let result = SessionComposerPalette.destination(for: project, store: store, recentSelections: recents)
        #expect(result == "Brukas > Default > \(AgentTemplate.orchestrator.name)")
    }

    /// A recent selection for a DIFFERENT project must not leak in —
    /// proves the `projectId` filter is load-bearing, not decorative.
    @Test func aRecentSelectionForAnotherProjectIsIgnored() {
        let project = Project(name: "Brukas", rootPath: "/tmp/brukas")
        let otherProjectId = Project(name: "Ghostties", rootPath: "/tmp/ghostties").id
        let store = makeStore()
        let recents = [RecentComposerSelection(projectId: otherProjectId, templateId: AgentTemplate.orchestrator.id)]
        let result = SessionComposerPalette.destination(for: project, store: store, recentSelections: recents)
        #expect(result == "Brukas > Default > \(AgentTemplate.browser.name)")
    }
}

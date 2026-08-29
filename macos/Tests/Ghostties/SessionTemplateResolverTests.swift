import XCTest
import GhosttiesCore
@testable import Ghostty

/// Tests for `SessionTemplateResolver` — the single template scoping +
/// ordering implementation that replaced `RecentsListView.availableTemplates`
/// and the three computed properties on `TemplatePickerView`.
@MainActor
final class SessionTemplateResolverTests: XCTestCase {

    // MARK: - group(for:)

    func testGroupClassifiesNonDefaultAsUser() {
        let template = AgentTemplate(name: "Mine", kind: .custom, isDefault: false)
        XCTAssertEqual(SessionTemplateResolver.group(for: template), .user)
    }

    func testGroupClassifiesNonDefaultAsUserEvenWithADescription() {
        // isDefault is switched on FIRST — a non-default template is always
        // `.user`, regardless of templateDescription.
        let template = AgentTemplate(name: "Mine", kind: .custom, isDefault: false, templateDescription: "desc")
        XCTAssertEqual(SessionTemplateResolver.group(for: template), .user)
    }

    func testGroupClassifiesDefaultWithDescriptionAsPreset() {
        let template = AgentTemplate(name: "Preset", kind: .custom, isDefault: true, templateDescription: "A preset")
        XCTAssertEqual(SessionTemplateResolver.group(for: template), .preset)
    }

    func testGroupClassifiesDefaultWithoutDescriptionAsBuiltin() {
        let template = AgentTemplate(name: "Shell", kind: .shell, isDefault: true)
        XCTAssertEqual(SessionTemplateResolver.group(for: template), .builtin)
    }

    // MARK: - templates(for:store:) — fixture

    /// Two projects sharing one store, seeded with the 5 built-in defaults
    /// (all global) plus a mixed set of global/scoped custom templates.
    private struct Fixture {
        let store: WorkspaceStore
        let projectA: Project
        let projectB: Project
        let scopedToA: AgentTemplate
        let globalUser1: AgentTemplate
        let globalUser2: AgentTemplate
        let globalPreset: AgentTemplate
    }

    private func makeFixture() -> Fixture {
        let projectA = Project(name: "A", rootPath: "/a")
        let projectB = Project(name: "B", rootPath: "/b")
        let store = WorkspaceStore(testingProjects: [projectA, projectB])

        // A project-scoped template — must appear only in projectA's list.
        let scopedToA = store.addTemplate(
            AgentTemplate(name: "ScopedToA", kind: .custom, isGlobal: false, projectId: projectA.id)
        )

        // Two global user templates, added in this order to verify
        // insertion order is preserved within the `.user` group.
        let globalUser1 = store.addTemplate(AgentTemplate(name: "GlobalUserFirst", kind: .custom, isGlobal: true))
        let globalUser2 = store.addTemplate(AgentTemplate(name: "GlobalUserSecond", kind: .custom, isGlobal: true))

        // A global default-with-description template — classifies as
        // `.preset` and must sort ahead of the built-in defaults.
        let globalPreset = store.addTemplate(
            AgentTemplate(
                name: "GlobalPreset",
                kind: .custom,
                isDefault: true,
                isGlobal: true,
                templateDescription: "A fixture preset"
            )
        )

        return Fixture(
            store: store,
            projectA: projectA,
            projectB: projectB,
            scopedToA: scopedToA,
            globalUser1: globalUser1,
            globalUser2: globalUser2,
            globalPreset: globalPreset
        )
    }

    /// D5 regression guard: a project-scoped template appears in exactly one
    /// project's list.
    func testProjectScopedTemplateAppearsInOnlyItsOwnProject() {
        let fixture = makeFixture()

        let listA = SessionTemplateResolver.templates(for: fixture.projectA, store: fixture.store)
        let listB = SessionTemplateResolver.templates(for: fixture.projectB, store: fixture.store)

        XCTAssertTrue(listA.contains { $0.id == fixture.scopedToA.id })
        XCTAssertFalse(listB.contains { $0.id == fixture.scopedToA.id })
    }

    func testGlobalTemplatesAppearInEveryProject() {
        let fixture = makeFixture()

        let listA = SessionTemplateResolver.templates(for: fixture.projectA, store: fixture.store)
        let listB = SessionTemplateResolver.templates(for: fixture.projectB, store: fixture.store)

        for global in [fixture.globalUser1, fixture.globalUser2, fixture.globalPreset] {
            XCTAssertTrue(listA.contains { $0.id == global.id })
            XCTAssertTrue(listB.contains { $0.id == global.id })
        }
    }

    func testDefaultTemplateIdIsAtIndexZero() {
        let fixture = makeFixture()
        fixture.store.updateProject(id: fixture.projectA.id, defaultTemplateId: fixture.globalUser2.id)
        let updatedProjectA = fixture.store.projects.first { $0.id == fixture.projectA.id }!

        let list = SessionTemplateResolver.templates(for: updatedProjectA, store: fixture.store)

        XCTAssertEqual(list.first?.id, fixture.globalUser2.id)
    }

    /// D6 regression guard: this is the test that genuinely fails against the
    /// old implementation. The fixture appends `GlobalPreset` after the user
    /// templates (see `makeFixture()`), so a non-grouping implementation
    /// surfaces a preset after a builtin — this assertion catches that.
    /// `testOrderingIsDeterministicAcrossRepeatedCalls` below does not: at
    /// this fixture size the old predicate is deterministic in practice
    /// (Swift's sort insertion-sorts short runs), so it passes
    /// against both implementations.
    func testGroupOrderIsPresetThenBuiltinThenUser() {
        let fixture = makeFixture()

        let list = SessionTemplateResolver.templates(for: fixture.projectA, store: fixture.store)
        let groups = list.map { SessionTemplateResolver.group(for: $0) }

        // No `.user` entry appears before any `.preset` or `.builtin` entry,
        // and no `.builtin` entry appears before any `.preset` entry.
        var sawBuiltin = false
        var sawUser = false
        for group in groups {
            switch group {
            case .preset:
                XCTAssertFalse(sawBuiltin, "preset found after a builtin")
                XCTAssertFalse(sawUser, "preset found after a user template")
            case .builtin:
                XCTAssertFalse(sawUser, "builtin found after a user template")
                sawBuiltin = true
            case .user:
                sawUser = true
            }
        }
    }

    func testInsertionOrderIsPreservedWithinAGroup() {
        let fixture = makeFixture()

        let list = SessionTemplateResolver.templates(for: fixture.projectA, store: fixture.store)
        let userNames = list
            .filter { SessionTemplateResolver.group(for: $0) == .user }
            .map(\.name)

        // Added in this order: ScopedToA, GlobalUserFirst, GlobalUserSecond.
        XCTAssertEqual(userNames, ["ScopedToA", "GlobalUserFirst", "GlobalUserSecond"])
    }

    /// Call-stability guard, NOT the D6 regression guard (that is
    /// `testGroupOrderIsPresetThenBuiltinThenUser` above). With more than two
    /// candidates, repeated calls must return the identical order every time.
    /// The predicate this replaces (`candidates.sorted { a, _ in a.id ==
    /// defaultId }`) is not a strict weak ordering, so `sorted` was free to
    /// permute everything past "the default sorts early" differently across
    /// calls — but at this fixture size Swift's sort insertion-sorts short
    /// runs, which happens to be deterministic anyway, so this
    /// test passes against both the old and new implementations.
    func testOrderingIsDeterministicAcrossRepeatedCalls() {
        let fixture = makeFixture()
        fixture.store.updateProject(id: fixture.projectA.id, defaultTemplateId: fixture.globalUser2.id)
        let updatedProjectA = fixture.store.projects.first { $0.id == fixture.projectA.id }!

        let first = SessionTemplateResolver.templates(for: updatedProjectA, store: fixture.store).map(\.id)
        for _ in 0..<10 {
            let next = SessionTemplateResolver.templates(for: updatedProjectA, store: fixture.store).map(\.id)
            XCTAssertEqual(first, next)
        }
    }

    // MARK: - WorkspaceStore.addTemplate dedupe-on-write

    func testAddTemplateDedupesExactNameCollision() {
        let store = WorkspaceStore(testingProjects: [])

        let first = store.addTemplate(AgentTemplate(name: "X", kind: .custom))
        let second = store.addTemplate(AgentTemplate(name: "X", kind: .custom))

        XCTAssertEqual(first.name, "X")
        XCTAssertEqual(second.name, "X 2")
    }
}

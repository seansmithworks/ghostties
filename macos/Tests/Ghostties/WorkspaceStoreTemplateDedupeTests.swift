// IDE-ONLY: not currently exercised in CI macos job (build-only).
// Run via Xcode Cmd+U or xcodebuild test locally.
// See .github/workflows/test-ghostties.yml — macos-app job is build-only due to
// XCTest host app hang in headless GH Actions runners.
import XCTest
import GhosttiesCore
@testable import Ghostty

/// Tests for `WorkspaceStore`'s name-uniqueness invariant across all three
/// template write paths (`addTemplate`, `updateTemplate`, `duplicateTemplate`).
/// Phase 1 review found the dedupe covered only `addTemplate` — a subsequent
/// `updateTemplate` (e.g. correcting a name back after dedupe renamed it) or
/// `duplicateTemplate` could still produce two templates sharing a name.
@MainActor
final class WorkspaceStoreTemplateDedupeTests: XCTestCase {

    private func makeStore() -> WorkspaceStore {
        WorkspaceStore(testingProjects: [])
    }

    private func makeTemplate(name: String) -> AgentTemplate {
        AgentTemplate(name: name, kind: .shell)
    }

    /// Adding "X" three times in a row must yield "X", "X 2", "X 3" — the
    /// existing `addTemplate` dedupe behavior, now routed through `uniqueName`.
    func testAddTemplate_repeatedName_appendsIncrementingSuffix() {
        let store = makeStore()

        let first = store.addTemplate(makeTemplate(name: "X"))
        let second = store.addTemplate(makeTemplate(name: "X"))
        let third = store.addTemplate(makeTemplate(name: "X"))

        XCTAssertEqual(first.name, "X")
        XCTAssertEqual(second.name, "X 2")
        XCTAssertEqual(third.name, "X 3")
    }

    /// Renaming an unrelated template to a name already in use must dedupe
    /// exactly like `addTemplate` — the collision check is not add-only.
    func testUpdateTemplate_renameToExistingName_appendsSuffix() {
        let store = makeStore()

        store.addTemplate(makeTemplate(name: "X"))
        store.addTemplate(makeTemplate(name: "X 2"))
        store.addTemplate(makeTemplate(name: "X 3"))
        let other = store.addTemplate(makeTemplate(name: "Other"))

        store.updateTemplate(id: other.id, name: "X")

        guard let updated = store.templates.first(where: { $0.id == other.id }) else {
            return XCTFail("updated template missing")
        }
        XCTAssertEqual(updated.name, "X 4", "must dedupe against all three existing X templates, not collide")
        XCTAssertEqual(store.templates.filter { $0.name == "X" }.count, 1, "the original X must remain the only X")
    }

    /// Renaming a template to the name it already holds is a no-op rename,
    /// not a self-collision — the `excluding:` guard must prevent it from
    /// becoming "X 2".
    func testUpdateTemplate_renameToOwnCurrentName_isUnchanged() {
        let store = makeStore()

        let template = store.addTemplate(makeTemplate(name: "X"))

        store.updateTemplate(id: template.id, name: "X")

        guard let updated = store.templates.first(where: { $0.id == template.id }) else {
            return XCTFail("updated template missing")
        }
        XCTAssertEqual(updated.name, "X", "renaming to the same name must not append a suffix")
    }
}

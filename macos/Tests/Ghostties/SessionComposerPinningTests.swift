import Foundation
import Testing
@testable import Ghostty

/// Coverage for the composer's pinned-template data layer (Composer UI 11,
/// Step 1) — `SessionComposerStore.togglePin(templateId:)` and
/// `prunePins(validIds:)`. Mirrors `SessionComposerBreadcrumbChipTests`'
/// pattern: `SessionComposerStore(isolatedForTesting: ())` against a private
/// `UserDefaults` suite, no singleton side effects, no real recents/pins
/// touched.
@MainActor
struct SessionComposerPinningTests {

    private func makeProject(name: String = "Proj") -> Project {
        Project(name: name, rootPath: "/tmp/\(name)-\(UUID().uuidString)")
    }

    // MARK: - Toggle round-trip

    /// Pinning an unpinned id adds it; pinning it again (the toggle) removes
    /// it. Names the real production symbol (`togglePin`/`pinnedTemplateIds`),
    /// not a re-declared local constant.
    @Test func togglePinRoundTrips() {
        let store = SessionComposerStore(isolatedForTesting: ())
        let templateId = UUID()

        #expect(!store.pinnedTemplateIds.contains(templateId))

        store.togglePin(templateId: templateId)
        #expect(store.pinnedTemplateIds.contains(templateId))

        store.togglePin(templateId: templateId)
        #expect(!store.pinnedTemplateIds.contains(templateId))
    }

    // MARK: - Persistence across store re-init

    /// The pin key is UserDefaults-backed (mirroring `recentProjectIds`), so
    /// a genuinely FRESH `SessionComposerStore` instance pointed at the SAME
    /// isolated `UserDefaults` suite as a prior instance must read back what
    /// that prior instance wrote — proof this is durable persisted state,
    /// not an in-memory property that happens to survive only because it's
    /// the same object.
    @Test func pinPersistsAcrossStoreReinitOnTheSameDefaultsSuite() {
        let suiteName = "ghostties.sessionComposerStore.test.\(UUID().uuidString)"
        let templateId = UUID()

        let firstInstance = SessionComposerStore(isolatedForTesting: suiteName)
        firstInstance.togglePin(templateId: templateId)

        let secondInstance = SessionComposerStore(isolatedForTesting: suiteName)
        #expect(secondInstance.pinnedTemplateIds == [templateId])
    }

    // MARK: - Prune drops an orphan

    @Test func prunePinsDropsAnOrphanedId() {
        let store = SessionComposerStore(isolatedForTesting: ())
        let validId = UUID()
        let orphanId = UUID()
        store.togglePin(templateId: validId)
        store.togglePin(templateId: orphanId)
        #expect(store.pinnedTemplateIds == [orphanId, validId])

        store.prunePins(validIds: [validId])

        #expect(store.pinnedTemplateIds == [validId])
    }

    /// `prunePins` runs from `open()` — proves the real call site actually
    /// invokes it (not just the pure function in isolation), against a
    /// project's real template set.
    @Test func openPrunesOrphanedPins() {
        let store = SessionComposerStore(isolatedForTesting: ())
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let validId = workspaceStore.templates.first!.id
        let orphanId = UUID()
        store.togglePin(templateId: validId)
        store.togglePin(templateId: orphanId)

        store.open(projectBinding: .locked(project), workspaceStore: workspaceStore)

        #expect(store.pinnedTemplateIds == [validId])
    }

    // MARK: - Pin order is most-recently-pinned-first

    @Test func pinOrderIsMostRecentlyPinnedFirst() {
        let store = SessionComposerStore(isolatedForTesting: ())
        let first = UUID()
        let second = UUID()
        let third = UUID()

        store.togglePin(templateId: first)
        store.togglePin(templateId: second)
        store.togglePin(templateId: third)

        #expect(store.pinnedTemplateIds == [third, second, first])
    }
}

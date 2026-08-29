import Foundation
import Testing
import GhosttiesCore
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

        // Defect 5 fix (review round 2): restored to its original,
        // pre-plausibility-floor form — a `validIds` universe SMALLER than
        // the persisted pin count (1 valid id against 2 pins) must still
        // drop the genuine orphan. The count-comparison floor this test was
        // weakened to accommodate (`[validId, UUID()]`, count 2) is gone —
        // see `prunePins`'s doc comment for why it blocked pruning forever
        // for a user who genuinely deletes down to fewer templates than
        // they have pins.
        store.prunePins(validIds: [validId], presetsLoadSucceeded: true)

        #expect(store.pinnedTemplateIds == [validId])
    }

    // MARK: - Load-success gate (defect 5 fix): soft-failed loads must not wipe pins

    /// `PresetLoader.loadPresetsResult()`'s soft-fail paths report
    /// `loadSucceeded: false` — this proves `prunePins` skips pruning
    /// entirely on that signal, rather than treating an incidentally empty
    /// `validIds` as "every pin is now orphaned" and wiping the persisted
    /// set. Names the real production symbol (`prunePins`'s
    /// `presetsLoadSucceeded` parameter) — fails under a mutation that
    /// removes the gate (see report).
    @Test func prunePinsSkipsOnPresetsLoadFailure() {
        let store = SessionComposerStore(isolatedForTesting: ())
        let first = UUID()
        let second = UUID()
        store.togglePin(templateId: first)
        store.togglePin(templateId: second)

        // Even an empty `validIds` (which now, absent the load-failure
        // signal, WOULD prune everything — see the sibling test below) must
        // not prune when the load itself is known to have failed.
        store.prunePins(validIds: [], presetsLoadSucceeded: false)

        #expect(store.pinnedTemplateIds == [second, first])
    }

    /// Defect 5's actual failure mode, proven fixed: a `validIds` universe
    /// SMALLER than the persisted pin count — the exact shape a user
    /// genuinely deleting templates down below their pin count produces —
    /// still prunes correctly once the load is known to have succeeded.
    /// The old count-comparison floor blocked this scenario FOREVER (the
    /// id universe could never grow back to the pin count without adding
    /// templates); this proves it no longer does.
    @Test func prunePinsDropsOrphansEvenWhenValidIdsIsSmallerThanPinCount() {
        let store = SessionComposerStore(isolatedForTesting: ())
        let first = UUID()
        let second = UUID()
        let third = UUID()
        store.togglePin(templateId: first)
        store.togglePin(templateId: second)
        store.togglePin(templateId: third)

        // Only one valid id against three persisted pins, load succeeded.
        store.prunePins(validIds: [first], presetsLoadSucceeded: true)

        #expect(store.pinnedTemplateIds == [first])
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

import XCTest
import GhosttiesCore
@testable import Ghostty

/// Dragging a project group in the one-view list: the store move and its
/// persistence, the pure drop geometry, and the rail following the same
/// order. The persistence test injects its state directory
/// (`WorkspaceStore(testingStateDirectory:)`); nothing here sets
/// `GHOSTTIES_STATE_DIR`.
@MainActor
final class ProjectReorderTests: XCTestCase {
    private let atlas = Project(name: "atlas-api", rootPath: "/tmp/ghostties-reorder/atlas-api")
    private let fieldwork = Project(name: "fieldwork", rootPath: "/tmp/ghostties-reorder/fieldwork")
    private let orbit = Project(name: "orbit-web", rootPath: "/tmp/ghostties-reorder/orbit-web")
    private let quiet = Project(name: "quiet", rootPath: "/tmp/ghostties-reorder/quiet")

    private func session(_ name: String, _ project: Project, pinned: Bool = false) -> AgentSession {
        AgentSession(name: name, templateId: UUID(), projectId: project.id, isPinned: pinned)
    }

    // MARK: - Store

    func testMoveProjectInsertsBeforeTargetOrAtEnd() {
        let store = WorkspaceStore(testingProjects: [atlas, fieldwork, orbit, quiet])

        // Down: before a later project resolves after removal.
        store.moveProject(id: atlas.id, before: orbit.id)
        XCTAssertEqual(store.projects.map(\.name), ["fieldwork", "atlas-api", "orbit-web", "quiet"])

        // Up.
        store.moveProject(id: quiet.id, before: fieldwork.id)
        XCTAssertEqual(store.projects.map(\.name), ["quiet", "fieldwork", "atlas-api", "orbit-web"])

        // Nil and an unknown target both mean last.
        store.moveProject(id: quiet.id, before: nil)
        XCTAssertEqual(store.projects.map(\.name), ["fieldwork", "atlas-api", "orbit-web", "quiet"])
        store.moveProject(id: fieldwork.id, before: UUID())
        XCTAssertEqual(store.projects.map(\.name), ["atlas-api", "orbit-web", "quiet", "fieldwork"])

        // Before itself, or an unknown project, changes nothing.
        store.moveProject(id: orbit.id, before: orbit.id)
        store.moveProject(id: UUID(), before: atlas.id)
        XCTAssertEqual(store.projects.map(\.name), ["atlas-api", "orbit-web", "quiet", "fieldwork"])
    }

    /// A reorder keeps every project's pin, and a pinned project leads the
    /// one-view groups wherever it sits in the array.
    func testMoveProjectKeepsPinsAndDrivesGroupOrder() {
        var pinnedOrbit = orbit
        pinnedOrbit.isPinned = true
        let store = WorkspaceStore(testingProjects: [atlas, fieldwork, pinnedOrbit])
        store.moveProject(id: pinnedOrbit.id, before: nil)
        store.moveProject(id: atlas.id, before: nil)

        XCTAssertEqual(store.projects.map(\.isPinned), [false, false, true])
        XCTAssertEqual(SidebarProjectGroup.make(active: [], projects: store.projects).map(\.name), ["orbit-web", "fieldwork", "atlas-api"])
    }

    // MARK: - Pin

    private func names(_ store: WorkspaceStore) -> [String] {
        SidebarProjectGroup.make(active: [], projects: store.projects).map(\.name)
    }

    /// Pin puts a project at the top of the list and the rail, pinned ones
    /// keep their own relative order, and Unpin returns a project to its
    /// place in the manual order.
    func testPinnedProjectsLeadTheListAndRailAndUnpinRestoresOrder() {
        let sessions = [session("a1", atlas), session("f1", fieldwork), session("o1", orbit), session("q1", quiet)]
        let store = WorkspaceStore(testingProjects: [atlas, fieldwork, orbit, quiet], testingSessions: sessions)
        for s in sessions { store.updateSessionStatus(id: s.id, status: .running) }
        XCTAssertEqual(names(store), ["atlas-api", "fieldwork", "orbit-web", "quiet"])

        store.togglePin(id: quiet.id)
        XCTAssertEqual(names(store), ["quiet", "atlas-api", "fieldwork", "orbit-web"])

        // Pinned later but earlier in the manual order: fieldwork leads.
        store.togglePin(id: fieldwork.id)
        XCTAssertEqual(names(store), ["fieldwork", "quiet", "atlas-api", "orbit-web"])
        XCTAssertEqual(store.railSessions(layout: .oneView).map(\.name), ["f1", "q1", "a1", "o1"])

        store.togglePin(id: fieldwork.id)
        XCTAssertEqual(names(store), ["quiet", "atlas-api", "fieldwork", "orbit-web"])
        XCTAssertEqual(store.railSessions(layout: .oneView).map(\.name), ["q1", "a1", "f1", "o1"])

        store.togglePin(id: quiet.id)
        XCTAssertEqual(names(store), ["atlas-api", "fieldwork", "orbit-web", "quiet"])
    }

    /// A move stays inside its pin group: a target across the boundary (or
    /// none) lands the project at its own group's near edge, and the other
    /// group never moves.
    func testMoveProjectStaysInsideItsPinGroup() {
        var pinnedAtlas = atlas
        pinnedAtlas.isPinned = true
        var pinnedOrbit = orbit
        pinnedOrbit.isPinned = true
        let store = WorkspaceStore(testingProjects: [pinnedAtlas, fieldwork, pinnedOrbit, quiet])
        XCTAssertEqual(names(store), ["atlas-api", "orbit-web", "fieldwork", "quiet"])

        // Within Pinned.
        store.moveProject(id: pinnedOrbit.id, before: pinnedAtlas.id)
        XCTAssertEqual(names(store), ["orbit-web", "atlas-api", "fieldwork", "quiet"])

        // Pinned dropped among the rest, or at the very end: end of Pinned.
        store.moveProject(id: pinnedOrbit.id, before: quiet.id)
        XCTAssertEqual(names(store), ["atlas-api", "orbit-web", "fieldwork", "quiet"])
        store.moveProject(id: pinnedAtlas.id, before: nil)
        XCTAssertEqual(names(store), ["orbit-web", "atlas-api", "fieldwork", "quiet"])

        // Unpinned dropped above a pinned project: top of the rest.
        store.moveProject(id: quiet.id, before: pinnedOrbit.id)
        XCTAssertEqual(names(store), ["orbit-web", "atlas-api", "quiet", "fieldwork"])

        // Within the rest, to the end.
        store.moveProject(id: quiet.id, before: nil)
        XCTAssertEqual(names(store), ["orbit-web", "atlas-api", "fieldwork", "quiet"])
        XCTAssertEqual(store.projects.map(\.isPinned), [true, false, true, false])
    }

    /// The drag gap stays inside the dragged project's pin group, counted
    /// with the dragged project removed.
    func testAllowedGapsKeepADragInsideItsPinGroup() {
        var pinnedAtlas = atlas
        pinnedAtlas.isPinned = true
        var pinnedOrbit = orbit
        pinnedOrbit.isPinned = true
        let order = ProjectListOrder.pinnedFirst([pinnedAtlas, fieldwork, pinnedOrbit, quiet])
        XCTAssertEqual(order.map(\.name), ["atlas-api", "orbit-web", "fieldwork", "quiet"])
        XCTAssertEqual(ProjectDragReflow.allowedGaps(order: order, dragged: pinnedAtlas.id), 0...1)
        XCTAssertEqual(ProjectDragReflow.allowedGaps(order: order, dragged: fieldwork.id), 2...3)
        // No pins: the whole list.
        XCTAssertEqual(ProjectDragReflow.allowedGaps(order: [atlas, fieldwork, orbit], dragged: atlas.id), 0...2)
    }

    /// Pin goes through the real `persist()` into an injected temp dir and
    /// a fresh store loaded from it comes back pinned, at the top.
    func testPinPersistsAndRoundTrips() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectReorderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        WorkspacePersistence.save(WorkspacePersistence.State(projects: [atlas, fieldwork, orbit]), to: dir)
        let store = WorkspaceStore(testingStateDirectory: dir)
        store.togglePin(id: orbit.id)
        await store.flushPersistenceForTesting()

        let reloaded = WorkspaceStore(testingStateDirectory: dir)
        XCTAssertEqual(reloaded.projects.map(\.isPinned), [false, false, true])
        XCTAssertEqual(names(reloaded), ["orbit-web", "atlas-api", "fieldwork"])
    }

    /// The move goes through the real `persist()` into an injected temp dir,
    /// the encoded file carries the new order, and a fresh store loaded from
    /// that dir comes back in it.
    func testMoveProjectPersistsAndRoundTrips() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectReorderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        WorkspacePersistence.save(WorkspacePersistence.State(projects: [atlas, fieldwork, orbit]), to: dir)
        let store = WorkspaceStore(testingStateDirectory: dir)
        XCTAssertEqual(store.projects.map(\.name), ["atlas-api", "fieldwork", "orbit-web"])

        store.moveProject(id: orbit.id, before: atlas.id)
        await store.flushPersistenceForTesting()

        let data = try Data(contentsOf: dir.appendingPathComponent("workspace.json"))
        let decoded = try JSONDecoder().decode(WorkspacePersistence.State.self, from: data)
        XCTAssertEqual(decoded.projects.map(\.id), [orbit.id, atlas.id, fieldwork.id])

        let reloaded = WorkspaceStore(testingStateDirectory: dir)
        XCTAssertEqual(reloaded.projects.map(\.name), ["orbit-web", "atlas-api", "fieldwork"])
    }

    // MARK: - Drop geometry

    func testHeaderOnlyGroupSplitsAtItsMidpoint() {
        XCTAssertEqual(ProjectDragReflow.insertionIndex(hoveredIndex: 2, slot: 0, slotCount: 1, fraction: 0.2), 2)
        XCTAssertEqual(ProjectDragReflow.insertionIndex(hoveredIndex: 2, slot: 0, slotCount: 1, fraction: 0.8), 3)
        // Out-of-range pointer y clamps to the slot's edges.
        XCTAssertEqual(ProjectDragReflow.insertionIndex(hoveredIndex: 0, slot: 0, slotCount: 1, fraction: -4), 0)
        XCTAssertEqual(ProjectDragReflow.insertionIndex(hoveredIndex: 0, slot: 0, slotCount: 1, fraction: 9), 1)
    }

    /// An expanded group with three rows has four slots: the top half
    /// (header and first row) lands before it, the bottom half after it.
    func testExpandedGroupSplitsAcrossItsHeaderAndRows() {
        let before = [(0, 0.1), (0, 0.9), (1, 0.4)]
        let after = [(2, 0.0), (2, 0.6), (3, 0.99)]
        for (slot, fraction) in before {
            XCTAssertEqual(ProjectDragReflow.insertionIndex(hoveredIndex: 1, slot: slot, slotCount: 4, fraction: fraction), 1, "slot \(slot) @ \(fraction)")
        }
        for (slot, fraction) in after {
            XCTAssertEqual(ProjectDragReflow.insertionIndex(hoveredIndex: 1, slot: slot, slotCount: 4, fraction: fraction), 2, "slot \(slot) @ \(fraction)")
        }
    }

    func testBeforeIdCountsWithTheDraggedProjectRemoved() {
        let order = [atlas.id, fieldwork.id, orbit.id, quiet.id]
        // Dragging atlas: the rendered list is [fieldwork, orbit, quiet].
        XCTAssertEqual(ProjectDragReflow.beforeId(gapIndex: 0, order: order, dragged: atlas.id), fieldwork.id)
        XCTAssertEqual(ProjectDragReflow.beforeId(gapIndex: 2, order: order, dragged: atlas.id), quiet.id)
        XCTAssertNil(ProjectDragReflow.beforeId(gapIndex: 3, order: order, dragged: atlas.id))
    }

    /// Slots per header and row, counted per group with the dragged group
    /// gone; folded and empty groups are header-only; the "Unknown" group
    /// gets none, so it never takes a project drop.
    func testSlotsIndexRenderedGroupsAndSkipUnknown() throws {
        let a1 = session("a1", atlas)
        let a2 = session("a2", atlas)
        let o1 = session("o1", orbit)
        let f1 = session("f1", fieldwork)
        let orphan = AgentSession(name: "lost", templateId: UUID(), projectId: UUID())
        let all = SidebarProjectGroup.make(active: [a1, a2, o1, f1, orphan], projects: [atlas, fieldwork, orbit, quiet])
        // fieldwork is in flight.
        let groups = all.filter { $0.projectId != fieldwork.id }
        let items = SidebarProjectGroupItem.items(groups, collapsed: [orbit.id])
        let slots = ProjectDragReflow.slots(groups: groups, items: items)

        let atlasHeader = try XCTUnwrap(slots["header-\(atlas.id.uuidString)"])
        XCTAssertEqual([atlasHeader.groupIndex, atlasHeader.slot, atlasHeader.slotCount], [0, 0, 3])
        XCTAssertEqual(atlasHeader.height, ProjectAccordionHeader.height(.sidebar))
        let a2Slot = try XCTUnwrap(slots[a2.id.uuidString])
        XCTAssertEqual([a2Slot.groupIndex, a2Slot.slot, a2Slot.slotCount], [0, 2, 3])
        XCTAssertEqual(a2Slot.height, SessionDragReflow.rowHeight)

        let orbitHeader = try XCTUnwrap(slots["header-\(orbit.id.uuidString)"])
        XCTAssertEqual([orbitHeader.groupIndex, orbitHeader.slotCount], [1, 1])
        let quietHeader = try XCTUnwrap(slots["header-\(quiet.id.uuidString)"])
        XCTAssertEqual([quietHeader.groupIndex, quietHeader.slotCount], [2, 1])

        XCTAssertNil(slots["header-unknown-project"])
        XCTAssertNil(slots[orphan.id.uuidString])
        XCTAssertNil(slots[o1.id.uuidString], "a folded group renders no rows")
    }

    func testDragStateCancelClearsBoth() {
        var state = ProjectDragState(draggingProjectId: atlas.id, gapIndex: 2)
        XCTAssertTrue(state.isDragging)
        state.cancel()
        XCTAssertEqual(state, ProjectDragState())
        XCTAssertFalse(state.isDragging)
    }

    // MARK: - Rail

    /// The rail's tiles and glyphs read the same `store.projects` order as
    /// the expanded list, so a reorder moves both.
    func testRailFollowsTheExpandedOrderAfterAReorder() {
        let pinned = session("orchestrator", orbit, pinned: true)
        let a1 = session("a1", atlas)
        let f1 = session("f1", fieldwork)
        let o1 = session("o1", orbit)
        let all = [pinned, a1, f1, o1]
        let store = WorkspaceStore(testingProjects: [atlas, fieldwork, orbit, quiet], testingSessions: all)
        for s in all { store.updateSessionStatus(id: s.id, status: .running) }

        store.moveProject(id: orbit.id, before: atlas.id)
        store.moveProject(id: quiet.id, before: atlas.id)

        let active = RecentsListView.activeSessions(from: store.sessions, statuses: store.globalStatuses, pinningAvailable: true)
        let expanded = SidebarProjectGroup.make(active: active, projects: store.projects)
        XCTAssertEqual(expanded.map(\.name), ["orbit-web", "quiet", "atlas-api", "fieldwork"])
        XCTAssertEqual(
            store.railSessions(layout: .oneView, pinningAvailable: true).map(\.name),
            ["orchestrator"] + expanded.flatMap(\.sessions).map(\.name)
        )
        XCTAssertEqual(store.railSessions(layout: .oneView, pinningAvailable: true).map(\.name), ["orchestrator", "o1", "a1", "f1"])
    }

    // MARK: - Capture hook

    func testCaptureProjectOrderParses() {
        XCTAssertEqual(CaptureFixture.projectOrder(" wren, switchboard ,,atlas-api"), ["wren", "switchboard", "atlas-api"])
        XCTAssertEqual(CaptureFixture.projectOrder(nil), [])
    }
}

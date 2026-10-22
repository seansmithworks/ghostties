import XCTest
import SwiftUI
import GhosttiesCore
@testable import Ghostty

/// Sidebar project order, mild2wild 2026-10-21 card 01 "Spacing only":
/// pinned projects first in their manual order, then every other project
/// sorted by name, with a 16pt gap between the two blocks that is the same
/// height in the rail and the pinned sidebar. Stores here are
/// persistence-disabled (`WorkspaceStore(testingProjects:)`); nothing sets
/// `GHOSTTIES_STATE_DIR`.
@MainActor
final class ProjectPinnedAlphaOrderTests: XCTestCase {
    private func project(_ name: String, pinned: Bool = false) -> Project {
        Project(name: name, rootPath: "/tmp/ghostties-pinned-alpha/\(name)", isPinned: pinned)
    }

    // MARK: - Order

    /// The unpinned block reads alphabetically (case-insensitive, numbers
    /// in numeric order) whatever order `workspace.json` holds, and the
    /// array itself is left alone.
    func testUnpinnedProjectsSortAlphabeticallyWhateverTheArrayOrder() {
        let projects = [
            project("kiln"), project("switchboard", pinned: true), project("harbor"), project("Beacon"),
            project("item10"), project("atlas-api", pinned: true), project("meridian"), project("item9"),
        ]
        XCTAssertEqual(ProjectListOrder.pinnedFirst(projects).map(\.name), [
            "switchboard", "atlas-api",
            "Beacon", "harbor", "item9", "item10", "kiln", "meridian",
        ])

        let store = WorkspaceStore(testingProjects: projects)
        XCTAssertEqual(SidebarProjectGroup.make(active: [], projects: store.projects).map(\.name), [
            "switchboard", "atlas-api",
            "Beacon", "harbor", "item9", "item10", "kiln", "meridian",
        ])
        XCTAssertEqual(store.projects.map(\.name), projects.map(\.name), "display order never rewrites the array")
    }

    /// Two unpinned projects with the same name keep their array order.
    func testEqualNamesKeepTheirArrayOrder() {
        let first = project("app")
        let second = project("App")
        let zed = project("zed")
        XCTAssertEqual(ProjectListOrder.pinnedFirst([zed, first, second]).map(\.id), [first.id, second.id, zed.id])
        XCTAssertEqual(ProjectListOrder.pinnedFirst([zed, second, first]).map(\.id), [second.id, first.id, zed.id])
    }

    /// Pinned projects keep their manual order, which a pinned drag still
    /// changes.
    func testPinnedProjectsKeepTheirManualOrder() {
        let zeta = project("zeta", pinned: true)
        let alpha = project("alpha", pinned: true)
        let store = WorkspaceStore(testingProjects: [project("mid"), zeta, alpha])
        XCTAssertEqual(SidebarProjectGroup.make(active: [], projects: store.projects).map(\.name), ["zeta", "alpha", "mid"])

        store.moveProject(id: alpha.id, before: zeta.id)
        XCTAssertEqual(SidebarProjectGroup.make(active: [], projects: store.projects).map(\.name), ["alpha", "zeta", "mid"])
    }

    /// Only a pinned project's header drags or takes Move Up/Down: the
    /// alphabetical block has no manual order to change, and the "Unknown"
    /// group has no project.
    func testOnlyPinnedGroupsReorder() {
        let pinned = project("zeta", pinned: true)
        let rest = project("alpha")
        let orphan = AgentSession(name: "lost", templateId: UUID(), projectId: UUID())
        let groups = SidebarProjectGroup.make(active: [orphan], projects: [rest, pinned])
        XCTAssertEqual(groups.map(\.name), ["zeta", "alpha", "Unknown"])
        XCTAssertEqual(groups.map(\.isReorderable), [true, false, false])
    }

    // MARK: - Gap

    /// The list's laid-out height at the pinned width and on the rail.
    private func height(_ projects: [Project], rail: Bool) -> CGFloat {
        let sessions = projects.map { AgentSession(name: "s-\($0.name)", templateId: UUID(), projectId: $0.id) }
        let store = WorkspaceStore(testingProjects: projects, testingSessions: sessions)
        for s in sessions { store.updateSessionStatus(id: s.id, status: .running) }
        return withDials({ $0.set(SidebarProjectsLayout.oneView.rawValue, forKey: SidebarDialTuning.projectsLayoutKey) }) {
            let expanded: CGFloat = 260
            let width = rail ? WorkspaceLayout.sidebarRailWidth : expanded
            let view = RecentsListView(previewDragState: SessionDragState())
                .environmentObject(store)
                .environmentObject(SessionCoordinator())
                .environmentObject(SidebarWidthModel(width: width, morph: rail ? 1 : 0, expandedWidth: expanded))
                .environment(\.sidebarMorphOverride, rail ? 1 : 0)
                .frame(width: width)
            let hosting = NSHostingView(rootView: view)
            hosting.layoutSubtreeIfNeeded()
            return hosting.fittingSize.height
        }
    }

    /// The break is 16pt, only when both blocks have a project, and the
    /// same in the rail and the pinned sidebar, so no tile moves between
    /// the two widths.
    func testBlockGapIsSixteenOnlyWhenBothBlocksExistAndMatchesRailAndSidebar() {
        let names = ["beacon", "harbor", "kiln", "meridian"]
        let mixed = names.enumerated().map { project($1, pinned: $0 < 2) }
        let allPinned = names.map { project($0, pinned: true) }
        let nonePinned = names.map { project($0) }

        for rail in [false, true] {
            let none = height(nonePinned, rail: rail)
            XCTAssertEqual(height(allPinned, rail: rail), none, accuracy: 0.5, "one block: no gap (rail \(rail))")
            XCTAssertEqual(height(mixed, rail: rail) - none, 16, accuracy: 0.5, "two blocks: a 16pt gap (rail \(rail))")
        }
    }
}

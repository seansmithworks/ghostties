import AppKit
import Combine
import Foundation
import GhosttiesCore
import SwiftUI
import XCTest
@testable import Ghostty

/// Gate: one view scrolls the selected thread into view, clear of the tray
/// (`SidebarSelectionFollower`).
///
/// Selecting a thread whose row is below the viewport scrolls the list the
/// least distance that rests the row `SidebarSelectionFollow.trayClearance`
/// (8pt) above the floating tray's top edge, never flush on it. After that
/// only another change of selection scrolls: activity and time do not.
///
/// A real `WorkspaceViewContainer` in a 900x620 window on a
/// persistence-disabled store; frames from the Redlines registry
/// (`row.<id>`, `tray.group`), both in the sidebar hosting view's top-left
/// coordinates.
///
/// XCTest, not Swift Testing: the follower scrolls on the next main-queue
/// turn, and a Swift Testing test body is itself a main-queue job, so that
/// turn never comes while the test is still running.
@MainActor
final class SidebarSelectionFollowGateTests: PrivateDefaultsTestCase {
    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    private struct Rig {
        let container: WorkspaceViewContainer
        let window: NSWindow
        let store: WorkspaceStore
        let projects: [Project]
        /// Three projects of six unpinned threads, in list order.
        let sessions: [AgentSession]

        func close() {
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
    }

    private func spin(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    }

    /// Enough threads that the list overflows the 620pt window; the first
    /// is selected, so the list starts at its top.
    private func makeRig() -> Rig {
        let projects = (1...3).map { Project(name: "project-\($0)", rootPath: "~/Code/project-\($0)") }
        var sessions: [AgentSession] = []
        for p in projects {
            for n in 1...6 {
                sessions.append(AgentSession(name: "thread \(p.name) \(n)", templateId: AgentTemplate.claudeCode.id, projectId: p.id))
            }
        }
        let store = WorkspaceStore(
            testingProjects: projects, testingSessions: sessions,
            hasShownPinMigrationNotice: true, hasDismissedPinMigrationNotice: true
        )
        for s in sessions {
            store.updateSessionStatus(id: s.id, status: .running)
            store.updateIndicatorState(id: s.id, state: .idle)
        }
        // Each project's last thread is working, so every project is active
        // and none folds into the idle row (`SidebarIdleFold`).
        for p in projects {
            guard let busy = sessions.last(where: { $0.projectId == p.id }) else { continue }
            store.updateIndicatorState(id: busy.id, state: .processing)
        }
        store.updateSidebarMode(.pinned)
        let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel(), store: store)
        container.coordinatorForTesting.setActiveSessionIdForTesting(sessions[0].id)
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = container
        window.orderFrontRegardless()
        let rig = Rig(container: container, window: window, store: store, projects: projects, sessions: sessions)
        settle(rig)
        return rig
    }

    /// Long enough for a scroll on the reflow spring to come to rest.
    private func settle(_ rig: Rig) {
        for _ in 0..<24 {
            rig.container.layoutSubtreeIfNeeded()
            spin(0.05)
        }
    }

    override func setUp() {
        super.setUp()
        defaults.set(true, forKey: SidebarDialTuning.redlinesKey)
    }

    private func frame(_ rig: Rig, _ id: String) throws -> CGRect {
        try XCTUnwrap(rig.container.redlineRegistryForTesting.rects[id], "no frame for \(id)")
    }

    /// The clear space between `session`'s row and the tray's top edge.
    private func gapAboveTray(_ rig: Rig, _ session: AgentSession) throws -> CGFloat {
        try frame(rig, RedlineID.trayGroup).minY - frame(rig, RedlineID.row(session.id)).maxY
    }

    private let clearance = SidebarSelectionFollow.trayClearance
    private let tolerance: CGFloat = 0.5

    func testSelectingAnOffScreenUnpinnedThreadRestsItEightPointsAboveTheTray() throws {
        let rig = makeRig()
        defer { rig.close() }
        // The third project's second thread: unpinned, mid-list, and
        // below the tray before it is selected.
        let target = rig.sessions[13]
        // A row reports its frame once it has been near the viewport.
        let start = rig.container.redlineRegistryForTesting.rects[RedlineID.row(target.id)]
        let trayTop = try frame(rig, RedlineID.trayGroup).minY
        XCTAssertTrue(start.map { $0.minY > trayTop } ?? true, "the thread starts off-screen, below the tray's top")

        rig.container.coordinatorForTesting.setActiveSessionIdForTesting(target.id)
        settle(rig)

        let gap = try gapAboveTray(rig, target)
        XCTAssertEqual(gap, clearance, accuracy: tolerance, "the selected row's clear space above the tray")
        // In view at the top too.
        let viewport = try frame(rig, RedlineID.listViewport)
        let row = try frame(rig, RedlineID.row(target.id))
        XCTAssertGreaterThanOrEqual(row.minY, viewport.minY - tolerance, "the row's top is inside the viewport")
    }

    func testTheLastThreadAlsoClearsTheTray() throws {
        let rig = makeRig()
        defer { rig.close() }
        let last = try XCTUnwrap(rig.sessions.last)

        rig.container.coordinatorForTesting.setActiveSessionIdForTesting(last.id)
        settle(rig)

        XCTAssertGreaterThanOrEqual(try gapAboveTray(rig, last), clearance - tolerance, "the last row's clear space above the tray")
    }

    /// Threads above the selected one, scrolled out of view, start needing
    /// you: each row gains its second line and its action line, which
    /// pushes every row under it down. The selected row was resting 8pt
    /// above the tray, so the list scrolls just enough to keep it there
    /// (`SidebarSelectionFollow.KeepClear`).
    ///
    /// Without the fix this is intermittent: in some runs the scroll view
    /// holds the selected row by itself, in others the row lands 39pt, then
    /// 87pt, under the tray's top. Two threads, one after the other,
    /// because the first to flip was the one most often held.
    func testARowAboveGrowingKeepsTheSelectedRowClearOfTheTray() throws {
        let rig = makeRig()
        defer { rig.close() }
        let target = rig.sessions[13]
        rig.container.coordinatorForTesting.setActiveSessionIdForTesting(target.id)
        settle(rig)
        XCTAssertEqual(try gapAboveTray(rig, target), clearance, accuracy: tolerance, "control: the selected row rests 8pt above the tray")

        // The second project's second thread, then the first project's
        // third: both above the viewport's top once the list has followed
        // the selection.
        for above in [rig.sessions[7], rig.sessions[2]] {
            let before = try frame(rig, RedlineID.row(above.id)).height
            rig.store.updateIndicatorState(id: above.id, state: .needsAttention)
            settle(rig)

            let after = try frame(rig, RedlineID.row(above.id)).height
            XCTAssertGreaterThan(after, before + SessionRowActionLine.addedHeight - tolerance, "control: \(above.name) grew by at least its action line")
            let gap = try gapAboveTray(rig, target)
            XCTAssertGreaterThanOrEqual(gap, clearance - tolerance, "after \(above.name) grew, the selected row is still clear of the tray (gap \(gap))")
            // The growing row overshoots on the fold's spring (about 3% of
            // its 48pt growth) and the list holds the selected row clear at
            // the peak, so it can rest a point or two higher, never more.
            XCTAssertLessThanOrEqual(gap, clearance + 2, "and the list scrolled no further than the spring's overshoot (gap \(gap))")
        }
    }

    /// The row order is the user's, so nothing but a selection scrolls:
    /// another thread working, printing and finishing leaves the list where
    /// the selection put it.
    func testAfterFollowingTheListDoesNotScrollAgainOnItsOwn() throws {
        let rig = makeRig()
        defer { rig.close() }
        let target = rig.sessions[13]
        rig.container.coordinatorForTesting.setActiveSessionIdForTesting(target.id)
        settle(rig)
        let rested = try frame(rig, RedlineID.row(target.id))

        let other = rig.sessions[2]
        rig.store.updateIndicatorState(id: other.id, state: .processing)
        rig.store.recordActivity(sessionId: other.id, projectId: other.projectId, isOutput: true)
        settle(rig)
        rig.store.updateIndicatorState(id: other.id, state: .idle)
        settle(rig)

        let after = try frame(rig, RedlineID.row(target.id))
        XCTAssertEqual(after.minY, rested.minY, accuracy: tolerance, "the selected row moved with no change of selection")
        // And the rows are where they were: the working thread is still
        // its project's third row.
        let order = rig.store.railSessions(layout: .oneView, pinningAvailable: true).map(\.id)
        XCTAssertEqual(order, rig.sessions.map(\.id))
    }
}

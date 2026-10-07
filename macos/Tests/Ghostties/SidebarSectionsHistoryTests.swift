import XCTest
import SwiftUI
import Combine
import GhosttiesCore
@testable import Ghostty

/// Mock I3: the sidebar renders Pinned, Active and one History row; inactive
/// and archived sessions are reachable only through History, which opens the
/// history browser in the canvas.
///
/// Every store here is persistence-disabled (`WorkspaceStore(testingProjects:)`)
/// and no path below touches `WorkspaceStore.shared`.
@MainActor
final class SidebarSectionsHistoryTests: XCTestCase {

    // MARK: - Fixture

    private let now = Date()
    private let projectA = Project(name: "ghostties", rootPath: "~/Code/ghostties")
    private let projectB = Project(name: "brukas", rootPath: "~/Code/brukas")

    private func session(
        _ name: String,
        project: Project? = nil,
        ago: TimeInterval? = nil,
        isPinned: Bool = false,
        resume: AgentResume? = nil
    ) -> AgentSession {
        let stamp = ago.map { now.addingTimeInterval(-$0) }
        return AgentSession(
            name: name,
            templateId: UUID(),
            projectId: (project ?? projectA).id,
            lastActiveAt: stamp,
            lastOutputAt: stamp,
            isPinned: isPinned,
            resume: resume
        )
    }

    /// 2 pinned (one running, one closed), 2 active, 1 inactive (ran this
    /// launch, stopped), 2 archived (restored, never started).
    private struct Fixture {
        let sessions: [AgentSession]
        let statuses: [UUID: SessionStatus]
        let startedThisLaunch: Set<UUID>
        let pinned: [AgentSession]
        let active: [AgentSession]
        let inactive: AgentSession
        let archivedOld: AgentSession
        let archivedNew: AgentSession

        var sections: SidebarSessionSections {
            SidebarSessionSections.make(sessions: sessions, statuses: statuses, sessionIdsStartedThisLaunch: startedThisLaunch)
        }
    }

    private func fixture() -> Fixture {
        let pinnedLive = session("orchestrator", ago: 60, isPinned: true)
        let pinnedClosed = session("inbox agent", ago: 7_200, isPinned: true)
        let active1 = session("fix checkout", project: projectB, ago: 30)
        let active2 = session("rail spacing", ago: 10)
        let inactive = session("tray glass pass", ago: 2 * 3_600)
        let archivedOld = session("job board scraper", project: projectB, ago: 14 * 86_400)
        let archivedNew = session("migrate auth", ago: 2 * 86_400)
        let sessions = [pinnedLive, pinnedClosed, active1, inactive, archivedOld, active2, archivedNew]
        return Fixture(
            sessions: sessions,
            statuses: [pinnedLive.id: .running, active1.id: .running, active2.id: .running, inactive.id: .exited],
            startedThisLaunch: [pinnedLive.id, active1.id, active2.id, inactive.id],
            pinned: [pinnedLive, pinnedClosed],
            active: [active1, active2],
            inactive: inactive,
            archivedOld: archivedOld,
            archivedNew: archivedNew
        )
    }

    // MARK: - Section model

    func testSidebarYieldsPinnedActiveAndHistoryOnly() {
        let f = fixture()
        let sections = f.sections

        XCTAssertEqual(sections.rendered, [.pinned(count: 2), .active(count: 2), .history(count: 3)])
        XCTAssertEqual(sections.rowSessions.map(\.id), (f.pinned + f.active).map(\.id))

        let pastIds: Set<UUID> = [f.inactive.id, f.archivedOld.id, f.archivedNew.id]
        XCTAssertTrue(Set(sections.rowSessions.map(\.id)).isDisjoint(with: pastIds), "inactive/archived must never render as rows")
        XCTAssertEqual(Set(sections.history.map(\.id)), pastIds)
    }

    func testPinnedIsOmittedWhenEmptyButActiveAndHistoryAlwaysRender() {
        let sections = SidebarSessionSections.make(sessions: [], statuses: [:], sessionIdsStartedThisLaunch: [])
        XCTAssertEqual(sections.rendered, [.active(count: 0), .history(count: 0)])
    }

    func testHistoryIsNewestFirstAcrossInactiveAndArchived() {
        let f = fixture()
        XCTAssertEqual(f.sections.history.map(\.name), ["tray glass pass", "migrate auth", "job board scraper"])
    }

    /// The rail lists exactly the sidebar's rows (Pinned then Active), so
    /// the rail shortcuts and the expanded list agree.
    func testRailSessionsMatchTheSidebarRows() {
        let f = fixture()
        let store = WorkspaceStore(testingProjects: [projectA, projectB], testingSessions: f.sessions)
        for (id, status) in f.statuses {
            store.updateSessionStatus(id: id, status: status)
        }
        XCTAssertEqual(store.railSessions().map(\.id), f.sections.rowSessions.map(\.id))
    }

    // MARK: - History row subtitle

    func testHistorySubtitleCountsAndLastActivity() {
        let f = fixture()
        let sections = f.sections
        XCTAssertEqual(
            HistorySummary.subtitle(count: sections.historyCount, lastActiveAt: sections.historyLastActiveAt, now: now),
            "3 sessions · last 2h ago"
        )
        XCTAssertEqual(HistorySummary.subtitle(count: 1, lastActiveAt: now.addingTimeInterval(-2 * 86_400), now: now), "1 session · last 2d ago")
        XCTAssertEqual(HistorySummary.subtitle(count: 148, lastActiveAt: now.addingTimeInterval(-3 * 7 * 86_400), now: now), "148 sessions · last 3w ago")
    }

    func testHistorySubtitleEmptyState() {
        XCTAssertEqual(HistorySummary.subtitle(count: 0, lastActiveAt: nil, now: now), "No past sessions")
        XCTAssertEqual(HistorySummary.subtitle(count: 0, lastActiveAt: now, now: now), "No past sessions")
    }

    func testHistorySubtitleWithoutTimestampsShowsTheCountOnly() {
        XCTAssertEqual(HistorySummary.subtitle(count: 4, lastActiveAt: nil, now: now), "4 sessions")
    }

    func testAgoUnits() {
        XCTAssertEqual(HistorySummary.ago(now.addingTimeInterval(-5), now: now), "1m")
        XCTAssertEqual(HistorySummary.ago(now.addingTimeInterval(-45 * 60), now: now), "45m")
        XCTAssertEqual(HistorySummary.ago(now.addingTimeInterval(-5 * 3_600), now: now), "5h")
        XCTAssertEqual(HistorySummary.ago(now.addingTimeInterval(-6 * 86_400), now: now), "6d")
        XCTAssertEqual(HistorySummary.ago(now.addingTimeInterval(-10 * 86_400), now: now), "1w")
        XCTAssertEqual(HistorySummary.ago(now.addingTimeInterval(-400 * 86_400), now: now), "1y")
    }

    // MARK: - History entries

    func testEntriesCoverInactiveAndArchivedWithProjectAndArchiveFlag() {
        let f = fixture()
        let entries = HistoryEntry.entries(from: f.sections, projects: [projectA, projectB])

        XCTAssertEqual(entries.map(\.id), [f.inactive.id, f.archivedNew.id, f.archivedOld.id])
        XCTAssertEqual(entries.map(\.isArchived), [false, true, true])
        XCTAssertEqual(entries.map(\.projectName), ["ghostties", "ghostties", "brukas"])
        XCTAssertEqual(entries.map(\.title), ["tray glass pass", "migrate auth", "job board scraper"])
        XCTAssertEqual(entries[0].lastActiveAt, f.inactive.displayTimestamp)
        XCTAssertFalse(entries.contains(where: \.isPinned))
    }

    // MARK: - Selecting History

    func testSelectingHistoryMovesTheSelectedCardToHistory() {
        let coordinator = SessionCoordinator()
        let prior = UUID()
        coordinator.setActiveSessionIdForTesting(prior)
        XCTAssertEqual(coordinator.sidebarSelectedSessionId, prior)

        coordinator.presentHistory()

        XCTAssertTrue(coordinator.isHistoryPresented)
        XCTAssertNil(coordinator.sidebarSelectedSessionId, "only the History row is selected while the browser is open")
        XCTAssertEqual(coordinator.activeSessionId, prior, "the underlying selection is kept for close")
    }

    func testCloseRestoresThePriorSelection() {
        let coordinator = SessionCoordinator()
        let store = WorkspaceStore(testingProjects: [projectA])
        let prior = UUID()
        coordinator.setActiveSessionIdForTesting(prior)
        coordinator.presentHistory()

        HistoryActions.make(store: store, coordinator: coordinator).close()

        XCTAssertFalse(coordinator.isHistoryPresented)
        XCTAssertEqual(coordinator.activeSessionId, prior)
        XCTAssertEqual(coordinator.sidebarSelectedSessionId, prior)
    }

    func testSelectingASessionClosesHistory() {
        let coordinator = SessionCoordinator()
        coordinator.presentHistory()
        coordinator.focusSession(id: UUID())
        XCTAssertFalse(coordinator.isHistoryPresented)
    }

    func testResumeRoutesTheIdToTheRelaunchFlowWithTheRightMode() {
        let withResume = session("resumable", ago: 600, resume: AgentResume(agent: .claude, sessionId: "abc"))
        let without = session("plain", ago: 600)
        let store = WorkspaceStore(testingProjects: [projectA], testingSessions: [withResume, without])
        let coordinator = SessionCoordinator()

        var calls: [(UUID, SessionCoordinator.RelaunchMode)] = []
        let actions = HistoryActions.make(store: store, coordinator: coordinator) { session, mode in
            calls.append((session.id, mode))
        }
        actions.resume(withResume.id)
        actions.resume(without.id)
        actions.resume(UUID()) // unknown id: no relaunch

        XCTAssertEqual(calls.map(\.0), [withResume.id, without.id])
        XCTAssertEqual(calls.map(\.1), [.resume, .fresh])
    }

    func testTogglePinUsesTheSidebarPinAction() {
        let past = session("old thread", ago: 86_400)
        let store = WorkspaceStore(testingProjects: [projectA], testingSessions: [past])
        let actions = HistoryActions.make(store: store, coordinator: SessionCoordinator())

        actions.togglePin(past.id)
        XCTAssertEqual(store.sessions.first?.isPinned, true)
        actions.togglePin(past.id)
        XCTAssertEqual(store.sessions.first?.isPinned, false)
    }

    // MARK: - Canvas

    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }

    func testSelectingHistoryPresentsTheBrowserInTheCanvasAndCloseRemovesIt() {
        let store = WorkspaceStore(testingProjects: [projectA])
        let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel(), store: store)
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 900, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = container
        window.orderFrontRegardless()
        defer {
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
        settle()
        XCTAssertFalse(container.isHistoryBrowserMountedForTesting)

        container.coordinatorForTesting.presentHistory()
        settle()
        XCTAssertTrue(container.isHistoryBrowserMountedForTesting)

        container.coordinatorForTesting.dismissHistory()
        settle()
        XCTAssertFalse(container.isHistoryBrowserMountedForTesting)
    }

    private final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    /// Opening History must take keyboard focus off the terminal so the
    /// browser's ⏎/esc/⌘P/arrows reach it: the query field ends up first
    /// responder. A text view inside the terminal card stands in for the
    /// focused terminal surface.
    func testOpeningHistoryMovesKeyFocusFromTheTerminalToTheBrowser() {
        let store = WorkspaceStore(testingProjects: [projectA])
        let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel(), store: store)
        let window = KeyableWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 900, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = container
        window.orderFrontRegardless()
        window.makeKey()
        defer {
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
        container.layoutSubtreeIfNeeded()
        let terminalStandIn = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        container.terminalContainer.addSubview(terminalStandIn)
        XCTAssertTrue(window.makeFirstResponder(terminalStandIn))

        container.coordinatorForTesting.presentHistory()
        let deadline = Date().addingTimeInterval(5)
        while !(container.historyBrowserHasKeyFocusForTesting && window.firstResponder is NSTextView), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }

        XCTAssertTrue(container.historyBrowserHasKeyFocusForTesting, "first responder: \(String(describing: window.firstResponder))")
        XCTAssertTrue(window.firstResponder is NSTextView, "the query field's editor should hold focus")
        XCTAssertFalse(window.firstResponder === terminalStandIn)
    }

    // MARK: - The History row is the session row

    private let width: CGFloat = 220
    private let rowHeight: CGFloat = 48

    private func render<V: View>(_ row: V) -> NSBitmapImageRep? {
        let framed = row
            .environmentObject(SidebarWidthModel(width: width))
            .environmentObject(SessionCoordinator())
            .padding(.leading, SidebarDialTuning.windowMargin() + SidebarDialTuning.contentPaddingLeading())
            .padding(.trailing, SidebarDialTuning.windowMargin() + SidebarDialTuning.contentPaddingTrailing())
            .frame(width: width, height: rowHeight)
            .background(Color.white)
        let hosting = NSHostingView(rootView: framed)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: rowHeight)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }

    /// Ink bounds in points within [fromX, toX), against the corner pixel.
    private func ink(_ rep: NSBitmapImageRep, fromX: CGFloat, toX: CGFloat) -> (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat)? {
        let scale = CGFloat(rep.pixelsWide) / width
        guard let bg = rep.colorAt(x: rep.pixelsWide - 1, y: 0)?.usingColorSpace(.sRGB) else { return nil }
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in 0..<rep.pixelsHigh {
            for x in Int(fromX * scale)..<min(rep.pixelsWide, Int(toX * scale)) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let d = abs(c.redComponent - bg.redComponent) + abs(c.greenComponent - bg.greenComponent) + abs(c.blueComponent - bg.blueComponent)
                if d > 0.45 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
            }
        }
        guard maxX >= 0 else { return nil }
        return (CGFloat(minX) / scale, CGFloat(maxX + 1) / scale, CGFloat(minY) / scale, CGFloat(maxY + 1) / scale)
    }

    private struct SessionRowHarness: View {
        @FocusState private var focus: Bool
        @State private var name = ""
        var body: some View {
            RecentsRowView(
                session: AgentSession(name: "History", templateId: UUID(), projectId: UUID()),
                projectName: "3 sessions · last 2h ago",
                indicatorState: .idle,
                isActive: false,
                editingName: $name,
                isRenameFocused: $focus,
                onTap: {}
            )
        }
    }

    /// Same title/subtitle text in both rows, so the label column must
    /// render pixel-identical, and the clock must sit inside the same
    /// trailing glyph box as a status glyph.
    func testHistoryRowRendersWithTheSessionRowsLayout() throws {
        let history = try XCTUnwrap(render(HistoryRowView(subtitle: "3 sessions · last 2h ago", isActive: false, onTap: {})))
        let sessionRow = try XCTUnwrap(render(SessionRowHarness()))

        let labelsEnd = width - 60
        let h = try XCTUnwrap(ink(history, fromX: 0, toX: labelsEnd), "history labels")
        let s = try XCTUnwrap(ink(sessionRow, fromX: 0, toX: labelsEnd), "session labels")
        XCTAssertEqual(h.minX, s.minX, accuracy: 0.5)
        XCTAssertEqual(h.minY, s.minY, accuracy: 0.5)
        XCTAssertEqual(h.maxY, s.maxY, accuracy: 0.5)

        let boxMaxX = width - SidebarDialTuning.windowMargin() - SidebarDialTuning.contentPaddingTrailing() - SidebarDialTuning.rowTrailingPadding()
        let boxMinX = boxMaxX - SidebarDialTuning.rowGhostSize()
        let clock = try XCTUnwrap(ink(history, fromX: labelsEnd, toX: width), "clock glyph")
        XCTAssertGreaterThanOrEqual(clock.minX, boxMinX - 0.6)
        XCTAssertLessThanOrEqual(clock.maxX, boxMaxX + 0.6)
        let rowMidY = rowHeight / 2
        XCTAssertEqual((clock.minY + clock.maxY) / 2, rowMidY, accuracy: 1.0, "clock is vertically centred like the status glyphs")
    }

    func testRailHistoryClockIsCentredOnTheRail() throws {
        let rail = try XCTUnwrap(render(RailHistoryRow(subtitle: "3 sessions", isActive: false, onTap: {})))
        let clock = try XCTUnwrap(ink(rail, fromX: 0, toX: width), "rail clock")
        XCTAssertEqual((clock.minX + clock.maxX) / 2, width / 2, accuracy: 0.5)
        XCTAssertEqual((clock.minY + clock.maxY) / 2, rowHeight / 2, accuracy: 1.0)
    }
}

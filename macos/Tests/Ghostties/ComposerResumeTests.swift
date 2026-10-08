import AppKit
import SwiftUI
import Testing
import XCTest
import GhosttiesCore
@testable import Ghostty

/// Sidebar vnext (2026-10-08): session History leaves the sidebar and lives
/// in the Cmd+T composer. ↓ reveals a Resume list (A5, default); a dial
/// swaps in a two-column composer (A4); a sidebar dial brings History back.
///
/// All fixture data is synthetic — public repo.
@Suite("Composer Resume: keyboard state")
struct ComposerResumeStateTests {
    private let a = UUID(), b = UUID(), c = UUID()

    @Test func listDefaultsToA5() {
        let name = "ghostties.composerResume.layout.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        #expect(ComposerResumeLayout.current(defaults: d) == .list)
        d.set("columns", forKey: ComposerResumeLayout.storageKey)
        #expect(ComposerResumeLayout.current(defaults: d) == .columns)
        d.set("nonsense", forKey: ComposerResumeLayout.storageKey)
        #expect(ComposerResumeLayout.current(defaults: d) == .list)
    }

    @Test func downRevealsTheListAndUpFromTheTopCollapsesIt() {
        var state = ComposerResumeState()
        let rows = [a, b, c]
        #expect(state.handle(.up, layout: .list, rowIDs: rows) == .passThrough, "↑ on the closed list stays the composer's")
        #expect(state.handle(.submit, layout: .list, rowIDs: rows) == .passThrough, "Return on the closed list starts a session")
        #expect(state.handle(.down, layout: .list, rowIDs: rows) == .handled)
        #expect(state.isRevealed)
        #expect(state.selection(in: rows) == a, "the newest row is highlighted first")
        #expect(state.handle(.down, layout: .list, rowIDs: rows) == .handled)
        #expect(state.handle(.down, layout: .list, rowIDs: rows) == .handled)
        #expect(state.handle(.down, layout: .list, rowIDs: rows) == .handled)
        #expect(state.selection(in: rows) == c, "clamps at the bottom")
        #expect(state.handle(.submit, layout: .list, rowIDs: rows) == .resume(c))
        _ = state.handle(.up, layout: .list, rowIDs: rows)
        _ = state.handle(.up, layout: .list, rowIDs: rows)
        #expect(state.isRevealed)
        #expect(state.handle(.up, layout: .list, rowIDs: rows) == .handled)
        #expect(!state.isRevealed, "↑ from the top row collapses")
    }

    @Test func escCollapsesInsteadOfClosing() {
        var state = ComposerResumeState()
        _ = state.handle(.down, layout: .list, rowIDs: [a])
        #expect(state.handle(.exit, layout: .list, rowIDs: [a]) == .handled)
        #expect(!state.isRevealed)
        #expect(state.handle(.exit, layout: .list, rowIDs: [a]) == .passThrough, "a second Esc closes the composer")
    }

    @Test func returnOnAnEmptyRevealedListFallsBackToStarting() {
        var state = ComposerResumeState()
        _ = state.handle(.down, layout: .list, rowIDs: [])
        #expect(state.isRevealed)
        #expect(state.handle(.submit, layout: .list, rowIDs: []) == .passThrough)
    }

    @Test func selectionReanchorsWhenTypingFiltersItOut() {
        var state = ComposerResumeState()
        _ = state.handle(.down, layout: .list, rowIDs: [a, b, c])
        _ = state.handle(.down, layout: .list, rowIDs: [a, b, c])
        #expect(state.selection(in: [a, b, c]) == b)
        #expect(state.selection(in: [c]) == c)
    }

    @Test func columnsCrossWithRightAndLeft() {
        var state = ComposerResumeState()
        let rows = [a, b]
        #expect(state.handle(.down, layout: .columns, rowIDs: rows) == .passThrough, "↓ moves the start column")
        #expect(state.handle(.right, layout: .columns, rowIDs: []) == .passThrough, "nothing to cross to")
        #expect(state.handle(.right, layout: .columns, rowIDs: rows) == .handled)
        #expect(state.ownsKeyboard)
        #expect(state.handle(.down, layout: .columns, rowIDs: rows) == .handled)
        #expect(state.handle(.submit, layout: .columns, rowIDs: rows) == .resume(b))
        #expect(state.handle(.left, layout: .columns, rowIDs: rows) == .handled)
        #expect(!state.ownsKeyboard)
        #expect(state.handle(.submit, layout: .columns, rowIDs: rows) == .passThrough)
        #expect(state.handle(.exit, layout: .columns, rowIDs: rows) == .passThrough)
    }

    @Test func rowsFilterByWhatIsTypedNewestFirst() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func entry(_ title: String, _ project: String, ago: TimeInterval) -> HistoryEntry {
            HistoryEntry(id: UUID(), projectName: project, title: title, lastActiveAt: now.addingTimeInterval(-ago), isArchived: true, isPinned: false)
        }
        let old = entry("flaky e2e retries", "atlas-api", ago: 2 * 86_400)
        let new = entry("rate limits", "atlas-api", ago: 7_200)
        let web = entry("pricing page copy", "orbit-web", ago: 86_400 + 60)
        #expect(ComposerResumeRows.rows(entries: [old, web, new], query: "").map(\.id) == [new.id, web.id, old.id])
        #expect(ComposerResumeRows.rows(entries: [old, web, new], query: "atlas").map(\.id) == [new.id, old.id])
        #expect(ComposerResumeRows.rows(entries: [old, web, new], query: "pricing").map(\.id) == [web.id])
        #expect(ComposerResumeRows.meta(projectName: "atlas-api", lastActiveAt: new.lastActiveAt, now: now) == "atlas-api · 2h")
        #expect(ComposerResumeRows.age(web.lastActiveAt, now: now) == "yesterday")
        #expect(ComposerResumeRows.age(old.lastActiveAt, now: now) == "2d")
    }

    @Test func windowKeepsTheSelectionInView() {
        #expect(ComposerResumeRows.window(count: 3, selected: 2, cap: 5) == 0..<3)
        #expect(ComposerResumeRows.window(count: 9, selected: 0, cap: 5) == 0..<5)
        #expect(ComposerResumeRows.window(count: 9, selected: 6, cap: 5) == 2..<7)
        #expect(ComposerResumeRows.window(count: 9, selected: 8, cap: 5) == 4..<9)
    }
}

/// The palette itself, mounted with isolated stores: ↓ then Return resumes
/// the newest past session through the relaunch flow the history browser
/// uses; Return alone still starts a session.
@MainActor
@Suite("Composer Resume: hosted palette")
struct ComposerResumeHostedTests {
    private let now = Date()

    private struct Mounted {
        let window: NSWindow
        let field: NSTextView
        let composerStore: SessionComposerStore
        let newest: AgentSession
    }

    private func mount(layout: ComposerResumeLayout, relaunch: @escaping (AgentSession, SessionCoordinator.RelaunchMode) -> Void) throws -> Mounted {
        let project = Project(name: "atlas-api", rootPath: "/tmp/composer-resume-\(UUID().uuidString)")
        let newest = AgentSession(
            name: "rate limits", templateId: AgentTemplate.claudeCode.id, projectId: project.id,
            lastActiveAt: now.addingTimeInterval(-7_200), lastOutputAt: now.addingTimeInterval(-7_200),
            isNamePinned: true, resume: AgentResume(agent: .claude, sessionId: "fixture-rate-limits")
        )
        let older = AgentSession(
            name: "migrate to v2 SDK", templateId: AgentTemplate.claudeCode.id, projectId: project.id,
            lastActiveAt: now.addingTimeInterval(-18_000), lastOutputAt: now.addingTimeInterval(-18_000),
            isNamePinned: true
        )
        let store = WorkspaceStore(testingProjects: [project], testingSessions: [older, newest])
        let composerStore = SessionComposerStore(isolatedForTesting: ())
        let suiteName = "ghostties.composerResume.hosted.\(UUID().uuidString)"
        let tuning = try #require(UserDefaults(suiteName: suiteName))
        tuning.set(layout.rawValue, forKey: ComposerResumeLayout.storageKey)

        let palette = SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(projectBinding: .prefilled(project)),
            composerStore: composerStore,
            tuningDefaultsForTesting: tuning,
            resumeRelaunchForTesting: relaunch
        )
        .environmentObject(store)
        .environmentObject(SessionCoordinator())

        let size = NSSize(width: 900, height: 600)
        let hosting = NSHostingView(rootView: palette.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        settle(hosting)
        let field = try #require(Self.textView(in: hosting), "composer field not found")
        return Mounted(window: window, field: field, composerStore: composerStore, newest: newest)
    }

    private func settle(_ view: NSView) {
        for _ in 0..<3 {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
    }

    static func textView(in view: NSView) -> NSTextView? {
        if let text = view as? NSTextView { return text }
        for sub in view.subviews {
            if let found = textView(in: sub) { return found }
        }
        return nil
    }

    private func press(_ selector: Selector, in m: Mounted) {
        m.field.doCommand(by: selector)
        settle(m.window.contentView!)
    }

    @Test func downThenReturnResumesTheNewestPastSessionThroughTheRelaunchFlow() throws {
        var relaunched: [(UUID, SessionCoordinator.RelaunchMode)] = []
        var started = 0
        let m = try mount(layout: .list) { relaunched.append(($0.id, $1)) }
        defer { m.window.orderOut(nil) }
        m.composerStore.dispatchOverrideForTesting = { _, _ in started += 1 }

        press(#selector(NSResponder.moveDown(_:)), in: m)
        press(#selector(NSResponder.insertNewline(_:)), in: m)

        #expect(relaunched.map(\.0) == [m.newest.id], "↓ then Return resumes the newest past session")
        #expect(relaunched.map(\.1) == [.resume], "a session with a resume record resumes its conversation")
        #expect(started == 0, "resuming does not also start a new session")
    }

    @Test func returnWithoutDownStillStartsASession() throws {
        var relaunched = 0
        var started = 0
        let m = try mount(layout: .list) { _, _ in relaunched += 1 }
        defer { m.window.orderOut(nil) }
        m.composerStore.dispatchOverrideForTesting = { _, _ in started += 1 }

        press(#selector(NSResponder.insertNewline(_:)), in: m)

        #expect(started == 1)
        #expect(relaunched == 0)
    }

    @Test func columnsCrossRightIntoResumeAndReturnResumes() throws {
        var relaunched: [UUID] = []
        let m = try mount(layout: .columns) { session, _ in relaunched.append(session.id) }
        defer { m.window.orderOut(nil) }

        press(#selector(NSResponder.moveRight(_:)), in: m)
        press(#selector(NSResponder.insertNewline(_:)), in: m)

        #expect(relaunched == [m.newest.id])
    }
}

/// "History in sidebar" (default hidden): History and its rail clock leave
/// the sidebar; Pinned and Active lay out exactly as before.
@MainActor
final class SidebarHistoryDialTests: XCTestCase {
    override func tearDown() {
        SidebarDialTuning.store.removeObject(forKey: SidebarDialTuning.historyInSidebarKey)
        super.tearDown()
    }

    func testDialDefaultsToHiddenAndResetClearsIt() {
        let name = "com.seansmithdesign.ghostties.tests.history-in-sidebar"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        defer { d.removePersistentDomain(forName: name) }
        XCTAssertFalse(SidebarDialTuning.historyInSidebar(defaults: d))
        d.set(true, forKey: SidebarDialTuning.historyInSidebarKey)
        XCTAssertTrue(SidebarDialTuning.historyInSidebar(defaults: d))
        XCTAssertTrue(SidebarDialTuning.allKeys.contains(SidebarDialTuning.historyInSidebarKey))
        SidebarDialTuning.reset(defaults: d)
        XCTAssertFalse(SidebarDialTuning.historyInSidebar(defaults: d))
        d.set("YES", forKey: SidebarDialTuning.historyInSidebarKey)
        XCTAssertTrue(SidebarDialTuning.historyInSidebar(defaults: d), "a launch argument arrives as a string")
    }

    func testHiddenHistoryLeavesPinnedAndActiveUnchanged() {
        let pinned = AgentSession(name: "p", templateId: UUID(), projectId: UUID(), isPinned: true)
        let active = AgentSession(name: "a", templateId: UUID(), projectId: UUID())
        let sections = SidebarSessionSections(pinned: [pinned], active: [active], inactive: [], archived: [])
        for placement in SidebarSessionSections.HistoryPlacement.allCases {
            let hidden = sections.layout(historyPlacement: placement, showsHistory: false)
            XCTAssertEqual(hidden.list, [.pinnedRows, .pinnedEnd, .pinnedHairline, .activeRows, .activeEnd])
            XCTAssertEqual(hidden.footer, [])
            let shown = sections.layout(historyPlacement: placement, showsHistory: true)
            XCTAssertEqual(shown.list + shown.footer, hidden.list + [.historyHairline, .history])
        }
    }

    /// The expanded list and the rail, with past sessions present: the
    /// History row's ink (at the bottom, above the tray) is there with the
    /// dial on and gone with it off.
    func testHistoryRowRendersOnlyWithTheDialOn() throws {
        for rail in [false, true] {
            let off = try renderBottomInk(rail: rail, historyInSidebar: false)
            let on = try renderBottomInk(rail: rail, historyInSidebar: true)
            XCTAssertEqual(off, 0, "no History ink with the dial off (rail: \(rail))")
            XCTAssertGreaterThan(on, 20, "History ink with the dial on (rail: \(rail))")
        }
    }

    /// Ink pixels in the bottom 120pt of the session column. The dial suite
    /// is shared across parallel test processes and cleared at each one's
    /// launch, so the render is retried until the dial held throughout.
    private func renderBottomInk(rail: Bool, historyInSidebar: Bool) throws -> Int {
        for _ in 0..<5 {
            SidebarDialTuning.store.set(historyInSidebar, forKey: SidebarDialTuning.historyInSidebarKey)
            let ink = try renderBottomInkOnce(rail: rail)
            if SidebarDialTuning.historyInSidebar() == historyInSidebar { return ink }
        }
        struct DialKeptChanging: Error {}
        throw DialKeptChanging()
    }

    private func renderBottomInkOnce(rail: Bool) throws -> Int {
        let project = Project(name: "atlas-api", rootPath: "~/Code/atlas-api")
        let live = AgentSession(name: "auth refactor", templateId: AgentTemplate.claudeCode.id, projectId: project.id, lastActiveAt: Date(), lastOutputAt: Date(), isNamePinned: true)
        let past = (0..<3).map { i in
            AgentSession(name: "past \(i)", templateId: AgentTemplate.claudeCode.id, projectId: project.id,
                         lastActiveAt: Date().addingTimeInterval(-Double(i + 1) * 3600), isNamePinned: true)
        }
        let store = WorkspaceStore(testingProjects: [project], testingSessions: [live] + past)
        store.updateSessionStatus(id: live.id, status: .running)
        let coordinator = SessionCoordinator()
        let width: CGFloat = rail ? 80 : 260
        let height: CGFloat = 500
        let column: AnyView = rail
            ? AnyView(SidebarRailView())
            : AnyView(VStack(spacing: 0) {
                Color.clear.frame(height: store.toolbarRowTopAnchorConstant * 2)
                RecentsListView()
                Spacer(minLength: 0)
                Color.clear.frame(height: SidebarTray.reservedHeight(isVertical: false))
            })
        let root = column
            .frame(width: width, height: height)
            .environment(\.sidebarTrailingGutter, 0)
            .environmentObject(store)
            .environmentObject(coordinator)
            .environmentObject(SidebarWidthModel(width: width))
            .background(Color.white)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / width
        let reserved = SidebarTray.reservedHeight(isVertical: rail)
        let top = Int((height - reserved - 120) * scale), bottom = Int((height - reserved) * scale)
        var ink = 0
        for y in top..<bottom {
            for x in 0..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if c.redComponent + c.greenComponent + c.blueComponent < 2.7 { ink += 1 }
            }
        }
        return ink
    }
}

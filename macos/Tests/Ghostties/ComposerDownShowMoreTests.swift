import AppKit
import SwiftUI
import Testing
import GhosttiesCore
@testable import Ghostty

/// Sean, 2026-10-08: the ↓ list's sections must not scroll on their own.
/// Each shows three rows, then a "Show N more" row that expands it in
/// place; the whole list scrolls as one, keeping the highlight in view.
///
/// All fixture data is synthetic — public repo.
@Suite("Composer ↓ list: show more (model)")
struct ComposerDownShowMoreModelTests {
    @Test func aLongSectionShowsThreeRowsThenShowMore() {
        let r = (0..<5).map { _ in UUID() }, t = UUID()
        let items = ComposerDownList.items(resume: r, templates: [t], projects: [], expanded: [])
        #expect(items == [
            .header(.resume), .row(.resume, r[0]), .row(.resume, r[1]), .row(.resume, r[2]),
            .showMore(.resume, hidden: 2),
            .header(.templates), .row(.templates, t),
        ])
        #expect(ComposerDownList.keyboardIDs(items) == [r[0], r[1], r[2], ComposerDownList.showMoreID(for: .resume), t],
                "Show more is a real stop between the sections")
    }

    @Test func expandingRevealsEveryRowInPlace() {
        let r = (0..<5).map { _ in UUID() }, t = UUID()
        let items = ComposerDownList.items(resume: r, templates: [t], projects: [], expanded: [.resume])
        #expect(ComposerDownList.keyboardIDs(items) == r + [t])
        #expect(ComposerDownList.firstRevealed(in: r) == r[3])
        #expect(ComposerDownList.firstRevealed(in: Array(r.prefix(3))) == nil)
    }

    @Test func showMoreIsAButtonNamedForItsSection() {
        #expect(ComposerDownList.showMoreAccessibilityLabel(section: .templates, hidden: 2) == "Show 2 more templates")
        #expect(ComposerDownList.showMoreAccessibilityLabel(section: .projects, hidden: 4) == "Show 4 more projects")
        #expect(ComposerDownList.showMoreAccessibilityLabel(section: .resume, hidden: 1) == "Show 1 more past sessions")
        for section in ComposerDownList.Section.allCases {
            #expect(ComposerDownList.showMoreSection(for: ComposerDownList.showMoreID(for: section)) == section)
        }
    }

    @Test func reopeningAndTypingCollapseEverySection() {
        var state = ComposerResumeState()
        state.expand(.resume, selecting: nil)
        #expect(state.expandedSections == [.resume])
        state.collapseSections()
        #expect(state.expandedSections.isEmpty)
        state.expand(.templates, selecting: nil)
        state.reset()
        #expect(state.expandedSections.isEmpty)
    }
}

@MainActor
@Suite("Composer ↓ list: show more (hosted)")
struct ComposerDownShowMoreHostedTests {
    private let now = Date()

    private struct Mounted {
        let window: NSWindow
        let hosting: NSView
        let field: NSTextView
        let composerStore: SessionComposerStore
        let sessions: [AgentSession]
    }

    /// Five past sessions (newest first: s0…s4), the default templates,
    /// two projects.
    private func mount(relaunch: @escaping (AgentSession, SessionCoordinator.RelaunchMode) -> Void) throws -> Mounted {
        let current = Project(name: "atlas-api", rootPath: "/tmp/composer-show-more-\(UUID().uuidString)")
        let other = Project(name: "device-frame", rootPath: "/tmp/composer-show-more-df-\(UUID().uuidString)")
        let sessions = (0..<5).map { i in
            AgentSession(
                name: "s\(i)", templateId: AgentTemplate.claudeCode.id, projectId: current.id,
                lastActiveAt: now.addingTimeInterval(-Double(i + 1) * 3_600),
                lastOutputAt: now.addingTimeInterval(-Double(i + 1) * 3_600), isNamePinned: true
            )
        }
        let store = WorkspaceStore(testingProjects: [current, other], testingSessions: sessions)
        let composerStore = SessionComposerStore(isolatedForTesting: ())
        let tuning = try #require(UserDefaults(suiteName: "ghostties.composerShowMore.\(UUID().uuidString)"))
        tuning.set(ComposerResumeLayout.list.rawValue, forKey: ComposerResumeLayout.storageKey)

        let palette = SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(projectBinding: .prefilled(current)),
            composerStore: composerStore,
            tuningDefaultsForTesting: tuning,
            resumeRelaunchForTesting: relaunch,
            nowForTesting: now
        )
        .environmentObject(store)
        .environmentObject(SessionCoordinator())

        let size = NSSize(width: 900, height: 900)
        let hosting = NSHostingView(rootView: palette.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        settle(hosting)
        let field = try #require(ComposerResumeHostedTests.textView(in: hosting), "composer field not found")
        return Mounted(window: window, hosting: hosting, field: field, composerStore: composerStore, sessions: sessions)
    }

    private func settle(_ view: NSView) {
        for _ in 0..<4 {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
    }

    private func press(_ selector: Selector, times: Int = 1, in m: Mounted) {
        for _ in 0..<times {
            m.field.doCommand(by: selector)
            settle(m.hosting)
        }
    }

    /// Every scroll view under the palette except the field's own.
    private func listScrollViews(in m: Mounted) -> [NSScrollView] {
        func walk(_ view: NSView) -> [NSScrollView] {
            var found: [NSScrollView] = []
            if let scroll = view as? NSScrollView { found.append(scroll) }
            for sub in view.subviews { found += walk(sub) }
            return found
        }
        return walk(m.hosting).filter { $0 !== m.field.enclosingScrollView }
    }

    private static let down = #selector(NSResponder.moveDown(_:))
    private static let up = #selector(NSResponder.moveUp(_:))
    private static let enter = #selector(NSResponder.insertNewline(_:))

    /// ↓ to "Show 2 more", Return: RESUME expands in place and the
    /// highlight sits on the first revealed row (s3), so Return resumes it.
    @Test func showMoreByKeyboardExpandsAndLandsOnTheFirstRevealedRow() throws {
        var relaunched: [UUID] = []
        let m = try mount { session, _ in relaunched.append(session.id) }
        defer { m.window.orderOut(nil) }
        m.composerStore.dispatchOverrideForTesting = { _, _ in }

        press(Self.down, times: 4, in: m)   // s0, s1, s2, Show 2 more
        press(Self.enter, in: m)
        #expect(relaunched.isEmpty, "Show more expands; it resumes nothing")
        press(Self.enter, in: m)
        #expect(relaunched == [m.sessions[3].id], "the highlight is on the first revealed row")
    }

    /// After expanding, ↓/↑ walk on without a gap: s3 → s4 → back up to s2.
    @Test func traversalStaysContinuousAfterExpanding() throws {
        var relaunched: [UUID] = []
        let m = try mount { session, _ in relaunched.append(session.id) }
        defer { m.window.orderOut(nil) }

        press(Self.down, times: 4, in: m)
        press(Self.enter, in: m)            // expanded, on s3
        press(Self.down, in: m)             // s4
        press(Self.up, times: 2, in: m)     // s3, s2
        press(Self.enter, in: m)
        #expect(relaunched == [m.sessions[2].id])
    }

    /// One scroll view for the whole list — no section scrolls on its own —
    /// and walking to the bottom and back scrolls it to keep the highlight
    /// in view.
    @Test func theListScrollsAsOneAndKeepsTheHighlightVisible() throws {
        let m = try mount { _, _ in }
        defer { m.window.orderOut(nil) }

        press(Self.down, times: 4, in: m)
        press(Self.enter, in: m)            // RESUME expanded: 5 rows + TEMPLATES + PROJECTS
        let scrolls = listScrollViews(in: m)
        #expect(scrolls.count == 1, "exactly one scroll view under the list, found \(scrolls.count)")
        let scroll = try #require(scrolls.first)
        let documentHeight = try #require(scroll.documentView).frame.height
        #expect(documentHeight > scroll.contentView.bounds.height + 1, "the fixture overflows the cap")

        let document = try #require(scroll.documentView)
        /// Distance of the visible rect from the document's top / bottom edge.
        func fromTop(_ r: NSRect) -> CGFloat { document.isFlipped ? r.minY : documentHeight - r.maxY }
        func fromBottom(_ r: NSRect) -> CGFloat { document.isFlipped ? documentHeight - r.maxY : r.minY }

        press(Self.down, times: 20, in: m)  // clamps on the last row
        let bottom = scroll.contentView.documentVisibleRect
        #expect(fromBottom(bottom) < 2, "scrolled to the highlighted last row: \(bottom) of \(documentHeight)")

        press(Self.up, times: 20, in: m)    // back to the first row
        let top = scroll.contentView.documentVisibleRect
        #expect(fromTop(top) < 2, "scrolled back to the first row: \(top) of \(documentHeight)")
    }
}

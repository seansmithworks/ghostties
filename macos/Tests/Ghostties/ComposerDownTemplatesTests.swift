import AppKit
import SwiftUI
import Testing
import GhosttiesCore
@testable import Ghostty

/// Sean, 2026-10-08: "↓ opens Resume — what about templates too". In A5 the
/// ↓ list shows RESUME then TEMPLATES, both filtered by the typed text, and
/// ↓/↑ walk them as one list. Return on a template row starts it through the
/// composer's own start path; Return on a resume row still resumes.
///
/// All fixture data is synthetic — public repo.
@Suite("Composer ↓ list: sections")
struct ComposerDownListSectionTests {
    @Test func resumeComesBeforeTemplatesAndEmptySectionsAreOmitted() {
        #expect(ComposerDownList.sections(resumeCount: 2, templateCount: 3) == [.resume, .templates])
        #expect(ComposerDownList.sections(resumeCount: 0, templateCount: 3) == [.templates])
        #expect(ComposerDownList.sections(resumeCount: 2, templateCount: 0) == [.resume])
        #expect(ComposerDownList.sections(resumeCount: 0, templateCount: 0) == [.resume], "RESUME holds the empty state")
    }

    @Test func keyboardOrderIsResumeThenTemplates() {
        let r1 = UUID(), r2 = UUID(), t1 = UUID()
        #expect(ComposerDownList.rowIDs(resume: [r1, r2], templates: [t1]) == [r1, r2, t1])
    }

    @Test func eachSectionScrollsWithinAShorterCapWhenBothShow() {
        #expect(ComposerDownList.cap(sectionCount: 1) == 5)
        #expect(ComposerDownList.cap(sectionCount: 2) == 3)
    }

    /// VoiceOver's name for the ↓ list covers both halves whenever
    /// TEMPLATES shows (the view passes `sections.contains(.templates)`).
    @Test func listIsNamedForWhatItHolds() {
        let resumeOnly = ComposerDownList.sections(resumeCount: 2, templateCount: 0)
        let both = ComposerDownList.sections(resumeCount: 2, templateCount: 3)
        let templatesOnly = ComposerDownList.sections(resumeCount: 0, templateCount: 3)
        #expect(ComposerResumeListView.accessibilityLabel(hasTemplates: resumeOnly.contains(.templates)) == "Resume a past session")
        #expect(ComposerResumeListView.accessibilityLabel(hasTemplates: both.contains(.templates)) == "Resume or start a session")
        #expect(ComposerResumeListView.accessibilityLabel(hasTemplates: templatesOnly.contains(.templates)) == "Resume or start a session")
    }

    @Test func downWalksIntoTemplatesAndUpWalksBack() {
        let r = UUID(), t1 = UUID(), t2 = UUID()
        let rows = ComposerDownList.rowIDs(resume: [r], templates: [t1, t2])
        var state = ComposerResumeState()
        #expect(state.handle(.down, layout: .list, rowIDs: rows) == .handled)
        #expect(state.selection(in: rows) == r)
        _ = state.handle(.down, layout: .list, rowIDs: rows)
        #expect(state.handle(.submit, layout: .list, rowIDs: rows) == .resume(t1))
        _ = state.handle(.up, layout: .list, rowIDs: rows)
        #expect(state.selection(in: rows) == r)
    }
}

/// The palette mounted with isolated stores, driven through the field's
/// own `doCommand(by:)`.
@MainActor
@Suite("Composer ↓ list: hosted palette")
struct ComposerDownTemplatesHostedTests {
    private let now = Date()

    private struct Mounted {
        let window: NSWindow
        let field: NSTextView
        let composerStore: SessionComposerStore
        let project: Project
        let store: WorkspaceStore
        let newest: AgentSession
        let codexReview: AgentSession
    }

    private func mount(relaunch: @escaping (AgentSession, SessionCoordinator.RelaunchMode) -> Void) throws -> Mounted {
        let project = Project(name: "atlas-api", rootPath: "/tmp/composer-down-templates-\(UUID().uuidString)")
        let newest = AgentSession(
            name: "rate limits", templateId: AgentTemplate.claudeCode.id, projectId: project.id,
            lastActiveAt: now.addingTimeInterval(-7_200), lastOutputAt: now.addingTimeInterval(-7_200),
            isNamePinned: true, resume: AgentResume(agent: .claude, sessionId: "fixture-rate-limits")
        )
        let codexReview = AgentSession(
            name: "codex review", templateId: AgentTemplate.codex.id, projectId: project.id,
            lastActiveAt: now.addingTimeInterval(-18_000), lastOutputAt: now.addingTimeInterval(-18_000),
            isNamePinned: true
        )
        let store = WorkspaceStore(testingProjects: [project], testingSessions: [codexReview, newest])
        let composerStore = SessionComposerStore(isolatedForTesting: ())
        let tuning = try #require(UserDefaults(suiteName: "ghostties.composerDownTemplates.\(UUID().uuidString)"))
        tuning.set(ComposerResumeLayout.list.rawValue, forKey: ComposerResumeLayout.storageKey)

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
        let field = try #require(ComposerResumeHostedTests.textView(in: hosting), "composer field not found")
        return Mounted(window: window, field: field, composerStore: composerStore, project: project, store: store,
                       newest: newest, codexReview: codexReview)
    }

    private func settle(_ view: NSView) {
        for _ in 0..<3 {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
    }

    private func press(_ selector: Selector, times: Int = 1, in m: Mounted) {
        for _ in 0..<times {
            m.field.doCommand(by: selector)
            settle(m.window.contentView!)
        }
    }

    private func type(_ text: String, in m: Mounted) {
        m.composerStore.searchText = text
        settle(m.window.contentView!)
    }

    private static let down = #selector(NSResponder.moveDown(_:))
    private static let up = #selector(NSResponder.moveUp(_:))
    private static let enter = #selector(NSResponder.insertNewline(_:))

    /// TEMPLATES lists the composer's own template order, pinned first, so
    /// the first template row is the pinned template, not the resolver's
    /// first (which a pin outranks).
    @Test func returnOnTheFirstTemplateRowStartsItThroughTheComposersStartPath() throws {
        var relaunched = 0
        var started: [AgentTemplate] = []
        let m = try mount { _, _ in relaunched += 1 }
        defer { m.window.orderOut(nil) }
        m.composerStore.dispatchOverrideForTesting = { _, template in started.append(template) }
        let resolverFirst = try #require(SessionTemplateResolver.templates(for: m.project, store: m.store).first)
        let pinned = try #require(SessionTemplateResolver.templates(for: m.project, store: m.store).last)
        try #require(pinned.id != resolverFirst.id, "the pin must be a template the resolver doesn't put first")
        m.composerStore.togglePin(templateId: pinned.id)
        settle(m.window.contentView!)
        let firstInTemplatesOrder = try #require(m.composerStore.pinnedTemplateIds.first)

        // Two resume rows, then the first template row.
        press(Self.down, times: 3, in: m)
        press(Self.enter, in: m)

        #expect(started.map(\.id) == [firstInTemplatesOrder], "TEMPLATES follows the two RESUME rows, pinned first")
        #expect(relaunched == 0)
    }

    @Test func returnOnAResumeRowStillResumes() throws {
        var relaunched: [UUID] = []
        var started = 0
        let m = try mount { session, _ in relaunched.append(session.id) }
        defer { m.window.orderOut(nil) }
        m.composerStore.dispatchOverrideForTesting = { _, _ in started += 1 }

        // Into TEMPLATES and back up to the second resume row.
        press(Self.down, times: 3, in: m)
        press(Self.up, in: m)
        press(Self.enter, in: m)

        #expect(relaunched == [m.codexReview.id])
        #expect(started == 0)
    }

    @Test func typingFiltersBothSections() throws {
        var relaunched: [UUID] = []
        var started: [AgentTemplate] = []
        let m = try mount { session, _ in relaunched.append(session.id) }
        defer { m.window.orderOut(nil) }
        m.composerStore.dispatchOverrideForTesting = { _, template in started.append(template) }

        type("codex", in: m)
        press(Self.down, in: m)
        press(Self.enter, in: m)
        #expect(relaunched == [m.codexReview.id], "RESUME narrows to the matching session")

        let m2 = try mount { session, _ in relaunched.append(session.id) }
        defer { m2.window.orderOut(nil) }
        m2.composerStore.dispatchOverrideForTesting = { _, template in started.append(template) }
        type("codex", in: m2)
        // One resume row, then TEMPLATES narrowed to Codex alone: ↓ clamps on it.
        press(Self.down, times: 6, in: m2)
        press(Self.enter, in: m2)
        #expect(started.map(\.id) == [AgentTemplate.codex.id], "TEMPLATES narrows to the matching template")
        #expect(relaunched == [m.codexReview.id])
    }

    @Test func aQueryNoSessionMatchesOpensStraightOntoTemplates() throws {
        var relaunched = 0
        var started: [AgentTemplate] = []
        let m = try mount { _, _ in relaunched += 1 }
        defer { m.window.orderOut(nil) }
        m.composerStore.dispatchOverrideForTesting = { _, template in started.append(template) }

        type("shell", in: m)
        press(Self.down, in: m)
        press(Self.enter, in: m)

        #expect(started.map(\.id) == [AgentTemplate.shell.id], "an empty RESUME is omitted, TEMPLATES leads")
        #expect(relaunched == 0)
    }
}

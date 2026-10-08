import AppKit
import SwiftUI
import Testing
import GhosttiesCore
@testable import Ghostty

/// Beta.26 bug: with a project named "Code", typing "Code" into the A5
/// one-line composer showed nothing — no ghost, no project row — so the
/// project was unreachable by typing. The single word tied "Codex"
/// (a template, exact prefix) and the template, ranked first, took the
/// highlight; the ghost then previewed a template path "Code" isn't a
/// prefix of, and A5's ↓ list had no PROJECTS section to fall back on.
///
/// All fixture data is synthetic — public repo.
@MainActor
@Suite("Composer ↓ list: projects (hosted)")
struct ComposerDownProjectsHostedTests {
    private let now = Date()

    private struct Mounted {
        let window: NSWindow
        let field: NSTextView
        let composerStore: SessionComposerStore
        let current: Project
        let code: Project
        let repo: Project
    }

    private func mount(relaunch: @escaping (AgentSession, SessionCoordinator.RelaunchMode) -> Void = { _, _ in }) throws -> Mounted {
        let current = Project(name: "atlas-api", rootPath: "/tmp/composer-down-projects-atlas-\(UUID().uuidString)")
        let code = Project(name: "Code", rootPath: "/tmp/composer-down-projects-code-\(UUID().uuidString)")
        let repo = Project(name: "repo", rootPath: "/tmp/composer-down-projects-repo-\(UUID().uuidString)")
        let past = AgentSession(
            name: "rate limits", templateId: AgentTemplate.claudeCode.id, projectId: current.id,
            lastActiveAt: now.addingTimeInterval(-7_200), lastOutputAt: now.addingTimeInterval(-7_200),
            isNamePinned: true
        )
        let store = WorkspaceStore(testingProjects: [current, code, repo], testingSessions: [past])
        let composerStore = SessionComposerStore(isolatedForTesting: ())
        let tuning = try #require(UserDefaults(suiteName: "ghostties.composerDownProjects.\(UUID().uuidString)"))
        tuning.set(ComposerResumeLayout.list.rawValue, forKey: ComposerResumeLayout.storageKey)

        let palette = SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(projectBinding: .prefilled(current)),
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
        return Mounted(window: window, field: field, composerStore: composerStore, current: current, code: code, repo: repo)
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

    /// A keystroke's path: the field's own `insertText`.
    private func type(_ text: String, in m: Mounted) {
        m.field.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        settle(m.window.contentView!)
    }

    private func ghost(_ m: Mounted) -> String {
        (m.field as? ComposerGhostNSTextView)?.currentGhostText ?? ""
    }

    private static let down = #selector(NSResponder.moveDown(_:))
    private static let up = #selector(NSResponder.moveUp(_:))
    private static let enter = #selector(NSResponder.insertNewline(_:))
    private static let tab = #selector(NSResponder.insertTab(_:))

    /// The bug, end to end: "Code" ghosts the project, and ↓ walks to a
    /// PROJECTS row whose Return selects the project the way a project row
    /// always has (`selectProject`: project set, field cleared).
    @Test func typingAProjectNameGhostsItAndTheDownListReachesIt() throws {
        var started = 0
        let m = try mount()
        defer { m.window.orderOut(nil) }
        m.composerStore.dispatchOverrideForTesting = { _, _ in started += 1 }

        type("Code", in: m)
        #expect(ghost(m).hasPrefix(" > "), "the ghost continues the project's path: \"\(ghost(m))\"")

        // RESUME has nothing for "Code"; TEMPLATES (Codex, Claude Code) then
        // PROJECTS. ↓ clamps on the last row: the Code project.
        press(Self.down, times: 8, in: m)
        press(Self.enter, in: m)

        #expect(m.composerStore.selectedProjectId == m.code.id, "Return on the PROJECTS row selects Code")
        #expect(m.composerStore.searchText.isEmpty, "selecting a project clears the field, as it always has")
        #expect(started == 0, "selecting a project starts nothing")
    }

    /// Control for the root cause: a project's full name with no template
    /// sharing its prefix ("repo") ghosts fine — a full-name match is not
    /// what suppressed the ghost; the tie with the "Codex" template was.
    @Test func aFullProjectNameNoTemplateSharesGhostsItsPath() throws {
        let m = try mount()
        defer { m.window.orderOut(nil) }
        type("repo", in: m)
        #expect(ghost(m).hasPrefix(" > "), "full name ghosts the path: \"\(ghost(m))\"")
    }

    /// Every casing and length of the colliding name ghosts the project.
    @Test(arguments: ["Code", "code", "Cod", "co"])
    func everyPrefixOfACollidingNameGhostsTheProject(_ typed: String) throws {
        let m = try mount()
        defer { m.window.orderOut(nil) }
        type(typed, in: m)
        let expected = String("Code".dropFirst(typed.count)) + " > "
        #expect(ghost(m).hasPrefix(expected), "\(typed) ghosts the project: \"\(ghost(m))\"")
    }

    /// The ↓ order is RESUME → TEMPLATES → PROJECTS: one ↑ from the
    /// project row lands on the last template, not on a resume row.
    @Test func downOrderIsResumeThenTemplatesThenProjects() throws {
        var relaunched = 0
        var started: [AgentTemplate] = []
        let m = try mount { _, _ in relaunched += 1 }
        defer { m.window.orderOut(nil) }
        m.composerStore.dispatchOverrideForTesting = { _, template in started.append(template) }

        // "co" matches no session; templates Codex + Claude Code; projects Code.
        type("co", in: m)
        press(Self.down, times: 8, in: m)
        press(Self.up, in: m)
        press(Self.enter, in: m)

        #expect(started.count == 1, "one ↑ from PROJECTS lands in TEMPLATES")
        #expect(m.composerStore.selectedProjectId != m.code.id)
        #expect(relaunched == 0)
    }

    /// The `repo cco` idiom by Tab: `cod` + Tab completes the project name
    /// with a trailing space (never a chevron), and the command that
    /// follows starts in that project with the list closed.
    @Test func ghostCompletesTheProjectNameAndTabEndsOnASpace() throws {
        var started: [(Project, AgentTemplate)] = []
        let m = try mount()
        defer { m.window.orderOut(nil) }
        m.composerStore.dispatchOverrideForTesting = { project, template in started.append((project, template)) }

        type("cod", in: m)
        #expect(ghost(m).hasPrefix("e > "), "the ghost completes the project name: \"\(ghost(m))\"")
        press(Self.tab, in: m)
        #expect(m.field.string == "code ", "Tab completes the name and ends on a space: \"\(m.field.string)\"")

        type(#"cco -n "x""#, in: m)
        press(Self.enter, in: m)

        #expect(started.map(\.0.id) == [m.code.id], "the command starts in the completed project")
        #expect(started.first?.1.buildCommand() == #"'cco' '-n' 'x'"#)
    }

    /// Sean's idiom with the list closed, unchanged: `repo cco -n "x"`
    /// starts `cco -n x` in `repo`.
    @Test func projectPrefixedCommandWithTheListClosedIsUnchanged() throws {
        var started: [(Project, AgentTemplate)] = []
        var relaunched = 0
        let m = try mount { _, _ in relaunched += 1 }
        defer { m.window.orderOut(nil) }
        m.composerStore.dispatchOverrideForTesting = { project, template in started.append((project, template)) }

        type(#"repo cco -n "x""#, in: m)
        press(Self.enter, in: m)

        #expect(started.map(\.0.id) == [m.repo.id])
        #expect(started.first?.1.buildCommand() == #"'cco' '-n' 'x'"#)
        #expect(relaunched == 0)
    }

    /// A leading "/" is not a path feature: "/Code" matches no project, so
    /// no project ghost and no PROJECTS row. It doesn't break the field.
    @Test func aLeadingSlashIsNoProjectMatch() throws {
        var started = 0
        let m = try mount()
        defer { m.window.orderOut(nil) }
        m.composerStore.dispatchOverrideForTesting = { _, _ in started += 1 }

        type("/Code", in: m)
        #expect(m.field.string == "/Code")
        #expect(!ghost(m).hasPrefix(" > Default"), "no project ghost for /Code: \"\(ghost(m))\"")
        press(Self.down, times: 8, in: m)
        press(Self.enter, in: m)
        #expect(m.composerStore.selectedProjectId != m.code.id, "no PROJECTS row for /Code")
    }
}

@Suite("Composer ↓ list: projects (model)")
struct ComposerDownProjectsModelTests {
    @Test func projectsFollowTemplatesAndEmptySectionsAreOmitted() {
        #expect(ComposerDownList.sections(resumeCount: 1, templateCount: 2, projectCount: 3) == [.resume, .templates, .projects])
        #expect(ComposerDownList.sections(resumeCount: 0, templateCount: 0, projectCount: 3) == [.projects])
        #expect(ComposerDownList.sections(resumeCount: 0, templateCount: 0, projectCount: 0) == [.resume])
        let r = UUID(), t = UUID(), p = UUID()
        #expect(ComposerDownList.rowIDs(resume: [r], templates: [t], projects: [p]) == [r, t, p])
    }

    private func option(_ title: String, id: UUID = UUID()) -> ComposerOption {
        ComposerOption(id: id, title: title, subtitle: nil, leadingIcon: nil, action: {})
    }

    @Test func aSingleWordPrefixingAProjectHighlightsIt() {
        let codex = option("Codex"), code = option("Code")
        let options = [codex, code]
        let ids: Set<UUID> = [code.id]
        #expect(SessionComposerPalette.projectWordIndex(in: options, projectIds: ids, rawQuery: "cod", currentProjectName: "atlas-api") == 1)
        #expect(SessionComposerPalette.projectWordIndex(in: options, projectIds: ids, rawQuery: "Code", currentProjectName: nil) == 1)
        #expect(SessionComposerPalette.projectWordIndex(in: options, projectIds: ids, rawQuery: "code ", currentProjectName: nil) == nil, "past the first word")
        #expect(SessionComposerPalette.projectWordIndex(in: options, projectIds: ids, rawQuery: "codex", currentProjectName: nil) == nil, "no project prefix")
        #expect(SessionComposerPalette.projectWordIndex(in: options, projectIds: ids, rawQuery: "cod", currentProjectName: "Code") == nil, "the current project already ghosts")
    }
}

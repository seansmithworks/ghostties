import AppKit
import SwiftUI
import Testing
import GhosttiesCore
@testable import Ghostty

/// Template management moved from the deleted composer popover's results
/// table into `ProjectSettingsView`'s Templates section. These cover every
/// action the table had: create, edit, duplicate, pin/unpin, delete.
@MainActor
struct ProjectTemplatesSectionTests {

    private func makeStore() -> WorkspaceStore {
        WorkspaceStore(testingProjects: [Project(name: "Demo", rootPath: "/tmp/templates-\(UUID().uuidString)")], testingSessions: [])
    }

    private func titles(_ actions: [TemplateManagement.Action?]) -> [String] {
        actions.compactMap { $0?.title }
    }

    // MARK: - Menu content per group (ported from ComposerRow.templateContextMenu)

    @Test func userTemplateGetsEditDuplicateDelete() {
        let template = AgentTemplate(name: "Mine", kind: .custom)
        let actions = TemplateManagement.actions(for: template, isPinned: false)
        #expect(titles(actions) == ["Pin", "Edit...", "Duplicate", "Delete"])
    }

    @Test func pinnedTemplateOffersUnpin() {
        let template = AgentTemplate(name: "Mine", kind: .custom)
        #expect(titles(TemplateManagement.actions(for: template, isPinned: true)).first == "Unpin")
    }

    @Test func builtInTemplateCanOnlyBeDuplicatedAndEditedNeverDeleted() {
        let actions = TemplateManagement.actions(for: AgentTemplate.shell, isPinned: false)
        #expect(titles(actions) == ["Pin", "Duplicate and Edit..."])
    }

    @Test func presetWithADescriptionOffersItsFile() {
        var preset = AgentTemplate(name: "Preset", kind: .custom, templateDescription: "From a file")
        preset.isDefault = true
        #expect(titles(TemplateManagement.actions(for: preset, isPinned: false)) == ["Pin", "Duplicate and Edit...", "Edit Preset File..."])
    }

    // MARK: - Store-backed actions

    @Test func newTemplateIsTrimmedAndAddedAsCustom() {
        let store = makeStore()
        let before = store.templates.count
        let template = TemplateManagement.addTemplate(named: "  Fresh  ", store: store)
        #expect(template?.name == "Fresh")
        #expect(template?.kind == .custom)
        #expect(store.templates.count == before + 1)
    }

    @Test func blankNewTemplateNameIsIgnored() {
        let store = makeStore()
        let before = store.templates.count
        #expect(TemplateManagement.addTemplate(named: "   ", store: store) == nil)
        #expect(store.templates.count == before)
    }

    @Test func duplicateAndDeleteGoThroughTheStore() {
        let store = makeStore()
        let original = TemplateManagement.addTemplate(named: "Mine", store: store)!
        let copy = store.duplicateTemplate(id: original.id)
        #expect(copy?.name == "Copy of Mine")
        store.removeTemplate(id: copy!.id)
        #expect(!store.templates.contains { $0.id == copy!.id })
        #expect(store.templates.contains { $0.id == original.id })
    }

    @Test func deleteMessageWarnsOnlyWhenSessionsUseTheTemplate() {
        let store = makeStore()
        let template = TemplateManagement.addTemplate(named: "Mine", store: store)!
        #expect(TemplateManagement.deleteMessage(for: template, store: store) == "This will permanently remove \"Mine\".")
    }

    @Test func deleteMessageNamesTheSessionsUsingTheTemplate() {
        let store = makeStore()
        let template = TemplateManagement.addTemplate(named: "Mine", store: store)!
        let other = TemplateManagement.addTemplate(named: "Other", store: store)!
        let project = store.projects[0]
        let users = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon"].map {
            AgentSession(name: $0, templateId: template.id, projectId: project.id)
        }
        let bystander = AgentSession(name: "Zulu", templateId: other.id, projectId: project.id)
        let two = WorkspaceStore(testingProjects: [project], testingSessions: [users[0], users[1], bystander])
        let twoMessage = TemplateManagement.deleteMessage(for: template, store: two)
        #expect(twoMessage.contains("Alpha, Beta."))
        #expect(!twoMessage.contains("Zulu"))

        let five = WorkspaceStore(testingProjects: [project], testingSessions: users + [bystander])
        let message = TemplateManagement.deleteMessage(for: template, store: five)
        #expect(message.contains("Alpha, Beta, Gamma and 2 more."))
        #expect(!message.contains("Delta"))
        #expect(message.contains("\"Mine\""))
    }

    @Test func confirmingDeleteDropsTheTemplateCountByOne() {
        let store = makeStore()
        let template = TemplateManagement.addTemplate(named: "Mine", store: store)!
        let before = store.templates.count
        store.removeTemplate(id: template.id)
        #expect(store.templates.count == before - 1)
    }

    @Test func pinTogglesThroughTheComposerStore() {
        let composerStore = SessionComposerStore(isolatedForTesting: ())
        let id = UUID()
        composerStore.togglePin(templateId: id)
        #expect(composerStore.pinnedTemplateIds.contains(id))
        composerStore.togglePin(templateId: id)
        #expect(!composerStore.pinnedTemplateIds.contains(id))
    }

    // MARK: - The section is mounted in the settings popover

    private func fittingHeight<V: View>(_ view: V, store: WorkspaceStore) -> CGFloat {
        let hosting = NSHostingView(rootView: view.environmentObject(store))
        return hosting.fittingSize.height
    }

    /// Fails if `ProjectSettingsView` stops mounting the Templates section:
    /// the section's list hugs its rows (up to a cap), so adding templates
    /// to the store must make the popover taller. Without the section the
    /// popover height is independent of the template count.
    @Test func settingsPopoverMountsTheTemplatesSection() {
        let store = makeStore()
        let project = store.projects[0]
        let before = fittingHeight(ProjectSettingsView(project: project, onDismiss: {}), store: store)
        _ = TemplateManagement.addTemplate(named: "One", store: store)
        _ = TemplateManagement.addTemplate(named: "Two", store: store)
        let after = fittingHeight(ProjectSettingsView(project: project, onDismiss: {}), store: store)
        #expect(after > before, "popover should grow with the template list: \(before) -> \(after)")
    }

    // MARK: - Evidence renders (light + dark) under .captures/

    private func capturesDirectory() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url.appendingPathComponent(".captures", isDirectory: true)
    }

    @Test(arguments: ["aqua", "darkAqua"])
    func rendersSettingsPopoverWithTemplatesSection(appearance: String) {
        let store = makeStore()
        _ = TemplateManagement.addTemplate(named: "Review pass", store: store)
        let project = store.projects[0]
        let name: NSAppearance.Name = appearance == "darkAqua" ? .darkAqua : .aqua
        let view = ProjectSettingsView(project: project, onDismiss: {})
            .environmentObject(store)
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: name)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("no bitmap rep"); return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("no png"); return
        }
        let dir = capturesDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? png.write(to: dir.appendingPathComponent("project-settings-templates-\(appearance).png"))
        #expect(size.height > 300)
    }
}

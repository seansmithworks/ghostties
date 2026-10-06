import SwiftUI
import GhosttiesCore

/// Template management, hosted in `ProjectSettingsView`. These actions used
/// to live in the composer popover's results table; the centered
/// single-line composer has no list, so this section is now the only place
/// templates are created, edited, duplicated, pinned and deleted.
///
/// Templates are GLOBAL (`WorkspaceStore.templates`), not per project, so
/// every change here applies immediately to the store (and to every other
/// project) — it is NOT staged behind the settings popover's Save/Cancel,
/// which only governs this project's icon, name and default template. That
/// is the same immediate-apply behavior the deleted results table had.
enum TemplateManagement {

    /// One entry in a template row's "…" / context menu.
    enum Action: Equatable {
        case togglePin(isPinned: Bool)
        case edit
        case duplicate
        case duplicateAndEdit
        case editPresetFile
        case delete

        var title: String {
            switch self {
            case .togglePin(let isPinned): return isPinned ? "Unpin" : "Pin"
            case .edit: return "Edit..."
            case .duplicate: return "Duplicate"
            case .duplicateAndEdit: return "Duplicate and Edit..."
            case .editPresetFile: return "Edit Preset File..."
            case .delete: return "Delete"
            }
        }
    }

    /// Menu content per template group, ported from the deleted
    /// `ComposerRow.templateContextMenu`: presets and built-ins are
    /// read-only (duplicate to change them), user templates are fully
    /// editable. A `nil` separator is a divider.
    @MainActor
    static func actions(for template: AgentTemplate, isPinned: Bool) -> [Action?] {
        var result: [Action?] = [.togglePin(isPinned: isPinned), nil]
        switch SessionTemplateResolver.group(for: template) {
        case .preset:
            result.append(.duplicateAndEdit)
            if template.templateDescription != nil { result.append(.editPresetFile) }
        case .builtin:
            result.append(.duplicateAndEdit)
        case .user:
            result.append(contentsOf: [.edit, .duplicate, nil, .delete])
        }
        return result
    }

    /// "New template": trims the typed name, ignores an empty one, and adds
    /// a name-only `.custom` template. The caller opens it in
    /// `TemplateEditForm` with `isNewlyCreated: true`, which deletes it again
    /// if the form is abandoned (so no empty junk template persists).
    @MainActor
    static func addTemplate(named raw: String, store: WorkspaceStore) -> AgentTemplate? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return store.addTemplate(AgentTemplate(name: trimmed, kind: .custom))
    }

    /// Preset files live at `~/.ghostties/presets/<slug>.md`; the resolved
    /// path must stay inside the presets directory.
    static func presetFileURL(for template: AgentTemplate) -> URL? {
        let filename = template.name.lowercased().replacingOccurrences(of: " ", with: "-") + ".md"
        let path = (PresetLoader.presetsDirectoryPath as NSString).appendingPathComponent(filename)
        let resolvedPath = (path as NSString).standardizingPath
        let presetsDir = (PresetLoader.presetsDirectoryPath as NSString).standardizingPath
        guard resolvedPath.hasPrefix(presetsDir + "/") else { return nil }
        guard FileManager.default.fileExists(atPath: resolvedPath) else { return nil }
        return URL(fileURLWithPath: resolvedPath)
    }

    /// The in-use delete alert names this many sessions, then "and N more".
    static let maxListedSessions = 3

    @MainActor
    static func deleteMessage(for template: AgentTemplate, store: WorkspaceStore) -> String {
        if store.templateInUse(id: template.id) {
            let names = store.sessions.filter { $0.templateId == template.id }.map(\.name)
            let listed = Array(names.prefix(maxListedSessions))
            var list = listed.dropLast().joined(separator: ", ")
            let last = listed.last ?? ""
            if names.count > maxListedSessions {
                list = listed.joined(separator: ", ") + " and \(names.count - maxListedSessions) more"
            } else {
                list += (list.isEmpty ? "" : " and ") + last
            }
            if list.hasSuffix(".") { list.removeLast() }
            return "Used by \(list). Sessions using \"\(template.name)\" will keep their current configuration but won't be relaunchable with this template."
        }
        return "This will permanently remove \"\(template.name)\"."
    }
}

struct ProjectTemplatesSection: View {
    @EnvironmentObject private var store: WorkspaceStore
    @ObservedObject private var composerStore: SessionComposerStore

    @State private var isAddingTemplate = false
    @State private var newTemplateName = ""
    @State private var templateToEdit: AgentTemplate?
    @State private var templateToEditIsFresh = false
    @State private var templateToDelete: AgentTemplate?
    @FocusState private var newTemplateNameFocused: Bool

    init(composerStore: SessionComposerStore = .shared) {
        self.composerStore = composerStore
    }

    private static let rowHeight: CGFloat = 28
    private static let listMaxHeight: CGFloat = 196

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Templates \u{00B7} shared across projects")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                // Hugs up to `listMaxHeight`, then scrolls — the template
                // list can run to a dozen rows and the popover must not.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(store.templates) { template in
                            row(for: template)
                        }
                    }
                }
                .frame(height: min(CGFloat(store.templates.count) * Self.rowHeight, Self.listMaxHeight))
                if isAddingTemplate {
                    newTemplateField
                } else {
                    newTemplateButton
                }
            }

            Text("Changes here apply immediately.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .sheet(item: $templateToEdit) { template in
            TemplateEditForm(template: template, isNewlyCreated: templateToEditIsFresh)
        }
        .alert(
            "Delete Template?",
            isPresented: Binding(
                get: { templateToDelete != nil },
                set: { if !$0 { templateToDelete = nil } }
            ),
            presenting: templateToDelete
        ) { template in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { store.removeTemplate(id: template.id) }
        } message: { template in
            Text(TemplateManagement.deleteMessage(for: template, store: store))
        }
        #if DEBUG
        .onAppear(perform: applyCaptureTemplateActionIfNeeded)
        #endif
    }

    #if DEBUG
    /// `GHOSTTIES_CAPTURE_PROJECT_SETTINGS=<project>:templates-edit|-delete`:
    /// what the row's "…" menu item does, on the first user template (the
    /// first template if none is user-created). A built-in's menu offers
    /// "Duplicate and Edit..." rather than "Edit...", so that is what runs
    /// for one; delete has no menu path on a built-in and opens the same
    /// alert directly.
    private func applyCaptureTemplateActionIfNeeded() {
        guard let hook = CaptureFixture.projectSettingsHook, hook.templateAction != .none,
              CaptureFixture.claimHook("templateAction") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard let template = store.templates.first(where: { SessionTemplateResolver.group(for: $0) == .user })
                ?? store.templates.first else { return }
            let offered = TemplateManagement.actions(for: template, isPinned: false)
            switch hook.templateAction {
            case .edit: perform(offered.contains(where: { $0 == .edit }) ? .edit : .duplicateAndEdit, on: template)
            case .delete: perform(.delete, on: template)
            case .none: break
            }
        }
    }
    #endif

    // MARK: - Rows

    private func row(for template: AgentTemplate) -> some View {
        let isPinned = composerStore.pinnedTemplateIds.contains(template.id)
        let actions = TemplateManagement.actions(for: template, isPinned: isPinned)
        return HStack(spacing: 6) {
            Text(template.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Pinned")
            }

            Menu {
                actionButtons(actions, for: template)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Actions for \(template.name)")
        }
        .frame(height: Self.rowHeight)
        .contentShape(Rectangle())
        .contextMenu { actionButtons(actions, for: template) }
    }

    @ViewBuilder
    private func actionButtons(_ actions: [TemplateManagement.Action?], for template: AgentTemplate) -> some View {
        ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
            if let action {
                Button(action.title, role: action == .delete ? .destructive : nil) {
                    perform(action, on: template)
                }
            } else {
                Divider()
            }
        }
    }

    private func perform(_ action: TemplateManagement.Action, on template: AgentTemplate) {
        switch action {
        case .togglePin:
            composerStore.togglePin(templateId: template.id)
        case .edit:
            templateToEditIsFresh = false
            templateToEdit = template
        case .duplicate:
            _ = store.duplicateTemplate(id: template.id)
        case .duplicateAndEdit:
            if let copy = store.duplicateTemplate(id: template.id) {
                templateToEditIsFresh = false
                templateToEdit = copy
            }
        case .editPresetFile:
            if let url = TemplateManagement.presetFileURL(for: template) {
                NSWorkspace.shared.open(url)
            }
        case .delete:
            templateToDelete = template
        }
    }

    // MARK: - New template

    private var newTemplateButton: some View {
        Button {
            newTemplateName = ""
            isAddingTemplate = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                Text("New template")
                    .font(.system(size: 13))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private var newTemplateField: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Template name", text: $newTemplateName)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($newTemplateNameFocused)
                .onSubmit { commitNewTemplate() }
                .onExitCommand { cancelNewTemplate() }
        }
        .frame(height: Self.rowHeight)
        .onAppear { DispatchQueue.main.async { newTemplateNameFocused = true } }
    }

    private func commitNewTemplate() {
        guard isAddingTemplate else { return }
        isAddingTemplate = false
        let name = newTemplateName
        newTemplateName = ""
        guard let template = TemplateManagement.addTemplate(named: name, store: store) else { return }
        templateToEditIsFresh = true
        templateToEdit = template
    }

    private func cancelNewTemplate() {
        isAddingTemplate = false
        newTemplateName = ""
    }
}

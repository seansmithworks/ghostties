import SwiftUI
import GhosttiesCore

/// Popover for editing a project's display name and default template, and for
/// managing the (global) templates. Save/Cancel covers the project fields only;
/// template changes apply immediately (see `ProjectTemplatesSection`). The
/// project's icon is set in the Settings window (`ProjectsSettingsPane`).
struct ProjectSettingsView: View {
    let project: Project
    var onDismiss: () -> Void

    @EnvironmentObject private var store: WorkspaceStore

    @State private var name: String
    @State private var defaultTemplateId: UUID?

    init(project: Project, onDismiss: @escaping () -> Void) {
        self.project = project
        self.onDismiss = onDismiss
        _name = State(initialValue: project.name)
        _defaultTemplateId = State(initialValue: project.defaultTemplateId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Name field
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Project name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
            }

            Divider()

            // Default template picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Default Template")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker("", selection: $defaultTemplateId) {
                    Text("Always ask").tag(nil as UUID?)
                    ForEach(store.templates) { template in
                        Text(template.name).tag(template.id as UUID?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            Divider()

            ProjectTemplatesSection()

            Divider()

            // Save / Cancel
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    onDismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
                Button("Save") {
                    save()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? project.name : trimmed
        store.updateProject(
            id: project.id,
            name: finalName,
            defaultTemplateId: defaultTemplateId
        )
        // If user picked "Always ask" (nil), explicitly clear the default template.
        if defaultTemplateId == nil {
            store.clearDefaultTemplate(for: project.id)
        }
        onDismiss()
    }
}

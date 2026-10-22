import SwiftUI
import GhosttiesCore

/// Popover for editing a project's display name and managing the (global)
/// templates. Save/Cancel covers the name only; template changes apply
/// immediately (see `ProjectTemplatesSection`). The project's icon and
/// new-session default are set in the Settings window (`ProjectsSettingsPane`).
struct ProjectSettingsView: View {
    let project: Project
    var onDismiss: () -> Void

    @EnvironmentObject private var store: WorkspaceStore

    @State private var name: String

    init(project: Project, onDismiss: @escaping () -> Void) {
        self.project = project
        self.onDismiss = onDismiss
        _name = State(initialValue: project.name)
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
        store.updateProject(id: project.id, name: finalName)
        onDismiss()
    }
}

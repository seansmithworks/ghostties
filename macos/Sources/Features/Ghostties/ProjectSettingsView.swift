import SwiftUI
import GhosttiesCore

/// Popover for editing a project's display name, ghost character, and default template.
struct ProjectSettingsView: View {
    let project: Project
    var onDismiss: () -> Void

    @EnvironmentObject private var store: WorkspaceStore

    @State private var name: String
    @State private var selectedGhost: GhostCharacter?
    @State private var defaultTemplateId: UUID?

    private let ghostColumns = Array(repeating: GridItem(.fixed(36), spacing: 8), count: 6)

    init(project: Project, onDismiss: @escaping () -> Void) {
        self.project = project
        self.onDismiss = onDismiss
        _name = State(initialValue: project.name)
        _selectedGhost = State(initialValue: project.ghostCharacter)
        _defaultTemplateId = State(initialValue: project.defaultTemplateId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Ghost picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Icon")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: ghostColumns, spacing: 8) {
                    ForEach(GhostCharacter.allCases, id: \.self) { ghost in
                        GhostCharacterView(
                            character: ghost,
                            color: selectedGhost == ghost ? Color.accentColor : .secondary
                        )
                        .frame(width: 20, height: 20)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedGhost == ghost ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedGhost = ghost
                        }
                        .accessibilityLabel(ghost.rawValue)
                        .accessibilityAddTraits(selectedGhost == ghost ? .isSelected : [])
                    }
                }
            }

            Divider()

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
            ghostCharacter: selectedGhost,
            defaultTemplateId: defaultTemplateId
        )
        // If user picked "Always ask" (nil), explicitly clear the default template.
        if defaultTemplateId == nil {
            store.clearDefaultTemplate(for: project.id)
        }
        onDismiss()
    }
}

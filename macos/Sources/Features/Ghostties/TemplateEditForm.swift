import SwiftUI
import UniformTypeIdentifiers
import GhosttiesCore

// MARK: - Template Edit Form

/// An inline sheet for editing a template's name, kind, agent configuration,
/// command, and environment variables.
///
/// The "Agent Configuration" section is only shown when `kind` is `.claudeCode`
/// or `.custom`, since `.shell` sessions have no AI config.
struct TemplateEditForm: View {
    let template: AgentTemplate

    /// True only for a template that was just created empty (name-only,
    /// `command: nil`, no agent config) and opened straight into this form
    /// to be configured — never for editing an already-configured template
    /// via the context menu's "Edit" action. Root cause of the persisted
    /// junk "New Template" rows found in production `workspace.json`
    /// (`docs/plans/session-creation-unified.html` finding D4, old
    /// `TemplatePickerView.addCustomTemplate()` flow): the record was
    /// added to the store BEFORE this form ran, so dismissing without
    /// ever hitting Save left an empty, unconfigured template behind
    /// forever. `didSave` + `onDisappear` below deletes it if abandoned —
    /// covers Cancel, Esc, and click-outside dismissal, not just the
    /// Cancel button.
    var isNewlyCreated: Bool = false

    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var didSave = false

    /// Pure decision, factored out so it's unit-testable without driving a
    /// real SwiftUI `.onDisappear` lifecycle event (this repo has no
    /// ViewInspector). True exactly when a freshly-created, still-empty
    /// template is being abandoned — Cancel, Esc, or a click outside the
    /// sheet all end up here via `onDisappear`, since `.dismiss()` alone
    /// can't distinguish "the user cancelled" from "the user saved".
    static func shouldDiscardOnDismiss(isNewlyCreated: Bool, didSave: Bool) -> Bool {
        isNewlyCreated && !didSave
    }

    // Basic fields
    @State private var name: String = ""
    @State private var kind: AgentTemplate.Kind = .custom
    @State private var command: String = ""
    @State private var envVarsText: String = ""

    // Agent config fields
    @State private var agentModel: String = ""
    @State private var agentSystemPromptFile: String = ""
    @State private var agentPermissionMode: String = ""
    @State private var agentEffort: String = ""
    @State private var agentAllowedTools: String = ""
    @State private var agentAdditionalFlags: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Template")
                .font(.system(size: 13, weight: .semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    field("Name") {
                        TextField("Template name", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    field("Kind") {
                        Picker("", selection: $kind) {
                            Text("Shell").tag(AgentTemplate.Kind.shell)
                            Text("Claude Code").tag(AgentTemplate.Kind.claudeCode)
                            Text("Custom").tag(AgentTemplate.Kind.custom)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    // Agent Configuration — only for non-shell kinds
                    if kind != .shell {
                        agentConfigSection
                    }

                    sectionHeader("Terminal")

                    field("Command") {
                        TextField("e.g. claude, python3", text: $command)
                            .textFieldStyle(.roundedBorder)
                        Text("Leave empty for default shell")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    field("Environment") {
                        TextEditor(text: $envVarsText)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 48)
                            .border(Color(.separatorColor), width: 0.5)
                        Text("KEY=VALUE, one per line")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxHeight: 420)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            name = template.name
            kind = template.kind
            command = template.command ?? ""
            envVarsText = template.environmentVariables
                .map { "\($0.key)=\($0.value)" }
                .sorted()
                .joined(separator: "\n")

            // Populate agent config fields from existing template
            if let agent = template.agent {
                agentModel = agent.model ?? ""
                agentSystemPromptFile = agent.systemPromptFile ?? ""
                agentPermissionMode = agent.permissionMode ?? ""
                agentEffort = agent.effort ?? ""
                agentAllowedTools = agent.allowedTools?.joined(separator: ",") ?? ""
                agentAdditionalFlags = agent.additionalFlags?.joined(separator: " ") ?? ""
            }
        }
        .onDisappear {
            guard Self.shouldDiscardOnDismiss(isNewlyCreated: isNewlyCreated, didSave: didSave) else { return }
            store.removeTemplate(id: template.id)
        }
    }

    // MARK: - Agent Configuration Section

    private var agentConfigSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Agent Configuration")

            field("Model") {
                Picker("", selection: $agentModel) {
                    Text("(none)").tag("")
                    Text("opus").tag("opus")
                    Text("sonnet").tag("sonnet")
                    Text("haiku").tag("haiku")
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            field("System Prompt") {
                HStack(spacing: 4) {
                    TextField("Path to .md file", text: $agentSystemPromptFile)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse") {
                        browseSystemPromptFile()
                    }
                }
            }

            field("Permission Mode") {
                Picker("", selection: $agentPermissionMode) {
                    Text("(none)").tag("")
                    Text("default").tag("default")
                    Text("plan").tag("plan")
                    Text("auto").tag("auto")
                    Text("acceptEdits").tag("acceptEdits")
                    Text("dontAsk").tag("dontAsk")
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            field("Effort") {
                Picker("", selection: $agentEffort) {
                    Text("(none)").tag("")
                    Text("low").tag("low")
                    Text("medium").tag("medium")
                    Text("high").tag("high")
                    Text("max").tag("max")
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            field("Allowed Tools") {
                TextField("Read,Grep,Bash", text: $agentAllowedTools)
                    .textFieldStyle(.roundedBorder)
                Text("Comma-separated tool names")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            field("Additional Flags") {
                TextField("--verbose --no-session", text: $agentAdditionalFlags)
                    .textFieldStyle(.roundedBorder)
                Text("Space-separated CLI flags")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 4)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func browseSystemPromptFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.directoryURL = URL(fileURLWithPath: ("~/.claude" as NSString).expandingTildeInPath)
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            agentSystemPromptFile = url.path
        }
    }

    // MARK: - Save

    private func save() {
        let trimmedCommand = command.trimmingCharacters(in: .whitespaces)
        let envVars = parseEnvironmentVariables(envVarsText)

        // Build AgentConfig from state if kind is not .shell
        let agentConfig: AgentTemplate.AgentConfig?? = {
            guard kind != .shell else {
                // Clear agent config for shell templates
                return .some(nil)
            }

            let model = agentModel.isEmpty ? nil : agentModel
            let systemPromptFile = agentSystemPromptFile.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil : agentSystemPromptFile.trimmingCharacters(in: .whitespaces)
            let permissionMode = agentPermissionMode.isEmpty ? nil : agentPermissionMode
            let effort = agentEffort.isEmpty ? nil : agentEffort

            let allowedTools: [String]? = {
                let trimmed = agentAllowedTools.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                return trimmed.split(separator: ",").map {
                    String($0).trimmingCharacters(in: .whitespaces)
                }.filter { !$0.isEmpty }
            }()

            let additionalFlags: [String]? = {
                let trimmed = agentAdditionalFlags.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                return trimmed.split(separator: " ").map {
                    String($0).trimmingCharacters(in: .whitespaces)
                }.filter { !$0.isEmpty }
            }()

            // If all fields are empty, set agent to nil
            if model == nil && systemPromptFile == nil && permissionMode == nil
                && effort == nil && allowedTools == nil && additionalFlags == nil {
                return .some(nil)
            }

            return .some(AgentTemplate.AgentConfig(
                systemPromptFile: systemPromptFile,
                model: model,
                permissionMode: permissionMode,
                effort: effort,
                allowedTools: allowedTools,
                additionalFlags: additionalFlags
            ))
        }()

        store.updateTemplate(
            id: template.id,
            name: name.trimmingCharacters(in: .whitespaces),
            kind: kind,
            command: trimmedCommand.isEmpty ? nil : trimmedCommand,
            environmentVariables: envVars,
            agent: agentConfig
        )
        didSave = true
        dismiss()
    }

    /// Parses "KEY=VALUE" lines into a dictionary, ignoring malformed lines
    /// and filtering out security-sensitive environment variable keys.
    private func parseEnvironmentVariables(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            guard !AgentTemplate.dangerousEnvKeys.contains(key.uppercased()) else { continue }
            result[key] = value
        }
        return result
    }
}

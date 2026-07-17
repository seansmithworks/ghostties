import SwiftUI

/// The Sessions tab content: a flat, time-sorted list of all sessions across projects.
///
/// Layout:
///   + New Session (full-width row → native flyout menu for project selection)
///   ─────────────────────────────────
///   ACTIVE    (sessions with a live indicator state)
///   ARCHIVE   (exited / never-run sessions)
struct RecentsListView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var coordinator: SessionCoordinator

    @State private var editingSessionId: UUID?
    @State private var editingName: String = ""
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            newSessionRow

            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(height: 1)

            if store.sessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if !activeSessions.isEmpty {
                            SessionSectionHeader(title: "Active")
                            ForEach(activeSessions) { session in
                                sessionRow(for: session)
                            }
                        }

                        if !archiveSessions.isEmpty {
                            SessionSectionHeader(title: "Archive")
                            ForEach(archiveSessions) { session in
                                sessionRow(for: session)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .accessibilityLabel("Sessions")
            }

            Spacer(minLength: 0)
        }
        .background(.clear)
    }

    // MARK: - New Session Row

    private var newSessionRow: some View {
        Menu {
            ForEach(store.projects) { project in
                let templates = availableTemplates(for: project)
                if templates.count <= 1 {
                    // Single template — tap creates directly, no submenu needed.
                    Button(project.name) {
                        startNewSession(in: project, template: templates.first)
                    }
                } else {
                    // Multiple templates — submenu: project name → template list.
                    Menu(project.name) {
                        ForEach(templates) { template in
                            Button(template.name) {
                                startNewSession(in: project, template: template)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: WorkspaceLayout.sidebarIconLabelSpacing) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: WorkspaceLayout.sidebarIconColumnWidth, alignment: .center)
                Text("New Session")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 4)
            }
            .padding(.leading, WorkspaceLayout.sidebarRowLeadingPadding)
            .padding(.trailing, 10)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(store.projects.isEmpty)
        .accessibilityLabel("New Session")
    }

    /// Returns templates available for a given project: global templates plus
    /// any templates scoped to that project, with the project's default first.
    private func availableTemplates(for project: Project) -> [AgentTemplate] {
        let candidates = store.templates.filter { $0.isGlobal || $0.projectId == project.id }
        // Lift the default template to the top of the list.
        if let defaultId = project.defaultTemplateId {
            let sorted = candidates.sorted { a, _ in a.id == defaultId }
            return sorted
        }
        return candidates
    }

    // MARK: - Session Row

    private func sessionRow(for session: AgentSession) -> some View {
        let project = store.projects.first { $0.id == session.projectId }
        let projectName = project?.name ?? "Unknown"
        let indicatorState = store.globalIndicatorStates[session.id] ?? .inactive
        return RecentsRowView(
            session: session,
            projectName: projectName,
            indicatorState: indicatorState,
            isActive: coordinator.activeSessionId == session.id,
            isEditing: editingSessionId == session.id,
            editingName: editingSessionId == session.id ? $editingName : .constant(""),
            isRenameFocused: $renameFieldFocused,
            onTap: { coordinator.focusSession(id: session.id) },
            onCommitRename: { commitRename(session: session) },
            onCancelRename: { cancelRename() }
        )
        .contextMenu {
            Button("Rename") {
                beginRename(session: session)
            }
            Divider()
            if coordinator.isRunning(id: session.id) {
                Button("Stop") {
                    coordinator.closeSession(id: session.id)
                }
            } else {
                Button("Relaunch") {
                    relaunchSession(session, project: project)
                }
                Button("Remove", role: .destructive) {
                    coordinator.clearRuntime(id: session.id)
                    store.removeSession(id: session.id)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            GhostCharacterView(character: .blinky, color: Color(.tertiaryLabelColor))
                .frame(width: 48, height: 48)

            Text("No sessions yet")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No sessions yet")
    }

    // MARK: - Data

    /// Sessions with a live indicator state — process is alive or actively tracked.
    var activeSessions: [AgentSession] {
        Self.sorted(sessions: store.sessions.filter {
            (store.globalIndicatorStates[$0.id] ?? .inactive) != .inactive
        })
    }

    /// Sessions that have exited, completed, or never had a live process this launch.
    var archiveSessions: [AgentSession] {
        Self.sorted(sessions: store.sessions.filter {
            (store.globalIndicatorStates[$0.id] ?? .inactive) == .inactive
        })
    }

    // MARK: - Actions

    private func startNewSession(in project: Project, template: AgentTemplate?) {
        let resolved: AgentTemplate = template ?? {
            if let defaultId = project.defaultTemplateId,
               let t = store.templates.first(where: { $0.id == defaultId }) {
                return t
            }
            return store.templates.first(where: { $0.kind == .shell })
                ?? AgentTemplate.shell
        }()
        Task {
            await coordinator.createQuickSession(for: project, template: resolved)
        }
    }

    // MARK: - Rename

    private func beginRename(session: AgentSession) {
        editingName = session.name
        editingSessionId = session.id
        DispatchQueue.main.async {
            renameFieldFocused = true
        }
    }

    private func commitRename(session: AgentSession) {
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != session.name {
            store.renameSession(id: session.id, name: trimmed)
        }
        editingSessionId = nil
    }

    private func cancelRename() {
        editingSessionId = nil
    }

    // MARK: - Relaunch

    private func relaunchSession(_ session: AgentSession, project: Project?) {
        guard let project,
              let template = store.templates.first(where: { $0.id == session.templateId }) else {
            // Template or project was deleted — cannot relaunch.
            print("Warning: Template or project for session '\(session.name)' not found (templateId: \(session.templateId))")
            return
        }

        // No pre-check needed — SessionCoordinator.createSession() calls
        // buildCommand() itself and handles missing prompt files gracefully.
        coordinator.clearRuntime(id: session.id)
        Task {
            await coordinator.createSession(session: session, template: template, project: project)
        }
    }

    // MARK: - Sorting (static so tests can call without a view instance)

    /// Sort sessions most-recently-active first; nil `lastActiveAt` sinks to bottom.
    static func sorted(sessions: [AgentSession]) -> [AgentSession] {
        sessions.sorted { lhs, rhs in
            switch (lhs.lastActiveAt, rhs.lastActiveAt) {
            case (let l?, let r?): return l > r
            case (.some, .none):   return true
            case (.none, .some):   return false
            case (.none, .none):   return false
            }
        }
    }
}

// MARK: - Section Header

private struct SessionSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(WorkspaceLayout.sectionHeaderForeground)
            .padding(.leading, WorkspaceLayout.sidebarRowLeadingPadding
                         + WorkspaceLayout.sidebarIconColumnWidth
                         + WorkspaceLayout.sidebarIconLabelSpacing)
            .padding(.trailing, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

#if DEBUG
#Preview("Sessions — active + archive") {
    let store = WorkspaceStore(testingProjects: [
        Project(name: "ghostties", rootPath: "~/Code/ghostties"),
        Project(name: "portfolio", rootPath: "~/Code/portfolio"),
    ])
    let coordinator = SessionCoordinator()
    return RecentsListView()
        .environmentObject(store)
        .environmentObject(coordinator)
        .frame(width: 220, height: 500)
        .preferredColorScheme(.dark)
}

#Preview("Sessions — empty") {
    let store = WorkspaceStore(testingProjects: [])
    let coordinator = SessionCoordinator()
    return RecentsListView()
        .environmentObject(store)
        .environmentObject(coordinator)
        .frame(width: 220, height: 500)
        .preferredColorScheme(.dark)
}
#endif

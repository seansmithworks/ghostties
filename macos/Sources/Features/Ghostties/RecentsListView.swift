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

    /// Section-collapse state, persisted across launches. Active defaults open
    /// (the sessions the user is working with today); Archive defaults closed.
    @AppStorage("ghostties.sessionsSection.active") private var isActiveExpanded = true
    @AppStorage("ghostties.sessionsSection.archive") private var isArchiveExpanded = false

    var body: some View {
        // Bound once per body pass — `activeSessions`/`archiveSessions` each
        // filter + build a Dictionary internally, and were previously
        // evaluated twice (once for an `isEmpty` check, once for `ForEach`).
        let active = activeSessions
        let archive = archiveSessions
        let selectedId = coordinator.activeSessionId

        VStack(spacing: 0) {
            newSessionRow

            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(height: 1)

            if store.sessions.isEmpty {
                emptyState
            } else {
                // Render-time-ONLY overrides — never written back to the
                // persisted `@AppStorage` preference below, so the user's
                // stored preference reapplies untouched once the condition
                // clears. See `effectiveExpanded(...)`.
                let activeExpanded = Self.effectiveExpanded(
                    storedPreference: isActiveExpanded,
                    isArchiveSection: false,
                    activeSessionsEmpty: active.isEmpty,
                    sectionContainsSelectedSession: selectedId.map { id in active.contains { $0.id == id } } ?? false
                )
                let archiveExpanded = Self.effectiveExpanded(
                    storedPreference: isArchiveExpanded,
                    isArchiveSection: true,
                    activeSessionsEmpty: active.isEmpty,
                    sectionContainsSelectedSession: selectedId.map { id in archive.contains { $0.id == id } } ?? false
                )

                ScrollView {
                    LazyVStack(spacing: 2) {
                        // Both headers always render (when there's at least
                        // one session anywhere) — membership adapts, but the
                        // ACTIVE/ARCHIVE headers themselves never disappear.
                        // Every header carries a count; a collapsed header
                        // with no count is illegible.
                        SessionSectionHeader(
                            title: "Active",
                            count: active.count,
                            isExpanded: $isActiveExpanded,
                            isEffectivelyExpanded: activeExpanded
                        )
                        if activeExpanded {
                            ForEach(active) { session in
                                sessionRow(for: session)
                            }
                        }

                        SessionSectionHeader(
                            title: "Archive",
                            count: archive.count,
                            isExpanded: $isArchiveExpanded,
                            isEffectivelyExpanded: archiveExpanded
                        )
                        if archiveExpanded {
                            ForEach(archive) { session in
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

    /// Sessions with a live indicator state — process is alive or actively
    /// tracked. Membership depends ONLY on indicator state (see
    /// `belongsInActive`) — it does NOT move when the user selects a row.
    /// Visibility of a selected-but-inactive session is guaranteed instead by
    /// the auto-expand override in `body` (`effectiveExpanded`), which expands
    /// whichever section actually contains the selection without relocating
    /// the row itself. A selection-based membership guard here would make
    /// rows jump between sections — and everything below them shift ~38pt —
    /// the instant the user clicks an Archive row, reintroducing exactly the
    /// "rows reshuffling under the cursor" problem this feature set removed.
    var activeSessions: [AgentSession] {
        Self.activeSessions(from: store.sessions, indicatorStates: store.globalIndicatorStates)
    }

    /// Sessions that have exited, completed, or never had a live process this
    /// launch. See `activeSessions` — membership is indicator-state-only.
    var archiveSessions: [AgentSession] {
        Self.archiveSessions(from: store.sessions, indicatorStates: store.globalIndicatorStates)
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
        // Guards against the Esc blur-commit race: cancelRename() clears
        // editingSessionId synchronously, so a commit that was scheduled
        // before the cancel ran (see RecentsRowView's deferred onChange)
        // finds a stale/mismatched id here and bails instead of writing.
        guard editingSessionId == session.id else { return }
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != session.name {
            store.renameSession(id: session.id, name: trimmed)
        }
        renameFieldFocused = false
        editingSessionId = nil
    }

    private func cancelRename() {
        renameFieldFocused = false
        editingName = ""
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

    // MARK: - Section Membership (static so tests can call without a view instance)

    /// Whether a session belongs in the Active section: it has a live
    /// indicator state. Membership depends ONLY on this — never on selection
    /// (see the doc comment on the `activeSessions` instance property for why).
    static func belongsInActive(indicatorState: SessionIndicatorState) -> Bool {
        indicatorState != .inactive
    }

    /// Pure, testable variant of the `activeSessions` instance property.
    static func activeSessions(
        from sessions: [AgentSession],
        indicatorStates: [UUID: SessionIndicatorState]
    ) -> [AgentSession] {
        sorted(sessions: sessions.filter {
            belongsInActive(indicatorState: indicatorStates[$0.id] ?? .inactive)
        })
    }

    /// Pure, testable variant of the `archiveSessions` instance property.
    /// Exact complement of `activeSessions` — every session is in exactly one
    /// of the two.
    static func archiveSessions(
        from sessions: [AgentSession],
        indicatorStates: [UUID: SessionIndicatorState]
    ) -> [AgentSession] {
        sorted(sessions: sessions.filter {
            !belongsInActive(indicatorState: indicatorStates[$0.id] ?? .inactive)
        })
    }

    // MARK: - Auto-Expand Override (static so tests can call without a view instance)

    /// Whether a section renders expanded. This is a RENDER-TIME override
    /// only — callers must never write the result back into the persisted
    /// `@AppStorage` preference, or a temporary condition (e.g. the selected
    /// session moving) would permanently clobber the user's stored choice.
    ///
    /// Expands, regardless of `storedPreference`, when either:
    ///   (a) `isArchiveSection` is true and `activeSessionsEmpty` is true —
    ///       nothing above it to show, so Archive can't be left collapsed
    ///       with the whole list hidden behind it.
    ///   (b) `isArchiveSection` is true and `sectionContainsSelectedSession`
    ///       is true — a session that drops into a collapsed Archive stays
    ///       visible, without relocating the session itself (see
    ///       `belongsInActive`). This override is Archive-only: Active has no
    ///       equivalent vanishing problem, and a selected, running session
    ///       lives in Active essentially all the time during normal use, so
    ///       applying the override there would make the Active header a dead
    ///       control.
    /// Otherwise falls through to `storedPreference` unchanged.
    static func effectiveExpanded(
        storedPreference: Bool,
        isArchiveSection: Bool,
        activeSessionsEmpty: Bool,
        sectionContainsSelectedSession: Bool
    ) -> Bool {
        if isArchiveSection && activeSessionsEmpty { return true }
        if isArchiveSection && sectionContainsSelectedSession { return true }
        return storedPreference
    }

    // MARK: - Sorting (static so tests can call without a view instance)

    /// Cross-project flat order for the Sessions tab: array position in the
    /// passed-in array ALONE — i.e. append/creation order in `store.sessions`.
    ///
    /// `AgentSession.sortOrder` is scoped to reordering WITHIN a project (see
    /// its doc comment) and must never be used as a cross-project sort key —
    /// two different projects each independently number their own sessions
    /// `0..<n`, so keying a flat, cross-project list on `sortOrder` interleaves
    /// unrelated projects (A1, B1, A2, B2, A3) and can land a freshly created
    /// session in the middle of the list instead of at the end.
    ///
    /// Callers always pass an already order-preserving filtered slice of
    /// `store.sessions` (`Array.filter` preserves relative order), so this is
    /// effectively an identity pass. Kept as a named, independently testable
    /// function — rather than inlined at each call site — so "no sortOrder,
    /// no reshuffling" has one place to read, change, and test, and so this
    /// can never regain a `Dictionary(uniqueKeysWithValues:)`-style trap on a
    /// duplicate session id (a real risk: session ids come from
    /// `workspace.json`, a file written by multiple windows).
    static func sorted(sessions: [AgentSession]) -> [AgentSession] {
        sessions
    }
}

// MARK: - Section Header

private struct SessionSectionHeader: View {
    let title: String
    let count: Int
    /// Persisted preference — toggled on tap. The header may render expanded
    /// even when this is `false` (see `isEffectivelyExpanded`); tapping always
    /// toggles the user's real stored preference, which reapplies once any
    /// override condition clears.
    @Binding var isExpanded: Bool
    /// What actually renders right now (stored preference, possibly
    /// overridden — see `RecentsListView.effectiveExpanded`). Drives the
    /// chevron direction and the accessibility state.
    let isEffectivelyExpanded: Bool

    var body: some View {
        Button {
            let animation: Animation? = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? nil
                : .easeInOut(duration: 0.2)
            withAnimation(animation) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: WorkspaceLayout.sidebarIconLabelSpacing) {
                // Sized to `sidebarIconColumnWidth` (not a hardcoded literal)
                // so this chevron's x-center lines up with session-row ghosts
                // directly below it — `PixelChevronView` already pins its own
                // internal content to a 16pt frame, so the outer frame here
                // must match that, not shrink it.
                PixelChevronView(color: WorkspaceLayout.sectionHeaderForeground, isExpanded: isEffectivelyExpanded)
                    .frame(width: WorkspaceLayout.sidebarIconColumnWidth, height: WorkspaceLayout.sidebarIconColumnWidth)

                Text("\(title.uppercased()) \(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(WorkspaceLayout.sectionHeaderForeground)

                Spacer(minLength: 0)
            }
            .padding(.leading, WorkspaceLayout.sidebarRowLeadingPadding)
            .padding(.trailing, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(title), \(count), \(isEffectivelyExpanded ? "expanded" : "collapsed")")
        .accessibilityHint("Double-tap to \(isEffectivelyExpanded ? "collapse" : "expand")")
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

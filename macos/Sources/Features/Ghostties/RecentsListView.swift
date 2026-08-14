import SwiftUI
import os

/// TEMPORARY diagnostic logger — see `SIDEBARDIAG` tag. To be reverted.
private let sidebarDiagLogger = Logger(subsystem: "com.seansmithdesign.ghostties", category: "sidebardiag")
private var sidebarDiagBodyCounter = 0

/// The Sessions tab content: a flat, time-sorted list of all sessions across projects.
///
/// Layout:
///   + New Session (full-width row → native flyout menu for project selection)
///   ─────────────────────────────────
///   ACTIVE    (sessions with a live indicator state)
///   INACTIVE  (started at some point this launch, currently not active — ran, then stopped)
///   ARCHIVE   (restored from disk, never started this launch)
struct RecentsListView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var coordinator: SessionCoordinator

    @State private var editingSessionId: UUID?
    @State private var editingName: String = ""
    @FocusState private var renameFieldFocused: Bool

    /// Section-collapse state, persisted across launches. Active and
    /// Inactive default open (sessions the user is working with today, or
    /// just stopped); Archive defaults closed.
    @AppStorage("ghostties.sessionsSection.active") private var isActiveExpanded = true
    @AppStorage("ghostties.sessionsSection.inactive") private var isInactiveExpanded = true
    @AppStorage("ghostties.sessionsSection.archive") private var isArchiveExpanded = false

    var body: some View {
        // Bound once per body pass — `activeSessions`/`inactiveSessions`/
        // `archiveSessions` each filter + build a Dictionary internally, and
        // were previously evaluated twice (once for an `isEmpty` check, once
        // for `ForEach`).
        let active = activeSessions
        let inactive = inactiveSessions
        let archive = archiveSessions
        let selectedId = coordinator.activeSessionId

        // TEMPORARY diagnostic — see SIDEBARDIAG in the boundaries note; to be reverted.
        let _ = {
            sidebarDiagBodyCounter &+= 1
            sidebarDiagLogger.debug("SIDEBARDIAG body pass=\(sidebarDiagBodyCounter, privacy: .public) activeCount=\(active.count, privacy: .public)")
            let activeSummary = active.map { "\(String($0.id.uuidString.prefix(8)))=\($0.name)" }.joined(separator: ", ")
            sidebarDiagLogger.debug("SIDEBARDIAG active sessions: \(activeSummary, privacy: .public)")
        }()

        VStack(spacing: 0) {
            if store.sessions.isEmpty {
                emptyState
            } else {
                // Render-time-ONLY overrides — never written back to the
                // persisted `@AppStorage` preference below, so the user's
                // stored preference reapplies untouched once the condition
                // clears. See `effectiveExpanded(...)`.
                let activeExpanded = Self.effectiveExpanded(
                    storedPreference: isActiveExpanded,
                    section: .active,
                    sectionContainsSelectedSession: selectedId.map { id in active.contains { $0.id == id } } ?? false
                )
                let inactiveExpanded = Self.effectiveExpanded(
                    storedPreference: isInactiveExpanded,
                    section: .inactive,
                    sectionContainsSelectedSession: selectedId.map { id in inactive.contains { $0.id == id } } ?? false
                )
                let archiveExpanded = Self.effectiveExpanded(
                    storedPreference: isArchiveExpanded,
                    section: .archive,
                    sectionContainsSelectedSession: selectedId.map { id in archive.contains { $0.id == id } } ?? false
                )

                ScrollView {
                    LazyVStack(spacing: 2) {
                        // All three headers always render (when there's at
                        // least one session anywhere) — membership adapts,
                        // but the ACTIVE/INACTIVE/ARCHIVE headers themselves
                        // never disappear. Every header carries a count; a
                        // collapsed header with no count is illegible.
                        SessionSectionHeader(
                            title: "Active",
                            count: active.count,
                            isExpanded: $isActiveExpanded,
                            isEffectivelyExpanded: activeExpanded
                        )
                        if activeExpanded {
                            // Keyed on the stable `\.id` (default Identifiable) —
                            // NOT `\.self`. `\.self` was tried and reverted: it makes
                            // row identity churn on every `lastActiveAt` write (see
                            // `AgentSession.lastActiveAt`, rewritten every few seconds
                            // for running sessions), which tears down and rebuilds the
                            // row — resetting `RecentsRowView`'s hover state and
                            // killing the inline-rename `TextField`/`FocusState`
                            // mid-edit. Freshness on a stable identity is instead
                            // guaranteed by `.equatable()` on `RecentsRowView` in
                            // `sessionRow(for:)`, which forces a body re-render
                            // whenever the row's own inputs change, without touching
                            // identity.
                            ForEach(active) { session in
                                sessionRow(for: session)
                            }
                        }

                        SessionSectionHeader(
                            title: "Inactive",
                            count: inactive.count,
                            isExpanded: $isInactiveExpanded,
                            isEffectivelyExpanded: inactiveExpanded
                        )
                        if inactiveExpanded {
                            // See the identity/`.equatable()` comment on the Active
                            // ForEach above — same fix applies here.
                            ForEach(inactive) { session in
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
                            // See the identity/`.equatable()` comment on the Active
                            // ForEach above — same fix applies here.
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

    // MARK: - New Session (project-picker templates)

    /// Returns templates available for a given project: global templates plus
    /// any templates scoped to that project, with the project's default first.
    /// Static so `NewSessionToolbarButton` (titlebar toolbar) can share the
    /// exact same resolution logic without instantiating this view.
    static func availableTemplates(for project: Project, store: WorkspaceStore) -> [AgentTemplate] {
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
        .equatable()
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
                Button("Delete", role: .destructive) {
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
    /// the instant the user clicks an Inactive/Archive row, reintroducing
    /// exactly the "rows reshuffling under the cursor" problem this feature
    /// set removed.
    var activeSessions: [AgentSession] {
        Self.activeSessions(from: store.sessions, indicatorStates: store.globalIndicatorStates)
    }

    /// Sessions that exited (or completed) THIS launch but were started at
    /// some point this launch — `coordinator.sessionIdsStartedThisLaunch`
    /// contains the id. This is the "ran, then stopped" bucket: a session
    /// the user actually interacted with this run, as opposed to one
    /// restored from disk that never started. See `archiveSessions` for the
    /// complement.
    var inactiveSessions: [AgentSession] {
        Self.inactiveSessions(
            from: store.sessions,
            indicatorStates: store.globalIndicatorStates,
            sessionIdsStartedThisLaunch: coordinator.sessionIdsStartedThisLaunch
        )
    }

    /// Sessions with no live indicator state AND never started this
    /// launch — restored from `workspace.json`, never started this run.
    /// Exact complement of `activeSessions` + `inactiveSessions` combined.
    var archiveSessions: [AgentSession] {
        Self.archiveSessions(
            from: store.sessions,
            indicatorStates: store.globalIndicatorStates,
            sessionIdsStartedThisLaunch: coordinator.sessionIdsStartedThisLaunch
        )
    }

    // MARK: - Actions

    /// Static so `NewSessionToolbarButton` shares this exactly — see
    /// `availableTemplates(for:store:)` above.
    static func startNewSession(in project: Project, template: AgentTemplate?, store: WorkspaceStore, coordinator: SessionCoordinator) {
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
        // Clear the sentinel before dropping focus: clearing focus itself
        // triggers the onChange handler that schedules a deferred commit,
        // so a re-entrant commit only sees the guard fail if the sentinel
        // is already nil by the time that handler runs.
        editingSessionId = nil
        renameFieldFocused = false
    }

    private func cancelRename() {
        // Clear the sentinel before dropping focus: renameFieldFocused =
        // false is itself a true→false transition that fires the same
        // onChange handler this cancel is trying to defeat. The guard in
        // commitRename only works if editingSessionId is already nil when
        // that deferred handler runs.
        editingSessionId = nil
        editingName = ""
        renameFieldFocused = false
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

    /// Pure, testable variant of the `inactiveSessions` instance property:
    /// not active (no live indicator state) AND was started at some point
    /// this launch — `sessionIdsStartedThisLaunch` is passed in rather than
    /// read from a coordinator so this stays a pure function callers can
    /// test directly. Ordering matches `activeSessions` (append order) —
    /// only `archiveSessions` reverses.
    static func inactiveSessions(
        from sessions: [AgentSession],
        indicatorStates: [UUID: SessionIndicatorState],
        sessionIdsStartedThisLaunch: Set<UUID>
    ) -> [AgentSession] {
        sorted(sessions: sessions.filter {
            !belongsInActive(indicatorState: indicatorStates[$0.id] ?? .inactive)
                && sessionIdsStartedThisLaunch.contains($0.id)
        })
    }

    /// Pure, testable variant of the `archiveSessions` instance property:
    /// not active AND never started this launch — restored from disk,
    /// never started. Together with `activeSessions` and `inactiveSessions`
    /// this is an exact three-way partition — every session lands in
    /// exactly one bucket. Sorted newest-first by `lastActiveAt` — the one
    /// bucket that does NOT keep append order, per Sean's call that Archive
    /// should read reverse-chronological. Sessions with a `nil`
    /// `lastActiveAt` sort last, after every timestamped session.
    static func archiveSessions(
        from sessions: [AgentSession],
        indicatorStates: [UUID: SessionIndicatorState],
        sessionIdsStartedThisLaunch: Set<UUID>
    ) -> [AgentSession] {
        let archived = sorted(sessions: sessions.filter {
            !belongsInActive(indicatorState: indicatorStates[$0.id] ?? .inactive)
                && !sessionIdsStartedThisLaunch.contains($0.id)
        })
        // Sort newest-first by `lastActiveAt`, nil last. `Array.sort` is not
        // guaranteed stable, so ties (and nil-vs-nil) are broken on the
        // original index to preserve incoming relative order.
        return archived
            .enumerated()
            .sorted { lhs, rhs in
                switch (lhs.element.lastActiveAt, rhs.element.lastActiveAt) {
                case let (l?, r?):
                    if l != r { return l > r }
                case (nil, .some):
                    return false
                case (.some, nil):
                    return true
                case (nil, nil):
                    break
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    // MARK: - Auto-Expand Override (static so tests can call without a view instance)

    /// One of the three Sessions-tab sections. Used only to decide which
    /// sections get the selected-session force-expand override below — not
    /// a membership concept (see `belongsInActive`, `inactiveSessions`,
    /// `archiveSessions` for that).
    enum Section {
        case active, inactive, archive
    }

    /// Whether a section renders expanded. This is a RENDER-TIME override
    /// only — callers must never write the result back into the persisted
    /// `@AppStorage` preference, or a temporary condition (e.g. the selected
    /// session moving) would permanently clobber the user's stored choice.
    ///
    /// Expands, regardless of `storedPreference`, when `section` is
    /// `.inactive` or `.archive` AND `sectionContainsSelectedSession` is
    /// true — a session that drops into a collapsed Inactive or Archive
    /// section stays visible, without relocating the session itself (see
    /// `belongsInActive`). This override excludes `.active`: a selected,
    /// running session lives in Active essentially all the time during
    /// normal use, so applying the override there would make the Active
    /// header a dead control.
    ///
    /// Otherwise falls through to `storedPreference` unchanged — including
    /// when another section is empty. An empty section is not, by itself, a
    /// reason to force a different section open; the user's
    /// collapsed/expanded choice is honored either way. (This "expand
    /// because another section is empty" rule was deliberately removed in
    /// PR #106 — do not reintroduce it.)
    static func effectiveExpanded(
        storedPreference: Bool,
        section: Section,
        sectionContainsSelectedSession: Bool
    ) -> Bool {
        if section != .active && sectionContainsSelectedSession { return true }
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

// MARK: - New Session Toolbar Button

/// Labelled toolbar button for the Sessions tab, presented in
/// `WorkspaceSidebarView.titlebarToolbar` right-aligned on the traffic-light
/// row. Opens the same project-picker flyout menu the former `newSessionRow`
/// showed inline in the list — see `RecentsListView.availableTemplates(for:store:)`
/// and `RecentsListView.startNewSession(in:template:store:coordinator:)`, which
/// this calls directly so the menu logic is never duplicated.
struct NewSessionToolbarButton: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var coordinator: SessionCoordinator

    @State private var isHovered = false

    var body: some View {
        Menu {
            ForEach(store.projects) { project in
                let templates = RecentsListView.availableTemplates(for: project, store: store)
                if templates.count <= 1 {
                    // Single template — tap creates directly, no submenu needed.
                    Button(project.name) {
                        RecentsListView.startNewSession(in: project, template: templates.first, store: store, coordinator: coordinator)
                    }
                } else {
                    // Multiple templates — submenu: project name → template list.
                    Menu(project.name) {
                        ForEach(templates) { template in
                            Button(template.name) {
                                RecentsListView.startNewSession(in: project, template: template, store: store, coordinator: coordinator)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                Text("New Session")
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        // `Menu` can otherwise claim more horizontal space than its label
        // content needs; this keeps it hugging the icon+text so the
        // trailing-aligned `Spacer()` in `WorkspaceSidebarView.titlebarToolbar`
        // has room to push it flush against the sidebar's trailing edge.
        .fixedSize()
        .foregroundStyle(isHovered ? .primary : .secondary)
        .onHover { isHovered = $0 }
        .disabled(store.projects.isEmpty)
        .accessibilityLabel("New Session")
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

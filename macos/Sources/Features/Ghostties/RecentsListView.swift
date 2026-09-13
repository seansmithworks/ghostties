import SwiftUI
import GhosttiesCore

/// The Sessions tab content: a flat, time-sorted list of all sessions across projects.
///
/// Layout:
///   + New Session (full-width row → native flyout menu for project selection)
///   ─────────────────────────────────
///   PINNED    (isPinned — hidden when empty; stays pinned whether open or closed)
///   ACTIVE    (the session's terminal is open — see `SessionBucket.membership`)
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
    @AppStorage("ghostties.sessionsSection.pinned") private var isPinnedExpanded = true
    @AppStorage("ghostties.sessionsSection.active") private var isActiveExpanded = true
    @AppStorage("ghostties.sessionsSection.inactive") private var isInactiveExpanded = true
    @AppStorage("ghostties.sessionsSection.archive") private var isArchiveExpanded = false

    var body: some View {
        // Bound once per body pass — `activeSessions`/`inactiveSessions`/
        // `archiveSessions` each filter + build a Dictionary internally, and
        // were previously evaluated twice (once for an `isEmpty` check, once
        // for `ForEach`).
        let pinned = pinnedSessions
        let active = activeSessions
        let inactive = inactiveSessions
        let archive = archiveSessions
        let selectedId = coordinator.activeSessionId

        VStack(spacing: 0) {
            if store.sessions.isEmpty {
                emptyState
            } else {
                // Render-time-ONLY overrides — never written back to the
                // persisted `@AppStorage` preference below, so the user's
                // stored preference reapplies untouched once the condition
                // clears. See `effectiveExpanded(...)`.
                let pinnedExpanded = Self.effectiveExpanded(
                    storedPreference: isPinnedExpanded,
                    section: .pinned,
                    sectionContainsSelectedSession: selectedId.map { id in pinned.contains { $0.id == id } } ?? false
                )
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
                    // Deliberately a plain VStack, NOT `LazyVStack`. A lazy
                    // container realizes each row once and retains it — when
                    // a session's fields (e.g. name) change but its `\.id`
                    // identity doesn't, `ForEach`'s content closure is never
                    // re-invoked for that row, so it renders the value it was
                    // first constructed with forever (proven by
                    // instrumentation: `sessionRow(for:)` fired only at
                    // creation, never on rename). Switching this back to
                    // `LazyVStack` reintroduces the frozen-name bug — rows
                    // will stop picking up renames, activity changes, and
                    // timestamp updates. If eager rendering of ~37 archive
                    // rows (each carrying a `.contextMenu`) ever becomes a
                    // measured perf problem, the fix is a lazy container that
                    // still re-invokes its content closure on element change
                    // (e.g. `LazyVStack` keyed with `.id` forced to include a
                    // content hash), not a plain revert.
                    VStack(spacing: 2) {
                        // Pinned is the one section that's hidden entirely
                        // when empty — it's an opt-in section, not one of
                        // the three lifecycle buckets every session always
                        // belongs to. Pinning a first session (before any
                        // are pinned) requires the context menu, since drag
                        // needs a rendered drop target — see task report.
                        if !pinned.isEmpty {
                            SessionSectionHeader(
                                title: "Pinned",
                                count: pinned.count,
                                isExpanded: $isPinnedExpanded,
                                isEffectivelyExpanded: pinnedExpanded
                            )
                            if pinnedExpanded {
                                ForEach(pinned) { session in
                                    sessionRow(for: session, section: .pinned, sectionList: pinned)
                                }
                            }
                        }

                        // All three lifecycle headers always render (when
                        // there's at least one session anywhere) —
                        // membership adapts, but the ACTIVE/INACTIVE/ARCHIVE
                        // headers themselves never disappear. Every header
                        // carries a count; a collapsed header with no count
                        // is illegible.
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
                            // mid-edit. Freshness on that stable identity comes from
                            // this container being a non-lazy `VStack` (see the
                            // comment above it) — `.equatable()` on `RecentsRowView`
                            // in `sessionRow(for:)` is a body-re-execution perf gate
                            // layered on top, not what makes rows fresh.
                            ForEach(active) { session in
                                sessionRow(for: session, section: .active, sectionList: active)
                            }
                        }

                        SessionSectionHeader(
                            title: "Inactive",
                            count: inactive.count,
                            isExpanded: $isInactiveExpanded,
                            isEffectivelyExpanded: inactiveExpanded
                        )
                        if inactiveExpanded {
                            // See the identity comment on the Active ForEach
                            // above — same reasoning applies here.
                            ForEach(inactive) { session in
                                sessionRow(for: session, section: .inactive, sectionList: inactive)
                            }
                        }

                        SessionSectionHeader(
                            title: "Archive",
                            count: archive.count,
                            isExpanded: $isArchiveExpanded,
                            isEffectivelyExpanded: archiveExpanded
                        )
                        if archiveExpanded {
                            // See the identity comment on the Active ForEach
                            // above — same reasoning applies here.
                            ForEach(archive) { session in
                                sessionRow(for: session, section: .archive, sectionList: archive)
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

    // MARK: - Session Row

    private func sessionRow(for session: AgentSession, section: SessionSection, sectionList: [AgentSession]) -> some View {
        let project = store.projects.first { $0.id == session.projectId }
        let projectName = project?.name ?? "Unknown"
        let indicatorState = store.globalIndicatorStates[session.id] ?? .inactive
        // Archive has no manual order (always newest-first) — no reorder
        // affordances (drop target, Move Up/Down) on its rows. It's still a
        // valid DRAG SOURCE, since decision 3 lets it be dragged up into
        // Active/Pinned; that's `.draggable` below, applied unconditionally.
        let supportsReorder = section != .archive
        let indexInSection = sectionList.firstIndex(where: { $0.id == session.id })

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
            if session.isNamePinned {
                Button("Sync name automatically") {
                    store.resetNamePin(id: session.id)
                }
            }
            Divider()
            Button(session.isPinned ? "Unpin" : "Pin") {
                store.toggleSessionPin(id: session.id)
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
        .draggable(session.id.uuidString) {
            Text(session.name)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .dropDestination(for: String.self) { items, _ in
            // Archive is never a drop target — `SessionSectionDrop.resolve`
            // already rejects `.archive` as a target section, so this guard
            // is belt-and-suspenders against attaching the affordance at all.
            guard supportsReorder else { return false }
            return handleSessionDrop(items: items, targetSection: section, targetList: sectionList, droppedOnSession: session)
        }
        .accessibilityAction(named: Text("Move Up")) {
            guard supportsReorder else { return }
            moveWithinSection(session: session, indexInSection: indexInSection, direction: -1, sectionList: sectionList)
        }
        .accessibilityAction(named: Text("Move Down")) {
            guard supportsReorder else { return }
            moveWithinSection(session: session, indexInSection: indexInSection, direction: 1, sectionList: sectionList)
        }
    }

    // MARK: - Drag / Drop

    /// Parses a drop, resolves the pure action via `SessionSectionDrop.resolve`,
    /// and applies it. This is the ONE call site that turns a drop into a
    /// store mutation — everything decision-related lives in the pure
    /// resolver, tested directly in `RecentsListViewTests`.
    private func handleSessionDrop(
        items: [String],
        targetSection: SessionSection,
        targetList: [AgentSession],
        droppedOnSession: AgentSession
    ) -> Bool {
        guard let raw = items.first,
              let draggedId = UUID(uuidString: raw),
              let draggedSession = store.sessions.first(where: { $0.id == draggedId }),
              let targetIndex = targetList.firstIndex(where: { $0.id == droppedOnSession.id })
        else { return false }

        let draggedBucket = SessionBucket.membership(
            status: store.globalStatuses[draggedId],
            startedThisLaunch: coordinator.sessionIdsStartedThisLaunch.contains(draggedId)
        )
        let draggedSection = SessionSection.section(isPinned: draggedSession.isPinned, bucket: draggedBucket)
        let draggedIsOpen = store.globalStatuses[draggedId]?.isAlive == true

        let action = SessionSectionDrop.resolve(
            draggedSection: draggedSection,
            draggedIsOpen: draggedIsOpen,
            targetSection: targetSection
        )

        switch action {
        case .reject:
            return false
        case .reorder:
            store.moveSessionInSessionsView(id: draggedId, toIndex: targetIndex, within: targetList)
        case .pin:
            store.setSessionPinned(id: draggedId, true)
            store.moveSessionInSessionsView(id: draggedId, toIndex: targetIndex, within: targetList)
        case .unpin(let relaunchIfClosed):
            store.setSessionPinned(id: draggedId, false)
            if relaunchIfClosed {
                relaunchSession(draggedSession, project: store.projects.first { $0.id == draggedSession.projectId })
            }
            store.moveSessionInSessionsView(id: draggedId, toIndex: targetIndex, within: targetList)
        case .relaunch:
            relaunchSession(draggedSession, project: store.projects.first { $0.id == draggedSession.projectId })
            store.moveSessionInSessionsView(id: draggedId, toIndex: targetIndex, within: targetList)
        }
        return true
    }

    /// VoiceOver/keyboard reorder within one section — the accessible
    /// counterpart to drag-reorder. `direction` is -1 (up) or +1 (down); a
    /// move past either end of the section is a no-op.
    private func moveWithinSection(session: AgentSession, indexInSection: Int?, direction: Int, sectionList: [AgentSession]) {
        guard let indexInSection else { return }
        let target = indexInSection + direction
        guard target >= 0, target < sectionList.count else { return }
        store.moveSessionInSessionsView(id: session.id, toIndex: target, within: sectionList)
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

    /// Sessions pinned to the top of the Sessions tab — see `SessionSection`.
    /// Pinning wins over bucket membership entirely; a pinned session never
    /// appears in `activeSessions`/`inactiveSessions`/`archiveSessions`
    /// regardless of whether its terminal is open.
    var pinnedSessions: [AgentSession] {
        Self.pinnedSessions(from: store.sessions)
    }

    /// Sessions whose terminal is open — see `SessionBucket.membership`, the
    /// one rule shared with project view. Membership does NOT move when the
    /// user selects a row. Visibility of a selected-but-inactive session is
    /// guaranteed instead by the auto-expand override in `body`
    /// (`effectiveExpanded`), which expands whichever section actually
    /// contains the selection without relocating the row itself. A
    /// selection-based membership guard here would make rows jump between
    /// sections — and everything below them shift ~38pt — the instant the
    /// user clicks an Inactive/Archive row, reintroducing exactly the "rows
    /// reshuffling under the cursor" problem this feature set removed.
    var activeSessions: [AgentSession] {
        Self.activeSessions(from: store.sessions, statuses: store.globalStatuses)
    }

    /// Sessions whose terminal closed THIS launch but were started at some
    /// point this launch — `coordinator.sessionIdsStartedThisLaunch`
    /// contains the id. This is the "ran, then stopped" bucket: a session
    /// the user actually interacted with this run, as opposed to one
    /// restored from disk that never started. See `archiveSessions` for the
    /// complement.
    var inactiveSessions: [AgentSession] {
        Self.inactiveSessions(
            from: store.sessions,
            statuses: store.globalStatuses,
            sessionIdsStartedThisLaunch: coordinator.sessionIdsStartedThisLaunch
        )
    }

    /// Sessions whose terminal is not open AND never started this launch —
    /// restored from `workspace.json`, never started this run. Exact
    /// complement of `activeSessions` + `inactiveSessions` combined.
    var archiveSessions: [AgentSession] {
        Self.archiveSessions(
            from: store.sessions,
            statuses: store.globalStatuses,
            sessionIdsStartedThisLaunch: coordinator.sessionIdsStartedThisLaunch
        )
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
        _Concurrency.Task {
            await coordinator.createSession(session: session, template: template, project: project)
        }
    }

    // MARK: - Section Membership (static so tests can call without a view instance)
    //
    // Bucketing here delegates entirely to `SessionBucket.membership(status:
    // startedThisLaunch:)` — the one Active/Inactive/Archive rule shared with
    // project view's `WorkspaceStore.computeSessionGroups`. Never re-derive
    // membership locally; both views must call the same function.

    /// Pure, testable variant of the `pinnedSessions` instance property.
    /// Pinning is layered ON TOP of `SessionBucket.membership` (see
    /// `SessionSection.section(isPinned:bucket:)`) — a pinned session is
    /// excluded from `activeSessions`/`inactiveSessions`/`archiveSessions`
    /// below regardless of its bucket.
    static func pinnedSessions(from sessions: [AgentSession]) -> [AgentSession] {
        orderedBySessionViewOrder(sorted(sessions: sessions.filter(\.isPinned)))
    }

    /// Pure, testable variant of the `activeSessions` instance property.
    static func activeSessions(
        from sessions: [AgentSession],
        statuses: [UUID: SessionStatus]
    ) -> [AgentSession] {
        orderedBySessionViewOrder(sorted(sessions: sessions.filter {
            !$0.isPinned && SessionBucket.membership(status: statuses[$0.id], startedThisLaunch: false) == .active
        }))
    }

    /// Pure, testable variant of the `inactiveSessions` instance property —
    /// `sessionIdsStartedThisLaunch` is passed in rather than read from a
    /// coordinator so this stays a pure function callers can test directly.
    /// Ordering matches `activeSessions` (append order, then
    /// `sessionViewOrder`) — only `archiveSessions` reverses.
    static func inactiveSessions(
        from sessions: [AgentSession],
        statuses: [UUID: SessionStatus],
        sessionIdsStartedThisLaunch: Set<UUID>
    ) -> [AgentSession] {
        orderedBySessionViewOrder(sorted(sessions: sessions.filter {
            !$0.isPinned && SessionBucket.membership(
                status: statuses[$0.id],
                startedThisLaunch: sessionIdsStartedThisLaunch.contains($0.id)
            ) == .inactive
        }))
    }

    /// Pure, testable variant of the `archiveSessions` instance property.
    /// Together with `pinnedSessions`, `activeSessions`, and
    /// `inactiveSessions` this is an exact four-way partition — every
    /// session lands in exactly one section. Sorted newest-first via
    /// `AgentSession.sortedNewestFirst(_:)` — the one bucket that does NOT
    /// keep append order and does NOT use `sessionViewOrder`, per Sean's
    /// call that Archive should read reverse-chronological with no manual
    /// order.
    static func archiveSessions(
        from sessions: [AgentSession],
        statuses: [UUID: SessionStatus],
        sessionIdsStartedThisLaunch: Set<UUID>
    ) -> [AgentSession] {
        let archived = sorted(sessions: sessions.filter {
            !$0.isPinned && SessionBucket.membership(
                status: statuses[$0.id],
                startedThisLaunch: sessionIdsStartedThisLaunch.contains($0.id)
            ) == .archive
        })
        return AgentSession.sortedNewestFirst(archived)
    }

    // MARK: - Auto-Expand Override (static so tests can call without a view instance)

    /// One of the four Sessions-tab sections. Used only to decide which
    /// sections get the selected-session force-expand override below — not
    /// a membership concept (see `belongsInActive`, `inactiveSessions`,
    /// `archiveSessions` for that).
    enum Section {
        case pinned, active, inactive, archive
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

    /// Layers drag-reorder on top of the append-order base from `sorted(sessions:)`.
    /// Sessions with an explicit `sessionViewOrder` sort ascending by it, ahead
    /// of any session without one; sessions without one keep their relative
    /// append/creation order. Only ever called on an already section-filtered
    /// list (Pinned, Active, or Inactive — Archive doesn't call this, see
    /// `archiveSessions`), so `sessionViewOrder` values are only ever compared
    /// within the section they were assigned in.
    static func orderedBySessionViewOrder(_ sessions: [AgentSession]) -> [AgentSession] {
        sessions
            .enumerated()
            .sorted { lhs, rhs in
                switch (lhs.element.sessionViewOrder, rhs.element.sessionViewOrder) {
                case let (l?, r?):
                    if l != r { return l < r }
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

// MARK: - New Session Toolbar Button

/// Labelled toolbar button for the Sessions tab, presented in
/// `WorkspaceSidebarView.titlebarToolbar` right-aligned on the traffic-light
/// row. Opens the centered session composer overlay (Phase 3 of
/// session-creation-unified) instead of the old two-level project → template
/// cascade menu (D7) — see `WorkspaceViewContainer.presentComposerOverlay(projectBinding:)`,
/// reached via `coordinator.containerView` since this view has no direct
/// reference to the AppKit container.
struct NewSessionToolbarButton: View {
    @EnvironmentObject private var coordinator: SessionCoordinator

    @State private var isHovered = false

    var body: some View {
        Button {
            // F9 (Phase 3 review): `coordinator.containerView` is always a
            // `WorkspaceViewContainer` in practice — it's set exactly once,
            // from `WorkspaceViewContainer.viewDidMoveToWindow()` — so this
            // cast is a class invariant, not a real runtime branch. The old
            // `Menu` silently did nothing if the invariant ever broke; assert
            // instead so a regression is caught in development rather than
            // shipping as a silently-dead button.
            guard let container = coordinator.containerView as? WorkspaceViewContainer else {
                assertionFailure("NewSessionToolbarButton: coordinator.containerView is not a WorkspaceViewContainer")
                return
            }
            container.presentComposerOverlay(projectBinding: .open)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                Text("New Session")
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? .primary : .secondary)
        .onHover { isHovered = $0 }
        // F9 (Phase 3 review): with zero projects, the composer's own
        // "+ Add project…" row (in the open project dropdown) is the only
        // way to add one from this tab — disabling the button that reaches
        // it made that path unreachable.
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

    @Environment(\.colorScheme) private var colorScheme

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
                PixelChevronView(isExpanded: isEffectivelyExpanded)
                    .frame(width: WorkspaceLayout.sidebarIconColumnWidth, height: WorkspaceLayout.sidebarIconColumnWidth)

                Text("\(title.uppercased()) \(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(WorkspaceLayout.sectionHeaderForeground(for: colorScheme))

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

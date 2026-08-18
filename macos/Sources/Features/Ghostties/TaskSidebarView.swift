import SwiftUI

/// Top-level task-first sidebar (Concept F). Composes the three zones —
/// Needs you · Active · Archive — plus a muted footer.
///
/// Designed to replace `WorkspaceSidebarView` behind a feature toggle. In
/// Wave 2 this view is standalone; Agent E wires it into the workspace shell
/// in a follow-up commit.
///
/// Width is 280pt (slightly wider than the 220pt legacy sidebar) — Concept F
/// is denser vertically but needs more horizontal room for the hero row's
/// two-line typography.
///
/// U8 (SEA-164): adds the persistent `[+ Start]` button in the header strip
/// (D22) and the inline composer slot driven by `NewTaskComposerStore.shared`.
struct TaskSidebarView: View {
    @ObservedObject var taskStore: TaskStore
    @ObservedObject var sessionDraftStore: SessionDraftStore

    /// U8: composer store — drives [+ Start] button state and the composer card.
    @ObservedObject private var composerStore: NewTaskComposerStore = .shared

    @EnvironmentObject private var workspaceStore: WorkspaceStore
    /// Only used to guard the Cmd+Shift+]/[ notifications to this window
    /// (same `containerView?.window` pattern `WorkspaceSidebarView` uses for
    /// its project/session cycling) — task cycling itself never touches the
    /// terminal or session state.
    @EnvironmentObject private var coordinator: SessionCoordinator
    @Environment(\.colorScheme) private var colorScheme

    /// Cursor for task cycling. Tracks the last task moved to; independent of
    /// native SwiftUI row focus (see `selectAdjacentTask(offset:proxy:)` for
    /// the limitation this implies).
    ///
    /// NOTE: Cmd+Shift+]/[ no longer drives this — that chord now cycles the
    /// active terminal session in every sidebar view (see the
    /// `.workspaceSelectNextSession` / `.workspaceSelectPreviousSession`
    /// `.onReceive` handlers in `body`). `selectAdjacentTask` and its
    /// `.workspaceSelectNextTask` / `.workspaceSelectPreviousTask` wiring stay
    /// in place, unreachable until they're given their own binding.
    @State private var taskCyclingCursorId: String?

    var body: some View {
        VStack(spacing: 0) {
            // D22: header strip with [+ Start] button at top-right.
            sidebarHeader

            ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Six-zone layout — locked order from the brief:
                    //
                    //   1. Inbox      — external arrivals (source-based); hides when empty
                    //   2. Backlog    — planned but not started; header always visible
                    //   3. Active     — running tasks + unpromoted session drafts; hides when empty
                    //   4. Needs you  — awaiting human input; always visible (reserved height)
                    //   5. Review     — done by agent, awaiting sign-off; header always visible
                    //   6. Graveyard  — Done tasks only; hides when empty
                    //
                    // Zone dividers are emitted only when the preceding zone
                    // rendered content (rows or a reserved-height empty state).
                    // Zone 1: Inbox — hides entirely when empty (special case).
                    InboxZoneView(
                        taskStore: taskStore,
                        workspaceStore: workspaceStore,
                        composerStore: composerStore
                    )
                    // Only emit the trailing divider when the inbox actually
                    // rendered rows (or is empty with the composer open).
                    if !taskStore.externalInbox.isEmpty || composerStore.isOpen {
                        zoneDivider
                    }

                    // Zone 2: Backlog — header always visible, body collapses when empty.
                    BacklogZoneView(taskStore: taskStore)
                    zoneDivider

                    // Zone 3: Active / Running — fully hidden when empty.
                    // "Empty" means no running tasks AND no unpromoted session drafts.
                    let activeIsEmpty = taskStore.active.isEmpty && sessionDraftStore.drafts.filter { $0.promotedToTaskId == nil }.isEmpty
                    if !activeIsEmpty {
                        ActiveZoneView(
                            taskStore: taskStore,
                            sessionDraftStore: sessionDraftStore
                        )
                        zoneDivider
                    }

                    // Zone 4: Needs you — always visible (reserved-height empty state).
                    NeedsYouZoneView(taskStore: taskStore)
                    zoneDivider

                    // Zone 5: Review — header always visible, body collapses when empty.
                    ReviewZoneView(taskStore: taskStore)
                    zoneDivider

                    // Zone 6: Graveyard — Done tasks only; hidden when empty.
                    if !taskStore.done.isEmpty {
                        GraveyardZoneView(taskStore: taskStore)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onReceive(NotificationCenter.default.publisher(for: .workspaceSelectNextTask)) { notification in
                guard notification.object as? NSWindow === coordinator.containerView?.window else { return }
                selectAdjacentTask(offset: 1, proxy: proxy)
            }
            .onReceive(NotificationCenter.default.publisher(for: .workspaceSelectPreviousTask)) { notification in
                guard notification.object as? NSWindow === coordinator.containerView?.window else { return }
                selectAdjacentTask(offset: -1, proxy: proxy)
            }
            }

            footer
        }
        .frame(maxHeight: .infinity)
        .background(backgroundColor)
        // U8: Observe the notification that AppDelegate's ⌘⇧N monitor posts.
        .onReceive(NotificationCenter.default.publisher(for: .openNewTaskComposer)) { _ in
            composerStore.open(workspaceStore: workspaceStore)
        }
        // Cmd+Shift+]/[ session cycling (browser-tab mental model), same
        // chord and same `SessionCoordinator.focusAdjacentLiveSession(offset:in:)`
        // helper `WorkspaceSidebarView` uses for the Projects/Sessions tabs.
        // Task-first mode has no project rows to expand/select, so this just
        // switches the active terminal — the task-cycling cursor below
        // (`selectAdjacentTask`) no longer owns this chord.
        .onReceive(NotificationCenter.default.publisher(for: .workspaceSelectNextSession)) { notification in
            guard notification.object as? NSWindow === coordinator.containerView?.window else { return }
            let liveSessions = workspaceStore.sessionsInVisualOrder(coordinator: coordinator)
            _ = coordinator.focusAdjacentLiveSession(offset: 1, in: liveSessions)
        }
        .onReceive(NotificationCenter.default.publisher(for: .workspaceSelectPreviousSession)) { notification in
            guard notification.object as? NSWindow === coordinator.containerView?.window else { return }
            let liveSessions = workspaceStore.sessionsInVisualOrder(coordinator: coordinator)
            _ = coordinator.focusAdjacentLiveSession(offset: -1, in: liveSessions)
        }
    }

    // MARK: - Task cycling (Cmd+Shift+]/[, task-first mode)

    /// Flat rendered order across all six zones, mirroring `body`'s zone
    /// sequence: Inbox → Backlog → Active → Needs you → Review → Graveyard.
    /// Session drafts in the Active zone are intentionally excluded — they
    /// aren't `TaskItem`s and have no independent row-click identity.
    private var flatTaskCycleOrder: [TaskItem] {
        taskStore.sortedExternalInbox
            + taskStore.backlog
            + taskStore.active
            + taskStore.needsYou
            + taskStore.review
            + taskStore.done
    }

    /// Moves the task-cycling cursor to the next/previous task in
    /// `flatTaskCycleOrder`, wrapping at both ends, and scrolls it into view.
    /// No-ops (no beep, no crash) when there are zero tasks.
    ///
    /// LIMITATION: this does not drive native SwiftUI keyboard focus
    /// (`@FocusState` lives inside `TaskRowView`, which this view doesn't
    /// own) so it doesn't move the visual focus ring or update
    /// `RowFocusStore` — Return/⌘O still act on whichever row last had real
    /// keyboard focus, independent of this cursor. It's scroll-to-reveal
    /// only. It also can't scroll to a task currently rendered in the Active
    /// zone: `ActiveZoneView` gives its merged rows a `"task:<id>"`-prefixed
    /// `ForEach` identity rather than the bare task id, so `scrollTo` silently
    /// no-ops for those rows specifically (still advances the cursor).
    private func selectAdjacentTask(offset: Int, proxy: ScrollViewProxy) {
        let order = flatTaskCycleOrder
        guard !order.isEmpty else { return }

        guard let currentId = taskCyclingCursorId,
              let currentIndex = order.firstIndex(where: { $0.id == currentId }) else {
            let target = offset > 0 ? order[0] : order[order.count - 1]
            taskCyclingCursorId = target.id
            withAnimation { proxy.scrollTo(target.id, anchor: .center) }
            return
        }

        let newIndex = (currentIndex + offset + order.count) % order.count
        let target = order[newIndex]
        taskCyclingCursorId = target.id
        withAnimation { proxy.scrollTo(target.id, anchor: .center) }
    }

    // MARK: - Header strip (D22)

    /// Sticky header with a low-contrast `[+ Start]` button at top-right.
    /// Stays outside the ScrollView so it doesn't scroll away.
    private var sidebarHeader: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            // D22: low-contrast chrome button — NOT terracotta.
            Button {
                composerStore.open(workspaceStore: workspaceStore)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Start")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color.primary.opacity(0.60))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                // D20: rgba(255,255,255,0.08) background — no terracotta.
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
            .help("New task — ⌘⇧N")
            .accessibilityLabel("Start a new task")
            .accessibilityHint("Opens the new task composer. Keyboard shortcut: Command Shift N")
            .padding(.trailing, TaskRowMetrics.horizontalPadding)
        }
        .frame(height: 28)
        .background(backgroundColor)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(height: 1)
        }
    }

    // MARK: - Zone divider

    /// 1pt zone separator. Slightly stronger than the 0.5pt intra-zone row
    /// dividers so the three zones read as distinct regions of the sidebar.
    private var zoneDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 0) {
            Text("tasks · \(taskStore.tasks.count)")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(colorScheme == .dark ? WorkspaceLayout.textSecondaryDark : WorkspaceLayout.textSecondaryLight)

            Spacer(minLength: 0)

            Image(systemName: "gearshape")
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        }
        .padding(.horizontal, TaskRowMetrics.horizontalPadding)
        .frame(height: 30)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
        }
    }

    // MARK: - Background

    private var backgroundColor: Color {
        Color(nsColor: colorScheme == .dark
              ? WorkspaceLayout.chromeBackgroundDark
              : WorkspaceLayout.chromeBackgroundLight)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Task Sidebar — Light + Dark") {
    let ws = WorkspaceStore(testingProjects: [])
    let coordinator = SessionCoordinator()
    HStack(spacing: 24) {
        TaskSidebarView(
            taskStore: TaskStore(),
            sessionDraftStore: SessionDraftStore()
        )
        .environmentObject(ws)
        .environmentObject(coordinator)
        .preferredColorScheme(.light)
        TaskSidebarView(
            taskStore: TaskStore(),
            sessionDraftStore: SessionDraftStore()
        )
        .environmentObject(ws)
        .environmentObject(coordinator)
        .preferredColorScheme(.dark)
    }
    .padding(24)
    .frame(height: 780)
}
#endif

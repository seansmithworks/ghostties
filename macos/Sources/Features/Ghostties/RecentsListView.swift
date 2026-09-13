import SwiftUI
import GhosttiesCore
import UniformTypeIdentifiers

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

    /// Transient live-reflow drag state (BACKLOG item G) — the proposed gap
    /// position while a drag is in progress. Never written to the persisted
    /// model; only `performGapDrop`/`applySectionDropAction` (a real drop) do
    /// that. Cleared on a successful drop, on drag-exit-without-a-drop, and
    /// on Escape — see `SessionDragState.cancel()` and
    /// `installDragEndMonitors()`.
    @State private var dragState = SessionDragState()
    @State private var escapeMonitor: Any?
    @State private var mouseUpMonitor: Any?
    @State private var autoScrollTimer: Timer?
    @State private var autoScrollAnchorId: String?

    init() {
        #if DEBUG
        self.skipScrollViewForTesting = false
        #endif
    }

    #if DEBUG
    /// Test/preview-only seam for injecting transient drag-reflow state
    /// without driving a real pointer — used by the temporary render-evidence
    /// harness for the live-reflow visual proof. Also renders every section
    /// expanded, unwrapped by `ScrollView` (`skipScrollViewForTesting`) —
    /// `ImageRenderer` does not render `ScrollView` content in that harness's
    /// execution context (confirmed with a trivial `ScrollView { Text(...) }`
    /// control case). This branch must live inside `body` itself, not a
    /// separately-called method, so `@EnvironmentObject` resolves normally
    /// through SwiftUI's own view-graph processing. Never referenced by the
    /// shipped app.
    init(previewDragState: SessionDragState) {
        self._dragState = State(initialValue: previewDragState)
        self.skipScrollViewForTesting = true
    }
    #endif

    #if DEBUG
    private let skipScrollViewForTesting: Bool

    /// `false` only for the temporary render-evidence harness. Static
    /// `ImageRenderer` capture (no real interactive drag session, no
    /// WindowServer compositing) renders every `.onDrag`/`.onDrop`-decorated
    /// view with a baked-in "operation not permitted" cursor badge — found
    /// while capturing this feature's own evidence PNGs, confirmed by
    /// removing the modifiers and watching the badge disappear. Real drags
    /// in the shipped app never show this; it is purely a static-capture
    /// artifact, so evidence renders skip attaching the drag modifiers
    /// entirely rather than ship a visibly-wrong screenshot.
    private var dragInteractionsEnabledForRendering: Bool { !skipScrollViewForTesting }
    #else
    private var dragInteractionsEnabledForRendering: Bool { true }
    #endif

    /// Sessions relaunched via a drop onto Active — held in their drop slot
    /// (rendered as Active) until `store.globalStatuses[id]?.isAlive` flips
    /// true, or 5s elapses, whichever comes first. Prevents the "flash in its
    /// old section while the terminal launches" flicker from item 6, without
    /// touching `SessionBucket.membership`. Purely a render-time overlay —
    /// see `applyPendingLaunchOverride(active:inactive:archive:)`.
    @State private var pendingLaunchSessionIds: Set<UUID> = []

    /// Section-collapse state, persisted across launches. Active and
    /// Inactive default open (sessions the user is working with today, or
    /// just stopped); Archive defaults closed.
    @AppStorage("ghostties.sessionsSection.pinned") private var isPinnedExpanded = true
    @AppStorage("ghostties.sessionsSection.active") private var isActiveExpanded = true
    @AppStorage("ghostties.sessionsSection.inactive") private var isInactiveExpanded = true
    @AppStorage("ghostties.sessionsSection.archive") private var isArchiveExpanded = false

    /// Whether the system's Reduce Motion accessibility setting is on — the
    /// reflow gap and section transitions still update instantly, just
    /// without animation, when this is true (item 5).
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Short, critically-damped spring for the live-reflow gap — DESIGN.md
    /// defines no motion tokens for this repo, so this targets ~200ms per
    /// the brief. `nil` under Reduce Motion (item 5).
    private var reflowAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 1.0)
    }

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

        // Item 6: hold a just-relaunched session in Active's drop slot until
        // its terminal actually comes up (or the timeout fires) — render-time
        // only, never touches `SessionBucket.membership`. See
        // `applyPendingLaunchOverride`.
        let displayed = applyPendingLaunchOverride(active: active, inactive: inactive, archive: archive)
        let displayActive = displayed.active
        let displayInactive = displayed.inactive
        let displayArchive = displayed.archive

        // The full cross-section id order, used only to walk the list one
        // row at a time during edge auto-scroll (item 4) — never used for
        // membership or persistence.
        let orderedRowIds = rowScrollIds(pinned: pinned, active: displayActive, inactive: displayInactive, archive: displayArchive)

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
                    sectionContainsSelectedSession: selectedId.map { id in displayActive.contains { $0.id == id } } ?? false
                )
                let inactiveExpanded = Self.effectiveExpanded(
                    storedPreference: isInactiveExpanded,
                    section: .inactive,
                    sectionContainsSelectedSession: selectedId.map { id in displayInactive.contains { $0.id == id } } ?? false
                )
                let archiveExpanded = Self.effectiveExpanded(
                    storedPreference: isArchiveExpanded,
                    section: .archive,
                    sectionContainsSelectedSession: selectedId.map { id in displayArchive.contains { $0.id == id } } ?? false
                )

                #if DEBUG
                if skipScrollViewForTesting {
                    // See the doc comment on the `previewDragState` init.
                    sectionsContent(
                        pinned: pinned,
                        displayActive: displayActive,
                        displayInactive: displayInactive,
                        displayArchive: displayArchive,
                        pinnedExpanded: true,
                        activeExpanded: true,
                        inactiveExpanded: true,
                        archiveExpanded: true
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                } else {
                    sessionsScrollView(
                        pinned: pinned,
                        displayActive: displayActive,
                        displayInactive: displayInactive,
                        displayArchive: displayArchive,
                        pinnedExpanded: pinnedExpanded,
                        activeExpanded: activeExpanded,
                        inactiveExpanded: inactiveExpanded,
                        archiveExpanded: archiveExpanded,
                        orderedRowIds: orderedRowIds
                    )
                }
                #else
                sessionsScrollView(
                    pinned: pinned,
                    displayActive: displayActive,
                    displayInactive: displayInactive,
                    displayArchive: displayArchive,
                    pinnedExpanded: pinnedExpanded,
                    activeExpanded: activeExpanded,
                    inactiveExpanded: inactiveExpanded,
                    archiveExpanded: archiveExpanded,
                    orderedRowIds: orderedRowIds
                )
                #endif
            }

            Spacer(minLength: 0)
        }
        .background(.clear)
        .onChange(of: dragState.isDragging) { isDragging in
            if isDragging {
                installDragEndMonitors()
            } else {
                removeDragEndMonitors()
                stopAutoScroll()
            }
        }
        .onDisappear {
            removeDragEndMonitors()
            stopAutoScroll()
        }
    }

    // MARK: - Sections Content

    /// The Sessions tab's actual section list — headers, rows, the
    /// live-reflow gap, and every drop zone. Factored out of `sessionsScrollView`
    /// so `body` can also render it unwrapped by `ScrollView` under
    /// `skipScrollViewForTesting` (`#if DEBUG` only) — see that flag's doc
    /// comment. Nothing here is test-only: production's `ScrollView` wraps
    /// this exact same content.
    @ViewBuilder
    private func sectionsContent(
        pinned: [AgentSession],
        displayActive: [AgentSession],
        displayInactive: [AgentSession],
        displayArchive: [AgentSession],
        pinnedExpanded: Bool,
        activeExpanded: Bool,
        inactiveExpanded: Bool,
        archiveExpanded: Bool
    ) -> some View {
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
            // belongs to. An in-progress drag renders an
            // explicit "Drop to pin" zone here instead (item 2)
            // so pinning a first session no longer requires the
            // context menu.
            if !pinned.isEmpty {
                SessionSectionHeader(
                    title: "Pinned",
                    count: pinned.count,
                    isExpanded: $isPinnedExpanded,
                    isEffectivelyExpanded: pinnedExpanded
                )
                if pinnedExpanded {
                    sectionRows(pinned, section: .pinned)
                    endDropZone(section: .pinned, sectionList: pinned)
                }
            } else if dragState.isDragging {
                SessionSectionHeader(
                    title: "Pinned",
                    count: 0,
                    isExpanded: $isPinnedExpanded,
                    isEffectivelyExpanded: true
                )
                emptyPinnedDropZone
            }

            // All three lifecycle headers always render (when
            // there's at least one session anywhere) —
            // membership adapts, but the ACTIVE/INACTIVE/ARCHIVE
            // headers themselves never disappear. Every header
            // carries a count; a collapsed header with no count
            // is illegible.
            SessionSectionHeader(
                title: "Active",
                count: displayActive.count,
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
                sectionRows(displayActive, section: .active)
                endDropZone(section: .active, sectionList: displayActive)
            }

            SessionSectionHeader(
                title: "Inactive",
                count: displayInactive.count,
                isExpanded: $isInactiveExpanded,
                isEffectivelyExpanded: inactiveExpanded
            )
            if inactiveExpanded {
                // See the identity comment on the Active ForEach
                // above — same reasoning applies here.
                sectionRows(displayInactive, section: .inactive)
                endDropZone(section: .inactive, sectionList: displayInactive)
            }

            SessionSectionHeader(
                title: "Archive",
                count: displayArchive.count,
                isExpanded: $isArchiveExpanded,
                isEffectivelyExpanded: archiveExpanded
            )
            if archiveExpanded {
                // See the identity comment on the Active ForEach
                // above — same reasoning applies here. Archive is
                // never a reflow/drop target (item 1) — plain rows,
                // no gap, no end zone.
                ForEach(displayArchive) { session in
                    sessionRow(for: session, section: .archive, sectionList: displayArchive)
                }
            }
        }
    }

    /// Production's real `ScrollView` — `sectionsContent` plus reflow
    /// animation, accessibility label, and the auto-scroll edge zones (item
    /// 4), which need `scrollProxy` and so make no sense outside a
    /// `ScrollViewReader`.
    private func sessionsScrollView(
        pinned: [AgentSession],
        displayActive: [AgentSession],
        displayInactive: [AgentSession],
        displayArchive: [AgentSession],
        pinnedExpanded: Bool,
        activeExpanded: Bool,
        inactiveExpanded: Bool,
        archiveExpanded: Bool,
        orderedRowIds: [String]
    ) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                sectionsContent(
                    pinned: pinned,
                    displayActive: displayActive,
                    displayInactive: displayInactive,
                    displayArchive: displayArchive,
                    pinnedExpanded: pinnedExpanded,
                    activeExpanded: activeExpanded,
                    inactiveExpanded: inactiveExpanded,
                    archiveExpanded: archiveExpanded
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .animation(reflowAnimation, value: dragState)
            }
            .accessibilityLabel("Sessions")
            .overlay(alignment: .top) { autoScrollEdgeZone(direction: -1, orderedRowIds: orderedRowIds, scrollProxy: scrollProxy) }
            .overlay(alignment: .bottom) { autoScrollEdgeZone(direction: 1, orderedRowIds: orderedRowIds, scrollProxy: scrollProxy) }
        }
    }

    // MARK: - Section Rows (drag-reflow aware)

    /// One droppable section's rows, with the live-reflow gap spliced in at
    /// `dragState.gap`'s index when it targets this section. The dragged
    /// session's own row is omitted entirely — its original slot collapses
    /// so there is never a double gap (item 1).
    @ViewBuilder
    private func sectionRows(_ list: [AgentSession], section: SessionSection) -> some View {
        ForEach(rowSlots(for: list, section: section)) { slot in
            switch slot.kind {
            case .session(let session):
                sessionRow(for: session, section: section, sectionList: list)
            case .gap:
                SessionDragGapView()
            }
        }
    }

    private struct SessionRowSlot: Identifiable {
        enum Kind {
            case session(AgentSession)
            case gap
        }
        let id: String
        let kind: Kind
    }

    private func rowSlots(for list: [AgentSession], section: SessionSection) -> [SessionRowSlot] {
        var working = list
        if let draggingId = dragState.draggingSessionId {
            working.removeAll { $0.id == draggingId }
        }
        var slots = working.map { SessionRowSlot(id: $0.id.uuidString, kind: .session($0)) }
        if let gap = dragState.gap, gap.section == section {
            let insertAt = min(gap.index ?? slots.count, slots.count)
            slots.insert(SessionRowSlot(id: "gap-\(section.rawValue)", kind: .gap), at: insertAt)
        }
        return slots
    }

    /// Every rendered row id across all four sections, in visual order —
    /// used only to walk the list one row at a time during edge auto-scroll
    /// (item 4). Rebuilt each body pass from the same lists already being
    /// rendered, so it always matches what auto-scroll can actually see.
    private func rowScrollIds(pinned: [AgentSession], active: [AgentSession], inactive: [AgentSession], archive: [AgentSession]) -> [String] {
        (pinned + active + inactive + archive).map { $0.id.uuidString }
    }

    // MARK: - Drop Zones

    /// The end-of-section drop target (item 2) — lets a drag land after the
    /// last row without having to hit the bottom half of that row exactly.
    /// Renders with zero height when no drag is in progress.
    @ViewBuilder
    private func endDropZone(section: SessionSection, sectionList: [AgentSession]) -> some View {
        let base = Color.clear
            .frame(height: dragState.isDragging ? 8 : 0)
            .contentShape(Rectangle())
        if dragInteractionsEnabledForRendering {
            base.onDrop(of: [.text], delegate: SessionEndZoneDropDelegate(
                section: section,
                dragState: $dragState,
                resolveGap: { draggedSection, draggedIsOpen in
                    SessionDragReflow.endInsertionPoint(draggedSection: draggedSection, draggedIsOpen: draggedIsOpen, targetSection: section)
                },
                draggedContext: { [self] id in draggedContext(for: id) },
                performDrop: { [self] draggedId, gap in performGapDrop(draggedId: draggedId, gap: gap, targetList: sectionList) }
            ))
        } else {
            base
        }
    }

    /// An empty Pinned section's stand-in drop target, sized like one row
    /// (item 2). Only rendered while a drag is in progress and Pinned is
    /// currently empty.
    @ViewBuilder
    private var emptyPinnedDropZone: some View {
        let base = HStack {
            Text("Drop to pin")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.leading, WorkspaceLayout.sidebarRowLeadingPadding)
        .frame(height: SessionDragReflow.rowHeight)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .contentShape(Rectangle())
        if dragInteractionsEnabledForRendering {
            base.onDrop(of: [.text], delegate: SessionEndZoneDropDelegate(
                section: .pinned,
                dragState: $dragState,
                resolveGap: { draggedSection, draggedIsOpen in
                    SessionDragReflow.endInsertionPoint(draggedSection: draggedSection, draggedIsOpen: draggedIsOpen, targetSection: .pinned)
                },
                draggedContext: { [self] id in draggedContext(for: id) },
                performDrop: { [self] draggedId, gap in performGapDrop(draggedId: draggedId, gap: gap, targetList: []) }
            ))
        } else {
            base
        }
    }

    /// This session's current section + open state, resolved from the store
    /// — the shared context every drop delegate needs to call
    /// `SessionDragReflow`/`SessionSectionDrop.resolve`.
    private func draggedContext(for id: UUID) -> (section: SessionSection, isOpen: Bool)? {
        guard let session = store.sessions.first(where: { $0.id == id }) else { return nil }
        let bucket = SessionBucket.membership(
            status: store.globalStatuses[id],
            startedThisLaunch: coordinator.sessionIdsStartedThisLaunch.contains(id)
        )
        let section = SessionSection.section(isPinned: session.isPinned, bucket: bucket)
        let isOpen = store.globalStatuses[id]?.isAlive == true
        return (section, isOpen)
    }

    /// Applies a resolved gap as a real drop — the one call site shared by
    /// every row and drop-zone delegate. Re-derives the actual
    /// `SessionSectionDrop` action (never trusts the gap's section alone) so
    /// the mutation always matches decision 3 exactly.
    private func performGapDrop(draggedId: UUID, gap: SessionDragReflow.GapPosition, targetList: [AgentSession]) -> Bool {
        guard let draggedSession = store.sessions.first(where: { $0.id == draggedId }),
              let context = draggedContext(for: draggedId) else { return false }

        let action = SessionSectionDrop.resolve(
            draggedSection: context.section,
            draggedIsOpen: context.isOpen,
            targetSection: gap.section
        )
        guard action != .reject else { return false }

        let workingList = targetList.filter { $0.id != draggedId }
        let beforeId = gap.index.flatMap { idx in workingList.indices.contains(idx) ? workingList[idx].id : nil }

        applySectionDropAction(action, draggedId: draggedId, draggedSession: draggedSession, beforeId: beforeId, targetList: targetList)
        return true
    }

    /// Escape while dragging reverts to "no drag in progress" — the same
    /// path `SessionDragState.cancel()` gives drag-exit-without-a-drop.
    ///
    /// Also installs a `leftMouseUp` monitor as the revert path for a drag
    /// released over dead space (no row, zone, or header claims the drop) —
    /// `DropDelegate` has no "the drag ended and nobody claimed it" callback
    /// of its own. `performDrop` already calls `dragState.cancel()`
    /// synchronously for every claimed drop, so this only fires when nothing
    /// did. NOT runtime-verified against a live `NSDraggingSession` — the
    /// app cannot be launched from this task (see brief) — worth Sean
    /// confirming on his next real drag.
    private func installDragEndMonitors() {
        if escapeMonitor == nil {
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53 /* Escape */ else { return event }
                dragState.cancel()
                return nil
            }
        }
        if mouseUpMonitor == nil {
            mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
                DispatchQueue.main.async {
                    if dragState.isDragging { dragState.cancel() }
                }
                return event
            }
        }
    }

    private func removeDragEndMonitors() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        escapeMonitor = nil
        if let mouseUpMonitor {
            NSEvent.removeMonitor(mouseUpMonitor)
        }
        mouseUpMonitor = nil
    }

    // MARK: - Auto-Scroll (item 4)

    /// A thin invisible drop target pinned to the top or bottom edge of the
    /// Sessions scroll view. While a drag hovers it, steps the scroll
    /// position one row at a time toward that edge on a fixed cadence.
    /// `direction` is -1 (toward the top) or +1 (toward the bottom).
    ///
    /// A `DropDelegate`, not `.onDrop(of:isTargeted:)` — the `isTargeted`
    /// binding variant renders a static "operation not permitted" drag-cursor
    /// decoration baked into the view even outside an active drag session
    /// (found while capturing this feature's own render-evidence PNGs via
    /// `ImageRenderer`), which every other drop target in this file already
    /// avoids by using a delegate.
    private func autoScrollEdgeZone(direction: Int, orderedRowIds: [String], scrollProxy: ScrollViewProxy) -> some View {
        Color.clear
            .frame(height: 24)
            .contentShape(Rectangle())
            .allowsHitTesting(dragState.isDragging)
            .onDrop(of: [.text], delegate: SessionAutoScrollEdgeDropDelegate(
                onHover: { startAutoScroll(direction: direction, orderedRowIds: orderedRowIds, scrollProxy: scrollProxy) },
                onExit: { stopAutoScroll() }
            ))
    }

    private func startAutoScroll(direction: Int, orderedRowIds: [String], scrollProxy: ScrollViewProxy) {
        stopAutoScroll()
        if autoScrollAnchorId == nil {
            // The dragged session's own id is always present in
            // `orderedRowIds` (its row is only removed from render slots,
            // never from the source lists this is built from) — a reliable
            // starting point to walk from, unlike a gap id, which only
            // exists in the section's render slots, not in `orderedRowIds`.
            autoScrollAnchorId = dragState.draggingSessionId?.uuidString ?? orderedRowIds.first
        }
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [self] _ in
            guard let anchor = autoScrollAnchorId,
                  let currentIndex = orderedRowIds.firstIndex(of: anchor) else { return }
            let nextIndex = currentIndex + direction
            guard orderedRowIds.indices.contains(nextIndex) else { return }
            autoScrollAnchorId = orderedRowIds[nextIndex]
            withAnimation(reduceMotion ? nil : .linear(duration: 0.12)) {
                scrollProxy.scrollTo(orderedRowIds[nextIndex], anchor: direction < 0 ? .top : .bottom)
            }
        }
    }

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        autoScrollAnchorId = nil
    }

    // MARK: - Pending Launch Override (item 6)

    /// Holds a just-relaunched session (dropped onto Active) in its Active
    /// drop slot until `store.globalStatuses` reports it alive, or the 5s
    /// timeout scheduled by `scheduleLaunchPendingTimeout` clears it —
    /// whichever comes first. Render-time only: `SessionBucket.membership`
    /// is untouched, and
    /// once a session is genuinely alive, real membership already agrees
    /// (the override becomes a no-op — see the `active.contains` check
    /// below).
    private func applyPendingLaunchOverride(
        active: [AgentSession],
        inactive: [AgentSession],
        archive: [AgentSession]
    ) -> (active: [AgentSession], inactive: [AgentSession], archive: [AgentSession]) {
        guard !pendingLaunchSessionIds.isEmpty else { return (active, inactive, archive) }
        var active = active
        var inactive = inactive
        var archive = archive
        var stillPending = pendingLaunchSessionIds
        for id in pendingLaunchSessionIds {
            if active.contains(where: { $0.id == id }) {
                // Already alive per real membership — override is done.
                stillPending.remove(id)
                continue
            }
            if let idx = inactive.firstIndex(where: { $0.id == id }) {
                active.append(inactive.remove(at: idx))
            } else if let idx = archive.firstIndex(where: { $0.id == id }) {
                active.append(archive.remove(at: idx))
            } else {
                // Session removed/deleted mid-flight — nothing left to hold.
                stillPending.remove(id)
            }
        }
        if stillPending != pendingLaunchSessionIds {
            DispatchQueue.main.async { pendingLaunchSessionIds = stillPending }
        }
        return (active, inactive, archive)
    }

    private func scheduleLaunchPendingTimeout(for id: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            pendingLaunchSessionIds.remove(id)
        }
    }

    // MARK: - Session Row

    private func sessionRow(for session: AgentSession, section: SessionSection, sectionList: [AgentSession]) -> some View {
        let project = store.projects.first { $0.id == session.projectId }
        let projectName = project?.name ?? "Unknown"
        let indicatorState = store.globalIndicatorStates[session.id] ?? .inactive
        // Archive has no manual order (always newest-first) — no reorder
        // affordances (drop target, Move Up/Down) on its rows. It's still a
        // valid DRAG SOURCE, since decision 3 lets it be dragged up into
        // Active/Pinned; that's `.onDrag` below, applied unconditionally —
        // `supportsReorder` only gates the drop-delegate side.
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
        .modifier(SessionRowDragModifier(
            isEnabled: dragInteractionsEnabledForRendering,
            session: session,
            dragState: $dragState
        ))
        .modifier(SessionRowDropModifier(
            isEnabled: supportsReorder && dragInteractionsEnabledForRendering,
            section: section,
            sectionList: sectionList,
            hoveredSession: session,
            dragState: $dragState,
            draggedContext: { [self] id in draggedContext(for: id) },
            performDrop: { [self] draggedId, gap in performGapDrop(draggedId: draggedId, gap: gap, targetList: sectionList) }
        ))
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

    /// Applies a resolved `SessionDropAction`. This is the ONE call site
    /// that turns a drop into a store mutation — every row's
    /// `SessionRowDropDelegate`, every section's end-of-list zone, and the
    /// empty-Pinned zone all funnel through `performGapDrop` above into
    /// here. Everything decision-related still lives in the pure
    /// `SessionSectionDrop.resolve`, tested directly in
    /// `SessionSectionDropTests`.
    private func applySectionDropAction(
        _ action: SessionDropAction,
        draggedId: UUID,
        draggedSession: AgentSession,
        beforeId: UUID?,
        targetList: [AgentSession]
    ) {
        switch action {
        case .reject:
            return
        case .reorder:
            store.moveSessionInSessionsView(id: draggedId, before: beforeId, within: targetList)
        case .pin:
            store.setSessionPinned(id: draggedId, true)
            store.moveSessionInSessionsView(id: draggedId, before: beforeId, within: targetList)
        case .unpin(let relaunchIfClosed):
            store.setSessionPinned(id: draggedId, false)
            if relaunchIfClosed {
                pendingLaunchSessionIds.insert(draggedId)
                scheduleLaunchPendingTimeout(for: draggedId)
                relaunchSession(draggedSession, project: store.projects.first { $0.id == draggedSession.projectId })
            }
            store.moveSessionInSessionsView(id: draggedId, before: beforeId, within: targetList)
        case .relaunch:
            pendingLaunchSessionIds.insert(draggedId)
            scheduleLaunchPendingTimeout(for: draggedId)
            relaunchSession(draggedSession, project: store.projects.first { $0.id == draggedSession.projectId })
            store.moveSessionInSessionsView(id: draggedId, before: beforeId, within: targetList)
        }
    }

    /// VoiceOver/keyboard reorder within one section — the accessible
    /// counterpart to drag-reorder. `direction` is -1 (up) or +1 (down); a
    /// move past either end of the section is a no-op. Adjacent swap,
    /// expressed as "insert before" the id that will end up on the other
    /// side of the swap — same rule drag-drop uses, so both paths share one
    /// insertion semantic in `WorkspaceStore.moveSessionInSessionsView`.
    private func moveWithinSection(session: AgentSession, indexInSection: Int?, direction: Int, sectionList: [AgentSession]) {
        guard let indexInSection else { return }
        let target = indexInSection + direction
        guard target >= 0, target < sectionList.count else { return }

        let beforeId: UUID?
        if direction < 0 {
            // Moving up: insert before whatever currently sits at `target`.
            beforeId = sectionList[target].id
        } else {
            // Moving down: insert before whatever comes right after `target`
            // (nil — drop at end — if `target` is the last row).
            let afterTarget = target + 1
            beforeId = afterTarget < sectionList.count ? sectionList[afterTarget].id : nil
        }
        store.moveSessionInSessionsView(id: session.id, before: beforeId, within: sectionList)
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

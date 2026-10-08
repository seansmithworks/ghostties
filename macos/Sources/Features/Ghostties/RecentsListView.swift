import SwiftUI
import GhosttiesCore
import UniformTypeIdentifiers

/// The Sessions tab content: a flat, time-sorted list of all sessions across projects.
///
/// Layout (mock I3, `SidebarSessionSections`):
///   Pinned 2  (isPinned — hidden when empty; stays pinned whether open or closed)
///   Active 5  (the session's terminal is open — see `SessionBucket.membership`)
///   History   (one row standing in for every inactive + archived session;
///              selecting it opens the history browser in the canvas),
///              pinned above the tray; hidden unless "History in sidebar" is on
/// Section labels are quiet, non-collapsible headers — no chevrons.
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

    /// Folded projects in the one-view list (`ProjectAccordionState`).
    @AppStorage(ProjectAccordionState.collapsedKey, store: SidebarDialTuning.store) private var collapsedProjectsRaw = ""
    @AppStorage("ghostties.sidebarTab") private var sidebarTab: SidebarTab = .projects

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
    /// see `applyPendingLaunchOverride(active:inactive:archive:)`. Keyed by a
    /// per-session generation (BACKLOG I) rather than a plain `Set<UUID>`, so
    /// a timeout only ever clears the hold it was scheduled for — see
    /// `PendingLaunchHold`.
    @State private var pendingLaunchGenerations: [UUID: Int] = [:]

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
        // Bound once per body pass — the section model filters the session
        // list into its buckets once (`SidebarSessionSections.make`).
        let sections = SidebarSessionSections.make(
            sessions: store.sessions,
            statuses: store.globalStatuses,
            sessionIdsStartedThisLaunch: coordinator.sessionIdsStartedThisLaunch
        )

        // Item 6: hold a just-relaunched session in Active's drop slot until
        // its terminal actually comes up (or the timeout fires) — render-time
        // only, never touches `SessionBucket.membership`. See
        // `applyPendingLaunchOverride`.
        let displayed = applyPendingLaunchOverride(active: sections.active, inactive: sections.inactive, archive: sections.archived)
        let displaySections = SidebarSessionSections(
            pinned: sections.pinned,
            active: displayed.active,
            inactive: displayed.inactive,
            archived: displayed.archive
        )

        // The full row id order, used only to walk the list one row at a
        // time during edge auto-scroll (item 4) — never used for membership
        // or persistence.
        let orderedRowIds = displaySections.rowSessions.map { $0.id.uuidString }

        // History (when shown) is pinned below the list as `layout.footer`.
        // The rail renders the same layout (`SidebarRailView`).
        let layout = displaySections.layout(showsHistory: SidebarDialTuning.historyInSidebar())

        VStack(spacing: 0) {
            if store.sessions.isEmpty {
                emptyState
            } else {
                #if DEBUG
                if skipScrollViewForTesting {
                    // See the doc comment on the `previewDragState` init.
                    sectionsContent(displaySections, slots: layout.list)
                        .modifier(SidebarColumnPadding())
                } else {
                    sessionsScrollView(displaySections, slots: layout.list, orderedRowIds: orderedRowIds)
                }
                #else
                sessionsScrollView(displaySections, slots: layout.list, orderedRowIds: orderedRowIds)
                #endif
            }

            Spacer(minLength: 0)

            // History and its hairline, outside the scrolling
            // area, so a long list never scrolls it away. The tray's
            // reserved space (`WorkspaceSidebarView`) already holds the
            // list-to-tray gap; this adds the row gap above it.
            if !store.sessions.isEmpty && !layout.footer.isEmpty {
                VStack(spacing: SidebarDialTuning.rowGap()) {
                    ForEach(layout.footer, id: \.self) { slot in
                        slotContent(slot, displaySections)
                    }
                }
                .modifier(SidebarColumnPadding(horizontalOnly: true))
                .padding(.bottom, SidebarSessionSections.historyToTrayGap() - SidebarDialTuning.listToTrayGap())
            }
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

    /// The Sessions tab's actual section list — rows, hairlines, the History
    /// row, the live-reflow gap, and every drop zone. Factored out of
    /// `sessionsScrollView` so `body` can also render it unwrapped by
    /// `ScrollView` under `skipScrollViewForTesting` (`#if DEBUG` only) — see
    /// that flag's doc comment. Nothing here is test-only: production's
    /// `ScrollView` wraps this exact same content.
    @ViewBuilder
    private func sectionsContent(_ sections: SidebarSessionSections, slots: [SidebarSessionSections.Slot]) -> some View {
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
        // timestamp updates.
        VStack(spacing: SidebarDialTuning.rowGap()) {
            // Pinned is the one section that's hidden entirely
            // when empty — it's an opt-in section. An in-progress
            // drag renders an explicit "Drop to pin" zone here
            // instead (item 2) so pinning a first session no
            // longer requires the context menu.
            if SessionPinning.isAvailable && sections.pinned.isEmpty && dragState.isDragging {
                emptyPinnedDropZone
            }
            ForEach(slots, id: \.self) { slot in
                slotContent(slot, sections)
            }
        }
    }

    /// One slot of the section layout (`SidebarSessionSections.Slot`), the
    /// same sequence `SidebarRailView` renders.
    @ViewBuilder
    private func slotContent(_ slot: SidebarSessionSections.Slot, _ sections: SidebarSessionSections) -> some View {
        switch slot {
        case .pinnedRows:
            sectionRows(sections.pinned, section: .pinned)
        case .pinnedEnd:
            endDropZone(section: .pinned, sectionList: sections.pinned)
        case .activeRows:
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
            if SidebarProjectsLayout.effective(tab: sidebarTab) == .oneView {
                groupedActiveRows(sections.active)
            } else {
                sectionRows(sections.active, section: .active)
            }
        case .activeEnd:
            endDropZone(section: .active, sectionList: sections.active)
        case .history:
            // Inactive and archived sessions never render as rows — one
            // History row stands in for them (mock I3) and opens the
            // history browser in the canvas.
            HistoryRowView(
                subtitle: HistorySummary.subtitle(count: sections.historyCount, lastActiveAt: sections.historyLastActiveAt),
                isActive: coordinator.isHistoryPresented,
                staggerIndex: sections.active.count,
                dialEpoch: SidebarDialTuning.epoch(),
                onTap: { coordinator.presentHistory() }
            )
        }
    }

    /// Production's real `ScrollView` — `sectionsContent` plus reflow
    /// animation, accessibility label, and the auto-scroll edge zones (item
    /// 4), which need `scrollProxy` and so make no sense outside a
    /// `ScrollViewReader`.
    private func sessionsScrollView(_ sections: SidebarSessionSections, slots: [SidebarSessionSections.Slot], orderedRowIds: [String]) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                sectionsContent(sections, slots: slots)
                    .modifier(SidebarColumnPadding())
                    .animation(reflowAnimation, value: dragState)
            }
            .accessibilityLabel("Sessions")
            .redlineFrame(RedlineID.listViewport)
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

    /// One view (`SidebarProjectsLayout.oneView`, mock B5): Active's rows
    /// under one accordion header per project. Drag and drop still act on
    /// the whole Active list (`sectionList`), so a reorder lands at the
    /// same place in every layout; the live gap shows before the row it
    /// targets, or after the last row for a drop at the end.
    @ViewBuilder
    private func groupedActiveRows(_ active: [AgentSession]) -> some View {
        let groups = SidebarProjectGroup.make(active: active, projects: store.projects)
        let items = SidebarProjectGroupItem.items(groups, collapsed: ProjectAccordionState.decode(collapsedProjectsRaw))
        let gapBeforeId = groupedGapTarget(active)
        ForEach(items) { item in
            switch item {
            case .spacer:
                Color.clear
                    .frame(height: SidebarProjectGroupItem.spacerHeight)
                    .accessibilityHidden(true)
            case .header(let group, let isCollapsed):
                ProjectAccordionHeader(name: group.name, count: group.sessions.count, isCollapsed: isCollapsed, isEmpty: group.isEmpty) {
                    ProjectAccordionState.headerClicked(group, collapsedRaw: $collapsedProjectsRaw) { projectId in
                        ProjectSelection.select(projectId, store: store, coordinator: coordinator, window: coordinator.containerView?.window)
                    }
                }
            case .row(let session, _):
                if session.id != dragState.draggingSessionId {
                    if gapBeforeId == .some(session.id) {
                        SessionDragGapView()
                    }
                    sessionRow(
                        for: session, section: .active, sectionList: active,
                        subtitle: (store.globalIndicatorStates[session.id] ?? .inactive).statusGlyphKind.groupedRowSubtitle
                    )
                }
            }
        }
        if gapBeforeId == .some(nil) {
            SessionDragGapView()
        }
    }

    /// Where the live drag gap sits among Active's rows: before the session
    /// returned, or at the end for `.some(nil)`. Nil when no gap targets
    /// Active. Same index rule as `rowSlots`.
    private func groupedGapTarget(_ active: [AgentSession]) -> UUID?? {
        guard let gap = dragState.gap, gap.section == .active else { return nil }
        let working = active.filter { $0.id != dragState.draggingSessionId }
        let index = min(gap.index ?? working.count, working.count)
        return .some(index < working.count ? working[index].id : nil)
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
        let section = SessionSection.section(isPinned: session.isPinnedForDisplay(), bucket: bucket)
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
    /// timeout scheduled by `beginPendingLaunch(for:)` clears it — whichever
    /// comes first. Render-time only: `SessionBucket.membership`
    /// is untouched, and
    /// once a session is genuinely alive, real membership already agrees
    /// (the override becomes a no-op — see the `active.contains` check
    /// below).
    private func applyPendingLaunchOverride(
        active: [AgentSession],
        inactive: [AgentSession],
        archive: [AgentSession]
    ) -> (active: [AgentSession], inactive: [AgentSession], archive: [AgentSession]) {
        guard !pendingLaunchGenerations.isEmpty else { return (active, inactive, archive) }
        var active = active
        var inactive = inactive
        var archive = archive
        var stillPending = pendingLaunchGenerations
        for id in pendingLaunchGenerations.keys {
            if active.contains(where: { $0.id == id }) {
                // Already alive per real membership — override is done.
                stillPending.removeValue(forKey: id)
                continue
            }
            if let idx = inactive.firstIndex(where: { $0.id == id }) {
                active.append(inactive.remove(at: idx))
            } else if let idx = archive.firstIndex(where: { $0.id == id }) {
                active.append(archive.remove(at: idx))
            } else {
                // Session removed/deleted mid-flight — nothing left to hold.
                stillPending.removeValue(forKey: id)
            }
        }
        if stillPending != pendingLaunchGenerations {
            DispatchQueue.main.async { pendingLaunchGenerations = stillPending }
        }
        return (active, inactive, archive)
    }

    /// Begins (or restarts) a hold for `id` and schedules its 5s timeout,
    /// tagged with the generation `PendingLaunchHold.begin` just minted so
    /// the timeout only clears the hold it was scheduled for (BACKLOG I) —
    /// see `PendingLaunchHold.timeoutShouldClear`.
    private func beginPendingLaunch(for id: UUID) {
        let started = PendingLaunchHold.begin(id: id, in: pendingLaunchGenerations)
        pendingLaunchGenerations = started.generations
        let token = started.token
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard PendingLaunchHold.timeoutShouldClear(id: id, token: token, in: pendingLaunchGenerations) else { return }
            pendingLaunchGenerations.removeValue(forKey: id)
        }
    }

    // MARK: - Session Row

    private func sessionRow(for session: AgentSession, section: SessionSection, sectionList: [AgentSession], subtitle: String? = nil) -> some View {
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
            hookUnconfirmed: coordinator.codexHookUnconfirmed(for: session),
            subtitle: subtitle,
            isActive: coordinator.sidebarSelectedSessionId == session.id,
            isEditing: editingSessionId == session.id,
            editingName: editingSessionId == session.id ? $editingName : .constant(""),
            isRenameFocused: $renameFieldFocused,
            onTap: { coordinator.focusSession(id: session.id) },
            onCommitRename: { commitRename(session: session) },
            onCancelRename: { cancelRename() },
            staggerIndex: indexInSection ?? 0,
            dialEpoch: SidebarDialTuning.epoch()
        )
        .equatable()
        .contextMenu {
            Button("Rename") {
                beginRename(session: session)
            }
            Divider()
            if SessionPinning.isAvailable {
                Button(session.isPinned ? "Unpin" : "Pin") {
                    store.toggleSessionPin(id: session.id)
                }
                Divider()
            }
            if coordinator.isRunning(id: session.id) {
                Button("Stop") {
                    // A stopped session must never keep rendering as Active
                    // for the rest of an open relaunch hold (BACKLOG I) —
                    // end it outright rather than wait out the timeout.
                    pendingLaunchGenerations = PendingLaunchHold.end(id: session.id, in: pendingLaunchGenerations)
                    coordinator.closeSession(id: session.id)
                }
            } else {
                if session.resume != nil {
                    Button("Resume") {
                        relaunchSession(session, mode: .resume)
                    }
                }
                Button("Start Fresh") {
                    relaunchSession(session, mode: .fresh)
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
                beginPendingLaunch(for: draggedId)
                relaunchSession(draggedSession, mode: draggedSession.resume != nil ? .resume : .fresh)
            }
            store.moveSessionInSessionsView(id: draggedId, before: beforeId, within: targetList)
        case .relaunch:
            beginPendingLaunch(for: draggedId)
            relaunchSession(draggedSession, mode: draggedSession.resume != nil ? .resume : .fresh)
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

    private func relaunchSession(_ session: AgentSession, mode: SessionCoordinator.RelaunchMode) {
        _Concurrency.Task {
            await coordinator.relaunch(session: session, mode: mode)
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
    static func pinnedSessions(
        from sessions: [AgentSession],
        pinningAvailable: Bool = SessionPinning.isAvailable
    ) -> [AgentSession] {
        orderedBySessionViewOrder(sorted(sessions: sessions.filter {
            $0.isPinnedForDisplay(pinningAvailable: pinningAvailable)
        }))
    }

    /// Pure, testable variant of the `activeSessions` instance property.
    static func activeSessions(
        from sessions: [AgentSession],
        statuses: [UUID: SessionStatus],
        pinningAvailable: Bool = SessionPinning.isAvailable
    ) -> [AgentSession] {
        orderedBySessionViewOrder(sorted(sessions: sessions.filter {
            !$0.isPinnedForDisplay(pinningAvailable: pinningAvailable) && SessionBucket.membership(status: statuses[$0.id], startedThisLaunch: false) == .active
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
        sessionIdsStartedThisLaunch: Set<UUID>,
        pinningAvailable: Bool = SessionPinning.isAvailable
    ) -> [AgentSession] {
        orderedBySessionViewOrder(sorted(sessions: sessions.filter {
            !$0.isPinnedForDisplay(pinningAvailable: pinningAvailable) && SessionBucket.membership(
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
        sessionIdsStartedThisLaunch: Set<UUID>,
        pinningAvailable: Bool = SessionPinning.isAvailable
    ) -> [AgentSession] {
        let archived = sorted(sessions: sessions.filter {
            !$0.isPinnedForDisplay(pinningAvailable: pinningAvailable) && SessionBucket.membership(
                status: statuses[$0.id],
                startedThisLaunch: sessionIdsStartedThisLaunch.contains($0.id)
            ) == .archive
        })
        return AgentSession.sortedNewestFirst(archived)
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
        .environmentObject(SidebarWidthModel(width: 220))
        .frame(width: 220, height: 500)
        .preferredColorScheme(.dark)
}

#Preview("Sessions — empty") {
    let store = WorkspaceStore(testingProjects: [])
    let coordinator = SessionCoordinator()
    return RecentsListView()
        .environmentObject(store)
        .environmentObject(coordinator)
        .environmentObject(SidebarWidthModel(width: 220))
        .frame(width: 220, height: 500)
        .preferredColorScheme(.dark)
}
#endif

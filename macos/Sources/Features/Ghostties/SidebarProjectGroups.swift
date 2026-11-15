import SwiftUI
import GhosttiesCore

// MARK: - Projects layout (sidebar vnext B5)

/// How the sidebar presents projects (the "Projects layout" dial).
///
/// - `tabs`: a Projects tab and a Sessions tab, switched from the View menu.
/// - `oneView`: one list, no tabs (mock B5). Pinned stays on top; every
///   other live session sits under its project's accordion header. The rail
///   heads each project's sessions with a monogram tile.
enum SidebarProjectsLayout: String, CaseIterable {
    case tabs
    case oneView

    /// The default (Sean, 2026-10-08): one view.
    static let shipped: SidebarProjectsLayout = .oneView

    /// The layout actually on screen. One view is the Projects tab's
    /// layout only; the Sessions tab is always its flat list.
    static func effective(dial: SidebarProjectsLayout, tab: SidebarTab) -> SidebarProjectsLayout {
        tab == .projects ? dial : .tabs
    }

    /// `effective` for the live dial.
    static func effective(tab: SidebarTab) -> SidebarProjectsLayout {
        effective(dial: SidebarDialTuning.projectsLayout(), tab: tab)
    }
}

/// Which body the sidebar mounts below the titlebar.
enum SidebarBodyKind: Equatable {
    case oneViewAccordion
    case sessionsList
    case projectsList

    static func resolve(tab: SidebarTab, dial: SidebarProjectsLayout) -> SidebarBodyKind {
        switch tab {
        case .sessions: return .sessionsList
        case .projects: return dial == .oneView ? .oneViewAccordion : .projectsList
        }
    }
}

/// The one-view list's project order, which the rail shares (mild2wild
/// 2026-10-21 card 01, "Spacing only"): pinned projects first, in
/// `WorkspaceStore.projects` order (the manual drag order), then every other
/// project by name — case-insensitive, numbers in numeric order, ties in
/// array order. The sort is display-only: `workspace.json` keeps its order.
/// Everything that orders one-view projects (`SidebarProjectGroup.make`,
/// project drag and keyboard moves) reads this. Only pinned projects
/// reorder (`SidebarProjectGroup.isReorderable`), and
/// `WorkspaceStore.moveProject` keeps a move inside its group.
enum ProjectListOrder {
    static func pinnedFirst(_ projects: [Project]) -> [Project] {
        let rest = projects.enumerated().filter { !$0.element.isPinned }.sorted { a, b in
            // `localizedStandardCompare` without its forced ordering, which
            // would break a case-only tie ("app"/"App") by case, not array order.
            switch a.element.name.compare(b.element.name, options: [.caseInsensitive, .numeric, .widthInsensitive], locale: .current) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return a.offset < b.offset
            }
        }
        return projects.filter(\.isPinned) + rest.map(\.element)
    }
}

/// One project's live, unpinned sessions in the one-view list.
struct SidebarProjectGroup: Equatable, Identifiable {
    /// Nil only for sessions whose project no longer exists.
    let projectId: UUID?
    let name: String
    let sessions: [AgentSession]
    /// The project is pinned: its group sits in the pinned block.
    var isPinned = false

    /// Whether a drag or Move Up/Down can move this group: the alphabetical
    /// block has no manual order, so only a pinned project reorders.
    var isReorderable: Bool { projectId != nil && isPinned }

    var id: String { projectId?.uuidString ?? "unknown-project" }

    /// A project with no live, unpinned session: shown dimmed with a count
    /// of 0 and no rows. It never folds; a click selects it instead.
    var isEmpty: Bool { sessions.isEmpty }

    /// Groups `active` (already in render order) by project, in
    /// `ProjectListOrder` (pinned first). Every project gets a group, empty ones included (Sean,
    /// 2026-10-08: show empty projects dimmed with count 0, rather than
    /// mock B5's hidden). Sessions whose project is gone trail in one
    /// "Unknown" group, the name rows already use for them, so no live
    /// session ever drops off the list.
    static func make(active: [AgentSession], projects: [Project]) -> [SidebarProjectGroup] {
        var byProject: [UUID: [AgentSession]] = [:]
        for session in active {
            byProject[session.projectId, default: []].append(session)
        }
        var groups: [SidebarProjectGroup] = ProjectListOrder.pinnedFirst(projects).map { project in
            SidebarProjectGroup(projectId: project.id, name: project.name, sessions: byProject.removeValue(forKey: project.id) ?? [], isPinned: project.isPinned)
        }
        let orphans = active.filter { byProject[$0.projectId] != nil }
        if !orphans.isEmpty {
            groups.append(SidebarProjectGroup(projectId: nil, name: "Unknown", sessions: orphans))
        }
        return groups
    }
}

// MARK: - Flattened items

/// The one-view groups as one flat sequence, so the list and the rail render
/// them inside the section `VStack` with its row gap, slot for slot: every
/// rail tile sits at its header's y, every rail glyph at its row's y.
enum SidebarProjectGroupItem: Identifiable {
    /// Clear space before every group but the first (`spacerHeight`). The
    /// one before the first unpinned project is also the pinned block's
    /// break (`pinnedBreakHeight` taller); while the only pinned project is
    /// dragged that group leads the list, and its spacer is the break alone.
    case spacer(groupId: String, height: CGFloat)
    case header(SidebarProjectGroup, isCollapsed: Bool)
    case row(AgentSession, group: SidebarProjectGroup)
    /// The idle fold's row (`SidebarIdleFold`): after every listed group,
    /// and before the idle ones while it is expanded.
    case idleFold(SidebarIdleFold.Row)

    /// Mock B5's break between groups: the hairline's 6pt margins and 1pt
    /// line (`.hair`). The rule itself now sits in the header.
    static let spacerHeight: CGFloat = 13

    /// Card 01's only separator between the pinned block and the
    /// alphabetical one (`WorkspaceLayout.projectPinnedBreak`), added to the
    /// usual break. The rail renders the same items, so the gap is the same
    /// height in both widths and no tile moves between them.
    static let pinnedBreakHeight: CGFloat = WorkspaceLayout.projectPinnedBreak

    /// The break above the idle fold's row, added to the usual one: the
    /// pinned break's step, so the list has one size of break.
    static let idleBreakHeight: CGFloat = pinnedBreakHeight

    /// The group the pinned break sits before: the first unpinned project,
    /// when a pinned project leads it. Read from the whole list, never the
    /// rendered one, so a pinned drag (which drops its group from the
    /// render) leaves the break where it was.
    static func pinnedBreakGroupId(_ groups: [SidebarProjectGroup]) -> String? {
        guard groups.contains(where: \.isPinned) else { return nil }
        return groups.first { $0.projectId != nil && !$0.isPinned }?.id
    }

    var id: String {
        switch self {
        case .spacer(let groupId, _): return "spacer-\(groupId)"
        case .header(let group, _): return "header-\(group.id)"
        case .row(let session, _): return session.id.uuidString
        case .idleFold: return SidebarIdleFold.rowId
        }
    }

    static func items(
        _ groups: [SidebarProjectGroup], collapsed: Set<UUID>, idleFold: SidebarIdleFold.Row? = nil
    ) -> [SidebarProjectGroupItem] {
        items(groups, collapsed: collapsed, pinnedBreakBefore: pinnedBreakGroupId(groups), idleFold: idleFold)
    }

    /// `pinnedBreakBefore` is `pinnedBreakGroupId` of the whole list when
    /// `groups` is the rendered one with a dragged group removed.
    /// `idleFold` is the fold's row (`SidebarIdleFold.Arrangement.row`),
    /// with `groups` in the arrangement's order: the row sits one break
    /// below whatever is above it, before its first idle group, or last
    /// while folded.
    static func items(
        _ groups: [SidebarProjectGroup], collapsed: Set<UUID>, pinnedBreakBefore: String?,
        idleFold: SidebarIdleFold.Row? = nil
    ) -> [SidebarProjectGroupItem] {
        var items: [SidebarProjectGroupItem] = []
        var foldPlaced = false
        func placeFold(_ row: SidebarIdleFold.Row) {
            if !items.isEmpty {
                items.append(.spacer(groupId: SidebarIdleFold.rowId, height: spacerHeight + idleBreakHeight))
            }
            items.append(.idleFold(row))
            foldPlaced = true
        }
        for group in groups {
            var breakHeight = group.id == pinnedBreakBefore ? pinnedBreakHeight : 0
            if let idleFold, idleFold.beforeGroupId == group.id {
                placeFold(idleFold)
                // The row's own break stands in for a pinned break that
                // would fall on the first idle project.
                breakHeight = 0
            }
            let height = (items.isEmpty ? 0 : spacerHeight) + breakHeight
            if height > 0 {
                items.append(.spacer(groupId: group.id, height: height))
            }
            let isCollapsed = !group.isEmpty && (group.projectId.map(collapsed.contains) ?? false)
            items.append(.header(group, isCollapsed: isCollapsed))
            if !isCollapsed {
                items += group.sessions.map { .row($0, group: group) }
            }
        }
        if let idleFold, !foldPlaced { placeFold(idleFold) }
        return items
    }

    /// The expand cascade over `items` (`SidebarLabelCascade`), from
    /// `start`: each header's index by group id, each row's by session id,
    /// and the index after the last.
    static func cascade(_ items: [SidebarProjectGroupItem], start: Int) -> (headers: [String: Int], rows: [UUID: Int], end: Int) {
        var groupIds: [String] = []
        var rowIds: [[UUID]] = []
        for item in items {
            switch item {
            case .header(let group, _):
                groupIds.append(group.id)
                rowIds.append([])
            case .row(let session, _):
                if !rowIds.isEmpty { rowIds[rowIds.count - 1].append(session.id) }
            case .idleFold:
                groupIds.append(SidebarIdleFold.rowId)
                rowIds.append([])
            case .spacer:
                break
            }
        }
        let indices = SidebarLabelCascade.indices(rowsPerSection: rowIds.map(\.count), start: start)
        var headers: [String: Int] = [:]
        var rows: [UUID: Int] = [:]
        for (section, entry) in indices.enumerated() {
            headers[groupIds[section]] = entry.header
            for (row, index) in entry.rows.enumerated() { rows[rowIds[section][row]] = index }
        }
        return (headers, rows, (indices.last.map { ($0.rows.last ?? $0.header) + 1 }) ?? start)
    }
}

// MARK: - Collapse state

/// Which projects are folded in the one-view list. One persisted set shared
/// by the list and the rail, so folding a project folds it in both.
enum ProjectAccordionState {
    static let collapsedKey = "ghostties.sidebar.collapsedProjects"

    /// The stored form: comma-separated UUID strings (`@AppStorage` has no
    /// set type).
    static func decode(_ raw: String) -> Set<UUID> {
        Set(raw.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    static func encode(_ ids: Set<UUID>) -> String {
        ids.map(\.uuidString).sorted().joined(separator: ",")
    }

    static func toggled(_ raw: String, _ projectId: UUID) -> String {
        var ids = decode(raw)
        if ids.contains(projectId) { ids.remove(projectId) } else { ids.insert(projectId) }
        return encode(ids)
    }

    #if DEBUG
    /// The capture script's fold/unfold: the stored set with `ids` folded
    /// or unfolded.
    static func setFolded(_ raw: String, ids: [UUID], folded: Bool) -> String {
        var set = decode(raw)
        if folded { set.formUnion(ids) } else { set.subtract(ids) }
        return encode(set)
    }
    #endif

    static func expanded(_ raw: String, _ projectId: UUID) -> String {
        var ids = decode(raw)
        ids.remove(projectId)
        return encode(ids)
    }

    /// The fold's spring (`SidebarUISpring.fold`): unfolding is an
    /// entrance and overshoots by the Bounce dial; folding is a close and
    /// settles without one. Reduce Motion: instant.
    static func toggleAnimation(unfolding: Bool) -> Animation? {
        SidebarUISpring.fold.animation(entering: unfolding)
    }

    /// What a click on a project's header (list) or monogram tile (rail)
    /// does: an empty project is selected (`select`); any other project
    /// folds or unfolds, written through `collapsedRaw` — the views'
    /// `@AppStorage` binding, so the fold persists.
    static func headerClicked(_ group: SidebarProjectGroup, collapsedRaw: Binding<String>, select: (UUID) -> Void) {
        guard let projectId = group.projectId else { return }
        if group.isEmpty {
            select(projectId)
            return
        }
        let unfolding = decode(collapsedRaw.wrappedValue).contains(projectId)
        withAnimation(toggleAnimation(unfolding: unfolding)) {
            collapsedRaw.wrappedValue = toggled(collapsedRaw.wrappedValue, projectId)
        }
    }
}

// MARK: - Project selection

enum ProjectSelection {
    /// Selects a project the way the Projects tab's header click and
    /// Next/Previous Project do: record it as the selection, focus its last
    /// session if it has one, and tell this window's Projects tab to mirror
    /// it (`WorkspaceSidebarView` expands and selects it).
    @MainActor
    static func select(_ projectId: UUID, store: WorkspaceStore, coordinator: SessionCoordinator, window: NSWindow?) {
        store.lastSelectedProjectId = projectId
        coordinator.focusLastSession(forProject: projectId)
        NotificationCenter.default.post(
            name: .workspaceDidSelectProjectFromShortcut,
            object: window,
            userInfo: ["projectId": projectId]
        )
    }
}

// MARK: - Paired browser rows

/// A browser an agent opened with `gt browser open` is paired with that
/// terminal at runtime only (`SessionCoordinator.pairedBrowserByTerminal`,
/// terminal id to browser id). Clicking either puts the same screen up, so
/// the pair is ONE sidebar row, the terminal's: the browser has no row of
/// its own, and the terminal's row carries a browser icon. Ending the
/// pairing needs no cleanup here: the browser is an ordinary row again the
/// next time a list is built.
enum PairedBrowserRows {
    /// The glyph for a browser everywhere in the sidebar (the composer's
    /// browser template).
    static let symbolName = "globe"

    /// `sessions` without the browsers paired to a terminal.
    static func visible(_ sessions: [AgentSession], pairedBrowsers: [UUID: UUID]) -> [AgentSession] {
        guard !pairedBrowsers.isEmpty else { return sessions }
        let hidden = Set(pairedBrowsers.values)
        return sessions.filter { !hidden.contains($0.id) }
    }

    /// True when `terminalId` has a paired browser: its row shows the icon.
    static func hasBrowser(_ terminalId: UUID, pairedBrowsers: [UUID: UUID]) -> Bool {
        pairedBrowsers[terminalId] != nil
    }

    /// The row that stands for `sessionId`: its terminal when it is a paired
    /// browser, itself otherwise.
    static func rowId(for sessionId: UUID, pairedBrowsers: [UUID: UUID]) -> UUID {
        pairedBrowsers.first { $0.value == sessionId }?.key ?? sessionId
    }
}

// MARK: - Row subtitle

extension SessionStatusGlyphKind {
    /// The one-view row subtitle. The project is the header above, so the
    /// row says what the session is doing instead (mock B5 wording).
    var groupedRowSubtitle: String {
        switch self {
        case .working:    return "working"
        case .needsInput: return "needs you"
        case .done:       return "done"
        case .error:      return "error"
        case .stopped:    return "stopped"
        }
    }
}

/// Whether a row genuinely needs the user: the one rule behind its "needs
/// you" subtitle and its project's "N need you" count. A needs-attention
/// indicator counts unless the session's Claude hook state says otherwise,
/// so a cached indicator that outlived its prompt (the hook has since gone
/// idle, e.g. `idle_prompt`) does not. With a hook state, genuine means
/// `SessionAttention` finds a question; with none, the indicator is the
/// only evidence and stands.
enum SessionNeedsYou {
    static func isGenuine(indicator: SessionIndicatorState, state: ClaudeState?) -> Bool {
        guard indicator == .needsAttention else { return false }
        guard let state else { return true }
        return SessionAttention.make(indicator: indicator, state: state) != nil
    }

    /// The status a one-view row stands for. A needs-attention row its
    /// hook state contradicts stands for what the hook state says instead.
    static func shownKind(indicator: SessionIndicatorState, state: ClaudeState?) -> SessionStatusGlyphKind {
        guard indicator == .needsAttention, !isGenuine(indicator: indicator, state: state), let state else {
            return indicator.statusGlyphKind
        }
        let hookIndicator = SessionCoordinator.claudeIndicator(kind: state.state, isLongRunning: false) ?? .idle
        return hookIndicator.statusGlyphKind
    }

    /// The one-view row subtitle: `shownKind` in words.
    static func subtitle(indicator: SessionIndicatorState, state: ClaudeState?) -> String {
        shownKind(indicator: indicator, state: state).groupedRowSubtitle
    }

    /// The trailing label of a project header: "N need you" while any of
    /// its rows genuinely needs the user, else its session count.
    static func headerCountLabel(sessionCount: Int, needYou: Int) -> String {
        needYou > 0 ? "\(needYou) need you" : "\(sessionCount)"
    }
}

/// What a row that genuinely needs the user (`SessionNeedsYou`) shows
/// inline (hover-approvals card 01): its question as the subtitle ("Run npm
/// test?", "Which env name?", or "needs you" when the hook carried none),
/// then an action line. Approve/Deny answer only a fresh bounded prompt
/// (`approvalPrompt`) and draw only while `ApprovalFlag` is on; every other
/// needs-you row hands off with "Answer in terminal →". Nil for a row that
/// doesn't need the user, which gets no action line.
struct SessionRowPrompt: Equatable {
    let question: String?
    /// The prompt Approve/Deny would answer, for the responder's stale guard.
    let approvalPrompt: SessionPopoverContent.ApprovalPrompt?

    var subtitle: String { question ?? SessionStatusGlyphKind.needsInput.groupedRowSubtitle }

    /// `canAnswerInline` is false when no single surface can be targeted (a split session); the row then hands off.
    static func make(indicator: SessionIndicatorState, state: ClaudeState?, now: Date = Date(), canAnswerInline: Bool = true) -> SessionRowPrompt? {
        guard SessionNeedsYou.isGenuine(indicator: indicator, state: state) else { return nil }
        guard let state, let attention = SessionAttention.make(indicator: indicator, state: state) else {
            return SessionRowPrompt(question: nil, approvalPrompt: nil)
        }
        switch attention {
        case let .freeform(question):
            let text = question?.trimmingCharacters(in: .whitespacesAndNewlines)
            return SessionRowPrompt(question: text?.isEmpty == false ? text : nil, approvalPrompt: nil)
        case let .bounded(prompt, command):
            let toolName = state.structuredPrompt?.toolName ?? ""
            let answerable = canAnswerInline && SessionPopoverContent.isFreshApproval(state, now: now) && state.structuredPrompt != nil
            return SessionRowPrompt(
                question: SessionPopoverContent.boundedQuestion(prompt: prompt, toolName: toolName, command: command),
                approvalPrompt: answerable
                    ? SessionPopoverContent.ApprovalPrompt(updatedAt: state.updatedAt, fingerprint: ApprovalFingerprint.make(state))
                    : nil
            )
        }
    }
}

// MARK: - Idle fold

/// One view folds every idle project into one row at the bottom of the
/// list, "Idle · N" (Sean, 2026-11-15, "Idle folded").
///
/// A project is active while any of its threads is working or needs you;
/// every other project (no threads, or only done, stopped or error ones) is
/// idle. Pinned projects never fold, and neither does the "Unknown" group.
/// The project holding the selected thread shows outside the fold: it is
/// where the user is. Clicking the row shows the idle projects under it, as
/// they draw anywhere else; the choice persists (`expandedKey`), folded by
/// default. With no idle project there is no row.
enum SidebarIdleFold {
    /// The fold's persisted state: true while the idle projects show.
    static let expandedKey = "ghostties.sidebar.idleProjectsExpanded"

    /// The fold row's id among the list's items and in the expand cascade.
    static let rowId = "idle-projects"

    static func isExpanded(defaults: UserDefaults = SidebarDialTuning.store) -> Bool {
        defaults.bool(forKey: expandedKey)
    }

    static func setExpanded(_ expanded: Bool, defaults: UserDefaults = SidebarDialTuning.store) {
        defaults.set(expanded, forKey: expandedKey)
    }

    /// The row's label.
    static func label(count: Int) -> String { "Idle · \(count)" }

    /// A project is active while a thread of it is working or needs you.
    /// `kinds` are its threads' statuses as their rows show them
    /// (`SessionNeedsYou.shownKind`).
    static func isActive(_ kinds: [SessionStatusGlyphKind]) -> Bool {
        kinds.contains { $0 == .working || $0 == .needsInput }
    }

    /// The active projects among `groups`.
    static func activeProjectIds(
        _ groups: [SidebarProjectGroup], kind: (AgentSession) -> SessionStatusGlyphKind
    ) -> Set<UUID> {
        Set(groups.compactMap { group in
            guard let projectId = group.projectId, isActive(group.sessions.map(kind)) else { return nil }
            return projectId
        })
    }

    /// The projects that belong outside the fold right now: the active
    /// ones, and the one holding the selected thread.
    static func unfolded(active: Set<UUID>, selectedProjectId: UUID?) -> Set<UUID> {
        selectedProjectId.map { active.union([$0]) } ?? active
    }

    /// The projects drawn outside the fold. `held` is `unfolded` as it was
    /// when the pointer entered the list, nil while the pointer is outside:
    /// a project changes sides only once the pointer has left, so no row
    /// moves under it. One exception: the selected thread's project comes
    /// out of a closed fold at once, because its row has to exist.
    static func shown(live: Set<UUID>, held: Set<UUID>?, selectedProjectId: UUID?, isExpanded: Bool) -> Set<UUID> {
        guard var shown = held else { return live }
        if let selectedProjectId, !isExpanded { shown.insert(selectedProjectId) }
        return shown
    }

    /// The fold row, as the list draws it.
    struct Row: Equatable {
        /// How many projects the fold holds.
        var count: Int
        var isExpanded: Bool
        /// The first idle group, which the row sits before while expanded;
        /// nil while folded, when the row ends the list.
        var beforeGroupId: String?
    }

    /// The one-view groups either side of the fold.
    struct Arrangement: Equatable {
        /// Pinned projects, then the unfolded ones, then "Unknown": in
        /// `SidebarProjectGroup.make`'s order.
        var listed: [SidebarProjectGroup]
        /// The idle projects, in the same order.
        var idle: [SidebarProjectGroup]
        var isExpanded: Bool

        /// The groups the list draws, in order.
        var groups: [SidebarProjectGroup] { listed + (isExpanded ? idle : []) }

        /// The fold row; nil with no idle project.
        var row: Row? {
            idle.isEmpty ? nil : Row(count: idle.count, isExpanded: isExpanded, beforeGroupId: isExpanded ? idle.first?.id : nil)
        }
    }

    /// Splits `groups` (`SidebarProjectGroup.make`) at the fold: a group
    /// folds when it is a real, unpinned project that `unfolded` leaves out.
    static func arrange(_ groups: [SidebarProjectGroup], unfolded: Set<UUID>, isExpanded: Bool) -> Arrangement {
        var arrangement = Arrangement(listed: [], idle: [], isExpanded: isExpanded)
        for group in groups {
            if let projectId = group.projectId, !group.isPinned, !unfolded.contains(projectId) {
                arrangement.idle.append(group)
            } else {
                arrangement.listed.append(group)
            }
        }
        return arrangement
    }

    /// What a click on the row does: shows or hides the idle projects on
    /// the fold's spring, written through `expanded` (the views'
    /// `@AppStorage` binding, so it persists). Reduce Motion: instant.
    static func rowClicked(expanded: Binding<Bool>) {
        let unfolding = !expanded.wrappedValue
        withAnimation(ProjectAccordionState.toggleAnimation(unfolding: unfolding)) {
            expanded.wrappedValue = unfolding
        }
    }
}

/// The idle fold's row (`SidebarIdleFold`): `[tile] IDLE · N ⌄`, drawn as a
/// quiet project header: the dimmed tile of an empty project, the header's
/// type in the dimmed ink, and its chevron. On the rail it is the tile
/// alone. Clicking anywhere on it shows or hides the idle projects.
struct IdleProjectsFoldRow: View {
    /// The tile's face: more projects are behind it.
    static let tileText = "…"

    let count: Int
    let isExpanded: Bool
    /// The row's place in the expand cascade (`SidebarLabelCascade`).
    var staggerIndex: Int = 0
    let onToggle: () -> Void

    @ChromeScheme private var colorScheme
    @EnvironmentObject private var widthModel: SidebarWidthModel
    @Environment(\.sidebarMorphOverride) private var morphOverride
    @Environment(\.sidebarMorphDials) private var morphDials
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
    @FocusState private var isFocused: Bool

    static func accessibilityLabel(count: Int) -> String {
        "Idle projects, \(count)"
    }

    static func accessibilityHint(isExpanded: Bool) -> String {
        isExpanded ? "Hides the idle projects" : "Shows the idle projects"
    }

    var body: some View {
        let progress = morphOverride ?? widthModel.morph
        let metrics = widthModel.metrics(progress, dials: morphDials)
        let dials = metrics.dials
        let slot = dials.sidebarTileSize
        let label = SidebarIdleFold.label(count: count)
        // A tap gesture and a focus stop, like a project header.
        HStack(spacing: 0) {
            Color.clear
                .frame(width: slot, height: slot)
                .overlay {
                    MorphTileFace(
                        progress: progress,
                        sizes: (dials.sidebarTileSize, dials.railTileSize),
                        textSizes: (
                            dials.tileTextSize(rail: false, letters: 1),
                            dials.tileTextSize(rail: true, letters: 1)
                        ),
                        monogram: Self.tileText,
                        isEmpty: true,
                        isSelectedProject: false,
                        redlineID: RedlineID.header(SidebarIdleFold.rowId) + ".tile",
                        badgeCount: nil
                    )
                }
                .modifier(MorphTravel(distance: metrics.tileTravel, progress: progress))
                .padding(.trailing, WorkspaceLayout.sidebarIconLabelSpacing)
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .monospacedDigit()
                .lineLimit(1)
                .modifier(MorphLabelFade(element: .names, staggerIndex: staggerIndex))
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .rotationEffect(.degrees(isExpanded ? 0 : -90))
                .frame(width: ProjectAccordionHeader.chevronWidth)
                .padding(.leading, 4)
                .modifier(MorphLabelFade(element: .trailingCluster, staggerIndex: staggerIndex))
            Spacer(minLength: 0)
        }
        .foregroundStyle(SidebarColors.dimmedProject(colorScheme))
        .padding(.leading, SidebarDialTuning.rowLeadingPadding())
        .padding(.trailing, SidebarDialTuning.rowTrailingPadding())
        .modifier(MorphHeight(from: dials.sidebarHeaderHeight, to: dials.railHeaderHeight, progress: progress))
        .redlineFrame(RedlineID.header(SidebarIdleFold.rowId))
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        // Mid-morph the row is in flight: no clicks land.
        .allowsHitTesting(!widthModel.isMorphing)
        .help(progress >= 0.5 ? label : "")
        .modifier(HeaderFocusStop())
        .focused($isFocused)
        .overlay(alignment: .leading) {
            if isFocused {
                Rectangle()
                    .fill(SidebarColors.secondaryText(colorScheme))
                    .frame(width: 2)
                    .allowsHitTesting(false)
            }
        }
        .modifier(ToggleKeyActivation(action: onToggle))
        .accessibilityElement(children: .ignore)
        .accessibilityAction(.default, onToggle)
        .accessibilityLabel(Self.accessibilityLabel(count: count))
        .accessibilityValue(isExpanded ? "expanded" : "collapsed")
        .accessibilityAddTraits([.isHeader, .isButton])
        .accessibilityHint(Self.accessibilityHint(isExpanded: isExpanded))
    }
}

// MARK: - Monograms

enum ProjectMonogram {
    /// One letter per project, uppercased. When two projects in `names`
    /// share a first letter, each of those gets two: the initials of its
    /// first two words (`atlas-api` → `AA`), else its first two letters.
    static func monograms(for names: [String]) -> [String] {
        let firsts = names.map { first(of: $0, count: 1) }
        var counts: [String: Int] = [:]
        for f in firsts { counts[f, default: 0] += 1 }
        return zip(names, firsts).map { name, f in
            (counts[f] ?? 0) > 1 ? two(of: name) : f
        }
    }

    private static func words(_ name: String) -> [Substring] {
        name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    }

    private static func first(of name: String, count: Int) -> String {
        let letters = words(name).joined()
        return letters.isEmpty ? "?" : String(letters.prefix(count)).uppercased()
    }

    private static func two(of name: String) -> String {
        let parts = words(name)
        if parts.count >= 2, let a = parts[0].first, let b = parts[1].first {
            return String([a, b]).uppercased()
        }
        return first(of: name, count: 2)
    }
}

// MARK: - Expanded header

/// Keyboard-only focus stop: on macOS 14+ a mouse click doesn't take focus
/// (so it can't pull it from the terminal or leave the mark lit) and the
/// system ring is off so it doesn't stack on the custom mark.
private struct HeaderFocusStop: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content.focusable(interactions: .activate).focusEffectDisabled()
        } else {
            content.focusable()
        }
    }
}

/// Space and Return fold the focused header. `onKeyPress` is macOS 14+; on 13
/// the header is still a focus stop but the keys do nothing.
private struct ToggleKeyActivation: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content.onKeyPress(keys: [.space, .return]) { _ in
                action()
                return .handled
            }
        } else {
            content
        }
    }
}

/// A project's accordion header in the one-view list (option D):
/// `[tile] NAME ⌄ ———— count`, on the expanded sidebar and the rail alike.
/// The monogram tile leads, in the column the rows' status glyphs sit in;
/// on the way to the rail its shape scales up to the rail's tile and
/// travels to the rail's centre with that column, in a header that stays
/// 40pt tall throughout, while the name, chevron and count fade
/// (`MorphLabelFade`). A folded project's tile
/// carries its session count on the rail. Clicking anywhere on it, tile
/// included, folds or unfolds the project's rows. An empty project's header
/// is dimmed, has no chevron (nothing to fold), and selects the project
/// instead.
struct ProjectAccordionHeader: View {
    /// The header's height on the sidebar and the rail (keyframe spec D1),
    /// which a tile at or under 40pt sits in.
    static let baseHeight: CGFloat = SidebarMorphMetrics.headerBaseHeight
    /// The header's height in `context` (the expanded header, or the rail's
    /// tile row): grows with that context's project tile, so the tile never
    /// overflows it and the group card, measured from the header's frame,
    /// always encloses the tile.
    static func height(_ context: SidebarTileContext) -> CGFloat {
        max(baseHeight, RailProjectTile.size(context))
    }

    let name: String
    /// `ProjectMonogram.monograms`' entry for this project.
    var monogram: String = "?"
    let count: Int
    /// How many of the project's sessions genuinely need the user
    /// (`SessionNeedsYou`): the trailing label reads "N need you" in place
    /// of `count` while this is above 0.
    var needYouCount: Int = 0
    let isCollapsed: Bool
    var isEmpty: Bool = false
    /// The project holds the selected session: its tile fills with ink.
    var isSelectedProject: Bool = false
    /// The project's resolved icon (`ProjectIconStore`'s cache), drawn in
    /// the tile in place of the monogram; nil draws the monogram.
    var icon: NSImage? = nil
    /// DEBUG Redlines tag (`RedlineID.header`).
    var redlineID: String? = nil
    /// The header's place in the expand cascade (`SidebarLabelCascade`).
    var staggerIndex: Int = 0
    /// DEBUG capture hooks: draw the hover state, and the chip as it is
    /// under the pointer, without a pointer.
    var forceHover: Bool = false
    var forceChipPointed: Bool = false
    /// The quick-create "+" chip (`ProjectHeaderNewThreadButton`); nil for
    /// a group with no project to create in.
    var onNewThread: (() -> Void)?
    let onToggle: () -> Void

    /// The chevron's frame and the count's minimum, at rest; held through
    /// the morph (`SidebarMorphMetrics.trailingClusterWidth`).
    static let chevronWidth: CGFloat = 18
    static let countMinWidth: CGFloat = 18

    /// The "+" chip's side: the rounded square drawn on hover is also the
    /// click target, one size for every project.
    static let newThreadChipSize: CGFloat = 24
    /// The "+" glyph's point size (the header's 11pt type).
    static let newThreadGlyphSize: CGFloat = 11
    /// Clear space between the chip and a "N need you" label beside it.
    static let newThreadLabelGap: CGFloat = 8

    /// The chip's leading edge, from the trailing label's laid-out edges.
    /// Over a plain count its trailing edge is the count's, so it takes the
    /// count's place and sits at the same x whatever the count's width;
    /// beside a "N need you" label it ends one gap before the label, which
    /// stays.
    static func newThreadChipMinX(labelMinX: CGFloat, labelMaxX: CGFloat, needYouCount: Int) -> CGFloat {
        needYouCount > 0
            ? labelMinX - newThreadLabelGap - newThreadChipSize
            : labelMaxX - newThreadChipSize
    }

    /// The room a "N need you" header keeps free before its label for the
    /// chip, always, so a long name never truncates further on hover.
    static func newThreadReserve(needYouCount: Int, canCreate: Bool) -> CGFloat {
        needYouCount > 0 && canCreate ? newThreadChipSize + newThreadLabelGap : 0
    }

    /// The least room between the chevron and the trailing label: 8pt, or
    /// the chip's reserve with 4pt before it (the chevron's own frame
    /// already stands clear of its glyph).
    static func trailingLabelSpacing(needYouCount: Int, canCreate: Bool) -> CGFloat {
        let reserve = newThreadReserve(needYouCount: needYouCount, canCreate: canCreate)
        return reserve > 0 ? reserve + 4 : 8
    }

    /// The chip shows while the pointer is over the header or the chip has
    /// keyboard focus, on the expanded sidebar only (the rail's header is
    /// its tile alone).
    static func showsNewThread(canCreate: Bool, isHovered: Bool, isFocused: Bool, morph: CGFloat) -> Bool {
        canCreate && morph <= 0 && (isHovered || isFocused)
    }

    /// The chip takes a plain count's place; a "N need you" label stays.
    static func hidesCountLabel(showsNewThread: Bool, needYouCount: Int) -> Bool {
        showsNewThread && needYouCount == 0
    }

    /// The chip's fill: the row's hover tint (`SidebarRowChipBackground`),
    /// and while the pointer is on the chip itself the chip ink at the
    /// selected chip's opacity, so it brightens in dark and deepens in
    /// light. (The selected row's own dark tint is black, which would dim
    /// it.)
    static func newThreadChipFill(isPointed: Bool, _ colorScheme: ColorScheme) -> Color {
        isPointed
            ? RailProjectColumn.tintInk(colorScheme).opacity(RailProjectColumn.selectedChipTintOpacity)
            : Color.primary.opacity(RailProjectColumn.hoverChipTintOpacity)
    }

    /// The chip's tooltip and VoiceOver label.
    static func newThreadLabel(project name: String) -> String {
        "New thread in \(name)"
    }

    @ChromeScheme private var colorScheme
    @EnvironmentObject private var widthModel: SidebarWidthModel
    @Environment(\.sidebarMorphOverride) private var morphOverride
    @Environment(\.sidebarMorphDials) private var morphDials
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
    @FocusState private var isFocused: Bool
    @FocusState private var isNewThreadFocused: Bool
    @State private var isHovered = false
    /// The chevron's and count's resting trailing edges in the header's own
    /// space, measured outside their ride (`MorphTrailingClusterRide`), and
    /// the count's leading edge, which places the "+" chip.
    @State private var clusterEdges: [ClusterPart: CGFloat] = [:]

    var body: some View {
        let ink = isEmpty ? SidebarColors.dimmedProject(colorScheme) : SidebarColors.secondaryText(colorScheme)
        let progress = morphOverride ?? widthModel.morph
        let metrics = widthModel.metrics(progress, dials: morphDials)
        let dials = metrics.dials
        let slot = dials.sidebarTileSize
        let showsNewThread = Self.showsNewThread(
            canCreate: onNewThread != nil, isHovered: isHovered || forceHover, isFocused: isNewThreadFocused, morph: progress
        )
        // A tap gesture, not a `Button`: the header is also the project's
        // drag handle (`RecentsListView.groupedActiveRows`), and a macOS
        // `Button` takes the mouse-down that `.onDrag` needs — the session
        // rows tap the same way. VoiceOver keeps the button trait and gets
        // the click as the default action.
        HStack(spacing: 0) {
            // The tile's face only: the whole header is the tap target and
            // the drag handle, so the tile is not a button of its own. Laid
            // out in the sidebar's slot; drawn in a fixed rail-sized square
            // centred on it, its shape scaled to this step's size.
            Color.clear
                .frame(width: slot, height: slot)
                .overlay {
                    MorphTileFace(
                        progress: progress,
                        sizes: (dials.sidebarTileSize, dials.railTileSize),
                        textSizes: (
                            dials.tileTextSize(rail: false, letters: monogram.count),
                            dials.tileTextSize(rail: true, letters: monogram.count)
                        ),
                        monogram: monogram,
                        isEmpty: isEmpty,
                        isSelectedProject: isSelectedProject,
                        redlineID: redlineID.map { $0 + ".tile" },
                        badgeCount: isCollapsed ? count : nil,
                        icon: icon
                    )
                }
                .modifier(MorphTravel(distance: metrics.tileTravel, progress: progress))
                .padding(.trailing, WorkspaceLayout.sidebarIconLabelSpacing)
            HStack(spacing: 0) {
                Text(name.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .redlineFrame(redlineID.map { $0 + ".label" })
                    .layoutPriority(1)
                    .modifier(MorphLabelFade(element: .names, staggerIndex: staggerIndex))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    .frame(width: SidebarMorphMetrics.trailingClusterWidth(resting: Self.chevronWidth, progress: progress))
                    .redlineFrame(redlineID.map { $0 + ".chevron" })
                    .padding(.leading, 4)
                    .opacity(isEmpty ? 0 : 1)
                    .modifier(MorphLabelFade(element: .trailingCluster, staggerIndex: staggerIndex))
                    .modifier(MorphTrailingClusterRide(metrics: metrics, slack: clusterSlack(.chevron), progress: progress))
                    .background(ClusterEdgeReporter(part: .chevron))
                Spacer(minLength: Self.trailingLabelSpacing(needYouCount: needYouCount, canCreate: onNewThread != nil))
                // Never squeezed by a long name: it keeps its own width.
                Text(SessionNeedsYou.headerCountLabel(sessionCount: count, needYou: needYouCount))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .fixedSize()
                    .frame(
                        minWidth: SidebarMorphMetrics.trailingClusterWidth(resting: Self.countMinWidth, progress: progress),
                        alignment: .trailing
                    )
                    // The chip takes a plain count's place on hover; a
                    // "N need you" label stays, with the chip beside it.
                    .opacity(Self.hidesCountLabel(showsNewThread: showsNewThread, needYouCount: needYouCount) ? 0 : 1)
                    .animation(SidebarUISpring.hover.settle(), value: showsNewThread)
                    .modifier(MorphLabelFade(element: .trailingCluster, staggerIndex: staggerIndex))
                    .modifier(MorphTrailingClusterRide(metrics: metrics, slack: clusterSlack(.count), progress: progress))
                    .background(ClusterEdgeReporter(part: .count, leadingPart: .countLeading))
                    // Sized before the name: the frame's 18pt minimum would
                    // otherwise let a long name take the room "2 need you"
                    // draws in, and the two would overlap.
                    .layoutPriority(2)
            }
        }
        .coordinateSpace(name: ClusterEdgeReporter.space)
        .onPreferenceChange(ClusterEdgesKey.self) { clusterEdges = $0 }
        .foregroundStyle(ink)
        .padding(.leading, SidebarDialTuning.rowLeadingPadding())
        .padding(.trailing, SidebarDialTuning.rowTrailingPadding())
        .modifier(MorphHeight(from: dials.sidebarHeaderHeight, to: dials.railHeaderHeight, progress: progress))
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        // Mid-morph the header is in flight: no clicks, drags or drops land.
        .allowsHitTesting(!widthModel.isMorphing)
        .help(progress >= 0.5 ? name : "")
        // Keyboard: a tap gesture isn't a focus stop the way a `Button` is,
        // so the header opts in and folds on Space / Return (macOS 14+, as
        // the task rows do). The leading rule matches their focus mark.
        .modifier(HeaderFocusStop())
        .focused($isFocused)
        .overlay(alignment: .leading) {
            if isFocused {
                // Full-strength header ink even on an empty (dimmed) project,
                // so the mark clears 3:1 on the light and dark sidebar alike.
                Rectangle()
                    .fill(SidebarColors.secondaryText(colorScheme))
                    .frame(width: 2)
                    .allowsHitTesting(false)
            }
        }
        .modifier(ToggleKeyActivation(action: onToggle))
        .accessibilityElement(children: .ignore)
        .accessibilityAction(.default, onToggle)
        .accessibilityLabel("\(name), \(count) \(count == 1 ? "session" : "sessions")" + (needYouCount > 0 ? ", \(needYouCount) need you" : ""))
        .accessibilityValue(isEmpty ? "" : (isCollapsed ? "collapsed" : "expanded"))
        .accessibilityAddTraits([.isHeader, .isButton])
        .accessibilityHint(Self.accessibilityHint(isEmpty: isEmpty, isCollapsed: isCollapsed))
        // After the header's own accessibility element, so the chip is a
        // separate button to VoiceOver and a separate keyboard stop, hover
        // or not.
        .overlay(alignment: .leading) {
            if let onNewThread, let minX = clusterEdges[.countLeading], let maxX = clusterEdges[.count] {
                ProjectHeaderNewThreadButton(
                    label: Self.newThreadLabel(project: name),
                    isVisible: showsNewThread,
                    forcePointed: forceChipPointed,
                    isFocused: $isNewThreadFocused,
                    action: onNewThread
                )
                // `clusterEdges` are measured inside the leading padding.
                .offset(x: SidebarDialTuning.rowLeadingPadding()
                    + Self.newThreadChipMinX(labelMinX: minX, labelMaxX: maxX, needYouCount: needYouCount))
                // The rail's header is its tile alone.
                .allowsHitTesting(progress <= 0 && !widthModel.isMorphing)
                .accessibilityHidden(progress > 0)
            }
        }
        .onHover { isHovered = $0 }
    }

    /// How far `part`'s trailing edge sits inside the count's (0 for the
    /// count, and until both are measured).
    private func clusterSlack(_ part: ClusterPart) -> CGFloat {
        guard let count = clusterEdges[.count], let edge = clusterEdges[part] else { return 0 }
        return count - edge
    }

    enum ClusterPart: Hashable { case chevron, count, countLeading }

    /// Reports a cluster part's resting trailing edge (and, under
    /// `leadingPart`, its leading edge). Attached outside the part's ride,
    /// so it reads the laid-out frame, not the drawn one.
    private struct ClusterEdgeReporter: View {
        static let space = "ProjectAccordionHeader.cluster"
        let part: ClusterPart
        var leadingPart: ClusterPart?

        var body: some View {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named(Self.space))
                Color.clear.preference(
                    key: ClusterEdgesKey.self,
                    value: leadingPart.map { [part: frame.maxX, $0: frame.minX] } ?? [part: frame.maxX]
                )
            }
        }
    }

    private struct ClusterEdgesKey: PreferenceKey {
        static let defaultValue: [ClusterPart: CGFloat] = [:]
        static func reduce(value: inout [ClusterPart: CGFloat], nextValue: () -> [ClusterPart: CGFloat]) {
            value.merge(nextValue()) { $1 }
        }
    }

    /// What a click does: an empty project selects, any other folds or
    /// unfolds.
    static func accessibilityHint(isEmpty: Bool, isCollapsed: Bool) -> String {
        isEmpty ? "Selects this project" : (isCollapsed ? "Shows this project's sessions" : "Hides this project's sessions")
    }
}

// MARK: - Quick create

/// A project header's "+" chip (one view): a click opens the composer with
/// the project filled in, Option-click creates a thread at once
/// (`ProjectRowNewSession.perform`). A rounded square on the row's hover
/// tint, stronger under the pointer
/// (`ProjectAccordionHeader.newThreadChipFill`); the square is the click
/// target. Drawn only while `isVisible`, but always a keyboard stop and a
/// VoiceOver button, so neither needs the pointer; focus draws it too. It
/// fades on the hover spring; Reduce Motion: it snaps.
///
/// A tap gesture and a focus stop, like the header under it, not a
/// `Button`: the same keyboard behaviour as the header (Space / Return).
private struct ProjectHeaderNewThreadButton: View {
    let label: String
    let isVisible: Bool
    /// DEBUG capture hook: draws the fill it has under the pointer.
    var forcePointed = false
    var isFocused: FocusState<Bool>.Binding
    let action: () -> Void

    @ChromeScheme private var colorScheme
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RailProjectColumn.chipCornerRadius, style: .continuous)
        Image(systemName: "plus")
            .font(.system(size: ProjectAccordionHeader.newThreadGlyphSize, weight: .semibold))
            .foregroundStyle(SidebarColors.secondaryText(colorScheme))
            .frame(width: ProjectAccordionHeader.newThreadChipSize, height: ProjectAccordionHeader.newThreadChipSize)
            .background(shape.fill(ProjectAccordionHeader.newThreadChipFill(isPointed: isHovered || forcePointed, colorScheme)))
            .overlay {
                if isFocused.wrappedValue {
                    // The header's focus mark ink, as a ring.
                    shape.strokeBorder(SidebarColors.secondaryText(colorScheme), lineWidth: 2)
                }
            }
            .contentShape(shape)
            .onTapGesture(perform: action)
            .onHover { isHovered = $0 }
            .opacity(isVisible ? 1 : 0)
            .animation(SidebarUISpring.hover.settle(), value: isVisible)
            .animation(SidebarUISpring.hover.settle(), value: isHovered)
            .help(label)
            .modifier(HeaderFocusStop())
            .focused(isFocused)
            .modifier(ToggleKeyActivation(action: action))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, action)
    }
}

// MARK: - Tile

/// The surface a project tile and its rows' thread tiles (chips) sit in.
/// Each has its own "Tiles" dials, so the two are tuned independently.
enum SidebarTileContext {
    /// The expanded sidebar: the group header's tile and its rows.
    case sidebar
    /// The collapsed rail: the column's tile and its rows.
    case rail
}

/// A project's monogram tile, as drawn (option D: r8, 10% tint; solid ink
/// when it heads the selected project): a `size` square whose shape is
/// scaled by `shapeScale` (`MorphTileScale`) while the monogram stays at
/// `textSize`, unscaled.
struct ProjectMonogramTileFace: View {
    /// A selected project's ring on an icon tile, in points as drawn.
    static let selectedRingWidth: CGFloat = 2

    let monogram: String
    let size: CGFloat
    let textSize: CGFloat
    var shapeScale: CGFloat = 1
    var isEmpty: Bool = false
    var isSelectedProject: Bool = false
    /// DEBUG Redlines tag for the drawn (scaled) shape.
    var redlineID: String? = nil
    /// The project's icon, filling the tile's shape in place of the
    /// monogram. Same frame, same shape: only the face changes.
    var icon: NSImage? = nil

    /// Re-renders on every dial write; the fill reads "Selected tile fill".
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
    @ChromeScheme private var colorScheme
    /// The header's group: its ink follows the group's card (`SelectedRowMix`).
    @Environment(\.selectedRowMixGroup) private var mixGroup

    // Option D (`hRCBC`: `#28221E1A`), per appearance.
    private var tint: Color { SidebarColors.tileFill(colorScheme, isEmpty: isEmpty) }
    var body: some View {
        SelectedRowMixGroupReader(id: mixGroup, fallback: isSelectedProject ? 1 : 0) { card in
            face(inkFill: card * RailProjectColumn.selectedTileFill)
        }
    }

    /// `inkFill`: ink laid over the tile tint, 0 unselected, the dial when
    /// selected. Past the midpoint the tile reads as ink, so its text flips
    /// to the chrome colour to stay legible.
    private func face(inkFill: Double) -> some View {
        let isFilled = inkFill > 0.5
        let shape = RoundedRectangle(cornerRadius: RailProjectTile.cornerRadius / max(shapeScale, 0.01), style: .continuous)
        // Tint fades out as ink fades in, so each end draws exactly one
        // fill: the plain tile at 0, solid ink at 1.
        let ink = RailProjectTile.ink(colorScheme)
        return shape.fill(tint.opacity(1 - inkFill)).overlay(shape.fill(ink.opacity(inkFill)))
            .overlay {
                if let icon {
                    // The icon covers the ink fill, so selection reads as an
                    // ink ring on the tile's edge instead, on the same mix
                    // (`inkFill`) the fill follows. Width is divided by the
                    // shape's scale so it draws 2pt at every morph step.
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(shape)
                        .opacity(isEmpty ? 0.5 : 1)
                        .overlay(shape.strokeBorder(ink.opacity(inkFill), lineWidth: Self.selectedRingWidth / max(shapeScale, 0.01)))
                }
            }
            .frame(width: size, height: size)
            // Inside the scale, so Redlines reports the drawn tile.
            .redlineFrame(redlineID)
            .scaleEffect(shapeScale)
            .overlay {
                if icon == nil {
                    Text(monogram)
                        .font(.system(size: textSize, weight: .bold))
                        .foregroundStyle(isEmpty ? SidebarColors.dimmedProject(colorScheme) : (isFilled ? RailProjectTile.badgeText(colorScheme) : RailProjectTile.ink(colorScheme)))
                }
            }
            .frame(width: size, height: size)
    }
}

/// The header's tile at one step of the morph: one rail-sized square in
/// both states, its shape scaled from the sidebar's size at 0 to the
/// rail's at 1 (`MorphTileScale`), the monogram at its own size, and, on
/// the rail, a folded project's session count on the drawn shape's corner.
struct MorphTileFace: View, Animatable {
    var progress: CGFloat
    let sizes: (from: CGFloat, to: CGFloat)
    let textSizes: (from: CGFloat, to: CGFloat)
    let monogram: String
    let isEmpty: Bool
    let isSelectedProject: Bool
    let redlineID: String?
    /// The folded project's session count; nil while it is unfolded.
    let badgeCount: Int?
    /// The project's icon; nil draws the monogram.
    var icon: NSImage? = nil

    @ChromeScheme private var colorScheme

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let container = sizes.to
        let scale = MorphTileScale.scale(from: sizes.from, to: sizes.to, progress: progress)
        // How far the drawn shape's corner sits inside the container's.
        let cornerInset = container * (1 - scale) / 2
        ProjectMonogramTileFace(
            monogram: monogram,
            size: container,
            textSize: SidebarMorphMetrics.lerp(textSizes.from, textSizes.to, progress),
            shapeScale: scale,
            isEmpty: isEmpty,
            isSelectedProject: isSelectedProject,
            redlineID: redlineID,
            icon: icon
        )
        .morphIdentityProbe(redlineID)
        .overlay(alignment: .topTrailing) {
            if let badgeCount {
                let style = RailCountBadge.style(selected: isSelectedProject, colorScheme: colorScheme)
                Text("\(badgeCount)")
                    .font(.system(size: 9.5, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(style.text)
                    .padding(.horizontal, 3)
                    .frame(minWidth: 15, minHeight: 15)
                    .background(Capsule().fill(style.fill))
                    .modifier(MorphRailOnlyFade())
                    .offset(x: 5 - cornerInset, y: -5 + cornerInset)
                    // Folding is a close, but the badge arriving with it
                    // is an entrance: it pops in on the fold spring's
                    // bounce, and leaves on an unfold without one.
                    .transition(.asymmetric(
                        insertion: AnyTransition.scale(scale: RailCountBadge.popFromScale)
                            .combined(with: .opacity)
                            .animation(SidebarUISpring.fold.animation()),
                        removal: AnyTransition.opacity.animation(SidebarUISpring.fold.settle())
                    ))
            }
        }
    }
}

/// A folded project's session count on its rail tile (keyframe spec D2,
/// "quiet tint"): an opaque faint capsule, the number in secondary text, no
/// ring, the same on a selected (ink) tile as on a plain one, where it
/// still separates from the ink.
enum RailCountBadge {
    /// The scale the badge pops in from when its project folds.
    static let popFromScale: CGFloat = 0.6

    struct Style {
        var fill: Color
        var text: Color
    }

    static func style(selected _: Bool, colorScheme: ColorScheme) -> Style {
        let theme = ChromeTheme.active(colorScheme)
        let dark = colorScheme == .dark
        // Ink at 12% (dark) / 14% (light) over the base, every theme.
        let alpha = dark ? 0.12 : 0.14
        let base: UInt32
        if ChromeTheme.activeIsGhostties(colorScheme) {
            // The Ghostties pair's greys: #3D3C3C dark, #D3CDCA light.
            base = dark ? 0x3D3C3C : 0xD3CDCA
        } else {
            // A theme the chrome derived: the same wash over its own chrome.
            let chrome = theme.chrome.usingColorSpace(.sRGB) ?? theme.chrome
            func byte(_ v: CGFloat, _ shift: UInt32) -> UInt32 { UInt32((v * 255).rounded()) << shift }
            base = byte(chrome.redComponent, 16) | byte(chrome.greenComponent, 8) | byte(chrome.blueComponent, 0)
        }
        return Style(fill: blend(ink: theme.ink, over: base, alpha: alpha), text: theme.inkSecondaryColor)
    }

    /// `ink` at `alpha` over `base`, flattened to one opaque colour.
    private static func blend(ink: NSColor, over base: UInt32, alpha: Double) -> Color {
        let inkRGB = ink.usingColorSpace(.sRGB) ?? ink
        func channel(_ ink: CGFloat, _ shift: UInt32) -> Double {
            let b = Double((base >> shift) & 0xFF)
            return (Double(ink) * 255 * alpha + b * (1 - alpha)) / 255
        }
        return Color(.sRGB, red: channel(inkRGB.redComponent, 16), green: channel(inkRGB.greenComponent, 8),
                     blue: channel(inkRGB.blueComponent, 0), opacity: 1)
    }
}

/// A project tile's dials and look, shared by the expanded header and the
/// rail (the tile itself is `ProjectAccordionHeader`'s, in both).
enum RailProjectTile {
    /// The sidebar's tile, unset (Sean, 2026-10-10: the 8pt grid).
    static let defaultSize: CGFloat = 32
    /// The rail's tile, unset (Sean, 2026-10-10: the rail's tiles grow a third
    /// as the sidebar shrinks to it, on the 8pt grid).
    static let defaultRailSize: CGFloat = 40
    /// The tile's side in `context`: that context's "Project tile size" dial.
    static func size(_ context: SidebarTileContext) -> CGFloat {
        switch context {
        case .sidebar: max(SidebarDialTuning.sidebarProjectTileSize(), 0)
        case .rail: max(SidebarDialTuning.railProjectTileSize(), 0)
        }
    }
    /// A one-letter monogram's font size: what the sidebar's "Project tile
    /// text" dial reads unset.
    static let defaultTextSize: CGFloat = 13
    /// The rail's monogram, unset: the sidebar's size, so the rail's larger
    /// tile holds the same text (Sean, 2026-10-10).
    static let defaultRailTextSize: CGFloat = 13
    /// The monogram's font size in `context` ("Project tile text"); a
    /// two-letter monogram draws 2pt smaller (13 / 11 in the sidebar and on
    /// the rail, at the defaults).
    static func textSize(_ context: SidebarTileContext, letters: Int) -> CGFloat {
        let text = switch context {
        case .sidebar: SidebarDialTuning.sidebarProjectTileText()
        case .rail: SidebarDialTuning.railProjectTileText()
        }
        return max(text - (letters > 1 ? 2 : 0), 1)
    }
    /// Option D: 8 (was 9).
    static let cornerRadius: CGFloat = 8
    /// The tile's tint in light (option D `#28221E1A`; was 7.5%).
    static let tintOpacity: Double = 0.10
    /// An empty project's tile tint in light (beta.26): lighter than a live
    /// tile's, so its `textSecondary` letter clears 4.5:1 (4.61 on chrome).
    static let emptyTintOpacity: Double = 0.085

    static func ink(_ colorScheme: ColorScheme) -> Color {
        Color(ChromeTheme.active(colorScheme).ink)
    }
    static func badgeText(_ colorScheme: ColorScheme) -> Color {
        Color(nsColor: SidebarColors.background(colorScheme))
    }
}

// MARK: - Auto-expand

/// Unfolds a project when a session is created in it, or focused from a
/// shortcut, in this view's window — so the session it lands on is a
/// visible row, not hidden under a folded header.
struct ProjectAccordionAutoExpand: ViewModifier {
    let window: () -> NSWindow?
    @AppStorage(ProjectAccordionState.collapsedKey, store: SidebarDialTuning.store) private var collapsedRaw = ""

    func body(content: Content) -> some View {
        content
            // A new tab into a folded project unfolds only that project, on
            // the selected-row mix's size curve (N4).
            .onReceive(NotificationCenter.default.publisher(for: .workspaceDidCreateSessionInProject)) {
                expand($0, animation: SelectedRowMix.unfoldAnimation())
            }
            .onReceive(NotificationCenter.default.publisher(for: .workspaceDidFocusSessionFromShortcut)) { expand($0) }
            #if DEBUG
            .onReceive(NotificationCenter.default.publisher(for: .captureProjectFold)) { captureFold($0) }
            #endif
    }

    #if DEBUG
    /// The capture script's fold ops in One view: written through the same
    /// `@AppStorage` string and spring as a header click
    /// (`ProjectAccordionState.headerClicked`). The tabs layout is handled by
    /// `WorkspaceSidebarView`.
    private func captureFold(_ notification: Notification) {
        guard SidebarDialTuning.projectsLayout() == .oneView,
              notification.object as? NSWindow === window(),
              let ids = notification.userInfo?["projectIds"] as? [UUID],
              let fold = notification.userInfo?["fold"] as? Bool else { return }
        withAnimation(ProjectAccordionState.toggleAnimation(unfolding: !fold)) {
            collapsedRaw = ProjectAccordionState.setFolded(collapsedRaw, ids: ids, folded: fold)
        }
    }
    #endif

    private func expand(_ notification: Notification, animation: Animation? = nil) {
        guard SidebarDialTuning.projectsLayout() == .oneView,
              notification.object as? NSWindow === window(),
              let projectId = notification.userInfo?["projectId"] as? UUID,
              ProjectAccordionState.decode(collapsedRaw).contains(projectId) else { return }
        withAnimation(animation) {
            collapsedRaw = ProjectAccordionState.expanded(collapsedRaw, projectId)
        }
    }
}

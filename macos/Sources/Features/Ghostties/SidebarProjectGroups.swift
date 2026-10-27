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

    /// Mock B5's break between groups: the hairline's 6pt margins and 1pt
    /// line (`.hair`). The rule itself now sits in the header.
    static let spacerHeight: CGFloat = 13

    /// Card 01's only separator between the pinned block and the
    /// alphabetical one (`WorkspaceLayout.projectPinnedBreak`), added to the
    /// usual break. The rail renders the same items, so the gap is the same
    /// height in both widths and no tile moves between them.
    static let pinnedBreakHeight: CGFloat = WorkspaceLayout.projectPinnedBreak

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
        }
    }

    static func items(_ groups: [SidebarProjectGroup], collapsed: Set<UUID>) -> [SidebarProjectGroupItem] {
        items(groups, collapsed: collapsed, pinnedBreakBefore: pinnedBreakGroupId(groups))
    }

    /// `pinnedBreakBefore` is `pinnedBreakGroupId` of the whole list when
    /// `groups` is the rendered one with a dragged group removed.
    static func items(_ groups: [SidebarProjectGroup], collapsed: Set<UUID>, pinnedBreakBefore: String?) -> [SidebarProjectGroupItem] {
        var items: [SidebarProjectGroupItem] = []
        for (index, group) in groups.enumerated() {
            let breakHeight = group.id == pinnedBreakBefore ? pinnedBreakHeight : 0
            let height = (index > 0 ? spacerHeight : 0) + breakHeight
            if height > 0 {
                items.append(.spacer(groupId: group.id, height: height))
            }
            let isCollapsed = !group.isEmpty && (group.projectId.map(collapsed.contains) ?? false)
            items.append(.header(group, isCollapsed: isCollapsed))
            if !isCollapsed {
                items += group.sessions.map { .row($0, group: group) }
            }
        }
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

    /// The one-view row subtitle. A needs-attention row its hook state
    /// contradicts reads what the hook state says instead.
    static func subtitle(indicator: SessionIndicatorState, state: ClaudeState?) -> String {
        guard indicator == .needsAttention, !isGenuine(indicator: indicator, state: state), let state else {
            return indicator.statusGlyphKind.groupedRowSubtitle
        }
        let hookIndicator = SessionCoordinator.claudeIndicator(kind: state.state, isLongRunning: false) ?? .idle
        return hookIndicator.statusGlyphKind.groupedRowSubtitle
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
    let onToggle: () -> Void

    /// The chevron's frame and the count's minimum, at rest; held through
    /// the morph (`SidebarMorphMetrics.trailingClusterWidth`).
    static let chevronWidth: CGFloat = 18
    static let countMinWidth: CGFloat = 18

    @ChromeScheme private var colorScheme
    @EnvironmentObject private var widthModel: SidebarWidthModel
    @Environment(\.sidebarMorphOverride) private var morphOverride
    @Environment(\.sidebarMorphDials) private var morphDials
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
    @FocusState private var isFocused: Bool
    /// The chevron's and count's resting trailing edges in the header's own
    /// space, measured outside their ride (`MorphTrailingClusterRide`).
    @State private var clusterEdges: [ClusterPart: CGFloat] = [:]

    var body: some View {
        let ink = isEmpty ? SidebarColors.dimmedProject(colorScheme) : SidebarColors.secondaryText(colorScheme)
        let progress = morphOverride ?? widthModel.morph
        let metrics = widthModel.metrics(progress, dials: morphDials)
        let dials = metrics.dials
        let slot = dials.sidebarTileSize
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
                Spacer(minLength: 8)
                // Never squeezed by a long name: it keeps its own width.
                Text(SessionNeedsYou.headerCountLabel(sessionCount: count, needYou: needYouCount))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .fixedSize()
                    .frame(
                        minWidth: SidebarMorphMetrics.trailingClusterWidth(resting: Self.countMinWidth, progress: progress),
                        alignment: .trailing
                    )
                    .modifier(MorphLabelFade(element: .trailingCluster, staggerIndex: staggerIndex))
                    .modifier(MorphTrailingClusterRide(metrics: metrics, slack: clusterSlack(.count), progress: progress))
                    .background(ClusterEdgeReporter(part: .count))
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
    }

    /// How far `part`'s trailing edge sits inside the count's (0 for the
    /// count, and until both are measured).
    private func clusterSlack(_ part: ClusterPart) -> CGFloat {
        guard let count = clusterEdges[.count], let edge = clusterEdges[part] else { return 0 }
        return count - edge
    }

    enum ClusterPart: Hashable { case chevron, count }

    /// Reports a cluster part's resting trailing edge. Attached outside the
    /// part's ride, so it reads the laid-out frame, not the drawn one.
    private struct ClusterEdgeReporter: View {
        static let space = "ProjectAccordionHeader.cluster"
        let part: ClusterPart

        var body: some View {
            GeometryReader { proxy in
                Color.clear.preference(key: ClusterEdgesKey.self, value: [part: proxy.frame(in: .named(Self.space)).maxX])
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

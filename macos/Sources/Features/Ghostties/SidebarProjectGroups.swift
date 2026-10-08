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

/// One project's live, unpinned sessions in the one-view list.
struct SidebarProjectGroup: Equatable, Identifiable {
    /// Nil only for sessions whose project no longer exists.
    let projectId: UUID?
    let name: String
    let sessions: [AgentSession]

    var id: String { projectId?.uuidString ?? "unknown-project" }

    /// A project with no live, unpinned session: shown dimmed with a count
    /// of 0 and no rows. It never folds; a click selects it instead.
    var isEmpty: Bool { sessions.isEmpty }

    /// Groups `active` (already in render order) by project, in `projects`
    /// order. Every project gets a group, empty ones included (Sean,
    /// 2026-10-08: show empty projects dimmed with count 0, rather than
    /// mock B5's hidden). Sessions whose project is gone trail in one
    /// "Unknown" group, the name rows already use for them, so no live
    /// session ever drops off the list.
    static func make(active: [AgentSession], projects: [Project]) -> [SidebarProjectGroup] {
        var byProject: [UUID: [AgentSession]] = [:]
        for session in active {
            byProject[session.projectId, default: []].append(session)
        }
        var groups: [SidebarProjectGroup] = projects.map { project in
            SidebarProjectGroup(projectId: project.id, name: project.name, sessions: byProject.removeValue(forKey: project.id) ?? [])
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
    /// Clear space before every group but the first (`spacerHeight`).
    case spacer(groupId: String)
    case header(SidebarProjectGroup, isCollapsed: Bool)
    case row(AgentSession, group: SidebarProjectGroup)

    /// Mock B5's break between groups: the hairline's 6pt margins and 1pt
    /// line (`.hair`). The rule itself now sits in the header.
    static let spacerHeight: CGFloat = 13

    var id: String {
        switch self {
        case .spacer(let groupId): return "spacer-\(groupId)"
        case .header(let group, _): return "header-\(group.id)"
        case .row(let session, _): return session.id.uuidString
        }
    }

    static func items(_ groups: [SidebarProjectGroup], collapsed: Set<UUID>) -> [SidebarProjectGroupItem] {
        var items: [SidebarProjectGroupItem] = []
        for (index, group) in groups.enumerated() {
            if index > 0 { items.append(.spacer(groupId: group.id)) }
            let isCollapsed = !group.isEmpty && (group.projectId.map(collapsed.contains) ?? false)
            items.append(.header(group, isCollapsed: isCollapsed))
            if !isCollapsed {
                items += group.sessions.map { .row($0, group: group) }
            }
        }
        return items
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

    static func expanded(_ raw: String, _ projectId: UUID) -> String {
        var ids = decode(raw)
        ids.remove(projectId)
        return encode(ids)
    }

    static var toggleAnimation: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeInOut(duration: 0.2)
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
        withAnimation(toggleAnimation) {
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

/// A project's accordion header in the one-view list:
/// `NAME ⌄ ———— count`. Clicking it folds or unfolds the project's rows.
/// An empty project's header is dimmed, has no chevron (nothing to fold),
/// and selects the project instead.
struct ProjectAccordionHeader: View {
    static let height: CGFloat = 30

    let name: String
    let count: Int
    let isCollapsed: Bool
    var isEmpty: Bool = false
    let onToggle: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0

    var body: some View {
        let ink = isEmpty ? WorkspaceLayout.emptyProjectForeground : WorkspaceLayout.sectionHeaderForeground(for: colorScheme)
        Button(action: onToggle) {
            HStack(spacing: 0) {
                Text(name.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    .frame(width: 14)
                    .padding(.leading, 4)
                    .opacity(isEmpty ? 0 : 1)
                Rectangle()
                    .fill(WorkspaceLayout.railSectionHairline)
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(ink)
            .padding(.leading, SidebarDialTuning.rowLeadingPadding())
            .padding(.trailing, SidebarDialTuning.rowTrailingPadding())
            .frame(height: Self.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(count) \(count == 1 ? "session" : "sessions")")
        .accessibilityValue(isEmpty ? "" : (isCollapsed ? "collapsed" : "expanded"))
        .accessibilityAddTraits([.isHeader, .isButton])
        .accessibilityHint(Self.accessibilityHint(isEmpty: isEmpty, isCollapsed: isCollapsed))
    }

    /// What a click does, for the header and its rail tile alike: an empty
    /// project selects, any other folds or unfolds.
    static func accessibilityHint(isEmpty: Bool, isCollapsed: Bool) -> String {
        isEmpty ? "Selects this project" : (isCollapsed ? "Shows this project's sessions" : "Hides this project's sessions")
    }
}

// MARK: - Rail tile

/// A project's monogram tile in the one-view rail, at its header's y.
/// Clicking it does what the header does (fold, or select an empty
/// project); a folded tile carries its session count, and an empty
/// project's tile is dimmed like its header.
struct RailProjectTile: View {
    static let size: CGFloat = 30

    let name: String
    let monogram: String
    let count: Int
    let isCollapsed: Bool
    var isEmpty: Bool = false
    /// Set when this project holds the selected session: the rail's
    /// selection style, which `.ring` and `.column` draw on the tile.
    var selection: RailSelectionStyle? = nil
    let onToggle: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var isFilled: Bool { selection == .column }

    // Mock B5 (`.mono` / `.mono .bd`), per appearance.
    private var tint: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color(red: 40 / 255, green: 34 / 255, blue: 30 / 255).opacity(0.075)
    }
    private var ink: Color {
        colorScheme == .dark
            ? Color(red: 0xF0 / 255, green: 0xEF / 255, blue: 0xED / 255)
            : Color(red: 0x23 / 255, green: 0x21 / 255, blue: 0x20 / 255)
    }
    private var badgeText: Color {
        Color(nsColor: colorScheme == .dark ? WorkspaceLayout.chromeBackgroundDark : WorkspaceLayout.chromeBackgroundLight)
    }

    var body: some View {
        Button(action: onToggle) {
            Text(monogram)
                .font(.system(size: monogram.count > 1 ? 11 : 13, weight: .bold))
                .foregroundStyle(isEmpty ? WorkspaceLayout.emptyProjectForeground : (isFilled ? badgeText : ink))
                .frame(width: Self.size, height: Self.size)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(isFilled ? ink : tint))
                .overlay {
                    if selection == .ring {
                        // Strawman A: the selected session's project, ringed
                        // just outside the tile.
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(ink.opacity(0.6), lineWidth: 1.5)
                            .padding(-3)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isCollapsed {
                        Text("\(count)")
                            .font(.system(size: 9.5, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(badgeText)
                            .padding(.horizontal, 3)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(Capsule().fill(ink))
                            .offset(x: 5, y: -5)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: ProjectAccordionHeader.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(count) \(count == 1 ? "session" : "sessions")")
        .accessibilityValue(isEmpty ? "" : (isCollapsed ? "collapsed" : "expanded"))
        .accessibilityAddTraits([.isHeader, .isButton])
        .accessibilityHint(ProjectAccordionHeader.accessibilityHint(isEmpty: isEmpty, isCollapsed: isCollapsed))
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
            .onReceive(NotificationCenter.default.publisher(for: .workspaceDidCreateSessionInProject)) { expand($0) }
            .onReceive(NotificationCenter.default.publisher(for: .workspaceDidFocusSessionFromShortcut)) { expand($0) }
    }

    private func expand(_ notification: Notification) {
        guard SidebarDialTuning.projectsLayout() == .oneView,
              notification.object as? NSWindow === window(),
              let projectId = notification.userInfo?["projectId"] as? UUID,
              ProjectAccordionState.decode(collapsedRaw).contains(projectId) else { return }
        collapsedRaw = ProjectAccordionState.expanded(collapsedRaw, projectId)
    }
}

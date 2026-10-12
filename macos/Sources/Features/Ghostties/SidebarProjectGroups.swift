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
    let isCollapsed: Bool
    var isEmpty: Bool = false
    /// The project holds the selected session: its tile fills with ink.
    var isSelectedProject: Bool = false
    /// DEBUG Redlines tag (`RedlineID.header`).
    var redlineID: String? = nil
    /// The header's place in the expand cascade (`SidebarLabelCascade`).
    var staggerIndex: Int = 0
    let onToggle: () -> Void

    /// The chevron's frame and the count's minimum, at rest; held through
    /// the morph (`SidebarMorphMetrics.trailingClusterWidth`).
    static let chevronWidth: CGFloat = 18
    static let countMinWidth: CGFloat = 18

    @Environment(\.colorScheme) private var colorScheme
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
                        badgeCount: isCollapsed ? count : nil
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
                Text("\(count)")
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
        .accessibilityLabel("\(name), \(count) \(count == 1 ? "session" : "sessions")")
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
    let monogram: String
    let size: CGFloat
    let textSize: CGFloat
    var shapeScale: CGFloat = 1
    var isEmpty: Bool = false
    var isSelectedProject: Bool = false
    /// DEBUG Redlines tag for the drawn (scaled) shape.
    var redlineID: String? = nil

    /// Re-renders on every dial write; the fill reads "Selected tile fill".
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
    @Environment(\.colorScheme) private var colorScheme

    /// Ink laid over the tile tint: 0 unselected, the dial when selected.
    private var inkFill: Double { isSelectedProject ? RailProjectColumn.selectedTileFill : 0 }
    /// Past the midpoint the tile reads as ink, so its text flips to the
    /// chrome colour to stay legible.
    private var isFilled: Bool { inkFill > 0.5 }

    // Option D (`hRCBC`: `#28221E1A`), per appearance.
    private var tint: Color { SidebarColors.tileFill(colorScheme) }
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RailProjectTile.cornerRadius / max(shapeScale, 0.01), style: .continuous)
        // Tint fades out as ink fades in, so each end draws exactly one
        // fill: the plain tile at 0, solid ink at 1.
        shape.fill(tint.opacity(1 - inkFill)).overlay(shape.fill(RailProjectTile.ink(colorScheme).opacity(inkFill)))
            .frame(width: size, height: size)
            // Inside the scale, so Redlines reports the drawn tile.
            .redlineFrame(redlineID)
            .scaleEffect(shapeScale)
            .overlay {
                Text(monogram)
                    .font(.system(size: textSize, weight: .bold))
                    .foregroundStyle(isEmpty ? SidebarColors.dimmedProject(colorScheme) : (isFilled ? RailProjectTile.badgeText(colorScheme) : RailProjectTile.ink(colorScheme)))
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

    @Environment(\.colorScheme) private var colorScheme

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
            redlineID: redlineID
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
        colorScheme == .dark
            // Ink 12% over #3D3C3C.
            ? Style(fill: blend(ink: 0xF0EFED, over: 0x3D3C3C, alpha: 0.12), text: WorkspaceLayout.textSecondaryDark)
            // Ink 14% over #D3CDCA.
            : Style(fill: blend(ink: 0x232120, over: 0xD3CDCA, alpha: 0.14), text: WorkspaceLayout.textSecondaryLight)
    }

    /// `ink` at `alpha` over `base`, flattened to one opaque colour.
    private static func blend(ink: UInt32, over base: UInt32, alpha: Double) -> Color {
        func channel(_ shift: UInt32) -> Double {
            let i = Double((ink >> shift) & 0xFF), b = Double((base >> shift) & 0xFF)
            return (i * alpha + b * (1 - alpha)) / 255
        }
        return Color(.sRGB, red: channel(16), green: channel(8), blue: channel(0), opacity: 1)
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

    static func ink(_ colorScheme: ColorScheme) -> Color {
        SidebarColors.tileInk(colorScheme)
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

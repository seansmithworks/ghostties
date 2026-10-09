import SwiftUI
import GhosttiesCore

// MARK: - Section Model (mock I3)

/// What the Sessions sidebar renders (mock I3): Pinned, Active, then one
/// History row standing in for every inactive and archived session. The
/// inactive/archive buckets still exist in the model
/// (`SessionBucket.membership`, `SessionSection`); they are only shown
/// through History now, never as sidebar rows.
///
/// Membership comes from `RecentsListView`'s static bucket functions — the
/// one rule shared with project view — never re-derived here.
struct SidebarSessionSections: Equatable {
    let pinned: [AgentSession]
    let active: [AgentSession]
    /// Ran this launch, then stopped. Shown only through History.
    let inactive: [AgentSession]
    /// Restored from disk, never started this launch. Shown only through History.
    let archived: [AgentSession]

    /// A rendered sidebar section, in order. Pinned is omitted when empty;
    /// Active and History always render.
    enum Rendered: Equatable {
        case pinned(count: Int)
        case active(count: Int)
        case history(count: Int)
    }

    static func make(
        sessions: [AgentSession],
        statuses: [UUID: SessionStatus],
        sessionIdsStartedThisLaunch: Set<UUID>,
        pinningAvailable: Bool = SessionPinning.isAvailable
    ) -> SidebarSessionSections {
        SidebarSessionSections(
            pinned: RecentsListView.pinnedSessions(from: sessions, pinningAvailable: pinningAvailable),
            active: RecentsListView.activeSessions(from: sessions, statuses: statuses, pinningAvailable: pinningAvailable),
            inactive: RecentsListView.inactiveSessions(
                from: sessions,
                statuses: statuses,
                sessionIdsStartedThisLaunch: sessionIdsStartedThisLaunch,
                pinningAvailable: pinningAvailable
            ),
            archived: RecentsListView.archiveSessions(
                from: sessions,
                statuses: statuses,
                sessionIdsStartedThisLaunch: sessionIdsStartedThisLaunch,
                pinningAvailable: pinningAvailable
            )
        )
    }

    var rendered: [Rendered] {
        var sections: [Rendered] = []
        if !pinned.isEmpty { sections.append(.pinned(count: pinned.count)) }
        sections.append(.active(count: active.count))
        sections.append(.history(count: historyCount))
        return sections
    }

    /// Sessions that render as rows — Pinned then Active. Inactive and
    /// archived sessions never do.
    var rowSessions: [AgentSession] { pinned + active }

    /// Every past session, newest first.
    var history: [AgentSession] { AgentSession.sortedNewestFirst(inactive + archived) }

    var historyCount: Int { inactive.count + archived.count }

    /// The most recent activity across the history set, if any session has
    /// a timestamp.
    var historyLastActiveAt: Date? {
        (inactive + archived).compactMap(\.displayTimestamp).max()
    }
}

// MARK: - History Placement

extension SidebarSessionSections {
    /// One element of the sidebar's section list. The expanded list and the
    /// rail both render exactly these, in this order, so every row keeps
    /// the same y through the pinned⇄rail morph.
    enum Slot: Hashable {
        case pinnedRows, pinnedEnd, activeRows, activeEnd, history
    }

    /// `list` scrolls; `footer` is pinned below it, just above the tray. The
    /// History row (when shown) is always the footer: anchored at the bottom
    /// of the session list, outside the scrolling area.
    struct Layout: Equatable {
        let list: [Slot]
        let footer: [Slot]
    }

    /// `showsHistory` is the "History in sidebar" dial
    /// (`SidebarDialTuning.historyInSidebar`): off, History and its hairline
    /// leave both views and Pinned/Active lay out exactly as before.
    func layout(showsHistory: Bool) -> Layout {
        var list: [Slot] = []
        if !pinned.isEmpty { list += [.pinnedRows, .pinnedEnd] }
        list += [.activeRows, .activeEnd]
        guard showsHistory else { return Layout(list: list, footer: []) }
        return Layout(list: list, footer: [.history])
    }

    /// The gap from the History row to the tray's top edge, in
    /// the expanded list and the rail alike: one row gap, as between rows,
    /// plus the list-to-tray gap.
    static func historyToTrayGap() -> CGFloat {
        SidebarDialTuning.rowGap() + SidebarDialTuning.listToTrayGap()
    }
}

// MARK: - History Row Subtitle

enum HistorySummary {
    /// "148 sessions · last 2d ago"; "No past sessions" when empty; just the
    /// count when no session has a timestamp.
    static func subtitle(count: Int, lastActiveAt: Date?, now: Date = .now) -> String {
        guard count > 0 else { return "No past sessions" }
        let countText = count == 1 ? "1 session" : "\(count) sessions"
        guard let lastActiveAt else { return countText }
        return "\(countText) · last \(ago(lastActiveAt, now: now)) ago"
    }

    /// Compact elapsed time: m, h, d, w, then y — never below 1m.
    static func ago(_ date: Date, now: Date = .now) -> String {
        let minutes = max(1, Int(now.timeIntervalSince(date) / 60))
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 7 { return "\(days)d" }
        let weeks = days / 7
        if days < 365 { return "\(weeks)w" }
        return "\(days / 365)y"
    }
}

// MARK: - History Entries

extension HistoryEntry {
    /// The history browser's rows: every inactive and archived session,
    /// newest first.
    static func entries(from sections: SidebarSessionSections, projects: [Project]) -> [HistoryEntry] {
        let archivedIds = Set(sections.archived.map(\.id))
        return sections.history.map { session in
            HistoryEntry(
                id: session.id,
                projectName: projects.first { $0.id == session.projectId }?.name ?? "Unknown",
                title: session.name,
                lastActiveAt: session.displayTimestamp ?? .distantPast,
                isArchived: archivedIds.contains(session.id),
                isPinned: session.isPinnedForDisplay()
            )
        }
    }
}

// MARK: - History Glyph

/// The clock in the History row's trailing status-glyph slot — the same
/// size, weight and colour as `SessionStatusGlyph`'s text glyphs.
struct HistoryGlyph: View {
    var size: CGFloat = WorkspaceLayout.sessionGhostSize

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: "clock.arrow.circlepath")
            .font(.system(size: size * 0.8, weight: .medium))
            .foregroundStyle(colorScheme == .dark ? WorkspaceLayout.textSecondaryDark : WorkspaceLayout.textSecondaryLight)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - History Row (expanded)

/// The History row after the Active rows (mock I3): the session row's own
/// chrome (`SidebarListRowChrome`) with title "History", the history
/// summary as subtitle, and a clock in the status-glyph slot.
struct HistoryRowView: View {
    let subtitle: String
    let isActive: Bool
    var staggerIndex: Int = 0
    /// `SidebarDialTuning.epoch()`, as on `RecentsRowView`: a changed input
    /// so a live dial edit re-renders this row like the session rows.
    var dialEpoch: Int = 0
    let onTap: () -> Void

    static let redlineID = "row.history"

    var body: some View {
        SidebarListRowChrome(
            subtitle: subtitle,
            isActive: isActive,
            staggerIndex: staggerIndex,
            redlineID: Self.redlineID
        ) {
            SidebarListRowTitle(text: "History", isActive: isActive)
        } glyph: {
            HistoryGlyph(size: SidebarDialTuning.rowGhostSize())
                .frame(width: SidebarDialTuning.rowGhostSize(), height: SidebarDialTuning.rowGhostSize())
        }
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("History, \(subtitle)")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : [.isButton])
    }
}

// MARK: - History Row (rail)

/// The rail's History row: the clock centred in the same 48pt row and
/// selected surface as `RailSessionRow`.
struct RailHistoryRow: View {
    /// Re-renders on every dial write; see `SidebarDialTuning.epochKey`.
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
    let subtitle: String
    let isActive: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HistoryGlyph(size: glyphSize)
                .frame(width: glyphSize, height: glyphSize)
                .frame(maxWidth: .infinity)
                .frame(height: SidebarDialTuning.rowHeight())
                .background(rowBackground)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("History — \(subtitle)")
        .accessibilityLabel("History, \(subtitle)")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    /// Same sizing rule as `RailSessionRow.glyphSize`.
    private var glyphSize: CGFloat {
        isActive ? TrayGlassStyle.selectedGlyphSize : SidebarDialTuning.rowGhostSize()
    }

    private var rowBackground: some View {
        SidebarRowCardBackground(isActive: isActive, isHovered: isHovered)
    }
}

/// Stands in for the expanded list's zero-height end-of-section drop
/// zone, so the rail keeps the same row-gap rhythm.
struct RailSectionEndMarker: View {
    var body: some View {
        Color.clear
            .frame(height: 0)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

// MARK: - Canvas Host

/// The history browser's actions, wired to the existing flows: resume →
/// `SessionCoordinator.resumeFromHistory` (the relaunch flow), pin → the
/// sidebar's pin action, close → back to the prior selection.
struct HistoryActions {
    let resume: (UUID) -> Void
    let togglePin: (UUID) -> Void
    let close: () -> Void

    @MainActor
    static func make(
        store: WorkspaceStore,
        coordinator: SessionCoordinator,
        relaunch: ((AgentSession, SessionCoordinator.RelaunchMode) -> Void)? = nil
    ) -> HistoryActions {
        HistoryActions(
            resume: { [weak store, weak coordinator] id in
                guard let store, let coordinator else { return }
                coordinator.resumeFromHistory(id: id, in: store, relaunch: relaunch)
            },
            togglePin: { [weak store] id in store?.toggleSessionPin(id: id) },
            close: { [weak coordinator] in coordinator?.dismissHistory() }
        )
    }
}

/// Hosted in the canvas card by `WorkspaceViewContainer` while
/// `SessionCoordinator.isHistoryPresented`. Builds the entries live from the
/// store so the list tracks sessions starting, stopping and pinning.
struct HistoryCanvasHost: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var coordinator: SessionCoordinator
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let sections = SidebarSessionSections.make(
            sessions: store.sessions,
            statuses: store.globalStatuses,
            sessionIdsStartedThisLaunch: coordinator.sessionIdsStartedThisLaunch
        )
        let actions = HistoryActions.make(store: store, coordinator: coordinator)
        HistoryBrowserView(
            entries: HistoryEntry.entries(from: sections, projects: store.projects),
            onResume: actions.resume,
            onTogglePin: actions.togglePin,
            onClose: actions.close
        )
        // The canvas card's own fill, opaque over the terminal underneath.
        .background(Color(nsColor: colorScheme == .dark ? WorkspaceLayout.canvasBackgroundDark : WorkspaceLayout.canvasBackgroundLight))
    }
}

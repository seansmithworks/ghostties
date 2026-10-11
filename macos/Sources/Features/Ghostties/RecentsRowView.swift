import SwiftUI

/// A single row in the Sessions recents list.
///
/// Displays a status dot (colored by `SessionIndicatorState`), the session name,
/// the owning project name in muted text, and a right-aligned relative timestamp.
/// Tapping focuses the session in the terminal area.
///
/// `Equatable` (manual, not synthesized — several stored properties are
/// closures/bindings and can't derive `==`) so the caller can apply
/// `.equatable()` and skip re-executing `body` when none of this row's own
/// inputs changed. This is the same pattern as `ProjectDisclosureRowContent`
/// (PR #40) and is a body-re-execution **perf gate**, not what makes a row
/// pick up new values — `RecentsListView` keys its `ForEach` on the stable
/// `\.id` (required so hover state and an in-progress inline rename survive
/// `WorkspaceStore` writes that don't touch this row, e.g. another session's
/// `lastActiveAt`), and freshness on that stable identity comes from the
/// caller using a non-lazy `VStack` rather than `LazyVStack` — a lazy
/// container retains a realized row and never re-invokes the `ForEach`
/// content closure when only the element changes, so `.equatable()` alone
/// cannot fix a frozen row (there is no new value to compare against).
/// See the `VStack` comment in `RecentsListView.body`.
struct RecentsRowView: View, Equatable {
    let session: AgentSession
    let projectName: String
    let indicatorState: SessionIndicatorState
    /// True while this session's Codex hook has never reported and the grace
    /// period has elapsed — see `SessionCoordinator.codexHookUnconfirmed(for:)`.
    /// Replaces the project-name subtitle with an explanatory hint; false is
    /// the default so every other call site is unaffected.
    var hookUnconfirmed: Bool = false
    /// Replaces the project-name subtitle — the one-view list, where the
    /// project is the header above the row (`SidebarProjectsLayout.oneView`).
    /// Nil keeps the project name.
    var subtitle: String? = nil
    let isActive: Bool
    var isEditing: Bool = false
    @Binding var editingName: String
    var isRenameFocused: FocusState<Bool>.Binding
    let onTap: () -> Void
    var onCommitRename: () -> Void = {}
    var onCancelRename: () -> Void = {}

    /// This row's position within its rendered section (Pinned/Active/
    /// Inactive) — decorative only, feeds the Flow 05 expand stagger
    /// (`WorkspaceLayout.expandLabelDelay`). Defaults to 0 so every other
    /// call site (unaffected by the stagger) is unchanged.
    var staggerIndex: Int = 0

    /// `SidebarDialTuning.epoch()` at construction — DEBUG-tuning-only.
    /// `.equatable()` is a body-re-execution perf gate (see the type doc
    /// comment above): none of this row's OTHER stored properties change
    /// when the sidebar DialKit panel writes a new row height/title size/
    /// ghost size/etc., so without this field a live tuning edit would be
    /// silently swallowed by the same `==` this row relies on for its perf
    /// win, until some unrelated row mutation happened to force a redraw.
    /// Defaults to 0 so every call site that never reads the panel (i.e.
    /// every Release build, where the key is never written) is unaffected.
    var dialEpoch: Int = 0

    @EnvironmentObject private var coordinator: SessionCoordinator

    /// Every field that affects rendered output. Deliberately excludes
    /// `editingName`/`isRenameFocused`/the closures — those are live
    /// bindings the `TextField` reads directly, not values `body` needs to
    /// re-run for.
    static func == (lhs: RecentsRowView, rhs: RecentsRowView) -> Bool {
        lhs.session == rhs.session
            && lhs.projectName == rhs.projectName
            && lhs.indicatorState == rhs.indicatorState
            && lhs.hookUnconfirmed == rhs.hookUnconfirmed
            && lhs.subtitle == rhs.subtitle
            && lhs.isActive == rhs.isActive
            && lhs.isEditing == rhs.isEditing
            && lhs.staggerIndex == rhs.staggerIndex
            && lhs.dialEpoch == rhs.dialEpoch
    }

    var body: some View {
        // The row's visuals (layout, padding, height, selected surface,
        // hover, and its part in the sidebar ⇄ rail morph) live in
        // `SidebarListRowChrome`, shared with the History row so the two
        // can never drift.
        SidebarListRowChrome(
            subtitle: hookUnconfirmed ? "Approve the Ghostties hook in Codex" : (subtitle ?? projectName),
            isActive: isActive,
            staggerIndex: staggerIndex,
            redlineID: RedlineID.row(session.id),
            popover: (session.id, coordinator.sessionPopover)
        ) {
            if isEditing {
                TextField("Session name", text: $editingName)
                    .font(.system(size: SidebarDialTuning.rowTitleSize()))
                    .textFieldStyle(.plain)
                    .focused(isRenameFocused)
                    .onSubmit { onCommitRename() }
                    .onExitCommand { onCancelRename() }
                    .onChange(of: isRenameFocused.wrappedValue) { focused in
                        // Deferred: Esc can drop focus (firing this) before
                        // SwiftUI's onExitCommand runs cancelRename(). Dispatching
                        // async lets cancelRename() clear editingSessionId first,
                        // so the id guard in commitRename(session:) rejects this
                        // call instead of writing a stale name to the store.
                        if !focused, isEditing {
                            DispatchQueue.main.async { onCommitRename() }
                        }
                    }
            } else {
                SidebarListRowTitle(text: session.name, isActive: isActive)
            }
        } glyph: { size in
            // No timestamp — Flow 07 round 6 drops the relative-time label
            // from the row entirely. `relativeLabel` is kept (it still backs
            // the accessibility label below); only the visible `Text` is gone.

            // Per-session status glyph (spinner / ? / check / x) in the
            // leading slot, under its project's tile (option D, 2026-10-09),
            // at the "Thread tile icon" size of this step of the morph.
            // Selection is the row's chip, not a glyph tint.
            SessionStatusGlyph(kind: indicatorState.statusGlyphKind, size: size)
        }
        .onTapGesture {
            guard !isEditing else { return }
            onTap()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        // Same `SessionStatusGlyphKind.spokenStatus` the visible glyph
        // renders from — this row previously stated no status at all.
        var parts = [session.name, "in \(projectName)", indicatorState.statusGlyphKind.spokenStatus]
        if hookUnconfirmed {
            parts.append("Approve the Ghostties hook in Codex")
        }
        if let ts = session.displayTimestamp {
            // "last output" — not a bare relative token — so a screen reader
            // has a noun for what this measures. Browsing (focus/selection)
            // no longer advances this value; without the noun, "2m" reads as
            // an event the user didn't cause. A11y string only — the visual
            // row keeps the bare relative label. See RecentsRowView.body.
            parts.append("last output \(Self.relativeLabel(ts))")
        }
        if isActive { parts.append("active") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Relative Time

    /// Formats a past date as a compact relative string.
    /// - "just now" for < 1 min
    /// - "2m", "45m" for < 1 hr
    /// - "3h" for < 24 hr
    /// - Day abbreviation ("Mon") for < 7 days
    /// - "May 5" for older
    static func relativeLabel(_ date: Date) -> String {
        let elapsed = Date.now.timeIntervalSince(date)
        if elapsed < 60 { return "just now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m" }
        if elapsed < 86400 { return "\(Int(elapsed / 3600))h" }
        if elapsed < 604800 { return dayFormatter.string(from: date) }
        return monthDayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f
    }()

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f
    }()
}

// MARK: - Shared Row Chrome

/// A sidebar list row's title line: the row title size, and the "Selected
/// title weight" dial on the selected row (macOS 27 sidebar selection:
/// semibold).
struct SidebarListRowTitle: View {
    let text: String
    let isActive: Bool

    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0

    var body: some View {
        Text(text)
            .font(.system(
                size: SidebarDialTuning.rowTitleSize(),
                weight: isActive ? SidebarDialTuning.selectedTitleWeight().fontWeight : .regular
            ))
            .foregroundStyle(Color.primary)
            .lineLimit(1)
    }
}

/// The visual shell of a sidebar list row (option D, 2026-10-09), on the
/// expanded sidebar and the rail alike — one glyph in the leading status
/// slot, the column the one-view tiles sit in, then title over subtitle; the
/// row height and padding dials, the selected chip, hover, and the row's
/// part in the sidebar ⇄ rail morph: the glyph and chip grow and travel to
/// the rail's centre with the tile column (`MorphGlyphSlot`, `MorphTravel`)
/// while the labels fade (`MorphLabelFade`). Shared by session rows
/// (`RecentsRowView`) and the History row (`HistoryRowView`) so both render
/// identically by construction. Callers add tap and accessibility on top.
struct SidebarListRowChrome<Title: View, Glyph: View>: View {
    let subtitle: String
    let isActive: Bool
    /// Position within the rendered section — feeds the expand stagger
    /// (`WorkspaceLayout.expandLabelDelay`).
    var staggerIndex: Int = 0
    let redlineID: String
    /// The session whose hover card this row shows, if any. On the rail
    /// the card names the session, since the row's title is gone.
    var popover: (sessionId: UUID, controller: SessionPopoverController)? = nil
    /// The tooltip the row shows on the rail, where its labels are gone.
    var railHelp: String? = nil
    @ViewBuilder let title: () -> Title
    /// The status glyph at a given side (the morph's size for this frame).
    @ViewBuilder let glyph: (CGFloat) -> Glyph

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var widthModel: SidebarWidthModel
    @Environment(\.sidebarMorphOverride) private var morphOverride
    @State private var isHovered = false
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0

    /// The leading status slot: the monogram tile's width, so a row's
    /// glyph centres under its project's tile.
    static var glyphSlotWidth: CGFloat { RailProjectTile.size(.sidebar) }

    var body: some View {
        let progress = morphOverride ?? widthModel.morph
        let dials = SidebarMorphMetrics.Dials.current()
        let travel = SidebarMorphMetrics(dials: dials, expandedWidth: widthModel.expandedWidth, railWidth: widthModel.railWidth, progress: 0).tileTravel
        HStack(spacing: WorkspaceLayout.sidebarIconLabelSpacing) {
            // Selection and hover are a tile-sized chip behind the glyph in
            // every list (option D): one rule; the group card is drawn only
            // around a project group.
            MorphGlyphSlot(
                progress: progress,
                slotWidth: Self.glyphSlotWidth,
                glyphSizes: (dials.sidebarGlyphSize, dials.railGlyphSize),
                chipSizes: (dials.sidebarChipSize, dials.railChipSize),
                isActive: isActive,
                isHovered: isHovered,
                chipID: redlineID + ".chip",
                glyph: glyph
            )
            .redlineFrame(redlineID + ".glyph")
            .modifier(MorphTravel(distance: travel, progress: progress))

            // Title + subtitle stacked
            VStack(alignment: .leading, spacing: 1) {
                title()

                Text(subtitle)
                    .font(.system(size: SidebarDialTuning.rowSubtitleSize()))
                    .foregroundStyle(colorScheme == .dark ? WorkspaceLayout.textSecondaryDark : WorkspaceLayout.textSecondaryLight)
                    .lineLimit(1)
            }
            .redlineFrame(redlineID + ".label")
            .modifier(MorphLabelFade(staggerIndex: staggerIndex))

            Spacer(minLength: 4)
        }
        .redlineFrame(redlineID + ".content")
        .padding(.leading, SidebarDialTuning.rowLeadingPadding())
        .padding(.trailing, SidebarDialTuning.rowTrailingPadding())
        // 48pt + the enclosing `VStack`'s 4pt row gap = a 52pt pitch.
        .frame(height: SidebarDialTuning.rowHeight())
        .redlineFrame(redlineID)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help(progress >= 0.5 ? (railHelp ?? "") : "")
        .background {
            if let popover {
                Color.clear.sessionPopoverAnchor(sessionId: popover.sessionId, controller: popover.controller, showsName: progress >= 0.5)
            }
        }
        // Mid-morph the row is in flight: no clicks, drags or drops land.
        .allowsHitTesting(!widthModel.isMorphing)
    }
}

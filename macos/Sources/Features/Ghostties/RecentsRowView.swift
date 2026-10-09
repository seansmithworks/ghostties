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
    /// A one-view grouped row (option D): selection is a tile-sized chip
    /// behind the glyph, inside the group card, not the wide row card.
    var inProjectColumn: Bool = false
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
            && lhs.inProjectColumn == rhs.inProjectColumn
            && lhs.isEditing == rhs.isEditing
            && lhs.staggerIndex == rhs.staggerIndex
            && lhs.dialEpoch == rhs.dialEpoch
    }

    var body: some View {
        // The row's visuals (layout, padding, height, selected surface,
        // hover, Flow 05 label choreography) live in `SidebarListRowChrome`,
        // shared with the History row so the two can never drift.
        SidebarListRowChrome(
            subtitle: hookUnconfirmed ? "Approve the Ghostties hook in Codex" : (subtitle ?? projectName),
            isActive: isActive,
            selection: inProjectColumn ? .chip : .card,
            staggerIndex: staggerIndex,
            redlineID: RedlineID.row(session.id)
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
        } glyph: {
            // No timestamp — Flow 07 round 6 drops the relative-time label
            // from the row entirely. `relativeLabel` is kept (it still backs
            // the accessibility label below); only the visible `Text` is gone.

            // Per-session status glyph (spinner / ? / check / x) in the
            // leading slot, under its project's tile (option D, 2026-10-09).
            // Selection is the row's card or chip, not a glyph tint. The
            // collapsed rail (`RailSessionRow`) draws the same glyph centered
            // in the rail, so across the pinned⇄rail transition the glyph
            // moves from this slot to the center (it snaps under Reduce Motion).
            SessionStatusGlyph(kind: indicatorState.statusGlyphKind, size: SidebarDialTuning.rowGhostSize())
                .frame(width: SidebarDialTuning.rowGhostSize(), height: SidebarDialTuning.rowGhostSize())
        }
        .sessionPopoverAnchor(sessionId: session.id, controller: coordinator.sessionPopover)
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

/// How a sidebar list row shows selection and hover.
enum SidebarRowSelection: Equatable {
    /// The wide row card (`SidebarRowCardBackground`): flat lists (the
    /// Sessions tab, Pinned, History).
    case card
    /// A tile-sized chip behind the glyph (`SidebarRowChipBackground`): a
    /// one-view grouped row, inside its project's group card (option D).
    case chip
}

/// The visual shell of a sidebar list row (option D, 2026-10-09) — one glyph
/// in the leading status slot, the column the one-view tiles sit in, then
/// title over subtitle; the row height and padding dials, the selected
/// surface, hover fill, and the Flow 05 label choreography. Shared by
/// session rows (`RecentsRowView`) and the History row (`HistoryRowView`) so
/// both render identically by construction. Callers add tap, popover and
/// accessibility on top.
struct SidebarListRowChrome<Title: View, Glyph: View>: View {
    let subtitle: String
    let isActive: Bool
    var selection: SidebarRowSelection = .card
    /// Position within the rendered section — feeds the Flow 05 expand
    /// stagger (`WorkspaceLayout.expandLabelDelay`).
    var staggerIndex: Int = 0
    let redlineID: String
    @ViewBuilder let title: () -> Title
    @ViewBuilder let glyph: () -> Glyph

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var widthModel: SidebarWidthModel
    @State private var isHovered = false
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0

    /// The leading status slot: the monogram tile's width, so a row's
    /// glyph centres under its project's tile.
    static var glyphSlotWidth: CGFloat { RailProjectTile.size }

    var body: some View {
        HStack(spacing: WorkspaceLayout.sidebarIconLabelSpacing) {
            glyph()
                .frame(width: Self.glyphSlotWidth)
                .background {
                    if selection == .chip {
                        SidebarRowChipBackground(isActive: isActive, isHovered: isHovered)
                    }
                }
                .redlineFrame(redlineID + ".glyph")

            // Title + subtitle stacked
            VStack(alignment: .leading, spacing: 1) {
                title()

                Text(subtitle)
                    .font(.system(size: SidebarDialTuning.rowSubtitleSize()))
                    .foregroundStyle(colorScheme == .dark ? WorkspaceLayout.textSecondaryDark : WorkspaceLayout.textSecondaryLight)
                    .lineLimit(1)
            }
            .opacity(labelOpacity)
            .animation(labelAnimation, value: widthModel.isCollapsedPresentation)

            Spacer(minLength: 4)
        }
        .redlineFrame(redlineID + ".content")
        .padding(.leading, SidebarDialTuning.rowLeadingPadding())
        .padding(.trailing, SidebarDialTuning.rowTrailingPadding())
        // 48pt + the enclosing `VStack`'s 4pt row gap = a 52pt pitch.
        .frame(height: SidebarDialTuning.rowHeight())
        .redlineFrame(redlineID)
        .background {
            if selection == .card {
                rowBackground
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    // MARK: - Flow 05 Content Choreography (sidebar-presence)
    //
    // `widthModel.isCollapsedPresentation` is injected into every sidebar
    // content tree (not just the transitional pinned⇄collapsed cross-fade
    // `WorkspaceViewContainer` mounts mid-transition), so these resolve
    // correctly at rest too: while steady-state pinned it's always `false`,
    // which is exactly this row's normal (label visible, glyph resting,
    // corner radius 8) appearance — nothing below changes existing behavior
    // outside an active transition.

    private var choreographyEnabled: Bool {
        WorkspaceLayout.sidebarRowChoreographyEnabled(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    /// Label (name/subtitle/timestamp) opacity — 1 while expanded, 0 while
    /// collapsed. Reduce Motion skips the windowed fade below and lets only
    /// the container-level cross-fade (120ms, Flow 05 "Reduced Motion") show
    /// the change; the label still ends at the right value, just without
    /// this row's own animation layered on top.
    private var labelOpacity: Double {
        widthModel.isCollapsedPresentation ? 0 : 1
    }

    /// COLLAPSE: labels fade fast (0-100ms of the 260ms window) with no
    /// delay — "labels leave first." EXPAND: labels fade in only after
    /// their glyph has landed, staggered per row — see `expandLabelDelay`.
    private var labelAnimation: Animation? {
        guard choreographyEnabled else { return nil }
        if widthModel.isCollapsedPresentation {
            return .easeOut(duration: WorkspaceLayout.sidebarRowLabelCollapseFadeDuration)
        }
        let delay = WorkspaceLayout.expandLabelDelay(
            rowIndex: staggerIndex,
            glyphLandDuration: WorkspaceLayout.sidebarRowGlyphExpandTravelDuration()
        )
        return .easeOut(duration: WorkspaceLayout.sidebarRowLabelExpandFadeDuration).delay(delay)
    }

    /// Row-background (corner radius) timing. COLLAPSE: waits for the label
    /// to mostly clear (60ms delay), then runs for the rest of the 260ms
    /// window. EXPAND: runs immediately over the whole expand window — every
    /// row starts together; only labels are staggered.
    private var glyphAnimation: Animation? {
        guard choreographyEnabled else { return nil }
        if widthModel.isCollapsedPresentation {
            return .timingCurve(0.32, 0.72, 0, 1, duration: WorkspaceLayout.sidebarRowGlyphCollapseTravelDuration)
                .delay(WorkspaceLayout.sidebarRowGlyphCollapseTravelDelay)
        }
        return .timingCurve(0.32, 0.72, 0, 1, duration: WorkspaceLayout.sidebarRowGlyphExpandTravelDuration())
    }

    // MARK: - Row Background

    /// Hover and selected share one footprint (`SidebarRowCardBackground`):
    /// the row frame, at `rowCornerRadius`.
    private var rowBackground: some View {
        SidebarRowCardBackground(isActive: isActive, isHovered: isHovered, cornerRadius: rowCornerRadius)
            .animation(glyphAnimation, value: widthModel.isCollapsedPresentation)
    }

    /// Row corner radius — the canvas's "8 → 16px" row, same window as the
    /// glyph travel above.
    private var rowCornerRadius: CGFloat {
        widthModel.isCollapsedPresentation
            ? WorkspaceLayout.sidebarRowCornerRadiusTraveled
            : WorkspaceLayout.sidebarRowCornerRadiusResting
    }
}

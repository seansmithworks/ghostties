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
    /// Set while the session genuinely needs the user: the row draws an
    /// action line under its question (`SessionRowPrompt`).
    var prompt: SessionRowPrompt? = nil
    /// `ApprovalFlag` as the list read it: Approve/Deny draw only while on.
    var approvalsEnabled: Bool = false
    let isActive: Bool
    var isEditing: Bool = false
    @Binding var editingName: String
    var isRenameFocused: FocusState<Bool>.Binding
    let onTap: () -> Void
    var onCommitRename: () -> Void = {}
    var onCancelRename: () -> Void = {}
    /// "Answer in terminal →": focus this session.
    var onAnswerInTerminal: () -> Void = {}
    /// Approve/Deny on the bounded prompt `prompt` names.
    var onApprovalDecision: (ApprovalDecision, SessionPopoverContent.ApprovalPrompt) -> Void = { _, _ in }

    /// This row's place in the expand cascade: one index through every
    /// section and project header in reading order (`SidebarLabelCascade`)
    /// — decorative only, feeds `WorkspaceLayout.morphFadeWindow`. Defaults
    /// to 0 so every other call site (unaffected by the stagger) is
    /// unchanged.
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
    /// The bounded prompt whose answer window (`ClaudeStateStore.staleInterval`)
    /// has run out while it showed: its Approve/Deny give way to "Answer in
    /// terminal" without waiting for anything else to redraw the row.
    @State private var expiredApproval: SessionPopoverContent.ApprovalPrompt?

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
            && lhs.prompt == rhs.prompt
            && lhs.approvalsEnabled == rhs.approvalsEnabled
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
            mixID: session.id,
            popover: (session.id, coordinator.sessionPopover),
            actions: actionLine
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
        .modifier(SessionRowPromptAccessibility(
            prompt: prompt, approval: liveApproval,
            onAnswerInTerminal: onAnswerInTerminal, onApprovalDecision: onApprovalDecision
        ))
        .task(id: prompt?.approvalPrompt) { await expireWhenStale(prompt?.approvalPrompt) }
    }

    /// The prompt Approve/Deny answer: a fresh bounded prompt, while the
    /// flag is on. Nil shows "Answer in terminal →" instead.
    private var liveApproval: SessionPopoverContent.ApprovalPrompt? {
        guard approvalsEnabled, let approval = prompt?.approvalPrompt, approval != expiredApproval else { return nil }
        return approval
    }

    /// Sleeps until `approval` ages past the answer window, then retires it.
    private func expireWhenStale(_ approval: SessionPopoverContent.ApprovalPrompt?) async {
        guard let approval else { return }
        let remaining = approval.updatedAt.addingTimeInterval(ClaudeStateStore.staleInterval).timeIntervalSinceNow
        if remaining > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard !Task.isCancelled else { return }
        }
        expiredApproval = approval
    }

    /// A needs-you row's action line: Approve/Deny for a live bounded
    /// prompt, else "Answer in terminal →".
    private var actionLine: SessionRowActionLine? {
        guard prompt != nil, !isEditing else { return nil }
        return SessionRowActionLine(
            sessionId: session.id,
            approval: liveApproval,
            answers: coordinator.sessionPopover.model,
            onApprovalDecision: onApprovalDecision,
            onAnswerInTerminal: onAnswerInTerminal
        )
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        Self.accessibilityLabel(
            name: session.name, projectName: projectName, kind: indicatorState.statusGlyphKind,
            question: prompt?.question,
            hookUnconfirmed: hookUnconfirmed, lastOutput: session.displayTimestamp, isActive: isActive
        )
    }

    /// The row's VoiceOver label, on the sidebar and the rail alike (the
    /// rail shows only the glyph, so the label carries the name): name,
    /// project, spoken status, the hook hint, last output, active.
    static func accessibilityLabel(
        name: String, projectName: String, kind: SessionStatusGlyphKind,
        question: String? = nil,
        hookUnconfirmed: Bool = false, lastOutput: Date? = nil, isActive: Bool
    ) -> String {
        // Same `SessionStatusGlyphKind.spokenStatus` the visible glyph
        // renders from — this row previously stated no status at all.
        var parts = [name, "in \(projectName)", kind.spokenStatus]
        if let question { parts.append(question) }
        if hookUnconfirmed {
            parts.append("Approve the Ghostties hook in Codex")
        }
        if let ts = lastOutput {
            // "last output" — not a bare relative token — so a screen reader
            // has a noun for what this measures. Browsing (focus/selection)
            // no longer advances this value; without the noun, "2m" reads as
            // an event the user didn't cause. A11y string only — the visual
            // row keeps the bare relative label. See RecentsRowView.body.
            parts.append("last output \(relativeLabel(ts))")
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

// MARK: - Row height

/// A sidebar list row's height at rest, the same on the sidebar and the
/// rail: the title band (the row height dial) plus the room a needs-you
/// row holds for its action line. Drag reflow splits a row and sizes its
/// gap with this, so both follow what is drawn.
enum SidebarListRowHeight {
    static func actionLine(hasActions: Bool) -> CGFloat {
        hasActions ? SessionRowActionLine.addedHeight : 0
    }

    static func row(hasActions: Bool) -> CGFloat {
        SidebarDialTuning.rowHeight() + actionLine(hasActions: hasActions)
    }
}

// MARK: - Inline action line

/// The action line's controls as VoiceOver actions: the row is one combined
/// element, so its buttons are offered as named actions on it.
private struct SessionRowPromptAccessibility: ViewModifier {
    let prompt: SessionRowPrompt?
    let approval: SessionPopoverContent.ApprovalPrompt?
    let onAnswerInTerminal: () -> Void
    let onApprovalDecision: (ApprovalDecision, SessionPopoverContent.ApprovalPrompt) -> Void

    func body(content: Content) -> some View {
        if prompt != nil {
            if let approval {
                content
                    .accessibilityAction(named: Text("Approve")) { onApprovalDecision(.approve, approval) }
                    .accessibilityAction(named: Text("Deny")) { onApprovalDecision(.deny, approval) }
            } else {
                content.accessibilityAction(named: Text("Answer in terminal"), onAnswerInTerminal)
            }
        } else {
            content
        }
    }
}

/// A needs-you row's action line, under its question (hover-approvals card
/// 01): Approve (ink fill) and Deny (quiet) for a bounded prompt while
/// `ApprovalFlag` is on, otherwise "Answer in terminal →".
struct SessionRowActionLine: View {
    let sessionId: UUID
    /// The prompt Approve/Deny answer; nil shows "Answer in terminal →".
    let approval: SessionPopoverContent.ApprovalPrompt?
    /// Which prompts a tap (here or on the hover card) already answered.
    @ObservedObject var answers: SessionPopoverModel
    let onApprovalDecision: (ApprovalDecision, SessionPopoverContent.ApprovalPrompt) -> Void
    let onAnswerInTerminal: () -> Void

    /// The hover card's chip height and corner (one control, one size; on
    /// the 4pt scale, where card 01's 20pt is not), with card 01's 8pt side
    /// padding and 4pt gap.
    static let controlHeight: CGFloat = SessionPopoverLayout.actionHeight
    static let controlHorizontalPadding: CGFloat = 8
    static let controlCornerRadius: CGFloat = SessionPopoverLayout.actionCornerRadius
    static let controlSpacing: CGFloat = 4
    /// Room the line adds under the row's title band: the controls, then
    /// the band's own bottom inset again, so the row keeps its margins.
    static let bottomInset: CGFloat = 8
    static var addedHeight: CGFloat { controlHeight + bottomInset }

    @ChromeScheme private var colorScheme

    var body: some View {
        let theme = ChromeTheme.active(colorScheme)
        let size = SidebarDialTuning.rowSubtitleSize()
        HStack(spacing: Self.controlSpacing) {
            if let approval {
                let answered = answers.isAnswered(approval, for: sessionId)
                Group {
                    chip("Approve", size: size, fill: Color(theme.ink), text: Color(theme.canvas)) {
                        onApprovalDecision(.approve, approval)
                    }
                    chip("Deny", size: size, fill: theme.ink(.composerRow), text: SidebarColors.primaryText(colorScheme)) {
                        onApprovalDecision(.deny, approval)
                    }
                }
                // Answered once: off until the prompt changes.
                .disabled(answered)
                .opacity(answered ? SessionPopoverLayout.answeredOpacity : 1)
            } else {
                Button(action: onAnswerInTerminal) {
                    Text("Answer in terminal →")
                        .font(.system(size: size, weight: .medium))
                        .underline()
                        .foregroundStyle(SidebarColors.primaryText(colorScheme))
                        .frame(height: Self.controlHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows this session's terminal")
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func chip(_ title: String, size: CGFloat, fill: Color, text: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(text)
                .padding(.horizontal, Self.controlHorizontalPadding)
                .frame(height: Self.controlHeight)
                .background(fill, in: RoundedRectangle(cornerRadius: Self.controlCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared Row Chrome

/// A sidebar list row's title line: the row title size, and the "Selected
/// title weight" dial on the selected row (macOS 27 sidebar selection:
/// semibold).
struct SidebarListRowTitle: View {
    let text: String
    let isActive: Bool

    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
    @ChromeScheme private var colorScheme

    var body: some View {
        Text(text)
            .font(.system(
                size: SidebarDialTuning.rowTitleSize(),
                weight: isActive ? SidebarDialTuning.selectedTitleWeight().fontWeight : .regular
            ))
            .foregroundStyle(SidebarColors.primaryText(colorScheme))
            .lineLimit(1)
    }
}

/// The visual shell of a sidebar list row (option D, 2026-10-09; rail stays
/// put, 2026-10-22), on the expanded sidebar and the rail alike — one glyph
/// in the leading status slot, on the rail's tile column where the one-view
/// tiles sit, then title over subtitle in the names panel right of the
/// rail's divider; the row height and padding dials, the selected chip,
/// hover, and the row's part in the sidebar ⇄ rail morph: the glyph and
/// chip stay put (`MorphGlyphSlot`) while the labels fade (`MorphLabelFade`). Shared by session rows
/// (`RecentsRowView`) and the History row (`HistoryRowView`) so both render
/// identically by construction. Callers add tap and accessibility on top.
struct SidebarListRowChrome<Title: View, Glyph: View>: View {
    let subtitle: String
    let isActive: Bool
    /// The row's place in the expand cascade, one index across every
    /// section and header (`SidebarLabelCascade`) — feeds
    /// `WorkspaceLayout.morphFadeWindow`.
    var staggerIndex: Int = 0
    let redlineID: String
    /// The row's id on the list's `SelectedRowMix` timeline (a session, or
    /// `SelectedRowMix.historyRowID`); nil shows the resting look.
    var mixID: UUID? = nil
    /// The session whose hover card this row shows, if any. Sidebar only:
    /// on the rail, resting the pointer reveals the whole sidebar instead
    /// (`RailHoverReveal`).
    var popover: (sessionId: UUID, controller: SessionPopoverController)? = nil
    /// The tooltip the row shows on the rail, where its labels are gone.
    var railHelp: String? = nil
    /// A needs-you row's action line, under the labels. The row grows by
    /// its height in the sidebar and loses it on the rail, where only the
    /// glyph shows; the glyph never moves off the title band.
    var actions: SessionRowActionLine? = nil
    @ViewBuilder let title: () -> Title
    /// The status glyph at a given side (the morph's size for this frame).
    @ViewBuilder let glyph: (CGFloat) -> Glyph

    @ChromeScheme private var colorScheme
    @EnvironmentObject private var widthModel: SidebarWidthModel
    @Environment(\.sidebarMorphOverride) private var morphOverride
    @Environment(\.sidebarMorphDials) private var morphDials
    @State private var isHovered = false
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0

    /// The leading status slot: the project tile's width, so a row's glyph
    /// centres under its project's tile.
    static var glyphSlotWidth: CGFloat { RailProjectTile.size }

    var body: some View {
        let progress = morphOverride ?? widthModel.morph
        let metrics = widthModel.metrics(progress, dials: morphDials)
        let dials = metrics.dials
        let bandHeight = SidebarDialTuning.rowHeight()
        // The labels' leading edge in the row's content: the glyph slot,
        // its trailing gap, then the stack spacing (same sum the HStack
        // lays out), so the action line starts under the title.
        let labelLeading = dials.railTileSize
            + max(0, metrics.labelGap - WorkspaceLayout.sidebarIconLabelSpacing)
            + WorkspaceLayout.sidebarIconLabelSpacing
        // The action line's room is held in every state, the rail included
        // (where the line itself fades out), so no tile or glyph below a
        // needs-you row ever moves across the morph or the hover reveal.
        let actionsHeight = SidebarListRowHeight.actionLine(hasActions: actions != nil)
        // The selection (`SelectedRowMix`): this instant's outline, tint,
        // and, for a new row, its growing slot and fading-in content.
        SelectedRowMixRowReader(id: mixID, isActive: isActive) { look in
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: WorkspaceLayout.sidebarIconLabelSpacing) {
                    // Hover is a tile-sized chip behind the glyph in every list
                    // (option D); the group card is drawn only around a project
                    // group.
                    MorphGlyphSlot(
                        progress: progress,
                        slotWidth: dials.railTileSize,
                        glyphSizes: (dials.railGlyphSize, dials.railGlyphSize),
                        chipSizes: (dials.railChipSize, dials.railChipSize),
                        // The chip is hover only; selection is the row's outline.
                        isHovered: isHovered && !isActive,
                        chipID: redlineID + ".chip",
                        glyph: glyph
                    )
                    .redlineFrame(redlineID + ".glyph")
                    // The labels start in the names panel, right of the divider.
                    .padding(.trailing, max(0, metrics.labelGap - WorkspaceLayout.sidebarIconLabelSpacing))

                    // Title + subtitle stacked
                    VStack(alignment: .leading, spacing: 1) {
                        title()

                        Text(subtitle)
                            .font(.system(size: SidebarDialTuning.rowSubtitleSize()))
                            .foregroundStyle(SidebarColors.secondaryText(colorScheme))
                            .lineLimit(1)
                    }
                    .redlineFrame(redlineID + ".label")
                    .modifier(MorphLabelFade(staggerIndex: staggerIndex))

                    Spacer(minLength: 4)
                }
                // The title band: the glyph and labels centre in it whether or
                // not an action line follows.
                .frame(height: bandHeight)
                if let actions {
                    actions
                        .padding(.leading, labelLeading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: actionsHeight, alignment: .top)
                        .clipped()
                        .modifier(MorphLabelFade(staggerIndex: staggerIndex))
                }
            }
            .opacity(look.content)
            .redlineFrame(redlineID + ".content")
            .padding(.leading, SidebarDialTuning.rowLeadingPadding())
            .padding(.trailing, SidebarDialTuning.rowTrailingPadding())
            // Leading: a row too narrow for its labels overflows at the
            // trailing end, so the glyph never leaves the tile column.
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            // 48pt + the enclosing `VStack`'s 4pt row gap = a 52pt pitch, plus
            // a needs-you row's action line. A new row's slot, gap included,
            // grows from nothing (N4).
            .frame(height: (bandHeight + actionsHeight) * look.height)
            // A row that starts or stops needing you grows or shrinks on the
            // fold's spring, the way an accordion opens and closes.
            .animation(SidebarUISpring.fold.animation(entering: actions != nil), value: actions != nil)
            .redlineFrame(redlineID)
            // The row-wide tint and its outline, drawn round the chip on the rail.
            .background {
                SelectedRowOutlineSurface(
                    look: look,
                    progress: progress,
                    chipCenterX: dials.rowLeadingPadding + dials.railTileSize / 2,
                    chipSizes: (dials.railChipSize, dials.railChipSize),
                    // The content centres in the row, so the band's centre
                    // sits half the action line above the row's.
                    chipCenterYOffset: -actionsHeight / 2
                )
            }
            .padding(.top, look.height == 1 ? 0 : SidebarDialTuning.rowGap() * (look.height - 1))
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help(progress >= 0.5 ? (railHelp ?? "") : "")
        .background {
            if let popover, progress < 0.5, !widthModel.isOverlaid {
                Color.clear.sessionPopoverAnchor(sessionId: popover.sessionId, controller: popover.controller)
            }
        }
        // Mid-morph the row is in flight: no clicks, drags or drops land.
        .allowsHitTesting(!widthModel.isMorphing)
    }
}

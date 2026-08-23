import AppKit
import SwiftUI

/// The session composer, presented in the existing sidebar popover (Phase 2
/// of session-creation-unified — fixes D3/D11). A forked COPY of
/// `CommandPalette.swift`, not an edit of it: that file is byte-identical to
/// upstream and editing it in place converts a zero-conflict file into a
/// permanent rebase liability. See
/// `reference_command-palette-reuse` for the gotchas this fork works around.
///
/// Differences from the system palette, each tied to a specific defect:
/// - Sectioned RECENT / TEMPLATES / PROJECTS results instead of one flat
///   list — the search field filters both templates and projects.
/// - An inline project BREADCRUMB CHIP at the head of the query field
///   (Slice A of the breadcrumb spec) instead of the trailing divided
///   project control it replaced — the chip removes the second control
///   competing with the field for width entirely, rather than tuning it.
/// - Prefix-first relevance ranking (`SessionComposerRanking`) instead of
///   boolean-match + color scoring.
/// - Focus-loss auto-dismiss removed: the project dropdown and
///   `+ Add project…`'s `NSOpenPanel` both take first responder, and either
///   would otherwise kill the composer mid-interaction (ship gate 2). This
///   is UNVERIFIED beyond source reading — see `ProjectDropdownView` below.
/// - `ComposerOption.id` is injectable (derived from the underlying
///   template/project id) instead of a fresh `UUID()` per recompute, so
///   options don't churn hover/scroll-to-selection on every keystroke.
/// - Proportions brought down to DESIGN.md's 11pt sidebar scale instead of
///   the system palette's 20pt field / 48pt row (D11).
///
/// NO session-name field — an unpinned session's name is its live terminal
/// title (locked decision). The search field only ever filters templates
/// and projects.
struct SessionComposerPalette: View {
    @Binding var isPresented: Bool
    let request: SessionComposerRequest

    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var coordinator: SessionCoordinator
    @ObservedObject private var composerStore = SessionComposerStore.shared

    @State private var selectedIndex: UInt?
    @State private var hoveredOptionID: UUID?
    /// Whether the inline project-chip picker (A2) is expanded. Replaces
    /// the old `isProjectDropdownOpen` popover flag — this one drives an
    /// expansion INSIDE the card, not a second `.popover`.
    @State private var isProjectChipPickerOpen = false
    /// Whether the inline branch-chip picker (B3) is expanded. Mutually
    /// exclusive with `isProjectChipPickerOpen` BY CONSTRUCTION — every
    /// site that flips one to `true` flips the other to `false` in the
    /// same statement — never merely "the two happen not to overlap in
    /// practice". A second live picker with its own capture layer would
    /// re-create exactly the ambiguity `ComposerQueryField.isPickerOpen`
    /// exists to remove (see that type's doc comment).
    @State private var isBranchChipPickerOpen = false
    /// Keyboard focus on the project chip's `Button`. D5 removed the
    /// left-arrow-from-the-field route into this (see the doc comment on
    /// `.move` handling below) without replacing it, so as of F6 (round-2
    /// review) this is set only by whatever focus route the system already
    /// provides for a focusable control — Tab under Full Keyboard Access,
    /// or VoiceOver navigation — never by anything in this file. The chip
    /// has no Return/Down keyboard handlers of its own; it is mouse- (and
    /// VoiceOver-activation-) only until a real keyboard route exists.
    @FocusState private var isChipFocused: Bool
    @State private var isAddingTemplate = false
    @State private var newTemplateName = ""
    @State private var newTemplateToEdit: AgentTemplate?
    @State private var showDeleteConfirmation = false
    @State private var templateToDelete: AgentTemplate?
    @FocusState private var newTemplateNameFocused: Bool

    // MARK: - No-match Enter feedback (command grammar slice 1)

    /// Drives `ShakeEffect` — 3 cycles / 6pt, animated over 0.25s. Bumped by
    /// one on every no-match Return. `ShakeEffect.effectValue` reads the
    /// ABSOLUTE value of `animatableData`, not a delta — bumping by whole
    /// integers works cleanly anyway because `shakesPerUnit` is an integer,
    /// so every whole increment lands the sine argument back on a
    /// zero-crossing, letting back-to-back no-match Returns restart a clean
    /// shake instead of visibly jumping mid-cycle.
    @State private var shakeTrigger: CGFloat = 0
    /// Reduce-motion fallback: a 400ms red border pulse instead of the
    /// shake, toggled true then back false after the duration.
    @State private var showNoMatchBorder = false
    /// Guards `.submitNoMatch` against a same-turn double-fire from
    /// `.onSubmit` + `Backport.onKeyPress` both firing on macOS 14+ (unlike
    /// `.submit`, nothing here synchronously invalidates a second handler's
    /// input — there's no list to swap out from under it). Set true
    /// synchronously on the first fire, cleared on the next runloop turn, so
    /// a second fire landing in the SAME turn is a no-op instead of driving
    /// `shakeTrigger` 0→2 and doubling the shake to 6 cycles.
    @State private var isHandlingNoMatchFeedback = false

    /// D6: guards `closeChipPickerOrDismiss` against a same-turn double-fire
    /// from its two `.onExitCommand` call sites (`queryRow`'s and
    /// `ComposerQueryField`'s own `.exit` event) — same pattern as
    /// `isHandlingNoMatchFeedback` above.
    @State private var isHandlingExitCommand = false

    // MARK: - DESIGN.md scale (D11) — see `TemplatePickerView` for precedent.
    // `paletteWidth` pulls from `WorkspaceLayout` tokens (DESIGN.md §2
    // forbids hardcoded pt values where an equivalent token exists); the
    // other constants have no `WorkspaceLayout` equivalent. Width varies by
    // presentation (Phase 3): `.anchored` matches the sidebar it pops out
    // of; `.centered` is wider since it floats free of the sidebar column.
    private var paletteWidth: CGFloat {
        switch request.presentation {
        case .anchored: return WorkspaceLayout.sidebarWidth - 16 // offsets `body`'s 8pt-per-side shake-clearance padding (16pt total) so net popover width matches the sidebar
        case .centered: return WorkspaceLayout.composerOverlayWidth
        }
    }

    // MARK: - Two surface classes (Phase 3 review — "New centered-modal
    // surface class")
    //
    // `.anchored` (the Phase 2 sidebar popover) and `.centered` (the Phase 3
    // overlay card) are typographically distinct — the card grew 220pt to
    // 360pt but originally kept the sidebar's own 11pt density, reading as a
    // stretched popover rather than a standalone surface. `.anchored`'s
    // values below are UNCHANGED from Phase 2 (do not restyle the sidebar
    // popover); `.centered` gets its own scale, documented as a canonical
    // surface class in `DESIGN.md` §3/§4/§6/§7 rather than living only here.
    private var fieldHeight: CGFloat {
        switch request.presentation {
        case .anchored: return 30
        case .centered: return 38
        }
    }

    private var fieldFontSize: CGFloat {
        switch request.presentation {
        case .anchored: return 11
        case .centered: return 15
        }
    }

    private var rowFontSize: CGFloat {
        switch request.presentation {
        case .anchored: return 12
        case .centered: return 13
        }
    }

    private var subtitleFontSize: CGFloat {
        switch request.presentation {
        case .anchored: return 10
        case .centered: return 11
        }
    }

    /// Row vertical padding — `ComposerRow`'s existing 5pt (Phase 2,
    /// `.anchored` only) predates the 4pt spacing scale; left as-is since
    /// restyling the popover is out of scope. `.centered` gets the scale's
    /// 8pt.
    private var rowVerticalPadding: CGFloat {
        switch request.presentation {
        case .anchored: return 5
        case .centered: return 8
        }
    }

    /// Card corner radius — `.anchored` keeps its existing 10pt (unstyled,
    /// Phase 2, not touched). `.centered` uses the DESIGN.md §7 terminal-card
    /// radius/style (`WorkspaceLayout.terminalCornerRadius`, `.continuous`) —
    /// the composer card is a peer surface to the terminal card, not a
    /// one-off.
    private var cornerRadius: CGFloat {
        switch request.presentation {
        case .anchored: return 10
        case .centered: return WorkspaceLayout.terminalCornerRadius
        }
    }

    /// DESIGN.md §7: "One radius. One style. No exceptions... Always pass
    /// `style: .continuous`." `.anchored` keeps the unstyled default
    /// (`.circular`) it shipped with in Phase 2; `.centered` is `.continuous`.
    private var cornerStyle: RoundedCornerStyle {
        switch request.presentation {
        case .anchored: return .circular
        case .centered: return .continuous
        }
    }

    private var composerClipShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: cornerStyle)
    }

    private static let sectionHeaderFontSize: CGFloat = 10

    private var isProjectLocked: Bool {
        if case .locked = request.projectBinding { return true }
        return false
    }

    private var query: String {
        composerStore.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentProject: Project? {
        // Command grammar slice 1: a resolved `<project> <remainder>` parse
        // takes precedence over `selectedProjectId` — the remainder needs
        // to filter THAT project's templates even though the dropdown
        // selection hasn't changed (selectProject(_:) also clears the
        // query, which would erase what's being typed).
        if let commandProject { return commandProject }
        guard let id = composerStore.selectedProjectId else { return nil }
        return store.projects.first(where: { $0.id == id })
    }

    // MARK: - Command grammar (slice 1)

    /// Tokenizes `query` against the known project list. `.none` (the
    /// common case) means "no command recognized" — every downstream
    /// filter below falls through to the ordinary whole-string query,
    /// byte-identical to before this parser existed.
    private var commandParse: SessionComposerCommandParser.ParseResult {
        SessionComposerCommandParser.parse(query: query, projects: store.projects, isLocked: isProjectLocked)
    }

    private var commandProject: Project? {
        if let projectId = commandParse.projectId {
            return store.projects.first(where: { $0.id == projectId })
        }
        // D3 fix: a genuine ≥2-token command whose remainder has been
        // backspaced down to nothing falls out of `commandParse` (it
        // requires ≥2 tokens), which used to drop the chip back to
        // whatever `selectedProjectId` still read — see
        // `SessionComposerCommandParser.stickyChipProjectId`'s doc comment
        // for the full failure mode. Keeps the chip resolved through that
        // empty-remainder state.
        guard let stickyId = SessionComposerCommandParser.stickyChipProjectId(
            rawQuery: composerStore.searchText,
            projects: store.projects,
            isLocked: isProjectLocked
        ) else { return nil }
        return store.projects.first(where: { $0.id == stickyId })
    }

    // MARK: - Branch chip (Slice B, B3)

    /// Whether the project is a git repo at all — the branch chip has no
    /// entry point unless the composer store's cache found SOMETHING to
    /// offer. A non-git project (or one where enumeration failed) shows NO
    /// chip, not a disabled one (Sean's call) — a dead control is worse
    /// than no control. This is deliberately keyed off "did enumeration
    /// find anything", not a dedicated repo-detection call, matching how
    /// `GitWorktreeEnumerator` already reports "not a repo" (exit 128 →
    /// `[]`, indistinguishable from "a repo with nothing else to offer").
    private var isBranchChipEligible: Bool {
        !composerStore.worktrees.isEmpty || !composerStore.branchesWithoutWorktree.isEmpty
    }

    /// A resolved TYPED branch (`> main > cco`) takes precedence over the
    /// picker's current pick, mirroring `currentProject`'s
    /// `commandProject`-before-`selectedProjectId` precedence exactly.
    private var typedWorktreePath: String? {
        guard let token = commandParse.branchToken else { return nil }
        return composerStore.worktrees.first(where: { $0.branch == token })?.path
    }

    /// What the branch chip displays: the typed branch token if a command
    /// resolved one, else the picker's current pick's branch name, else
    /// `nil` (no chip rendered — see `queryRow`).
    private var currentBranchLabel: String? {
        if let token = commandParse.branchToken { return token }
        guard let path = composerStore.selectedWorktreePath else { return nil }
        return composerStore.worktrees.first(where: { $0.path == path })?.branch ?? path
    }

    /// The breadcrumb chip's displayed/editable text (A1). When a typed
    /// command has resolved a project, this is the remainder ONLY — the
    /// resolved token renders as the chip instead, and edits reconstruct
    /// the full stored string by re-prepending the ORIGINAL prefix (the
    /// matched token plus whatever whitespace separated it, taken verbatim
    /// from `searchText`). Otherwise it is `composerStore.searchText`
    /// unchanged, exactly as before chips existed.
    ///
    /// B1 fix: this used to `get` `commandParse.remainderText` — a display
    /// string rebuilt as `remainderTokens.joined(separator: " ")` — and `set`
    /// by re-prepending the matched token with a single hardcoded space. That
    /// round trip silently ate trailing whitespace and stripped quote
    /// characters (SwiftUI writes the `get`'s lossy value straight back into
    /// the field on the next render), making `ghostties cco -n "test"`
    /// untypable: the first space after `-n` never survived. Routing through
    /// `SessionComposerCommandParser.splitOnFirstToken` instead means BOTH
    /// halves are exact substrings of the real `searchText` — there is no
    /// reconstruction step left to lose anything in.
    private var queryFieldText: Binding<String> {
        Binding(
            get: {
                guard commandProject != nil,
                      let split = SessionComposerCommandParser.splitOnFirstToken(composerStore.searchText)
                else { return composerStore.searchText }
                return split.remainder
            },
            set: { newValue in
                // D4: any real keystroke disarms a pending chip-undo — see
                // `SessionComposerStore.noteSearchTextEditedByTyping()`.
                composerStore.noteSearchTextEditedByTyping()
                guard commandProject != nil,
                      let split = SessionComposerCommandParser.splitOnFirstToken(composerStore.searchText)
                else {
                    composerStore.searchText = newValue
                    return
                }
                composerStore.searchText = split.prefix + newValue
            }
        )
    }

    /// The text template/recent options are ranked against. A resolved
    /// command scopes filtering to the remainder (`cco -n test`, not the
    /// whole `ghostties cco -n test` query) — otherwise nothing in the
    /// project's own template list would ever match the project name that
    /// prefixes it.
    private var templateFilterQuery: String {
        commandProject != nil ? commandParse.remainderText : query
    }

    /// The `Run "<remainder>"` row appended in a new COMMAND section once a
    /// command is recognized. Blanket-running the remainder happens ONLY
    /// here, behind the same ≥2-token + project-match gate as the rest of
    /// the grammar — `filteredTemplateOptions` above still ranks any
    /// matching template first, so `ghostties orchestrator` keeps reaching
    /// the Orchestrator template instead of trying to exec a nonexistent
    /// `orchestrator` binary.
    private var commandOptions: [ComposerOption] {
        guard let commandProject,
              let template = SessionComposerCommandParser.makeAdHocTemplate(remainderTokens: commandParse.remainderTokens)
        else { return [] }

        return [
            ComposerOption(
                id: SessionComposerCommandParser.runRowId,
                title: "Run \"\(commandParse.remainderText)\"",
                subtitle: commandProject.name,
                leadingIcon: "terminal",
                action: { commit(template: template) }
            )
        ]
    }

    // MARK: - Options

    private func makeOption(for template: AgentTemplate) -> ComposerOption {
        let group = SessionTemplateResolver.group(for: template)
        let isPreset = group == .preset

        // Restores the "Default shell" subtitle fallback `TemplatePickerView`
        // ships: description first, then command (non-presets only), then
        // "Default shell" (non-presets only). Presets with no description
        // render no subtitle, matching the original.
        let subtitle: String? = {
            if let description = template.templateDescription { return description }
            if !isPreset, let command = template.command { return command }
            if !isPreset { return "Default shell" }
            return nil
        }()

        return ComposerOption(
            id: template.id,
            title: template.name,
            subtitle: subtitle,
            leadingIcon: template.icon ?? iconName(for: template),
            action: { commit(template: template) },
            template: template,
            templateGroup: group
        )
    }

    private func makeOption(for project: Project) -> ComposerOption {
        ComposerOption(
            id: project.id,
            title: project.name,
            subtitle: nil,
            leadingIcon: "folder",
            // `SessionComposerStore.selectProject(_:)` clears the query
            // alongside the id — load-bearing, not tidying: leaving a
            // project-scoping query like "ghos" in place after a project
            // row commits filters the newly-scoped project's OWN templates
            // against that same text, which rarely matches anything —
            // Return would silently do nothing (D1's dead end, PR #132
            // review round 2, F2). `selectedIndex = nil` here is the SAME
            // invariant `commit(template:)` documents (N1): every action
            // that replaces the option list nils `selectedIndex` FIRST, so
            // a same-keystroke double-fire (`.onSubmit` +
            // `.backport.onKeyPress`, macOS 14+) can't resolve
            // `selectedOption` against a list this action just swapped out
            // from under it (F1, PR #132 review round 2). `.onChange(of:
            // query)` -> `reselectBestMatch()` re-seeds it in the same
            // update pass, so nothing is lost.
            action: {
                selectedIndex = nil
                composerStore.selectProject(project.id)
            }
        )
    }

    private func iconName(for template: AgentTemplate) -> String {
        switch template.kind {
        case .shell: return "terminal"
        case .claudeCode: return template.agent != nil ? "cpu" : "sparkle"
        case .custom: return "gearshape"
        case .browser: return "globe"
        }
    }

    private var availableTemplates: [AgentTemplate] {
        guard let project = currentProject else { return [] }
        return SessionTemplateResolver.templates(for: project, store: store)
    }

    /// Recent `(project, template)` pairs scoped to the current project,
    /// most-recent-first, deduplicated by template.
    private var recentOptions: [ComposerOption] {
        guard let project = currentProject else { return [] }
        let recentIds = composerStore.recentSelections
            .filter { $0.projectId == project.id }
            .map { $0.templateId }

        var seen = Set<UUID>()
        var result: [ComposerOption] = []
        for id in recentIds {
            guard !seen.contains(id), let template = availableTemplates.first(where: { $0.id == id }) else { continue }
            seen.insert(id)
            result.append(makeOption(for: template))
        }
        return result
    }

    private var filteredRecentOptions: [ComposerOption] {
        SessionComposerRanking.sorted(recentOptions, query: templateFilterQuery, title: { $0.title }, subtitle: { $0.subtitle })
    }

    private var filteredTemplateOptions: [ComposerOption] {
        let recentIds = Set(filteredRecentOptions.map { $0.id })
        let base = availableTemplates
            .map(makeOption)
            .filter { !recentIds.contains($0.id) }
        return SessionComposerRanking.sorted(base, query: templateFilterQuery, title: { $0.title }, subtitle: { $0.subtitle })
    }

    /// Query-matching projects (S2, locked decision: "the search field
    /// filters BOTH templates and projects"). Empty when the query is
    /// blank — the trailing dropdown already covers browsing every project
    /// unfiltered. Selecting a row here sets the composer's selected
    /// project; it does not start a session.
    private var filteredProjectOptions: [ComposerOption] {
        // N3: `.locked` fixes the project at the write path (`commit()`
        // resolves from the bound project, never `selectedProjectId`), so
        // letting a project row re-scope the list here would show project B
        // while `commit()` still creates in locked project A.
        //
        // A resolved command does NOT suppress this section (reverted —
        // that suppression was never in the brief and made a multi-word
        // project name unreachable: with projects "ghostties" and
        // "ghostties web", typing "ghostties web" resolves token 1 against
        // the first project and, with PROJECTS hidden, offers only
        // `Run "web"` — the project being named disappears from the list.
        // A mis-parse must stay recoverable, so PROJECTS keeps ranking
        // against the raw `query` exactly as it does with no command typed.
        guard !isProjectLocked, !query.isEmpty else { return [] }
        let options = store.projects.map(makeOption)
        return SessionComposerRanking.sorted(options, query: query, title: { $0.title })
    }

    /// The full flattened list, in on-screen order, used for keyboard
    /// navigation and selection clamping. COMMAND renders last — matching
    /// templates in TEMPLATES rank first, per the locked design.
    private var flattenedOptions: [ComposerOption] {
        filteredRecentOptions + filteredTemplateOptions + filteredProjectOptions + commandOptions
    }

    private var selectedOption: ComposerOption? {
        guard let selectedIndex else { return nil }
        let options = flattenedOptions
        return if selectedIndex < options.count {
            options[Int(selectedIndex)]
        } else {
            options.last
        }
    }

    /// D1 fix: the best-tier option across the WHOLE flattened list, not
    /// just index 0. RECENT → TEMPLATES → PROJECTS render in that fixed
    /// section order (`flattenedOptions`), and `SessionComposerRanking.sorted`
    /// only ranks WITHIN each section — so a `.substring` match on a
    /// Templates row's subtitle used to always beat an `.exactPrefix` match
    /// on a Projects row purely because Templates renders above Projects
    /// (e.g. typing "ghos" selected a "Linear Sync" template whose
    /// description mentions "Ghostties" over the "ghostties" project
    /// itself). Ties — including a blank query, where every option is
    /// untiered — keep index 0, i.e. current section order, so unambiguous
    /// queries and the empty-query default are unchanged.
    private func bestSelectionIndex(in options: [ComposerOption]) -> UInt {
        UInt(SessionComposerRanking.bestMatchIndex(in: options, query: templateFilterQuery, title: { $0.title }, subtitle: { $0.subtitle }))
    }

    // MARK: - Body

    var body: some View {
        let scheme: ColorScheme = OSColor(Color(nsColor: .windowBackgroundColor)).isLightColor ? .light : .dark

        // Shake-clearance wrapper (finding: `.anchored` is an NSPopover
        // sized exactly to its content — a shake applied to the composer's
        // root, with no margin around it, clips or draws over the popover
        // chrome). The card itself stays `paletteWidth` wide; this adds an
        // 8pt clear inset on ALL FOUR SIDES (DESIGN.md §5 Layout Tokens —
        // 8 is the nearest valid step above the ±6pt shake amplitude) so
        // the ±6pt lateral translation has room in both `.anchored` and
        // `.centered`. Symmetric, not horizontal-only: it's the same
        // component in both presentations, so it gets the same pattern —
        // an inset flush top/bottom but padded left/right would read as a
        // clipping bug rather than a frame. `paletteWidth`'s `.anchored`
        // case subtracts this same 16pt (8pt × 2 sides) so the net
        // popover width still matches the sidebar exactly; `.centered`'s
        // card width (`composerOverlayWidth`) is unaffected since only
        // the outer padding grows.
        composerCard
            .padding(8)
            // Overlay shadow (DESIGN.md §6, `.centered` only — Phase 3
            // review fix, retuned in PR #132 (shadow-only elevation) now
            // that the shadow carries the "on top of" read alone, with no
            // scrim behind it). `.anchored` relies on the native NSPopover
            // chrome/shadow instead; adding a second shadow there would
            // double up.
            .shadow(
                color: request.presentation == .centered
                    ? .black.opacity(WorkspaceLayout.composerModalShadowOpacity)
                    : .clear,
                radius: request.presentation == .centered ? WorkspaceLayout.composerModalShadowRadius : 0,
                y: request.presentation == .centered ? WorkspaceLayout.composerModalShadowYOffset : 0
            )
            .environment(\.colorScheme, scheme)
            .onAppear {
                composerStore.open(projectBinding: request.projectBinding, workspaceStore: store)
                // S5: row 0 is the project's default template (Phase 1's
                // default-first ordering) and the legend reads "↵ start" —
                // seed the selection so Return isn't a dead key on first
                // open. `bestSelectionIndex` is index 0 here since the
                // query is blank on first open (D1's cross-section ranking
                // only applies once there's a query to rank against).
                selectedIndex = bestSelectionIndex(in: flattenedOptions)
            }
            .onChange(of: isPresented) { presented in
                if !presented {
                    composerStore.cancel()
                    isAddingTemplate = false
                    newTemplateName = ""
                    isProjectChipPickerOpen = false
                }
            }
            .onDisappear {
                // The only reliable teardown hook for popover content — the
                // row hosting this popover can leave the hierarchy (project
                // removed, sidebar view-mode switch, `windowDidResignKey` /
                // `mouseExited` closing the popover) without
                // `onChange(of: isPresented)` ever firing, which otherwise
                // latches `SessionComposerStore.isOpen` true forever (B3).
                composerStore.cancel()
            }
            .onChange(of: query) { _ in reselectBestMatch() }
            .onChange(of: composerStore.selectedProjectId) { _ in
                // N5: changing the project via the dropdown or a project row
                // changes `flattenedOptions.count` with `query` unchanged, so
                // the query-only clamp above never ran — `selectedOption`
                // fell back to `options.last` and the highlight silently
                // jumped to the bottom of the list.
                clampSelectedIndex()
            }
            .onChange(of: commandProject?.id) { _ in
                // F3 fix (round-2 review): `query` is the TRIMMED search
                // text, so the keystroke that arms the sticky chip (typing
                // the space after a project name) leaves `query` byte-
                // identical — the `onChange(of: query)` above never fires.
                // `selectedProjectId` doesn't change on that keystroke
                // either, so N5's clamp above didn't fire. But
                // `commandProject` flips `nil` -> resolved on exactly that
                // keystroke, and `flattenedOptions` swaps to the resolved
                // project's templates wholesale underneath the still-unclamped
                // `selectedIndex` — if the new list is shorter, `selectedOption`
                // fell through to `options.last` and Return committed the
                // wrong row. Same fix as N5, triggered off the thing that
                // actually changes the list at that moment.
                clampSelectedIndex()
            }
            .onChange(of: composerStore.focusSearchFieldTrigger) { triggered in
                // R8 (Phase 3 review round 2): mirrors the S5 seed in
                // `onAppear` for the "re-open while already installed" path
                // (F4) — `onAppear` doesn't reliably re-fire there (observed,
                // see F4's comment in
                // `WorkspaceViewContainer.presentComposerOverlay`), so a
                // `selectedIndex` left `nil` by a just-completed commit
                // (S1's reset) never gets re-seeded, and Return goes dead on
                // a fast re-present. `focusSearchFieldTrigger` is exactly
                // `open()`'s "already open" signal (S7) — unlike `isOpen`
                // itself, which SwiftUI's `.onChange` won't re-fire on since
                // it stays `true` across the whole re-open.
                guard triggered else { return }
                clampSelectedIndex()
            }
            .sheet(item: $newTemplateToEdit) { template in
                TemplateEditForm(template: template)
            }
            .alert(
                "Delete Template?",
                isPresented: $showDeleteConfirmation,
                presenting: templateToDelete
            ) { template in
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    store.removeTemplate(id: template.id)
                }
            } message: { template in
                if store.templateInUse(id: template.id) {
                    Text("Sessions using \"\(template.name)\" will keep their current configuration but won't be relaunchable with this template.")
                } else {
                    Text("This will permanently remove \"\(template.name)\".")
                }
            }
    }

    /// The composer's visible card — background, clip shape, border, the
    /// no-match feedback overlays, and the shake itself. Kept separate from
    /// `body` so the shake-clearance inset (`body`'s `.padding(8)`) wraps
    /// it rather than the shake living on the true root, which
    /// left no room to translate inside an `.anchored` NSPopover sized
    /// exactly to its content.
    private var composerCard: some View {
        let backgroundColor = Color(nsColor: .windowBackgroundColor)

        return VStack(alignment: .leading, spacing: 0) {
            queryRow
                // A4: ⌘Z restores the chip cascade's cleared segment(s) as
                // one step. Scoped to only exist while something is
                // actually pending. D4 fix: this DOES contend with AppKit's
                // own text undo, despite an earlier version of this comment
                // claiming otherwise — this `Button`'s shortcut writes
                // `searchText`/`selectedProjectId` directly, bypassing the
                // field editor's undo manager entirely, so typing after a
                // chip change followed by ⌘Z used to discard those
                // keystrokes with NO way to get them back (a second ⌘Z had
                // nothing left to restore them from either). Fixed by
                // disarming `pendingChipUndo` the moment the user edits
                // `searchText` by typing (`queryFieldText`'s setter calls
                // `SessionComposerStore.noteSearchTextEditedByTyping()`) —
                // once that happens this overlay's `Button` simply stops
                // existing, so a stray ⌘Z falls through to AppKit's own
                // text undo instead of silently eating new keystrokes.
                .overlay {
                    if composerStore.pendingChipUndo != nil {
                        Button(action: undoChipCascade) { Color.clear }
                            .buttonStyle(PlainButtonStyle())
                            .keyboardShortcut("z", modifiers: [.command])
                            .frame(width: 0, height: 0)
                            .accessibilityHidden(true)
                    }
                }

            Divider()

            ComposerResultsTable(
                sections: [
                    (title: filteredRecentOptions.isEmpty ? nil : "RECENT", options: filteredRecentOptions),
                    (title: "TEMPLATES", options: filteredTemplateOptions),
                    (title: filteredProjectOptions.isEmpty ? nil : "PROJECTS", options: filteredProjectOptions),
                    (title: commandOptions.isEmpty ? nil : "COMMAND", options: commandOptions)
                ],
                query: query,
                selectedIndex: $selectedIndex,
                hoveredOptionID: $hoveredOptionID,
                rowFontSize: rowFontSize,
                subtitleFontSize: subtitleFontSize,
                sectionHeaderFontSize: Self.sectionHeaderFontSize,
                rowVerticalPadding: rowVerticalPadding,
                onEditTemplate: { newTemplateToEdit = $0 },
                onDuplicateTemplate: { _ = store.duplicateTemplate(id: $0.id) },
                onDuplicateAndEditTemplate: {
                    if let copy = store.duplicateTemplate(id: $0.id) { newTemplateToEdit = copy }
                },
                onEditPresetFile: { openPresetInEditor($0) },
                onRequestDeleteTemplate: {
                    templateToDelete = $0
                    showDeleteConfirmation = true
                }
            ) { option in
                // Does NOT dismiss the popover here — `option.action()` (a
                // template commit) only clears `isPresented` once the store
                // confirms the write succeeded (S6). Dismissing eagerly, as
                // this used to, closed the composer with no session and no
                // visible error whenever `commit()`'s pre-check failed.
                option.action()
            }

            Divider()

            if let writeError = composerStore.writeError {
                Text(writeError)
                    .font(.system(size: subtitleFontSize))
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
            }

            newTemplateRow
        }
        .frame(width: paletteWidth)
        .background(
            ZStack {
                Rectangle().fill(.regularMaterial)
                Rectangle().fill(backgroundColor).blendMode(.color)
            }
            .compositingGroup()
        )
        .clipShape(composerClipShape)
        .overlay(
            composerClipShape
                .stroke(Color(nsColor: .tertiaryLabelColor).opacity(0.75))
        )
        // No-match Enter feedback: a 400ms red border pulse under
        // reduce-motion, standing in for the shake below (`triggerNoMatchFeedback`).
        .overlay(
            composerClipShape
                .stroke(Color(nsColor: .systemRed), lineWidth: 2)
                .opacity(showNoMatchBorder ? 1 : 0)
        )
        .modifier(ShakeEffect(animatableData: shakeTrigger))
    }

    // MARK: - Query row (breadcrumb chip + search field, A1/A2)
    //
    // The project no longer competes with the field for width as a
    // trailing control (the old trailing project label/button and its
    // `isProjectDropdownOpen` popover flag, both deleted) — it renders as
    // a chip at the HEAD of the same field, with
    // the remainder staying live editable text (`queryFieldText`).
    // Changing the chip expands `inlineProjectPicker` INSIDE the card
    // (below the field, `isProjectChipPickerOpen`), never a second
    // `.popover` — the old trailing control's picker was a `.popover`
    // nested inside the composer's own `.popover`, on the known-fragile
    // list and never verified; two chips would have doubled that risk.
    //
    // B2 fix: the chip is now ALWAYS present, even with no project selected
    // (`currentProject == nil`) — it renders a "Select project" placeholder
    // that still opens the picker. The prior version only rendered anything
    // here `if let project = currentProject`, which had no fallback at all
    // once the trailing dropdown's old always-present control was deleted:
    // backspacing a picker-selected chip back to raw text
    // (`popChipToText`), or a fresh install with zero projects, left NO
    // project control on screen whatsoever — `+ Add project…` (the only way
    // to escape zero projects) was unreachable.

    /// D7/round-4 fix: there is no width cap on the chip. Three prior rounds
    /// each shipped `.frame(maxWidth: chipMaxWidth)` on the chip's `Text`,
    /// and each time it was wrong for the same reason: `.frame(maxWidth:)`
    /// on a flexible axis is greedy, not a ceiling — offered more space than
    /// the view's own ideal size, it returns the *proposed* size clamped to
    /// the maximum, not its content size. A short name (`atlas-api`) and a
    /// long one (`ghostties-website-redesign`) both got proposed the same
    /// width by the parent `HStack`, so both rendered as the same fixed
    /// 96pt slab — a short name padded with dead tinted background, a long
    /// one truncated for no reason. Screenshots proved this identically in
    /// both the `.anchored` and locked/`.centered` cards.
    ///
    /// The fix is to have no `.frame(maxWidth:)` at all. `Text` with
    /// `.lineLimit(1)` + `.truncationMode(.tail)` is NOT greedy on its own:
    /// offered more space than it needs, it reports its own ideal width;
    /// offered less, it truncates. F1 (round-2 review, still true) already
    /// established that neither child in the `HStack` below carries
    /// `.layoutPriority` — with none set, the chip's `Text` claims only what
    /// its content needs and the `TextField`, which has no maximum, absorbs
    /// the rest. That is what makes a short chip hug its text and a long
    /// chip truncate only when the row genuinely runs out of room, instead
    /// of both being clamped to one arbitrary number.
    ///
    /// No hard ceiling is enforced for the wide `.centered` card. A true cap
    /// would need `ViewThatFits(in: .horizontal)` (macOS 13-safe), not a
    /// max-only frame — not added here because it wasn't proven necessary
    /// against the capture harness; the `HStack`'s own space division was
    /// sufficient in every observed card width.

    private var queryRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                projectChip(currentProject)

                Text("›")
                    .font(.system(size: fieldFontSize, weight: .regular))
                    .foregroundStyle(.tertiary)
                    // Decorative separator between the chip and the field —
                    // carries no information VoiceOver needs (nit).
                    .accessibilityHidden(true)

                // B3: rendered only when the project is eligible (a git
                // repo enumeration found something to offer) — a
                // non-git project shows NO branch chip at all, not a
                // disabled one (Sean's call).
                if isBranchChipEligible {
                    branchChip()

                    Text("›")
                        .font(.system(size: fieldFontSize, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }

                ComposerQueryField(
                    query: queryFieldText,
                    fontSize: fieldFontSize,
                    focusTrigger: $composerStore.focusSearchFieldTrigger,
                    hasSelection: selectedOption != nil,
                    // D6/B3: while EITHER inline picker is open, the field's
                    // own ↑/↓/Return handlers must go quiet — see
                    // `ComposerQueryField.isPickerOpen`'s doc comment. The
                    // two pickers are mutually exclusive by construction
                    // (see `isBranchChipPickerOpen`'s doc comment) — the
                    // field only needs "is ANY picker open", the OR.
                    isPickerOpen: isProjectChipPickerOpen || isBranchChipPickerOpen,
                    // Nit: the placeholder still said "...and projects" even
                    // once a chip has already picked the project — the
                    // field only filters that project's templates at that
                    // point, never projects.
                    placeholder: currentProject != nil ? "Search templates…" : "Search templates and projects…"
                ) { event in
                    handle(event)
                }
                .frame(height: fieldHeight)
            }
            .padding(.horizontal, 10)

            if isProjectChipPickerOpen {
                Divider()
                inlineProjectPicker
            } else if isBranchChipPickerOpen {
                Divider()
                inlineBranchPicker
            }
        }
        // A5: Esc while focus is on the chip or inside the inline picker
        // (i.e. NOT in the text field, which has its own `onExitCommand`
        // below that routes through the same `closeChipPickerOrDismiss`)
        // closes the picker without closing the composer.
        .onExitCommand(perform: closeChipPickerOrDismiss)
    }

    /// The chip itself. `.locked` renders a static label with no picker
    /// affordance (A2) — matching the old trailing control's locked branch.
    /// Sean's call, flagged as a strawman rather than settled: `.locked`
    /// drops the pill background entirely (plain secondary text + the `›`)
    /// instead of inheriting the interactive chip's pill — a pill with no
    /// picker behind it reads as a control that isn't one, same reasoning
    /// DESIGN.md already records for the control this replaced.
    ///
    /// F5 fix (round-2 review): `.locked` is gated on `isProjectLocked`
    /// ALONE now, never `isProjectLocked, let project` — the old `if let`
    /// fell through to the INTERACTIVE `else` branch whenever the locked
    /// project couldn't resolve (e.g. deleted mid-composer), rendering a
    /// live picker `Button` and key handlers inside what is supposed to be
    /// an inert, locked composer. `commit(template:)`'s write target was
    /// never at risk (`precommit` resolves from `currentProjectBinding`,
    /// never from this view's render), so this was affordance-only, but a
    /// locked chip that starts opening a picker on click is still wrong.
    ///
    /// `project == nil` (B2) renders a "Select project" placeholder in the
    /// SAME interactive chip shape rather than nothing — this is the only
    /// project affordance in the composer once the trailing control was
    /// deleted, so it must survive every reachable state: no project chosen
    /// yet, a chip popped back to raw text, and zero projects on a fresh
    /// install (where its only job is making `+ Add project…` reachable via
    /// the picker it opens).
    @ViewBuilder
    private func projectChip(_ project: Project?) -> some View {
        if isProjectLocked {
            Text(project?.name ?? "Project unavailable")
                .font(.system(size: fieldFontSize, weight: .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
                // F7/a11y: a bare `Text` reads its content with no context —
                // VoiceOver announced a naked folder name. Frames it as the
                // locked project, and degrades to a neutral label rather
                // than reading nothing at all if `project` can't resolve.
                .accessibilityLabel(project.map { "Project: \($0.name)" } ?? "Project unavailable")
        } else {
            let label = Text(project?.name ?? "Select project")
                .font(.system(size: fieldFontSize, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isProjectChipPickerOpen ? WorkspaceLayout.composerChipBackgroundActive : WorkspaceLayout.composerChipBackground)
                // 5pt matches `ComposerRow`'s existing row highlight in this
                // same file — not a new arbitrary radius. `.clipShape(...,
                // style: .continuous)` replaces the deprecated, non-`.continuous`
                // `.cornerRadius(5)` API per DESIGN.md §7 ("Always pass
                // `style: .continuous`").
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            Button {
                // Mouse click TOGGLES (click-to-open, click-again-to-close —
                // the ordinary disclosure-control gesture); Return/Down
                // below only ever OPEN. Deliberately different, not an
                // oversight flagged and left as-is (review fragility note):
                // a keyboard route that could CLOSE the picker on Down would
                // make Down ambiguous with "move to the next row inside an
                // already-open picker" once D6's picker-level Down handler
                // exists. The two inputs don't fire in the same turn, so the
                // differing polarity is not a double-fire risk in practice.
                // B3: closing the branch picker in the SAME statement is
                // what makes the two mutually exclusive by construction —
                // not merely "the two happen not to overlap in practice".
                isBranchChipPickerOpen = false
                isProjectChipPickerOpen.toggle()
            } label: {
                label
            }
            .buttonStyle(.plain)
            .focused($isChipFocused)
            .accessibilityHint("Opens project picker")
            // F6 fix (round-2 review): the A5 Return/Down handlers that used
            // to live here are DELETED, not left guarded. Left-arrow (D5,
            // see the `.move` doc comment below) was the only thing in this
            // file that ever wrote `isChipFocused` true, and D5 removed it
            // without replacing it — so `guard isChipFocused` never passed
            // via any route this file controls, and the handlers asserted a
            // keyboard capability (Return/Down opens the picker) that had
            // already gone unreachable. Left as dead code, they'd silently
            // reassert that capability to the next reader. The chip stays
            // reachable by mouse click and by whatever focus route the
            // system itself provides for a focusable `Button` (Tab under
            // Full Keyboard Access, VoiceOver) — `isChipFocused` is kept
            // wired for that, not for a route this file no longer has.
        }
    }

    /// A2: `ProjectDropdownView`'s list content, reused verbatim, but
    /// presented as an expansion inline inside the composer card instead of
    /// via `.popover` — see the type's own doc comment for why that was
    /// fragile. A6: `currentProject?.id`, not the raw
    /// `composerStore.selectedProjectId`, is the single source of truth
    /// passed in for both cascade ordering and the selected-row highlight —
    /// fixes the checkmark-vs-label disagreement that existed whenever a
    /// typed command resolved a DIFFERENT project than `selectedProjectId`
    /// still read.
    private var inlineProjectPicker: some View {
        ProjectDropdownView(selectedProjectId: currentProject?.id) { project in
            changeProjectChip(to: project)
        } onAddProject: {
            composerStore.addProjectViaPanel(workspaceStore: store)
            isProjectChipPickerOpen = false
        }
        .environmentObject(store)
    }

    // MARK: - Branch chip (Slice B, B3)

    /// The branch chip. No `.locked` state — the composer never locks the
    /// BRANCH the way `.locked` binding locks the project, only whether it
    /// appears at all (`isBranchChipEligible`). Label is "Default" when
    /// nothing is picked and no command resolved one — the picker's own
    /// "Default (<branch>)" row uses the SAME word so the chip and the row
    /// that clears it read as the same concept.
    private func branchChip() -> some View {
        // B4: "Creating…" while `createWorktree` is in flight overrides
        // whatever `currentBranchLabel` would otherwise show — there is no
        // resolved branch/worktree to display yet.
        let label = Text(composerStore.isCreatingWorktree ? "Creating…" : (currentBranchLabel ?? "Default"))
            .font(.system(size: fieldFontSize, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isBranchChipPickerOpen ? WorkspaceLayout.composerChipBackgroundActive : WorkspaceLayout.composerChipBackground)
            // Same 5pt/`.continuous` shape as `projectChip` — one radius,
            // one style, no exceptions (DESIGN.md §7).
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

        return Button {
            // B3: closes the project picker in the SAME statement — see
            // that Button's matching line for why this makes the two
            // mutually exclusive by construction, not by convention.
            isProjectChipPickerOpen = false
            isBranchChipPickerOpen.toggle()
        } label: {
            label
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens branch picker")
        // B3: opening the picker is also the third refresh trigger (on top
        // of B1's project-selection and initial-open triggers) — Sean runs
        // 2-7 parallel sessions creating worktrees constantly, so THIS is
        // the moment accuracy matters most.
        .onChange(of: isBranchChipPickerOpen) { isOpen in
            guard isOpen, let project = currentProject else { return }
            Task { await composerStore.refreshWorktrees(for: project.rootPath) }
        }
    }

    /// `WorktreeDropdownView`'s list content, presented as an inline
    /// expansion inside the card — NEVER a `.popover`, same reasoning as
    /// `inlineProjectPicker` (a nested popover is exactly what Slice A
    /// deleted: a child taking key can dismiss the parent composer).
    private var inlineBranchPicker: some View {
        WorktreeDropdownView(
            worktrees: composerStore.worktrees,
            branchesWithoutWorktree: composerStore.branchesWithoutWorktree,
            currentBranchAtProjectRoot: composerStore.currentBranchAtProjectRoot,
            isRefreshing: composerStore.isRefreshingWorktrees,
            selectedWorktreePath: composerStore.selectedWorktreePath,
            onSelectDefault: {
                composerStore.clearBranchChip()
                isBranchChipPickerOpen = false
            },
            onSelectWorktree: { path in
                changeBranchChip(to: path)
            },
            // B4: selecting a create row does NOT launch a session — it
            // closes the picker (same statement, mirroring `onSelectDefault`/
            // `onSelectWorktree` above) and arms creation with the composer
            // still open. The branch chip shows "Creating…"
            // (`isCreatingWorktree`) until it resolves.
            onCreateWorktree: { branchName in
                guard let project = currentProject else { return }
                isBranchChipPickerOpen = false
                composerStore.createWorktree(named: branchName, in: project)
            }
        )
    }

    // MARK: - Footer: + New template…

    @ViewBuilder
    private var newTemplateRow: some View {
        if isAddingTemplate {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .frame(width: 16)
                TextField("Template name", text: $newTemplateName)
                    .font(.system(size: rowFontSize, weight: .medium))
                    .textFieldStyle(.plain)
                    .focused($newTemplateNameFocused)
                    .onSubmit { commitNewTemplate() }
                    .onExitCommand { cancelNewTemplate() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .onAppear {
                DispatchQueue.main.async { newTemplateNameFocused = true }
            }
        } else {
            Button {
                newTemplateName = ""
                isAddingTemplate = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .frame(width: 16)
                    Text("New template…")
                        .font(.system(size: rowFontSize, weight: .medium))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private func commitNewTemplate() {
        guard isAddingTemplate else { return }
        isAddingTemplate = false
        let trimmed = newTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
        newTemplateName = ""
        guard !trimmed.isEmpty else { return }
        let template = store.addTemplate(AgentTemplate(name: trimmed, kind: .custom))
        newTemplateToEdit = template
    }

    private func cancelNewTemplate() {
        isAddingTemplate = false
        newTemplateName = ""
    }

    // MARK: - Template context menu actions (S4, ported from
    // `TemplatePickerView` — that view now has zero callers, so everything
    // it owned, most seriously `store.removeTemplate`'s only UI caller, was
    // unreachable).

    /// Preset files live at `~/.ghostties/presets/<slug>.md`. Duplicated
    /// from `TemplatePickerView.openPresetInEditor` (that method is
    /// `private` to a different file, not reachable from here).
    private func openPresetInEditor(_ template: AgentTemplate) {
        let filename = template.name.lowercased().replacingOccurrences(of: " ", with: "-") + ".md"
        let path = (PresetLoader.presetsDirectoryPath as NSString).appendingPathComponent(filename)

        // Validate the resolved path stays within the presets directory.
        let resolvedPath = (path as NSString).standardizingPath
        let presetsDir = (PresetLoader.presetsDirectoryPath as NSString).standardizingPath
        guard resolvedPath.hasPrefix(presetsDir + "/") else { return }

        let url = URL(fileURLWithPath: resolvedPath)
        if FileManager.default.fileExists(atPath: resolvedPath) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Actions

    /// Clamp `selectedIndex` into range rather than nil-ing out — the old
    /// logic only reset when the index was exactly 0, so a stale index from
    /// a shrunk list (e.g. RECENT reordering after a commit) survived a
    /// query or project change untouched. Shared by the `query` and
    /// `selectedProjectId` triggers (N5) — either can change
    /// `flattenedOptions.count`.
    private func clampSelectedIndex() {
        let options = flattenedOptions
        guard !options.isEmpty else {
            selectedIndex = nil
            return
        }
        if let current = selectedIndex {
            if current >= UInt(options.count) {
                selectedIndex = UInt(options.count - 1)
            }
        } else {
            selectedIndex = bestSelectionIndex(in: options)
        }
    }

    /// D1: query-driven reselection, distinct from `clampSelectedIndex`
    /// above. `clampSelectedIndex` deliberately PRESERVES a still-valid
    /// index (N5's fix, for the `selectedProjectId` trigger, where the list
    /// changing shape shouldn't discard a user's manual arrow selection).
    /// A query keystroke is different: every keystroke re-ranks the whole
    /// list, so the top match needs to be reselected live even when the old
    /// index is still in bounds — that's the D1 bug itself (a stale index-0
    /// silently stayed valid while the query changed underneath it).
    private func reselectBestMatch() {
        let options = flattenedOptions
        guard !options.isEmpty else {
            selectedIndex = nil
            return
        }
        selectedIndex = bestSelectionIndex(in: options)
    }

    private func commit(template: AgentTemplate) {
        // S1: reset the stale index up front. `recordRecent` (inside the
        // store's precommit) reorders RECENT, which would otherwise leave
        // `selectedIndex` pointing at the wrong row if the composer stays
        // open on a failed commit (S6). Synchronous and load-bearing (N1):
        // it is what makes a double Return a no-op if both `.onSubmit` and
        // `.onKeyPress` ever fire on macOS 14+. Scoped to what's actually
        // reachable via Return: every `ComposerOption.action` in
        // `flattenedOptions` — this one and the search-result project row
        // (`makeOption(for project:)`) — nils `selectedIndex` FIRST for the
        // same reason. The trailing project dropdown and "+ Add project…"
        // are mouse-only Buttons outside `flattenedOptions`, so
        // `handle(.submit)` can never resolve `selectedOption` into them —
        // they don't need this guard, and `addProjectViaPanel` (on
        // `SessionComposerStore`) couldn't apply it anyway, having no
        // access to this view's `@State` (PR #132 review round 3 — a prior
        // draft of this comment claimed all four sites nil'd first; only
        // these two do).
        selectedIndex = nil

        // BLOCKER fix (command grammar slice 1): a resolved command project
        // must win over whatever `selectedProjectId` still reads, for EVERY
        // row that reaches `commit(template:)` — not just the synthesized
        // Run row. Before this, `precommit` resolved the write target from
        // `composerStore.selectedProjectId`, which typing a command never
        // changes (see `currentProject`), so a `.exactPrefix` template row
        // auto-selected under a command like `ghostties orchestrator` would
        // commit into whatever project the dropdown was still showing.
        // Setting `selectedProjectId` directly here, rather than via
        // `selectProject(_:)`, is deliberate: `selectProject` also clears
        // `searchText`, which would blank the command mid-commit.
        composerStore.selectedProjectId = SessionComposerCommandParser.resolveCommitProjectId(
            commandProjectId: commandProject?.id,
            selectedProjectId: composerStore.selectedProjectId
        )

        // B3: same precedence for the branch segment — a typed branch
        // (`> main > cco`) wins over whatever the branch chip's picker
        // currently has selected, for every row that reaches this
        // function. `precommit` reads `selectedWorktreePath` directly (it
        // has no view-layer access to resolve `typedWorktreePath` itself —
        // that lookup needs `composerStore.worktrees`, which this view
        // already has via `@ObservedObject`).
        composerStore.selectedWorktreePath = SessionComposerCommandParser.resolveCommitWorktreePath(
            typedWorktreePath: typedWorktreePath,
            selectedWorktreePath: composerStore.selectedWorktreePath
        )

        // F1 (Phase 3 review): capture the target project BEFORE precommit
        // runs — `.locked`'s enforced project can differ from whatever
        // `selectedProjectId` reads after `precommit` records the recent
        // pair and closes the store, and this notification exists
        // specifically to auto-expand the project the session actually
        // landed in.
        let targetProject = currentProject

        // N1: `precommit` is synchronous — it validates, records the
        // recent pair, and dispatches the actual session spawn from a
        // detached `Task` it does not wait on. Dismissing here, on that
        // synchronous result, is what keeps the popover from lingering
        // over the newly-created session while `createQuickSession`
        // resolves the binary path (a 3s-timeout shell-out).
        let success = composerStore.precommit(template: template, coordinator: coordinator, workspaceStore: store)
        if success {
            isPresented = false
            // F1: without this, a session created via the composer into a
            // collapsed project spawns with no visible sidebar row — see
            // `WorkspaceLayout.workspaceDidCreateSessionInProject`.
            if let targetProject {
                NotificationCenter.default.post(
                    name: .workspaceDidCreateSessionInProject,
                    object: coordinator.containerView?.window,
                    userInfo: ["projectId": targetProject.id]
                )
            }
        } else {
            // N4: precommit failed — the composer stays open with
            // `writeError` showing. `selectedIndex` was just nil'd above,
            // so Return is dead until the user types or arrows; re-seed the
            // best match (D1) so Return works again immediately.
            selectedIndex = bestSelectionIndex(in: flattenedOptions)
        }
    }

    /// Return and ⌥+Return are identical: both start the session, which
    /// already reveals/focuses it (`SessionCoordinator.createSession` makes
    /// the new surface "the sole occupant of the terminal area"), then
    /// close the composer like any other commit. An earlier version of this
    /// file invented a "commit but keep composer open" meaning for ⌥+Return
    /// that contradicted the plan's own legend (`↵ start · ⌥↵ start +
    /// reveal · esc cancel`) — deleted, not kept as a fallback.
    private func handle(_ event: ComposerQueryField.KeyboardEvent) {
        switch event {
        case .exit:
            closeChipPickerOrDismiss()

        case .submit:
            selectedOption?.action()

        case .submitNoMatch:
            triggerNoMatchFeedback()

        case .backspaceAtStart:
            // A5: backspace at position 0 pops the chip back to editable
            // text — chips are not text.
            popChipToText()

        case .move(.up):
            if flattenedOptions.isEmpty { break }
            let current = selectedIndex ?? UInt(flattenedOptions.count)
            selectedIndex = (current == 0) ? UInt(flattenedOptions.count - 1) : current - 1

        case .move(.down):
            if flattenedOptions.isEmpty { break }
            let current = selectedIndex ?? UInt.max
            selectedIndex = (current >= UInt(flattenedOptions.count - 1)) ? 0 : current + 1

        // D5: left-arrow-focuses-chip is DEAD. `NSTextView` implements
        // `moveLeft:` unconditionally and no-ops at caret position 0 rather
        // than forwarding to `.onMoveCommand` — the prior version of this
        // handler asserted the opposite ("the field only forwards `.left`
        // when the caret is at true start") with no runtime evidence behind
        // it. Genuinely intercepting `moveLeft:` at position 0 needs an
        // `NSViewRepresentable` wrapper around the field editor (reading
        // its `selectedRange` directly) — out of scope for this pass, and a
        // `.leftArrow` `.keyboardShortcut` alternative (this file's usual
        // fallback for a `.onMoveCommand` gap) is worse than no route at
        // all: it would fire on EVERY left-arrow press, including mid-word,
        // and yank focus off the field. Removed rather than left asserted
        // but unverified. The chip stays reachable by mouse click; `isChipFocused`
        // (`.focused($isChipFocused)` on the chip's `Button`) is still wired
        // for whatever focus route the system provides (e.g. VoiceOver/Tab).
        // This pass adds no NEW keyboard route into it from inside the field.
        case .move:
            break
        }
    }

    // MARK: - Breadcrumb chip actions (Slice A)

    /// A2/A3: change the chip via the inline picker. The cascade rule
    /// (clear-on-change, no-op-on-repick) and the ⌘Z undo capture both live
    /// on `SessionComposerStore` — testable there without constructing this
    /// view. "Currently shown" (A6's single source of truth) is resolved
    /// through `SessionComposerCommandParser.resolveCommitProjectId` — the
    /// SAME precedence rule `currentProject` itself applies (a resolved
    /// command project wins over `selectedProjectId`) — rather than
    /// re-deriving it inline as `currentProject?.id`, so this call site is
    /// backed by the one place that rule has real unit coverage. The
    /// inert-test review finding (breadcrumb chip review) flagged that
    /// coverage as call-site-only and unreachable from a store-level test;
    /// routing through the shared, tested function is what's actually
    /// achievable without a SwiftUI view-test harness this repo doesn't
    /// have — see `resolveCommitProjectId`'s own doc comment for the same
    /// honest limitation.
    private func changeProjectChip(to project: Project) {
        isProjectChipPickerOpen = false
        let currentlyShownId = SessionComposerCommandParser.resolveCommitProjectId(
            commandProjectId: commandProject?.id,
            selectedProjectId: composerStore.selectedProjectId
        )
        composerStore.changeProjectChip(to: project.id, currentlyShown: currentlyShownId)
    }

    /// A4: ⌘Z restores the segment(s) the most recent chip change cleared,
    /// as one step.
    private func undoChipCascade() {
        composerStore.undoProjectChipChange()
    }

    /// B3: change the branch chip via the inline picker. Same
    /// currently-shown resolution idiom as `changeProjectChip(to:)` above
    /// (typed wins over picked), routed through the shared, tested
    /// `resolveCommitWorktreePath` rather than re-deriving the precedence
    /// inline.
    private func changeBranchChip(to worktreePath: String) {
        isBranchChipPickerOpen = false
        let currentlyShown = SessionComposerCommandParser.resolveCommitWorktreePath(
            typedWorktreePath: typedWorktreePath,
            selectedWorktreePath: composerStore.selectedWorktreePath
        )
        composerStore.changeBranchChip(to: worktreePath, currentlyShown: currentlyShown)
    }

    /// A5: backspace at position 0 (field empty) pops the chip back into
    /// raw editable text. Guarded on `commandParse.projectId == nil` rather
    /// than `commandProject == nil` (D3 fix): a genuine ≥2-token command
    /// always has SOME remainder text, so this event (field already empty)
    /// can never fire while one is live — but the sticky empty-remainder
    /// state (`stickyChipProjectId`) DOES leave the field empty with
    /// `commandProject` non-nil, and that state must stay poppable so
    /// backspacing all the way through a mid-typed command's project name
    /// still works, rather than becoming a second dead end next to the one
    /// this function exists to fix.
    ///
    /// B3: the BRANCH chip pops first, if one is showing and it's a
    /// PICKER pick rather than a typed command (`commandParse.branchToken
    /// == nil`) — a typed branch is text already, nothing to "pop" back
    /// to; only a picker-selected `selectedWorktreePath` needs clearing.
    /// Otherwise backspace-at-start would pop the PROJECT chip while a
    /// picked branch chip was still showing, silently discarding the
    /// branch pick along with it and reading as the wrong chip disappearing.
    private func popChipToText() {
        if commandParse.branchToken == nil, composerStore.selectedWorktreePath != nil {
            composerStore.clearBranchChip()
            return
        }
        guard !isProjectLocked, commandParse.projectId == nil, let project = currentProject else { return }
        composerStore.popChipToText(projectName: project.name)
    }

    /// A5: Esc closes the inline picker without closing the composer when
    /// it's open; otherwise it's an ordinary composer dismiss.
    ///
    /// D6 fix: guarded against a same-turn double-fire, matching every other
    /// double-fire site in this file (`isHandlingNoMatchFeedback` above is
    /// the same pattern) — this one was the odd one out, unguarded. Reached
    /// from TWO `.onExitCommand` sites (`queryRow`'s and `ComposerQueryField`'s
    /// own `.exit` event) — if both fired in the same turn, the first call
    /// closes the picker and the second, unguarded, would close the whole
    /// composer instead of leaving it open with the picker now dismissed.
    ///
    /// B3: widened to check BOTH pickers — `isProjectChipPickerOpen` alone
    /// would let Esc close the whole composer while the BRANCH picker was
    /// open instead of just dismissing that picker.
    private func closeChipPickerOrDismiss() {
        guard !isHandlingExitCommand else { return }
        isHandlingExitCommand = true
        DispatchQueue.main.async { isHandlingExitCommand = false }

        if isBranchChipPickerOpen {
            isBranchChipPickerOpen = false
        } else if isProjectChipPickerOpen {
            isProjectChipPickerOpen = false
        } else {
            isPresented = false
        }
    }

    /// Enter with no row highlighted (empty results, or a dead-key press
    /// before selection is seeded) used to be a silent no-op. 3 cycles /
    /// 6pt over 0.25s via `ShakeEffect`; under reduce-motion, a 400ms red
    /// border pulse instead.
    private func triggerNoMatchFeedback() {
        guard !isHandlingNoMatchFeedback else { return }
        isHandlingNoMatchFeedback = true
        DispatchQueue.main.async { isHandlingNoMatchFeedback = false }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            showNoMatchBorder = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                showNoMatchBorder = false
            }
        } else {
            withAnimation(.linear(duration: 0.25)) {
                shakeTrigger += 1
            }
        }
    }
}

/// Standard sine-wave shake: `amount` pt of lateral travel, `shakesPerUnit`
/// full cycles per unit of `animatableData`. Driving `animatableData` by +1
/// with a 0.25s linear animation and `shakesPerUnit = 3` produces exactly
/// 3 cycles / 6pt / 0.25s (the no-match Enter spec) — SwiftUI interpolates
/// `animatableData` continuously across the animation's duration, and one
/// unit of `animatableData` sweeps the sine through `shakesPerUnit` full
/// periods (argument spans `2π · shakesPerUnit`).
private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    var amount: CGFloat = 6
    var shakesPerUnit: CGFloat = 3

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: amount * sin(animatableData * 2 * .pi * shakesPerUnit),
            y: 0
        ))
    }
}

// MARK: - ComposerOption

/// Analog of `CommandOption` with an INJECTABLE id (derived from the
/// underlying template/project id), fixing the churn `CommandOption.id =
/// UUID()` causes on every keystroke recompute.
///
/// `template`/`templateGroup` are non-nil only for options backed by a
/// template — `ComposerRow` uses them to decide whether (and which)
/// context menu to attach; project options and other rows carry no menu.
struct ComposerOption: Identifiable, Hashable {
    let id: UUID
    let title: String
    let subtitle: String?
    let leadingIcon: String?
    let action: () -> Void
    let template: AgentTemplate?
    let templateGroup: SessionTemplateResolver.Group?

    init(
        id: UUID,
        title: String,
        subtitle: String?,
        leadingIcon: String?,
        action: @escaping () -> Void,
        template: AgentTemplate? = nil,
        templateGroup: SessionTemplateResolver.Group? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.leadingIcon = leadingIcon
        self.action = action
        self.template = template
        self.templateGroup = templateGroup
    }

    static func == (lhs: ComposerOption, rhs: ComposerOption) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Query field

/// The composer's search field. Forked from `CommandPaletteQuery` with two
/// changes: the focus-loss auto-dismiss (`onChange(of: isTextFieldFocused)`
/// calling `.exit`) is REMOVED — the project dropdown and
/// `+ Add project…`'s `NSOpenPanel` both take first responder, and either
/// would otherwise kill the composer mid-interaction (ship gate 2) — and
/// Return is wired through BOTH `.onSubmit` and `Backport.onKeyPress`:
/// `Backport.onKeyPress` is a documented no-op below macOS 14
/// (`Helpers/Backport.swift:53-68`) and the app's deployment target is
/// 13.0, so `.onSubmit` alone is what makes Return work pre-14. If both
/// fire on 14+, the invariant that makes a double-fire a no-op instead of
/// a double-commit is scoped to `handle(.submit)`'s own reach: every
/// `ComposerOption.action` in `flattenedOptions` — `commit(template:)`
/// (N1) and the search-result project row's action — nils `selectedIndex`
/// SYNCHRONOUSLY first, so the second fire's `selectedOption` resolves to
/// `nil` and its handler becomes a no-op rather than acting on a list the
/// first fire already swapped out from under it. The trailing project
/// dropdown and "+ Add project…" don't need this: they're mouse-only
/// Buttons that `handle(.submit)` never reaches, and `addProjectViaPanel`
/// (on `SessionComposerStore`) has no access to this `@State` regardless
/// (PR #132 review round 3) — this repo cannot verify from source alone
/// whether `.onSubmit`/`.onKeyPress` actually both fire, only that a
/// double-fire is harmless if they do.
struct ComposerQueryField: View {
    @Binding var query: String
    var fontSize: CGFloat
    @Binding var focusTrigger: Bool
    /// Whether there's a highlighted row to commit. When false, Return
    /// fires `.submitNoMatch` (shake/border feedback) instead of `.submit`
    /// — no longer a silent no-op (nit: `.onKeyPress` used to return
    /// `.handled` unconditionally, swallowing Return against an empty
    /// list).
    var hasSelection: Bool
    /// D6: whether the breadcrumb chip's inline picker is currently open.
    /// While `true`, this field's own ↑/↓/Return handlers go quiet — the
    /// picker (`ProjectDropdownView.keyboardCaptureLayer`) becomes the only
    /// live ↑/↓/Return handler on screen. Clicking the chip to open the
    /// picker does NOT move first responder away from this field (deliberate
    /// — see this type's own doc comment on why focus-loss auto-dismiss was
    /// removed), so without this gate the field's hidden ↑/↓ `Button`s and
    /// `.onSubmit` kept responding: Return committed whatever TEMPLATE row
    /// was highlighted and dismissed the whole composer instead of choosing
    /// a project from the now-open picker.
    var isPickerOpen: Bool
    var placeholder: String
    var onEvent: ((KeyboardEvent) -> Void)?
    @FocusState private var isTextFieldFocused: Bool

    enum KeyboardEvent {
        case exit
        case submit
        /// Return pressed with no row highlighted (empty results list) —
        /// distinct from `.submit` so the parent can play the no-match
        /// shake/border feedback instead of silently swallowing the key.
        case submitNoMatch
        case move(MoveCommandDirection)
        /// Backspace/delete pressed while the field is already empty — the
        /// breadcrumb chip's pop-to-text gesture (A5). There is nothing to
        /// delete in the field itself at that point, so this can't collide
        /// with ordinary text deletion.
        case backspaceAtStart
    }

    var body: some View {
        ZStack {
            Group {
                // FA fix (round-2 review): these four are only mounted while
                // `!isPickerOpen`, not merely guarded internally. The prior
                // shape kept all four `Button`s (and their
                // `.keyboardShortcut` registrations) installed in the view
                // hierarchy at all times, gating only the ACTION body —
                // `ProjectDropdownView.keyboardCaptureLayer` then registered
                // an identical second ↑/↓/Return pair in the same window
                // while the picker was open. Two live registrations for the
                // same shortcut is exactly the kind of ambiguity SwiftUI
                // gives no resolution guarantee for; removing these from the
                // hierarchy entirely (rather than no-oping their action)
                // means the picker's handlers are the ONLY ones installed
                // while it's open, by construction, not by hope.
                if !isPickerOpen {
                    Button { onEvent?(.move(.up)) } label: { Color.clear }
                        .buttonStyle(PlainButtonStyle())
                        .keyboardShortcut(.upArrow, modifiers: [])
                    Button { onEvent?(.move(.down)) } label: { Color.clear }
                        .buttonStyle(PlainButtonStyle())
                        .keyboardShortcut(.downArrow, modifiers: [])

                    Button { onEvent?(.move(.up)) } label: { Color.clear }
                        .buttonStyle(PlainButtonStyle())
                        .keyboardShortcut(.init("p"), modifiers: [.control])
                    Button { onEvent?(.move(.down)) } label: { Color.clear }
                        .buttonStyle(PlainButtonStyle())
                        .keyboardShortcut(.init("n"), modifiers: [.control])
                }
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)

            TextField(placeholder, text: $query)
                .padding(.vertical, 6)
                // R6 (Phase 3 review round 2): `.light` isn't an allowed
                // DESIGN.md weight (§3: `.regular`/`.medium`, `.semibold`
                // sparingly), and DESIGN.md's own new "centered modal" row
                // documents this field as `.regular` — reconciling to that.
                .font(.system(size: fontSize, weight: .regular))
                .textFieldStyle(.plain)
                // FB (round-2 review): this is a command field, not prose —
                // autocorrection has no business firing on a project name or
                // shell flag. NOTE this does NOT verifiably suppress macOS's
                // separate "smart quotes and dashes" substitution (a
                // distinct AppKit feature from spelling autocorrection, on
                // by default, with no exposed SwiftUI/AppKit toggle scoped
                // to a single `NSTextField` short of reaching into its field
                // editor mid-edit) — the actual guarantee against a
                // substituted curly quote breaking the command grammar is
                // `SessionComposerCommandParser.tokenize`/`splitOnFirstToken`
                // now treating U+201C/U+201D as quote characters alongside
                // `"`, which holds regardless of whether substitution fires.
                .autocorrectionDisabled(true)
                .focused($isTextFieldFocused)
                .onExitCommand { onEvent?(.exit) }
                .onMoveCommand { guard !isPickerOpen else { return }; onEvent?(.move($0)) }
                // B1: `.onSubmit` is the ONLY Return handler that works
                // below macOS 14 — the app's deployment target is 13.0.
                // D6: quiet while the picker is open (see `isPickerOpen`'s
                // doc comment) — Return there belongs to the picker.
                .onSubmit {
                    guard !isPickerOpen else { return }
                    guard hasSelection else {
                        onEvent?(.submitNoMatch)
                        return
                    }
                    onEvent?(.submit)
                }
                .backport.onKeyPress(.return) { _ in
                    guard !isPickerOpen else { return .ignored }
                    guard hasSelection else {
                        onEvent?(.submitNoMatch)
                        return .handled
                    }
                    onEvent?(.submit)
                    return .handled
                }
                // A5: below macOS 14 this is a documented no-op
                // (`Backport.onKeyPress`) — the chip-pop gesture degrades
                // gracefully to "clear the field yourself" there, same as
                // every other Backport-only convenience in this file.
                .backport.onKeyPress(.delete) { _ in
                    guard query.isEmpty else { return .ignored }
                    onEvent?(.backspaceAtStart)
                    return .handled
                }
                .onAppear {
                    DispatchQueue.main.async {
                        isTextFieldFocused = true
                    }
                }
                .onChange(of: focusTrigger) { triggered in
                    // S7: consumes `SessionComposerStore.focusSearchFieldTrigger`
                    // — previously set on re-open but read nowhere, so the
                    // "opening while already open focuses the field" parity
                    // the doc comment claimed was a complete no-op.
                    guard triggered else { return }
                    isTextFieldFocused = true
                    focusTrigger = false
                }
        }
    }
}

// MARK: - Results table

/// Forked from `CommandTable`, with two changes: it renders named sections
/// (RECENT / TEMPLATES / PROJECTS — `CommandPaletteView` has no section
/// grouping at all) and it uses a plain `VStack`, never `LazyVStack` — this
/// repo has a known bug class where `LazyVStack` never re-invokes
/// `ForEach`'s content closure when an element changes but its `id` does
/// not, which froze sidebar rows at first construction (PR #121).
private struct ComposerResultsTable: View {
    var sections: [(title: String?, options: [ComposerOption])]
    var query: String
    @Binding var selectedIndex: UInt?
    @Binding var hoveredOptionID: UUID?
    var rowFontSize: CGFloat
    var subtitleFontSize: CGFloat
    var sectionHeaderFontSize: CGFloat
    var rowVerticalPadding: CGFloat
    var onEditTemplate: (AgentTemplate) -> Void
    var onDuplicateTemplate: (AgentTemplate) -> Void
    var onDuplicateAndEditTemplate: (AgentTemplate) -> Void
    var onEditPresetFile: (AgentTemplate) -> Void
    var onRequestDeleteTemplate: (AgentTemplate) -> Void
    var action: (ComposerOption) -> Void

    private var flattened: [ComposerOption] {
        sections.flatMap { $0.options }
    }

    var body: some View {
        if flattened.isEmpty {
            Text("No matches")
                .font(.system(size: rowFontSize))
                .foregroundStyle(.secondary)
                .padding(12)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                            if !section.options.isEmpty {
                                if let title = section.title {
                                    Text(title)
                                        .font(.system(size: sectionHeaderFontSize, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 4)
                                        .padding(.top, 6)
                                        .padding(.bottom, 2)
                                }

                                ForEach(section.options) { option in
                                    ComposerRow(
                                        option: option,
                                        query: query,
                                        isSelected: isSelected(option),
                                        hoveredID: $hoveredOptionID,
                                        titleFontSize: rowFontSize,
                                        subtitleFontSize: subtitleFontSize,
                                        verticalPadding: rowVerticalPadding,
                                        onEditTemplate: onEditTemplate,
                                        onDuplicateTemplate: onDuplicateTemplate,
                                        onDuplicateAndEditTemplate: onDuplicateAndEditTemplate,
                                        onEditPresetFile: onEditPresetFile,
                                        onRequestDeleteTemplate: onRequestDeleteTemplate
                                    ) {
                                        action(option)
                                    }
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 220)
                .onChange(of: selectedIndex) { _ in
                    guard let selectedIndex, selectedIndex < flattened.count else { return }
                    proxy.scrollTo(flattened[Int(selectedIndex)].id)
                }
            }
        }
    }

    private func isSelected(_ option: ComposerOption) -> Bool {
        guard let selectedIndex, let index = flattened.firstIndex(where: { $0.id == option.id }) else { return false }
        return Int(selectedIndex) == index || (Int(selectedIndex) >= flattened.count && index == flattened.count - 1)
    }
}

/// Forked from `CommandRow`, resized to DESIGN.md's 11pt sidebar scale.
/// Reuses `String.matchedIndices(for:)` (`CommandPalette.swift`,
/// module-scope) for highlighting — redeclaring it would be a compile
/// error.
///
/// S4: carries a `.contextMenu`, ported from
/// `TemplatePickerView.templateRow` (`TemplatePickerView.swift:186-217`),
/// for template-backed rows only (`option.template != nil`) — project rows
/// get no menu. Perf note (`project_perf-contextmenu-render-cost.md`):
/// per-row `.contextMenu` in a long-lived sidebar list is a known
/// bottleneck, but this is a transient popover showing ~10 rows, so it's
/// acceptable; no `.popover`/`.draggable` is added per row alongside it.
private struct ComposerRow: View {
    let option: ComposerOption
    var query: String
    var isSelected: Bool
    @Binding var hoveredID: UUID?
    var titleFontSize: CGFloat
    var subtitleFontSize: CGFloat
    var verticalPadding: CGFloat
    var onEditTemplate: (AgentTemplate) -> Void
    var onDuplicateTemplate: (AgentTemplate) -> Void
    var onDuplicateAndEditTemplate: (AgentTemplate) -> Void
    var onEditPresetFile: (AgentTemplate) -> Void
    var onRequestDeleteTemplate: (AgentTemplate) -> Void
    var action: () -> Void

    private var highlightedTitle: Text {
        guard !query.isEmpty, let indices = option.title.matchedIndices(for: query) else {
            return Text(option.title).font(.system(size: titleFontSize, weight: .medium))
        }

        var attributed = AttributedString(option.title)
        attributed[attributed.startIndex...].font = .system(size: titleFontSize, weight: .medium)

        for idx in indices {
            let offset = option.title.distance(from: option.title.startIndex, to: idx)
            let attrStart = attributed.index(attributed.startIndex, offsetByCharacters: offset)
            let attrEnd = attributed.index(attrStart, offsetByCharacters: 1)
            attributed[attrStart..<attrEnd].font = .system(size: titleFontSize, weight: .bold)
            attributed[attrStart..<attrEnd].foregroundColor = Color.accentColor
        }

        return Text(attributed)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = option.leadingIcon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }

                VStack(alignment: .leading, spacing: 1) {
                    highlightedTitle

                    if let subtitle = option.subtitle {
                        Text(subtitle)
                            .font(.system(size: subtitleFontSize))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, verticalPadding)
            .contentShape(Rectangle())
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.2)
                    : (hoveredID == option.id ? Color.secondary.opacity(0.2) : Color.clear)
            )
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredID = hovering ? option.id : nil
        }
        .contextMenu {
            templateContextMenu
        }
    }

    /// Replicates `TemplatePickerView.templateRow`'s context menu exactly:
    /// presets get "Duplicate and Edit..." (+ "Edit Preset File..." when a
    /// description exists), built-ins get "Duplicate and Edit..." only,
    /// user templates get Edit… / Duplicate / Delete. Renders nothing for
    /// non-template rows (project options).
    @ViewBuilder
    private var templateContextMenu: some View {
        if let template = option.template, let group = option.templateGroup {
            if group == .preset {
                Button("Duplicate and Edit...") { onDuplicateAndEditTemplate(template) }
                if template.templateDescription != nil {
                    Button("Edit Preset File...") { onEditPresetFile(template) }
                }
            } else if template.isDefault {
                Button("Duplicate and Edit...") { onDuplicateAndEditTemplate(template) }
            } else {
                Button("Edit...") { onEditTemplate(template) }
                Button("Duplicate") { onDuplicateTemplate(template) }
                Divider()
                Button("Delete", role: .destructive) { onRequestDeleteTemplate(template) }
            }
        }
    }
}

// MARK: - Project dropdown

/// The project chip's picker list (formerly the trailing `▾` control's
/// dropdown). Three-tier ordering, no visible headers: cascade pick
/// (pre-selected) -> recently-used most-recent-first -> everything else
/// alphabetically (locked decision). `+ Add project…` is always the last
/// row.
///
/// A2 (breadcrumb spec): presented as an inline expansion INSIDE the
/// composer card (`SessionComposerPalette.inlineProjectPicker`), never a
/// `.popover` — this view used to be nested inside the composer's own
/// `.popover`, on the known-fragile "child popover taking key can dismiss
/// the parent" list and never verified. Reused verbatim here; only the
/// presentation at the call site changed.
///
/// `selectedProjectId` is the CALLER's single source of truth for "what's
/// currently shown" (A6) — the call site passes `currentProject?.id`, not
/// a raw stored id, so the selected-row weight below and the chip's own
/// label can never disagree about which project is current.
private struct ProjectDropdownView: View {
    let selectedProjectId: UUID?
    var onSelect: (Project) -> Void
    var onAddProject: () -> Void

    @EnvironmentObject private var store: WorkspaceStore

    /// D6: which row (0..<`orderedProjects.count` for project rows,
    /// `orderedProjects.count` for the trailing "+ Add project…" row) is
    /// keyboard-highlighted. Seeded to the currently-shown project on
    /// appear — this view is only ever mounted while the picker is open, so
    /// `onAppear` firing once per open is exactly the right lifetime.
    @State private var highlightedIndex: Int = 0

    // N6: this view has no search field of its own — the main composer
    // field does the filtering (locked decision) — so a local `query`
    // and a `filteredProjects` indirection over it were dead: always
    // equal to `orderedProjects`. Removed rather than kept as unused
    // scaffolding.
    private var orderedProjects: [Project] {
        let recentIds = SessionComposerStore.shared.recentProjectIds
        return SessionComposerProjectOrdering.order(
            projects: store.projects,
            cascadePick: selectedProjectId,
            recentProjectIds: recentIds
        )
    }

    /// Every navigable row: project rows plus the trailing "+ Add project…"
    /// row.
    private var rowCount: Int { orderedProjects.count + 1 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(orderedProjects.enumerated()), id: \.element.id) { index, project in
                    Button {
                        onSelect(project)
                    } label: {
                        HStack(spacing: 6) {
                            Text(project.name)
                                .font(.system(size: 12, weight: project.id == selectedProjectId ? .semibold : .regular))
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                        // F9 (nit, round-2 review): reuses the named token
                        // rather than re-inlining the exact expression it
                        // was carved out of.
                        .background(index == highlightedIndex ? WorkspaceLayout.composerChipBackground : Color.clear)
                    }
                    .buttonStyle(.plain)
                    // A11y gap (round-2 review): the keyboard highlight was
                    // background-color only, with no equivalent for
                    // VoiceOver — it saw an ordinary row, not "currently
                    // highlighted".
                    .accessibilityAddTraits(index == highlightedIndex ? .isSelected : [])
                }

                Divider().padding(.horizontal, 8).padding(.vertical, 2)

                Button(action: onAddProject) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                            .frame(width: 14)
                        Text("Add project…")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .background(highlightedIndex == orderedProjects.count ? WorkspaceLayout.composerChipBackground : Color.clear)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(highlightedIndex == orderedProjects.count ? .isSelected : [])
            }
            .padding(6)
        }
        // A2: no fixed `sidebarWidth` frame anymore — inline, this fills
        // whatever width the composer card (`paletteWidth`) already gives
        // it instead of a width sized for the old standalone popover.
        // Pre-existing 240pt cap, not retuned as part of this pass.
        .frame(maxHeight: 240)
        .overlay(keyboardCaptureLayer)
        .onAppear {
            highlightedIndex = orderedProjects.firstIndex(where: { $0.id == selectedProjectId }) ?? 0
        }
    }

    /// D6 fix: while this view is on screen, ↑/↓/Return must move ITS OWN
    /// highlight and commit ITS OWN row — not the composer field's
    /// template list. `SessionComposerPalette.ComposerQueryField.isPickerOpen`
    /// removes the field's equivalent hidden `Button`s from the hierarchy
    /// entirely while the picker is open (FA fix, round-2 review — not
    /// merely no-oping their action, which left a second live
    /// `.keyboardShortcut` registration for the same keys installed
    /// alongside these), so these ARE the only live ↑/↓/Return handlers
    /// while the picker is open, by construction. Same hidden-`Button` +
    /// `.keyboardShortcut` pattern `ComposerQueryField` already uses (works
    /// down to macOS 13, unlike `Backport.onKeyPress`).
    private var keyboardCaptureLayer: some View {
        Group {
            Button {
                highlightedIndex = (highlightedIndex - 1 + rowCount) % rowCount
            } label: { Color.clear }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut(.upArrow, modifiers: [])

            Button {
                highlightedIndex = (highlightedIndex + 1) % rowCount
            } label: { Color.clear }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut(.downArrow, modifiers: [])

            Button {
                commitHighlighted()
            } label: { Color.clear }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut(.return, modifiers: [])
        }
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func commitHighlighted() {
        if highlightedIndex < orderedProjects.count {
            onSelect(orderedProjects[highlightedIndex])
        } else {
            onAddProject()
        }
    }
}

// MARK: - Branch chip picker (Slice B, B3)

/// The branch chip's inline picker, modeled on `ProjectDropdownView` —
/// presented as an expansion INSIDE the card, never a `.popover` (see that
/// type's doc comment for why a nested popover is exactly what Slice A
/// deleted).
///
/// Row order, per the spec: `Default (<current branch>)` first (clears the
/// override); then existing worktrees (path shown secondary); then, under
/// a divider, branches with no worktree yet — a **create** action (B4),
/// labeled "+ worktree for "<branch>"" since the branch already exists;
/// then a "New branch name…" field whose "+ new branch + worktree "<name>""
/// row only appears once the typed name is genuinely novel (matches
/// nothing already offered above) — creation is explicit only, never an
/// implicit side effect of typing. Sean's stated reason for keeping the
/// no-worktree-yet group at all: discoverability — nobody should have to
/// recall a branch name.
private struct WorktreeDropdownView: View {
    let worktrees: [GitWorktreeEnumerator.Worktree]
    let branchesWithoutWorktree: [String]
    let currentBranchAtProjectRoot: String?
    let isRefreshing: Bool
    let selectedWorktreePath: String?
    var onSelectDefault: () -> Void
    var onSelectWorktree: (String) -> Void
    /// B4: fired by BOTH the (now-live) "no worktree yet" rows (an
    /// existing branch) and the "new branch name…" field's create row (a
    /// branch that doesn't exist yet). `SessionComposerStore.createWorktree`
    /// checks `GitWorktreeEnumerator.branchExists` itself to pick the right
    /// `git worktree add` form — this view doesn't need to know which case
    /// it is, only the name.
    var onCreateWorktree: (String) -> Void

    /// Keyboard-highlighted row, 0-based across ONLY the navigable rows:
    /// the Default row, then existing worktrees, in that order. The "no
    /// worktree yet" rows and the new-branch field are mouse/field-only —
    /// same reasoning `ProjectDropdownView` applies to its own trailing
    /// "+ Add project…" row, just with that group excluded entirely rather
    /// than included as a navigable target.
    @State private var highlightedIndex: Int = 0

    /// The typed candidate for a brand-new branch — a dedicated field
    /// rather than reusing the composer's own search field, which stays
    /// live (filtering templates) the whole time this picker is open.
    @State private var newBranchNameField: String = ""

    private var rowCount: Int { 1 + worktrees.count }

    private var trimmedNewBranchName: String {
        newBranchNameField.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the typed name is genuinely new — matches nothing already
    /// offered above. Gates the create row so typing never implicitly
    /// creates anything, and so re-typing an already-offered name doesn't
    /// duplicate a row that already exists above it.
    private var newBranchNameIsNovel: Bool {
        let name = trimmedNewBranchName
        guard !name.isEmpty else { return false }
        if worktrees.contains(where: { $0.branch == name }) { return false }
        if branchesWithoutWorktree.contains(name) { return false }
        if name == currentBranchAtProjectRoot { return false }
        return true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                defaultRow

                ForEach(Array(worktrees.enumerated()), id: \.element.path) { index, worktree in
                    worktreeRow(worktree, index: index + 1)
                }

                if !branchesWithoutWorktree.isEmpty {
                    Divider().padding(.horizontal, 8).padding(.vertical, 2)

                    ForEach(branchesWithoutWorktree, id: \.self) { branch in
                        noWorktreeRow(branch)
                    }
                }

                if isRefreshing {
                    Text("Refreshing…")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                }

                Divider().padding(.horizontal, 8).padding(.vertical, 2)
                newBranchField
                newBranchCreateRow
            }
            .padding(6)
        }
        // Same pre-existing 240pt cap `ProjectDropdownView` uses — not
        // retuned as part of this pass.
        .frame(maxHeight: 240)
        .overlay(keyboardCaptureLayer)
        .onAppear {
            highlightedIndex = worktrees.firstIndex(where: { $0.path == selectedWorktreePath }).map { $0 + 1 } ?? 0
        }
    }

    private var defaultRow: some View {
        let isSelected = selectedWorktreePath == nil
        let label = currentBranchAtProjectRoot.map { "Default (\($0))" } ?? "Default"
        return Button(action: onSelectDefault) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(highlightedIndex == 0 ? WorkspaceLayout.composerChipBackground : Color.clear)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(highlightedIndex == 0 ? .isSelected : [])
    }

    private func worktreeRow(_ worktree: GitWorktreeEnumerator.Worktree, index: Int) -> some View {
        let isSelected = worktree.path == selectedWorktreePath
        return Button {
            onSelectWorktree(worktree.path)
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(worktree.branch ?? (worktree.path as NSString).lastPathComponent)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    Text(worktree.path)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(index == highlightedIndex ? WorkspaceLayout.composerChipBackground : Color.clear)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(index == highlightedIndex ? .isSelected : [])
    }

    /// A branch that already exists but has no worktree yet — picking it
    /// is a CREATE action (`git worktree add <dir> <branch>`, the
    /// existing-branch form; `SessionComposerStore.createWorktree` decides
    /// the exact git invocation). Labeled by what it DOES, not by the
    /// absence it used to describe (B4) — "+ worktree for "<branch>""
    /// rather than the B3 placeholder "No worktree yet", since a plain
    /// label reading as a dead-end fact is exactly what a live control
    /// must not look like.
    private func noWorktreeRow(_ branch: String) -> some View {
        Button {
            onCreateWorktree(branch)
        } label: {
            HStack(spacing: 6) {
                Text(branch)
                    .font(.system(size: 12, weight: .regular))
                Spacer()
                Text("+ worktree for \"\(branch)\"")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create worktree for \(branch)")
    }

    /// The dedicated "type a brand-new branch name" field — deliberately
    /// separate from the composer's own search field, which stays live the
    /// whole time this picker is open (it filters templates, not branches).
    private var newBranchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 12)
            TextField("New branch name…", text: $newBranchNameField)
                .font(.system(size: 12))
                .textFieldStyle(.plain)
                .onSubmit {
                    guard newBranchNameIsNovel else { return }
                    onCreateWorktree(trimmedNewBranchName)
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    /// Only rendered once the typed name is genuinely novel
    /// (`newBranchNameIsNovel`) — creation is explicit only, never an
    /// implicit side effect of typing a name that happens to match
    /// nothing (yet).
    @ViewBuilder
    private var newBranchCreateRow: some View {
        if newBranchNameIsNovel {
            Button {
                onCreateWorktree(trimmedNewBranchName)
            } label: {
                HStack(spacing: 6) {
                    Text("+ new branch + worktree \"\(trimmedNewBranchName)\"")
                        .font(.system(size: 12, weight: .regular))
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create new branch and worktree \(trimmedNewBranchName)")
        }
    }

    /// Same hidden-`Button` + `.keyboardShortcut` pattern
    /// `ProjectDropdownView.keyboardCaptureLayer` uses — works down to
    /// macOS 13, unlike `Backport.onKeyPress`. `ComposerQueryField.isPickerOpen`
    /// (the OR of both pickers) is what removes the field's own equivalent
    /// handlers while this one is on screen, so these are the only live
    /// ↑/↓/Return handlers while THIS picker is open, by construction.
    private var keyboardCaptureLayer: some View {
        Group {
            Button {
                highlightedIndex = (highlightedIndex - 1 + rowCount) % rowCount
            } label: { Color.clear }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut(.upArrow, modifiers: [])

            Button {
                highlightedIndex = (highlightedIndex + 1) % rowCount
            } label: { Color.clear }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut(.downArrow, modifiers: [])

            Button {
                commitHighlighted()
            } label: { Color.clear }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut(.return, modifiers: [])
        }
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func commitHighlighted() {
        if highlightedIndex == 0 {
            onSelectDefault()
        } else {
            onSelectWorktree(worktrees[highlightedIndex - 1].path)
        }
    }
}

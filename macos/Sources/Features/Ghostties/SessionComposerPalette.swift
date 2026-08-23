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
/// - TYPE-FIRST entry (model A, replacing Slice A/B's breadcrumb chips —
///   see the note below). The field holds the literal typed string, always;
///   a RESOLUTION LINE beneath it (`resolutionLine`) shows what that string
///   currently resolves to — project, branch, and the template Return would
///   commit — and is the only mouse entry point into the project/branch
///   pickers.
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
///
/// Model A rebuild (replaces Slice A's project chip and Slice B's branch
/// chip): three review rounds on the chip-based field kept finding blockers
/// that all shared one root cause — the field's TEXT and the CHIPS were two
/// representations of one underlying string, and they could disagree (a
/// branch segment that became uneditable, a branch consumed with no chip
/// rendering it, a token displayed twice). This rebuild has exactly ONE
/// representation: whatever the user typed is what the `TextField` holds,
/// completely and always — nothing is ever consumed into a hidden,
/// non-editable prefix. The command grammar underneath
/// (`SessionComposerCommandParser`) and the store-layer cascade/undo
/// (`SessionComposerStore`) are UNCHANGED; only the chip rendering and the
/// field-text transform that fed it are gone.
struct SessionComposerPalette: View {
    @Binding var isPresented: Bool
    let request: SessionComposerRequest

    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var coordinator: SessionCoordinator
    @ObservedObject private var composerStore = SessionComposerStore.shared

    @State private var selectedIndex: UInt?
    @State private var hoveredOptionID: UUID?
    /// Whether the inline project picker is expanded — opened from the
    /// resolution line's project segment (model A rebuild; used to be the
    /// project chip's own click target, Slice A/A2). Drives an expansion
    /// INSIDE the card, not a `.popover`.
    @State private var isProjectPickerOpen = false
    /// Whether the inline branch picker is expanded — opened from the
    /// resolution line's branch segment (model A rebuild; used to be the
    /// branch chip's click target, Slice B/B3). Mutually exclusive with
    /// `isProjectPickerOpen` BY CONSTRUCTION — every site that flips one to
    /// `true` flips the other to `false` in the same statement — never
    /// merely "the two happen not to overlap in practice". A second live
    /// picker with its own capture layer would re-create exactly the
    /// ambiguity `ComposerQueryField.isPickerOpen` exists to remove (see
    /// that type's doc comment).
    @State private var isBranchPickerOpen = false
    /// Blocker 2 fix (Slice B review round 2): debounced re-refresh when a
    /// typed command resolves a DIFFERENT project than whatever the
    /// composer's worktree cache currently describes — see
    /// `SessionComposerStore.worktreesProjectId`'s doc comment. Cancelled
    /// and replaced on every `commandProject` change so a fast typist who
    /// flips through several project names before settling only ever fires
    /// the LAST one, never one refresh per keystroke.
    @State private var commandProjectRefreshTask: Task<Void, Never>?
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

    // MARK: - Branch segment eligibility (Slice B, B3 — chip deleted)

    /// Whether the project is a git repo at all — the resolution line's
    /// branch segment (and its picker) has no entry point unless the
    /// project genuinely IS one. Blocker 6 fix (Slice B review round 1):
    /// this used to be keyed off "did enumeration find anything to offer"
    /// (`!worktrees.isEmpty || !branchesWithoutWorktree.isEmpty`), but BOTH
    /// of those lists exclude cases that still mean "yes, this is a
    /// repo" — `worktrees` excludes the project's own root, and
    /// `branchesWithoutWorktree` excludes every already-claimed branch. A
    /// repo with exactly one branch checked out at its own root (a fresh
    /// project, the single most common first-run state) satisfies neither,
    /// so the segment never appeared and `+ new branch + worktree` was
    /// unreachable exactly where it matters most. `isGitRepo` is derived by
    /// the store from `GitWorktreeEnumerator.list(repoPath:)`'s UNFILTERED
    /// result (non-empty = a repo) — see `SessionComposerStore.refreshWorktrees`.
    private var isBranchSegmentEligible: Bool {
        composerStore.isGitRepo
    }

    /// A resolved TYPED branch (`> main > cco`) takes precedence over the
    /// picker's current pick, mirroring `currentProject`'s
    /// `commandProject`-before-`selectedProjectId` precedence exactly.
    ///
    /// Blocker 2 fix (Slice B review round 1): this collapses
    /// `typedBranchResolution`'s three non-"not typed" cases down to a
    /// plain optional for every call site EXCEPT `commit(template:)`, which
    /// needs to tell "nothing typed" apart from "typed but unresolvable" —
    /// see that function and `typedBranchResolution` below. Everywhere else
    /// (the picker's own "already shown" comparisons), both `.isDefaultBranch`
    /// and `.unresolved` collapse to "no override, defer to the picker" —
    /// which is safe there because those call sites never launch a session;
    /// only `commit(template:)` may, and it never reads this property.
    private var typedWorktreePath: String? {
        switch typedBranchResolution {
        // Blocker 2 fix (Slice B review round 2): `.pending` (the cache
        // doesn't describe the project being resolved for yet) collapses
        // to "no override" here for the same reason `.unresolved` already
        // does — this property never launches a session; only
        // `commit(template:)`'s STRICT resolver below does, and it reads
        // `typedBranchResolution` directly rather than through here.
        case .notTyped, .unresolved, .pending: return nil
        case .resolved(let path): return path
        case .isDefaultBranch: return nil
        }
    }

    /// Full three-state resolution of the typed branch token, if any —
    /// backs `commit(template:)`'s loud-failure path (blocker 2). See
    /// `SessionComposerCommandParser.TypedBranchResolution`'s doc comment
    /// for what each case means.
    private var typedBranchResolution: SessionComposerCommandParser.TypedBranchResolution {
        SessionComposerCommandParser.resolveTypedBranch(
            branchToken: commandParse.branchToken,
            worktrees: composerStore.worktrees,
            currentBranchAtProjectRoot: composerStore.currentBranchAtProjectRoot,
            // Blocker 2 fix (Slice B review round 2): only trust
            // `composerStore.worktrees` when it actually describes the
            // project the branch was typed against — see
            // `worktreesProjectId`'s doc comment and
            // `TypedBranchResolution.pending`'s.
            cachedProjectId: composerStore.worktreesProjectId,
            resolvingForProjectId: commandProject?.id
        )
    }

    /// What the branch chip displays: the typed branch token if a command
    /// resolved one, else the picker's current pick's branch name, else
    /// `nil` (no chip rendered — see `queryRow`).
    private var currentBranchLabel: String? {
        if let token = commandParse.branchToken { return token }
        guard let path = composerStore.selectedWorktreePath else { return nil }
        return composerStore.worktrees.first(where: { $0.path == path })?.branch ?? path
    }

    /// The query field's binding (model A rebuild — replaces the deleted
    /// `queryFieldText`/`resolvedFieldSplit` prefix-consuming transform).
    /// `get` returns `composerStore.searchText` VERBATIM — never a computed
    /// remainder — and `set` writes whatever the field sends back
    /// UNCHANGED: this is the property that makes acceptance criterion 1
    /// ("the field's contents are always exactly `searchText`") true. The
    /// only thing layered on top of the identity get/set is the same D4 side
    /// effect the old binding also carried: disarming a pending chip-undo
    /// the instant the user types by hand (`noteSearchTextEditedByTyping()`)
    /// — that's engine-layer undo bookkeeping the composer breadcrumb spec
    /// still requires (⌘Z restoring a cleared segment as one step), not a
    /// transform of the value itself.
    private var searchTextBinding: Binding<String> {
        Binding(
            get: { composerStore.searchText },
            set: { newValue in
                composerStore.noteSearchTextEditedByTyping()
                composerStore.searchText = newValue
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
                    isProjectPickerOpen = false
                    // Finding 14 fix (Slice B review round 1): this was
                    // missing here while `isProjectPickerOpen` right
                    // above it was reset — leaving the branch picker
                    // latched open across a dismiss/re-present cycle.
                    isBranchPickerOpen = false
                    // Blocker 2 fix (Slice B review round 2): a pending
                    // debounced refresh for whatever project was typed must
                    // not land after the composer has already closed.
                    commandProjectRefreshTask?.cancel()
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
                commandProjectRefreshTask?.cancel()
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

                // Blocker 2 fix (Slice B review round 2): the worktree cache
                // only ever refreshed on project-DROPDOWN changes, initial
                // open, and the branch picker opening — never when a TYPED
                // `<project> > <branch>` command resolved a DIFFERENT
                // project than whatever the composer opened on, so a typed
                // branch could match a STALE cache entry under the wrong
                // project (see `SessionComposerStore.worktreesProjectId`'s
                // doc comment for the exact bug). Debounced 300ms, not fired
                // per keystroke — `commandProject` only flips when the
                // project TOKEN match itself changes, but a fast typist can
                // still flip it more than once before settling.
                commandProjectRefreshTask?.cancel()
                if let project = commandProject {
                    commandProjectRefreshTask = Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        await composerStore.refreshWorktrees(for: project.rootPath, projectId: project.id)
                    }
                } else {
                    // SF-2 fix (Slice B review round 3): this `else` was
                    // missing entirely — a typed project name resolving,
                    // then being erased (one backspace past the match) left
                    // the cache STRANDED on whatever `commandProject` the
                    // debounce above had just refreshed it to.
                    // `currentProject` falls back to `selectedProjectId`'s
                    // project the instant `commandProject` goes `nil`, but
                    // nothing re-synced `worktrees`/`isGitRepo`/
                    // `worktreesProjectId` to match — the chip fell back to
                    // the dropdown's project while the branch picker kept
                    // showing the just-typed project's worktrees underneath
                    // it (BL-1's outcome again, reached without ever typing
                    // a branch). Immediate, not debounced: there's no
                    // fast-typing burst to coalesce here — this is the one
                    // moment the resolved project just disappeared.
                    if let project = currentProject {
                        Task { await composerStore.refreshWorktrees(for: project.rootPath, projectId: project.id) }
                    } else {
                        Task { await composerStore.refreshWorktrees(for: nil, projectId: nil) }
                    }
                }
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
                // `searchText` by typing (`searchTextBinding`'s setter calls
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

    // MARK: - Query row (type-first field + resolution line, model A rebuild)
    //
    // Replaces Slice A/B's project/branch chips with plain text entry: the
    // field holds `composerStore.searchText` verbatim (`searchTextBinding`),
    // and `resolutionLine` below it shows what that string resolves to,
    // segment by segment, as the ONLY mouse entry point left into the
    // project/branch pickers. Changing a segment still expands the SAME
    // inline pickers this replaced (`inlineProjectPicker`/`inlineBranchPicker`,
    // both unchanged) — never a `.popover`, for the same nested-popover
    // reason Slice A originally recorded (a child popover taking key can
    // dismiss the parent composer).

    private var queryRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            ComposerQueryField(
                query: searchTextBinding,
                fontSize: fieldFontSize,
                focusTrigger: $composerStore.focusSearchFieldTrigger,
                hasSelection: selectedOption != nil,
                // D6/B3: while EITHER inline picker is open, the field's own
                // ↑/↓/Return handlers must go quiet — see
                // `ComposerQueryField.isPickerOpen`'s doc comment. The two
                // pickers are mutually exclusive by construction (see
                // `isBranchPickerOpen`'s doc comment) — the field only needs
                // "is ANY picker open", the OR.
                isPickerOpen: isProjectPickerOpen || (isBranchPickerOpen && isBranchSegmentEligible),
                placeholder: "Type a project, branch, and command…"
            ) { event in
                handle(event)
            }
            .frame(height: fieldHeight)
            .padding(.horizontal, 10)

            resolutionLine
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

            if isProjectPickerOpen {
                Divider()
                inlineProjectPicker
            } else if isBranchPickerOpen && isBranchSegmentEligible {
                // Finding 14 fix (Slice B review round 1, still applies):
                // gated on eligibility too, not just the flag — a project
                // change cascades `worktrees`/`branchesWithoutWorktree` to
                // empty (making the branch segment itself stop rendering)
                // without necessarily flipping `isBranchPickerOpen` back to
                // false in the same instant, which used to leave this picker
                // expanded with no segment above it while
                // `ComposerQueryField.isPickerOpen` still kept the field's
                // own ↑/↓/Return handlers unmounted.
                Divider()
                inlineBranchPicker
            }
        }
        // A5: Esc while inside the inline picker (i.e. NOT in the text
        // field, which has its own `onExitCommand` below that routes
        // through the same `closeChipPickerOrDismiss`) closes the picker
        // without closing the composer.
        .onExitCommand(perform: closeChipPickerOrDismiss)
        // Nit fix (Slice B review round 2, still applies): `isBranchPickerOpen`
        // was never reset when `isBranchSegmentEligible` flipped false (e.g.
        // the resolved project changes to a non-git project while the
        // branch picker happened to be open) — the flag latched `true`, so
        // the picker silently re-expanded the next time eligibility
        // returned with no click in between.
        .onChange(of: isBranchSegmentEligible) { eligible in
            if !eligible { isBranchPickerOpen = false }
        }
        // B3: opening the branch picker is also a refresh trigger (on top
        // of the project-selection and initial-open triggers) — Sean runs
        // 2-7 parallel sessions creating worktrees constantly, so this is
        // the moment accuracy matters most. Used to live on the deleted
        // branch chip's own `Button`; moved here since the resolution
        // line's branch segment is a plain click target, not a dedicated
        // view worth attaching a modifier to.
        .onChange(of: isBranchPickerOpen) { isOpen in
            guard isOpen, let project = currentProject else { return }
            Task { await composerStore.refreshWorktrees(for: project.rootPath, projectId: project.id) }
        }
    }

    /// The resolution line: what the CURRENT field text resolves to, one
    /// clause per segment — project, branch (only when the project is a git
    /// repo), and the template Return would currently commit. Answers
    /// "where will this go?" even with an empty field, which is the whole
    /// point of the feature (Sean's words: "when hitting Cmd+T I have an
    /// intent"). This is now the ONLY mouse entry point into the
    /// project/branch pickers — the project and branch segments are
    /// clickable (unless `.locked`); the template segment is plain text,
    /// since template choice is made from the results list below, not a
    /// third picker.
    ///
    /// Kept quiet by design (Sean's ask: "maybe on hover the chips are
    /// shown" — this is the resting, always-visible form of that): plain
    /// secondary text, no pill background, no border — a status line, not a
    /// control strip. DESIGN.md §4 documents the exact styling.
    private var resolutionLine: some View {
        let segments = SessionComposerCommandParser.resolutionLineSegments(
            projectName: currentProject?.name,
            isProjectLocked: isProjectLocked,
            isBranchSegmentEligible: isBranchSegmentEligible,
            isCreatingWorktree: composerStore.isCreatingWorktree,
            typedBranchResolution: typedBranchResolution,
            currentBranchLabel: currentBranchLabel,
            templateTitle: selectedOption?.title
        )

        return HStack(spacing: 4) {
            Text("→")
                .font(.system(size: subtitleFontSize))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            resolutionSegment(
                segments.projectLabel,
                isClickable: segments.isProjectClickable,
                accessibilityLabel: "Project: \(segments.projectLabel)",
                accessibilityHint: segments.isProjectClickable ? "Opens project picker" : nil
            ) {
                isBranchPickerOpen = false
                isProjectPickerOpen.toggle()
            }

            // B3: rendered only when the project is eligible (a git repo
            // enumeration found something to offer) — a non-git project
            // shows no branch segment at all, not a disabled one (Sean's
            // call, unchanged from the deleted chip's own reasoning).
            if let branchLabel = segments.branchLabel {
                resolutionDot
                resolutionSegment(
                    branchLabel,
                    isClickable: true,
                    isError: segments.branchIsError,
                    accessibilityLabel: "Branch: \(branchLabel)",
                    accessibilityHint: "Opens branch picker"
                ) {
                    isProjectPickerOpen = false
                    isBranchPickerOpen.toggle()
                }
            }

            resolutionDot
            Text(segments.templateLabel)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Template: \(segments.templateLabel)")
        }
        .font(.system(size: subtitleFontSize))
    }

    private var resolutionDot: some View {
        Text("·")
            .font(.system(size: subtitleFontSize))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    /// One resolution-line segment: a plain `Text` when `isClickable` is
    /// false (the `.locked` project — a locked composer must never expose a
    /// live picker affordance, same rule the deleted chip's `.locked` state
    /// enforced), otherwise a plain-styled `Button` opening the segment's
    /// picker. `isError` renders in `.systemRed` — the legible, on-screen
    /// form of an unresolved typed branch (previously visible only as a
    /// `writeError` message after a failed commit attempt).
    @ViewBuilder
    private func resolutionSegment(
        _ label: String,
        isClickable: Bool,
        isError: Bool = false,
        accessibilityLabel: String,
        accessibilityHint: String?,
        action: @escaping () -> Void
    ) -> some View {
        let text = Text(label)
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(isError ? AnyShapeStyle(Color(nsColor: .systemRed)) : AnyShapeStyle(.secondary))

        if isClickable {
            Button(action: action) { text }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint(accessibilityHint ?? "")
        } else {
            text.accessibilityLabel(accessibilityLabel)
        }
    }

    /// `ProjectDropdownView`'s list content, reused verbatim, but presented
    /// as an expansion inline inside the composer card instead of via
    /// `.popover` — see the type's own doc comment for why that was
    /// fragile. `currentProject?.id`, not the raw
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
            isProjectPickerOpen = false
        }
        .environmentObject(store)
    }

    // MARK: - Branch picker (Slice B, B3 — chip deleted, picker kept)

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
                isBranchPickerOpen = false
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
                isBranchPickerOpen = false
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
        // Blocker 2 fix (Slice B review round 1): reject an unresolvable
        // typed branch loudly, checked FIRST and before touching ANY of
        // this function's other state — see `typedBranchResolution`'s doc
        // comment for why silently falling through to the picker's last
        // pick is exactly the bug this closes. `selectedIndex` is
        // deliberately left alone here (unlike the N4 failed-precommit path
        // below) — the row that triggered this was never actually about to
        // commit into the wrong project or session; only the branch
        // segment is broken, and the user is still mid-typing it.
        // SF-1 fix (Slice B review round 3): `.pending` used to fall
        // through this guard entirely — it wasn't in the switch — so
        // `selectedIndex = nil` and the `selectedProjectId` write below both
        // ran before the LATER switch (line ~1349) finally rejected it,
        // silently repointing the dropdown at a project the user never
        // selected before the commit failed. `.pending` gets the exact same
        // treatment as `.unresolved` here: rejected first, before touching
        // ANY of this function's other state — matching this guard's own
        // doc comment below, which already promised that for every
        // unresolvable typed-branch case.
        switch typedBranchResolution {
        case .unresolved(let token):
            composerStore.rejectUnresolvedBranch(token: token)
            return
        case .pending:
            composerStore.rejectUnresolvedBranch(message: "Still checking branches for this project — try again in a moment.")
            return
        case .notTyped, .resolved, .isDefaultBranch:
            break
        }

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
        //
        // Blocker 2: routed through the STRICT commit-time resolver, not
        // the plain-optional `resolveCommitWorktreePath` the picker's
        // "already shown" comparisons still use — `.unresolved` AND
        // `.pending` (SF-1 fix, Slice B review round 3) are both already
        // handled by the early-return guard above, so `.success` is the
        // only case this switch can reach; the `.failure` arm exists only
        // so this stays exhaustive and safe if that invariant ever breaks.
        switch SessionComposerCommandParser.resolveCommitWorktreePathForCommit(
            typedBranch: typedBranchResolution,
            selectedWorktreePath: composerStore.selectedWorktreePath
        ) {
        case .success(let path):
            composerStore.selectedWorktreePath = path
        case .failure(let error):
            composerStore.rejectUnresolvedBranch(message: error.message)
            selectedIndex = bestSelectionIndex(in: flattenedOptions)
            return
        }

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

        case .move(.up):
            if flattenedOptions.isEmpty { break }
            let current = selectedIndex ?? UInt(flattenedOptions.count)
            selectedIndex = (current == 0) ? UInt(flattenedOptions.count - 1) : current - 1

        case .move(.down):
            if flattenedOptions.isEmpty { break }
            let current = selectedIndex ?? UInt.max
            selectedIndex = (current >= UInt(flattenedOptions.count - 1)) ? 0 : current + 1

        // Model A rebuild: there is no chip to focus with left-arrow (D5's
        // dead-code note about `NSTextView.moveLeft:` applied to the
        // now-deleted chip specifically), and no `.backspaceAtStart` event
        // either — the field has no non-editable segment for backspace to
        // pop back to text, so ordinary `NSTextField` backspace already
        // does the right thing on every macOS version with no handler
        // needed here at all.
        case .move:
            break
        }
    }

    // MARK: - Project/branch segment actions (resolution line, model A —
    // was "Breadcrumb chip actions, Slice A" before the chips were deleted)

    /// Change the resolved project via the inline picker. The cascade rule
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
        isProjectPickerOpen = false
        let currentlyShownId = SessionComposerCommandParser.resolveCommitProjectId(
            commandProjectId: commandProject?.id,
            selectedProjectId: composerStore.selectedProjectId
        )
        composerStore.changeProjectChip(to: project.id, currentlyShown: currentlyShownId)
    }

    /// ⌘Z restores the segment(s) the most recent project-segment change
    /// cleared, as one step.
    private func undoChipCascade() {
        composerStore.undoProjectChipChange()
    }

    /// Change the resolved branch via the inline picker. Same
    /// currently-shown resolution idiom as `changeProjectChip(to:)` above
    /// (typed wins over picked), routed through the shared, tested
    /// `resolveCommitWorktreePath` rather than re-deriving the precedence
    /// inline.
    private func changeBranchChip(to worktreePath: String) {
        isBranchPickerOpen = false
        let currentlyShown = SessionComposerCommandParser.resolveCommitWorktreePath(
            typedWorktreePath: typedWorktreePath,
            selectedWorktreePath: composerStore.selectedWorktreePath
        )
        composerStore.changeBranchChip(to: worktreePath, currentlyShown: currentlyShown)
    }

    // `popChipToText()` used to live here — the A5 "backspace at position 0
    // pops the chip back into raw editable text" gesture. Deleted with the
    // chips (model A rebuild): the field has no non-editable segment for
    // backspace to pop back to, so ordinary text editing already does the
    // right thing. `SessionComposerStore.popChipToText(projectName:)` and
    // its test were deleted alongside this call site.

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
    /// B3: widened to check BOTH pickers — `isProjectPickerOpen` alone
    /// would let Esc close the whole composer while the BRANCH picker was
    /// open instead of just dismissing that picker.
    private func closeChipPickerOrDismiss() {
        guard !isHandlingExitCommand else { return }
        isHandlingExitCommand = true
        DispatchQueue.main.async { isHandlingExitCommand = false }

        if isBranchPickerOpen {
            isBranchPickerOpen = false
        } else if isProjectPickerOpen {
            isProjectPickerOpen = false
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
    /// D6: whether the resolution line's inline project/branch picker is
    /// currently open (opened by clicking a resolution-line segment, model A
    /// rebuild — used to be the breadcrumb chip's own click target). While
    /// `true`, this field's own ↑/↓/Return handlers go quiet — the picker
    /// (`ProjectDropdownView.keyboardCaptureLayer`) becomes the only live
    /// ↑/↓/Return handler on screen. Clicking a segment to open the picker
    /// does NOT move first responder away from this field (deliberate — see
    /// this type's own doc comment on why focus-loss auto-dismiss was
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
        // `.backspaceAtStart` used to live here — the breadcrumb chip's
        // pop-to-text gesture (A5), fired when backspace hit an empty field
        // with a chip still showing. Deleted with the chips (model A
        // rebuild): the field has no non-editable segment left to pop, so
        // backspace against an empty field is now ordinary, no-op text
        // editing with no event to dispatch.
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

    /// Blocker 5 fix (Slice B review round 1): whether the "New branch
    /// name…" field currently has first responder. `keyboardCaptureLayer`
    /// installs a hidden `Button().keyboardShortcut(.return, modifiers: [])`
    /// in the SAME window as this field's own `.onSubmit` — AppKit
    /// dispatches key equivalents via `performKeyEquivalent` BEFORE
    /// `keyDown` reaches the first responder, so Return in the field fired
    /// `commitHighlighted()` (discarding the typed name with no feedback)
    /// and ↑/↓ moved the row highlight instead of the caret. This mirrors
    /// exactly how `ComposerQueryField` already stands its OWN equivalent
    /// handlers down while `isPickerOpen` — the third capture layer this
    /// picker never accounted for is itself, against its own child field.
    @FocusState private var isNewBranchFieldFocused: Bool

    /// Should-fix 12 fix (Slice B review round 2): drives a shake on the
    /// "New branch name…" field when Return fires against a name that isn't
    /// novel (empty, or matches an existing row) — that used to be a
    /// silent no-op with no feedback at all, since this picker's own
    /// `keyboardCaptureLayer` is unmounted while this field has focus
    /// (blocker 5) and the field's own `.onSubmit` guard just returned.
    @State private var newBranchFieldShakeTrigger: CGFloat = 0

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
        // Blocker 3 fix (Slice B review round 1): clamp `highlightedIndex`
        // whenever `worktrees` itself changes, not only in `.onAppear` — a
        // sibling session pruning a worktree (or this store's own refresh
        // landing) while the picker is open and highlighted at the LAST row
        // used to leave `highlightedIndex` pointing past the shrunk array,
        // and `commitHighlighted()` indexed it unguarded. `min` is
        // sufficient here — `rowCount` is `1 + worktrees.count`, so a
        // shrink can only ever move the valid upper bound down, never
        // invalidate an index that was already in range.
        .onChange(of: worktrees) { newWorktrees in
            highlightedIndex = min(highlightedIndex, newWorktrees.count)
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
                    // Nit fix (Slice B review round 1): `isLocked` was
                    // parsed and tested but never surfaced anywhere — a
                    // worktree Sean has pinned against `git worktree prune`
                    // read identically to an unlocked one. Appended to the
                    // existing path subtitle rather than a new row/icon, to
                    // stay inside this picker's existing two-line-per-row
                    // shape.
                    Text(worktree.isLocked ? "\(worktree.path) · locked" : worktree.path)
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
                .focused($isNewBranchFieldFocused)
                .onSubmit {
                    // Should-fix 12 fix (Slice B review round 2): Return
                    // against a name that isn't novel (empty, or already
                    // offered above) used to be a silent no-op — nothing
                    // else is listening either, since `keyboardCaptureLayer`
                    // below unmounts its own Return/↑/↓ handlers while this
                    // field has focus (blocker 5). Shake for feedback on a
                    // genuine (non-empty) attempt that didn't create
                    // anything, and drop focus so Return/↑/↓ go back to
                    // navigating the rows above instead of doing nothing a
                    // second time.
                    guard newBranchNameIsNovel else {
                        if !trimmedNewBranchName.isEmpty {
                            withAnimation(.linear(duration: 0.25)) {
                                newBranchFieldShakeTrigger += 1
                            }
                        }
                        isNewBranchFieldFocused = false
                        return
                    }
                    onCreateWorktree(trimmedNewBranchName)
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .modifier(ShakeEffect(animatableData: newBranchFieldShakeTrigger))
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
    ///
    /// Blocker 5 fix (Slice B review round 1): this is ALSO removed from
    /// the hierarchy entirely (not merely no-op'd) while
    /// `isNewBranchFieldFocused` — the same `FA` pattern
    /// `ComposerQueryField` already uses against `isPickerOpen`, applied
    /// here against this picker's OWN child field. AppKit resolves a key
    /// equivalent (`performKeyEquivalent`, which is how `.keyboardShortcut`
    /// is implemented) before ordinary `keyDown` reaches the first
    /// responder, so leaving this `Button` mounted while the "New branch
    /// name…" field has focus meant Return there always committed the
    /// HIGHLIGHTED ROW instead of the typed name, and ↑/↓ always moved the
    /// row highlight instead of the caret — the field's own `.onSubmit`
    /// (just above) never got a chance to fire. Verification note: I could
    /// not exercise this with real keystrokes (no synthesized keyboard
    /// input, per this task's hard constraint) — this fix is the same
    /// architecture as the already-shipped, unmount-not-guard fix for
    /// `ComposerQueryField`'s equivalent problem, applied symmetrically;
    /// it is NOT independently runtime-verified here, and is flagged as
    /// such rather than claimed proven.
    private var keyboardCaptureLayer: some View {
        Group {
            if !isNewBranchFieldFocused {
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
        }
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    /// Blocker 3 fix (Slice B review round 1): bounds-safe, mirroring
    /// `ProjectDropdownView.commitHighlighted`'s guard exactly — the view
    /// this was copied from. `worktrees[highlightedIndex - 1]` unguarded
    /// crashed whenever a refresh (opening the picker IS a refresh trigger)
    /// landed a SHORTER list than what `highlightedIndex` was still keyed
    /// against: open with 3 cached, arrow down to the last row, a sibling
    /// session prunes one mid-picker, the refresh lands with 2, Return —
    /// hard crash. The `.onChange(of: worktrees)` clamp above closes the
    /// window further, but this guard is what actually prevents the crash
    /// if anything ever slips past it.
    private func commitHighlighted() {
        if highlightedIndex == 0 {
            onSelectDefault()
        } else {
            let index = highlightedIndex - 1
            guard index >= 0, index < worktrees.count else { return }
            onSelectWorktree(worktrees[index].path)
        }
    }
}

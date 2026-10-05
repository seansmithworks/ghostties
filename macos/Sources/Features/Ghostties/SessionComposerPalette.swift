import AppKit
import SwiftUI
import GhosttiesCore

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
///   see the note below). The field holds the literal typed string, always.
///   Composer UI 11 (plan §3 Step 3/4/5) replaced the resolution line that
///   used to sit beneath it with an in-field GHOST PLACEHOLDER
///   (`ghostPlaceholder`) showing the exact path Return
///   would currently commit and a STATUS STRIP for pre/post-Return errors.
///   Variant G (Pass A, locked 2026-08-30) removed the sibling branch
///   chevron control that used to sit beside the field; Pass C
///   (2026-08-30) removed the last one, `projectControl`, on Sean's call
///   that projects belong IN the results list, not behind a chevron — a
///   blank query now populates the PROJECTS lane with every project
///   instead of hiding it (`filteredProjectOptions`). The field's trailing
///   edge is a plain caret; the branch stage still opens by typing `>`, no
///   mouse route was ever added back for it.
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
    @ObservedObject private var composerStore: SessionComposerStore

    /// `composerStore` defaults to the real process-wide singleton for
    /// every production call site (`SessionComposerOverlay`,
    /// `ProjectDisclosureRow`), unchanged from before this initializer
    /// existed. The parameter exists so the Step 2 snapshot harness
    /// (`SessionComposerSnapshotTests`) can mount this view against an
    /// isolated `SessionComposerStore(isolatedForTesting:)` instead — this
    /// repo's `.shared` composer store has no environment-object seam, so
    /// without this the harness would have no way to avoid mutating the
    /// developer's real, persisted UserDefaults (pins, recents) on every
    /// test run.
    /// Round 13 review finding: `.singleLine`'s `newStyleFieldFontSize`/
    /// `newStyleFieldWidth` read `ComposerSingleLineTuning`'s `.standard`-
    /// defaulting call sites with no injection point, so no test could
    /// prove this palette actually consumes a non-default tuning without
    /// writing the real `UserDefaults.standard` domain — off-limits to a
    /// parallel `xcodebuild test` run for the same reason documented on
    /// the isolated stores above. `nil` (every production call site)
    /// falls through to `.standard`, unchanged.
    let tuningDefaultsForTesting: UserDefaults?

    init(
        isPresented: Binding<Bool>,
        request: SessionComposerRequest,
        composerStore: SessionComposerStore = .shared,
        tuningDefaultsForTesting: UserDefaults? = nil
    ) {
        self._isPresented = isPresented
        self.request = request
        self.composerStore = composerStore
        self.tuningDefaultsForTesting = tuningDefaultsForTesting
    }

    @State private var selectedIndex: UInt?
    /// Blocker 2 fix (Slice B review round 2): debounced re-refresh when a
    /// typed command resolves a DIFFERENT project than whatever the
    /// composer's worktree cache currently describes — see
    /// `SessionComposerStore.worktreesProjectId`'s doc comment. Cancelled
    /// and replaced on every `commandProject` change so a fast typist who
    /// flips through several project names before settling only ever fires
    /// the LAST one, never one refresh per keystroke.
    @State private var commandProjectRefreshTask: _Concurrency.Task<Void, Never>?
    // MARK: - No-match Enter feedback (command grammar slice 1)

    /// Drives `ShakeEffect` — 3 cycles / 6pt, animated over 0.25s. Bumped by
    /// one on every no-match Return. `ShakeEffect.effectValue` reads the
    /// ABSOLUTE value of `animatableData`, not a delta — bumping by whole
    /// integers works cleanly anyway because `shakesPerUnit` is an integer,
    /// so every whole increment lands the sine argument back on a
    /// zero-crossing, letting back-to-back no-match Returns restart a clean
    /// shake instead of visibly jumping mid-cycle.
    @State private var shakeTrigger: CGFloat = 0

    // MARK: - R14 Witness ghost (composer-only trial, single-line + centered only)

    /// Bumped on the four finished-event beats the Witness view doesn't
    /// detect on its own (`.resolve` is `ComposerWitnessView`'s own
    /// `.onChange(of: identity)`, not here). See `ComposerWitness.Beat`
    /// hook sites: open (`onAppear`/`onChange(focusSearchFieldTrigger)`
    /// below), Tab accept (`handle(_:)` `.acceptedGhost` case above),
    /// unknown branch (`commit(template:)`'s `.unresolved` branch), launch
    /// (`commit(template:)`'s success branch).
    @State private var witnessBeat: ComposerWitness.Beat = .idle

    /// Placement gate (plan §1): toggle on.
    private var showsWitness: Bool {
        ComposerWitnessSetting.isEnabled(defaults: tuningDefaults)
    }

    private var witnessIdentity: ComposerWitness.Identity {
        ComposerWitness.identity(commandProject: commandProject, binding: request.projectBinding)
    }

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

    /// Round 12: the one production call site that resolves `NSGlassEffect
    /// View`'s real runtime availability — see `ComposerSingleLineBackground
    /// Choice`'s doc comment for why the SELECTION rule itself lives in a
    /// separate, unit-testable pure function instead of being inlined here.
    private var isGlassTreatmentAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

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

    /// The project a locked composer's binding already fixes — Fix 3
    /// (round-2 review). `nil` unless `request.projectBinding` is
    /// `.locked`, in which case it's that exact project; fed to `parsePath`
    /// as `preResolvedProject` so branch/operator/thread matching can run
    /// against a locked composer's typed text (previously dead — see
    /// `isProjectLocked`'s call sites before this fix).
    private var lockedProject: Project? {
        if case .locked(let project) = request.projectBinding { return project }
        return nil
    }

    /// Project-only resolution pass — Fix 1 (round-2 review). `parsePath`'s
    /// project match never depends on `templates`/`knownBranchNames` (it's
    /// tried first, unconditionally), so this lightweight pass safely
    /// determines WHICH project's branch/template lists `commandParse`
    /// below should be scoped to, without `commandParse` ever feeding back
    /// into its own inputs (that would be a genuine circular reference:
    /// `commandParse` → `commandProject`/`currentProject` →
    /// `availableTemplates`/worktrees → `commandParse`).
    private var commandProjectIdHint: UUID? {
        // Round-4 review, defect: was `query` (trimmed). `parse()` builds
        // its ranges against whatever string it's handed, so passing raw
        // is range-safe — see `commandParse`'s doc comment for why the
        // trimmed contract diverges from `effectiveCommandParse` on the
        // exact keystroke that resolves a typed project.
        SessionComposerCommandParser.parse(
            query: composerStore.searchText, projects: store.projects, isLocked: isProjectLocked,
            preResolvedProject: lockedProject
        ).projectId
    }

    private var commandProjectHint: Project? {
        guard let id = commandProjectIdHint else { return nil }
        return store.projects.first(where: { $0.id == id })
    }

    /// Real branch names for whichever project `commandProjectIdHint`
    /// resolves — Fix 1. Sourced from the same worktree cache
    /// `typedBranchResolution` already reads; that cache is refreshed
    /// (debounced) whenever `commandProject` changes, so it can trail the
    /// hint by a keystroke on a fast typist, same tolerance already
    /// accepted for `typedBranchResolution` itself (see
    /// `TypedBranchResolution.pending`).
    private var commandKnownBranchNames: [String] {
        guard commandProjectHint != nil else { return [] }
        var names = composerStore.worktrees.compactMap { $0.branch }
        if let rootBranch = composerStore.currentBranchAtProjectRoot {
            names.append(rootBranch)
        }
        // Bug fix: the parser's `knownBranchNames` used to only ever see
        // branches that already have a worktree (plus the root branch) —
        // every other branch in the repo fell through to the ad-hoc/thread
        // free-text path regardless of the `>`-armed-branch fix above.
        // `branchesWithoutWorktree` is the store's already-computed list of
        // exactly those; appending it here is what makes a typed branch
        // with no worktree yet resolve to `.branch(...)` (unresolved, or
        // creatable — see `typedBranchCreateOffer` below) instead of
        // silently becoming a shell command.
        names.append(contentsOf: composerStore.branchesWithoutWorktree)
        return names
    }

    /// Real per-project template list for whichever project
    /// `commandProjectIdHint` resolves — Fix 1.
    private var commandTemplates: [AgentTemplate] {
        guard let project = commandProjectHint else { return [] }
        return SessionTemplateResolver.templates(for: project, store: store)
    }

    /// Tokenizes `query` against the known project list, real per-project
    /// branch names, and real per-project templates. `.none` (the common
    /// case) means "no command recognized" — every downstream filter below
    /// falls through to the ordinary whole-string query, byte-identical to
    /// before this parser existed.
    private var commandParse: SessionComposerCommandParser.ParseResult {
        // Round-4 review, defect: was `query` (trimmed). Since
        // `effectiveParse` returns `directParse` unchanged whenever a
        // project token was typed (the common "typed-project" shape), a
        // trimmed `commandParse` meant that shape never saw the raw-text
        // path `effectiveCommandParse` otherwise gets everywhere else —
        // `"ghostties orchestrator "` failed to resolve the operator while
        // the implied-project equivalent `"orchestrator "` did.
        SessionComposerCommandParser.parse(
            query: composerStore.searchText,
            projects: store.projects,
            knownBranchNames: commandKnownBranchNames,
            templates: commandTemplates,
            isLocked: isProjectLocked,
            preResolvedProject: lockedProject
        )
    }

    /// Fix 4 (round-2 review), re-routed through `effectiveParse` (round-3
    /// review, Blockers 2/3): when no project token was typed at all
    /// (`commandParse.projectId == nil`) but `currentProject` already
    /// resolves (the sticky/selected default the ghost placeholder is
    /// already showing), branch/operator/thread typing still needs to
    /// resolve against THAT project's context — `commandParse` itself came
    /// back `.none` in this shape, so its remainder fields are empty/
    /// invalid and can't just be reused. This is now the ONE parse of
    /// record every caller needing branch/operator/thread resolution reads
    /// — `templateFilterQuery`/`commandOptions` below AND
    /// `typedBranchResolution`/`currentBranchLabel` further down — so they
    /// can never diverge by construction (Blocker 3: they used to read two
    /// different parses, and a typed branch consumed by this one was
    /// invisible to the other, silently inheriting the picker's stale
    /// worktree pick instead of the typed branch). `rawQuery:
    /// composerStore.searchText` — NOT the trimmed `query` — is what fixes
    /// Blocker 2 (the trimmed text erased the trailing-whitespace signal
    /// `effectiveParse` needs to tell "project typed, nothing after it yet"
    /// apart from "project typed, content following it").
    private var effectiveCommandParse: SessionComposerCommandParser.ParseResult {
        let branchNames: [String] = {
            var names = composerStore.worktrees.compactMap { $0.branch }
            if let rootBranch = composerStore.currentBranchAtProjectRoot {
                names.append(rootBranch)
            }
            // Bug fix: see `commandKnownBranchNames`'s matching comment
            // above — the same gap exists here for the implied-project
            // (no project literally typed) resolution path.
            names.append(contentsOf: composerStore.branchesWithoutWorktree)
            return names
        }()
        return SessionComposerCommandParser.effectiveParse(
            rawQuery: composerStore.searchText,
            directParse: commandParse,
            impliedProject: currentProject,
            projects: store.projects,
            knownBranchNames: branchNames,
            templates: currentProject.map { SessionTemplateResolver.templates(for: $0, store: store) } ?? [],
            isLocked: isProjectLocked
        )
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

    /// Whether the project is a git repo at all — `branchControl` (and its
    /// picker) has no entry point unless the project genuinely IS one.
    /// Blocker 6 fix (Slice B review round 1):
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

    /// Full three-state resolution of the typed branch token, if any —
    /// backs `commit(template:)`'s loud-failure path (blocker 2). See
    /// `SessionComposerCommandParser.TypedBranchResolution`'s doc comment
    /// for what each case means.
    ///
    /// Round-6 review, Blocker: the argument assembly is hoisted into
    /// `Self.resolveTypedBranch(branchToken:composerStore:resolvingForProjectId:)`
    /// below — an `internal static` seam, not `private` — specifically so a
    /// test can exercise the real production wiring (which STORED PROPERTY
    /// feeds `cachedProjectId`) instead of only `resolveTypedBranch`'s own
    /// pure logic. `cachedProjectId: composerStore.worktreesProjectId,` was
    /// silently dropped from this call in `4560d9b5c` (the same edit that
    /// swapped `resolvingForProjectId` from `commandProject?.id` to
    /// `currentProject?.id`), leaving the callee's `cachedProjectId == nil`
    /// default compared against a non-nil `resolvingForProjectId` forever —
    /// every typed branch read `.pending` permanently, and every EXISTING
    /// test called `resolveTypedBranch` directly with both arguments
    /// hand-passed, so none of them exercised this call site and all stayed
    /// green. See `SessionComposerBranchLaunchTests.typedBranchResolutionWiresComposerStoreWorktreesProjectIdAsCachedProjectId`.
    private var typedBranchResolution: SessionComposerCommandParser.TypedBranchResolution {
        Self.resolveTypedBranch(
            // Round-3 review, Blocker 3: reads `effectiveCommandParse`, the
            // SAME parse `templateFilterQuery`/`commandOptions` read, not
            // the un-implied `commandParse` — see `effectiveCommandParse`'s
            // doc comment. `commandParse.branchToken` alone never saw a
            // branch typed against an already-selected-but-not-literally-
            // typed project (`"main cco -n test"` with the project picked
            // via the dropdown): `commandParse` has no project context to
            // resolve "main" as a branch against in that shape, so it always
            // reported `.notTyped`, and this function silently deferred to
            // whatever worktree the picker had last selected instead of
            // "main".
            branchToken: effectiveCommandParse.branchToken,
            composerStore: composerStore,
            // Blocker 2 fix (Slice B review round 2): only trust
            // `composerStore.worktrees` when it actually describes the
            // project the branch was typed against — see
            // `worktreesProjectId`'s doc comment and
            // `TypedBranchResolution.pending`'s. Round-3 review, Blocker 3:
            // `currentProject`, not `commandProject` — the branch above now
            // resolves against `currentProject`'s context (via
            // `effectiveCommandParse`'s `impliedProject`) even when nothing
            // was literally typed, so the project this resolution is FOR
            // must agree; `commandProject` stays `nil` in that exact shape
            // and would falsely read as a cache mismatch (`.pending`
            // forever) against a `worktreesProjectId` that already, and
            // correctly, points at `currentProject`.
            resolvingForProjectId: currentProject?.id
        )
    }

    /// Round-6 review, Blocker: the call-site wiring extracted out of
    /// `typedBranchResolution` above — reads `composerStore.worktrees`,
    /// `composerStore.currentBranchAtProjectRoot`, AND
    /// `composerStore.worktreesProjectId` (as `cachedProjectId`) directly
    /// off the passed-in store, so a test that constructs a real
    /// `SessionComposerStore` and calls this exercises the exact same
    /// property wiring production does — not a hand-passed
    /// `cachedProjectId:` a caller could silently omit.
    static func resolveTypedBranch(
        branchToken: String?,
        composerStore: SessionComposerStore,
        resolvingForProjectId: UUID?
    ) -> SessionComposerCommandParser.TypedBranchResolution {
        SessionComposerCommandParser.resolveTypedBranch(
            branchToken: branchToken,
            worktrees: composerStore.worktrees,
            currentBranchAtProjectRoot: composerStore.currentBranchAtProjectRoot,
            cachedProjectId: composerStore.worktreesProjectId,
            resolvingForProjectId: resolvingForProjectId
        )
    }

    /// What the branch chip displays: the typed branch token if a command
    /// resolved one, else the picker's current pick's branch name, else
    /// `nil` (no chip rendered — see `queryRow`).
    private var currentBranchLabel: String? {
        // Round-3 review, Blocker 3: same single-parse-of-record read as
        // `typedBranchResolution` above.
        if let token = effectiveCommandParse.branchToken { return token }
        guard let path = composerStore.selectedWorktreePath else { return nil }
        return composerStore.worktrees.first(where: { $0.path == path })?.branch ?? path
    }

    /// The 11.1 rest-state ghost placeholder (Step 3, Composer UI 11 plan
    /// §3) — the descriptor cycle's last item. Built
    /// from the exact same segments `selectedOption` and a Return commit
    /// read (D-B) — see `SessionComposerCommandParser.ghostPlaceholder`'s
    /// doc comment for the four rules and their order.
    private var ghostPlaceholder: String {
        let segments = SessionComposerCommandParser.resolutionLineSegments(
            projectName: currentProject?.name,
            isProjectLocked: isProjectLocked,
            isBranchSegmentEligible: isBranchSegmentEligible,
            isCreatingWorktree: composerStore.isCreatingWorktree,
            typedBranchResolution: typedBranchResolution,
            currentBranchLabel: currentBranchLabel,
            templateTitle: selectedOption?.title
        )
        return SessionComposerCommandParser.ghostPlaceholder(
            segments: segments,
            hasSelection: selectedOption != nil,
            projectsExist: !store.projects.isEmpty
        )
    }

    /// The ghost field's source — deliberately NOT `ghostPlaceholder` above.
    /// `ghostPlaceholder` is welded to `currentProject` (it always renders
    /// `"<currentProject.name> > ..."`), which is correct for the rest state
    /// (only ever shown while the field is EMPTY, before any option could
    /// diverge from the current project) but wrong once text is present:
    /// typing `bruk` against a highlighted `Brukas` PROJECT row — a
    /// different project than `currentProject` — produced a ghost that
    /// still started with `currentProject`'s name, so `bruk` was never a
    /// prefix of it and no ghost rendered at all, even though the list
    /// agreed on `Brukas`. This reads the CURRENTLY HIGHLIGHTED option's
    /// own resolved destination instead — the field and the list can no
    /// longer disagree about what Return would launch.
    ///
    /// No selection: falls back to the same four-rule empty-state text
    /// `ghostPlaceholder` computes (status text, not a destination — model
    /// A's own rules already cover "nothing resolved" correctly, so
    /// there's no reason to re-derive that half).
    ///
    /// Selection is a TEMPLATE (or the ad-hoc `Run "…"` row) in
    /// `currentProject`: identical to what `ghostPlaceholder` already
    /// computes — `selectedOption?.title` was always the right segment 3,
    /// the bug was only ever the project segment.
    ///
    /// Selection is a PROJECT-switch row (a different project than
    /// `currentProject`): resolves THAT project's own destination via
    /// `destination(for:)` — not `currentProject`'s.
    private var ghostFullPathForField: String {
        guard let selectedOption else { return ghostPlaceholder }
        if selectedOption.template == nil,
           let targetProject = store.projects.first(where: { $0.id == selectedOption.id }),
           targetProject.id != currentProject?.id {
            return SessionComposerPalette.destination(
                for: targetProject,
                store: store,
                recentSelections: composerStore.recentSelections
            )
        }
        return ghostPlaceholder
    }

    /// The destination a Return commit would resolve to for `project` if
    /// the user switched to it right now — used only by
    /// `ghostFullPathForField` above, for a project OTHER than
    /// `currentProject`. A `static` pure function (not a `self`-scoped
    /// computed property) deliberately, so it's directly unit-testable
    /// without constructing a `SessionComposerPalette` view — this repo's
    /// usual private-computed-property-on-a-View test gap doesn't apply
    /// here. Branch is always `"Default"`: this repo caches git branch
    /// data (`SessionComposerStore.currentBranchAtProjectRoot`) for
    /// `currentProject` alone (refreshed async on `open()`/project
    /// switch), so a highlighted-but-not-yet-switched-to project's real
    /// current branch is genuinely unknown without a new async git query —
    /// out of scope here (`SessionComposerStore` persistence/git plumbing
    /// is explicitly untouched by this task). `"Default"` mirrors
    /// `resolutionLineSegments`'s own "no override" fallback rather than
    /// inventing a second, differently-worded placeholder for the same
    /// idea.
    static func destination(
        for project: Project,
        store: WorkspaceStore,
        recentSelections: [RecentComposerSelection]
    ) -> String {
        let templates = SessionTemplateResolver.templates(for: project, store: store)
        let templateTitle: String
        if let defaultId = project.defaultTemplateId,
           let match = templates.first(where: { $0.id == defaultId }) {
            templateTitle = match.name
        } else if let recent = recentSelections.first(where: { $0.projectId == project.id }),
                  let match = templates.first(where: { $0.id == recent.templateId }) {
            templateTitle = match.name
        } else if let first = templates.first {
            templateTitle = first.name
        } else {
            templateTitle = "Shell"
        }
        return "\(project.name) > Default > \(templateTitle)"
    }

    /// Step 4 (Composer UI 11 plan §3): the status strip's single occupant —
    /// generalized from the old `writeError`-only strip. Additive: the
    /// resolution line is still present after this step, so its deletion
    /// (Step 5) reverts independently.
    private var statusStripMessage: String? {
        // Decision 1: a typed branch with no worktree gets an offered row
        // (`commandOptions`, below) rather than reading as a dead end — the
        // plain "not found" message would contradict that offer, so it's
        // suppressed whenever `typedBranchCreateOffer` applies. `writeError`
        // still wins over either, matching `statusStripMessage`'s own
        // priority.
        if composerStore.writeError == nil, typedBranchCreateOffer != nil {
            return nil
        }
        return SessionComposerCommandParser.statusStripMessage(
            writeError: composerStore.writeError,
            typedBranchResolution: typedBranchResolution
        )
    }

    /// Composer variant G (Sean's ruling, 2026-08-31): the typed token in an
    /// armed branch position (`> <token>`), whenever it doesn't already
    /// resolve — `commandOptions` offers a create row for it, EITHER shape:
    /// a KNOWN branch with no worktree yet (`composerStore
    /// .branchesWithoutWorktree`, the pre-existing case — "Create worktree
    /// for X") or a token that matches no branch at all (the new case —
    /// "Create branch X", since creating it also creates its worktree; see
    /// `isTypedBranchCreateOfferForKnownBranch` below for which copy
    /// applies). This used to gate on `branchesWithoutWorktree.contains`
    /// alone, which is exactly what left an unknown token with no offer at
    /// all — the gap that silently exec'd it as a shell command (or, before
    /// `b5286319b`, dead-ended on "No worktree found"). `nil` for every
    /// other shape (nothing typed, already resolved).
    private var typedBranchCreateOffer: String? {
        guard case .unresolved(let token) = typedBranchResolution else { return nil }
        return token
    }

    /// Distinguishes the two `typedBranchCreateOffer` cases for COPY only —
    /// the create action itself (`composerStore.createWorktree`) is
    /// identical either way; `GitWorktreeEnumerator.add` already calls
    /// `branchExists` and runs `git worktree add -b <branch> <dir>` only
    /// when the branch doesn't exist yet, so no new git plumbing is needed
    /// here. `false` (the default) is safe for `token == nil` callers —
    /// they never render.
    private func isTypedBranchCreateOfferForKnownBranch(_ token: String) -> Bool {
        composerStore.branchesWithoutWorktree.contains(token)
    }

    /// Worktree-launch ruling (2026-08-27, control-flow inversion — review
    /// round 2): what "the composer field already resolves to something
    /// launchable" MEANS, for the ONE call site that's still allowed to
    /// launch (the typed-branch create row in `commandOptions` below — the
    /// branch picker's `inlineBranchPicker` create rows never launch, per
    /// finding 1). Thin wrapper over the pure, unit-tested
    /// `SessionComposerCommandParser.resolveWorktreeCreationLaunchTemplate`
    /// — see that function's doc comment for the three-tier resolution and
    /// why finding 3 (an unterminated template name) needed a middle tier
    /// this view-layer property used to skip entirely.
    private var worktreeCreationLaunchTemplate: AgentTemplate? {
        Self.worktreeCreationLaunchTemplate(project: currentProject, store: store, parse: effectiveCommandParse)
    }

    /// Round-4 review: the argument assembly extracted out of the private
    /// property above — same precedent as `resolveTypedBranch` a few
    /// screens up (`typedBranchResolution`/`resolveTypedBranch`, itself a
    /// round-6 extraction): a prior review claimed "no testable seam" here,
    /// which is wrong by that same precedent — hoisting the wiring into an
    /// `internal static` (not `private`) lets a test drive the REAL
    /// production scoping (`SessionTemplateResolver.templates(for:store:)`,
    /// round-3 finding 2's fix) against a real `Project`/`WorkspaceStore`,
    /// instead of only the pure resolver's logic with a hand-built template
    /// list a test could accidentally get right for the wrong reason.
    static func worktreeCreationLaunchTemplate(
        project: Project?,
        store: WorkspaceStore,
        parse: SessionComposerCommandParser.ParseResult
    ) -> AgentTemplate? {
        SessionComposerCommandParser.resolveWorktreeCreationLaunchTemplate(
            resolvedTemplateId: parse.resolvedTemplateId,
            remainderTokens: parse.remainderTokens,
            templates: project.map { SessionTemplateResolver.templates(for: $0, store: store) } ?? []
        )
    }

    /// Runs once `createWorktree`'s `onSuccess` fires (worktree-launch
    /// ruling, control-flow inversion): re-reads `worktreeCreationLaunchTemplate`
    /// LIVE (not a value captured before creation started — the field could
    /// have changed during the ≤10s window) and, if something resolves,
    /// commits through the SAME `commit(template:)` every other Return
    /// uses — `resolveCommitProjectId`, the `.workspaceDidCreateSessionInProject`
    /// post, and the `selectedIndex = nil` double-Return guard all come
    /// along for free, none of them reimplemented here. `commit(template:)`
    /// reads `composerStore.selectedWorktreePath`/`worktrees` at call time,
    /// both of which `createWorktree` already updated to the NEW worktree
    /// before invoking this — no destination needs to be threaded through
    /// explicitly. When nothing resolves, the composer stays open (B4's
    /// original behavior) and `reselectBestMatch()` moves the highlight
    /// onto the template list now that the create-offer row is gone, so the
    /// next keystroke continues the flow instead of restarting it.
    private func launchOrFocusAfterWorktreeCreation() {
        if let template = worktreeCreationLaunchTemplate {
            commit(template: template)
        } else {
            reselectBestMatch()
        }
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
    /// prefixes it. Fix 4 (round-2 review): gates on `currentProject`, not
    /// `commandProject` — a project can already be implied (sticky/
    /// selected default) with none typed at all, in which case
    /// `effectiveCommandParse` re-parses (via `effectiveParse`) against that
    /// implied project.
    private var templateFilterQuery: String {
        currentProject != nil ? effectiveCommandParse.remainderText : query
    }

    /// The `Run "<remainder>"` row appended in a new COMMAND section once a
    /// command is recognized. Blanket-running the remainder happens ONLY
    /// here, behind the same ≥2-token + project-match gate as the rest of
    /// the grammar — `filteredTemplateOptions` above still ranks any
    /// matching template first, so `ghostties orchestrator` keeps reaching
    /// the Orchestrator template instead of trying to exec a nonexistent
    /// `orchestrator` binary. Fix 4 (round-2 review): gates on
    /// `currentProject`/`effectiveCommandParse` for the same reason
    /// `templateFilterQuery` above does — a bare `cco` typed with no
    /// project prefix, against an already-implied `currentProject`, still
    /// gets a Run row.
    private var commandOptions: [ComposerOption] {
        var options: [ComposerOption] = []

        // Decision 1 (superseded by the worktree-launch ruling, 2026-08-27;
        // control flow inverted in review round 2): a typed branch that
        // names a real branch with no worktree yet gets an offered row, not
        // silent creation and not a dead-end error. Selecting it arms
        // creation exactly like `inlineBranchPicker`'s own
        // `onCreateWorktree` row does — and now also launches straight into
        // the new worktree whenever `worktreeCreationLaunchTemplate`
        // resolves something, via `launchOrFocusAfterWorktreeCreation`'s
        // `onSuccess` callback, so creation completes the user's intent
        // instead of parking it. When nothing resolves, this is unchanged:
        // the composer stays open with the branch control reading
        // "Creating…" until it resolves. `selectedIndex = nil` FIRST,
        // mirroring `commit(template:)`'s own S1 comment: this row is now
        // reachable via `selectedOption?.action()` (Return) exactly like
        // the two call sites that comment already covers, so a second
        // Return fired before creation resolves must not re-select this
        // same row and start a second, concurrent `git worktree add` — the
        // STORE'S own `guard !isCreatingWorktree` in `createWorktree` is
        // the second, independent guard against the same race (covers the
        // mouse-click path this one doesn't).
        if let currentProject, let token = typedBranchCreateOffer {
            options.append(
                ComposerOption(
                    id: SessionComposerCommandParser.createWorktreeRowId,
                    title: SessionComposerCommandParser.createBranchOfferTitle(
                        token: token,
                        isKnownBranchWithoutWorktree: isTypedBranchCreateOfferForKnownBranch(token)
                    ),
                    subtitle: currentProject.name,
                    leadingIcon: "arrow.triangle.branch",
                    action: {
                        selectedIndex = nil
                        composerStore.createWorktree(named: token, in: currentProject) { _ in
                            launchOrFocusAfterWorktreeCreation()
                        }
                    }
                )
            )
        }

        // Composer variant G: when an armed branch token consumed a word
        // that could equally have been read as the start of a command
        // (`typedBranchCreateOffer`), the parser's own remainder no longer
        // includes it — `parsePath` now always resolves an armed,
        // non-matching token as a (failed) branch lookup, never a
        // fall-through (see `parsePath`'s `branchArmed` handling). Prepending
        // the token back here is what keeps BOTH readings visible: the
        // create-branch row above, and this Run row showing exactly what
        // Sean's dominant no-branch idiom (`ghostties cco -n "thread name"`)
        // would have launched had the leading `>` never been typed at all —
        // `Run "cco -n thread name"`, not just `Run "-n thread name"` with
        // the verb silently dropped.
        let runRemainderTokens = typedBranchCreateOffer.map { [$0] + effectiveCommandParse.remainderTokens }
            ?? effectiveCommandParse.remainderTokens

        guard let currentProject,
              let template = SessionComposerCommandParser.makeAdHocTemplate(remainderTokens: runRemainderTokens)
        else { return options }

        options.append(
            ComposerOption(
                id: SessionComposerCommandParser.runRowId,
                title: "Run \"\(runRemainderTokens.joined(separator: " "))\"",
                subtitle: currentProject.name,
                leadingIcon: "terminal",
                action: { commit(template: template) }
            )
        )
        return options
    }

    // MARK: - Options

    private func makeOption(for template: AgentTemplate) -> ComposerOption {
        let group = SessionTemplateResolver.group(for: template)
        let isPreset = group == .preset

        // Subtitle: description first, then command (non-presets only), then
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
            // composerStore.searchText)` -> `reselectBestMatch()` (round-4
            // review swapped this trigger from `query`) re-seeds it in the
            // same update pass, so nothing is lost.
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

    // MARK: - Pinned lane (Composer UI 11, Step 2)

    /// Pinned templates, in pin order (most-recently-pinned-first), ranked
    /// within the lane by `SessionComposerRanking` once a query exists (a
    /// no-op against a blank query — `sorted` returns items unreordered
    /// then). Each carries `.pinned` trailing meta.
    private var pinnedOptions: [ComposerOption] {
        var seen = Set<UUID>()
        var result: [ComposerOption] = []
        for id in composerStore.pinnedTemplateIds {
            guard !seen.contains(id), let template = availableTemplates.first(where: { $0.id == id }) else { continue }
            seen.insert(id)
            result.append(makeOption(for: template).withTrailingMeta(.pinned))
        }
        return SessionComposerRanking.sorted(result, query: templateFilterQuery, title: { $0.title }, subtitle: { $0.subtitle })
    }

    /// Lane 1 (board 11.2): pinned options first, then recents minus
    /// whatever's already pinned — a pinned-and-recent item renders once, in
    /// the pinned block, keeping only the pin glyph (11.11 backlog strawman,
    /// built as adapted). Non-pinned recents carry `.recent` trailing meta.
    private var lane1Options: [ComposerOption] {
        Self.composeLane1(
            pinned: pinnedOptions,
            recent: filteredRecentOptions.map { $0.withTrailingMeta(.recent) }
        )
    }

    /// Pure composition of lane 1 — extracted as a static, directly
    /// testable seam (this file's established pattern, e.g.
    /// `SessionComposerStore.resolveLaunchTemplate`) because `onAppear`'s
    /// `selectedIndex = bestSelectionIndex(in: flattenedOptions)` seeds off
    /// `flattenedOptions[0]`, i.e. THIS array's first element whenever the
    /// query is blank (`SessionComposerRanking.bestMatchIndex` returns 0 for
    /// a blank query) — and neither `flattenedOptions` nor `onAppear`'s
    /// `@State` write is otherwise reachable from a test (no SwiftUI
    /// view-test harness in this repo). G-F8: pinned options always precede
    /// non-pinned recents here, so a pin existing moves index 0 from "most
    /// recent" to "top pinned" — a real, deliberate first-open-Return change
    /// (11.11, flagged to Sean), proven by
    /// `SessionComposerLaneOrderingTests.composeLane1PutsThePinnedHeadAtIndexZero`.
    static func composeLane1(pinned: [ComposerOption], recent: [ComposerOption]) -> [ComposerOption] {
        let pinnedIds = Set(pinned.map { $0.id })
        let recentMinusPinned = recent.filter { !pinnedIds.contains($0.id) }
        return pinned + recentMinusPinned
    }

    /// Rest-state cap for the TEMPLATES and PROJECTS lanes (Sean, 2026-08-30):
    /// a blank query showed 1 recent + 6 templates + 6 projects, scrolling
    /// past the fold. Matches the precedent already set by
    /// `SessionComposerStore.maxRecents`, which has always capped RECENT at
    /// 3 — this just extends the same number to the other two lanes.
    /// Rest-state only: a non-blank query is never capped, since hiding a
    /// filtered match defeats the point of searching for it.
    private static let restStateLaneCap = 3

    /// Pure seam behind the rest-state cap — extracted (this file's
    /// established pattern, e.g. `composeLane1`) so "cap applies only at a
    /// blank query, after ordering" is directly testable without a SwiftUI
    /// view-test harness. Callers pass their lane's already-ordered options;
    /// a non-blank `query` returns them unchanged.
    static func applyRestStateCap(to options: [ComposerOption], query: String) -> [ComposerOption] {
        guard query.isEmpty else { return options }
        return Array(options.prefix(restStateLaneCap))
    }

    /// Lane 2 (board 11.2): remaining templates minus anything already
    /// surfaced in lane 1 (recent OR pinned) — `filteredTemplateOptions`
    /// already excludes recents; this additionally excludes pins so a
    /// pinned-but-not-recent template doesn't render twice.
    private var lane2Options: [ComposerOption] {
        let pinnedIds = Set(pinnedOptions.map { $0.id })
        let options = filteredTemplateOptions.filter { !pinnedIds.contains($0.id) }
        return Self.applyRestStateCap(to: options, query: query)
    }

    /// Query-matching projects (S2, locked decision: "the search field
    /// filters BOTH templates and projects"). Variant G (Pass C, 2026-08-30):
    /// Sean removed `projectControl` — the trailing chevron that used to be
    /// the only way to browse every project unfiltered — on the premise
    /// that "the projects were going to be in the search / input results."
    /// A blank query now populates this lane with every project instead of
    /// returning empty, so browsing moved INTO the results well rather than
    /// disappearing. Selecting a row here sets the composer's selected
    /// project; it does not start a session.
    private var filteredProjectOptions: [ComposerOption] {
        // N3: `.locked` fixes the project at the write path (`commit()`
        // resolves from the bound project, never `selectedProjectId`), so
        // letting a project row re-scope the list here would show project B
        // while `commit()` still creates in locked project A. This guard
        // stays even though the empty-query guard next to it is gone —
        // locked composers never show a PROJECTS lane at all, blank query
        // or not.
        //
        // A resolved command does NOT suppress this section (reverted —
        // that suppression was never in the brief and made a multi-word
        // project name unreachable: with projects "ghostties" and
        // "ghostties web", typing "ghostties web" resolves token 1 against
        // the first project and, with PROJECTS hidden, offers only
        // `Run "web"` — the project being named disappears from the list.
        // A mis-parse must stay recoverable, so PROJECTS keeps ranking
        // against the raw `query` exactly as it does with no command typed.
        guard !isProjectLocked else { return [] }

        guard !query.isEmpty else {
            // Blank query: `SessionComposerRanking.sorted` returns `items`
            // unfiltered AND unreordered on a blank query (see its own doc
            // comment), which would just be `store.projects`' raw storage
            // order — not a defensible rest-state order. `ProjectDropdownView`
            // (the inline picker this lane replaces as the browse route)
            // already solved "order every project with no query" via
            // `SessionComposerProjectOrdering.order`: cascade pick first,
            // then most-recently-used, then alphabetical. Reused verbatim
            // here rather than inventing a second ordering for the same
            // "browse everything" job.
            let recentIds = SessionComposerStore.shared.recentProjectIds
            let ordered = SessionComposerProjectOrdering.order(
                projects: store.projects,
                cascadePick: currentProject?.id,
                recentProjectIds: recentIds
            )
            return Self.applyRestStateCap(to: ordered.map(makeOption), query: query)
        }

        let options = store.projects.map(makeOption)
        return SessionComposerRanking.sorted(options, query: query, title: { $0.title })
    }

    /// The full flattened list, in on-screen order, used for keyboard
    /// navigation and selection clamping. COMMAND renders last — matching
    /// templates in TEMPLATES rank first, per the locked design.
    ///
    /// G-F8 (Step 2): lane 1 is now pinned-then-recent, not recent-only, so
    /// index 0 here — what `onAppear` seeds `selectedIndex` to — is the top
    /// PINNED template whenever any pin exists, not the most recent one.
    /// Deliberate consequence of pinned-first ordering (11.11 flagged to
    /// Sean), not an accident of this refactor.
    private var flattenedOptions: [ComposerOption] {
        lane1Options + lane2Options + filteredProjectOptions + commandOptions
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
        // Composer variant G (Sean's ruling, 2026-08-31): a typed `>` is the
        // deliberate, formal way to declare a branch — once the field offers
        // a create-branch/create-worktree row for it (`typedBranchCreateOffer`),
        // that row leads the list outright, ahead of the `Run "X"` row
        // sitting right next to it and ahead of text ranking. Checked BEFORE
        // the resolved-operator-template override below: an armed, unresolved
        // branch position can never coexist with a resolved operator segment
        // in the same parse (the operator position isn't reachable until
        // branch is filled — see `parsePath`'s `filled` bookkeeping), so
        // there's no real ordering conflict between the two checks, only a
        // defensive one.
        if typedBranchCreateOffer != nil,
           let index = options.firstIndex(where: { $0.id == SessionComposerCommandParser.createWorktreeRowId }) {
            return UInt(index)
        }
        // Blocker 1 (round-3 review): a resolved operator template
        // (`effectiveCommandParse.resolvedTemplateId`) wins outright over
        // text ranking — the moment an operator resolves, its remainder is
        // EMPTY (see `ParseResult.resolvedTemplateId`'s doc comment), which
        // otherwise leaves every option tied and Return launching whatever
        // section order/most-recent-first happens to put at index 0, not
        // the template the user just named.
        if let resolvedTemplateId = effectiveCommandParse.resolvedTemplateId,
           let index = options.firstIndex(where: { $0.id == resolvedTemplateId }) {
            return UInt(index)
        }
        return UInt(SessionComposerRanking.bestMatchIndex(in: options, query: templateFilterQuery, title: { $0.title }, subtitle: { $0.subtitle }))
    }

    private var reduceMotionEnabled: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // MARK: - Body

    var body: some View {
        let scheme: ColorScheme = NSColor(Color(nsColor: .windowBackgroundColor)).isLightColor ? .light : .dark

        // Shake-clearance wrapper: an 8pt clear inset on all four sides
        // (DESIGN.md §5 Layout Tokens — the nearest valid step above the
        // ±6pt shake amplitude) so the lateral translation has room.
        singleLineComposerCard
            .padding(8)
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
                // R14: open beat. `onAppear` doesn't refire on a fast
                // re-open of an already-mounted palette — see the matching
                // `onChange(focusSearchFieldTrigger)` below.
                witnessBeat = witnessBeat.next(.open)
            }
            .onChange(of: isPresented) { presented in
                if !presented {
                    composerStore.cancel()
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
            // Round-4 review, Blocker: was `.onChange(of: query)`. `query`
            // is the TRIMMED search text, so a typed trailing space (the
            // exact keystroke that resolves an implied project — see
            // `effectiveCommandParse`'s doc comment on Blocker 2) leaves
            // `query` byte-identical while `flattenedOptions` swaps to a
            // wholly different list underneath the still-stale
            // `selectedIndex`. Neither the N5 clamp (`selectedProjectId`
            // doesn't change on that keystroke) nor the F3 clamp
            // (`commandProject?.id` doesn't change when the typed token is a
            // branch, not a project name) fires either — this is the only
            // trigger that subsumes every case, since `searchText` changes
            // on every keystroke `query` does plus every one it drops.
            .onChange(of: composerStore.searchText) { _ in reselectBestMatch() }
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
                // identical, which is why this block exists as its own
                // trigger rather than relying on a `query`-keyed one (round-4
                // review later added `.onChange(of: composerStore.searchText)`
                // above, which now also fires on that keystroke, but the
                // `commandProjectRefreshTask` debounce below still needs its
                // own trigger keyed off `commandProject?.id` specifically).
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
                    commandProjectRefreshTask = _Concurrency.Task {
                        try? await _Concurrency.Task.sleep(for: .milliseconds(300))
                        guard !_Concurrency.Task.isCancelled else { return }
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
                        _Concurrency.Task { await composerStore.refreshWorktrees(for: project.rootPath, projectId: project.id) }
                    } else {
                        _Concurrency.Task { await composerStore.refreshWorktrees(for: nil, projectId: nil) }
                    }
                }
            }
            .onChange(of: composerStore.worktrees) { _ in
                // Round-6 review, Defect: `commandKnownBranchNames` reads
                // `composerStore.worktrees`, which lands async (300ms
                // debounce + git shell-out above) with `searchText`,
                // `selectedProjectId`, and `commandProject?.id` all
                // unchanged — none of the other triggers on this modifier
                // chain fire. When it lands, `effectiveCommandParse`
                // genuinely re-parses against a different branch list (a
                // token that WAS a resolved branch under the stale cache
                // can stop being one), so `flattenedOptions` can reshape
                // out from under a stale `selectedIndex` the same way a
                // keystroke does. `reselectBestMatch()`, not a bare clamp:
                // this is a real re-parse of record, same as the
                // `searchText` trigger above, not just a shorter list.
                reselectBestMatch()
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
                // R14: open beat, fast-re-open path — mirrors `onAppear`'s
                // seed above for the same reason (`onAppear` doesn't
                // reliably re-fire on a fast re-present).
                witnessBeat = witnessBeat.next(.open)
            }
    }

    // MARK: - Single-line field

    /// The one-line field (brief §1): SF Pro Text at the tuned size, reusing
    /// the ghost text field and `handle(_:)` event routing.
    /// `ghostFullPath` is blanked at rest (`query.isEmpty`) so
    /// `ComposerDescriptorGhostText` owns the rest-state hint text instead
    /// of the field's own placeholder ghost (which would otherwise always
    /// show the chevron path first, the thing Sean's rule forbids). Field
    /// text size, row size, and container width are live dials
    /// (`ComposerSingleLineTuning`).
    private var tuningDefaults: UserDefaults {
        tuningDefaultsForTesting ?? .standard
    }

    private var newStyleFieldFontSize: CGFloat {
        ComposerSingleLineTuning.fieldSize(defaults: tuningDefaults)
    }

    private var newStyleFieldLineHeight: CGFloat {
        ComposerSingleLineTuning.lineHeight(fieldSize: ComposerSingleLineTuning.fieldSize(defaults: tuningDefaults))
    }

    private var newStyleFieldWidth: CGFloat {
        ComposerSingleLineTuning.width(defaults: tuningDefaults)
    }

    /// R18 fix: the width `newStyleField` actually renders its content at.
    /// `singleLineComposerCard` wraps the field in
    /// `singleLineHorizontalPadding` on each side and then re-frames the
    /// WHOLE padded stack back to `newStyleFieldWidth` (the card's own
    /// tuned width) so the card itself never grows past that value.
    /// Framing the field at the FULL `newStyleFieldWidth` on top of that
    /// padding made the padding spill outside the card instead of insetting
    /// the text. Subtracting both paddings here is the ONE inner-content
    /// width that makes the padded stack's ideal width exactly
    /// `newStyleFieldWidth` again.
    private var newStyleFieldRenderWidth: CGFloat {
        newStyleFieldWidth - (2 * singleLineHorizontalPadding)
    }

    private var newStyleField: some View {
        ZStack(alignment: .leading) {
            ComposerDescriptorGhostText(
                descriptors: ComposerDescriptorCycle.descriptors(
                    mostRecentProjectName: currentProject?.name,
                    ghostPlaceholderPath: ghostPlaceholder
                ),
                query: query,
                opacity: 0.65,
                reduceMotion: reduceMotionEnabled
            )
            .font(.system(size: newStyleFieldFontSize, weight: .regular))
            .allowsHitTesting(false)
            .frame(width: newStyleFieldRenderWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            ComposerGhostTextField(
                query: searchTextBinding,
                fontSize: newStyleFieldFontSize,
                fontWeight: .regular,
                rowHeight: newStyleFieldLineHeight,
                focusTrigger: $composerStore.focusSearchFieldTrigger,
                hasSelection: selectedOption != nil,
                ghostFullPath: query.isEmpty ? "" : ghostFullPathForField
            ) { event in
                handle(event)
            }
            .accessibilityLabel(ComposerQueryField.accessibilityFieldLabel)
        }
        .frame(width: newStyleFieldRenderWidth, height: newStyleFieldLineHeight)
    }

    /// The classic "no worktree found" message says "Use the create-branch
    /// suggestion above" — wrong here, where there is no results list.
    /// Swaps in `SessionComposerCopy.unresolvedBranchMessageForNewStyles`
    /// ONLY when we can confirm this IS that specific message
    /// (`typedBranchResolution` is `.unresolved` for the same token
    /// `writeError` was set from) — every OTHER `writeError` string (e.g.
    /// the "still checking branches" pending message) passes through
    /// `statusStripMessage` unchanged.
    private var newStyleStatusStripMessage: String? {
        if composerStore.writeError != nil,
           case .unresolved(let token) = typedBranchResolution {
            return SessionComposerCopy.unresolvedBranchMessageForNewStyles(token: token)
        }
        return statusStripMessage
    }

    /// Status strip: the one thing that stays loud (brief §1) — rendered
    /// only when non-nil, red, directly beneath the field.
    @ViewBuilder
    private var newStyleStatusStrip: some View {
        if let newStyleStatusStripMessage {
            Text(newStyleStatusStripMessage)
                .font(.system(size: ComposerSingleLineTuning.rowSize(defaults: tuningDefaults)))
                .foregroundStyle(Color(nsColor: .systemRed))
        }
    }

    // MARK: - Single-line style (spike)

    /// Round 12: container padding scales off the field-size dial —
    /// `ComposerSingleLineTuning.verticalPadding`/`horizontalPadding`'s doc
    /// comment has the exact ratio this preserves from the shipped 8pt/16pt
    /// constants.
    private var singleLineVerticalPadding: CGFloat {
        ComposerSingleLineTuning.verticalPadding(fieldSize: ComposerSingleLineTuning.fieldSize(defaults: tuningDefaults))
    }

    private var singleLineHorizontalPadding: CGFloat {
        ComposerSingleLineTuning.horizontalPadding(fieldSize: ComposerSingleLineTuning.fieldSize(defaults: tuningDefaults))
    }

    /// Session-7 brief: the single-line card's OWN corner-radius dial —
    /// independent of `cornerRadius`/`composerClipShape` above, which stay
    /// exactly as they were. See `ComposerSingleLineTuning.defaultCornerRadius`
    /// for the default.
    private var singleLineCornerRadius: CGFloat {
        ComposerSingleLineTuning.cornerRadius(defaults: tuningDefaults)
    }

    private var singleLineClipShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: singleLineCornerRadius, style: .continuous)
    }

    /// Pure function extracted from the overlay modifier below so it's
    /// directly testable without rendering (`ComposerSingleLineStyleTests
    /// .witnessOverlayYOffsetIsSizePlusGap`) — `ghostGap` is the tunable
    /// space between the Witness sprite's bottom edge and the card's top
    /// edge, so the overlay must rise an additional `ghostGap` points
    /// beyond the sprite's own height. Round 14: the sprite's height is
    /// itself now a dial (`ComposerWitnessSize`), so this takes `size`
    /// rather than a hardcoded 24 — otherwise the gap would silently
    /// shrink or grow as Sean tunes the sprite bigger or smaller.
    static func witnessOverlayYOffset(size: CGFloat, ghostGap: CGFloat) -> CGFloat {
        -(size + ghostGap)
    }

    /// Current card chrome exactly as DESIGN.md §4 specifies
    /// (`.regularMaterial` + `windowBackgroundColor` blend, 12pt continuous
    /// radius, stroke, shadow tokens), sized to the field row only — no
    /// results list ever (brief §3). Reuses `singleLineClipShape` and the
    /// classic card's shadow tokens rather than re-deriving them. Round 12:
    /// width/padding are now dial-driven (see the two properties above and
    /// `newStyleFieldWidth`'s `.singleLine` case), and the whole chrome
    /// layer branches on `ComposerSingleLineTreatment` — `.material` is
    /// this same background/clip/stroke, byte-identical; `.glass` swaps in
    /// `NSGlassEffectView` (via `ComposerLiquidGlassBackground`) on macOS
    /// 26+ only, falling back to `.material` below that (never raising the
    /// macOS 13 floor for a fork feature, per
    /// `decision_align-to-upstream-degrade-gracefully`).
    private var singleLineComposerCard: some View {
        let backgroundColor = Color(nsColor: .windowBackgroundColor)
        let content = VStack(alignment: .leading, spacing: 8) {
            newStyleField
            newStyleStatusStrip
        }
        .padding(.vertical, singleLineVerticalPadding)
        .padding(.horizontal, singleLineHorizontalPadding)
        .frame(width: newStyleFieldWidth)

        let materialBackground = content
            .background(
                ZStack {
                    Rectangle().fill(.regularMaterial)
                    Rectangle().fill(backgroundColor).blendMode(.color)
                }
                .compositingGroup()
            )
            .clipShape(singleLineClipShape)
            .overlay(
                singleLineClipShape
                    .stroke(Color(nsColor: .tertiaryLabelColor).opacity(0.75))
            )

        return Group {
            #if compiler(>=6.2)
            if ComposerSingleLineBackgroundChoice.resolve(
                treatment: ComposerSingleLineTreatment.current(defaults: tuningDefaults),
                glassAvailable: isGlassTreatmentAvailable
            ) == .glass, #available(macOS 26.0, *) {
                content
                    .background(
                        ComposerLiquidGlassBackground(
                            cornerRadius: singleLineCornerRadius,
                            tintColor: ComposerSingleLineGlassTint.current(defaults: tuningDefaults).nsColor
                        )
                    )
                    .clipShape(singleLineClipShape)
            } else {
                materialBackground
            }
            #else
            materialBackground
            #endif
        }
        .shadow(
            color: .black.opacity(ComposerSingleLineShadowDials.opacity()),
            radius: ComposerSingleLineShadowDials.radius(),
            y: ComposerSingleLineShadowDials.yOffset()
        )
        .modifier(ShakeEffect(animatableData: shakeTrigger))
        // R14: AFTER `ShakeEffect` so the card's own no-match shake never
        // stacks a second shake onto the Witness (plan §1). Unclipped
        // because the glass/material `.clipShape` above only wraps `Group`
        // content, and `body`'s own `.padding(8)` doesn't clip either — see
        // `r14-witness-plan.md` §1 for the full unclipped-overlay reasoning.
        .overlay(alignment: .topLeading) {
            if showsWitness {
                ComposerWitnessView(
                    identity: witnessIdentity,
                    beatTrigger: witnessBeat,
                    reduceMotion: reduceMotionEnabled,
                    size: ComposerWitnessSize.size(defaults: tuningDefaults),
                    floatAmplitude: ComposerWitnessFloatAmplitude.amplitude(defaults: tuningDefaults),
                    floatHorizontalAmplitude: ComposerWitnessFloatHorizontal.amplitude(defaults: tuningDefaults),
                    floatPeriod: ComposerWitnessFloatPeriod.period(defaults: tuningDefaults),
                    opacity: ComposerWitnessOpacity.opacity(defaults: tuningDefaults),
                    beatSpeed: ComposerWitnessBeatSpeed.speed(defaults: tuningDefaults)
                )
                // R18 fix: was a hardcoded 20 — now the SAME
                // `singleLineHorizontalPadding` value the field's own text
                // is inset by (`newStyleFieldRenderWidth`'s doc comment),
                // so the ghost's leading edge lines up with the typed
                // text's leading edge instead of sitting ~10pt off it.
                // Session-7 brief: `y: -24` was flush against the sprite's
                // own bottom edge — `ComposerWitnessGap` adds the tunable
                // gap on top of the sprite's own (now dial-driven) height.
                .offset(
                    x: singleLineHorizontalPadding,
                    y: Self.witnessOverlayYOffset(
                        size: ComposerWitnessSize.size(defaults: tuningDefaults),
                        ghostGap: ComposerWitnessGap.gap(defaults: tuningDefaults)
                    )
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
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
            // R14: unknown-branch beat, fired at THIS call site (not
            // `onChange(writeError)` — a second Enter on the same
            // unresolved token would write the same string and never fire
            // `onChange` again). `.pending` (below) doesn't count.
            witnessBeat = witnessBeat.next(.unknownBranch)
            return
        case .pending:
            composerStore.rejectUnresolvedBranch(message: "Still checking branches for this project — try again in a moment.")
            return
        case .notTyped, .resolved, .isDefaultBranch:
            break
        }

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
            // R14: launch beat, before `isPresented = false` — the fade/
            // removal that follows truncates the lift, but the beat itself
            // must fire while the Witness is still mounted.
            witnessBeat = witnessBeat.next(.launch)
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
            dismissComposer()

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

        case .acceptedGhost:
            witnessBeat = witnessBeat.next(.tabAccept)
        }
    }

    /// Esc dismisses the composer. Guarded against a same-turn double-fire,
    /// the same pattern as `isHandlingNoMatchFeedback` below.
    private func dismissComposer() {
        guard !isHandlingExitCommand else { return }
        isHandlingExitCommand = true
        DispatchQueue.main.async { isHandlingExitCommand = false }
        isPresented = false
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
/// template; project options and other rows carry neither.
struct ComposerOption: Identifiable, Hashable {
    /// Trailing meta rendered on the right edge of a composer row (Composer
    /// UI 11, Step 2, board `V02Quieted222.dc.html`): a pin glyph for a
    /// pinned template, or the literal string `recent` for a non-pinned
    /// recent — never a timestamp (`lastUsedAt` was cut, G-F18).
    enum TrailingMeta: Equatable {
        case pinned
        case recent
    }

    let id: UUID
    let title: String
    let subtitle: String?
    let leadingIcon: String?
    let action: () -> Void
    let template: AgentTemplate?
    let templateGroup: SessionTemplateResolver.Group?
    let trailingMeta: TrailingMeta?

    init(
        id: UUID,
        title: String,
        subtitle: String?,
        leadingIcon: String?,
        action: @escaping () -> Void,
        template: AgentTemplate? = nil,
        templateGroup: SessionTemplateResolver.Group? = nil,
        trailingMeta: TrailingMeta? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.leadingIcon = leadingIcon
        self.action = action
        self.template = template
        self.templateGroup = templateGroup
        self.trailingMeta = trailingMeta
    }

    /// Returns a copy with `trailingMeta` replaced — every other field
    /// (including `id`, so `==`/`hash` are unaffected) untouched. Used by
    /// the pinned/recent lane builders to tag an otherwise-identical option
    /// after the fact rather than threading a meta parameter through every
    /// `makeOption` call site.
    func withTrailingMeta(_ meta: TrailingMeta?) -> ComposerOption {
        ComposerOption(
            id: id,
            title: title,
            subtitle: subtitle,
            leadingIcon: leadingIcon,
            action: action,
            template: template,
            templateGroup: templateGroup,
            trailingMeta: meta
        )
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
    /// While `true`, this field's own ↑/↓/Return handlers go quiet. No
    /// inline picker exists in the current composer, so nothing sets it.
    var isPickerOpen: Bool
    /// Step 3 (Composer UI 11 plan §3): the 11.1 ghost path when it renders
    /// (`.centered`, rest state), else the generic hint. Rendered as a
    /// layered `Text` in this view's `ZStack`, shown only while `query` is
    /// empty, rather than through `TextField`'s `prompt:` initializer:
    /// SwiftUI on macOS does not honour `.foregroundColor`/`.opacity` on a
    /// prompt `Text` (measured — the prompt route rendered at ~83% opacity
    /// against a 49% target, `#1A1A1A7E`, `DESIGN.md` §4). The overlay is
    /// safe here specifically because the field is empty in this state, so
    /// there's no horizontal scroll offset to desync against — do not reuse
    /// this pattern for non-empty text (`reference_composer-field-cannot-tint-subranges.md`).
    var placeholder: String
    var onEvent: ((KeyboardEvent) -> Void)?
    @FocusState private var isTextFieldFocused: Bool

    /// DESIGN.md §4's ghost placeholder grey went through `#1A1A1A7E`
    /// (0x7E/0xFF ≈ 0.49, measured 2.99:1 light / 3.99:1 dark against WCAG
    /// AA text contrast's 4.5:1 floor) and 0.65 (measured 4.74:1 light /
    /// 5.93:1 dark, clearing AA) before Sean, looking at the real build,
    /// called 0.50 as a deliberate contrast/legibility tradeoff for
    /// ghost-completion text — his call as design authority, not an
    /// accessibility miss. **0.50 does NOT meet WCAG AA** (measured ≈3.0:1
    /// light mode; see `ComposerDesignCallRenderTests`' evidence for the
    /// exact rendered ratio).
    /// Deliberately kept in lockstep with
    /// `ComposerGhostTextField.ghostOpacity` so the two fields render the
    /// same ghost — if you change one, change the other. A production
    /// symbol, not a re-declared literal, so a test can pin it without
    /// drifting from the value actually rendered.
    static let ghostPlaceholderOpacity: Double = 0.50

    /// DEFECT 4 fix (Composer UI 11 review round 2): a named production
    /// symbol for the field's `.accessibilityLabel`, so
    /// `AccessibilityTests` can assert against the string the field
    /// actually renders instead of a re-declared local literal that would
    /// still pass against a typo'd production string.
    static let accessibilityFieldLabel: String = "New session command"

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
        /// R14: Tab accepted a ghost-text segment (`ComposerGhostTextField
        /// .acceptGhost`, past both its guards — a Tab with nothing to
        /// accept sends nothing). Drives the Witness ghost's hop beat only;
        /// no other effect (the field already wrote the accepted text
        /// itself).
        case acceptedGhost
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

            // Ghost placeholder overlay — see `placeholder`'s doc comment
            // for why this replaces `TextField`'s `prompt:` route. Same
            // font/weight and vertical padding as the `TextField` below so
            // the metrics line up; only shown while the field is empty.
            if query.isEmpty {
                Text(placeholder)
                    .font(.system(size: fontSize, weight: .regular))
                    .foregroundColor(Color(nsColor: .labelColor).opacity(Self.ghostPlaceholderOpacity))
                    // Fix 1 (review): the deleted `resolutionSegment` code
                    // carried both of these on every segment; without them a
                    // long resolved path (this repo's own
                    // `ghostties > feat/composer-ui-11 > Orchestrator` is 45
                    // chars, over the ~42-char field width at `.centered`)
                    // wraps to a second line inside the fixed-height 38pt
                    // field instead of truncating on one.
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            TextField(
                "",
                text: $query
            )
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
                // Fix 5 (review): the deleted `resolutionLine` announced
                // "Project: <name>", "Branch: <name>", "Template: <name>" —
                // with the composer hiding the sidebar/terminal from
                // VoiceOver while open, this field is essentially the only
                // accessible content, so losing that with no replacement
                // meant a screen-reader user learned the destination only
                // AFTER pressing Return. `accessibilityValue` reuses the
                // exact same source the ghost `Text` renders (`placeholder`)
                // while the field is empty — the resolved destination Return
                // would currently commit — and falls back to the literal
                // typed text once there's something typed, matching
                // `TextField`'s own default announcement (which this
                // override replaces). The ghost `Text` itself stays
                // `.accessibilityHidden(true)` — decorative once its value
                // is carried here.
                .accessibilityLabel(Self.accessibilityFieldLabel)
                .accessibilityValue(query.isEmpty ? placeholder : query)
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

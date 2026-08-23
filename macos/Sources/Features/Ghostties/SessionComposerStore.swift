import AppKit
import Foundation
import SwiftUI

/// Describes how a `SessionComposerPalette` was invoked (Phase 2 of
/// session-creation-unified). Nothing else parameterizes the composer.
struct SessionComposerRequest {
    /// How the composer is presented. Only `.anchored` (the sidebar
    /// popover) is built in Phase 2 — `.centered` is declared now so the
    /// type is stable, but Phase 3 is the first caller to actually use it.
    enum Presentation: Equatable {
        case anchored
        case centered
    }

    /// How the project is bound at open time.
    enum ProjectBinding {
        /// The project is fixed and cannot be changed from inside the
        /// composer (the sidebar's per-project "+ New Session").
        case locked(Project)
        /// The project starts pre-selected but the user can change it via
        /// the trailing dropdown.
        case prefilled(Project)
        /// No project pre-selected — the smart-default cascade decides.
        case open
    }

    let presentation: Presentation
    let projectBinding: ProjectBinding
}

/// A `(project, template)` pair recorded on commit, most-recent-first, for
/// the composer's RECENT section. Persisted as JSON via `defaults` since
/// `AppStorage` has no native support for `Codable` arrays.
struct RecentComposerSelection: Codable, Equatable {
    let projectId: UUID
    let templateId: UUID
}

/// State machine and commit logic for the session composer (Phase 2,
/// D3/D11). Mirrors `NewTaskComposerStore`'s shape deliberately — same
/// singleton pattern, same open/focus/cancel vocabulary — but it is a
/// separate type: the composer commits by calling
/// `SessionCoordinator.createQuickSession(for:template:)`, it never writes
/// a `.md` task file, and it has no title field (an unpinned session's name
/// is its live terminal title — locked decision, never re-add one).
@MainActor
final class SessionComposerStore: ObservableObject {

    // MARK: - Shared instance

    static let shared = SessionComposerStore()

    /// The `UserDefaults` domain persisted state is read/written through.
    /// Injectable so `isolatedForTesting:` gets a private domain instead of
    /// silently writing real app state (`.standard`) — see that initializer.
    private let defaults: UserDefaults

    private init() {
        self.defaults = .standard
    }

    #if DEBUG
    /// Test-only initialiser — a private `UserDefaults` suite, no singleton
    /// side-effects, and no risk of a test polluting real recents.
    init(isolatedForTesting: Void) {
        self.defaults = UserDefaults(suiteName: "ghostties.sessionComposerStore.test.\(UUID().uuidString)") ?? .standard
    }
    #endif

    // MARK: - Visibility

    @Published private(set) var isOpen: Bool = false

    /// The window that most recently opened the CENTERED composer overlay
    /// (Phase 3 review round 3, Blocker 3). This store is one process-wide
    /// singleton, but only one workspace window's overlay should be "the"
    /// composer at a time — without this, two windows could each install
    /// their own overlay against the same shared state (`selectedProjectId`/
    /// `searchText`/`currentProjectBinding`), each visibly showing
    /// whichever window opened last, with Escape in either tearing down
    /// both. `WorkspaceViewContainer.presentComposerOverlay` writes this on
    /// every CENTERED-overlay open (dismissing any other window's overlay
    /// first); its `$isOpen` sink and `dismissComposerOverlayIfPresented`
    /// check it before acting.
    ///
    /// Deliberately NOT written by the ANCHORED popover's `open()` call
    /// (`SessionComposerPalette.swift`'s `.onAppear`) — a row popover in
    /// window B while window A's centered overlay is up still leaves two
    /// composers live against the shared store. That's pre-existing
    /// behavior (the round-2 `NSApp.isActive` gate produced the same
    /// outcome) and explicitly out of scope here — not chased by this
    /// property, which only arbitrates between CENTERED overlays.
    ///
    /// `weak` so this never keeps a window alive and simply reads `nil`
    /// once one is gone.
    weak var owningWindow: NSWindow?

    /// When true, the search field should receive first responder on the
    /// next render cycle. Cleared by the view after the focus request is
    /// consumed. Mirrors `NewTaskComposerStore.focusTitleFieldTrigger`.
    @Published var focusSearchFieldTrigger: Bool = false

    // MARK: - Field state

    @Published var selectedProjectId: UUID?
    @Published var searchText: String = ""

    // MARK: - Worktree cache (Slice B, B1)

    /// Cached `git worktree list --porcelain` results for the currently
    /// selected project, minus the project's own root worktree (the store
    /// filters that out here, not in `GitWorktreeEnumerator`, since only the
    /// store knows which path is "the project itself"). No UI reads this
    /// yet — the branch chip's picker is a later step.
    @Published private(set) var worktrees: [GitWorktreeEnumerator.Worktree] = []

    /// Local branches with no worktree anywhere yet — the branch chip
    /// picker's second, disabled-for-now group (B3; B4 wires up creation).
    /// Populated on the SAME refresh as `worktrees`, never by a second
    /// racing task — see `refreshWorktrees(for:)`.
    @Published private(set) var branchesWithoutWorktree: [String] = []

    /// The branch checked out at the project's own root — i.e. what "no
    /// override" resolves to. Backs the picker's "Default (<branch>)" row.
    /// Populated on the same refresh as `worktrees`/`branchesWithoutWorktree`.
    @Published private(set) var currentBranchAtProjectRoot: String?

    /// The branch chip's current pick: a worktree path to launch the
    /// session in, overriding `project.rootPath` at commit time (`precommit`).
    /// `nil` means "no override" — the picker's "Default" row, and the
    /// state after `open(...)`/`cancel()` reset it. Reset in BOTH of those
    /// (not just one) is load-bearing: this store is a process-wide
    /// singleton, so leaving a stale path set across a `cancel()` +
    /// reopen-on-a-different-project would launch a session into a
    /// DIFFERENT project's worktree — silently, with no error, wrong cwd.
    @Published var selectedWorktreePath: String?

    /// Set for the duration of a `refreshWorktrees` call so a later step's
    /// picker can show a loading state instead of a silent empty list.
    @Published private(set) var isRefreshingWorktrees: Bool = false

    /// Monotonic counter guarding against a stale `refreshWorktrees` call
    /// landing after a newer one — this store is a process-wide singleton,
    /// so a slow enumeration for project A must not overwrite project B's
    /// already-returned result if the user switched projects (or reopened
    /// the composer) before A's `Task.detached` finished.
    private var worktreeRefreshToken: Int = 0

    /// Re-enumerates worktrees for `repoPath` off the main actor, discarding
    /// the result if a newer call has since been made. 2-second timeout —
    /// matches `SessionCoordinator.createSession`'s detached-task-plus-timeout
    /// shape — so a hung or missing `git` never hangs the composer; it just
    /// yields an empty list.
    @MainActor
    func refreshWorktrees(for repoPath: String?) async {
        worktreeRefreshToken += 1
        let token = worktreeRefreshToken

        guard let repoPath else {
            worktrees = []
            branchesWithoutWorktree = []
            currentBranchAtProjectRoot = nil
            isRefreshingWorktrees = false
            return
        }

        // Deliberately NOT blanked here — a refresh in flight must keep
        // rendering whatever the previous result was (the branch picker
        // shows a trailing "Refreshing…" row via `isRefreshingWorktrees`
        // instead), or the list collapses and jumps under the cursor on
        // every reopen.
        isRefreshingWorktrees = true

        // One detached task computing BOTH results off a single token
        // check — never two racing tasks each racing the other's
        // `worktreeRefreshToken` write.
        let listTask = Task.detached(priority: .userInitiated) { () -> ([GitWorktreeEnumerator.Worktree], [String]) in
            let rawList = GitWorktreeEnumerator.list(repoPath: repoPath)
            let branches = GitWorktreeEnumerator.branchesWithoutWorktree(repoPath: repoPath)
            return (rawList, branches)
        }
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(2))
            listTask.cancel()
        }
        let (rawList, branches) = await listTask.value
        timeoutTask.cancel()

        // Discard if a newer refresh has since been kicked off. Already back
        // on the main actor here (this method is `@MainActor`) — no
        // `MainActor.run` needed.
        guard token == worktreeRefreshToken else { return }

        worktrees = rawList.filter { $0.path != repoPath }
        currentBranchAtProjectRoot = rawList.first(where: { $0.path == repoPath })?.branch
        branchesWithoutWorktree = branches
        isRefreshingWorktrees = false
    }

    /// The binding this open() call was made with, retained so `commit()`
    /// can enforce `.locked` at the write path even if `selectedProjectId`
    /// has drifted (Phase 3 is the first caller that relies on `.locked`
    /// meaning locked).
    private(set) var currentProjectBinding: SessionComposerRequest.ProjectBinding = .open

    /// The `WorkspaceStore` passed to the most recent `open(...)` call,
    /// retained weakly so `changeProjectChip(to:currentlyShown:)` — which
    /// `SessionComposerPalette` calls without a `WorkspaceStore` argument —
    /// can still resolve the newly-chosen project's `rootPath` to trigger a
    /// worktree refresh. `weak` because this store outlives any one
    /// workspace window; it must never keep one alive.
    private weak var cachedWorkspaceStore: WorkspaceStore?

    // MARK: - Error state

    @Published private(set) var writeError: String?

    // MARK: - Recent (project, template) pairs

    private static let recentSelectionsKey = "ghostties.sessionComposerRecentSelections"
    private static let maxRecents = 3

    private var recentSelectionsData: Data {
        get { defaults.data(forKey: Self.recentSelectionsKey) ?? Data() }
        set { defaults.set(newValue, forKey: Self.recentSelectionsKey) }
    }

    var recentSelections: [RecentComposerSelection] {
        (try? JSONDecoder().decode([RecentComposerSelection].self, from: recentSelectionsData)) ?? []
    }

    private func recordRecent(projectId: UUID, templateId: UUID) {
        var current = recentSelections
        let entry = RecentComposerSelection(projectId: projectId, templateId: templateId)
        current.removeAll { $0 == entry }
        current.insert(entry, at: 0)
        if current.count > Self.maxRecents {
            current = Array(current.prefix(Self.maxRecents))
        }
        recentSelectionsData = (try? JSONEncoder().encode(current)) ?? Data()
    }

    // MARK: - Recent project ids (separate from `recentSelections`)

    /// Deduped by PROJECT, most-recent-first, longer than `maxRecents` —
    /// `recentSelections` is capped at 3 pairs and deduped on the pair, so a
    /// user who runs three templates in one project fills all three slots
    /// with that one project and the dropdown's "recently used" tier
    /// degenerates to a single entry. This is the project-only MRU the
    /// dropdown ordering and the smart-default cascade both read from.
    private static let recentProjectIdsKey = "ghostties.sessionComposerRecentProjectIds"
    private static let maxRecentProjects = 10

    var recentProjectIds: [UUID] {
        guard let strings = try? JSONDecoder().decode([String].self, from: recentProjectIdsData) else { return [] }
        return strings.compactMap { UUID(uuidString: $0) }
    }

    private var recentProjectIdsData: Data {
        get { defaults.data(forKey: Self.recentProjectIdsKey) ?? Data() }
        set { defaults.set(newValue, forKey: Self.recentProjectIdsKey) }
    }

    private func recordRecentProject(_ projectId: UUID) {
        var current = recentProjectIds
        current.removeAll { $0 == projectId }
        current.insert(projectId, at: 0)
        if current.count > Self.maxRecentProjects {
            current = Array(current.prefix(Self.maxRecentProjects))
        }
        recentProjectIdsData = (try? JSONEncoder().encode(current.map(\.uuidString))) ?? Data()
    }

    // MARK: - Open / focus / cancel

    /// Open the composer for `projectBinding`. If already open, the reset
    /// and binding are STILL re-applied (only the "second instance" early
    /// exit is skipped) — otherwise a popover that was orphaned by its
    /// hosting row leaving the hierarchy (project removed, sidebar
    /// view-mode switch, `windowDidResignKey`/`mouseExited` closing the
    /// popover without the row's `@State` transitioning) leaves `isOpen`
    /// latched `true` forever, and the next open() for a DIFFERENT project
    /// silently reuses the stale `selectedProjectId` (D3/D11 regression;
    /// see also the `.onDisappear` teardown in `SessionComposerPalette`).
    func open(projectBinding: SessionComposerRequest.ProjectBinding, workspaceStore: WorkspaceStore) {
        let wasOpen = isOpen

        searchText = ""
        writeError = nil
        currentProjectBinding = projectBinding
        pendingChipUndo = nil
        worktrees = []
        // B3: reset on EVERY open(), not just when a project actually
        // changes — this store is a process-wide singleton, so a stale
        // `selectedWorktreePath` left over from a PRIOR project would
        // otherwise launch the next session into a DIFFERENT project's
        // worktree path (silent, wrong cwd, no error).
        branchesWithoutWorktree = []
        currentBranchAtProjectRoot = nil
        selectedWorktreePath = nil
        cachedWorkspaceStore = workspaceStore

        switch projectBinding {
        case .locked(let project), .prefilled(let project):
            selectedProjectId = project.id
        case .open:
            selectedProjectId = resolveDefaultProject(workspaceStore: workspaceStore)
        }

        if wasOpen {
            focusSearchFieldTrigger = true
        }
        isOpen = true

        if let projectId = selectedProjectId,
           let project = workspaceStore.projects.first(where: { $0.id == projectId }) {
            Task { await self.refreshWorktrees(for: project.rootPath) }
        }
    }

    /// Close the composer without writing anything (Esc / cancel / popover
    /// teardown). Idempotent — safe to call from `.onDisappear` even if
    /// `cancel()` already ran via `onChange(of: isPresented)`.
    func cancel() {
        isOpen = false
        searchText = ""
        writeError = nil
        pendingChipUndo = nil
        worktrees = []
        // See the matching reset in `open(...)` — this store is a
        // process-wide singleton and must never carry a worktree pick
        // across into whatever project opens next.
        branchesWithoutWorktree = []
        currentBranchAtProjectRoot = nil
        selectedWorktreePath = nil
    }

    // MARK: - Commit

    /// Validate and record the recent pair, SYNCHRONOUSLY, then dispatch
    /// session creation without waiting on it. This is the ONLY write path
    /// — it calls `coordinator.createQuickSession(for:template:)` and
    /// nothing else (ship gate 5).
    ///
    /// Split from a single `async` `commit()` (N1): the prior shape awaited
    /// `createQuickSession`, which shells out to resolve the binary path
    /// with a 3-second timeout — so the view stayed presented for up to 3s
    /// after the query had already blanked and the new session was already
    /// showing behind the still-open composer. The pre-check below is the
    /// only part that can still fail with something to show on screen
    /// (`writeError`), so it is what the view dismisses on; the spawn is
    /// fired from a detached `Task` the view does not await.
    ///
    /// Returns `true` once the project has been validated and the session
    /// creation call has been dispatched, `false` if the pre-check failed
    /// (`writeError` is set in that case and the caller must NOT dismiss —
    /// dismissing before this returns is exactly the bug where the popover
    /// vanished with no session and no visible message).
    ///
    /// Double-Return protection lives in `SessionComposerPalette.commit(template:)`'s
    /// synchronous `selectedIndex = nil` (see that function), not here —
    /// this function has no suspension point for a second call to land in.
    @discardableResult
    func precommit(
        template: AgentTemplate,
        coordinator: SessionCoordinator,
        workspaceStore: WorkspaceStore
    ) -> Bool {
        // R3 (Phase 3 review round 2): the keyboard path's double-Return
        // guard (`SessionComposerPalette.commit(template:)` nil-ing
        // `selectedIndex` synchronously) doesn't cover the mouse path —
        // `ComposerRow`'s `Button(action:)` calls `option.action()` directly
        // and never reads `selectedIndex`. A fast double-click on a
        // template row (well inside the system's ~500ms double-click
        // interval, especially during the centered overlay's 0.2s
        // dismiss-fade before hit-testing is disabled) could otherwise fire
        // `precommit` twice and create two sessions. `isOpen` is already set
        // `false` synchronously below on the first successful call, so this
        // guard rejects the second one for free.
        guard isOpen else { return false }

        // `.locked` enforces at the write path — resolved from the bound
        // project, never from `selectedProjectId` — so the enum case isn't
        // decorative once Phase 3 starts relying on it. `.prefilled`/`.open`
        // resolve from `selectedProjectId` as before, since the user is
        // allowed to change the project for those bindings.
        let resolvedProjectId: UUID?
        if case .locked(let lockedProject) = currentProjectBinding {
            resolvedProjectId = lockedProject.id
        } else {
            resolvedProjectId = selectedProjectId
        }

        guard let projectId = resolvedProjectId,
              let project = workspaceStore.projects.first(where: { $0.id == projectId }) else {
            writeError = "Selected project no longer exists."
            return false
        }

        // B3: the branch chip's pick, if any, overrides the LOCAL copy of
        // the template's `workingDirectory` — `SessionCoordinator` itself
        // is never touched (it already reads
        // `template.workingDirectory ?? project.rootPath`). Checked here,
        // synchronously, so a worktree that vanished between pick and
        // commit (pruned by another session, branch deleted) surfaces a
        // `writeError` instead of silently launching into a stale/missing
        // path.
        var launchTemplate = template
        if let worktreePath = selectedWorktreePath {
            guard FileManager.default.fileExists(atPath: worktreePath) else {
                writeError = "Worktree no longer exists at \(worktreePath)."
                return false
            }
            launchTemplate.workingDirectory = worktreePath
        }

        writeError = nil
        recordRecent(projectId: projectId, templateId: template.id)
        recordRecentProject(projectId)
        isOpen = false
        searchText = ""

        // N2: fire-and-forget from here on. The composer is already
        // dismissed by the time this runs, so a genuine spawn failure
        // (`ghostty.app` nil, CEF-init failure for browser templates) has
        // no composer left to surface it into. This is exactly the
        // existing Option-click instant-create path's behaviour today —
        // the composer is at parity, not newly regressed.
        Task.detached { [coordinator, launchTemplate] in
            _ = await coordinator.createQuickSession(for: project, template: launchTemplate)
        }

        return true
    }

    // MARK: - Project selection

    /// The single write path for changing `selectedProjectId` from any of
    /// the composer's project-selection controls (search-result row,
    /// trailing dropdown, "+ Add project…"). Clears `searchText` alongside
    /// the id: a query that scoped the OLD project (e.g. "ghos", used to
    /// find the project itself) almost never matches anything in the newly
    /// selected project's own templates, so leaving it in place silently
    /// empties the results list and strands the user on a dead field
    /// (fixed in PR #132 review, round 2 — F2). Hoisted here rather than
    /// duplicated at each call site so the fix can't be applied to two
    /// sites and missed on a third again.
    func selectProject(_ id: UUID) {
        selectedProjectId = id
        searchText = ""
    }

    /// Pop the breadcrumb chip back into raw editable text (A5): clear the
    /// selection and replace `searchText` with the given project name.
    /// `selectProject(_:)` doesn't fit here — it clears `searchText`, and
    /// this operation needs to SET it to the popped project's name — so this
    /// is its own single write path for the same reason `selectProject(_:)`
    /// is one: `SessionComposerPalette.popChipToText()` used to write
    /// `selectedProjectId` directly, which is exactly the "fix applied to
    /// two sites and missed on a third" failure this file's `selectProject(_:)`
    /// doc comment already warns about.
    func popChipToText(projectName: String) {
        selectedProjectId = nil
        searchText = projectName
    }

    // MARK: - Breadcrumb chip cascade + undo (Slice A)

    /// Whether `changeProjectChip(to:currentlyShown:)` actually cascaded or
    /// was a no-op. Exposed so callers (and tests) can assert on the exact
    /// branch rather than inferring it from state deltas.
    enum ProjectChipChangeResult: Equatable {
        case changed
        case noOp
    }

    /// What the most recent `changeProjectChip` cascade cleared, restorable
    /// as ONE step via `undoProjectChipChange()` (breadcrumb spec, decision
    /// #2, ⌘Z). `nil` once restored, once a fresh cascade overwrites it, or
    /// before any cascade has happened.
    /// `@Published` (D4 fix / fragility note): this was a plain `var` before
    /// — the ⌘Z `Button` in `SessionComposerPalette` only ever appeared
    /// because `changeProjectChip` happens to touch OTHER published state
    /// (`selectedProjectId`/`searchText`) one line after setting this, which
    /// incidentally forced a re-render. Nothing guaranteed that ordering;
    /// publishing this directly is what actually makes the ⌘Z affordance's
    /// appearance/disappearance a real, provable contract.
    /// B3: extended with `previousWorktreePath` so ⌘Z restores project +
    /// branch + command as ONE step — the cascade rule clears the branch
    /// chip alongside the project (a branch name is meaningless in another
    /// repo), so its undo has to travel with the same tuple or restoring
    /// project/search text without the branch would silently leave the
    /// wrong worktree armed.
    @Published private(set) var pendingChipUndo: (previousProjectId: UUID?, previousSearchText: String, previousWorktreePath: String?)?

    /// Change the project chip to `projectId`, cascading per the breadcrumb
    /// spec's decision #2: the typed remainder is branch-agnostic today, but
    /// a different project invalidates it (a different project's templates
    /// don't apply), so the cascade clears `searchText` alongside the id —
    /// exactly `selectProject(_:)`'s existing behavior, reused rather than
    /// duplicated.
    ///
    /// `currentlyShown` is the id the CHIP is actually rendering right now —
    /// which the palette derives as `currentProject?.id` and can differ from
    /// `selectedProjectId` when a typed command has resolved a different
    /// project (`commandProject`). Comparing against the displayed identity,
    /// not the raw stored one, is what makes decision #2's "re-picking the
    /// value already selected is a no-op, not a clear" hold for the
    /// typed-command path too.
    @discardableResult
    func changeProjectChip(to projectId: UUID, currentlyShown: UUID?) -> ProjectChipChangeResult {
        guard projectId != currentlyShown else { return .noOp }
        pendingChipUndo = (
            previousProjectId: selectedProjectId,
            previousSearchText: searchText,
            previousWorktreePath: selectedWorktreePath
        )
        selectProject(projectId)
        // B3: a different project invalidates the branch chip too — a
        // branch name is meaningless in another repo (spec's cascade
        // rule) — so it cascades alongside `searchText`, captured in the
        // same undo tuple above.
        selectedWorktreePath = nil

        if let project = cachedWorkspaceStore?.projects.first(where: { $0.id == projectId }) {
            Task { await self.refreshWorktrees(for: project.rootPath) }
        }

        return .changed
    }

    /// Restore the segment(s) cleared by the most recent `changeProjectChip`
    /// cascade, as one step (⌘Z). A no-op if nothing is pending — e.g. a
    /// second ⌘Z in a row, or no chip change has happened yet this session.
    func undoProjectChipChange() {
        guard let pending = pendingChipUndo else { return }
        selectedProjectId = pending.previousProjectId
        searchText = pending.previousSearchText
        selectedWorktreePath = pending.previousWorktreePath
        pendingChipUndo = nil
    }

    // MARK: - Branch chip (Slice B, B3)

    /// Mirrors `ProjectChipChangeResult` — reused rather than duplicated
    /// with a different name, since the two enums would be structurally
    /// identical.
    typealias BranchChipChangeResult = ProjectChipChangeResult

    /// Pick a worktree for the branch chip. Per the spec's cascade rule,
    /// changing the BRANCH clears nothing else (a command is branch-agnostic
    /// — `cco -n "xyz"` means the same thing on any branch) and arms no
    /// ⌘Z undo — only a PROJECT change does that. Re-picking the value
    /// already shown is a no-op, matching `changeProjectChip`'s same rule.
    @discardableResult
    func changeBranchChip(to worktreePath: String, currentlyShown: String?) -> BranchChipChangeResult {
        guard worktreePath != currentlyShown else { return .noOp }
        selectedWorktreePath = worktreePath
        return .changed
    }

    /// The picker's "Default (<branch>)" row — clears the override back to
    /// "wherever the project points right now" (`project.rootPath`). Arms
    /// no undo, same reasoning as `changeBranchChip`.
    func clearBranchChip() {
        selectedWorktreePath = nil
    }

    /// D4 fix: disarm the pending chip-undo the moment the user types
    /// anything by hand. `changeProjectChip` itself also writes `searchText`
    /// (clearing it as part of the cascade this undo exists to restore) —
    /// that write goes through `selectProject(_:)`, NOT this method, so it
    /// can't disarm the very undo it just armed. Only
    /// `SessionComposerPalette.queryFieldText`'s setter (real keystrokes)
    /// calls this. Without it, ⌘Z after typing past a chip change discarded
    /// those keystrokes with no way back — AppKit's own text-undo never saw
    /// them (this binding writes `searchText` directly, bypassing the field
    /// editor's undo manager), so a second ⌘Z couldn't recover them either.
    func noteSearchTextEditedByTyping() {
        pendingChipUndo = nil
    }

    // MARK: - Add project via NSOpenPanel

    /// Invoked from the open project dropdown's "+ Add project…" row.
    /// Opens `NSOpenPanel`, adds the project, auto-selects it, and records
    /// it as the most-recent project so it becomes the cascade default
    /// (mirrors `NewTaskComposerStore.addProjectViaPanel` setting
    /// `mruProjectId`) — without closing the composer (ship gate 2).
    func addProjectViaPanel(workspaceStore: WorkspaceStore) {
        guard let newId = workspaceStore.addProjectViaFolderPicker() else { return }
        selectProject(newId)
        recordRecentProject(newId)
    }

    // MARK: - Smart-default cascade

    /// Resolves the same three-step smart-default cascade used by `open(projectBinding: .open, ...)`,
    /// without opening the composer UI. Phase 3's instant-create paths
    /// (Cmd+Shift+T, and Cmd+T when `ghostties.newSessionOpensComposer` is
    /// off) need the cascade pick but must never touch `isOpen` or any of
    /// the other UI-facing state `open()` resets.
    func resolveCascadeProject(workspaceStore: WorkspaceStore) -> UUID? {
        resolveDefaultProject(workspaceStore: workspaceStore)
    }

    /// Same three-step cascade as `NewTaskComposerStore.resolveDefaultProject`
    /// (cwd of the frontmost terminal -> MRU -> most-recently-touched).
    /// Duplicated rather than shared: `NewTaskComposerStore` is a boundary
    /// file for this phase (it commits a `.md` task file the session
    /// composer must never touch), so its cascade is private and not
    /// reachable from here without editing that file.
    private func resolveDefaultProject(workspaceStore: WorkspaceStore) -> UUID? {
        let projects = workspaceStore.projects
        guard !projects.isEmpty else { return nil }

        if let cwdMatch = resolveFromFrontmostTerminal(projects: projects) {
            return cwdMatch
        }

        if let mru = recentProjectIds.first, projects.contains(where: { $0.id == mru }) {
            return mru
        }

        let sorted = projects.sorted {
            switch ($0.lastActiveAt, $1.lastActiveAt) {
            case let (a?, b?): return a > b
            case (_?, nil): return true
            default: return false
            }
        }
        return sorted.first?.id
    }

    private func resolveFromFrontmostTerminal(projects: [Project]) -> UUID? {
        guard let keyWindow = NSApp.keyWindow else { return nil }
        let windowTitle = keyWindow.title

        for project in projects {
            let rootURL = URL(fileURLWithPath: project.rootPath)
            let basename = rootURL.lastPathComponent
            if windowTitle == basename || windowTitle.hasPrefix(project.rootPath) {
                return project.id
            }
        }
        return nil
    }
}

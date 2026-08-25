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

    /// Same isolation as `init(isolatedForTesting:)`, but pinned to a
    /// CALLER-CHOSEN suite name rather than a fresh random one each call —
    /// the one thing that initializer can't do is let a test construct a
    /// SECOND `SessionComposerStore` instance reading the SAME persisted
    /// UserDefaults suite the first one wrote to, which is what proves pin
    /// persistence is actually durable state and not an in-memory cache
    /// (`SessionComposerPinningTests`).
    init(isolatedForTesting suiteName: String) {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// Test-only override for `precommit`'s session-dispatch call — see the
    /// finding 9 fix at that call site for why this exists.
    var dispatchOverrideForTesting: ((Project, AgentTemplate) -> Void)?
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

    /// BL-1 fix (Slice B review round 3): `selectProject(_:)`'s doc comment
    /// claimed to be "the single write path for changing `selectedProjectId`
    /// from any of the composer's project-selection controls", but three
    /// reachable routes bypassed the cascade it (and `changeProjectChip`)
    /// used to implement by hand: `makeOption(for project:)`'s Return-on-row
    /// action, `addProjectViaPanel`, and — the one that actually broke, with
    /// no timing window required — `SessionComposerPalette.commit(template:)`
    /// writing `selectedProjectId` DIRECTLY when a typed `<project>
    /// <remainder>` command resolved a project the picker never selected.
    /// That last route left `selectedWorktreePath` (and the whole worktree
    /// cache) pointed at whatever the PREVIOUS project's branch chip had
    /// picked — a session for the new project silently launched with cwd
    /// inside the old project's worktree, no error, no timing window.
    ///
    /// The fix moves the cascade to the STATE layer via `didSet` rather than
    /// re-auditing every call site again: every write to this property —
    /// present or future — now cascades automatically, so a fourth route
    /// added later can't reopen this same class of bug. `open(...)` is the
    /// one caller that legitimately wants to skip it (it already performs
    /// its own full reset before assigning, and immediately kicks its own
    /// single refresh — see `suppressProjectChangeCascade`).
    @Published var selectedProjectId: UUID? {
        didSet {
            guard !suppressProjectChangeCascade else { return }
            guard selectedProjectId != oldValue else { return }
            cascadeProjectChange(to: selectedProjectId)
        }
    }

    /// Set for the duration of `open(...)`'s own `selectedProjectId`
    /// assignment — that method already performs the full reset
    /// `cascadeProjectChange(to:)` would otherwise repeat, and kicks its own
    /// single refresh `Task` right after. Without this, every `open()` fired
    /// TWO racing refreshes for the same project (harmless — both are
    /// `worktreeRefreshToken`-guarded — but wasteful on every popover open).
    private var suppressProjectChangeCascade = false

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

    /// Whether the current project is a git repo AT ALL — derived from
    /// `GitWorktreeEnumerator.list(repoPath:)`'s UNFILTERED result (non-empty
    /// means yes), never from whether `worktrees`/`branchesWithoutWorktree`
    /// found anything to OFFER (blocker 6, Slice B review round 1). Those
    /// two lists both exclude cases that still mean "yes, a repo" —
    /// `worktrees` excludes the project's own root, `branchesWithoutWorktree`
    /// excludes every already-claimed branch — so a repo with exactly one
    /// branch checked out at its own root (the most common first-run state)
    /// satisfied neither, and the branch chip never appeared. This is what
    /// `SessionComposerPalette.isBranchSegmentEligible` reads instead.
    @Published private(set) var isGitRepo: Bool = false

    /// The project id `worktrees`/`branchesWithoutWorktree`/
    /// `currentBranchAtProjectRoot`/`isGitRepo` currently describe — `nil`
    /// only in the "nothing selected yet" state. Blocker 2 fix (Slice B
    /// review round 2): a typed branch used to resolve against WHATEVER
    /// this cache last held, regardless of which project the composer's
    /// command grammar had actually resolved for. Repro: composer opens on
    /// project A (cache holds A's worktrees); typing `<project B> >
    /// <branch name that happens to match one of A's worktrees>
    /// <remainder>` matched A's stale cache under B's name and launched a
    /// session in B with cwd silently pointed at one of A's worktrees — no
    /// error. Every caller resolving a typed branch (see
    /// `SessionComposerPalette.typedBranchResolution`) must check this
    /// against the project it's resolving FOR before trusting `worktrees`.
    @Published private(set) var worktreesProjectId: UUID?

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

    /// Set for the duration of a `createWorktree` call (B4) — the branch
    /// chip renders "Creating…" instead of the (still-unset) branch name
    /// while `git worktree add` runs. The picker is already closed by the
    /// time this is true (`SessionComposerPalette`'s `onCreateWorktree`
    /// closure closes it in the same statement it calls `createWorktree`),
    /// so this is read by the chip label alone.
    @Published private(set) var isCreatingWorktree: Bool = false

    /// Monotonic counter guarding a `createWorktree` result (success,
    /// failure, or timeout) that lands after a newer creation call — or a
    /// `cancel()`/`open()` on a different project — has superseded it.
    /// Same shape as `worktreeRefreshToken`, for the same reason: this
    /// store is a process-wide singleton, so a slow `git worktree add`
    /// finishing after the composer moved on must not write `writeError`
    /// or `selectedWorktreePath` into whatever context is current by then.
    private var worktreeCreationToken: Int = 0

    /// Monotonic counter guarding against a stale `refreshWorktrees` call
    /// landing after a newer one — this store is a process-wide singleton,
    /// so a slow enumeration for project A must not overwrite project B's
    /// already-returned result if the user switched projects (or reopened
    /// the composer) before A's `Task.detached` finished.
    private var worktreeRefreshToken: Int = 0

    /// Re-enumerates worktrees for `repoPath` off the main actor, discarding
    /// the result if a newer call has since been made. 2-second timeout via
    /// `race(_:timeoutSeconds:)` — should-fix 7 (Slice B review round 1)
    /// FIXED a false claim this doc comment used to make: the previous
    /// shape called `listTask.cancel()` on a timeout and then still
    /// `await`ed `listTask.value`, which does not return early against a
    /// blocking `Process.waitUntilExit()` (cancellation is cooperative —
    /// nothing inside `GitWorktreeEnumerator.list`/`branchesWithoutWorktree`
    /// checks `Task.isCancelled`). A hung `git` left `isRefreshingWorktrees`
    /// stuck true forever, showing "Refreshing…" permanently, with every
    /// reopen spawning another hung process on top. `race(_:timeoutSeconds:)`
    /// is the same unstructured, never-await-the-loser shape
    /// `createWorktree` already uses for exactly this reason — reused here
    /// via `raceAny`, its `T`-generic sibling (this call's result shape
    /// isn't `Result<String, GitWorktreeCreationError>`, `race` itself is
    /// unchanged for `GitWorktreeCreationTests`' sake).
    @MainActor
    func refreshWorktrees(for repoPath: String?, projectId: UUID?) async {
        worktreeRefreshToken += 1
        let token = worktreeRefreshToken

        guard let repoPath else {
            worktrees = []
            branchesWithoutWorktree = []
            currentBranchAtProjectRoot = nil
            isGitRepo = false
            isRefreshingWorktrees = false
            worktreesProjectId = nil
            return
        }

        // Deliberately NOT blanked here — a refresh in flight must keep
        // rendering whatever the previous result was (the branch picker
        // shows a trailing "Refreshing…" row via `isRefreshingWorktrees`
        // instead), or the list collapses and jumps under the cursor on
        // every reopen. Should-fix 8 fix (Slice B review round 2): this
        // now ALSO applies across a genuine timeout below (see that
        // branch's comment) — the same rationale, stated once, in one
        // place.
        isRefreshingWorktrees = true

        // Should-fix 5 fix (Slice B review round 2): a shared handle across
        // all three git shell-outs below, so a timeout can terminate
        // whichever one is actually still running — same
        // handle-and-terminate discipline `createWorktree` already has, now
        // wired here too (this doc comment used to claim the OLD shape —
        // cancel `listTask` then still `await` its `.value` — was already
        // fixed via `raceAny`; that part IS true, `raceAny` really does
        // return at the deadline, but the detached task's `Process`es kept
        // running in the background with nothing left to stop them, so a
        // hung `git` spawned a fresh one on every reopen).
        let processHandle = ProcessHandle()

        // One detached task computing ALL results off a single token check
        // — never two racing tasks each racing the other's
        // `worktreeRefreshToken` write. Should-fix 11 fix: `canonicalPath`
        // moved IN HERE, off the main actor — it was the only enumerator
        // entry point still called directly from this `@MainActor` method,
        // running a blocking `realpath(3)` syscall on the main thread on
        // every refresh.
        let listTask = Task.detached(priority: .userInitiated) { () -> (isRepo: Bool, canonicalRepoPath: String, rawList: [GitWorktreeEnumerator.Worktree], branches: [String]) in
            let canonicalRepoPath = GitWorktreeEnumerator.canonicalPath(repoPath)
            // Should-fix 7 fix: derived from `git rev-parse
            // --is-inside-work-tree`'s exit status, never from
            // `list(repoPath:)`'s emptiness — `list` runs `parsePorcelain`,
            // which DROPS `bare`/`detached`/`prunable` stanzas, so a repo
            // whose only worktree is at detached HEAD produced an EMPTY
            // `rawList` in a real, valid git repo — exactly should-fix 6's
            // original failure this claimed to fix, reopened by `rawList`
            // itself being the filtered list rather than the unfiltered one
            // the old doc comment claimed it was.
            let isRepo = GitWorktreeEnumerator.isInsideWorkTree(repoPath: repoPath) { process in
                processHandle.set(process)
            }
            // SF-3 fix (Slice B review round 3): checked between EVERY
            // shell-out, not just once at the top — three sequential git
            // invocations share ONE `ProcessHandle` (should-fix 5's design),
            // so a timeout's single `processHandle.terminate()` call only
            // ever reaches whichever ONE of the three happens to be running
            // at that instant. Without this guard, once that one process
            // died the still-unstructured, still-running `listTask` simply
            // proceeded to launch the NEXT one — which nothing was left to
            // terminate, since the caller had already returned. `listTask`
            // is now explicitly `.cancel()`ed on timeout (below) so this
            // check actually trips.
            guard !Task.isCancelled else { return (false, canonicalRepoPath, [], []) }
            let rawList = GitWorktreeEnumerator.list(repoPath: repoPath) { process in
                processHandle.set(process)
            }
            guard !Task.isCancelled else { return (isRepo, canonicalRepoPath, rawList, []) }
            // Nit fix (Slice B review round 2): pass the already-fetched
            // claimed-branch set in rather than letting
            // `branchesWithoutWorktree` call `list(repoPath:)` a SECOND
            // time internally — this repo's real branch count is small
            // enough that the double call was never a performance problem,
            // just redundant.
            let claimedBranches = Set(rawList.compactMap(\.branch))
            let branches = GitWorktreeEnumerator.branchesWithoutWorktree(repoPath: repoPath, claimedBranches: claimedBranches) { process in
                processHandle.set(process)
            }
            return (isRepo, canonicalRepoPath, rawList, branches)
        }

        guard let result = await Self.raceAny(listTask, timeoutSeconds: 2) else {
            // Should-fix 5 fix: actually stop whatever git invocation is
            // still running, rather than abandoning it — every reopen
            // against a hung repo used to spawn another on top.
            processHandle.terminate()
            // SF-3 fix (Slice B review round 3): cancels the still-running
            // detached task itself, not just the process it's currently
            // blocked on — see the `Task.isCancelled` guards threaded
            // through `listTask` above. Without this, killing ONE hung
            // process just let the task move on to the NEXT of the three
            // git invocations, which nothing was left to terminate.
            listTask.cancel()
            // Timed out — discard if superseded, same as the ordinary path.
            guard token == worktreeRefreshToken else { return }
            // Should-fix 8 fix: a slow `git` must not blank the chip —
            // `isGitRepo` (and the other cached fields) keep whatever they
            // last held, exactly the same "don't blank mid-refresh"
            // rationale a few lines above already applies to the ordinary
            // in-flight case. Only stop showing "Refreshing…".
            isRefreshingWorktrees = false

            // BL-2 fix (Slice B review round 3): a timeout used to leave
            // `.pending` PERMANENT whenever it landed on the composer's very
            // FIRST refresh (`open()`'s own call) — `isGitRepo` stays
            // `false` from its initial value, so the branch segment itself
            // never renders (`isBranchSegmentEligible == isGitRepo`), which
            // means the picker-open refresh trigger (the resolution line's
            // branch segment, `SessionComposerPalette`'s
            // `.onChange(of: isBranchPickerOpen)`, model A rebuild) is
            // unreachable — there is otherwise NOTHING left in the composer
            // that will ever ask again. `.onChange(of: commandProject?.id)`
            // doesn't help
            // either: the id never changed. Scheduling exactly one retry
            // here — guarded by the SAME `worktreeRefreshToken` every other
            // invalidation already uses, so it's a silent no-op the moment
            // `open()`/`cancel()`/another `changeProjectChip` supersedes it —
            // gives `.pending` an actual escape route: the composer keeps
            // retrying on its own every ~4s while it stays open on this
            // project, with no new UI surface and no synthetic input
            // required, until the machine's load clears and a refresh
            // finally lands.
            Task {
                try? await Task.sleep(for: .seconds(2))
                guard token == worktreeRefreshToken else { return }
                await self.refreshWorktrees(for: repoPath, projectId: projectId)
            }
            return
        }

        // Discard if a newer refresh has since been kicked off. Already back
        // on the main actor here (this method is `@MainActor`) — no
        // `MainActor.run` needed.
        guard token == worktreeRefreshToken else { return }

        isGitRepo = result.isRepo
        worktrees = result.rawList.filter { $0.path != result.canonicalRepoPath }
        currentBranchAtProjectRoot = result.rawList.first(where: { $0.path == result.canonicalRepoPath })?.branch
        branchesWithoutWorktree = result.branches
        worktreesProjectId = projectId
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

    // MARK: - Pinned templates (Composer UI 11, Step 1)

    /// Pinned template ids, most-recently-pinned-first. Mirrors
    /// `recentProjectIds`'s UserDefaults JSON `[String]` pattern
    /// (`recentProjectIdsData` above) exactly, including the
    /// `isolatedForTesting` domain handling via `defaults` — a plain
    /// computed property over persisted state, not `@Published` storage, so
    /// `togglePin(templateId:)`/`prunePins(validIds:)` call
    /// `objectWillChange.send()` themselves to drive the pin glyph / lane
    /// membership update. Global across projects (11.10 in the plan,
    /// flagged to Sean, deliberate — not scoped per project).
    private static let pinnedTemplateIdsKey = "ghostties.sessionComposerPinnedTemplateIds"

    private var pinnedTemplateIdsData: Data {
        get { defaults.data(forKey: Self.pinnedTemplateIdsKey) ?? Data() }
        set { defaults.set(newValue, forKey: Self.pinnedTemplateIdsKey) }
    }

    var pinnedTemplateIds: [UUID] {
        guard let strings = try? JSONDecoder().decode([String].self, from: pinnedTemplateIdsData) else { return [] }
        return strings.compactMap { UUID(uuidString: $0) }
    }

    private func setPinnedTemplateIds(_ ids: [UUID]) {
        pinnedTemplateIdsData = (try? JSONEncoder().encode(ids.map(\.uuidString))) ?? Data()
    }

    /// Toggle whether `templateId` is pinned. Pinning inserts at the front
    /// (most-recently-pinned-first); unpinning removes it wherever it sits.
    func togglePin(templateId: UUID) {
        objectWillChange.send()
        var current = pinnedTemplateIds
        if let index = current.firstIndex(of: templateId) {
            current.remove(at: index)
        } else {
            current.insert(templateId, at: 0)
        }
        setPinnedTemplateIds(current)
    }

    /// Drops any pinned id no longer present in `validIds` (G-F14) — called
    /// from `open()` with the full set of template ids currently known to
    /// `WorkspaceStore.templates` (user templates + presets + built-ins, all
    /// already merged there). Never runs on a background write. A no-op
    /// (including no `objectWillChange`) when nothing was orphaned.
    ///
    /// Fix 3 (review): a plausibility floor on `validIds` before pruning at
    /// all. `PresetLoader.loadPresets()` returns `[]` on several soft-failure
    /// paths with no error surfaced (missing directory, a symlinked
    /// directory, an enumeration failure — `PresetLoader.swift:171-176`), so
    /// a caller can legitimately hand this an id universe that's empty, or
    /// smaller than the persisted pin set, purely because ITS load failed —
    /// not because the pins are genuinely orphaned. Wiping every preset pin
    /// on a transient load hiccup is worse than leaving a stale id behind
    /// until the next successful `open()` prunes it correctly.
    func prunePins(validIds: Set<UUID>) {
        let current = pinnedTemplateIds
        guard !current.isEmpty else { return }
        guard !validIds.isEmpty, validIds.count >= current.count else { return }
        let pruned = current.filter { validIds.contains($0) }
        guard pruned != current else { return }
        objectWillChange.send()
        setPinnedTemplateIds(pruned)
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
        isGitRepo = false
        worktreesProjectId = nil
        selectedWorktreePath = nil
        // B4: invalidates any in-flight `createWorktree` so a slow
        // `git worktree add` that finishes after this open() (a different
        // project, possibly) can't write its result into the new context.
        isCreatingWorktree = false
        worktreeCreationToken += 1
        // Should-fix 8 fix (Slice B review round 1): bumped SYNCHRONOUSLY
        // here, before anything is scheduled — `refreshWorktrees` itself
        // also bumps this, but only once IT starts running, which is too
        // late to invalidate a refresh from a PRIOR `open()`/`changeProjectChip`
        // call that is still in flight (a slow `git worktree list` for
        // project A finishing after this `open()` for project B would
        // otherwise still pass A's stale `token == worktreeRefreshToken`
        // check and overwrite B's freshly-reset empty state).
        worktreeRefreshToken += 1
        cachedWorkspaceStore = workspaceStore

        // G-F14: pins are never pruned or reconciled anywhere else — this is
        // the one call site, per `prunePins(validIds:)`'s doc comment.
        // `workspaceStore.templates` already merges user templates, presets,
        // and built-ins (`WorkspaceStore.swift`'s `self.templates = presets +
        // AgentTemplate.defaults + customTemplates`), so its id set alone is
        // the full valid-id universe with no separate preset/built-in lookup
        // needed.
        prunePins(validIds: Set(workspaceStore.templates.map(\.id)))

        // See `suppressProjectChangeCascade`'s doc comment: this method
        // already did its own full reset above and kicks its own single
        // refresh below — the `didSet` cascade would otherwise duplicate
        // both.
        suppressProjectChangeCascade = true
        switch projectBinding {
        case .locked(let project), .prefilled(let project):
            selectedProjectId = project.id
        case .open:
            selectedProjectId = resolveDefaultProject(workspaceStore: workspaceStore)
        }
        suppressProjectChangeCascade = false

        if wasOpen {
            focusSearchFieldTrigger = true
        }
        isOpen = true

        if let projectId = selectedProjectId,
           let project = workspaceStore.projects.first(where: { $0.id == projectId }) {
            Task { await self.refreshWorktrees(for: project.rootPath, projectId: project.id) }
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
        isGitRepo = false
        worktreesProjectId = nil
        selectedWorktreePath = nil
        // See the matching invalidation in `open(...)`.
        isCreatingWorktree = false
        worktreeCreationToken += 1
        // Should-fix 8 fix (Slice B review round 1): `cancel()` used to
        // never bump this at all — an in-flight `refreshWorktrees` call
        // (kicked off by an `open()` or `changeProjectChip` that has since
        // been cancelled) kept its still-valid token and applied its
        // result into the now-closed, reset state on arrival. See the
        // matching bump + comment in `open(...)`.
        worktreeRefreshToken += 1
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

        // Should-fix 16 fix (Slice B review round 1): a commit while
        // `createWorktree` is still in flight used to launch at whatever
        // cwd `selectedWorktreePath` currently read (the old worktree, or
        // none) — the "Creating…" chip stayed clickable and Return still
        // committed normally — and the eventual `cancel()`-on-close
        // invalidates the creation's token, so the worktree it was making
        // still lands on disk with nothing left to announce it. Gate the
        // commit instead of racing it.
        guard !isCreatingWorktree else {
            writeError = "Still creating the worktree — wait for it to finish."
            return false
        }

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
        // `template.workingDirectory ?? project.rootPath`). Resolved via
        // `resolveLaunchTemplate` (finding 18, Slice B review round 1): a
        // pure static function, not inlined here, specifically so a test
        // can exercise the one line that makes a branch change the launch
        // directory WITHOUT constructing a `SessionCoordinator` — going
        // through `precommit` end-to-end would call
        // `coordinator.createQuickSession`, which touches
        // `WorkspaceStore.shared` (the real, persisted singleton) even in
        // the `#if DEBUG` testing-stub coordinator. See
        // `SessionComposerBranchLaunchTests` for the test this seam exists
        // for, and its mutant-proof (delete the `workingDirectory` write
        // below and watch that test go red).
        let launchTemplate: AgentTemplate
        switch Self.resolveLaunchTemplate(template: template, selectedWorktreePath: selectedWorktreePath) {
        case .success(let resolved):
            launchTemplate = resolved
        case .failure(let error):
            writeError = error.message
            return false
        }

        writeError = nil
        recordRecent(projectId: projectId, templateId: template.id)
        recordRecentProject(projectId)
        isOpen = false
        searchText = ""

        #if DEBUG
        // Finding 9 fix (Slice B review round 2): test-only seam so a test
        // can prove `precommit` actually CALLS `resolveLaunchTemplate` (and
        // dispatches whatever it returns), not just that
        // `resolveLaunchTemplate` itself works in isolation —
        // `SessionComposerBranchLaunchTests`'s existing coverage exercised
        // only the pure function; replacing this method's whole
        // `resolveLaunchTemplate` switch with `launchTemplate = template`
        // left that suite green. The real dispatch below
        // (`coordinator.createQuickSession`) can't be the test's assertion
        // point: it calls `WorkspaceStore.shared.addSession(...)`
        // unconditionally, even from the `#if DEBUG` testing-stub
        // `SessionCoordinator()`, before it ever checks whether `ghostty`
        // is nil — see `SessionComposerBranchLaunchTests`'s own doc comment
        // for why that rules it out as a test seam. `nil` in every
        // non-test path; when set, this REPLACES the dispatch below rather
        // than running alongside it, so a test never touches the real
        // coordinator/store at all.
        if let dispatchOverrideForTesting {
            dispatchOverrideForTesting(project, launchTemplate)
            return true
        }
        #endif

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

    /// Pure: resolves the LOCAL launch template `precommit` actually spawns
    /// — the branch chip's pick, if any and if still present on disk,
    /// overrides `template.workingDirectory`. Extracted from `precommit`
    /// itself (finding 18, Slice B review round 1) as a real test seam:
    /// `precommit`'s only other caller-visible effect is dispatching
    /// `coordinator.createQuickSession`, which is not something a unit test
    /// should invoke (see the call site's comment) — so nothing exercised
    /// the `workingDirectory` override at all, and deleting the line that
    /// applies it left the suite green.
    static func resolveLaunchTemplate(
        template: AgentTemplate,
        selectedWorktreePath: String?,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Result<AgentTemplate, SessionComposerCommitError> {
        guard let worktreePath = selectedWorktreePath else { return .success(template) }
        guard fileExists(worktreePath) else {
            return .failure(SessionComposerCommitError(message: "Worktree no longer exists at \(worktreePath)."))
        }
        var launchTemplate = template
        launchTemplate.workingDirectory = worktreePath
        return .success(launchTemplate)
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
    ///
    /// BL-1 fix (Slice B review round 3): the cascade (branch chip +
    /// worktree cache reset + refresh) is no longer performed here by hand —
    /// it lives on `selectedProjectId`'s `didSet` now, so every write to
    /// that property inherits it, including the one write path that used to
    /// bypass this function entirely (`SessionComposerPalette.commit(template:)`
    /// setting `selectedProjectId` directly for a typed command). See that
    /// property's doc comment for the full enumeration of writers.
    func selectProject(_ id: UUID) {
        selectedProjectId = id
        searchText = ""
    }

    // MARK: - Breadcrumb chip cascade + undo (Slice A)
    //
    // Note (model A rebuild): "breadcrumb chip" in the section title below
    // now names the STATE-layer cascade/undo contract only — the field is no
    // longer a chip, it's the literal `searchText` (see
    // `SessionComposerPalette`'s doc comment). `popChipToText(projectName:)`
    // used to live here, backing the field's "backspace pops the chip back
    // to raw text" gesture (A5) — that gesture doesn't exist once the field
    // has no non-editable segment to pop, so it (and its call site,
    // `SessionComposerPalette.popChipToText()`) were deleted rather than
    // ported. `changeProjectChip`/`undoProjectChipChange`/`changeBranchChip`
    // below are unchanged: the resolution line's segments call them exactly
    // as the deleted chips did.

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
        // BL-1 fix (Slice B review round 3): the cache clear/refresh this
        // used to perform by hand now lives on `selectedProjectId`'s
        // `didSet` (`cascadeProjectChange(to:)`) — `selectProject(_:)`
        // triggers it exactly the same way every other write path does.
        selectProject(projectId)
        return .changed
    }

    /// Restore the segment(s) cleared by the most recent `changeProjectChip`
    /// cascade, as one step (⌘Z). A no-op if nothing is pending — e.g. a
    /// second ⌘Z in a row, or no chip change has happened yet this session.
    ///
    /// Blocker 1 fix (Slice B review round 1): fires a worktree refresh for
    /// the RESTORED project, same as `changeProjectChip` does on the way
    /// out. Without this, ⌘Z put `selectedProjectId`/`searchText`/
    /// `selectedWorktreePath` back to project A's values while
    /// `worktrees`/`currentBranchAtProjectRoot` stayed whatever
    /// `changeProjectChip`'s own refresh had already overwritten them with
    /// for project B — no race required: open the branch picker after ⌘Z
    /// and it shows B's worktrees under A's chip, and picking one launches
    /// A's template with B's worktree as cwd.
    func undoProjectChipChange() {
        guard let pending = pendingChipUndo else { return }
        // BL-1 fix (Slice B review round 3): `selectedProjectId`'s `didSet`
        // now performs the same cache-clear-and-refresh
        // `changeProjectChip`'s cascade used to duplicate by hand (see
        // `cascadeProjectChange(to:)`) — ⌘Z is itself a project switch (back
        // to whatever was current before the cascade), so it needs the
        // identical guarantee, and now gets it for free via the same write
        // path. `selectedWorktreePath` is restored to the PRE-cascade value
        // on the line after, overwriting whatever the cascade just cleared
        // it to.
        selectedProjectId = pending.previousProjectId
        searchText = pending.previousSearchText
        selectedWorktreePath = pending.previousWorktreePath
        pendingChipUndo = nil
    }

    /// The single cascade every `selectedProjectId` write now goes through
    /// (BL-1, Slice B review round 3) — see that property's `didSet`. A
    /// different project (or no project) invalidates the branch chip's pick
    /// and the worktree cache entirely: a branch name/worktree path is
    /// meaningless in another repo.
    ///
    /// SF-4 fix (same round): `isGitRepo` is deliberately NOT reset to
    /// `false` when switching TO a project (only when switching to NO
    /// project, `projectId == nil`) — it is held at whatever it last read.
    /// Blocker 3's original fix (round 2) reset it synchronously here,
    /// which is what made the branch chip (gated on `isBranchSegmentEligible`
    /// == `isGitRepo`) disappear — separator and all — for the up-to-2s a
    /// refresh takes, then reappear once it resolved: a visible flicker on
    /// every project-chip change or ⌘Z, permanent if that refresh timed
    /// out. Holding the stale value is safe because the DATA that could
    /// actually be launched into (`worktrees`, `selectedWorktreePath`,
    /// `worktreesProjectId`) is still cleared synchronously below — nothing
    /// stale is ever offered to click, only the chip's bare presence is held
    /// stale for a moment. `worktreesProjectId = nil` also makes
    /// `resolveTypedBranch` return `.pending` rather than trusting a typed
    /// branch against the wrong project's cache in that same window.
    private func cascadeProjectChange(to projectId: UUID?) {
        worktreeRefreshToken += 1
        selectedWorktreePath = nil
        worktrees = []
        branchesWithoutWorktree = []
        currentBranchAtProjectRoot = nil
        worktreesProjectId = nil
        if projectId == nil {
            isGitRepo = false
        }

        guard let projectId,
              let project = cachedWorkspaceStore?.projects.first(where: { $0.id == projectId })
        else { return }
        Task { await self.refreshWorktrees(for: project.rootPath, projectId: project.id) }
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

    /// Blocker 2 (Slice B review round 1): sets `writeError` for an
    /// unresolvable typed branch — the ONLY caller is
    /// `SessionComposerPalette.commit(template:)`'s early-return guard, so
    /// `precommit` never runs and nothing else about the composer's state
    /// changes.
    func rejectUnresolvedBranch(token: String) {
        writeError = "No worktree found for branch \"\(token)\". Pick one from the branch picker or clear the typed branch."
    }

    /// Same write, pre-formatted message variant — used by the defensive
    /// `.failure` arm in `SessionComposerPalette.commit(template:)`'s
    /// `resolveCommitWorktreePathForCommit` switch, where the message has
    /// already been built by `SessionComposerCommitError`.
    func rejectUnresolvedBranch(message: String) {
        writeError = message
    }

    // MARK: - Branch chip creation (Slice B, B4)

    /// Outcome of racing `createWorktree`'s `git worktree add` against a
    /// timeout — see `race(_:timeoutSeconds:)` for why this can't reuse
    /// `SessionCoordinator.createSession`'s cancel-then-await shape as-is.
    enum WorktreeCreationOutcome {
        case completed(Result<String, GitWorktreeEnumerator.GitWorktreeCreationError>)
        case timedOut
    }

    /// Creates a worktree for `branchName` in `project`'s repo (the "+
    /// worktree for ..." / "+ new branch + worktree ..." rows in
    /// `WorktreeDropdownView`). Runs off the main actor with a 10-second
    /// timeout — longer than `refreshWorktrees`'s 2s because `worktree add`
    /// copies a working tree rather than just listing one.
    ///
    /// On success: refreshes the worktree cache (the fourth refresh
    /// trigger, after initial-open/project-change/picker-open), then
    /// selects the new worktree. On failure OR timeout: `writeError` is set
    /// — git's own `fatal: ...` line verbatim for a failure (see
    /// `GitWorktreeEnumerator.firstMeaningfulLine(ofStderr:)`), a fixed message
    /// for a timeout — the chip reverts to unset, and the composer stays
    /// open. Never a silent success, never a silent no-op.
    @MainActor
    func createWorktree(named branchName: String, in project: Project) {
        worktreeCreationToken += 1
        let token = worktreeCreationToken
        isCreatingWorktree = true

        // Blocker 13 fix (Slice B review round 1): captured BEFORE this
        // creation touches anything, so the failure/timeout branches below
        // can tell "nothing changed while this was in flight" apart from
        // "the user picked something else via the picker while it was
        // running" (the chip stays clickable during `isCreatingWorktree` —
        // that's intentional, discoverability). Only reset
        // `selectedWorktreePath` back to `nil` if it still equals what it
        // was at the start; otherwise a legitimate pick made mid-creation
        // would be silently clobbered by this creation's own failure.
        let selectionAtStart = selectedWorktreePath

        let repoPath = project.rootPath
        let slug = branchName.replacingOccurrences(of: "/", with: "-")

        // Blocker 12 fix: a thread-safe handle to the `Process`
        // `GitWorktreeEnumerator.add` launches, so a timeout below can
        // actually terminate it instead of abandoning it — the prior shape
        // had no handle at all, so a timed-out creation kept running in the
        // background with nothing left to report it, occasionally leaving
        // a worktree on disk the composer never mentioned (and the next
        // attempt then failed with "already exists").
        let processHandle = ProcessHandle()

        // Unstructured (not a child of any task group) so a hang in the
        // `git` call it eventually makes never blocks the race below from
        // returning at the timeout deadline.
        let gitTask = Task.detached(priority: .userInitiated) { () -> Result<String, GitWorktreeEnumerator.GitWorktreeCreationError> in
            // Blocker 17 fix: resolves the repo's MAIN worktree explicitly
            // via `git rev-parse --git-common-dir`, never by assuming
            // `list(repoPath:)`'s first element is main — that list drops
            // `bare`/`detached`/`prunable` entries, so a bare main repo or a
            // detached-HEAD main worktree made `.first` a LINKED worktree
            // instead, silently creating the new worktree as a sibling
            // under the wrong directory's `.claude/worktrees/`.
            guard let mainWorktreePath = GitWorktreeEnumerator.mainWorktreePath(repoPath: repoPath, onProcessStarted: { process in
                processHandle.set(process)
            }) else {
                return .failure(GitWorktreeEnumerator.GitWorktreeCreationError(message: "Could not determine the repository's main worktree."))
            }
            let directory = (mainWorktreePath as NSString).appendingPathComponent(".claude/worktrees/\(slug)")
            let result = GitWorktreeEnumerator.add(branch: branchName, directory: directory, repoPath: repoPath) { process in
                processHandle.set(process)
            }
            // Should-fix 6 fix (Slice B review round 2): clears the handle
            // once `add` has genuinely finished on its own — a LATE,
            // unrelated `terminate()` call (none reaches here today, but
            // this closes the gap defensively) can't reach across into
            // whatever a NEXT, unrelated creation's `onProcessStarted` sets
            // on the same handle instance.
            processHandle.clear()
            return result
        }

        Task {
            let outcome = await Self.race(gitTask, timeoutSeconds: 10)

            // Discard if superseded — see `worktreeCreationToken`'s doc
            // comment.
            guard token == worktreeCreationToken else { return }

            switch outcome {
            case .timedOut:
                // Should-fix 6 (Slice B review round 2), documented rather
                // than fixed: SIGTERM landing mid-`git worktree add` can
                // leave a half-created `directory` on disk AND a registered
                // `.git/worktrees/<slug>` admin entry behind — git's own
                // cleanup on a clean failure removes both, but a killed
                // process gets no chance to run it. The NEXT attempt at the
                // same branch/slug then fails with "already exists", the
                // exact symptom this file's blocker-12 fix was written to
                // prevent, just from a different trigger (a genuine kill
                // instead of an abandoned process). Automatically running
                // `git worktree remove --force`/`prune` here was considered
                // and rejected: this fires against WHATEVER repo the
                // composer's current project points at, and blindly pruning
                // worktree admin state on a timeout (which is not proof the
                // directory is actually still incomplete — `git` may have
                // finished writing after the timeout fired but before
                // `terminate()` landed) is a worse failure mode than a
                // one-time "already exists" the user can resolve by hand.
                processHandle.terminate()
                writeError = "Creating the worktree timed out."
                if selectedWorktreePath == selectionAtStart {
                    selectedWorktreePath = nil
                }
                isCreatingWorktree = false
            case .completed(.success(let path)):
                await refreshWorktrees(for: repoPath, projectId: project.id)
                // Blocker 4 fix: re-checked AFTER the `await` above, not
                // just before it — the prior shape's only check was before
                // `refreshWorktrees` suspended, so `cancel()`/`open()`
                // bumping the token during that suspension (create in
                // project A, close, reopen on B before the refresh
                // returned) still landed A's new worktree path into B's
                // now-current composer.
                guard token == worktreeCreationToken else { return }
                selectedWorktreePath = path
                isCreatingWorktree = false
            case .completed(.failure(let error)):
                writeError = error.message
                if selectedWorktreePath == selectionAtStart {
                    selectedWorktreePath = nil
                }
                isCreatingWorktree = false
            }
        }
    }

    /// Thread-safe holder for the `Process` a background `git worktree add`
    /// launches (blocker 12) — `GitWorktreeEnumerator.add`'s
    /// `onProcessStarted` callback runs on the detached task's background
    /// thread; `.terminate()` is called from the `@MainActor` timeout
    /// branch above. `NSLock`-guarded rather than left to chance, same
    /// discipline `race(_:timeoutSeconds:)` already applies to its own
    /// resume-once flag.
    private final class ProcessHandle: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?

        func set(_ process: Process) {
            lock.lock()
            defer { lock.unlock() }
            self.process = process
        }

        /// Should-fix 6 fix (Slice B review round 2): guards on `isRunning`
        /// before calling `terminate()` — an already-exited (and possibly
        /// already-reaped) `Process` is a no-op target either way, but the
        /// unconditional call masked whether this handle was even tracking
        /// something still alive. Clears the reference after acting so a
        /// second `terminate()` call in the same run can't re-signal
        /// whatever this happened to be set to most recently.
        func terminate() {
            lock.lock()
            defer { lock.unlock() }
            if process?.isRunning == true {
                process?.terminate()
            }
            process = nil
        }

        /// Should-fix 6 fix: lets a caller that knows its tracked process
        /// finished ON ITS OWN (not via `terminate()`) drop the reference —
        /// `GitWorktreeEnumerator.add`'s caller (`createWorktree`) calls this
        /// once `add` returns, so a later, unrelated `terminate()` call
        /// can't reach across into whatever a subsequent creation's
        /// `onProcessStarted` sets on the same handle instance.
        func clear() {
            lock.lock()
            defer { lock.unlock() }
            process = nil
        }
    }

    /// Races `task` against a `timeoutSeconds` sleep WITHOUT waiting for
    /// whichever one loses. This is deliberately NOT
    /// `SessionCoordinator.swift:192-217`'s cancel-then-`await value` shape:
    /// that shape calls `.cancel()` on a timeout and then still `await`s
    /// the cancelled task's `.value`, which only works because
    /// `resolveCommand` eventually returns on its own — a blocking
    /// `Process.waitUntilExit()` never checks `Task.isCancelled`, so the
    /// same shape here would block on a hung `git worktree add` indefinitely
    /// regardless of the "timeout". Both branches below are independent,
    /// unstructured `Task`s (not children of a `TaskGroup`, which would
    /// implicitly await the loser at scope exit) racing to call `resume`
    /// once; an `NSLock`-guarded flag makes the second call a no-op.
    ///
    /// Not `private` — this is the seam
    /// `SessionComposerCreateWorktreeTimeoutTests` exercises directly with a
    /// short `timeoutSeconds` against a task that never completes, since a
    /// real `createWorktree` timeout would otherwise take an actual 10
    /// seconds of wall-clock time to prove.
    static func race(_ task: Task<Result<String, GitWorktreeEnumerator.GitWorktreeCreationError>, Never>, timeoutSeconds: Double) async -> WorktreeCreationOutcome {
        await withCheckedContinuation { continuation in
            let lock = NSLock()
            var didResume = false
            var waiterTask: Task<Void, Never>?
            var timeoutTask: Task<Void, Never>?
            func resumeOnce(_ outcome: WorktreeCreationOutcome) {
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: outcome)
                // Nit fix (Slice B review round 2): cancel the LOSER rather
                // than leaving it to sleep out its full duration — this was
                // leaking one sleeping `Task` per race (10s here, 2s for
                // `raceAny`'s sibling copy below) every time a composer
                // opened, never reclaimed early.
                waiterTask?.cancel()
                timeoutTask?.cancel()
            }
            // Nit fix (Slice B review round 3): the assignments below used
            // to write `waiterTask`/`timeoutTask` with no synchronization at
            // all, while `resumeOnce` above reads them under `lock` — a
            // genuine data race on the references themselves, independent
            // of the (much narrower, effectively unobservable in practice
            // given the real work — a detached `git worktree add`, or a
            // multi-second `Task.sleep` — each side does before it can call
            // `resumeOnce`) ordering window where a task could finish and
            // call `resumeOnce` before its OWN reference is even stored.
            // Locking every write closes the data race the reviewer flagged;
            // the latter, narrower window is unchanged from before this fix.
            let waiter = Task<Void, Never> {
                let result = await task.value
                resumeOnce(.completed(result))
            }
            lock.lock()
            waiterTask = waiter
            lock.unlock()

            let timeout = Task<Void, Never> {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                resumeOnce(.timedOut)
            }
            lock.lock()
            timeoutTask = timeout
            lock.unlock()
        }
    }

    /// Generic sibling of `race(_:timeoutSeconds:)` — same unstructured,
    /// never-await-the-loser shape, returning `nil` on timeout instead of a
    /// dedicated outcome enum. Added for should-fix 7 (Slice B review round
    /// 1): `refreshWorktrees`'s own 2-second timeout never actually worked
    /// (it cancelled the list task and then still `await`ed its `.value`,
    /// which doesn't return early against a blocking
    /// `Process.waitUntilExit()`) — `race` itself is intentionally left
    /// untouched rather than generified in place, since
    /// `GitWorktreeCreationTests` depends on its concrete
    /// `Result<String, GitWorktreeEnumerator.GitWorktreeCreationError>`
    /// element type directly.
    /// Nit fix (Slice B review round 2): constrained to `T: Sendable` — the
    /// value crosses from the detached `task`'s isolation domain into this
    /// continuation's closure, which is exactly the kind of cross-isolation
    /// hand-off `Sendable` exists to check at compile time. Every current
    /// caller's `T` (this file's own tuple result type) is already
    /// `Sendable`, so this is a compile-time-only tightening, not a
    /// behavior change.
    static func raceAny<T: Sendable>(_ task: Task<T, Never>, timeoutSeconds: Double) async -> T? {
        await withCheckedContinuation { continuation in
            let lock = NSLock()
            var didResume = false
            var waiterTask: Task<Void, Never>?
            var timeoutTask: Task<Void, Never>?
            func resumeOnce(_ outcome: T?) {
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: outcome)
                // Same leak fix as `race(_:timeoutSeconds:)` above — cancel
                // the loser instead of letting it sleep out its full
                // duration.
                waiterTask?.cancel()
                timeoutTask?.cancel()
            }
            // Nit fix (Slice B review round 3): same synchronization fix as
            // `race(_:timeoutSeconds:)` above — see that function's matching
            // comment.
            let waiter = Task<Void, Never> {
                let result = await task.value
                resumeOnce(result)
            }
            lock.lock()
            waiterTask = waiter
            lock.unlock()

            let timeout = Task<Void, Never> {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                resumeOnce(nil)
            }
            lock.lock()
            timeoutTask = timeout
            lock.unlock()
        }
    }

    /// D4 fix: disarm the pending chip-undo the moment the user types
    /// anything by hand. `changeProjectChip` itself also writes `searchText`
    /// (clearing it as part of the cascade this undo exists to restore) —
    /// that write goes through `selectProject(_:)`, NOT this method, so it
    /// can't disarm the very undo it just armed. Only
    /// `SessionComposerPalette.searchTextBinding`'s setter (real keystrokes)
    /// calls this. Without it, ⌘Z after typing past a chip change discarded
    /// those keystrokes with no way back — AppKit's own text-undo never saw
    /// them (this binding writes `searchText` directly, bypassing the field
    /// editor's undo manager), so a second ⌘Z couldn't recover them either.
    func noteSearchTextEditedByTyping() {
        pendingChipUndo = nil
        // Nit fix (Slice B review round 2): `writeError` used to be cleared
        // only in `open()`/`cancel()`/`precommit`, so a rejection message
        // (e.g. an unresolved typed branch) stayed on screen while the user
        // kept editing text that had since changed underneath it — this is
        // the one call site every real keystroke already routes through.
        writeError = nil
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

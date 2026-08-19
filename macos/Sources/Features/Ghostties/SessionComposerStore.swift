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

    /// When true, the search field should receive first responder on the
    /// next render cycle. Cleared by the view after the focus request is
    /// consumed. Mirrors `NewTaskComposerStore.focusTitleFieldTrigger`.
    @Published var focusSearchFieldTrigger: Bool = false

    // MARK: - Field state

    @Published var selectedProjectId: UUID?
    @Published var searchText: String = ""

    /// The binding this open() call was made with, retained so `commit()`
    /// can enforce `.locked` at the write path even if `selectedProjectId`
    /// has drifted (Phase 3 is the first caller that relies on `.locked`
    /// meaning locked).
    private(set) var currentProjectBinding: SessionComposerRequest.ProjectBinding = .open

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
    }

    /// Close the composer without writing anything (Esc / cancel / popover
    /// teardown). Idempotent — safe to call from `.onDisappear` even if
    /// `cancel()` already ran via `onChange(of: isPresented)`.
    func cancel() {
        isOpen = false
        searchText = ""
        writeError = nil
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
        Task.detached { [coordinator] in
            _ = await coordinator.createQuickSession(for: project, template: template)
        }

        return true
    }

    // MARK: - Add project via NSOpenPanel

    /// Invoked from the open project dropdown's "+ Add project…" row.
    /// Opens `NSOpenPanel`, adds the project, auto-selects it, and records
    /// it as the most-recent project so it becomes the cascade default
    /// (mirrors `NewTaskComposerStore.addProjectViaPanel` setting
    /// `mruProjectId`) — without closing the composer (ship gate 2).
    func addProjectViaPanel(workspaceStore: WorkspaceStore) {
        guard let newId = workspaceStore.addProjectViaFolderPicker() else { return }
        selectedProjectId = newId
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

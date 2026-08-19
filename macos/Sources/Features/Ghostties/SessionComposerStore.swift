import AppKit
import Foundation
import SwiftUI

/// Describes how a `SessionComposerPalette` was invoked (Phase 2 of
/// session-creation-unified). Nothing else parameterizes the composer.
struct SessionComposerRequest {
    /// How the composer is presented. Only `.anchored` (the sidebar
    /// popover) is built in Phase 2 — `.centered` is declared now so the
    /// type is stable, but Phase 3 is the first caller to actually use it.
    enum Presentation {
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
/// the composer's RECENT section. Persisted as JSON in `@AppStorage` since
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

    private init() {}

    #if DEBUG
    /// Test-only initialiser — isolated state, no singleton side-effects.
    init(isolatedForTesting: Void) {}
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

    // MARK: - Error state

    @Published private(set) var writeError: String?

    // MARK: - Recent (project, template) pairs

    @AppStorage("ghostties.sessionComposerRecentSelections")
    private var recentSelectionsData: Data = Data()

    private static let maxRecents = 3

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

    // MARK: - Open / focus / cancel

    /// Open the composer for `projectBinding`, or — if already open — focus
    /// the existing search field instead of spawning a second instance
    /// (D11, mirrors `NewTaskComposerStore.open`).
    func open(projectBinding: SessionComposerRequest.ProjectBinding, workspaceStore: WorkspaceStore) {
        if isOpen {
            focusSearchFieldTrigger = true
            return
        }

        searchText = ""
        writeError = nil

        switch projectBinding {
        case .locked(let project), .prefilled(let project):
            selectedProjectId = project.id
        case .open:
            selectedProjectId = resolveDefaultProject(workspaceStore: workspaceStore)
        }

        isOpen = true
    }

    /// Close the composer without writing anything (Esc / cancel).
    func cancel() {
        isOpen = false
        searchText = ""
        writeError = nil
    }

    // MARK: - Commit

    /// Validate, create the session, record the recent pair, and close.
    /// This is the ONLY write path — it calls
    /// `coordinator.createQuickSession(for:template:)` and nothing else
    /// (ship gate 5).
    func commit(
        template: AgentTemplate,
        coordinator: SessionCoordinator,
        workspaceStore: WorkspaceStore
    ) async {
        guard let projectId = selectedProjectId,
              let project = workspaceStore.projects.first(where: { $0.id == projectId }) else {
            writeError = "Selected project no longer exists."
            return
        }

        writeError = nil
        recordRecent(projectId: projectId, templateId: template.id)
        isOpen = false
        searchText = ""

        _ = await coordinator.createQuickSession(for: project, template: template)
    }

    // MARK: - Add project via NSOpenPanel

    /// Invoked from the open project dropdown's "+ Add project…" row.
    /// Opens `NSOpenPanel`, adds the project, and auto-selects it, without
    /// closing the composer (ship gate 2).
    func addProjectViaPanel(workspaceStore: WorkspaceStore) {
        guard let newId = workspaceStore.addProjectViaFolderPicker() else { return }
        selectedProjectId = newId
    }

    // MARK: - Smart-default cascade

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

        if let mru = recentSelections.first?.projectId, projects.contains(where: { $0.id == mru }) {
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

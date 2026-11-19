import AppKit
import Combine
import GhosttiesCore
import SwiftUI

/// The one Settings window (Cmd+, / app menu "Settings…" / the `open_config`
/// keybind / a project's "Settings…" / "MCP Sources…"): a System Settings
/// style list at left, grouped App / Workspace / Agents with search on top,
/// and the selected pane's form at right (mild2wild 2026-11-18, card 11
/// "Preview strip"). It replaces App Settings' tabs, the "Your sidebar"
/// projects window and the MCP Sources window.
final class GhosttiesSettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = GhosttiesSettingsWindowController()

    /// The project panes' state and actions.
    let projects: ProjectsSettingsModel
    /// The list's selection and search text.
    let navigation: SettingsNavigation

    private var titleSync: AnyCancellable?
    /// Off under XCTest by default, so a test never writes icon caches.
    private let refreshesIcons: Bool

    static let contentSize = NSSize(width: 820, height: 640)

    init(
        store: WorkspaceStore = .shared,
        iconStore: ProjectIconStore = .shared,
        refreshesIcons: Bool = !QuietTestHost.isActive
    ) {
        let model = ProjectsSettingsModel(store: store, iconStore: iconStore)
        projects = model
        navigation = SettingsNavigation()
        self.refreshesIcons = refreshesIcons

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.contentMinSize = NSSize(width: 680, height: 480)
        let host = NSHostingController(rootView: UnifiedSettingsView(
            navigation: navigation,
            projects: model,
            store: store
        ))
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(Self.contentSize)
        super.init(window: window)
        window.delegate = self

        titleSync = navigation.$selection
            .combineLatest(store.$projects)
            .sink { [weak self] selection, projects in
                self?.window?.title = SettingsNavigation.title(for: selection ?? .general, projects: projects)
            }
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The pane the window shows now.
    var pane: SettingsPane { navigation.selection ?? .general }

    // MARK: - Showing

    /// Cmd+, (and every plain "Settings…"): the pane shown last, General the
    /// first time.
    func show() {
        present()
    }

    /// A project's "Settings…": that project's pane.
    func show(projectId: UUID) {
        show(pane: .project(projectId))
    }

    /// Any pane, e.g. "MCP Sources…" from the app menu.
    func show(pane: SettingsPane) {
        navigation.select(pane)
        present()
    }

    /// The negative cache can hide an icon added to a project for up to a
    /// day; opening Settings re-checks every project.
    private func refreshIcons() {
        guard refreshesIcons else { return }
        for project in projects.store.projects {
            projects.iconStore.refreshInBackground(project, force: true)
        }
    }

    private func present() {
        refreshIcons()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// The left list's selection and search text.
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var selection: SettingsPane? = .general
    @Published var query = ""

    /// Selects `pane`, clearing a search that would hide its row.
    func select(_ pane: SettingsPane) {
        query = ""
        selection = pane
    }

    /// The window's title for `pane`: its row's title.
    static func title(for pane: SettingsPane, projects: [Project]) -> String {
        if case .project(let id) = pane {
            return projects.first(where: { $0.id == id })?.name ?? "Settings"
        }
        return pane.fixedTitle ?? "Settings"
    }
}

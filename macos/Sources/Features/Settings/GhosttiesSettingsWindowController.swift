import AppKit
import SwiftUI

/// The Settings window (Cmd+, / app menu "Settings…" / the `open_config`
/// keybind). One shared window with two contents, swapped in place:
///
/// - **Your sidebar** (`ProjectsSettingsPane`), the default: a copy of the
///   sidebar's project list, where each project's icon and new-session
///   default are edited (settings-general card 05).
/// - **App Settings**: the General and Appearance tabs, macOS's own
///   toolbar-of-tabs layout, each with a "← Your sidebar" link back.
final class GhosttiesSettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = GhosttiesSettingsWindowController()

    enum Tab: Int { case general, appearance }
    enum Pane: Equatable { case projects, app(Tab) }

    /// The projects pane's state; `show(projectId:)` selects into it.
    let projects: ProjectsSettingsModel

    private let tabs = NSTabViewController()
    private let projectsHost: NSHostingController<ProjectsSettingsPane>
    /// The toolbar the tab controller installs, kept while the projects
    /// pane is up (it has no toolbar) and put back for App Settings.
    private var tabsToolbar: NSToolbar?
    /// Keeps the window title on the selected tab's name in App Settings.
    private var tabSelection: NSKeyValueObservation?
    /// Off under XCTest by default, so a test never writes icon caches.
    private let refreshesIcons: Bool

    init(
        store: WorkspaceStore = .shared,
        iconStore: ProjectIconStore = .shared,
        refreshesIcons: Bool = !QuietTestHost.isActive
    ) {
        let model = ProjectsSettingsModel(store: store, iconStore: iconStore)
        projects = model
        projectsHost = NSHostingController(rootView: ProjectsSettingsPane(model: model, store: store))
        projectsHost.sizingOptions = .preferredContentSize
        self.refreshesIcons = refreshesIcons

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        model.onOpenAppSettings = { [weak self] in self?.show(tab: .general) }
        let back: () -> Void = { [weak self] in self?.backToSidebar() }
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(Self.item(
            label: "General", symbol: "gearshape",
            view: AppSettingsPane(onBack: back) { SettingsView() }
        ))
        tabs.addTabViewItem(Self.item(
            label: "Appearance", symbol: "paintpalette",
            view: AppSettingsPane(onBack: back) { AppearanceSettingsView() }
        ))
        window.toolbarStyle = .preference
        tabSelection = tabs.observe(\.selectedTabViewItemIndex) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.syncTitle() }
        }
        setContent(projectsHost)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func item<V: View>(label: String, symbol: String, view: V) -> NSTabViewItem {
        let host = NSHostingController(rootView: view)
        host.sizingOptions = .preferredContentSize
        let item = NSTabViewItem(viewController: host)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }

    /// What the window shows now.
    var pane: Pane {
        if window?.contentViewController === projectsHost { return .projects }
        return .app(Tab(rawValue: tabs.selectedTabViewItemIndex) ?? .general)
    }

    // MARK: - Showing

    /// Cmd+,: the projects pane, on the current project (the one Cmd+T's
    /// composer would pick: the frontmost terminal's, else the most recent).
    func show() {
        let store = projects.store
        let current = SessionComposerStore.shared.resolveCascadeProject(workspaceStore: store)
        showProjects(selecting: current ?? projects.projects.first?.id)
    }

    /// The project menu's "Settings…": the projects pane on `projectId`.
    func show(projectId: UUID) {
        showProjects(selecting: projectId)
    }

    /// App Settings, on `tab`.
    func show(tab: Tab) {
        tabs.selectedTabViewItemIndex = tab.rawValue
        setContent(tabs)
        present()
    }

    /// App Settings' "← Your sidebar".
    func backToSidebar() {
        setContent(projectsHost)
    }

    private func showProjects(selecting projectId: UUID?) {
        if let projectId { projects.select(projectId) }
        setContent(projectsHost)
        refreshIcons()
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

    /// Swaps the window's content, keeping its top-left corner where it
    /// was. The tab controller's toolbar only belongs over App Settings.
    private func setContent(_ controller: NSViewController) {
        guard let window, window.contentViewController !== controller else { return }
        let topLeft = window.contentViewController == nil ? nil : NSPoint(x: window.frame.minX, y: window.frame.maxY)
        if window.contentViewController === tabs {
            tabsToolbar = window.toolbar ?? tabsToolbar
            window.toolbar = nil
        }
        window.contentViewController = controller
        if controller === tabs, window.toolbar == nil, let tabsToolbar {
            window.toolbar = tabsToolbar
        }
        syncTitle()
        if let topLeft { window.setFrameTopLeftPoint(topLeft) }
    }

    /// "Settings" over the projects pane; the tab's name over App Settings.
    private func syncTitle() {
        guard let window else { return }
        switch pane {
        case .projects:
            window.title = "Settings"
        case .app:
            let index = tabs.selectedTabViewItemIndex
            window.title = tabs.tabViewItems.indices.contains(index) ? tabs.tabViewItems[index].label : "Settings"
        }
    }

    private func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// An App Settings tab: the "← Your sidebar" link above the tab's content.
private struct AppSettingsPane<Content: View>: View {
    let onBack: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("\u{2190} Your sidebar", action: onBack)
                .buttonStyle(.link)
                .padding(.horizontal, 24)
                .padding(.top, 12)
            content()
        }
    }
}

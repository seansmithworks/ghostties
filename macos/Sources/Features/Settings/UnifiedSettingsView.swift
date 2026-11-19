import AppKit
import GhosttiesCore
import SwiftUI

/// The Settings window's content: the searchable list at left, the
/// selected pane at right (`GhosttiesSettingsWindowController`).
struct UnifiedSettingsView: View {
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var projects: ProjectsSettingsModel
    /// Observed so project rows follow renames, adds and removes.
    @ObservedObject var store: WorkspaceStore

    /// Built once: All themes reads every bundled theme, too slow to redo
    /// on each visit to Appearance.
    @StateObject private var appearance = AppearanceSettingsModel(applyMode: {
        (NSApp.delegate as? AppDelegate)?.applyAppearanceMode()
    })

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail(navigation.selection ?? .general)
                .navigationTitle(SettingsNavigation.title(for: navigation.selection ?? .general, projects: store.projects))
        }
    }

    // MARK: - List

    private var sidebar: some View {
        let list = SettingsPaneList(projects: projects.projects, query: navigation.query)
        let monograms = Dictionary(
            zip(projects.projects.map(\.id), ProjectMonogram.monograms(for: projects.projects.map(\.name))),
            uniquingKeysWith: { first, _ in first }
        )
        return List(selection: $navigation.selection) {
            ForEach(list.sections) { section in
                Section(section.group.rawValue) {
                    ForEach(section.rows) { row in
                        label(row, monograms: monograms)
                            .tag(row.pane)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $navigation.query, placement: .sidebar, prompt: "Search")
        .modifier(NoSidebarToggle())
        .overlay {
            if list.sections.isEmpty {
                Text("No Results for \u{201C}\(navigation.query)\u{201D}")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    @ViewBuilder
    private func label(_ row: SettingsPaneList.Row, monograms: [UUID: String]) -> some View {
        if case .project(let id) = row.pane, let project = store.projects.first(where: { $0.id == id }) {
            Label {
                Text(row.title)
            } icon: {
                ProjectMonogramTileFace(
                    monogram: monograms[id] ?? "?",
                    size: 18,
                    textSize: 10,
                    icon: projects.icon(for: project)
                )
            }
        } else {
            Label(row.title, systemImage: row.pane.symbol)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private func detail(_ pane: SettingsPane) -> some View {
        switch pane {
        case .general:
            GeneralSettingsPane()
        case .appearance:
            AppearanceSettingsView(model: appearance)
        case .sidebar:
            SidebarSettingsPane(projects: projects)
        case .project(let id):
            ProjectSettingsPane(projectId: id, model: projects, store: store)
                .id(id)
        case .templates:
            TemplatesSettingsPane(store: store)
        case .mcpSources:
            MCPSourceSettingsView()
        }
    }
}

/// Settings > Templates: the shared templates (`ProjectTemplatesSection`),
/// which every project's New Session default picks from.
struct TemplatesSettingsPane: View {
    @ObservedObject var store: WorkspaceStore

    var body: some View {
        Form {
            Section {
                ProjectTemplatesSection()
                    .environmentObject(store)
            }
        }
        .formStyle(.grouped)
    }
}

/// Settings' list is always shown, as in System Settings: no toolbar
/// button to hide it (macOS 14+; 13 keeps the stock button).
private struct NoSidebarToggle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}

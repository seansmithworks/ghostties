import Foundation
import GhosttiesCore

/// One row of the Settings window's left list (mild2wild 2026-11-18, card 11
/// "Preview strip"): App (General, Appearance, Sidebar), Workspace (each
/// project, then Templates), Agents (MCP Sources).
enum SettingsPane: Hashable {
    case general
    case appearance
    case sidebar
    case project(UUID)
    case templates
    case mcpSources

    enum Group: String, CaseIterable {
        case app = "App"
        case workspace = "Workspace"
        case agents = "Agents"
    }

    var group: Group {
        switch self {
        case .general, .appearance, .sidebar: .app
        case .project, .templates: .workspace
        case .mcpSources: .agents
        }
    }

    /// The row's title. A project's is its name, so it isn't known here.
    var fixedTitle: String? {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .sidebar: "Sidebar"
        case .project: nil
        case .templates: "Templates"
        case .mcpSources: "MCP Sources"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "circle.lefthalf.filled"
        case .sidebar: "sidebar.left"
        case .project: "folder"
        case .templates: "doc.on.doc"
        case .mcpSources: "powerplug"
        }
    }

    /// The labels of the controls on the pane, so search finds a pane by
    /// what it holds ("icons" finds Sidebar), not only by its name.
    var settingLabels: [String] {
        switch self {
        case .general: ["Update channel", "Beta", "Stable", "Config file", "Open Config File"]
        case .appearance: ["Mode", "System", "Light", "Dark", "Theme", "Mix light & dark", "All themes", "Open Config File"]
        case .sidebar: ["Icons", "None", "Small", "Large", "Text", "Standard", "Detailed", "Composer theme results", "Grid", "Chips"]
        case .project: ["Name", "Icon", "Auto", "Monogram", "Choose Image", "New Session", "Shell", "Last used"]
        case .templates: ["Templates", "New template", "Pin", "Duplicate", "Preset"]
        case .mcpSources: ["MCP Sources", "Add MCP Source", "Linear", "Sentry", "GitHub"]
        }
    }

    /// Whether the pane draws the live preview strip above its form: only
    /// panes whose settings change how the window looks.
    var hasPreviewStrip: Bool {
        switch self {
        case .appearance, .sidebar, .project: true
        case .general, .templates, .mcpSources: false
        }
    }
}

/// The left list as data: every row in order, grouped, filtered by the
/// search field. Pure, so the filtering and routing are testable without a
/// window.
struct SettingsPaneList: Equatable {
    struct Row: Equatable, Identifiable {
        let pane: SettingsPane
        let title: String
        var id: SettingsPane { pane }
    }

    struct Section: Equatable, Identifiable {
        let group: SettingsPane.Group
        let rows: [Row]
        var id: SettingsPane.Group { group }
    }

    let sections: [Section]

    /// `projects` in the sidebar's order. An empty or blank `query` lists
    /// every row; otherwise a row stays when its title or one of its
    /// settings' labels contains the query (case and diacritics ignored).
    init(projects: [Project], query: String) {
        var rows: [Row] = [
            Row(pane: .general, title: "General"),
            Row(pane: .appearance, title: "Appearance"),
            Row(pane: .sidebar, title: "Sidebar"),
        ]
        rows += projects.map { Row(pane: .project($0.id), title: $0.name) }
        rows += [
            Row(pane: .templates, title: "Templates"),
            Row(pane: .mcpSources, title: "MCP Sources"),
        ]
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty {
            rows = rows.filter { row in
                ([row.title] + row.pane.settingLabels).contains {
                    $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                }
            }
        }
        sections = SettingsPane.Group.allCases.compactMap { group in
            let inGroup = rows.filter { $0.pane.group == group }
            return inGroup.isEmpty ? nil : Section(group: group, rows: inGroup)
        }
    }

    var panes: [SettingsPane] { sections.flatMap { $0.rows.map(\.pane) } }
}

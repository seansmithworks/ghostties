import AppKit
import GhosttiesCore
import SwiftUI

/// Settings' default pane, "Settings is your sidebar" (settings-general
/// card 05): a copy of the sidebar's project list on the chrome at left;
/// click a project to edit it at right. Everything app-wide is one link
/// away in App Settings.
struct ProjectsSettingsPane: View {
    @ObservedObject var model: ProjectsSettingsModel
    /// Observed so the list and detail follow every project change.
    @ObservedObject var store: WorkspaceStore

    @ChromeScheme private var colorScheme

    static let listWidth: CGFloat = 184
    static let rowHeight: CGFloat = 36
    static let listTileSize: CGFloat = 24
    static let paneSize = CGSize(width: 568, height: 400)

    var body: some View {
        let projects = model.projects
        let monograms = Dictionary(
            zip(projects.map(\.id), ProjectMonogram.monograms(for: projects.map(\.name))),
            uniquingKeysWith: { first, _ in first }
        )
        HStack(spacing: 0) {
            list(projects, monograms: monograms)
            detail(monograms: monograms)
        }
        .frame(width: Self.paneSize.width, height: Self.paneSize.height)
    }

    // MARK: - List

    private func list(_ projects: [Project], monograms: [UUID: String]) -> some View {
        let theme = ChromeTheme.active(colorScheme)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Your sidebar")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.inkSecondaryColor)
                .padding(.horizontal, 8)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(projects) { project in
                        row(project, monogram: monograms[project.id] ?? "?", theme: theme)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 16)
        .frame(width: Self.listWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(theme.chrome))
    }

    private func row(_ project: Project, monogram: String, theme: ChromeTheme) -> some View {
        let isSelected = project.id == model.selectedProject?.id
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Button {
            model.select(project.id)
        } label: {
            HStack(spacing: 8) {
                ProjectTileView(
                    projectId: project.id,
                    iconStyle: project.iconStyle,
                    monogram: monogram,
                    size: Self.listTileSize,
                    textSize: 12,
                    iconStore: model.iconStore
                )
                Text(project.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if isSelected {
                    Text("editing")
                        .font(.system(size: 11))
                        .foregroundStyle(WorkspaceLayout.composerSelectionAccent)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: Self.rowHeight)
            .background(isSelected ? shape.fill(Color(theme.lifted(.container))) : shape.fill(Color.clear))
            .overlay(isSelected ? shape.strokeBorder(WorkspaceLayout.composerSelectionAccent, lineWidth: 1.5) : nil)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Detail

    @ViewBuilder
    private func detail(monograms: [UUID: String]) -> some View {
        if let project = model.selectedProject {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.system(size: 15, weight: .semibold))
                    Text("Click any project at left")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                Spacer(minLength: 0)
                appSettingsLink
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("No projects yet")
                    .font(.system(size: 15, weight: .semibold))
                Text("Add a project in the sidebar to set its icon and new-session default here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                appSettingsLink
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var appSettingsLink: some View {
        HStack(spacing: 4) {
            Text("Everything else:")
                .foregroundStyle(.secondary)
            Button("App Settings", action: model.openAppSettings)
                .buttonStyle(.link)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
}

// MARK: - Model

/// The projects pane's state and actions, injectable with its stores so it
/// runs in tests without the shared ones.
@MainActor
final class ProjectsSettingsModel: ObservableObject {
    let store: WorkspaceStore
    let iconStore: ProjectIconStore
    /// The project being edited. Nil, or a removed project, falls back to
    /// the first in the list.
    @Published private(set) var selectedProjectId: UUID?
    /// App Settings, set by the window controller.
    var onOpenAppSettings: () -> Void = {}

    init(store: WorkspaceStore, iconStore: ProjectIconStore) {
        self.store = store
        self.iconStore = iconStore
    }

    /// The sidebar's projects in the sidebar's order.
    var projects: [Project] { store.projectsInDisplayOrder() }

    var selectedProject: Project? {
        if let selectedProjectId, let project = store.projects.first(where: { $0.id == selectedProjectId }) {
            return project
        }
        return projects.first
    }

    func select(_ projectId: UUID) {
        selectedProjectId = projectId
    }

    func openAppSettings() { onOpenAppSettings() }

    func chooseImage(from url: URL, for projectId: UUID) async throws {
        store.setIconStyle(.file, for: projectId)
        try await iconStore.setOverride(projectId: projectId, from: url)
    }
}

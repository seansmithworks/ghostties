import AppKit
import Combine
import GhosttiesCore
import SwiftUI
import UniformTypeIdentifiers

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
                Form {
                    Section {
                        iconEditor(project, monogram: monograms[project.id] ?? "?")
                    } header: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("Click any project at left")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 16)
                            Text("Icon")
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
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

    /// The tile at Settings size, what it is, and the three ways to set it.
    private func iconEditor(_ project: Project, monogram: String) -> some View {
        let caption = model.iconCaption(for: project)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ProjectTileView(
                    projectId: project.id,
                    iconStyle: project.iconStyle,
                    monogram: monogram,
                    size: 40,
                    textSize: 18,
                    iconStore: model.iconStore
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(caption.title)
                    Text(caption.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Button("Auto") { model.useAutoIcon(for: project.id) }
                Button("Monogram") { model.useMonogram(for: project.id) }
                Button("Choose Image\u{2026}") { model.presentImagePicker(for: project.id) }
            }
            if let error = model.iconError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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

    /// Shown under the icon buttons when a chosen image can't be read.
    @Published private(set) var iconError: String?

    private var iconChanges: AnyCancellable?

    init(store: WorkspaceStore, iconStore: ProjectIconStore) {
        self.store = store
        self.iconStore = iconStore
        // The caption says whether an icon was detected: re-read it when one lands.
        iconChanges = iconStore.changes.sink { [weak self] _ in self?.objectWillChange.send() }
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

    // MARK: Icon

    /// What the tile shows now, in words.
    func iconCaption(for project: Project) -> (title: String, detail: String) {
        switch project.iconStyle ?? .auto {
        case .auto:
            return iconStore.image(for: project.id) == nil
                ? ("Monogram", "No icon found in the project folder")
                : ("Detected icon", "Found in the project folder")
        case .monogram:
            return ("Monogram", "Always the project's initial")
        case .file:
            return ("Your image", "Chosen with Choose Image\u{2026}")
        }
    }

    /// Back to detection, re-checked now (past the negative cache).
    func useAutoIcon(for projectId: UUID) {
        iconError = nil
        store.setIconStyle(nil, for: projectId)
        refreshIcon(projectId, force: true)
    }

    func useMonogram(for projectId: UUID) {
        iconError = nil
        store.setIconStyle(.monogram, for: projectId)
        refreshIcon(projectId, force: false)
    }

    /// Choose Image…: an open panel, then `chooseImage(from:for:)`.
    func presentImagePicker(for projectId: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .bmp, .ico, .icns]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Choose"
        panel.message = "Choose an image for this project's tile"
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            _Concurrency.Task { try? await self?.chooseImage(from: url, for: projectId) }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    /// Copies `url`, normalized, in as the project's tile. `iconStyle` is
    /// `.file` BEFORE the copy lands, so nothing reads a half-made choice;
    /// the refresh that sets off can't drop the copy (`setOverride`). An
    /// unreadable image puts the old style back.
    func chooseImage(from url: URL, for projectId: UUID) async throws {
        let previous = store.projects.first(where: { $0.id == projectId })?.iconStyle
        iconError = nil
        store.setIconStyle(.file, for: projectId)
        do {
            try await iconStore.setOverride(projectId: projectId, from: url)
        } catch {
            store.setIconStyle(previous, for: projectId)
            iconError = "That image couldn't be read. Try a PNG or JPEG."
            throw error
        }
    }

    private func refreshIcon(_ projectId: UUID, force: Bool) {
        guard let project = store.projects.first(where: { $0.id == projectId }) else { return }
        iconStore.refreshInBackground(project, force: force)
    }
}

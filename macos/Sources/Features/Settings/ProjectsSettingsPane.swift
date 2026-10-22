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
                    Section("New Session") {
                        newSessionPicker(project)
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

    /// What an instant new session creates in this project. Labelled with
    /// the shortcut that actually reads it: Cmd+Shift+T always, and Cmd+T
    /// only when Cmd+T creates instantly instead of opening the composer.
    private func newSessionPicker(_ project: Project) -> some View {
        Picker(model.newSessionTriggerLabel, selection: Binding(
            get: { model.newSessionSelection(for: project) },
            set: { model.setNewSessionDefault($0, for: project.id) }
        )) {
            Text("Shell").tag(NewSessionDefault.shell)
            Text(model.lastUsedTitle(for: project)).tag(NewSessionDefault.lastUsed)
            let templates = model.templateChoices(for: project)
            if !templates.isEmpty {
                Divider()
                ForEach(templates) { template in
                    Text(template.name).tag(NewSessionDefault.template(template.id))
                }
            }
        }
        .pickerStyle(.menu)
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
    /// The task is the refresh; the style, and cancelling a chosen image
    /// still being copied, take effect before this returns.
    @discardableResult
    func useAutoIcon(for projectId: UUID) -> _Concurrency.Task<Void, Never> {
        setIconStyle(nil, for: projectId, force: true)
    }

    @discardableResult
    func useMonogram(for projectId: UUID) -> _Concurrency.Task<Void, Never> {
        setIconStyle(.monogram, for: projectId, force: false)
    }

    /// Every icon edit for a project (a style picked, an image chosen)
    /// bumps this; a choose that fails only undoes itself if it is still
    /// the latest edit.
    private var iconEdits: [UUID: Int] = [:]

    private func beginIconEdit(_ projectId: UUID) -> Int {
        let edit = (iconEdits[projectId] ?? 0) + 1
        iconEdits[projectId] = edit
        return edit
    }

    /// The style from before a run of overlapping chooses: captured by the
    /// first choose that hasn't landed, kept until one lands or a style is
    /// picked. A failed choose restores this, never another choose's `.file`.
    private var styleBeforeChoosing: [UUID: ProjectIconStyle?] = [:]

    private func setIconStyle(_ style: ProjectIconStyle?, for projectId: UUID, force: Bool) -> _Concurrency.Task<Void, Never> {
        _ = beginIconEdit(projectId)
        styleBeforeChoosing[projectId] = nil
        iconError = nil
        store.setIconStyle(style, for: projectId)
        guard let project = store.projects.first(where: { $0.id == projectId }) else { return _Concurrency.Task {} }
        return iconStore.styleDidChange(project, force: force)
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
    /// unreadable image puts back the style from before the first of any
    /// overlapping chooses (`styleBeforeChoosing`), unless the icon was
    /// changed again while it was being read.
    func chooseImage(from url: URL, for projectId: UUID) async throws {
        let edit = beginIconEdit(projectId)
        if styleBeforeChoosing.index(forKey: projectId) == nil {
            styleBeforeChoosing[projectId] = .some(store.projects.first(where: { $0.id == projectId })?.iconStyle)
        }
        iconError = nil
        store.setIconStyle(.file, for: projectId)
        do {
            try await iconStore.setOverride(projectId: projectId, from: url)
            if iconEdits[projectId] == edit { styleBeforeChoosing.removeValue(forKey: projectId) }
        } catch {
            if iconEdits[projectId] == edit {
                let previous = styleBeforeChoosing[projectId] ?? nil
                _ = setIconStyle(previous, for: projectId, force: false)
                iconError = "That image couldn't be read. Try a PNG or JPEG."
            }
            throw error
        }
    }

    // MARK: New session

    /// The shortcut(s) the new-session default applies to.
    var newSessionTriggerLabel: String {
        #if DEBUG
        let defaults = WorkspaceViewContainer.composerPreferenceDefaults(fixtureActive: CaptureFixture.isActive)
        #else
        let defaults = UserDefaults.standard
        #endif
        return Self.newSessionTriggerLabel(
            composerOpensOnCmdT: WorkspaceViewContainer.newSessionOpensComposer(in: defaults)
        )
    }

    static func newSessionTriggerLabel(composerOpensOnCmdT: Bool) -> String {
        composerOpensOnCmdT ? "\u{21E7}\u{2318}T starts" : "\u{2318}T and \u{21E7}\u{2318}T start"
    }

    /// The templates offered besides Shell and Last used: the ones this
    /// project can use, Shell itself excluded (it has its own row).
    func templateChoices(for project: Project) -> [AgentTemplate] {
        store.templates.filter {
            ($0.isGlobal || $0.projectId == project.id) && $0.id != AgentTemplate.shell.id
        }
    }

    /// The popup's selection: the project's default, with a template since
    /// deleted shown as Shell (what it resolves to).
    func newSessionSelection(for project: Project) -> NewSessionDefault {
        let value = SessionTemplateResolver.newSessionDefault(for: project)
        if case .template(let id) = value, !templateChoices(for: project).contains(where: { $0.id == id }) {
            return .shell
        }
        return value
    }

    func setNewSessionDefault(_ value: NewSessionDefault, for projectId: UUID) {
        store.setNewSessionDefault(value, for: projectId)
    }

    /// "Last used", naming the template when there is one.
    func lastUsedTitle(for project: Project) -> String {
        guard let id = project.lastTemplateId,
              let template = store.templates.first(where: { $0.id == id }) else { return "Last used" }
        return "Last used (\(template.name))"
    }
}

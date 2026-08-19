import AppKit
import SwiftUI

/// The session composer, presented in the existing sidebar popover (Phase 2
/// of session-creation-unified — fixes D3/D11). A forked COPY of
/// `CommandPalette.swift`, not an edit of it: that file is byte-identical to
/// upstream and editing it in place converts a zero-conflict file into a
/// permanent rebase liability. See
/// `reference_command-palette-reuse` for the gotchas this fork works around.
///
/// Differences from the system palette, each tied to a specific defect:
/// - Sectioned RECENT / TEMPLATES / PROJECTS results instead of one flat
///   list — the search field filters both templates and projects.
/// - A trailing divided project control (Treatment 2) instead of a
///   project-chip row — Spotlight direction, project selector on the right.
/// - Prefix-first relevance ranking (`SessionComposerRanking`) instead of
///   boolean-match + color scoring.
/// - Focus-loss auto-dismiss removed: the project dropdown and
///   `+ Add project…`'s `NSOpenPanel` both take first responder, and either
///   would otherwise kill the composer mid-interaction (ship gate 2). This
///   is UNVERIFIED beyond source reading — see `ProjectDropdownView` below.
/// - `ComposerOption.id` is injectable (derived from the underlying
///   template/project id) instead of a fresh `UUID()` per recompute, so
///   options don't churn hover/scroll-to-selection on every keystroke.
/// - Proportions brought down to DESIGN.md's 11pt sidebar scale instead of
///   the system palette's 20pt field / 48pt row (D11).
///
/// NO session-name field — an unpinned session's name is its live terminal
/// title (locked decision). The search field only ever filters templates
/// and projects.
struct SessionComposerPalette: View {
    @Binding var isPresented: Bool
    let request: SessionComposerRequest

    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var coordinator: SessionCoordinator
    @ObservedObject private var composerStore = SessionComposerStore.shared

    @State private var selectedIndex: UInt?
    @State private var hoveredOptionID: UUID?
    @State private var isProjectDropdownOpen = false
    @State private var isAddingTemplate = false
    @State private var newTemplateName = ""
    @State private var newTemplateToEdit: AgentTemplate?
    @State private var showDeleteConfirmation = false
    @State private var templateToDelete: AgentTemplate?
    @FocusState private var newTemplateNameFocused: Bool

    // MARK: - DESIGN.md scale (D11) — see `TemplatePickerView` for precedent.
    // `paletteWidth` pulls from `WorkspaceLayout.sidebarWidth` (DESIGN.md §2
    // forbids hardcoded pt values where an equivalent token exists); the
    // other constants have no `WorkspaceLayout` equivalent.

    private static let paletteWidth: CGFloat = WorkspaceLayout.sidebarWidth
    private static let fieldHeight: CGFloat = 30
    private static let fieldFontSize: CGFloat = 11
    private static let rowFontSize: CGFloat = 12
    private static let subtitleFontSize: CGFloat = 10
    private static let sectionHeaderFontSize: CGFloat = 10

    private var isProjectLocked: Bool {
        if case .locked = request.projectBinding { return true }
        return false
    }

    private var query: String {
        composerStore.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentProject: Project? {
        guard let id = composerStore.selectedProjectId else { return nil }
        return store.projects.first(where: { $0.id == id })
    }

    // MARK: - Options

    private func makeOption(for template: AgentTemplate) -> ComposerOption {
        let group = SessionTemplateResolver.group(for: template)
        let isPreset = group == .preset

        // Restores the "Default shell" subtitle fallback `TemplatePickerView`
        // ships: description first, then command (non-presets only), then
        // "Default shell" (non-presets only). Presets with no description
        // render no subtitle, matching the original.
        let subtitle: String? = {
            if let description = template.templateDescription { return description }
            if !isPreset, let command = template.command { return command }
            if !isPreset { return "Default shell" }
            return nil
        }()

        return ComposerOption(
            id: template.id,
            title: template.name,
            subtitle: subtitle,
            leadingIcon: template.icon ?? iconName(for: template),
            action: { commit(template: template) },
            template: template,
            templateGroup: group
        )
    }

    private func makeOption(for project: Project) -> ComposerOption {
        ComposerOption(
            id: project.id,
            title: project.name,
            subtitle: nil,
            leadingIcon: "folder",
            action: { composerStore.selectedProjectId = project.id }
        )
    }

    private func iconName(for template: AgentTemplate) -> String {
        switch template.kind {
        case .shell: return "terminal"
        case .claudeCode: return template.agent != nil ? "cpu" : "sparkle"
        case .custom: return "gearshape"
        case .browser: return "globe"
        }
    }

    private var availableTemplates: [AgentTemplate] {
        guard let project = currentProject else { return [] }
        return SessionTemplateResolver.templates(for: project, store: store)
    }

    /// Recent `(project, template)` pairs scoped to the current project,
    /// most-recent-first, deduplicated by template.
    private var recentOptions: [ComposerOption] {
        guard let project = currentProject else { return [] }
        let recentIds = composerStore.recentSelections
            .filter { $0.projectId == project.id }
            .map { $0.templateId }

        var seen = Set<UUID>()
        var result: [ComposerOption] = []
        for id in recentIds {
            guard !seen.contains(id), let template = availableTemplates.first(where: { $0.id == id }) else { continue }
            seen.insert(id)
            result.append(makeOption(for: template))
        }
        return result
    }

    private var filteredRecentOptions: [ComposerOption] {
        SessionComposerRanking.sorted(recentOptions, query: query, title: { $0.title }, subtitle: { $0.subtitle })
    }

    private var filteredTemplateOptions: [ComposerOption] {
        let recentIds = Set(filteredRecentOptions.map { $0.id })
        let base = availableTemplates
            .map(makeOption)
            .filter { !recentIds.contains($0.id) }
        return SessionComposerRanking.sorted(base, query: query, title: { $0.title }, subtitle: { $0.subtitle })
    }

    /// Query-matching projects (S2, locked decision: "the search field
    /// filters BOTH templates and projects"). Empty when the query is
    /// blank — the trailing dropdown already covers browsing every project
    /// unfiltered. Selecting a row here sets the composer's selected
    /// project; it does not start a session.
    private var filteredProjectOptions: [ComposerOption] {
        guard !query.isEmpty else { return [] }
        let options = store.projects.map(makeOption)
        return SessionComposerRanking.sorted(options, query: query, title: { $0.title })
    }

    /// The full flattened list, in on-screen order, used for keyboard
    /// navigation and selection clamping.
    private var flattenedOptions: [ComposerOption] {
        filteredRecentOptions + filteredTemplateOptions + filteredProjectOptions
    }

    private var selectedOption: ComposerOption? {
        guard let selectedIndex else { return nil }
        let options = flattenedOptions
        return if selectedIndex < options.count {
            options[Int(selectedIndex)]
        } else {
            options.last
        }
    }

    // MARK: - Body

    var body: some View {
        let backgroundColor = Color(nsColor: .windowBackgroundColor)
        let scheme: ColorScheme = OSColor(backgroundColor).isLightColor ? .light : .dark

        VStack(alignment: .leading, spacing: 0) {
            queryRow

            Divider()

            ComposerResultsTable(
                sections: [
                    (title: filteredRecentOptions.isEmpty ? nil : "RECENT", options: filteredRecentOptions),
                    (title: "TEMPLATES", options: filteredTemplateOptions),
                    (title: filteredProjectOptions.isEmpty ? nil : "PROJECTS", options: filteredProjectOptions)
                ],
                query: query,
                selectedIndex: $selectedIndex,
                hoveredOptionID: $hoveredOptionID,
                rowFontSize: Self.rowFontSize,
                subtitleFontSize: Self.subtitleFontSize,
                sectionHeaderFontSize: Self.sectionHeaderFontSize,
                onEditTemplate: { newTemplateToEdit = $0 },
                onDuplicateTemplate: { _ = store.duplicateTemplate(id: $0.id) },
                onDuplicateAndEditTemplate: {
                    if let copy = store.duplicateTemplate(id: $0.id) { newTemplateToEdit = copy }
                },
                onEditPresetFile: { openPresetInEditor($0) },
                onRequestDeleteTemplate: {
                    templateToDelete = $0
                    showDeleteConfirmation = true
                }
            ) { option in
                // Does NOT dismiss the popover here — `option.action()` (a
                // template commit) only clears `isPresented` once the store
                // confirms the write succeeded (S6). Dismissing eagerly, as
                // this used to, closed the composer with no session and no
                // visible error whenever `commit()`'s pre-check failed.
                option.action()
            }

            Divider()

            if let writeError = composerStore.writeError {
                Text(writeError)
                    .font(.system(size: Self.subtitleFontSize))
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
            }

            newTemplateRow
        }
        .frame(width: Self.paletteWidth)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(backgroundColor).blendMode(.color)
            }
            .compositingGroup()
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .tertiaryLabelColor).opacity(0.75))
        )
        .environment(\.colorScheme, scheme)
        .onAppear {
            composerStore.open(projectBinding: request.projectBinding, workspaceStore: store)
            // S5: row 0 is the project's default template (Phase 1's
            // default-first ordering) and the legend reads "↵ start" — seed
            // the selection so Return isn't a dead key on first open.
            selectedIndex = 0
        }
        .onChange(of: isPresented) { presented in
            if !presented {
                composerStore.cancel()
                isAddingTemplate = false
                newTemplateName = ""
            }
        }
        .onDisappear {
            // The only reliable teardown hook for popover content — the row
            // hosting this popover can leave the hierarchy (project
            // removed, sidebar view-mode switch, `windowDidResignKey` /
            // `mouseExited` closing the popover) without
            // `onChange(of: isPresented)` ever firing, which otherwise
            // latches `SessionComposerStore.isOpen` true forever (B3).
            composerStore.cancel()
        }
        .onChange(of: query) { _ in
            // Clamp into range rather than nil-ing out — the old logic only
            // reset when the index was exactly 0, so a stale index from a
            // shrunk list (e.g. RECENT reordering after a commit) survived
            // a query change untouched.
            let count = flattenedOptions.count
            guard count > 0 else {
                selectedIndex = nil
                return
            }
            if let current = selectedIndex {
                if current >= UInt(count) {
                    selectedIndex = UInt(count - 1)
                }
            } else {
                selectedIndex = 0
            }
        }
        .sheet(item: $newTemplateToEdit) { template in
            TemplateEditForm(template: template)
        }
        .alert(
            "Delete Template?",
            isPresented: $showDeleteConfirmation,
            presenting: templateToDelete
        ) { template in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.removeTemplate(id: template.id)
            }
        } message: { template in
            if store.templateInUse(id: template.id) {
                Text("Sessions using \"\(template.name)\" will keep their current configuration but won't be relaunchable with this template.")
            } else {
                Text("This will permanently remove \"\(template.name)\".")
            }
        }
    }

    // MARK: - Query row (search field + trailing project control)

    private var queryRow: some View {
        HStack(spacing: 0) {
            ComposerQueryField(
                query: $composerStore.searchText,
                fontSize: Self.fieldFontSize,
                focusTrigger: $composerStore.focusSearchFieldTrigger,
                hasSelection: selectedOption != nil
            ) { event in
                handle(event)
            }
            .frame(height: Self.fieldHeight)

            projectControl
        }
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private var projectControl: some View {
        let label = currentProject?.name ?? "Select project"

        if isProjectLocked {
            // No hairline divider here (nit): a divider next to a static
            // label with no `▾` reads as a control that isn't one.
            Text(label)
                .font(.system(size: Self.rowFontSize, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        } else {
            Divider()
                .frame(height: Self.fieldHeight * 0.5)

            Button {
                isProjectDropdownOpen = true
            } label: {
                HStack(spacing: 4) {
                    Text(label)
                        .font(.system(size: Self.rowFontSize, weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // UNVERIFIED beyond source reading: this is a `.popover` nested
            // inside the composer's own `.popover`. Whether the child
            // taking key dismisses the parent (the exact mechanism ship
            // gate 2 exists to catch) can only be settled by running the
            // app.
            .popover(isPresented: $isProjectDropdownOpen, arrowEdge: .bottom) {
                ProjectDropdownView(
                    selectedProjectId: composerStore.selectedProjectId
                ) { project in
                    composerStore.selectedProjectId = project.id
                    isProjectDropdownOpen = false
                } onAddProject: {
                    composerStore.addProjectViaPanel(workspaceStore: store)
                    isProjectDropdownOpen = false
                }
                .environmentObject(store)
            }
        }
    }

    // MARK: - Footer: + New template…

    @ViewBuilder
    private var newTemplateRow: some View {
        if isAddingTemplate {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .frame(width: 16)
                TextField("Template name", text: $newTemplateName)
                    .font(.system(size: Self.rowFontSize, weight: .medium))
                    .textFieldStyle(.plain)
                    .focused($newTemplateNameFocused)
                    .onSubmit { commitNewTemplate() }
                    .onExitCommand { cancelNewTemplate() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .onAppear {
                DispatchQueue.main.async { newTemplateNameFocused = true }
            }
        } else {
            Button {
                newTemplateName = ""
                isAddingTemplate = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .frame(width: 16)
                    Text("New template…")
                        .font(.system(size: Self.rowFontSize, weight: .medium))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private func commitNewTemplate() {
        guard isAddingTemplate else { return }
        isAddingTemplate = false
        let trimmed = newTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
        newTemplateName = ""
        guard !trimmed.isEmpty else { return }
        let template = store.addTemplate(AgentTemplate(name: trimmed, kind: .custom))
        newTemplateToEdit = template
    }

    private func cancelNewTemplate() {
        isAddingTemplate = false
        newTemplateName = ""
    }

    // MARK: - Template context menu actions (S4, ported from
    // `TemplatePickerView` — that view now has zero callers, so everything
    // it owned, most seriously `store.removeTemplate`'s only UI caller, was
    // unreachable).

    /// Preset files live at `~/.ghostties/presets/<slug>.md`. Duplicated
    /// from `TemplatePickerView.openPresetInEditor` (that method is
    /// `private` to a different file, not reachable from here).
    private func openPresetInEditor(_ template: AgentTemplate) {
        let filename = template.name.lowercased().replacingOccurrences(of: " ", with: "-") + ".md"
        let path = (PresetLoader.presetsDirectoryPath as NSString).appendingPathComponent(filename)

        // Validate the resolved path stays within the presets directory.
        let resolvedPath = (path as NSString).standardizingPath
        let presetsDir = (PresetLoader.presetsDirectoryPath as NSString).standardizingPath
        guard resolvedPath.hasPrefix(presetsDir + "/") else { return }

        let url = URL(fileURLWithPath: resolvedPath)
        if FileManager.default.fileExists(atPath: resolvedPath) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Actions

    private func commit(template: AgentTemplate) {
        // S1: reset the stale index up front. `recordRecent` (inside the
        // store's commit) reorders RECENT, which would otherwise leave
        // `selectedIndex` pointing at the wrong row if the composer stays
        // open on a failed commit (S6).
        selectedIndex = nil
        Task {
            let success = await composerStore.commit(template: template, coordinator: coordinator, workspaceStore: store)
            if success {
                isPresented = false
            }
        }
    }

    /// Return and ⌥+Return are identical: both start the session, which
    /// already reveals/focuses it (`SessionCoordinator.createSession` makes
    /// the new surface "the sole occupant of the terminal area"), then
    /// close the composer like any other commit. An earlier version of this
    /// file invented a "commit but keep composer open" meaning for ⌥+Return
    /// that contradicted the plan's own legend (`↵ start · ⌥↵ start +
    /// reveal · esc cancel`) — deleted, not kept as a fallback.
    private func handle(_ event: ComposerQueryField.KeyboardEvent) {
        switch event {
        case .exit:
            isPresented = false

        case .submit:
            selectedOption?.action()

        case .move(.up):
            if flattenedOptions.isEmpty { break }
            let current = selectedIndex ?? UInt(flattenedOptions.count)
            selectedIndex = (current == 0) ? UInt(flattenedOptions.count - 1) : current - 1

        case .move(.down):
            if flattenedOptions.isEmpty { break }
            let current = selectedIndex ?? UInt.max
            selectedIndex = (current >= UInt(flattenedOptions.count - 1)) ? 0 : current + 1

        case .move:
            break
        }
    }
}

// MARK: - ComposerOption

/// Analog of `CommandOption` with an INJECTABLE id (derived from the
/// underlying template/project id), fixing the churn `CommandOption.id =
/// UUID()` causes on every keystroke recompute.
///
/// `template`/`templateGroup` are non-nil only for options backed by a
/// template — `ComposerRow` uses them to decide whether (and which)
/// context menu to attach; project options and other rows carry no menu.
struct ComposerOption: Identifiable, Hashable {
    let id: UUID
    let title: String
    let subtitle: String?
    let leadingIcon: String?
    let action: () -> Void
    let template: AgentTemplate?
    let templateGroup: SessionTemplateResolver.Group?

    init(
        id: UUID,
        title: String,
        subtitle: String?,
        leadingIcon: String?,
        action: @escaping () -> Void,
        template: AgentTemplate? = nil,
        templateGroup: SessionTemplateResolver.Group? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.leadingIcon = leadingIcon
        self.action = action
        self.template = template
        self.templateGroup = templateGroup
    }

    static func == (lhs: ComposerOption, rhs: ComposerOption) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Query field

/// The composer's search field. Forked from `CommandPaletteQuery` with two
/// changes: the focus-loss auto-dismiss (`onChange(of: isTextFieldFocused)`
/// calling `.exit`) is REMOVED — the project dropdown and
/// `+ Add project…`'s `NSOpenPanel` both take first responder, and either
/// would otherwise kill the composer mid-interaction (ship gate 2) — and
/// Return is wired through BOTH `.onSubmit` and `Backport.onKeyPress`:
/// `Backport.onKeyPress` is a documented no-op below macOS 14
/// (`Helpers/Backport.swift:53-68`) and the app's deployment target is
/// 13.0, so `.onSubmit` alone is what makes Return work pre-14. If both
/// fire on 14+, `SessionComposerStore.commit()`'s re-entry guard (`S9`)
/// makes the second call a no-op rather than a double-commit — this repo
/// cannot verify from source alone whether both actually fire, only that a
/// double-fire would be harmless if they do.
struct ComposerQueryField: View {
    @Binding var query: String
    var fontSize: CGFloat
    @Binding var focusTrigger: Bool
    /// Whether there's a highlighted row to commit. When false, Return is a
    /// deliberate no-op (nit: `.onKeyPress` used to return `.handled`
    /// unconditionally, swallowing Return against an empty list).
    var hasSelection: Bool
    var onEvent: ((KeyboardEvent) -> Void)?
    @FocusState private var isTextFieldFocused: Bool

    enum KeyboardEvent {
        case exit
        case submit
        case move(MoveCommandDirection)
    }

    var body: some View {
        ZStack {
            Group {
                Button { onEvent?(.move(.up)) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.upArrow, modifiers: [])
                Button { onEvent?(.move(.down)) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.downArrow, modifiers: [])

                Button { onEvent?(.move(.up)) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.init("p"), modifiers: [.control])
                Button { onEvent?(.move(.down)) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.init("n"), modifiers: [.control])
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)

            TextField("Search templates and projects…", text: $query)
                .padding(.vertical, 6)
                .font(.system(size: fontSize, weight: .light))
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .onExitCommand { onEvent?(.exit) }
                .onMoveCommand { onEvent?(.move($0)) }
                // B1: `.onSubmit` is the ONLY Return handler that works
                // below macOS 14 — the app's deployment target is 13.0.
                .onSubmit {
                    guard hasSelection else { return }
                    onEvent?(.submit)
                }
                .backport.onKeyPress(.return) { _ in
                    guard hasSelection else { return .ignored }
                    onEvent?(.submit)
                    return .handled
                }
                .onAppear {
                    DispatchQueue.main.async {
                        isTextFieldFocused = true
                    }
                }
                .onChange(of: focusTrigger) { triggered in
                    // S7: consumes `SessionComposerStore.focusSearchFieldTrigger`
                    // — previously set on re-open but read nowhere, so the
                    // "opening while already open focuses the field" parity
                    // the doc comment claimed was a complete no-op.
                    guard triggered else { return }
                    isTextFieldFocused = true
                    focusTrigger = false
                }
        }
    }
}

// MARK: - Results table

/// Forked from `CommandTable`, with two changes: it renders named sections
/// (RECENT / TEMPLATES / PROJECTS — `CommandPaletteView` has no section
/// grouping at all) and it uses a plain `VStack`, never `LazyVStack` — this
/// repo has a known bug class where `LazyVStack` never re-invokes
/// `ForEach`'s content closure when an element changes but its `id` does
/// not, which froze sidebar rows at first construction (PR #121).
private struct ComposerResultsTable: View {
    var sections: [(title: String?, options: [ComposerOption])]
    var query: String
    @Binding var selectedIndex: UInt?
    @Binding var hoveredOptionID: UUID?
    var rowFontSize: CGFloat
    var subtitleFontSize: CGFloat
    var sectionHeaderFontSize: CGFloat
    var onEditTemplate: (AgentTemplate) -> Void
    var onDuplicateTemplate: (AgentTemplate) -> Void
    var onDuplicateAndEditTemplate: (AgentTemplate) -> Void
    var onEditPresetFile: (AgentTemplate) -> Void
    var onRequestDeleteTemplate: (AgentTemplate) -> Void
    var action: (ComposerOption) -> Void

    private var flattened: [ComposerOption] {
        sections.flatMap { $0.options }
    }

    var body: some View {
        if flattened.isEmpty {
            Text("No matches")
                .font(.system(size: rowFontSize))
                .foregroundStyle(.secondary)
                .padding(12)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                            if !section.options.isEmpty {
                                if let title = section.title {
                                    Text(title)
                                        .font(.system(size: sectionHeaderFontSize, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 4)
                                        .padding(.top, 6)
                                        .padding(.bottom, 2)
                                }

                                ForEach(section.options) { option in
                                    ComposerRow(
                                        option: option,
                                        query: query,
                                        isSelected: isSelected(option),
                                        hoveredID: $hoveredOptionID,
                                        titleFontSize: rowFontSize,
                                        subtitleFontSize: subtitleFontSize,
                                        onEditTemplate: onEditTemplate,
                                        onDuplicateTemplate: onDuplicateTemplate,
                                        onDuplicateAndEditTemplate: onDuplicateAndEditTemplate,
                                        onEditPresetFile: onEditPresetFile,
                                        onRequestDeleteTemplate: onRequestDeleteTemplate
                                    ) {
                                        action(option)
                                    }
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 220)
                .onChange(of: selectedIndex) { _ in
                    guard let selectedIndex, selectedIndex < flattened.count else { return }
                    proxy.scrollTo(flattened[Int(selectedIndex)].id)
                }
            }
        }
    }

    private func isSelected(_ option: ComposerOption) -> Bool {
        guard let selectedIndex, let index = flattened.firstIndex(where: { $0.id == option.id }) else { return false }
        return Int(selectedIndex) == index || (Int(selectedIndex) >= flattened.count && index == flattened.count - 1)
    }
}

/// Forked from `CommandRow`, resized to DESIGN.md's 11pt sidebar scale.
/// Reuses `String.matchedIndices(for:)` (`CommandPalette.swift`,
/// module-scope) for highlighting — redeclaring it would be a compile
/// error.
///
/// S4: carries a `.contextMenu`, ported from
/// `TemplatePickerView.templateRow` (`TemplatePickerView.swift:186-217`),
/// for template-backed rows only (`option.template != nil`) — project rows
/// get no menu. Perf note (`project_perf-contextmenu-render-cost.md`):
/// per-row `.contextMenu` in a long-lived sidebar list is a known
/// bottleneck, but this is a transient popover showing ~10 rows, so it's
/// acceptable; no `.popover`/`.draggable` is added per row alongside it.
private struct ComposerRow: View {
    let option: ComposerOption
    var query: String
    var isSelected: Bool
    @Binding var hoveredID: UUID?
    var titleFontSize: CGFloat
    var subtitleFontSize: CGFloat
    var onEditTemplate: (AgentTemplate) -> Void
    var onDuplicateTemplate: (AgentTemplate) -> Void
    var onDuplicateAndEditTemplate: (AgentTemplate) -> Void
    var onEditPresetFile: (AgentTemplate) -> Void
    var onRequestDeleteTemplate: (AgentTemplate) -> Void
    var action: () -> Void

    private var highlightedTitle: Text {
        guard !query.isEmpty, let indices = option.title.matchedIndices(for: query) else {
            return Text(option.title).font(.system(size: titleFontSize, weight: .medium))
        }

        var attributed = AttributedString(option.title)
        attributed[attributed.startIndex...].font = .system(size: titleFontSize, weight: .medium)

        for idx in indices {
            let offset = option.title.distance(from: option.title.startIndex, to: idx)
            let attrStart = attributed.index(attributed.startIndex, offsetByCharacters: offset)
            let attrEnd = attributed.index(attrStart, offsetByCharacters: 1)
            attributed[attrStart..<attrEnd].font = .system(size: titleFontSize, weight: .bold)
            attributed[attrStart..<attrEnd].foregroundColor = Color.accentColor
        }

        return Text(attributed)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = option.leadingIcon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }

                VStack(alignment: .leading, spacing: 1) {
                    highlightedTitle

                    if let subtitle = option.subtitle {
                        Text(subtitle)
                            .font(.system(size: subtitleFontSize))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.2)
                    : (hoveredID == option.id ? Color.secondary.opacity(0.2) : Color.clear)
            )
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredID = hovering ? option.id : nil
        }
        .contextMenu {
            templateContextMenu
        }
    }

    /// Replicates `TemplatePickerView.templateRow`'s context menu exactly:
    /// presets get "Duplicate and Edit..." (+ "Edit Preset File..." when a
    /// description exists), built-ins get "Duplicate and Edit..." only,
    /// user templates get Edit… / Duplicate / Delete. Renders nothing for
    /// non-template rows (project options).
    @ViewBuilder
    private var templateContextMenu: some View {
        if let template = option.template, let group = option.templateGroup {
            if group == .preset {
                Button("Duplicate and Edit...") { onDuplicateAndEditTemplate(template) }
                if template.templateDescription != nil {
                    Button("Edit Preset File...") { onEditPresetFile(template) }
                }
            } else if template.isDefault {
                Button("Duplicate and Edit...") { onDuplicateAndEditTemplate(template) }
            } else {
                Button("Edit...") { onEditTemplate(template) }
                Button("Duplicate") { onDuplicateTemplate(template) }
                Divider()
                Button("Delete", role: .destructive) { onRequestDeleteTemplate(template) }
            }
        }
    }
}

// MARK: - Project dropdown

/// The open project dropdown (Treatment 2's trailing `▾` control). Three-tier
/// ordering, no visible headers: cascade pick (pre-selected) -> recently-used
/// most-recent-first -> everything else alphabetically (locked decision).
/// `+ Add project…` is always the last row.
///
/// UNVERIFIED beyond source reading (flagged at the call site too): this
/// view is presented as a `.popover` nested inside the composer's own
/// `.popover`. A child popover taking key can dismiss the parent, and
/// removing the text-field-blur handler on `ComposerQueryField` does NOT by
/// itself fix popover-loses-key dismissal — this is the exact mechanism
/// ship gate 2 exists to catch, and it can only be settled by running the
/// app.
private struct ProjectDropdownView: View {
    let selectedProjectId: UUID?
    var onSelect: (Project) -> Void
    var onAddProject: () -> Void

    @EnvironmentObject private var store: WorkspaceStore

    /// Decoupled from the composer's search field (nit): this used to read
    /// `SessionComposerStore.shared.searchText` directly, so typing
    /// "claude" to find a template and then opening the dropdown showed
    /// every project filtered out even though this view has no visible
    /// search field of its own. Starts empty, unaffected by the composer's
    /// query.
    @State private var query: String = ""

    private var orderedProjects: [Project] {
        let recentIds = SessionComposerStore.shared.recentProjectIds
        return SessionComposerProjectOrdering.order(
            projects: store.projects,
            cascadePick: selectedProjectId,
            recentProjectIds: recentIds
        )
    }

    private var filteredProjects: [Project] {
        SessionComposerRanking.sorted(orderedProjects, query: query, title: { $0.name })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(filteredProjects) { project in
                    Button {
                        onSelect(project)
                    } label: {
                        HStack(spacing: 6) {
                            Text(project.name)
                                .font(.system(size: 12, weight: project.id == selectedProjectId ? .semibold : .regular))
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Divider().padding(.horizontal, 8).padding(.vertical, 2)

                Button(action: onAddProject) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                            .frame(width: 14)
                        Text("Add project…")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(6)
        }
        .frame(width: 220)
        .frame(maxHeight: 240)
    }
}

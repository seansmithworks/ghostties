import Foundation
import GhosttiesCore

/// The single source of truth for "which templates are available to a
/// project, in what order" for the session-creation surfaces (the New
/// Session menu and the template picker) — replaces two divergent
/// implementations that used to live in
/// `RecentsListView.availableTemplates(for:store:)` and the three computed
/// properties on `TemplatePickerView` (`presetTemplates`, `builtinTemplates`,
/// `customTemplates`). Both those callers now route through this type.
///
/// `WorkspaceStore.templates(for projectId:)` is a third, knowingly-separate
/// copy of the scoping predicate consumed by `NewTaskComposerView` — it does
/// not route through here. Do not assume this is the only scoping/ordering
/// implementation left in the codebase before adding a new caller.
@MainActor
enum SessionTemplateResolver {

    /// The three sections the template picker renders, in display order.
    enum Group {
        case preset
        case builtin
        case user
    }

    /// Classifies a template into a picker section.
    ///
    /// Switches on `isDefault` first so the function is total: a non-default
    /// template is always user-created (`.user`), regardless of its other
    /// fields. Among default templates, one with a `templateDescription` is
    /// a file-based preset (`.preset`); one without is a built-in
    /// (`.builtin`, e.g. Shell, Claude Code).
    static func group(for template: AgentTemplate) -> Group {
        guard template.isDefault else { return .user }
        return template.templateDescription != nil ? .preset : .builtin
    }

    /// Returns the templates available to `project`, in the order both the
    /// flat "New Session" menu and the sectioned template picker should
    /// present them.
    ///
    /// Scope: a template is a candidate if it's global (`isGlobal`) or
    /// scoped to this exact project (`projectId == project.id`).
    ///
    /// Order:
    /// 1. The project's `defaultTemplateId` template, if present in the
    ///    candidate set, always comes first — regardless of its group.
    /// 2. The remaining candidates, grouped `.preset`, then `.builtin`, then
    ///    `.user`, with insertion order preserved within each group (a
    ///    stable partition, not a `sort` — the predicate this replaces,
    ///    `candidates.sorted { a, _ in a.id == defaultId }`, is not a strict
    ///    weak ordering and leaves everything past "the default sorts
    ///    early" unspecified across repeated calls).
    ///
    /// Default-first, ahead of group order, is a deliberate ordering
    /// decision: because a stable partition preserves each group's relative
    /// order, putting the default first in this flat list also puts it
    /// first within whichever section it belongs to once `TemplatePickerView`
    /// filters this same list by `group(for:)` — so the sectioned picker's
    /// "default appears first in its own section" behavior falls out of one
    /// resolved list for free, instead of needing a second, separate sort.
    static func templates(for project: Project, store: WorkspaceStore) -> [AgentTemplate] {
        let candidates = store.templates.filter { $0.isGlobal || $0.projectId == project.id }

        let defaultId = project.defaultTemplateId
        var defaultTemplate: AgentTemplate?
        var rest: [AgentTemplate] = []
        rest.reserveCapacity(candidates.count)
        for candidate in candidates {
            if defaultTemplate == nil, let defaultId, candidate.id == defaultId {
                defaultTemplate = candidate
            } else {
                rest.append(candidate)
            }
        }

        var presets: [AgentTemplate] = []
        var builtins: [AgentTemplate] = []
        var users: [AgentTemplate] = []
        for candidate in rest {
            switch group(for: candidate) {
            case .preset: presets.append(candidate)
            case .builtin: builtins.append(candidate)
            case .user: users.append(candidate)
            }
        }

        var result: [AgentTemplate] = []
        result.reserveCapacity(candidates.count)
        if let defaultTemplate { result.append(defaultTemplate) }
        result.append(contentsOf: presets)
        result.append(contentsOf: builtins)
        result.append(contentsOf: users)
        return result
    }
}

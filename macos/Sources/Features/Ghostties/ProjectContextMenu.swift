import SwiftUI
import GhosttiesCore

extension View {
    /// The project context menu (Settings…, which opens the Settings window
    /// on this project; Pin/Unpin; Remove) and the DEBUG capture hook that
    /// opens Settings on a project. Defined once here and applied to every project
    /// header: the tabs layout's `ProjectDisclosureRow` and one-view's
    /// `ProjectAccordionHeader` (which is also the rail's project tile).
    func projectContextMenu(_ project: Project) -> some View {
        modifier(ProjectContextMenu(project: project))
    }
}

struct ProjectContextMenu: ViewModifier {
    let project: Project

    @EnvironmentObject private var store: WorkspaceStore

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Settings\u{2026}") {
                    GhosttiesSettingsWindowController.shared.show(projectId: project.id)
                }
                Divider()
                Button(project.isPinned ? "Unpin" : "Pin") {
                    store.togglePin(id: project.id)
                }
                Divider()
                Button("Remove", role: .destructive) {
                    store.removeProject(id: project.id)
                }
            }
            #if DEBUG
            .onAppear(perform: applyCaptureProjectSettingsIfNeeded)
            #endif
    }

    #if DEBUG
    /// `GHOSTTIES_CAPTURE_PROJECT_SETTINGS`: what the context menu's
    /// "Settings…" does: opens Settings on the named project.
    private func applyCaptureProjectSettingsIfNeeded() {
        guard CaptureFixture.projectSettingsHook?.projectName == project.name,
              CaptureFixture.claimHook("projectSettings") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            GhosttiesSettingsWindowController.shared.show(projectId: project.id)
        }
    }
    #endif
}

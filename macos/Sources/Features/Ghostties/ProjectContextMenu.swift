import SwiftUI
import GhosttiesCore

extension View {
    /// The project context menu (Settings…, Pin/Unpin, Remove), the Settings
    /// popover it opens (which hosts Templates), and the DEBUG capture hook
    /// for that popover. Defined once here and applied to every project
    /// header: the tabs layout's `ProjectDisclosureRow` and one-view's
    /// `ProjectAccordionHeader` (which is also the rail's project tile).
    func projectContextMenu(_ project: Project) -> some View {
        modifier(ProjectContextMenu(project: project))
    }
}

struct ProjectContextMenu: ViewModifier {
    let project: Project

    @EnvironmentObject private var store: WorkspaceStore
    @State private var settingsProject: Project?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Settings\u{2026}") {
                    settingsProject = project
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
            .popover(
                isPresented: Binding(
                    get: { settingsProject?.id == project.id },
                    set: { if !$0 { settingsProject = nil } }
                ),
                arrowEdge: .trailing
            ) {
                ProjectSettingsView(project: project) {
                    settingsProject = nil
                }
                .environmentObject(store)
            }
            #if DEBUG
            .onAppear(perform: applyCaptureProjectSettingsIfNeeded)
            #endif
    }

    #if DEBUG
    /// `GHOSTTIES_CAPTURE_PROJECT_SETTINGS`: what the context menu's
    /// "Settings…" does. Deferred so the window is on screen before the
    /// popover anchors to the header.
    private func applyCaptureProjectSettingsIfNeeded() {
        guard CaptureFixture.projectSettingsHook?.projectName == project.name,
              CaptureFixture.claimHook("projectSettings") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            settingsProject = project
        }
    }
    #endif
}

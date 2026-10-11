import AppKit
import Combine
import Foundation
import GhosttiesCore
import SwiftUI
import Testing
@testable import Ghostty

/// Gate: the project list scrolls UNDER the floating glass tray (Flow 07).
///
/// The tray is hosted over the list, so the list's viewport must run to
/// the tray's bottom, not stop at the tray's top. When the VStack instead
/// reserves the tray's height below the list (`MorphTrayReserve`), the
/// list is cut flat there and the strip behind the glass shows the bare
/// chrome as an opaque band.
///
/// A real `WorkspaceViewContainer` in a 900x620 window on a
/// persistence-disabled store; frames from the Redlines registry
/// (`list.viewport`, `tray.group`), both in the sidebar hosting view's
/// top-left coordinates.
@MainActor
@Suite(.serialized)
struct SidebarTrayOverlapGateTests {
    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    private func spin(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    }

    /// Enough threads that the list overflows the 620pt window.
    @Test func theListRunsUnderTheTrayWithNoOpaqueBandBetween() throws {
        try withDials({ $0.set(true, forKey: SidebarDialTuning.redlinesKey) }) {
            let tabKey = "ghostties.sidebarTab"
            let previousTab = UserDefaults.standard.object(forKey: tabKey)
            UserDefaults.standard.set(SidebarTab.projects.rawValue, forKey: tabKey)

            let projects = (1...3).map { Project(name: "project-\($0)", rootPath: "~/Code/project-\($0)") }
            var sessions: [AgentSession] = []
            for p in projects {
                for n in 1...6 {
                    sessions.append(AgentSession(name: "thread \(p.name) \(n)", templateId: AgentTemplate.claudeCode.id, projectId: p.id))
                }
            }
            let store = WorkspaceStore(
                testingProjects: projects, testingSessions: sessions,
                hasShownPinMigrationNotice: true, hasDismissedPinMigrationNotice: true
            )
            for s in sessions {
                store.updateSessionStatus(id: s.id, status: .running)
                store.updateIndicatorState(id: s.id, state: .idle)
            }
            store.updateSidebarMode(.pinned)
            let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel(), store: store)
            container.coordinatorForTesting.setActiveSessionIdForTesting(sessions[0].id)
            let window = NSWindow(
                contentRect: .init(x: 0, y: 0, width: 900, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = container
            window.orderFrontRegardless()
            defer {
                window.contentView = nil
                window.orderOut(nil)
                window.close()
                if let previousTab { UserDefaults.standard.set(previousTab, forKey: tabKey) } else { UserDefaults.standard.removeObject(forKey: tabKey) }
            }
            for _ in 0..<16 {
                container.layoutSubtreeIfNeeded()
                spin(0.05)
            }

            let rects = container.redlineRegistryForTesting.rects
            let viewport = try #require(rects[RedlineID.listViewport], "no list.viewport frame")
            let tray = try #require(rects[RedlineID.trayGroup], "no tray.group frame")
            let panelBottom = container.sidebarFrameForTesting.height

            // The tray floats in the panel's bottom margin.
            #expect(tray.maxY <= panelBottom + 0.5, "tray \(tray) sits inside the panel (height \(panelBottom))")
            // The list's viewport runs past the tray's bottom edge, so
            // content scrolls under the glass and shows in the gaps around it.
            #expect(
                viewport.maxY >= tray.maxY - 0.5,
                "list viewport ends at y=\(viewport.maxY), above the tray's bottom y=\(tray.maxY) (top \(tray.minY)): the list is cut off and the strip behind the glass is an opaque band"
            )
            // And runs on to the panel's bottom, less the card margin.
            #expect(
                viewport.maxY >= panelBottom - 8 - 0.5,
                "list viewport ends at y=\(viewport.maxY), short of the panel bottom \(panelBottom) less the 8pt card margin"
            )
        }
    }
}

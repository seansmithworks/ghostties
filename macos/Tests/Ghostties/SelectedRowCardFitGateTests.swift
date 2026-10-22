import AppKit
import Combine
import GhosttiesCore
import SwiftUI
import Testing
@testable import Ghostty

/// Amendment 6 (`docs/plans/selected-row-mix-contract.md`, rail stays put,
/// superseding Amendment 5's expanded card): the glass active-group card
/// hugs the rail's tile column in the expanded list too, wrapping the
/// group's tile and chips with an even 4pt gap (the column inset) at the
/// sides and the bottom, with concentric corners (chip radius 8 + gap 4 =
/// card radius 12). Its extent comes from the group's last row's chip, so it
/// never depends on which row is selected.
///
/// Live: a real `WorkspaceViewContainer` in a window, frames from the
/// Redlines registry (`RedlineID.row(id) + ".chip"`, the drawn chip). Do
/// not widen the band.
@MainActor
@Suite(.serialized)
struct SelectedRowCardFitGateTests {
    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    private let atlas = Project(name: "atlas-api", rootPath: "~/Code/atlas-api")
    private let fieldwork = Project(name: "fieldwork", rootPath: "~/Code/fieldwork")

    private struct Rig {
        let container: WorkspaceViewContainer
        let window: NSWindow
        let sessions: [AgentSession]   // atlas-api's two sessions come first
        let restoreTab: () -> Void

        func close() {
            window.contentView = nil
            window.orderOut(nil)
            window.close()
            restoreTab()
        }
    }

    private func spin(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    }

    private func makeRig() -> Rig {
        let tabKey = "ghostties.sidebarTab"
        let previousTab = UserDefaults.standard.object(forKey: tabKey)
        UserDefaults.standard.set(SidebarTab.projects.rawValue, forKey: tabKey)
        let sessions = [
            AgentSession(name: "auth refactor", templateId: AgentTemplate.claudeCode.id, projectId: atlas.id),
            AgentSession(name: "schema pass", templateId: AgentTemplate.claudeCode.id, projectId: atlas.id),
            AgentSession(name: "docs pass", templateId: AgentTemplate.claudeCode.id, projectId: fieldwork.id),
            AgentSession(name: "build fix", templateId: AgentTemplate.claudeCode.id, projectId: fieldwork.id),
        ]
        let store = WorkspaceStore(
            testingProjects: [atlas, fieldwork], testingSessions: sessions,
            hasShownPinMigrationNotice: true, hasDismissedPinMigrationNotice: true
        )
        for s in sessions {
            store.updateSessionStatus(id: s.id, status: .running)
            store.updateIndicatorState(id: s.id, state: .idle)
        }
        store.updateSidebarMode(.pinned)
        let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel(), store: store)
        container.coordinatorForTesting.setActiveSessionIdForTesting(sessions[1].id)
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
        for _ in 0..<10 {
            container.layoutSubtreeIfNeeded()
            spin(0.05)
        }
        return Rig(
            container: container, window: window, sessions: sessions,
            restoreTab: {
                if let previousTab { UserDefaults.standard.set(previousTab, forKey: tabKey) } else { UserDefaults.standard.removeObject(forKey: tabKey) }
            }
        )
    }

    private func settle(_ rig: Rig) {
        for _ in 0..<8 {
            rig.container.layoutSubtreeIfNeeded()
            spin(0.06)
        }
    }

    private func frame(_ rig: Rig, _ id: String) throws -> CGRect {
        try #require(rig.container.redlineRegistryForTesting.rects[id], "no frame for \(id)")
    }

    private let gap: CGFloat = 4
    private let tolerance: CGFloat = 0.5

    @Test func cardWrapsTheLastSelectedRowWithAnEvenFourPointGap() throws {
        try withDials({ $0.set(true, forKey: SidebarDialTuning.redlinesKey) }) {
            let rig = makeRig()
            defer { rig.close() }
            // atlas-api's second (last) session is selected.
            settle(rig)
            let card = try frame(rig, RedlineID.groupCard)
            let chip = try frame(rig, RedlineID.row(rig.sessions[1].id) + ".chip")

            let left = chip.minX - card.minX
            let right = card.maxX - chip.maxX
            let bottom = card.maxY - chip.maxY
            #expect(abs(left - gap) <= tolerance, "left gap \(left), want \(gap)")
            #expect(abs(right - gap) <= tolerance, "right gap \(right), want \(gap)")
            #expect(abs(bottom - gap) <= tolerance, "bottom gap \(bottom), want \(gap)")

            // Concentric corners: the card's radius is the chip's plus the gap
            // actually drawn, so the three agree.
            let metrics = SidebarMorphMetrics(
                expandedWidth: rig.container.sidebarFrameForTesting.width,
                railWidth: WorkspaceLayout.collapsedRailWidth(in: rig.container), progress: 0
            ).card(hasRows: true)
            #expect(metrics.cornerRadius == RailProjectColumn.chipCornerRadius + gap, "card radius \(metrics.cornerRadius), chip radius \(RailProjectColumn.chipCornerRadius)")
            #expect(abs(metrics.cornerRadius - (RailProjectColumn.chipCornerRadius + left)) <= tolerance, "radius \(metrics.cornerRadius) is not chip radius + the drawn gap \(left)")
        }
    }

    @Test func cardFrameDoesNotDependOnWhichRowIsSelected() throws {
        try withDials({ $0.set(true, forKey: SidebarDialTuning.redlinesKey) }) {
            let rig = makeRig()
            defer { rig.close() }
            settle(rig)
            let lastSelected = try frame(rig, RedlineID.groupCard)

            rig.container.coordinatorForTesting.setActiveSessionIdForTesting(rig.sessions[0].id)
            settle(rig)
            let firstSelected = try frame(rig, RedlineID.groupCard)

            for (name, a, b) in [
                ("minX", lastSelected.minX, firstSelected.minX), ("maxX", lastSelected.maxX, firstSelected.maxX),
                ("minY", lastSelected.minY, firstSelected.minY), ("maxY", lastSelected.maxY, firstSelected.maxY),
            ] {
                #expect(abs(a - b) <= tolerance, "card \(name) moved from \(a) to \(b) when the selection changed rows")
            }

            // With the first row selected the card still reaches 4pt past the
            // last row's chip, and 4pt past the chips at the sides.
            let lastChip = try frame(rig, RedlineID.row(rig.sessions[1].id) + ".chip")
            #expect(abs((firstSelected.maxY - lastChip.maxY) - gap) <= tolerance, "bottom gap with the first row selected: \(firstSelected.maxY - lastChip.maxY)")
            let firstChip = try frame(rig, RedlineID.row(rig.sessions[0].id) + ".chip")
            #expect(abs((firstChip.minX - firstSelected.minX) - gap) <= tolerance, "left gap with the first row selected: \(firstChip.minX - firstSelected.minX)")
            #expect(abs((firstSelected.maxX - firstChip.maxX) - gap) <= tolerance, "right gap with the first row selected: \(firstSelected.maxX - firstChip.maxX)")
        }
    }
}

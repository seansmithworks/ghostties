import AppKit
import Combine
import Foundation
import GhosttiesCore
import SwiftUI
import Testing
@testable import Ghostty

/// Gate for "rail stays put" (A2): one rail tile column that never moves
/// between the collapsed rail and the expanded sidebar, or mid-morph.
///
/// - The tile is the same size in both states (40pt).
/// - Its centre x is the same in both states and at every morph progress;
///   the rail is on the 8pt grid (96pt), so the centre is 48.
/// - `tileTravel` is 0: nothing slides across the morph.
/// - The expanded layout's tile column (list edge, glyph slot) is anchored
///   to the rail tile centre.
///
/// Written red against the pre-fix base: today the sidebar tile is 32pt
/// with centre ~32 and the rail is 98pt wide with centre 49.
///
/// The view-tree test runs in a window pinned to `.aqua`, so the result
/// does not follow system dark mode.
@MainActor
@Suite(.serialized)
struct RailStaysPutGateTests {
    private let expandedWidth: CGFloat = 256
    /// The traffic-light cluster's zoom button maxX and leading inset on
    /// macOS 26 (the inputs behind option D's 98pt rail).
    private let zoomMaxX: CGFloat = 79
    private let leadingInset: CGFloat = 19
    private let steps: [CGFloat] = [0, 0.25, 0.5, 0.75, 1]

    private func railWidth() -> CGFloat {
        withDials { WorkspaceLayout.collapsedRailWidth(zoomButtonMaxX: zoomMaxX, leadingInset: leadingInset) }
    }

    private func metrics(_ progress: CGFloat) -> SidebarMorphMetrics {
        let rail = railWidth()
        return withDials {
            SidebarMorphMetrics(expandedWidth: expandedWidth, railWidth: rail, progress: progress)
        }
    }

    // MARK: - Metrics level

    @Test func tileSizeIsEqualAtProgress0And1() {
        #expect(metrics(0).tileSize == metrics(1).tileSize, "tile size \(metrics(0).tileSize) expanded vs \(metrics(1).tileSize) rail")
        #expect(metrics(1).tileSize == 40, "rail tile size \(metrics(1).tileSize)")
        #expect(metrics(0).tileSize == 40, "sidebar tile size \(metrics(0).tileSize)")
    }

    @Test func tileCentreXIsEqualAtEveryProgress() {
        let xs = steps.map { metrics($0).tileCenterX }
        for (p, x) in zip(steps, xs) {
            #expect(x == xs[0], "tile centre x at progress \(p) is \(x), at 0 it is \(xs[0])")
        }
    }

    @Test func tileTravelIsZero() {
        let m = metrics(0)
        #expect(m.tileTravel == 0, "tileTravel \(m.tileTravel): sidebar centre \(m.sidebarTileCenterX), rail centre \(m.railTileCenterX)")
    }

    @Test func railTileCentreXIs48() {
        #expect(railWidth() == 96, "collapsedRailWidth for a 79 + 19 cluster is \(railWidth()), not 96")
        #expect(metrics(1).railTileCenterX == 48, "rail tile centre x \(metrics(1).railTileCenterX)")
    }

    @Test func theExpandedColumnIsAnchoredToTheRailTileCentre() {
        let m = metrics(0)
        #expect(m.sidebarTileCenterX == m.railTileCenterX, "sidebar centre \(m.sidebarTileCenterX) vs rail \(m.railTileCenterX)")
        // The pinned / History glyph slot is the rail tile's width.
        let slot = withDials { SidebarListRowChrome<EmptyView, EmptyView>.glyphSlotWidth }
        #expect(slot == m.dials.railTileSize, "glyph slot \(slot) vs rail tile \(m.dials.railTileSize)")
        // The slot starts where the tile does: list edge + row padding.
        let slotMinX = m.listMinX + m.dials.rowLeadingPadding
        let tileMinX = m.railTileCenterX - m.dials.railTileSize / 2
        #expect(slotMinX == tileMinX, "glyph slot minX \(slotMinX) vs rail tile minX \(tileMinX)")
    }

    // MARK: - Real view tree

    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    private func spin(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    }

    @Test func theDrawnTileAndChipNeverMoveOrResizeAcrossTheMorph() throws {
        try withDials({ $0.set(true, forKey: SidebarDialTuning.redlinesKey) }) {
            let tabKey = "ghostties.sidebarTab"
            let previousTab = UserDefaults.standard.object(forKey: tabKey)
            UserDefaults.standard.set(SidebarTab.projects.rawValue, forKey: tabKey)
            defer {
                if let previousTab { UserDefaults.standard.set(previousTab, forKey: tabKey) } else { UserDefaults.standard.removeObject(forKey: tabKey) }
            }

            let atlas = Project(name: "atlas-api", rootPath: "~/Code/atlas-api")
            let sessions = [
                AgentSession(name: "auth refactor", templateId: AgentTemplate.claudeCode.id, projectId: atlas.id),
                AgentSession(name: "schema pass", templateId: AgentTemplate.claudeCode.id, projectId: atlas.id),
            ]
            let store = WorkspaceStore(
                testingProjects: [atlas], testingSessions: sessions,
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
            defer {
                window.contentView = nil
                window.orderOut(nil)
                window.close()
            }
            for _ in 0..<10 { container.layoutSubtreeIfNeeded(); spin(0.05) }

            let tile = RedlineID.header(atlas.id.uuidString) + ".tile"
            let chip = RedlineID.row(sessions[1].id) + ".chip"
            var tiles: [CGFloat: CGRect] = [:]
            var chips: [CGFloat: CGRect] = [:]
            for p in steps {
                container.applyMorphStep(p)
                for _ in 0..<6 { container.layoutSubtreeIfNeeded(); spin(0.05) }
                tiles[p] = try #require(container.redlineRegistryForTesting.rects[tile], "no tile frame at \(p)")
                chips[p] = try #require(container.redlineRegistryForTesting.rects[chip], "no chip frame at \(p)")
            }
            let t0 = try #require(tiles[0]), t1 = try #require(tiles[1])
            #expect(abs(t0.width - t1.width) <= 0.5, "tile width \(t0.width) expanded vs \(t1.width) rail")
            for p in steps {
                let t = try #require(tiles[p]), c = try #require(chips[p])
                #expect(abs(t.midX - t1.midX) <= 0.5, "tile centre x at \(p): \(t.midX), rail \(t1.midX)")
                #expect(abs(c.midX - t1.midX) <= 0.5, "chip centre x at \(p): \(c.midX), rail tile \(t1.midX)")
            }
            let hosted = WorkspaceLayout.collapsedRailWidth(in: container)
            #expect(abs(t1.midX - hosted / 2) <= 0.5, "rail tile centre x \(t1.midX), hosted rail \(hosted) wide")
        }
    }
}

import AppKit
import DialkitmacOSCore
import Combine
import Foundation
import GhosttiesCore
import SwiftUI
import Testing
@testable import Ghostty

/// The sidebar ⇄ rail morph's gates (morph plan §4), on a real
/// `WorkspaceViewContainer` in a 900×620 window, on a persistence-disabled
/// `WorkspaceStore` (never `.shared`):
///
/// - Path: the selected group's tile, a row's chip and the group card at
///   morph 0.5 sit on the midpoint of their frames at 0 and 1, and the ends
///   are `SidebarMorphMetrics`' sidebar and rail geometry.
/// - Identity: a pinned → rail → pinned round trip mounts each of those
///   elements once. Two trees crossfading mount them again.
/// - Perf: one toggle runs `RecentsListView.body` at most twice.
///
/// Frames come from the Redlines registry (`redlineFrame`), switched on in
/// a private dial suite (`withDials`). Mounts and body passes come from the
/// container's `MorphProbe`.
@MainActor
@Suite(.serialized)
struct SidebarMorphGateTests {
    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    private let atlas = Project(name: "atlas-api", rootPath: "~/Code/atlas-api")
    private let fieldwork = Project(name: "fieldwork", rootPath: "~/Code/fieldwork")

    private struct Rig {
        let container: WorkspaceViewContainer
        let store: WorkspaceStore
        let window: NSWindow
        let groupId: String
        let selected: UUID
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
        while Date() < end {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    /// Two projects with two running sessions each, the Projects tab in One
    /// view, the second atlas-api session selected (its group carries the
    /// card), pinned.
    private func makeRig() -> Rig {
        // The tab is store-less `@AppStorage` (`.standard`, the test host's
        // own domain); pin it to Projects for this rig and put it back.
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
        // ARC owns it; `close()` must not release it a second time.
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
            container: container, store: store, window: window, groupId: atlas.id.uuidString, selected: sessions[1].id,
            restoreTab: {
                if let previousTab { UserDefaults.standard.set(previousTab, forKey: tabKey) } else { UserDefaults.standard.removeObject(forKey: tabKey) }
            }
        )
    }

    // MARK: - Path

    private func settledFrames(_ rig: Rig, ids: [String]) throws -> [String: CGRect] {
        for _ in 0..<6 {
            rig.container.layoutSubtreeIfNeeded()
            spin(0.05)
        }
        return try ids.reduce(into: [:]) { out, id in
            out[id] = try #require(rig.container.redlineRegistryForTesting.rects[id], "no frame for \(id)")
        }
    }

    private func frames(_ rig: Rig, at progress: CGFloat, ids: [String]) throws -> [String: CGRect] {
        rig.container.applyMorphStep(progress)
        for _ in 0..<6 {
            rig.container.layoutSubtreeIfNeeded()
            spin(0.05)
        }
        var out: [String: CGRect] = [:]
        for id in ids {
            out[id] = try #require(rig.container.redlineRegistryForTesting.rects[id], "no frame for \(id) at morph \(progress)")
        }
        return out
    }

    @Test func tileChipAndCardTravelOnAStraightLineBetweenTheirEnds() throws {
        try withDials({ $0.set(true, forKey: SidebarDialTuning.redlinesKey) }) {
            let rig = makeRig()
            defer { rig.close() }
            let tile = RedlineID.header(rig.groupId) + ".tile"
            let chip = RedlineID.row(rig.selected) + ".chip"
            let card = RedlineID.groupCard
            let ids = [tile, chip, card]

            let expandedWidth = rig.container.sidebarFrameForTesting.width
            let railWidth = WorkspaceLayout.collapsedRailWidth(in: rig.container)
            let start = try frames(rig, at: 0, ids: ids)
            let end = try frames(rig, at: 1, ids: ids)
            let mid = try frames(rig, at: 0.5, ids: ids)

            // The ends are the metrics' sidebar and rail.
            for (frame, progress) in [(start, CGFloat(0)), (end, 1)] {
                let m = SidebarMorphMetrics(expandedWidth: expandedWidth, railWidth: railWidth, progress: progress)
                let t = try #require(frame[tile]), c = try #require(frame[chip]), k = try #require(frame[card])
                #expect(abs(t.midX - m.tileCenterX) <= 0.5, "tile centre x at \(progress): \(t.midX) vs \(m.tileCenterX)")
                #expect(abs(t.width - m.tileSize) <= 0.5, "tile size at \(progress): \(t.width) vs \(m.tileSize)")
                #expect(abs(c.midX - m.tileCenterX) <= 0.5, "chip centre x at \(progress): \(c.midX) vs \(m.tileCenterX)")
                #expect(abs(c.width - m.chipSize) <= 0.5, "chip size at \(progress): \(c.width) vs \(m.chipSize)")
                let shape = m.card(hasRows: true)
                #expect(abs(k.minX - shape.minX) <= 0.5, "card min x at \(progress): \(k.minX) vs \(shape.minX)")
                #expect(abs(k.width - shape.width) <= 0.5, "card width at \(progress): \(k.width) vs \(shape.width)")
            }

            // The midpoint is halfway on every edge.
            for id in ids {
                let a = try #require(start[id]), b = try #require(end[id]), m = try #require(mid[id])
                for (name, value, from, to) in [
                    ("minX", m.minX, a.minX, b.minX), ("minY", m.minY, a.minY, b.minY),
                    ("width", m.width, a.width, b.width), ("height", m.height, a.height, b.height),
                ] {
                    #expect(abs(value - (from + to) / 2) <= 0.5, "\(id) \(name) at 0.5: \(value), ends \(from) / \(to)")
                }
            }
        }
    }

    // MARK: - Live dials

    /// A Rail-panel edit, written the way the inspector writes it and
    /// announced the way `SidebarDialInspector.start` announces it, resizes
    /// the rail's drawn tile and chip while the tree stays mounted.
    @available(macOS 14, *)
    @Test func aRailDialEditRedrawsTheRailLive() throws {
        try withDials({ $0.set(true, forKey: SidebarDialTuning.redlinesKey) }) {
            let rig = makeRig()
            defer { rig.close() }
            let tile = RedlineID.header(rig.groupId) + ".tile"
            let chip = RedlineID.row(rig.selected) + ".chip"
            rig.container.toggleSidebar()
            spin(0.6)
            #expect(rig.container.sidebarModeForTesting == .collapsed)
            let before = try settledFrames(rig, ids: [tile, chip])

            let defaults = SidebarDialTuning.store
            let coordinator = FocusedDialKitCoordinator<RailDialPanel>(defaults: defaults) {
                rig.store.objectWillChange.send()
                NotificationCenter.default.post(name: SidebarDialTuning.didChangeNotification, object: nil)
            }
            coordinator.state.values.railProjectTileSize = 31
            coordinator.state.values.railThreadTileSize = 25
            for _ in 0..<6 {
                rig.container.layoutSubtreeIfNeeded()
                spin(0.05)
            }

            let after = try settledFrames(rig, ids: [tile, chip])
            let t0 = try #require(before[tile]), t1 = try #require(after[tile])
            let c0 = try #require(before[chip]), c1 = try #require(after[chip])
            #expect(abs(t1.width - 31) <= 0.5, "rail tile stayed \(t0.width) -> \(t1.width) after the dial was set to 31")
            #expect(abs(c1.width - 25) <= 0.5, "rail chip stayed \(c0.width) -> \(c1.width) after the dial was set to 25")
        }
    }

    // MARK: - Identity

    @Test func aRoundTripMountsEachElementOnce() throws {
        let rig = makeRig()
        defer { rig.close() }
        let tile = RedlineID.header(rig.groupId) + ".tile"
        let chip = RedlineID.row(rig.selected) + ".chip"
        let probe = rig.container.morphProbe
        for id in [tile, chip, RedlineID.groupCard] {
            #expect(probe.appearCounts[id] == 1, "\(id) mounted \(probe.appearCounts[id] ?? 0)× before the toggle")
        }

        rig.container.toggleSidebar()
        spin(0.6)
        #expect(rig.container.sidebarModeForTesting == .collapsed)
        rig.container.toggleSidebar()
        spin(0.6)
        #expect(rig.container.sidebarModeForTesting == .pinned)

        for (id, count) in probe.appearCounts.sorted(by: { $0.key < $1.key }) {
            #expect(count == 1, "\(id) mounted \(count)× across pinned → rail → pinned")
        }
    }

    // MARK: - Perf

    @Test func aToggleRunsTheListBodyAtMostTwice() throws {
        let rig = makeRig()
        defer { rig.close() }
        let probe = rig.container.morphProbe
        let key = "RecentsListView.body"
        for target in [SidebarMode.collapsed, .pinned] {
            let before = probe.bodyCounts[key] ?? 0
            rig.container.toggleSidebar()
            spin(0.6)
            #expect(rig.container.sidebarModeForTesting == target)
            let runs = (probe.bodyCounts[key] ?? 0) - before
            #expect(runs <= 2, "RecentsListView.body ran \(runs)× toggling to \(target)")
        }
    }
}

import XCTest
import SwiftUI
import Vision
import GhosttiesCore
@testable import Ghostty

/// Hover-approvals follow-up B (Sean, 2026-10-22): a needs-you row in the
/// Pinned section or the flat Sessions list gets the same question subtitle
/// and action line as a grouped row, at the same reserved height
/// (`SidebarListRowHeight`), so its drag gap is its drawn height.
///
/// Fixture state only: invented hook payloads in a temp `ClaudeStateStore`,
/// no `~/.claude` or `~/.ghostties` read.
@MainActor
final class HoverApprovalsFollowupTests: XCTestCase {
    private let bashId = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000E1")!
    private let askId = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000E2")!
    private let workingId = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000E3")!

    private let bashPermission = #"{"cwd":"/tmp","hook_event_name":"PermissionRequest","session_id":"c-1","tool_name":"Bash","tool_input":{"command":"npm test"}}"#
    private let askQuestion = #"{"cwd":"/tmp","hook_event_name":"PreToolUse","session_id":"c-2","tool_name":"AskUserQuestion","tool_use_id":"tu-1","tool_input":{"questions":[{"question":"Which env name?","header":"Env","options":[{"label":"staging"},{"label":"prod"}],"multiSelect":false}]}}"#
    private let busyTool = #"{"cwd":"/tmp","hook_event_name":"PreToolUse","session_id":"c-3","tool_name":"Bash","tool_use_id":"tu-3","tool_input":{"command":"ls"}}"#

    private let tabKey = "ghostties.sidebarTab"
    private var previousTab: Any?
    private var tempDirs: [URL] = []

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(false, forKey: ApprovalFlag.defaultsKey)
        previousTab = UserDefaults.standard.object(forKey: tabKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: ApprovalFlag.defaultsKey)
        if let previousTab { UserDefaults.standard.set(previousTab, forKey: tabKey) } else { UserDefaults.standard.removeObject(forKey: tabKey) }
        for dir in tempDirs { try? FileManager.default.removeItem(at: dir) }
        tempDirs = []
        super.tearDown()
    }

    // MARK: - Fixtures

    private enum Kind { case bash, ask, working }

    private func makeClaudeStore() -> (ClaudeStateStore, (String, UUID) -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HoverApprovalsFollowup-\(UUID().uuidString)", isDirectory: true)
        tempDirs.append(dir)
        let store = ClaudeStateStore(directoryURL: dir)
        store.resumeWriterForTesting = { _, _ in }
        let write: (String, UUID) -> Void = { hook, id in
            let json = #"{"ghosttiesSessionId":"\#(id.uuidString)","updatedAt":\#(Int(Date().timeIntervalSince1970)),"hook":\#(hook)}"#
            try? json.write(to: dir.appendingPathComponent("\(id.uuidString).json"), atomically: true, encoding: .utf8)
            store.refreshForTesting()
        }
        return (store, write)
    }

    private struct World {
        let store: WorkspaceStore
        let coordinator: SessionCoordinator
    }

    /// One project, one session per `kinds` entry, each pinned when `pinned`.
    private func world(_ kinds: [Kind], pinned: Bool) -> World {
        let project = Project(name: "atlas-api", rootPath: "/Users/example/work/atlas-api")
        let ids: [Kind: UUID] = [.bash: bashId, .ask: askId, .working: workingId]
        let names: [Kind: String] = [.bash: "deploy preview", .ask: "schema notes", .working: "auth refactor"]
        let hooks: [Kind: String] = [.bash: bashPermission, .ask: askQuestion, .working: busyTool]
        let indicators: [Kind: SessionIndicatorState] = [.bash: .needsAttention, .ask: .needsAttention, .working: .processing]
        let sessions = kinds.map {
            AgentSession(
                id: ids[$0]!, name: names[$0]!, templateId: UUID(), projectId: project.id,
                lastActiveAt: Date(), lastOutputAt: Date(), isNamePinned: true, isPinned: pinned
            )
        }
        let store = WorkspaceStore(
            testingProjects: [project], testingSessions: sessions,
            hasShownPinMigrationNotice: true, hasDismissedPinMigrationNotice: true
        )
        let (claude, write) = makeClaudeStore()
        for kind in kinds {
            write(hooks[kind]!, ids[kind]!)
            store.updateIndicatorState(id: ids[kind]!, state: indicators[kind]!)
            store.updateSessionStatus(id: ids[kind]!, status: .running)
        }
        let coordinator = SessionCoordinator()
        coordinator.claudeStateStoreForTesting = claude
        return World(store: store, coordinator: coordinator)
    }

    /// Where a row sits: the Pinned section, or the flat Sessions list.
    private enum Placement: String, CaseIterable { case pinned, flat }

    private func list(_ kinds: [Kind], _ placement: Placement, drag: SessionDragState = SessionDragState()) -> some View {
        UserDefaults.standard.set((placement == .flat ? SidebarTab.sessions : SidebarTab.projects).rawValue, forKey: tabKey)
        let w = world(kinds, pinned: placement == .pinned)
        return RecentsListView(previewDragState: drag, pinningAvailable: placement == .pinned)
            .environmentObject(w.store)
            .environmentObject(w.coordinator)
            .environmentObject(SidebarWidthModel(width: 320))
    }

    // MARK: - Rendering

    private func render<V: View>(_ view: V, size: CGSize) -> NSBitmapImageRep? {
        let framed = view
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.white)
        let hosting = NSHostingView(rootView: framed)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }

    /// Lower-cased text Vision reads in `rep`, upscaled 3x first.
    private func text(in rep: NSBitmapImageRep?) -> String {
        guard let cg = rep?.cgImage else { return "" }
        let scale = 3
        let w = cg.width * scale, h = cg.height * scale
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return "" }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let big = ctx.makeImage() else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: big, options: [:]).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n").lowercased()
    }

    /// The list's laid-out height.
    private func height<V: View>(_ view: V) -> CGFloat {
        let hosting = NSHostingView(rootView: view.frame(width: 320))
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }

    // MARK: - B. Pinned and flat rows ask their question and answer inline

    func testPinnedAndFlatNeedsYouRowsShowQuestionAndActionLine() {
        for placement in Placement.allCases {
            let shown = text(in: render(list([.bash, .ask, .working], placement), size: CGSize(width: 320, height: 480)))
            XCTAssertTrue(shown.contains("deploy preview") && shown.contains("auth refactor"),
                          "\(placement): control, the rows render; list shows \(shown.debugDescription)")
            XCTAssertTrue(shown.contains("run npm test?"), "\(placement): bounded row's subtitle is its question; list shows \(shown.debugDescription)")
            XCTAssertTrue(shown.contains("which env name?"), "\(placement): freeform row's subtitle is its question; list shows \(shown.debugDescription)")
            XCTAssertTrue(shown.contains("answer in terminal"), "\(placement): flag off, needs-you rows draw \"Answer in terminal →\"; list shows \(shown.debugDescription)")
            XCTAssertFalse(shown.contains("approve"), "\(placement): flag off, no Approve; list shows \(shown.debugDescription)")
        }
    }

    func testPinnedAndFlatBoundedRowsShowApproveDenyWithFlagOn() {
        UserDefaults.standard.set(true, forKey: ApprovalFlag.defaultsKey)
        for placement in Placement.allCases {
            let shown = text(in: render(list([.bash], placement), size: CGSize(width: 320, height: 320)))
            XCTAssertTrue(shown.contains("approve") && shown.contains("deny"),
                          "\(placement): flag on, the bounded row shows inline Approve and Deny; list shows \(shown.debugDescription)")
        }
    }

    /// A needs-you row draws at `SidebarListRowHeight.row(hasActions: true)`:
    /// the list is exactly one action line taller than with a plain row.
    func testPinnedAndFlatNeedsYouRowsHoldTheReservedHeight() {
        let added = SidebarListRowHeight.actionLine(hasActions: true)
        XCTAssertGreaterThan(added, 0)
        for placement in Placement.allCases {
            let plain = height(list([.working], placement))
            let needing = height(list([.bash], placement))
            XCTAssertGreaterThan(plain, 0, "\(placement): control, the list lays out")
            XCTAssertEqual(needing - plain, added, accuracy: 0.5,
                           "\(placement): a needs-you row is one action line (\(added)pt) taller than a plain row")
        }
    }

    /// The live drag gap is the dragged row's own height, so the list's
    /// total height is the same whichever row is in flight: dragging the
    /// needs-you row leaves the plain row plus a tall gap, dragging the
    /// plain row leaves the needs-you row plus a plain gap. A gap sized as
    /// a plain row either way would make the first one action line shorter.
    func testPinnedAndFlatDragGapIsTheDraggedRowsHeight() {
        for placement in Placement.allCases {
            let section: SessionSection = placement == .pinned ? .pinned : .active
            func dragging(_ id: UUID) -> CGFloat {
                height(list([.bash, .working], placement, drag: SessionDragState(draggingSessionId: id, gap: .init(section: section, index: 0))))
            }
            let rest = height(list([.bash, .working], placement))
            let tallInFlight = dragging(bashId)
            let plainInFlight = dragging(workingId)
            XCTAssertGreaterThan(rest, 0, "\(placement): control, the list lays out")
            XCTAssertEqual(tallInFlight, plainInFlight, accuracy: 0.5,
                           "\(placement): the gap is the dragged needs-you row's drawn height (\(SidebarListRowHeight.row(hasActions: true))pt)")
        }
    }
}

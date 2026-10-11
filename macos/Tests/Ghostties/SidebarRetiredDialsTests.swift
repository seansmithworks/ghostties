import XCTest
import SwiftUI
import GhosttiesCore
@testable import Ghostty

/// The vnext lock (2026-10-08) removed the losing dial options: Selected row
/// keeps only Tint + shimmer, Tray style only Glass, and History placement
/// only Bottom. A value a Dev build stored under a retired key must change
/// nothing: the sidebar renders exactly as with nothing stored, and the
/// selected row still draws (no blank). Uses private suites only.
@MainActor
final class SidebarRetiredDialsTests: XCTestCase {
    func testTintShimmerDarkIntensityDefaultsToLightAndRoundTrips() {
        let name = "com.seansmithdesign.ghostties.tests.tint-shimmer-dark"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        defer { d.removePersistentDomain(forName: name) }
        XCTAssertEqual(SidebarDialTuning.tintShimmerDarkIntensityKey, "ghostties.sidebarDial.tintShimmerDarkIntensity")
        XCTAssertEqual(SidebarDialTuning.tintShimmerDarkIntensity(defaults: d), TrayGlassStyle.light.chromaticIntensity)
        XCTAssertGreaterThan(SidebarDialTuning.tintShimmerDarkIntensity(defaults: d), 0)
        d.set(0.65, forKey: SidebarDialTuning.tintShimmerDarkIntensityKey)
        XCTAssertEqual(SidebarDialTuning.tintShimmerDarkIntensity(defaults: d), 0.65)
        XCTAssertTrue(SidebarDialTuning.allKeys.contains(SidebarDialTuning.tintShimmerDarkIntensityKey))
    }

    /// "Reset sidebar" clears the retired keys too, so a stale value can't
    /// linger in a Dev domain.
    func testResetClearsRetiredKeys() {
        let name = "com.seansmithdesign.ghostties.tests.retired-reset"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        defer { d.removePersistentDomain(forName: name) }
        for key in SidebarDialTuning.retiredKeys { d.set("x", forKey: key) }
        SidebarDialTuning.reset(defaults: d)
        for key in SidebarDialTuning.retiredKeys { XCTAssertNil(d.object(forKey: key), key) }
        XCTAssertTrue(Set(SidebarDialTuning.retiredKeys).isDisjoint(with: SidebarDialTuning.allKeys))
    }

    /// The tray pills and the canvas card sit the window margin inside the
    /// window, so both are concentric with its corner: radius = window
    /// radius − margin, at any margin. A value stored under the retired
    /// tray corner-radius dial changes nothing.
    func testTrayPillsAndCanvasAreConcentricWithTheWindowCorner() {
        let name = "com.seansmithdesign.ghostties.tests.concentric-radius"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        defer { d.removePersistentDomain(forName: name) }
        XCTAssertEqual(WorkspaceLayout.windowCornerRadius, 16, "measured on macOS 27, 2026-10-08")
        XCTAssertEqual(SidebarDialTuning.trayCornerRadius(defaults: d), 8, "16 − the 8pt window margin")
        d.set(20.0, forKey: SidebarDialTuning.retiredTrayCornerRadiusKey)
        XCTAssertEqual(SidebarDialTuning.trayCornerRadius(defaults: d), 8, "the retired dial is ignored")
        for margin in [0.0, 4.0, 12.0, 24.0] {
            d.set(margin, forKey: SidebarDialTuning.windowMarginKey)
            XCTAssertEqual(SidebarDialTuning.trayCornerRadius(defaults: d), max(0, 16 - CGFloat(margin)), "margin \(margin)")
        }
        withDials {
            XCTAssertEqual(WorkspaceLayout.terminalCornerRadius, SidebarDialTuning.trayCornerRadius(), "card and pills share the rule")
        }
        withDials({ $0.set(4.0, forKey: SidebarDialTuning.windowMarginKey) }) {
            XCTAssertEqual(WorkspaceLayout.terminalCornerRadius, 12, "the card follows the margin dial")
        }
    }

    /// Every removed option stored at once (the flat and glass selected
    /// rows, the bare tray, History after Active) renders pixel-identical to
    /// an empty store, in the expanded sidebar and the rail.
    func testStoredRemovedOptionsRenderAsTheSurvivors() throws {
        let removed: [(String, String)] = [
            (SidebarDialTuning.retiredSelectedRowStyleKey, "flat"),
            (SidebarDialTuning.retiredLegacySelectedStyleKey, "glass"),
            (SidebarDialTuning.retiredTrayStyleKey, "bare"),
            (SidebarDialTuning.retiredHistoryPlacementKey, "afterActive"),
        ]
        for rail in [false, true] {
            let survivor = try render(rail: rail, stored: [])
            let migrated = try render(rail: rail, stored: removed)
            XCTAssertEqual(survivor.pixelsWide, migrated.pixelsWide)
            XCTAssertEqual(survivor.pixelsHigh, migrated.pixelsHigh)
            XCTAssertEqual(differingPixels(survivor, migrated), 0, "stored removed options changed the render (rail: \(rail))")
            // The rail marks the selected session with a tile-sized chip in
            // its project column (`RailProjectColumn`), not a row-tall card.
            let minimum = rail ? RailProjectColumn.chipSize - 10 : SidebarDialTuning.rowHeight() - 8
            XCTAssertGreaterThan(longestTintRun(migrated, width: rail ? 80 : 260, rail: rail), minimum, "the selected row is not blank (rail: \(rail))")
        }
    }

    // MARK: - Harness

    private func render(rail: Bool, stored: [(String, String)]) throws -> NSBitmapImageRep {
        try withDials({ suite in
            // History shown, so a placement change would move it.
            suite.set(true, forKey: SidebarDialTuning.historyInSidebarKey)
            for (key, value) in stored { suite.set(value, forKey: key) }
        }) {
            let project = Project(name: "atlas-api", rootPath: "~/Code/atlas-api")
            let ids = ["9B2A6E10-0000-4A11-8B00-000000000000", "9B2A6E10-0000-4A11-8B00-000000000001"]
            var live: [AgentSession] = []
            for (i, id) in ids.enumerated() {
                live.append(AgentSession(
                    id: try XCTUnwrap(UUID(uuidString: id)),
                    name: "Session \(i)", templateId: AgentTemplate.claudeCode.id, projectId: project.id,
                    sortOrder: i, lastActiveAt: Date(timeIntervalSince1970: 1_800_000_000),
                    lastOutputAt: Date(timeIntervalSince1970: 1_800_000_000), isNamePinned: true
                ))
            }
            let past = AgentSession(
                id: try XCTUnwrap(UUID(uuidString: "9B2A6E10-0000-4A11-8B00-0000000000FF")),
                name: "past", templateId: AgentTemplate.claudeCode.id, projectId: project.id,
                sortOrder: 9, lastActiveAt: Date(timeIntervalSince1970: 1_799_000_000), isNamePinned: true
            )
            let store = WorkspaceStore(
                testingProjects: [project], testingSessions: live + [past],
                hasShownPinMigrationNotice: true, hasDismissedPinMigrationNotice: true
            )
            for s in live {
                store.updateIndicatorState(id: s.id, state: .inactive)
                store.updateSessionStatus(id: s.id, status: .running)
            }
            let coordinator = SessionCoordinator()
            coordinator.setActiveSessionIdForTesting(live[0].id)

            let width: CGFloat = rail ? 80 : 260
            let height: CGFloat = 480
            let column: AnyView = rail
                ? AnyView(SidebarRailView())
                : AnyView(VStack(spacing: 0) {
                    Color.clear.frame(height: store.toolbarRowTopAnchorConstant * 2)
                    RecentsListView()
                    Spacer(minLength: 0)
                    Color.clear.frame(height: SidebarTray.reservedHeight(isVertical: false))
                })
            let chrome = try XCTUnwrap(WorkspaceLayout.chromeBackgroundLight.usingColorSpace(.sRGB))
            let root = column
                .frame(width: width, height: height)
                .overlay(alignment: .bottom) {
                    SidebarTray(isVertical: rail, toggleLabel: rail ? "Expand Sidebar" : "Collapse Sidebar", forceOpaque: true)
                }
                .environment(\.sidebarTrailingGutter, 0)
                .environmentObject(store)
                .environmentObject(coordinator)
                .environmentObject(SidebarWidthModel(width: width))
                .background(Color(nsColor: chrome))
            let hosting = NSHostingView(rootView: root)
            hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = hosting
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            hosting.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            return rep
        }
    }

    private func differingPixels(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Int {
        var count = 0
        for y in stride(from: 0, to: a.pixelsHigh, by: 1) {
            for x in stride(from: 0, to: a.pixelsWide, by: 1) {
                guard let ca = a.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      let cb = b.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let d = abs(ca.redComponent - cb.redComponent) + abs(ca.greenComponent - cb.greenComponent)
                    + abs(ca.blueComponent - cb.blueComponent)
                if d > 0.02 { count += 1 }
            }
        }
        return count
    }

    /// The longest run, in points, of pixels the selected row's tint darkens
    /// below the chrome, down one column clear of the rim and the row's ink.
    /// In the rail that line runs 4pt inside the selected chip, and the
    /// floor sits above the project column's faint tint (~0.08).
    private func longestTintRun(_ rep: NSBitmapImageRep, width: CGFloat, rail: Bool) -> CGFloat {
        guard let chrome = WorkspaceLayout.chromeBackgroundLight.usingColorSpace(.sRGB) else { return 0 }
        let base = chrome.redComponent + chrome.greenComponent + chrome.blueComponent
        let scale = CGFloat(rep.pixelsWide) / width
        let x = rail ? width / 2 - RailProjectColumn.chipSize / 2 + 4 : SidebarDialTuning.windowMargin() + 6
        let px = Int(x * scale)
        let floor: CGFloat = rail ? 0.12 : 0.08
        var longest = 0, run = 0
        for y in 0..<rep.pixelsHigh {
            guard let c = rep.colorAt(x: px, y: y)?.usingColorSpace(.sRGB) else { run = 0; continue }
            let delta = base - (c.redComponent + c.greenComponent + c.blueComponent)
            run = (delta > floor && delta < 0.5) ? run + 1 : 0
            longest = max(longest, run)
        }
        return CGFloat(longest) / scale
    }
}

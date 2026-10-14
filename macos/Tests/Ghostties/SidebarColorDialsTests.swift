#if DEBUG
import XCTest
import SwiftUI
import DialkitmacOS
import DialkitmacOSProtocol
import GhosttiesCore
@testable import Ghostty

/// The "Sidebar colors" DialKit panel (beta.27, DEBUG only): untouched it
/// reads exactly the shipped colours, each dial reaches the pixels it names,
/// its reset and "Reset all panels" put everything back, and its contrast
/// rows are WCAG ratios. Private suites only.
@MainActor
final class SidebarColorDialsTests: XCTestCase {
    private static let schemes: [ColorScheme] = [.light, .dark]

    private func suite(_ tag: String) -> UserDefaults {
        let name = "com.seansmithdesign.ghostties.tests.sidebar-colors.\(tag)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    // MARK: Baked defaults

    /// An empty store reads the shipped expressions themselves, so an
    /// untouched panel (and Release, which never reads a key) draws today's
    /// colours.
    func testEmptyStoreReadsTheShippedColors() {
        let d = suite("empty")
        for scheme in Self.schemes {
            let dark = scheme == .dark
            XCTAssertEqual(SidebarColors.background(scheme, defaults: d),
                           dark ? WorkspaceLayout.chromeBackgroundDark : WorkspaceLayout.chromeBackgroundLight)
            XCTAssertEqual(SidebarColors.primaryText(scheme, defaults: d), Color.primary)
            XCTAssertEqual(SidebarColors.secondaryText(scheme, defaults: d),
                           dark ? WorkspaceLayout.textSecondaryDark : WorkspaceLayout.textSecondaryLight)
            XCTAssertEqual(SidebarColors.tileFill(scheme, defaults: d),
                           dark ? Color.white.opacity(0.07) : Color(red: 40 / 255, green: 34 / 255, blue: 30 / 255).opacity(0.10))
            XCTAssertEqual(SidebarColors.tileInk(scheme, defaults: d),
                           dark ? Color(red: 0xF0 / 255, green: 0xEF / 255, blue: 0xED / 255)
                                : Color(red: 0x23 / 255, green: 0x21 / 255, blue: 0x20 / 255))
            XCTAssertEqual(SidebarColors.selectedRowTint(scheme, defaults: d),
                           (dark ? Color.white : Color.black).opacity(0.10))
            XCTAssertEqual(SidebarColors.dimmedProject(scheme, defaults: d), WorkspaceLayout.emptyProjectForeground)
            for role in SidebarColors.Role.allCases {
                XCTAssertNil(SidebarColorTuning.override(role, scheme, defaults: d), "\(role) \(scheme)")
            }
            XCTAssertNil(SidebarColorTuning.dimmedOverride(scheme, defaults: d))
        }
    }

    /// What each dial shows unset: the shipped values, in hex.
    func testPanelShowsTheShippedValues() {
        let d = suite("panel-defaults")
        let model = SidebarColorsDialPanel.read(d)
        XCTAssertEqual(model.light.background, "#F0E9E6")
        XCTAssertEqual(model.dark.background, "#242424")
        XCTAssertEqual(model.light.secondaryText, "#5E5E5E")
        XCTAssertEqual(model.dark.secondaryText, "#A6A6A6")
        XCTAssertEqual(model.light.primaryText, "#000000")
        XCTAssertEqual(model.dark.primaryText, "#FFFFFF")
        XCTAssertEqual(model.light.primaryTextOpacity, 0.85, accuracy: 0.01)
        XCTAssertEqual(model.light.tileFill, "#28221E")
        XCTAssertEqual(model.light.tileFillOpacity, 0.10, accuracy: 1e-9)
        XCTAssertEqual(model.dark.tileFill, "#FFFFFF")
        XCTAssertEqual(model.dark.tileFillOpacity, 0.07, accuracy: 1e-9)
        XCTAssertEqual(model.light.tileInk, "#232120")
        XCTAssertEqual(model.dark.tileInk, "#F0EFED")
        XCTAssertEqual(model.light.selectedRowTint, "#000000")
        XCTAssertEqual(model.dark.selectedRowTint, "#FFFFFF")
        XCTAssertEqual(model.light.selectedRowTintOpacity, 0.10, accuracy: 1e-9)
        XCTAssertEqual(model.dark.selectedRowTintOpacity, 0.10, accuracy: 1e-9)
        // Reading the panel writes nothing.
        for key in SidebarColorTuning.allKeys { XCTAssertNil(d.object(forKey: key), key) }
    }

    // MARK: Writes and resets

    /// A panel edit persists only the moved field; the readout rows never
    /// reach the store.
    func testPanelWritesOnlyTheMovedField() {
        let d = suite("diff-write")
        let before = SidebarColorsDialPanel.read(d)
        var after = before
        after.dark.secondaryText = "#B0B0B0"
        after.light.contrastPrimary = "edited"
        SidebarColorsDialPanel.write(d, from: before, to: after)
        let written = SidebarColorTuning.allKeys.filter { d.object(forKey: $0) != nil }
        XCTAssertEqual(written, [SidebarColorTuning.hexKey(.secondaryText, .dark)])
        XCTAssertEqual(SidebarColors.secondaryText(.dark, defaults: d), Color(.sRGB, red: 0xB0 / 255, green: 0xB0 / 255, blue: 0xB0 / 255, opacity: 1))
        XCTAssertEqual(SidebarColors.secondaryText(.light, defaults: d), WorkspaceLayout.textSecondaryLight, "the other appearance is untouched")
    }

    /// An opacity alone keeps the shipped hue.
    func testOpacityAloneKeepsTheShippedColor() throws {
        let d = suite("opacity-only")
        d.set(0.3, forKey: SidebarColorTuning.opacityKey(.selectedRowTint, .light))
        let tuned = try XCTUnwrap(SidebarColorTuning.override(.selectedRowTint, .light, defaults: d))
        XCTAssertEqual(tuned, SidebarColorTuning.RGBA(r: 0, g: 0, b: 0, a: 0.3))
        d.set(0.5, forKey: SidebarColorTuning.dimmedOpacityKey(.dark))
        XCTAssertEqual(try XCTUnwrap(SidebarColorTuning.dimmedOverride(.dark, defaults: d)).a, 0.5)
    }

    /// The panel's own Reset clears exactly its keys; "Reset all panels"
    /// clears them too. The keys belong to no other panel.
    func testResetAndResetAllClearTheColorKeys() {
        XCTAssertTrue(Set(SidebarColorTuning.allKeys).isSubset(of: SidebarDialTuning.allKeys))
        let others = Set(SidebarDialTuning.railKeys + SidebarDialTuning.sidebarListKeys + SidebarDialTuning.trayShadowStateKeys)
        XCTAssertTrue(Set(SidebarColorTuning.allKeys).isDisjoint(with: others))
        XCTAssertTrue(Set(SidebarColorTuning.allKeys).isDisjoint(with: SidebarDialTuning.retiredKeys))
        XCTAssertEqual(Set(SidebarColorTuning.allKeys).count, SidebarColorTuning.allKeys.count, "no duplicate keys")

        // The section's Reset, through its coordinator's action.
        let d = suite("reset")
        let coordinator = FocusedDialKitCoordinator<SidebarColorsDialPanel>(defaults: d, onChange: {})
        for key in SidebarColorTuning.allKeys { d.set(key.hasSuffix("pacity") ? 0.4 : "#123456", forKey: key) }
        d.set(12.0, forKey: SidebarDialTuning.rowHeightKey)
        coordinator.handleAction("reset")
        for key in SidebarColorTuning.allKeys { XCTAssertNil(d.object(forKey: key), key) }
        XCTAssertEqual(d.double(forKey: SidebarDialTuning.rowHeightKey), 12, "its Reset leaves other panels alone")
        XCTAssertEqual(coordinator.state.values, SidebarColorsDialPanel.read(suite("reset-empty")), "the panel shows the shipped values again")

        // "Reset all panels" (the Glass & Layout panel's action).
        let all = suite("reset-all")
        let glass = SidebarDialKitCoordinator(defaults: all, onChange: {})
        for key in SidebarColorTuning.allKeys { all.set(key.hasSuffix("pacity") ? 0.4 : "#123456", forKey: key) }
        glass.handleAction("resetSidebar")
        for key in SidebarColorTuning.allKeys { XCTAssertNil(all.object(forKey: key), key) }
    }

    /// The inspector's route: a remote colour edit, addressed by the panel
    /// id and control path from the published snapshot, persists the key,
    /// and the contrast row follows it.
    func testRemoteColorEditPersistsAndUpdatesTheReadout() throws {
        let d = suite("remote")
        let coordinator = FocusedDialKitCoordinator<SidebarColorsDialPanel>(defaults: d, onChange: {})
        let panel = try XCTUnwrap(DialStore.shared.remoteSnapshot(appName: "t").panels.first { $0.id == coordinator.state.id })
        XCTAssertEqual(panel.name, "Sidebar colors")
        func find(_ controls: [DialKitControlSnapshot], _ path: String) -> DialKitControlSnapshot? {
            for control in controls {
                if control.path.hasSuffix(path) { return control }
                if case let .group(_, children) = control.kind, let hit = find(children, path) { return hit }
            }
            return nil
        }
        let control = try XCTUnwrap(find(panel.controls, "lightSecondaryText"))
        let before = coordinator.state.values.light.contrastSecondary
        XCTAssertTrue(DialStore.shared.setRemoteControlValue(panelID: coordinator.state.id, path: control.path, value: .string("#F0E9E6")))
        XCTAssertEqual(d.string(forKey: SidebarColorTuning.hexKey(.secondaryText, .light)), "#F0E9E6")
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertNotEqual(coordinator.state.values.light.contrastSecondary, before)
        XCTAssertTrue(coordinator.state.values.light.contrastSecondary.hasPrefix("1.00:1"), coordinator.state.values.light.contrastSecondary)
        // The readout is never persisted.
        XCTAssertEqual(SidebarColorTuning.allKeys.filter { d.object(forKey: $0) != nil }, [SidebarColorTuning.hexKey(.secondaryText, .light)])
    }

    // MARK: Contrast

    func testContrastRatioMatchesWCAG() {
        let black = SidebarColorTuning.RGBA(r: 0, g: 0, b: 0)
        let white = SidebarColorTuning.RGBA(r: 1, g: 1, b: 1)
        XCTAssertEqual(SidebarColorTuning.contrastRatio(black, on: white), 21, accuracy: 1e-9)
        XCTAssertEqual(SidebarColorTuning.contrastRatio(white, on: black), 21, accuracy: 1e-9)
        XCTAssertEqual(SidebarColorTuning.contrastRatio(white, on: white), 1, accuracy: 1e-9)
        // #777777 on white: the classic 4.48:1 near-miss.
        let grey = SidebarColorTuning.RGBA(hex: "#777777")!
        XCTAssertEqual(SidebarColorTuning.contrastRatio(grey, on: white), 4.48, accuracy: 0.01)
        // A translucent foreground is composited first, in gamma sRGB:
        // 50% black on white is 0.5 per channel (linear 0.21404), so
        // 1.05 / 0.26404 = 3.9766. (The 8-bit #808080 would give 3.95.)
        XCTAssertEqual(SidebarColorTuning.contrastRatio(SidebarColorTuning.RGBA(r: 0, g: 0, b: 0, a: 0.5), on: white), 3.9766, accuracy: 0.001)
    }

    /// The ratios at the shipped colours (the panel's readout untouched).
    /// Since beta.26 ("Option 2") secondary text clears 4.5:1 on the chrome
    /// and on the group card (a white lift) in both appearances, and an
    /// empty project draws in the secondary token.
    func testShippedContrastRatios() {
        let d = suite("ratios")
        func pairs(_ scheme: ColorScheme) -> SidebarColorTuning.ContrastPairs {
            // The panel rebuilds every colour from its dials: 8-bit hex and
            // opacity at two decimals (dark chrome 0.14 is #242424, not
            // 0.14: 10.94:1 on the tile, not 10.99). Quantize the same way.
            func q(_ c: SidebarColorTuning.RGBA) -> SidebarColorTuning.RGBA {
                SidebarColorTuning.RGBA(hex: c.hex, a: (c.a * 100).rounded() / 100)!
            }
            let card = scheme == .dark
                ? SidebarDialTuning.railColumnTintOpacity(defaults: d)
                : RailProjectColumn.lightColumnLiftOpacity
            return SidebarColorTuning.contrastPairs(
                background: q(SidebarColorTuning.base(.background, scheme)),
                primary: q(SidebarColorTuning.base(.primaryText, scheme)),
                secondary: q(SidebarColorTuning.base(.secondaryText, scheme)),
                tileFill: q(SidebarColorTuning.base(.tileFill, scheme)),
                tileInk: q(SidebarColorTuning.base(.tileInk, scheme)),
                dimmed: q(SidebarColorTuning.baseDimmed(scheme)),
                cardTint: SidebarColorTuning.RGBA(r: 1, g: 1, b: 1, a: card)
            )
        }
        for scheme in Self.schemes {
            let p = pairs(scheme)
            print(String(format: "CONTRAST %@ primary %.2f secondary %.2f secondaryOnCard %.2f tile %.2f selectedTile %.2f dimmed %.2f",
                         scheme == .dark ? "dark" : "light", p.primary, p.secondary, p.secondaryOnCard, p.tile, p.selectedTile, p.dimmed))
            XCTAssertGreaterThan(p.primary, 7)
            XCTAssertGreaterThan(p.secondary, 4.5)
            XCTAssertGreaterThan(p.tile, 7)
            XCTAssertGreaterThan(p.selectedTile, 7)
            XCTAssertGreaterThan(p.secondaryOnCard, 4.5)
            XCTAssertEqual(p.dimmed, p.secondary, accuracy: 1e-9, "an empty project draws in the secondary token")
        }
        // The panel shows the same numbers.
        let model = SidebarColorsDialPanel.read(d)
        XCTAssertEqual(model.light.contrastSecondary, SidebarColorTuning.readout(pairs(.light).secondary))
        XCTAssertEqual(model.dark.contrastTile, SidebarColorTuning.readout(pairs(.dark).tile))
    }

    // MARK: Pixels

    /// Each dial reaches the pixels it names, in the real one-view sidebar;
    /// the panel's Reset renders pixel-identical to an empty store.
    func testEachDialReachesThePixelsAndResetRestoresThem() throws {
        let wild: [(String, Any)] = [
            (SidebarColorTuning.hexKey(.background, .light), "#00FF00"),
            (SidebarColorTuning.hexKey(.primaryText, .light), "#FF00FF"),
            (SidebarColorTuning.opacityKey(.primaryText, .light), 1.0),
            (SidebarColorTuning.hexKey(.secondaryText, .light), "#0000FF"),
            (SidebarColorTuning.hexKey(.tileFill, .light), "#FF0000"),
            (SidebarColorTuning.opacityKey(.tileFill, .light), 1.0),
            (SidebarColorTuning.hexKey(.tileInk, .light), "#00FFFF"),
            (SidebarColorTuning.hexKey(.selectedRowTint, .light), "#FFFF00"),
            (SidebarColorTuning.opacityKey(.selectedRowTint, .light), 1.0),
            // The empty project's ink ships opaque (the secondary token).
            (SidebarColorTuning.dimmedOpacityKey(.light), 0.3),
        ]
        try withDials {
            let empty = try render(.light)
            XCTAssertEqual(differingPixels(empty, try render(.light)), 0, "the harness is deterministic")
            for (key, value) in wild {
                SidebarDialTuning.store.set(value, forKey: key)
                let tuned = try render(.light)
                XCTAssertGreaterThan(differingPixels(empty, tuned), 4, "\(key) changed no pixels")
                SidebarDialTuning.reset(keys: SidebarColorTuning.allKeys)
            }
            for (key, value) in wild { SidebarDialTuning.store.set(value, forKey: key) }
            XCTAssertGreaterThan(differingPixels(empty, try render(.light)), 1000)
            SidebarDialTuning.reset(keys: SidebarColorsDialPanel.resetKeys)
            XCTAssertEqual(differingPixels(empty, try render(.light)), 0, "Reset left a pixel changed")
        }
        // Dark: its own set; a light dial changes nothing there.
        try withDials {
            let empty = try render(.dark)
            SidebarDialTuning.store.set("#FF00FF", forKey: SidebarColorTuning.hexKey(.secondaryText, .light))
            XCTAssertEqual(differingPixels(empty, try render(.dark)), 0, "a light dial reached dark")
            SidebarDialTuning.store.set("#FF00FF", forKey: SidebarColorTuning.hexKey(.secondaryText, .dark))
            XCTAssertGreaterThan(differingPixels(empty, try render(.dark)), 4)
        }
    }

    // MARK: - Harness

    /// The one-view sidebar: a selected project with two live sessions (its
    /// tile filled with ink, the first row's chip selected) and an empty,
    /// dimmed project.
    private func render(_ scheme: ColorScheme) throws -> NSBitmapImageRep {
        let project = Project(name: "atlas-api", rootPath: "~/Code/atlas-api")
        let empty = Project(name: "zeta-web", rootPath: "~/Code/zeta-web")
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
        let store = WorkspaceStore(
            testingProjects: [project, empty], testingSessions: live,
            hasShownPinMigrationNotice: true, hasDismissedPinMigrationNotice: true
        )
        for s in live {
            store.updateIndicatorState(id: s.id, state: .idle)
            store.updateSessionStatus(id: s.id, status: .running)
        }
        let coordinator = SessionCoordinator()
        coordinator.setActiveSessionIdForTesting(live[0].id)

        let width: CGFloat = 260, height: CGFloat = 480
        let root = VStack(spacing: 0) {
            Color.clear.frame(height: store.toolbarRowTopAnchorConstant * 2)
            RecentsListView()
        }
        .frame(width: width, height: height)
        .environment(\.sidebarTrailingGutter, 0)
        .environmentObject(store)
        .environmentObject(coordinator)
        .environmentObject(SidebarWidthModel(width: width))
        // What `WorkspaceViewContainer` paints behind the sidebar.
        .background(Color(nsColor: SidebarColors.background(scheme)))
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
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

    private func differingPixels(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Int {
        guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return Int.max }
        var count = 0
        for y in 0..<a.pixelsHigh {
            for x in 0..<a.pixelsWide {
                guard let ca = a.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      let cb = b.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let d = abs(ca.redComponent - cb.redComponent) + abs(ca.greenComponent - cb.greenComponent)
                    + abs(ca.blueComponent - cb.blueComponent)
                if d > 0.02 { count += 1 }
            }
        }
        return count
    }
}
#endif

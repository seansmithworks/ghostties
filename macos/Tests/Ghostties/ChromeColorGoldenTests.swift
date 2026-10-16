import AppKit
import SwiftUI
import Testing
@testable import Ghostty

/// GATE for the chrome-token consolidation (appearance-themes plan, slice 1).
/// Freezes every resolved chrome colour and shadow value the Ghostties theme
/// renders today, in light and dark. A refactor that moves the tokens into
/// one `ChromeTheme` must leave every number below untouched.
///
/// Each colour is resolved the way the app draws it: dynamic colours under
/// `NSAppearance(named: .aqua / .darkAqua).performAsCurrentDrawingAppearance`,
/// converted to sRGB, rounded to 3 decimals as [r, g, b, a].
///
/// Accessors the refactor must keep, or update here in the same commit (the
/// goldens never change):
/// - Kept as-is: `SidebarColors.*`, `CanvasStyle.*`, `SidebarColorTuning.base`
///   (DEBUG), `TrayGlassStyle.{glassTint, surfaceFill, rimColor, iconColor,
///   chromaticColors, light, dark, opaqueDarkEdgeColor}`,
///   `SidebarDialTuning.trayGlass(for:state:defaults:)`,
///   `RailProjectColumn.{columnFill, tintInk}`, `RailCountBadge.style`.
/// - Planned for deletion or rename (slice 1 deletes the WorkspaceLayout
///   colour statics, so each reader below must be repointed to the new
///   accessor; the golden stays): `WorkspaceLayout.{textSecondaryLight/Dark,
///   sectionHeaderForeground, sessionGroupHeaderForeground,
///   emptyProjectForeground, hoverBarFill, expandedContainerLight/Dark,
///   activeRowLight/Dark, composerRowSelectedLight/Dark,
///   composerChipBackground(Active), canvasShadowColorLight/Dark,
///   canvasShadowRadius/Offset/Opacity}`. The raw `chromeBackground*`,
///   `canvasBackground*` and `borderDark` statics are covered through their
///   readers (`SidebarColors.background`, `CanvasStyle.background`,
///   `hoverBarFill`, `rimColor` / `surfaceFill` at opacity 1), so deleting
///   them needs no test edit.
/// - Theme-invariant brand and status colours stay on `WorkspaceLayout`.
///
/// Not frozen (private to their views): `HistoryBrowserView.Style`,
/// `OrphanTriageCardView.cardBackground`, `SessionPopoverCard` hairline and
/// shadows. They read the statics above; their literals are for the
/// slice's lint test.
@MainActor
struct ChromeColorGoldenTests {
    typealias Values = [Double]

    // MARK: - Resolution

    private static func round3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }

    private static func appearance(_ scheme: ColorScheme) -> NSAppearance {
        NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!
    }

    private static func rgba(_ ns: NSColor, _ scheme: ColorScheme) -> Values {
        var out: Values = []
        appearance(scheme).performAsCurrentDrawingAppearance {
            let c = ns.usingColorSpace(.sRGB) ?? ns
            out = [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { round3(Double($0)) }
        }
        return out
    }

    private static func rgba(_ color: Color, _ scheme: ColorScheme) -> Values { rgba(NSColor(color), scheme) }

    private static func rgba(_ cg: CGColor, _ scheme: ColorScheme) -> Values {
        rgba(NSColor(cgColor: cg) ?? .clear, scheme)
    }

    private static func fresh(_ tag: String) -> UserDefaults {
        let name = "com.seansmithdesign.ghostties.tests.chrome-golden.\(tag)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    // MARK: - Inventory

    /// Every colour, resolved per appearance. Names are the golden keys.
    private static func colorEntries() -> [(name: String, value: (ColorScheme) -> Values)] {
        let d = fresh("colors")
        var e: [(String, (ColorScheme) -> Values)] = []
        func add(_ name: String, _ value: @escaping (ColorScheme) -> Values) { e.append((name, value)) }

        // Chrome and canvas layers.
        add("chrome.background") { rgba(SidebarColors.background($0, defaults: d), $0) }
        add("chrome.hoverBarFill") { rgba(ChromeTheme.ghostties($0).chrome, $0) }
        add("canvas.background") { rgba(CanvasStyle.background($0, defaults: d), $0) }
        add("canvas.shadowColor") { rgba(CanvasStyle.shadowColor($0, defaults: d), $0) }
        add("canvas.hoverBarShadowColor") { rgba(WorkspaceLayout.hoverBarShadowColor, $0) }

        // Text.
        add("text.primary") { rgba(SidebarColors.primaryText($0, defaults: d), $0) }
        add("text.secondary") { rgba(SidebarColors.secondaryText($0, defaults: d), $0) }
        add("text.secondary.token") { rgba(ChromeTheme.ghostties($0).inkSecondaryColor, $0) }
        add("text.sectionHeader") { rgba(ChromeTheme.ghostties($0).inkSecondaryColor, $0) }
        add("text.sessionGroupHeader") { rgba(ChromeTheme.ghostties($0).inkSecondaryColor, $0) }
        add("text.emptyProject") { rgba(WorkspaceLayout.emptyProjectForeground, $0) }
        add("text.dimmedProject") { rgba(SidebarColors.dimmedProject($0, defaults: d), $0) }
        add("text.activityNormal") { rgba(WorkspaceLayout.activityNormalForeground, $0) }
        add("text.activityMuted") { rgba(WorkspaceLayout.activityMutedForeground, $0) }
        add("text.trayIcon") { rgba(TrayGlassStyle.iconColor(for: $0), $0) }

        // Tiles, chips, rows, cards.
        add("tile.fill") { rgba(SidebarColors.tileFill($0, defaults: d), $0) }
        add("tile.fillEmpty") { rgba(SidebarColors.tileFill($0, isEmpty: true, defaults: d), $0) }
        add("tile.ink") { rgba(SidebarColors.tileInk($0, defaults: d), $0) }
        add("tile.selectedRowTint") { rgba(SidebarColors.selectedRowTint($0, defaults: d), $0) }
        add("tile.tintInk") { rgba(RailProjectColumn.tintInk($0), $0) }
        add("tile.badgeText") { rgba(RailProjectTile.badgeText($0), $0) }
        add("tile.countBadge.fill") { rgba(RailCountBadge.style(selected: false, colorScheme: $0).fill, $0) }
        add("tile.countBadge.text") { rgba(RailCountBadge.style(selected: false, colorScheme: $0).text, $0) }
        add("column.fill") { rgba(RailProjectColumn.columnFill($0), $0) }
        add("column.fillDarkAtDefaultTint") { rgba(Color.white.opacity(RailProjectColumn.defaultColumnTintOpacity), $0) }
        add("column.lightLift") { rgba(Color.white.opacity(RailProjectColumn.lightColumnLiftOpacity), $0) }
        add("column.selectedChip") { rgba(RailProjectColumn.tintInk($0).opacity(RailProjectColumn.selectedChipTintOpacity), $0) }
        add("column.hoverChip") { rgba(RailProjectColumn.tintInk($0).opacity(RailProjectColumn.hoverChipTintOpacity), $0) }
        add("row.expandedContainer") { rgba(ChromeTheme.ghostties($0).lifted(.container), $0) }
        add("row.active") { rgba(ChromeTheme.ghostties($0).ink(.row), $0) }
        add("row.composerSelected") { rgba(ChromeTheme.ghostties($0).ink(.composerRow), $0) }
        add("composer.chip") { rgba(WorkspaceLayout.composerChipBackground, $0) }
        add("composer.chipActive") { rgba(WorkspaceLayout.composerChipBackgroundActive, $0) }

        // Tray glass: the real looks, then each layer at opacity 1 so the
        // base colour (chrome, border, white) is frozen apart from its alpha.
        for scheme in ["light", "dark"] {
            let look = scheme == "dark" ? TrayGlassStyle.dark : TrayGlassStyle.light
            var solid = look
            solid.tintOpacity = 1; solid.surfaceOpacity = 1; solid.rimOpacity = 1
            // Both appearances are read for each look, so a mis-keyed branch fails.
            add("tray.\(scheme).glassTint") { s in TrayGlassStyle.glassTint(look, for: s).map { rgba($0, s) } ?? [] }
            add("tray.\(scheme).surfaceFill") { rgba(TrayGlassStyle.surfaceFill(look, for: $0), $0) }
            add("tray.\(scheme).rim") { rgba(TrayGlassStyle.rimColor(look, for: $0), $0) }
            add("tray.\(scheme).glassTint@1") { s in TrayGlassStyle.glassTint(solid, for: s).map { rgba($0, s) } ?? [] }
            add("tray.\(scheme).surfaceFill@1") { rgba(TrayGlassStyle.surfaceFill(solid, for: $0), $0) }
            add("tray.\(scheme).rim@1") { rgba(TrayGlassStyle.rimColor(solid, for: $0), $0) }
        }
        add("tray.opaqueDarkEdge") { rgba(TrayGlassStyle.opaqueDarkEdgeColor, $0) }
        for palette in TrayGlassStyle.ChromaticPalette.allCases {
            add("tray.chromatic.\(palette.rawValue)") { s in
                TrayGlassStyle.chromaticColors(palette, for: s).flatMap { rgba($0, s) }
            }
        }

        // Theme-invariant brand and status colours.
        add("brand.terracotta") { rgba(WorkspaceLayout.waitingTerracotta, $0) }
        add("brand.terracottaNS") { rgba(WorkspaceLayout.waitingTerracottaNS, $0) }
        add("status.yourTurnBlue") { rgba(WorkspaceLayout.statusYourTurnBlue, $0) }
        add("status.yourTurnBlueNS") { rgba(WorkspaceLayout.statusYourTurnBlueNS, $0) }
        add("status.needsDecisionGold") { rgba(WorkspaceLayout.statusNeedsDecisionGold, $0) }
        add("status.needsDecisionGoldNS") { rgba(WorkspaceLayout.statusNeedsDecisionGoldNS, $0) }
        add("status.longRunningOrange") { rgba(WorkspaceLayout.statusLongRunningOrange, $0) }
        add("status.longRunningOrangeNS") { rgba(WorkspaceLayout.statusLongRunningOrangeNS, $0) }
        add("status.needsAttentionPurple") { rgba(WorkspaceLayout.needsAttentionPurple, $0) }
        add("composer.selectionAccent") { rgba(WorkspaceLayout.composerSelectionAccent, $0) }
        add("source.shell") { rgba(WorkspaceLayout.sourceDotShell, $0) }
        add("source.linear") { rgba(WorkspaceLayout.sourceDotLinear, $0) }
        add("source.github") { rgba(WorkspaceLayout.sourceDotGitHub, $0) }
        add("source.sentry") { rgba(WorkspaceLayout.sourceDotSentry, $0) }
        add("source.unknown") { rgba(WorkspaceLayout.sourceDotUnknown, $0) }
        add("status.ciFail") { rgba(WorkspaceLayout.ciFailColor, $0) }

        #if DEBUG
        // What each DialKit dial shows unset (DEBUG-only readers).
        for role in SidebarColors.Role.allCases {
            add("dialkit.sidebar.\(role.rawValue)") { s in
                let c = SidebarColorTuning.base(role, s)
                return [c.r, c.g, c.b, c.a].map { round3($0) }
            }
        }
        add("dialkit.sidebar.dimmed") { s in
            let c = SidebarColorTuning.baseDimmed(s)
            return [c.r, c.g, c.b, c.a].map { round3($0) }
        }
        #endif
        return e.map { (name: $0.0, value: $0.1) }
    }

    /// Shadow and opacity numbers, per appearance where they differ.
    private static func scalarEntries() -> [(name: String, value: (ColorScheme) -> Values)] {
        let d = fresh("scalars")
        var e: [(String, (ColorScheme) -> Values)] = []
        func add(_ name: String, _ value: @escaping (ColorScheme) -> Values) { e.append((name, value)) }

        add("canvas.shadow") {
            let o = CanvasStyle.shadowOffset($0, defaults: d)
            return [CanvasStyle.shadowOpacity($0, defaults: d), Double(CanvasStyle.shadowRadius($0, defaults: d)),
                    Double(o.width), Double(o.height)].map(round3)
        }
        add("canvas.shadow.token") { _ in
            [WorkspaceLayout.canvasShadowOpacity, Double(WorkspaceLayout.canvasShadowRadius),
             Double(WorkspaceLayout.canvasShadowOffset.width), Double(WorkspaceLayout.canvasShadowOffset.height)].map(round3)
        }
        add("hoverBar.shadow") { _ in
            [Double(WorkspaceLayout.hoverBarShadowOpacity), Double(WorkspaceLayout.hoverBarShadowRadius)].map(round3)
        }
        add("railReveal.shadow") { _ in
            [Double(WorkspaceLayout.railRevealShadowOpacity), Double(WorkspaceLayout.railRevealShadowRadius)].map(round3)
        }
        add("composerModal.shadow") { _ in
            [WorkspaceLayout.composerModalShadowOpacity, Double(WorkspaceLayout.composerModalShadowRadius),
             Double(WorkspaceLayout.composerModalShadowYOffset)].map(round3)
        }
        for state in SidebarDialTuning.TrayShadowState.allCases {
            add("tray.shadow.\(state.rawValue)") { s in
                let l = SidebarDialTuning.trayGlass(for: s, state: state, defaults: d)
                return [l.shadowOpacity, Double(l.shadowRadius), Double(l.shadowYOffset)].map(round3)
            }
        }
        add("tray.look") { s in
            let l = TrayGlassStyle.defaultLook(for: s)
            return [l.tintOpacity, l.surfaceOpacity, Double(l.rimWidth), l.rimOpacity, l.shadowOpacity,
                    Double(l.shadowRadius), Double(l.shadowYOffset)].map(round3)
        }
        add("tray.opaqueDarkEdgeWidth") { _ in [Double(TrayGlassStyle.opaqueDarkEdgeWidth)] }
        add("tile.opacities") { _ in
            [RailProjectTile.tintOpacity, RailProjectTile.emptyTintOpacity, RailProjectColumn.lightColumnLiftOpacity,
             RailProjectColumn.defaultColumnTintOpacity, RailProjectColumn.selectedChipTintOpacity,
             RailProjectColumn.hoverChipTintOpacity].map(round3)
        }
        return e.map { (name: $0.0, value: $0.1) }
    }

    private static func key(_ name: String, _ scheme: ColorScheme) -> String {
        "\(name)|\(scheme == .dark ? "dark" : "light")"
    }

    private static func literal(_ v: Values) -> String { "[" + v.map { String($0) }.joined(separator: ", ") + "]" }

    // MARK: - Tests

    @Test func everyChromeColorMatchesItsGolden() {
        let entries = Self.colorEntries()
        for scheme in [ColorScheme.light, .dark] {
            for entry in entries {
                let k = Self.key(entry.name, scheme)
                let actual = entry.value(scheme)
                #expect(Self.colorGoldens[k] == actual,
                        "\(k): golden \(Self.colorGoldens[k].map(Self.literal) ?? "MISSING"), got \(Self.literal(actual))")
            }
        }
    }

    @Test func everyShadowAndOpacityMatchesItsGolden() {
        let entries = Self.scalarEntries()
        for scheme in [ColorScheme.light, .dark] {
            for entry in entries {
                let k = Self.key(entry.name, scheme)
                let actual = entry.value(scheme)
                #expect(Self.scalarGoldens[k] == actual,
                        "\(k): golden \(Self.scalarGoldens[k].map(Self.literal) ?? "MISSING"), got \(Self.literal(actual))")
            }
        }
    }

    /// A golden with no live entry means an accessor was dropped from the
    /// inventory: the gate would silently stop covering it.
    @Test func noGoldenIsOrphaned() {
        let colorKeys = Set(Self.colorEntries().flatMap { e in [ColorScheme.light, .dark].map { Self.key(e.name, $0) } })
        let scalarKeys = Set(Self.scalarEntries().flatMap { e in [ColorScheme.light, .dark].map { Self.key(e.name, $0) } })
        #expect(Set(Self.colorGoldens.keys) == colorKeys)
        #expect(Set(Self.scalarGoldens.keys) == scalarKeys)
    }

    // MARK: - Goldens (captured from the code at the head of PR #244)

    private static let colorGoldens: [String: Values] = [
        "brand.terracottaNS|dark": [0.788, 0.451, 0.314, 1.0],
        "brand.terracottaNS|light": [0.788, 0.451, 0.314, 1.0],
        "brand.terracotta|dark": [0.788, 0.451, 0.314, 1.0],
        "brand.terracotta|light": [0.788, 0.451, 0.314, 1.0],
        "canvas.background|dark": [0.078, 0.078, 0.075, 1.0],
        "canvas.background|light": [0.98, 0.969, 0.953, 1.0],
        "canvas.hoverBarShadowColor|dark": [0.0, 0.0, 0.0, 1.0],
        "canvas.hoverBarShadowColor|light": [0.0, 0.0, 0.0, 1.0],
        "canvas.shadowColor|dark": [1.0, 1.0, 1.0, 1.0],
        "canvas.shadowColor|light": [0.059, 0.059, 0.059, 1.0],
        "chrome.background|dark": [0.14, 0.14, 0.14, 1.0],
        "chrome.background|light": [0.941, 0.914, 0.902, 1.0],
        "chrome.hoverBarFill|dark": [0.14, 0.14, 0.14, 1.0],
        "chrome.hoverBarFill|light": [0.941, 0.914, 0.902, 1.0],
        "column.fillDarkAtDefaultTint|dark": [1.0, 1.0, 1.0, 0.04],
        "column.fillDarkAtDefaultTint|light": [1.0, 1.0, 1.0, 0.04],
        "column.fill|dark": [1.0, 1.0, 1.0, 0.04],
        "column.fill|light": [1.0, 1.0, 1.0, 0.45],
        "column.hoverChip|dark": [1.0, 1.0, 1.0, 0.04],
        "column.hoverChip|light": [0.0, 0.0, 0.0, 0.04],
        "column.lightLift|dark": [1.0, 1.0, 1.0, 0.45],
        "column.lightLift|light": [1.0, 1.0, 1.0, 0.45],
        "column.selectedChip|dark": [1.0, 1.0, 1.0, 0.1],
        "column.selectedChip|light": [0.0, 0.0, 0.0, 0.1],
        "composer.chipActive|dark": [1.0, 1.0, 1.0, 0.137],
        "composer.chipActive|light": [0.0, 0.0, 0.0, 0.125],
        "composer.chip|dark": [1.0, 1.0, 1.0, 0.082],
        "composer.chip|light": [0.0, 0.0, 0.0, 0.075],
        "composer.selectionAccent|dark": [0.357, 0.553, 0.937, 1.0],
        "composer.selectionAccent|light": [0.357, 0.553, 0.937, 1.0],
        "dialkit.sidebar.background|dark": [0.14, 0.14, 0.14, 1.0],
        "dialkit.sidebar.background|light": [0.941, 0.914, 0.902, 1.0],
        "dialkit.sidebar.dimmed|dark": [0.651, 0.651, 0.651, 1.0],
        "dialkit.sidebar.dimmed|light": [0.369, 0.369, 0.369, 1.0],
        "dialkit.sidebar.primaryText|dark": [1.0, 1.0, 1.0, 0.847],
        "dialkit.sidebar.primaryText|light": [0.0, 0.0, 0.0, 0.847],
        "dialkit.sidebar.secondaryText|dark": [0.651, 0.651, 0.651, 1.0],
        "dialkit.sidebar.secondaryText|light": [0.369, 0.369, 0.369, 1.0],
        "dialkit.sidebar.selectedRowTint|dark": [1.0, 1.0, 1.0, 0.1],
        "dialkit.sidebar.selectedRowTint|light": [0.0, 0.0, 0.0, 0.1],
        "dialkit.sidebar.tileFill|dark": [1.0, 1.0, 1.0, 0.07],
        "dialkit.sidebar.tileFill|light": [0.157, 0.133, 0.118, 0.1],
        "dialkit.sidebar.tileInk|dark": [0.941, 0.937, 0.929, 1.0],
        "dialkit.sidebar.tileInk|light": [0.137, 0.129, 0.125, 1.0],
        "row.active|dark": [1.0, 1.0, 1.0, 0.06],
        "row.active|light": [0.0, 0.0, 0.0, 0.04],
        "row.composerSelected|dark": [1.0, 1.0, 1.0, 0.1],
        "row.composerSelected|light": [0.0, 0.0, 0.0, 0.06],
        "row.expandedContainer|dark": [0.16, 0.16, 0.16, 1.0],
        "row.expandedContainer|light": [1.0, 1.0, 1.0, 1.0],
        "source.github|dark": [0.541, 0.541, 0.561, 1.0],
        "source.github|light": [0.541, 0.541, 0.561, 1.0],
        "source.linear|dark": [0.431, 0.416, 0.682, 1.0],
        "source.linear|light": [0.431, 0.416, 0.682, 1.0],
        "source.sentry|dark": [0.604, 0.431, 0.557, 1.0],
        "source.sentry|light": [0.604, 0.431, 0.557, 1.0],
        "source.shell|dark": [0.541, 0.663, 0.416, 1.0],
        "source.shell|light": [0.541, 0.663, 0.416, 1.0],
        "source.unknown|dark": [1.0, 1.0, 1.0, 0.247],
        "source.unknown|light": [0.0, 0.0, 0.0, 0.259],
        "status.ciFail|dark": [1.0, 0.259, 0.271, 0.7],
        "status.ciFail|light": [1.0, 0.22, 0.235, 0.7],
        "status.longRunningOrangeNS|dark": [0.976, 0.451, 0.086, 1.0],
        "status.longRunningOrangeNS|light": [0.976, 0.451, 0.086, 1.0],
        "status.longRunningOrange|dark": [0.976, 0.451, 0.086, 1.0],
        "status.longRunningOrange|light": [0.976, 0.451, 0.086, 1.0],
        "status.needsAttentionPurple|dark": [0.659, 0.333, 0.969, 1.0],
        "status.needsAttentionPurple|light": [0.659, 0.333, 0.969, 1.0],
        "status.needsDecisionGoldNS|dark": [1.0, 0.769, 0.0, 1.0],
        "status.needsDecisionGoldNS|light": [1.0, 0.769, 0.0, 1.0],
        "status.needsDecisionGold|dark": [1.0, 0.769, 0.0, 1.0],
        "status.needsDecisionGold|light": [1.0, 0.769, 0.0, 1.0],
        "status.yourTurnBlueNS|dark": [0.357, 0.553, 0.937, 1.0],
        "status.yourTurnBlueNS|light": [0.357, 0.553, 0.937, 1.0],
        "status.yourTurnBlue|dark": [0.357, 0.553, 0.937, 1.0],
        "status.yourTurnBlue|light": [0.357, 0.553, 0.937, 1.0],
        "text.activityMuted|dark": [1.0, 1.0, 1.0, 0.247],
        "text.activityMuted|light": [0.0, 0.0, 0.0, 0.259],
        "text.activityNormal|dark": [1.0, 1.0, 1.0, 0.847],
        "text.activityNormal|light": [0.0, 0.0, 0.0, 0.847],
        "text.dimmedProject|dark": [0.651, 0.651, 0.651, 1.0],
        "text.dimmedProject|light": [0.369, 0.369, 0.369, 1.0],
        "text.emptyProject|dark": [0.651, 0.651, 0.651, 1.0],
        "text.emptyProject|light": [0.369, 0.369, 0.369, 1.0],
        "text.primary|dark": [1.0, 1.0, 1.0, 0.847],
        "text.primary|light": [0.0, 0.0, 0.0, 0.847],
        "text.secondary.token|dark": [0.651, 0.651, 0.651, 1.0],
        "text.secondary.token|light": [0.369, 0.369, 0.369, 1.0],
        "text.secondary|dark": [0.651, 0.651, 0.651, 1.0],
        "text.secondary|light": [0.369, 0.369, 0.369, 1.0],
        "text.sectionHeader|dark": [0.651, 0.651, 0.651, 1.0],
        "text.sectionHeader|light": [0.369, 0.369, 0.369, 1.0],
        "text.sessionGroupHeader|dark": [0.651, 0.651, 0.651, 1.0],
        "text.sessionGroupHeader|light": [0.369, 0.369, 0.369, 1.0],
        "text.trayIcon|dark": [0.651, 0.651, 0.651, 1.0],
        "text.trayIcon|light": [0.369, 0.369, 0.369, 1.0],
        "tile.badgeText|dark": [0.14, 0.14, 0.14, 1.0],
        "tile.badgeText|light": [0.941, 0.914, 0.902, 1.0],
        "tile.countBadge.fill|dark": [0.323, 0.32, 0.319, 1.0],
        "tile.countBadge.fill|light": [0.731, 0.709, 0.699, 1.0],
        "tile.countBadge.text|dark": [0.651, 0.651, 0.651, 1.0],
        "tile.countBadge.text|light": [0.369, 0.369, 0.369, 1.0],
        "tile.fillEmpty|dark": [1.0, 1.0, 1.0, 0.07],
        "tile.fillEmpty|light": [0.157, 0.133, 0.118, 0.085],
        "tile.fill|dark": [1.0, 1.0, 1.0, 0.07],
        "tile.fill|light": [0.157, 0.133, 0.118, 0.1],
        "tile.ink|dark": [0.941, 0.937, 0.929, 1.0],
        "tile.ink|light": [0.137, 0.129, 0.125, 1.0],
        "tile.selectedRowTint|dark": [1.0, 1.0, 1.0, 0.1],
        "tile.selectedRowTint|light": [0.0, 0.0, 0.0, 0.1],
        "tile.tintInk|dark": [1.0, 1.0, 1.0, 1.0],
        "tile.tintInk|light": [0.0, 0.0, 0.0, 1.0],
        "tray.chromatic.chrome|dark": [0.651, 0.651, 0.651, 1.0, 0.14, 0.14, 0.14, 1.0, 0.078, 0.078, 0.075, 1.0, 0.14, 0.14, 0.14, 1.0, 0.651, 0.651, 0.651, 1.0],
        "tray.chromatic.chrome|light": [0.369, 0.369, 0.369, 1.0, 0.941, 0.914, 0.902, 1.0, 0.98, 0.969, 0.953, 1.0, 0.941, 0.914, 0.902, 1.0, 0.369, 0.369, 0.369, 1.0],
        "tray.chromatic.ember|dark": [0.788, 0.451, 0.314, 1.0, 0.14, 0.14, 0.14, 1.0, 0.078, 0.078, 0.075, 1.0, 0.14, 0.14, 0.14, 1.0, 0.788, 0.451, 0.314, 1.0],
        "tray.chromatic.ember|light": [0.788, 0.451, 0.314, 1.0, 0.941, 0.914, 0.902, 1.0, 0.98, 0.969, 0.953, 1.0, 0.941, 0.914, 0.902, 1.0, 0.788, 0.451, 0.314, 1.0],
        "tray.chromatic.mono|dark": [0.651, 0.651, 0.651, 1.0, 0.651, 0.651, 0.651, 1.0],
        "tray.chromatic.mono|light": [0.369, 0.369, 0.369, 1.0, 0.369, 0.369, 0.369, 1.0],
        "tray.chromatic.pastel|dark": [0.62, 0.86, 1.0, 1.0, 0.8, 0.74, 1.0, 1.0, 1.0, 0.78, 0.9, 1.0, 1.0, 0.95, 0.7, 1.0, 0.74, 1.0, 0.86, 1.0, 0.62, 0.86, 1.0, 1.0],
        "tray.chromatic.pastel|light": [0.62, 0.86, 1.0, 1.0, 0.8, 0.74, 1.0, 1.0, 1.0, 0.78, 0.9, 1.0, 1.0, 0.95, 0.7, 1.0, 0.74, 1.0, 0.86, 1.0, 0.62, 0.86, 1.0, 1.0],
        "tray.chromatic.rainbow|dark": [1.0, 0.259, 0.271, 1.0, 1.0, 0.573, 0.188, 1.0, 1.0, 0.839, 0.0, 1.0, 0.188, 0.82, 0.345, 1.0, 0.235, 0.827, 0.996, 1.0, 0.0, 0.569, 1.0, 1.0, 0.859, 0.204, 0.949, 1.0, 1.0, 0.259, 0.271, 1.0],
        "tray.chromatic.rainbow|light": [1.0, 0.22, 0.235, 1.0, 1.0, 0.553, 0.157, 1.0, 1.0, 0.8, 0.0, 1.0, 0.204, 0.78, 0.349, 1.0, 0.0, 0.753, 0.91, 1.0, 0.0, 0.533, 1.0, 1.0, 0.796, 0.188, 0.878, 1.0, 1.0, 0.22, 0.235, 1.0],
        "tray.chromatic.signal|dark": [0.357, 0.553, 0.937, 1.0, 0.14, 0.14, 0.14, 1.0, 1.0, 0.769, 0.0, 1.0, 0.14, 0.14, 0.14, 1.0, 0.976, 0.451, 0.086, 1.0, 0.14, 0.14, 0.14, 1.0, 0.357, 0.553, 0.937, 1.0],
        "tray.chromatic.signal|light": [0.357, 0.553, 0.937, 1.0, 1.0, 0.769, 0.0, 1.0, 0.976, 0.451, 0.086, 1.0, 0.357, 0.553, 0.937, 1.0],
        "tray.dark.glassTint@1|dark": [0.14, 0.14, 0.14, 1.0],
        "tray.dark.glassTint@1|light": [1.0, 1.0, 1.0, 1.0],
        "tray.dark.glassTint|dark": [0.14, 0.14, 0.14, 0.35],
        "tray.dark.glassTint|light": [1.0, 1.0, 1.0, 0.35],
        "tray.dark.rim@1|dark": [0.165, 0.165, 0.165, 1.0],
        "tray.dark.rim@1|light": [1.0, 1.0, 1.0, 1.0],
        "tray.dark.rim|dark": [0.165, 0.165, 0.165, 0.6],
        "tray.dark.rim|light": [1.0, 1.0, 1.0, 0.6],
        "tray.dark.surfaceFill@1|dark": [0.14, 0.14, 0.14, 1.0],
        "tray.dark.surfaceFill@1|light": [1.0, 1.0, 1.0, 1.0],
        "tray.dark.surfaceFill|dark": [0.14, 0.14, 0.14, 0.6],
        "tray.dark.surfaceFill|light": [1.0, 1.0, 1.0, 0.6],
        "tray.light.glassTint@1|dark": [0.14, 0.14, 0.14, 1.0],
        "tray.light.glassTint@1|light": [1.0, 1.0, 1.0, 1.0],
        "tray.light.glassTint|dark": [0.14, 0.14, 0.14, 0.35],
        "tray.light.glassTint|light": [1.0, 1.0, 1.0, 0.35],
        "tray.light.rim@1|dark": [0.165, 0.165, 0.165, 1.0],
        "tray.light.rim@1|light": [1.0, 1.0, 1.0, 1.0],
        "tray.light.rim|dark": [0.165, 0.165, 0.165, 0.6],
        "tray.light.rim|light": [1.0, 1.0, 1.0, 0.6],
        "tray.light.surfaceFill@1|dark": [0.14, 0.14, 0.14, 1.0],
        "tray.light.surfaceFill@1|light": [1.0, 1.0, 1.0, 1.0],
        "tray.light.surfaceFill|dark": [0.14, 0.14, 0.14, 0.6],
        "tray.light.surfaceFill|light": [1.0, 1.0, 1.0, 0.6],
        "tray.opaqueDarkEdge|dark": [0.18, 0.18, 0.18, 1.0],
        "tray.opaqueDarkEdge|light": [0.18, 0.18, 0.18, 1.0]
    ]
    private static let scalarGoldens: [String: Values] = [
        "canvas.shadow.token|dark": [0.06, 16.0, 0.0, -2.0],
        "canvas.shadow.token|light": [0.06, 16.0, 0.0, -2.0],
        "canvas.shadow|dark": [0.06, 16.0, 0.0, -2.0],
        "canvas.shadow|light": [0.06, 16.0, 0.0, -2.0],
        "composerModal.shadow|dark": [0.3, 24.0, 8.0],
        "composerModal.shadow|light": [0.3, 24.0, 8.0],
        "hoverBar.shadow|dark": [0.127, 16.0],
        "hoverBar.shadow|light": [0.127, 16.0],
        "railReveal.shadow|dark": [0.2, 12.0],
        "railReveal.shadow|light": [0.2, 12.0],
        "tile.opacities|dark": [0.1, 0.085, 0.45, 0.04, 0.1, 0.04],
        "tile.opacities|light": [0.1, 0.085, 0.45, 0.04, 0.1, 0.04],
        "tray.look|dark": [0.35, 0.6, 1.0, 0.6, 0.4, 12.0, 4.0],
        "tray.look|light": [0.35, 0.6, 1.0, 0.6, 0.12, 8.0, 4.0],
        "tray.opaqueDarkEdgeWidth|dark": [1.0],
        "tray.opaqueDarkEdgeWidth|light": [1.0],
        "tray.shadow.hoverBar|dark": [0.4, 12.0, 4.0],
        "tray.shadow.hoverBar|light": [0.12, 8.0, 4.0],
        "tray.shadow.rail|dark": [0.4, 12.0, 4.0],
        "tray.shadow.rail|light": [0.12, 8.0, 4.0],
        "tray.shadow.sidebar|dark": [0.4, 12.0, 4.0],
        "tray.shadow.sidebar|light": [0.12, 8.0, 4.0]
    ]
}

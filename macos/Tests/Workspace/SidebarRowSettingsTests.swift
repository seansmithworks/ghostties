import XCTest
import SwiftUI
import GhosttiesCore
@testable import Ghostty

/// Settings > Appearance > Sidebar: the Icons and Text settings mapped to
/// the row's layout (`SidebarRowIcons`, `SidebarRowText`), the defaults
/// equal to the look before the settings existed, and the rail unchanged
/// under every setting.
@MainActor
final class SidebarRowSettingsTests: PrivateDefaultsTestCase {
    private let kinds: [SessionStatusGlyphKind] = [.working, .needsInput, .done, .error, .stopped]

    // MARK: - Defaults are today's look

    func testUnsetSettingsAreLargeAndStandard() {
        XCTAssertEqual(SidebarRowIcons.current(defaults: defaults), .large)
        XCTAssertEqual(SidebarRowText.current(defaults: defaults), SidebarRowText.standard)
    }

    func testUnsetIconsDrawTodaysTiles() {
        XCTAssertEqual(RailProjectTile.size(.sidebar), 32)
        XCTAssertEqual(RailProjectTile.textSize(.sidebar, letters: 1), 13)
        XCTAssertEqual(RailProjectColumn.chipSize(.sidebar), 32)
        XCTAssertEqual(RailProjectColumn.chipGlyphSize(.sidebar), 16)
        let dials = SidebarMorphMetrics.Dials.current(defaults: defaults)
        XCTAssertEqual(dials.sidebarTileSize, 32)
        XCTAssertEqual(dials.sidebarChipSize, 32)
        XCTAssertEqual(dials.sidebarGlyphSize, 16)
        XCTAssertEqual(dials.sidebarTileText, 13)
        XCTAssertEqual(dials.sidebarLabelSpacing, WorkspaceLayout.sidebarIconLabelSpacing)
    }

    func testUnsetTextKeepsTheNeedsYouRule() {
        for kind in kinds {
            XCTAssertEqual(SessionRowSecondLine.isShown(kind), kind == .needsInput || kind == .error, "\(kind)")
        }
    }

    // MARK: - Icons → tile sizes

    func testEachIconsSettingsTiles() {
        XCTAssertEqual(SidebarRowIcons.large.sidebarTiles(dials: defaults),
                       SidebarTileSizes(projectTile: 32, projectText: 13, threadTile: 32, threadIcon: 16))
        XCTAssertEqual(SidebarRowIcons.small.sidebarTiles(dials: defaults),
                       SidebarTileSizes(projectTile: 24, projectText: 11, threadTile: 24, threadIcon: 12))
        XCTAssertEqual(SidebarRowIcons.none.sidebarTiles(dials: defaults),
                       SidebarTileSizes(projectTile: 0, projectText: 0, threadTile: 0, threadIcon: 0))
    }

    /// Every view's resolver reads the stored setting: the header tile, the
    /// row slot, the chip and the glyph move together.
    func testTheStoredIconsSettingReachesEveryResolver() {
        for (icons, tile, chip, glyph) in [(SidebarRowIcons.small, 24.0, 24.0, 12.0), (.none, 0, 0, 0), (.large, 32, 32, 16)] {
            defaults.set(icons.rawValue, forKey: SidebarRowIcons.key)
            XCTAssertEqual(RailProjectTile.size(.sidebar), tile, "\(icons)")
            XCTAssertEqual(SidebarListRowChrome<EmptyView, EmptyView>.glyphSlotWidth, tile, "\(icons)")
            XCTAssertEqual(RailProjectColumn.chipSize(.sidebar), chip, "\(icons)")
            XCTAssertEqual(RailProjectColumn.chipGlyphSize(.sidebar), glyph, "\(icons)")
            let dials = SidebarMorphMetrics.Dials.current(defaults: defaults)
            XCTAssertEqual(dials.sidebarTileSize, tile, "\(icons)")
            XCTAssertEqual(dials.sidebarChipSize, chip, "\(icons)")
            XCTAssertEqual(dials.sidebarGlyphSize, glyph, "\(icons)")
        }
    }

    /// None drops the slot, so the labels start one small inset in from the
    /// row's leading edge; Small keeps the gap.
    func testNoneStartsTheLabelsNearTheLeadingEdge() {
        XCTAssertEqual(SidebarMorphMetrics.Dials.current(defaults: defaults, icons: .none).sidebarLabelSpacing, 8)
        XCTAssertEqual(SidebarMorphMetrics.Dials.current(defaults: defaults, icons: .small).sidebarLabelSpacing,
                       WorkspaceLayout.sidebarIconLabelSpacing)
    }

    /// Large is the "Tiles" dials, so DialKit still tunes today's look;
    /// Small and None are fixed.
    func testLargeFollowsTheDialsAndSmallDoesNot() {
        defaults.set(36.0, forKey: SidebarDialTuning.sidebarProjectTileSizeKey)
        defaults.set(36.0, forKey: SidebarDialTuning.sidebarThreadTileSizeKey)
        XCTAssertEqual(SidebarRowIcons.large.sidebarTiles(dials: defaults).projectTile, 36)
        XCTAssertEqual(SidebarRowIcons.large.sidebarTiles(dials: defaults).threadTile, 36)
        XCTAssertEqual(SidebarRowIcons.small.sidebarTiles(dials: defaults).projectTile, 24)
        XCTAssertEqual(SidebarRowIcons.none.sidebarTiles(dials: defaults).projectTile, 0)
    }

    /// The rail is icon-only: its tiles, chips and glyphs are the rail
    /// dials under every setting.
    func testTheRailKeepsItsTilesUnderEverySetting() {
        let large = SidebarMorphMetrics.Dials.current(defaults: defaults, icons: .large)
        for icons in SidebarRowIcons.allCases {
            let dials = SidebarMorphMetrics.Dials.current(defaults: defaults, icons: icons)
            XCTAssertEqual(dials.railTileSize, large.railTileSize, "\(icons)")
            XCTAssertEqual(dials.railChipSize, large.railChipSize, "\(icons)")
            XCTAssertEqual(dials.railGlyphSize, large.railGlyphSize, "\(icons)")
            XCTAssertEqual(dials.railTileText, large.railTileText, "\(icons)")
            XCTAssertGreaterThan(dials.railTileSize, 0, "\(icons)")
        }
    }

    /// With no tile the group card keeps its top where Large puts it, round
    /// the header's name, instead of dropping to the header's midline.
    func testNoneKeepsTheGroupCardsTop() {
        func cardTop(_ icons: SidebarRowIcons) -> CGFloat {
            let dials = SidebarMorphMetrics.Dials.current(defaults: defaults, icons: icons)
            let card = SidebarMorphMetrics(dials: dials, expandedWidth: 260, railWidth: 60, progress: 0).sidebarCard(hasRows: true)
            return card.tileTrim - card.topInset
        }
        XCTAssertEqual(cardTop(.none), cardTop(.large))
    }

    // MARK: - Text → second line

    func testStandardShowsTheSecondLineOnlyWhenTheThreadNeedsTheUser() {
        for kind in kinds {
            XCTAssertEqual(SessionRowSecondLine.isShown(kind, text: SidebarRowText.standard), kind == .needsInput || kind == .error, "\(kind)")
        }
    }

    func testDetailedShowsTheSecondLineOnEveryRow() {
        for kind in kinds {
            XCTAssertTrue(SessionRowSecondLine.isShown(kind, text: .detailed), "\(kind)")
        }
    }

    func testTheStoredTextSettingReachesTheRule() {
        defaults.set(SidebarRowText.detailed.rawValue, forKey: SidebarRowText.key)
        XCTAssertTrue(SessionRowSecondLine.isShown(.working))
        XCTAssertTrue(SessionRowSecondLine.isShown(.done))
        defaults.set(SidebarRowText.standard.rawValue, forKey: SidebarRowText.key)
        XCTAssertFalse(SessionRowSecondLine.isShown(.working))
    }

    /// A Detailed row is two lines tall, as a needs-you row already is.
    func testADetailedRowTakesTheTwoLineHeight() {
        XCTAssertEqual(
            SidebarListRowHeight.band(hasSubtitle: SessionRowSecondLine.isShown(.working, text: .detailed)),
            SidebarDialTuning.rowHeight()
        )
        XCTAssertEqual(
            SidebarListRowHeight.band(hasSubtitle: SessionRowSecondLine.isShown(.working, text: SidebarRowText.standard)),
            SidebarListRowHeight.oneLineBand
        )
    }
}

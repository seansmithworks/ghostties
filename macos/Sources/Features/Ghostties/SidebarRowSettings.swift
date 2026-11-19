import Foundation

// Settings > Appearance > Sidebar (beta.28): two independent settings for how
// much a sidebar row shows. Both live in `AppDefaults.store`; every row and
// header reads them through the resolvers below, so one code path covers all
// six combinations.

/// The expanded sidebar's tiles: the project tile heading a group and the
/// thread tile (chip and status glyph) in each row under it. The rail keeps
/// its own tiles under every setting: it is icon-only, so it always shows
/// them.
enum SidebarRowIcons: String, CaseIterable {
    /// No tiles: the names and titles take the tiles' room.
    case none
    case small
    /// Today's look: the sidebar's "Tiles" dials.
    case large

    static let key = "ghostties.sidebar.rowIcons"

    var title: String {
        switch self {
        case .none: "None"
        case .small: "Small"
        case .large: "Large"
        }
    }

    /// The stored setting; a capture's `GHOSTTIES_CAPTURE_SIDEBAR_ICONS`
    /// wins (DEBUG).
    static func current(defaults: UserDefaults = AppDefaults.store) -> SidebarRowIcons {
        #if DEBUG
        if let captured = CaptureFixture.sidebarIcons { return captured }
        #endif
        return defaults.string(forKey: key).flatMap(Self.init(rawValue:)) ?? .large
    }

    /// Small's tiles, on the 8pt grid: the Large tile's 32 down a step to
    /// 24, its 16pt glyph and 13pt monogram scaled with it.
    static let smallTiles = SidebarTileSizes(projectTile: 24, projectText: 11, threadTile: 24, threadIcon: 12)

    /// This setting's expanded-sidebar tiles. Large reads the "Tiles" dials
    /// from `dials`, so DialKit keeps tuning today's look.
    func sidebarTiles(dials: UserDefaults = SidebarDialTuning.store) -> SidebarTileSizes {
        switch self {
        case .none:
            SidebarTileSizes(projectTile: 0, projectText: 0, threadTile: 0, threadIcon: 0)
        case .small:
            Self.smallTiles
        case .large:
            SidebarTileSizes(
                projectTile: SidebarDialTuning.sidebarProjectTileSize(defaults: dials),
                projectText: SidebarDialTuning.sidebarProjectTileText(defaults: dials),
                threadTile: SidebarDialTuning.sidebarThreadTileSize(defaults: dials),
                threadIcon: SidebarDialTuning.sidebarThreadTileIcon(defaults: dials)
            )
        }
    }
}

/// The expanded sidebar's tile sizes under one `SidebarRowIcons` setting.
struct SidebarTileSizes: Equatable {
    /// The project tile's side, and the leading slot every row's glyph
    /// centres in under it.
    var projectTile: CGFloat
    /// The monogram's font size (one letter; two draw 2pt smaller).
    var projectText: CGFloat
    /// A row's chip side.
    var threadTile: CGFloat
    /// A row's status glyph side.
    var threadIcon: CGFloat

    /// The gap from a `tile`-wide slot to the labels. With no slot it is
    /// the labels' inset from the row's leading edge, the same for headers
    /// and rows so their text lines up, and clear of the selected row's
    /// outline (which the text touched at 0).
    static func labelSpacing(tile: CGFloat) -> CGFloat { tile > 0 ? WorkspaceLayout.sidebarIconLabelSpacing : noTileLabelInset }
    static let noTileLabelInset: CGFloat = 8

    /// The side the group card's top is measured from (`tileTrim`): the
    /// tile, or with no tile the Large tile, so the card sits round the
    /// header's name where it always has.
    static func cardAnchor(tile: CGFloat) -> CGFloat { tile > 0 ? tile : RailProjectTile.defaultSize }
}

/// Whether one-view rows draw their second line for every status or only
/// when the thread needs the user (`SessionRowSecondLine`).
enum SidebarRowText: String, CaseIterable {
    /// Today's rule: the second line only for needs-you and error.
    case standard
    /// The second line on every row that has one.
    case detailed

    static let key = "ghostties.sidebar.rowText"

    var title: String {
        switch self {
        case .standard: "Standard"
        case .detailed: "Detailed"
        }
    }

    /// The stored setting; a capture's `GHOSTTIES_CAPTURE_SIDEBAR_TEXT`
    /// wins (DEBUG).
    static func current(defaults: UserDefaults = AppDefaults.store) -> SidebarRowText {
        #if DEBUG
        if let captured = CaptureFixture.sidebarText { return captured }
        #endif
        return defaults.string(forKey: key).flatMap(Self.init(rawValue:)) ?? .standard
    }
}

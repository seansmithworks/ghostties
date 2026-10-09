import SwiftUI

// MARK: - Expanded tiles (exploration, `explore/expanded-tiles`)
//
// Strawmen for bringing the rail's project monogram tile into the expanded
// one-view list, so the two sidebar states read as one surface. Every
// variant reuses the rail's own pieces (`RailProjectTile`, `RailGroupColumn`,
// `SessionStatusGlyph`, the chip's `SidebarRowCardBackground`), so geometry
// matches by construction rather than by look-alike. Exploration only.

/// How the expanded one-view list carries the rail's tiles (the
/// "Expanded tiles" dial).
///
/// - `current`: text headers, status glyph trailing (what ships).
/// - `gutter` (A): a leading gutter the rail's width. Tiles and glyphs sit
///   at their exact rail x/y, with the rail's column and chip; collapsing
///   crops to the gutter.
/// - `header` (B): the tile prefixed to the header label; rows unchanged.
/// - `card` (C): tree layout at the list's own inset (tile in the header,
///   glyphs leading under it), and the selected project's group as one
///   tinted card the full row width: the rail column, widened.
enum ExpandedTileStyle: String, CaseIterable {
    case current
    case gutter
    case header
    case card

    static let shipped: ExpandedTileStyle = .current

    /// Rows draw their status glyph in a leading slot, under the tile.
    var hasLeadingGlyph: Bool { self == .gutter || self == .card }
}

/// Where the leading tile/glyph slot sits, per variant, in the list's
/// content coordinates (the list column's leading edge is the window margin
/// plus "Content padding leading"; the rail's is the window margin alone).
enum ExpandedTileGeometry {
    /// The tile's centre, from the list content's leading edge.
    static func tileCenterX(_ style: ExpandedTileStyle, railWidth: CGFloat) -> CGFloat {
        switch style {
        case .gutter:
            // The rail centres its tile in its content column
            // (`SidebarRailView.columnPadding`, symmetric window margins),
            // i.e. at railWidth / 2 from the sidebar's leading edge.
            return railWidth / 2 - SidebarDialTuning.windowMargin() - SidebarDialTuning.contentPaddingLeading()
        default:
            // The list's own text inset: the tile's leading edge where a
            // row title starts today.
            return SidebarDialTuning.rowLeadingPadding() + RailProjectTile.size / 2
        }
    }

    /// The column's half width: the tile plus the column inset.
    static var holderWidth: CGFloat { RailProjectTile.size + RailProjectColumn.columnInset * 2 }

    /// The leading slot's width: content edge through the column's trailing edge.
    static func slotWidth(_ style: ExpandedTileStyle, railWidth: CGFloat) -> CGFloat {
        tileCenterX(style, railWidth: railWidth) + holderWidth / 2
    }

    /// Column edge to label.
    static let labelGap: CGFloat = WorkspaceLayout.sidebarIconLabelSpacing
}

/// The leading slot: `content` centred in a column-wide holder, the holder
/// pushed out so its centre lands on `tileCenterX`. The holder carries the
/// rail column's anchor, so `RailGroupColumn` draws the same column here.
struct ExpandedTileSlot<Content: View>: View {
    let style: ExpandedTileStyle
    let height: CGFloat
    let isInSelectedColumn: Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.sidebarRailWidth) private var railWidth

    var body: some View {
        content()
            .frame(width: ExpandedTileGeometry.holderWidth, height: height)
            .railGroupColumn(style == .gutter && isInSelectedColumn)
            .frame(width: ExpandedTileGeometry.slotWidth(style, railWidth: railWidth), alignment: .trailing)
    }
}

// MARK: Header

/// A one-view project header for the tile variants. B keeps the text header
/// and prefixes the tile; A and C put the tile in the leading slot.
struct ExpandedTileHeader: View {
    let style: ExpandedTileStyle
    let name: String
    let monogram: String
    let count: Int
    let isCollapsed: Bool
    let isEmpty: Bool
    let isSelectedProject: Bool
    let onToggle: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0

    var body: some View {
        let ink = isEmpty ? WorkspaceLayout.emptyProjectForeground : WorkspaceLayout.sectionHeaderForeground(for: colorScheme)
        HStack(spacing: 0) {
            switch style {
            case .header:
                tile
                    .frame(width: RailProjectTile.size)
                    .padding(.leading, SidebarDialTuning.rowLeadingPadding())
                    .padding(.trailing, ExpandedTileGeometry.labelGap)
            default:
                ExpandedTileSlot(style: style, height: ProjectAccordionHeader.height, isInSelectedColumn: isSelectedProject) {
                    tile
                }
                .padding(.trailing, ExpandedTileGeometry.labelGap)
            }
            Button(action: onToggle) {
                HStack(spacing: 0) {
                    Text(name.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                        .frame(width: 14)
                        .padding(.leading, 4)
                        .opacity(isEmpty ? 0 : 1)
                    Spacer(minLength: 8)
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                }
                .foregroundStyle(ink)
                .frame(height: ProjectAccordionHeader.height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, SidebarDialTuning.rowTrailingPadding())
        }
        .frame(height: ProjectAccordionHeader.height)
        .modifier(ExpandedGroupCardAnchor(isOn: style == .card && isSelectedProject))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(count) \(count == 1 ? "session" : "sessions")")
        .accessibilityValue(isEmpty ? "" : (isCollapsed ? "collapsed" : "expanded"))
        .accessibilityAddTraits([.isHeader, .isButton])
        .accessibilityHint(ProjectAccordionHeader.accessibilityHint(isEmpty: isEmpty, isCollapsed: isCollapsed))
    }

    private var tile: some View {
        RailProjectTile(
            name: name,
            monogram: monogram,
            count: count,
            // The header already says the count; the tile's fold badge is
            // the rail's stand-in for it.
            isCollapsed: false,
            isEmpty: isEmpty,
            isSelectedProject: isSelectedProject,
            onToggle: onToggle
        )
    }
}

// MARK: Row

/// A grouped session row for A and C: the status glyph in the leading slot
/// under its project's tile (the rail's glyph, at the rail's resting size),
/// title and subtitle beside it, nothing trailing. The selected row's glyph
/// sits on the rail's chip; A adds a softer card running right from the
/// column, C lets the group card carry it.
struct ExpandedTileRow<Title: View>: View {
    let style: ExpandedTileStyle
    let kind: SessionStatusGlyphKind
    let subtitle: String
    let isActive: Bool
    let isInSelectedGroup: Bool
    @ViewBuilder let title: () -> Title

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0

    var body: some View {
        let glyph = SidebarDialTuning.rowGhostSize()
        HStack(spacing: 0) {
            ExpandedTileSlot(style: style, height: SidebarDialTuning.rowHeight(), isInSelectedColumn: isInSelectedGroup) {
                SessionStatusGlyph(kind: kind, size: glyph)
                    .frame(width: glyph, height: glyph)
                    .background {
                        if isActive || isHovered {
                            SidebarRowCardBackground(isActive: isActive, isHovered: isHovered, cornerRadius: RailProjectColumn.chipCornerRadius)
                                .frame(width: RailProjectColumn.chipSize, height: RailProjectColumn.chipSize)
                        }
                    }
            }
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    title()
                    Text(subtitle)
                        .font(.system(size: SidebarDialTuning.rowSubtitleSize()))
                        .foregroundStyle(colorScheme == .dark ? WorkspaceLayout.textSecondaryDark : WorkspaceLayout.textSecondaryLight)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .padding(.leading, ExpandedTileGeometry.labelGap)
            .padding(.trailing, SidebarDialTuning.rowTrailingPadding())
            .frame(height: SidebarDialTuning.rowHeight())
            .background(alignment: .leading) {
                // A: the selected row's card, softer than the chip, runs
                // from the column's edge to the row's end. Collapsing crops
                // it away with the labels; the chip stays.
                if style == .gutter && isActive {
                    RoundedRectangle(cornerRadius: RailProjectColumn.chipCornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(RailProjectColumn.columnTintOpacity))
                        .frame(height: RailProjectColumn.chipSize)
                        .padding(.leading, 2)
                }
            }
        }
        .frame(height: SidebarDialTuning.rowHeight())
        .modifier(ExpandedGroupCardAnchor(isOn: style == .card && isInSelectedGroup))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

// MARK: C's group card

/// The bounds of every item in the selected project's group (C only).
struct ExpandedGroupCardKey: PreferenceKey {
    static var defaultValue: [Anchor<CGRect>] = []
    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value += nextValue()
    }
}

struct ExpandedGroupCardAnchor: ViewModifier {
    let isOn: Bool
    func body(content: Content) -> some View {
        if isOn {
            content.anchorPreference(key: ExpandedGroupCardKey.self, value: .bounds) { [$0] }
        } else {
            content
        }
    }
}

/// C: the rail column widened to the row width. Same tint, same inset and
/// corner as the column, hugging the tile's top and the last chip's bottom,
/// so collapsing is one shape narrowing to the column.
struct ExpandedGroupCard: View {
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
    let anchors: [Anchor<CGRect>]

    var body: some View {
        GeometryReader { proxy in
            if let first = anchors.first {
                let union = anchors.dropFirst().reduce(proxy[first]) { $0.union(proxy[$1]) }
                let inset = RailProjectColumn.columnInset
                let topTrim = (ProjectAccordionHeader.height - RailProjectTile.size) / 2
                let bottomTrim = anchors.count > 1
                    ? (SidebarDialTuning.rowHeight() - RailProjectColumn.chipSize) / 2
                    : topTrim
                let top = union.minY + topTrim - inset
                let bottom = union.maxY - bottomTrim + inset
                RoundedRectangle(cornerRadius: RailProjectColumn.chipCornerRadius + inset, style: .continuous)
                    .fill(Color.primary.opacity(RailProjectColumn.columnTintOpacity))
                    .frame(width: union.width, height: bottom - top)
                    .position(x: union.midX, y: (top + bottom) / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

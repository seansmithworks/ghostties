# Sidebar vnext: Option D spec (pulled from the canvas)

Source: pen.dev `Sidebar vnext – options 2026-10-08.pen`, frame `xgAzp`
"7 · OPTION D — Group card" inside `HmzBw` "Build 2026-10-08". Values were read
with the pencil MCP (`Get`), not eyeballed. Render: `~/.ghostties-evidence/vnext/option-d/pen-D.png`.

## Frames treated as the spec

- `E2ozb` (inside `xgAzp`): the expanded one-view sidebar. Sean edited its project
  rows, tiles, group card and tray.
- `ptiEO` (inside `xgAzp`): the rail. Its list `iXmN8` is disabled; the visible rail
  is `Nh7Pf` (98pt column, project column `p6osQ7`, vertical tray `emGcV`).
- Context only: `ZFlsM` (strawman C, used to find what Sean changed for D), `egWwj`
  (Sessions-tab layout; D has no Sessions-tab frame), `Ftfu0` ("Rail — PENDING
  BUILD", superseded by D's rail: its 82pt pills became 48pt).

## What changed C → D (Sean's edits)

Tile column moved in from 24pt to 12pt (group padding 4, tile slot 30, not 50).
Tile and chip radius 9 → 8. Tile tint 7.5% → 10%. Selected chip 7.5% → 10%. Group
card 4% → 6%, r13 → r12, now 2pt past the list on each side and 6pt above the
header and below the last row. Tray 60pt → 48pt: square 48pt buttons, pill radius
20 → 12, no inner padding except 2pt at the ends of the Create pill. WREN's group
and TROVE's tile radius were not edited and still carry C's values; the edited
majority is the spec.

## Element table

Coordinates are pt, relative to the sidebar's leading edge (window x) unless noted.
"Current code" is `feat/rail-column` @ `95f8d9ce9`.

| Element | D value (node) | Current code value | file:symbol |
| --- | --- | --- | --- |
| Expanded sidebar width | list x 8–256, canvas card at x 264 (`re3jN`, `C2tMoC`) | card at 244 + 8 = 252 | `WorkspaceLayout.swift:sidebarWidth` (244) |
| Window margin | 8 (list x, tray x, tray bottom, card inset) | 8 | `SidebarDialKit.swift:windowMargin` dial |
| List top | y 52 (traffic lights centred at y 26) | 2 × traffic-light centre + 0 | `WorkspaceSidebarView` titlebar inset, `contentPaddingTop` dial (0) |
| Group → group gap | 21 (`re3jN` gap) | rowGap 4 + spacer 13 + rowGap 4 = 21 | `SidebarProjectGroupItem.spacerHeight`, `rowGap` dial |
| Header → row, row → row | 4 (group gap) | 4 | `rowGap` dial |
| Row leading inset (tile / glyph column) | 4 (group padding `[0,4]`), tile at x 12 | 16, no tile in the expanded list | `rowLeadingPadding` dial |
| Row trailing inset | 16 label padding + 4 group padding = 20 | 16 | `rowTrailingPadding` dial |
| Project header height | 30 (`Mkjpt`) | 30 | `ProjectAccordionHeader.height` |
| Monogram tile (expanded header) | 30 × 30, leading, x 12 (`hRCBC`) | not drawn in the expanded list | `ProjectAccordionHeader` |
| Monogram tile size (rail) | 30 × 30, centred at x 49 (`P9lK6`) | 30, centred | `RailProjectTile.size` |
| Tile corner radius | 8 | 9 | `RailProjectTile` (literal 9) |
| Tile fill (light) | `#28221E1A` (10%) | `#28221E` at 7.5% | `RailProjectTile.tint` |
| Monogram text | Inter 13 bold (1 letter) / 11 bold (2), `#232120` → SF Pro 13/11 bold | 13/11 bold, `#232120` | `RailProjectTile` |
| Selected project tile | fill `#232120`, text `#F0E9E6` (`KKqkk`) | ink fill 1, chrome text | `railSelectedTileFill` dial (1) |
| Empty project tile/name/count | `#00000042` (`WZ2qJ`, `D2MLB`) | `tertiaryLabelColor` (same) | `WorkspaceLayout.emptyProjectForeground` |
| Tile → header label gap | 10 (`jiRxR` padding left) | 10 | `WorkspaceLayout.sidebarIconLabelSpacing` |
| Header name | 11 semibold, tracking 0.5, `#636363`, uppercase | same | `ProjectAccordionHeader` |
| Header chevron | lucide `chevron-down` 9pt in an 18pt frame, 4pt leading pad | SF `chevron.down` 8pt bold, 14pt frame, 4pt leading pad | `ProjectAccordionHeader` (unchanged C → D) |
| Header count | 11 medium `#636363`, trailing | same | `ProjectAccordionHeader` |
| Session row height | 48 | 48 | `rowHeight` dial |
| Status glyph slot | leading, 30 wide (the tile column), glyph centred under the tile | trailing, 20 wide | `RecentsRowView` / `SidebarListRowChrome` |
| Status glyph | 20 × 20 frame; `?` 16 semibold, `✓` 13 | 20 | `rowGhostSize` dial, `SessionStatusGlyph` |
| Glyph → title gap | 10 (`K3oST` padding left) | 10 | `sidebarIconLabelSpacing` |
| Row title | 14 regular `#000000D9` | 14 regular, `.primary` | `rowTitleSize` dial |
| Row subtitle | 11 regular `#636363`, 1pt below title | same | `rowSubtitleSize` dial |
| Selected row (grouped, expanded) | 30 × 30 chip behind the glyph, r8, `#0000001A`, no rim (`m6j5AS`) | full-row card, r8, primary 7.5% + chromatic rim | `SidebarRowCardBackground` |
| Selected group card (expanded) | list −2 / +2 horizontally, header top −6, last row bottom +6; r12; `#0000000F` (`T6FfX`) | not drawn | new (from `explore/expanded-tiles` C) |
| Rail project column | tile ±4 (38 wide), tile top −4, last row bottom +3; r12; `#0000000F` (`p6osQ7`) | tile ±8 (46 wide), last chip bottom +8; r 9 + 8 = 17; 4% | `railColumnInset` (8), `railChipCornerRadius` (9), `railColumnTintOpacity` (0.04) dials |
| Rail selected chip | 30 × 30, r8, `#0000001A`, no rim (`ZiGlb`) | r9, primary 7.5% + rim | `railChipCornerRadius` dial, `SidebarRowCardBackground` |
| Rail width | 98 (traffic lights x 19–79, + 19) | hug: zoom maxX + close minX + `railExtraWidth` (0) | `WorkspaceLayout.collapsedRailWidth` |
| Expanded tray frame | x 8–256, bottom 8, height 48 (`WhwIC`) | height 60 | `SidebarTray` |
| Create pill (expanded) | 2 buttons 48 × 48, padding `[0, 2]`, gap 0 → 100 × 48 (`ab279`) | buttons 44 × 44, padding 8, gap 2, stretches the bar | `trayHorizontalButtonSize` (44), `trayInnerPadding` (8) dials, `TrayGlassStyle.horizontalItemGap` (2) |
| Toggle pill (expanded) | 48 × 48, no padding (`zjWsW`) | 44 + 2 × 8 = 60 | same |
| Pill arrangement (expanded) | Create leading, Toggle trailing (`space_between`) | Create fills the bar, Toggle trailing | `trayWidth` dial (`fill`) |
| Pill corner radius | 12 (canvas window r20 − 8) | concentric: window 16 − 8 = 8 | `SidebarDialTuning.trayCornerRadius` |
| Pill fill | white 70% + white 15% | surface 0.7, tint 0.15 | `TrayGlassStyle.light` |
| Pill rim | 1.25 inner, white 25% | 1.25, 0.25 | `TrayGlassStyle.light` |
| Pill chromatic rim | angular, 30%, rotation 202.7 | 0.3, 202.7 | `TrayGlassStyle.light` |
| Pill shadow | 15%, blur 16, y 3 (blur 16 = SwiftUI radius 8, as the card's) | 0.20, radius 12, y 4 | light glass shadow dials (Rail panel) |
| Tray icons | 18, `#636363` | 18, `textSecondaryLight` | `trayHorizontalIconSize`, `trayVerticalIconSize` dials |
| Rail tray | pills 48 wide centred (x 25–73); Create 48 × 100 (padding `[2, 0]`); Toggle 48 × 48; gap 8; bottom 8 (`emGcV`) | pill = rail width − 16 (82); icon gap 12 | `RailTrayGeometry`, `railTrayIconGap` dial |
| Canvas card | r12, shadow 15% blur 16 y 2 | concentric r8; 0.15 / radius 8 / y 2 | `WorkspaceLayout.terminalCornerRadius`, `canvasShadow*` |

### Sessions tab (no D frame; built to match D)

Leading 30pt glyph slot at the same x as the one-view glyphs, project name as the
subtitle, the full-row card for the selected row (no group, so no chip). The rail's
Sessions tab is unchanged.

## DESIGN.md conflicts (D wins)

1. §3 Typography: "11pt density", "two weights maximum". D: 14pt row titles,
   13pt monograms; bold, semibold, medium and regular on one surface.
2. §5 Spacing: "valid values only 4, 8, 12, 16, 24, 32, 48, 64". D: 21 group
   gap (13 spacer), 10 label gap, 30 tiles, 20 trailing inset, 6 card outset, 2
   pill padding, y 3 shadow.
3. §7 Shapes: "One radius. One style." (12). D: tiles and chips 8, cards 12.
4. §5 Layout tokens: `sidebarWidth 220`. D: 256 (code was already 244).
5. §6 Depth: three shadow levels. D's tray pill shadow (15% / blur 16 / y 3) is a
   fourth.
6. §4 Row/hover: "Do not create new hover colors". D adds a 6% group card and a
   10% selected chip.

## Kept over D (behaviour rules from the brief)

- Pill and card corner radius stay concentric with the real window (16 − 8 = 8).
  D's 12 is concentric with the canvas's 20pt window; the rule is the same, the
  window is not.

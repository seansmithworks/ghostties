# App Rebuild Spec — Ghostties Sidebar (source-extracted)

Every value below is transcribed from Swift source with a `file:line` citation.
No literal is invented; where source lacks a value it's marked
**NOT FOUND — needs runtime measurement**.

Reference photos: `app-sessions.jpg` (Projects tab, expanded), `app-tasks.jpg`
(Projects tab, collapsed) — light mode, `projectFirst` mode (default,
`WorkspaceViewContainer.swift:90`). Neither shows the flat Sessions-tab list
(`RecentsListView`/`RecentsRowView`) — that's a View-menu toggle, not a
visible sidebar control (§2).

## 1. Window chrome

| Value | Source | Citation |
|---|---|---|
| Traffic lights (geometry/spacing/color) | Native `standardWindowButton` — not custom-drawn | `WorkspaceViewContainer.swift:770-771` (hide/show only); **NOT FOUND — needs runtime measurement** |
| Window corner radius | Native macOS chrome, not set in app code | **NOT FOUND — needs runtime measurement** (~10px in photos) |
| Titlebar spacer height | `titlebarSpacerHeight = 28` | `WorkspaceLayout.swift:35` |
| Sidebar material | `NSVisualEffectView`, `.material = .sidebar`, `.blendingMode = .behindWindow`, `.state = .active` | `WorkspaceViewContainer.swift:58-64` |
| Chrome background (light/dark) | `#F0E9E6` / `#242424` | `WorkspaceLayout.swift:109, 112` |
| Canvas background (light/dark, terminal card) | `#FAF7F3` / `#2D2D2D` | `WorkspaceLayout.swift:119, 123` |
| Terminal card corner radius | `terminalCornerRadius = 12` | `WorkspaceLayout.swift:67` |
| Terminal card inset (pinned mode) | `terminalInset = 8` (all 4 sides) | `WorkspaceLayout.swift:83` |
| Card shadow | `black.opacity(0.15)`, radius `8`, offset `(0, -2)` | `WorkspaceLayout.swift:70-79` |

## 2. Sidebar frame

| Value | Source | Citation |
|---|---|---|
| Sidebar width (projectFirst, default) | `sidebarWidth = 220`, via `.frame(width: model.width)` | `WorkspaceLayout.swift:19`; `WorkspaceViewContainer.swift:36` |
| Sidebar width (taskFirst) | `taskSidebarWidth = 280` | `WorkspaceLayout.swift:24` |
| Min / max drag width | `sidebarMinWidth: 180`, `sidebarMaxWidth: 480` | `WorkspaceLayout.swift:28, 32` |
| Row leading padding | `sidebarRowLeadingPadding = 8` | `WorkspaceLayout.swift:225` |
| Icon column width | `sidebarIconColumnWidth = 16` | `WorkspaceLayout.swift:216` |
| Icon-to-label gap | `sidebarIconLabelSpacing = 10` | `WorkspaceLayout.swift:220` |
| List padding (Projects tab) | horizontal 8, vertical 4 | `WorkspaceSidebarView.swift:82-83` |
| **Sessions/Projects tab switcher** | **No visible in-sidebar control.** `sidebarTab` = `@AppStorage` enum, toggled via View menu — not a segmented control. | `WorkspaceSidebarView.swift:7-10, 39, 46-93` |
| Titlebar toolbar row height | `toolbarRowTopAnchorConstant * 2` (dynamic, centers on traffic-light row) | `WorkspaceSidebarView.swift:175` |
| Toolbar row horizontal padding | 12pt | `WorkspaceSidebarView.swift:172` |
| Toolbar button icon/label | icon 10pt `.medium`; label 12pt `.medium` | `WorkspaceSidebarView.swift:514-517` |
| Toolbar button color | `.secondary`, `.primary` on hover | `WorkspaceSidebarView.swift:521` |

## 3. Sessions tab rows (`RecentsRowView` — flat list, no reference photo)

| Value | Source | Citation |
|---|---|---|
| Row height | 36pt | `RecentsRowView.swift:104` |
| Row padding | leading 8pt (`sidebarRowLeadingPadding`), trailing 10pt | `RecentsRowView.swift:102-103` |
| Element spacing | `sidebarIconLabelSpacing` (10pt) | `RecentsRowView.swift:51` |
| Ghost glyph size | `sessionGhostSize = 14`, centered in 16pt icon column | `WorkspaceLayout.swift:230`; `RecentsRowView.swift:55-56` |
| Ghost glyph tint | `dotColor` — see §6 status palette; **is** the status mark, no separate dot | `RecentsRowView.swift:119-129` |
| Name label (not editing) | 12pt regular, `Color.primary` | `RecentsRowView.swift:78-81` |
| Name label (editing) | `TextField`, 12pt regular, `.plain` | `RecentsRowView.swift:61-63` |
| Project-name subline | 10pt regular, `textSecondaryLight/Dark` | `RecentsRowView.swift:84-87` |
| Name/subline spacing | `VStack(spacing: 1)` | `RecentsRowView.swift:59` |
| Timestamp label | 10pt regular, secondary color, `.monospacedDigit()` | `RecentsRowView.swift:96-100` |
| Row bg — active | `activeRowLight`/`Dark` (see §6) | `RecentsRowView.swift:138-143` |
| Row bg — hover | `primary.opacity(0.05)` | `RecentsRowView.swift:144-145` |
| Row corner radius | 6pt | `RecentsRowView.swift:134` |

## 4. Projects tab rows (`ProjectDisclosureRow` + `SessionRow` — matches both reference photos)

### Project header row

| Value | Source | Citation |
|---|---|---|
| Row height | 32pt | `ProjectDisclosureRow.swift:348` |
| Padding | leading 8pt / trailing 12pt | `ProjectDisclosureRow.swift:346-347` |
| Element spacing | `sidebarIconLabelSpacing` (10pt) | `ProjectDisclosureRow.swift:305` |
| Ghost glyph size | 12×12pt, centered in 16pt icon column | `ProjectDisclosureRow.swift:323, 326` |
| Ghost glyph tint | `store.projectGhostColor(for:)` — aggregate of child-session status, §6 palette | `ProjectDisclosureRow.swift:321` |
| Project name | 13pt `.medium`, tracking `-0.13`, 1 line | `ProjectDisclosureRow.swift:328-331` |
| Hover background | `primary.opacity(0.06)`, 6pt radius | `ProjectDisclosureRow.swift:349-352` |
| "+" new-session button (expanded only) | 10pt `.medium` icon, 24×24pt hit target | `ProjectDisclosureRow.swift:335-340` |
| **No disclosure chevron** — whole row is the tap target | `ProjectDisclosureRow.swift:296-354` |
| Expanded container bg | `Color.white` / `Color(white:0.16)`, 8pt radius | `WorkspaceLayout.swift:95, 98`; `ProjectDisclosureRow.swift:390-395` |
| Header/session-list spacing | `VStack(spacing: 2)` | `ProjectDisclosureRow.swift:113` |

### Session child row (`SessionRow`, `SessionDetailView.swift`)

| Value | Source | Citation |
|---|---|---|
| Row height | 28pt | `SessionDetailView.swift:75` |
| Padding | horizontal 8pt; +20pt left indent under project | `SessionDetailView.swift:74`; `ProjectDisclosureRow.swift:176` |
| Element spacing | `HStack(spacing: 4)` | `SessionDetailView.swift:33` |
| Session name | 12pt: `.semibold` if `needsAttention`, `.medium` if `waiting`, else `.regular` | `SessionDetailView.swift:53` |
| Name color | `.primary`, except `.idle` (`secondaryLabelColor`), `.inactive` (`textSecondaryLight/Dark`) | `SessionDetailView.swift:168-176` |
| Ghost glyph size | 12×12pt, centered in 16×16pt frame | `SessionDetailView.swift:144-145` |
| Ghost glyph style | `.filled`, `.outline` (1pt stroke) when `.inactive` | `SessionDetailView.swift:142` |
| Row bg — active/hover | `activeRowLight/Dark` (§6) / `primary.opacity(0.04)` | `SessionDetailView.swift:178-185` |
| Row corner radius | 6pt | `SessionDetailView.swift:76-78` |
| Active-row shadow | `black.opacity(0.1)`, radius 2, y 1 | `SessionDetailView.swift:80-83` |

### Section headers

| Value | Source | Citation |
|---|---|---|
| Projects-tab group header (Pinned/Active Now/Recent/All Projects) | icon 9pt `.semibold` (`tertiaryLabelColor`) + label 10pt `.semibold`, tracking `0.6`, uppercase | `WorkspaceSidebarView.swift:436-445` |
| Header padding | leading 8, trailing 12, vertical 4 | `WorkspaceSidebarView.swift:449-451` |
| Sessions-tab bucket header (Active/Recent/Idle) | `PixelChevronView` 16×16pt + label 10pt `.semibold`, tracking `0.6` | `RecentsListView.swift:557-569` |
| Bucket header padding | leading 8, trailing 12, top 8, bottom 4 | `RecentsListView.swift:573-576` |

## 5. Type ramp

Web fallback for all rows below (suggestion only): `-apple-system, "SF Pro Text", "Inter", sans-serif`; terminal content: `"SF Mono", ui-monospace, monospace`.

| Surface | Font spec (source) | Citation |
|---|---|---|
| Sidebar UI general (design-system doc) | SF Pro Text, 11pt, `.regular`/`.medium` | `DESIGN.md:114-119` (root) |
| Project name (header row) | System font, 13pt `.medium`, tracking `-0.13` | `ProjectDisclosureRow.swift:329-330` |
| Session name (child row) | 12pt, `.regular`/`.medium`/`.semibold` by state | `SessionDetailView.swift:53` |
| Sessions-tab row name | 12pt `.regular` | `RecentsRowView.swift:79` |
| Sessions-tab project subline / timestamp | 10pt `.regular` | `RecentsRowView.swift:85, 97` |
| Section header labels | 10pt `.semibold`, tracking `0.6`, uppercase | `WorkspaceSidebarView.swift:443-444` |
| Toolbar button label | 12pt `.medium` | `WorkspaceSidebarView.swift:517` |
| Toolbar/section icon glyphs | SF Symbols, 8-10pt `.medium`/`.semibold` | `ProjectDisclosureRow.swift:337`, `WorkspaceSidebarView.swift:438, 515` |
| Terminal content | SF Mono, user-config size | `DESIGN.md:118` |

## 6. Color table

### Status palette (literal hex — the ghost glyph itself is tinted; no separate dot)

| State | Hex | Source |
|---|---|---|
| Needs decision (gold) | `#FFC400` | `WorkspaceLayout.swift:148` |
| Waiting / your turn (blue) | `#5B8DEF` | `WorkspaceLayout.swift:140` |
| Long-running (orange) | `#F97316` | `WorkspaceLayout.swift:156` |
| Processing | `Color(.systemGreen)` — semantic, ~`#28CD41` light / `#32D74B` dark | `RecentsRowView.swift:125` — verify vs. screenshots |
| Error | `Color(.systemRed)` — semantic, ~`#FF3B30` light / `#FF453A` dark | `RecentsRowView.swift:121` — verify vs. screenshots |
| Idle | `Color.primary.opacity(0.30)` | `RecentsRowView.swift:126` |
| Inactive | `Color.primary.opacity(0.12)` | `RecentsRowView.swift:127` |

### Background/text layers

| Role | Light | Dark | Source |
|---|---|---|---|
| Chrome background | `#F0E9E6` | `#242424` | `WorkspaceLayout.swift:109, 112` |
| Canvas background | `#FAF7F3` | `#2D2D2D` | `WorkspaceLayout.swift:119, 123` |
| Text primary | `Color.primary` (semantic; design-doc equiv. `#1a1a1a`) | `Color.primary` (design-doc equiv. `#f0efed`) | `DESIGN.md:9, 18` — semantic, verify vs. screenshots |
| Text secondary | `#636363` | `#9A9A9A` | `WorkspaceLayout.swift:186, 189` |
| Active row tint | `black.opacity(0.04)` | `white.opacity(0.06)` | `WorkspaceLayout.swift:101, 104` |
| Expanded container | `Color.white` | `Color(white:0.16)` ≈ `#292929` | `WorkspaceLayout.swift:95, 98` |
| Hover (Sessions row) | `primary.opacity(0.05)` | same | `RecentsRowView.swift:144-145` |
| Hover (Projects session row) | `primary.opacity(0.04)` | same | `SessionDetailView.swift:184-185` |
| Hover (project header row) | `primary.opacity(0.06)` | same | `ProjectDisclosureRow.swift:351` |
| Section-header icon / tertiary | `tertiaryLabelColor` — semantic, ~30% black/white | `WorkspaceSidebarView.swift:439` — verify vs. screenshots |

## 7. Gaps — visible in reference photos, not pinned to source

- **Traffic-light geometry/spacing/colors** — native AppKit chrome, never drawn/measured in app code.
- **Window corner radius** — native macOS chrome (~10px in both photos), no literal in source.
- **Titlebar height above the list** reads taller than the 28pt `titlebarSpacerHeight` token alone — likely includes the toolbar row (`toolbarRowTopAnchorConstant * 2`, dynamic, tied to live traffic-light position). No static px value in source.
- **Vertical rhythm** between "PINNED" header/first row, and between last expanded session/next project header in `app-sessions.jpg` — composed from multiple `.padding` calls (`WorkspaceSidebarView.swift:70`, `ProjectDisclosureRow.swift:113,121`), not verified pixel-for-pixel against the photo.
- **`app-tasks.jpg` name vs. content**: both photos show the **Projects tab** (collapsed/expanded), not the flat Sessions-tab list. No reference photo exists for the Sessions tab — §3 is source-only, unverified against a screenshot.
- **Terminal-pane content** (prompt styling, output color, top-right globe icon, top-left sidebar toggle) is GhosttyKit/terminal chrome, out of this sidebar spec's scope — not measured.
- **Semantic `Color.primary`/`NSColor` resolved hexes** — typical Apple system values noted above, flagged "verify vs. screenshots"; dynamic, not literal in source.

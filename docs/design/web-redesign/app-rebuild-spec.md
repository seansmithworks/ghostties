# App Rebuild Spec — Ghostties Sidebar (source-extracted)

Every value below is transcribed from Swift source with a `file:line` citation.
No literal is invented; where source lacks one it's marked **NOT FOUND — needs runtime measurement**.

## Framing: two different builds

`app-sessions.jpg`/`app-tasks.jpg` and the Swift source are **two different
builds**. **Source is authoritative for COLOR. Photos for GEOMETRY.** Known
divergences — build to the resolution given, not to whichever side "looks right":

| # | Divergence | Build value |
|---|---|---|
| a | Photos show deprecated terracotta waiting ghosts (`#BC7B51`/`#C97A59`) | Replaced — build waiting as `statusYourTurnBlue` `#5B8DEF` (`WorkspaceLayout.swift:140`; deprecation note `:127`) |
| b | Photo sidebar ≈232px (user drag-resized) | Fallback token is 220 (`:19`); **build at 232** to match the reference pair |
| c | Photo toolbar shows a bare "+" | Source renders icon+label buttons (§2) — build icon+label |
| d | Card face measures `#F7F7F7` in photo | That's `GhosttyKit`'s user-configurable theme color, not the `#FAF7F3` canvas token — build the canvas token; card face is out of scope |

Both photos show the **Projects tab, light mode**. No Sessions-tab or
dark-mode photo exists yet (Sean is capturing them) — see §8.

## 1. Window chrome

| Value | Source | Citation |
|---|---|---|
| Traffic lights | Native `standardWindowButton`, not custom-drawn | `WorkspaceViewContainer.swift:771`; **NOT FOUND — needs runtime measurement** |
| Window corner radius | Native macOS chrome, not set in app code | **NOT FOUND** (~10px in photos) |
| Titlebar spacer height (taskFirst only) | `titlebarSpacerHeight = 28` | `WorkspaceViewContainer.swift:689,693`; `WorkspaceLayout.swift:35` |
| Titlebar toolbar row height (projectFirst — both photos) | `toolbarRowTopAnchorConstant * 2`, dynamic. projectFirst does NOT use `titlebarSpacerHeight`; uses `.ignoresSafeArea(.container, edges: .top)` | `WorkspaceSidebarView.swift:175`; `WorkspaceViewContainer.swift:666-674,717-721` |
| Measured (projectFirst, cross-check only) | Traffic-light centerline y≈27; toolbar row ≈54px; first header top y≈58 | runtime, not source |
| Sidebar material | `NSVisualEffectView`, `.sidebar`, `.behindWindow`, `.active` | `WorkspaceViewContainer.swift:58-64` |
| Chrome bg (light/dark) | `#F0E9E6` / `#242424` | `WorkspaceLayout.swift:109,112` |
| Canvas bg (light/dark) | `#FAF7F3` / `#2E2E2E` (`white:0.18`, generic-gray colorspace, approximate) | `WorkspaceLayout.swift:119,123` |
| Terminal card radius / inset / shadow | radius 12; inset 8 all sides; `black.opacity(0.15)` radius 8 offset `(0,-2)` | `WorkspaceLayout.swift:67,83,70-79` |

## 2. Sidebar frame

| Value | Source | Citation |
|---|---|---|
| Sidebar width — **build at 232** (Framing b) | Persisted per-mode, clamped 180–480; `220` is only cold-start fallback | `WorkspaceViewContainer.swift:100-119`; fallback `WorkspaceLayout.swift:19` |
| Sidebar width (taskFirst) / min-max | `taskSidebarWidth=280`; drag clamp `180`/`480` | `WorkspaceLayout.swift:24,28,32` |
| Row padding / icon column / icon-label gap | leading 8; column 16; gap 10 | `WorkspaceLayout.swift:225,216,220` |
| List padding (Projects tab) | horizontal 8, vertical 4 | `WorkspaceSidebarView.swift:82-83` |
| **Sessions/Projects tab switcher** | No visible in-sidebar control — `sidebarTab` is an `@AppStorage` enum toggled via View menu | `WorkspaceSidebarView.swift:7-10,39,46-93` |
| Toolbar row padding | 12pt horizontal | `WorkspaceSidebarView.swift:172` |
| Toolbar content — forks by tab | Projects: `ToolbarLabelButton(plus,"New Project")`. Sessions: `NewSessionToolbarButton` `Menu`, disabled with no projects. Both icon+label — bare "+" is Framing-c | `WorkspaceSidebarView.swift:166-167`; `RecentsListView.swift:483-528` |
| Toolbar button icon/label/color | icon 10pt `.medium`; label 12pt `.medium`; `.secondary`→`.primary` hover | `WorkspaceSidebarView.swift:514-521` |

## 3. Sessions tab rows (`RecentsRowView` — flat list, no reference photo)

| Value | Source | Citation |
|---|---|---|
| Row height / padding / spacing | 36pt; leading 8pt, trailing 10pt; element gap 10pt | `RecentsRowView.swift:104,102-103,51` |
| Ghost glyph | 14pt, centered in 16pt column, **leading** (before name); tint = `dotColor` (§6 palette) — **is** the status mark, no separate dot | `WorkspaceLayout.swift:230`; `RecentsRowView.swift:54-56,119-129` |
| Name label | Not editing: 12pt regular `Color.primary`. Editing: `TextField`, 12pt regular `.plain` | `RecentsRowView.swift:78-81,61-63` |
| Project subline / timestamp | 10pt regular, `textSecondaryLight/Dark`; `VStack(spacing:1)` name/subline; timestamp `.monospacedDigit()` | `RecentsRowView.swift:84-87,59,96-100` |
| Row bg | Active: `activeRowLight`/`Dark` (§6). Hover: `primary.opacity(0.05)` → light `rgba(0,0,0,.05)`, dark `rgba(255,255,255,.05)`. Radius 6pt | `RecentsRowView.swift:138-145,134` |
| Section headers | "Active"/"Inactive"/"Archive", `"\(title.uppercased()) \(count)"`, count always present; tappable collapse; Archive defaults **collapsed** (`isArchiveExpanded=false`); label = `sectionHeaderForeground` (§6), not tertiary | `RecentsListView.swift:84,108,122,566,22-24,549-579` |

## 4. Projects tab rows (`ProjectDisclosureRow` + `SessionRow` — matches both reference photos)

### Project header row

| Value | Source | Citation |
|---|---|---|
| Row height / padding / spacing | 32pt; leading 8pt/trailing 12pt; element gap 10pt | `ProjectDisclosureRow.swift:348,346-347,305` |
| Ghost glyph | 12×12pt, centered in 16pt column, **leading**; tint = `store.projectGhostColor(for:)` (§6 palette) | `ProjectDisclosureRow.swift:317-326,321` |
| Project name | 13pt `.medium`, tracking `-0.13`, 1 line | `ProjectDisclosureRow.swift:328-331` |
| Hover bg / "+" button | Hover light `rgba(0,0,0,.06)`/dark `rgba(255,255,255,.06)`, 6pt radius; "+" (expanded only) 10pt `.medium` icon, 24×24pt hit target | `ProjectDisclosureRow.swift:349-352,335-340` |
| **No disclosure chevron** — whole row is the tap target | — | `ProjectDisclosureRow.swift:296-354` |
| Expanded container bg / spacing | Dark `Color(white:0.16)`≈`#292929`, Light `Color.white` (dark cited first, source order); `VStack(spacing:2)` | `WorkspaceLayout.swift:95,98`; `ProjectDisclosureRow.swift:390-395,113` |

### Session child row (`SessionRow`, `SessionDetailView.swift`)

| Value | Source | Citation |
|---|---|---|
| Element order | `HStack { name; Spacer(); ghostIndicator }` — glyph **trailing**, opposite of §3's leading | `SessionDetailView.swift:33-73` |
| Row height / padding | 28pt; horizontal 8pt +20pt left indent under project; `HStack(spacing:4)` | `SessionDetailView.swift:75,74,33`; `ProjectDisclosureRow.swift:176` |
| Session name | 12pt: `.semibold` if `needsAttention`, `.medium` if `waiting`, else `.regular`. Color `.primary`, except `.idle` (`secondaryLabelColor`), `.inactive` (`textSecondaryLight/Dark`) | `SessionDetailView.swift:53,168-176` |
| Ghost glyph | 12×12pt in 16×16pt frame; `.filled`, `.outline` (1pt) when `.inactive` | `SessionDetailView.swift:144-145,142` |
| Row bg | Active `activeRowLight/Dark` (§6); hover light `rgba(0,0,0,.04)` / dark `rgba(255,255,255,.04)`; radius 6pt | `SessionDetailView.swift:178-185,76-78` |
| Active-row shadow | `black.opacity(0.1)`, radius 2, y 1 | `SessionDetailView.swift:80-83` |

### Nested/header rows

| Row | Spec | Citation |
|---|---|---|
| In-row group header (`SessionGroupHeader`, only when `groups.count > 1`, buckets Active/Recent/Idle) | `HStack(spacing:5)`: icon 8pt `.semibold` tertiary in 10pt frame + 9pt `.semibold` uppercase tracking `0.5` label (`sessionGroupHeaderForeground`); padding h8/v2, `.leading 20`, top 2 first bucket else 6 | `ProjectDisclosureRow.swift:533-548,552-553,144-145,139,142` |
| "+ New Session" row (below session list) | `HStack(spacing:6)`: plus 10pt `.medium` + "New Session" 11pt `.medium`; padding h8/v4, `.leading 20`; `.tertiary`→`.secondary` hover | `ProjectDisclosureRow.swift:436-443,449-450,121,448` |
| Top-level group header (Pinned/Active Now/Recent/All Projects) | icon 9pt `.semibold` tertiary + 10pt `.semibold` uppercase tracking `0.6` label; padding leading 8/trailing 12/vertical 4 | `WorkspaceSidebarView.swift:436-445,449-451` |
| Sessions-tab bucket header (Active/Inactive/Archive) | `PixelChevronView` 16×16pt + 10pt `.semibold` uppercase tracking `0.6` label; padding leading 8/trailing 12/top 8/bottom 4 | `RecentsListView.swift:557-569,573-576` |

## 5. Type ramp

Web fallback (suggestion only): `-apple-system, "SF Pro Text", "Inter", sans-serif`; terminal: `"SF Mono", ui-monospace, monospace`.

| Surface | Font spec (source) | Citation |
|---|---|---|
| Project name (header row) | 13pt `.medium`, tracking `-0.13` | `ProjectDisclosureRow.swift:329-330` |
| Session name (child row) | 12pt, `.regular`/`.medium`/`.semibold` by state | `SessionDetailView.swift:53` |
| Sessions-tab row name / subline / timestamp | 12pt `.regular` name; 10pt `.regular` subline/timestamp | `RecentsRowView.swift:79,85,97` |
| Section header labels (top-level) | 10pt `.semibold`, tracking `0.6`, uppercase | `WorkspaceSidebarView.swift:443-444` |
| In-row group header labels | 9pt `.semibold`, tracking `0.5`, uppercase | `ProjectDisclosureRow.swift:545-547` |
| Toolbar button label / icons | Label 12pt `.medium`; icon glyphs SF Symbols 8-10pt `.medium`/`.semibold` | `WorkspaceSidebarView.swift:517,438,515`; `ProjectDisclosureRow.swift:337` |
| Terminal content | SF Mono, user-config size — out of sidebar scope | not normative |

*Cut:* prior "Sidebar UI general, SF Pro Text 11pt" row cited stale root
`DESIGN.md:114-119` — every row above is source-grounded instead.

## 6. Color table

### Status palette (literal hex — the ghost glyph itself is tinted; no separate dot)

| State | Hex / value | Source |
|---|---|---|
| Needs decision (gold) / Long-running (orange) | `#FFC400` / `#F97316` | `WorkspaceLayout.swift:148,156` |
| Waiting / your turn (blue) | `#5B8DEF` (replaces terracotta — Framing a) | `WorkspaceLayout.swift:140` |
| Processing / Error | `.systemGreen` ~`#28CD41`L/`#32D74B`D; `.systemRed` ~`#FF3B30`L/`#FF453A`D — verify vs. screenshots | `RecentsRowView.swift:125,121` |
| Idle / Inactive (Sessions-tab dot) | `primary.opacity(0.30)` / `(0.12)`: light black, dark white | `RecentsRowView.swift:126-127` |
| Idle / Inactive (Projects-tab child row+ghost) | `secondaryLabelColor` / `tertiaryLabelColor` — NOT `primary.opacity` | `SessionDetailView.swift:162,164` |
| Idle/inactive project ghost (header row) | `activityNormalForeground` (`Color.primary`) if `lastActiveAt`≤24h, else `activityMutedForeground` (`tertiaryLabelColor`) | `WorkspaceStore.swift:987-1000` |

### Background/text layers

| Role | Light | Dark | Source |
|---|---|---|---|
| Chrome background | `#F0E9E6` | `#242424` | `WorkspaceLayout.swift:109,112` |
| Canvas background | `#FAF7F3` | `#2E2E2E` (approx., generic-gray colorspace) | `WorkspaceLayout.swift:119,123` |
| Text primary | `Color.primary` | `Color.primary` | semantic, dynamic — verify vs. screenshots |
| Text secondary | `#636363` | `#9A9A9A` | `WorkspaceLayout.swift:186,189` |
| Active row tint | `black.opacity(0.04)` | `white.opacity(0.06)` (dark cited first, source order) | `WorkspaceLayout.swift:101,104` |
| Expanded container | `Color(white:0.16)`≈`#292929` | `Color.white` (dark cited first, source order) | `WorkspaceLayout.swift:95,98` |
| Section-header label (top-level + Sessions buckets) | `#636363` | `#9A9A9A` | `WorkspaceLayout.swift:186,189,196-198,445`; `RecentsListView.swift:569` |
| In-row group header label | `#636363` | `#9A9A9A` | `WorkspaceLayout.swift:204-206` |
| Hover: Sessions row / Projects session row / project header | `rgba(0,0,0,.05/.04/.06)` | `rgba(255,255,255,.05/.04/.06)` | `RecentsRowView.swift:144`; `SessionDetailView.swift:184`; `ProjectDisclosureRow.swift:351` |
| Photo-measured (light, ref. only) | Sidebar ≈`#EEE9E5`-`#EDE5E2` (`.sidebar` over `#F0E9E6`); card face ≈`#F7F7F7` (Framing d) | verify vs. dark photo | `WorkspaceViewContainer.swift:58-64` |

## 7. Animation

| Element | Spec | Citation |
|---|---|---|
| Processing ghost | Bounce `offset(y:-2)`, `.easeInOut(1.2s).repeatForever` | `SessionDetailView.swift:100-107` |
| Waiting / Needs-attention ghost | Pulse to 0.6 opacity, `.easeInOut(2.0s)` / `(1.0s)` `.repeatForever` | `SessionDetailView.swift:117-131,117-128` |
| Reduce Motion | All three gated via `accessibilityDisplayShouldReduceMotion` | `SessionDetailView.swift:28-30,101,118,126` |
| Disclosure expand/collapse | `.easeInOut(0.2)`, reduce-motion → `nil` | `ProjectDisclosureRow.swift:296-300` |
| Chevron (Sessions headers) | Rotates -90°→0° on expand, `.easeInOut(0.2)` | `PixelChevronView.swift:37-43` |

## 8. Gaps — visible in reference photos, not pinned to source

- **Traffic-light geometry/spacing/colors** — native AppKit chrome, never drawn/measured in app code.
- **Window corner radius** — native macOS chrome (~10px in photos), no literal in source.
- **No dark-mode photo exists yet** — every dark value above is source-derived, unverified against a render.
- **No Sessions-tab photo exists** — §3 is source-only, unverified against a screenshot.
- **Vertical rhythm** ("Pinned" header/first row, last session/next header in `app-sessions.jpg`) — composed from `.padding` calls (`WorkspaceSidebarView.swift:70`, `ProjectDisclosureRow.swift:113,121`), not pixel-verified.
- **Terminal-pane content** (prompt, output color, globe icon, sidebar toggle) — GhosttyKit chrome, out of scope.
- **Semantic `Color.primary`/`NSColor` hexes** — typical Apple values noted above, dynamic, not literal.

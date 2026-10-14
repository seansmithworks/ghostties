---
version: alpha
name: "Ghostties — Design System"
colors:
  # Two-layer model: chrome (sidebar column + gutter) and canvas (terminal card)
  # Light mode
  chromeBackground: "#F0E9E6"
  canvasBackground: "#FAF7F3"
  textPrimary: "#1a1a1a"
  textSecondary: "#5E5E5E"
  accent: "#C97350"
  border: "#e5e5e3"
  destructive: "#dc3545"
  success: "#2d7d46"
  # Dark mode
  darkChromeBackground: "#242424" # white:0.14
  darkCanvasBackground: "#141413"
  darkTextPrimary: "#f0efed"
  darkTextSecondary: "#a6a6a6"
  darkBorder: "#2a2a2a"
typography:
  ui:
    fontFamily: "SF Pro Text"
    fontSize: "11pt"
    fontWeight: ".regular / .medium"
    notes: "Sidebar labels, project/session names"
  terminal:
    fontFamily: "SF Mono"
    fontSize: "user config"
    notes: "Terminal output, hex values in design docs"
spacing:
  xs: 4
  sm: 8
  md: 12
  lg: 16
  xl: 24
  xxl: 32
  xxxl: 48
  huge: 64
  sidebarWidth: 220
  terminalInset: 8
rounded:
  card: 12
  style: "continuous"
components:
  terminal-card:
    cornerRadius: 12
    shadowColor: "#0F0F0F (light) / #FFFFFF (dark)"
    shadowOpacity: 0.06
    shadowOffset: "0, 2"
    shadowRadius: 16
  overlay-sidebar:
    shadowOpacity: 0.20
  composer-modal:
    shadowOpacity: 0.30
    shadowOffset: "0, 8"
    shadowRadius: 24
---

# Design System: Ghostties

<!-- The YAML frontmatter above is machine-readable and Stitch-CLI-compatible. -->

## 1. Visual Theme & Atmosphere

Ghostties is a workspace tool, not a content surface. The sidebar UI is dense, informational, and intentionally quiet — it defers to the terminal content it frames. Warmth comes from the palette (terracotta accent, warm chrome/canvas tones) and the 24-ghost character set, not from decorative elements or copy.

**Key Characteristics:**

- Full dark and light mode support — both are primary targets
- SF Pro Text for all UI; SF Mono for terminal content and design doc hex values
- Warm two-layer background model (chrome + canvas)
- Terracotta (`#C97350`) as the only saturated accent — reserved for `waiting` state
- 12pt continuous corner radius on the terminal card
- Shadows on the terminal card, the overlay sidebar, the browser card, and
  surfaces that float free of the sidebar (the session composer's
  `.centered` presentation). A floating surface is lifted by shadow alone;
  it never dims the content behind it.
- No gradients, no decorative borders, no visual noise

**Design References:** Ghostty terminal UI, Dia Browser sidebar restraint
**Anti-References:** No companion-app warmth, no productivity-app cheerfulness, no IDE chrome

## 2. Color Palette & Roles

### Two-layer background model (settled Session 17)

Ghostties has exactly two design-system background layers. Neither is bound to the user's terminal theme. Terminal content is GPU-painted by GhosttyKit using the user's terminal config — intentionally outside Swift's scope.

| Layer      | Coverage                                     | Light     | Dark                   | Token name         |
| ---------- | -------------------------------------------- | --------- | ---------------------- | ------------------ |
| **Chrome** | Left sidebar column + gutter padding         | `#F0E9E6` | `#242424` (white:0.14) | `chromeBackground` |
| **Canvas** | Terminal card body (header strip + card rim) | `#FAF7F3` | `#141413`              | `canvasBackground` |

The sidebar itself is `.background(.clear)` in both modes — chrome reads through from the container layer.

### Full palette

| Role                  | Light     | Dark      | Token                        |
| --------------------- | --------- | --------- | ---------------------------- |
| **Chrome background** | `#F0E9E6` | `#242424` | `ChromeTheme.chrome`         |
| **Canvas background** | `#FAF7F3` | `#141413` | `ChromeTheme.canvas`         |
| **Text Primary**      | `#1a1a1a` | `#f0efed` | `textPrimary`                |
| **Text Secondary**    | `#5e5e5e` | `#a6a6a6` | `ChromeTheme.inkSecondary`   |
| **Accent (waiting)**  | `#C97350` | `#C97350` | `waitingTerracotta`          |
| **Composer selection** | `#5B8DEF` | `#5B8DEF` | `composerSelectionAccent`   |
| **Border**            | `#e5e5e3` | `#2a2a2a` | `border`                     |
| **Destructive**       | `#dc3545` | `#dc3545` | `destructive`                |
| **Success**           | `#2d7d46` | `#2d7d46` | `success`                    |

**Accent rule:** Terracotta is reserved exclusively for the `waiting` activity indicator state. Do not use it for hover, selection, or other indicator states.

### Implementation

Every chrome colour that changes with appearance lives in one value type, `ChromeTheme` (`macos/Sources/Features/Ghostties/ChromeTheme.swift`), resolved per appearance as `ChromeTheme.ghostties(colorScheme)`. It holds five base colours; everything else the chrome draws is one of them at a named step. A new colour is a reuse of one of these, never a new token. `ColorLiteralLintTests` fails on any colour literal outside `ChromeTheme.swift` that is not already on its frozen allowlist, and `TokenSyncTests` fails when this file's frontmatter, the Swift tokens and the `Ghostties Light` / `Ghostties Dark` theme files disagree.

| Token          | Light                          | Dark                       | Replaces                                              |
| -------------- | ------------------------------ | -------------------------- | ----------------------------------------------------- |
| `canvas`       | `#FAF7F3`                      | `#141413`                  | The theme file's `background`. No Swift copy.         |
| `chrome`       | `#F0E9E6`                      | `#242424`                  | Chrome background, hover-bar fill, tray glass base.   |
| `ink`          | black                          | white                      | The base of every translucent tint (rows, chips).    |
| `inkSecondary` | `#5E5E5E`                      | `#A6A6A6`                  | Secondary text, section and group headers, empty-project ink, tray icons. |
| `shadow`       | `#0F0F0F`                      | `#FFFFFF`                  | The canvas card's shadow colour.                      |

Named steps on those five:

- `Step.row` ink at 4% (light) / 6% (dark): the active and hovered session row. `Step.composerRow` 6% / 10%: the highlighted row in the Cmd+T composer. `Step.tile` 7%: a project tile's plain fill in dark.
- `Lift.container` and `Lift.border`: the chrome lifted toward white. `container` is the expanded project group's surface (white in light, `0.16` grey in dark); `border` is the tray glass's rim (`#2A2A2A` in dark).

Two values sit outside the five because no step of them reproduces the shipped colour: `tileInk` (`#232120` / `#F0EFED`, a project tile's monogram and the selected project's fill) and `tileFillBase` (`#28221E`, the light tile fill's base). Each is a candidate to merge into `ink` when a design pass allows a visible shift.

`WorkspaceLayout.swift` keeps geometry and the theme-invariant brand and status colours (`waitingTerracotta`, the status dots, `composerSelectionAccent`, the source dots). Never hardcode hex or pt values in view files: pull colours from `ChromeTheme` and the brand block in `WorkspaceLayout`.

### Terminal theme

Out of the box the terminal runs the **Ghostties Light / Ghostties Dark** pair, set by `GhosttiesConfigDefaults` as `theme = light:Ghostties Light,dark:Ghostties Dark`. The defaults load before the user's config, so a user `theme =` (or `background =`, `palette =`) line still wins. The direction is one-way: the theme matches the canvas, the canvas never reads the theme.

| Value                   | Ghostties Light | Ghostties Dark |
| ----------------------- | --------------- | -------------- |
| `background`            | `#FAF7F3` (canvas, light) | `#141413` (canvas, dark) |
| `foreground`            | `#000000`       | `#FFFFFF`      |
| Palette 0–15, cursor, selection | Apple System Colors Light | Apple System Colors |

Only `background` differs from the Apple System Colors originals, so the terminal fills its card with no seam. Contrast against the new backgrounds: foreground 19.66:1 light / 18.43:1 dark. Light mode loses about 6% contrast on every palette entry versus Apple's `#FEFFFF`; dark gains about 10% versus Apple's `#1E1E1E`.

Theme files live in `macos/Resources/ghostty/themes/` beside upstream's. A new pair goes there as `Ghostties <Name> Light` / `Ghostties <Name> Dark`, with its own test arguments in `GhosttiesDefaultThemeTests`.

## 3. Typography Rules

Ghostties uses exactly two font families and a strict size/weight discipline.

| Surface                    | Font        | Size        | Weight                               |
| -------------------------- | ----------- | ----------- | ------------------------------------ |
| Sidebar UI (labels, names) | SF Pro Text | 11pt        | `.regular`, `.medium`                |
| Title above terminal card  | SF Pro Text | 11pt        | `.regular`, centered, 6pt top offset |
| Terminal content           | SF Mono     | User config | —                                    |
| Hex values in design docs  | SF Mono     | —           | —                                    |

**Rules:**

- One font family per surface
- Two weights maximum: `.regular` and `.medium` (or `.semibold` when needed for emphasis — use sparingly)
- No Dynamic Type in sidebar UI — density is intentional at 11pt
- SF Mono for all monospaced content; never SF Pro in the terminal card

### Centered modal — a third surface class

A surface that floats free of the sidebar column entirely — not anchored to it, not part of it — does not inherit the 11pt sidebar density. It gets its own scale:

| Element     | Font        | Size | Weight     |
| ----------- | ----------- | ---- | ---------- |
| Query field | SF Pro Text | 15pt | `.regular` |
| Row title   | SF Pro Text | 13pt | `.medium`  |
| Row subtitle | SF Pro Text | 11pt | —          |

Query field height: 38pt. Row vertical padding: 8pt (the 4pt spacing scale's own value — unlike the sidebar's legacy 5pt).

**Current example:** the session composer (`SessionComposerPalette`, the one centered single-line composer, floats at 360pt wide, introduced in Phase 3 of session-creation-unified). The rule is about floating free of the sidebar, not about which view happens to implement it — the next surface that floats free of the sidebar uses this scale too, whether or not it's `SessionComposerPalette`.

## 4. Component Stylings

### Terminal card (pinned mode)

```swift
.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
// light #0F0F0F, dark #FFFFFF (ChromeTheme.shadow)
.shadow(color: canvasShadowColor.opacity(0.06), radius: 16, y: 2)
// shadowPath must be set explicitly in layout() — see Gotchas
```

### Overlay sidebar

```swift
// Higher opacity shadow to lift from content
.shadow(color: .black.opacity(0.20), radius: 12)
```

### Centered modal — component stylings

Any surface floating free of the sidebar (§3) is a peer to the terminal card, not a one-off: same 12pt `.continuous` corner radius (`WorkspaceLayout.terminalCornerRadius`). Current example: the session composer card. It is lifted by shadow alone (`0.30/24/y8`, §6 — shadow-only elevation, no scrim, PR #132) — no scrim behind it, so the shadow has to carry the "on top of" read by itself. `SessionComposerOverlay` still hosts an invisible dismiss layer beneath the card (`Color.clear` + `.contentShape`) for click-outside-to-dismiss and the a11y dismiss affordance, excluding the titlebar band (0 in fullscreen, where there's no titlebar to protect) so traffic lights and window dragging aren't affected.

Background is layered `.regularMaterial` (a translucent system blur) with the surface's `windowBackgroundColor` blended over it at `.blendMode(.color)` — `.ultraThinMaterial` was too transparent once the scrim stopped dimming the terminal behind it, letting live terminal content wreck the composer's own text contrast (PR #132). Unlike the shadow below, this material composite is applied unconditionally in code.

```swift
// Session composer card:
.clipShape(RoundedRectangle(cornerRadius: WorkspaceLayout.terminalCornerRadius, style: .continuous))
.shadow(
    color: .black.opacity(WorkspaceLayout.composerModalShadowOpacity),
    radius: WorkspaceLayout.composerModalShadowRadius,
    y: WorkspaceLayout.composerModalShadowYOffset
)
```

**Model A rebuild (2026-08, replaces the breadcrumb chips documented in every prior revision of this section).** Sean's ask after using the chip-based field: "I want it to be something I can just type in... let me backspace to delete as well." Three review rounds on the chip field kept finding blockers with one shared root cause — the field's text and the chips were two representations of one string, and they could disagree. Model A has exactly one representation: the `TextField` holds `composerStore.searchText` verbatim, always — nothing is ever consumed into a hidden, non-editable prefix. Backspace, ⌘A, arrow keys, and click-to-position are ordinary `NSTextField` behavior on every macOS version, with no keyboard interception required. The command grammar (`>` segment separator, the project/branch/remainder parse) is unchanged — only the field's own representation and the chip rendering it used to feed are gone.

**Composer UI 11 (2026-08, replaces the resolution line documented in every prior revision of this paragraph).** The row of text that used to sit beneath the field (`→ project · branch · template`) is deleted. Every one of its jobs got a named successor — nothing about "where will this go?" was dropped, it moved:

**In-field ghost placeholder** (`ghostPlaceholder`, `SessionComposerCommandParser.swift`; wired through `ComposerQueryField.placeholder`). While the field is empty, the placeholder renders the exact path Return would currently commit, in the centered composer. Sourced from `resolutionLineSegments(...)` (the same computation the deleted line used) plus `selectedOption?.title` — the identical values a Return commit reads, so the ghost can never state a destination Return would not launch. Four rules, in order: (1) a real project resolved and a template is selected — `"<project> > <branch> > <template>"`, branch segment omitted when the project isn't a git repo; (2) locked and unresolvable — `"Project unavailable"`, a status rather than a false destination; (3) zero projects exist anywhere — `"Add a project to begin"`; (4) otherwise — the plain `"Type a project, branch, and command…"` hint. **Rendered as a layered `Text` in a `ZStack` behind the `TextField`, shown only while `query` is empty** — NOT `TextField`'s `prompt:` initializer, which does not honour `.foregroundColor`/`.opacity` on macOS (measured: the prompt route rendered at ~83% opacity against the 50% target). The overlay `Text` carries `.foregroundColor(Color(nsColor: .labelColor).opacity(0.50))` (`#1A1A1A80`) — the 50% ghost grey, Sean's call looking at the real build after trying 49% and 65%. **This does not meet WCAG AA text contrast** (measured ≈3.0:1 light mode against the 4.5:1 floor; 65% cleared it at 4.74:1) — a deliberate design tradeoff, not an oversight — plus `.lineLimit(1)`/`.truncationMode(.tail)` so a long resolved path truncates on one line instead of wrapping inside the fixed-height field. The overlay pattern is safe only because the field is empty in this state (no horizontal scroll offset to desync against) — see `reference_composer-field-cannot-tint-subranges` before reusing it for non-empty text.

**Status strip** (`statusStripMessage`, one occupant, rendered only when non-nil so the happy-path card carries no strip at all). `writeError` — a failed Return, post-commit, unchanged — always wins over a pre-Return typed-branch-not-found message (`branch "<token>" not found`, `.systemRed`), so a typing-time failure is visible before the user ever presses Return.

**Trailing picker controls and results list — REMOVED.** The field row's trailing project/branch controls, the inline pickers, and the results list (`ComposerResultsTable`/`ComposerRow`, pins/recents lanes, "New template" row) are gone with the anchored popover composer (2026-10-04): there is one composer, the centered single-line card, and no list under the field. Every "+" opens it (a project row's "+" pre-fills that project).

**Templates — managed in Project settings.** Template create / edit / duplicate / pin / delete lives in `ProjectSettingsView`'s **Templates** section (`ProjectTemplatesSection`), labeled "Templates · shared across projects" because templates are global (`WorkspaceStore.templates`). Compact 28pt rows (13pt name, `pin.fill` indicator at 10pt, trailing "…" menu and context menu), `+ New template` as the last row, list capped at 196pt then scrolls. Template changes apply immediately — they are not staged behind the popover's Save/Cancel, which governs only the project's icon, name and default template.

### Row / hover states

Use `ChromeTheme.ink(.row)` for the active and hovered row, `ChromeTheme.lifted(.container)` for the expanded group surface, and `RailProjectColumn.columnFill` for the group card. Do not create new hover colors.

### Session status glyph (pattern D, "type is the icon" — BACKLOG J/K, 2026-09-13)

A session row's status slot holds one monospaced type glyph, replacing the ghost as the status
signal there (the ghost still appears elsewhere — project rollups, empty states, identity). One
status icon per row, never a ghost plus a glyph.

| Session state (`SessionIndicatorState`)      | Glyph          | Color              |
| --------------------------------------------- | -------------- | ------------------- |
| `.processing` / `.longRunning`                | Braille spinner (⠋⠙⠹⠸⠼⠴⠦⠧, ~80ms/frame) | `ChromeTheme.inkSecondary` |
| `.needsAttention`                             | `?`            | `.primary` — the only emphasis; no accent color |
| `.idle` / `.waiting`                          | `✓`            | `ChromeTheme.inkSecondary` |
| `.error`                                      | `✕`            | `ChromeTheme.inkSecondary` |
| `.inactive`                                   | (empty slot)   | —                    |

`✓` also covers `.waiting` — `SessionCoordinator`'s silent/unknown fallback when there's no
observed evidence the session is doing anything, not confirmed work. It must not spin
indefinitely, so it reads at the same low salience as a confirmed-idle session.

Reduce Motion replaces the spinner with a static `…` in the same color; no other state animates.
No new colors — glyph colors are the existing `ChromeTheme` text tokens, not the
`waitingTerracotta`/gold/blue/orange status-dot palette used elsewhere in the sidebar.

## 5. Layout Tokens

```
sidebarWidth:           220pt
titlebarSpacerHeight:   38pt
terminalTitleBarHeight: 28pt
terminalCornerRadius:   12pt
terminalInset:          8pt  (all sides, pinned mode)
overlayTriggerWidth:    10pt
```

### Spacing scale (4pt base)

Valid values only: `4, 8, 12, 16, 24, 32, 48, 64`

Never use arbitrary values (13pt, 22pt, 7pt, etc.).

## 6. Depth & Elevation

Three shadow levels.

| Level                  | Opacity | Radius | Y   | Usage                          |
| ---------------------- | ------- | ------ | --- | ------------------------------- |
| Card (pinned)          | `0.06`  | `16`   | `2` | Terminal card in pinned sidebar, and browser card. Colour per appearance: `#0F0F0F` light, `#FFFFFF` dark |
| Overlay (documented)   | `0.20`  | `12`   | `0` | Sidebar in overlay mode         |
| Centered composer card | `0.30`  | `24`   | `8` | Session composer (`WorkspaceLayout.composerModalShadowOpacity`/`composerModalShadowRadius`/`composerModalShadowYOffset`) — no scrim behind it (shadow-only elevation, PR #132), so it needs to read heavier than the Overlay row it used to (coincidentally) match |

**Known deviation (pre-existing, not from Phase 3):** the "Overlay" row's actual code values (`WorkspaceViewContainer.swift`, `sidebarOverlayBackground.layer`) are opacity `0.2`, radius `6`, offset `(2, 0)` — not `0.20/12/0` as documented above. This table has been wrong since before session-creation-unified; flagged here rather than silently propagated. The centered composer card row is its own level, independently tuned in PR #132 — it no longer coincides with the Overlay row's documented numbers.

**Critical:** `shadowPath` must be set explicitly in `layout()`. Without it, CoreAnimation rasterizes from the alpha channel every frame (GPU performance hit).

## 7. Shapes

One radius. One style. No exceptions.

| Surface                              | Radius | Style         |
| ------------------------------------- | ------ | ------------- |
| Terminal card                         | 12pt   | `.continuous` |
| Centered composer card | 12pt   | `.continuous` |

Always pass `style: .continuous` to `RoundedRectangle` — it matches Apple's squircle aesthetic.

### Known Deviations


## 8. Do's and Don'ts

### Do

- Define all chrome color tokens in `ChromeTheme.swift` (brand and status colours in `WorkspaceLayout.swift`) — view files pull from there
- Use chrome/canvas tokens for background layers — never bind to terminal theme
- Set `shadowPath` explicitly in `layout()` before the card renders
- Keep sidebar UI at 11pt SF Pro Text — resist upsizing for "readability"
- Reserve terracotta for the `waiting` indicator state only
- Support both dark and light mode — always test both
- Use `randomUnused(excluding:)` when assigning ghost characters to new sessions
- Full-bleed 1024×1024 for the app icon — no rounded corners, no drop shadow (macOS applies its own squircle tile)

### Don't

- Bind chrome or canvas background to the user's terminal theme (`surface.derivedConfig.backgroundColor`)
- Hardcode hex or pt values in view files — use `ChromeTheme` and `WorkspaceLayout` tokens
- Use terracotta for hover, selection, or states other than `waiting`
- Mix corner radii — 12pt continuous everywhere on the terminal card
- Add shadows outside the card, overlay, browser, and floating-modal contexts listed in §1
- Use `update_styles` in Paper MCP to change SVG attributes — use `write_html(mode: "replace")` instead

## 9. Device Targets

macOS only. No iPhone or iPad targets.

| Platform                 | Notes                   |
| ------------------------ | ----------------------- |
| macOS (AppKit + SwiftUI) | Primary and only target |

## 10. Theme Conversion Checklist

When converting dark ↔ light in Paper or in code:

- [ ] Artboard / window background
- [ ] Chrome layer (sidebar column)
- [ ] Canvas layer (terminal card body)
- [ ] Expanded / selected container backgrounds (easy to miss)
- [ ] Primary, secondary, tertiary text colors
- [ ] Terminal output text, path, prompt, cursor
- [ ] SVG icon strokes and fills (`write_html` replace, not `update_styles`)
- [ ] Traffic lights, status dots (usually keep as-is)

## 11. Agent Prompt Guide

When generating SwiftUI or AppKit views for this project:

- Read this file first — do not guess tokens
- All colors from `ChromeTheme.swift` (chrome) or `WorkspaceLayout.swift` (brand, status) — never `Color(red:green:blue:)` in view files
- Chrome and canvas are the only two background layers — never bind to the user's terminal theme
- Terracotta (`#C97350`) is reserved for the `waiting` indicator state only
- Corner radius is 12pt `.continuous` on the terminal card — nowhere else unless explicitly specified
- `shadowPath` must be set in `layout()` — not left to CoreAnimation
- SF Pro Text 11pt for sidebar UI; SF Mono for terminal content
- Spacing from the 4pt scale only: `4, 8, 12, 16, 24, 32, 48, 64`
- macOS only — no `horizontalSizeClass` adaptation needed

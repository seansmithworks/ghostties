---
version: alpha
name: "Ghostties — Design System"
colors:
  # Two-layer model: chrome (sidebar column + gutter) and canvas (terminal card)
  # Light mode
  chromeBackground: "#F0E9E6"
  canvasBackground: "#FAF7F3"
  textPrimary: "#1a1a1a"
  textSecondary: "#636363"
  accent: "#C97350"
  border: "#e5e5e3"
  destructive: "#dc3545"
  success: "#2d7d46"
  # Dark mode
  darkChromeBackground: "#242424" # white:0.14
  darkCanvasBackground: "#2D2D2D" # white:0.18
  darkTextPrimary: "#f0efed"
  darkTextSecondary: "#9a9a9a"
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
    shadowOpacity: 0.15
    shadowOffset: "0, 2"
    shadowRadius: 8
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
| **Canvas** | Terminal card body (header strip + card rim) | `#FAF7F3` | `#2D2D2D` (white:0.18) | `canvasBackground` |

The sidebar itself is `.background(.clear)` in both modes — chrome reads through from the container layer.

### Full palette

| Role                  | Light     | Dark      | Token                        |
| --------------------- | --------- | --------- | ---------------------------- |
| **Chrome background** | `#F0E9E6` | `#242424` | `chromeBackgroundLight/Dark` |
| **Canvas background** | `#FAF7F3` | `#2D2D2D` | `canvasBackgroundLight/Dark` |
| **Text Primary**      | `#1a1a1a` | `#f0efed` | `textPrimary`                |
| **Text Secondary**    | `#636363` | `#9a9a9a` | `textSecondary`              |
| **Accent (waiting)**  | `#C97350` | `#C97350` | `waitingTerracotta`          |
| **Border**            | `#e5e5e3` | `#2a2a2a` | `border`                     |
| **Destructive**       | `#dc3545` | `#dc3545` | `destructive`                |
| **Success**           | `#2d7d46` | `#2d7d46` | `success`                    |

**Accent rule:** Terracotta is reserved exclusively for the `waiting` activity indicator state. Do not use it for hover, selection, or other indicator states.

### Implementation

All tokens live in `macos/Sources/Features/Ghostties/WorkspaceLayout.swift`. Never hardcode hex or pt values in view files — always pull from `WorkspaceLayout`.

**Legacy tokens** still in `WorkspaceLayout.swift` (`cardBackgroundLight/Dark`, `expandedContainerLight/Dark`, `activeRowLight/Dark`) are kept for row/hover state — do not confuse with the bg-layer tokens above.

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

Query field height: 38pt. Row vertical padding: 8pt (the 4pt spacing scale's own value — not the sidebar popover's legacy 5pt, see §7's Known Deviations).

**Current example:** the session composer's `.centered` presentation (`SessionComposerPalette`, floats at 360pt wide, introduced in Phase 3 of session-creation-unified). Its `.anchored` presentation — the same view, popped out of a sidebar row — stays on the sidebar scale instead, since it IS anchored to the sidebar column. The rule is about floating free of the sidebar, not about which view happens to implement it — the next surface that floats free of the sidebar uses this scale too, whether or not it's `SessionComposerPalette`.

## 4. Component Stylings

### Terminal card (pinned mode)

```swift
.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
.shadow(color: .black.opacity(0.15), radius: 8, y: 2)
// shadowPath must be set explicitly in layout() — see Gotchas
```

### Overlay sidebar

```swift
// Higher opacity shadow to lift from content
.shadow(color: .black.opacity(0.20), radius: 12)
```

### Centered modal — component stylings

Any surface floating free of the sidebar (§3) is a peer to the terminal card, not a one-off: same 12pt `.continuous` corner radius (`WorkspaceLayout.terminalCornerRadius`). Current example: the session composer's `.centered` presentation card. It is lifted by shadow alone (`0.30/24/y8`, §6 — shadow-only elevation, no scrim, PR #132) — no scrim behind it, so the shadow has to carry the "on top of" read by itself. `SessionComposerOverlay` still hosts an invisible dismiss layer beneath the card (`Color.clear` + `.contentShape`) for click-outside-to-dismiss and the a11y dismiss affordance, excluding the titlebar band (0 in fullscreen, where there's no titlebar to protect) so traffic lights and window dragging aren't affected. `.anchored` (the sidebar popover presentation of the same view) is unchanged — unstyled 10pt radius, relies on the native `NSPopover` chrome/shadow instead; see §7's Known Deviations.

Background is layered `.regularMaterial` (a translucent system blur) with the surface's `windowBackgroundColor` blended over it at `.blendMode(.color)` — `.ultraThinMaterial` was too transparent once the scrim stopped dimming the terminal behind it, letting live terminal content wreck the composer's own text contrast (PR #132). Unlike the shadow below, this material composite is applied unconditionally in code — it is NOT `.centered`-only, and `.anchored` (the sidebar popover) inherits it too.

```swift
// .centered only — .anchored uses native NSPopover chrome; applying this
// there would double up.
.clipShape(RoundedRectangle(cornerRadius: WorkspaceLayout.terminalCornerRadius, style: .continuous))
.shadow(
    color: .black.opacity(WorkspaceLayout.composerModalShadowOpacity),
    radius: WorkspaceLayout.composerModalShadowRadius,
    y: WorkspaceLayout.composerModalShadowYOffset
)
```

The composer's project control is a breadcrumb CHIP (`projectChip`, composer breadcrumb spec Slice A) at the HEAD of `queryRow`, not a trailing control — this replaced the old trailing `projectControl` (hairline divider + label + chevron) so the project no longer competes with the search field for width as a second control; the chip renders inline instead, followed by a `›` separator and the field. It has two visual states, keyed off `isProjectLocked`. Locked renders plain secondary-styled text with no pill background — a pill with nothing behind it reads as a control that isn't one, so it's omitted deliberately, same reasoning this section recorded for the old divider-plus-chevron control. Unlocked renders a pill: `WorkspaceLayout.composerChipBackground`/`composerChipBackgroundActive` (resting/open), `cornerRadius: 5` via `.clipShape(..., style: .continuous)` (matches `ComposerRow`'s existing row-highlight radius), horizontal padding 8pt / vertical 4pt. Both states are always present, even with no project selected — an unresolved chip shows a "Select project" placeholder rather than disappearing, since it is the ONLY project affordance in the composer once the trailing control was removed (it must stay reachable with zero projects and after backspacing a chip back to text). Both states truncate the label (`.lineLimit(1)`) and cap at 96pt wide rather than wrapping or squeezing the field — the chip sits in a `queryRow` HStack alongside the query field, and project names come from `url.lastPathComponent` of a user-picked folder, so long names are the normal case. Type size is `fieldFontSize` (matches the query field, both presentations) so the breadcrumb reads as one line rather than two competing scales.

### Row / hover states

Use `cardBackgroundLight/Dark`, `expandedContainerLight/Dark`, `activeRowLight/Dark` tokens from `WorkspaceLayout.swift`. Do not create new hover colors.

### Activity indicator states

| State       | Color                         |
| ----------- | ----------------------------- |
| Waiting     | `waitingTerracotta` `#C97350` |
| Running     | — (system)                    |
| Idle / done | — (muted)                     |

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
| Card (pinned)          | `0.15`  | `8`    | `2` | Terminal card in pinned sidebar, and browser card |
| Overlay (documented)   | `0.20`  | `12`   | `0` | Sidebar in overlay mode         |
| Centered composer card | `0.30`  | `24`   | `8` | Session composer, `.centered` presentation (`WorkspaceLayout.composerModalShadowOpacity`/`composerModalShadowRadius`/`composerModalShadowYOffset`) — no scrim behind it (shadow-only elevation, PR #132), so it needs to read heavier than the Overlay row it used to (coincidentally) match |

**Known deviation (pre-existing, not from Phase 3):** the "Overlay" row's actual code values (`WorkspaceViewContainer.swift`, `sidebarOverlayBackground.layer`) are opacity `0.2`, radius `6`, offset `(2, 0)` — not `0.20/12/0` as documented above. This table has been wrong since before session-creation-unified; flagged here rather than silently propagated. The centered composer card row is its own level, independently tuned in PR #132 — it no longer coincides with the Overlay row's documented numbers.

**Critical:** `shadowPath` must be set explicitly in `layout()`. Without it, CoreAnimation rasterizes from the alpha channel every frame (GPU performance hit).

## 7. Shapes

One radius. One style. No exceptions.

| Surface                              | Radius | Style         |
| ------------------------------------- | ------ | ------------- |
| Terminal card                         | 12pt   | `.continuous` |
| Centered composer card (`.centered`) | 12pt   | `.continuous` |

Always pass `style: .continuous` to `RoundedRectangle` — it matches Apple's squircle aesthetic.

### Known Deviations

- **Composer popover (`.anchored` presentation, `SessionComposerPalette`).** 10pt radius, unstyled default (`.circular`), not `.continuous`. Shipped in Phase 2, before this rule was written down as covering the composer at all. Not extended further — the `.centered` presentation above is `.continuous`, and any future presentation should be too. Do not fix this by loosening the rule again; fix it by eventually restyling the popover instead.

## 8. Do's and Don'ts

### Do

- Define all color tokens in `WorkspaceLayout.swift` — view files pull from there
- Use chrome/canvas tokens for background layers — never bind to terminal theme
- Set `shadowPath` explicitly in `layout()` before the card renders
- Keep sidebar UI at 11pt SF Pro Text — resist upsizing for "readability"
- Reserve terracotta for the `waiting` indicator state only
- Support both dark and light mode — always test both
- Use `randomUnused(excluding:)` when assigning ghost characters to new sessions
- Full-bleed 1024×1024 for the app icon — no rounded corners, no drop shadow (macOS applies its own squircle tile)

### Don't

- Bind chrome or canvas background to the user's terminal theme (`surface.derivedConfig.backgroundColor`)
- Hardcode hex or pt values in view files — always use `WorkspaceLayout` tokens
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
- All colors from `WorkspaceLayout.swift` — never `Color(red:green:blue:)` in view files
- Chrome and canvas are the only two background layers — never bind to the user's terminal theme
- Terracotta (`#C97350`) is reserved for the `waiting` indicator state only
- Corner radius is 12pt `.continuous` on the terminal card — nowhere else unless explicitly specified
- `shadowPath` must be set in `layout()` — not left to CoreAnimation
- SF Pro Text 11pt for sidebar UI; SF Mono for terminal content
- Spacing from the 4pt scale only: `4, 8, 12, 16, 24, 32, 48, 64`
- macOS only — no `horizontalSizeClass` adaptation needed

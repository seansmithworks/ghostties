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
- Shadows only on the terminal card — nowhere else
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

### Centered modal (session composer)

A third surface class, distinct from sidebar UI — introduced in Phase 3 of session-creation-unified (`SessionComposerPalette`, `.centered` presentation only). It floats free of the sidebar column at 360pt wide, so it does not inherit the 11pt sidebar density; the anchored popover presentation (the same view, `.anchored`) keeps the sidebar scale unchanged.

| Element                  | Font        | Size | Weight     |
| ------------------------ | ----------- | ---- | ---------- |
| Query field               | SF Pro Text | 15pt | `.regular` |
| Row title                 | SF Pro Text | 13pt | `.medium`  |
| Row subtitle               | SF Pro Text | 11pt | —          |

Query field height: 38pt. Row vertical padding: 8pt (the 4pt spacing scale's own value — not the sidebar popover's legacy 5pt).

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

### Centered modal (session composer card)

Peer surface to the terminal card, not a one-off: same 12pt `.continuous` corner radius (`WorkspaceLayout.terminalCornerRadius`), and reuses the Overlay sidebar's shadow spec above rather than inventing a third shadow level. Paired with a full-bleed black-0.25 scrim (`SessionComposerOverlay`) so the card reads as "on top of" the terminal — the scrim excludes the titlebar band so traffic lights and window dragging aren't affected. `.anchored` (the sidebar popover presentation of the same view) is unchanged — unstyled 10pt radius, relies on the native `NSPopover` chrome/shadow instead.

```swift
.clipShape(RoundedRectangle(cornerRadius: WorkspaceLayout.terminalCornerRadius, style: .continuous))
.shadow(color: .black.opacity(WorkspaceLayout.composerModalShadowOpacity), radius: WorkspaceLayout.composerModalShadowRadius)
```

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

Two shadow levels — terminal card and overlay. The centered composer card reuses the Overlay level rather than adding a third.

| Level         | Opacity | Radius | Y   | Usage                                              |
| ------------- | ------- | ------ | --- | --------------------------------------------------- |
| Card (pinned) | `0.15`  | `8`    | `2` | Terminal card in pinned sidebar                    |
| Overlay       | `0.20`  | `12`   | `0` | Sidebar in overlay mode; centered composer card    |

**Critical:** `shadowPath` must be set explicitly in `layout()`. Without it, CoreAnimation rasterizes from the alpha channel every frame (GPU performance hit).

## 7. Shapes

One radius. One style. No exceptions — for surfaces documented here.

| Surface                          | Radius | Style         |
| --------------------------------- | ------ | ------------- |
| Terminal card                     | 12pt   | `.continuous` |
| Centered composer card (`.centered`) | 12pt   | `.continuous` |

Always pass `style: .continuous` to `RoundedRectangle` — it matches Apple's squircle aesthetic. (The composer's `.anchored` sidebar-popover presentation keeps its own unstyled 10pt radius from Phase 2 — a legacy exception, not a new one; do not extend it further.)

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
- Add shadows outside the card and overlay contexts
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

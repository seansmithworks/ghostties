# Flow 01 — Sidebar presence

Build four sidebar widths with one rule: **chrome never floats over live terminal content.** Every control sits in its own opaque surface. This closes the carried header-pivot item (variant E placement) — the legibility pass killed glass controls over htop, light themes and diffs.

Source of truth: pen.dev frame `mkJau` in `~/.pencil/documents/edff08ac-9284-4e03-a98e-52105f8fbeab/pencil-new.pen`. Reference PNGs in `./reference/`. Mock window is 700×520 for layout only — **all point values below are literal**.

| # | State | Sidebar | Traffic lights | Terminal | Reference |
|---|---|---|---|---|---|
| 01 | Expanded | 244pt, pinned | in sidebar top | inset card | `state-01-expanded-244.png` |
| 02 | Collapsed | 72pt rail | in sidebar top | inset card | `state-02-collapsed-72.png` |
| 03 | Closed | 0pt + 24pt hot zone | hidden | full bleed, no chrome | `state-03-closed-0.png` |
| 04 | Revealed | 244pt opaque overlay | in overlay top | full bleed underneath | `state-04-revealed.png` |

## What actually changes in code

Grounded in `macos/Sources/Features/Ghostties/`. Verify each before building — this was read, not run.

- **`SidebarMode` gains a fourth case** (`WorkspaceLayout.swift:10`). Today: `pinned / closed / overlay`. The 72pt rail is new. It is `Codable` by `Int` raw value and persisted in `WorkspaceStore`, so **append `case collapsed = 3`** — do not renumber.
- **`sidebarWidth` 220 → 244**, and add `sidebarRailWidth: CGFloat = 72` (`WorkspaceLayout.swift:19`). `sidebarMinWidth`/`sidebarMaxWidth` (180/480) still govern drag in expanded mode only; the rail is not drag-resizable.
- **`overlayTriggerWidth` 10 → 24** (`WorkspaceLayout.swift:116`, used at `WorkspaceViewContainer.swift:1436`). The hot zone is invisible in the app — the `#ffffff08` fill on the canvas is a diagram device only.
- **The reveal overlay goes opaque.** The sidebar today sits on an `NSVisualEffectView` with material `.sidebar`, blending `.behindWindow` (`WorkspaceViewContainer.swift:74-79`). State 04 is a hard-edged opaque panel — no background blur. This supersedes DESIGN.md §4 "Overlay sidebar".
- **The bottom tray is new.** `WorkspaceSidebarView.swift` has no footer today — no New Session, toggle or account row below the list. All three are new construction in both expanded and rail form.
- **Traffic lights already behave correctly** for closed (`setTrafficLightsHidden(sidebarMode == .closed)`, `WorkspaceViewContainer.swift:545`). Rail and overlay must keep showing them.
- **Toggle cycling changes.** `toggleSidebar()` (`:906`) is a two-way pinned↔closed flip today. The rail needs a route in and out — see open decision 1.

## Specs

### Window shell (every state)
- Chrome fill `#1c1c1c`, window corner radius 20, clipped.
- Terminal card: fill `#0a0300`, radius 12 (18 in states 03/04 where it meets the window edge).
- Card wrapper padding: top/right/bottom 8, **left 0** in states 01/02; 0 all round in states 03/04.
- Card edge light: outer shadow `#ffffff1a`, offset (−4, 0), blur 12. This is a left rim-light, not a drop shadow — the existing `canvasShadow*` tokens are black and do something different.

### 01 — Expanded, 244pt
- Sidebar: vertical, `space_between`, padding 16 / 10 / 14 / 10 (T/R/B/L). Content column 224.
- Top group, vertical, gap 14: traffic lights → section header → session rows.
- Traffic lights: three 12pt circles, gap 8 — `#FF5F57` / `#FEBC2E` / `#28C840`.
- Section header: height 24, padding 4/8, gap 10. 12pt `chevron-down` (lucide) `#9a9a9a` in a 16pt column; title Geist 11/500 `#c8c6c3`; count Geist 11 `#7a7a7a`. **Same 34pt rail as the session names** — do not indent it differently.
- Session rows: vertical, gap 2. Each 42pt tall, padding 6/8, gap 10, radius 6.
  - Leading 16×16 status chip, radius 4 — this is the existing `SessionStatusGlyph` (pattern D), not new art.
  - Text column, gap 1: name Geist 12 `#c8c6c3`; subtitle Geist 10 `#9a9a9a`, truncating.
  - Trailing meta column, gap 4, right-aligned: elapsed Geist Mono 9.5 `#9a9a9a`; activity marks 5×3 `#c8c6c3` gap 4 over a 10×1 tail rule `#4a4a4a`.
  - Active row: 2×26 bar `#f0efed`, radius 1, pinned to the row's left edge 8pt from its top.
- Bottom group, vertical, gap 6: 1pt divider `#ffffff14`, then three dock items — 28pt tall, padding 6/8, gap 10, radius 6, 14pt lucide icon `#9a9a9a` + Geist 12 `#c8c6c3` label.
  - `plus` → "New Session" · `panel-left` → "Close Sidebar" · 16pt avatar circle `#2A5E4A` with Geist 9/500 `#E8F3EC` initial → account name.

### 02 — Collapsed rail, 72pt
- Same padding as expanded, centre-aligned, `space_between`. Content column 52.
- Top group gap 14: traffic lights unchanged, then rail rows — 52×32, radius 6, gap 4, centre-stacked status chip (16) + marks (3×2, gap 2).
- Labels drop; the glyphs stay. **The tray survives the collapse unchanged** — grouping comes from the surface, not from a hairline rule across a narrow column.
- Bottom group gap 12, centred: tray pill 40 wide, fill `#ffffff0a`, fully rounded, padding 4, gap 2, holding two 32×32 icon buttons (`plus`, `panel-left`); then a 28pt account circle `#2A5E4A` with Geist 12/500 initial, outside the pill.

### 03 — Closed, 0pt
- No chrome at all: no header, no band, no floating buttons, no traffic lights. Terminal is full bleed at radius 18.
- A 24pt invisible hot zone on the window's left edge is the only affordance.

### 04 — Revealed
- 244pt opaque panel, fill `#1c1c1c`, radius 18, inset 4pt from the window edges, 1pt stroke `#00000026`.
- Shadow: `#00000080`, offset (12, 0), blur 16 — cast right, onto the terminal.
- Identical internal layout to state 01 so nothing is re-learned. Only the toggle label differs: "Open Sidebar".
- Clicking the toggle promotes it to pinned (state 01) — this already exists at `WorkspaceViewContainer.swift:910`.

## Decisions for Sean

1. **How do you reach the rail?** Nothing on the canvas says. Recommended: toggle cycles `pinned → collapsed → closed → pinned`, so one control walks all three persistent widths and the hot zone stays the only way back from closed.
2. **Does the rail get its own hover-reveal?** Recommended no — reveal at 244 from any non-pinned state, so there is one reveal, not two.
3. **DESIGN.md §5 conflicts with this canvas.** §5 allows only `4, 8, 12, 16, 24, 32, 48, 64`; the sidebar internals here use 2, 6, 10, 14, 34, 42. Recommended: amend §5 to admit a 2pt sub-scale for sidebar internals and record 244/72/24 as tokens — the canvas is the newer decision and the rows were tuned to it.
4. **Is there an account entity?** The footer shows "Sean Smith" with an initial avatar; nothing in the sidebar sources reads a user today. If there is no account model, this row is a settings/profile affordance and needs a destination.

Transition timing is unspecified on the canvas — reuse the existing `transitionTo` animation unless it reads wrong at 72pt.

Out of scope: `flow-02-list-organisation` (frame `Y3bTXV`) is a separate canvas and a separate build.

# Selected-row mix: build contract

Sean's pick (2026-10-19, r9 board, Mix): row motion **04 Hand-off**, project switch
**P1 Cross-fade**, new tab **N4 Outline first**, **Glass on**, **Switch 300ms**,
**New tab 600ms**. Supersedes `selected-row-outline-contract.md` (the r7 06 drawn
trace): nothing is traced any more; the outline cross-fades.

- **Rest:** the selected row is a 1pt `inkSecondary` outline at 0.4 over the
  selected-row tint (`SidebarColors.selectedRowTint`), exactly as 06's rest. The dark tint
  value is set by Amendment 1 below. One
  active-group card (the glass card) sits behind the project holding the active
  session; its tile is ink-filled. Tokens only, no new colour, no edge stripe.
- **Row switch (same project), click:** the old row's outline and tint fade out as the
  new row's fade in, in place, 300ms. Nothing moves.
- **Project switch, click:** the card fades off the old group and onto the new one in
  place, 300ms; the row hand-off plays inside it and lands at 275ms. No group folds.
- **New tab:** the outline lands first on an empty slot that grows under it, then the
  session's content fades in; 600ms. Into a folded project, only that project unfolds.
- **Keys (Cmd+Shift+] / [):** snap to the end state. **Retarget:** starts from the
  current value, never from 0, never queued. **Reduce Motion:** opacity fades only,
  120ms in / 100ms out, nothing changes size or position.
- **Curves:** opacity `bezier(0.77, 0, 0.175, 1)`; size `bezier(0.77, 0, 0.175, overshootY2)`,
  `overshootY2 = 1.2` (one constant, tunable; Sean picked 1.2 over 1.1 for a visible overshoot). Only N4 moves geometry (the new row's
  height, so the outline grows with it, and a folded target's unfold), so that is the
  only place the overshoot shows. 04 and P1 are opacity-only.
- **Surfaces:** sidebar list, rail (expanded project = tile + session-chip column;
  folded = one tile with its count badge; empty = dimmed tile, no chevron) and the
  rail hover panel; light and dark.

Gate: `macos/Tests/Ghostties/SelectedRowMixModelTests.swift` (timeline),
`SelectedRowMixPixelTests.swift` (rest pixels). Numbers: `node docs/plans/selected-row-mix-reference.js`.

## API the builder provides (`@testable import Ghostty`)

```swift
enum SelectedRowMix {
    static let switchMs: Double          // 300
    static let newTabMs: Double          // 600
    static let reduceMotionInMs: Double  // 120
    static let reduceMotionOutMs: Double // 100
    static let restOutlineOpacity: Double // 0.4
    static let overshootY2: Double       // 1.2
    static func ease(_ x: Double) -> Double          // bezier(0.77, 0, 0.175, 1), clamped 0...1 in x
    static func easeOvershoot(_ x: Double) -> Double // bezier(0.77, 0, 0.175, overshootY2)

    /// One session row. outline: the outline's opacity (0...0.4); tint: the selected-row
    /// tint's opacity scale (0...1); height: the row's height as a fraction of its
    /// natural height (1 except a growing new row; may pass 1 by < 3%); content: the
    /// row's glyph + label opacity (1 except a new row filling in).
    struct RowLook: Equatable { var outline, tint, height, content: Double }
    /// One project group. card: the active-group card's opacity behind it, and its tile's
    /// ink fill; open: how unfolded it is, 0...1 (may pass 1 by < 3% while unfolding).
    struct GroupLook: Equatable { var card, open: Double }
    enum Input: Equatable { case click, key }

    struct Timeline {   // a value type; every input is explicit, no clock inside
        init(active: UUID?, activeGroup: String?, collapsed: Set<String>)
        var active: UUID? { get }
        var activeGroup: String? { get }
        var collapsed: Set<String> { get }   // the folds to persist (ProjectAccordionState)
        mutating func select(_ session: UUID, in group: String, via: Input, reduceMotion: Bool, at ms: Double)
        mutating func newTab(_ session: UUID, in group: String, reduceMotion: Bool, at ms: Double)
        func row(_ session: UUID, at ms: Double) -> RowLook   // unknown row: (0, 0, 1, 1)
        func group(_ group: String, at ms: Double) -> GroupLook
        var settledAt: Double { get }        // the ms the last channel lands
    }
}
```

- Group ids are `SidebarProjectGroup.ID` strings; session ids are `AgentSession.id`.
- `row`/`group` are defined for `ms` at or after the latest event. Events arrive in time order.
- The view drives a clock only while `ms < settledAt` (as `SelectedRowOutlineClock` does today), so a resting list never ticks.
- The chevron fold is not in the model. It keeps `SidebarUISpring.fold`; the model only owns a new tab's unfold.

## Timing tables

Each channel holds its value at the event, then runs `from -> to` over `[a, b]` ms after
the event. One factor per event scales the variant's own numbers to the picked total,
which is how the board's Mix ("total" mode) plays them.

**Row switch, same project, click, @300** (04 at k = 300/220):

| channel | to | a | b | curve |
|---|---|---|---|---|
| old row outline | 0 | 0 | 300 | ease |
| old row tint | 0 | 0 | 218.2 | ease |
| new row outline | 0.4 | 0 | 300 | ease |
| new row tint | 1 | 81.8 | 300 | ease |

**Project switch, click, @300** (P1 at k = 300/240 = 1.25; the hand-off inside it runs on the same 1.25, so it lands at 275):

| channel | to | a | b | curve |
|---|---|---|---|---|
| every other group's card | 0 | 0 | 300 | ease |
| target group's card | 1 | 0 | 300 | ease |
| old row outline | 0 | 0 | 275 | ease |
| old row tint | 0 | 0 | 200 | ease |
| new row outline | 0.4 | 0 | 275 | ease |
| new row tint | 1 | 75 | 275 | ease |

**New tab, @600** (N4 at k = 600/440; the hand-off and P1's card cross-fade inside it run on the same k):

| channel | to | a | b | curve | when |
|---|---|---|---|---|---|
| new row height | 1 (from 0) | 0 | 354.5 | easeOvershoot | always |
| new row content | 1 (from 0) | 327.3 | 600 | ease | always |
| new row outline | 0.4 | 0 | 300 | ease | always |
| new row tint | 1 | 81.8 | 300 | ease | always |
| old row outline / tint | 0 | 0 / 0 | 300 / 218.2 | ease | always |
| target group open | 1 (from 0) | 0 | 354.5 | easeOvershoot | target was folded |
| every other card / target card | 0 / 1 | 0 | 327.3 | ease | card was elsewhere (folded target, or another open project) |

- **Active-project new tab:** the card never moves; only the slot, outline and content play.
- **Outline grows with the row:** the outline and tint are drawn on the row's current (height-scaled) frame, so in N4 they grow, and overshoot, with it.
- **Height overshoot** at `overshootY2 = 1.2` passes the target at about 70% of the segment, peaks at +2.25% at about 83% (about 1.1pt on a 48pt row) and lands exactly at 100%.
- **Engine check:** the r9 engine's own probe at k = 1 (headless, `?ev=P1&rowmo=04&probe=120&evt=switch`) gives cards 0.404/0.596 and new-row tint 0.171; `?ev=N4&probe=130&evt=new-closed` gives open and height 0.596. The reference reproduces both at the same k.

## Rules

- **Keys snap.** Cmd+Shift+] / [ (and any key-driven selection) first lands every channel in flight at its target, then shows the new end state at once: target row at rest, every other row clear, the card on the target's group. No frame in between.
- **Retarget never restarts or queues.** A new event replaces the tracks of the channels it touches, from their current values, with full durations from the new event; untouched channels keep running. Velocity matching is not required.
- **Touched by a select:** the previously selected row, the new one, and (on a project switch) every group's card. Not touched: other rows still fading, an in-flight new row's height and content, and any group's `open`.
- **A second new tab** lands the earlier new row's height and content at once, then plays its own.
- **Reduce Motion** replaces every track with a timed `ease` fade from the current value: fade-ins 120ms (new row outline + tint, target card, new row content), fade-outs 100ms (old row, old cards). Nothing changes size: a folded target opens at once, a new row is full height at once, an in-flight unfold or growth lands at once. Reduce Motion wins over the key snap (the engine fades on keys too).
- **Groups:** expand and collapse independently. The model never folds a group; a project switch never changes any `open` or the `collapsed` set. A new tab into a folded project removes only that project from `collapsed`; the builder persists it with `ProjectAccordionState.expanded`.
- **Opacity** channels stay in 0...1 (the outline in 0...0.4); size channels may pass 1 by under 3% and land exactly on 1.

## Glass: the active-group card

The mock's glass (r8 05, verbatim in the r9 engine), in token terms, over the `chrome`:

- **Dark:** a vertical gradient of `ink` at 12% (top) to 6% (bottom); a 1px inner top highlight of `ink` at 16%; a 0.5pt inner hairline of `ink` at 8%; a soft drop glow `0 2 12` of `shadow` at 6%; a backdrop blur 20 + saturate 1.5, which over the flat chrome is invisible.
- **Light:** a vertical gradient of `canvas` at 90% (top) to 55% (bottom); a 1px inner top highlight of `canvas`; a 0.5pt inner hairline of `ink` at 6%; a drop shadow `0 2 12` of `shadow` at 8%.
- **Shape:** unchanged from today's `ProjectGroupCard` geometry (rect, radius 12, insets, the rail column's narrowing). Only the fill changes.

The builder picks the API (layered SwiftUI fills, `.glassEffect`, an `NSVisualEffectView`). What must hold, measured on raw pixels by `SelectedRowMixPixelTests`:

- **Lift band:** the card's body, over the chrome, lifts luminance by the gradient's span: dark between 6% and 12% of (`ink` − `chrome`), light between 55% and 90% of (`canvas` − `chrome`), with 10% slack. The old dark card (4% white, lift 0.034 on #242424) fails this, which was Sean's report.
- **AA under muted text:** `inkSecondary` on the card's top band (under the header) must clear 4.5:1. The mock's dark 12% top stop gives 4.39:1 and fails, so the dark top stop must stay at or under about 11% `ink`.
- **Everywhere it sits:** sidebar list, rail column, and the hover panel (the hover panel renders the list, so the list test covers it).

## What replaces the 06 trace

- **Gone:** the trace (`traceProgress`, the 0.6 draw opacity, `outlinePath`'s start-at-leading-middle order), `.leaving` 100ms, the click-origin window (`recordClick`, `clickWindow`), and the rail's selection-chip travel (`SelectionChipTravel` on `.move`).
- **Kept:** the 1pt `inkSecondary` stroke inset 1pt at radius 8 (`SelectedRowOutline.strokeWidth/inset/cornerRadius`, `box()` for the rail morph), the tint token, the resting look.
- **Click vs key:** decided by the input, not by a timing window. A row tap passes `.click`; Cmd+Shift+] / [ passes `.key`; anything else that changes the selection (Cmd+1–9, a session closing) passes `.key`.

## Tests to retire (the builder updates or deletes these with the change)

- **`SelectedRowOutlineModelTests` (whole suite):** pins the 06 trace (click checkpoints, `traceProgress`, `.leaving` 100ms, `Mode`, the path's start point). The path-geometry tests (inset 1, r8, `box()`) stay valid only if `outlinePath`/`box` are kept.
- **`SelectionChipTravelTests.testSelectionChipTravelsToTheNewRow`** (`SidebarUISpringTests.swift`): requires one chip travelling between rows and fails on two at once; the hand-off is exactly two cross-fading.
- **`SidebarProjectsLayoutTests.testRailColumnDialDefaultsAreOptionD`**, lines asserting `columnTintOpacity == 0.04`, `columnFillOpacity(.dark) == 0.04`, `columnFillOpacity(.light) == 0.45`: the flat fill the glass replaces.
- **`ChromeColorGoldenTests`** goldens `column.fill|dark/light` and `column.fillDarkAtDefaultTint`: same flat fill.
- **`SidebarContrastTests.secondaryTextClearsAAOnCardAndChrome`:** its approved dark card floor (5.6:1) caps the dark card at about 4.5% white, which is the card Sean reported as invisible; even the glass's weakest stop (6%) gives 5.35:1. It conflicts with the glass; see the decision below. AA (4.5) stays.
- **`SidebarBeta26FeedbackGateTests` empty-project AA tests and `SidebarRetiredDialsTests`/`SidebarHistoryPlacementTests` reads of `columnFillOpacity(.light)`:** they treat `columnFill` as the card's fill; repoint them at the new card's representative colour (its top stop, the worst case for text).
- **`SidebarBeta26FeedbackGateTests.emptyProjectTileGlyphClearsAA`, the "group card" case** (amended 2026-10-19, removed by the amender, not the builder): an empty project never holds the active-group card, so the tile glyph is never drawn on it. The chrome case stays.
- **Still valid, keep:** `SelectedRowOutlinePixelTests` (resting outline + tint, light), `SelectedRowFootprintTests` (rail chip footprint, row-wide expanded surface).

## Amendments (2026-10-19, Sean)

1. **Dark selected-row subtitle must clear AA.** Measured 3.3:1: `inkSecondary` on the 10% selected tint over the glass card. Fix (Sean, 2026-10-19): in dark, the selected row and the rail chip use a 10% **black** tint, not white. White over the dark glass card cannot clear AA (4.54:1 untinted, 3.35:1 at 10%), and lowering a white tint can't clear AA either; 10% black measures 4.976:1 for `inkSecondary` on the card's top stop. The subtitle colour is unchanged. Light is unchanged (10% `ink`, which is black). The resting-tint pixel gate renders the dark row over the card's representative colour (the selected row always sits on the active-group card), not the bare chrome.
2. **Dark group-card text floor 5.6 to 4.5 (commit `cd006b697`) is confirmed.** "Decision 2" below is resolved.
3. **Empty-project tile glyph, "on card" case dropped** from `emptyProjectTileGlyphClearsAA`; see "Tests to retire". Off-card cases stay.

## Decisions

1. **Overshoot size: decided, 1.2** (2026-10-19). 1.1 peaked at +0.64% (about 0.3pt on a 48pt row), present but invisible; 1.2 peaks at +2.25%, under the 3% cap.
2. **Dark card contrast floor: confirmed by Sean (2026-10-19).** The gate requires AA 4.5:1 for `inkSecondary` on the card's top band, which caps the dark top stop at about 11% `ink`. `SidebarContrastTests`' approved 5.6:1 dark floor cannot hold with any glass that makes the card visible (see "Tests to retire").

<details><summary>Resolutions of ambiguities in the design source</summary>

- **Hand-off inside a project switch lands at 275, not 300:** the engine runs the row on the switch's factor (300/240), so 04's 220ms becomes 275. Kept engine-exact.
- **Reduce Motion fade-out is 100ms everywhere:** the engine fades the old card out over 120; the brief says 120 in / 100 out. Followed the brief.
- **An unfold always finishes:** the engine cancels the whole event lane on a project switch, which can freeze a folded project half-open mid new tab. Here a group's `open` is never touched by a select.
- **Reduce Motion never resets content:** the engine resets an in-flight new row's content to 0 under Reduce Motion; here it fades on from its current value.
- **The tile's ink follows the card's opacity:** the engine sets each tile's ink from its group's card opacity, so `GroupLook.card` drives both.
- **Curves:** Sean changed the engine's single ease-in-out to ease-in-out with a slight overshoot on size channels only (2026-10-19), y2 = 1.2. Opacity channels keep the engine's curve.
- **Overshoot window:** with y2 = 1.2 the size curve passes its target from about 70% of the segment; the tests check it is over at 75% and 90%, under at 65%, and exact at 100%.

</details>

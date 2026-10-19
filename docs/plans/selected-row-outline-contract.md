# Selected-row outline: model contract

The gate for the "drawn outline" selected state (card 06, r7, with Sean's
"ease in and out" change). The builder implements this API; the tests in
`macos/Tests/Ghostties/SelectedRowOutline*Tests.swift` check it against
`docs/plans/selected-row-outline-reference.js`, which holds the card's JS.

Source of truth for every number: card 06, `VARIANT.select` and `VARIANT.rm`
(`.mild2wild/2026-10-16-connected-tab/r7/06-drawn-outline/index.html`, git-excluded)
on the r7 engine's `bezier`, `seg`, `lerp` (`r7/_base/index.html`).

## Behaviour

Applies to the selected session row in the sidebar list, the rail (around the
40pt tile/chip) and the rail hover-reveal panel.

- **Click**: a 1pt `inkSecondary` outline (r8, centreline inset 1pt inside the row)
  is traced once, from the leading edge's middle, clockwise, 0-260ms. Outline
  opacity 0 -> 0.6 over 0-80ms, then 0.6 -> 0.4 over 260-300ms. The existing
  selected-row tint fades in 80-260ms. Rest: outline 0.4 + tint 1.
- **Leaving**: outline and tint fade out together in 100ms, from wherever they are.
- **Up/Down (every press)**: snaps to rest, no trace. A retarget mid-trace
  continues from the current frame, never queues.
- **Reduce Motion**: no trace. Rest outline + tint fade in over 120ms, out over 100ms.
- Every curve is `bezier(0.77, 0, 0.175, 1)` (ease-in-out). Tokens only: no new
  colour, no accent stripe, no canvas join.

## API (`macos/Sources/Features/Ghostties/SelectedRowOutline.swift`, `@testable import Ghostty`)

```swift
enum SelectedRowOutline {
    /// One instant of the effect. traceProgress 0...1 is the drawn fraction of
    /// the path (the card's pathLength = 1 dash); tintOpacity 0...1 scales the
    /// existing selected-row tint.
    struct Frame: Equatable { var traceProgress, outlineOpacity, tintOpacity: Double }
    static let hidden = Frame(traceProgress: 0, outlineOpacity: 0, tintOpacity: 0)
    static let rest   = Frame(traceProgress: 1, outlineOpacity: 0.4, tintOpacity: 1)

    enum Mode: Equatable {
        case click(from: Frame)          // 300ms; `.hidden` for a fresh pick, the live frame for a retarget
        case rest                        // keys: the resting frame, any elapsed
        case leaving(from: Frame)        // 100ms; traceProgress is left as it was
        case reduceMotionIn(from: Frame) // 120ms; traceProgress 1
        case reduceMotionOut(from: Frame)// 100ms; traceProgress 1
    }

    static func duration(_ mode: Mode) -> Double   // ms: 300, 0, 100, 120, 100
    /// `elapsedMs` is clamped to 0...duration.
    static func frame(elapsedMs: Double, mode: Mode) -> Frame

    /// bezier(0.77, 0, 0.175, 1) on 0...1 (clamped). Any solver within 1e-3.
    static func curve(_ x: Double) -> Double

    static let strokeWidth: CGFloat = 1, inset: CGFloat = 1, cornerRadius: CGFloat = 8

    /// Closed rounded rect, y-down, centreline inset by `inset`, radius
    /// min(8, w/2, h/2) after the inset. First element `.move` to the leading
    /// edge's middle, then up (anticlockwise on paper, clockwise on screen with y
    /// down: the card's `d()`), ending back at that point and `.closeSubpath`.
    /// `Path.trimmedPath(from: 0, to: traceProgress)` is the trace.
    static func outlinePath(rowRect: CGRect) -> Path

    /// The card's `box()`: the row's rect at morph 0, the chip's at 1, linear between.
    static func box(row: CGRect, chip: CGRect, morph: Double) -> CGRect
}
```

Mode maths (`t = clamp(elapsedMs)`, `io = curve`, `seg(t,a,b) = clamp01((t-a)/(b-a))`,
`f` = the `from` frame):

| mode | traceProgress | outlineOpacity | tintOpacity |
|---|---|---|---|
| click | `lerp(f.trace, 1, io(seg(t,0,260)))` | t <= 260: `lerp(f.op, 0.6, io(seg(t,0,80)))`; else `lerp(0.6, 0.4, io(seg(t,260,300)))` | `lerp(f.tint, 1, io(seg(t,80,260)))` |
| leaving | `f.trace` | `f.op * (1 - io(t/100))` | `f.tint * (1 - io(t/100))` |
| rest | 1 | 0.4 | 1 |
| reduceMotionIn | 1 | `lerp(f.op, 0.4, io(t/120))` | `lerp(f.tint, 1, io(t/120))` |
| reduceMotionOut | 1 | `lerp(f.op, 0, io(t/100))` | `lerp(f.tint, 0, io(t/100))` |

## Rendering (what the pixel test asserts)

The list row, rail tile/chip and hover-panel row draw `outlinePath` stroked
`inkSecondary` (1pt) at `outlineOpacity`, trimmed to `traceProgress`, over the
selected-row tint (`SidebarColors.selectedRowTint`) scaled by `tintOpacity`.
A row that is already selected when it first appears renders at `.rest`: no trace.
The list selection is the row-wide tint plus outline (the card), replacing the
glyph-slot chip in the list; `SelectedRowFootprintTests.testExpandedSelectedRowIsTheChipBehindTheGlyphSlot`
encodes the old footprint and is the builder's to update with the change.
No hit-testing, no animation modifier left on the old chip for the list row.

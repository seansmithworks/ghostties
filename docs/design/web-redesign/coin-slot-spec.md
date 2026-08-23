# Coin slot — build spec

**Supersedes the earlier discreet-ember concept (below the fold).** The user supplied
two reference photos of real coin plates — a backlit arcade keychain (saturated red
panel glowing behind stacked `25¢` / `INSERT COIN TO PLAY` type, a tall slot down the
left) and a cabinet coin door (chunky gold-outlined `INSERT` / `COIN`, double rule
divider, coin entering edge-on) — and called the keychain "pretty much what I
envisioned." That overrides the original "dark plate, ember only" direction: a real
coin plate is a *lit* object, not a hidden one.

A **backlit coin plate**: a black bezel with real thickness, an inset red panel that
glows and blooms slightly past its own edges, a tall vertical slot occupying roughly
the left third of the panel, and stacked gold `INSERT` / `COIN` type separated by a
double rule. Fixed top-right, small, corner-mounted hardware — not a promoted button.
Pressing it drops a coin into the slot, flashes the backlight, flips `CR 0` to `CR 1`,
and swaps the label to `ESC` / `EXIT`.

```
   fixed: top 16, right 16                z-index 90
   ┌────────────────────────────┐
   │ ┌──┐                       │
   │ │▐▐│   I N S E R T         │  78px
   │ │▐▐│   ─────────           │
   │ │▐▐│   C O I N             │
   │ └──┘   CR 0                │
   └────────────────────────────┘
      ▲       ▲                    100px
      │       └ stacked label, double rule, credit readout
      └ slot, ~24px wide (left third of the panel), lamp/catch-light on its lip
```

## States

| | Panel backlight | Label | Credit | Bezel |
|---|---|---|---|---|
| **Rest** | breathing bloom, 3.2s alternate, shallow | `INSERT` / `COIN` gold | `CR 0` | flat, top catch-light |
| **Hover / focus-visible** | breathing stops, bloom strengthens + widens (no layout shift) | brighter gold glow | unchanged | unchanged |
| **Press** | flashes brighter (`gx-coin-panel-flash`, ~350ms) while the coin drops; bezel depresses `translateY(1px)` with inverted bevel | unchanged until settle | flips to `1` at t=200ms | inverted bevel |
| **Armed** | steady bloom, no breathing | `ESC` / `EXIT` gold | `CR 1`, digit brightens to `#ffe9a8` | flat, top catch-light |

**State is never signalled by colour alone** — the label line text and the credit digit
both change, both text at high contrast against the red field. That is also how WCAG
1.4.11 is met here: the control is identified by its always-present label, not by the
backlight hue.

## Exact values

**Footprint.** `position: fixed; top: 16px; right: 16px; width: 100px; height: 78px;`
`z-index: 90` (above `.gx-ghost` at 2–3; below `.skip-link` at 100 and `.gx-label` at
300). Small screens (`max-width: 480px`): `top/right: 10px`, plate `82x64`.

**Colour — scoped to this component, not the shared token file.** Defined as CSS
custom properties on `.gx-coin` itself:

```
--coin-bezel:   #101012
--coin-red-hi:  #c81b22
--coin-red-lo:  #4a0509
--coin-gold:    #e8b545
--coin-glow:    rgba(255, 40, 34, 0.4)
```

Never `--amber` (`#ffd54f`) — that stays the page's CTA colour, and reusing it here
would blur the corner back into "third install button." `--coin-gold` is a deliberately
more saturated, warmer yellow so the two read as different materials even side by side.

**Bezel.** `.gx-coin-bezel` — black (`--coin-bezel`), `padding: 6px` (small: `5px`) so
the black frame reads as real material thickness around the lit panel, `border-radius:
5px`. Two faint radial-gradient highlights fake the case's dome/texture. Depth comes
from `box-shadow`: an outer drop shadow (`0 3px 8px rgba(0,0,0,.55)`) plus two inset
edges (`inset 0 1px 0 rgba(233,230,245,.08)` top highlight, `inset 0 -2px 3px
rgba(0,0,0,.65)` bottom shadow) — the plate reads as mounted on the page's dark face,
not floating.

**Panel.** `.gx-coin-panel` fills the bezel's padding box, `border-radius: 2px`, flex
row (`slot` + `info`). Fill is a radial gradient from `--coin-red-hi` to `--coin-red-lo`
(`120% 140% at 30% 20%`) for internal glow rather than a flat fill. Bloom is an outer
`box-shadow` (`0 0 10px var(--coin-glow)`, `0 0 20px rgba(255,20,16,.16)` at rest) that
extends past the panel's own edge — this is the "light blooms slightly past its edges"
behaviour from the keychain reference. Panel depth: `inset 0 1px 0 rgba(255,255,255,.1)`
top highlight, `inset 0 -3px 5px rgba(0,0,0,.55)` bottom shadow.

**Slot.** `24px` wide (small: `20px`), `align-self: stretch` with `margin: 7px 0` so it
runs nearly the full panel height — a substantial vertical element occupying the left
quarter to third of the plate, per both references. Fill a near-black vertical gradient
(`#150406` → `#060102` → `#150406`) with an inset shadow for aperture depth. A
`.gx-coin-lamp` child lays a warm rim highlight along the inner edges (`inset 1px 0 0
rgba(255,205,130,.35)`, `inset -1px 0 0 rgba(255,205,130,.12)`) — a static catch-light
on the lip, not an animated ember; the backlight (panel bloom) is what breathes now,
not the slot.

**Type.** `.gx-coin-label-line`: `--font-display` (Silkscreen) **700** (chunky weight —
the reference's outlined block letters), `11px/1` (small: `9px`), `letter-spacing
.03em`, uppercase, fill `--coin-gold`, `text-shadow: 0 0 3px rgba(232,181,69,.55)` to
fake the backlit-outline glow at pixel-font sizes (a true stroked outline reads muddy
below ~14px in a pixel typeface — this is the honest approximation, noted for anyone
revisiting at larger sizes). `.gx-coin-rule`: a **double rule** (matching the cabinet
reference, not just the keychain's single divider) — `border-top` + `border-bottom`,
both `1px solid var(--coin-gold)`, `height: 3px` so a 1px gap shows between them,
`width: 32px` (small: `26px`), centred. `.gx-coin-credit`: `--font-mono` (DM Mono),
`7px/1` (small: `6.5px`), `letter-spacing .12em`, uppercase, dim gold; the digit is a
`<b>` at weight 500 in full `--coin-gold`, brightening to `#ffe9a8` when armed. Copy
shortened from `CREDIT` to `CR` — the panel is roughly a third of its old width's worth
of type real estate now that it's carrying two stacked words plus a rule.

**Cursor** `pointer`. Hover rules go inside `@media (hover: hover)` so an iOS tap
doesn't leave the hover backlight stuck on.

**The coin** is the original 6×6 inline SVG pixel-circle, now drawn at `8×8`, `--coin-
gold` fill, absolutely positioned over the slot mouth (`left: 8px` / small: `6px`,
`top: -18px`) so it visibly falls in from above the plate.

## Motion

| Step | Time | Easing (literal) | What moves |
|---|---|---|---|
| Attract breath | 3200ms, `infinite alternate` | `ease-in-out` | panel bloom `box-shadow` alpha only |
| Rest → hover | 220ms | `cubic-bezier(.25,1,.5,1)` | panel bloom, label text-shadow |
| Press depress | 60ms | `linear` | bezel `translateY(1px)` + bevel inversion |
| Coin fall | 200ms | `cubic-bezier(.5,0,.75,0)` | coin `translateY(-18px → 0)`; at 75% `scaleX(.5)` and fade to 0 |
| Panel flash | 90ms in / 260ms out | in `linear`, out `cubic-bezier(.25,1,.5,1)` | panel bloom to peak, back to armed level |
| Credit flip | instant at t=200ms | — | `textContent` 0 → 1 |
| Armed settle | — | — | bloom animation removed (goes steady), rule opacity → 1 |
| Coin-out (Esc / re-click) | 180ms | `cubic-bezier(.25,1,.5,1)` | everything back to rest |

Press → armed totals ~420ms, unchanged from the original build. `var()` is not
substituted for `animation-timing-function`/colour values inside `@keyframes` and fails
silently back to the shorthand curve (`DESIGN.md` §5) — every literal above is written
out in the CSS, not referenced through a custom property, inside `gx-coin-breathe`,
`gx-coin-fall`, and `gx-coin-panel-flash`.

**The attract behaviour is a breath, never a blink.** A ~0.5s blinking `INSERT COIN` is
the authentic arcade attract cadence, and it is exactly what makes a control read as a
promoted CTA. The blink lives on the backlight only, slowed to 3.2s and held to a
shallow bloom-alpha swing. **The label text never blinks, in any version of this
component.**

## Copy

| State | Label (two lines) | Credit | `aria-label` | `title` |
|---|---|---|---|---|
| Rest / hover / press | `INSERT` / `COIN` | `CR 0` | `Insert coin` | `Insert coin (C)` |
| Armed | `ESC` / `EXIT` | `CR 1` | `Return coin and exit the ghost field` | `Return coin (Esc)` |

Live region `#gx-coin-status` (`role="status" aria-live="polite"`, in `v3.html`):

- Coin-in: `Credit 1. The ghost field is live. Press Escape to return your coin.`
- Coin-out: `Coin returned. The ghost field is ambient again.` — clears after 3s.

No number appears anywhere except the credit count, which counts coins, not ghosts.

## The coin — a physical, grabbable object

The coin is no longer a decorative flourish that plays once on plate-press. It is a
single physical object drifting in the ambient ghost field (`assets/ghost-field.js`,
alongside the ghosts), and dragging it into this plate's slot is *how* the field arms —
not a side effect of pressing a button.

- **One coin, drawn like the ghosts.** Same technique (inline SVG built from a small
  pixel grid, no image files), an 8×8 grid at 4px/cell, filled `#e8b545` with a soft
  top-edge highlight gradient for shine — no new asset pipeline.
- **Drift pacing matches the ghosts', kept under ~0.6px/frame** — ambient, not urgent.
  Same wall-bounce clamp as every ghost.
- **Grabbable before coin-in, when no ghost is.** Every `.gx-ghost` is `pointer-events:
  none` until `.gx-armed`; the coin is `pointer-events: auto` unconditionally, because
  it's the one thing that has to be interactive precomputed-armed in order to arm
  anything. Cursor is `grab` at rest, `grabbing` while dragged.
- **Lives in its own stacking context, not inside `#gx-field`.** The field paints under
  page content (`z-index: 0`, vs. `main`'s `1`) by design, so ghosts drift behind text —
  correct for ambient background sprites, but it would leave the coin permanently
  ungrabbable wherever it happened to drift under a heading or button. The coin element
  is appended to `<body>` instead, `z-index: 50` — above page content, still under the
  plate (`90`) and skip-link (`100`) — so it's reachable anywhere on the page.
- **Pointer Events, not separate mouse/touch handlers** (`pointerdown`/`pointermove`/
  `pointerup` with `setPointerCapture`), so one code path drives both mouse and touch
  drag with no duplication. `touch-action: none` on the token stops the browser
  scrolling the page mid-drag on mobile.
- **Drop tolerance is generous.** The hit test on release is the plate's own bounding
  box inflated by 40px on every side — a pixel-perfect target on a drifting object is
  miserable to hit, on a touchscreen especially.
- **Dropped on the slot → inserts.** The coin animates into the slot (translate + scale
  down + rotate, 220ms, matching the existing coin-fall easing) and is hidden
  (`display: none`) once it lands — it is genuinely gone while the game is armed, not
  just invisible-but-present. `GXField.coinIn()` arms the field from this path exactly
  like it does from a plate click or the `"c"` key.
- **Dropped anywhere else → keeps drifting.** The existing throw-velocity math (drop
  delta × damping, capped) carries over unchanged from the ghost drag code — the coin
  picks up release velocity like a thrown ghost does.
- **Coin return is symmetric.** `GXField.coinOut()` (Escape, or the plate again) reverses
  the insert animation from the slot's position outward, then hands the coin back to
  normal drift physics with a small "pop" velocity. The state is visibly reversible, not
  just functionally.

### One state, several listeners — not several flags

`armed` (in `ghost-field.js`) is the only truth. The coin's position/visibility, the
plate's label/credit/aria, and every ghost's `pointer-events` all derive from it, never
from a second `coinInserted`-style flag that could drift out of sync. Concretely:

- `coinIn()`/`coinOut()` are the single entry points, reachable from drag-drop landing on
  the slot, the plate's click handler, the `"c"` key, or GXField's own Escape listener —
  every path funnels through the same two functions, so the coin, the plate, and the
  ghosts' interactivity can't disagree about which path was used.
- They run `coinInsert()`/`coinEject()` (the coin's own animation) directly, and then
  dispatch a `"gx-armchange"` `CustomEvent` on `document` with `{ armed: true|false }`.
- The plate's script (`v3.html`) no longer runs its choreography (panel flash, label
  swap, credit flip, live-region announce) inline inside its own click handler — it
  listens for `"gx-armchange"` and reacts to whatever GXField reports, so a coin-drag
  arm gets the identical plate choreography a click-arm gets, with no duplicated code
  path to fall out of sync.

## Accessibility

- **It is a real `<button type="button">`.** Enter and Space activate natively — no
  keydown handler for them.
- **Accessible name swaps with state** (table above). Still no `aria-pressed`: the two
  states are different verbs, not one thing toggled on and off.
- **Focus-visible inherits the global rule** in `v3.css`. `:focus-visible` also triggers
  the full hover backlight response, so a keyboard user gets the same "the machine
  noticed you" feedback as a mouse hover.
- **Getting out:** Escape (handled in `ghost-field.js`), or activating the plate again.
  No separate coin-return button.
- **`prefers-reduced-motion: reduce` → `display: none` on the whole control, unchanged.**
  `ghost-field.js` returns a stub `GXField` in its reduce branch (`toggleCoin` a no-op,
  `isArmed` permanently `false`), so the plate is a dead control there — removing it
  from the page and the tab order is the honest answer. Verified: computed `display` is
  `none` under an emulated `reducedMotion: 'reduce'` context.

## Build notes

- **Markup shape (updated):** `button > span.gx-coin-bezel[aria-hidden] > span.gx-coin-
  panel > (span.gx-coin-slot > span.gx-coin-lamp + svg.gx-coin-piece) + (span.gx-coin-
  info > (span.gx-coin-label > span.gx-coin-label-line × 2 + span.gx-coin-rule) +
  span.gx-coin-credit)`. All decorative structure sits under one `aria-hidden="true"` on
  `.gx-coin-bezel`, since the button's own `aria-label` carries the accessible name.
- **The label is two DOM spans, not one text node**, so `INSERT`/`COIN` and `ESC`/`EXIT`
  can sit either side of the double rule without relying on line-wrap. The inline script
  in `v3.html`'s `render(armed)` writes `labelLines[0].textContent` /
  `labelLines[1].textContent` instead of a single `.textContent` assignment.
- The `C` key route stays, and the `title` still advertises it. The
  `docs/design/web-redesign/README.md` says the key is `I`; the code says `c`. Still out
  of scope here.
- Apply CSS/HTML edits via `sed`/`python3` from Bash — the global Prettier
  `PostToolUse` hook reformats any `.html`/`.css` touched by Edit/Write and will bury
  the diff.

## References

Two photos supplied directly by the user (not sourced from the web) drove this pass:

1. A backlit arcade coin-plate keychain — black textured bezel, saturated red panel
   glowing behind stacked `25¢` / `INSERT COIN TO PLAY`, tall slot down the left side,
   bloom visible past the panel edge. Called "pretty much what I envisioned" — the
   primary target.
2. A real cabinet coin door at an angle — black bezel with visible thickness, deep red
   field, chunky gold-outlined `INSERT` / `COIN` stacked with a **double** horizontal
   rule between them, a coin entering the slot edge-on. Took: the double-rule detail
   (the keychain has none) and the chunky/outlined type treatment.

Prior research references (arcade cabinet PSU lighting, coin-door parts inventories,
lamp colour temperature, hardware label phrasing, attract-mode cadence, easter-egg
discovery patterns, coin-entry geometry) are unchanged from the original pass and still
inform the parts of this spec the photos didn't override — footprint discretion, label
phrasing conventions, motion timing, and the coin's edge-on entry. See git history for
the original citation list if needed; trimmed here to keep this file describing what
was actually built rather than accumulating research that's now baked into the values
above.

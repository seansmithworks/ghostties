# Coin slot — build spec

**Round 3 (current, supersedes Round 2 below on six points) matches a close-up
reference photo of a real arcade coin plate, not the keychain shot Round 2 was built
from.** The keychain reference read as landscape and near-white type; the close-up
photo makes clear the real object is **portrait** (`≈0.64` w/h, not landscape),
**type is glowing red** (`≈#ff2a18` fading to `≈#e01810`), not white/orange, the
lamp is a **bright bar across the top** with a visible hot point (not a centred
radial hotspot), the plastic reads **deep translucent red** (`≈#8a1a10` near the
lamp to `≈#2a0806` at the bottom, not the brighter `--coin-red-hi`/`--coin-red-lo`
below), the bezel texture is **coarser** (pebble/crinkle, not a fine 3px stipple),
and the slot is a **long vertical channel, ~17% width × ~73% height**, not a
`20px`-wide flex-stretch column. Layout also changes: the label is three stacked
lines — `INSERT` / `COIN TO` / `PLAY`, with `PLAY` set largest — rather than two.

- **Footprint:** `92×144` (small ≤480px: `78×122`), not `118×94`/`92×76`. Aspect
  `~0.639`, portrait.
- **Colour vars:** `--coin-red-hi: #8a1a10`, `--coin-red-lo: #2a0806`,
  `--coin-type: #ff2a18` with a `--coin-type-lo: #e01810` for the smaller lines —
  `--coin-gold`/`--coin-frame`/`--coin-glow`/`--coin-bezel` unchanged.
- **Panel fill** is now a fixed (non-animated) top-to-bottom `linear-gradient`
  (`--coin-red-hi → #5c120c → --coin-red-lo`) carrying the falloff, with the lamp's
  hot bar living entirely on `.gx-coin-panel::after` (a top-aligned `linear-gradient`
  + off-centre radial hot point, `mix-blend-mode: screen`) so it can pulse without
  the base colour ever flattening out. The `gx-coin-breathe` `box-shadow` keyframe
  from Round 2 is retired; the pulse is carried by `::after` opacity alone
  (`gx-coin-breathe-glow`, unchanged 1700ms swing, now `.24 → .82`).
- **Slot:** `width: 17%; height: 73%; align-self: center;` on `.gx-coin-slot`,
  replacing the `20px`/`16px` fixed-width, full-stretch column.
- **Type:** `.gx-coin-price` `17px` (small: `14px`), `.gx-coin-label-line` `7.5px`
  (small: `6.5px`) in `--coin-type-lo`, and a new `.gx-coin-label-line-big` modifier
  (`12px`/small `10px`, `--coin-type`) on the `PLAY`/`EXIT` line — hierarchy matches
  the reference's largest-line-on-bottom reading. Text-shadow layers are now red-only
  (no white core) — hot red bleeding to a duller red, never white/orange.
- **Bezel texture:** the `repeating-radial-gradient` pitch widened `3px → 6px` and two
  `repeating-linear-gradient` diagonal streak layers (118°/26°) added on top, for a
  coarser, less uniform crinkle than the fine stipple alone gave.
- **Hero overlap re-swept** for the taller plate: `.hero { padding-top }` is now
  `188px` at `≤900px` (was `132px`) and `154px` at `≤480px` (was `108px`), based on a
  320–1200px sweep of real `getBoundingClientRect()` overlap against `h1`/`.head`,
  not a spot-check.

Everything below this point describes Round 2 and is superseded on the six points
above; the shared parts (states table, motion timing outside the retired
`gx-coin-breathe` keyframe, copy/ARIA grammar except the label going from two lines
to three, the physical coin object) still apply.

**Round 2 matches the user's actual keychain reference photo, not just its
colour palette.** The first pass (below, superseded in the details but not the
direction) got the black bezel and red field right but was a *coloured rectangle with
gold type* — flat fill, no hotspot, no inner lit frame, painted-looking type. The user
pointed at the reference again and asked for the panel to read as a genuinely lit sign,
plus an explicit glowing pulse. This pass adds: a top-down lamp hotspot the field falls
off from (not a flat fill), a lit red inner frame around the panel (the acrylic's own
edge-lit border, distinct from the bezel), backlit type — near-white cores bleeding to
red-orange via layered `text-shadow`, because the light comes through the letters, not
sitting on top of them — and a `25¢` price line over the stacked `INSERT COIN` / `TO
PLAY` label, matching the reference's actual arrangement (`INSERT COIN` currently wraps
to two lines at this width, giving three visual lines total — `INSERT` / `COIN` / `TO
PLAY` — which happens to track the reference's three-line layout closely).

**Supersedes the earlier discreet-ember concept (below the fold).** The user supplied
two reference photos of real coin plates — a backlit arcade keychain (saturated red
panel glowing behind stacked `25¢` / `INSERT COIN TO PLAY` type, a tall slot down the
left) and a cabinet coin door (chunky gold-outlined `INSERT` / `COIN`, double rule
divider, coin entering edge-on) — and called the keychain "pretty much what I
envisioned." That overrides the original "dark plate, ember only" direction: a real
coin plate is a *lit* object, not a hidden one.

A **backlit coin plate**: a black bezel with real thickness, corner-screw hardware, and
a faint stippled texture, an inset red panel lit from a hotspot near the top and
falling off toward the bottom, a lit inner frame (the panel's own glowing border) just
inside the bezel, a tall vertical slot occupying roughly the left third of the panel
with its own edge light, and backlit `25¢` over stacked `INSERT COIN` / `TO PLAY` type.
Fixed top-right, small, corner-mounted hardware — not a promoted button. Pressing it
drops a coin into the slot, flashes the backlight, flips `CR 0` to `CR 1`, and swaps
the label to `ESC` / `EXIT`. The backlight breathes on a slow, luminous cycle at rest —
the pulse the user asked for explicitly — never blinking the label.

```
   fixed: top 16, right 16                z-index 90
   ┌──────────────────────────────┐
   │ ┏━━┓ ┌──────────────────┐    │
   │ ┃▐▐┃ │      2 5 ¢       │    │  94px
   │ ┃▐▐┃ │     INSERT       │    │
   │ ┃▐▐┃ │      COIN        │    │
   │ ┗━━┛ │     TO PLAY      │    │
   │      │      CR 0        │    │
   │      └──────────────────┘    │
   └──────────────────────────────┘
      ▲       ▲                      118px
      │       └ lit inner frame around the panel; backlit type, credit readout
      └ slot, ~20px wide, own edge light on its lip
```

## States

| | Panel backlight | Type | Credit | Bezel |
|---|---|---|---|---|
| **Rest** | breathing pulse, 1.7s alternate (~3.4s full swell-fade cycle), clearly perceptible | `25¢` / `INSERT COIN` / `TO PLAY`, backlit white-to-red-orange | `CR 0` gold | flat, top catch-light |
| **Hover / focus-visible** | breathing stops, bloom strengthens + widens (no layout shift) | brighter backlit glow | unchanged | unchanged |
| **Press** | flashes brighter (`gx-coin-panel-flash`, ~350ms) while the coin drops; bezel depresses `translateY(1px)` with inverted bevel | unchanged until settle | flips to `1` at t=200ms | inverted bevel |
| **Armed** | steady bloom, no breathing | `25¢` stays; label swaps to `ESC` / `EXIT`, same backlit treatment | `CR 1`, digit brightens to `#ffe9a8` | flat, top catch-light |

**State is never signalled by colour alone** — the label line text and the credit digit
both change, both text at high contrast against the red field. That is also how WCAG
1.4.11 is met here: the control is identified by its always-present label, not by the
backlight hue.

## Exact values

**Footprint.** `position: fixed; top: 16px; right: 16px; width: 118px; height: 94px;`
`z-index: 90` (above `.gx-ghost` at 2–3; below `.skip-link` at 100 and `.gx-label` at
300). Grew from the original `100x78` to fit the price line + two-line label + credit
readout without crowding — still corner hardware, not a panel competing with the page.
Small screens (`max-width: 480px`): `top/right: 10px`, plate `92x76`.

**Colour — scoped to this component, not the shared token file.** Defined as CSS
custom properties on `.gx-coin` itself:

```
--coin-bezel:   #101012
--coin-red-hi:  #d81f26
--coin-red-lo:  #38040a
--coin-frame:   #ff4634
--coin-gold:    #e8b545
--coin-glow:    rgba(255, 40, 34, 0.4)
--coin-type:    #fff6ec
```

Never `--amber` (`#ffd54f`) — that stays the page's CTA colour, and reusing it here
would blur the corner back into "third install button." `--coin-gold` stays reserved
for the physical coin (the SVG piece) and the credit digit — a distinctly warmer,
metallic material from the panel's own light. `--coin-frame` and `--coin-type` are new
this pass: the lit inner border and the backlit type respectively, both hot red-orange
rather than gold, because they're light sources, not painted/metal parts.

**Bezel.** `.gx-coin-bezel` — black (`--coin-bezel`), `padding: 6px` (small: `5px`) so
the black frame reads as real material thickness around the lit panel, `border-radius:
5px`. Layered `radial-gradient`s fake four corner screws (small dots near each corner)
plus a faint `repeating-radial-gradient` stipple for case texture, on top of the
original two dome highlights. Depth comes from `box-shadow`: an outer drop shadow
(`0 3px 8px rgba(0,0,0,.55)`) plus two inset edges (`inset 0 1px 0
rgba(233,230,245,.08)` top highlight, `inset 0 -2px 3px rgba(0,0,0,.65)` bottom shadow)
— the plate reads as mounted on the page's dark face, not floating.

**Panel.** `.gx-coin-panel` fills the bezel's padding box, `border-radius: 3px`, flex
row (`slot` + `info`), with a **`1px solid var(--coin-frame)` border** — the lit inner
frame the reference's acrylic edge shows, distinct from the black bezel around it. Fill
is two stacked radial gradients, not one flat one: a top hotspot (`65% 45% at 50% 4%`,
white fading through orange to transparent) simulating the lamp sitting behind the top
of the panel, laid over the base red field (`120% 130% at 50% 16%`, `--coin-red-hi` to
`--coin-red-lo`) — the field is genuinely lit from above and falls off toward the
bottom, not a flat fill. A second hotspot lives on `.gx-coin-panel::after`
(`mix-blend-mode: screen`, `pointer-events: none`) so its opacity can pulse
independently of the frame's `box-shadow` bloom — this is the second half of the
glowing-pulse effect (see Motion). Bloom is still an outer `box-shadow`
(`0 0 10px var(--coin-glow)`, `0 0 20px rgba(255,20,16,.16)` at rest) extending past the
panel's own edge, plus new inset glow (`inset 0 0 0 1px rgba(255,130,100,.35)`,
`inset 0 0 9px rgba(255,40,30,.5)`) around the frame border itself so it visibly emits
light rather than just being a stroked line. Panel depth carries over: `inset 0 1px 0
rgba(255,255,255,.1)` top highlight, `inset 0 -3px 5px rgba(0,0,0,.55)` bottom shadow.

**Slot.** `20px` wide (small: `16px`), `align-self: stretch` with `margin: 6px 0` so it
runs nearly the full panel height — a substantial vertical element occupying the left
quarter to third of the plate, per both references. Fill a near-black vertical gradient
(`#150406` → `#060102` → `#150406`) with an inset shadow for aperture depth, plus an
outer `box-shadow` (`0 0 6px rgba(255,40,30,.45)`) so the slot channel reads as
edge-lit like the frame, not a plain dark cutout. A `.gx-coin-lamp` child lays a warm
red-orange rim highlight along the inner edges (`inset 1px 0 0 rgba(255,120,80,.55)`,
`inset -1px 0 0 rgba(255,70,45,.25)`, plus `inset 0 0 6px rgba(255,40,30,.4)`) — a
static catch-light on the lip, not an animated ember; the backlight (panel bloom) is
what breathes, not the slot.

**Type — backlit, not painted.** This is the pass's main correction: flat gold fill
read as printed type; the reference's type is lit from behind. `.gx-coin-price`
(`25¢`, new): `--font-display` (Silkscreen) **700**, `19px/1` (small: `15px`),
`letter-spacing .01em`, colour `var(--coin-type)` (near-white), with a four-layer
`text-shadow` — a tight white core (`0 0 2px rgba(255,255,255,.95)`) bleeding through
orange (`0 0 7px rgba(255,150,90,.9)`) to red (`0 0 16px rgba(255,60,30,.7)`, `0 0 30px
rgba(255,20,10,.4)`) — the "near-white core bleeding to red-orange" look, because the
light is coming through the letters. `.gx-coin-label-line` (`INSERT COIN` / `TO PLAY`,
was `INSERT` / `COIN`): same treatment scaled down, `8.5px/1.15` (small: `7.5px`),
`letter-spacing .01em`, uppercase, same `--coin-type` colour and a proportionally
smaller four-layer shadow. At this width `INSERT COIN` wraps to two lines inside its
own span, giving three visual lines total (`INSERT` / `COIN` / `TO PLAY`) — an
accidental match to the reference's actual three-line layout, kept rather than forced
onto one line. The double-rule divider from round 1 (a cabinet-reference crossover, not
present on the keychain) is dropped — the primary reference has no rule between price
and label, and removing it gave the type room to be legible at this size.
`.gx-coin-credit`: `--font-mono` (DM Mono), `6.5px/1` (small: `6px`), `letter-spacing
.12em`, uppercase, dim gold; the digit is a `<b>` at weight 500 in full `--coin-gold`,
brightening to `#ffe9a8` when armed — kept as the one gold (not backlit-red) element,
since it's a functional readout, not part of the lit signage.

**Cursor** `pointer`. Hover rules go inside `@media (hover: hover)` so an iOS tap
doesn't leave the hover backlight stuck on.

**The coin** is the original 6×6 inline SVG pixel-circle, now drawn at `8×8`, `--coin-
gold` fill, absolutely positioned over the slot mouth (`left: 50%`, `margin-left: -4px`,
`top: 0`) — the fall itself is the `gx-coin-fall` keyframe animating `translateY(-18px →
0)`, not a static offset, so it visibly drops in from above the plate on firing and
otherwise sits flush with the slot mouth at rest.

## Motion

| Step | Time | Easing (literal) | What moves |
|---|---|---|---|
| Attract pulse | 1700ms, `infinite alternate` (~3.4s full swell-fade cycle) | `ease-in-out` | panel bloom `box-shadow` alpha/radius **and** `.gx-coin-panel::after` hotspot `opacity`, in parallel |
| Rest → hover | 220ms | `cubic-bezier(.25,1,.5,1)` | panel bloom, frame border glow, price/label text-shadow |
| Press depress | 60ms | `linear` | bezel `translateY(1px)` + bevel inversion |
| Coin fall | 200ms | `cubic-bezier(.5,0,.75,0)` | coin `translateY(-18px → 0)`; at 75% `scaleX(.5)` and fade to 0 |
| Panel flash | 90ms in / 260ms out | in `linear`, out `cubic-bezier(.25,1,.5,1)` | panel bloom to peak, back to armed level |
| Credit flip | instant at t=200ms | — | `textContent` 0 → 1 |
| Armed settle | — | — | bloom animation removed (goes steady); `::after` hotspot animation removed, opacity fixed at `.7` |
| Coin-out (Esc / re-click) | 260ms (16ms delay, then the transition) | `cubic-bezier(.25,1,.5,1)` | everything back to rest |

Press → armed totals ~420ms, unchanged from the original build. `var()` is not
substituted for `animation-timing-function`/colour values inside `@keyframes` and fails
silently back to the shorthand curve (`DESIGN.md` §5) — every literal above is written
out in the CSS, not referenced through a custom property, inside `gx-coin-breathe`,
`gx-coin-breathe-glow`, `gx-coin-fall`, and `gx-coin-panel-flash`.

**The pulse is a breath, never a blink — and this pass makes it clearly perceptible.**
Round 1's attract breath was too shallow to register (`box-shadow` alpha swinging
`.3→.5` over 3.2s one-way). The user asked for the pulse explicitly, so this pass
widened the swing substantially (measured: the panel's outer bloom brightness swings
roughly 4–5× between trough and peak, sampled from screenshots at the same page
location across the cycle) and shortened the cycle to land in the 2.5–3.5s
neighbourhood (~3.4s full swell-fade, up from 6.4s). **The one thing protected: the
label text never blinks, in any version of this component.** Only `box-shadow`
alpha/radius and the `::after` hotspot's `opacity` animate — no property that would
make the type appear/disappear is ever touched by `gx-coin-breathe` or
`gx-coin-breathe-glow`. A ~0.5s blinking `INSERT COIN` is the authentic arcade attract
cadence, and it is exactly what makes a control read as a promoted CTA — deliberately
avoided here.

## Copy

| State | Price (fixed) | Label (two lines) | Credit | `aria-label` | `title` |
|---|---|---|---|---|---|
| Rest / hover / press | `25¢` | `INSERT COIN` / `TO PLAY` | `CR 0` | `Insert coin` | `Insert coin (C)` |
| Armed | `25¢` | `ESC` / `EXIT` | `CR 1` | `Return coin and exit the ghost field` | `Return coin (Esc)` |

`25¢` never changes — a real coin machine doesn't reprice itself when armed. Only the
label lines and the credit digit carry the state change, same as round 1.

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
  none` until `.gx-armed`; the coin's own box is `pointer-events: auto` by default (it's
  the one thing that has to be interactive before the field is armed, in order to arm
  it), except where it currently overlaps a real page control — see the yielding note
  below. Cursor is `grab` at rest, `grabbing` while dragged.
- **Lives in its own stacking context, not inside `#gx-field`.** The field paints under
  page content while ambient (`z-index: 0`, vs. `main`'s `1`), so ghosts drift behind
  text — correct for ambient background sprites. The coin element is appended to
  `<body>` instead, `z-index: 50` — always above page content regardless of arm state,
  still under the plate (`90`) and skip-link (`100`) — so it's reachable anywhere on the
  page, before or after arming.
- **The coin yields to whatever page control it's currently over, decided ahead of the
  gesture, never mid-gesture.** A drifting coin can park directly over the install
  buttons or a footer link (the full-bleed field has no reserved gutter). Flipping the
  coin's `pointer-events` *during* `pointerdown` was tried and rejected: by the time a
  pointerdown fires the browser has already resolved its hit-test target, so toggling
  then just breaks both the coin's own click and the control's (the control's `click`
  fires on the nearest common ancestor of the mismatched down/up targets instead of
  either element). Instead, `ghost-field.js` keeps the coin's `pointer-events`
  continuously correct: every animation frame, `updateCoinHitTest()` tests the coin's
  current box against a cache of the page's real interactive controls' rects (`.install-
  row a`, `.install-row button`, `#still-ghostty a`, `.install-grid a`, `.footer-links
  a`, `.footer-icons a`) and sets `pointer-events: none` on the coin when it overlaps
  one, `""` (the CSS default `auto`) otherwise. The rect cache is rebuilt on `resize` and
  `scroll`, since those controls sit in normal document flow while the coin is fixed.
- **Ghosts move above page content once armed — `z-index`, not just `pointer-events`,
  changes.** `#gx-field` jumps from `z-index: 0` to `20` when `.gx-armed` is added (still
  under the coin token's `50` and the plate's `90`, so both stay reachable), and
  `.gx-armed .gx-ghost` sets `pointer-events: auto` on the ghosts inside it. `#gx-field`
  itself stays `pointer-events: none` in both states — only the ghosts opt in — so empty
  field area and any page control not actually covered by a ghost's own box remain
  reachable and selectable. Ghosts covering page text/controls while armed is correct:
  the user is playing a game at that point, and every ghost is grabbable with no dead
  zones, since nothing is intercepting the hit test above them anymore.
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

- **Markup shape (updated again):** `button > span.gx-coin-bezel[aria-hidden] >
  span.gx-coin-panel > (span.gx-coin-slot > span.gx-coin-lamp + svg.gx-coin-piece) +
  (span.gx-coin-info > span.gx-coin-price + (span.gx-coin-label >
  span.gx-coin-label-line × 2) + span.gx-coin-credit)`. `.gx-coin-rule` is gone (see
  Type above); `.gx-coin-price` is new, sits above the label, and is never touched by
  the arm/disarm script. All decorative structure sits under one `aria-hidden="true"`
  on `.gx-coin-bezel`, since the button's own `aria-label` carries the accessible name.
- **The label is still two DOM spans, not one text node**, so `INSERT COIN`/`TO PLAY`
  and `ESC`/`EXIT` can swap independently. The inline script in `v3.html`'s
  `render(armed)` writes `labelLines[0].textContent` / `labelLines[1].textContent`
  instead of a single `.textContent` assignment — unchanged from round 1, only the
  strings it writes changed (`'INSERT'`/`'COIN'` → `'INSERT COIN'`/`'TO PLAY'`).
- **The glowing pulse is two animations sharing one duration, not one.**
  `gx-coin-breathe` (on `.gx-coin-panel`, `box-shadow`) and `gx-coin-breathe-glow` (on
  the new `.gx-coin-panel::after`, `opacity`) both run `1700ms ease-in-out infinite
  alternate` so they read as one coherent breath rather than two independent layers
  drifting out of phase. Both are turned off (`animation: none`) and pinned to a fixed
  value under `.gx-coin-armed` and the hover/focus-visible rules, matching the existing
  pattern from `gx-coin-breathe` alone in round 1.
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

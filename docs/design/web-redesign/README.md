# ghostties.org redesign — design canvas sources

Working files for the design canvas at
<https://claude.ai/code/artifact/7abace9c-8541-4960-ad29-eec5ffb4b593>

Every `*.dc.html` is one artboard. `canvas.json` lays them out and defines the
two pages (Round 2 — Arcade developed; Round 1 — first pass). The published
canvas is regenerated from these files; it is never edited in place.

## Rebuilding the canvas

The two app captures are **not** duplicated here — they live in `web/assets/`.
Copy them in before seeding:

```bash
cd docs/design/web-redesign
cp ../../../web/assets/product-sessions-poster.jpg app-sessions.jpg
cp ../../../web/assets/product-flow-poster.jpg     app-tasks.jpg
```

Then seed and publish with the `/design` skill's helper (`seed-canvas.mjs`),
passing every `--artboard`, both `--image`s and `--canvas canvas.json`.
Publishing must target the existing artifact URL above so the link stays stable.

## Decisions locked so far

- **Direction: Arcade.** D (Long Hallway), E (Manifest), F (Field) retired
  2026-08-19. B (Ghostties OS) retired — its terminal pane was invented content
  presented as the real app.
- **Type: pixel + grotesk.** Silkscreen for display, Archivo for sections and
  prose, DM Mono for commands and block labels. The app itself is SF Pro (UI) +
  SF Mono (terminal), so a sans + mono pairing keeps site and product aligned.
  Written up as a system on `TypeSpec.dc.html` — that board is now the source of
  truth for the ramp, not T1/T2/T3.
- **The game is opt-in and secret.** The page is a page until someone presses
  `I` to insert a coin. Full-screen playfield, WASD and arrows, wrap at the
  edges so there is no lose state.
- **App treatment: B4 scroll-zoom**, with B1 annotated captures for anything
  that does not earn a camera move. B3 clickable replica is cut — it has to be
  re-measured against the app every release or it starts lying.
- **Vendor logos are never drawn.** Collectible tokens ship as generic agent
  glyphs. The `tokenStyle: labelled` dial on `Snake.dc.html` shows named
  placeholder plates *with the trademark warning on the board*; it exists to
  price the idea, not to ship it.
- **House vocabulary:** square status marks, never circles or pills. Block
  labels butted together sharing hairlines. No rounded corners or drop shadows
  on chrome. Uppercase micro-labels at 0.2em tracking.

## Round 3 — the build round (2026-08-19)

Top row of page 1, above everything else:

| Board | What it is |
| --- | --- |
| `CutList.dc.html` | Seven ship, four park, eight cut, each with its reason. A strawman. |
| `Ghosts.dc.html` | The robot pass — five machine faces, an antenna, and a size ladder down to 12px. |
| `TypeSpec.dc.html` | The locked pairing written up as a ramp, plus a conformance box. |

`Snake.dc.html` was rebuilt as v2 in the same round: hero copy pushed below the
playfield, collectible tokens added, five dials exposed, and the app-window peek
cut for room.

## Known drift

**Eight Round 2 boards still load Martian Mono** where the type spec says
Archivo: `Main`, `Anatomy`, `AppAnnotated`, `AppMasks`, `AppReplica`,
`CastOfEight`, `PixelMorph`, `ScrollFocus`. On spec today: `Snake`, `AppZoom`,
`Decrypt`, `TypeGrotesk`, and the three Round 3 boards. Fix each board when it
is next opened — several are cut candidates and not worth a sweep.

## Open

- **Which ghost face.** Five on `Ghosts.dc.html`; also unresolved is whether
  they keep tracking pupils at all, since that is the strongest Pac-Man tell.
- **The cut list itself** is a proposal, not a ruling.
- Real ElevenLabs SFX for the game — parked until the shape is approved.
- Section 08, *first 60 seconds*, does not exist yet and is on the ship list.

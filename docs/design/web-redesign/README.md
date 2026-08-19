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
  prose, DM Mono kept for commands and block labels. The app itself is SF Pro
  (UI) + SF Mono (terminal), so a sans + mono pairing keeps site and product
  aligned.
- **The game is opt-in and secret.** The page is a page until someone presses
  `I` to insert a coin. Full-screen playfield, WASD and arrows, wrap at the
  edges so there is no lose state.
- **House vocabulary:** square status marks, never circles or pills. Block
  labels butted together sharing hairlines. No rounded corners or drop shadows
  on chrome. Uppercase micro-labels at 0.2em tracking.

## Open

- App UI treatment — B4 (scroll-driven zoom into a high-fidelity recreation) is
  the direction; B1/B2/B3 on the canvas are the superseded options.
- Motion language — C1/C2/C3 all rejected. Exploring Grid, Asciify and
  Decrypt-Reveal (canvasui.dev) instead.
- Ghost art — the visor redraw is not settled; robot/agent ghosts to explore.
- Collectible tokens for the game; competitor logos are a trademark risk.

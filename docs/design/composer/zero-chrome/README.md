# Zero-Chrome Composer — design canvas sources

Design-Components artboards for the zero-chrome composer direction (variant 09
of the ten mild→wild composer directions).

Published canvas: https://claude.ai/code/artifact/fbd31813-d56e-4a55-8f7a-3a9dea7239f9

Five pages, laid out by `canvas.json`:

| Page | Artboards | What it answers |
| --- | --- | --- |
| Prior art | `PriorArt`, `Placement` | What the field actually ships, and where the composer should sit |
| Unsolved | `Unsolved` | Ten open details, worst first |
| Flow | `Main`, `Typing`, `Branch`, `Commit`, `Error` | The five states over live terminal output |
| Hints | `HintLadder`, `JobsHandoff`, `Contrast` | What teaches the user, and the legibility cost |
| Motion | `Summon`, `Reveal`, `Exit`, `Timing` | Transition choreography (three artboards animate) |

To edit: change the `.dc.html` files here, re-seed with the `design` skill's
`seed-canvas.mjs`, and republish to the same artifact URL.

Values are lifted from `DESIGN.md` §3/§4 — composer selection `#5B8DEF`, canvas
`#FAF7F3`/`#2D2D2D`, centered-modal 15/13/11pt scale, 12pt radius, 50% ghost grey.
`DESIGN.md` remains the source of truth; these boards are a proposal against it.

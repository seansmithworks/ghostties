# Robot-ghost sprites — exploration

**Status: EXPLORATION ONLY.** Nothing here is wired into the site. No
commitment has been made to ship a robot redesign — this is design
source checked in so it survives a context reset, not a spec.

## Why this exists

The shipped ghost sprite is near-identical to the Pac-Man ghost
silhouette: dome top, twin eye blocks, scalloped tail. The four
trademarked ghost NAMES were already fixed in commit `92a3bb297`. The
SILHOUETTE is the remaining exposure, and that's what this explores —
a set of alternate 12x12 sprites that read as small retro robots
instead.

## Hard constraint

Use only generic retro-robot vocabulary: antenna, visor, rivets,
vents, treads, dome. Do **not** model on recognizable robot characters
(R2-D2, Wall-E, Bender, Johnny 5) — that just trades one trademark
exposure for a worse one. This is a decision, not an oversight.

## The tonal finding

Flat color suits ghosts — vapor has no lit side. Tonal shading suits
metal. `sprites.py` implements a continuous shading algorithm (not
four discrete presets) that lights silhouette edges and, at higher
levels, interior edges too (eye slots, vents, gaps between
legs/treads) without the interior edges reading as a heavy outline at
rest. See the algorithm comment block in `sprites.py` for the exact
math (flood-fill outer/inner edge classification, per-edge weight).

Sean's direction: shading level becomes **dynamic**, not static.

- Rest sits at level **2.4**.
- The ends of the range are events, not steady states: **4.0** =
  deepen/hold, **1.0** = flat "blown out" flash.

**Open question, not decided:** whether 4.0 is a *held* state (e.g.
hover, agent-active) and 1.0 is a *fired spike* (e.g. status change,
arming) — or some other trigger mapping entirely.

## Animation vocabulary per sprite

The vapor tail-wave used on the current ghosts is meaningless on a
robot. Replacement per sprite (shared bob + blink stay across all
nine):

- **flicker** — antenna spark
- **shade** — light sweeps the visor
- **murk** — scanline rolls down the CRT face
- **haze** — rivets pulse
- **specter** — mast beacon blinks
- **wisp** — thruster flicker
- **phantom** — vents cycle
- **ember** — core glows/dims
- **chill** — shimmer across fins

## Renderer note

The live renderer (`ghost-field.js`) currently supports exactly one
flat color per ghost (`PX = 5`, 12x12 grid). Multi-tone shading would
need the glyph set widened beyond the current single fill character —
the COIN renderer in the same file already does this (`o` / `#` / `+`
glyphs mapped to different tones), so the pattern exists there as
precedent if this ever moves past exploration.

## Files

- `sprites.py` — the nine sprite grids + the tonal-shading algorithm.
  Run `python3 sprites.py` to regenerate the preview PNGs
  (`roster_sheet.png`, `level_ramp.png`) next to the script. Needs
  only Pillow.
- `roster_sheet.png` / `level_ramp.png` — generated previews,
  **gitignored** (see `.gitignore` in this directory). Regenerate
  locally rather than pulling them from git history.

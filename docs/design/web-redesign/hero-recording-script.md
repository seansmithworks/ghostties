# Hero film — recording script

Operator runbook for the 14s `ghostties.org` hero. Derived from `hero-storyboard.json`
v2, which stays the spec; this is the take sheet. Tool is **Matte** (window recording,
manually placed zooms).

Two takes, dark and light, identical script and timings. Budget ~20 minutes for both
once prep is done.

---

## Before you press record

1. **Build a dedicated instance.** Never the daily driver — the film must not contain
   real work. Release build, launched fresh.
2. **Fabricated sessions only.** Five in ACTIVE, mixed status colours, no real project
   names, paths, branches, or transcript text. The transcript on the right is texture
   and must never be readable as anything specific.
3. **Window at 1680 × 945 logical**, capture scale 2 (3360 × 1890), 30fps.
4. **Window-scoped capture in Matte.** The desktop must never appear in frame.
5. Do Not Disturb on. Menu-bar clock and any notification surface out of the window
   anyway, but assume nothing.
6. Sidebar in **Sessions** tab, not Projects.

**Correction to the storyboard:** it says the composer opens on ⌘T. It does not.
The composer is **⌘⇧N** (`setupNewTaskComposerShortcut`, `AppDelegate.swift:381`).
⌘T is "New Session" in project-first mode — a different action that will produce the
wrong take. Film ⌘⇧N.

---

## The take

Whole thing is keyboard-only. If your hand reaches for the mouse, the take is dead —
that constraint is the point, not a preference.

| t | Beat | What you do | What must be true |
|---|---|---|---|
| 0.0–2.5 | **Establish** | Nothing. Hands off. | Five rows, five ghost glyphs, mixed colours, all legible. Pointer out of frame. |
| 2.5–5.0 | **Composer opens** | Press **⌘⇧N** | Panel centres, query field focused and empty. |
| 5.0–8.5 | **Type** | Type a few characters, then arrow to a result | Breadcrumb chips resolve project and template as the query narrows. List reorders. No mouse. |
| 8.5–11.5 | **Birth** | Press **Return** | Panel dismisses, a sixth row animates into ACTIVE with its own ghost. |
| 11.5–14.0 | **Settle** | Nothing. Let it rest. | New glyph flips idle → working. Framing matches beat 1 exactly. |

Record the full 14s in one continuous take. Do not cut between beats — the camera
moves are added afterward.

---

## Camera, added in Matte after the take

Easing `cubic-bezier(0.33, 0, 0.15, 1)`. Zoom ceiling **1.35** — above that the
2× capture starts to soften at the hero's 1140px display width.

- **Beat 2:** push from 1.0 to 1.35, pan to `[435, 245]`, over 0.8s. Time it so the
  camera settles as the panel finishes opening — within 100ms of each other.
- **Beat 4:** pull back and left, arriving on the sidebar *before* the new row's
  entrance animation starts. Never during the camera move.
- **Beat 5:** return to 1.0 / `[0,0]`. Must match beat 1 exactly so the rest frame is
  seamless with the poster.

Attention treatment outside the focus region: luminance down 18% over 400ms. Soft,
never a hard vignette edge.

---

## After each take, check before moving on

- New row fully in frame before its animation starts (beat 4) — the most likely retake.
- Camera settle and panel open resolve together (beat 2).
- Final frame is pixel-identical framing to the first.
- No pointer anywhere in 14 seconds.
- No real project name, path, or branch readable at any zoom.

---

## Output

`hero-dark.mp4` and `hero-light.mp4` — H.265 plus an AV1 sibling, poster frame pulled
from beat 1, `preload="none"`.

The page is already wired for this. `web/index.html` holds a live `HERO_VIDEO` constant
pointing at `/assets/hero-dark.mp4` with today's still as the poster, plus a comment
block naming exactly what to re-add: a `<video id="hero-video">` in `.product-frame`,
play-once-on-load, replay on hover or click, poster-only under
`prefers-reduced-motion`. The swap is one path, not a rewrite.

Plays once, then rests on frame 01. **Never loops** — the ambient ghost field owns
continuous motion on that page.

---

## Still open

Beat 5's idle → working flip may happen on its own when a session starts. If it does
not, it is the only beat in the film needing fixture help; everything else is
user-driven. Check it on the first take.

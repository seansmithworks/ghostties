# Ghostties — Backlog

Full history (every dated entry, all completed work, all narrative): `BACKLOG-log.md`.
This file is open items only — no changelog, no findings essays. Prune at `/wrap`.

## Open

- [ ] Per-sprite accent animations (antenna spark, visor sweep, scanline, rivet pulse, mast
  beacon, thruster flicker, vent cycle, core glow, fin shimmer) — spec'd in
  `docs/design/web-redesign/robot-ghosts/README.md`, deliberately out of scope for the
  tonal-shading wire-in (`a96fb453e`). | design | new
- [ ] Coin scale-on-grab — DECIDED 2026-08-26 (Sean): coin STAYS 16x16 (a 33% bigger
  object than the 12x12 ghosts, deliberately), and scales up to ~24x24 equivalent on
  hover/drag. Read as a 1.5x transform on the same 16x16 array, not a re-grid. Motion
  quality is the point — match the ghosts' existing armed-hover behaviour. | build | new
- [ ] Coin hover shine/ripple, unbuilt. Ghosts already have a hover behaviour (3D tilt,
  `scale(1.8)`, only while armed) — a coin ripple should probably match that gate. |
  build | new
- [ ] Coin default size (`COIN_PX` 5, ~92px) is a first-pass number — tune by eye once
  live. | design | new
- [ ] `coin-slot-spec.md` stale against shipped behaviour (carried since 2026-08-23). |
  design | carried
- [ ] Review round 3 on `ef474700f` + `3edfa724b` — never run, carried since 2026-08-23;
  may be moot given later rewrites, re-scope before running. | quality | carried
- [ ] Purge `5215ce015` from public GitHub history — a full-screen capture of a live
  session (real project names, session counts, in-progress conversation text) leaked into
  a committed asset, later replaced (`2165c2f86`) but the blob is still reachable by SHA.
  Not on `main`. Needs Sean: rewrite+force-push / GitHub Support purge / accept and move
  on. | security | needs-Sean
- [ ] `gt` CLI — DECIDED 2026-08-26 (Sean): KEEP in the product, do NOT promote on the
  site. Sean wants to understand it more before it gets marketing. Concretely: the
  `gt-list` section and the +414 lines of `gt` marketing on this branch must NOT carry
  into the v3 cutover. The "Install gt" onboarding button bug in `OnboardingSheet.swift`
  is still open as an app bug. | product | new
- [ ] Public-repo hygiene: `docs/SESSION_NOTES.md`, handoffs, brainstorms, `PR_DRAFTS.md`,
  `BACKLOG.md`/`BACKLOG-log.md` themselves are all publicly readable. Untracking stops new
  leaks, doesn't clear already-public history. | security | needs-Sean
- [ ] Design-system site plan never written (light/dark ramp, type ramp, menus, ghost
  sequences, marketing asset set). | design | new
- [ ] Review `docs/plans/session-creation-unified.html` (36KB) — needs Sean's read + 9
  corrections logged in `reference_command-palette-reuse.md`. | design | new
- [ ] Contrast fix (TEXT ONLY) — wire `DESIGN.md`'s `textSecondary` into code, replacing
  `tertiaryLabelColor` (20 files / 44 occurrences), not a blanket replace. | design | new
- [ ] Wire `HOMEBREW_TAP_TOKEN` PAT — needs Sean to generate a fine-grained PAT from a
  desktop; order matters (token before repo var) or the next release goes red. | build |
  needs-Sean
- [ ] Todo accordion — plan + build, sequenced after other sidebar work. | app | new
- [ ] `ThrottleTrailingEdgeHypothesisTests.swift` — decide or kill (carried 3×+). | app |
  carried
- [ ] PR #120 (session-cache load harness) — decide or kill (carried 3×+). | build |
  carried
- [ ] Screen Recording grant doesn't stick for local Debug builds — likely every rebuild
  re-signs with a fresh cdhash, invalidating the TCC grant. | env | needs-Sean
- [ ] `~/.claude/hooks/scope-guard.sh` never fires — greps for `'^Repo:'` but the card
  writes `'│ Repo:'` with a frame rail; every out-of-scope Write/Edit exits silently.
  Global tooling fix, not this repo. | tooling | new
- [ ] Six named-graph skills unversioned (`batch-ship`, `apply-wave`, `content-cascade`,
  `debug-trace`, `skill-forge`, `case-forge`) — only in `~/.claude/skills/`, not backed up
  in `~/Code/agent-skills`. | ops | new
- [ ] `MEMORY.md` and `ORCHESTRATOR.md` both over their size target — need
  `/orchestrator-route`. | build | new

- [ ] Snake game — DECIDED 2026-08-26 (Sean): the coin unlocks a SNAKE game where you
  collect LLM tokens. `web/assets/snake.js` (22.6K) already has a working engine — grid,
  movement, ghost pursuit, sound, keyboard, a11y announce — but it is referenced ONLY by
  `v2.html`, draws the OLD SVG ghosts (not the new robot sprites), and was built for v2's
  rejected hero-autopilot. Port = re-skin to robot sprites, swap food to tokens, drop
  autopilot. Open inside this: what a token looks like, and what collecting one does
  (score only, or unlocks something). | build | new
- [ ] Six secondary pages stay on old `style.css` — DECIDED 2026-08-26 (Sean): "no for
  now, keep the new site simpler." `download`, `changelog`, `privacy`, `support`,
  `licenses`, `404`. KNOWN CONSEQUENCE, unresolved: v3's footer links to changelog /
  privacy / support, so tapping one leaves the new site and lands on the old one.
  Cheap middle option if that reads badly once live — port only the shell (fonts, colors,
  header, footer), no redesign. | design | new

- [ ] Favicon is still the OLD Pac-Man-shaped ghost — the inline-SVG generator carried over
  from the v1 `index.html` into the v3 cutover (`0ca62754a`) draws the classic rounded-top /
  wavy-bottom ghost with two eyes. Every other ghost on the site was redrawn as a robot in
  `a96fb453e`; this one was missed because it lives in a `<script>` in the head, not in
  `ghost-field.js`. Same IP exposure class Sean just closed. | design | new

## Needs a fresh relevance pass (pre-2026-08-22, likely superseded)

Full detail in `BACKLOG-log.md`. Spans: v3 section-by-section build (review rounds 1-3,
the migration-plan pivot), hero storyboard/Matte recording, session composer palette-reuse
plan, PR #128/#126 follow-ups, beta.22/23 release checks, repo hygiene, the app/UX six-PR
wave, docs refresh. Don't act on any of it without re-checking current `main` and this
branch first — several pivots since (whole-site rebuild → coin-plate → robot-ghost) have
likely already overtaken most of it.

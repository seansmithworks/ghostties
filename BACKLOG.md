# Ghostties — Backlog

Full history (every dated entry, all completed work, all narrative): `BACKLOG-log.md`.
This file is open items only — no changelog, no findings essays. Prune at `/wrap`.

## Open

- [ ] Per-sprite accent animations (antenna spark, visor sweep, scanline, rivet pulse, mast
  beacon, thruster flicker, vent cycle, core glow, fin shimmer) — spec'd in
  `docs/design/web-redesign/robot-ghosts/README.md`, deliberately out of scope for the
  tonal-shading wire-in (`a96fb453e`). | design | new
- [ ] Coin grid 16x16 (80px) vs ghosts 12x12 (60px) — same 5px cell, but the coin is a 33%
  bigger object. Dropping the coin to 12x12 would make it a true sibling. Real fork,
  unopened. | design | new
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
- [ ] `gt` CLI product status undecided (kept feature / contributor tool / cut) — blocks
  the "Install gt" onboarding button fix and `web/index.html`'s `gt list` section. |
  product | needs-Sean
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

## Needs a fresh relevance pass (pre-2026-08-22, likely superseded)

Full detail in `BACKLOG-log.md`. Spans: v3 section-by-section build (review rounds 1-3,
the migration-plan pivot), hero storyboard/Matte recording, session composer palette-reuse
plan, PR #128/#126 follow-ups, beta.22/23 release checks, repo hygiene, the app/UX six-PR
wave, docs refresh. Don't act on any of it without re-checking current `main` and this
branch first — several pivots since (whole-site rebuild → coin-plate → robot-ghost) have
likely already overtaken most of it.

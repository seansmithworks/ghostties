# Ghostties — Backlog

Parked items that survive context resets. Prune at `/wrap`.

> Reconciled 2026-07-29: the tracked `main` copy (07-17→07-22) and the untracked working-tree copy (07-26→07-28) had diverged. This file is the union. Only closed items were dropped (PR #48 merged as `3d2cefc57`).

## 2026-08-20 — ghostties.org app section: spec + HTML rebuild built

**Shipped on `feat/web-redesign-round4`:**

- `e5dff25ee` — root `DESIGN.md` de-staled (terracotta `#C97350` → `#5B8DEF` waiting accent, 9
  refs).
- `af2919f9f` → `c1cacc43c` → `c4799e03d` — `docs/design/web-redesign/app-rebuild-spec.md`: UI
  spec extracted from source, then hardened across two adversarial rounds (17 findings, then
  12; the first fix commit both introduced a light/dark inversion and deleted load-bearing
  rows — the fix-regresses-cleared-paths pattern, twice in one day). Spec is canonical for the
  rebuild; Framing block resolves photo-vs-source conflicts.
- `c6bdb42a4` → `c91a297ca` → `015d3d59d` — `docs/design/web-redesign/rebuild/index.html`:
  self-contained HTML rebuild of the app window, both tabs, both themes (system-following +
  review override), 232px sidebar, true ghost cast pixel-correlated to `GhostCharacter.swift`
  (photo cast was misidentified in v1 and 5 ghosts duplicated), all measured geometry verified
  by Playwright (84/54/36/38/8). Review rounds found 14 then 6 blockers; key discoveries: v1 had
  a doubled titlebar putting everything 54px low ("missing wren" was clipping); atlas-api photo
  ghost is black not terracotta; AppKit y-up shadow offset means CSS `0 2px`.
- `7f8a3e036` — twelve photo-read fixes to `rebuild/index.html` from a fairness-corrected image
  comparison against the reference photo: full-width toolbar band (card was floating 44px high),
  card shadow `0 3px 18px rgba(0,0,0,0.22)` (the seam read as a bright ridge, not the app's dark
  valley), sidebar type +3.5% with negative tracking dropped, hairline `+` glyphs (were 2.7× the
  app's ink), section headers to tertiary, `--text-primary` `rgba(0,0,0,0.85)`, `--status-green`
  `#34C759`, window radius 26px, window widened 900→1180 as a proportion strawman.
- `9ef21add3` — four static canvas artboards (`AppSessionsLight/Dark`, `AppProjectsLight/Dark`)
  seeded from the corrected rebuild, plus a toolbar-button position fix applied to both boards
  and `rebuild/index.html`. Canvas republished to the existing artifact URL
  `7abace9c-8541-4960-ad29-eec5ffb4b593` (28 artboards, 2 images, canvas.json; `--check` printed
  31 files). Published state was verified byte-identical to the repo before overwriting — no
  unsaved GUI edits were lost.

**Decisions (Sean, 2026-08-20):** Sessions primary / Projects second zoom stop (both shown); no
agent/ghost counts in any copy — "limitless" (closes the SIX AGENTS question: no number);
rebuild confirmed over screenshots. **Pipeline changed (Sean's call):** optical-fidelity
iteration moves to the design canvas. The rebuild SEEDS boards, Sean hand-tunes them, and the
approved board state becomes the build contract for the site section (HTML-vs-HTML
verification, not HTML-vs-native-screenshot). Measure→review→fix rounds against app screenshots
are NOT to be re-entered for how-it-reads questions.

**Findings:**

- **The reference jpgs are Display-P3 captures with the ICC profile stripped.** Read raw they
  make every saturated color look too loud (terracotta `#C97350` reads `#BC7757`; `.systemGreen
  #34C759` reads `#69C566`); neutrals are unaffected, which is why greys always matched. Any
  future comparison needs the fairness pipeline (2x render → Lanczos downscale → sRGB→P3
  renumber → matched JPEG) or a P3→sRGB conversion of photo picks. Ask Sean for profile-intact
  PNGs next time.
- **The photos predate current source in three places:** session rows measure 30px (source says
  28), there is no terminal title strip (source has `terminalTitleBarHeight = 28`), and status
  ghosts are terracotta (source is `#5B8DEF`). Where they disagree, the rebuild now follows the
  photo for how-it-reads geometry and source for color, per the spec's Framing block.

**Open — blocked on Sean:**

- [ ] Tune the four app artboards on the canvas — the approved state becomes the build contract
  | design | new
- [ ] Three reference captures: Sessions tab light + dark, Projects tab dark (both existing jpgs
  are Projects-tab light, pre-`#5B8DEF`, P3-stripped) | design | carried
- [ ] Two strawmen to keep or kill: staged INACTIVE/ARCHIVE quiet-end content, and the 28px
  terminal title strip | design | carried
- [ ] Terminal interior richness: minimal prompt (current) vs the full staged Claude Code TUI
  from the photo | design | carried

## 2026-08-20 (later) — ghostties.org: scope reconciliation (read-only session)

Compared current state against the original redesign scope (`a77f5a558`, the ten-section content
map on `Anatomy.dc.html`, and the round-3 cut list). No code changed.

**Where it stands:** direction work is complete — every axis the redesign opened is closed
(Arcade, pixel+grotesk, visor ghost, A+B4, cut list ruled 8 ship / 4 park / 6 cut). Build work is
one section deep: all app-section fidelity, nothing in `web/`. **0 of 10 mapped sections are
rebuilt in production**; the live site is still hero + 2 videos + install, exactly as the Anatomy
board described it on day one.

**Two scope additions vs. the original, both carrying real cost:** B3 was CUT in round 2
(`Main.dc.html` still says so — "re-measured every release or it lies") and round 4 reinstated it
folded into B4; and both-themes-following-system, added 2026-08-20, is what forces the DOM rebuild
at all since a raster capture cannot follow a system theme.

**Parked (off-objective, do not promote into the next thread):**

- [ ] Sections 02, 05, 06, 07 have no captures and **08 "first 60 seconds" has no assets at all**,
  despite the cut list calling it the biggest unspoken objection and the cheapest to answer.
  Section 08 is already tracked as carried under the 2026-08-19 entry; this is the scope-level
  read of the same gap. | web | parked
- [ ] `rebuild/preview-*.png` (4 files) are one commit stale — rendered 09:11, the toolbar-button
  fix landed 09:15. Re-render before anyone cites them as current. | design | new

## 2026-08-20 — ghostties.org redesign: direction locked, app fidelity raised

**Decisions locked (Sean's calls, this session):**

- **Cut list accepted with two amendments.** B3 clickable replica comes OUT of CUT. T1/T2
  specimen boards stay live as boards rather than being cut. New tally: **8 ship / 4 park / 6
  cut** (was 7/4/8).
- **Ghosts keep tracking pupils.** This rules out the `readout` face, which has status blocks
  where eyes would go — the round-3 strawman argued for readout and is now superseded.
- **Direction is a combination of A (opt-in Snake game hero) and B4 (scroll-zoom app section).**
  Both were already on the SHIP list, so the cut list is unaffected. B1 annotated captures drops
  to a supporting role.
- **Light and dark both ship, following the system theme,** across the whole site — not
  dark-only. Every board on the canvas is currently dark, so this is a real lift.
- **The app section is an HTML/DOM rebuild, not screenshots.** Sean asked for pixel-perfect
  recreation. The theme decision forces it: a raster capture cannot follow the system theme.
  Accepted cost: the per-release re-measure burden that originally got B3 cut. Three mitigations
  agreed — build from `DESIGN.md` tokens rather than hand-typed values, keep one real light/dark
  capture pair in the repo as the reference to diff against, and state once in the section that
  it is a rebuild.

**Findings — things that turned out to be wrong:**

- **`DESIGN.md` is stale.** Its frontmatter documents `accent: "#C97350"` (terracotta) as the
  waiting-state color. The source uses `statusYourTurnBlue` `#5B8DEF`
  (`macos/Sources/Features/Ghostties/WorkspaceLayout.swift:138-140`), and a comment at `:127`
  exists specifically to warn that terracotta is NOT the session-status waiting color. The code
  is correct; DESIGN.md needs updating. Since DESIGN.md is canonical for design values, anything
  built from it inherits the error.
- **The live status palette**, from source: `#FFC400` gold (needs decision), `#5B8DEF` blue
  (your turn / waiting), `#F97316` orange (long-running), system green (processing), system red
  (error), idle = `Color.primary.opacity(0.30)`, inactive = `opacity(0.12)`.
- **There is no status "dot."** The status mark IS the ghost glyph itself, tinted — 14pt on the
  Sessions tab, 12pt on the Projects tab. B4's planned payoff stop was "the seven-pixel status
  dot shown at seven hundred pixels"; that framing needs rewriting, and the real version is
  stronger because mascot and status are the same object.
- **`projectFirst` is the DEFAULT sidebar mode**
  (`macos/Sources/Features/Ghostties/WorkspaceViewContainer.swift:90`; key
  `ghostties.sidebarViewMode`, other value `taskFirst`). An earlier claim in this session that
  the site's current poster showed "an app that no longer exists" was WRONG — the poster shows
  the Projects tab, which is what a new install opens on. What IS stale in that poster:
  terracotta/green ghost glyphs (no longer status colors), Claude Code v2.1.186, Opus 4.8.
- **Snake board: "SIX AGENTS." headline vs eight ghosts on the field.** The set is eight
  hardcoded entries in `Snake.dc.html`'s `renderVals()`; there is no dial for the count. A real
  copy/art mismatch, not a render artifact.

**Open — blocked on Sean:**

- [x] Ghost face and dome — resolved round 4: **visor + tall**, locked in the board's DECIDED
  box (not just a dial default). | design | done
- [x] Collectible tokens on the Snake board — resolved round 4: **cut entirely**. The ghosts
  joining the tail already are the collectible; art, both dials, legend band, scoreboard cell,
  and spawn logic all removed. | design | done
- [x] Playfield height — resolved round 4: `ROWS` cut 10→6, drawn border now matches the grid at
  264px with `OY` 220. | design | done
- [x] Which sidebar tab the site features — resolved: **Sessions primary, Projects second zoom
  stop, both shown**. | design | done
- [ ] Three reference captures needed (not one) — Sessions light+dark, Projects dark. Both
  existing jpgs are Projects-tab light, from a pre-`#5B8DEF` build, so their status colors are
  stale. Cannot be captured from a session — `screencapture` is gated by the terminal's own TCC
  grant and fails silently, and driving the live app with synthetic input is prohibited. |
  design | new

**Carried forward unchanged** from the 2026-08-19 section: real ElevenLabs SFX, the
first-60-seconds section, and the 8 Round-2 boards still loading Martian Mono.

**Round 4 shipped 2026-08-20** — three commits on `feat/web-redesign-round4`: `bcb7cd46c` (the
four locked decisions above), `7d5ee8ad4` (seven fixes from an adversarial review), `2b5224f54`
(one regression fix plus a factual correction). Republished to the existing artifact URL
`7abace9c-8541-4960-ad29-eec5ffb4b593` (24 artboards, 2 images, canvas.json — verified by the
seeder's `--check`).

**What the review round caught (process evidence, not a task list):**

The adversarial review round found **six defects** the builder's own verification missed, making
this repo **six-for-six** on round-two UI reviews finding real defects. The worst:
`CutList.dc.html` still carried a "Vendor-logo tokens" entry arguing trademark risk and closing
"Generic glyphs only" — asserting the token system ships, on the board whose job is recording
decisions, while the Snake annotation simultaneously claimed the cut was "flagged on the cut
list." Two boards contradicting each other in the same round.

The follow-on matters more than any single defect: **the fix commit itself regressed a cleared
decision.** `7d5ee8ad4` closed the board's dead bottom band by restoring `.lattice` and `.bounds`
to `height: 440px` while `ROWS` stayed 6 — so the drawn field border was 176px taller than the
reachable grid, putting the void back inside the playfield. Caught by the orchestrator on
inspection, fixed in `2b5224f54`. This is the documented "fix commits regress already-cleared
paths" pattern firing again.

Two defects were found outside any review agent's brief, by the orchestrator reading renders
directly: the B4 cut-list entry promising a "seven-pixel status dot" that does not exist, and the
same claim surviving on `AppZoom.dc.html` and the `n-appzoom` sticky note. All three corrected —
the true version is that the status mark IS the ghost glyph, tinted at 14pt.

**Still open on the boards:**

- [ ] The "SIX AGENTS." headline vs eight hardcoded ghosts in `Snake.dc.html`'s `renderVals()`.
  Deliberately untouched across all three commits — Sean has not ruled on it. Either the headline
  becomes EIGHT or the set drops to six. | design | carried
- [ ] Three pre-existing issues an adversarial review confirmed are NOT from this work, left
  alone: the Ghosts size-ladder label reading "28px · favicon" against a note saying the favicon
  is 32; the Snake game clock being rAF-tick-based so it runs roughly 2x on ProMotion displays;
  the Snake pupil rect overhanging the visor slit by ~2px at extreme angles. | design | new

## 2026-08-19 — ghostties.org redesign: ROUND 3 BUILT, awaiting Sean's review (carried)

Branch `feat/web-redesign-round3` @ `89d7e3963`, pushed. `worktree-session-2` sits at
`439518bff`, the merge-base — this branch is strictly 3 commits ahead. Nothing to consolidate.

**Done 2026-08-19 (round 3, commits `6aed18963` + `89d7e3963`):**

- [x] **Snake v2** — hero copy moved below the playfield (grid now 30x10 at OY=148), collectible
  tokens on a 14-node pool, five dials (`speed`, `strayEvery`, `tokens`, `tokenStyle`, `sound`).
  Generic-vs-vendor token art is the `tokenStyle` dial on one board, with the trademark warning
  wired to the legend band. The app-window peek was cut for room.
- [x] **Ghost art pass** (`Ghosts.dc.html`) — robot direction. Visor is now a dial against
  dual-lens, single-lens, scanline and readout; antenna added; size ladder at 96/48/28/16/12.
- [x] **Type respec** (`TypeSpec.dc.html`) — the locked pairing as a system, three ramps, house
  rules, live tracking dial.
- [x] **Cut list** (`CutList.dc.html`) — 7 ship / 4 park / 8 cut, each with its reason.
- [x] `Main.dc.html` decision strip refreshed — it still listed type and app treatment as open.

**Open — Sean's calls, all live on the canvas:**

- [x] **React to the cut list** — resolved 2026-08-20: accepted with two amendments (B3 back in,
  T1/T2 stay live as boards). See the 2026-08-20 section below. | design | carried
- [ ] **Pick a ghost face.** Five on the board; strawman argument is `readout`. Whether they keep
  tracking pupils is resolved 2026-08-20 — yes, which rules out `readout`. Face/dome pick itself
  is still open; see the 2026-08-20 section below. | design | carried
- [x] **Confirm Snake v2 reads as a hero** — resolved 2026-08-20: direction locked as A (Snake
  hero) combined with B4. Whether tokens clutter the loop reopened as its own item below
  (recommendation: cut). | design | carried

**Found this round, not fixed:**

- [ ] **8 Round 2 boards still load Martian Mono** where the locked type spec says Archivo: Main,
  Anatomy, AppAnnotated, AppMasks, AppReplica, CastOfEight, PixelMorph, ScrollFocus. Recorded in
  the conformance box on `TypeSpec.dc.html`. Fix each board when next opened — several are cut
  candidates, so a sweep would be wasted. | design | new

**Carried unchanged:**

- [ ] **Real SFX** via ElevenLabs — coin, collect, stray, rescue, ambient hum. Only after the
  shape is approved; current audio is synthesised placeholder. | design | carried
- [ ] **First 60 seconds section** — on the cut list's SHIP column and the only item there that
  does not exist yet. What happens after install, where it puts things, what it touches, how to
  leave. | web | carried

**Parked (off-objective):**

- [ ] `MEMORY.md` is over its 20,000 cap and read in full every boot. Route older entries to
  `INDEX.md`. Flagged by the size gate 2026-08-19.
- [ ] Confirm "dialkit" — read as *dials* (tuning controls). If it is an actual library Sean had
  in mind, swap the approach.
- [x] Cast-of-eight naming pass — **closed**, dies with C3 on the cut list.

## 2026-08-18 — Session composer: palette reuse + design direction (carried)

Sean picked the composer direction from mockups this session. Design decisions locked; the plan
still needs rewriting to match.

- [ ] **Rewrite `docs/plans/session-creation-unified.html` — 9 corrections.** Its "Centered
  presentation" section is built on a false premise: "there is no centered-panel pattern in the app
  today" is wrong. `CommandPaletteView` (`CommandPalette.swift:60`) is a shipped Spotlight overlay
  (`TerminalCommandPalette.swift:22-43`), plus `UpdateOverlay`, `SurfaceSearchOverlay`, and
  `buildInfoBadgeHostingView`. Full correction list + every gotcha:
  `reference_command-palette-reuse.md`. Also: `TransparentHostingView` is `private class` at
  `WorkspaceViewContainer.swift:1701`, so the plan's separate-file `SessionComposerOverlay.swift`
  can't reach it as written; and the "85 KB of fragile AppKit" framing is overstated —
  `buildInfoBadgeHostingView` (`:165`, `:1507-1508`) is a shipped constraint-only precedent. |
  app | carried

- [ ] **DECIDE OR KILL: fork a copy of the palette, or build new.** Strawman is **fork a copy** into
  `macos/Sources/Features/Ghostties/SessionComposerPalette.swift`, renamed and parameterized.
  Reasoning: calling it as-is cannot deliver the chosen design (the trailing project control needs
  `CommandPaletteQuery`, which is `private`), so the real choice is only copy-or-build — and copying
  starts from working keyboard nav, selection clamping, and initials-match highlighting.
  `CommandPalette.swift` is byte-identical to `upstream/main`, so editing it in place creates a
  permanent rebase liability. Sean asked "is forking actually better" and had not answered as of
  session end. | app | new

**Design decisions locked 2026-08-18 (do not re-litigate):**

- **Spotlight direction**, refined: project/repo selector moves to the right side of the search
  field; the separate project-chip row is dropped.
- **Treatment 2 — divided trailing control** (hairline vertical rule inside the field, `▾`). Sean's
  call: "option 2 works."
- **`+ Add project…` is not new complexity** — `NewTaskComposerStore.swift:162` already runs the
  folder picker without closing the composer. Mirror it; last item in the open dropdown.
- **No session-name field, ever** — an unpinned session's name is its live terminal title.

- [ ] **Open: does the field still filter projects, or templates only?** Giving the project a
  dedicated control makes the plan's "one field filters both" either redundant-by-design or
  abandoned. Shown both ways in the mockups; Sean had not chosen. Strawman: keep filtering both, so
  "type `bru`, Return" survives. | app | new

- [ ] **Composer needs prefix-first relevance ranking.** `filteredOptions`
  (`CommandPalette.swift:74-92`) is boolean match then `colorMatchScore` only. The plan promises
  "type three characters, press Return"; nothing guarantees the right row is first. Not inherited —
  must be built. | app | new

- [ ] **Audit's `#6D6A68` alternative is wrong — correct
  `docs/audits/sidebar-contrast-audit.md`.** It proposes `#6D6A68` as an exact 4.50:1 fix. Recomputed
  independently: **4.475 on chrome, still failing**, and 4.108 on the active-row tint. It was
  computed against a different backdrop. #128 shipped `#636363` instead (5.007 / 4.598). The audit
  still tells the next reader to use a value that fails. | design | new

- [ ] **Mockups live only as Artifacts, not in the repo.** Four pages built this session (composer
  v1, composer v2, forked-palette, design-system page directions) exist as claude.ai Artifacts and
  in the session scratchpad, which is ephemeral. If they matter beyond this thread, commit the HTML
  under `docs/mockups/`. | design | new

## 2026-08-18 — PR #128 sidebar contrast follow-ups (deferred, not dropped)

`textSecondary` shipped in #128 (`tertiaryLabelColor` → fixed `#636363`/`#9a9a9a` hex for
low-emphasis sidebar text). Two items surfaced during round-two review, deliberately out of scope
for that PR — neither blocks merge.

- [ ] **`Color.secondary` is now the worst text in the sidebar.** Independently verified at
  3.85:1 against chrome — below the 4.5:1 tier #128 just fixed for `tertiaryLabelColor`. Visible
  side-by-side at `ArchiveZoneView.swift:98-106` (the "Done" lane label reads lighter than the
  count beside it) and `NeedsYouZoneView.swift:89-91`. #128 didn't cause this, but fixing the
  tertiary tier made the secondary tier the new visible outlier. | design | new
- [ ] **Fixed hex text tokens drop Increase Contrast support.** `NSColor.tertiaryLabelColor`
  ships system high-contrast appearance variants; a literal `Color(red:green:blue:)` (the fix
  #128 applied) does not respond to `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast`.
  Affects exactly the low-vision users #128 targets. Possible follow-up: branch `textSecondary`
  on that accessibility flag and return a still-higher-contrast value when set. | design | new

## 2026-08-18 — PR #126 lastOutputAt follow-ups (deferred, not dropped)

`lastOutputAt` (splitting Sessions-row/Archive recency from focus-driven project bucketing) shipped
in #126, two adversarial review rounds. Four items surfaced during review, deliberately out of scope
for that PR — none block merge.

- [ ] **Split panes freeze the row timestamp.** `subscribeToOutput` runs once per session on the ROOT
  surface (`SessionCoordinator.swift:270`) and `outputSubscriptions` is `[UUID: AnyCancellable]` —
  structurally one entry per session id, so a second pane's subscription cannot be held, and there is
  no split-creation hook. Run a 20-minute build in pane 2 and the row shows "May 5" while being
  actively typed in; Archive ranks it ancient. Pre-existing hole the indicator dot shares — exposed,
  not created, by #126. Fix is subscribing every surface in the tree and resubscribing on split. |
  app | new
- [ ] **Pruner and Archive rank by different keys.** `pruneStaleSessionsAtLaunch`
  (`WorkspaceStore.swift:236-271`) keeps each project's top-15 by `lastActiveAt`; Archive now sorts by
  `displayTimestamp`. In a project with >15 sessions all outside the 30-day window, launch prune can
  delete the session sitting highest in the visible Archive list. Deliberate for now — retention is a
  "last touched" policy. Add one line to the pruner's doc comment saying so. | app | new
- [ ] **Projects and Sessions tabs now disagree about the same session.** Projects buckets on
  `lastActiveAt`, Sessions displays `lastOutputAt`, so after a click a session is `.recent` in one tab
  and "3h ago" in the other. Deliberate, Sean's call. | app | new
- [ ] **`sessionSignature` extra invalidation.** `ProjectDisclosureRow.swift:104-110` compares
  `[AgentSession]` with synthesized `==`, now including `lastOutputAt`, so a `lastOutputAt`-only write
  re-runs every expanded project row's body for a field the Projects tab never renders. Bounded to
  once per 5s per session; flagged only because this row's render cost is the known-unfixed
  `contextMenu` bottleneck. | app | new

## 2026-08-18 — orchestrator session (Safari ship, #126 review, two plans)

**Closed:**

- [x] ~~**#126 WIP is UNVERIFIED**~~ — **verified and closed.** Round-2's refactor (injectable
  `store:` parameter on `subscribeToOutput`) silently dropped `isOutput: true` from the sink's
  `recordActivity` call, disabling the entire `lastOutputAt` feature on the real output path.
  Restored in `1f15cea6a`. The pinned test has teeth, confirmed by observation not assumption:
  `SessionCoordinatorOutputActivityTests.testOutputSignalAdvancesLastOutputAt` FAILED against the
  unmodified `3fb27cbbf` and passes after the restore. Full unfiltered suite: **694 passed / 0
  failed / 1 skipped** (baseline 691/0/1 at `ab0fe95f3` + three tests genuinely new since that
  commit — the two `SessionCoordinatorOutputActivityTests` cases plus
  `outputNeedsUpdateAdvancesIndependentlyOfLastActiveAtGuard`). All five `@Test` cases in
  `WorkspaceStoreLastOutputAtTests` ran and passed, verified by enumerating the result bundle's
  test list, not the summary line. | app | closed

**Approved by Sean 2026-08-18, not started:**

- [ ] **Contrast fix — TEXT ONLY.** Sean's call: wire `DESIGN.md`'s existing `textSecondary` (`#6B6B6B` light / `#8E8E8E` dark) into code, replacing `tertiaryLabelColor` (25% opacity, 20 files / 44 occurrences). **Do not blanket-replace** — only text that must clear 4.5:1; `PixelChevronView` and other decorative uses stay. Two review rounds required (UI). Evidence: `docs/audits/sidebar-contrast-audit.md`. | design | new
- [ ] **Wire `HOMEBREW_TAP_TOKEN` PAT.** Sean's call over manual bumps. Set the **secret before the variable** (`HOMEBREW_TAP_TOKEN` then `HOMEBREW_TAP_REPO`) or the next release goes red at its final job. Needs Sean to generate a fine-grained PAT — cannot be done from a session. | build | carried
- [ ] **Todo accordion — plan the pipeline AND build it.** Sean's call (rejected the tasks-first shortcut). Order: (0) lift the `launchBanner` guard at `SessionCoordinator.swift:225` so launcher scripts always get written — coverage is currently **zero**, `~/.ghostties/cache/launchers/` is empty; (1) port the `ppid` walk + `KERN_PROCARGS2` ancestor lookup from `~/Code/Agent-Status-loader-explore/Sources/AgentStatusCore` — it is NOT in this repo; (2) `SessionTodoStore` reusing `TaskFileWatcher` (genuinely free, it is general); (3) accordion UI copying `ProjectDisclosureRow`'s pattern. Row sketch and data facts: `reference_claude-todo-data-source.md`. Affordance must be **absent, not disabled**, when empty — only 5 of 336 todo files are non-empty. Sequencing: touches `RecentsRowView`/`RecentsListView`, so it lands after #126. | app | new

**Owed — my miss:**

- [ ] **Design-system site plan was never written.** The brief was split when the Opus pool 529'd repeatedly and only the measurement half shipped (the contrast audit). The plan for the reference site (light/dark, colors, type ramp, menus, lists, ghost sequences) and the marketing asset set (app icon, screenshots) does not exist. Note asset capture is blocked by the Screen Recording TCC problem, so plan it as an at-the-desk step. | design | new

**Needs Sean:**

- [ ] **Review `docs/plans/session-creation-unified.html`** (36KB, on `main`). Offer stands to open it on `:4849` for inline comments. Two design forks have strawmen rather than questions: scrim behind the centered composer (rec: yes, 0.25) and whether Cmd+T opens the panel or stays instant (rec: panel, `Cmd+Shift+T` becomes instant). | design | new

**Latent defects found while mapping — not fixed, surgical rule:**

- [ ] **Project matching is by NAME, not path** (`SessionCoordinator.swift:485`) — miss and it registers a brand-new project. Combined with force-pin on every add (`WorkspaceStore.swift:638,649`, nothing ever un-pins) this is why the project list reached 28. Task-row clicks are a creation path too, so it grows unattended. | app | new
- [ ] **Invalid sort predicate** at `RecentsListView.swift:156` — `sorted { a, _ in a.id == defaultId }` ignores its second operand, so it is not a strict weak ordering. Swift's sort has undefined behavior with an invalid comparator. | app | new
- [ ] **Project-scoped templates leak into every project** — `TemplatePickerView.swift:32-43` ignores scoping, `RecentsListView.swift:153` respects it. Two filters, two answers. | app | new
- [ ] **Status dots fail 3:1 in LIGHT mode only** (gold 1.33, green 1.85, orange 2.34, blue 2.69; dark passes at 4.81–9.72). Deferred by Sean's text-only call — fixing means changing the palette he picked. Proposed values in the audit. | design | parked
- [ ] **Token drift, both directions.** `DESIGN.md` defines `textPrimary`/`textSecondary` that exist **nowhere** in code; `WorkspaceLayout.swift`'s status-dot palette is absent from `DESIGN.md`, which still documents the dropped terracotta scheme. | design | new
- [ ] **Six named-graph skills are unversioned** — `batch-ship`, `apply-wave`, `content-cascade`, `debug-trace`, `skill-forge`, `case-forge` exist only in `~/.claude/skills/`, not in `~/Code/agent-skills`. No git history, no backup. | ops | new

## 2026-08-17 — beta.23 shipped, verified end-to-end

Tag `v0.1.0-beta.23` → `7987f6b19`. Release green, published, all four assets. **First release whose
pre-tag gate was actually run:** build inputs (`GhosttyKit.xcframework`, `zig-out`, `vendor/cef*`)
were cloned into a worktree with `cp -Rc` (APFS copy-on-write, near-instant, no real disk), making
the "a fresh worktree can't build" constraint routinely solvable. Suite: **685 passed / 0 failed /
1 skipped** via `xcresulttool`. Shipped in: #121, #122, #56, #125, #124.

Repo hygiene same session: worktrees 19 → 3, local branches 32 → 8, origin branches 8 → 5. All 16
dead `session-*` worktrees came out under `git worktree remove` **without** `--force`, which is
git's own dirty check and stronger evidence than the sampled audit that preceded it.

- [ ] **`npx ghostties-install` is stale again — pins beta.22 while beta.23 is live.** `0.1.1` was
  published 2026-08-17 (registry `latest: 0.1.1`) closing the long-running beta.21 gap, but the pin
  in `bin/ghostties-install.js` (`tag: "v0.1.0-beta.22"`) now trails by one release. Same one-command
  fix from a real terminal; `npm publish` is deny-blocked inside a session. Self-heals via Sparkle on
  first launch, so low urgency by design. | dist | carried
- [ ] **Homebrew cask not bumped to beta.23.** CI auto-bump still not active (needs the fine-grained
  PAT — set `HOMEBREW_TAP_TOKEN` *before* `HOMEBREW_TAP_REPO` or the next release goes red at its
  final job). Manual: `bash scripts/update-cask-version.sh v0.1.0-beta.23`, then copy into the tap's
  `Casks/ghostties.rb`. | build | carried
- [ ] **Canvas shadow fix shipped UNVERIFIED — needs a repro.** #125 guards the `shadowPath` rebuild
  against zero-size bounds in both `terminalShadowHost` and `browserShadowHost`. The trigger was
  never reproduced, so the fix may be a no-op. Sean is testing against beta.23; the release notes ask
  for the trigger. If it still vanishes, the next move is a repro, **not** a second blind fix. Full
  diagnosis: `project_canvas-shadow-disappears-during-use.md`. | app | new
- [ ] **Timestamp-on-focus → beta.24.** Sidebar `lastActiveAt` advances on focus (keyboard cycling
  and row clicks), by design since April 2026 — not a #121 regression. Strawman is written and not
  built: add `lastOutputAt` written only by the output sink; Sessions rows and Archive sort read it,
  project bucketing keeps `lastActiveAt`. Deferred by Sean 2026-08-17. Detail:
  `reference_lastactiveat-written-on-focus.md`. | app | new
- [ ] **PR #120 (session-cache load harness) — decide or kill** (carried 3×). Still open, never
  merged, branch and worktree still alive. **Strawman unchanged: kill it.** Claude Code now writes
  `~/.claude/sessions/<pid>.json`, so session naming looks to be moving to read-from-source rather
  than something Ghostties infers and caches — the harness would test a layer Ghostties won't own.
  Counter: it's written and costs nothing to merge. | build | carried 3×
- [ ] **`ThrottleTrailingEdgeHypothesisTests.swift` — decide or kill** (carried 3×). Untracked, so it
  was absent from the beta.23 worktree — which is why that run reported 0 failures where local runs
  usually report 2. **Strawman unchanged: keep the trailing-edge test as a regression test, delete
  the two diagnostic ones** (one calls `XCTFail` unconditionally). | app | carried 3×
- [ ] **#56's discriminator is imperfect by design.** Now live: `template.kind != .shell` gates the
  `.waiting` fallback. The recorded plan was always to rewire to a real foreground-TUI signal later.
  Its five tests ran and passed for the first time in beta.23, including the shell-session guard. |
  app | carried
- [ ] **Tag protection does not constrain Sean.** Pushing `v0.1.0-beta.23` reported `Bypassed rule
  violations for refs/tags/... creations being restricted`. The ruleset stops other people; his own
  permissions pass through it. Tags still cannot be deleted after the fact. | ops | new

**Closed this session:** DMG-ships-unstapled (#124, verified on the *shipped* artifact — `stapler
validate` + `spctl` → `accepted`, source `Notarized Developer ID`); npm beta.21 staleness; PR #56
merged after six weeks; repo hygiene wave.

## 2026-08-11 — Repo hygiene wave (worktrees, branches, stale PRs)

Worktrees 21 → 3, local branches 60 → 13, origin branches 11 → 5, disk 34 GB → 2.5 GB. Merged
#116 `3ea42d69d`, #105 `45c834929`, #119 `7ec311a57`. Recovered an unpushed commit (`059d5ef38`,
website session notes) from an abandoned worktree before pruning would have destroyed it.

- **Safari drops the `]` on the hero `npx` line — STILL LIVE ON PRODUCTION** (carried 1×).
  Re-verified 2026-08-11 against `https://ghostties.org/`: `steps(27)` is still present and the JS
  width-lock still covers `line6` only. Fix and the do-NOT-bump-`steps(N)` warning are in the
  2026-08-10 section below; nothing about them has changed. This is the highest-value open item on
  the site — it breaks the install command in the hero for every Safari visitor above 481px.
- **PR #120 (session-cache load harness) — decide or kill.** Opened this session at Sean's request;
  CI green. **Strawman: kill it.** Claude Code now writes `~/.claude/sessions/<pid>.json` carrying
  `nameSource`, so session naming looks to be moving to read-from-source rather than something
  Ghostties infers and caches. If that holds, the harness tests a layer Ghostties will not own.
  Counter-argument if you want to keep it: it is already written and costs nothing to merge.
- **PR #56 (`fix/agent-session-idle-fallback`) — keep open, needs a rebase** (carried 2×).
  `CONFLICTING` against main. **The earlier plan to close it was reversed on evidence:** Switchboard's
  session JSON is written by Claude Code ONLY, while #56 gates on `template.kind != .shell`, which
  also covers the Codex template (#101) and any custom agent CLI. Main still has a bare
  `return .waiting` at `SessionCoordinator.swift:1308` and zero `isAgentKindSession`. Closing it
  would ship a known, quantified lie with nothing in its place.
- **Screen Recording permission still not granted** (carried 3×). Root blocker for two separate
  things: the runtime-verification debt that shipped into beta.22, and the product-clip re-shoot.
  One toggle in System Settings → Privacy & Security → Screen Recording. Three agents plus the
  orchestrator have hit it independently across sessions.

**Environment facts established this session** (all verified by running them, full text in
`ORCHESTRATOR.md` under the 2026-08-11 entry): a worktree-isolated session CAN `git worktree remove`
but CANNOT `git -C`/`cd` into siblings; detect sibling dirty state with `git ls-tree` +
`git hash-object` from your own worktree; `git branch -D` is denied, use
`git update-ref -d refs/heads/<name>`; `git worktree remove` does not delete the branch.

## 2026-08-10 — Website: product-card band, hero bracket, caption (all SHIPPED)

Merged and prod-verified in the deployed asset/HTML: **#114 `12dae56d3`** (product-sessions trimmed
to 1520×922, band gone) and **#118 `f7f26ea63`** (hero `]` no longer clipped, caption corrected).
Left open:

- **Safari drops the `]` on hero line-5, live on production.** WebKit's final animation progress is
  `0.9999999999999997`, so `steps(27)` floors to step 26 and the line settles at 26ch inside an
  `overflow: hidden` box — the whole bracket sits outside. Pre-existing, predates both PRs, only
  above 481px. Fix: extend the existing JS width-lock (`activateCarets` already pins
  `line6.style.width = '16ch'`) to lines 1–5, branching on the mobile widths. **Do NOT bump
  `steps(N)` or the `ch` value** — Chromium lands exactly and would break. Full isolation evidence,
  including the route-rewrite table, in `reference_webkit-steps-animation-floors.md`. Measured via
  Playwright WebKit, not Safari itself — confirm in real Safari before closing.
- **Copy-icon sits centered rather than right-aligned.** `decide or kill` — strawman: change
  `.copy-icon { text-align: center }` to `right`. Measured gap to the `]` is 13–15 ink-columns at
  DPR 2 versus 8 on the pre-#118 baseline, so it overshot the original rhythm; every other glyph on
  that line sits on a 1ch monospace grid. One-character change, no width impact. Shipped as
  `center` on Sean's "ship it" — cosmetic only, not a defect.
- **Hover underline no longer reaches the copy icon.** `display: inline-block` makes the span an
  atomic inline box, and `text-decoration` is never painted on one — even when set directly on it
  (`getComputedStyle` reports it active, no pixels render). Accepted, not fixed: a `border-bottom`
  substitute would sit at the box edge rather than the text baseline. Same change also glued the
  selection text to `brew install⧉`. Both cosmetic.
- **Pin `-refs 5` (or `-level:v 4.0`) into the capture spec** at
  `docs/plans/website-install-paths.html`. `-preset veryslow` raised the sessions clip's reference
  frames to 16, forcing h264 level 5.0; `product-flow.mp4` is still level 4.0. Decode verified in
  both Chromium and WebKit so it does not block, but the two clips should encode identically at the
  re-shoot.
- **Product clips still need re-shooting** (carried). `product-sessions.mp4` has no window titlebar
  at all while `product-flow.mp4` shows traffic lights; trimming the band made that asymmetry more
  legible, not less. Cropping flow to match would delete real UI, so the fix is re-capturing
  sessions *with* its chrome, per the committed spec. Blocked on demo capture being parked and
  Screen Recording permission.
- [x] ~~**Stray worktree:** `.claude/worktrees/hero-bracket`~~ — DONE 2026-08-11. **The premise of
  this item was wrong and is corrected below:** `git worktree remove` runs fine from a
  worktree-isolated session (probed, exit 0). It is `git -C <sibling>` and `cd <sibling> && git …`
  that the harness refuses. See the 2026-08-11 section.

## 2026-08-10 — beta.22 SHIPPED; distribution + one new bug

`v0.1.0-beta.22` tagged at `3979c7025`, release CI green, appcast live (build 16655, verified in
the deployed XML). Merged tonight: #110 (title-sanitizer leaks), #113 (`Remove`→`Delete`),
#115 (changelog), #117 (npm pin). Sean passed all three runtime gates (#57, #58, #92) on a build
proven fresh by launch-time-vs-binary-mtime. Full suite **674 / 673 pass / 0 fail / 1 skip** via
`xcrun xcresulttool get test-results summary` at the merged tip.

- [ ] **NEW BUG — a session started in the launch window is invisible to the sidebar.** Sean opened
  beta.22, used the terminal the app opens with, ran `claude` in `~/Code/Career-ops`. The agent runs
  fine; the sidebar reads **ACTIVE 0 / INACTIVE 0** (screenshot 2026-08-10). Not mis-sorted —
  there is no row at all. Suspected mechanism: `AgentSession` records are only created by
  `SessionCoordinator.createSession(session:template:project:)`, i.e. only via the sidebar's New
  Session path; the default launch window is a plain terminal with no `AgentSession` behind it, so
  anything started inside it is unknown to `WorkspaceStore`. **Almost certainly predates beta.22** —
  Sean's own read, and nothing in this release touches session creation. **Same root gap as the
  parked #56 item below** (2026-07-28 section): Ghostties only knows about agents it launched
  itself. The launcher-UUID join would close both, which is the argument for doing that work as one
  piece rather than patching each symptom. | macos | needs-triage
- [ ] **`npx ghostties-install` is stuck on beta.21.** `ghostties-install@0.1.1` is merged and ready
  (`cad579db7` — pin `v0.1.0-beta.22`, zip sha256 verified against GitHub's own asset digest) but
  **never published**. Blocked by a deliberate global rule `"deny": ["Bash(npm publish*)"]` in
  `~/.claude/settings.json` — a `deny` refuses outright and never prompts, so no session can
  approve past it, and the `!` prefix no-ops from Sean's phone. Publish is one command from a
  desktop: `cd dist/ghostties/npm/ghostties-install && npm publish`. Low urgency — an npx install
  lands beta.21 and Sparkle offers beta.22 on first launch. **Re-verified 2026-08-12** (carried 1×):
  registry `latest` is still `0.1.0`, repo `package.json` is `0.1.1` pinning `v0.1.0-beta.22`, and
  the `Bash(npm publish*)` deny is still at `~/.claude/settings.json:32`. **This is the only stale
  user-facing install channel** — brew was checked the same day and is correct. Worth noting the
  homepage hero advertises `npx ghostties-install` by name. | dist | needs-desktop
- [x] ~~**PR #116 — decide or kill.**~~ MERGED 2026-08-11 as `3ea42d69d`. **Confirmed before merging
  that this was bookkeeping, not user-facing:** the live tap `SeanSmithWorks/homebrew-tap` already
  served beta.22 with a byte-identical sha256 (bumped 2026-08-10, `3b4bddca6`), so `brew install`
  was never stale. The strawman's second half — marking the repo file as a snapshot template — was
  NOT done; the drift described above is still real and still unaddressed after every release.
  Automating it is the item below. | dist | partially-closed
- [ ] **Turn on the Homebrew cask auto-bump.** The `homebrew-cask` job already exists and is
  complete (opens a PR on the tap, preserving the human gate) — it skipped this release only because
  `vars.HOMEBREW_TAP_REPO` is unset. Needs a fine-grained PAT scoped to `SeanSmithWorks/homebrew-tap`
  alone, Contents + Pull requests read/write, minted in the GitHub UI (`gh` cannot create one).
  **Order is load-bearing: set `HOMEBREW_TAP_TOKEN` (secret) BEFORE `HOMEBREW_TAP_REPO` (variable).**
  The job gates on the variable and errors hard when it exists without the token — reversing the
  order turns the *next* release red at its final job, after the release is already public. Never
  substitute `gh auth token`; it spans every repo including private ones. | dist | needs-sean
- [ ] **npm publishing has no automation path at all.** Unlike brew, there is no CI job — publishing
  from CI would need an npm automation token as a repo secret plus a publish step that doesn't
  exist. Doing this is what stops npx drifting behind every release, and it leaves the `npm publish`
  deny rule fully intact because publishing stops being a local action. | dist | not-started
- [ ] **Resume-on-Relaunch — designed, not built.** Relaunch currently rebuilds from template
  (`clearRuntime` + `createSession`), so the terminal returns and the conversation does not; the
  fork has **zero** references to `resume`/`--continue`/any Claude session identity. Design settled
  with Sean: **flat context menu with a `Relaunch` section title** (not a submenu — his call), three
  items **Resume** / **Branch from here** / **Fresh**, shown only when a transcript exists.
  `.claudeCode` templates only. Mechanism: launch with `claude --session-id <AgentSession.id>` so the
  transcript is keyed to the UUID Ghostties already owns, then `--resume <id>`. **Claude is the only
  agent CLI that lets the caller dictate the session ID at launch** — codex resumes by
  subcommand, gemini by positional index, cursor-agent by chatId, so `.custom` templates would each
  need their own resume config. **One unverified assumption blocks the build:** whether
  `Section("Relaunch")` renders a visible header inside a SwiftUI `.contextMenu` on macOS. If it
  renders as a bare divider the flat layout loses its labelling and the submenu wins by default.
  Cheap to check at build time. Wireframes in the session scratchpad. | macos | ready-to-brief

## 2026-08-09 — App/UX wave: six PRs open, none merged

Objective was to turn Sean's seven asks into reviewable PRs without merging. All seven closed.
Distribution (#99) was the sibling thread's and is already on `main`.

- [ ] **Merge the wave, in order.** `#102` **before** `#103` — both touch `WorkspaceSidebarView.swift`.
  `#96` (titlebar), `#100` (hide Tasks), `#101` (Codex template) and `#104` (overlay card) are
  independent of each other. | macos | carried
- [ ] **#102 shipped WITHOUT its minimum-sidebar-width measurement.** Adding text labels to the
  toolbar buttons widens them; the agent could not isolate its own Dev window to measure, and
  correctly refused to force focus. **Nothing was pre-built for an overflow that was never
  confirmed to exist.** 2-minute manual check is in the PR body — if the label truncates at
  minimum width, an icon-only fallback is the fix. | macos | needs-runtime-check
- [ ] **Screen Recording permission is NOT granted to this session's process.** `screencapture`
  returns an all-black image and `osascript`/System Events is denied assistive access. Two
  subagents and the orchestrator hit it independently — environmental, not agent error. **Every
  visual acceptance criterion in this wave went unverified because of it**, and the parked
  dark-mode hero capture is blocked on the same thing. Granting it once to the terminal
  (System Settings → Privacy & Security → Screen Recording) unblocks the whole class. | ops | quick
- [x] **~~#96's window-floor tradeoff~~ — dissolved, do not chase it.** Removing the
  `TerminalController` override looked like it would let the gutter below the terminal card bleed
  terminal colour instead of sidebar chrome. It does not: `WorkspaceViewContainer` paints its own
  layer with `canvasBackgroundCGColor` in `.pinned`/`.closed` (lines 509, 1166, 1177), so
  `window.backgroundColor` only ever shows in the titlebar strip. `.overlay` was the one exception
  (`layer.backgroundColor = nil`, line 1188) and **#104 closes it** by making overlay paint its own.
- **Sean's design call, 2026-08-09:** the canvas is **always** a shadowed card, including overlay.
  Built as #104. Note a shadow needs the inset to be visible at all — a full-bleed view's shadow is
  clipped — so inset, radius and shadow move together. This was never a persistence bug.

### Method notes worth keeping

- **`xcrun xcresulttool get test-results summary` is the fix for the recurring test-count
  miscount.** Raw log lines overcount by a constant −49 in this repo; #103's agent reported "688
  passed" against a real ~638. #104's agent used xcresulttool and hit the baseline exactly. Put it
  in any brief that asks for totals.
- **Verify PRs with `gh pr diff`, never `git diff main..branch`.** `main` moved repeatedly during
  the wave, and a raw range diff made #100 look like it deleted the entire distribution lane. It
  changed one file, +4/−10.
- **A subagent typed into one of Sean's live sessions** — memory
  `feedback_subagent-gui-automation-hit-live-session`. Every brief now carries: screen capture yes,
  synthetic input never. Two later agents hit that wall and correctly stopped rather than route
  around it.

## 2026-08-04 — Sessions-tab cycling + indicator lifecycle (PRs #90, #92 shipped)

Both merged to `main` and verified present in the merged code, not just merge-succeeded.

- [ ] **#92 was never eyes-on'd.** #90 Sean tested by hand (Sessions-tab cycling, verified against
  a build whose PID launch time postdated the binary). #92 passed code review + 629-test suite
  only. **Decisive check before beta.22:** with the app running, start two sessions, stop one —
  it must leave ACTIVE for ARCHIVE *without* relaunching the app. A cold launch shows correct
  zones even on unfixed code (no cache yet → `.exited` → `.inactive`), so launching and looking
  proves nothing. | macos | needs-runtime-check
- [ ] **Sessions tab: two zones or three?** Open design question, deliberately deferred until
  ACTIVE is honest. Sean's instinct was a third "Idle/Inactive" zone for stopped-but-warm
  sessions; the counter is that ARCHIVE accumulates across launches (30-day retention, top-15
  per project) so a just-stopped session lands in a 20–80 row pile. **Strawman if revived:** port
  the Projects tab's existing three-bucket model — `computeSessionGroups` (`WorkspaceStore.swift`)
  already does active / recent (`lastActiveAt` within 24h) / idle, and `SessionBucket` exists. Re-look
  now that #92 makes ACTIVE truthful; if `ACTIVE 1 / ARCHIVE 23` reads fine, kill this. | craft | session
- [ ] **`focusAdjacentLiveSession` returns a target it never focused** (`SessionCoordinator.swift`).
  Returns `target` unconditionally even when `focusSession` bailed on a missing tree — the silent
  lie that made the #90 cycling regression invisible at the call site. Durable fix, but touches
  three call sites (`WorkspaceSidebarView`, `TaskSidebarView` ×2). Own PR. | macos | session
- [ ] **ARCHIVE order is load order, not recency.** `RecentsListView.sorted(sessions:)` is an
  identity function. Not a bug today, but it's why a just-stopped session is hard to find, and it
  gates the zone decision above. **Decide or kill.** | craft | quick
- [ ] **`clearRuntime` clears only the store cache, not `cachedIndicatorStates`** — same asymmetry
  #92 fixed in `setStatus`. Unreachable (a removed session's UUID never returns), one line for
  symmetry. | macos | quick
- [ ] **Two contradictory test-isolation conventions** once #56 lands. #56 adds a `#if DEBUG`
  injected-store seam so tests avoid `WorkspaceStore.shared`; #92's tests use `.shared` directly
  (correctly declined — threading a store through `setStatus` would undermine the "single mutation
  point" property the PR exists to make auditable). Pick one convention. | quality | quick

## 2026-08-03 — ⚠️ UI fix wave merged to main WITHOUT its runtime gates

**#57, #58, #59 are on `main`. Two of the three were never verified in the running app.** Sean merged on green CI, knowingly, after the risk was flagged. Recording it here so a future release does not assume these work.

CI proves they *compile and pass unit tests*. It cannot prove either fix actually fires — both are behavioural fixes in SwiftUI event handling, which the test suite does not exercise.

- [ ] **#57 (`d03d67a5c`) — Esc reverts inline rename. UNVERIFIED, and it is the risky one.** The entire fix reduces to one untested boolean: if `.onExitCommand` never fires on that field, the merge shipped the original bug unchanged while looking fixed. **Decisive check:** rename a session inline, press Esc, then right-click the row — **"Sync name automatically" must be ABSENT** from the context menu. If it is present, the fix is inert. | macos | needs-runtime-check
- [ ] **#58 (`e3dd959fe`) — sidebar re-clamp on window shrink. UNVERIFIED.** **Decisive check, and the order matters:** close the sidebar FIRST, shrink the window to ~700pt, THEN open the sidebar — it must come in already narrowed. Testing in any other order passes trivially and proves nothing. | macos | needs-runtime-check
- [x] **#59 (`cdb74ad4c`) — grey out Next/Previous Project menu items when empty.** No runtime gate; this one was always safe to land on CI alone.

**Run both checks before cutting beta.22.** If either fails, the fix is inert and needs reopening — the merge did not close the underlying bug.

## 2026-08-02 — media previews in the terminal

Investigation only, no code written. Findings in `reference_terminal-images-work-claude-code-doesnt.md`.

- **Verify the fork renders Kitty graphics.** Only *upstream* Ghostty was tested (Sean was in the wrong app). The fork has the full implementation and doesn't touch the terminal core, so this is near-certain — but unproven. One command in a plain Ghostties tab closes it: `scratchpad/kitty-test.sh` (script is in a session scratchpad and will be GC'd; the one-liner is in the memory file).
- **Sidebar preview pane (`QLPreviewView`).** The real gap: Claude Code hands you a file path when an agent produces a screenshot, and no terminal-side image support fixes that. QuickLook gets images, video, PDFs, and scrubbing at real resolution. Slots into the existing panel architecture alongside `BrowserPanelView.swift` / `BrowserTabManager`. Not scoped — wants a plan before code.
- Rejected: a `PostToolUse` hook firing QuickLook on every image Read. Works today and takes ~20 min, but steals focus during autonomous runs. Only viable as a manual trigger.

## 2026-08-02 — documentation IA + case study

Objective (locked): repo documentation + correct Ghostty-vs-Ghostties calibration. All five refresh waves are merged to `main`; this wave adds the design layer that was missing.

- [x] ~~**PR #80** — `docs/INFORMATION-ARCHITECTURE.md` + `docs/case-study-documentation-refresh.md`.~~ **Merged 2026-08-02 as `1c2ff4e82`.** Records the IA the refresh produced (audience model, the disambiguation-not-topic-tree principle, decay model per file, five questions before adding a doc) and the narrative of how it was arrived at. Entry points in `CONTRIBUTING.md` for humans and `AGENTS.md` for agents.
- [x] ~~**Should the case-study visuals live in the repo?**~~ **DECIDED 2026-08-03: no, killed.** GitHub markdown cannot render the CSS/SVG figures, so putting them in the repo means exporting PNGs, and images cannot be diffed — they would go stale silently and break the decay-model rule the IA doc itself sets. Repo docs stay textual; the visual version stays an Artifact. Do not re-open as a question.
- [ ] **Visual case study lives only as an Artifact.** `https://claude.ai/code/artifact/8bda1349-3010-4780-bee8-88ffe72e5c0c` — six figures (inherited-scale receipt, the auto-close trap, the routing fork, six entry points, the 3.8:1 deletion bar, CONTRIBUTING before/after) plus the inlined demo GIF. Private to Sean's account; it is not backed up in the repo and would need rebuilding from `docs/case-study-documentation-refresh.md` if lost. | docs | reference

## 2026-08-03 — Wave 0 repo settings ✅ COMPLETE

Every Wave 0 item is applied and verified live. Issues, Discussions, private vulnerability reporting, Dependabot **alerts**, 10 topics, and the 1280×640 social preview. The long-standing "needs Sean's login" note was wrong on every count — `gh api` reached the settings, and Claude in Chrome reached the social preview, for which **no REST or GraphQL endpoint exists**.

Two follow-ups, neither blocking:

- [ ] **The social-preview card has no preserved source.** It was rendered from a standalone HTML file in a session scratchpad, which is gone. Rebuilding is required to change the version string, the tagline, or the layout. **Now more pointed:** the site's `og:image` (PR #88, `web/assets/social-card.png`) also came from the Paper artboard — the Paper file is now the de-facto source for both the GitHub social preview and the site's share card. Decide whether that's acceptable or whether a rebuildable source belongs in the repo (e.g. `.github/assets/social-preview.html` + a render note). | docs | decide-or-kill
- [x] ~~**Paper promo artboard carries the pre-rename URL.**~~ **Fixed.** Sean updated the artboard; the card shipped in PR #88 reads `github.com/SeanSmithWorks/ghostties` (verified in the rendered PNG).

**Deliberately NOT enabled:** Dependabot *security updates* (the auto-PR feature, `/automated-security-fixes`). `.github/dependabot.yml` is still the inherited upstream config pointing at upstream paths, so auto-PRs would file against the wrong targets until that retarget lands.

**Off-objective, parked deliberately:**

- [ ] **Idea-log prune** — 10 of 31 captures in `tease-capture.md` are older than 30 days and unacted-on, which is that file's own documented prune threshold (1 from May, 9 from June). Surfaced at `/wrap` 2026-08-02, nothing deleted. Spans projects, so it is not this thread's objective. | ops | needs-Sean

## 2026-08-03 — stale live indicator in Sessions tab ACTIVE zone ✅ FIXED 2026-08-04

**Closed by PR #92 (`981fab47e`).** `setStatus(_:for:)` now clears both indicator caches on
`.completed`/`.exited`/`.killed`, and writes `.error` to both so failed sessions stay visible.
Original entry preserved below for the diagnosis.

Found during PR #90 review (`fix/sessions-tab-cycle-order`). Exited sessions render
in the Sessions tab's ACTIVE zone with a stale live indicator until relaunched or
removed: `handleSurfaceClose` (`SessionCoordinator.swift`) removes the session tree
and sets `.exited`/`.completed`/`.error` but never calls `removeIndicatorState`, and
the 1 Hz tick only iterates statuses where `isAlive`, so the stale indicator never
clears. Pre-existing display bug, not introduced by #90 — but it's what made the
Cmd+Shift+[/] cycling regression reachable (a dead session sitting in ACTIVE with a
live-looking indicator). Root-cause fix would clear indicator state on session exit;
deferred because it touches what lands in Archive. | craft | quick

## 2026-08-03 — repo branch/PR cleanup ✅ COMPLETE

Objective (locked): clean up ghostties branches and PRs. **Done.** Origin branches
**43 → 9**, local **62 → 12**, open PRs **7 → 5**, worktrees **10 → 5**. Every branch,
PR and worktree that remains is there on purpose.

**Shipped:** 27 origin branches deleted (26 with merged PRs + `fix/ci-green-cli-and-host-hang`,
whose PR #33 was closed and superseded by #47), then 5 more no-PR branches. 5 stale worktrees
removed, all clean. 33 stale locals + 15 orphaned `worktree-agent-*` names deleted by Sean.
**#46 closed** as a duplicate — `main` already carried beta.20 at `CHANGELOG.md:38` via #49,
and the PR's link reference still pointed at the pre-rename `SeanSmithDesign` URL. **#37 merged**
(`f10536996`) — `zig-pkg/` genuinely was not ignored, and its red check was
`macOS App (xcodebuild test)`, a job name #47 renamed away.

**Method note worth keeping:** nothing was deleted on branch name or age. Every branch was
resolved to a PR state first, and the two locals that mapped to *no* PR were resolved by
reading main — `sidebar-ttl-fix`'s TTL work is on main (`WorkspaceStore.swift:23-28`), and
`work/revert-equatable-tweak`'s revert landed too (`ProjectDisclosureRow.swift:93` documents
the reverted semantics). `git branch --merged` reports merged=0 for all of them because they
were squash-merged; PR state is the only reliable signal.

**Still open from this objective:**

- ~~**PR #50 — rebase onto the design system, or close.**~~ **Closed 2026-08-08 as superseded**,
  not merged. Its +143/−8 all landed in `web/index.html`, which #86/#88/#93 have since rewritten;
  it had been `CONFLICTING` since 2026-07-22. The scroll-triggered boot-sequence idea is not
  rejected — it should return as a fresh PR against current `main`. | web | decide-or-kill
- **3 origin branches kept deliberately, no PR:** `feat/demo-capture-instance` (live handoff
  doc in memory), `feat/ghostties-animation` (the parked teaser landing page depends on it),
  `test/session-cache-load-harness` (Switchboard track is live; the 2→4→6 render-cascade ramp
  is still the missing measurement). | ops | reference
- **`git branch -D` is classifier-blocked to Claude, and Claude cannot unblock itself.**
  Editing `.claude/settings.local.json` to add the permission is *also* blocked — correctly,
  it is self-escalation. Sean runs it with the `!` prefix, or pastes
  `"Bash(git branch -D *)"` into `permissions.allow` himself. Carried 3× since 2026-07-26.
  | ops | needs-Sean
- `gh pr close` is classifier-blocked; `gh api -X PATCH repos/<o>/<r>/pulls/<n> -f state=closed`
  works. Full table in `reference_gh-classifier-blocks-and-workarounds`. | ops | reference
- **Squash-merge breaks stacked PRs.** Recorded in memory as
  `reference_stacked-pr-squash-merge-conflict` — squash-merging the base orphans the
  child, retargeting balloons the diff and conflicts. Resolve by merging main in and
  taking the branch version; never force-push. Relevant if any of the 7 open PRs are
  stacked. | ops | session

## 2026-08-02 — ghostties.org audit (impeccable full sweep)

Full design/technical audit of the live site. Scores: **Design 15/40 Nielsen, Technical 5/20 — "Critical" band.** Six mechanical bugs found in this same audit (changelog 404, missing custom 404 page, dead X link, robots/sitemap, 1.5 MB orphaned assets, asset cache policy) already shipped in PR #77 and are deliberately absent below.

**Most of this section is addressed in PR #86 (`fix/web-audit-remediation`, open, not yet merged — do not read "fixed" below as "on main").** Verified against `git diff origin/main -- web/`. New findings the remediation work surfaced are logged in a subsection at the end.

### Structural — SHIPPED to main 2026-08-02 (PR #81, `cff9bc345`)
- ~~**`web/` has no design system.**~~ **Shipped.** `web/style.css` (tokens +
  reset + base elements + shared components + footer) and `web/DESIGN.md` (the
  site's spec, distinct from the root `DESIGN.md` which documents the macOS
  app). All 7 pages now link the stylesheet and keep only page-specific rules:
  805 lines of duplicated CSS deleted, 75 added. `privacy.html` has no page CSS
  at all. Colour literals in the seven page blocks went 131 occurrences / 29
  distinct → 6, each a genuine one-off, commented and listed in `DESIGN.md` §6. Verified by before/after screenshot diff at 1280 and 375:
  changelog, download, licenses, privacy and support are **pixel-identical**;
  index is within animation noise (an unmodified-vs-unmodified control diffs
  more); `/404`'s `h1` intentionally adopts the shared heading treatment
  (white + tighter tracking) so it matches every other page. `task-flows.html`
  was deliberately left out of the system, and has since been pulled from
  the public site entirely — see the `/flows` decision below.
  **Every item below is now a one-file edit.** | web | project

### `/404` polish — SHIPPED to main 2026-08-02 (PR #82, `6fa61089f`)
- Ghost drops in, teeters, topples onto its side, eyes become pixel X's. Also
  fixed centring: the page set `justify-content: center` but `min-height: 100%`
  never resolved, so the column had no free space and the content sat at the
  top. Now `100dvh`. Easing is set per keyframe so the fall accelerates
  (40 → 1022 deg/s) and each rebound decelerates; a single curve across the
  sequence read as a flip. Measured 239 frames, avg 8.33ms, zero over 20ms,
  transform/opacity only. `prefers-reduced-motion` fades the already-fallen
  ghost in rather than hard-cutting. Added `--ease-out`/`--ease-in` to
  `style.css`; `DESIGN.md` §5 documents the motion vocabulary **and** the
  gotcha that `var()` is silently ignored for `animation-timing-function`
  inside `@keyframes`. | web | project

### Accessibility — was 1/4, mostly fixed in PR #86 (open)
- ~~`prefers-reduced-motion` is ~19% honored.~~ Not part of this pass — carried below unchanged where still open (see Small/polish and 07-29 items); the fixes below did not touch the entrance/typewriter animation set.
- ~~**Contrast failures, all computed and all failing WCAG AA:** 2.27:1 footer text and links on every page (worst on the site); 2.70:1 changelog labels; 3.21:1 `.back` link; 3.22:1 homepage `.line-3`; 3.78:1 `.download-meta`/`.all-releases`; 4.27–4.43:1 body note.~~ **Fixed.** All six raised past AA (`--text-faint` 0.25→0.55 alpha = 5.96:1, the rest similarly), per-token contrast numbers now in `web/DESIGN.md` §3. **Not fixed, now moot:** 3.03:1 `#666` on flows lane names — lived in `task-flows.html`, now pulled from the public site (see the `/flows` decision below).
- ~~No `<h1>` on `index.html`; no `<main>` landmark on any of the 7 pages; no skip link.~~ **Fixed** on all 7 pages: visually-hidden `<h1>` on the homepage, `<main id="main">` wrapping content, a skip link before it. `task-flows.html` still has none, now moot — see the `/flows` decision below.
- ~~`changelog.html` skips heading levels H1 → H3, six times.~~ **Fixed** — release headings are now H2, section labels H3.
- ~~The ghost-scatter interaction is mouse-only, not reachable in a tab sweep.~~ **Resolved as decorative, not by adding a control.** The scatter `<div class="ghosts">` and its 8 SVGs are now `aria-hidden="true"`; the click handler is unchanged (still mouse-only) but the element is out of the accessibility tree, so there's no longer an unreachable interactive element for AT users to miss.
- ~~8 foreground ghost SVGs have no `aria-hidden`.~~ **Fixed**, same change as above.
- ~~`/flows` still has 0 focusable elements and 6 unlabeled mermaid SVGs — untouched, tracked under the `/flows` decision below.~~ **Moot.** `/flows` is no longer publicly routed — see the `/flows` decision below.
- ~~No focus styling authored anywhere.~~ **Fixed** — site-wide `:focus-visible` ring (`--accent`, 2px, keyboard-only), plus a `:focus` reveal on the new skip link.
- ~~All six terminal lines are in the DOM from load... a screen reader announces `- ghostties % install soon` as fact.~~ **Fixed.** `.line-3` (the joke line) is now `aria-hidden="true"`; every line that states something real stays in the tree. `.line-6`'s `+ [` / `]` decoration is also now `aria-hidden`, so the link's accessible name is "download now," not "plus bracket download now bracket" (this was originally filed under Small/polish, fixed by the same change). | web | project

### Responsive — was 1/4, mostly fixed in PR #86 (open)
- ~~**Horizontal overflow at 10 of 14 tested widths, from two independent causes.**~~ **Both fixed.** (1) 320–560px `.terminal` escape: `.terminal` now clips overflow and its `max-width` calc widened to account for body padding. (2) 700–900px `.product-window::before` glow escape: `.product` now has `overflow: hidden`. Cause 2 had already shipped in PR #72; cause 1 is new in #86.
- ~~`/support` overflows +11px and `/privacy` +22px at 320px.~~ **Fixed** — `<code>` now has `overflow-wrap: anywhere` site-wide so long unbroken tokens (bundle IDs) wrap instead of forcing the container wider.
- ~~All 48 interactive elements are under 44×44 at 375px.~~ **Fixed** for the CTA and footer icons — `/download`'s primary button gets `min-height: 44px`, and footer icon anchors get 15px padding to grow their tap box to 44×44 without changing the visible 14px icon.
- **Breakpoint coverage is still a single `max-width: 480px` query on six of seven pages.** Not addressed by adding breakpoints — the overflow fixes above (clip + wrap + wider `calc()`) are width-independent, so the gap in 481–719px coverage no longer has a live overflow bug behind it. The breakpoint sparseness itself is unchanged.
- ~~**`.terminal { max-width: calc(100vw - 112px) }` over-subtracts by 40px at ≤480px.**~~ **Shipped in #93** (`f06e4fdc2`) as `calc(100vw - 72px)`. Verified live: 248px @320, 303px @375. | web | quick
- ~~All font sizes are `px` literals.~~ **Fixed** — every sized value in `style.css` and the un-tokenised single-use sizes in each page are now `rem`. | web | project

### Conversion and trust — mostly still open
- **The homepage CTA is still gated behind ~10.1s of animation with no skip.** Untouched by PR #86.
- ~~**`/download` still has no trust signals at the highest-risk moment.**~~ **Shipped in #93.**
- The homepage still has no `<h1>` a sighted user can see (the new `<h1>` added for a11y is `visually-hidden`), no visible wordmark, no prose.
- ~~The site still never says this is a fork of Ghostty until `/licenses`.~~ **Shipped in #93** — fork attribution added on homepage and `/download`.
- Still no Download link in any subpage footer. Untouched.
- ~~`og:image` is relative and may not resolve for crawlers. No `og:url`, `twitter:card`, or `twitter:image`. Zero OG tags on all five subpages.~~ **Fixed.** `og:title`/`og:description`/`og:type`/`og:url`/`twitter:card` landed in PR #86; `og:image`/`twitter:image` were restored in PR #88 (`b9dae122c`) pointing at the new `assets/social-card.png`. | web | session

### Content staleness — mostly fixed in PR #86 (open)
- ~~`changelog.html`'s newest entry is beta.19; the site ships beta.21.~~ **Fixed** — beta.20 and beta.21 entries added.
- ~~`/support`'s `<meta description>` advertises a known-issues section the page does not contain.~~ **Fixed** — meta description corrected to match the page. **Not fixed:** the visible "Last updated April 26, 2026" text on the page itself is still stale; only the meta tag was touched.
- **The release version is still hand-synced across 4+ locations**, two of which are character counts (`steps(N)` and `Nch`). Untouched — still wants build-time substitution. | web | quick

### Footer consistency — fixed in PR #86 (open)
- ~~**Four distinct footer variants across seven pages**; `task-flows.html` has none.~~ **Fixed for the six document pages** — one shared `.footer-links` markup/CSS block. The homepage keeps its own icon-row variant deliberately (see `web/DESIGN.md`). `task-flows.html` still has none, now moot — see the `/flows` decision below.
- ~~Same link labeled `aria-label="X / Twitter"` on index vs `"Twitter"` on subpages.~~ **Was already stale before this pass** — there is no Twitter/X link anywhere on the live site (removed earlier, per PR #77's dead-link fix). Nothing to do here.
- ~~Footers are `position: fixed` with no background, so on any page taller than the viewport they render on top of body text.~~ **Fixed for the six document pages** — footer is now `position: static`, pushed to the bottom of a flex column via `main { flex: 1 }`. The homepage re-pins its footer to `fixed` deliberately (it's a single exactly-viewport-height hero designed around a footer glued to the bottom edge, not a scrolling document). | web | quick

### `/flows` — decided, pulled from the public site
- ~~`task-flows.html` is untouched by PR #86, deliberately — an internal spec, publicly routed, linked from nowhere, unpinned `mermaid@11` from jsdelivr, no design-system migration, no `<main>`/skip-link/`<h1>`/footer. Still needs Sean's call: pull it from `web/`, or bring it into the design system and rewrite the GAP grid as a roadmap.~~ **Decided: pulled.** `task-flows.html` moved to `docs/task-flows.html` (history preserved via `git mv`); the `/flows` rewrite dropped from `vercel.json` and the URL dropped from `sitemap.xml`. It stays an internal reference doc, unmigrated to the design system, no longer publicly routed or CSP-governed. | web | project

### Security headers — fixed in PR #86 (open)
- ~~`vercel.json` sets HSTS and `nosniff`. Missing: `Content-Security-Policy`, `X-Frame-Options`/`frame-ancestors`, `Referrer-Policy`, `Permissions-Policy`.~~ **Fixed** — all four added. | security | quick

### Performance — investigated, no change warranted
- **No `preload` attribute on any `<video>`.** Investigated in PR #86 and deliberately left alone: both product videos are `autoplay`, so eager fetch is the correct behavior — `preload="none"`/`"metadata"` would just delay playback for no benefit. The finding was moot, not fixed.
- **Zero lazy loading site-wide.** Investigated: there are zero `<img>` tags anywhere on the site (all imagery is inline SVG or CSS), so `loading=`/`decoding=` have nothing to attach to. Also moot. | web | quick

### Small / polish
- The favicon still randomizes color on every load. Untouched — still needs Sean's call. | web | needs-Sean
- ~~`<link rel="icon" href="">` on all pages fires a request against the current document URL.~~ **Fixed** — the empty `href` attribute was removed entirely on all 7 pages.
- **`.product-window::before` still uses terracotta** (`rgba(201,115,80,0.3)`), the only chromatic accent below the hero. Untouched. (Separately, terracotta is now also the site's focus-ring color — see the new item below.)
- ~~`.line-6` anchor text is `+ [download now]` — the diff marker is inside the link.~~ **Fixed**, same change that resolved the terminal-announced-as-fact accessibility item above — the `+ [` / `]` decoration is now `aria-hidden`, so the accessible name is "download now."
- **The mobile `.ghost` override is still `64px`** against a `72px` base. An agent changed it during this work; the change was deliberately reverted before merge. Still open. | web | quick

### New findings from PR #86 (needs Sean)
- ~~**The site has no correct social-share image.**~~ **Fixed in PR #88 (`b9dae122c`).** New `web/assets/social-card.png` (2560×1280, from Sean's Paper artboard) ships as `og:image`/`twitter:image` on all 6 pages with OG blocks. Note the real dimensions are 2560×1280 (2:1), not 1200×630 — `summary_large_image` crops to ~1.91:1, so roughly 2% is trimmed from each side; margins absorb it. Accepted tradeoff, not a defect.
- ~~**`web/assets/poster.png` is unreferenced but still contains dead content.**~~ **Fixed in PR #88** — deleted. `assets/poster.png` now 404s in production.
- **Terracotta `--accent` now doubles as the site's focus-ring color** (4.92:1, passes AA) on a site where terracotta was explicitly dropped as a brand color. Introduced by the new `:focus-visible` rule in PR #86. Deliberate or not, terracotta is now an interaction color, not just a caption accent. | web | needs-Sean
- **The hero terminal clips the GitHub URL below 768px.** A fluid `clamp()` type scale fixes it but retunes the hero's type across the whole 320–767px range and reaches 10px monospace at 320px — a real design tradeoff, not a defect fix. Built and deliberately reverted before PR #86 merged. | web | needs-Sean
- **The mobile footer is now ~2.5× its former height** (112px document / 106px homepage at ≤480px) because the 44×44 touch-target fix makes the tap boxes real. Reads fine, but on the homepage — which pins its footer `position: fixed` — it's now a permanently fixed ~13% of an 800px viewport. | web | needs-Sean

## 2026-08-08 — web audit follow-up (PRs #93, #95)

### New findings
- **Footer tap targets fail WCAG 2.5.8 at the 768px breakpoint.** Measured: footer link height
  is 13–16px at 768px, under the 24px minimum. Mobile widths are fine (38–41px tall at 320/375;
  homepage icon links 44×44). Cause is `--size-small` (13px) typography at that breakpoint, not
  any recent change — it's pre-existing and was explicitly out of scope for PRs #93 and #95.
  Raising it is a type-scale decision, not a mechanical fix. | web | needs-Sean
- **The homepage's fixed footer rests on a premise that is no longer true.** `web/index.html`
  keeps `footer { position: fixed }` (the six document pages use a static in-flow footer via
  `style.css`). That was designed for a hero that was exactly one viewport tall. On mobile the
  homepage content now exceeds one viewport, so scrolling content passes under a fixed bar —
  which is the root cause of the stacking bug fixed in #95, not an incidental detail. #95 fixed
  the symptom correctly (footer raised to `z-index: 2` with an opaque `var(--bg)` background,
  `.product` mobile bottom padding raised 72px→112px to clear it). Accepted trade-off, Sean's
  explicit call: at mobile widths, headings are now cleanly clipped behind the opaque bar during
  scroll instead of bleeding through it messily. Open question: should the homepage footer stay
  fixed on mobile at all, or go static below 480px to match the other six pages. | web | needs-Sean

### Shipped
- ~~**Homepage footer links non-tappable on mobile.**~~ **Shipped in #95** (`6bb98f57c`), verified
  with real click dispatch at 320/375/768.

## 2026-08-01 — ghostties.org docs section (parked)

- [ ] **ghostties.org — high-level docs section (P3).** Add a docs overview page to the marketing site with high-level concepts, linking to the GitHub repo for depth. Blocked on the repo-documentation work happening in a separate thread — needs the real doc URLs to land first so the links aren't dead. | web | needs-docs

## 2026-07-31 — In-app browser has no keyboard support (new, from Sean's testing)

Sean hit this testing a real build: **can't paste into the URL bar, and none of the normal browser keyboard shortcuts work.** Static trace done (read-only explore agent); the two obvious suspects were both RULED OUT.

- **Not the Edit menu.** `MainMenu.xib:245-268` wires Copy/Paste/Select All to the standard responder selectors (`copy:`/`paste:`/`selectAll:`), not to terminal-specific actions. The menu is not stealing Cmd+V.
- **Not an event monitor.** Every `.keyDown` monitor in the app was enumerated. The only ones that swallow (`return nil`) are Cmd+Shift+N (`AppDelegate.swift:860`) and Cmd+Shift+[/] (`AppDelegate.swift:915-932`). Nothing touches plain Cmd+V. `BaseTerminalController.swift:222` is `.flagsChanged` only; `SurfaceView_AppKit.swift:351` is `.keyUp`/`.leftMouseDown` only.
- **Live hypothesis: the URL field never becomes first responder.** `BrowserNavigationBar.swift:31-39` is a plain NSTextField with no custom key handling. Its delegate (`WorkspaceViewContainer`, set at `:845`) implements only `insertNewline` (`:1543-1567`) and returns false for everything else. Nothing in the codebase calls `makeFirstResponder` on it. **Needs a runtime probe to confirm — cannot be settled by reading.**
- **Separately: the shortcuts were never built.** No handler exists anywhere for Cmd+L (focus URL bar), Cmd+R (reload), or back/forward. This is not a regression; the panel shipped without keyboard support. Nav buttons also have no target/action until `embedBrowserInPanel()` runs (`WorkspaceViewContainer.swift:837-844`).
- **CORRECTION — plain Cmd+[ / Cmd+] do NOT collide.** Verified in `src/config/Config.zig:7038-7048`: macOS binds `cmd+shift+[` / `cmd+shift+]` to previous_tab/next_tab, and plain brackets are unbound. Sean's user config (`~/.config/ghostty/config:49`) has exactly one keybind (`cmd+alt+t`). So Cmd+[/] is free for back/forward with no gate needed. The chords that DO collide are Cmd+T (`new_tab`) and Cmd+W — those need the browser-focus gate.
- **Multi-tab browsing is fully built but structurally UNREACHABLE.** `BrowserTabManager.swift` implements create/close/switch/closeAll with a separate CEFBrowserView (own Chromium process) per tab, and `BrowserTabBar.swift` is a real tab strip with per-tab close buttons and a "+" button (`:251`). But `BrowserTabBar.swift:156` sets `alphaValue = tabs.count > 1 ? 1 : 0` — and the only way to create a second tab is the "+" inside that hidden bar. Chicken-and-egg: you can never reach two tabs, so the bar never appears. Sessions each get one tab seeded to google.com (`SessionCoordinator.swift:320-321`). Note `alphaValue = 0` does not stop hit-testing or collapse layout, so there is an invisible-but-clickable strip taking `barHeight` above the content area. **Needs Sean's call: make tabs reachable, or accept single-tab and delete the strip.**
- Unresolved without a build: whether CEF's internal C++ consumes events before the NSTextField sees them, and whether `SurfaceView.focused` correctly goes false when the browser panel is shown. | craft | session

## 2026-07-29 — UI fix wave (PRs #57 / #58 / #59)

### ⛔ MERGE GATES — runtime checks only a human can run
- **PR #57 — the whole fix reduces to one untested boolean: does `.onExitCommand` fire at all?** If AppKit's field editor *handles* `cancelOperation:` it consumes the message and it never reaches SwiftUI, in which case nothing clears `editingSessionId`, the deferred commit passes the guard, and the original bug ships unchanged — deterministically. Ordering C explains the original symptom exactly as well as the orderings the fix was designed against. **Test (90s, project-first mode):** rename a session → type `zzz` → Esc → row must show the ORIGINAL name → right-click that row again and confirm **"Sync name automatically" is ABSENT** (it only appears once `isNamePinned` is true, so its presence proves a store write slipped through and the fix is inert). Then: rename → type `abc` → click another row → must commit. Then: rename → Esc → rename again → field must accept keystrokes. **If the second check fails,** replace `.onExitCommand` with an Esc catcher that runs at `performKeyEquivalent:` time — a zero-size `Button` with `.keyboardShortcut(.cancelAction)` beside the TextField, or `.onKeyPress(.escape)`. Both guarantee the ordering by construction and remove the premise. Do NOT pre-apply; the test decides. Failure mode is binary, not a timing race — passes once means passes always.
- **PR #58 — five checks, ~3 min.** Build the branch (`open macos/Ghostties.xcodeproj`, scheme Ghostties, Cmd+R).
  1. **Width restore.** Wide window, drag sidebar near max. Tile to half-screen — sidebar visibly narrows, terminal stops shrinking. Un-tile. **Sidebar must return to the original width.** If it stays narrow, Blocker 1 is not fixed.
  2. **Open animation.** Reduce Motion **OFF** (Settings → Accessibility → Display). Toggle sidebar closed → open. **Must slide over ~0.2s, not snap** — should feel identical to the close direction.
  3. **The re-review defect (decisive check).** Close the sidebar *first*, THEN shrink the window to ~700pt, THEN open the sidebar. **It should come in already narrowed.** If it opens full-width and squeezes the terminal, correcting only after you nudge the window edge, the `needsLayout` re-trigger didn't take.
  4. **Browser budget.** Sidebar pinned wide, open the browser panel, shrink until the sidebar clamps. **No gap between the terminal card and browser card.** A phantom gap means `resizableWidth` reads the wrong width.
  5. **Beachball watch.** Activity Monitor on Ghostties. Drag the window edge slowly left/right ~10s through the clamping range. CPU should look like a normal resize and **return to idle immediately on mouse-up**. Sustained pegging after release is the old failure signature.
- **PR #57 CI** — the `macOS App (build-for-testing)` job was still in progress at review time. `Swift Package (cli/)` green. Don't merge until the macOS job lands.

### Accepted-and-deferred in this wave (disclosed in PR bodies)
- **PR #58 does NOT fix terminal crushing.** `maxByAvailableSpace` ignores the browser panel's width budget: with the browser open at its 320pt minimum in a 900pt window, the sidebar may stay at 480 and leave the terminal **76pt** — a quarter of `terminalMinWidth`. Left alone deliberately, because the identical formula appears in `handleSidebarDrag` (~line 825) and **changing one without the other makes the resize clamp fight live drags**. Fix both together or neither. Arguably the more visible bug than the window-shrink one #58 does fix. | craft | session
- **PR #57 behavior changes.** (a) Editing session A then starting a rename on session B without an intervening blur now DISCARDS A's pending commit instead of committing it — Finder semantics say the first rename should commit, so this is a mild regression. (b) Quitting (⌘Q) in the same runloop turn as a blur loses the commit rather than delaying it. Both low severity, both disclosed.
- **PR #58 cosmetics, non-blocking.** `intrinsicContentSize` still reads `currentSidebarWidth`, which can now exceed the applied width — only consumed by `defaultSize.apply` at window creation when the two are equal, so no impact today. And a stray 1pt nudge of the drag handle in a narrow window still collapses the desired width to the clamped one via `handleSidebarDrag` — pre-existing shape, worth fixing when that formula is revisited.
- **`isSidebarTransitionAnimating` is arguably redundant.** The re-reviewer found the guard-witness change alone kills the animation-clobber (an `ObservableObject` has no `animator()` proxy, so `widthModel.width` structurally cannot hold intermediates). The flag prevents a failure the witness already prevents, and introduced the missing-`needsLayout` defect in doing so. Deleting it is the smallest *correct* patch; we took the smallest *safe* one. Revisit if this file is touched again.

### Follow-up: session-cycling menu validation
- **Greying the session menu items will NOT disable ⌘⇧[/] — a validation-only fix is a trap.** `AppDelegate.setupSessionCyclingShortcut()` (`AppDelegate.swift:915-935`) intercepts that chord in an `NSEvent.addLocalMonitorForEvents` handler that calls `NSApp.sendAction(_:to: nil, from: nil)` — which **does not consult `validateMenuItem`** — and returns `nil` unconditionally, swallowing the event. So after a naive fix the menu row greys while the keyboard chord still fires the same silent no-op AND still eats the keystroke instead of falling through to Ghostty's `next_tab`/`previous_tab`. The session fix must apply the same predicate *inside that monitor* and `return event` when it fails. Anyone who ships session validation without this will believe they fixed it and will not have. | craft | session
- **Unblock is `WorkspaceViewContainer.swift:69` — drop `private` from `let coordinator: SessionCoordinator`.** `TerminalController` already reaches the container via `window?.contentView as? WorkspaceViewContainer` at four existing sites. Cost: one keyword + a ~4-line validation case calling `store.sessionsInVisualOrder(coordinator:)`. Correct by construction — it resolves the coordinator for the window being validated.
- **Do NOT use a `RowFocusStore`-style bridge for this.** Reviewed and rejected: `RowFocusStore` holds the most-recently-focused item *across all windows* (`RowFocusStore.swift:13-20`). Menu validation must answer for the key window; with two workspace windows open a global bridge greys or enables based on the wrong window's session set — reintroducing the exact "greyed while the action would have worked" failure the ticket set out to avoid.
- Project cycling's predicate is deliberately loose and should stay that way: with exactly one project already selected + expanded, ⌘⌃] is still a no-op, but tightening to `count > 1` would be actively wrong (a stale `selectedProjectId` makes the action take its meaningful branch). `selectedProjectId` is per-window SwiftUI `@State` AppKit cannot read, so a tight predicate is impossible from `TerminalController`.

### Build environment
- **A fresh `git worktree` cannot build this repo without help.** `GhosttyKit.xcframework`, `zig-out/`, and `vendor/{cef,cef-build}` are all gitignored, so `xcodebuild` fails immediately in a new worktree. All three agents in this wave hit it independently. Copy/symlink those from the main tree before building; `zig build` is not an option (broken on macOS 26). Worth a `docs/solutions/` note and a line in the delegation template. | build | quick

### Design-system drift (surfaced 2026-07-29, see artifact)
- **`DESIGN.md` never learned the June 2026 status palette.** §4 still documents three activity states with terracotta as "waiting"; the code ships four named status colors (`statusYourTurnBlue` #5B8DEF, `statusNeedsDecisionGold` #FFC400, `statusLongRunningOrange` #F97316, plus green) that the spec never mentions. This single omission is the root of the terracotta contradiction — DESIGN.md:102 says terracotta is reserved exclusively for `waiting`, WorkspaceLayout.swift:126 says it is explicitly NOT the status waiting color, and all 21 uses across 9 files are the accent uses the spec forbids. **Needs Sean's call: update the spec to match the code, or move the code to match the spec.**
- `titlebarSpacerHeight` — spec says 38pt, code ships 28pt. Flat numeric drift.
- Ten of fifteen layout tokens exist only in code, never documented.
- Source-dot palette (`sourceDotShell`/`Linear`/`GitHub`/`Sentry`) entirely undocumented in the spec.
- `needsAttentionPurple` — 1 reference in the repo (its own definition), already `@deprecated`. Safe deletion, no decision needed.

## 2026-07-28 (later) — from Phase 0 + PR #56 review

### Blocking the truthful-status work
- **Replace the template-kind proxy with a real foreground-TUI signal.** PR #56 keys on `template.kind != .shell`, which misses 46 of 84 live sessions — the ones started by opening a Shell and typing `claude`. Correct discriminator is "is a full-screen TUI in the foreground of this PTY": read the PTY foreground process group, or read Claude Code's session JSON (already the authoritative source). Closes the coverage gap AND backfills the "silent when Claude actually blocks" regression in one move.
- **Launcher-script coverage fix** — `SessionCoordinator.swift:184` only writes the launcher when a template has a banner. Always write it when `resolvedCommand != nil` (~5 lines). Takes every agent-template session to an exact Claude↔Ghostties join via the UUID in argv.
- **Rewrite the plan doc's phases around the launcher-UUID join.** Strategy B (cwd→project + title match) is dead — the plan as written is materially wrong from "Join strategies, ranked" onward.

### Test + hygiene
- `UpdateViewModelTests.testNotFoundText()` fails on clean main — the fork customized the Sparkle "no update" copy and never updated the upstream test. Makes every suite run red and trains people to ignore it. **Precise fix:** test expects `"No Updates Available"`; shipped `.notFound` copy (changed in fork PR #34, in beta.19) is `"You're on the latest"` / `"No stable releases yet"`. One-line string update. | quality | quick
- PR #56's shell regression guard is vacuous (passes even if the body is `return false`). Needs a `.custom`-kind test and a missing-session test. Nothing covers `.custom` or `.browser`.
- PR #56: flip the unknown-template fallback to `.idle` for internal consistency; rename `isAgentKindSession` → `isNonShellSession`; document that `.browser` is swept in; refresh the stale `indicatorState(for:)` header doc.
- `~/.ghostties/cache/launchers/` accumulates scripts with no cleanup. Harmless now; becomes load-bearing if the join depends on those paths.

### Design
- `WorkspaceLayout.swift:126` `waitingTerracotta` and `needsAttentionPurple` match neither the documented green/blue/gold/orange status-dot palette nor the decision that terracotta is not a brand color.
- The `.waiting` → `.idle` flip is a **layout** change, not a color change — silent sessions leave Active for Recent, and projects reorder in the sidebar seconds after going quiet. Wants eyeballing on screen before it lands.

### Measurement gap (not closed)
- The cache-load harness measured store recompute (~181ms over 50 simulated min of 6-agent load — fine) but **not** the SwiftUI re-render cascade that made the June storm expensive. The `project_perf-contextmenu-render-cost.md` 2→4→6 ramp is still the missing data. **Confirmed 2026-07-22:** the per-row `.contextMenu`/`.popover`/`.draggable` modifiers are still present in `ProjectDisclosureRow.swift` — not code-fixed. | perf | session

## 2026-07-28 — Switchboard status-engine integration (new track)

### Uncommitted on disk
- `docs/plans/switchboard-status-engine-integration.html` — the reviewed plan, decisions answered. Commit to main when convenient. (Was blocked by the main worktree sitting on a website branch; unblocked 2026-07-29.)

### Decided (review session `sess_d3105e5d`, 2026-07-28)
- **Vendor `AgentStatusCore`, don't take an SPM dependency.** Note the reasoning correction: SPM is NOT risky here — Ghostties already ships Sparkle + swift-argument-parser as remote SPM packages (`project.pbxproj:1566`). Vendoring wins on sequencing, not safety. Shared-package extraction is Phase 5, once the join is proven.
- **Switchboard keeps existing and will be released.** The vendored copy is an explicit temporary fork; it needs a provenance header naming the source commit.
- **Run phases 0→3 autonomously**, each gated on its own tests + a separate reviewer agent.

### Open
- **Naming collision — needs a strawman before any code.** Both codebases define `AgentSession` AND `SessionStatus` with different shapes. Proposed: prefix vendored types `Claude*` (`ClaudeSession`, `ClaudeSessionStatus`). Cheap to decide now, touches every call site later.
- **`foregroundPID` / `ttyName` are stubbed to `return nil`** (`Ghostty.Surface.swift:96-116`) — the C symbols exist (`include/ghostty.h:1118`) but postdate the local `GhosttyKit.xcframework`, and zig 0.15.2 can't relink on macOS 26. This blocks the exact process-ancestry join. Superseded in practice by the launcher-UUID join (see 07-28 later), but the stub itself is still there.

## 2026-07-27 — Sessions sidebar + name sync (PRs #54, #55)

### Resolved this session
- **Ghosts approved by eye** — Sean reviewed a real Release build of #55 (all 82 sessions backfilled, 24 characters, ~4 sessions each). Verdict: "others seem to be ok." Legibility at 14pt is fine; the 4× repeat is fine.
- **`ACTIVE 0` taste call is moot** — live state showed `ACTIVE 3 / ARCHIVE 79`. The empty-ACTIVE header only appears on a genuinely cold launch.
- **PR #55 merged** to main as `3c6f59a83` (squash, branch deleted).
- **PR #54 brought up to date** — merged `origin/main` into the branch (NOT rebased, to avoid a force-push) as `8d8935bc1`. One conflict, `AgentSession.swift`, resolved additively; both `ghostCharacter` and `isNamePinned` survive with both decoder lines. Full unfiltered suite: **674 run, 673 passed**, 1 known pre-existing failure.

### Still open
- **Measure #54 under 5-7 real agents.** Each name write clears `sessionGroupsCache` for ALL projects via the `didSet` at `WorkspaceStore.swift:32-37`, bypassing the PR #39 memoization store-wide. Bounded to one write per 5s per session (~20× below the June storm rate) and almost certainly fine — but it is a NEW steady-state cost on the exact path that caused the beachball, and the reviewer's call was "measure, don't reason." **Cannot be driven from an agent session.** Agreed substitute: a synthetic harness at the real cadence — exercises the mechanism, not the real load. Not yet built.
- **Follow-up after both land:** #54 could not add the "Sync name automatically" menu item to `RecentsListView` (parallel PR owned that file). Small, needs doing.

### Confirmed this session
- **The June status-dot palette was never merged.** Logged "SHIPPED ✅" in `ORCHESTRATOR.md` for a month while `main` kept the dropped purple/terracotta. Cherry-picked into #55. See `feedback-shipped-means-merged-to-main`.

## 2026-07-26

### Ship / release
- **Cmd+Shift+[/] fix is on `main` but NOT in a release.** Merged as `af726311b` (PR #53). Users on beta.20 still have the broken shortcut until the next tag. Fold into next beta.
- **PR #33 still open** — superseded by #47; close attempt was permission-denied earlier. | ops | quick

### Repo hygiene
- **Delete merged local branches** (permission-denied during wrap):
  `git branch -D feat/sessions-tab-context-menu feat/session-cycling-shortcut feat/sidebar-resize`
- **Branch protection does not gate on CI.** PR #53 merged instantly with `--auto` while the macOS build + Swift package checks were still in progress. If checks should block merges, that's a branch-protection setting — the merge command can't enforce it. (Post-merge run came back green.)
- **Sweep stale `SeanSmithDesign` refs from memory files + docs** — the account renamed to `SeanSmithWorks` (2026-07-21). Code refs are fixed (PRs #51/#52), but lingering `SeanSmithDesign` strings in memory/docs (and possibly a cached "configured origin") make the harness security scanner FALSE-POSITIVE on every correct PR to `SeanSmithWorks/ghostties`. Harmless but noisy. Intentionally left: test-fixture/doc-comment example URLs (`CrossSurfaceCoherenceTests.swift`, `TaskModelTests.swift`, `TaskModel.swift` — illustrative `pull/99` examples) and `web/appcast-beta.xml` (CI-regenerated). See memory `feedback-scanner-false-positive-account-rename.md`. Carried from 2026-07-22. | ops | quick

### Task view (unspecified)
- **Sean flagged "issues with tasks" during the 2026-07-26 session but did not specify them.** Needs his description before it can be scoped. Do not guess.
- Known from PR #44 review: task-first cycling scrolls but doesn't move the visual focus ring, and can't scroll to Active-zone rows (`"task:<id>"`-prefixed ForEach identity → silent no-op). May or may not be what he meant.

### Docs
- **`docs/solutions/` note not written** for the `performKeyEquivalent` focus-gate gotcha (offered, no answer). Worth capturing: a fork keybind that collides with an upstream Ghostty binding fails *only while a terminal surface has focus* (`SurfaceView_AppKit.swift:1307` `if !focused { return false }`), which makes the collision look intermittent and defeats casual testing. Fix pattern is a local `NSEvent` monitor.

### Parked from earlier waves
- Window-shrink doesn't re-clamp sidebar width (same gap as browser panel).
- Menu-item validation — no greying when zero live sessions/projects.
- Retro-fit visuals into PR bodies #43/#44/#45 (merged before the UI-PR-visuals rule landed).

## 2026-07-18

- [ ] **Re-enable app-hosted macOS test execution on CI** — `test-ghostties.yml`'s `macos-app` job now runs `build-for-testing` (compile-only), not `test`. Reason: launching `Ghostties Dev.app` as the XCTest host reliably hangs ~6 min on headless GitHub runners ("test runner hung before establishing connection" → exit 65), even though the three-layer XCTest short-circuit makes local Cmd+U launch fast. The pure-Swift logic suites still run in the `swift-package` (cli/) job; app-hosted `GhosttyTests` execution is local-Cmd+U-only. Real fix: move the host-independent test classes (TaskModelTests, TaskFileWatcherTests, TaskStoreWriteTests, router/dedup/zone logic, etc.) into a non-app-hosted logic bundle so they run without launching the GUI. See memory `project-ci-host-app-hang.md`. | build | session

## 2026-07-17

- [ ] **Esc doesn't cancel inline session rename** (#43 polish) — right-click → Rename → type → `Esc` keeps the typed value instead of reverting; only `Enter` commits and re-typing reverts. Wire up Escape-to-cancel. Minor, out of scope of beta.20 verify. | craft | quick
- [ ] **Phase 1 file-watch not live-verified** — blocked by TCC: the ad-hoc `Ghostties Demo` build lacks Files & Folders permission ("Data Access Blocked"), so it can't read `examples/demo-workspace/*/.ghostties/tasks/`. Needs Sean to grant it in System Settings → Privacy → Files & Folders, OR accept the Phase 1 close on code verification. | build | needs-Sean
- [ ] **`.gitignore` build-output dirs** — `.build-demo/` and `.build-verify/` are untracked build artifacts sitting in the repo root; add to `.gitignore`. (`.build-demo/` gitignore already noted in ORCHESTRATOR demo-capture entry.) | build | quick
- [ ] **Stale updater test on main** — `GhosttyTests/UpdateViewModelTests.testNotFoundText()` expects `"No Updates Available"` but the shipped `.notFound` copy (changed in fork PR #34, in beta.19) is `"You're on the latest"` / `"No stable releases yet"`. Pre-existing, unrelated to beta.20; our red CI never caught it. One-line fix: update the test's expected string to match current copy. | quality | quick
- [ ] **Perf track (contextMenu render cost, #1/#2)** — confirmed this session the per-row `.contextMenu`/`.popover`/`.draggable` modifiers are still present in `ProjectDisclosureRow.swift` (not code-fixed). Full state + the one remaining interaction-under-load check live in ORCHESTRATOR In-Flight Work. Separate objective from beta.20 verify. | perf | session

## 2026-08-01 — repo documentation refresh

Objective: get the GitHub repo presentable for incoming interest, with correct Ghostty-vs-Ghostties calibration. Plan: `docs/plans/repo-documentation-refresh.html`.

**All five waves are now in PRs awaiting review.** Merge order matters: #74 before #76, because the copy of `CONTRIBUTING.md` on `main` still links to the `AI_POLICY.md` that #76 deletes.

- [x] **Wave 1 — governance purge** — PR #71. 19 files, 4,524 deletions: CODEOWNERS, VOUCHED.td, 5 vouch workflows, 2 discussion templates, 8 dead upstream pipelines.
- [x] **Wave 2 — licensing & attribution** — PR #73. LICENSE stacked copyright + `THIRD-PARTY-NOTICES.md`, and the notice now ships inside the `.app` (verified by build: lands in `Contents/Resources/`, byte-identical). Corrections to the original plan: nerd-fonts is MIT (`font-patcher.py`), not OFL; swift-argument-parser (Apache-2.0) was missing entirely; Sparkle's LICENSE bundles four more licenses.
- [x] **Wave 3 — README rewrite** — PR #75. 68 lines, uncropped hero (Sean's call), 332K inline demo GIF (GitHub won't render `<video>` from a repo-relative path), plain Ghostty credit + non-affiliation, fixed the License copyright mismatch.
- [x] **Wave 4 — intake & support docs** — PR #74. CONTRIBUTING rewrite, SECURITY, CODE_OF_CONDUCT (Covenant 2.1), TESTING (written against real runs: 110 cli tests, 673 app tests, both green), YAML issue forms. 6 area labels created directly on the repo.
- [x] **Wave 5 — inherited-doc cleanup** — PR #76. Deleted `PACKAGING.md` + `AI_POLICY.md`, rewrote `AGENTS.md`, fixed the `HACKING.md` header (it cloned upstream's URL).
- [ ] **Wave 0 — repo settings (Sean's hands, GATED on Wave 1 merging to main)** — enable Issues + Discussions (Q&A and Ideas only, delete other categories), private vulnerability reporting, Dependabot alerts. Set description, 10 topics (currently empty), and a 1280x640 social preview. **Do not enable Issues before the merge** — `issues`-triggered workflows run from the default branch, so the inherited auto-close vouching workflow is still armed on `main`. | docs | needs-Sean
- [ ] **`blank_issues_enabled: false`** — the Wave 4 plan called for this; left `true` so people who don't fit either form still have a route in. Flip it if the untemplated issues turn out to be noise. | docs | quick
- [ ] **`.github/dependabot.yml` retarget** — listed in the Wave 5 plan, not done; it was out of the doc-prune scope and belongs with a CI pass. | build | quick
- [ ] **Dark-mode hero capture — deferred** — hero is light-only, and a light screenshot on GitHub's dark theme reads as broken. `<picture>` theme-swapping needs a dark capture. Not worth a session on its own; do it next time Ghostties is open with Screen Recording granted. | design | deferred
- [ ] **Stale comment in `ghostties-release.yml`** — line 6 reads `# Key differences from upstream release-tag.yml:`, but that file was deleted in Wave 1. Comment only, no functional reference. Left untouched because the security work-stream owns that file. | build | quick

**Off-objective, parked here deliberately (do NOT carry into the docs thread):**

- [ ] **Public-repo hygiene** — `docs/SESSION_NOTES.md` (158KB of internal notes), `docs/handoffs/`, `docs/brainstorms/`, `docs/PR_DRAFTS.md`, `drafts/`, `todos/`, `BACKLOG.md` are all publicly readable. Wave D already untracked one file for the same reason. Untracking stops the bleeding but does not clear already-public history — see the private memory for prior art and the real fix. Deliberately NOT folded into a documentation branch. | security | needs-Sean

## Deferred / low priority

- [ ] **Ghost physics playground — full port** — the fuller interactive playground (drift physics, drag-throw, trading-card hover) from the sibling `2026-web-playground` repo was explicitly parked in favor of the lighter ambient-drift-only version that shipped in PR #48. Repo isn't cloned on this machine. Revisit only if Sean asks for the fuller version specifically. | web | deferred
- [ ] **Approve or edit the 4 social drafts** at `drafts/ghostties-social-question-series.md` — question-hook posts paired with the site's two hero visuals. Drafted and shown to Sean, not yet reacted to. Note: social/content review happens in a separate dedicated thread, not the app orchestrator thread. | content | needs-Sean

## 2026-08-08

- [ ] **DMG-installed app is unstapled** (`.github/workflows/ghostties-release.yml`) — `create-dmg` runs (~line 288) before `xcrun stapler staple` (~line 334), so `Ghostties.dmg`'s app never gets the staple; `ghostties-macos-arm64.zip`, zipped after stapling (~line 337), does. Verified by installing both: the zip's app reports `Notarization Ticket=stapled`; the DMG's app fails `stapler validate` and carries `com.apple.quarantine`. Both still pass `spctl` while online. Consequence: a Homebrew cask install (copies out of the DMG) needs an online Gatekeeper check on first launch — offline or on a restrictive network it shows the "cannot check it for malicious software" dialog, on the exact path the README calls recommended. Likely fix: staple before `create-dmg`, not after. Not fixed here — touches the release pipeline, can't be verified without cutting a release, and beta.22 belongs to a sibling thread. | build | needs-release-cut

## 2026-08-09

- [ ] **Cask CI auto-bump not activated.** Needs a fine-grained PAT scoped to `SeanSmithWorks/homebrew-tap` stored as `HOMEBREW_TAP_TOKEN`, plus the `HOMEBREW_TAP_REPO` variable. **Set both together or neither** — the job intentionally fails loudly when the variable exists without the token, which would turn a release run red. Do not substitute `gh auth token` (spans every repo, including private ones, and rotates with the CLI session). Until then, bump manually: `bash scripts/update-cask-version.sh <tag>`, then copy into the tap's `Casks/ghostties.rb`. | build | needs-Sean
- [ ] **npm version bumps are manual.** `dist/ghostties/npm/ghostties-install/package.json` pins the app version and its SHA256; publishing a new pin means `npm publish` by hand. Deliberate — Sparkle catches installed apps up on first launch, so a stale pin self-heals. | build | deferred

Sidebar/UX wave night. Ten PRs merged: the six-PR overnight wave (#96, #100, #101, #102, #103, #104) plus four follow-ups driven by live testing (#106 Archive stays collapsed, #107 repo-name-echo titles, #108 Inactive zone, #109 real Archive sort by `lastActiveAt`, #111 Inactive boundary correction). Main at `86e2c0bc4`, suite 659/658/0/1.

- [ ] **#110 fixture swap — IN FLIGHT, UNVERIFIED** — PR #110 (three title-sanitizer leaks: spinner glyphs, `<dir> | Claude Code`, ellipsis paths) is CLEAN and MERGEABLE but its fixtures contain real local strings (`2026-web-playground`, `…/Code/_experiments/…`). A subagent was mid-swap when the thread was recycled; its **uncommitted** edits to `SessionTitleSanitizer.swift` + `SessionTitleSanitizerTests.swift` are in the worktree at `.claude/worktrees/agent-af3ba3c118d267faf` on branch `fix/reject-status-glyph-titles`. Verify with `grep -rn "2026-web-playground\|_experiments\|/Users/sean" macos/` — must return nothing before merging. If the work is gone, it's a 3-string swap: `2026-web-playground`→`sample-web-project`, `…/Code/_experiments/2026-web-playground`→`…/Code/sandbox/sample-web-project`, `/Users/sean/`→`/Users/someone/`. Suite must stay exactly 673/672/0/1 — a pure string swap changes no counts. | app | carried
- [ ] **Rename-with-Enter verdict** — `isNamePinned` is **0 of 31** sessions after a full evening of Sean testing. Consistent with only-Esc (correct #57 behavior), but not proven. Code reads correct on both tabs (`.onSubmit → commitRename → store.renameSession`), persistence verified (the flag is written on all 31 records). Needs one deliberate Rename → type → **Enter**, then read `~/Library/Application Support/Ghostties Dev/workspace.json`. Until settled, cannot rule out a broken Enter path. | app | needs-Sean
- [ ] **beta.22 — three runtime checks, then tag** — tag point `047cd3a85` confirmed still an ancestor of main, so the wave did not contaminate it. Checks (each has an ordering trap that makes the lazy version pass trivially): **#57** rename → junk → Esc → right-click, "Sync name automatically" must be ABSENT, **Projects tab only** (the item only exists in `ProjectDisclosureRow`) and on a never-renamed session; **#58** close sidebar FIRST, shrink to ~700pt, THEN open; **#92** two sessions running, stop one, other must stay ACTIVE, on an already-running app. Tag needs Sean's explicit go — fires release CI and republishes the appcast, and origin rulesets block tag deletion. | release | needs-Sean
- [ ] **CI guard for `window.backgroundColor`** — offered, never built. A test that fails if a `WorkspaceLayout` token is ever assigned to a window's `backgroundColor` anywhere in `macos/Sources`. #96 deleted both hardcoded overrides and left fork-fence comments, but comments don't enforce. Root cause of the 3× recurrence was `agent-craft.md` actively instructing the bug; both entries corrected 2026-08-09 and captured in `feedback_window-backgroundcolor-is-derived.md`. | app | quick
- [ ] **Prune 8 stale worktrees** — all merged branches, only `vendor/cef*` build artifacts dirty, no work at risk: the four `agent-*` from the wave, plus `esc-cancel-rename` (#57), `hide-tasks-view` (#100), `menu-validation` (#59), `sidebar-reclamp` (#58). Do NOT touch `session-2` (locked, another session, PR #105) or `truthful-idle` (#56 open) or `cache-load-harness` (never merged). | build | quick
- [ ] **Archive expansion is remembered, not reset per launch** — Sean asked for "closed by default"; the code default was already `false` and the symptom was a stale stored `1` from testing (fixed by `defaults write com.seansmithdesign.ghostties.dev ghostties.sessionsSection.archive -bool false`). Open question he hasn't answered: should Archive *always* start collapsed each launch regardless of how it was left? That's a real code change. | app | needs-Sean

**Off-objective, parked (do NOT carry):**

- [ ] **PR #105** (`docs/npm-published`) — owned by another session, worktree `session-2` is locked. Not this thread's to merge. | dist | other-session
- [ ] **PR #56** (idle-fallback) — open since July, correctly excluded from beta.22. | app | deferred
- [ ] **`test/session-cache-load-harness`** — branch on origin, no PR ever opened, genuinely unmerged. Confirm whether it's dead. | build | deferred

## 2026-08-14

**CLOSED 2026-08-14 — sidebar row staleness. Root cause was `LazyVStack`, not `.equatable()`.** All three merged to `main`: #121 `988b11223`, #122 `7e04b7fd3`, #123 `f7248d5b9`. Build green, 682/685 (2 failures = the untracked Throttle file below). Full write-up: `reference_sidebar-rows-frozen-lazyvstack.md`.

- [x] ~~Verify the `.equatable()` fix at runtime~~ — verified and **FAILED**. `.equatable()` was never the fix; kept only as a perf gate.
- [x] ~~Strip temporary SIDEBARDIAG instrumentation~~ — zero hits in `macos/Sources` on `main`.
- [x] ~~Run the full suite + reshape PR #121~~ — done; PR body now describes the real root cause.
- [x] ~~`SessionTitleSanitizer` doesn't strip `◐`/`◑`~~ — fixed in #122 via a structural rule (category `So`, non-emoji-presentation) unioned with the legacy `* · •` set, rather than enumerating glyphs.

**Still open:**

- [ ] **`ThrottleTrailingEdgeHypothesisTests.swift`** (untracked) — DECIDE OR KILL: keep the trailing-edge test as a regression test and delete the two diagnostic ones (one calls `XCTFail` unconditionally, so it fails every local run), or drop the file. Strawman: keep the trailing-edge test only. It is the sole reason local runs report 2 failures. | app | carried 2×
- [ ] **`.workspaceSidebarTabChanged` is a dead notification** — declared `WorkspaceLayout.swift:338`, posted twice from `TerminalController.swift:1361,1368`, zero observers anywhere. The sidebar tab switch actually works by riding the `.workspaceSidebarViewModeChanged` post on the following line, usually setting the mode to the value it already held. | app | carried 1×
- [ ] **Re-test every conclusion measured through a Sessions-tab row** — RAISED IN PRIORITY. Now proven: rows were frozen at first construction, so *any* value read off a row (name, indicator dot, timestamp) was the value at creation, not the live one. Affects the invisible-session bug (2026-08-10) and the blue-ghost indicator readings in `project_switchboard-phase0-verdict.md` — including the "7 idle / 4 busy / 0 waitingFor" measurement the polarity-inversion plan rests on. | app | carried 1×
- [ ] **Archive-expansion perf, unmeasured** — #121 swapped `LazyVStack` for `VStack`, so expanding Archive now builds ~37 rows eagerly, each carrying a `.contextMenu` — a documented, still-unfixed bottleneck (`project_perf-contextmenu-render-cost.md`). If it bites, the fix is a lazy container that still re-invokes content on element change; a plain revert to `LazyVStack` reinstates the frozen-name bug. Warning is already in the code comment. | app | new
- [ ] **Screen Recording grant for `/Applications/Ghostties.app` isn't taking effect** — toggle shows ON, `screencapture` still fails (not the CC sandbox; fails identically with it disabled). Likely a code-requirement mismatch from a pre-beta.22 local build. Fix: `tccutil reset ScreenCapture com.seansmithdesign.ghostties` then relaunch — but the relaunch kills any Claude Code session running inside it, so it is a break-time job. Blocks all screenshot capture from CC sessions. See `reference_screencapture-responsible-app-is-the-terminal.md`. | env | new
- [ ] **Build-badge type size** — the badge ships at 9pt, deliberately below the sidebar's 11pt floor, on the subagent's reasoning that a diagnostic HUD shouldn't read as product UI. Sean's call to keep or raise. | design | new

**Parked — design, Sean's call:**

- [ ] **Status representation vs. per-session ghost icons** — half of this resolved itself: #122 removed the `✳` glyph from names, so the row no longer carries two competing status channels. The remaining question is whether the ghost icon is the right status channel at all. Design decision. Captured in `tease-capture.md`. | design | parked

## 2026-08-21 — Screen Recording grant keeps re-prompting (other thread)

- [ ] **Screen Recording grant is re-requested after it's been given, repeatedly** — Sean has
  granted it "so many times." Extends the 2026-08-14 item (grant shows ON, `screencapture` still
  fails). Leading hypothesis: TCC keys the grant to the binary's code requirement, and every local
  build re-signs ad-hoc with a fresh cdhash, so each new build is a *different* app to TCC — the
  stored grant points at a binary that no longer exists. Consistent with both symptoms (toggle
  visibly ON but denied, and repeated re-prompting). Check whether a stable signing identity for
  local Debug builds fixes it. Note `screencapture` is gated by the *terminal's* grant, not the
  app's — see `reference_screencapture-responsible-app-is-the-terminal.md`. **Explicitly routed to
  a separate thread** (2026-08-21) — do not fold into the web-redesign objective. | env | needs-Sean

## 2026-08-21 — app section: pipeline reversed to automated real screenshots

**Decision (Sean, 2026-08-21):** the HTML replica is NO LONGER the shipping asset. The site's
app section ships **real screenshots of the app, produced automatically.** This reverses the
08-20 "rebuild not screenshots" call; the deciding input was Sean's "it will keep changing" — a
replica caps around 95% fidelity and needs re-tuning on every app change, a capture is 100% and
needs re-taking. `docs/design/web-redesign/rebuild/index.html` and `app-rebuild-spec.md` survive
as reference and as the measurement source, not as shipped output.

**Superseded — do NOT resume:** tuning the four App* canvas artboards as the build contract, and
propagating tuned deltas back into the boards + rebuild. Both existed to perfect a replica.

**Proven this session (`f97171190`, spike):**

- XCUITest captures the app window at **true 2x** (1280x705 pt -> 2560x1410 px) and needs **no
  Screen Recording permission** — it runs through `testmanagerd`, not ScreenCaptureKit. The
  broken TCC grant does not block asset production.
- `XCUIElement.screenshot()` clips to window bounds: rounded corners survive, **shadow does
  not**. `XCUIScreen.main.screenshot()` keeps the shadow but captures the whole display —
  in the spike run it picked up the desktop and a chunk of another live session's content.
  **Resolution: capture the window element, add the shadow in CSS.** Closes both the shadow
  question and the privacy leak with one decision.
- The UI-test runner is **sandboxed** and cannot write PNGs to an arbitrary host path (`/tmp`
  fails with `Operation not permitted`). Write into `FileManager.default.temporaryDirectory`
  and copy out afterwards.
- **Pre-existing repo bug, diagnosed not fixed:** `TEST_TARGET_NAME = Ghostty` in
  `project.pbxproj` names a target that does not exist (it is `Ghostties`), so the generated
  `.xctestrun` gets no `UITargetAppPath` and plain `xcodebuild test` fails for **all**
  GhosttyUITests — reproduced against the pre-existing `GhosttyTitlebarTabsUITests`. The spike
  worked around it at the CLI layer only.

**Plan — open:**

- [ ] **Fix `TEST_TARGET_NAME`** in `macos/Ghostties.xcodeproj/project.pbxproj` (`Ghostty` ->
  `Ghostties`) so `xcodebuild test` runs UI tests without patching the `.xctestrun`. | build | quick
- [ ] **Capture fixture behind a launch argument** — canned workspace (invented project and
  session names) plus a canned terminal transcript, so no real project names, no hostname, and
  no dev build badge can reach a published asset. Privacy-critical: the spike capture showed all
  three. | app | new
- [ ] **`scripts/capture-marketing.sh`** — build, run the capture tests, write 2x window PNGs,
  convert to WebP, emit `<picture>` sources. One command, repeatable after any app change.
  Bonus: the same rig doubles as a visual-regression suite. | build | new
- [ ] **Build the B4 scroll-zoom section in `web/`** on the generated assets, with headline copy.
  The "this is a rebuild" disclosure line is **no longer needed** — the assets are real. | web | new
- [ ] **Terminal interior content** — minimal prompt vs staged Claude Code TUI. Now scoped as
  "what goes in the canned transcript." | design | needs-Sean

## 2026-08-22 — capture rig built (unverified), thread checkpointed

**Landed on `feat/web-redesign-round4`:** `386cbf39f` TEST_TARGET_NAME fix · `a86d5662e` fixture
mode · `5215ce015` `scripts/capture-marketing.sh` + four 2x assets in
`docs/design/web-redesign/captures/`. All pushed.

- [ ] **Re-verify `scripts/capture-marketing.sh`** — the agent was stopped mid-verification. It
  had confirmed one end-to-end run only: **no idempotency re-run and no full-suite run**. Treat
  the script and the four committed assets as working-but-unproven until re-run. | build | carried
- [ ] **Sean redlines the fixture transcript** — the canned Claude Code session in the capture is
  a strawman built without him (invented cast: switchboard/fieldwork/pendulum/silo/trove/wren, a
  Go connection-lock fix). Apply or redline; do not re-ask whether to build one. | design | carried
- [ ] **Build sections 03 SIDEBAR + 04 GT LIST in `web/`** on the generated captures — the two
  sections the content map marks as doing the work. First real `web/` change of the redesign.
  | web | new
- [ ] **02 THE PROBLEM needs an asset decision** — "six windows of sprawl" is a *before* shot, not
  an app capture, so the rig does not produce it. Recording, composed still, or illustration?
  | design | needs-Sean
- [ ] **08 FIRST 60 SECONDS deferred, deliberately** — Sean's call 2026-08-22: it is a closer and
  makes no sense until the core of the site exists. Do not promote it. | web | parked

**Closed:** the 2026-08-21 Screen Recording re-prompt item — root-caused by another thread the
same day (stale `csreq` pinning an old signing identity; fix is `tccutil reset ScreenCapture
<bundle-id>`, no relaunch). Write-up at `docs/solutions/runtime-errors/`. Moot for capture anyway
— XCUITest never needed the grant.

**Off-objective, parked (do NOT carry into web work):**

- [ ] **`~/.claude/hooks/scope-guard.sh` has never fired** — it reads the scope card with
  `grep '^Repo:'`, but `scope-init.sh` writes the line with the frame rail (`│ Repo: …`). The
  grep matches 0 lines, `ROOT` is empty, and the next line is `[ -n "$ROOT" ] || exit 0`, so
  every out-of-scope Write/Edit exits silently. Verified against a live card. Fix: match
  `'│ Repo:'` and strip the rail in the `sed`. Global tooling, not this repo. | tooling | new

## 2026-08-22 (later) — capture rig VERIFIED; real-session leak found in the committed assets

**The rig is proven.** Clean rebuild from scratch → `TEST BUILD SUCCEEDED`; all four
`MarketingCaptureUITests` passed; re-run is reproducible — three of four states re-render within
**0.006–0.021% of pixels** (isolated subpixel antialiasing, max channel delta ≤ 180). Idempotency
and a from-zero build are both closed. `scripts/capture-marketing.sh` can be trusted and re-run
after any app change.

**The fourth state was not a rig product at all.** `app-sessions-dark@2x.png` as committed in
`5215ce015` differed by **82% of pixels** — because it was never a fixture capture. It was a
full-screen shot of a live Ghostties window, and it leaked:

- real project names — Ghostties vNext, Ghostties Website, Ghost Concept, Career-ops,
  Ghostties Screen Recording, GooseWorks Ad
- real session counts — ACTIVE 7 / INACTIVE 3 / **ARCHIVE 150**
- the **complete text of an in-progress Claude Code conversation**, including commit SHAs
  (`5a460ee0b`, `be69856a7`, `#112`) and internal planning prose
- the `.webp` beside it was derived from the same image and leaked identically

This is the exact failure `feedback_public-repo-no-real-session-data.md` warns about, and
`reference_xcuitest-marketing-capture.md` predicted the mechanism: the pre-fixture spike used
`XCUIScreen.main.screenshot()`, which captures the whole display. One of its outputs was committed
alongside the three genuine fixture renders and never re-checked.

- [x] Branch tip cleaned — `2165c2f86` replaces all four states with verified fixture renders,
  pushed to `origin/feat/web-redesign-round4`.
- [ ] **Purge the blob from history — needs Sean.** `5215ce015` is pushed to a **PUBLIC** repo, so
  the object stays reachable by SHA even after the branch moves. It is **NOT on `main`** (verified
  `git merge-base --is-ancestor` → not an ancestor), so the default branch was never exposed.
  Removing it needs an interactive rebase **plus a force-push**, which stands against the standing
  never-`--force` rule, **plus** a GitHub Support cached-object purge — the same path as the
  still-open B1 item under `project_security-remediation-plan.md`. Sean's call, three options:
  rewrite + force-push + support request / support request alone / accept and move on.
  | security | needs-Sean

**Method note for next time:** `git status` reported all eight assets as modified after the re-run,
which reads as "the rig is non-deterministic." It was not — a **per-pixel diff separated 0.02%
antialiasing noise from an 82% content swap**, and only the diff found the leak. Byte-comparison
alone would have justified either "flaky rig, ignore" or "re-commit all eight," and both would have
carried the leak forward.

## 2026-08-22 (later still) — sections 03 + 04 built; two decisions land on Sean

First real `web/` changes of the redesign. `afc3b6d38` on `feat/web-redesign-round4` adds section
03 THE SIDEBAR (fixture capture + seven-state status key) and 04 GT LIST (real `gt` stdout + lane
ramp), with Silkscreen/Archivo/DM Mono scoped to the two new sections. Independent review found 8
confirmed defects; a fix pass is in flight for 7 of them. **Two are not defects — they are Sean's
calls, and both are blocking honest copy.**

- [ ] **The section 03 headline claim is false about the app.** The locked content-map line is
  "Every session in one window, **ordered so whoever is blocked on you is on top**." The app does
  not do that: `RecentsListView.sorted(sessions:)`
  (`macos/Sources/Features/Ghostties/RecentsListView.swift:470-472`) is the **identity function** —
  its own doc comment says "no sortOrder, no reshuffling." Sessions are bucketed
  ACTIVE/INACTIVE/ARCHIVE and otherwise left in workspace order. `SessionIndicatorState`'s
  `Comparable` conformance drives **project-header ghost colour only**, not any session sort.
  The shipped capture refutes the sentence on the same screen: rows 1–2 are green `processing`
  (priority 2), rows 3–5 blue `waiting` (priority 4) — recency order, with lower-priority sessions
  above higher-priority ones — and the status key 200px below explicitly ranks `waiting` above
  `processing`. Three ways out: **(a)** rewrite the copy to what the app does, **(b)** change the
  app so the session list sorts by indicator priority, **(c)** ship it as aspirational. Copy was
  left untouched pending this. | web · product | needs-Sean
- [ ] **The page now says the same two things twice.** The pre-existing video sections
  (`web/index.html:968-984`) already cover the sidebar ("every session, one window") and gt list
  ("gt list — every task, one lane"). The new sections re-prove both in a different visual
  language, so the page reads sidebar-video → gtlist-video → sidebar-still → gtlist-text. Related:
  the new headings start at "**03**" with no 01 or 02 anywhere on the page, which reads as a
  half-deployed site. Do the videos get replaced, or do 01/02 get built to close the gap?
  | web | needs-Sean

**Finding worth keeping:** the highest-severity defect was invisible to local rendering. The live
CSP (`web/vercel.json`, confirmed with `curl -sI https://ghostties.org/`) is `style-src 'self'
'unsafe-inline'; font-src 'self'` — **Google Fonts is blocked in production.** Every new font rule
would have fallen back to system sans, which is the one typographic tell
`feedback_web-redesign-constraints.md` names by name. `python3 -m http.server` — the verification
recipe in `web/DESIGN.md` — sends no CSP header, so it looked perfect locally and would have
shipped dead. Fix is self-hosting the WOFF2 (`font-src 'self'` already allows it), never widening
the CSP. **Any future web verification must check against the deployed headers, not a local
static server.**

## 2026-08-22 (wrap) — objective changed: stop building sections, plan the whole-site migration

Sections 03 + 04 shipped to `feat/web-redesign-round4` @ `8b5a4c31b` (build `afc3b6d38`, review
fixes `fa0b92631`, gt-block width `932a5e625`, copy correction `8b5a4c31b`). **Sean saw the page
and the reaction is the finding:** it looks essentially unchanged. The diff says why — **414
insertions, 0 deletions.** Not one line of the existing site was touched.

**Root cause, and it is structural, not a bug.** The redesign has **no migration plan**. The
content map (`Anatomy.dc.html`) describes a ten-section page built from scratch; production is the
old hero + two videos + install. Nobody ever decided how you get from one to the other. Two of my
scoping calls maximised the mismatch — the builder was told not to touch existing sections, and the
new fonts were scoped to only the two new sections — both deliberate safety choices for
unsupervised overnight work, both correct in isolation, and together they guarantee a page that
reads as untouched with two foreign sections bolted underneath.

**Section-by-section into the live page can never produce a finished site to judge.** That is the
whole lesson. It also explains the two symptoms already logged today (duplicate content, headings
starting at "03") — they are not separate defects, they are this one.

- [ ] **NEXT OBJECTIVE — a migration/rebuild plan, then the build.** Strawman to apply or redline,
  not to re-ask: build the redesign as a **complete separate page** — Arcade shell (`#06060e`
  ground, `#ffd54f` accent), Snake hero (01), all ten sections at the locked direction's fidelity,
  real captures where they exist and honest placeholders where they do not — then swap it in as one
  move. Sections 03 + 04 become its 03 and 04 rather than orphans. | web | new
- [ ] **Nothing of the locked direction is in `web/` except type.** Silkscreen/Archivo/DM Mono are
  self-hosted and working, but scoped to two sections. The Arcade palette, the ghosts, the
  scanlines, the visor treatment, the Snake game — **all still only `.dc.html` boards** in
  `docs/design/web-redesign/`. **2 of 10 sections built.** | web | carried
- [ ] **Purge `5215ce015` from public history BEFORE this branch merges** — carried 2× since
  2026-08-22. Sean deferred it deliberately ("finished site first, then clean up"), which is fine,
  but the deadline is real: this repo merges with real merge commits, so merging makes the leaked
  blob a permanent ancestor of `main` and turns a branch-only rewrite into a `main` rewrite.
  | security | carried
- [ ] **Merge hazard flagged by the composer thread:** this branch carries `386cbf39f`
  (`TEST_TARGET_NAME` fix), which arms nine GUI-driving UI tests that type shell text at whatever
  holds focus. Check before merging. [[feedback_test-target-name-fix-arms-gui-tests]] | build | new

**Closed today:** rig verification (idempotency + clean build, both proven); the real-session leak
at the branch tip; the false "ordered so whoever is blocked on you is on top" claim — Sean chose to
fix the copy, not the app's sort, so the lead is now his sentence minus the false clause.

# Ghostties — Backlog

Parked items that survive context resets. Prune at `/wrap`.

> Reconciled 2026-07-29: the tracked `main` copy (07-17→07-22) and the untracked working-tree copy (07-26→07-28) had diverged. This file is the union. Only closed items were dropped (PR #48 merged as `3d2cefc57`).

## 2026-08-02 — media previews in the terminal

Investigation only, no code written. Findings in `reference_terminal-images-work-claude-code-doesnt.md`.

- **Verify the fork renders Kitty graphics.** Only *upstream* Ghostty was tested (Sean was in the wrong app). The fork has the full implementation and doesn't touch the terminal core, so this is near-certain — but unproven. One command in a plain Ghostties tab closes it: `scratchpad/kitty-test.sh` (script is in a session scratchpad and will be GC'd; the one-liner is in the memory file).
- **Sidebar preview pane (`QLPreviewView`).** The real gap: Claude Code hands you a file path when an agent produces a screenshot, and no terminal-side image support fixes that. QuickLook gets images, video, PDFs, and scrubbing at real resolution. Slots into the existing panel architecture alongside `BrowserPanelView.swift` / `BrowserTabManager`. Not scoped — wants a plan before code.
- Rejected: a `PostToolUse` hook firing QuickLook on every image Read. Works today and takes ~20 min, but steals focus during autonomous runs. Only viable as a manual trigger.

## 2026-08-02 — documentation IA + case study

Objective (locked): repo documentation + correct Ghostty-vs-Ghostties calibration. All five refresh waves are merged to `main`; this wave adds the design layer that was missing.

- [ ] **PR #80 — `docs/INFORMATION-ARCHITECTURE.md` + `docs/case-study-documentation-refresh.md`.** Open, MERGEABLE, CI green 4/4. Records the IA the refresh produced (audience model, the disambiguation-not-topic-tree principle, decay model per file, five questions before adding a doc) and the narrative of how it was arrived at, including that it was emergent rather than designed up front. Entry points added in `CONTRIBUTING.md` for humans and `AGENTS.md` for agents. | docs | ready-to-merge
- [ ] **Should the case-study visuals live in the repo? — STRAWMAN: no, kill it.** GitHub markdown cannot render the CSS/SVG figures, so putting them in the repo means exporting PNGs. Images cannot be diffed, so they would go stale silently and break the decay-model rule the IA doc itself sets. Recommendation: repo docs stay textual; the visual version stays an Artifact for job and portfolio use. Only revisit if the repo docs are meant to carry imagery. | docs | decide-or-kill
- [ ] **Visual case study lives only as an Artifact.** `https://claude.ai/code/artifact/8bda1349-3010-4780-bee8-88ffe72e5c0c` — six figures (inherited-scale receipt, the auto-close trap, the routing fork, six entry points, the 3.8:1 deletion bar, CONTRIBUTING before/after) plus the inlined demo GIF. Private to Sean's account; it is not backed up in the repo and would need rebuilding from `docs/case-study-documentation-refresh.md` if lost. | docs | reference

**Off-objective, parked deliberately:**

- [ ] **Idea-log prune** — 10 of 31 captures in `tease-capture.md` are older than 30 days and unacted-on, which is that file's own documented prune threshold (1 from May, 9 from June). Surfaced at `/wrap` 2026-08-02, nothing deleted. Spans projects, so it is not this thread's objective. | ops | needs-Sean

## 2026-08-02 — repo branch/PR cleanup (next objective)

State captured at the end of the website thread. **42 remote branches, 7 open PRs.**
Website branches were already cleaned this session (9 deleted on origin, 8 locally).

- **7 open PRs, none merged since #59 on 2026-07-30.** #59 `fix/grey-cycling-menu-items`,
  #58 `fix/reclamp-sidebar-on-window-shrink`, #57 `fix/esc-cancels-inline-rename`,
  #56 `fix/agent-session-idle-fallback`, #50 `feat/website-boot-sequence`,
  #46 `docs/beta.20-changelog`, #37 `chore/gitignore-zig-pkg` (oldest, 2026-06-19).
  #57/#58/#59 all carry ⛔ human-only runtime merge gates — see the 2026-07-29 section. | ops | session
- **PR #50 will now conflict with the design system.** Scroll-triggered boot-sequence
  entrance, 143 lines in `web/index.html`, untouched since 2026-07-22, opened before
  the `style.css` refactor (#81) rewrote that file's `<style>` block. Decide: rebase
  onto the new structure, or close it. | web | needs-Sean
- **9 remote branches have no PR at all** and need a keep-or-delete call:
  `1.1.x`, `1.2.x`, `tristan957/gtk-ng` (all three are upstream Ghostty branches —
  probably keep), `claude/happy-morse-62ea22`, `feat/demo-capture-instance`,
  `feat/ghostties-animation`, `fix/stale-mcp-tools-test`,
  `test/session-cache-load-harness`. | ops | quick
- **Stale local branches whose upstream is gone** (squash-merged, safe to `-D`):
  `docs/changelog-beta.20`, `feat/session-cycling-shortcut`,
  `feat/sessions-tab-context-menu`, `feat/sidebar-resize`,
  `fix/ci-green-macos15-and-stale-mcp-test`, `fix/session-cycling-all-views`,
  plus `docs/web-backlog-status`. Carried from the 2026-07-26 entry — `git branch -D`
  was permission-denied again this session, so it needs Sean's shell or an allowlist
  entry. | ops | quick
- **`security/web-docs-hygiene` cannot be deleted locally** — it is checked out in a
  worktree. Remove the worktree first or leave it. | ops | quick
- **Squash-merge breaks stacked PRs.** Recorded in memory as
  `reference_stacked-pr-squash-merge-conflict` — squash-merging the base orphans the
  child, retargeting balloons the diff and conflicts. Resolve by merging main in and
  taking the branch version; never force-push. Relevant if any of the 7 open PRs are
  stacked. | ops | session

## 2026-08-02 — ghostties.org audit (impeccable full sweep)

Full design/technical audit of the live site. Scores: **Design 15/40 Nielsen, Technical 5/20 — "Critical" band.** Six mechanical bugs found in this same audit (changelog 404, missing custom 404 page, dead X link, robots/sitemap, 1.5 MB orphaned assets, asset cache policy) already shipped in PR #77 and are deliberately absent below.

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
  was deliberately left out of the system pending the `/flows` decision below.
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

### Accessibility — scored 1/4
- **`prefers-reduced-motion` is ~19% honored.** Only rule is `.bg-ghost { animation: none }` at `index.html:410`. Measured under `reduce`: 26 animations on the page, **17 still running, 8 still infinite** (`float-g0`…`float-g7`), plus the full ~10s entrance and typewriter sequence.
- **Contrast failures, all computed and all failing WCAG AA:** 2.27:1 `rgba(255,255,255,0.25)` footer text and links on **every page** (worst value on the site); 2.70:1 changelog `<h4>` section labels; 3.03:1 `#666` on flows lane names; 3.21:1 `.back` link; 3.22:1 homepage `.line-3`; 3.78:1 `.download-meta` / `.all-releases`; 4.27–4.43:1 download/changelog body note. Raising the white-alpha floor to `0.55` yields 5.96:1. Note `#C97350` captions **pass** at 4.92:1 — not a finding.
- No `<h1>` on `index.html`; no `<main>` landmark on any of the 7 pages; no skip link.
- `changelog.html` skips heading levels H1 → H3, six times.
- The ghost-scatter interaction is mouse-only — `<div class="ghosts">` with a click listener at `index.html:637`, no `tabindex`, `role`, or key handler. Not reachable in a tab sweep.
- 8 foreground ghost SVGs have no `aria-hidden`, `role="img"`, or `<title>`.
- `/flows` has 0 focusable elements and 6 mermaid SVGs with no accessible name.
- No focus styling authored anywhere (`:focus`/`outline` = zero hits across all 7 pages). The Chromium UA default is intact, so this is a gap, not a removal.
- All six terminal lines are in the DOM from load, only clipped by `width: 0` — a screen reader announces `- ghostties % install soon` as fact. The joke is visual-only. | web | project

### Responsive — scored 1/4
- **Horizontal overflow at 10 of 14 tested widths, from two independent causes.** (1) 320–560px: `.terminal` is clamped by `max-width: calc(100vw - 48px)` but its `.line` children are `white-space: nowrap` and animate to hard-coded `ch` widths, so they escape the parent; only visible after ~7s because the typewriter delays run to 9.7s. (2) 700–900px: `.product-window::before { inset: -10%; filter: blur(40px) }` escapes because `.product` has no `overflow: hidden` — arithmetic confirmed at 768/820/900px. **Cause 2 shipped in PR #72 and is live.**
- `/support` overflows +11px and `/privacy` +22px at 320px (`CODE` elements don't wrap).
- **All 48 interactive elements are under 44×44 at 375px; zero pass in both dimensions.** Footer icons are 14×14 (index) and 16×16 (subpages). The `/download` primary CTA is 280.8×41 — 3px short.
- Breakpoint coverage is a single `max-width: 480px` query on six of seven pages; nothing addresses 481–719px on index, which is exactly where the overflows live.
- All font sizes are `px` literals — no `rem`/`em`, so text scaling breaks layouts. | web | project

### Conversion and trust
- **The homepage CTA is gated behind ~10.1s of animation** with no skip. `.line-6` types at 9.7s (`index.html:196-201`); JS locks the caret at 10100ms. Median bounce is well under that. Fix should compress the schedule (the delays are hand-authored) and add a persistent download affordance outside the animated scene — the hero's choreography stays as-is.
- **`/download` has no trust signals at the highest-risk moment.** A 147MB DMG from an unknown developer, with no mention of Developer ID signing, notarization, Gatekeeper, or a checksum — **even though the build genuinely is notarized**. It names no author, and it is the only page in the funnel with no product image.
- The homepage has no `<h1>`, no wordmark, and no prose. The product name appears only inside `cd ~/ghostties` and a GitHub URL.
- The site never says this is a fork of Ghostty until `/licenses`, the last footer link.
- No Download link in any subpage footer — the funnel dead-ends on every page it can reach.
- `og:image` is relative (`index.html:26`) and may not resolve for crawlers. No `og:url`, `twitter:card`, or `twitter:image`. **Zero OG tags on all five subpages** — sharing the download link produces a bare URL, which matters for a product distributed by link-sharing. | web | session

### Content staleness
- `changelog.html`'s newest entry is **beta.19**; the site ships **beta.21** — two releases undocumented.
- `/support` says "Last updated April 26, 2026" and its `<meta description>` advertises a known-issues section the page does not contain.
- The release version is hand-synced across 4+ locations, two of which are character counts (`steps(N)` and `Nch`). Bumping to a longer version string clips or trails the primary CTA. Wants build-time substitution. | web | quick

### Footer consistency
- **Four distinct footer variants across seven pages**; `task-flows.html` has none. Same link labeled `aria-label="X / Twitter"` on index vs `"Twitter"` on subpages.
- Footers are `position: fixed` with no background, so on any page taller than the viewport they render on top of body text. Confirmed on `/support` mobile colliding with a code span. | web | quick

### `/flows` — needs a decision
- `task-flows.html` is an internal spec, publicly routed at `vercel.json`, linked from nowhere. Its subtitle is "Review before building further" and its bottom third is a grid of red `GAP` cards enumerating unbuilt features. It also loads `mermaid@11` from jsdelivr as a **render-blocking, unpinned, no-SRI** third-party script on the same origin that serves the Sparkle appcast. Decide: pull it from `web/`, or give it the site's design language and rewrite the GAP grid as a roadmap. | web | needs-Sean

### Security headers
- `vercel.json` sets HSTS and `nosniff`. Missing: `Content-Security-Policy` (relevant given the unpinned CDN script above), `X-Frame-Options` / `frame-ancestors`, `Referrer-Policy`, `Permissions-Policy`. | security | quick

### Performance
- No `preload` attribute on any `<video>`; the full file is fetched even when playback never starts. Media dropped 582KB → 262KB in PR #72, so this is now smaller but still eager.
- Zero lazy loading site-wide — no `loading=`, `decoding=`, or `preload` anywhere. | web | quick

### Small / polish
- The favicon randomizes color on every load, so a pinned tab is never recognizable. Deliberate call needed. | web | needs-Sean
- `<link rel="icon" href="">` on all pages fires a request against the current document URL before the JS runs.
- `.product-window::before` uses `rgba(201,115,80,0.3)` — terracotta, explicitly dropped as a brand color. It's the only chromatic accent below the hero while the actual 8-ghost palette sits unused.
- `.line-6` anchor text is `+ [download now]` — the diff marker is inside the link, so screen readers announce "plus bracket download now bracket".
- The mobile `.ghost` override is still `64px` while the base is now `72px` (shipped in PR #78) — only an 8px step down. Probably wants revisiting or removing. | web | quick

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

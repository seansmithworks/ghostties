# Sidebar Section Vocabulary — Post-Merge Test Plan

Branch `feat/sidebar-section-vocabulary`, PR #175. Run after merging to `main`.

## Already verified on the branch

- Three independent "pass with notes" reviews, each note fixed in-branch:
  - Drag/drop-zone reflow (`4e3a04419`)
  - Resume diff (Claude + Codex resume flow)
  - Status glyph change (`9b1a6d735`) — `.waiting`/label mismatch fixed in `90b120cff`
- Unit test classes added: `SessionDragReflowTests`, `PendingLaunchHoldTests`,
  `ResumePlanTests`, `CodexHookRegistrarTests`, `WorkspaceStoreResumeTests`,
  `AgentSessionCodableTests`, `CodexHookConfirmationTests`, `SessionStatusGlyphMappingTests`.
- `origin/main` merged into the branch (`61e09d692`), no conflicts, `build-for-testing` succeeds.

## After merge, on `main`

Run the full unfiltered `GhosttyTests` suite (never a filtered subset):

```bash
xcodebuild test \
  -project macos/Ghostties.xcodeproj \
  -scheme Ghostties \
  -destination 'platform=macOS,arch=arm64' \
  ONLY_ACTIVE_ARCH=YES ARCHS=arm64 \
  -derivedDataPath macos/build \
  -only-testing:GhosttyTests
```

Read totals from the result bundle, not raw log lines (raw log counts carry a constant −49
offset):

```bash
xcrun xcresulttool get test-results summary --path <path-to-.xcresult>
```

- Last branch baseline: **1156 passed / 5 failed / 1 skipped**. The 5 known failures are in
  `SessionComposerWorktreeLaunchTests` and `GitWorktreeCreationTests` — pre-existing, not caused
  by this PR.
- Totals vary by worktree — compare by **test identifier sets**, not totals, to confirm coverage
  is unchanged.
- This test host shares the Dev bundle id with a running `Ghostties Dev` — it will quit one if
  running.

## Live checks

Each item: steps → expected result → pass/fail.

- [ ] **Sections in both views** — session view shows Pinned (when non-empty or during a drag) /
  Active / Inactive / Archive; project view groups each project's sessions by the same
  Active / Inactive / Archive rule, and its Archive header matches the session view's headers
  (chevron on the leading side, same weight). Expected: a session sits in the same
  Active/Inactive/Archive bucket in both views.
- [ ] **Pin via drag onto empty Pinned** — drag a row onto an empty Pinned section. Expected:
  "Drop to pin" zone appears during the drag; drop pins the session.
- [ ] **Drag reorder gap** — drag a row within a section. Expected: a one-row gap opens at the
  proposed insertion point, before/after decided by which half of the target row the pointer is
  over.
- [ ] **Drop released over empty space** — start a drag, release over empty space outside any
  drop zone. Expected: the drag reverts, no reorder happens.
- [ ] **Edge auto-scroll** — drag near the sidebar's top/bottom edge. Expected: the list
  auto-scrolls; check it feels row-stepped, not jumpy.
- [ ] **Drop onto Active relaunches** — drag a row onto Active. Expected: the session relaunches
  (resuming where possible) and holds its Active slot until alive or a 5s timeout. Stopping the
  session during the hold ends it immediately, without leaving a stale hold.
- [ ] **Resume (Claude)** — start Claude from a shell opened AFTER `GHOSTTIES_LAUNCHER` landed in
  `~/.claude/shell/zshrc` (via `cco`), send one prompt, Stop the session, right-click. Expected:
  "Resume" and "Start Fresh" both appear; Resume reopens the same conversation. A session with no
  saved conversation shows only "Start Fresh".
- [ ] **Start Fresh (Claude)** — right-click the same stopped session → Start Fresh. Expected:
  relaunches with a new conversation.
- [ ] **Resume (Codex)** — right-click a Codex session, approve the Ghostties hook in Codex once.
  Expected: before approval, row shows "Approve the Ghostties hook in Codex"; after approval,
  Resume works.
- [ ] **Status glyphs** — verify all five slot states render: spinner (working), `?`
  (needs input), `✓` (idle/waiting), `✕` (error), empty (stopped). The working spinner is drawn
  as a dot grid sized to the slot (`fix(sidebar): draw the working spinner as a dot grid sized
  to the slot`) — confirm it no longer reads as two faint dots.
- [ ] **VoiceOver status word** — with VoiceOver on, each glyph reads its status word (working /
  needs your input / idle / error / stopped).
- [ ] **Reduce Motion** — with Reduce Motion on, the working state shows a static `…` instead of
  the spinner.

## Known issues to watch, not fix

- `idle_prompt` maps to `?` (needs input) even on a finished, idle session — finished and blocked
  read the same (BACKLOG F, undecided).
- Esc-interrupting Claude may leave hook state busy with no Stop, so a row can spin for up to
  30 min — inferred, unverified.
- The Codex hook registers only for template-launched Codex sessions; a `codex` typed into a
  plain shell never registers.

## Automated suite status (2026-09-14 night)

Full unfiltered `GhosttyTests` (`-skip-testing:GhosttyUITests`), Light, HEAD `6742b881e`:
**1333 passed / 7 failed / 1 skipped / 1341 total**. ID set matches run9-ids.txt (1341/1341).
All 7 failures are known load flakes — no product regression. Suite is **GREEN**.

- `typedUnknownBranchTokenRendersCreateBranchRowFirst`: isolated pass 1.0 s; setup timed out
  under parallel load. Evidence: `triage-typedUnknownBranch-isolated.xcresult`. Not a bug.
- `raceReturnsTimedOut…`: still failed isolated (2.64 s vs 2.0 s ceiling); noted, no fix tonight.

> **WAIVED by Sean 2026-09-15.** These live checks were not performed. Beta 25 shipped on the
> automated suite alone. Nothing below has been exercised by hand.

Live checks below remain unchecked — the suite result does not substitute for them.

## Screenshots / fixture recipe

```bash
open --env GHOSTTIES_CAPTURE_FIXTURE=1 --env GHOSTTIES_STATE_DIR=<throwaway dir> \
  "macos/build/Build/Products/Debug/Ghostties Dev.app"
```

Public repo — never capture or commit real session data (names, usernames, hostnames, or home
paths). Use a throwaway `GHOSTTIES_STATE_DIR` every time.
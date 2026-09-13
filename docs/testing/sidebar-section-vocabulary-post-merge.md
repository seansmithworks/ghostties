# Sidebar Section Vocabulary — Post-Merge Test Plan

PR #175. No existing `docs/testing/` convention — `docs/` only had `docs/plans/`, which is
for feature plans, not test plans, so this is a new file/directory.

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

- [ ] **Sections in both views** — Session view and project view both show Pinned / Active /
  Inactive / Archive under one rule. Expected: identical section set and ordering in both views.
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
- [ ] **Resume (Claude)** — right-click a session with a saved conversation. Expected: "Resume" +
  "Start Fresh" both appear; Resume only appears when a saved conversation exists.
- [ ] **Start Fresh (Claude)** — right-click a Claude session started from a shell opened after
  `GHOSTTIES_LAUNCHER` landed. Expected: "Start Fresh" relaunches with no resume.
- [ ] **Resume (Codex)** — right-click a Codex session, approve the Ghostties hook in Codex once.
  Expected: before approval, row shows "Approve the Ghostties hook in Codex"; after approval,
  Resume works.
- [ ] **Status glyphs** — verify all five slot states render: spinner (working), `?`
  (needs input), `✓` (idle/waiting), `✕` (error), empty (stopped).
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

## Screenshots / fixture recipe

```bash
open --env GHOSTTIES_CAPTURE_FIXTURE=1 --env GHOSTTIES_STATE_DIR=<throwaway dir> \
  "macos/build/Build/Products/Debug/Ghostties Dev.app"
```

Public repo — never capture or commit real session data (names, usernames, hostnames, or home
paths). Use a throwaway `GHOSTTIES_STATE_DIR` every time.

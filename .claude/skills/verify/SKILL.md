---
name: verify
description: Verify a Ghostties (macOS Swift fork of Ghostty) sidebar or UI change by launching the Debug "Ghostties Dev" app in capture-fixture mode and screenshotting its window. Use after any change under macos/Sources/Features/Ghostties/ or the sidebar integration points, before reporting UI work done.
---

# verify (Ghostties)

Surface: the macOS app, Debug "Ghostties Dev" (bundle id `com.seansmithdesign.ghostties.dev`, process name `ghostty`). Not simctl. Launched in fixture mode (`CaptureFixture.swift`): invented projects/sessions, canned terminal transcript, no real user data.

All mechanics are in `.claude/skills/verify/run.sh`. Run it from the repo/worktree root.

## Build prerequisites (fresh worktree)
`up` builds the app itself but fails with one line if an input is missing or stale. It never builds zig.
- `macos/GhosttyKit.xcframework` and `zig-out/` (needs `zig-out/share`): copy with `cp -Rp` from a tree with a fresh engine. Stale means `libghostty-internal.a` is older than the last commit touching `src/`. To build one: `PATH=/opt/homebrew/opt/zig@0.16/bin:$PATH zig build -Doptimize=Debug -Demit-macos-app=false -Demit-xcframework=true` (~2 min on zig 0.16; the default zig 0.15.2 fails).
- `vendor/cef` and `vendor/cef-build`: symlink from the main checkout.

## Launch
```
VERIFY_SIDEBAR_MODE=pinned VERIFY_SIDEBAR_TAB=sessions .claude/skills/verify/run.sh up
```
Env knobs: `VERIFY_SIDEBAR_MODE=pinned|collapsed|closed` (`closed` needs ~10s to settle), `VERIFY_POPOVER=needs-bash|needs-edit|running|done`, `VERIFY_SIDEBAR_TAB=sessions|projects`, `VERIFY_BUILD=0` to skip xcodebuild when the app is already built from this tree.
Launch-state hooks (DEBUG only, `CaptureFixture.swift`; each calls the action its click or shortcut calls, once per launch; names are fixture projects: atlas-api, fieldwork, pendulum, silo, switchboard, trove, wren):
- `VERIFY_EXPAND_PROJECT=<project>`: expands and selects that project (implies `TAB=projects`).
- `VERIFY_COMPOSER=open|prefilled:<project>[:delay=<s>]`: `open` is the tray +, `prefilled:` is a project row's +. Fires 1s after the window appears unless `:delay=` says otherwise.
- `VERIFY_PROJECT_SETTINGS=<project>[:templates-edit|:templates-delete]`: opens that project's settings popover; a suffix also opens the template edit sheet or delete alert for the first user template (first template if none; a built-in gets "Duplicate and Edit...", as its menu offers). Implies `TAB=projects`.
- `VERIFY_SIDEBAR_TOGGLE_AFTER=<s>`: runs Cmd+S's action after N s (pinned to rail), again after 2N s (back).
`up` launches the binary directly (not `open`, which only focuses a running Dev build sharing the bundle id), strips `GHOSTTIES_SESSION_ID`/`GHOSTTIES_LAUNCHER`, sets `GHOSTTIES_STATE_DIR` to the evidence dir, records the pid, and records the old `ghostties.sidebarTab` value if a tab was requested. Mode is fixed at launch: one flow = one `up`/`down` cycle.

## Doctor
`run.sh doctor`: pid alive, runs this tree's binary, has a real window. Nonzero exit with one line why.

## Drive
Each flow is `down`, `up` with that flow's env, `doctor`, wait ~5s, `shot <name>`. Then Read the PNG.
- **A. Expanded sidebar, Sessions tab** (`MODE=pinned TAB=sessions`). Look for: Active/Inactive/Archive sections; status glyphs (spinner, `?`, check, x) on the right edge of rows, with the hover/selected row showing a kebab instead; tray at the bottom with + / folder / gear / sidebar; 8pt card margin; sidebar bg follows the terminal theme. Fixture "Claude Code 6" is the `?` row.
- **B. Collapsed rail** (`MODE=collapsed TAB=sessions`). Look for: ~128pt-ish narrow rail, glyphs centered in the rail (not right-aligned), section chevrons, and the tray as a thin centered pill with + / folder / gear / sidebar stacked.
- **C. Projects tab** (`MODE=pinned TAB=projects`). Look for: project list instead of sessions; same tray.
- **D. Popover states** (`MODE=pinned POPOVER=<needs-bash|needs-edit|running|done>`, one launch each). Look for: card anchored to its row, tool/command or file path (needs-*), prompt + current step (running). `done` shows no card by design. If the popover is its own window, the largest-window capture misses it: check the first PNG.
- **E. Expanded project** (`MODE=pinned EXPAND_PROJECT=switchboard`). Look for: session rows under the project with type glyphs on the right, not ghosts. The Projects tab reads `coordinator.indicatorState(for:)`, not the fixture's seeded states, so these rows show checks where the Sessions tab shows spinners.
- **F. Composer** (`COMPOSER=open` or `COMPOSER=prefilled:switchboard`). Look for: single-line card centred in the window; the Witness ghost on the card is grey for `open` and the project's ghost for `prefilled`. For the open animation: `COMPOSER=open:delay=4`, then `video <name> 7` right after `up`.
- **G. Project settings** (`PROJECT_SETTINGS=switchboard`, then `:templates-edit`, `:templates-delete`). Look for: the Templates section; with a suffix, whether the popover is still on screen behind the sheet/alert. The popover, sheet and alert are child windows and the main-window shot includes them; `swift .claude/skills/verify/windows.swift <pid>` lists them.
- **H. Sidebar toggle video** (`MODE=pinned TAB=sessions SIDEBAR_TOGGLE_AFTER=4`, then `video <name> 10` right after `up`). Look for: width animation both ways, glyphs moving to the rail centre and back. Find the transitions with `ffmpeg -i <mp4> -vf "select='gt(scene,0.003)',showinfo" -f null -`.
Also check the PNG for regressions in the area you changed, not just the checklist.

## Capture scripts, focus clips, contract report (composer harness)
- `run.sh script <file.json>`: launches like `up` (same env knobs) with `GHOSTTIES_CAPTURE_SCRIPT=<abs path>`. The app announces each `mark` op in `state/marks.jsonl`; `run.sh` shoots `shots/<name>.png`, then touches `state/marks/<name>.done`. Returns 0 on `script.done`; non-zero on `script.error`, app exit, or `VERIFY_SCRIPT_TIMEOUT` (default 120s). The app stays up either way: read `state/dispatch.jsonl`, then `down`. Ops and handshake: `beta26-test-harness/capture-script-schema.md` (memory folder). Step files live in `beta26-test-harness/steps/`, not in the repo.
- `run.sh video <name> <s> --focus x,y,w,h`: the usual full clip plus `<name>.focus.mp4`, a crop of that rect (window points, top-left origin) scaled by the backing scale and upscaled to 1080px wide for a phone.
- `run.sh report <contract.md>`: runs `contract-report.py`, which reads `status.json` beside the contract and writes one self-contained phone-width HTML page (`$VERIFY_REPORT_OUT`, default `<evidence>/report.html`): SEAN rows first, then FAIL, PENDING, PASS, PNGs inlined, no video.
- `contract-check.sh [memory-folder] [--require-signed]`: the tag gate. Exit 0 only if the contract sha256 equals `status.json.approved.sha256`, every table row except those under "P1 rows" is PASS (a `SEAN` row is never PASS), and `status.json.suite` holds an unfiltered `-only-testing:GhosttyTests` xcresult whose `xcresulttool get test-results summary` has no failures (totals are printed). SEAN rows print as signed (`"signed": true`) or pending; `--require-signed` makes pending ones fail.

## Evidence
`/tmp/verify-ghostties-<hash of tree path>/`: `shots/<name>.png`, `build.log`, `app.log`, `state/`. `shot` captures only the largest on-screen window of the recorded pid via `screencapture -x -o -l <windowid>` (the first windows found are a blank one and a 33pt menu-bar strip). Never full-screen. `video <name> <s>` records the same window with `screencapture -v -V <s> -l <windowid>` (the .mov includes the window shadow margin; macOS draws its recording pill over the traffic lights) and converts it to a ~1400px H.264 `<name>.mp4`. Evidence is never committed (public repo).

## What this can't reach
Needs a new launch hook (see `docs/plans/headless-smoke-harness.html`) or Sean: hover states, typing into the composer, the click-to-action wiring itself (a hook proves the state, not that the button calls it), anything else needing a click or key.

## Gotchas
- **No synthetic input, ever**: no keystrokes, clicks, AX actions, System Events. An agent once typed into Sean's live session, and Cmd+Q once hit his real Ghostties. Stop Dev with `kill <pid>` only (`down` does this).
- Never `killall ghostty`: that is also Sean's daily-driver process name. `up` refuses if another Dev is running (it would occlude yours); ask Sean to quit it.
- Never touch `/Applications/Ghostties.app`, the `com.seansmithdesign.ghostties` (Release) domain, or `com.mitchellh.ghostty`. Only the `.dev` domain is read/written, only for the sidebar tab, and restored by `down`.
- Tests: if you run any, use `xcodebuild test ... -only-testing:GhosttyTests`. Never the UI test target: it raises a password prompt that blocks all testing. Swift Testing filters need a trailing `()`.
- Display asleep gives black captures; `up`/`shot` check for it.
- Seen once in a collapsed capture (1 of 2 runs): whole terminal pane rendered with a blue selection highlight. Did not reproduce; if you see it, retake before reporting it as a bug.
- The debug-build banner at the top of the terminal is expected.

## Teardown
`run.sh down`: kills the recorded pid, restores the sidebar tab default, diffs `git status --porcelain` against the `up` snapshot (nonzero on drift), keeps evidence. Run it after any failed try.

# CEF crash — strategy and overnight plan (2026-09-01)

**Verdict.** Sean's Release CEF profile was written by **Chromium 150** and is being opened by **Chromium 144**. The Aug 1 security pin (`b174f0937`, PR #60) swapped the "latest stable" CEF download for a fixed 144 build; Chromium does not support profile downgrades, and a 144 startup task against 150-era data ends in a deliberate process quit ~0.4s after `CefInitialize` returns — before `CreateBrowser`, so the merged sentinel (#159) never arms. Fix = a pre-init **downgrade guard** that moves a newer-version profile aside, plus the sentinel re-anchored around `CefInitialize`. The `exit_type: Crashed` hypothesis is dead.

## 1. Diagnosis

- **Confirmed — downgrade.** `CEF-backup-2026-09-01/Default/Preferences` → `extensions.last_chrome_version = "150.0.7871.129"`, mtime Aug 1 00:47 (frozen since). `vendor/cef/include/cef_version.h` → `CHROME_VERSION_MAJOR 144`. Pin commit text: the server "previously chose latest stable at build time". `Local State` `variations_crash_streak = 9`.
- **Confirmed — Dev is not a fixture.** Dev profile reads `144.0.7559.258`, no crash streak: it was never downgraded. Its afternoon 3/3 death was a different, decayed poison. Only the Release backup is a stable fixture — and it is stable *because* 144 never lives long enough to rewrite `Preferences`.
- **Confirmed — a deliberate quit, not a fault.** No `.ips`, no signal handler, no `atexit`, `runningboardd` `proc_exit` → `_exit`-class termination. Timeline (22:55:34): `.083` profile init inside `CefInitialize`; `.261` `CEF initialized.`; `.349` last Ghostties line; `.390` blockfile warning; `.702` helpers report "parent died". Death is asynchronous, on the UI thread our pump drives, after `initializeIfNeeded` returned and before `CEFBrowserView.mm:499`.
- **Killed — `exit_type: Crashed`.** CEF's `chrome_runtime.patch` wraps `browser_creator_->Start(...)` in `#if !BUILDFLAG(ENABLE_CEF)`: session restore, crashed bubble and `StartupBrowserCreator` never run. `ExitTypeService` only reads/writes the pref. The on-disk value is the last successful flush, not the last run. `exited_cleanly = true` is noise: metrics recording is off under CEF.
- **Inferred — mechanism (moderate on class, low on frame).** 150-era data makes a 144 startup task take and release a `KeepAlive` (web-app/extension reconciliation are the candidates) while zero `Browser` objects exist. CEF's Chrome bootstrap also removes `AppController` (the Mac keep-alive) and skips the startup browser, so the 1→0 edge reaches `BrowserProcessImpl::Unpin` → main-loop quit → shutdown → `_exit`. Experiment E1 pins the frame; the fix does not depend on it.
- **Why #159 could never catch it:** the sentinel is written after `initializeIfNeeded` succeeds; the process is dead before line 499.

## 2. Experiments (cheapest first; each against a fresh `cp -Rp` of the backup)

Oracle per run: own PID alive at T+20s = SURVIVED; `ghostties-cef-internal.log` "parent died" + PID gone = DIED. Two runs per arm.

- **E0 baseline** — untouched copy → must DIE 2/2, else stop (fixture decayed; re-derive before anything else).
- **E1 mechanism** — launch the lab copy under `lldb` with `b _exit`, `b exit`, `b abort`, `b kill`; on stop, `bt 60`, `thread list`, `image list` → the frame that quits. Exit status vs signal also settles "was it SIGKILL". Free, decisive.
- **E2 kill-check** — `profile.exit_type` → `"Normal"` only → still DIES (expected; if it survives, section 1 is wrong and E1's frame says why).
- **E3 version flip** — `extensions.last_chrome_version` → `"144.0.7559.258"` only → SURVIVES = version string itself gates the path; DIES = other 150-era data does.
- **E4 Preferences swap** — replace `Default/Preferences` with one from a fresh-144 run → SURVIVES = poison is in Preferences; DIES = elsewhere.
- **E5 halving** — only if E4 dies: remove `Default/` vs everything-but-`Default/`, then halve inside the survivor. ≤6 arms.
- **E6 switches** — only if E1 names a feature: `--disable-features=<it>` via `OnBeforeCommandLineProcessing`. Not a fix, a confirmation.
- **E7 cefclient** — only if E1 is unreadable: build `vendor/cef/tests/cefclient` (needs `brew install cmake`, free) with `--cache-path=<copy>`; DIES = pure Chromium+data, SURVIVES = needs our no-browser window.

## 3. Fix (one decision)

- **Downgrade guard, before `CefInitialize`.** Own a stamp `<appsupport>/cef-profile-chromium-version` written after the first `OnAfterCreated`. On init: stamp major (fallback: `Default/Preferences` `extensions.last_chrome_version`) > `CHROME_VERSION_MAJOR` → move `CEF/` to `CEF-downgraded-<ts>/`, start fresh, `os_log` one `[CEFBridge]` line. Cookies-only data; no prompt.
- **Re-anchor the sentinel** to bracket `CefInitialize`: write before it, clear on `OnAfterCreated` and in the 3s creation watchdog (process alive = not this crash). Keeps recovery for unknown poisons. Keep `resetProfileDirectoryPreservingDataError` and the recovery view, but make it render (the four constraint conflicts named in `BACKLOG.md`).
- **Why not the alternatives.** Rewriting prefs pre-init treats one key while 150 wrote ~30 files. Command-line switches disable a Chromium feature we don't own and break on the next roll. Removing the sentinel discards the only net for poisons we haven't seen. Rolling CEF forward to 150 masks the class and reopens #60.

## 4. Observability (Phase 1, ships in Release, env-gated)

- `[CEFDiag]` probes: `#if DEBUG` → `getenv("GHOSTTIES_CEF_DIAG")`, `os_log` with `%{public}`. `atexit`/signal handlers stay Debug-only.
- Add `[CEFBridge]` `os_log` at: pre-`CefInitialize`, post-return, every 250ms for 3s after (pump alive-ticks), guard decision, sentinel write/clear.
- `GHOSTTIES_CEF_APP_SUPPORT_DIR` overrides `_appSupportBundleDirectory` (profile + sentinel + stamp move together); resolved path logged.
- `GHOSTTIES_CEF_LOG_VERBOSE=1` → `LOGSEVERITY_VERBOSE` + `--vmodule=browser_shutdown=2,keep_alive_registry=2,browser_process_impl=2`.
- `GHOSTTIES_DEBUG_AUTO_OPEN_BROWSER=1` in `WorkspaceViewContainer.swift`: drop the `#if DEBUG`, keep the env gate. This is how a Release-signed build opens the browser with zero GUI driving.
- Read back: `/usr/bin/log show --predicate 'eventMessage CONTAINS "[CEF"' --info --debug --start <t>`.

## 5. Phases (T2 Sonnet implements, T1 Opus reviews each; overnight, unattended)

**Constraints for every phase.** Never `killall ghostty`/`ghostties` — SIGTERM only the PID this run launched. Never synthetic input or AX driving; `screencapture` only. Never modify `.../ghostties/CEF-backup-2026-09-01` or `.../ghostties/CEF`; experiments run on copies under the scratchpad via `GHOSTTIES_CEF_APP_SUPPORT_DIR`. Public repo: never commit profile contents or logs with URLs/cookies. Commits and pushes to `origin` only; never `upstream`; no `gh release`, no prod. `pgrep`/`ps` cannot see Ghostties — use `osascript -e 'tell application "System Events" to get unix id of every process whose bundle identifier is "com.seansmithdesign.ghostties"'`. Build `Release` with `ARCHS=arm64`, never `ReleaseLocal`; re-sign the COPY: `codesign --force --sign - --entitlements macos/GhosttyReleaseLocal.entitlements <copy.app>` (lab copy adds `com.apple.security.get-task-allow` from a scratch entitlements file so lldb can attach). Verify every binary: `strings <app>/Contents/MacOS/ghostty | grep -c CefInitialize` ≠ 0. `xcodebuild` to a log file, `set -o pipefail`, assert exit 0. Before the first launch: assert no real Ghostties running (osascript above), `df -g /` ≥ 15, back up all non-`CEF*` files in the app-support dir; restore them after the last run if changed.

**P0 — Preconditions (15 min).** Outcome: stable fixture proven. Touch nothing. Accept: launchd/RunningBoard exit record for pid 69891 captured (exit code vs signal, `/usr/bin/log show`); E0 DIED 2/2 on the *unfixed* `main` lab build. Stop: E0 survives → stop, report.

**P1 — Observability + lab controls.** Files: `CEFBridge.mm`, `CEFBridge.h`, `CEFBrowserView.mm`, `WorkspaceViewContainer.swift`, `scripts/debug/cef-repro.sh` (accept Release copies; drop the `.dev` bundle-id refusal behind a flag). Off-limits: everything else. Accept: lab copy launched against an empty override dir logs pre/post-init lines and alive-ticks (`log show`); `Local State` appears under the override path (mtime); `strings` count ≠ 0. Stop: no `[CEF` lines in Release → fix gating before proceeding.

**P2 — Experiments.** No source changes. Accept: one Markdown table in the PR body, arm × result × artefact (backtrace file path, log excerpt, exit code). E1 backtrace saved to scratchpad with paths/URLs scrubbed. Stop: E1 shows a signal from outside the process → section 1 is wrong; write findings, skip to P4 with observability only.

**P3 — Fix.** Files: `CEFBridge.mm/.h`, `CEFBrowserView.mm`, `BrowserFailureStateView.swift`, `CEFBrowserSentinelTests.swift` (+ a version-compare test that names the production symbol and fails when the comparison is inverted). Off-limits: `download-cef.sh`, `vendor/`, entitlements, pbxproj. Accept: fresh backup copy + fixed lab build → SURVIVED 3/3 (`OnAfterCreated` logged, PID alive at T+20s), `CEF-downgraded-*` sibling exists, stamp file reads `144`; second launch on the same dir → no move, SURVIVED; `xcodebuild test` run unfiltered, totals reported via `xcresulttool`. Stop: any DIED → back to E1 with the fixed build; do not tune blind.

**P4 — Ship.** Branch `fix/cef-downgrade-guard`, PR against `main` on `SeanSmithWorks/ghostties` with the E-table and P3 evidence; no screenshots of browser content. Build a second Release copy signed with the plain `GhosttyReleaseLocal.entitlements` at `/Applications/Ghostties-fix.app` (no override env → Sean's real profile). Screenshot the running window via `screencapture -l <CGWindowID>` to `docs/plans/evidence/` — if composer C needs a keystroke to appear, do not press it; leave Sean the recipe ("⌘N in Ghostties-fix.app"). Delete lab copies and worktrees; update `BACKLOG.md`. Accept: PR URL, `/Applications/Ghostties-fix.app` `strings` count ≠ 0, `git checkout main` clean.

## 6. What would make this wrong

- **It's the crash streak / safe-mode state, not the 150 data.** Separator: fresh-144 profile with only the backup's `Local State` dropped in → DIES = streak; SURVIVES = data.
- **It's our zero-browser window, and any startup keep-alive edge would kill us regardless of version.** Separator: E7 — cefclient (browser created at `OnContextInitialized`) on the same copy SURVIVES while the app DIES.

**Decision for Sean (recommended answer):** on downgrade, reset silently with one inline notice line (yes) vs. offer a button (no — the button is a second failure surface, see BACKLOG's invisible fallback).

Demoted: Chromium source citations and the raw log excerpts live in the memory memos linked from `MEMORY.md § Browser / CEF`.

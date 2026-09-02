# P2 — Experiment ladder (2026-09-02)

Lab build: `Ghostties-p1.app` (verified `strings … | grep -c 'CefInitialize\|CefBrowserHost'` = 6 before use). All runs launched the binary directly (`.../Contents/MacOS/ghostty &`, PID captured from the shell — never `open`, never bundle-id enumeration for scoring) with `GHOSTTIES_CEF_APP_SUPPORT_DIR` set to a scratchpad copy and `GHOSTTIES_DEBUG_AUTO_OPEN_BROWSER=1`. Oracle: PID alive at T+20s = SURVIVED; PID gone (+ `parent died` in helper stderr, when captured) = DIED. Real Ghostties (pid 7205) confirmed running throughout and never touched.

| Arm | What was changed | Run 1 | Run 2 | Time-to-death (init → helper "parent died") | Artefact path |
|---|---|---|---|---|---|
| **E0** baseline | Fresh untouched copy of `CEF-backup-2026-09-01` | DIED (pid 70771) | DIED (pid 71681) | 0.53s / 0.41s | `lab/E0/run{1,2}-stdout.log` |
| **E3** version flip | `Default/Preferences` → `extensions.last_chrome_version` = `"144.0.7559.258"` only; everything else (incl. `exit_type: Crashed`) untouched | DIED (pid 72940) | DIED (pid 73607) | 0.43s / 0.42s | `lab/E3/run{1,2}-stdout.log` |
| **E4** Preferences swap | `Default/Preferences` replaced wholesale with the clean-144 control's file (from the P1 surviving run, `appsupport-p1/CEF/Default/Preferences`) | DIED (pid 74465) | DIED (pid 75274) | 0.39s / not captured* | `lab/E4/run{1,2}-stdout.log` |
| **E2** kill-check | `profile.exit_type` → `"Normal"` only; `last_chrome_version` left at `150.0.7871.129` | DIED (pid 76632) | DIED (pid 77376) | not captured* | `lab/E2/run{1,2}-stdout.log` |
| **E1** mechanism (lldb) | Breakpoints on `exit`/`_exit`/`abort`/`kill` across a lab copy re-signed with `get-task-allow` | **Inconclusive — abandoned** | — | — | `lab/e1-lldb-cmds.txt`, transcript path noted below |

\*E4-run2, E2-run1, E2-run2 scored DIED by PID-liveness (the primary oracle) but the helper's `Mach rendezvous failed, terminating process (parent died?)` stderr line wasn't captured in that window (buffering/reap race, not a different outcome) — all other captured runs land in the same ~0.39–0.53s band, so these are consistent with, not contradicting, that window.

## E1 — abandoned, not a contradiction

Breakpoints on the generic `exit`/`abort`/`kill` symbols matched 9–39 locations each across a multiprocess Chromium/CEF binary and fired continuously from ordinary per-thread activity (dozens of hits/second, plus new locations added as libraries load) with no way to isolate the fatal call inside the ~15-minute budget. I killed the debug session at that point rather than let it run further; killing `lldb` also killed the debuggee (pid 80188) — confirmed gone via `ps -p`, no orphan. This does not change P0's finding (exit status 0, no signal, `runningboardd`-observed clean termination): E1 was asked only to name the frame, not to re-litigate whether it's a clean exit. Recommend a **unit-test-level** follow-up instead of more lldb time: a Chromium `KeepAliveRegistry` observer/counter test would name the exact edge without fighting breakpoint noise.

## What this means for the P3 fix

**Keying the guard solely on `extensions.last_chrome_version` is not sufficient. The guard must move the whole profile aside.**

- E3 (version string alone rewritten to 144) still DIED 2/2 — the crash does not require the version string to read 150; other 150-era on-disk state reproduces it on its own.
- E4 (the entire `Default/Preferences` file replaced with a clean-144 copy, leaving every other CEF file from the poisoned backup) still DIED 2/2 — the poison is not confined to `Preferences` either.
- E2 (only `exit_type` normalized) still DIED 2/2, as expected — independently reconfirms `exit_type: Crashed` is not the mechanism (dead per P1).

Together: a guard that patches or replaces one file (`Preferences`) or one key inside it will not prevent this crash. PLAN §3's design — *stamp the Chromium major version on first successful run; on a stamp mismatch (or fallback to `extensions.last_chrome_version` > `CHROME_VERSION_MAJOR`) move the entire `CEF/` directory aside and start fresh* — is the right shape and should not be narrowed to a Preferences-only rewrite. The version-key comparison is fine as the *trigger*; it must not become the *remediation*.

## PIDs launched — all confirmed terminated

70771, 71681, 72940, 73607, 74465, 75274, 76632, 77376, 80188 (lldb debuggee). Verified via `ps -p <pid>` (all absent) and a final sweep (`ps aux | grep -i ghostty`) showing only the real app at pid 7205 (`/Applications/Ghostties.app/Contents/MacOS/ghostty`). `osascript … bundle identifier … com.seansmithdesign.ghostties` returned only `7205` after the last run.

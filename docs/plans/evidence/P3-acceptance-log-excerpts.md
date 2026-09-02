# P3/P3b/P4 acceptance runs — CEF log excerpts

All runs used a scratch `appsupport` directory under the session scratchpad
(never the real `~/Library/Application Support/com.seansmithdesign.ghostties`,
never the real profile backup). Paths below are relative to that scratch root.
Timestamps and PIDs are per-run; no cookies, URLs, or profile contents are
included.

## Item A — fresh backup copy, fixed build, 3 consecutive launches

Each launch is a fresh `cp -Rp` of the poisoned (Chromium-150-era) backup
fixture onto the fixed binary.

```
[CEFBridge] Downgrade guard: profile recordedMajor=150 > runningMajor=144 — moved aside to appsupport/CEF-downgraded-<ts> (error=none)
[CEFBridge] CefInitialize returned true
[CEFBridge] alive-tick t+3000ms
[CEFBridge] Cleared browser-open-attempt sentinel at appsupport/browser-open-attempt
```

Repeated identically across all 3 runs (distinct PIDs, distinct
`CEF-downgraded-<ts>` sibling directories). Oracle: PID alive past the
alive-tick t+3000ms mark = SURVIVED. **3/3 survived.**

## Item B — second launch on the already-remediated directory

```
[CEFBridge] Downgrade guard: no action (recordedMajor=144 runningMajor=144)
[CEFBridge] Cleared browser-open-attempt sentinel at appsupport/browser-open-attempt
```

Stamp reads 144 after the first remediation; the guard performs no move and
the second launch survives — confirms the fix is idempotent, not a
repeated-reset loop.

## Item C — oversized/malformed major version (`"1440.1.2.3"`)

```
[CEFBridge] Downgrade guard: no action (recordedMajor=0 runningMajor=144)
[CEFBridge] Cleared browser-open-attempt sentinel at appsupport/browser-open-attempt
```

The bounded parser rejects the malformed value (falls back to `0`, which is
`<= runningMajor`), so no action is taken and no directory is moved. Confirms
the parse path fails closed rather than misfiring on garbage input.

## Item D — fast-teardown / permission-denied sentinel write (P4)

```
[CEFBridge] Failed to write browser-open-attempt sentinel: permission denied
[CEFBridge] CEF initialized.
[CEFBridge] Failed to clear browser-open-attempt sentinel: permission denied
[CEFBridge] CEF shut down.
```

Exercises the sentinel-write/clear failure path directly (simulated via a
read-only target directory) rather than via the dealloc-era fast-teardown
race, which was removed rather than patched. No sentinel round-trip in this
branch is now load-bearing for correctness — see PR body "known limitations."

## Sentinel timing correction (re-measured this round)

Earlier diagnosis inferred "death precedes `CreateBrowser`" from the sentinel
file being absent on disk after a crash. Re-instrumented logging shows the
actual sequence:

- `t+0.009s` — sentinel written
- `t+0.164s` — `OnAfterCreated` fires, sentinel cleared (the browser **is**
  created)
- `t+0.49s` — process exits

The sentinel clearing on a normal code path made its on-disk absence
ambiguous as a crash signal. This is why the clear was moved off the
per-browser-creation callback and onto a process-level 3-second timer.

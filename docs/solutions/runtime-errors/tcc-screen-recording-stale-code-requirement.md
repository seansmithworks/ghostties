---
title: "Screen Recording Silently Denied After a Signing-Identity Change"
date: 2026-08-21
category: runtime-errors
severity: high
problem_type: runtime-errors
component: macOS TCC / Screen Recording permission
tags:
  - tcc
  - screen-recording
  - screencapture
  - code-signing
  - macos-permissions
  - developer-id
symptoms:
  - "`screencapture` returns `could not create image from display`"
  - App's toggle is visibly ON in System Settings → Screen & System Audio Recording
  - No permission prompt ever appears
  - Toggling the switch off/on does not help
  - Quitting and relaunching the app does not help
related_files:
  - /Applications/Ghostties.app
---

# Screen Recording Silently Denied After a Signing-Identity Change

> **Status:** Root cause confirmed and fixed 2026-08-21 on macOS 27.0 (build 26A5416b).
> Recurred for weeks before diagnosis because every intuitive fix is a dead end.

## Problem

`screencapture` from a Claude Code shell (or any child of Ghostties) failed with:

```
could not create image from display
```

while System Settings → Privacy & Security → **Screen & System Audio Recording**
showed **Ghostties toggled ON**. No prompt, no error dialog, no log visible to the user.

## Root cause

TCC stores each grant with a **code requirement** (`csreq`) captured when the row was
first created. Ghostties' row was written back when the app was a **local Xcode build
signed with an Apple Development certificate**. `/Applications/Ghostties.app` is now
signed with a **Developer ID Application** certificate.

The stored requirement pins the old certificate, so it can never match the running
binary again. And `kTCCServiceScreenCapture` is a **no-prompt service** — macOS will
not re-ask — so the denial is completely silent.

Evidence from `tccd`:

```
Failed to match existing code requirement for subject com.seansmithdesign.ghostties
  and service kTCCServiceScreenCapture

  stored: identifier "com.seansmithdesign.ghostties" and anchor apple generic
          and certificate leaf[subject.CN] = "Apple Development: <your-name> (<DEV-CERT-ID>)"

  actual: identifier "com.seansmithdesign.ghostties" and anchor apple generic
          and certificate leaf[subject.OU] = "5P7G79U672"   (Developer ID Application)

Service kTCCServiceScreenCapture does not allow prompting; returning denied.
```

## Why every intuitive fix fails

| Attempted fix | Why it cannot work |
|---|---|
| Toggle the switch off then on | Flips the row's `allowed` bit only. Never rewrites the stored `csreq`. |
| Quit and relaunch the app | Re-arms whatever the row says — and the row is permanently wrong. |
| Grant permission again | There is nothing to grant; the row already says allowed. |
| Wait for a re-prompt | ScreenCapture is a no-prompt service. macOS never re-asks and never self-heals. |

Only **deleting the row** helps, because tccd then writes a fresh one against the
binary's current signature.

## Fix

```bash
tccutil reset ScreenCapture com.seansmithdesign.ghostties
```

**A relaunch is NOT required.** Verified: `screencapture` succeeded immediately
afterward in the already-running Ghostties process (PID 1288, launched ~11 hours
earlier). The reset touches no processes and is safe to run mid-session — important
here, because relaunching Ghostties kills every Claude Code session hosted inside it.

## Diagnosing it in seconds next time

```bash
/usr/bin/log show --last 3m --predicate 'subsystem == "com.apple.TCC"' --style compact \
  | grep -iE 'Failed to match|does not allow prompting|AUTHREQ_ATTRIBUTION'
```

Two gotchas that cost real time:

1. **`log` is a zsh builtin.** Bare `log show ...` fails with
   `log:1: too many arguments`. Always use `/usr/bin/log`.
2. **No `sudo` needed.** `TCC.db` itself cannot be read without Full Disk Access
   (`sqlite3` returns `unable to open database file`), but the unified log exposes
   the full decision — including the stored vs. actual requirement — to a normal user.

The `AUTHREQ_ATTRIBUTION` line also settles *which* app needs the grant. For a
Claude Code shell it is the **responsible** process, not the accessing one:

```
attribution={
  responsible={identifier=com.seansmithdesign.ghostties, pid=1288, ...},
  accessing={identifier=com.apple.screencapture, ...},
  requesting={identifier=com.apple.replayd, ...}
}
```

So the terminal hosting the session needs the grant — never the app being photographed.

## Does a new release re-break this? No.

The stored requirement pins the **certificate identity**, not the build:

```
identifier "com.seansmithdesign.ghostties" and anchor apple generic
  and certificate leaf[subject.OU] = "5P7G79U672"
```

There is no `cdhash`. Every build signed with the same Developer ID certificate
matches, so routine releases and Sparkle auto-updates are safe. This was a
**one-time** break caused by the app crossing signing-identity classes
(Apple Development → Developer ID, around beta.22).

What would break it again:

- Switching identity class again (Developer ID → ad-hoc/unsigned, or back to Apple Development)
- Changing the Team ID
- Changing the bundle identifier
- **Overwriting `/Applications/Ghostties.app` with a local Xcode Debug build** —
  Xcode signs those with Apple Development. The Debug build uses
  `com.seansmithdesign.ghostties.dev` (a separate bundle ID and its own TCC row),
  so normal dev work does not trigger this.

## Generalize

Any app whose **signing identity class changes** carries a poisoned TCC row for
**every service it was previously granted**. The row keeps displaying and keeps
showing as enabled; it just silently never matches.

If a permission looks granted but behaves as denied, check the unified log before
touching System Settings. Then `tccutil reset <service> <bundle-id>`.

Services worth checking the same way: `ScreenCapture`, `Accessibility`,
`ListenEvent`, `Microphone`, `Camera`, `AppleEvents`, `SystemPolicyAllFiles`.

Stale rows for bundle IDs that no longer exist on disk are a tell that this has
happened before — the log showed orphaned `com.seansmithdesign.ghostties.debug`
entries from an earlier bundle-ID change.

## Ruled out along the way

- **Not the Claude Code sandbox** — fails identically with `dangerouslyDisableSandbox: true`.
- **Not a stale process serving old code** — bundle mtime (2026-08-17) predates the
  process launch (2026-08-20), so the running binary matched the bundle on disk.
- **Not an unsigned or broken bundle** — valid Developer ID chain, hardened runtime,
  `TeamIdentifier=5P7G79U672` present.
- **Not the wrong app row** — `/Applications/Ghostties.app` is
  `com.seansmithdesign.ghostties`; upstream `/Applications/Ghostty.app` is
  `com.mitchellh.ghostty` and is a separate, independently granted row.

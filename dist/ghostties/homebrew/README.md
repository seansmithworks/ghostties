# Homebrew Cask

`ghostties.rb` is the Homebrew Cask for Ghostties. This file is the **source
template** it's generated from — versioned alongside the app it packages, but
not a live mirror of what users install. The tap is what `brew install`
actually resolves; see "The in-repo copy trails releases" below for how the
two stay (or fall out of) sync.

The tap is live. End-user install:

```
brew install --cask seansmithworks/tap/ghostties
```

## Why it tracks a prerelease

Ghostties has not cut a stable GitHub release yet — every tag so far,
including the one this cask is pinned to, is a prerelease. The cask
deliberately tracks the beta/prerelease channel today rather than waiting for
a stable tag that doesn't exist. Moving to stable later is a one-line change
(the `url`/`version` already interpolate from a single `version` string). The
`livecheck` block is written to include prereleases in its version scan —
Homebrew's default GitHub livecheck strategies skip prereleases, which would
otherwise report "no version found."

## Keeping it current

`scripts/update-cask-version.sh <tag>` resolves the release's `Ghostties.dmg`
sha256 from GitHub and rewrites `version` + `sha256` in this file. Run it by
hand after cutting a release:

```
bash scripts/update-cask-version.sh v0.1.0-beta.24
```

It's idempotent and fails loudly if the release or the DMG asset is missing.

## CI sync to the tap (inert until activated)

`.github/workflows/ghostties-release.yml` has a `homebrew-cask` job that,
after a release is published, bumps this file and opens a PR against a
Homebrew tap repo. It is a no-op today — it's gated on a repository variable
that doesn't exist yet, so it skips cleanly on every release run without
failing.

The tap repo `SeanSmithWorks/homebrew-tap` already exists and is seeded with
the current cask. To activate CI auto-bump:

1. **Add a repository variable** on `ghostties`: `HOMEBREW_TAP_REPO` =
   `SeanSmithWorks/homebrew-tap`. (Settings → Secrets and variables → Actions
   → Variables.)
2. **Add a repository secret**: `HOMEBREW_TAP_TOKEN` — a token with push
   access to the tap repo (a fine-grained PAT scoped to that one repo is
   enough; a classic PAT with `repo` scope also works). Add it under
   Secrets and variables → Actions → Secrets, on the `ghostties` repo (the
   job runs in `ghostties` CI and pushes out to the tap using this token).

Once both are set, every future release run will bump the cask **in its own
checkout** (not committed) and open a PR in the tap with the bumped file
synced into `Casks/ghostties.rb`.

Until then — or if the token is missing while the variable is set — the job
either skips (`vars.HOMEBREW_TAP_REPO` unset) or fails with a clear
`::error::` message naming the missing secret (variable set, token missing).
It never fails silently and never turns green release runs red because of a
tap that doesn't exist.

### The in-repo copy trails releases

The CI job deliberately never commits or pushes to `main` — it only bumps
its own checkout of this file to build the tap PR. That keeps this pipeline,
which has an expensive bug history, from having a second unrelated write
path to `main` on every release run. The consequence: `ghostties.rb` in this
repo pins whatever version someone last ran `scripts/update-cask-version.sh`
against by hand — it is the **template/source**, not a live mirror. The tap
(`Casks/ghostties.rb` in `SeanSmithWorks/homebrew-tap`) is what users
actually install from, and CI keeps that copy current on every release. If
you need the in-repo copy to reflect the latest release, run the script
yourself:

```
bash scripts/update-cask-version.sh v0.1.0-beta.24
```

## `brew audit` results

This cask cannot pass `brew audit --online` today, by construction, for as
long as every release is a GitHub prerelease: Homebrew's online audit
(`shared_audits.rb`) rejects casks pointing at prereleases, and the waiver
for that is Homebrew's own maintained allowlist — third-party taps cannot
opt in. Running with `new_cask: true` also flags this repo as a fork, not
the canonical repository. Neither error matters for a personal tap with no
CI running `brew audit` against it, but don't be surprised by it if you ever
add that CI.

Actual results, obtained by invoking `Cask::Audit` directly (`brew audit`
itself is blocked on this machine by an Xcode-version gate):

- strict + offline: 0 errors
- strict + online + signing: 1 error (`is a GitHub pre-release`); signing
  audit passed
- full (`new_cask: true`): 2 errors (pre-release + `GitHub fork (not
  canonical repository)`)

## Zap stanza

`zap` removes only Ghostties' own preference, cache, Application Support, and
saved-state files — all keyed to `com.seansmithdesign.ghostties`, the actual
app's bundle identifier. It deliberately does not touch anything under
upstream Ghostty's `com.mitchellh.ghostty` identifier, `~/.config/ghostty/config`
(shared between Ghostty and Ghostties), or the separate `Ghostties Dev`/
`Ghostties Demo` build variants.

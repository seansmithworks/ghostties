# Ghostties Demo Rig

Produces an isolated `Ghostties Demo.app` for screen recording and marketing
capture — never touches the real daily-driver app or its data.

## How isolation works

`refresh-demo.sh` re-bundles the app under bundle ID
`com.seansmithdesign.ghostties.demo`. `WorkspacePersistence` derives its state
directory from `Bundle.main.bundleIdentifier`, so the demo app reads/writes
`~/Library/Application Support/Ghostties Demo/` — completely separate from
`~/Library/Application Support/Ghostties/` (release) and `Ghostties Dev/`.

## Refresh modes

```bash
# Default: download the latest published release and re-bundle it (recommended)
./scripts/demo/refresh-demo.sh

# Pin to a specific tag
./scripts/demo/refresh-demo.sh --from-release v0.1.0-beta.24

# Build the local checkout instead (Debug, arm64)
./scripts/demo/refresh-demo.sh --from-source
./scripts/demo/refresh-demo.sh --from-source --pull-main   # fetch+checkout main first

# Verification / CI use
./scripts/demo/refresh-demo.sh --dest /tmp/x.app --no-launch
```

Release downloads are cached under `~/Library/Caches/ghostties-demo/<tag>/` so
re-running the same tag doesn't re-download the ~147MB asset.

**Sparkle updates are disabled in the demo build.** Ad-hoc re-signing
(required to rewrite the bundle ID) invalidates the Developer ID signature
Sparkle needs to trust an update, and `UpdateDelegate.feedURLString(for:)`
honours an explicit Info.plist `SUFeedURL` before falling back to the real
release channels — so a manual "Check for Updates…" in the demo could
otherwise resolve the real Ghostties feed and overwrite the demo app with
the real one (they share the same `SUPublicEDKey`). The script instead sets
`SUFeedURL` to `https://ghostties.org/appcast-demo.xml`, a URL that
deliberately does not exist, so a manual check fails benignly with a 404
rather than installing anything. It also unconditionally sets
`SUEnableAutomaticChecks` to `false` (adding the key if absent) — a missing
key makes Sparkle prompt the user, so it's never left out. **This script is
the demo's update mechanism — re-run it to refresh to a new release.**

## Seed the workspace

```bash
./scripts/demo/seed-demo-workspace.sh
```

Copies the 10 fixtures in `examples/demo-workspace/` into
`~/Library/Application Support/Ghostties Demo/repos/<name>/`, turns each into
a real git repo (init + one commit; a few get an extra branch), and points
`workspace.json` at those copies — not at this checkout, so the demo doesn't
break when this repo changes branch. Idempotent; backs up any existing
`workspace.json` before overwriting.

## Quitting

Never `killall`. Quit cleanly:

```bash
osascript -e 'tell application "Ghostties Demo" to quit'
```

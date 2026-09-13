# Ghostties Demo Rig

Produces an isolated `Ghostties Demo.app` for screen recording and marketing
capture — never touches the real daily-driver app or its data.

## Entrypoint: `demo-ready.sh`

Before capturing anything, run:

```bash
./scripts/demo/demo-ready.sh
```

This is the one command an agent or Sean should run as preflight. It resolves
the newest release tag on `SeanSmithWorks/ghostties`, compares it against the
installed demo app's version, calls `refresh-demo.sh` only if they differ,
always reseeds the fixture workspace via `seed-demo-workspace.sh`, stages
demo agent sessions via the same logic `demo-drive.sh` uses (since reseeding
always wipes any previously staged sessions), and writes a manifest recording
exactly what's on disk. `refresh-demo.sh`, `seed-demo-workspace.sh`, and
`demo-drive.sh` are the pieces it builds on — call them directly only when
working on the rig itself. "Ready" means all of: app current, fixtures
seeded, fixture repos trusted, AND sessions staged — `--check` verifies all
four.

```bash
./scripts/demo/demo-ready.sh --check     # assert freshness; exits non-zero if stale/missing, never changes the app
./scripts/demo/demo-ready.sh --source    # demo the current checkout instead of the newest release
./scripts/demo/demo-ready.sh --dest <path>  # non-default app location
```

### Manifest

Every successful run — including a passing `--check` — writes
`~/Library/Application Support/Ghostties Demo/demo-manifest.json`, recording
the demo app version (or, in `--source` mode, the built commit sha), the
source tag or ref+sha, the resolved absolute path of the app bundle that was
just inspected or refreshed, the app bundle's mtime, an ISO-8601
refreshed-at timestamp, the fixture project count, and the seeded repos
path. `--check` never touches the app or the fixture workspace — it only
records what it just verified, so a stale manifest can't survive a clean
preflight. **A capture run should copy this manifest next to whatever assets
it produces** — it's what lets anyone later trace a screenshot or clip back
to the exact build that produced it.

### Fixture trust

Claude Code stops each staged session at its "Do you trust this folder?"
screen unless the folder is already marked trusted, which would otherwise
show a safety prompt instead of an agent in every capture. `demo-ready.sh`
(the non-`--check` path) marks only the 10 seeded fixture repo paths as
trusted by setting `projects["<fixture path>"].hasTrustDialogAccepted = true`
in Sean's real `~/.claude.json` — no other key or entry is touched. It backs
up the file first (`~/.claude.json.bak-demo-<timestamp>`), writes nothing if
already trusted, and re-reads the file afterward to confirm the write stuck.
`demo-ready.sh --check` treats a missing or `false` trust entry as not ready
(non-zero exit), so a concurrent Claude Code process rewriting the config
can't silently drop the entries without the preflight catching it.

### Staged sessions

`demo-ready.sh --check` also treats a missing or short-staffed set of staged
sessions (fewer than `demo-drive.sh`'s own default `--count`) as not ready.
This exists because `seed-demo-workspace.sh` always writes a fresh,
session-free `workspace.json` — a reseed with no restaging would otherwise
leave `--check` reporting "ready" for a demo with nothing to capture. The
non-`--check` path re-stages sessions via `_stage-demo-sessions.sh` (shared
with `demo-drive.sh`, so the two never drift) every time it runs, after
seeding and fixture trust.

## How isolation works

`refresh-demo.sh` re-bundles the app under bundle ID
`com.seansmithdesign.ghostties.demo` AND sets an explicit Info.plist
`LSEnvironment:GHOSTTIES_STATE_DIR` pinned to
`~/Library/Application Support/Ghostties Demo/`. That `LSEnvironment` entry —
not the bundle ID alone — is what actually isolates the demo app: it's the
only mechanism that reaches a **LaunchServices launch** (`open`, Finder, Dock
double-click), and `WorkspacePersistence.directory` checks
`GHOSTTIES_STATE_DIR` before falling back to bundle-ID-derived resolution.
Without it, opening the Demo app normally would read/write the release
workspace at `~/Library/Application Support/Ghostties/` — the same file
Sean's real, running app uses. `refresh-demo.sh` re-registers the app with
`lsregister` after rewriting the plist so `open` picks up the new env instead
of a cached registration.

`demo-ready.sh --check` and `demo-drive.sh` both verify this pin is present
and correct before reporting ready / printing the `open` instruction — a
demo app missing it is treated as stale, even if its version matches.

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
`/Users/Shared/Ghostties Demo/repos/<name>/`, turns each into a real git repo
(init + one commit; a few get an extra branch), and points `workspace.json`
at those copies — not at this checkout, so the demo doesn't break when this
repo changes branch. The repos root lives outside `$HOME` (unlike the rest of
the demo state dir) so a captured terminal pane's cwd never shows the real
username. Idempotent; backs up any existing `workspace.json` before
overwriting.

## Stage real agent sessions: `demo-drive.sh`

```bash
./scripts/demo/demo-drive.sh              # stage 4 sessions across seeded repos
./scripts/demo/demo-drive.sh --count 6    # stage 6 sessions
./scripts/demo/demo-drive.sh --reset      # clear staged sessions
```

**The demo app must be quit before running this.** `WorkspacePersistence`
rewrites `workspace.json` from memory while the app runs, so any edit made
while it's open is silently reverted. If it's running, the script refuses to
proceed and prints:

```bash
osascript -e 'tell application "Ghostties Demo" to quit'
```

It detects a running instance via `osascript`/System Events by bundle ID —
querying only, never used to quit or drive the app.

The actual write is delegated to `_stage-demo-sessions.sh`, an internal
script also called by `demo-ready.sh` — `demo-drive.sh` owns the
user-facing preconditions (readiness check, "is the app running") and stays
a standalone entrypoint; `demo-ready.sh` calls the shared writer directly
instead of calling `demo-drive.sh`, to avoid a
demo-ready → demo-drive → demo-ready cycle through `demo-drive.sh`'s own
`demo-ready.sh --check` precondition.

Each staged session is bound to its own per-repo `AgentTemplate` whose
command is `claude` with a short, harmless, read-only prompt (summarize the
README, list TODOs, describe the structure, explain the last commit — cycled
across sessions). Nothing about the resulting activity is faked: no GUI
automation is used anywhere, and the script never launches the app or runs
`claude` itself. It only writes the staged records to `workspace.json`
(backed up first, validated as JSON, written atomically); re-running replaces
the previously staged set rather than appending duplicates.

**Important:** Ghostties only spawns a process from a user-triggered UI
action (a sidebar "Relaunch" click, a row click, or the composer) — there is
no launch-time code path that replays persisted sessions automatically. A
staged session appears in the sidebar as "Exited" with a Relaunch action;
producing genuinely live ghost states for capture still requires clicking
"Relaunch" once per session after opening the app:

```bash
open "/Applications/Ghostties Demo.app"
```

## Capture marketing PNGs from the seeded workspace: `demo-capture.sh`

```bash
./scripts/demo/demo-capture.sh              # writes to output/demo-capture/
./scripts/demo/demo-capture.sh --out <dir>   # custom output dir
```

The capture build gets its own bundle ID (`com.seansmithdesign.ghostties.democapture.dev`,
via `GHOSTTIES_DEV_BUNDLE_SUFFIX`) instead of the shared `.dev` every worktree's
Debug build otherwise uses — XCUITest's `launch()` quits any running app
under the target bundle ID, and Ghostty is single-instance per bundle ID, so
a capture run under the shared `.dev` ID would either kill or hijack
whatever Dev build is already running elsewhere. The suffix must always end
in `.dev`: `WorkspacePersistence.directory` falls back to a bundle-ID-derived
state directory whenever `GHOSTTIES_STATE_DIR` is unusable, and that fallback
routes to the real release workspace (`~/Library/Application Support/Ghostties`)
unless the bundle ID itself ends in `.dev` or `.debug` — a suffix like
`.democapture` alone would risk mutating Sean's real, running workspace if
the override ever failed.

The agent-facing entrypoint for producing marketing assets from the **real
seeded fixture repos** — 10 real git repos with real branches — instead of
`MarketingCaptureUITests`' hardcoded in-app cast (`switchboard`, `atlas-api`,
`fieldwork`, `pendulum`, `silo`, `trove`, `wren`). It:

1. Runs `demo-ready.sh --check` and aborts if the demo app / fixtures are stale.
2. Copies `~/Library/Application Support/Ghostties Demo/` to a throwaway
   location — the demo state dir is treated as **read-only** by this script,
   never written to. Also writes a fixture zsh dotdir (`.demo-zdotdir`)
   inside that same throwaway location, so the captured terminal prompt
   never shows the real username or hostname.
3. Runs `GhosttyUITests/DemoWorkspaceCaptureUITests` via `xcodebuild test`,
   pointing the app at the throwaway copy via `GHOSTTIES_STATE_DIR` and the
   fixture dotdir via `GHOSTTIES_DEMO_ZDOTDIR`. Resolves the real xcresult
   totals before classifying any failure — `xcodebuild` exits 65 for both a
   build failure and a plain test failure, so a missing result bundle (or
   zero tests) is reported as a BUILD failure, and a present bundle with
   real totals is reported as the actual test failure count. Also asserts
   the resolved test count matches what's expected (a malformed
   `-only-testing` filter can silently match zero tests and still exit 0 —
   this is checked, not trusted).
4. Copies the captured PNGs to the output directory, alongside a copy of
   `demo-manifest.json` so every capture traces back to the exact build that
   produced it.
5. Asserts every PNG is non-blank (checks decompressed pixel-data variance,
   not just file existence) before declaring success — a denied capture or a
   solid-color window still produces a structurally valid PNG.

### Prompt identity leak — fixture zsh dotdir

The default zsh prompt reads `user@hostname ~ %`, which would otherwise leak
Sean's real username and machine name into every marketing capture.
`demo-capture.sh` writes a throwaway `.demo-zdotdir` (containing `.zshenv`,
`.zprofile`, `.zshrc`) inside the same `COPY_DIR` it already treats as
disposable. Each dotfile sources the matching real dotfile from `$HOME` first
(so `PATH` and `claude` still resolve), then `.zshrc` sets a user/host-free
`PROMPT='%1~ %# '` with `RPROMPT=''`.

The directory is forwarded to `xcodebuild` as `TEST_RUNNER_GHOSTTIES_DEMO_ZDOTDIR`
(a process env var picked up by the test runner) and the test sets
`app.launchEnvironment["ZDOTDIR"]` from it before launch. This works because
Ghostty's zsh auto-integration (`setupZsh` in `src/termio/shell_integration.zig`)
preserves any pre-existing `ZDOTDIR` and restores it before sourcing the
user's dotfile chain (`src/shell-integration/zsh/.zshenv`) — it round-trips
through the integration, it doesn't get clobbered by it.

Separately: the "Last login: … on ttysNNN" line comes from macOS's
`/usr/bin/login` binary itself (Ghostty spawns shells via `login -flp`, see
`src/termio/Exec.zig`), not from any dotfile or env var — this rig does not
attempt to suppress it.

### `DemoWorkspaceCaptureUITests` — fail-closed by design

`WorkspacePersistence.directory` honors `GHOSTTIES_STATE_DIR` when set, but
**falls back to the real state directory if the override path is unusable** —
by design, so a shipping launch is never affected. That means a bad override
here would silently point the app at Sean's real workspace. The test does not
trust the env var being set as proof: before capturing anything, it asserts
that `brukas` — a project name that exists only in
`examples/demo-workspace/`, not in `MarketingCaptureUITests`' invented cast —
is visibly rendered in the sidebar. If it isn't, the test fails loudly instead
of capturing.

This test is additive: it does not change `MarketingCaptureUITests`' behavior
or output paths, and it never sets `GHOSTTIES_CAPTURE_FIXTURE` (that flag
seeds an in-memory invented cast, which would defeat the point).

## Quitting

Never `killall`. Quit cleanly:

```bash
osascript -e 'tell application "Ghostties Demo" to quit'
```

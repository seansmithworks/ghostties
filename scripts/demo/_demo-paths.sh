#!/usr/bin/env bash
# =============================================================================
# _demo-paths.sh — Shared path/constant definitions for the Ghostties Demo rig
#
# Sourced (never executed directly) by demo-ready.sh, seed-demo-workspace.sh,
# demo-drive.sh, _stage-demo-sessions.sh, and demo-capture.sh, so these values
# can't drift between scripts. Requires REPO_ROOT to already be set by the
# sourcing script.
# =============================================================================

# State dir for Ghostties Demo.app (bundle ID com.seansmithdesign.ghostties.demo).
# NEVER equals the release workspace dir (~/Library/Application Support/Ghostties).
# Overridable only for fail-closed verification against a scratch copy — never
# set in normal runs.
DEMO_STATE_DIR="${DEMO_STATE_DIR_OVERRIDE:-$HOME/Library/Application Support/Ghostties Demo}"

# Repos root lives outside $HOME so a captured terminal pane's cwd never shows
# the real username — only DEMO_STATE_DIR (above) stays under $HOME.
REPOS_DIR="/Users/Shared/Ghostties Demo/repos"

# Name prefix demo-drive.sh / _stage-demo-sessions.sh use for sessions they
# stage, and the default number of sessions staged when --count isn't passed.
# demo-ready.sh --check uses both to verify sessions are staged without
# hardcoding a count that could drift from demo-drive.sh's own default.
DEMO_SESSION_MARKER="Demo Agent — "
DEMO_DRIVE_DEFAULT_COUNT=4

# ── Isolation check: LSEnvironment must pin GHOSTTIES_STATE_DIR ─────────────
# `WorkspacePersistence.directoryName` maps the demo bundle ID
# (com.seansmithdesign.ghostties.demo) to "Ghostties Demo" — but ONLY when
# the app is launched by a process that inherited that bundle ID naturally
# (e.g. run directly from xcodebuild). A LaunchServices launch (`open`,
# Finder, Dock double-click) reads Info.plist but the running process's
# Bundle.main.bundleIdentifier still reflects the on-disk bundle ID, so that
# part is fine — the actual risk is bundle IDs the mapping doesn't recognize,
# or this rig's own re-signing/re-bundling process losing the state dir
# override that pins it explicitly. `refresh-demo.sh` sets
# LSEnvironment:GHOSTTIES_STATE_DIR to this exact path so isolation does not
# depend solely on bundle-ID string matching. This function is the one place
# that checks it, so demo-ready.sh and demo-drive.sh can't drift.
#
# Usage: demo_app_isolation_ok "<path to .app>"  → prints a status line,
# returns 0 if LSEnvironment:GHOSTTIES_STATE_DIR equals $DEMO_STATE_DIR.
demo_app_isolation_ok() {
  local app_path="$1"
  local plist="$app_path/Contents/Info.plist"
  if [[ ! -f "$plist" ]]; then
    echo "NOT READY: no Info.plist at $plist." >&2
    return 1
  fi
  local state_dir
  state_dir=$(/usr/libexec/PlistBuddy -c "Print :LSEnvironment:GHOSTTIES_STATE_DIR" "$plist" 2>/dev/null || true)
  if [[ -z "$state_dir" ]]; then
    echo "NOT READY: $plist has no LSEnvironment:GHOSTTIES_STATE_DIR." >&2
    echo "           Fix: run ./scripts/demo/refresh-demo.sh to rebundle with the isolation env set." >&2
    return 1
  fi
  if [[ "$state_dir" != "$DEMO_STATE_DIR" ]]; then
    echo "NOT READY: $plist LSEnvironment:GHOSTTIES_STATE_DIR is '$state_dir', expected '$DEMO_STATE_DIR'." >&2
    echo "           Fix: run ./scripts/demo/refresh-demo.sh to rebundle with the correct isolation env." >&2
    return 1
  fi
  echo "OK: isolation env set (LSEnvironment:GHOSTTIES_STATE_DIR = $state_dir)."
  return 0
}

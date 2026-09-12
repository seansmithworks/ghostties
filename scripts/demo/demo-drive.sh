#!/usr/bin/env bash
# =============================================================================
# demo-drive.sh — Stage real agent sessions into the Ghostties Demo workspace
#
# PURPOSE
#   Writes N AgentSession entries (bound to per-repo AgentTemplates whose
#   command is `claude`) directly into
#   "~/Library/Application Support/Ghostties Demo/workspace.json", spread
#   across the fixture repos seeded by seed-demo-workspace.sh. Nothing about
#   the resulting agent activity is faked: this script never launches the
#   app and never runs `claude` itself. When the operator opens the demo app
#   and clicks "Relaunch" on a staged session, the app spawns a REAL `claude`
#   process against a real fixture repo, running a short, harmless,
#   read-only prompt — that is what produces genuinely live ghost states for
#   capture.
#
#   IMPORTANT — what this script does NOT do:
#     Ghostties only calls SessionCoordinator.createSession() (the thing that
#     actually spawns a process) from user-triggered UI actions — the
#     sidebar "Relaunch" button, a row click, or the composer. There is no
#     app-launch-time code path that iterates persisted sessions and
#     relaunches them automatically. A session staged by this script will
#     appear in the sidebar as "Exited" (per AgentSession's own doc comment)
#     with a Relaunch action available — it will NOT start running on its
#     own just because the app launched. Producing live activity for a shot
#     still requires one manual click per session; this script cannot and
#     does not attempt to script that click (no GUI automation, ever).
#
# PRECONDITIONS
#   1. `demo-ready.sh --check` must pass (current app + fixtures). Stale?
#      Run `./scripts/demo/demo-ready.sh` first.
#   2. Ghostties Demo.app MUST be quit before running this script.
#      WorkspacePersistence rewrites workspace.json from memory while the
#      app runs, so any edit made here would be silently discarded the
#      moment the app is running. If it's open:
#        osascript -e 'tell application "Ghostties Demo" to quit'
#      This script detects a running instance via System Events (querying
#      only — never used to quit or drive the app) and refuses to proceed.
#
# USAGE
#   ./scripts/demo/demo-drive.sh                # stage 4 sessions (default)
#   ./scripts/demo/demo-drive.sh --count 6       # stage 6 sessions
#   ./scripts/demo/demo-drive.sh --reset         # clear staged sessions
#
# BEHAVIOR
#   - Idempotent: re-running replaces the previously staged set (identified
#     by a "Demo Agent — " name prefix) rather than appending duplicates.
#   - Backs up workspace.json before writing (same convention as
#     seed-demo-workspace.sh: workspace.json.bak-<timestamp>).
#   - Writes to a temp file, validates it as JSON, then moves it into place
#     — never leaves a partially-written workspace.json.
#   - Does NOT launch the app. Prints the `open` command to run manually.
#   - Never writes to ~/.ghostties/presets/ (shared with the real app) or
#     to ~/Library/Application Support/Ghostties/ (the real workspace).
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEMO_READY_SCRIPT="$REPO_ROOT/scripts/demo/demo-ready.sh"
STAGE_SCRIPT="$REPO_ROOT/scripts/demo/_stage-demo-sessions.sh"

source "$REPO_ROOT/scripts/demo/_demo-paths.sh"

TARGET="$DEMO_STATE_DIR/workspace.json"
APP_PATH="/Applications/Ghostties Demo.app"
BUNDLE_ID="com.seansmithdesign.ghostties.demo"

COUNT="$DEMO_DRIVE_DEFAULT_COUNT"
RESET=0

# ── Arg parsing ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --count)
      COUNT="$2"
      shift 2
      ;;
    --reset)
      RESET=1
      shift
      ;;
    -h|--help)
      sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "ERROR: Unrecognized argument: $1" >&2
      exit 1
      ;;
  esac
done

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [[ "$COUNT" -lt 1 ]]; then
  echo "ERROR: --count must be a positive integer, got: $COUNT" >&2
  exit 1
fi

echo "==> Ghostties demo-drive"
echo "    Target: $TARGET"
if [[ "$RESET" -eq 1 ]]; then
  echo "    Mode:   reset (clear staged sessions)"
else
  echo "    Mode:   stage $COUNT session(s)"
fi
echo ""

# ── Safety check: never touch the release workspace ─────────────────────────
RELEASE_DIR="$HOME/Library/Application Support/Ghostties"
if [[ "$DEMO_STATE_DIR" == "$RELEASE_DIR" ]]; then
  echo "ERROR: Demo dir resolved to release dir. Aborting." >&2
  exit 1
fi

# ── Precondition 1: fixtures must be current ────────────────────────────────
echo "==> Checking demo-ready.sh --check..."
if ! "$DEMO_READY_SCRIPT" --check; then
  echo "" >&2
  echo "ERROR: demo-ready.sh --check failed — app/fixtures are stale or missing." >&2
  echo "       Run ./scripts/demo/demo-ready.sh first, then retry." >&2
  exit 1
fi
echo ""

# ── Precondition 2: app must be quit ────────────────────────────────────────
echo "==> Checking whether Ghostties Demo is running..."
IS_RUNNING="false"
if command -v osascript >/dev/null 2>&1; then
  IS_RUNNING=$(osascript -e "tell application \"System Events\" to exists (first process whose bundle identifier is \"$BUNDLE_ID\")" 2>/dev/null || echo "false")
fi

if [[ "$IS_RUNNING" == "true" ]]; then
  echo "ERROR: Ghostties Demo is currently running." >&2
  echo "       workspace.json edits are silently reverted while the app runs" >&2
  echo "       (WorkspacePersistence rewrites it from memory). Quit it first:" >&2
  echo "" >&2
  echo "         osascript -e 'tell application \"Ghostties Demo\" to quit'" >&2
  echo "" >&2
  echo "       Then re-run this script." >&2
  exit 1
fi
echo "    Not running. Proceeding."
echo ""

if [[ ! -f "$TARGET" ]]; then
  echo "ERROR: $TARGET does not exist. Run seed-demo-workspace.sh (or demo-ready.sh) first." >&2
  exit 1
fi

# ── Delegate the actual write to the shared staging script (also used by
#    demo-ready.sh) so the two never drift ──────────────────────────────────
if [[ "$RESET" -eq 1 ]]; then
  "$STAGE_SCRIPT" --reset
else
  "$STAGE_SCRIPT" --count "$COUNT"
fi
echo ""
echo "Next: open the demo app to materialize the staged sessions, then click"
echo "\"Relaunch\" on each one to spawn its real claude process for capture:"
echo ""
echo "  open \"$APP_PATH\""

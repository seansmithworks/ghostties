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

DEMO_DIR="$HOME/Library/Application Support/Ghostties Demo"
TARGET="$DEMO_DIR/workspace.json"
REPOS_DIR="$DEMO_DIR/repos"
APP_PATH="/Applications/Ghostties Demo.app"
BUNDLE_ID="com.seansmithdesign.ghostties.demo"

SESSION_MARKER="Demo Agent — "
TEMPLATE_MARKER="Demo Drive: "

COUNT=4
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
if [[ "$DEMO_DIR" == "$RELEASE_DIR" ]]; then
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

# ── Back up existing workspace.json ─────────────────────────────────────────
BACKUP="$DEMO_DIR/workspace.json.bak-$(date +%Y%m%dT%H%M%S)"
echo "==> Backing up existing workspace.json -> $(basename "$BACKUP")"
cp "$TARGET" "$BACKUP"
echo ""

# ── Write staged sessions via python3 (atomic temp-file swap) ───────────────
TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/workspace.XXXXXX.json")"
trap 'rm -f "$TMP_FILE"' EXIT

echo "==> Rewriting workspace.json..."
python3 - "$TARGET" "$TMP_FILE" "$REPOS_DIR" "$COUNT" "$RESET" "$SESSION_MARKER" "$TEMPLATE_MARKER" <<'PYEOF'
import sys
import json
import subprocess
import os

target_path, tmp_path, repos_dir, count_str, reset_str, session_marker, template_marker = sys.argv[1:8]
count = int(count_str)
reset = reset_str == "1"

with open(target_path) as f:
    state = json.load(f)

projects = state.get("projects", [])
if not projects:
    print("ERROR: workspace.json has no projects to bind sessions to.", file=sys.stderr)
    sys.exit(1)

# Only bind to projects whose rootPath actually lives under the seeded repos
# dir — never point a session at an arbitrary project.
eligible_projects = [p for p in projects if p.get("rootPath", "").startswith(repos_dir)]
if not eligible_projects:
    print(f"ERROR: no projects with rootPath under {repos_dir}.", file=sys.stderr)
    sys.exit(1)

# Strip any previously staged sessions/templates (identified by name prefix)
# so re-running replaces rather than appends.
prior_sessions = state.get("sessions", [])
prior_templates = state.get("templates", [])

kept_sessions = [s for s in prior_sessions if not s.get("name", "").startswith(session_marker)]
kept_templates = [t for t in prior_templates if not t.get("name", "").startswith(template_marker)]

removed_sessions = len(prior_sessions) - len(kept_sessions)
removed_templates = len(prior_templates) - len(kept_templates)
print(f"    Removed {removed_sessions} previously staged session(s), {removed_templates} template(s).")

if reset:
    state["sessions"] = kept_sessions
    state["templates"] = kept_templates
    with open(tmp_path, "w") as f:
        json.dump(state, f, indent=2, sort_keys=True)
    print("    Reset complete — staged sessions cleared.")
    sys.exit(0)

def new_uuid():
    return subprocess.run(["uuidgen"], capture_output=True, text=True, check=True).stdout.strip().upper()

# Short, harmless, read-only prompts — cycled across staged sessions. Each
# is a plain positional argument to `claude`, never a flag that could touch
# the filesystem.
PROMPTS = [
    "Summarize this repository's README in 3 bullet points. Read-only — do not modify any files.",
    "List any TODO or FIXME comments you can find in this repository. Read-only — do not modify any files.",
    "Describe this repository's directory structure in a few sentences. Read-only — do not modify any files.",
    "Explain what the most recent git commit in this repository changed. Read-only — do not modify any files.",
]

new_sessions = []
new_templates = []

for i in range(count):
    project = eligible_projects[i % len(eligible_projects)]
    prompt = PROMPTS[i % len(PROMPTS)]
    project_name = project["name"]
    root_path = project["rootPath"]

    template_id = new_uuid()
    session_id = new_uuid()

    template = {
        "id": template_id,
        "name": f"{template_marker}{project_name}",
        "kind": "claudeCode",
        "isDefault": False,
        "isGlobal": False,
        "projectId": project["id"],
        "command": "claude",
        "environmentVariables": {},
        "workingDirectory": root_path,
        "agent": {
            "additionalFlags": [prompt],
        },
        "templateDescription": "Demo-drive staged agent (read-only)",
    }

    session = {
        "id": session_id,
        "name": f"{session_marker}{project_name}",
        "templateId": template_id,
        "projectId": project["id"],
        "isNamePinned": True,
    }

    new_templates.append(template)
    new_sessions.append(session)

state["sessions"] = kept_sessions + new_sessions
state["templates"] = kept_templates + new_templates

with open(tmp_path, "w") as f:
    json.dump(state, f, indent=2, sort_keys=True)

print(f"    Staged {len(new_sessions)} session(s) across {len(eligible_projects)} eligible project(s):")
for s, t in zip(new_sessions, new_templates):
    print(f"      - {s['name']}  (template: {t['workingDirectory']})")
PYEOF

# ── Validate before moving into place ───────────────────────────────────────
echo ""
echo "==> Validating JSON..."
python3 -m json.tool "$TMP_FILE" > /dev/null
echo "    Valid."

mv "$TMP_FILE" "$TARGET"
chmod 600 "$TARGET"
trap - EXIT

echo ""
echo "==> Verifying staged state..."
python3 - "$TARGET" "$SESSION_MARKER" <<'PYEOF'
import sys, json
target_path, marker = sys.argv[1:3]
with open(target_path) as f:
    data = json.load(f)
staged = [s for s in data.get("sessions", []) if s.get("name", "").startswith(marker)]
print(f"    Total sessions   : {len(data.get('sessions', []))}")
print(f"    Staged sessions  : {len(staged)}")
print(f"    Total templates  : {len(data.get('templates', []))}")
PYEOF

echo ""
if [[ "$RESET" -eq 1 ]]; then
  echo "Done. Staged sessions cleared."
else
  echo "Done. $COUNT session(s) staged."
fi
echo ""
echo "Next: open the demo app to materialize the staged sessions, then click"
echo "\"Relaunch\" on each one to spawn its real claude process for capture:"
echo ""
echo "  open \"$APP_PATH\""

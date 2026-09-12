#!/usr/bin/env bash
# =============================================================================
# seed-demo-workspace.sh — Write isolated demo workspace.json for screen captures
#
# PURPOSE
#   Seeds ~/Library/Application Support/Ghostties Demo/workspace.json with 10
#   fictional projects that look realistic on camera. This directory is used
#   exclusively by Ghostties Demo.app (bundle ID com.seansmithdesign.ghostties.demo).
#   It NEVER touches ~/Library/Application Support/Ghostties/ (release workspace).
#
#   Each fixture in examples/demo-workspace/ is copied into
#   "/Users/Shared/Ghostties Demo/repos/<name>/" and turned into a real git
#   repo (git init, one commit; a few get an extra branch), so the demo has
#   real repo state and doesn't depend on this checkout's branch. The repos
#   root lives outside $HOME (unlike the rest of the demo state dir) so
#   captured terminal panes never show a path containing the real username.
#
# USAGE
#   ./scripts/demo/seed-demo-workspace.sh
#
#   Idempotent / re-runnable. Any existing workspace.json is backed up to
#   workspace.json.bak-<timestamp> before overwriting. Repo copies under
#   repos/<name>/ are removed and recreated fresh on every run.
#
# NON-REPRODUCIBLE ITEMS (not handled here)
#   - Branded shell prompt: `export PS1='ghostties ~/%1~ %% '`
#     This is per-shell-session and must be set by hand at capture time.
#     Making it persistent would require a demo-only ZDOTDIR override; that
#     is out of scope for this script.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURES_DIR="$REPO_ROOT/examples/demo-workspace"

DEMO_DIR="$HOME/Library/Application Support/Ghostties Demo"
TARGET="$DEMO_DIR/workspace.json"
# Repos root lives outside $HOME so a captured terminal pane's cwd never
# shows the real username — only the demo STATE dir (above) stays under
# $HOME. Must match the value in demo-ready.sh and demo-drive.sh.
REPOS_DIR="/Users/Shared/Ghostties Demo/repos"

echo "==> Seeding Ghostties Demo workspace"
echo "    Target: $TARGET"
echo "    Repos:  $REPOS_DIR"
echo ""

# ── Safety check: never touch the release workspace ─────────────────────────
RELEASE_DIR="$HOME/Library/Application Support/Ghostties"
if [[ "$DEMO_DIR" == "$RELEASE_DIR" ]]; then
  echo "ERROR: Demo dir resolved to release dir. Aborting."
  exit 1
fi

# ── Create directories if needed ─────────────────────────────────────────────
if [[ ! -d "$DEMO_DIR" ]]; then
  echo "    Creating directory: $DEMO_DIR"
  mkdir -p "$DEMO_DIR"
  chmod 700 "$DEMO_DIR"
fi
mkdir -p "$REPOS_DIR"

# ── Back up existing workspace.json ─────────────────────────────────────────
if [[ -f "$TARGET" ]]; then
  BACKUP="$DEMO_DIR/workspace.json.bak-$(date +%Y%m%dT%H%M%S)"
  echo "    Backing up existing workspace.json -> $(basename "$BACKUP")"
  cp "$TARGET" "$BACKUP"
fi

# ── Projects: (name, extra-branch-or-empty) ──────────────────────────────────
declare -a PROJECT_SPECS=(
  "atlas-api|"
  "fieldwork|"
  "pendulum|feat/live-activity-widget"
  "silo|"
  "switchboard|feat/webhook-hmac"
  "trove|"
  "wren|fix/export-pdf-fonts"
  "brukas|"
  "annotie|"
  "ghostties|"
)

echo "==> Rebuilding fixture repos under $REPOS_DIR ..."
for spec in "${PROJECT_SPECS[@]}"; do
  IFS='|' read -r name extra_branch <<< "$spec"
  src="$FIXTURES_DIR/$name"
  dest="$REPOS_DIR/$name"

  if [[ ! -d "$src" ]]; then
    echo "ERROR: Fixture not found: $src" >&2
    exit 1
  fi

  rm -rf "$dest"
  mkdir -p "$dest"
  cp -R "$src/." "$dest/"

  git -C "$dest" init -q -b main
  git -C "$dest" config user.name "Demo User"
  git -C "$dest" config user.email "demo@example.com"
  git -C "$dest" add -A
  git -C "$dest" commit -q -m "Initial commit"

  if [[ -n "$extra_branch" ]]; then
    git -C "$dest" checkout -q -b "$extra_branch"
    git -C "$dest" checkout -q main
  fi

  echo "    $name -> $dest ($(git -C "$dest" branch --show-current))"
done
echo ""

# ── Generate JSON via python3 ────────────────────────────────────────────────
echo "    Generating workspace.json with ${#PROJECT_SPECS[@]} projects..."

python3 - "$TARGET" "$REPOS_DIR" <<'PYEOF'
import sys
import json
import subprocess
import datetime

target_path = sys.argv[1]
repos_dir = sys.argv[2]

projects_spec = [
    ("atlas-api",    "banshee"),
    ("fieldwork",    "clyde"),
    ("pendulum",     "ember"),
    ("silo",         "haunt"),
    ("switchboard",  "pinky"),
    ("trove",        "specter"),
    ("wren",         "wisp"),
    ("brukas",       "jinx"),
    ("annotie",      "mist"),
    ("ghostties",    "wraith"),
]

def new_uuid():
    result = subprocess.run(["uuidgen"], capture_output=True, text=True, check=True)
    return result.stdout.strip().upper()

now_base = datetime.datetime.utcnow()
projects = []
switchboard_id = None

CLAUDE_CODE_TEMPLATE_ID = "00000000-0000-0000-0000-000000000002"

for i, (name, ghost) in enumerate(projects_spec):
    uid = new_uuid()
    ts = (now_base - datetime.timedelta(hours=i * 3)).strftime("%Y-%m-%dT%H:%M:%SZ")
    proj = {
        "ghostCharacter": ghost,
        "id": uid,
        "isPinned": True,  # All projects pinned — renders control-tower disclosure rows
        "lastActiveAt": ts,
        "name": name,
        "rootPath": f"{repos_dir}/{name}",
    }
    if name == "switchboard":
        proj["defaultTemplateId"] = CLAUDE_CODE_TEMPLATE_ID
        switchboard_id = uid
    projects.append(proj)

state = {
    "hasDismissedPinMigrationNotice": True,
    "hasShownPinMigrationNotice": True,
    "lastSelectedProjectId": switchboard_id,
    "projects": projects,
    "sessions": [],
    "sidebarMode": 0,
    "templates": [],
}

with open(target_path, "w") as f:
    json.dump(state, f, indent=2, sort_keys=True)

print(f"    Written {len(projects)} projects.")
print(f"    switchboard UUID: {switchboard_id}")
print(f"    lastSelectedProjectId: {state['lastSelectedProjectId']}")
PYEOF

chmod 600 "$TARGET"

echo ""
echo "==> Verifying output..."
python3 - "$TARGET" <<'PYEOF'
import sys, json
with open(sys.argv[1]) as f:
    data = json.load(f)
projects = data['projects']
print(f"    Project count : {len(projects)}")
print(f"    sidebarMode   : {data['sidebarMode']}")
print(f"    lastSelected  : {data['lastSelectedProjectId']}")

all_pinned = all(p.get('isPinned') is True for p in projects)
print(f"    All isPinned  : {all_pinned}")
if not all_pinned:
    not_pinned = [p['name'] for p in projects if not p.get('isPinned')]
    print(f"    ERROR: unpinned projects: {not_pinned}")
    sys.exit(1)

switchboard = next((p for p in projects if p['name'] == 'switchboard'), None)
if switchboard:
    id_match = switchboard['id'] == data['lastSelectedProjectId']
    default_tmpl = switchboard.get('defaultTemplateId', '<missing>')
    print(f"    switchboard id: {switchboard['id']}")
    print(f"    lastSelected == switchboard: {id_match}")
    print(f"    defaultTemplateId : {default_tmpl}")
    if default_tmpl != "00000000-0000-0000-0000-000000000002":
        print("    ERROR: defaultTemplateId does not match AgentTemplate.claudeCode.id!")
        sys.exit(1)
else:
    print("    ERROR: switchboard project not found!")
    sys.exit(1)
PYEOF

# ── UI feature flags (NSUserDefaults — NOT in workspace.json) ────────────────
# These must be set via `defaults write` against the demo bundle ID.
# They are NOT stored in workspace.json; the app reads them from NSUserDefaults.
#
# NOTE: sidebarViewMode is intentionally set to "projectFirst", NOT "taskFirst".
# taskFirst mode routes through TaskStore which leaks real global sessions from
# the release app — not safe for demo captures.
echo ""
echo "==> Writing UI feature flags for com.seansmithdesign.ghostties.demo..."
defaults write com.seansmithdesign.ghostties.demo ghostties.hasSeenOnboarding -bool true
defaults write com.seansmithdesign.ghostties.demo ghostties.sidebarViewMode -string projectFirst
defaults write com.seansmithdesign.ghostties.demo ghostties.sidebarTab -string projects
echo "    ghostties.hasSeenOnboarding  = true"
echo "    ghostties.sidebarViewMode    = projectFirst"
echo "    ghostties.sidebarTab         = projects"

echo ""
echo "==> Done. Seed complete:"
echo "    $TARGET"

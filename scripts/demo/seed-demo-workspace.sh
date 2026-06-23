#!/usr/bin/env bash
# =============================================================================
# seed-demo-workspace.sh — Write isolated demo workspace.json for screen captures
#
# PURPOSE
#   Seeds ~/Library/Application Support/Ghostties Demo/workspace.json with 7
#   fictional projects that look realistic on camera. This directory is used
#   exclusively by Ghostties Demo.app (bundle ID com.seansmithdesign.ghostties.demo).
#   It NEVER touches ~/Library/Application Support/Ghostties/ (release workspace).
#
# USAGE
#   ./scripts/demo/seed-demo-workspace.sh
#
#   Idempotent / re-runnable. Any existing workspace.json is backed up to
#   workspace.json.bak-<timestamp> before overwriting.
#
# NON-REPRODUCIBLE ITEMS (not handled here)
#   - Branded shell prompt: `export PS1='ghostties ~/%1~ %% '`
#     This is per-shell-session and must be set by hand at capture time.
#     Making it persistent would require a demo-only ZDOTDIR override; that
#     is out of scope for this script.
# =============================================================================
set -euo pipefail

DEMO_DIR="$HOME/Library/Application Support/Ghostties Demo"
TARGET="$DEMO_DIR/workspace.json"

echo "==> Seeding Ghostties Demo workspace"
echo "    Target: $TARGET"
echo ""

# ── Safety check: never touch the release workspace ─────────────────────────
RELEASE_DIR="$HOME/Library/Application Support/Ghostties"
if [[ "$DEMO_DIR" == "$RELEASE_DIR" ]]; then
  echo "ERROR: Demo dir resolved to release dir. Aborting."
  exit 1
fi

# ── Create directory if needed ───────────────────────────────────────────────
if [[ ! -d "$DEMO_DIR" ]]; then
  echo "    Creating directory: $DEMO_DIR"
  mkdir -p "$DEMO_DIR"
  chmod 700 "$DEMO_DIR"
fi

# ── Back up existing workspace.json ─────────────────────────────────────────
if [[ -f "$TARGET" ]]; then
  BACKUP="$DEMO_DIR/workspace.json.bak-$(date +%Y%m%dT%H%M%S)"
  echo "    Backing up existing workspace.json -> $(basename "$BACKUP")"
  cp "$TARGET" "$BACKUP"
fi

# ── Generate JSON via python3 ────────────────────────────────────────────────
echo "    Generating workspace.json with 7 projects..."

python3 - "$TARGET" <<'PYEOF'
import sys
import json
import subprocess
import datetime

target_path = sys.argv[1]

demo_base = "/Users/seansmith/Code/ghostties/examples/demo-workspace"

projects_spec = [
    ("atlas-api",    "atlas-api",    "banshee"),
    ("fieldwork",    "fieldwork",    "clyde"),
    ("pendulum",     "pendulum",     "ember"),
    ("silo",         "silo",         "haunt"),
    ("switchboard",  "switchboard",  "pinky"),
    ("trove",        "trove",        "specter"),
    ("wren",         "wren",         "wisp"),
]

def new_uuid():
    result = subprocess.run(["uuidgen"], capture_output=True, text=True, check=True)
    return result.stdout.strip().upper()

# Build project list, track switchboard UUID for lastSelectedProjectId
now_base = datetime.datetime.utcnow()
projects = []
switchboard_id = None

CLAUDE_CODE_TEMPLATE_ID = "00000000-0000-0000-0000-000000000002"

for i, (name, subdir, ghost) in enumerate(projects_spec):
    uid = new_uuid()
    # Stagger timestamps slightly so they look like real usage history
    ts = (now_base - datetime.timedelta(hours=i * 3)).strftime("%Y-%m-%dT%H:%M:%SZ")
    proj = {
        "ghostCharacter": ghost,
        "id": uid,
        "isPinned": True,  # All projects pinned — renders control-tower disclosure rows
        "lastActiveAt": ts,
        "name": name,
        "rootPath": f"{demo_base}/{subdir}",
    }
    # Only switchboard gets the default template baked in
    if subdir == "switchboard":
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

# Confirm all projects are pinned
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

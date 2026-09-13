#!/usr/bin/env bash
# =============================================================================
# seed-demo-workspace.sh — Write isolated demo workspace.json for screen captures
#
# PURPOSE
#   Seeds ~/Library/Application Support/Ghostties Demo/workspace.json with 7
#   real, public, cloned repos (see DEMO_PROJECT_SPECS in _demo-paths.sh) that
#   look realistic on camera because they ARE realistic. This directory is
#   used exclusively by Ghostties Demo.app (bundle ID
#   com.seansmithdesign.ghostties.demo). It NEVER touches
#   ~/Library/Application Support/Ghostties/ (release workspace).
#
#   Each project is cloned at its pinned commit SHA into
#   "/Users/Shared/Ghostties Demo/repos/<name>/" as a normal, standalone git
#   repo on branch `main` (a few also get a second branch), so the demo has
#   real repo history and doesn't depend on this checkout's branch. Clones
#   are drawn from a persistent local cache (DEMO_CLONE_CACHE_DIR) so
#   re-seeding is fast and works offline once a SHA is cached. The repos
#   root lives outside $HOME (unlike the rest of the demo state dir) so
#   captured terminal panes never show a path containing the real username.
#
# USAGE
#   ./scripts/demo/seed-demo-workspace.sh
#
#   Idempotent / re-runnable. Any existing workspace.json is backed up to
#   workspace.json.bak-<timestamp> before overwriting. Repo copies under
#   repos/<name>/ are removed and recreated fresh on every run (cheap: they're
#   local clones off the cache, not re-downloads).
#
# NON-REPRODUCIBLE ITEMS (not handled here)
#   - Branded shell prompt: `export PS1='ghostties ~/%1~ %% '`
#     This is per-shell-session and must be set by hand at capture time.
#     Making it persistent would require a demo-only ZDOTDIR override; that
#     is out of scope for this script.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$REPO_ROOT/scripts/demo/_demo-paths.sh"

DEMO_DIR="$DEMO_STATE_DIR"
TARGET="$DEMO_DIR/workspace.json"

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

# ── Populate the local clone cache (network only on a cache miss) ──────────
echo "==> Ensuring clone cache is populated ($DEMO_CLONE_CACHE_DIR)..."
mkdir -p "$DEMO_CLONE_CACHE_DIR"
for spec in "${DEMO_PROJECT_SPECS[@]}"; do
  IFS='|' read -r name repo sha extra_branch ghost <<< "$spec"
  cache_dir="$DEMO_CLONE_CACHE_DIR/$name"

  if [[ -d "$cache_dir/.git" ]] && git -C "$cache_dir" cat-file -e "${sha}^{commit}" 2>/dev/null; then
    echo "    $name: cache hit @ ${sha:0:7} (no download)"
    continue
  fi

  echo "    $name: cache miss — cloning $repo @ ${sha:0:7} (depth 50)..."
  rm -rf "$cache_dir"
  git clone -q --depth 50 --no-tags "https://github.com/$repo.git" "$cache_dir"

  if ! git -C "$cache_dir" cat-file -e "${sha}^{commit}" 2>/dev/null; then
    echo "ERROR: pinned sha $sha not found in $repo after clone. The pin in" \
         "_demo-paths.sh (DEMO_PROJECT_SPECS) may be stale, or $repo's history" \
         "moved past the 50-commit shallow window." >&2
    exit 1
  fi
done
echo ""

# ── Seed REPOS_DIR from the cache: fresh local clone + checkout at the
#    pinned SHA on branch main ────────────────────────────────────────────────
echo "==> Rebuilding seeded repos under $REPOS_DIR ..."
for spec in "${DEMO_PROJECT_SPECS[@]}"; do
  IFS='|' read -r name repo sha extra_branch ghost <<< "$spec"
  cache_dir="$DEMO_CLONE_CACHE_DIR/$name"
  dest="$REPOS_DIR/$name"

  rm -rf "$dest"
  git clone -q --local "$cache_dir" "$dest"
  git -C "$dest" checkout -q -B main "$sha"

  if [[ -n "$extra_branch" ]]; then
    git -C "$dest" checkout -q -b "$extra_branch"
    git -C "$dest" checkout -q main
  fi

  # Suppress Claude Code's "/rc connecting..." startup line, which otherwise
  # shows in every captured pane because Sean's user settings have
  # remoteControlAtStartup: true. A project-level settings.local.json may
  # override to false (never to true). This is a REAL cloned repo now, so the
  # file must stay untracked — excluded via .git/info/exclude, never added to
  # the tracked history a pinned SHA is supposed to reproduce exactly.
  mkdir -p "$dest/.claude"
  echo ".claude/settings.local.json" >> "$dest/.git/info/exclude"
  python3 - "$dest/.claude/settings.local.json" <<'PYEOF'
import sys, json, os

path = sys.argv[1]
settings = {}
if os.path.isfile(path):
    with open(path) as f:
        try:
            settings = json.load(f)
        except json.JSONDecodeError:
            settings = {}

settings["remoteControlAtStartup"] = False

with open(path, "w") as f:
    json.dump(settings, f, indent=2, sort_keys=True)
    f.write("\n")
PYEOF

  size="$(du -sh "$dest" 2>/dev/null | cut -f1)"
  echo "    $name -> $dest ($(git -C "$dest" branch --show-current), $size)"
done
echo ""

# ── Generate JSON via python3 ────────────────────────────────────────────────
echo "    Generating workspace.json with ${#DEMO_PROJECT_SPECS[@]} projects..."

# DEMO_PROJECT_SPECS (from _demo-paths.sh) is "name|repo|sha|branch|ghost";
# reduce to "name|ghost" for the JSON generator below.
PROJECTS_SPEC_ARG=""
for spec in "${DEMO_PROJECT_SPECS[@]}"; do
  IFS='|' read -r name _repo _sha _branch ghost <<< "$spec"
  PROJECTS_SPEC_ARG+="$name|$ghost"$'\n'
done

python3 - "$TARGET" "$REPOS_DIR" "$PROJECTS_SPEC_ARG" <<'PYEOF'
import sys
import json
import subprocess
import datetime

target_path = sys.argv[1]
repos_dir = sys.argv[2]
projects_spec_raw = sys.argv[3]

projects_spec = [
    tuple(line.split("|"))
    for line in projects_spec_raw.splitlines()
    if line.strip()
]

def new_uuid():
    result = subprocess.run(["uuidgen"], capture_output=True, text=True, check=True)
    return result.stdout.strip().upper()

now_base = datetime.datetime.utcnow()
projects = []
default_project_id = None

# "ghostties" (first in DEMO_PROJECT_SPECS) is the Claude Code default
# template + last-selected project — this used to be "switchboard" before
# the fixture set switched to real cloned repos.
DEFAULT_PROJECT_NAME = "ghostties"
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
    if name == DEFAULT_PROJECT_NAME:
        proj["defaultTemplateId"] = CLAUDE_CODE_TEMPLATE_ID
        default_project_id = uid
    projects.append(proj)

state = {
    "hasDismissedPinMigrationNotice": True,
    "hasShownPinMigrationNotice": True,
    "lastSelectedProjectId": default_project_id,
    "projects": projects,
    "sessions": [],
    "sidebarMode": 0,
    "templates": [],
}

with open(target_path, "w") as f:
    json.dump(state, f, indent=2, sort_keys=True)

print(f"    Written {len(projects)} projects.")
print(f"    {DEFAULT_PROJECT_NAME} UUID: {default_project_id}")
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

default_project = next((p for p in projects if p['name'] == 'ghostties'), None)
if default_project:
    id_match = default_project['id'] == data['lastSelectedProjectId']
    default_tmpl = default_project.get('defaultTemplateId', '<missing>')
    print(f"    ghostties id: {default_project['id']}")
    print(f"    lastSelected == ghostties: {id_match}")
    print(f"    defaultTemplateId : {default_tmpl}")
    if default_tmpl != "00000000-0000-0000-0000-000000000002":
        print("    ERROR: defaultTemplateId does not match AgentTemplate.claudeCode.id!")
        sys.exit(1)
else:
    print("    ERROR: ghostties project not found!")
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

#!/usr/bin/env bash
# =============================================================================
# _stage-demo-sessions.sh — Core staged-session writer, shared by demo-ready.sh
# and demo-drive.sh.
#
# Not a standalone entrypoint: no preconditions (app-currency, fixture trust,
# "is the app running") are enforced here — callers own those. This is kept
# separate from demo-drive.sh so demo-ready.sh can stage sessions during its
# own bootstrap without calling back into demo-drive.sh, which itself checks
# `demo-ready.sh --check` as a precondition — calling demo-drive.sh from
# demo-ready.sh would create a demo-ready -> demo-drive -> demo-ready cycle
# that deadlocks on the very first run, before any sessions exist to check.
#
# USAGE (internal — called by demo-ready.sh / demo-drive.sh only)
#   ./scripts/demo/_stage-demo-sessions.sh [--count N] [--reset]
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/scripts/demo/_demo-paths.sh"

TARGET="$DEMO_STATE_DIR/workspace.json"
TEMPLATE_MARKER="Demo Drive: "

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

if [[ ! -f "$TARGET" ]]; then
  echo "ERROR: $TARGET does not exist. Run seed-demo-workspace.sh (or demo-ready.sh) first." >&2
  exit 1
fi

# ── Resolve claude's absolute path now, at staging time ─────────────────────
# Baking the resolved path into each wrapper means a staged session's launch
# doesn't depend on the spawned process's PATH (which, inside the GUI app,
# is minimal — see SessionCoordinator.resolveCommand's own PATH-recovery
# fallback for the same reason).
CLAUDE_BIN="$(command -v claude || true)"
if [[ -z "$CLAUDE_BIN" ]]; then
  echo "ERROR: 'claude' not found on PATH. Cannot stage sessions without a resolvable claude binary." >&2
  exit 1
fi

# ── Wrapper scripts: WorkspacePersistence.sanitizeTemplate strips any
#    agent.additionalFlags entry that isn't a CLI flag (^--?[a-zA-Z]...), so a
#    plain prompt sentence placed there is silently dropped and `claude`
#    launches with no prompt. Instead, stage one small executable wrapper per
#    prompt and point the template's `command` at its absolute, space-free
#    path; the wrapper execs the resolved claude binary with the prompt as a
#    single argv entry. DEMO_WRAPPER_DIR (see _demo-paths.sh) is deliberately
#    outside the space-containing demo state/repos dirs: SessionCoordinator
#    extracts the base command by splitting on the first whitespace
#    character, so a path containing a space would be truncated there.
mkdir -p "$DEMO_WRAPPER_DIR"
chmod 700 "$DEMO_WRAPPER_DIR"

# ── Back up existing workspace.json ─────────────────────────────────────────
BACKUP="$DEMO_STATE_DIR/workspace.json.bak-$(date +%Y%m%dT%H%M%S)"
echo "==> Backing up existing workspace.json -> $(basename "$BACKUP")"
cp "$TARGET" "$BACKUP"
echo ""

# ── Write staged sessions via python3 (atomic temp-file swap) ───────────────
TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/workspace.XXXXXX.json")"
trap 'rm -f "$TMP_FILE"' EXIT

echo "==> Rewriting workspace.json..."
python3 - "$TARGET" "$TMP_FILE" "$REPOS_DIR" "$COUNT" "$RESET" "$DEMO_SESSION_MARKER" "$TEMPLATE_MARKER" "$DEMO_WRAPPER_DIR" "$CLAUDE_BIN" <<'PYEOF'
import sys
import json
import subprocess
import os
import shlex

target_path, tmp_path, repos_dir, count_str, reset_str, session_marker, template_marker, wrapper_dir, claude_bin = sys.argv[1:10]
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

# Clear previously staged wrapper scripts so re-running doesn't accumulate
# stale wrappers pointing at a since-removed template.
if os.path.isdir(wrapper_dir):
    for name in os.listdir(wrapper_dir):
        if name.startswith("demo-drive-"):
            os.remove(os.path.join(wrapper_dir, name))

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

    # Wrapper script: sanitizeTemplate strips a plain-sentence prompt out of
    # agent.additionalFlags (only entries matching ^--?[a-zA-Z]... survive),
    # so the prompt is baked into a small executable wrapper instead, and the
    # template's `command` points at the wrapper's absolute path. The wrapper
    # execs claude directly (no shell re-parsing) so the prompt always
    # arrives as exactly one argv entry, regardless of spaces/punctuation.
    wrapper_path = os.path.join(wrapper_dir, f"demo-drive-{template_id}.sh")
    wrapper_script = (
        "#!/bin/sh\n"
        f"exec {shlex.quote(claude_bin)} {shlex.quote(prompt)}\n"
    )
    with open(wrapper_path, "w") as wf:
        wf.write(wrapper_script)
    os.chmod(wrapper_path, 0o700)

    template = {
        "id": template_id,
        "name": f"{template_marker}{project_name}",
        "kind": "claudeCode",
        "isDefault": False,
        "isGlobal": False,
        "projectId": project["id"],
        "command": wrapper_path,
        "environmentVariables": {},
        "workingDirectory": root_path,
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
python3 - "$TARGET" "$DEMO_SESSION_MARKER" <<'PYEOF'
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

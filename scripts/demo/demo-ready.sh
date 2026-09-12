#!/usr/bin/env bash
# =============================================================================
# demo-ready.sh — Single preflight entrypoint for capturing Ghostties Demo assets
#
# PURPOSE
#   The one command an agent (or Sean) runs before capturing anything. It makes
#   it structurally impossible to shoot from a stale demo build: it checks the
#   installed demo app's version/commit against the intended source of truth,
#   refreshes only if needed, always reseeds the fixture workspace, and writes
#   a manifest recording exactly what produced the app now on disk.
#
# MODES
#   --release (default)  Compare the installed app's CFBundleShortVersionString
#                         against the newest tag on SeanSmithWorks/ghostties
#                         (gh release list, pre-releases included).
#   --source              Compare the installed app's GhosttyCommit (an
#                         Info.plist key this script sets on --from-source
#                         builds) against this checkout's HEAD sha. Never
#                         compares against a release tag.
#
# USAGE
#   ./scripts/demo/demo-ready.sh                       # ensure release-current, reseed
#   ./scripts/demo/demo-ready.sh --check                # assert freshness, exit non-zero if stale
#   ./scripts/demo/demo-ready.sh --source                # demo the current checkout instead
#   ./scripts/demo/demo-ready.sh --dest /path/x.app      # non-default app location (testing)
#
# FLAGS
#   --check         Report status and exit non-zero if stale or missing. Never
#                   refreshes, never reseeds, never touches the app or fixture
#                   workspace — but a PASSING check still writes the manifest,
#                   since that's the record of which bundle it just verified.
#   --dest <path>   Demo app path. Default: /Applications/Ghostties Demo.app
#   --source        Use this checkout (refresh-demo.sh --from-source) instead
#                   of the newest release. "Current" means the app's recorded
#                   git sha equals this checkout's HEAD sha.
#
# MANIFEST
#   Written on every successful run (including a passing --check) to:
#     ~/Library/Application Support/Ghostties Demo/demo-manifest.json
#   regardless of --dest, because seed-demo-workspace.sh is likewise pinned to
#   that fixed state directory (it is keyed off the demo bundle ID, not the
#   app's install location). destPath always records the resolved, absolute
#   path of the app that was actually inspected — the manifest describes
#   whatever bundle the run just checked or refreshed, not a fixed default.
#   A capture run should copy this file next to whatever assets it produces —
#   see scripts/demo/README.md.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REFRESH_SCRIPT="$REPO_ROOT/scripts/demo/refresh-demo.sh"
SEED_SCRIPT="$REPO_ROOT/scripts/demo/seed-demo-workspace.sh"
STAGE_SCRIPT="$REPO_ROOT/scripts/demo/_stage-demo-sessions.sh"
FIXTURES_DIR="$REPO_ROOT/examples/demo-workspace"
RELEASE_REPO="SeanSmithWorks/ghostties"
ASSET_NAME="ghostties-macos-arm64.zip"

source "$REPO_ROOT/scripts/demo/_demo-paths.sh"

MANIFEST_PATH="$DEMO_STATE_DIR/demo-manifest.json"
# Claude Code's own trust store. Overridable for fail-closed verification
# against a scratch copy — never used against the real file in normal runs.
CLAUDE_CONFIG="${DEMO_CLAUDE_CONFIG:-$HOME/.claude.json}"

MODE="release"
DEST_APP="/Applications/Ghostties Demo.app"
CHECK_ONLY=0

# ── Arg parsing ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      CHECK_ONLY=1
      shift
      ;;
    --dest)
      DEST_APP="$2"
      shift 2
      ;;
    --source)
      MODE="source"
      shift
      ;;
    *)
      echo "ERROR: Unrecognized argument: $1" >&2
      exit 1
      ;;
  esac
done

fail() {
  echo "ERROR: $1" >&2
  exit 1
}

plist_get() {
  # plist_get <plist-path> <key>  -> prints value, or "" if unreadable/missing
  local plist="$1" key="$2"
  /usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null || true
}

echo "==> Ghostties demo-ready preflight"
echo "    Mode: $MODE"
echo "    Dest: $DEST_APP"
echo "    Check-only: $([[ "$CHECK_ONLY" -eq 1 ]] && echo yes || echo no)"
echo ""

PLIST="$DEST_APP/Contents/Info.plist"
APP_EXISTS=0
[[ -d "$DEST_APP" && -f "$PLIST" ]] && APP_EXISTS=1

SOURCE_LABEL=""
CURRENT=0
REFRESH_ARGS=()
SUMMARY_VERSION=""

if [[ "$MODE" == "release" ]]; then
  echo "==> Resolving newest release (including pre-releases) on $RELEASE_REPO..."
  if ! RELEASE_JSON=$(gh release list --repo "$RELEASE_REPO" --limit 1 --json tagName 2>&1); then
    fail "Could not reach GitHub to list releases for $RELEASE_REPO (gh failed: ${RELEASE_JSON}). Check 'gh auth status' and network connectivity."
  fi
  TAG=$(echo "$RELEASE_JSON" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d[0]["tagName"] if d else "")')
  if [[ -z "$TAG" ]]; then
    fail "No releases found on $RELEASE_REPO. Cannot determine the newest tag."
  fi
  echo "    Resolved tag: $TAG"

  echo "==> Verifying release asset '$ASSET_NAME' exists on $TAG..."
  if ! ASSET_JSON=$(gh release view "$TAG" --repo "$RELEASE_REPO" --json assets 2>&1); then
    fail "Could not read release '$TAG' on $RELEASE_REPO (gh failed: ${ASSET_JSON})."
  fi
  HAS_ASSET=$(echo "$ASSET_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print('yes' if any(a['name']=='$ASSET_NAME' for a in d.get('assets', [])) else 'no')")
  if [[ "$HAS_ASSET" != "yes" ]]; then
    fail "Release '$TAG' on $RELEASE_REPO has no '$ASSET_NAME' asset. Refusing to fall back to whatever demo app happens to be installed."
  fi
  echo "    Asset present."
  echo ""

  WANT_VERSION="${TAG#v}"
  SOURCE_LABEL="$TAG"

  if [[ "$APP_EXISTS" -eq 1 ]]; then
    INSTALLED_VERSION=$(plist_get "$PLIST" CFBundleShortVersionString)
  else
    INSTALLED_VERSION=""
  fi
  SUMMARY_VERSION="$WANT_VERSION"

  if [[ "$APP_EXISTS" -eq 0 ]]; then
    echo "==> No demo app at '$DEST_APP'."
  elif [[ -z "$INSTALLED_VERSION" ]]; then
    echo "==> Demo app at '$DEST_APP' has no readable CFBundleShortVersionString — treating as stale."
  elif [[ "$INSTALLED_VERSION" == "$WANT_VERSION" ]]; then
    CURRENT=1
    echo "==> Demo app is already at $INSTALLED_VERSION (matches newest tag $TAG)."
  else
    echo "==> Demo app is at $INSTALLED_VERSION, newest tag is $TAG ($WANT_VERSION) — stale."
  fi
  REFRESH_ARGS=(--from-release "$TAG" --dest "$DEST_APP" --no-launch)

else
  # ── --source ──────────────────────────────────────────────────────────────
  HEAD_REF=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)
  HEAD_SHA=$(git -C "$REPO_ROOT" rev-parse HEAD)
  HEAD_SHORT=$(git -C "$REPO_ROOT" rev-parse --short HEAD)
  SOURCE_LABEL="$HEAD_REF @ $HEAD_SHORT"
  SUMMARY_VERSION="$HEAD_SHORT"
  echo "==> Source checkout: $REPO_ROOT"
  echo "    Ref: $HEAD_REF  SHA: $HEAD_SHA"
  echo ""

  if [[ "$APP_EXISTS" -eq 1 ]]; then
    INSTALLED_SHA=$(plist_get "$PLIST" GhosttyCommit)
  else
    INSTALLED_SHA=""
  fi

  if [[ "$APP_EXISTS" -eq 0 ]]; then
    echo "==> No demo app at '$DEST_APP'."
  elif [[ -z "$INSTALLED_SHA" ]]; then
    echo "==> Demo app at '$DEST_APP' has no recorded GhosttyCommit — treating as stale."
  elif [[ "$INSTALLED_SHA" == "$HEAD_SHA" ]]; then
    CURRENT=1
    echo "==> Demo app already built from $HEAD_REF @ $HEAD_SHORT."
  else
    INSTALLED_SHORT="${INSTALLED_SHA:0:7}"
    echo "==> Demo app was built from $INSTALLED_SHORT, checkout HEAD is $HEAD_SHORT — stale."
  fi
  REFRESH_ARGS=(--from-source --dest "$DEST_APP" --no-launch)
fi

echo ""

# ── Manifest writer: records exactly which bundle was just inspected/refreshed ─
write_manifest() {
  local dest_app_resolved
  dest_app_resolved="$(cd "$(dirname "$DEST_APP")" && pwd)/$(basename "$DEST_APP")"

  local fixture_count app_mtime_epoch app_mtime_iso refreshed_at installed_version_now
  fixture_count=$(find "$FIXTURES_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  app_mtime_epoch=$(stat -f%m "$dest_app_resolved")
  app_mtime_iso=$(date -u -r "$app_mtime_epoch" +"%Y-%m-%dT%H:%M:%SZ")
  refreshed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  if [[ "$MODE" == "release" ]]; then
    installed_version_now=$(plist_get "$PLIST" CFBundleShortVersionString)
  else
    installed_version_now=$(plist_get "$PLIST" GhosttyCommit)
  fi

  mkdir -p "$DEMO_STATE_DIR"
  chmod 700 "$DEMO_STATE_DIR"

  python3 - "$MANIFEST_PATH" <<PYEOF
import json

manifest = {
    "demoAppVersion": "$installed_version_now",
    "mode": "$MODE",
    "source": "$SOURCE_LABEL",
    "destPath": "$dest_app_resolved",
    "appBundleMtime": "$app_mtime_iso",
    "refreshedAt": "$refreshed_at",
    "fixtureProjectCount": $fixture_count,
    "seededReposPath": "$REPOS_DIR",
}

with open("$MANIFEST_PATH", "w") as f:
    json.dump(manifest, f, indent=2, sort_keys=True)
PYEOF
  chmod 600 "$MANIFEST_PATH"

  echo "==> Wrote manifest: $MANIFEST_PATH"
}

# ── Fixture trust: mark only the seeded fixture repo paths as trusted in
#    Claude Code's own config, so a staged `claude` session doesn't stop at
#    the "Do you trust this folder?" screen during capture. Never touches
#    any other key or project entry. See scripts/demo/README.md.
check_fixture_trust() {
  python3 - "$CLAUDE_CONFIG" "$FIXTURES_DIR" "$REPOS_DIR" <<'PYEOF'
import sys, os, json

config_path, fixtures_dir, repos_dir = sys.argv[1:4]

if not os.path.isfile(config_path):
    print(f"ERROR: Claude config not found at {config_path}", file=sys.stderr)
    sys.exit(1)

with open(config_path) as f:
    try:
        data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"ERROR: {config_path} is not valid JSON: {e}", file=sys.stderr)
        sys.exit(1)

projects = data.get("projects", {})
fixture_names = sorted(
    n for n in os.listdir(fixtures_dir)
    if os.path.isdir(os.path.join(fixtures_dir, n))
)

untrusted = []
for name in fixture_names:
    path = os.path.join(repos_dir, name)
    entry = projects.get(path)
    if not entry or entry.get("hasTrustDialogAccepted") is not True:
        untrusted.append(name)

if untrusted:
    print(f"NOT READY: fixture repo(s) not trusted in {config_path}: {', '.join(untrusted)}", file=sys.stderr)
    print("           Fix: run ./scripts/demo/demo-ready.sh (without --check) to write trust entries.", file=sys.stderr)
    sys.exit(1)

print(f"OK: trusted {len(fixture_names)}/{len(fixture_names)} fixture paths in {config_path}.")
PYEOF
}

ensure_fixture_trust() {
  echo "==> Ensuring fixture repos are trusted in Claude Code config ($CLAUDE_CONFIG)..."
  python3 - "$CLAUDE_CONFIG" "$FIXTURES_DIR" "$REPOS_DIR" <<'PYEOF'
import sys, os, json, time, shutil

config_path, fixtures_dir, repos_dir = sys.argv[1:4]

if not os.path.isfile(config_path):
    print(f"ERROR: Claude config not found at {config_path}", file=sys.stderr)
    sys.exit(1)

with open(config_path, "r") as f:
    raw = f.read()
try:
    data = json.loads(raw)
except json.JSONDecodeError as e:
    print(f"ERROR: {config_path} is not valid JSON: {e}", file=sys.stderr)
    sys.exit(1)

if "projects" not in data or not isinstance(data["projects"], dict):
    print(f"ERROR: {config_path} has no top-level 'projects' object — refusing to invent one.", file=sys.stderr)
    sys.exit(1)

# Detect the file's existing indent so the rewrite matches its formatting.
indent = "  "
for line in raw.split("\n")[1:]:
    stripped = line.lstrip(" \t")
    if stripped and stripped != line:
        indent = line[: len(line) - len(stripped)]
        break
trailing_newline = raw.endswith("\n")

fixture_names = sorted(
    n for n in os.listdir(fixtures_dir)
    if os.path.isdir(os.path.join(fixtures_dir, n))
)

projects = data["projects"]
before_count = len(projects)
changed = False
trusted = 0

for name in fixture_names:
    path = os.path.join(repos_dir, name)
    entry = projects.get(path)
    if entry is None:
        projects[path] = {"hasTrustDialogAccepted": True}
        changed = True
    elif entry.get("hasTrustDialogAccepted") is not True:
        entry["hasTrustDialogAccepted"] = True
        changed = True
    trusted += 1

if not changed:
    print("NOCHANGE")
    print(f"TRUSTED={trusted}")
    print(f"BEFORE={before_count}")
    print(f"AFTER={before_count}")
    sys.exit(0)

after_count = len(projects)

backup_path = f"{config_path}.bak-demo-{time.strftime('%Y%m%dT%H%M%S')}"
shutil.copy2(config_path, backup_path)

dirn = os.path.dirname(config_path) or "."
tmp_path = os.path.join(dirn, f".{os.path.basename(config_path)}.tmp-{os.getpid()}")
mode = os.stat(config_path).st_mode

with open(tmp_path, "w") as f:
    json.dump(data, f, indent=indent, separators=(",", ": "))
    if trailing_newline:
        f.write("\n")

os.chmod(tmp_path, mode)
os.replace(tmp_path, config_path)

print(f"BACKUP={backup_path}")
print(f"TRUSTED={trusted}")
print(f"BEFORE={before_count}")
print(f"AFTER={after_count}")
PYEOF
}

# ── Staged sessions check: "ready" must mean sessions are staged, not just
#    app-current + fixtures-seeded — a reseed silently wipes staged sessions
#    (seed-demo-workspace.sh always writes a fresh, session-free
#    workspace.json) and the preflight previously had no way to see that.
#    Expected count is derived from DEMO_DRIVE_DEFAULT_COUNT in
#    _demo-paths.sh, not hardcoded here.
check_staged_sessions() {
  local target="$DEMO_STATE_DIR/workspace.json"
  if [[ ! -f "$target" ]]; then
    echo "NOT READY: no workspace.json at $target — fixtures were never seeded." >&2
    echo "           Fix: run ./scripts/demo/demo-ready.sh (without --check)." >&2
    return 1
  fi
  python3 - "$target" "$DEMO_SESSION_MARKER" "$DEMO_DRIVE_DEFAULT_COUNT" <<'PYEOF'
import sys, json

target_path, marker, expected_str = sys.argv[1:4]
expected = int(expected_str)

with open(target_path) as f:
    data = json.load(f)

staged = [s for s in data.get("sessions", []) if s.get("name", "").startswith(marker)]
if len(staged) < expected:
    print(f"NOT READY: only {len(staged)}/{expected} staged session(s) found in {target_path} (marker '{marker}').", file=sys.stderr)
    print("           Fix: run ./scripts/demo/demo-ready.sh (without --check) to stage sessions.", file=sys.stderr)
    sys.exit(1)

print(f"OK: {len(staged)}/{expected} staged session(s) found in {target_path}.")
PYEOF
}

# ── --check: report only, never touch the app/fixtures — but do record what
#             was just verified, so a passing check can't leave a stale manifest
if [[ "$CHECK_ONLY" -eq 1 ]]; then
  if [[ "$CURRENT" -eq 1 ]]; then
    if ! check_fixture_trust; then
      exit 1
    fi
    if ! check_staged_sessions; then
      exit 1
    fi
    echo "OK: Ghostties Demo is current (source: $SOURCE_LABEL, dest: $DEST_APP)."
    write_manifest
    exit 0
  else
    echo "STALE: Ghostties Demo at '$DEST_APP' does not match $SOURCE_LABEL. Run demo-ready.sh (without --check) to refresh." >&2
    exit 1
  fi
fi

# ── Refresh if needed ────────────────────────────────────────────────────────
DID_REFRESH=0
if [[ "$CURRENT" -eq 1 ]]; then
  echo "==> App already current — skipping refresh."
else
  echo "==> Refreshing: $REFRESH_SCRIPT ${REFRESH_ARGS[*]}"
  "$REFRESH_SCRIPT" "${REFRESH_ARGS[@]}"
  DID_REFRESH=1

  if [[ "$MODE" == "source" ]]; then
    echo "==> Recording built commit sha into Info.plist (GhosttyCommit)..."
    /usr/libexec/PlistBuddy -c "Set :GhosttyCommit $HEAD_SHA" "$PLIST"
  fi
fi
echo ""

# ── Always reseed the fixture workspace ─────────────────────────────────────
echo "==> Seeding fixture workspace..."
"$SEED_SCRIPT"
echo ""

# ── Ensure fixture repos are trusted, so staged `claude` sessions don't stop
#    at a trust prompt during capture ────────────────────────────────────────
TRUST_OUTPUT="$(ensure_fixture_trust)"
echo "$TRUST_OUTPUT"
if echo "$TRUST_OUTPUT" | grep -q '^BACKUP='; then
  echo "    Backup: $(echo "$TRUST_OUTPUT" | sed -n 's/^BACKUP=//p')"
fi
TRUST_BEFORE="$(echo "$TRUST_OUTPUT" | sed -n 's/^BEFORE=//p')"
TRUST_AFTER="$(echo "$TRUST_OUTPUT" | sed -n 's/^AFTER=//p')"
TRUST_COUNT="$(echo "$TRUST_OUTPUT" | sed -n 's/^TRUSTED=//p')"
echo "    Trusted fixture paths: $TRUST_COUNT (projects before=$TRUST_BEFORE after=$TRUST_AFTER)"

echo "==> Verifying fixture trust..."
if ! check_fixture_trust; then
  fail "Fixture trust verification failed after write — see message above."
fi
echo ""

# ── Stage demo agent sessions — seeding above always wipes any previously
#    staged sessions, so this must run every time, not just once. Calls the
#    staging logic directly (not demo-drive.sh) to avoid a demo-ready ->
#    demo-drive -> demo-ready cycle: demo-drive.sh checks
#    `demo-ready.sh --check` as its own precondition, which would deadlock on
#    a first run before any sessions exist yet to satisfy that check.
echo "==> Staging demo agent sessions..."
"$STAGE_SCRIPT" --count "$DEMO_DRIVE_DEFAULT_COUNT"
echo ""

# ── Write manifest ───────────────────────────────────────────────────────────
write_manifest
echo ""

# ── Summary ──────────────────────────────────────────────────────────────────
if [[ "$DID_REFRESH" -eq 1 ]]; then
  ACTION="refreshed"
else
  ACTION="already current"
fi
if [[ "$MODE" == "release" ]]; then
  echo "Demo ready: Ghostties Demo v$SUMMARY_VERSION (source: $SOURCE_LABEL) — $ACTION"
else
  echo "Demo ready: Ghostties Demo @ $SUMMARY_VERSION (source: $SOURCE_LABEL) — $ACTION"
fi

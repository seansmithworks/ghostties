#!/bin/bash
# stamp-dev-build-info.sh — Called from Xcode "Stamp Dev Build Info" build
# phase (Ghostties target, after Info.plist has been processed into the
# built product).
#
# Writes two Info.plist keys into the built app bundle so
# BuildInfoBadgeView.swift can show which Claude Code thread produced a Dev
# build:
#   GhosttyDevThreadName  — best-effort session name (see below), or the
#                           worktree directory name if unavailable
#   GhosttyDevBuildSHA    — `git rev-parse --short HEAD` for this checkout
#
# Debug/Dev builds ONLY. Release and CI builds must never read ~/.claude and
# must never fail this build phase when it's absent — this script exits 0
# immediately for any non-Debug configuration, before touching ~/.claude.
#
# Thread-name source: Claude Code writes ~/.claude/sessions/<pid>.json with
# fields pid, cwd, name, updatedAt. We pick the entry whose cwd equals this
# checkout's git toplevel and whose pid is a live process, preferring the
# newest updatedAt. Best-effort throughout — any failure here (missing dir,
# malformed JSON, no matching session) falls back silently, never fails the
# build.
set -uo pipefail

if [[ "${CONFIGURATION:-}" != "Debug" ]]; then
  exit 0
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="${CODESIGNING_FOLDER_PATH:-${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}}/Contents/Info.plist"

if [[ ! -f "$PLIST" ]]; then
  echo "warning: stamp-dev-build-info.sh: no Info.plist at $PLIST — skipping."
  exit 0
fi

TOPLEVEL="$(git -C "$REPO_ROOT" rev-parse --show-toplevel 2>/dev/null || true)"
SHORT_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"

THREAD_NAME="$(python3 - "$HOME/.claude/sessions" "$TOPLEVEL" <<'PYEOF' 2>/dev/null
import sys, os, json

sessions_dir, toplevel = sys.argv[1:3]

if not toplevel or not os.path.isdir(sessions_dir):
    sys.exit(0)

best = None
for fname in os.listdir(sessions_dir):
    if not fname.endswith(".json"):
        continue
    path = os.path.join(sessions_dir, fname)
    try:
        with open(path) as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        continue

    if data.get("cwd") != toplevel:
        continue

    pid = data.get("pid")
    if not isinstance(pid, int):
        continue
    try:
        os.kill(pid, 0)
    except OSError:
        continue  # pid not alive

    name = data.get("name")
    if not name:
        continue

    updated_at = data.get("updatedAt", "")
    if best is None or updated_at > best[0]:
        best = (updated_at, name)

if best:
    print(best[1])
PYEOF
)"

if [[ -z "$THREAD_NAME" ]]; then
  # Fallback: the worktree directory name.
  THREAD_NAME="$(basename "$REPO_ROOT")"
fi

/usr/libexec/PlistBuddy -c "Delete :GhosttyDevThreadName" "$PLIST" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :GhosttyDevThreadName string $THREAD_NAME" "$PLIST" >/dev/null 2>&1

/usr/libexec/PlistBuddy -c "Delete :GhosttyDevBuildSHA" "$PLIST" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :GhosttyDevBuildSHA string $SHORT_SHA" "$PLIST" >/dev/null 2>&1

echo "stamp-dev-build-info.sh: GhosttyDevThreadName=$THREAD_NAME GhosttyDevBuildSHA=$SHORT_SHA"
exit 0

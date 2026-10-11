#!/usr/bin/env bash
# Build (once) and start the DialKit macOS inspector that tunes Ghostties Dev live.
#
# The inspector is a standalone app from mikelikesdesign/dialkit-macos, NOT part of
# this repo (macos/Packages/DialkitmacOS only vendors the in-app agent). The pin
# below must match macos/Packages/DialkitmacOS/VENDORED.md.
#
# Usage: scripts/open-dialkit.sh [--build-only | --foreground]
#   (default)     start detached, print pid + log path, return immediately;
#                 does nothing if an inspector is already running
#   --build-only  fetch + build, do not start
#   --foreground  run attached to this terminal (for humans)
# Start the inspector BEFORE launching Ghostties Dev; the Dev agent connects to
# 127.0.0.1:44777 at launch. Installs to ~/Library/Caches/ghostties/dialkit/<sha>.
set -euo pipefail

SHA="cc305b46beb731e50cbdde84aed5530d83842acc"
REPO="https://github.com/mikelikesdesign/dialkit-macos.git"
DIR="${GHOSTTIES_DIALKIT_DIR:-$HOME/Library/Caches/ghostties/dialkit}/$SHA"

MODE="${1:-detach}"
case "$MODE" in
  detach|--build-only|--foreground) ;;
  *) echo "usage: $0 [--build-only | --foreground]" >&2; exit 2 ;;
esac
[ $# -le 1 ] || { echo "usage: $0 [--build-only | --foreground]" >&2; exit 2; }

BIN="$DIR/.build/out/Products/Release/dialkit-macos"
LOG="$(dirname "$DIR")/inspector-$SHA.log"

# Running guard first: nothing below may touch the cache while the inspector runs from it.
if pgrep -f "$BIN" >/dev/null || lsof -nP -iTCP:44777 -sTCP:LISTEN >/dev/null 2>&1; then
  if [ "$MODE" = "--build-only" ]; then
    echo "Inspector is running; refusing to rebuild its cache. Stop it first." >&2
    exit 1
  fi
  echo "Inspector already running (pid $(pgrep -f "$BIN" | head -1 || true)); not starting another."
  exit 0
fi

mkdir -p "$DIR"
[ -d "$DIR/.git" ] || git -C "$DIR" init -q
git -C "$DIR" remote add origin "$REPO" 2>/dev/null || git -C "$DIR" remote set-url origin "$REPO"

# Pristine pinned tree: wrong commit or any local change -> refetch from scratch.
if [ "$(git -C "$DIR" rev-parse -q --verify HEAD 2>/dev/null || true)" != "$SHA" ] \
   || [ -n "$(git -C "$DIR" status --porcelain --untracked-files=no)" ]; then
  rm -rf "$DIR"
  mkdir -p "$DIR"
  git -C "$DIR" init -q
  git -C "$DIR" remote add origin "$REPO"
  git -C "$DIR" fetch -q --depth 1 origin "$SHA"
  git -C "$DIR" checkout -q --detach FETCH_HEAD
fi

(cd "$DIR" && swift build -c release --product dialkit-macos)
echo "DialKit inspector: $BIN"

case "$MODE" in
  --build-only) exit 0 ;;
  --foreground)
    echo "Launch Ghostties Dev after this starts so its agent connects."
    exec "$BIN" ;;
esac

[ -x "$BIN" ] || { echo "build did not produce $BIN" >&2; exit 1; }
nohup "$BIN" >"$LOG" 2>&1 &
PID=$!
disown
echo "Started inspector pid $PID (log: $LOG). Launch Ghostties Dev now so its agent connects."

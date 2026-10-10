#!/usr/bin/env bash
# Build (once) and run the DialKit macOS inspector that tunes Ghostties Dev live.
#
# The inspector is a standalone app from mikelikesdesign/dialkit-macos, NOT part of
# this repo (macos/Packages/DialkitmacOS only vendors the in-app agent). The pin
# below must match macos/Packages/DialkitmacOS/VENDORED.md.
#
# Usage: scripts/open-dialkit.sh [--build-only]
# Start the inspector BEFORE launching Ghostties Dev; the Dev agent connects to
# 127.0.0.1:44777 at launch. Installs to ~/Library/Caches/ghostties/dialkit/<sha>.
set -euo pipefail

SHA="cc305b46beb731e50cbdde84aed5530d83842acc"
REPO="https://github.com/mikelikesdesign/dialkit-macos.git"
DIR="${GHOSTTIES_DIALKIT_DIR:-$HOME/Library/Caches/ghostties/dialkit}/$SHA"

if [ ! -d "$DIR/.git" ]; then
  mkdir -p "$DIR"
  git -C "$DIR" init -q
  git -C "$DIR" remote add origin "$REPO"
fi
if [ "$(git -C "$DIR" rev-parse -q --verify HEAD 2>/dev/null || true)" != "$SHA" ]; then
  git -C "$DIR" fetch -q --depth 1 origin "$SHA"
  git -C "$DIR" checkout -q --detach FETCH_HEAD
fi

(cd "$DIR" && swift build -c release --product dialkit-macos)
BIN="$(cd "$DIR" && swift build -c release --product dialkit-macos --show-bin-path)/dialkit-macos"
echo "DialKit inspector: $BIN"

if [ "${1:-}" = "--build-only" ]; then
  exit 0
fi
echo "Launch Ghostties Dev after this starts so its agent connects."
exec "$BIN"

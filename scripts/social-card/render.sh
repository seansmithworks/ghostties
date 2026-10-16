#!/usr/bin/env bash
# Render scripts/social-card/card.html to web/assets/social-card.png (2560x1280).
#
# Usage: bash scripts/social-card/render.sh [output.png]
#
# Needs Google Chrome (headless) and python3; nothing to install. Override the
# browser with CHROME=/path/to/chrome. Serves the repo root on a free local port
# so the card can load web/assets/ghost-field.js and the self-hosted DM Mono.
# The page sets <html data-ready="ok"> once all 8 ghosts are in the row; the
# script checks that first and exits non-zero, leaving the output untouched,
# if it is anything else.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$ROOT/web/assets/social-card.png}"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

[ -x "$CHROME" ] || { echo "Chrome not found at: $CHROME (set CHROME=...)" >&2; exit 1; }

PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$ROOT" >/dev/null 2>&1 &
SERVER=$!
PROFILE="$(mktemp -d)"
BROWSER=
trap 'kill $BROWSER $SERVER 2>/dev/null; wait 2>/dev/null; rm -rf "$PROFILE"' EXIT

for _ in $(seq 1 50); do
  curl -sf "http://127.0.0.1:$PORT/scripts/social-card/card.html" >/dev/null && break
  sleep 0.1
done

URL="http://127.0.0.1:$PORT/scripts/social-card/card.html"
# Headless Chrome on macOS finishes its output but often never exits, so each
# run goes to the background; wait for its output file, then stop it.
# --force-prefers-reduced-motion is what puts ghost-field.js on its static path.
chrome() { # <output-file> <chrome flags...>
  local file="$1"; shift
  "$CHROME" --headless --disable-gpu --hide-scrollbars \
    --user-data-dir="$PROFILE/chrome" --no-first-run --no-default-browser-check \
    --force-prefers-reduced-motion --force-device-scale-factor=1 \
    --window-size=2560,1280 --virtual-time-budget=5000 "$@" "$URL" 2>/dev/null &
  BROWSER=$!
  for _ in $(seq 1 600); do
    if [ -s "$file" ]; then sleep 1; break; fi  # let Chrome finish writing
    sleep 0.1
  done
  kill $BROWSER 2>/dev/null || true; wait $BROWSER 2>/dev/null || true
  [ -s "$file" ] || { echo "Chrome produced no output" >&2; exit 1; }
}

# 1. The page must report every ghost rendered before anything is written.
DOM="$PROFILE/card.dom"
chrome "$DOM" --dump-dom >"$DOM"
READY="$(grep -o '<html[^>]*data-ready="[a-z]*"' "$DOM" | sed 's/.*data-ready="//; s/"$//' || true)"
[ "$READY" = ok ] || { echo "card not ready (data-ready=\"${READY:-unset}\"); $OUT left unchanged" >&2; exit 1; }

# 2. Screenshot, check size, and only then replace the output.
SHOT="$PROFILE/card.png"
chrome "$SHOT" --screenshot="$SHOT"
W="$(sips -g pixelWidth "$SHOT" | awk '/pixelWidth/{print $2}')"
H="$(sips -g pixelHeight "$SHOT" | awk '/pixelHeight/{print $2}')"
[ "$W" = 2560 ] && [ "$H" = 1280 ] || { echo "wrong size: ${W}x${H}; $OUT left unchanged" >&2; exit 1; }
mv "$SHOT" "$OUT"
echo "$OUT (${W}x${H})"

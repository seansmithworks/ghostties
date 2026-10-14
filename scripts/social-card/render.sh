#!/usr/bin/env bash
# Render scripts/social-card/card.html to web/assets/social-card.png (2560x1280).
#
# Usage: bash scripts/social-card/render.sh [output.png]
#
# Needs Google Chrome (headless) and python3 — nothing to install. Override the
# browser with CHROME=/path/to/chrome. Serves the repo root on a free local port
# so the card can load web/assets/ghost-field.js and the self-hosted DM Mono.
# --force-prefers-reduced-motion is load-bearing: it puts ghost-field.js on its
# static path, which is where the card takes its ghost SVGs from.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$ROOT/web/assets/social-card.png}"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

[ -x "$CHROME" ] || { echo "Chrome not found at: $CHROME (set CHROME=...)" >&2; exit 1; }

PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$ROOT" >/dev/null 2>&1 &
SERVER=$!
PROFILE="$(mktemp -d)"
trap 'kill $SERVER 2>/dev/null; wait 2>/dev/null; rm -rf "$PROFILE"' EXIT

for _ in $(seq 1 50); do
  curl -sf "http://127.0.0.1:$PORT/scripts/social-card/card.html" >/dev/null && break
  sleep 0.1
done

# Headless Chrome on macOS writes the screenshot but often never exits, so
# run it in the background, wait for a finished PNG, then stop it.
SHOT="$PROFILE/card.png"
"$CHROME" --headless --disable-gpu --hide-scrollbars \
  --user-data-dir="$PROFILE" --no-first-run --no-default-browser-check \
  --force-prefers-reduced-motion --force-device-scale-factor=1 \
  --window-size=2560,1280 --virtual-time-budget=5000 \
  --screenshot="$SHOT" "http://127.0.0.1:$PORT/scripts/social-card/card.html" >/dev/null 2>&1 &
BROWSER=$!
trap 'kill $BROWSER $SERVER 2>/dev/null; wait 2>/dev/null; rm -rf "$PROFILE"' EXIT
for _ in $(seq 1 600); do
  if [ -s "$SHOT" ]; then sleep 1; break; fi  # let Chrome finish writing
  sleep 0.1
done
[ -s "$SHOT" ] || { echo "Chrome produced no screenshot" >&2; exit 1; }
mv "$SHOT" "$OUT"

W="$(sips -g pixelWidth "$OUT" | awk '/pixelWidth/{print $2}')"
H="$(sips -g pixelHeight "$OUT" | awk '/pixelHeight/{print $2}')"
[ "$W" = 2560 ] && [ "$H" = 1280 ] || { echo "wrong size: ${W}x${H}" >&2; exit 1; }
echo "$OUT (${W}x${H})"

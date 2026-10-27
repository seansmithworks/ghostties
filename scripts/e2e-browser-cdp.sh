#!/bin/bash
# e2e-browser-cdp.sh — end-to-end check of `gt browser open` and the CDP
# gateway against a real capture build of the app (real CEF, real Chromium).
#
# What it proves (see scripts/e2e/browser-cdp.mjs for the assertions):
#   1. `gt browser open <url>` returns {endpoint,targetId,wsUrl}
#   2. Playwright connectOverCDP attaches and screenshots the page (width > 0)
#   3. Browser.close is refused, the app stays alive, no alert window appears
#   4. Target.createTarget is refused
#   5. Target.closeTarget removes the target and its browser session, app alive
#   6. Playwright browser.close() disconnects without quitting the app
#
# It launches the .capture build (its own bundle id and state, never Sean's
# Dev) in fixture mode with a throwaway state directory, and drives it only
# through the gateway: no keystrokes, no accessibility. The window is visible
# for the length of the run (about a minute); the app is stopped with SIGTERM
# when the run ends.
#
# Usage:
#   scripts/build-capture.sh && (cd cli && swift build --product gt)
#   scripts/e2e-browser-cdp.sh
# Output (screenshots, log) goes to $E2E_OUT, default a fresh temp directory.
# Never committed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${E2E_APP:-$REPO_ROOT/.build-capture/Build/Products/Debug/Ghostties Dev.app}"
GT="${E2E_GT:-$REPO_ROOT/cli/.build/debug/gt}"
OUT="${E2E_OUT:-$(mktemp -d "${TMPDIR:-/tmp}/ghostties-e2e-browser-cdp.XXXXXX")}"
NODE_DIR="${E2E_NODE_DIR:-${TMPDIR:-/tmp}/ghostties-e2e-node}"
PLAYWRIGHT_CORE_VERSION="1.64.1"
# The fixture's first terminal ("reconnect race"), a live session at launch.
FIXTURE_TERMINAL="CAFEFEED-0000-4000-8000-000000000100"

fail() { echo "E2E FAIL: $1" >&2; exit 1; }

[[ -d "$APP" ]] || fail "capture app not built: $APP (run scripts/build-capture.sh)"
[[ -x "$GT" ]] || fail "gt not built: $GT (run: cd cli && swift build --product gt)"
command -v node >/dev/null || fail "node not found"

# The bundle id must be the capture one: this script must never touch Sean's Dev.
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
[[ "$BUNDLE_ID" == *.capture ]] || fail "refusing to launch $BUNDLE_ID (expected a *.capture bundle)"

mkdir -p "$OUT" "$NODE_DIR"
if [[ ! -d "$NODE_DIR/node_modules/playwright-core" ]]; then
  echo "==> installing playwright-core@$PLAYWRIGHT_CORE_VERSION into $NODE_DIR (no browsers)"
  (cd "$NODE_DIR" && npm init -y >/dev/null && npm install --no-audit --no-fund "playwright-core@$PLAYWRIGHT_CORE_VERSION" >/dev/null)
fi

STATE="$(mktemp -d "${TMPDIR:-/tmp}/ghostties-e2e-state.XXXXXX")"
APP_PID=""
cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill -TERM "$APP_PID" 2>/dev/null || true
    for _ in $(seq 1 50); do kill -0 "$APP_PID" 2>/dev/null || break; sleep 0.2; done
    if kill -0 "$APP_PID" 2>/dev/null; then
      echo "E2E NOTE: pid $APP_PID ignored SIGTERM (a modal is blocking quit); sending SIGKILL to that pid only" >&2
      kill -KILL "$APP_PID" 2>/dev/null || true
    fi
  fi
  rm -rf "$STATE"
}
trap cleanup EXIT

echo "==> launching $BUNDLE_ID (fixture mode, state $STATE)"
GHOSTTIES_CAPTURE_FIXTURE=1 \
GHOSTTIES_STATE_DIR="$STATE" \
GHOSTTIES_CAPTURE_BACKGROUND=1 \
  "$APP/Contents/MacOS/ghostty" >"$OUT/app.log" 2>&1 &
APP_PID=$!

echo "==> waiting for the gateway (cdp.json)"
for _ in $(seq 1 150); do
  [[ -s "$STATE/cdp.json" ]] && break
  kill -0 "$APP_PID" 2>/dev/null || { tail -20 "$OUT/app.log" >&2; fail "the app exited before publishing cdp.json"; }
  sleep 0.2
done
[[ -s "$STATE/cdp.json" ]] || fail "cdp.json never appeared in $STATE"

E2E_APP_PID="$APP_PID" \
E2E_STATE_DIR="$STATE" \
E2E_OUT="$OUT" \
E2E_GT="$GT" \
E2E_TERMINAL="$FIXTURE_TERMINAL" \
E2E_NODE_DIR="$NODE_DIR" \
  node "$REPO_ROOT/scripts/e2e/browser-cdp.mjs"

echo "E2E OK (output in $OUT)"

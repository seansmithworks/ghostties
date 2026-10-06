#!/bin/bash
# Ghostties verify rig. Subcommands: up | doctor | shot <name> | video <name> <seconds> | down
# Launches the Debug "Ghostties Dev" app in fixture mode and captures its window.
# Never sends keystrokes/clicks. Never touches /Applications/Ghostties.app, the
# com.seansmithdesign.ghostties (Release) domain, or com.mitchellh.ghostty.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TREE="$(cd "$HERE/../../.." && pwd)"
HASH="$(printf %s "$TREE" | shasum | cut -c1-8)"
EV="/tmp/verify-ghostties-$HASH"
DEV_DOMAIN="com.seansmithdesign.ghostties.dev"
APP="$TREE/macos/build/Build/Products/Debug/Ghostties Dev.app"
BIN="$APP/Contents/MacOS/ghostty"
ENGINE="$TREE/macos/GhosttyKit.xcframework/macos-arm64/libghostty-internal.a"

die() { echo "FAIL: $*" >&2; exit 1; }
pid() { cat "$EV/pid" 2>/dev/null || true; }
alive() { local p; p="$(pid)"; [ -n "$p" ] && kill -0 "$p" 2>/dev/null && [[ "$(ps -p "$p" -o command=)" == *"$APP/Contents/MacOS"* ]]; }
awake() { swift "$HERE/windows.swift" asleep >/dev/null || die "display is asleep; captures would be black"; }
status() { git -C "$TREE" status --porcelain; }

check_inputs() {
  [ -f "$ENGINE" ] || die "engine missing. Copy macos/GhosttyKit.xcframework and zig-out from a fresh tree (see SKILL.md Build), or: PATH=/opt/homebrew/opt/zig@0.16/bin:\$PATH zig build -Doptimize=Debug -Demit-macos-app=false -Demit-xcframework=true (~2 min on 0.16)"
  local src_ct a_mt
  src_ct="$(git -C "$TREE" log -1 --format=%ct -- src include build.zig build.zig.zon pkg)"
  a_mt="$(stat -f %m "$ENGINE")"
  [ "$a_mt" -ge "$src_ct" ] || die "engine stale (older than last src/ commit). Rebuild with zig 0.16 or copy a fresh one (see SKILL.md Build)"
  [ -d "$TREE/zig-out/share" ] || die "zig-out/share missing. Copy zig-out from a fresh tree (see SKILL.md Build)"
  [ -e "$TREE/vendor/cef" ] && [ -e "$TREE/vendor/cef-build" ] || die "vendor/cef or vendor/cef-build missing. Symlink them from the main checkout (see SKILL.md Build)"
}

cmd_up() {
  mkdir -p "$EV/shots" "$EV/state"
  case "${VERIFY_SIDEBAR_TAB:-sessions}" in sessions|projects) ;; *) die "VERIFY_SIDEBAR_TAB must be sessions|projects" ;; esac
  # Launch-state hooks (CaptureFixture.swift, DEBUG only). Project names are fixture names.
  local name='[A-Za-z0-9._-]+' delay='(:delay=[0-9]+(\.[0-9]+)?)?'
  if [ -n "${VERIFY_EXPAND_PROJECT:-}" ]; then
    [[ "$VERIFY_EXPAND_PROJECT" =~ ^$name$ ]] || die "VERIFY_EXPAND_PROJECT must be a fixture project name"
  fi
  if [ -n "${VERIFY_COMPOSER:-}" ]; then
    [[ "$VERIFY_COMPOSER" =~ ^(open|prefilled:$name)$delay$ ]] || die "VERIFY_COMPOSER must be open|prefilled:<project>, optionally :delay=<seconds>"
  fi
  if [ -n "${VERIFY_PROJECT_SETTINGS:-}" ]; then
    [[ "$VERIFY_PROJECT_SETTINGS" =~ ^$name(:templates-edit|:templates-delete)?$ ]] || die "VERIFY_PROJECT_SETTINGS must be <project>[:templates-edit|:templates-delete]"
  fi
  if [ -n "${VERIFY_SIDEBAR_TOGGLE_AFTER:-}" ]; then
    [[ "$VERIFY_SIDEBAR_TOGGLE_AFTER" =~ ^[0-9]+(\.[0-9]+)?$ ]] && [ "$VERIFY_SIDEBAR_TOGGLE_AFTER" != 0 ] || die "VERIFY_SIDEBAR_TOGGLE_AFTER must be seconds > 0"
  fi
  # Expanding a project and its settings popover live on the Projects tab.
  if [ -n "${VERIFY_EXPAND_PROJECT:-}${VERIFY_PROJECT_SETTINGS:-}" ]; then
    [ "${VERIFY_SIDEBAR_TAB:-projects}" = projects ] || die "VERIFY_EXPAND_PROJECT/VERIFY_PROJECT_SETTINGS need VERIFY_SIDEBAR_TAB=projects"
    VERIFY_SIDEBAR_TAB=projects
  fi
  alive && die "already running (pid $(pid)); run down first"
  [ -f "$EV/git-status.before" ] || status > "$EV/git-status.before"
  check_inputs
  # Another Dev window at the default position occludes ours. Never kill it.
  local other
  other="$(ps -axo pid=,command= | grep "Ghostties Dev.app/Contents/MacOS" | grep -v grep | head -1 || true)"
  [ -z "$other" ] || die "another Ghostties Dev is running ($other). Ask Sean to quit it; do not kill it"
  awake
  if [ -n "${VERIFY_BUILD:-1}" ] && [ "${VERIFY_BUILD:-1}" != 0 ]; then
    ( cd "$TREE" && xcodebuild -project macos/Ghostties.xcodeproj -scheme Ghostties -configuration Debug \
        -derivedDataPath macos/build ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build ) > "$EV/build.log" 2>&1 \
      || { tail -20 "$EV/build.log"; die "build failed (full log $EV/build.log)"; }
    grep -q "BUILD SUCCEEDED" "$EV/build.log" || die "no BUILD SUCCEEDED in $EV/build.log"
  fi
  [ -x "$BIN" ] || die "no app at $APP (run without VERIFY_BUILD=0)"
  # Record the Dev-domain sidebar tab so down can restore it.
  if [ -n "${VERIFY_SIDEBAR_TAB:-}" ]; then
    local old
    if [ ! -f "$EV/sidebarTab.old" ]; then
      old="$(defaults read "$DEV_DOMAIN" ghostties.sidebarTab 2>/dev/null || echo __unset__)"
      echo "$old" > "$EV/sidebarTab.old"
    fi
    defaults write "$DEV_DOMAIN" ghostties.sidebarTab "$VERIFY_SIDEBAR_TAB"
  fi
  local extra=()
  if [ -n "${VERIFY_SIDEBAR_MODE:-}" ]; then extra+=("GHOSTTIES_CAPTURE_SIDEBAR_MODE=$VERIFY_SIDEBAR_MODE"); fi
  if [ -n "${VERIFY_POPOVER:-}" ]; then extra+=("GHOSTTIES_CAPTURE_POPOVER=$VERIFY_POPOVER"); fi
  if [ -n "${VERIFY_EXPAND_PROJECT:-}" ]; then extra+=("GHOSTTIES_CAPTURE_EXPAND_PROJECT=$VERIFY_EXPAND_PROJECT"); fi
  if [ -n "${VERIFY_COMPOSER:-}" ]; then extra+=("GHOSTTIES_CAPTURE_COMPOSER=$VERIFY_COMPOSER"); fi
  if [ -n "${VERIFY_PROJECT_SETTINGS:-}" ]; then extra+=("GHOSTTIES_CAPTURE_PROJECT_SETTINGS=$VERIFY_PROJECT_SETTINGS"); fi
  if [ -n "${VERIFY_SIDEBAR_TOGGLE_AFTER:-}" ]; then extra+=("GHOSTTIES_CAPTURE_SIDEBAR_TOGGLE_AFTER=$VERIFY_SIDEBAR_TOGGLE_AFTER"); fi
  env -u GHOSTTIES_SESSION_ID -u GHOSTTIES_LAUNCHER \
    GHOSTTIES_CAPTURE_FIXTURE=1 GHOSTTIES_STATE_DIR="$EV/state" ${extra[@]+"${extra[@]}"} \
    "$BIN" > "$EV/app.log" 2>&1 &
  echo $! > "$EV/pid"
  # Wait for a real window (largest on-screen window > 400x300).
  local i w
  for i in $(seq 1 30); do
    sleep 1
    w="$(swift "$HERE/windows.swift" "$(pid)" | head -1)"
    set -- $w
    [ -n "${2:-}" ] && [ "${2:-0}" -gt 400 ] && [ "${3:-0}" -gt 300 ] && { echo "up: pid $(pid) window $1 (${2}x${3}) evidence $EV"; return 0; }
  done
  die "no window within 30s (see $EV/app.log)"
}

cmd_doctor() {
  [ -d "$EV" ] || die "no evidence dir; run up"
  alive || die "recorded pid $(pid) not alive or not our Dev binary"
  local w; w="$(swift "$HERE/windows.swift" "$(pid)" | head -1)"; set -- $w
  [ -n "${2:-}" ] && [ "${2:-0}" -gt 400 ] || die "no usable window for pid $(pid)"
  [ "$(ps -p "$(pid)" -o command=)" = "$BIN" ] || die "pid runs a different binary"
  echo "ok: pid $(pid) runs $BIN, window $1 ${2}x${3}"
}

cmd_shot() {
  local name="${1:-}"; [ -n "$name" ] || die "usage: shot <name>"
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "shot name must match [A-Za-z0-9._-]+"
  alive || die "not running; run up"
  awake
  local w; w="$(swift "$HERE/windows.swift" "$(pid)" | head -1)"; set -- $w
  [ -n "${1:-}" ] || die "no window for pid $(pid)"
  screencapture -x -o -l "$1" "$EV/shots/$name.png" || die "screencapture failed"
  echo "shot: $EV/shots/$name.png (window $1, ${2}x${3})"
}

# Records only the recorded pid's largest window, then converts to an
# H.264 mp4 (~1400px wide) next to the shots. The .mov is kept as evidence.
cmd_video() {
  local name="${1:-}" secs="${2:-}"
  [ -n "$name" ] && [ -n "$secs" ] || die "usage: video <name> <seconds>"
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "video name must match [A-Za-z0-9._-]+"
  [[ "$secs" =~ ^[0-9]+$ ]] && [ "$secs" -gt 0 ] && [ "$secs" -le 60 ] || die "video seconds must be an integer 1-60"
  command -v ffmpeg >/dev/null || die "ffmpeg not found"
  alive || die "not running; run up"
  awake
  local w; w="$(swift "$HERE/windows.swift" "$(pid)" | head -1)"; set -- $w
  [ -n "${1:-}" ] || die "no window for pid $(pid)"
  local mov="$EV/shots/$name.mov" mp4="$EV/shots/$name.mp4"
  rm -f "$mov" "$mp4"
  screencapture -x -v -V "$secs" -l "$1" "$mov" || die "screencapture -v failed"
  [ -s "$mov" ] || die "no video written to $mov"
  ffmpeg -loglevel error -y -i "$mov" -vf "scale=1400:-2" -c:v libx264 -pix_fmt yuv420p -an -movflags +faststart "$mp4" \
    || die "ffmpeg conversion failed"
  echo "video: $mp4 (window $1, ${2}x${3}, ${secs}s)"
}

cmd_down() {
  local p; p="$(pid)"
  if alive; then
    kill -TERM "$p"
    for _ in $(seq 1 10); do kill -0 "$p" 2>/dev/null || break; sleep 1; done
    if kill -0 "$p" 2>/dev/null; then
      echo "FAIL: pid $p still alive after 10s; pid file and defaults left as-is (not force-killing)"
      return 1
    fi
  else
    echo "down: pid ${p:-none} already gone"
  fi
  local rc=0
  if [ -f "$EV/sidebarTab.old" ]; then
    local old; old="$(cat "$EV/sidebarTab.old")"
    if [ "$old" = "__unset__" ]; then defaults delete "$DEV_DOMAIN" ghostties.sidebarTab 2>/dev/null || true
    else defaults write "$DEV_DOMAIN" ghostties.sidebarTab "$old"; fi
    rm -f "$EV/sidebarTab.old"
    echo "down: restored $DEV_DOMAIN ghostties.sidebarTab -> $old"
  else
    echo "down: no defaults to restore"
  fi
  rm -f "$EV/pid"
  if [ -f "$EV/git-status.before" ]; then
    local d; d="$(diff "$EV/git-status.before" <(status) || true)"
    if [ -z "$d" ]; then echo "down: no git drift"; else echo "down: GIT DRIFT"; echo "$d"; rc=1; fi
    rm -f "$EV/git-status.before"
  fi
  echo "down: evidence kept at $EV"
  return $rc
}

case "${1:-}" in
  up) cmd_up ;;
  doctor) cmd_doctor ;;
  shot) shift; cmd_shot "$@" ;;
  video) shift; cmd_video "$@" ;;
  down) cmd_down ;;
  *) echo "usage: run.sh up|doctor|shot <name>|video <name> <seconds>|down  (env: VERIFY_SIDEBAR_MODE, VERIFY_POPOVER, VERIFY_SIDEBAR_TAB, VERIFY_EXPAND_PROJECT, VERIFY_COMPOSER, VERIFY_PROJECT_SETTINGS, VERIFY_SIDEBAR_TOGGLE_AFTER, VERIFY_BUILD=0)"; exit 2 ;;
esac

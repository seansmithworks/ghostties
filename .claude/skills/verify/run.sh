#!/bin/bash
# Ghostties verify rig. Subcommands: up | doctor | shot <name> | video <name> <seconds> [--focus x,y,w,h]
#   | script <file.json> | report <contract.md> | down
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
  if [ -n "${VERIFY_SCRIPT:-}" ]; then extra+=("GHOSTTIES_CAPTURE_SCRIPT=$VERIFY_SCRIPT"); fi
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
# With --focus x,y,w,h (window points, origin top-left) it also writes
# <name>.focus.mp4: that rect cropped at the backing scale, upscaled to 1080px wide.
cmd_video() {
  local name="${1:-}" secs="${2:-}" focus=""
  [ -n "$name" ] && [ -n "$secs" ] || die "usage: video <name> <seconds> [--focus x,y,w,h]"
  shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --focus) [ -n "${2:-}" ] || die "--focus needs x,y,w,h"; focus="$2"; shift 2 ;;
      *) die "unknown video argument: $1" ;;
    esac
  done
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "video name must match [A-Za-z0-9._-]+"
  [[ "$secs" =~ ^[0-9]+$ ]] && [ "$secs" -gt 0 ] && [ "$secs" -le 60 ] || die "video seconds must be an integer 1-60"
  local fx fy fw fh
  if [ -n "$focus" ]; then
    [[ "$focus" =~ ^[0-9]+(\.[0-9]+)?(,[0-9]+(\.[0-9]+)?){3}$ ]] || die "--focus must be x,y,w,h in window points"
    IFS=, read -r fx fy fw fh <<< "$focus"
    command -v ffprobe >/dev/null || die "ffprobe not found"
  fi
  command -v ffmpeg >/dev/null || die "ffmpeg not found"
  alive || die "not running; run up"
  awake
  local w; w="$(swift "$HERE/windows.swift" "$(pid)" | head -1)"; set -- $w
  [ -n "${1:-}" ] || die "no window for pid $(pid)"
  local wid="$1" wpt="$2" hpt="$3"
  local mov="$EV/shots/$name.mov" mp4="$EV/shots/$name.mp4"
  rm -f "$mov" "$mp4" "$EV/shots/$name.focus.mp4"
  screencapture -x -v -V "$secs" -l "$wid" "$mov" || die "screencapture -v failed"
  [ -s "$mov" ] || die "no video written to $mov"
  ffmpeg -loglevel error -y -i "$mov" -vf "scale=1400:-2" -c:v libx264 -pix_fmt yuv420p -an -movflags +faststart "$mp4" \
    || die "ffmpeg conversion failed"
  echo "video: $mp4 (window $wid, ${wpt}x${hpt}, ${secs}s)"
  if [ -n "$focus" ]; then
    local pxw crop
    pxw="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$mov")"
    [[ "$pxw" =~ ^[0-9]+$ ]] || die "ffprobe could not read the clip width"
    # scale = pixels per point; even integer crop box (yuv420p needs even sizes).
    crop="$(awk -v pxw="$pxw" -v wpt="$wpt" -v x="$fx" -v y="$fy" -v w="$fw" -v h="$fh" 'BEGIN{
      s=pxw/wpt; cw=int(w*s/2)*2; ch=int(h*s/2)*2; cx=int(x*s/2)*2; cy=int(y*s/2)*2;
      if (cw<2||ch<2) exit 1; printf "crop=%d:%d:%d:%d", cw, ch, cx, cy }')" || die "--focus rect is empty"
    ffmpeg -loglevel error -y -i "$mov" -vf "$crop,scale=1080:-2:flags=lanczos" -c:v libx264 -pix_fmt yuv420p -an -movflags +faststart "$EV/shots/$name.focus.mp4" \
      || die "ffmpeg focus crop failed ($crop; a rect outside the window fails here)"
    echo "video: $EV/shots/$name.focus.mp4 (focus $focus pt, $crop)"
  fi
}

# Runs a capture script (see capture-script-schema.md). Launches like `up` with
# GHOSTTIES_CAPTURE_SCRIPT, shoots each mark the app announces in marks.jsonl, then
# touches marks/<name>.done so the app continues. Exits non-zero on script.error or
# timeout (VERIFY_SCRIPT_TIMEOUT seconds, default 120). The app is left up either way: run down.
cmd_script() {
  local f="${1:-}"; [ -n "$f" ] || die "usage: script <file.json>"
  [ -f "$f" ] || die "no such script file: $f"
  f="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
  python3 -I - "$f" <<'PY' || die "script file is not valid JSON with a non-empty steps array"
import json, sys
d = json.load(open(sys.argv[1]))
assert isinstance(d.get("steps"), list) and d["steps"]
PY
  local sd="$EV/state" timeout="${VERIFY_SCRIPT_TIMEOUT:-120}"
  [[ "$timeout" =~ ^[0-9]+$ ]] && [ "$timeout" -gt 0 ] || die "VERIFY_SCRIPT_TIMEOUT must be a positive integer"
  mkdir -p "$sd"
  rm -rf "$sd/marks" "$sd/marks.jsonl" "$sd/script.done" "$sd/script.error" "$sd/dispatch.jsonl"
  mkdir -p "$sd/marks"
  VERIFY_SCRIPT="$f" cmd_up
  local seen=0 start now n line mark
  start="$(date +%s)"
  while :; do
    if [ -f "$sd/script.error" ]; then
      echo "FAIL: script error: $(head -1 "$sd/script.error")" >&2; return 1
    fi
    if [ -f "$sd/marks.jsonl" ]; then
      n="$(wc -l < "$sd/marks.jsonl" | tr -d ' ')"
      while [ "$seen" -lt "$n" ]; do
        seen=$((seen + 1))
        line="$(sed -n "${seen}p" "$sd/marks.jsonl")"
        mark="$(python3 -I -c 'import json,sys; print(json.loads(sys.argv[1])["name"])' "$line")" \
          || { echo "FAIL: bad marks.jsonl line $seen: $line" >&2; return 1; }
        [[ "$mark" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "FAIL: mark name not shot-safe: $mark" >&2; return 1; }
        cmd_shot "$mark" || return 1
        : > "$sd/marks/$mark.done"
      done
    fi
    if [ -f "$sd/script.done" ]; then
      echo "script: done, $seen mark(s) shot, evidence $EV (dispatch: $sd/dispatch.jsonl)"; return 0
    fi
    alive || { echo "FAIL: app exited before script.done (see $EV/app.log)" >&2; return 1; }
    now="$(date +%s)"
    [ $((now - start)) -lt "$timeout" ] || { echo "FAIL: script timed out after ${timeout}s" >&2; return 1; }
    sleep 0.1
  done
}

cmd_report() {
  local c="${1:-}"; [ -n "$c" ] || die "usage: report <contract.md>  (status.json is read beside it; page goes to \$VERIFY_REPORT_OUT or $EV/report.html)"
  mkdir -p "$EV"
  python3 -I "$HERE/contract-report.py" "$c" "${VERIFY_REPORT_OUT:-$EV/report.html}"
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
  script) shift; cmd_script "$@" ;;
  report) shift; cmd_report "$@" ;;
  down) cmd_down ;;
  *) echo "usage: run.sh up|doctor|shot <name>|video <name> <seconds> [--focus x,y,w,h]|script <file.json>|report <contract.md>|down  (env: VERIFY_SCRIPT_TIMEOUT, VERIFY_SIDEBAR_MODE, VERIFY_POPOVER, VERIFY_SIDEBAR_TAB, VERIFY_EXPAND_PROJECT, VERIFY_COMPOSER, VERIFY_PROJECT_SETTINGS, VERIFY_SIDEBAR_TOGGLE_AFTER, VERIFY_BUILD=0)"; exit 2 ;;
esac

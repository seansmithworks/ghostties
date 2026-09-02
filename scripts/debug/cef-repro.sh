#!/usr/bin/env bash
#
# cef-repro.sh — Unattended reproduction harness for the CEF embedded-browser
# crash (main process dies ~460ms after CefBrowserHost::CreateBrowser).
#
# Drives the SAME code path as a real click on the globe button
# (WorkspaceViewContainer.toggleBrowser()), triggered by an env var that only
# exists in Debug builds — no synthetic keystrokes, no accessibility driving.
#
# Usage:
#   scripts/debug/cef-repro.sh [--runs N] [--timeout SECONDS] [--app PATH]
#
# Exit code: 0 if the LAST run SURVIVED, 1 if it DIED (or on a setup error).
# With --runs > 1, the exit code reflects the last run only; the printed
# tally is the authoritative summary across all runs.
#
# HARD RULE: this script must never `killall ghostty` / `killall ghostties`.
# Cleanup only ever SIGTERMs the exact PID this script itself launched, and
# only after verifying that PID's executable path points at the Dev bundle
# we launched.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

APP_PATH="${GHOSTTIES_DEV_APP:-$REPO_ROOT/macos/build/Build/Products/Debug/Ghostties Dev.app}"
TIMEOUT_SECONDS=30
RUNS=1

usage() {
  cat <<'EOF'
Usage: cef-repro.sh [--runs N] [--timeout SECONDS] [--app PATH]

  --runs N        Repeat the reproduction N times and report a tally (default 1).
  --timeout SEC   Seconds to wait for DIED/SURVIVED per run (default 30).
  --app PATH      Path to "Ghostties Dev.app" (default: macos/build/Build/Products/Debug).

Exit code 0 if the last run SURVIVED, 1 if it DIED, 2 on a setup/preflight error.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs)
      RUNS="$2"; shift 2 ;;
    --timeout)
      TIMEOUT_SECONDS="$2"; shift 2 ;;
    --app)
      APP_PATH="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2 ;;
  esac
done

BUNDLE_EXEC="$APP_PATH/Contents/MacOS/ghostty"
INFO_PLIST="$APP_PATH/Contents/Info.plist"

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: app bundle not found at: $APP_PATH" >&2
  echo "Build it first: xcodebuild -project macos/Ghostties.xcodeproj -scheme Ghostties -configuration Debug -derivedDataPath macos/build ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build" >&2
  exit 2
fi

if [[ ! -x "$BUNDLE_EXEC" ]]; then
  echo "ERROR: no executable at: $BUNDLE_EXEC" >&2
  exit 2
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST" 2>/dev/null || true)"
if [[ -z "$BUNDLE_ID" ]]; then
  echo "ERROR: could not read CFBundleIdentifier from $INFO_PLIST" >&2
  exit 2
fi

# Refuse to run against a non-Debug build. Debug Dev builds carry the
# ".dev" bundle-id suffix (see CEFBridge.mm's cache-dir comment); Release
# does not build the auto-open trigger at all (it's `#if DEBUG`-gated), so
# this bundle-id check is the cheap first gate and the strings(1) check
# below is the real one.
case "$BUNDLE_ID" in
  *.dev) ;;
  *)
    echo "ERROR: refusing to run against a non-Debug build (bundle id: $BUNDLE_ID)." >&2
    echo "This harness only works against a Debug 'Ghostties Dev.app' build." >&2
    exit 2
    ;;
esac

# The trigger's string literal lives in the Swift debug dylib
# (ghostty.debug.dylib), not the thin launcher executable, on a Debug build
# with dynamic linking — so check both. Write to a temp file rather than
# piping straight into `grep -q`: with `set -o pipefail`, grep -q's early
# exit on match sends SIGPIPE back up to `strings` on a 40MB+ dylib, and
# that non-zero signal-exit status propagates through the pipeline.
DEBUG_DYLIB="$APP_PATH/Contents/MacOS/ghostty.debug.dylib"
_strings_tmp="$(mktemp -t cef-repro-strings)"
/usr/bin/strings "$BUNDLE_EXEC" >"$_strings_tmp" 2>/dev/null
[[ -f "$DEBUG_DYLIB" ]] && /usr/bin/strings "$DEBUG_DYLIB" >>"$_strings_tmp" 2>/dev/null
if ! grep -q 'GHOSTTIES_DEBUG_AUTO_OPEN_BROWSER' "$_strings_tmp"; then
  rm -f "$_strings_tmp"
  echo "ERROR: no GHOSTTIES_DEBUG_AUTO_OPEN_BROWSER support found in $BUNDLE_EXEC or $DEBUG_DYLIB." >&2
  echo "Rebuild after WorkspaceViewContainer.swift's debug auto-open trigger lands." >&2
  exit 2
fi
rm -f "$_strings_tmp"

CACHE_DIR="$HOME/Library/Application Support/$BUNDLE_ID/CEF"
CEF_INTERNAL_LOG="$CACHE_DIR/ghostties-cef-internal.log"

echo "== cef-repro.sh =="
echo "App:        $APP_PATH"
echo "Bundle ID:  $BUNDLE_ID"
echo "CEF cache:  $CACHE_DIR"
echo "Runs:       $RUNS"
echo "Timeout:    ${TIMEOUT_SECONDS}s per run"
echo

# ---------------------------------------------------------------------------
# One repro run.
#
# Sets globals: RUN_VERDICT ("SURVIVED" or "DIED"), RUN_DIED_MS (empty if
# SURVIVED), RUN_CEFDIAG_LOG (path to this run's captured [CEFDiag] lines),
# RUN_LAUNCHED_PID.
# ---------------------------------------------------------------------------
run_once() {
  local run_idx="$1"
  echo "--- Run $run_idx/$RUNS ---"

  # Snapshot the CEF internal log's size BEFORE launch, so we can tail only
  # what this run appended.
  local cef_log_before_size=0
  if [[ -f "$CEF_INTERNAL_LOG" ]]; then
    cef_log_before_size=$(stat -f%z "$CEF_INTERNAL_LOG")
  fi

  # Stream [CEFDiag]-tagged unified log lines from this process to a temp
  # file, started BEFORE launch so nothing is missed. `log stream` attaches
  # asynchronously; give it a beat before we launch.
  local diag_log
  diag_log="$(mktemp -t cef-repro-diag)"
  /usr/bin/log stream --style compact \
    --predicate 'eventMessage contains "[CEFDiag]"' \
    >"$diag_log" 2>/dev/null &
  local log_stream_pid=$!
  sleep 0.5

  # Launch directly (bypasses `open`'s async PID-hunting problem — we get
  # the exact PID from $! and know its executable path is $BUNDLE_EXEC
  # because we just exec'd it ourselves).
  GHOSTTIES_DEBUG_AUTO_OPEN_BROWSER=1 "$BUNDLE_EXEC" >/dev/null 2>&1 &
  local pid=$!

  echo "Launched PID $pid ($BUNDLE_EXEC)"

  # Verify the env var actually arrived in the child's environment.
  sleep 0.5
  local env_check
  env_check="$(ps eww -p "$pid" 2>/dev/null | grep -o 'GHOSTTIES_DEBUG_AUTO_OPEN_BROWSER=1' || true)"
  if [[ -z "$env_check" ]]; then
    echo "WARNING: could not confirm GHOSTTIES_DEBUG_AUTO_OPEN_BROWSER=1 in PID $pid's environment via ps eww (process may have already died, or ps may not expose environ for this process)."
  else
    echo "Confirmed: $env_check present in PID $pid's environment."
  fi

  # Poll for up to TIMEOUT_SECONDS for either the process dying or
  # OnAfterCreated appearing in the streamed diagnostics. Wall-clock
  # timestamps come from python3 (millisecond precision) rather than the
  # unified log's own timestamps — `date`(1) on macOS has no sub-second
  # format specifier, and the CreateBrowser-to-death window is sub-second.
  local now_ms
  now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }

  local deadline_epoch_s=$(( $(date +%s) + TIMEOUT_SECONDS ))
  local verdict="SURVIVED"
  local create_seen=0
  local create_ms=""
  while [[ $(date +%s) -lt $deadline_epoch_s ]]; do
    if [[ "$create_seen" -eq 0 ]] && grep -q 'Calling CefBrowserHost::CreateBrowser' "$diag_log" 2>/dev/null; then
      create_seen=1
      create_ms="$(now_ms)"
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      verdict="DIED"
      break
    fi
    if grep -q 'OnAfterCreated fired' "$diag_log" 2>/dev/null; then
      verdict="SURVIVED"
      break
    fi
    sleep 0.1
  done
  local end_ms
  end_ms="$(now_ms)"

  local died_ms=""
  if [[ "$verdict" == "DIED" && -n "$create_ms" ]]; then
    died_ms=$(( end_ms - create_ms ))
  fi

  # Give the log stream a moment to flush the last lines (e.g. the six
  # helper "Mach rendezvous failed" lines land shortly after main-process
  # death), then stop it.
  sleep 1
  kill "$log_stream_pid" 2>/dev/null
  wait "$log_stream_pid" 2>/dev/null

  # ---- Cleanup: SIGTERM only OUR launched PID, only after verifying its
  # executable path matches the bundle we launched. Never killall. ----
  if kill -0 "$pid" 2>/dev/null; then
    local exec_path
    exec_path="$(ps -o comm= -p "$pid" 2>/dev/null || true)"
    if [[ "$exec_path" == "$BUNDLE_EXEC" ]]; then
      kill "$pid" 2>/dev/null
      sleep 0.3
      kill -9 "$pid" 2>/dev/null
    else
      echo "WARNING: PID $pid's executable path ($exec_path) no longer matches $BUNDLE_EXEC — skipping cleanup kill to avoid targeting the wrong process." >&2
    fi
  fi

  echo
  if [[ "$verdict" == "DIED" ]]; then
    if [[ -n "$died_ms" ]]; then
      echo "VERDICT: DIED after ${died_ms}ms from CreateBrowser"
    else
      echo "VERDICT: DIED (could not compute ms-from-CreateBrowser — see raw log below)"
    fi
  else
    echo "VERDICT: SURVIVED"
  fi

  echo
  echo "[CEFDiag] lines (run $run_idx):"
  if [[ -s "$diag_log" ]]; then
    cat "$diag_log"
  else
    echo "(none captured)"
  fi

  echo
  echo "CEF internal log tail (new bytes this run):"
  if [[ -f "$CEF_INTERNAL_LOG" ]]; then
    local cef_log_after_size
    cef_log_after_size=$(stat -f%z "$CEF_INTERNAL_LOG")
    if [[ "$cef_log_after_size" -gt "$cef_log_before_size" ]]; then
      tail -c $(( cef_log_after_size - cef_log_before_size )) "$CEF_INTERNAL_LOG"
    else
      echo "(no new bytes appended to $CEF_INTERNAL_LOG)"
    fi
  else
    echo "(no CEF internal log at $CEF_INTERNAL_LOG)"
  fi
  echo

  RUN_VERDICT="$verdict"
  RUN_DIED_MS="$died_ms"
  rm -f "$diag_log"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

SURVIVED_COUNT=0
DIED_COUNT=0

for ((i = 1; i <= RUNS; i++)); do
  run_once "$i"
  if [[ "$RUN_VERDICT" == "SURVIVED" ]]; then
    SURVIVED_COUNT=$((SURVIVED_COUNT + 1))
  else
    DIED_COUNT=$((DIED_COUNT + 1))
  fi
  echo "=================================================="
  echo
done

if [[ "$RUNS" -gt 1 ]]; then
  echo "== Tally =="
  echo "SURVIVED: $SURVIVED_COUNT/$RUNS"
  echo "DIED:     $DIED_COUNT/$RUNS"
  echo
fi

if [[ "$RUN_VERDICT" == "SURVIVED" ]]; then
  exit 0
else
  exit 1
fi

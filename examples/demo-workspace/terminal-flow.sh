#!/usr/bin/env bash
# =============================================================================
# terminal-flow.sh — Ghostties Demo Terminal Flow Choreography
# =============================================================================
#
# Drives demo task fixtures through a lifecycle sequence so the terminal
# renders `gt list` lane re-renders as a task moves through status lanes.
# Designed for screen recording via an EXTERNAL recorder (ffmpeg / Cmd-Shift-5).
#
# HARD RULE: This script NEVER captures the screen. Recording is external —
# use Cmd-Shift-5 in macOS (or ffmpeg) to record before running this script.
# This script only mutates fixture Markdown files and drives `gt list` output.
#
# USAGE:
#   ./terminal-flow.sh              — Live mode. Real hold times. Runs to
#                                     completion automatically; EXIT trap
#                                     restores the fixture. Stop your recorder
#                                     after the final `gt list` clears.
#   ./terminal-flow.sh --dry-run    — Verification mode. Short holds (0.3s).
#                                     Prints a labeled lane snapshot after each
#                                     beat. Fixture is restored at exit.
#
# RUN FROM: anywhere — paths are hardcoded.
#
# =============================================================================

set -euo pipefail

# =============================================================================
# PATHS
# =============================================================================

REPO_ROOT="/Users/seansmith/Code/ghostties"
TASKS_DIR="${REPO_ROOT}/examples/demo-workspace/switchboard/.ghostties/tasks"
GT_BIN="${REPO_ROOT}/cli/.build/release/gt"
SWITCHBOARD_DIR="${REPO_ROOT}/examples/demo-workspace/switchboard"

# =============================================================================
# DRY-RUN HOLD OVERRIDE (seconds)
# =============================================================================

DRY_RUN_HOLD="0.3"

# =============================================================================
# SNAPSHOT / RESTORE HELPERS
# =============================================================================

SNAPSHOT_DIR=""

snapshot_tasks() {
  SNAPSHOT_DIR="$(mktemp -d)"
  cp -R "${TASKS_DIR}/." "${SNAPSHOT_DIR}/"
  echo "[terminal-flow] Snapshot saved to ${SNAPSHOT_DIR}"
}

restore_from_snapshot() {
  if [[ -z "${SNAPSHOT_DIR}" || ! -d "${SNAPSHOT_DIR}" ]]; then
    return
  fi
  echo ""
  echo "[terminal-flow] Restoring fixture from snapshot…"
  # Remove all current files in the tasks dir and copy the snapshot back
  find "${TASKS_DIR}" -mindepth 1 -maxdepth 1 -delete
  cp -R "${SNAPSHOT_DIR}/." "${TASKS_DIR}/"
  echo "[terminal-flow] Fixture restored."
}

# =============================================================================
# FILE MUTATION HELPERS
# =============================================================================

set_status() {
  local filename="$1"   # without .md
  local new_status="$2"
  local filepath="${TASKS_DIR}/${filename}.md"

  if [[ ! -f "${filepath}" ]]; then
    echo "[terminal-flow] ERROR: File not found: ${filepath}" >&2
    return 1
  fi

  # BSD sed (macOS): in-place replacement, no backup
  sed -i '' -E "s/^status:.*/status: ${new_status}/" "${filepath}"
}

create_oauth_scope_validation() {
  local filepath="${TASKS_DIR}/oauth-scope-validation.md"
  cat > "${filepath}" <<'TASKEOF'
---
title: "Add OAuth scope validation to webhook registration API"
status: inbox
created: 2026-06-12T09:00:00Z
project: switchboard
source: github
source-id: GH-79
priority: medium
branch: feat/oauth-scope-validation
worktree: ~/Code/switchboard
---

## Goal
Validate that the OAuth token used when registering a new webhook endpoint carries the required `webhooks:write` scope. Reject registrations with insufficient permissions before the endpoint is persisted, returning a 403 with a descriptive error body.

## Notes
Current registration handler checks token validity (expiry, signature) but skips scope inspection entirely. The scope claim lives in the JWT payload as `scope` (space-delimited string). Need a scope-parser utility and a middleware layer so the check is reusable by future permission-gated routes. Token refresh flow is out of scope — callers with expired tokens get a 401 via the existing auth middleware.

## Activity
- 2026-06-12T09:00:00Z — Discovered gap during security review of webhook registration endpoint
TASKEOF
}

# =============================================================================
# GT LANE SNAPSHOT (dry-run only)
# =============================================================================

print_lane_snapshot() {
  local label="$1"

  local gt_output
  gt_output="$(cd "${SWITCHBOARD_DIR}" && "${GT_BIN}" list 2>/dev/null)" || true

  echo ""
  echo "  ┌─────────────────────────────────────────────────────────────────────┐"
  printf  "  │ %-69s │\n" "${label}"
  echo "  ├──────────────┬──────────────────────────────────────────────────────┤"

  local lane_inbox lane_backlog lane_running lane_needs_you lane_review lane_graveyard
  lane_inbox=""
  lane_backlog=""
  lane_running=""
  lane_needs_you=""
  lane_review=""
  lane_graveyard=""

  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    local id task_status
    id="$(echo "${line}" | awk '{print $1}')"
    task_status="$(echo "${line}" | awk '{print $2}')"

    case "${task_status}" in
      inbox)
        lane_inbox="${lane_inbox:+${lane_inbox}, }${id}" ;;
      backlog)
        lane_backlog="${lane_backlog:+${lane_backlog}, }${id}" ;;
      running)
        lane_running="${lane_running:+${lane_running}, }${id}" ;;
      needs-you)
        lane_needs_you="${lane_needs_you:+${lane_needs_you}, }${id}" ;;
      review)
        lane_review="${lane_review:+${lane_review}, }${id}" ;;
      graveyard)
        lane_graveyard="${lane_graveyard:+${lane_graveyard}, }${id}" ;;
    esac
  done <<< "${gt_output}"

  printf "  │ %-12s │ %-54s │\n" "inbox"     "${lane_inbox}"
  printf "  │ %-12s │ %-54s │\n" "backlog"   "${lane_backlog}"
  printf "  │ %-12s │ %-54s │\n" "running"   "${lane_running}"
  printf "  │ %-12s │ %-54s │\n" "needs-you" "${lane_needs_you}"
  printf "  │ %-12s │ %-54s │\n" "review"    "${lane_review}"
  printf "  │ %-12s │ %-54s │\n" "graveyard" "${lane_graveyard}"

  echo "  └──────────────┴──────────────────────────────────────────────────────┘"
  echo ""
}

# =============================================================================
# BEAT RUNNER
# =============================================================================

run_flow() {
  local is_dry_run="$1"  # "true" or "false"

  # ── Beat 1: Initial state — all six lanes ─────────────────────────────────
  clear
  cd "${SWITCHBOARD_DIR}" && "${GT_BIN}" list

  if [[ "${is_dry_run}" == "true" ]]; then
    print_lane_snapshot "Beat 1 — Initial state (six lanes)"
    sleep "${DRY_RUN_HOLD}"
  else
    sleep 3
  fi

  # ── Beat 2: New task lands in Inbox ───────────────────────────────────────
  create_oauth_scope_validation
  clear
  cd "${SWITCHBOARD_DIR}" && "${GT_BIN}" list

  if [[ "${is_dry_run}" == "true" ]]; then
    print_lane_snapshot "Beat 2 — oauth-scope-validation created (inbox)"
    sleep "${DRY_RUN_HOLD}"
  else
    sleep 3
  fi

  # ── Beat 3: Agent starts work (Inbox → Running) ───────────────────────────
  set_status "oauth-scope-validation" "running"
  clear
  cd "${SWITCHBOARD_DIR}" && "${GT_BIN}" list

  if [[ "${is_dry_run}" == "true" ]]; then
    print_lane_snapshot "Beat 3 — oauth-scope-validation running"
    sleep "${DRY_RUN_HOLD}"
  else
    sleep 3
  fi

  # ── Beat 4: Agent is blocked — needs you (terracotta) ─────────────────────
  set_status "oauth-scope-validation" "needs-you"
  clear
  cd "${SWITCHBOARD_DIR}" && "${GT_BIN}" list

  if [[ "${is_dry_run}" == "true" ]]; then
    print_lane_snapshot "Beat 4 — oauth-scope-validation needs-you (terracotta)"
    sleep "${DRY_RUN_HOLD}"
  else
    sleep 3.5
  fi

  # ── Final: Settle on needs-you lane ───────────────────────────────────────
  clear
  cd "${SWITCHBOARD_DIR}" && "${GT_BIN}" list

  if [[ "${is_dry_run}" == "true" ]]; then
    print_lane_snapshot "Final — settle on needs-you"
    sleep "${DRY_RUN_HOLD}"
  else
    sleep 2
  fi
}

# =============================================================================
# MODES
# =============================================================================

mode_dry_run() {
  if [[ ! -d "${TASKS_DIR}" ]]; then
    echo "[terminal-flow] ERROR: Tasks dir not found: ${TASKS_DIR}" >&2
    exit 1
  fi
  if [[ ! -x "${GT_BIN}" ]]; then
    echo "[terminal-flow] ERROR: gt binary not found or not executable: ${GT_BIN}" >&2
    exit 1
  fi

  echo "[terminal-flow] DRY-RUN mode — holds are ${DRY_RUN_HOLD}s, fixture will be restored at exit."
  snapshot_tasks

  trap restore_from_snapshot EXIT

  run_flow "true"

  echo ""
  echo "========================================================================="
  echo "  PASS — All beats completed. Fixture will be restored on exit."
  echo "========================================================================="
}

mode_live() {
  if [[ ! -d "${TASKS_DIR}" ]]; then
    echo "[terminal-flow] ERROR: Tasks dir not found: ${TASKS_DIR}" >&2
    exit 1
  fi
  if [[ ! -x "${GT_BIN}" ]]; then
    echo "[terminal-flow] ERROR: gt binary not found or not executable: ${GT_BIN}" >&2
    exit 1
  fi

  echo "[terminal-flow] LIVE mode — real hold times, recording-ready."
  echo ""
  echo "         REMEMBER: This script does not capture the screen."
  echo "         Start your recorder (Cmd-Shift-5 or ffmpeg) BEFORE running."
  echo "         The script runs to completion automatically."
  echo ""
  sleep 1

  snapshot_tasks

  trap restore_from_snapshot EXIT

  run_flow "false"

  echo ""
  echo "========================================================================="
  echo "  Flow complete. Stop your screen recording now."
  echo "  Fixture will be restored on exit."
  echo "========================================================================="
}

# =============================================================================
# ENTRY POINT
# =============================================================================

MODE="${1:-}"

case "${MODE}" in
  --dry-run)
    mode_dry_run
    ;;
  "")
    mode_live
    ;;
  *)
    echo "[terminal-flow] Unknown flag: ${MODE}" >&2
    echo "Usage: $0 [--dry-run]" >&2
    exit 1
    ;;
esac

#!/usr/bin/env bash
# =============================================================================
# choreograph.sh — Ghostties Demo Sidebar Choreography
# =============================================================================
#
# Drives the demo task fixtures through a lifecycle sequence so the live
# Ghostties sidebar animates cards between zones. Designed for screen recording.
#
# HARD RULE: This script NEVER captures the screen. Recording is separate —
# use Cmd-Shift-5 in macOS to record, then stop your recording before pressing
# Enter when prompted. This script only mutates fixture Markdown files.
#
# MODES:
#   ./choreograph.sh              — Live mode. Real hold times. Waits for Enter
#                                   before restoring so you can stop recording.
#   ./choreograph.sh --dry-run    — Verification mode. Short holds (0.3s).
#                                   Prints a labeled lane snapshot after each
#                                   beat. Restores fixture at the end.
#   ./choreograph.sh --restore    — Emergency reset. Reverts the switchboard
#                                   tasks dir to its committed git state.
#
# EDITING THE BEAT SEQUENCE:
#   Beats are defined in the BEATS array near the bottom of this file.
#   Each beat is a colon-separated record:
#     BEAT_TYPE:LABEL:HOLD_SECONDS:EXTRA_ARGS
#   Types:
#     hold          — pause only; no file mutations
#     create        — write a new task file (EXTRA_ARGS = filename without .md)
#     set_status    — rewrite status: field  (EXTRA_ARGS = filename:new_status)
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
# BEAT SEQUENCE CONFIGURATION
# =============================================================================
#
# Format per entry:  "TYPE:LABEL:HOLD_SECONDS:EXTRA"
#
#   hold        "hold:Rest label:SECONDS:"
#   create      "create:Label:SECONDS:FILENAME_WITHOUT_EXTENSION"
#   set_status  "set_status:Label:SECONDS:FILENAME_WITHOUT_EXTENSION:NEW_STATUS"
#
# HOLDS: real-time durations used in live mode.
# In --dry-run mode all holds are replaced with 0.3s.
#
# Keep webhook-signature-verify in `running` throughout (never touch it) so
# the Running lane stays populated even while the new task travels through lanes.

BEATS=(
  "hold:Rest — all six lanes populated:2.0:"
  "create:New task lands in Inbox:2.0:oauth-scope-validation"
  "set_status:Agent starts work (Inbox → Running):2.5:oauth-scope-validation:running"
  "set_status:Agent is blocked — needs you (terracotta):3.0:oauth-scope-validation:needs-you"
  "hold:Settle — Needs You lane showing both blocked tasks:2.0:"
)

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
  echo "[choreograph] Snapshot saved to ${SNAPSHOT_DIR}"
}

restore_from_snapshot() {
  if [[ -z "${SNAPSHOT_DIR}" || ! -d "${SNAPSHOT_DIR}" ]]; then
    return
  fi
  echo ""
  echo "[choreograph] Restoring fixture from snapshot…"
  # Remove all current files in the tasks dir and copy the snapshot back
  find "${TASKS_DIR}" -mindepth 1 -maxdepth 1 -delete
  cp -R "${SNAPSHOT_DIR}/." "${TASKS_DIR}/"
  echo "[choreograph] Fixture restored."
}

restore_from_git() {
  echo "[choreograph] Restoring switchboard tasks from git…"
  git -C "${REPO_ROOT}" checkout -- "examples/demo-workspace/switchboard/.ghostties/tasks/"
  git -C "${REPO_ROOT}" clean -fd "examples/demo-workspace/switchboard/.ghostties/tasks/" > /dev/null
  echo "[choreograph] Restore complete."
}

# =============================================================================
# FILE MUTATION HELPERS
# =============================================================================

set_status() {
  local filename="$1"   # without .md
  local new_status="$2"
  local filepath="${TASKS_DIR}/${filename}.md"

  if [[ ! -f "${filepath}" ]]; then
    echo "[choreograph] ERROR: File not found: ${filepath}" >&2
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
# GT SNAPSHOT DISPLAY
# =============================================================================

print_lane_snapshot() {
  local label="$1"

  # Run gt list from the switchboard project dir (it walks up to find .ghostties/tasks/)
  local gt_output
  gt_output="$(cd "${SWITCHBOARD_DIR}" && "${GT_BIN}" list 2>/dev/null)" || true

  echo ""
  echo "  ┌─────────────────────────────────────────────────────────────────────┐"
  printf  "  │ %-69s │\n" "${label}"
  echo "  ├──────────────┬──────────────────────────────────────────────────────┤"

  # Build one variable per lane using awk (bash 3.2-safe, no associative arrays)
  local lane_inbox lane_backlog lane_running lane_needs_you lane_review lane_graveyard
  lane_inbox=""
  lane_backlog=""
  lane_running=""
  lane_needs_you=""
  lane_review=""
  lane_graveyard=""

  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    # gt list columns: SOURCE-ID   STATUS   TITLE   [project: ...]
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
# BEAT EXECUTION
# =============================================================================

run_beats() {
  local is_dry_run="$1"  # "true" or "false"

  for beat in "${BEATS[@]}"; do
    # Parse the colon-delimited beat record
    local beat_type label hold_secs extra
    beat_type="${beat%%:*}"
    local rest="${beat#*:}"
    label="${rest%%:*}"
    rest="${rest#*:}"
    hold_secs="${rest%%:*}"
    extra="${rest#*:}"

    # In dry-run mode, override hold with the short dry-run hold
    local effective_hold="${hold_secs}"
    if [[ "${is_dry_run}" == "true" ]]; then
      effective_hold="${DRY_RUN_HOLD}"
    fi

    # Print the beat label
    echo ""
    echo ">>> BEAT: ${label}"

    # Execute the beat action
    case "${beat_type}" in
      hold)
        # No file mutation — just hold
        ;;

      create)
        local filename="${extra}"
        case "${filename}" in
          oauth-scope-validation)
            create_oauth_scope_validation
            echo "    Created ${filename}.md (status: inbox)"
            ;;
          *)
            echo "[choreograph] ERROR: Unknown create target: ${filename}" >&2
            return 1
            ;;
        esac
        ;;

      set_status)
        # extra format: "FILENAME:NEW_STATUS"
        local fname nstatus
        fname="${extra%%:*}"
        nstatus="${extra#*:}"
        set_status "${fname}" "${nstatus}"
        echo "    Set ${fname}.md → status: ${nstatus}"
        ;;

      *)
        echo "[choreograph] ERROR: Unknown beat type: ${beat_type}" >&2
        return 1
        ;;
    esac

    # In dry-run mode, print the lane snapshot after each beat
    if [[ "${is_dry_run}" == "true" ]]; then
      print_lane_snapshot "${label}"
    fi

    # Hold
    sleep "${effective_hold}"
  done
}

# =============================================================================
# MODES
# =============================================================================

mode_restore() {
  restore_from_git
  echo "[choreograph] Done. Switchboard tasks dir is clean."
}

mode_dry_run() {
  # Guard: make sure required paths exist
  if [[ ! -d "${TASKS_DIR}" ]]; then
    echo "[choreograph] ERROR: Tasks dir not found: ${TASKS_DIR}" >&2
    exit 1
  fi
  if [[ ! -x "${GT_BIN}" ]]; then
    echo "[choreograph] ERROR: gt binary not found or not executable: ${GT_BIN}" >&2
    exit 1
  fi

  echo "[choreograph] DRY-RUN mode — holds are ${DRY_RUN_HOLD}s, fixture will be restored at exit."
  snapshot_tasks

  # Always restore on exit (handles Ctrl-C too)
  trap restore_from_snapshot EXIT

  run_beats "true"

  echo ""
  echo "========================================================================="
  echo "  PASS — All beats completed. Fixture will be restored on exit."
  echo "========================================================================="
}

mode_live() {
  # Guard: make sure required paths exist
  if [[ ! -d "${TASKS_DIR}" ]]; then
    echo "[choreograph] ERROR: Tasks dir not found: ${TASKS_DIR}" >&2
    exit 1
  fi
  if [[ ! -x "${GT_BIN}" ]]; then
    echo "[choreograph] ERROR: gt binary not found or not executable: ${GT_BIN}" >&2
    exit 1
  fi

  echo "[choreograph] LIVE mode — real hold times, recording-ready."
  echo "[choreograph] Start your screen recording NOW (Cmd-Shift-5), then the beats begin."
  echo ""
  echo "         REMEMBER: This script does not capture the screen."
  echo "         Use Cmd-Shift-5 to record. Stop your recording before"
  echo "         pressing Enter at the end of the sequence."
  echo ""
  sleep 1

  snapshot_tasks

  # Always restore on exit (handles Ctrl-C too)
  trap restore_from_snapshot EXIT

  run_beats "false"

  echo ""
  echo "========================================================================="
  echo "  All beats complete. The fixture is LIVE at its final state."
  echo "  Stop your screen recording now (Cmd-Shift-5 > Stop), then press Enter."
  echo "========================================================================="
  read -r -p "  > Press Enter to restore fixture and exit: "
}

# =============================================================================
# ENTRY POINT
# =============================================================================

MODE="${1:-}"

case "${MODE}" in
  --dry-run)
    mode_dry_run
    ;;
  --restore)
    mode_restore
    ;;
  "")
    mode_live
    ;;
  *)
    echo "[choreograph] Unknown flag: ${MODE}" >&2
    echo "Usage: $0 [--dry-run | --restore]" >&2
    exit 1
    ;;
esac

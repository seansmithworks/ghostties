#!/usr/bin/env bash
# =============================================================================
# _demo-paths.sh — Shared path/constant definitions for the Ghostties Demo rig
#
# Sourced (never executed directly) by demo-ready.sh, seed-demo-workspace.sh,
# demo-drive.sh, _stage-demo-sessions.sh, and demo-capture.sh, so these values
# can't drift between scripts. Requires REPO_ROOT to already be set by the
# sourcing script.
# =============================================================================

# State dir for Ghostties Demo.app (bundle ID com.seansmithdesign.ghostties.demo).
# NEVER equals the release workspace dir (~/Library/Application Support/Ghostties).
# Overridable only for fail-closed verification against a scratch copy — never
# set in normal runs.
DEMO_STATE_DIR="${DEMO_STATE_DIR_OVERRIDE:-$HOME/Library/Application Support/Ghostties Demo}"

# Repos root lives outside $HOME so a captured terminal pane's cwd never shows
# the real username — only DEMO_STATE_DIR (above) stays under $HOME.
REPOS_DIR="/Users/Shared/Ghostties Demo/repos"

# Name prefix demo-drive.sh / _stage-demo-sessions.sh use for sessions they
# stage, and the default number of sessions staged when --count isn't passed.
# demo-ready.sh --check uses both to verify sessions are staged without
# hardcoding a count that could drift from demo-drive.sh's own default.
DEMO_SESSION_MARKER="Demo Agent — "
DEMO_DRIVE_DEFAULT_COUNT=4

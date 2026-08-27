#!/bin/sh
#
# ghostties-status.sh — Claude Code hook that publishes session status to
# ~/.ghostties/state/ for Ghostties to read.
#
# This script is APP-OWNED: it is seeded to ~/.ghostties/hooks/ by
# HookInstaller.swift and OVERWRITTEN whenever the app bumps
# HookInstaller.seedVersion. Any local edits to the seeded copy will be
# lost on the next version bump — edit this source file instead.
#
# Sean registers this script per-event in ~/.claude/settings.json with
# "async": true on every event (UserPromptSubmit, PreToolUse, PostToolUse,
# Stop, Notification, PermissionRequest, SessionEnd). It must never block
# or fail a Claude Code hook, so every exit path is 0.
#
# Behaviour:
#   1. No-op if GHOSTTIES_SESSION_ID is unset/empty, or contains anything
#      other than [A-Za-z0-9-] (it becomes part of a filename).
#   2. Reads the hook JSON payload from stdin.
#   3. Writes {"ghosttiesSessionId","updatedAt","hook"} to
#      ~/.ghostties/state/<id>.json (or <id>.todos.json for a
#      PostToolUse/TodoWrite payload), via a same-directory temp file +
#      rename so directory watchers see a real rename(2), not an in-place
#      write.

trap 'exit 0' EXIT

[ -z "$GHOSTTIES_SESSION_ID" ] && exit 0

case "$GHOSTTIES_SESSION_ID" in
    *[!A-Za-z0-9-]*) exit 0 ;;
esac

payload=$(cat)

state_dir="$HOME/.ghostties/state"
mkdir -p "$state_dir" || exit 0
chmod 700 "$state_dir" || exit 0

case "$payload" in
    *'"tool_name":"TodoWrite"'*|*'"tool_name": "TodoWrite"'*)
        dest="$state_dir/$GHOSTTIES_SESSION_ID.todos.json"
        ;;
    *)
        dest="$state_dir/$GHOSTTIES_SESSION_ID.json"
        ;;
esac

tmp="$dest.$$.tmp"

if [ -z "$payload" ]; then
    hook_json=null
else
    hook_json=$payload
fi

printf '{"ghosttiesSessionId":"%s","updatedAt":%s,"hook":%s}' \
    "$GHOSTTIES_SESSION_ID" "$(date +%s)" "$hook_json" > "$tmp" || exit 0

mv -f "$tmp" "$dest" || exit 0

exit 0

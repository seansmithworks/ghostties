#!/bin/bash
# check-test-defaults.sh — fails if a test can reach the app's real defaults
# domain. Run by CI (test-ghostties.yml); takes no build and no arguments.
#
# Why: hosted tests run inside the app, so UserDefaults.standard IS the real
# domain of any live build sharing the bundle ID. A test's write reaches that
# build's windows at their next redraw; every test run flipped a running capture
# build's Approve/Deny off this way. Reading .standard to prove it didn't change
# is fine. Tests write AppDefaults / SidebarDialTuning, or a private suite
# (withDials, PrivateDefaultsTestCase), never .standard.
#
# Production gets the same line, because code under test writes too: settings
# go through AppDefaults.store, and an @AppStorage names its store.
#
# Usage: scripts/check-test-defaults.sh [root]   (root defaults to the repo)
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit 2

fail=0
report() {
  echo "error: $1"
  echo "$2" | sed 's/^/  /'
  fail=1
}

check() { # check <message> <regex> <paths...>
  local message="$1" regex="$2"; shift 2
  local hits
  hits="$(grep -rnE --include='*.swift' "$regex" "$@" 2>/dev/null | grep -vE '^[^:]+:[0-9]+: *//')"
  [[ -z "$hits" ]] || report "$message" "$hits"
}

TESTS=(macos/Tests macos/GhosttyUITests)

check "tests must not write UserDefaults.standard; use AppDefaults, withDials or PrivateDefaultsTestCase" \
  'UserDefaults\.standard\.(set|setValue|setPersistentDomain|removeObject|removePersistentDomain|register|setVolatileDomain|removeVolatileDomain|addSuite|synchronize)\b' \
  "${TESTS[@]}"
check "tests must not hold UserDefaults.standard in a variable or pass it on; a write through it is invisible here" \
  '(^|[^=!])= *(UserDefaults)?\.standard *($|[^.[:alnum:]])|[(,:] *(UserDefaults)?\.standard *([,)]|$)|UserDefaults\(\)' \
  "${TESTS[@]}"
check "tests must not run defaults(1) against a real domain; UI tests pass launch arguments" \
  '/usr/bin/defaults|"defaults"|CFPreferencesSet' \
  "${TESTS[@]}"
check "tests must not open a real Ghostties domain as a suite" \
  'suiteName: *"com\.(seansmithdesign\.ghostties|mitchellh\.ghostty)(\.(dev|debug|demo|capture))?"' \
  "${TESTS[@]}"

SOURCES=macos/Sources
check "settings go through AppDefaults.store, not UserDefaults.standard" \
  'UserDefaults\.standard\.(set|setValue|removeObject)\b' \
  "$SOURCES"
check "an @AppStorage must name its store (AppDefaults.store, or a dial's SidebarDialTuning.store)" \
  '@AppStorage\([^,]*\)( |$)' \
  "$SOURCES"

if [[ "$fail" -ne 0 ]]; then
  echo "check-test-defaults: FAILED (see macos/Tests/Ghostties/GhosttiesTestIsolation.swift)"
  exit 1
fi
echo "check-test-defaults: ok"

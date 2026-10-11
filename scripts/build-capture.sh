#!/bin/bash
# build-capture.sh — build a Ghostties Dev app with its OWN bundle ID so an
# agent can launch it (captures, `open -n`, hosted tests) without quitting
# Sean's running Dev.
#
# Why: every Debug build shares com.seansmithdesign.ghostties.dev, and a
# second instance under one bundle ID terminates the first (clean terminate:,
# not a crash). This uses the existing GHOSTTIES_DEV_BUNDLE_SUFFIX build
# setting (project.pbxproj) — same mechanism as scripts/demo/demo-capture.sh.
#
# State isolation: WorkspacePersistence maps any ID that is not exact-release
# or *.dev/*.debug/*.demo to its own "Ghostties (<bundleId>)" folder, so the
# ".capture" suffix never touches Sean's "Ghostties Dev" workspace. Do NOT
# change the suffix to end in ".dev" — that would share his Dev state folder.
#
# Usage:
#   scripts/build-capture.sh              # build only (never launches)
#   scripts/build-capture.sh test [args]  # build-for-testing + test, same ID;
#                                         # extra args go to xcodebuild
#                                         # (e.g. -only-testing:...)
# Output: <repo>/.build-capture/Build/Products/Debug/Ghostties Dev.app
#         (bundle ID com.seansmithdesign.ghostties.capture)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"  # relative -project: an absolute path failed to resolve GhosttyKit.xcframework
ACTION="build"
if [[ "${1:-}" == "test" ]]; then ACTION="test"; shift; fi

xcodebuild "$ACTION" \
  -project macos/Ghostties.xcodeproj \
  -scheme Ghostties \
  -configuration Debug \
  -derivedDataPath .build-capture \
  ONLY_ACTIVE_ARCH=YES \
  ARCHS=arm64 \
  GHOSTTIES_DEV_BUNDLE_SUFFIX=.capture \
  -skipPackagePluginValidation \
  "$@"

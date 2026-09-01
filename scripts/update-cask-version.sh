#!/usr/bin/env bash
# update-cask-version.sh — Bump dist/ghostties/homebrew/ghostties.rb to a new release.
#
# Usage: bash scripts/update-cask-version.sh <tag>
#   e.g. bash scripts/update-cask-version.sh v0.1.0-beta.24
#
# Resolves the sha256 of that release's Ghostties.dmg from GitHub (never
# hand-typed) and rewrites `version` + `sha256` in the cask. Idempotent —
# running it again with the same tag re-verifies and leaves the file
# unchanged. Fails loudly if the release or the DMG asset is missing.
#
# Requires: gh (authenticated), curl, and sha256sum (or shasum as a fallback).
# Portable by construction: no GNU- or BSD-only flags (mktemp template,
# sed-to-temp-then-mv instead of sed -i, sha256sum/shasum fallback).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CASK_FILE="$REPO_ROOT/dist/ghostties/homebrew/ghostties.rb"
REPO="SeanSmithWorks/ghostties"
ASSET="Ghostties.dmg"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <tag>" >&2
    echo "  e.g. $0 v0.1.0-beta.24" >&2
    exit 1
fi

TAG="$1"
VERSION="${TAG#v}"

if [[ ! -f "$CASK_FILE" ]]; then
    echo "Cask file not found at $CASK_FILE" >&2
    exit 1
fi

command -v gh >/dev/null 2>&1 || { echo "gh CLI is required." >&2; exit 1; }

echo "Looking up release ${TAG} on ${REPO}…"
if ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "Release ${TAG} not found on ${REPO}." >&2
    exit 1
fi

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"

echo "Downloading ${ASSET} to compute sha256 (this is ~150MB, may take a minute)…"
TMP_DMG="$(mktemp "${TMPDIR:-/tmp}/ghostties-cask-dmg.XXXXXX")"
trap 'rm -f "$TMP_DMG"' EXIT

HTTP_STATUS=$(curl -L --fail -o "$TMP_DMG" -w "%{http_code}" "$DOWNLOAD_URL") || {
    echo "Failed to download ${DOWNLOAD_URL} (HTTP ${HTTP_STATUS:-unknown})." >&2
    exit 1
}

if command -v sha256sum >/dev/null 2>&1; then
    SHA256=$(sha256sum "$TMP_DMG" | awk '{print $1}')
else
    SHA256=$(shasum -a 256 "$TMP_DMG" | awk '{print $1}')
fi

if [[ -z "$SHA256" ]]; then
    echo "Failed to compute sha256 for ${ASSET}." >&2
    exit 1
fi

echo "  version: $VERSION"
echo "  sha256:  $SHA256"

# Idempotent rewrite of the two version-derived lines. Written to a temp
# file and moved into place rather than using `sed -i`, whose in-place
# flag syntax differs between BSD and GNU sed.
sed -E \
    -e "s/^(  version \")[^\"]+(\")$/\1${VERSION}\2/" \
    -e "s/^(  sha256 \")[^\"]+(\")$/\1${SHA256}\2/" \
    "$CASK_FILE" > "$CASK_FILE.tmp"
mv "$CASK_FILE.tmp" "$CASK_FILE"

# Verify the rewrite actually landed (fail loudly rather than silently no-op).
if ! grep -q "version \"${VERSION}\"" "$CASK_FILE"; then
    echo "Failed to write version into $CASK_FILE." >&2
    exit 1
fi
if ! grep -q "sha256 \"${SHA256}\"" "$CASK_FILE"; then
    echo "Failed to write sha256 into $CASK_FILE." >&2
    exit 1
fi

echo "Updated $CASK_FILE to ${VERSION} (${SHA256})."

ruby -c "$CASK_FILE" >/dev/null || {
    echo "Rewritten cask file has invalid Ruby syntax." >&2
    exit 1
}

echo "Done."

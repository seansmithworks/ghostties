#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────
# Download CEF (Chromium Embedded Framework) for macOS ARM64
# Used by the embedded browser feature in Ghostties
# ─────────────────────────────────────────────────────────────────────

CEF_PLATFORM="macosarm64"
CEF_DIST="standard"
CEF_DIR="vendor/cef"
CEF_BASE_URL="https://cef-builds.spotifycdn.com"

# ─── Pinned version ──────────────────────────────────────────────────
# The build downloads a fixed CEF release, not "latest stable" — the
# download server must never be trusted to pick what ships to users.
#
# To roll forward: download the new cef_binary_<version>_macosarm64.tar.bz2
# from https://cef-builds.spotifycdn.com/index.json, run
# `shasum -a 256` on it, and update both constants below together.
CEF_VERSION="144.0.32+g5ce7d26+chromium-144.0.7559.258"
CEF_SHA256="cf923ad835fe7b1ae8cc358af8e97de1fd7ae29a5c328d8173260caf4a77d989"

# ─── Check existing installation ────────────────────────────────────
if [ -f "$CEF_DIR/.version" ]; then
  EXISTING_VERSION=$(cat "$CEF_DIR/.version")
  if [ "$EXISTING_VERSION" = "$CEF_VERSION" ]; then
    echo "CEF already downloaded (version $CEF_VERSION)"
    exit 0
  fi
  echo "Existing CEF version $EXISTING_VERSION differs from target $CEF_VERSION"
  echo "Removing old installation..."
  rm -rf "$CEF_DIR"
fi

# ─── Build download URL ─────────────────────────────────────────────
# Filename format: cef_binary_<cef_version>_<platform>.tar.bz2
# Note: cef_version already includes +chromium-<version> suffix
CEF_FILENAME="cef_binary_${CEF_VERSION}_${CEF_PLATFORM}.tar.bz2"
CEF_URL="${CEF_BASE_URL}/${CEF_FILENAME}"

echo ""
echo "Downloading CEF binary distribution..."
echo "  URL: $CEF_URL"
echo "  This is ~300MB, please be patient."
echo ""

# ─── Download ────────────────────────────────────────────────────────
TMPDIR_DL=$(mktemp -d)
trap 'rm -rf "$TMPDIR_DL"' EXIT

DOWNLOAD_PATH="${TMPDIR_DL}/${CEF_FILENAME}"
curl -fSL --progress-bar -o "$DOWNLOAD_PATH" "$CEF_URL" || {
  echo "ERROR: Download failed from $CEF_URL" >&2
  echo "Check that this CEF version is available for $CEF_PLATFORM." >&2
  exit 1
}

echo "Download complete. Size: $(du -h "$DOWNLOAD_PATH" | cut -f1)"

# ─── Verify checksum (against pinned SHA-256) ────────────────────────
# The expected hash is never fetched from the network — it's committed
# above as CEF_SHA256, alongside the pinned CEF_VERSION.
echo "Verifying SHA-256 checksum against pinned value..."
command -v shasum >/dev/null 2>&1 || {
  echo "ERROR: shasum not found; cannot verify download integrity." >&2
  exit 1
}

if [ ! -s "$DOWNLOAD_PATH" ]; then
  echo "ERROR: Downloaded file is missing or empty: $DOWNLOAD_PATH" >&2
  exit 1
fi

ACTUAL_SHA256=$(shasum -a 256 "$DOWNLOAD_PATH" | awk '{print $1}')
if [ "$ACTUAL_SHA256" != "$CEF_SHA256" ]; then
  echo "ERROR: SHA-256 checksum mismatch!" >&2
  echo "  Expected: $CEF_SHA256" >&2
  echo "  Actual:   $ACTUAL_SHA256" >&2
  exit 1
fi
echo "SHA-256 checksum verified: $ACTUAL_SHA256"

# ─── Remove macOS quarantine attribute ───────────────────────────────
# CEF archives downloaded from the internet get quarantined by macOS
xattr -d com.apple.quarantine "$DOWNLOAD_PATH" 2>/dev/null || true

# ─── Extract ─────────────────────────────────────────────────────────
echo "Extracting to $CEF_DIR/..."
mkdir -p "$CEF_DIR"

# Extract and strip the top-level directory from the archive
tar -xjf "$DOWNLOAD_PATH" -C "$CEF_DIR" --strip-components=1 || {
  echo "ERROR: Failed to extract archive" >&2
  rm -rf "$CEF_DIR"
  exit 1
}

# ─── Write version marker ───────────────────────────────────────────
echo "$CEF_VERSION" > "$CEF_DIR/.version"

echo ""
echo "CEF downloaded and extracted successfully."
echo "  Version:  CEF $CEF_VERSION"
echo "  Location: $CEF_DIR/"
echo "  Contents: $(find "$CEF_DIR" -maxdepth 1 -mindepth 1 | wc -l | tr -d ' ') top-level items"

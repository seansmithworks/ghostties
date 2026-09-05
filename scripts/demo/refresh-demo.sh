#!/usr/bin/env bash
# =============================================================================
# refresh-demo.sh — Produce/refresh Ghostties Demo.app for marketing capture
#
# PURPOSE
#   Produces "Ghostties Demo.app" with bundle ID com.seansmithdesign.ghostties.demo,
#   which causes WorkspacePersistence to resolve its state directory to
#   "~/Library/Application Support/Ghostties Demo/" — completely isolated from
#   the release ("Ghostties") and dev ("Ghostties Dev") workspaces.
#
# DEFAULT MODE: --from-release
#   Downloads a published GitHub release artifact (the same binary Sean ships)
#   and re-bundles it as the demo app. This is the correct source for a
#   marketing demo — it matches what's actually shipping.
#
# USAGE
#   ./scripts/demo/refresh-demo.sh                       # latest release (incl. pre-releases)
#   ./scripts/demo/refresh-demo.sh --from-release v0.1.0-beta.24
#   ./scripts/demo/refresh-demo.sh --from-source          # build local checkout (Debug)
#   ./scripts/demo/refresh-demo.sh --from-source --pull-main
#   ./scripts/demo/refresh-demo.sh --dest /tmp/x.app --no-launch
#
# FLAGS
#   --from-release [TAG]  Download the published release asset and re-bundle it.
#                          DEFAULT if no source flag is given. With no TAG, resolves
#                          to the newest release (including pre-releases) on
#                          SeanSmithWorks/ghostties. With TAG, uses that exact tag.
#   --from-source          Build the current local checkout instead (Debug, arm64).
#   --pull-main            Only valid with --from-source. Fetch origin + checkout
#                          main + pull --ff-only BEFORE building.
#   --dest <path>          Destination .app path. Default: /Applications/Ghostties Demo.app
#   --no-launch            Skip the final `open` step.
#
# SAFETY
#   - Never modifies ~/Library/Application Support/Ghostties/ (release workspace).
#   - Never runs killall. Quit any existing instance before running.
#   - arm64 only (GhosttyKit.xcframework is arm64-only).
#   - Sparkle auto-update is DISABLED in the demo build (ad-hoc re-signing
#     invalidates the Developer ID signature Sparkle needs). This script IS
#     the demo's update mechanism — re-run it to refresh.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCHEME="Ghostties"
PROJECT="$REPO_ROOT/macos/Ghostties.xcodeproj"
BUILD_DIR="$REPO_ROOT/.build-demo"
BUNDLE_ID="com.seansmithdesign.ghostties.demo"
RELEASE_REPO="SeanSmithWorks/ghostties"
ASSET_NAME="ghostties-macos-arm64.zip"
CACHE_DIR="$HOME/Library/Caches/ghostties-demo"

MODE="from-release"
RELEASE_TAG=""
DEST_APP="/Applications/Ghostties Demo.app"
DO_LAUNCH=1
PULL_MAIN=0

# ── Arg parsing ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-release)
      MODE="from-release"
      shift
      # Optional positional tag: only consume it if it doesn't look like another flag.
      if [[ $# -gt 0 && "$1" != --* ]]; then
        RELEASE_TAG="$1"
        shift
      fi
      ;;
    --from-source)
      MODE="from-source"
      shift
      ;;
    --pull-main)
      PULL_MAIN=1
      shift
      ;;
    --dest)
      DEST_APP="$2"
      shift 2
      ;;
    --no-launch)
      DO_LAUNCH=0
      shift
      ;;
    *)
      echo "ERROR: Unrecognized argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "$PULL_MAIN" -eq 1 && "$MODE" != "from-source" ]]; then
  echo "ERROR: --pull-main is only valid with --from-source." >&2
  exit 1
fi

echo "==> Ghostties Demo refresh"
echo "    Mode: $MODE"
echo "    Dest: $DEST_APP"
echo ""

BUILT_APP=""

if [[ "$MODE" == "from-source" ]]; then
  echo "    Repo: $REPO_ROOT"
  echo "    Branch: $(git -C "$REPO_ROOT" branch --show-current)"
  echo ""

  if [[ "$PULL_MAIN" -eq 1 ]]; then
    echo "==> [--pull-main] Fetching origin and switching to main..."
    git -C "$REPO_ROOT" fetch origin
    git -C "$REPO_ROOT" checkout main
    git -C "$REPO_ROOT" pull --ff-only
    echo "    Done. Now on: $(git -C "$REPO_ROOT" branch --show-current)"
    echo ""
  fi

  echo "==> Phase 1: Building from source (Debug, arm64)..."
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -derivedDataPath "$BUILD_DIR" \
    ONLY_ACTIVE_ARCH=YES \
    ARCHS=arm64 \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build \
    | grep -E "^(Build|CompileSwift|error:|warning: build input|PhaseScriptExecution|== BUILD)" \
    | head -200 || true

  BUILT_APP=$(find "$BUILD_DIR/Build/Products/Debug" -maxdepth 1 -name "Ghostties Dev.app" -type d | head -1)
  if [[ -z "$BUILT_APP" ]]; then
    echo ""
    echo "ERROR: Build output not found at $BUILD_DIR/Build/Products/Debug/Ghostties Dev.app"
    echo "       Run xcodebuild without grep to see full error output."
    exit 1
  fi
  echo "    Built: $BUILT_APP"
  echo ""
else
  # ── from-release ────────────────────────────────────────────────────────────
  if [[ -z "$RELEASE_TAG" ]]; then
    echo "==> Resolving newest release (including pre-releases) on $RELEASE_REPO..."
    RELEASE_TAG=$(gh release list --repo "$RELEASE_REPO" --limit 1 --json tagName -q '.[0].tagName')
    if [[ -z "$RELEASE_TAG" ]]; then
      echo "ERROR: Could not resolve a release tag from $RELEASE_REPO." >&2
      exit 1
    fi
  fi
  echo "    Resolved tag: $RELEASE_TAG"
  echo ""

  CACHED_ZIP="$CACHE_DIR/$RELEASE_TAG/$ASSET_NAME"
  if [[ -f "$CACHED_ZIP" ]]; then
    echo "==> Using cached asset: $CACHED_ZIP"
  else
    echo "==> Downloading $ASSET_NAME for $RELEASE_TAG (~147MB)..."
    mkdir -p "$CACHE_DIR/$RELEASE_TAG"
    TMP_DL_DIR="$(mktemp -d)"
    gh release download "$RELEASE_TAG" \
      --repo "$RELEASE_REPO" \
      --pattern "$ASSET_NAME" \
      --dir "$TMP_DL_DIR"
    mv "$TMP_DL_DIR/$ASSET_NAME" "$CACHED_ZIP"
    rm -rf "$TMP_DL_DIR"
    echo "    Cached: $CACHED_ZIP"
  fi
  echo ""

  echo "==> Unzipping release artifact..."
  UNZIP_DIR="$(mktemp -d)"
  ditto -x -k "$CACHED_ZIP" "$UNZIP_DIR"
  BUILT_APP=$(find "$UNZIP_DIR" -maxdepth 2 -name "*.app" -type d | head -1)
  if [[ -z "$BUILT_APP" ]]; then
    echo "ERROR: No .app found inside $ASSET_NAME." >&2
    exit 1
  fi
  echo "    Found: $BUILT_APP"
  echo ""
fi

# ── Phase 2: Re-bundle ───────────────────────────────────────────────────────
echo "==> Re-bundling to '$DEST_APP'..."

mkdir -p "$(dirname "$DEST_APP")"
if [[ -d "$DEST_APP" ]]; then
  echo "    Removing previous $DEST_APP..."
  rm -rf "$DEST_APP"
fi

cp -R "$BUILT_APP" "$DEST_APP"
echo "    Copied."

PLIST="$DEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID"         "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Ghostties Demo"           "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Ghostties Demo"    "$PLIST"

# Neutralise Sparkle — ad-hoc re-signing invalidates the Developer ID signature
# Sparkle needs to trust an update, so leaving the feed URL in place would just
# produce silent update failures. This script is the demo's update mechanism.
if /usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$PLIST" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$PLIST"
  echo "    Removed SUFeedURL."
fi
if /usr/libexec/PlistBuddy -c "Print :SUEnableAutomaticChecks" "$PLIST" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks false" "$PLIST"
else
  /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool false" "$PLIST"
fi
echo "    Sparkle disabled. This script is the demo's update mechanism — re-run it to refresh."

echo "    Plist updated:"
echo "      CFBundleIdentifier  = $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
echo "      CFBundleName        = $(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$PLIST")"
echo "      CFBundleDisplayName = $(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$PLIST")"
echo "      CFBundleExecutable  = $(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST") (unchanged)"
echo ""

# ── Phase 3: Re-sign ad-hoc ──────────────────────────────────────────────────
echo "==> Ad-hoc re-signing..."
if [[ "$MODE" == "from-release" ]]; then
  echo "    Clearing quarantine attribute (downloaded artifact)..."
  xattr -dr com.apple.quarantine "$DEST_APP" || true
fi
codesign --force --deep --sign - "$DEST_APP"
echo "    Signed. Verifying..."
codesign --verify --deep "$DEST_APP"
echo "    Verification passed."
echo ""

# ── Phase 4: Launch ──────────────────────────────────────────────────────────
if [[ "$DO_LAUNCH" -eq 1 ]]; then
  echo "==> Launching Ghostties Demo..."
  open "$DEST_APP"
  echo "    Launched."
  echo ""
else
  echo "==> Skipping launch (--no-launch)."
  echo ""
fi

echo "==> Done. Ghostties Demo is at:"
echo "    $DEST_APP"
echo "    State: ~/Library/Application Support/Ghostties Demo/workspace.json"
echo ""
echo "    To quit cleanly (never use killall):"
echo "    osascript -e 'tell application \"Ghostties Demo\" to quit'"

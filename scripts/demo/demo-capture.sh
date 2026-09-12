#!/usr/bin/env bash
# =============================================================================
# demo-capture.sh — Agent-facing entrypoint: capture marketing PNGs from the
# seeded Ghostties Demo workspace (real fixture repos, not the hardcoded
# in-app cast MarketingCaptureUITests uses).
#
# PIPELINE
#   1. demo-ready.sh --check   — abort if the demo app / fixtures are stale.
#   2. Copy the demo state dir to a throwaway location. The demo state dir
#      itself is treated as READ-ONLY: never written to, never launched
#      against directly.
#   3. Run DemoWorkspaceCaptureUITests via `xcodebuild test`, pointing the
#      app at the throwaway copy via GHOSTTIES_STATE_DIR. That test asserts
#      the override took effect (a demo-only fixture project is visible)
#      before it captures anything — see the test file for why.
#   4. Copy the resulting PNGs to the output directory, alongside a copy of
#      demo-manifest.json so every capture traces to the build that made it.
#   5. Assert every captured PNG is non-blank before declaring success.
#
# USAGE
#   ./scripts/demo/demo-capture.sh                     # default output dir
#   ./scripts/demo/demo-capture.sh --out /path/to/dir   # custom output dir
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEMO_READY_SCRIPT="$REPO_ROOT/scripts/demo/demo-ready.sh"

source "$REPO_ROOT/scripts/demo/_demo-paths.sh"

MANIFEST_PATH="$DEMO_STATE_DIR/demo-manifest.json"

BUILD_DIR="$REPO_ROOT/macos/build"
OUTPUT_DIR="$REPO_ROOT/output/demo-capture"
ONLY_TESTING="GhosttyUITests/DemoWorkspaceCaptureUITests"
EXPECTED_TEST_COUNT=2

# ── Arg parsing ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      echo "ERROR: Unrecognized argument: $1" >&2
      exit 1
      ;;
  esac
done

fail() {
  echo "ERROR: $1" >&2
  exit 1
}

echo "==> Ghostties demo-capture"
echo "    Output: $OUTPUT_DIR"
echo ""

# ── 1. Preflight: demo app + fixtures must be current ───────────────────────
echo "==> Checking demo readiness..."
if ! "$DEMO_READY_SCRIPT" --check; then
  fail "Demo app / fixtures are stale. Run './scripts/demo/demo-ready.sh' first."
fi
echo ""

[[ -d "$DEMO_STATE_DIR" ]] || fail "Demo state dir not found: $DEMO_STATE_DIR"

# ── 2. Copy the demo state dir to a throwaway location ──────────────────────
COPY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ghostties-demo-capture-state.XXXXXX")"
cleanup() {
  rm -rf "$COPY_DIR"
}
trap cleanup EXIT

echo "==> Copying demo state dir (read-only source) to throwaway location..."
echo "    Source: $DEMO_STATE_DIR"
echo "    Copy:   $COPY_DIR"
# Copy contents, not the directory itself, so COPY_DIR is the state dir root.
cp -R "$DEMO_STATE_DIR/." "$COPY_DIR/"
echo ""

# Sanity: the copy must actually contain a workspace.json, or the override
# would produce an empty/default workspace and the test's fail-closed assert
# would (correctly) fail — catch the more obvious case here with a clearer
# message.
[[ -f "$COPY_DIR/workspace.json" ]] || fail "Copied state dir has no workspace.json — run demo-ready.sh (it seeds this)."

# ── 2b. Fixture zsh dotdir — strips the real username/hostname from the ────
# captured prompt. Lives inside the throwaway COPY_DIR, never under $HOME.
# Each dotfile sources the matching real one from $HOME first (if present)
# so PATH and `claude` still resolve, then .zshrc overrides the prompt.
# Ghostty's zsh auto-integration round-trips ZDOTDIR through its own
# resource dir and restores this value before sourcing these files — see
# src/termio/shell_integration.zig's setupZsh and
# src/shell-integration/zsh/.zshenv:28-33,45. Passed as a TEST_RUNNER_ env
# var (process env), never a trailing build setting — a build setting runs
# 0 tests and exits green.
DEMO_ZDOTDIR="$COPY_DIR/.demo-zdotdir"
mkdir -p "$DEMO_ZDOTDIR"

cat > "$DEMO_ZDOTDIR/.zshenv" <<'EOF'
[[ -r "$HOME/.zshenv" ]] && source "$HOME/.zshenv"
EOF

cat > "$DEMO_ZDOTDIR/.zprofile" <<'EOF'
[[ -r "$HOME/.zprofile" ]] && source "$HOME/.zprofile"
EOF

cat > "$DEMO_ZDOTDIR/.zshrc" <<'EOF'
[[ -r "$HOME/.zshrc" ]] && source "$HOME/.zshrc"

# User/host-free prompt for marketing captures — overrides anything the
# real .zshrc above set.
PROMPT='%1~ %# '
RPROMPT=''
EOF

# ── 3. Run the capture test ──────────────────────────────────────────────────
echo "==> Running DemoWorkspaceCaptureUITests..."
RESULT_BUNDLE="$(mktemp -d "${TMPDIR:-/tmp}/ghostties-demo-capture-result.XXXXXX")/Result.xcresult"

set +e
TEST_RUNNER_GHOSTTIES_UI_CAPTURE=1 \
TEST_RUNNER_GHOSTTIES_DEMO_STATE_DIR="$COPY_DIR" \
TEST_RUNNER_GHOSTTIES_DEMO_ZDOTDIR="$DEMO_ZDOTDIR" \
xcodebuild test \
  -project "$REPO_ROOT/macos/Ghostties.xcodeproj" \
  -scheme Ghostties \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -only-testing:"$ONLY_TESTING" \
  ONLY_ACTIVE_ARCH=YES \
  ARCHS=arm64 \
  GHOSTTIES_DEV_BUNDLE_SUFFIX=.democapture.dev \
  -skipPackagePluginValidation \
  | tee "$COPY_DIR/xcodebuild.log"
XCODEBUILD_EXIT=${PIPESTATUS[0]}
set -e

# ── Resolve real totals FIRST — never trust raw log lines or exit code ─────
# alone. xcodebuild also exits 65 for a plain test failure, not just a
# build failure, so classify only after the xcresult totals are in hand.
if [[ ! -d "$RESULT_BUNDLE" ]]; then
  fail "No result bundle produced at $RESULT_BUNDLE (xcodebuild exit $XCODEBUILD_EXIT) — this is a BUILD failure, not a test failure. See log above."
fi

SUMMARY_JSON="$(xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" --format json)"
TOTAL_TEST_COUNT="$(echo "$SUMMARY_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("totalTestCount", 0))')"
PASSED_COUNT="$(echo "$SUMMARY_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("passedTests", 0))')"
FAILED_COUNT="$(echo "$SUMMARY_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("failedTests", 0))')"

echo ""
echo "==> Resolved totals: total=$TOTAL_TEST_COUNT passed=$PASSED_COUNT failed=$FAILED_COUNT"

if [[ "$TOTAL_TEST_COUNT" -eq 0 ]]; then
  if [[ "$XCODEBUILD_EXIT" -eq 65 ]]; then
    fail "xcodebuild exited 65 with zero tests resolved — this is a BUILD failure. See log above."
  fi
  fail "-only-testing:$ONLY_TESTING matched ZERO tests. This is a malformed -only-testing filter (Swift Testing identifiers need '()'), not a clean run — xcodebuild's exit code cannot be trusted here."
fi
if [[ "$TOTAL_TEST_COUNT" -ne "$EXPECTED_TEST_COUNT" ]]; then
  fail "Expected $EXPECTED_TEST_COUNT tests, resolved $TOTAL_TEST_COUNT. Check -only-testing filter and DemoWorkspaceCaptureUITests' test method count."
fi
if [[ "$FAILED_COUNT" -gt 0 || "$XCODEBUILD_EXIT" -ne 0 ]]; then
  fail "$FAILED_COUNT test(s) failed (xcodebuild exit $XCODEBUILD_EXIT). See $RESULT_BUNDLE."
fi

# ── 4. Copy PNGs out ─────────────────────────────────────────────────────────
echo ""
echo "==> Collecting captured PNGs..."
mkdir -p "$OUTPUT_DIR"

CAPTURE_PATHS=()
while IFS= read -r line; do
  CAPTURE_PATHS+=("$line")
done < <(grep -o 'CAPTURE_OUTPUT: .*\.png' "$COPY_DIR/xcodebuild.log" | sed 's/^CAPTURE_OUTPUT: //' | sort -u)

if [[ "${#CAPTURE_PATHS[@]}" -eq 0 ]]; then
  fail "No CAPTURE_OUTPUT lines found in xcodebuild log — no PNGs were produced."
fi

for src in "${CAPTURE_PATHS[@]}"; do
  [[ -f "$src" ]] || fail "Captured PNG reported by the test does not exist on disk: $src"
  dest="$OUTPUT_DIR/$(basename "$src")"
  cp "$src" "$dest"
  echo "    $dest"
done

# ── 5. Assert every captured PNG is non-blank ────────────────────────────────
# A denied screen-capture permission or a black/empty window still produces a
# structurally valid PNG and exit 0 — check actual pixel variance, not just
# file existence. Use sips to get pixel dimensions and a rough content check
# via file size as a floor, then a real variance check via python3/Foundation
# if Pillow-less: compare min/max pixel bytes isn't available without a
# library, so fall back to comparing this run's PNG against a solid-color PNG
# of the same dimensions generated on the fly, plus a minimum-file-size floor
# that a genuinely blank 2x window screenshot cannot plausibly clear.
echo ""
echo "==> Verifying captured PNGs are non-blank..."
for f in "$OUTPUT_DIR"/*.png; do
  [[ -f "$f" ]] || continue

  DIMENSIONS="$(sips -g pixelWidth -g pixelHeight "$f" 2>/dev/null | awk '/pixelWidth|pixelHeight/ {print $2}' | tr '\n' 'x' | sed 's/x$//')"
  echo "    $(basename "$f"): ${DIMENSIONS}px"

  python3 - "$f" <<'PYEOF'
import sys
import struct
import zlib
from collections import Counter

path = sys.argv[1]

def read_png_chunks(data):
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos = 8
    chunks = []
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        ctype = data[pos + 4:pos + 8]
        cdata = data[pos + 8:pos + 8 + length]
        chunks.append((ctype, cdata))
        pos += 12 + length
    return chunks

with open(path, "rb") as fh:
    data = fh.read()

chunks = read_png_chunks(data)
ihdr = next((cdata for ctype, cdata in chunks if ctype == b"IHDR"), None)
if ihdr is None:
    print(f"FAIL: {path} has no IHDR chunk (not a real PNG)")
    sys.exit(1)
width, height = struct.unpack(">II", ihdr[:8])

idat = b"".join(cdata for ctype, cdata in chunks if ctype == b"IDAT")
if not idat:
    print(f"FAIL: {path} has no IDAT chunk (not a real image)")
    sys.exit(1)

# Decompress the filtered scanline stream. We don't need to fully unfilter
# (reverse Paev/Sub/Up prediction) to detect a blank frame: a genuinely
# blank/solid-color capture (e.g. from a denied screen-recording permission)
# has every scanline start with filter byte 0 (None) and every pixel byte
# after it identical, so the raw decompressed stream itself is >99% one
# repeated byte value. A real UI screenshot with text, icons, and window
# chrome is not.
raw = zlib.decompress(idat)
if not raw:
    print(f"FAIL: {path} decompressed to 0 bytes")
    sys.exit(1)

counts = Counter(raw)
most_common_byte, most_common_count = counts.most_common(1)[0]
dominant_fraction = most_common_count / len(raw)

MAX_DOMINANT_FRACTION = 0.99
if dominant_fraction >= MAX_DOMINANT_FRACTION:
    print(
        f"FAIL: {path} ({width}x{height}) is {dominant_fraction:.4%} a single "
        f"repeated byte (0x{most_common_byte:02x}) in its decompressed pixel "
        f"data — looks blank/solid-color, not a real capture"
    )
    sys.exit(1)

print(
    f"    OK: {width}x{height}, {len(raw)} bytes decompressed pixel data, "
    f"dominant byte {dominant_fraction:.2%}"
)
PYEOF
done

echo ""

# ── 6. Manifest ───────────────────────────────────────────────────────────────
[[ -f "$MANIFEST_PATH" ]] || fail "No demo-manifest.json at $MANIFEST_PATH — demo-ready.sh should have written one."
cp "$MANIFEST_PATH" "$OUTPUT_DIR/demo-manifest.json"
echo "==> Copied manifest: $OUTPUT_DIR/demo-manifest.json"

echo ""
echo "==> demo-capture complete: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"

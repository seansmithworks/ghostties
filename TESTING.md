# Testing Ghostties

Ghostties has three test suites. Two of them cover the fork's own code and are the
ones you'll usually care about; the third is upstream Ghostty's.

## Swift Package — `cli/`

Covers `GhosttiesCore`, the `gt` CLI, and the `ghostties-mcp` server. No app host,
no Xcode needed, runs in seconds.

```bash
cd cli
swift test --parallel
```

Currently 110 tests. This is what CI runs on every PR.

## macOS app — Xcode

Covers the workspace sidebar and the macOS integration layer. These are
**app-hosted** tests: they launch `Ghostties Dev.app` to run.

In Xcode, open `macos/Ghostties.xcodeproj` and press **Cmd+U**.

From the command line:

```bash
xcodebuild test \
  -project macos/Ghostties.xcodeproj \
  -scheme Ghostties \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath macos/build \
  ONLY_ACTIVE_ARCH=YES \
  ARCHS=arm64 \
  -skipPackagePluginValidation
```

Currently 673 tests across 52 suites, about 15 seconds.

Two things that will bite you:

- **`-derivedDataPath` must be exactly `macos/build`.** Any other path inside
  `macos/` pulls Sparkle's Swift Package sources into SwiftLint's scope, and the
  build fails inside third-party code with errors that look unrelated to your change.
- **`ONLY_ACTIVE_ARCH=YES ARCHS=arm64` is required** for any command-line
  `xcodebuild` invocation here.

### Why CI doesn't run these

CI builds this suite with `build-for-testing` but does not execute it. App-hosted
tests hang on GitHub's headless runners when the test host tries to launch. That
hang is **specific to headless CI** — locally the suite runs fine and fast, as
above. So compilation is verified on every PR, but execution is a local step.

**If you're changing sidebar or macOS code, run Cmd+U before opening a PR.** CI will
not catch a failure here for you.

## Zig core — upstream

The terminal core is upstream Ghostty's code and has its own suite:

```bash
zig build test
zig build test -Dtest-filter=<name>   # the full suite is slow
```

Ghostties doesn't modify the terminal core, so this rarely needs running for
fork work.

## Before opening a PR

```bash
cd cli && swift test --parallel     # fast, always run
# then Cmd+U in Xcode if you touched macos/
swiftlint lint --strict --fix       # Swift formatting
```

Report totals, not a filtered subset — a filtered run that passes can hide a red
suite elsewhere.

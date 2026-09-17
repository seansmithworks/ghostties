# Ghostties

Fork of [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty). Adds multi-agent workspace sidebar on top of the upstream terminal.

## Git & GitHub

- **NEVER open PRs against upstream** (`ghostty-org/ghostty`). Only push/PR to `origin` (`SeanSmithWorks/ghostties`) unless the user explicitly says otherwise.
- `origin` = `SeanSmithWorks/ghostties` (the fork)
- `upstream` = `ghostty-org/ghostty` (read-only reference)

## Build

```bash
open macos/Ghostties.xcodeproj         # Open in Xcode, scheme "Ghostties"
# Cmd+U in Xcode to run tests

# Browser (CEF) — optional, needed for embedded browser
bash scripts/download-cef.sh  # Downloads ~300MB CEF framework

# zig build is broken on macOS 26 — all builds go through Xcode above.
# zig build run -Doptimize=ReleaseFast   # Build + launch release app
# rm -rf macos/build && zig build run -Doptimize=ReleaseFast  # Clean rebuild
```

## Xcode Project

- Project/scheme/target renamed to **Ghostties**
- `PRODUCT_MODULE_NAME = Ghostty` — all Swift code uses `import Ghostty` (do not change)
- `PRODUCT_NAME = Ghostties` — the built .app bundle name
- Test targets remain `GhosttyTests` / `GhosttyUITests`

## Design Quality

**Layers:** craft, a11y
**Aesthetic:** bold-content
**Strictness:** standard
**Teaching:** normal

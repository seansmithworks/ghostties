# Agent Development Guide

A file for [guiding coding agents](https://agents.md/).

## The fork

This is a fork of `ghostty-org/ghostty` that adds a multi-agent workspace sidebar.

- **Origin**: `SeanSmithWorks/ghostties` — all PRs go here
- **Upstream**: `ghostty-org/ghostty` — read-only reference. **NEVER** open PRs against upstream.

Ghostties is macOS-only. Upstream's Linux and FreeBSD GTK app is not built,
shipped, or tested here.

## Commands

> **`zig build` does not currently work on this machine.** Zig 0.15.2's linker
> fails on macOS 26+ (can't find `_abort`, `_free`, `_malloc`). Still 0.15.2 and
> now macOS 27.0 as of 2026-09-20, so nothing has changed that would fix it.
> Build through Xcode until Zig 0.16 ships, then re-check.

- **Build + launch**: open `macos/Ghostties.xcodeproj`, Cmd+R
- **Build (release, CLI)**:
  `xcodebuild -project macos/Ghostties.xcodeproj -scheme Ghostties -configuration Release -derivedDataPath macos/build ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`
- **Clean rebuild**: `rm -rf macos/build`, then the command above
- **Launch built app**: `open macos/build/Build/Products/Release/Ghostties.app`
- **Test (macOS app)**: open `macos/Ghostties.xcodeproj`, Cmd+U
- **Test (Swift package)**: `cd cli && swift test --parallel`
- **Browser (CEF)**: `bash scripts/download-cef.sh` — ~300MB, only needed for
  the embedded browser
- **Formatting**: `zig fmt .` · `swiftlint lint --strict --fix` · `prettier -w .`

Blocked on the Zig toolchain, kept for when it works again:
`zig build run -Doptimize=ReleaseFast` (build + launch),
`zig build -Demit-macos-app=false` (Zig only, skips the app bundle),
`zig build test` (slow; prefer `-Dtest-filter=<name>`).

See [TESTING.md](TESTING.md) for what each suite covers and the two xcodebuild
flags you need from the command line.

Editing docs? [docs/INFORMATION-ARCHITECTURE.md](docs/INFORMATION-ARCHITECTURE.md)
says who each file is for and how each one is meant to stay true. Do not add a new
document without answering the questions in it.

## Directory structure

- `src/` — shared Zig core (upstream's terminal)
- `macos/` — the macOS app
- `cli/` — Swift package: `gt` CLI, `ghostties-mcp` server, `GhosttiesCore`
- `macos/Sources/Features/Ghostties/` — workspace sidebar (the fork's main addition)
- `macos/Sources/Features/Terminal/` — upstream terminal, integration points
- `macos/Tests/Workspace/` — sidebar unit tests

## Module naming

- `PRODUCT_MODULE_NAME = Ghostty` — all Swift code uses `import Ghostty` (do NOT change)
- `PRODUCT_NAME = Ghostties` — the `.app` bundle name
- Xcode project, scheme and target: `Ghostties`
- Test targets keep upstream's names: `GhosttyTests` / `GhosttyUITests`

## Issues and PRs

Don't open issues or pull requests unless you've been asked to. When you are,
always target `SeanSmithWorks/ghostties` — never upstream.

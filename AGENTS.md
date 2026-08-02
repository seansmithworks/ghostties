# Agent Development Guide

A file for [guiding coding agents](https://agents.md/).

## The fork

This is a fork of `ghostty-org/ghostty` that adds a multi-agent workspace sidebar.

- **Origin**: `SeanSmithWorks/ghostties` — all PRs go here
- **Upstream**: `ghostty-org/ghostty` — read-only reference. **NEVER** open PRs against upstream.

Ghostties is macOS-only. Upstream's Linux and FreeBSD GTK app is not built,
shipped, or tested here.

## Commands

- **Build + launch**: `zig build run -Doptimize=ReleaseFast`
- **Clean rebuild**: `rm -rf macos/build && zig build run -Doptimize=ReleaseFast`
- **Launch built app**: `open macos/build/ReleaseLocal/Ghostties.app`
- **Build (Zig only)**: `zig build -Demit-macos-app=false` — skips the app bundle,
  much faster when you don't need it
- **Test (Swift package)**: `cd cli && swift test --parallel`
- **Test (macOS app)**: open `macos/Ghostties.xcodeproj`, Cmd+U
- **Test (Zig)**: `zig build test` — slow; prefer `-Dtest-filter=<name>`
- **Formatting**: `zig fmt .` · `swiftlint lint --strict --fix` · `prettier -w .`

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
- Xcode scheme: `Ghostties`

## Issues and PRs

Don't open issues or pull requests unless you've been asked to. When you are,
always target `SeanSmithWorks/ghostties` — never upstream.

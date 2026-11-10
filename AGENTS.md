# Agent Development Guide

A file for [guiding coding agents](https://agents.md/).

## The fork

This is a fork of `ghostty-org/ghostty` that adds a multi-agent workspace sidebar.

- **Origin**: `SeanSmithWorks/ghostties` — all PRs go here
- **Upstream**: `ghostty-org/ghostty` — read-only reference. **NEVER** open PRs against upstream.

Ghostties is macOS-only. Upstream's Linux and FreeBSD GTK app is not built,
shipped, or tested here.

## Commands

> **Default `zig` (0.15.2) fails to link on macOS 26+.** Zig 0.16 works:
> `/opt/homebrew/opt/zig@0.16` (not on `PATH` by default). Xcode needs
> `macos/GhosttyKit.xcframework` (gitignored). A fresh worktree lacks it; build it
> with 0.16 first (about 2 minutes), then run `xcodebuild`:
>
> ```sh
> PATH=/opt/homebrew/opt/zig@0.16/bin:$PATH zig build -Doptimize=Debug -Demit-macos-app=false -Demit-xcframework=true -Dxcframework-target=native
> ```
>
> Keep `-Dxcframework-target=native`. The default `universal` writes
> `macos-arm64_x86_64/`, which the verify scripts don't find. Don't copy a
> framework from another worktree; it may be stale. The Debug app also needs
> `zig-out/share` (vim, zsh, terminfo) copied or symlinked into a fresh worktree.

- **Build + launch Dev (terminal)**:
  `xcodebuild -project macos/Ghostties.xcodeproj -scheme Ghostties -configuration Debug -derivedDataPath macos/build ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`,
  then `open "macos/build/Build/Products/Debug/Ghostties Dev.app"`. From inside a
  Ghostties terminal, prefix `env -u GHOSTTIES_SESSION_ID -u GHOSTTIES_LAUNCHER`.
  Agents build and launch it for Sean; never hand him steps.
- **Xcode** is only for when it's really required (something the terminal genuinely can't do), never the default path.
- **Build (release, CLI)**:
  `xcodebuild -project macos/Ghostties.xcodeproj -scheme Ghostties -configuration Release -derivedDataPath macos/build ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`
- **Clean rebuild**: `rm -rf macos/build`, then the command above
- **Launch built app**: `open macos/build/Build/Products/Release/Ghostties.app`
- **Test (macOS app)**: the `xcodebuild test` command in [TESTING.md](TESTING.md)
- **Test (Swift package)**: `cd cli && swift test --parallel`
- **DialKit inspector** (live-tunes Dev; start it before Dev): `bash scripts/open-dialkit.sh` (starts detached, returns at once; `--foreground` for humans)
- **Browser (CEF)**: `bash scripts/download-cef.sh` — ~300MB, only needed for
  the embedded browser
- **Formatting**: `zig fmt .` · `swiftlint lint --strict --fix` · `prettier -w .`

Zig-only commands, not verified here; they need zig 0.16 on `PATH`:
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

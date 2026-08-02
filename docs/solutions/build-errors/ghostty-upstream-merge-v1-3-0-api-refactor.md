---
title: "Merging Upstream Ghostty v1.3.0 into Ghostties Fork with Workspace Sidebar"
date: 2026-03-10
category: build-errors
tags:
  - git-merge
  - swift
  - xcode
  - zig
  - conflict-resolution
  - ghostty
  - upstream-sync
severity: high
component:
  - TerminalController.swift
  - WorkspaceViewContainer
  - GhosttyPackage.swift
  - action.zig
  - GhosttyXcodebuild.zig
  - project.pbxproj
symptoms:
  - Build failures after merging 479 upstream commits
  - WorkspaceViewContainer broken due to TerminalViewContainer generic removal
  - Duplicate commandFinished method causing compile errors
  - Stale precompiled module cache errors after Sparkle update
  - Duplicate GHOSTTY_ACTION_COMMAND_FINISHED switch case (dead code)
root_cause: >
  Upstream Ghostty v1.3.0 refactored TerminalViewContainer from a generic to a
  non-generic type, breaking the fork's WorkspaceViewContainer which depended on
  the generic API. Concurrent independent additions of commandFinished in both
  upstream and the fork created duplicate symbol conflicts. Sparkle dependency
  update invalidated precompiled module cache.
---

## Problem

Merging upstream Ghostty v1.3.0 (479 commits) into the Ghostties fork broke the build in four distinct areas:

1. **`WorkspaceViewContainer.swift`** — Upstream refactored `TerminalViewContainer` from `class TerminalViewContainer<Content: View>` to a non-generic class with a `@ViewBuilder` closure init. The fork's `WorkspaceViewContainer<ViewModel>` depended on the generic API and failed to compile.
2. **`Ghostty.App.swift`** — Both upstream and the fork independently added a `commandFinished` handler. The merge produced a duplicate method and a duplicate switch case (`GHOSTTY_ACTION_COMMAND_FINISHED`).
3. **`GhosttyPackage.swift`** — The fork had left this file empty (1 line). Upstream extracted 453 lines into it from `Ghostty.App.swift`, including the `Ghostty.Notification` extension where the fork's notification names needed to live.
4. **Stale `.pcm` cache** — Upstream bumped Sparkle, invalidating precompiled module files. The first release build failed with "file has been modified since the module file was built."

## Root Cause

Upstream v1.3.0 introduced API-level changes that conflicted with fork additions:

- **Generic removal**: `TerminalViewContainer` changed from generic class to non-generic with `@ViewBuilder` closure init. Any consumer binding the type parameter broke at compile time.
- **Parallel `commandFinished` additions**: Both codebases added the same action handler independently. Git auto-merged them as separate entries, creating dead code.
- **Sparkle update**: Binary framework cache keyed to old header sizes.

## Solution Steps

### Step 1: Make WorkspaceViewContainer non-generic, init generic

Moved the generic parameter from the class to the init method, matching upstream's own pattern:

```swift
// Before (broke with upstream):
class WorkspaceViewContainer<ViewModel: TerminalViewModel>: NSView {
    private let terminalContainer: TerminalViewContainer<ViewModel>
    init(ghostty: Ghostty.App, viewModel: ViewModel, delegate: ...) {
        self.terminalContainer = TerminalViewContainer(ghostty: ghostty, viewModel: viewModel, delegate: delegate)
    }
}

// After (matches upstream pattern):
class WorkspaceViewContainer: NSView {
    private let terminalContainer: TerminalViewContainer
    init<ViewModel: TerminalViewModel>(ghostty: Ghostty.App, viewModel: ViewModel, delegate: ...) {
        self.terminalContainer = TerminalViewContainer {
            TerminalView(ghostty: ghostty, viewModel: viewModel, delegate: delegate)
        }
    }
}
```

Also removed all `WorkspaceViewContainer<TerminalController>` specializations in `TerminalController.swift` (4 call sites → plain `WorkspaceViewContainer`).

### Step 2: Merge fork notification into upstream's commandFinished

Placed the fork's `NotificationCenter.post` **above** upstream's config guard so the sidebar receives events unconditionally:

```swift
// IMPORTANT: Must remain ABOVE the config check below — the sidebar
// needs this event unconditionally, even when notifyOnCommandFinish == .never.
NotificationCenter.default.post(
    name: Notification.ghosttyCommandFinished,
    object: surfaceView,
    userInfo: ["exit_code": v.exit_code, "duration": v.duration]
)

// Upstream's config-gated notification logic follows...
guard let config = (NSApplication.shared.delegate as? AppDelegate)?.ghostty.config else { return }
```

Removed the fork's duplicate `commandFinished` method entirely.

### Step 3: Add notification names to GhosttyPackage.swift

Accepted upstream's full file, then added fork-specific names in the `Ghostty.Notification` extension:

```swift
static let ghosttyCommandFinished = Notification.Name("com.mitchellh.ghostty.commandFinished")
static let ghosttyPromptReady = Notification.Name("com.mitchellh.ghostty.promptReady")
```

### Step 4: Remove duplicate switch case

Deleted the second `GHOSTTY_ACTION_COMMAND_FINISHED` case (dead code — Swift matches first occurrence):

```swift
// Removed: duplicate case at line 648 (merge artifact)
case GHOSTTY_ACTION_COMMAND_FINISHED:  // only one instance now, at line 642
    commandFinished(app, target: target, v: action.action.command_finished)
```

### Step 5: Clean build cache

```bash
rm -rf macos/build && zig build run -Doptimize=ReleaseFast
```

## Key Decisions

| Decision | Rationale |
|---|---|
| Generic on `init`, not class | Matches upstream's own `TerminalViewContainer` pattern. Zero runtime overhead (Swift monomorphizes). Eliminates generic viral propagation to all call sites. |
| Fork notification above config guard | Sidebar needs all command completions unconditionally. Placing inside the guard would silently break sidebar for `notifyOnCommandFinish = .never` users. |
| Separate notification names | Decouples fork's subscribers from upstream internals. If upstream renames its notifications, the fork's sidebar code won't silently break. |
| Accept upstream's full GhosttyPackage.swift | Fork had an empty file; upstream extracted 453 lines into it. No fork logic existed to preserve. |

## Prevention Strategies

### For Future Upstream Merges

- **API watchlist**: Maintain a list of upstream symbols the fork wraps (`TerminalViewContainer`, `BaseTerminalController`, `SurfaceView`). Before each merge, grep upstream's changelog for those symbols.
- **Clean build unconditionally**: After any merge that bumps dependencies, always `rm -rf macos/build` before building. Stale `.pcm` files can make a broken build appear to succeed or a correct build appear to fail.
- **Search for duplicates after conflict resolution**: After resolving each file, search it for duplicate `func`, `case`, and `var` declarations. Swift compiles duplicate switch cases without error.
- **Enable warnings-as-errors in debug**: `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` would catch unreachable code (duplicate cases) at build time.

### Merge Checklist

**Pre-merge:**
- [ ] Clean working tree (`git stash` if needed)
- [ ] Create backup branch: `git branch pre-vX.Y-backup main`
- [ ] Create merge branch: `git checkout -b merge/upstream-vX.Y.Z`
- [ ] Review upstream release notes for API changes

**Conflict resolution:**
- [ ] Resolve Swift type/generic conflicts first (they cascade)
- [ ] Search each resolved file for duplicate declarations
- [ ] For `Notification.Name` files, union entries from both sides
- [ ] For empty fork files that upstream populated, accept upstream + add fork additions

**Post-merge:**
- [ ] `rm -rf macos/build` (always)
- [ ] Build with zero warnings
- [ ] Smoke test: sidebar toggle, session creation, terminal rendering
- [ ] Push to fork only (`origin`), never `upstream`

## Related Documentation

- Merge plan (local plan file, not tracked in-repo) — Full merge strategy
- [Nib window subclass titlebar hiding](../architecture/nib-window-subclass-titlebar-hiding.md) — Why `windowNibName` is forced to `"Terminal"`
- [Sidebar 3-state machine](../architecture/sidebar-3-state-machine-overlay-pattern.md) — WorkspaceViewContainer architecture
- [C union Swift interop fix](../runtime-errors/c-union-swift-interop-fallthrough-fix.md) — Relevant to `action.zig` changes
- [Safe area inset fix](../ui-bugs/safe-area-inset-blocks-terminal-card-top-constraint.md) — WorkspaceViewContainer override that must survive merges
- [Phase 1 integration](../integration-issues/ghostty-fork-workspace-sidebar-phase1.md) — Original sidebar wiring
- [Phase 2 integration](../integration-issues/ghostty-fork-workspace-sidebar-phase2.md) — Session management integration
- PR: [SeanSmithDesign/ghostties#2](https://github.com/SeanSmithDesign/ghostties/pull/2)

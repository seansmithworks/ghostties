# Upstream sync to Zig 0.16: conflict-resolution plan

Merge `upstream/main` (982fe90d9) into `sync/upstream-zig-0.16` (== main 53d9301bb). Base 1547dd667.
All 34 conflicts are mapped below. **21 TAKE-FORK · 0 TAKE-UPSTREAM · 1 TAKE-UPSTREAM-DELETE · 12 HAND-MERGE.**
There are also **8 fixes outside the conflict markers**. Without them the tree fails to compile or silently regresses (§3).

**The three riskiest files**
- **`project.pbxproj`**: the renamed project has to lose the whole iOS target and pick up Sparkle's `exactVersion 2.9.6`. It must keep every fork resource, build phase, and package. A wrong hunk breaks the Xcode build with nothing obvious to go on.
- **`UpdateViewModel.swift` + `UpdateController.swift`**: upstream rewrote the update state machine: `isIdle`→`isHidden`, `installUpdate()` removed, `Installing.isAutoUpdate`→`appcastItem`, and `cancel()` now goes through `cancelAction`. **Correction to the brief:** "keep fork" is wrong here. The fork's delta is ~30 lines of copy plus one escape hatch, and taking the fork file wholesale would not compile against upstream's `UpdateDelegate`/`UpdatePill`. The Sparkle feed lives in `UpdateDelegate.swift`, which auto-merges and keeps `ghostties.org/appcast-*.xml` (checked).
- **`AppDelegate.swift`**: keep the fork's app-wide quit modal. Upstream's new `terminate()` checks each window controller's surfaceTree and can't see background sessions held by `SessionCoordinator`, so it would kill running agents without asking.

**Stop the run, with no push, if any of these happen**
- **P0 fails.** Pristine `upstream/main` can't build GhosttyKit with `/opt/homebrew/opt/zig@0.16/bin/zig` on Xcode 27 / macOS 27 SDK without the `~/.local/zig-sdk-shim` xcrun shim. A rebuilt xcframework is the whole point of the sync.
- **Zig errors outside the known list.** `zig build` fails in a fork-only Zig hunk for any reason other than the `embedded.zig` fix in §3.A. That means the 0.16 porting surface is bigger than mapped here, so report back rather than improvising.
- **A fork seam is missing.** The count of `Ghostties fork fence` markers, or the `WorkspaceViewContainer` fall-through in `TerminalViewContainer.swift`, differs from main after the merge.
- **A fork test ID disappears.** Any test identifier in the main baseline (1341 IDs) is absent from the merged run and wasn't deleted by upstream on purpose.

Toolchain facts, verified 2026-09-25:
- `zig` on PATH is **0.15.2** (`~/.local/bin/zig`), so always call `/opt/homebrew/opt/zig@0.16/bin/zig` (0.16.0) by absolute path.
- `xcrun` already resolves to `/usr/bin/xcrun` (shim not on PATH). SDK is MacOSX27.0.
- The worktree has no `vendor/cef`. Run `bash scripts/download-cef.sh` from the worktree root before the Xcode build.

---

## 1. Conflict table

| # | File | Verdict | Rule |
|---|---|---|---|
| 1 | `.github/DISCUSSION_TEMPLATE/issue-triage.yml` | TAKE-FORK | stays deleted (`git rm`) |
| 2 | `.github/ISSUE_TEMPLATE/config.yml` | TAKE-FORK | keep fork's file (`git add`); upstream deleted its templates, fork owns its own |
| 3 | `.github/VOUCHED.td` | TAKE-FORK | stays deleted |
| 4–17 | `.github/workflows/{flatpak,milestone,nix,publish-tag,release-tag,release-tip,snap,test,update-colorschemes,vouch-check-issue,vouch-check-pr,vouch-manage-by-discussion,vouch-manage-by-issue,vouch-sync-codeowners}.yml` (14) | TAKE-FORK | stay deleted; fork CI is `ghostties-release.yml` / `test-ghostties.yml` / `clean-artifacts.yml` only (#71) |
| 18 | `.gitignore` | HAND-MERGE | union: fork block, then upstream's `/sprite_face_test*` |
| 19 | `CODEOWNERS` | TAKE-FORK | stays deleted |
| 20 | `PACKAGING.md` | TAKE-FORK | stays deleted |
| 21 | `build.zig.zon` | HAND-MERGE | end state = `upstream/main:build.zig.zon` byte-for-byte **except** `.version = "0.1.0"`. Take upstream in both hunks (wayland_protocols, iterm2_themes) **and delete the auto-merged `.utfcpp = .{ .path = "./pkg/utfcpp", ... }` line**. That line and the old wayland/themes pins are leftovers from an earlier sync; `pkg/utfcpp` doesn't exist on main. |
| 22 | `include/ghostty.h` | HAND-MERGE | keep both: `GHOSTTY_ACTION_MOVE_TAB_TO_NEW_WINDOW,` then `GHOSTTY_ACTION_PROMPT_READY,` (fork entry **last**) |
| 23 | `macos/Ghostties.xcodeproj/project.pbxproj` | HAND-MERGE | fork's rename and extras survive; every iOS-target object goes; Sparkle takes upstream's pin. Hunk-by-hunk rules in §2 |
| 24 | `macos/Ghostty.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | TAKE-FORK | stays deleted. **Load-bearing:** leaving it recreates a `macos/Ghostty.xcodeproj/` dir, and `xcodebuild` without `-project` (which `GhosttyXcodebuild.zig` relies on) then fails on two projects. Sparkle bump goes into the Ghostties project instead (§3.F) |
| 25 | `macos/Sources/App/AppDelegate.swift` (moved from `App/macOS/`) | HAND-MERGE | 3 hunks, see §2 |
| 26 | `macos/Sources/App/MainMenu.xib` (moved) | HAND-MERGE | keep both, in order: Preferences…, fork's hidden `MCP Sources…` item, upstream separator `GOd-qX-exa`, Reload Configuration |
| 27 | `macos/Sources/App/iOS/iOSApp.swift` | TAKE-UPSTREAM-DELETE | `git rm`; upstream removed the iOS app, fork's only edit was a label |
| 28 | `macos/Sources/Features/Command Palette/TerminalCommandPalette.swift` | HAND-MERGE | take upstream's `if updateViewModel.state.isInstallable { … state.confirm() }` block whole; re-apply fork copy `"Update Ghostties and Restart"` |
| 29 | `macos/Sources/Features/Terminal/BaseTerminalController.swift` | HAND-MERGE | keep both properties (`updateStateCancellable` + `clipboardConfirmationCancellable`). **Also, outside the markers:** change both fork sinks from `!newState.isIdle` to `!newState.isHidden` (in `windowDidLoad` fallback and `activateUpdateOverlayFallback()`) |
| 30 | `macos/Sources/Features/Update/UpdateController.swift` | HAND-MERGE | upstream structure wins; keep both imports (`import os`, `import SwiftUI`); signature is upstream's `func checkForUpdates()` (no `@objc`), with the fork's two `Logger(subsystem: "com.seansmithdesign.ghostties", category: "update")` lines as its first statements |
| 31 | `macos/Sources/Features/Update/UpdateViewModel.swift` | HAND-MERGE | upstream's `.installing` bodies (`appcastItem`) + fork's `.notFound(let v)` channel-aware copy. In `cancelAction`, keep upstream's `.idle: nil` and write `.permissionRequest(let request): { request.reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false)) }` with the fork comment above it |
| 32 | `macos/Sources/Ghostty/Ghostty.App.swift` | TAKE-FORK | the hunk's upstream side is empty; keep `case GHOSTTY_ACTION_PROMPT_READY: promptReady(app, target: target)` before `default:`. Separate required fix in the same file: §3.E |
| 33 | `src/apprt/action.zig` | HAND-MERGE | both hunks: upstream `move_tab_to_new_window` first, fork `prompt_ready` (with its doc comment) **last**, in both the union and `Key` enum. Order must match ghostty.h (`checkGhosttyHEnum` test enforces) |
| 34 | `src/build/GhosttyXcodebuild.zig` | HAND-MERGE | `const env = b.graph.environ_map;` (upstream, required by 0.16) + `const app_path = b.fmt("macos/build/{s}/Ghostties.app", …)` (fork) |

## 2. Hunk detail for the hard files

**project.pbxproj**: 7 hunks. Trial-merge line numbers are approximate:
- **~L19**: resolve to nothing. Drop upstream's `A553F4142E06EB1600257779 Ghostty.icon in Resources`, which the fork removed.
- **~L105**: keep only `A5B3053D… Ghostties.entitlements`. Drop the `A5D4499D… Ghostty-iOS.app` file ref.
- **~L240**: keep only `A5B30531… Ghostties Dev.app`. Drop `Ghostty-iOS.app`.
- **~L423**: keep only `A5B30530… Ghostties`. Drop the `Ghostty-iOS` target.
- **~L487**: drop the whole fork side (`A5D4499B… Resources` phase, iOS).
- **~L1246**: drop the whole fork side (`A5D449A8/A9/AA` iOS build configs).
- **~L1437**: take upstream: `kind = exactVersion; version = 2.9.6;`.
- **Auto-merged, already correct, don't touch:** bridging header path `Sources/App/ghostty-bridging-header.h` ×3; DockTilePlugin exceptions (`OSPasteboard+Extension.swift` added, `CrossKit.swift` gone); macOS-target exceptions reduced to `DockTilePlugin.swift`.
- **Afterwards:** `grep -c "A5D449\|A53D0C95\|Ghostty-iOS" project.pbxproj` must be 0, and `plutil -lint` must pass.

**AppDelegate.swift**: 3 hunks:
- **`applicationShouldTerminate`**: TAKE-FORK. Keep the fork's `NSAlert` "Quit Ghostties?" modal, and don't call `terminate()`.
- **`application(_:openFile:)`**: keep both. Put upstream's `if commandLineOpenFileFilter.shouldIgnore(filename) { …; return true }` first, closed with `}`. Then the fork's `_Concurrency.Task { @MainActor in _ = ClaudeStateStore.shared` (the shared `}` after the markers closes it).
- **End of file**: keep both extensions. First the fork's `MXMetricManagerSubscriber` extension, closed with `        }\n    }\n}` plus a blank line. Then upstream's `// MARK: - Termination Flow` extension (the shared tail `}}}` closes it).
  - Keep upstream's `terminate()` as unused code to keep the file close to upstream.
  - Change its two bare `Task {` to `_Concurrency.Task {` (see §3.D).

## 3. Required fixes outside the conflict markers (apply after the merge commit, one commit each)

- **A. Zig 0.16 port, `src/apprt/embedded.zig`:** `env.remove("CLAUDECODE");` → `_ = env.orderedRemove("CLAUDECODE");`. `env` is now `std.process.Environ.Map`; the neighbouring upstream lines already use `orderedRemove`. This is the only fork Zig hunk that needs an API change.
- **B. `macos/Sources/Features/Ghostties/SessionComposerPalette.swift:1459`:** `OSColor(` → `NSColor(`. Upstream deleted `CrossKit.swift` (`OSColor`/`OSView`/`OSSize`/`OSPasteboard`/`OSViewRepresentable`). This is the only fork-only use.
- **C. Stale-xcframework stubs from the 2026-05 sync: restore upstream code.** Each carries a "Ghostties NOTE (upstream sync 2026-05)" saying to restore it once the xcframework is rebuilt; this sync rebuilds it. Take upstream's version of each block:
  - `Ghostty.App.swift`: un-comment `case GHOSTTY_ACTION_SET_TAB_TITLE: return setTabTitle(…)` and delete the NOTE.
  - `AppDelegate.swift` local key monitor: restore `if let app = ghostty.app, let config = ghostty.config.config` + `if !ghostty_config_key_is_binding(config, ghosttyEvent) { return false }`.
  - `Ghostty.Surface.swift`: restore `foregroundPID` (`ghostty_surface_foreground_pid`) and `ttyName` (`ghostty_surface_tty_name`) bodies.
- **D. `GhosttiesCore.Task` hides Swift's `Task` in upstream code.** Only `AppDelegate.swift` and `TerminalController.swift` `import GhosttiesCore`. Qualify every bare `Task {` there as `_Concurrency.Task {`: AppDelegate ×2 (termination extension) and TerminalController ×1 (the upstream close-all-windows review block). Precedent: a2a28870b.
- **E. `Ghostty.App.swift`:** covered by C. There's nothing else to adopt from the ghostty.h C API changes: upstream's own Swift already handles the new clipboard callbacks and `ghostty_surface_complete_clipboard_request`. Fork-only code calls only `ghostty_surface_set_focus` and the two action tags (grep-verified).
- **F. Sparkle 2.9.6:** run `xcodebuild -resolvePackageDependencies -project macos/Ghostties.xcodeproj -scheme Ghostties`. Confirm `macos/Ghostties.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` pins Sparkle `2.9.6` / `ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a`. Don't hand-edit `originHash`.
- **G. Fork CI:**
  - In `.github/workflows/ghostties-release.yml` (L154) and `test-ghostties.yml` (L92): `version: 0.15.2` → `0.16.0`.
  - Update the "Install Zig 0.15.2" comments to match.
  - Leave the Xcode 26.3 selection and the `macos-15` runner alone in this sync. Dropping them is a follow-up once branch CI is green (add to BACKLOG).
- **H. `.github/scripts/check-apple-libghostty-vt.nu`** (new upstream file, used only by upstream's deleted `test.yml`): `git rm`, following the fork's no-upstream-CI stance.

The fork's Zig porting surface: of the 11 fork hunks, only A needs a change. The rest compile under 0.16 unchanged; the APIs they use (`std.mem.startsWith`, `std.ascii.isAlphanumeric`, `performAction`, `surfaceMessageWriter`, `Log.create`, the `.end_prompt_start_input*` tags) all appear in upstream's 0.16 code:

| Hunk | 0.16 change? |
|---|---|
| `include/ghostty.h` +PROMPT_READY | no (C). Ordering only, see #22 |
| `pkg/macos/os/log.zig`, `signpost.zig`: bundle-id strings in tests | no |
| `src/Surface.zig`: `.prompt_ready` arm, same shape as upstream's `.command_finished` | no |
| `src/apprt/action.zig` / `apprt/surface.zig`: `prompt_ready` members | no |
| `src/apprt/embedded.zig`: remove `CLAUDECODE` env | **yes, fix A** |
| `src/build/Config.zig`: SemVer pre-release tag check (auto-merged) | no |
| `src/build/GhosttyXcodebuild.zig`: Ghostties target/scheme/app path | yes, but already covered by the conflict resolution (`b.graph.environ_map`) |
| `src/build_config.zig`: bundle id | no |
| `src/termio/stream_handler.zig`: OSC 133;B → `.prompt_ready` | no |

## 4. Execution sequence (worktree `.claude/worktrees/upstream-sync`, plain single-purpose commands)

1. **Check the start state:** `git status` is clean, `git rev-parse HEAD` = 53d9301bb, and branch = `sync/upstream-zig-0.16`.
2. **Start the merge:** `git merge --no-ff --no-commit upstream/main`. Expect exactly the 34 conflicts in §1.
3. **Modify/delete batch:**
   - `git rm` rows 1, 3–17, 19, 20, 24, and 27.
   - `git add .github/ISSUE_TEMPLATE/config.yml`.
   - Confirm `macos/Ghostty.xcodeproj` no longer exists on disk.
4. **Content hunks:** resolve rows 18, 21, 22, 33, 34 (Zig/C/config), then 23, 25, 26, 28–32 (macOS). Follow §1/§2 and `git add` each file.
5. **Pre-commit gates:**
   - `git grep -n '^<<<<<<<\|^>>>>>>>' -- .` is empty.
   - `plutil -lint macos/Ghostties.xcodeproj/project.pbxproj` passes.
   - `git diff upstream/main -- build.zig.zon` shows only the `.version` line.
6. **Commit the merge:** `Merge upstream/main (Zig 0.16) into Ghostties`, with the verdict counts in the body. Conflict resolutions only.
7. **Fixes:** apply §3 A–H as separate commits, in order A, B, C, D, F, G, H.
8. **Build GhosttyKit:** `/opt/homebrew/opt/zig@0.16/bin/zig build -Demit-macos-app=false -Doptimize=ReleaseFast` (same flags as CI).
9. **Zig header-sync test:** `/opt/homebrew/opt/zig@0.16/bin/zig build test -Dtest-filter="ghostty.h"`. Proves ghostty.h and action.zig are in the same order.
10. **CEF:** `bash scripts/download-cef.sh`.
11. **Xcode Debug build:** `xcodebuild -project macos/Ghostties.xcodeproj -scheme Ghostties -configuration Debug -derivedDataPath .build-verify ONLY_ACTIVE_ARCH=YES ARCHS=arm64 build`.
12. **Test suite:** `xcodebuild test … -only-testing:GhosttyTests -resultBundlePath .build-verify/merge.xcresult`, same pins. Count with `xcrun xcresulttool get test-results summary`. Record `defaults read -g AppleInterfaceStyle`.
13. **Hand to P5 review.** Push to `origin` only, with no PR, merge, or tag.

## 5. Verification

- **Fork Zig delta equals the mapped list:** `git diff upstream/main HEAD --name-only -- src pkg include build.zig build.zig.zon` lists exactly the 11 files in §3's table plus `build.zig.zon`.
- **Fork Swift delta survived:** `git diff upstream/main HEAD --name-only -- macos/Sources ':!macos/Sources/Features/Ghostties'` matches the pre-merge list from `git diff 1547dd667 main --name-only -- macos/Sources`. Map paths `App/macOS/` → `App/`, and drop `iOSApp.swift`.
- **Seams intact:** `git grep -c "Ghostties fork fence"` matches main per file. Check `TerminalViewContainer.terminalViewContainer` falls through to `WorkspaceViewContainer`, `TerminalWindow.awakeFromNib` still attaches the `.unified` NSToolbar, and `UpdateDelegate.feedURLString` returns `ghostties.org/appcast-{beta,stable}.xml`.
- **No stale stubs left:** `git grep -n "Ghostties NOTE (upstream sync 2026-05)"` returns nothing.
- **Build products:** step 8 produces `macos/GhosttyKit.xcframework` with a `macos-arm64*` slice. Step 11 builds `Ghostties Dev.app`, which contains `Contents/Resources/ghostty/themes`, `terminfo`, `shell-integration` (via `embed-ghostty-resources.sh`) and the CEF framework.
- **Test identifiers:** every ID in the main baseline (1341) is present. New upstream tests add IDs:
  - Expect upstream's `CommandLineOpenFileFilterTests`, `CommandPaletteTests`, `UntrustedURLTests`, `URLTests` and others.
  - Prove coverage by diffing identifier sets, never totals.
  - An upstream test that fails only on fork copy ("Ghostties", channel-aware not-found text) gets its expectation changed to the fork copy. Nothing else in it changes.
- **Sean's hands-on pass (agents can capture the screen but must never send keystrokes):**
  - Switching sessions in the sidebar works.
  - The prompt-ready / idle glyph updates after a command.
  - Quitting with a running background session shows "Quit Ghostties?".
  - An OSC 52 read from a background session waits and shows its sheet only when that session is focused (upstream's new per-controller `$surfaceTree` clipboard flow).
  - Check for Updates shows the pill and the not-found copy.
  - Traffic lights stay aligned.

<details><summary>Backing: symbols and risks checked, clean or not in scope</summary>

- **Checked clean:** 70 Swift declarations and 30 signatures that upstream removed or changed, grepped across the 181 fork-added files. The only hit is `OSColor` (fix B). `HostingWindow`, `AnySortKey`, `installUpdate`, `isInstalling`, `confirmClipboard*`, `makeOSView`, and `BackportNSGlassStyle` have no fork callers.
- **No type-name collisions:** upstream's new types (`UntrustedURL`, `ClipboardConfirmationRequest`, `CommandLineOpenFileFilter`, …) don't clash with fork types. `Identity` is nested on both sides.
- **Synchronized folders:** `macos/Sources` and `macos/Tests` are `PBXFileSystemSynchronizedRootGroup`s, so the 6 new upstream source files and 10 new test files join the Ghostties target automatically. No pbxproj file-ref mirroring needed.
- **Renamed fork files:** `images/Ghostty.icon/icon.json` (upstream +5 lines) merged into `images/Ghostties.icon/` cleanly. Upstream didn't touch `Ghostty-Info.plist`, the entitlements, or the scheme.
- **Pre-existing, not in scope (flag only):**
  - The update release-notes links still point at `ghostty.org` / `ghostty-org/ghostty`.
  - Close-window confirmation only checks the active session tree, not background ones. Both were true before this merge.
</details>

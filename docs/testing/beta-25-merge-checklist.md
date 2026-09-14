# Beta 25 Merge Checklist (manual)

For Sean's hand-test of the merged build. Each item: check the box, then jot a note.
The automated suite runs separately overnight — this file is manual-only.

## Before you start

Quit any running "Ghostties Dev" build first — from the app itself (Cmd+Q), never
`killall`/`pkill` (can hit `com.mitchellh.ghostty`, the daily-driver build).

Build the merged main:

```
xcodebuild build-for-testing \
  -project macos/Ghostties.xcodeproj \
  -scheme Ghostties \
  -destination 'platform=macOS,arch=arm64' \
  ONLY_ACTIVE_ARCH=YES ARCHS=arm64 \
  -derivedDataPath macos/build
```

Launch it:

```
open "macos/build/Build/Products/Debug/Ghostties Dev.app"
```

Confirm you're running the fresh build, not a stale one from a sibling worktree:

```
lsappinfo info -only executablepath -app com.seansmithdesign.ghostties.dev
```

## Sidebar (#175)

- [ ] Compare a session's section placement in session view vs. project view (Pinned when non-empty or during a drag / Active / Inactive / Archive) → same session sits in the same bucket in both views; project view's Archive header matches session view's (chevron leading, same weight)
  Notes:

- [ ] Drag a row onto an empty Pinned section → "Drop to pin" zone appears during the drag; drop pins the session
  Notes:

- [ ] Drag a row within a section → a one-row gap opens at the insertion point, before/after decided by which half of the target row the pointer is over
  Notes:

- [ ] Start a drag, release over empty space outside any drop zone → the drag reverts, no reorder happens
  Notes:

- [ ] Drag near the sidebar's top/bottom edge → the list auto-scrolls, and it feels row-stepped, not jumpy
  Notes:

- [ ] Drag a row onto Active → the session relaunches (resuming where possible) and holds its Active slot until alive or a 5s timeout; stopping the session during the hold ends it immediately with no stale hold left behind
  Notes:

- [ ] Start Claude from a shell opened after `cco`, send one prompt, Stop the session, right-click it → "Resume" and "Start Fresh" both appear; Resume reopens the same conversation. A session with no saved conversation shows only "Start Fresh"
  Notes:

- [ ] Right-click that same stopped session → Start Fresh → relaunches with a new conversation
  Notes:

- [ ] Right-click a Codex session, approve the Ghostties hook in Codex once → before approval, row shows "Approve the Ghostties hook in Codex"; after approval, Resume works
  Notes:

- [ ] Check all five slot states render → spinner (working, drawn as a dot grid — should not read as two faint dots), `?` (needs input), `✓` (idle/waiting), `✕` (error), empty (stopped)
  Notes:

- [ ] Turn on VoiceOver and focus each status glyph → each reads its status word (working / needs your input / idle / error / stopped)
  Notes:

- [ ] Turn on Reduce Motion → the working state shows a static "…" instead of the spinner
  Notes:

## Composer (#169)

- [ ] Open a new composer → single-line opens by default
  Notes:

- [ ] Type a known repo at ghost size 30 → coloured ghost appears; before it resolves, the gray placeholder has no mesh lines
  Notes:

- [ ] Tab into a different repo → ghost dissolves into the new ghost, then hops
  Notes:

- [ ] Type an unknown branch → ghost dissolves, then shakes
  Notes:

- [ ] Launch a session → the launch dissolve plays fully, not visibly cut off
  Notes:

- [ ] Click into the field; try with caps lock on and while dictating → no cursor-accessory bubble in any case
  Notes:

- [ ] Check the card in light and dark appearance → matches your reference look for the card; reads as glass in both
  Notes:

- [ ] Watch the idle ghost → floats gently, up/down and side-to-side
  Notes:

- [ ] Enable Reduce Motion → no float, instant ghost swaps, composer still usable
  Notes:

- [ ] Open the sidebar "+ New Session" popover; compare side by side against the installed Release app at `/Applications/Ghostties.app` → results list opens and works
  Notes:

- [ ] Click "add project" from the sidebar header → opens the single-line composer locked to that project
  Notes:

- [ ] On this Dev build, open the Composer Tuning panel → style list offers only Single line and Zero chrome (zero chrome still selectable); Copy puts JSON on the clipboard; Reset single-line works
  Notes:

## Demo rig (#177)

- [ ] Look at the chosen agent's answer in the produced capture → its answer is on screen, not a login banner, a dialog, or a "thinking" frame
  Notes:

- [ ] Scan for identity leaks in the capture → no home path, username, hostname, email (GitHub noreply addresses included), GitHub handle, or old org name anywhere in frame
  Notes:

- [ ] Check which repos/ghosts appear in the capture → only the 7 fixture repos, no dev badge, sidebar at the top, no Pac-Man silhouettes
  Notes:

- [ ] If #175 shipped in this build, check the status glyphs in frame → they're states you accept
  Notes:

## Known broken (expected)

- The demo capture tests still click "Relaunch" — #175 renamed that to Resume/Start Fresh, so the capture script's click target no longer exists.
- On #175, sessions restored from disk land in the collapsed Archive section, so their rows aren't rendered for the capture to find.

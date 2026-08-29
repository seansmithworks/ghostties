# Changelog

All notable changes to Ghostties are documented here. Ghostties is a macOS terminal app built on top of [Ghostty](https://ghostty.org) that adds a multi-agent workspace sidebar.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions are pre-release betas until v0.1.0 stable.

---

## [0.1.0-beta.24] — Unreleased

The session composer's field row gets trailing project/branch controls in place of the old resolution line, template pinning, and an experimental ghost-text autocomplete field you can opt into.

### Added

- **Pin templates in the composer.** Right-click a template row for Pin/Unpin — pinned templates stay at the top of the list, ahead of your recents.
- **An "Add project…" row** where the composer used to just say "No matches" if you have no projects yet.
- **Experimental ghost-text composer field**, opt-in from View → Experimental Composer Field (off by default). As you type a session name, it previews the full destination — project, branch, template — as greyed-out ghost text, and Tab accepts one segment at a time instead of committing the whole thing at once.
- **Typing `>` to target any branch in the repo now works**, not just branches that already have a worktree — Ghostties offers to create one on the spot if it doesn't.

### Changed

- **The composer field row drops its resolution-line text** in favor of two small trailing buttons — a chevron for the project picker, a branch glyph for the branch picker — shown inline instead of underneath the field.
- **Template rows in the composer are single-line now**, with the pin glyph or "recent" label trailing instead of a subtitle underneath.

### Fixed

- **The composer's results list no longer opens with dead space below a short list**, and stops growing past its cap on a long one.
- **The composer card now resizes cleanly to fit its content at every window width**, instead of clipping or leaving extra space.

---

## [0.1.0-beta.23] — 2026-08-17

A small fix release: idle Claude Code sessions stop reading as if they need you, and sidebar session names stay in sync.

### Fixed

- **Idle Claude Code sessions no longer show up as needing your attention.** Claude Code's terminal never emits the shell-prompt marker Ghostties used to detect "waiting for input," so every session went quiet and immediately looked like it needed you. Silence with no other evidence now reads as idle for agent sessions; plain shell sessions are unaffected.
- **Session names fully shed the leading status glyph.** A prior fix stripped it from new names, but a title shaped like "repo | ✳ Claude Code" — the actual production shape — could still leak the glyph in the second segment, and already-stored names with a glyph baked in weren't cleaned up. Both are fixed now, including self-healing existing names on their next sync.
- **The Sessions tab shows a session's current name and status without needing a tab toggle first.** Renaming or a terminal title change could sit stale on screen until you switched away and back.
- **Guarded against a rare case where a window's terminal or browser shadow could disappear.** Unverified against a live repro, but a code-level gap (shadow path rebuilding from empty bounds) is now closed defensively.

---

## [0.1.0-beta.22] — 2026-08-09

The Sessions tab gets a real Inactive zone, session keyboard shortcuts, and a titlebar fix that finally sticks.

### Added

- **Active, Inactive, and Archive zones in the Sessions tab.** A session you've stopped now lands in its own Inactive zone instead of Archive, so "still running," "stopped this launch," and "from a while ago" read as three different things instead of one crowded list.
- **Keyboard navigation for sessions.** `Cmd+T` opens a new session, `Cmd+W` closes the current one (confirming first if it's still active, and closing the window if nothing's left running), and `Cmd+1` through `Cmd+9` jump straight to a session by its position in the sidebar.
- **A built-in Codex template** alongside Shell and Claude Code in the New Session picker.
- **Terminal install options.** Install without the DMG: `brew install --cask seansmithworks/tap/ghostties` or `npx ghostties-install`.

### Changed

- **One "+ New" button per tab.** Projects and Sessions each get a single labelled button for starting something new, replacing the old icon-only button and full-width row.
- **The overlay sidebar floats like the others now.** In overlay/hover mode the terminal card had lost its inset, rounded corners, and shadow; it now matches the pinned and closed modes.
- **Tasks removed from the Sidebar View menu.** Projects and Sessions remain.
- **The session context menu's "Remove" is now "Delete."** It permanently deletes the session with no undo — the old label read like it moved the session to Archive instead.

### Fixed

- **The window titlebar now matches your actual terminal theme.** It was drawing from a fixed color instead of your theme's real background, so it could look mismatched against the terminal below it. It now always tracks the same background your terminal renders.
- **`Cmd+Shift+[` and `Cmd+Shift+]` cycle sessions in the order you actually see them** when the Sessions tab is open, instead of the Projects tab's order.
- **Stopped sessions land in Inactive instead of vanishing.** They were being swept straight into Archive as soon as they stopped.
- **Stopping one session no longer disturbs other running sessions.** A stale internal cache could hold back status updates for sessions that were still running, whenever a different session had just stopped.
- **Archive stays collapsed when there's nothing active**, instead of forcing itself back open every time you close it.
- **Archive sorts by when a session was last active**, not by the order it happened to be added.
- **Session names no longer echo just the repo name plus boilerplate** — a title like "my-project | Claude Code" duplicating the row's own subtitle.
- **Session names no longer flicker through spinner characters, bare directory names, or truncated paths.** Claude Code's terminal title changes rapidly while it's working; Ghostties now filters those out and keeps only genuinely informative titles.
- **Pressing Esc while renaming a session reverts it**, instead of committing whatever you'd typed so far.
- **The sidebar re-clamps its width correctly when you shrink the window**, so it can no longer end up wider than the window itself.
- **Next Project and Previous Project grey out in the menu when there's nothing to cycle to**, instead of sitting there as if they'd do something.

---

## [0.1.0-beta.21] — 2026-08-01

The Sessions tab gets its own character, names that keep themselves current, and a round of security hardening.

### Added

- **Session names that keep themselves current.** A session's name in the sidebar now follows the title Claude Code sets, so a row tells you what that agent is actually working on instead of showing a generic label. Rename a session yourself and your name wins — Ghostties stops syncing that one. Right-click and choose **Sync name automatically** to hand it back.
- **A ghost for every session.** Each session in the Sessions tab now has its own ghost character, tinted by status, in place of the plain dot. A session keeps its ghost across relaunches.
- **Collapsible Active and Archive sections.** The Sessions tab splits into Active and Archive, and each one folds away. Ghostties remembers which you left open.

### Changed

- **The Sessions list holds still.** Rows used to reshuffle themselves by most recent activity, so the list rearranged under you while you were reading it. Order is now stable.
- **Status colors across the sidebar.** Green means working, blue means your turn, gold means a decision is waiting, orange means long-running, red means something went wrong.

### Fixed

- **`Cmd+Shift+[` and `Cmd+Shift+]` cycle sessions again.** The shortcut only worked when focus was outside the terminal — which is almost never, in practice. The terminal was claiming the key combination for its own tab switching before the menu ever saw it.

### Security

- **Updated Sparkle to 2.9.4**, which fixes two vulnerabilities in the update framework (CVE-2026-47121 and CVE-2026-47122).
- **MCP server discovery now reads only your own configuration.** Ghostties also used to look for MCP configuration inside the project folder you opened, so opening someone else's repository could offer to launch a program that repository shipped. It now reads from `~/.ghostties/` only.
- **Narrowed what the app is permitted to do.** The shipping build no longer requests two hardened-runtime exceptions it never needed.
- **Session launcher scripts are cleaned up** when a session ends, and anything left behind for more than a day is swept away at launch.
- **Fixed a path-handling flaw in `gt done`** that let a crafted task name reach files outside the task directory.

---

## [0.1.0-beta.20] — 2026-07-20

Quality-of-life improvements to the workspace sidebar — resize it, rename sessions in place, and jump between live agents from the keyboard.

### Added

- **Drag to resize the sidebar.** Grab the sidebar's trailing edge and drag to make it wider or narrower. Ghostties remembers your width separately for the Sessions and Tasks views, so each stays how you left it.
- **Rename, stop, and relaunch sessions from the Sessions tab.** Right-click any row in the Sessions tab for a menu matching the project view — Rename, Stop, Relaunch, Remove. Renaming happens inline, right on the row.
- **Cycle through live agents from the keyboard.** `Cmd+Shift+]` / `Cmd+Shift+[` now step through your running sessions in sidebar order (or through task zones in Tasks view). Project cycling moved to `Cmd+Ctrl+]` / `Cmd+Ctrl+[`.

### Changed

- **The Sessions list trims itself at launch.** It used to keep every agent session you ever started. It now keeps everything from the last 30 days plus each project's 15 most recent, so the list stays tidy without touching any of your actual work.

---

## [0.1.0-beta.19] — 2026-07-05

The workspace stays responsive when several agents are running at once.

### Fixed

- **Running multiple agents no longer pins the CPU.** With a few Claude Code sessions streaming at the same time, the workspace could peg a core and beachball the app until you force-quit it. The sidebar was rebuilding itself on every terminal-title change — many times a second, per session — and redoing that work for every project row whether or not anything had actually changed. Activity updates are now throttled, and the sidebar only redraws the rows that changed. The app keeps up under real multi-agent load.

### Performance

- Task list reloads incrementally — only the task files that changed are re-read, instead of re-parsing every task on any file-system event.

---

## [0.1.0-beta.18] — 2026-06-19

The first build delivered to existing users over the air — it confirms auto-updates work end to end. No other changes from beta.17.

---

## [0.1.0-beta.17] — 2026-06-19

Auto-updates work now, and the workspace sidebar no longer freezes the app.

### Fixed

- **Auto-updates now work.** "Check for Updates" was silently doing nothing in beta.16 — a permission-request wedge stalled Sparkle, and the in-app update notification never rendered in the workspace window. Ghostties now checks for updates in the background and shows a notification pill when a new version is ready. *One catch: because the updater itself was broken in beta.16 and earlier, you'll need to install this build manually — but updates after this one will arrive on their own.*
- **Sidebar no longer freezes the app.** Opening the project sidebar could peg the CPU and beachball the window. Fixed.

---

## [0.1.0-beta.16] — 2026-05-18

The tasks sidebar is now fully wired up, with six status zones, Linear preset support, and a complete `gt` CLI.

### Added

- **Six-zone task sidebar** — Inbox, Backlog, Running, Needs You, Review, and Graveyard lanes are all live. Done tasks no longer appear in Inbox.
- **Linear Sync preset** — a "Linear Sync" template in the New Session picker pre-configures the MCP server with your Linear workspace. Source dots show indigo for Linear-sourced tasks, sage for shell tasks.
- **`set_task_fields` MCP tool** — agents can write back worktree path, PR URL, branch name, and PR state directly into task files.
- **Sessions tab** — sidebar now has a recents tab showing recent terminal sessions alongside tasks.
- **New Session template picker** — flyout menu now shows available agent templates when starting a new session.
- **Sidebar View submenu** — Sessions/Projects toggle moved to the View menu and grouped with other sidebar layout options.
- **Wordmark animation** — assembly/erosion loop for empty terminal panes. Off by default; opt in with `defaults write com.seansmithdesign.ghostties ghostties.emptyStatePhysics.wordmark -bool true`.
- **`gt smoke`** — new subcommand for automated task-state verification.
- **Claude Code template default** — new sessions default to the Claude Code agent template.
- **`install-gt.sh`** — installer script for the `gt` CLI with PATH setup guidance.

### Fixed

- **"Check for Updates" visibility** — progress and result messages now appear correctly in hidden-titlebar and tabbed windows (previously only showed in standard windows).
- **Auto-update channel** — channel is now user-controllable via `defaults write com.seansmithdesign.ghostties ghostties.autoUpdateChannel beta` (or `stable` / `tip`). Previously hardcoded.
- **`gt done` speed** — done command is noticeably faster with cleaner progress output.

### Performance

- Suppressed 1Hz sidebar re-render when session states haven't changed — reduces CPU overhead while Claude is running.

---

## [0.1.0-beta.15] — 2026-05-05

Polish and stability fixes following the beta.14 smoke test.

### Fixed

- Dark mode titlebar now matches the canvas background color (previously showed a mismatched gray)
- Fullscreen icon position in the toolbar corrected
- Canvas corner radius is now consistent on all four corners
- Shadow depth between the browser panel and terminal panel is now consistent
- Sparkle update-available toast is no longer shown in release builds (debug-only now)

### Quality

- All upstream Ghostty tests pass — full test suite is green

---

## [0.1.0-beta.14] — 2026-04-30

First beta with a production-quality icon and an onboarding experience on first launch.

### Added

- New production app icon
- Debug builds use a distinct blueprint-style icon so it's easy to tell Dev from Release at a glance
- Onboarding sheet appears on first launch — includes welcome copy, links to send feedback, and a version footer
- Tasks panel now shows a "preview" callout card instead of an inline alert
- Honest placeholder copy in places that aren't fully wired up yet

### Changed

- Fresh installs now default to showing the project sidebar first (previously opened to an empty state)

---

## [0.1.0-beta.13] — 2026-04-30

Window controls alignment and the first version of task row interaction.

### Fixed

- Traffic light buttons (close / minimize / zoom) are now correctly centered in the titlebar — previously they floated slightly off

### Added

- Sidebar row-click v0 — clicking a task row now lets you interact with it

---

## [0.1.0-beta.12] — 2026-04-28

First distributable build. Ghostties can now be installed and kept up to date automatically.

### Added

- First full DMG bundle with notarization — Ghostties is now installable like any other Mac app
- Sparkle auto-update wired to ghostties.org — the app will notify you when a new beta is available
- Row-click interaction across the task list (12 interaction units shipped)
- Privacy and support pages live at ghostties.org

---

[0.1.0-beta.19]: https://github.com/SeanSmithWorks/ghostties/releases/tag/v0.1.0-beta.19
[0.1.0-beta.18]: https://github.com/SeanSmithWorks/ghostties/releases/tag/v0.1.0-beta.18
[0.1.0-beta.17]: https://github.com/SeanSmithWorks/ghostties/releases/tag/v0.1.0-beta.17
[0.1.0-beta.16]: https://github.com/SeanSmithWorks/ghostties/releases/tag/v0.1.0-beta.16
[0.1.0-beta.15]: https://github.com/SeanSmithWorks/ghostties/releases/tag/v0.1.0-beta.15
[0.1.0-beta.14]: https://github.com/SeanSmithWorks/ghostties/releases/tag/v0.1.0-beta.14
[0.1.0-beta.13]: https://github.com/SeanSmithWorks/ghostties/releases/tag/v0.1.0-beta.13
[0.1.0-beta.12]: https://github.com/SeanSmithWorks/ghostties/releases/tag/v0.1.0-beta.12

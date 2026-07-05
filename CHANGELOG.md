# Changelog

All notable changes to Ghostties are documented here. Ghostties is a macOS terminal app built on top of [Ghostty](https://ghostty.org) that adds a multi-agent workspace sidebar.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions are pre-release betas until v0.1.0 stable.

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

[0.1.0-beta.19]: https://github.com/SeanSmithDesign/ghostties/releases/tag/v0.1.0-beta.19
[0.1.0-beta.18]: https://github.com/SeanSmithDesign/ghostties/releases/tag/v0.1.0-beta.18
[0.1.0-beta.17]: https://github.com/SeanSmithDesign/ghostties/releases/tag/v0.1.0-beta.17
[0.1.0-beta.16]: https://github.com/SeanSmithDesign/ghostties/releases/tag/v0.1.0-beta.16
[0.1.0-beta.15]: https://github.com/SeanSmithDesign/ghostties/releases/tag/v0.1.0-beta.15
[0.1.0-beta.14]: https://github.com/SeanSmithDesign/ghostties/releases/tag/v0.1.0-beta.14
[0.1.0-beta.13]: https://github.com/SeanSmithDesign/ghostties/releases/tag/v0.1.0-beta.13
[0.1.0-beta.12]: https://github.com/SeanSmithDesign/ghostties/releases/tag/v0.1.0-beta.12

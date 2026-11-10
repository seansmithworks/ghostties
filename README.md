# Ghostties

**Run all your coding agents in one window.**

Ghostties is a macOS fork of [Ghostty](https://github.com/ghostty-org/ghostty) with a sidebar for your agent sessions.

![The Ghostties window: a project sidebar on the left with sessions marked needs you, working and done, and a Claude Code session running in the terminal on the right.](.github/assets/product-hero.png)

> **Pre-1.0.** Active development, ships as a beta. Things move, and occasionally break.

## The problem

Running one coding agent is fine. Running five is a mess of terminal windows where you can't tell which one is working, which one is waiting on you, and which one finished twenty minutes ago while you were looking somewhere else.

Ghostties puts them in one window, grouped by project, and shows you what each one is doing.

![A recording of Ghostties: a list of sessions in the sidebar, which then collapses to a narrow strip of icons while Claude Code works through a flaky test in the terminal.](.github/assets/demo.gif)

## What it adds

Ghostty's terminal, with a workspace layer on top.

- **A project sidebar.** Sessions grouped by project. Projects show their real icons. The sidebar can collapse to a narrow strip of icons.
- **Status at a glance.** Each session shows whether its agent is working, needs you, is done, or hit an error. This works for Claude Code and Codex.
- **Approve or deny from the sidebar.** When Claude Code asks permission to run something, answer from the session's row. Codex sessions get status only.
- **A window that follows your theme.** Set any theme other than the default and the sidebar, the area around the terminal, and the toolbar take their colors from it. Ghostties Light and Ghostties Dark are the default.
- **An embedded browser.** The thing you're building, next to the thing building it.

Everything else is Ghostty: the terminal, the renderer, fonts, keybindings, shell integration. Ghostties reads your existing Ghostty config (`~/.config/ghostty/config`) and doesn't edit it. Two defaults differ from Ghostty's: the Ghostties theme and 20pt of window padding. Anything you set in your config overrides both. A theme you pick inside the app overrides the `theme =` line in your config until you clear that pick in the app.

### Build from source: `gt` and an MCP server

The repo also has `gt`, a CLI for creating and moving task files from inside an agent session, and an MCP server so agents can read and update the same list. Neither ships in the Homebrew cask or the DMG. You build them from source. See [cli/README.md](cli/README.md).

## Install

With Homebrew:

```sh
brew install --cask seansmithworks/tap/ghostties
```

Or run `npx ghostties-install`, or download the latest `.dmg` from [Releases](https://github.com/SeanSmithWorks/ghostties/releases) and drag it to Applications.

The app checks for updates on its own, whichever way you installed it. Homebrew knows this, so `brew upgrade` skips it.

Requires **macOS 13 or later on Apple Silicon**. There's no Intel build and no Linux build.

### First launch

macOS may ask for access to Desktop, Documents, iCloud Drive or other folders. Those prompts come from commands running inside the terminal (an agent, `ls`, `git`), not from Ghostties itself. Allow only the folders you actually work in. You can change any of them later in System Settings, under Privacy & Security, then Files and Folders. Full Disk Access also silences the prompts, but it's broad, and this is a beta. I'd leave it off unless the prompts get in your way.

## Uninstall

Homebrew:

```sh
brew uninstall --cask ghostties
```

Add `--zap` to also delete Ghostties' preferences, caches, saved state and Application Support folder. It doesn't touch `~/.config/ghostty/config` or the separate Ghostty app.

DMG or `npx` install: quit Ghostties and drag it from Applications to the Trash.

Neither removes the status hooks Ghostties added for your agents. Delete these by hand if you want them gone:

- In `~/.claude/settings.json`, the entries under `hooks` whose command runs `ghostties-status.sh`.
- In `~/.codex/hooks.json`, the same entries (only present if you launched a Codex session).
- The folder `~/.ghostties`, which holds that script, your presets, session state and caches.

The hook entries are harmless if left. They skip silently when the script is gone, so deleting `~/.ghostties` won't cause errors.

## Its relationship to Ghostty

Ghostties is a fork of [Ghostty](https://github.com/ghostty-org/ghostty), the terminal emulator built by [Mitchell Hashimoto](https://github.com/mitchellh) and the Ghostty contributors. Ghostty is the original, and the reason this exists. The terminal, its performance, and nearly all of this repository's source are its work. Ghostties adds a sidebar.

This fork is not affiliated with or endorsed by the Ghostty project.

That distinction matters when something breaks. If the problem is the terminal itself, meaning rendering, fonts, config syntax, keybindings, or escape sequences, it's an upstream issue and belongs at [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty/issues), where it gets fixed for every Ghostty user. If it's the sidebar, `gt`, the MCP server, or updates, [file it here](https://github.com/SeanSmithWorks/ghostties/issues).

Please don't take Ghostties bugs to the Ghostty maintainers. They didn't ship this.

And if you want the terminal without the agent workspace, you want [Ghostty](https://ghostty.org). It's excellent. Go use it.

## Documentation

- [CONTRIBUTING.md](CONTRIBUTING.md). How to report things, and what happens with pull requests.
- [TESTING.md](TESTING.md). Running the test suites.
- [Building from source](AGENTS.md#commands). The build and launch commands.
- [SECURITY.md](SECURITY.md). Reporting a vulnerability privately.

Terminal configuration is documented at [ghostty.org/docs](https://ghostty.org/docs). Ghostties uses the same config.

## License

[MIT](LICENSE).

Copyright © 2026 Sean Smith. Copyright © 2024 Mitchell Hashimoto and the Ghostty contributors.

Ghostties bundles other people's software: the Chromium Embedded Framework, and Sparkle. Their licenses and notices are in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

# Ghostties

**Run all your coding agents in one window.**

Ghostties is a macOS fork of [Ghostty](https://github.com/ghostty-org/ghostty) with a sidebar for your agent sessions.

![The Ghostties window: a project sidebar on the left with sessions marked needs you, working and done, and a Claude Code session running in the terminal on the right.](.github/assets/product-hero.png)

> **Pre-1.0.** Active development, ships as a beta. Things move, and occasionally break.

## The problem

Running one coding agent is fine. Running five is a mess of terminal windows where you can't tell which one is working, which one is waiting on you, and which one finished twenty minutes ago while you were looking somewhere else.

Ghostties puts them in one window, grouped by project, and shows you what each one is doing.

![A recording of Ghostties: the sidebar collapses to a narrow rail while Claude Code fixes a flaky test in the terminal.](.github/assets/demo.gif)

## What it adds

Ghostty's terminal, with a workspace layer on top.

- **A project sidebar.** Sessions and tasks grouped by project. Projects show their real icons, and the sidebar collapses to a narrow rail.
- **Status at a glance.** Each session shows whether its agent is working, needs you, is done, or hit an error.
- **Approve or deny from the sidebar.** When Claude Code asks permission to run something, answer from the session's row.
- **A window that follows your theme.** With a terminal theme set, the sidebar, canvas and toolbar take their colors from it. Ghostties Light and Dark are the default.
- **`gt`, a CLI.** Create and move tasks from inside any agent session, so an agent can file its own work.
- **An MCP server.** Agents read and update the task list directly.
- **An embedded browser.** The thing you're building, next to the thing building it.

Everything else is Ghostty, unmodified: the terminal, the renderer, fonts, config, keybindings, shell integration.

## Install

With Homebrew:

```sh
brew install --cask seansmithworks/tap/ghostties
```

Or run `npx ghostties-install`, or download the latest `.dmg` from [Releases](https://github.com/SeanSmithWorks/ghostties/releases) and drag it to Applications. It updates itself after that.

Requires **macOS 13 or later on Apple Silicon**. There's no Intel build and no Linux build.

### First launch

macOS will ask for access to Desktop, Documents, and iCloud Drive. That's standard for any new terminal. The prompts come from commands running inside the terminal, not from Ghostties. Deny anything you don't need. To stop them entirely, grant Full Disk Access in System Settings, under Privacy & Security.

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

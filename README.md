# Ghostties

**A terminal for running several AI agents at once — a fork of [Ghostty](https://github.com/ghostty-org/ghostty).**

![Ghostties](web/assets/product-hero.png)

> **Pre-1.0.** This is in active development and ships as a beta. Things move and occasionally break.

## The problem

Running one coding agent is fine. Running five is a mess of terminal windows where you can't tell which one is working, which one is waiting on you, and which one finished twenty minutes ago while you were looking somewhere else.

Ghostties puts them in one window, organized by project, and shows you their state at a glance.

![Ghostties sidebar](.github/assets/demo.gif)

## What it adds

Ghostties is Ghostty's terminal with a workspace layer on top:

- **A project sidebar** — sessions and tasks grouped by project, so a window full of agents stays readable.
- **Status at a glance** — each task shows whether it's running, waiting on you, in review, or parked.
- **`gt`, a CLI** — create and move tasks from inside any agent session, so an agent can file its own work.
- **An MCP server** — agents can read and update the task list directly.
- **An embedded browser panel** — for the thing you're building, next to the thing building it.

Everything else — the terminal itself, the renderer, fonts, config, keybindings, shell integration — is Ghostty, unmodified.

## Install

Download the latest `.dmg` from [Releases](https://github.com/SeanSmithWorks/ghostties/releases), drag it to Applications, and open it. It updates itself after that.

Requires **macOS 13 or later on Apple Silicon**. There is no Intel or Linux build.

### First launch

macOS will ask for access to folders like Desktop, Documents, and iCloud Drive. That's standard for any new terminal — the prompts come from commands running *inside* the terminal, not from Ghostties. Deny anything you don't need. To stop the prompts entirely, grant Full Disk Access in System Settings → Privacy & Security.

The prompts say "Ghostty" rather than "Ghostties" because they use the bundle identifier inherited from upstream.

## Its relationship to Ghostty

Ghostties is a fork of [Ghostty](https://github.com/ghostty-org/ghostty), the terminal emulator created by [Mitchell Hashimoto](https://github.com/mitchellh) and the Ghostty contributors. Ghostty is the original, and it is the reason this exists — the terminal, its performance, and nearly all of this repository's source are its work. Ghostties adds a sidebar.

This fork is not affiliated with or endorsed by the Ghostty project.

**That distinction matters when something breaks.** If the problem is with the terminal — rendering, fonts, config syntax, keybindings, escape sequences — it's an upstream issue and belongs at [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty/issues), where it gets fixed for everyone. If it's the sidebar, `gt`, the MCP server, or updates, [file it here](https://github.com/SeanSmithWorks/ghostties/issues).

Please don't report Ghostties bugs to the Ghostty maintainers. They didn't ship this.

If you want the terminal without the agent workspace, you want [Ghostty](https://ghostty.org) — it's excellent, and you should use it.

## Documentation

- [CONTRIBUTING.md](CONTRIBUTING.md) — how to report things, and what happens with pull requests
- [TESTING.md](TESTING.md) — running the test suites
- [HACKING.md](HACKING.md) — building from source
- [SECURITY.md](SECURITY.md) — reporting a vulnerability privately

For terminal configuration, see [ghostty.org/docs](https://ghostty.org/docs) — Ghostties uses the same config.

## License

[MIT](LICENSE).

Copyright © 2026 Sean Smith. Copyright © 2024 Mitchell Hashimoto and the Ghostty contributors.

Ghostties bundles other people's software — Chromium Embedded Framework and Sparkle. Their licenses and notices are in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

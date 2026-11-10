# Contributing to Ghostties

Ghostties is a fork of [Ghostty](https://github.com/ghostty-org/ghostty) that adds a
multi-agent workspace sidebar. It's a personal project, built and maintained by one
person in his spare time.

The most useful thing you can do is **tell me when something is broken or confusing**.
I read every bug report.

## Is it a Ghostties issue or a Ghostty issue?

This matters, because sending it to the wrong place wastes your time.

**File it here** if it involves the workspace sidebar, the `gt` CLI, the MCP server,
installation, or auto-updates. Anything this fork adds.

**File it upstream** at [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty)
if it involves the terminal itself: rendering, fonts, config syntax, keybindings,
shell integration, escape sequences, or terminal performance. Ghostties inherits all
of that from Ghostty and doesn't modify it. Please don't report upstream bugs here,
and please don't report them upstream *as Ghostties bugs*. The Ghostty maintainers
didn't ship this fork and shouldn't have to support it.

If you're not sure, file it here and I'll route it.

## Pull requests

**I'm not accepting code contributions right now.** Not because your work wouldn't be
good. Reviewing and maintaining code I didn't write costs more time than I
have, and I'd rather leave an issue open honestly than let a PR sit unreviewed for
months.

Please open an issue instead. If you've already found the fix, describe it in the
issue and I'll credit you when it ships.

Documentation corrections are the exception. If something here is wrong or out of
date, a small PR is welcome.

If you're adding a document rather than fixing one,
[docs/INFORMATION-ARCHITECTURE.md](docs/INFORMATION-ARCHITECTURE.md) explains how
these files are organized and the questions to answer before adding another.

## Filing a good issue

- Which version you're on (About Ghostties in the menu bar, or `gt --version`) and
  which macOS version.
- What you expected, and what actually happened.
- Screenshots or screen recordings. These help a lot for sidebar issues.
- If it crashed, the report from `~/Library/Logs/DiagnosticReports/`.

The issue forms will walk you through this.

## Security

Please don't file security issues publicly. See [SECURITY.md](SECURITY.md).

## Building and testing

- [AGENTS.md § Commands](AGENTS.md#commands): building from source
- [TESTING.md](TESTING.md): running the test suites

## Conduct

Be decent to people. See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

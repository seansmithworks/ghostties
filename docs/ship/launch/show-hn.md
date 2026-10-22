# Show HN

## Title

Show HN: Ghostties, a Ghostty fork for running coding agents in one window

## URL

https://github.com/SeanSmithWorks/ghostties

## First comment

Hi HN, I'm Sean. I run a handful of Claude Code and Codex sessions at once, and I kept losing track of which terminal was working, which was waiting on me, and which finished twenty minutes ago.

Ghostties is a fork of Ghostty that adds a workspace sidebar. Sessions are grouped by project. Each row shows a status glyph: a spinner while the agent works, a ? when it needs you, a check when it's done, a cross on an error. For Claude Code, status can come from its own hooks rather than guesses from terminal output, after a one time hook setup. With that hook, hovering a row shows what the agent wants to run and why, or your last prompt and its current step.

Cmd+T opens one composer for everything: start a Shell, Claude Code, Codex or Browser session in any project, or resume a past one. The sidebar collapses to a rail of icons with Cmd+S. And there's an embedded browser, so the thing you're building sits next to the thing building it.

The newest beta adds a Settings window and a theme picker with a live preview, and the whole window now follows your terminal theme.

Everything else is Ghostty, unmodified: the renderer, fonts, config and keybindings. Your existing config loads as is. Terminal bugs belong upstream; sidebar bugs belong in this repo, and the README says how to tell them apart. This fork isn't affiliated with the Ghostty project.

It's MIT licensed, macOS 13 or later on Apple Silicon only, and it's a beta, so things move and occasionally break. Homebrew, npx and a signed, notarized DMG are all on ghostties.org.

I'd especially like to hear how you run several agents today, and what you'd want the sidebar to tell you that it doesn't.

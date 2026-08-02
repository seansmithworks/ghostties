# Security Policy

## Reporting a vulnerability

**Please don't open a public issue for a security problem.**

Report it through GitHub's private vulnerability reporting:
[Report a vulnerability](https://github.com/SeanSmithWorks/ghostties/security/advisories/new)

If that doesn't work for you, email **sean@seansmithdesign.com** with "Ghostties
security" in the subject.

I'll acknowledge within a few days. This is a personal project, not a company with
an on-call rotation — please don't expect an SLA, but I do take this seriously and
I will respond.

## What's in scope

Ghostties adds a workspace sidebar, the `gt` CLI, and an MCP server on top of
Ghostty. In-scope issues include:

- The `gt` CLI reading or writing outside its intended paths
- The MCP server exposing data or actions it shouldn't
- Task and session files leaking data across projects
- Problems with the update mechanism (Sparkle), signing, or notarization
- The embedded browser panel escaping its sandbox

## What's out of scope here

**Vulnerabilities in the terminal itself** — the emulator, parser, renderer, font
handling, shell integration — belong to upstream Ghostty. Report those to
[ghostty-org/ghostty](https://github.com/ghostty-org/ghostty/security) so every
Ghostty user gets the fix, not just Ghostties users. If a fix lands upstream,
Ghostties picks it up when it merges.

Third-party components (Chromium Embedded Framework, Sparkle) should be reported to
their own projects. If a known CVE affects a version Ghostties pins, that *is* worth
telling me about — I'll bump it.

## Supported versions

Only the most recent release gets fixes. Ghostties is pre-1.0 and ships from a
single release channel; there are no maintained older branches.

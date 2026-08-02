# Information architecture

How the documentation in this repository is organized, who each piece is for, and the rules for adding to it.

This is written for anyone maintaining these docs, including future me and any coding agent working in this repo. It exists because the last set of docs rotted silently: they were inherited from upstream and stayed wrong for months, because nothing recorded what they were supposed to do.

A note on honesty: this architecture was not designed up front. It emerged from an audit, and this document was written afterward to make it explicit and therefore maintainable. Writing it down is what turns a set of choices into something that can be checked.

## The problem this structure solves

Ghostties is a fork of [Ghostty](https://github.com/ghostty-org/ghostty). Nearly all of the source is upstream's work. The sidebar, the `gt` CLI, and the MCP server are the fork's.

That means almost every visitor arrives with a question that has to be routed before it can be answered: **is this a Ghostty thing or a Ghostties thing?** Get it wrong and a bug report lands with maintainers who never shipped the software, or a fix that would help every Ghostty user gets buried in a fork.

So the organizing principle here is not a topic tree. It is a disambiguation.

## Who arrives, and what they need

| Reader | Arrives at | Needs to know | Served by |
|---|---|---|---|
| Someone deciding whether to care | README | What it is, what it looks like, whether it runs on their machine | `README.md` |
| Someone with a problem | Issues, README | Whether this is the right repo, and how to describe it usefully | Issue forms, `CONTRIBUTING.md` |
| Someone who wants to help | CONTRIBUTING | Whether code contributions are wanted, and what to do instead | `CONTRIBUTING.md` |
| Someone building from source | HACKING | How to get it compiling | `HACKING.md`, `TESTING.md` |
| A security researcher | SECURITY | Where to send it privately, and what is in scope | `SECURITY.md` |
| Someone checking licensing | LICENSE | Who owns what, and what is bundled | `LICENSE`, `THIRD-PARTY-NOTICES.md` |
| A coding agent | AGENTS.md | The commands that work here, and the rules it must not break | `AGENTS.md` |

One document per reader, not one document per topic. A document that serves two readers well is rare. A document that claims to serve two readers usually serves neither.

The last row is the one people miss. `AGENTS.md` has a non-human audience, and it is read as instructions rather than as reference. That makes accuracy in it more load-bearing than in prose a person would skim: an agent will act on a stale command without noticing it is stale.

## Wayfinding is repeated, not centralized

The Ghostty-or-Ghostties question is answered at **six** entry points:

1. `README.md`, in its own section
2. `CONTRIBUTING.md`, as the first heading after the intro
3. `SECURITY.md`, as an explicit in-scope and out-of-scope split
4. The bug report form, before the first field
5. The feature request form, before the first field
6. `.github/ISSUE_TEMPLATE/config.yml`, as a link out to upstream

That repetition is deliberate. People do not arrive at the front door and walk inward. They arrive from a search result, a link, or the New Issue button. A single canonical page explaining the boundary would be correct and unread.

The tradeoff is real: six copies of an idea is six places to update when it changes. The rule that keeps it manageable is that only the *boundary* is repeated, never the detail. Each copy is one or two sentences and a link.

## Disclosure is keyed to commitment, not to complexity

The ladder runs: README, then CONTRIBUTING, then TESTING and HACKING.

The ordering is by how much of their time the reader is about to spend, not by how advanced the material is. This is why "code pull requests are not being accepted" appears in CONTRIBUTING rather than lower down in HACKING. Someone deciding whether to write a patch needs it before they build, not after.

Put the discouraging thing early. A reader who bounces at the top of the funnel lost a minute. A reader who finds out at the bottom lost a weekend.

## Every document declares how it decays

Documentation goes wrong when nobody knows which parts are supposed to be true. Each file here has one of three decay models.

**Generated.** `THIRD-PARTY-NOTICES.md` is assembled from the licence files on disk and diffed against them, never retyped. When a dependency version changes, the file is regenerated, not edited. Legal text is the clearest case where hand-copying is a defect.

**Measured.** `TESTING.md` states test counts and timings from actual runs. Those numbers go stale by design, which is why the file says to read the count from the run rather than trusting the number printed in it.

**Inherited and frozen.** `HACKING.md` is upstream's build documentation and stays that way, because Ghostties does not modify the build system, the Zig core, or the renderer. Rewriting it would mean maintaining a worse copy of a correct document. Only its header is ours, and that header's job is to mark which sections describe platforms this fork does not ship.

If you cannot say which of the three a new document is, it is not ready to add.

## Deletion is most of the work

The refresh that produced this structure changed 39 files: **1,340 lines added, 5,028 removed.** Close to four lines deleted for every one written, and a fifth of what was added was the plan describing the deletions.

The failure mode was not missing documentation. It was confidently wrong documentation: a `CODEOWNERS` file assigning review of this fork's source to 39 upstream teams, a vouching system that auto-closed issues from anyone not on a 233-person list belonging to another project, and contributor guides written in another maintainer's voice about another maintainer's rules.

Wrong signposts are worse than no signposts. Someone lost will ask. Someone confidently misdirected will not.

When auditing these docs, the first question is which files are lying, not which files are missing.

## Adding a document

Before adding one, answer these. If any answer is weak, the content probably belongs in an existing file.

1. **Which reader?** Name one from the table above, or add a row and justify it.
2. **What question does it answer** that no current document answers?
3. **Which decay model?** Generated, measured, or inherited.
4. **Where is it linked from?** An unlinked document does not exist. It needs an entry point on the path its reader is already walking.
5. **What does it say about the upstream boundary,** if a reader could plausibly be in the wrong repo?

## What this repository deliberately does not have

- **User-facing product documentation.** Terminal configuration lives at [ghostty.org/docs](https://ghostty.org/docs) and applies unchanged. Restating it here would create a second source of truth that drifts.
- **API or architecture reference.** The fork's internals change too fast for prose to keep up, and the code is the reference. `AGENTS.md` carries the map, not the detail.
- **A changelog per document.** Git carries that.
- **Tutorials.** There is no getting-started path beyond install, because the product is a terminal and the audience already has one.

## Keeping this file true

This document describes the other documents. That makes it the fastest one to rot, and the least likely to be noticed when it does.

It should be revisited whenever a document is added or removed, whenever the upstream boundary shifts, or whenever a reader turns out to arrive somewhere the table above does not predict. That last one is the strongest signal available and the easiest to ignore: if people keep filing terminal bugs here, the wayfinding is not working, regardless of how correct it looks on the page.

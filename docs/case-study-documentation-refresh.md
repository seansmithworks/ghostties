# Case study: rebuilding this repo's documentation

A record of how the documentation in this repository was audited, redesigned, and shipped, and what it got wrong along the way.

The structure it produced is described in [INFORMATION-ARCHITECTURE.md](INFORMATION-ARCHITECTURE.md). The original plan, written before any of it shipped, is at [plans/repo-documentation-refresh.html](plans/repo-documentation-refresh.html). This document is the narrative: what the problem turned out to be, which calls were made, and which are still unproven.

## The situation

Ghostties is a fork of [Ghostty](https://github.com/ghostty-org/ghostty), a well-known terminal emulator. The fork adds a workspace sidebar for running several AI agents at once. Nearly all of the source is upstream's.

By August 2026 it had 38 stars and was getting inbound attention. Issues were still switched off, because turning them on felt premature. The brief was simple: make the repository presentable, and get the Ghostty-versus-Ghostties relationship stated correctly, without over- or under-claiming.

The expectation was a README rewrite and a few missing files.

## What the audit actually found

The docs were the smaller half of the problem.

A fork inherits everything, including the parts that describe the original project's community rather than its code. Those parts had never been pruned. They were not stale in the ordinary sense. They were **actively wrong and still running**:

- **`CODEOWNERS`** assigned 67 review rules over this fork's source to **39 `@ghostty-org` teams**. None of them could review anything here. It generated review requests that could never be satisfied.
- **`.github/VOUCHED.td`** published the names of **233 individuals** from the upstream project, in a repository they had no involvement with.
- **Five vouching workflows**, two of which **auto-close issues and pull requests** from anyone not on that 233-person list, posting a message linking to another project's contributor guide.
- **`CONTRIBUTING.md`, `PACKAGING.md`, `AI_POLICY.md`** were upstream verbatim: another maintainer's voice, another project's rules, routing people to a discussion category that does not exist here.
- **Eight dead pipelines** building artifacts for distribution channels this fork does not ship to.

The affiliation problem everyone worries about in a fork is usually a README wording question. Here it was structural repository data. The repo was not overclaiming in prose. It was overclaiming in configuration, which is worse, because configuration executes.

The sharpest instance: **enabling Issues would have fired the auto-close workflow on the first issue anyone filed.** `issues`-triggered workflows run from the default branch, so the workflow was armed on `main` regardless of what any branch said. The single most important finding of a documentation audit turned out to be a sequencing constraint: purge the governance apparatus, *then* open the front door.

## The design calls

**Route on the boundary, everywhere.** The organizing principle is a disambiguation, not a topic tree: is this a Ghostty problem or a Ghostties problem? That question is answered at six entry points rather than one canonical page, because people arrive from search results and the New Issue button, not the front door. The cost is six places to update. The rule that keeps it cheap is that only the boundary is repeated, never the detail.

**One reader per document.** README for someone deciding whether to care. CONTRIBUTING for someone about to spend time. TESTING and HACKING for someone building. SECURITY for a researcher. `AGENTS.md` for a coding agent, which is a non-human reader that acts on instructions rather than skimming them.

**Disclose by commitment, not complexity.** "Code pull requests are not being accepted" belongs in CONTRIBUTING, not deep in HACKING. Someone deciding whether to write a patch needs that before they build. A reader who bounces early loses a minute. A reader who finds out late loses a weekend.

**Say no clearly.** This is a personal project with no capacity to review outside code. The choice was between an honest posture and a polite one that leaves pull requests rotting for months. CONTRIBUTING states it in the second section, gives the actual reason, exempts documentation fixes, and asks for issues instead.

**Give every document a decay model.** Generated (third-party notices, assembled from licence files on disk by script and diffed against them), measured (test counts, from real runs, with an instruction to re-measure rather than trust the printed number), or inherited and frozen (HACKING, which is upstream's and correct, so rewriting it would mean maintaining a worse copy).

**Delete first.** 39 files changed: 1,340 lines added, 5,028 removed. Wrong signposts are worse than missing ones, because someone lost will ask and someone confidently misdirected will not.

## What shipped

Five pull requests, merged in a required order.

| PR | What | Why the order mattered |
|---|---|---|
| #71 | Governance purge, 19 files, 4,524 deletions | Had to precede enabling Issues |
| #74 | CONTRIBUTING rewrite, SECURITY, CODE_OF_CONDUCT, TESTING, YAML issue forms | Had to precede #76 |
| #76 | Deleted PACKAGING and AI_POLICY, rewrote AGENTS.md, fixed HACKING header | Depended on #74 removing links to AI_POLICY |
| #73 | LICENSE stacked copyright, THIRD-PARTY-NOTICES, notice shipped in the app | Independent |
| #75 | README rewrite | Independent |

CONTRIBUTING went from 195 lines to 60. The README went to 68 lines with a product shot and an inline demo.

## Three things the plan had wrong

Worth recording, because they are the kind of error a plan produces and only contact with the files catches.

**The licence list was wrong in three places.** The plan said nerd-fonts was OFL; what is actually vendored is a source file that nerd-fonts explicitly licenses MIT, and no fonts are vendored at all. swift-argument-parser, which is Apache-2.0, was missing from the plan entirely. And Sparkle's licence file bundles four further licences inside it that a line reading "Sparkle, MIT" would silently drop.

**A notice in the repository is not a notice in the product.** The plan treated the licensing gap as a file to write. The actual obligation, under CEF's BSD-3 clause 2, is that the notice reaches a binary redistribution. The shipped `.app` contained no licence file anywhere, and the DMG is assembled from the `.app` alone, so the app bundle was the only route to a person who installs it. Fixing this meant an Xcode resource change, not a documentation change.

**The README needed a second pass for voice.** The first draft was accurate and structurally right, and read like documentation written by committee. It contained 19 em dashes, which the voice standard bans outright. Splitting those clauses into sentences was most of the fix. Same length, same structure, different register.

## How it was checked

Claims in documentation are worth what the verification behind them is worth.

- Licence bodies were assembled by script from the files on disk, then diffed byte for byte against those sources. Legal text is the clearest case where retyping is a defect.
- The in-app notice was confirmed by building the app and inspecting the bundle, not by reasoning that the build phase should work.
- Test counts in TESTING.md came from running both suites: 110 in the Swift package, 673 across 52 suites in the app. The previously recorded figure was 625, so the number had drifted.
- The six-entry-point claim in the architecture doc was checked by grepping all six files.
- Every deletion was checked for inbound references before it was made.

## What is still unproven

**The wayfinding has never met a real user.** Issues is still switched off. Every routing decision here is a hypothesis: that people will read the boundary statement, that the dropdown will catch misfiled bugs, that the upstream link will be taken. The first month of real issues is the test, and the honest measure of success is how many terminal bugs still land in this repo.

**Six copies of the boundary is a maintenance bet.** It is correct today. Whether it survives the next change to the fork's scope is unknown.

**`blank_issues_enabled` was left `true`, against the plan.** The plan called for forcing everyone through a form. Leaving the blank option open trades some structure for not turning away someone who fits neither template. If untemplated issues become noise, that flips.

**The hardest problem was not solved, only stated.** A fork's documentation has to explain a relationship, not just a product. Every reader has to be told what is not ours before they can be helped. No amount of structure makes that free.

## The honest note

This architecture was not designed up front from an audience model. It came out of an audit, decision by decision, and the architecture document was written afterward to make the implicit structure explicit and therefore checkable.

That order is worth admitting, because the alternative reading, that a clean structure was derived from first principles, would be a nicer story and a false one. The useful part is the writing-down. A set of choices nobody recorded is what produced the inherited mess in the first place.

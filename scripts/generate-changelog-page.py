#!/usr/bin/env python3
"""
Generate web/changelog.html from CHANGELOG.md.

CHANGELOG.md is the source of truth for release notes; this script renders
it into the site's changelog page so the two can never drift apart. Run it
after editing CHANGELOG.md and commit the regenerated web/changelog.html.

Usage: python3 scripts/generate-changelog-page.py
"""

import html
import re
from datetime import datetime

CHANGELOG_PATH = "CHANGELOG.md"
OUTPUT_PATH = "web/changelog.html"

PAGE_HEAD = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Changelog — ghostties</title>
  <link rel="icon" type="image/svg+xml">
  <script>
    (function() {
      var colors = ['#e84855','#8b5cf6','#22d3ee','#f472b6','#f59e0b','#eab308','#38bdf8','#7c6f9c'];
      var c = colors[Math.floor(Math.random() * colors.length)];
      var svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">'
        + '<path d="M4 2h8v1h2v1h1v10h-1v-1h-1v-1h-1v2h-1v-2h-1v1h-1v1h-1v-2h-1v2h-1v-1h-1v1H4v-1H3V3h1z" fill="' + c + '"/>'
        + '<rect x="5" y="5" width="2" height="3" fill="white"/>'
        + '<rect x="9" y="5" width="2" height="3" fill="white"/>'
        + '<rect x="6" y="6" width="1" height="2" fill="#1a1a2e"/>'
        + '<rect x="10" y="6" width="1" height="2" fill="#1a1a2e"/>'
        + '</svg>';
      var link = document.querySelector('link[rel="icon"]');
      link.href = 'data:image/svg+xml;base64,' + btoa(svg);
    })();
  </script>
  <meta name="description" content="Changelog — what's new in each Ghostties release.">
  <meta property="og:title" content="Changelog — ghostties">
  <meta property="og:description" content="Changelog — what's new in each Ghostties release.">
  <meta property="og:type" content="website">
  <meta property="og:url" content="https://ghostties.org/changelog">
  <meta property="og:image" content="https://ghostties.org/assets/social-card.png">
  <meta property="og:image:width" content="2560">
  <meta property="og:image:height" content="1280">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:image" content="https://ghostties.org/assets/social-card.png">
  <link rel="stylesheet" href="/style.css">
  <style>
    /* Changelog page only. Shared base: /style.css */

    .release {
      margin-top: 48px;
      padding-bottom: 48px;
      border-bottom: 1px solid var(--line-faint);
    }

    .release:last-child {
      border-bottom: none;
    }

    .release-heading {
      display: flex;
      align-items: baseline;
      gap: 12px;
      margin-bottom: 8px;
    }

    .release-heading h2 {
      font-size: 1.25rem; /* 20px */
      font-weight: 700;
      letter-spacing: -0.02em;
      color: var(--text-heading);
      text-transform: none;
      margin-top: 0;
      margin-bottom: 0;
    }

    .release-heading .date {
      font-size: var(--size-small);
      color: var(--text-label);
    }

    .release-summary {
      font-size: var(--size-body);
      line-height: var(--leading-snug);
      color: rgba(255, 255, 255, 0.55); /* one-off ramp step */
      margin-bottom: 20px;
    }

    .release-section {
      margin-top: 16px;
    }

    .release-section h3 {
      font-size: 0.6875rem; /* 11px */
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.1em;
      color: var(--text-label-quiet);
      margin-bottom: 8px;
    }

    /* Denser than the shared prose list; resets the shared ul spacing. */
    .release-section ul {
      list-style: none;
      padding: 0;
      margin-bottom: 0;
    }

    .release-section ul li {
      font-size: var(--size-meta);
      line-height: var(--leading-snug);
      color: rgba(255, 255, 255, 0.6); /* one-off ramp step */
      padding: 3px 0 3px 16px;
      margin-bottom: 0;
      position: relative;
    }

    .release-section ul li::before {
      content: '–';
      position: absolute;
      left: 0;
      color: var(--text-faint);
    }
  </style>
</head>
<body>
  <a class="skip-link" href="#main">Skip to content</a>
  <main id="main">
  <div class="content">
    <a class="back" href="/">&larr; ghostties</a>

    <h1>Changelog</h1>
    <p class="lead">What&rsquo;s new in each Ghostties release, newest first.</p>

    <div class="note">
      <p><strong style="color:rgba(255,255,255,0.6)">Beta.15 and earlier:</strong> Auto-updates aren't reliable yet in early betas. Download the latest release manually from the <a href="/download">download page</a>.</p>
    </div>
"""

PAGE_FOOT = """  </div>
  </main>

  <footer>
    <span class="footer-links">
      <span>&copy; 2026</span>
      <a href="/changelog">Changelog</a>
      <a href="/privacy">Privacy</a>
      <a href="/support">Support</a>
      <a href="/licenses">Licenses</a>
    </span>
  </footer>
</body>
</html>
"""

VERSION_HEADING_RE = re.compile(r"^## \[(.+?)\] — (\d{4}-\d{2}-\d{2})\s*$")
SUBSECTION_RE = re.compile(r"^### (.+?)\s*$")
REFERENCE_LINK_RE = re.compile(r"^\[[^\]]+\]:\s+https?://\S+\s*$")
CODE_SPAN_RE = re.compile(r"`([^`]*)`")


def smart_quotes(text: str) -> str:
    """Convert straight quotes/apostrophes in prose to typographic
    equivalents. Only ever call this on prose text — never on code-span
    contents, and never after HTML markup (e.g. href="...") has been
    generated, or it will mangle straight quotes that must stay literal."""
    # Contraction/possessive apostrophes: between two word characters
    # (session's, doesn't), including one before a trailing "s".
    text = re.sub(r"(\w)'(\w)", "\\1\u2019\\2", text)
    # Leading apostrophe eliding a letter at the start of a word ('til).
    text = re.sub(r"(^|\s)'(\w)", "\\1\u2019\\2", text)
    # Double quotes: alternate opening "/closing " for each pair encountered.
    if '"' in text:
        parts = text.split('"')
        rebuilt = parts[0]
        for i, part in enumerate(parts[1:]):
            mark = "\u201c" if i % 2 == 0 else "\u201d"
            rebuilt += mark + part
        text = rebuilt
    return text


def format_inline(text: str) -> str:
    """Escape HTML, then render the inline markdown CHANGELOG.md uses:
    `code`, [text](url), **bold**, *italic* — in that order, so code spans
    are protected before link/emphasis markers inside them are touched.
    Smart-quotes prose (not code-span contents) before any markup with
    literal quote characters (links) is generated."""
    text = html.escape(text, quote=False)

    # CODE_SPAN_RE.split alternates prose, code, prose, code, ... (odd
    # indices are the captured code-span contents). Smart-quote only the
    # prose pieces, then wrap the code pieces in <code> untouched.
    pieces = CODE_SPAN_RE.split(text)
    for idx in range(len(pieces)):
        if idx % 2 == 0:
            pieces[idx] = smart_quotes(pieces[idx])
        else:
            pieces[idx] = f"<code>{pieces[idx]}</code>"
    text = "".join(pieces)

    text = re.sub(r"\[(.+?)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"\*(.+?)\*", r"<em>\1</em>", text)
    return text


def format_date(date_str: str) -> str:
    return datetime.strptime(date_str, "%Y-%m-%d").strftime("%B %-d, %Y")


def parse_changelog(text: str):
    lines = text.splitlines()
    lines = [ln for ln in lines if not REFERENCE_LINK_RE.match(ln)]

    entries = []
    i = 0
    while i < len(lines):
        m = VERSION_HEADING_RE.match(lines[i])
        if not m:
            i += 1
            continue
        version, date = m.group(1), m.group(2)
        i += 1

        # Body runs until the next version heading or end of file.
        body = []
        while i < len(lines) and not VERSION_HEADING_RE.match(lines[i]):
            body.append(lines[i])
            i += 1

        # Summary: non-blank lines before the first "### " subsection or "---".
        summary_lines = []
        j = 0
        while j < len(body) and not SUBSECTION_RE.match(body[j]) and body[j].strip() != "---":
            if body[j].strip():
                summary_lines.append(body[j].strip())
            j += 1
        summary = " ".join(summary_lines)

        # Subsections: "### Name" followed by "- bullet" lines.
        sections = []
        while j < len(body):
            sm = SUBSECTION_RE.match(body[j])
            if sm:
                name = sm.group(1)
                j += 1
                bullets = []
                while j < len(body) and (body[j].strip() == "" or body[j].startswith("- ")):
                    if body[j].startswith("- "):
                        bullets.append(body[j][2:].strip())
                    j += 1
                sections.append((name, bullets))
            else:
                j += 1

        entries.append({"version": version, "date": date, "summary": summary, "sections": sections})

    return entries


def render_entry(entry) -> str:
    out = []
    out.append(f'    <!-- {entry["version"].split("-")[-1] if "-" in entry["version"] else entry["version"]} -->')
    out.append('    <div class="release">')
    out.append('      <div class="release-heading">')
    out.append(f'        <h2>v{entry["version"]}</h2>')
    out.append(f'        <span class="date">{format_date(entry["date"])}</span>')
    out.append('      </div>')
    out.append(f'      <p class="release-summary">{format_inline(entry["summary"])}</p>')

    for name, bullets in entry["sections"]:
        if not bullets:
            continue
        out.append('')
        out.append('      <div class="release-section">')
        out.append(f'        <h3>{html.escape(name, quote=False)}</h3>')
        out.append('        <ul>')
        for bullet in bullets:
            out.append(f'          <li>{format_inline(bullet)}</li>')
        out.append('        </ul>')
        out.append('      </div>')

    out.append('    </div>')
    return "\n".join(out)


def main():
    with open(CHANGELOG_PATH) as f:
        changelog = f.read()

    entries = parse_changelog(changelog)

    body = "\n\n".join(render_entry(e) for e in entries)

    page = PAGE_HEAD + "\n" + body + "\n\n" + PAGE_FOOT

    with open(OUTPUT_PATH, "w") as f:
        f.write(page)

    print(f"Wrote {OUTPUT_PATH} with {len(entries)} releases (newest: v{entries[0]['version']}).")


if __name__ == "__main__":
    main()

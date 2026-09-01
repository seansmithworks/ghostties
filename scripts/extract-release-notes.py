#!/usr/bin/env python3
"""
Extract one version's release notes from CHANGELOG.md.

Prints the summary paragraph and all subsections for the given version,
stopping before the next version heading. Used by the release workflow to
populate the GitHub Release body via --notes-file, so raw changelog prose
(quotes, backticks, parens) reaches GitHub untouched by shell interpolation.

Usage: python3 scripts/extract-release-notes.py <version>
  e.g. python3 scripts/extract-release-notes.py 0.1.0-beta.24

Exits non-zero if the version has no section in CHANGELOG.md.
"""

import re
import sys

CHANGELOG_PATH = "CHANGELOG.md"
VERSION_HEADING_RE = re.compile(r"^## \[(.+?)\] — \d{4}-\d{2}-\d{2}\s*$")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <version>", file=sys.stderr)
        return 1

    version = sys.argv[1].lstrip("v")  # accept "0.1.0-beta.24" or "v0.1.0-beta.24"

    with open(CHANGELOG_PATH) as f:
        lines = f.read().splitlines()

    body = []
    found = False
    i = 0
    while i < len(lines):
        m = VERSION_HEADING_RE.match(lines[i])
        if m and m.group(1) == version:
            found = True
            i += 1
            while i < len(lines) and not VERSION_HEADING_RE.match(lines[i]):
                body.append(lines[i])
                i += 1
            break
        i += 1

    if not found:
        print(f"No section for version {version!r} in {CHANGELOG_PATH}.", file=sys.stderr)
        return 1

    # Trim the trailing "---" separator and any blank lines around it.
    while body and body[-1].strip() in ("", "---"):
        body.pop()
    while body and body[0].strip() == "":
        body.pop(0)

    print("\n".join(body))
    return 0


if __name__ == "__main__":
    sys.exit(main())

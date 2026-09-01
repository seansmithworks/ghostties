#!/usr/bin/env python3
"""
Update version strings in web/index.html and web/download.html.
Called from the release workflow after a new tag is pushed.

Usage: python3 scripts/update-web-version.py <tag> [dmg-size-bytes]
  e.g. python3 scripts/update-web-version.py v0.1.0-beta.14 158314217

The optional second argument (DMG size in bytes) is rendered as MB in the
download page meta line. Omit to leave the existing size string in place.
"""

import os
import re
import sys
from datetime import datetime


failures = []


def replace(path: str, pattern: str, repl: str, label: str) -> None:
    """Replace `pattern` with `repl` in `path`. Logs whether it matched."""
    src = open(path).read()
    new, n = re.subn(pattern, repl, src)
    if n == 0:
        print(f"  ! {label}: pattern did not match in {path}")
        failures.append(label)
    else:
        open(path, "w").write(new)
        print(f"  ✓ {label}: {n} replacement(s) in {path}")


if len(sys.argv) not in (2, 3):
    print(f"Usage: {sys.argv[0]} <version-tag> [dmg-size-bytes]", file=sys.stderr)
    sys.exit(1)

version = sys.argv[1]  # e.g. "v0.1.0-beta.14" — strip leading "v" for display where natural
display_version = version  # full form including "v" prefix
short_version = version.lstrip("v")  # "0.1.0-beta.14"

now = datetime.now()
date_long = now.strftime("%B %-d, %Y")          # "April 30, 2026"

dmg_size_str = None
if len(sys.argv) == 3:
    bytes_ = int(sys.argv[2])
    mb = round(bytes_ / (1024 * 1024))
    dmg_size_str = f"{mb} MB"

print(f"Bumping site to {version} ({date_long})")

# 1. DMG download URL — both download.html and index.html hardcode one.
#    (index.html's hero "download now" line links straight to the DMG, not
#    to /download, so it needs the same bump.)
replace(
    "web/download.html",
    r"releases/download/v[\d][^/]+/Ghostties\.dmg",
    f"releases/download/{version}/Ghostties.dmg",
    "download.html DMG URL",
)
replace(
    "web/index.html",
    r"releases/download/v[\d][^/]+/Ghostties\.dmg",
    f"releases/download/{version}/Ghostties.dmg",
    "index.html DMG URL",
)

# 2. download.html — button label  ("Download v0.1.0-beta.X for macOS")
replace(
    "web/download.html",
    r"Download v[\d]\.\d+\.\d+(?:-[a-z0-9.]+)? for macOS",
    f"Download {version} for macOS",
    "download.html button label",
)

# 3. download.html — meta line. "v0.1.0-beta.X &middot; <date> &middot; <size> MB<br>"
if dmg_size_str:
    replace(
        "web/download.html",
        r"v[\d]\.\d+\.\d+(?:-[a-z0-9.]+)? &middot; [A-Z][a-z]+ \d+, \d{4} &middot; [\d]+ MB<br>",
        f"{display_version} &middot; {date_long} &middot; {dmg_size_str}<br>",
        "download.html meta line (with size)",
    )
else:
    # Replace version + date only; leave size as-is
    replace(
        "web/download.html",
        r"v[\d]\.\d+\.\d+(?:-[a-z0-9.]+)? &middot; [A-Z][a-z]+ \d+, \d{4} &middot;",
        f"{display_version} &middot; {date_long} &middot;",
        "download.html meta line (version+date only)",
    )

# 4. download.html — "Last updated <date>"
replace(
    "web/download.html",
    r"Last updated [A-Z][a-z]+ \d+, \d{4}",
    f"Last updated {date_long}",
    "download.html last-updated footer",
)

# 5. index.html — DMG install-cell trailing label ("...Ghostties.dmg</a><br>v0.1.0-beta.X")
replace(
    "web/index.html",
    r"(?<=</a><br>)v[\d]\.\d+\.\d+(?:-[a-z0-9.]+)?",
    version,
    "index.html DMG install-cell label",
)

# 6. index.html — channels-note current-release text
#    "Current release is <strong>v0.1.0-beta.X</strong> on the beta channel."
replace(
    "web/index.html",
    r"(?<=Current release is <strong>)v[\d]\.\d+\.\d+(?:-[a-z0-9.]+)?(?=</strong>)",
    version,
    "index.html channels-note current release",
)

if failures:
    print(f"\n{len(failures)} pattern(s) failed to match. Aborting.", file=sys.stderr)
    sys.exit(1)

print("Done.")

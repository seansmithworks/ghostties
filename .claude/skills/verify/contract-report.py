#!/usr/bin/env python3
"""Build one self-contained phone-width HTML page from composer-contract.md + status.json.

Usage: contract-report.py <contract.md> <out.html>
status.json is read from the contract's directory:
  rows: {"<ID>": {"result": "PASS|FAIL|PENDING|SEAN", "evidence": "...", "png": "path|null"}}
Order on the page: SEAN, FAIL, PENDING, PASS. PNGs are inlined as data URIs; video is never embedded.
Stdlib only.
"""
import base64
import html
import json
import os
import re
import sys

ORDER = ["SEAN", "FAIL", "PENDING", "PASS"]
ID_RE = re.compile(r"^[A-Z]+\d+$")


def parse_contract(path):
    """Returns (rows, p1_ids). rows: ordered list of dicts keyed by table column."""
    rows, p1 = [], []
    in_p1 = False
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if line.startswith("**P1 rows"):
            in_p1 = True
            continue
        if in_p1:
            m = re.match(r"^- \*\*([A-Z]+\d+):\*\*\s*(.*)$", line)
            if m:
                p1.append(m.group(1))
            continue
        if line.startswith("|"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) >= 5 and ID_RE.match(cells[0]):
                rows.append({"id": cells[0], "behavior": cells[1], "check": cells[2],
                             "evidence": cells[3], "bar": cells[4],
                             "focus": cells[5] if len(cells) > 5 else ""})
    return rows, p1


def load_status(contract_path):
    p = os.path.join(os.path.dirname(os.path.abspath(contract_path)), "status.json")
    return json.load(open(p, encoding="utf-8")), os.path.dirname(p)


def inline_png(png, base):
    if not png:
        return ""
    p = os.path.expanduser(png)
    if not os.path.isabs(p):
        p = os.path.join(base, p)
    try:
        data = base64.b64encode(open(p, "rb").read()).decode()
    except OSError:
        return '<p class="miss">PNG missing: %s</p>' % html.escape(png)
    return '<img alt="%s" src="data:image/png;base64,%s">' % (html.escape(os.path.basename(p)), data)


def card(r, res, base):
    result = res.get("result", "PENDING") if res else "PENDING"
    if res and res.get("signed"):
        result_label = "SEAN (signed)"
    else:
        result_label = result
    ev = (res or {}).get("evidence") or "no evidence recorded"
    return (
        '<section class="card %s"><h2><span class="id">%s</span><span class="badge">%s</span></h2>'
        '<p class="beh">%s</p><dl><dt>Bar</dt><dd>%s</dd><dt>Evidence</dt><dd>%s</dd></dl>%s</section>'
        % (result.lower(), html.escape(r["id"]), html.escape(result_label), html.escape(r["behavior"]),
           html.escape(r["bar"]) or "-", html.escape(ev), inline_png((res or {}).get("png"), base))
    )


CSS = """
:root{color-scheme:light dark;--bg:#fff;--fg:#111;--mut:#666;--card:#f4f4f5;--bd:#d9d9de;
--pass:#1a7f37;--fail:#c62828;--pend:#8a6d00;--sean:#6a3fd0}
@media(prefers-color-scheme:dark){:root{--bg:#111113;--fg:#ececf0;--mut:#9a9aa5;--card:#1c1c20;--bd:#33333a;
--pass:#4cc26a;--fail:#ff6b6b;--pend:#e0b841;--sean:#a98bff}}
*{box-sizing:border-box}
body{margin:0;padding:16px;background:var(--bg);color:var(--fg);font:16px/1.4 -apple-system,system-ui,sans-serif;
max-width:560px;margin-inline:auto;overflow-wrap:anywhere}
h1{font-size:20px;margin:0 0 4px}.sub{color:var(--mut);margin:0 0 16px;font-size:14px}
h3.grp{margin:24px 0 8px;font-size:14px;text-transform:uppercase;letter-spacing:.06em;color:var(--mut)}
.card{background:var(--card);border:1px solid var(--bd);border-left:4px solid var(--bd);border-radius:8px;padding:12px;margin:0 0 12px}
.card.pass{border-left-color:var(--pass)}.card.fail{border-left-color:var(--fail)}
.card.pending{border-left-color:var(--pend)}.card.sean{border-left-color:var(--sean)}
.card h2{font-size:16px;margin:0 0 6px;display:flex;justify-content:space-between;gap:8px}
.badge{font-size:12px;font-weight:600}.pass .badge{color:var(--pass)}.fail .badge{color:var(--fail)}
.pending .badge{color:var(--pend)}.sean .badge{color:var(--sean)}
.beh{margin:0 0 8px}dl{margin:0 0 8px;font-size:14px}dt{color:var(--mut);font-size:12px;margin-top:6px}dd{margin:0}
img{display:block;max-width:100%;height:auto;border-radius:6px;border:1px solid var(--bd)}
.miss{color:var(--fail);font-size:13px;margin:0}
"""


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: contract-report.py <contract.md> <out.html>")
    contract, out = sys.argv[1], sys.argv[2]
    rows, p1 = parse_contract(contract)
    if not rows:
        sys.exit("FAIL: no contract rows parsed from %s" % contract)
    status, base = load_status(contract)
    res = status.get("rows", {})
    known = {r["id"] for r in rows}
    # Rows only present in status.json (SEAN-1..10, P1 rows) get a card with no behavior text.
    for rid in res:
        if rid not in known:
            rows.append({"id": rid, "behavior": "(not in contract table)", "bar": "", "check": "", "evidence": "", "focus": ""})
    by = {k: [] for k in ORDER}
    for r in rows:
        k = (res.get(r["id"]) or {}).get("result", "PENDING")
        by[k if k in by else "PENDING"].append(r)
    counts = " · ".join("%d %s" % (len(by[k]), k) for k in ORDER)
    parts = ["<!doctype html><html lang=en><head><meta charset=utf-8>"
             '<meta name=viewport content="width=device-width,initial-scale=1">'
             "<title>Composer contract report</title><style>%s</style></head><body>" % CSS,
             "<h1>Composer contract, beta.26</h1><p class=sub>%s</p>" % html.escape(counts)]
    for k in ORDER:
        if by[k]:
            parts.append('<h3 class="grp">%s (%d)</h3>' % (k, len(by[k])))
            parts.extend(card(r, res.get(r["id"]), base) for r in by[k])
    parts.append("</body></html>")
    with open(out, "w", encoding="utf-8") as f:
        f.write("".join(parts))
    print("report: %s (%s)" % (out, counts))


if __name__ == "__main__":
    main()

#!/bin/bash
# Tag gate for the composer contract. Usage: contract-check.sh [memory-folder] [--require-signed]
# Exit 0 only when ALL hold; one stderr/stdout line per failing reason otherwise:
#  (a) sha256(composer-contract.md) == status.json.approved.sha256
#  (b) every gating row (each table row except IDs under "P1 rows") has result PASS.
#      A row with result SEAN is never PASS: it is reported pending/signed under (d).
#  (c) status.json.suite.{xcresult,command}: command is an unfiltered -only-testing:GhosttyTests run,
#      the xcresult summary (re-read via xcresulttool) has 0 failures and a Passed result. Totals are printed.
#  (d) SEAN rows are reported pending or signed. With --require-signed, pending ones fail too.
# Test seam: CONTRACT_CHECK_XCRESULTTOOL overrides `xcrun xcresulttool` (a command that takes the same args).
set -euo pipefail
DIR="/Users/seansmith/.claude/projects/-Users-seansmith-Code-ghostties/memory/beta26-test-harness"
REQ=0
for a in "$@"; do
  case "$a" in --require-signed) REQ=1 ;; *) DIR="$a" ;; esac
done
C="$DIR/composer-contract.md"; S="$DIR/status.json"
[ -f "$C" ] && [ -f "$S" ] || { echo "FAIL: missing $C or $S"; exit 1; }
ACTUAL="$(shasum -a 256 "$C" | cut -d' ' -f1)"
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

# Everything JSON-shaped goes through python3; it prints "FAIL: ..." / "INFO: ..." lines and the xcresult path on a "XC:" line.
OUT="$(python3 -I - "$C" "$S" "$ACTUAL" "$REQ" <<'PY'
import json, re, sys
contract, status, actual, req = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"
rows, p1, inp1 = [], set(), False
for line in open(contract, encoding="utf-8"):
    line = line.rstrip("\n")
    if line.startswith("**P1 rows"):
        inp1 = True; continue
    if inp1:
        m = re.match(r"^- \*\*([A-Z]+\d+):", line)
        if m: p1.add(m.group(1))
        continue
    if line.startswith("|"):
        c = [x.strip() for x in line.strip().strip("|").split("|")]
        if len(c) >= 5 and re.match(r"^[A-Z]+\d+$", c[0]): rows.append(c[0])
st = json.load(open(status, encoding="utf-8"))
res = st.get("rows", {})
# (a)
want = (st.get("approved") or {}).get("sha256")
if not want: print("FAIL: (a) status.json has no approved.sha256")
elif want != actual: print("FAIL: (a) contract sha256 %s does not match approved %s" % (actual[:12], want[:12]))
# (b) and (d)
pend, signed = [], []
for rid in rows:
    if rid in p1: continue
    r = res.get(rid)
    if r is None: print("FAIL: (b) %s has no result in status.json" % rid); continue
    v = r.get("result")
    if v == "PASS": continue
    if v == "SEAN":
        (signed if r.get("signed") else pend).append(rid); continue
    print("FAIL: (b) %s is %s, not PASS" % (rid, v))
for rid, r in res.items():
    if rid not in rows and r.get("result") == "SEAN":
        (signed if r.get("signed") else pend).append(rid)
print("INFO: (d) SEAN signed: %s" % (", ".join(sorted(signed)) or "none"))
print("INFO: (d) SEAN pending: %s" % (", ".join(sorted(pend)) or "none"))
if req and pend: print("FAIL: (d) %d SEAN row(s) pending: %s" % (len(pend), ", ".join(sorted(pend))))
# (c)
su = st.get("suite") or {}
xc, cmd = su.get("xcresult"), su.get("command", "")
if not xc: print("FAIL: (c) status.json has no suite.xcresult")
else: print("XC:" + xc)
if not xc or not cmd:
    if xc: print("FAIL: (c) suite.command missing, cannot prove the run was unfiltered")
else:
    only = re.findall(r"-only-testing[:=]?\s*(\S+)", cmd)
    if only != ["GhosttyTests"] or "-skip-testing" in cmd or "GhosttyUITests" in cmd:
        print("FAIL: (c) suite.command is not an unfiltered -only-testing:GhosttyTests run: %s" % cmd)
PY
)" || { echo "FAIL: could not evaluate status.json (invalid JSON?)"; exit 1; }

XC=""
while IFS= read -r l; do
  case "$l" in
    FAIL:*) fail "${l#FAIL: }" ;;
    INFO:*) echo "${l#INFO: }" ;;
    XC:*) XC="${l#XC:}" ;;
  esac
done <<< "$OUT"

if [ -n "$XC" ]; then
  # shellcheck disable=SC2086
  if SUM="$(${CONTRACT_CHECK_XCRESULTTOOL:-xcrun xcresulttool} get test-results summary --path "$XC" 2>&1)"; then
    TOT="$(python3 -I -c '
import json,sys
d=json.loads(sys.stdin.read())
g=lambda k:d.get(k,0)
print("%s|%s|%s|%s|%s"%(d.get("result"),g("totalTestCount"),g("passedTests"),g("failedTests"),g("skippedTests")))' <<< "$SUM")" \
      || { fail "(c) could not parse xcresult summary for $XC"; TOT=""; }
    if [ -n "$TOT" ]; then
      IFS='|' read -r res total pass failed skipped <<< "$TOT"
      echo "suite: result=$res total=$total passed=$pass failed=$failed skipped=$skipped ($XC)"
      [ "$res" = "Passed" ] && [ "$failed" = 0 ] && [ "$total" != 0 ] || fail "(c) suite not green: result=$res total=$total failed=$failed"
    fi
  else
    fail "(c) xcresulttool could not read $XC: $(printf %s "$SUM" | head -1)"
  fi
fi

if [ "$fails" -eq 0 ]; then echo "contract-check: OK"; exit 0; fi
echo "contract-check: $fails failing reason(s)"; exit 1

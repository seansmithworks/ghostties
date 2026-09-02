# P0 evidence — launchd/RunningBoard exit record

Query:
`log show --predicate 'process == "runningboardd" OR process == "launchd"' --info --start '2026-09-01 22:54:00' --end '2026-09-01 22:57:00' | grep <redacted-pid>`

Decisive line (22:55:34.714746):

    runningboardd: [app<application.com.seansmithdesign.ghostties...:<redacted-pid>>]
    termination reported by launchd (0, 0, 1536)

**Exit status 0, no signal.** The process quit itself cleanly.

Corroborating: the SIGKILLs observed a few microseconds later target *child*
XPC services (`com.apple.SetStoreUpdateService`, `com.apple.MTLCompilerService`),
and launchd labels them "sent by launchd[1] during teardown of process-scoped
services **after host exited**". They are an effect of the host process already
being gone, not a cause.

Conclusion: independent confirmation that this is a deliberate quit, not a
fault. No signal, no crash, exit code 0 — consistent with an `_exit`-class quit
from Chromium's main-loop shutdown. The `exit_type: Crashed` hypothesis
(read from the profile's `Preferences` file) is not the mechanism.

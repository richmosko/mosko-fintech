---
name: zero-value-sentinel-flips-meaning
description: When a fix changes a predicate, re-check every zero-value/EMPTY sentinel fed into it — a "safe default" is only safe relative to the predicate that consumed it, and read-failure paths substitute those sentinels
metadata:
  type: feedback
---

A `EMPTY_*` / zero-value sentinel substituted for "the read failed" is **not** self-evidently safe. Its
safety is a property of the predicate consuming it, so **any change to that predicate re-opens the
question** — and the comment asserting "the safe default" will not have been updated.

**Why:** at SELF-220, `+page.svelte` did `boundary={data.navBoundary ?? EMPTY_NAV_BOUNDARY}` on a
fail-soft read. The old date-gated predicate returned `false` on EMPTY → staleness markers SHOWN
(fail-loud). The fix for a genuine state-(b) bug changed the predicate to `!has_cron_rows || …`, and
EMPTY has `has_cron_rows === false` → **every point suppressed, whole series re-classified, and the
compensating disclosure also silent** (it required a different field). The failure posture inverted
from fail-loud to fail-quiet on a disclosure control, and two comments still called it "the safe
default". No test was red: the unit block's own docstring said the sentinel state was "moot, no points
exist to ask this of" — true of the genuine empty state, false of the read-failure path that
substitutes the same sentinel while points DO exist.

**How to apply:** on any predicate change, grep for the sentinel (`EMPTY_`, `?? DEFAULT`, zero-value
consts) and evaluate the NEW predicate against it by hand. Ask: which paths substitute this sentinel
for *unknown* rather than for *genuinely empty*? Those two are different states wearing one value.
Then check whether the compensating control (disclosure, banner, marker) fires in that same state —
a fail-quiet primary plus a silent compensator is the whole failure.

**The sharper rule this taught me**, after I handed over a criterion that proved insufficient: when a
composite return exists specifically to prevent state-collapse (here 069's three fields for four
states), "branch on the state fields" is **not enough** — a predicate keying on ONE field collapses a
different pair of states, one field over. **Branch on the full state tuple, not on any single field of
it.** A fix for a collapse bug can re-collapse a different pair; check all N states against the new
predicate, not just the one that was broken.

**Remediation-selection heuristic that paid off here:** when a defect has left comments asserting the
opposite of behaviour, prefer the fix that makes the EXISTING comments true again over the fix that
requires rewriting them. At SELF-220 the one-line predicate change restored the documented
"safe default", so the two files carrying that claim were never touched — closing a stale-comment
finding without opening a new stale-comment surface. Rewriting the comments to match the new behaviour
would have ratified a fail-open as intended.

Related: [[measure-the-fence-regex-not-its-comment]] (the stale-comment half),
[[catalog-comments-carry-live-state-tallies]].

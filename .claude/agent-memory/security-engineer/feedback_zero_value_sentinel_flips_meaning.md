---
name: zero-value-sentinel-flips-meaning
description: When a fix changes a predicate, re-check every zero-value/EMPTY sentinel fed into it — a "safe default" is only safe relative to the predicate that consumed it, and read-failure paths substitute those sentinels
metadata:
  type: feedback
---

**⚠ A `=== 0` DIVISION GUARD IS A NaN GUARD, NOT A DOMAIN GUARD — check the SIGN too.**
`nonReAllocation.ts` guarded `totalNonRe === 0` and I cleared it at review, satisfied that NaN
was prevented. **I never asked what happens when the denominator is NEGATIVE.** It can be:
`fn_subcat_market_value` admits liability-account balances, which are *signed naturally negative*
(`056`), so a tenant whose debts exceed their holdings gets `totalNonRe < 0` and a fully-rendered,
**sign-inverted** allocation table — positive assets showing negative %Alloc, liabilities showing
positive. No NaN, no throw, nothing red.

**The reason it survived review is the reusable half: the invariant that still holds is exactly
the one that hides it.** Σ %Alloc remains 100 under a negative denominator — algebraically it
must — so the strongest existing assertion passes on an inverted table. **When proposing the
paired watcher, name the fixture (`denominator < 0`) and explicitly rule OUT the sum-check**,
or the fix ships with a test that would have passed before it.

**How to apply:** at every `x / d`, ask three questions, not one — *can `d` be 0? can `d` be
NEGATIVE? can `d` be NaN?* Guard the domain the figure actually requires (`d <= 0` for a
share-of-whole percentage), not merely the arithmetic exception. Signed aggregates over mixed
asset/liability sets are the recurring source. Related:
[[two-functions-two-partitions-axis-mismatch]] — the same signed-liability fact drove both.

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

**The third place the sentinel hides — the PROP DEFAULT (SELF-229).** A fail-closed rework fixed
`loadStaleness()` to degrade to UNKNOWN, but every consumer still declared `staleness = EMPTY_STALENESS`
/ `isStale = false` as its **prop default**, and the page did `data.staleness ?? EMPTY_STALENESS`. Every
live mount passed the prop, so nothing was broken — but the framework's own ADR (013 D1) says its surface
list is illustrative and more surfaces ramp later, so the default is a fail-open **armed for the next
ramp site that forgets the prop**. When reviewing a fail-closed fix, check three layers, not one:
the loader's error paths, the render predicate, and **the default that applies when the value never
arrives at all**. Offer both shapes: default flips to the UNKNOWN constant (fails closed at runtime,
costs a test re-run) or the prop becomes required (fails closed at typecheck, zero runtime change).

**Also SELF-229 — the guard predicate vs the payload's arity.** `loadStaleness` guarded `error` and
`!row` but normalized with `Boolean(row.is_stale)` and `Array.isArray(items) ? … : []`, so a malformed
*field* (not a failed read) landed back on the confirmed-healthy value the rework existed to eliminate —
while the module header claimed "malformed → UNKNOWN". Same lesson one level down: the contract was a
two-field tuple and the guard tested existence only. Check reachability before severity — I proved it
unreachable from the current DB fn (`is_stale = exists(…)` and the item list aggregate over the SAME
CTE), which is what made it a flag rather than a veto.

**The fourth hiding place — a MIRROR LIB that drops the sibling's gate (SELF-241, PR #520).** §2.2.2's
client mirror carries `ratioColumnsUnset(total) → total <= 0` and threads the denominator into BOTH
render helpers, with a comment naming the bug class it exists for ("a fake-zero at a degenerate
denominator … shipped once already"). §2.2.3's new mirror advertised itself as the same pattern but its
`fmtPct`/`fmtUsd` **dropped the denominator parameter**, keeping only the `null` translation — and its
server sibling guards `=== 0` on two *independent* denominators where §2.2.2 guards `> 0` on one and
nulls all four ratio columns together. Neither layer of the two-layer defense survived the copy.
**How to apply:** when a file's own header says "MIRROR of X" / "reuses the shipped pattern", diff the
EXPORTED SIGNATURES against X, not the prose — a dropped parameter is a dropped control, and the claim
of mirroring is what stops anyone from looking. Then ask what the banner/copy ASSERTS and whether the
render path can contradict it: here the note said "percent and target comparisons aren't shown below"
while the %Target column rendered real figures in the ordinary onboarding state (`total = 0`,
targets configured).

**And the paired tell: the test fixture was shaped to the claim.** The one degenerate-state test built
an **all-null** row fixture — a payload the server does not produce in that state — so it asserted the
banner's text against a world where the text was true. **Check a degenerate-state fixture against what
the compute core actually RETURNS in that state**, not against what the assertion needs. Same family as
[[a-red-whose-message-names-the-wrong-defect]] and the "assertion with no watcher" class.

Related: [[measure-the-fence-regex-not-its-comment]] (the stale-comment half),
[[catalog-comments-carry-live-state-tallies]].

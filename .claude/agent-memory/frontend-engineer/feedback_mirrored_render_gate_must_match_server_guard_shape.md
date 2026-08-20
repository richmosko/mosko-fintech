---
name: mirrored-render-gate-must-match-server-guard-shape
description: When copying a sibling table's client-side degenerate-denominator gate, verify the two SERVER compute cores actually null together on the same predicate — don't assume the copied gate is redundant belt-and-suspenders.
metadata:
  type: feedback
---

Sec caught this as a blocking (AMBER) finding on SELF-241/PR #520, not something I caught myself:
`UsEquityAllocationTable`'s `fmtPct`/`fmtUsd` dropped the denominator parameter that
`NonReAllocationTable`'s sibling `fmtRatioPct`/`fmtRatioUsd` carry, because I assumed the shipped
§2.2.2 gate was pure belt-and-suspenders on an already-guarded server payload — true for §2.2.2,
false for §2.2.3.

**Why:** `computeNonReAllocation` (§2.2.2) guards on ONE domain predicate (`total_non_re > 0`) and
nulls all four ratio columns TOGETHER — its client gate is genuinely redundant. `computeUsEquityAllocation`
(§2.2.3, a different server module even though it's the "same table family") guards on TWO
INDEPENDENT `=== 0` checks (a NaN guard, not `<= 0`) — `pct_alloc` nulls separately from
`pct_target`/`dollar_target`/`dollar_realloc`. Two reachable, real states fell through: zero
holdings with configured targets (ordinary onboarding — server returns non-null `pct_target` while
`dollar_alloc` is exactly zero), and a negative total (`=== 0` never catches negative, so every
ratio column renders real numbers). Dropping the gate because "the server already guards this" was
true for the module I was copying visual/structural patterns from, not the module I was actually
wrapping.

**How to apply:** when reusing a sibling table's render-side gate/formatter pattern, don't assume
the two server compute cores share a degenerate-state contract just because they're the same table
family or were built back-to-back (SELF-239/SELF-240 here). Read the ACTUAL guard predicate in the
server module this component wraps — grep for `=== 0` vs `> 0`/`<= 0`, and check whether multiple
fields null on the SAME check or on separate ones. If they diverge, the client-side gate is
load-bearing, not redundant, and needs to reuse the shared predicate (e.g. `ratioColumnsUnset` from
`$lib/nonre-allocation`) applied uniformly across every ratio column at the render boundary —
document which case it is in the file's own header so the next author (who will copy whichever
sibling file they find first) doesn't rediscover the divergence as a live bug.

See [[feedback_stale_component_header_vs_migration]] for the sibling discipline of reading the
actual source (here: the actual guard predicate) rather than trusting a sibling's narrative.

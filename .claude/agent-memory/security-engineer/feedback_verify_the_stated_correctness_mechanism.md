---
name: verify-the-stated-correctness-mechanism
description: When a file names its own correctness mechanism ("textual identity across N copies", "STABLE", "verbatim kernel"), MEASURE it — the claim is usually true and unwatched, and a fence added while it holds locks in a real invariant rather than codifying drift
metadata:
  type: feedback
---

**When an artifact states the mechanism that makes it correct, treat that sentence as a testable
claim, not as reassurance.** Migration `076` said it outright: *"The house treats textual identity as
the correctness mechanism: five copies that read identically can be diffed; five that read
differently cannot."* Nothing verified it — an assertion with no watcher, sitting behind every
financial figure in the product.

**Measure it before deciding what to do about it.** Extracted the price-pick kernel from every copy
(`019` `049` `050` `056` `059`×2 `076`) and hashed. **All identical — the claim was true.** That is the
more useful outcome than finding drift, because **a fence added while the invariant HOLDS locks in a
real property; added after drift it codifies the drift.** Say that when proposing the control; it is
the argument for doing it now rather than "sometime".

⚠ **The measurement detail that would have broken the fence:** raw hashes differed across copies and
looked like drift. The difference was **leading whitespace only** — the copies sit at different
nesting depths, legitimately. Normalize leading whitespace (`sed 's/^[[:space:]]*//'`) before
comparing, and **tell the fence author**, or the fence fails on day one and gets disabled. A
first-pass "drift found!" here would have been a false finding delivered with hashes attached.

**Companion pattern — a stated modifier is also a testable claim.** The same review surfaced CONTRACT
text claiming `STABLE` on three financial functions whose DDL omits the modifier, leaving them
**VOLATILE** (`grep -A4 'CREATE OR REPLACE FUNCTION'` for `LANGUAGE sql` with no volatility keyword).
**Find the concrete hook rather than filing it as tidiness:** ADR-038's foot-to-NAV invariant compares
two of them in one statement, and VOLATILE gives no statement-level snapshot guarantee for that
comparison. Remediation shape: fix all instances in one migration **plus a structural pin**
(`pg_proc.provolatile = 's'`) — the mismatch survived because nothing asserted it, so the fix must
include the assertion. ⚠ Also: the reporting agent named two instances; measuring found a third.
**Re-measure the population, don't inherit its size.**

**And when a brief tells you a function has no `limit 1`, check.** `076` has two selectors: a
`GROUP BY` aggregation (isolation path — a leak ADDS to a sum, so the #474 displacement class does not
apply and a corrupt-the-control fails LOUD) and a price-pick `limit 1` with a non-total ordering
(value nondeterminism). **One function, both kinds.** Correct the framing precisely rather than
accepting or rejecting it wholesale — "no limit-1 selector" was false, "no limit-1 on the isolation
path" was the true and load-bearing claim.

**How to apply:** grep any reviewed artifact for sentences of the form *"X is what makes this
correct"* / *"copied verbatim"* / *"identical to"* / a declared modifier, and ask (1) what command
falsifies it, (2) run that command, (3) if it holds, is anything watching it, (4) if not, propose the
fence now and hand over the normalization detail. Related:
[[measure-the-fence-regex-not-its-comment]] and
[[corrupt-the-control-canary-boundary-tie]].

⚠ **The posture TRIPLE is the family convention, and a battery can pin one third of it.** `096`'s
battery pinned `prosecdef` alone; `062`/`064`/`067`/`069`/`070`/`071`/`073`/`079`/`089` pin all three in
ONE leg — `is((select array[p.prosecdef::text, p.provolatile::text, array_to_string(p.proconfig, ',')]
… ), array['false','s','search_path=""'], …)`. `093`/`094` pin none, so **check which sibling convention a
new battery inherited before calling it a regression** (`grep -l "proconfig" supabase/tests/rls/*.sql`).
Converting `ok()` → `is()` is one leg out, one leg in, so `plan(N)` and the header's leg breakdown both
stay valid — a free fix, which is the argument for asking at review rather than booking it. **Why it
bites:** it fails closed on BOTH removal paths — dropping `set search_path = ''` makes `proconfig` NULL,
and Postgres array equality uses btree semantics (a NULL element opposite a non-NULL one is NOT-equal,
not NULL), so the leg REDs instead of passing on a NULL comparison. Verify that property before
accepting an array-shaped assertion as a watcher; the SQL-three-valued intuition predicts the opposite.

**Companion — a ONE-TIME mechanism offered as a PERMANENT invariant.** The GL-split ADR draft
(2026-08-18) wrote: *"the new table's identity sequence is set past the maximum so no id is ever
reused on either side"*, concluding *"every historical snapshot remains resolvable against exactly
one table."* The mechanism delivers the conclusion **only at the migration instant** — two
independent identity sequences both advanced past a shared max then run forward in parallel and
collide on the very next insert each. **Ask of every stated mechanism: does it hold at t=0 only, or
by construction forever?** The tell is a mechanism phrased as an ACTION ("is set past…") supporting a
claim phrased as a STATE ("remains resolvable"). Remediation shape is always the same: replace the
action with a construction (one shared sequence, or disjoint reserved ranges) and make the battery
assert the **construction**, not a point-in-time count. ⚠ And the point-in-time battery leg the draft
proposed was **vacuous on a fresh CI stack**, where the property holds by construction rather than by
verification — the "fresh-stack CI is clean by construction" trap in
[[a-red-whose-message-names-the-wrong-defect]].

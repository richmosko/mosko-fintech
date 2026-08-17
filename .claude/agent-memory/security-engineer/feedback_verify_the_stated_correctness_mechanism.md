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

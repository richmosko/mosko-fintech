---
name: pgtap-ran-count-watcher-gap-not-literal
description: How to build a pgTAP leg that re-arms the "planned N ran M" plan/ran drift watcher for a file with trailing savepoint-wrapped legs — a bare `curr_test = <literal>` comparison is inversion-proven WRONG; assert the GAP between `_get('plan')` and `_get('curr_test')` instead.
metadata:
  type: reference
---

pgTAP exposes its internal bookkeeping via `public._get(label text)` reading a per-transaction
temp table `__tcache__` (`select value from __tcache__ where label = $1`). Two labels matter
here: `'plan'` (set once by `plan(N)`, at the top of the file, long before any savepoint — never
rolls back) and `'curr_test'` (updated by every `ok()`/`is()`/`throws_like()` call as it runs,
INSIDE whatever transaction/savepoint scope is active at that moment — DOES roll back with a
`rollback to savepoint`).

**A file whose trailing legs are all `savepoint ... rollback to savepoint`-wrapped** (SELF-355's
`115`, 14h-i..iv) shows `finish()`'s own "Looks like you planned N tests but ran M" comment,
because `curr_test`'s value reverts to whatever the LAST non-rolled-back write left it at.
[[feedback_pg_prove_aggregate_run_tap_artifact_unconfirmed]] documents the drift arithmetic;
[[feedback_strike_the_real_guard_before_trusting_a_mechanism_claim]] documents that pass/fail
DETECTION survives this rollback (the printed TAP line is the statement's own return value,
unaffected). This note is about a THIRD thing: re-arming the plan-count watcher itself so a
NEW trailing savepoint-wrapped leg added later doesn't silently widen the drift unnoticed.

**First attempt, WRONG (inversion-proven):** `is(_get('curr_test'), 49, ...)` — a bare literal
matching the currently-observed value. Struck by injecting a 5th trailing savepoint-wrapped leg
on a scratch copy: it stayed GREEN. Why: `curr_test` reverts to the SAME value (49, set by the
last non-rolled-back leg) after EVERY rolled-back savepoint, regardless of how many run in
sequence — the literal cannot distinguish 4 trailing legs from 5, or from 40.

**Correct shape:** `is(_get('plan') - _get('curr_test'), <expected drift>, ...)`. `plan` grows
by 1 when a genuine new assertion (and its `plan(N)` bump) is added, but `curr_test` does NOT
move if that new assertion is ALSO trailing-savepoint-wrapped (its own write also rolls back) —
so the ARITHMETIC GAP widens by exactly 1, and the watcher REDs. Inversion-proven correct on
the same injected-leg scratch copy (with `plan()` bumped to match the new leg, as any honest
addition would do): the gap read 6 against an expected 5, failing loudly by name.

**The off-by-one to get right:** the watcher leg's own `plan()` slot is ALREADY counted in
`plan()`'s total (since `plan(N)` is set once for the whole file) but its own `curr_test` write
has NOT happened yet at the moment its own comparison runs (that write happens as part of the
SAME `is()` call finishing, after the comparison is evaluated). So the expected gap equals
(known trailing-savepoint-leg count) + 1 — the "+1" is this very leg, planned but not yet run
at comparison time. Getting this wrong reads as the watcher itself failing on an otherwise
correct file — verify empirically on a clean scratch clone before trusting the constant.

**Side effect worth knowing, not the point:** because the watcher leg is itself NOT
savepoint-wrapped, its own `_set('curr_test', ...)` write survives to `finish()`'s later read
and "resurrects" `curr_test` to match `plan()` exactly — so `finish()`'s own "planned N ran M"
comment disappears entirely once this leg exists, even though the underlying savepoint-rollback
mechanism is completely unchanged. Don't mistake the vanished comment for the drift itself
having gone away.

How to apply: any file with trailing savepoint-wrapped legs and a plan-count drift that a
reviewer wants actively watched (not just documented) should end with this gap-based leg,
never a bare-literal one — and MUST be inversion-proven with a real injected extra leg before
landing, the same way any other structural/catalog leg in this codebase is.

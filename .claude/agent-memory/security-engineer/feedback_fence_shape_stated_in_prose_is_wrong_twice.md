---
name: fence-shape-stated-in-prose-is-wrong-twice
description: A proposed DB fence described in natural language gets its PREDICATE and its SCOPING wrong in opposite directions — derive the refused set from the defect mechanism and prefer a STATE invariant on NEW over a transition guard, which leaks the other write order
metadata:
  type: feedback
---

**When someone hands me a fence described as a sentence, the sentence is the thing to distrust —
and it fails in two independent places.** V1.3 pre-flight D-8 (`pfin.account_trans_annotation`,
the M3 money defect): the proposal was *"refuse a non-Transfer cat when `journal_id IS NOT NULL`,
scoped `WHEN new.sub_cat_id IS DISTINCT FROM old.sub_cat_id`."* Both halves were wrong, in
**opposite** directions — the predicate too broad, the scoping too narrow — and each was one grep
from being right.

**(1) PREDICATE — a "refuse non-X" phrasing over an enum sweeps in the siblings.** Measure the
enum's full vocabulary first. `084:588` fixes `cat in ('Revenue','Expense','Transfer','Equity',
'Trade')`, and `084:1233`'s biconditional `(security_id is not null) <> (cat = 'Trade')` **forces**
an in-kind transfer's security legs to `Trade`. "Non-Transfer" therefore refuses every in-kind
transfer. **Derive the refused set from the defect mechanism, not from the English.** The defect was
an ordered `CASE` (`084:869-872`) whose first three branches pre-empt the correct one, so the
refused set is exactly those three: `cat IN ('Revenue','Expense','Equity')`. A predicate derived
from the mechanism can also be *explained* by it in the function comment, which is what stops a
future reader from "completing" or deleting a partial fence. Related:
[[two-functions-two-partitions-axis-mismatch]] (measure both member sets before the arithmetic).

**(2) SCOPING — a transition guard leaks the OTHER write order.** `WHEN new.x IS DISTINCT FROM
old.x` fences the invariant only when `x` moves. But the invariant read **two** columns
(`sub_cat_id` and `journal_id`), and the violating state is reachable by moving either:
classify-then-attach changes only `journal_id`, never fires, defect reached. ⚠ **Mechanical check:
enumerate every column the invariant READS, and ask whether changing each one alone can reach the
violating state.** If more than one can, a transition guard on one of them is a hole.

**Prefer a STATE invariant on NEW.** `when (new.a is not null and new.b is not null)` is valid on
INSERT and UPDATE, references no OLD, and has no ordering hole because it constrains the *resulting
row* rather than the *edit*. Two facts that make this the default rather than a preference:
- A `WHEN` clause on a `BEFORE INSERT OR UPDATE` trigger **cannot reference OLD at all** — Postgres
  rejects it. Transition-scoping such a trigger forces either two triggers or a body-side `tg_op`
  branch, i.e. more surface for the weaker guarantee.
- The "hazard" that motivated transition-scoping (the fence firing on an unrelated UPDATE and
  breaking a legitimate flow) is a property of the **broad** predicate, not of state-scoping. Once
  the predicate is narrowed per (1), firing on that UPDATE is the fence **working** — the legitimate
  flows pass and only the defect state raises. **Re-test a scoping objection after narrowing the
  predicate; it often evaporates.**

**And the battery has to be able to tell the two shapes apart.** A pgTAP battery that exercises only
attach-then-classify passes under BOTH the state invariant and the leaky transition guard — it
cannot distinguish them, so it is not a watcher for the thing that was decided. Require a leg per
write ORDER, plus `lives_ok` controls for each legitimate cat that must still pass. Same family as
[[corrupt-the-control-canary-boundary-tie]] and [[inversion-test-the-rationale-not-the-presence]].

**Placement note that came free.** Folding a new rule into an existing trigger function that already
resolves the same rows looks cheap, but that function carries a `comment on function` shipping to
`pg_description` and existing catalog assertions key on it ([[signature-change-invalidates-catalog-
assertions]] in the shared index). A separate function + trigger keeps attribution readable and
leaves the assertions untouched, for one extra lookup on qualifying writes only.

---
name: before-row-trigger-cannot-see-later-rows
description: A BEFORE ROW trigger cannot see rows inserted later in the same statement, so a set-property fence (monotonicity, ordering, totality) written as BEFORE ROW passes a bad multi-row batch — it must be a deferred CONSTRAINT TRIGGER or a statement-level AFTER check.
metadata:
  type: reference
---

Found at the V1.4 pre-flight on SELF-259's drafted monotonicity trigger (*"each successive
`bracket_floor` > previous"*), and Sec had it independently as a §3 trap.

**The mechanism.** A `BEFORE INSERT ... FOR EACH ROW` trigger fires per row, before the statement's
remaining rows exist. A multi-row `INSERT ... VALUES (…), (…), (…)` — which is what any
**replace-all** write path emits — therefore validates each row against a set that is not yet
complete. A non-monotone batch **passes**.

**The tell:** the fence names a property of a SET (monotone, ordered, exactly-one, sums-to-zero) but
is attached per ROW. Per-row fences can only check per-row properties plus already-committed state.

**The fix:** `CREATE CONSTRAINT TRIGGER … AFTER INSERT OR UPDATE … DEFERRABLE INITIALLY DEFERRED FOR
EACH ROW`, or a statement-level `AFTER` trigger — either way it evaluates once the set exists.

⚠ **This is worse than a fence that is merely redundant.** A constraint over a by-construction
property cannot fire and turns a future regression into an outage
([[feedback_watcher_not_fence_for_by_construction_properties]]). This one is the inverse: it is
written in a form that **cannot observe the property it names**, and it reads to a reviewer as a live
guarantee. The paired battery leg that catches it is *"a non-monotone MULTI-ROW batch is rejected"* —
a single-row leg passes either way.

⚠ **SERIALIZABLE is not a substitute and the claim must be struck wherever it appears.** SERIALIZABLE
guarantees only that concurrent transactions are equivalent to *some* serial order; it says nothing
about whether one transaction leaves the rows monotone. Sec struck exactly that parenthetical from
SELF-269's AC6 because it would let a reviewer accept the isolation level **in place of** the check.

Related: [[reference_before_row_fence_makes_the_fk_unreachable]] ·
[[reference_with_check_is_a_policy_not_a_check_constraint]] ·
[[feedback_assertion_with_no_watcher]]

---
name: check-violation-reported-in-constraint-name-order
description: Postgres reports a CHECK violation by constraint NAME order, not creation order — so an additive constraint is masked by an alphabetically-earlier sibling, and a rename silently re-attributes every name-anchored test leg
metadata:
  type: reference
---

When a row violates more than one CHECK on a table, PostgreSQL reports the one whose
**constraint name sorts first** — creation order is irrelevant. Measured 2026-08-29 with
an inverted probe: `z_created_first` added first, `a_created_second` added second, a row
violating both → Postgres named **`a_created_second`**.

**Why it bites.** Adding a constraint whose predicate OVERLAPS an existing one does not
make the new one observable. At `095`, `cpi_u_index_value_positive_finite` bars NaN and
±Infinity, but `cpi_u_index_value_finite` sorts ahead of it, so those three values are
still reported against the OLDER constraint. **A test leg asserting the new constraint's
name on an overlapping value FAILS on correct DDL.** To attribute the overlap to the new
constraint, drop the earlier-sorting one inside a savepoint first.

**How to apply.**
- Adding an overlapping constraint → decide, at authoring time, which name will report,
  and say so in the migration's QA block. Non-overlapping values (here `0`, `-1`) report
  against the new one and need no special handling.
- Renaming EITHER constraint can flip the attribution with no predicate change and no
  behaviour change — it silently reds every name-anchored leg. Rename → re-measure BOTH
  batteries. Sec pinned this as its own item precisely because nothing else watches it.
- Generalizes past CHECKs: any assertion keyed to *which* object reported an error is
  keyed to a resolution order the DDL does not state.

Related: [[named-vs-predicate-exclusion-visibility]] · [[watcher-not-fence-for-by-construction-properties]]

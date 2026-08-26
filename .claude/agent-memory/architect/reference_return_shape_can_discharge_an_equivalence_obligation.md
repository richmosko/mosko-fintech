---
name: return-shape-can-discharge-an-equivalence-obligation
description: When two reachable states must mean the same thing to every caller, pick the return SHAPE that makes them indistinguishable — do not push the equivalence onto consumer discipline
metadata:
  type: reference
---

An obligation of the form *"state X and state Y mean the same thing and every caller must
treat them identically"* has two possible homes, and only one of them holds.

- **Consumer discipline** — every handler is told to branch on both. It ships unchecked,
  and the first handler that anticipates only one diverges (typically by throwing on the
  absent case, or rendering a caption for a cleared value).
- **The return shape** — the function's own type makes the two states produce *the same
  bytes*, so there is nothing for a caller to branch on. The obligation cannot be broken
  because it cannot be observed.

**Worked case (SELF-250, `093`).** `pfin.cashflow_target` has two reachable "no targets
set" states under the always-NULL-never-DELETE ruling: **zero rows** (never opened the
editor) and **one row of NULLs** (set then cleared). They reach a driver as *different
result shapes*. Returning `jsonb` and building the block from **scalar subqueries** makes
them identical by construction — a scalar subquery over zero rows yields NULL, so both
states emit `{"income_target_annual": null, "expense_target_monthly": null}`, byte for
byte. A `returns table` would have re-exposed the zero-rows-vs-one-row difference at the
boundary, which is the exact defect the obligation names. Verified on all three reachable
states (absent / both-null / values set); house precedent is Lock 11's
`fn_render_monthly_report(...) RETURNS JSONB`.

⚠ **The tell that you are in this case:** the obligation's own wording says *"a handler
anticipating only one diverges."* That sentence is a description of consumer discipline
failing. Treat it as a signal to move the obligation into the type, not as a warning to
write on the ACs.

⚠ **Scope it honestly.** This works when the states are genuinely synonymous. If they ever
need to be told apart (an audit surface asking *did the user ever open the editor*), the
collapse is lossy and the right answer is a separate query, not a wider return.

The Lock-14 settings family has three more per-domain tables coming with the same
unset-representation question — the shape decision templates.

Related: [[a-rationale-home-is-not-an-enforcement-home]] ·
[[watcher-not-fence-for-by-construction-properties]] ·
[[scope-the-invariant-before-writing-it]]

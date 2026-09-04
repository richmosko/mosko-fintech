---
name: watcher-not-fence-for-by-construction-properties
description: When a property already holds by construction, a runtime fence can never fire and turns a future regression into an outage — give it a test, not a constraint
metadata:
  type: feedback
---

**When a property is already guaranteed by construction, do not add a runtime
constraint enforcing it. Add an assertion that watches it.**

A fence over a by-construction property:
- **can never fire**, so its green is evidence of nothing — `062`'s first diagnostic
  question (*"can this check ever fail?"*) answered wrongly;
- **costs on every write** (often a cross-table aggregate on a cron path) to buy that
  nothing;
- and when the property finally *does* break, the fence **rejects the write** — turning
  a derivation regression into a nightly outage instead of a report.

> **The thing worth watching is not whether the property holds. It is whether the
> property STAYS held by construction.** A test observes that; a constraint cannot
> distinguish it from normal operation until it starts failing production.

**Why:** ADR-054, 2026-08-12. PM identified that Σ(per-account leaf values) should
reconcile with the scalar `nav_daily` checkpoint for the same `(user, date)` and left
the enforcement question as Architect design space. The two figures derive from the same
computation in the same cron transaction — `051`'s header records its NAV equals
`Σ 049(active)` equals `fn_compute_nav(as_of, true)` **by construction**. Ruled: QA
battery leg, not a constraint trigger.

**How to apply:**
- Ask **"what would have to change for this to become false?"** If the answer is "a
  future refactor of the derivation", that is a **test's** job.
- Reserve fences for properties an *adversary or a caller* can violate at runtime. Use
  watchers for properties *our own future code* could regress.
- ⚠ **Name the hidden coupling the equality rests on**, or the watcher tests less than
  it appears to. Here: Σ(leaves) equals the scalar **only while both sides apply the
  same active/as-of account filter**. Change one independently and it breaks for reasons
  unrelated to the feature.
- ⚠ **Make the watcher an obligation, not an intention** — put it in the migration's QA
  pairing block. A check chained to nothing is decoration.
- ⚠ **Mark the analysis contingent when it depends on an unratified answer.** This one
  presumes the "documented property" ruling; under an enforced-invariant ruling the
  argument must be re-made against a different property. An analysis that reads as
  unconditional gets carried across a decision it never covered.

- ⚠ **A UNIQUE constraint can make an "ordering" requirement by-construction, and the
  requirement's own wording hides it.** SELF-259's AC named *"bracket-row
  monotonicity"* without naming a column. `unique (schedule_id, bracket_floor)` already
  makes a schedule's floors pairwise **distinct**, and any distinct numeric set is
  **totally ordered** — so a floor-ordering trigger leg could never fire. The
  falsifiable set property was the **PAIRING**: rate non-decreasing in ascending floor
  order, which no unique constraint and no per-row check can see. **When a spec says
  "monotonic / ordered / sequential" but does not name the column, find the one whose
  ordering is not already given away by a key.**

Related: [[structural-fence-must-cover-the-same-class]] · [[fixture-is-shared-state]]

---
name: backlog-issue-deliverable-may-already-have-shipped
description: A Backlog issue's deliverable can already be on main under an unrelated migration's name — grep for the DATA/behavior, not the issue's own identifiers, before calling it unbuilt.
metadata:
  type: feedback
---

Before classifying a Backlog issue as "to build", grep for the **thing it delivers**, not the identifiers its AC names. The AC's identifiers are the ones that drifted; the deliverable may have shipped years-of-migrations ago inside a file named after something else.

**Why:** measured at the V1.3 pre-flight (2026-08-22). SELF-245 read "ship the cashflow-side additive seed" and its ACs named `user_taxonomy` + `domain='cashflow'` + the retired 4-Cat vocabulary — all schema-impossible, which makes the whole issue *look* unbuilt. It was not: `041` had already seeded 27 cash-flow default rows **in the ratified 5-class vocabulary**, and `084` relocated them to `posting_prototype_default`. Reporting "build the seed" would have been a correct-looking edit on a wrong premise. Only the `is_tax_payment` half was genuinely live.

**How to apply:** when an AC's identifiers are all falsified, that is a signal to widen the search, not to conclude absence. Query the seeded/live state (`select cat, count(*) …` on a scratch DB, or read the seed INSERT in the migration that owns the table) before writing "UNBUILT". Inverse of [[feedback_ratified_name_is_not_a_built_table]]; same family as [[feedback_no_concept_exists_check_deferred_decisions]] and [[reference_schema_impossible_ac_traces_to_incumbent]].

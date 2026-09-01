---
name: in-queue-is-a-ratified-name-not-ddl
description: The `in_queue` unclassified predicate that S-2/SELF-251/254/256 ACs all cite as "single source" has ZERO DDL — but its semantics ARE realized inside fn_cashflow_items. Equivalence proof + the real drift risk.
metadata:
  type: project
---

`in_queue` and `effective_sub_cat_id` have **zero hits in `supabase/migrations/`**.
Every occurrence is in `docs/records/v13-preflight/`. Measured 2026-08-31.

**The semantics are built; only the NAME is not.** The ratified definition is
`in_queue(row) := classifiable(row) AND effective_sub_cat_id IS NULL`, and both
halves fall out of `pfin.fn_cashflow_items(p_as_of)` (093) by construction:
- `classifiable()` = **membership in that function's output** (mechanically-excluded
  rows never appear — 096's header states this).
- `effective_sub_cat_id` = the **emitted `sub_cat_id`**, because the emission
  branches resolve it per grain: an unsplit transaction projects
  `c.ann_sub_cat_id`, a split child projects its OWN `s.sub_cat_id`, and split
  parents are NEVER emitted (the split XOR). No grain diverges.

So `in_queue(row) ≡ row ∈ fn_cashflow_items(p_as_of) AND sub_cat_id IS NULL`, and
093's `unclassified.count_ytd` (`sub_cat_id is null and i.in_ytd`) is **faithful,
not a re-derived variant**.

**Why:** a brief called 093's form "a re-derived `sub_cat_id IS NULL` variant" to be
avoided in favour of "093's `in_queue` predicate". Neither exists as written. Had I
taken the framing, this would have been filed as a 093 defect instead of a naming gap.

**How to apply:**
- If asked to "reuse the `in_queue` predicate", say it does not exist, give the
  equivalence above, and **prove it from the emission branches** — the split-child
  grain is where it would break if it broke. See
  [[project_p4_split_child_journaled_cat_residual]].
- ⚠ **The real risk is hand-copying, not wrong semantics.** The predicate is spelled
  inline in each consumer with no shared home; 093 has one copy and SELF-251 / 254 /
  256 each want another. Four copies of a ratified predicate is the same drift shape
  as the month-anchor rule — see [[project_nav_month_anchor_degeneracy]].
- 096 **cannot** supply this count: it filters `cat = 'Expense'` and INNER-joins
  `posting_prototype` on `sub_cat_id`, so unclassified rows are doubly excluded.
  That is the S-2 ruling working, not a bug.
- Generalizes [[feedback_ratified_name_is_not_a_built_table]] and
  [[feedback_no_concept_exists_check_deferred_decisions]].

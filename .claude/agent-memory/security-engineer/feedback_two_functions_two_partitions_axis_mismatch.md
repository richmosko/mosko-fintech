---
name: two-functions-two-partitions-axis-mismatch
description: When an AC or invariant equates figures from two functions, check that both partition the portfolio on the SAME axis — an account_type filter and a taxonomy-cat filter look interchangeable and are not; measure prosrc, don't read the header.
metadata:
  type: feedback
---

**Rule: any claim of the form "Σ X from function A equals Y from function B" is first a question
about PARTITIONS, not about arithmetic. Establish that both sides slice the same set on the same
axis before evaluating whether the numbers match.**

**Why:** SELF-238's F/CTO-ratified AC4 required `Σ $Alloc = fn_nav_composition`'s `total_non_re`,
EXACT. Measured at the live catalog: `fn_nav_composition` filters on **`account_type`** and
excludes `('real_estate','liability')`; `fn_subcat_market_value` has **no `account_type` filter at
all** (`prosrc ilike '%account_type%'` → false) and excludes only taxonomy `cat = 'Real Estate'`.
QA and Backend both found the real-estate mismatch and both framed it as *conditional on a
misclassification*. **The third case is structural: LIABILITY accounts.** Their balances flow into
the taxonomy-axis rollup and are excluded from `total_non_re` outright — so the equality fails for
any tenant with a credit card, with nothing misclassified. **The AC was a category error between
two partitions of the same portfolio, not an edge case.**

**How to apply:**
- **Measure the filter, don't read the description.** `select prosrc ilike '%account_type%' from
  pg_proc where proname = …` settles in one query what a header comment will not.
- **Enumerate the partition members of BOTH sides and diff them.** Here: `{real_estate,
  liability}` vs `{cat='Real Estate'}`. The asymmetry is visible the moment both are written down
  and invisible while either is described in prose.
- **Separate "the implementation is wrong" from "the claim is unsatisfiable."** Here the module's
  own internal denominator was self-consistent and correct; only the cross-function AC was false.
  **Say which, because the remedies have different owners** — code to the author, AC text to
  PM + F/CTO.
- **A ratified AC can be the defect.** Ratification establishes intent, not feasibility. Raising
  it is in scope; see [[pm-draft-ac-vs-schema]] in the project index for the sibling pattern.
- **Check reachability before setting severity.** `grep -rln <module> api/src/routes/` returned
  nothing — no user saw a wrong number, which turned a merge-block into a record-block. **Block
  the RECORD and the SEQUENCING** (the sibling surface must not inherit the assumption) rather
  than the diff, when the diff is not what is wrong.
- **"Not live-verified" can be the correct call.** Backend declined to build a footing fixture; a
  fixture for an unprovable identity yields either a green on a hand-picked tenant or a red nobody
  can interpret. Do not treat a missing test as a gap until the claim it would test is known true.

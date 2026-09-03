---
name: two-functions-two-partitions-axis-mismatch
description: When an AC or invariant equates figures from two functions, check that both partition the portfolio on the SAME axis — an account_type filter and a taxonomy-cat filter look interchangeable and are not; measure prosrc, don't read the header. Also: before flagging a NULL enum as a routing gap, find which field the CONSUMER actually branches on.
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

---

⚠ **VARIANT — the ROUTING axis. A NULL in a lookup column is only a gap if the consumer branches
on that column. Read the consumer's steps before calling it one.** At the V1.4 pre-flight I flagged
`tax_character = NULL` on the two `tax_relevant = true` Trade seed rows as an undefined
bracket-routing gap, reasoning from the PRD's *enum → schedule* routing TABLE, which has no NULL
row. Wrong: the consuming computation's own numbered steps sum **by column** (Ordinary / ST CG /
LT CG) and consult the enum only *within* the Ordinary column — so a NULL on a Trade row is
coherent by design, and the seed row's own note said so. **The routing table looked like the
discriminator and was one only for a subset of rows.**

- **The tell:** a lookup table and a step-by-step procedure describing the same routing. The table
  reads as total; the procedure is where the actual branch lives. **Read the procedure.**
- **The corrected finding was elsewhere and sharper:** the column placement depended on a
  **holding period** that an explicitly-sanctioned state (an unmatched sell) does not have. The
  first framing pointed at a table that was fine; the second at a state the tree itself blesses.
  **A refuted flag often has a real sibling one layer down — look before dropping it.**
- **Cost of getting this wrong in an interim message:** it ships as a finding before the retraction
  does. Name it in §-form in the same document as the findings, per the standing rule.

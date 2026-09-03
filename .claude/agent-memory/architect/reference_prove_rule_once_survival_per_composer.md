---
name: prove-rule-once-survival-per-composer
description: In an extracted-reader family, a RULE is proven once at the extraction but SURVIVAL-THROUGH-COMPOSITION is a different assertion owed by each composer — the §2.3 batteries encode this, and two composers are missing the D19-required leg
metadata:
  type: reference
---

**Two different assertions, routinely conflated when someone asks "isn't this already tested?"**

1. **The RULE** — proven ONCE, in the extraction's own battery. Re-proving it in each consumer is
   the drift the extraction exists to prevent, and it triples the authoring cost.
2. **SURVIVAL THROUGH COMPOSITION** — that the composer does not independently break the rule.
   This is owed by **each composer**, and only where composition could plausibly break it.

The §2.3 cash-flow family encodes this explicitly and is the worked example. `093`
`fn_cashflow_items` owns the six reader rules; `094`'s battery header states outright that reader
rules are *"093's exclusive territory … and are NOT re-proven here"* — then carries exactly ONE
reader-rule leg, the created-ON-D half-open bound, justified as *"composition could break it
independently."* `096` has the same shape (its `BOUND/F1` leg).

**How to use it:** when an AC says a rule should be *"tested once rather than N times across the
consumers,"* that is almost always a **coverage-inventory ruling** — cite the extraction's legs by
label in the COMPOSED pattern — **not** a request to author fresh SQL. Check the consumers' battery
headers first; ours already declined to re-derive.

**RULED DISTRIBUTIVE, 2026-09-03 (team-lead).** ADR-011 Decision 19's amendment states verbatim
that the created-ON-the-as-of-date-is-INCLUDED leg *"is now required of the §2.3 verification
battery."* Collective-vs-distributive was genuinely ambiguous and decided real work, so it was
routed rather than read; **`094`'s own recorded rationale — "composition could break it
independently" — is what decided it.** So: **every composer on the shared reader owes that leg**,
shaped to its own contract.

At the ruling, `093`/`094`/`096` carried it and `fn_expenditures_unclassified_count` (098) and
`fn_cashflow_contributors` (099) did not; QA authors both in the SELF-257 battery. ⚠ **Re-measure
the inventory rather than trusting that list** — it drifts every time a composer is added, and the
obligation now attaches automatically to each new one.

**The transferable half:** when a ratified phrase is ambiguous between a cheap and an expensive
reading, *route it* — do not resolve it in the direction that creates work for a teammate. And look
for a sibling artifact that already reasoned about the same question; here a battery header's
one-line rationale settled an ADR's ambiguity.

Related: [[feedback_a_rationale_home_is_not_an_enforcement_home]] ·
[[feedback_structural_fence_must_cover_the_same_class]].

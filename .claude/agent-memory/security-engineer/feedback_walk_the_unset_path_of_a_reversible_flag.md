---
name: walk-the-unset-path-of-a-reversible-flag
description: A control gated on a reversible user flag has an UN-SET path that is a live money/state move — walk it; and review the ADDITION a remediation lands beside your verbatim text, because the qualifier ships unreviewed
metadata:
  type: feedback
---

Two halves of one catch, from the SELF-267 re-review.

**1. When a fence is gated on a REVERSIBLE user flag, walk the UN-SET path as its own event.**
I reviewed the set path exhaustively — default-state hazard, mark → both figures move, cross-tenant,
the partial unique index — and passed it. The un-set path was in the battery as a correctness leg
(*"the exclusion is a live read, not a one-way latch"*) and I read it as a **reassurance** rather
than as a **hazard notice**. It is both: clearing the `tax_jurisdiction` designation returns that
ledger to `fn_nav_composition`'s leaf set, so **NAV rises by every payment ever made to that
authority** — the exact double-count the feature exists to prevent, arriving through un-setting.
[[feedback_a_safety_proof_is_someone_elses_hazard_notice]] at flag grain: the leg that proves the
control is live is the same fact that proves the un-set is a money move.

**How to apply:** for every user-settable flag that gates a money figure or a security control, ask
**three** questions, not one — what does SET do · what does UN-SET do · **what is the recommended
procedure for un-setting, and does anything state its consequence?** The third is where this one
lived: V1's only rollover procedure (clear the old designation, designate a fresh ledger) silently
produced the defect, and had just been written into the artifact as guidance.

**2. Review the ADDITION a remediation lands beside your verbatim text.**
My B1 clause shipped byte-identical — I checked that and would have stopped there. Architect added an
adjacent rollover clause under a ruling ID (`E19`) that exists on no pushed ref. **The qualifier is
where the falsifiable content was**, and it also made my own sentence read as contradicting it
(*"prevents a fresh ledger per tax year"* vs *"a fresh designation is always available"* — both true,
adjacent, and the second reads as refuting the first). **How to apply: diff the whole surrounding
block, never just `my text == what landed`; then re-read my own landed sentence against its NEW
neighbours and name my own ambiguity in the same message as the finding.** Related:
[[supplied-verbatim-text-ships-unfiltered]], [[a-period-named-figure-may-carry-no-period-bound]].

**Instrument note that made the first half provable:**
`git diff -U0 A B -- <file> | grep -E "^[+-]" | grep -vE "^(\+\+\+|---)" | grep -vE "^[+-]--"`
returns exactly the changed NON-comment lines of a SQL migration — a cheap, independent
corroboration of a teammate's "function bodies md5-identical" claim that does not depend on locating
the `$$` delimiters (my `awk`/`perl` body-extraction attempts both silently matched nothing and
returned the empty-string md5 `d41d8cd9…`, which looks like a real answer;
[[feedback_instrument_cannot_observe_the_property]]).

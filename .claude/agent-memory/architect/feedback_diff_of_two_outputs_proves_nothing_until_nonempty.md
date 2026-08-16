---
name: diff-of-two-outputs-proves-nothing-until-nonempty
description: A diff between two captured command outputs reports IDENTICAL when both are empty — check non-emptiness before believing an equivalence claim
metadata:
  type: feedback
---

Before believing `diff a b` → "identical", assert both captures are NON-EMPTY (`wc -l`, or a row-count predicate). An equivalence claim over two empty files is the strongest-looking and least informative result the tool can produce.

**Why:** authoring `072`, I claimed "all ten pre-existing columns are unchanged between 071 and 072" from a `diff` of two psql captures. The diff said identical. Both files had **zero lines** — `psql -c` with a multi-statement `begin; … rollback;` string had emitted nothing, so the comparison had no content on either side. I caught it only because I ran `wc -l` afterwards out of habit; the claim was already on its way into a commit message and a report. Re-run with `-f <file>` produced 5 rows on each side and the equivalence then meant something.

**How to apply:** any time an equivalence, containment, or regression claim rests on comparing two captured outputs — psql, git show, catalog dumps — the non-emptiness check belongs in the SAME command as the diff, not as a follow-up. `wc -l` both, then diff. The generalization: a comparison operator is only as strong as the weakest thing it will accept as a valid operand, and "nothing" is a valid operand to every one of them.

Related: [[verify_the_bytes_you_commit]] (verify the artifact, not its source) and the user-level `feedback_permissive_harness_vacuous_green` (a harness that cannot fail is not a green).

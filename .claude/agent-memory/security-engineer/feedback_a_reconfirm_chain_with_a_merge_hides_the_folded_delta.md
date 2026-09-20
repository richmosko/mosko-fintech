---
name: a-reconfirm-chain-with-a-merge-hides-the-folded-delta
description: "A re-confirm brief that states the FIX COMMIT's --stat understates the baseline..tip delta whenever a merge sits in the chain; measure both, then prove the merged blobs arrive byte-identical and are already on main"
metadata:
  type: feedback
---

When a re-confirm chain is `reviewed-tip → merge-of-main → fix-commit`, the brief's
`--stat` is usually the **fix commit's**. The verdict is pinned to the **tip**. Those are
different deltas and the gap is everything the merge carried in.

**Why:** PR #840 (2026-09-20). Brief said "3 files, +11/−13" — exactly right for
`51040b05..bdc0ef9f`. But `a22bb77b..bdc0ef9f` was **6 files, +106/−29**: the merge brought
`scripts/deploy-app.sh` +59 and two more files from a sibling PR. Blessing the tip on the
fix commit's stat would have put a GREEN over a +59 change to a deploy script that the
re-confirm never named. Nothing was wrong here — but nothing in the brief would have told me.

**How to apply:**
1. **Always measure `baseline..tip` yourself**, not the commit the brief describes. If they
   differ, say so in the report and name the axis — the brief is not wrong, it is answering
   a different question.
2. **Prove the merged blobs arrive unmodified:** `git diff <main-sha> <merge-sha> -- <those
   paths> --stat`. Expect only the branch's own additions; anything else is a **fold** —
   content that entered via conflict resolution and was reviewed by nobody.
3. **Prove the merged content is genuinely already reviewed:**
   `git merge-base --is-ancestor <main-sha> origin/main`. "It came from main" is a claim.
4. `git log -1 --format='%P' <merge>` to confirm the parents are the two you expect.

Cheap — four commands — and it converts "the brief says the merge is content-free" into a
measurement. See [[feedback_grading_a_composed_verdict_across_a_stacked_chain]] (folds,
COUNT, "did any blob arrive UNREVIEWED?") and [[feedback_reconfirm_brief_scope_is_a_claim]].

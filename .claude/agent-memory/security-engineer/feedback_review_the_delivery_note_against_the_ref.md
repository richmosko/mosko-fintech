---
name: review-the-delivery-note-against-the-ref
description: A teammate's temp/ delivery note is a claim about WHICH TREE was measured — diff it against the reviewed ref; a v2 sitting uncommitted means the green run named a tree that is not the one being merged
metadata:
  type: feedback
---

At a merge-gate review, read the executing agent's `temp/` delivery note **and diff its artifacts
against the ref under review**. The note's test counts and "all green" claims are a claim about the
tree the author measured, which is not necessarily the tree being merged.

**Why:** on the ELEMENT PR (`feature/gl-element-column` @ `527a89c`) the branch carried QA's **v1**
of two battery files while `temp/qa-element-battery-delivery.md` was headed *"v2 — supersedes the
first delivery"* and reported its green run as a test count that only exists with v2's extra leg
present. The brief described the committed content accurately, so reviewing only the ref would have
reported clean and missed it entirely. Related: [[feedback_read_the_branch_from_the_ref_not_the_worktree]]
and [[feedback_temp_handoff_path_is_per_worktree]] — `temp/` is gitignored, so an undelivered v2
does not survive session close and must be disposed explicitly, never left "for later".

**How to apply:** when a PR pairs a migration with a battery, `diff` the branch file against the
same-named file in `temp/` before writing the verdict. Then **bound the gap rather than just
reporting it** — if the delta is purely additive, say so, because that is what lets the author's
green run transfer to the committed legs and keeps the finding a FLAG instead of a RED. Offer the
disposition as land-v2 / declare-v1-ratified / merge-and-lose-it, and name the third option's cost
out loud so it is a decision rather than an evaporation.

**Second lesson from the same review:** a pgTAP `plan N ran N-1` diagnostic on a file ending in
rolled-back `corrupt-the-control` legs is **not** "each rolled-back leg loses a count." The counter
is a POSITION the next leg re-occupies, so only the **tail** rolled-back leg is unreplaced — drift
is always 1, never the number of savepoints. I predicted N-2 from a sum model and was wrong; see
[[feedback_a_red_whose_message_names_the_wrong_defect]] — a header predicting the wrong number on
the exact diagnostic a reader uses to detect a missing leg will get that diagnostic dismissed.

---
name: route-the-sha-not-the-description
description: A joint-review-mandatory surface must be DISPATCHED at a frozen sha on the branch it lives on — describing it in a report is not routing, and the reviewer is right to refuse it.
metadata:
  type: feedback
---

I built a write surface on an ADR-011 Decision 2 audit-class table (the first live
exercise of the Decision 3 #4 fence) on a **stacked** branch, and **described it in a
status report** to the reviewer instead of having it dispatched. Sec refused to review
it from the description — correctly — and asked for a frozen sha.

**Why:** my own routing rules name that exact pair as joint-review-mandatory. A
description is not a reviewable artifact: the reviewer cannot diff it, cannot check the
claims I chose not to make, and cannot anchor an approval to anything. Worse, my report
had made it *look* reviewed — Sec's first read said "two things look right" — which is
the state where an unreviewed surface acquires the appearance of clearance.

**The mechanism that produced it:** the surface lived on a *different branch* from the
one under review. Everything else in that exchange was about branch A; the new surface
was on branch B, stacked. The reviewer was never given branch B at all.

**How to apply:**
- When work lands on a branch the reviewer has not been dispatched, say so **in its own
  line**: *"X is on <branch> at <sha> and has not been dispatched to you."* Do not let
  it ride inside a summary of the branch that *was* dispatched.
- A stacked branch is a **separate review scope**, not a continuation of its base.
- Ask the coordinator to dispatch it; don't self-dispatch by narrating.
- ⚠ Describing a surface accurately makes this *worse*, not better — the more
  convincing the summary, the more likely it substitutes for the review.

## The root is MY-SCOPE standing in for BRANCH-SCOPE — it recurred within one session

Second instance, same shape: I told the coordinator *"`345` has no work left
outstanding."* Measured, two QA branches were stale against a predicate change I had
made **after** them — so the sentence was true of **my queue** and false of **the
branch**, and the veto actually cleared on one of those, not on the thing I was
chasing. A reviewer caught it; I had read the status off my own todo list.

**The discipline is the one already applied to counts: state what the claim is OVER.**
*"`345` is clear of Architect work"* and *"`345` is clear"* are different sentences, and
the second is the one that gets relayed. Before reporting a branch as done, enumerate
**every** branch stacked on or derived from it and check each against your latest change
— `git branch -r --contains <your tip>` and a grep for the thing you changed.

⚠ **Corollary worth stating separately, because it shrinks the ask:** when reporting
someone else's branch as stale, say *what* is stale. Here QA had already re-legged the
signature change; only the **predicate** legs were behind. "Stale" without a scope reads
as "discard and restart."

Related: [[feedback_state_what_the_count_is_over]],
[[feedback_anchor_confirm_requests_to_a_sha]],
[[feedback_relay_from_the_tree_not_the_report]],
[[feedback_a_filtered_grep_is_a_claim_about_the_filter]].

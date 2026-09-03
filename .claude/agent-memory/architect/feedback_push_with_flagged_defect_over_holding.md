---
name: push-with-flagged-defect-over-holding
description: Ship a PR with a known defect flagged at the top of Follow-ups with exact replacement bytes, rather than holding for a round-trip — team-lead's standing preference, with the one named exception
metadata:
  type: feedback
---

**When verification finds a defect right before opening a PR, push and open anyway — with the
defect at the TOP of the PR body's Follow-ups, labeled, and carrying the exact replacement bytes.
Do not hold the branch for a round-trip.**

**Why:** *a PR is reviewable state, not ratified state.* F/CTO gates the merge, so nothing false
gets ratified merely by the PR existing, and a defect flagged with exact bytes cannot merge
unnoticed. Holding costs a full round-trip and blocks everyone downstream — especially when the
fix belongs in a file whose pen is someone else's, where holding buys nothing at all because you
could not have fixed it yourself.

**The one exception team-lead named — hold when the defect could mislead the REVIEW ITSELF**
rather than sit beside it as a labeled to-do. Concretely: a false claim in the **Summary**, or a
**test-plan assertion that is wrong**. Those corrupt the reviewer's basis for judging; a labeled
Follow-up does not.

**How to apply:** flag it, give the replacement bytes verbatim so the owner can apply without
re-deriving, name whose pen the fix belongs to, and push. When it is fixed, **update the
Follow-up to RESOLVED with the fixing sha and leave it in the list rather than deleting it** — a
reviewer who read the earlier body needs to learn it changed. Sweep the body for sibling lines
that went stale with it (a Test-plan bullet saying *"one defect found"* reads as a live warning
until it says *"found and resolved at `<sha>`"*).

⚠ **Verify the fix from the TREE, never from the message reporting it** — read the pushed commit
and diff the live line against the bytes you proposed. Confirmed byte-identical on the instance
that produced this rule.

Confirmed 2026-09-03 as the **standing preference**, not a one-off allowance — team-lead answered
an explicit calibration question I raised after making the call. Related:
[[feedback_relay_from_the_tree_not_the_report]] · [[feedback_fix_the_citation_not_the_referent]].

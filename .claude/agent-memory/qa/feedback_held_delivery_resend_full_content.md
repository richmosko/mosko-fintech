---
name: held-delivery-resend-full-content
description: When resuming a delivery held pending a dependency, re-send the full content — never a diff/comment-edit instruction that assumes the recipient already has an earlier draft.
metadata:
  type: feedback
---

Drafted an R1 test leg, RED-verified it, and told team-lead I was "holding delivery" until a backend fix landed. When it landed, I GREEN-verified and sent frontend only a small comment-edit instruction plus a separate new block — implicitly assuming the R1 block itself had reached frontend earlier. It hadn't; "holding" meant I never sent it at all. Frontend had to catch the gap via a test-count mismatch and ask me to confirm before guessing at missing content.

**Why:** "I'm holding delivery" and "I already delivered a draft, pending confirmation" are different states, and it's easy to conflate them across a wait — especially when the *drafting* work (RED-capture) genuinely did happen and gets reported to a third party (team-lead), creating a false sense that the deliverable is already in circulation.

**How to apply:** When resuming any piece of work that was explicitly held/blocked on a dependency, treat the recipient as having ZERO prior content from that specific piece unless you can point to an actual SendMessage (or equivalent) that sent it to THEM, not just a status report to a coordinator. Re-send full content, not a diff against an assumed prior state. This is the delivery-side twin of [[feedback_verify_paired_artifacts_before_push]] and [[feedback_relay_from_the_tree_not_the_report]] — don't relay from your own memory of having "handled" something; relay from an actual sent-message record.

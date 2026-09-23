---
name: restate-before-push-even-on-an-unambiguous-correction
description: pushing directly off a teammate's correction request instead of restating it back to team-lead first, even when the fix is unambiguous
metadata:
  type: feedback
---

The protocol on this branch is restate → team-lead's confirm → ONE push, not restate-only-when-the-ask-is-ambiguous. Skipping the confirm step because a correction looks self-evidently correct (e.g. Sec pointing out a factual error with a clear fix) is still a protocol miss, even if it lands fine.

**Why:** team-lead (PR #882, 2026-09-22): Sec sent a correction request (the "pfin.asset RLS bypass" text was a defective check's own output, not an adjudicated finding); I pushed the fix directly rather than restating it back first. It happened to land correctly because both team-lead's own eventual wording and Sec's ask said the same thing — but team-lead named this explicitly as the failure class the restate step exists to prevent: "it landed right this time because both corrections said the same thing, but the restate step is what prevents the crossed-build class."

**How to apply:** any time a teammate (not just team-lead) sends something that reads like an instruction to fix and push, treat it as a *report to restate*, not a *ticket to execute*: send team-lead a one-line restatement of what you're about to change and why, wait for their confirm, then push once. This holds even when: the fix is small, the ask reads unambiguous, or the requester is someone with standing (like Sec) rather than team-lead directly. The cost of one extra round-trip is cheap; the cost of a crossed build (two agents' fixes landing inconsistently, or a "confirmed" fix that wasn't what team-lead actually wanted) is not. See also [[feedback_a_mid_pr_reruling_needs_a_measurement_before_it_becomes_a_brief]] for the adjacent rule about design re-rulings specifically.

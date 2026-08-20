---
name: a-ref-handed-over-is-not-yours-to-advance
description: Once you declare a sha review-ready, stop pushing to that branch until you know the review's state — unknown must be treated as blocking, because a hold issued after you act cannot reach you in time
metadata:
  type: feedback
---

**Rule.** The moment you hand a ref over as review-ready, **the ref stops being yours to
advance.** Do not push again to that branch until you know the review's state. **Unknown
counts as blocking**, not as clear.

**Why.** 2026-08-19, the ELEMENT PR (`085`). I reported `527a89c` as review-ready and
ready for Sec's merge gate. QA then delivered a v2 strengthening; I verified it, committed
it as `73962b4` and pushed. Team-lead had meanwhile ruled the v2 **HELD UNCOMMITTED**
precisely because Sec was mid-review at `527a89c` — and that ruling arrived **after** the
push. Confirmed from inbox ordering: push → my report → *then* the hold. Nothing told me
Sec had started.

Containment was cheap (Sec re-anchored to the new head, delta named, no round lost), but
the shape is what matters:

> **A hold is a message in flight. It cannot protect an action that is already moving.**
> A rule that needs no message — *I do not advance a ref I have handed over* — closes the
> case where nobody thought to issue a hold at all.

**How to apply.**
- After sending *"ready for review at `<sha>`"*, treat further pushes to that branch as
  gated. Ask, or wait for the verdict. **Do not infer "the review hasn't started" from
  silence** — silence is the state you cannot observe.
- Hold the bytes locally instead: verify, prepare the commit, and say the delta exists and
  is held. Additive strengthening is still a ref move.
- ⚠ **The reverse hazard is real and must be raised, not swallowed:** an approval names a
  ref, so if the reviewer stays pinned to the old sha, **their approval does not cover the
  head.** When a push has already crossed, the options are (a) re-anchor the reviewer to
  the new head and name the delta — usually right, cost is a re-read — or (b) leave the
  approval not covering the head, which someone must then remember at merge. **Never (c)
  force-push back to the reviewed sha**: it rewrites a shared ref others may have fetched,
  to undo a change nobody objects to on its merits.
- **Own your half when a coordinator offers to take the whole lesson.** Team-lead framed
  it as their missing ACK gate. The ACK gate is right *and* the ref-handover rule is mine;
  the two close different cases and the pair is stronger than either.

**The recurring cause underneath, seen three times on this one branch:** a measurement
taken against a ref that had already moved — Backend re-verifying an applied-clean claim,
QA diffing a head that had advanced, and this hold. **Anchor a claim to a sha read in the
same command as the claim.**

Related: [[reread-the-ref-before-dispatching]] · [[anchor-confirm-requests-to-a-sha]] ·
[[incoming-message-is-not-newer-state]] · [[verify-the-bytes-you-commit]]

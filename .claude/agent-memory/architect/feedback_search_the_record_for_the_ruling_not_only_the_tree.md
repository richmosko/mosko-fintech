---
name: search-the-record-for-the-ruling-not-only-the-tree
description: A correct mechanism measurement licenses no claim that the finding is NEW; novelty is a separate query against BACKLOG / docs/records / sitting logs, and skipping it produces well-evidenced escalations that are false in their framing.
metadata:
  type: feedback
---

**Before escalating a measurement as a FINDING, search the record for the RULING.** The tree
answers *what the code does*. It cannot answer *whether this is already known, booked, or
deliberate*. Those are different queries against different corpora — `BACKLOG.md` §7 seam-records,
`docs/records/`, sitting logs, `DECISIONS.md`.

**Why:** SELF-340 close-out. I measured that a reversal row's GL contra falls to Suspense instead
of cancelling its original's category, worked a correct example, and escalated it as a third
finding — recommending a merge hold on a PR and a code change. It was `BACKLOG` §7.28 item 1,
booked five days earlier, **citing evidence in a file I had written myself**. The absent annotation
was *ruled design intent*, and my recommended fix would have violated the ruling.

**How to apply:**
- The measurement being right is exactly what makes this dangerous — **the escalation looks
  well-evidenced, because the evidence is good. Only the framing is false**, and framing is what
  the reader acts on.
- Grep the record for the *mechanism's vocabulary*, not the issue id: the subject nouns
  (`reversal`, `Suspense`, `netting`) across `BACKLOG.md` + `docs/records/`.
- **Authoring a record does not make it recall-accessible.** Treat your own prior artifacts as
  external sources to be searched, never as things you would remember writing.
- ⚠ **Every downstream instruction inherits the bad framing while looking independently sound** —
  a merge hold, a teammate's blocked branch. Retract to *everyone* you told, name the withdrawal
  explicitly (not "some nuance"), and lift the holds in the same message.

The mirror of [[feedback_claim_about_the_world_vs_decision_about_what_we_do]] — I applied that
distinction in one direction and not the other. Related: [[feedback_upward_checking_norm]]
(the check that caught this came from above and was right) ·
[[reference_suspense_branch_absorbs_the_divergence]].

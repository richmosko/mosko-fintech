---
name: self-authored-label-hardens-into-fact
description: A label you invent for your own convenience acquires authority through repetition — and lands somewhere with no supersession mechanism, like a commit subject
metadata:
  type: feedback
---

**A label nobody gave you is a claim, and repeating it is how it stops looking like
one.** Track where every identifier in your output came from; if you cannot name the
message that assigned it, you invented it.

**Why:** Sec's AMBER verdict, 2026-08-17. Team-lead's dispatch said *"Yours is **C2**
plus the D1-class framing correction Sec folded into it"* and then enumerated EDITs
1 / 2 / 3 beneath it. EDIT 1 was always **C2's first third**. I wrote `C1` in a status
table — for symmetry, so three edits could line up against three condition labels — and
from there it hardened: status table → status table again → **a commit subject**,
`docs(sec): C1/EDIT 1 — …`. `C1` was real (the cluster REVOKEs, with F/CTO). EDIT 1 was
real. **The pairing was mine and it never existed**, which is precisely why it passed
every spot-check I ran: both halves are checkable and both check out.

> This is the false-composite shape arriving **self-inflicted** rather than inherited
> from a source. Same review also produced the inherited kind (I quoted a wrong figure
> byte-exactly from Sec) and the derived kind (Sec's correction contradicted its own
> enumeration). Three routes into one class in one review.

**⚠ The compounding half — where it landed.** A commit subject has **no supersession
mechanism**. A catalog comment takes a new comment-only migration; a file header can be
amended in place; an ADR can be superseded. A commit message can only be fixed by
rewriting history, which on a reviewed branch voids every approval and measurement
anchored to those shas — a worse trade than the label costs. Team-lead ruled *don't
rewrite*, correctly. The correction has to live somewhere a reader of `git log` will
actually encounter it: **the PR body**.

**How to apply:**
- **Before a label reaches a commit subject, grep the dispatch that assigned it.** Not
  your own earlier message — the teammate's. Self-citation is the failure, so your prior
  use is not evidence.
- **Suspect symmetry.** I invented `C1` because three edits *wanted* three labels. A
  tidy correspondence you did not receive is a tell, not a finding.
- **Rank surfaces by their correction cost** and spend care accordingly: commit subject
  (uncorrectable) > catalog comment (needs a migration) > file header / ADR (editable).
  The uncorrectable surface deserves the check the editable one can skip.
- Own it plainly and move on — do not tally it.

Related: [[prove-derived-text-against-its-source]] · [[count-over-history-vs-live-definitions]] · [[cited-precedent-transmits-its-retracted-half]]

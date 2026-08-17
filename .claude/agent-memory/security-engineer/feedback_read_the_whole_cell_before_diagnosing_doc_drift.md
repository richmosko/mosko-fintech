---
name: read-the-whole-cell-before-diagnosing-doc-drift
description: Before calling a doc entry "drifted", read the entry to its END and check whether it was CORRECT for a superseded design — and check whether my correction would delete the only coverage another surface has
metadata:
  type: feedback
---

**Two failures, both mine, both on the same SD-23 finding.**

**1. A truncated read produced a confident wrong diagnosis.** I reported SD-23's description as having
"drifted onto the wrong surface" after reading the first ~400 characters of its cells. Reading the
exposure cell to the END showed it specifies a **grain and a unique key** — *"2 rows per tenant
(income / expense); `UNIQUE (users_id, target_kind)`"* — which is a coherent, correct description of
what `planning_target` was **ratified to be at Lock 14**. Nothing drifted. **The entry was accurate
for a design that was later superseded and never revisited.** Supersession and drift look identical
from a partial read and call for opposite treatments: drift gets corrected, supersession gets
**retracted in place with the superseded text quoted** (the repo's own runbook §6.1 / ADR-016 D4
discipline), because the old text is the record of what was ratified.
**How to tell them apart:** does the old text describe something *internally coherent* (a grain, a
key, a shape)? Coherent = it was true of something. Incoherent/mismatched-in-part = drift.

**2. My correction would have DELETED the only coverage a third surface had.** The §2.3.2
income/expense classification is not "missing an SD entry" — it is *sitting inside SD-23*. Rewriting
SD-23 for the new surface without the sibling slot landing removes it silently. **Before editing a
classification/catalog entry, ask what would become UNCOVERED by the edit**, not only what becomes
correct. Where the sibling decision is someone else's call, the shape is: rewrite, and carry an
explicit **marked, dated pointer** that the displaced content is un-homed pending that decision —
deferral made visible, never folded into a discharge. Same principle as refusing to let a gate absorb
the half it did not prove.

**Bonus finding from the same trace, worth the pattern:** a locked ADR enumeration and the working
list had diverged — Decision 18 still reads *"four per-domain tables"* while `BACKLOG.md` asserts
five, **citing Decision 18's "four" verbatim as its own source in the same bullet**. Every downstream
artifact was copying the working list. **When an entry cites a canonical count and then states a
different one, the divergence is inside a single sentence and is free to catch — grep the canonical
text for the enumeration whenever a doc asserts family membership.**

**How to apply:** on any doc-catalog finding — (1) read the entry to its end before naming the defect;
(2) ask whether it was true of a prior ratified design; (3) ask what my edit un-covers; (4) if the
answer is non-empty and the fix is another agent's call, make the gap visible in the same edit rather
than deferring it. Related: [[stated-invariant-stronger-than-the-contract]] and
[[clearance-conditions-must-absorb-my-own-recommendations]].

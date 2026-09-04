---
name: a-ruling-makes-claims-about-the-tree
description: A ruling and its AC block assert facts about the tree — a named watcher, a premise, an open question. At the pre-ruling, verify each as a CLAIM; the named watcher may not exist, the premise may be falsified, and the "open" question may already be ruled and landed
metadata:
  type: feedback
---

A ruling is not only a decision. Its text carries **claims about the tree**, and those claims are
what the build will stand on. At a pre-ruling re-read, grade them as claims — separately from
grading the decision.

**Why:** at the SELF-268 pre-ruling (the §2.5.4 NAV composition flip, a one-way door) three
different classes of claim in R3 and its AC block were wrong, and none of them touched what was
ruled.

**Three classes, each with its own check:**

1. **A NAMED WATCHER may not exist, or may exist and be unable to fail.** R3 rider 0 and AC 1a both
   read *"SELF-226's foot-to-headline reconciliation is the watcher that goes red if the headline is
   left behind; it stays in the battery."* Measured: `grep -rn "composition.nav" api/src` returned
   **one** hit — a render. No test compared the headline value to the foot value. The nearest
   candidate rendered a **fixture** and asserted a formatted string, echoing the headline only in
   its test title. **A one-way door had been ruled with a safety net that was a formatting
   assertion.** ⚠ Grep for the watcher by the VALUES it must compare, not by the name the ruling
   gives it — the name is usually a test title, and a test title is prose.

2. **A PREMISE may be falsified on the tree, and usually already corrected somewhere else.** Two AC
   premises were false at the anchor: *"`051`/`049` carry no volatility declaration"* (a migration
   had pinned them `stable` two dozen migrations earlier) and *"the current comment asserts the
   identity"* (the immediately-preceding migration had already rewritten it). **Both had already
   been corrected in the execution log and in the ADR — the AC block was the stale copy.** The
   INSTRUCTION survived in both cases; only the reason died. Say so in that shape: *"the instruction
   stands, the reason does not"*, so nobody drops the instruction along with its dead premise.

3. **An "open" question may already be RULED and LANDED.** Architect's memo offered A/B for the
   unavailable-scalar case. (A) was ruled in the execution log, recorded in the ADR's Consequences,
   and quoted in a **merged migration header**. A memo re-opening that is a re-opening — it needs an
   ADR amendment and an F/CTO call, not a design decision taken inside the issue. **Before answering
   an A/B, grep the execution log, the ADR body, and the merged migration headers for the option
   names.** Answer the merits anyway, but say which act you are performing.

**The tell that ties all three together, and it generalizes past this issue:** a ruling written at a
sitting is written against the tree **as of that sitting**. Migrations land between the sitting and
the dispatch. So a pre-ruling re-read is not ceremony — the interval is exactly where these three
classes are minted. **Anchor the re-read to a sha, re-measure every tree-claim in the same turn as
writing the finding, and grade the ruling's decision and the ruling's facts separately.**

**The residual worth naming:** the AC block is the artifact the builder actually reads. Corrections
that live only in the execution log and the ADR do not reach it. When drifts are premise-class, the
escalation is *"the AC block needs a correction pass before dispatch, not after"* — otherwise a
correct ruling ships on a false premise, which is
[[my-review-measurements-become-quoted-sources]]'s failure one layer up.


**The fourth class, found at the SELF-268 freeze — a MIGRATION COMMENT makes claims about the
CONSUMER, and the consumer is in another language in another directory.** `105`'s `comment on
function` asserted *"the consumer's buildup ladder renders all three as subtractions."* The shipped
consumer negated **one**, deliberately, with two dedicated unit regressions pinning that
(`flippedKeys` equals `['debt']`). Nothing was red: **the code and its tests were internally
consistent, and the SQL and its battery were internally consistent — the contradiction lived only
ACROSS the two, in prose, which no suite reads.**

**Three things make this class worth a standing check.**
- **The direction of harm.** The comment did not merely misdescribe; it *instructed* the second
  sign flip that the same comment's next sentence warns against. An artifact written to prevent a
  defect can specify it.
- **The fix window is the shortest in the repo.** A `comment on …` has a database representation
  and is corrected only by emitting a NEW migration. So a cross-artifact prose contradiction that
  would be trivial anywhere else is **pre-merge-only** here — which is the argument the migration
  itself was making about a different comment three paragraphs earlier.
- **It is invisible to the natural review order.** Reading the migration, then the app, then the
  battery, each looks right. **Read the migration's claims ABOUT THE CONSUMER as a checklist, then
  open the consumer and grade each one.** Same for the reverse: the app file's header also asserted
  the convention, in the opposite words.

**How to apply:** on any migration touching a rendered figure, grep its header and `comment on` for
sentences whose subject is *the consumer / the caller / the ladder / the surface* — those are claims
about files the migration does not own. Verify each against the consumer in the same pass. And when
the two disagree, **say which artifact is wrong rather than which is right**: the wrong one may be
the one with the shorter fix window, and that decides the ordering of the remediation.

**Also from that pass, on severity honesty:** the sign question underneath it (should the ladder
negate one row or three?) was a **legibility** judgment on a money surface, not a security
requirement — and M-3's actual hazard, a display-shaped value feeding back into the computation, was
structurally CLOSED because the call was DB→DB. Saying that first, before the flag, is what kept the
flag from reading as a veto in disguise. **Separate "the mechanism I named is closed" from "a
related defect remains" explicitly** — see [[hazard-mechanism-vs-reachability]].

Related: [[assertion-with-no-watcher]] · [[grep-the-existing-battery-before-scoping-a-remediation]] ·
[[a-citation-has-four-falsifiable-axes]] · [[verify-the-cited-source-subsection-not-the-headline]] ·
[[off-tree-fcto-rulings-live-in-linear]].

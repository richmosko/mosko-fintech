---
name: a-discharge-can-go-stale-against-its-own-pr
description: Two conditions discharged in one round can contradict each other — one file's fix cites the other file's defect as still-open. Grade the discharge set as a SET, cross-reading every condition's file against every other's.
metadata:
  type: feedback
---

**Grade a multi-condition discharge round as a SET, not condition-by-condition.** After each
condition passes on its own, re-read every discharging file for claims **about the other
conditions' files**. A fix authored against the pre-round tree cites defects the same round removed.

**Why:** PR #671 round 2 (2026-09-08). C5 (Architect) corrected `055`'s CONTRACT block in-place.
C3 (DevOps) wrote runbook §6.2 the same round, containing: *"Do not follow `055`'s CONTRACT block for
either role — Sec grades it SUPERSEDED and actively hazardous... Architect corrects it before the
Phase-7 deploy pass reads it."* Both landed in the **same commit range**. The runbook now tells a
deploy operator to distrust a block that is correct and names an owed correction that already landed.
Each condition graded clean alone; only the cross-read caught it. Same round, second instance: a
condition-C3 fix to the runbook's TZ-1 login-role enumeration left the **identical** enumeration
uncorrected in `docs/records/v1final/production-standup.md` row 10 — a live, DevOps-owned deploy-gate
record, not a frozen one (check the header: "fill at events" / "opens at first deploy" means LIVE).

**How to apply:** after per-condition grades, before the verdict, run one pass asking of each
discharging file: *does it make a claim about any OTHER file in this diff, or about a defect this
round fixed?* Grep the diff's file basenames across the diff's own contents. Two named smells:
- a fix that says another artifact "is hazardous" / "must still be corrected"
- an enumeration corrected in one artifact whose duplicate lives in a record or a per-directory
  `CLAUDE.md` — see [[feedback_a_correction_pass_inherits_the_reviewers_filter]].

Also check **dates on supplied text**: three artifacts in this round were stamped 2026-09-09 on
2026-09-08 — a UTC-vs-repo-clock read. Repo convention is `-0700`; see
[[project_db_clock_is_utc_repo_clock_is_pdt]] and [[feedback_supplied_verbatim_text_ships_unfiltered]].

## ⚠ THE SHARPEST INSTANCE — MY OWN POSTURE ENTRY, AND THE HASH CHECK COULD NOT SEE IT (2026-09-17)
My §4.2 entry recorded an sshd write-ordering hazard as **OPEN**. By the time its branch was brought current,
**`main` carried the fix — landed in the PR I had graded GREEN two messages earlier.** Merging would have put a
security posture entry on `main` asserting an open hazard that the same session had already closed.

⚠ **The merge check was CLEAN and would have passed it.** Parents correct, both diffs hashing identically,
no both-sides file. **A blob/hash check verifies that nothing MOVED; it cannot verify that what did not move is
still TRUE.** For a document whose content is *claims about the tree*, those are two different questions and only
one of them is automated.

**How to apply:**
- **Before pinning MY OWN doc PR, re-read the landed text for claims the session has since falsified** — the
  trigger phrase is *"did anything I asserted as OPEN / UNVERIFIED / NOT YET get closed since I wrote it."* My
  entries are dense with dated status claims, which is what makes them useful and what makes them rot fast.
- **The correction shape is the same one I demand of others:** mark it CLOSED with the sha and PR, quote what it
  previously said, and ⚠ **state the RESIDUAL so the fix is not over-read** — here the fix narrows the lockout
  window to milliseconds rather than eliminating it, and saying only "closed" would have overstated it.
- **A long review session is the risk factor.** The gap between authoring a finding and merging its record is
  exactly the window in which teammates fix the finding. **The faster the team is, the staler my drafts get.**

## ⚠⚠ SECOND INSTANCE IN CONSECUTIVE TURNS — so the cause is my AUTHORING HABIT, not my checking
The same entry went stale a second time before it could merge: the header still read **"TWO ITEMS OPEN AT THE
TIME OF WRITING"** while the body already marked one CLOSED (a header contradicting its own body), and the
second item still said *"until that environment exists with at least one required reviewer, the gate is named
and not enforced"* — **after I had personally verified by API that it existed.** The merge check was clean both
times.

**The fix is upstream of the check. Author status as DATED OBSERVATIONS, not as OPEN-ITEM LISTS:**
- *"measured OPEN on 2026-09-17"* ages **honestly** — it stays true forever and invites a re-measure.
- *"is OPEN"* / *"TWO ITEMS OPEN"* / *"until X exists"* ages into a **false claim**, and a header that counts
  open items rots the moment any one of them closes.
**On a fast-moving workstream the team closes my findings faster than I merge the record of them**, so an
open-item list is stale by construction, not by accident.

⚠ **And when closing one, do not flip it to a bare "closed" — state the RESIDUAL, or you overstate in the other
direction.** Here: the environment gate is satisfied **in fact** and still procedural **in kind** — deleting the
environment would silently un-gate the job and nothing watches for that. **"Closed" alone would have hidden the
thing actually worth keeping**, and the residual is usually the sentence that earns the entry its place.

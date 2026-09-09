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

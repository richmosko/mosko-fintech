# V1.4 execution log — rulings under F/CTO delegation

**Delegation (F/CTO, 2026-09-03, verbatim):** *"I would like for you to execute V1.4 to completion. You are authorized to go with your rec for any decisions that come up... and are authorized to merge prs."*

**What that changes.** For the V1.4 build loop, the team-lead recommendation stands in for the F/CTO ruling at every decision point — including the SELF-263 tax-value inventory session, which the sitting log (R5) described as F/CTO time. Every such ruling is recorded here with provenance **TEAM-LEAD RULING UNDER DELEGATION** per [ADR-063](../../../DECISIONS.md#adr-063) Decision 3, never flattened into "F/CTO ruled." The reversal window on each is open until V1.4's close-gate merges; F/CTO can reverse any entry by saying so. Merges: on green, by team-lead, per the same delegation; doc-only and feature PRs alike.

**What it does not change.** Sec's veto stands. The live walk-through gate stands on every user-facing PR. Sec joint-review is mandatory on all ten issues per the sitting log's map. The ruled dispatch order is [`../v14-preflight/sitting-log.md`](../v14-preflight/sitting-log.md) § *Ruled dispatch order*; the ACs are the re-derived text on each Linear issue (applied 2026-09-03 from `rederived-acs.md` at `762f793`).

**Migration numbers reserved up front** so three parallel branches do not collide: `100` = SELF-263 seed delta + `tax_relevant` column comments · `101` = SELF-259 bracket tables · `102` = SELF-267 `tax_jurisdiction` + YTD-Paid primitive + the `051` leaf-set exclusion. Later numbers allocate at dispatch.

---

## Rulings

_(entries appended as they are made; one per decision; each names the options weighed and the losing side)_

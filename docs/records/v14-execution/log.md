# V1.4 execution log — rulings under F/CTO delegation

**Delegation (F/CTO, 2026-09-03, verbatim):** *"I would like for you to execute V1.4 to completion. You are authorized to go with your rec for any decisions that come up... and are authorized to merge prs."*

**What that changes.** For the V1.4 build loop, the team-lead recommendation stands in for the F/CTO ruling at every decision point — including the SELF-263 tax-value inventory session, which the sitting log (R5) described as F/CTO time. Every such ruling is recorded here with provenance **TEAM-LEAD RULING UNDER DELEGATION** per [ADR-063](../../../DECISIONS.md#adr-063) Decision 3, never flattened into "F/CTO ruled." The reversal window on each is open until V1.4's close-gate merges; F/CTO can reverse any entry by saying so. Merges: on green, by team-lead, per the same delegation; doc-only and feature PRs alike.

**What it does not change.** Sec's veto stands. The live walk-through gate stands on every user-facing PR. Sec joint-review is mandatory on all ten issues per the sitting log's map. The ruled dispatch order is [`../v14-preflight/sitting-log.md`](../v14-preflight/sitting-log.md) § *Ruled dispatch order*; the ACs are the re-derived text on each Linear issue (applied 2026-09-03 from `rederived-acs.md` at `762f793`).

**Migration numbers reserved up front** so three parallel branches do not collide: `100` = SELF-263 seed delta + `tax_relevant` column comments · `101` = SELF-259 bracket tables · `102` = SELF-267 `tax_jurisdiction` + YTD-Paid primitive + the `051` leaf-set exclusion. Later numbers allocate at dispatch.

---

## Rulings

_(entries appended as they are made; one per decision; each names the options weighed and the losing side)_

### E1 — `bracket_rate` unit = FRACTION (`0.22`, bound `<= 1`) · TEAM-LEAD RULING UNDER DELEGATION · 2026-09-03
SELF-259 AC 2 leaves the unit to the author with the requirement that it be stated in words in the column comment. Ruled fraction: the PRD's §2.5.3 arithmetic multiplies taxable income by the rate directly, and a fraction needs no ÷100 at the one consumer (SELF-262). **Losing side:** percent (`22`) reads more naturally on the §2.5.2 settings editor and matches how the IRS publishes brackets — the editor converts at the boundary (SELF-265) and the seed (SELF-260) is written in fractions. Recorded in `101`'s header by Architect.

### E2 — SELF-259's replace-all endpoint ships in the SAME PR as `101`, as a LABELED separate commit on a sibling branch · TEAM-LEAD RULING UNDER DELEGATION · 2026-09-03
AC 6 says "split it or label it." Ruled label: one PR keeps the DDL and its only writer reviewable together (Sec reads the endpoint's tenant handling against the RLS it relies on), and a second PR would re-open the joint-review on the same surface. **Losing side:** a split PR gives the migration a cleaner Sec record and lets `101` land before the endpoint is green. Mitigation: Backend's commits are prefixed `feat(api)` and the PR body lists the two halves separately.

### E3 — The `051` leaf-set exclusion lands in SELF-267 (`102`), not in SELF-268 · TEAM-LEAD RULING UNDER DELEGATION · 2026-09-03
The re-derived SELF-267 AC 2a already places it there; ruled explicitly because SELF-268 also replaces `051` (the tax scalars), so `fn_nav_composition` is CoR'd twice across the milestone. Grounds: R3 rider 0b makes the designation's default-state hazard part of SELF-267's walk ("mark → BOTH figures move"), which is unobservable unless the exclusion is live when the designation ships. **Losing side:** one CoR of `051` at SELF-268, fewer signature-preserving replacements to verify; it would leave the R3 E-2 double-count latent between the two merges while the tax literals are still `0` — not a live defect, but a walk that cannot see its own hazard.

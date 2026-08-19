---
name: gl-brainstorm-pm-positions
description: PM's 2026-08-18 inputs to the taxonomy-vs-GL brainstorm — grain ruling, S1 recommendation, rename conditions, scope table
metadata:
  type: project
---

PM positions delivered 2026-08-18 into the F/CTO taxonomy-vs-GL brainstorm (asymmetric split ratified; ADR draft in flight). Deliverable was `temp/pm-gl-brainstorm-inputs.md` (gitignored — this memory is the survivor).

**Positions taken (verify against the landed ADR before reuse):**
1. **Grain (Q3a):** Sub-Cat-grain income/expense reporting is V1 by §2.3.2/§2.3.3/§2.5.1 — but no story requires GL-native derivation, and Sub-Cat is reachable at read time → ledger_account / Option-2 stage 2 gated **V2**; GL-native P&L booked to BACKLOG §5 candidacy.
2. **Sequencing:** recommended **S1** (split→element) with flip trigger: if the split isn't landable within the V1.2 window, flip to S2. Premise: SELF-242 keeps the milestone fed while the SELF-239 §2.2.2 AC rework waits.
3. **Rename ('Equity'→'Marketable Securities') supported V1 with two ratify-shaped conditions:** (i) §3.3 label-mapping footnote (Cash-row-footnote precedent); (ii) explicit F/CTO ruling on §2.6.2's four V1-fixed sub-section labels (parity-exact AND Cat-aligned — rename breaks one either way).
4. **Scope table:** split V1 · element V1 · posting_template V2 (the smuggle risk) · Equity::Distribution/Contribution seeding HOLD · M-hier not V1.x.

**Why:** the PROVISIONAL-AC recurrence ([[ac-signatures-copied-not-composed]]) drove S1 — write the held ACs once against the final shape.

**How to apply:** when the split/element/rename PRs or the PRD-recalibration pass arrive, these are the standing PM positions unless F/CTO ruled otherwise — read the ADR + session outcome first. ⚠ PRD 'Equity' count: 18 is LINES, 24 occurrences; "US Equity" (market term, not rename targets) = 12 case-insensitive (Architect's correction at close — my 11 was case-sensitive and missed lowercase "US equity" at line 229) — the PRD sweep is per-occurrence adjudication. Also open at handoff: §3.3 Liabilities-superset clause cites §2.2.2's "V1 extension" scope, falsified by the 08-18 assets-only ruling — re-word with the held rework. Related: [[v12-manual-bucket-rehome]], [[cash-bucket-granularity]].

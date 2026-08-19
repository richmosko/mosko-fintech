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

**How to apply:** when the split/element/rename PRs or the PRD-recalibration pass arrive, these are the standing PM positions unless F/CTO ruled otherwise — read the ADR + session outcome first. **Adjudication DELIVERED 2026-08-19** (ADR-058 items 10–12): RENAME 7 (224/552 need incumbent-attribution rewords) · KEEP 17 · RIDER-B-dependent 5; lines 320/324 resolved RENAME on in-sentence evidence; riders (a) footnote + (b) Option-A both F/CTO-RATIFIED 2026-08-19 (brainstorm-log decisions 10/11); PRD landing authored same day as **PR #503** (`meta/prd-marketable-securities`, docs/PRD only, 11+/10−) — **merge-gated behind feature PR #502** (schema first). Verify #503's merge state live before citing. Count decomposition settled: 24 capital 'Equity' / 11 "US Equity"; case-insensitive US-equity = 12; full `equit*` universe 29 tokens / 21 lines — always state the scope. Also open at handoff: §3.3 Liabilities-superset clause (PRD 629) cites §2.2.2's "V1 extension" scope, falsified by the 08-18 assets-only ruling — belongs to the held §2.2.2 rework, NOT the rename PR. Related: [[v12-manual-bucket-rehome]], [[cash-bucket-granularity]].

# mosko-fintech — MILESTONES

Compact state ledger for mosko-fintech. **Top section (above `## Roadmap`) is auto-loaded by the SessionStart hook** per [ADR-009](DECISIONS.md#adr-009) Decision 6 (compact-ledger auto-load model — `MILESTONES.md` is the auto-load anchor; everything else consult-on-demand). Detail below the cutoff is consult-on-demand.

**Conventions:**
- Milestones tracked at two scales per [ADR-009](DECISIONS.md#adr-009) Decision 7: **meta-process** (M0 / M1 / M2 / M3 = R / P / I+V / Deploy) and **product** (V1.0 / V1.1 / V1.final / V2-X).
- Sprint = Linear cycle (orthogonal pacing wrapper, not a hierarchy level).
- Feature = Linear Issue = one PR = one I↔V loop.
- Last updated: 2026-05-26 (post Step-4 in-session drilling; **🎉 ALL 16 SUBSTANTIVE LOCKS CLOSED + CANDIDATE P3 RESOLVED** — Flag #11 just landed; Step 4 drilling COMPLETE; **Step 4 close work is the next phase** — full state at [`temp/step-4-locks-log.md`](temp/step-4-locks-log.md)).

## Project / Initiative

| Field | Value |
|---|---|
| Project name | mosko-fintech |
| Linear Initiative | _TBD — created at Phase 4 entry per ADR-009 Decision 7_ |
| Status | Active |
| Owner | F/CTO |
| Target ship date | _TBD — V1 sub-version sequencing defined as M1's "Populate product milestones" output_ |
| Health | On track |

## Current Phase

| Field | Value |
|---|---|
| **Phase** | Phase 1 — Product Definition (PRD) |
| **Step** | Step 4 (Architectural overview consult; Architect lead; Phase 3 entry gate) — **DRILLING COMPLETE 2026-05-26**; Step 4 CLOSE WORK is the next phase (ADR batch + §SECURITY HTML edits + PRD HTML edits + WORKFLOW lessons-learned + BACKLOG V2+ entries + phase-transition prompt). |
| **Locks closed** | **🎉 ALL 16 SUBSTANTIVE FLAGS CLOSED + CANDIDATE P3 RESOLVED** — Flag #1 / P2 / E1a / Flag #2 / E2 / P1 / Flag #3 / Wave 1 step 2 (#10 + #12) / Flag #4 / Flag #5 / Flag #6 / Flag #7 / Flag #8 / Flag #9 / Flag #13 / Flag #11; P3 disposition = V1-default (ingest + no UI). **Lock 9 amended at Lock 15** (re-introduce `account_trans.created_at` as IMMUTABLE post-INSERT). Full alphanumeric track + Waves 1-5 closed. |
| **Locks remaining** | **NONE.** Drilling complete. |
| **Next pick** | **Step 4 CLOSE WORK** — ADR batch (~19 entries) + §SECURITY HTML edits (SD matrix 14→23; RT catalog +10 entries; multiple §4.x annotations) + PRD HTML edits (§7.3 V1-dormant `account_users` bullet; `users_id` sweep per Flag P1) + MILESTONES Phase 1 → complete + WORKFLOW lessons-learned subsection + BACKLOG entries (V2+ FMP cost-saving levers; V2+ stock-screening UI surface) + phase-transition prompt per `docs/handoff-prompts.md`. F/CTO's choice on pacing — single-PR mega-close vs decomposed-PR sequence per `feedback_late_phase_density_overload`. |
| **Authoritative state file** | [`temp/step-4-locks-log.md`](temp/step-4-locks-log.md) — full lock rationale + Sec verdicts + 8 meta-patterns + Sec mod inventory + pending Step 4 work. **Consult this file as first stop to resume.** Gitignored per `feedback_working_artifacts_temp_not_docs`; local-only working artifact. |
| **Team task tracker** | `~/.claude/teams/phase-1-step-4/` team durable in-session. **13 Phase 3 carry-over tasks** booked (#11/#13/#15/#16/#17/#20/#26/#29/#32/#33/#34/#35/#36) — each with full Sec-mod descriptions for Phase 3 implementation. Team mode active per ADR-003; spawn teammates via `Agent(team_name="phase-1-step-4", subagent_type=..., name=...)`. |
| **Candidate ADRs for Step 4 close** | 4 project-convention ADRs identified (locks-log meta-patterns §6 / §7 / §8 + candidate §10 strengthened at Lock 14 + further-strengthened at Lock 15): (a) **privileged-context-write discipline** for non-JWT writes; (b) **immutable + INSERT-new-version discipline** for audit-class surfaces; (c) **cross-tenant FK-bypass attack family** — matched-tenant validation required on every FK-shaped reference (incl. INTEGER[] arrays); strengthened to 4 instances at Lock 12 + candidate §9 extension (immutability triggers fence tenant anchors + audit-load-bearing columns); (d) **candidate §10 — defense-in-depth fencing across surface boundaries + schema-level orthogonality awareness** — at Lock 13 (privileged-context: code + CI + JWT shape + infrastructure-credential-presence) + Lock 14 (user-facing: Zod strict-mode + mass-assignment fence + numeric adversarial battery + RLS WITH CHECK + DB-trigger backstops) + **Lock 15 (schema-level: drop-column corrections must be evaluated against all downstream PRD commitments, not just immediate-driver concern)**. Plus per-lock ADRs (~15 candidates from the 15 locks) + **ADR-008 amendment for Lock 9 correction #3 partial-reversal**. |
| **§SECURITY HTML edits accumulated** | SD-matrix expansion 14→23 (SD-14 plaid_item_state_history; SD-15 acct_number; SD-16 reconciliation_event HIGH; SD-17 holdings_checkpoint; SD-18 reconciliation_event_trans; SD-12 monthly_report HIGH; plus SD-00 immutability addendum + **SD-00 light addendum per Lock 15 re-introduced `created_at` column**; SD-12 child sub-class addendum per Lock 12; +2 per Lock 13: pfin.plaid_sync_audit table + PDF-worker-signing-key credential-class; +SD-23 per Lock 14 + SD-04/SD-11 row revisions per Lock 14 mod #5). RT catalog +9 entries (RT-16 cost-basis cascade; RT-17 reconciliation surfaces append-only; RT-18 immutability invariant suite; RT-19 read-time composition tenant-scoping; RT-20 fourth-instance FK-bypass; RT-21 PDF worker JWT verification HIGH + RT-22 PDF worker container credential audit medium per Lock 13; RT-23 planning_target write-path medium + RT-24 tax_bracket write-path medium per Lock 14; **+RT-25 as-of-date adversarial-input medium per Lock 15 — closes Sec Task #23 forward-looking comment #1**). RT-13 amendment (light) for SECURITY INVOKER read-path-only fence; RT-09 + RT-10 amendments per Lock 13. §4.2 three-surface external-API inventory + webhook-bypass-risk annotation + scheduled-poll annotation per Lock 13 + light V2+ tax-API ingestion forward-compat note per Lock 14 mod #8. §4.3 axis (vi) Coolify-container-boundary + infrastructure-layer fence framing per Lock 13 mod #2. §4.6 PCI-DSS scope posture sub-section + four-surface reconciliation audit family annotation + trans-table-as-audit-log composition annotation + snapshot-account-name audit sub-family per Lock 12 + Plaid sync audit sub-family per Lock 13. **+ADR-008 amendment for Lock 9 correction #3 partial-reversal (Lock 15 mod #1).** |
| **PRD HTML edits accumulated** | §7.3 V1-dormant `account_users` bullet (Flag P2). `tenant_id` → `users_id` sweep per Flag P1 (~8–15 edits across §1.4 + §7.3 + §SECURITY §4.1 axes (i)–(iv) + §4.4 SD matrix + ADR-008 Decision 1). |
| **Outer category** | Research (per ADR-009 Decision 2 — mosko Phases 1 + 2 sit under template's Research outer frame) |
| **Started** | 2026-05-09 (Phase 1 entry); 2026-05-25 (Step 4 in-session drilling start) |
| **Driver agent** | Architect (lead Step 4; PM consulted at P-flags; Sec at every architectural lock — Sec found 23+ V1-ship-blockers across reviews including 4 instances of the cross-tenant FK-bypass attack family + 8 distinct chain-attack catches Architect missed; Lock 13 added the future-regression-fence catch via infrastructure-layer credential-absence; Lock 14 added app-layer mass-assignment + numeric-input adversarial-battery catches at the first user-facing direct DB write surface; Lock 15 added the schema-level orthogonality-awareness catch — Lock 9 correction #3 dropped a column needed by Flag #13's §2.3.3 commitment, surfaced + amended at Lock 15) |
| **Gate criteria** | Step 4 close work landed (ADR batch + §SECURITY HTML edits + PRD HTML edits + MILESTONES + WORKFLOW lessons-learned + BACKLOG V2+ entries + phase-transition prompt per `docs/handoff-prompts.md`) → Phase 1 closes; Phase 3 (Technical Architecture) becomes available (skipping Phase 2 fast-track TBD at phase transition) |
| **New memory entries this session** | 4 — `feedback_team_mode_default` (spawn via team_name), `feedback_incumbent_exceeds_v1_review` (P-flag pattern when incumbent exceeds V1), `feedback_horizontal_rule_after_fcto_input` (formatting), `reference_pfin_back_etl` (sibling Python ETL on Coolify with BLS + FMP APIs already in production) |

## Active Feature

| Field | Value |
|---|---|
| Feature | _Step 4 close work — ADR batch + §SECURITY HTML edits + PRD HTML edits + WORKFLOW lessons-learned + BACKLOG V2+ entries + phase-transition prompt. Drilling complete; close work is the gate before Phase 1 ends + Phase 3 opens._ |
| Linear issue | _N/A — Linear activates at Phase 4 entry_ |
| Branch | _N/A — drilling work in `temp/`; doc commits via `meta/` branches per ADR-009 Decision 9_ |
| Status | _Active 2026-05-26. Team `phase-1-step-4` durable in-session. Drilling complete. Resume via consulting [`temp/step-4-locks-log.md`](temp/step-4-locks-log.md). Step 4 close work to begin per F/CTO direction (single-PR mega-close vs decomposed PR sequence)._ |

## Recent activity (last 7 days)

- **2026-05-26 (Flag #11 close — FINAL FLAG + P3 resolved)** — Phase 1 Step 4 drilling **COMPLETE**: **Flag #11 / Lock 16 closed** (Wave 5 — cost feasibility) + **candidate P3 disposition** (V1-default: ingest + no UI). Locked **Outcome 1** (confirm ≤$50/month V1 cost target; no PRD revision) + **FMP path (a)** (keep starter plan) + **P3 V1-default** (pfin_back_etl ingestion continues; stock-screening UI deferred to V2+; ADR documents disposition). Architecture confidence HIGH on Outcome 1 after F/CTO clarified three v1-frame bugs: FMP is fixed-cost (feature-independent); Plaid is fixed-cost (per-account, locked); VPS is actual feature-driver (Hetzner cax21 €9.50/mo baseline reframes everything). V1 marginal cost projects $15-$65/mo; mid-range ~$35/mo (well under target). Only Phase 3 entry-gate unknown: Plaid production-tier minimum (sales-call task). PM consult SKIPPED (no scope-cut to vet); Sec review SKIPPED (no architectural re-touch; no V1-SHIP-BLOCK security surface in cost-feasibility). BACKLOG entries queued for V2+ FMP cost-saving levers (free tier; Yahoo/Google scrape) + V2+ stock-screening UI surface. New `reference_hetzner_cax21` memory entry. **All 16 substantive flags closed; Step 4 close work is the next phase.**
- **2026-05-26 (Flag #13 close + Lock 9 amendment)** — Phase 1 Step 4 drilling continued: **Flag #13 / Lock 15 closed** (Wave 4 step 3 — as-of-date semantics). Locked Option A (app-layer parameter threading with dual-column `transaction_date <= $1 AND created_at <= $1` filter) + Sec's 9 mods (2 V1-SHIP-BLOCK + 7 advisory; mods #7 + #7b added + mod #2 tightened + mod #5 strengthened in Sec addendum post-initial-ratify). **Sec's load-bearing finding (8th chain-attack catch this Step) surfaced a Lock 9 schema cascade:** Architect's worked example for Lock 5 reverse-and-replace composition relied on `account_trans.created_at`, which Lock 9 / Flag #4 F/CTO correction #3 had dropped. F/CTO ratified **Lock 9 amendment** at Lock 15 mod #1 — re-introduce `account_trans.created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()` IMMUTABLE post-INSERT (inherits Lock 10 mod #8 trigger pattern). ADR-008 amendment required at Step 4 close documenting Lock 9 correction #3 partial-reversal. Lock 9 entry annotated inline with amendment marker. Sec addendum mods: tightened DATE range bound `[2015-12-01, CURRENT_DATE]` (NAV anchor floor + no future dates; reduces timing-attack signal); server-derived-only fence for §2.6 paths (`data_as_of` NEVER client-asserted for cron + on-demand monthly_report; §2.3.3 drill-down is the sole client-toggle surface); Lock 11 mod #2 audit-log shape extension (new `data_as_of DATE` field; Architect's "no schema delta on monthly_report" preserved — audit-log row carries the forensic record); PDF worker JWT integrity (NO `data_as_of` claim; V1 app reads frozen value from audit-log row server-side). New RT-25 medium (closes Sec Task #23 forward-looking comment #1; includes timing-attack measurement sub-test). Candidate §10 meta-pattern strengthened: schema-level orthogonality awareness (drop-column corrections must be evaluated against ALL downstream PRD commitments, not just immediate-driver concern). Task #36 booked for Phase 3 carry-over.
- **2026-05-26 (Flag #9 close)** — Phase 1 Step 4 drilling continued: **Flag #9 / Lock 14 closed** (Wave 4 step 2 — settings store; first user-facing direct DB write surface outside §2.4). Locked Option B (4 per-domain tables fully split: `planning_target` + `tax_bracket_schedule` + `tax_bracket_row` + `owner_identification`; greenfield) + Sec's 9 mods (2 V1-SHIP-BLOCK + 7 advisory; mod #9 added in Sec addendum post-initial-ratify covering `updated_at` UPDATE-refresh trigger via `fn_refresh_updated_at()`). Load-bearing Sec catch (mods #1 + #2): app-layer mass-assignment fence (Zod `.strict()` + `users_id` from `auth.uid()` not `req.body`) + numeric-input adversarial battery (NaN/Inf/currency-string regex/overflow/scientific-notation reject) — 7th chain-attack catch in joint flags. v1.2 drill landed at 344 lines including (A) audit-trail-shape + (B) owner-id-no-Lock-12-parallel + (C) tax_year transition + (4) Lock 11 cron tax_year derivation from target_month for year-boundary correctness. New RT-23 + RT-24 medium; new SD-23; SD-04 + SD-11 revisions. NOT a new instance of §8 FK-bypass family at V1 (Sec confirmed; chain becomes live at V2+ live-tax-API-ingestion under service_role — Sec re-consult MANDATORY at that adoption with Flag #7 mod #2-pattern fence as V1-SHIP-BLOCK for that surface). Candidate §10 meta-pattern strengthened to span privileged-context + user-facing surfaces. Task #35 booked for Phase 3 carry-over.
- **2026-05-26 (Flag #8 close)** — Phase 1 Step 4 drilling continued: **Flag #8 / Lock 13 closed** (Wave 4 step 1 — background-worker architecture). Locked Option C (hybrid: `pfin_back_etl` for data workers + V1 app for webhook/render + new Node PDF worker container) + Sec's 10 mods (4 V1-SHIP-BLOCK + 6 advisory). Load-bearing Sec catch (mod #2): infrastructure-layer fence — no Supabase credentials in PDF worker container preserves Lock 12 mod #1 read-path-only fence by-construction against future-optimization regressions. 6th chain-attack catch in joint flags. New RT-21 (HIGH PDF JWT verification) + RT-22 (medium PDF container credential audit); RT-09 + RT-10 amendments. New `pfin.plaid_sync_audit` table as cross-language schema-as-contract per mod #8. Candidate §10 meta-pattern (defense-in-depth fencing). Task #34 booked for Phase 3 carry-over.
- **2026-05-26 (Flag #7 close)** — Phase 1 Step 4 drilling continued: **Flag #7 / Lock 12 closed** (Wave 3 step 2 — snapshot-vs-live render-path composition; Architect-Sec joint). Locked Option A (sibling `pfin.monthly_report_account_snapshot` child table) + Sec's 8 mods (3 V1-SHIP-BLOCK + 5 advisory). Load-bearing Sec catch (mod #2): immutability trigger extended to fence parent `users_id` + `target_month` UPDATE — the 5th chain-attack catch in joint flags. New RT-20 (HIGH); RT-13 light amendment. 4th instance of cross-tenant FK-bypass family. Task #33 booked for Phase 3 carry-over.
- **2026-05-25 → 2026-05-26 (active drilling session; no PRs yet — work in `temp/`)** — Phase 1 Step 4 drilling **COMPLETE**: **🎉 all 16 substantive locks closed + candidate P3 resolved** (Flag #1 / P2 / E1a / Flag #2 / E2 / P1 / Flag #3 / Wave 1 step 2 #10+#12 / Flag #4 / Flag #5 / Flag #6 / Flag #7 / Flag #8 / Flag #9 / Flag #13 / Flag #11; P3 V1-default). **Lock 9 amended at Lock 15.** Full alphanumeric track + Waves 1-5 closed. 13 Phase 3 carry-overs booked in team task tracker `phase-1-step-4`. 8 locks-log meta-patterns identified (4 candidate ADRs for Step 4 close incl. §10 defense-in-depth spanning privileged-context + user-facing + schema-level surfaces). Sec found 23+ V1-ship-blockers across reviews; 8 chain-attack catches Architect missed. 5 new memory entries (including `reference_hetzner_cax21`). Full state at [`temp/step-4-locks-log.md`](temp/step-4-locks-log.md). Step 4 CLOSE WORK is the next phase.
- **2026-05-24** — PR #48 merged: ADR-010 PR 2 — comments-sidecar pass 2 (Python server `scripts/serve-docs.{py,sh}` + JS widget `docs/_assets/comments.{js,css}` + `/serve-docs` skill + asset wiring in all three HTML docs + WORKFLOW.md Inline-authoring subsection). Closes the ADR-010 two-PR landing — `/refine-doc` + `/serve-docs` both available; Step 4 PRD review can begin with widget support.
- **2026-05-24** — PR #47 merged: ADR-010 PR 1 — comments-sidecar pass 1 (`/refine-doc` skill + `comments.md` convention + gitignore + WORKFLOW.md Doc review loop section + ADR-010).
- **2026-05-23** — PR #46 merged: MILESTONES.md post-PR-B refresh.
- **2026-05-23** — PR #45 merged: PR B content migration — PRD §1/§2/§3/§6/§7/appendices → `docs/PRD/index.html`; §4 → `docs/SECURITY/index.html`; §5 → `BACKLOG.md`; §8 → `docs/MILESTONE-FRAMING.md`; `PRD.md` archived (tasks #12 + #13 + #14). ADR-009 mechanics wave complete.
- **2026-05-23** — PR #44 merged: PR C / SessionStart hook → MILESTONES.md head (task #11).
- **2026-05-23** — PR #43 merged: MILESTONES.md initial ledger creation (tasks #7 + #15).
- **2026-05-23** — PR #42 merged: adapt doc-update skills + retire /ship-branch (task #17).
- **2026-05-23** — PR #41 merged: extract WORKFLOW.md changelog to CHANGELOG.md (task #10).
- **2026-05-23** — PR #40 merged: PR A HTML doc scaffolding (task #18).
- **2026-05-23** — PR #39 merged: ADR-009 selective project_template adoption (task #9; 9-Decision consolidation ADR).
- **2026-05-20** — PR #38 merged: Phase 1 Step 3.5 post-rewrite verify pass closure (v1.30).

Full PR history in [`CHANGELOG.md`](CHANGELOG.md).

## Pending (immediate)

- **Drilling complete.** All 16 substantive locks closed + candidate P3 resolved. Locks log at [`temp/step-4-locks-log.md`](temp/step-4-locks-log.md) is the authoritative state file (16 lock entries + Lock 9 amendment annotation + 8 meta-patterns + candidate §10 strengthened across Lock 13/14/15 + Step 4 close work inventory + full Sec-mod inventory).
- **13 Phase 3 carry-over tasks** in team tracker `phase-1-step-4`: #11 / #13 / #15 / #16 / #17 / #20 / #26 / #29 / #32 / #33 / #34 / #35 / #36 — full descriptions in the locks log per-lock entries.
- **Step 4 CLOSE WORK (next phase, F/CTO direction on pacing)** — ADR batch (~19 entries: 4 project-convention ADRs from locks-log meta-patterns §6/§7/§8 + candidate §10 defense-in-depth + per-lock ADRs + ADR-008 amendment for Lock 9 correction #3 partial-reversal per Lock 15 + minor ADR for Lock 16 Outcome 1 + FMP (a) + P3 disposition) + §SECURITY HTML edits (SD matrix 14→23 expansion; RT catalog +10 entries incl. RT-20, RT-21 HIGH, RT-22, RT-23, RT-24, RT-25; RT-13 + RT-09 + RT-10 amendments; §4.2 + §4.6 annotations; §4.3 axis (vi) Coolify framing; PCI sub-section; SD-00 immutability + Lock 15 addenda) + PRD HTML edits (§7.3 V1-dormant `account_users` bullet; `users_id` sweep per P1) + MILESTONES Phase 1 → complete + WORKFLOW lessons-learned subsection + **BACKLOG entries (V2+ FMP cost-saving levers (b) + (c); V2+ stock-screening UI surface)** + phase-transition prompt per `docs/handoff-prompts.md`. F/CTO's choice on pacing: single-PR mega-close vs decomposed-PR sequence per `feedback_late_phase_density_overload`.
- **Candidate P3 follow-up** — FMP API + stock-screening tables (already shipped in `pfin_back_etl`) are incumbent-exceeds-V1 per `feedback_incumbent_exceeds_v1_review` guardrail; PM consult needed at F/CTO's choice of timing (not blocking Step 4 close but should land before Phase 3 ARCH drafting).

---

## Roadmap

[awk cutoff for SessionStart hook lives at this `## Roadmap` line per template's auto-load pattern. Content above this line is auto-loaded; content below is consult-on-demand.]

### Meta-process milestones

| # | Milestone | Status | Gate | Linear Project | Notes |
|---|---|---|---|---|---|
| **M0** | Research (PRD lock) | Active (virtually done) | PRD locked at end of mosko Phase 1 (after Step 4 ratifies) | _TBD on /setup-linear-team_ | Retro-tagged issues: Step 3 + Step 3.5 PRs (see [Completed Features](#completed-m0-retro-tagged) below). Plus the ADR-009 brainstorm-adoption arc (PRs #39–#42). |
| **M1** | Plan (ARCH + SECURITY docs) | Pending | ARCH + SECURITY docs locked at end of mosko Phase 3 | _TBD_ | Initial issues: (a) Draft ARCHITECTURE.md; (b) Extend `docs/SECURITY/index.html` with Phase 3 architectural decisions (V1 Sec posture already landed via ADR-008 + PR #45 content migration); (c) Populate product milestones in MILESTONES.md → see [`docs/MILESTONE-FRAMING.md`](docs/MILESTONE-FRAMING.md); (d) further granularity TBD. Also catches Phase 4 (Project Scoping) work as part of issue (c). |
| **M2** | Build (V1.0 → V1.final) | Pending | V1 ship | _TBD; defined as M1 issue (c) output_ | Product milestones (V1.0 / V1.1 / V1.final) get defined as M1's "Populate product milestones" output. M2 then decomposes into sprints. |
| **M3** | Deploy & Iterate | Pending | V1 in production | _TBD_ | mosko Phase 7 territory; ongoing project-scale I+V loops post-V1 ship. V2 candidates from [`BACKLOG.md`](BACKLOG.md) feed here. |

### Product milestones

| Milestone | Status | Gate | Notes |
|---|---|---|---|
| V1.0 / V1.1 / V1.final / V2-X | _NOT YET DEFINED_ | _Defined by M1 issue (c) output_ | See [`docs/MILESTONE-FRAMING.md`](docs/MILESTONE-FRAMING.md) for the V1 sub-version convention + drop-replace migration pattern + Phase 4 handoff anchor per ADR-004. |

## Sprints (Linear cycles)

| Sprint | Milestone | Start | End | Features | Status | Notes |
|---|---|---|---|---|---|---|
| _none yet — sprints activate at Phase 6 entry per ADR-009 Decision 7_ | | | | | | |

## Features

### Completed (M0 retro-tagged)

Issues retroactively tagged under M0 (Research milestone). Full PR history at [`CHANGELOG.md`](CHANGELOG.md).

| Feature | PR | Merged | Notes |
|---|---|---|---|
| ADR-010 PR 2 — comments-sidecar pass 2 (server + widget + `/serve-docs`) | #48 | 2026-05-24 | Closes the ADR-010 two-PR landing. Python stdlib HTTP server + JS widget + `/serve-docs` skill + asset wiring in all three HTML docs (PRD / ARCH / SECURITY) + WORKFLOW.md Inline-authoring subsection. Both `/refine-doc` and `/serve-docs` now available; Step 4 PRD review can begin with widget support. |
| ADR-010 PR 1 — comments-sidecar pass 1 (convention + `/refine-doc`) | #47 | 2026-05-24 | Adopted comments-sidecar feature from `richmosko/project_template` per ADR-009 Decision 8 selective-adoption framework. Pass 1 of 2: convention + skill + gitignore + WORKFLOW.md Doc-review-loop section + ADR-010. |
| PR B — PRD content migration to HTML artifact set | #45 | 2026-05-23 | Tasks #12 + #13 + #14 (ADR-009 Decision 4 second stage; closes the architectural shift). Migrated §1/§2/§3/§6/§7/appendices to `docs/PRD/index.html`; §4 → `docs/SECURITY/`; §5 → `BACKLOG.md`; §8 → `docs/MILESTONE-FRAMING.md`; `PRD.md` archived. |
| PR C — SessionStart hook → MILESTONES.md head | #44 | 2026-05-23 | Task #11 (ADR-009 Decision 6 mechanics; compact-ledger auto-load) |
| MILESTONES.md initial ledger | #43 | 2026-05-23 | Tasks #7 + #15 (this file's creation) |
| Adapt doc-update skills + retire /ship-branch | #42 | 2026-05-23 | Task #17 (ADR-009 Decision 9 implementation) |
| Extract WORKFLOW.md changelog to CHANGELOG.md | #41 | 2026-05-23 | Task #10 (orthogonal cleanup) |
| PR A — HTML doc scaffolding for PRD/ARCH/SECURITY | #40 | 2026-05-23 | Task #18 (ADR-009 Decision 4 first stage) |
| ADR-009 — selective project_template adoption | #39 | 2026-05-23 | Task #9 (9-Decision synthesis ADR) |
| Step 3.5 PR 11 — post-rewrite verify pass closure | #38 | 2026-05-20 | v1.30; 14-gate VP walk; 3 surgical edits; Sec hard-line preserved |
| Step 3.5 PR 10 — Step 3.5 closure + Appendix B consolidation | #37 | 2026-05-19 | v1.29; 114-entry App B body lifted + classified |
| Step 3.5 PR 9 — §8 rewrite | #36 | 2026-05-19 | v1.28; last PM-led drafting task in Phase 1 Step 3 |
| Step 3.5 PR 8 — §7 rewrite | (prior PR) | 2026-05-19 | v1.27 |
| Step 3.5 PR 7 — §6 rewrite | (prior PR) | 2026-05-19 | v1.26 |
| Step 3.5 PR 6 — §5 rewrite | (prior PR) | 2026-05-19 | v1.24 |
| Step 3.5 PR 5 — §4 rewrite (Sec primary author) | (prior PR) | 2026-05-19 | v1.23 |
| Step 3.5 PR 4 — §3 rewrite | (prior PR) | 2026-05-19 | v1.22 |
| Step 3.5 PR 3 — §2 rewrite + Appendix C | (prior PR) | 2026-05-18 | v1.21; 32 story traces extracted |
| Step 3.5 PR 2 — §1 rewrite | (prior PR) | 2026-05-18 | v1.20 |
| Step 3.5 PR 1 — Step 3.5 kickoff + archive | (prior PR) | 2026-05-18 | v1.19; PRD-v1.18 source archived |
| Step 3 §1–§8 PRD section drafting | PRs #10–#24 | 2026-05-09 → 2026-05-18 | Initial PRD drafting + ADRs 002–008 + Sec at-lock passes |
| Step 2 + Step 1 + Phase 0 / 0.5 bootstrap | PRs #1–#9 | 2026-04-24 → 2026-05-09 | Operating model + agent roster + WORKFLOW.md / DECISIONS.md / CLAUDE.md foundations |

### In Flight (M1)

| Feature | PR | Milestone | Branch | Status |
|---|---|---|---|---|
| _none active — between PRs; Step 4 (Architect PRD ratification) is the immediate next deliverable_ | | | | |
| _Substantive M1 features open after Step 4 ratifies / Phase 3 entry_ | | | | |

### Backlog (M1+)

Pulled from Linear once activated. Until then, M1's initial issues are listed in the [Meta-process milestones](#meta-process-milestones) table above. V2 candidates live in [`BACKLOG.md`](BACKLOG.md).

## Releases

| Version | Date | Milestone shipped | Notes |
|---|---|---|---|
| _none yet — first tagged release at V1.0 ship (defined by M1 issue (c) output)_ | | | |

## Decisions

The Decision Log lives in [`DECISIONS.md`](DECISIONS.md) (consult-on-demand per [ADR-009](DECISIONS.md#adr-009) Decision 6). Hybrid ADR format policy (consolidation vs terse) per ADR-009 Decision 8.

**Most recent ADRs:**

- **[ADR-010](DECISIONS.md#adr-010)** (2026-05-24; terse) — Adopt comments-sidecar feature from project_template. Two-PR landing: pass 1 (convention + `/refine-doc` skill); pass 2 (server + widget + `/serve-docs` skill).
- **[ADR-009](DECISIONS.md#adr-009)** (2026-05-23; consolidation) — Selective adoption of richmosko/project_template patterns. 9 Decisions consolidating the template-adoption brainstorm.
- **[ADR-008](DECISIONS.md#adr-008)** (2026-05-18; consolidation) — Phase 1 Step 3 §4 lock: V1 security posture canonical reference. 5 Decisions including 14-entry SD matrix + 15-entry RT catalog.
- **[ADR-007](DECISIONS.md#adr-007)** (2026-05-17; terse amendment) — Amendment to ADR-002 Finding (b): tax-loss-harvesting reclassified V2+ → permanent non-goal.
- **[ADR-006](DECISIONS.md#adr-006)** (2026-05-17; terse amendment) — Amendment to ADR-004 Decision D: V1 input-layer characterization (bracket schedules + tax_character enum).
- **[ADR-005](DECISIONS.md#adr-005)** (2026-05-13; terse amendment) — Amendment to ADR-002 §1.2: planning-targets V1 static reference-value rendering.

Full ADR list and historical entries at [`DECISIONS.md`](DECISIONS.md).

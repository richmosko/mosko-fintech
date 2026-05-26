# mosko-fintech — MILESTONES

Compact state ledger for mosko-fintech. **Top section (above `## Roadmap`) is auto-loaded by the SessionStart hook** per [ADR-009](DECISIONS.md#adr-009) Decision 6 (compact-ledger auto-load model — `MILESTONES.md` is the auto-load anchor; everything else consult-on-demand). Detail below the cutoff is consult-on-demand.

**Conventions:**
- Milestones tracked at two scales per [ADR-009](DECISIONS.md#adr-009) Decision 7: **meta-process** (M0 / M1 / M2 / M3 = R / P / I+V / Deploy) and **product** (V1.0 / V1.1 / V1.final / V2-X).
- Sprint = Linear cycle (orthogonal pacing wrapper, not a hierarchy level).
- Feature = Linear Issue = one PR = one I↔V loop.
- Last updated: 2026-05-26 (post Step-4 in-session drilling; 11 of 16 substantive locks closed; Step 4 in progress, NOT "ready to open" — full state at [`temp/step-4-locks-log.md`](temp/step-4-locks-log.md)).

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
| **Step** | Step 4 (Architectural overview consult; Architect lead; Phase 3 entry gate) — **IN PROGRESS** (active drilling session 2026-05-25 → 2026-05-26; paused mid-Step-4) |
| **Locks closed** | **11 of 16 substantive flags closed** — Flag #1 / P2 / E1a / Flag #2 / E2 / P1 / Flag #3 / Wave 1 step 2 (#10 + #12) / Flag #4 / Flag #5 / Flag #6. Full alphanumeric track (P1/P2/E1a/E2) closed. Waves 1 + 2 closed; Wave 3 step 1 closed. |
| **Locks remaining** | **5 substantive** (Flags #7 / #8 / #9 / #11 / #13) + candidate **P3** (FMP/stock-screening incumbent-exceeds-V1 — PM consult) |
| **Next pick** | **Flag #7** (Wave 3 step 2: snapshot-vs-live render-path composition; Architect/Sec joint per PRD §2.6.5 non-silent staleness; cross-tenant signal-leak race RT-13) |
| **Authoritative state file** | [`temp/step-4-locks-log.md`](temp/step-4-locks-log.md) — full lock rationale + Sec verdicts + 8 meta-patterns + Sec mod inventory + pending Step 4 work. **Consult this file as first stop to resume.** Gitignored per `feedback_working_artifacts_temp_not_docs`; local-only working artifact. |
| **Team task tracker** | `~/.claude/teams/phase-1-step-4/` team active; `~/.claude/tasks/phase-1-step-4/` task list has 32 tasks. **9 Phase 3 carry-over tasks** booked (#11/#13/#15/#16/#17/#20/#26/#29/#32) — each with full Sec-mod descriptions for Phase 3 implementation. Team mode active per ADR-003; spawn teammates via `Agent(team_name="phase-1-step-4", subagent_type=..., name=...)`. |
| **Candidate ADRs for Step 4 close** | 3 project-convention ADRs identified (locks-log meta-patterns §6 / §7 / §8): (a) **privileged-context-write discipline** for non-JWT writes; (b) **immutable + INSERT-new-version discipline** for audit-class surfaces; (c) **cross-tenant FK-bypass attack family** — matched-tenant validation required on every FK-shaped reference (incl. INTEGER[] arrays). Plus per-lock ADRs (~11 candidates from the 11 locks). |
| **§SECURITY HTML edits accumulated** | SD-matrix expansion 14→20 (SD-14 plaid_item_state_history; SD-15 acct_number; SD-16 reconciliation_event HIGH; SD-17 holdings_checkpoint; SD-18 reconciliation_event_trans; SD-12 monthly_report HIGH; plus SD-00 immutability addendum). RT catalog +3 entries (RT-16 cost-basis cascade; RT-17 reconciliation surfaces append-only; RT-18 immutability invariant suite; RT-19 read-time composition tenant-scoping). §4.2 three-surface external-API inventory + webhook-bypass-risk annotation. §4.6 PCI-DSS scope posture sub-section + four-surface reconciliation audit family annotation + trans-table-as-audit-log composition annotation. |
| **PRD HTML edits accumulated** | §7.3 V1-dormant `account_users` bullet (Flag P2). `tenant_id` → `users_id` sweep per Flag P1 (~8–15 edits across §1.4 + §7.3 + §SECURITY §4.1 axes (i)–(iv) + §4.4 SD matrix + ADR-008 Decision 1). |
| **Outer category** | Research (per ADR-009 Decision 2 — mosko Phases 1 + 2 sit under template's Research outer frame) |
| **Started** | 2026-05-09 (Phase 1 entry); 2026-05-25 (Step 4 in-session drilling start) |
| **Driver agent** | Architect (lead Step 4; PM consulted at P-flags; Sec at every architectural lock — Sec found 13+ V1-ship-blockers across reviews including 3 instances of the cross-tenant FK-bypass attack family) |
| **Gate criteria** | 5 substantive flags drilled + Step 4 close (ADR batch + §SECURITY HTML edits + PRD HTML edits + MILESTONES + WORKFLOW lessons-learned + phase-transition prompt per `docs/handoff-prompts.md`) → Phase 1 closes; Phase 3 (Technical Architecture) becomes available (skipping Phase 2 fast-track TBD at phase transition) |
| **New memory entries this session** | 4 — `feedback_team_mode_default` (spawn via team_name), `feedback_incumbent_exceeds_v1_review` (P-flag pattern when incumbent exceeds V1), `feedback_horizontal_rule_after_fcto_input` (formatting), `reference_pfin_back_etl` (sibling Python ETL on Coolify with BLS + FMP APIs already in production) |

## Active Feature

| Field | Value |
|---|---|
| Feature | _Step 4 architectural drilling — Wave 3 step 1 just closed (Flag #6); Wave 3 step 2 (Flag #7) is next pick_ |
| Linear issue | _N/A — Linear activates at Phase 4 entry_ |
| Branch | _N/A — drilling work in `temp/`; doc commits via `meta/` branches per ADR-009 Decision 9_ |
| Status | _Session paused 2026-05-26 mid-Step-4. Resume via consulting [`temp/step-4-locks-log.md`](temp/step-4-locks-log.md) + team task tracker. Next session: TeamCreate not needed (team `phase-1-step-4` durable); spawn Architect via `Agent(team_name="phase-1-step-4", ...)` and brief on Flag #7._ |

## Recent activity (last 7 days)

- **2026-05-25 → 2026-05-26 (active drilling session; no PRs yet — work in `temp/`)** — Phase 1 Step 4 drilling: **11 substantive locks closed** (Flag #1 / P2 / E1a / Flag #2 / E2 / P1 / Flag #3 / Wave 1 step 2 #10+#12 / Flag #4 / Flag #5 / Flag #6). Full alphanumeric track closed; Waves 1+2 closed; Wave 3 step 1 closed. 9 Phase 3 carry-overs booked in team task tracker `phase-1-step-4`. 8 locks-log meta-patterns identified (3 candidate ADRs for Step 4 close). Sec found 13+ V1-ship-blockers across reviews. 4 new memory entries. Full state at [`temp/step-4-locks-log.md`](temp/step-4-locks-log.md). Step 4 close work blocked on remaining 5 flag drills (#7 / #8 / #9 / #11 / #13) + candidate P3.
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

- **Step 4 drilling continues** — **Flag #7** (Wave 3 step 2: snapshot-vs-live render-path composition; Architect/Sec joint per PRD §2.6.5) is the immediate next pick. Composes with Flag #6 = B Option's read-time composition + Plaid Item state-history from Flag #2.
- **Locks log** at [`temp/step-4-locks-log.md`](temp/step-4-locks-log.md) is the authoritative state file (11 lock entries + 8 meta-patterns + pending Step 4 work + full Sec-mod inventory).
- **9 Phase 3 carry-over tasks** in team tracker `phase-1-step-4`: #11 (E1a Sec mods + E1b NULL bug) / #13 (Flag #2 Plaid Sec mods) / #15 (E2 Sec mods) / #16 (Flag P1 schema rename + PRD/Sec adoption) / #17 (Flag #3 taxonomy migration Option A) / #20 (Wave 1 step 2 Sec mods) / #26 (Flag #4 Sec mods + per-transaction reconciliation model) / #29 (Flag #5 immutable account_trans + 10 Sec mods + RT-18) / #32 (Flag #6 monthly_report + 9 Sec mods + RT-19).
- **Step 4 close work (Task #8 in tracker, BLOCKED on remaining flag drills)** — ADR batch (~14 entries: 3 project-convention ADRs from locks-log meta-patterns §6/§7/§8 + per-lock ADRs) + §SECURITY HTML edits (SD matrix 14→20 expansion; RT catalog +4 entries; §4.2 + §4.6 annotations; PCI sub-section; SD-00 immutability addendum) + PRD HTML edits (§7.3 V1-dormant `account_users` bullet; `users_id` sweep per P1) + MILESTONES Phase 1 → complete + WORKFLOW lessons-learned subsection + phase-transition prompt per `docs/handoff-prompts.md`.
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

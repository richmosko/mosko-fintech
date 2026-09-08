# SELF-365 (P11) — V1.final §3.4 close-gate protocol: decomposition draft for F/CTO ratification

**Status:** DRAFT — assumes nothing ratified. Every claim below is pinned to `main` = `d83d7edb` (PR #660, V1.5 → V1.final rotation). No Linear writes were made; the five sub-issues in §B are created through the liaison only after F/CTO rules on §A and §C.
**Author:** PM · **Date:** 2026-09-07 · **Inputs read verbatim:** PRD §3.3 / §3.4; `docs/MILESTONE-FRAMING.md` §8.1–§8.3 + routing flag (d); `BACKLOG.md` §7.2 P11; `docs/records/v15-preflight/sitting-log.md` R12; `pm-findings.md` §6; `rederived-acs.md` § *Not in this wave*; live Linear descriptions of SELF-365 / SELF-375 / SELF-378 (liaison-fetched, verbatim); migrations `108` / `111` / `114` / `115`; `workers/etl/src/pfin_back_etl/monthly_report_cron.py`; `docs/deployment-runbook.md`; `WORKFLOW.md` Phase 6 / Phase 7; ADR-021 / ADR-036 / ADR-068.

---

## 0. Drift catches (read before the substance)

| # | Where | What the text says | What the tree says | Load-bearing? |
|---|---|---|---|---|
| D-1 | Live SELF-365 AC (b) · P11 AC (b) · MILESTONES *Next deliverable* | "ARCH §10 SD + RT mapping verified post-implementation" | **ARCH has no §10.** "§10" is ADR-011 Decision 4's catalogued-instance ledger (layer definitions at SECURITY §4.2; ARCH §8.5 is only an *explicit-unchanged annotation*). "SD + RT" is SECURITY §4.4 (SD matrix) + §4.5 (RT catalog); ARCH §6.1 maps a load-bearing subset of §4.5 to CI stages. Three surfaces fused into one citation that names none of them. | **Yes** — and it is not PRD §3.4(b) at all (see §A.2). |
| D-2 | Live SELF-375 description | "PRD §6 / sitting-log R12 clause (2) … Owner: PM (§6 owner)" | PRD §6 is *Out-of-scope for this PRD lifecycle* (permanent non-goals). The source is **`pm-findings.md` §6** (the PM's V1.5 findings section), not the PRD. | No — the measurement is unaffected; the citation should be corrected when the issue is next edited. |
| D-3 | Dispatch brief | "43 rows" of `docs/v1-parity-matrix.md` marked "V1 preserve" | **42 table rows** carry "V1 preserve" (over lines beginning `\|`, all five capability tables: reference data 8 · per-account 12 · aggregator 14 · output 5 · cross-cutting 3). The 43rd `grep` hit is the legend line at the top of the file. | Minor — the count feeds the (a) trace table; 42 is the number to build against. |
| D-4 | MILESTONES *Next deliverable* | "(c) N=2 consecutive months of monthly report generation + commentary authoring + RLS clean" | That is the **pre-R12** P11 wording. The live SELF-365 AC (c) is the six-clause R12 definition (re-worded at the amendment batch, comment 2026-09-04). | No — the live AC governs; the ledger line is stale prose. |
| D-5 | PRD §7.3 (*Usage model*) | "V1 ships to a single user (the F/CTO) … the set of users is closed and invite-controlled" | **ADR-036** records *"F/CTO ruled V1 signup is OPEN (public signup + email-confirmation)"*. The PRD predates that ruling. | Yes for **SELF-378** (the cron's tenant population is not "one tenant"); a PRD §7.3 amendment is owed (PM) — outside this record's deliverable, booked in §E. |

---

## A. Criterion reconciliation — §3.4(a) and §3.4(b)

### A.1 Facts established against the tree

**(i) §3.3 parity tests do not exist.** Over the whole tree at `d83d7edb`:
- `workers/etl/tests/test_replay_parity.py` is the **RT-15 record-replay** suite (synthetic BLS/FMP payloads through the ETL fetch/parse path, "NO network and NO credentials"). It compares nothing to the incumbent. Its docstring names RT-15, not §3.3.
- `tests/fixtures/parity/README.md` is the RT-15 **fixture-governance** surface; its one "§3.3" mention is RT-15's own label (*"§3.3 parity-fixture test-environment RLS posture"*). It governs what a fixture MUST NOT contain (production rows), which is the opposite of a §3.3 comparison fixture.
- The §3.3 comparison fixtures (`Finance_Report_2026_04.pdf`, the Asset Summary workbook) are **not in git** (`git ls-files` over `*.pdf`, `*.xlsx`, `finance_report`, `asset summary`: empty). SECURITY §4.6 *Parity-fixture handling* commits them to "access-controlled paths (specific access-control mechanism is Architect Phase 3 per routing flag (j))" — no tree location was ever resolved.
- No harness, no tolerance-class code (≤ $1 / ≤ 0.01 %), no cell-comparison fixture exists for any of the six §3.3 tests (§2.1 / §2.2 / §2.3 / §2.4 / §2.5 / §2.6). `BACKLOG.md` §7 stages **no** parity-harness item; `MILESTONES.md` and `DECISIONS.md` carry no "parity test" booking beyond ADR-007's TLH mention.

**(ii) §3.4(a)/(b) were never amended or re-derived.** `git log -L699,711:docs/PRD/index.html` shows the §3.4 block touched only by the 2026-05-23 HTML migration commits (`f2064f7f`, `fa3e454b`). The §7.19 recalibration pass body (BACKLOG §7.19) has zero §3.3 / §3.4 hits. PRs #625 / #626 (V1.5 amendment batch) touched §2.6 / §2.5.3, not §3.4. §3.3 itself *was* amended (the 2026-08-17 Cash-row and Liabilities-group footnotes; the 2026-08-19 Marketable-Securities footnote) — each adjusts the *comparison*, and each presupposes a test that has never been built. Every other §3.4 reference on the tree (BACKLOG P11, MILESTONES, `docs/linear-setup.md`, MILESTONE-FRAMING §8.1 / §8.3, SECURITY §4.6 tear-down bullet) *cites* §3.4; none restates or narrows it.

**(iii) The live SELF-365 AC** (comment 2026-09-04: *"AC re-worded to the R12 definition at the V1.5 amendment batch"*) reads, verbatim:
> **(a)** PRD trace exit criterion — all 32 §2 stories have ≥ 1 issue closed in Linear (post-rotation).
> **(b)** ARCH §10 SD + RT mapping verified post-implementation.
> **(c)** N = 2 consecutive months of operation, per R12. [six clauses — quoted in §B.3]

So on this tree: the live (a) is PRD §3.4(a)(i) *by story* (32 = the Appendix C story-trace count) with §3.4(a)(ii) (the parity test) **absent**; the live (b) is **not** §3.4(b) — it is a security-catalog verification, and §3.4(b)'s amendment-delivery check has no carrier anywhere in Linear.

**Standing facts that bound the options:** the app is greenfield (ADR-021) — there is no running incumbent to compare against automatically, only the F/CTO's documents; the PRD predates the GL feature set, so §3.3's cell enumerations describe surfaces the GL recalibration has since re-shaped (e.g. §2.5.1's ST/LT CG columns render UNAVAILABLE by ruling; §2.3's rollup is now GL-derived). Some §3.3 cells are therefore unmeetable *as enumerated*, not merely unbuilt.

### A.2 Options for §3.4(a) — what "every V1-preserve row has a §2 story AND a passing §3.3 parity test" means as a sub-issue on this tree

| Option | Sub-issue (a) AC becomes | Cost / who | **Losing side** |
|---|---|---|---|
| **A-1 Literal** | 42-row trace table (matrix row → §2 story → ≥ 1 Done Linear issue) **and** a §3.3 harness executing all six tests against the fixtures for one canonical comparison month, tolerance classes as written, green in CI. | New build: fixture location (Architect/Sec joint, routing flag (j), never resolved), harness for six surfaces, GL-era re-derivation of the cell lists (PRD amendment first), Sec review of a fixture holding real $ values. Several issues; unstaged. | The calendar in §D floors V1.final at ~3 months out, so the build might *fit* — but §3.3's cell lists are pre-GL and would have to be re-derived before they can be coded, which is a PRD amendment cycle *before* a build. The harness would be built once, for one month, to close one criterion; §3.4(c)'s two months of no-reconciliation is the operative parity signal anyway. Highest cost, lowest marginal information. |
| **A-2 Trace-only (the live AC as written)** | 42-row trace table; §3.4(a)(ii) discharged by **substitute evidence**: the six V1.x close-gate battery verdicts already recorded (SELF-269 · SELF-362 precedents) + §3.4(c)'s two attested months. Requires a **PRD §3.4(a) amendment** replacing "a §3.3 parity test passing for the canonical comparison month" with the substitute, F/CTO-ratified before (a) can close. | One PM issue (trace table) + one PRD amendment PR. Liaison read of Linear per story. | §3.4(a)(ii) as written is **not met**, and closing on it without the amendment is a false close. §3.3's tolerance-class machinery becomes dead text the PRD still carries (a second amendment, or an explicit "retained as V2 harness spec" note, is owed). The ≤ $1 / 0.01 % numeric claim is never made by any test. |
| **A-3 Hybrid — trace + one manual §2.6 end-to-end comparison** | 42-row trace table **and** one F/CTO-performed comparison of a V1-generated report against the incumbent `Finance_Report` for a **single comparison month that both systems hold**, recorded as a checklist over §3.3's §2.6 test clauses (i)–(v) with per-cell pass/fail at the stated tolerance; no automated harness. PRD §3.4(a)(ii) amended from "parity test passing" to "recorded manual parity comparison". | One PM issue (trace) + one F/CTO session + a smaller PRD amendment. | Manual, non-repeatable; tolerance checked by eye. **The comparison month must be one the incumbent still holds and V1 already holds** — the deploy month (which never counts toward (c) anyway) is the natural candidate, but V1's historical completeness for that month is `⟨OPEN⟩` (NAV history is seeded per SELF-217; transaction/cash-flow history for the comparison month is not established). Doing the comparison on a *counting* month would trip clause (6)'s "no reconciliation needed" — so it must be M0, not M1/M2. |

PRD's own text weighs toward A-3: §3.3 closes with *"passing §2.6 parity for a given month is the strongest single signal that V1 reproduces the F/CTO's monthly Finance_Report workflow."* PM does not pick; F/CTO rules. All three require the trace table, so **that sub-issue can be created regardless of the ruling** (§B.1).

### A.3 Options for §3.4(b) — amendment delivery (ADR-004 A/B/C/D + ADR-005 + ADR-006), and what to do with the live AC's security-catalog (b)

| Option | Sub-issue (b) AC becomes | **Losing side** |
|---|---|---|
| **B-1 Literal** | Per amendment: capability delivered (named surface: route / migration / story) **and** parity-tested. | Inherits (a)'s parity dependency wholesale — chooses A-1 by the back door. |
| **B-2 Delivery trace + "nothing deferred silently" check** | Six rows (ADR-004 Decision A rebalance-target visualization · B multi-scope ownership · C multi-level taxonomy · D estimated-taxes primitive form · ADR-005 planning-targets static rendering + settings UI · ADR-006 bracket schedules + standard deduction + `tax_character`) → §2 story → ≥ 1 Done Linear issue → shipped surface named. Plus an explicit **deferral audit**: every `BACKLOG.md` §5 entry and every SECURITY §4.6 V2-ship-gate entry touching those six is listed with its ratifying ADR (a deferral with no ADR = §3.4(b)'s "deferred to V2 silently" failure mode). Parity clause follows whatever A-option is ruled. | "Parity-tested" is dropped from (b) explicitly — same PRD amendment as (a). Known deferrals that will surface in the audit and need a named ADR to pass: SELF-340's securities-edit surface (staged §7, ADR at `DECISIONS.md` *"C — a real securities-edit surface — is staged, not built"*); §2.5.1 ST/LT CG UNAVAILABLE-by-ruling; §2.2 asset-allocation history (matrix: "data model only; reporting V2-deferred"). |
| **B-3 Fold (b) into (a)** | The 42-row trace table gains an *ADR* column; the six amendments are all matrix rows (the "was V2 in ADR-002, F/CTO uses today" rows), so one table discharges both. | Loses the deferral audit unless the table carries a *Deferred → ADR* column too; collapses two conjunctive criteria into one issue (the record can still show both discharged, but the Linear granularity F/CTO asked for is lost). |

**The live AC's (b) — "SD + RT mapping verified":** it is a real check but a *different* one, owned by Sec, and it is already WORKFLOW Phase 6's exit criterion *"Security Reviewer signs off on V1 as a whole."* Options: **(S-1)** keep it as a fifth-plus-one Sec-owned sub-issue of SELF-365 (AC: every SECURITY §4.4 SD row and §4.5 RT row, and each ADR-011 D4 §10 catalogued instance, has either a Done issue or an explicit V2-ship-gate entry in §4.6 — Sec authors the AC; PM only names the surfaces); **(S-2)** move it out of SELF-365 to the Phase 6 exit walk, and let SELF-365 (b) be PRD §3.4(b). Losing side of S-1: SELF-365 carries an item PM cannot specify or verify; of S-2: V1.final closes without the security sign-off *inside* the gate — acceptable only because the phase exit already holds it. **PM lean: S-2** — it restores (b) to the PRD's meaning; the Sec sign-off is not lost, it is homed where WORKFLOW already puts it.

---

## B. The five sub-issue specs (Linear grade; created only after §A / §C rule)

Common fields: **Project** Platform / Cross-cutting · **Milestone** V1.final — §3.4 close mechanism · **Parent** SELF-365 · **Label** `role:pm` unless stated.

### B.1 — (a) Parity-matrix V1-preserve trace

- **Title.** V1.final (a): 42-row parity-matrix "V1 preserve" trace → §2 story → Done Linear issue [+ parity evidence per §A.2 ruling]
- **Source.** PRD §3.4(a) verbatim; `docs/v1-parity-matrix.md` (the five capability tables); PRD Appendix C story-trace index (32 entries); the §A.2 ruling.
- **AC.**
  1. A table at `docs/records/v1final/a-parity-trace.md` with one row per "V1 preserve" table row of `docs/v1-parity-matrix.md` (42 at `d83d7edb`; the count is re-derived at execution and stated as *over table rows*), columns: matrix row · §2 story (Appendix C anchor) · Linear issue(s) · state · sha of the PR that closed it.
  2. Every row names ≥ 1 Linear issue in state Done, read live through the liaison at execution time (never from memory or MILESTONES); the read-back lists the 32 stories with their Done-issue counts.
  3. Rows whose story maps to a capability the GL recalibration re-shaped cite the ruling (ADR / sitting-log R-number) that re-shaped it, so a row is never "Done by a different surface" silently.
  4. *Conditional on §A.2:* A-1 → the harness sub-issues are opened and this issue is Blocked-by them; A-2 → the PRD §3.4(a) amendment PR is merged first and cited by sha; A-3 → the manual §2.6 comparison record is attached (`docs/records/v1final/a-manual-parity-M0.md`, clauses (i)–(v) each pass/fail, comparison month named, both artifacts' provenance named, **$ values redacted** per PRD public-tier discipline).
- **Dependencies.** Upstream: all V1.0–V1.5 issues Done (verified at rotation 2026-09-07). Blocked-by: the §A.2 ruling; under A-2/A-3 the PRD §3.4 amendment PR.

### B.2 — (b) ADR-004 / ADR-005 / ADR-006 amendment delivery

- **Title.** V1.final (b): ADR-004 A–D + ADR-005 + ADR-006 amendment-delivery trace and silent-deferral audit
- **Source.** PRD §3.4(b) verbatim; ADR-004 Decisions A / B / C / D; ADR-005; ADR-006; `BACKLOG.md` §5; SECURITY §4.6 V2-ship-gate inventory; the §A.3 ruling.
- **AC.**
  1. `docs/records/v1final/b-amendment-trace.md`: six rows (the four ADR-004 Decisions + ADR-005 + ADR-006), each → §2 story → Done Linear issue(s) → shipped surface named (route path or migration number as it exists on the tree at execution).
  2. Deferral audit: every `BACKLOG.md` §5 entry and SECURITY §4.6 inventory entry whose subject falls under one of the six cites the ADR (or sitting-log ruling) that deferred it; an entry with none is listed as a §3.4(b) failure and routed to F/CTO.
  3. *Conditional:* under S-1 the Sec-owned SD/RT sub-issue is a sibling, not part of this AC; under S-2 this issue's title drops any "§10" wording and the MILESTONES *Next deliverable* line is corrected in the close-PR.
  4. Parity clause per the §A ruling (same amendment as B.1 item 4).
- **Dependencies.** Same as B.1. Blocked-by: the §A.3 ruling.

### B.3 — (c)-month-1 and (c)-month-2 (identical AC; M differs)

- **Title.** V1.final (c) month N: calendar month M = ⟨YYYY-MM⟩ counts under the R12 six-clause definition
- **Source.** PRD §3.4(c) verbatim; `docs/records/v15-preflight/sitting-log.md` R12 (F/CTO RULING 2026-09-04) — definition + skip ruling (A); live SELF-365 AC (c); migrations `108` / `111` / `113` / `114` / `115`; SELF-375 (measurement) and SELF-378 (population) as ruled.
- **AC.** A record `docs/records/v1final/c-month-⟨N⟩.md` showing each R12 clause with its evidence. The clauses, **verbatim from R12**, each followed by *how it is evidenced on the tree at `d83d7edb`*:

  1. *"(1) V1 held the tenant's connected and manual accounts for the whole of M — the deploy month never counts"* — **Evidence:** the production deploy date (the Coolify deploy record named by DevOps — `⟨OPEN⟩` which record, see §D) is before the 1st of M; `min(created_at)` over `pfin.account` for the tenant (column at `003_account_and_account_users.sql`) is before the 1st of M. `⟨OPEN⟩` — does an account *added during M* break "whole of M"? PM reading: no — the account set as of the 1st of M is held all month; additions are ordinary use. F/CTO confirms or narrows.
  2. *"(2) the 1st-of-(M+1) cron fired and created M's pending report, evidenced by the R7 audit row (trigger = cron, `data_as_of` = last day of M)"* — **Evidence:** one `pfin.audit_log` row with `surface_name = 'monthly_report_generation'`, `trigger_source = 'cron'`, `users_id` = tenant, `data_as_of` = last day of M, `created_at` on/after the 1st of M+1, `subject_table = 'pfin.monthly_report'` and `subject_id` naming the row with `target_month` = first of M (all columns at `111`; the GUC-derived `trigger_source` at `113` / ADR-068 Decision 9 C1). Counted as **distinct `(users_id, date_trunc('month', data_as_of))`**, never rows (SELF-375, §C.1). *Noted, not re-opened:* a cron failure recovered by the on-demand path (PRD §2.6.3's own fallback) writes `on_demand`, so **that month does not count** under R12 as ratified.
  3. *"(3) the user **authored** commentary for M and finalized"* + the skip ruling *"(A) a month whose commentary was explicitly skipped (all four sub-sections) does not count"* — **Evidence:** the `pfin.monthly_report` row for `target_month` = M with `generation_status = 'final'` (enum at `108`: `draft` / `final` / `superseded`), `commentary_disposition = 'authored'` (vocabulary CHECK at `108`; written only by `115`), `generated_at` not null, and the frozen payload's `sections.rebalancing_targets.disposition = 'authored'` (`115` item 7). *Interpretation note:* `115` item 9 makes `'authored'` with four empty strings legal by design; the gate reads the disposition, not the text — a month "authored" blank counts by the letter of R12; clause (6)'s attestation carries the spirit. Regeneration after finalization is permitted (the superseded row stays; the *current* final is what is read).
  4. *"(4) the user exported M's PDF at least once (the R2 path exercised end-to-end)"* — **`⟨OPEN⟩` — no durable evidence exists on the tree.** `pfin.audit_log`'s `surface_name` vocabulary is exactly `('monthly_report_generation')` (`111` CHECK); the PDF is a transient download by PRD §2.6.3 (not persisted server-side). Options: (i) F/CTO attestation + the downloaded file retained (mtime) — a statement, like clause (6); (ii) the PDF worker's container log line at export time (Coolify log retention unverified — DevOps); (iii) a second audit surface `monthly_report_pdf_export` — a migration that grows the vocabulary (ADR-011 D19 extension; **Sec joint-review** — the export route is a §4.1 RT-26 surface). PM lean **(i)** for V1.final: cheap, and (iii) is a schema change to close a gate the schema was not designed to evidence. Losing side of (i): clause (4) stops being a measurement.
  5. *"(5) the §2.6.6 battery (SELF-362) was green on the tree that generated M"* — **Evidence:** the deployed sha at the moment the 1st-of-(M+1) cron ran (`⟨OPEN⟩` — which Coolify record names the image/sha; DevOps), and a CI db-tests run at that sha with `supabase/tests/rls/self362_v15_close_gate.sql` green, cited by run URL; precedent shape = `docs/records/v15-execution/self362-close-gate-verdict.md` (verdict at `ab92187`) + `self362-close-gate-ratification.md`. *CI is the authority* — the local run carries two documented EXPECTED-DIFFERENT-LOCALLY legs (`054`, `111` dblink) that are not failures of the gate.
  6. *"(6) the F/CTO attests no reconciliation against the spreadsheet was needed for M — the one criterion that is a statement, not a measurement, and §3.4's own named failure mode"* — **Evidence:** a dated, signed line by F/CTO in the month record. Nothing on the tree can evidence this; the record is the evidence.

  **Consecutive:** month-2's M is month-1's M + 1 (R12: *"Two consecutive = M and M+1 both pass"*). A failed M2 does not reset to M3 alone — the next candidate pair is (M3, M4).
- **Dependencies.** Blocked-by: production deploy + tenant accounts in place before the 1st of M (§D); SELF-375 ruled (clause 2's count); SELF-378 ruled (clause 2's population). Month-2 Blocked-by month-1 PASS.

### B.4 — V1.final-close-PR

- **Title.** V1.final close PR: §3.4 (a)+(b)+(c) all-pass record, ledger rotation, drop-replace termination
- **Source.** PRD §3.4 closing paragraph (conjunctive); MILESTONE-FRAMING §8.2 (drop-replace terminates at §3.4(c) retirement) + §8.3 routing flag (d); SECURITY §4.6 *Shadow-workflow tear-down* bullet; `.claude/skills/milestone-rotation`; ADR-017 Decision 2.
- **AC.**
  1. `docs/records/v1final/close.md` cites B.1 / B.2 / B.3×2 records by path and sha and states all-pass.
  2. SECURITY §4.6's four tear-down commitments are each discharged or explicitly routed: no dual-write to the Google Sheet · one-time NAV import terminated · **read-only archive at a Sec-acknowledged access-controlled location** · **snapshot of the existing system at cutover preserved as an audit artifact** — the last two are **V1-required and unowned today** (§E).
  3. MILESTONES head: V1.final COMPLETE; *Next deliverable* restated; the stale (c) wording (D-4) removed. `BACKLOG.md` §7.2 P11 entry tombstoned ("closed at SELF-365, sha").
  4. Any PRD §3.4 amendment ruled at §A is merged **before** this PR (this PR cites it; it does not carry it).
  5. Sec sign-off per WORKFLOW Phase 6 exit ("Security Reviewer signs off on V1 as a whole") attached or cited (under S-2 this is where it lives).
- **Dependencies.** Blocked-by: B.1, B.2, both B.3 issues Done. Final V1 issue; nothing promotes after it (V1.6 = SELF-205 already in Linear per ADR-035).

---

## C. SELF-375 and SELF-378 proposals

### C.1 SELF-375 — the cron-generation measurement

**What the live description asks:** define the V1.final cron-generation measurement as *distinct `(users_id, date_trunc('month', data_as_of))` where `trigger_source = 'cron'`* — never a row count — because `fn_regenerate_monthly_report` (`114`) writes one audit row per regeneration for the same month, so rows are inflatable by ordinary use. ADR-068 Decision 9's C2 bullet records this as *"a RECOMMENDATION, not an open question … Routed to PM."* `111`'s `data_as_of` column comment already states the same predicate **and adds the surface filter** `surface_name = 'monthly_report_generation'` as load-bearing (a future surface a cron transaction can write would silently change the result), and says prose is the weak form — *"COMMIT THE PREDICATE AS SQL — a view … routed to PM."*

**PM definition (proposed for ratification):** *A month M is cron-generated for tenant T iff there exists at least one `pfin.audit_log` row with `surface_name = 'monthly_report_generation'` and `trigger_source = 'cron'` and `users_id = T` and `date_trunc('month', data_as_of) = M`. The measurement is the set of distinct `(users_id, date_trunc('month', data_as_of))` pairs satisfying that predicate — cardinality over pairs, never over rows.* For V1.final clause (2) the set is further restricted to T = the F/CTO tenant and M ∈ {M1, M2}, so the expected cardinality is exactly 1 per month.

| Option — where the definition lives | **Losing side** |
|---|---|
| **M-1 Committed SQL (a view or function on the tree), with a pgTAP leg pinning the surface vocabulary** | A migration + Sec joint-review (a new read surface over an audit-class table; RLS/`security_invoker` posture is Architect's). Cost before it is ever read twice. |
| **M-2 Recorded query in the month record, run by team-lead at month close** | `111`'s own words: no watcher; a vocabulary growth changes the answer without anyone touching the query. |
| **M-3 M-2 plus a battery leg that REDs when `audit_log_surface_name_vocab` grows beyond the one value** (the FLAG-4 pattern SELF-375's addendum cites for `payload_schema_version`) | The battery watches the tree, not production data; the read is still manual. No new DB surface. |

**PM lean: ratify the definition now (product wording above) and M-3 as its carrier for V1.final**, with M-1 staged to `BACKLOG.md` §5 as the durable form. Losing side: the measurement is executed by hand twice. The *mechanism* choice is Architect's; the *definition* is what PM owns and what this record asks F/CTO to ratify. Correct the D-2 citation when the issue is edited.

### C.2 SELF-378 — tenant population for the monthly-report cron

**What the live description asks:** the cron enumerates `select distinct users_id from pfin.account` (`monthly_report_cron.py`, mirrored from `nav_daily.py`; the code's own docstring flags it as *"the ONLY existing per-tenant enumeration precedent … call it out if PM/Architect intended a different population"*). A user with no accounts gets no draft, no pending item, no notification. SELF-351's AC never pinned the population. Sec: not a security finding, no objection either way.

**Product frame:** under ADR-036 (open signup) the population is *every confirmed user*, not one tenant (D-5). A report for a tenant with no accounts is six empty sections.

| Option | What the user sees | **Losing side** | Sec visibility |
|---|---|---|---|
| **T-1 Keep: account-owning tenants only (current code), and pin it in SELF-351's AC by comment** | A no-account user sees an empty report listing with no explanation. | An open-signup user who has not yet added an account gets nothing and no cue; the pending-queue affordance (PRD §2.6.3, V1) is silent for them. | None new — population unchanged. |
| **T-2 Every confirmed user: open an empty draft for tenants with no accounts** | A pending item every month, with nothing in it. | Empty snapshots frozen as immutable rows for every idle signup, forever (ADR-011 Lock 11 INSERT-only); the cron's per-tenant impersonated write (sitting-log R3 α binding) now runs for tenants that own nothing — that is a **change in which tenants the cron impersonates**, so Sec must see it before it is posture, per R3. | **Yes** — flag, do not decide. |
| **T-3 T-1 population + an empty-state message on the report listing for no-account tenants** ("Add or connect an account to receive monthly reports") | The cue without the row. | A frontend copy item on a Done milestone (P5's listing surface, SELF-357) — lands as a V1.x follow-up or V2; V1.final does not wait for it. | None new. |

**PM lean: T-1 as the V1 rule (pinned), T-3 staged as a V1.x follow-up in `BACKLOG.md` §7.** Losing side: an idle open-signup tenant is uncued until T-3 lands. Not a V1.final blocker: the F/CTO tenant owns accounts, so clause (2) is unaffected under every option. The population predicate — whichever is ruled — is what clause (2) reads through, so it is cited from the (c) issues.

---

## D. The calendar — earliest V1.final close from 2026-09-07

**Scheduling fact for F/CTO (not resolved here): there is no production deployment.** Evidence at `d83d7edb`: `docs/deployment-runbook.md` is marked *"SKELETON (Phase 6 entry, 2026-06-29)"* with every section a `STUB`; WORKFLOW Phase 7 (*Deploy & Iterate* — "Get V1 to production") is *"⏳ Not started"* and lists "Production VPS ready" and "Plaid Production credentials" as *inputs*; MILESTONES M3 (Deploy) is *Pending*; `BACKLOG.md` §7 entries read *"Blocked-by: Phase 7 arrival — per ADR-021 greenfield the deployment environment does not exist until deploy"*; no Coolify/deploy record exists under `docs/records/`. Everything shipped so far runs on the local Supabase CLI stack.

**Phase-ordering contradiction to escalate:** WORKFLOW Phase 6's exit criterion is *"All V1 milestones complete"*, and V1.final is a Phase 6 milestone — but its (c) requires two months of **production** operation, which WORKFLOW places in Phase 7 (*"V1 is in production, used by owner for at least one full monthly cycle"* is Phase 7's exit). As written, V1.final cannot close inside Phase 6. Either Phase 7 entry precedes V1.final close (production stand-up becomes a V1.final dependency, and Phase 6/7 overlap), or the WORKFLOW phase gate is amended. F/CTO's call; PM flags it.

**Dependency chain** (each link before the 1st of M1): production stand-up (VPS · Coolify · Supabase · secrets manifest applied · Plaid production credentials · PDF worker + cron containers) → F/CTO signup + **all** accounts connected / entered (clause 1) → M1 whole → cron on the 1st of M1+1 → author + finalize + export (any day thereafter) → M2 whole → cron on the 1st of M2+1 → author + finalize + export + attestation → close-PR.

| Deploy **and** accounts complete by | Deploy month (never counts) | M1 | M2 | Second cron fires | Earliest close (cron + same-day authoring/export/attest + PR) | Edge cases §3.4(c) names that the pair exercises |
|---|---|---|---|---|---|---|
| 2026-09-30 | 2026-09 | 2026-10 | 2026-11 | **2026-12-01** | first days of 2026-12 | neither quarter-end (Q4 est-tax is 2027-01-15) nor year-end |
| 2026-10-31 | 2026-10 | 2026-11 | 2026-12 | **2027-01-01** | first days of 2027-01 | year-end NAV anchor rollover · Q4 est-tax window |
| 2026-11-30 | 2026-11 | 2026-12 | 2027-01 | **2027-02-01** | first days of 2027-02 | year-end rollover (in M1) · Q4 est-tax (Jan 15, in M2) |
| 2026-12-31 | 2026-12 | 2027-01 | 2027-02 | **2027-03-01** | first days of 2027-03 | Q4 est-tax (in M1); no year-end |

Each **failed** month (cron miss → `on_demand`; skipped commentary; a red battery on the deployed sha; a reconciliation) pushes the close by **two** months if it is M2 (next pair = M3/M4), by one if it is M1. A September stand-up needs the skeleton runbook executed end-to-end in ~3 weeks; PM states the fact and does not size it — DevOps leads Phase 7.

---

## E. Scope flags (V2 creep · V1-required-but-unowned · PRD debts)

| # | Flag | Class | Route |
|---|---|---|---|
| E-1 | **§3.3 parity harness** — required by §3.4(a)(ii) as written, built nowhere, staged nowhere, fixtures off-tree with no resolved location (SECURITY §4.6 routing flag (j) never landed as a tree fact). Resolved by the §A.2 ruling, not by building. | V1-required, unowned | F/CTO (§A.2) |
| E-2 | **§3.4(b) amendment-delivery trace** has no Linear carrier — the live AC's (b) replaced it with a security-catalog check (D-1). | V1-required, unowned | F/CTO (§A.3) |
| E-3 | **Production stand-up** — no Linear issue, no BACKLOG §7 entry names Phase 7 entry as work; the runbook is a skeleton; Plaid production credentials are unrequested. V1.final's month-1 clock cannot start without it. | V1-required, unowned | F/CTO + DevOps |
| E-4 | **SECURITY §4.6 tear-down obligations at cutover** — read-only archive at a Sec-acknowledged location; cutover snapshot preserved as an audit artifact. Neither has an owner or a home; both are close-PR content (B.4 item 2). | V1-required, unowned | Sec + F/CTO |
| E-5 | **WORKFLOW Phase 6 ↔ Phase 7 ordering** (§D) — V1.final cannot close inside Phase 6 as the phase gates are written. | Process contradiction | F/CTO (team-lead relays) |
| E-6 | **PRD §7.3 "single-user V1"** contradicts ADR-036's open-signup ruling (D-5). PRD amendment owed; affects how SELF-378 is read, not V1.final's gate. | PRD debt (PM) | PM drafts post-ratify |
| E-7 | **PRD §3.3 tolerance-class machinery** becomes dead text under A-2 / A-3 unless the amendment says what it is retained *for* (a V2 harness spec, or struck). | PRD debt (PM) | PM, same amendment as §A |
| E-8 | **Clause (4) audit surface** (§B.3 item 4 option iii) — a new `audit_log` surface to evidence PDF export is a schema change proposed to serve a gate; not V1 unless F/CTO wants clause (4) measured rather than attested. | V2 creep if built now | F/CTO; Sec if built |
| E-9 | **SELF-378 T-2** (empty drafts for every confirmed user) — immutable empty rows per idle signup, monthly, forever; and a change in the cron's impersonation population. | Creep risk; Sec-visible | Sec before posture |
| E-10 | **SELF-375 M-1 view** — durable form is right, but a new read surface over an audit-class table is not needed to close V1.final; stage to §5 unless Architect wants it now. | Defer (V2 / later V1.x) | Architect |
| E-11 | **MILESTONES *Next deliverable*** carries the pre-R12 (c) wording (D-4) and the "ARCH §10" fusion (D-1) — corrected in the close-PR or at the next ledger PR, whichever is first. | Ledger drift | team-lead |

---

## F. What F/CTO is asked to rule (one line each; PM leans stated where PM has one)

1. §A.2 — (a)'s parity clause: **A-1** literal harness · **A-2** trace + substitute evidence · **A-3** trace + one manual §2.6 comparison on M0. (No PM pick; PRD's own text favours A-3's comparison.)
2. §A.3 — (b)'s shape: **B-1** / **B-2** / **B-3**; and the live AC's security-catalog (b): **S-1** keep as Sec sub-issue · **S-2** re-home to the Phase 6 exit walk. (PM lean: **B-2 + S-2**.)
3. §B.3 clause (1) — does an account added mid-M break "whole of M"? (PM reading: no.)
4. §B.3 clause (4) — attest **(i)** · worker log **(ii)** · new audit surface **(iii)**. (PM lean: **(i)**.)
5. §C.1 — ratify the SELF-375 measurement wording; carrier **M-1 / M-2 / M-3**. (PM lean: wording now, **M-3** carrier, M-1 staged.)
6. §C.2 — SELF-378 population **T-1 / T-2 / T-3**. (PM lean: **T-1** pinned, **T-3** staged; T-2 needs Sec first.)
7. §D — the deploy target month (sets M1), and the Phase 6/7 ordering (E-5).

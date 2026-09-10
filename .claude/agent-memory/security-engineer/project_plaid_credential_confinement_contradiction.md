---
name: plaid-credential-confinement-contradiction
description: RULED twice — #697 (root .env.example) and #699 (ETL half + ADR-011 D17/Lock 13 amendment). provider-sync is sole Plaid holder. Open residue is operator-facing prose + SD-19's falsified cross-language rationale.
metadata:
  type: project
---

**BOTH HALVES RULED.** F/CTO 2026-09-09, across two PRs.

- **#697** (`74d9a1d5`) removed the `PLAID_*` entries from the **root** `.env.example`.
- **#699** (`meta/adr011-d17-poll-relocation`, tip `344d8c23`) landed the **ADR-011
  Decision 17 / Lock 13 in-line amendment**: the Plaid scheduled-poll runs in
  `provider-sync`, which is the **SOLE holder** of `PLAID_CLIENT_ID` / `PLAID_SECRET`.
  It struck the declarations from `workers/etl/.env.example` with a *prohibitive*
  absence note (reintroduction = confinement violation, not a completeness fix).
  ⚠ It **ratifies a build that outran its lock** — `workers/provider-sync/src/cli/poll.ts`
  was already shipped; `workers/etl/src/` has never held a Plaid API code path.

**My #699 verdict: APPROVE + 2 conditions** (`temp/security-pr699-conditions.md` at
review time — gitignored; check whether team-lead placed it durably).
The precedent I applied, and would apply again: **operator-facing PROVISIONING
surfaces are merge conditions; CI-fence work is a follow-up.**
- C-1 `secrets-manifest.yml` 133–134 — the manifest IS the provisioning instruction.
- C-2 `docs/local-dev.md` 96 + 110 — instructed mirroring both vars into
  `workers/etl/.env`. **Prose that INSTRUCTS the failure is a merge condition;
  merely stale prose is a follow-up.**

**Standing obligations that survived the ruling — BOOKED, cite the ID, do not re-describe:**
- **SELF-391** — SECURITY revision: SD-19 / §4.2 / RT-09(b) after the poll relocation.
- **SELF-392** — deployment-runbook §5: name `provider-sync` the sole Plaid provisioning target
  (this is the converted form of my #697 §5 carve-out).
- Both: Platform / Cross-cutting, V1.x, Backlog, `sec-joint-review` / `role:sec-review` /
  `surface:plaid`. My ACs went in verbatim, incl. the "do NOT relax the `source` ENUM" warning.
- A third issue (ID pending) holds the `fn_plaid_webhook_commit` unlocked-RMW race —
  see [[feedback_stored_status_column_vs_derived_history_half]]. Unrelated to the confinement.

**Detail behind those obligations:**
- **§5 carve-out is DISCHARGED as a carve-out and CONVERTED.** It was explicitly
  conditional ("until the ETL item is ruled"). Replacement: **the PR that authors
  `docs/deployment-runbook.md` §5 must name `provider-sync` as the sole Plaid
  provisioning target, and that PR is Sec joint-review.** Residue at review time:
  runbook :733 lists a phantom separate "Plaid scheduled-poll worker (Wave 6)" cron
  alongside provider-sync's; :723 still says 3-container topology; §5 is a STUB.
- **SD-19's rationale is FALSIFIED, not merely mis-attributed** — its
  "cross-language schema-as-contract (webhook TS + poll Python)" premise is dead;
  both writers are TypeScript. ⚠ **The `source` ENUM discriminator must NOT be
  relaxed** — it still does attribution work. Also stale independently:
  SD-19 names `pfin.plaid_sync_audit`, folded into `linked_source_sync_audit` at
  `015_linked_source_fold.sql`. **RT-09 sub-case (b)** names ETL/Python as the poll
  tenant-isolation test target — a battery built to that spec is **vacuous**;
  it becomes a merge condition if RT-09(b) is scheduled before the SECURITY revision.
- **Nothing fences the confinement.** `grep -rn 'PLAID' .github/workflows/ scripts/`
  = 0 (positive control `SUPABASE_SERVICE_ROLE_KEY` = 4). `check-secrets-nonoverlap.py`
  enforces ci_only/production_only **disjointness only, never per-container
  placement** — and the ci_only pair is distinct-named (`PLAID_SANDBOX_*`), so it
  cannot trip either. A fence here would be a **new §10 cataloguing decision**
  (Sec + F/CTO), never an Architect cleanup.

⚠ **Beware the ARCH §5 citation loop** — §5's per-container enumeration self-marks as
Phase-3 vintage and drifted, naming the per-surface `.env.example` files the source of
truth. An `.env.example` citing §5 for its own contents is circular. Rest confinement
claims on **ADR-011 D17 as amended** and ADR-037. ⚠ My #697-era memory that "§5 says
*Neither holds a Plaid credential today*" went stale — §5 now names provider-sync
explicitly. **Re-read §5 live; never cite it from here.**

Related: [[feedback_correcting_half_a_hand_maintained_mirror]] ·
[[feedback_supplied_verbatim_text_ships_unfiltered]] ·
[[feedback_a_grep_over_comments_measures_intent_not_data]]

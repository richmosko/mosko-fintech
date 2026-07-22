---
name: apply-migration
description: Invoke when authoring a new Supabase migration — adding a base table, extending an RLS surface, writing a new SECURITY INVOKER helper, or proposing any function with SECURITY DEFINER posture. Codifies the Architect-owned procedure: migration file shape (POSTURE RATIONALE + CONTRACT blocks + `comment on function` + `set search_path = ''` + idempotent schema creation), mandatory §10 3-axis cross-check before drafting, Decision 3 matched-tenant validation rule for every FK-shaped column, Sec joint-review routing triggers, and QA pgTAP test-pairing requirement. Also invoke when evaluating whether a new column or array type activates the cross-tenant FK-bypass family. Do NOT invoke for Backend `supabase migration up` execution (Backend role) or pgTAP test authorship (QA role).
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Agent
  - SendMessage
---

# apply-migration — author a Supabase migration under V1 discipline

Architect-owned procedure for authoring migrations in `supabase/migrations/`. Operationalizes [`supabase/CLAUDE.md`](../../../supabase/CLAUDE.md) (primary source) + [ADR-011](../../../DECISIONS.md#adr-011) Decisions 3 / 4 / 9 / Lock 11.

## Role split — who does what

| Role | Owns |
|---|---|
| **Architect** | Authors migration SQL files + `config.toml` edits |
| **Backend** | Applies (`supabase migration up`) after CI fixture-seed verification — read-only on the file |
| **QA** | Authors `tests/` pgTAP battery — Architect does NOT edit `tests/` |
| **DevOps** | Wires CI test-fixture seeding around the migration |

## Step 0 — §10 3-axis cross-check (MANDATORY before drafting)

Before writing a single line of SQL, read [ADR-011 Decision 4](../../../DECISIONS.md#adr-011) verbatim. Cross-check the draft against three axes:

1. **Instance-numbering** — canonical ordering is RT-22 first, RT-26 second. Do not reorder or renumber.
2. **Layer-attribution** — do not re-attribute which layer a catalogued instance operates at (RT-22 = infrastructure-credential-presence layer; RT-26 = code-layer CI grep fence).
3. **Verbatim-vs-paraphrase** — the catalogued numbered list is not restated in migration files; link to Decision 4 (Path B: drop-enumeration-let-link-carry). Only restate verbatim if the migration file IS the canonical anchor (it never is — Decision 4 is).

The V1 §10 ledger commitment is **2 instances only** (RT-22 + RT-26). Do not silently add a catalogued instance. Any ledger change (count or layer-attribution) is **Sec joint-review-mandatory** before the migration is finalized.

## Step 1 — Migration file shape

Model file: `supabase/migrations/002_fn_mask_acct_number.sql`. Numbering note: `001` is reserved for the foundational `users_id_rename` migration (SELF-186 Phase 5 close-gate, authored later); `fn_mask` is order-independent so it lands at `002`.

Every migration file carries this header structure:

```sql
-- ============================================================================
-- Migration: pfin.<name> — <one-line description>
-- <Phase / Linear issue reference>. Closes / extends <SD-NN / RT-NN / Lock N>.
--
-- Numbering: <why this number; what precedes / what this depends on>
--
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT SECURITY DEFINER.
--   <why INVOKER is correct here — "reads no tables and needs no elevated privilege">
--   OR
-- POSTURE RATIONALE — SECURITY DEFINER — Sec joint-review required; see DEFINER allowlist.
--   <why DEFINER is required; which allowlist entry this is>
--
-- CONTRACT
--   <function signature> — <brief behavior description>
--   <security-load-bearing edges: NULL handling, immutability invariants, tenant-binding>
-- ============================================================================
```

Every function also carries:
- `set search_path = ''` — prevents search_path injection
- `comment on function <name>(<args>) is '...'` — self-documenting; include ADR anchor + posture + SD/RT refs
- Schema creation is idempotent: `create schema if not exists pfin`

**Sequencing:** pure helpers (no table dependencies) are order-independent. Base-table migrations and RLS policies are order-dependent — sequence them deliberately; note the dependency in the header.

## Step 2 — INVOKER vs DEFINER decision

**Default posture: SECURITY INVOKER** ([Lock 11](../../../DECISIONS.md#adr-011)). The canonical V1 read-composition path (`fn_compute_nav` / `fn_compute_tax_liability` / `fn_render_monthly_report`) is entirely INVOKER — functions run as the calling user, inheriting their RLS context.

**SECURITY DEFINER allowlist — 2 entries only** ([ADR-011 Decision 9](../../../DECISIONS.md#adr-011)):
1. `fn_refresh_updated_at` — trigger helper for `updated_at` refresh
2. The audit-log insert helper

`fn_mask_acct_number` is NOT a DEFINER entry — it is a pure `IMMUTABLE`/`STRICT` string transform that reads no tables and needs no elevated privilege (DEFINER allowlist corrected 3→2 at Phase 5 Step 4 W2 per Decision 9 amendment).

**Any new SECURITY DEFINER function → Sec joint-review before finalizing.** Route via `spawn-sec-joint-review` (compose with this skill).

## Step 3 — Decision 3 matched-tenant validation

Any FK-shaped reference column — single FK, self-FK, or `INTEGER[]` array element — that crosses a tenant isolation boundary requires **explicit matched-tenant validation** ([ADR-011 Decision 3](../../../DECISIONS.md#adr-011)). PostgreSQL FK constraints validate existence, not tenant scope. Without matched-tenant validation, FK-shaped columns create chain-attack surfaces that defeat RLS protection at the schema layer.

**Required validation shape:**
- Single FK column → `WITH CHECK` constraint matching tenant anchor
- `INTEGER[]` array → `BEFORE INSERT/UPDATE` trigger validating every array element's `users_id` equals row's `users_id` (PostgreSQL cannot express this declaratively)

**Family count:** 7 instances at Phase 4 close (Lock 9 / Lock 10 / Lock 11 / Lock 12 from Phase 1 Step 4 + 3 additions across Phase 4 Wave 5 decomposition). This is a **non-negotiable** discipline — matched-tenant validation in the DDL is mandatory; it does not skip even when the surface "looks safe."

Decision 3 extensions are **Sec joint-review triggers** — every new FK-shaped reference column that joins the family routes to Sec before the migration lands.

## Step 4 — Base-table migration checklist

When introducing or modifying a base table:

- **`grant`-then-RLS shape** (durable root-cause, PR #106): Postgres checks table ACL before RLS. A table needs `grant select, insert, … to authenticated` even with RLS enabled — RLS filters rows; the GRANT lets the role reach the table at all. Pair every base-table migration's RLS policy with a matching table-level GRANT. Missing GRANT = ACL denial before RLS is consulted, producing misleading test failures.
- **`users_id` predicate**: RLS policies key on `users_id = auth.uid()`. After the SELF-186 migration (`001_users_id_rename.sql`), the renamed column is the isolation anchor; all downstream V1.0 RLS work depends on it.
- **Immutability triggers** for audit-class tables (Decision 2 / Lock 10): block UPDATE + DELETE across both `authenticated` AND `service_role` via DB trigger. Append-only at the policy layer is not sufficient — service_role bypasses RLS but not DB triggers.
- **aal2 step-up backstop inheritance** (C3 standing obligation; [ADR-029](../../../DECISIONS.md#adr-029) / `025_aal2_step_up_backstop.sql`): any **new sensitive tenant-owned `pfin` table** MUST inherit the per-user-conditional aal2 backstop clause on its `authenticated` policies when it lands — AND-ed into the read `USING` and the write `WITH CHECK`/`USING`, exactly as `025` does for the current 14 tables. The clause (COALESCE null-safe, inline — no helper): `(coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp','passkey') or (auth.jwt() ->> 'aal') = 'aal2')`. Without it, a new sensitive table silently ships un-claused and opens an **aal1 read/write gap on the direct PostgREST API** (Sec's C2 threat — a stolen password reaches the data before TOTP step-up). **Exclusions** (do NOT clause; state the reason in-header per `025`): (i) **global shared-read** tables (`using(true)`, e.g. `tax_character`); (ii) **service_role-only / default-deny** tables (RLS on, zero `authenticated` policy, e.g. `026`/`027`/`linked_source_sync_audit`); (iii) the **`user_settings` substrate itself** (clausing it = infinite RLS recursion — the clause's subquery reads `user_settings`). **Corollary — new `user_settings` *columns* are already covered:** the MB-1 downgrade guard (`fn_user_settings_block_mfa_downgrade`, `025`) fires only on an `mfa_policy` *weakening*, so unrelated column edits (e.g. future SELF-232 settings) are unaffected — but a **new sensitive *table* is not automatically covered** and must be claused per this bullet.

## Step 5 — QA test-pairing requirement

A new RLS policy or new SECURITY INVOKER helper **ships in the same PR** with a per-Wave two-tenant pgTAP battery (SECURITY §4.5 posture; RT-15 parity fixture). The battery must:

- Cross-tenant read → fail closed
- Cross-tenant write → fail closed
- Owner reads own rows → pass
- INVOKER helper cross-tenant invocation → asserts-fails-closed

QA authors the tests (Architect does not edit `tests/`). Sec sign-off gates V1-SHIP-BLOCK merge. A vacuous green (e.g., fixture only populates one tenant) does not satisfy the requirement.

## Routing summary

| Trigger | Route to |
|---|---|
| Any new SECURITY DEFINER function | Sec joint-review (mandatory before finalize) |
| §10 ledger change — count or layer-attribution | Sec joint-review (mandatory) |
| New FK-shaped column joining Decision 3 family | Sec joint-review (Decision 3 extension trigger) |
| Migration extends RLS surface | QA test-pairing same-PR |
| Migration ready to apply | Backend (`supabase migration up` after CI verification) |
| Migration requires CI fixture changes | DevOps |

## Gotchas

- **`major_version = 17` is PROVISIONAL** in `config.toml` — confirm against prod (`SHOW server_version;` or Studio → Settings → Infrastructure) before Phase 6 base-table work, where version-skew bites harder. Today's pure-function migrations are PG 15/17-identical.
- **Migrations live in code, not the Supabase dashboard.** Any dashboard-applied change that doesn't have a migration file is invisible to CI and is a discipline violation.
- **`supabase/tests/` is QA-owned.** Architect does not author or edit there; QA does not edit `supabase/migrations/`.

## Notes

- Composes with `spawn-sec-joint-review` (Sec routing for DEFINER / Decision 3 / §10 ledger changes).
- Composes with `brief-drift-catch` (verbatim-source cross-check on Lock/ADR citations before forwarding a draft to F/CTO ratify).
- Origin: [`supabase/CLAUDE.md`](../../../supabase/CLAUDE.md) (Step 5 canonical) + [ADR-011](../../../DECISIONS.md#adr-011) Decisions 3 / 4 / 9 / Lock 11 + PR #106 grant-then-RLS root-cause. Track record: `002_fn_mask_acct_number.sql` is the first V1 migration exercising this procedure end-to-end.

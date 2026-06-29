# `supabase/` — scoped context for Claude Code

> **Per-directory `CLAUDE.md`** (WORKFLOW.md Phase 5 Step 5). Scoped conventions for working inside `supabase/`. The root [`CLAUDE.md`](../CLAUDE.md) + canonical artifacts ([ARCH](../docs/ARCH/index.html) · [SECURITY](../docs/SECURITY/index.html) · [DECISIONS](../DECISIONS.md)) stay source-of-truth; this file is the surface-local quick reference.

**Owner role:** Architect (authors migrations + `config.toml`); Backend consumes (read-only). QA owns `tests/`; DevOps owns the CI job. Per WORKFLOW.md Agent Roster.

## What lives here
- `migrations/` — Architect-authored SQL migrations. **Migrations live in code, not the dashboard** (root CLAUDE.md). Current: `001_pfin_foundation.sql` (foundational — `pfin` schema + `fn_refresh_updated_at` SECURITY DEFINER `updated_at` trigger helper; SELF-186 Phase 5 close-gate) + `002_fn_mask_acct_number.sql` (SD-15 masking primitive).
- `config.toml` — Supabase CLI config. Note the **PROVISIONAL `[db] major_version = 17`** (see gotchas).
- `tests/` — **QA-owned** pgTAP RLS battery (`supabase test db`, directory-mode). Architect does not author here, but every migration extending RLS surface is paired with a QA battery test. See [`tests/README.md`](tests/README.md) + [`tests/rls/DESIGN.md`](../tests/rls/DESIGN.md).

## Conventions
1. **Migration file shape** (model: `002_fn_mask_acct_number.sql`). One migration per logical lock-set. Header carries: numbering rationale, a **POSTURE RATIONALE** block (INVOKER vs DEFINER + why), a **CONTRACT** block (signature + behavior + security-load-bearing edges), and `comment on function`. Functions set `set search_path = ''`; schema creation is idempotent (`create schema if not exists pfin`). Pure helpers are order-independent; base-table/RLS migrations are order-dependent — sequence them deliberately.
2. **RLS-default-trust** ([Lock 11](../DECISIONS.md#adr-011)). Postgres RLS is the V1 isolation primitive: policies key on `users_id = auth.uid()`. **SECURITY INVOKER read-composition is the canonical read path** (`fn_compute_nav` / `fn_compute_tax_liability` / `fn_render_monthly_report`). **SECURITY DEFINER is a narrow 2-entry allowlist only** — `fn_refresh_updated_at` + the audit-log insert helper ([ADR-011 Decision 9](../DECISIONS.md#adr-011): SD-15 `fn_mask_acct_number` is NOT DEFINER — it's a pure `IMMUTABLE`/`STRICT` transform). **Any new SECURITY DEFINER function routes to Sec joint-review** before finalize.
3. **§10 SD+RT enforcement.** Every migration touching an SD-NN class must:
   - **(a)** preserve the [ADR-011 Decision 4](../DECISIONS.md#adr-011) §10 catalogued-instance ledger — a **2-instance** commitment (RT-22 = PDF-worker container credential audit; RT-26 = `SUPABASE_SERVICE_ROLE_KEY` allowlist CI grep fence). **Do not silently add a catalogued instance.** Any ledger change (count or layer-attribution) is Sec joint-review-mandatory.
   - **(b)** carry **matched-tenant validation** in the DDL for any FK-shaped reference column — including `INTEGER[]` arrays — per the [Decision 3](../DECISIONS.md#adr-011) cross-tenant FK-bypass family (**7 at Phase 4 close**; matched-tenant validation is **non-negotiable**).
   - **(c)** ship a pgTAP RLS battery test (QA) that would catch a **real** cross-tenant violation, not a vacuous green.
   - **Pre-emptive §10 cross-check (3 axes: instance-numbering / layer-attribution / verbatim-vs-paraphrase) is mandatory** at every migration draft + every DECISIONS ADR touching §10-adjacent territory. This file *references* the ledger — it does not restate the canonical numbered list (Path B).
4. **Test pairing.** A new RLS policy / new SECURITY INVOKER helper ⇒ ships **in the same PR** with a per-Wave two-tenant battery test (SECURITY §4.5 posture; RT-15 parity fixture): cross-tenant read fails closed, cross-tenant write fails closed, owner reads own rows, INVOKER helper asserts-fails-closed cross-tenant. QA sign-off gates V1-SHIP-BLOCK merge.

## Canonical references
- [`../DECISIONS.md`](../DECISIONS.md) — ADR-011 D3 (FK-bypass family) / D4 (§10 ledger) / D9 (SD-15 + DEFINER allowlist) / Lock 11 (INVOKER read-composition) · [ADR-019](../DECISIONS.md#adr-019) (monorepo; ETL at `workers/etl/`).
- [`../docs/ARCH/index.html`](../docs/ARCH/index.html) §10 (SD+RT) · [`../docs/SECURITY/index.html`](../docs/SECURITY/index.html) (SD matrix + RT catalog + [§4.5](../docs/SECURITY/index.html#sec-4-5) two-tenant posture).
- [`tests/README.md`](tests/README.md) · [`tests/rls/DESIGN.md`](../tests/rls/DESIGN.md).

## Fail-closed / gotchas
- **`grant`-then-RLS shape** (durable root-cause, PR #106). Postgres checks the **table ACL before RLS**. A table needs `grant select, insert, … to authenticated` *even with RLS enabled* — RLS filters rows; the GRANT lets the role reach the table at all. A missing grant denies at the ACL layer before RLS is consulted (you'd be testing GRANTs, not RLS). Every base-table migration pairs its RLS policy with the matching table-level GRANT.
- **`major_version = 17` is PROVISIONAL** — F/CTO best-guess for cax21 prod PG. **Confirm against prod** (Studio → Settings → Infrastructure, or `SHOW server_version;`) **before Phase 6 base-table work**, where version-skew bites harder. Today's content (pure-fn masking + inversion canary) is 15/17-identical, so low-stakes now.
- **Migrations live in code, not the Supabase dashboard.** Architect authors; Backend applies (`supabase migration up`) after CI fixture-seed verification; QA consumes in fixture setup.
- **Architect authors / Backend consumes read-only.** Do not edit `migrations/` as Backend; do not edit `tests/` as Architect (QA-owned).

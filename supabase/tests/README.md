# `supabase/tests/` — pgTAP RLS verification battery (QA-owned)

**Ownership:** QA owns `supabase/tests/`. Architect owns `supabase/migrations/` + `config.toml`.
DevOps owns the CI job that runs `supabase test db`. (Per Phase 5 Step 4 W3 + team-lead
scaffold relay 2026-06-25 — `supabase init` created `config.toml` + `migrations/`, NOT `tests/`,
so this dir is QA's with no collision.)

**Framework shape:** pgTAP via `supabase test db` (locked, W3-A routing). Design rationale:
[`tests/rls/DESIGN.md`](../../tests/rls/DESIGN.md).

## What runs

| File | Class | Status |
|---|---|---|
| `00_rls_inversion_self_test.sql` | harness self-proof (inversion-mode) | runnable now (no migration dep) |
| `sd15_fn_mask_acct_number.sql` | SD-15 per-§10 behavioral + no-disclosure | **RED until `002_fn_mask_acct_number.sql` lands**, then GREEN |
| `rls/NN_<table>_rls.sql` | per-Wave cross-tenant cases | added per migration (none yet — main has no RLS base tables) |
| `_fixtures/rls_verbs.sql` | shared assertion verbs (NOT a test) | `\ir`-included by test files |

## Helper-placement (Option C, via `\ir`)

Reusable assertion verbs live once in `_fixtures/rls_verbs.sql` (DRY). Each test file
`\ir _fixtures/rls_verbs.sql` at the top of its `begin…rollback` txn — the verbs are created
transactionally per test and rolled back with it. This keeps a single verb source without
depending on cross-file pgTAP state persistence or a particular seed-load mechanism. The
two-tenant **data** is seeded per-test inside the txn (no bleed); the verbs expose the fixed
synthetic tenant identities (`_rls.tenant_a()` / `_rls.tenant_b()`).

**Discovery (RESOLVED at author-time, DevOps 2026-06-25):** `supabase test db` runs `pg_prove
… -r`, which **recurses** — so a bare `supabase/tests` target WOULD collect
`_fixtures/rls_verbs.sql` as a planless test and fail the run. The `db-tests.yml` job therefore
passes an **explicit `_fixtures/`-excluding file list** (not the bare dir); the CLI still mounts
the parent `supabase/tests` dir so each test's `\ir _fixtures/rls_verbs.sql` resolves. The
`_fixtures/` subdir layout stays as-is — the exclusion lives in the job, not in the directory
name. (Verified: the job's list returns exactly the 2 real test files and skips the verbs.)

## The inversion self-test (why a green battery is trustworthy)

Mirrors W1's CI inversion-mode (a fence must FAIL against a known-bad fixture). The self-test
builds an unprotected canary table and asserts the cross-tenant probe **detects** the leak —
proving the probe has teeth. A regression here is a QA fence gap, exactly like a W1 fence that
stops catching its golden fixture. Negative-detection is proven now; positive isolation (probe
returns 0 on a real PROTECTED table) is proven by per-table cases once RLS tables land (Phase 6).

## Per-Wave discipline (going forward)

Every Phase 6 Wave landing a migration that extends RLS surface — new `users_id` table, new RLS
policy, new SECURITY INVOKER helper — ships a `rls/NN_<table>_rls.sql` case **in the same PR**
asserting: cross-tenant read fails closed, cross-tenant write fails closed, owner reads own rows
(fail-closed both directions), and any SECURITY INVOKER helper asserts-fails-closed cross-tenant.
QA sign-off gates V1-SHIP-BLOCK merge.

## Access-control / fixture posture

Synthetic-only — no production data, no PII, no real account numbers. Governed by the central
parity discipline: [`tests/fixtures/parity/README.md`](../../tests/fixtures/parity/README.md).
The verbs schema (`_rls`) and the test seed load into the **test** DB only, never production.

## Auth context — `db`-only, SQL-seeded (no GoTrue)

The battery simulates tenant auth **in-SQL**: `_rls.set_tenant()` sets `role=authenticated` +
`request.jwt.claims.sub`, and `auth.uid()` (a DB function from migrations) reads it. Tenant
identities are seeded into `auth.users` **via SQL** (fixed UUIDs), not GoTrue signup — so the
CI spin-up is **`db`-only** (`supabase start -x …` drops the GoTrue/auth container — see ## Run;
`supabase db start` does not exist). Per DevOps CI-lane decision 2026-06-25.

> When the first real RLS base table (with an `auth.users` FK) lands in Phase 6, a
> `_rls.seed_tenants()` helper will insert the two fixed-UUID `auth.users` rows with the minimal
> valid column set, inside each test's rolled-back txn (hermetic). The inversion canary needs no
> `auth.users` rows, so `db`-only suffices today.

## Run

`supabase db start` does **not** exist (the `db` subcommands are diff/dump/lint/pull/push/reset/
schema-* only). `supabase test db` requires a running stack via `supabase start`. db-only
incantation (drop GoTrue + the rest; `auth.uid()` stays — the `auth` schema is created at DB
init, not by the GoTrue container):

```
supabase start -x gotrue,realtime,storage-api,imgproxy,studio,edge-runtime,logflare,vector,supavisor,postgres-meta,mailpit
supabase test db <explicit _fixtures-excluding file list>   # NOT the bare dir (pg_prove -r recurses)
```

CI: own workflow `db-tests.yml` (DevOps-owned), path-triggered on `supabase/migrations/**` +
`supabase/tests/**` + `supabase/config.toml` — deliberately path-triggered (heavy DB spin-up),
unlike the always-run fast fences in `security-scan.yml`. The job runs the db-only `supabase
start -x …`, applies migrations on bring-up, runs a `select auth.uid();` smoke guard, then
`supabase test db` with the explicit file list. DB major-version is pinned via `config.toml
[db] major_version` (pending F/CTO confirm vs cax21 prod PG — version-skew guard).

⟦WIRE-VALIDATE⟧ not yet executed — authored against the firmed contracts; first live run happens
once `002` lands + the DevOps CI job is wired. Per the W3-A grounding discipline, not claimed
green until that run.

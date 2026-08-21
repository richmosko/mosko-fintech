# `supabase/tests/` — pgTAP RLS verification battery (QA-owned)

**Ownership:** QA owns `supabase/tests/`. Architect owns `supabase/migrations/` + `config.toml`.
DevOps owns the CI job that runs `supabase test db`. (Per Phase 5 Step 4 W3 + team-lead
scaffold relay 2026-06-25 — `supabase init` created `config.toml` + `migrations/`, NOT `tests/`,
so this dir is QA's with no collision.)

**Framework shape:** pgTAP via `supabase test db` (locked, W3-A routing). Design rationale:
[`rls/DESIGN.md`](rls/DESIGN.md).

## What runs

| File | Class | Status |
|---|---|---|
| `00_rls_inversion_self_test.sql` | harness self-proof (inversion-mode) | runnable now (no migration dep) |
| `sd15_fn_mask_acct_number.sql` | SD-15 per-§10 behavioral + no-disclosure | **RED until `002_fn_mask_acct_number.sql` lands**, then GREEN |
| `rls/NN_<table>_rls.sql` | per-Wave cross-tenant cases | added per migration (none yet — main has no RLS base tables) |
| `_fixtures/rls_verbs.psql` | shared assertion verbs (NOT a test — `.psql` non-test extension) | `\ir`-included by test files |

## Helper-placement (Option C, via `\ir`)

Reusable assertion verbs live once in `_fixtures/rls_verbs.psql` (DRY). Each test file
`\ir _fixtures/rls_verbs.psql` at the top of its `begin…rollback` txn — the verbs are created
transactionally per test and rolled back with it. This keeps a single verb source without
depending on cross-file pgTAP state persistence or a particular seed-load mechanism. The
two-tenant **data** is seeded per-test inside the txn (no bleed); the verbs expose the fixed
synthetic tenant identities (`_rls.tenant_a()` / `_rls.tenant_b()`).

**Discovery (RESOLVED on PR #106 first run, DevOps 2026-06-25):** the `db-tests.yml` job runs
`supabase test db` in **directory-mode** (no file args) — it mounts the whole `supabase/tests`
tree, and `pg_prove -r` recurses but collects only `*.sql`/`*.pg` files as tests. The verbs file
carries a **non-test extension `.psql`**, so it is mounted (so each test's `\ir _fixtures/
rls_verbs.psql` resolves) but never run as a planless test. (The earlier "explicit file list"
plan was wrong: explicit-files mode binds each file alone with no parent dir, which breaks `\ir`
— directory-mode + `.psql` is the correct fix and keeps the per-test `\ir` model unchanged.)
DevOps's job also has a fail-closed guard: any `.sql`/`.pg` ever landing under `_fixtures/`
errors the run.

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

> **`\ir` relative-path note for nested cases:** `\ir` is relative to the **including file's**
> location. Top-level tests (e.g. `00_rls_inversion_self_test.sql`) use `\ir _fixtures/rls_verbs.psql`;
> cases under `supabase/tests/rls/NN_*.sql` are one dir down, so they use
> `\ir ../_fixtures/rls_verbs.psql`. Directory-mode mounts the whole tree, so both resolve.

> **Grant-then-RLS shape (isolate the layer under test):** Postgres checks the **table ACL
> before RLS**. So a cross-tenant test must hold the table-level grant OPEN to `authenticated`
> (`grant select, insert … to authenticated`) and let **RLS be the only gate** — otherwise a
> missing grant denies the probe at the ACL layer and you're testing GRANTs, not RLS. This
> mirrors prod (authenticated holds table privileges; RLS does row filtering). The inversion
> canary encodes this; Phase-6 per-table cases follow the same model. (Root-caused on PR #106:
> the canary's probe hit `permission denied` before RLS because the grant was missing.)

## Sequence coupling across files — rollback isolates rows, not id values

**Per-file `rollback` does not isolate the suite from itself for anything keyed on absolute id
values.** Postgres `nextval()` is non-transactional: a rolled-back INSERT undoes the row but never
rewinds the identity sequence it consumed. So every file that creates rows on a shared identity
column (`pfin.asset`, for one) permanently advances the starting id every LATER file sees, for the
life of the database — in whatever order `pg_prove` sorts the files.

**Consequence: any assertion that depends on the absolute VALUE of an id — not just its ordering
relative to other rows in that same file's own fixture — is silently coupled to every file that
happens to sort before it.** Worked example (SELF-330, 2026-08-20): `self200`'s `(v-embed-1)`
compared an array sorted by `asset_id` (numeric) against an array sorted by its own
`"assetid:subcatid"` text encoding (lexicographic). The two orderings agree as long as every id in
play shares the same digit count, and had agreed since the assertion was written — not because
anything guaranteed it, but because nothing had yet pushed the shared sequence past a digit-count
boundary before `self200` ran. Migration `086`'s battery (sorting before `self200` alphabetically)
was simply the first to do so. It did not break `self200`; it made a pre-existing sort-key mismatch
reachable for the first time. Fix: `order by split_part(x, ':', 1)::bigint` on the text-encoded
side — order by the same numeric key the other side uses, never by the encoded text itself.

**A REUSED scratch database hides this class of bug.** A database that has already been through a
full suite pass has its sequences already advanced past most such boundaries, so the identical
defect reads as green there and RED-3-for-3 on a freshly rebuilt one. Rebuild fresh before trusting
a green on any assertion that could depend on this.

**The rule for new batteries:** never assert on an id-derived value's ORDER, and never assert an
exact id VALUE (rather than a value fetched via `\gset`/`returning`), without an explicit,
comparison-consistent sort key on both sides. If a comparison sorts one side numerically, the other
side must sort by the same numeric key — not by a text encoding that happens to agree with it today.

Full mechanism + before/after measurement: [`rls/DESIGN.md` §16](rls/DESIGN.md).

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
supabase test db          # directory-mode (no args): mounts supabase/tests/, runs *.sql/*.pg
```

CI: own workflow `db-tests.yml` (DevOps-owned), path-triggered on `supabase/migrations/**` +
`supabase/tests/**` + `supabase/config.toml` — deliberately path-triggered (heavy DB spin-up),
unlike the always-run fast fences in `security-scan.yml`. The job runs the db-only `supabase
start -x …`, applies migrations on bring-up, runs a `select auth.uid();` smoke guard, then
`supabase test db` in directory-mode. DB major-version is pinned via `config.toml [db]
major_version` (pending F/CTO confirm vs cax21 prod PG — version-skew guard).

⟦WIRE-VALIDATE⟧ not yet executed — authored against the firmed contracts; first live run happens
once `002` lands + the DevOps CI job is wired. Per the W3-A grounding discipline, not claimed
green until that run.

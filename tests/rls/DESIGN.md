# Per-Wave RLS verification battery — framework-body design (W3-B)

**Status:** Phase 5 Step 4 W3-B. This is the **design rationale** doc. The scaffold has landed
and the battery now lives at **`supabase/tests/`** (`_fixtures/rls_verbs.sql` + `00_rls_inversion_
self_test.sql` + `sd15_fn_mask_acct_number.sql` + `README.md`). Framework shape **locked: pgTAP
via `supabase test`** (per W3-A routing). Helper-placement **Option C confirmed**, realized via
`\ir` textual include. SD-15 test **verified against authored `002_fn_mask_acct_number.sql`**.
Remaining: first live `supabase test` run (post-Sec-clear of 002 + DevOps CI job) + per-Wave
cross-tenant cases as RLS base tables land in Phase 6.

This doc is the reviewable plan for the framework body. It defines: the two-tenant fixture
shape, the reusable cross-tenant assertion verbs, the inversion self-test (harness self-proof),
the per-Wave case pattern, and the SD-15 first-target test. **Assumptions flagged `⟦A?⟧`** are
sync-points with Architect/DevOps before wiring.

---

## 1. Two-tenant fixture shape (SECURITY §4.5)

Two **synthetic, deterministic** tenants with **fixed** UUIDs (no `gen_random_uuid()` — fixed
so assertions are deterministic and diffable):

```
TENANT_A = '00000000-0000-0000-0000-00000000000a'
TENANT_B = '00000000-0000-0000-0000-00000000000b'
```

- Seeded into `auth.users` (test DB only) as the two JWT-`sub` identities.
- Tenant A **owns** rows; Tenant B's RLS context **attempts** read/write; the battery asserts
  B sees nothing it shouldn't and cannot modify what it doesn't own.
- **NO production data / NO PII / NO real account numbers** — synthetic only, per the central
  parity governance (`tests/fixtures/parity/README.md`). The two-tenant seed is **Sec
  joint-review-mandatory** when it lands.

⟦A?-1⟧ **RLS policy column convention.** Confirm policies are `users_id = auth.uid()` (post
`001_users_id_rename`). The tenant-context helper sets `request.jwt.claims.sub`; the assertion
verbs assume `auth.uid()` resolves from it. If policies key off a different claim, the helper
adjusts.

## 2. Tenant-context + assertion verbs (the reusable framework)

pgTAP-in-Supabase runs each test file as `begin; select plan(N); …; select * from finish();
rollback;`. RLS context is set per-assertion via:

```sql
-- set the active tenant for subsequent statements (within the test txn)
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', :tenant)::text, true);
```

Reusable verbs (names provisional):

| Verb | Asserts |
|---|---|
| `_rls.set_tenant(uuid)` | switches RLS context to a tenant (role + jwt.claims) |
| `_rls.expect_cross_tenant_read_empty(tbl regclass, intruder uuid)` | intruder tenant sees **0** of owner's rows |
| `_rls.expect_cross_tenant_write_blocked(tbl, intruder, payload)` | intruder INSERT/UPDATE into owner's row **fails closed** (RLS/WITH CHECK rejects) |
| `_rls.expect_owner_can_read(tbl, owner uuid, n int)` | owner sees exactly its **n** rows (guards over-restrictive policy — fail-closed both ways) |

⟦A?-2⟧ **Helper placement** — see the options below; chosen option determines whether these
verbs live in a shared test-seed or are inlined per file.

## 3. Inversion self-test (harness self-proof — mirrors W1 inversion-mode)

W1's fences fail closed if they do **not** catch the golden violation. The RLS battery needs the
same property: prove the cross-tenant assertion **has teeth** — that it actually fails when
isolation is absent, so a green battery is never vacuous.

```
00_inversion_self_test.sql:
  - create a throwaway canary table `_rls_canary(users_id uuid, val text)` with RLS DISABLED
  - seed one Tenant-A row + one Tenant-B row
  - set tenant = B
  - ASSERT the canary LEAKS A's row  (i.e. the same isolation assertion the battery uses,
    run against an unprotected table, MUST report a violation)
  → if the assertion *passes* (reports isolated) against an unprotected table, the harness
    is broken and the self-test fails. This is the battery testing the battery.
```

This file ships with the framework and runs every battery invocation. A regression here = a QA
fence gap, exactly like a W1 fence that stops catching its golden fixture.

## 4. Per-Wave case pattern (populated as migrations land)

One file per RLS-bearing table: `NN_<table>_rls.sql`. Each:
1. seeds Tenant-A-owned + Tenant-B-owned rows for that table (inside the test txn),
2. `expect_cross_tenant_read_empty` + `expect_cross_tenant_write_blocked` for B-vs-A,
3. `expect_owner_can_read` for A-sees-own (fail-closed both directions),
4. for any **SECURITY INVOKER helper** the migration adds → a cross-tenant-asserts-fails-closed
   case (per the QA agent-def).

**Today main has no RLS base tables** — so this folder starts with the inversion self-test + the
SD-15 test only; real per-table cases land per-Wave with their migrations (same PR).

## 5. SD-15 — first real per-§10-instance target (distinct test class)

`fn_mask_acct_number(p_acct TEXT) → TEXT IMMUTABLE` is a **pure transformer** — no base table,
no RLS. So its test is **not** a cross-tenant test; it is a per-§10-instance **behavioral +
no-full-disclosure** test (SD-15's first test, per the per-§10-instance discipline):

```
sd15_fn_mask_acct_number.sql:
  - is( fn_mask_acct_number('123456789'), <masked form ⟦A?-3⟧>, 'masks to last-4 only' )
  - ok( fn_mask_acct_number('123456789') NOT LIKE '%12345%', 'never discloses full value' )
  - is( fn_mask_acct_number(''), <edge ⟦A?-3⟧>, 'empty input handled' )
  - is( fn_mask_acct_number(fn_mask_acct_number(x)), fn_mask_acct_number(x), 'idempotent' )
  - the "full-value-disclosure fence" Architect's migration forward-points to is authored here
    as the mechanical assertion that the function output never contains the full input.
```

⟦A?-3⟧ **Masking contract** — confirm with Architect the exact masked format (e.g. `****6789`
vs `•••6789` vs `XXXXX6789`) + last-N digits + empty/short-input behavior, so the assertions
match the migration, not my guess.

---

## 6. Proposed file layout (post-scaffold, in `supabase/tests/`)

```
supabase/
  config.toml                ⟦A?-4⟧ DevOps/Architect: test-DB seed paths + ports
  migrations/<ts>_sd15_fn_mask_acct_number.sql   (Architect)
  seed.test.sql              (my test-only seed; helper verbs + two-tenant baseline — Option B/C)
  tests/
    00_inversion_self_test.sql
    helpers/…                (if Option A/C: inlined/partial)
    rls/NN_<table>_rls.sql   (per-Wave, populated as migrations land)
    sd/sd15_fn_mask_acct_number.sql
```

⟦A?-4⟧ **`config.toml` test settings** — coordinate with DevOps/Architect on `supabase test`
seed-path + test-DB port so the pgTAP job is deterministic in CI (ties into the task #4 ETL CI
job + the broader CI fence shape DevOps owns).

## 7. Helper-placement decision (the one real framework sub-decision) — needs a call

Where do the reusable assertion verbs + two-tenant baseline live?

- **Option A — self-contained per-test-file.** Verbs + seed declared inside each test's
  `begin…rollback`. *Pro:* total isolation, every file standalone, zero cross-file state. *Con:*
  boilerplate repetition.
- **Option B — shared test-seed.** Verbs + two-tenant baseline in `supabase/seed.test.sql`,
  loaded once into the test DB; test files call them. *Pro:* DRY, single home for tenant UUIDs.
  *Con:* helpers persist outside the per-test txn (fine for read-only verbs); prod DB must never
  load the test seed (already disciplined in the parity README).
- **Option C — hybrid (recommended).** Assertion **verbs** in the shared test-seed (DRY); the
  two-tenant **data** seeded **per-test-file** inside the rolled-back txn (no data bleed across
  tests). *Pro:* DRY verbs + isolated data. *Con:* two places to look.

**Recommendation: C.** Reusable verbs shouldn't be copy-pasted; per-test data shouldn't bleed.
Sec-relevant because it touches where synthetic seed data lives — flagging for the joint-review.

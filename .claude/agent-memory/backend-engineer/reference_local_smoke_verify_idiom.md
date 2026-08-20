---
name: reference-local-smoke-verify-idiom
description: How to apply pending migrations and smoke-verify an INVOKER function against already-seeded local data without supabase db reset.
metadata:
  type: reference
---

Local Supabase project has no `supabase link` set up (no project ref), so `supabase migration list` / `db push` fail with "Cannot find project ref." That's fine — `supabase migration up` works directly against the local Docker DB regardless of link state and is the correct command to apply pending migration files locally (confirmed working on migrations 070/071, 2026-08-13).

To verify migration state directly: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "select version from supabase_migrations.schema_migrations order by version desc limit N;"`. To check a function's posture from the catalog (never trust behavior alone to distinguish INVOKER/DEFINER — see [[feedback_execute_acl_stakes_invert_on_definer]] in the shared team memory): `select proname, prosecdef, provolatile, proacl from pg_proc where proname in (...);`.

To smoke-verify a SECURITY INVOKER, zero-tenant-parameter RPC against ALREADY-SEEDED data (not a throwaway fixture — never `supabase db reset`, it wipes F/CTO's seeded test data) without leaving side effects: wrap in `begin; ... rollback;` and set role via `set_config`, non-derived-role idiom:
```sql
begin;
select set_config('role','authenticated', true);
select set_config('request.jwt.claims', json_build_object('sub','<tenant-uuid>','role','authenticated')::text, true);
\x on
select * from pfin.fn_whatever();
\x off
rollback;
```
This is a read-only variant of the fixture-creating pattern in temp/self-202-038-smoke.sql (which inserts its own tenant fixtures then rolls back) — when the goal is exercising a function against pre-existing seeded data rather than fresh fixtures, skip the insert/fixture section entirely and just set role + claims before the query.

See also [[feedback_draft_verify_revert_when_not_branch_owner]].

**⚠ `schema_migrations` being clean/contiguous does NOT mean the DB matches it.** On 2026-08-20 the local dev DB's `schema_migrations` table was found perfectly clean at 075 (contiguous 001–075, names matching filenames, no dupes/nulls) — but several LIVE OBJECTS (three `CREATE OR REPLACE FUNCTION`s from migrations 076/078) already existed in `pg_proc`, applied out-of-band at some earlier point without their `schema_migrations` rows ever being committed. Bookkeeping-table cleanliness only proves the bookkeeping is clean, not that the underlying objects match it. Before trusting "DB is at version N" for anything beyond a routine `migration up`, spot-check a few of the NEXT pending migrations' objects directly (`select proname from pg_proc where proname = '...'`, `select column_name from information_schema.columns where ...`) rather than assuming a gap between recorded and file versions means nothing has run. In practice this didn't block anything: because the drifted migrations used idempotent forms (`CREATE OR REPLACE FUNCTION`, `CREATE TABLE IF NOT EXISTS`), replaying them in order via `supabase migration up` converged cleanly and backfilled the bookkeeping with zero conflicts — but a non-idempotent migration (a bare `ALTER TABLE ADD COLUMN` without a guard, a `CREATE TABLE` without `IF NOT EXISTS`) would have errored instead, and that's the case worth checking for before running `migration up` blind on a DB with a known/suspected bookkeeping gap.

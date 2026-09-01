---
name: scratch-db-for-migration-verify
description: How to clean-apply migrations without the banned reset — createdb on the running Supabase container + a container-side pg_dump of the auth schema.
metadata:
  type: reference
---

Verify a migration clean-apply against the LOCAL Supabase stack without touching
F/CTO's data. The banned reset command is hook-blocked outright (any form).

**Recipe** (verified end-to-end 2026-08-30, SELF-344, 95 migrations, 0 failures):
1. Container `supabase_db_mosko-fintech` listens on **127.0.0.1:54322**, db
   `postgres`, user `postgres`, password `postgres`. PG 17.6.
2. `createdb -h 127.0.0.1 -p 54322 -U postgres <scratch>`.
3. `create extension` pgcrypto, "uuid-ossp", pgtap, `supabase_vault cascade`.
4. ⚠ **The `auth` schema is per-database** and the migrations need it. Dump it
   from `postgres`: `docker exec supabase_db_mosko-fintech pg_dump -U postgres
   -d postgres --schema-only --schema=auth --no-owner --no-privileges`.
   **Homebrew's local pg_dump is v14 and REFUSES the 17.6 server** — must run
   inside the container. Roles (`authenticated`/`service_role`/`anon`) are
   cluster-level and already exist.
5. Loop `psql -v ON_ERROR_STOP=1 -q -f` per file in sorted order.
6. `dropdb` when done; re-read a table in `postgres` to prove it was untouched.

**Seeding `pfin.nav_daily` fails without a GUC.** The ADR-011 Decision 1 write
fence (`fn_nav_daily_assert_computed_for`) rejects any INSERT whose `users_id`
does not equal `app.nav_computed_for`. Set it transaction-locally first:
`select set_config('app.nav_computed_for','<uuid>', true);` — see
[[feedback_capability_verify_adr_db_primitives]].

**How to make the measurement test the FIX and not the fixture:** restore the
superseded function bodies inside a `begin; \i old.sql; <measure>; rollback;`
and show the defect reproducing on the SAME fixture, keeping one unaffected
horizon as the control leg. See
[[feedback_inversion_test_the_rationale_not_the_presence]].

---
name: reference-nav-daily-write-tenant-binding-fence
description: pfin.nav_daily has a fn_nav_daily_assert_computed_for trigger requiring app.nav_computed_for set to the row's users_id before every INSERT, even as postgres — a plain privileged seed INSERT fails without it.
metadata:
  type: reference
---

`pfin.nav_daily` (054, SELF-214 B7 / ADR-011 Decision 1 clause (c)) carries a write-tenant
binding fence: `fn_nav_daily_assert_computed_for()` rejects any INSERT where the row's
`users_id` doesn't match the transaction-local GUC `app.nav_computed_for` — "the checkpoint's
tenant must equal the tenant the database actually served during the impersonated read."

This fires **regardless of role** (measured: a plain `insert into pfin.nav_daily (...)` as
`postgres` was REJECTED, not just under RLS/authenticated). Before any nav_daily fixture
INSERT: `select set_config('app.nav_computed_for', :'tenant_uuid', true);` — transaction-local
(`true` = local), so it must be set immediately before EACH insert (or at least before the
first one in the same transaction if the value doesn't change).

054's own battery (`054_nav_daily_rls.sql`) is the exhaustive proof of this fence's edges (w1
NULL-trap, w2 empty-string trap, w5/w12 idempotent-rowcount pair). Discovered authoring
SELF-269's close-gate (2026-09-04) when a first-draft nav_daily fixture block died with
`P0001 write-tenant binding REJECTED` on a plain seed insert, killing the rest of that pgTAP
transaction (18 legs). [[feedback_scratch_db_pgtap_harness_gotchas]]

-- =====================================================================
-- Per-Wave battery — pfin.asset GLOBAL-ASSET service_role WRITE-PATH + cusip global dedup
--   (ADR-027 provider-sync worker / 020 — C6 EXPOSURE-GATING per ADR-023 / SECURITY §4.5;
--    V1-SHIP-BLOCK; JOINT-REVIEW-MANDATORY — a NEW service_role write path on an
--    all-tenants-readable table. This battery is the merge-gate.)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/020_asset_global_write_path.sql
--   (A) grant select, insert on pfin.asset to service_role — the worker auto-registers an unknown
--       symbol/cusip as a GLOBAL asset row (users_id NULL). LEAN: SELECT+INSERT only (no UPDATE —
--       enrichment V2; no DELETE — least privilege).
--   (B) asset_global_cusip_uniq — unique(cusip) WHERE users_id IS NULL AND cusip IS NOT NULL
--       (fixed-income cusip dedup; mirrors 016 asset_global_symbol_uniq on cusip).
--   016 policies UNCHANGED: asset_select (global-OR-owned) + asset_insert/update/delete WITH CHECK
--       (users_id = auth.uid()). This migration adds ONLY service_role reachability.
-- Prereqs exercised (001→020): 001/003 (pfin schema + auth.users), 008 (service_role pfin USAGE),
--   016 (pfin.asset hybrid registry + owner-only WITH CHECK + asset_global_symbol_uniq + the cusip
--   column), 020 (the grant + the cusip index). References no other pfin table.
-- Reuses the 016/017/018/019 idiom: \ir verbs, ALL-LOWERCASE \gset, SQLSTATE-precise throws_ok +
--   CONSTRAINT-NAME-precise throws_like (004 all-42501/all-23505 false-green lesson), role restored
--   to postgres between blocks (PR #121 _rls-USAGE root-cause).
--
-- ┌─ THE NEW RISK THIS BATTERY GUARDS (why it is not vanilla isolation) ───────────────────────────┐
-- │ Every OTHER service_role writer (015/018/019) lands TENANT-SCOPED data. pfin.asset is different: │
-- │ a GLOBAL row (users_id NULL) is readable by ALL tenants (016 asset_select). So the new write path │
-- │ must prove THREE things a vanilla battery misses:                                                 │
-- │   (a) service_role CAN write a global row AND it is genuinely SHARED-READ (BOTH tenants see it) — │
-- │       the intended design, not a leak. Vanilla isolation would never assert cross-tenant VISIBILITY.│
-- │   (b) authenticated STILL cannot forge a global row — the new service_role grant must NOT have     │
-- │       widened the authenticated lane (016 owner-only WITH CHECK still fences NULL = auth.uid()).   │
-- │   (c) per-user isolation is INTACT under the new grant — B still reads 0 of A's private assets.    │
-- │ Plus (d): the cusip dedup keeps the global registry collision-free (worker ON CONFLICT idiom).     │
-- └────────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ WHY EACH SIGNAL IS DISTINCT (no fence passes for another) ────────────────────────────────────┐
-- │  • authenticated forge-global INSERT      -> 016 asset_insert WITH CHECK -> 42501 (throws_ok)     │
-- │  • duplicate GLOBAL cusip                  -> asset_global_cusip_uniq -> 23505 (constraint-name)   │
-- │  • cross-tenant per-user read (B on A)     -> 016 asset_select filters -> 0 rows (is, not throw)   │
-- │ SQLSTATE-precise (42501 forge vs 23505 dedup) + CONSTRAINT-NAME (cusip vs symbol index, both 23505)│
-- │ + behavioral 0-row (silent RLS filter) keeps one fence from ever passing for another (004 lesson). │
-- └────────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (a1)  -> non-vacuous control: service_role INSERT of a GLOBAL row SUCCEEDS (the 020 grant is LIVE
--            — a green (b1) forge-block is not a vacuously-absent grant).
--   (a2)/(a3) -> SHARED-READ (the design intent): BOTH tenant A and tenant B read the same global row.
--            RED if the 016 `users_id IS NULL` read disjunct were dropped (global reference vanishes).
--   (b1)  -> LOAD-BEARING: RED if the new service_role grant widened authenticated into the global
--            lane — a user must STILL be unable to forge a global row (016 WITH CHECK: NULL = auth.uid()
--            → NULL → fail-closed 42501). Proves the grant is service_role-ONLY.
--   (c1)  -> RED if per-user isolation regressed under the new grant: B reads A's private per-user asset.
--   (c2)  -> non-vacuous positive: A reads its OWN per-user asset (guards an over-restrictive read).
--   (d1)  -> RED if asset_global_cusip_uniq were dropped: two global rows with the same cusip → the
--            worker's fixed-income registry double-registers a bond (constraint-name-precise 23505).
--   (d2)  -> the worker's dedup idiom: ON CONFLICT (cusip) DO NOTHING collapses a re-presented global
--            cusip → the registry count stays 1 (RED if the arbiter did not infer the partial index).
--   (d3)  -> PARTIAL-index scoping: a PER-USER row with the same cusip does NOT collide (the index is
--            WHERE users_id IS NULL) — RED if the index over-constrained per-user assets.
--   (f1)  -> non-vacuous ACL positive: service_role HOLDS INSERT (the write path is live).
--   (f2)/(f3) -> LEAN grant posture: service_role holds NO UPDATE (enrichment = V2) and NO DELETE
--            (least privilege) — RED if either were granted.
--   (f4)  -> anon zero-grant by construction (schema-usage fence + no table grant).
--   (e)   -> N/A — Sec ACCEPTED Option A at joint-review (#20, 2026-07-17): plain least-privilege
--            grant, NO global-lane role-guard fence. There is therefore no per-user-insert fence to
--            assert (under Option A a service_role per-user insert would simply succeed — service_role
--            is the trusted privileged writer, Decision 1; the global-lane discipline is app-layer).
--            The (e) leg is NOT authored; the battery is final at plan(13).
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 2 (RT-22 + RT-26; the service_role grant is a DB-LAYER
--   ACL, not the RT-26 code-layer allowlist surface — per the 020 header §10 3-axis, Path B).
--   Decision-3 family UNCHANGED at 8 realized: 020 adds a GRANT (an ACL, not a column) + a partial-
--   UNIQUE INDEX on cusip (TEXT identity, NOT an FK) → no FK-shaped tenant-crossing reference.
--   pfin.asset.users_id stays the SOLE tenant anchor. This battery adds no ledger change.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b(); NO PII /
--   real account numbers / prod data. A owns a per-user asset (users_id EXPLICIT — auth.uid() is NULL
--   under postgres). GLOBAL rows are written by service_role (BYPASSRLS) — the exact 020 write path.
--   All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated. Tenant UUIDs +
--   the per-user asset id resolved to psql LITERALS via \gset at role=postgres; every _rls.set_tenant
--   is called at role=postgres and each block restores role=postgres before the next. \gset var names
--   ALL-LOWERCASE. GLOBAL-row reads use manual is(count where symbol=… / cusip=… and users_id is null);
--   per-user cross-tenant reads key on users_id.
--
-- ⟦WIRE-VALIDATE⟧ authored + smoke-verified GREEN against the 001→020 stack (DB at 019; 020 transiently
--   applied + rolled back) 2026-07-16. service_role name-checked (BYPASSRLS + the 020 grant + pgTAP
--   fn execute). CI pg_prove directory-mode after Backend's apply is the green gate. plan(13) — FINAL
--   (Sec accepted Option A at #20; no Option-C (e) leg).
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

select plan(13);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres — RLS-bypassed seed path).
--   A owns a per-user asset (users_id EXPLICIT — auth.uid() NULL under postgres → an omitted users_id
--   would land a GLOBAL row). B seeds nothing (reads only). Global rows are written by service_role below.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.asset (users_id, asset_type, pricing_source, name)
  values (:'ta', 'collectible', 'manual_valuation', 'A Private')
  returning asset_id as a_peruser \gset

-- =====================================================================
-- LEG (a) + (d) — the service_role GLOBAL write path (BYPASSRLS; the 020 grant).
-- =====================================================================
select set_config('role', 'service_role', true);

-- (a1) service_role INSERT of a GLOBAL equity row SUCCEEDS (the 020 grant is live).
select lives_ok(
  $$ insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
       values (null, 'equity', 'market_feed', 'GLOBEQ', 'Global Equity') $$,
  '(a1) service_role global write: INSERT of a GLOBAL asset row (users_id NULL) SUCCEEDS — the 020 SELECT+INSERT grant is LIVE (the worker auto-registration path)'
);

-- setup for (d): an existing GLOBAL fixed-income row keyed by cusip 'C123' (distinct symbol so the
-- symbol index never fires — the cusip index is the isolated arbiter).
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, cusip, name)
  values (null, 'bond', 'market_feed', 'BONDA', 'C123', 'Bond A');

-- (d1) duplicate GLOBAL cusip → asset_global_cusip_uniq (constraint-name-precise; DISTINCT symbol
--      'BONDB' so this is the cusip index firing, NOT the symbol index).
select throws_like(
  $$ insert into pfin.asset (users_id, asset_type, pricing_source, symbol, cusip, name)
       values (null, 'bond', 'market_feed', 'BONDB', 'C123', 'Bond B dup') $$,
  '%asset_global_cusip_uniq%',
  '(d1) cusip dedup has teeth: a 2nd GLOBAL row with cusip ''C123'' (distinct symbol) → asset_global_cusip_uniq unique_violation (23505, constraint-name-precise) — fixed-income assets dedup on CUSIP, not symbol'
);

-- (d2) worker dedup idiom: ON CONFLICT (cusip) WHERE ... DO NOTHING collapses the re-presented cusip
--      (a plain statement; the arbiter infers the partial index → the row is skipped).
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, cusip, name)
  values (null, 'bond', 'market_feed', 'BONDC', 'C123', 'Bond C')
  on conflict (cusip) where users_id is null and cusip is not null do nothing;
select is(
  (select count(*) from pfin.asset where cusip = 'C123' and users_id is null)::bigint, 1::bigint,
  '(d2) ON CONFLICT (cusip) DO NOTHING collapses: a re-presented global cusip ''C123'' is SKIPPED (arbiter infers asset_global_cusip_uniq) — the global registry count stays 1 (the worker''s dedup-safe write)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (a2) + (b) + (c2) + (d3) — authenticated A: shared-read, forge-block, own-read, partial-index.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (a2) SHARED-READ: A reads the service_role-written global equity (users_id NULL disjunct).
select is(
  (select count(*) from pfin.asset where symbol = 'GLOBEQ' and users_id is null)::bigint, 1::bigint,
  '(a2) shared-read (tenant A): A reads the service_role-written GLOBAL equity row (016 asset_select `users_id IS NULL` disjunct exposes shared reference data written by the 020 path)'
);

-- (b1) LOAD-BEARING: authenticated A STILL cannot forge a global row (016 WITH CHECK NULL = auth.uid()).
select throws_ok(
  $$ insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
       values (null, 'equity', 'market_feed', 'FORGEQ', 'Forged Global') $$,
  '42501', null,
  '(b1) LOAD-BEARING forge-block: authenticated A inserting a GLOBAL row (users_id NULL) is STILL REJECTED by 016 asset_insert WITH CHECK (NULL = auth.uid() → NULL → fail-closed 42501) — the new 020 service_role grant did NOT widen the authenticated lane'
);

-- (c2) non-vacuous positive: A reads its OWN per-user asset.
select is(
  (select count(*) from pfin.asset where users_id = :'ta')::bigint, 1::bigint,
  '(c2) owner reads own: authenticated A reads its 1 own per-user asset (read path not over-restrictive)'
);

-- (d3) PARTIAL-index scoping: a PER-USER row with cusip 'C123' does NOT collide (the cusip index is
--      WHERE users_id IS NULL → per-user rows are outside it).
select lives_ok(
  $$ insert into pfin.asset (asset_type, pricing_source, cusip, name)
       values ('bond', 'manual_valuation', 'C123', 'A Private Bond') $$,
  '(d3) partial-index scoping: A inserts a PER-USER asset (users_id DEFAULT auth.uid()) with cusip ''C123'' → ACCEPTED (asset_global_cusip_uniq is WHERE users_id IS NULL, so it does NOT constrain per-user rows even on a colliding cusip)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (a3) + (c1) — authenticated B: shared-read (same global) + per-user isolation intact.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);

-- (a3) SHARED-READ (both tenants): B reads the SAME service_role-written global equity as A.
select is(
  (select count(*) from pfin.asset where symbol = 'GLOBEQ' and users_id is null)::bigint, 1::bigint,
  '(a3) shared-read (tenant B): B reads the SAME service_role-written GLOBAL equity as A (identical global row — the 020 write path lands genuinely SHARED reference data, not a per-tenant leak)'
);

-- (c1) per-user isolation INTACT under the new grant: B reads 0 of A's per-user rows.
select is(
  (select count(*) from pfin.asset where users_id = :'ta')::bigint, 0::bigint,
  '(c1) isolation intact under the 020 grant: tenant B reads 0 of A''s per-user asset rows (016 asset_select users_id = auth.uid() still excludes another tenant''s private assets — the service_role write path did not weaken per-user isolation)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (f) — LEAN grant posture (ACL facts, run as postgres — role-agnostic).
-- =====================================================================
-- (f1) service_role HOLDS INSERT (the 020 write path is live).
select ok(
  has_table_privilege('service_role', 'pfin.asset', 'INSERT'),
  '(f1) ACL positive: service_role HOLDS INSERT on pfin.asset (the 020 global-asset auto-registration write path is live)'
);
-- (f2) service_role holds NO UPDATE (enrichment = V2).
select ok(
  not has_table_privilege('service_role', 'pfin.asset', 'UPDATE'),
  '(f2) lean grant: service_role holds NO UPDATE on pfin.asset (enrichment — cusip/name/figi backfill — is DEFERRED to V2; RED if an UPDATE grant were added)'
);
-- (f3) service_role holds NO DELETE (least privilege).
select ok(
  not has_table_privilege('service_role', 'pfin.asset', 'DELETE'),
  '(f3) least-privilege: service_role holds NO DELETE on pfin.asset (the worker never deletes a global asset; RED if a DELETE grant were added)'
);
-- (f4) anon zero-grant by construction.
select ok(
  not has_table_privilege('anon', 'pfin.asset', 'SELECT'),
  '(f4) anon zero-grant: anon holds NO SELECT on pfin.asset (schema-usage fence + no table grant — by construction, ADR-023 C2)'
);

select * from finish();
rollback;

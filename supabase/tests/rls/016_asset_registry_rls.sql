-- =====================================================================
-- Per-Wave battery — pfin.asset UNIVERSAL asset registry, HYBRID RLS
--   (ADR-027 / 016 — C6 EXPOSURE-GATING per ADR-023 / SECURITY §4.5; V1-SHIP-BLOCK;
--    sec-joint-review GREEN, this battery named the merge-gate)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/016_asset_registry.sql
--   - pfin.asset  (universal asset-definition registry; HYBRID population under one table:
--       GLOBAL rows users_id IS NULL — market/currency reference, shared/readable by ALL
--       authenticated; PER-USER rows users_id = a uuid — physical/custom, owner-private).
--   - RLS (the NOVEL hybrid posture — the batch Sec merge-block 6):
--       SELECT using (users_id is null OR users_id = auth.uid())  -- global-OR-owned read
--       INSERT with check (users_id = auth.uid())                 -- owner-only create; no forge
--       UPDATE using (users_id = auth.uid()) with check (= auth.uid())  -- owner-only edit
--       DELETE using (users_id = auth.uid())                      -- owner-only delete
--   - GRANT authenticated SELECT/INSERT/UPDATE/DELETE (active V1 write path — SELF-201
--       manual-asset onboarding; contrast 009 user_taxonomy SELECT-only dormancy).
--       anon ZERO-grant (schema-usage fence, 001/003). service_role UNGRANTED in 016.
--   - Committed GLOBAL currency-asset identity seed: 7 rows users_id NULL (USD + majors),
--       asset_type 'currency', pricing_source 'fx_feed' (011-style global reference data).
--   - Partial-uniques: asset_global_symbol_uniq = unique(symbol) where users_id IS NULL;
--       asset_user_name_uniq = unique(users_id, name) where users_id IS NOT NULL.
-- Prereqs exercised (already on main): 001 (pfin schema + fn_refresh_updated_at, reused for
--   the updated_at trigger) + auth.users (the users_id anchor). References NO other pfin table.
-- Reuses the SELF-187/189/190/196/231/012/015 idiom: \ir verbs, ALL-LOWERCASE \gset literals
--   (005 case-fold lesson), SQLSTATE-precise throws_ok (004 all-42501 false-green lesson), role
--   restored to postgres between blocks (PR #121 _rls-USAGE root-cause).
--
-- ┌─ WHY THIS IS A HYBRID BATTERY, NOT VANILLA ISOLATION (Sec was explicit) ───────────────┐
-- │ A vanilla two-tenant battery would prove only "B sees 0 of A's rows". That is NECESSARY  │
-- │ (leg b) but INSUFFICIENT for pfin.asset, because the table has a SECOND population — the  │
-- │ NULL-owner GLOBAL rows — that BOTH tenants MUST read AND NEITHER may forge/mutate. The    │
-- │ two hybrid-only legs vanilla misses:                                                       │
-- │   (a) GLOBAL-READABLE-BY-BOTH — A and B each read the SAME committed global set (USD +     │
-- │       majors). RED if the SELECT policy dropped the `users_id IS NULL OR` disjunct (global │
-- │       reference data would vanish for everyone — a functional break masquerading as        │
-- │       "isolation"). A vanilla battery would still pass, so it cannot guard this.           │
-- │   (c) NO-GLOBAL-FORGE — B cannot INSERT a users_id = NULL row (fabricate global reference  │
-- │       data): `NULL = auth.uid()` is NULL → WITH CHECK fail-closed → 42501. RED if WITH      │
-- │       CHECK were widened to permit NULL owners (any tenant could poison the shared registry │
-- │       every other tenant reads). Vanilla batteries never test a NULL-owner INSERT.          │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ WHY EACH REJECTION MATCHES A DIFFERENT SIGNAL (no fence passes for another) ─────────────┐
-- │  • cross-tenant PER-USER read (B on A)      -> RLS SELECT filters -> 0 rows (is, not throw) │
-- │  • forge-global / forge-owned-by-A INSERT   -> RLS WITH CHECK -> 42501 (throws_ok)          │
-- │  • cross-tenant / global UPDATE|DELETE       -> RLS USING excludes -> 0 rows AFFECTED;       │
-- │       asserted as target-row-UNCHANGED / STILL-PRESENT on a privileged re-read (RLS filters, │
-- │       it does NOT raise — a silent 0-row is the honest signal, distinct from a 42501)        │
-- │  • per-user name collision WITHIN a tenant   -> asset_user_name_uniq -> 23505 (unique_viol)  │
-- │  • duplicate GLOBAL symbol (seed/DDL path)   -> asset_global_symbol_uniq -> 23505            │
-- │ SQLSTATE-precise (42501 forge vs 23505 collision) + behavioral 0-row (silent RLS filter)     │
-- │ keeps one fence from ever passing for another (the 004 all-42501 discipline).                │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (a1)/(a2)  -> HYBRID load-bearing: RED if the SELECT `users_id IS NULL OR` disjunct were
--                  dropped -> global reference rows would disappear for BOTH tenants (a vanilla
--                  isolation battery would stay green — this is the leg only a hybrid battery guards).
--   (a3)         -> concrete shared-global proof: BOTH tenants read the SAME USD global row.
--   (b1)         -> non-vacuous positive: owner A reads exactly its 3 own per-user rows (guards an
--                  over-restrictive SELECT that also hid the owner's own rows).
--   (b2)         -> RED if the SELECT policy leaked per-user rows (B reads A's private physical assets).
--   (c1)         -> HYBRID load-bearing: RED if WITH CHECK permitted users_id = NULL -> any tenant
--                  could FORGE a global row into the shared registry every other tenant reads.
--   (c2)         -> RED if WITH CHECK permitted users_id = <other tenant> -> B could plant a row owned by A.
--   (c3)         -> non-vacuous control: B inserting its OWN row SUCCEEDS -> proves (c1)/(c2) are
--                  owner-mismatch-driven, not a blanket authenticated-B INSERT block.
--   (d1)/(d2)    -> RED if the UPDATE/DELETE USING clause were widened -> B could mutate/delete A's
--                  PER-USER rows (cross-tenant tamper). Asserted as A's row unchanged / still present.
--   (d3)/(d4)    -> HYBRID load-bearing: RED if USING did not exclude NULL-owner rows -> a tenant
--                  could edit/delete the SHARED global registry. Asserted as USD unchanged / still present.
--   (e1)/(e2)    -> non-vacuous positives: owner A UPDATEs + DELETEs its OWN per-user rows (guards an
--                  over-restrictive USING that blocked even the legitimate owner write path).
--   (f1)         -> partial-unique partitions by tenant: A and B may EACH own a per-user 'House' (same
--                  name, different users_id) with NO collision. RED if the index omitted users_id.
--   (f2)         -> asset_user_name_uniq has teeth WITHIN a tenant: A's 2nd 'House' -> 23505.
--   (f3)         -> asset_global_symbol_uniq has teeth (seed/DDL-scoped — users cannot insert globals,
--                  proven by (c1), so exercised on the privileged seed path): duplicate global 'USD' -> 23505.
--   (g1)         -> non-vacuous ACL positive: authenticated HOLDS INSERT (active V1 write path — the
--                  grant is not vacuously absent; RED if 016 shipped SELECT-only like 009).
--   (g2)/(g3)    -> RED if anon or service_role were ever granted reach to pfin.asset (anon zero-grant
--                  by construction; service_role's global-enrichment write path is DEFERRED + C6-gated).
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 2 (RT-22 + RT-26; 016 introduces ZERO catalogued §10
--   instances — hybrid RLS + GRANT + reference seed are authenticated-tier DB-layer work, NOT the
--   RT-26 code-layer SERVICE_ROLE_KEY allowlist grep nor the RT-22 PDF-worker infra fence; per the
--   016 header §10 3-axis + Decision-3 eval, Path B). Decision-3 family UNCHANGED at 6: pfin.asset.
--   users_id is the SOLE tenant anchor (not a cross-tenant reference), NULL = a legitimate global row;
--   the novel global-OR-matched-tenant FENCES that reference this table are authored at 017/020 and
--   evaluated THERE (016 defines only the referenced registry — it adds no D3 instance).
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b(); NO PII /
--   NO real account numbers / NO prod data. Per-user asset CRUD IS an active V1 authenticated write
--   path (SELF-201), so A's per-user rows are inserted PRIVILEGED with users_id set EXPLICITLY (under
--   postgres auth.uid() is NULL, so the DEFAULT would land a GLOBAL row — the explicit users_id is
--   mandatory here); B's own rows are created under authenticated B via the DEFAULT auth.uid() path
--   (the realistic app path). The committed global currency rows come from the migration seed itself.
--   All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so NO `_rls.*`
--   call runs under authenticated. Tenant UUIDs, the global count, and row ids are resolved to psql
--   LITERALS via \gset at role=postgres; every _rls.set_tenant is called at role=postgres and each
--   block restores role=postgres before the next. \gset var names are ALL-LOWERCASE. The cross-tenant/
--   global UPDATE|DELETE probes execute under authenticated (RLS filters to 0 rows — no raise) and are
--   ASSERTED by a privileged re-read (the row survived) so RLS — not an ACL — is the sole gate proven.
--   has_table_privilege probes run as postgres (ACL facts, role-agnostic).
--
-- ⟦WIRE-VALIDATE⟧ authored against 016's firmed contract; the authoritative run is against the
--   001->016 reset stack. Roles authenticated / anon / service_role name-checked. RED-until-016-applied
--   is expected on any pre-016 stack (pfin.asset + the committed currency seed absent).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(20);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed).
--  - Two tenants in auth.users.
--  - gcount = the count of committed GLOBAL rows (users_id NULL) the migration seed landed
--    (7 currency identities; resolved dynamically so the battery is robust to a future seed add).
--  - A owns THREE per-user rows (users_id set EXPLICITLY — auth.uid() is NULL under postgres, so
--    an omitted users_id would land a GLOBAL row): a_house ('House', target of the cross-tenant
--    mutate probes), a_edit (owner-UPDATE target), a_del (owner-DELETE target).
--  - B seeds NO privileged per-user rows here; B creates its own rows under authenticated B below
--    via the DEFAULT auth.uid() app path (the realistic write path + the (c3)/(f1) controls).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

select count(*) as gcount from pfin.asset where users_id is null \gset

insert into pfin.asset (users_id, asset_type, pricing_source, name)
  values (:'ta', 'real_estate', 'manual_valuation', 'House')
  returning asset_id as a_house \gset
insert into pfin.asset (users_id, asset_type, pricing_source, name)
  values (:'ta', 'vehicle', 'manual_valuation', 'A Editable')
  returning asset_id as a_edit \gset
insert into pfin.asset (users_id, asset_type, pricing_source, name)
  values (:'ta', 'collectible', 'manual_valuation', 'A Deletable')
  returning asset_id as a_del \gset

-- =====================================================================
-- LEG (a) GLOBAL-READABLE-BY-BOTH + LEG (b) PER-USER ISOLATION — read side.
-- =====================================================================
-- BLOCK A-READ (authenticated A).
select _rls.set_tenant(:'ta'::uuid);

-- (a1) HYBRID: A reads the full committed GLOBAL set (users_id NULL rows are shared).
select is(
  (select count(*) from pfin.asset where users_id is null)::bigint, :gcount::bigint,
  '(a1) HYBRID global-readable: tenant A reads all committed GLOBAL rows (users_id IS NULL) — the SELECT `users_id IS NULL OR` disjunct exposes shared reference data'
);

-- (b1) non-vacuous positive: A reads exactly its 3 own per-user rows (not over-restrictive).
select is(
  (select count(*) from pfin.asset where users_id = :'ta')::bigint, 3::bigint,
  '(b1) per-user positive: owner A reads exactly its 3 own per-user rows (users_id = auth.uid(); read path not over-restrictive)'
);
select set_config('role', 'postgres', true);

-- BLOCK B-READ (authenticated B) — same shared globals; zero of A's per-user rows.
select _rls.set_tenant(:'tb'::uuid);

-- (a2) HYBRID: B reads the SAME global set A did (identical count -> shared, not per-tenant).
select is(
  (select count(*) from pfin.asset where users_id is null)::bigint, :gcount::bigint,
  '(a2) HYBRID global-readable: tenant B reads the SAME committed GLOBAL set as A (identical users_id-NULL count — the global population is shared, not per-tenant)'
);

-- (a3) concrete shared-global: B reads the USD global row (the base unit both tenants depend on).
select is(
  (select count(*) from pfin.asset where symbol = 'USD' and users_id is null)::bigint, 1::bigint,
  '(a3) HYBRID concrete: tenant B reads the shared USD global currency-asset (users_id NULL) — both tenants resolve the same base-unit row'
);

-- (b2) cross-tenant per-user read fails closed: B sees ZERO of A's per-user rows.
select is(
  (select count(*) from pfin.asset where users_id = :'ta')::bigint, 0::bigint,
  '(b2) per-user isolation: tenant B sees 0 of A''s per-user rows (RLS SELECT users_id = auth.uid() excludes another tenant''s private assets)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (c) NO-GLOBAL-FORGE (INSERT) — the hybrid WITH CHECK fence.
-- =====================================================================
-- BLOCK B-FORGE (authenticated B).
select _rls.set_tenant(:'tb'::uuid);

-- (c1) HYBRID load-bearing: B cannot FORGE a global row (users_id = NULL fails WITH CHECK).
select throws_ok(
  $$ insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
       values (null, 'currency', 'fx_feed', 'XTS', 'Forged Global') $$,
  '42501', null,
  '(c1) HYBRID no-global-forge: B inserting users_id = NULL (fabricate a shared global row) is REJECTED by WITH CHECK (NULL = auth.uid() -> NULL -> fail-closed, 42501) — a tenant cannot poison the shared registry'
);

-- (c2) B cannot plant a row OWNED BY A (users_id = A fails WITH CHECK equality).
select throws_ok(
  format($$ insert into pfin.asset (users_id, asset_type, pricing_source, name)
              values (%L, 'real_estate', 'manual_valuation', 'B plants on A') $$, :'ta'),
  '42501', null,
  '(c2) no cross-tenant plant: B inserting users_id = A''s uuid is REJECTED by WITH CHECK (A = auth.uid()=B -> false, 42501) — cannot create a row owned by another tenant'
);

-- (c3) non-vacuous control: B inserting its OWN row (users_id DEFAULT auth.uid()=B) SUCCEEDS.
select lives_ok(
  $$ insert into pfin.asset (asset_type, pricing_source, name)
       values ('vehicle', 'manual_valuation', 'B Boat') $$,
  '(c3) control: B inserts its OWN per-user row (users_id omitted -> DEFAULT auth.uid()=B) -> ACCEPTED (proves (c1)/(c2) are owner-mismatch-driven, not a blanket authenticated-B INSERT block)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (d) NO CROSS-TENANT / NO-GLOBAL MUTATE (UPDATE + DELETE) — the USING fence.
--   Executed under authenticated B (RLS USING filters the rows out -> 0 rows AFFECTED, no raise);
--   asserted by a PRIVILEGED re-read that the target survived UNCHANGED.
-- =====================================================================
-- BLOCK B-MUTATE (authenticated B) — four 0-row mutations (silent RLS filter, no error).
select _rls.set_tenant(:'tb'::uuid);
update pfin.asset set name = 'hacked-peruser'  where asset_id = :a_house;               -- cross-tenant UPDATE (d1)
delete from pfin.asset                          where asset_id = :a_house;               -- cross-tenant DELETE (d2)
update pfin.asset set name = 'hacked-global'    where symbol = 'USD' and users_id is null; -- global UPDATE (d3)
delete from pfin.asset                          where symbol = 'USD' and users_id is null; -- global DELETE (d4)
select set_config('role', 'postgres', true);

-- (d1) cross-tenant UPDATE had NO effect: A's per-user row name is unchanged.
select is(
  (select name from pfin.asset where asset_id = :a_house),
  'House',
  '(d1) no cross-tenant UPDATE: B''s UPDATE of A''s per-user row affected 0 rows (RLS USING users_id = auth.uid() excludes it) — A''s row name is UNCHANGED'
);
-- (d2) cross-tenant DELETE had NO effect: A's per-user row still exists.
select is(
  (select count(*) from pfin.asset where asset_id = :a_house)::bigint, 1::bigint,
  '(d2) no cross-tenant DELETE: B''s DELETE of A''s per-user row affected 0 rows (RLS USING excludes it) — A''s row still PRESENT'
);
-- (d3) HYBRID: global UPDATE had NO effect: the shared USD row is unchanged (USING excludes NULL-owner).
select is(
  (select name from pfin.asset where symbol = 'USD' and users_id is null),
  'US Dollar',
  '(d3) HYBRID no-global-mutate: B''s UPDATE of the shared USD global row affected 0 rows (USING excludes NULL-owner rows) — the shared registry is UNCHANGED'
);
-- (d4) HYBRID: global DELETE had NO effect: the shared USD row still exists.
select is(
  (select count(*) from pfin.asset where symbol = 'USD' and users_id is null)::bigint, 1::bigint,
  '(d4) HYBRID no-global-delete: B''s DELETE of the shared USD global row affected 0 rows (USING excludes NULL-owner rows) — the shared registry row still PRESENT'
);

-- =====================================================================
-- LEG (e) OWNER CRUD — A edits + deletes its OWN per-user rows (non-vacuous positives).
--   + (f2) A's within-tenant name collision (runs under authenticated A alongside the owner writes).
-- =====================================================================
-- BLOCK A-OWN (authenticated A) — owner UPDATE + owner DELETE (executed) + (f2) collision (asserted).
select _rls.set_tenant(:'ta'::uuid);
update pfin.asset set name = 'A Edited' where asset_id = :a_edit;   -- owner UPDATE (verified below as e1)
delete from pfin.asset            where asset_id = :a_del;          -- owner DELETE (verified below as e2)

-- (f2) within-tenant collision: A already owns 'House' (a_house), so a 2nd 'House' -> asset_user_name_uniq.
select throws_ok(
  $$ insert into pfin.asset (asset_type, pricing_source, name)
       values ('real_estate', 'manual_valuation', 'House') $$,
  '23505', null,
  '(f2) per-user unique WITHIN a tenant: A inserting a 2nd row named ''House'' -> asset_user_name_uniq unique_violation (23505) — the per-user (users_id, name) partial-unique has teeth inside a tenant'
);
select set_config('role', 'postgres', true);

-- (e1) owner UPDATE persisted: A's editable row now carries the new name (privileged re-read).
select is(
  (select name from pfin.asset where asset_id = :a_edit),
  'A Edited',
  '(e1) owner UPDATE: A edited its OWN per-user row (USING + WITH CHECK users_id = auth.uid()) -> the change PERSISTED (owner write path not over-restrictive)'
);
-- (e2) owner DELETE persisted: A's deletable row is gone.
select is(
  (select count(*) from pfin.asset where asset_id = :a_del)::bigint, 0::bigint,
  '(e2) owner DELETE: A deleted its OWN per-user row (USING users_id = auth.uid()) -> the row is GONE (owner delete path works)'
);

-- =====================================================================
-- LEG (f) PARTIAL-UNIQUE behavior (cross-tenant partition + global-symbol DDL fence).
-- =====================================================================
-- (f1) cross-tenant partition: B may own a per-user 'House' even though A owns one (different users_id
--      partition -> asset_user_name_uniq(users_id, name) does NOT collide). Run under authenticated B.
select _rls.set_tenant(:'tb'::uuid);
select lives_ok(
  $$ insert into pfin.asset (asset_type, pricing_source, name)
       values ('real_estate', 'manual_valuation', 'House') $$,
  '(f1) partial-unique partitions by tenant: B owns a per-user ''House'' while A already owns one -> NO collision (asset_user_name_uniq keys on (users_id, name); the two partitions are independent)'
);
select set_config('role', 'postgres', true);

-- (f3) global-symbol partial-unique (seed/DDL-scoped — users CANNOT insert globals, proven by (c1),
--      so exercised on the PRIVILEGED seed path): a duplicate GLOBAL symbol 'USD' -> asset_global_symbol_uniq.
select throws_ok(
  $$ insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
       values (null, 'currency', 'fx_feed', 'USD', 'Duplicate USD') $$,
  '23505', null,
  '(f3) global-symbol partial-unique (seed/DDL-scoped): a privileged INSERT of a duplicate GLOBAL symbol ''USD'' (users_id NULL) -> asset_global_symbol_uniq unique_violation (23505) — the global dedup index has teeth on the seed path'
);

-- =====================================================================
-- LEG (g) GRANT posture (ACL facts, run as postgres — role-agnostic).
--   authenticated CRUD active; anon + service_role zero-reach (016 GRANT rationale).
-- =====================================================================
-- (g1) non-vacuous ACL positive: authenticated HOLDS INSERT (active V1 write path, not SELECT-only).
select ok(
  has_table_privilege('authenticated', 'pfin.asset', 'INSERT'),
  '(g1) ACL positive: authenticated HOLDS INSERT on pfin.asset (the active V1 per-user write path — SELF-201; grant not vacuously absent, contrast 009 SELECT-only dormancy)'
);
-- (g2) anon zero-grant by construction.
select ok(
  not has_table_privilege('anon', 'pfin.asset', 'SELECT'),
  '(g2) anon zero-grant: anon holds NO SELECT on pfin.asset (internet-facing anon fenced at the schema-usage layer + no table grant — by construction)'
);
-- (g3) service_role ungranted in 016 (the global-enrichment write path is DEFERRED + C6-gated).
select ok(
  not has_table_privilege('service_role', 'pfin.asset', 'SELECT'),
  '(g3) service_role ungranted in 016: service_role holds NO SELECT on pfin.asset (the global registry-enrichment write path is a later worker-build surface — deferred, C6-gated + Sec joint-review then)'
);

select * from finish();
rollback;

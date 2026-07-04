-- =====================================================================
-- Per-Wave battery — pfin.tax_character GLOBAL shared-read reference table
--   + user_taxonomy.tax_character CHECK→FK conversion
--   (SELF-231 / ADR-024 Option C / migration 011 — C6 EXPOSURE-GATING per
--    ADR-023; V1-SHIP-BLOCK)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/011_tax_character_registry.sql
--   - pfin.tax_character                 (NEW global reference table: code text PK,
--                                         label, notes, display_order, timestamps;
--                                         5 committed seed rows)
--   - policy tax_character_select        (FOR SELECT TO authenticated USING (true) —
--                                         GLOBAL shared-read; NOT users_id-scoped)
--   - grant select on pfin.tax_character to authenticated   (ACL-before-RLS; SELECT only)
--   - NO write policy / NO write grant   (bootstrap-seeded canonical data; V2 adds
--                                         values as a CODE event, never a user write)
--   - anon: ZERO grant                   (pfin schema-usage denial — ADR-023 C2)
--   - pfin.user_taxonomy.tax_character   (CHANGED: 009 inline CHECK dropped; now text FK
--                                         REFERENCES pfin.tax_character(code) ON DELETE
--                                         RESTRICT; nullable stays valid)
--
-- ┌─ WHY A NEW SIBLING BATTERY (not an extension of 009) ────────────────────────────────┐
-- │ pfin.tax_character has a FUNDAMENTALLY DIFFERENT tenancy posture from user_taxonomy:   │
-- │ it is GLOBAL shared-read (every tenant reads the SAME 5 rows via USING (true)) — the   │
-- │ OPPOSITE of the 009 per-user isolation assertion (users_id = auth.uid()). Overloading  │
-- │ 009 would conflate two contradictory golden properties in one file. This sibling       │
-- │ battery asserts the shared-read/FK-integrity posture; 009 keeps asserting isolation.   │
-- │ Both reuse the SAME shared two-tenant fixture (../_fixtures/rls_verbs.psql via \ir) —  │
-- │ no duplicate auth.users seeding idiom, per DESIGN.md Option C.                          │
-- └──────────────────────────────────────────────────────────────────────────────────────┘
--
-- Reuses the 009 idiom: \ir shared verbs, ALL-LOWERCASE \gset literals (005 case-fold
--   lesson), MESSAGE-precise throws_like + SQLSTATE-precise throws_ok (004 all-42501
--   false-green lesson — the grant-layer denial is pinned to the exact table message, NOT
--   a bare 42501), role restored to postgres between blocks (PR #121 _rls-usage discipline).
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (a1)/(a2) -> GLOBAL shared-read golden property: BOTH tenants see all 5 rows. RED if the
--               policy were users_id-scoped instead of USING (true), or if a tenant saw <5
--               (a filtered / over-restrictive policy). This is the exact INVERSE of 009's
--               isolation assertion — the defining property of a global reference table.
--   (b1)/(b2)/(b3) -> GRANT-layer write denial: authenticated INSERT/UPDATE/DELETE fail closed
--               with the SPECIFIC 'permission denied for table tax_character' (42501), NOT a
--               bare 42501 and NOT a WITH-CHECK RLS message. RED if a write GRANT were opened
--               (the write would commit, or the message would change). Guards the SELECT-only
--               grant against an accidental widening to a write grant.
--   (b4)     -> RLS-layer write denial: ZERO non-SELECT (write / ALL) policies exist on the
--               table. RED if an INSERT/UPDATE/DELETE/ALL policy were added — the second,
--               independent write fence (defence-in-depth: grant-layer AND rls-layer).
--   (c1)     -> FK integrity: a user_taxonomy row with a BOGUS tax_character code fails closed
--               (23503 foreign_key_violation). RED if the FK were dropped (the 009 CHECK is
--               gone, so with no FK a bogus code would INSERT freely).
--   (c2)/(c3)-> FK non-vacuous positives: a VALID code ('ordinary') AND a NULL both succeed.
--               RED if the FK targeted the wrong column/were over-strict (c2), or if the
--               column were made NOT NULL / the nullable contract broke (c3).
--   (d1)/(d2)-> user_taxonomy isolation UNAFFECTED by the FK add: owner A still reads its own
--               row (d1, non-vacuous) and tenant B still reads 0 of A's user_taxonomy rows
--               (d2). RED if the CHECK→FK conversion had weakened the users_id = auth.uid()
--               isolation. Non-vacuous: with RLS off/widened, d2 returns 1 (A's row).
--   (e1)     -> ADR-023 C2 outer fence: anon holds NO SELECT on tax_character. RED if anon
--               gained SELECT — CRITICAL for a USING (true) table (a global read policy means
--               that IF anon ever held a grant, anon would read ALL 5 rows). Guards the new
--               table's anon zero-grant against the shared-read posture's blast radius.
--
-- §10 / DECISION 3: ledger UNCHANGED at 2 (RT-22 + RT-26); Decision-3 family UNCHANGED at 7
--   (per the 011 header: tax_character carries NO tenant anchor — global reference data — so
--   its FK is a Decision-3 CLEARED, not a matched-tenant instance; the pending SELF-201
--   sub_cat_id -> user_taxonomy FK is the SEPARATE matched-tenant-MANDATORY instance, evaluated
--   at THAT migration). Per the 011 header §10 3-axis + Decision-3 eval.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b();
--   NO PII / NO real financial data / NO prod data. tax_character's 5 rows are the migration's
--   COMMITTED non-personal canonical seed (present after db reset — NOT re-seeded here). The
--   user_taxonomy rows are seeded PRIVILEGED (role=postgres) because there is NO authenticated
--   write path (V1-write-dormant); auth.uid() is NULL under postgres, so users_id is explicit.
--   All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so NO
--   `_rls.*` call runs while switched to authenticated. Tenant UUIDs are resolved to psql
--   LITERALS via \gset at role=postgres; every _rls.set_tenant is called at role=postgres and
--   each block restores role=postgres before the next. \gset var names are ALL-LOWERCASE.
--
-- ⟦WIRE-VALIDATE⟧ authored against 011's working-tree contract; the authoritative run is against
--   the 001→011 reset stack. Roles `authenticated` / `anon` name-checked in (b*)/(e1). RED-until-
--   011-applied is expected on any pre-011 stack (the table / FK would not exist).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(12);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed; the only write path, since
-- user_taxonomy is V1-write-dormant). A owns ONE taxonomy row; B owns ONE. tax_character's
-- 5 rows are ALREADY present from migration 011's committed seed (not re-seeded here).
-- users_id is set explicitly (auth.uid() is NULL under postgres).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat, tax_relevant, tax_character)
  values (:'ta', 'asset', 'Brokerage', 'US Equity', true, 'qualified_dividend')
  returning id as a_row \gset
insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat)
  values (:'tb', 'asset', 'Brokerage', 'US Equity');

-- =====================================================================
-- BLOCK A — GLOBAL shared-read (the golden property; INVERSE of 009 isolation).
--   Both distinct tenants read all 5 seeded rows — NOT users_id-filtered.
-- =====================================================================
-- (a1) tenant A sees all 5 rows.
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*) from pfin.tax_character)::bigint, 5::bigint,
  '(a1) global shared-read: tenant A sees all 5 tax_character rows (USING (true) — not users_id-scoped)'
);
select set_config('role', 'postgres', true);

-- (a2) tenant B sees all 5 rows — the SAME shared rows (golden shared-read; INVERSE of 009).
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from pfin.tax_character)::bigint, 5::bigint,
  '(a2) global shared-read: tenant B ALSO sees all 5 tax_character rows (shared, not isolated — the defining property of a global reference table)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK B — write fails closed at BOTH layers (grant-layer + rls-layer).
--   No write grant + no write policy. Run under authenticated A: even a legit tenant
--   cannot write canonical reference data in V1 (values change as a CODE event).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (b1) authenticated INSERT fails closed at the GRANT layer (no INSERT grant; no write policy).
select throws_like(
  $$ insert into pfin.tax_character (code, label) values ('bogus_new', 'Bogus') $$,
  'permission denied for table tax_character',
  '(b1) write fails closed: authenticated INSERT denied at the GRANT layer (permission denied — SELECT-only grant, no write policy; distinct from a WITH-CHECK RLS rejection)'
);
-- (b2) authenticated UPDATE fails closed at the GRANT layer (targets an existing seed row).
select throws_like(
  $$ update pfin.tax_character set label = 'Changed' where code = 'ordinary' $$,
  'permission denied for table tax_character',
  '(b2) write fails closed: authenticated UPDATE denied at the GRANT layer (no UPDATE grant — guards the SELECT-only grant against widening)'
);
-- (b3) authenticated DELETE fails closed at the GRANT layer.
select throws_like(
  $$ delete from pfin.tax_character where code = 'ordinary' $$,
  'permission denied for table tax_character',
  '(b3) write fails closed: authenticated DELETE denied at the GRANT layer (no DELETE grant)'
);
select set_config('role', 'postgres', true);

-- (b4) RLS-layer write denial: ZERO non-SELECT (write / ALL) policies on the table. The second,
--      independent write fence — RED if an INSERT/UPDATE/DELETE/ALL policy were added. (Catalog
--      query; role-independent — run privileged.)
select is(
  (select count(*) from pg_policies
     where schemaname = 'pfin' and tablename = 'tax_character' and cmd <> 'SELECT')::bigint,
  0::bigint,
  '(b4) write fails closed: ZERO non-SELECT (write/ALL) policies exist on tax_character (RLS-layer write denial — defence-in-depth alongside the grant-layer fence)'
);

-- =====================================================================
-- BLOCK D — user_taxonomy isolation UNAFFECTED by the CHECK→FK conversion.
--   Asserted BEFORE the FK-integrity block so the extra live inserts (c2/c3) do not
--   perturb A's row count.
-- =====================================================================
-- (d1) POSITIVE (non-vacuous): owner A reads exactly its 1 own user_taxonomy row.
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*) from pfin.user_taxonomy where users_id = :'ta')::bigint, 1::bigint,
  '(d1) user_taxonomy isolation intact: owner A reads exactly its 1 own row (users_id = auth.uid() unweakened by the FK add)'
);
select set_config('role', 'postgres', true);

-- (d2) cross-tenant read STILL fails closed: B sees ZERO of A's user_taxonomy rows.
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from pfin.user_taxonomy where users_id = :'ta')::bigint, 0::bigint,
  '(d2) user_taxonomy isolation intact: B sees 0 of A''s rows (the CHECK→FK conversion did NOT widen the direct-owner isolation)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK C — FK integrity (privileged inserts; the FK replaces the 009 inline CHECK).
--   Runs AFTER block D so the live positive inserts don't affect A's isolation count.
-- =====================================================================
-- (c1) BOGUS tax_character code fails closed with foreign_key_violation (23503).
select throws_ok(
  format($$ insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat, tax_character)
              values (%L, 'asset', 'Brokerage', 'FK Bogus', 'not_a_real_code') $$, :'ta'),
  '23503', null,
  '(c1) FK integrity: a bogus tax_character code raises foreign_key_violation (23503) — fails closed (RED if the FK were dropped: with no CHECK either, a bad value would insert)'
);
-- (c2) VALID code ('ordinary') succeeds — non-vacuous positive (guards an over-strict/wrong-target FK).
select lives_ok(
  format($$ insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat, tax_character)
              values (%L, 'asset', 'Brokerage', 'FK Valid', 'ordinary') $$, :'ta'),
  '(c2) FK integrity: a valid tax_character code (''ordinary'') INSERTs successfully (FK targets tax_character(code) correctly; not over-strict)'
);
-- (c3) NULL tax_character succeeds — the nullable contract is preserved (asset-domain dormant-NULL).
select lives_ok(
  format($$ insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat, tax_character)
              values (%L, 'asset', 'Brokerage', 'FK Null', null) $$, :'ta'),
  '(c3) FK integrity: a NULL tax_character INSERTs successfully (nullable contract preserved; asset-domain dormant-NULL)'
);

-- =====================================================================
-- BLOCK E — ADR-023 C2 internet-facing anon outer fence (critical for USING (true)).
-- =====================================================================
-- (e1) anon holds NO SELECT on tax_character (table-ACL zero-grant). CRITICAL: a USING (true)
--      shared-read policy means anon would read ALL 5 rows IF it ever held a grant.
select ok(
  not has_table_privilege('anon', 'pfin.tax_character', 'SELECT'),
  '(e1) ADR-023 C2 outer fence: anon holds NO SELECT on pfin.tax_character (a USING (true) global-read table must NEVER be anon-reachable)'
);

select * from finish();
rollback;

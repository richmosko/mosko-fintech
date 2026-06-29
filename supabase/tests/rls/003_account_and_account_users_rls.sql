-- =====================================================================
-- Per-Wave RLS battery — pfin.account + pfin.account_users (SELF-187 / 003)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/003_account_and_account_users.sql
--   - pfin.account            (RLS: users_id = auth.uid(); SELECT/INSERT/UPDATE)
--   - pfin.account_users       (V1-DORMANT ACL; RLS SELECT-only; SELECT-only GRANT)
--   - pfin.fn_grant_creator_access()  (SECURITY DEFINER AFTER INSERT trigger;
--                                      sole writer of account_users in V1)
-- These vectors were authored line-by-line against the authored 003 SQL — not a
-- relayed guess: RLS predicates `users_id = auth.uid()`, the INSERT WITH CHECK
-- linchpin, the SELECT-only grant on account_users, and the DEFINER creator-grant
-- trigger. First live run is the W3-A ⟦WIRE-VALIDATE⟧ once the DevOps db-tests job
-- is wired; RED until 003 is applied, GREEN once applied — expected, not a failure.
--
-- WHY THIS IS NON-VACUOUS (fails-closed proof — each assertion guards a REAL edge):
--   (v)  cross-tenant read empty  -> RED if RLS on either table were dropped/widened
--                                    (B would then see A's rows; isnt-0 fires).
--   (vi) forged-users_id INSERT   -> RED if the INSERT WITH CHECK (users_id=auth.uid())
--                                    were removed (forged row would commit; no throw).
--   (iii) write-locked ACL        -> RED if any authenticated INSERT/UPDATE/DELETE grant
--                                    were opened on account_users (UPDATE/DELETE would
--                                    silently affect 0 rows instead of erroring -> no throw).
--   (i)  creator-grant fires      -> RED if the DEFINER trigger stopped firing (count 0)
--                                    or A could not read its own ACL row under RLS.
--   The inversion self-test (00_rls_inversion_self_test.sql) separately proves the
--   cross-tenant PROBE has teeth on an unprotected table; this file proves POSITIVE
--   isolation on the real RLS tables (the Phase-6 half DESIGN.md §3 forward-points to).
--
-- ((ii) DEFERRED — DO NOT FAKE.) The Lock-3 assertion "tenant B cannot reach A's
--   account_trans rows via the account_users.rd_access-JOIN read path" is only
--   testable once pfin.account_trans lands (a LATER migration). It requires the JOIN
--   target table to exist; writing it now against a non-existent table would be a
--   vacuous green. It is OWNED BY and lands in the account_trans migration's battery
--   (same PR), not here. Tracked: account_trans Wave.
--
-- AUTH/FIXTURE POSTURE (SECURITY §4.5): synthetic only — fixed-UUID tenants from
--   _rls.tenant_a()/_rls.tenant_b(); NO PII / NO real account numbers / NO prod data.
--   The two auth.users rows are seeded INLINE inside this test's rolled-back txn
--   (per-test data per DESIGN.md §1). NOTE: promoting this to a shared
--   _rls.seed_tenants() verb (DESIGN.md README forward-points to it) is a future DRY
--   step that touches the §4.5 access-control boundary -> Sec joint-review-gated;
--   deliberately NOT done unilaterally in this PR (kept to the test file only).
-- =====================================================================

begin;

-- shared cross-tenant verbs, loaded textually into this txn (Option C via \ir).
-- nested case (one dir below tests/) -> path is ../_fixtures/ per DESIGN.md note.
\ir ../_fixtures/rls_verbs.psql

select plan(10);

-- ---------------------------------------------------------------------
-- Fixture: two synthetic tenants in auth.users (test DB only; rolled back).
-- Seeded as the connecting superuser (session role = postgres) BEFORE any
-- tenant context switch. Minimal column set (id); pfin.account.users_id FKs
-- auth.users(id). Synthetic fixed UUIDs — no PII.
-- ---------------------------------------------------------------------
insert into auth.users (id) values
  (_rls.tenant_a()),
  (_rls.tenant_b());

-- Setup: tenant A creates ONE account through the real app path — users_id is
-- left to DEFAULT auth.uid() (= A), exercising the DEFAULT + WITH CHECK linchpin.
-- The AFTER INSERT DEFINER trigger fn_grant_creator_access fires and writes the
-- creator-grant row into the (authenticated-write-locked) account_users table.
select _rls.set_tenant(_rls.tenant_a());
insert into pfin.account (name, account_type, scope, tax_treatment)
  values ('A primary checking', 'depository', 'household', 'taxable');

-- =====================================================================
-- (i) Creator-grant fires under RLS, and A can SELECT its own grant row.
--     (Runs as authenticated A: the count is gated by account_users' RLS
--      SELECT policy — A seeing the row IS the read-path assertion.)
-- =====================================================================
select is(
  (select count(*)
     from pfin.account_users au
     join pfin.account a on a.account_id = au.account_id
    where au.users_id = _rls.tenant_a()
      and a.users_id  = _rls.tenant_a())::bigint,
  1::bigint,
  '(i) fn_grant_creator_access fired: exactly one creator-grant row links A''s account to A, and A can read it under RLS'
);

select is(
  (select (rd_access and wr_access)
     from pfin.account_users
    where users_id = _rls.tenant_a()),
  true,
  '(i) creator grant carries rd_access=true AND wr_access=true (full creator access)'
);

select set_config('role', 'postgres', true);  -- restore privileged context for the verbs

-- =====================================================================
-- (iv) Owner reads own (non-vacuous; guards an over-restrictive policy too).
--      A sees exactly its 1 account row and its 1 account_users row.
-- =====================================================================
select _rls.expect_owner_can_read('pfin.account'::regclass,       _rls.tenant_a(), 1::bigint);
select _rls.expect_owner_can_read('pfin.account_users'::regclass, _rls.tenant_a(), 1::bigint);

-- =====================================================================
-- (v) Cross-tenant read fails closed: B sees ZERO of A's rows on both tables
--     (RLS users_id = auth.uid()).
-- =====================================================================
select _rls.expect_cross_tenant_read_empty('pfin.account'::regclass,       _rls.tenant_a(), _rls.tenant_b());
select _rls.expect_cross_tenant_read_empty('pfin.account_users'::regclass, _rls.tenant_a(), _rls.tenant_b());

-- =====================================================================
-- (vi) LINCHPIN: an INSERT into pfin.account with a forged users_id != auth.uid()
--      fails the INSERT WITH CHECK (users_id = auth.uid()). This is the property
--      the DEFINER trigger's whole isolation argument rests on — NEW.users_id is
--      un-forgeable, so the creator-grant can only ever name the true creator.
-- =====================================================================
select _rls.set_tenant(_rls.tenant_a());  -- A is authenticated; tries to forge B's ownership
select throws_ok(
  $$ insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
       values (_rls.tenant_b(), 'forged-by-A', 'depository', 'household', 'taxable') $$,
  '42501',
  null,
  '(vi) linchpin: forged users_id (!= auth.uid()) is rejected by the account INSERT WITH CHECK'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (iii) No authenticated write path on account_users in V1-dormant.
--       authenticated holds SELECT only (no INSERT/UPDATE/DELETE grant) and the
--       DEFINER trigger is the SOLE writer. Each verb fails closed at the table
--       ACL (42501). A targets its OWN visible rows -> proving even the owner
--       cannot write the dormant ACL table directly.
-- =====================================================================
select _rls.set_tenant(_rls.tenant_a());
select throws_ok(
  $$ insert into pfin.account_users (account_id, users_id, rd_access, wr_access)
       select account_id, _rls.tenant_a(), true, true
         from pfin.account where users_id = _rls.tenant_a() $$,
  '42501',
  null,
  '(iii) authenticated INSERT on account_users fails closed (no INSERT grant; DEFINER trigger is sole writer)'
);
select throws_ok(
  $$ update pfin.account_users set rd_access = true where users_id = _rls.tenant_a() $$,
  '42501',
  null,
  '(iii) authenticated UPDATE on account_users fails closed (no UPDATE grant — V1-dormant)'
);
select throws_ok(
  $$ delete from pfin.account_users where users_id = _rls.tenant_a() $$,
  '42501',
  null,
  '(iii) authenticated DELETE on account_users fails closed (no DELETE grant — V1-dormant)'
);
select set_config('role', 'postgres', true);  -- restore before finish()

select * from finish();
rollback;

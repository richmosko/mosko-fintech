-- =====================================================================
-- Per-Wave RLS battery — pfin.account + pfin.account_users (SELF-187 / 003)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/003_account_and_account_users.sql
--   - pfin.account            (RLS: users_id = auth.uid(); SELECT/INSERT/UPDATE)
--   - pfin.account_users       (V1-DORMANT ACL; RLS SELECT-only; SELECT-only GRANT)
--   - pfin.fn_grant_creator_access()  (SECURITY DEFINER AFTER INSERT trigger;
--                                      sole writer of account_users in V1)
-- Vectors authored line-by-line against the authored 003 SQL: RLS predicates
-- `users_id = auth.uid()`, the INSERT WITH CHECK linchpin, the SELECT-only grant on
-- account_users, and the DEFINER creator-grant trigger.
--
-- ROLE/SCHEMA DISCIPLINE (root-cause fix, PR #121 first wire-validate run):
--   The `_rls` test schema grants no USAGE to `authenticated`, so NO `_rls.*` call
--   may execute while the role is switched to authenticated (it errors + aborts the
--   whole script). Therefore:
--     - the two fixed tenant UUIDs are resolved to PSQL LITERALS via \gset while
--       role=postgres (single source = the verb fns), and used as :'ta'/:'tb';
--     - dynamic (throwing) SQL interpolates the literal via format(%L, :'ta') so the
--       UUID is substituted OUTSIDE the dynamic string — no `_rls.*` inside it;
--     - every `_rls.*` verb is called ONLY at role=postgres (explicit reset before
--       each). set_config('role','postgres',true) is itself privilege-free here
--       because the test session user is the superuser `postgres` (same mechanic the
--       verbs use to restore context). We did NOT grant USAGE on `_rls` to
--       authenticated — that touches the shared fixture / SECURITY §4.5 boundary.
--
-- WHY NON-VACUOUS (fails-closed proof — each assertion guards a REAL edge):
--   (v)  cross-tenant read empty  -> RED if RLS on either table were dropped/widened.
--   (vi) forged-users_id INSERT   -> RED if the INSERT WITH CHECK were removed
--                                    (forged row commits; no RLS-violation throw).
--   (iii) write-locked ACL        -> RED if any authenticated write grant were opened
--                                    (UPDATE/DELETE would silently affect 0 rows under
--                                    RLS instead of an ACL denial -> no throw).
--   (i)  creator-grant fires      -> RED if the DEFINER trigger stopped firing, or A
--                                    could not read its own ACL row under RLS.
--   42501-PRECISION: schema-USAGE-denied, table-ACL-denied, and RLS-WITH-CHECK are
--   ALL SQLSTATE 42501. So the throwing assertions use throws_like on the MESSAGE
--   (a stronger discriminator than the code): only an RLS WITH CHECK violation emits
--   'new row violates row-level security policy%'; only a table-ACL denial emits
--   'permission denied for table account_users'. This catches the INTENDED failure,
--   not an incidental 42501. (throws_like, not throws_ok 4-arg, because exact-match
--   would couple to the policy NAME — brittle if the policy is renamed.)
--
-- ((ii) DEFERRED — DO NOT FAKE.) "tenant B cannot reach A's account_trans via the
--   account_users.rd_access-JOIN read path" is only testable once pfin.account_trans
--   lands (a LATER migration); it requires the JOIN target to exist. It is OWNED BY
--   and lands in the account_trans migration's battery (same PR), not here. A version
--   written now against a non-existent table would be a vacuous green.
--
-- AUTH/FIXTURE POSTURE (SECURITY §4.5): synthetic only — fixed-UUID tenants from
--   _rls.tenant_a()/_rls.tenant_b(); NO PII / NO real account numbers / NO prod data.
--   The two auth.users rows are seeded INLINE inside this rolled-back txn (per-test
--   data per DESIGN.md §1). RED-until-003-applied is expected (W3-A grounding).
-- =====================================================================

begin;

-- shared cross-tenant verbs, loaded textually into this txn (Option C via \ir).
-- nested case (one dir below tests/) -> path is ../_fixtures/ per DESIGN.md note.
\ir ../_fixtures/rls_verbs.psql

select plan(10);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres),
-- so NO _rls.* call ever runs under the switched-to authenticated role. Single
-- source of truth = the verb fns.
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture: two synthetic tenants in auth.users (test DB only; rolled back).
-- pfin.account.users_id FKs auth.users(id). Minimal column set (id).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

-- Setup: tenant A creates ONE account through the real app path — users_id is left
-- to DEFAULT auth.uid() (= A), exercising the DEFAULT + WITH CHECK linchpin. The
-- AFTER INSERT DEFINER trigger fn_grant_creator_access fires and writes the
-- creator-grant row into the (authenticated-write-locked) account_users table.
-- _rls.set_tenant runs here at role=postgres (ok) and flips to authenticated A.
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.account (name, account_type, scope, tax_treatment)
  values ('A primary checking', 'depository', 'household', 'taxable');

-- =====================================================================
-- (i) Creator-grant fires under RLS, and A can SELECT its own grant row.
--     Runs as authenticated A (predicates use :'ta' literals, no _rls.*):
--     A seeing the row IS the RLS-gated read-path assertion.
-- =====================================================================
select is(
  (select count(*)
     from pfin.account_users au
     join pfin.account a on a.account_id = au.account_id
    where au.users_id = :'ta' and a.users_id = :'ta')::bigint,
  1::bigint,
  '(i) fn_grant_creator_access fired: exactly one creator-grant row links A''s account to A, and A can read it under RLS'
);

select is(
  (select (rd_access and wr_access) from pfin.account_users where users_id = :'ta'),
  true,
  '(i) creator grant carries rd_access=true AND wr_access=true (full creator access)'
);

select set_config('role', 'postgres', true);  -- restore privileged context for the verbs

-- =====================================================================
-- (iv) Owner reads own (non-vacuous; guards an over-restrictive policy too).
--      A sees exactly its 1 account row and its 1 account_users row.
--      Verbs run at role=postgres and restore role=postgres internally.
-- =====================================================================
select _rls.expect_owner_can_read('pfin.account'::regclass,       :'ta'::uuid, 1::bigint);
select _rls.expect_owner_can_read('pfin.account_users'::regclass, :'ta'::uuid, 1::bigint);

-- =====================================================================
-- (v) Cross-tenant read fails closed: B sees ZERO of A's rows on both tables
--     (RLS users_id = auth.uid()).
-- =====================================================================
select _rls.expect_cross_tenant_read_empty('pfin.account'::regclass,       :'ta'::uuid, :'tb'::uuid);
select _rls.expect_cross_tenant_read_empty('pfin.account_users'::regclass, :'ta'::uuid, :'tb'::uuid);

-- =====================================================================
-- (vi) LINCHPIN: an INSERT into pfin.account with a forged users_id != auth.uid()
--      is rejected by the INSERT WITH CHECK (users_id = auth.uid()). This is the
--      un-forgeable-NEW.users_id property the DEFINER trigger's isolation rests on.
--      Message-matched to the RLS-policy violation (not an incidental 42501);
--      the forged UUID is interpolated via format(%L) OUTSIDE the dynamic SQL.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);  -- A is authenticated; tries to forge B's ownership
select throws_like(
  format($$ insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
              values (%L, 'forged-by-A', 'depository', 'household', 'taxable') $$, :'tb'),
  'new row violates row-level security policy%for table "account"',
  '(vi) linchpin: forged users_id (!= auth.uid()) rejected by the account INSERT WITH CHECK (RLS-policy violation, not an incidental 42501)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (iii) No authenticated write path on account_users in V1-dormant.
--       authenticated holds SELECT only; the DEFINER trigger is the SOLE writer.
--       Each verb fails closed at the TABLE ACL — message-matched to
--       'permission denied for table account_users' (the intended denial, not an
--       incidental 42501). INSERT targets A's own users_id (format %L); UPDATE/DELETE
--       need no row to prove ACL denial (raised before any row is touched).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ insert into pfin.account_users (account_id, users_id, rd_access, wr_access)
              values (1, %L, true, true) $$, :'ta'),
  'permission denied for table account_users',
  '(iii) authenticated INSERT on account_users fails closed at the table ACL (no INSERT grant; DEFINER trigger is sole writer)'
);
select throws_like(
  $$ update pfin.account_users set rd_access = true $$,
  'permission denied for table account_users',
  '(iii) authenticated UPDATE on account_users fails closed at the table ACL (no UPDATE grant — V1-dormant)'
);
select throws_like(
  $$ delete from pfin.account_users $$,
  'permission denied for table account_users',
  '(iii) authenticated DELETE on account_users fails closed at the table ACL (no DELETE grant — V1-dormant)'
);
select set_config('role', 'postgres', true);  -- restore before finish()

select * from finish();
rollback;

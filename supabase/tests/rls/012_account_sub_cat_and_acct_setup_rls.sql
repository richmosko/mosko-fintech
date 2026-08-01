-- =====================================================================
-- Per-Wave battery — account_trans AcctSetup transaction_type discriminator
--   (SELF-201 / 012 — C6 EXPOSURE-GATING per ADR-023; V1-SHIP-BLOCK)
-- =====================================================================
-- RECONCILED AT 048 (SELF-319) — the account-level Sub-Cat half of 012 is DROPPED.
--   Migration 048 physically removes pfin.account.sub_cat_id, the trigger
--   account_matched_sub_cat, and the function fn_account_matched_sub_cat() — the
--   Decision-3 CANONICAL instance #5 matched-tenant fence (built-then-removed: the
--   THIRD status class, DROPPED, per ADR-011 D3 "Enumeration DROP resolution
--   (SELF-319 / 048)"). Those objects no longer exist, so this battery can no longer
--   exercise them. The former sub_cat_id coverage — old assertions (1a)/(1b)/(1c)
--   (matched-tenant PASS: owner-tags-own INSERT + owner-read + SELF-236 UPDATE),
--   (2a)/(2b)/(2c) (LOAD-BEARING cross-tenant INSERT/UPDATE fail-closed + non-vacuous
--   B-owns control), (3) (NULL-tag WHEN-skip), and (6) (ON DELETE RESTRICT) — is
--   REMOVED here. It is REPLACED by supabase/tests/rls/048_drop_account_sub_cat.sql,
--   which proves the drop actually happened (the fence's absence is now the invariant).
--
--   WHAT THIS FILE STILL COVERS (unchanged surface — 048 DELIBERATELY does NOT touch
--   it, per the 048 de-conflation guard): the AcctSetup transaction_type discriminator
--   on the immutable pfin.account_trans ledger. That is the OTHER half of migration 012
--   and is fully LIVE (the recreated fn_create_manual_account still writes
--   transaction_type='acct_setup'). Its assertions stay.
--
--   ASSERTION-LABEL REMAP (old 012 → reconciled 012): the surviving discriminator
--   assertions are renumbered (1)/(2)/(3)/(4) for a clean standalone file:
--     old (4a) 'acct_setup' admitted            -> (1)
--     old (4b) CHECK fails closed (23514)        -> (2)
--     old (4c) DEFAULT lands 'standard'          -> (3)
--     old (5)  cross-tier immutability           -> (4)
--   plan(12) -> plan(4).  (Eight sub_cat assertions removed; four discriminator kept.)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/012_account_sub_cat_and_acct_setup.sql
--   (post-048: only the transaction_type discriminator half survives)
--   - pfin.account_trans.transaction_type text NOT NULL DEFAULT 'standard'
--       CHECK IN ('standard','acct_setup')  (AcctSetup discriminator; permanent per-row
--       on the immutable 004 ledger; ADR-025 one-way door).
-- Prereqs exercised (already on main): 003 (account RLS/GRANT + fn_grant_creator_access
--   creator-grant trigger — seeds account_users wr_access on the app-path account
--   INSERT), 004 (account_trans immutability triggers), 006 (account_trans authenticated
--   SELECT+INSERT grant + rd/wr-JOIN policies). 048 (drops account.sub_cat_id + its
--   fence — this file no longer references either).
-- Reuses the SELF-187/189/190/196/231 idiom: \ir verbs, ALL-LOWERCASE \gset literals (005
--   case-fold lesson), SQLSTATE-precise throws_ok + message-precise throws_like (004 all-42501
--   false-green lesson), role restored to postgres between blocks (PR #121 _rls-USAGE root-cause).
--
-- ┌─ DISCRIMINATOR IMMUTABILITY LAYERING (assertion (4) — WHY service_role, not auth) ┐
-- │ 006 grants authenticated SELECT+INSERT only on account_trans (NO update grant). So   │
-- │ an authenticated UPDATE of transaction_type fails at the TABLE ACL ('permission      │
-- │ denied…') — the 004 immutability TRIGGER is never reached; asserting the trigger     │
-- │ message under authenticated would be a false-RED (the 004 (a)/(c-auth) layering).    │
-- │ The HONEST assertion that the discriminator is PERMANENT is cross-tier: service_role │
-- │ bypasses RLS and (test-granted) holds the table privilege, so the ONLY remaining     │
-- │ gate is the 004 trigger, which RAISES. That is the one-way-door property ADR-025     │
-- │ leans on. (Same grant-then-trigger idiom the 004 battery uses.)                      │
-- └─────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (1)  -> non-vacuous positive: 'acct_setup' admitted by the CHECK. RED if the CHECK
--          excluded a valid class.
--   (2)  -> RED if the transaction_type CHECK were dropped/widened (a bad value commits).
--   (3)  -> non-vacuous positive: the omitted transaction_type lands 'standard'. RED if
--          the DEFAULT changed or NOT NULL DEFAULT were dropped.
--   (4)  -> RED if the 004 immutability trigger were removed -> the discriminator would be
--          editable post-INSERT (one-way-door / permanence broken).
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22 + RT-26 + RT-27; this file touches no
--   catalogued instance — authenticated/service_role-tier CHECK + immutability-trigger work,
--   no infra-credential or service_role-KEY surface). Decision-3 family: instance #5
--   (account.sub_cat_id) is DROPPED at 048 — its fence no longer exists, so this battery no
--   longer asserts it; 048_drop_account_sub_cat.sql proves the drop instead.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenant from _rls.tenant_a();
--   NO PII / NO real account numbers / NO prod data. One tenant suffices: the discriminator
--   is a per-row CHECK + a cross-tier immutability trigger, neither cross-tenant. All in a
--   rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so NO
--   `_rls.*` call runs under authenticated. The tenant UUID is resolved to a psql LITERAL via
--   \gset at role=postgres; every _rls.set_tenant is called at role=postgres and each block
--   restores role=postgres before the next. \gset var names are ALL-LOWERCASE.
--
-- ⟦WIRE-VALIDATE⟧ authored against 012+048's firmed contract; the authoritative run is against
--   the 001->048 reset stack. Roles `authenticated` / `service_role` name-checked in the blocks.
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(4);

-- Resolve the fixed tenant UUID to a psql literal while privileged (role=postgres).
select _rls.tenant_a() as ta \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session). One tenant in auth.users.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta');

-- =====================================================================
-- BLOCK 1 (authenticated A) — AcctSetup discriminator on account_trans. A creates an
--   account via the APP PATH (users_id DEFAULT auth.uid() = A); the 003 DEFINER
--   creator-grant trigger seeds account_users(rd,wr=true) in THIS same transaction, so
--   A holds wr_access and its account_trans INSERTs satisfy the 006 wr_access-JOIN WITH
--   CHECK — the transaction_type CHECK is then the SOLE gate.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- app-path account (no sub_cat_id — the column is gone at 048), captured for the trans rows.
insert into pfin.account (name, account_type, scope, tax_treatment)
  values ('A acct', 'depository', 'household', 'taxable')
  returning account_id as acct_a \gset

-- (1) discriminator positive: transaction_type = 'acct_setup' INSERT admitted (SELF-201
--     bootstrap opening-balance row).
select lives_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type)
              values (%s, '2026-03-01', 500, 'setup', 'opening balance', 'acct_setup') $$, :acct_a),
  '(1) discriminator: transaction_type = ''acct_setup'' INSERT ADMITTED by the CHECK (SELF-201 bootstrap opening-balance row)'
);

-- (2) discriminator CHECK fails closed: a value outside ('standard','acct_setup') raises 23514.
--     The row is otherwise valid (A''s own wr_access account), so the CHECK is the SOLE gate.
select throws_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type)
              values (%s, '2026-03-02', 10, 'x', 'bad type', 'bogus_type') $$, :acct_a),
  '23514', null,
  '(2) discriminator CHECK: a transaction_type outside (standard,acct_setup) raises check_violation (23514) — fails closed on a bad value'
);

-- fixture: an INSERT omitting transaction_type, captured to assert the DEFAULT + immutability (4).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:acct_a, '2026-03-03', 20, 'y', 'defaulted')
  returning trans_id as t_def \gset

-- (3) discriminator DEFAULT: the omitted transaction_type lands 'standard' (guards NOT NULL
--     DEFAULT 'standard'). A reads its own row under RLS (rd_access).
select is(
  (select transaction_type from pfin.account_trans where trans_id = :t_def),
  'standard',
  '(3) discriminator DEFAULT: an INSERT omitting transaction_type lands ''standard'' (guards the NOT NULL DEFAULT ''standard'')'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 2 (service_role) — discriminator IMMUTABILITY (cross-tier). Hold the account_trans
--   ACL open to service_role (test setup, rolled back) so the 004 immutability TRIGGER — not
--   a missing grant — is the sole gate (the grant-then-trigger idiom from the 004 battery).
-- =====================================================================
grant usage on schema pfin to service_role;
grant select, update on pfin.account_trans to service_role;

select set_config('role', 'service_role', true);  -- superuser session can SET ROLE
-- (4) discriminator permanence: even a privileged RLS-bypassing UPDATE of transaction_type is
--     blocked by the 004 immutability trigger -> the discriminator is PERMANENT per-row (the
--     ADR-025 one-way-door property; RLS-bypass does NOT bypass the trigger).
select throws_like(
  format($$ update pfin.account_trans set transaction_type = 'standard' where trans_id = %s $$, :t_def),
  'pfin.account_trans is immutable%UPDATE blocked%',
  '(4) discriminator IMMUTABILITY (cross-tier): a service_role UPDATE of transaction_type is blocked by the 004 immutability TRIGGER (RLS-bypass does not bypass the trigger) — the discriminator is PERMANENT per-row (ADR-025 one-way door)'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;

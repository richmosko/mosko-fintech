-- =====================================================================
-- Per-Wave battery — pfin.account.sub_cat_id matched-tenant fence + account_trans
--   AcctSetup discriminator (SELF-201 / 012 — C6 EXPOSURE-GATING per ADR-023; V1-SHIP-BLOCK)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/012_account_sub_cat_and_acct_setup.sql
--   - pfin.account.sub_cat_id bigint NULL -> pfin.user_taxonomy(id) ON DELETE RESTRICT
--       (Decision-3 CANONICAL instance #5; ADR-025 — BOTH sides per-user, so a bare PG FK
--        would let a user tag their account with ANOTHER tenant's Sub-Cat).
--   - pfin.fn_account_matched_sub_cat()  (SECURITY INVOKER; BEFORE INSERT OR UPDATE ON
--       pfin.account WHEN (new.sub_cat_id IS NOT NULL); NULL-safe fail-closed NOT EXISTS ->
--       raise 'cross-tenant Sub-Cat rejected%'; the read composes with RLS on user_taxonomy).
--   - pfin.account_trans.transaction_type text NOT NULL DEFAULT 'standard'
--       CHECK IN ('standard','acct_setup')  (AcctSetup discriminator; permanent per-row on the
--       immutable 004 ledger; ADR-025 one-way door).
-- Prereqs exercised (already on main): 003 (account RLS/GRANT + fn_grant_creator_access),
--   004 (account_trans immutability triggers), 006 (account_trans authenticated SELECT+INSERT
--   grant + rd/wr-JOIN policies), 009 (user_taxonomy — the FK target; V1-write-dormant SELECT-only).
-- Reuses the SELF-187/189/190/196/231 idiom: \ir verbs, ALL-LOWERCASE \gset literals (005
--   case-fold lesson), SQLSTATE-precise throws_ok + message-precise throws_like (004 all-42501
--   false-green lesson), role restored to postgres between blocks (PR #121 _rls-USAGE root-cause).
--
-- ┌─ WHY THE CROSS-TENANT ASSERTION HAS TEETH (the load-bearing (2a)/(2b) point) ─────┐
-- │ fn_account_matched_sub_cat is SECURITY INVOKER. Under authenticated B tagging its   │
-- │ OWN account (users_id = B via the 003 WITH CHECK) with A's sub_cat_id, the trigger  │
-- │ reads: EXISTS user_taxonomy WHERE id = <A's sub_cat> AND users_id = B. TWO          │
-- │ independent reasons this is empty: (i) A's taxonomy row is users_id = A (the         │
-- │ matched-tenant predicate excludes it); (ii) user_taxonomy RLS scopes the INVOKER     │
-- │ read to auth.uid() = B, so A's row is RLS-INVISIBLE anyway. NOT EXISTS -> RAISE. We  │
-- │ assert the RAISE MESSAGE ('cross-tenant Sub-Cat rejected%') — NOT a bare 42501, NOT  │
-- │ a 23503 FK violation, NOT a silent pass — so this fence can never pass for another.  │
-- │ (2c) is the non-vacuous control: B tagging its OWN sub_cat SUCCEEDS, proving the     │
-- │ raise is MISMATCH-driven, not a blanket authenticated-B block.                       │
-- └─────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ DISCRIMINATOR IMMUTABILITY LAYERING (assertion (5) — WHY service_role, not auth) ─┐
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
--   (1a)/(1c)  -> non-vacuous positives: owner-tags-OWN INSERT + SELF-236 UPDATE reassignment
--                to another OWN sub_cat SUCCEED. RED if the trigger over-broadly blocked matched
--                tenants (a fence that rejects everything is useless).
--   (1b)       -> RED if the tag were not actually persisted/readable (owner-reads-own under RLS).
--   (2a)       -> LOAD-BEARING: RED if fn_account_matched_sub_cat (or its trigger) were removed,
--                or the users_id predicate dropped -> B's cross-tenant INSERT tag would COMMIT.
--   (2b)       -> RED if the trigger did not cover UPDATE (BEFORE INSERT OR UPDATE) -> a
--                reassignment could pivot to another tenant's Sub-Cat (SELF-236 path).
--   (2c)       -> non-vacuous control: RED if the trigger blanket-blocked authenticated B (would
--                prove (2a)/(2b) vacuous). Confirms the raise is CROSS-TENANT-mismatch-driven.
--   (3)        -> RED if the WHEN(new.sub_cat_id IS NOT NULL) clause were dropped and a NULL tag
--                started raising (untagged/Unsorted-pending must remain insertable).
--   (4a)/(4c)  -> non-vacuous positives: 'acct_setup' admitted by the CHECK; DEFAULT lands
--                'standard'. RED if the CHECK excluded a valid class or the DEFAULT changed.
--   (4b)       -> RED if the transaction_type CHECK were dropped/widened (a bad value commits).
--   (5)        -> RED if the 004 immutability trigger were removed -> the discriminator would be
--                editable post-INSERT (one-way-door / permanence broken).
--   (6)        -> RED if ON DELETE RESTRICT were relaxed to NO ACTION-without-teeth/CASCADE/SET
--                NULL -> a referenced user_taxonomy row could be deleted out from under an account.
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 2 (RT-22 + RT-26; 012 touches no catalogued
--   instance — authenticated-tier RLS/FK/column work, no infra-credential or service_role-key
--   surface). Decision-3 family: 012 lands CANONICAL instance #5 (account.sub_cat_id ->
--   user_taxonomy) — this battery is the pgTAP proof that its matched-tenant fence catches a REAL
--   cross-tenant violation (per the 012 header enumeration 4 -> 5 + ADR-025; Sec joint-review).
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b();
--   NO PII / NO real account numbers / NO prod data. BOTH tenants are populated with their OWN
--   user_taxonomy rows (A: 2 asset Sub-Cats; B: 1 asset Sub-Cat) so the matched-tenant PASS and
--   the cross-tenant FAIL both have real referents (non-vacuous per the brief). user_taxonomy is
--   V1-write-dormant, so those rows are seeded PRIVILEGED (role=postgres). All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so NO
--   `_rls.*` call runs under authenticated. Tenant UUIDs + row ids are resolved to psql LITERALS
--   via \gset at role=postgres; every _rls.set_tenant is called at role=postgres and each block
--   restores role=postgres before the next. \gset var names are ALL-LOWERCASE.
--
-- ⟦WIRE-VALIDATE⟧ authored against 012's firmed contract; the authoritative run is against the
--   001->012 reset stack. Roles `authenticated` / `service_role` name-checked in the blocks.
--   RED-until-012-applied is expected on any pre-012 stack (sub_cat_id / transaction_type absent).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(12);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session). Two tenants in auth.users, each with their OWN
-- user_taxonomy rows (V1-write-dormant -> the only write path is privileged; users_id set
-- explicitly since auth.uid() is NULL under postgres). A owns TWO asset Sub-Cats; B owns ONE.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat)
  values (:'ta', 'asset', 'Brokerage', 'US Equity')
  returning id as a_sub1 \gset
insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat)
  values (:'ta', 'asset', 'Real Estate', 'Primary Home')
  returning id as a_sub2 \gset
insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat)
  values (:'tb', 'asset', 'Brokerage', 'US Equity')
  returning id as b_sub1 \gset

-- =====================================================================
-- BLOCK 1 (authenticated A) — matched-tenant PASS: owner tags OWN account (INSERT + UPDATE)
--   + owner-reads-own + NULL-tag allowed. Accounts are created via the APP PATH (users_id
--   DEFAULT auth.uid() = A); the 003 DEFINER creator-grant trigger fires harmlessly on each.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (1a) matched-tenant INSERT positive: A tags a fresh account with its OWN sub_cat -> accepted.
select lives_ok(
  format($$ insert into pfin.account (name, account_type, scope, tax_treatment, sub_cat_id)
              values ('A tagged acct 1', 'depository', 'household', 'taxable', %s) $$, :a_sub1),
  '(1a) matched-tenant INSERT: A tags its OWN account with its OWN sub_cat_id -> fn_account_matched_sub_cat ACCEPTS (owner-tags-own INSERT path, non-vacuous positive)'
);

-- fixture: a second tagged account, captured for the UPDATE (1c) + owner-read (1b) + RESTRICT (6).
insert into pfin.account (name, account_type, scope, tax_treatment, sub_cat_id)
  values ('A tagged acct 2', 'depository', 'household', 'taxable', :a_sub1)
  returning account_id as acct_a \gset

-- (1b) owner-reads-own: A reads its own account carrying its own sub_cat_id under RLS.
select is(
  (select sub_cat_id from pfin.account where account_id = :acct_a),
  :a_sub1::bigint,
  '(1b) owner-reads-own: A reads its own account carrying its own sub_cat_id under RLS (the tag is really persisted + visible)'
);

-- (1c) matched-tenant UPDATE positive (SELF-236 reassignment): A moves the account to ANOTHER
--      of ITS OWN sub_cats -> trigger accepts (covers the BEFORE UPDATE path, not just INSERT).
select lives_ok(
  format($$ update pfin.account set sub_cat_id = %s where account_id = %s $$, :a_sub2, :acct_a),
  '(1c) matched-tenant UPDATE (SELF-236 reassignment): A reassigns its account to another of ITS OWN sub_cats -> trigger ACCEPTS (BEFORE INSERT OR UPDATE covers reassignment)'
);

-- (3) NULL sub_cat_id INSERT allowed: WHEN(new.sub_cat_id IS NOT NULL) skips the trigger.
select lives_ok(
  $$ insert into pfin.account (name, account_type, scope, tax_treatment)
       values ('A untagged acct', 'depository', 'household', 'taxable') $$,
  '(3) NULL sub_cat_id: an INSERT omitting sub_cat_id SUCCEEDS — trigger WHEN(new.sub_cat_id IS NOT NULL) skips (untagged / Unsorted-pending stays insertable)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 2 (authenticated B) — THE LOAD-BEARING cross-tenant fence + a non-vacuous positive
--   control. B owns its account (users_id = B) but attempts to tag it with A's sub_cat_id.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);

-- (2c) NON-VACUOUS CONTROL: B tags its OWN account with its OWN sub_cat -> accepted. Proves the
--      (2a)/(2b) raises are cross-tenant-MISMATCH-driven, not a blanket authenticated-B block.
select lives_ok(
  format($$ insert into pfin.account (name, account_type, scope, tax_treatment, sub_cat_id)
              values ('B tags own', 'depository', 'household', 'taxable', %s) $$, :b_sub1),
  '(2c) control: B tags its OWN account with its OWN sub_cat_id -> ACCEPTED (proves the cross-tenant raises below are mismatch-driven, not a blanket authenticated-B block)'
);

-- (2a) LOAD-BEARING cross-tenant INSERT fails closed: B tags its own account with A's sub_cat_id.
--      The BEFORE INSERT trigger reads user_taxonomy(id=A's sub_cat, users_id=B) -> NOT EXISTS
--      (A's row is users_id=A AND RLS-invisible to B) -> RAISE. Assert the RAISE (not a silent
--      pass, not a bare 42501, not a 23503 FK violation).
select throws_like(
  format($$ insert into pfin.account (name, account_type, scope, tax_treatment, sub_cat_id)
              values ('B steals A sub_cat', 'depository', 'household', 'taxable', %s) $$, :a_sub1),
  'cross-tenant Sub-Cat rejected%',
  '(2a) LOAD-BEARING cross-tenant INSERT: B tags its own account with A''s sub_cat_id -> fn_account_matched_sub_cat RAISES (NOT EXISTS matched-tenant row; the exact chain-attack Decision-3 instance #5 fences — a real violation, not a silent pass)'
);

-- fixture: B's own untagged account (NULL sub_cat -> WHEN skips -> inserts), captured for (2b).
insert into pfin.account (name, account_type, scope, tax_treatment)
  values ('B untagged acct', 'depository', 'household', 'taxable')
  returning account_id as acct_b \gset

-- (2b) cross-tenant UPDATE fails closed: B reassigns its own account to A's sub_cat -> BEFORE
--      UPDATE trigger RAISES. Confirms the fence covers reassignment (SELF-236), not just INSERT.
select throws_like(
  format($$ update pfin.account set sub_cat_id = %s where account_id = %s $$, :a_sub1, :acct_b),
  'cross-tenant Sub-Cat rejected%',
  '(2b) cross-tenant UPDATE: B reassigns its own account to A''s sub_cat_id -> trigger RAISES (matched-tenant fence covers the UPDATE/reassignment path — a reassignment cannot pivot to another tenant''s Sub-Cat)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 3 (authenticated A) — AcctSetup discriminator on account_trans. A holds wr_access on
--   acct_a via the 003 creator grant (created app-path above), so its account_trans INSERTs
--   satisfy the 006 wr_access-JOIN WITH CHECK; the transaction_type CHECK is then the sole gate.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (4a) discriminator positive: transaction_type = 'acct_setup' INSERT admitted (SELF-201
--      bootstrap opening-balance row).
select lives_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type)
              values (%s, '2026-03-01', 500, 'setup', 'opening balance', 'acct_setup') $$, :acct_a),
  '(4a) discriminator: transaction_type = ''acct_setup'' INSERT ADMITTED by the CHECK (SELF-201 bootstrap opening-balance row)'
);

-- (4b) discriminator CHECK fails closed: a value outside ('standard','acct_setup') raises 23514.
--      The row is otherwise valid (A's own wr_access account), so the CHECK is the SOLE gate.
select throws_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type)
              values (%s, '2026-03-02', 10, 'x', 'bad type', 'bogus_type') $$, :acct_a),
  '23514', null,
  '(4b) discriminator CHECK: a transaction_type outside (standard,acct_setup) raises check_violation (23514) — fails closed on a bad value'
);

-- fixture: an INSERT omitting transaction_type, captured to assert the DEFAULT + immutability (5).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:acct_a, '2026-03-03', 20, 'y', 'defaulted')
  returning trans_id as t_def \gset

-- (4c) discriminator DEFAULT: the omitted transaction_type lands 'standard' (guards NOT NULL
--      DEFAULT 'standard'). A reads its own row under RLS (rd_access).
select is(
  (select transaction_type from pfin.account_trans where trans_id = :t_def),
  'standard',
  '(4c) discriminator DEFAULT: an INSERT omitting transaction_type lands ''standard'' (guards the NOT NULL DEFAULT ''standard'')'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 4 (service_role) — discriminator IMMUTABILITY (cross-tier). Hold the account_trans ACL
--   open to service_role (test setup, rolled back) so the 004 immutability TRIGGER — not a
--   missing grant — is the sole gate (the grant-then-trigger idiom from the 004 battery).
-- =====================================================================
grant usage on schema pfin to service_role;
grant select, update on pfin.account_trans to service_role;

select set_config('role', 'service_role', true);  -- superuser session can SET ROLE
-- (5) discriminator permanence: even a privileged RLS-bypassing UPDATE of transaction_type is
--     blocked by the 004 immutability trigger -> the discriminator is PERMANENT per-row (the
--     ADR-025 one-way-door property; RLS-bypass does NOT bypass the trigger).
select throws_like(
  format($$ update pfin.account_trans set transaction_type = 'standard' where trans_id = %s $$, :t_def),
  'pfin.account_trans is immutable%UPDATE blocked%',
  '(5) discriminator IMMUTABILITY (cross-tier): a service_role UPDATE of transaction_type is blocked by the 004 immutability TRIGGER (RLS-bypass does not bypass the trigger) — the discriminator is PERMANENT per-row (ADR-025 one-way door)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 5 (postgres) — ON DELETE RESTRICT posture. a_sub1 is still referenced by 'A tagged acct
--   1' (acct_a was reassigned off it to a_sub2), so deleting it is restricted. user_taxonomy is
--   V1-write-dormant -> the only delete path is privileged; the RESTRICT is the sole gate here.
-- =====================================================================
-- (6) ON DELETE RESTRICT: deleting a user_taxonomy row still referenced by an account is
--     restricted (foreign_key_violation 23503) — fail-loud referential integrity.
select throws_ok(
  format($$ delete from pfin.user_taxonomy where id = %s $$, :a_sub1),
  '23503', null,
  '(6) ON DELETE RESTRICT: deleting a user_taxonomy row still referenced by pfin.account.sub_cat_id is RESTRICTED (foreign_key_violation 23503) — fail-loud referential integrity, no orphaned tag'
);

select * from finish();
rollback;

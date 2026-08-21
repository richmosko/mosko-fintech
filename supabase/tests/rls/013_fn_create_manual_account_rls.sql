-- =====================================================================
-- Per-Wave battery — pfin.fn_create_manual_account INVOKER write-composition RPC
--   (SELF-201 / 013 — C6 EXPOSURE-GATING per ADR-023; V1-SHIP-BLOCK)
-- =====================================================================
-- RECONCILED AT 048 (SELF-319) — the p_sub_cat_id param + the account-level Sub-Cat
--   fence it fed are DROPPED. Migration 048 changes fn_create_manual_account 7-arg ->
--   6-arg (DROP + recreate, INVOKER) and removes pfin.account.sub_cat_id +
--   fn_account_matched_sub_cat. This battery can no longer call the 7-arg overload, read
--   account.sub_cat_id, or exercise the matched-tenant fence THROUGH the RPC. Those
--   assertions are REMOVED here and REPLACED by supabase/tests/rls/048_drop_account_sub_cat.sql
--   (which proves the drop happened). The COMPOSITION properties the RPC still guarantees
--   — caller-bound ownership, same-txn creator-grant, atomicity, NaN backstop, anon-denial —
--   are unchanged and stay.
--
--   ASSERTION REMAP (old 013 -> reconciled 013): plan(12) -> plan(9).
--     KEPT  : (1a) owner-create account | (1b) acct_setup row | (1c) same-txn creator-grant
--             (2a) caller-bound ownership (B) | (4a) stmt-2 NOT NULL | (4b) atomicity orphan-
--             rollback | (7) NaN DB-backstop | (6a) anon no-EXECUTE | (6b) anon call fails closed
--     REMOVED (surface dropped at 048): (3a) cross-tenant sub_cat THROUGH the RPC |
--             (3b) atomicity on the sub_cat-fence path | (5) NULL p_sub_cat_id allowed
--     (1a)/(2a) lose their `sub_cat_id = …` predicate (the column is gone) — they now assert
--     ownership only. No p_sub_cat_id is passed to any call (all calls are 6-arg).
--
-- RECONCILED AT 087 (SELF-325) — fn_create_manual_account DROP + CREATE again,
--   this time 6-arg -> 7-arg (adds p_positions jsonb default '[]'::jsonb; the
--   6-arg overload no longer exists in pg_proc — not a second overload). Every
--   assertion in THIS file is UNCHANGED in substance — the composition
--   properties 013 proves (caller-bound ownership, same-txn creator-grant,
--   atomicity, NaN backstop, anon-denial) are unaffected by adding a
--   default-valued trailing jsonb parameter. ONLY (6a) needs a text change:
--   its has_function_privilege() call names the function by an EXACT
--   regprocedure argument-type list, which does NOT accept an omitted
--   default-bearing trailing type the way an actual RPC CALL does -- once the
--   6-arg signature is gone from the catalog, the OLD 6-type string makes the
--   cast itself raise ("function ... does not exist"), not merely fail the
--   assertion. (6b)'s positional 6-arg CALL is UNCHANGED and still resolves
--   (the 7th param's default absorbs it) -- only the CATALOG-STRING assertion
--   needed the update. The NEW p_positions properties (F1/F2/F3, the RPC's
--   own asset-creation composition, the Lock 14 adversarial-numeric matrix)
--   are proved by SELF-325's own battery, supabase/tests/rls/
--   087_manual_account_value_binding_rls.sql -- NOT added here, to keep this
--   file's original scope (the 013/SELF-201 composition properties) intact.
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/048_drop_account_sub_cat.sql (recreated 6-arg fn);
--   originally supabase/migrations/013_fn_create_manual_account.sql.
--   - pfin.fn_create_manual_account(p_name text, p_account_type text, p_scope text,
--       p_tax_treatment text, p_initial_value numeric, p_as_of_date date) RETURNS bigint —
--       SECURITY INVOKER, set search_path = '', VOLATILE. Atomic body:
--         (1) INSERT pfin.account (users_id DEFAULT auth.uid() — NOT a param)
--             RETURNING account_id
--         (2) INSERT pfin.account_trans (transaction_type='acct_setup',
--             transaction_date=p_as_of_date, amount=p_initial_value)
--         RETURN account_id
--   - REVOKE EXECUTE FROM PUBLIC (denies anon) + GRANT EXECUTE TO authenticated only.
-- Prereqs exercised (all on main): 003 (account_insert WITH CHECK users_id=auth.uid()
--   + fn_grant_creator_access DEFINER trigger + account_users), 004 (account_trans
--   immutable ledger; transaction_date/amount NOT NULL), 006 (account_trans rd/wr_access
--   -JOIN RLS + GRANT select,insert), 012 (transaction_type CHECK), 048 (7-arg -> 6-arg;
--   account.sub_cat_id + fn_account_matched_sub_cat DROPPED — no longer referenced here).
-- Reuses the SELF-187..201 idiom: \ir verbs, ALL-LOWERCASE \gset literals (005 case-fold
--   lesson), SQLSTATE-precise throws_ok + message-precise throws_like (004 all-42501
--   false-green lesson), role restored to postgres between blocks (PR #121 _rls-USAGE root).
--
-- ┌─ WHAT THIS RPC BATTERY PROVES ────────────────────────────────────────────────────┐
-- │ The RPC wraps two writes in ONE INVOKER transaction, so this battery proves the       │
-- │ COMPOSITION properties the RPC introduces:                                           │
-- │  • caller-bound ownership: users_id is NOT a param (defaults auth.uid()) — a caller    │
-- │    cannot create an account for another tenant (no forge surface exists).            │
-- │  • ATOMICITY: a statement-(2) failure rolls back statement-(1) — NO orphan account on  │
-- │    the immutable ledger (the forcing-function the RPC exists for; app-level compensation │
-- │    is structurally blocked — authenticated has no account DELETE).                    │
-- │  • anon cannot execute (EXECUTE revoked from PUBLIC, granted to authenticated only).   │
-- └─────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (1a)/(1b)  -> non-vacuous positives: the owner RPC call creates exactly one A-owned
--                account AND exactly one acct_setup opening-balance row (amount/date/type as
--                passed). RED if the RPC dropped either write, mis-set the discriminator, or
--                mis-scoped ownership.
--   (1c)       -> same-txn creator-grant: RED if the 003 AFTER-INSERT DEFINER trigger did not
--                fire in-txn before statement 2 (account_users(wr) absent -> statement 2's
--                wr_access-JOIN could not have been satisfied inside the RPC body).
--   (2a)       -> caller-bound ownership: B's RPC call yields a B-owned account. RED if users_id
--                ever became a forgeable parameter (B could create for another tenant).
--   (4a)       -> the acct_setup insert (statement 2) fails NOT NULL (23502) when p_as_of_date
--                is NULL — proves statement 2 is reached AND can fail after statement 1.
--   (4b)       -> LOAD-BEARING ATOMICITY: the statement-2 failure rolled back statement 1 —
--                NO orphan account persists. RED if the two writes were not one transaction.
--   (7)        -> NaN DB-backstop: RED if the account_trans.amount CHECK (amount <> 'NaN') were
--                absent -> a NaN initial value would persist via the API-exposed RPC (which
--                bypasses the app-layer Zod NaN reject). Fails closed at 23514 (Sec should-fix).
--   (6a)/(6b)  -> RED if EXECUTE were granted to PUBLIC/anon (internet-facing exposure of a
--                write RPC). (6a) asserts the grant absence; (6b) the actual anon call fails closed.
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22 + RT-26 + RT-27; 013 is authenticated-tier
--   INVOKER write-composition — no infra-credential (RT-22) or SUPABASE_SERVICE_ROLE_KEY
--   (RT-26) surface; the create path uses NO service_role). Decision-3 family: instance #5
--   (account.sub_cat_id) DROPPED at 048 — this battery no longer passes p_sub_cat_id through
--   to it. 013 adds NO FK-shaped column of its own.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b();
--   NO PII / NO real account numbers / NO prod data. Two tenants suffice (owner-create + a
--   distinct caller for the caller-bound-ownership proof). All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so NO
--   `_rls.*` call runs under authenticated. Tenant UUIDs are resolved to psql LITERALS via
--   \gset at role=postgres; every _rls.set_tenant is called at role=postgres and each block
--   restores role=postgres before the next. \gset var names are ALL-LOWERCASE.
--
-- ⟦WIRE-VALIDATE⟧ authored against 048's firmed contract; the authoritative run is against the
--   001->048 reset stack. Roles authenticated / anon name-checked in the blocks.
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(9);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session). Two tenants in auth.users. No user_taxonomy
-- rows are needed post-048 (the account-level sub_cat surface + its FK target are gone).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

-- =====================================================================
-- BLOCK 1 (authenticated A) — owner create positive: ONE RPC call creates account +
--   acct_setup row + RETURNS the account_id (6-arg; no sub_cat).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- Owner RPC call (the SELF-201 create path). Capture the RETURNED account_id.
select pfin.fn_create_manual_account(
  'A manual acct', 'depository', 'household', 'taxable', 1000.00, '2026-04-01'
) as rpc_acct \gset

-- (1a) the RETURN maps to exactly one A-owned account (users_id=auth.uid()=A).
select is(
  (select count(*) from pfin.account
     where account_id = :rpc_acct and users_id = :'ta')::bigint,
  1::bigint,
  '(1a) owner create: the RPC returned an account_id for exactly one A-owned account (users_id=auth.uid()=A) — account write + return value correct'
);

-- (1b) exactly one acct_setup opening-balance row with the passed amount + as-of date.
select is(
  (select count(*) from pfin.account_trans
     where account_id = :rpc_acct and transaction_type = 'acct_setup'
       and amount = 1000.00 and transaction_date = '2026-04-01')::bigint,
  1::bigint,
  '(1b) owner create: the RPC created exactly one acct_setup opening-balance account_trans row (transaction_type=''acct_setup'', amount + as-of date as passed) in the same call'
);

-- (1c) same-txn creator-grant: fn_grant_creator_access (003, AFTER-INSERT DEFINER) seeded the
--      account_users(rd,wr=true) row for the RPC-created account — evidence the 003 trigger
--      fired in the SAME transaction BEFORE statement (2), letting statement (2)'s account_trans
--      wr_access-JOIN (006) succeed inside the RPC body.
select is(
  (select (rd_access and wr_access) from pfin.account_users
     where account_id = :rpc_acct and users_id = :'ta'),
  true,
  '(1c) same-txn creator-grant: fn_grant_creator_access seeded account_users(rd=t,wr=t) for A''s RPC-created account — proving the 003 AFTER-INSERT DEFINER trigger fired in-txn BEFORE statement 2, satisfying its wr_access-JOIN'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 2 (authenticated B) — caller-bound ownership: users_id is NOT a forgeable param.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);

-- B's own RPC call (6-arg).
select pfin.fn_create_manual_account(
  'B manual acct', 'depository', 'household', 'taxable', 200, '2026-04-02'
) as rpc_acct_b \gset

-- (2a) caller-bound ownership: B's call yields a B-owned account. users_id is NOT a
--      parameter -> B cannot create for another tenant (no forge surface exists).
select is(
  (select count(*) from pfin.account
     where account_id = :rpc_acct_b and users_id = :'tb')::bigint,
  1::bigint,
  '(2a) caller-bound ownership: B''s RPC call yields a B-owned account (users_id=auth.uid()=B — NOT a forgeable param, so B cannot create an account for another tenant)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 3 (authenticated A) — ATOMICITY on a STATEMENT-2 failure. p_as_of_date=NULL passes
--   the account INSERT (statement 1) but fails the account_trans INSERT (statement 2) on the
--   004 transaction_date NOT NULL constraint (23502) — the two-writes-one-transaction proof.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (4a) statement 2 (acct_setup insert) fails NOT NULL when p_as_of_date is NULL -> proves
--      statement 2 is reached and can fail AFTER statement 1's account insert succeeded.
select throws_ok(
  $$ select pfin.fn_create_manual_account(
       'A orphan test', 'depository', 'household', 'taxable', 500, null::date) $$,
  '23502', null,
  '(4a) statement-2 failure: a NULL p_as_of_date fails the account_trans.transaction_date NOT NULL constraint (23502) — statement 2 is reached and fails after statement 1 succeeded'
);

-- (4b) LOAD-BEARING ATOMICITY: the statement-2 failure rolled back statement 1 -> NO orphan
--      account. This is the all-or-nothing property the INVOKER RPC exists to guarantee on the
--      immutable ledger (client-side compensation is structurally blocked — no account DELETE).
select is(
  (select count(*) from pfin.account where name = 'A orphan test' and users_id = :'ta')::bigint,
  0::bigint,
  '(4b) LOAD-BEARING ATOMICITY: the statement-2 failure rolled back statement 1 — NO orphan ''A orphan test'' account persists (all-or-nothing; guards against two-non-atomic-writes orphaning an account on the immutable ledger)'
);

-- (7) NaN DB-BACKSTOP: p_initial_value = 'NaN'::numeric is rejected by the account_trans.amount
--     CHECK (amount <> 'NaN') at statement 2 -> 23514. This is the DB backstop for the API-
--     exposed RPC path (/rpc), which BYPASSES the app-layer Zod NaN reject (Sec should-fix
--     flag). PG treats NaN <> NaN as FALSE, so a CHECK `amount <> 'NaN'` fails closed on NaN
--     and admits every real value.
select throws_ok(
  $$ select pfin.fn_create_manual_account(
       'A nan test', 'depository', 'household', 'taxable', 'NaN'::numeric, '2026-04-11') $$,
  '23514', null,
  '(7) NaN DB-backstop: p_initial_value = NaN is rejected by the pfin.account_trans.amount CHECK (amount <> ''NaN'') -> check_violation (23514). Fences the API-exposed RPC path that bypasses the app-layer Zod NaN reject (Sec should-fix flag)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 4 (anon + catalog) — anon cannot execute the write RPC (EXECUTE revoked from PUBLIC,
--   granted to authenticated only; internet-facing exposure fence per ADR-023).
-- =====================================================================
-- (6a) grant-layer: anon holds NO EXECUTE on the 7-arg RPC (role-independent catalog
--   assertion). RECONCILED AT 087 — the regprocedure string is a full argument-type
--   list, so the 087 DROP+CREATE (6-arg -> 7-arg) requires updating it to the type it
--   still resolves against, or this cast itself errors ("function ... does not exist").
select ok(
  not has_function_privilege(
    'anon',
    'pfin.fn_create_manual_account(text, text, text, text, numeric, date, jsonb)',
    'EXECUTE'),
  '(6a) anon holds NO EXECUTE on the 7-arg fn_create_manual_account (revoked from PUBLIC, granted to authenticated only — the write RPC is not anon-callable)'
);

-- (6b) behavior: an actual anon call fails closed at 42501 (schema-USAGE / EXECUTE denial —
--      anon has neither USAGE on schema pfin nor EXECUTE on the fn; either way, denied).
select set_config('role', 'anon', true);  -- superuser session can SET ROLE
select throws_ok(
  $$ select pfin.fn_create_manual_account(
       'anon try', 'depository', 'household', 'taxable', 1, '2026-04-09') $$,
  '42501', null,
  '(6b) anon call fails closed: an anon invocation of fn_create_manual_account is denied at 42501 (no schema-USAGE / no EXECUTE) — the write path is authenticated-tier only'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;

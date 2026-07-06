-- =====================================================================
-- Per-Wave battery — pfin.fn_create_manual_account INVOKER write-composition RPC
--   (SELF-201 / 013 — C6 EXPOSURE-GATING per ADR-023; V1-SHIP-BLOCK)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/013_fn_create_manual_account.sql
--   - pfin.fn_create_manual_account(p_name text, p_account_type text, p_scope text,
--       p_tax_treatment text, p_initial_value numeric, p_as_of_date date,
--       p_sub_cat_id bigint DEFAULT NULL) RETURNS bigint —
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
--   -JOIN RLS + GRANT select,insert), 012 (transaction_type CHECK + sub_cat_id FK +
--   fn_account_matched_sub_cat matched-tenant BEFORE-INSERT trigger).
-- Reuses the SELF-187..201 idiom: \ir verbs, ALL-LOWERCASE \gset literals (005 case-fold
--   lesson), SQLSTATE-precise throws_ok + message-precise throws_like (004 all-42501
--   false-green lesson), role restored to postgres between blocks (PR #121 _rls-USAGE root).
--
-- ┌─ WHAT THIS RPC BATTERY PROVES BEYOND THE 012 COLUMN BATTERY ──────────────────────┐
-- │ 012's battery proved the sub_cat matched-tenant fence + the discriminator CHECK on   │
-- │ direct table writes. 013 wraps two writes in ONE INVOKER transaction, so this battery │
-- │ proves the COMPOSITION properties the RPC introduces:                                │
-- │  • caller-bound ownership: users_id is NOT a param (defaults auth.uid()) — a caller    │
-- │    cannot create an account for another tenant (no forge surface exists).            │
-- │  • the 012 sub_cat fence still fires THROUGH the RPC (defense-in-depth), not bypassed. │
-- │  • ATOMICITY: a statement-(2) failure rolls back statement-(1) — NO orphan account on  │
-- │    the immutable ledger (the forcing-function the RPC exists for; app-level compensation │
-- │    is structurally blocked — authenticated has no account DELETE).                    │
-- │  • anon cannot execute (EXECUTE revoked from PUBLIC, granted to authenticated only).   │
-- └─────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (1a)/(1b)  -> non-vacuous positives: the owner RPC call creates exactly one A-owned
--                account carrying the passed sub_cat AND exactly one acct_setup opening-
--                balance row (amount/date/type as passed). RED if the RPC dropped either
--                write, mis-set the discriminator, or mis-scoped ownership.
--   (1c)       -> same-txn creator-grant: RED if the 003 AFTER-INSERT DEFINER trigger did not
--                fire in-txn before statement 2 (account_users(wr) absent -> statement 2's
--                wr_access-JOIN could not have been satisfied inside the RPC body).
--   (2a)       -> caller-bound ownership: B's RPC call yields a B-owned account carrying B's
--                OWN sub_cat. RED if users_id ever became a forgeable parameter, or if the
--                caller's own sub_cat were wrongly rejected (non-vacuous control for (3a)).
--   (3a)       -> LOAD-BEARING: RED if the 012 fn_account_matched_sub_cat fence were bypassed
--                by routing through the RPC -> B could tag with A's sub_cat via /rpc.
--   (3b)       -> RED if the RPC were non-atomic on the sub_cat-fence path (statement-1
--                account would orphan when statement-1's own trigger raised — trivially 0 here,
--                but guards the all-or-nothing contract on the first-statement failure path).
--   (4a)       -> the acct_setup insert (statement 2) fails NOT NULL (23502) when p_as_of_date
--                is NULL — proves statement 2 is reached AND can fail after statement 1.
--   (4b)       -> LOAD-BEARING ATOMICITY: the statement-2 failure rolled back statement 1 —
--                NO orphan account persists. RED if the two writes were not one transaction.
--   (7)        -> NaN DB-backstop: RED if the account_trans.amount CHECK (amount <> 'NaN') were
--                absent -> a NaN initial value would persist via the API-exposed RPC (which
--                bypasses the app-layer Zod NaN reject). Fails closed at 23514 (Sec should-fix).
--   (5)        -> RED if a NULL p_sub_cat_id were rejected (untagged/Unsorted-pending must be
--                creatable via the RPC — the 012 WHEN-clause skip must hold through the RPC).
--   (6a)/(6b)  -> RED if EXECUTE were granted to PUBLIC/anon (internet-facing exposure of a
--                write RPC). (6a) asserts the grant absence; (6b) the actual anon call fails closed.
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 2 (RT-22 + RT-26; 013 is authenticated-tier
--   INVOKER write-composition — no infra-credential (RT-22) or SUPABASE_SERVICE_ROLE_KEY
--   (RT-26) surface; the create path uses NO service_role). Decision-3 family UNCHANGED at 5
--   (013 adds NO FK-shaped column; it PASSES p_sub_cat_id THROUGH to the 012 canonical
--   instance #5 fence — evaluated there, not a new obligation). Per the 013 header 3-axis.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b();
--   NO PII / NO real account numbers / NO prod data. BOTH tenants populated with their OWN
--   user_taxonomy row (A: a_sub1; B: b_sub1) so the matched-tenant ACCEPT (own) and cross-
--   tenant REJECT (A's, under B) both have real referents. user_taxonomy is V1-write-dormant,
--   so those rows are seeded PRIVILEGED (role=postgres). All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so NO
--   `_rls.*` call runs under authenticated. Tenant UUIDs + row ids are resolved to psql
--   LITERALS via \gset at role=postgres; every _rls.set_tenant is called at role=postgres and
--   each block restores role=postgres before the next. \gset var names are ALL-LOWERCASE.
--
-- ⟦WIRE-VALIDATE⟧ authored against 013's firmed contract; the authoritative run is against the
--   001->013 reset stack. Roles authenticated / anon name-checked in the blocks. RED-until-013-
--   applied is expected on any pre-013 stack (the function would not exist).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(12);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session). Two tenants in auth.users, each with their OWN
-- user_taxonomy row (V1-write-dormant -> the only write path is privileged; users_id set
-- explicitly since auth.uid() is NULL under postgres).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat)
  values (:'ta', 'asset', 'Brokerage', 'US Equity')
  returning id as a_sub1 \gset
insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat)
  values (:'tb', 'asset', 'Brokerage', 'US Equity')
  returning id as b_sub1 \gset

-- =====================================================================
-- BLOCK 1 (authenticated A) — owner create positive: ONE RPC call creates account +
--   acct_setup row + RETURNS the account_id; NULL sub_cat also allowed.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- Owner RPC call (the SELF-201 create path). Capture the RETURNED account_id.
select pfin.fn_create_manual_account(
  'A manual acct', 'depository', 'household', 'taxable', 1000.00, '2026-04-01', :a_sub1
) as rpc_acct \gset

-- (1a) the RETURN maps to exactly one A-owned account carrying the passed sub_cat.
select is(
  (select count(*) from pfin.account
     where account_id = :rpc_acct and users_id = :'ta' and sub_cat_id = :a_sub1)::bigint,
  1::bigint,
  '(1a) owner create: the RPC returned an account_id for exactly one A-owned account (users_id=auth.uid()=A) carrying the passed sub_cat_id (account write + return value correct)'
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
--      account_users(rd,wr=true) row for the RPC-created account. This is the evidence that the
--      003 trigger fired in the SAME transaction BEFORE statement (2) ran — the mechanism that
--      let statement (2)'s account_trans_insert wr_access-JOIN (006) succeed inside the RPC body.
select is(
  (select (rd_access and wr_access) from pfin.account_users
     where account_id = :rpc_acct and users_id = :'ta'),
  true,
  '(1c) same-txn creator-grant: fn_grant_creator_access seeded account_users(rd=t,wr=t) for A''s RPC-created account — proving the 003 AFTER-INSERT DEFINER trigger fired in-txn BEFORE statement 2, satisfying its wr_access-JOIN'
);

-- (5) NULL p_sub_cat_id allowed through the RPC (untagged/Unsorted-pending; 012 WHEN skip holds).
select lives_ok(
  $$ select pfin.fn_create_manual_account(
       'A no subcat', 'depository', 'household', 'taxable', 50, '2026-04-05'
     ) $$,
  '(5) NULL sub_cat_id: the RPC succeeds with p_sub_cat_id defaulted/NULL (untagged/Unsorted-pending is creatable — the 012 WHEN(new.sub_cat_id IS NOT NULL) skip holds through the RPC)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 2 (authenticated B) — caller-bound ownership + LOAD-BEARING cross-tenant sub_cat.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);

-- B's own RPC call, tagged with B's OWN sub_cat (non-vacuous control for (3a)).
select pfin.fn_create_manual_account(
  'B manual acct', 'depository', 'household', 'taxable', 200, '2026-04-02', :b_sub1
) as rpc_acct_b \gset

-- (2a) caller-bound ownership: B's call yields a B-owned account carrying B's OWN sub_cat.
--      users_id is NOT a parameter -> B cannot create for another tenant; and the sub_cat
--      path ACCEPTS the caller's own tag (proving (3a)'s raise is mismatch-driven).
select is(
  (select count(*) from pfin.account
     where account_id = :rpc_acct_b and users_id = :'tb' and sub_cat_id = :b_sub1)::bigint,
  1::bigint,
  '(2a) caller-bound ownership: B''s RPC call yields a B-owned account (users_id=auth.uid()=B — NOT a forgeable param, so B cannot create for another tenant) carrying B''s OWN sub_cat (own-tag ACCEPTED through the RPC)'
);

-- (3a) LOAD-BEARING: B calls the RPC with A's sub_cat_id -> the 012 matched-tenant fence
--      fires THROUGH the RPC (defense-in-depth) -> RAISE. The forge surface Decision-3
--      instance #5 fences is not reopened by wrapping the write in an INVOKER RPC.
select throws_like(
  format($$ select pfin.fn_create_manual_account(
              'B steal', 'depository', 'household', 'taxable', 300, '2026-04-03', %s) $$, :a_sub1),
  'cross-tenant Sub-Cat rejected%',
  '(3a) LOAD-BEARING cross-tenant sub_cat THROUGH the RPC: B calls fn_create_manual_account with A''s sub_cat_id -> the 012 fn_account_matched_sub_cat fence RAISES (defense-in-depth; the RPC does NOT bypass the matched-tenant trigger)'
);

-- (3b) atomicity of the (3a) failure: the statement-(1) trigger raise left NO orphan account.
select is(
  (select count(*) from pfin.account where name = 'B steal' and users_id = :'tb')::bigint,
  0::bigint,
  '(3b) atomicity (statement-1-fence path): the (3a) cross-tenant raise left NO orphan ''B steal'' account for B (all-or-nothing — the account INSERT is rolled back with the failing call)'
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
--     and admits every real value. PLACEMENT-AGNOSTIC: whether the CHECK lands 013-inline
--     (ALTER) or in a follow-on migration, directory-mode pgTAP runs against the fully-applied
--     stack, so the reject holds either way. (RED until the CHECK lands — expected ⟦WIRE-VALIDATE⟧.)
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
-- (6a) grant-layer: anon holds NO EXECUTE on the RPC (role-independent catalog assertion).
select ok(
  not has_function_privilege(
    'anon',
    'pfin.fn_create_manual_account(text, text, text, text, numeric, date, bigint)',
    'EXECUTE'),
  '(6a) anon holds NO EXECUTE on fn_create_manual_account (revoked from PUBLIC, granted to authenticated only — the write RPC is not anon-callable)'
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

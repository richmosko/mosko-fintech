-- =====================================================================
-- Per-Wave battery — M1-evt Slice A1 (SELF-293): (1) transaction_type vocab widen
--   {standard,acct_setup} -> {standard,acct_setup,basis_adjust,corp_action}; (2) the
--   metadata jsonb column on account_trans_annotation (023); (3) the combined Trade-
--   constraint fence fn_account_trans_annotation_trade_constraints (Sec Condition A) —
--   consistency (security_id <=> cat='Trade') + sign-alignment (BTO/BTC=>qty>0,
--   STC/STO=>qty<0). V1-SHIP-BLOCK; JOINT-REVIEW-MANDATORY (money-flow / GL fact).
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/030_transaction_type_vocab_trade_constraints.sql
--   - CHECK account_trans_transaction_type_check widened (012 -> 030; same name).
--   - column account_trans_annotation.metadata jsonb NULL (inherits 023 RLS + full-CRUD).
--   - fn_account_trans_annotation_trade_constraints() + trigger
--       account_trans_annotation_trade_constraints (BEFORE INS/UPD WHEN sub_cat_id NOT
--       NULL; SECURITY INVOKER; NULL-safe fail-closed; UPDATE path load-bearing).
-- Prereqs on the reset stack: 001 (pfin), 003 (account + creator-grant rd=t/wr=t), 004
--   (account_trans immutable ledger + transaction_type), 006 (account_trans rd/wr RLS +
--   grant), 009 (user_taxonomy), 012 (the CHECK 030 widens), 016 (pfin.asset — the
--   security_id target; a GLOBAL asset users_id=NULL is legal for any tenant), 017
--   (security_id/quantity facts + the global-OR-owned #7 fence), 023 (the annotation host
--   + the #10 matched-tenant fence the trade fence composes behind).
--
-- ┌─ ROLE MODEL (why annotation tests run under AUTHENTICATED — contrast 009/029) ──────────┐
-- │ Unlike write-dormant 009/029, account_trans_annotation (023) is FULL-CRUD authenticated. │
-- │ So the trade-fence tests run under the REAL path (authenticated A on its OWN txns + OWN   │
-- │ Sub-Cats): the #10 fence + the trade fence (both SECURITY INVOKER) compose with RLS just  │
-- │ as in production. The FIXTURE (accounts, asset, account_trans, taxonomy) + the vocab CHECK│
-- │ test + the trade fail-closed isolation are seeded/run PRIVILEGED (role=postgres). Roles   │
-- │ are restored to postgres between phases (PR #121 _rls-USAGE discipline: _rls.set_tenant   │
-- │ is invoked at role=postgres, which switches to authenticated for the following stmts).    │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ TRIGGER ORDER + WHY (7b) DISABLES #10 (a documented, rolled-back test-only device) ────┐
-- │ Two BEFORE INS/UPD triggers fire on the 023 annotation, alphabetically:                  │
-- │   account_trans_annotation_matched_sub_cat  (#10, 023)  <  ..._trade_constraints (030).  │
-- │ So #10 fires FIRST. For an unresolvable/cross-tenant reference #10 raises before the trade │
-- │ fence runs, MASKING the trade fence's own NULL-safe fail-closed branch. (7b) transiently  │
-- │ DISABLEs #10 (role=postgres, inside the rolled-back txn, re-ENABLEd immediately after) so  │
-- │ the trade fence's `cannot resolve fact` guard is the SOLE gate and is proven to have teeth │
-- │ — the 023 LEG-F honesty (a test-only isolation device, NOT a prod path). (7a) proves #10  │
-- │ itself is UNCHANGED by 030 (still fires for a cross-tenant Sub-Cat).                       │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (1a)/(1b) basis_adjust / corp_action INSERT into account_trans PASS — RED if the CHECK
--        were not widened (the settle-before-import vocab would reject a real fact).
--   (1c) a bogus transaction_type RAISES 23514 — RED if the CHECK were dropped/opened.
--   (2a) securities row (security_id set) + non-Trade cat RAISES consistency — RED if the
--        biconditional were absent (a securities fact mis-classed as cash).
--   (2b) securities row + Trade (BTO, qty>0) PASSES — non-vacuous consistency control.
--   (2c) cash row (security_id NULL) + Trade cat RAISES consistency — RED if a cash row could
--        masquerade as a Trade.
--   (2d) cash row + non-Trade cat PASSES — non-vacuous control.
--   (3a)/(3b)/(3c)/(3d) BTO/STC/BTC/STO on the sign-aligned frozen quantity PASS — RED if a
--        legit trade direction were over-blocked (all four sub-cats recognized).
--   (3e) BTO on qty<0 RAISES sign-alignment — RED if a buy could sit on a sell quantity.
--   (3f) STC on qty>0 RAISES sign-alignment — RED if a sell could sit on a buy quantity.
--   (3g) BTO on qty=0 RAISES sign-alignment (Sec pre-push boundary lock) — RED if the fence
--        used `>= 0` instead of strict `> 0` (a zero-quantity buy must not pass).
--   (4a) UPDATE path load-bearing: re-categorizing BTO->STC on a frozen qty>0 row RAISES on
--        UPDATE — RED if the fence covered only INSERT (an overlay edit could break the invariant).
--   (5a) NULL sub_cat annotation on a securities row PASSES (WHEN-skip) — RED if the trade
--        fence did not skip NULL (a Suspense-pending line could never land).
--   (6a) non-Trade cash re-categorization (Expense->Expense) PASSES — RED if the fence
--        over-reached onto ordinary cash rows.
--   (7a) #10 UNCHANGED: A tagging its txn with B's Sub-Cat still RAISES 'cross-tenant Sub-Cat
--        rejected%' — RED if 030 disturbed #10 or changed the trigger ordering.
--   (7b) trade fence fail-closed (isolated): an unresolvable trans_id RAISES 'cannot resolve
--        fact%' (fires BEFORE the FK check) — RED if the NULL-safe guard silently skipped.
--   (8a) metadata jsonb round-trips (write {"reason":"wash_sale"}, read it back).
--   (8b) two-tenant read isolation: B sees 0 of A's annotations (023 RLS unchanged by 030).
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22 + RT-26 + RT-27; 030 adds ZERO catalogued
--   §10 instances — a CHECK-widen + a jsonb value column + one authenticated-tier INVOKER
--   value-fence; no service_role grant, no admission channel). Decision-3 family UNCHANGED
--   (12 labeled / 10 DDL-realized after 029): the trade fence is Decision-3-NEUTRAL (no
--   cross-tenant dimension — #10 already fences a cross-tenant sub_cat; Sec Condition A). The
--   metadata jsonb is a value column (NOT FK-shaped). The deferred lot-match buy-reference FK
--   (Slice B) is the next instance (#14, Sec pins) — NOT this migration.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants _rls.tenant_a()/_b(); NO PII /
--   NO real account numbers / NO prod data. A owns acct-alpha + securities/cash txns + Trade
--   (BTO/BTC/STC/STO) & Expense Sub-Cats; B owns acct-beta + a Trade Sub-Cat (the cross-tenant
--   #10 referent). A GLOBAL asset (users_id NULL) backs every security_id (legal for any
--   tenant, 016/017). Trade taxonomy uses the ratified cat='Trade' (028/ADR-031 Amendment 1).
--   All in a rolled-back txn.
--
-- ⟦WIRE-VALIDATE⟧ authored against 030's firmed contract; the authoritative run is the 001->030
--   reset stack (Backend owns the clean-apply). Locally the DB is NOT 030-clean, so a net-zero
--   rolled-back harness \i's 030 transiently before this file (self-provisioning the Trade
--   taxonomy fixture); CI (pg_prove directory-mode, db-tests.yml) is the green gate. plan(20).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(21);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed seed path).
--  - Two tenants; A owns acct-alpha, B owns acct-beta (003 creator-grant seeds rd=t/wr=t).
--  - ONE global asset (users_id NULL) backing every securities row (017 fence: global is
--    legal for any tenant).
--  - account_trans: securities rows (security_id=g_asset, signed quantity) + cash rows
--    (security_id NULL, quantity 0). transaction_type defaults 'standard'.
--  - taxonomy: A owns Trade sub-cats BTO/BTC/STC/STO + Expense (Groceries/Rent); B owns a
--    Trade/BTO (the #10 cross-tenant referent).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-alpha', 'investment', 'household', 'taxable')
  returning account_id as accta \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'acct-beta', 'investment', 'household', 'taxable')
  returning account_id as acctb \gset

-- GLOBAL asset (users_id NULL) — legal security_id for any tenant (016 G1 hybrid registry).
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'GSX', 'Global Sec X') returning asset_id as g_asset \gset

-- Securities account_trans (security_id set, signed quantity). amount arbitrary/finite.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:accta, '2026-03-01', -100, 'vSNT', 'sec/non-trade', :g_asset,  10) returning trans_id as ct_sec_nt \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:accta, '2026-03-02', -100, 'vSTR', 'sec/trade',     :g_asset,  10) returning trans_id as ct_sec_tr \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:accta, '2026-03-03', -100, 'vBTOP', 'bto qty+',     :g_asset,   5) returning trans_id as ct_bto_p \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:accta, '2026-03-04',  100, 'vSTCN', 'stc qty-',     :g_asset,  -5) returning trans_id as ct_stc_n \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:accta, '2026-03-05', -100, 'vBTCP', 'btc qty+',     :g_asset,   6) returning trans_id as ct_btc_p \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:accta, '2026-03-06',  100, 'vSTON', 'sto qty-',     :g_asset,  -6) returning trans_id as ct_sto_n \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:accta, '2026-03-07', -100, 'vBTON', 'bto qty-',     :g_asset,  -4) returning trans_id as ct_bto_n \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:accta, '2026-03-08',  100, 'vSTCP', 'stc qty+',     :g_asset,   4) returning trans_id as ct_stc_p \gset
-- qty=0 boundary row (securities): the 017 CHECK (quantity=0 OR security_id NOT NULL) permits
-- a zero-qty securities row since security_id is set — the (3g) strict->0 boundary lock.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:accta, '2026-03-16', -100, 'vBTOZ', 'bto qty0',     :g_asset,   0) returning trans_id as ct_bto_z \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:accta, '2026-03-09', -100, 'vUPD', 'update path',   :g_asset,   8) returning trans_id as ct_upd \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:accta, '2026-03-10', -100, 'vNULL', 'null-skip',    :g_asset,  10) returning trans_id as ct_null \gset

-- Cash account_trans (security_id NULL, quantity 0 default).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-03-11', -50, 'vCTR', 'cash/trade')  returning trans_id as ct_cash_tr \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-03-12', -50, 'vCNT', 'cash/non-trade') returning trans_id as ct_cash_nt \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-03-13', -50, 'vNT2', 'non-trade update') returning trans_id as ct_nt2 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-03-14', -50, 'vMETA', 'metadata') returning trans_id as ct_meta \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-03-15', -50, 'vX7A', 'cross-tenant #10') returning trans_id as ct_x7a \gset

-- Taxonomy (ratified cat='Trade' for the four Trade sub-cats; Expense for non-Trade).
insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat) values (:'ta','cashflow','Trade','BTO') returning id as a_bto \gset
insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat) values (:'ta','cashflow','Trade','BTC') returning id as a_btc \gset
insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat) values (:'ta','cashflow','Trade','STC') returning id as a_stc \gset
insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat) values (:'ta','cashflow','Trade','STO') returning id as a_sto \gset
insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat) values (:'ta','cashflow','Expense','Groceries') returning id as a_exp \gset
insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat) values (:'ta','cashflow','Expense','Rent') returning id as a_exp2 \gset
insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat) values (:'tb','cashflow','Trade','BTO') returning id as b_bto \gset

-- =====================================================================
-- PHASE 1 (role=postgres) — vocab CHECK (AC1) + the isolated trade fail-closed (AC7b).
-- =====================================================================
-- (1a) basis_adjust INSERT into the immutable ledger PASSES the widened CHECK.
select lives_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type)
              values (%s, '2026-03-20', 0, 'vBA', 'basis adj', 'basis_adjust') $$, :accta),
  '(1a) vocab widen: transaction_type=basis_adjust INSERT PASSES account_trans_transaction_type_check'
);
-- (1b) corp_action INSERT PASSES.
select lives_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type)
              values (%s, '2026-03-21', 0, 'vCA', 'corp action', 'corp_action') $$, :accta),
  '(1b) vocab widen: transaction_type=corp_action INSERT PASSES the widened CHECK'
);
-- (1c) a bogus transaction_type RAISES 23514.
select throws_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type)
              values (%s, '2026-03-22', 0, 'vBOGUS', 'bogus', 'wormhole') $$, :accta),
  '23514', null,
  '(1c) vocab CHECK fails closed: a transaction_type outside the lean set RAISES check_violation (23514)'
);

-- (7b) trade fence fail-closed, ISOLATED from #10 (test-only, rolled back): disable the
--      #10 fence so the trade fence is the sole BEFORE trigger, then an unresolvable
--      trans_id trips the trade fence's NULL-safe guard (fires BEFORE the FK check).
alter table pfin.account_trans_annotation disable trigger account_trans_annotation_matched_sub_cat;
select throws_like(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, %s) $$, 9999999, :a_bto),
  '%cannot resolve fact%',
  '(7b) trade fence fail-closed (isolated from #10): an unresolvable trans_id RAISES the trade fence NULL-safe guard (before the FK check)'
);
alter table pfin.account_trans_annotation enable trigger account_trans_annotation_matched_sub_cat;

-- =====================================================================
-- PHASE 2 (authenticated A) — consistency / sign / UPDATE / NULL-skip / non-Trade / #10 /
--   metadata write. A annotates its OWN txns with its OWN Sub-Cats (the real path).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- --- (AC2) consistency (both directions) ---
-- (2a) securities row + non-Trade cat -> RAISE (security present but cat != 'Trade').
select throws_like(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, %s) $$, :ct_sec_nt, :a_exp),
  '%Trade consistency violation%',
  '(2a) consistency: a securities row (security_id set) tagged non-Trade RAISES (security_id present <=> cat=Trade)'
);
-- (2b) securities row + Trade (BTO, qty+10) -> PASS (non-vacuous consistency control).
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, %s) $$, :ct_sec_tr, :a_bto),
  '(2b) consistency control: a securities row tagged Trade/BTO (qty>0) PASSES (consistency + sign both satisfied)'
);
-- (2c) cash row + Trade cat -> RAISE (security absent but cat = 'Trade').
select throws_like(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, %s) $$, :ct_cash_tr, :a_bto),
  '%Trade consistency violation%',
  '(2c) consistency: a cash row (security_id NULL) tagged Trade RAISES (a cash fact cannot be a Trade)'
);
-- (2d) cash row + non-Trade cat -> PASS (non-vacuous control).
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, %s) $$, :ct_cash_nt, :a_exp),
  '(2d) consistency control: a cash row tagged non-Trade Expense PASSES'
);

-- --- (AC3) sign-alignment (all securities/Trade; consistency already satisfied) ---
-- (3a) BTO on qty>0 PASS.
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, %s) $$, :ct_bto_p, :a_bto),
  '(3a) sign: BTO on qty>0 (buy) PASSES'
);
-- (3b) STC on qty<0 PASS.
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, %s) $$, :ct_stc_n, :a_stc),
  '(3b) sign: STC on qty<0 (sell) PASSES'
);
-- (3c) BTC on qty>0 PASS.
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, %s) $$, :ct_btc_p, :a_btc),
  '(3c) sign: BTC on qty>0 (buy-to-close) PASSES'
);
-- (3d) STO on qty<0 PASS.
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, %s) $$, :ct_sto_n, :a_sto),
  '(3d) sign: STO on qty<0 (sell-to-open) PASSES'
);
-- (3e) BTO on qty<0 RAISE.
select throws_like(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, %s) $$, :ct_bto_n, :a_bto),
  '%sign-alignment%',
  '(3e) sign fails closed: BTO on qty<0 RAISES sign-alignment (a buy cannot sit on a sell quantity)'
);
-- (3f) STC on qty>0 RAISE.
select throws_like(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, %s) $$, :ct_stc_p, :a_stc),
  '%sign-alignment%',
  '(3f) sign fails closed: STC on qty>0 RAISES sign-alignment (a sell cannot sit on a buy quantity)'
);
-- (3g) qty=0 BOUNDARY (Sec pre-push add): BTO on qty=0 must RAISE — locks the STRICT
--      quantity > 0 semantics against a future >= 0 regression (a zero-qty buy is not a buy).
select throws_like(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, %s) $$, :ct_bto_z, :a_bto),
  '%sign-alignment%',
  '(3g) sign boundary: BTO on qty=0 RAISES sign-alignment (locks strict quantity>0 — a >=0 regression would let a zero-qty buy through)'
);

-- --- (AC4) UPDATE path load-bearing ---
-- setup: annotate ct_upd (qty+8) with BTO (valid). Then re-categorize BTO->STC -> RAISE on UPDATE.
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:ct_upd, :a_bto);
select throws_like(
  format($$ update pfin.account_trans_annotation set sub_cat_id = %s where trans_id = %s $$, :a_stc, :ct_upd),
  '%sign-alignment%',
  '(4a) UPDATE path load-bearing: re-categorizing BTO->STC on a frozen qty>0 row RAISES sign-alignment on UPDATE (fence covers UPDATE, not only INSERT)'
);

-- --- (AC5) NULL-skip ---
-- (5a) NULL sub_cat on a securities row PASSES (WHEN clause skips the trade fence).
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, null) $$, :ct_null),
  '(5a) NULL-skip: a NULL sub_cat annotation on a securities row PASSES (WHEN sub_cat_id IS NOT NULL skips the trade fence — Suspense-pending)'
);

-- --- (AC6) non-Trade unaffected ---
-- setup: annotate ct_nt2 (cash) with Expense. Then re-categorize to another non-Trade -> PASS.
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:ct_nt2, :a_exp);
select lives_ok(
  format($$ update pfin.account_trans_annotation set sub_cat_id = %s where trans_id = %s $$, :a_exp2, :ct_nt2),
  '(6a) non-Trade unaffected: re-categorizing a cash Expense annotation to another non-Trade Sub-Cat PASSES (fence consistency-neutral for non-securities)'
);

-- --- (AC7a) #10 matched-tenant fence UNCHANGED by 030 ---
-- A tags its txn with B's Sub-Cat -> #10 RAISES (fires before the trade fence).
select throws_like(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, %s) $$, :ct_x7a, :b_bto),
  '%cross-tenant Sub-Cat rejected%',
  '(7a) #10 unchanged: A tagging its txn with B''s Sub-Cat still RAISES the #10 matched-tenant fence (030 did not disturb #10 or the trigger ordering)'
);

-- --- (AC8a) metadata jsonb round-trip (write under A) ---
insert into pfin.account_trans_annotation (trans_id, sub_cat_id, metadata)
  values (:ct_meta, :a_exp, '{"reason":"wash_sale"}'::jsonb);
select is(
  (select metadata->>'reason' from pfin.account_trans_annotation where trans_id = :ct_meta),
  'wash_sale',
  '(8a) metadata jsonb round-trips: A writes {"reason":"wash_sale"} on its own annotation and reads it back under RLS'
);

select set_config('role', 'postgres', true);

-- =====================================================================
-- PHASE 3 (authenticated B) — metadata two-tenant read isolation (AC8b).
-- =====================================================================
-- (8b) B sees 0 of A's annotations (023 ata_select rd_access RLS — unchanged by 030).
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from pfin.account_trans_annotation where trans_id = :ct_meta)::bigint, 0::bigint,
  '(8b) two-tenant read isolation: B sees 0 of A''s annotations incl. metadata (023 RLS unchanged by 030)'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;

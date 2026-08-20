-- =====================================================================
-- Per-Wave battery — pfin.fn_subcat_market_value's cash leg routes a
--   liability-type account's cash to the caller's own 'Liabilities' /
--   'Liability Balances' Sub-Cat (080) instead of the per-currency raw-cash
--   bucket. SELF-329; account-type-aware cash routing, F/CTO-ratified
--   2026-08-17. Read-only fix: NO new table, NO new DEFINER, NO new
--   FK-shaped column, NO signature/grant/comment change.
-- =====================================================================
-- BINDS TO MIGRATION:
--   supabase/migrations/081_fn_subcat_market_value_liability_cash_route.sql
--   cash_leg gains a CASE on account_type: 'liability' -> LEFT JOIN the
--   caller's own user_taxonomy row matched BY NAME (domain='asset',
--   cat='Liabilities', sub_cat='Liability Balances', users_id=acc.users_id
--   — the users_id conjunct REDUNDANT under INVOKER RLS, stated anyway,
--   ADDING a gate); every other account_type unchanged (currency-asset
--   junction route). sec_leg is BYTE-IDENTICAL to the live definition —
--   untouched.
--
-- ┌─ VALUE-NEUTRAL ON THE TOTAL, NOT ON THE ROW SET (081''s own header) ────┐
-- │ "Routing moves a value BETWEEN rows; the sum over all returned rows is  │
-- │ unchanged... any assertion that only compares totals will pass whether  │
-- │ or not this migration applied." The legs below are ALL row-level for   │
-- │ exactly this reason — a totals-only battery is blind to this migration │
-- │ by the migration''s own design.                                        │
-- └───────────────────────────────────────────────────────────────────────┘
--
-- ┌─ NOT DUPLICATED HERE, BY DESIGN — already watched elsewhere ────────────┐
-- │ sec_leg (the price-pick kernel) is reproduced byte-for-byte: SELF-328''s │
-- │ FENCE1a/FENCE1b/FENCE1c (078''s battery) already assert this LIVE, every │
-- │ PR, over the catalog definition this migration replaces — re-asserting │
-- │ kernel identity here would duplicate an existing, independently-owned  │
-- │ watcher rather than add coverage. Likewise the EXECUTE grants (ACL1/    │
-- │ ACL2, 078''s battery) and the STABLE pin (V5, 079''s battery) — CREATE OR │
-- │ REPLACE preserves grants and this body carries `stable` inline, so     │
-- │ both existing legs continue to correctly watch this exact function     │
-- │ post-081 with ZERO changes needed on either side. VERIFIED, not        │
-- │ assumed: 078''s and 079''s EXISTING batteries (SELF-328 branch, unmerged │
-- │ at authoring time) were re-run against the POST-081 catalog before this │
-- │ file was finalized — FENCE1a=3, FENCE1b=1, FENCE1c=3, V5=''s'', ACL1/ACL2 │
-- │ unchanged, all green. See the hand-off report for the run.             │
-- └───────────────────────────────────────────────────────────────────────┘
--
-- Prereqs exercised (on the 001->081 stack): 003 (account_type domain,
--   pfin.account direct-owner RLS); 022 (user_asset_category junction, the
--   022 cash-via-currency-asset model this migration adds a SECOND route
--   alongside); 041/077 (seeded Cash/CD vocabulary + the Cash Balances
--   catch-all, reused as the "before" route control); 056
--   (fn_account_cash_as_of, TOTAL over pfin.account — the zero-balance
--   filter this migration leaves unchanged); 076 (fn_subcat_market_value''s
--   own R1/R2/R3 contract — INVOKER, no tenant param, the unclassified row);
--   080 (the route TARGET, matched by NAME — the migration this file is
--   order-dependent on).
--
-- §10 / DECISION 3: §10 ledger UNCHANGED (081 changes a classification join
--   inside one read-only SQL function — no credential surface, no
--   code-layer fence, no network/config surface; read ADR-011 Decision 4
--   live). Decision-3 family UNCHANGED — the new relation reference is a
--   JOIN PREDICATE inside a query matched by (users_id, domain, cat,
--   sub_cat), not a stored FK; no column exists to check. This battery
--   introduces no catalogued instance.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants (raw
--   literals, suffixed '81'). NO PII / NO real account numbers / NO prod
--   data. All seeds PRIVILEGED (role=postgres) with users_id set
--   EXPLICITLY. Whole file in one rolled-back txn.
--
-- ⟦WIRE-VALIDATE⟧ authored + fixture-verified GREEN via a transient apply of
--   001->081 (080 before 081, per 081''s own stated order dependency)
--   against a postgres-owned scratch DB (NON-destructive; zero
--   cluster-level grants). plan(8): 3 routing value (L1-L3) + 1 real-estate-
--   type discriminator folded into L2 (own structural judgment: proves the
--   trigger is account_type='liability' specifically, not "any non-cash-
--   like type") + 2 missing-target (L4a-L4b) + 1 zero-balance suppression
--   (Z1) + 2 isolation (I1-I2) = 8.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

select plan(8);

\set ta '00000000-0000-0000-0000-00000000a081'
\set tb '00000000-0000-0000-0000-00000000b081'
\set tc '00000000-0000-0000-0000-00000000c081'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc');

-- ---------------------------------------------------------------------
-- FIXTURE. Tenant A holds FOUR accounts, pure cash (no securities — this
--   migration touches ONLY cash_leg, so a securities leg would add nothing
--   to what these legs discriminate):
--   a-dep (depository, +200.00) + a-re (real_estate TYPE, +80.00) — BOTH
--     classified via the GLOBAL USD currency-asset (asset_id=1) to A''s OWN
--     'Cash Balances' row (a_cb, 077''s catch-all — reused rather than
--     invented, matching house convention). a-re is the OWN judgment call:
--     account_type='real_estate' must NOT trigger the liability route
--     either — the trigger is account_type='liability' SPECIFICALLY, not
--     "any non-depository type".
--   a-cc (liability, -400.00, real card debt) + a-cc-over (liability,
--     +150.00, OVERPAID) — BOTH route to A''s 'Liability Balances' row
--     (a_lb, 080), by account_type alone, regardless of sign.
--   Expected: Liability Balances = -400+150 = -250.00 (L1). Cash Balances =
--   200+80 = 280.00 (L2, proves NEITHER -400 NOR +150 landed there — the
--   ONLY routing combination producing BOTH -250.00 AND 280.00
--   simultaneously is "both liability accounts route to Liability
--   Balances, both non-liability accounts route to Cash Balances"; any
--   other routing produces a DIFFERENT pair). Total = -250+280 = 30.00 (L3).
-- ---------------------------------------------------------------------
insert into pfin.user_taxonomy (users_id, cat, sub_cat) values
  (:'ta','Cash','Cash Balances') returning id as a_cb \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat) values
  (:'ta','Liabilities','Liability Balances') returning id as a_lb \gset

insert into pfin.user_asset_category (users_id, asset_id, sub_cat_id) values
  (:'ta', 1, :a_cb);

insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta','a-dep-81','depository','household','taxable') returning account_id as a_dep \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:a_dep, 200.00, 'USD', '2026-07-01', 'seed');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta','a-re-81','real_estate','household','taxable') returning account_id as a_re \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:a_re, 80.00, 'USD', '2026-07-01', 'seed');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta','a-cc-81','liability','household','taxable') returning account_id as a_cc \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:a_cc, -400.00, 'USD', '2026-07-01', 'seed');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta','a-cc-over-81','liability','household','taxable') returning account_id as a_cc_over \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:a_cc_over, 150.00, 'USD', '2026-07-01', 'seed');

-- ---------------------------------------------------------------------
-- TENANT B — isolation control. Own liability account, DISTINCT value.
-- ---------------------------------------------------------------------
insert into pfin.user_taxonomy (users_id, cat, sub_cat) values
  (:'tb','Liabilities','Liability Balances') returning id as b_lb \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'tb','b-cc-81','liability','household','taxable') returning account_id as b_cc \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:b_cc, -120.00, 'USD', '2026-07-01', 'seed');

-- ---------------------------------------------------------------------
-- TENANT C — missing-target (leg e): a liability account, but the USER''S
--   OWN Liability Balances row is then DELETED (not the global taxonomy_
--   default row — 080''s reach is unaffected). The LEFT JOIN degrades to
--   NULL keys; the value must land in the R2 unclassified row, intact.
-- ---------------------------------------------------------------------
insert into pfin.user_taxonomy (users_id, cat, sub_cat) values
  (:'tc','Liabilities','Liability Balances') returning id as c_lb \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'tc','c-cc-81','liability','household','taxable') returning account_id as c_cc \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:c_cc, -75.00, 'USD', '2026-07-01', 'seed');
delete from pfin.user_taxonomy where id = :c_lb;

-- =====================================================================
-- ROUTING VALUE (L1-L3) — the three discriminating totals per the header
-- box: leg (a) signed liability value, leg (b) cash unaffected, leg (d)
-- overpay stays in the SAME row (jointly proven by L1+L2 together — see
-- the fixture comment above for why no other routing combination fits),
-- leg (c) total unchanged, PLUS the own-judgment real-estate-type
-- discriminator folded into L2 (a-re contributes to Cash Balances, proving
-- the trigger is account_type='liability' specifically).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select market_value from pfin.fn_subcat_market_value('2026-07-25'::date, true) where sub_cat_id = :a_lb),
  -250.00::numeric,
  '(L1) leg (a)+(d): Liability Balances = EXACTLY -250.00 = a-cc (-400.00, real debt) + a-cc-over (+150.00, OVERPAID) — BOTH liability accounts route here regardless of sign; the SIGNED value is visible (not a magnitude, not clamped to <=0)'
);
select is(
  (select market_value from pfin.fn_subcat_market_value('2026-07-25'::date, true) where sub_cat_id = :a_cb),
  280.00::numeric,
  '(L2) leg (b) + own judgment (account_type discriminator): Cash Balances = EXACTLY 280.00 = a-dep (200.00, depository) + a-re (80.00, real_estate TYPE) — NEITHER the -400.00 debt NOR the +150.00 overpay landed here (leg b), and a real_estate-TYPE account routes via the currency-asset junction same as depository, proving the liability route triggers on account_type=''liability'' specifically, not "any non-depository type"'
);
select is(
  (select sum(market_value) from pfin.fn_subcat_market_value('2026-07-25'::date, true)),
  30.00::numeric,
  '(L3) leg (c): total = EXACTLY 30.00 = -250.00 (Liability Balances) + 280.00 (Cash Balances) — the footing is unchanged by routing (081''s own header: "the sum over all returned rows is unchanged"); this is the ONLY leg that could pass on a totally-unrouted (pre-081) or mis-routed catalog by coincidence, which is exactly why L1/L2 exist as the discriminating legs and this one is the corroborating footing check, not the primary proof'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- MISSING-TARGET (L4a-L4b) — leg (e). Tenant C''s liability debt, with the
-- USER''S OWN route-target row deleted, lands in the R2 unclassified
-- (Unsorted) row — value intact, never dropped, never silently zeroed.
-- =====================================================================
select _rls.set_tenant(:'tc'::uuid);
select is(
  (select market_value from pfin.fn_subcat_market_value('2026-07-25'::date, true) where sub_cat_id is null),
  -75.00::numeric,
  '(L4a) leg (e): missing-target — C''s -75.00 liability debt, with the OWN Liability Balances row deleted (global taxonomy_default row untouched), lands in the R2 unclassified row with its SIGNED value INTACT — LEFT JOIN degrades to NULL keys, never an INNER JOIN that would drop the row, never silently zeroed'
);
select ok(
  (select cat is null and sub_cat is null
     from pfin.fn_subcat_market_value('2026-07-25'::date, true) where sub_cat_id is null),
  '(L4b) missing-target structural check: the unclassified row''s cat AND sub_cat are BOTH NULL (not just sub_cat_id) — cannot be confused with a real, oddly-named Sub-Cat'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (Z1) ZERO-BALANCE SUPPRESSION — 081''s CONTRACT states this filter is
-- UNCHANGED, worth re-verifying rather than trusting the claim: a tenant
-- with a SOLE zero-balance liability account (paid off) contributes NO
-- row at all — not a phantom 0.00 Liability Balances row.
-- =====================================================================
\set td '00000000-0000-0000-0000-00000000d081'
insert into auth.users (id) values (:'td');
insert into pfin.user_taxonomy (users_id, cat, sub_cat) values
  (:'td','Liabilities','Liability Balances') returning id as d_lb \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'td','d-cc-paid-81','liability','household','taxable') returning account_id as d_cc \gset
-- no checkpoint at all -> fn_account_cash_as_of degrades to 0 by construction.
select _rls.set_tenant(:'td'::uuid);
select is(
  (select count(*) from pfin.fn_subcat_market_value('2026-07-25'::date, true)),
  0::bigint,
  '(Z1) zero-balance liability suppression, re-verified rather than trusted from 081''s CONTRACT claim: a tenant whose SOLE account is a paid-off (zero-balance) liability contributes ZERO rows — not a phantom 0.00 Liability Balances row, matching the SAME `coalesce(c.balance_native,0)<>0` filter this migration leaves unchanged'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- ISOLATION (I1-I2) — the liability route''s new relation carries an
-- EXPLICIT users_id conjunct (081''s own header: "ADDING a gate rather
-- than removing one"). Light coverage here, deliberately: the GENERAL
-- isolation mechanism (INVOKER RLS composition, corrupt-the-control) is
-- already proven at length in 076''s own battery and is UNCHANGED by this
-- migration — this checks the NEW route specifically, not the mechanism.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select market_value from pfin.fn_subcat_market_value('2026-07-25'::date, true) where sub_cat_id = :b_lb),
  -120.00::numeric,
  '(I1) isolation, non-vacuous: tenant B''s Liability Balances = EXACTLY -120.00 (B''s OWN liability account) — does NOT include A''s -250.00, and the two tenants'' Liability Balances rows (different sub_cat_id, same Sub-Cat NAME) never merge'
);
select ok(
  not exists (select 1 from pfin.fn_subcat_market_value('2026-07-25'::date, true) where sub_cat_id = :a_lb),
  '(I2) cross-tenant read fails closed: B''s call to fn_subcat_market_value never returns A''s Liability Balances sub_cat_id (a_lb) — the new relation''s explicit users_id conjunct (081''s own "ADDING a gate" note) holds, verified rather than assumed'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;

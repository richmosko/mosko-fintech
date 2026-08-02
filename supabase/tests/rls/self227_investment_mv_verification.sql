-- =====================================================================
-- Integration battery — §2.1.6 investment MARKET-VALUE-vs-COST-BASIS verification
--   (SELF-227 / V1.1 "Net worth full"; PRD §2.1.6). Proves that investment-account
--   contributions to NAV use CURRENT MARKET VALUE (eod_price × qty × fx), NOT cost basis,
--   and that all three §2.1.x NAV surfaces AGREE. The NAV primitives are already correct
--   (Backend audited CLEAN; migration 052 lands the audit-trace comments) — this battery is
--   the REGRESSION FENCE that locks the MV-not-cost invariant + three-surface consistency,
--   and is the §2.1.6 V1-SHIP-BLOCK deliverable.
-- =====================================================================
-- BINDS TO (read-only — this test authors NOTHING; it exercises already-landed surfaces):
--   pfin.fn_account_unrealized_gl(p_as_of date)          — 049 (per-account MV / cost_basis / G/L)
--   pfin.fn_compute_nav(p_as_of date, p_active_only bool) — 050 (§2.1.1 headline; (today,true))
--   pfin.fn_nav_composition(p_as_of date)                 — 051 (§2.1.5 composition tree → nav)
--   pfin.fn_compute_nav / *_unrealized_gl / *_composition obj_description — 052 (SELF-227 trace)
--   All SECURITY INVOKER (Lock 11). DESIGN C account-total model (ADR-038): 049.cmv = securities
--   MV (qty × eod_price × fx) + cash (roll-forward); investment cost_basis = securities carried
--   book (fn_gl_entries trade_position) + the SAME cash term (cancels). SELF-227 is the assertion
--   that the SECURITIES half of cmv is MARKET, never book.
--
-- FIXTURE CRUX — FUND-then-BUY (per Backend; the Design-C account-total model):
--   Under Design C, 049.cmv/nav = securities MV + cash. A BARE buy (amount −15000) leaves cash
--   −15000 → cmv = 20000 − 15000 = 5000, NOT the AC's 20000. So each investment account is
--   FUNDED first: a pure-cash deposit +15000 (security_id NULL, quantity 0) funds cash, then a
--   BUY of 100 shares (amount −15000, cost_basis 15000, quantity 100) deploys it → NET CASH 0 →
--   cmv = securities MV alone = 100 × eod_price 200 = 20000. Prices/dates use current_date so the
--   "(today, true)" headline path is exercised (deterministic — current_date, no wall-clock sleep).
--
-- ┌─ WHAT THIS BATTERY PROVES (each assertion guards a REAL violation) ────────────────────────┐
-- │ AC#1 (CORE — MV not cost, tenant A/a1): the investment account holding 100 shares @ eod_price │
-- │   200 with cost_basis 15000 contributes 20000 (MARKET VALUE) to NAV — NOT 15000 (cost).       │
-- │   cmv == qty × eod_price (independently recomputed) proves the value is sourced from the       │
-- │   current price, not the book. RED if the MV leg ever read cost_basis (cmv would be 15000).    │
-- │ AC#2 (THREE-SURFACE CONSISTENCY, tenant A): 049.cmv, fn_compute_nav(today,true), and           │
-- │   051.nav ALL agree at 20000; 049 → cmv 20000 / cost_basis 15000 / unrealized_gl 5000;         │
-- │   051 → nav 20000 & leaf cmv 20000. The three §2.1.x surfaces cannot diverge on MV.            │
-- │ ISO (two-tenant scoping, A/B): B calling any surface sees ZERO of A's/N's accounts; A sees     │
-- │   ZERO of B's/N's; B sees its OWN account (non-vacuous). Isolation itself is proven exhaustively │
-- │   at 051's battery (32/32) — this is the convention-consistent boundary re-assert, not the      │
-- │   focus. RED if any surface were SECURITY DEFINER / lost set search_path / lost RLS.            │
-- │ AC#4 (NEGATIVE — behavioral, STRONGER than a grep, tenant N/n1): an account IDENTICAL to a1     │
-- │   (same 100 shares, same eod_price 200, same funding) EXCEPT cost_basis 99999 → cmv and nav are │
-- │   BYTE-INVARIANT at 20000, while cost_basis moves 15000→99999 and unrealized_gl moves           │
-- │   5000→−79999. Proves cost basis CANNOT leak into ANY current-value / NAV path — the value is   │
-- │   invariant under the one input we varied. Non-vacuous: cost_basis DID change (99999 ≠ 15000)   │
-- │   and DID flow to the G/L column, so the fixture genuinely exercised the cost-basis input.      │
-- │ AC#3 (MACHINE-CHECK, depends on 052): obj_description of all four NAV-path read helpers matches  │
-- │   '%SELF-227%' — the MV-vs-cost audit-trace is documented AT the aggregation point. LOOSE like   │
-- │   (not exact text) per brief; migration 052 lands the comments (same-PR in CI).                  │
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22/RT-26/RT-27). This is a QA test over four
--   authenticated-tier INVOKER READ functions — no service_role grant, no credential, no admission
--   surface, no new table / no FK-shaped reference column (Decision-3 family UNCHANGED). SECURITY
--   DEFINER allowlist UNCHANGED at 4. 052 (the paired migration) is COMMENT-ONLY. This battery
--   introduces no catalogued instance; it is the pgTAP proof the §2.1.6 MV-not-cost invariant holds.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants _rls.tenant_a()/_b() + a fixed
--   literal for N; NO PII / NO real account numbers (SD-15) / NO real Plaid tokens (SD-03) / NO prod
--   data. The GLOBAL security carries users_id NULL (016/017 #7 — readable by any tenant's INVOKER).
--   All seeds PRIVILEGED (role=postgres; RLS+ACL bypassed) with users_id set EXPLICITLY (auth.uid()
--   is NULL under postgres); the fns are invoked ONLY under the authenticated tenant contexts under
--   test. All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated. Tenant UUIDs
--   + account ids resolve to psql LITERALS via \gset at role=postgres; every _rls.set_tenant is
--   called at role=postgres and each block restores role=postgres before the next. The AC#3
--   obj_description checks run at role=postgres (pg_catalog metadata). is/isnt/ok under authenticated
--   are proven safe by the green 019/035/049/050/051 batteries.
--
-- ⟦WIRE-VALIDATE⟧ authored + smoke-verified GREEN via a transient apply-of-052 + run inside a single
--   rolled-back txn against the 001→051 landed local stack (NON-destructive; no `supabase db reset` —
--   F/CTO local data intact). The authoritative gate is CI pg_prove directory-mode (db-tests.yml)
--   AFTER Backend's clean-apply of 052. RED-until-052-applied is EXPECTED for the AC#3 block on any
--   pre-052 stack (obj_description would lack SELF-227); AC#1/AC#2/AC#4/ISO are GREEN on the 001→051
--   stack alone. plan(25).
-- =====================================================================

begin;

-- shared cross-tenant verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(25);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset
-- N: the AC#4 negative-variant tenant (fixed literal, like the sibling 049 tf/th/tp tenants).
\set tn '00000000-0000-0000-0000-000000227001'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'tn');

-- ---------------------------------------------------------------------
-- GLOBAL security (users_id NULL → 016/017 #7 fence: readable by every tenant's INVOKER).
--   MV227: single eod_price 200 @ current_date — the CURRENT MARKET price. Cost basis (15000 or
--   99999) lives ONLY on the buy row; it must never surface in cmv/nav.
-- ---------------------------------------------------------------------
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'MV227', 'SELF-227 MV security') returning asset_id as sec \gset
insert into pfin.eod_price (asset_id, price_date, source, price) values
  (:sec, current_date, 'market_feed', 200.0000);   -- $200/share CURRENT market price

-- =====================================================================
-- TENANT A — a1: single INVESTMENT account, FUND-then-BUY, cost_basis 15000.
--   deposit +15000 (fund cash) ; BUY 100 MV227 amount -15000 cost_basis 15000 → net cash 0.
--   sec_mv = 100 × 200 = 20000 ; cash 0 ; sec_book (GL trade_position) = 15000.
--   049 → cmv 20000 / cost_basis 15000+0 = 15000 / unrealized_gl 20000−15000 = 5000.
--   fn_compute_nav(today,true) = 20000 (single active account) ; 051.nav = 20000 ; leaf cmv = 20000.
-- =====================================================================
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-inv-1', 'investment', 'household', 'taxable') returning account_id as a1 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor)
  values (:a1, current_date, 15000.0000, 0, null, null, 'standard', 'fund-a1');       -- FUND cash +15000
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor)
  values (:a1, current_date, -15000.0000, 100, :sec, 15000.0000, 'standard', 'buy-a1'); -- BUY 100 @ cost 15000

-- =====================================================================
-- TENANT B — cross-tenant victim/control. One depository account so B's OWN call is non-empty.
-- =====================================================================
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'b-dep-1', 'depository', 'household', 'taxable') returning account_id as b1 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:b1, 100.0000, 'USD', current_date, 'seed');

-- =====================================================================
-- TENANT N — the AC#4 NEGATIVE variant. n1 is IDENTICAL to a1 (same 100 shares of the SAME global
--   MV227 @ 200, same +15000 fund / −15000 buy amount) EXCEPT cost_basis on the buy = 99999.
--   The ONE varied input is cost_basis. Expect: cmv 20000 (INVARIANT) / nav 20000 (INVARIANT) ;
--   cost_basis 99999+0 = 99999 (VARIED) ; unrealized_gl 20000−99999 = −79999 (VARIED). Proves cost
--   basis flows to the G/L column ONLY, never to the current-value / NAV path.
-- =====================================================================
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tn', 'n-inv-1', 'investment', 'household', 'taxable') returning account_id as n1 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor)
  values (:n1, current_date, 15000.0000, 0, null, null, 'standard', 'fund-n1');        -- IDENTICAL fund
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor)
  values (:n1, current_date, -15000.0000, 100, :sec, 99999.0000, 'standard', 'buy-n1'); -- cost_basis VARIED → 99999

-- =====================================================================
-- AC#1 — CORE: investment cmv = MARKET VALUE (20000), NOT cost basis (15000). Tenant A.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (1) cmv(a1) = 20000 = 100 shares × eod_price 200 (MARKET VALUE contribution to NAV).
select is(
  (select current_market_value from pfin.fn_account_unrealized_gl(current_date) where account_id = :a1),
  20000.0000::numeric,
  '(1) AC#1 core: a1 (100 sh @ eod_price 200, cost_basis 15000) contributes current_market_value = 20000 (MARKET VALUE) to NAV');
-- (2) cmv(a1) ≠ 15000 — the value is NOT the cost basis. RED (=15000) if the MV leg read cost_basis.
select isnt(
  (select current_market_value from pfin.fn_account_unrealized_gl(current_date) where account_id = :a1),
  15000.0000::numeric,
  '(2) AC#1 core: a1 current_market_value ≠ 15000 (the cost basis) — market value, NOT cost basis, contributes to NAV');
-- (3) cmv(a1) == independently-recomputed Σ(qty × current eod_price) — value SOURCED from market price.
select is(
  (select current_market_value from pfin.fn_account_unrealized_gl(current_date) where account_id = :a1),
  (select coalesce(sum(h.quantity * ep.price), 0)
     from pfin.fn_holdings_as_of(current_date) h
     join lateral (select e.price from pfin.eod_price e
                   where e.asset_id = h.asset_id and e.price_date <= current_date
                   order by e.price_date desc limit 1) ep on true
     where h.account_id = :a1),
  '(3) AC#1 core: a1 current_market_value == Σ(holdings qty × current eod_price) recomputed independently — the value is sourced from the CURRENT MARKET price (cash is 0 here), never the book');

-- =====================================================================
-- AC#2 — THREE-SURFACE CONSISTENCY (049 / fn_compute_nav(today,true) / 051), all at 20000. Tenant A.
-- =====================================================================
-- (4) 049 cost_basis(a1) = 15000 (Design-C account-total book = securities book 15000 + cash 0).
select is(
  (select cost_basis from pfin.fn_account_unrealized_gl(current_date) where account_id = :a1),
  15000.0000::numeric,
  '(4) AC#2: 049 cost_basis(a1) = 15000 (securities carried book 15000 + cash 0 — Design-C account-total)');
-- (5) 049 unrealized_gl(a1) = 5000 (= market 20000 − book 15000).
select is(
  (select unrealized_gl from pfin.fn_account_unrealized_gl(current_date) where account_id = :a1),
  5000.0000::numeric,
  '(5) AC#2: 049 unrealized_gl(a1) = 5000 = market value 20000 − securities book 15000 (the pure securities G/L)');
-- (6) Design-C identity: unrealized_gl = cmv − cost_basis (the two branches share the cash term).
select is(
  (select unrealized_gl - (current_market_value - cost_basis)
     from pfin.fn_account_unrealized_gl(current_date) where account_id = :a1),
  0::numeric,
  '(6) AC#2: Design-C identity holds — 049 unrealized_gl(a1) = current_market_value − cost_basis (cash term cancels)');
-- (7) fn_compute_nav(today, true) = 20000 (the §2.1.1 headline surface).
select is(
  pfin.fn_compute_nav(current_date, true),
  20000.0000::numeric,
  '(7) AC#2: §2.1.1 headline fn_compute_nav(current_date, true) = 20000 (single active account = a1 market value)');
-- (8) 051.nav = 20000 (the §2.1.5 composition surface).
select is(
  (pfin.fn_nav_composition(current_date) ->> 'nav')::numeric,
  20000.0000::numeric,
  '(8) AC#2: §2.1.5 fn_nav_composition(current_date).nav = 20000 (composition foots to the market-value headline)');
-- (9) 051 leaf cmv(a1) = 20000 (the a1 leaf inside the composition tree carries market value).
select is(
  (select (acc->>'current_market_value')::numeric
     from jsonb_array_elements(pfin.fn_nav_composition(current_date) -> 'groups') g,
          jsonb_array_elements(g -> 'accounts') acc
     where (acc->>'account_id')::bigint = :a1),
  20000.0000::numeric,
  '(9) AC#2: 051 a1 leaf current_market_value = 20000 (the composition leaf uses market value, not cost basis)');
-- (10) 051 leaf unrealized_gl(a1) = 5000 (the leaf carries the same 049-derived G/L).
select is(
  (select (acc->>'unrealized_gl')::numeric
     from jsonb_array_elements(pfin.fn_nav_composition(current_date) -> 'groups') g,
          jsonb_array_elements(g -> 'accounts') acc
     where (acc->>'account_id')::bigint = :a1),
  5000.0000::numeric,
  '(10) AC#2: 051 a1 leaf unrealized_gl = 5000 (leaf inherits 049''s securities G/L)');
-- (11) SURFACES AGREE #1: 049.cmv(a1) == fn_compute_nav(today, true).
select is(
  (select current_market_value from pfin.fn_account_unrealized_gl(current_date) where account_id = :a1),
  pfin.fn_compute_nav(current_date, true),
  '(11) AC#2 three-surface: 049 current_market_value(a1) == fn_compute_nav(current_date, true) — §2.1.5 leaf agrees with §2.1.1 headline');
-- (12) SURFACES AGREE #2: fn_compute_nav(today, true) == 051.nav.
select is(
  pfin.fn_compute_nav(current_date, true),
  (pfin.fn_nav_composition(current_date) ->> 'nav')::numeric,
  '(12) AC#2 three-surface: fn_compute_nav(current_date, true) == fn_nav_composition(current_date).nav — §2.1.1 headline agrees with §2.1.5 composition');

-- (13) A sees NONE of B's or N's accounts (cross-tenant fail-closed under A).
select is(
  (select count(*)::int from pfin.fn_account_unrealized_gl(current_date) where account_id in (:b1, :n1)),
  0,
  '(13) ISO: under A, the fn output contains NONE of B''s or N''s accounts (INVOKER composes under A''s RLS)');
select set_config('role', 'postgres', true);

-- =====================================================================
-- ISO — two-tenant fail-closed + non-vacuous own-read. Tenant B.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);
-- (14) LOAD-BEARING: B sees ZERO of A's/N's accounts across ALL three surfaces (049 here).
select is(
  (select count(*)::int from pfin.fn_account_unrealized_gl(current_date) where account_id in (:a1, :n1)),
  0,
  '(14) ISO LOAD-BEARING: tenant B sees 0 of A''s/N''s accounts — RED (>0) if any surface were SECURITY DEFINER / lost set search_path / lost RLS (a1/n1 demonstrably exist, per 15)');
-- (15) non-vacuous: B sees its OWN account b1 → (14)'s 0 is a boundary denial, not a globally empty fn.
select is(
  (select count(*)::int from pfin.fn_account_unrealized_gl(current_date) where account_id = :b1),
  1,
  '(15) ISO non-vacuous: B sees its OWN account b1 (exactly 1 row) → (14)''s 0 is a cross-tenant BOUNDARY denial, not an empty function');
select set_config('role', 'postgres', true);

-- =====================================================================
-- AC#4 — NEGATIVE (behavioral): VARY cost_basis, hold shares + eod_price FIXED → cmv/nav INVARIANT.
--   Tenant N. n1 == a1 in every input EXCEPT cost_basis (15000 → 99999).
-- =====================================================================
select _rls.set_tenant(:'tn'::uuid);
-- (16) cmv(n1) = 20000 — INVARIANT under cost_basis (identical to a1's 20000 despite cost_basis 99999).
select is(
  (select current_market_value from pfin.fn_account_unrealized_gl(current_date) where account_id = :n1),
  20000.0000::numeric,
  '(16) AC#4 negative: n1 current_market_value = 20000 — INVARIANT under cost_basis (same as a1 despite cost_basis 99999 vs 15000); the current-value path cannot read cost basis');
-- (17) fn_compute_nav(today, true) under N = 20000 — NAV headline INVARIANT under cost_basis.
select is(
  pfin.fn_compute_nav(current_date, true),
  20000.0000::numeric,
  '(17) AC#4 negative: fn_compute_nav(current_date, true) under N = 20000 — the §2.1.1 NAV is INVARIANT under cost_basis');
-- (18) 051.nav under N = 20000 — composition NAV INVARIANT under cost_basis.
select is(
  (pfin.fn_nav_composition(current_date) ->> 'nav')::numeric,
  20000.0000::numeric,
  '(18) AC#4 negative: fn_nav_composition(current_date).nav under N = 20000 — the §2.1.5 composition NAV is INVARIANT under cost_basis');
-- (19) NON-VACUOUS: cost_basis(n1) = 99999 — the varied input genuinely reached the G/L column.
select is(
  (select cost_basis from pfin.fn_account_unrealized_gl(current_date) where account_id = :n1),
  99999.0000::numeric,
  '(19) AC#4 non-vacuous: n1 cost_basis = 99999 (99999 securities book + 0 cash) — the varied cost_basis input is REAL and reaches 049''s cost_basis column');
-- (20) cost_basis(n1) ≠ 15000 (a1's) — the fixture genuinely VARIED cost_basis between the two accounts.
select isnt(
  (select cost_basis from pfin.fn_account_unrealized_gl(current_date) where account_id = :n1),
  15000.0000::numeric,
  '(20) AC#4 non-vacuous: n1 cost_basis (99999) ≠ a1 cost_basis (15000) — cost_basis DID change, yet (16)-(18) cmv/nav did NOT: the invariance is real, not a coincidence of equal inputs');
-- (21) unrealized_gl(n1) = -79999 (= market 20000 − book 99999) — cost_basis flows to G/L, NOT to value.
select is(
  (select unrealized_gl from pfin.fn_account_unrealized_gl(current_date) where account_id = :n1),
  -79999.0000::numeric,
  '(21) AC#4: n1 unrealized_gl = -79999 = market 20000 − book 99999 — cost basis flows to the unrealized_gl (G/L) column ONLY, never to current_market_value / nav');
select set_config('role', 'postgres', true);

-- =====================================================================
-- AC#3 — MACHINE-CHECK (obj_description audit-trace; DEPENDS ON migration 052; run at role=postgres).
--   LOOSE like '%SELF-227%' per brief (052 lands the exact text same-PR). RED-until-052 expected.
-- =====================================================================
-- (22) fn_compute_nav(date) — 1-arg wrapper — carries the SELF-227 audit-trace.
select ok(
  obj_description('pfin.fn_compute_nav(date)'::regprocedure, 'pg_proc') like '%SELF-227%',
  '(22) AC#3: obj_description(fn_compute_nav(date)) matches ''%SELF-227%'' — MV-vs-cost audit-trace documented at the aggregation point (052)');
-- (23) fn_compute_nav(date, boolean) — 2-arg impl.
select ok(
  obj_description('pfin.fn_compute_nav(date, boolean)'::regprocedure, 'pg_proc') like '%SELF-227%',
  '(23) AC#3: obj_description(fn_compute_nav(date, boolean)) matches ''%SELF-227%'' (052)');
-- (24) fn_account_unrealized_gl(date) — 049.
select ok(
  obj_description('pfin.fn_account_unrealized_gl(date)'::regprocedure, 'pg_proc') like '%SELF-227%',
  '(24) AC#3: obj_description(fn_account_unrealized_gl(date)) matches ''%SELF-227%'' (052)');
-- (25) fn_nav_composition(date) — 051.
select ok(
  obj_description('pfin.fn_nav_composition(date)'::regprocedure, 'pg_proc') like '%SELF-227%',
  '(25) AC#3: obj_description(fn_nav_composition(date)) matches ''%SELF-227%'' (052)');

select * from finish();
rollback;

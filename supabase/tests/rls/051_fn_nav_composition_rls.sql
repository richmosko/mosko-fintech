-- =====================================================================
-- Per-Wave battery — pfin.fn_nav_composition(p_as_of date) — §2.1.5 NAV-composition
--   aggregation (SELF-225 / 051; V1.1 "Net worth full"; PRD §2.1.5; Lock 11 SECURITY INVOKER
--   read-composition). Composes on 049 (fn_account_unrealized_gl) + pfin.account; foots EXACT
--   to fn_compute_nav(as_of, true) (050 / ADR-038/039). Paired with the migration in the SAME
--   PR (verify-paired-artifacts discipline — a migration merging without its battery = vacuous CI).
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/051_fn_nav_composition.sql
--   pfin.fn_nav_composition(p_as_of date default current_date) RETURNS jsonb — SECURITY INVOKER,
--     STABLE, set search_path=''. Returns the §2.1.5 composition tree:
--       { "groups":[ {"category", "accounts":[{"account_id","account_name",
--                     "current_market_value","unrealized_gl"}], "subtotal"}, … ],
--         "buildups":{ "total_non_re","gross_total","debt","realized_tax_liab",
--                      "unrealized_tax_liab" },
--         "nav": gross_total − debt − realized_tax_liab − unrealized_tax_liab }
--   groups[] in CANONICAL category order (depository/investment/retirement/crypto/manual_other →
--   real_estate → liability); EMPTY categories omitted; accounts[] by account_id. DEBT-SIGN D-1:
--   liability leaves + subtotal carry 049's natural NEGATIVE sign; buildups.debt = −(liability
--   subtotal) = positive magnitude. FOOT-TO-NAV EXACT (ADR-038/039): nav == fn_compute_nav(as_of,
--   TRUE) by construction (single-substrate natural summation of the same active-account leaves).
--
-- Prereqs exercised (on the 001→051 reset stack): 003 (pfin.account direct-owner RLS +
--   account_type CHECK 7-value + is_active + fn_grant_creator_access DEFINER trigger seeding
--   account_users rd/wr per INSERT); 004/006 (account_trans immutable + rd/wr RLS); 016/017
--   (pfin.asset global-OR-owned + security_id/quantity/cost_basis); 019 (eod_price D-first LOCF +
--   fn_holdings_as_of + account_balance_checkpoint roll-forward); 035/037 (fn_gl_entries
--   trade_position basis); 049 (fn_account_unrealized_gl — the leaf substrate 051 composes on);
--   050 (fn_compute_nav(as_of, p_active_only) — the EXACT foot anchor). auth.uid() reads
--   request.jwt.claims (PG 17 stack).
--
-- ┌─ WHAT THIS BATTERY PROVES (each assertion guards a REAL violation) ────────────────────────┐
-- │ (I) TWO-TENANT ISOLATION — the load-bearing test. Under A, the tree contains EXACTLY A's 7   │
-- │     active accounts and NONE of B's; under B, ZERO of A's accounts appear. Non-vacuous: B     │
-- │     sees its OWN account (b1), and A's NAV>0 — so the cross-tenant 0 is a BOUNDARY denial,    │
-- │     not an empty fn. RED if the fn were DEFINER / lost set search_path / lost RLS.            │
-- │ (C) CATEGORY GROUPING (PRD §2.1.5 / AC#2): canonical group order; asset-half account keyed    │
-- │     to its type group; real_estate its OWN group; liability its OWN group.                     │
-- │ (S) SUBTOTAL / BUILDUP MATH: per-category subtotals; total_non_re = Σ(asset-half − RE − liab);│
-- │     gross_total = total_non_re + real_estate; nav = gross_total − debt − realized − unrealized.│
-- │ (F) FOOT-TO-NAV EXACT: nav == fn_compute_nav(as_of, TRUE) EXACTLY (the §2.1.1==§2.1.5 AC).    │
-- │     Non-vacuous: nav ≠ fn_compute_nav(as_of, FALSE) — the inactive a7's value lives only in   │
-- │     the all-accounts figure, so the foot is provably to the ACTIVE scope.                      │
-- │ (D) DEBT SIGN D-1: liability leaf + subtotal carry natural NEGATIVE sign; buildups.debt =     │
-- │     positive magnitude = −(liability subtotal).                                                │
-- │ (A) is_active INHERITANCE (via 049): the value-bearing INACTIVE a7 appears in NO group AND is  │
-- │     absent from the buildups (depository subtotal excludes it) — the filter is inherited.      │
-- │ (T) TAX PLACEHOLDERS (Option A V1.1 / AC#5): realized_tax_liab == 0 AND unrealized_tax_liab   │
-- │     == 0.                                                                                       │
-- │ (E) EMPTY-CATEGORY OMISSION (A4): a category with 0 active accounts (crypto) does NOT appear   │
-- │     in groups[], yet buildups still compute over the FULL active set (nav foots exact).        │
-- │ (G) UNPRICED/EDGE: an unpriced holding contributes 0 (cash only), never NaN/NULL; nav IS NOT   │
-- │     NULL.                                                                                       │
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22/RT-26/RT-27; 051 is a single
--   authenticated-tier INVOKER READ function — no service_role grant, no credential, no admission
--   surface). Decision-3 family UNCHANGED (051 authors NO table / NO FK-shaped reference column —
--   it READS existing FKs via 049 + the account join). SECURITY DEFINER allowlist UNCHANGED at 4
--   (this is INVOKER; authored DEFINER fns stay 3). This battery introduces no catalogued instance;
--   it is the pgTAP proof the helper fails closed cross-tenant AND composes the §2.1.5 tree correctly.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants _rls.tenant_a()/_b(); NO PII / NO
--   real account numbers (SD-15) / NO real Plaid tokens (SD-03) / NO prod data. GLOBAL securities
--   carry users_id NULL (016/017 #7 — readable by any tenant's INVOKER). All seeds PRIVILEGED
--   (role=postgres; RLS+ACL bypassed) with users_id set EXPLICITLY (auth.uid() is NULL under
--   postgres); the fn is invoked ONLY under the authenticated tenant contexts under test. All in a
--   rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated. Tenant UUIDs
--   + account ids resolve to psql LITERALS via \gset at role=postgres; every _rls.set_tenant is
--   called at role=postgres and each block restores role=postgres before the next. The fn / pgTAP
--   is/ok/cmp_ok under authenticated is proven safe by the green 019/035/049/050 batteries.
--
-- ⟦WIRE-VALIDATE⟧ authored + smoke-verified GREEN via a transient apply+rollback of 051 against the
--   001→050 landed local stack (NON-destructive; no `supabase db reset` — F/CTO local data intact).
--   The authoritative gate is CI pg_prove directory-mode (db-tests.yml) AFTER Backend's clean-apply
--   of 051. RED-until-051-applied is expected on any pre-051 stack (the function would not exist).
--   plan(32).
-- =====================================================================

begin;

-- shared cross-tenant verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(32);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

insert into auth.users (id) values (:'ta'), (:'tb');

-- ---------------------------------------------------------------------
-- GLOBAL securities (users_id NULL → 016/017 #7 fence: readable by every tenant's INVOKER).
--   SECA: single price 150 @ 2026-06-01 (the priced security).
--   SECU: NO eod_price (the unpriced-asset SUM-NULL fence).
-- ---------------------------------------------------------------------
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'CMSECA', 'Comp Sec A') returning asset_id as seca \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'CMSECU', 'Comp Sec U (unpriced)') returning asset_id as secu \gset
insert into pfin.eod_price (asset_id, price_date, source, price) values
  (:seca, '2026-06-01', 'market_feed', 150.0000);
-- CMSECU: intentionally NO eod_price row.

-- =====================================================================
-- TENANT A — multi-category portfolio spanning the §2.1.5 tree.
--   a1 investment : cp 3000; BUY 10 CMSECA cb 1000 amt -1000 → sec 1500 + cash 2000 = cmv 3500.
--   a8 investment : cp  300; BUY  5 CMSECU cb  500 amt    0  → sec 0 (unpriced) + cash 300 = cmv 300.
--   a2 depository : cp 5000 → cmv 5000.
--   a3 retirement : cp 2000 (no holdings) → cmv 2000.
--   a6 manual_other: cp 1000 → cmv 1000.
--   a4 real_estate: cp 400000 → cmv 400000.
--   a5 liability  : cp -2000 → cmv -2000 (R-7 natural negative).
--   a7 depository INACTIVE + value-bearing 9999 → MUST be excluded (is_active inheritance via 049).
--   NO crypto account → the empty-category omission probe.
--
--   Category subtotals: depository 5000 · investment 3800 (3500+300) · retirement 2000 ·
--     manual_other 1000 · real_estate 400000 · liability -2000.  (crypto omitted.)
--   Buildups: total_non_re = 5000+3800+2000+1000 = 11800 ; gross_total = 11800+400000 = 411800 ;
--     debt = −(−2000) = 2000 ; realized/unrealized_tax_liab = 0.
--   NAV = 411800 − 2000 − 0 − 0 = 409800  ==  fn_compute_nav(2026-06-30, TRUE) (active-scoped).
--   fn_compute_nav(2026-06-30, FALSE) = 409800 + 9999 (inactive a7) = 419799  →  nav ≠ FALSE.
-- =====================================================================
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-inv-1', 'investment', 'household', 'taxable') returning account_id as a1 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a1, 3000.0000, 'USD', '2026-06-01', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor)
  values (:a1, '2026-06-05', -1000.0000, 10, :seca, 1000.0000, 'standard', 'buy-a1');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-inv-unpriced-8', 'investment', 'household', 'taxable') returning account_id as a8 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a8, 300.0000, 'USD', '2026-06-01', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor)
  values (:a8, '2026-06-05', 0.0000, 5, :secu, 500.0000, 'standard', 'buy-a8');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-dep-2', 'depository', 'household', 'taxable') returning account_id as a2 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a2, 5000.0000, 'USD', '2026-06-01', 'seed');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-ret-3', 'retirement', 'household', 'tax_deferred') returning account_id as a3 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a3, 2000.0000, 'USD', '2026-06-01', 'seed');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-manual-6', 'manual_other', 'household', 'taxable') returning account_id as a6 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a6, 1000.0000, 'USD', '2026-06-01', 'seed');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-re-4', 'real_estate', 'household', 'taxable') returning account_id as a4 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a4, 400000.0000, 'USD', '2026-06-01', 'seed');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-liab-5', 'liability', 'household', 'taxable') returning account_id as a5 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a5, -2000.0000, 'USD', '2026-06-01', 'seed');

-- a7: CLOSED as of 2026-06-30 (was `is_active=false` + a live 9999; see 049's note — that
--   state is unconstructible under ADR-042). Seeded through the real gate: funded, zeroed, closed.
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-dep-closed-7', 'depository', 'household', 'taxable') returning account_id as a7 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a7, 9999.0000, 'USD', '2026-06-01', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, vendor)
  values (:a7, '2026-06-30', -9999.0000, 0, 'wind-down-a7');
-- The seed block runs at postgres with no tenant, so auth.uid() is NULL and 057's
-- writer refuses rather than letting absence become a value. Declare the writer, as
-- its own raise instructs. 'system:remediation' is the ONLY system actor 057 admits
-- (enumerated, not an open pattern, so a new system identity fails the CHECK).
select set_config('pfin.actor', 'system:remediation', true);
select set_config('pfin.reason_code', 'no_longer_used', true);
update pfin.account set closed_at = '2026-06-30'::timestamptz where account_id = :a7;

-- =====================================================================
-- TENANT B — the cross-tenant victim/control. One investment account so B's OWN call is non-empty.
-- =====================================================================
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'b-inv-1', 'investment', 'household', 'taxable') returning account_id as b1 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:b1, 100.0000, 'USD', '2026-06-01', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor)
  values (:b1, '2026-06-05', -50.0000, 1, :seca, 50.0000, 'standard', 'buy-b1');

-- =====================================================================
-- TENANT A ASSERTIONS (blocks I/C/S/F/D/A/T/E/G run under A's RLS context).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- ---- I: TWO-TENANT ISOLATION (load-bearing) --------------------------
-- (I1) A's tree contains EXACTLY 7 leaves = A's 7 active accounts (inactive a7 excluded).
select is(
  (select count(*)::int
     from jsonb_array_elements(pfin.fn_nav_composition('2026-06-30'::date) -> 'groups') g,
          jsonb_array_elements(g -> 'accounts') a),
  7,
  '(I1) A''s composition tree carries EXACTLY 7 leaves = A''s 7 ACTIVE accounts (a1,a2,a3,a4,a5,a6,a8); the value-bearing INACTIVE a7 is excluded');
-- (I2) A's leaf account-id set = EXACTLY {a1,a2,a3,a4,a5,a6,a8} (identity, not just count).
select is(
  (select array_agg((a->>'account_id')::bigint order by (a->>'account_id')::bigint)
     from jsonb_array_elements(pfin.fn_nav_composition('2026-06-30'::date) -> 'groups') g,
          jsonb_array_elements(g -> 'accounts') a),
  (select array_agg(x order by x) from (values (:a1::bigint),(:a2),(:a3),(:a4),(:a5),(:a6),(:a8)) v(x)),
  '(I2) owner identity set: A''s leaves are EXACTLY {a1,a2,a3,a4,a5,a6,a8} — every active account, only active accounts');
-- (I3) cross-tenant: B's account (b1) is NOT anywhere in A's tree.
select ok(
  not exists (
    select 1 from jsonb_array_elements(pfin.fn_nav_composition('2026-06-30'::date) -> 'groups') g,
                  jsonb_array_elements(g -> 'accounts') a
    where (a->>'account_id')::bigint = :b1),
  '(I3) cross-tenant read fails closed: A''s tree contains NONE of B''s accounts (b1) — INVOKER composes under A''s RLS');
-- (I6) non-vacuous companion: A's NAV > 0 → the DB holds value; B''s absence (I4) is a boundary denial.
select cmp_ok(
  (pfin.fn_nav_composition('2026-06-30'::date) ->> 'nav')::numeric,
  '>', 0::numeric,
  '(I6) non-vacuous: under A, nav > 0 — the DB demonstrably holds value-bearing accounts, so B''s cross-tenant 0 (I4) is a BOUNDARY denial, not an empty DB');

-- ---- C: CATEGORY GROUPING (PRD §2.1.5 / AC#2) ------------------------
-- (C1) groups[] in CANONICAL order, empties omitted (crypto absent) — proves grouping + ordering.
select is(
  (select array_agg(elem->>'category' order by ord)
     from jsonb_array_elements(pfin.fn_nav_composition('2026-06-30'::date) -> 'groups')
          with ordinality as t(elem, ord)),
  array['depository','investment','retirement','manual_other','real_estate','liability']::text[],
  '(C1) groups[] in CANONICAL category order (depository,investment,retirement,manual_other,real_estate,liability); crypto omitted (no active crypto account)');
-- (C2) asset-half: a1 is grouped under its TYPE (investment), part of the asset half.
select is(
  (select g->>'category' from jsonb_array_elements(pfin.fn_nav_composition('2026-06-30'::date) -> 'groups') g,
          jsonb_array_elements(g -> 'accounts') a where (a->>'account_id')::bigint = :a1),
  'investment',
  '(C2) asset-half grouping: investment account a1 lands under the ''investment'' group (asset half keyed by account_type)');
-- (C3) real_estate is its OWN group (a4 not folded into the asset half).
select is(
  (select g->>'category' from jsonb_array_elements(pfin.fn_nav_composition('2026-06-30'::date) -> 'groups') g,
          jsonb_array_elements(g -> 'accounts') a where (a->>'account_id')::bigint = :a4),
  'real_estate',
  '(C3) real_estate is its OWN group: a4 lands under ''real_estate'', separate from the asset half (§2.1.5)');
-- (C4) liability is its OWN group (a5).
select is(
  (select g->>'category' from jsonb_array_elements(pfin.fn_nav_composition('2026-06-30'::date) -> 'groups') g,
          jsonb_array_elements(g -> 'accounts') a where (a->>'account_id')::bigint = :a5),
  'liability',
  '(C4) liability is its OWN group: a5 lands under ''liability'', separate from the asset half (§2.1.5)');

-- ---- S: SUBTOTAL / BUILDUP MATH -------------------------------------
-- (S1) depository subtotal = 5000 (a2 only; a7 inactive excluded — see also A2).
select is(
  (select (g->>'subtotal')::numeric from jsonb_array_elements(pfin.fn_nav_composition('2026-06-30'::date) -> 'groups') g
     where g->>'category' = 'depository'),
  5000.0000::numeric,
  '(S1) depository subtotal = 5000 (a2''s roll-forward balance; the inactive a7''s 9999 is NOT included)');
-- (S2) investment subtotal = 3800 (a1 3500 + a8 300).
select is(
  (select (g->>'subtotal')::numeric from jsonb_array_elements(pfin.fn_nav_composition('2026-06-30'::date) -> 'groups') g
     where g->>'category' = 'investment'),
  3800.0000::numeric,
  '(S2) investment subtotal = 3800 = a1 (1500 sec + 2000 cash) + a8 (0 unpriced + 300 cash) — Σ of leaf current_market_value');
-- (S3) real_estate subtotal = 400000.
select is(
  (select (g->>'subtotal')::numeric from jsonb_array_elements(pfin.fn_nav_composition('2026-06-30'::date) -> 'groups') g
     where g->>'category' = 'real_estate'),
  400000.0000::numeric,
  '(S3) real_estate subtotal = 400000 (a4)');
-- (S4) total_non_re = 11800 = Σ asset-half excl real_estate & liability.
select is(
  (pfin.fn_nav_composition('2026-06-30'::date) -> 'buildups' ->> 'total_non_re')::numeric,
  11800.0000::numeric,
  '(S4) buildups.total_non_re = 11800 = depository 5000 + investment 3800 + retirement 2000 + manual_other 1000 (excludes real_estate AND liability)');
-- (S5) gross_total = total_non_re + real_estate = 411800.
select is(
  (pfin.fn_nav_composition('2026-06-30'::date) -> 'buildups' ->> 'gross_total')::numeric,
  411800.0000::numeric,
  '(S5) buildups.gross_total = 411800 = total_non_re 11800 + real_estate 400000');
-- (S6) nav = gross_total − debt − realized − unrealized (internal consistency from the RETURNED buildups).
select is(
  (pfin.fn_nav_composition('2026-06-30'::date) ->> 'nav')::numeric,
  (
    (pfin.fn_nav_composition('2026-06-30'::date) -> 'buildups' ->> 'gross_total')::numeric
    - (pfin.fn_nav_composition('2026-06-30'::date) -> 'buildups' ->> 'debt')::numeric
    - (pfin.fn_nav_composition('2026-06-30'::date) -> 'buildups' ->> 'realized_tax_liab')::numeric
    - (pfin.fn_nav_composition('2026-06-30'::date) -> 'buildups' ->> 'unrealized_tax_liab')::numeric
  ),
  '(S6) nav internal consistency: nav = gross_total − debt − realized_tax_liab − unrealized_tax_liab, computed from the RETURNED buildups (RED if the assemble step diverged from the documented formula)');
-- (S7) concrete nav = 409800.
select is(
  (pfin.fn_nav_composition('2026-06-30'::date) ->> 'nav')::numeric,
  409800.0000::numeric,
  '(S7) nav = 409800 = gross_total 411800 − debt 2000 (concrete end-to-end composition)');

-- ---- F: FOOT-TO-NAV EXACT (§2.1.1 == §2.1.5; the ADR-038/039 invariant) ----
-- (F1) nav == fn_compute_nav(as_of, TRUE) EXACTLY (same tenant / same as_of).
select is(
  (pfin.fn_nav_composition('2026-06-30'::date) ->> 'nav')::numeric,
  pfin.fn_compute_nav('2026-06-30'::date, true),
  '(F1) FOOT-TO-NAV EXACT: nav == fn_compute_nav(2026-06-30, TRUE) — the §2.1.5 composition foots to the §2.1.1 active-scoped headline by construction (single-substrate natural summation)');
-- (F2) non-vacuous: nav ≠ fn_compute_nav(as_of, FALSE) — a7''s 9999 lives only in the all-accounts figure.
select isnt(
  (pfin.fn_nav_composition('2026-06-30'::date) ->> 'nav')::numeric,
  pfin.fn_compute_nav('2026-06-30'::date, false),
  '(F2) foot is to the ACTIVE scope: nav (409800) ≠ fn_compute_nav(2026-06-30, FALSE) (419799 — includes the inactive a7''s 9999). Confirms F1 is an active-scoped foot, not a coincidence');

-- ---- D: DEBT SIGN D-1 ------------------------------------------------
-- (D1) liability leaf a5 current_market_value carries 049's natural NEGATIVE sign.
select is(
  (select (a->>'current_market_value')::numeric
     from jsonb_array_elements(pfin.fn_nav_composition('2026-06-30'::date) -> 'groups') g,
          jsonb_array_elements(g -> 'accounts') a where (a->>'account_id')::bigint = :a5),
  -2000.0000::numeric,
  '(D1) debt sign D-1: liability leaf a5 current_market_value = -2000 (049''s natural negative sign preserved in the leaf — no abs/flip)');
-- (D2) liability group subtotal carries the natural NEGATIVE sign.
select is(
  (select (g->>'subtotal')::numeric from jsonb_array_elements(pfin.fn_nav_composition('2026-06-30'::date) -> 'groups') g
     where g->>'category' = 'liability'),
  -2000.0000::numeric,
  '(D2) debt sign D-1: liability group subtotal = -2000 (natural negative → the tree sums naturally to NAV)');
-- (D3) buildups.debt = positive magnitude 2000.
select is(
  (pfin.fn_nav_composition('2026-06-30'::date) -> 'buildups' ->> 'debt')::numeric,
  2000.0000::numeric,
  '(D3) debt sign D-1: buildups.debt = 2000 = POSITIVE magnitude (so AC#4 nav = gross_total − debt reads literally)');
-- (D4) identity: debt == −(liability subtotal).
select is(
  (pfin.fn_nav_composition('2026-06-30'::date) -> 'buildups' ->> 'debt')::numeric,
  -(select (g->>'subtotal')::numeric from jsonb_array_elements(pfin.fn_nav_composition('2026-06-30'::date) -> 'groups') g
      where g->>'category' = 'liability'),
  '(D4) debt sign D-1 identity: buildups.debt == −(liability subtotal) — the positive magnitude is exactly the negated natural-signed subtotal');

-- ---- A: is_active INHERITANCE (via 049) -----------------------------
-- (A1) the value-bearing INACTIVE a7 appears in NO group leaf (non-vacuous: a7 exists + carries 9999).
select ok(
  not exists (
    select 1 from jsonb_array_elements(pfin.fn_nav_composition('2026-06-30'::date) -> 'groups') g,
                  jsonb_array_elements(g -> 'accounts') a
    where (a->>'account_id')::bigint = :a7),
  '(A1) is_active inheritance: a7 EXISTS + carries 9999 cash, yet NEVER appears in any group — 051 inherits 049''s is_active filter (it never touches an account 049 excluded). RED if inactive leaked in');
-- (A2) a7 is absent from the BUILDUPS too: depository subtotal (5000) excludes a7''s 9999 (would be 14999).
select is(
  (select (g->>'subtotal')::numeric from jsonb_array_elements(pfin.fn_nav_composition('2026-06-30'::date) -> 'groups') g
     where g->>'category' = 'depository'),
  5000.0000::numeric,
  '(A2) is_active inheritance into buildups: depository subtotal = 5000 (a2 only), NOT 14999 (a2 + inactive a7) — the inactive account affects neither groups nor the foot');

-- ---- T: TAX PLACEHOLDERS (Option A V1.1 / AC#5) --------------------
-- (T1) realized_tax_liab == 0::numeric.
select is(
  (pfin.fn_nav_composition('2026-06-30'::date) -> 'buildups' ->> 'realized_tax_liab')::numeric,
  0::numeric,
  '(T1) tax placeholder: buildups.realized_tax_liab == 0 (Option A V1.1; V1.4 ramp)');
-- (T2) unrealized_tax_liab == 0::numeric.
select is(
  (pfin.fn_nav_composition('2026-06-30'::date) -> 'buildups' ->> 'unrealized_tax_liab')::numeric,
  0::numeric,
  '(T2) tax placeholder: buildups.unrealized_tax_liab == 0 (Option A V1.1; V1.4 ramp)');

-- ---- E: EMPTY-CATEGORY OMISSION (A4) -------------------------------
-- (E1) no 'crypto' group is emitted (A has zero active crypto accounts).
select ok(
  not exists (
    select 1 from jsonb_array_elements(pfin.fn_nav_composition('2026-06-30'::date) -> 'groups') g
    where g->>'category' = 'crypto'),
  '(E1) empty-category omission: no ''crypto'' group is emitted (A holds zero active crypto accounts) — a group appears only if it has ≥1 active account');
-- (E2) exactly 6 groups (< 7 canonical categories) yet the foot is EXACT — buildups over the FULL active set.
select is(
  (select jsonb_array_length(pfin.fn_nav_composition('2026-06-30'::date) -> 'groups')),
  6,
  '(E2) exactly 6 groups emitted (of 7 canonical — crypto omitted); yet nav foots EXACT (F1), proving buildups compute over the FULL active set regardless of which groups are emitted');

-- ---- G: UNPRICED / EDGE -------------------------------------------
-- (G1) unpriced holding (a8 holds CMSECU, no price) → current_market_value = cash only (300), 0 not NaN.
select is(
  (select (a->>'current_market_value')::numeric
     from jsonb_array_elements(pfin.fn_nav_composition('2026-06-30'::date) -> 'groups') g,
          jsonb_array_elements(g -> 'accounts') a where (a->>'account_id')::bigint = :a8),
  300.0000::numeric,
  '(G1) unpriced fence: a8 holds 5 CMSECU (NO eod_price) → the security term drops to 0 → current_market_value = cash 300 ("needs valuation", never NaN). RED if the unpriced holding poisoned the leaf');
-- (G2) a8 leaf current_market_value IS NOT NULL (the unpriced asset never yields NULL/NaN).
select ok(
  (select (a->>'current_market_value') is not null
     from jsonb_array_elements(pfin.fn_nav_composition('2026-06-30'::date) -> 'groups') g,
          jsonb_array_elements(g -> 'accounts') a where (a->>'account_id')::bigint = :a8),
  '(G2) unpriced fence: a8''s current_market_value IS NOT NULL — the 049 COALESCE fence carries through composition (a NULL would poison the subtotal + nav)');
-- (G3) top-level nav IS NOT NULL despite an unpriced holding in the portfolio.
select ok(
  (pfin.fn_nav_composition('2026-06-30'::date) ->> 'nav') is not null,
  '(G3) unpriced fence: top-level nav IS NOT NULL with an unpriced holding present — the composition never NULLs out (fails to a number, not to NULL)');

select set_config('role', 'postgres', true);

-- =====================================================================
-- TENANT B ASSERTIONS — the load-bearing cross-tenant fail-closed + non-vacuous own-read.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);
-- (I4) LOAD-BEARING: B calling the fn sees ZERO of A''s accounts.
select is(
  (select count(*)::int
     from jsonb_array_elements(pfin.fn_nav_composition('2026-06-30'::date) -> 'groups') g,
          jsonb_array_elements(g -> 'accounts') a
     where (a->>'account_id')::bigint in (:a1,:a2,:a3,:a4,:a5,:a6,:a8,:a7)),
  0,
  '(I4) LOAD-BEARING cross-tenant fail-closed: tenant B''s tree contains 0 of A''s accounts — RED (>0) if the fn were SECURITY DEFINER / lost set search_path / lost RLS composition (A''s accounts demonstrably exist, per I6)');
-- (I5) non-vacuous: B sees its OWN account b1 (exactly 1 leaf) → I4 is a boundary denial, not an empty fn.
select is(
  (select count(*)::int
     from jsonb_array_elements(pfin.fn_nav_composition('2026-06-30'::date) -> 'groups') g,
          jsonb_array_elements(g -> 'accounts') a
     where (a->>'account_id')::bigint = :b1),
  1,
  '(I5) non-vacuous: B sees its OWN account b1 (exactly 1 leaf) → (I4)''s 0 is a cross-tenant BOUNDARY denial, not a globally empty function');
select set_config('role', 'postgres', true);

select * from finish();
rollback;

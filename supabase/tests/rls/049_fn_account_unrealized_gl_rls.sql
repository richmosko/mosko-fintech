-- =====================================================================
-- Per-Wave battery — pfin.fn_account_unrealized_gl(p_as_of date) — per-account unrealized
--   G/L aggregation primitive (SELF-224 / 049; V1.1 "Net worth full"; PRD §2.1.5.a; DESIGN C
--   account-total symmetric, ADR-038; Lock 11 SECURITY INVOKER read-composition — clones the
--   fn_compute_nav / fn_gl_entries posture). Paired with the migration in the SAME PR
--   (verify-paired-artifacts discipline — a migration merging without its battery = vacuous CI).
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/049_fn_account_unrealized_gl.sql
--   pfin.fn_account_unrealized_gl(p_as_of date default current_date)
--     RETURNS TABLE(account_id bigint, current_market_value numeric, cost_basis numeric,
--                   unrealized_gl numeric) — SECURITY INVOKER, STABLE, set search_path=''.
--   One row per NON-INACTIVE (account.is_active) account VISIBLE to the caller. DESIGN C:
--     current_market_value (ALL types) = securities MV (fn_holdings_as_of qty × eod_price[D-first
--       LOCF] × fx) + roll-forward cash (account_balance_checkpoint anchor + Σ account_trans.amount
--       strictly-after) × fx  → the account's fn_compute_nav contribution.
--     INVESTMENT-class (account_type ∈ investment/retirement/crypto, 003 CHECK):
--       cost_basis    = securities carried book (Σ fn_gl_entries trade_position × fx) + the SAME
--                       cash term as current_market_value (identical expression → cancels).
--       unrealized_gl = current_market_value − cost_basis = securities MV − securities book
--                       (pure securities G/L; the cash term cancels EXACTLY).
--     NON-INVESTMENT (depository/manual_other/real_estate/liability): cost_basis = unrealized_gl
--       = NULL (NOT 0 — concept-does-not-apply discriminator).
--
-- Prereqs exercised (on the 001→049 reset stack): 003 (pfin.account direct-owner RLS +
--   account_type/is_active/currency + the fn_grant_creator_access DEFINER trigger, which seeds
--   account_users rd=t/wr=t on each INSERT so each tenant's INVOKER read reaches its OWN
--   account_trans via the Lock-3 rd_access-JOIN); 004/006 (account_trans immutable + rd/wr RLS);
--   016/017 (pfin.asset global-OR-owned + security_id/quantity/cost_basis); 019 (eod_price +
--   fn_holdings_as_of + fn_compute_nav — REUSED verbatim, not reimplemented); 035/037
--   (fn_gl_entries — the trade_position basis source). auth.uid()/auth.jwt() read
--   request.jwt.claims (PG 17 stack).
--
-- ┌─ WHAT THIS BATTERY PROVES (each assertion guards a REAL violation) ────────────────────────┐
-- │ (T1) CROSS-TENANT FAIL-CLOSED + owner-only-active: B calling the fn sees ZERO of A's         │
-- │      accounts; A sees ZERO of B's; A sees EXACTLY its 4 ACTIVE accounts (the value-bearing    │
-- │      INACTIVE a5 is EXCLUDED). INVERSION: RED if the fn were DEFINER / lost set search_path /  │
-- │      lost RLS (B would see A's accounts) OR if the is_active filter were dropped (a5 appears).  │
-- │      Non-vacuous: B owns a REAL account (b1) → A's 0 is a boundary denial, not an empty fn;    │
-- │      a5 is REAL + value-bearing (9999) → its exclusion is a real filter, not an empty set.     │
-- │ (T2) INVESTMENT arithmetic (a1): cmv = sec_mv+cash; cost_basis = sec_book+cash;               │
-- │      unrealized_gl = sec_mv−sec_book AND = cmv−cost_basis (the Design-C identity).             │
-- │ (T3) FOOT-TO-NAV (Design-C headline, tenant F): Σ current_market_value = fn_compute_nav at    │
-- │      the SAME as_of. Proven on an ALL-ACTIVE tenant (see the is_active/NAV NOTE below).        │
-- │ (T4) NON-INVESTMENT (a2 depository): cmv = roll-forward balance; cost_basis IS NULL;          │
-- │      unrealized_gl IS NULL.                                                                    │
-- │ (T5) NULL-vs-ZERO discrimination: a zero-holdings INVESTMENT (a3) → (cash, cash, 0) — concept │
-- │      APPLIES, G/L is 0 and NOT NULL; a non-investment → NULL. Asserts NULL ≠ 0.                │
-- │ (T6) CASH-CANCELLATION (a1 with a cash sweep): unrealized_gl EXCLUDES the cash (= pure         │
-- │      securities G/L, recomputed independently from fn_holdings_as_of − fn_gl_entries), while   │
-- │      current_market_value INCLUDES it (cmv − sec_mv = the 2000 sweep).                         │
-- │ (T7) AS-OF historical (tenant H): fn('2026-06-30') reads historical eod_price (LOCF) — the     │
-- │      as_of value DIFFERS from the current-date value (price rose 100→200 after as_of).         │
-- │ (T8) LIABILITY R-7 sign (a4): current_market_value is NEGATIVE (owed); cost_basis IS NULL.    │
-- │ (T9) AC#6 PERF smoke (tenant P, 20 accounts): fn returns ≤300ms — the conditional-lock         │
-- │      flip-gate. If RED, the fallback is extracting the shared trade_position projection to     │
-- │      drop fn_gl_entries' internal fn_compute_nav memo double-call (flag to team-lead+Architect).│
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ⚑ is_active / FOOT-TO-NAV NOTE (QA finding, surfaced to team-lead + Architect):
--   049 filters `where acc.is_active`; fn_compute_nav (019) does NOT filter is_active (its cash_leg
--   reads `from pfin.account acc` unqualified, and fn_holdings_as_of images all accounts). So the
--   "Σ current_market_value = NAV" invariant in the 049 header holds ONLY for a tenant with NO
--   value-bearing INACTIVE account. Tenant A here HAS one (a5, 9999) → for A, Σ049.cmv ≠ NAV(A) by
--   design. Foot-to-NAV (T3) is therefore proven on tenant F (all-active), where the invariant is
--   exact. Not a bug in 049 — a documented scope divergence worth an explicit ADR-038 footnote.
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22/RT-26/RT-27; 049 is a single authenticated-tier
--   INVOKER READ function — no service_role grant, no credential, no admission/network surface).
--   Decision-3 family UNCHANGED (049 authors NO table / NO FK-shaped reference column — it READS
--   existing FKs via the composed fns). SECURITY DEFINER allowlist UNCHANGED at 4 (this is INVOKER;
--   authored DEFINER fns stay 3). This battery introduces no catalogued instance; it is the pgTAP
--   proof the helper fails closed cross-tenant AND computes Design-C correctly.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants _rls.tenant_a()/_b() + fixed
--   literals for F/H/P; NO PII / NO real account numbers (SD-15) / NO real Plaid tokens (SD-03) /
--   NO prod data. GLOBAL securities carry users_id NULL (016/017 #7 — readable by any tenant's
--   INVOKER). All seeds PRIVILEGED (role=postgres; RLS+ACL bypassed) with users_id set EXPLICITLY
--   (auth.uid() is NULL under postgres); the fn is invoked ONLY under the authenticated tenant
--   contexts under test. All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated. Tenant UUIDs
--   + account ids resolve to psql LITERALS via \gset at role=postgres; every _rls.set_tenant is
--   called at role=postgres and each block restores role=postgres before the next. The fn / pgTAP
--   is/ok/cmp_ok/performs_ok under authenticated is proven safe by the green 019/035 batteries.
--
-- ⟦WIRE-VALIDATE⟧ authored + smoke-verified GREEN via a transient apply+rollback of 049 against the
--   001→048 landed local stack (NON-destructive; no `supabase db reset` — F/CTO local data intact).
--   The authoritative gate is CI pg_prove directory-mode (db-tests.yml) AFTER Backend's clean-apply
--   of 049. RED-until-049-applied is expected on any pre-049 stack (the function would not exist).
--   plan(28).
-- =====================================================================

begin;

-- shared cross-tenant verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(28);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset
\set tf '00000000-0000-0000-0000-0000000f0049'
\set th '00000000-0000-0000-0000-0000000f004a'
\set tp '00000000-0000-0000-0000-0000000f004b'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'tf'), (:'th'), (:'tp');

-- ---------------------------------------------------------------------
-- GLOBAL securities (users_id NULL → 016/017 #7 fence: readable by every tenant's INVOKER).
--   SECA: single price 150 @ 2026-06-01 (the main-portfolio + foot-to-NAV security).
--   SECH: 100 @ 2026-01-15 then 200 @ 2026-07-15 (the as-of LOCF security — price rises AFTER as_of).
-- ---------------------------------------------------------------------
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'RFSECA', 'RF Sec A') returning asset_id as seca \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'RFSECH', 'RF Sec H (as-of)') returning asset_id as sech \gset

insert into pfin.eod_price (asset_id, price_date, source, price) values
  (:seca, '2026-06-01', 'market_feed', 150.0000),
  (:sech, '2026-01-15', 'market_feed', 100.0000),   -- ≤ 2026-06-30 as_of → 100
  (:sech, '2026-07-15', 'market_feed', 200.0000);   -- > as_of; ≤ current_date → 200 (the LOCF trap)

-- =====================================================================
-- TENANT A — rich portfolio (a1 investment+sweep, a2 depository, a3 zero-holdings investment,
--   a4 liability) + a5 value-bearing INACTIVE. The isolation ANCHOR + branches T2/T4/T5/T6/T8.
-- =====================================================================
-- a1 (investment, tests T2/T6): checkpoint 3000 @ 06-01; BUY 10 SECA cost_basis 1000 amount -1000.
--   sec_mv = 10×150 = 1500 ; sec_book = 1000 ; cash = 3000−1000 = 2000.
--   cmv = 3500 ; cost_basis = 1000+2000 = 3000 ; unrealized_gl = 1500−1000 = 500 (= cmv−cost_basis).
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-inv-1', 'investment', 'household', 'taxable') returning account_id as a1 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a1, 3000.0000, 'USD', '2026-06-01', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor)
  values (:a1, '2026-06-05', -1000.0000, 10, :seca, 1000.0000, 'standard', 'buy-a1');

-- a2 (depository, T4): checkpoint 5000 → cmv 5000 ; cost_basis NULL ; unrealized_gl NULL.
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-dep-2', 'depository', 'household', 'taxable') returning account_id as a2 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a2, 5000.0000, 'USD', '2026-06-01', 'seed');

-- a3 (zero-holdings INVESTMENT, T5): checkpoint 800, NO securities.
--   sec_mv 0 ; sec_book 0 ; cash 800 → cmv 800 ; cost_basis 0+800 = 800 ; unrealized_gl 0 (NOT NULL).
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-inv-empty-3', 'investment', 'household', 'taxable') returning account_id as a3 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a3, 800.0000, 'USD', '2026-06-01', 'seed');

-- a4 (liability, T8): checkpoint -2000 (owed = negative, R-7 uniform) → cmv -2000 ; cost_basis NULL.
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-liab-4', 'liability', 'household', 'taxable') returning account_id as a4 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a4, -2000.0000, 'USD', '2026-06-01', 'seed');

-- a5 (depository, CLOSED as of 2026-06-30): must be EXCLUDED from the fn.
--   ⚑ RE-SEEDED AT ADR-042. This was `is_active = false` + a live 9999 balance — a
--     value-bearing INACTIVE account. THAT STATE IS NOW UNCONSTRUCTIBLE, and that is the
--     ADR's point, not an obstacle to it: the biconditional CHECK rejects the flag without a
--     date, the transfer-in fence rejects funding a closed account, and the close gate rejects
--     closing one that holds value. `disable trigger` / `session_replication_role` WOULD build
--     it and are REFUSED — fabricating a state the system prevents, to preserve an assertion
--     about it, is the defect ADR-042 removes.
--   Seeded through the REAL gate instead: funded while open, counter-booked to zero, closed.
--     Non-vacuity is now carried by the DATE (it really held 9999 on 2026-06-01) rather than
--     by a closed account still holding value.
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-closed-5', 'depository', 'household', 'taxable') returning account_id as a5 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a5, 9999.0000, 'USD', '2026-06-01', 'seed');
-- counter-book to zero ON the closing date, so leg 2 (cash) and leg 3 (post-closure activity)
-- both pass at closed_at.
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, vendor)
  values (:a5, '2026-06-30', -9999.0000, 0, 'wind-down-a5');
-- The seed block runs at postgres with no tenant, so auth.uid() is NULL and 057's
-- writer refuses rather than letting absence become a value. Declare the writer, as
-- its own raise instructs. 'system:remediation' is the ONLY system actor 057 admits
-- (enumerated, not an open pattern, so a new system identity fails the CHECK).
select set_config('pfin.actor', 'system:remediation', true);
select set_config('pfin.reason_code', 'no_longer_used', true);
update pfin.account set closed_at = '2026-06-30'::timestamptz where account_id = :a5;

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
-- TENANT F — foot-to-NAV (all ACTIVE, so Σ049.cmv = fn_compute_nav is EXACT).
--   f1 inv: checkpoint 2000; BUY 5 SECA cost_basis 500 amount -500 → sec_mv 750, cash 1500, cmv 2250.
--   f2 dep: checkpoint 400 → cmv 400.  f3 liab: checkpoint -300 → cmv -300.
--   Σ cmv = 2350.  fn_compute_nav = sec_leg 750 + cash_leg (1500+400−300=1600) = 2350.
-- =====================================================================
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tf', 'f-inv-1', 'investment', 'household', 'taxable') returning account_id as f1 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:f1, 2000.0000, 'USD', '2026-06-01', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor)
  values (:f1, '2026-06-05', -500.0000, 5, :seca, 500.0000, 'standard', 'buy-f1');
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tf', 'f-dep-2', 'depository', 'household', 'taxable') returning account_id as f2 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:f2, 400.0000, 'USD', '2026-06-01', 'seed');
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tf', 'f-liab-3', 'liability', 'household', 'taxable') returning account_id as f3 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:f3, -300.0000, 'USD', '2026-06-01', 'seed');

-- =====================================================================
-- TENANT H — as-of historical (T7). h1 inv: checkpoint 500 @ 01-01; BUY 1 SECH cost_basis 100
--   amount -100 @ 01-20.  cash = 500−100 = 400 (buy ≤ both dates).
--   as_of 2026-06-30: sec_mv 1×100 = 100 → cmv 500 ; unrealized_gl 100−100 = 0.
--   as_of current  : sec_mv 1×200 = 200 → cmv 600 ; unrealized_gl 200−100 = 100.  (values DIFFER).
-- =====================================================================
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'th', 'h-inv-1', 'investment', 'household', 'taxable') returning account_id as h1 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:h1, 500.0000, 'USD', '2026-01-01', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor)
  values (:h1, '2026-01-20', -100.0000, 1, :sech, 100.0000, 'standard', 'buy-h1');

-- =====================================================================
-- TENANT P — perf (T9): 20 ACTIVE investment accounts, each a checkpoint + a securities buy.
--   Generated set-wise; the fn_grant_creator_access trigger fires per account INSERT.
-- =====================================================================
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  select :'tp', 'p-acct-' || g, 'investment', 'household', 'taxable' from generate_series(1, 20) g;
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  select account_id, 1000.0000, 'USD', '2026-06-01', 'seed' from pfin.account where users_id = :'tp';
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor)
  select account_id, '2026-06-05', -200.0000, 2, :seca, 200.0000, 'standard', 'buy-p'
  from pfin.account where users_id = :'tp';

-- =====================================================================
-- T1 — CROSS-TENANT FAIL-CLOSED + owner-only-active (the isolation proof).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (1a) A sees EXACTLY its 4 ACTIVE accounts (a5 inactive excluded). RED=5 if is_active unfiltered.
select is(
  (select count(*)::int from pfin.fn_account_unrealized_gl('2026-06-30')),
  4,
  '(1a) owner-only-active: A sees EXACTLY 4 rows (a1..a4 active); the value-bearing INACTIVE a5 is EXCLUDED. RED=5 if the is_active filter were dropped');

-- (1b) A's returned account-id set = EXACTLY {a1,a2,a3,a4} (identity, not just count).
select is(
  (select array_agg(account_id order by account_id) from pfin.fn_account_unrealized_gl('2026-06-30')),
  (select array_agg(x order by x) from (values (:a1::bigint),(:a2),(:a3),(:a4)) v(x)),
  '(1b) owner identity set: A''s rows are EXACTLY {a1,a2,a3,a4} — every active account, only active accounts');

-- (1c) a5 (inactive, value-bearing 9999) is NOT among A's rows — non-vacuous is_active exclusion.
select ok(
  not exists (select 1 from pfin.fn_account_unrealized_gl('2026-06-30') where account_id = :a5),
  '(1c) is_active exclusion is non-vacuous: a5 EXISTS + carries 9999 cash, yet NEVER appears in the fn output (a suspended account feeds no per-account G/L card). RED if is_active were unfiltered');

-- (1f) cross-tenant: A sees ZERO of B's accounts.
select is(
  (select count(*)::int from pfin.fn_account_unrealized_gl('2026-06-30') where account_id = :b1),
  0,
  '(1f) cross-tenant read fails closed: A''s fn output contains NONE of B''s accounts (INVOKER composes under A''s RLS)');
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'tb'::uuid);
-- (1d) LOAD-BEARING: B calling the fn sees ZERO of A's four accounts.
select is(
  (select count(*)::int from pfin.fn_account_unrealized_gl('2026-06-30')
     where account_id in (:a1, :a2, :a3, :a4)),
  0,
  '(1d) LOAD-BEARING cross-tenant fail-closed: tenant B sees 0 of A''s accounts — RED (>0) if the fn were SECURITY DEFINER / lost set search_path / lost RLS composition (a1..a4 demonstrably exist, per B8)');
-- (1e) non-vacuous: B sees its OWN account (b1) — B's INVOKER read works; 1d is a boundary denial.
select is(
  (select count(*)::int from pfin.fn_account_unrealized_gl('2026-06-30') where account_id = :b1),
  1,
  '(1e) non-vacuous: B sees its OWN account b1 (exactly 1 row) → (1d)''s 0 is a cross-tenant BOUNDARY denial, not a globally empty function');
select set_config('role', 'postgres', true);

-- =====================================================================
-- T2 — INVESTMENT branch arithmetic (a1). Design-C: cmv=sec_mv+cash; cost_basis=sec_book+cash;
--   unrealized_gl = sec_mv−sec_book = cmv−cost_basis.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select current_market_value from pfin.fn_account_unrealized_gl('2026-06-30') where account_id = :a1),
  3500.0000::numeric,
  '(2a) investment cmv = sec_mv (10×150=1500) + cash (3000 checkpoint − 1000 buy = 2000) = 3500');
select is(
  (select cost_basis from pfin.fn_account_unrealized_gl('2026-06-30') where account_id = :a1),
  3000.0000::numeric,
  '(2b) investment cost_basis = sec_book (GL trade_position 1000) + the SAME cash term (2000) = 3000 (Design-C account-total book)');
select is(
  (select unrealized_gl from pfin.fn_account_unrealized_gl('2026-06-30') where account_id = :a1),
  500.0000::numeric,
  '(2c) investment unrealized_gl = sec_mv 1500 − sec_book 1000 = 500 (pure securities G/L)');
select is(
  (select unrealized_gl - (current_market_value - cost_basis)
     from pfin.fn_account_unrealized_gl('2026-06-30') where account_id = :a1),
  0::numeric,
  '(2d) Design-C identity: unrealized_gl = current_market_value − cost_basis (the identical cash term cancels) — RED if the two branches used different cash terms');
select set_config('role', 'postgres', true);

-- =====================================================================
-- T3 — FOOT-TO-NAV (Design-C headline; tenant F, all-active → invariant is exact).
-- =====================================================================
select _rls.set_tenant(:'tf'::uuid);
select is(
  (select coalesce(sum(current_market_value), 0) from pfin.fn_account_unrealized_gl('2026-06-30')),
  2350.0000::numeric,
  '(3a) Σ current_market_value over F''s accounts = 2350 (f1 2250 + f2 400 − f3 300)');
select is(
  pfin.fn_compute_nav('2026-06-30'::date),
  2350.0000::numeric,
  '(3b) fn_compute_nav(F) = 2350 (security_leg 750 + cash_leg 1600) — the independent NAV anchor');
select is(
  (select coalesce(sum(current_market_value), 0) from pfin.fn_account_unrealized_gl('2026-06-30')),
  pfin.fn_compute_nav('2026-06-30'::date),
  '(3c) FOOT-TO-NAV INVARIANT: Σ current_market_value = fn_compute_nav at the same as_of — RED if the cash term or securities leg diverged from NAV''s (Design-C''s whole point)');
select set_config('role', 'postgres', true);

-- =====================================================================
-- T4 — NON-INVESTMENT branch (a2 depository): cmv = roll-forward balance; cost_basis/unrealized_gl NULL.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select current_market_value from pfin.fn_account_unrealized_gl('2026-06-30') where account_id = :a2),
  5000.0000::numeric,
  '(4a) non-investment cmv = roll-forward cash balance 5000 (securities MV = 0)');
select ok(
  (select cost_basis is null from pfin.fn_account_unrealized_gl('2026-06-30') where account_id = :a2),
  '(4b) non-investment cost_basis IS NULL (concept does not apply) — RED if it were 0 (a false "$0 basis")');
select ok(
  (select unrealized_gl is null from pfin.fn_account_unrealized_gl('2026-06-30') where account_id = :a2),
  '(4c) non-investment unrealized_gl IS NULL (concept does not apply)');
select set_config('role', 'postgres', true);

-- =====================================================================
-- T5 — NULL-vs-ZERO discrimination (a3 zero-holdings INVESTMENT → 0, NOT NULL).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select unrealized_gl from pfin.fn_account_unrealized_gl('2026-06-30') where account_id = :a3),
  0::numeric,
  '(5a) zero-holdings INVESTMENT a3: unrealized_gl = 0 (concept APPLIES; securities G/L is genuinely zero)');
select ok(
  (select unrealized_gl is not null from pfin.fn_account_unrealized_gl('2026-06-30') where account_id = :a3),
  '(5b) NULL-vs-ZERO: a3''s unrealized_gl is 0 and NOT NULL — an empty investment account is 0/0/0, distinct from a non-investment''s NULL (RED if the branch returned NULL for zero holdings)');
select is(
  (select cost_basis from pfin.fn_account_unrealized_gl('2026-06-30') where account_id = :a3),
  800.0000::numeric,
  '(5c) zero-holdings INVESTMENT a3: cost_basis = 0 sec_book + 800 cash = 800 (account-total book; NOT NULL — investment class)');
select set_config('role', 'postgres', true);

-- =====================================================================
-- T6 — CASH-CANCELLATION (a1 with a 2000 cash sweep). sec_mv/sec_book recomputed INDEPENDENTLY
--   from fn_holdings_as_of / fn_gl_entries — the non-vacuous cancellation proof.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (6a) current_market_value INCLUDES the cash sweep: cmv − securities MV = 2000.
select is(
  (select current_market_value from pfin.fn_account_unrealized_gl('2026-06-30') where account_id = :a1)
    - (select coalesce(sum(h.quantity * ep.price), 0)
       from pfin.fn_holdings_as_of('2026-06-30') h
       join lateral (select e.price from pfin.eod_price e
                     where e.asset_id = h.asset_id and e.price_date <= '2026-06-30'
                     order by e.price_date desc limit 1) ep on true
       where h.account_id = :a1),
  2000.0000::numeric,
  '(6a) cash-cancellation: A1 current_market_value MINUS securities MV = 2000 → the cash sweep IS included in cmv (RED at 0 if cmv omitted cash)');
-- (6b) unrealized_gl EXCLUDES the cash: unrealized_gl = securities MV − securities book (cash cancels).
select is(
  (select unrealized_gl from pfin.fn_account_unrealized_gl('2026-06-30') where account_id = :a1),
  (
    (select coalesce(sum(h.quantity * ep.price), 0)
       from pfin.fn_holdings_as_of('2026-06-30') h
       join lateral (select e.price from pfin.eod_price e
                     where e.asset_id = h.asset_id and e.price_date <= '2026-06-30'
                     order by e.price_date desc limit 1) ep on true
       where h.account_id = :a1)
    - (select coalesce(sum(g.amount_book), 0) from pfin.fn_gl_entries('2026-06-30') g
        where g.account_id = :a1 and g.entry_class = 'trade_position')
  ),
  '(6b) cash-cancellation: A1 unrealized_gl = securities MV (1500) − securities book (trade_position 1000) = 500; the 2000 cash cancels EXACTLY (RED at 2500 if cash leaked into unrealized_gl)');
select set_config('role', 'postgres', true);

-- =====================================================================
-- T7 — AS-OF historical (tenant H): the composed fns thread p_as_of → historical eod_price (LOCF).
-- =====================================================================
select _rls.set_tenant(:'th'::uuid);
-- (7a) historical cmv @ 2026-06-30 = 500 (sec_mv 1×100 + cash 400).
select is(
  (select current_market_value from pfin.fn_account_unrealized_gl('2026-06-30') where account_id = :h1),
  500.0000::numeric,
  '(7a) as-of historical: cmv @ 2026-06-30 = 500 (SECH LOCF price 100 @ 01-15 × 1 + cash 400)');
-- (7b) historical unrealized_gl @ 2026-06-30 = 0 (sec_mv 100 − sec_book 100).
select is(
  (select unrealized_gl from pfin.fn_account_unrealized_gl('2026-06-30') where account_id = :h1),
  0::numeric,
  '(7b) as-of historical: unrealized_gl @ 2026-06-30 = 0 (mv 100 − book 100; the 200 price is AFTER as_of, LOCF ignores it)');
-- (7c) the as_of value DIFFERS from the current-date value (default param): 500 ≠ 600.
select isnt(
  (select current_market_value from pfin.fn_account_unrealized_gl('2026-06-30') where account_id = :h1),
  (select current_market_value from pfin.fn_account_unrealized_gl() where account_id = :h1),
  '(7c) as-of threads through: cmv @ 2026-06-30 (500) ≠ cmv @ current_date (600 — SECH rose to 200 @ 07-15) — p_as_of genuinely selects the historical price, not always the latest');
select set_config('role', 'postgres', true);

-- =====================================================================
-- T8 — LIABILITY R-7 sign (a4): current_market_value NEGATIVE; cost_basis NULL.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select current_market_value from pfin.fn_account_unrealized_gl('2026-06-30') where account_id = :a4),
  -2000.0000::numeric,
  '(8a) liability R-7 sign: current_market_value = -2000 (owed balance is naturally negative — no account_type branch / no abs). RED at +2000 if a sign-flip were applied');
select ok(
  (select cost_basis is null from pfin.fn_account_unrealized_gl('2026-06-30') where account_id = :a4),
  '(8b) liability is non-investment: cost_basis IS NULL (unrealized_gl likewise) — a liability has no "unrealized gain"');
select set_config('role', 'postgres', true);

-- =====================================================================
-- T9 — AC#6 PERF smoke (tenant P, 20 accounts) — the conditional-lock flip-gate.
-- =====================================================================
select _rls.set_tenant(:'tp'::uuid);
-- (9a) non-vacuous perf fixture: P returns exactly 20 rows (the perf query does real work).
select is(
  (select count(*)::int from pfin.fn_account_unrealized_gl('2026-06-30')),
  20,
  '(9a) perf fixture is non-vacuous: tenant P''s ~20-account portfolio returns 20 rows');
-- (9b) AC#6: the 20-account portfolio computes within 300ms. If RED, the flip-gate fallback is
--      extracting the shared trade_position projection to drop fn_gl_entries'' fn_compute_nav memo
--      double-call (flag to team-lead + Architect). NOTE: a timing assertion is environment-
--      sensitive; the authoritative measurement is captured in the QA smoke report.
select performs_ok(
  'select * from pfin.fn_account_unrealized_gl(''2026-06-30''::date)',
  300,
  '(9b) AC#6 perf: fn_account_unrealized_gl over a 20-account portfolio completes in ≤300ms (conditional-lock flip-gate)');
select set_config('role', 'postgres', true);

select * from finish();
rollback;

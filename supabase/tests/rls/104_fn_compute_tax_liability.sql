-- =====================================================================
-- Per-Wave battery — pfin.fn_compute_tax_liability, the §2.5 keystone read
--   helper (SELF-262; migration 104). Paired with the migration in the SAME
--   PR (verify-paired-artifacts discipline). Companion to SELF-269's own
--   two-tenant extension — this file covers the fences 104 itself owns.
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/104_fn_compute_tax_liability.sql.
--   Object: pfin.fn_compute_tax_liability(p_data_as_of date default
--   current_date) returns jsonb. SECURITY INVOKER, STABLE, set search_path
--   = ''. No table, no column, no policy, no trigger. Reads through 093
--   (fn_cashflow_items), 084 (posting_prototype), 049/056/079
--   (fn_account_unrealized_gl), 003 (account), 102
--   (fn_ytd_paid_per_jurisdiction), 101/103 (tax_bracket_schedule /
--   tax_bracket_row). ADR-067 Decision 5 is the payload contract's
--   canonical home; every AC below maps to it and to the SELF-262 AC block,
--   read live at authoring, plus E22/E25/E26 in
--   docs/records/v14-execution/log.md.
--
-- ┌─ WHAT THIS BATTERY PROVES — one line per required leg ─────────────────────┐
-- │ L1  DECOMPOSITION: Revenue-class fence (BOTH conjuncts) excludes a Trade/  │
-- │       STC decoy reaching fn_cashflow_items through the split-child branch │
-- │       on a NON-security parent (030's Trade trigger does not fire on a    │
-- │       split child); total and rows[] both prove the exclusion.            │
-- │ L2  UNCLASSIFIED COUNT: from the SAME query that sums (SELF-264 AC 3b).   │
-- │ L3  CAPITAL_GAINS: always {status:unavailable, reason:                    │
-- │       no_sale_recording_capability}, NO rows key, structural not a count. │
-- │ L4  E22 FALLBACK: federal.basis_year is the CURRENT year, california's is │
-- │       the LATEST PRIOR year (103's real seed shape) — read from the SAME  │
-- │       call, not two separate fixtures.                                    │
-- │ L5  FLOOR: federal LT-CG taxable income floors at 0 when the standard     │
-- │       deduction exceeds the input; never negative.                        │
-- │ L6  INSTALLMENTS / Q4 RESIDUAL: federal's four installments sum EXACTLY   │
-- │       to round(annual,2); Q1=Q2=Q3; the residual sits on Q4 (hand-        │
-- │       verified exact cents); california asserted structurally (same      │
-- │       invariant, evenly-divisible case).                                  │
-- │ L7  APPLIED_MARGINAL_RATE present (both legs) when computed.              │
-- │ L8  YTD PAID: designated (federal, non-null amount) vs undesignated       │
-- │       (california, NULL not 0) in the SAME call; funds_due UNAVAILABLE/   │
-- │       ytd_paid_unavailable when ytd_paid is null and the schedule IS      │
-- │       resolved (computed=true).                                          │
-- │ L9  YTD-ZERO: a designated-but-empty ledger reads 0, not NULL — the       │
-- │       distinguishing half of L8 (E11's one-character design choice).      │
-- │ L10 REALIZED nav_component: UNAVAILABLE/ytd_paid_unavailable while one    │
-- │       jurisdiction's YTD is null; COMPUTED (sum of both funds_due gaps,   │
-- │       negative allowed) once both are designated.                        │
-- │ L11 UNREALIZED CLAMP: a net-LOSS aggregate across TAXABLE accounts        │
-- │       (GL-backed cost basis, not a market-value-only numerator) clamps    │
-- │       to 0, never a negative liability.                                  │
-- │ L12 (π) EXCLUSION: a tax_deferred account's gain is excluded from the     │
-- │       Unrealized aggregate; moving it to taxable MOVES the figure by      │
-- │       exactly its own contribution — the inversion is the fixture, not a │
-- │       struck line.                                                       │
-- │ L13 QUARTERS_ELAPSED: the count of due dates on or before p_data_as_of,   │
-- │       swept across all four federal boundaries within one tax year.      │
-- │ L14 R8 WINDOW: open on Jan 10 and Jan 15 (inclusive), closed Jan 16;      │
-- │       tax_year is the PRIOR year in ALL THREE calls — only `open` moves   │
-- │       (⚠ corrects the design memo's own §8 outline, which wrongly showed  │
-- │       tax_year moving across the boundary).                              │
-- │ L15 EMPTY CURRENT-YEAR SCHEDULE: a schedule ROW that exists but carries   │
-- │       zero bracket rows is treated as ABSENT for selection (falls back    │
-- │       past it to the next usable prior year) and is reported via         │
-- │       current_year_schedule_empty, distinct from L4's no-row case.       │
-- │ L16 NO-SCHEDULE-ANY-YEAR / CROSS-TENANT: a tenant with no schedules and   │
-- │       no ledger gets UNAVAILABLE (never zeros) on both jurisdictions and  │
-- │       both nav_components, with applied_marginal_rate KEY ABSENT — and   │
-- │       its OWN decomposition rows only, never the rich tenant's, while     │
-- │       BOTH tenants' data coexist in the same database (RLS-authenticated,│
-- │       not a postgres-bypassed read).                                     │
-- │ L17 CATALOG POSTURE: prosecdef=f, provolatile=s, search_path='' pinned,   │
-- │       EXECUTE revoked PUBLIC / granted authenticated, EXACTLY ONE         │
-- │       overload by proname.                                               │
-- │ L18 VOLATILITY PIN: all SIX named functions (the helper itself plus its   │
-- │       three real callees plus the two functions the header's volatility  │
-- │       section additionally names) measure provolatile = 's' — the        │
-- │       watcher for a future CREATE OR REPLACE silently un-pinning one.     │
-- │ L19 NO nav_daily REFERENCE in the catalog body (not a header-comment      │
-- │       grep — AC 1's structural exclusion, measured).                     │
-- │ L20 fn_compute_nav(date) / fn_compute_nav(date,boolean) /                 │
-- │       fn_nav_composition(date) BYTE-UNCHANGED: md5(pg_get_functiondef)    │
-- │       pinned against a clean 001->103 control build (this branch,        │
-- │       2026-09-04 — see the header note below for the measured values).   │
-- └──────────────────────────────────────────────────────────────────────────┘
--
-- ⚠ FIXTURE HAZARD (Architect, carried into the dispatch): a Trade-class
--   annotation is refused at the write path unless security_id is set (030's
--   fn_account_trans_annotation_trade_constraints trigger, which fires on
--   pfin.account_trans_annotation only). The L1 decoy is therefore seeded as
--   an account_trans_split CHILD on a NON-security PARENT — the trigger does
--   not fire on account_trans_split at all, so this is not a bypass of a
--   fence 104 depends on, it is the only way to construct a tax_relevant
--   Trade row that fn_cashflow_items would ever emit.
-- ⚠ FIXTURE HAZARD (Architect): fn_account_unrealized_gl's cost_basis comes
--   from GL trade_position entries (account_trans.cost_basis, via
--   transaction_type='standard'), not from market value alone. L11's clamp
--   fixture is GL-BACKED (cost_basis > market value on the loss leg) so it
--   exercises the FULL (market_value - cost_basis) numerator, not merely the
--   market-value half — a market-value-only fixture cannot produce a net
--   loss at all, since cost_basis defaults to 0 with no GL entries.
-- ⚠ FIXTURE-CLOCK TRAP (own agent-memory,
--   feedback_fixture_clock_trap_recurred_self257): account_trans.created_at
--   defaults to real wall-clock now(), which is AFTER every as_of this file
--   uses. Every account_trans row below sets created_at EXPLICITLY to its
--   own transaction_date, or Lock 15's half-open created_at filter in 093
--   silently empties every reader.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY; no PII, no real account numbers
--   (SD-15), no prod data; all dollar figures below are synthetic test
--   fixtures, not F/CTO's real figures (AC 9); rolled-back txn; no
--   `supabase db reset`.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

-- plan = 45: L1 2 · L2 1 · L3 2 · L4 2 · L5 1 · L6 3 · L7 1 · L8 3 · L9 1 ·
--   L10 1 · L11 1 · L12 1 · L13 4 · L14 3 · L15 3 · L16 8 · L17 3 · L18 1 ·
--   L19 1 · L20 3.
select plan(45);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

insert into auth.users (id) values (:'ta'), (:'tb');

select set_config('role', 'postgres', true);

-- =====================================================================
-- FIXTURE (PRIVILEGED postgres session — RLS-bypassed seed path, matching
-- the 093/049/102 battery convention: writes go through controlled RPCs in
-- the app; a battery seeds base tables directly, as postgres).
-- =====================================================================

-- ---- posting_prototype (tenant A) ----
insert into pfin.posting_prototype (users_id, cat, sub_cat, tax_relevant, tax_character, is_tax_payment)
  values (:'ta', 'Revenue', 'Salary104', true, null, false)
  returning id as a_salary \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, tax_relevant, tax_character, is_tax_payment)
  values (:'ta', 'Revenue', 'Dividend104', true, null, false)
  returning id as a_div \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, tax_relevant, tax_character, is_tax_payment)
  values (:'ta', 'Revenue', 'DividendQualified104', true, 'qualified_dividend', false)
  returning id as a_divq \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, tax_relevant, tax_character, is_tax_payment)
  values (:'ta', 'Trade', 'STC104', true, null, false)
  returning id as a_trade \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, tax_relevant, is_tax_payment)
  values (:'ta', 'Expense', 'SplitLeg104', false, false)
  returning id as a_splitexp \gset

-- ---- cash account + Revenue transactions (dated 2026-01-10 -> in_ytd for
--      every as_of this file uses, from 2026-02-01 through 2026-12-31) ----
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-cash-104', 'depository', 'household', 'taxable')
  returning account_id as acct_cash \gset

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, created_at)
  values (:acct_cash, '2026-01-10', 2500.0000, 'salary-104', '2026-01-10'::timestamptz)
  returning trans_id as t_salary \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_salary, :a_salary);

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, created_at)
  values (:acct_cash, '2026-01-10', 500.0000, 'div-104', '2026-01-10'::timestamptz)
  returning trans_id as t_div \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_div, :a_div);

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, created_at)
  values (:acct_cash, '2026-01-10', 1001.0000, 'divq-104', '2026-01-10'::timestamptz)
  returning trans_id as t_divq \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_divq, :a_divq);

-- L1 fixture hazard: split parent carries NO security_id (non-security), so
-- 030's Trade trigger (which fires only on account_trans_annotation) never
-- sees this row at all; the children route through account_trans_split.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, created_at)
  values (:acct_cash, '2026-01-10', -300.0000, 'split-parent-104', '2026-01-10'::timestamptz)
  returning trans_id as t_split \gset
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount)
  values (:t_split, :a_trade, -250.0000);
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount)
  values (:t_split, :a_splitexp, -50.0000);

-- L2 fixture: an unannotated transaction -> sub_cat_id null -> unclassified.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, created_at)
  values (:acct_cash, '2026-01-10', -10.0000, 'unclassified-104', '2026-01-10'::timestamptz)
  returning trans_id as t_unc \gset

-- ---- tax_bracket_schedule / tax_bracket_row (tenant A; 101/103 substrate)
--      federal_ordinary + federal_lt_cg at 2026 (current year, L4's federal
--      half); california_ordinary at 2025 ONLY (no 2026 row at all -- L4's
--      california fallback half, matching 103's real seed shape). ----
insert into pfin.tax_bracket_schedule (users_id, schedule_type, tax_year, standard_deduction, schedule_label)
  values (:'ta', 'federal_ordinary', 2026, 500.0000, 'fed-ord-2026-104')
  returning id as sch_fedord \gset
insert into pfin.tax_bracket_row (users_id, schedule_id, bracket_floor, bracket_rate)
  values (:'ta', :sch_fedord, 0, 0.10),
         (:'ta', :sch_fedord, 2003, 0.20);

-- L5 FLOOR fixture: standard_deduction (1500) exceeds the LT-CG input (1001
-- from DividendQualified104) -> taxable floors at 0.
insert into pfin.tax_bracket_schedule (users_id, schedule_type, tax_year, standard_deduction, schedule_label)
  values (:'ta', 'federal_lt_cg', 2026, 1500.0000, 'fed-ltcg-2026-104')
  returning id as sch_fedltcg \gset
insert into pfin.tax_bracket_row (users_id, schedule_id, bracket_floor, bracket_rate)
  values (:'ta', :sch_fedltcg, 0, 0.05);

insert into pfin.tax_bracket_schedule (users_id, schedule_type, tax_year, standard_deduction, schedule_label)
  values (:'ta', 'california_ordinary', 2025, 799.0000, 'ca-ord-2025-104')
  returning id as sch_ca \gset
insert into pfin.tax_bracket_row (users_id, schedule_id, bracket_floor, bracket_rate)
  values (:'ta', :sch_ca, 0, 0.08),
         (:'ta', :sch_ca, 3000, 0.12);

-- ---- L8/L10: irs ledger designated with a checkpoint of 1200; NO ftb
--      ledger yet (california stays undesignated until the L9/L10 STATE2
--      mutation below). ----
insert into pfin.account (users_id, name, account_type, scope, tax_treatment, tax_jurisdiction)
  values (:'ta', 'a-irs-ledger-104', 'depository', 'household', 'taxable', 'irs')
  returning account_id as acct_irs \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:acct_irs, 1200.0000, 'USD', '2026-01-01', 'seed');

-- ---- L11/L12: Unrealized -- one global asset, GL-backed cost basis on
--      three investment accounts. mv = 10 * 150.00 = 1500.00 on every one.
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'SEC104', 'Sec 104 (self262 control)')
  returning asset_id as ast \gset
insert into pfin.eod_price (asset_id, price_date, source, price) values
  (:ast, '2026-06-01', 'market_feed', 150.0000);

-- a_gain (taxable): cost_basis 1000 -> unrealized_gl = 1500-1000 = +500.
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-unreal-gain-104', 'investment', 'household', 'taxable')
  returning account_id as a_gain \gset
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor, created_at)
  values (:a_gain, '2026-01-05', -1000.0000, 10, :ast, 1000.0000, 'standard', 'buy-gain-104', '2026-01-05'::timestamptz);

-- a_loss (taxable): cost_basis 3000 -> unrealized_gl = 1500-3000 = -1500.
-- gain(500) + loss(-1500) = -1000 net -> L11's clamp fixture.
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-unreal-loss-104', 'investment', 'household', 'taxable')
  returning account_id as a_loss \gset
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor, created_at)
  values (:a_loss, '2026-01-05', -3000.0000, 10, :ast, 3000.0000, 'standard', 'buy-loss-104', '2026-01-05'::timestamptz);

-- a_pi (TAX_DEFERRED): cost_basis 100 -> unrealized_gl = 1500-100 = +1400.
-- L12's (pi) exclusion fixture -- excluded while tax_deferred.
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-pi-104', 'investment', 'household', 'tax_deferred')
  returning account_id as a_pi \gset
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor, created_at)
  values (:a_pi, '2026-01-05', -100.0000, 10, :ast, 100.0000, 'standard', 'buy-pi-104', '2026-01-05'::timestamptz);

-- ---- L16: tenant B, its OWN small Revenue row, NO schedules, NO ledger. ----
insert into pfin.posting_prototype (users_id, cat, sub_cat, tax_relevant, is_tax_payment)
  values (:'tb', 'Revenue', 'BSalary104', true, false)
  returning id as b_sal \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'b-cash-104', 'depository', 'household', 'taxable')
  returning account_id as b_acct \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, created_at)
  values (:b_acct, '2026-01-10', 77.0000, 'b-salary-104', '2026-01-10'::timestamptz)
  returning trans_id as b_t \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:b_t, :b_sal);

-- =====================================================================
-- L1-L11 — the MAIN walk, as TENANT A under REAL RLS (authenticated +
-- request.jwt.claims), not a postgres-bypassed read. Both tenants' data
-- coexist in this database -- A's numbers below are unaffected by B's row.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

select is(
  (pfin.fn_compute_tax_liability('2026-08-15'::date)->'decomposition'->'ordinary_income'->>'total')::numeric,
  4001.0000::numeric,
  '(L1a) ordinary_income.total = 4001.0000 (Salary 2500 + Dividend 500 + DividendQualified 1001) -- the Trade/STC decoy (-250, reached via the split-child branch) contributes NOTHING'
);
select is(
  jsonb_array_length(pfin.fn_compute_tax_liability('2026-08-15'::date)->'decomposition'->'ordinary_income'->'rows'),
  3,
  '(L1b) ordinary_income.rows has EXACTLY 3 elements -- the Trade decoy and the Expense split-sibling are both absent (cat=''Revenue'' AND tax_relevant, BOTH conjuncts)'
);

select is(
  (pfin.fn_compute_tax_liability('2026-08-15'::date)->'decomposition'->'unclassified'->>'count_ytd')::int,
  1,
  '(L2) decomposition.unclassified.count_ytd = 1 -- the one unannotated transaction, from the SAME query that sums (SELF-264 AC 3b)'
);

select is(
  pfin.fn_compute_tax_liability('2026-08-15'::date)->'decomposition'->'capital_gains',
  '{"status":"unavailable","reason":"no_sale_recording_capability"}'::jsonb,
  '(L3a) capital_gains is ALWAYS {status:unavailable, reason:no_sale_recording_capability} -- a STRUCTURAL fact (no sale writer exists), never a row count'
);
select ok(
  not (pfin.fn_compute_tax_liability('2026-08-15'::date)->'decomposition'->'capital_gains' ? 'rows'),
  '(L3b) capital_gains carries NO ''rows'' key at all -- an empty rows:[] beside the status would be a second way to say the same thing and invite a consumer to render it (E26 ruling 4)'
);

select is(
  (pfin.fn_compute_tax_liability('2026-08-15'::date)->'jurisdictions'->'federal'->>'basis_year')::int,
  2026,
  '(L4a) federal.basis_year = 2026, the CURRENT tax year -- a federal_ordinary/federal_lt_cg schedule exists for 2026'
);
select is(
  (pfin.fn_compute_tax_liability('2026-08-15'::date)->'jurisdictions'->'california'->>'basis_year')::int,
  2025,
  '(L4b) california.basis_year = 2025, the LATEST PRIOR year -- NO california_ordinary schedule exists for 2026 at all, the E22 fallback in use, same call as L4a'
);

select is(
  (pfin.fn_compute_tax_liability('2026-08-15'::date)->'jurisdictions'->'federal'->'taxable_income'->>'lt_cg')::numeric,
  0::numeric,
  '(L5) federal.taxable_income.lt_cg = 0 -- standard_deduction (1500) exceeds the LT-CG input (1001), floored at zero rather than going negative (Sec M-9), applied BEFORE the bracket walk'
);

select is(
  pfin.fn_compute_tax_liability('2026-08-15'::date)->'jurisdictions'->'federal'->'installments',
  '[{"quarter":1,"due_date":"2026-04-15","amount":74.93},{"quarter":2,"due_date":"2026-06-15","amount":74.93},{"quarter":3,"due_date":"2026-09-15","amount":74.93},{"quarter":4,"due_date":"2027-01-15","amount":74.91}]'::jsonb,
  '(L6a) federal.installments -- Q1=Q2=Q3=74.93, Q4=74.91 carries the rounding residual so all four sum EXACTLY to round(299.70,2)=299.70 (E25); hand-verified exact cents'
);
select ok(
  (with j as (select pfin.fn_compute_tax_liability('2026-08-15'::date)->'jurisdictions'->'california' as ca)
   select (select sum((i->>'amount')::numeric) from j, jsonb_array_elements(j.ca->'installments') i)
        = (select (j.ca->>'annual_liability')::numeric from j)
     and (select (i->>'amount')::numeric from j, jsonb_array_elements(j.ca->'installments') i where (i->>'quarter')::int = 1)
       = (select (i->>'amount')::numeric from j, jsonb_array_elements(j.ca->'installments') i where (i->>'quarter')::int = 3)
  ),
  '(L6b) california installments: sum(amounts) = annual_liability EXACTLY and Q1 = Q3 (structural E25 invariant, independent hand-computed leg from federal''s)'
);
select is(
  (pfin.fn_compute_tax_liability('2026-08-15'::date)->'jurisdictions'->'california'->>'annual_liability')::numeric,
  264.24::numeric,
  '(L6c) california.annual_liability = 264.24 -- taxable 3202.00 (4001 input - 799 deduction) walked at 0.08/0.12 (240.00 + 24.24), hand-verified independently of L6a''s federal figure'
);

select is(
  pfin.fn_compute_tax_liability('2026-08-15'::date)->'jurisdictions'->'federal'->'applied_marginal_rate',
  '{"ordinary":0.20000000,"lt_cg":0.05000000}'::jsonb,
  '(L7) federal.applied_marginal_rate = {ordinary:0.20, lt_cg:0.05} -- present because federal is computed (both required schedules resolved)'
);

select is(
  pfin.fn_compute_tax_liability('2026-08-15'::date)->'jurisdictions'->'federal'->'ytd_paid',
  '{"status":"designated","amount":1200.0000}'::jsonb,
  '(L8a) federal.ytd_paid = {designated, 1200.0000} -- the irs ledger''s checkpoint, in the SAME call as L8b''s undesignated california'
);
select is(
  pfin.fn_compute_tax_liability('2026-08-15'::date)->'jurisdictions'->'california'->'ytd_paid',
  '{"status":"unavailable","reason":"no_ledger_designated"}'::jsonb,
  '(L8b) california.ytd_paid = {unavailable, no_ledger_designated} -- NULL, not 0, since no ftb ledger is designated (undesignated half, paired with L8a''s designated federal in the SAME call)'
);
select is(
  jsonb_build_object(
    'california_status', pfin.fn_compute_tax_liability('2026-08-15'::date)->'jurisdictions'->'california'->'status',
    'funds_due', pfin.fn_compute_tax_liability('2026-08-15'::date)->'jurisdictions'->'california'->'funds_due'
  ),
  '{"funds_due":{"status":"unavailable","reason":"ytd_paid_unavailable"},"california_status":"computed"}'::jsonb,
  '(L8c) california.funds_due = {unavailable, ytd_paid_unavailable} EVEN THOUGH california.status = computed -- funds_due keys on ytd_paid''s own availability, not on whether the schedule resolved'
);

-- =====================================================================
-- L9/L10 — STATE2: designate an ftb ledger with a ZERO-balance checkpoint.
-- Distinguishes designated-empty (0) from undesignated (NULL, L8b above),
-- and moves nav_components.realized_tax_liab from unavailable to computed.
-- =====================================================================
select set_config('role', 'postgres', true);
insert into pfin.account (users_id, name, account_type, scope, tax_treatment, tax_jurisdiction)
  values (:'ta', 'a-ftb-ledger-104', 'depository', 'household', 'taxable', 'ftb')
  returning account_id as acct_ftb \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:acct_ftb, 0.0000, 'USD', '2026-01-01', 'seed');
select _rls.set_tenant(:'ta'::uuid);

select is(
  pfin.fn_compute_tax_liability('2026-08-15'::date)->'jurisdictions'->'california'->'ytd_paid',
  '{"status":"designated","amount":0.0000}'::jsonb,
  '(L9) STATE2: california.ytd_paid = {designated, 0.0000} -- a designated ledger holding NOTHING reads 0, not NULL (E11''s one-character-reversal design choice, the distinguishing half of L8b)'
);
select is(
  pfin.fn_compute_tax_liability('2026-08-15'::date)->'nav_components'->'realized_tax_liab',
  '{"status":"computed","amount":-918.0200}'::jsonb,
  '(L10) STATE2: nav_components.realized_tax_liab moves from unavailable (before STATE2, both jurisdictions'' ytd_paid required) to {computed, -918.0200} -- the SUM of both jurisdictions'' Estimated-Funds-Due gaps (federal -1050.14 + california 132.12), a NEGATIVE combined figure surfaced rather than clamped (nu-1)'
);

-- =====================================================================
-- L11/L12 — Unrealized: clamp on a net loss, then the (pi) exclusion moved
-- by re-classifying a_pi from tax_deferred to taxable.
-- =====================================================================
select is(
  pfin.fn_compute_tax_liability('2026-08-15'::date)->'nav_components'->'unrealized_tax_liab',
  '{"status":"computed","amount":0}'::jsonb,
  '(L11) nav_components.unrealized_tax_liab = {computed, 0} -- a_gain(+500) + a_loss(-1500) = -1000 net, x (fed_ltcg_top 0.05 + ca_top 0.12) = -170, CLAMPED to 0 rather than reported negative (R9); a_pi''s +1400 gain (tax_deferred) is excluded -- if it had leaked in the net would be +400 and this assertion would be RED'
);

select set_config('role', 'postgres', true);
update pfin.account set tax_treatment = 'taxable' where account_id = :a_pi;
select _rls.set_tenant(:'ta'::uuid);
select is(
  (pfin.fn_compute_tax_liability('2026-08-15'::date)->'nav_components'->'unrealized_tax_liab'->>'amount')::numeric,
  68.00::numeric,
  '(L12) (pi) EXCLUSION, moved: after re-classifying a_pi to taxable, the aggregate becomes -1000+1400=400, x 0.17 = 68.00 -- moving the account MOVES the figure by exactly its own contribution (the inversion IS the fixture: L11''s clamped-0 could not have hidden a leak, since a leaked +1400 would have made L11 red already)'
);
select set_config('role', 'postgres', true);
update pfin.account set tax_treatment = 'tax_deferred' where account_id = :a_pi;
select _rls.set_tenant(:'ta'::uuid);

-- =====================================================================
-- L13 — QUARTERS_ELAPSED: swept across all four federal due-date
-- boundaries, all within tax_year 2026 (Q4's due date is NEVER reached
-- inside its own tax year, by construction -- see the migration header).
-- =====================================================================
select is(
  (pfin.fn_compute_tax_liability('2026-02-01'::date)->'jurisdictions'->'federal'->>'quarters_elapsed')::int,
  0, '(L13a) as_of 2026-02-01, before Apr 15 -> quarters_elapsed = 0'
);
select is(
  (pfin.fn_compute_tax_liability('2026-05-01'::date)->'jurisdictions'->'federal'->>'quarters_elapsed')::int,
  1, '(L13b) as_of 2026-05-01, after Apr 15 -> quarters_elapsed = 1'
);
select is(
  (pfin.fn_compute_tax_liability('2026-07-01'::date)->'jurisdictions'->'federal'->>'quarters_elapsed')::int,
  2, '(L13c) as_of 2026-07-01, after Jun 15 -> quarters_elapsed = 2'
);
select is(
  (pfin.fn_compute_tax_liability('2026-10-01'::date)->'jurisdictions'->'federal'->>'quarters_elapsed')::int,
  3, '(L13d) as_of 2026-10-01, after Sep 15 -> quarters_elapsed = 3 (the max reachable inside tax_year 2026 itself; Q4''s Jan-15-following-year due date can never be <= an as_of dated inside the same tax_year)'
);

-- =====================================================================
-- L14 — R8 render window: open Jan 10 / Jan 15 (inclusive), closed Jan 16.
-- tax_year is the PRIOR year in ALL THREE calls -- only `open` moves. This
-- CORRECTS the self262-design.md memo's own S8 table, which showed
-- tax_year moving across the boundary; the shipped code does not.
-- =====================================================================
select is(
  pfin.fn_compute_tax_liability('2026-01-10'::date)->'prior_year_q4_window',
  '{"open":true,"due_date":"2026-01-15","tax_year":2025}'::jsonb,
  '(L14a) Jan 10: window open, tax_year = 2025 (prior)'
);
select is(
  pfin.fn_compute_tax_liability('2026-01-15'::date)->'prior_year_q4_window',
  '{"open":true,"due_date":"2026-01-15","tax_year":2025}'::jsonb,
  '(L14b) Jan 15 (INCLUSIVE): window still open, tax_year UNCHANGED at 2025'
);
select is(
  pfin.fn_compute_tax_liability('2026-01-16'::date)->'prior_year_q4_window',
  '{"open":false,"due_date":"2026-01-15","tax_year":2025}'::jsonb,
  '(L14c) Jan 16: window closed -- ONLY `open` flipped to false; prior_year_q4_window.tax_year stays 2025 (the constant PRIOR year) across all three calls -- it never tracks the payload''s own top-level `tax_year` (which is 2026 for a Jan-2026 as_of)'
);

-- =====================================================================
-- L15 — EMPTY CURRENT-YEAR SCHEDULE: a california_ordinary row that EXISTS
-- at tax_year 2027 but carries ZERO bracket rows. Distinct from L4b (no row
-- at all) -- this must fall back PAST the empty row to 2025 and say so.
-- =====================================================================
select set_config('role', 'postgres', true);
insert into pfin.tax_bracket_schedule (users_id, schedule_type, tax_year, standard_deduction, schedule_label)
  values (:'ta', 'california_ordinary', 2027, 900.0000, 'ca-ord-2027-empty-104');
select _rls.set_tenant(:'ta'::uuid);

select is(
  (pfin.fn_compute_tax_liability('2027-06-15'::date)->'jurisdictions'->'california'->'schedules'->'california_ordinary'->>'current_year_schedule_empty')::boolean,
  true,
  '(L15a) at as_of 2027-06-15, california_ordinary.current_year_schedule_empty = true -- the 2027 row exists but holds zero bracket rows'
);
select is(
  (pfin.fn_compute_tax_liability('2027-06-15'::date)->'jurisdictions'->'california'->>'basis_year')::int,
  2025,
  '(L15b) basis_year is STILL 2025 -- the empty 2027 row is skipped for SELECTION (not just flagged), falling back past it to the latest USABLE prior year'
);
select is(
  pfin.fn_compute_tax_liability('2027-06-15'::date)->'jurisdictions'->'california'->>'status',
  'computed',
  '(L15c) status = computed, NOT suppressed -- an empty current-year row must not consume the current-year key and silently compute $0 off it (103''s own rejected option (b))'
);

-- =====================================================================
-- L16 — NO-SCHEDULE-ANY-YEAR / CROSS-TENANT: tenant B, called under REAL
-- RLS while tenant A's rich fixture ALSO exists in this database. B has no
-- schedules and no designated ledger.
-- =====================================================================
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);

select is(
  (pfin.fn_compute_tax_liability('2026-08-15'::date)->'decomposition'->'ordinary_income'->>'total')::numeric,
  77.0000::numeric,
  '(L16a) B sees its OWN total (77.0000) -- never tenant A''s 4001.0000, and never a coalesced 0 that would suggest a leak-and-cancel'
);
select is(
  jsonb_array_length(pfin.fn_compute_tax_liability('2026-08-15'::date)->'decomposition'->'ordinary_income'->'rows'),
  1,
  '(L16b) B sees exactly 1 row -- tenant A''s 3 Revenue rows do not leak in under INVOKER + inherited RLS'
);
select is(
  pfin.fn_compute_tax_liability('2026-08-15'::date)->'jurisdictions'->'federal'->'status',
  '"unavailable"'::jsonb,
  '(L16c) B''s federal.status = unavailable (no schedule of any type/year exists for B)'
);
select is(
  pfin.fn_compute_tax_liability('2026-08-15'::date)->'jurisdictions'->'federal'->'reason',
  '"no_schedule_any_year"'::jsonb,
  '(L16d) B''s federal.reason = no_schedule_any_year, and NOT zeros (Sec M-11)'
);
select ok(
  not (pfin.fn_compute_tax_liability('2026-08-15'::date)->'jurisdictions'->'federal' ? 'applied_marginal_rate')
  and not (pfin.fn_compute_tax_liability('2026-08-15'::date)->'jurisdictions'->'california' ? 'applied_marginal_rate'),
  '(L16e) applied_marginal_rate is OMITTED ENTIRELY (key absent, not null, not 0) on BOTH of B''s unavailable jurisdictions (E26 ruling 5)'
);
select is(
  pfin.fn_compute_tax_liability('2026-08-15'::date)->'nav_components',
  '{"realized_tax_liab":{"status":"unavailable","reason":"no_schedule_any_year"},"unrealized_tax_liab":{"status":"unavailable","reason":"no_schedule_any_year"}}'::jsonb,
  '(L16f) B''s nav_components: BOTH scalars unavailable/no_schedule_any_year -- the bootstrap default state, never a coalesced 0'
);
select is(
  pfin.fn_compute_tax_liability('2026-08-15'::date)->'decomposition'->'capital_gains',
  '{"status":"unavailable","reason":"no_sale_recording_capability"}'::jsonb,
  '(L16g) B''s capital_gains is the SAME structural-unavailable shape as A''s (L3a) -- independent of any other data B has or lacks'
);

select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
select is(
  (pfin.fn_compute_tax_liability('2026-08-15'::date)->'decomposition'->'ordinary_income'->>'total')::numeric,
  4001.0000::numeric,
  '(L16h) A''s total is STILL 4001.0000 with B''s row ALSO present in the database -- symmetric leak-free proof, re-read after L16a-g touched B''s context'
);

-- =====================================================================
-- L17 — CATALOG POSTURE + exactly one overload.
-- =====================================================================
select set_config('role', 'postgres', true);

select is(
  (select array[p.prosecdef::text, p.provolatile::text, array_to_string(p.proconfig, ',')]
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_compute_tax_liability'),
  array['false', 's', 'search_path=""'],
  '(L17a) fn_compute_tax_liability(date) POSTURE: SECURITY INVOKER (prosecdef false), STABLE (provolatile s), search_path pinned empty'
);
select ok(
  not has_function_privilege('anon', 'pfin.fn_compute_tax_liability(date)', 'execute')
  and has_function_privilege('authenticated', 'pfin.fn_compute_tax_liability(date)', 'execute'),
  '(L17b) fn_compute_tax_liability(date) EXECUTE revoked from PUBLIC (anon denied), granted to authenticated only'
);
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_compute_tax_liability'),
  1,
  '(L17c) EXACTLY ONE overload of pfin.fn_compute_tax_liability -- the single-authored-copy signature (SELF-262 AC block header)'
);

-- =====================================================================
-- L18 — VOLATILITY PIN: the helper itself PLUS the five functions its own
-- header names (fn_cashflow_items, fn_account_unrealized_gl,
-- fn_ytd_paid_per_jurisdiction, fn_tax_authority_ledgers, fn_server_today)
-- all measure provolatile = 's'. ⚠ Two of these five (fn_tax_authority_
-- ledgers, fn_server_today) are NOT actually called anywhere in 104's own
-- SQL body -- confirmed by grep and by the header's OWN "NOT READ,
-- DELIBERATELY" / "no fn_server_today() call in the body" text a few lines
-- above the volatility section that names them as "callees". This leg pins
-- what the header instructs regardless; the header inaccuracy itself is
-- flagged in the hand-off, not silently corrected here.
-- =====================================================================
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin'
      and p.proname in ('fn_compute_tax_liability', 'fn_cashflow_items', 'fn_account_unrealized_gl',
                         'fn_ytd_paid_per_jurisdiction', 'fn_tax_authority_ledgers', 'fn_server_today')
      and p.provolatile = 's'),
  6,
  '(L18) all SIX named functions (the helper + the five its header names) measure provolatile = ''s'' -- the watcher for a future CREATE OR REPLACE silently un-pinning one'
);

-- =====================================================================
-- L19 — NO nav_daily reference in the catalog body (AC 1's structural
-- exclusion, read from pg_proc.prosrc, never from a header-comment grep).
-- =====================================================================
select ok(
  (select prosrc !~ 'nav_daily' from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_compute_tax_liability'),
  '(L19) pfin.fn_compute_tax_liability''s CATALOG BODY (pg_proc.prosrc) contains NO reference to nav_daily -- 051 calls this function, never the reverse'
);

-- =====================================================================
-- L20 — fn_compute_nav / fn_nav_composition BYTE-UNCHANGED. md5 pinned
-- against a clean sequential 001->103 control build (this branch,
-- 2026-09-04): fn_compute_nav(date) = c207483f5e786fb5e90a03212b2de5e0,
-- fn_compute_nav(date,boolean) = 9917963f130498c3614eb6d550f53f51 (matches
-- 102's OWN L10 pin -- 104 is a second migration confirming the same
-- value, since 104 does not touch this function either), fn_nav_composition
-- (date) = 2cc5453c8a258ec27969efc96773c78f.
-- =====================================================================
select is(
  (select md5(pg_get_functiondef(p.oid))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_compute_nav'
      and pg_get_function_arguments(p.oid) = 'p_as_of date'),
  'c207483f5e786fb5e90a03212b2de5e0',
  '(L20a) fn_compute_nav(date) is BYTE-UNCHANGED by 104'
);
select is(
  (select md5(pg_get_functiondef(p.oid))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_compute_nav'
      and pg_get_function_arguments(p.oid) = 'p_as_of date, p_active_only boolean'),
  '9917963f130498c3614eb6d550f53f51',
  '(L20b) fn_compute_nav(date,boolean) is BYTE-UNCHANGED by 104 -- matches 102''s own L10 pin, a second migration confirming the value'
);
select is(
  (select md5(pg_get_functiondef(p.oid))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_composition'),
  '2cc5453c8a258ec27969efc96773c78f',
  '(L20c) fn_nav_composition(date) is BYTE-UNCHANGED by 104 -- 051 calls THIS function''s output at read time (SELF-268), but 104 itself does not touch 051''s body'
);

select * from finish();
rollback;

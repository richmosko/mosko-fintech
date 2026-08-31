-- =====================================================================
-- Per-Wave battery — pfin.fn_historical_expenditures(p_as_of date) — the PRD
--   §2.3.4 Historical Expenditures series, inflation-normalized (SELF-255;
--   migration 096). Composes on pfin.fn_cashflow_items (093) for every ledger
--   row and on pfin.fn_cpi_u_index_for_period (066) for every CPI-U level;
--   restates neither. SECURITY INVOKER read-composition, no relation read of
--   its own beyond posting_prototype (one attribute lookup). Paired with the
--   migration in the SAME PR (verify-paired-artifacts discipline).
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/096_fn_historical_expenditures.sql,
--   commit 7280a3dda63c54fe0471f221621fc3df1c841dfc on feature/self-255, blob
--   md5 b5748e739c4c8061b83157483676d0cd (self-computed via `git show
--   <sha>:<path> | md5`, not taken from a report). Drafted against the
--   migration's own CONTRACT / ZERO ROW vs NO ROW / ROLLING WINDOW / BASIS /
--   SCOPE / SIGN CONVENTION blocks and the SELF-255 re-derived AC block (read
--   live on Linear at authoring time, 2026-08-30) — NOT against architect's own
--   nine scratch legs, per QA's independent-re-establishment mandate.
--
--   Contract as landed:
--     returns table (month_end date, expense_monthly_nominal numeric,
--       expense_monthly_inflation_adjusted numeric,
--       rolling_12mo_avg_inflation_adjusted numeric, cpi_period date,
--       cpi_value numeric, cpi_is_carried boolean, cpi_carried_from date,
--       cpi_period_was_due boolean, cpi_nonpublication_on_record boolean,
--       cpi_coverage_through date)
--     SECURITY INVOKER · STABLE · set search_path = ''
--     Window: trailing 60 COMPLETE calendar months ending at the last
--       month_end <= p_as_of. Dense interior / no leading pad / dense trailing
--       pad to D. Sign: outflow-POSITIVE (default-and-notify, ADR-063
--       Decision 3 — reversible in the sign_convention CTE alone). Scope:
--       reader cat='Expense' minus resolved is_tax_payment=true. Deflator:
--       nominal x (cpi at coverage_through / cpi at cpi_period), NULL (never
--       0) when either leg is non-positive/absent. Rolling: 12-constituent
--       mean over a RANGE(month_ord) frame, NULL on <12 constituents OR any
--       NULL constituent.
--
-- ┌─ WHAT THIS BATTERY PROVES — one line per pinned architect decision ───────────────┐
-- │ (1) DENSITY   dense interior (a no-activity month INSIDE the span emits a ZERO    │
-- │               row) · no leading pad (nothing before the first qualifying month)   │
-- │               · dense trailing pad (zero rows continue to D after the last real   │
-- │               activity) · zero-rows-total (no qualifying activity anywhere in the │
-- │               window -> literally zero rows, not an error, not an all-zero row).  │
-- │ (2) SIGN      outflow-positive on an ordinary month; NEGATIVE (never abs()) on a  │
-- │               refund-dominated month.                                            │
-- │ (3) FRAME     RANGE over the integer month ordinal, not ROWS — a structural       │
-- │               source-text leg PLUS a standalone mechanism proof (the frames       │
-- │               diverge under a manufactured ordinal gap; see (RF) below for why    │
-- │               this cannot be driven through the real function).                  │
-- │ (4) NULL-PROP any NULL constituent poisons EVERY 12-month window containing it —  │
-- │               proven across three regimes in one fixture: <12 constituents, a     │
-- │               poisoned-but-full-count window, and a clean recovered window once   │
-- │               the poison ages out past the 12-month frame.                        │
-- │ (5) PRE-CPI   months before the CPI store's leading edge emit nominal intact,     │
-- │               adjusted/rolling NULL, with provenance columns present (and an      │
-- │               EMPTY store distinguished by coverage_through ALSO going NULL).     │
-- │ (6) TAX       an is_tax_payment=true Expense row is excluded from the sum; the    │
-- │               same month's non-tax Expense row is not.                           │
-- │ (7) BOUNDARY  the reader's half-open as-of bound (transaction_date<=D AND         │
-- │               created_at<D+1) is proven THROUGH this composer, not just at 093 — │
-- │               a row created ON D's last instant counts; one created at D+1        │
-- │               00:00:00 does not, on the SAME calendar day and SAME month.         │
-- │ (T)/(X) two-tenant non-vacuous (same month, different tenant, different nominal)  │
-- │         plus cross-tenant isolation (A sees none of B's marker value; B sees      │
-- │         exactly its own single row, never A's 20).                               │
-- │ (DS)    DIVISION SAFETY — an empty CPI store (066's own NULL-period raise never   │
-- │         reached) and a corrupted zero CPI print (096's OWN case-guard, not just   │
-- │         066's) both degrade to NULL, never a raise, never 0, never a poisoned     │
-- │         leak.                                                                    │
-- │ (WF)    the 60-month floor truncates: an expense far outside the window never     │
-- │         surfaces and never moves the anchor.                                     │
-- │ (P)/(A) SECURITY INVOKER posture pin + ACL (authenticated yes; PUBLIC / '''       │
-- │         service_role no) + NULL p_as_of fails closed (zero rows, no raise).       │
-- └─────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ ⚠ (RF) SCOPE DISCLOSURE — the RANGE-vs-ROWS frame discriminator CANNOT be driven ─┐
-- │ through the real function as an assertion-with-a-watcher on THIS surface, and that │
-- │ is recorded here rather than silently worked around. The density decision (1)      │
-- │ makes the month_ord sequence contiguous BY CONSTRUCTION (generate_series steps one │
-- │ calendar month at a time from ms_first to ms_last with no skip) — so there is no   │
-- │ fixture that produces a real ordinal gap for the real function to react to; RANGE  │
-- │ and ROWS are behaviourally IDENTICAL over a contiguous series. (RF-struct) below   │
-- │ pins the source text (the decision as WRITTEN); (RF-mech) is a standalone SQL      │
-- │ window-function demonstration — architect's own measured numbers (ordinals 1..11  │
-- │ then 25: ROWS counts 12, RANGE counts 1) — proving the HAZARD the frame choice     │
-- │ guards against is real, independent of this function, mirroring 067's (V2)        │
-- │ division-by-zero-hazard-proven-real pattern. Reported to team-lead as the one      │
-- │ property this file could not attach a direct watcher to.                          │
-- └─────────────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3 / DEFINER ALLOWLIST — this battery introduces NO catalogued
--   instance and changes none. 096 authors ONE function, SECURITY INVOKER, reached by
--   `authenticated` over PostgREST; no credential, no container, no admission endpoint
--   in its path, and it creates no column of any kind (no FK-shaped reference to
--   matched-tenant-validate). No count is restated here — read ADR-011 Decision 3 and
--   Decision 4 LIVE at the canonical anchor at merge time, not from this comment.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants via _rls.tenant_a() /
--   _rls.tenant_b() / _rls.tenant_c() (the third for the zero-activity leg). NO PII /
--   NO real account numbers / NO production data. Every dollar figure and CPI print is
--   an invented round number. cpi_u_index is GLOBAL — normalized to a known shape via
--   `delete from pfin.cpi_u_index` inside the rolled-back transaction before seeding
--   (mirrors 064/066/067: an assertion about the leading/trailing edge depends on
--   every row in the table, not just what this file wrote). All in begin…rollback; no
--   `supabase db reset` at any point.
--
-- ⚠ Sec joint-review MANDATORY per the migration's own header (two independent
--   triggers: a financial calculation on the §2.3 money path, and a DEFLATOR layered
--   over it). This file is QA's half of that review's evidence; it does not
--   substitute for it.
--
-- plan(36) — (FP: 2 fixture pins) + (BOUND/FORMULA: 1 ten-column anchor, arithmetic +
--   as-of boundary + provenance in one shot) + (T/X: 2 two-tenant non-vacuous + 3
--   cross-tenant isolation) + (DENSITY: 1 no-leading-pad + 1 interior-zero + 1
--   trailing-pad + 2 zero-rows-total + 1 window-floor) + (SIGN: 2) + (TAX: 1) +
--   (ROLLING: 1 fewer-than-12 aggregate + 1 poisoned-pinpoint + 1 poisoned aggregate +
--   2 clean-recovered independent-computation) + (FRAME: 2 structural + 2 mechanism) +
--   (DIVISION SAFETY: 2 empty-store + 2 corrupt-the-control) + (POSTURE: 1) + (ACL: 3)
--   + (NULL p_as_of: 2). Verify with `pg_prove`, never bare `psql` (plan-count
--   enforcement is TAP-aware-consumer-only).
-- =====================================================================

begin;

-- shared cross-tenant verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(36);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset
\set d_asof '2026-09-30'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc');

-- =====================================================================
-- FIXTURE — one 20-month dense series for A (2025-02 .. 2026-09, D=2026-09-30 is
--   itself a month-end so September is its own last complete month), a single-month
--   series for B (the two-tenant/cross-tenant referent), and a no-activity account for
--   C (the zero-rows-total referent).
-- =====================================================================
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-a255', 'depository', 'household', 'taxable')
  returning account_id as accta \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'acct-b255', 'depository', 'household', 'taxable')
  returning account_id as acctb \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tc', 'acct-c255', 'depository', 'household', 'taxable')
  returning account_id as acctc \gset

insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Expense', 'Misc255A', false) returning id as a_exp \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Expense', 'TaxPmt255A', true) returning id as a_tax \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'tb', 'Expense', 'Misc255B', false) returning id as b_exp \gset

-- ---------------------------------------------------------------------
-- A's 20-month series. One qualifying transaction per month except: 2025-03 (row 2,
-- deliberately NO transaction — the interior-zero leg), 2025-05 (row 4, two
-- transactions — the tax-exclusion leg), 2025-06 (row 5, two transactions — the
-- refund-dominated sign leg), 2026-08 (row 19, deliberately NO transaction — the
-- trailing-pad leg after the last real activity). created_at is explicit
-- (transaction_date + 1 day) throughout except the AC7 boundary pair at row 20,
-- comfortably inside D+1 (D=2026-09-30) — the 093 lesson that a default `now()`
-- created_at is invisible to any past as-of, byte-identical to a broken function.
-- ---------------------------------------------------------------------
-- row 1 — 2025-02 (the anchor: the FIRST qualifying month in the 60-month window)
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2025-02-15', -100, 'v255r1', '255 row1 anchor month', '2025-02-16')
  returning trans_id as t1 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t1, :a_exp);

-- row 2 — 2025-03: NO transaction (interior zero)

-- row 3 — 2025-04
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2025-04-15', -50, 'v255r3', '255 row3', '2025-04-16')
  returning trans_id as t3 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t3, :a_exp);

-- row 4 — 2025-05: TAX EXCLUSION leg. nontax -80 counts; tax-payment -40 must not.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2025-05-15', -80, 'v255r4nontax', '255 row4 nontax expense', '2025-05-16')
  returning trans_id as t4a \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t4a, :a_exp);
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2025-05-16', -40, 'v255r4tax', '255 row4 tax payment (MUST be excluded)', '2025-05-17')
  returning trans_id as t4b \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t4b, :a_tax);

-- row 5 — 2025-06: REFUND-DOMINATED SIGN leg. -20 expense + +80 refund = +60 net
-- ledger-signed -> nominal = -1 * 60 = -60 (NEGATIVE — never abs()'d).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2025-06-10', -20, 'v255r5exp', '255 row5 ordinary expense', '2025-06-11')
  returning trans_id as t5a \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t5a, :a_exp);
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2025-06-20', 80, 'v255r5refund', '255 row5 refund exceeding the month''s spend', '2025-06-21')
  returning trans_id as t5b \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t5b, :a_exp);

-- row 6 — 2025-07
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2025-07-15', -30, 'v255r6', '255 row6', '2025-07-16')
  returning trans_id as t6 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t6, :a_exp);

-- row 7 — 2025-08: the LAST month before the CPI store's leading edge (2025-09-01).
-- This is the NULL-propagation poison source (rolling windows 12 rows via rows 7..18
-- carry it; windows from row 19 on do not).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2025-08-15', -70, 'v255r7', '255 row7 last before-CPI-coverage month', '2025-08-16')
  returning trans_id as t7 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t7, :a_exp);

-- rows 8..18 — 2025-09 .. 2026-07, uniform -100/mo, all inside CPI coverage.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2025-09-15', -100, 'v255r8',  '255 row8',  '2025-09-16') returning trans_id as t8  \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2025-10-15', -100, 'v255r9',  '255 row9',  '2025-10-16') returning trans_id as t9  \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2025-11-15', -100, 'v255r10', '255 row10', '2025-11-16') returning trans_id as t10 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2025-12-15', -100, 'v255r11', '255 row11', '2025-12-16') returning trans_id as t11 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2026-01-15', -100, 'v255r12', '255 row12 first-12-constituents (still poisoned)', '2026-01-16') returning trans_id as t12 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2026-02-15', -100, 'v255r13', '255 row13', '2026-02-16') returning trans_id as t13 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2026-03-15', -100, 'v255r14', '255 row14', '2026-03-16') returning trans_id as t14 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2026-04-15', -100, 'v255r15', '255 row15', '2026-04-16') returning trans_id as t15 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2026-05-15', -100, 'v255r16', '255 row16', '2026-05-16') returning trans_id as t16 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2026-06-15', -100, 'v255r17', '255 row17', '2026-06-16') returning trans_id as t17 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2026-07-15', -100, 'v255r18', '255 row18 last row still poisoned', '2026-07-16') returning trans_id as t18 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values
  (:t8, :a_exp), (:t9, :a_exp), (:t10, :a_exp), (:t11, :a_exp), (:t12, :a_exp),
  (:t13, :a_exp), (:t14, :a_exp), (:t15, :a_exp), (:t16, :a_exp), (:t17, :a_exp), (:t18, :a_exp);

-- row 19 — 2026-08: NO transaction (dense TRAILING pad after the last real activity,
-- still inside the window and strictly before D).

-- row 20 — 2026-09 (D's own month, D IS the month-end). AC7 AS-OF BOUNDARY PAIR: one
-- transaction created within D (INCLUDED), one created exactly at D+1 00:00:00
-- (EXCLUDED) — proven THROUGH this composer, not just at 093's reader battery.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, :'d_asof'::date, -7, 'v255r20in', '255 row20 created within D (INCLUDED)', '2026-09-30 23:59:59+00')
  returning trans_id as t20in \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, :'d_asof'::date, -13, 'v255r20out', '255 row20 created at D+1 00:00:00 (EXCLUDED)', '2026-10-01 00:00:00+00')
  returning trans_id as t20out \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t20in, :a_exp), (:t20out, :a_exp);

-- WINDOW-FLOOR (WF) — an expense far outside the 60-month window (floor is
-- 2021-10-01; this is 2019, well before it). Must never surface and must never move
-- the anchor backward from row 1's 2025-02.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2019-06-15', -9999, 'v255wf', '255 window-floor stray, must be truncated', '2019-06-16')
  returning trans_id as twf \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:twf, :a_exp);

-- ---------------------------------------------------------------------
-- B — a single qualifying transaction, SAME month as A's row 20 (D's month), a
-- DIFFERENT value (the two-tenant non-vacuity pair) and a value (500) A never uses
-- anywhere (the cross-tenant leak canary).
-- ---------------------------------------------------------------------
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:acctb, :'d_asof'::date, -500, 'v255b', '255 tenant B sole transaction', '2020-01-02')
  returning trans_id as tb1 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:tb1, :b_exp);

-- C — account exists, zero transactions (the zero-rows-total referent).

-- ---------------------------------------------------------------------
-- cpi_u_index — GLOBAL, normalized to a known shape. Leading edge 2025-09-01
-- (300.000), one print per month through 2026-09-01 (312.000), trailing/coverage
-- edge 2026-10-01 (313.000 — the basis every figure is restated into).
-- ---------------------------------------------------------------------
delete from pfin.cpi_u_index;
insert into pfin.cpi_u_index (cpi_period, cpi_value) values
  ('2025-09-01', 300.000), ('2025-10-01', 301.000), ('2025-11-01', 302.000),
  ('2025-12-01', 303.000), ('2026-01-01', 304.000), ('2026-02-01', 305.000),
  ('2026-03-01', 306.000), ('2026-04-01', 307.000), ('2026-05-01', 308.000),
  ('2026-06-01', 309.000), ('2026-07-01', 310.000), ('2026-08-01', 311.000),
  ('2026-09-01', 312.000), ('2026-10-01', 313.000);

-- =====================================================================
-- (FP) FIXTURE PINS — every downstream claim about "before coverage" / "the basis"
--   is a claim ABOUT these two facts.
-- =====================================================================
select is(
  (select min(cpi_period) from pfin.cpi_u_index), '2025-09-01'::date,
  '(FP1) fixture pin: CPI leading edge = 2025-09-01 — rows 1..7 (2025-02..2025-08) are all strictly before it'
);
select ok(
  (select cpi_value = 313.000 from pfin.cpi_u_index where cpi_period = (select max(cpi_period) from pfin.cpi_u_index)),
  '(FP2) fixture pin: CPI trailing/coverage edge = 2026-10-01, value 313.000 — the basis every adjusted figure is restated into'
);

-- =====================================================================
-- (BOUND/FORMULA) row 20 (D's own month, 2026-09-30). Proves in ONE row: the AC7
--   as-of boundary (nominal=7, NOT 20 — the D+1-created transaction never counted),
--   the deflator arithmetic (7 * 313.000/312.000, computed independently of the
--   function under test), and every CPI provenance column. rolling_12mo is checked
--   SEPARATELY below (ROLL4) since it is a 12-month average, not a per-row fact.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select results_eq(
  $$ select month_end, expense_monthly_nominal, round(expense_monthly_inflation_adjusted, 6),
            cpi_period, cpi_value, cpi_is_carried, cpi_carried_from, cpi_period_was_due,
            cpi_nonpublication_on_record, cpi_coverage_through
       from pfin.fn_historical_expenditures('2026-09-30') where month_end = '2026-09-30' $$,
  $$ values ('2026-09-30'::date, 7::numeric, round(7 * 313.000/312.000, 6),
             '2026-09-01'::date, 312.000::numeric, false, '2026-09-01'::date, true,
             false, '2026-10-01'::date) $$,
  '(BOUND/F1) ⭐ nominal=7 (ONLY the created-within-D transaction; the D+1-created one is invisible), and the deflator ratio computed independently of the function under test — RED if either the boundary or the arithmetic drifts'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (T)/(X) TWO-TENANT NON-VACUOUS + CROSS-TENANT ISOLATION.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  $$ select * from pfin.fn_historical_expenditures('2026-09-30') $$,
  '(X1) A''s full call does not raise'
);
select is(
  (select count(*)::int from pfin.fn_historical_expenditures('2026-09-30')),
  20,
  '(X1b) A sees exactly its own 20 dense rows (2025-02..2026-09) — not fewer (over-restrictive) and not more (leaked)'
);
select is(
  (select count(*)::int from pfin.fn_historical_expenditures('2026-09-30') where expense_monthly_nominal = 500),
  0,
  '(X2) ⭐ CROSS-TENANT LEAK CANARY: no row of A''s ever carries B''s unique marker value (500)'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'tb'::uuid);
select lives_ok(
  $$ select * from pfin.fn_historical_expenditures('2026-09-30') $$,
  '(X3) B''s call does not raise'
);
select results_eq(
  $$ select month_end, expense_monthly_nominal from pfin.fn_historical_expenditures('2026-09-30') $$,
  $$ values ('2026-09-30'::date, 500::numeric) $$,
  '(T1) ⭐ THE NON-VACUITY THAT MAKES ISOLATION A TEST: B sees EXACTLY one row (the SAME month as A''s row 20), with a DIFFERENT nominal (500, not 7/20) — results_eq fails if B saw any of A''s 20 rows too, so this is simultaneously the two-tenant non-vacuous pair and the isolation boundary'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (DENSITY) no-leading-pad, interior zero, trailing pad, zero-rows-total, window
--   floor.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select min(month_end) from pfin.fn_historical_expenditures('2026-09-30')),
  '2025-02-28'::date,
  '(Z1) NO-LEADING-PAD: the earliest row is row1''s own month (2025-02) — nothing before it, even though the 60-month floor reaches back to 2021-10'
);
select results_eq(
  $$ select month_end, expense_monthly_nominal from pfin.fn_historical_expenditures('2026-09-30') where month_end = '2025-03-31' $$,
  $$ values ('2025-03-31'::date, 0::numeric) $$,
  '(Z2) ⭐ DENSE INTERIOR: the no-activity month BETWEEN two real months (2025-03) is EMITTED as a ZERO row, not dropped — results_eq fails outright if the row were missing'
);
select results_eq(
  $$ select month_end, expense_monthly_nominal from pfin.fn_historical_expenditures('2026-09-30') where month_end = '2026-08-31' $$,
  $$ values ('2026-08-31'::date, 0::numeric) $$,
  '(Z3) ⭐ DENSE TRAILING PAD: the no-activity month AFTER the last real activity (2026-07) but before D (2026-08) is still EMITTED as a ZERO row, all the way to D'
);
select is(
  (select count(*)::int from pfin.fn_historical_expenditures('2026-09-30') where expense_monthly_nominal = 9999),
  0,
  '(WF) ⭐ WINDOW FLOOR: the 2019 stray expense (far outside the 60-month window) never surfaces — its value never appears in any row'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'tc'::uuid);
select lives_ok(
  $$ select * from pfin.fn_historical_expenditures('2026-09-30') $$,
  '(Z4a) ZERO-ROWS-TOTAL: a tenant with an account but NO qualifying activity anywhere in the window does not raise'
);
select is(
  (select count(*)::int from pfin.fn_historical_expenditures('2026-09-30')),
  0,
  '(Z4b) ⭐ …and returns LITERALLY ZERO ROWS — not a single all-zero row, not an error. This is the state a leading-pad implementation could not produce (it would fabricate 60 zero rows instead)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (SIGN) outflow-positive ordinary month; refund-dominated NEGATIVE month (never
--   abs()'d).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select expense_monthly_nominal from pfin.fn_historical_expenditures('2026-09-30') where month_end = '2025-11-30'),
  100::numeric,
  '(SIGN1) ordinary month: outflow-POSITIVE (raw ledger -100 -> nominal +100)'
);
select is(
  (select expense_monthly_nominal from pfin.fn_historical_expenditures('2026-09-30') where month_end = '2025-06-30'),
  -60::numeric,
  '(SIGN2) ⭐ REFUND-DOMINATED month renders NEGATIVE (-60), never abs()''d to a false spending spike — a refund (+80) exceeding the month''s spend (-20) is a real, informative negative bar'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (TAX) is_tax_payment=true Expense row excluded; the same month's non-tax row is not.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select expense_monthly_nominal from pfin.fn_historical_expenditures('2026-09-30') where month_end = '2025-05-31'),
  80::numeric,
  '(TAX1) ⭐ the tax-payment leg (-40) is excluded from the sum: nominal is 80 (the nontax leg alone), never 120 (both legs)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (ROLLING) three regimes in one fixture: fewer-than-12 constituents, a poisoned
--   full-count window, and a clean recovered window once the poison ages out.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*)::int from pfin.fn_historical_expenditures('2026-09-30')
     where month_end between '2025-02-28' and '2025-12-31' and rolling_12mo_avg_inflation_adjusted is null),
  11,
  '(ROLL1) fewer-than-12-constituents: all 11 of rows 1..11 (2025-02..2025-12) have a NULL rolling average'
);
select ok(
  (select rolling_12mo_avg_inflation_adjusted is null from pfin.fn_historical_expenditures('2026-09-30') where month_end = '2026-01-31'),
  '(ROLL2a) ⭐ row 12 (2026-01) is the FIRST row with exactly 12 constituents available, and it is STILL NULL: the poison (row7, before CPI coverage) fires immediately, not a leftover "still short" false read'
);
select is(
  (select count(*)::int from pfin.fn_historical_expenditures('2026-09-30')
     where month_end between '2026-01-31' and '2026-07-31' and rolling_12mo_avg_inflation_adjusted is null),
  7,
  '(ROLL2b) all 7 of rows 12..18 (2026-01..2026-07) stay poisoned — averaging the 11 survivors and calling it a 12-month average is exactly the silently-short window the RANGE frame exists to prevent'
);
select is(
  (select round(rolling_12mo_avg_inflation_adjusted, 6) from pfin.fn_historical_expenditures('2026-09-30') where month_end = '2026-08-31'),
  (select round(avg(x.nominal * 313.000 / c.cpi_value), 6)
     from (values
       ('2025-09-01'::date,100),('2025-10-01',100),('2025-11-01',100),('2025-12-01',100),
       ('2026-01-01',100),('2026-02-01',100),('2026-03-01',100),('2026-04-01',100),
       ('2026-05-01',100),('2026-06-01',100),('2026-07-01',100),('2026-08-01',0)
     ) as x(period, nominal)
     join pfin.cpi_u_index c on c.cpi_period = x.period),
  '(ROLL3) ⭐ CLEAN RECOVERED WINDOW: row 19 (2026-08)''s 12-month window (2025-09..2026-08) no longer includes the poisoned row7 — a REAL average, computed independently against the CPI store and this fixture''s own known nominal values, not a hand-typed literal'
);
select is(
  (select round(rolling_12mo_avg_inflation_adjusted, 6) from pfin.fn_historical_expenditures('2026-09-30') where month_end = '2026-09-30'),
  (select round(avg(x.nominal * 313.000 / c.cpi_value), 6)
     from (values
       ('2025-10-01'::date,100),('2025-11-01',100),('2025-12-01',100),('2026-01-01',100),
       ('2026-02-01',100),('2026-03-01',100),('2026-04-01',100),('2026-05-01',100),
       ('2026-06-01',100),('2026-07-01',100),('2026-08-01',0),('2026-09-01',7)
     ) as x(period, nominal)
     join pfin.cpi_u_index c on c.cpi_period = x.period),
  '(ROLL4) row 20 (D''s own month, 2026-09)''s 12-month window (2025-10..2026-09) is also clean — independently computed, including the AC7-boundary-proven nominal (7) for its own month'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (RF) RANGE-vs-ROWS frame discriminator. See the header SCOPE DISCLOSURE for why
--   this cannot be driven through the real function (density makes a real ordinal
--   gap unreachable) — (RF-struct) pins the source text, (RF-mech) proves the hazard
--   the text choice guards against is real, at the SQL level, independent of 096.
-- =====================================================================
select ok(
  (select p.prosrc ~* 'range\s+between\s+11\s+preceding\s+and\s+current\s+row'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_historical_expenditures'),
  '(RF-struct-1) the stored source carries the literal `range between 11 preceding and current row` frame clause'
);
select ok(
  (select p.prosrc !~* 'rows\s+between'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_historical_expenditures'),
  '(RF-struct-2) …and NO `rows between` frame appears anywhere in the source'
);
select is(
  (select cnt from (
     select ord, count(*) over (order by ord range between 11 preceding and current row) as cnt
       from (values (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(25)) v(ord)
   ) w where ord = 25)::int,
  1,
  '(RF-mech-1) ⭐ MECHANISM PROOF, independent of 096, using REAL window-function frames: over the manufactured ordinal series {1..11, 25} (a gap standing in for a density failure), a RANGE(11 preceding, current row) frame AT THE ordinal-25 ROW admits only ordinal 25 itself (25-11=14 > every earlier ordinal) — COUNT 1, which is what makes the NULL guard fire on a real gap'
);
select is(
  (select cnt from (
     select ord, count(*) over (order by ord rows between 11 preceding and current row) as cnt
       from (values (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(25)) v(ord)
   ) w where ord = 25)::int,
  12,
  '(RF-mech-2) ⭐ …whereas a ROWS(11 preceding, current row) frame AT THE SAME ordinal-25 row counts twelve physical ROWS regardless of the 13-ordinal gap they span — architect''s measured "ROWS counts 12, RANGE counts 1": exactly the silently-short window the RANGE choice exists to prevent'
);

-- =====================================================================
-- (DS) DIVISION SAFETY — empty CPI store (066's NULL-period raise must never be
--   reached), then a corrupted zero CPI print (096's OWN case-guard, not 066's).
--   Both savepoint-scoped; both leave the main fixture intact for legs after.
-- =====================================================================
savepoint empty_cpi;
delete from pfin.cpi_u_index;
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  $$ select * from pfin.fn_historical_expenditures('2026-09-30') $$,
  '(DS-empty-1) ⭐ an EMPTY cpi_u_index does NOT raise — THE LEG THAT FIRES IF THE `if v_coverage is not null` GUARD IS EVER REMOVED: 066 raises when asked to resolve a period against a NULL period argument, and coverage_through is NULL on an empty store'
);
select ok(
  (select expense_monthly_nominal = 100
          and expense_monthly_inflation_adjusted is null
          and rolling_12mo_avg_inflation_adjusted is null
          and cpi_value is null
          and cpi_coverage_through is null
     from pfin.fn_historical_expenditures('2026-09-30') where month_end = '2025-02-28'),
  '(DS-empty-2) ⭐ …nominal STILL passes through intact (100) while adjusted/rolling/cpi_value are NULL and cpi_coverage_through is ALSO NULL — distinguishing "the store is empty" from the ordinary "before this store''s coverage" case, where coverage_through stays populated'
);
select set_config('role', 'postgres', true);
rollback to savepoint empty_cpi;

savepoint poison_cpi;
alter table pfin.cpi_u_index
  drop constraint cpi_u_index_value_positive_finite,
  drop constraint cpi_u_index_value_finite;
update pfin.cpi_u_index set cpi_value = 0 where cpi_period = '2025-09-01';
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  $$ select * from pfin.fn_historical_expenditures('2026-09-30') $$,
  '(DS-poison-1) corrupt-the-control: a ZERO CPI print at a real resolvable period, both table CHECKs dropped, does not raise — 096''s OWN case-guard, not 066''s and not the table CHECK, is what holds here'
);
select results_eq(
  $$ select month_end, expense_monthly_nominal, expense_monthly_inflation_adjusted, cpi_value
       from pfin.fn_historical_expenditures('2026-09-30') where month_end = '2025-09-30' $$,
  $$ values ('2025-09-30'::date, 100::numeric, null::numeric, 0::numeric) $$,
  '(DS-poison-2) ⭐ THE ROW EXISTS (results_eq, not a scalar is()-on-NULL that would pass vacuously against a dropped row): adjusted NULL, nominal 100 intact, the poisoned 0 still surfaced — never a raise, never a fabricated 0-as-adjusted, never a sign-flip'
);
select set_config('role', 'postgres', true);
rollback to savepoint poison_cpi;

-- =====================================================================
-- (POSTURE)/(ACL) SECURITY INVOKER pin + EXECUTE grants.
-- =====================================================================
select is(
  (select array[p.prosecdef::text, p.provolatile::text, array_to_string(p.proconfig, ',')]
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_historical_expenditures'),
  array['false','s','search_path=""'],
  '(POSTURE) ⭐ read DECLARATIVELY from the catalog, the 067 (ADR2) three-element form: SECURITY INVOKER (prosecdef false — the migration''s own posture rationale, DEFINER here would sever the posting_prototype join from the RLS that makes it safe), STABLE (provolatile s), search_path pinned empty. Behaviour alone cannot distinguish INVOKER from a DEFINER owned by a non-privileged role — only the catalog can'
);
select ok(
  has_function_privilege('authenticated', 'pfin.fn_historical_expenditures(date)', 'execute'),
  '(A1) authenticated HOLDS EXECUTE'
);
select ok(
  not has_function_privilege('public', 'pfin.fn_historical_expenditures(date)', 'execute'),
  '(A2) LOAD-BEARING: PUBLIC does NOT — `create function` grants EXECUTE to PUBLIC by default, so the revoke is load-bearing and silent on removal'
);
select ok(
  not has_function_privilege('service_role', 'pfin.fn_historical_expenditures(date)', 'execute'),
  '(A3) service_role does NOT hold EXECUTE — this is a pure INVOKER read surface with no worker-side caller'
);

-- =====================================================================
-- (NULL) a NULL p_as_of fails closed: zero rows, never a raise.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  $$ select * from pfin.fn_historical_expenditures(null) $$,
  '(NULLp-1) a NULL p_as_of does not raise'
);
select is(
  (select count(*)::int from pfin.fn_historical_expenditures(null)),
  0,
  '(NULLp-2) …and returns ZERO ROWS — every date comparison against a NULL p_as_of is NULL, so the reader itself already fails closed and generate_series with a NULL bound emits nothing'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;

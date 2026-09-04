-- =====================================================================
-- Per-Wave battery — pfin.fn_compute_tax_liability, the §2.5 keystone read
--   helper (SELF-262; migration 104). Paired with the migration in the SAME
--   PR (verify-paired-artifacts discipline). Companion to SELF-269's own
--   two-tenant extension — this file covers the fences 104 itself owns.
--   SECOND PASS (this file): re-cut after Sec's AMBER
--   (docs/records/v14-execution/self262-sec-findings.md) and the Architect
--   fixes it drove — F-1 (LT CG empty-no-fallback OR-term), F-2
--   (standard_deduction_ignored on the LT CG leg), F-3
--   (quarters_elapsed RENAMED to installments_due_through_next +
--   next_due_date, and its Dec-31 >= 4 branch going LIVE), N-2 (trunc, not
--   round, on the quarterly split), N-4 (jurisdiction basis_year gated on
--   computed), N-5 (rounded annual_liability). Every number below was
--   RECOMPUTED against the landed migration body, not carried from the
--   first-pass battery or from any dispatch note — see the F-2 note below
--   on why L5's own value moved.
--   THIRD PASS (this file): Sec's re-look at 5c9e0e6 found ONE blocking
--   condition, F-4 — the second pass's (N4) leg reused B's L16c/d federal
--   jurisdiction, where BOTH federal halves are unresolved, so
--   least(NULL, NULL) is NULL with or without the `computed` gate and the
--   leg could not fail. (N4) is re-pointed below onto its own tax_year
--   (2030) where exactly ONE federal half resolves. No other leg moved, no
--   migration change, plan count UNCHANGED at 60.
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
-- ⚠ F-2 CASCADE: 104's F-2 fix makes the LT CG walk subtract NOTHING from
--   the LT CG input, ever (PRD-verbatim, "no standard deduction applied to
--   this schedule"). Under the first-pass battery's own fixture (LT CG
--   input 1001, LT CG standard_deduction 1500) taxable_income.lt_cg used to
--   floor to 0 (SD wrongly subtracted); it is now 1001.0000 (SD never
--   subtracted), which cascades into every downstream federal number: L6a's
--   installments, L10's realized_tax_liab. The M-9 floor-at-zero property
--   itself is STILL REAL (greatest(taxable, 0) is unconditional in the
--   `targets` CTE) but is now UNREACHABLE via LT CG under any fixture where
--   inputs stay non-negative — the M9 leg below re-proves it on an ORDINARY
--   schedule instead, where the standard deduction is actually subtracted.
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
-- │ L5  F-2: federal LT-CG taxable_income.lt_cg = 1001.0000, the FULL input,  │
-- │       since the LT CG walk never subtracts the standard deduction.        │
-- │ F2  standard_deduction_ignored = true on federal.schedules.federal_lt_cg  │
-- │       (stored SD non-zero); key ABSENT on california.schedules (no LT CG  │
-- │       type there); false when no LT CG schedule resolves at all (B/F-1).  │
-- │ M9  the M-9 floor-at-zero property, re-proven on an ORDINARY schedule     │
-- │       (california, tenant B, 2027) since L5's LT CG case can no longer    │
-- │       reach it after F-2 (see F-2 CASCADE note above).                    │
-- │ L6  INSTALLMENTS / Q4 RESIDUAL, N-2 (trunc not round): federal's four     │
-- │       installments sum EXACTLY to round(annual,2); Q1=Q2=Q3 TRUNCATED,    │
-- │       Q4 carries the residual and is never negative by construction       │
-- │       (hand-verified exact cents against the F-2-cascaded 349.75 annual); │
-- │       california asserted structurally (independent hand-computed leg).  │
-- │ L7  APPLIED_MARGINAL_RATE present (both legs) when computed.              │
-- │ L8  YTD PAID: designated (federal, non-null amount) vs undesignated       │
-- │       (california, NULL not 0) in the SAME call; funds_due UNAVAILABLE/   │
-- │       ytd_paid_unavailable when ytd_paid is null and the schedule IS      │
-- │       resolved (computed=true).                                          │
-- │ L9  YTD-ZERO: a designated-but-empty ledger reads 0, not NULL — the       │
-- │       distinguishing half of L8 (E11's one-character design choice).      │
-- │ L10 REALIZED nav_component: UNAVAILABLE/ytd_paid_unavailable while one    │
-- │       jurisdiction's YTD is null; COMPUTED (sum of both funds_due gaps,   │
-- │       negative allowed, F-2-cascaded to -739.5300) once both designated.  │
-- │ L11 UNREALIZED CLAMP: a net-LOSS aggregate across TAXABLE accounts        │
-- │       (GL-backed cost basis, not a market-value-only numerator) clamps    │
-- │       to 0, never a negative liability.                                  │
-- │ L12 (π) EXCLUSION: a tax_deferred account's gain is excluded from the     │
-- │       Unrealized aggregate; moving it to taxable MOVES the figure by      │
-- │       exactly its own contribution — the inversion is the fixture, not a │
-- │       struck line.                                                       │
-- │ L13 F-3 RENAME: quarters_elapsed is GONE. installments_due_through_next   │
-- │       (the ordinal of the UPCOMING installment, capped at 4) + its paired │
-- │       next_due_date, swept across the same four boundaries: 1·2·3·4.      │
-- │ F3  F-3 BOUNDARY SET: Apr14→1, Apr15→1 (due-today still counts as         │
-- │       upcoming), Apr16→2, Dec31→4, next-tax-year Jan10→1 — each with its   │
-- │       next_due_date; plus the Dec-31 obligation_to_date >= 4 branch,       │
-- │       DEAD under the old metric and now LIVE, using the ROUNDED annual    │
-- │       rather than 4× the truncated quarter (differs by 3c, measured).      │
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
-- │ N4  jurisdictions.federal.basis_year is JSON null when the jurisdiction   │
-- │       is unavailable (LEAST ignores SQL NULLs; N-4's ungated bug) --      │
-- │       Sec F-4 THIRD PASS: re-pointed onto its OWN tax_year (2030) where   │
-- │       exactly ONE federal half resolves (federal_lt_cg), the only shape  │
-- │       that can tell gated-NULL apart from LEAST's ignore-NULLs default.  │
-- │ F1  current_year_schedule_empty = true on schedules.federal_lt_cg when a  │
-- │       current-year LT CG row is present-but-empty with NO prior-year      │
-- │       fallback (tenant B) — the identical situation to L15, one schedule  │
-- │       type over, that Sec's F-1 finding says the shipped code missed.      │
-- │ N2  the trunc-not-round fix at the boundary: annual 0.02 -> installments   │
-- │       [0.00,0.00,0.00,0.02] (never negative); annual 7532.98 -> three      │
-- │       equal 1883.24 truncated quarters + a 1883.26 Q4.                     │
-- │ L17 CATALOG POSTURE: prosecdef=f, provolatile=s, search_path='' pinned,   │
-- │       EXECUTE revoked PUBLIC / granted authenticated, EXACTLY ONE         │
-- │       overload by proname.                                               │
-- │ L18 VOLATILITY PIN, split in two per Sec's second-pass note: (a) the       │
-- │       PINNED set — the helper plus every function the header's           │
-- │       transitive-read-set diagram marks 's' — all measure provolatile=s;  │
-- │       (b) the two functions that diagram marks 'v' (fn_gl_entries,        │
-- │       fn_holdings_as_of) contain NO write statement in prosrc, the        │
-- │       property that backs calling them read-only. NOT a hard-coded        │
-- │       six-name list extended to eight (that count would be wrong and go   │
-- │       red for the wrong reason) — a shape change, not a bigger number.    │
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

-- plan = 60 (second pass, +15 over the first pass's 45): L1 2 · L2 1 ·
--   L3 2 · L4 2 · L5 1 · F2b/F2c 2 · M9 1 · L6 3 · L7 1 · L8 3 · L9 1 ·
--   L10 1 · L11 1 · L12 1 · L13 4 · F3(a-f) 6 · L14 3 · L15 3 · L16 8 ·
--   N4 1 · F1 1 · F2a 1 · N2(a-b) 2 · L17 3 · L18(a-b) 2 · L19 1 · L20 3.
select plan(60);

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

-- ---- F-1 / F-2a / N-4 (tenant B): a federal_lt_cg schedule PRESENT at the
--      SAME tax_year (2026) as B's other calls above, carrying ZERO bracket
--      rows and NO other federal_lt_cg row at any year -- present-but-empty
--      with no prior-year fallback, the case Sec's F-1 finding says the
--      shipped code answers wrong (identical to L15's shape, one schedule
--      type over). federal_ordinary stays absent for B throughout, so
--      federal remains `unavailable` regardless -- this exercises the
--      `schedules.federal_lt_cg` sub-object INSIDE an unavailable
--      jurisdiction, which nothing above ever inspects for B.
insert into pfin.tax_bracket_schedule (users_id, schedule_type, tax_year, standard_deduction, schedule_label)
  values (:'tb', 'federal_lt_cg', 2026, 0.0000, 'b-fed-ltcg-2026-empty-104');
-- (deliberately NO tax_bracket_row insert -- row_count stays 0)

-- ---- M9 (tenant B): the M-9 floor-at-zero property, re-proven on an
--      ORDINARY schedule (california_ordinary, tax_year 2027) now that F-2
--      makes L5's LT CG case unreachable for it. standard_deduction (100)
--      EXCEEDS the input (50) -> taxable floors at 0, never negative.
insert into pfin.tax_bracket_schedule (users_id, schedule_type, tax_year, standard_deduction, schedule_label)
  values (:'tb', 'california_ordinary', 2027, 100.0000, 'b-ca-ord-2027-m9-104')
  returning id as sch_b_m9 \gset
insert into pfin.tax_bracket_row (users_id, schedule_id, bracket_floor, bracket_rate)
  values (:'tb', :sch_b_m9, 0, 0.10);
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, created_at)
  values (:b_acct, '2027-01-10', 50.0000, 'b-m9-104', '2027-01-10'::timestamptz)
  returning trans_id as b_t_m9 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:b_t_m9, :b_sal);

-- ---- N-2 (tenant B): two crafted california_ordinary schedules, EACH its
--      OWN tax_year so the two calls cannot interact, a single bracket at
--      rate=1.00 (max legal, 101's CHECK) so annual_liability equals the
--      input EXACTLY -- 0.02 (the negative-Q4 boundary Sec measured) and
--      7532.98 (the boundary-adjacent large case), proving `trunc` rather
--      than `round` at both ends of the range.
insert into pfin.tax_bracket_schedule (users_id, schedule_type, tax_year, standard_deduction, schedule_label)
  values (:'tb', 'california_ordinary', 2029, 0.0000, 'b-ca-ord-2029-n2a-104')
  returning id as sch_b_n2a \gset
insert into pfin.tax_bracket_row (users_id, schedule_id, bracket_floor, bracket_rate)
  values (:'tb', :sch_b_n2a, 0, 1.00);
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, created_at)
  values (:b_acct, '2029-01-10', 0.0200, 'b-n2a-104', '2029-01-10'::timestamptz)
  returning trans_id as b_t_n2a \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:b_t_n2a, :b_sal);

insert into pfin.tax_bracket_schedule (users_id, schedule_type, tax_year, standard_deduction, schedule_label)
  values (:'tb', 'california_ordinary', 2028, 0.0000, 'b-ca-ord-2028-n2b-104')
  returning id as sch_b_n2b \gset
insert into pfin.tax_bracket_row (users_id, schedule_id, bracket_floor, bracket_rate)
  values (:'tb', :sch_b_n2b, 0, 1.00);
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, created_at)
  values (:b_acct, '2028-01-10', 7532.9800, 'b-n2b-104', '2028-01-10'::timestamptz)
  returning trans_id as b_t_n2b \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:b_t_n2b, :b_sal);
-- ⚠ NONE of the four schedule/tax_year additions above (2026 empty-LTCG,
--   2027, 2028, 2029) is <= 2026 in a way that changes any L16 assertion at
--   as_of 2026-08-15: `pick` requires tax_year <= p.tax_year, so the three
--   future-year CA rows are invisible at tax_year 2026, and the empty LT CG
--   row never resolves (row_count=0) so it cannot make federal `computed`.

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
  1001.0000::numeric,
  '(L5 / F-2) federal.taxable_income.lt_cg = 1001.0000, the FULL LT-CG input -- the stored 1500 standard_deduction on the federal_lt_cg schedule is NEVER subtracted (PRD-verbatim "no standard deduction applied to this schedule"), so it does not reduce this figure at all; this is the F-2 fix, and it CASCADES into L6a and L10 below'
);
select is(
  (pfin.fn_compute_tax_liability('2026-08-15'::date)->'jurisdictions'->'federal'->'schedules'->'federal_lt_cg'->>'standard_deduction_ignored')::boolean,
  true,
  '(F-2b) schedules.federal_lt_cg.standard_deduction_ignored = true -- the resolved LT CG schedule stores a NON-ZERO standard_deduction (1500), and the payload SAYS it was ignored rather than silently disagreeing with the user-entered value'
);
select ok(
  not (pfin.fn_compute_tax_liability('2026-08-15'::date)->'jurisdictions'->'california'->'schedules'->'california_ordinary' ? 'standard_deduction_ignored'),
  '(F-2c) california.schedules.california_ordinary carries NO standard_deduction_ignored key AT ALL -- california has no LT CG type (jur_def.ltcg_type is null for it), so the key does not exist for it, key-absent rather than false'
);

-- =====================================================================
-- M9 — the M-9 floor-at-zero property, re-proven on an ORDINARY schedule
-- (tenant B, california_ordinary, tax_year 2027) since F-2 makes L5's LT CG
-- case unreachable for it: standard_deduction (100) EXCEEDS the input (50).
-- =====================================================================
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  jsonb_build_object(
    'ordinary', (pfin.fn_compute_tax_liability('2027-06-01'::date)->'jurisdictions'->'california'->'taxable_income'->>'ordinary')::numeric,
    'annual',   (pfin.fn_compute_tax_liability('2027-06-01'::date)->'jurisdictions'->'california'->>'annual_liability')::numeric
  ),
  jsonb_build_object('ordinary', 0::numeric, 'annual', 0.00::numeric),
  '(M9) tenant B, california_ordinary 2027: standard_deduction (100) exceeds the input (50) -> taxable_income.ordinary floors to 0 and annual_liability = 0.00, never negative -- the same greatest(taxable, 0) mechanism L5 used to exercise before F-2, now proven on the schedule type that still reaches it'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);

select is(
  pfin.fn_compute_tax_liability('2026-08-15'::date)->'jurisdictions'->'federal'->'installments',
  '[{"quarter":1,"due_date":"2026-04-15","amount":87.43},{"quarter":2,"due_date":"2026-06-15","amount":87.43},{"quarter":3,"due_date":"2026-09-15","amount":87.43},{"quarter":4,"due_date":"2027-01-15","amount":87.46}]'::jsonb,
  '(L6a / F-2 cascade) federal.installments -- annual is now round(299.70 ordinary + 50.05 lt_cg, 2) = 349.75 (F-2''s taxable_income.lt_cg=1001 cascades here); Q1=Q2=Q3=trunc(349.75/4,2)=87.43, Q4=87.46 carries the residual so all four sum EXACTLY to 349.75 (E25/N-2); hand-verified exact cents'
);
select ok(
  (with j as (select pfin.fn_compute_tax_liability('2026-08-15'::date)->'jurisdictions'->'california' as ca)
   select (select sum((i->>'amount')::numeric) from j, jsonb_array_elements(j.ca->'installments') i)
        = (select (j.ca->>'annual_liability')::numeric from j)
     and (select (i->>'amount')::numeric from j, jsonb_array_elements(j.ca->'installments') i where (i->>'quarter')::int = 1)
       = (select (i->>'amount')::numeric from j, jsonb_array_elements(j.ca->'installments') i where (i->>'quarter')::int = 3)
  ),
  '(L6b / N-5) california installments: sum(amounts) = annual_liability EXACTLY and Q1 = Q3 (structural E25 invariant, independent hand-computed leg from federal''s) -- this equality is robustly true only BECAUSE annual_liability is already rounded to 2dp (N-5): a consumer summing installments against an unrounded annual would foot a penny short/over on a case this fixture does not happen to hit'
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
  '{"status":"computed","amount":-739.5300}'::jsonb,
  '(L10 / F-2 cascade) STATE2: nav_components.realized_tax_liab moves from unavailable (before STATE2, both jurisdictions'' ytd_paid required) to {computed, -739.5300} -- the SUM of both jurisdictions'' Estimated-Funds-Due gaps at as_of 2026-08-15 (installments_due_through_next=3: federal 3x87.43-1200=-937.71, california 3x66.06-0=+198.18), a NEGATIVE combined figure surfaced rather than clamped (nu-1); F-2''s taxable_income.lt_cg=1001 cascades into federal''s 87.43 quarter here too'
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
-- L13 — F-3 RENAME: quarters_elapsed is GONE. installments_due_through_next
-- is the ORDINAL OF THE UPCOMING installment (due dates STRICTLY BEFORE
-- as_of, plus one, capped at 4) with next_due_date beside it. Swept across
-- the SAME four boundaries as the retired quarters_elapsed leg, all within
-- tax_year 2026.
-- =====================================================================
select is(
  jsonb_build_object(
    'due_through_next', (pfin.fn_compute_tax_liability('2026-02-01'::date)->'jurisdictions'->'federal'->>'installments_due_through_next')::int,
    'next_due_date',    pfin.fn_compute_tax_liability('2026-02-01'::date)->'jurisdictions'->'federal'->>'next_due_date'
  ),
  jsonb_build_object('due_through_next', 1, 'next_due_date', '2026-04-15'),
  '(L13a) as_of 2026-02-01, before Apr 15 -> installments_due_through_next = 1 (Q1 is the upcoming one), next_due_date = 2026-04-15'
);
select is(
  jsonb_build_object(
    'due_through_next', (pfin.fn_compute_tax_liability('2026-05-01'::date)->'jurisdictions'->'federal'->>'installments_due_through_next')::int,
    'next_due_date',    pfin.fn_compute_tax_liability('2026-05-01'::date)->'jurisdictions'->'federal'->>'next_due_date'
  ),
  jsonb_build_object('due_through_next', 2, 'next_due_date', '2026-06-15'),
  '(L13b) as_of 2026-05-01, after Apr 15 -> installments_due_through_next = 2, next_due_date = 2026-06-15'
);
select is(
  jsonb_build_object(
    'due_through_next', (pfin.fn_compute_tax_liability('2026-07-01'::date)->'jurisdictions'->'federal'->>'installments_due_through_next')::int,
    'next_due_date',    pfin.fn_compute_tax_liability('2026-07-01'::date)->'jurisdictions'->'federal'->>'next_due_date'
  ),
  jsonb_build_object('due_through_next', 3, 'next_due_date', '2026-09-15'),
  '(L13c) as_of 2026-07-01, after Jun 15 -> installments_due_through_next = 3, next_due_date = 2026-09-15'
);
select is(
  jsonb_build_object(
    'due_through_next', (pfin.fn_compute_tax_liability('2026-10-01'::date)->'jurisdictions'->'federal'->>'installments_due_through_next')::int,
    'next_due_date',    pfin.fn_compute_tax_liability('2026-10-01'::date)->'jurisdictions'->'federal'->>'next_due_date'
  ),
  jsonb_build_object('due_through_next', 4, 'next_due_date', '2027-01-15'),
  '(L13d) as_of 2026-10-01, after Sep 15 -> installments_due_through_next = 4 (the max reachable inside tax_year 2026 itself -- under the NEW ordinal-of-upcoming meaning, unlike the retired quarters_elapsed leg''s max of 3; the cap never actually binds here: Q1-Q3 strictly-before caps the running count at 3, so +1 alone reaches 4 -- Q4''s Jan-15-following-year due date can never itself be strictly before an as_of dated inside the same tax_year), next_due_date = 2027-01-15'
);

-- =====================================================================
-- F-3 — boundary set (Apr 14/15/16, Dec 31, next-tax-year Jan 10) and the
-- Dec-31 obligation_to_date >= 4 branch, DEAD under the old on-or-before
-- reading and now LIVE: at a count of 4 the obligation is the ROUNDED
-- ANNUAL, not 4x the truncated quarter (they differ by up to 3c since
-- N-2's trunc, not round, is what makes Q1..Q3 truncate down).
-- =====================================================================
select is(
  jsonb_build_object(
    'due_through_next', (pfin.fn_compute_tax_liability('2026-04-14'::date)->'jurisdictions'->'federal'->>'installments_due_through_next')::int,
    'next_due_date',    pfin.fn_compute_tax_liability('2026-04-14'::date)->'jurisdictions'->'federal'->>'next_due_date'
  ),
  jsonb_build_object('due_through_next', 1, 'next_due_date', '2026-04-15'),
  '(F3a) as_of 2026-04-14, one day before Q1 is due -> installments_due_through_next = 1 (still the upcoming one), next_due_date = 2026-04-15'
);
select is(
  jsonb_build_object(
    'due_through_next', (pfin.fn_compute_tax_liability('2026-04-15'::date)->'jurisdictions'->'federal'->>'installments_due_through_next')::int,
    'next_due_date',    pfin.fn_compute_tax_liability('2026-04-15'::date)->'jurisdictions'->'federal'->>'next_due_date'
  ),
  jsonb_build_object('due_through_next', 1, 'next_due_date', '2026-04-15'),
  '(F3b) as_of 2026-04-15, DUE TODAY -> installments_due_through_next STILL 1 (< not <=: a payment due today is still the upcoming one, not yet elapsed), next_due_date = 2026-04-15'
);
select is(
  jsonb_build_object(
    'due_through_next', (pfin.fn_compute_tax_liability('2026-04-16'::date)->'jurisdictions'->'federal'->>'installments_due_through_next')::int,
    'next_due_date',    pfin.fn_compute_tax_liability('2026-04-16'::date)->'jurisdictions'->'federal'->>'next_due_date'
  ),
  jsonb_build_object('due_through_next', 2, 'next_due_date', '2026-06-15'),
  '(F3c) as_of 2026-04-16, one day after Q1 -> installments_due_through_next = 2, next_due_date = 2026-06-15'
);
select is(
  jsonb_build_object(
    'due_through_next', (pfin.fn_compute_tax_liability('2026-12-31'::date)->'jurisdictions'->'federal'->>'installments_due_through_next')::int,
    'next_due_date',    pfin.fn_compute_tax_liability('2026-12-31'::date)->'jurisdictions'->'federal'->>'next_due_date'
  ),
  jsonb_build_object('due_through_next', 4, 'next_due_date', '2027-01-15'),
  '(F3d) as_of 2026-12-31 -> installments_due_through_next = 4 (Q1-Q3 all strictly before), next_due_date = 2027-01-15 (Q4, still not itself due)'
);
select is(
  jsonb_build_object(
    'due_through_next', (pfin.fn_compute_tax_liability('2027-01-10'::date)->'jurisdictions'->'federal'->>'installments_due_through_next')::int,
    'next_due_date',    pfin.fn_compute_tax_liability('2027-01-10'::date)->'jurisdictions'->'federal'->>'next_due_date'
  ),
  jsonb_build_object('due_through_next', 1, 'next_due_date', '2027-04-15'),
  '(F3e) as_of 2027-01-10 -- tax_year is 2027 (its OWN Q1 due 2027-04-15, not 2026''s Q4 due 2027-01-15, which belongs to the PRIOR tax_year''s cycle) -> installments_due_through_next resets to 1, next_due_date = 2027-04-15; federal stays computed via the E22 fallback to the 2026 schedules'
);
select is(
  pfin.fn_compute_tax_liability('2026-12-31'::date)->'jurisdictions'->'federal'->'funds_due',
  '{"status":"computed","amount":-850.2500}'::jsonb,
  '(F3f) as_of 2026-12-31, installments_due_through_next=4: funds_due uses the ROUNDED annual (349.75) MINUS ytd_paid (1200.0000) = -850.2500 -- NOT 4 x the truncated quarter (4x87.43=349.72, which would give -850.2800, off by 3c); the previously-dead ">= 4" branch is now reachable and this proves it uses the correct operand'
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

-- =====================================================================
-- N-4 — jurisdiction-level basis_year is JSON null when the jurisdiction is
-- unavailable (SQL LEAST ignores NULLs; the ungated form of this field
-- rendered a confident year beside an unavailable status).
-- ⚠ Sec's F-4 finding (re-look at 5c9e0e6): the FIRST-CUT leg reused B's
-- already-unavailable federal jurisdiction from L16c/d, where BOTH federal
-- halves are unresolved -- least(NULL, NULL) is NULL WITH OR WITHOUT the
-- `case when jr.computed` gate, so that leg could not fail. Re-pointed onto
-- its OWN tax year (2030 -- unused anywhere else in this file, so this
-- fixture cannot perturb L15/L16/F1/F2a/M9/N2, and F-1's own 2026
-- empty-federal_lt_cg row for B stays untouched) where EXACTLY ONE federal
-- half resolves: federal_lt_cg gets a real, non-empty bracket schedule;
-- federal_ordinary stays absent for B at every year (B never seeds one, at
-- any tax_year, anywhere in this file). That feeds LEAST a NON-NULL
-- ltcg_basis_year beside a NULL ord_basis_year -- the one shape where
-- LEAST's ignore-NULLs behaviour and the `computed` gate actually disagree,
-- so this is the only fixture that can tell them apart.
-- =====================================================================
select set_config('role', 'postgres', true);
insert into pfin.tax_bracket_schedule (users_id, schedule_type, tax_year, standard_deduction, schedule_label)
  values (:'tb', 'federal_lt_cg', 2030, 0.0000, 'b-fed-ltcg-2030-n4-104')
  returning id as sch_b_n4 \gset
insert into pfin.tax_bracket_row (users_id, schedule_id, bracket_floor, bracket_rate)
  values (:'tb', :sch_b_n4, 0, 0.15);
select _rls.set_tenant(:'tb'::uuid);

select ok(
  (pfin.fn_compute_tax_liability('2030-08-15'::date)->'jurisdictions'->'federal'->>'status' = 'unavailable')
  and (pfin.fn_compute_tax_liability('2030-08-15'::date)->'jurisdictions'->'federal'->'basis_year' = 'null'::jsonb)
  and (pfin.fn_compute_tax_liability('2030-08-15'::date)->'jurisdictions'->'federal'->'schedules'->'federal_lt_cg'->'basis_year' = '2030'::jsonb),
  '(N4) B, tax_year 2030 (federal_lt_cg resolved with a real bracket row; federal_ordinary still absent) -- jurisdictions.federal.status = unavailable AND jurisdictions.federal.basis_year is JSON null, in the SAME payload as schedules.federal_lt_cg.basis_year = 2030 -- LEAST(NULL, 2030) would render 2030 at the jurisdiction level if the `case when jr.computed` gate at 104''s jur_calc CTE were struck; the retired L16c/d fixture (both federal halves unresolved) fed LEAST(NULL, NULL), which is NULL either way and could never distinguish gated from ungated'
);

-- =====================================================================
-- F-1 / F-2a — tenant B's federal_lt_cg schedule (seeded upfront: present
-- at tax_year 2026, ZERO bracket rows, no other federal_lt_cg row at any
-- year) is the identical situation to L15's california_ordinary case, one
-- schedule type over: present-but-empty with NO prior-year fallback. Sec's
-- F-1 finding is that the shipped code answered this LT CG leg differently
-- from the ordinary leg (false instead of true) for the identical shape.
-- =====================================================================
select is(
  (pfin.fn_compute_tax_liability('2026-08-15'::date)->'jurisdictions'->'federal'->'schedules'->'federal_lt_cg'->>'current_year_schedule_empty')::boolean,
  true,
  '(F1) B''s schedules.federal_lt_cg.current_year_schedule_empty = true -- a present-but-empty 2026 row with NO prior-year fallback (ltcg_empty_no_fallback, mirroring L15''s ordinary-leg shape); federal.status stays unavailable throughout since federal_ordinary is still absent for B -- the flag is visible INSIDE an unavailable jurisdiction, which is the point'
);
select is(
  (pfin.fn_compute_tax_liability('2026-08-15'::date)->'jurisdictions'->'federal'->'schedules'->'federal_lt_cg'->>'standard_deduction_ignored')::boolean,
  false,
  '(F2a) B''s schedules.federal_lt_cg.standard_deduction_ignored = false -- when NO LT CG schedule resolves at all (wl.schedule_id null, the F-1 case above), ltcg_standard_deduction is null and coalesce(null,0)<>0 is false; paired with F-2b''s true (a schedule that DOES resolve with a non-zero stored deduction, tenant A) and F-2c''s key-absent (california, no LT CG type)'
);

-- =====================================================================
-- N-2 — trunc, not round, at both boundary shapes Sec measured: annual
-- 0.02 (the negative-Q4 case under the retired round() form) and 7532.98
-- (a large case, same mechanism). Each on its OWN tax_year for tenant B so
-- the two calls cannot interact; a single 100%-rate bracket makes
-- annual_liability equal the seeded input EXACTLY.
-- =====================================================================
select is(
  pfin.fn_compute_tax_liability('2029-06-01'::date)->'jurisdictions'->'california'->'installments',
  '[{"quarter":1,"due_date":"2029-04-15","amount":0.00},{"quarter":2,"due_date":"2029-06-15","amount":0.00},{"quarter":3,"due_date":"2029-09-15","amount":0.00},{"quarter":4,"due_date":"2030-01-15","amount":0.02}]'::jsonb,
  '(N2a) annual_liability = 0.02 -> installments [0.00,0.00,0.00,0.02] -- trunc(0.02/4,2)=trunc(0.005,2)=0.00 for Q1-Q3, Q4 carries the full 0.02; under the retired round() form this was [0.01,0.01,0.01,-0.01], a NEGATIVE Q4. No installment here is negative.'
);
select is(
  pfin.fn_compute_tax_liability('2028-06-01'::date)->'jurisdictions'->'california'->'installments',
  '[{"quarter":1,"due_date":"2028-04-15","amount":1883.24},{"quarter":2,"due_date":"2028-06-15","amount":1883.24},{"quarter":3,"due_date":"2028-09-15","amount":1883.24},{"quarter":4,"due_date":"2029-01-15","amount":1883.26}]'::jsonb,
  '(N2b) annual_liability = 7532.98 -> installments 1883.24 x 3 (trunc(7532.98/4,2)=trunc(1883.245,2)=1883.24) + 1883.26 on Q4 (the residual) -- sum is exactly 7532.98, no installment negative'
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
-- L18 — VOLATILITY PIN, split in two per Sec's second-pass N-1 finding: the
-- first-pass leg was a hard-coded six-name count(*) that pinned NEITHER the
-- direct-callee set NOR the reach set (it wrongly included fn_server_today,
-- never called at all, and omitted fn_account_cash_as_of / fn_compute_nav /
-- fn_tax_authority_ledgers, which the corrected header's TRANSITIVE READ SET
-- diagram places in the reach set). Extending the OLD list to eight names
-- would go red for the WRONG reason (a count mismatch, not an un-pin) --
-- this is a shape change, read off the corrected header, not a bigger
-- number on the same shape.
--
-- (a) THE PINNED SET -- every function the header's diagram marks 's':
--     the helper itself, its three direct callees (fn_cashflow_items,
--     fn_ytd_paid_per_jurisdiction, fn_account_unrealized_gl), and the
--     three 's'-marked functions one or more hops deeper
--     (fn_account_cash_as_of, fn_compute_nav [both overloads],
--     fn_tax_authority_ledgers). Counts BOTH the row total (catches a
--     missing function) AND that every one of those rows is 's' (catches a
--     silent un-pin).
-- (b) THE TWO 'v'-MARKED REACH-SET MEMBERS (fn_gl_entries,
--     fn_holdings_as_of) contain NO write statement (insert/update/delete/
--     truncate) in prosrc -- the property that backs treating them as
--     read-only despite being unpinned (VOLATILE is language sql's default,
--     not a declared write).
-- =====================================================================
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin'
      and p.proname in ('fn_compute_tax_liability', 'fn_cashflow_items', 'fn_account_unrealized_gl',
                         'fn_ytd_paid_per_jurisdiction', 'fn_account_cash_as_of', 'fn_compute_nav',
                         'fn_tax_authority_ledgers')
      and p.provolatile = 's'),
  8,
  '(L18a) the PINNED set -- helper + 3 direct callees + 3 deeper reach-set members (fn_compute_nav counted TWICE, once per overload) -- all 8 rows measure provolatile = ''s'', read off 104''s CORRECTED header (not the first-pass six-name list, which named a non-callee and omitted three real reach-set members)'
);
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin'
      and p.proname in ('fn_gl_entries', 'fn_holdings_as_of')
      and p.provolatile = 'v'
      and p.prosrc !~* '\minsert\M|\mupdate\M|\mdelete\M|\mtruncate\M'),
  2,
  '(L18b) the two ''v''-marked reach-set members (fn_gl_entries, fn_holdings_as_of) contain NO write statement in prosrc -- pure reads simply never pinned, the property N-1''s honesty argument actually depends on (not "every callee is s")'
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

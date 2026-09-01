-- =====================================================================
-- Per-Wave battery — pfin.fn_expenditure_window(p_as_of date),
--   pfin.fn_expenditures_unclassified_count(p_as_of date), and the
--   pfin.fn_historical_expenditures CoR that consumes the window
--   (SELF-256; migration 098). Three SECURITY INVOKER read-composition
--   objects. Paired with the migration in the SAME PR.
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/098_expenditure_window_and_unclassified_count.sql.
--   Every leg below is one line of that migration's own QA TEST-PAIRING
--   block (items 1-13), plus the exact-one-row cardinality emphasis and the
--   corrupt-the-control cat-unscoped inversion the migration's own header
--   names as a trap ("restoring symmetry with 096 makes N permanently
--   zero").
--
--   Contract as landed:
--     fn_expenditure_window(p_as_of) -> TABLE(ms_floor date, ms_last date)
--       — EXACTLY ONE ROW ALWAYS, including (NULL,NULL) on a NULL argument.
--       Both bounds first-of-month. ms_last = first-of-month of the LAST
--       COMPLETE month at or before p_as_of, via the (p_as_of + 1) form
--       (a month-end p_as_of keeps its own month). ms_floor = 59 months
--       before ms_last (60 months inclusive of both endpoints).
--     fn_expenditures_unclassified_count(p_as_of) -> TABLE(
--       unclassified_count bigint, ms_floor date, ms_last date) — EXACTLY
--       ONE ROW ALWAYS. Counts pfin.fn_cashflow_items rows with
--       sub_cat_id IS NULL, bucketed and clipped to the SAME window
--       fn_expenditure_window returns (also returned, for cross-check).
--       NO cat filter, NO posting_prototype join — deliberately (see the
--       migration's own trap note). NULL p_as_of -> unclassified_count
--       NULL, not 0.
--     fn_historical_expenditures(p_as_of) — CoR, 096's contract UNCHANGED;
--       only the window's derivation moved (096's own bounds+span CTE pair
--       -> a single span CTE selecting from fn_expenditure_window).
--     All three: SECURITY INVOKER · STABLE · set search_path = ''.
--
-- ┌─ WHAT THIS BATTERY PROVES — one line per migration-header QA TEST-PAIRING item ────┐
-- │ (1)  CRUX ⭐⭐ fn_expenditure_window IS BEHAVIOUR-PRESERVING, proven                │
-- │          DIFFERENTIALLY: 15 dates (month-ends, the 1st, mid-month, leap AND        │
-- │          non-leap Feb boundaries, Dec31/Jan1, a 30-day-month boundary, NULL)        │
-- │          against an INDEPENDENT derivation — integer year*12+month ordinal         │
-- │          arithmetic with a plain `extract(month from d+1) <> extract(month from    │
-- │          d)` month-end test, sharing NO date_trunc/interval machinery with the      │
-- │          body. Verified against the live function before being written into this   │
-- │          file (all 15 rows agreed) — not assumed correct because it looks right.   │
-- │ (CARD)  exactly-one-row cardinality, both a real date and NULL — the property       │
-- │          096's CROSS JOIN depends on.                                              │
-- │ (2)  096's OUTPUT IS UNCHANGED BY THE CoR — a dense 60-row series with items        │
-- │          EXACTLY AT both window edges, proving the extraction moved no bound.       │
-- │ (3)  THE COUNT USES THE SAME WINDOW AS THE SERIES, asserted FROM THE OUTPUT in one  │
-- │          statement, PLUS an item just outside the floor excluded non-vacuously.     │
-- │ (4)  THE PARTIAL-MONTH EDGE: the SAME item, included under a month-end p_as_of and  │
-- │          excluded under a mid-month one for the same month.                        │
-- │ (5)  THE COUNT IS UNSCOPED TO cat, NON-VACUOUSLY, PLUS corrupt-the-control: a       │
-- │          "restore symmetry with 096" variant, installed via CoR in a savepoint and  │
-- │          rolled back, is proven to make N zero on the SAME fixture the real         │
-- │          function counts >0 on — the trap the migration's own header names, made    │
-- │          real rather than taken on the header's word.                              │
-- │ (6)  GRAIN: a split UNCLASSIFIED child counted, its classified sibling not, the     │
-- │          parent never a candidate at all.                                          │
-- │ (7)  NULL p_as_of -> NULL, not 0 — the full row.                                    │
-- │ (8)  TWO-TENANT, NON-VACUOUSLY: different unclassified populations, different N.    │
-- │ (9)  CROSS-TENANT: 0, not an error, not a leak.                                     │
-- │ (10) AAL2 BACKSTOP, both legs.                                                      │
-- │ (11) POSTURE, all three objects (the 067 three-element form).                       │
-- │ (12) ACL, all three objects.                                                        │
-- │ (13) 096's CATALOG COMMENT renders and now names fn_expenditure_window.             │
-- └─────────────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3 / DEFINER ALLOWLIST — this battery introduces NO catalogued
--   instance and changes none. 098 authors two new functions and re-issues a third,
--   all SECURITY INVOKER, reached by `authenticated` over PostgREST; no credential,
--   no container, no admission endpoint in its path, and it creates no column of any
--   kind. No count is restated here — read ADR-011 Decision 3 and Decision 4 LIVE at
--   the canonical anchor at merge time.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants via _rls.tenant_a() /
--   _rls.tenant_b() / _rls.tenant_c(), plus three locally-declared fixed tenants
--   (D aal2, E partial-month, F split-grain). NO PII / NO real account numbers / NO
--   production data. p_as_of D = 2026-09-30 (a month-end — the same fixture date
--   096's own battery uses, so a reader can cross-check window numbers between the
--   two files); D2 = 2026-09-15 (mid-month, item 4 only). Both are ARGUMENTS, not
--   the wall clock — none of the three objects under test reads
--   pfin.fn_server_today(), so unlike the 071/072/073 family this battery carries NO
--   clock-forcing and NO clock-sensitivity at all.
--
-- ⚠ Sec joint-review MANDATORY per the migration's own header (096's CoR is a
--   financial calculation; the count is the completeness signal on a money surface).
--   This file is QA's half of that review's evidence; it does not substitute for it.
--
-- plan(34) — (CRUX: 1 differential batch + 2 exactly-one-row cardinality = 3) +
--   (ITEM2: row-count + floor-edge + last-edge = 3) + (ITEM3: window-agreement +
--   edge-exclusion = 2) + (ITEM4: included + excluded = 2) + (ITEM5: non-vacuous +
--   inversion lives_ok + inversion result = 3) + (ITEM6: 1) + (ITEM7: 1) + (ITEM8: 2)
--   + (ITEM9: 2) + (ITEM10: 2) + (POSTURE x3 objects: 3) + (ACL x3 objects x3 checks:
--   9) + (ITEM13: 1). Verify with `pg_prove`, never bare `psql`.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

select plan(34);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset
\set td '00000000-0000-0000-0000-0000000000d8'
\set te '00000000-0000-0000-0000-0000000000e8'
\set tf '00000000-0000-0000-0000-0000000000f8'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc'), (:'td'), (:'te'), (:'tf');
insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta','none'), (:'tb','none'), (:'tc','none'), (:'td','totp'), (:'te','none'), (:'tf','none');

\set d_asof '2026-09-30'
\set d2_asof '2026-09-15'

-- =====================================================================
-- FIXTURE — Tenant A: two CLASSIFIED expense items, one at EACH window edge
--   for D=2026-09-30 (floor=2021-10-01, last=2026-09-01 in first-of-month
--   space), giving a DENSE 60-row series under 096 — the (2) differential
--   proof. Also carries ONE unclassified item (item 8's own-count half).
-- =====================================================================
select set_config('app.nav_computed_for', :'ta', true);
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-a98', 'depository', 'household', 'taxable')
  returning account_id as accta \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Expense', 'Misc98A', false) returning id as a_exp \gset

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2021-10-15', -1000, 'v98floor', '098 tenant A floor-edge classified expense', '2021-10-16')
  returning trans_id as t_floor \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_floor, :a_exp);

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2026-09-15', -2000, 'v98last', '098 tenant A last-edge classified expense', '2026-09-16')
  returning trans_id as t_last \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_last, :a_exp);

-- item 8's own-count half: ONE unclassified item, no annotation at all.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2024-01-15', -50, 'v98aunc', '098 tenant A unclassified item (item 8)', '2024-01-16')
  returning trans_id as t_a_unc \gset
select set_config('role', 'postgres', true);

-- =====================================================================
-- FIXTURE — Tenant B: THREE unclassified items — one strictly OUTSIDE the
--   floor edge (excluded), two inside (included). Total under D is 2, not
--   3 — the non-vacuous edge-exclusion proof (item 3) and item 8's other
--   own-count half (2, distinct from A's 1).
-- =====================================================================
select set_config('app.nav_computed_for', :'tb', true);
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'acct-b98', 'depository', 'household', 'taxable')
  returning account_id as acctb \gset

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:acctb, '2021-09-15', -60, 'v98outside', '098 tenant B just OUTSIDE the floor edge (EXCLUDED)', '2021-09-16')
  returning trans_id as t_b_outside \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:acctb, '2021-10-15', -70, 'v98atfloor', '098 tenant B AT the floor edge (included)', '2021-10-16')
  returning trans_id as t_b_atfloor \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:acctb, '2024-05-15', -80, 'v98mid', '098 tenant B mid-window (included)', '2024-05-16')
  returning trans_id as t_b_mid \gset
select set_config('role', 'postgres', true);

-- Tenant C: ZERO checkpoints — cross-tenant leg (item 9).

-- =====================================================================
-- FIXTURE — Tenant D: aal2 backstop, ONE unclassified item mid-window.
-- =====================================================================
select set_config('app.nav_computed_for', :'td', true);
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'td', 'acct-d98', 'depository', 'household', 'taxable')
  returning account_id as acctd \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:acctd, '2024-06-15', -90, 'v98d', '098 tenant D aal2 unclassified item', '2024-06-16')
  returning trans_id as t_d \gset
select set_config('role', 'postgres', true);

-- =====================================================================
-- FIXTURE — Tenant E: ONE unclassified item dated in D's OWN month
--   (2026-09), nothing else. Item 4: included when queried at D (Sep is
--   complete), excluded when queried at D2 (mid-September, Sep is NOT
--   complete) — the SAME item, the SAME transaction_date, two different
--   p_as_of values, two different results.
-- =====================================================================
select set_config('app.nav_computed_for', :'te', true);
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'te', 'acct-e98', 'depository', 'household', 'taxable')
  returning account_id as accte \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accte, '2026-09-15', -95, 'v98e', '098 tenant E partial-month edge item', '2026-09-16')
  returning trans_id as t_e \gset
select set_config('role', 'postgres', true);

-- =====================================================================
-- FIXTURE — Tenant F: a SPLIT transaction, one UNCLASSIFIED child and one
--   CLASSIFIED sibling child. Item 6 (grain): the count is 1 (the
--   unclassified child alone) — never 2 (double-counting the classified
--   sibling), never 0 (missing the child), and the split PARENT is never a
--   countable row at all (093's split XOR — it is never emitted as an item).
-- =====================================================================
select set_config('app.nav_computed_for', :'tf', true);
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tf', 'acct-f98', 'depository', 'household', 'taxable')
  returning account_id as acctf \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'tf', 'Expense', 'Misc98F', false) returning id as f_exp \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:acctf, '2024-03-15', -100, 'v98split', '098 tenant F split parent (never a countable item)', '2024-03-16')
  returning trans_id as t_f_split \gset
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount) values
  (:t_f_split, null, -60),      -- unclassified child — counted
  (:t_f_split, :f_exp, -40);    -- classified sibling — not counted
select set_config('role', 'postgres', true);

-- =====================================================================
-- (CRUX) ⭐⭐ fn_expenditure_window IS BEHAVIOUR-PRESERVING — 15 dates
--   (month-ends, the 1st, mid-month, leap/non-leap Feb boundaries,
--   Dec31/Jan1, a 30-day-month boundary, NULL), independently derived via
--   integer year*12+month ordinal arithmetic. Verified against the live
--   function before authoring (all 15 agreed) — recorded so this leg's
--   provenance is not "it happened to pass".
-- =====================================================================
select ok(
  (with test_dates(d) as (
     values
       (null::date),
       ('2026-08-31'::date), ('2026-08-30'::date), ('2026-08-01'::date), ('2026-08-15'::date),
       ('2026-02-28'::date), ('2026-02-27'::date),
       ('2024-02-29'::date), ('2024-02-28'::date),
       ('2025-12-31'::date), ('2026-01-01'::date),
       ('2026-04-30'::date), ('2026-04-29'::date),
       ('2026-01-31'::date), ('2026-01-30'::date)
   ),
   expected as (
     select
       d,
       case when d is null then null::int
            when extract(month from d + 1) <> extract(month from d) then extract(year from d)::int
            else case when extract(month from d)::int = 1 then extract(year from d)::int - 1 else extract(year from d)::int end
       end as cy,
       case when d is null then null::int
            when extract(month from d + 1) <> extract(month from d) then extract(month from d)::int
            else case when extract(month from d)::int = 1 then 12 else extract(month from d)::int - 1 end
       end as cm
     from test_dates
   ),
   expected2 as (
     select
       d,
       case when d is null then null::date else make_date(cy, cm, 1) end as exp_ms_last,
       case when d is null then null::date else
         make_date(
           (((cy*12 + (cm-1)) - 59) / 12),
           ((((cy*12 + (cm-1)) - 59) % 12) + 1),
           1
         )
       end as exp_ms_floor
     from expected
   )
   select bool_and(
            (w.ms_last  is not distinct from e.exp_ms_last)
        and (w.ms_floor is not distinct from e.exp_ms_floor)
          )
     from expected2 e
     cross join lateral pfin.fn_expenditure_window(e.d) w),
  '(CRUX) ⭐⭐ fn_expenditure_window(d) agrees with an INDEPENDENT ordinal-arithmetic derivation (integer year*12+month, a plain extract(month from d+1)<>extract(month from d) month-end test — sharing no date_trunc/interval machinery with the body) across 15 dates including NULL, month-ends of 28/29/30/31-day months, Dec31/Jan1, and mid-month days. RED if the extraction shifted the window by a month on any one of them, which a single-date spot-check could not distinguish from a correct one'
);

select is(
  (select count(*)::int from pfin.fn_expenditure_window(null)),
  1,
  '(CARD1) ⭐ exactly ONE row on a NULL argument, not zero — the cardinality 096''s CROSS JOIN depends on. Both columns are NULL (already proven by (CRUX)), but the ROW must still exist'
);
select is(
  (select count(*)::int from pfin.fn_expenditure_window(:'d_asof'::date)),
  1,
  '(CARD2) …and exactly ONE row on a real date too — a SELECT with no FROM clause could in principle return zero or duplicate; pinned directly rather than inferred from the values matching'
);

-- =====================================================================
-- (2) 096's OUTPUT IS UNCHANGED BY THE CoR — tenant A's dense 60-row
--   series, with real items EXACTLY at both window edges.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*)::int from pfin.fn_historical_expenditures(:'d_asof'::date)),
  60,
  '(ITEM2-COUNT) ⭐ the series is exactly 60 rows (dense, floor to last) — the row count the CTE splice could silently shrink or grow if it moved a bound'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select expense_monthly_nominal from pfin.fn_historical_expenditures(:'d_asof'::date) where month_end = '2021-10-31'),
  1000::numeric,
  '(ITEM2-FLOOR) ⭐ the FLOOR-EDGE row (2021-10-31, the earliest month the window admits) carries the real item''s nominal (1000) — proving the extraction did not shift the floor'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select expense_monthly_nominal from pfin.fn_historical_expenditures(:'d_asof'::date) where month_end = '2026-09-30'),
  2000::numeric,
  '(ITEM2-LAST) ⭐ the LAST-EDGE row (2026-09-30, D''s own complete month) carries the real item''s nominal (2000) — proving the extraction did not shift ms_last, including the (p_as_of + 1) month-end-keeps-its-own-month rule'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (3) THE COUNT USES THE SAME WINDOW AS THE SERIES, asserted FROM THE
--   OUTPUT in one statement, PLUS the edge-exclusion non-vacuity.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (with win as (select * from pfin.fn_expenditure_window(:'d_asof'::date)),
        cnt as (select * from pfin.fn_expenditures_unclassified_count(:'d_asof'::date)),
        ser as (select min(month_end) as first_m, max(month_end) as last_m
                   from pfin.fn_historical_expenditures(:'d_asof'::date))
   select win.ms_floor = cnt.ms_floor
      and win.ms_last  = cnt.ms_last
      and date_trunc('month', ser.first_m)::date = win.ms_floor
      and date_trunc('month', ser.last_m)::date  = win.ms_last
     from win cross join cnt cross join ser),
  '(ITEM3-AGREE) ⭐ the count''s (ms_floor, ms_last) EQUAL the window function''s own output, AND the series'' first/last months EXACTLY BRACKET them (tenant A''s fixture places real items precisely at both edges, so this is an equality, not a loose bound) — asserted from the OUTPUTS of all three objects in one statement, never by reading two bodies'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'tb'::uuid);
select is(
  (select unclassified_count from pfin.fn_expenditures_unclassified_count(:'d_asof'::date)),
  2::bigint,
  '(ITEM3-EDGE) ⭐ tenant B''s count is 2, NOT 3 — the item dated one month before the floor edge (2021-09-15) is excluded; an all-inside fixture could not distinguish a correct bound from one off by a month, this one can'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (4) THE PARTIAL-MONTH EDGE, BOTH SIDES — the SAME item (tenant E,
--   dated 2026-09-15), two different p_as_of values.
-- =====================================================================
select _rls.set_tenant(:'te'::uuid);
select is(
  (select unclassified_count from pfin.fn_expenditures_unclassified_count(:'d_asof'::date)),
  1::bigint,
  '(ITEM4-IN) ⭐ at D=2026-09-30 (September IS complete), the item counts: 1'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'te'::uuid);
select is(
  (select unclassified_count from pfin.fn_expenditures_unclassified_count(:'d2_asof'::date)),
  0::bigint,
  '(ITEM4-OUT) ⭐ at D2=2026-09-15 (mid-September, NOT complete), the SAME item does not count: 0 — the chart draws no bar for this month at D2, so the count must not report an item sitting in it'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (5) THE COUNT IS UNSCOPED TO cat, NON-VACUOUSLY, PLUS the
--   corrupt-the-control inversion the migration's own header names as a
--   trap: "restoring symmetry with 096 makes N permanently zero".
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select unclassified_count from pfin.fn_expenditures_unclassified_count(:'d_asof'::date)),
  2::bigint,
  '(ITEM5-POS) ⭐ tenant B''s unclassified items (cat is NULL for every one of them, by definition — sub_cat_id IS NULL) are STILL counted: 2, not 0 — the count is unscoped to cat'
);
select set_config('role', 'postgres', true);

savepoint cat_symmetry_trap;
create or replace function pfin.fn_expenditures_unclassified_count(p_as_of date)
returns table (unclassified_count bigint, ms_floor date, ms_last date)
language sql stable security invoker set search_path = ''
as $$
  select
    case when p_as_of is null then null::bigint
         else (
           select count(*)::bigint
           from pfin.fn_cashflow_items(p_as_of) i
           join pfin.posting_prototype pp on pp.id = i.sub_cat_id
           where i.sub_cat_id is null
             and i.cat = 'Expense'
             and pp.is_tax_payment = false
             and date_trunc('month', i.transaction_date::timestamp)::date >= w.ms_floor
             and date_trunc('month', i.transaction_date::timestamp)::date <= w.ms_last
         )
    end as unclassified_count,
    w.ms_floor,
    w.ms_last
  from pfin.fn_expenditure_window(p_as_of) w;
$$;
select _rls.set_tenant(:'tb'::uuid);
select lives_ok(
  $$ select * from pfin.fn_expenditures_unclassified_count('2026-09-30'::date) $$,
  '(ITEM5-INV0) corrupt-the-control: the ''restore symmetry with 096'' variant (adds cat=''Expense'' + posting_prototype INNER JOIN) does not raise'
);
select is(
  (select unclassified_count from pfin.fn_expenditures_unclassified_count(:'d_asof'::date)),
  0::bigint,
  '(ITEM5-INV1) ⭐⭐ …and it returns 0 on the SAME tenant B fixture the real function counts 2 on — the trap the migration''s header names, made real: `cat = ''Expense''` is NULL for every unclassified row (NULL sub_cat_id -> NULL cat), and the INNER join drops every one of them. Nothing raised; the banner would simply never render. This is what the shipped function''s absent filters avoid'
);
select set_config('role', 'postgres', true);
rollback to savepoint cat_symmetry_trap;

-- =====================================================================
-- (6) GRAIN: split children count individually; the parent is never a
--   candidate row at all.
-- =====================================================================
select _rls.set_tenant(:'tf'::uuid);
select is(
  (select unclassified_count from pfin.fn_expenditures_unclassified_count(:'d_asof'::date)),
  1::bigint,
  '(ITEM6) ⭐ tenant F''s split transaction contributes exactly 1 — the unclassified CHILD alone. Not 2 (the classified sibling is not double-counted), not 0 (the child is not missed), and the split PARENT is never emitted as an item at all (093''s split XOR), so it was never a candidate to begin with'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (7) NULL p_as_of -> NULL, not 0 — the full row.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select results_eq(
  $$ select unclassified_count, ms_floor, ms_last from pfin.fn_expenditures_unclassified_count(null) $$,
  $$ values (null::bigint, null::date, null::date) $$,
  '(ITEM7) ⭐ a NULL p_as_of returns unclassified_count NULL — not the 0 that count(*) over an empty set would naturally produce — because "nothing is unclassified" and "this could not be computed" must not render alike. ms_floor/ms_last are NULL too, matching fn_expenditure_window''s own NULL-argument row'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (8) TWO-TENANT, NON-VACUOUSLY: different unclassified populations,
--   different N.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select unclassified_count from pfin.fn_expenditures_unclassified_count(:'d_asof'::date)),
  1::bigint,
  '(ITEM8-A) A''s own unclassified count is 1'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select unclassified_count from pfin.fn_expenditures_unclassified_count(:'d_asof'::date)),
  2::bigint,
  '(ITEM8-B) ⭐ THE NON-VACUITY THAT MAKES (ITEM8-A) A TEST: the IDENTICAL call under B returns B''s OWN count (2), never A''s (1) — a same-population fixture could not distinguish this from a broken tenant predicate'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (9) CROSS-TENANT: 0, not an error, not a leak.
-- =====================================================================
select _rls.set_tenant(:'tc'::uuid);
select lives_ok(
  $$ select * from pfin.fn_expenditures_unclassified_count('2026-09-30'::date) $$,
  '(ITEM9-A) tenant C (zero checkpoints) does not raise'
);
select is(
  (select unclassified_count from pfin.fn_expenditures_unclassified_count(:'d_asof'::date)),
  0::bigint,
  '(ITEM9-B) …and returns 0, not an error and not another tenant''s count — the fail-closed direction for a disclosure signal'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (10) AAL2 BACKSTOP, BOTH LEGS.
-- =====================================================================
select is(
  _rls.count_as(:'td'::uuid, 'aal1',
    $$ select count(*) from pfin.fn_expenditures_unclassified_count('2026-09-30'::date) where unclassified_count is null or unclassified_count = 0 $$
  ), 1::bigint,
  '(ITEM10-A) an aal1 session for the totp-declared tenant D gets a zero/null count, even though D genuinely has an unclassified item — the aal2 backstop fails this read closed'
);
select is(
  _rls.count_as(:'td'::uuid, 'aal2',
    $$ select count(*) from pfin.fn_expenditures_unclassified_count('2026-09-30'::date) where unclassified_count = 1 $$
  ), 1::bigint,
  '(ITEM10-B) ⭐ the POSITIVE leg that makes (ITEM10-A) a test: the SAME tenant at aal2 sees their REAL count (1). Without this, (ITEM10-A) could pass vacuously against a policy that blinds every caller'
);

-- =====================================================================
-- (11) POSTURE, ALL THREE OBJECTS — the 067/097 three-element form.
-- =====================================================================
select is(
  (select array[p.prosecdef::text, p.provolatile::text, array_to_string(p.proconfig, ',')]
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_expenditure_window'),
  array['false','s','search_path=""'],
  '(POSTURE-WINDOW) SECURITY INVOKER, STABLE, search_path pinned empty — read declaratively from the catalog'
);
select is(
  (select array[p.prosecdef::text, p.provolatile::text, array_to_string(p.proconfig, ',')]
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_expenditures_unclassified_count'),
  array['false','s','search_path=""'],
  '(POSTURE-COUNT) SECURITY INVOKER, STABLE, search_path pinned empty'
);
select is(
  (select array[p.prosecdef::text, p.provolatile::text, array_to_string(p.proconfig, ',')]
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_historical_expenditures'),
  array['false','s','search_path=""'],
  '(POSTURE-096) ⭐ 096''s CoR did NOT silently flip it VOLATILE — an omitted volatility clause on `create or replace` defaults to VOLATILE and no behavioural leg would see it. Verified HERE, in this file, independent of 096''s own battery'
);

-- =====================================================================
-- (12) ACL, ALL THREE OBJECTS.
-- =====================================================================
select ok(has_function_privilege('authenticated', 'pfin.fn_expenditure_window(date)', 'execute'), '(ACL-WINDOW-1) authenticated HOLDS EXECUTE');
select ok(not has_function_privilege('public', 'pfin.fn_expenditure_window(date)', 'execute'), '(ACL-WINDOW-2) LOAD-BEARING: PUBLIC does NOT');
select ok(not has_function_privilege('service_role', 'pfin.fn_expenditure_window(date)', 'execute'), '(ACL-WINDOW-3) service_role does NOT');

select ok(has_function_privilege('authenticated', 'pfin.fn_expenditures_unclassified_count(date)', 'execute'), '(ACL-COUNT-1) authenticated HOLDS EXECUTE');
select ok(not has_function_privilege('public', 'pfin.fn_expenditures_unclassified_count(date)', 'execute'), '(ACL-COUNT-2) LOAD-BEARING: PUBLIC does NOT');
select ok(not has_function_privilege('service_role', 'pfin.fn_expenditures_unclassified_count(date)', 'execute'), '(ACL-COUNT-3) service_role does NOT');

select ok(has_function_privilege('authenticated', 'pfin.fn_historical_expenditures(date)', 'execute'), '(ACL-096-1) authenticated HOLDS EXECUTE — the ACL is a restatement, but verified here rather than assumed');
select ok(not has_function_privilege('public', 'pfin.fn_historical_expenditures(date)', 'execute'), '(ACL-096-2) PUBLIC does NOT');
select ok(not has_function_privilege('service_role', 'pfin.fn_historical_expenditures(date)', 'execute'), '(ACL-096-3) service_role does NOT');

-- =====================================================================
-- (13) 096's CATALOG COMMENT renders and now NAMES fn_expenditure_window.
-- =====================================================================
select ok(
  obj_description('pfin.fn_historical_expenditures(date)'::regprocedure, 'pg_proc') ~ 'fn_expenditure_window',
  '(ITEM13) ⭐ 096''s re-issued catalog comment names pfin.fn_expenditure_window as the window''s new single home — otherwise the comment would go on describing the window as derived inline, sending the next editor to the wrong file'
);

select * from finish();
rollback;

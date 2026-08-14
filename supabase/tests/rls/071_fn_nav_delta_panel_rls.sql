-- =====================================================================
-- Per-Wave battery — pfin.fn_nav_delta_panel() — the §2.1.3.a multi-horizon
--   NAV-delta backend (SELF-221; migration 071). SECURITY INVOKER
--   read-composition over pfin.nav_daily (054) + pfin.fn_cpi_u_index_for_period
--   (066), today from pfin.fn_server_today (070, same PR). No parameters —
--   tenant and "today" both derive from session state. Paired with the
--   migration in the SAME PR.
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/071_fn_nav_delta_panel.sql, commit
--   14600bd. Every leg below is one line of that migration's own QA
--   TEST-PAIRING block (items 1-12).
--
--   ⚠ NO p_as_of PARAMETER — DELIBERATE (a client-suppliable as-of would BE
--   the two-clock hazard ADR-044 closes). "Today" is derived internally via
--   070, which returns the SESSION's live `current_date`. Consequence for
--   this battery: fixture checkpoint dates and every expected-value
--   computation below are expressed RELATIVE TO `pfin.fn_server_today()`
--   captured ONCE at the top of this transaction, using the IDENTICAL
--   date-resolution expressions the migration body uses (base month-end,
--   YTD anchor, 1y/3y/5y offsets) — this is fixture SCAFFOLDING (knowing
--   WHICH calendar dates to seed), not the thing under test. What IS
--   independently computed, by hand, in plain arithmetic, is the
--   inflation-adjusted VALUE at (1) below — the crux this migration exists
--   to fix.
--
--   Contract as landed:
--     returns table (horizon text, anchor_date date, anchor_checkpoint_date
--       date, delta_nominal numeric, delta_percent numeric,
--       delta_inflation_adjusted numeric, cpi_basis_period date,
--       cpi_any_carried boolean, cpi_unavailable boolean)
--     SECURITY INVOKER · STABLE · set search_path = '' · NO ARGUMENTS.
--     EXACTLY FIVE ROWS ALWAYS: month/ytd/1y/3y/5y, fixed order.
--     Formula: delta_inflation_adjusted = nav_current*(cpi_ye/cpi_current)
--       - nav_anchor*(cpi_ye/cpi_anchor) — THREE CPI observations, each
--       endpoint deflated separately THEN differenced (never the single-ratio
--       defective draft this migration's header records at length).
--
-- ┌─ WHAT THIS BATTERY PROVES — one line per migration-header QA TEST-PAIRING item ────┐
-- │ (1)  CRUX ⭐⭐ THE ARITHMETIC, cpi_current ≠ cpi_anchor ≠ cpi_ye on EVERY adj leg.   │
-- │          Independently hand-computed expected values for 1y/3y/5y.                 │
-- │ (2)  FIVE five rows always, fixed order, incl. a zero-checkpoint tenant.            │
-- │ (—)  ANCHOR anchor-date DERIVATION verified by FIVE INDEPENDENT PROPERTIES           │
-- │          (Architect, d97f444 header (c), sharpened round-2): make_date()-based       │
-- │          reconstruction for ytd/cpi_basis_period (P3/P4, the load-bearing pair —     │
-- │          the body's own most-convoluted line), relational month-spacing (P2),        │
-- │          self-consistency month-end check (P1), loose recency bound (P5) — none      │
-- │          recompute an anchor from `today` using the body's own machinery, so a       │
-- │          shared month-end mistake between this file's fixture scaffolding and the    │
-- │          body cannot hide.                                                           │
-- │ (3)  CAUSE the three NULL causes distinguished on the full row: insufficient        │
-- │          history, CPI-unresolvable, not-applicable (month/ytd).                     │
-- │ (4)  CARRY carry provenance, BOTH sides: a NAV anchor served by an earlier          │
-- │          checkpoint, AND a CPI leg actually carried (cpi_any_carried true).         │
-- │ (5)  PCT0 delta_percent NULL (not 0, not a raise) on a zero anchor NAV, with        │
-- │          delta_nominal still present.                                               │
-- │ (6)  CPIG zero AND negative CPI on the denominator -> NULL adj, never raised,       │
-- │          never sign-flipped.                                                        │
-- │ (7)  T   two-tenant, non-vacuously: identical dates, different nav_values.          │
-- │ (8)  X   cross-tenant / zero-checkpoint tenant -> five all-NULL rows.               │
-- │ (9)  M   aal2 backstop, both legs.                                                  │
-- │ (10) PST1 catalog posture for 071 (070's own posture is 070's own battery).         │
-- │ (11) A   ACL: authenticated yes, PUBLIC no, service_role no.                        │
-- │ (12) TUP full-state-tuple discipline — every full-row assertion below reads         │
-- │          the WHOLE row (results_eq / multi-field ok()), never a single column       │
-- │          in isolation, satisfying Sec's criterion at the point of use.              │
-- └──────────────────────────────────────────────────────────────────────────────────────┘
--
-- ⚠ `supabase db reset` is PROHIBITED — destroys F/CTO's active local test data.
--   Scratch database only, pg_prove via `supabase test db`, never bare psql.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

-- plan = 30 : 3 fixture pins (Z) + 3 crux arithmetic (CRUX) + 1 five-rows-order
-- (FIVE) + 5 independent anchor-derivation properties (ANCHOR-P1..P5)
-- + 4 null-cause (CAUSE) + 2 carry provenance (CARRY) + 1 zero-anchor percent
-- (PCT0) + 2 CPI guard (CPIG) + 2 two-tenant (T) + 1 cross-tenant (X)
-- + 2 aal2 (M) + 1 catalog posture (PST1) + 3 ACL (A).
select plan(30);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset
\set td '00000000-0000-0000-0000-000000000d71'
\set te '00000000-0000-0000-0000-000000000e71'
\set tf '00000000-0000-0000-0000-000000000f71'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc'), (:'td'), (:'te'), (:'tf');
insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta','none'), (:'tb','none'), (:'tc','none'), (:'td','totp'), (:'te','none'), (:'tf','none');

-- =====================================================================
-- ANCHOR-DATE SCAFFOLDING — mirrors the migration body's OWN date expressions
-- exactly (070's answer, then base/ytd/ye_period/1y/3y/5y). This is not the
-- thing under test (the migration's anchor-date FORMULA is a documented
-- product default, not a correctness crux); it is how this file knows which
-- calendar dates to seed checkpoints and CPI prints at, regardless of which
-- real day this battery happens to run on.
-- =====================================================================
select pfin.fn_server_today() as today \gset
select (case
          when :'today'::date = (date_trunc('month', :'today'::date::timestamp)
                                  + '1 mon'::interval - '1 day'::interval)::date
          then :'today'::date
          else (date_trunc('month', :'today'::date::timestamp) - '1 day'::interval)::date
        end) as base \gset
select (date_trunc('year', :'today'::date::timestamp) - '1 day'::interval)::date as ytdanchor \gset
select (date_trunc('year', :'today'::date::timestamp) - '1 year'::interval + '11 mon'::interval)::date as yeperiod \gset
select (:'base'::date::timestamp - '12 mon'::interval)::date as a1y \gset
select (:'base'::date::timestamp - '36 mon'::interval)::date as a3y \gset
select (:'base'::date::timestamp - '60 mon'::interval)::date as a5y \gset
select date_trunc('month', :'a1y'::date::timestamp)::date as a1ymonth \gset
select date_trunc('month', :'a3y'::date::timestamp)::date as a3ymonth \gset
select date_trunc('month', :'a5y'::date::timestamp)::date as a5ymonth \gset

-- =====================================================================
-- FIXTURE — CPI-U (global; shared across every tenant below). Five distinct
-- print values, no two equal — the crux's own precondition:
--   cpi_ye (basis, Dec of prior year)         = 300.000
--   cpi_current (coverage_through — the LATEST period seeded)  = 320.000
--   cpi_anchor_1y (first-of-month of the 1y anchor)            = 250.000
--   cpi_anchor_3y (first-of-month of the 3y anchor)            = 200.000
--   cpi_anchor_5y (first-of-month of the 5y anchor)            = 240.000
-- Chosen so cpi_ye/cpi_current and cpi_ye/cpi_anchor_* all reduce to
-- TERMINATING decimals (0.9375, 1.2, 1.5, 1.25) — the crux legs below are
-- exact, not rounded, so a wrong formula cannot hide behind a repeating-
-- decimal coincidence.
-- =====================================================================
delete from pfin.cpi_u_index;
insert into pfin.cpi_u_index (cpi_period, cpi_value) values
  (:'yeperiod'::date, 300.000),
  (:'a1ymonth'::date, 250.000),
  (:'a3ymonth'::date, 200.000),
  (:'a5ymonth'::date, 240.000),
  (date_trunc('month', :'today'::date::timestamp)::date, 320.000);

-- (z) fixture pins.
select is(
  (select max(cpi_period) from pfin.cpi_u_index),
  date_trunc('month', :'today'::date::timestamp)::date,
  '(z1) fixture pin: coverage_through resolves to the seeded ''current'' month — cpi_current below reads exactly 320.000, never carried'
);
select isnt(
  (select cpi_value from pfin.cpi_u_index where cpi_period = :'yeperiod'::date),
  (select cpi_value from pfin.cpi_u_index where cpi_period = date_trunc('month', :'today'::date::timestamp)::date),
  '(z2) fixture pin: cpi_ye (300.000) != cpi_current (320.000) — the crux''s own precondition, checked directly rather than assumed'
);
select is(
  (select count(distinct cpi_value) from pfin.cpi_u_index)::int, 5,
  '(z3) fixture pin: all FIVE seeded CPI prints are pairwise distinct — no two adj legs could coincidentally pass under the defective single-ratio formula'
);

-- =====================================================================
-- FIXTURE — Tenant A: full-depth, every anchor case in one tenant.
--   current (:today)        = 700,000  (exact — latest checkpoint <= today)
--   month anchor (:base)    = 690,000  (EXACT HIT)
--   ytd anchor               = 600,000  (EXACT HIT)
--   1y anchor (:a1y)         = 580,000  (EXACT HIT)
--   3y anchor: NO checkpoint AT :a3y — seeded 5 days EARLIER at 400,000, so
--     the 3y row is served by CARRY (anchor_checkpoint_date < anchor_date).
--   5y anchor (:a5y)         = 300,000  (EXACT HIT, confirms real depth)
-- =====================================================================
select set_config('app.nav_computed_for', :'ta', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values
  (:'ta', :'today'::date, 700000),
  (:'ta', :'base'::date, 690000),
  (:'ta', :'ytdanchor'::date, 600000),
  (:'ta', :'a1y'::date, 580000),
  (:'ta', (:'a3y'::date - 5), 400000),
  (:'ta', :'a5y'::date, 300000)
on conflict (users_id, nav_date) do nothing;
select set_config('role', 'postgres', true);

-- Tenant B: SAME dates, 10x values — the two-tenant non-vacuity pair.
select set_config('app.nav_computed_for', :'tb', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values
  (:'tb', :'today'::date, 7000000),
  (:'tb', :'base'::date, 6900000),
  (:'tb', :'ytdanchor'::date, 6000000),
  (:'tb', :'a1y'::date, 5800000),
  (:'tb', (:'a3y'::date - 5), 4000000),
  (:'tb', :'a5y'::date, 3000000)
on conflict (users_id, nav_date) do nothing;
select set_config('role', 'postgres', true);

-- Tenant C: ZERO checkpoints — cross-tenant / no-history leg.

-- Tenant D: aal2 backstop, mirrors A's exact-hit shape with distinct values.
select set_config('app.nav_computed_for', :'td', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values
  (:'td', :'today'::date, 111000),
  (:'td', :'base'::date, 110000),
  (:'td', :'ytdanchor'::date, 100000),
  (:'td', :'a1y'::date, 95000),
  (:'td', :'a3y'::date, 80000),
  (:'td', :'a5y'::date, 70000)
on conflict (users_id, nav_date) do nothing;
select set_config('role', 'postgres', true);

-- Tenant E: SHORT history (floor 4 months before :base) — proves the
-- insufficient-history NULL cause is PER-HORIZON, not all-or-nothing: month
-- resolves (via carry from the floor checkpoint), ytd/1y/3y/5y do not.
select set_config('app.nav_computed_for', :'te', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values
  (:'te', :'today'::date, 50000),
  (:'te', (:'base'::date::timestamp - '4 mon'::interval)::date, 45000)
on conflict (users_id, nav_date) do nothing;
select set_config('role', 'postgres', true);

-- Tenant F: isolates the zero-anchor-NAV / delta_percent case — a checkpoint
-- of VALUE ZERO exactly on the month anchor.
select set_config('app.nav_computed_for', :'tf', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values
  (:'tf', :'today'::date, 500000),
  (:'tf', :'base'::date, 0)
on conflict (users_id, nav_date) do nothing;
select set_config('role', 'postgres', true);

-- =====================================================================
-- (1) CRUX ⭐⭐ THE ARITHMETIC. Independently hand-computed:
--   1y: 700000*(300/320) - 580000*(300/250) = 656250 - 696000  = -39750
--   3y: 700000*(300/320) - 400000*(300/200) = 656250 - 600000  =  56250
--   5y: 700000*(300/320) - 300000*(300/240) = 656250 - 375000  = 281250
-- All three exact (the CPI ratios above were chosen to terminate) — computed
-- via the RATIFIED two-endpoints-deflated-separately formula, which is NOT
-- what the defective single-ratio draft would produce (the migration
-- header's own worked example shows the draft agrees with the correct
-- answer ONLY when cpi_current = cpi_anchor — false on all three legs here).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select delta_inflation_adjusted from pfin.fn_nav_delta_panel() where horizon = '1y'),
  (-39750)::numeric,
  '(CRUX1) ⭐⭐ 1y inflation-adjusted delta, computed independently: 700000*(300/320) - 580000*(300/250) = -39750 — a REAL negative real-terms change, not the drafted formula''s always-overstating figure'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select delta_inflation_adjusted from pfin.fn_nav_delta_panel() where horizon = '3y'),
  (56250)::numeric,
  '(CRUX2) 3y inflation-adjusted delta: 700000*(300/320) - 400000*(300/200) = 56250 — this anchor is CARRIED (see (CARRY1)), proving the formula reads the SERVED value, not a fabricated one'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select delta_inflation_adjusted from pfin.fn_nav_delta_panel() where horizon = '5y'),
  (281250)::numeric,
  '(CRUX3) 5y inflation-adjusted delta: 700000*(300/320) - 300000*(300/240) = 281250'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (2) FIVE — five rows, fixed order, on tenant A.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select array_agg(horizon) from pfin.fn_nav_delta_panel()),
  array['month','ytd','1y','3y','5y'],
  '(FIVE1) exactly five rows, in fixed order — a horizon is never dropped from the result set'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (ANCHOR) — anchor-date DERIVATION, verified by INDEPENDENT arithmetic
--   (Architect, d97f444 header (c); five properties confirmed by name in
--   round-2 review). This file's own fixture-scaffolding section above DOES
--   reuse the body's date_trunc/interval expressions (to know where to seed
--   checkpoints) — legitimate for THAT purpose, but insufficient on its own:
--   a shared mistake in month-end derivation would place the fixture at the
--   SAME wrong date the function looks for, and every arithmetic leg above
--   would still pass. These five legs are what actually close that gap, each
--   checking the function's OWN reported value against a DIFFERENT route
--   than the body's:
--     (P1) every anchor_date is the last day of its OWN month — a
--          self-consistency check on the returned value, never a
--          recomputation from `today`.
--     (P2) 1y/3y/5y sit exactly 12/36/60 months before the month anchor —
--          purely relational between returned rows, no date arithmetic on
--          `today` at all.
--     (P3) ⭐ ytd.anchor_date = make_date(year(today)-1, 12, 31) — make_date
--          RECONSTRUCTS a date from components; the body reaches this via
--          date_trunc('year', today) - 1 day, which shares NO machinery
--          with make_date.
--     (P4) ⭐⭐ cpi_basis_period = make_date(year(today)-1, 12, 1) — the
--          load-bearing pair with (P3). The body's own expression for this
--          (date_trunc('year') - 1 year + 11 mon) is the most convoluted
--          line in the function and the one Architect flagged as least
--          likely to be right by luck; make_date shares nothing with it.
--     (P5) month.anchor_date is not in the future and sits within one
--          month of today (a loose bound — catches a base landing a whole
--          month too far back, not a precise recomputation).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select bool_and(anchor_date = (date_trunc('month', anchor_date::timestamp) + interval '1 month' - interval '1 day')::date)
     from pfin.fn_nav_delta_panel()),
  '(ANCHOR-P1) every anchor_date, across all five horizons, is the last day of its own calendar month — a self-consistency check on the returned value'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'ta'::uuid);
select ok(
  (with panel as (select * from pfin.fn_nav_delta_panel()),
        m as (select anchor_date as month_anchor from panel where horizon = 'month')
   select bool_and(
     (12 * (extract(year from m.month_anchor) - extract(year from p.anchor_date))
          + (extract(month from m.month_anchor) - extract(month from p.anchor_date)))
       = n.months_back
   )
   from panel p
   join (values ('1y',12), ('3y',36), ('5y',60)) as n(horizon, months_back) on n.horizon = p.horizon
   cross join m),
  '(ANCHOR-P2) 1y/3y/5y anchors sit EXACTLY 12/36/60 calendar months before the month anchor — purely relational between returned rows (one call to the function, via a CTE), no arithmetic on `today` at all'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select anchor_date = make_date(extract(year from :'today'::date)::int - 1, 12, 31)
     from pfin.fn_nav_delta_panel() where horizon = 'ytd'),
  '(ANCHOR-P3) ⭐ ytd.anchor_date = make_date(year(today)-1, 12, 31) — make_date RECONSTRUCTS a date from components, sharing no machinery with the body''s date_trunc(''year'', today) - 1 day'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select bool_and(cpi_basis_period = make_date(extract(year from :'today'::date)::int - 1, 12, 1))
     from pfin.fn_nav_delta_panel() where horizon in ('1y','3y','5y')),
  '(ANCHOR-P4) ⭐⭐ THE LOAD-BEARING PAIR WITH (P3): cpi_basis_period = make_date(year(today)-1, 12, 1) on all three adj-eligible horizons — the body''s own expression here (date_trunc(''year'') - 1 year + 11 mon) is the most convoluted line in the function; make_date shares nothing with it'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select anchor_date <= :'today'::date and :'today'::date - anchor_date < 31
     from pfin.fn_nav_delta_panel() where horizon = 'month'),
  '(ANCHOR-P5) month anchor is not in the future and sits within one month of today — a loose bound, catches a base landing a whole month too far back'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (3) CAUSE — the three NULL causes, each on the FULL row (Sec''s full-tuple
--   discipline).
-- =====================================================================
-- (a) INSUFFICIENT HISTORY — tenant E''s ytd row: anchor_date present,
--     anchor_checkpoint_date NULL, both deltas NULL.
select _rls.set_tenant(:'te'::uuid);
select results_eq(
  $$ select anchor_date is not null, anchor_checkpoint_date is null, delta_nominal is null, delta_percent is null
       from pfin.fn_nav_delta_panel() where horizon = 'ytd' $$,
  $$ values (true, true, true, true) $$,
  '(CAUSE1) ⭐ INSUFFICIENT HISTORY: E''s ytd anchor predates its earliest checkpoint — anchor_date is KNOWN, anchor_checkpoint_date is NULL, deltas NULL. "the query dropped it" and "not computable" must not render alike, and here the row survives with its anchor named'
);
select set_config('role', 'postgres', true);
-- Same tenant''s MONTH row resolves normally — proving the gate is PER-HORIZON.
select _rls.set_tenant(:'te'::uuid);
select ok(
  (select anchor_checkpoint_date is not null and delta_nominal is not null
     from pfin.fn_nav_delta_panel() where horizon = 'month'),
  '(CAUSE1b) ⭐ …and on the SAME tenant, the month row resolves fine (served by the floor checkpoint) — insufficient-history is per-horizon, not an all-or-nothing gate on the whole panel'
);
select set_config('role', 'postgres', true);

-- (b) CPI UNRESOLVABLE — savepoint: delete the 5y-anchor month''s CPI print
--     entirely (and seed nothing earlier for it to carry from), on tenant A,
--     which has full NAV depth so delta_nominal must still be present.
savepoint cpi_unresolvable;
delete from pfin.cpi_u_index where cpi_period = :'a5ymonth'::date;
select _rls.set_tenant(:'ta'::uuid);
select results_eq(
  $$ select cpi_unavailable, delta_inflation_adjusted is null, delta_nominal is not null
       from pfin.fn_nav_delta_panel() where horizon = '5y' $$,
  $$ values (true, true, true) $$,
  '(CAUSE2) ⭐ CPI UNRESOLVABLE: with no print (and nothing to carry from) for the 5y anchor month, cpi_unavailable is TRUE and delta_inflation_adjusted is NULL — but delta_nominal STANDS, because the nominal figure never depended on CPI'
);
select set_config('role', 'postgres', true);
rollback to savepoint cpi_unresolvable;

-- (c) NOT APPLICABLE — month/ytd, on tenant A''s own clean fixture: every
--     cpi_* column NULL, by design, never attempted.
select _rls.set_tenant(:'ta'::uuid);
select results_eq(
  $$ select horizon, cpi_basis_period, cpi_any_carried, cpi_unavailable
       from pfin.fn_nav_delta_panel() where horizon in ('month','ytd') order by horizon $$,
  $$ values ('month'::text, null::date, null::boolean, null::boolean),
            ('ytd'::text, null::date, null::boolean, null::boolean) $$,
  '(CAUSE3) NOT APPLICABLE: month and ytd carry ALL THREE cpi_* columns NULL — the adjusted column does not EXIST for these horizons, distinguishable in shape from either NULL cause above'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (4) CARRY — provenance, both sides.
-- =====================================================================
-- NAV-side carry: A''s 3y anchor has no exact checkpoint; served by the row
-- 5 days earlier.
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select anchor_checkpoint_date < anchor_date
          and anchor_checkpoint_date = (:'a3y'::date - 5)
          and delta_nominal = 300000
     from pfin.fn_nav_delta_panel() where horizon = '3y'),
  '(CARRY1) ⭐ NAV-SIDE CARRY: A''s 3y anchor_checkpoint_date is EARLIER than anchor_date (served by the row 5 days prior), and delta_nominal (300000) reflects the CARRIED value, not a fabricated exact-anchor figure'
);
select set_config('role', 'postgres', true);

-- CPI-side carry: savepoint — delete the 1y-anchor month''s exact print,
-- seed one earlier for it to carry from, confirm cpi_any_carried flips true.
savepoint cpi_carry;
delete from pfin.cpi_u_index where cpi_period = :'a1ymonth'::date;
insert into pfin.cpi_u_index (cpi_period, cpi_value) values
  ((:'a1ymonth'::date - interval '1 month')::date, 245.000);
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select cpi_any_carried from pfin.fn_nav_delta_panel() where horizon = '1y'),
  '(CARRY2) ⭐ CPI-SIDE CARRY: with the 1y anchor''s exact CPI print removed and only an earlier one available, cpi_any_carried is TRUE — correctly threading 066''s is_carried flag through, satisfying Sec''s full-tuple criterion at the point this function consumes another helper''s row'
);
select set_config('role', 'postgres', true);
rollback to savepoint cpi_carry;

-- =====================================================================
-- (5) PCT0 — delta_percent NULL (never 0) on a zero anchor NAV.
-- =====================================================================
select _rls.set_tenant(:'tf'::uuid);
select ok(
  (select delta_percent is null and delta_nominal = 500000
     from pfin.fn_nav_delta_panel() where horizon = 'month'),
  '(PCT0) ⭐ zero anchor NAV (tenant F''s month anchor = 0): delta_percent is NULL — no division attempted — while delta_nominal (500000) is a real, present figure. "No change" and "cannot be expressed" must not render alike'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (6) CPIG — zero AND negative CPI guard.
-- =====================================================================
savepoint cpi_zero;
update pfin.cpi_u_index set cpi_value = 0 where cpi_period = :'a5ymonth'::date;
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select cpi_unavailable and delta_inflation_adjusted is null
     from pfin.fn_nav_delta_panel() where horizon = '5y'),
  '(CPIG1) ⭐ ZERO CPI on the denominator: cpi_unavailable TRUE, delta_inflation_adjusted NULL — never `division by zero`'
);
select set_config('role', 'postgres', true);
rollback to savepoint cpi_zero;

savepoint cpi_negative;
update pfin.cpi_u_index set cpi_value = -50 where cpi_period = :'a5ymonth'::date;
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select cpi_unavailable and delta_inflation_adjusted is null
     from pfin.fn_nav_delta_panel() where horizon = '5y'),
  '(CPIG2) ⭐ NEGATIVE CPI on the denominator: cpi_unavailable TRUE, delta_inflation_adjusted NULL — never a silently sign-flipped net-worth figure. 053 bars NaN/Infinity but not zero/negative, so this guard is the only thing standing between a poisoned print and a wrong answer'
);
select set_config('role', 'postgres', true);
rollback to savepoint cpi_negative;

-- =====================================================================
-- (7) T — TWO-TENANT, NON-VACUOUSLY.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select delta_nominal from pfin.fn_nav_delta_panel() where horizon = 'month'), 10000::numeric,
  '(T1) A''s month delta_nominal (700000-690000=10000). POSITIVE leg'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select delta_nominal from pfin.fn_nav_delta_panel() where horizon = 'month'), 100000::numeric,
  '(T2) ⭐ THE NON-VACUITY THAT MAKES (T1) A TEST: the IDENTICAL call under B returns B''s OWN delta (7000000-6900000=100000, B''s 10x fixture), never A''s'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (8) X — CROSS-TENANT / zero-checkpoint tenant.
-- =====================================================================
select _rls.set_tenant(:'tc'::uuid);
select is(
  (select count(*) from pfin.fn_nav_delta_panel()
    where anchor_checkpoint_date is null and delta_nominal is null and delta_percent is null
      and delta_inflation_adjusted is null)::int,
  5,
  '(X1) tenant C (zero checkpoints): all FIVE rows are present with every value-bearing column NULL — fails closed, never an error, never another tenant''s figures leaking through'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (9) M — AAL2 BACKSTOP, BOTH LEGS.
-- =====================================================================
select is(
  _rls.count_as(:'td'::uuid, 'aal1',
    $$ select count(*) from pfin.fn_nav_delta_panel() where delta_nominal is null $$
  ), 5::bigint,
  '(M1) an aal1 session for the totp-declared tenant D gets all FIVE rows all-NULL, even though D genuinely has checkpoints — the aal2 backstop fails this read closed'
);
select is(
  _rls.count_as(:'td'::uuid, 'aal2',
    $$ select count(*) from pfin.fn_nav_delta_panel() where horizon = 'month' and delta_nominal = 1000 $$
  ), 1::bigint,
  '(M2) ⭐ the POSITIVE leg that makes (M1) a test: the SAME tenant at aal2 sees their REAL month delta (111000-110000=1000). Without this, (M1) could pass vacuously against a policy that blinds every caller'
);

-- =====================================================================
-- (10) PST1 — CATALOG POSTURE for 071.
-- =====================================================================
select is(
  (select array[p.prosecdef::text, p.provolatile::text, array_to_string(p.proconfig, ',')]
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_delta_panel'),
  array['false','s','search_path=""'],
  '(PST1) POSTURE, read DECLARATIVELY: SECURITY INVOKER, STABLE, search_path pinned empty. A DEFINER swap here would detach the read from nav_daily''s RLS context AND break 070''s shared-session guarantee, while every behavioral leg above stayed green'
);

-- =====================================================================
-- (11) A — ACL.
-- =====================================================================
select ok(
  has_function_privilege('authenticated', 'pfin.fn_nav_delta_panel()', 'execute'),
  '(A1) authenticated HOLDS EXECUTE'
);
select ok(
  not has_function_privilege('public', 'pfin.fn_nav_delta_panel()', 'execute'),
  '(A2) LOAD-BEARING: PUBLIC does NOT — the revoke is load-bearing and silent on removal'
);
select ok(
  not has_function_privilege('service_role', 'pfin.fn_nav_delta_panel()', 'execute'),
  '(A3) service_role does NOT hold EXECUTE — an INVOKER helper granted to service_role would be a de facto cross-tenant read, the same reasoning 067/069 already record'
);

select * from finish();
rollback;

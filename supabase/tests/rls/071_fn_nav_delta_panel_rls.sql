-- =====================================================================
-- Per-Wave battery — pfin.fn_nav_delta_panel() — the §2.1.3.a multi-horizon
--   NAV-delta backend (SELF-221; migration 071). SECURITY INVOKER
--   read-composition over pfin.nav_daily (054) + pfin.fn_cpi_u_index_for_period
--   (066), today from pfin.fn_server_today (070, same PR). No parameters —
--   tenant and "today" both derive from session state. Paired with the
--   migration in the SAME PR.
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/071_fn_nav_delta_panel.sql, commit
--   83cf781 (return-shape option A adds current_checkpoint_date; the
--   negative-anchor guard widens from `<> 0` to `> 0`; the two-clock/ytd
--   header paragraph gained a documentation-only correction, no code change —
--   see the migration header, no battery leg needed for that one), AND
--   supabase/migrations/072_fn_nav_delta_panel_real_percent.sql (the
--   §2.1.3.b AC3 amendment — DROP+CREATE adds delta_inflation_adjusted_percent
--   at ordinal 8, shifting cpi_basis_period/cpi_any_carried/cpi_unavailable
--   down one ordinal each; re-issues the grants and the comment the DROP
--   destroys). This file now binds to the CURRENT (072) object — there is
--   only one live `pfin.fn_nav_delta_panel()` at a time, so this battery
--   evolves with it rather than forking a parallel file per migration. Every
--   leg below is one line of 072's own QA TEST-PAIRING block (items 1-16;
--   items 1-12 inherited from 071, items 13-16 new at 072).
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
--   inflation-adjusted VALUE at (1) below — the crux 071 exists to fix, now
--   extended to the real-terms PERCENT 072 adds on the SAME fixture.
--
--   ⚠ POSITIONAL-READ AUDIT (072 handoff instruction): every one of the 34
--   legs inherited from 071 was checked against the ordinal shift. NONE of
--   them read the row positionally — each SELECT lists columns BY NAME (or
--   accesses a `select *`-sourced CTE's fields by name, see (ANCHOR-P2)),
--   which Postgres resolves by name regardless of physical catalog order.
--   No leg needed re-deriving; (SHAPE1) below is the ONE leg in this file
--   that deliberately reads the row positionally, by design, so an ordinal
--   regression is caught by name going forward instead of by accident.
--
--   Contract as landed (071 + 072):
--     returns table (horizon text, anchor_date date, anchor_checkpoint_date
--       date, current_checkpoint_date date, delta_nominal numeric,
--       delta_percent numeric, delta_inflation_adjusted numeric,
--       delta_inflation_adjusted_percent numeric, cpi_basis_period date,
--       cpi_any_carried boolean, cpi_unavailable boolean) — ELEVEN columns,
--       delta_inflation_adjusted_percent newly inserted at position 8 (072,
--       F/CTO ratify 2026-08-14, the §2.1.3.b AC3 amendment).
--     SECURITY INVOKER · STABLE · set search_path = '' · NO ARGUMENTS.
--     EXACTLY FIVE ROWS ALWAYS: month/ytd/1y/3y/5y, fixed order.
--     Formula: delta_inflation_adjusted = nav_current*(cpi_ye/cpi_current)
--       - nav_anchor*(cpi_ye/cpi_anchor) — THREE CPI observations, each
--       endpoint deflated separately THEN differenced (never the single-ratio
--       defective draft the 071 migration header records at length).
--     072: delta_inflation_adjusted_percent = delta_inflation_adjusted /
--       real_base * 100, where real_base = nav_anchor*(cpi_ye/cpi_anchor) —
--       the SAME deflated-anchor term the dollar formula's subtrahend already
--       is, bound once in the body. NULL — never 0 — wherever
--       delta_inflation_adjusted is NULL, or where real_base is not strictly
--       positive (equivalent to a non-positive anchor NAV under the CPI
--       guard, but written on the actual denominator). ⚠ NO ROUNDING IS
--       APPLIED — `numeric` division residue means an exact-equality leg
--       against a hand-computed decimal can RED on a correct function; use
--       ROUND or a tolerance (see (CRUX1P)).
--     delta_percent guard is `v_a_nav > 0` (was `<> 0`): a NEGATIVE anchor now
--       NULLs delta_percent too (a negative base inverts the sign), while
--       delta_nominal/delta_inflation_adjusted stay computed and unguarded.
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
-- │ (4)  CARRY carry provenance, THREE sides: a NAV anchor served by an earlier         │
-- │          checkpoint, a CPI leg actually carried (cpi_any_carried true), AND         │
-- │          (CARRY3, F/CTO ratify 2026-08-13 return-shape A) the CURRENT endpoint      │
-- │          itself carried — current_checkpoint_date older than today, identical      │
-- │          on all five rows, the cron-outage shape.                                  │
-- │ (5)  PCT0 delta_percent NULL (not 0, not a raise) on a zero anchor NAV, with        │
-- │          delta_nominal still present. (NEG1) the sibling: a NEGATIVE anchor NAV     │
-- │          also NULLs delta_percent (guard widened to `> 0`), while delta_nominal     │
-- │          AND delta_inflation_adjusted stay present — unguarded, sound over a        │
-- │          negative base.                                                            │
-- │ (6)  CPIG zero AND negative CPI on the denominator -> NULL adj, never raised,       │
-- │          never sign-flipped.                                                        │
-- │ (7)  T   two-tenant, non-vacuously: identical dates, different nav_values.          │
-- │ (8)  X   cross-tenant / zero-checkpoint tenant -> five all-NULL rows. (LEAK)         │
-- │          corrupt-the-control: nav_daily_select broken open to using(true) proves    │
-- │          A's read returns something OTHER than A's OWN row. Asserted as a           │
-- │          NEGATIVE (Sec finding, 2026-08-14: NOT a specific other tenant's value —    │
-- │          the A/B one-day offset defends A-vs-B ties, not a third party landing on    │
-- │          :base), so it is robust to whatever else the database carries.             │
-- │ (9)  M   aal2 backstop, both legs.                                                  │
-- │ (10) PST1 catalog posture for 071 (070's own posture is 070's own battery).         │
-- │ (11) A   ACL: authenticated yes, PUBLIC no, service_role no, anon no (A4, 072).      │
-- │ (12) TUP full-state-tuple discipline — every full-row assertion below reads         │
-- │          the WHOLE row (results_eq / multi-field ok()), never a single column       │
-- │          in isolation, satisfying Sec's criterion at the point of use. NOW          │
-- │          PRIMARY (072 item 12): the DROP+CREATE means a botched re-issue is         │
-- │          silent to any leg that doesn't read the full row.                          │
-- │ (13) SHAPE eleven columns by NAME, TYPE and ORDINAL, read off pg_proc's own         │
-- │          catalog (unnest WITH ORDINALITY) — the one leg that IS positional,         │
-- │          by design, so a future column drop/reorder is loud.                        │
-- │ (14) BASE0 NULL — never 0 — on a non-positive DEFLATED anchor base, both            │
-- │          sub-cases: zero anchor NAV (REALBASE0) and negative anchor NAV with a      │
-- │          positive current NAV (NEG1P) — both dollar columns still present,          │
-- │          only the two percent columns go NULL.                                     │
-- │ (15) CAUSE1c the insufficient-history NULL cause, now proven on an ADJ-ELIGIBLE     │
-- │          horizon (072's percent column goes NULL via that path too) — (CAUSE2)      │
-- │          and (CAUSE3) widened in place to cover the same column on the              │
-- │          CPI-unresolvable and not-applicable rows.                                  │
-- │ (16) COMMENT1 the catalog comment SURVIVES the DROP+CREATE — otherwise invisible    │
-- │          to every other leg, none of which reads it. (PST1)/(A1-A3) unchanged in    │
-- │          content but now PRIMARY, not confirmatory (the DROP defaults to            │
-- │          EXECUTABLE BY PUBLIC if the re-grant is ever dropped).                     │
-- └─ 072 item 1 (AMENDED): (CRUX1P/2P/3P) assert delta_inflation_adjusted_percent on the SAME
--    fixture as (CRUX1-3), rounded/exact per residue; (INV1) the co-null check plus the
--    same-sign-where-both-present check, needing nothing but the rows — ⚠ TENANT-A-SCOPED,
--    NOT a universal claim: the dollar/percent relation is a ONE-WAY implication (dollar NULL
--    -> percent NULL), never a biconditional (REALBASE0/NEG1P prove the dollar column STAYS
--    PRESENT while the percent goes NULL on a non-positive real_base) — INV1's co-null half
--    only holds because A's fixture never hits that state; do not widen INV1 to another
--    tenant's panel expecting it to still pass.
-- └──────────────────────────────────────────────────────────────────────────────────────┘
--
-- ⚠ `supabase db reset` is PROHIBITED — destroys F/CTO's active local test data.
--   Scratch database only, pg_prove via `supabase test db`, never bare psql.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

-- plan = 44 : the 34 inherited from 071 (3 fixture pins (Z) + 3 crux arithmetic
-- (CRUX) + 1 five-rows-order (FIVE) + 5 independent anchor-derivation properties
-- (ANCHOR-P1..P5) + 4 null-cause (CAUSE) + 4 carry provenance (CARRY1 NAV-side,
-- CARRY2 CPI-side, CARRY3 current-side, CARRY4 jan/feb basis-carry) + 1
-- zero-anchor percent (PCT0) + 1 negative-anchor percent (NEG1) + 2 CPI guard
-- (CPIG) + 2 two-tenant (T) + 1 cross-tenant (X) + 1 corrupt-the-control leak
-- canary (LEAK) + 2 aal2 (M) + 1 catalog posture (PST1) + 3 ACL (A)) + 10 new
-- at 072 (SHAPE1 + CRUX1P/CRUX2P/CRUX3P + INV1 + REALBASE0 + NEG1P + CAUSE1c +
-- COMMENT1 + A4 anon ACL, Sec finding). CAUSE2/CAUSE3/X1/M1 are WIDENED in
-- place (same leg, one more column in an existing predicate) — not counted
-- as new. (LEAK1) is REWRITTEN in place (Sec finding: assert the negative,
-- `<> 690000`, not the specific value `= 6900000` — see its own header) —
-- also not a count change.
select plan(44);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset
\set td '00000000-0000-0000-0000-000000000d71'
\set te '00000000-0000-0000-0000-000000000e71'
\set tf '00000000-0000-0000-0000-000000000f71'
\set tg '00000000-0000-0000-0000-000000000071'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc'), (:'td'), (:'te'), (:'tf'), (:'tg');
insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta','none'), (:'tb','none'), (:'tc','none'), (:'td','totp'), (:'te','none'), (:'tf','none'), (:'tg','none');

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
--   month anchor (:base)    = 690,000  — served by CARRY from (:base - 2), NOT
--     an exact hit. ⚠ Deliberately offset from B's exact-hit date below (Sec's
--     leak-canary note, see (LEAK1)): if A and B both sat exactly on :base, a
--     `using(true)` sabotage would find TWO rows tied on the same nav_date and
--     tie-break nondeterministically, making a corrupt-the-control leg flaky.
--     delta_nominal for the month horizon is UNCHANGED by this (still
--     700000-690000=10000 — only WHICH DATE serves it moves, not the value).
--   ytd anchor               = 600,000  (EXACT HIT)
--   1y anchor (:a1y)         = 580,000  (EXACT HIT)
--   3y anchor: NO checkpoint AT :a3y — seeded 5 days EARLIER at 400,000, so
--     the 3y row is served by CARRY (anchor_checkpoint_date < anchor_date).
--   5y anchor (:a5y)         = 300,000  (EXACT HIT, confirms real depth)
-- =====================================================================
select set_config('app.nav_computed_for', :'ta', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values
  (:'ta', :'today'::date, 700000),
  (:'ta', (:'base'::date - 2), 690000),
  (:'ta', :'ytdanchor'::date, 600000),
  (:'ta', :'a1y'::date, 580000),
  (:'ta', (:'a3y'::date - 5), 400000),
  (:'ta', :'a5y'::date, 300000)
on conflict (users_id, nav_date) do nothing;
select set_config('role', 'postgres', true);

-- Tenant B: SAME dates as A for ytd/1y/3y/5y, 10x values — the two-tenant
-- non-vacuity pair. Month anchor is the ONE exception: B sits EXACTLY on
-- :base (A does not, see above) — this is Sec's leak-canary date, the single
-- checkpoint only B holds at that exact date, used by (LEAK1) below.
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

-- Tenant G: current-side CARRY (cron-outage shape) — the LATEST checkpoint is
-- 10 days before :today, not fresh, so current_checkpoint_date must be that
-- older date on ALL FIVE rows, not today itself. Mirrors A's other anchors
-- so all five horizons still resolve cleanly.
select set_config('app.nav_computed_for', :'tg', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values
  (:'tg', (:'today'::date - 10), 750000),
  (:'tg', (:'base'::date - 2), 740000),
  (:'tg', :'ytdanchor'::date, 650000),
  (:'tg', :'a1y'::date, 630000),
  (:'tg', (:'a3y'::date - 5), 450000),
  (:'tg', :'a5y'::date, 350000)
on conflict (users_id, nav_date) do nothing;
select set_config('role', 'postgres', true);

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
-- of VALUE ZERO exactly on the month anchor. ALSO carries a NEGATIVE anchor
-- at the 1y checkpoint (-50,000) for the sibling negative-anchor leg (NEG1) —
-- 1y is adj-eligible, so this tenant proves delta_inflation_adjusted stays
-- present over a negative base too, not just delta_nominal.
-- 072 ADDITION (item 14(a), REALBASE0): a THIRD row at the 3y anchor, ALSO
-- value ZERO — 3y is adj-eligible (month is not), so this is the case the
-- month row can't reach: a zero anchor NAV feeding a zero DEFLATED base
-- (real_base = 0 * cpi_ratio = 0), which must NULL delta_inflation_adjusted_
-- percent by the SAME "never 0" principle as delta_percent, while
-- delta_nominal and delta_inflation_adjusted (500000*(300/320) - 0 = 468750)
-- both still stand. Additive only — does not touch the month/1y rows above.
select set_config('app.nav_computed_for', :'tf', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values
  (:'tf', :'today'::date, 500000),
  (:'tf', :'base'::date, 0),
  (:'tf', :'a1y'::date, -50000),
  (:'tf', :'a3y'::date, 0)
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
-- (1, AMENDED) 072 item 1 — THE AMENDED COLUMN: delta_inflation_adjusted_percent,
--   on the SAME fixture as (CRUX1-3). real_base = anchor NAV * (cpi_ye/cpi_anchor)
--   — the SAME term the dollar formula's subtrahend already is:
--     1y: real_base = 580000*(300/250) = 696000 (exact); percent = -39750/696000*100
--         ≈ -5.7112...% — NOT a terminating decimal (696000 = 2^5*3*5^3*29), so
--         ROUNDED per the migration header's own warning: exact equality here
--         would RED a correct function. Nominal delta_percent on the SAME row =
--         120000/580000*100 ≈ +20.69% — OPPOSITE SIGN from the real percent, the
--         one fixture shape no nominal-base substitution can reproduce (071's own
--         Tenant A fixture already produces this; no new tenant was needed).
--     3y: real_base = 400000*(300/200) = 600000 (the CARRIED anchor value, per
--         CARRY1); percent = 56250/600000*100 = 9.375 EXACT (this fixture's ratios
--         happen to terminate here).
--     5y: real_base = 300000*(300/240) = 375000; percent = 281250/375000*100 = 75
--         EXACT.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select round(delta_inflation_adjusted_percent, 2) = -5.71
          and round(delta_percent, 2) = 20.69
          and delta_inflation_adjusted_percent <> delta_percent
          and sign(delta_inflation_adjusted_percent) <> sign(delta_percent)
     from pfin.fn_nav_delta_panel() where horizon = '1y'),
  '(CRUX1P) ⭐⭐ 072 item 1, AMENDED COLUMN: 1y real-terms PERCENT against the deflated anchor (real_base = 580000*(300/250) = 696000): -39750/696000*100 ≈ -5.71%, ROUNDED (numeric division residue — exact equality would RED a correct function). OPPOSITE SIGN from the nominal delta_percent (+20.69%) — the two figures disagree about the DIRECTION of the change, which is exactly what a nominal-base substitution cannot reproduce'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select delta_inflation_adjusted_percent from pfin.fn_nav_delta_panel() where horizon = '3y'),
  9.375::numeric,
  '(CRUX2P) 3y real-terms percent, EXACT (this fixture''s ratios happen to terminate): real_base = 400000*(300/200) = 600000 (the CARRIED anchor value, per CARRY1); 56250/600000*100 = 9.375 exactly'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select delta_inflation_adjusted_percent from pfin.fn_nav_delta_panel() where horizon = '5y'),
  75::numeric,
  '(CRUX3P) 5y real-terms percent, EXACT: real_base = 300000*(300/240) = 375000; 281250/375000*100 = 75 exactly'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select bool_and((delta_inflation_adjusted is null) = (delta_inflation_adjusted_percent is null))
      and bool_and(delta_inflation_adjusted is null or delta_inflation_adjusted_percent is null
                   or sign(delta_inflation_adjusted) = sign(delta_inflation_adjusted_percent))
     from pfin.fn_nav_delta_panel()),
  '(INV1) ⭐ 072 item 1, the two invariants that need nothing but the returned rows: across A''s full five-row panel, delta_inflation_adjusted and delta_inflation_adjusted_percent are NULL TOGETHER on every row (month/ytd not-applicable, 1y/3y/5y both present) and, wherever both are present, carry THE SAME SIGN — exactly what fails first if the real_base > 0 guard is ever dropped'
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
-- (13) SHAPE — 072 item 13: RETURN SHAPE, eleven columns by NAME, TYPE and
--   ORDINAL. This is the ONE leg in this file that deliberately reads the
--   row POSITIONALLY — off pg_proc's own catalog storage (unnest(proargnames)
--   / proallargtypes WITH ORDINALITY), not a hand-written SELECT list (which
--   would just re-resolve every column by name regardless of physical order,
--   the reason none of the OTHER 42 legs in this file needed re-deriving for
--   the ordinal shift). delta_inflation_adjusted_percent sits at ordinal 8,
--   immediately after delta_inflation_adjusted; cpi_basis_period/
--   cpi_any_carried/cpi_unavailable each shift down one ordinal from 071 —
--   this is what makes a future accidental drop or reorder of a column loud.
-- =====================================================================
-- array_agg + is(), not results_eq(): pgTAP's results_eq() drives an internal
-- cursor EXCEPT that can raise "could not determine which collation to use"
-- comparing pg_proc's `name`-typed catalog columns against VALUES literals
-- (measured on this leg, local scratch DB, 2026-08-14) — array equality
-- sidesteps it entirely and is no less exact, since `is()` on arrays is a
-- plain element-wise comparison, not a set operation.
select is(
  (select array_agg(a.name::text || ':' || format_type(t.oid, null)::text order by a.ord)
     from pg_proc p,
          unnest(p.proargnames) with ordinality as a(name, ord)
          join unnest(p.proallargtypes) with ordinality as b(typid, ord2) on a.ord = b.ord2
          join pg_type t on t.oid = b.typid
    where p.pronamespace = 'pfin'::regnamespace and p.proname = 'fn_nav_delta_panel'),
  array['horizon:text', 'anchor_date:date', 'anchor_checkpoint_date:date',
        'current_checkpoint_date:date', 'delta_nominal:numeric', 'delta_percent:numeric',
        'delta_inflation_adjusted:numeric', 'delta_inflation_adjusted_percent:numeric',
        'cpi_basis_period:date', 'cpi_any_carried:boolean', 'cpi_unavailable:boolean'],
  '(SHAPE1) ⭐ 072 item 13: eleven columns by NAME, TYPE and ORDINAL, straight off pg_proc''s own catalog (unnest(proargnames)/proallargtypes WITH ORDINALITY, array_agg''d in ordinal order) — delta_inflation_adjusted_percent at ordinal 8 immediately after delta_inflation_adjusted; cpi_basis_period/cpi_any_carried/cpi_unavailable each shifted down one ordinal from 071'
);

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

-- (a, 072 item 15) INSUFFICIENT HISTORY on an ADJ-ELIGIBLE horizon — (CAUSE1)
--     above uses tenant E's ytd row, which is BOTH insufficient-history AND
--     not-applicable (ytd never carries a real-terms figure), so it cannot by
--     itself prove the percent column goes NULL via the insufficient-history
--     PATH rather than the not-applicable one. Tenant E's earliest checkpoint
--     (base - 4 months) is also more recent than the 1y anchor (base - 12
--     months), so E's 1y row is insufficient-history too — and 1y IS
--     adj-eligible, so this is the row that actually isolates the path.
select _rls.set_tenant(:'te'::uuid);
select results_eq(
  $$ select anchor_date is not null, anchor_checkpoint_date is null, delta_nominal is null,
            delta_percent is null, delta_inflation_adjusted is null, delta_inflation_adjusted_percent is null
       from pfin.fn_nav_delta_panel() where horizon = '1y' $$,
  $$ values (true, true, true, true, true, true) $$,
  '(CAUSE1c) ⭐ 072 item 15: INSUFFICIENT HISTORY on an ADJ-ELIGIBLE horizon — tenant E''s 1y anchor also predates its earliest checkpoint (unlike (CAUSE1)''s ytd row, 1y DOES carry real-terms columns when resolvable), so BOTH real-terms columns (delta_inflation_adjusted, and 072''s delta_inflation_adjusted_percent) go NULL via the insufficient-history path specifically, not the not-applicable or CPI-unresolvable one — the third distinct NULL cause, now proven on a row where the percent column could otherwise have existed'
);
select set_config('role', 'postgres', true);

-- (b) CPI UNRESOLVABLE — savepoint: delete the 5y-anchor month''s CPI print
--     entirely (and seed nothing earlier for it to carry from), on tenant A,
--     which has full NAV depth so delta_nominal must still be present.
savepoint cpi_unresolvable;
delete from pfin.cpi_u_index where cpi_period = :'a5ymonth'::date;
select _rls.set_tenant(:'ta'::uuid);
select results_eq(
  $$ select cpi_unavailable, delta_inflation_adjusted is null, delta_nominal is not null,
            delta_inflation_adjusted_percent is null
       from pfin.fn_nav_delta_panel() where horizon = '5y' $$,
  $$ values (true, true, true, true) $$,
  '(CAUSE2) ⭐ CPI UNRESOLVABLE: with no print (and nothing to carry from) for the 5y anchor month, cpi_unavailable is TRUE and BOTH real-terms columns (delta_inflation_adjusted, and 072''s delta_inflation_adjusted_percent — item 15) are NULL — but delta_nominal STANDS, because the nominal figure never depended on CPI'
);
select set_config('role', 'postgres', true);
rollback to savepoint cpi_unresolvable;

-- (c) NOT APPLICABLE — month/ytd, on tenant A''s own clean fixture: every
--     cpi_* column NULL, by design, never attempted.
select _rls.set_tenant(:'ta'::uuid);
select results_eq(
  $$ select horizon, cpi_basis_period, cpi_any_carried, cpi_unavailable, delta_inflation_adjusted_percent
       from pfin.fn_nav_delta_panel() where horizon in ('month','ytd') order by horizon $$,
  $$ values ('month'::text, null::date, null::boolean, null::boolean, null::numeric),
            ('ytd'::text, null::date, null::boolean, null::boolean, null::numeric) $$,
  '(CAUSE3) NOT APPLICABLE: month and ytd carry ALL FOUR cpi_*/real-terms-percent columns NULL (072 item 15 adds delta_inflation_adjusted_percent to this row) — the adjusted columns do not EXIST for these horizons, distinguishable in shape from either NULL cause above'
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

-- JAN/FEB BASIS-CARRY (Architect addendum, 83cf781 header): structural, not a
-- bug — cpi_ye names the December that JUST ENDED, whose print doesn't exist
-- yet (CPI publishes 1-2 months in arrears), so 066 serves it CARRIED and
-- cpi_any_carried comes back TRUE panel-wide for ~2 months every year. Needs
-- its OWN savepoint (not the crux fixture): omitting the basis December would
-- move cpi_ye and with it all three hand-computed crux values. Sharper than
-- "carried is true" alone: also asserts cpi_unavailable is FALSE on the SAME
-- rows — fences the conflation of "carried" with "unavailable", which is the
-- more damaging failure (it would suppress a real figure) and the exact
-- distinction SELF-222's copy rests on ("the year just turned" vs "the figure
-- can't be formed").
savepoint ye_carry;
delete from pfin.cpi_u_index where cpi_period = :'yeperiod'::date;
insert into pfin.cpi_u_index (cpi_period, cpi_value) values
  ((:'yeperiod'::date - interval '1 month')::date, 295.000);
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select bool_and(cpi_any_carried = true and cpi_unavailable = false)
     from pfin.fn_nav_delta_panel() where horizon in ('1y','3y','5y')),
  '(CARRY4) ⭐ JAN/FEB BASIS-CARRY: with the basis December''s print absent and only November''s available, cpi_any_carried is TRUE panel-wide across 1y/3y/5y AND cpi_unavailable stays FALSE on the same rows — a carried basis must never render as an unavailable one, or a real figure would be silently suppressed'
);
select set_config('role', 'postgres', true);
rollback to savepoint ye_carry;

-- CURRENT-side carry (F/CTO ratify 2026-08-13, return-shape option A): tenant
-- G's latest checkpoint is 10 days before :today, not a fresh same-day write
-- — the cron-outage shape. current_checkpoint_date must reflect that OLDER
-- date, IDENTICAL across all five rows (a store property, like
-- cpi_basis_period), and strictly less than today — the leg that would fail
-- if this column merely echoed :today instead of the checkpoint that
-- actually served it.
select _rls.set_tenant(:'tg'::uuid);
select ok(
  (select bool_and(current_checkpoint_date = (:'today'::date - 10)
                    and current_checkpoint_date < :'today'::date)
     from pfin.fn_nav_delta_panel()),
  '(CARRY3) ⭐ CURRENT-SIDE CARRY: tenant G''s current_checkpoint_date is 10 days before today (the cron-outage shape) on ALL FIVE rows, not today itself — every horizon''s delta is disclosed as measured against a stale present, which is exactly why this column earns its place (every delta has TWO endpoints; until now only the anchor side disclosed provenance)'
);
select set_config('role', 'postgres', true);

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

-- (NEG1) ⭐ the sibling to (PCT0): NEGATIVE anchor NAV (tenant F's 1y anchor
-- = -50000). delta_percent is NULL here too (guard is now `> 0`, not `<> 0` —
-- a negative base would otherwise invert the sign: -100 -> +100 reporting
-- -200%). delta_nominal and delta_inflation_adjusted are NOT guarded — both
-- must remain PRESENT, since they're arithmetically sound over a negative
-- base. Full row, per Architect's note: a partial check can't tell "percent
-- suppressed" from "everything suppressed".
select _rls.set_tenant(:'tf'::uuid);
select ok(
  (select delta_percent is null
          and delta_nominal = 550000
          and delta_inflation_adjusted is not null
     from pfin.fn_nav_delta_panel() where horizon = '1y'),
  '(NEG1) ⭐ NEGATIVE anchor NAV (tenant F''s 1y anchor = -50000): delta_percent is NULL (same NULL cause as the zero case, deliberately undiscriminated — no fourth signal exists), while delta_nominal (500000-(-50000)=550000) and delta_inflation_adjusted are BOTH still present — sound over a negative base, and NOT guarded'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (14) BASE0 — 072 item 14: NULL, never 0, on a non-positive DEFLATED anchor
--   base, both sub-cases. real_base = anchor NAV * (cpi_ye/cpi_anchor), so
--   either sub-case here composes with tenant F's existing rows above.
-- =====================================================================
-- (b) NEGATIVE anchor NAV with a POSITIVE current NAV — tenant F's 1y row
--     (current 500000, anchor -50000) already proven by (NEG1) for the dollar
--     column; this is the SAME row, the new percent column.
select _rls.set_tenant(:'tf'::uuid);
select ok(
  (select delta_inflation_adjusted_percent is null and delta_inflation_adjusted is not null
     from pfin.fn_nav_delta_panel() where horizon = '1y'),
  '(NEG1P) ⭐ 072 item 14(b): NEGATIVE ANCHOR NAV with a POSITIVE current NAV (tenant F''s 1y anchor = -50000, current = 500000) — real_base = -50000*(300/250) = -60000, NOT strictly positive, so delta_inflation_adjusted_percent is NULL while delta_inflation_adjusted itself stays present and sound over the negative base, exactly as (NEG1) already established for the dollar figure alone'
);
select set_config('role', 'postgres', true);

-- (a) ZERO anchor NAV on an ADJ-ELIGIBLE horizon — (PCT0) above used tenant
--     F's month anchor (also zero), but month is NOT adj-eligible, so it
--     cannot exercise real_base at all. Tenant F's NEW 3y row (also zero) is
--     the case that isolates it: real_base = 0*(300/200) = 0.
select _rls.set_tenant(:'tf'::uuid);
select results_eq(
  $$ select delta_nominal, delta_percent is null, delta_inflation_adjusted, delta_inflation_adjusted_percent is null
       from pfin.fn_nav_delta_panel() where horizon = '3y' $$,
  $$ values (500000::numeric, true, 468750::numeric, true) $$,
  '(REALBASE0) ⭐ 072 item 14(a): ZERO ANCHOR NAV on tenant F''s 3y checkpoint (0), a CPI-applicable horizon — real_base = 0*(300/200) = 0, not strictly positive, so delta_inflation_adjusted_percent is NULL (never 0) exactly like delta_percent already is on the same row; delta_nominal (500000) and delta_inflation_adjusted (500000*(300/320) - 0 = 468750) BOTH still stand — only the two percent columns go NULL, not the dollar ones'
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
      and delta_inflation_adjusted is null and delta_inflation_adjusted_percent is null)::int,
  5,
  '(X1) tenant C (zero checkpoints): all FIVE rows are present with every value-bearing column NULL, including 072''s delta_inflation_adjusted_percent — fails closed, never an error, never another tenant''s figures leaking through'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (LEAK) ⭐ CORRUPT-THE-CONTROL — proving RLS, not application logic, is the
--   fence. Sec's note: A's month-anchor checkpoint was deliberately dated
--   TWO DAYS BEFORE B's (see the Tenant A/B fixture comments above) — if both
--   sat on the IDENTICAL date, a `nav_daily_select` policy broken open to
--   `using (true)` would leave TWO rows tied on the same nav_date for the
--   at-or-before query, and "order by nav_date desc limit 1" would tie-break
--   nondeterministically, making this leg flaky rather than a reliable RED.
--   With the TWO-DAY gap, B's checkpoint is UNAMBIGUOUSLY the more recent
--   of the two once both are visible, so the A-vs-B leak is deterministic —
--   see below for what that guarantee does NOT extend to.
--   Savepoint-scoped; the real policy is restored immediately after.
-- =====================================================================
-- ⚠ (LEAK1) ASSERTS A NEGATIVE — the predicate is `nav_value is not null
--   and nav_value <> 690000` (Sec's required shape, 2026-08-14), NOT a bare
--   `<> 690000` or `isnt(..., 690000)`: on an empty result the subquery
--   yields NULL, and NULL compared either way is NULL/passes — the exact
--   vacuous-green path this leg exists to close. Fails closed on no rows,
--   written rather than relied on.
--
--   ⚠ TYPO-TRAP: `690000` (A's own value, Tenant A fixture above) and
--   `6900000` (B's canary, Tenant B fixture above) are BOTH live in this
--   file and differ by ONE DIGIT. `<> 690000` is deliberate — do NOT
--   "restore" it to `6900000` thinking a digit was dropped; that would
--   silently defeat the leg (it would stop checking that A sees something
--   other than its OWN value and start checking something else entirely).
--
--   WHAT CHANGED, AND THE LOSING SIDE OF THE TRADE: an earlier draft
--   asserted `= 6900000` and additionally proved B SPECIFICALLY was the
--   deterministic winner once the fence opened. The negative form proves
--   only that SOME foreign row wins, not WHICH one — that determinism is
--   exactly what a non-pristine database destroys, so trading it away is
--   what makes the leg hold everywhere rather than only on a fixture-only
--   DB. The trade was necessary, not cosmetic: the exact-match form's
--   determinism claim was already false outside a pristine fixture, and not
--   for the reason an earlier draft of THIS comment gave ("a more recent
--   row" — impossible, B's canary sits EXACTLY at :base, the maximum date
--   `nav_date <= :base` admits). The real failure mode was a TIE at :base,
--   not lateness: SELF-217 laid month-end checkpoints
--   (docs/records/self217-nav-seeding-run.md, tenant b1aa21a2), and :base is
--   itself a month-end, so a seeded tenant can land on B's exact date;
--   `order by nav_date desc limit 1` has no secondary sort key, so a tie's
--   winner is not guaranteed. Confirmed empirically on a scratch clone of
--   the seeded shared dev DB: the broken-open query returned 8267000 — a
--   THIRD tenant's value, neither A's own (690000) nor B's canary
--   (6900000) — proving a genuine leak of some other tenant's row, not a
--   more benign same-tenant artifact.
savepoint leak_canary;
alter policy nav_daily_select on pfin.nav_daily using (true);
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select nav_value is not null and nav_value <> 690000
     from pfin.nav_daily where nav_date <= :'base'::date order by nav_date desc limit 1),
  '(LEAK1) ⭐ CORRUPT-THE-CONTROL: with nav_daily_select broken OPEN, A''s month-anchor query returns a NON-NULL value OTHER than A''s own (690000) — proving RLS, not application logic, is what confines tenant A to its own rows. Fails CLOSED on an empty result rather than passing vacuously, and is robust to whichever other tenant''s row wins the read: RED here is the proof the fence is real; green here would mean this battery is blind to a broken policy'
);
select set_config('role', 'postgres', true);
rollback to savepoint leak_canary;

-- =====================================================================
-- (9) M — AAL2 BACKSTOP, BOTH LEGS.
-- =====================================================================
select is(
  _rls.count_as(:'td'::uuid, 'aal1',
    $$ select count(*) from pfin.fn_nav_delta_panel()
         where delta_nominal is null and delta_inflation_adjusted_percent is null $$
  ), 5::bigint,
  '(M1) an aal1 session for the totp-declared tenant D gets all FIVE rows all-NULL (delta_nominal AND 072''s delta_inflation_adjusted_percent both null on every row), even though D genuinely has checkpoints — the aal2 backstop fails this read closed'
);
select is(
  _rls.count_as(:'td'::uuid, 'aal2',
    $$ select count(*) from pfin.fn_nav_delta_panel() where horizon = 'month' and delta_nominal = 1000 $$
  ), 1::bigint,
  '(M2) ⭐ the POSITIVE leg that makes (M1) a test: the SAME tenant at aal2 sees their REAL month delta (111000-110000=1000). Without this, (M1) could pass vacuously against a policy that blinds every caller'
);

-- =====================================================================
-- (10) PST1 — CATALOG POSTURE. ⭐ 072 item 16: content UNCHANGED from 071 (072
--   re-issues the SAME posture), but NOW PRIMARY, not confirmatory — the
--   DROP+CREATE means a botched re-issue after a future amendment would be
--   silent to every behavioral leg in this file, and this is one of the two
--   that would actually catch it.
-- =====================================================================
select is(
  (select array[p.prosecdef::text, p.provolatile::text, array_to_string(p.proconfig, ',')]
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_delta_panel'),
  array['false','s','search_path=""'],
  '(PST1) POSTURE, read DECLARATIVELY: SECURITY INVOKER, STABLE, search_path pinned empty. A DEFINER swap here would detach the read from nav_daily''s RLS context AND break 070''s shared-session guarantee, while every behavioral leg above stayed green'
);

-- 072 item 16: the catalog COMMENT is destroyed by the same DROP that
-- destroys the grants (see (A1-A3) below) and re-issued by the migration —
-- but unlike the grants, nothing else in this file ever reads it, so its
-- silent absence would be invisible without a dedicated leg. Checks for the
-- stable 'SECURITY INVOKER' marker every function comment in this migration
-- family opens with, not the full text (expected to be re-worded over time).
select ok(
  obj_description('pfin.fn_nav_delta_panel()'::regprocedure, 'pg_proc') is not null
    and obj_description('pfin.fn_nav_delta_panel()'::regprocedure, 'pg_proc') ~ 'SECURITY INVOKER',
  '(COMMENT1) ⭐ 072 item 16: the catalog comment SURVIVES the DROP+CREATE — its absence would otherwise be invisible to every other leg in this file'
);

-- =====================================================================
-- (11) A — ACL. ⭐ 072 item 16: content UNCHANGED from 071, NOW PRIMARY — a
--   freshly created function is EXECUTABLE BY PUBLIC by default, so these
--   legs are what catch a forgotten revoke/grant after the DROP. (A4) is
--   NEW here (Sec finding, 2026-08-14): no leg in this family pinned `anon`
--   specifically before now — 064 has one, 062/067/069/070/071 do not. anon
--   is the role reached WITHOUT a JWT at all, so it closes a family-wide
--   convention gap rather than responding to a specific defect.
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
select ok(
  not has_function_privilege('anon', 'pfin.fn_nav_delta_panel()', 'execute'),
  '(A4) ⭐ Sec finding, 072-adjacent: anon does NOT hold EXECUTE — anon is the role reached WITHOUT a JWT at all, so this is the fence in front of every OTHER identity check this function depends on (RLS keys off auth.uid(), which anon never carries). Closes a family-wide convention gap: 064 has this leg, 062/067/069/070/071 do not'
);

select * from finish();
rollback;

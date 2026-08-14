-- =====================================================================
-- Per-Wave battery — pfin.fn_nav_reference_dates() — the §2.1.4 NAV-at-
--   three-reference-dates backend. SECURITY INVOKER read-composition over
--   pfin.nav_daily (054) + pfin.fn_cpi_u_index_for_period (066), today from
--   pfin.fn_server_today (070). No parameters — tenant and "today" both
--   derive from session state. Paired with the migration in the SAME PR.
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/073_fn_nav_reference_dates.sql.
--   Every leg below is one line of that migration's own QA TEST-PAIRING
--   block (items 1-14), except (LEAK1) and the (REF-P*) anchor-derivation
--   set, which are not individually itemized there but follow the family
--   convention 071/072 already established (a corrupt-the-control canary,
--   and independent-arithmetic proof of every calendar derivation) — called
--   out explicitly here so a reader does not go looking for them in the
--   migration header and come up empty.
--
--   ⚠ NO p_as_of PARAMETER — DELIBERATE, same argument as 071/072: "today"
--   is derived internally via 070, the SESSION's live `current_date`.
--   Fixture checkpoint dates and expected-value computations below are
--   expressed RELATIVE TO `pfin.fn_server_today()` captured ONCE at the top
--   of this transaction, using the IDENTICAL date-resolution expressions the
--   migration body uses (base month-end, ye_period, ye_date) — fixture
--   SCAFFOLDING, not the thing under test. What IS independently computed,
--   by hand, in plain arithmetic, are the deflated VALUES at (2) and the
--   reconciliation at (3) — the crux this migration exists to compute
--   correctly.
--
--   Contract as landed:
--     returns table (reference text, reference_date date,
--       reference_checkpoint_date date, nav numeric,
--       nav_prior_yr_dollars numeric, cpi_period date, cpi_basis_period date,
--       cpi_any_carried boolean, cpi_unavailable boolean) — NINE columns.
--     SECURITY INVOKER · STABLE · set search_path = '' · NO ARGUMENTS.
--     EXACTLY THREE ROWS ALWAYS: this_month/prior_month/prior_year_end,
--     fixed order.
--     Formula: nav_prior_yr_dollars = nav * (cpi_basis / cpi_at_reference) —
--     level deflation (the 067 shape), NOT the two-endpoints-differenced
--     shape 072 uses for a DELTA — this surface returns LEVELS.
--     TWO null causes, not three (072's not-applicable cause does not exist
--     here — every row is CPI-eligible). The history predicate is PER ROW.
--
-- ┌─ WHAT THIS BATTERY PROVES — one line per migration-header QA TEST-PAIRING item ────┐
-- │ (1)  EXACT ⭐ prior_year_end EXACTNESS: nav_prior_yr_dollars = nav (numeric =,      │
-- │          never text/display), AND cpi_period = cpi_basis_period (provenance        │
-- │          form). Scoped to cpi_unavailable = false — the equality is FALSE           │
-- │          without that scope, proven at (CAUSE2) on the SAME row.                    │
-- │ (2)  ARITH ⭐⭐ this_month / prior_month deflation, independently computed. Reads    │
-- │          the seeded CPI value at assertion time rather than a hardcoded literal —   │
-- │          :basemonth collides with the basis period in January (Architect finding),  │
-- │          and this stays correct on both sides of that collision.                    │
-- │ (—)  ARREARS ⭐ realistic CPI arrears, family convention (not itemized in the        │
-- │          migration header): (z1) pins coverage_through to the current month,        │
-- │          removing arrears — the NORMAL production state. Proves this_month's        │
-- │          deflation follows coverage_through's real fallback once that pin is        │
-- │          removed, without spending a slot on the specific January all-three-exact   │
-- │          case Architect found (documented in prose, Architect's call to spend a     │
-- │          slot on it).                                                               │
-- │ (3)  RECON ⭐ THE TWO-PANEL RECONCILIATION against pfin.fn_nav_delta_panel() (072)   │
-- │          on the SAME seeded fixture: level differences equal the panel's deltas,    │
-- │          and the current-side checkpoint dates agree. this_month and prior_month    │
-- │          seeded with DIFFERENT checkpoints so the two rows cannot coincide.         │
-- │ (4)  THREE three rows always, fixed order, incl. a zero-checkpoint tenant.          │
-- │ (—)  REF-P anchor-date DERIVATION verified by INDEPENDENT arithmetic (071/072       │
-- │          precedent): this_month = today (trivial pin), prior_month self-           │
-- │          consistency (last day of its own month), prior_year_end AND                │
-- │          cpi_basis_period reconstructed via make_date — neither recomputed with     │
-- │          the body's own date_trunc/interval expression.                            │
-- │ (5)  CAUSE the two NULL causes distinguished on the full row: insufficient          │
-- │          history, proven on prior_year_end TOGETHER WITH prior_month (⚠ REVISED —   │
-- │          per-row split between those two is structurally impossible in January,     │
-- │          Architect finding; divergence pinned on this_month vs the other two        │
-- │          instead, which holds year-round) and CPI-unresolvable (basis corrupted,    │
-- │          cascades to all three rows — cpi_basis_period stays non-null throughout,   │
-- │          (6)).                                                                      │
-- │ (7)  CARRY carry provenance, THREE sides: a NAV reference served by an earlier      │
-- │          checkpoint (prior_month), a CPI reference-leg carried (ordinary months;    │
-- │          collapses onto the basis-leg case in January, documented not engineered    │
-- │          around), AND THE BASIS LEG CARRIED ALONE still ORs true table-wide.        │
-- │ (8)  CPIG zero AND negative CPI on the denominator -> NULL, never raised, never     │
-- │          sign-flipped. this_month's own print (⚠ REVISED from prior_month, which    │
-- │          collides with the shared basis in January) — always isolation-safe. PLUS   │
-- │          the SHARED BASIS print negative (Sec finding: previously unexercised,      │
-- │          table-wide cascade, not a duplicate of the this_month leg).                │
-- │ (9)  T   two-tenant, non-vacuously: identical dates, different nav_values.          │
-- │ (10) X   cross-tenant / zero-checkpoint tenant -> three all-NULL rows.              │
-- │ (—)  LEAK ⭐ corrupt-the-control, family convention (not itemized in the migration   │
-- │          header): nav_daily_select broken open to using(true) must surface a       │
-- │          value OTHER than A's own. Probes fn_nav_reference_dates() ITSELF, not the  │
-- │          table (Sec finding — a table-level probe cannot catch a redundant local    │
-- │          predicate added to the function). NEGATIVE predicate from the start        │
-- │          (071/072's fragile exact-match trap is not repeated here) — fails closed   │
-- │          on an empty result, robust to whichever other tenant's row wins.           │
-- │ (11) M   aal2 backstop, both legs.                                                  │
-- │ (12) PST1 catalog posture.                                                          │
-- │ (13) A   ACL: authenticated yes, PUBLIC no, service_role no, anon no.               │
-- │ (14) TUP full-state-tuple discipline — every full-row assertion below reads         │
-- │          the WHOLE row (results_eq / multi-field ok()), never a single column       │
-- │          in isolation.                                                              │
-- └──────────────────────────────────────────────────────────────────────────────────────┘
--
-- ⚠ `supabase db reset` is PROHIBITED, in ANY form, ANY flags — standing order.
--   Verify non-destructively on a hand-built scratch DB (createdb + psql -f),
--   pg_prove-equivalent via `supabase test db`, never bare psql.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

-- plan = 38 : 2 fixture pins (Z — z3's "3 pairwise-distinct values" claim was
-- dropped, it is false in the January CPI-period collision, see the fixture
-- note below) + 2 prior-year-end exactness (EXACT) + 2 arithmetic (ARITH) +
-- 1 realistic-CPI-arrears proof (ARREARS1 — not itemized in the migration
-- header, added per Architect's second-round finding: (z1)'s fixture pin
-- removes arrears, the normal production state) + 3 two-panel reconciliation
-- (RECON) + 1 three-rows-order (THREE) + 4 independent reference-date
-- derivation (REF-P1..P4) + 3 null-cause (CAUSE1 insufficient-history on
-- prior_year_end unconditionally + CAUSE1-prior_month the same, asserting
-- the month-end coincidence positively rather than skipping it + CAUSE1b
-- per-row-gate proof on this_month) + 1 CPI-unresolvable full-table (CAUSE2,
-- also proves item 6) + 1 NAV-side carry on an isolated tenant (CARRY1) + 2
-- CPI-side carry (CARRY-CPI1 reference-leg-only, CARRY-CPI2 basis-only) + 5
-- CPI guard (CPIG1 zero + CPIG1b prior_year_end unconditional + CPIG1c
-- prior_month, asserting the coincidence positively + CPIG2 negative on
-- this_month's own print + CPIG3 negative on the SHARED BASIS print, Sec
-- finding — the other half of the positivity guard, previously
-- unexercised, table-wide cascade) + 2 two-tenant (T) + 1 cross-tenant (X)
-- + 1 corrupt-the-control leak canary (LEAK — Sec finding: now probes
-- fn_nav_reference_dates() itself, not pfin.nav_daily directly) + 2 aal2
-- (M) + 1 catalog posture (PST1) + 4 ACL (A, incl. anon).
select plan(38);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset
\set td '00000000-0000-0000-0000-000000000d73'
\set te '00000000-0000-0000-0000-000000000e73'
\set tf '00000000-0000-0000-0000-000000000f73'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc'), (:'td'), (:'te'), (:'tf');
insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta','none'), (:'tb','none'), (:'tc','none'), (:'td','totp'), (:'te','none'), (:'tf','none');

-- =====================================================================
-- REFERENCE-DATE SCAFFOLDING — mirrors the migration body's OWN date
-- expressions exactly (070's answer, then base/ye_period/ye_date). Not the
-- thing under test (the migration's reference-date FORMULA is a documented
-- product default carried over from 071/072, not a correctness crux here);
-- it is how this file knows which calendar dates to seed checkpoints and CPI
-- prints at, regardless of which real day this battery happens to run on.
-- =====================================================================
select pfin.fn_server_today() as today \gset
select (case
          when :'today'::date = (date_trunc('month', :'today'::date::timestamp)
                                  + '1 mon'::interval - '1 day'::interval)::date
          then :'today'::date
          else (date_trunc('month', :'today'::date::timestamp) - '1 day'::interval)::date
        end) as base \gset
select (date_trunc('year', :'today'::date::timestamp) - '1 day'::interval)::date as yedate \gset
select (date_trunc('year', :'today'::date::timestamp) - '1 year'::interval + '11 mon'::interval)::date as yeperiod \gset
select date_trunc('month', :'base'::date::timestamp)::date as basemonth \gset

-- =====================================================================
-- FIXTURE — CPI-U (global; shared across every tenant below).
--   cpi_ye (basis, Dec of prior year)                    = 300.000
--   cpi_this_month (coverage_through — the LATEST seeded) = 320.000
--   cpi_prior_month (first-of-month of :base)             = 250.000, IF that
--     period differs from :yeperiod — see the collision note below.
-- Chosen so cpi_ye/cpi_this_month (0.9375) and cpi_ye/cpi_prior_month (1.2)
-- both reduce to TERMINATING decimals where they apply — a wrong formula
-- cannot hide behind a repeating-decimal coincidence. prior_year_end's own
-- CPI period IS :yeperiod (the basis itself, structural — not a fourth value
-- to seed).
--
-- ⚠ COLLISION, MEASURED (Architect, 2026-08-14): date_trunc('month', :base)
-- (prior_month's own CPI period) EQUALS :yeperiod (the basis period) FOR ANY
-- RUN DAY IN JANUARY — because the most recent completed month-end in
-- January IS 31 December of the prior year, the SAME December the basis
-- names. There is then only ONE real distinct period to seed, not two, and
-- `on conflict (cpi_period) do nothing` on the second insert lets the basis
-- value (300) silently govern it — which is CORRECT (there is genuinely one
-- CPI print for that shared period), not a workaround. (ARITH2) below reads
-- whichever value actually landed rather than assuming 250, so it stays
-- correct on both sides of the collision. IN THAT SAME MONTH, prior_month's
-- deflator becomes v/v = 1 too — prior_year_end is not the ONLY exact row
-- every month; it is the row whose CPI period is ALWAYS the basis period,
-- and prior_month joins it for the one month a year the two coincide.
-- Nothing below claims prior_year_end is uniquely exact.
--
-- ⚠ A SECOND COLLISION, MEASURED SEPARATELY (any run day where :today is
-- ITSELF a month-end, e.g. 31 December — not January-specific): :basemonth
-- (date_trunc('month', :base)) EQUALS date_trunc('month', :today) when
-- :base = :today, because prior_month's period and this_month's period are
-- the SAME expression on that one day. INSERT ORDER is what resolves it:
-- yeperiod, then this_month's period, THEN basemonth — each later insert
-- `on conflict do nothing`, so basemonth ALWAYS defers to whichever of the
-- other two it might collide with, never the reverse (a plain insert with
-- no guard crashed on this exact day when it ran last — measured). (ARITH2)
-- already reads the governing value dynamically, so this resolution order
-- does not need to be threaded through any assertion, only through the
-- insert sequence itself.
-- =====================================================================
delete from pfin.cpi_u_index;
insert into pfin.cpi_u_index (cpi_period, cpi_value) values (:'yeperiod'::date, 300.000);
insert into pfin.cpi_u_index (cpi_period, cpi_value) values
  (date_trunc('month', :'today'::date::timestamp)::date, 320.000)
  on conflict (cpi_period) do nothing;
insert into pfin.cpi_u_index (cpi_period, cpi_value) values (:'basemonth'::date, 250.000)
  on conflict (cpi_period) do nothing;

-- (z) fixture pins.
select is(
  (select max(cpi_period) from pfin.cpi_u_index),
  date_trunc('month', :'today'::date::timestamp)::date,
  '(z1) fixture pin: coverage_through resolves to the seeded ''current'' month — cpi_this_month below reads exactly 320.000, never carried'
);
select isnt(
  (select cpi_value from pfin.cpi_u_index where cpi_period = :'yeperiod'::date),
  (select cpi_value from pfin.cpi_u_index where cpi_period = date_trunc('month', :'today'::date::timestamp)::date),
  -- ⚠ SCOPED TO THIS FIXTURE (Architect finding, 2026-08-14, second round):
  -- an earlier version of this claim said "structurally never December of
  -- the prior year, so this holds on every run day" — true of THIS fixture
  -- (z1 pins coverage_through to the current month, seeded fresh every run),
  -- but FALSE of the function in general under realistic CPI arrears:
  -- Architect measured that in January, with coverage_through genuinely
  -- lagging to December of the prior year (one-to-two-month arrears, the
  -- normal production state), this_month's CPI period IS the basis period —
  -- all three rows become exact that month. That state is a real, correct,
  -- product-visible behavior this battery does not exercise (see ARREARS1
  -- below) because z1 deliberately removes the arrears this fixture pin
  -- would otherwise be checking. The claim below is about the FIXTURE, not
  -- a structural guarantee of the function.
  '(z2) fixture pin: cpi_ye (300.000) != cpi_this_month (320.000) UNDER THIS FIXTURE''S z1 PIN — the arithmetic legs'' own precondition here, checked directly rather than assumed. Not a general property of the function: see (ARREARS1) for the realistic-arrears case where this equality can legitimately fail'
);

-- =====================================================================
-- FIXTURE — Tenant A: full-depth, every reference case in one tenant.
--   this_month (:today - 1)    = 700,000  — served by CARRY from one day
--     before :today, NOT an exact hit. Deliberately offset from B's exact
--     hit below (the (LEAK1) leak-canary trap, same reasoning 072's own
--     Tenant A/B fixture already records): if A and B both sat exactly on
--     :today, a `using (true)` sabotage would find rows from BOTH tenants
--     tied on the same nav_date, and "order by nav_date desc limit 1" would
--     tie-break nondeterministically — occasionally returning A's OWN row
--     even with the fence broken, which would falsely pass the negative
--     predicate at (LEAK1) for the wrong reason. Reference_date (the
--     CALENDAR reference) is unaffected either way — it is always :today
--     regardless of which checkpoint serves it (REF-P1).
--   prior_month (:base)        = 690,000  — served by CARRY from (:base - 2),
--     NOT an exact hit, and deliberately a DIFFERENT checkpoint from
--     this_month's (item 3's own trap: if the latest checkpoint IS the
--     month-end, the two rows coincide and the reconciliation leg passes
--     without exercising anything).
--   prior_year_end (:yedate)   = 600,000  (EXACT HIT)
--   These are the SAME numbers 072's own Tenant A fixture uses for
--   current/month-anchor/ytd-anchor — deliberately, so the two-panel
--   reconciliation at (3) is checking a real cross-surface agreement, not a
--   coincidence engineered independently in each file.
-- =====================================================================
select set_config('app.nav_computed_for', :'ta', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values
  (:'ta', (:'today'::date - 1), 700000),
  (:'ta', (:'base'::date - 2), 690000),
  (:'ta', :'yedate'::date, 600000)
on conflict (users_id, nav_date) do nothing;
select set_config('role', 'postgres', true);

-- Tenant B: SAME dates as A for prior_month/prior_year_end, 10x values — the
-- two-tenant non-vacuity pair. this_month is the ONE exception: B sits
-- EXACTLY on :today (A does not, see above) — this is the leak-canary date,
-- the single checkpoint only B holds at that exact date, used by (LEAK1).
select set_config('app.nav_computed_for', :'tb', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values
  (:'tb', :'today'::date, 7000000),
  (:'tb', (:'base'::date - 2), 6900000),
  (:'tb', :'yedate'::date, 6000000)
on conflict (users_id, nav_date) do nothing;
select set_config('role', 'postgres', true);

-- Tenant C: ZERO checkpoints — cross-tenant / no-history leg.

-- Tenant D: aal2 backstop, exact hits throughout (not testing carry here).
select set_config('app.nav_computed_for', :'td', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values
  (:'td', :'today'::date, 111000),
  (:'td', :'base'::date, 110000),
  (:'td', :'yedate'::date, 100000)
on conflict (users_id, nav_date) do nothing;
select set_config('role', 'postgres', true);

-- Tenant E: ONE checkpoint, AT :today. ⚠ REVISED (Architect finding,
-- 2026-08-14): an earlier draft floored this checkpoint at ":base - 4
-- months", reasoned to always postdate :yedate — MEASURED FALSE for run
-- days January through May, where that offset lands AT-OR-BEFORE :yedate
-- and prior_year_end resolves when the leg needs it not to (the leg would
-- have REDS for five months of the year). Worse, in January specifically
-- :base EQUALS :yedate (the most recent completed month-end IS 31 December
-- of the prior year), so prior_month and prior_year_end are the SAME
-- reference_date that month — no fixture can split "prior_month resolves,
-- prior_year_end does not" between them in January; it is structurally
-- unprovable, not a fixture defect.
--   Pinning the divergence on this_month against the OTHER TWO sidesteps
-- both problems: a checkpoint AT :today satisfies "at-or-before :today"
-- (this_month resolves) but is STRICTLY AFTER :base and :yedate on every
-- ordinary day (:base is always <= :today by construction, :yedate always
-- further back still), so prior_month AND prior_year_end both correctly
-- find nothing — insufficient history on BOTH, proven every month of the
-- year, matching the migration header's own framing verbatim ("a tenant can
-- have enough history for this_month and not for prior_year_end").
--   ⚠ RESIDUAL: on the one day a year :today IS ITSELF a month-end
-- (:base = :today), this same checkpoint would ALSO satisfy prior_month's
-- query, collapsing (CAUSE1b)'s claim for that single day. This is the same
-- class of single-day residual (3)'s own trap already documents for the
-- reconciliation fixture — not eliminated, because eliminating it needs a
-- p_as_of this migration deliberately does not have.
select set_config('app.nav_computed_for', :'te', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values
  (:'te', :'today'::date, 45000)
on conflict (users_id, nav_date) do nothing;
select set_config('role', 'postgres', true);

-- Tenant F: NAV-SIDE CARRY, isolated. ⚠ ADDED (Architect finding, 2026-08-14
-- second round, measured on a simulated January run): tenant A's OWN
-- prior_month carry source (:base - 2) is NOT safe for this proof, because
-- in January prior_month's reference_date collapses onto :yedate (the
-- fixture-CPI-collision note above), and A ALSO holds an EXACT-HIT
-- checkpoint AT :yedate for prior_year_end — once prior_month's query is
-- ALSO asking "at-or-before :yedate", that later, more-recent exact-hit row
-- wins over the intended :base-2 carry source, and prior_month silently
-- becomes an exact hit too (measured: nav read 600000, A's prior_year_end
-- value, not A's own intended 690000). NAV-side carry and prior_year_end
-- exactness cannot be demonstrated on the SAME tenant in January — they are
-- mutually exclusive that month by the same structural fact as (CAUSE1)'s
-- own collision, one level down (checkpoints, not CPI periods). Tenant F
-- holds EXACTLY ONE checkpoint and nothing else, so there is never a
-- competing row for "at-or-before :base" to prefer — the carry holds on
-- every run day, unconditionally.
select set_config('app.nav_computed_for', :'tf', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values
  (:'tf', (:'base'::date - 2), 690000)
on conflict (users_id, nav_date) do nothing;
select set_config('role', 'postgres', true);

-- =====================================================================
-- (1) EXACT ⭐ prior_year_end EXACTNESS BY CONSTRUCTION. Neither leg below
--   claims prior_year_end is the ONLY exact row — it is the row whose CPI
--   period is ALWAYS the basis period; prior_month joins it for the one
--   month a year (January) the two periods coincide (fixture note above).
--   The property under test here is scoped to prior_year_end specifically
--   and is true on every run day regardless of what prior_month is doing.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select nav_prior_yr_dollars from pfin.fn_nav_reference_dates() where reference = 'prior_year_end'),
  (select nav from pfin.fn_nav_reference_dates() where reference = 'prior_year_end'),
  '(EXACT1) ⭐ prior_year_end nav_prior_yr_dollars EQUALS nav exactly (numeric =, not text/display) — both legs are the SAME request to 066 (v/v = 1), no residue'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select cpi_period from pfin.fn_nav_reference_dates() where reference = 'prior_year_end'),
  (select cpi_basis_period from pfin.fn_nav_reference_dates() where reference = 'prior_year_end'),
  '(EXACT2) provenance form of the same invariant: cpi_period = cpi_basis_period on prior_year_end — the row''s own reference-date CPI request and the basis request are literally the same period'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (2) ARITH ⭐⭐ this_month / prior_month DEFLATION, independently computed:
--   this_month (tenant A):  700000 * (300/320) = 656250 — cpi_basis (300)
--     <> cpi_at_reference (320) UNDER THIS FIXTURE'S z1 PIN (z2), so this leg
--     exercises a real deflation here; see (ARREARS1) for why z1's coverage
--     pin, not a structural guarantee, is what makes that hold.
--   prior_month (tenant F, ⚠ NOT A — see F's own fixture note above for why
--     A's prior_month NAV is not safe to hardcode): 690000 * (300/cpi_value
--     at :basemonth) — the CPI side is read from the SEEDED value at
--     assertion time rather than hardcoding 250, because :basemonth can
--     COLLIDE with :yeperiod in January (fixture note above): on ordinary
--     days this multiplies out to 690000*(300/250) = 828000; in the
--     collision month it correctly degrades to 690000*(300/300) = 690000
--     (prior_month becomes exact too, per that same note). The NAV side
--     (690000) is safe to hardcode HERE because tenant F holds nothing else
--     for the reference query to prefer.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select nav_prior_yr_dollars from pfin.fn_nav_reference_dates() where reference = 'this_month'),
  (656250)::numeric,
  '(ARITH1) ⭐⭐ this_month prior-year-dollars, computed independently: 700000*(300/320) = 656250'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tf'::uuid);
select is(
  (select nav_prior_yr_dollars from pfin.fn_nav_reference_dates() where reference = 'prior_month'),
  (select 690000 * (300.000 / cpi_value) from pfin.cpi_u_index where cpi_period = :'basemonth'::date),
  '(ARITH2) ⭐⭐ prior_month prior-year-dollars (tenant F): 690000*(300/cpi_at_:basemonth) — this reference is CARRIED (see (CARRY1)), proving the formula reads the SERVED value, not a fabricated exact-reference one. Reads the fixture''s actual seeded CPI value rather than a hardcoded 250, so this holds on both sides of the January CPI collision'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (ARREARS) ⭐ REALISTIC CPI ARREARS — not itemized in the migration header,
--   added per Architect's second-round finding (2026-08-14): (z1)'s fixture
--   pin (coverage_through = the current month, seeded fresh every run)
--   removes CPI arrears entirely, but arrears is the NORMAL production
--   state (CPI publishes one to two months behind — the migration header's
--   own words). This proves this_month's deflation reads whatever
--   coverage_through ACTUALLY resolves to once the current-month print is
--   absent — not a value baked into this fixture's assumptions — without
--   spending a plan slot reproducing the SPECIFIC product-visible case
--   Architect measured (realistic January arrears pushing coverage_through
--   onto the basis period itself, making all three rows exact for about a
--   month a year): that would need its own January-guarded branch, the same
--   shape as (CAUSE1-prior_month)/(CPIG1c) above, for one dated finding
--   rather than a defect. Recorded here in prose; Architect's own call to
--   spend a slot on it, not taken without agreement.
-- =====================================================================
savepoint cpi_arrears;
delete from pfin.cpi_u_index where cpi_period = date_trunc('month', :'today'::date::timestamp)::date;
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select nav_prior_yr_dollars from pfin.fn_nav_reference_dates() where reference = 'this_month'),
  (select 700000 * (300.000 / cpi_value)
     from pfin.cpi_u_index where cpi_period = (select max(cpi_period) from pfin.cpi_u_index)),
  '(ARREARS1) ⭐ with the current-month print absent (realistic arrears — the state (z1) otherwise pins away), this_month''s deflation reads whatever coverage_through ACTUALLY falls back to (the fixture''s remaining freshest print — the basis period itself in January, per Architect''s finding; the prior-month print otherwise), not the deleted value — proving the formula follows 066''s real coverage_through rather than an assumption this fixture bakes in'
);
select set_config('role', 'postgres', true);
rollback to savepoint cpi_arrears;

-- =====================================================================
-- (3) RECON ⭐ THE TWO-PANEL RECONCILIATION against pfin.fn_nav_delta_panel()
--   (072), on the SAME tenant-A fixture:
--     (this_month nav) - (prior_month nav)    = panel's 'month' delta_nominal
--       700000 - 690000 = 10000
--     (this_month nav) - (prior_year_end nav) = panel's 'ytd'   delta_nominal
--       700000 - 600000 = 100000
--   Both computed here from THIS function's own returned nav values, then
--   checked against 072's independently-computed delta_nominal for the same
--   tenant — the reconciliation this migration's header names as the reason
--   the anchors were chosen at all.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select r.nav - m.nav
     from pfin.fn_nav_reference_dates() r, pfin.fn_nav_reference_dates() m
    where r.reference = 'this_month' and m.reference = 'prior_month'),
  (select delta_nominal from pfin.fn_nav_delta_panel() where horizon = 'month'),
  '(RECON1) ⭐ this_month - prior_month (10000) EQUALS 072''s ''month'' delta_nominal on the same tenant — a reader subtracting two cells in this table lands exactly on the panel''s figure'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select r.nav - y.nav
     from pfin.fn_nav_reference_dates() r, pfin.fn_nav_reference_dates() y
    where r.reference = 'this_month' and y.reference = 'prior_year_end'),
  (select delta_nominal from pfin.fn_nav_delta_panel() where horizon = 'ytd'),
  '(RECON2) ⭐ this_month - prior_year_end (100000) EQUALS 072''s ''ytd'' delta_nominal on the same tenant'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select reference_checkpoint_date from pfin.fn_nav_reference_dates() where reference = 'this_month'),
  (select current_checkpoint_date from pfin.fn_nav_delta_panel() limit 1),
  '(RECON3) this_month''s reference_checkpoint_date EQUALS 072''s current_checkpoint_date — the SAME "now" endpoint disclosed the same way on both surfaces'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (4) THREE — three rows, fixed order, on tenant A.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select array_agg(reference) from pfin.fn_nav_reference_dates()),
  array['this_month','prior_month','prior_year_end'],
  '(THREE1) exactly three rows, in fixed order — a reference is never dropped from the result set'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (REF-P) — reference-date DERIVATION, verified by INDEPENDENT arithmetic
--   (071/072 precedent): each check reads the function's OWN reported value
--   against a DIFFERENT route than the body's date_trunc/interval
--   expression, so a shared mistake between this file's fixture scaffolding
--   and the body cannot hide.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select reference_date from pfin.fn_nav_reference_dates() where reference = 'this_month'),
  :'today'::date,
  '(REF-P1) this_month.reference_date = today, exactly — the trivial pin, but worth asserting explicitly since it is the row every other date in this table is expressed relative to'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select reference_date = (date_trunc('month', reference_date::timestamp) + interval '1 month' - interval '1 day')::date
     from pfin.fn_nav_reference_dates() where reference = 'prior_month'),
  '(REF-P2) prior_month.reference_date is the last day of its own calendar month — a self-consistency check on the returned value, never a recomputation from `today`'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'ta'::uuid);
select is(
  (select reference_date from pfin.fn_nav_reference_dates() where reference = 'prior_year_end'),
  make_date(extract(year from :'today'::date)::int - 1, 12, 31),
  '(REF-P3) ⭐ prior_year_end.reference_date = make_date(year(today)-1, 12, 31) — make_date RECONSTRUCTS a date from components, sharing no machinery with the body''s date_trunc(''year'', today) - 1 day'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select bool_and(cpi_basis_period = make_date(extract(year from :'today'::date)::int - 1, 12, 1))
     from pfin.fn_nav_reference_dates()),
  '(REF-P4) ⭐⭐ THE LOAD-BEARING PAIR WITH (REF-P3): cpi_basis_period = make_date(year(today)-1, 12, 1) on all three rows — the body''s own expression here (date_trunc(''year'') - 1 year + 11 mon) is the most convoluted line in the function; make_date shares nothing with it'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (5) CAUSE — the two NULL causes, each on the FULL row.
-- =====================================================================
-- (a) INSUFFICIENT HISTORY — tenant E''s prior_year_end row SPECIFICALLY,
--     proven together with prior_month (both fail identically; see the
--     fixture note above for why this pair, not prior_month vs
--     prior_year_end, is the divergence this leg can prove year-round).
--     ⚠ SECOND MEASURED RESIDUAL: on a run day where :today IS ITSELF a
--     month-end (:base = :today, ~12 days a year), E''s checkpoint AT :today
--     ALSO satisfies "at-or-before :base" — this_month and prior_month
--     become the SAME query on that one day, so prior_month resolves too
--     (measured: swept every month-end day in a year, all 12 reproduce it).
--     No fixture can avoid this: it is the empty-interval case "> base and
--     <= today" degenerating when base = today, the same shape as the
--     January impossibility one level down. Guarded rather than reworked
--     again — prior_year_end''s own insufficient-history proof (the row
--     this leg exists for) still holds unconditionally; only prior_month''s
--     half of the pairing is inapplicable that one day, and the CASE below
--     says so rather than silently passing or falsely redding.
select _rls.set_tenant(:'te'::uuid);
select ok(
  (select (reference_checkpoint_date is null and nav is null and nav_prior_yr_dollars is null)
     from pfin.fn_nav_reference_dates() where reference = 'prior_year_end'),
  '(CAUSE1) ⭐ INSUFFICIENT HISTORY, proven on prior_year_end SPECIFICALLY: E''s only checkpoint is AT :today, strictly after :yedate on every run day (:yedate <= :base <= :today, always), so "at-or-before :yedate" finds nothing — reference_checkpoint_date and both value columns are NULL. This is the row the UI renders as "Insufficient history"'
);
select set_config('role', 'postgres', true);
-- ⚠ STRENGTHENED (Architect's second finding, 2026-08-14): an earlier draft
-- guarded the month-end branch with a bare `else true` — vacuous on exactly
-- the ~12 days a year the coincidence is LIVE, and a 24-day calendar sweep
-- cannot catch a vacuous branch passing on every day it fires. Rewritten to
-- assert what SHOULD be true that day instead of skipping it: prior_month
-- and this_month share the identical reference_date, checkpoint and nav
-- (measured directly on run day 2026-09-30: both rows read reference_date
-- 2026-09-30, reference_checkpoint_date 2026-09-30, nav 45000).
select _rls.set_tenant(:'te'::uuid);
select ok(
  (with p as (select reference_date, reference_checkpoint_date, nav
                from pfin.fn_nav_reference_dates() where reference = 'prior_month'),
        m as (select reference_date, reference_checkpoint_date, nav
                from pfin.fn_nav_reference_dates() where reference = 'this_month')
   select case when :'base'::date < :'today'::date
            then p.reference_checkpoint_date is null and p.nav is null
            else p.reference_date = m.reference_date
                 and p.reference_checkpoint_date = m.reference_checkpoint_date
                 and p.nav = m.nav
          end
     from p cross join m),
  '(CAUSE1-prior_month) …and prior_month fails the SAME way on every ordinary run day; on the ~12 days a year :today is itself a month-end (:base = :today), prior_month and this_month become the SAME query BY CONSTRUCTION — asserted as identical reference_date/checkpoint/nav that day, not skipped'
);
select set_config('role', 'postgres', true);
-- Same tenant''s this_month resolves fine (exact hit at :today) — proving
-- the gate is PER-ROW, not all-or-nothing on the whole table.
select _rls.set_tenant(:'te'::uuid);
select ok(
  (select reference_checkpoint_date is not null and nav = 45000
     from pfin.fn_nav_reference_dates() where reference = 'this_month'),
  '(CAUSE1b) ⭐ …and on the SAME tenant, this_month resolves (exact hit at :today, 45000) while prior_month and prior_year_end both do not — insufficient-history is per-row, not an all-or-nothing gate on the whole table'
);
select set_config('role', 'postgres', true);

-- (b) CPI UNRESOLVABLE — savepoint: delete the BASIS print entirely (and
--     seed nothing earlier for it to carry from), on tenant A. Because
--     prior_year_end''s OWN reference-date CPI period IS the basis period,
--     corrupting the basis cascades to ALL THREE rows — there is no way to
--     make prior_year_end unresolvable in isolation, structurally, since its
--     leg and the basis leg are literally the same request. nav STANDS on
--     every row (nominal never depended on CPI); cpi_basis_period STAYS
--     NON-NULL throughout (item 6: it is a calendar label, not an
--     observation, and survives an unresolvable CPI).
savepoint cpi_unresolvable;
delete from pfin.cpi_u_index where cpi_period = :'yeperiod'::date;
select _rls.set_tenant(:'ta'::uuid);
select results_eq(
  $$ select reference, cpi_unavailable, nav is not null, nav_prior_yr_dollars is null, cpi_basis_period is not null
       from pfin.fn_nav_reference_dates() order by reference $$,
  $$ values ('prior_month'::text, true, true, true, true),
            ('prior_year_end'::text, true, true, true, true),
            ('this_month'::text, true, true, true, true) $$,
  '(CAUSE2) ⭐ CPI UNRESOLVABLE, table-wide: with no print (and nothing to carry from) for the basis period, cpi_unavailable is TRUE on ALL THREE rows — nav STANDS everywhere (nominal never depended on CPI), nav_prior_yr_dollars is NULL everywhere (including prior_year_end, proving (EXACT1)''s equality is FALSE without the cpi_unavailable=false scope), and cpi_basis_period stays NON-NULL throughout (072/071''s "calendar label, not an observation" property, item 6)'
);
select set_config('role', 'postgres', true);
rollback to savepoint cpi_unresolvable;

-- =====================================================================
-- (7) CARRY — provenance, three sides.
-- =====================================================================
-- NAV-side carry: tenant F''s prior_month has no exact checkpoint; served by
-- the row 2 days earlier. ⚠ TENANT F, NOT A — see F''s own fixture note
-- above: on tenant A, this exact proof (checkpoint < reference_date) is
-- FALSE in January, because A''s prior_year_end exact-hit checkpoint (at
-- :yedate) outranks A''s intended :base-2 carry source once prior_month''s
-- own reference_date collapses onto :yedate that month — measured, not
-- predicted. F holds nothing else, so nothing can outrank its one
-- checkpoint, on any run day.
select _rls.set_tenant(:'tf'::uuid);
select ok(
  (select reference_checkpoint_date < reference_date
          and reference_checkpoint_date = (:'base'::date - 2)
          and nav = 690000
     from pfin.fn_nav_reference_dates() where reference = 'prior_month'),
  '(CARRY1) ⭐ NAV-SIDE CARRY (tenant F): prior_month reference_checkpoint_date is EARLIER than reference_date (served by the row 2 days prior), and nav (690000) reflects the CARRIED value, not a fabricated exact-reference figure'
);
select set_config('role', 'postgres', true);

-- CPI-side carry, REFERENCE LEG ONLY: savepoint — delete prior_month''s exact
-- print, seed one earlier for it to carry from. Basis is untouched (any
-- ordinary month), so this isolates the reference leg''s own contribution to
-- the OR. ⚠ NOT ISOLATED IN JANUARY: :basemonth collides with :yeperiod that
-- month (fixture note above), so this savepoint and (CARRY-CPI2) below
-- become mechanically the same operation — deleting "prior_month''s own
-- print" IS deleting the basis print. The assertion still passes (it only
-- reads prior_month''s own row), it just stops being a distinguishing case
-- from (CARRY-CPI2) for that one month. Documented rather than engineered
-- around, matching the family''s existing tolerance for named calendar
-- coincidences (see 072''s jan/feb basis-carry header note).
savepoint cpi_carry_ref;
delete from pfin.cpi_u_index where cpi_period = :'basemonth'::date;
-- on conflict do nothing: the "-1 month" seed can itself collide with
-- another already-seeded period on some run days (measured on a February
-- run: :basemonth - 1 month landed exactly on :yeperiod, crashing a plain
-- insert with a duplicate-key error) — defer rather than raise.
insert into pfin.cpi_u_index (cpi_period, cpi_value) values
  ((:'basemonth'::date - interval '1 month')::date, 245.000)
  on conflict (cpi_period) do nothing;
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select cpi_any_carried and not cpi_unavailable
     from pfin.fn_nav_reference_dates() where reference = 'prior_month'),
  '(CARRY-CPI1) ⭐ CPI-SIDE CARRY, REFERENCE LEG: with prior_month''s exact CPI print removed and only an earlier one available, cpi_any_carried is TRUE and cpi_unavailable stays FALSE — the reference leg alone can flip the OR'
);
select set_config('role', 'postgres', true);
rollback to savepoint cpi_carry_ref;

-- CPI-side carry, BASIS LEG ONLY (the case explicitly measured before
-- drafting): savepoint — delete the basis print, seed one month earlier.
-- Because the basis is shared, cpi_any_carried must come back TRUE on ALL
-- THREE rows, even though each row''s OWN reference leg (this_month /
-- prior_month / prior_year_end''s own request) is unaffected.
savepoint cpi_carry_basis;
delete from pfin.cpi_u_index where cpi_period = :'yeperiod'::date;
-- on conflict do nothing, defensively, for the same reason as the sibling
-- savepoint above — not measured to collide on any swept run day, but cheap
-- insurance against the same crash class.
insert into pfin.cpi_u_index (cpi_period, cpi_value) values
  ((:'yeperiod'::date - interval '1 month')::date, 295.000)
  on conflict (cpi_period) do nothing;
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select bool_and(cpi_any_carried = true and cpi_unavailable = false)
     from pfin.fn_nav_reference_dates()),
  '(CARRY-CPI2) ⭐ CPI-SIDE CARRY, BASIS LEG ONLY: with the basis print absent and only an earlier one available, cpi_any_carried is TRUE table-wide (the OR captures the shared basis leg alone) and cpi_unavailable stays FALSE everywhere — the case measured before drafting this leg'
);
select set_config('role', 'postgres', true);
rollback to savepoint cpi_carry_basis;

-- =====================================================================
-- (8) CPIG — zero AND negative CPI guard, isolated to this_month''s own
--   print (coverage_through). ⚠ REVISED from an earlier draft that targeted
--   prior_month''s print (:basemonth): that period COLLIDES with the shared
--   basis (:yeperiod) in January (see the fixture note above), which would
--   have corrupted prior_year_end too and falsified CPIG1b''s "other two
--   rows unaffected" claim for that month. this_month''s CPI period is
--   coverage_through — structurally NEVER the basis period, on any run
--   day (z2''s own precondition) — so targeting it here is isolation-safe
--   year-round, not just in the eleven months the old target happened to
--   work.
-- =====================================================================
savepoint cpi_zero;
update pfin.cpi_u_index set cpi_value = 0 where cpi_period = date_trunc('month', :'today'::date::timestamp)::date;
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select cpi_unavailable and nav_prior_yr_dollars is null and nav is not null
     from pfin.fn_nav_reference_dates() where reference = 'this_month'),
  '(CPIG1) ⭐ ZERO CPI on the denominator: cpi_unavailable TRUE, nav_prior_yr_dollars NULL, nav STANDS — never `division by zero`'
);
select set_config('role', 'postgres', true);
-- prior_year_end is unaffected UNCONDITIONALLY: this_month's coverage_through
-- period can never equal the basis period (established at z2 — different
-- years, always). prior_month's isolation is conditional: on a month-end run
-- day (:base = :today, measured — see (CAUSE1)'s sibling note above),
-- prior_month's own CPI period equals date_trunc('month', :today) too, the
-- SAME period this savepoint just corrupted — guarded rather than silently
-- passed or falsely redding.
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select not cpi_unavailable from pfin.fn_nav_reference_dates() where reference = 'prior_year_end'),
  '(CPIG1b) …and prior_year_end is unaffected on every run day — its CPI period is the basis period, which coverage_through can never equal'
);
select set_config('role', 'postgres', true);
-- ⚠ STRENGTHENED (Architect's second finding, 2026-08-14): the same vacuous-
-- branch issue as (CAUSE1-prior_month) above — rewritten to assert the
-- month-end day's expected state instead of skipping it.
--   ⚠ ON THE RATIONALE ITSELF (Architect's first finding, re-verified rather
--   than accepted): re-measured directly on a fresh scratch DB, run day
--   2026-09-30, reproducing this file's OWN fixture sequence exactly —
--   `select cpi_period from pfin.cpi_u_index` showed only TWO rows,
--   2025-12-01 (basis) and 2026-09-01, because the fixture's own insert
--   order (this_month before basemonth, both `on conflict do nothing`)
--   makes basemonth's insert DEFER to the identical period this_month
--   already claimed. `select reference, cpi_period from
--   pfin.fn_nav_reference_dates()` confirmed this_month AND prior_month both
--   report cpi_period = 2026-09-01 — the SAME period, not merely close ones
--   — and corrupting it flips cpi_unavailable TRUE on BOTH rows. The
--   original rationale stands for THIS fixture; a differently-built fixture
--   (coverage_through genuinely lagging, as it would in an unmanipulated
--   table under normal CPI-publication arrears) could show the two periods
--   differing, but that is not the state this savepoint or the battery's own
--   insert sequence ever produces.
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select case when :'basemonth'::date <> date_trunc('month', :'today'::date::timestamp)::date
            then not cpi_unavailable
            else cpi_unavailable  -- :base = :today: prior_month's own CPI
                                  -- period IS this_month's (re-verified
                                  -- above, not assumed) — corrupting the
                                  -- shared period MUST flip this row too.
          end
     from pfin.fn_nav_reference_dates() where reference = 'prior_month'),
  '(CPIG1c) …and prior_month is unaffected on every ORDINARY run day; on the ~12 days a year its own CPI period coincides with this_month''s (:base = :today), it is asserted AFFECTED — the shared period was just corrupted, so cpi_unavailable must be true, not silently skipped'
);
select set_config('role', 'postgres', true);
rollback to savepoint cpi_zero;

savepoint cpi_negative;
update pfin.cpi_u_index set cpi_value = -50 where cpi_period = date_trunc('month', :'today'::date::timestamp)::date;
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select cpi_unavailable and nav_prior_yr_dollars is null and nav is not null
     from pfin.fn_nav_reference_dates() where reference = 'this_month'),
  '(CPIG2) ⭐ NEGATIVE CPI on the denominator: cpi_unavailable TRUE, nav_prior_yr_dollars NULL — never a silently sign-flipped net-worth figure'
);
select set_config('role', 'postgres', true);
rollback to savepoint cpi_negative;

-- ⚠ (CPIG3) THE BASIS-SIDE GUARD HAD NO WATCHER (Sec finding, 2026-08-14,
--   GREEN verdict flag 2): (CPIG1)/(CPIG2) above corrupt only this_month's
--   OWN denominator print; nothing in this file made the shared BASIS print
--   (:yeperiod) itself zero or negative. Deleting the strictly-positive
--   guard on v_cpi_ye specifically (`and v_cpi_ye > 0` in the body) would
--   leave all other legs green while re-admitting a sign-flipped
--   prior-year-dollar figure across the WHOLE table — the basis feeds every
--   row's deflation, so this is not a duplicate of (CPIG1)/(CPIG2), it is
--   the other half of the same guard, previously unexercised. Because the
--   basis is shared, the cascade is table-wide by construction (the SAME
--   mechanism (CAUSE2) already proves for a deleted basis print) — asserted
--   on the FULL row, all three references, in one leg.
savepoint cpi_basis_negative;
update pfin.cpi_u_index set cpi_value = -50 where cpi_period = :'yeperiod'::date;
select _rls.set_tenant(:'ta'::uuid);
select results_eq(
  $$ select reference, cpi_unavailable, nav_prior_yr_dollars is null, nav is not null
       from pfin.fn_nav_reference_dates() order by reference $$,
  $$ values ('prior_month'::text, true, true, true),
            ('prior_year_end'::text, true, true, true),
            ('this_month'::text, true, true, true) $$,
  '(CPIG3) ⭐ NEGATIVE CPI ON THE SHARED BASIS: cpi_unavailable TRUE on ALL THREE rows, nav_prior_yr_dollars NULL everywhere, nav STANDS everywhere — the basis-side positivity guard, exercised for the first time in this file, cascades exactly like a deleted basis print (CAUSE2) rather than degrading silently or sign-flipping a net-worth figure'
);
select set_config('role', 'postgres', true);
rollback to savepoint cpi_basis_negative;

-- =====================================================================
-- (9) T — TWO-TENANT, NON-VACUOUSLY.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select nav from pfin.fn_nav_reference_dates() where reference = 'this_month'), 700000::numeric,
  '(T1) A''s this_month nav (700000).'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select nav from pfin.fn_nav_reference_dates() where reference = 'this_month'), 7000000::numeric,
  '(T2) ⭐ THE NON-VACUITY THAT MAKES (T1) A TEST: the IDENTICAL call under B returns B''s OWN nav (7000000, B''s 10x fixture), never A''s'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (10) X — CROSS-TENANT / zero-checkpoint tenant.
-- =====================================================================
select _rls.set_tenant(:'tc'::uuid);
select is(
  (select count(*) from pfin.fn_nav_reference_dates()
    where reference_checkpoint_date is null and nav is null and nav_prior_yr_dollars is null)::int,
  3,
  '(X1) tenant C (zero checkpoints): all THREE rows are present with every value-bearing column NULL — fails closed, never an error, never another tenant''s figures leaking through'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (LEAK) ⭐ CORRUPT-THE-CONTROL — proving RLS, not application logic, is the
--   fence. Family convention (071/072), not individually itemized in this
--   migration's own header. NEGATIVE predicate from the start: `nav is not
--   null and nav <> 700000` (A''s own this_month value). Fails closed on an
--   empty result rather than passing vacuously (the exact vacuous-green path
--   a bare `isnt()` would open, per 072''s own corrected leg — not repeated
--   here). Robust to whichever other tenant''s row wins, so it needs no
--   engineered date offset between A and B to stay deterministic.
--   ⚠ SUBJECT IS THE FUNCTION, NOT THE TABLE (Sec finding, 2026-08-14, GREEN
--   verdict flag 1): an earlier draft probed pfin.nav_daily directly,
--   at-or-before :today — the SAME shape as 072's leg, but it meant this
--   canary could never catch the hazard 062's own header calls load-bearing:
--   a future redundant `users_id = auth.uid()` predicate added LOCALLY to
--   fn_nav_reference_dates() would keep this leg green (nav_daily's own
--   policy is still broken open, so the table-level probe still leaks) even
--   though the function itself had grown a second, masking fence. Probing
--   pfin.fn_nav_reference_dates() directly closes that gap — this leg now
--   exercises the SAME code path every other leg in this file does.
--   Determinism verified: under the sabotage below, every competing
--   checkpoint at-or-before :today (B 7000000, D 111000, E 45000) differs
--   from A''s 700000, so the negative predicate cannot pass vacuously
--   regardless of which one wins.
-- =====================================================================
savepoint leak_canary;
alter policy nav_daily_select on pfin.nav_daily using (true);
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select nav is not null and nav <> 700000
     from pfin.fn_nav_reference_dates() where reference = 'this_month'),
  '(LEAK1) ⭐ CORRUPT-THE-CONTROL: with nav_daily_select broken OPEN, A''s this_month nav (via fn_nav_reference_dates() itself, not a table probe) is NON-NULL and OTHER than A''s own (700000) — proving RLS, not application logic, is what confines tenant A to its own rows, exercised on the SAME code path the function''s real callers use. Fails CLOSED on an empty result; robust to whichever other tenant''s row wins: RED here is the proof the fence is real'
);
select set_config('role', 'postgres', true);
rollback to savepoint leak_canary;

-- =====================================================================
-- (11) M — AAL2 BACKSTOP, BOTH LEGS.
-- =====================================================================
select is(
  _rls.count_as(:'td'::uuid, 'aal1',
    $$ select count(*) from pfin.fn_nav_reference_dates() where nav is null $$
  ), 3::bigint,
  '(M1) an aal1 session for the totp-declared tenant D gets all THREE rows all-NULL, even though D genuinely has checkpoints — the aal2 backstop fails this read closed'
);
select is(
  _rls.count_as(:'td'::uuid, 'aal2',
    $$ select count(*) from pfin.fn_nav_reference_dates() where reference = 'this_month' and nav = 111000 $$
  ), 1::bigint,
  '(M2) ⭐ the POSITIVE leg that makes (M1) a test: the SAME tenant at aal2 sees their REAL this_month nav (111000). Without this, (M1) could pass vacuously against a policy that blinds every caller'
);

-- =====================================================================
-- (12) PST1 — CATALOG POSTURE.
-- =====================================================================
select is(
  (select array[p.prosecdef::text, p.provolatile::text, array_to_string(p.proconfig, ',')]
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_reference_dates'),
  array['false','s','search_path=""'],
  '(PST1) POSTURE, read DECLARATIVELY: SECURITY INVOKER, STABLE, search_path pinned empty. A DEFINER swap here would detach the read from nav_daily''s RLS context AND break 070''s shared-session guarantee, while every behavioral leg above stayed green'
);

-- =====================================================================
-- (13) A — ACL, including anon from the start (the 064 idiom, named in this
--   migration's own CONTRACT/comment text).
-- =====================================================================
select ok(
  has_function_privilege('authenticated', 'pfin.fn_nav_reference_dates()', 'execute'),
  '(A1) authenticated HOLDS EXECUTE'
);
select ok(
  not has_function_privilege('public', 'pfin.fn_nav_reference_dates()', 'execute'),
  '(A2) LOAD-BEARING: PUBLIC does NOT — the revoke is load-bearing and silent on removal'
);
select ok(
  not has_function_privilege('service_role', 'pfin.fn_nav_reference_dates()', 'execute'),
  '(A3) service_role does NOT hold EXECUTE — an INVOKER helper granted to service_role would be a de facto cross-tenant read, the same reasoning 067/069/071/072 already record'
);
select ok(
  not has_function_privilege('anon', 'pfin.fn_nav_reference_dates()', 'execute'),
  '(A4) anon does NOT hold EXECUTE — anon is the role reached WITHOUT a JWT at all; the 064 idiom, named explicitly in this migration''s own comment text'
);

select * from finish();
rollback;

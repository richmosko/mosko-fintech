-- =====================================================================
-- Per-Wave battery — pfin.fn_nav_series(p_granularity text, p_start_date date, p_end_date date)
--   — the §2.1.2 net-worth-TREND read surface (SELF-219 / 062; V1.1 "Net worth full";
--   PRD §2.1.2; Lock 11 SECURITY INVOKER read-composition over pfin.nav_daily (054)).
--   Paired with the migration in the SAME PR (verify-paired-artifacts discipline — a
--   migration merging without its battery makes CI green over an incomplete change).
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/062_fn_nav_series.sql
--   OPTION A (F/CTO-ratified 2026-08-07): all three granularities READ FROZEN CHECKPOINTS.
--   Coarser views are SAMPLED FROM the daily grain; nothing is recomputed.
--   Sub-decision (iii) (F/CTO-ratified): a missing checkpoint CARRIES FORWARD and the
--   third output column `checkpoint_date` returns the date the value was MEASURED.
--
-- ┌─ ⟦EXPECTED STACK⟧ ────────────────────────────────────────────────────────────────┐
-- │ **A RESULT HERE IS UNINTERPRETABLE WITHOUT THE MIGRATION SET IT RAN AGAINST.**      │
-- │ Report it alongside:  select max(version) from supabase_migrations.schema_migrations;│
-- │ EXPECTED STACK: `062`-applied (which requires `054` for pfin.nav_daily, `024` for   │
-- │ pfin.user_settings and `025` for the aal2 backstop). RED-until-062-applied is the   │
-- │ correct result on any pre-062 stack — the function does not exist there.            │
-- │ Authored + measured GREEN against the 001→061 landed local stack with `062` applied │
-- │ inside a ROLLED-BACK transaction (PG 17.6, session TimeZone UTC). NO `supabase db   │
-- │ reset` — F/CTO's local data untouched; pfin.nav_daily held 0 rows before and after. │
-- └────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ WHAT THIS BATTERY PROVES — one line per migration-header QA item ─────────────────┐
-- │ (I) item 1  TWO-TENANT, NON-VACUOUSLY — A and B carry checkpoints on the SAME dates │
-- │             with DIFFERENT values, so the identical call returns different answers.  │
-- │ (X) item 2  CROSS-TENANT FAILS CLOSED as ZERO ROWS, never an error.                 │
-- │ (M) item 3  AAL2 BACKSTOP, BOTH LEGS — aal1 totp reader 0 rows AND aal2 reader N>0. │
-- │ (P) item 4  PERIOD BUCKETING IS REAL — 3 checkpoints in one month, the month-end    │
-- │             answer distinguishable from first / max / min / avg.                     │
-- │ (G) item 5  GAPS CARRY FORWARD, NOT INTERPOLATED — and checkpoint_date exposes it.  │
-- │ (E) item 6  EMPTY SERIES = ZERO ROWS, not an error and not a 0-valued point.        │
-- │ (B) item 7  BOUNDS — no point before the first checkpoint or after the last,        │
-- │             including when p_end_date is in the future.                              │
-- │ (L) item 8  FAIL-LOUD — asserted on the RAISE and its message, not on emptiness;    │
-- │             plus a raise-SITE count so a new unasserted fence is visible (§8 rule 2).│
-- │ (N) item 9  NO-RECOMPUTE SOURCE FENCE — prosrc reaches no valuation function.       │
-- │ (Z) item 10 ZONE FENCE — prosrc carries no zone-aware type and no clock function.   │
-- │ (A) item 11 ADR-040 ASSEMBLED-STATEMENT — the REAL PostgREST-shaped named-argument   │
-- │             call, real `authenticated` role, real JWT claim, live DB, rolled back.   │
-- │ (V) ⭐ INVERSION — the block that makes every one of the above non-vacuous, by      │
-- │             SABOTAGING the fence and watching the assertions go red. See below.      │
-- └────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ ⭐ (V) — CORRUPT THE CONTROL. THE METHOD, AND WHAT THE MEASUREMENT SHOWED ────────┐
-- │ `062` deliberately carries NO local `users_id` predicate: RLS on pfin.nav_daily is  │
-- │ the SOLE tenant fence (the 049/050/051 precedent), on the argument that a redundant │
-- │ predicate would make this battery pass even with the fence gone. Per rls/DESIGN.md  │
-- │ §10 — *a test's claim that it detects something is itself an assertion, and it is   │
-- │ usually unrun* — that argument is TESTED here, not accepted.                        │
-- │                                                                                     │
-- │ ⚠ THE METHOD MATTERS, AND THE OBVIOUS FORM OF IT IS WRONG.                          │
-- │ "Remove the control and see if the test notices" falsifies a battery ONLY WHERE     │
-- │ REMOVAL FAILS OPEN. Postgres RLS fails CLOSED on absence: drop the policy and RLS   │
-- │ default-denies, so EVERY tenant — the owner included — sees zero rows. A            │
-- │ cross-tenant leg asserting "A sees none of B's rows" then passes ON THE NOTHING.    │
-- │   >> WHEN A CONTROL FAILS CLOSED, CORRUPT IT RATHER THAN DELETE IT. <<              │
-- │ So the fence is BROKEN OPEN (`using (true)`), not removed. The deleted-fence world  │
-- │ is kept as its own leg and LABELLED AS THE VACUITY IT IS, never as a proof.         │
-- │                                                                                     │
-- │ MEASURED — the two modes are caught by DIFFERENT halves of the battery:             │
-- │                                                                                     │
-- │   CORRUPTED  policy → `using (true)`. Fence broken open, reads still permitted.     │
-- │     062 as authored     → 3 rows {80,300,5000}, provenance 2026-02-10 (B leaks in)  │
-- │                           ⇒ (V1)+(V1b)+(V2) RED. The battery SEES a broken fence.✅ │
-- │     redundant variant   → 2 rows {80,300}, provenance 2026-01-20 — IDENTICAL TO     │
-- │                           BASELINE on BOTH value set and cardinality.               │
-- │                           ⇒ (V3)+(V3b) GREEN OVER A BROKEN FENCE.                   │
-- │                           **062's rationale is CONFIRMED. Do not add the predicate.**│
-- │                                                                                     │
-- │   ABSENT     policy dropped. RLS on, no policy ⇒ deny-all. 062 → 0 rows.            │
-- │     The cross-tenant NEGATIVE passes VACUOUSLY. Only the POSITIVE legs fire —       │
-- │     (I1), (I5), (M2), (X3). ⇒ (V4), kept as the counter-example to the method.      │
-- │                                                                                     │
-- │ TWO CONSEQUENCES, STATED SO THEY ARE NOT LOST:                                      │
-- │  1. The pairing is LOAD-BEARING, not stylistic. Deleting any positive leg as        │
-- │     "redundant" reopens the ABSENT mode as an undetectable failure.                 │
-- │  2. The fixture's DIFFERING VALUES are load-bearing too — and are still not enough. │
-- │     A broken fence can leak rows whose values match the owner's, so the corrupt-    │
-- │     the-control legs assert CARDINALITY as well as the value set ((V1b), (V3b)).    │
-- │     A value-only assertion can pass while leaking.                                  │
-- │                                                                                     │
-- │ CITATION ANCHOR: the (V…) tags are self-describing by design because 062's header   │
-- │ cites them as the instrument enforcing its design. Renaming one is a cross-artifact │
-- │ change. The (V) legs are the reason every OTHER assertion here is believable.        │
-- └────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ WHAT THIS BATTERY STRUCTURALLY CANNOT PROVE (rls/DESIGN.md §8 rules 0 + 1) ───────┐
-- │ The disclosure, derived from what the fixture SUPPLIES:                             │
-- │  · REACHABILITY. This file INSERTS its own pfin.nav_daily rows, so it has by        │
-- │    construction substituted for the W-1 cron writer and can never detect that       │
-- │    nothing writes checkpoints in production. It would stay green forever against an │
-- │    empty table. Reachability is assertable only in the WRITER's battery (SELF-214 / │
-- │    054), never here. As of `062` the series is FORWARD-ONLY and no production        │
-- │    checkpoint exists — so "this function returns a chart" is UNPROVEN end-to-end.    │
-- │  · THE ZONE INVARIANT ACROSS PROCESSES. (Z) proves the function BODY is zone-free.  │
-- │    It cannot observe what zone `nav_daily.nav_date` was DERIVED in by the worker,    │
-- │    nor what date the app hands to p_start_date/p_end_date — that invariant spans     │
-- │    two processes and every test we have replaces one of them with a fixture          │
-- │    (rls/DESIGN.md §12). The still-OPEN nav_date zone one-way door is untested here   │
-- │    BY CONSTRUCTION, and `062` not touching it is exactly why that is acceptable.     │
-- │  · LATENCY / the p95 ≤ 50ms reframe. Deliberately NOT asserted: a timing assertion   │
-- │    in a pgTAP suite is a flake generator, and (N) is the STRICTLY STRONGER fence     │
-- │    for the property that number was a proxy for — so a FAST WRONG implementation     │
-- │    still fails here. Latency belongs at the Phase 7 measurement on the real deploy   │
-- │    target, per the migration header. Recorded so its absence is not read as an       │
-- │    oversight.                                                                        │
-- │  · CONSUMER BEHAVIOUR. (G) proves checkpoint_date <> point_date is RETURNED across  │
-- │    a gap. Whether SELF-220's chart SURFACES that staleness is a frontend assertion,  │
-- │    not a DB one. The detectability MECHANISM is proven; its USE is not.              │
-- └────────────────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3 / DEFINER ALLOWLIST — this battery introduces NO catalogued instance
--   and changes none. `062` authors ONE function and it is SECURITY INVOKER, reached by
--   `authenticated` over PostgREST: it holds no credential, runs no container, and has no
--   worker in its path. No count is restated here — read ADR-011 Decision 3 (cross-tenant
--   FK-bypass family) and Decision 4 (§10 catalogued-instance ledger) LIVE at the canonical
--   anchor; both grow, and a tally copied into a derived surface goes stale silently.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants via _rls.tenant_a()/_b()/_c()
--   plus one locally-declared fixed tenant D. NO PII / NO real account numbers (SD-15) / NO
--   real Plaid tokens (SD-03) / NO production data. Every nav_value is an invented round
--   number. All seeds run PRIVILEGED (role=postgres; RLS+ACL bypassed) with users_id set
--   EXPLICITLY — auth.uid() is NULL under postgres — and 054's BEFORE INSERT write-tenant
--   binding fence requires `app.nav_computed_for` to be bound to each row's OWN users_id
--   before its INSERT, so the seed is grouped per tenant for that reason and not for tidiness.
--   The function is invoked ONLY under the authenticated tenant contexts under test.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated.
--   Tenant UUIDs resolve to psql LITERALS via \gset at role=postgres; every _rls.set_tenant*
--   is called at role=postgres and each block restores role=postgres before the next.
-- =====================================================================

begin;

-- shared cross-tenant verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

-- plan = 57 : 46 property assertions (I6 X3 M3 P6 G4 E3 B5 L6 N3 Z3 A4) + the 11-leg (V)
-- inversion block (V1 V1b V2 V3 V3b V4 V5 V6 V7 V8 V9). Recorded as an arithmetic
-- decomposition so a silent plan-edit is visible in review as a changed sum.
-- ⚠ DO NOT "fix" this by lowering it to a reported figure: (V1)–(V7) run inside savepoints,
-- and a rolled-back savepoint REWINDS pgTAP's plan counter while the emitted numbering
-- marches on (rls/DESIGN.md §9 harness note). 57 reconciles here only because (V8)/(V9) sit
-- OUTSIDE any savepoint and re-set the counter to their own numbers — that is the structural
-- guard, not a coincidence, and moving (V9) off the end would silently re-break it.
select plan(57);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset
\set td '00000000-0000-0000-0000-00000000000d'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc'), (:'td');

-- =====================================================================
-- FIXTURE — four tenants. The VARIATION is the test; a same-value or single-tenant
--   fixture passes under a broken predicate (rls/DESIGN.md: invariance is blindness).
--
--   A  (tenant_a) mfa 'none'.  01-05=100 · 01-12=50 · 01-20=80 · 02-28=300 · 03-15=400
--        THREE checkpoints inside January with NON-MONOTONIC values, chosen so the
--        month-end answer (80, from 01-20) is distinguishable from EVERY plausible wrong
--        bucketing: first-of-month=100, max=100, min=50, mean=76.67. A monotonic fixture
--        cannot separate "at-or-before month-end" from "max" — measured, and it is why
--        50 sits between 100 and 80 rather than the other way round.
--        A deliberate 38-day HOLE spans 01-21..02-27 (the cron-outage leg).
--        A's newest checkpoint is 03-15 — the UPPER bound anchor.
--   B  (tenant_b) mfa 'none'.  01-05=1000 · 01-20=2000 · 02-10=2500 · 02-28=3000
--                              · 03-15=4000 · 03-31=5000
--        SAME dates as A carrying DIFFERENT values (the non-vacuity requirement), PLUS
--        two dates A DOES NOT HAVE. Those two are the LEAK CANARIES and they are what
--        make the (V) sabotage DETERMINISTIC rather than a coin-flip:
--          · 02-10 falls INSIDE A's hole and is strictly LATER than A's 01-20, so a
--            leaked lateral picks it unambiguously — on a SHARED date the `order by
--            nav_date desc limit 1` tie could resolve either way and the sabotage could
--            pass by luck.
--          · 03-31 is strictly LATER than A's newest, so a leaked upper bound emits a
--            March point that must not exist. Row COUNT alone then goes red.
--   C  (tenant_c) NO user_settings row, NO checkpoints — the empty-series leg.
--   D  (tenant_d) mfa 'totp'.  01-05=777 · 02-28=888 — the aal2 backstop needs a tenant
--        with a declared step-up policy AND REAL ROWS, or its negative leg is vacuous.
-- =====================================================================
insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta', 'none'), (:'tb', 'none'), (:'td', 'totp');
-- (tenant_c deliberately gets NO user_settings row.)

-- ⚠ `app.nav_computed_for` must be bound to each row's OWN users_id before its INSERT
--    (054's B7 write-tenant binding fence). Not stylistic grouping — required.
select set_config('app.nav_computed_for', :'ta', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values
  (:'ta','2026-01-05',100), (:'ta','2026-01-12',50), (:'ta','2026-01-20',80),
  (:'ta','2026-02-28',300), (:'ta','2026-03-15',400);
select set_config('app.nav_computed_for', :'tb', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values
  (:'tb','2026-01-05',1000), (:'tb','2026-01-20',2000), (:'tb','2026-02-10',2500),
  (:'tb','2026-02-28',3000), (:'tb','2026-03-15',4000), (:'tb','2026-03-31',5000);
select set_config('app.nav_computed_for', :'td', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values
  (:'td','2026-01-05',777), (:'td','2026-02-28',888);

-- =====================================================================
-- (I) item 1 — TWO-TENANT ISOLATION, NON-VACUOUSLY.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

select is(
  (select array_agg(nav_value order by point_date) from pfin.fn_nav_series('monthly','2026-01-01','2026-03-31')),
  array[80, 300]::numeric[],
  '(I1) A''s monthly series over 2026-01-01..03-31 is EXACTLY {80,300}. POSITIVE leg — this is the assertion that fires when the RLS policy is DROPPED outright (deny-all), which the cross-tenant NEGATIVE cannot see. RED if A stops seeing its own checkpoints');
select is(
  (select array_agg(checkpoint_date order by point_date) from pfin.fn_nav_series('monthly','2026-01-01','2026-03-31')),
  array['2026-01-20','2026-02-28']::date[],
  '(I2) …and their provenance is A''s OWN checkpoint dates {01-20, 02-28}');
select is(
  (select array_agg(checkpoint_date order by point_date) from pfin.fn_nav_series('daily','2026-02-14','2026-02-16')),
  array['2026-01-20','2026-01-20','2026-01-20']::date[],
  '(I3) LEAK CANARY: across A''s hole, every daily point is provenanced to A''s 2026-01-20. B holds 2026-02-10 — strictly LATER and inside that hole — so a leaked lateral would return 2026-02-10 here DETERMINISTICALLY (measured under the (V) sabotage). RED on any cross-tenant read composition');
select ok(
  not exists (select 1 from pfin.fn_nav_series('daily','2026-01-01','2026-03-31') where nav_value in (1000,2000,2500,3000,4000,5000)),
  '(I4) VALUE-LEVEL isolation: no point in A''s full daily series carries ANY of B''s six nav_values. Asserted on the VALUES, not the row count — a leak that happened to preserve cardinality would still fire here');

select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);

select is(
  (select array_agg(nav_value order by point_date) from pfin.fn_nav_series('monthly','2026-01-01','2026-03-31')),
  array[2000, 3000, 5000]::numeric[],
  '(I5) ⭐ THE NON-VACUITY THAT MAKES (I1) A TEST: the IDENTICAL call under B returns {2000,3000,5000}, not {80,300}. A and B hold checkpoints on the SAME dates with DIFFERENT values, so a broken tenant predicate cannot produce both answers. A same-value fixture would pass here with no isolation at all');
select is(
  (select nav_value from pfin.fn_nav_series('monthly','2026-01-01','2026-03-31') where point_date = '2026-01-31'),
  2000::numeric,
  '(I6) same-date discrimination, stated concretely: at the SAME point_date 2026-01-31, sourced from the SAME checkpoint_date 2026-01-20, A reads 80 (I1) and B reads 2000');

select set_config('role', 'postgres', true);

-- =====================================================================
-- (X) item 2 — CROSS-TENANT FAILS CLOSED AS ZERO ROWS, NOT AN ERROR.
--   Probed on the window 03-16..03-31, which is entirely PAST A's newest checkpoint
--   (03-15) and in which B holds 03-31=5000. So A must see nothing there while the
--   data demonstrably exists — a BOUNDARY denial, not an empty database.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  $$ select * from pfin.fn_nav_series('daily','2026-03-16','2026-03-31') $$,
  '(X1) fails CLOSED, not LOUD: a window containing only another tenant''s checkpoint returns normally — no exception. RED if the function ever raised on a cross-tenant miss (an error is a disclosure: it distinguishes "exists but not yours" from "does not exist")');
select is(
  (select count(*)::int from pfin.fn_nav_series('daily','2026-03-16','2026-03-31')),
  0,
  '(X2) …and returns ZERO ROWS over that window — B''s 2026-03-31 checkpoint is invisible to A');
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*)::int from pfin.fn_nav_series('daily','2026-03-16','2026-03-31')),
  16,
  '(X3) NON-VACUOUS COMPANION to (X2): B sees 16 daily points over the identical window (03-16..03-31, bounded by B''s own 03-31 checkpoint). So (X2)''s zero is a cross-tenant BOUNDARY denial and not an empty window — without this leg, (X2) would pass against a function that returns nothing to anyone');
select set_config('role', 'postgres', true);

-- =====================================================================
-- (M) item 3 — AAL2 STEP-UP BACKSTOP, BOTH LEGS.
--   INHERITED through nav_daily_select (054 / 025 / C3); 062 creates no policy of its
--   own, so this is a PROPERTY TO BE ASSERTED, never a claim the function may make.
-- =====================================================================
select is(
  _rls.count_as(:'td'::uuid, 'aal1', $$ select count(*) from pfin.fn_nav_series('daily','2026-01-01','2026-02-28') $$),
  0::bigint,
  '(M1) aal2 backstop NEGATIVE leg: tenant D declared mfa_policy ''totp'' and presents an aal1 session → 0 rows THROUGH THIS FUNCTION. The INVOKER posture is what carries the backstop here; RED if 062 were re-implemented as SECURITY DEFINER or given any privileged path');
select is(
  _rls.count_as(:'td'::uuid, 'aal2', $$ select count(*) from pfin.fn_nav_series('daily','2026-01-01','2026-02-28') $$),
  55::bigint,
  '(M2) ⭐ aal2 backstop POSITIVE leg — THE ESSENTIAL ONE: the SAME tenant at aal2 sees 55 daily points (01-05..02-28, bounded by D''s own newest checkpoint). Without this, (M1) passes on an empty fixture and proves nothing. 55 is asserted exactly rather than as N>0, so a partial regression is visible too');
select is(
  _rls.count_as(:'ta'::uuid, 'aal1', $$ select count(*) from pfin.fn_nav_series('monthly','2026-01-01','2026-03-31') $$),
  2::bigint,
  '(M3) the backstop gates on the READER''s OWN declared policy, never a blanket aal2: tenant A declared ''none'' and at aal1 still sees its 2 monthly points. RED if the conjunct were widened to require aal2 of everyone — which (M1)+(M2) alone cannot distinguish from correct behaviour');

-- =====================================================================
-- (P) item 4 — PERIOD BUCKETING IS REAL.
--   Three January checkpoints, non-monotonic: 01-05=100, 01-12=50, 01-20=80.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select nav_value from pfin.fn_nav_series('monthly','2026-01-01','2026-03-31') where point_date = '2026-01-31'),
  80::numeric,
  '(P1) monthly bucketing = the checkpoint AT-OR-BEFORE month-end. January holds THREE checkpoints with non-monotonic values, so 80 is distinguishable from first-of-month (100), max (100), min (50) and mean (76.67) SIMULTANEOUSLY. A fixture with one checkpoint per month, or with monotonic values, cannot separate these');
select is(
  (select checkpoint_date from pfin.fn_nav_series('monthly','2026-01-01','2026-03-31') where point_date = '2026-01-31'),
  '2026-01-20'::date,
  '(P2) …and the provenance column names 2026-01-20 — the LAST January checkpoint, not the first');
select is(
  (select array_agg(nav_value order by point_date) from pfin.fn_nav_series('weekly','2026-01-01','2026-02-28')),
  array[100, 50, 80, 80, 80, 80, 80]::numeric[],
  '(P3) weekly bucketing samples the SAME daily grain at ISO week-ends (Sundays): the three January checkpoints resolve to distinct week-end values 100 (w/e 01-11) / 50 (w/e 01-18) / 80 (w/e 01-25), then carry. RED if date_trunc(''week'') were re-pointed to the week START (Monday) — the values would shift by one bucket');
select is(
  (select array_agg(point_date order by point_date) from pfin.fn_nav_series('weekly','2026-01-01','2026-02-28')),
  array['2026-01-11','2026-01-18','2026-01-25','2026-02-01','2026-02-08','2026-02-15','2026-02-22']::date[],
  '(P4) …and every weekly point_date is a SUNDAY (the ISO week-END). The +6-day offset off date_trunc(''week'')''s Monday is asserted on the dates themselves, so a Monday/Sunday re-point fires here even if the values coincided');
select is(
  (select array_agg(point_date order by point_date) from pfin.fn_nav_series('monthly','2026-01-15','2026-02-28')),
  array['2026-01-31','2026-02-28']::date[],
  '(P5) month-END arithmetic is correct for a SHORT month: February 2026 ends on the 28th, and the point is emitted at 02-28 — the (first-of-month + 1 month − 1 day) form, not a fixed 30/31. RED on any hardcoded day-of-month');
select ok(
  not exists (select 1 from pfin.fn_nav_series('monthly','2026-01-01','2026-02-15') where point_date = '2026-02-28'),
  '(P6) a period whose END falls outside [p_start,p_end] is EXCLUDED: with p_end=2026-02-15 no 2026-02-28 point is emitted — a PARTIAL trailing month is not reported as if it were a whole one');

-- =====================================================================
-- (G) item 5 — GAPS CARRY FORWARD AND ARE NOT INTERPOLATED.
--   A's 38-day hole: 01-21 .. 02-27.  Sub-decision (iii) is what is under test.
-- =====================================================================
select is(
  (select array_agg(nav_value order by point_date) from pfin.fn_nav_series('daily','2026-02-25','2026-03-02')),
  array[80, 80, 80, 300, 300, 300]::numeric[],
  '(G1) carry-forward, NOT interpolation: across the hole the value is FLAT at the last real checkpoint (80) then steps to 300 on the measured day. THE NEGATIVE THAT FIRES: any interpolating "improvement" would emit values strictly BETWEEN 80 and 300 on 02-25..02-27, which this exact-array assertion cannot accept');
select is(
  (select array_agg(checkpoint_date order by point_date) from pfin.fn_nav_series('daily','2026-02-25','2026-03-02')),
  array['2026-01-20','2026-01-20','2026-01-20','2026-02-28','2026-02-28','2026-02-28']::date[],
  '(G2) sub-decision (iii) DETECTABILITY: checkpoint_date returns the date the value was MEASURED, so a consumer can tell "measured today" from "last measured 39 days ago". This column is the entire difference between (iii) and (ii) — RED if it were dropped or aliased to point_date');
select is(
  (select count(*)::int from pfin.fn_nav_series('daily','2026-02-25','2026-03-02') where checkpoint_date < point_date),
  5,
  '(G3) exactly 5 of the 6 points are STALE (checkpoint_date < point_date) — {02-25,02-26,02-27} carried across the hole plus {03-01,03-02} carried past the last checkpoint. ⚑ AUTHORED AS 4 AND CORRECTED BY THE RUN: the first draft counted only the pre-checkpoint side of the window and forgot that carry-forward continues AFTER 02-28 as well. Recorded rather than silently fixed, because it is the concrete case for rls/DESIGN.md §8 rule 2 — a number reasoned into an assertion is unrun until the assertion runs');
select is(
  (select count(*)::int from pfin.fn_nav_series('daily','2026-02-25','2026-03-02') where checkpoint_date = point_date),
  1,
  '(G4) …and exactly ONE point is FRESH (checkpoint_date = point_date): 2026-02-28, the only day in the window that has a real checkpoint. The pair (G3)+(G4) is what proves checkpoint_date is a FUNCTION OF THE DATA and not a constant — a column hardwired to point_date would pass (G4) and fail (G3); one hardwired to the first checkpoint would do the inverse');

-- =====================================================================
-- (E) item 6 — EMPTY SERIES = ZERO ROWS, not an error and not a zero VALUE.
--   "Absence is not a value" (ADR-042): "$0 net worth" and "no data yet" must not render
--   identically. Tenant C holds no checkpoints and no user_settings row.
-- =====================================================================
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tc'::uuid);
select lives_ok(
  $$ select * from pfin.fn_nav_series('monthly','2026-01-01','2026-03-31') $$,
  '(E1) a tenant with zero checkpoints does NOT raise — an empty series is a legitimate state, not a caller error');
select is(
  (select count(*)::int from pfin.fn_nav_series('monthly','2026-01-01','2026-03-31')),
  0,
  '(E2) …and returns ZERO ROWS. THE NEGATIVE THAT FIRES: a single row carrying nav_value 0. RED if the upper-bound NULL comparison were ever "fixed" with a coalesce, or a leading zero fabricated');
select ok(
  not exists (select 1 from pfin.fn_nav_series('daily','2026-01-01','2026-03-31') where nav_value = 0),
  '(E3) stated as its own assertion because it is the one that matters at the UI: NO point anywhere in an empty tenant''s daily series carries the VALUE 0. (E2) counts rows; this one names the specific wrong answer — a $0 chart where the honest answer is "no data yet"');
select set_config('role', 'postgres', true);

-- =====================================================================
-- (B) item 7 — SERIES BOUNDS. Never extends past evidence, in EITHER direction.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select array_agg(point_date order by point_date) from pfin.fn_nav_series('daily','2025-12-28','2026-01-06')),
  array['2026-01-05','2026-01-06']::date[],
  '(B1) LOWER BOUND: a window opening 8 days BEFORE A''s first checkpoint emits nothing until 2026-01-05. The chart begins where the data begins. THE NEGATIVE THAT FIRES: a fabricated leading zero — the exact defect Option A exists to avoid, arriving from the other side (a LEFT JOIN in place of the inner CROSS JOIN LATERAL would emit 2025-12-28..2026-01-04 with NULL/0)');
select ok(
  not exists (select 1 from pfin.fn_nav_series('weekly','2026-01-01','2026-02-28') where point_date = '2026-01-04'),
  '(B2) the lower bound holds on the WEEKLY path too: 2026-01-04 is a Sunday inside the window, but it precedes A''s first checkpoint (01-05) so no point is emitted. Asserted separately because bucketing and bounding are different code paths and one can be fixed without the other');
select is(
  (select array_agg(nav_value order by point_date) from pfin.fn_nav_series('monthly','2026-01-01','2027-12-31')),
  array[80, 300]::numeric[],
  '(B3) UPPER BOUND with a FUTURE p_end_date: extending the request 21 months past A''s newest checkpoint returns the SAME two points. THE NEGATIVE THAT FIRES: a flat carried-forward line into the future reading as "net worth stopped moving" when the truth is "we have not measured since" — 22 extra monthly points, all 400');
select is(
  (select max(point_date) from pfin.fn_nav_series('daily','2026-01-01','2027-12-31')),
  '2026-03-15'::date,
  '(B4) …and the last point is exactly A''s newest checkpoint date (2026-03-15), asserted on the DATE rather than the count so the bound is pinned to the evidence and not to an arithmetic coincidence');
select is(
  (select count(*)::int from pfin.fn_nav_series('daily','2026-01-01','2027-12-31')),
  70,
  '(B5) the whole daily series is 70 points = 2026-01-05..2026-03-15 inclusive. Printed adjacent to (B4) as an INDEPENDENT second figure: (B4) reads the maximum, (B5) counts the set, and they come from different properties of the result — so they can disagree, which is what makes the pair a check (rls/DESIGN.md §8 rule 4)');
select set_config('role', 'postgres', true);

-- =====================================================================
-- (L) item 8 — FAIL LOUD. Asserted on the RAISE and its MESSAGE, never on emptiness.
--   Mechanism-agnostic ("any exception") is deliberately NOT used: it cannot tell this
--   fence from a fence that refuses everything (rls/DESIGN.md §9).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select throws_ok(
  $$ select * from pfin.fn_nav_series('yearly','2026-01-01','2026-03-31') $$,
  'P0001', null,
  '(L1) an UNKNOWN granularity RAISES rather than returning empty. This is the load-bearing fail-loud case: an empty set is indistinguishable from "this tenant has no checkpoints", so a caller typo would render as a legitimately-blank chart on a financial surface');
select throws_like(
  $$ select * from pfin.fn_nav_series('yearly','2026-01-01','2026-03-31') $$,
  '%unknown p_granularity%',
  '(L2) …and the message identifies WHICH fence fired. Bound to this fence''s own wording, not to a bare SQLSTATE — a bare P0001 match cannot distinguish the granularity fence from the date fences, and would stay green if the three raises were reordered or merged');
select throws_like(
  $$ select * from pfin.fn_nav_series(null,'2026-01-01','2026-03-31') $$,
  '%unknown p_granularity%',
  '(L3) a NULL granularity takes the SAME fence (the `is null or not in (...)` disjunct), rather than falling through the CASE to a silent all-NULL period set');
select throws_like(
  $$ select * from pfin.fn_nav_series('monthly',null,'2026-03-31') $$,
  '%both required%',
  '(L4) a NULL date bound raises the DATE fence — a distinct message from (L2), so the two fences are textually disjoint and neither can mask the other');
select throws_like(
  $$ select * from pfin.fn_nav_series('monthly','2026-03-31','2026-01-01') $$,
  '%is after%',
  '(L5) an INVERTED range raises rather than returning empty: reversed bounds are a caller error, and generate_series would otherwise yield zero rows and report it as "no data"');
select set_config('role', 'postgres', true);
select is(
  (select (length(p.prosrc) - length(replace(p.prosrc, 'raise exception', '')))
          / length('raise exception')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_series'),
  3,
  '(L6) ⭐ COUNT THE RAISE SITES IN THE SUBJECT, not the assertions against plan() (rls/DESIGN.md §8 rule 2). The function body contains EXACTLY 3 `raise exception` sites and (L1..L5) assert all three. This is the only assertion here that can detect a NEW fence landing UNTESTED — a plan count proves the file is internally consistent and says nothing about coverage of the thing under test');

-- =====================================================================
-- (N) item 9 — NO-RECOMPUTE SOURCE FENCE. The property that keeps Option A from
--   silently becoming Option B. Source-level, not EXPLAIN-level: the EXPLAIN fence was
--   WITHDRAWN ON MEASUREMENT — a plpgsql body is opaque to the planner, so it could
--   never have failed. A source assertion is also strictly stronger than a latency
--   proxy, because a FAST WRONG implementation still fails it.
-- =====================================================================
select ok(
  (select p.prosrc !~ 'compute_nav'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_series'),
  '(N1) the stored source reaches NO valuation function. Scoped to `prosrc` — the text BETWEEN the $$ delimiters — which is the mechanically checkable boundary; the migration header and the `comment on` both name that function freely and neither is part of prosrc. A bare grep over the .sql file hits the prose EXPLAINING the fence and is the wrong instrument (rls/DESIGN.md anchoring rule; the migration records this trap being hit three times in one file)');
select ok(
  (select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') !~ 'compute_nav'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_series'),
  '(N2) …and it still holds with SQL COMMENTS STRIPPED, i.e. against EXECUTABLE TEXT only. (N1) is the primary fence and is deliberately the stricter of the two (it forbids the token in body comments as well, which is what the migration header instructs a future editor to preserve). (N2) is here so that RELAXING (N1) — the natural response to a legitimate body comment — cannot silently remove the fence on a real CALL. Corroborating, not load-bearing');
select ok(
  (select count(*) = 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_series'),
  '(N3) …and the fence has exactly ONE subject: `pfin.fn_nav_series` is not overloaded. An absence assertion is vacuous whenever its subject does not exist (rls/DESIGN.md §10), and it is UNDER-SCOPED if a second overload exists that (N1) never inspected');

-- =====================================================================
-- (Z) item 10 — ZONE FENCE (source-level, same shape as (N)). This is what keeps the
--   surface OFF the still-open nav_date zone one-way door.
-- =====================================================================
select ok(
  (select p.prosrc !~* 'timestamptz'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_series'),
  '(Z1) the stored source carries no `timestamptz`. Every date expression operates on date / timestamp WITHOUT time zone, so nothing in the function is evaluated in the session TimeZone');
select ok(
  (select p.prosrc !~* 'with time zone|time zone'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_series'),
  '(Z2) ⭐ …and no `time zone` in the SPELLED-OUT form either. Asserted separately and deliberately: `timestamptz` and `timestamp with time zone` are the SAME TYPE under two names, so a (Z1)-only fence — which is what the migration header specifies — is defeated by an editor who writes the canonical spelling. The alias is not a synonym a regex knows about');
select ok(
  (select p.prosrc !~* '\mcurrent_date\M|\mnow\s*\(|\mlocaltimestamp\M|\mcurrent_timestamp\M|\mstatement_timestamp\s*\(|\mclock_timestamp\s*\('
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_series'),
  '(Z3) ⭐ …and no CLOCK FUNCTION of any kind. The migration header instructs a future editor never to introduce current_date / now() / localtimestamp "or any timestamptz cast" — but item 10 as specified fences only the TYPE. A clock call needs no timestamptz token to make this surface a party to the zone decision: `current_date` alone is evaluated in the session TimeZone. This assertion is what makes that instruction MECHANICAL rather than an exhortation, which is the migration''s own stated rule for fences');

-- =====================================================================
-- (A) item 11 — ADR-040 ASSEMBLED-STATEMENT DISCIPLINE. The EXACT production statement
--   text, under the real `authenticated` role with a real JWT claim, against a live
--   database, in a rolled-back transaction. Not an approximation: this is the discipline
--   that caught 054's B9 ON CONFLICT defect after four reviewers passed the file.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select array_agg(nav_value order by point_date) from pfin.fn_nav_series(
     p_granularity := 'monthly', p_start_date := '2026-01-01', p_end_date := '2026-03-31')),
  array[80, 300]::numeric[],
  '(A1) ⭐ THE REAL POSTGREST CALL SHAPE: PostgREST invokes an RPC with NAMED arguments, never positionally. Asserted as its own leg because it pins the PARAMETER NAMES — a rename of p_granularity / p_start_date / p_end_date is invisible to every positional assertion in this file and would 404 every production call. §4.3 of the design brief records that this signature IS a public API surface');
select set_config('role', 'postgres', true);
select is(
  (select array[p.prosecdef::text, p.provolatile::text, array_to_string(p.proconfig, ',')]
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_series'),
  array['false','s','search_path=""'],
  '(A2) POSTURE, read DECLARATIVELY from the catalog rather than inferred from behaviour: SECURITY INVOKER (prosecdef false), STABLE (provolatile s), and search_path pinned empty. Behaviour cannot distinguish INVOKER from a DEFINER owned by a non-privileged role — only the catalog can, and DEFINER here would detach the read from both the caller''s RLS context and the 025 aal2 backstop');
select ok(
  has_function_privilege('authenticated', 'pfin.fn_nav_series(text,date,date)', 'execute'),
  '(A3) `authenticated` holds EXECUTE — the positive half of the grant pair. Without it (A4)''s denial could be a missing grant to everyone rather than a targeted one');
select ok(
  not has_function_privilege('public', 'pfin.fn_nav_series(text,date,date)', 'execute'),
  '(A4) …and PUBLIC does NOT. `create function` grants EXECUTE to PUBLIC by default, so the revoke is load-bearing and its removal is silent: every assertion in this file would stay green while the function became callable by `anon`');

-- =====================================================================
-- (V) ⭐ INVERSION BLOCK — the battery testing the battery.
--   Every assertion above is a claim; this block is where those claims are RUN against
--   a deliberately broken fence. "To believe an assertion detects X, build X and watch
--   it go red" (rls/DESIGN.md §10). Each leg runs inside a SAVEPOINT and is rolled back.
--   ⚠ A rolled-back savepoint REWINDS pgTAP's plan counter while the emitted numbering
--   marches on — so (V9) below is deliberately OUTSIDE any savepoint and runs LAST.
-- =====================================================================

-- ---- V/S2 — CORRUPT-THE-CONTROL. The fence BROKEN OPEN, not absent. The sharp mode. ----
--   ⚠ THE METHOD, AND WHY THE OBVIOUS FORM IS WRONG. "Remove the control and see if the
--   test notices" is a valid falsification ONLY WHERE REMOVAL FAILS OPEN. Postgres RLS
--   fails CLOSED on absence: with the policy DROPPED, RLS is still enabled and default-
--   denies, so every tenant — including the owner — sees zero rows. A cross-tenant leg
--   asserting "A sees none of B's rows" then passes on the NOTHING, which is the opposite
--   of the property it exists to prove. An ABSENT fence cannot demonstrate a LEAK.
--   >> WHEN A CONTROL FAILS CLOSED, CORRUPT IT RATHER THAN DELETE IT. <<
--   That absent-fence world is still worth pinning, so it is kept as its own leg below
--   (V4-FENCE-ABSENT-IS-VACUOUS) — labelled as the vacuity it is, not as a proof.
--
--   FORM: `alter policy … using (true)` is used instead of drop-then-recreate. Measured
--   equivalent — both yield exactly `cmd=SELECT roles={authenticated} qual=true` — and
--   it is the more surgical of the two, since it cannot leave a differently-shaped policy
--   behind if the savepoint were ever mishandled. Recorded so this does not read as a
--   deviation from the drop+create form the instruction was relayed in.
--
--   ⚠ CITATION ANCHOR. The (V…) tags below are self-describing BY DESIGN and are cited
--   from 062's migration header as the instrument enforcing its no-local-users_id-
--   predicate design. RENAMING ONE IS A CROSS-ARTIFACT CHANGE, not a cosmetic edit.
savepoint v_s2;
alter policy nav_daily_select on pfin.nav_daily using (true);
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select array_agg(nav_value order by point_date) from pfin.fn_nav_series('monthly','2026-01-01','2026-03-31')),
  array[80, 300, 5000]::numeric[],
  '(V1-FENCE-CORRUPTED-IS-DETECTED) ⭐ CORRUPT-THE-CONTROL: with nav_daily_select broken OPEN to `using (true)`, A''s monthly series GAINS a third point valued 5000 — B''s 2026-03-31 checkpoint. This is (I1) going RED, measured rather than asserted. THE PROPERTY THIS ENFORCES: because 062 carries no local users_id predicate, RLS is the sole tenant fence AND this battery can SEE that fence break. RED here is the proof; green here would mean the battery is blind to a broken fence');
select is(
  (select count(*)::int from pfin.fn_nav_series('monthly','2026-01-01','2026-03-31')),
  3,
  '(V1b-FENCE-CORRUPTED-ROW-COUNT) …asserted on CARDINALITY as well as on the value set, and not as a belt-and-braces duplicate. A broken tenant fence leaks rows whose VALUES may be indistinguishable from the owner''s — under a same-value fixture the leak is invisible to any value-only assertion and shows up ONLY as extra rows. This fixture varies the values so (V1) also fires, but the count leg is what survives a fixture someone later "simplifies" into uniformity');
select is(
  (select array_agg(checkpoint_date order by point_date) from pfin.fn_nav_series('daily','2026-02-14','2026-02-16')),
  array['2026-02-10','2026-02-10','2026-02-10']::date[],
  '(V2-FENCE-CORRUPTED-PROVENANCE-LEAKS) …and (I3)''s leak canary fires: the daily provenance moves from A''s 2026-01-20 to B''s 2026-02-10. DETERMINISTIC because B''s 02-10 sits inside A''s hole and is strictly later — on a shared date the `order by nav_date desc limit 1` tie could have resolved either way and this sabotage could have passed by luck');
select set_config('role', 'postgres', true);

-- The COUNTERFACTUAL, built to answer the question the migration header ASSERTS an answer
-- to. Identical to 062 except for the two redundant local `users_id = auth.uid()`
-- predicates it argues against. Under the SAME sabotage, does the battery still see it?
create or replace function pfin.fn_nav_series_qa_counterfactual(
  p_granularity text, p_start_date date, p_end_date date
) returns table (point_date date, nav_value numeric, checkpoint_date date)
language plpgsql stable security invoker set search_path = '' as $cf$
#variable_conflict use_column
begin
  return query
  with days as (
    select gs::date as d from generate_series(p_start_date::timestamp, p_end_date::timestamp, '1 day'::interval) as gs
  ),
  periods as (
    select distinct case p_granularity
        when 'daily'   then days.d
        when 'weekly'  then (date_trunc('week',  days.d::timestamp)::date + 6)
        when 'monthly' then (date_trunc('month', days.d::timestamp) + '1 mon'::interval - '1 day'::interval)::date
      end as pe
    from days
  ),
  bounded as (
    select periods.pe from periods
    where periods.pe between p_start_date and p_end_date
      and periods.pe <= (select max(nd_max.nav_date) from pfin.nav_daily nd_max
                          where nd_max.users_id = auth.uid())        -- the redundant predicate
  )
  select bounded.pe, cp.nav_value, cp.nav_date
  from bounded
  cross join lateral (
    select nd.nav_value, nd.nav_date from pfin.nav_daily nd
    where nd.nav_date <= bounded.pe
      and nd.users_id = auth.uid()                                   -- the redundant predicate
    order by nd.nav_date desc limit 1
  ) as cp
  order by bounded.pe;
end;
$cf$;
grant execute on function pfin.fn_nav_series_qa_counterfactual(text,date,date) to authenticated;
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select array_agg(nav_value order by point_date) from pfin.fn_nav_series_qa_counterfactual('monthly','2026-01-01','2026-03-31')),
  array[80, 300]::numeric[],
  '(V3-REDUNDANT-PREDICATE-WOULD-BLIND-US) ⭐⭐ 062''S OWN RATIONALE, TESTED RATHER THAN ACCEPTED — and CONFIRMED. Under the IDENTICAL corruption that reds (V1), the redundant-predicate variant returns the BASELINE answer {80,300}: green, indistinguishable from a healthy fence. So adding a local users_id filter as "defense-in-depth" would buy a second layer at the cost of the ability to verify the FIRST — which is the one the whole V1 isolation model rests on. RED HERE would mean the rationale is wrong and 062 must carry the predicate after all');
select is(
  (select count(*)::int from pfin.fn_nav_series_qa_counterfactual('monthly','2026-01-01','2026-03-31')),
  2,
  '(V3b-REDUNDANT-PREDICATE-BLINDS-THE-COUNT-TOO) …and the blinding is not partial: the redundant variant matches the baseline on CARDINALITY as well as on values, so neither half of the (V1)/(V1b) pair would have caught the broken fence. Stated separately because "the value assertion would still have fired" is the natural objection to (V3), and this is the measurement that answers it');
select set_config('role', 'postgres', true);
rollback to savepoint v_s2;

-- ---- V/S1: the policy DROPPED outright. The mode the NEGATIVE alone cannot see. ----
savepoint v_s1;
drop policy nav_daily_select on pfin.nav_daily;
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*)::int from pfin.fn_nav_series('monthly','2026-01-01','2026-03-31')),
  0,
  '(V4-FENCE-ABSENT-IS-VACUOUS) ⚠ THE COUNTER-EXAMPLE TO THE OBVIOUS METHOD, kept deliberately. With the policy DROPPED (RLS still enabled, no policy ⇒ deny-all) A sees NOTHING — so a cross-tenant NEGATIVE assertion ("A sees none of B''s rows") passes VACUOUSLY here, on the nothing. THIS LEG IS NOT A PROOF OF ISOLATION and must never be cited as one; it is the demonstration that DELETING a fail-closed control tests the opposite of the intended property, which is why (V1) CORRUPTS instead. Under this mode only the POSITIVE legs fire — (I1), (I5), (M2), (X3) — so THE PAIRING IS LOAD-BEARING: deleting any positive leg as redundant reopens this mode as an undetectable failure');
select set_config('role', 'postgres', true);
rollback to savepoint v_s1;

-- ---- V/N + V/Z: do the SOURCE fences actually have teeth? Build the defect. ----
savepoint v_src;
create or replace function pfin.fn_nav_series(p_granularity text, p_start_date date, p_end_date date)
returns table (point_date date, nav_value numeric, checkpoint_date date)
language plpgsql stable security invoker set search_path = '' as $sab$
begin
  return query select p_start_date, pfin.fn_compute_nav(p_end_date, true), p_end_date;
end;
$sab$;
select ok(
  (select p.prosrc ~ 'compute_nav' from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_series'),
  '(V5-NO-RECOMPUTE-FENCE-HAS-TEETH) the (N1) no-recompute fence HAS TEETH: rebuilt with a body that actually calls the valuation function, the source predicate flips. Without this leg, (N1) is an absence assertion whose detection capability had never been run — the failure mode rls/DESIGN.md §10 records a whole battery agreeing with the defect its own comments described');
select set_config('role', 'postgres', true);
rollback to savepoint v_src;

savepoint v_zone;
create or replace function pfin.fn_nav_series(p_granularity text, p_start_date date, p_end_date date)
returns table (point_date date, nav_value numeric, checkpoint_date date)
language plpgsql stable security invoker set search_path = '' as $sab$
begin
  return query select p_start_date, 1::numeric, (p_end_date::timestamp with time zone)::date;
end;
$sab$;
select ok(
  (select p.prosrc !~* 'timestamptz' and p.prosrc ~* 'time zone'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_series'),
  '(V6-ZONE-FENCE-NEEDS-BOTH-SPELLINGS) ⭐ the zone fence needs BOTH spellings, PROVEN: this sabotage introduces a real zone-aware cast written as `timestamp with time zone`, and (Z1)''s `timestamptz` predicate STAYS GREEN on it while (Z2)''s catches it. That is the measurement behind (Z2) existing — item 10 as specified in the migration header fences only the abbreviation and would have passed over this body');
select set_config('role', 'postgres', true);
rollback to savepoint v_zone;

savepoint v_clock;
create or replace function pfin.fn_nav_series(p_granularity text, p_start_date date, p_end_date date)
returns table (point_date date, nav_value numeric, checkpoint_date date)
language plpgsql stable security invoker set search_path = '' as $sab$
begin
  return query select current_date, 1::numeric, p_end_date;
end;
$sab$;
select ok(
  (select p.prosrc !~* 'timestamptz|time zone' and p.prosrc ~* '\mcurrent_date\M'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_series'),
  '(V7-CLOCK-FENCE-IS-NOT-COVERED-BY-TYPE-FENCES) ⭐ …and the CLOCK fence is not covered by either type fence, PROVEN: a body using `current_date` — evaluated in the session TimeZone, and the exact token the migration header forbids a future editor — carries NEITHER spelling of the zone-aware type. (Z1) AND (Z2) both stay green on it; only (Z3) fires. This is why (Z3) exists');
select set_config('role', 'postgres', true);
rollback to savepoint v_clock;

-- ---- V/final: restoration, asserted rather than assumed. NOT in a savepoint. ----
select is(
  (select count(*)::int
     from pg_policies
    where schemaname = 'pfin' and tablename = 'nav_daily' and policyname = 'nav_daily_select'
      and qual like '%users_id = auth.uid()%'
      and qual like '%aal2%'
      and qual <> 'true'),
  1,
  '(V8-CONTROL-RESTORED) the corrupted policy is BACK, asserted on its QUAL and not merely on its existence. ⚑ AUTHORED AS A BARE `count(*) = 1` AND CORRECTED ON MEASUREMENT: `alter policy … using (true)` leaves the policy PRESENT with the same name, so pg_policies still reports exactly 1 row in BOTH the corrupted and the restored world — the original assertion could not tell them apart and would have passed over a still-broken fence. The predicate now requires the tenant conjunct to be back and the qualifier not to be `true`. Same defect class this file exists to catch, found in its own restoration check');
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select array_agg(nav_value order by point_date) from pfin.fn_nav_series('monthly','2026-01-01','2026-03-31')),
  array[80, 300]::numeric[],
  '(V9-PLAN-COUNTER-REARMED) ⭐ STRUCTURAL, AND DELIBERATELY LAST + OUTSIDE ANY SAVEPOINT (rls/DESIGN.md §9 harness note): it re-establishes pgTAP''s plan counter after the savepoint rewinds, so this file cannot emit a spurious "planned 46 but ran N" that would train a reader to discount the one signal distinguishing a real aborted run. It also earns its place independently — the function and the policy are both back to their authored behaviour, so the (V) block undid everything it did');
select set_config('role', 'postgres', true);

select * from finish();
rollback;

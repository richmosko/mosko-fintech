-- =====================================================================
-- Per-Wave battery — pfin.fn_nav_series_inflation_adjusted(p_granularity text,
--   p_start_date date, p_end_date date) — the §2.1.2.c CPI-U inflation-adjusted
--   net-worth overlay (SELF-218; migration 067). Composes on pfin.fn_nav_series
--   (062) + pfin.fn_cpi_u_index_for_period (066) — SECURITY INVOKER read-
--   composition, no relation read of its own. Paired with the migration in the
--   SAME PR (verify-paired-artifacts discipline).
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/067_fn_nav_series_inflation_adjusted.sql,
--   commit e0c1b5c on the item branch (architect worktree). RECONCILED against the
--   committed migration's own QA TEST-PAIRING block, which SUPERSEDES the earlier
--   temp/architect-self218.md §6 draft (12 criteria -> 13: adds the ADR-040
--   assembled-statement leg (ADR); sharpens #4/(F)/(C) to require the two CPI
--   levels DIFFER — already true of this fixture; sharpens #5/(N) to require
--   asserting the GAP ROW EXISTS, not just that the column is NULL — already true
--   here via results_eq, which fails outright on a dropped row). Column names/
--   order/formula verified against the migration's own RETURNS TABLE and body —
--   no drift from what this file assumed at first authoring.
--
--   ⚠ RECONCILIATION ROUND 2 (architect, temp/architect-self218-qa-reconcile.md):
--   the FIRST version of this file, run mentally against the landed pair, had 8 of
--   36 legs RED — not from the return shape (exact match, no drift) but from two
--   properties of 062's landed body this file's fixture had not accounted for:
--   (R1) 062 never emits a period-end AFTER the tenant's OVERALL max checkpoint
--   (its upper series bound — a caller-future-dated request must not draw a flat
--   line), so a checkpoint sitting mid-month rather than ON the period end drops
--   that month's point entirely; (R2) 'daily' grain emits one row per CALENDAR DAY
--   in the window, carry-forwarding a single checkpoint across all of it, so a
--   wide window inflates row counts for reasons unrelated to tenant isolation.
--   Three fixture edits (checkpoints moved onto period ends; two windows narrowed
--   to a single day) fixed all eight with NO assertion-logic change — recorded
--   here rather than silently corrected, per rls/DESIGN.md's own discipline that
--   a number reasoned into a fixture is unrun until the battery actually runs.
--   Also added on this pass: leg (NP) — architect found no row anywhere in the
--   original fixture ever set cpi_nonpublication_on_record TRUE, so nothing
--   distinguished a correct pass-through from a hardcoded false.
--
--   ⚠ RECONCILIATION ROUND 3 (Sec, AMBER on f03caa2 — team-lead relay): round 2's
--   (ZN2) rewrite REPLACED the clock-token deny-list instead of supplementing it.
--   FIX: (ZN2) kept UNCHANGED (structural — date_trunc/interval/::timestamp cast;
--   a DIFFERENT CLASS from clock reads, per architect's own correction of their
--   round-2 recommendation: a body containing only `where x <= current_date` has
--   no date_trunc/interval/::timestamp/timestamptz and passes ZN1+ZN2 both, so the
--   structural leg was never a superset of the token leg — it tests a different
--   property). (ZN3) ADDED as a separate leg, restoring the token deny-list.
--
--   ⚠ AMENDED AT SELF-343 / migration 095 (BACKLOG §7.14 first entry, condition 4 — QA-owned):
--   095 hardens this function's guard (explicit NaN and +Infinity clauses on both CPI legs,
--   create-or-replace, re-issued comment) and adds pfin.cpi_u_index.cpi_value's
--   cpi_u_index_value_positive_finite CHECK. Extended IN PLACE per the RLS-battery-keyed-to-
--   original-migration convention (the 071/072 precedent), not a new file. (ZC) rebuilt as a
--   5-poison-class corrupt-the-control family (095 makes 0/-1/NaN/±Infinity all un-seedable
--   through a plain INSERT once the CHECK holds); (ZCB) added for the basis-leg NaN/+Infinity
--   cases item 4 calls out; (CMT) added for the re-issued function comment; (V3) added as the
--   inversion proof that the hardened clauses are load-bearing. 053's own battery
--   (053_cpi_u_index_rls.sql) owns the CHECK's own reject/accept legs and the column-comment
--   watcher — this file owns everything reached THROUGH this function.
--
--   ⚠ ZN3 WENT THROUGH THREE DRAFTS BEFORE LANDING, RECORDED SO THE NEXT REBUILD
--   HAS A SOURCE TO DIFF AGAINST INSTEAD OF SOMEONE'S RECOLLECTION (architect's
--   root-cause diagnosis: "the list is being rebuilt from memory each round
--   because it has no source"). ZN3's member set is stated here as ITS OWN
--   ANCHOR — the UNION of two named sources, nothing else:
--     SOURCE A — the original (pre-round-2) token list this file carried:
--       current_date · current_timestamp · localtimestamp · localtime · now( ·
--       statement_timestamp( · clock_timestamp( · transaction_timestamp( · timezone(
--     SOURCE B —062's header near-miss (9), the evasions Sec catalogued there:
--       'today'::date · 'now'::timestamp · transaction_timestamp() ·
--       timezone('<zone>', …) [no space, so it slips a "time zone" text search] ·
--       plus date 'today' (the un-cast literal spelling of the same class).
--   Draft 1 (Sec's verbatim relay) covered Source A's first four members plus
--   Source B — missing localtime/statement_timestamp/clock_timestamp/
--   transaction_timestamp/timezone(. Draft 2 added transaction_timestamp/
--   timezone/statement_timestamp/clock_timestamp back — missing only localtime.
--   Draft 3 (this one) adds localtime. ANY FUTURE EDIT TO THIS LEG MUST BE STATED
--   AS A CHANGE TO SOURCE A OR SOURCE B ABOVE, not as a token added from memory.
--
--   Contract as landed:
--     returns table (point_date date, nav_nominal numeric, checkpoint_date date,
--       nav_inflation_adjusted numeric, cpi_period date, cpi_value numeric,
--       cpi_is_carried boolean, cpi_carried_from date, cpi_period_was_due boolean,
--       cpi_nonpublication_on_record boolean, cpi_coverage_through date)
--     SECURITY INVOKER · STABLE · set search_path = ''
--     Formula: nav_inflation_adjusted = nav_nominal * (cpi_today / cpi_at_point),
--       deflated at point_date (not checkpoint_date); cpi_today = the print at
--       066's coverage_through. Missing/unpublished/zero/negative CPI on either
--       leg -> nav_inflation_adjusted NULL, never a throw.
--
-- ┌─ WHAT THIS BATTERY PROVES — one line per migration-header QA TEST-PAIRING item ────┐
-- │ (1)  T   two-tenant, non-vacuously: SAME dates, DIFFERENT nav_values -> different   │
-- │          adjusted arrays.                                                          │
-- │ (2)  X   cross-tenant returns ZERO ROWS, not an error, at a canary window only the  │
-- │          other tenant has data in.                                                 │
-- │ (3)  M   aal2 backstop, BOTH legs (inherited through 062, INVOKER carries it).      │
-- │ (4)  F/C the arithmetic is real: an exact-print anchor (F) AND a carried-CPI anchor │
-- │          (C) where cpi_today != cpi_at_point, computed independently of the fn.     │
-- │ (5)  N   missing CPI (before coverage, nothing at-or-before) -> NULL, row still     │
-- │          returned, nav_nominal intact — never dropped, never a throw. (NP) is the   │
-- │          companion: the SAME before-coverage shape but WITH a 063 record, proving   │
-- │          cpi_nonpublication_on_record is forwarded and not hardcoded false.         │
-- │ (6)  Z   empty CPI store -> every row NULL adjusted, no raise. The leg invisible    │
-- │          without the fixture (066's helper raises on NULL coverage_through          │
-- │          unguarded).                                                               │
-- │ (7)  ZC  zero/negative/NaN/±Infinity on the POINT-leg denominator -> NULL, never a   │
-- │          raise, never a poisoned leak (SELF-343/095 corrupt-the-control family; both │
-- │          table CHECKs dropped per savepoint since 095 makes these un-seedable        │
-- │          otherwise). ZCB companions the NaN/+Infinity cases onto the BASIS leg.      │
-- │ (8)  C   carried CPI is SURFACED (cpi_is_carried/cpi_carried_from), not silently    │
-- │          applied — same leg as (4)'s carried anchor.                                │
-- │ (9)  P   nav_nominal + checkpoint_date byte-identical to 062's own output over the  │
-- │          SAME args — catches a re-implementation instead of composition.            │
-- │ (10) L   fail-loud inherited: bad granularity / inverted dates still raise.         │
-- │ (11) ZN  zone fence — a STRUCTURAL leg (ZN2, "no date arithmetic at all") PLUS a     │
-- │          TOKEN leg (ZN3, the clock-keyword deny-list) — DIFFERENT CLASSES, both     │
-- │          required per the migration's own #11; the differential digest is scoped   │
-- │          out (see below).                                                          │
-- │ (12) A   ACL: authenticated yes, PUBLIC / service_role no.                          │
-- │ (13) ADR ADR-040 assembled-statement discipline: the EXACT PostgREST-shaped named-  │
-- │          argument call, real `authenticated` role, real JWT claim, live DB,         │
-- │          rolled back — plus a catalog posture pin (INVOKER/STABLE/search_path).     │
-- │ (V)  ⭐  two inversion controls proving (X)/(ZC) are not vacuous — see below.        │
-- └──────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ ⚠ SCOPE DISCLOSURE — the DIFFERENTIAL DIGEST (062/066's two-TimeZone run) is scoped ─┐
-- │ OUT; the TOKEN LEG is NOT. 062's (Z4) and 064/066's zone legs run the function under   │
-- │ two extreme session TimeZones and assert byte-identical output — the property, not a   │
-- │ token proxy. This battery does NOT reproduce THAT here: 067 imprints no NEW zone       │
-- │ surface of its own (it reads nav_date/cpi_period through 062/066, both already zone-   │
-- │ fenced that way), so the marginal risk this leg exists to catch is a clock call ADDED  │
-- │ IN 067's OWN BODY, which the source-text fences below (ZN1/ZN2/ZN3) do catch.          │
-- │ ⚠ ACCEPTED BY ARCHITECT ON RECONCILIATION (temp/architect-self218-qa-reconcile.md):    │
-- │ "067's body performs no date arithmetic at all... so there is no zone-dependent        │
-- │ expression for a differential digest to catch that the text fence cannot." Sec         │
-- │ CONFIRMED this scope-down stands (AMBER round) — only the TOKEN LEG half of the        │
-- │ text-fence pair was found deficient, and is restored below as (ZN3). (ZN2) alone was   │
-- │ NEVER a substitute for it (different class — see RECONCILIATION ROUND 3 above), and    │
-- │ its comment previously implied otherwise — corrected.                                  │
-- └──────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ ⭐ (V) INVERSION — proving the negative legs are not vacuous ─────────────────────────┐
-- │ (V1) CORRUPT-THE-CONTROL: nav_daily_select broken open (`using (true)`, not dropped —  │
-- │      Postgres RLS fails CLOSED on absence, so a DROPPED policy would make (X)'s zero    │
-- │      pass vacuously; per rls/DESIGN.md, corrupt rather than delete). Probed at the      │
-- │      2025-10-01 canary — a date ONLY B holds, so A seeing it under corruption is an     │
-- │      unambiguous leak with no tie-break risk (062's own near-miss lesson).              │
-- │ (V2) the division-by-zero hazard (ZC) guards against is proven REAL at the SQL level    │
-- │      (bare numeric division by the literal 0), so a green (ZC) is evidence the guard    │
-- │      fired, not evidence the hazard never existed.                                      │
-- └──────────────────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3 / DEFINER ALLOWLIST — this battery introduces NO catalogued instance and
--   changes none. 067 authors ONE function, SECURITY INVOKER, reached by `authenticated`
--   over PostgREST; no credential, no container, no admission endpoint in its path, and it
--   creates no column of any kind (no FK-shaped reference to matched-tenant-validate). No
--   count is restated here — read ADR-011 Decision 3 and Decision 4 LIVE at the canonical
--   anchor at merge time.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants via _rls.tenant_a()/_b() plus
--   one locally-declared fixed tenant D (aal2 backstop). NO PII / NO real account numbers /
--   NO production data. Every nav_value and cpi_value is an invented round number. The
--   cpi_u_index fixture DELETES the table's rows inside the rolled-back transaction before
--   seeding (mirrors 064/066: this is a GLOBAL table, so an assertion about "is there a
--   later/earlier period" depends on every row in it, not just what this file wrote — a
--   fixture layered on ambient data would mean something different in CI vs a dev machine
--   with 137 real BLS prints). Safety: inside begin…rollback, no `supabase db reset` at any
--   point; cpi_u_index has no inbound FK so the delete cascades nothing.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated; every
--   _rls.set_tenant / _rls.count_as call runs at role=postgres and restores role=postgres
--   before the next assertion.
--
-- ⚠ RE-VERIFY AFTER ANY FURTHER LEG CHANGE. Last verified GREEN by QA (2026-08-29) via
--   pg_prove on a hand-built 001->095 scratch database (ownership transferred to postgres
--   before the migration chain — the shape that matches `supabase start`), against the
--   executable plan() call below, as part of a full supabase/tests-tree run (88 files, 2071
--   tests) rather than this file in isolation. Never bare psql (plan-count enforcement).
-- =====================================================================

begin;

-- shared cross-tenant verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

-- plan = 51 : 3 fixture pins (z) + 2 two-tenant (T) + 1 formula anchor (F) + 1 carried-CPI
-- anchor (C) + 4 before-coverage NULL (N) + 1 nonpublication passthrough (NP) + 4 empty-store
-- (Z) + 10 point-leg corrupt-the-control (ZC: zero/negative/NaN/+Infinity/-Infinity, 2 legs each
-- — SELF-343/095) + 4 basis-leg corrupt-the-control (ZCB: NaN/+Infinity, 2 legs each — SELF-343
-- item 4, the widened +Infinity guard) + 3 cross-tenant (X) + 1 062-parity passthrough (P) +
-- 2 aal2 backstop (M) + 2 fail-loud (L) + 3 zone fence (ZN: ZN1 timestamptz + ZN2 structural
-- + ZN3 token, restored per Sec AMBER) + 3 ACL (A) + 2 ADR-040 assembled-statement (ADR) +
-- 2 comment re-issue watchers (CMT — SELF-343 condition 3) + 3 inversion (V: V1/V2 original +
-- V3 SELF-343, the pre-095 guard leaking NaN).
select plan(51);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset
\set td '00000000-0000-0000-0000-00000000000d'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'td');

-- =====================================================================
-- FIXTURE — two tenants (A, B) with checkpoints on the SAME dates carrying DIFFERENT
--   nav_values (the non-vacuity requirement) plus deliberately non-overlapping edge
--   checkpoints that serve as leak/bound canaries; a third tenant D for the aal2 backstop.
--
--   A  2025-11-01=50    <- before CPI leading edge, NO record: the NULL-gap leg (N)
--      2025-12-01=999   <- before CPI leading edge, WITH a 063 record: the
--                           nonpublication-passthrough leg (NP). ⚠ MUST postdate (X)'s
--                           2025-10-01 canary window: an EARLIER A checkpoint would give
--                           062's lower-bound clamp something to carry INTO that window,
--                           defeating (X)'s "A holds nothing here" premise (measured while
--                           fixing this file — the first draft put NP at 2025-08-01 and it
--                           silently broke X1/X2).
--      2026-01-05=100   <- Jan, EXACT CPI print (310.000): formula anchor (F) uses Mar
--                           instead so this point free to be the carried-CPI companion
--      2026-02-10=200   <- Feb, CPI GAP (carried from Jan): the carried-CPI leg (C)
--      2026-03-31=300   <- Mar, EXACT CPI print (320.000), ON THE PERIOD END: the
--                           formula anchor (F). ⚠ MUST sit on-or-after the period end —
--                           062's upper series bound is `period_end <= tenant's MAX
--                           checkpoint`, architect-measured (temp/architect-self218-qa-
--                           reconcile.md): a checkpoint anywhere inside March (e.g.
--                           03-05) makes 062 DROP the March point entirely, since
--                           2026-03-31 > 2026-03-05. This is ALSO A's overall max
--                           checkpoint, so it bounds every other monthly leg below it.
--
--   B  2025-10-01=900   <- STRICTLY BEFORE A's earliest checkpoint (2025-11-01): the
--                           cross-tenant canary — A must
--                           see ZERO rows here (X), and it is the leak canary for (V1)
--                           since A has NO row to collide with. Probed as a SINGLE DAY
--                           (not a month) — 062 emits one row per CALENDAR DAY at
--                           'daily' grain, carrying B's checkpoint forward across the
--                           whole window, so a wider window returns far more than 1 row
--                           for reasons unrelated to tenant isolation (architect-measured).
--      2026-01-05=1000, 2026-02-10=2000, 2026-03-31=3000  <- SAME dates as A (Mar moved
--                           to the period end for the same 062 upper-bound reason above),
--                           10x the value: the two-tenant non-vacuity pair (T)
--
--   D  2026-01-05=777, 2026-02-28=888, mfa_policy='totp'  <- aal2 backstop (M), mirrors
--                           the 062/066 fixture idiom. Feb checkpoint moved to the period
--                           END (02-28) for the SAME 062 upper-bound reason: at 02-10 the
--                           February month-end point was dropped, so (M2)'s positive leg
--                           silently proved less than it claimed.
-- =====================================================================
insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta', 'none'), (:'tb', 'none'), (:'td', 'totp');

select set_config('app.nav_computed_for', :'ta', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values
  (:'ta','2025-11-01',50), (:'ta','2025-12-01',999), (:'ta','2026-01-05',100),
  (:'ta','2026-02-10',200), (:'ta','2026-03-31',300);
select set_config('app.nav_computed_for', :'tb', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values
  (:'tb','2025-10-01',900), (:'tb','2026-01-05',1000), (:'tb','2026-02-10',2000), (:'tb','2026-03-31',3000);
select set_config('app.nav_computed_for', :'td', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values
  (:'td','2026-01-05',777), (:'td','2026-02-28',888);
select set_config('role', 'postgres', true);

-- the ONE 063 record this fixture seeds — feeds (NP) only. A period with nothing
-- at-or-before it (before cpi_u_index's leading edge, seeded below), so it exercises
-- 066's B9 shape: recorded_nonpublication with no carry source.
insert into pfin.cpi_u_nonpublication (cpi_period, published_value_raw) values ('2025-12-01', '-');

-- cpi_u_index is GLOBAL — normalize to a known shape first (see POSTURE note above).
--   2026-01-01=310.000 (leading edge, exact for A/B's Jan checkpoint)
--   2026-02-01 ABSENT   (the interior gap A/B's Feb checkpoint carries across)
--   2026-03-01=320.000 (exact for A/B's Mar checkpoint)
--   2026-04-01=325.000 (trailing edge = coverage_through; cpi_today for every leg below)
delete from pfin.cpi_u_index;
insert into pfin.cpi_u_index (cpi_period, cpi_value) values
  ('2026-01-01', 310.000), ('2026-03-01', 320.000), ('2026-04-01', 325.000);

-- (z) fixture pins — every (N)/(C)/(F) assertion below is a claim ABOUT these three facts.
select is(
  (select max(cpi_period) from pfin.cpi_u_index), '2026-04-01'::date,
  '(z1) fixture pin: coverage_through (trailing edge) = 2026-04-01, value 325.000 — cpi_today for every non-NULL leg in this file'
);
select is(
  (select min(cpi_period) from pfin.cpi_u_index), '2026-01-01'::date,
  '(z2) fixture pin: leading edge = 2026-01-01 — A''s 2025-11-01 checkpoint is strictly before it, which is the premise of leg (N)'
);
select is(
  (select count(*) from pfin.cpi_u_index where cpi_period = '2026-02-01')::bigint, 0::bigint,
  '(z3) fixture pin: 2026-02-01 is ABSENT and interior (bracketed by Jan/Mar prints) — the premise of the carried-CPI leg (C)'
);

-- =====================================================================
-- (T) TWO-TENANT, NON-VACUOUSLY. Rounded to 6dp: the repeating decimals on the carried
--   Jan/Feb legs make an unrounded exact-equality assertion brittle to division order,
--   without weakening what is actually being proven (rls/DESIGN.md: a fixture with only
--   terminating decimals could not distinguish this from an implementation that rounds
--   differently and still be "the arithmetic").
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select array_agg(round(nav_inflation_adjusted, 6) order by point_date)
     from pfin.fn_nav_series_inflation_adjusted('monthly','2026-01-01','2026-03-31')),
  array[round(100*325.000/310.000,6), round(200*325.000/310.000,6), round(300*325.000/320.000,6)]::numeric[],
  '(T1) A''s monthly adjusted series over Jan-Mar, computed independently of the function under test. POSITIVE leg — fires if A stops seeing its own checkpoints, or if the formula composes the wrong ratio'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select array_agg(round(nav_inflation_adjusted, 6) order by point_date)
     from pfin.fn_nav_series_inflation_adjusted('monthly','2026-01-01','2026-03-31')),
  array[round(1000*325.000/310.000,6), round(2000*325.000/310.000,6), round(3000*325.000/320.000,6)]::numeric[],
  '(T2) ⭐ THE NON-VACUITY THAT MAKES (T1) A TEST: the IDENTICAL call under B, over the SAME dates, returns a DIFFERENT array (B''s nominal values are 10x A''s on every date). A same-value fixture would pass here under a broken tenant predicate'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (F) FORMULA ANCHOR — Mar checkpoint, EXACT CPI print on both legs (320.000 at point,
--   325.000 at coverage_through). 300 * (325/320) = 304.6875 terminates exactly, so this
--   is asserted WITHOUT rounding as the primary arithmetic proof; (C) below covers the
--   carried-CPI, repeating-decimal case. Full 11-column row so no column can be silently
--   wrong while the others read correct. ⚠ checkpoint_date is 2026-03-31, not 2026-03-05:
--   A's Mar checkpoint sits ON the period end (see the FIXTURE note on 062's upper series
--   bound), so checkpoint_date and point_date COINCIDE here — the exact-print anchor and
--   the fresh-checkpoint case are the same row by construction, which is fine since (G)-
--   style staleness is already covered by the carried-CPI leg (C) below, not by this one.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select results_eq(
  $$ select point_date, nav_nominal, checkpoint_date, round(nav_inflation_adjusted,6),
            cpi_period, cpi_value, cpi_is_carried, cpi_carried_from, cpi_period_was_due,
            cpi_nonpublication_on_record, cpi_coverage_through
       from pfin.fn_nav_series_inflation_adjusted('monthly','2026-03-01','2026-03-31') $$,
  $$ values ('2026-03-31'::date, 300::numeric, '2026-03-31'::date, 304.6875::numeric,
             '2026-03-01'::date, 320.000::numeric, false, '2026-03-01'::date, true,
             false, '2026-04-01'::date) $$,
  '(F1) ⭐ THE ARITHMETIC IS REAL: nav_nominal (300) x (cpi_today 325.000 / cpi_at_point 320.000) = 304.6875, computed independently of the function under test. A fixture where the two CPI values were equal could not distinguish this from an implementation that returns nominal unchanged (sharpened criterion #4) — 320 != 325 here'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (C) CARRIED CPI IS SURFACED, NOT SILENTLY APPLIED. Feb checkpoint: 2026-02-01 has no
--   own print, so cpi_at_point CARRIES from 2026-01-01 (310.000) — the ratio is
--   325.000/310.000, a repeating decimal, hence the 6dp round on both sides.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select results_eq(
  $$ select point_date, nav_nominal, checkpoint_date, round(nav_inflation_adjusted,6),
            cpi_period, round(cpi_value,3), cpi_is_carried, cpi_carried_from, cpi_period_was_due,
            cpi_nonpublication_on_record, cpi_coverage_through
       from pfin.fn_nav_series_inflation_adjusted('monthly','2026-02-01','2026-02-28') $$,
  $$ values ('2026-02-28'::date, 200::numeric, '2026-02-10'::date, round(200*325.000/310.000,6),
             '2026-02-01'::date, 310.000::numeric, true, '2026-01-01'::date, true,
             false, '2026-04-01'::date) $$,
  '(C1) ⭐ the fires this leg is built for: cpi_is_carried=true and cpi_carried_from names 2026-01-01 (the source period), NOT a silent application of a stale value. period_was_due=true because 2026-02-01 is bracketed by real prints on both sides (the informational-marker gate, per 066''s §2.4.4 rule). RED if either provenance column were dropped or the ratio computed against a fabricated value'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (N) MISSING CPI (before coverage, nothing at-or-before) -> NULL, never dropped, never a
--   throw. A's 2025-11-01 checkpoint predates cpi_u_index's leading edge entirely.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  $$ select * from pfin.fn_nav_series_inflation_adjusted('daily','2025-11-01','2025-11-01') $$,
  '(N0) a point_date before ALL CPI coverage does NOT raise — an unresolvable adjustment is a legitimate state, not a caller error'
);
select results_eq(
  $$ select point_date, nav_nominal, checkpoint_date, cpi_period
       from pfin.fn_nav_series_inflation_adjusted('daily','2025-11-01','2025-11-01') $$,
  $$ values ('2025-11-01'::date, 50::numeric, '2025-11-01'::date, '2025-11-01'::date) $$,
  '(N1) ⭐ SHARPENED CRITERION #5: THE ROW EXISTS — asserted by results_eq comparing the full row against an expected ONE-ROW set, which fails outright if the row were dropped. A NULL-only assertion on nav_inflation_adjusted alone would pass vacuously against an implementation that silently drops unresolvable points; this does not. nav_nominal (50) and checkpoint_date (2025-11-01) intact, and cpi_period names the NORMALIZED period the caller asked about'
);
select is(
  (select nav_inflation_adjusted from pfin.fn_nav_series_inflation_adjusted('daily','2025-11-01','2025-11-01')),
  null::numeric,
  '(N2) …and nav_inflation_adjusted IS NULL — THE NEGATIVE THAT FIRES: a fabricated 0 or a silently-dropped row. nav_nominal (50) and checkpoint_date (2025-11-01) still returned intact on the SAME row (see the migration header standing requirement that the row is never dropped)'
);
select ok(
  (select cpi_value is null and cpi_period_was_due = false and cpi_coverage_through = '2026-04-01'::date
     from pfin.fn_nav_series_inflation_adjusted('daily','2025-11-01','2025-11-01')),
  '(N3) cpi_value is NULL (nothing at-or-before to resolve), period_was_due is FALSE (an edge, not an alarm — 066''s marker gate), and coverage_through is STILL populated (2026-04-01): the dated basis line renders on every path, including the unresolvable one'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (NP) cpi_nonpublication_on_record IS FORWARDED, NOT HARDCODED. Architect's review
--   found nothing in the original fixture ever set this column TRUE — a body hardcoding
--   it to `false` would have passed every other leg in this file silently. Probes the
--   2025-12-01 checkpoint, for which a 063 record was seeded (main fixture block above)
--   at a period with NOTHING at-or-before it — 066's B9 shape: the record fires
--   recorded_nonpublication even at the leading edge, producing period_was_due=TRUE /
--   is_carried=FALSE / cpi_value=NULL, distinguishable from the plain unrecorded
--   before_coverage case at (N) by nonpublication_on_record alone.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select nav_nominal = 999 and checkpoint_date = '2025-12-01'::date
          and cpi_value is null and cpi_is_carried = false
          and cpi_period_was_due = true and cpi_nonpublication_on_record = true
          and nav_inflation_adjusted is null
     from pfin.fn_nav_series_inflation_adjusted('daily','2025-12-01','2025-12-01')),
  '(NP1) ⭐ cpi_nonpublication_on_record IS TRUE and REACHES THIS SURFACE — the recorded-nonpublication-at-the-edge shape. Nothing at-or-before to carry from, so is_carried is FALSE and cpi_value is NULL (nav_inflation_adjusted therefore NULL too), but period_was_due is TRUE because a 063 record exists — this is what makes it distinguishable from (N)''s plain unrecorded edge, and what a hardcoded `false` on this column cannot pass'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (Z) EMPTY CPI STORE. This is the leg invisible without the fixture: 066's helper
--   raises on a NULL coverage_through if the caller does not guard it, and an empty
--   store is the ONLY way to produce that NULL. Savepoint-scoped so the main fixture is
--   restored for legs below.
-- =====================================================================
savepoint empty_cpi;
delete from pfin.cpi_u_index;
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  $$ select * from pfin.fn_nav_series_inflation_adjusted('monthly','2026-01-01','2026-03-31') $$,
  '(Z0) ⭐ an EMPTY cpi_u_index does NOT raise. THE LEG THAT FIRES IF THE NULL-coverage_through GUARD IS EVER REMOVED: fn_cpi_u_index_for_period raises when asked to resolve a period against a NULL coverage_through, so 067 must skip that second call rather than let it propagate'
);
select is(
  (select count(*) from pfin.fn_nav_series_inflation_adjusted('monthly','2026-01-01','2026-03-31')
    where nav_inflation_adjusted is not null)::int,
  0,
  '(Z1) …and EVERY row returns NULL adjusted — none fabricated as 0 or as the nominal value unchanged'
);
select is(
  (select array_agg(nav_nominal order by point_date) from pfin.fn_nav_series_inflation_adjusted('monthly','2026-01-01','2026-03-31')),
  array[100, 200, 300]::numeric[],
  '(Z2a) …while nav_nominal STILL passes through correctly for all 3 points — an empty CPI store must not degrade the nominal half of this surface'
);
select is(
  (select array_agg(checkpoint_date order by point_date) from pfin.fn_nav_series_inflation_adjusted('monthly','2026-01-01','2026-03-31')),
  array['2026-01-05','2026-02-10','2026-03-31']::date[],
  '(Z2b) …and checkpoint_date likewise, confirming the NAV half of the composition is untouched by the CPI store being empty'
);
select set_config('role', 'postgres', true);
rollback to savepoint empty_cpi;

-- =====================================================================
-- (ZC) ZERO / NEGATIVE / NaN / ±Infinity ON THE POINT-LEG DENOMINATOR -> NULL, never a raise,
--   never 0, never a sign-flip, never a poisoned NaN/Infinity leak. SELF-343/095 condition (4):
--   these are CORRUPT-THE-CONTROL legs — 095's cpi_u_index_value_positive_finite CHECK now makes
--   every one of these five values un-seedable through a plain INSERT, so each savepoint below
--   drops BOTH constraints first (dropping only the new one would leave cpi_u_index_value_finite
--   blocking NaN/±Infinity and prove nothing about 067's own guard for those three — 095 header ⚠).
--   Once the CHECK holds in production this is unreachable-by-construction — 067's own header rule
--   that unreachable-by-construction is a reason to KEEP a leg, not skip it.
--   Each class: a no-raise control (lives_ok) plus ONE results_eq asserting the FULL row —
--   point_date, nav_nominal, nav_inflation_adjusted, cpi_value — in a single non-vacuous shot.
--   ⚠ NOT a bare `is(nav_inflation_adjusted, null)`: a scalar subquery over a DROPPED row also
--   returns NULL, so that shape would pass vacuously against an implementation that dropped the
--   row entirely (095 QA TEST-PAIRING item 3) — results_eq fails outright if the row is missing.
--   postgres owns pfin.cpi_u_index (measured directly against this file's scratch harness); role
--   is already postgres entering each savepoint below, so no role switch precedes the ALTER.
-- =====================================================================
savepoint zero_cpi;
alter table pfin.cpi_u_index
  drop constraint cpi_u_index_value_positive_finite,
  drop constraint cpi_u_index_value_finite;
delete from pfin.cpi_u_index;
insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2026-01-01', 0), ('2026-02-01', 325.000);
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  $$ select * from pfin.fn_nav_series_inflation_adjusted('daily','2026-01-05','2026-01-05') $$,
  '(ZC0) corrupt-the-control (SELF-343): a ZERO CPI print at the point-leg denominator, with BOTH CHECKs dropped, does NOT raise division-by-zero — 067''s own guard, not the table CHECK, is what holds here'
);
select results_eq(
  $$ select point_date, nav_nominal, nav_inflation_adjusted, cpi_value
       from pfin.fn_nav_series_inflation_adjusted('daily','2026-01-05','2026-01-05') $$,
  $$ values ('2026-01-05'::date, 100::numeric, null::numeric, 0::numeric) $$,
  '(ZC1) ⭐ THE ROW EXISTS (results_eq, not a scalar is()-on-NULL that would pass vacuously against a dropped row): nav_inflation_adjusted NULL, nav_nominal 100 intact, cpi_value=0 still surfaced — never a raise, never a fabricated 0, never a sign-flip'
);
select set_config('role', 'postgres', true);
rollback to savepoint zero_cpi;

savepoint negative_cpi;
alter table pfin.cpi_u_index
  drop constraint cpi_u_index_value_positive_finite,
  drop constraint cpi_u_index_value_finite;
delete from pfin.cpi_u_index;
insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2026-01-01', -5.000), ('2026-02-01', 325.000);
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  $$ select * from pfin.fn_nav_series_inflation_adjusted('daily','2026-01-05','2026-01-05') $$,
  '(ZCn0) corrupt-the-control (SELF-343): a NEGATIVE CPI print at the point-leg denominator, both CHECKs dropped, does not raise'
);
select results_eq(
  $$ select point_date, nav_nominal, nav_inflation_adjusted, cpi_value
       from pfin.fn_nav_series_inflation_adjusted('daily','2026-01-05','2026-01-05') $$,
  $$ values ('2026-01-05'::date, 100::numeric, null::numeric, -5.000::numeric) $$,
  '(ZCn1) ⭐ THE ROW EXISTS: nav_inflation_adjusted NULL, not a negative-multiplied nonsense figure; nav_nominal 100 intact; the poisoned -5.000 still surfaced'
);
select set_config('role', 'postgres', true);
rollback to savepoint negative_cpi;

savepoint nan_point_cpi;
alter table pfin.cpi_u_index
  drop constraint cpi_u_index_value_positive_finite,
  drop constraint cpi_u_index_value_finite;
delete from pfin.cpi_u_index;
insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2026-01-01', 'NaN'::numeric), ('2026-02-01', 325.000);
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  $$ select * from pfin.fn_nav_series_inflation_adjusted('daily','2026-01-05','2026-01-05') $$,
  '(ZCnan0) corrupt-the-control (SELF-343): a NaN CPI print at the point-leg denominator, both CHECKs dropped, does not raise — 067''s explicit NaN clause (095 STEP 4), not the table CHECK, guards this'
);
select results_eq(
  $$ select point_date, nav_nominal, nav_inflation_adjusted, cpi_value
       from pfin.fn_nav_series_inflation_adjusted('daily','2026-01-05','2026-01-05') $$,
  $$ values ('2026-01-05'::date, 100::numeric, null::numeric, 'NaN'::numeric) $$,
  '(ZCnan1) ⭐ THE ROW EXISTS: nav_inflation_adjusted NULL — never the poisoned NaN itself, which is what the PRE-095 guard would have returned (bare `<= 0` never catches NaN; see (V3) below). nav_nominal 100 intact, cpi_value surfaces the NaN print'
);
select set_config('role', 'postgres', true);
rollback to savepoint nan_point_cpi;

savepoint inf_point_cpi;
alter table pfin.cpi_u_index
  drop constraint cpi_u_index_value_positive_finite,
  drop constraint cpi_u_index_value_finite;
delete from pfin.cpi_u_index;
insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2026-01-01', 'Infinity'::numeric), ('2026-02-01', 325.000);
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  $$ select * from pfin.fn_nav_series_inflation_adjusted('daily','2026-01-05','2026-01-05') $$,
  '(ZCinf0) corrupt-the-control (SELF-343): a +Infinity CPI print at the point-leg denominator, both CHECKs dropped, does not raise'
);
select results_eq(
  $$ select point_date, nav_nominal, nav_inflation_adjusted, cpi_value
       from pfin.fn_nav_series_inflation_adjusted('daily','2026-01-05','2026-01-05') $$,
  $$ values ('2026-01-05'::date, 100::numeric, null::numeric, 'Infinity'::numeric) $$,
  '(ZCinf1) ⭐ THE ROW EXISTS: nav_inflation_adjusted NULL — never the FLAT-ZERO collapse the migration header names (point-leg +Infinity: basis/+Infinity -> 0, the pre-095 guard''s actual failure mode on this class; see (V3)). nav_nominal 100 intact, cpi_value surfaces the +Infinity print'
);
select set_config('role', 'postgres', true);
rollback to savepoint inf_point_cpi;

savepoint neg_inf_point_cpi;
alter table pfin.cpi_u_index
  drop constraint cpi_u_index_value_positive_finite,
  drop constraint cpi_u_index_value_finite;
delete from pfin.cpi_u_index;
insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2026-01-01', '-Infinity'::numeric), ('2026-02-01', 325.000);
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  $$ select * from pfin.fn_nav_series_inflation_adjusted('daily','2026-01-05','2026-01-05') $$,
  '(ZCninf0) corrupt-the-control (SELF-343): a -Infinity CPI print at the point-leg denominator, both CHECKs dropped, does not raise — caught by the pre-existing `<= 0` clause; no new clause was needed for this class'
);
select results_eq(
  $$ select point_date, nav_nominal, nav_inflation_adjusted, cpi_value
       from pfin.fn_nav_series_inflation_adjusted('daily','2026-01-05','2026-01-05') $$,
  $$ values ('2026-01-05'::date, 100::numeric, null::numeric, '-Infinity'::numeric) $$,
  '(ZCninf1) ⭐ THE ROW EXISTS: nav_inflation_adjusted NULL, nav_nominal 100 intact, cpi_value surfaces the -Infinity print — same shape as every other poison class, completing all five'
);
select set_config('role', 'postgres', true);
rollback to savepoint neg_inf_point_cpi;

-- =====================================================================
-- (ZCB) NaN / +Infinity ON THE BASIS LEG (the store's trailing coverage print, not the at-point
--   print) — SELF-343 item 4: the WIDENED guard bars +Infinity on BOTH legs. The two legs fail in
--   DIFFERENT ways when poisoned: point-leg +Infinity collapses the figure to a FLAT ZERO
--   (basis/+Infinity -> 0, indistinguishable from "real value is zero" — see ZCinf1 above and
--   (V3) below); basis-leg +Infinity does the opposite, yielding an INFINITE figure
--   (+Infinity/finite -> +Infinity, multiplied through nav_nominal). Same corrupt-the-control
--   shape: both CHECKs dropped in a savepoint. The coverage/basis print is the table's MAX
--   cpi_period (067's z1 fixture pin above already establishes coverage_through = max(cpi_period)).
-- =====================================================================
savepoint nan_basis_cpi;
alter table pfin.cpi_u_index
  drop constraint cpi_u_index_value_positive_finite,
  drop constraint cpi_u_index_value_finite;
delete from pfin.cpi_u_index;
insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2026-01-01', 100), ('2026-02-01', 'NaN'::numeric);
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  $$ select * from pfin.fn_nav_series_inflation_adjusted('daily','2026-01-05','2026-01-05') $$,
  '(ZCBnan0) corrupt-the-control (SELF-343): a NaN print at the BASIS (coverage_through, 2026-02-01 = max cpi_period) leg, both CHECKs dropped, does not raise'
);
select results_eq(
  $$ select point_date, nav_nominal, nav_inflation_adjusted, cpi_value
       from pfin.fn_nav_series_inflation_adjusted('daily','2026-01-05','2026-01-05') $$,
  $$ values ('2026-01-05'::date, 100::numeric, null::numeric, 100::numeric) $$,
  '(ZCBnan1) ⭐ THE ROW EXISTS: nav_inflation_adjusted NULL even though the AT-POINT leg (cpi_value, surfaced here as 100) is perfectly finite — the poison is on the BASIS leg alone, so only the guard''s own basis-leg clause can be catching this'
);
select set_config('role', 'postgres', true);
rollback to savepoint nan_basis_cpi;

savepoint inf_basis_cpi;
alter table pfin.cpi_u_index
  drop constraint cpi_u_index_value_positive_finite,
  drop constraint cpi_u_index_value_finite;
delete from pfin.cpi_u_index;
insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2026-01-01', 100), ('2026-02-01', 'Infinity'::numeric);
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  $$ select * from pfin.fn_nav_series_inflation_adjusted('daily','2026-01-05','2026-01-05') $$,
  '(ZCBinf0) corrupt-the-control (SELF-343): a +Infinity print at the BASIS (coverage_through) leg, both CHECKs dropped, does not raise — without the guard this leg would multiply nav_nominal by an infinite ratio, the OPPOSITE failure mode from the point-leg case'
);
select results_eq(
  $$ select point_date, nav_nominal, nav_inflation_adjusted, cpi_value
       from pfin.fn_nav_series_inflation_adjusted('daily','2026-01-05','2026-01-05') $$,
  $$ values ('2026-01-05'::date, 100::numeric, null::numeric, 100::numeric) $$,
  '(ZCBinf1) ⭐ THE ROW EXISTS: nav_inflation_adjusted NULL, never an infinite figure — the AT-POINT leg (cpi_value=100) is finite and correctly surfaced; the poison and the guard that catches it are both on the basis leg alone'
);
select set_config('role', 'postgres', true);
rollback to savepoint inf_basis_cpi;

-- =====================================================================
-- (X) CROSS-TENANT FAILS CLOSED AS ZERO ROWS, NOT AN ERROR. Probed at B's 2025-10-01
--   checkpoint — strictly before A's earliest (2025-11-01), so A has NO row of its own to
--   collide with here (the deliberate canary, also reused at (V1)). ⚠ SINGLE-DAY WINDOW,
--   NOT A MONTH: 062 emits one row per CALENDAR DAY at 'daily' grain and carries B's
--   checkpoint forward across the whole window (architect-measured: a 31-day window
--   returned 31 rows for B, unrelated to tenant isolation). Narrowing to exactly
--   2025-10-01 keeps this leg a pure isolation probe.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  $$ select * from pfin.fn_nav_series_inflation_adjusted('daily','2025-10-01','2025-10-01') $$,
  '(X1) fails CLOSED, not LOUD: a window containing only another tenant''s checkpoint returns normally'
);
select is(
  (select count(*)::int from pfin.fn_nav_series_inflation_adjusted('daily','2025-10-01','2025-10-01')),
  0,
  '(X2) …and returns ZERO ROWS — B''s 2025-10-01 checkpoint is invisible to A'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select results_eq(
  $$ select point_date, nav_nominal from pfin.fn_nav_series_inflation_adjusted('daily','2025-10-01','2025-10-01') $$,
  $$ values ('2025-10-01'::date, 900::numeric) $$,
  '(X3) NON-VACUOUS COMPANION to (X2): B sees exactly its own 2025-10-01/900 point over the identical window — so (X2)''s zero is a cross-tenant BOUNDARY denial, not an empty window'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (P) 062-PARITY PASSTHROUGH. nav_nominal + checkpoint_date must be byte-identical to
--   fn_nav_series' own nav_value + checkpoint_date over the SAME args — catches a
--   re-implementation of the checkpoint read instead of a genuine call into 062. ⚠ THE
--   WINDOW STILL EXTENDS INTO APRIL, BUT NO APRIL POINT IS EVER EMITTED BY EITHER SIDE:
--   062's upper series bound (period_end <= tenant's max checkpoint, 2026-03-31 here)
--   excludes 2026-04-30 on BOTH the direct 062 call and the 067 call underneath it
--   (architect-measured). This leg is self-referential — it compares two live queries
--   against each other rather than against a hardcoded row count — so it holds at
--   whatever cardinality both sides agree on; the April reach was originally described
--   here as proving something it does not, corrected on review rather than left standing.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select results_eq(
  $$ select point_date, nav_nominal, checkpoint_date
       from pfin.fn_nav_series_inflation_adjusted('monthly','2026-01-01','2026-04-30') $$,
  $$ select point_date, nav_value, checkpoint_date
       from pfin.fn_nav_series('monthly','2026-01-01','2026-04-30') $$,
  '(P1) ⭐ nav_nominal/checkpoint_date are byte-identical, row for row, to a direct call into pfin.fn_nav_series over the SAME arguments. RED if 067 re-derives the checkpoint read instead of composing on 062'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (M) AAL2 STEP-UP BACKSTOP, BOTH LEGS — inherited through fn_nav_series (062) via the
--   SECURITY INVOKER posture; 067 creates no policy of its own.
-- =====================================================================
select is(
  _rls.count_as(:'td'::uuid, 'aal1', $$ select count(*) from pfin.fn_nav_series_inflation_adjusted('monthly','2026-01-01','2026-02-28') $$),
  0::bigint,
  '(M1) aal2 backstop NEGATIVE leg: tenant D declared mfa_policy ''totp'' and presents an aal1 session -> 0 rows through this function'
);
select is(
  _rls.count_as(:'td'::uuid, 'aal2', $$ select count(*) from pfin.fn_nav_series_inflation_adjusted('monthly','2026-01-01','2026-02-28') $$),
  2::bigint,
  '(M2) ⭐ POSITIVE leg: the SAME tenant at aal2 sees 2 rows (Jan+Feb, bounded by D''s own checkpoints). Without this, (M1) passes on an empty fixture and proves nothing'
);

-- =====================================================================
-- (L) FAIL-LOUD INHERITED — an unknown granularity / inverted range still raises,
--   through the 062 call this function composes on.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select throws_ok(
  $$ select * from pfin.fn_nav_series_inflation_adjusted('yearly','2026-01-01','2026-03-31') $$,
  'P0001', null,
  '(L1) an UNKNOWN granularity RAISES rather than returning empty — 062''s fence, inherited unmodified'
);
select throws_like(
  $$ select * from pfin.fn_nav_series_inflation_adjusted('monthly','2026-03-31','2026-01-01') $$,
  '%is after%',
  '(L2) an INVERTED date range raises 062''s own date fence, asserted on the message so a caller error is not mistaken for an empty result'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (ZN) ZONE TEXT-FENCE — a STRUCTURAL leg (ZN2) plus a TOKEN leg (ZN3). Sec's AMBER
--   finding on the prior commit: round 2 REPLACED the token deny-list with the
--   structural check instead of keeping both, dropping this function's own paired-QA
--   requirement #11 ("keep token legs ... as the cheap secondary") on the floor. Both
--   now run. ZN3's member set is anchored at the top of this file (Source A / Source B)
--   after two rounds of an incomplete rebuild — read that block before editing this leg.
-- =====================================================================
select ok(
  (select p.prosrc !~* 'timestamptz'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_series_inflation_adjusted'),
  '(ZN1) the stored source carries no `timestamptz` — nothing in this function is evaluated in the session TimeZone'
);
select ok(
  (select p.prosrc !~* 'date_trunc|interval|::\s*timestamp'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_series_inflation_adjusted'),
  '(ZN2) STRUCTURAL: no date_trunc, no interval, no ::timestamp cast anywhere in prosrc — the positive property that 067 performs no date arithmetic at all (it passes dates through and multiplies two numerics). ⚠ CORROBORATING, NOT SUBSTITUTIVE — a DIFFERENT CLASS from (ZN3): a body containing only `where x <= current_date` has no date_trunc/interval/::timestamp cast and passes this leg cleanly, so this leg was never a superset of the clock-keyword class (ZN3)''s job, restored below after Sec found an earlier version of THIS comment claiming coverage it never had. True of the committed body today, and it fires the moment someone adds the per-distinct-month optimization the migration header explicitly parks — exactly the change that would re-open the zone question for this file'
);
select ok(
  (select p.prosrc !~* '\mcurrent_date\M|\mcurrent_timestamp\M|\mlocaltimestamp\M|\mlocaltime\M|\mnow\s*\(|\mstatement_timestamp\s*\(|\mclock_timestamp\s*\(|\mtransaction_timestamp\s*\(|\mtimezone\s*\(|''(now|today|tomorrow|yesterday)''|timestamp\s+with\s+time\s+zone'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_series_inflation_adjusted'),
  '(ZN3) ⭐ RESTORED PER SEC (AMBER on f03caa2), member set = Source A UNION Source B stated in the header (read there before editing — this leg took three drafts to reach the full set and the header records why). Catches the full clock-function family (current_date, current_timestamp, localtimestamp, localtime, now(, statement_timestamp(, clock_timestamp(, transaction_timestamp(, timezone() plus the bare-quoted keywords today/now/yesterday/tomorrow — ONE pattern catching BOTH the ''x''::date and the date ''x'' spelling, since it matches the quoted keyword regardless of what precedes or follows it (the idiom proven at 062''s (Z3)) — plus the uncast "timestamp with time zone" spelling. Measured NOT to false-positive on `date ''1913-01-01''`, the fixed CPI-U series epoch literal in the coverage probe: the keyword alternation matches only the four clock words, never an arbitrary date literal. An enumeration is still exhortation wearing a regex (062''s near-miss (9)) — which is exactly why (ZN2) exists too, and why this leg alone was never sufficient either'
);

-- =====================================================================
-- (A) ACL.
-- =====================================================================
select ok(
  has_function_privilege('authenticated', 'pfin.fn_nav_series_inflation_adjusted(text,date,date)', 'execute'),
  '(A1) authenticated HOLDS EXECUTE'
);
select ok(
  not has_function_privilege('public', 'pfin.fn_nav_series_inflation_adjusted(text,date,date)', 'execute'),
  '(A2) LOAD-BEARING: PUBLIC does NOT — `create function` grants EXECUTE to PUBLIC by default, so the revoke is load-bearing and silent on removal'
);
select ok(
  not has_function_privilege('service_role', 'pfin.fn_nav_series_inflation_adjusted(text,date,date)', 'execute'),
  '(A3) service_role does NOT hold EXECUTE — carrying forward 066''s recorded reasoning (worker identity is NOINHERIT and must `set role authenticated`); a grant here would turn an INVOKER helper into a de facto cross-tenant read'
);

-- =====================================================================
-- (ADR) CRITERION #13 — ADR-040 ASSEMBLED-STATEMENT DISCIPLINE. The EXACT
--   production statement text — PostgREST invokes an RPC with NAMED arguments,
--   never positionally — under the real `authenticated` role with a real JWT
--   claim, against a live database, in this rolled-back transaction. Reuses the
--   (F1) fixture (Mar checkpoint, exact CPI both legs) so the expected value is
--   already independently verified above; this leg's job is the CALL SHAPE, not
--   a second arithmetic proof.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select nav_inflation_adjusted from pfin.fn_nav_series_inflation_adjusted(
     p_granularity := 'monthly', p_start_date := '2026-03-01', p_end_date := '2026-03-31')),
  304.6875::numeric,
  '(ADR1) ⭐ THE REAL POSTGREST CALL SHAPE: named arguments, pinning p_granularity / p_start_date / p_end_date by NAME. A rename of any parameter is invisible to every positional call in this file and would 404 every production request'
);
select set_config('role', 'postgres', true);
select is(
  (select array[p.prosecdef::text, p.provolatile::text, array_to_string(p.proconfig, ',')]
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_series_inflation_adjusted'),
  array['false','s','search_path=""'],
  '(ADR2) POSTURE, read DECLARATIVELY from the catalog: SECURITY INVOKER (prosecdef false), STABLE (provolatile s), search_path pinned empty. Behaviour alone cannot distinguish INVOKER from a DEFINER owned by a non-privileged role — only the catalog can, and DEFINER here would detach the read from both 062''s RLS context and the inherited aal2 backstop'
);

-- =====================================================================
-- (CMT) COMMENT RE-ISSUE WATCHERS (SELF-343 condition 3, function half) — catalog reads, not
--   file-text checks. 095 STEP 5 re-issues this function's comment because create-or-replace
--   preserves the OLD one otherwise, which would keep describing a guard the function no longer
--   has. 053's own battery owns the matching column-comment watcher (095 STEP 3).
-- =====================================================================
select ok(
  obj_description('pfin.fn_nav_series_inflation_adjusted(text,date,date)'::regprocedure, 'pg_proc')
    ~* 'landed at 095',
  '(CMT1) obj_description names the 095 landing point for cpi_u_index_value_positive_finite — the comment was actually RE-ISSUED, not left stale by create-or-replace''s comment-preserving behaviour'
);
select ok(
  obj_description('pfin.fn_nav_series_inflation_adjusted(text,date,date)'::regprocedure, 'pg_proc')
    !~* 'bars NaN and the infinities but NOT zero or negative values',
  '(CMT2) obj_description no longer states the stale premise ("053''s finiteness CHECK bars NaN/±Infinity but NOT zero or negative values") — that premise went false the moment 095 applied, and the pre-095 wording named a "separate vehicle" that this function''s own catalog comment must not still describe as pending'
);

-- =====================================================================
-- (V) ⭐ INVERSION — proving (X) and (ZC) are not vacuous.
-- =====================================================================
savepoint v1_corrupt_rls;
alter policy nav_daily_select on pfin.nav_daily using (true);
select _rls.set_tenant(:'ta'::uuid);
select results_eq(
  $$ select point_date, nav_nominal from pfin.fn_nav_series_inflation_adjusted('daily','2025-10-01','2025-10-01') $$,
  $$ values ('2025-10-01'::date, 900::numeric) $$,
  '(V1-FENCE-CORRUPTED-IS-DETECTED) ⭐ with nav_daily_select broken OPEN, A''s call at the SAME single-day canary window (X1/X2) now LEAKS B''s 2025-10-01/900 point. This is (X2) going RED, measured rather than asserted — the canary was chosen specifically so A has no row of its own here, so any hit is unambiguously a leak, not a tie-break. Narrowed to a single day (not a month) for the SAME reason (X) is: a wider window would carry B''s checkpoint forward across every remaining day regardless of RLS, drowning the isolation signal in the calendar-day-expansion property'
);
select set_config('role', 'postgres', true);
rollback to savepoint v1_corrupt_rls;

select throws_like(
  $$ select 325.000::numeric / 0::numeric $$,
  '%division by zero%',
  '(V2) the hazard (ZC) guards against is REAL at the SQL level: a bare numeric division by the literal 0 raises division_by_zero. So (ZC0)''s green is evidence the guard fired, not evidence there was never anything to guard against'
);

-- =====================================================================
-- (V3) ⭐ INVERSION (SELF-343) — proving the 095-HARDENED guard is load-bearing, not decorative.
--   Restores the PRE-095 CASE (bare `<= 0` on each leg, no NaN/+Infinity clause) via create-or-
--   replace inside a nested savepoint, corrupts cpi_u_index with the SAME NaN point-leg fixture
--   (ZCnan1) uses (both table CHECKs also dropped), and asserts the OLD body LEAKS the poison
--   rather than nulling it — measured, not merely asserted: `NaN <= 0` is FALSE (PostgreSQL
--   numeric places NaN above every finite value), so the old guard's two `when` clauses never
--   fire and the `else` branch computes nav_nominal * (finite / NaN) = NaN. This is exactly what
--   (ZCnan1) would have missed had the 095 clauses never landed. Rolled back at the end, which
--   restores BOTH table CHECKs and the REAL (095-hardened) function body — DDL inside a savepoint
--   is fully transactional, function bodies included.
-- =====================================================================
select set_config('role', 'postgres', true);
savepoint v3_uncorrupt_guard;
alter table pfin.cpi_u_index
  drop constraint cpi_u_index_value_positive_finite,
  drop constraint cpi_u_index_value_finite;

create or replace function pfin.fn_nav_series_inflation_adjusted(
  p_granularity text,
  p_start_date  date,
  p_end_date    date
)
returns table (
  point_date                    date,
  nav_nominal                   numeric,
  checkpoint_date               date,
  nav_inflation_adjusted        numeric,
  cpi_period                    date,
  cpi_value                     numeric,
  cpi_is_carried                boolean,
  cpi_carried_from              date,
  cpi_period_was_due            boolean,
  cpi_nonpublication_on_record  boolean,
  cpi_coverage_through          date
)
language plpgsql
stable
security invoker
set search_path = ''
as $inv$
#variable_conflict use_column
declare
  v_coverage  date;
  v_cpi_basis numeric;
begin
  select h.coverage_through into v_coverage
  from pfin.fn_cpi_u_index_for_period(date '1913-01-01') h;

  if v_coverage is not null then
    select h.cpi_value into v_cpi_basis
    from pfin.fn_cpi_u_index_for_period(v_coverage) h;
  end if;

  return query
  select
    s.point_date,
    s.nav_value,
    s.checkpoint_date,
    -- PRE-095 GUARD, DELIBERATELY RESTORED FOR THIS INVERSION LEG ONLY: bare `<= 0`, no NaN/
    -- +Infinity clause. `NaN <= 0` and `Infinity <= 0` are both FALSE, so neither `when` fires.
    case
      when v_cpi_basis is null or v_cpi_basis <= 0 then null::numeric
      when c.cpi_value  is null or c.cpi_value  <= 0 then null::numeric
      else s.nav_value * (v_cpi_basis / c.cpi_value)
    end,
    c.cpi_period,
    c.cpi_value,
    c.is_carried,
    c.carried_from,
    c.period_was_due,
    c.nonpublication_on_record,
    c.coverage_through
  from pfin.fn_nav_series(p_granularity, p_start_date, p_end_date) s
  cross join lateral pfin.fn_cpi_u_index_for_period(s.point_date) c
  order by s.point_date;
end;
$inv$;

delete from pfin.cpi_u_index;
insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2026-01-01', 'NaN'::numeric), ('2026-02-01', 325.000);
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select nav_inflation_adjusted from pfin.fn_nav_series_inflation_adjusted('daily','2026-01-05','2026-01-05')),
  'NaN'::numeric,
  '(V3) ⭐ THE HARDENED CLAUSE IS LOAD-BEARING, MEASURED: with the PRE-095 guard body restored, the SAME NaN-point-leg fixture that (ZCnan1) asserts NULL for now LEAKS the poison as nav_inflation_adjusted = NaN — `NaN <= 0` is FALSE in PostgreSQL numeric ordering, so the old guard''s when-clauses never fire and the else branch computes nav_nominal * (finite / NaN). This is exactly what (ZCnan1) would have missed had the 095 clauses never been added'
);
select set_config('role', 'postgres', true);
rollback to savepoint v3_uncorrupt_guard;

rollback;

-- =====================================================================
-- Per-Wave battery — pfin.fn_first_cron_checkpoint() — the §2.1.2.d boundary-date
--   signal (SELF-220; migration 069). SECURITY INVOKER read-composition over
--   pfin.nav_daily (054) ONLY — no relation read of its own beyond that one table,
--   no arguments (the answer is a property of the caller's own store). Paired with
--   the migration in the SAME PR (verify-paired-artifacts discipline).
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/069_fn_first_cron_checkpoint.sql. Every
--   leg below is one line of that migration's own QA TEST-PAIRING block (items
--   1-7) — no drift from what that block specifies; column names/order/CONTRACT
--   verified against the migration's own RETURNS TABLE and body.
--
--   Contract as landed:
--     returns table (first_cron_checkpoint date, has_cron_rows boolean,
--       has_imported_rows boolean) — SECURITY INVOKER · STABLE · set search_path = ''.
--     EXACTLY ONE ROW, ALWAYS (an aggregate over an empty set still returns a row).
--     CLASSIFIER: a row is CRON iff created_at < nav_date + interval '7 days';
--       otherwise IMPORTED. The 7-day margin is load-bearing (26-hour max session-
--       zone span vs. months-scale real import gaps) — see the migration header's
--       "THE ZONE QUESTION" section for the full reasoning this battery verifies
--       directly at leg (1), not by inspecting the margin's literal value.
--     TENANT FENCE: inherited entirely from nav_daily's RLS SELECT policy (054) —
--       this function adds no users_id predicate of its own. A cross-tenant caller
--       gets the empty-store answer (NULL/false/false), never an error and never a
--       leaked aggregate.
--
-- ┌─ WHAT THIS BATTERY PROVES — one line per migration-header QA TEST-PAIRING item ────┐
-- │ (1)  Z-INV ZONE INVARIANCE, THE PROPERTY, NOT A TOKEN PROXY: full-row digest,      │
-- │          byte-identical under two extreme session TimeZones (Kiritimati UTC+14 /   │
-- │          Midway UTC-11). Plus a same-file inversion control proving the harness    │
-- │          itself is capable of catching a genuinely zone-dependent comparison —     │
-- │          without it, this leg's green would be zone-BLINDNESS, not proof.          │
-- │ (2)  MTX FOUR-STATE MATRIX, all four, asserted on the FULL row: (a) no rows, (b)    │
-- │          imported only ⭐, (c) cron only, (d) mixed. (a)'s assertion is probed      │
-- │          AFTER every other tenant below already holds rows, so it doubles as leg   │
-- │          (5)'s non-vacuous cross-tenant/no-leak proof (noted inline, not double-    │
-- │          counted in the plan).                                                     │
-- │ (3)  MRG  THE MARGIN DISCRIMINATES, NON-VACUOUSLY: a cron-shaped row and an         │
-- │          import-shaped row in the SAME store classify into DIFFERENT buckets —     │
-- │          the returned date is the cron row's, never the import row's.             │
-- │ (4)  T   TWO-TENANT, NON-VACUOUSLY: A and B, DIFFERENT boundary dates; A's call    │
-- │          returns A's, and the IDENTICAL call under B returns something different.  │
-- │ (5)  X   CROSS-TENANT gets the empty-store answer, not an error, not a leaked      │
-- │          aggregate — folded into leg (2a); see note there.                         │
-- │ (6)  M   AAL2 BACKSTOP, BOTH LEGS: aal1 -> (NULL,false,false); aal2 -> the real     │
-- │          boundary. Without the positive leg the negative passes vacuously.         │
-- │ (7)  A   ACL: authenticated yes, PUBLIC no, service_role no (structural exclusion   │
-- │          per the migration header — service_role cannot read created_at at all).   │
-- │ (8)  PST CATALOG POSTURE, read declaratively (Sec AMBER, 2026-08-13, added post-    │
-- │          review): prosecdef/provolatile/proconfig assert INVOKER/STABLE/search_path │
-- │          pinned — none of legs (1)-(7) would catch a DEFINER swap, a VOLATILE       │
-- │          relaxation, or a dropped search_path pin. 067's (ADR2) idiom.              │
-- └──────────────────────────────────────────────────────────────────────────────────────┘
--
-- ⚠ `supabase db reset` is PROHIBITED — destroys F/CTO's active local test data.
--   Scratch database only. Verified with pg_prove, NEVER bare psql (bare psql
--   exits 0 on a failed plan count — the QA scratch-DB harness lesson).
-- =====================================================================

begin;

-- shared cross-tenant verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

-- plan = 19 : 3 fixture pins (Z) + 2 zone-invariance (Z-INV incl. inversion control)
-- + 4 four-state matrix (MTX; (a) doubles as leg 5's non-vacuous cross-tenant proof)
-- + 2 margin-discriminates (MRG) + 2 two-tenant (T) + 2 aal2 backstop (M) + 3 ACL (A)
-- + 1 catalog posture (PST; Sec AMBER, 2026-08-13 — item 8, added post-review).
select plan(19);

-- Resolve the shared fixed tenant UUIDs while privileged (role=postgres); three
-- more purpose-built tenants beyond what _fixtures/rls_verbs.psql provides, one
-- per four-state-matrix shape that A/B/C (all "mixed") don't cover on their own.
select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset
\set te '00000000-0000-0000-0000-0000000000e0'
\set tf '00000000-0000-0000-0000-0000000000f0'
\set tg '00000000-0000-0000-0000-000000000090'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc'), (:'te'), (:'tf'), (:'tg');

-- =====================================================================
-- FIXTURE — six tenants, each a distinct SHAPE of the classifier's input space:
--
--   A  MIXED — imported row (~10.5y gap) + two cron rows (hours-scale gap). Boundary
--      = 2026-06-01 (the EARLIER cron nav_date). Used for: zone-invariance (1),
--      margin-discriminates (3), two-tenant (4), four-state (d).
--   B  MIXED — SAME shape as A, DIFFERENT dates throughout, boundary = 2026-07-20.
--      Used for: two-tenant non-vacuity (4) — the pair only proves something if the
--      two boundaries actually differ.
--   C  MIXED, mfa_policy='totp' — aal2 backstop tenant (6). Boundary = 2026-05-10.
--   E  ZERO ROWS — four-state (a) AND cross-tenant leg (5): probed LAST, after
--      A/B/C/F/G already hold rows, so a leaked/blended aggregate would show up here
--      if RLS (or a stray local predicate) were broken.
--   F  IMPORTED ONLY, no cron rows at all — four-state (b), the state a bare `date`
--      return would collapse into (a); GUARANTEED to occur in production between a
--      seeding run and the first cron night (migration header).
--   G  CRON ONLY, no imported rows at all — four-state (c).
--
--   All created_at values carry an explicit +00 offset so the FIXTURE itself is
--   zone-safe regardless of the scratch DB's ambient session TimeZone at load time;
--   only the ASSERTIONS below deliberately vary TimeZone.
-- =====================================================================
insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta', 'none'), (:'tb', 'none'), (:'tc', 'totp'), (:'te', 'none'), (:'tf', 'none'), (:'tg', 'none');

select set_config('app.nav_computed_for', :'ta', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value, created_at) values
  (:'ta', '2015-12-31', 50,  '2026-08-01 12:00:00+00'),  -- imported: ~10.5y gap
  (:'ta', '2026-06-01', 100, '2026-06-01 23:50:00+00'),  -- cron: ~0h gap -> A's boundary
  (:'ta', '2026-06-15', 110, '2026-06-16 04:00:00+00');  -- cron: ~28h gap
select set_config('app.nav_computed_for', :'tb', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value, created_at) values
  (:'tb', '2016-03-31', 900, '2026-08-01 12:00:00+00'),  -- imported
  (:'tb', '2026-07-20', 950, '2026-07-20 22:00:00+00');  -- cron -> B's boundary (DIFFERENT from A's)
select set_config('app.nav_computed_for', :'tc', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value, created_at) values
  (:'tc', '2016-06-30', 777, '2026-08-01 12:00:00+00'),  -- imported
  (:'tc', '2026-05-10', 800, '2026-05-10 23:30:00+00');  -- cron -> C's boundary
select set_config('app.nav_computed_for', :'tf', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value, created_at) values
  (:'tf', '2018-01-31', 60, '2026-08-01 12:00:00+00'),   -- imported only
  (:'tf', '2018-02-28', 65, '2026-08-01 12:00:00+00');   -- imported only, no cron row exists
select set_config('app.nav_computed_for', :'tg', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value, created_at) values
  (:'tg', '2026-07-01', 500, '2026-07-01 23:00:00+00'),  -- cron only -> G's boundary
  (:'tg', '2026-07-02', 510, '2026-07-03 01:00:00+00');  -- cron only, no imported row exists
select set_config('role', 'postgres', true);
-- E gets no nav_daily rows at all — that omission IS its fixture.

-- (Z) fixture pins — every (MTX)/(MRG)/(T) assertion below is a claim ABOUT these facts.
select is(
  (select count(*) from pfin.nav_daily where users_id = :'ta'::uuid), 3::bigint,
  '(z1) fixture pin: A carries exactly 3 rows (1 imported + 2 cron) — every A leg below assumes this shape'
);
select is(
  (select count(*) from pfin.nav_daily where users_id = :'tb'::uuid
     and created_at < nav_date + interval '7 days')::int, 1,
  '(z2) fixture pin: B has exactly ONE cron-shaped row by the classifier''s own predicate — its boundary is unambiguous'
);
select isnt(
  (select min(nav_date) from pfin.nav_daily where users_id = :'ta'::uuid and created_at < nav_date + interval '7 days'),
  (select min(nav_date) from pfin.nav_daily where users_id = :'tb'::uuid and created_at < nav_date + interval '7 days'),
  '(z3) fixture pin: A''s and B''s cron-shaped boundaries are DIFFERENT dates by construction — the premise leg (4) needs to be non-vacuous'
);

-- =====================================================================
-- (1) Z-INV — ZONE INVARIANCE, THE PROPERTY. A local digest helper (this file only;
--   _rls is created per-test by the \ir and rolls back with it) captures the FULL
--   three-column row as text under _rls.set_tenant, exactly the _rls.qa*_digest
--   idiom 062/067 use for their own zone legs.
-- =====================================================================
create or replace function _rls.qa220_boundary_digest(p_tenant uuid) returns text
  language plpgsql as $qd$
declare v text;
begin
  perform _rls.set_tenant(p_tenant);
  select coalesce(first_cron_checkpoint::text, '<null>') || '/' || has_cron_rows::text || '/' || has_imported_rows::text
    into v
  from pfin.fn_first_cron_checkpoint();
  perform set_config('role', 'postgres', true);
  return v;
end;
$qd$;

set local TimeZone = 'Pacific/Kiritimati';
select _rls.qa220_boundary_digest(:'ta'::uuid) as z_east \gset
set local TimeZone = 'Pacific/Midway';
select _rls.qa220_boundary_digest(:'ta'::uuid) as z_west \gset
reset TimeZone;
select is(
  :'z_east'::text, :'z_west'::text,
  '(Z-INV1) ⭐ ZONE-INVARIANCE MEASURED DIRECTLY: A''s full (first_cron_checkpoint, has_cron_rows, has_imported_rows) row is BYTE-IDENTICAL under Pacific/Kiritimati (UTC+14) and Pacific/Midway (UTC-11), 25 hours apart. This asserts the PROPERTY the migration header''s margin reasoning depends on, not a proxy for it'
);

-- (Z-INV2) INVERSION CONTROL — proves the digest/harness is not blind to zone, i.e. a
--   genuinely zone-dependent expression WOULD show up different under the same two
--   `set local TimeZone` calls used above. Reproduces the classifier's shape but with
--   the margin narrowed to a single day against a row placed so its created_at and
--   nav_date land on the same UTC calendar day but DIFFERENT local calendar days
--   under the two test zones — this is a scratch comparison, not 069 itself; 069 is
--   never modified or bypassed by this leg.
savepoint zone_inversion;
create table _rls.qa220_near_miss (created_at timestamptz, nav_date date);
insert into _rls.qa220_near_miss values ('2026-06-01 23:30:00+00', '2026-06-01');
set local TimeZone = 'Pacific/Kiritimati';
select (created_at::date <> nav_date) as v from _rls.qa220_near_miss \gset e_
set local TimeZone = 'Pacific/Midway';
select (created_at::date <> nav_date) as v from _rls.qa220_near_miss \gset w_
reset TimeZone;
select isnt(
  :'e_v'::boolean, :'w_v'::boolean,
  '(Z-INV2) ⭐ HARNESS HAS TEETH: a genuinely zone-dependent comparison (::date cast on the SAME near-miss row) DOES differ under the two extreme zones used at (Z-INV1) — proving that setup is capable of catching zone-dependence, not merely never exercising it. Without this control, (Z-INV1)''s green would be zone-BLINDNESS, not zone-independence'
);
rollback to savepoint zone_inversion;

-- =====================================================================
-- (2) MTX — THE FOUR-STATE MATRIX, all four, full row.
-- =====================================================================
-- (a) NO ROWS AT ALL — probed LAST-fixture-wise but here for matrix ordering; the
--     table already holds A/B/C/F/G's rows at this point in the transaction, so a
--     leaked/blended aggregate (broken RLS, or a stray cross-tenant predicate) would
--     surface here. THIS SAME ASSERTION DISCHARGES LEG (5) — cross-tenant gets the
--     empty-store answer, not an error and not another tenant's boundary; nothing
--     E-specific exists in the fixture for (5) to probe separately.
select _rls.set_tenant(:'te'::uuid);
select results_eq(
  $$ select first_cron_checkpoint, has_cron_rows, has_imported_rows from pfin.fn_first_cron_checkpoint() $$,
  $$ values (null::date, false, false) $$,
  '(MTX-a) ⭐ no rows at all -> (NULL, false, false), even with FIVE other tenants holding real rows in the same table — this leg IS leg (5)''s non-vacuous cross-tenant/fail-closed proof, not a separately-fixtured duplicate'
);
select set_config('role', 'postgres', true);

-- (b) IMPORTED ONLY, no cron yet — THE STATE A BARE `date` RETURN WOULD COLLAPSE INTO (a).
select _rls.set_tenant(:'tf'::uuid);
select results_eq(
  $$ select first_cron_checkpoint, has_cron_rows, has_imported_rows from pfin.fn_first_cron_checkpoint() $$,
  $$ values (null::date, false, true) $$,
  '(MTX-b) ⭐⭐ THE LEG THAT MATTERS MOST: imported-only -> (NULL, false, TRUE) — distinguishable from (a) ONLY by has_imported_rows. A scalar-date consumer would read this identically to "no data ever" and render "Collect data over time" over a fully-populated decade'
);
select set_config('role', 'postgres', true);

-- (c) CRON ONLY, no imported rows.
select _rls.set_tenant(:'tg'::uuid);
select results_eq(
  $$ select first_cron_checkpoint, has_cron_rows, has_imported_rows from pfin.fn_first_cron_checkpoint() $$,
  $$ values ('2026-07-01'::date, true, false) $$,
  '(MTX-c) cron only -> (min cron date, true, false) — no suppression, no disclosure downstream'
);
select set_config('role', 'postgres', true);

-- (d) MIXED — the everyday post-seeding-run state.
select _rls.set_tenant(:'ta'::uuid);
select results_eq(
  $$ select first_cron_checkpoint, has_cron_rows, has_imported_rows from pfin.fn_first_cron_checkpoint() $$,
  $$ values ('2026-06-01'::date, true, true) $$,
  '(MTX-d) mixed -> (first cron date, true, true) — A''s two cron rows correctly collapse to the EARLIER one (min), never the later or the imported date'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (3) MRG — THE MARGIN DISCRIMINATES, NON-VACUOUSLY. A's imported row (2015-12-31)
--   and cron rows (2026-06-xx) sit in the SAME store; the returned boundary must be
--   the CRON date, never the imported one — proving the two rows landed in different
--   buckets, not that the function ignores one of them entirely (a constant-false
--   has_imported_rows would also make (MTX-d)'s has_imported_rows fire wrong, but a
--   constant that happened to return the WRONG min would not be caught by (MTX-d)
--   alone without this explicit date check).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select first_cron_checkpoint from pfin.fn_first_cron_checkpoint()), '2026-06-01'::date,
  '(MRG1) the returned boundary is the CRON row''s date (2026-06-01), never the imported row''s (2015-12-31) — the two shapes classify into different buckets'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select has_cron_rows and has_imported_rows from pfin.fn_first_cron_checkpoint()),
  '(MRG2) ⭐ both has_cron_rows AND has_imported_rows are TRUE simultaneously on the SAME store — a fixture whose rows all looked alike (both classified the same way) could not distinguish a working predicate from one that returns a constant'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (4) T — TWO-TENANT, NON-VACUOUSLY.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select first_cron_checkpoint from pfin.fn_first_cron_checkpoint()), '2026-06-01'::date,
  '(T1) A''s call returns A''s own boundary (2026-06-01). POSITIVE leg — fires if A stops seeing its own rows'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select first_cron_checkpoint from pfin.fn_first_cron_checkpoint()), '2026-07-20'::date,
  '(T2) ⭐ THE NON-VACUITY THAT MAKES (T1) A TEST: the IDENTICAL call under B returns a DIFFERENT date (2026-07-20, not A''s 2026-06-01). A same-boundary fixture would pass here under a broken predicate that returned everyone''s boundary, or the wrong tenant''s'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (6) M — AAL2 BACKSTOP, BOTH LEGS. C declared mfa_policy='totp' above.
-- =====================================================================
select is(
  _rls.count_as(:'tc'::uuid, 'aal1',
    $$ select count(*) from pfin.fn_first_cron_checkpoint() where first_cron_checkpoint is null and not has_cron_rows and not has_imported_rows $$
  ), 1::bigint,
  '(M1) an aal1 session for a totp-declared tenant gets the empty-store answer (NULL/false/false), even though C genuinely has rows — the aal2 backstop, inherited through nav_daily''s RLS, fails this read closed'
);
select is(
  _rls.count_as(:'tc'::uuid, 'aal2',
    $$ select count(*) from pfin.fn_first_cron_checkpoint() where first_cron_checkpoint = '2026-05-10'::date and has_cron_rows and has_imported_rows $$
  ), 1::bigint,
  '(M2) ⭐ the POSITIVE leg that makes (M1) a test: the SAME tenant at aal2 gets their REAL boundary (2026-05-10, true, true) — without this, (M1) could pass vacuously against a policy that blinds every caller, not just aal1'
);

-- =====================================================================
-- (7) A — ACL.
-- =====================================================================
select ok(
  has_function_privilege('authenticated', 'pfin.fn_first_cron_checkpoint()', 'execute'),
  '(A1) authenticated HOLDS EXECUTE'
);
select ok(
  not has_function_privilege('public', 'pfin.fn_first_cron_checkpoint()', 'execute'),
  '(A2) LOAD-BEARING: PUBLIC does NOT — `create function` grants EXECUTE to PUBLIC by default, so the revoke is load-bearing and silent on removal'
);
select ok(
  not has_function_privilege('service_role', 'pfin.fn_first_cron_checkpoint()', 'execute'),
  '(A3) service_role does NOT hold EXECUTE — and structurally could not use it if it did: 054 gives service_role only a column-level select on (users_id, nav_date), and this function reads created_at. A grant here would produce a broken path, not a wider one (migration header''s own recorded reasoning)'
);

-- =====================================================================
-- (8) PST — CATALOG POSTURE, read DECLARATIVELY. Sec AMBER finding (2026-08-13):
--   the ACL legs above prove WHO may call this function, never WHAT POSTURE it
--   runs under. Behaviour alone cannot distinguish SECURITY INVOKER from a
--   DEFINER owned by a non-privileged role — a DEFINER swap would leave every
--   leg above green while detaching the read from nav_daily's RLS context and
--   the inherited aal2 backstop (the migration header's own POSTURE RATIONALE
--   section). Same idiom as 067's (ADR2) leg.
-- =====================================================================
select is(
  (select array[p.prosecdef::text, p.provolatile::text, array_to_string(p.proconfig, ',')]
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_first_cron_checkpoint'),
  array['false','s','search_path=""'],
  '(PST1) POSTURE, read DECLARATIVELY from the catalog: SECURITY INVOKER (prosecdef false), STABLE (provolatile s), search_path pinned empty. A DEFINER swap, a VOLATILE relaxation, or a dropped search_path pin would each leave every leg above green and only this one would catch it'
);

select * from finish();
rollback;

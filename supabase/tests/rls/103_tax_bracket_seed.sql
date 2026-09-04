-- =====================================================================
-- Per-Wave battery — pfin.fn_tax_bracket_seed_template() +
--   pfin.fn_provision_tax_brackets() + statement (3)'s explicit backfill
--   (SELF-260; V1.4; V1-SHIP-BLOCK; JOINT-REVIEW-MANDATORY per the
--   migration's own AC 5 — bracket rates and standard deductions are
--   financial-calculation inputs)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/103_tax_bracket_seed.sql (07871f6)
--   - pfin.fn_tax_bracket_seed_template() — SQL, IMMUTABLE, SECURITY
--       INVOKER, set search_path = '', reads NO TABLE (a constant VALUES
--       list with a name). THE SINGLE HOME of every seeded figure: three
--       schedules, flat rows (schedule scalars repeat per row).
--   - pfin.fn_provision_tax_brackets() returns integer — plpgsql, VOLATILE,
--       SECURITY INVOKER, set search_path = ''. Writes the CALLER's own
--       three schedules from the template, idempotent PER SCHEDULE KEY
--       (`on conflict (users_id, tax_year, schedule_type) do nothing`, the
--       row INSERT driven off that RETURNING set), takes NO TENANT
--       PARAMETER. Composes with 101's RLS + the 025 aal2 backstop.
--   - Statement (3), the migration's own bare backfill (no function wrapper)
--       — reaches users who already existed when 103 applied (ADR-057), from
--       auth.users cross-joined with the template, same idempotence key.
--       Realizes NO new column and NO new table; every schedule_id it writes
--       into tax_bracket_row is the SAME statement's own INSERT into
--       tax_bracket_schedule, so Decision 3 canonical #18's matched-tenant
--       fence is passed by construction, not by luck.
--   - THE FIGURES: federal_ordinary (2026, 7 rows, std ded 16100, top rate
--       0.37 @ 640600), federal_lt_cg (2026, 3 rows, std ded 0 — "takes no
--       deduction", not "unset"), california_ordinary (2025 — the FTB had
--       not published 2026 at authoring time — 10 rows, std ded 5706, a
--       10th bracket at floor 1000000 / rate 0.133 = the 12.3% FTB Schedule
--       X top rate plus the 1% R&TC 17043 Mental Health Services Tax, cited
--       separately in the migration header — E23). Every label states filing
--       status SINGLE (AC 6 / PM's A-6) and its own tax_year.
--
-- Prereqs exercised (already on the branch stack, applied before this file):
--   001 (pfin schema), 101 (SELF-259 — tax_bracket_schedule, tax_bracket_row,
--   both tables' RLS + the deferred set-fence trigger this file's BLOCK F
--   exercises for the first time on a real multi-row batch), 024/025 (the
--   aal2 backstop shape composed here, not independently re-tested — 101's
--   own battery already covers AAL-S/AAL-R on both tables; a caller with no
--   `pfin.user_settings` row reads as the aal-LESS / 'none' path, which is
--   why this file's fixtures insert no user_settings rows at all — probe 2
--   measured this on the real functions before this file was authored).
--
-- ⚠ THE BACKFILL-REACH LEG CANNOT OBSERVE "BEFORE 103" DIRECTLY — the real
--   statement (3) already ran, once, at migration-apply time, before this
--   file's own fixture users exist. BLOCK R (leg 2) and BLOCK I (leg 5)
--   instead re-run a BYTE-IDENTICAL copy of statement (3) inside THIS file's
--   own (never-committing) transaction — the only way to observe "reaches an
--   already-existing user" and "a second apply is a true no-op" both,
--   deterministically, against fixture users this file controls. The copy
--   targets auth.users UNFILTERED, exactly as the migration does; that is
--   safe here because every user already backfilled at real apply time is
--   already idempotent-skipped, and the whole file rolls back regardless.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from
--   _rls.tenant_a()/_rls.tenant_b()/_rls.tenant_c(). NO PII / NO real account
--   numbers / NO prod data. All inside one rolled-back transaction.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause, reused from 101/090/074):
--   every _rls.set_tenant(_aal) call happens at role=postgres and each block
--   restores role=postgres before the next.
--
-- pg_prove ONLY (never bare psql — a pgTAP plan under-run exits 0 there).
--   Verified on a scratch DB rebuilt from empty, sequential apply 001..099,
--   101, 103 (100/102 skipped — sibling-branch migrations touching neither
--   table). `supabase db reset` is mechanically banned and was not used.
--
--   plan(42): 8 template pins (T1-T8: AC 1/2, E1, E23 — total row count,
--   per-schedule (type, tax_year, std_ded, row_count) bag, universal
--   zero-floor, universal fraction bound, universal rate-monotonicity, the
--   CA top bracket, the three federal_lt_cg pairs, the federal_ordinary top
--   bracket) + 7 backfill reach (R1-R7: AC 7 — A/B each hold 3 schedules/20
--   rows, A cannot read B's schedules or rows, every B-owned row carries
--   users_id=B) + 4 new-user provisioning (N1-N2 the call and its no-op
--   repeat, plus the RLS-scoped read-back of both counts) + 2 unauthenticated
--   refusal (U1-U2: Sec F-2 — fn_provision_tax_brackets()'s fail-closed
--   `auth.uid() is null` guard RAISES, paired with a non-vacuous control that
--   the identical call succeeds once a tenant claim is set) + 9 the deferred
--   set fence's first real multi-row exercise (F1a-c pins on the SEEDED
--   California set itself; F2a-b non-monotone rate rejection; F3a-b nonzero
--   lowest-floor rejection; F4a-b the non-vacuous control) + 2 idempotency
--   (I1-I2: a second statement-(3) apply creates zero new schedules/rows) +
--   3 posture (P1-P2 both functions' full posture+ACL, P3 the pfin DEFINER
--   allowlist unchanged at exactly 3 names) + 6 labels (Sec V-2 — L1-L6 read
--   the STORED pfin.tax_bracket_schedule.schedule_label column, not the
--   template's discarded return value: L1 every stored label states SINGLE,
--   L2 the CA label states 2025/§17043/FLAT, L3 both federal labels cite
--   Rev. Proc. 2025-32, L4 every label is within its own 1..500 DDL bound,
--   L5 an exact-length anti-drift pin on A's CA label, L6 a dedicated leg on
--   C's signup-path provisioning) + 1 forward-looking absence proof for
--   SELF-262 (E1: no california_ordinary schedule at the CURRENT calendar
--   year) = 42.
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(42);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset

-- =====================================================================
-- BLOCK T (postgres — pure function call) — TEMPLATE PINS (AC 1/2, E1, E23).
--   fn_tax_bracket_seed_template() reads no table; every assertion below
--   calls it directly, the single home of every seeded figure.
-- =====================================================================
select is(
  (select count(*) from pfin.fn_tax_bracket_seed_template()),
  20::bigint,
  '(T1) fn_tax_bracket_seed_template() returns EXACTLY 20 rows total — RED if any schedule gained or lost a bracket'
);

select bag_eq(
  $$ select schedule_type, tax_year, standard_deduction, count(*)
       from pfin.fn_tax_bracket_seed_template()
      group by schedule_type, tax_year, standard_deduction $$,
  $$ values
      ('federal_ordinary'::pfin.tax_schedule_type_enum, 2026::smallint, 16100.0000::numeric, 7::bigint),
      ('federal_lt_cg'::pfin.tax_schedule_type_enum, 2026::smallint, 0.0000::numeric, 3::bigint),
      ('california_ordinary'::pfin.tax_schedule_type_enum, 2025::smallint, 5706.0000::numeric, 10::bigint) $$,
  '(T2) per-schedule (schedule_type, tax_year, standard_deduction, row_count): federal_ordinary 2026/16100/7, federal_lt_cg 2026/0/3, california_ordinary 2025/5706/10 — RED on any drift in year, deduction, or row count, per schedule'
);

select is(
  (select count(*) from (
     select schedule_type, min(bracket_floor) as lo
       from pfin.fn_tax_bracket_seed_template()
      group by schedule_type
   ) s where s.lo <> 0),
  0::bigint,
  '(T3) every schedule''s LOWEST bracket_floor is 0 — RED if any schedule''s first bracket does not start at zero, including federal_lt_cg whose first rate is itself 0'
);

select is(
  (select count(*) from pfin.fn_tax_bracket_seed_template()
    where not (bracket_rate >= 0 and bracket_rate <= 1)),
  0::bigint,
  '(T4) every seeded bracket_rate is a FRACTION between 0 and 1 inclusive (0 is legitimate — federal_lt_cg''s own 0% band) — RED if any rate were entered as a whole percent (22 instead of 0.22) or fell outside [0,1]'
);

select is(
  (select count(*) from (
     select schedule_type, bracket_rate,
            lag(bracket_rate) over (partition by schedule_type order by bracket_floor) as prev_rate
       from pfin.fn_tax_bracket_seed_template()
   ) s where s.prev_rate is not null and s.bracket_rate < s.prev_rate),
  0::bigint,
  '(T5) bracket_rate is NON-DECREASING in ascending bracket_floor order, within every schedule — RED if any two adjacent seeded brackets stepped down'
);

select results_eq(
  $$ select bracket_floor, bracket_rate from pfin.fn_tax_bracket_seed_template()
      where schedule_type = 'california_ordinary' order by bracket_floor desc limit 1 $$,
  $$ values (1000000.0000::numeric, 0.13300000::numeric) $$,
  '(T6) the california_ordinary TOP bracket is floor 1,000,000 / rate 0.133 — FTB Schedule X''s 12.3% top rate plus the 1% R&TC 17043 Mental Health Services Tax (E23), the one row this file does not trace to Schedule X alone'
);

select results_eq(
  $$ select bracket_floor, bracket_rate from pfin.fn_tax_bracket_seed_template()
      where schedule_type = 'federal_lt_cg' order by bracket_floor $$,
  $$ values (0.0000::numeric, 0.00000000::numeric),
            (49450.0000::numeric, 0.15000000::numeric),
            (545500.0000::numeric, 0.20000000::numeric) $$,
  '(T7) federal_lt_cg carries exactly the three published (floor, rate) pairs — 0/0%, 49,450/15%, 545,500/20% (IRS Rev. Proc. 2025-32 §3.03, All Other Individuals)'
);

select results_eq(
  $$ select bracket_floor, bracket_rate from pfin.fn_tax_bracket_seed_template()
      where schedule_type = 'federal_ordinary' order by bracket_floor desc limit 1 $$,
  $$ values (640600.0000::numeric, 0.37000000::numeric) $$,
  '(T8) federal_ordinary''s TOP bracket is floor 640,600 / rate 0.37 (IRS Rev. Proc. 2025-32 §3.01 Table 3, § 1(j)(2)(C))'
);

-- =====================================================================
-- BLOCK R (postgres fixture, then _rls verbs) — BACKFILL REACH (AC 7).
--   A and B are inserted into auth.users, then a BYTE-IDENTICAL copy of
--   statement (3) is applied once — the only way to observe "reaches an
--   already-existing user" deterministically inside this file's own txn.
--
--   ⚠ TRANSCRIBED COPY, NOT THE SHIPPED STATEMENT (Sec SELF-260 F-3). The
--   SQL below is retyped from the migration's own statement (3), not
--   executed FROM the migration file — a future edit to that statement
--   does NOT move this copy, and (R7) below (plus (I1)/(I2) at BLOCK I,
--   the same copy again) would keep asserting a shape that no longer
--   ships. PIN: statement (3) as authored in
--   supabase/migrations/103_tax_bracket_seed.sql at `8247778` (lines
--   609-634) hashes to md5 2cfb9421cb479908f76598abfd9149d4 — recompute
--   with `git show 8247778:supabase/migrations/103_tax_bracket_seed.sql
--   | sed -n '609,634p' | md5sum` (or `md5 -q` on macOS) before trusting
--   this copy still matches a later migration edit. No rewrite is
--   required by this pin alone — it is a tripwire for a human to notice,
--   not a mechanical fence pgTAP can run against a one-shot DDL statement.
-- =====================================================================
insert into auth.users (id) values (:'ta'), (:'tb');

with tpl as (
  select * from pfin.fn_tax_bracket_seed_template()
),
parent_src as (
  select distinct u.id as users_id, t.schedule_type, t.tax_year, t.standard_deduction,
                  t.schedule_label
    from auth.users u
   cross join tpl t
),
sched as (
  insert into pfin.tax_bracket_schedule
    (users_id, tax_year, schedule_type, schedule_label, standard_deduction)
  select p.users_id, p.tax_year, p.schedule_type, p.schedule_label, p.standard_deduction
    from parent_src p
   order by p.users_id, p.schedule_type
  on conflict (users_id, tax_year, schedule_type) do nothing
  returning id, users_id, tax_year, schedule_type
)
insert into pfin.tax_bracket_row
  (users_id, schedule_id, bracket_floor, bracket_rate)
select s.users_id, s.id, t.bracket_floor, t.bracket_rate
  from sched s
  join tpl  t
    on t.tax_year = s.tax_year
   and t.schedule_type = s.schedule_type
 order by s.id, t.bracket_floor;

select _rls.expect_owner_can_read('pfin.tax_bracket_schedule'::regclass, :'ta'::uuid, 3::bigint);
select _rls.expect_owner_can_read('pfin.tax_bracket_row'::regclass, :'ta'::uuid, 20::bigint);
select _rls.expect_owner_can_read('pfin.tax_bracket_schedule'::regclass, :'tb'::uuid, 3::bigint);
select _rls.expect_owner_can_read('pfin.tax_bracket_row'::regclass, :'tb'::uuid, 20::bigint);
select _rls.expect_cross_tenant_read_empty('pfin.tax_bracket_schedule'::regclass, :'tb'::uuid, :'ta'::uuid);
select _rls.expect_cross_tenant_read_empty('pfin.tax_bracket_row'::regclass, :'tb'::uuid, :'ta'::uuid);

select is(
  (select count(*) from pfin.tax_bracket_row r
     join pfin.tax_bracket_schedule s on s.id = r.schedule_id
    where s.users_id = :'tb' and r.users_id <> s.users_id),
  0::bigint,
  '(R7) every row of a B-owned schedule carries users_id = B — the backfill''s child users_id is the SAME expression that produced the parent, never a second lookup that could drift (Decision 3 canonical #18)'
);

-- =====================================================================
-- BLOCK N (authenticated C, a BRAND-NEW user) — SIGNUP-PATH PROVISIONING
--   (probe 2's pattern). fn_provision_tax_brackets() takes no user_settings
--   fixture: an aal-LESS caller reads as mfa_policy 'none' equivalent.
-- =====================================================================
insert into auth.users (id) values (:'tc');
select _rls.set_tenant(:'tc'::uuid);

select is(
  pfin.fn_provision_tax_brackets(),
  3,
  '(N1) fn_provision_tax_brackets() for a brand-new authenticated caller creates all 3 schedules and returns 3 (AC 7 signup path)'
);
select is(
  pfin.fn_provision_tax_brackets(),
  0,
  '(N2) the SAME caller''s second call is a true no-op per schedule key: returns 0 — not re-triggered by a repeat call'
);
select set_config('role', 'postgres', true);

select _rls.expect_owner_can_read('pfin.tax_bracket_schedule'::regclass, :'tc'::uuid, 3::bigint);
select _rls.expect_owner_can_read('pfin.tax_bracket_row'::regclass, :'tc'::uuid, 20::bigint);

-- =====================================================================
-- BLOCK U (Sec F-2) — fn_provision_tax_brackets() FAIL-CLOSED REFUSAL.
--   The function's own explicit guard (`auth.uid() is null`) had NO
--   watcher before this leg: (P2) below pins the EXECUTE ACL, a DIFFERENT
--   control that would still pass even if a future grant widened EXECUTE
--   to a broader role — the guard is what holds THEN.
-- =====================================================================
select set_config('role', 'postgres', true);
select set_config('request.jwt.claims', '', true);
savepoint sp_u1;
select throws_like(
  'select pfin.fn_provision_tax_brackets()',
  '%no authenticated caller%',
  '(U1) fn_provision_tax_brackets() with NO authenticated caller (auth.uid() is null) RAISES the function''s own fail-closed guard rather than falling through to a bare NOT NULL violation on users_id'
);
rollback to savepoint sp_u1;

select _rls.set_tenant(:'ta'::uuid);
select is(
  pfin.fn_provision_tax_brackets(),
  0,
  '(U2) CONTROL: the IDENTICAL call succeeds (returns 0, not an error) once request.jwt.claims carries a tenant — proves (U1) is a non-vacuous refusal, not a stub that always throws. A already holds all 3 schedules from BLOCK R''s backfill, so 0 is the correct per-key idempotent return'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK F (AC 3 — 101's deferred set fence, FIRST exercise on a real
--   multi-row batch). F1a-c pin the SEEDED california_ordinary set A
--   received from BLOCK R's backfill. F2/F3 stage synthetic multi-row
--   INSERTs on a FRESH schedule and force the fence with `set constraints
--   all immediate` (029/038/101 idiom); F4 is the non-vacuous control.
-- =====================================================================
select id as ca_sched_a from pfin.tax_bracket_schedule
  where users_id = :'ta' and schedule_type = 'california_ordinary' \gset

select is(
  (select count(*) from pfin.tax_bracket_row where schedule_id = :ca_sched_a),
  10::bigint,
  '(F1a) A''s BACKFILLED california_ordinary schedule carries exactly 10 rows — the SEEDED set the deferred fence accepted, not a synthetic one'
);
select is(
  (select min(bracket_floor) from pfin.tax_bracket_row where schedule_id = :ca_sched_a),
  0.0000::numeric,
  '(F1b) its lowest bracket_floor is 0'
);
select is(
  (select count(*) from (
     select bracket_rate, lag(bracket_rate) over (order by bracket_floor) as prev
       from pfin.tax_bracket_row where schedule_id = :ca_sched_a
   ) s where s.prev is not null and s.bracket_rate < s.prev),
  0::bigint,
  '(F1c) its rates are non-decreasing in floor order — leg B, verified against the SEEDED set itself'
);

select _rls.set_tenant(:'ta'::uuid);
insert into pfin.tax_bracket_schedule (tax_year, schedule_type, schedule_label, standard_deduction)
  values (2027, 'federal_ordinary',
          'QA synthetic fence-test schedule (BLOCK F) — not a seeded template row; excluded from BLOCK L''s label legs by tax_year',
          16100.00) returning id as sched_fence \gset

set constraints all deferred;
select lives_ok(
  format($$ insert into pfin.tax_bracket_row (schedule_id, bracket_floor, bracket_rate)
             values (%s, 0, 0.20), (%s, 50000, 0.10), (%s, 100000, 0.05) $$, :sched_fence, :sched_fence, :sched_fence),
  '(F2a) a SINGLE multi-row INSERT with DECREASING rates (0.20, 0.10, 0.05) succeeds as a statement — the deferred fence has not fired yet'
);
select throws_like(
  'set constraints all immediate',
  '%rate monotonicity%',
  '(F2b) SET CONSTRAINTS ALL IMMEDIATE forces the fence to fire and it REJECTS the non-monotone batch, AFTER the INSERT already returned successfully — the ORDER a BEFORE ROW trigger could not reproduce'
);
delete from pfin.tax_bracket_row where schedule_id = :sched_fence;
set constraints all deferred;

select lives_ok(
  format($$ insert into pfin.tax_bracket_row (schedule_id, bracket_floor, bracket_rate)
             values (%s, 500, 0.10), (%s, 1000, 0.20) $$, :sched_fence, :sched_fence),
  '(F3a) a MONOTONE multi-row INSERT (0.10 then 0.20) whose LOWEST floor is 500, not 0, succeeds as a statement — monotonicity alone cannot see this'
);
select throws_like(
  'set constraints all immediate',
  '%zero-floor%',
  '(F3b) SET CONSTRAINTS ALL IMMEDIATE REJECTS it at commit-equivalent time — leg A zero-floor, a genuinely separate control from leg B rate monotonicity'
);
delete from pfin.tax_bracket_row where schedule_id = :sched_fence;
set constraints all deferred;

select lives_ok(
  format($$ insert into pfin.tax_bracket_row (schedule_id, bracket_floor, bracket_rate)
             values (%s, 0, 0.10), (%s, 500, 0.20) $$, :sched_fence, :sched_fence),
  '(F4a) CONTROL: the same shape, monotone AND zero-floor, succeeds as a statement'
);
select lives_ok(
  'set constraints all immediate',
  '(F4b) CONTROL: SET CONSTRAINTS ALL IMMEDIATE now COMMITS cleanly — proves (F2b)/(F3b) are non-vacuous, the fence itself was the blocker'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK I (postgres — IDEMPOTENCY, leg 5). A second, byte-identical apply
--   of statement (3) — every user reachable by it (A, B, C, and any real
--   pre-existing user from the scratch DB build) already holds all three
--   schedules by this point, so it must create nothing.
--
--   ⚠ TRANSCRIBED COPY (Sec SELF-260 F-3) — same statement, same pin, as
--   BLOCK R above: md5 2cfb9421cb479908f76598abfd9149d4 of
--   supabase/migrations/103_tax_bracket_seed.sql lines 609-634 at
--   `8247778`. Not re-derived here; see BLOCK R's comment for the
--   recompute command.
-- =====================================================================
select (select count(*) from pfin.tax_bracket_schedule)::bigint as sched_before,
       (select count(*) from pfin.tax_bracket_row)::bigint as rows_before \gset

with tpl as (
  select * from pfin.fn_tax_bracket_seed_template()
),
parent_src as (
  select distinct u.id as users_id, t.schedule_type, t.tax_year, t.standard_deduction,
                  t.schedule_label
    from auth.users u
   cross join tpl t
),
sched as (
  insert into pfin.tax_bracket_schedule
    (users_id, tax_year, schedule_type, schedule_label, standard_deduction)
  select p.users_id, p.tax_year, p.schedule_type, p.schedule_label, p.standard_deduction
    from parent_src p
   order by p.users_id, p.schedule_type
  on conflict (users_id, tax_year, schedule_type) do nothing
  returning id, users_id, tax_year, schedule_type
)
insert into pfin.tax_bracket_row
  (users_id, schedule_id, bracket_floor, bracket_rate)
select s.users_id, s.id, t.bracket_floor, t.bracket_rate
  from sched s
  join tpl  t
    on t.tax_year = s.tax_year
   and t.schedule_type = s.schedule_type
 order by s.id, t.bracket_floor;

select is(
  (select count(*) from pfin.tax_bracket_schedule)::bigint,
  :sched_before::bigint,
  '(I1) re-running statement (3) a SECOND time (byte-identical copy) creates ZERO new schedules'
);
select is(
  (select count(*) from pfin.tax_bracket_row)::bigint,
  :rows_before::bigint,
  '(I2) the SAME second run creates ZERO new bracket rows — the child INSERT is truly driven off the parent''s (now-empty) RETURNING set'
);

-- =====================================================================
-- BLOCK P (postgres — pg_proc/pg_namespace catalog) — POSTURE PINS.
-- =====================================================================
select is(
  (select count(*)::bigint
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_tax_bracket_seed_template'
      and p.prosecdef = false
      and p.provolatile = 'i'
      and not has_function_privilege('public', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
      and not has_function_privilege('service_role', p.oid, 'EXECUTE')
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) cfg where cfg = 'search_path=""')),
  1::bigint,
  '(P1) fn_tax_bracket_seed_template(): SECURITY INVOKER, IMMUTABLE, search_path="", PUBLIC/anon/service_role EXECUTE all absent, authenticated EXECUTE present — count=1 means none of the seven predicates was lost'
);
select is(
  (select count(*)::bigint
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_provision_tax_brackets'
      and p.prosecdef = false
      and p.provolatile = 'v'
      and not has_function_privilege('public', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
      and not has_function_privilege('service_role', p.oid, 'EXECUTE')
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) cfg where cfg = 'search_path=""')),
  1::bigint,
  '(P2) fn_provision_tax_brackets(): SECURITY INVOKER, VOLATILE, search_path="", PUBLIC/anon/service_role EXECUTE all absent, authenticated EXECUTE present'
);
select is(
  (select array_agg(p.proname::text order by p.proname)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.prosecdef = true),
  array['fn_grant_creator_access', 'fn_reclass_history_insert', 'fn_refresh_updated_at']::text[],
  '(P3) pfin''s SECURITY DEFINER allowlist is UNCHANGED — still exactly these three names (ADR-011 Decision 9); neither new function added itself to it'
);

-- =====================================================================
-- BLOCK L (labels state the filing status — AC 6 / PM's A-6; Sec V-2).
--   Reads the STORED column pfin.tax_bracket_schedule.schedule_label
--   directly — NOT pfin.fn_tax_bracket_seed_template()'s return value,
--   which nothing downstream consumes. Covers A/B (BLOCK R's backfill)
--   AND C (BLOCK N's signup-path fn_provision_tax_brackets()), scoped to
--   tax_year in (2025, 2026) so BLOCK F's synthetic 2027 fence-test
--   schedule (which carries its own non-template label) is out of scope
--   by construction rather than by an extra predicate per leg.
-- =====================================================================
select is(
  (select count(*) from pfin.tax_bracket_schedule
     where users_id in (:'ta', :'tb', :'tc')
       and tax_year in (2025, 2026)
       and schedule_label not ilike '%single%'),
  0::bigint,
  '(L1) every STORED schedule_label (A/B''s backfill and C''s signup-path provisioning alike) states filing status SINGLE, case-insensitive — RED if any schedule''s PERSISTED label dropped that assumption, not just the template''s'
);
select is(
  (select count(*) from pfin.tax_bracket_schedule
     where users_id in (:'ta', :'tb', :'tc')
       and schedule_type = 'california_ordinary'
       and not (schedule_label like '%2025%'
            and schedule_label like '%§17043%'
            and schedule_label like '%FLAT%')),
  0::bigint,
  '(L2) every STORED california_ordinary label states its own year 2025, cites R&TC §17043, and states the threshold is FLAT — RED if a future edit regressed to Sec V-1''s false filing-status-moves claim or dropped the §17043 citation'
);
select is(
  (select count(*) from pfin.tax_bracket_schedule
     where users_id in (:'ta', :'tb', :'tc')
       and tax_year in (2025, 2026)
       and schedule_type in ('federal_ordinary', 'federal_lt_cg')
       and schedule_label not like '%Rev. Proc. 2025-32%'),
  0::bigint,
  '(L3) every STORED federal label (ordinary and long-term-capital-gains alike) cites Rev. Proc. 2025-32 — scoped to tax_year 2025/2026 so BLOCK F''s synthetic 2027 fence-test schedule is out of scope, same as (L1)/(L4)'
);
select is(
  (select count(*) from pfin.tax_bracket_schedule
     where users_id in (:'ta', :'tb', :'tc')
       and tax_year in (2025, 2026)
       and (length(schedule_label) < 1 or length(schedule_label) > 500)),
  0::bigint,
  '(L4) every STORED schedule_label falls within its own DDL bound, length 1..500 (tax_bracket_schedule_schedule_label_check) — RED if a future edit widened a label past the column''s own CHECK'
);
select is(
  (select length(schedule_label) from pfin.tax_bracket_schedule
     where users_id = :'ta' and schedule_type = 'california_ordinary' and tax_year = 2025),
  473,
  '(L5) A''s STORED california_ordinary label is EXACTLY 473 characters — an anti-drift pin on the composed V-1/E29 text (Architect measured 473 at `8247778`), RED on silent truncation or unnoticed expansion'
);
select is(
  (select count(*) from pfin.tax_bracket_schedule
     where users_id = :'tc' and schedule_label not ilike '%single%'),
  0::bigint,
  '(L6) C''s SIGNUP-PATH provisioning (fn_provision_tax_brackets, BLOCK N) independently stores the SINGLE-filer label on all 3 schedules too — a dedicated leg on the NEW-USER path, not folded into (L1), so a future regression that breaks only the provisioning writer (while the backfill writer still works) is attributed correctly'
);

-- =====================================================================
-- BLOCK E (forward-looking for SELF-262, E22) — the ABSENCE that fires the
--   prior-year fallback: no california_ordinary schedule at the CURRENT
--   calendar year. A leg that goes RED if a later migration seeds an EMPTY
--   current-year CA schedule "so the year exists" (the migration header's
--   rejected alternative (b) — that would suppress the fallback and render
--   a silent zero).
-- =====================================================================
select is(
  (select count(*) from pfin.tax_bracket_schedule
     where users_id = :'ta' and schedule_type = 'california_ordinary'
       and tax_year = extract(year from current_date)::smallint),
  0::bigint,
  '(E1) A holds NO california_ordinary schedule for the CURRENT calendar year — the absence is what SELF-262''s reader fallback (E22) fires on'
);

select * from finish();
rollback;

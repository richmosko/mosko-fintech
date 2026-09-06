-- =====================================================================
-- 114 — pfin.fn_regenerate_monthly_report(p_target_month) returns bigint
--   (SELF-366 E15 item 10; the Decision 2 `final -> superseded` transition at
--   108 item 6(ii)). THE ONLY user-reachable path that performs that
--   transition. By-state behaviour: `final` present -> supersede + open a new
--   draft (one transaction); `draft` present -> open it, INSERT NOTHING;
--   nothing present -> open a draft. Delegates the insert half to `113`, so
--   the INSERT shape (data_as_of, draft default, audit emission, race
--   handling) exists exactly once.
-- =====================================================================
-- QA-owned. Authors NO schema. Pairs with Architect's `114`. Depends on `108`,
-- `111` (transitively, via `113`) and `113` (calls it directly).
--
-- ⟦EXPECTED STACK⟧ `114`-applied. Below it the function does not exist and
-- every assertion is RED for that reason alone.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants (_rls.tenant_a()/
-- _b() plus battery-local tenant D, totp-enrolled, for the aal2 leg). No PII,
-- no real account numbers, no production data. Rolled-back txn; no
-- `supabase db reset`.
--
-- ⚠ LEG 4 (ATOMICITY) SUBSTITUTES THE PAIRING LIST'S OWN SUGGESTED MECHANISM,
-- DISCLOSED HERE RATHER THAN SILENTLY: the pairing list names "a target_month
-- that is not a month start" as the failure trigger, but that mechanism
-- CANNOT compose with an existing `final` row at that same month — 108's own
-- CHECK forbids ANY row, final or otherwise, from existing at a non-month-
-- start value, so there is nothing to supersede at an invalid month in the
-- first place. This leg instead forces the SAME failure POINT (the delegated
-- INSERT inside `113`) via a temporary test-only REVOKE of the INSERT grant
-- `authenticated` normally holds — restored immediately after use, the 054/
-- 107 test-only-grant idiom run in reverse (narrowing a real grant instead of
-- widening an absent one).
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

\set m_insufficient '%permission denied for table monthly_report%'
\set m_rls '%row-level security policy%'

select plan(27);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset
\set td '00000000-0000-0000-0000-00000000000d'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'td');
insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta', 'none'), (:'tb', 'none'), (:'td', 'totp');

-- =====================================================================
-- LEG 1 — REGENERATE AGAINST A `final` MONTH: the old row is superseded, a
-- new draft exists, the month holds exactly one of each, and the returned id
-- is the new draft's.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-01-01', '2026-01-31') returning report_id as m1_final \gset
update pfin.monthly_report set generation_status = 'final', rendered_payload = '{}'::jsonb,
  payload_schema_version = 1, generated_at = now(), commentary_disposition = 'skipped' where report_id = :m1_final;
select pfin.fn_regenerate_monthly_report('2026-01-01') as m1_draft \gset
select set_config('role', 'postgres', true);
select is(
  (select generation_status from pfin.monthly_report where report_id = :m1_final::bigint),
  'superseded',
  '(1a) the OLD final row is now `superseded`'
);
select ok(
  (select generation_status from pfin.monthly_report where report_id = :m1_draft::bigint) = 'draft',
  '(1b) a NEW `draft` row exists — the returned id'
);
select is(
  (select count(*)::int from pfin.monthly_report where target_month = '2026-01-01' and users_id = :'ta'::uuid),
  2,
  '(1c) NON-VACUOUS: exactly TWO rows for the month — one superseded, one draft'
);
select isnt(
  :m1_draft::bigint, :m1_final::bigint,
  '(1d) the returned id is the NEW draft''s, not the old final row''s'
);

-- =====================================================================
-- LEG 2 — REGENERATE AGAINST A `draft` MONTH INSERTS NOTHING (E15 item 11
-- (iii)) and returns the existing draft's id. Row count must be UNCHANGED,
-- not only that an id came back.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_open_monthly_report_draft('2026-02-01') as m2_draft \gset
select set_config('role', 'postgres', true);
select (select count(*)::int from pfin.audit_log where subject_table = 'pfin.monthly_report' and subject_id = :m2_draft::bigint) as m2_audit_before \gset
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*)::int from pfin.monthly_report where target_month = '2026-02-01' and users_id = :'ta'::uuid),
  1,
  '(2a) NON-VACUOUS PRECONDITION: exactly one draft row before regenerate is called'
);
select is(
  pfin.fn_regenerate_monthly_report('2026-02-01'),
  :m2_draft::bigint,
  '(2b) regenerate against the SAME draft month returns the SAME draft''s id'
);
select set_config('role', 'postgres', true);
select is(
  (select count(*)::int from pfin.monthly_report where target_month = '2026-02-01' and users_id = :'ta'::uuid),
  1,
  '(2c) NON-VACUOUS: row count is UNCHANGED at one — regenerating a draft inserts nothing'
);

-- =====================================================================
-- LEG 3 — REGENERATE AGAINST A MONTH WITH NO REPORT creates one draft and
-- nothing else.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_regenerate_monthly_report('2026-03-01') as m3_draft \gset
select set_config('role', 'postgres', true);
select is(
  (select count(*)::int from pfin.monthly_report where target_month = '2026-03-01' and users_id = :'ta'::uuid),
  1,
  '(3a) exactly ONE row exists — a fresh draft'
);
select is(
  (select generation_status from pfin.monthly_report where report_id = :m3_draft::bigint),
  'draft',
  '(3b) it is a `draft`'
);

-- =====================================================================
-- LEG 4 — ATOMICITY (see file header for the disclosed mechanism
-- substitution): force the DELEGATED insert to fail via a temporary
-- test-only REVOKE; the SUPERSEDE must not survive.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-04-01', '2026-04-30') returning report_id as m4_final \gset
update pfin.monthly_report set generation_status = 'final', rendered_payload = '{}'::jsonb,
  payload_schema_version = 1, generated_at = now(), commentary_disposition = 'skipped' where report_id = :m4_final;
select set_config('role', 'postgres', true);

revoke insert on pfin.monthly_report from authenticated;
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  $$ select pfin.fn_regenerate_monthly_report('2026-04-01') $$,
  :'m_insufficient',
  '(4a) with authenticated''s INSERT grant TEMPORARILY revoked, the delegated insert inside 113 fails at the ACL, and the WHOLE call throws — no exception handler in either function catches insufficient_privilege'
);
select set_config('role', 'postgres', true);
grant insert on pfin.monthly_report to authenticated;

select is(
  (select generation_status from pfin.monthly_report where report_id = :m4_final::bigint),
  'final',
  '(4b) THE CATCH CRITERION: the transition does NOT survive a failed regeneration — the old row is STILL `final`, not stuck at `superseded` with no replacement'
);
select is(
  (select count(*)::int from pfin.monthly_report where target_month = '2026-04-01' and users_id = :'ta'::uuid),
  1,
  '(4c) NON-VACUOUS: still exactly ONE row for the month — no orphan draft or superseded row was left behind by the aborted attempt'
);

-- =====================================================================
-- LEG 5 — EXACTLY ONE AUDIT ROW per successful regeneration (trigger source
-- on_demand, via the delegated 113 call); ZERO on the draft-month path
-- (LEG 2's month, since opening an existing draft writes nothing).
-- =====================================================================
select is(
  (select count(*)::int from pfin.audit_log where subject_table = 'pfin.monthly_report' and subject_id = :m1_draft::bigint),
  1,
  '(5a) exactly ONE audit row for LEG 1''s successful regeneration'
);
select is(
  (select trigger_source from pfin.audit_log where subject_table = 'pfin.monthly_report' and subject_id = :m1_draft::bigint),
  'on_demand',
  '(5b) NON-VACUOUS: its trigger_source is `on_demand`'
);
select is(
  (select count(*)::int from pfin.audit_log where subject_table = 'pfin.monthly_report' and subject_id = :m2_draft::bigint),
  :m2_audit_before::int,
  '(5c) ZERO NEW audit rows from LEG 2''s regenerate-a-draft call: the count for m2_draft is UNCHANGED from before that call (captured at :m2_audit_before, itself 1 — from the ORIGINAL fn_open_monthly_report_draft call) — regenerate-against-a-draft inserted nothing and audited nothing'
);

-- =====================================================================
-- LEG 6 — THREE REGENERATIONS OF ONE MONTH -> exactly one `final` at each
-- settled point, and exactly one `draft` in flight after the third call
-- (Sec D-5's three-not-two rule: two regenerations pass against a defective
-- index that only guards a two-column key).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_regenerate_monthly_report('2026-05-01') as m6_d1 \gset
update pfin.monthly_report set generation_status = 'final', rendered_payload = '{}'::jsonb,
  payload_schema_version = 1, generated_at = now(), commentary_disposition = 'skipped' where report_id = :m6_d1::bigint;
select set_config('role', 'postgres', true);
select is(
  (select count(*)::int from pfin.monthly_report where target_month = '2026-05-01' and users_id = :'ta'::uuid and generation_status = 'final'),
  1,
  '(6-settle-1) SETTLED POINT 1: exactly one `final` after the first regenerate-and-promote cycle'
);

select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_regenerate_monthly_report('2026-05-01') as m6_d2 \gset
update pfin.monthly_report set generation_status = 'final', rendered_payload = '{}'::jsonb,
  payload_schema_version = 1, generated_at = now(), commentary_disposition = 'skipped' where report_id = :m6_d2::bigint;
select set_config('role', 'postgres', true);
select is(
  (select count(*)::int from pfin.monthly_report where target_month = '2026-05-01' and users_id = :'ta'::uuid and generation_status = 'final'),
  1,
  '(6-settle-2) SETTLED POINT 2: STILL exactly one `final` after the SECOND cycle — the pre-existing 2026 (row-1) index-style leg 108 (3a)/(3b) already proved 108''s index; this leg re-proves it through THIS function''s own call path'
);

select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_regenerate_monthly_report('2026-05-01') as m6_d3 \gset
select set_config('role', 'postgres', true);
select is(
  (select count(*)::int from pfin.monthly_report where target_month = '2026-05-01' and users_id = :'ta'::uuid),
  3,
  '(6d) THREE REGENERATIONS -> THREE ROWS TOTAL for the month'
);
select is(
  (select count(*)::int from pfin.monthly_report where target_month = '2026-05-01' and users_id = :'ta'::uuid and generation_status = 'draft'),
  1,
  '(6e) NON-VACUOUS, THE THREE-NOT-TWO CHECK: exactly ONE `draft` in flight after the third call (m6_d3, not yet promoted) — a defective two-row-tolerant index could pass at two regenerations and only fail here'
);
select is(
  (select count(*)::int from pfin.monthly_report where target_month = '2026-05-01' and users_id = :'ta'::uuid and generation_status = 'superseded'),
  2,
  '(6f) and exactly TWO `superseded` rows (m6_d1, m6_d2''s promoted finals, both since superseded)'
);

-- =====================================================================
-- LEG 7 — CROSS-TENANT: tenant B cannot supersede tenant A's `final` row;
-- A's row is asserted STILL final afterwards.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-06-01', '2026-06-30') returning report_id as m7_a_final \gset
update pfin.monthly_report set generation_status = 'final', rendered_payload = '{}'::jsonb,
  payload_schema_version = 1, generated_at = now(), commentary_disposition = 'skipped' where report_id = :m7_a_final;
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'tb'::uuid);
select pfin.fn_regenerate_monthly_report('2026-06-01') as m7_b \gset
select set_config('role', 'postgres', true);
select is(
  (select generation_status from pfin.monthly_report where report_id = :m7_a_final::bigint),
  'final',
  '(7a) tenant A''s row is STILL `final` — B''s call could not see it (RLS-scoped), so it never reached the transition'
);
select ok(
  (select users_id from pfin.monthly_report where report_id = :m7_b::bigint) = :'tb'::uuid,
  '(7b) NON-VACUOUS: B''s own returned row belongs to B (its own separate draft for the same calendar month, per 113''s own cross-tenant shape) — B was not silently refused into nothing'
);

-- =====================================================================
-- LEG 8 — aal2 AS A SEPARATE LEG FROM CROSS-TENANT (Sec F-9): a totp-enrolled
-- caller at a below-aal2 JWT is refused by the SAME raw RLS mechanism as
-- 113's own aal2 leg (no bespoke message in this function either).
-- =====================================================================
select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-07-01', '2026-07-31') returning report_id as m8_d_final \gset
update pfin.monthly_report set generation_status = 'final', rendered_payload = '{}'::jsonb,
  payload_schema_version = 1, generated_at = now(), commentary_disposition = 'skipped' where report_id = :m8_d_final;
select set_config('role', 'postgres', true);

select _rls.set_tenant_aal(:'td'::uuid, 'aal1');
select throws_like(
  $$ select pfin.fn_regenerate_monthly_report('2026-07-01') $$,
  :'m_rls',
  '(8a) totp-enrolled tenant D at aal1 -> refused: the SELECTs for draft/final see nothing under the aal2 backstop, so it falls to the delegate''s INSERT, which the INSERT policy''s own aal2 WITH CHECK refuses'
);
select set_config('role', 'postgres', true);
select is(
  (select generation_status from pfin.monthly_report where report_id = :m8_d_final::bigint),
  'final',
  '(8b) NON-VACUOUS: tenant D''s final row is UNCHANGED by the refused call'
);

-- =====================================================================
-- LEG 9 — IT CANNOT WRITE `final`: the new row is a `draft`, and the ONLY
-- status this function itself ever writes is `superseded`.
-- =====================================================================
select ok(
  (select generation_status from pfin.monthly_report where report_id = :m1_draft::bigint) = 'draft',
  '(9a) BEHAVIOURAL (rides LEG 1''s fixture): the row this function inserts is `draft`, never `final`'
);
select ok(
  (with body as (
     select lower(pg_get_functiondef(p.oid)) as src
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'pfin' and p.proname = 'fn_regenerate_monthly_report'
   )
   select src !~ $r$set\s+generation_status\s*=\s*'final'$r$
      and src ~ $r$set\s+generation_status\s*=\s*'superseded'$r$
     from body),
  '(9b) STRUCTURAL: this function''s body contains NO `set generation_status = ''final''` assignment anywhere, and DOES contain exactly the `= ''superseded''` write — it is structurally incapable of writing `final` itself (the draft it returns comes from delegating to 113, an INSERT-defaulted status, never a `generation_status` assignment in THIS function''s own text)'
);

-- =====================================================================
-- LEG 10 — STANDING: no rolbypassrls role (service_role, by name) holds
-- EXECUTE on this function.
-- =====================================================================
select ok(
  not has_function_privilege('service_role', 'pfin.fn_regenerate_monthly_report(date)'::regprocedure, 'EXECUTE'),
  '(10) service_role holds NO EXECUTE on fn_regenerate_monthly_report'
);

select * from finish();
rollback;

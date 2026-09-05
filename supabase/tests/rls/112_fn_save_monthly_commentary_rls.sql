-- =====================================================================
-- 112 — pfin.fn_save_monthly_commentary(p_target_month, p_cash, p_bonds,
--   p_marketable_securities, p_alternatives) (SELF-355 AC 5). The §2.6.2
--   commentary WRITE path — RT-11. Replace-all onto the caller's LIVE DRAFT
--   for one month; the FIRST statement (SELECT ... FOR UPDATE, filtered on
--   generation_status = 'draft') IS the tenant fence AND the aal2 gate,
--   because it runs under SECURITY INVOKER through 108's own RLS policies.
-- =====================================================================
-- QA-owned. Authors NO schema. Pairs with Architect's `112`. Depends on `108`.
--
-- ⟦EXPECTED STACK⟧ `112`-applied. Below it the function does not exist and
-- every assertion is RED for that reason alone.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants (_rls.tenant_a()/
-- _b() plus battery-local tenant D, totp-enrolled, for the aal2 leg). No PII,
-- no real account numbers, no production data. Rolled-back txn; no
-- `supabase db reset`.
--
-- ⚠ TWO MESSAGES, AND WHICH FIRES WHERE (read from the function body, not
-- guessed): the lock SELECT filters `generation_status = 'draft'` AND is
-- itself RLS-scoped. So "no row visible under my own RLS" (cross-tenant, a
-- below-aal2 session, or genuinely no report) and "a row exists in MY OWN
-- scope but is final/superseded" are DISTINGUISHABLE ONLY BECAUSE the
-- function's own diagnostic second read is ALSO RLS-scoped: a cross-tenant or
-- below-aal2 caller sees NOTHING on either read (m_no_report fires), while an
-- owner at the right aal sees their own final/superseded row on the second
-- read (m_not_draft fires, naming the actual status). Legs 1/2 vs leg 3 below
-- are pinned to the message this actually produces, not to the message that
-- would be "nicer."
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

\set m_no_report '%no monthly report exists for%'
\set m_not_draft '%writable only inside the DRAFT window%'
\set m_len '%monthly_report_commentary_cash_len%'

select plan(21);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset
\set td '00000000-0000-0000-0000-00000000000d'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'td');
insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta', 'none'), (:'tb', 'none'), (:'td', 'totp');

-- =====================================================================
-- LEG 1 — CROSS-TENANT: tenant B calls for a month tenant A owns -> refused,
-- and tenant A's row is UNCHANGED afterwards (the second half this leg exists
-- to catch — a refusal that still wrote would pass a message-only check).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-01-01', '2026-01-31') returning report_id as d1 \gset
update pfin.monthly_report set commentary_cash = 'A-crosstenant-original' where report_id = :d1;

select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select throws_like(
  $$ select pfin.fn_save_monthly_commentary('2026-01-01', 'forged', 'forged', 'forged', 'forged') $$,
  :'m_no_report',
  '(1a) tenant B calling for tenant A''s month -> refused: B''s own RLS-scoped read (lock AND diagnostic) sees NOTHING for that month, so the function cannot even tell the caller a report exists'
);
select set_config('role', 'postgres', true);
select is(
  (select commentary_cash from pfin.monthly_report where report_id = :d1),
  'A-crosstenant-original',
  '(1b) NON-VACUOUS, THE SECOND HALF: tenant A''s row is UNCHANGED after B''s refused call — a refusal that still wrote would pass (1a) alone'
);

-- =====================================================================
-- LEG 2 — aal2 AS A SEPARATE LEG FROM CROSS-TENANT (Sec F-9): a totp-enrolled
-- caller with a below-aal2 JWT is refused BY FINDING NO ROW TO LOCK, so the
-- SAME m_no_report message fires as leg 1 — not a bespoke aal2 message. The
-- pairing list's own warning: assert THIS path's message, not the policy's.
-- =====================================================================
-- SETUP at aal2 (tenant D is totp-enrolled, so a plain set_tenant with NO aal
-- claim reads as below-aal2 under the 025 backstop and would refuse the
-- fixture's OWN setup UPDATE — use set_tenant_aal('aal2') for setup, and
-- switch to aal1 only for the actual refusal call below).
select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-02-01', '2026-02-28') returning report_id as d2 \gset
update pfin.monthly_report set commentary_cash = 'D-aal2-original' where report_id = :d2;
select set_config('role', 'postgres', true);

select _rls.set_tenant_aal(:'td'::uuid, 'aal1');
select throws_like(
  $$ select pfin.fn_save_monthly_commentary('2026-02-01', 'forged', 'forged', 'forged', 'forged') $$,
  :'m_no_report',
  '(2a) totp-enrolled tenant D at aal1 (below the 025 step-up) -> refused with the SAME m_no_report message as cross-tenant: the aal2 clause gates through the lock statement''s own RLS, not through a bespoke aal2 error in this function'
);
select set_config('role', 'postgres', true);
select is(
  (select commentary_cash from pfin.monthly_report where report_id = :d2),
  'D-aal2-original',
  '(2b) NON-VACUOUS: tenant D''s row is UNCHANGED after the below-aal2 refused call'
);

-- =====================================================================
-- LEG 3 — DRAFT WINDOW: the same call against a `final` month refused, and
-- against a `superseded` month refused; the owner's own row is asserted
-- unchanged in both cases. Here the OWNER's own diagnostic read DOES see the
-- row (right tenant, right aal), so the message names the actual status.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-03-01', '2026-03-31') returning report_id as d3f \gset
update pfin.monthly_report set commentary_cash = 'A-final-original' where report_id = :d3f;
update pfin.monthly_report set generation_status = 'final', rendered_payload = '{}'::jsonb,
  payload_schema_version = 1, generated_at = now(), commentary_disposition = 'skipped' where report_id = :d3f;

insert into pfin.monthly_report (target_month, data_as_of) values ('2026-04-01', '2026-04-30') returning report_id as d3s \gset
update pfin.monthly_report set commentary_cash = 'A-superseded-original' where report_id = :d3s;
update pfin.monthly_report set generation_status = 'final', rendered_payload = '{}'::jsonb,
  payload_schema_version = 1, generated_at = now(), commentary_disposition = 'skipped' where report_id = :d3s;
update pfin.monthly_report set generation_status = 'superseded' where report_id = :d3s;

select throws_like(
  $$ select pfin.fn_save_monthly_commentary('2026-03-01', 'forged', 'forged', 'forged', 'forged') $$,
  :'m_not_draft',
  '(3a) against a `final` month -> refused, naming the actual status (the owner CAN see it — this is not the leg-1/2 message)'
);
select throws_like(
  $$ select pfin.fn_save_monthly_commentary('2026-04-01', 'forged', 'forged', 'forged', 'forged') $$,
  :'m_not_draft',
  '(3b) against a `superseded` month -> refused, same message family'
);
select set_config('role', 'postgres', true);
select is(
  (select commentary_cash from pfin.monthly_report where report_id = :d3f),
  'A-final-original',
  '(3c) NON-VACUOUS: the owner''s own `final` row is UNCHANGED'
);
select is(
  (select commentary_cash from pfin.monthly_report where report_id = :d3s),
  'A-superseded-original',
  '(3d) NON-VACUOUS: the owner''s own `superseded` row is UNCHANGED'
);

-- =====================================================================
-- LEG 4 — REPLACE-ALL IS LITERAL: save four values, then save with two of
-- them empty -> the two are now empty, NOT left at their old values.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-05-01', '2026-05-31') returning report_id as d4 \gset
select is(
  pfin.fn_save_monthly_commentary('2026-05-01', 'C1', 'B1', 'S1', 'Alt1'),
  :d4::bigint,
  '(4a) first save writes all four columns and returns the row it wrote'
);
select set_config('role', 'postgres', true);
select ok(
  (select commentary_cash = 'C1' and commentary_bonds = 'B1'
      and commentary_marketable_securities = 'S1' and commentary_alternatives = 'Alt1'
     from pfin.monthly_report where report_id = :d4),
  '(4b) NON-VACUOUS: all four columns hold the FIRST call''s values'
);
select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_save_monthly_commentary('2026-05-01', 'C1', '', 'S1', '');
select set_config('role', 'postgres', true);
select ok(
  (select commentary_cash = 'C1' and commentary_bonds = '' and commentary_marketable_securities = 'S1' and commentary_alternatives = ''
     from pfin.monthly_report where report_id = :d4),
  '(4c) REPLACE-ALL IS LITERAL: bonds and alternatives are now EMPTY STRINGS, not left at ''B1''/''Alt1'' — there is no notion of "unchanged" in this function'
);

-- =====================================================================
-- LEG 5 — commentary_disposition becomes 'authored' on a successful save,
-- AND ALSO when all four arguments are empty (the leg that fails against an
-- implementation that only sets the disposition when something was written).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-06-01', '2026-06-30') returning report_id as d5 \gset
select is(
  (select commentary_disposition from pfin.monthly_report where report_id = :d5),
  null,
  '(5a) NON-VACUOUS PRECONDITION: commentary_disposition starts NULL (neither authored nor skipped)'
);
select pfin.fn_save_monthly_commentary('2026-06-01', '', '', '', '');
select set_config('role', 'postgres', true);
select is(
  (select commentary_disposition from pfin.monthly_report where report_id = :d5),
  'authored',
  '(5b) FOUR EMPTY STRINGS ARE A LEGITIMATE AUTHORED STATE: disposition is ''authored'', not left NULL and not ''skipped'' — the entire reason this column exists is to distinguish this from the skip, which is not writable from this function'
);

-- =====================================================================
-- LEG 6 — LENGTH, THE RULED NUMBERS: a 4,000-code-point body saves; 4,001 is
-- refused (23514, this function's own CHECK-through-DB layer) when submitted
-- DIRECTLY through PostgREST, not only 400-ed by the app.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-07-01', '2026-07-31') returning report_id as d6 \gset
select throws_like(
  format($$ select pfin.fn_save_monthly_commentary('2026-07-01', %L, '', '', '') $$, repeat('x', 4001)),
  :'m_len',
  '(6a) 4001 plain-ASCII characters -> refused by 108''s CHECK, propagated UNMODIFIED through this function (no second bound is applied here)'
);
select lives_ok(
  format($$ select pfin.fn_save_monthly_commentary('2026-07-01', %L, '', '', '') $$, repeat('x', 4000)),
  '(6b) NON-VACUOUS: exactly 4000 characters is accepted'
);

-- =====================================================================
-- LEG 6b — THE UNIT LEG (fails if anyone reverts to `.length`): a body of
-- 3,996 ASCII + 4 astral characters is 4,000 CODE POINTS / 4,004 UTF-16
-- units. A battery that only tests ASCII cannot tell the two units apart —
-- this is ACCEPTED, proving the DB bound counts code points.
-- =====================================================================
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-08-01', '2026-08-31') returning report_id as d6b \gset
select lives_ok(
  format($$ select pfin.fn_save_monthly_commentary('2026-08-01', %L, '', '', '') $$, repeat('x', 3996) || repeat('😀', 4)),
  '(6c) 3996 ASCII + 4 astral characters = 4000 CODE POINTS (4004 UTF-16 units) -> ACCEPTED — a `.length`-based mirror would compute 4004 and wrongly reject this'
);
select throws_like(
  format($$ select pfin.fn_save_monthly_commentary('2026-08-01', %L, '', '', '') $$, repeat('x', 3996) || repeat('😀', 5)),
  :'m_len',
  '(6d) DISCLOSED EXTRA, BEYOND THE PAIRING LIST: the same mix one astral character over (4001 code points) is refused by the SAME CHECK — confirms the boundary is still enforced in code points on the mixed-content side too, not merely a coincidence of the pure-ASCII legs'
);

-- =====================================================================
-- LEG 6c — NEWLINES: this leg documents a DEPENDENCY, not a defect (see the
-- migration's own FINDING). A body of 4000 `\n`-separated code points is
-- accepted; the SAME logical body with `\r\n` line endings is refused once
-- the extra `\r` pushes the code-point count over the bound.
-- =====================================================================
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-09-01', '2026-09-30') returning report_id as d6c \gset
select lives_ok(
  format($$ select pfin.fn_save_monthly_commentary('2026-09-01', %L, '', '', '') $$, repeat('a', 1999) || E'\n' || repeat('a', 2000)),
  '(6e) 1999 + 1 (\n) + 2000 = 4000 code points, LF-separated -> ACCEPTED'
);
select throws_like(
  format($$ select pfin.fn_save_monthly_commentary('2026-09-01', %L, '', '', '') $$, repeat('a', 1999) || E'\r\n' || repeat('a', 2000)),
  :'m_len',
  '(6f) THE DEPENDENCY, NOT A DEFECT: the IDENTICAL logical body with CRLF line endings is 1999 + 2 (\r\n) + 2000 = 4001 code points -> REFUSED. This is what the migration''s FINDING names: the N-5 equality depends on the CLIENT normalizing \r\n -> \n before counting, which this function deliberately does not do (rewriting stored text would trade a visible refusal for an invisible mutation)'
);

-- =====================================================================
-- LEG 7 — RETURN VALUE: the returned report_id is the row that changed.
-- =====================================================================
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-10-01', '2026-10-31') returning report_id as d7 \gset
select is(
  pfin.fn_save_monthly_commentary('2026-10-01', 'ret-check', '', '', ''),
  :d7::bigint,
  '(7) the returned report_id equals the row this call actually changed'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 8 — STANDING: no rolbypassrls role (service_role, by name) holds
-- EXECUTE on this function — RLS is the ONLY thing scoping the row it locks
-- and updates, so a bypass-RLS caller with EXECUTE would have the entire
-- perimeter, not the weakest fence.
-- =====================================================================
select ok(
  not has_function_privilege('service_role', 'pfin.fn_save_monthly_commentary(date,text,text,text,text)'::regprocedure, 'EXECUTE'),
  '(8) service_role holds NO EXECUTE on fn_save_monthly_commentary — RLS is the only fence this function has, so a bypass-RLS EXECUTE grant would be the entire perimeter'
);

select * from finish();
rollback;

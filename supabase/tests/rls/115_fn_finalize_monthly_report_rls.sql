-- =====================================================================
-- 115 — pfin.fn_finalize_monthly_report(p_target_month, p_commentary_disposition)
--   returns bigint (SELF-356 §2.6.2.c; A10 AC item 6). THE P4 FREEZE POINT: the
--   draft -> final transition. Writes the disposition FIRST (still draft, so
--   110 sees it when composing), then composes through 110, asserts the
--   composition echoes the LOCKED row (Finding 4), and freezes payload +
--   version + generated_at + owner_header_at_generation + generation_status
--   in ONE further UPDATE — all inside ONE transaction, so a half-finalized
--   report cannot exist. No audit row (named alternative, not an omission —
--   the row itself is the record, same reasoning as 114's sibling transition).
-- =====================================================================
-- QA-owned. Authors NO schema. Pairs with Architect's `115`. Depends on `108`,
-- `110` (fn_render_monthly_report) and `106` (pfin.owner_identification).
--
-- ⟦EXPECTED STACK⟧ `115`-applied. Below it the function does not exist and
-- every assertion is RED for that reason alone.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants (_rls.tenant_a()/
-- _b() plus battery-local tenant D, totp-enrolled, for the aal2 leg). No PII,
-- no real account numbers, no production data. Rolled-back txn; no
-- `supabase db reset`.
--
-- ⚠ aal2 REFUSAL HERE IS NOT A RAW RLS VIOLATION, UNLIKE 113/114: this
-- function's ONLY failure mode for "no visible draft" (cross-tenant, below-
-- aal2, or genuinely absent) is its OWN "no live draft for that month"
-- message — the SELECT that resolves the draft is a plain filtered read, not
-- an INSERT/UPDATE whose WITH CHECK could raise a bespoke RLS error, so aal2
-- and cross-tenant share ONE message family here (both leave v_report_id
-- null), unlike 113 where the code path falls through to an INSERT.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

\set m_no_draft '%no live draft for that month%'
\set m_vocab '%must be ''authored'' or ''skipped''%'
\set m_one_transition '%admits exactly ONE transition%'

select plan(32);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset
\set td '00000000-0000-0000-0000-00000000000d'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'td');
insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta', 'none'), (:'tb', 'none'), (:'td', 'totp');

-- Minimal manual-account fixtures per tenant (110's own precedent) so
-- fn_render_monthly_report composes a genuinely non-empty payload.
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'A-acct', 'depository', 'household', 'taxable') returning account_id as ta_acct \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'B-acct', 'depository', 'household', 'taxable') returning account_id as tb_acct \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'td', 'D-acct', 'depository', 'household', 'taxable') returning account_id as td_acct \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type)
  values (:ta_acct, '2026-01-01', 1000, 'setup', 'opening balance', 'acct_setup');
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type)
  values (:tb_acct, '2026-01-01', 2000, 'setup', 'opening balance', 'acct_setup');
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type)
  values (:td_acct, '2026-01-01', 3000, 'setup', 'opening balance', 'acct_setup');

-- =====================================================================
-- LEG 1 — FINALIZE A DRAFT: the row is `final`, rendered_payload NOT NULL,
-- and the payload's OWN echoed source_report_id equals the returned id (the
-- echo half is the leg — mere non-NULL passes while being about another row).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_open_monthly_report_draft('2026-01-01') as d1 \gset
select pfin.fn_finalize_monthly_report('2026-01-01', 'skipped') as d1_ret \gset
select set_config('role', 'postgres', true);
select is(:d1_ret::bigint, :d1::bigint, '(1a) the returned id equals the draft''s report_id');
select is(
  (select generation_status from pfin.monthly_report where report_id = :d1::bigint),
  'final',
  '(1b) the row is now `final`'
);
select ok(
  (select rendered_payload from pfin.monthly_report where report_id = :d1::bigint) is not null,
  '(1c) rendered_payload is NOT NULL'
);
select is(
  (select (rendered_payload -> 'sections' -> 'rebalancing_targets' ->> 'source_report_id')::bigint from pfin.monthly_report where report_id = :d1::bigint),
  :d1::bigint,
  '(1d) THE ECHO HALF: the frozen payload''s OWN source_report_id equals the row it is stored on — not merely present, but ABOUT this row'
);

-- =====================================================================
-- LEG 2 — FINALIZE TWICE: the second call is REFUSED (no live draft
-- remains), and the row is UNCHANGED — generated_at did not move.
-- =====================================================================
select (select generated_at from pfin.monthly_report where report_id = :d1::bigint) as d1_gen_at \gset
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  $$ select pfin.fn_finalize_monthly_report('2026-01-01', 'authored') $$,
  :'m_no_draft',
  '(2a) finalizing the SAME month a second time is refused — no live draft remains'
);
select set_config('role', 'postgres', true);
select is(
  (select generated_at from pfin.monthly_report where report_id = :d1::bigint),
  :'d1_gen_at'::timestamptz,
  '(2b) NON-VACUOUS: generated_at did NOT move — the row is genuinely unchanged, not merely "an error was raised"'
);

-- =====================================================================
-- LEG 3 — FINALIZE A `final` MONTH refused (reuses LEG 1/2's month, already
-- proven above at (2a)). FINALIZE A `superseded` MONTH refused separately —
-- two legs because they fail at DIFFERENT fences and one leg proves one.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_open_monthly_report_draft('2026-02-01') as d3 \gset
select pfin.fn_finalize_monthly_report('2026-02-01', 'skipped');
select set_config('role', 'postgres', true);
update pfin.monthly_report set generation_status = 'superseded' where report_id = :d3::bigint;
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  $$ select pfin.fn_finalize_monthly_report('2026-02-01', 'authored') $$,
  :'m_no_draft',
  '(3) finalizing a `superseded` month is refused'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 4 — CROSS-TENANT: tenant B finalizing tenant A's month affects ZERO
-- rows and A's report is STILL `draft` afterwards.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_open_monthly_report_draft('2026-03-01') as d4 \gset
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select throws_like(
  $$ select pfin.fn_finalize_monthly_report('2026-03-01', 'authored') $$,
  :'m_no_draft',
  '(4a) tenant B finalizing tenant A''s month is refused — B''s own RLS-scoped read sees no draft there'
);
select set_config('role', 'postgres', true);
select is(
  (select generation_status from pfin.monthly_report where report_id = :d4::bigint),
  'draft',
  '(4b) NON-VACUOUS: tenant A''s report is STILL `draft` afterward'
);

-- =====================================================================
-- LEG 5 — aal2 AS A SEPARATE LEG FROM CROSS-TENANT (Sec F-9): a totp-enrolled
-- caller at a below-aal2 JWT is refused by the SAME "no live draft" message
-- (the SELECT that resolves the draft finds nothing under the aal2 backstop).
-- =====================================================================
select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
select pfin.fn_open_monthly_report_draft('2026-04-01') as d5 \gset
select set_config('role', 'postgres', true);
select _rls.set_tenant_aal(:'td'::uuid, 'aal1');
select throws_like(
  $$ select pfin.fn_finalize_monthly_report('2026-04-01', 'authored') $$,
  :'m_no_draft',
  '(5a) totp-enrolled tenant D at aal1 -> refused with the SAME message family'
);
select set_config('role', 'postgres', true);
select is(
  (select generation_status from pfin.monthly_report where report_id = :d5::bigint),
  'draft',
  '(5b) NON-VACUOUS: tenant D''s report is STILL `draft` afterward'
);

-- =====================================================================
-- LEG 6 — ATOMICITY: a transaction that finalizes and then ROLLS BACK leaves
-- the row `draft` with rendered_payload NULL, generated_at NULL, AND the
-- disposition NULL — the third is what catches the two-UPDATE shape leaking
-- a committed half (the disposition write is the FIRST of the two).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_open_monthly_report_draft('2026-05-01') as d6 \gset
savepoint sp_finalize_rollback;
select pfin.fn_finalize_monthly_report('2026-05-01', 'authored');
select set_config('role', 'postgres', true);
select is(
  (select generation_status from pfin.monthly_report where report_id = :d6::bigint),
  'final',
  '(6a) inside the same transaction, the row IS final'
);
rollback to savepoint sp_finalize_rollback;
select set_config('role', 'postgres', true);
select is(
  (select generation_status from pfin.monthly_report where report_id = :d6::bigint),
  'draft',
  '(6b) RESTORED: back to `draft` after rollback'
);
select ok(
  (select rendered_payload is null and generated_at is null and commentary_disposition is null
     from pfin.monthly_report where report_id = :d6::bigint),
  '(6c) THE CATCH CRITERION: rendered_payload, generated_at, AND commentary_disposition are ALL NULL — the disposition write (step 2, committed first inside the function) did not leak past the rollback either, proving the two-UPDATE shape is genuinely one transaction'
);

-- =====================================================================
-- LEG 7 — DISPOSITION-BEFORE-COMPOSE, the ordering leg and the reason this
-- file exists in the order it does: finalize with 'skipped' and assert the
-- FROZEN payload's own disposition field is 'skipped', not NULL.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_open_monthly_report_draft('2026-06-01') as d7 \gset
select pfin.fn_finalize_monthly_report('2026-06-01', 'skipped');
select set_config('role', 'postgres', true);
select is(
  (select rendered_payload -> 'sections' -> 'rebalancing_targets' ->> 'disposition' from pfin.monthly_report where report_id = :d7::bigint),
  'skipped',
  '(7) A VERSION THAT COMPOSED FIRST PASSES EVERY OTHER LEG HERE: the frozen payload''s disposition field is ''skipped'', proving the column was written BEFORE 110 read it'
);

-- =====================================================================
-- LEG 8 — THE DISPOSITION VOCABULARY IS ENFORCED: NULL and an invented value
-- are refused (authored/skipped success is already proven at legs 1 and 7).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_open_monthly_report_draft('2026-07-01') as d8 \gset
select throws_like(
  $$ select pfin.fn_finalize_monthly_report('2026-07-01', null) $$,
  :'m_vocab',
  '(8a) NULL disposition is refused'
);
select throws_like(
  $$ select pfin.fn_finalize_monthly_report('2026-07-01', 'partially-done') $$,
  :'m_vocab',
  '(8b) an invented disposition value is refused'
);
select set_config('role', 'postgres', true);
select is(
  (select generation_status from pfin.monthly_report where report_id = :d8::bigint),
  'draft',
  '(8c) NON-VACUOUS: the draft is UNTOUCHED by both refused attempts and remains available'
);

-- =====================================================================
-- LEG 9 — 'authored' WITH FOUR EMPTY-STRING COMMENTARY COLUMNS SUCCEEDS
-- (R12 rider 1) — a leg asserting the opposite would encode a gate the
-- product does not have.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_open_monthly_report_draft('2026-08-01') as d9 \gset
select pfin.fn_save_monthly_commentary('2026-08-01', '', '', '', '');
select lives_ok(
  $$ select pfin.fn_finalize_monthly_report('2026-08-01', 'authored') $$,
  '(9) finalizing with disposition ''authored'' and all four commentary columns genuinely empty strings SUCCEEDS'
);
select set_config('role', 'postgres', true);
select is(
  (select generation_status from pfin.monthly_report where report_id = :d9::bigint),
  'final',
  '(9b) NON-VACUOUS: the row is genuinely `final` afterward'
);

-- =====================================================================
-- LEG 10 — THE IMMUTABILITY TRIGGER THEN BLOCKS EVERY LATER COLUMN WRITE:
-- after finalize, UPDATEs of rendered_payload, a commentary column, and
-- owner_header_at_generation are each refused; the ONLY permitted move is
-- final -> superseded. As `postgres` (owner, ACL-exempt) so the trigger,
-- not a missing grant, is what fires.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_open_monthly_report_draft('2026-09-01') as d10 \gset
select pfin.fn_finalize_monthly_report('2026-09-01', 'skipped');
select set_config('role', 'postgres', true);
select throws_like(
  format($$ update pfin.monthly_report set rendered_payload = '{}'::jsonb where report_id = %s $$, :d10::bigint),
  :'m_one_transition',
  '(10a) UPDATE of rendered_payload refused — the only permitted UPDATE on a final row is the ONE monotone transition, and this is not it'
);
select throws_like(
  format($$ update pfin.monthly_report set commentary_cash = 'forged' where report_id = %s $$, :d10::bigint),
  :'m_one_transition',
  '(10b) UPDATE of a commentary column refused'
);
select throws_like(
  format($$ update pfin.monthly_report set owner_header_at_generation = 'forged' where report_id = %s $$, :d10::bigint),
  :'m_one_transition',
  '(10c) UPDATE of owner_header_at_generation refused'
);
select lives_ok(
  format($$ update pfin.monthly_report set generation_status = 'superseded' where report_id = %s $$, :d10::bigint),
  '(10d) NON-VACUOUS: the ONE permitted move, final -> superseded, still succeeds — (10a)-(10c) are not a blanket freeze of the whole row'
);

-- =====================================================================
-- LEG 11 — owner_header_at_generation IS FROZEN FROM 106: set a header,
-- finalize, change the header, and assert the report STILL carries the OLD
-- one — copying a value and joining it live are indistinguishable until the
-- source changes, which is the third step here.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.owner_identification (owner_id_header_text) values ('Header V1');
select pfin.fn_open_monthly_report_draft('2026-10-01') as d11 \gset
select pfin.fn_finalize_monthly_report('2026-10-01', 'skipped');
select set_config('role', 'postgres', true);
select is(
  (select owner_header_at_generation from pfin.monthly_report where report_id = :d11::bigint),
  'Header V1',
  '(11a) the frozen header equals what was set at finalize time'
);
select _rls.set_tenant(:'ta'::uuid);
update pfin.owner_identification set owner_id_header_text = 'Header V2' where users_id = :'ta'::uuid;
select set_config('role', 'postgres', true);
select is(
  (select owner_header_at_generation from pfin.monthly_report where report_id = :d11::bigint),
  'Header V1',
  '(11b) THE LEG: after changing 106''s LIVE row to Header V2, the FINALIZED report STILL says Header V1 — a live join would have shown V2'
);

-- =====================================================================
-- LEG 12 — A TENANT WITH NO owner-identification ROW finalizes successfully
-- with owner_header_at_generation NULL (PM A-13) — a refusal here would be
-- the defect.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);
select pfin.fn_open_monthly_report_draft('2026-11-01') as d12 \gset
select lives_ok(
  $$ select pfin.fn_finalize_monthly_report('2026-11-01', 'skipped') $$,
  '(12a) tenant B (no owner_identification row at all) finalizes successfully'
);
select set_config('role', 'postgres', true);
select is(
  (select owner_header_at_generation from pfin.monthly_report where report_id = :d12::bigint),
  null,
  '(12b) owner_header_at_generation is NULL — a legitimate value, not a failure'
);

-- =====================================================================
-- LEG 13 — payload_schema_version EQUALS THE PAYLOAD'S OWN FIELD (rides
-- LEG 1's fixture) — not a hardcoded 1.
-- =====================================================================
select is(
  (select payload_schema_version::int from pfin.monthly_report where report_id = :d1::bigint),
  (select (rendered_payload ->> 'payload_schema_version')::int from pfin.monthly_report where report_id = :d1::bigint),
  '(13) payload_schema_version matches the FROZEN PAYLOAD''S OWN field, extracted rather than hardcoded'
);

-- =====================================================================
-- LEG 14 — included_reconciliation_event_ids IS STILL '{}' after finalize
-- (rides LEG 1's fixture).
-- =====================================================================
select is(
  (select included_reconciliation_event_ids from pfin.monthly_report where report_id = :d1::bigint),
  '{}'::int[],
  '(14) included_reconciliation_event_ids is still the empty array — this function deliberately never populates it'
);

-- =====================================================================
-- LEG 15 — data_as_of IS UNCHANGED BY FINALIZATION, and the payload's OWN
-- as_of equals it — the draft's as-of is what was composed, no clock
-- re-derived (rides LEG 1's fixture).
-- =====================================================================
select ok(
  (select data_as_of = (rendered_payload ->> 'as_of')::date
     from pfin.monthly_report where report_id = :d1::bigint),
  '(15) monthly_report.data_as_of equals the frozen payload''s OWN as_of field'
);

-- =====================================================================
-- LEG 16 — STANDING: no rolbypassrls role (service_role, by name) holds
-- EXECUTE on this function.
-- =====================================================================
select ok(
  not has_function_privilege('service_role', 'pfin.fn_finalize_monthly_report(date,text)'::regprocedure, 'EXECUTE'),
  '(16) service_role holds NO EXECUTE on fn_finalize_monthly_report'
);

select * from finish();
rollback;

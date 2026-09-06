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
--
-- ⚠ BEFORE the ran-count watcher leg below existed, this file showed
-- "LOOKS LIKE YOU PLANNED 53 TESTS BUT RAN 49" in an aggregate pg_prove run
-- — EXPECTED, and it did NOT MEAN a savepoint-wrapped leg can't fail
-- (VERIFIED, not inferred — struck
-- guard (6a) in the real `fn_finalize_monthly_report` on a scratch clone and
-- ran this UNMODIFIED file through pg_prove: (14h-i)/(14h-ii) correctly went
-- `not ok`, by name, with `Result: FAIL`). The mechanism: an `ok(...)`/
-- `throws_like(...)` call's TAP line is that statement's own RETURN VALUE —
-- psql prints it the moment the `select` completes, which is BEFORE the
-- following `rollback to savepoint` runs, so pass/fail survives the
-- rollback intact and pg_prove (the real consumer) sees and counts it
-- correctly. What DOES roll back with the savepoint is pgTAP's OWN internal
-- bookkeeping table (`finish()`'s self-diagnostic counter, not the TAP
-- stream), which is why `finish()` reports a mismatched "ran" count for any
-- trailing savepoint-wrapped legs with nothing non-rolled-back after them to
-- refresh that counter. Expected drift here = 4, exactly the trailing 14h-i
-- through 14h-iv legs (each its own `savepoint ... rollback to savepoint`
-- pair, immediately before `finish()`).
--
-- ⚠ WITH THE RAN-COUNT WATCHER LEG BELOW IN PLACE, the "planned N ran M"
-- comment no longer appears at all (verified) — the watcher leg is itself
-- NOT savepoint-wrapped, so its own `_set('curr_test', …)` write survives to
-- `finish()`'s read and resurrects the counter to match the plan exactly,
-- the same "a later non-rolled-back write overwrites the loss" mechanism
-- this note already describes. That is a side effect, not the point: the
-- watcher's OWN comparison runs BEFORE that resurrecting write, comparing
-- the declared plan against the counter as the four rolled-back legs
-- actually left it — a GAP, not a bare literal (see the leg's own comment
-- for why a bare `curr_test = 49` literal was tried first and inversion-
-- proven wrong).
--
-- ⚠ THIS IS A KNOWINGLY DISARMED PLAN/RAN WATCHER, NEVER "COSMETIC" (Sec-c):
-- pass/fail detection itself is intact (see above, verified) — but the PLAN
-- COUNT watcher specifically no longer functions as a guard against a leg
-- that is ACCIDENTALLY never executed at all inside such a savepoint (a leg
-- whose `select ok(...)` is itself missing, or short-circuited before it
-- runs, produces the IDENTICAL "planned N ran M" comment as one that ran
-- and passed, or ran and was correctly caught failing — the comment cannot
-- distinguish those cases). Calling that "cosmetic" undersells it: a WATCHER
-- exists here and it has been deliberately disarmed by this file's own
-- shape, on purpose, with the tradeoff named. The leg right before
-- `finish()` below RE-ARMS it explicitly, so a FIFTH silent drift (a new
-- trailing savepoint-wrapped leg added later without this note being
-- updated) REDs instead of hiding inside the same unwatched comment.
-- Trust `Result:`/the `Failed tests:` list, not the plan-count comment, for
-- individual leg pass/fail; if a leg's actual EXECUTION is ever in doubt,
-- verify it the way this note was verified — strike the real guard and
-- watch the real leg flip, not from the plan-count line alone.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

\set m_no_draft '%no live draft for that month%'
\set m_vocab '%must be ''authored'' or ''skipped''%'
\set m_one_transition '%admits exactly ONE transition%'
\set m_snap_immut '%monthly_report_account_snapshot is immutable%'
\set m_snap_no_resolve '%does not resolve%'
\set m_snap_cross_tenant '%is not owned by the report''s tenant%'
\set m_snap_closed '%snapshot set CLOSES at finalization%'
\set m_bad_groups_path '%expected a JSON array%'
\set m_group_no_accounts '%has no `accounts` array%'
\set m_cardinality_mismatch '%the composed payload names % accounts%'

select plan(54);

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

-- =====================================================================
-- LEGS 14a-14i — THE LOCK 12 CHILDREN (pfin.monthly_report_account_snapshot),
-- Sec's pairing list. `109` shipped this table with NO WRITER anywhere in the
-- product until this migration; every one of these legs is genuinely new
-- coverage, not a re-aim.
-- =====================================================================

-- --- 14a: THE CHILDREN ARE WRITTEN, set matches the payload EXACTLY (rides
-- LEG 1's fixture: tenant A, d1, one account ta_acct, no ledger account yet).
select is(
  (select count(*)::int from pfin.monthly_report_account_snapshot where monthly_report_id = :d1::bigint),
  1,
  '(14a-1) exactly one Lock 12 child row for d1'
);
select is(
  (select account_id from pfin.monthly_report_account_snapshot where monthly_report_id = :d1::bigint),
  :ta_acct::bigint,
  '(14a-2) the child row names ta_acct'
);
select ok(
  (select array_agg(account_id order by account_id) from pfin.monthly_report_account_snapshot where monthly_report_id = :d1::bigint)
  = (select array_agg((acc ->> 'account_id')::bigint order by (acc ->> 'account_id')::bigint)
       from pfin.monthly_report r,
            jsonb_array_elements(r.rendered_payload #> '{sections,account_holdings,groups}') g
            cross join lateral jsonb_array_elements(g -> 'accounts') acc
      where r.report_id = :d1::bigint),
  '(14a-3) SET EQUALITY IN BOTH DIRECTIONS: the child account_id set equals the FROZEN PAYLOAD''S OWN account_id set, extracted independently from rendered_payload — not merely a matching count'
);

-- --- 14b: THE DISCRIMINATOR — a tax-authority ledger account must be ABSENT
-- from the children. Without this leg, 14a passes identically for a writer
-- that reads pfin.account live (every account the caller owns) instead of
-- the payload's own (ledger-excluding) account set.
select set_config('role', 'postgres', true);
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'A-irs-ledger', 'depository', 'household', 'taxable') returning account_id as ta_ledger_acct \gset
update pfin.account set tax_jurisdiction = 'irs' where account_id = :ta_ledger_acct::bigint;
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type)
  values (:ta_ledger_acct, '2026-01-01', 500, 'setup', 'opening balance', 'acct_setup');
select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_open_monthly_report_draft('2027-01-01') as d14b \gset
select pfin.fn_finalize_monthly_report('2027-01-01', 'skipped');
select set_config('role', 'postgres', true);
select ok(
  not exists (
    select 1 from pfin.monthly_report_account_snapshot
     where monthly_report_id = :d14b::bigint and account_id = :ta_ledger_acct::bigint
  ),
  '(14b) THE LEG: tenant A''s designated tax-authority ledger account (ta_ledger_acct) is ABSENT from the children — the composition''s own ledger-exclusion, not a live pfin.account read'
);
select ok(
  exists (
    select 1 from pfin.monthly_report_account_snapshot
     where monthly_report_id = :d14b::bigint and account_id = :ta_acct::bigint
  ),
  '(14b) NON-VACUOUS: the SAME tenant''s ordinary account (ta_acct) IS present — the exclusion is selective, not a blanket empty set'
);

-- --- 14c: acct_name_at_generation and tax_treatment_at_generation are
-- FROZEN — rename the account and change its tax treatment AFTER finalize,
-- and assert the child row still carries the OLD values (rides d1).
select is(
  (select acct_name_at_generation from pfin.monthly_report_account_snapshot where monthly_report_id = :d1::bigint and account_id = :ta_acct::bigint),
  'A-acct',
  '(14c-setup) NON-VACUOUS: the child row currently carries the account''s name AT GENERATION TIME'
);
update pfin.account set name = 'A-acct-RENAMED', tax_treatment = 'tax_deferred' where account_id = :ta_acct::bigint;
select is(
  (select acct_name_at_generation from pfin.monthly_report_account_snapshot where monthly_report_id = :d1::bigint and account_id = :ta_acct::bigint),
  'A-acct',
  '(14c-1) THE LEG: after a LIVE rename, the child row still carries the OLD name — a copy, not a live join'
);
select is(
  (select tax_treatment_at_generation from pfin.monthly_report_account_snapshot where monthly_report_id = :d1::bigint and account_id = :ta_acct::bigint),
  'taxable',
  '(14c-2) THE LEG: after a LIVE tax_treatment change, the child row still carries the OLD value'
);

-- --- 14d: ROLLBACK TAKES THE CHILDREN WITH IT (parallels LEG 6's atomicity).
select _rls.set_tenant(:'ta'::uuid);
savepoint sp_14d;
select pfin.fn_open_monthly_report_draft('2027-02-01') as d14d \gset
select pfin.fn_finalize_monthly_report('2027-02-01', 'skipped');
select set_config('role', 'postgres', true);
select ok(
  (select count(*)::int from pfin.monthly_report_account_snapshot where monthly_report_id = :d14d::bigint) > 0,
  '(14d-setup) NON-VACUOUS PRECONDITION: children exist for d14d before the rollback'
);
rollback to savepoint sp_14d;
select set_config('role', 'postgres', true);
select is(
  (select count(*)::int from pfin.monthly_report_account_snapshot where monthly_report_id = :d14d::bigint),
  0,
  '(14d) THE LEG: after the finalize transaction ROLLS BACK, ZERO snapshot rows remain for that report — the children are as atomic as the parent'
);

-- --- 14e: THE CHILDREN ARE IMMUTABLE AND DELETE-BLOCKED, and the PARENT
-- cannot be deleted while they exist (ON DELETE RESTRICT).
select throws_like(
  format($$ update pfin.monthly_report_account_snapshot set acct_name_at_generation = 'forged' where monthly_report_id = %s and account_id = %s $$, :d1, :ta_acct),
  :'m_snap_immut',
  '(14e-a) UPDATE on a child row is refused — immutable audit-class'
);
select throws_like(
  format($$ delete from pfin.monthly_report_account_snapshot where monthly_report_id = %s and account_id = %s $$, :d1, :ta_acct),
  :'m_snap_immut',
  '(14e-b) DELETE on a child row is refused'
);
-- ⚠ Deleting d1 (a `final` parent) does NOT reach ON DELETE RESTRICT at all:
-- 108's OWN immutability trigger blocks deleting a FINAL row regardless of
-- children, firing first and making the FK layer unobservable through that
-- path — the SAME "fence made unreachable by an earlier one" shape as 111's
-- leg 4d. The genuine ON DELETE RESTRICT test needs a DRAFT parent with a
-- child, since 109's own comment names this precisely: "108's trigger
-- PERMITS deleting a draft parent... so a draft parent that has children
-- cannot be deleted" — only reachable by a direct owner-path INSERT while
-- the parent is still draft (postgres bypasses RLS but not 109's own
-- closes-at-finalization trigger, which permits exactly this).
select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_open_monthly_report_draft('2027-05-01') as d14e \gset
select set_config('role', 'postgres', true);
insert into pfin.monthly_report_account_snapshot (monthly_report_id, account_id, acct_name_at_generation, tax_treatment_at_generation)
  values (:d14e, :ta_acct, 'A-acct', 'taxable');
select ok(
  (select generation_status from pfin.monthly_report where report_id = :d14e::bigint) = 'draft',
  '(14e-c-setup) NON-VACUOUS: the parent is still `draft` with a child already attached — 109''s own trigger permits an insert while draft'
);
select throws_like(
  format($$ delete from pfin.monthly_report where report_id = %s $$, :d14e),
  '%violates foreign key constraint%',
  '(14e-c) THE LEG: a DRAFT parent CANNOT be deleted while a child exists — ON DELETE RESTRICT, reachable here because 108''s own immutability trigger does NOT block deleting a draft, unlike (the unreachable-through-this-path) final row'
);

-- --- 14f: FLAG-4 IS NO LONGER MOOT — a direct owner-path INSERT against a
-- `final` parent is refused (the 14a/14b/14c/14d successes above already
-- prove the POSITIVE half: the finalize path''s own INSERT succeeds only
-- because it fires while the parent is still `draft`).
select throws_like(
  format($$ insert into pfin.monthly_report_account_snapshot (monthly_report_id, account_id, acct_name_at_generation, tax_treatment_at_generation)
              values (%s, %s, 'forged', 'forged') $$, :d1, :ta_acct),
  :'m_snap_closed',
  '(14f) a direct owner-path INSERT against a `final` parent (d1) is refused — the snapshot set CLOSES at finalization (Sec FLAG-4), driven THROUGH this table''s own trigger, not asserted on an empty table'
);

-- --- 14g: A TENANT WITH NO ACCOUNTS finalizes successfully with ZERO
-- children — an empty set is a valid outcome, and the required MATCHED
-- CONTROL for 14h below (which otherwise only proves the function CAN
-- refuse).
\set tz '00000000-0000-0000-0000-00000000000f'
insert into auth.users (id) values (:'tz');
insert into pfin.user_settings (users_id, mfa_policy) values (:'tz', 'none');
select _rls.set_tenant(:'tz'::uuid);
select pfin.fn_open_monthly_report_draft('2027-03-01') as d14g \gset
select lives_ok(
  $$ select pfin.fn_finalize_monthly_report('2027-03-01', 'skipped') $$,
  '(14g) THE CONTROL: a tenant with NO accounts at all finalizes successfully — an empty child set is a valid outcome, not a failure'
);
select set_config('role', 'postgres', true);
select is(
  (select count(*)::int from pfin.monthly_report_account_snapshot where monthly_report_id = :d14g::bigint),
  0,
  '(14g) NON-VACUOUS: zero children were written, matching the zero-account payload'
);

-- --- ⚠ 14i — NOT A LEG, AND THIS LIST MUST NOT IMPLY OTHERWISE: the
-- sibling-key shape is UNCOVERABLE here. If a `110` restructuring relocated
-- accounts to a NEW sibling key while `sections.account_holdings.groups`
-- stayed a legitimately empty `'[]'`, every guard in `115` passes — it is
-- INDISTINGUISHABLE from 14g's own zero-account tenant, which is the exact
-- shape this file must NOT false-RED on. A `payload_schema_version` pin
-- would catch it and was deliberately NOT taken: a payload version bump is
-- a Sec-review event, not something a DB self-check should gate on. No leg
-- is written here that would appear to cover this residual gap.

-- --- 14h — Sec FLAG-7: THE FOUR RESTRUCTURING SHAPES, each driven by
-- REPLACING pfin.fn_render_monthly_report on THIS transaction (savepoint-
-- wrapped, restored after each shape — the DDL is transactional like
-- everything else here), each MUST REFUSE. Each stub keeps the ONE thing 115
-- checks before reaching the shape under test — a correct
-- sections.rebalancing_targets.source_report_id echo — so the failure
-- observed is genuinely the guard under test, not an earlier echo mismatch.
-- ⚠ BOTH REQUIRED CONTROLS ALREADY RAN, IN THIS SAME FILE, AGAINST THE REAL
-- (uncorrupted) fn_render_monthly_report: 14a/14b (a tenant WITH accounts
-- finalizes with the full, correctly-excluded set) and 14g immediately above
-- (a tenant with NO accounts finalizes with zero children) — satisfying
-- Sec's "both controls must pass in the same run," without which these four
-- shapes would prove only that the function CAN refuse.
select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_open_monthly_report_draft('2027-04-01') as d14h \gset
select set_config('role', 'postgres', true);

-- (i) the {sections,account_holdings,groups} path RENAMED/moved.
savepoint sp_14h_i;
create or replace function pfin.fn_render_monthly_report(p_target_month date, p_data_as_of date)
returns jsonb language sql security invoker stable set search_path = '' as $stub$
  select jsonb_build_object(
    'payload_schema_version', 1,
    'sections', jsonb_build_object(
      'rebalancing_targets', jsonb_build_object(
        'source_report_id', (select report_id from pfin.monthly_report where target_month = p_target_month and generation_status = 'draft')
      ),
      'account_holdings', jsonb_build_object('renamed_groups', '[]'::jsonb)
    )
  );
$stub$;
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  $$ select pfin.fn_finalize_monthly_report('2027-04-01', 'skipped') $$,
  :'m_bad_groups_path',
  '(14h-i) THE {sections,account_holdings,groups} PATH RENAMED/MOVED is refused — without this guard: zero children, no error, the report frozen forever (the exact P8 degradation this migration exists to fix, re-created)'
);
select set_config('role', 'postgres', true);
rollback to savepoint sp_14h_i;

-- (ii) that path present but a SCALAR, not an array — SAME named message.
savepoint sp_14h_ii;
create or replace function pfin.fn_render_monthly_report(p_target_month date, p_data_as_of date)
returns jsonb language sql security invoker stable set search_path = '' as $stub$
  select jsonb_build_object(
    'payload_schema_version', 1,
    'sections', jsonb_build_object(
      'rebalancing_targets', jsonb_build_object(
        'source_report_id', (select report_id from pfin.monthly_report where target_month = p_target_month and generation_status = 'draft')
      ),
      'account_holdings', jsonb_build_object('groups', to_jsonb('oops'::text))
    )
  );
$stub$;
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  $$ select pfin.fn_finalize_monthly_report('2027-04-01', 'skipped') $$,
  :'m_bad_groups_path',
  '(14h-ii) THE PATH PRESENT BUT A SCALAR is refused with the SAME named message as (i) — a restructuring, not a distinct failure, and an operator should not see a raw 22023 from inside the traversal'
);
select set_config('role', 'postgres', true);
rollback to savepoint sp_14h_ii;

-- (iii) an account element with no `account_id` key — refused by the
-- cardinality assertion (silent partial drop at the join, without it).
savepoint sp_14h_iii;
create or replace function pfin.fn_render_monthly_report(p_target_month date, p_data_as_of date)
returns jsonb language sql security invoker stable set search_path = '' as $stub$
  select jsonb_build_object(
    'payload_schema_version', 1,
    'sections', jsonb_build_object(
      'rebalancing_targets', jsonb_build_object(
        'source_report_id', (select report_id from pfin.monthly_report where target_month = p_target_month and generation_status = 'draft')
      ),
      'account_holdings', jsonb_build_object(
        'groups', jsonb_build_array(
          jsonb_build_object('accounts', jsonb_build_array(jsonb_build_object('foo', 'bar')))
        )
      )
    )
  );
$stub$;
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  $$ select pfin.fn_finalize_monthly_report('2027-04-01', 'skipped') $$,
  :'m_cardinality_mismatch',
  '(14h-iii) AN ACCOUNT ELEMENT WITH NO account_id KEY is refused by the cardinality assertion — wrote 0, the payload names 1, a silent partial drop at the join without this guard'
);
select set_config('role', 'postgres', true);
rollback to savepoint sp_14h_iii;

-- (iv) a group with no `accounts` array — the cardinality assertion cannot
-- see this shape (count query and INSERT share the traversal, both drop it),
-- so it needs its OWN guard.
savepoint sp_14h_iv;
create or replace function pfin.fn_render_monthly_report(p_target_month date, p_data_as_of date)
returns jsonb language sql security invoker stable set search_path = '' as $stub$
  select jsonb_build_object(
    'payload_schema_version', 1,
    'sections', jsonb_build_object(
      'rebalancing_targets', jsonb_build_object(
        'source_report_id', (select report_id from pfin.monthly_report where target_month = p_target_month and generation_status = 'draft')
      ),
      'account_holdings', jsonb_build_object(
        'groups', jsonb_build_array(jsonb_build_object('category', 'x'))
      )
    )
  );
$stub$;
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  $$ select pfin.fn_finalize_monthly_report('2027-04-01', 'skipped') $$,
  :'m_group_no_accounts',
  '(14h-iv) A GROUP WITH NO accounts ARRAY is refused by its OWN guard — the cardinality assertion structurally cannot see this shape, since the count query and the INSERT share the same traversal and both drop the group identically'
);
select set_config('role', 'postgres', true);
rollback to savepoint sp_14h_iv;

-- =====================================================================
-- LEG (RAN-COUNT WATCHER) — Sec-c FLAG-4/option-(C): RE-ARMS the plan/ran
-- drift this file's own header discusses. Deliberately the LAST leg before
-- `finish()` and deliberately NOT inside a savepoint, so it always runs and
-- always counts.
-- ⚠ NOT a bare `curr_test = 49` literal (tried first, INVERSION-PROVEN
-- WRONG): struck this exact shape by injecting a FIFTH trailing
-- savepoint-wrapped leg on a scratch copy and it stayed GREEN — `curr_test`
-- reverts to whatever the LAST NON-rolled-back write set (49, from leg
-- 14g's own check) after EVERY rolled-back savepoint, regardless of how
-- many such legs run in sequence, so a bare literal comparison cannot see a
-- count of trailing legs change AT ALL.
-- ⚠ THE ACTUAL CHECK: the ARITHMETIC GAP between the declared plan
-- (`_get('plan')`, set once by `plan(54)` above, long before any savepoint,
-- so it never rolls back) and `curr_test` (`_get('curr_test')`, reverted by
-- every trailing rollback) equals the KNOWN drift of 4. A new trailing
-- savepoint-wrapped leg bumps the declared plan (a real assertion was
-- added) but does NOT move `curr_test` (its own write also rolls back), so
-- the gap becomes 5 and THIS leg REDs — INVERSION-PROVEN on the same
-- injected-fifth-leg scratch copy, with `plan()` bumped to match, before
-- landing this shape. Whoever adds a NEW trailing savepoint-wrapped leg to
-- this file must update the expected drift here (and the header note above)
-- in the SAME commit — that is the point of naming it a leg rather than
-- leaving it as prose.
-- =====================================================================
select is(
  public._get('plan') - public._get('curr_test'),
  5,
  '(115-watcher) EXPLICIT drift check: the gap between the declared plan (54, set once pre-savepoint, never rolls back) and pgTAP''s own bookkeeping counter (reverted by every trailing rolled-back savepoint, reads 49 here) is EXACTLY 5 — the 4 KNOWN trailing 14h-i..iv legs PLUS this watcher leg itself (planned but not yet run at the moment this comparison executes). A new trailing savepoint-wrapped leg bumps the plan without moving the counter, widening this gap, and REDs this leg by name instead of hiding in the plan-count comment'
);

select * from finish();
rollback;

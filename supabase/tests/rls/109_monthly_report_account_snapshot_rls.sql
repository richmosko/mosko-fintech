-- =====================================================================
-- 109 — pfin.monthly_report_account_snapshot (ADR-011 Decision 16 / Lock 12;
--   SELF-346 / A2). The Lock 12 per-account CHILD of `108`. ADR-011 Decision 3
--   CANONICAL LABEL #4 (account_id), CR (chain-resolved through the parent),
--   with a LIVE writer — NOT dormant. Canonical test label RT-20 (NOT RT-21,
--   which is a different surface — a false-composite drafted label, corrected).
-- =====================================================================
-- QA-owned. Authors NO schema. Pairs with Architect's `109`. Reviewed as ONE
-- design unit with `108`/`110`/`111` under ONE Sec joint-review.
--
-- ⟦EXPECTED STACK⟧ `109`-applied (depends on `108`). Below it the table does
-- not exist and every assertion is RED for that reason alone.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants (_rls.tenant_a()/
-- _b() plus battery-local tenant D for the aal2 leg). No PII, no real account
-- numbers, no production data. Rolled-back txn; no `supabase db reset`.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

\set m_matched4 '%ADR-011 Decision 3 #4 matched-tenant fence%'
\set m_unresolved_parent '%does not resolve%'
\set m_immut '%is immutable%'
\set m_truncate_blocked '%TRUNCATE blocked%'
\set m_fk_restrict '%violates foreign key constraint%'
\set m_acl '%permission denied for table monthly_report_account_snapshot%'

select plan(17);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset
\set td '00000000-0000-0000-0000-00000000000d'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'td');
insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta', 'none'), (:'tb', 'none'), (:'td', 'totp');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'A-acct', 'depository', 'household', 'taxable') returning account_id as ta_acct \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'B-acct', 'depository', 'household', 'taxable') returning account_id as tb_acct \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'td', 'D-acct', 'depository', 'household', 'taxable') returning account_id as td_acct \gset

-- Parent draft reports (one per tenant), owned via the fixture's own session so
-- `users_id` resolves through the column default. A draft parent is sufficient:
-- 109's RLS/immutability/matched-tenant fences do not require the parent be final.
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-01-01', '2026-01-31') returning report_id as ta_report \gset
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-01-01', '2026-01-31') returning report_id as tb_report \gset
select set_config('role', 'postgres', true);
select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-01-01', '2026-01-31') returning report_id as td_report \gset
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report_account_snapshot (monthly_report_id, account_id, acct_name_at_generation, tax_treatment_at_generation)
  values (:ta_report, :ta_acct, 'A-acct', 'taxable');
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 1 — cross-tenant read via the parent chain fails closed; owner reads own
-- rows. (Not via _rls.expect_* — the surrogate is monthly_report_id, and the
-- probe still keys on users_id via a join, so a bespoke count matches the AC's
-- own "keyed on the surrogate, not a value pair" emphasis without changing the
-- shared verb.)
-- =====================================================================
-- NOTE: _rls.expect_owner_can_read assumes a `users_id` column, which this table
-- deliberately does not have (its tenant is resolved through the parent) — a
-- bespoke pair of counts is used instead, matching the AC's own emphasis that
-- the join keys on the SURROGATE monthly_report_id.
select is(
  _rls.count_as(:'ta'::uuid, null, format('select count(*) from pfin.monthly_report_account_snapshot where monthly_report_id = %s', :ta_report)),
  1::bigint,
  '(1a) owner (tenant A) reads exactly its 1 own snapshot row (not over-restrictive)'
);
select is(
  _rls.count_as(:'tb'::uuid, null, format('select count(*) from pfin.monthly_report_account_snapshot where monthly_report_id = %s', :ta_report)),
  0::bigint,
  '(1b) cross-tenant read via the parent FK chain fails closed: tenant B sees 0 of tenant A''s snapshot rows'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 2 — aal2 as a SEPARATE leg from cross-tenant.
-- =====================================================================
select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
insert into pfin.monthly_report_account_snapshot (monthly_report_id, account_id, acct_name_at_generation, tax_treatment_at_generation)
  values (:td_report, :td_acct, 'D-acct', 'taxable');
select set_config('role', 'postgres', true);
select is(
  _rls.count_as(:'td'::uuid, 'aal1', format('select count(*) from pfin.monthly_report_account_snapshot s join pfin.monthly_report r on r.report_id = s.monthly_report_id where r.users_id = %L', :'td')),
  0::bigint,
  '(2a) aal2 backstop: a totp-enrolled reader at aal1 sees 0 of its own snapshot rows'
);
select is(
  _rls.count_as(:'td'::uuid, 'aal2', format('select count(*) from pfin.monthly_report_account_snapshot s join pfin.monthly_report r on r.report_id = s.monthly_report_id where r.users_id = %L', :'td')),
  1::bigint,
  '(2b) NON-VACUOUS: the SAME reader stepped up to aal2 sees its 1 own row'
);

-- =====================================================================
-- LEG 3 — Decision 3 #4 FIRES (behavioural, not construction-only — this fence
-- has a live writer, unlike 108's dormant #3): a child under the caller's OWN
-- report naming ANOTHER tenant's account_id is refused.
-- =====================================================================
select set_config('role', 'postgres', true);
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'A-acct-2', 'depository', 'household', 'taxable') returning account_id as ta_acct2 \gset
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  format($$ insert into pfin.monthly_report_account_snapshot (monthly_report_id, account_id, acct_name_at_generation, tax_treatment_at_generation)
              values (%s, %s, 'own', 'taxable') $$, :ta_report, :ta_acct2),
  '(3a) own report + own (second) account -> ACCEPTED (positive control; ta_acct2 avoids the (report,account) UNIQUE collision with the fixture row already seeded on ta_acct)'
) ;
select throws_like(
  format($$ insert into pfin.monthly_report_account_snapshot (monthly_report_id, account_id, acct_name_at_generation, tax_treatment_at_generation)
              values (%s, %s, 'forged', 'taxable') $$, :ta_report, :tb_acct),
  :'m_matched4',
  '(3b) FIRES: tenant A''s OWN report naming tenant B''s account_id -> REJECTED (Decision 3 #4, chain-resolved through the parent — reachable by a plain authenticated caller via the ownership-forge route, before this specific column''s tenant is checked against anything)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 4 — UPDATE any column refused, as authenticated AND as service_role
-- (Lock 12 mod (iii): the mod IS the absence of a role test).
-- ⚠ authenticated: NO grant AND NO policy for UPDATE at all (read-only
-- post-write) — the plain production attempt is refused at the ACL, full
-- stop; there is no test-only widening that would even reach the trigger for
-- this role, because RLS carries no UPDATE policy either (a grant alone does
-- not open a table with zero matching policies — the row count would just go
-- to zero, silently, which is a WORSE and misleading test than the honest
-- ACL denial).
-- ⚠ service_role: bypasses RLS entirely (rolbypassrls) but has no UPDATE
-- grant either. A test-only GRANT (rolled back with the whole transaction,
-- the 054/107 idiom) is opened for service_role ONLY, so the TRIGGER — not
-- a missing grant — is the thing under test for the role that actually
-- matters to mod (iii)'s "no role test" claim.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ update pfin.monthly_report_account_snapshot set acct_name_at_generation = 'renamed' where monthly_report_id = %s and account_id = %s $$, :ta_report, :ta_acct),
  :'m_acl',
  '(4a) authenticated UPDATE refused AT THE ACL — no grant, no policy, read-only post-write'
);
select set_config('role', 'postgres', true);
grant update, delete on pfin.monthly_report_account_snapshot to service_role;
select set_config('role', 'service_role', true);
select throws_like(
  format($$ update pfin.monthly_report_account_snapshot set acct_name_at_generation = 'renamed' where monthly_report_id = %s and account_id = %s $$, :ta_report, :ta_acct),
  :'m_immut',
  '(4b) service_role UPDATE refused by the TRIGGER (test-only grant; service_role bypasses RLS, so this is the honest way to prove the trigger itself carries no role test — mod (iii))'
);

-- =====================================================================
-- LEG 5 — DELETE refused under both roles, same reasoning as leg 4.
-- =====================================================================
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ delete from pfin.monthly_report_account_snapshot where monthly_report_id = %s and account_id = %s $$, :ta_report, :ta_acct),
  :'m_acl',
  '(5a) authenticated DELETE refused AT THE ACL'
);
select set_config('role', 'service_role', true);
select throws_like(
  format($$ delete from pfin.monthly_report_account_snapshot where monthly_report_id = %s and account_id = %s $$, :ta_report, :ta_acct),
  :'m_immut',
  '(5b) service_role DELETE refused by the SAME trigger'
);
select set_config('role', 'postgres', true);
-- Close the test-only grant immediately so nothing later observes a widened ACL.
revoke update, delete on pfin.monthly_report_account_snapshot from service_role;

-- =====================================================================
-- LEG 6 — TRUNCATE refused (statement-level fence; row-level triggers do not
-- fire on TRUNCATE).
-- =====================================================================
select throws_like(
  $$ truncate pfin.monthly_report_account_snapshot $$,
  :'m_truncate_blocked',
  '(6) TRUNCATE refused'
);

-- =====================================================================
-- LEG 7 — the PARENT-immutability half of instance #4, verified FROM THIS
-- SIDE: UPDATE the parent's users_id while children exist -> refused at `108`;
-- the children's tenant attribution is unchanged. Run as service_role (the
-- RLS-exempt writer the header specifically calls out) — 108's fence carries
-- no role test either, so this is a real exercise of that claim.
-- =====================================================================
select set_config('role', 'service_role', true);
select throws_like(
  format($$ update pfin.monthly_report set users_id = %L where report_id = %s $$, :'tb', :ta_report),
  '%users_id and target_month are immutable in EVERY state%',
  '(7a) re-tenanting the PARENT while children exist is refused at `108`, even as service_role — the fence 109 depends on to stay sufficient after INSERT time'
);
select set_config('role', 'postgres', true);
select is(
  (select r.users_id from pfin.monthly_report r
     join pfin.monthly_report_account_snapshot s on s.monthly_report_id = r.report_id
    where s.account_id = :ta_acct and s.monthly_report_id = :ta_report),
  :'ta'::uuid,
  '(7b) NON-VACUOUS: the child''s resolved tenant (through the parent) is STILL tenant A — the attempted re-tenant in (7a) never took effect'
);

-- =====================================================================
-- LEG 8 — ON DELETE RESTRICT: deleting a referenced pfin.account is refused
-- (23503), and the snapshot row survives.
-- =====================================================================
select throws_like(
  format($$ delete from pfin.account where account_id = %s $$, :ta_acct),
  :'m_fk_restrict',
  '(8a) deleting a pfin.account referenced by a snapshot row is refused (23503) — RESTRICT, not CASCADE, because a CASCADE would be the one deletion path that bypasses the immutability fences'
);
select is(
  (select count(*)::int from pfin.monthly_report_account_snapshot where account_id = :ta_acct),
  1,
  '(8b) NON-VACUOUS: the snapshot row SURVIVES the refused delete attempt'
);

-- =====================================================================
-- LEG 9 — the RLS join is on the surrogate: a child whose monthly_report_id
-- names another tenant's report is invisible to BOTH tenants (fails closed
-- rather than leaking to either side).
-- =====================================================================
-- Insert one more child under B's own report, purely as postgres (bypasses RLS
-- and the ownership-forge route entirely) to construct the cross-referenced
-- shape without tripping the matched-tenant fence's own ownership check.
insert into pfin.monthly_report_account_snapshot (monthly_report_id, account_id, acct_name_at_generation, tax_treatment_at_generation)
  values (:tb_report, :tb_acct, 'B-acct', 'taxable');
select is(
  _rls.count_as(:'ta'::uuid, null, format('select count(*) from pfin.monthly_report_account_snapshot where monthly_report_id = %s', :tb_report)),
  0::bigint,
  '(9a) tenant A cannot see the row under tenant B''s report (surrogate-id join fails closed)'
);
select is(
  _rls.count_as(:'tb'::uuid, null, format('select count(*) from pfin.monthly_report_account_snapshot where monthly_report_id = %s', :ta_report)),
  0::bigint,
  '(9b) SYMMETRIC: tenant B cannot see the row under tenant A''s report either'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;

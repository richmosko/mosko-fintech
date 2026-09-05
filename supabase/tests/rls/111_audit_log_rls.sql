-- =====================================================================
-- 111 — pfin.audit_log + pfin.fn_emit_audit_log (block AH; ruled at R7 option
--   (2)). The GENERAL same-transaction audit-log surface discharging ADR-011
--   Decision 1 clause (d). SECURITY DEFINER (forced by A10's own-session
--   caller) — the wave's only new DEFINER function, realizing the long-
--   reserved allowlist slot.
-- =====================================================================
-- QA-owned. Authors NO schema. Pairs with Architect's `111`. Reviewed as ONE
-- design unit with `108`/`109`/`110` under ONE Sec joint-review.
--
-- ⟦EXPECTED STACK⟧ `111`-applied. Below it the table/function do not exist
-- and every assertion is RED for that reason alone.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants (_rls.tenant_a()
-- / _b()). No PII, no real account numbers, no production data. Rolled-back
-- txn; no `supabase db reset`.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

\set m_no_tenant '%no resolved tenant%'
\set m_chain '%p_tenant_resolution_chain is required%'
\set m_acl '%permission denied for table audit_log%'
\set m_immut '%is immutable%'
\set m_truncate '%TRUNCATE blocked%'

select plan(19);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset
insert into auth.users (id) values (:'ta'), (:'tb');

-- =====================================================================
-- LEG 1 — the row exists IN THE SAME TRANSACTION as the privileged write it
-- describes, and — the restored catch criterion — is ABSENT when the
-- generation transaction ROLLS BACK.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
savepoint sp_rollback_leg;
select pfin.fn_emit_audit_log('monthly_report_generation', 'on_demand', 'impersonated session: request.jwt.claims.sub', '2026-08-31', 'pfin.monthly_report', 1);
-- authenticated holds NO grant on pfin.audit_log at all (RLS enabled, zero
-- policies, zero grants) — read as postgres. This set_config happens AFTER
-- the savepoint, so ROLLBACK TO SAVEPOINT below undoes the role switch too,
-- along with the row: role reverts to authenticated(ta) at that point.
select set_config('role', 'postgres', true);
select is(
  (select count(*)::int from pfin.audit_log where users_id = :'ta'::uuid),
  1,
  '(1a) the audit row exists in the SAME transaction as the privileged write it describes'
);
rollback to savepoint sp_rollback_leg;
select set_config('role', 'postgres', true);
select is(
  (select count(*)::int from pfin.audit_log where users_id = :'ta'::uuid),
  0,
  '(1b) the RESTORED CATCH CRITERION: the row is ABSENT once the generation transaction rolls back — a row that survives a rolled-back generation is worse than no row'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 2 — the row names the RESOLVED TENANT, and that tenant equals the
-- impersonated session's auth.uid().
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_emit_audit_log('monthly_report_generation', 'cron', 'impersonated session: request.jwt.claims.sub', '2026-08-31', 'pfin.monthly_report', 42) as a1 \gset
select set_config('role', 'postgres', true);
select is(
  (select users_id from pfin.audit_log where audit_id = :a1),
  :'ta'::uuid,
  '(2) the written row names the RESOLVED tenant, equal to the impersonated session''s auth.uid()'
);

-- =====================================================================
-- LEG 3 — a service_role session that has NOT impersonated cannot write a
-- row: auth.uid() is NULL and the INSERT fails closed, taking the
-- transaction with it.
-- =====================================================================
select set_config('role', 'service_role', true);
select set_config('request.jwt.claims', '', true);
select throws_like(
  $$ select pfin.fn_emit_audit_log('monthly_report_generation', 'cron', 'impersonated session: request.jwt.claims.sub', '2026-08-31', 'pfin.monthly_report', 1) $$,
  :'m_no_tenant',
  '(3) service_role with NO impersonation (auth.uid() is NULL) is refused closed — a privileged write whose tenant cannot be named is not a write anyone should keep'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 4 — an invented surface_name is REFUSED, and so is an invented
-- trigger_source.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- NOTE: the helper's OWN guard (m_surface) only catches NULL/blank — an
-- invented-but-non-blank value like 'bogus_surface' passes that guard and is
-- caught by the table's own CHECK constraint instead (a real, distinct fence,
-- just one layer further in). Both are "refused"; this leg asserts the layer
-- that actually fires for a non-blank invented value.
select throws_like(
  $$ select pfin.fn_emit_audit_log('bogus_surface', 'cron', 'impersonated session: request.jwt.claims.sub', '2026-08-31', null, null) $$,
  '%audit_log_surface_name_vocab%',
  '(4a) an invented (non-blank) surface_name is refused by the table CHECK — a general helper is where per-surface discipline goes to be forgotten'
);
select throws_like(
  $$ select pfin.fn_emit_audit_log('monthly_report_generation', 'bogus_trigger', 'impersonated session: request.jwt.claims.sub', '2026-08-31', null, null) $$,
  '%audit_log_trigger_source_vocab%',
  '(4b) an invented trigger_source is refused by the table CHECK (cron / on_demand only)'
);
-- Cheap, genuine coverage of the helper's OWN blank-chain guard — the field
-- the header names as "the one Decision 1 clause (d) actually asks for".
select throws_like(
  $$ select pfin.fn_emit_audit_log('monthly_report_generation', 'cron', '   ', '2026-08-31', null, null) $$,
  :'m_chain',
  '(4c) a blank tenant_resolution_chain is refused by the HELPER''s own guard — a resolved tenant id with no account of how it was resolved discharges only half of Decision 1 clause (d)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 5 — authenticated holds NO table grant: a direct INSERT through
-- PostgREST is refused at the ACL, while the SAME caller succeeds through
-- the helper. Both halves required.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ insert into pfin.audit_log (surface_name, trigger_source, users_id, tenant_resolution_chain)
              values ('monthly_report_generation', 'on_demand', %L, 'forged') $$, :'ta'),
  :'m_acl',
  '(5a) a DIRECT INSERT into pfin.audit_log through PostgREST is refused at the ACL — no role holds any grant on this table'
);
select lives_ok(
  $$ select pfin.fn_emit_audit_log('monthly_report_generation', 'on_demand', 'impersonated session: request.jwt.claims.sub', '2026-08-31', null, null) $$,
  '(5b) NON-VACUOUS: the SAME caller succeeds THROUGH the helper — distinguishing DEFINER-with-no-grant from INVOKER-with-a-grant, which is the whole security difference'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 6 — UPDATE / DELETE / TRUNCATE refused under both roles.
-- =====================================================================
select is(
  (select count(*)::int from pfin.audit_log where users_id = :'ta'::uuid),
  2,
  '(6-setup) NON-VACUOUS sanity: 2 rows exist for tenant A going into the mutation-refusal legs (leg 2''s + leg 5b''s)'
);
select throws_like(
  format($$ update pfin.audit_log set tenant_resolution_chain = 'forged' where audit_id = %s $$, :a1),
  :'m_immut',
  '(6a) UPDATE refused as postgres/owner (no role test in the trigger)'
);
select throws_like(
  format($$ delete from pfin.audit_log where audit_id = %s $$, :a1),
  :'m_immut',
  '(6b) DELETE refused as postgres/owner'
);
-- NOTE: SELECT is required alongside UPDATE/DELETE even though this leg never
-- reads a column value directly — the WHERE audit_id = %s predicate itself
-- needs SELECT to evaluate (same privilege-model fact as RETURNING: a command
-- that filters or returns a column needs SELECT on it, distinct from the
-- write verb's own grant). Confirmed by isolated repro: UPDATE+DELETE alone
-- produced 'permission denied for table audit_log' with a HINT naming the
-- missing GRANT SELECT — not the immutability trigger — until SELECT was added.
grant usage on schema pfin to service_role;
grant select, update, delete on pfin.audit_log to service_role;
select set_config('role', 'service_role', true);
select throws_like(
  format($$ update pfin.audit_log set tenant_resolution_chain = 'forged' where audit_id = %s $$, :a1),
  :'m_immut',
  '(6c) UPDATE refused as service_role too (test-only grant; no role test in the trigger)'
);
select throws_like(
  format($$ delete from pfin.audit_log where audit_id = %s $$, :a1),
  :'m_immut',
  '(6d) DELETE refused as service_role'
);
select set_config('role', 'postgres', true);
revoke select, update, delete on pfin.audit_log from service_role;
select throws_like(
  $$ truncate pfin.audit_log $$,
  :'m_truncate',
  '(6e) TRUNCATE refused — the one operation an audit trail exists to make impossible'
);

-- =====================================================================
-- LEG 7 — STANDING catalog assertion: fn_emit_audit_log is the only
-- prosecdef=true function added by this wave, and its EXECUTE ACL names
-- exactly authenticated and service_role, NOT public.
-- =====================================================================
-- postgres (the owner) appears implicitly in information_schema.routine_privileges
-- regardless of any explicit grant (ownership implies grantable privilege) and is
-- excluded here — the claim is about the two roles the migration actually grants.
select is(
  (select array_agg(grantee::text order by grantee) from information_schema.routine_privileges
    where routine_schema = 'pfin' and routine_name = 'fn_emit_audit_log' and privilege_type = 'EXECUTE'
      and grantee <> 'postgres'),
  array['authenticated', 'service_role'],
  '(7a) fn_emit_audit_log''s EXECUTE ACL names EXACTLY {authenticated, service_role} beyond the implicit owner — no PUBLIC, no third grantee'
);
select ok(
  (select prosecdef from pg_proc where oid = 'pfin.fn_emit_audit_log(text,text,text,date,text,bigint)'::regprocedure),
  '(7b) fn_emit_audit_log IS the SECURITY DEFINER function this wave adds — forced by A10''s own-session caller, realizing the long-reserved allowlist slot'
);

-- =====================================================================
-- LEG 8 — two callers, one shape: rows written by the cron and by the
-- on-demand path differ ONLY in trigger_source.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);
select pfin.fn_emit_audit_log('monthly_report_generation', 'cron', 'impersonated session: request.jwt.claims.sub', '2026-08-31', 'pfin.monthly_report', 99) as tb_cron \gset
select pfin.fn_emit_audit_log('monthly_report_generation', 'on_demand', 'impersonated session: request.jwt.claims.sub', '2026-08-31', 'pfin.monthly_report', 99) as tb_ondemand \gset
select set_config('role', 'postgres', true);
select is(
  (select count(*)::int from pfin.audit_log
    where audit_id in (:tb_cron, :tb_ondemand)
      and surface_name = 'monthly_report_generation'
      and users_id = :'tb'::uuid
      and data_as_of = '2026-08-31'
      and subject_table = 'pfin.monthly_report'
      and subject_id = 99),
  2,
  '(8) the cron row and the on-demand row are IDENTICAL on every column except trigger_source — two callers, one shape'
);
select is(
  (select array_agg(trigger_source order by trigger_source) from pfin.audit_log where audit_id in (:tb_cron, :tb_ondemand)),
  array['cron', 'on_demand'],
  '(8b) NON-VACUOUS: trigger_source is the ONLY column that actually differs between the two'
);

select * from finish();
rollback;

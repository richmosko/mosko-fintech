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
--
-- ⚠⚠ RE-LEGGED WHOLESALE FOR Sec's C1-C4 RULING (VETO-1, PR #636; frozen at
-- 5ca2cd1). `fn_emit_audit_log` DROPPED `p_trigger_source` (now 5 arguments,
-- not 6) and gained a C2 subject-binding dispatch — EVERY call site in the
-- PRIOR version of this file was an arity error, and every call that reaches
-- the `monthly_report_generation` branch now needs a REAL pfin.monthly_report
-- row, owned by the caller, written in the SAME transaction, or C2 refuses it
-- before the INSERT. `trigger_source` is derived from the transaction-local
-- GUC `app.report_generation_source` (exact match `'cron'`, else
-- `'on_demand'`) — a pgTAP session CAN set that GUC itself (nothing here
-- fences it), so the legs below prove the DERIVATION, never the GUC's
-- unreachability from a real PostgREST caller — that absence is a property of
-- the tree (no exposed function takes a GUC name from its argument) and is
-- DevOps's CI-fence to watch, not provable from inside a database session.
--
-- ⚠⚠ LEGS 7a-i (earlier-transaction refusal) AND 7b (read-only/no-xid
-- refusal) ARE STRUCTURAL CATALOG PINS, NOT LIVE BEHAVIOURAL PROOFS — A
-- DISCLOSED DOWNGRADE FROM Sec's SPEC, WITH A MEASURED REASON, NOT A
-- CONVENIENCE. Both conditions need a row or a session state that is
-- genuinely EARLIER than / OUTSIDE this file's own wrapped transaction — no
-- savepoint can ever produce that, because anything this file writes, at any
-- savepoint depth, is by construction part of its OWN top-level transaction
-- (verified directly: a row inserted under a savepoint that is then RELEASED,
-- not rolled back, is still reported as written-here).
--
-- `dblink` (a separate physical connection to this same database, opened and
-- closed mid-file) was tried FIRST and WORKS for creating the fact each leg
-- needs — but it has a MEASURED, SERIOUS side effect: opening and closing a
-- dblink connection mid-transaction corrupts `pg_current_snapshot()` for the
-- REST of that transaction, such that the session's OWN xid subsequently
-- reads as "already visible" to itself. Measured directly, reproduced
-- minimally: `pg_current_snapshot()` before any dblink activity reports
-- `xmin:xmin:` (empty range, own xid correctly excluded); after a
-- dblink-connect/insert/disconnect sequence in the SAME transaction, the very
-- next snapshot reports `xmin:xmin+N:` — a NON-EMPTY range with an EMPTY
-- `xip_list` — which makes `pg_visible_in_snapshot` treat ANY xid in that
-- range, INCLUDING the calling transaction's own, as already-committed. This
-- broke every C2-success leg that would otherwise follow a dblink call in the
-- same file (confirmed: a bare INSERT's own row, checked immediately after,
-- read as "not written here"). An EXTERNAL pre-seed — a row committed via a
-- FULLY SEPARATE connection that opens, commits, and exits BEFORE this file's
-- own `begin` — does NOT exhibit the corruption (no temporal overlap with
-- this transaction at all), but requires a companion step outside this
-- self-contained file, which is a real convention departure of its own.
-- Given neither safe option fits inside one file without cost, these two legs
-- are PRESENCE pins instead (matching 101's own SF-L "presence, not effect"
-- posture for a different un-simulatable claim): they confirm the function's
-- body actually calls the right primitives and raises the right messages,
-- never that calling it under the real condition behaviourally reproduces the
-- refusal. Flagged to team-lead/Sec as a live gap, not silently routed
-- around — an external pre-seed script is the concrete follow-up if full
-- behavioural coverage is wanted.
--
-- ⚠⚠ SECOND MEASURED FINDING, INDEPENDENT OF DBLINK — a caught trigger-raised
-- exception poisons this SAME transaction's OWN later writes for
-- `pg_visible_in_snapshot`. Minimal reproduction (13 lines, no dblink
-- anywhere): create a table with a BEFORE UPDATE/DELETE trigger that RAISEs;
-- `throws_like()` a real UPDATE against an existing row of that table (the
-- exact shape leg 6's 6a-6d need to prove the immutability trigger fires);
-- then, as a perfectly ordinary LATER top-level statement in the SAME
-- transaction, INSERT a fresh row and check
-- `pg_visible_in_snapshot(newrow.xmin::text::xid8, pg_current_snapshot())` —
-- it reads TRUE (wrongly "already committed/visible", i.e. NOT "written
-- here") even though that INSERT is a bare top-level statement with no
-- savepoint of its own. Bisected against this file directly (truncating at
-- successive leg boundaries and probing): the gap is absent through the end
-- of leg 5, present by the end of the original leg 6, and narrows to leg
-- 6a alone (a single throws_like'd UPDATE hitting the real trigger) —
-- confirmed NOT caused by: throws_like alone with no real trigger-write
-- (25-iteration burst, no gap); a bare savepoint/real-write/rollback cycle
-- alone or repeated 8x in the exact shape of leg 1 (no gap); GRANT/REVOKE
-- DDL alone. The isolating factor is specifically a data-modifying statement
-- that reaches a BEFORE trigger which raises, caught by throws_like. Fix
-- applied here: LEG 6 IS MOVED TO THE END OF THIS FILE (after leg 12), so
-- every C2-success/derivation leg that depends on `fn_emit_audit_log`'s own
-- internal `pg_visible_in_snapshot` call (8-iii, 10, 11, 12) runs BEFORE the
-- poisoning trigger fires, keeping them genuinely BEHAVIOURAL rather than
-- forcing a further structural-pin downgrade. This is a PRODUCT-RELEVANT
-- finding, not just a test-harness artifact: any real application
-- transaction that catches an exception from a trigger-raised UPDATE/DELETE
-- and THEN calls `fn_emit_audit_log` naming a row written earlier in that
-- SAME transaction risks the identical false refusal — flagged to
-- team-lead/Architect/Sec; the reorder here is QA's test-file mitigation
-- only, not a statement that the product mechanism itself is safe.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

\set m_no_tenant '%no resolved tenant%'
\set m_chain '%p_tenant_resolution_chain is required%'
\set m_acl '%permission denied for table audit_log%'
\set m_immut '%is immutable%'
\set m_truncate '%TRUNCATE blocked%'
\set m_no_binding '%no C2 subject binding is defined for surface%'
\set m_vocab_check '%audit_log_surface_name_vocab%'
\set m_bad_subject '%requires p_subject_table%'
\set m_not_yours '%is not a row belonging to the tenant%'

select plan(29);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset
insert into auth.users (id) values (:'ta'), (:'tb');

-- =====================================================================
-- LEG 1 — the row exists IN THE SAME TRANSACTION as the privileged write it
-- describes, and — the restored catch criterion — is ABSENT when the
-- generation transaction ROLLS BACK. C2 now requires a REAL subject row, so
-- the leaf write itself is part of the fixture under the savepoint.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
savepoint sp_rollback_leg;
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-01-01', '2026-01-31') returning report_id as leg1_subject \gset
select pfin.fn_emit_audit_log('monthly_report_generation', 'impersonated session: request.jwt.claims.sub', '2026-01-31', 'pfin.monthly_report', :leg1_subject::bigint);
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
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-02-01', '2026-02-28') returning report_id as leg2_subject \gset
select pfin.fn_emit_audit_log('monthly_report_generation', 'impersonated session: request.jwt.claims.sub', '2026-02-28', 'pfin.monthly_report', :leg2_subject::bigint) as a1 \gset
select set_config('role', 'postgres', true);
select is(
  (select users_id from pfin.audit_log where audit_id = :a1::bigint),
  :'ta'::uuid,
  '(2) the written row names the RESOLVED tenant, equal to the impersonated session''s auth.uid()'
);

-- =====================================================================
-- LEG 3 — a service_role session that has NOT impersonated cannot write a
-- row: auth.uid() is NULL and the insert fails closed, taking the
-- transaction with it. Fails before C2 is ever reached, so the subject
-- arguments stay placeholders.
-- =====================================================================
select set_config('role', 'service_role', true);
select set_config('request.jwt.claims', '', true);
select throws_like(
  $$ select pfin.fn_emit_audit_log('monthly_report_generation', 'impersonated session: request.jwt.claims.sub', '2026-08-31', 'pfin.monthly_report', 1) $$,
  :'m_no_tenant',
  '(3) service_role with NO impersonation (auth.uid() is NULL) is refused closed — a privileged write whose tenant cannot be named is not a write anyone should keep'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 4a — RE-AIMED (Sec C2, item 7c): an invented surface_name now hits the
-- dispatch's `else` (P0001, "no C2 subject binding") BEFORE it can ever reach
-- `audit_log_surface_name_vocab` — the CHECK is unreachable through this,
-- the ONLY granted write path. A leg still matching the CHECK's name here
-- would go red; that is the fix, not a regression.
-- LEG 4b — RETIRED. `p_trigger_source` no longer exists as a parameter (Sec
-- C1 drops it entirely, derived from a GUC instead), so "an invented
-- trigger_source is refused" has no premise left to test. Not replaced by an
-- equivalent leg because there is nothing left for it to assert; leg 8 below
-- covers cron/on_demand DERIVATION instead of ARGUMENT validation.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  $$ select pfin.fn_emit_audit_log('bogus_surface', 'impersonated session: request.jwt.claims.sub', '2026-08-31', null, null) $$,
  :'m_no_binding',
  '(4a) an invented (non-blank) surface_name is refused by the DISPATCH''S OWN else -- "no C2 subject binding is defined for surface" -- fired before the table CHECK is ever reached'
);
-- Cheap, genuine coverage of the helper's OWN blank-chain guard — the field
-- the header names as "the one Decision 1 clause (d) actually asks for".
-- Fires before C2 too, so the subject stays placeholder-null.
select throws_like(
  $$ select pfin.fn_emit_audit_log('monthly_report_generation', '   ', '2026-08-31', null, null) $$,
  :'m_chain',
  '(4c) a blank tenant_resolution_chain is refused by the HELPER''s own guard'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 4d (Sec C2, item 7c's SECOND required leg) — THE CHECK ITSELF HAS NO
-- OBSERVER THROUGH THE GRANTED PATH ANY MORE (the `else` fires first), so it
-- must be observed directly: a DIRECT OWNER-PATH INSERT (postgres bypasses
-- the DEFINER helper and the ACL entirely) is what still reaches
-- `audit_log_surface_name_vocab`. Without this leg, a reader could drop the
-- CHECK believing "the else covers it" and silently lose the storability
-- floor for the owner path, which does not come through the helper at all.
-- =====================================================================
select throws_like(
  format($$ insert into pfin.audit_log (surface_name, trigger_source, tenant_resolution_chain, users_id)
              values ('bogus_surface', 'on_demand', 'owner-path direct insert', %L) $$, :'ta'),
  :'m_vocab_check',
  '(4d) a DIRECT owner-path INSERT with an invented surface_name is refused by the TABLE CHECK itself — the check''s own, still-live observer, independent of the helper''s dispatch'
);

-- =====================================================================
-- LEG 5 — authenticated holds NO table grant: a direct INSERT through
-- PostgREST is refused at the ACL, while the SAME caller succeeds through
-- the helper. Both halves required.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ insert into pfin.audit_log (surface_name, users_id, tenant_resolution_chain)
              values ('monthly_report_generation', %L, 'forged') $$, :'ta'),
  :'m_acl',
  '(5a) a DIRECT INSERT into pfin.audit_log through PostgREST is refused at the ACL — no role holds any grant on this table'
);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-05-01', '2026-05-31') returning report_id as leg5_subject \gset
select lives_ok(
  format($$ select pfin.fn_emit_audit_log('monthly_report_generation', 'impersonated session: request.jwt.claims.sub', '2026-05-31', 'pfin.monthly_report', %s) $$, :leg5_subject),
  '(5b) NON-VACUOUS: the SAME caller succeeds THROUGH the helper — distinguishing DEFINER-with-no-grant from INVOKER-with-a-grant, which is the whole security difference'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 7 — STANDING catalog assertions: (i) EXECUTE ACL exactly
-- {authenticated, service_role}; (ii) EXACTLY ONE fn_emit_audit_log exists
-- (the OLD 6-argument signature does not survive as a live overload — Sec
-- C1's `drop function` is load-bearing and invisible to a fresh scratch
-- apply, so this is the paired assertion for a database where 111 had
-- ALREADY been applied once); (iii) it takes NO p_trigger_source parameter.
-- =====================================================================
select is(
  (select array_agg(grantee::text order by grantee) from information_schema.routine_privileges
    where routine_schema = 'pfin' and routine_name = 'fn_emit_audit_log' and privilege_type = 'EXECUTE'
      and grantee <> 'postgres'),
  array['authenticated', 'service_role'],
  '(7-i) fn_emit_audit_log''s EXECUTE ACL names EXACTLY {authenticated, service_role} beyond the implicit owner — no PUBLIC, no third grantee'
);
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_emit_audit_log'),
  1,
  '(7-ii) EXACTLY ONE pfin.fn_emit_audit_log exists in pg_proc — the dropped 6-argument signature did not survive as a live overload (Sec C1: `create or replace` cannot remove a parameter, so the drop is load-bearing)'
);
select ok(
  not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_emit_audit_log'
      and 'p_trigger_source' = any(p.proargnames)
  ),
  '(7-iii) fn_emit_audit_log takes NO p_trigger_source parameter — THE ONE THAT WOULD HAVE CAUGHT THE FORGERY: trigger_source is derived, never passed'
);
select ok(
  (select prosecdef from pg_proc where oid = 'pfin.fn_emit_audit_log(text,text,date,text,bigint)'::regprocedure),
  '(7-iv) fn_emit_audit_log IS the SECURITY DEFINER function this wave adds — forced by A10''s own-session caller, realizing the long-reserved allowlist slot'
);

-- =====================================================================
-- LEG 8 (Sec C2, item 7a) — THE C2 SUBJECT-BINDING LEGS.
-- (i) STRUCTURAL PIN (see file header for the measured dblink-snapshot-
--     corruption finding that forces this downgrade): an emit naming a
--     report_id from an EARLIER, genuinely separate transaction is REFUSED
--     WITH A DISTINCT MESSAGE — confirmed by catalog inspection of the
--     function body, not by live reproduction.
-- (ii) an emit naming ANOTHER tenant's report_id is refused with the
--      not-yours message — distinct from (i), self-contained and BEHAVIOURAL
--      (both rows exist in THIS transaction, owned by different tenants, no
--      earlier-transaction trick needed at all).
-- (iii) NON-VACUOUS: an emit naming a report_id from a BARE INSERT in THIS
--       transaction, by the SAME tenant, SUCCEEDS. ⚠ This is the bare-INSERT
--       half only — the subtransaction-wrapped form (the real
--       fn_open_monthly_report_draft product path, the one a naive
--       xid-equality implementation would have refused) is proved on
--       feature/self-355-db-qa's 113 battery, which is where that function
--       actually lives; it does not exist on this branch.
-- =====================================================================
-- --- (i) EARLIER TRANSACTION — STRUCTURAL, per the file header's disclosed
-- downgrade. Pins: the CORRECT mechanism (a snapshot-visibility check) is
-- present exactly once; the refusal message this leg is about exists in the
-- body; and it is a DISTINCT string from (8-ii)'s not-yours message (Sec's
-- own requirement that the two be separately identifiable, checked here as
-- "two different strings exist" rather than "two different behaviours fire").
-- NOTE: presence checks only (>=1), not exact-count — prosrc includes this
-- function's own extensive inline commentary, which independently mentions
-- both primitives and both message families in prose (e.g. explaining WHY
-- pg_visible_in_snapshot is correct and an xid-equality check would be
-- wrong), so an exact-count or a combined "X but not Y nearby" regex is
-- fooled by the comments rather than reading the executable body.
select ok(
  (select prosrc ~ 'pg_visible_in_snapshot'
      and prosrc ~ 'pg_current_xact_id_if_assigned'
      and prosrc ~ 'was NOT written in this transaction'
     from pg_proc where oid = 'pfin.fn_emit_audit_log(text,text,date,text,bigint)'::regprocedure),
  '(8-i) STRUCTURAL (dblink-corruption downgrade, see file header): the body calls pg_visible_in_snapshot (the correct snapshot-based mechanism) and pg_current_xact_id_if_assigned, and contains the earlier-transaction refusal message'
);

-- --- (ii) OTHER TENANT (self-contained, no dblink, fully BEHAVIOURAL) ---
select _rls.set_tenant(:'tb'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-10-01', '2026-10-31') returning report_id as tb_subject \gset
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ select pfin.fn_emit_audit_log('monthly_report_generation', 'impersonated session: request.jwt.claims.sub', '2026-10-31', 'pfin.monthly_report', %s) $$, :tb_subject),
  :'m_not_yours',
  '(8-ii) an emit naming ANOTHER tenant''s report_id (tenant B''s, from tenant A''s session) is refused with the not-yours message — distinct from (8-i)''s message, per Sec''s requirement that the two be separately asserted'
);
select set_config('role', 'postgres', true);

-- --- (iii) NON-VACUOUS SUCCESS, bare INSERT in this transaction ---
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-11-01', '2026-11-30') returning report_id as leg8iii_subject \gset
select lives_ok(
  format($$ select pfin.fn_emit_audit_log('monthly_report_generation', 'impersonated session: request.jwt.claims.sub', '2026-11-30', 'pfin.monthly_report', %s) $$, :leg8iii_subject),
  '(8-iii) NON-VACUOUS: an emit naming a report_id from a BARE INSERT made earlier in THIS SAME transaction, by the SAME tenant, SUCCEEDS — C2 is not a blanket refusal'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 9 (Sec C2, item 7b) — A READ-ONLY TRANSACTION IS REFUSED (no xid
-- assigned): the fail-closed leg. STRUCTURAL, for TWO independent reasons,
-- not one: (a) it is UNTESTABLE from inside THIS file's own transaction by
-- the time any pgTAP assertion can run — `plan()` itself assigns an xid
-- (verified directly: `pg_current_xact_id_if_assigned()` is NULL before
-- `plan()` and non-NULL immediately after), so every assertion in this file
-- already has a top-level xid by construction; (b) the ONLY mechanism that
-- could otherwise produce a genuinely xid-less session mid-file — dblink —
-- is the one the file header documents as corrupting this exact function's
-- own snapshot-visibility check for the rest of the transaction. Both
-- reasons independently rule out a behavioural leg here.
-- =====================================================================
select ok(
  (select prosrc ~ 'pg_current_xact_id_if_assigned\(\) is null'
      and prosrc ~ 'this transaction has written nothing'
     from pg_proc
    where oid = 'pfin.fn_emit_audit_log(text,text,date,text,bigint)'::regprocedure),
  '(9) STRUCTURAL (untestable behaviourally from inside this file for two independent reasons — see the comment above): the body guards on pg_current_xact_id_if_assigned() IS NULL and raises naming "this transaction has written nothing"'
);

-- =====================================================================
-- LEG 10 — TWO CALLERS, ONE SHAPE: the cron row is now produced by SETTING
-- THE GUC, not by passing a value (Sec C1 removed the parameter) — this is a
-- genuine two-caller leg for the first time; passing 'cron' from the
-- battery's own argument list, as the old file did, was one caller twice.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-12-01', '2026-12-31') returning report_id as tb_cron_subj \gset
select set_config('app.report_generation_source', 'cron', true);
select pfin.fn_emit_audit_log('monthly_report_generation', 'impersonated session: request.jwt.claims.sub', '2026-12-31', 'pfin.monthly_report', :tb_cron_subj::bigint) as tb_cron \gset
-- `set_config(..., true)` is transaction-local, not statement-local — it does
-- NOT revert on its own between these two calls. Cleared explicitly so
-- (10b) actually exercises "no GUC set", not "GUC still 'cron' from (10a)"
-- (caught live: without this, (10b) read 'cron' and wanted 'on_demand').
reset app.report_generation_source;
insert into pfin.monthly_report (target_month, data_as_of) values ('2027-01-01', '2027-01-31') returning report_id as tb_ondemand_subj \gset
select pfin.fn_emit_audit_log('monthly_report_generation', 'impersonated session: request.jwt.claims.sub', '2027-01-31', 'pfin.monthly_report', :tb_ondemand_subj::bigint) as tb_ondemand \gset
select set_config('role', 'postgres', true);
select is(
  (select trigger_source from pfin.audit_log where audit_id = :tb_cron::bigint),
  'cron',
  '(10a) the row emitted with app.report_generation_source SET TO ''cron'' -> trigger_source = ''cron'' — a GENUINE two-caller leg, driven by the GUC rather than an argument'
);
select is(
  (select trigger_source from pfin.audit_log where audit_id = :tb_ondemand::bigint),
  'on_demand',
  '(10b) the row emitted with the GUC explicitly cleared after (10a) -> trigger_source = ''on_demand'''
);
select ok(
  (select r1.surface_name = r2.surface_name and r1.users_id = r2.users_id and r1.tenant_resolution_chain = r2.tenant_resolution_chain
     from pfin.audit_log r1, pfin.audit_log r2
    where r1.audit_id = :tb_cron::bigint and r2.audit_id = :tb_ondemand::bigint),
  '(10c) NON-VACUOUS: the cron row and the on-demand row are IDENTICAL on every OTHER column — trigger_source is the only thing that differs between the two callers'
);

-- =====================================================================
-- LEG 11 (Sec C1, GUC transaction-locality, "d") — the GUC is `is_local`: a
-- boundary that ends its scope (here, a SAVEPOINT rollback, which undoes a
-- transaction-local `set_config` exactly as ending a transaction would) sees
-- the DEFAULT again, without re-setting anything.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
savepoint sp_guc_locality;
select set_config('app.report_generation_source', 'cron', true);
insert into pfin.monthly_report (target_month, data_as_of) values ('2027-02-01', '2027-02-28') returning report_id as guc_subj1 \gset
select pfin.fn_emit_audit_log('monthly_report_generation', 'impersonated session: request.jwt.claims.sub', '2027-02-28', 'pfin.monthly_report', :guc_subj1::bigint) as guc_cron_id \gset
select set_config('role', 'postgres', true);
select is(
  (select trigger_source from pfin.audit_log where audit_id = :guc_cron_id::bigint),
  'cron',
  '(11a) inside the savepoint, with the GUC set, the row reads ''cron'''
);
rollback to savepoint sp_guc_locality;
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2027-02-01', '2027-02-28') returning report_id as guc_subj2 \gset
select pfin.fn_emit_audit_log('monthly_report_generation', 'impersonated session: request.jwt.claims.sub', '2027-02-28', 'pfin.monthly_report', :guc_subj2::bigint) as guc_default_id \gset
select set_config('role', 'postgres', true);
select is(
  (select trigger_source from pfin.audit_log where audit_id = :guc_default_id::bigint),
  'on_demand',
  '(11b) THE LEG: after the savepoint that set the GUC is ROLLED BACK (a boundary ending that transaction-local setting''s scope, exactly as a real second transaction would), a call WITHOUT re-setting anything reads the DEFAULT again — the GUC did not silently survive'
);

-- =====================================================================
-- LEG 12 — Sec C1's case matrix: 'CRON' (case-folded), 'cron ' (trailing
-- space), '' (empty), 'on_demand,cron' (a value containing but not equal to
-- 'cron') all yield 'on_demand' — EXACT match only, never a prefix, never
-- case-folded, never trimmed.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select set_config('app.report_generation_source', 'CRON', true);
insert into pfin.monthly_report (target_month, data_as_of) values ('2027-03-01', '2027-03-31') returning report_id as c12a \gset
select pfin.fn_emit_audit_log('monthly_report_generation', 'chain', '2027-03-31', 'pfin.monthly_report', :c12a::bigint) as c12a_id \gset
select set_config('app.report_generation_source', 'cron ', true);
insert into pfin.monthly_report (target_month, data_as_of) values ('2027-04-01', '2027-04-30') returning report_id as c12b \gset
select pfin.fn_emit_audit_log('monthly_report_generation', 'chain', '2027-04-30', 'pfin.monthly_report', :c12b::bigint) as c12b_id \gset
select set_config('app.report_generation_source', '', true);
insert into pfin.monthly_report (target_month, data_as_of) values ('2027-05-01', '2027-05-31') returning report_id as c12c \gset
select pfin.fn_emit_audit_log('monthly_report_generation', 'chain', '2027-05-31', 'pfin.monthly_report', :c12c::bigint) as c12c_id \gset
select set_config('app.report_generation_source', 'on_demand,cron', true);
insert into pfin.monthly_report (target_month, data_as_of) values ('2027-06-01', '2027-06-30') returning report_id as c12d \gset
select pfin.fn_emit_audit_log('monthly_report_generation', 'chain', '2027-06-30', 'pfin.monthly_report', :c12d::bigint) as c12d_id \gset
select set_config('role', 'postgres', true);
select is(
  (select array_agg(trigger_source order by audit_id) from pfin.audit_log where audit_id in (:c12a_id, :c12b_id, :c12c_id, :c12d_id)),
  array['on_demand', 'on_demand', 'on_demand', 'on_demand'],
  '(12) ''CRON'', ''cron '', '''', and ''on_demand,cron'' ALL yield ''on_demand'' — exact match only, never a prefix, never case-folded, never trimmed'
);

-- =====================================================================
-- LEG 6 — UPDATE / DELETE / TRUNCATE refused under both roles. MOVED HERE,
-- last, DELIBERATELY — see the file header's second measured finding: a
-- throws_like()-caught exception from a real BEFORE trigger on an
-- UPDATE/DELETE (exactly what 6a-6d need) leaves THIS transaction's own
-- pg_current_snapshot() unable to correctly attest a LATER plain top-level
-- write as "written in this transaction" — which is exactly what legs
-- 8-iii/10/11/12 need `fn_emit_audit_log`'s C2 check to get right. Running
-- leg 6 after them, not before, keeps those legs BEHAVIOURAL instead of
-- forcing a further structural-pin downgrade. Leg 6 itself needs no C2
-- success path, so its own correctness is unaffected by running last.
-- =====================================================================
select is(
  (select count(*)::int from pfin.audit_log where audit_id = :a1::bigint),
  1,
  '(6-setup) NON-VACUOUS sanity: leg 2''s row (the one 6a-6d mutate) still exists — robust to how many OTHER legs have written by this point in the file, unlike a total per-tenant count would be'
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
-- write verb's own grant).
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

select * from finish();
rollback;

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
-- ⚠⚠ RE-LEGGED A SECOND TIME AT `72c3e5c` — Sec's C2 EXPRESSION ITSELF WAS
-- UNSOUND, RULED, NOT A TEST-HARNESS LIMITATION, CORRECTING WHAT THIS HEADER
-- PREVIOUSLY SAID. An earlier version of this file diagnosed "opening a
-- dblink connection mid-transaction corrupts `pg_current_snapshot()`" as a
-- harness quirk and downgraded two legs to structural pins to route around
-- it; a second, independent-looking observation ("a caught trigger-raised
-- exception poisons the same transaction's own later writes") was treated as
-- a THIRD, separate quirk and worked around by physically reordering legs.
-- **Sec reproduced both with a matched control pair and ruled they were the
-- SAME real defect in C2's predicate — `pg_visible_in_snapshot(row.xmin::
-- text::xid8, pg_current_snapshot())` — not two harness limitations at all:**
-- **THE MECHANISM.** A transaction's own xid is NEVER listed in its own
-- snapshot's `xip` (in-progress) array — `pg_visible_in_snapshot` does not
-- special-case "is this me," only real MVCC visibility checks do that, and
-- this function did not use one. Snapshot `xmax` is effectively
-- `latestCompletedXid + 1`, and `latestCompletedXid` is CLUSTER-WIDE, not
-- transaction-local. So the moment ANY xid — belonging to anyone, not just
-- this session — completes (commits OR aborts) after our subject row's xid
-- was consumed and before we check it, `xmax` advances past that xid, and
-- since it is not in `xip`, `pg_visible_in_snapshot` misreports it as
-- already-committed rather than still-running. **This is real on a NON-IDLE
-- production database**: an aborted WRITING subtransaction of our own
-- (dblink's side effect and the caught-trigger-exception's side effect are
-- both instances of exactly this), or an ORDINARY COMMIT FROM A SECOND
-- SESSION between the write and the emit, trip it identically — no
-- exception, no trigger, no dblink required. **The consequence was never a
-- missing audit row: the emit runs inside the generation transaction, so a
-- false refusal rolls back THE WHOLE REPORT GENERATION, non-deterministically,
-- on any non-idle database — every battery passed only because a scratch DB
-- is idle.**
-- **THE FIX, at `72c3e5c`: `pg_xact_status(r.xmin::text::xid8) = 'in
-- progress'`, resolved in ONE statement together with `r.users_id`.**
-- `pg_xact_status` reads the commit log for THAT specific xid — no snapshot,
-- no cluster-wide counter, nothing that another session's activity can move.
-- It answers `'in progress'` for a row written by this transaction OR ANY OF
-- ITS SUBTRANSACTIONS (released or not), which is what the earlier
-- `xmin = pg_current_xact_id()` attempt got wrong, and `'committed'` for a
-- row from an earlier transaction — WITHOUT depending on anything
-- cluster-wide, which is what `pg_visible_in_snapshot` got wrong. ⚠⚠ **THE
-- INVARIANT THAT MAKES THIS SOUND IS A PROPERTY OF THE STATEMENT, NOT OF THE
-- PREDICATE: `'in progress'` is ALSO true for another session's own
-- in-progress transaction — the predicate does not discriminate between them
-- and was never asked to.** What discriminates is that `users_id` and the
-- transaction-status flag are resolved by THIS transaction's OWN MVCC READ,
-- IN THE SAME STATEMENT — another session's uncommitted row is invisible to
-- that read and never reaches the test at all. Splitting the read (caching
-- the row, resolving the two facts separately) breaks this coupling SILENTLY:
-- the predicate keeps returning a value and starts answering a different
-- question, correctly on an idle database and wrongly under concurrency —
-- see leg 7g below, the structural leg that watches exactly this.
-- **ANY FUTURE REPLACEMENT OF THIS EXPRESSION MUST NOT DEPEND ON
-- `latestCompletedXid`, snapshot `xmax`, OR ANY OTHER CLUSTER-WIDE COUNTER**
-- — that is the disqualifier both prior attempts failed.
--
-- ⚠⚠ STANDING RULE FOR EVERY `prosrc` ASSERTION IN THIS FILE'S BATTERY
-- (Sec): **presence/count checks on `prosrc` are VACUOUS in BOTH directions
-- here, PRECISELY BECAUSE THIS FILE'S COMMENTS ARE GOOD** — a superseded
-- primitive's name survives in the prose explaining why it was abandoned
-- (measured at `72c3e5c`: `pg_visible_in_snapshot` raw **3**, comment-stripped
-- **0**; `pg_xact_status` raw **5**, comment-stripped **1**;
-- `pg_current_xact_id_if_assigned` raw **2**, comment-stripped **1**), so a
-- legacy leg asserting the SUPERSEDED primitive goes GREEN certifying a
-- primitive the body does not use AT ALL, and a naively re-aimed leg on the
-- CURRENT primitive would pass even if the body used something else
-- entirely. A red gets investigated; a green gets trusted — which makes the
-- first case the dangerous one. **THEREFORE: strip `--` comments first
-- (`regexp_replace(prosrc, '--[^\n]*', '', 'g')`), then assert, matching
-- CASE-INSENSITIVELY (`~*` / `'gi'`)** — SQL does not care about case, so a
-- case-sensitive leg fails open on a body whose split statement happens to be
-- capitalized. `111`'s own apply-time `do $watch$` block (the one-statement
-- invariant's watcher, at the end of the migration) is the reference
-- implementation this file's own structural legs copy.
--
-- ⚠ `dblink` IS NOW A LEGITIMATE, VERIFIED-SAFE FIXTURE MECHANISM, reversing
-- this file's earlier posture. Since C2 no longer depends on ANY
-- cluster-wide snapshot state, opening/using/closing a dblink connection
-- mid-transaction no longer corrupts anything this file's own legs rely on —
-- verified directly against `72c3e5c` before writing legs 8-i and 7d below.
-- It is used ONLY to construct facts genuinely impossible from inside a
-- single wrapped, rolled-back pgTAP transaction (a row from a truly earlier,
-- separate, committed transaction). ⚠ ITS FIXTURE ROWS (a dedicated
-- synthetic tenant E, fixed UUID, no PII) ARE REAL COMMITTED WRITES THAT DO
-- NOT ROLL BACK WITH THE REST OF THIS FILE — the one disclosed departure
-- from this battery's usual all-rolls-back convention, cleaned up explicitly
-- by the leg that creates them rather than left as residue.
--
-- ⚠ LEG 6 (immutability) IS BACK IN ITS NATURAL POSITION, after leg 5. The
-- previous version of this file moved it to the end of the file as a
-- mitigation for the (mis-diagnosed) dblink/trigger-exception "poisoning" —
-- that mitigation is no longer needed once the underlying predicate is
-- sound, and reordering legs for narrative convenience rather than
-- correctness is not this battery's convention.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

-- Used ONLY by leg 8-i's earlier-transaction fixture — verified-safe under
-- the new pg_xact_status expression (file header). Legs 7d/7e's own
-- counter-advance proxy is a same-connection aborted subtransaction and
-- needs no second connection at all. create extension is transactional; it
-- does not survive this file's own rollback, matching every other schema
-- object here.
create extension if not exists dblink;

\set m_no_tenant '%no resolved tenant%'
\set m_chain '%p_tenant_resolution_chain is required%'
\set m_acl '%permission denied for table audit_log%'
\set m_immut '%is immutable%'
\set m_truncate '%TRUNCATE blocked%'
\set m_no_binding '%no C2 subject binding is defined for surface%'
\set m_vocab_check '%audit_log_surface_name_vocab%'
\set m_bad_subject '%requires p_subject_table%'
\set m_not_yours '%is not a row belonging to the tenant%'
\set m_not_written '%was NOT written in this transaction%'

select plan(36);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset
insert into auth.users (id) values (:'ta'), (:'tb');
-- Tenant E is a THIRD synthetic tenant, used ONLY by the dblink-fixture legs
-- below (8-i, 7d). It is deliberately NOT inserted into auth.users here — a
-- dblink connection is a SEPARATE session that cannot see this transaction's
-- own uncommitted rows, so tenant E's auth.users row is created (and
-- committed) entirely THROUGH the dblink connection instead, at the point of
-- use. Its id is fixed and synthetic; no PII, no real account numbers.
\set te '00000000-0000-0000-0000-00000000000e'

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
-- LEG 4e/4f (Sec FLAG-3) — C2 GUARD (b) HAS NO OTHER OBSERVER. p_subject_table
-- is written VERBATIM into the row (see the INSERT below guard (c)), so this
-- guard is the ONLY thing standing between a caller holding EXECUTE and a
-- FORGED LOCATOR on an emit that is valid in every other respect: real
-- subject row, own tenant, this transaction. `\set m_bad_subject` above was
-- declared and never referenced across the re-leg for 72c3e5c — the tell
-- that this leg was lost. The guard is a DISJUNCTION (`p_subject_table is
-- distinct from ... or p_subject_id is null`), so BOTH branches are asserted
-- separately — one leg alone leaves the other branch unwatched. Reachability
-- checked against the body's own guard order (111 migration L749-772): (a)
-- xid-assigned fires first and passes, because the `insert into
-- pfin.monthly_report` below IS a write in this same transaction, giving it
-- an assigned xid; guard (b) fires next and refuses. Neither leg reaches
-- guard (c), so neither depends on the C2 subject-resolution predicate FLAG-2
-- discusses.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of)
  values ('2028-01-01', '2028-01-31') returning report_id as leg4e_subj \gset
select throws_like(
  format($$ select pfin.fn_emit_audit_log('monthly_report_generation', 'impersonated session: request.jwt.claims.sub', '2028-01-31', 'pfin.account', %s) $$, :leg4e_subj),
  :'m_bad_subject',
  '(4e) THE LEG: a REAL, OWN, same-transaction report_id submitted with a FORGED p_subject_table is refused by C2 guard (b) — the column is written verbatim into the row, so without this guard an otherwise-valid emit records a locator pointing at a table the write never touched'
);
select throws_like(
  $$ select pfin.fn_emit_audit_log('monthly_report_generation', 'impersonated session: request.jwt.claims.sub', '2028-01-31', 'pfin.monthly_report', null) $$,
  :'m_bad_subject',
  '(4f) the NULL p_subject_id half of the SAME disjunctive guard, asserted separately — a caller supplying the correct table but omitting the id is refused by the same guard, not silently coerced'
);
select set_config('role', 'postgres', true);

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
-- LEG 6 — UPDATE / DELETE / TRUNCATE refused under both roles.
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
-- LEG 7d (Sec, REQUIRED WHATEVER EXPRESSION IS IN PLACE) — THE
-- COUNTER-ADVANCE LEG: advance `latestCompletedXid` between the subject
-- write and the emit, and assert the emit STILL SUCCEEDS. This is the leg
-- whose absence let the superseded expression survive review — a scratch DB
-- is idle, so every OTHER leg here passes regardless of whether C2 depends
-- on cluster-wide state. T1 is the faithful proxy: an ABORTED WRITING
-- subtransaction between the write and the emit (no second connection or
-- dblink needed — a savepoint with a real INSERT, then ROLLBACK TO
-- SAVEPOINT, consumes and completes an xid exactly as a caught trigger
-- exception or a caught unique_violation would). T2 is its MATCHED NEGATIVE
-- CONTROL: the identical shape with NO write inside the aborted
-- subtransaction. Both are asserted, not just T1 — the pair is what
-- identifies xid consumption as the cause rather than "exceptions" in
-- general (verified directly against the superseded expression before this
-- rework: T1 failed, T2 passed — the exact signature of the bug this leg
-- exists to catch).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2027-07-01', '2027-07-31') returning report_id as d7_t1_subj \gset
savepoint sp_d7_t1;
insert into pfin.monthly_report (target_month, data_as_of) values ('2027-08-01', '2027-08-31');
rollback to savepoint sp_d7_t1;
select lives_ok(
  format($$ select pfin.fn_emit_audit_log('monthly_report_generation', 'impersonated session: request.jwt.claims.sub', '2027-07-31', 'pfin.monthly_report', %s) $$, :d7_t1_subj),
  '(7d-T1) THE LEG: an ABORTED WRITING subtransaction between the write and the emit does NOT cause a false refusal — the faithful single-connection proxy for "any xid completes between write and emit," which is the real, cluster-wide shape of the defect this leg exists to catch'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2027-09-01', '2027-09-30') returning report_id as d7_t2_subj \gset
savepoint sp_d7_t2;
do $$ begin raise exception 'no write, just abort — the matched negative control'; exception when others then null; end $$;
rollback to savepoint sp_d7_t2;
select lives_ok(
  format($$ select pfin.fn_emit_audit_log('monthly_report_generation', 'impersonated session: request.jwt.claims.sub', '2027-09-30', 'pfin.monthly_report', %s) $$, :d7_t2_subj),
  '(7d-T2) MATCHED NEGATIVE CONTROL: a NON-WRITING aborted subtransaction in the identical slot also succeeds (trivially, under a sound expression) — asserted alongside T1 so the pair, not either leg alone, is what pins xid consumption (not "any exception") as the mechanism'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 7e — BOTH SUB-COMMIT SHAPES: a write that completes inside a
-- subtransaction WITHOUT aborting (a "sub-commit") still permits the emit.
-- (i) an explicit SAVEPOINT ... RELEASE around the write. (ii) THE
-- PRODUCTION SHAPE: a write inside a plpgsql `begin ... exception ... end`
-- block that exits NORMALLY (no exception raised) — sub-commits the same
-- way and is what `fn_open_monthly_report_draft` (113, feature/self-355-db)
-- actually does on its winning (non-colliding) path.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
savepoint sp_e7i;
insert into pfin.monthly_report (target_month, data_as_of) values ('2027-10-01', '2027-10-31') returning report_id as e7i_subj \gset
release savepoint sp_e7i;
select lives_ok(
  format($$ select pfin.fn_emit_audit_log('monthly_report_generation', 'impersonated session: request.jwt.claims.sub', '2027-10-31', 'pfin.monthly_report', %s) $$, :e7i_subj),
  '(7e-i) a write inside an explicit SAVEPOINT that is then RELEASED (not rolled back) — a sub-commit, not an abort — still permits the emit'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
do $$
declare v_id bigint;
begin
  insert into pfin.monthly_report (target_month, data_as_of) values ('2027-11-01', '2027-11-30') returning report_id into v_id;
  perform set_config('audit_test.e7ii_subj', v_id::text, true);
exception when unique_violation then
  raise;
end $$;
select current_setting('audit_test.e7ii_subj')::bigint as e7ii_subj \gset
select lives_ok(
  format($$ select pfin.fn_emit_audit_log('monthly_report_generation', 'impersonated session: request.jwt.claims.sub', '2027-11-30', 'pfin.monthly_report', %s) $$, :e7ii_subj),
  '(7e-ii) THE PRODUCTION SHAPE: a write inside a plpgsql exception block that exits NORMALLY — exactly what fn_open_monthly_report_draft (113) does on its winning path — still permits the emit'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- ⚠ LEG 7f — NOT A LEG, AND THIS LIST MUST NOT IMPLY OTHERWISE: another
-- session's UNCOMMITTED row is refused STRUCTURALLY BY MVCC, not by any
-- assertion in this file. `pg_xact_status` returns 'in progress' for that
-- row too — what excludes it is that THIS transaction's own read (the
-- one-statement invariant, see leg 7g) never resolves it at all, because an
-- uncommitted row from another session is invisible to an ordinary MVCC
-- read. The case is UNBUILDABLE in a single-connection pgTAP battery, so no
-- leg can cover it and none should be written to look as though it does.
-- Recorded here so a reader of this list does not infer coverage that
-- cannot exist. What WOULD falsify it is not a test but an edit — see 7g.
-- =====================================================================

-- =====================================================================
-- LEG 7g — THE ONE-STATEMENT INVARIANT, AS A STRUCTURAL LEG ON THE
-- INSTALLED DEFINITION. Strip `--` comments from `pg_proc.prosrc` and assert
-- EXACTLY ONE executable `from pfin.monthly_report` in fn_emit_audit_log's
-- body (case-insensitive: SQL doesn't care about case, so a case-sensitive
-- leg fails open on a split whose second read happens to be written `FROM`
-- — measured, see below). ⚠ WHY THIS LEG SPECIFICALLY: splitting the
-- one-statement read behaves CORRECTLY on an idle database and diverges
-- only under concurrency — no behavioural leg in this file, including 7d
-- above, can distinguish a correct body from a split one, because neither
-- this file nor a scratch DB is ever concurrent with itself. This is a
-- STRUCTURAL leg watching the INSTALLED definition (the migration's own
-- apply-time `do $watch$` block watches only THIS migration's edits; a
-- LATER migration re-creating the function is outside that watcher's scope
-- but inside this one's).
-- ⚠⚠ INVERSION-PROVEN, NOT ASSERTED GREEN (Sec) — verified directly against
-- three bodies on scratch clones before landing this leg, matching the
-- migration's own measured counts exactly: the CORRECT body (stripped
-- count 1, this leg passes silently); a split written in LOWERCASE (`from`
-- twice — stripped count 2, RED); and a split whose SECOND read is written
-- `FROM` (stripped count 2 case-insensitively — RED — but case-SENSITIVE
-- count 1, which would have WRONGLY PASSED — the reason `~*`/`'gi'` is not
-- cosmetic here, matching DevOps's own C3 prosrc scanner convention).
-- =====================================================================
select ok(
  (select count(*) = 1
     from regexp_matches(
            (select regexp_replace(prosrc, '--[^\n]*', '', 'g') from pg_proc
              where oid = 'pfin.fn_emit_audit_log(text,text,date,text,bigint)'::regprocedure),
            'from\s+pfin\.monthly_report', 'gi')),
  '(7g) THE ONE-STATEMENT INVARIANT: EXACTLY ONE executable, comment-stripped, case-insensitive `from pfin.monthly_report` read in the installed body — inversion-proven on three bodies (correct / lowercase split / FROM split) before landing, see comment above'
);

-- =====================================================================
-- LEG 8 (Sec C2, item 7a) — THE C2 SUBJECT-BINDING LEGS, ALL THREE NOW
-- BEHAVIOURAL. `dblink` is verified-safe under the new expression (file
-- header) and is used here to construct the ONE fact genuinely impossible
-- from inside a single wrapped, rolled-back transaction: a row from a truly
-- earlier, separate, COMMITTED transaction.
-- (i) an emit naming a report_id from an EARLIER, genuinely separate
--     transaction (tenant E, via dblink) is REFUSED WITH A DISTINCT MESSAGE.
-- (ii) an emit naming ANOTHER tenant's report_id is refused with the
--      not-yours message — distinct from (i), self-contained and BEHAVIOURAL
--      (both rows exist in THIS transaction, owned by different tenants, no
--      earlier-transaction trick needed at all).
-- (iii) NON-VACUOUS: an emit naming a report_id from a BARE INSERT in THIS
--       transaction, by the SAME tenant, SUCCEEDS. ⚠ This is the bare-INSERT
--       half only — the subtransaction-wrapped form (the real
--       fn_open_monthly_report_draft product path) is proved on
--       feature/self-355-db-qa's 113 battery, which is where that function
--       actually lives; it does not exist on this branch. Legs 7d/7e above
--       cover the subtransaction shape self-contained, without needing that
--       function.
-- =====================================================================
-- --- (i) EARLIER TRANSACTION, via dblink (verified-safe, see file header) ---
select dblink_connect('conn111i', format('dbname=%s host=%s port=%s user=postgres password=postgres', current_database(), inet_server_addr(), inet_server_port()));
select * from dblink('conn111i', format($$ insert into auth.users (id) values ('%s') $$, :'te')) as t(x text);
select * from dblink('conn111i', format($$
  select set_config('role', 'authenticated', false);
  select set_config('request.jwt.claims', json_build_object('sub', '%s', 'role', 'authenticated')::text, false);
$$, :'te')) as t(x text);
select * from dblink('conn111i', $$
  insert into pfin.monthly_report (target_month, data_as_of) values ('2027-12-01', '2027-12-31') returning report_id
$$) as t(report_id bigint) \gset
select dblink_disconnect('conn111i');
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'te'::uuid);
select throws_like(
  format($$ select pfin.fn_emit_audit_log('monthly_report_generation', 'impersonated session: request.jwt.claims.sub', '2027-12-31', 'pfin.monthly_report', %s) $$, :report_id),
  :'m_not_written',
  '(8-i) BEHAVIOURAL (dblink, verified-safe under pg_xact_status — see file header): an emit naming a report_id from a GENUINELY earlier, separate, COMMITTED transaction is refused with the earlier-transaction message, distinct from (8-ii)''s not-yours message'
);
select set_config('role', 'postgres', true);
-- Cleanup: tenant E's dblink-committed rows do NOT roll back with the rest
-- of this file (see file header) — removed explicitly rather than left as
-- residue in whatever database this battery runs against.
select dblink_connect('conn111i_cleanup', format('dbname=%s host=%s port=%s user=postgres password=postgres', current_database(), inet_server_addr(), inet_server_port()));
select * from dblink('conn111i_cleanup', format($$ delete from auth.users where id = '%s' $$, :'te')) as t(x text);
select dblink_disconnect('conn111i_cleanup');

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
-- assigned): the fail-closed leg. STILL STRUCTURAL — but RE-DERIVED here,
-- not carried forward: the previous version of this file gave TWO reasons,
-- and the second ("dblink corrupts the snapshot") is now known to be a
-- mis-diagnosis of the real, now-fixed defect and does not survive. THE ONE
-- REASON THAT DOES SURVIVE, UNCHANGED BY EITHER REWORK: `plan()` itself
-- unconditionally assigns this transaction a top-level xid before any leg
-- in this file can run (verified directly: `pg_current_xact_id_if_assigned()`
-- is NULL immediately before `plan()` and non-NULL immediately after), so a
-- genuinely xid-less state in THIS SESSION'S OWN transaction is unreachable
-- from any leg here — dblink or not, since dblink is a SEPARATE session and
-- cannot affect this session's own xid-assignment history either way. This
-- is the one guard in the function that this rework left untouched (it is
-- part of the C1 fail-closed-first check, not the C2 subject-resolution
-- predicate that changed), so its structural check needs no re-aiming to a
-- new primitive — only the standing comment-stripping rule, applied for
-- consistency with every other prosrc assertion in this file.
-- =====================================================================
select ok(
  (select regexp_replace(prosrc, '--[^\n]*', '', 'g') ~* 'pg_current_xact_id_if_assigned\(\)\s+is\s+null'
      and regexp_replace(prosrc, '--[^\n]*', '', 'g') ~* 'this transaction has written nothing'
     from pg_proc
    where oid = 'pfin.fn_emit_audit_log(text,text,date,text,bigint)'::regprocedure),
  '(9) STRUCTURAL, RE-DERIVED (see comment above): untestable behaviourally because plan() itself assigns this transaction''s xid before any leg can run, independent of dblink or the C2 predicate that changed. Comment-stripped, case-insensitive: the body guards on pg_current_xact_id_if_assigned() IS NULL and raises naming "this transaction has written nothing"'
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

select * from finish();
rollback;

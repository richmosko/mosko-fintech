-- =====================================================================
-- Per-Wave battery — pfin.account_trans immutability + matched-account (SELF-189 / 004)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/004_account_trans_immutable.sql
--   - pfin.account_trans                       (RLS enabled, NO policies = default-deny-all;
--                                               NO table GRANT to authenticated — fenced-but-
--                                               inaccessible until SELF-190)
--   - pfin.fn_account_trans_block_mutation()    (BEFORE UPDATE OR DELETE; raise — RT-18 cross-tier
--                                               immutability fence; INVOKER)
--   - pfin.fn_account_trans_matched_account()   (BEFORE INSERT WHEN replaces_trans_id IS NOT NULL;
--                                               Decision-3 2nd instance; INVOKER)
--   - pfin.fn_account_trans_block_truncate()    (BEFORE TRUNCATE, STATEMENT-level; raise — closes the
--                                               TRUNCATE bypass of the row-level fence; Sec 2nd-review catch)
-- Reuses the SELF-187 idiom: \ir verbs, \gset literals, throws_like message-precision.
--
-- ┌─ CROSS-TIER LAYERING (the RT-18 point — WHY each role hits a DIFFERENT message) ─┐
-- │ The table is RLS default-deny-all AND has no GRANT to authenticated. So:         │
-- │  • authenticated UPDATE/DELETE fail at the TABLE ACL ('permission denied for     │
-- │    table account_trans') — the per-row immutability trigger is NEVER reached     │
-- │    (no grant; and even with a grant, RLS default-deny filters every row → 0 rows │
-- │    → BEFORE-ROW trigger never fires). Asserting the immutability MESSAGE under   │
-- │    authenticated would be a false-RED. The honest assertion is the ACL denial.   │
-- │  • service_role BYPASSES RLS (but NOT triggers). With the table grant held open  │
-- │    (test setup below — the "grant-then-trigger" analogue of the README's grant-  │
-- │    then-RLS discipline), the UPDATE/DELETE reaches the trigger, which RAISES.    │
-- │    THIS is the load-bearing cross-tier fence: RLS-default-deny alone would NOT   │
-- │    catch a privileged RLS-bypassing mutation — only the trigger does.            │
-- └──────────────────────────────────────────────────────────────────────────────────┘
--   (Divergence from the brief's literal wording is intentional and is the 42501/
--    message-precision discipline applied — see report.)
--
-- 42501/Pxxxxx-PRECISION (per the SELF-187 lesson): the immutability raise and the
--   matched-account raise are DISTINCT messages (both P0001, raise_exception); the
--   ACL denial is 42501. throws_like matches the SPECIFIC message so one fence can
--   never pass for another:
--     immutability  -> 'pfin.account_trans is immutable%<OP> blocked%'  (<OP> = UPDATE/DELETE
--                      row-level; TRUNCATE statement-level — same prefix, distinct verb clause)
--     matched-acct  -> 'cross-account reverse-and-replace rejected%'
--     ACL denial    -> 'permission denied for table account_trans'
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (b)/(c-svc)/(e) -> RED if fn_account_trans_block_mutation (or its trigger) were
--                      removed: the service_role UPDATE/DELETE would SUCCEED (no throw).
--   (f)             -> RED if fn_account_trans_matched_account (or its trigger) were
--                      removed: the cross-account reverse INSERT would SUCCEED.
--   (a)/(c-auth)    -> RED if a write grant were opened to authenticated absent a
--                      policy (the denial message would change / the write would 0-row).
--   (d)/(g)         -> non-vacuous positives: prove INSERT (incl. valid same-account
--                      reverse) is NOT blocked — guards an over-broad block trigger.
--   (h)             -> RED if fn_account_trans_block_truncate (or its statement-level
--                      trigger) were removed: TRUNCATE as the owner would SUCCEED.
--
-- DEFERRED (DO NOT FAKE) — SELF-187's deferred assertion (ii): "tenant B blocked from
--   A's account_trans via the account_users.rd_access-JOIN read path" stays DEFERRED
--   to SELF-190. account_trans has NO SELECT policy here (default-deny-all), so the
--   rd_access-JOIN read path does not yet exist — there is nothing real to assert.
--   It lands in SELF-190's battery (same PR as the JOIN policies), not faked here.
--
-- POSTURE: synthetic only — fixed-UUID tenant; NO PII / real account numbers / prod
--   data. account_trans rows are seeded via the PRIVILEGED (postgres) session because
--   the table is default-deny-all (no authenticated INSERT path until SELF-190).
--
-- ⟦WIRE-VALIDATE⟧ (per team-lead's explicit ask): the cross-tier (b)/(c-svc)/(e)
--   assertions depend on `service_role` (i) existing in the test stack, (ii) having
--   BYPASSRLS, and (iii) being able to run pgTAP fns. We grant service_role table
--   access in-test (rolled back) to isolate the trigger as the gate. If the role name
--   differs or it lacks BYPASSRLS (→ RLS default-deny would 0-row the UPDATE and the
--   trigger would never fire), THIS is the adjustment point. RED-until-004-applied is
--   expected (W3-A grounding).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(9);

-- Resolve the fixed tenant UUID to a psql literal while privileged (role=postgres).
select _rls.tenant_a() as ta \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed; the only INSERT path here).
-- One tenant owning TWO accounts (matched-account fence is per-ACCOUNT, not per-tenant),
-- then one committed transaction in each. account.users_id is set explicitly (auth.uid()
-- is NULL under postgres; superuser bypasses the account WITH CHECK). The 003 creator-
-- grant trigger fires harmlessly on each account INSERT.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-1', 'depository', 'household', 'taxable')
  returning account_id as acct1 \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-2', 'depository', 'household', 'taxable')
  returning account_id as acct2 \gset

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:acct1, '2026-01-15', 100, 'v1', 'committed original in acct-1')
  returning trans_id as t1 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:acct2, '2026-01-16', 200, 'v2', 'committed original in acct-2')
  returning trans_id as t2 \gset

-- Hold the table ACL OPEN to service_role (test setup, rolled back) so the immutability
-- TRIGGER — not a missing grant — is the only thing that can stop a service_role write.
grant usage on schema pfin to service_role;
grant select, update, delete on pfin.account_trans to service_role;

-- =====================================================================
-- (d) / (g) — INSERT is NOT blocked (privileged session). Non-vacuous positives.
-- =====================================================================
-- (d) a normal append succeeds.
select lives_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
              values (%s, '2026-02-01', 50, 'v3', 'normal append') $$, :acct1),
  '(d) normal INSERT into account_trans succeeds (block trigger is UPDATE/DELETE-only)'
);
-- (d-reverse)/(g) a reverse row with a valid SAME-account replaces_trans_id succeeds
--   (matched-account fence accepts in-account replacement — companion to (f)).
select lives_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, is_reverse, replaces_trans_id)
              values (%s, '2026-02-02', -100, true, %s) $$, :acct1, :t1),
  '(d/g) reverse INSERT with a SAME-account replaces_trans_id succeeds (matched-account fence accepts in-account replacement)'
);

-- =====================================================================
-- (f) — matched-account fence REJECTS cross-account reverse-and-replace.
--       account_id=acct-1 but replaces_trans_id points at acct-2's transaction.
-- =====================================================================
select throws_like(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, is_reverse, replaces_trans_id)
              values (%s, '2026-02-03', -100, true, %s) $$, :acct1, :t2),
  'cross-account reverse-and-replace rejected%',
  '(f) Decision-3 matched-account: cross-account replaces_trans_id REJECTED (distinct from the immutability fence)'
);

-- =====================================================================
-- (a) / (c-auth) — authenticated tier is fully fenced at the TABLE ACL.
--       (No grant + RLS default-deny -> permission denied; the immutability trigger
--        is never reached under authenticated — see the layering note above.)
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);  -- role=postgres here -> ok; flips to authenticated
select throws_like(
  format($$ update pfin.account_trans set amount = 999 where trans_id = %s $$, :t1),
  'permission denied for table account_trans',
  '(a) authenticated UPDATE fails closed at the table ACL (default-deny-all; no write grant until SELF-190)'
);
select throws_like(
  format($$ delete from pfin.account_trans where trans_id = %s $$, :t1),
  'permission denied for table account_trans',
  '(c-auth) authenticated DELETE fails closed at the table ACL (default-deny-all)'
);
select set_config('role', 'postgres', true);  -- restore privileged context

-- =====================================================================
-- (b) / (e) / (c-svc) — THE CROSS-TIER FENCE. service_role bypasses RLS and holds the
--   (test-granted) table privilege, so the ONLY remaining gate is the trigger. It
--   RAISES on UPDATE (incl. created_at) and DELETE — proving RLS-default-deny alone is
--   insufficient and the trigger is what closes the privileged-context immutability gap.
-- =====================================================================
select set_config('role', 'service_role', true);  -- role=postgres -> service_role (superuser session can SET ROLE)
-- (b) the load-bearing assertion: privileged, RLS-bypassing UPDATE is stopped by the trigger.
select throws_like(
  format($$ update pfin.account_trans set amount = 999 where trans_id = %s $$, :t1),
  'pfin.account_trans is immutable%UPDATE blocked%',
  '(b) CROSS-TIER: service_role UPDATE blocked by the immutability TRIGGER (RLS-bypass does NOT bypass the trigger)'
);
-- (e) created_at is immutable post-INSERT — same fence (Lock 15 mod #1).
select throws_like(
  format($$ update pfin.account_trans set created_at = now() where trans_id = %s $$, :t1),
  'pfin.account_trans is immutable%UPDATE blocked%',
  '(e) created_at cannot be changed: service_role UPDATE of created_at blocked by the immutability trigger'
);
-- (c-svc) the cross-tier DELETE half.
select throws_like(
  format($$ delete from pfin.account_trans where trans_id = %s $$, :t1),
  'pfin.account_trans is immutable%DELETE blocked%',
  '(c-svc) CROSS-TIER: service_role DELETE blocked by the immutability TRIGGER'
);
select set_config('role', 'postgres', true);  -- restore before (h) + finish()

-- =====================================================================
-- (h) — TRUNCATE is fenced too (statement-level trigger; Sec 2nd-review catch).
--   Row-level UPDATE/DELETE triggers do NOT fire on TRUNCATE — it goes through the
--   STATEMENT-level BEFORE TRUNCATE trigger fn_account_trans_block_truncate. Run as
--   postgres (the OWNER — definitely holds TRUNCATE privilege + bypasses RLS) so the
--   statement-level trigger is the SOLE gate: if that trigger were removed the
--   TRUNCATE would succeed -> RED. (Under service_role the migration's REVOKE TRUNCATE
--   would deny at the ACL — that would NOT catch trigger removal, so postgres is the
--   correct role here.) Message matched against the authored 004 text — DISTINCT from
--   the row-level 'UPDATE blocked'/'DELETE blocked' fence.
-- =====================================================================
-- CASCADE is REQUIRED as of 005: reconciliation_event_trans.account_trans_id now adds an
-- inbound FK on account_trans, so a plain TRUNCATE trips Postgres's FK-guard ('cannot
-- truncate a table referenced in a foreign key constraint') BEFORE the statement-trigger
-- fires. CASCADE bypasses the guard and includes the referencing table; account_trans (the
-- TARGET) is first in the truncation set, so its BEFORE TRUNCATE trigger fires first and
-- raises -> the message stays precise. (Same FK-guard-then-trigger cross-tier layering the
-- 005 battery documents; 005 introduced the FK, so this PR fixes the regression here.)
select throws_like(
  $$ truncate pfin.account_trans cascade $$,
  'pfin.account_trans is immutable%TRUNCATE blocked%',
  '(h) TRUNCATE (CASCADE past the 005 inbound-FK guard) blocked by the statement-level immutability TRIGGER (bulk audit-wipe path fenced; distinct from the row-level UPDATE/DELETE fence)'
);

select * from finish();
rollback;

-- =====================================================================
-- Per-Wave battery — pfin.reconciliation_event family append-only + matched-account
--   (SELF-188 / 005 — V1-SHIP-BLOCK)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/005_reconciliation_event_family.sql
--   - pfin.reconciliation_event             (append-only RLS: SELECT rd_access-JOIN,
--                                            INSERT wr_access-JOIN; dimension-shape CHECK)
--   - pfin.holdings_checkpoint              (SUBSTRATE: SELECT rd_access-JOIN only; NO
--                                            authenticated INSERT path in V1.0)
--   - pfin.reconciliation_event_trans       (append-only join; RLS via PARENT event
--                                            FK-chain; Decision-3 matched-account fence)
--   - pfin.fn_reconciliation_family_block_mutation()  (BEFORE UPDATE OR DELETE row-level;
--                                            raise — RT-17 cross-tier immutability; INVOKER)
--   - pfin.fn_reconciliation_family_block_truncate()  (BEFORE TRUNCATE statement-level;
--                                            raise — closes the TRUNCATE bypass; INVOKER)
--   - pfin.fn_reconciliation_event_trans_matched_account()  (BEFORE INSERT; Decision-3
--                                            ALREADY-CATALOGUED instance realized here; INVOKER)
-- Reuses the SELF-187/189 idiom: \ir verbs, \gset literals, throws_like message-precision.
--
-- ┌─ SCOPE — RT-17 FULLY; RT-16 SUBSTRATE-SLICE ONLY ────────────────────────────────┐
-- │ RT-17 (append-only audit-class immutability + matched-account) is covered in full │
-- │ here. RT-16 (cost-basis-cascade / write-skew) is the DEFERRED slice: the cascade   │
-- │ (SELECT ... FOR UPDATE row-lock on holdings_checkpoint during the composition walk)│
-- │ lands at V1.3 WITH the cascade writer (blocked on deferred account_trans investment│
-- │ columns + no securities-master + no eod_price). This file authors NO cascade /     │
-- │ FOR-UPDATE / write-skew tests; 005's RT-16 coverage is the append-only SUBSTRATE   │
-- │ slice only. Those tests land in the V1.3 usage-wave battery (same PR as the writer).│
-- └────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ CROSS-TIER LAYERING (WHY each role hits a DIFFERENT message) ────────────────────┐
-- │ append-only tables carry RLS SELECT/INSERT policies (+ SELECT/INSERT grants) but   │
-- │ NO UPDATE/DELETE policy or grant. So per role:                                      │
-- │  • authenticated UPDATE/DELETE fail at the TABLE ACL ('permission denied for table │
-- │    <t>') — no write grant; the row-level immutability trigger is never reached.     │
-- │    (holdings_checkpoint: authenticated holds SELECT only, so INSERT also ACL-fails.)│
-- │  • service_role BYPASSES RLS but NOT triggers. With the table grant held OPEN in    │
-- │    test setup (rolled back), a service_role UPDATE/DELETE reaches the row-level     │
-- │    trigger, which RAISES. THIS is the load-bearing cross-tier fence — RLS-default   │
-- │    alone would NOT catch a privileged RLS-bypassing mutation; only the trigger does.│
-- │  • TRUNCATE runs through the STATEMENT-level trigger only (row-level triggers do    │
-- │    NOT fire on TRUNCATE). Exercised as the OWNER (postgres — holds TRUNCATE +       │
-- │    bypasses RLS) so the statement-level trigger is the SOLE gate: remove it and the │
-- │    TRUNCATE succeeds -> RED. (service_role would ACL-deny on REVOKE TRUNCATE, which │
-- │    would NOT catch trigger removal — so postgres is the correct role, per 004 (h).) │
-- └────────────────────────────────────────────────────────────────────────────────────┘
--
-- MESSAGE-PRECISION (per the 004 false-green lesson — all-42501 ambiguity is a vacuous
--   green; match the SPECIFIC message so one fence can never pass for another). The
--   triple-fence embeds tg_table_name + tg_op so raises are PER-TABLE-DISTINCT:
--     row immutability -> 'pfin.<t> is immutable%<OP> blocked%'   (<OP> = UPDATE/DELETE)
--     truncate fence    -> 'pfin.<t> is immutable%TRUNCATE blocked%'
--     matched-account   -> 'cross-account reconciliation link rejected%'
--     ACL denial        -> 'permission denied for table <t>'
--     RLS WITH CHECK     -> 'new row violates row-level security policy%for table "<t>"'
--     dimension CHECK    -> '...violates check constraint "reconciliation_event_dimension_shape"'
--
-- ┌─ D3 MATCHED-ACCOUNT — WHY EXERCISED PRIVILEGED (postgres), NOT authenticated ─────┐
-- │ fn_reconciliation_event_trans_matched_account is SECURITY INVOKER and reads        │
-- │ pfin.account_trans. account_trans is default-deny-all with NO authenticated grant  │
-- │ until SELF-190 — so under authenticated the trigger's account_trans read ACL-fails  │
-- │ (fail-closed; see the (24) FINDING note below). The AUTHORITATIVE matched-account   │
-- │ check therefore runs under a privileged / RLS-bypassed context — so the cross-      │
-- │ account-REJECT and same-account-ACCEPT assertions run as postgres, mirroring 004's  │
-- │ fn_account_trans_matched_account (f)/(d-reverse).                                    │
-- └────────────────────────────────────────────────────────────────────────────────────┘
--
-- ⚑ (24) FINDING for team-lead/Sec (fail-closed either way; NOT a defect, DOC nuance).
--   The migration header prose says an authenticated link "returns nothing -> NOT EXISTS
--   -> raise" (the cross-account raise). In fact, because authenticated holds NO grant on
--   account_trans (004 posture), the INVOKER trigger's account_trans read raises
--   'permission denied for table account_trans' at the TABLE ACL — it never reaches the
--   NOT-EXISTS branch. Both fail closed; the LAYER differs (ACL, not the matched-account
--   raise). Assertion (24) asserts the ACTUAL behavior (ACL denial). When SELF-190 grants
--   account_trans SELECT, the matched-account semantics take over and (24) must be
--   revisited in that wave's battery. Routing to Sec as a Sec-load-bearing-surface note.
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   immut svc UPDATE/DELETE -> RED if the row-level block trigger were removed (privileged
--                              RLS-bypassing mutation would SUCCEED).
--   immut TRUNCATE          -> RED if the statement-level block trigger were removed
--                              (owner TRUNCATE would wipe the immutable ledger).
--   immut auth UPD/DEL/INS  -> RED if any authenticated write grant were opened absent a
--                              policy (denial message changes / write 0-rows silently).
--   D3 negative             -> RED if the matched-account trigger were removed (cross-
--                              account link would commit). D3 positive = non-vacuous control.
--   rls owner/cross reads   -> RED if RLS on the table were dropped/widened (intruder sees
--                              owner rows / owner sees nothing).
--   rls INSERT wr_access     -> RED if the INSERT WITH CHECK were removed (cross-account
--                              event INSERT commits).
--   substrate INSERT deny    -> RED if an authenticated INSERT grant/policy were added to
--                              holdings_checkpoint before its V1.3 writer + DP-4 posture.
--   dimension CHECK          -> RED if the dimension-shape CHECK were dropped/loosened.
--
-- POSTURE (SECURITY §4.5): synthetic only — fixed-UUID tenants from _rls.tenant_a()/_b();
--   NO PII / NO real account numbers / NO prod data. reconciliation_event / holdings_
--   checkpoint / link rows are seeded via the PRIVILEGED (postgres) session (append-only
--   INSERT is unblocked; the matched-account fence is authoritative under postgres).
--
-- ⟦WIRE-VALIDATE⟧ (mirrors 004): the cross-tier service_role assertions depend on
--   `service_role` (i) existing, (ii) having BYPASSRLS, (iii) able to run pgTAP fns. We
--   grant service_role table access in-test (rolled back) to isolate the trigger as the
--   gate. RED-until-005-applied is expected. §10: ledger UNCHANGED at 2 (RT-22 + RT-26);
--   Decision-3 family UNCHANGED at 7 (this realizes the ALREADY-CATALOGUED instance).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(31);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres),
-- so NO _rls.* call ever runs under the switched-to authenticated role.
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed; INSERT path here).
-- Tenant A owns acct-A; Tenant B owns acct-B. account.users_id is set explicitly
-- (auth.uid() is NULL under postgres). The 003 AFTER-INSERT DEFINER creator-grant
-- trigger fires on each account INSERT -> account_users(acct, owner, rd=t, wr=t),
-- which is exactly the rd_access/wr_access-JOIN state the 005 RLS policies key on.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-A', 'investment', 'household', 'taxable')
  returning account_id as accta \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'acct-B', 'investment', 'household', 'taxable')
  returning account_id as acctb \gset

-- account_trans: two in acct-A, one in acct-B (matched-account fence is per-ACCOUNT).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-01-15', 100, 'vA1', 'acct-A trans 1')
  returning trans_id as transa1 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-01-16', 200, 'vA2', 'acct-A trans 2')
  returning trans_id as transa2 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:acctb, '2026-01-17', 300, 'vB1', 'acct-B trans 1')
  returning trans_id as transb1 \gset

-- reconciliation_event: two in acct-A (balance + quantity), one in acct-B (balance).
insert into pfin.reconciliation_event (account_id, reconciliation_date, dimension, statement_balance)
  values (:accta, '2026-01-31', 'balance', 1000)
  returning event_id as eventa_bal \gset
insert into pfin.reconciliation_event (account_id, reconciliation_date, dimension, symbol, statement_quantity)
  values (:accta, '2026-01-31', 'quantity', 'AAPL', 10)
  returning event_id as eventa_qty \gset
insert into pfin.reconciliation_event (account_id, reconciliation_date, dimension, statement_balance)
  values (:acctb, '2026-01-31', 'balance', 2000)
  returning event_id as eventb_bal \gset

-- holdings_checkpoint: one in acct-A (substrate read target).
insert into pfin.holdings_checkpoint (account_id, symbol, as_of_date, quantity, balance)
  values (:accta, 'AAPL', '2026-01-31', 10, 1500)
  returning checkpoint_id as hcpa \gset

-- reconciliation_event_trans: seed L1 = (eventa_bal, transa1) — both acct-A, so the
-- matched-account fence passes even under this privileged INSERT (read target for RLS).
insert into pfin.reconciliation_event_trans (event_id, account_trans_id)
  values (:eventa_bal, :transa1)
  returning id as l1 \gset

-- Hold the table ACL OPEN to service_role (test setup, rolled back) so the immutability
-- TRIGGERS — not a missing grant — are the only thing that can stop a service_role write.
grant usage on schema pfin to service_role;
grant select, update, delete on pfin.reconciliation_event       to service_role;
grant select, update, delete on pfin.holdings_checkpoint        to service_role;
grant select, update, delete on pfin.reconciliation_event_trans to service_role;

-- =====================================================================
-- [D3] matched-account fence (RT-17 / Lock 9 mod #1) — ALREADY-CATALOGUED instance.
--   Exercised PRIVILEGED (postgres) — the authoritative RLS-bypassed check.
--   NOTE: the positive control adds L2, so the join-table has 2 committed rows before
--   the RLS read assertions below (deterministic count = 2).
-- =====================================================================
-- (1) POSITIVE control: SAME-account link (event + trans both acct-A) SUCCEEDS.
select lives_ok(
  format($$ insert into pfin.reconciliation_event_trans (event_id, account_trans_id)
              values (%s, %s) $$, :eventa_qty, :transa2),
  '[D3+] same-account link (event & trans both in acct-A) SUCCEEDS — matched-account fence accepts in-account link (guards an over-broad reject; non-vacuous positive)'
);
-- (2) NEGATIVE: cross-account link (event acct-A, trans acct-B) REJECTED.
select throws_like(
  format($$ insert into pfin.reconciliation_event_trans (event_id, account_trans_id)
              values (%s, %s) $$, :eventa_bal, :transb1),
  'cross-account reconciliation link rejected%',
  '[D3-] cross-account link (event acct-A, trans acct-B) REJECTED by the matched-account fence (distinct message; Decision 3 / Lock 9 mod #1)'
);

-- =====================================================================
-- [RLS] append-only RLS positive/negative — reads FIRST (before any row-adding write),
--   so owner/cross-tenant counts are deterministic.
-- =====================================================================
-- Owner (tenant A, rd_access on acct-A) reads its own rows. Only is() runs under
-- authenticated (no _rls.* call while switched) — set_tenant is called at role=postgres.
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*) from pfin.reconciliation_event)::bigint, 2::bigint,
  '[RLS] owner A reads exactly its 2 reconciliation_event rows (rd_access-JOIN; not over-restrictive)'
);
select is(
  (select count(*) from pfin.reconciliation_event_trans)::bigint, 2::bigint,
  '[RLS] owner A reads exactly its 2 reconciliation_event_trans rows (parent-event FK-chain rd_access-JOIN)'
);
select is(
  (select count(*) from pfin.holdings_checkpoint)::bigint, 1::bigint,
  '[substrate] owner A reads its 1 holdings_checkpoint row (rd_access-JOIN SELECT works)'
);
select set_config('role', 'postgres', true);

-- Cross-tenant (tenant B, rd_access on acct-B only) sees ZERO of A's rows -> fails closed.
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from pfin.reconciliation_event where account_id = :accta)::bigint, 0::bigint,
  '[RLS] cross-tenant read fails closed: B sees 0 of A''s reconciliation_event rows'
);
select is(
  (select count(*) from pfin.reconciliation_event_trans)::bigint, 0::bigint,
  '[RLS] cross-tenant read fails closed: B sees 0 reconciliation_event_trans rows (all links are A''s; parent FK-chain excludes B)'
);
select is(
  (select count(*) from pfin.holdings_checkpoint where account_id = :accta)::bigint, 0::bigint,
  '[substrate] cross-tenant read fails closed: B sees 0 of A''s holdings_checkpoint rows'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- [IMMUT] append-only both-roles (RT-17) on ALL 3 tables.
--   authenticated -> ACL denial (no write grant); service_role -> row-level trigger raise
--   (LOAD-BEARING cross-tier); postgres -> statement-level TRUNCATE trigger raise.
-- =====================================================================
-- ---- authenticated tier: fully fenced at the TABLE ACL (no write grant) ----
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ update pfin.reconciliation_event set reconciliation_date = '2026-02-01' where event_id = %s $$, :eventa_bal),
  'permission denied for table reconciliation_event',
  '[IMMUT auth] reconciliation_event UPDATE fails closed at the table ACL (no write grant; trigger never reached)'
);
select throws_like(
  format($$ delete from pfin.reconciliation_event where event_id = %s $$, :eventa_bal),
  'permission denied for table reconciliation_event',
  '[IMMUT auth] reconciliation_event DELETE fails closed at the table ACL'
);
select throws_like(
  format($$ update pfin.reconciliation_event_trans set created_at = now() where id = %s $$, :l1),
  'permission denied for table reconciliation_event_trans',
  '[IMMUT auth] reconciliation_event_trans UPDATE fails closed at the table ACL'
);
select throws_like(
  format($$ delete from pfin.reconciliation_event_trans where id = %s $$, :l1),
  'permission denied for table reconciliation_event_trans',
  '[IMMUT auth] reconciliation_event_trans DELETE fails closed at the table ACL'
);
select throws_like(
  format($$ update pfin.holdings_checkpoint set as_of_date = '2026-02-01' where checkpoint_id = %s $$, :hcpa),
  'permission denied for table holdings_checkpoint',
  '[IMMUT auth] holdings_checkpoint UPDATE fails closed at the table ACL (SELECT-only grant)'
);
select throws_like(
  format($$ delete from pfin.holdings_checkpoint where checkpoint_id = %s $$, :hcpa),
  'permission denied for table holdings_checkpoint',
  '[IMMUT auth] holdings_checkpoint DELETE fails closed at the table ACL (SELECT-only grant)'
);
select set_config('role', 'postgres', true);

-- ---- service_role tier: RLS-bypassed + granted -> the TRIGGER is the sole gate (LOAD-BEARING) ----
select set_config('role', 'service_role', true);
select throws_like(
  format($$ update pfin.reconciliation_event set reconciliation_date = '2026-02-01' where event_id = %s $$, :eventa_bal),
  'pfin.reconciliation_event is immutable%UPDATE blocked%',
  '[IMMUT svc] CROSS-TIER: service_role reconciliation_event UPDATE blocked by the immutability TRIGGER (RLS-bypass does NOT bypass the trigger)'
);
select throws_like(
  format($$ delete from pfin.reconciliation_event where event_id = %s $$, :eventa_bal),
  'pfin.reconciliation_event is immutable%DELETE blocked%',
  '[IMMUT svc] CROSS-TIER: service_role reconciliation_event DELETE blocked by the immutability TRIGGER'
);
select throws_like(
  format($$ update pfin.reconciliation_event_trans set created_at = now() where id = %s $$, :l1),
  'pfin.reconciliation_event_trans is immutable%UPDATE blocked%',
  '[IMMUT svc] CROSS-TIER: service_role reconciliation_event_trans UPDATE blocked by the immutability TRIGGER'
);
select throws_like(
  format($$ delete from pfin.reconciliation_event_trans where id = %s $$, :l1),
  'pfin.reconciliation_event_trans is immutable%DELETE blocked%',
  '[IMMUT svc] CROSS-TIER: service_role reconciliation_event_trans DELETE blocked by the immutability TRIGGER'
);
select throws_like(
  format($$ update pfin.holdings_checkpoint set as_of_date = '2026-02-01' where checkpoint_id = %s $$, :hcpa),
  'pfin.holdings_checkpoint is immutable%UPDATE blocked%',
  '[IMMUT svc] CROSS-TIER: service_role holdings_checkpoint UPDATE blocked by the immutability TRIGGER'
);
select throws_like(
  format($$ delete from pfin.holdings_checkpoint where checkpoint_id = %s $$, :hcpa),
  'pfin.holdings_checkpoint is immutable%DELETE blocked%',
  '[IMMUT svc] CROSS-TIER: service_role holdings_checkpoint DELETE blocked by the immutability TRIGGER'
);
select set_config('role', 'postgres', true);

-- ---- TRUNCATE tier: statement-level trigger, exercised as OWNER (postgres) — sole gate ----
-- reconciliation_event is REFERENCED by reconciliation_event_trans.event_id, so a plain
-- TRUNCATE hits Postgres's FK-guard ('cannot truncate a table referenced in a foreign key
-- constraint') BEFORE the statement-trigger fires. CASCADE bypasses that guard and includes
-- the referencing table in the truncation set; the TARGET (reconciliation_event) is first in
-- the set, so ITS BEFORE TRUNCATE trigger fires first and raises -> message-precise match.
-- (_trans + holdings_checkpoint have no inbound FK, so they need no CASCADE.)
select throws_like(
  $$ truncate pfin.reconciliation_event cascade $$,
  'pfin.reconciliation_event is immutable%TRUNCATE blocked%',
  '[IMMUT trunc] reconciliation_event TRUNCATE (CASCADE past the inbound-FK guard) blocked by the statement-level trigger (audit-wipe path fenced; distinct from the row-level fence)'
);
select throws_like(
  $$ truncate pfin.reconciliation_event_trans $$,
  'pfin.reconciliation_event_trans is immutable%TRUNCATE blocked%',
  '[IMMUT trunc] reconciliation_event_trans TRUNCATE blocked by the statement-level trigger'
);
select throws_like(
  $$ truncate pfin.holdings_checkpoint $$,
  'pfin.holdings_checkpoint is immutable%TRUNCATE blocked%',
  '[IMMUT trunc] holdings_checkpoint TRUNCATE blocked by the statement-level trigger'
);

-- =====================================================================
-- [RLS-WRITE] append-only INSERT respects wr_access-JOIN (reconciliation_event), and the
--   authenticated link path is fail-closed at V1.0 (account_trans SELF-190-gated).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- A holds wr_access on acct-A -> INSERT into its own account SUCCEEDS.
select lives_ok(
  format($$ insert into pfin.reconciliation_event (account_id, reconciliation_date, dimension, statement_balance)
              values (%s, '2026-03-01', 'balance', 300) $$, :accta),
  '[RLS-WRITE] A INSERT reconciliation_event into own acct-A SUCCEEDS (wr_access-JOIN WITH CHECK satisfied)'
);
-- A has NO wr_access on acct-B -> INSERT rejected by the INSERT WITH CHECK.
select throws_like(
  format($$ insert into pfin.reconciliation_event (account_id, reconciliation_date, dimension, statement_balance)
              values (%s, '2026-03-01', 'balance', 300) $$, :acctb),
  'new row violates row-level security policy%for table "reconciliation_event"',
  '[RLS-WRITE] A INSERT reconciliation_event into acct-B REJECTED by the wr_access-JOIN WITH CHECK (cross-account write fails closed)'
);
-- Authenticated link INSERT — (24) FINDING forward-note DISCHARGED at SELF-190/006.
-- At 005-time this ACL-failed-closed ('permission denied for table account_trans'):
-- account_trans had no authenticated grant, so the INVOKER matched-account trigger's
-- account_trans read hit the table ACL. 006 grants authenticated SELECT on account_trans,
-- and directory-mode runs this test against the full schema, so A (rd/wr on acct-A) now
-- resolves the read: (eventa_qty, transa1) is a SAME-account (both acct-A) link -> the
-- matched-account trigger matches -> parent wr_access WITH CHECK passes -> the link now
-- SUCCEEDS. Converted throws_like -> lives_ok in the SAME PR that changed the behavior
-- (006), mirroring the 005->004 TRUNCATE-CASCADE cross-migration fix pattern. The
-- authoritative matched-account semantics (same-account accept / cross-account reject) are
-- covered comprehensively by 006's §5 (5a/5b); this keeps 005 internally green under 006.
select lives_ok(
  format($$ insert into pfin.reconciliation_event_trans (event_id, account_trans_id)
              values (%s, %s) $$, :eventa_qty, :transa1),
  '[RLS-WRITE] authenticated SAME-account link (eventa_qty + transa1, both acct-A) SUCCEEDS under 006 — the (24) FINDING ACL-gated fail-closed is discharged; matched-account semantics now permit the same-account link under authenticated (rd_access on account_trans reachable via SELF-190/006).'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- [substrate] holdings_checkpoint has NO authenticated INSERT path in V1.0.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ insert into pfin.holdings_checkpoint (account_id, symbol, as_of_date, quantity)
              values (%s, 'AAPL', '2026-03-01', 5) $$, :accta),
  'permission denied for table holdings_checkpoint',
  '[substrate] authenticated INSERT into holdings_checkpoint fails closed at the table ACL (no INSERT grant/policy; writer + DP-4 posture defer to V1.3)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- [DIM] dimension-shape CHECK (DP-2) — run PRIVILEGED so the table CHECK is the sole gate.
-- =====================================================================
select throws_like(
  format($$ insert into pfin.reconciliation_event (account_id, reconciliation_date, dimension, symbol, statement_balance)
              values (%s, '2026-04-01', 'balance', 'AAPL', 100) $$, :accta),
  'new row for relation "reconciliation_event" violates check constraint "reconciliation_event_dimension_shape"%',
  '[DIM] balance event with a non-null symbol REJECTED by the dimension-shape CHECK (balance carries no symbol)'
);
select throws_like(
  format($$ insert into pfin.reconciliation_event (account_id, reconciliation_date, dimension, statement_quantity)
              values (%s, '2026-04-01', 'quantity', 5) $$, :accta),
  'new row for relation "reconciliation_event" violates check constraint "reconciliation_event_dimension_shape"%',
  '[DIM] quantity event missing symbol REJECTED by the dimension-shape CHECK (quantity requires symbol)'
);
select lives_ok(
  format($$ insert into pfin.reconciliation_event (account_id, reconciliation_date, dimension, statement_balance)
              values (%s, '2026-04-01', 'balance', 100) $$, :accta),
  '[DIM+] valid balance event (statement_balance set; symbol/quantity null) inserts'
);
select lives_ok(
  format($$ insert into pfin.reconciliation_event (account_id, reconciliation_date, dimension, symbol, statement_quantity)
              values (%s, '2026-04-01', 'quantity', 'AAPL', 5) $$, :accta),
  '[DIM+] valid quantity event (symbol + statement_quantity set; balance null) inserts'
);

select * from finish();
rollback;

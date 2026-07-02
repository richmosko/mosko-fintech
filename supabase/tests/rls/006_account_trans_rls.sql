-- =====================================================================
-- Per-Wave battery — pfin.account_trans rd_access/wr_access-JOIN RLS
--   (SELF-190 / 006 — V1-SHIP-BLOCK)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/006_account_trans_rls.sql
--   - policy account_trans_select  (FOR SELECT TO authenticated; rd_access-JOIN to
--                                    pfin.account_users)
--   - policy account_trans_insert  (FOR INSERT TO authenticated; wr_access-JOIN
--                                    WITH CHECK — mod #3: write keys on wr_access)
--   - grant select, insert on pfin.account_trans to authenticated  (ACL-before-RLS)
--   NO UPDATE/DELETE policy or grant (Fork-2 = A; default-deny + 004 triggers).
-- Prereqs realized by earlier migrations (exercised here):
--   - 003 fn_grant_creator_access  (DEFINER; seeds the rd=t/wr=t creator grant the
--                                    two policies JOIN against — mod #2 VERIFY-ONLY here)
--   - 004 pfin.account_trans + its immutability triggers (append-only fence)
--   - 005 fn_reconciliation_event_trans_matched_account (INVOKER; the cross-feature
--                                    fence that account_trans SELECT now makes reachable)
-- Reuses the SELF-187/188/189 idiom: \ir verbs, all-lowercase \gset literals,
-- message-precise throws_like (the 004 all-42501 / 005 \gset-case-fold lessons).
--
-- 006 DISCHARGES the 004 deferral: account_trans becomes reachable by authenticated
-- for the FIRST time. So this battery lands the assertions that were DEFERRED-not-faked
-- while account_trans was default-deny-all:
--   • SELF-187 deferred assertion (ii) — cross-tenant read fails closed via the
--     rd_access-JOIN read path (there was no SELECT policy to exercise until now).
--   • 005 (24) FINDING forward-note — the matched-account fence's account_trans read
--     previously ACL-failed-closed under authenticated; with SELECT now granted it is
--     REACHABLE under authenticated and the matched-account SEMANTICS take over (§5).
--
-- ┌─ THE THREE FAIL LAYERS (WHY each rejection matches a DIFFERENT message) ──────────┐
-- │ 006 grants authenticated SELECT + INSERT only. So per attempted op:                │
-- │  • cross-account INSERT (no wr_access on target) -> RLS INSERT WITH CHECK rejects  │
-- │    -> 'new row violates row-level security policy%for table "account_trans"'.       │
-- │  • authenticated UPDATE/DELETE -> NO update/delete grant -> TABLE-ACL denial        │
-- │    -> 'permission denied for table account_trans' (RLS/trigger never reached; the   │
-- │    004 (a)/(c-auth) layering — a false-RED if we asserted the trigger message here).│
-- │  • cross-account reconciliation LINK -> the 005 matched-account BEFORE-INSERT       │
-- │    trigger raises 'cross-account reconciliation link rejected%' (fires before the   │
-- │    parent WITH CHECK; the read is now RLS-scoped, not ACL-blocked).                 │
-- │ Matching the SPECIFIC message (not a bare 42501) keeps one fence from passing for   │
-- │ another — the 004 all-42501 false-green lesson.                                     │
-- └─────────────────────────────────────────────────────────────────────────────────────┘
--
-- WRITE-KEY SEPARATION (mod #3) — WHY tenant C exists. The creator-grant trigger only
--   ever seeds rd=t/wr=t, so an rd-only-but-not-wr grant cannot arise via the app path.
--   A THIRD synthetic tenant C is seeded a PRIVILEGED rd=t/wr=f share on acct-A (this is
--   the V2 sharing-shape ACL the migration's mod #4 advisory notes). C proves the write
--   path keys on wr_access, NOT rd_access: C READS acct-A (rd=t) but its INSERT is
--   rejected by the wr_access-JOIN WITH CHECK. Core A/B isolation stays a clean two-tenant
--   fixture (B holds NO grant on acct-A); C is the narrow rd/wr-separation vehicle only.
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (1b)        -> RED if the SELECT policy were dropped/widened (B would see A's rows).
--   (2b)/(2c-w) -> RED if the INSERT WITH CHECK were removed OR keyed on rd_access
--                  (cross-tenant / rd-only write would commit). mod #3 linchpin.
--   (4u)/(4d)   -> RED if an authenticated update/delete grant were added (message would
--                  change / the write would silently 0-row under default-deny). Guards the
--                  'SELECT, INSERT only' grant against widening.
--   (5b)        -> RED if the matched-account trigger were removed (cross-account link
--                  commits). (5a)/(2c-r)/(3*) = non-vacuous positives (guard over-broad
--                  reject / over-restrictive read / a non-firing creator grant).
--
-- §10 / DECISION 3: ledger UNCHANGED at 2 (RT-22 + RT-26); Decision-3 family UNCHANGED at
--   7 (006 adds no FK-shaped column; the two policies are the isolation MECHANISM the
--   already-catalogued columns rely on — migration header §10 3-axis + Decision 3 eval).
--
-- POSTURE (SECURITY §4.5): synthetic only — fixed-UUID tenants from _rls.tenant_a()/_b()
--   plus a fixed literal tenant C; NO PII / NO real account numbers / NO prod data.
--   Committed account_trans + reconciliation_event rows + C's share are seeded PRIVILEGED
--   (role=postgres). auth.uid() is NULL under postgres, so account.users_id is set
--   explicitly for the seeds; the app-path account (acct-A2, §3) is created UNDER
--   authenticated A to exercise the DEFAULT auth.uid() + creator-grant chain end-to-end.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated,
--   so NO `_rls.*` call runs while switched to authenticated. Tenant UUIDs are resolved
--   to psql LITERALS via \gset at role=postgres; every _rls.set_tenant is called at
--   role=postgres and each block restores role=postgres before the next. \gset var names
--   are ALL-LOWERCASE (the 005 case-fold lesson — Postgres folds unquoted RETURNING
--   aliases to lowercase; mixed-case aborts the file with "syntax error at :").
--
-- ⟦LOCAL RUN⟧ Docker is down in the authoring env -> `supabase test db` could not run
--   locally; CI (pg_prove directory-mode) is the gate. RED-until-006-applied is expected.
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(12);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
-- tenant C has no _rls helper (two-tenant fixture ships a()/b() only) -> fixed literal
-- mirroring the convention (…00c), used only for the rd/wr write-key separation (§2c).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset
\set tc '00000000-0000-0000-0000-00000000000c'

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed seed path).
-- A owns acct-A; B owns acct-B. account.users_id is set explicitly (auth.uid() is NULL
-- under postgres). The 003 AFTER-INSERT DEFINER creator-grant trigger fires on each
-- account INSERT -> account_users(acct, owner, rd=t, wr=t) — exactly the rd/wr-JOIN
-- state the 006 policies key on (mod #2).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-A', 'depository', 'household', 'taxable')
  returning account_id as accta \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'acct-B', 'depository', 'household', 'taxable')
  returning account_id as acctb \gset

-- Committed account_trans: two in acct-A, one in acct-B. These pre-existing rows back
-- the cross-tenant read (§1) + rd-only read (§2c) + append-only (§4) + cross-feature (§5)
-- assertions. acct-A never receives a SUCCESSFUL authenticated INSERT below, so its
-- account_trans count stays a deterministic 2 for every reader.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-01-15', 100, 'vA1', 'acct-A committed 1')
  returning trans_id as ta1 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-01-16', 200, 'vA2', 'acct-A committed 2')
  returning trans_id as ta2 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:acctb, '2026-01-17', 300, 'vB1', 'acct-B committed 1')
  returning trans_id as tb1 \gset

-- reconciliation_event: one 'balance' event per account (cross-feature link targets, §5).
insert into pfin.reconciliation_event (account_id, reconciliation_date, dimension, statement_balance)
  values (:accta, '2026-01-31', 'balance', 1000)
  returning event_id as evta \gset
insert into pfin.reconciliation_event (account_id, reconciliation_date, dimension, statement_balance)
  values (:acctb, '2026-01-31', 'balance', 2000)
  returning event_id as evtb \gset

-- Tenant C: PRIVILEGED rd-only share on acct-A (rd=t, wr=f). account_users is
-- authenticated-write-locked (DEFINER trigger is the only app-path writer, and it always
-- sets rd/wr=t), so an rd-only grant can only be seeded privileged. This is the V2
-- sharing-shape ACL the migration mod #4 advisory notes; here it is the §2c write-key
-- separation vehicle. unique(account_id, users_id) -> distinct from A's creator grant.
insert into pfin.account_users (account_id, users_id, rd_access, wr_access)
  values (:accta, :'tc', true, false);

-- =====================================================================
-- BLOCK 1 (authenticated A) — §3 mod #2 creator-grant end-to-end + §1 owner reads own.
--   A creates acct-A2 via the APP PATH (users_id DEFAULT auth.uid()); the DEFINER
--   creator-grant trigger fires and seeds account_users(acct-A2, A, rd=t, wr=t), which
--   is what lets A then SELECT + INSERT its own account_trans under RLS.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (3a) app-path account create (NOT an assertion) — DEFINER creator-grant trigger fires.
insert into pfin.account (name, account_type, scope, tax_treatment)
  values ('A app-path acct', 'depository', 'household', 'taxable')
  returning account_id as accta2 \gset

-- (3b) mod #2: the creator grant exists with rd=t AND wr=t, and A reads it under RLS.
select is(
  (select (rd_access and wr_access) from pfin.account_users
     where account_id = :accta2 and users_id = :'ta'),
  true,
  '(3) mod #2: fn_grant_creator_access seeded a rd=t/wr=t creator grant on A''s app-path account, and A reads it under account_users RLS (users_id = auth.uid())'
);

-- (3c) mod #2 + §2 write-path POSITIVE: the creator grant (wr=t) lets A INSERT
--      account_trans into its OWN account under RLS (wr_access-JOIN WITH CHECK satisfied).
select lives_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
              values (%s, '2026-02-01', 42, 'vA-app', 'A app-path append') $$, :accta2),
  '(3/2+) creator grant (wr_access) lets A INSERT account_trans into its own account under RLS — wr_access-JOIN WITH CHECK satisfied (write-path positive control)'
);

-- (3d) mod #2 + §1 read POSITIVE: the creator grant (rd=t) lets A SELECT its own
--      account_trans under RLS — sees exactly the 1 row it just inserted into acct-A2.
select is(
  (select count(*) from pfin.account_trans where account_id = :accta2)::bigint, 1::bigint,
  '(3/1+) creator grant (rd_access) lets A SELECT its own account_trans under RLS (rd_access-JOIN; sees exactly its 1 acct-A2 row — not over-restrictive)'
);

-- (1a) §1 owner reads own committed rows: A sees exactly acct-A''s 2 committed trans.
select is(
  (select count(*) from pfin.account_trans where account_id = :accta)::bigint, 2::bigint,
  '(1) two-tenant core: owner A reads exactly its 2 committed account_trans rows in acct-A (rd_access-JOIN)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 2 (authenticated B) — §1 cross-tenant read fails closed (SELF-187 deferred (ii))
--   + §2 cross-tenant write fails closed.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);

-- (1b) SELF-187 DEFERRED ASSERTION (ii), now landable: B holds no grant on acct-A, so the
--      rd_access-JOIN read path yields ZERO of A''s account_trans. (No-op-empty until 006's
--      SELECT policy existed; that is why 004/003 deferred rather than faked it.)
select is(
  (select count(*) from pfin.account_trans where account_id = :accta)::bigint, 0::bigint,
  '(1) SELF-187 deferred assertion (ii): cross-tenant read fails closed — B sees 0 of A''s account_trans via the rd_access-JOIN read path'
);

-- (2b) §2 cross-tenant write fails closed: B has no wr_access on acct-A -> INSERT rejected
--      by the wr_access-JOIN WITH CHECK (message-precise RLS-policy violation, not the ACL).
select throws_like(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
              values (%s, '2026-02-05', 77, 'vB-x', 'B cross-account write attempt') $$, :accta),
  'new row violates row-level security policy%for table "account_trans"',
  '(2) cross-tenant write fails closed: B INSERT into acct-A (no wr_access) REJECTED by the wr_access-JOIN WITH CHECK'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 3 (authenticated C) — §2 mod #3 write-key separation: rd_access grants READ but
--   NOT WRITE. C holds a privileged rd=t/wr=f share on acct-A.
-- =====================================================================
select _rls.set_tenant(:'tc'::uuid);

-- (2c-read) rd_access POSITIVE: the rd-only sharee C reads acct-A''s 2 committed trans
--           (rd_access-JOIN grants read to a non-owner sharee — non-vacuous control).
select is(
  (select count(*) from pfin.account_trans where account_id = :accta)::bigint, 2::bigint,
  '(2) rd-only sharee C (rd=t) reads acct-A''s 2 committed account_trans under RLS (rd_access-JOIN grants read to a non-owner sharee)'
);

-- (2c-write) mod #3 LINCHPIN: the SAME rd-only grant does NOT permit INSERT -> the write
--            path keys on wr_access, NOT rd_access. REJECTED by the wr_access-JOIN WITH CHECK.
select throws_like(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
              values (%s, '2026-02-06', 88, 'vC-x', 'C rd-only write attempt') $$, :accta),
  'new row violates row-level security policy%for table "account_trans"',
  '(2) mod #3 linchpin: rd-only sharee C (rd=t, wr=f) INSERT into acct-A REJECTED — the write path keys on wr_access, NOT rd_access (rd alone grants read but never write)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 4 (authenticated A) — §4 append-only preserved + §5 cross-feature reconciliation link.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (4u)/(4d) §4 append-only: 006 grants SELECT + INSERT only (NO update/delete). So an
--   authenticated UPDATE/DELETE fails at the TABLE ACL BEFORE RLS/trigger is consulted —
--   the honest layer for authenticated (asserting the 004 immutability-trigger message
--   here would be a false-RED; the trigger is never reached). This guards the
--   'SELECT, INSERT only' grant against an accidental widening to update/delete (which
--   would silently 0-row under default-deny rather than throw). The cross-tier service_role
--   immutability TRIGGER fence (RLS-bypass does not bypass triggers) is covered in the 004
--   battery — not re-litigated here; 006 changes only the authenticated grant.
select throws_like(
  format($$ update pfin.account_trans set amount = 999 where trans_id = %s $$, :ta1),
  'permission denied for table account_trans',
  '(4) append-only: authenticated UPDATE fails closed at the table ACL (006 grants SELECT+INSERT only; no UPDATE grant — guards the grant against widening)'
);
select throws_like(
  format($$ delete from pfin.account_trans where trans_id = %s $$, :ta1),
  'permission denied for table account_trans',
  '(4) append-only: authenticated DELETE fails closed at the table ACL (no DELETE grant)'
);

-- (5a) §5 CROSS-FEATURE POSITIVE (closes 005''s forward-note / the (24) FINDING): now that
--   account_trans has an authenticated SELECT (rd_access), the 005 matched-account INVOKER
--   fence — which reads account_trans and previously ACL-failed-closed under authenticated —
--   is REACHABLE + SATISFIED under authenticated. A wr_access user links a SAME-account
--   (event, trans) pair -> matched-account trigger reads ta1 via A''s rd_access -> matched ->
--   parent wr_access WITH CHECK passes -> row inserts. (Was privileged-only pre-SELF-190.)
select lives_ok(
  format($$ insert into pfin.reconciliation_event_trans (event_id, account_trans_id)
              values (%s, %s) $$, :evta, :ta1),
  '(5) cross-feature: authenticated wr_access user links a SAME-account (event, account_trans) pair — SUCCEEDS. The 005 matched-account fence is now reachable+satisfied under authenticated'
);

-- (5b) §5 CROSS-FEATURE NEGATIVE: a CROSS-account pair (event acct-A, trans acct-B) is
--   rejected by the matched-account RAISE (no longer the ACL layer). Under authenticated A
--   the trigger''s account_trans read is RLS-scoped: tb1 (acct-B) is unreadable + its
--   account_id differs from evta''s -> NOT EXISTS -> matched-account raise (fires before the
--   parent WITH CHECK). This is the (24) FINDING''s forward-note discharged: authenticated
--   now enforces matched-account SEMANTICS, not an ACL denial.
select throws_like(
  format($$ insert into pfin.reconciliation_event_trans (event_id, account_trans_id)
              values (%s, %s) $$, :evta, :tb1),
  'cross-account reconciliation link rejected%',
  '(5) cross-feature: authenticated link of a CROSS-account (event acct-A, trans acct-B) pair REJECTED by the matched-account raise — the 005 fence now enforces matched-account under authenticated (closes the 005 (24) FINDING)'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;

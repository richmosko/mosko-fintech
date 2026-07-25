-- =====================================================================
-- Per-Wave battery — M1-evt Slice A2 (SELF-293): pfin.account_trans_annotation_history —
--   the APPEND-ONLY, IMMUTABLE (004-mirror) reclassification-history audit-class table
--   over the 023 overlay's routing columns (sub_cat_id + metadata). Written by EXACTLY
--   ONE SECURITY DEFINER helper (fn_reclass_history_insert — the AUTHORED 4th allowlist
--   entry) fired by an AFTER INS/UPD trigger on 023; authenticated has NO direct INSERT
--   grant (un-forgeable). V1-SHIP-BLOCK; JOINT-REVIEW-MANDATORY (D2 audit-class + a new
--   SECURITY DEFINER entry).
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/031_reclass_history.sql
--   - table account_trans_annotation_history (id PK; trans_id -> account_trans ON DELETE
--       RESTRICT = SOLE tenant anchor α, NOT D3; version_seq int; sub_cat_id bigint SNAPSHOT
--       NO FK; metadata jsonb; op CHECK IN (insert,update); captured_at; changed_by uuid
--       DEFAULT auth.uid(); UNIQUE(trans_id,version_seq)).
--   - policy ..._select ONLY (parent-chain rd_access-JOIN; owner-only read).
--   - grant SELECT ONLY to authenticated (NO write grant). anon zero; service_role ungranted.
--   - fn_reclass_history_insert() — AFTER INS/UPD on 023; SECURITY DEFINER; capture gate
--       (UPDATE writes nothing unless sub_cat_id/metadata IS DISTINCT FROM old); version_seq
--       = max+1. The AUTHORED 4th DEFINER allowlist entry.
--   - fn_reclass_history_block_mutation()/_block_truncate() — INVOKER immutability fences.
--   - the migration's backfill INSERT...SELECT (birth v1 for history-less 023 rows).
-- Prereqs on the reset stack: 001 (pfin), 003 (account + creator-grant rd=t/wr=t), 004
--   (account_trans + immutability pattern), 006 (account_users rd_access), 009 (user_taxonomy),
--   023 (the overlay host + its #10/trade triggers), 030 (023.metadata — 031 versions it).
--
-- ┌─ ROLE MODEL ───────────────────────────────────────────────────────────────────────────┐
-- │ Capture (AC3), immutability (AC1), DEFINER-priv checks (AC2a/b), snapshot (AC5), backfill │
-- │ (AC6) run PRIVILEGED (role=postgres) — the DEFINER capture helper runs as the table owner  │
-- │ regardless of caller, so a postgres 023 edit exercises it fully. The REAL authenticated    │
-- │ path (AC4) + the direct-INSERT-denied grant check (AC2c) run under authenticated A/B (the  │
-- │ production RLS + changed_by=auth.uid() attribution). service_role (AC1d) proves the         │
-- │ immutability TRIGGER binds even when RLS is bypassed. Roles restored to postgres between    │
-- │ phases (PR #121 discipline: _rls.set_tenant/_service_role invoked at role=postgres).        │
-- │ NOTE: label order (AC1..AC6) != execution order — a history row must EXIST (AC3 capture)    │
-- │ before it can be attacked (AC1), so AC3 executes first. pgTAP numbers sequentially.         │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ WHY (1d) HOLDS A service_role GRANT OPEN (the 004 lesson) ─────────────────────────────┐
-- │ service_role is UNGRANTED on the history table, so a bare service_role UPDATE would hit    │
-- │ 'permission denied' (42501, ACL) BEFORE the immutability trigger — asserting the wrong     │
-- │ fence. (1d) grants UPDATE to service_role TEST-ONLY (rolled back) so the write REACHES the  │
-- │ trigger and the immutability MESSAGE (not a missing grant) is the proven gate. Mirrors 004. │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ WHY (6) DISABLES THE CAPTURE TRIGGER (a documented, rolled-back test-only device) ─────┐
-- │ The migration's backfill births v1 rows for PRE-EXISTING 023 rows that have no history.    │
-- │ In-test, every 023 INSERT auto-fires the capture trigger (so a fresh row already has        │
-- │ history — the backfill's NOT EXISTS would skip it, testing nothing). (6) transiently        │
-- │ DISABLEs the capture trigger to mint a history-LESS 023 row (the pre-existing shape), re-   │
-- │ ENABLEs it, then runs the migration's backfill INSERT...SELECT verbatim and asserts the     │
-- │ v1 birth + idempotent re-run. Test-only, rolled back.                                       │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (1a)/(1b)/(1c) UPDATE / DELETE / TRUNCATE on history RAISE (append-only immutability) —
--        RED if a fence were dropped (an audit row could be edited/erased).
--   (1d) a service_role UPDATE (RLS-bypass, grant held open) is STILL blocked by the trigger —
--        RED if immutability relied on RLS/grant rather than the trigger (tamper-evidence gone).
--   (2a) authenticated holds NO direct INSERT grant — RED if a write grant leaked (forgeable
--        history via PostgREST).
--   (2b) authenticated holds SELECT — RED if the owner-read grant were missing.
--   (2c) a direct authenticated INSERT fails at the GRANT layer — RED if a user could POST a
--        forged history row (the DEFINER helper is the SOLE write path).
--   (3a) a 023 INSERT writes history v1 (op=insert, version_seq=1) — RED if birth capture broke.
--   (3b) a sub_cat_id UPDATE writes v2 (op=update) — RED if routing-change capture broke.
--   (3c) a metadata UPDATE writes v3 (op=update) — RED if metadata-change capture broke.
--   (3d) a note-only UPDATE writes NOTHING — RED if the DISTINCT-FROM capture gate were absent
--        (noise versions would flood the audit trail).
--   (3e) version_seq is monotonic 1,2,3 per trans_id — RED if the max+1 / UNIQUE broke.
--   (4a) the REAL authenticated 023 edit writes exactly one birth row via the DEFINER helper.
--   (4b) changed_by = A's uid (the DEFINER helper resolves auth.uid()) — RED if attribution lost.
--   (4c) two-tenant read isolation: B reads 0 of A's history — RED if the parent-chain SELECT
--        policy leaked.
--   (5a) snapshot truth: history.sub_cat_id survives deletion of the referenced user_taxonomy
--        row (no FK) — RED if a FK/cascade made the audit lie about the past.
--   (6a) backfill-birth: a pre-existing history-less 023 row gets a v1 op=insert row.
--   (6b) backfill idempotent: a re-run adds no duplicate (NOT EXISTS).
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22 + RT-26 + RT-27). Decision-3 family
--   UNCHANGED (12 labeled / 10 DDL-realized): trans_id is the SOLE anchor (NOT D3); sub_cat_id
--   is a plain-bigint SNAPSHOT (NO FK); version_seq has no predecessor FK. *** DEFINER allowlist
--   3 -> 4 (fn_reclass_history_insert is the AUTHORED 4th entry — a real one-way-door ledger
--   change, F/CTO-ratified; the immutability fences stay INVOKER). *** A DEFINER-allowlist change
--   is a SEPARATE ledger from §10 (SELF-187 de-conflation) — §10 stays 3.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants _rls.tenant_a()/_b(); NO PII /
--   NO real account numbers / NO prod data. A owns acct-alpha + cash txns + Expense Sub-Cats; B
--   owns acct-beta. All in a rolled-back txn.
--
-- ⟦WIRE-VALIDATE⟧ authored against 031's firmed contract; authoritative run is the 001->031
--   reset stack. Locally the DB is at 027, so a net-zero rolled-back harness \i's 030 then 031
--   transiently before this file (031 depends on 030's 023.metadata); CI (pg_prove directory-
--   mode) is the green gate. plan(18).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(18);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres). A owns acct-alpha (+ 4 cash txns) + Expense Sub-Cats;
-- B owns acct-beta (a real second tenant for the isolation read). Cash txns + Expense
-- Sub-Cats keep the 023 #10 + trade fences satisfied on every capture write.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-alpha', 'depository', 'household', 'taxable') returning account_id as accta \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'acct-beta', 'depository', 'household', 'taxable') returning account_id as acctb \gset

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-04-01', -50, 'vCAP', 'capture') returning trans_id as ct_cap \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-04-02', -50, 'vAUTH', 'auth capture') returning trans_id as ct_auth \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-04-03', -50, 'vSNAP', 'snapshot') returning trans_id as ct_snap \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-04-04', -50, 'vBF', 'backfill') returning trans_id as ct_bf \gset

insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat) values (:'ta','cashflow','Expense','Groceries') returning id as a_exp \gset
insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat) values (:'ta','cashflow','Expense','Rent') returning id as a_exp2 \gset
insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat) values (:'ta','cashflow','Expense','SnapCat') returning id as a_snap \gset

-- =====================================================================
-- AC3 — CAPTURE CORRECTNESS (postgres; the DEFINER capture helper runs as owner regardless).
--   ct_cap: birth -> sub_cat edit -> metadata edit -> note-only edit (no capture).
-- =====================================================================
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:ct_cap, :a_exp);
-- capture the immutable v1 row id for the AC1 immutability attacks.
select id as h_id from pfin.account_trans_annotation_history where trans_id = :ct_cap and version_seq = 1 \gset

-- (3a) 023 INSERT -> history v1 (count 1, version_seq 1, op insert).
select is(
  (select count(*)::text || '|' || max(version_seq)::text || '|' || string_agg(distinct op, ',')
     from pfin.account_trans_annotation_history where trans_id = :ct_cap),
  '1|1|insert',
  '(3a) capture birth: a 023 INSERT writes exactly one history v1 (count 1, version_seq 1, op=insert)'
);
-- (3b) sub_cat_id UPDATE -> v2 (op=update).
update pfin.account_trans_annotation set sub_cat_id = :a_exp2 where trans_id = :ct_cap;
select is(
  (select count(*)::text || '|' || max(version_seq)::text || '|'
          || (select op from pfin.account_trans_annotation_history where trans_id = :ct_cap order by version_seq desc limit 1)
     from pfin.account_trans_annotation_history where trans_id = :ct_cap),
  '2|2|update',
  '(3b) capture change: a sub_cat_id UPDATE writes a new version (count 2, version_seq 2, op=update)'
);
-- (3c) metadata UPDATE -> v3 (op=update). Uses the NON-RESERVED key `note` (metadata.reason is
--   basis_adjust-only under 034 R3, and ct_cap is a STANDARD txn — a reason here would trip
--   'misplaced reason'); the metadata-change-capture intent (a DISTINCT metadata edit → new
--   version) is unchanged.
update pfin.account_trans_annotation set metadata = '{"note":"reclassified"}'::jsonb where trans_id = :ct_cap;
select is(
  (select count(*)::text || '|' || max(version_seq)::text || '|'
          || (select op from pfin.account_trans_annotation_history where trans_id = :ct_cap order by version_seq desc limit 1)
     from pfin.account_trans_annotation_history where trans_id = :ct_cap),
  '3|3|update',
  '(3c) capture change: a metadata UPDATE writes a new version (count 3, version_seq 3, op=update)'
);
-- (3d) note-only UPDATE -> NO new row (DISTINCT-FROM capture gate).
update pfin.account_trans_annotation set note = 'just a note, not routing-relevant' where trans_id = :ct_cap;
select is(
  (select count(*) from pfin.account_trans_annotation_history where trans_id = :ct_cap)::int, 3,
  '(3d) capture gate: a note-only UPDATE writes NO history row (sub_cat_id/metadata IS NOT DISTINCT FROM old)'
);
-- (3e) version_seq monotonic 1,2,3 per trans_id.
select is(
  (select string_agg(version_seq::text, ',' order by version_seq)
     from pfin.account_trans_annotation_history where trans_id = :ct_cap),
  '1,2,3',
  '(3e) version_seq monotonic: exactly 1,2,3 per trans_id (max+1; UNIQUE(trans_id,version_seq) fail-safes a race)'
);

-- =====================================================================
-- AC1 — APPEND-ONLY IMMUTABILITY (attacks the immutable v1 row h_id; each RAISES).
-- =====================================================================
-- (1a) UPDATE (postgres/owner — triggers fire for owner too).
select throws_like(
  format($$ update pfin.account_trans_annotation_history set op = 'update' where id = %s $$, :h_id),
  '%is immutable%UPDATE blocked%',
  '(1a) append-only: an UPDATE on a history row RAISES (block_mutation fence — corrections land as a new version)'
);
-- (1b) DELETE.
select throws_like(
  format($$ delete from pfin.account_trans_annotation_history where id = %s $$, :h_id),
  '%is immutable%DELETE blocked%',
  '(1b) append-only: a DELETE on a history row RAISES (block_mutation fence)'
);
-- (1c) TRUNCATE (statement-level fence; distinct message).
select throws_like(
  'truncate pfin.account_trans_annotation_history',
  '%is immutable%TRUNCATE blocked%',
  '(1c) append-only: TRUNCATE RAISES (statement-level block_truncate fence — the audit trail cannot be wiped)'
);
-- (1d) service_role UPDATE (RLS-bypass) STILL blocked by the trigger. Grants held OPEN
--      (test-only, rolled back) so the trigger — not a missing ACL — is the proven gate.
--      SELECT is required too (the UPDATE ... WHERE reads rows) + schema USAGE; else the ACL
--      denies before the trigger is reached (the 004 grant-then-trigger lesson).
grant usage on schema pfin to service_role;
grant select, update on pfin.account_trans_annotation_history to service_role;
select set_config('role', 'service_role', true);
select throws_like(
  format($$ update pfin.account_trans_annotation_history set op = 'update' where id = %s $$, :h_id),
  '%is immutable%UPDATE blocked%',
  '(1d) cross-tier: a service_role UPDATE (RLS bypassed, grant held open) is STILL blocked by the immutability TRIGGER'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- AC2 — DEFINER-ONLY-WRITE / un-forgeable (2a/2b = catalog privilege facts).
-- =====================================================================
-- (2a) authenticated holds NO direct INSERT grant on history.
select ok(
  not has_table_privilege('authenticated', 'pfin.account_trans_annotation_history', 'INSERT'),
  '(2a) DEFINER-only: authenticated holds NO direct INSERT grant on history (un-forgeable via PostgREST)'
);
-- (2b) authenticated holds SELECT (owner-only read via RLS).
select ok(
  has_table_privilege('authenticated', 'pfin.account_trans_annotation_history', 'SELECT'),
  '(2b) authenticated holds SELECT on history (owner-only read composes via the parent-chain policy)'
);

-- =====================================================================
-- AC5 — SNAPSHOT TRUTH (postgres): history.sub_cat_id survives deletion of the referenced
--   user_taxonomy row (no FK). Set up ct_snap -> a_snap (history v1 snapshots a_snap), then
--   move the LIVE 023 row off a_snap so the taxonomy row is deletable (023 FK is ON DELETE
--   RESTRICT — only a live reference blocks it), then delete a_snap and assert the snapshot.
-- =====================================================================
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:ct_snap, :a_snap);
update pfin.account_trans_annotation set sub_cat_id = :a_exp where trans_id = :ct_snap;  -- live row off a_snap
delete from pfin.user_taxonomy where id = :a_snap;                                        -- now unreferenced-live -> deletable
select is(
  (select sub_cat_id from pfin.account_trans_annotation_history where trans_id = :ct_snap and version_seq = 1),
  :a_snap::bigint,
  '(5a) snapshot truth: history v1.sub_cat_id retains the (now-deleted) taxonomy id — no FK, audit-truthful about the past'
);

-- =====================================================================
-- AC6 — BACKFILL-BIRTH (postgres; capture trigger disabled to mint a history-less 023 row).
-- =====================================================================
alter table pfin.account_trans_annotation disable trigger account_trans_annotation_capture_history;
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:ct_bf, :a_exp);  -- no history yet
alter table pfin.account_trans_annotation enable trigger account_trans_annotation_capture_history;

-- Run the migration's backfill INSERT...SELECT verbatim (births v1 for history-less 023 rows).
insert into pfin.account_trans_annotation_history
  (trans_id, version_seq, sub_cat_id, metadata, op, captured_at, changed_by)
select a.trans_id, 1, a.sub_cat_id, a.metadata, 'insert', a.created_at, null
  from pfin.account_trans_annotation a
 where not exists (
   select 1 from pfin.account_trans_annotation_history h where h.trans_id = a.trans_id
 );
-- (6a) backfill births exactly one v1 op=insert row (changed_by NULL — actor unknown).
select is(
  (select count(*)::text || '|' || max(version_seq)::text || '|' || string_agg(distinct op, ',')
          || '|' || (select coalesce(changed_by::text, 'null')
                       from pfin.account_trans_annotation_history where trans_id = :ct_bf order by version_seq limit 1)
     from pfin.account_trans_annotation_history where trans_id = :ct_bf),
  '1|1|insert|null',
  '(6a) backfill-birth: a pre-existing history-less 023 row gets a v1 op=insert birth row (changed_by NULL)'
);
-- (6b) re-run the backfill -> idempotent (NOT EXISTS adds no duplicate).
insert into pfin.account_trans_annotation_history
  (trans_id, version_seq, sub_cat_id, metadata, op, captured_at, changed_by)
select a.trans_id, 1, a.sub_cat_id, a.metadata, 'insert', a.created_at, null
  from pfin.account_trans_annotation a
 where not exists (
   select 1 from pfin.account_trans_annotation_history h where h.trans_id = a.trans_id
 );
select is(
  (select count(*) from pfin.account_trans_annotation_history where trans_id = :ct_bf)::int, 1,
  '(6b) backfill idempotent: a re-run adds no duplicate (still exactly 1 row for the backfilled trans)'
);

-- =====================================================================
-- AC2c + AC4 — the REAL authenticated path.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (2c) a direct authenticated INSERT into history fails closed at the GRANT layer.
select throws_like(
  format($$ insert into pfin.account_trans_annotation_history (trans_id, version_seq, sub_cat_id, op)
              values (%s, 99, %s, 'insert') $$, :ct_cap, :a_exp),
  '%permission denied for table account_trans_annotation_history%',
  '(2c) DEFINER-only-write: a direct authenticated INSERT into history fails at the GRANT layer (sole write path is the DEFINER helper)'
);
-- (4a) authenticated A annotates a fresh txn -> the DEFINER capture writes one birth row.
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:ct_auth, :a_exp);
select is(
  (select count(*) from pfin.account_trans_annotation_history where trans_id = :ct_auth)::int, 1,
  '(4a) authenticated capture path: A''s real 023 edit writes exactly one history birth row via the DEFINER helper'
);
-- (4b) changed_by = A's uid (the DEFINER helper resolves auth.uid()).
select is(
  (select changed_by from pfin.account_trans_annotation_history where trans_id = :ct_auth),
  :'ta'::uuid,
  '(4b) changed_by attribution: the DEFINER helper stamps auth.uid()=A on the version A wrote (request GUC resolves under DEFINER)'
);
select set_config('role', 'postgres', true);

-- (4c) two-tenant read isolation: B reads 0 of A's history.
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from pfin.account_trans_annotation_history where trans_id = :ct_auth)::bigint, 0::bigint,
  '(4c) two-tenant read isolation: B reads 0 of A''s history (parent-chain rd_access-JOIN SELECT policy)'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;

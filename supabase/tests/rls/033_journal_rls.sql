-- =====================================================================
-- Per-Wave battery — M2 (SELF-295): pfin.journal — the double-entry GROUPING parent
--   (direct-owner RLS, users_id = auth.uid(), WRITE-LIVE full CRUD; the 025 aal2 backstop
--   inherited on all four policies) + the journal_id attachment column on the 023 MUTABLE
--   annotation overlay + the Decision-3 CANONICAL #12 matched-tenant leg fence
--   fn_account_trans_annotation_matched_journal (HYBRID-resolved: leg tenant chain-resolved
--   trans_id -> account_trans.account_id -> account.users_id; journal tenant read directly;
--   BEFORE INSERT OR UPDATE WHEN journal_id IS NOT NULL; SECURITY INVOKER; NULL-safe
--   fail-closed NOT EXISTS -> raise). V1-SHIP-BLOCK; JOINT-REVIEW-MANDATORY (Decision-3
--   family + multi-tenant isolation). This battery is the paired non-vacuous pgTAP proof
--   the migration does NOT merge without (SECURITY §4.5; C6 EXPOSURE-gating).
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/033_journal.sql
--   - pfin.journal (journal_id identity PK; users_id uuid NOT NULL default auth.uid()
--       -> auth.users ON DELETE CASCADE = SOLE tenant anchor, NOT-D3; group_type text CHECK
--       in transfer/transfer_in_kind/compound; status text default 'open' CHECK in
--       open/closed; description text NULL; created/updated_at). RLS ENABLED; four
--       direct-owner policies journal_select/insert/update/delete, EACH users_id = auth.uid()
--       AND the 025 aal2 backstop clause (COALESCE null-safe). journal_update gates BOTH
--       USING + WITH CHECK (no cross-tenant close/reopen, no users_id reassignment —
--       Decision 7 M2 cond 4). grant select,insert,update,delete to authenticated; anon
--       zero-grant; service_role UNGRANTED (cond 5). trigger journal_set_updated_at reuses
--       the 001 DEFINER allowlist #1 (no new DEFINER).
--   - pfin.account_trans_annotation.journal_id (bigint NULL -> pfin.journal(journal_id),
--       ON DELETE NO ACTION). NULL = unattached (default). The leg -> group link.
--   - pfin.fn_account_trans_annotation_matched_journal() (Decision-3 CANONICAL #12) — the
--       #10 sub_cat clone, HYBRID-resolved. SECURITY INVOKER; set search_path=''; the
--       explicit j.users_id = acc.users_id predicate is AUTHORITATIVE regardless of RLS.
-- Prereqs exercised (on the 001->033 reset stack): 001 (pfin schema, auth.uid(),
--   fn_refresh_updated_at); 003 (pfin.account + the fn_grant_creator_access DEFINER trigger
--   the annotation RLS chain JOINs — seeds account_users rd=t/wr=t on account insert); 004
--   (pfin.account_trans — the trans_id the #12 fence chain-resolves + the 023 FK target); 006
--   (account_trans rd/wr_access-JOIN RLS the annotation RLS + the fence subquery compose
--   with); 023 (pfin.account_trans_annotation — the overlay that gains journal_id + carries
--   the #10 fence, skipped here by a NULL sub_cat_id); 024/025 (pfin.user_settings + the aal2
--   backstop clause this table inherits). auth.jwt() reads request.jwt.claims (PG 17 stack);
--   the aal dimension rides _rls.set_tenant_aal / _rls.count_as (already in the shared verbs).
--
-- Reuses the 022/023/025/032 idiom: \ir shared verbs; ALL-LOWERCASE \gset literals (005
--   case-fold lesson); SQLSTATE-precise throws_ok(P0001) on the #12 fence (004 all-42501
--   false-green lesson — the fence RAISE is P0001, distinct from the RLS 42501 / '%violates
--   row-level security policy%'; SELF-298 switched these from message-match throws_like to
--   P0001 so the fence-message softening cannot RED CI); role restored to postgres between blocks (PR
--   #121 _rls-USAGE root-cause); fixtures built at role=postgres (bypasses RLS + ACL, so the
--   backstop + fence are exercised ONLY on the authenticated / service_role paths under test).
--
-- ┌─ WHY THE #12 FENCE HAS TEETH (the 023 LEG-F / 032 AC1 discipline applied) ─────────────┐
-- │ The fence is SECURITY INVOKER. Under authenticated A, both cross-tenant directions RAISE │
-- │ even if the explicit j.users_id = acc.users_id predicate were removed — because A's RLS  │
-- │ makes B's journal (journal_select) AND B's account_trans (006 rd_access) INVISIBLE, so   │
-- │ the fence subquery is empty either way (NOT EXISTS -> raise). That is belt-and-suspenders │
-- │ (3a/3b) — NECESSARY but NOT sufficient to prove the trigger. (3c)/(3d) isolate the        │
-- │ trigger: under service_role (RLS BYPASSED — BOTH tenants' journals + legs ARE visible to  │
-- │ the subquery), the SAME cross-tenant attach STILL RAISES in BOTH directions, so the       │
-- │ explicit chain-resolved predicate — NOT RLS — is the sole gate (LOAD-BEARING if a future  │
-- │ service_role grouping writer is ever added, Decision 7 M2 cond 3). (3f) is the non-vacuous │
-- │ control: a matched (same-tenant) attach under service_role COMMITS -> the fence is owner- │
-- │ mismatch-driven, not a blanket block. NOTE — 033 grants service_role NOTHING; BLOCK 3's   │
-- │ service_role grants are a TEST-ONLY trigger-isolation device, held OPEN in-test (rolled   │
-- │ back with the txn) purely so RLS-bypass exposes the referenced rows and the explicit       │
-- │ predicate is the sole remaining gate (mirrors 023 LEG F / 025 case F honest framing).      │
-- │ (3h) extends the SAME RLS-bypass rigor to the UPDATE-ATTACH path — re-pointing an EXISTING  │
-- │ annotation's journal_id to a foreign journal — proving the BEFORE INSERT OR *UPDATE* trigger │
-- │ fires on UPDATE, not just INSERT (a dropped `or update` would pass every other case).        │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (1a) owner CREATE: A inserts its own journal -> RED if journal_insert WITH CHECK over-blocked the owner (feature dead).
--   (1b) owner READ (not over-restrictive): A sees exactly its 2 journals -> RED if journal_select were over-restrictive.
--   (1c) owner UPDATE / CLOSE: A closes its own journal (status open->closed) -> RED if journal_update USING/WITH CHECK over-blocked.
--   (1d) owner REOPEN: A reopens same-tenant (closed->open) -> RED if reopen were blocked (C-i: same-tenant reopen is allowed).
--   (1e) owner DELETE: A deletes its own UNATTACHED journal -> RED if the DELETE grant/policy were missing.
--   (1f) DELETE applied: the deleted journal is gone (not a silent 0-row no-op).
--   (2a) NON-VACUOUS control: B creates its OWN journal -> RED-proof the cross-tenant rejections below are mismatch-driven, not a blanket B block.
--   (2b) cross-tenant READ fails closed: B reads 0 of A's journals -> RED if journal_select leaked.
--   (2c) cross-tenant INSERT (forge users_id=A) fails closed: RLS WITH CHECK rejects -> RED if the WITH CHECK were dropped.
--   (2d) cross-tenant UPDATE (close) blocked: B's close of A's journal matches 0 rows (journal_update USING) -> A's status UNCHANGED (cross-tenant close/reopen blocked).
--   (2e) cross-tenant DELETE blocked: B's delete of A's journal matches 0 rows -> A's journal SURVIVES.
--   (3a) #12 own-leg × FOREIGN-journal under authenticated -> RAISE (belt-and-suspenders: jB RLS-invisible to A).
--   (3b) #12 FOREIGN-leg × own-journal under authenticated -> RAISE (belt-and-suspenders: B's leg RLS-invisible to A; BEFORE trigger fires ahead of the RLS WITH CHECK).
--   (3c) #12 LOAD-BEARING own-leg × foreign-journal under service_role (RLS BYPASSED) -> STILL RAISE (explicit predicate is the sole gate).
--   (3d) #12 LOAD-BEARING foreign-leg × own-journal under service_role -> STILL RAISE (mirror direction).
--   (3e) #12 NULL-safe fail-closed: attach to a NON-EXISTENT journal_id -> RAISE the #12 fence (P0001, BEFORE the FK 23503; no NULL <> leak).
--   (3f) #12 NON-VACUOUS control: a matched (same-tenant) attach under service_role COMMITS -> the fence is mismatch-driven.
--   (3g) #12 matched attach under authenticated A (own leg × own journal) -> COMMITS (the real feature works; positive on the authenticated path).
--   (3h) #12 UPDATE-ATTACH load-bearing (service_role, RLS bypassed): re-pointing an EXISTING own-annotation to a FOREIGN journal STILL RAISES -> proves the fence covers BEFORE UPDATE (not just INSERT); RED if `or update` were dropped from the trigger (silent UPDATE-attach leak) or if the fence leaned on RLS. (Sec condition-1 add.)
--   (4a) NULL journal_id INSERT (unattached): the WHEN (journal_id IS NOT NULL) SKIPS the fence -> a leg lands unattached (the default state).
--   (4b) DETACH: an attached annotation UPDATE to journal_id = NULL SKIPS the fence -> detach PASSES.
--   (6a) aal2 backstop READ blocked: totp user + aal1 -> 0 of its OWN journals -> RED if the backstop were dropped from journal_select USING.
--   (6b) aal2 backstop READ non-vacuous: SAME totp user + aal2 -> its 1 journal VISIBLE -> proves (6a) is non-vacuous.
--   (6c) aal2 backstop WRITE blocked: totp user + aal1 INSERT -> RLS WITH CHECK rejects -> RED if the backstop were dropped from journal_insert WITH CHECK.
--   (6d) aal2 backstop WRITE non-vacuous: SAME totp user + aal2 INSERT COMMITS -> proves (6c) blocks on aal, not on write-incapacity.
--   (6e) NOT-BLANKET READ: a none-policy user + aal1 -> its own journal VISIBLE -> RED if the clause became a blanket aal2.
--   (6f) NOT-BLANKET WRITE: a none-policy user + aal1 INSERT COMMITS -> aal1 is not a blanket write-block.
--   (6g) ISOLATION ⟂ MFA: totp user stepped-up to aal2 STILL sees 0 of A's journals -> the aal conjunct is ANDed with, never replaces, the tenant predicate.
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22 + RT-26 + RT-27; 033 introduces ZERO
--   catalogued §10 instances — authenticated-tier RLS/FK/trigger DDL + one INVOKER fence,
--   NO service_role grant). Decision-3 family: REALIZES CANONICAL instance #12
--   (account_trans_annotation.journal_id -> journal, matched-tenant, HYBRID-resolved) per
--   ADR-031 Decision 8 / Amendment 1 item 8 — realized LAST of the three forward-flagged
--   labels (#13@029 / #14@032 realized ahead; non-contiguous). After 033: 14 labeled / 12
--   DDL-realized. SECURITY DEFINER allowlist UNCHANGED at 4 (the #12 fence + updated_at reuse
--   are INVOKER / allowlist #1). Sec pins the authoritative #12 label at joint-review. This
--   battery is the pgTAP proof #12 catches a REAL cross-tenant violation, incl. under RLS-bypass.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants _rls.tenant_a()/_b() + two
--   dedicated aal tenants (tt = totp, tn = none); NO PII / NO real account numbers / NO prod
--   data. A owns acct-alpha (+ 3 cash legs) + a journal; B owns acct-beta (+ 1 cash leg) + a
--   journal (the cross-tenant targets); tt/tn each own an account + a journal for the aal
--   matrix. users_id set EXPLICITLY on the seed (auth.uid() is NULL under postgres). All in a
--   rolled-back txn.
--
-- ⟦WIRE-VALIDATE⟧ authored against 033's firmed contract. The authoritative run is the
--   001->033 reset stack under CI (pg_prove directory-mode, db-tests.yml, after Backend's
--   clean-apply). Locally the DB is at 027, so a net-zero rolled-back harness applies 033
--   transiently (033 depends only on 001/003/004/006/023/024/025 — all <=027, already applied)
--   to VERIFY green before merge; the committed file does NOT self-apply the migration (CI
--   applies migrations on bring-up). Roles authenticated / service_role / anon name-checked
--   in the blocks; BLOCK 3's service_role grants are held OPEN in-test (rolled back) so the
--   TRIGGER — not a missing ACL — is isolated as the sole gate. plan(28) (was plan(27); +1 =
--   the 3h UPDATE-attach load-bearing assertion, Sec condition-1 add).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(28);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
-- tt/tn are dedicated aal tenants (totp / none) — literal UUIDs (no _rls verb needed).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset
\set tt '00000000-0000-0000-0000-0000000000d1'
\set tn '00000000-0000-0000-0000-0000000000d2'

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres — RLS + ACL bypassed; backstop + fence NOT exercised here).
--  - Four tenants in auth.users. user_settings: tt = 'totp', tn = 'none'; A + B carry NO
--    row (coalesce -> 'none', so plain _rls.set_tenant passes the backstop — the main blocks
--    run un-stepped-up).
--  - A owns acct-alpha + 3 cash legs (leg_a1/leg_a2/leg_a3) + journal jA. B owns acct-beta +
--    1 cash leg (leg_b1) + journal jB. The 003 creator-grant trigger fires on each account
--    insert -> account_users rd=t/wr=t (the annotation RLS chain state).
--  - tt owns acct-tt + journal jTT; tn owns acct-tn + journal jTN (the aal read/write matrix).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb'), (:'tt'), (:'tn');

insert into pfin.user_settings (users_id, mfa_policy) values
  (:'tt', 'totp'), (:'tn', 'none');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-alpha', 'depository', 'household', 'taxable') returning account_id as accta \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'acct-beta', 'depository', 'household', 'taxable') returning account_id as acctb \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tt', 'acct-tt', 'depository', 'household', 'taxable');
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tn', 'acct-tn', 'depository', 'household', 'taxable');

-- A's 3 cash legs (quantity defaults 0 -> passes the 017 qty_requires_security CHECK).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-05-01', 11, 'vA1', 'alpha leg 1') returning trans_id as leg_a1 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-05-02', 12, 'vA2', 'alpha leg 2') returning trans_id as leg_a2 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-05-03', 13, 'vA3', 'alpha leg 3') returning trans_id as leg_a3 \gset
-- B's 1 cash leg.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:acctb, '2026-05-04', 14, 'vB1', 'beta leg 1') returning trans_id as leg_b1 \gset

-- journals (seed at postgres; users_id explicit — auth.uid() is NULL under postgres).
insert into pfin.journal (users_id, group_type, status, description)
  values (:'ta', 'transfer', 'open', 'A journal') returning journal_id as j_a \gset
insert into pfin.journal (users_id, group_type, status, description)
  values (:'tb', 'transfer', 'open', 'B journal') returning journal_id as j_b \gset
insert into pfin.journal (users_id, group_type, status, description)
  values (:'tt', 'transfer', 'open', 'tt journal') returning journal_id as j_tt \gset
insert into pfin.journal (users_id, group_type, status, description)
  values (:'tn', 'transfer', 'open', 'tn journal') returning journal_id as j_tn \gset

-- =====================================================================
-- BLOCK 1 (authenticated A) — owner CRUD + same-tenant close/reopen (the WRITE-LIVE contract).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (1a) owner CREATE: A inserts its own journal (users_id defaults auth.uid() = A).
select lives_ok(
  $$ insert into pfin.journal (group_type, description) values ('compound', 'A journal 2') $$,
  '(1a) owner CREATE: authenticated A inserts its OWN journal (users_id defaults auth.uid()) -> journal_insert WITH CHECK admits the owner write (WRITE-LIVE full CRUD)'
);

-- (1b) owner READ (not over-restrictive): A sees exactly its 2 journals (jA + the new one).
select is(
  (select count(*) from pfin.journal where users_id = :'ta'::uuid)::bigint, 2::bigint,
  '(1b) owner READ: A reads exactly its 2 own journals via journal_select (users_id = auth.uid()) -- not over-restrictive'
);

-- (1c) owner UPDATE / CLOSE: A closes its own journal (status open -> closed).
select lives_ok(
  format($$ update pfin.journal set status = 'closed' where journal_id = %s $$, :j_a),
  '(1c) owner UPDATE / CLOSE: A closes its OWN journal (status open->closed) -> journal_update USING + WITH CHECK admit the owner close'
);

-- (1d) owner REOPEN (C-i: same-tenant reopen allowed): A reopens (closed -> open).
select lives_ok(
  format($$ update pfin.journal set status = 'open' where journal_id = %s $$, :j_a),
  '(1d) owner REOPEN: A reopens its OWN journal same-tenant (closed->open) -> allowed (C-i; the #12 leg fence re-fires on any subsequent overlay attach/update, not on the journal status flip)'
);

-- (1e) owner DELETE: A deletes its own UNATTACHED journal (journal 2 has no attached legs).
select lives_ok(
  $$ delete from pfin.journal where description = 'A journal 2' and users_id = auth.uid() $$,
  '(1e) owner DELETE: A deletes its OWN unattached journal -> journal_delete USING admits the owner delete (full-CRUD contract)'
);
select set_config('role', 'postgres', true);

-- (1f) the owner-DELETE really applied: A is back to 1 journal (jA).
select is(
  (select count(*) from pfin.journal where users_id = :'ta'::uuid)::bigint, 1::bigint,
  '(1f) after A''s owner-DELETE, A owns 1 journal again (jA) -- the delete really applied (not a silent 0-row no-op)'
);

-- =====================================================================
-- BLOCK 2 (authenticated B) — non-vacuous control + cross-tenant read/insert/update/delete
--   fail closed (incl. cross-tenant close/reopen blocked by the UPDATE USING).
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);

-- (2a) NON-VACUOUS control: B creates its OWN journal -> ACCEPTED (proves the cross-tenant
--      rejections below are mismatch-driven, not a blanket B block).
select lives_ok(
  $$ insert into pfin.journal (group_type, description) values ('transfer', 'B journal 2') $$,
  '(2a) control: B creates its OWN journal -> ACCEPTED (the cross-tenant rejections below are mismatch-driven, not a blanket B block)'
);

-- (2b) cross-tenant READ fails closed: B sees 0 of A's journals.
select is(
  (select count(*) from pfin.journal where users_id = :'ta'::uuid)::bigint, 0::bigint,
  '(2b) cross-tenant READ fails closed: B sees 0 of A''s journals (journal_select users_id = auth.uid())'
);

-- (2c) cross-tenant INSERT (forge users_id = A) fails closed: WITH CHECK rejects.
select throws_like(
  format($$ insert into pfin.journal (users_id, group_type, description) values (%L, 'transfer', 'B-forges-A') $$, :'ta'),
  '%violates row-level security policy%',
  '(2c) cross-tenant INSERT fails closed: B forging users_id = A is REJECTED by journal_insert WITH CHECK (users_id = auth.uid())'
);

-- (2d) cross-tenant UPDATE (close) blocked: B's close of A's journal matches 0 rows (USING).
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
update pfin.journal set status = 'closed' where journal_id = :j_a;  -- 0 rows (journal_update USING hides A's row)
select set_config('role', 'postgres', true);
select is(
  (select status from pfin.journal where journal_id = :j_a),
  'open',
  '(2d) cross-tenant close/reopen blocked: after B''s UPDATE targeting A''s journal, its status is UNCHANGED (still open) -- the journal_update USING scoped B to its own rows (0 rows affected)'
);

-- (2e) cross-tenant DELETE blocked: B's delete of A's journal matches 0 rows (USING).
select _rls.set_tenant(:'tb'::uuid);
delete from pfin.journal where journal_id = :j_a;  -- 0 rows (journal_delete USING hides A's row)
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.journal where journal_id = :j_a)::bigint, 1::bigint,
  '(2e) cross-tenant DELETE blocked: after B''s DELETE targeting A''s journal, the row still EXISTS -- the journal_delete USING scoped B to its own rows (0 rows affected)'
);

-- =====================================================================
-- BLOCK 3 (#12 matched-tenant leg fence) — both directions; belt-and-suspenders under
--   authenticated + LOAD-BEARING under service_role (RLS bypassed) + non-vacuous controls.
-- =====================================================================
-- (3a) authenticated A: own leg × FOREIGN journal (jB) -> RAISE (jB RLS-invisible to A).
select _rls.set_tenant(:'ta'::uuid);
select throws_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, journal_id) values (%s, %s) $$, :leg_a1, :j_b),
  'P0001', null,
  '(3a) #12 own-leg × FOREIGN-journal under authenticated A: A attaches its OWN leg to B''s journal -> fn_account_trans_annotation_matched_journal RAISES (belt-and-suspenders: jB is journal_select-invisible to A -> NOT EXISTS -> raise). SQLSTATE-match (P0001, distinct from RLS 42501) so the SELF-298 #12 message softening cannot RED this.'
);
-- (3b) authenticated A: FOREIGN leg (B's) × own journal (jA) -> RAISE (B's leg RLS-invisible).
select throws_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, journal_id) values (%s, %s) $$, :leg_b1, :j_a),
  'P0001', null,
  '(3b) #12 FOREIGN-leg × own-journal under authenticated A: A pulls B''s leg into its OWN journal -> the BEFORE trigger fence RAISES (belt-and-suspenders: B''s account_trans is 006 rd_access-invisible to A; the trigger fires ahead of the RLS WITH CHECK). SQLSTATE-match (P0001, distinct from RLS 42501) so the SELF-298 #12 message softening cannot RED this.'
);
select set_config('role', 'postgres', true);

-- (3c)/(3d)/(3e)/(3f) — the LOAD-BEARING leg under service_role (RLS BYPASSED). Hold the ACLs
--   the fence subquery + the INSERT need OPEN to service_role (TEST-ONLY; rolled back with the
--   txn — 033 grants service_role NOTHING). Under RLS-bypass BOTH tenants' journals + legs ARE
--   visible to the subquery; only the explicit j.users_id = acc.users_id predicate rejects.
grant usage on schema pfin to service_role;
grant select on pfin.journal to service_role;
grant select on pfin.account_trans to service_role;
grant select on pfin.account to service_role;
grant select, insert, update on pfin.account_trans_annotation to service_role;  -- update+select for 3h (UPDATE-attach)

select set_config('role', 'service_role', true);

-- (3c) LOAD-BEARING own-leg × foreign-journal: A's leg × B's journal STILL RAISES.
select throws_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, journal_id) values (%s, %s) $$, :leg_a1, :j_b),
  'P0001', null,
  '(3c) #12 LOAD-BEARING under service_role: RLS BYPASSED (jB IS visible), yet A''s leg × B''s journal STILL RAISES -- the explicit j.users_id = acc.users_id predicate (leg tenant chain-resolved = A != jB.users_id = B) is the SOLE gate. SQLSTATE-match (P0001, distinct from RLS 42501) so the SELF-298 #12 message softening cannot RED this.'
);
-- (3d) LOAD-BEARING mirror: B's leg × A's journal STILL RAISES.
select throws_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, journal_id) values (%s, %s) $$, :leg_b1, :j_a),
  'P0001', null,
  '(3d) #12 LOAD-BEARING mirror under service_role: B''s leg × A''s journal STILL RAISES -- the explicit predicate (leg tenant chain-resolved = B != jA.users_id = A) is the sole gate (mirror direction). SQLSTATE-match (P0001, distinct from RLS 42501) so the SELF-298 #12 message softening cannot RED this.'
);
-- (3e) NULL-safe fail-closed: attach to a NON-EXISTENT journal_id -> RAISE before the FK check.
select throws_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, journal_id) values (%s, %s) $$, :leg_a1, 9999999),
  'P0001', null,
  '(3e) #12 NULL-safe fail-closed: attaching to a NON-EXISTENT journal_id RAISES the fence (NOT EXISTS -> raise, ahead of the FK 23503) -- a missing journal fails closed, no NULL <> leak. SQLSTATE-match (P0001, distinct from RLS 42501) so the SELF-298 #12 message softening cannot RED this.'
);
-- (3f) NON-VACUOUS control: matched (same-tenant) attach under service_role COMMITS.
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, journal_id) values (%s, %s) $$, :leg_a1, :j_a),
  '(3f) #12 control: a matched (A''s leg × A''s journal) attach under service_role COMMITS -> the fence is owner-mismatch-driven, not a blanket block (non-vacuous)'
);
select set_config('role', 'postgres', true);

-- (3g) matched attach under AUTHENTICATED A (own leg × own journal) -> COMMITS (real feature).
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, journal_id) values (%s, %s) $$, :leg_a2, :j_a),
  '(3g) #12 matched attach under authenticated A: A attaches its OWN leg to its OWN journal -> the fence ACCEPTS (leg chain-resolves to A == jA.users_id) and the annotation wr_access WITH CHECK admits the write (the real grouping feature works)'
);
select set_config('role', 'postgres', true);

-- (3h) #12 UPDATE-ATTACH load-bearing mirror of 3c (service_role, RLS BYPASSED). Re-point an
--   EXISTING own-annotation (leg_a1 -> jA, committed at 3f) to B's FOREIGN journal. This is the
--   ONLY assertion on the UPDATE-attach path: 3a-3d are INSERT-attach, 4b UPDATEs to NULL (which
--   SKIPS the fence via the WHEN clause). The fence is BEFORE INSERT OR *UPDATE* — a regression
--   dropping `or update` would silently COMMIT this leak yet pass all other cases. Under
--   service_role RLS is bypassed (jB IS visible), so the explicit predicate is the sole gate on
--   the UPDATE path too. Grants persist in the txn from the 3c-3f block.
select set_config('role', 'service_role', true);
select throws_ok(
  format($$ update pfin.account_trans_annotation set journal_id = %s where trans_id = %s $$, :j_b, :leg_a1),
  'P0001', null,
  '(3h) #12 UPDATE-ATTACH LOAD-BEARING under service_role: re-pointing an EXISTING own-annotation (leg_a1 -> jA) to B''s FOREIGN journal STILL RAISES -- proves the fence covers BEFORE UPDATE (not just INSERT) and the explicit predicate is the sole gate on the UPDATE-attach path; RED if `or update` were dropped from the trigger (silent UPDATE-attach leak) or if the fence leaned on RLS. SQLSTATE-match (P0001, distinct from RLS 42501) so the SELF-298 #12 message softening cannot RED this.'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 4 (NULL journal_id / detach) — the WHEN (journal_id IS NOT NULL) SKIP path.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (4a) NULL journal_id INSERT (unattached): the fence WHEN-clause SKIPS -> a leg lands unattached.
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, journal_id) values (%s, null) $$, :leg_a3),
  '(4a) NULL journal_id INSERT: A annotates a leg with journal_id = NULL (unattached) -> the fence WHEN (new.journal_id IS NOT NULL) SKIPS -> the note-only overlay lands (a leg can be created unattached — the default state)'
);
-- (4b) DETACH: an attached annotation (leg_a2 -> jA, from 3g) UPDATE to journal_id = NULL PASSES.
select lives_ok(
  format($$ update pfin.account_trans_annotation set journal_id = null where trans_id = %s $$, :leg_a2),
  '(4b) DETACH: A detaches leg_a2 from its journal (journal_id -> NULL) -> the fence WHEN-clause SKIPS on the new NULL -> detach PASSES (the mutable grouping-interpretation path)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 6 (aal2 step-up backstop) — totp blocked read+write @ aal1; none passes;
--   non-vacuous @ aal2; isolation ⟂ MFA. Probes SCOPED by users_id (deterministic).
-- =====================================================================
-- (6a) totp user + aal1 -> 0 of its OWN journals (backstop blocks the aal1 direct-API read).
select is(
  _rls.count_as(:'tt'::uuid, 'aal1', format('select count(*) from pfin.journal where users_id = %L', :'tt')),
  0::bigint,
  '(6a) aal2 backstop READ blocked: totp user + aal1 -> 0 of its OWN journals; RED if the backstop were dropped from journal_select USING'
);
-- (6b) SAME totp user + aal2 -> its 1 own journal VISIBLE (proves 6a non-vacuous).
select is(
  _rls.count_as(:'tt'::uuid, 'aal2', format('select count(*) from pfin.journal where users_id = %L', :'tt')),
  1::bigint,
  '(6b) aal2 backstop READ non-vacuous: SAME totp user + aal2 -> its 1 own journal VISIBLE (proves 6a really owns a row); RED if the backstop over-blocked aal2'
);
-- (6c) totp user + aal1 INSERT -> RLS WITH CHECK rejects (backstop false).
select _rls.set_tenant_aal(:'tt'::uuid, 'aal1');
select throws_like(
  $$ insert into pfin.journal (group_type, description) values ('transfer', 'tt-aal1-blocked') $$,
  '%violates row-level security policy%',
  '(6c) aal2 backstop WRITE blocked: totp user + aal1 INSERT -> journal_insert WITH CHECK rejects (backstop false); RED if the backstop were dropped from the WITH CHECK'
);
select set_config('role', 'postgres', true);
-- (6d) SAME totp user + aal2 INSERT -> COMMITS (proves 6c blocks on aal, not write-incapacity).
select _rls.set_tenant_aal(:'tt'::uuid, 'aal2');
select lives_ok(
  $$ insert into pfin.journal (group_type, description) values ('transfer', 'tt-aal2-ok') $$,
  '(6d) aal2 backstop WRITE non-vacuous: SAME totp user + aal2 INSERT COMMITS (backstop satisfied) -- proves 6c blocks on aal, not on write-incapacity'
);
select set_config('role', 'postgres', true);
-- (6e) NOT-BLANKET READ: none user + aal1 -> its own journal VISIBLE.
select is(
  _rls.count_as(:'tn'::uuid, 'aal1', format('select count(*) from pfin.journal where users_id = %L', :'tn')),
  1::bigint,
  '(6e) NOT-BLANKET READ: none-policy user + aal1 -> its own journal VISIBLE; RED if the clause became a blanket aal2 (it would lock out a none user)'
);
-- (6f) NOT-BLANKET WRITE: none user + aal1 INSERT -> COMMITS.
select _rls.set_tenant_aal(:'tn'::uuid, 'aal1');
select lives_ok(
  $$ insert into pfin.journal (group_type, description) values ('transfer', 'tn-aal1-ok') $$,
  '(6f) NOT-BLANKET WRITE: none-policy user + aal1 INSERT COMMITS (backstop true for none) -- aal1 is not a blanket write-block'
);
select set_config('role', 'postgres', true);
-- (6g) ISOLATION ⟂ MFA: totp user stepped-up to aal2 STILL sees 0 of A's journals.
select is(
  _rls.count_as(:'tt'::uuid, 'aal2', format('select count(*) from pfin.journal where users_id = %L', :'ta')),
  0::bigint,
  '(6g) ISOLATION ⟂ MFA: tt stepped-up to aal2 STILL sees 0 of A''s journals -- the aal conjunct is ANDed with, never replaces, the tenant predicate'
);

select * from finish();
rollback;

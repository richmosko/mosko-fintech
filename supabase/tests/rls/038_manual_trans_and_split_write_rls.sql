-- =====================================================================
-- Per-Wave battery — 038 manual cash-entry write path + un-dorm account_trans_split
--   writes (SELF-202 / §2.4.3.a; ADR-032). C6 EXPOSURE-GATING per ADR-023; V1-SHIP-BLOCK;
--   JOINT-REVIEW-MANDATORY (aal2/C3 fence-surface change + the un-dormed write path).
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/038_manual_trans_and_split_write.sql
--   PART A — un-dorms pfin.account_trans_split writes (029 shipped SELECT-only / write-
--     dormant): adds account_trans_split_insert / _update / _delete (wr_access-JOIN + the
--     aal2 backstop conjunct) + GRANT insert,update,delete to authenticated; AND closes the
--     029 C3 gap by ALTERing account_trans_split_select to AND-in the same aal2 backstop.
--     The 029 Σ=parent DEFERRABLE constraint trigger + the #13 chain-resolved matched-tenant
--     sub_cat fence already exist — un-dorming ACTIVATES them on the authenticated write path.
--   PART B — pfin.fn_create_manual_trans(p_account_id, p_transaction_date, p_amount, p_vendor,
--     p_description, p_sub_cat_id, p_note) RETURNS bigint: SECURITY INVOKER, set search_path=''.
--     Atomically INSERTs a manual CASH account_trans row (transaction_type='standard';
--     security_id NULL + quantity 0 default → 017 CHECK; plaid_transaction_id/import_hash NULL)
--     and, WHEN p_sub_cat_id or p_note is supplied, its 023 category/note annotation — in ONE
--     txn under the caller's RLS. The cash sibling of 013's fn_create_manual_account.
--     REVOKE EXECUTE FROM PUBLIC (denies anon) + GRANT EXECUTE TO authenticated only.
--
-- ⟦PAIRED EDIT — READ THIS⟧ 038 un-doms 029's write-dormant table. CI runs pg_prove in
--   DIRECTORY mode against the FULLY-APPLIED 001→038 stack, so 029's BLOCK 4 (which asserted
--   authenticated INSERT/UPDATE/DELETE fail closed at the GRANT layer with 'permission denied
--   for table account_trans_split') is now FALSE — after 038's write GRANT those writes reach
--   RLS, not the ACL. 029 BLOCK 4 is therefore REMOVED in the SAME PR (029 plan 17→14) and the
--   un-dormed write-path coverage lives HERE. Ship both files together (a green CI with only one
--   would be vacuous — the memory "verify paired artifacts before push" discipline).
--
-- Prereqs exercised (001→038 reset stack; Backend owns the clean-apply): 001 (pfin,
--   fn_refresh_updated_at, auth.uid()), 003 (account + fn_grant_creator_access DEFINER creator-
--   grant trigger → account_users rd=t/wr=t), 004 (account_trans immutable ledger — the FK
--   target + numeric(20,4) amount + NaN CHECK), 006 (account_trans rd/wr_access-JOIN RLS +
--   grant — the chain the RPC + split policies compose under), 009 (user_taxonomy — the sub_cat
--   FK target + auth.uid()-scoped SELECT), 017 (cash-row shape: quantity=0 OR security_id NOT
--   NULL), 023 (account_trans_annotation + the #10 chain-resolved matched-tenant fence), 024
--   (user_settings.mfa_policy — the aal2 backstop's control variable), 025 (the aal2 backstop
--   clause 038 mirrors onto split), 029 (account_trans_split — table + Σ trigger + #13 fence +
--   view; the write-dormant table 038 un-doms), 030 (transaction_type='standard' + the Trade-
--   constraint fence on account_trans_annotation).
--
-- Reuses the 013/023/025/029 idiom: \ir shared verbs, ALL-LOWERCASE \gset literals (005 case-
--   fold lesson), %L for uuids / %s for bigints (022 lesson), SQLSTATE-precise throws_ok +
--   MESSAGE-precise throws_like (004 all-42501 false-green lesson), role restored to postgres
--   between blocks (PR #121 _rls-USAGE root-cause), aal via _rls.set_tenant_aal / _rls.count_as.
--
-- ┌─ DEFERRED-Σ ON THE UN-DORMED WRITE PATH (why BLOCK 1 owns the flushes) ──────────────────┐
-- │ 029 proved the Σ=parent DEFERRABLE trigger under PRIVILEGED (write-dormant era) writes.  │
-- │ BLOCK 1 re-proves it composes with the UN-DORMED AUTHENTICATED write path. The trigger   │
-- │ is SECURITY INVOKER — at flush it runs AS the writer and sums the children under the      │
-- │ writer's RLS, so the sum is correct ONLY if every pending row is the writer's own. BLOCK  │
-- │ 1 therefore writes exclusively as tenant A (mfa 'none' → aal backstop is a no-op) and no  │
-- │ cross-tenant split row is pending during any flush (T's C3 read fixture is seeded LATER,  │
-- │ after the last flush, and NEVER flushed). Same SET CONSTRAINTS choreography as 029: stage │
-- │ DEFERRED, fire with `set constraints all immediate`, re-defer before the next set.        │
-- └──────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ ATOMICITY IS THE ONLY ORPHAN GUARD ON THE RPC NEGATIVE PATHS (the 013 discipline) ──────┐
-- │ fn_create_manual_trans writes to the IMMUTABLE ledger (004) which has NO authenticated    │
-- │ DELETE. So when statement-2 (the annotation) raises (#10 or Trade fence), the ONLY thing  │
-- │ that prevents an orphaned account_trans row is transaction rollback. Each RPC-negative    │
-- │ assertion is therefore PAIRED with a distinct-vendor orphan-count = 0 (4b/4d/4f).         │
-- └──────────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   SPLIT WRITES (un-dormed):
--   (1a) owner INSERT + balanced Σ PASSES — RED if the un-dorm INSERT policy/grant were absent
--        (the split feature would never admit an owner write) or the Σ over-raised on a balanced set.
--   (1b) unbalanced set RAISES at COMMIT — RED if Σ did not compose with the authenticated write
--        (a money-incorrect split would commit). The money-correctness negative; inversion-proven vs 1a.
--   (1c) UNSPLIT (delete whole set → 0 children) PASSES — RED if the DELETE grant/policy were
--        absent or the ≥1-child gate mis-fired (revert-to-parent-only would be impossible).
--   (2a) cross-tenant INSERT fails closed (wr_access) — RED if the INSERT WITH CHECK leaked (B
--        writes a child on A's txn). NULL sub_cat isolates the RLS gate from the #13 fence (023 (2c)).
--   (2b) #13 cross-tenant sub_cat rejected through the write — RED if the 029 #13 fence did not
--        fire on the un-dormed INSERT (A tags its own child with B's Sub-Cat and it commits).
--   (2c) cross-account re-parent UPDATE fails closed — RED if the UPDATE WITH CHECK leaked (a
--        child re-pointed onto an account the caller lacks wr_access on).
--   fn_create_manual_trans:
--   (3a)/(3b) owner-create with cat: exactly one A-owned cash row + its annotation land ATOMICALLY
--        in one call — RED if the RPC dropped either write or mis-set the cash shape/ownership.
--   (3c)/(3d) owner-create without cat/note: the row lands with NO annotation — RED if the overlay
--        INSERT were unconditional (an uncategorized entry could never land) or wrongly created.
--   (4a)/(4b) cross-tenant-account create fails closed + NO orphan — RED if the account_trans_insert
--        wr_access-JOIN were bypassed through the RPC, or the two writes were not one transaction.
--   (4c)/(4d) cross-tenant Sub-Cat (#10) rejected through the RPC + NO orphan — RED if the RPC
--        bypassed the 023 #10 fence, or the statement-2 raise orphaned the statement-1 ledger row.
--   (4e)/(4f) Trade-cat-on-cash (030) rejected through the RPC + NO orphan — RED if the 030 Trade-
--        consistency fence were bypassed (a security_id-NULL cash row tagged 'Trade' would commit).
--   C3 FIX (account_trans_split_select aal2 backstop):
--   (5a) totp reader @ aal1 → 0 own rows — RED if the 038 SELECT ALTER did not add the backstop
--        (the 029 un-claused C3 gap — a stolen-password aal1 read of split amounts/cats — reopens).
--   (5b) SAME totp reader @ aal2 → its 2 own rows (5a non-vacuous) — RED if the backstop over-blocked aal2.
--   (5c) intruder @ aal2 → 0 of T's rows — RED if the aal conjunct had REPLACED (not ANDed with)
--        the parent-chain tenant predicate (isolation ⟂ aal).
--   (5d) none reader @ aal1 → its own rows — RED if the ALTER became a BLANKET aal2 (locks out a none user).
--   (5e) totp caller @ aal1 through the RPC → blocked — RED if the account_trans_insert aal2 backstop
--        did not compose through the INVOKER RPC (the migration's headline: step-up enforced with no in-fn aal-check).
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22 + RT-26 + RT-27; 038 adds ZERO catalogued
--   §10 instances — authenticated-tier RLS/policy/GRANT + one SECURITY INVOKER RPC, NO service_role
--   grant/reach → no admission channel). Decision-3 family UNCHANGED — 038 adds NO FK-shaped column:
--   PART A un-doms writes on 029's already-catalogued #13 (account_trans_split.sub_cat_id → user_
--   taxonomy, chain-resolved), it does not add an instance; PART B's p_sub_cat_id flows into the
--   EXISTING 023 #10 annotation fence (defense-in-depth), not a new obligation. The aal2 backstop is
--   an ADR-029 C3 mechanism and the #13/#10 fences are Decision-3 mechanisms — NEITHER is a §10
--   catalogued instance (the 025/023/029 de-conflation). This battery is the pgTAP proof the un-
--   dormed write path + the RPC + the closed C3 gap catch REAL violations.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants _rls.tenant_a()/_b()/_c(); NO PII /
--   NO real account numbers / NO prod data. A (mfa 'none') owns acct-alpha + its parents; B (mfa
--   'none') owns acct-beta (the cross-tenant intruder + target); T (mfa 'totp') owns acct-theta +
--   the C3 aal read fixture. BOTH A + B own OWN cashflow Sub-Cats; A owns a Trade Sub-Cat — every
--   matched PASS + cross-tenant/Trade FAIL has a real referent. account.users_id set EXPLICITLY
--   (auth.uid() NULL under postgres). All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121): `_rls` grants no USAGE to authenticated; every _rls.* call
--   runs at role=postgres (or flips role itself) and each block restores role=postgres before the
--   next; \gset var names are ALL-LOWERCASE; row ids/uuids resolved to LITERALS while privileged.
--
-- ⟦WIRE-VALIDATE⟧ authored against 038's firmed contract; the authoritative run is the 001→038
--   reset stack under CI (pg_prove directory-mode, db-tests.yml, after Backend's clean-apply).
--   Roles authenticated / anon name-checked in the blocks. plan(21).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case → ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(21);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — bypasses RLS + ACL; the write policies + the aal2
-- backstop are exercised ONLY on the authenticated paths under test, never during setup).
--  - Three tenants. user_settings: A 'none', B 'none', T 'totp' (the C3 step-up subject).
--  - Accounts via the 003 creator-grant trigger (rd=t/wr=t). A: acct-alpha; B: acct-beta;
--    T: acct-theta.
--  - account_trans CASH parents (security_id NULL + quantity 0 default → 017 CHECK):
--      A: sp_bal(100) balanced-Σ + owner-INSERT, sp_imb(50) unbalanced-Σ, sp_uns(40) UNSPLIT,
--         sp_rep(80) re-parent source, sp_fence(30) #13-through-write.
--      B: bt(70) — B's own txn (cross-tenant write target + re-parent destination).
--      T: tt(90) — T's split parent (C3 aal read fixture; children seeded in BLOCK 5).
--  - user_taxonomy: A a_sub (cashflow Expense/Groceries) matched + a_trade (asset Trade/BTO)
--    for the Trade-on-cash reject; B b_sub (cashflow Expense/Groceries) the cross-tenant referent.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc');

insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta', 'none'), (:'tb', 'none'), (:'tc', 'totp');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-alpha', 'depository', 'household', 'taxable') returning account_id as accta \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'acct-beta', 'depository', 'household', 'taxable') returning account_id as acctb \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tc', 'acct-theta', 'depository', 'household', 'taxable') returning account_id as acctt \gset

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-03-01', 100, 'vBAL', 'A balanced-split parent') returning trans_id as sp_bal \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-03-02', 50, 'vIMB', 'A imbalance-split parent') returning trans_id as sp_imb \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-03-03', 40, 'vUNS', 'A unsplit parent') returning trans_id as sp_uns \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-03-04', 80, 'vREP', 'A re-parent source') returning trans_id as sp_rep \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-03-05', 30, 'vFEN', 'A #13-fence parent') returning trans_id as sp_fence \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:acctb, '2026-03-06', 70, 'vB', 'B own txn (cross-tenant target)') returning trans_id as bt \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:acctt, '2026-03-07', 90, 'vT', 'T split parent (C3 read fixture)') returning trans_id as tt \gset

insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat)
  values (:'ta', 'cashflow', 'Expense', 'Groceries') returning id as a_sub \gset
insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat)
  values (:'ta', 'asset', 'Trade', 'BTO') returning id as a_trade \gset
insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat)
  values (:'tb', 'cashflow', 'Expense', 'Groceries') returning id as b_sub \gset

-- =====================================================================
-- BLOCK 1 — Σ=parent DEFERRABLE constraint on the UN-DORMED authenticated write path.
--   Runs FIRST; owns all SET CONSTRAINTS IMMEDIATE flushes (029 DEFERRED-Σ model). Every
--   write is authenticated A (mfa 'none' → aal backstop is a no-op at any aal); only A's own
--   split rows are ever pending at a flush → the SECURITY INVOKER Σ trigger (running as A)
--   sums the full child set under A's RLS correctly.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
set constraints all deferred;

-- (1a) un-dormed owner INSERT + balanced Σ: A inserts a balanced 2-child set (60+40 = parent
--      100) on its OWN txn → admitted by account_trans_split_insert (wr_access + aal2 backstop)
--      AND passes the deferred Σ=parent check at flush.
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount, display_order)
  values (:sp_bal, null, 60, 1);
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount, display_order)
  values (:sp_bal, null, 40, 2);
select lives_ok(
  'set constraints all immediate',
  '(1a) un-dormed owner write + balanced Σ: authenticated A inserts a balanced 2-child split (60+40 = parent 100) on its OWN txn → admitted by the un-dormed INSERT policy/grant AND passes the deferred Σ=parent check at flush'
);
set constraints all deferred;

-- (1b) unbalanced split rejected at COMMIT (money-correctness invariant; inversion-proven vs 1a).
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount)
  values (:sp_imb, null, 30);
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount)
  values (:sp_imb, null, 15);
select throws_ok(
  'set constraints all immediate',
  'P0001', null,
  '(1b) unbalanced split rejected at COMMIT: authenticated A''s 30+15 = 45 != parent 50 RAISES the Σ=parent deferred constraint at flush (the money-correctness invariant fires on the un-dormed write path)'
);
delete from pfin.account_trans_split where account_trans_id = :sp_imb;  -- clean before the next flush
set constraints all deferred;

-- (1c) UNSPLIT (delete whole set) PASSES: A creates then deletes the entire child set on its
--      OWN parent → 0 children → the ≥1-child gate passes at flush (revert-to-parent-only).
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount)
  values (:sp_uns, null, 40);
delete from pfin.account_trans_split where account_trans_id = :sp_uns;
select lives_ok(
  'set constraints all immediate',
  '(1c) UNSPLIT PASSES: A creates then deletes the entire child set on its OWN parent → 0 children → the ≥1-child gate passes the deferred Σ check (revert-to-parent-only; enabled by the un-dormed DELETE grant + policy)'
);
set constraints all deferred;
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 2 — un-dormed write-path RLS + fence isolation (synchronous; no Σ flush after BLOCK 1,
--   so leftover pending events from the writes here are discarded at the final rollback).
-- =====================================================================
-- (2a) cross-tenant write fails closed (wr_access): B inserts a child on A's txn with a NULL
--      sub_cat (NULL skips the #13 fence WHEN-clause → the RLS WITH CHECK is the sole gate; the
--      023 (2c) lesson). B holds no wr_access on acct-alpha → REJECT.
select _rls.set_tenant(:'tb'::uuid);
select throws_like(
  format($$ insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount) values (%s, null, 10) $$, :sp_bal),
  '%violates row-level security policy%',
  '(2a) cross-tenant write fails closed: authenticated B inserts a split child on A''s txn (NULL sub_cat skips the #13 fence) → the account_trans_split_insert wr_access-JOIN WITH CHECK REJECTS (B holds no wr_access on acct-alpha)'
);
select set_config('role', 'postgres', true);

-- (2b) #13 cross-tenant sub_cat rejected through the un-dormed write: A inserts a child on its
--      OWN txn (wr_access ok) tagged with B's Sub-Cat → the 029 #13 chain-resolved fence (BEFORE
--      INSERT, now active on the write path) RAISES. SQLSTATE-match P0001 (029 (2b) idiom).
select _rls.set_tenant(:'ta'::uuid);
select throws_ok(
  format($$ insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount) values (%s, %s, 30) $$, :sp_fence, :b_sub),
  'P0001', null,
  '(2b) #13 cross-tenant sub_cat rejected through the write: A tags a split child on its OWN txn with B''s Sub-Cat → fn_account_trans_split_matched_sub_cat RAISES on the un-dormed authenticated INSERT (chain sp_fence → acct-alpha → A != b_sub.users_id = B)'
);

-- (2c) cross-account re-parent (UPDATE) fails closed: A owns a child on its OWN parent, then
--      re-points account_trans_id onto B's txn (acct-beta, A lacks wr_access) → the
--      account_trans_split_update WITH CHECK (post-image wr_access-JOIN) REJECTS. The child
--      insert is never flushed (its Σ event is discarded at the final rollback).
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount)
  values (:sp_rep, null, 80) returning id as rep_child \gset
select throws_like(
  format($$ update pfin.account_trans_split set account_trans_id = %s where id = %s $$, :bt, :rep_child),
  '%violates row-level security policy%',
  '(2c) cross-account re-parent fails closed: A re-points its OWN split child onto B''s txn (acct-beta) → the account_trans_split_update WITH CHECK (post-image wr_access-JOIN) REJECTS — a child cannot be re-parented onto an account the caller lacks wr_access on'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 3 — fn_create_manual_trans owner-create PASS (atomic row + CONDITIONAL annotation).
--   The RPC calls run as authenticated A (the composition under test); the read-back asserts
--   are privileged (deterministic full-visibility counts).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- WITH category + note: one call = one cash account_trans row + its 023 annotation, atomically.
select pfin.fn_create_manual_trans(
  :accta, '2026-03-10', 25.50, 'RPC-with-anno', 'manual cash w/ cat', :a_sub, 'a note'
) as rpc_t1 \gset
-- WITHOUT category/note: the row lands, NO annotation (conditional overlay — Unsorted-pending).
select pfin.fn_create_manual_trans(
  :accta, '2026-03-11', 12.00, 'RPC-no-anno', 'manual cash uncategorized'
) as rpc_t2 \gset
select set_config('role', 'postgres', true);

-- (3a) the WITH-cat call created exactly one A-owned CASH standard row (security_id NULL,
--      quantity 0) carrying the passed vendor/amount.
select is(
  (select count(*) from pfin.account_trans
     where trans_id = :rpc_t1 and account_id = :accta and transaction_type = 'standard'
       and security_id is null and quantity = 0 and amount = 25.50 and vendor = 'RPC-with-anno')::bigint,
  1::bigint,
  '(3a) RPC owner-create: exactly one A-owned cash account_trans row (transaction_type=standard, cash shape security_id NULL + quantity 0, amount/vendor as passed) for the returned trans_id'
);
-- (3b) ...and its 023 annotation landed ATOMICALLY in the SAME call (trans_id, a_sub, note).
select is(
  (select count(*) from pfin.account_trans_annotation
     where trans_id = :rpc_t1 and sub_cat_id = :a_sub and note = 'a note')::bigint,
  1::bigint,
  '(3b) RPC owner-create atomic annotation: the 023 category + note annotation landed in the SAME RPC call as the account_trans row (row + annotation composed atomically under the caller''s RLS)'
);
-- (3c) the NO-cat/NO-note call created its cash account_trans row (uncategorized entry is creatable).
select is(
  (select count(*) from pfin.account_trans
     where trans_id = :rpc_t2 and account_id = :accta and transaction_type = 'standard')::bigint,
  1::bigint,
  '(3c) RPC owner-create (uncategorized): the account_trans row lands with NO category/note passed — an untagged/Unsorted-pending manual entry is creatable'
);
-- (3d) ...and NO annotation row (the overlay INSERT is conditional on cat-or-note).
select is(
  (select count(*) from pfin.account_trans_annotation where trans_id = :rpc_t2)::bigint,
  0::bigint,
  '(3d) RPC owner-create (uncategorized): NO annotation row exists for the uncategorized entry → the 023 overlay INSERT is conditional (skipped when both p_sub_cat_id and p_note are NULL)'
);

-- =====================================================================
-- BLOCK 4 — fn_create_manual_trans fail-closed paths, each ATOMIC (the immutable ledger has no
--   authenticated DELETE → rollback is the sole orphan guard; the 013 discipline).
-- =====================================================================
-- (4a) cross-tenant-account create fails closed: A calls the RPC with B's account_id →
--      statement-1 account_trans_insert wr_access-JOIN (006) REJECTS under the caller's RLS.
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ select pfin.fn_create_manual_trans(%s, '2026-03-12', 40, 'RPC-xtenant', 'steal', null, null) $$, :acctb),
  '%violates row-level security policy%',
  '(4a) cross-tenant-account create fails closed: A calls fn_create_manual_trans with B''s account_id → the account_trans_insert wr_access-JOIN WITH CHECK REJECTS under the caller''s RLS (A holds no wr_access on acct-beta)'
);
select set_config('role', 'postgres', true);
-- (4b) atomicity: the (4a) rejection left NO orphan row on the immutable ledger.
select is(
  (select count(*) from pfin.account_trans where vendor = 'RPC-xtenant')::bigint,
  0::bigint,
  '(4b) atomicity (statement-1 reject): the (4a) cross-tenant call left NO orphan account_trans row (all-or-nothing; the immutable ledger has no authenticated DELETE, so rollback is the only guard)'
);

-- (4c) cross-tenant Sub-Cat (#10) rejected through the RPC: A calls the RPC on its OWN account
--      with B's Sub-Cat → statement-1 row succeeds, statement-2 annotation INSERT trips the 023
--      #10 chain-resolved matched-tenant fence → RAISE (P0001, SQLSTATE-match per SELF-298).
select _rls.set_tenant(:'ta'::uuid);
select throws_ok(
  format($$ select pfin.fn_create_manual_trans(%s, '2026-03-13', 40, 'RPC-xsubcat', 'x', %s, null) $$, :accta, :b_sub),
  'P0001', null,
  '(4c) cross-tenant Sub-Cat (#10) rejected through the RPC: A calls the RPC on its OWN account with B''s Sub-Cat → fn_account_trans_annotation_matched_sub_cat RAISES on the composed annotation INSERT (defense-in-depth; the RPC does not bypass #10)'
);
select set_config('role', 'postgres', true);
-- (4d) atomicity: the (4c) fence raise rolled back statement-1 → NO orphan row.
select is(
  (select count(*) from pfin.account_trans where vendor = 'RPC-xsubcat')::bigint,
  0::bigint,
  '(4d) atomicity (statement-2 #10 fence path): the (4c) raise rolled back the statement-1 account_trans row → NO orphan on the immutable ledger'
);

-- (4e) Trade-cat-on-cash (030) rejected through the RPC: A tags a manual CASH entry (security_id
--      NULL) with its OWN Trade Sub-Cat → #10 passes (own tenant), then the 030 Trade-consistency
--      fence RAISES (security_id present ⟺ cat='Trade' is violated). MESSAGE-precise (the 030
--      fence message is not softened — distinguishes it from the #10 raise).
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ select pfin.fn_create_manual_trans(%s, '2026-03-14', 40, 'RPC-tradecash', 'x', %s, null) $$, :accta, :a_trade),
  '%Trade consistency violation%',
  '(4e) Trade-cat-on-cash rejected through the RPC: A tags a manual CASH entry (security_id NULL) with a Trade Sub-Cat → fn_account_trans_annotation_trade_constraints RAISES (security_id present ⟺ cat=Trade violated) even through the RPC'
);
select set_config('role', 'postgres', true);
-- (4f) atomicity: the (4e) trade-fence raise left NO orphan row.
select is(
  (select count(*) from pfin.account_trans where vendor = 'RPC-tradecash')::bigint,
  0::bigint,
  '(4f) atomicity (statement-2 Trade-fence path): the (4e) raise rolled back the statement-1 account_trans row → NO orphan on the immutable ledger'
);

-- =====================================================================
-- BLOCK 5 — the folded-in C3 fix: account_trans_split_select now carries the aal2 backstop
--   (038 PART A ALTER). Two-tenant + two-aal fixture. T (mfa 'totp') is the step-up subject.
--   T's split children are seeded PRIVILEGED here (AFTER BLOCK 1's last flush) with the Σ
--   constraint DEFERRED and NEVER flushed → the pending event is discarded at the final
--   rollback; they exist in-txn purely as the C3 read fixture (balanced 50+40 = parent 90 anyway).
-- =====================================================================
set constraints all deferred;
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount) values (:tt, null, 50);
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount) values (:tt, null, 40);

-- (5a) totp reader @ aal1 → 0 of its OWN split rows (the 038 SELECT ALTER closes the 029 C3 gap).
select is(
  _rls.count_as(:'tc'::uuid, 'aal1', format('select count(*) from pfin.account_trans_split where account_trans_id = %s', :tt)),
  0::bigint,
  '(5a) C3 fix: a totp reader at aal1 sees 0 of its OWN split rows → the aal2 backstop conjunct now gates account_trans_split_select (the 029 un-claused SELECT gap is closed at 038)'
);
-- (5b) SAME totp reader @ aal2 → its 2 own split rows (proves 5a is non-vacuous).
select is(
  _rls.count_as(:'tc'::uuid, 'aal2', format('select count(*) from pfin.account_trans_split where account_trans_id = %s', :tt)),
  2::bigint,
  '(5b) C3 fix non-vacuous: the SAME totp reader stepped up to aal2 sees its 2 own split rows → the backstop is aal-gated, not a blanket block'
);
-- (5c) isolation ⟂ aal: intruder B @ aal2 STILL sees 0 of T's split rows → the aal conjunct is
--      ANDed with, never replaces, the parent-chain tenant predicate.
select is(
  _rls.count_as(:'tb'::uuid, 'aal2', format('select count(*) from pfin.account_trans_split where account_trans_id = %s', :tt)),
  0::bigint,
  '(5c) isolation ⟂ aal: B at aal2 sees 0 of T''s split rows → the aal backstop is ANDed with (never replaces) the parent-chain rd_access tenant fence'
);
-- (5d) not-blanket: a none-policy reader (A) @ aal1 sees its OWN split rows (sp_bal, from 1a) →
--      RED if the ALTER had become a BLANKET aal2 (it would lock out a none user).
select is(
  _rls.count_as(:'ta'::uuid, 'aal1', format('select count(*) from pfin.account_trans_split where account_trans_id = %s', :sp_bal)),
  2::bigint,
  '(5d) not-blanket: a none-policy reader at aal1 sees its 2 own split rows (sp_bal) → the 038 ALTER gates the reader''s own mfa_policy, never a blanket aal2'
);
-- (5e) aal2 backstop composes THROUGH the INVOKER RPC: T (totp) at aal1 calls the RPC on its OWN
--      account → statement-1 account_trans_insert aal2 backstop (006→025) REJECTS under the
--      caller's RLS, with NO in-function aal-check (the migration's headline claim).
select _rls.set_tenant_aal(:'tc'::uuid, 'aal1');
select throws_like(
  format($$ select pfin.fn_create_manual_trans(%s, '2026-03-15', 20, 'RPC-aal1', 'x', null, null) $$, :acctt),
  '%violates row-level security policy%',
  '(5e) aal2 backstop composes through the RPC: a totp caller at aal1 invoking fn_create_manual_trans on its OWN account is REJECTED by the account_trans_insert aal2 backstop (INVOKER-composed; step-up enforced with no in-function aal-check)'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;

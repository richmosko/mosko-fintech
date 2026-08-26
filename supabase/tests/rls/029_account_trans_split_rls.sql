-- =====================================================================
-- Per-Wave battery — pfin.account_trans_split: the M2.5 1:many receipt-split child
--   overlay (SELF-294). ANCHOR α (parent-FK-chain tenancy, NO own users_id — the 023
--   1:1 sibling's 1:many cousin) + WRITE-DORMANT RLS (009 pattern: SELECT policy +
--   SELECT grant only; NO write policy/grant) + the Σ=parent DEFERRABLE constraint
--   trigger + the CHAIN-RESOLVED Decision-3 matched-tenant sub_cat fence (provisional
--   #13 — Sec pins) + the security_invoker reconciliation VIEW.
--   C6 EXPOSURE-GATING per ADR-023; V1-SHIP-BLOCK; JOINT-REVIEW-MANDATORY (Decision-3).
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/029_account_trans_split.sql
--   - pfin.account_trans_split (id identity PK; account_trans_id -> account_trans(trans_id)
--       ON DELETE RESTRICT = SOLE tenant anchor, NOT D3; sub_cat_id NULL -> user_taxonomy(id)
--       ON DELETE RESTRICT = the D3 matched-tenant fence target; amount numeric(20,4) NOT
--       NULL CHECK <> 'NaN'; display_order/note; created/updated_at). NO own users_id.
--   - policy account_trans_split_select (rd_access-JOIN via account_trans_id ->
--       account_trans.account_id -> account_users; the ONLY policy — WRITE-DORMANT).
--   - grant select ONLY to authenticated (ACL-before-RLS). anon zero-grant; service_role
--       ungranted.
--   - fn_account_trans_split_balance() — AFTER INS/UPD/DEL CONSTRAINT TRIGGER, DEFERRABLE
--       INITIALLY DEFERRED (fires at COMMIT / SET CONSTRAINTS IMMEDIATE); SECURITY INVOKER.
--       Σ(children.amount) = parent.amount when >=1 child; unsplit (0) passes; NULL-safe.
--   - fn_account_trans_split_matched_sub_cat() — BEFORE INS/UPD WHEN (sub_cat_id NOT NULL);
--       SECURITY INVOKER; NULL-safe fail-closed; chain-resolves the owning tenant via
--       account_trans_id -> account_trans -> account.users_id and requires user_taxonomy
--       .users_id to match ('cross-tenant Sub-Cat rejected%').
--   - view pfin.account_trans_split_balance (security_invoker=true) — per-line + windowed
--       parent aggregates (children_sum, imbalance_delta, child_count, is_balanced, *_side).
-- Prereqs exercised on the reset stack: 001 (pfin + fn_refresh_updated_at), 003 (account +
--   the DEFINER creator-grant trigger seeding rd=t/wr=t on new.users_id), 004 (account_trans
--   immutable ledger — the FK target + chain middle hop), 006 (account_trans rd/wr-JOIN RLS +
--   grant), 009 (user_taxonomy — the sub_cat_id FK target + auth.uid()-scoped SELECT).
--
-- ┌─ DEFERRED-Σ TEST MODEL (why SET CONSTRAINTS ALL IMMEDIATE is the firing lever) ─────────┐
-- │ The Σ trigger is DEFERRABLE INITIALLY DEFERRED — it fires at COMMIT. This whole pgTAP    │
-- │ battery runs in ONE begin…rollback txn that NEVER commits, so the Σ check fires ONLY on  │
-- │ an explicit `set constraints all immediate` — giving us exact control. Discipline:       │
-- │  (i)  stage a multi-row split set with constraints DEFERRED (else per-row IMMEDIATE would │
-- │       raise on the first, pre-set row);                                                   │
-- │  (ii) fire the check by asserting on `set constraints all immediate` (lives_ok = balanced │
-- │       set passes; throws_ok = imbalance raises);                                          │
-- │  (iii) `set constraints all deferred` again before staging the next set. IMMEDIATE flushes│
-- │       ALL pending events table-wide, so the BALANCE BLOCK RUNS FIRST and every later block│
-- │       does NO immediate flush (its pending events are simply discarded at the final       │
-- │       rollback). ta_p1's balanced children are authored + flushed once, then REUSED as    │
-- │       read fixtures by the RLS + view blocks (kept pristine — the re-parent case uses a   │
-- │       dedicated ta_p4, never ta_p1).                                                      │
-- └─────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ WHY THE FENCE TESTS RUN UNDER postgres (RLS-BYPASS = the load-bearing teeth) ──────────┐
-- │ account_trans_split is WRITE-DORMANT — authenticated has NO write grant, so the fence    │
-- │ CANNOT be exercised under authenticated (a write would 42501 at the ACL, a false-RED     │
-- │ that never reaches the BEFORE trigger). The seed/write path is admin (role=postgres),    │
-- │ exactly per the migration's EXPOSURE note. Under postgres RLS is BYPASSED, so the fence's │
-- │ subquery SEES both tenants' rows and the explicit `ut.users_id = acc.users_id` predicate  │
-- │ is the SOLE remaining gate — the strongest proof it has teeth (the 023 LEG-F / 022 #9     │
-- │ discipline: every matched-tenant fence is authoritative regardless of RLS).              │
-- └─────────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (1a) balanced 3-child set PASSES the deferred Σ check — RED if the trigger mis-summed or
--        over-raised (the feature would never commit a legit split).
--   (1b) imbalanced set RAISES 'split imbalance%' — RED if the Σ invariant were absent/loose
--        (money-incorrect splits would commit). The core money-correctness negative.
--   (1c) ≥1-child GATE: a parent whose children are removed to 0 PASSES — RED if the gate
--        (v_count >= 1) were wrong so an unsplit/emptied parent falsely raised.
--   (1d) re-parent UPDATE RAISES — RED if the OLD/NEW affected-parent loop missed a parent on
--        re-parent (both parents must be re-balanced; moving a child imbalances both).
--   (2a) matched same-tenant sub_cat INSERT PASSES (non-vacuous control) — RED if the fence
--        blanket-blocked own-tenant Sub-Cats.
--   (2b) cross-tenant sub_cat INSERT RAISES 'cross-tenant Sub-Cat rejected%' — RED if the D3
--        fence (or its explicit chain-resolved predicate) were removed (the exact chain attack
--        D3 fences). LOAD-BEARING under RLS-bypass (postgres): the predicate is the sole gate.
--   (2c) NULL sub_cat INSERT PASSES — RED if the WHEN (sub_cat_id IS NOT NULL) clause did not
--        skip NULL (an uncategorized/Suspense line could never land).
--   (2d) cross-tenant UPDATE (re-categorization) RAISES — RED if the fence covered only INSERT
--        (a re-categorize could pivot a split line onto another tenant's Sub-Cat).
--   (3a) owner-reads-own: A reads its 3 own split rows via the parent-chain rd_access policy —
--        RED if the SELECT policy were over-restrictive.
--   (3b) cross-tenant read fails closed: B reads 0 of A's split rows — RED if the parent-chain
--        SELECT policy leaked (B sees A's splits).
--   (4a)/(4b)/(4c) ⟦REMOVED at 038 — see the amendment note below⟧. These asserted the WRITE-
--        DORMANT ACL denial ('permission denied for table account_trans_split'). 038 (SELF-202)
--        un-doms the table (adds the write policies + GRANT insert,update,delete), so those
--        assertions are now FALSE against the applied stack. The un-dormed write-path coverage
--        (owner INSERT, cross-tenant/re-parent fail-closed, Σ-at-commit on the authenticated
--        write, #13-through-write) lives in 038_manual_trans_and_split_write_rls.sql.
--   (5a) NaN amount RAISES 23514 (account_trans_split_amount_finite) — RED if the finite CHECK
--        were dropped (a NaN line would poison Σ).
--   (5b) ±Infinity amount fails closed at numeric(20,4) coercion — RED if the type were widened
--        off the 014 finite discipline.
--   (6a) recon view: A sees is_balanced=true / imbalance_delta=0 / child_count=3 for the
--        balanced parent — RED if the windowed aggregate math were wrong.
--   (6b) recon view security_invoker scoping: B sees 0 view rows for A's parent — RED if the
--        view were security_definer / leaked across the tenant boundary.
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22 + RT-26 + RT-27; 029 adds ZERO catalogued
--   §10 instances — authenticated-tier RLS/FK/trigger/view DDL, write-dormant SELECT path, NO
--   service_role grant → no admission channel). Decision-3 family: 029 REALIZES the provisional
--   canonical #13 (account_trans_split.sub_cat_id -> user_taxonomy, matched-tenant, CHAIN-
--   RESOLVED — the 023 #10 shape). account_trans_id is the SOLE anchor (NOT D3). Sec pins the
--   authoritative #13 label at joint-review (must not collide with the #12/journal_group
--   reservation) — this battery is the pgTAP proof the fence catches a REAL cross-tenant
--   violation, incl. under RLS-bypass (BLOCK 2 under postgres).
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants _rls.tenant_a()/_b(); NO PII /
--   NO real account numbers / NO prod data. A owns acct-alpha (+ parents ta_p1..ta_p4); B owns
--   acct-beta (+ tb_p1) — both via the 003 creator-grant trigger (rd=t/wr=t). BOTH tenants own
--   OWN cashflow Sub-Cats (ratified 5-class enum — 'Expense' per 028/ADR-031 Amendment 1) so
--   every matched PASS + cross-tenant FAIL has a real referent. account.users_id set EXPLICITLY
--   (auth.uid() NULL under postgres). Split rows seeded PRIVILEGED (write-dormant — the only
--   write path). All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121): `_rls` grants no USAGE to authenticated; every _rls.* call
--   runs at role=postgres, each block restores role=postgres before the next; \gset literals are
--   ALL-LOWERCASE. Split-child ids captured to LITERALS for the write-dormant UPDATE/DELETE
--   targets.
--
-- ⟦WIRE-VALIDATE⟧ authored against 029's firmed contract; the authoritative run is the 001->029
--   reset stack (Backend owns the clean-apply). Locally the DB is NOT 029-clean, so a net-zero
--   rolled-back harness \i's the 029 migration transiently before this file; CI (pg_prove
--   directory-mode, db-tests.yml) is the green gate. plan(17) → plan(14) as of the 038 amendment.
--
-- ⟦038 AMENDMENT (SELF-202)⟧ 038 UN-DOMS this write-dormant table (adds account_trans_split
--   insert/update/delete policies + GRANT + ALTERs _select to add the aal2 backstop). CI runs
--   pg_prove in DIRECTORY mode against the FULLY-APPLIED 001→038 stack, so BLOCK 4's write-
--   dormant ACL assertions became FALSE and are REMOVED here (plan 17→14). BLOCKs 1/2/3/5/6
--   (Σ trigger, #13 fence, parent-chain read isolation, finite CHECK, recon view) STAND — 038
--   only widens the write ACL/policy set + adds the SELECT aal2 conjunct (BLOCK 3 reads: A/B
--   carry no user_settings row → mfa 'none' → the new backstop passes at aal1, so 3a/3b hold).
--   The un-dormed write-path battery lives in 038_manual_trans_and_split_write_rls.sql. SHIP
--   BOTH TOGETHER.
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(15);  -- was 17 pre-038, 14 post-038 (BLOCK 4 write-dormant assertions removed), +1 (2e) conversion leg at 084

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed seed path; the ONLY write path
-- since account_trans_split is write-dormant).
--  - Two tenants; A owns acct-alpha, B owns acct-beta (003 creator-grant seeds rd=t/wr=t).
--  - account_trans parents: ta_p1(100) balanced+reused, ta_p2(50) imbalance, ta_p3(30) gate
--    + fence + finite, ta_p4(80) re-parent; tb_p1(70) B's parent.
--  - user_taxonomy: A owns a_sub (cashflow Expense/Groceries); B owns b_sub (Expense/Groceries)
--    — ratified 5-class cats (028/ADR-031 Amendment 1); the cross-tenant fence referents.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-alpha', 'depository', 'household', 'taxable')
  returning account_id as accta \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'acct-beta', 'depository', 'household', 'taxable')
  returning account_id as acctb \gset

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-02-01', 100, 'vP1', 'parent p1 (balanced/reused)') returning trans_id as ta_p1 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-02-02', 50, 'vP2', 'parent p2 (imbalance)') returning trans_id as ta_p2 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-02-03', 30, 'vP3', 'parent p3 (gate/fence/finite)') returning trans_id as ta_p3 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-02-04', 80, 'vP4', 'parent p4 (re-parent)') returning trans_id as ta_p4 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:acctb, '2026-02-05', 70, 'vB1', 'B parent') returning trans_id as tb_p1 \gset

-- A + B each own a posting prototype (ratified enum) — POST-084 these are
-- pfin.posting_prototype rows, not pfin.user_taxonomy (ADR-058 Decision 1's split).
-- a_sub is the matched referent; b_sub is the cross-tenant referent the #13 fence
-- must reject. a_asset_sub is NEW: an asset-domain (storage-side) user_taxonomy
-- row, for the (2e) conversion leg.
-- is_tax_payment added (SELF-245/091, boolean not null no default) — false, not tax semantics here.
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Expense', 'Groceries', false) returning id as a_sub \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'tb', 'Expense', 'Groceries', false) returning id as b_sub \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat, element)
  values (:'ta', 'Brokerage', 'US Equity', 'asset') returning id as a_asset_sub \gset

-- =====================================================================
-- BLOCK 1 — Σ=parent DEFERRABLE balance trigger (RUNS FIRST; owns all SET CONSTRAINTS
--   IMMEDIATE flushes; see the DEFERRED-Σ TEST MODEL box). Constraints start INITIALLY
--   DEFERRED. Split children seeded with sub_cat_id NULL to isolate Σ from the fence
--   (BLOCK 2 tests the fence separately; NULL skips the fence WHEN-clause).
-- =====================================================================
set constraints all deferred;

-- (1a) balanced: 3 children of ta_p1 sum to 100 = parent. Capture child #1 id for the
--      write-dormant UPDATE/DELETE targets (BLOCK 4).
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount, display_order)
  values (:ta_p1, null, 60, 1) returning id as p1_c1 \gset
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount, display_order)
  values (:ta_p1, null, 30, 2);
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount, display_order)
  values (:ta_p1, null, 10, 3);
select lives_ok(
  'set constraints all immediate',
  '(1a) Σ=parent: a balanced 3-child split (60+30+10 = parent 100) PASSES the deferred Σ check at flush'
);
set constraints all deferred;

-- (1b) imbalance: 2 children of ta_p2 sum to 45 != parent 50 -> RAISE at flush.
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount)
  values (:ta_p2, null, 30);
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount)
  values (:ta_p2, null, 15);
select throws_ok(
  'set constraints all immediate',
  'P0001',
  null,
  '(1b) Σ=parent: an imbalanced split (30+15 = 45 != parent 50) RAISES split-imbalance at flush (money-correctness invariant)'
);
-- clean ta_p2's imbalanced children so they cannot contaminate a later flush.
delete from pfin.account_trans_split where account_trans_id = :ta_p2;

-- (1c) >=1-child GATE: seed then remove a child of ta_p3 -> 0 children -> flush PASSES
--      (an unsplit/emptied parent never raises).
set constraints all deferred;
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount)
  values (:ta_p3, null, 30);
delete from pfin.account_trans_split where account_trans_id = :ta_p3;
select lives_ok(
  'set constraints all immediate',
  '(1c) >=1-child gate: a parent whose children are removed to 0 PASSES the deferred check (unsplit parent never raises)'
);
set constraints all deferred;

-- (1d) re-parent UPDATE: stage ta_p4 balanced (50+30 = 80), then move the 30-child to
--      ta_p2 -> BOTH parents imbalanced (ta_p4=50!=80, ta_p2=30!=50) -> flush RAISES,
--      proving the OLD/NEW affected-parent loop re-checks both. (Not reused after.)
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount)
  values (:ta_p4, null, 50);
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount)
  values (:ta_p4, null, 30) returning id as p4_move \gset
update pfin.account_trans_split set account_trans_id = :ta_p2 where id = :p4_move;
select throws_ok(
  'set constraints all immediate',
  'P0001',
  null,
  '(1d) re-parent UPDATE: moving a child across parents RAISES (both OLD ta_p4 and NEW ta_p2 re-balanced -> both imbalanced -> raise)'
);
-- Leave constraints deferred; ta_p4/ta_p2 leftover events discarded at final rollback
-- (no further IMMEDIATE flush in this file). ta_p1 remains pristine (3 balanced children).
set constraints all deferred;

-- =====================================================================
-- BLOCK 2 — Decision-3 CHAIN-RESOLVED matched-tenant sub_cat fence (provisional #13).
--   Under postgres (RLS-BYPASS) so the explicit ut.users_id = acc.users_id predicate is the
--   SOLE gate (see box). BEFORE INSERT fires synchronously (not deferred). Uses ta_p3
--   (A's parent, 0 children). Rows created by (2a)/(2c) are deleted after so BLOCK 3/6 read
--   exactly ta_p1's 3 children.
-- =====================================================================
-- (2a) matched same-tenant (A parent + A Sub-Cat) INSERT PASSES (non-vacuous control).
select lives_ok(
  format($$ insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount)
              values (%s, %s, 30) $$, :ta_p3, :a_sub),
  '(2a) #13 fence non-vacuous control: A tags its OWN txn with its OWN Sub-Cat -> matched-tenant PASSES'
);
-- (2b) cross-tenant (A parent + B Sub-Cat) INSERT RAISES — the chain attack #13 fences.
select throws_ok(
  format($$ insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount)
              values (%s, %s, 30) $$, :ta_p3, :b_sub),
  'P0001',
  null,
  '(2b) #13 fence LOAD-BEARING (RLS-bypass): A tags its txn with B''s Sub-Cat -> cross-tenant chain mismatch RAISES (explicit ut.users_id=acc.users_id predicate is the sole gate)'
);
-- (2c) NULL sub_cat INSERT PASSES (WHEN-clause skips the fence — Unsorted/Suspense line).
select lives_ok(
  format($$ insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount)
              values (%s, null, 30) $$, :ta_p3),
  '(2c) #13 fence WHEN-skip: a NULL sub_cat line PASSES (uncategorized/Suspense line can land)'
);
-- (2d) fence covers UPDATE (re-categorization): seed a matched child, then re-point its
--      sub_cat_id to B's Sub-Cat -> the BEFORE UPDATE fence RAISES (mirrors 023 F2 — the
--      mutable overlay's re-categorize path must be fenced, not just INSERT).
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount)
  values (:ta_p3, :a_sub, 30) returning id as fence_child \gset
select throws_ok(
  format($$ update pfin.account_trans_split set sub_cat_id = %s where id = %s $$, :b_sub, :fence_child),
  'P0001', null,
  '(2d) #13 fence covers UPDATE: re-categorizing a split line to another tenant''s Sub-Cat RAISES (fence fires BEFORE UPDATE, not only INSERT)'
);
-- (2e) CONVERSION LEG (mirrors 023 F2b): A's OWN storage-side (asset) user_taxonomy
--   id as a split child's sub_cat_id -> REJECTED. Pre-084 this succeeded (029's own
--   DOMAIN NOTE: app-layer only); post-084 the fence's resolving read into
--   posting_prototype finds nothing (a_asset_sub lives in user_taxonomy only).
select throws_like(
  format($$ insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount)
              values (%s, %s, 30) $$, :ta_p3, :a_asset_sub),
  '%is not a posting prototype owned by the tenant of account_trans_id%',
  '(2e) CONVERSION: A references its OWN storage-side (asset) user_taxonomy id as a split child''s sub_cat_id -> REJECTED -- mirrors 023 F2b, same cross-vocabulary-reference-now-impossible property'
);
-- remove BLOCK-2 rows so the parent-chain read/view blocks see only ta_p1's 3 children.
delete from pfin.account_trans_split where account_trans_id = :ta_p3;

-- =====================================================================
-- BLOCK 3 — parent-chain RLS SELECT (write-dormant read path). Reuses ta_p1's 3 balanced
--   children. rd_access-JOIN via account_trans_id -> account_trans -> account_users.
-- =====================================================================
-- (3a) owner-reads-own: A reads its 3 own split rows for ta_p1.
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*) from pfin.account_trans_split where account_trans_id = :ta_p1)::bigint, 3::bigint,
  '(3a) owner-reads-own: A reads exactly its 3 own split rows via the parent-chain rd_access SELECT policy (not over-restrictive)'
);
select set_config('role', 'postgres', true);

-- (3b) cross-tenant read fails closed: B reads 0 of A's split rows.
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from pfin.account_trans_split where account_trans_id = :ta_p1)::bigint, 0::bigint,
  '(3b) cross-tenant read fails closed: B sees 0 of A''s split rows (parent-chain RLS isolation — B holds no account_users grant on acct-alpha)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 4 — ⟦REMOVED at the 038 un-dorm amendment (SELF-202)⟧
--   This block asserted WRITE-DORMANCY: authenticated INSERT/UPDATE/DELETE fail closed at the
--   GRANT layer ('permission denied for table account_trans_split'). 038 adds the write policies
--   + GRANT insert,update,delete to authenticated, so those assertions are now FALSE against the
--   applied stack. The un-dormed write-path coverage (owner INSERT PASS, cross-tenant write +
--   cross-account re-parent fail-closed, Σ-at-commit on the authenticated write, #13-through-
--   write) lives in 038_manual_trans_and_split_write_rls.sql. Plan reduced 17→14 (see header).
--   The p1_c1 \gset (BLOCK 1) is now unused but harmless — left in place to keep BLOCK 1 intact.
-- =====================================================================

-- =====================================================================
-- BLOCK 5 — finite CHECK (account_trans_split_amount_finite; the 014 discipline).
--   Privileged inserts so the raise is the CHECK/coercion, not a grant denial.
-- =====================================================================
-- (5a) NaN amount raises 23514 (the CHECK amount <> 'NaN').
select throws_ok(
  format($$ insert into pfin.account_trans_split (account_trans_id, amount) values (%s, 'NaN'::numeric) $$, :ta_p3),
  '23514', null,
  '(5a) finite CHECK: a NaN line amount fails closed at account_trans_split_amount_finite (23514) — a NaN would poison Σ'
);
-- (5b) +Infinity fails closed at numeric(20,4) coercion (rejects +/-Infinity before insert).
select throws_ok(
  format($$ insert into pfin.account_trans_split (account_trans_id, amount) values (%s, 'Infinity'::numeric(20,4)) $$, :ta_p3),
  null, null,
  '(5b) finite discipline: an +/-Infinity line amount fails closed at numeric(20,4) coercion (014 finite discipline — no overflow line in a split)'
);

-- =====================================================================
-- BLOCK 6 — reconciliation VIEW (security_invoker). Reuses ta_p1's 3 balanced children.
-- =====================================================================
-- (6a) A sees the balanced parent's windowed aggregates: is_balanced true, delta 0, 3 children.
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select bool_and(child_count = 3 and imbalance_delta = 0 and is_balanced and children_sum = 100)
     from pfin.account_trans_split_balance where account_trans_id = :ta_p1),
  '(6a) recon view: A sees child_count=3, children_sum=100, imbalance_delta=0, is_balanced=true across all 3 lines of the balanced parent (windowed aggregate math correct)'
);
select set_config('role', 'postgres', true);

-- (6b) security_invoker scoping: B sees 0 rows of A's parent through the view.
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from pfin.account_trans_split_balance where account_trans_id = :ta_p1)::bigint, 0::bigint,
  '(6b) recon view security_invoker: B sees 0 view rows for A''s parent (RLS composes through the view — not security_definer)'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;

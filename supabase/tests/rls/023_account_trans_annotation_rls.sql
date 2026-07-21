-- =====================================================================
-- Per-Wave battery — pfin.account_trans_annotation: the R-17 per-transaction
--   MUTABLE annotation overlay + PARENT-FK-CHAIN RLS (rd/wr_access-JOIN via
--   trans_id → account_trans.account_id → account_users — the annotation has NO own
--   users_id) + the CHAIN-RESOLVED Decision-3 CANONICAL #10 matched-tenant fence on
--   sub_cat_id + 1:1 PK + grants (ADR-027 R-17 / SELF-283 — C6 EXPOSURE-GATING per
--   ADR-023; V1-SHIP-BLOCK; JOINT-REVIEW-MANDATORY — the FINAL substrate slice + the
--   LAST label of the ADR-027 (g) 5→10 batch (#6–#10); NOT the last of the family)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/023_account_trans_annotation.sql
--   - pfin.account_trans_annotation (trans_id bigint PK -> pfin.account_trans(trans_id)
--       ON DELETE RESTRICT — the SOLE tenant anchor + the 1:1 enforcer; sub_cat_id bigint
--       NULL -> pfin.user_taxonomy(id) ON DELETE RESTRICT; note text NULL; created/
--       updated_at). NO own users_id — tenancy derives via the account FK-chain.
--   - PARENT-FK-CHAIN RLS (the 006 account_trans / 005 reconciliation_event_trans shape):
--       ata_select (rd_access-JOIN) / ata_insert (wr_access-JOIN WITH CHECK) / ata_update
--       (wr_access-JOIN USING + WITH CHECK) / ata_delete (wr_access-JOIN USING). SELECT
--       keys on rd_access; ALL WRITES key on wr_access (mod #3). Full authenticated CRUD
--       (MUTABLE overlay — contrast the 004/005 append-only ledgers).
--   - grant select, insert, update, delete on pfin.account_trans_annotation to
--       authenticated (ACL-before-RLS). anon zero-grant; service_role UNGRANTED.
--   - pfin.fn_account_trans_annotation_matched_sub_cat()  (Decision-3 CANONICAL #10; the
--       012 Pattern 1 matched-tenant fence, but CHAIN-RESOLVED — mirrors 017's chain-JOIN
--       tenant resolution; SECURITY INVOKER; set search_path=''; BEFORE INSERT OR UPDATE
--       WHEN (new.sub_cat_id IS NOT NULL); NULL-safe fail-closed NOT EXISTS -> raise
--       'cross-tenant Sub-Cat rejected%'). The referenced user_taxonomy row must share the
--       annotation's OWNING tenant, resolved via trans_id -> account_trans.account_id ->
--       account.users_id (this table has NO local new.users_id — contrast 012/022).
--   - trigger account_trans_annotation_set_updated_at (reuses the 001 DEFINER allowlist #1).
-- Prereqs exercised (already on main / applied by Backend on the reset stack): 001 (pfin
--   schema + fn_refresh_updated_at), 003 (pfin.account + the DEFINER creator-grant trigger
--   the RLS chain JOINs — seeds rd=t/wr=t keyed on new.users_id), 004 (pfin.account_trans
--   immutable ledger — the trans_id FK target + the chain's middle hop), 006 (account_trans
--   rd/wr_access-JOIN RLS + GRANT — the account_trans read the fence + the annotation RLS
--   compose with), 009 (pfin.user_taxonomy — the sub_cat_id FK target + its auth.uid()-
--   scoped SELECT policy the fence composes with under authenticated).
-- Reuses the SELF-187/189/190/196/006/017/022 idiom: \ir verbs, ALL-LOWERCASE \gset
--   literals (005 case-fold lesson), MESSAGE-precise throws_like (004 all-42501 false-green
--   lesson), %L for UUIDs / %s for bigints in format() (022 lesson), role restored to
--   postgres between blocks (PR #121 _rls-USAGE root-cause).
--
-- ┌─ ⚠️ THE (a)-CONDITIONAL FENCE BLOCK — SEC RULES SHAPE (a) vs (b) AT JOINT-REVIEW ─────┐
-- │ 023's §6A C-NOTE leaves ONE open sub-decision: the sub_cat_id matched-tenant fence     │
-- │ SHAPE. Architect authored + recommends (a) CHAIN-RESOLVED trigger; (b) is RLS-         │
-- │ composition belt-and-suspenders (drop the explicit fence, rely on the account-chain    │
-- │ RLS + user_taxonomy_select auth.uid()-scoping). This battery is built against (a).     │
-- │   • The RLS-ISOLATION tests (BLOCKs 1/2/4 + grants/PK/RESTRICT) STAND EITHER WAY —      │
-- │     they exercise the parent-FK-chain RLS + the 1:1 PK + the ACL, which (b) keeps.     │
-- │   • LEG F (the 4 fence-specific assertions F1..F4) is CONDITIONAL ON (a). Under (b)     │
-- │     the explicit fence + its trigger are DROPPED, and a crafted INSERT/UPDATE with a    │
-- │     KNOWN cross-tenant sub_cat_id id would SUCCEED at the DB layer (the FK is existence-│
-- │     only; RLS invisibility is a SELECT-scoping property, it does not block an INSERT    │
-- │     referencing a known id) — so F1..F4 would FAIL under (b). IF SEC RULES (b): DELETE  │
-- │     LEG F in full and change plan(18) -> plan(14). The RLS battery is unaffected.       │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ WHY LEG F's CROSS-TENANT ASSERTIONS HAVE TEETH (the 017 (a3)-vs-(a4) lesson applied   │
-- │  to the CHAIN-RESOLVED fence) ────────────────────────────────────────────────────────┐│
-- │ The fence is SECURITY INVOKER. Under authenticated A, the fence's user_taxonomy read    ││
-- │ composes with 009's auth.uid()-scoped SELECT (B's Sub-Cat is RLS-INVISIBLE to A) AND    ││
-- │ the account_trans/account chain reads are 006/003 RLS-scoped — so (F1)/(F2) could PASS  ││
-- │ even if the explicit `ut.users_id = acc.users_id` predicate were removed and RLS        ││
-- │ carried the whole load. That is belt-and-suspenders: NECESSARY but NOT sufficient to    ││
-- │ prove the TRIGGER. (F3) isolates the trigger: under service_role (RLS BYPASSED — B's    ││
-- │ Sub-Cat AND A's txn/account ARE visible to the fence's subquery), the SAME cross-tenant ││
-- │ INSERT STILL RAISES, so the explicit chain-resolved predicate — NOT RLS — is the gate.  ││
-- │ (F4) is the non-vacuous control: a matched (same-tenant) Sub-Cat under service_role     ││
-- │ COMMITS. NOTE — 023 grants service_role NOTHING (POSTURE: R-18 lazy, no service_role    ││
-- │ annotation writer in V1). BLOCK F's service_role grants are a TEST-ONLY trigger-        ││
-- │ isolation device, held OPEN in-test (rolled back with the txn) purely so RLS-bypass     ││
-- │ exposes the referenced rows and the explicit predicate is the sole remaining gate. It   ││
-- │ asserts the fence has teeth, NOT a prod path (mirrors 022's BLOCK 6 honest framing).    ││
-- │ Unlike 017 (whose chain-resolved fence is load-bearing under a REAL provider-sync       ││
-- │ service_role writer), 023's is future-proofing for a HYPOTHETICAL writer under §6A      ││
-- │ Option A — the C-NOTE (a) rationale. The teeth still bind: it is the family's discipline││
-- │ that EVERY matched-tenant fence is authoritative regardless of RLS (022 #9 precedent).  ││
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ WHY EACH REJECTION MATCHES A DISTINCT SIGNAL (no fence/policy/constraint passes for    │
-- │  another — the 004 all-42501 discipline) ─────────────────────────────────────────────┐
-- │  • cross-tenant sub_cat (fence #10)          -> raise 'cross-tenant Sub-Cat rejected%'   │
-- │  • cross-account write, no wr_access (RLS)   -> 'new row violates row-level security     │
-- │                                                  policy%for table "account_trans_        │
-- │                                                  annotation"'                            │
-- │  • second annotation on same trans_id (PK)   -> unique_violation 23505                   │
-- │  • ON DELETE RESTRICT (sub_cat_id FK)        -> foreign_key_violation 23503              │
-- │  • anon (no schema USAGE)                    -> insufficient_privilege 42501 (ACL,       │
-- │                                                  before RLS)                             │
-- │ The RLS INSERT isolation (2c) uses a NULL sub_cat_id to SKIP the fence WHEN-clause, so   │
-- │ the RLS WITH CHECK — not the fence — is proven the gate (else B inserting on A's txn     │
-- │ would raise the FENCE first: under B's RLS the chain JOIN cannot even SEE A's txn ->     │
-- │ NOT EXISTS -> fence raise, masking the RLS test). The 006 write-key-isolation lesson.    │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (1a) -> #10 matched-tenant PASS + wr_access INSERT POSITIVE: RED if the fence over-
--          blocked own-tenant Sub-Cats, or if the wr_access-JOIN WITH CHECK rejected an
--          owner's own-account annotation (the feature would not work).
--   (1b) -> NULL sub_cat_id (Unsorted-pending, SELF-200) PASS: RED if the WHEN-clause did
--          not skip NULL (a txn could never land uncategorized — breaks the lazy model).
--   (1c) -> matched-tenant re-categorization UPDATE PASS: RED if the fence did not cover
--          UPDATE for the SAME-tenant case (a legit re-categorization to another OWN Sub-Cat
--          must succeed — the overlay's raison d'etre is the mutable re-categorize path).
--   (1d) -> owner-reads-own: RED if the rd_access-JOIN SELECT policy were over-restrictive
--          (owner cannot read its own annotations).
--   (2a) -> NON-VACUOUS control: RED if the fence/RLS blanket-blocked authenticated B
--          (proves the (2b)/(2c)/LEG-F rejections are cross-tenant-MISMATCH-driven, not a
--          blanket B block).
--   (2b) -> cross-tenant read fails closed: RED if the ata_select rd_access-JOIN leaked ->
--          B sees A's annotations.
--   (2c) -> cross-account INSERT fails closed: RED if ata_insert's wr_access-JOIN WITH CHECK
--          were removed / keyed on rd_access -> B annotates a txn on an account it lacks
--          wr_access on. (NULL sub_cat isolates the RLS gate from the fence — see box.)
--   (4a) -> cross-account UPDATE blocked: RED if the ata_update USING policy leaked -> B
--          could re-point/modify A's annotation.
--   (4b) -> cross-account DELETE blocked: RED if the ata_delete USING policy leaked -> B
--          could clear A's annotation.
--   (6a) -> anon zero-grant: RED if anon were granted any reach -> an internet-facing
--          overlay becoming anon-readable is an exposure regression (C6).
--   (6b) -> authenticated DELETE POSITIVE (full-CRUD contract): RED if the DELETE grant/
--          policy were missing -> owner cannot clear its own annotation.
--   (6c) -> the owner-DELETE really applied (the deleted annotation is gone under RLS).
--   (7)  -> 1:1 PK: RED if the trans_id PK were relaxed -> a SECOND annotation on the same
--          transaction would double-insert (the overlay is 1:1 by construction).
--   (8)  -> sub_cat_id ON DELETE RESTRICT: RED if RESTRICT were relaxed -> a referenced
--          user_taxonomy row could be deleted out from under an annotation (orphan).
--  LEG F ((a)-CONDITIONAL — drop if Sec rules (b)):
--   (F1) -> #10 cross-tenant INSERT under authenticated: RED if the fence (or its explicit
--          predicate) were removed -> A tags its own txn with B's Sub-Cat and it COMMITS
--          (the exact chain-attack Decision-3 #10 fences). Belt-and-suspenders leg.
--   (F2) -> #10 cross-tenant UPDATE under authenticated: RED if the fence did not cover
--          UPDATE -> a re-categorization could pivot to another tenant's Sub-Cat.
--   (F3) -> LOAD-BEARING: RED if the fence relied on RLS instead of its explicit chain-
--          resolved `ut.users_id = acc.users_id` predicate -> under RLS-bypass the cross-
--          tenant write would COMMIT. The SOLE assertion that isolates the TRIGGER from RLS.
--   (F4) -> NON-VACUOUS service_role control: a matched (same-tenant) Sub-Cat under
--          service_role COMMITS -> the fence is owner-mismatch-driven, not a blanket block.
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22 + RT-26 + RT-27; 023 introduces ZERO
--   catalogued §10 instances — authenticated-tier RLS/FK/trigger DDL + one INVOKER fence;
--   adds NO service_role grant, so no RT-26 code-layer surface + no admission channel).
--   Decision-3 family: this migration REALIZES CANONICAL instance #10
--   (account_trans_annotation.sub_cat_id -> user_taxonomy, matched-tenant, CHAIN-RESOLVED)
--   per the ADR-027 atomic amendment (g) — the LAST label of the (g) 5→10 batch (#6–#10),
--   NOT the last of the family. The canonical family = 11 labeled instances (NOT 10): #11 =
--   holdings_checkpoint.security_id was realized EARLY at 019 (ADR-027 (p), distinct-
--   provenance, outside the (g) batch). After 023, DDL-realized = 9 of 11 (#1,#2,#5,#6,#7,
--   #8,#9,#10,#11); UNREALIZED = #3, #4 (monthly_report tables, V1.3+). 023 moves realized
--   +1 (#10). This is explicitly NOT "fully realized" and NOT a convergence-to-completion
--   point. No new ADR. trans_id is the SOLE tenant anchor (NOT D3 — same class as
--   account_trans.account_id @ 004). This battery is the pgTAP proof of #10 (the mechanism),
--   confirming the chain-resolved fence catches a REAL cross-tenant violation — incl. under
--   RLS-bypass (LEG F).
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b();
--   NO PII / NO real account numbers / NO prod data. A owns acct-alpha (+ 5 txns); B owns
--   acct-beta (+ 1 txn) — both via the 003 creator-grant trigger (keyed on new.users_id,
--   seeds rd=t/wr=t). BOTH tenants own their OWN cashflow user_taxonomy Sub-Cats so every
--   matched-tenant PASS and every cross-tenant FAIL has a real referent (non-vacuous).
--   account.users_id is set EXPLICITLY (auth.uid() is NULL under postgres). All in a
--   rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so
--   NO `_rls.*` call runs under authenticated. Tenant UUIDs + row ids are resolved to psql
--   LITERALS via \gset at role=postgres; every _rls.set_tenant is called at role=postgres
--   and each block restores role=postgres before the next. \gset var names are ALL-LOWERCASE.
--
-- ⟦WIRE-VALIDATE⟧ authored against 023's firmed contract; the authoritative run is against
--   the 001->023 reset stack (Backend owns the local stack + the clean-apply — this file
--   does NOT reset). Roles `authenticated` / `service_role` / `anon` name-checked in the
--   blocks; LEG F's service_role SELECT/INSERT grants are held OPEN in-test (rolled back)
--   so the TRIGGER — not a missing ACL — is isolated as the sole gate (a missing grant
--   would 42501 'permission denied', a false-RED). CI (pg_prove directory-mode, db-tests.yml,
--   after Backend's clean-apply) is the green gate. plan(18)  [plan(14) if Sec rules (b) and
--   LEG F is dropped].
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(18);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed seed path).
--  - Two tenants in auth.users.
--  - A owns acct-alpha, B owns acct-beta. The 003 AFTER-INSERT DEFINER creator-grant
--    trigger fires on each account INSERT -> account_users(acct, owner, rd=t, wr=t),
--    exactly the rd/wr-JOIN state the annotation RLS chain keys on (mod #2). users_id set
--    EXPLICITLY (auth.uid() is NULL under postgres).
--  - account_trans: FIVE committed cash rows on acct-alpha (ta1..ta5 — quantity defaults 0
--    -> passes the 017 qty_requires_security CHECK) + ONE on acct-beta (tb1). These are the
--    annotation targets (the annotation PK = trans_id, so each txn holds AT MOST one).
--  - user_taxonomy: A owns TWO cashflow Sub-Cats (a_sub + a_sub2, the re-categorization
--    target for 1c); B owns ONE (b_sub — the cross-tenant target the #10 fence must reject).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-alpha', 'depository', 'household', 'taxable')
  returning account_id as accta \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'acct-beta', 'depository', 'household', 'taxable')
  returning account_id as acctb \gset

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-01-11', 11, 'vA1', 'alpha txn 1') returning trans_id as ta1 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-01-12', 12, 'vA2', 'alpha txn 2') returning trans_id as ta2 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-01-13', 13, 'vA3', 'alpha txn 3') returning trans_id as ta3 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-01-14', 14, 'vA4', 'alpha txn 4') returning trans_id as ta4 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-01-15', 15, 'vA5', 'alpha txn 5') returning trans_id as ta5 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:acctb, '2026-01-16', 16, 'vB1', 'beta txn 1') returning trans_id as tb1 \gset

insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat)
  values (:'ta', 'cashflow', 'Housing', 'Rent') returning id as a_sub \gset
insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat)
  values (:'ta', 'cashflow', 'Food', 'Groceries') returning id as a_sub2 \gset
insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat)
  values (:'tb', 'cashflow', 'Housing', 'Rent') returning id as b_sub \gset

-- =====================================================================
-- BLOCK 1 (authenticated A) — matched-tenant PASSes: annotate own txn (matched Sub-Cat),
--   NULL Sub-Cat (Unsorted-pending), a re-categorization UPDATE, and owner-reads-own.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (1a) #10 matched-tenant PASS + wr_access INSERT POSITIVE: A annotates its OWN txn with its
--      OWN cashflow Sub-Cat -> the chain-resolved fence resolves ta1 -> acct-alpha -> A, and
--      a_sub.users_id = A -> EXISTS -> PASS; the wr_access-JOIN WITH CHECK is satisfied (A
--      holds wr_access on acct-alpha). Non-vacuous positive.
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, %s) $$, :ta1, :a_sub),
  '(1a) matched-tenant PASS + wr_access INSERT: authenticated A annotates its OWN transaction with its OWN Sub-Cat -> the chain-resolved #10 fence ACCEPTS (ta1 -> acct-alpha -> A == a_sub.users_id) and the wr_access-JOIN WITH CHECK admits the write'
);

-- (1b) NULL sub_cat_id PASS (Unsorted-pending, SELF-200): the fence WHEN-clause skips NULL,
--      so a txn lands uncategorized (the user assigns later — the lazy model).
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, null) $$, :ta2),
  '(1b) NULL sub_cat_id PASS: A annotates a txn with a NULL Sub-Cat (Unsorted-pending) -> the fence WHEN (new.sub_cat_id IS NOT NULL) SKIPS, the note-only overlay lands (a txn can be created uncategorized — the R-18 lazy model)'
);

-- fixture: A annotates ta3 with a_sub (captured for the re-categorization UPDATE (1c) + the
-- RLS UPDATE/DELETE isolation probes (4a)/(4b)).
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:ta3, :a_sub);

-- (1c) matched-tenant re-categorization UPDATE PASS: A moves ta3's annotation to ANOTHER of
--      its OWN Sub-Cats -> the BEFORE UPDATE fence ACCEPTS (covers UPDATE, not just INSERT;
--      the overlay's raison d'etre is the mutable re-categorize path).
select lives_ok(
  format($$ update pfin.account_trans_annotation set sub_cat_id = %s where trans_id = %s $$, :a_sub2, :ta3),
  '(1c) matched-tenant re-categorization UPDATE: A reassigns its annotation to another of ITS OWN Sub-Cats -> the fence ACCEPTS (BEFORE INSERT OR UPDATE covers the mutable re-categorization path — the overlay keeps the immutable ledger clean)'
);

-- (1d) owner-reads-own: A sees exactly its 3 annotations (ta1, ta2, ta3) via the rd_access-
--      JOIN SELECT policy (guards an over-restrictive policy). No other annotations exist yet.
select is(
  (select count(*) from pfin.account_trans_annotation)::bigint, 3::bigint,
  '(1d) owner-reads-own: A reads exactly its 3 annotations (ta1/ta2/ta3) via the rd_access-JOIN parent-chain SELECT policy — not over-restrictive'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 2 (authenticated B) — non-vacuous control + cross-tenant read fails closed +
--   cross-account INSERT fails closed (RLS wr_access WITH CHECK, isolated via NULL sub_cat).
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);

-- (2a) NON-VACUOUS control: B annotates its OWN txn (tb1) with its OWN Sub-Cat -> ACCEPTED
--      (fence resolves tb1 -> acct-beta -> B == b_sub.users_id; B holds wr_access on
--      acct-beta). Proves the cross-tenant rejections below are MISMATCH-driven, not a
--      blanket B block.
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, %s) $$, :tb1, :b_sub),
  '(2a) control: B annotates its OWN txn with its OWN Sub-Cat -> ACCEPTED (proves the cross-tenant rejections below are mismatch-driven — the fence + RLS do not blanket-block authenticated B)'
);

-- (2b) cross-tenant read fails closed: B holds no grant on acct-alpha, so the rd_access-JOIN
--      read path yields ZERO of A's annotations (ta1/ta2/ta3).
select is(
  (select count(*) from pfin.account_trans_annotation where trans_id in (:ta1, :ta2, :ta3))::bigint, 0::bigint,
  '(2b) cross-tenant read fails closed: B sees 0 of A''s annotations (ta1/ta2/ta3) via the parent-chain rd_access-JOIN SELECT policy — the annotation''s tenancy IS the account chain'
);

-- (2c) cross-account INSERT fails closed: B annotates A's txn (ta4) with a NULL Sub-Cat. The
--      NULL SKIPS the fence WHEN-clause, isolating the RLS gate: B holds no wr_access on
--      acct-alpha -> the wr_access-JOIN WITH CHECK REJECTS (message-precise RLS violation,
--      not the fence — see the fail-layer box for why NULL sub_cat is load-bearing here).
select throws_like(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, null) $$, :ta4),
  'new row violates row-level security policy%for table "account_trans_annotation"',
  '(2c) cross-account INSERT fails closed: B annotates A''s txn (NULL Sub-Cat skips the fence) -> REJECTED by the ata_insert wr_access-JOIN WITH CHECK (B holds no wr_access on acct-alpha; mod #3 — writes key on wr_access)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 4 (authenticated B -> postgres asserts) — RLS UPDATE/DELETE isolation (USING).
--   B's write statements target A's annotation (ta3); the ata_update/ata_delete USING
--   wr_access-JOIN filters it out -> 0 rows affected (silently — 0 matching rows, so the
--   BEFORE fence never fires). The assertions prove A's annotation survives UNCHANGED.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);
update pfin.account_trans_annotation set sub_cat_id = :b_sub where trans_id = :ta3;  -- 0 rows (RLS hides A's row; fence never fires)
delete from pfin.account_trans_annotation where trans_id = :ta3;                     -- 0 rows (RLS hides A's row)
select set_config('role', 'postgres', true);

-- (4a) cross-account UPDATE blocked: A's annotation still carries a_sub2 (from 1c) — B's
--      UPDATE touched 0 rows (ata_update USING wr_access-JOIN owner-scoping).
select is(
  (select sub_cat_id from pfin.account_trans_annotation where trans_id = :ta3),
  :a_sub2::bigint,
  '(4a) cross-account UPDATE blocked: after B''s UPDATE targeting A''s annotation, the row is UNCHANGED (still a_sub2) — the ata_update USING wr_access-JOIN scoped B to its own rows (0 rows affected)'
);

-- (4b) cross-account DELETE blocked: A's annotation still present — B's DELETE touched 0 rows.
select is(
  (select count(*) from pfin.account_trans_annotation where trans_id = :ta3)::bigint,
  1::bigint,
  '(4b) cross-account DELETE blocked: after B''s DELETE targeting A''s annotation, the row still EXISTS — the ata_delete USING wr_access-JOIN scoped B to its own rows (0 rows affected)'
);

-- =====================================================================
-- BLOCK 6 (grants) — anon zero-grant + authenticated DELETE (full-CRUD contract).
-- =====================================================================
-- (6a) anon has NO USAGE on schema pfin -> even SELECT is denied at the ACL layer (42501),
--      before RLS is consulted (C6 exposure-gating — the overlay is not anon-reachable).
select set_config('role', 'anon', true);
select throws_ok(
  'select count(*) from pfin.account_trans_annotation',
  '42501', null,
  '(6a) anon zero-grant: anon holds no USAGE on schema pfin -> SELECT is denied at the ACL layer (insufficient_privilege 42501), before RLS — the internet-facing overlay is not anon-reachable (C6)'
);
select set_config('role', 'postgres', true);

-- (6b) authenticated DELETE POSITIVE (completes the full-CRUD contract): A clears its OWN
--      annotation on ta2 (RLS ata_delete USING scopes to A's wr_access accounts).
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  format($$ delete from pfin.account_trans_annotation where trans_id = %s $$, :ta2),
  '(6b) authenticated DELETE: A clears its OWN annotation (ta2) -> the ata_delete wr_access-JOIN USING admits the owner delete (MUTABLE overlay full-CRUD contract — contrast the append-only ledgers)'
);
select set_config('role', 'postgres', true);

-- (6c) the owner-DELETE really applied: ta2's annotation is gone (privileged re-read).
select is(
  (select count(*) from pfin.account_trans_annotation where trans_id = :ta2)::bigint,
  0::bigint,
  '(6c) after A''s owner-DELETE, ta2''s annotation is GONE (0) — the delete really applied (not a silent 0-row no-op)'
);

-- =====================================================================
-- BLOCK 7 (authenticated A) — 1:1 PK: one annotation per transaction (trans_id PK).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (7) A annotates ta1 a SECOND time (ta1 is already annotated from 1a) with its OWN Sub-Cat
--     (a_sub2) so the fence PASSES first -> the trans_id PRIMARY KEY then RAISES 23505. The
--     fence is not the gate here (a_sub2 is A's own); the 1:1 PK is.
select throws_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, %s) $$, :ta1, :a_sub2),
  '23505', null,
  '(7) 1:1 PK: a SECOND annotation on an already-annotated transaction (ta1) is REJECTED (unique_violation 23505) — the trans_id PRIMARY KEY enforces the 1:1 overlay; the fence passes first (own Sub-Cat), so the PK is the sole gate'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 8 (postgres) — sub_cat_id ON DELETE RESTRICT (fail-loud referential integrity).
--   A's ta1 annotation (from 1a) still references a_sub.
-- =====================================================================
-- (8) deleting a user_taxonomy row still referenced by an annotation is blocked (23503) —
--     no orphaned Sub-Cat reference. (trans_id ON DELETE RESTRICT is moot — account_trans is
--     immutable, no DELETE path exists — so it is not exercised here.)
select throws_ok(
  format($$ delete from pfin.user_taxonomy where id = %s $$, :a_sub),
  '23503', null,
  '(8) sub_cat_id ON DELETE RESTRICT: deleting a user_taxonomy row still referenced by an annotation is RESTRICTED (foreign_key_violation 23503) — no orphaned Sub-Cat reference'
);

-- =====================================================================
-- ⚠️ LEG F — (a)-CONDITIONAL FENCE BLOCK (the CHAIN-RESOLVED #10 matched-tenant fence).
--   DROP THIS ENTIRE LEG (F1..F4) AND CHANGE plan(18) -> plan(14) IF SEC RULES SHAPE (b)
--   AT JOINT-REVIEW (the explicit fence + its trigger are removed under (b); these
--   assertions test the explicit fence and would FAIL — see the (a)-conditional box).
-- =====================================================================
-- F1/F2 — the fence under AUTHENTICATED A (belt-and-suspenders: B's Sub-Cat is also RLS-
--   invisible to A, so the subquery is empty either way — NECESSARY but not sufficient).
select _rls.set_tenant(:'ta'::uuid);

-- (F1) #10 cross-tenant INSERT: A annotates its OWN txn (ta5) with B's Sub-Cat -> the fence
--      resolves ta5 -> acct-alpha -> A, requires b_sub.users_id (B) == A -> NOT EXISTS ->
--      RAISE. The chain-attack Decision-3 #10 fences (a real violation, not a silent pass).
select throws_like(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, %s) $$, :ta5, :b_sub),
  'cross-tenant Sub-Cat rejected%',
  '(F1) #10 cross-tenant INSERT under authenticated: A annotates its OWN txn with B''s Sub-Cat -> fn_account_trans_annotation_matched_sub_cat RAISES (chain-resolved: ta5 -> acct-alpha -> A != b_sub.users_id=B; NOT EXISTS -> raise; belt-and-suspenders with 009 user_taxonomy RLS)'
);

-- (F2) #10 cross-tenant UPDATE: A re-points ta1's annotation (currently a_sub) to B's
--      Sub-Cat -> the BEFORE UPDATE fence RAISES. Confirms #10 covers UPDATE/reassignment.
select throws_like(
  format($$ update pfin.account_trans_annotation set sub_cat_id = %s where trans_id = %s $$, :b_sub, :ta1),
  'cross-tenant Sub-Cat rejected%',
  '(F2) #10 cross-tenant UPDATE under authenticated: A re-categorizes its OWN annotation to B''s Sub-Cat -> the fence RAISES (BEFORE INSERT OR UPDATE covers the mutable re-categorization path — a re-categorization cannot pivot to another tenant''s Sub-Cat)'
);
select set_config('role', 'postgres', true);

-- F3/F4 — THE LOAD-BEARING LEG (service_role, RLS BYPASSED). Hold the ACLs the fence's
--   subquery + the INSERT need OPEN to service_role (TEST-ONLY isolation, rolled back — 023
--   itself grants service_role NOTHING; see the teeth box). Under RLS-bypass B's Sub-Cat AND
--   A's txn/account ARE visible to the subquery; only the explicit chain-resolved predicate
--   rejects. auth.uid() is NULL under service_role, so there is no ambient tenant — the fence
--   resolves the tenant purely via the trans_id -> account chain (exactly the (a) property).
grant usage on schema pfin to service_role;
grant select on pfin.user_taxonomy to service_role;
grant select on pfin.account_trans to service_role;
grant select on pfin.account to service_role;
grant insert on pfin.account_trans_annotation to service_role;

select set_config('role', 'service_role', true);

-- (F3) LOAD-BEARING: service_role annotates A's txn (ta4) with B's Sub-Cat. RLS is BYPASSED
--      (B's Sub-Cat IS visible), yet the explicit `ut.users_id = acc.users_id` predicate
--      (B != A, resolved via the ta4 -> acct-alpha chain) STILL RAISES. Proves the chain-
--      resolved TRIGGER predicate — NOT RLS — is the sole gate (the C-NOTE (a) property:
--      authoritative under a hypothetical service_role annotation writer, §6A Option A).
select throws_like(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, %s) $$, :ta4, :b_sub),
  'cross-tenant Sub-Cat rejected%',
  '(F3) LOAD-BEARING fence RAISE under service_role: RLS BYPASSED (B''s Sub-Cat IS visible), yet annotating A''s txn with B''s Sub-Cat STILL RAISES — the explicit chain-resolved ut.users_id=acc.users_id predicate (NOT RLS) is the sole gate (authoritative regardless of writer)'
);

-- (F4) NON-VACUOUS service_role control: service_role annotates A's txn (ta5) with A's OWN
--      Sub-Cat -> matched (a_sub.users_id = A resolved via ta5 -> acct-alpha -> A) -> COMMITS.
--      The fence is owner-mismatch-driven, not a blanket service_role block. (ta5 is clean —
--      F1's INSERT was rejected + rolled back to its savepoint.)
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, %s) $$, :ta5, :a_sub),
  '(F4) control: a matched (A''s txn + A''s Sub-Cat) annotation under service_role COMMITS -> the fence does not blanket-block; it is owner-mismatch-driven (non-vacuous service_role control; chain resolves ta5 -> acct-alpha -> A == a_sub.users_id)'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;

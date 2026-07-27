-- =====================================================================
-- Per-Wave battery — 039 stock-split entry (SELF-203 / §2.4.3 event entry, re-scoped to
--   stock-split-only per ADR-033 Decision 2). Two surfaces:
--     (1) CHECK account_trans_corp_action_shape on pfin.account_trans — a corp_action row is
--         BOOK-NEUTRAL (coalesce(amount,0)=0 AND coalesce(cost_basis,0)=0); quantity
--         UNCONSTRAINED (it carries the split delta). Role-AGNOSTIC table CHECK.
--     (2) pfin.fn_create_stock_split(p_account_id, p_security_id, p_ratio_num, p_ratio_den,
--         p_ex_date) RETURNS bigint — SECURITY INVOKER write-composition RPC (Lock 11; mirrors
--         fn_create_manual_trans/_account). Resolves the caller's position as-of ex-date via
--         fn_holdings_as_of (019), computes delta = position × (ratio−1), INSERTs ONE book-
--         neutral corp_action account_trans row + its 023 annotation.
--   V1-SHIP-BLOCK; JOINT-REVIEW-MANDATORY (money-flow / GL fact + multi-tenant isolation + a new
--   SECURITY INVOKER write RPC). Paired with the migration in the SAME PR (verify-paired-artifacts).
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/039_stock_split_entry.sql
--
-- ┌─ SEC JOINT-REVIEW CATCH-CRITERIA → ASSERTION MAP (the AMBER→GREEN gate) ────────────────────┐
-- │ 1. Owner PASS (row + annotation) .......................... B1, B2                            │
-- │ 2. Cross-tenant ACCOUNT fail-closed + NO row landed ....... B5 (raise) + B5b (orphan count 0) │
-- │ 3. Cross-tenant HOLDINGS fail-closed (caller-scoped read) . Bscope (B sees 0 of A's position) │
-- │                                                            + B7 (RPC raises on empty position)│
-- │ 4. CHECK role-agnostic under authenticated AND service_role A2/A3 (postgres) + A5 (auth) +    │
-- │                                                            A6 (service_role) [+ A1/A4 controls]│
-- │ 5. Source-of-truth guard (linked account → raise) ........ B6                                 │
-- │ 6. Delta math — forward / reverse / no-op / empty / bad ... B3 (2:1 +qty) · Brev (1:2 −qty/2, │
-- │                                                            pos>0) · B8 (1:1 raise) · B7 (empty │
-- │                                                            raise) · B9 (≤0 raise) · B10 (NULL) │
-- │ 7. #7 security fence (cross-tenant security_id) .......... Bfence (distinct from the account  │
-- │                                                            cross-tenant test)                 │
-- │ + book-neutrality GL proof (Sec content GREEN) ........... B4 (0 GL rows) + B4b (non-vacuous) │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- Prereqs exercised on the 001→039 reset stack (Backend owns the clean-apply): 001 (pfin,
--   fn_refresh_updated_at, auth.uid()), 003 (account + fn_grant_creator_access DEFINER creator-
--   grant trigger → account_users rd=t/wr=t; the linked_source guard read target + the account
--   SELECT RLS users_id=auth.uid()), 004 (account_trans immutable ledger — the INSERT target +
--   the CHECK host), 006 (account_trans rd/wr_access RLS + grant — the chain the RPC composes
--   under), 015 (account.linked_source_id + linked_source + fn_account_matched_linked_source —
--   the source-of-truth guard read), 016/017 (pfin.asset + security_id/quantity/cost_basis
--   numeric(28,8) + the #7 global-OR-owned security fence — Bfence + the corp_action INSERT
--   EXERCISE it), 019 (fn_holdings_as_of — the caller-scoped roll-forward position read), 023
--   (account_trans_annotation — the overlay INSERT + #10 sub_cat fence, WHEN-skipped on NULL),
--   024 (user_settings.mfa_policy — A/B 'none' → the account_trans_insert aal2 backstop is a
--   no-op), 030 (the corp_action vocab CHECK value + metadata jsonb column + the Trade
--   biconditional WHEN-skip on NULL-sub_cat), 034 (basis_adjust reason trigger — fires WHEN
--   metadata IS NOT NULL but PASSES: split metadata carries NO `reason` key → R1/R2/R3 skip; the
--   034 (B9) one-directional lesson), 035/037 (fn_gl_entries — the book-neutrality target).
--
-- ┌─ ADDS COVERAGE, REPAIRS NOTHING (the new CHECK vs the existing corp_action test inserts) ──┐
-- │ Existing corp_action inserts are ALL book-neutral → they still PASS the new CHECK (read-    │
-- │ confirmed): 030 (1b) amount=0/cost_basis NULL → PASS; 034 t_ca amount=0/cost_basis NULL →   │
-- │ PASS; 035/037 insert NO corp_action row. 039 adds the first non-book-neutral REJECT coverage.│
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ ROLE MODEL (037/034/038 discipline) ──────────────────────────────────────────────────────┐
-- │ Fixture PRIVILEGED (postgres; users_id explicit — auth.uid() NULL under postgres; the       │
-- │ creator-grant trigger, #7 fence, matched-linked_source fence fire role-agnostically + PASS   │
-- │ on the seed). CRITERION 4 exercises the CHECK across THREE roles to prove it is a table CHECK │
-- │ (not RLS-dependent): postgres (A2/A3 baseline), authenticated A (A5 — CHECK fires after RLS   │
-- │ admits the owner write), service_role (A6 — RLS BYPASSED but the CHECK STILL fires). The two  │
-- │ ADMIT rows (A1/A4) are dated 2027, AFTER every holdings as-of read, so they cannot pollute    │
-- │ the roll-forward. The RPC + its reads (PART B) run UNDER authenticated A/B — the REAL INVOKER │
-- │ path. GL/holdings read-backs run under authenticated (the 037 direct-is()-under-authenticated │
-- │ pattern). Roles restored to postgres between blocks (PR #121 _rls-USAGE discipline).          │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation; none is a vacuous green):
--   PART A — CHECK account_trans_corp_action_shape (role-agnostic; direct INSERT):
--   (A1) ADMIT (postgres): book-neutral corp_action (amount=0, cost_basis NULL, quantity=50
--        delta, security set) PASSES — the invariant admits the split fact AND leaves quantity
--        UNCONSTRAINED (it carries the share delta).
--   (A2) amount<>0 corp_action RAISES 23514 (postgres) — the coalesce(amount,0)=0 clause.
--   (A3) cost_basis<>0 corp_action RAISES 23514 (postgres) — the NULL-safe coalesce(cost_basis,0)
--        =0 clause (a naive `cost_basis=0` reads NULL as pass-by-NULL, a silent gap).
--   (A4) a NON-corp_action (standard) row that WOULD violate (amount<>0 AND cost_basis<>0) PASSES
--        — the transaction_type<>'corp_action' disjunct is load-bearing.
--   (A5) [CRITERION 4] amount<>0 corp_action under AUTHENTICATED A on A's OWN account RAISES 23514
--        — RLS admits the owner write, then the table CHECK fires → the CHECK gates the real
--        authenticated write tier, not just privileged inserts.
--   (A6) [CRITERION 4] amount<>0 corp_action under SERVICE_ROLE RAISES 23514 — service_role
--        BYPASSES RLS but NOT the CHECK → proves it is a role-agnostic TABLE CHECK, not an RLS
--        artifact (the ingest tier is fenced too).
--   PART B — fn_create_stock_split (authenticated A/B) + the #7 fence:
--   (B1) [CRITERION 1] owner call creates EXACTLY ONE book-neutral corp_action row (amount=0,
--        cost_basis NULL, quantity=delta=100, security set) for the returned trans_id.
--   (B2) [CRITERION 1] ...its 023 annotation landed ATOMICALLY (metadata action='split', 2:1).
--   (B3) [CRITERION 6 forward] restates own holdings: after 2:1, fn_holdings_as_of(ex_date) for
--        (accta, g_asset) = 200 = position 100 × 2 (delta = position × (ratio−1) = +100).
--   (B4) book-neutrality (load-bearing GL): fn_gl_entries emits ZERO rows for the split trans_id
--        (P1/P2 skip, P9 nets 0 & drops) — a book-neutral corp_action moves NO book value.
--   (B4b) non-vacuous GL anchor: fn_gl_entries emits >0 rows for the position-establishing BUY →
--        the GL engine is LIVE, so (B4)'s 0 is a REAL book-neutrality, not an empty-set 0.
--   (Brev) [CRITERION 6 reverse] reverse 1:2 split: fn_holdings_as_of = 100 = 200 × 1/2 (delta =
--        −100; the position SHRINKS but stays > 0) — RED if reverse-split delta were mis-signed.
--   (B6) [CRITERION 5] source-of-truth guard: A on its OWN provider-linked account (linked_source
--        _id NOT NULL) RAISES 'provider-linked' (linked splits arrive via SELF-204 reconciliation).
--   (B7) [CRITERION 6 empty / 3] empty position: A for a security it holds NO position in RAISES
--        'nothing to split' (the RPC's caller-scoped position read fails closed on 0/none).
--   (B8) [CRITERION 6 no-op] 1:1 ratio yields delta=0 → RAISES 'no-op'.
--   (B9) [CRITERION 6 bad] ratio num=0 (≤0) → RAISES 'positive rational'.
--   (B10) [CRITERION 6 bad] ratio den NULL → RAISES 'positive rational' (the NULL branch).
--   (Bfence) [CRITERION 7] #7 security fence: a DIRECT INSERT (authenticated A) of a corp_action
--        row on A's account carrying a security_id owned by TENANT B (not global, not A's) RAISES
--        'cross-tenant security rejected' — RED if the #7 global-OR-owned fence leaked. DISTINCT
--        from the account cross-tenant test (B5): this fences the SECURITY axis.
--   CROSS-TENANT (authenticated B + privileged orphan check):
--   (Bscope) [CRITERION 3] caller-scoped holdings: tenant B calling fn_holdings_as_of sees ZERO of
--        A's (accta, g_asset) position — the roll-forward read is INVOKER/caller-scoped (B3 is the
--        non-vacuous companion: A sees its own 200). RED if fn_holdings_as_of lost RLS composition.
--   (B5) [CRITERION 2] cross-tenant ACCOUNT fail-closed: tenant B calling fn_create_stock_split
--        for A's account RAISES 'not found or not visible' via the RPC's account-resolve guard
--        (A's account invisible under B's RLS → fail closed). DEFINER would BREAK this — INVOKER is
--        load-bearing. Encodes migration CONTRACT step (b).
--        HISTORY: this cross-tenant probe caught a pre-merge defect — the RPC's original account
--        guard (`v_account_found boolean := false; select true into v_account_found …; if not
--        v_account_found`) was dead on a no-match (SELECT INTO sets the var to NULL → `if not NULL`
--        skips the raise), so a cross-tenant caller fell through to the 'nothing to split' guard.
--        Architect fixed it to the `FOUND` idiom before merge, so B5 now fires the account fence
--        per contract. (Isolation is additionally proven — independent of this guard — by Bscope + B5b.)
--   (B5b) [CRITERION 2] NO row landed: after B's cross-tenant attempt (ratio 3:1 — a marker A
--        never used), ZERO 'Stock split 3:1' corp_action rows exist on A's account (the raise left
--        no orphan on the immutable ledger; account_trans has no authenticated DELETE).
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22 + RT-26 + RT-27; 039 adds ZERO catalogued
--   §10 instances — a role-agnostic table CHECK + one authenticated-tier SECURITY INVOKER RPC; no
--   service_role grant, no credential, no admission channel). Decision-3 family UNCHANGED — 039
--   adds NO FK-shaped reference column: the CHECK is a value/book-neutrality invariant on existing
--   columns; the RPC INSERTs a row carrying the EXISTING account_trans.security_id FK → it EXERCISES
--   the already-realized #7 fence (Bfence), it does not add a new instance (POSITION-LEVEL, OWD-1 →
--   C: no lot-linkage column). SECURITY DEFINER allowlist UNCHANGED at 4 (the RPC is INVOKER; the
--   CHECK is not a function). De-conflation: the corp_action-shape CHECK is a value invariant, NOT
--   a §10 instance and NOT a Decision-3 instance. This battery introduces no catalogued instance.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants _rls.tenant_a()/_b(); NO PII / NO
--   real account numbers / NO prod data. GLOBAL securities users_id NULL (016/017 #7; legal for any
--   tenant), UNPRICED (no eod_price → fn_compute_nav values positions at 0 in the memo pair, which
--   nets 0 — the book-neutrality assertion is untouched; the 035/037 posture). A owns acct-alpha (a
--   real position via a standard BUY) + acct-linked (provider-linked, the source-of-truth fixture);
--   B owns acct-beta + b_asset (a PRIVATE B-owned security — the #7 cross-tenant-security referent).
--   account.users_id set EXPLICITLY (auth.uid() NULL under postgres). All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121): `_rls` grants no USAGE to authenticated; each block restores
--   role=postgres before the next; \gset var names ALL-LOWERCASE; %L for uuids / %s for bigints;
--   SQLSTATE-precise throws_ok (23514) for the CHECK + MESSAGE-precise throws_like for the RPC /
--   #7 raises (P0001 all — SQLSTATE alone would not distinguish the raise reasons; 004 lesson).
--
-- ⟦WIRE-VALIDATE⟧ authored against 039's firmed contract + locally verified via a net-zero rolled-
--   back transient harness (pgtap + 039 applied in one txn, rolled back — DB confirmed unchanged);
--   the AUTHORITATIVE run is the 001→039 reset stack under CI (pg_prove directory-mode, db-tests.yml,
--   after Backend's clean-apply + `supabase migration up`). The committed file does NOT self-apply
--   the migration. plan(21).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case → ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(21);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres — RLS + ACL bypassed; the creator-grant trigger, the #7 fence, and
-- the matched-linked_source fence fire role-agnostically and PASS on the well-formed seed).
--  - Two tenants A + B, both mfa 'none' (→ the account_trans_insert aal2 backstop is a no-op).
--  - Accounts via the 003 creator-grant trigger (rd=t/wr=t). A: acct-alpha (source-of-truth) +
--    acct-linked (provider-linked). B: acct-beta (the cross-tenant intruder).
--  - Assets: g_asset (GLOBAL; A holds a position) + g_asset2 (GLOBAL; A holds NONE) + b_asset
--    (PRIVATE, users_id=B; the #7 cross-tenant-security referent).
--  - A's position: a standard BUY of 100 g_asset @ 2026-05-01 (cost_basis 1000 → a real book leg
--    for the (B4b) non-vacuous GL anchor). Unpriced.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.user_settings (users_id, mfa_policy) values (:'ta', 'none'), (:'tb', 'none');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-alpha', 'investment', 'household', 'taxable') returning account_id as accta \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'acct-beta', 'investment', 'household', 'taxable') returning account_id as acctb \gset

insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'ZG39A', 'QA 39 Sec A (global)') returning asset_id as g_asset \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'ZG39B', 'QA 39 Sec B (global, no position)') returning asset_id as g_asset2 \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (:'tb', 'equity', 'market_feed', 'ZG39C', 'QA 39 Sec C (B-private)') returning asset_id as b_asset \gset

-- A's position-establishing BUY (standard; security set, quantity 100, cost_basis 1000 → P1 cash +
-- P2 position book legs → the (B4b) GL anchor). Dated well before the split ex-date.
insert into pfin.account_trans
  (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
  values (:accta, '2026-05-01', -1000, 'vBUY', 'buy 100 g_asset @10', 'standard', :g_asset, 100, 1000)
  returning trans_id as buy_tid \gset

-- A's provider-linked source + account (source-of-truth guard fixture). linked_source.users_id = A
-- = account.users_id → the 015 matched-linked_source fence PASSES on the seed.
insert into pfin.linked_source (users_id, provider, institution_name)
  values (:'ta', 'plaid', 'QA 39 Institution') returning source_id as a_source \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment, linked_source_id)
  values (:'ta', 'acct-linked', 'investment', 'household', 'taxable', :a_source)
  returning account_id as acctlink \gset

-- =====================================================================
-- PART A — CHECK account_trans_corp_action_shape, exercised across postgres / authenticated /
--   service_role to prove it is a ROLE-AGNOSTIC table CHECK (Sec criterion 4). The two ADMIT rows
--   (A1/A4) are dated 2027, AFTER every PART B holdings as-of read. Rejects do not persist.
-- =====================================================================
-- (A1) ADMIT (postgres): book-neutral corp_action w/ a NONZERO quantity delta PASSES.
select lives_ok(
  format($$ insert into pfin.account_trans
    (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
    values (%s, '2027-01-05', 0, 'vCA1', 'A1 book-neutral split delta', 'corp_action', %s, 50, null) $$,
    :accta, :g_asset),
  '(A1) shape CHECK ADMITS: a book-neutral corp_action (amount=0, cost_basis NULL) with a NONZERO quantity delta (50) PASSES — admits the split fact and leaves quantity UNCONSTRAINED'
);
-- (A2) amount<>0 corp_action RAISES 23514 (postgres).
select throws_ok(
  format($$ insert into pfin.account_trans
    (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
    values (%s, '2027-01-06', 100, 'vCA2', 'A2 substantive amount', 'corp_action', %s, 0, null) $$,
    :accta, :g_asset),
  '23514', null,
  '(A2) shape CHECK fails closed (postgres): a corp_action with amount<>0 RAISES 23514 — a substantive (cash-carrying) corp_action is blocked in V1'
);
-- (A3) cost_basis<>0 corp_action RAISES 23514 (postgres; the NULL-safe coalesce clause).
select throws_ok(
  format($$ insert into pfin.account_trans
    (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
    values (%s, '2027-01-07', 0, 'vCA3', 'A3 substantive basis', 'corp_action', %s, 0, 25) $$,
    :accta, :g_asset),
  '23514', null,
  '(A3) shape CHECK fails closed (postgres): a corp_action with cost_basis<>0 RAISES 23514 — the coalesce(cost_basis,0)=0 clause is NULL-safe (a naive cost_basis=0 would pass-by-NULL)'
);
-- (A4) a NON-corp_action (standard) row that WOULD violate the clause PASSES (the disjunct).
select lives_ok(
  format($$ insert into pfin.account_trans
    (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
    values (%s, '2027-01-08', -100, 'vA4', 'A4 standard unconstrained', 'standard', %s, 5, 100) $$,
    :accta, :g_asset),
  '(A4) shape CHECK is corp_action-scoped: a STANDARD row (amount<>0 AND cost_basis<>0 — would violate if corp_action) PASSES (the transaction_type<>corp_action disjunct)'
);

-- (A5) [criterion 4] AUTHENTICATED A: RLS admits the owner write, then the table CHECK fires → 23514.
select _rls.set_tenant(:'ta'::uuid);
select throws_ok(
  format($$ insert into pfin.account_trans
    (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
    values (%s, '2027-02-01', 100, 'vA5', 'A5 auth amount<>0', 'corp_action', %s, 0, null) $$,
    :accta, :g_asset),
  '23514', null,
  '(A5) CHECK role-agnostic (authenticated): A''s amount<>0 corp_action on its OWN account (RLS admits the owner write) RAISES 23514 → the CHECK gates the REAL authenticated write tier, not just privileged inserts'
);
select set_config('role', 'postgres', true);

-- (A6) [criterion 4] SERVICE_ROLE: RLS BYPASSED, but the table CHECK STILL fires → 23514.
select _rls.set_service_role();
select throws_ok(
  format($$ insert into pfin.account_trans
    (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
    values (%s, '2027-02-02', 100, 'vA6', 'A6 service_role amount<>0', 'corp_action', %s, 0, null) $$,
    :accta, :g_asset),
  '23514', null,
  '(A6) CHECK role-agnostic (service_role): an amount<>0 corp_action under service_role (which BYPASSES RLS) STILL RAISES 23514 → it is a role-agnostic TABLE CHECK, not an RLS artifact (the ingest tier is fenced too)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK B1 (authenticated A) — fn_create_stock_split owner-create + delta math + book-neutrality.
--   Forward 2:1 on the 100-share g_asset position (delta = 100 × (2/1 − 1) = +100), then reverse.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- The composition under test: one call = one book-neutral corp_action row + its 023 annotation.
select pfin.fn_create_stock_split(:accta, :g_asset, 2, 1, '2026-06-01'::date) as split_tid \gset

-- (B1) [criterion 1] exactly ONE A-owned book-neutral corp_action row (quantity=delta=100).
select is(
  (select count(*) from pfin.account_trans
     where trans_id = :split_tid and account_id = :accta and transaction_type = 'corp_action'
       and amount = 0 and cost_basis is null and security_id = :g_asset and quantity = 100)::bigint,
  1::bigint,
  '(B1) owner-create: exactly ONE A-owned book-neutral corp_action row (amount=0, cost_basis NULL, quantity=delta=100 = 100 × (2/1 − 1), security set) for the returned trans_id'
);
-- (B2) [criterion 1] ...its 023 annotation landed ATOMICALLY in the SAME call.
select is(
  (select count(*) from pfin.account_trans_annotation
     where trans_id = :split_tid and sub_cat_id is null
       and metadata->>'action' = 'split'
       and (metadata->>'ratio_num')::numeric = 2
       and (metadata->>'ratio_den')::numeric = 1)::bigint,
  1::bigint,
  '(B2) atomic annotation: the 023 annotation (sub_cat_id NULL; metadata {action:split, ratio_num:2, ratio_den:1}) landed in the SAME RPC call as the corp_action row (composed atomically under the caller''s RLS)'
);
-- (B3) [criterion 6 forward] restates own holdings: fn_holdings_as_of = 200 = 100 × 2 (delta +100).
select is(
  (select h.quantity from pfin.fn_holdings_as_of('2026-06-01'::date) h
     where h.account_id = :accta and h.asset_id = :g_asset),
  200::numeric,
  '(B3) forward split restates holdings: after 2:1, fn_holdings_as_of(ex_date) for (accta, g_asset) = 200 = position 100 × 2 (delta = position × (ratio − 1) = +100 via 019''s roll-forward)'
);
-- (B4) book-neutrality (load-bearing GL): fn_gl_entries emits ZERO rows for the split trans_id.
select is(
  (select count(*) from pfin.fn_gl_entries('2026-06-30'::date) where source_trans_id = :split_tid)::bigint,
  0::bigint,
  '(B4) book-neutral GL: fn_gl_entries emits ZERO rows for the split''s corp_action trans_id — P1 skips (amount=0), P2 skips (cost_basis NULL), P9 evaluates to 0 & drops. A book-neutral corp_action moves NO book value'
);
-- (B4b) non-vacuous GL anchor: fn_gl_entries emits >0 rows for the position-establishing BUY.
select cmp_ok(
  (select count(*) from pfin.fn_gl_entries('2026-06-30'::date) where source_trans_id = :buy_tid),
  '>', 0::bigint,
  '(B4b) non-vacuous: fn_gl_entries emits >0 rows for the position-establishing BUY (P1 cash + P2 position legs) — the GL engine is LIVE, so (B4)''s ZERO for the split is a genuine book-neutrality, not an empty-set 0'
);

-- (Brev) [criterion 6 reverse] reverse 1:2 split: fn_holdings_as_of = 100 = 200 × 1/2 (delta = −100;
--        the position SHRINKS but stays > 0). A book-neutral corp_action carrying a NEGATIVE delta.
select pfin.fn_create_stock_split(:accta, :g_asset, 1, 2, '2026-06-02'::date) as rev_tid \gset
select is(
  (select h.quantity from pfin.fn_holdings_as_of('2026-06-02'::date) h
     where h.account_id = :accta and h.asset_id = :g_asset),
  100::numeric,
  '(Brev) reverse split restates holdings: after a 1:2 reverse on the 200-share position, fn_holdings_as_of = 100 = 200 × 1/2 (delta = −100; the position SHRINKS but stays > 0) — proves reverse-split delta is correctly signed'
);

select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK B2 (authenticated A) — the RPC fail-closed paths on A's OWN context + the #7 fence. Each
--   RAISEs before any row lands. (The current position after Brev is 100 g_asset shares.)
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (B6) [criterion 5] source-of-truth guard: A on its OWN provider-linked account → raise.
select throws_like(
  format($$ select pfin.fn_create_stock_split(%s, %s, 2, 1, '2026-06-01'::date) $$, :acctlink, :g_asset),
  '%provider-linked%',
  '(B6) source-of-truth guard: A calling fn_create_stock_split on its OWN provider-linked account (linked_source_id NOT NULL) RAISES — linked splits arrive via reconciliation (SELF-204), never manual entry'
);
-- (B7) [criterion 6 empty / 3] empty position: A for g_asset2 (holds NONE) → 'nothing to split'.
select throws_like(
  format($$ select pfin.fn_create_stock_split(%s, %s, 2, 1, '2026-06-01'::date) $$, :accta, :g_asset2),
  '%nothing to split%',
  '(B7) empty position: A calling for a security it holds NO position in (g_asset2) RAISES ''nothing to split'' — the RPC''s caller-scoped position read fails closed on a 0/none holding'
);
-- (B8) [criterion 6 no-op] 1:1 → delta 0 → 'no-op'.
select throws_like(
  format($$ select pfin.fn_create_stock_split(%s, %s, 1, 1, '2026-06-02'::date) $$, :accta, :g_asset),
  '%no-op%',
  '(B8) no-op ratio: a 1:1 ratio yields a zero delta (100 × (1/1 − 1) = 0) → RAISES ''no-op'' — a zero-delta corp_action that restates nothing is rejected'
);
-- (B9) [criterion 6 bad] ratio num=0 (≤0) → 'positive rational'.
select throws_like(
  format($$ select pfin.fn_create_stock_split(%s, %s, 0, 1, '2026-06-02'::date) $$, :accta, :g_asset),
  '%positive rational%',
  '(B9) bad ratio (num=0, ≤0): RAISES ''ratio must be a positive rational'' — a non-positive ratio is not a split'
);
-- (B10) [criterion 6 bad] ratio den NULL → 'positive rational' (the NULL branch).
select throws_like(
  format($$ select pfin.fn_create_stock_split(%s, %s, 2, null, '2026-06-02'::date) $$, :accta, :g_asset),
  '%positive rational%',
  '(B10) bad ratio (den NULL): RAISES ''ratio must be a positive rational'' — the NULL branch fails closed (a NULL denominator would divide-by-NULL downstream)'
);
-- (Bfence) [criterion 7] #7 security fence: a DIRECT INSERT (authenticated A) of a corp_action row
--        on A's OWN account (RLS admits) carrying a security_id owned by TENANT B (not global, not
--        A's) → the 017 #7 global-OR-owned fence RAISES. Distinct from the account cross-tenant test.
select throws_like(
  format($$ insert into pfin.account_trans
    (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
    values (%s, '2026-06-10', 0, 'vFENCE', 'x-tenant security', 'corp_action', %s, 10, null) $$,
    :accta, :b_asset),
  '%cross-tenant security rejected%',
  '(Bfence) #7 security fence: a corp_action row on A''s OWN account carrying a TENANT-B-owned security_id (not global, not A''s) RAISES ''cross-tenant security rejected'' (017 global-OR-owned fence). The SECURITY axis, distinct from the account cross-tenant test (B5)'
);

select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK B3 (authenticated B) — cross-tenant fails closed: holdings caller-scoped (criterion 3) +
--   the account guard (criterion 2). The INVOKER isolation proof.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);

-- (Bscope) [criterion 3] caller-scoped holdings: B sees ZERO of A's (accta, g_asset) position →
--          fn_holdings_as_of composes ENTIRELY under B's RLS (B3 is the non-vacuous companion:
--          A sees its own 200). RED (>0) if the roll-forward read lost RLS composition.
select is(
  (select count(*) from pfin.fn_holdings_as_of('2026-06-01'::date)
     where account_id = :accta and asset_id = :g_asset)::bigint,
  0::bigint,
  '(Bscope) caller-scoped holdings: tenant B calling fn_holdings_as_of sees ZERO of A''s (accta, g_asset) position — the roll-forward read is INVOKER/caller-scoped (A sees its own 200 in B3). RED if fn_holdings_as_of lost RLS composition'
);

-- (B5) [criterion 2] cross-tenant ACCOUNT fail-closed: B calls for A's account with a MARKER ratio
--      (3:1) A never used → the account-resolve guard (FOUND idiom) raises. (Isolation is also
--      proven independent of this guard by Bscope + B5b.)
select throws_like(
  format($$ select pfin.fn_create_stock_split(%s, %s, 3, 1, '2026-06-01'::date) $$, :accta, :g_asset),
  '%not found or not visible%',
  '(B5) cross-tenant ACCOUNT fail-closed: tenant B calling fn_create_stock_split for A''s account RAISES ''not found or not visible'' — A''s account is invisible under B''s RLS, so the account-resolve guard (FOUND idiom) fails closed. DEFINER would BREAK this (INVOKER load-bearing)'
);

select set_config('role', 'postgres', true);

-- (B5b) [criterion 2] NO row landed: B's cross-tenant attempt left NO orphan on the immutable
--       ledger. Privileged read (full visibility) for the 3:1 marker A never legitimately used.
select is(
  (select count(*) from pfin.account_trans
     where account_id = :accta and transaction_type = 'corp_action' and description = 'Stock split 3:1')::bigint,
  0::bigint,
  '(B5b) NO row landed: B''s cross-tenant attempt (marker ratio 3:1) left ZERO ''Stock split 3:1'' corp_action rows on A''s account — the raise created no orphan (account_trans is immutable; no authenticated DELETE, so rollback/abort is the only guard)'
);

select * from finish();
rollback;

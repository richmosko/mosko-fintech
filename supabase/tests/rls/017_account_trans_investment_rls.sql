-- =====================================================================
-- Per-Wave battery — pfin.account_trans investment columns + the NOVEL global-OR-
--   matched-tenant security_id fence + fn_ingest_transactions bulk RPC
--   (ADR-027 / 017 — V1-SHIP-BLOCK; sec-joint-review GREEN, this battery is the
--    remaining merge-gate; the batch's HEAVIEST Sec surface)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/017_account_trans_investment.sql
--   - pfin.account_trans gains: security_id (nullable FK → pfin.asset), signed quantity
--       numeric(28,8) NOT NULL DEFAULT 0, cost_basis / price numeric(20,4), the generic
--       provider-dedup pair source_provider + provider_txn_id (+ partial-unique
--       account_trans_provider_dedup_idx), provider_category (display hint); DROPs
--       plaid_transaction_id.
--   - CHECK account_trans_qty_requires_security (quantity = 0 OR security_id IS NOT NULL)
--       — the uniform cash-as-asset invariant (23514).
--   - CHECK account_trans_{quantity,cost_basis,price}_finite — 014-style NaN rejection
--       (23514; disambiguated by CONSTRAINT NAME, not bare SQLSTATE — the 004 lesson).
--   - fn_account_trans_security_asset() — BEFORE INSERT WHEN (security_id IS NOT NULL);
--       SECURITY INVOKER; the NOVEL global-OR-matched-tenant fence (Decision-3 CANONICAL
--       instance #7 / Pattern 2 site 1). Global (asset.users_id IS NULL) OR owned by the
--       account's tenant (asset.users_id = account.users_id, resolved via account JOIN).
--   - fn_ingest_transactions(jsonb) RETURNS TABLE(inserted, skipped) — SECURITY INVOKER
--       (R-15); all-or-nothing set-based insert…select…on conflict (provider dedup) do
--       nothing; EXECUTE granted to authenticated only.
-- Prereqs exercised (already on main / to be applied by Backend): 003 (pfin.account +
--   the DEFINER creator-grant trigger the 006 policies JOIN), 004 (immutable ledger +
--   its block-mutation/matched-account triggers), 006 (account_trans rd/wr_access-JOIN
--   RLS + GRANT select,insert to authenticated), 008 (service_role SELECT,INSERT on
--   account_trans — the fenced ingest path), 016 (pfin.asset hybrid registry + the
--   committed GLOBAL currency seed the fence's global disjunct reads).
-- Reuses the SELF-187/189/190/196/012/015/016 idiom: \ir verbs, ALL-LOWERCASE \gset
--   literals (005 case-fold lesson), CONSTRAINT-NAME-precise throws_like (004 all-42501/
--   all-23514 false-green lesson), role restored to postgres between blocks (PR #121
--   _rls-USAGE root-cause).
--
-- ┌─ THE LOAD-BEARING LEG — THE FENCE UNDER service_role (why this battery is heavy) ────┐
-- │ account_trans is written under service_role by the provider-sync ingest path (008    │
-- │ grant; RLS BYPASSED). service_role bypasses RLS but NOT triggers, so the BEFORE       │
-- │ INSERT security_id fence is the SOLE gate there. A vanilla "under authenticated"      │
-- │ assertion (a3) is NECESSARY but INSUFFICIENT: under authenticated the fence composes  │
-- │ with 016's asset RLS (B's asset is RLS-invisible to A anyway), so a3 could pass even  │
-- │ if the trigger did nothing and RLS carried the whole load. Only (a4) — the SAME       │
-- │ cross-tenant INSERT under service_role, where RLS is bypassed and B's asset IS        │
-- │ visible to the subquery — proves the TRIGGER's explicit JOIN-to-account predicate     │
-- │ (not RLS) rejects it. (a4) is the whole point of 017. (a5) is its non-vacuous         │
-- │ control: a legit matched-tenant security under service_role still PASSES (the fence   │
-- │ does not blanket-block the ingest path).                                              │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ WHY EACH REJECTION MATCHES A DIFFERENT SIGNAL (no fence passes for another) ─────────┐
-- │  • cross-tenant/forged security_id (fence)   -> raise 'cross-tenant security rejected%'│
-- │  • quantity!=0 & security_id NULL            -> CHECK account_trans_qty_requires_security│
-- │  • quantity/cost_basis/price = NaN           -> CHECK account_trans_{col}_finite (each) │
-- │  • foreign account_id via the RPC (no wr)    -> RLS WITH CHECK 'new row violates …'     │
-- │ All CHECK violations share SQLSTATE 23514, so they are matched by CONSTRAINT NAME      │
-- │ (throws_like '%<constraint>%'), never a bare 23514 — one CHECK can never pass for      │
-- │ another (the 004 all-42501 discipline, applied to 23514 here).                         │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (a1)/(a2)  -> non-vacuous positives: global + owned security-legs PASS under authenticated
--                  (guards an over-broad fence that blocked legit securities).
--   (a3)         -> RED if the fence trigger were removed: cross-tenant security INSERT would
--                  commit under authenticated (here also RLS-blind, belt-and-suspenders).
--   (a4)         -> LOAD-BEARING: RED if the fence relied on RLS instead of the explicit
--                  account-JOIN predicate — under service_role (RLS bypassed) the cross-tenant
--                  security would COMMIT. This is the sole assertion that isolates the TRIGGER.
--   (a5)         -> non-vacuous service_role control: a matched-tenant security under
--                  service_role PASSES (fence is owner-mismatch-driven, not a blanket block).
--   (b1)         -> RED if account_trans_qty_requires_security were dropped (a share movement
--                  with no security would land — poisons holdings).
--   (b2)/(b3)/(b4)-> RED if the respective _finite CHECK were dropped (a NaN would poison every
--                  SUM/holdings aggregation on the immutable ledger; can never be UPDATEd out).
--   (b5)         -> non-vacuous positive: a pure-cash row (quantity=0/security NULL) PASSES
--                  (guards an over-strict invariant that rejected legit cash).
--   (c1)         -> RED if the RPC dropped rows / mis-counted (inserted/skipped contract).
--   (c2)         -> RED if the RPC were NOT all-or-nothing: one bad row would leave the good
--                  rows committed. Asserted as raise + acct-A count UNCHANGED (0 landed).
--   (c3)         -> RED if the RPC bypassed the caller's RLS (R-15): a foreign-account row
--                  would land. The wr_access WITH CHECK rejects → whole batch aborts.
--   (c4)         -> RED if provider dedup broke: a re-presented (source_provider, provider_txn_id)
--                  would double-insert (skipped) instead of being skipped, or would abort the batch.
--   (d1)/(d2)    -> RED if the RPC's jsonb column list were widened to accept is_reverse /
--                  replaces_trans_id / trans_id (mass-assignment) — the landed row must carry the
--                  DEFAULTS, not the injected values.
--   (e1)/(e2)    -> Sec's fail-closed CORRECTNESS ask: RED if the fence's RLS-scoped account
--                  subquery spuriously rejected a legit own-account security-leg insert — proves
--                  account SELECT-visibility ⊇ account_trans wr_access (no false-positive fence).
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 2 (RT-22 + RT-26; 017 introduces ZERO catalogued
--   §10 instances — authenticated-tier column/RLS/trigger DDL + one INVOKER RPC; adds no
--   service_role grant, so no RT-26 code-layer surface). Decision-3 family: instance #7 REALIZED
--   here (account_trans.security_id → pfin.asset, the novel global-OR-matched-tenant fence,
--   Pattern 2 site 1); the count moves 6→7 per the ADR-027 atomic amendment (g) — no new ADR.
--   This battery is the pgTAP proof of #7 (the mechanism), verifying the fence catches a REAL
--   cross-tenant violation, incl. under the service_role write path.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b(); NO PII
--   / NO real account numbers / NO prod data. A owns acct-A; B owns acct-B (both via the 003
--   creator-grant trigger, which keys on new.users_id). A's per-user asset + B's per-user asset
--   are seeded PRIVILEGED with users_id set EXPLICITLY (auth.uid() is NULL under postgres, so an
--   omitted users_id would land a GLOBAL row). The GLOBAL security-leg uses the committed USD
--   currency-asset from the 016 seed. All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so NO
--   `_rls.*` call runs under authenticated. Tenant UUIDs + account/asset ids + the baseline
--   count are resolved to psql LITERALS via \gset at role=postgres; every _rls.set_tenant is
--   called at role=postgres and each block restores role=postgres before the next. \gset var
--   names are ALL-LOWERCASE.
--
-- ⟦WIRE-VALIDATE⟧ (mirrors 004): the (a4)/(a5) service_role legs depend on `service_role`
--   (i) existing in the test stack, (ii) holding BYPASSRLS, and (iii) being able to run pgTAP
--   fns. The fence's subquery reads pfin.asset + pfin.account under SECURITY INVOKER, so under
--   service_role it needs SELECT on BOTH — granted IN-TEST (rolled back) so the TRIGGER, not a
--   missing ACL, is isolated as the sole gate (a missing SELECT would 42501 'permission denied
--   for table asset', a false-RED). FORWARD-NOTE (not a 017 defect): the real provider-sync
--   worker path (a later, deferred + C6-gated surface — 016 leg g3) will likewise need
--   service_role SELECT on pfin.asset + pfin.account for the fence's read to execute; 017
--   correctly adds no service_role grant, but the worker-enablement migration must.
--   Local stack sits at 016 — `supabase test db` cannot reach 017 until Backend applies it;
--   RED-until-017-applied is expected. CI (pg_prove directory-mode) after Backend's apply is
--   the green gate. plan(19).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(19);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed seed path).
--  - A owns acct-A, B owns acct-B (003 creator-grant trigger seeds rd=t/wr=t on each,
--    keyed on new.users_id — this is what lets authenticated A insert into acct-A below).
--  - g_usd = the committed GLOBAL USD currency-asset (users_id NULL) from the 016 seed —
--    the global-disjunct target for the fence's PASS path.
--  - a_asset = a per-user asset OWNED BY A; b_asset = a per-user asset OWNED BY B
--    (users_id set EXPLICITLY — auth.uid() is NULL under postgres). b_asset is the
--    cross-tenant target the fence must reject.
--  - service_role ACLs held OPEN in-test (rolled back) so the fence TRIGGER — not a
--    missing grant — is the sole gate on the (a4)/(a5) service_role legs.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-A', 'depository', 'household', 'taxable')
  returning account_id as accta \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'acct-B', 'depository', 'household', 'taxable')
  returning account_id as acctb \gset

select asset_id as g_usd from pfin.asset where symbol = 'USD' and users_id is null \gset

insert into pfin.asset (users_id, asset_type, pricing_source, name)
  values (:'ta', 'collectible', 'manual_valuation', 'A owned security')
  returning asset_id as a_asset \gset
insert into pfin.asset (users_id, asset_type, pricing_source, name)
  values (:'tb', 'collectible', 'manual_valuation', 'B owned security')
  returning asset_id as b_asset \gset

-- Hold the ACLs the fence's subquery + the ingest INSERT need OPEN to service_role
-- (test setup, rolled back). SELECT on pfin.asset + pfin.account = the fence's read path;
-- INSERT on account_trans = the ingest write path (008 already grants it — harmless dup).
grant usage on schema pfin to service_role;
grant select on pfin.asset to service_role;
grant select on pfin.account to service_role;
grant insert on pfin.account_trans to service_role;

-- =====================================================================
-- LEG (a) — the security_id fence, under authenticated AND under service_role.
-- =====================================================================
-- BLOCK A (authenticated A) — global PASS, owned PASS, cross-tenant RAISE.
select _rls.set_tenant(:'ta'::uuid);

-- (a1) GLOBAL asset -> PASS (the fence's `asset.users_id IS NULL` disjunct).
select lives_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, vendor, description)
              values (%s, '2026-03-01', -100, 5, %s, 'a1-glob', 'A buys a GLOBAL security') $$, :accta, :g_usd),
  '(a1) fence PASS (global): authenticated A inserts a security-leg row into A''s account referencing a GLOBAL asset (users_id NULL) — allowed by the global-OR-owned fence'
);

-- (a2) A-OWNED asset -> PASS (the fence's matched-tenant disjunct, asset.users_id = account.users_id).
select lives_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, vendor, description)
              values (%s, '2026-03-02', -50, 3, %s, 'a2-own', 'A buys an A-OWNED custom security') $$, :accta, :a_asset),
  '(a2) fence PASS (owned): authenticated A inserts a security-leg row referencing an A-OWNED asset (asset.users_id = account.users_id) — allowed by the matched-tenant disjunct'
);

-- (a3) B-OWNED asset -> RAISE (cross-tenant) under authenticated (belt-and-suspenders:
--      B's asset is also RLS-invisible to A, so the subquery is empty either way).
select throws_like(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, vendor)
              values (%s, '2026-03-03', -50, 3, %s, 'a3-x') $$, :accta, :b_asset),
  'cross-tenant security rejected%',
  '(a3) fence RAISE under authenticated: A references an asset OWNED BY B — REJECTED by the global-OR-owned fence (NOT EXISTS → raise; belt-and-suspenders with 016 asset RLS)'
);
select set_config('role', 'postgres', true);

-- BLOCK A-SVC (service_role) — THE LOAD-BEARING LEG. RLS is BYPASSED, so B's asset IS
--   visible to the subquery; only the TRIGGER's explicit account-JOIN predicate rejects it.
select set_config('role', 'service_role', true);

-- (a4) LOAD-BEARING: cross-tenant security under service_role STILL RAISES — the trigger,
--      not RLS, is the sole gate on the provider-sync ingest path.
select throws_like(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, vendor)
              values (%s, '2026-03-04', -50, 3, %s, 'a4-svc-x') $$, :accta, :b_asset),
  'cross-tenant security rejected%',
  '(a4) LOAD-BEARING fence RAISE under service_role: service_role (RLS BYPASSED — B''s asset IS visible) inserting B''s asset into A''s account STILL RAISES — the explicit account-JOIN predicate (NOT RLS) is the sole gate on the service_role ingest path'
);

-- (a5) non-vacuous service_role control: a matched-tenant (A-owned) security under
--      service_role PASSES — the fence is owner-mismatch-driven, not a blanket block.
select lives_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, vendor)
              values (%s, '2026-03-05', -50, 3, %s, 'a5-svc-ok') $$, :accta, :a_asset),
  '(a5) fence does NOT over-block the ingest path: service_role inserting an A-OWNED (matched-tenant) security into A''s account is ACCEPTED (non-vacuous service_role control)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (b) — the CHECK constraints (role-agnostic; run under authenticated A).
--   CONSTRAINT-NAME-precise (all are 23514; a bare SQLSTATE would let one pass for another).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (b1) quantity != 0 with security_id NULL -> qty_requires_security (trigger does NOT fire:
--      WHEN security_id IS NOT NULL is false — only the CHECK gates).
select throws_like(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, quantity, vendor)
              values (%s, '2026-03-06', -10, 5, 'b1') $$, :accta),
  '%account_trans_qty_requires_security%',
  '(b1) qty_requires_security: a share movement (quantity != 0) with security_id NULL is REJECTED (23514, constraint-name-precise) — the uniform cash-as-asset invariant'
);

-- (b2) quantity = NaN -> quantity_finite. Isolated with a VALID a_asset security so
--      qty_requires_security passes first and ONLY the finite CHECK can fire.
select throws_like(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, vendor)
              values (%s, '2026-03-07', -10, 'NaN', %s, 'b2') $$, :accta, :a_asset),
  '%account_trans_quantity_finite%',
  '(b2) quantity_finite: quantity = NaN is REJECTED (constraint-name-precise; isolated via a valid security so qty_requires_security passes, proving the finite CHECK — not another — fires)'
);

-- (b3) cost_basis = NaN -> cost_basis_finite (on a pure-cash row so only this CHECK gates).
select throws_like(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, quantity, cost_basis, vendor)
              values (%s, '2026-03-08', -10, 0, 'NaN', 'b3') $$, :accta),
  '%account_trans_cost_basis_finite%',
  '(b3) cost_basis_finite: cost_basis = NaN is REJECTED (constraint-name-precise)'
);

-- (b4) price = NaN -> price_finite (pure-cash row).
select throws_like(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, quantity, price, vendor)
              values (%s, '2026-03-08', -10, 0, 'NaN', 'b4') $$, :accta),
  '%account_trans_price_finite%',
  '(b4) price_finite: price = NaN is REJECTED (constraint-name-precise)'
);

-- (b5) pure-cash (quantity=0 / security_id NULL) -> PASS (the invariant permits cash).
select lives_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, quantity, vendor)
              values (%s, '2026-03-09', -25, 0, 'b5') $$, :accta),
  '(b5) pure-cash invariant: quantity=0 / security_id NULL is ACCEPTED (uniform cash-as-asset model permits cash rows — non-vacuous positive)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (c) — fn_ingest_transactions: all-land, all-or-nothing, RLS-enforced, provider dedup.
-- =====================================================================
-- (c1) a valid 2-row batch under A lands both -> RETURNS (inserted=2, skipped=0). Row 1
--      carries a provider key (seedprov, TXN-DEDUP-1) — the committed anchor for (c4).
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select inserted::text || '/' || skipped::text
     from pfin.fn_ingest_transactions(
       format($$[
         {"account_id":%s,"transaction_date":"2026-03-10","amount":-50,"vendor":"c1a","quantity":0,"source_provider":"seedprov","provider_txn_id":"TXN-DEDUP-1"},
         {"account_id":%s,"transaction_date":"2026-03-11","amount":-60,"vendor":"c1b","quantity":0}
       ]$$, :accta, :accta)::jsonb)),
  '2/0',
  '(c1) fn_ingest_transactions all-land: a valid 2-row batch under A inserts both — RETURNS (inserted=2, skipped=0)'
);
select set_config('role', 'postgres', true);

-- Baseline for the all-or-nothing assertion (privileged re-read AFTER c1 committed).
select count(*) as cnt_before from pfin.account_trans where account_id = :accta \gset

-- (c2) all-or-nothing: a batch with ONE bad row (quantity!=0 & security_id NULL) aborts the
--      WHOLE call. (c3) a batch row targeting acct-B (foreign account) is rejected by the
--      006 wr_access WITH CHECK (R-15: the RPC inserts under the CALLER's RLS). Both raise;
--      throws_like rolls each back to its savepoint, so nothing lands.
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ select * from pfin.fn_ingest_transactions($j$[
      {"account_id":%s,"transaction_date":"2026-03-12","amount":-70,"vendor":"c2good","quantity":0},
      {"account_id":%s,"transaction_date":"2026-03-13","amount":-80,"vendor":"c2bad","quantity":9}
    ]$j$::jsonb) $$, :accta, :accta),
  '%account_trans_qty_requires_security%',
  '(c2) all-or-nothing raise: a batch with ONE bad row (quantity!=0, security_id NULL) aborts the WHOLE call (constraint-name-precise) — the good row does NOT land'
);
select throws_like(
  format($$ select * from pfin.fn_ingest_transactions($j$[
      {"account_id":%s,"transaction_date":"2026-03-14","amount":-90,"vendor":"c3","quantity":0}
    ]$j$::jsonb) $$, :acctb),
  'new row violates row-level security policy%for table "account_trans"',
  '(c3) RLS-enforced (R-15): a batch row targeting acct-B (owned by B, called under A) is REJECTED by the 006 wr_access WITH CHECK — the whole batch aborts'
);
select set_config('role', 'postgres', true);

-- (c2/count) the behavioral all-or-nothing proof: after the two aborted batches, acct-A's
--      account_trans count is UNCHANGED (0 rows from c2/c3 landed).
select is(
  (select count(*) from pfin.account_trans where account_id = :accta)::bigint,
  :cnt_before::bigint,
  '(c2/count) all-or-nothing rollback: after the aborted bad-row (c2) + foreign-account (c3) batches, acct-A''s account_trans count is UNCHANGED — no partial batch landed'
);

-- (c4) provider dedup: re-present the committed (seedprov, TXN-DEDUP-1) plus one NEW row ->
--      the duplicate is SKIPPED (ON CONFLICT DO NOTHING), the new row lands, the batch does
--      NOT abort -> RETURNS (inserted=1, skipped=1).
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select inserted::text || '/' || skipped::text
     from pfin.fn_ingest_transactions(
       format($$[
         {"account_id":%s,"transaction_date":"2026-03-15","amount":-50,"vendor":"c4dup","quantity":0,"source_provider":"seedprov","provider_txn_id":"TXN-DEDUP-1"},
         {"account_id":%s,"transaction_date":"2026-03-16","amount":-55,"vendor":"c4new","quantity":0,"source_provider":"seedprov","provider_txn_id":"TXN-NEW"}
       ]$$, :accta, :accta)::jsonb)),
  '1/1',
  '(c4) provider dedup: a batch re-presenting an already-committed (source_provider, provider_txn_id) plus one new row → duplicate SKIPPED, new row inserted — RETURNS (inserted=1, skipped=1); the batch does NOT abort'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (d) — mass-assignment blocked: is_reverse / replaces_trans_id / trans_id jsonb keys
--   are NOT in the RPC's jsonb_to_recordset column list, so they are IGNORED — the landed
--   row carries the DEFAULTS + a DB-generated trans_id.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (not an assertion) call the RPC with a row that TRIES to set the excluded columns.
select pfin.fn_ingest_transactions(
  format($$[
    {"account_id":%s,"transaction_date":"2026-03-17","amount":-33,"vendor":"MASSTEST","quantity":0,"is_reverse":true,"replaces_trans_id":123456,"trans_id":999999}
  ]$$, :accta)::jsonb
);
select set_config('role', 'postgres', true);

-- (d1) is_reverse defaulted (false) + replaces_trans_id defaulted (NULL) — jsonb keys ignored.
select is(
  (select is_reverse::text || '/' || coalesce(replaces_trans_id::text, 'null')
     from pfin.account_trans where account_id = :accta and vendor = 'MASSTEST'),
  'false/null',
  '(d1) mass-assignment blocked: the is_reverse + replaces_trans_id jsonb keys are IGNORED (not in the RPC column list) — the landed row carries DEFAULT is_reverse=false / replaces_trans_id NULL'
);
-- (d2) trans_id is DB-generated, NOT the injected 999999.
select is(
  (select (trans_id <> 999999) from pfin.account_trans where account_id = :accta and vendor = 'MASSTEST'),
  true,
  '(d2) mass-assignment blocked: trans_id is DB-generated (identity), NOT the injected jsonb value 999999 — the key was ignored'
);

-- =====================================================================
-- LEG (e) — Sec's fail-closed CORRECTNESS ask (NOT a security assertion): the fence's
--   account subquery is RLS-scoped under authenticated, so a legit own-account security-leg
--   insert must NOT be spuriously rejected. Proves account SELECT-visibility ⊇ wr_access.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (e1) A inserts a valid security-leg row into A's OWN account -> PASS (the account-JOIN
--      resolves under A's account SELECT-visibility; no false-positive fence rejection).
select lives_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, vendor)
              values (%s, '2026-03-18', -40, 2, %s, 'ECORR') $$, :accta, :g_usd),
  '(e1) fail-closed correctness: A inserts a valid security-leg row into A''s OWN account — the fence account-subquery JOIN resolves under A''s account SELECT-visibility (no spurious RLS-scoped rejection)'
);
-- (e2) A can SELECT it back under RLS -> SELECT-visibility ⊇ account_trans wr_access.
select is(
  (select count(*) from pfin.account_trans where account_id = :accta and vendor = 'ECORR')::bigint,
  1::bigint,
  '(e2) fail-closed correctness: A SELECTs back the row it just inserted (rd_access) — account SELECT-visibility ⊇ account_trans wr_access; the legit security-leg insert is visible, not spuriously fenced'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;

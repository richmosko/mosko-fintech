-- =====================================================================
-- Per-Wave battery — pfin.holdings_checkpoint.security_id NOVEL global-OR-matched-tenant fence
--   (ADR-027 / 019 uniform-model amendment — Decision-3 CANONICAL instance #11, Pattern-2 site 3;
--    V1-SHIP-BLOCK; JOINT-REVIEW-MANDATORY — this battery is the pgTAP proof of D3 #11)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/019_eod_price_and_valuation.sql
--   - pfin.holdings_checkpoint GAINS security_id (nullable bigint FK → pfin.asset ON DELETE RESTRICT).
--   - pfin.fn_holdings_checkpoint_security_asset() — BEFORE INSERT WHEN (security_id IS NOT NULL);
--       SECURITY INVOKER; set search_path=''; the NOVEL global-OR-matched-tenant fence. A referenced
--       asset is valid IFF GLOBAL (asset.users_id IS NULL) OR OWNED by the account's tenant
--       (asset.users_id = account.users_id, resolved via account_id JOIN — holdings_checkpoint has no
--       own users_id). NULL-safe fail-closed. Raises 'cross-tenant security rejected: …'. Mirrors the
--       017 account_trans.security_id fence (#7) exactly.
-- Prereqs exercised (001→019 landed stack): 003 (pfin.account + creator-grant trigger the JOIN reads),
--   005 (holdings_checkpoint base + append-only immutability triple-fence → the new fence is BEFORE
--   INSERT only), 008 (service_role schema USAGE), 016 (pfin.asset hybrid registry — the FK target +
--   the global disjunct), 018 (service_role SELECT+INSERT on holdings_checkpoint — the provider-sync
--   write path this fence gates). Reuses the 017 idiom: \ir verbs, ALL-LOWERCASE \gset, message-precise
--   throws_like, role restored to postgres between blocks (PR #121 _rls-USAGE root-cause).
--
-- ┌─ THE LOAD-BEARING LEG — THE FENCE UNDER service_role (mirrors 017) ────────────────────────────┐
-- │ holdings_checkpoint is written ONLY under service_role (018 grant; authenticated has NO INSERT — │
-- │ the append-only provider-sync path). service_role BYPASSES RLS but NOT triggers, so the BEFORE   │
-- │ INSERT fence is the SOLE gate. (a3) is the whole point: under service_role, B's asset IS visible │
-- │ to the fence's subquery (RLS bypassed), so ONLY the explicit account-JOIN predicate — not RLS —  │
-- │ rejects a cross-tenant security. There is NO authenticated fence leg here (unlike 017's a1..a3),  │
-- │ because authenticated cannot reach the table at all (b1 proves the ACL denial).                  │
-- └────────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ WHY EACH SIGNAL IS DISTINCT ────────────────────────────────────────────────────────────────┐
-- │  • cross-tenant / forged security_id (fence)  -> raise 'cross-tenant security rejected%'         │
-- │  • authenticated INSERT (no grant)            -> 'permission denied for table holdings_checkpoint'│
-- │  • NULL security_id                           -> fence WHEN-guard skips → row lands (lives_ok)     │
-- └────────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (a1)  -> non-vacuous positive: a GLOBAL asset security_id under service_role PASSES (guards an
--            over-broad fence that blocked legit global positions).
--   (a2)  -> non-vacuous positive: an account-tenant-OWNED asset under service_role PASSES (the
--            matched-tenant disjunct; guards a fence that blocked legit owned positions).
--   (a3)  -> LOAD-BEARING: RED if the fence relied on RLS instead of the explicit account-JOIN
--            predicate — under service_role (RLS bypassed) a cross-tenant security would COMMIT into
--            another tenant's holdings. THE sole assertion that isolates the TRIGGER. This is the D3 #11 proof.
--   (a4)  -> nullable-unresolved path: a NULL security_id (unresolved provider symbol) LANDS (fence
--            WHEN-guard skips) → the position is stored unvalued until the worker resolves it. RED if
--            the fence fired on NULL (it must not) or the column were made NOT NULL.
--   (b1)  -> RED if an authenticated INSERT grant were opened on holdings_checkpoint (the append-only
--            provider write path must be service_role-only; ACL denial before RLS/fence).
--   (d1)/(d2) -> ACL posture: service_role HOLDS INSERT (the provider path is live — a1..a4 are not a
--            vacuously-absent grant); authenticated holds NO INSERT.
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 2. Decision-3 family 7 → 8 — this REALIZES canonical
--   instance #11 (holdings_checkpoint.security_id → pfin.asset, novel global-OR-matched-tenant, Pattern-2
--   site 3; the 020/021 labels #8/#9/#10 are UNCHANGED per the 019 header numbering note). This battery
--   is the pgTAP proof that the fence catches a REAL cross-tenant violation, incl. under service_role.
--   Sec numbering sign-off at joint-review (#10) — if the fence shape changes, this leg realigns.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants; NO PII / real account numbers / prod
--   data. A owns acct-A, B owns acct-B (003 creator-grant). g_asset = GLOBAL equity (users_id NULL);
--   a_asset OWNED by A, b_asset OWNED by B (users_id EXPLICIT — auth.uid() NULL under postgres). The
--   fence's subquery reads pfin.asset + pfin.account under INVOKER, so service_role needs SELECT on
--   BOTH — granted IN-TEST (rolled back) so the TRIGGER, not a missing ACL, is the isolated gate (the
--   017 lesson: a missing SELECT would 42501 'permission denied for table asset', a false-RED). All in
--   a rolled-back txn.
--
-- ⟦WIRE-VALIDATE⟧ authored + smoke-verified GREEN against the 001→019 landed stack (transient
--   apply+rollback) 2026-07-15. CI pg_prove directory-mode after Backend's apply is the green gate. plan(7).
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

select plan(7);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres — RLS-bypassed seed path).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-A', 'investment', 'household', 'taxable') returning account_id as accta \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'acct-B', 'investment', 'household', 'taxable') returning account_id as acctb \gset

insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'HCGLOB', 'HC Global Equity') returning asset_id as g_asset \gset
insert into pfin.asset (users_id, asset_type, pricing_source, name)
  values (:'ta', 'collectible', 'manual_valuation', 'A owned') returning asset_id as a_asset \gset
insert into pfin.asset (users_id, asset_type, pricing_source, name)
  values (:'tb', 'collectible', 'manual_valuation', 'B owned') returning asset_id as b_asset \gset

-- Hold the ACLs the fence subquery needs OPEN to service_role (rolled back) so the TRIGGER — not a
-- missing grant — is the sole gate. SELECT on asset+account = the fence read path; INSERT on
-- holdings_checkpoint already from 018 (harmless dup).
grant usage on schema pfin to service_role;
grant select on pfin.asset to service_role;
grant select on pfin.account to service_role;
grant insert on pfin.holdings_checkpoint to service_role;

-- =====================================================================
-- LEG (a) — the fence under service_role (the real provider-sync write path; RLS bypassed).
-- =====================================================================
select set_config('role', 'service_role', true);

-- (a1) GLOBAL asset → PASS (the fence's `asset.users_id IS NULL` disjunct).
select lives_ok(
  format($$ insert into pfin.holdings_checkpoint (account_id, security_id, symbol, as_of_date, quantity, balance)
              values (%s, %s, 'HCGLOB', '2026-01-31', 10, 1500) $$, :accta, :g_asset),
  '(a1) fence PASS (global): service_role inserts a holdings_checkpoint referencing a GLOBAL asset (users_id NULL) into acct-A — allowed by the global disjunct'
);
-- (a2) matched-tenant (A-owned asset into A's account) → PASS.
select lives_ok(
  format($$ insert into pfin.holdings_checkpoint (account_id, security_id, symbol, as_of_date, quantity, balance)
              values (%s, %s, 'AOWN', '2026-01-31', 5, 500) $$, :accta, :a_asset),
  '(a2) fence PASS (matched): service_role inserts an A-OWNED asset (asset.users_id = account.users_id) into acct-A — allowed by the matched-tenant disjunct'
);
-- (a3) LOAD-BEARING cross-tenant RAISE: B-owned asset into A's account under service_role. RLS is
--      BYPASSED so B's asset IS visible to the subquery; only the account-JOIN predicate rejects it.
select throws_like(
  format($$ insert into pfin.holdings_checkpoint (account_id, security_id, symbol, as_of_date, quantity, balance)
              values (%s, %s, 'XTEN', '2026-01-31', 1, 1) $$, :accta, :b_asset),
  'cross-tenant security rejected%',
  '(a3) LOAD-BEARING fence RAISE under service_role: inserting B''s asset into A''s account STILL RAISES (RLS bypassed — B''s asset IS visible; the explicit account-JOIN predicate, NOT RLS, is the sole gate on the provider-sync path). THE Decision-3 #11 proof'
);
-- (a4) NULL security_id → fence WHEN-guard skips → the unresolved-symbol position LANDS.
select lives_ok(
  format($$ insert into pfin.holdings_checkpoint (account_id, security_id, symbol, as_of_date, quantity, balance)
              values (%s, NULL, NULL, '2026-05-01', 3, 100) $$, :accta),
  '(a4) nullable-unresolved path: a NULL security_id (unresolved provider symbol) LANDS (fence WHEN (security_id IS NOT NULL) skips) — the position is stored unvalued until the worker resolves it'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (b) — authenticated CANNOT reach the table (append-only provider write path is service_role-only).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (b1) authenticated A INSERT into holdings_checkpoint fails closed at the table ACL (no INSERT grant).
select throws_like(
  format($$ insert into pfin.holdings_checkpoint (account_id, security_id, symbol, as_of_date, quantity, balance)
              values (%s, %s, 'HCGLOB', '2026-07-01', 1, 1) $$, :accta, :g_asset),
  'permission denied for table holdings_checkpoint',
  '(b1) authenticated INSERT fails closed: A INSERT into holdings_checkpoint denied at the table ACL (018 SELECT-only grant; the append-only provider write path is service_role-only — even a valid global asset cannot be inserted by authenticated)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (d) — ACL posture (role-agnostic facts, run as postgres).
-- =====================================================================
-- (d1) service_role HOLDS INSERT (the provider-sync write path is live — a1..a4 are not vacuous).
select ok(
  has_table_privilege('service_role', 'pfin.holdings_checkpoint', 'INSERT'),
  '(d1) ACL positive: service_role HOLDS INSERT on pfin.holdings_checkpoint (018 provider-sync grant is live — the fence-PASS legs prove a working path, not an absent one)'
);
-- (d2) authenticated holds NO INSERT (write path is service_role-only).
select ok(
  not has_table_privilege('authenticated', 'pfin.holdings_checkpoint', 'INSERT'),
  '(d2) least-privilege: authenticated holds NO INSERT on pfin.holdings_checkpoint (SELECT-only; the append-only provider write path is service_role-only — RED if an authenticated INSERT grant were added)'
);

select * from finish();
rollback;

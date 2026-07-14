-- =====================================================================
-- Per-Wave battery — pfin provider snapshot write-paths (018 / ADR-027)
--   (A) holdings_checkpoint (005) provider-write-path activation:
--         symbol NOT NULL → nullable · service_role SELECT+INSERT grant ·
--         holdings_checkpoint_latest view (security_invoker = true, merge-block #2)
--   (B) NEW pfin.account_balance_checkpoint — the §7 cash analog (merge-block #8):
--         append-only immutability triple-fence · rd_access-JOIN SELECT RLS ·
--         NaN CHECK · service_role SELECT+INSERT-only · unique(account_id,as_of_date,source)
--   V1-SHIP-BLOCK — Sec joint-review GREEN; this two-tenant C6 battery is the
--   remaining merge-gate for BOTH new service_role write grants (C6 exposure-gate / ADR-023).
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/018_provider_snapshots.sql
--   - pfin.holdings_checkpoint (005 ALTER): symbol nullable + GRANT select,insert to
--       service_role; 005 immutability triple-fence + authenticated SELECT-only + rd_access-
--       JOIN SELECT policy UNCHANGED. Shared fn_reconciliation_family_block_mutation/
--       _block_truncate raises 'pfin.holdings_checkpoint is immutable%<OP> blocked%'.
--   - pfin.holdings_checkpoint_latest — VIEW with (security_invoker = true); SELECT to
--       authenticated; DISTINCT ON (account_id, symbol) latest-by (as_of_date desc,
--       checkpoint_id desc). Inherits the CALLER's RLS (the load-bearing leg (5)).
--   - pfin.account_balance_checkpoint — NEW append-only cash-balance snapshot. SOLE tenant
--       anchor account_id (NO own users_id; scope via account_users rd_access-JOIN, mirrors
--       005/006). CHECK account_balance_checkpoint_balance_finite (balance <> 'NaN').
--       unique(account_id, as_of_date, source). RLS SELECT rd_access-JOIN; NO write policy.
--       GRANT select to authenticated (RLS-gated) + select,insert to service_role.
--   - pfin.fn_account_balance_checkpoint_block_mutation()  BEFORE UPDATE OR DELETE (row);
--       raises 'pfin.account_balance_checkpoint is immutable%<OP> blocked%'. INVOKER.
--   - pfin.fn_account_balance_checkpoint_block_truncate()  BEFORE TRUNCATE (statement);
--       raises 'pfin.account_balance_checkpoint is immutable%TRUNCATE blocked%'. INVOKER.
--   - revoke truncate on pfin.account_balance_checkpoint from public.
-- Reuses the 004/005/017 idiom: \ir verbs, ALL-LOWERCASE \gset literals (005 case-fold
--   lesson), message/constraint-name-precise throws_like (004 all-42501 / all-23514 false-
--   green lesson), role restored to postgres between blocks (PR #121 _rls-USAGE root-cause).
--
-- ┌─ SEC'S 6-ASSERTION CONTRACT → ASSERTION MAP (plan(16)) ──────────────────────────────┐
-- │ (1) append-only UNDER service_role — BOTH tables (UPD/DEL/TRUNCATE raise) → 1a…1f (6) │
-- │ (2) cross-tenant read fail-closed on account_balance_checkpoint (B=0, A=own) → 2a,2b  │
-- │ (3) null-symbol holdings INSERT under service_role SUCCEEDS (relax proof)     → 3     │
-- │ (4) NaN balance rejected (constraint-name-precise)                            → 4     │
-- │ (5) security_invoker view scoping cross-tenant fail-closed THROUGH the view   → 5a,5b │
-- │ (6) authenticated INSERT fail-closed — BOTH tables + service_role control     → 6a…6d │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ THE LOAD-BEARING LEGS (why service_role, not authenticated) ────────────────────────┐
-- │ (1) APPEND-ONLY under service_role. service_role BYPASSES RLS but NOT triggers. The    │
-- │   005/018 immutability fences are the SOLE gate on the privileged provider-sync write  │
-- │   path — RLS/grant alone would NOT stop an RLS-bypassing UPDATE/DELETE/TRUNCATE; only   │
-- │   the trigger does. So all 6 mutation legs run UNDER service_role, with the UPDATE/     │
-- │   DELETE/TRUNCATE ACLs held OPEN in-test (rolled back) so a MISSING grant can never     │
-- │   produce a false-RED 42501 in place of the real fence raise (the 017 lesson): with the │
-- │   grant open, a REMOVED trigger → the mutation SUCCEEDS → RED. That is the load-bearing  │
-- │   property. (Without the in-test TRUNCATE grant the raise would be 'permission denied…', │
-- │   NOT the immutable message — a false-RED under message-precise matching. 017 lesson.)  │
-- │ (5) SECURITY_INVOKER VIEW. holdings_checkpoint_latest is security_invoker = true, so a  │
-- │   read runs under the CALLER's RLS. Tenant B holds its OWN holdings row, so if the view  │
-- │   were owner/definer-semantics B would see A's rows too → (5a) count>0 → RED. (5a) is    │
-- │   RED iff the view is NOT security_invoker. (5b) is the non-vacuous positive.            │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ WHY EACH REJECTION MATCHES A DIFFERENT SIGNAL (no fence passes for another) ─────────┐
-- │  • account_balance_checkpoint UPDATE/DELETE  -> 'pfin.account_balance_checkpoint is    │
-- │                                                  immutable%<OP> blocked%' (row trigger) │
-- │  • account_balance_checkpoint TRUNCATE       -> '…is immutable%TRUNCATE blocked%'       │
-- │  • holdings_checkpoint UPDATE/DELETE          -> 'pfin.holdings_checkpoint is           │
-- │                                                  immutable%<OP> blocked%' (005 shared)   │
-- │  • holdings_checkpoint TRUNCATE              -> '…is immutable%TRUNCATE blocked%'        │
-- │  • balance = NaN                             -> CHECK account_balance_checkpoint_balance_finite│
-- │  • authenticated INSERT (no grant)          -> 'permission denied for table <t>' (ACL)  │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (1a…1f) -> RED if the respective immutability trigger were removed: an RLS-bypassing
--             service_role UPDATE/DELETE would mutate, or a TRUNCATE would WIPE the append-
--             only ledger. THE load-bearing append-only proof (RLS/grant alone miss it).
--   (2a)     -> RED if the account_balance_checkpoint rd_access-JOIN SELECT policy were
--             dropped/widened: B would see A's cash balances.
--   (2b)     -> non-vacuous positive: RED if the policy were over-restrictive (A sees 0).
--   (3)      -> RED if the 018 symbol-NOT-NULL relax were reverted: a null-symbol provider
--             snapshot INSERT would 23502 not-null-violation instead of landing.
--   (4)      -> RED if the balance_finite CHECK were dropped: a NaN would poison SUM/NAV and
--             can never be UPDATEd out of the immutable ledger.
--   (5a)     -> RED if holdings_checkpoint_latest were NOT security_invoker: an owner/definer
--             view leaks EVERY tenant's positions to any authenticated reader through the view.
--   (5b)     -> non-vacuous positive: A sees its own latest row through the view.
--   (6a)/(6b)-> RED if an authenticated INSERT grant were opened on either table absent a
--             write policy (append-only write path must be service_role-only).
--   (6c)/(6d)-> non-vacuous controls: service_role INSERT of a valid own row into BOTH tables
--             SUCCEEDS — proves the C6-gated grants WORK (a green (6a)/(6b) is not a broken grant).
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 2 (RT-22 + RT-26; 018 introduces ZERO catalogued
--   §10 instances — the two service_role grants are DB-LAYER ACLs, not the RT-26 code-layer
--   allowlist surface). Decision-3 family UNCHANGED at 7 (every FK-shaped column in 018 is a
--   SOLE tenant anchor — account_id resolves tenancy via the account_users JOIN, no second
--   anchor to mismatch; NOT a matched-tenant instance). This battery adds no ledger change.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b(); NO
--   PII / NO real account numbers / NO prod data. A owns acct-A; B owns acct-B (both via the
--   003 creator-grant trigger → account_users rd=t/wr=t). Snapshot rows are seeded PRIVILEGED
--   (postgres — RLS-bypassed; INSERT is unblocked, only UPDATE/DELETE/TRUNCATE are fenced).
--   All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so NO
--   `_rls.*` call runs under authenticated. Tenant UUIDs + account/row ids are resolved to
--   psql LITERALS via \gset at role=postgres; every _rls.set_tenant is called at role=postgres
--   and each block restores role=postgres before the next. \gset var names are ALL-LOWERCASE.
--   account_balance_checkpoint / holdings_checkpoint have NO users_id column (rd_access-JOIN
--   tenancy), so cross-tenant reads use manual is(count where account_id=…) — NOT the
--   _rls.expect_cross_tenant_read_empty verb (which assumes a users_id column).
--
-- ⟦WIRE-VALIDATE⟧ (mirrors 005/017): the (1a…1f) service_role legs depend on `service_role`
--   (i) existing in the test stack, (ii) holding BYPASSRLS, (iii) being able to run pgTAP fns.
--   UPDATE/DELETE/TRUNCATE on BOTH snapshot tables are granted to service_role IN-TEST (rolled
--   back) so the TRIGGER — not a missing grant — is the sole gate (the 005/017 "hold the ACL
--   open" pattern; a missing grant would 42501, a false-RED under message-precise matching).
--   Local stack sits at 017 — `supabase test db` cannot reach 018 until Backend applies it;
--   RED-until-018-applied is expected. CI (pg_prove directory-mode) after Backend's apply is
--   the green gate. plan(16).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(16);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed; append-only INSERT is unblocked).
--  - A owns acct-A, B owns acct-B (003 creator-grant trigger seeds rd=t/wr=t on each,
--    keyed on new.users_id — this is what the rd_access-JOIN SELECT policies key on).
--  - holdings_checkpoint: one row per account (A=AAPL, B=MSFT) — the cross-tenant + view
--    scoping targets.
--  - account_balance_checkpoint: one row per account (A + B) — the cross-tenant read targets
--    + the append-only mutation target (A's row).
--  - service_role ACLs (UPDATE/DELETE/TRUNCATE on both tables) held OPEN in-test (rolled
--    back) so the immutability TRIGGERS — not a missing grant — are the sole gate on (1a…1f).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-A', 'investment', 'household', 'taxable')
  returning account_id as accta \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'acct-B', 'investment', 'household', 'taxable')
  returning account_id as acctb \gset

-- holdings_checkpoint: A=AAPL, B=MSFT (view scoping + append-only mutation target).
insert into pfin.holdings_checkpoint (account_id, symbol, as_of_date, quantity, balance)
  values (:accta, 'AAPL', '2026-01-31', 10, 1500)
  returning checkpoint_id as hcpa \gset
insert into pfin.holdings_checkpoint (account_id, symbol, as_of_date, quantity, balance)
  values (:acctb, 'MSFT', '2026-01-31', 20, 3000);

-- account_balance_checkpoint: A + B cash-balance snapshots (cross-tenant read + mutation target).
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:accta, 12345.6700, 'USD', '2026-01-31', 'seed')
  returning balance_id as bala \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:acctb, 98765.4300, 'USD', '2026-01-31', 'seed');

-- Hold the mutation ACLs OPEN to service_role (test setup, rolled back) so the immutability
-- TRIGGERS are the sole gate on (1a…1f). SELECT+INSERT already come from 018 (harmless dup).
grant usage on schema pfin to service_role;
grant select, insert, update, delete, truncate on pfin.account_balance_checkpoint to service_role;
grant select, insert, update, delete, truncate on pfin.holdings_checkpoint        to service_role;

-- =====================================================================
-- [READS FIRST] — cross-tenant fail-closed + owner-can-read, BEFORE any row-adding write,
--   so owner/cross-tenant counts are deterministic.
-- =====================================================================
-- Contract (2) + (5): cross-tenant B, then owner A. account_*_checkpoint carry NO users_id
--   (rd_access-JOIN tenancy) → manual is(count where account_id=…).
select _rls.set_tenant(:'tb'::uuid);
-- (2a) cross-tenant read fails closed: B sees 0 of A's cash-balance rows (rd_access-JOIN).
select is(
  (select count(*) from pfin.account_balance_checkpoint where account_id = :accta)::bigint, 0::bigint,
  '(2a) cross-tenant read fails closed: authenticated B sees 0 of A''s account_balance_checkpoint rows (rd_access-JOIN SELECT policy)'
);
-- (5a) LOAD-BEARING security_invoker: B reads the LATEST VIEW → 0 of A's rows. B holds its
--      OWN holdings row, so a NON-invoker (owner/definer) view would leak A's rows here → RED.
select is(
  (select count(*) from pfin.holdings_checkpoint_latest where account_id = :accta)::bigint, 0::bigint,
  '(5a) security_invoker view cross-tenant fail-closed: authenticated B reads holdings_checkpoint_latest → 0 of A''s rows (the view inherits the CALLER''s RLS; RED iff the view were NOT security_invoker — B holds its own row so a definer view would leak A''s)'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'ta'::uuid);
-- (2b) non-vacuous positive: A reads exactly its 1 own cash-balance row (not over-restrictive).
select is(
  (select count(*) from pfin.account_balance_checkpoint where account_id = :accta)::bigint, 1::bigint,
  '(2b) owner reads own: authenticated A reads exactly its 1 account_balance_checkpoint row (rd_access-JOIN; fail-closed both directions)'
);
-- (5b) non-vacuous positive: A reads its own latest row THROUGH the view.
select is(
  (select count(*) from pfin.holdings_checkpoint_latest where account_id = :accta)::bigint, 1::bigint,
  '(5b) security_invoker view owner-read: authenticated A reads its own latest holdings row through holdings_checkpoint_latest (1 row; DISTINCT ON per account/symbol)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- [APPEND-ONLY UNDER service_role] — Contract (1): BOTH tables, UPDATE/DELETE/TRUNCATE raise.
--   service_role BYPASSES RLS but NOT triggers → the TRIGGER is the SOLE gate (load-bearing).
--   Mutation ACLs held OPEN above so a missing grant can't false-RED (017 lesson).
-- =====================================================================
select set_config('role', 'service_role', true);

-- (1a) account_balance_checkpoint UPDATE blocked by the row-level immutability trigger.
select throws_like(
  format($$ update pfin.account_balance_checkpoint set balance = 0 where balance_id = %s $$, :bala),
  'pfin.account_balance_checkpoint is immutable%UPDATE blocked%',
  '(1a) append-only UNDER service_role: account_balance_checkpoint UPDATE blocked by the immutability TRIGGER (RLS-bypass does NOT bypass the trigger — the load-bearing append-only fence)'
);
-- (1b) account_balance_checkpoint DELETE blocked.
select throws_like(
  format($$ delete from pfin.account_balance_checkpoint where balance_id = %s $$, :bala),
  'pfin.account_balance_checkpoint is immutable%DELETE blocked%',
  '(1b) append-only UNDER service_role: account_balance_checkpoint DELETE blocked by the immutability TRIGGER'
);
-- (1c) account_balance_checkpoint TRUNCATE blocked by the statement-level trigger (in-test
--      TRUNCATE grant held open → the trigger, not the REVOKE, is the isolated gate).
select throws_like(
  $$ truncate pfin.account_balance_checkpoint $$,
  'pfin.account_balance_checkpoint is immutable%TRUNCATE blocked%',
  '(1c) append-only UNDER service_role: account_balance_checkpoint TRUNCATE blocked by the statement-level trigger (audit-wipe path fenced; distinct message from the row-level fence)'
);
-- (1d) holdings_checkpoint UPDATE blocked by the 005 shared immutability trigger.
select throws_like(
  format($$ update pfin.holdings_checkpoint set as_of_date = '2026-02-01' where checkpoint_id = %s $$, :hcpa),
  'pfin.holdings_checkpoint is immutable%UPDATE blocked%',
  '(1d) append-only UNDER service_role: holdings_checkpoint UPDATE blocked by the 005 immutability TRIGGER (the 018 service_role INSERT grant does NOT open a mutation path)'
);
-- (1e) holdings_checkpoint DELETE blocked.
select throws_like(
  format($$ delete from pfin.holdings_checkpoint where checkpoint_id = %s $$, :hcpa),
  'pfin.holdings_checkpoint is immutable%DELETE blocked%',
  '(1e) append-only UNDER service_role: holdings_checkpoint DELETE blocked by the 005 immutability TRIGGER'
);
-- (1f) holdings_checkpoint TRUNCATE blocked by the 005 statement-level trigger.
select throws_like(
  $$ truncate pfin.holdings_checkpoint $$,
  'pfin.holdings_checkpoint is immutable%TRUNCATE blocked%',
  '(1f) append-only UNDER service_role: holdings_checkpoint TRUNCATE blocked by the 005 statement-level trigger'
);

-- =====================================================================
-- [service_role POSITIVE CONTROLS] — Contract (3) + (6c) + (6d) + (4). Still under service_role.
--   These prove the C6-gated grants WORK (non-vacuous) + the symbol relax + the NaN fence.
-- =====================================================================
-- (3) null-symbol holdings INSERT under service_role SUCCEEDS (the 018 relax; pre-018 this
--     would 23502 not-null-violation). Proves provider position/sweep snapshots can land.
select lives_ok(
  format($$ insert into pfin.holdings_checkpoint (account_id, symbol, as_of_date, quantity, balance)
              values (%s, NULL, '2026-05-01', 3, 100) $$, :accta),
  '(3) symbol relax: service_role INSERT of a holdings_checkpoint row with symbol = NULL SUCCEEDS (018 dropped the 005 NOT NULL; pre-018 this would be a not-null violation)'
);
-- (6d) non-vacuous control: service_role INSERT of a VALID (non-null) holdings row SUCCEEDS —
--      proves the 018 service_role INSERT grant works (a green (6b) is not a broken grant).
select lives_ok(
  format($$ insert into pfin.holdings_checkpoint (account_id, symbol, as_of_date, quantity, balance)
              values (%s, 'GOOG', '2026-05-02', 2, 50) $$, :accta),
  '(6d) grant-works control: service_role INSERT of a valid holdings_checkpoint row SUCCEEDS (the 018 SELECT+INSERT grant is live)'
);
-- (6c) non-vacuous control: service_role INSERT of a valid own account_balance row SUCCEEDS.
select lives_ok(
  format($$ insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
              values (%s, 1234.5600, 'USD', '2026-05-01', 'svc-ctl') $$, :accta),
  '(6c) grant-works control: service_role INSERT of a valid account_balance_checkpoint row SUCCEEDS (the 018 SELECT+INSERT grant is live; append-only holds even with INSERT granted)'
);
-- (4) NaN balance REJECTED by the CHECK (constraint-name-precise; role-agnostic — service_role
--     bypasses RLS but NOT the CHECK). Isolated on a distinct (as_of_date, source) so the
--     unique constraint cannot fire first.
select throws_like(
  format($$ insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
              values (%s, 'NaN'::numeric, 'USD', '2026-06-01', 'nan-src') $$, :accta),
  '%account_balance_checkpoint_balance_finite%',
  '(4) NaN fence: balance = NaN is REJECTED by the account_balance_checkpoint_balance_finite CHECK (constraint-name-precise; role-agnostic — a NaN would poison SUM/NAV and can never be UPDATEd out of the immutable ledger)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- [AUTHENTICATED INSERT FAIL-CLOSED] — Contract (6a) + (6b): BOTH tables. authenticated holds
--   SELECT only (no INSERT grant, no write policy) → ACL denial before RLS is consulted
--   (the PR #106 grant-then-RLS ordering; append-only write path is service_role-only).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (6a) authenticated A INSERT into account_balance_checkpoint fails closed at the table ACL.
select throws_like(
  format($$ insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
              values (%s, 500, 'USD', '2026-07-01', 'auth-x') $$, :accta),
  'permission denied for table account_balance_checkpoint',
  '(6a) authenticated INSERT fails closed: A INSERT into account_balance_checkpoint denied at the table ACL (SELECT-only grant; no write policy — service_role is the sole writer)'
);
-- (6b) authenticated A INSERT into holdings_checkpoint fails closed at the table ACL.
select throws_like(
  format($$ insert into pfin.holdings_checkpoint (account_id, symbol, as_of_date, quantity, balance)
              values (%s, 'XYZ', '2026-07-01', 1, 1) $$, :accta),
  'permission denied for table holdings_checkpoint',
  '(6b) authenticated INSERT fails closed: A INSERT into holdings_checkpoint denied at the table ACL (005 authenticated SELECT-only grant unchanged by 018)'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;

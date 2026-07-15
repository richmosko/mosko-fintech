-- =====================================================================
-- Per-Wave battery — pfin.eod_price HYBRID RLS + the C6 write-authz fence
--   + account_balance_checkpoint_latest security_invoker isolation
--   + fn_holdings_as_of INVOKER cross-tenant scope
--   (ADR-027 / 019 — THE C6 MERGE-GATE per ADR-023 / SECURITY §4.5; V1-SHIP-BLOCK)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/019_eod_price_and_valuation.sql
--   - pfin.eod_price (valuation-per-date registry). SOLE tenant anchor asset_id (tenancy via
--       the asset-JOIN read RLS; NO own users_id). HYBRID RLS:
--         SELECT: asset global (users_id IS NULL) OR owned by caller  -- shared globals + own manuals
--         INSERT: source='manual_valuation' AND asset owned by caller (WITH CHECK)
--         UPDATE: same, USING + WITH CHECK (post-image re-validated → no asset_id re-point escape)
--         DELETE: same, USING
--       GRANT authenticated SELECT/INSERT/UPDATE/DELETE (RLS/policy-gated to manual-owned);
--       service_role SELECT/INSERT/UPDATE (global market/spot/fx writer; NO DELETE — least priv).
--       CHECK eod_price_price_finite (price <> 'NaN', 014 idiom).
--   - pfin.account_balance_checkpoint_latest — VIEW with (security_invoker = true) (merge-block
--       #2/#8; the 018 forward-flag). DISTINCT ON (account_id, source) latest by (as_of_date desc,
--       balance_id desc). Inherits the CALLER's RLS; SELECT to authenticated.
--   - pfin.fn_holdings_as_of(date) RETURNS TABLE(account_id, asset_id, quantity) — the roll-forward
--       read; return col is `asset_id` (bound to #9's landed 019 — NOT `security_id`). SECURITY
--       INVOKER; RLS-scoped via holdings_checkpoint + account_trans rd_access-JOIN. EXECUTE to authenticated.
--   - pfin.fn_compute_nav(date) — UNIFORM ROLL-FORWARD valuation; its CORRECTNESS fixture lives in
--       the sibling file rls/019_fn_compute_nav_roll_forward.sql (functional, scenario-tenant
--       isolated). THIS file is the security merge-gate (isolation + write-authz).
-- Prereqs exercised (already on main / applied by Backend): 001 (pfin schema + fn_refresh_updated_at),
--   003 (pfin.account direct-owner RLS + the DEFINER creator-grant trigger the rd_access-JOIN reads),
--   006 (account_trans rd_access-JOIN RLS + GRANT), 016 (pfin.asset hybrid registry + global currency
--   seed + the 017 security_id fence's global disjunct), 017 (account_trans.security_id + fence),
--   018 (account_balance_checkpoint base table + rd_access-JOIN SELECT RLS + GRANT).
-- Reuses the SELF-187/016/017/018 idiom: \ir verbs, ALL-LOWERCASE \gset literals (005 case-fold
--   lesson), SQLSTATE-precise throws_ok (004 all-42501 false-green lesson) + CONSTRAINT-NAME-precise
--   throws_like (finite CHECK), role restored to postgres between blocks (PR #121 _rls-USAGE root-cause).
--
-- ┌─ WHY THIS IS A HYBRID + WRITE-AUTHZ BATTERY, NOT VANILLA ISOLATION ────────────────────┐
-- │ eod_price mirrors 016's hybrid: GLOBAL rows (market/fx, asset users_id NULL) BOTH tenants │
-- │ read but NEITHER may write; PER-USER manual valuations (asset owned) are owner-private +   │
-- │ owner-writable. Vanilla "B sees 0 of A" is NECESSARY (a3) but INSUFFICIENT. The load-       │
-- │ bearing write-authz legs vanilla misses:                                                    │
-- │   (c1) NO-MARKET-WRITE — authenticated cannot write a market/spot/fx row AT ALL (source pin) │
-- │        even on its OWN asset. RED if the source-pin were dropped: a user could forge a fake  │
-- │        global market price that feeds every reader's NAV.                                    │
-- │   (c2) NO-GLOBAL-FORGE — B cannot write a manual_valuation on a GLOBAL asset (users_id NULL  │
-- │        ≠ auth.uid()). RED if the own-asset predicate were widened to permit NULL-owner assets.│
-- │   (c3) NO-CROSS-TENANT-WRITE — B cannot write a manual_valuation on A's asset.               │
-- │   (e1/e2) NO-REPOINT-ESCAPE — the UPDATE WITH CHECK re-validates the POST-image, so A cannot  │
-- │        re-point its own manual row's asset_id to a global/other-tenant asset (the classic     │
-- │        mutable-row escape). RED if UPDATE had USING but no WITH CHECK.                        │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ WHY EACH REJECTION MATCHES A DIFFERENT SIGNAL (no fence passes for another) ─────────────┐
-- │  • cross-tenant PER-USER read (B on A's manual)  -> RLS SELECT filters -> 0 rows (is, not throw)│
-- │  • forge-market / forge-global / cross-tenant     -> RLS WITH CHECK -> 42501 (throws_ok)        │
-- │    INSERT + re-point UPDATE                                                                     │
-- │  • cross-tenant UPDATE|DELETE of A's manual        -> RLS USING excludes -> 0 rows AFFECTED;     │
-- │       asserted as target-row UNCHANGED / STILL-PRESENT on a privileged re-read (silent filter,  │
-- │       distinct from a 42501)                                                                    │
-- │  • price = NaN                                     -> CHECK eod_price_price_finite (name-precise)│
-- │ SQLSTATE-precise (42501 forge) + behavioral 0-row (silent RLS filter) + constraint-name         │
-- │ (finite CHECK) keeps one fence from ever passing for another (the 004 discipline).              │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (a1)         -> non-vacuous positive: owner A reads its own 2 manual-valuation rows (guards an
--                    over-restrictive read that also hid the owner's own rows).
--   (a2)/(a4)    -> HYBRID load-bearing: RED if the SELECT `asset users_id IS NULL` disjunct were
--                    dropped -> shared global market prices vanish for BOTH tenants (a vanilla
--                    isolation battery would stay green — the leg only a hybrid battery guards).
--   (a3)         -> RED if the asset-JOIN read policy leaked per-user rows -> B reads A's private
--                    manual valuations (the core cross-tenant read fence).
--   (a5)         -> non-vacuous positive: owner B reads its own manual valuation.
--   (c1)         -> LOAD-BEARING: RED if the source-pin were dropped -> a user forges a fake global
--                    market price feeding every reader's NAV (writes market_feed on its OWN asset).
--   (c2)         -> LOAD-BEARING: RED if the own-asset predicate permitted NULL-owner assets ->
--                    a user plants a manual valuation onto a shared global asset.
--   (c3)         -> RED if the own-asset predicate were widened -> B writes a manual valuation onto
--                    A's private asset (cross-tenant write).
--   (c5)         -> non-vacuous control: B writes a manual_valuation on its OWN asset -> ACCEPTED
--                    (proves (c1)/(c2)/(c3) are source/owner-mismatch-driven, not a blanket block).
--   (d3)         -> DELETE source-pin: RED if the DELETE USING were widened to permit market/global
--                    rows -> authenticated could delete a shared market price (symmetric with c1's
--                    no-market-INSERT). The global market row must survive B's DELETE.
--   (d1)/(d2)    -> RED if the UPDATE/DELETE USING were widened -> B mutates/deletes A's manual
--                    valuation. Asserted as A's price UNCHANGED / row STILL-PRESENT.
--   (e1)/(e2)    -> LOAD-BEARING: RED if UPDATE lacked WITH CHECK -> A re-points its own manual row's
--                    asset_id to a GLOBAL / B's asset (escapes the fence into the shared registry / a
--                    foreign tenant). The post-image re-validation is the sole gate.
--   (e3)/(e4)    -> non-vacuous positives: A UPDATEs + DELETEs its OWN manual valuation (guards an
--                    over-restrictive USING that blocked even the legitimate owner write path).
--   (f1)         -> RED if the price-finite CHECK were dropped -> a NaN poisons every fn_compute_nav
--                    SUM (role-agnostic; service_role bypasses RLS but NOT the CHECK).
--   (g1)         -> non-vacuous C6 control: service_role INSERT of a GLOBAL market row SUCCEEDS ->
--                    proves the C6-gated service_role grant WORKS (a green write-fence is not a
--                    vacuously-absent grant).
--   (h1)         -> non-vacuous ACL positive: authenticated HOLDS INSERT (active V1 manual-valuation
--                    write path; grant not vacuously absent).
--   (h2)/(h3)    -> service_role posture: HOLDS INSERT (global writer) but NOT DELETE (least priv —
--                    market rows are corrected via upsert, never deleted). RED if DELETE were granted.
--   (h4)         -> anon zero-grant by construction (schema-usage fence + no table grant).
--   (i1)         -> LOAD-BEARING security_invoker: B reads account_balance_checkpoint_latest -> 0 of
--                    A's rows. B holds its OWN balance row, so a NON-invoker (owner/definer) view would
--                    leak A's cash balances here -> RED iff the view were NOT security_invoker.
--   (i2)/(i3)    -> non-vacuous positive: A reads its OWN latest cash balance THROUGH the view; the
--                    DISTINCT ON returns the LATEST (999, not the older 111) — the current-snapshot
--                    contract has teeth.
--   (j1)         -> LOAD-BEARING: RED if fn_holdings_as_of were DEFINER or leaked -> B's call returns
--                    A's holdings. INVOKER + account_trans rd_access-JOIN scopes it to the caller.
--   (j2)/(j3)    -> non-vacuous positive + 3-COL SIGNATURE proof: A's call returns exactly its 1 own
--                    holding row as (account_id, asset_id, quantity) with quantity = 3. RED if the
--                    return signature regressed/renamed (the SELECT of asset_id would error/shift).
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 2 (RT-22 + RT-26; 019 introduces ZERO catalogued §10
--   instances — the eod_price service_role grant is a DB-LAYER ACL, NOT the RT-26 code-layer
--   SERVICE_ROLE_KEY allowlist grep surface; per the 019 header §10 3-axis, Path B). Decision-3 family
--   UNCHANGED at 7: eod_price.asset_id is the SOLE tenant anchor (tenancy via the asset-JOIN read RLS;
--   no second anchor to mismatch), and the write-authz WITH CHECK is a Sec-CLASSIFIED cross-tenant-write
--   gate that does NOT increment the family (019 header PART C / §16). This battery adds no ledger change.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b(); NO PII /
--   NO real account numbers / NO prod data. A owns acct-A + asset a_manual; B owns acct-B + asset
--   b_manual (both via the 003 creator-grant trigger keyed on new.users_id). The GLOBAL market asset
--   g_equity + the seeded eod_price / balance / holdings rows are inserted PRIVILEGED (postgres —
--   RLS-bypassed; INSERT is the only unblocked seed path). Per-user asset/valuation CRUD IS an active
--   V1 authenticated write path, so A/B own-asset rows carry users_id EXPLICITLY (auth.uid() is NULL
--   under postgres, so an omitted users_id would land a GLOBAL row). All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so NO `_rls.*`
--   call runs under authenticated. Tenant UUIDs + asset/account ids are resolved to psql LITERALS via
--   \gset at role=postgres; every _rls.set_tenant is called at role=postgres and each block restores
--   role=postgres before the next. \gset var names are ALL-LOWERCASE. eod_price / balance-checkpoint
--   carry NO own users_id (asset-JOIN / rd_access-JOIN tenancy) → cross-tenant reads use manual
--   is(count where asset_id=… / account_id=…), NOT the _rls.expect_cross_tenant_read_empty verb.
--
-- ⟦WIRE-VALIDATE⟧ authored against 019's firmed contract; the authoritative run is against the
--   001->019 reset stack. The (g1)/(h2)/(h3) service_role legs depend on `service_role` existing +
--   holding its 019 grants. Local stack sits at 018 — `supabase test db` cannot reach 019 until
--   Backend applies it; RED-until-019-applied is EXPECTED. CI (pg_prove directory-mode) after Backend's
--   apply is the green gate. plan(28).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(28);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed seed path).
--  - A owns acct-A + asset a_manual (real_estate, manual_valuation); B owns acct-B + asset b_manual.
--  - g_equity = a GLOBAL market asset (users_id NULL, equity, market_feed) — the shared-read +
--    no-write target + the re-point-escape target + the fn_holdings security_id.
--  - eod_price seed: A has TWO manual valuations on a_manual (2026-01-31 read/update target +
--    2026-02-28 delete target); B has one on b_manual; one GLOBAL market_feed row on g_equity.
--  - account_balance_checkpoint: A has TWO rows (older 111 + newer 999 → DISTINCT ON latest proof);
--    B has one (222). account_trans: A + B each hold one security-leg row on g_equity (fn_holdings).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-A', 'investment', 'household', 'taxable')
  returning account_id as accta \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'acct-B', 'investment', 'household', 'taxable')
  returning account_id as acctb \gset

insert into pfin.asset (users_id, asset_type, pricing_source, name)
  values (:'ta', 'real_estate', 'manual_valuation', 'A House')
  returning asset_id as a_manual \gset
insert into pfin.asset (users_id, asset_type, pricing_source, name)
  values (:'tb', 'real_estate', 'manual_valuation', 'B House')
  returning asset_id as b_manual \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'GLBLX', 'Global Equity X')
  returning asset_id as g_equity \gset

-- eod_price seed (privileged).
insert into pfin.eod_price (asset_id, price_date, source, price)
  values (:a_manual, '2026-01-31', 'manual_valuation', 250000.0000);  -- A read/update target
insert into pfin.eod_price (asset_id, price_date, source, price)
  values (:a_manual, '2026-02-28', 'manual_valuation', 260000.0000);  -- A delete target
insert into pfin.eod_price (asset_id, price_date, source, price)
  values (:b_manual, '2026-01-31', 'manual_valuation', 30000.0000);   -- B own
insert into pfin.eod_price (asset_id, price_date, source, price)
  values (:g_equity, '2026-01-31', 'market_feed', 150.0000);          -- shared global

-- account_balance_checkpoint seed (privileged; append-only INSERT is unblocked).
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:accta, 111.0000, 'USD', '2026-01-31', 'seed');
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:accta, 999.0000, 'USD', '2026-02-28', 'seed');             -- newer → DISTINCT ON latest
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:acctb, 222.0000, 'USD', '2026-01-31', 'seed');

-- account_trans security-leg seed (privileged; 017 fence passes — g_equity is GLOBAL).
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, vendor)
  values (:accta, '2026-03-01', 0, 3, :g_equity, 'a-hold');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, vendor)
  values (:acctb, '2026-03-01', 0, 8, :g_equity, 'b-hold');

-- =====================================================================
-- LEG (a) eod_price HYBRID READ — globals shared by both; per-user manuals owner-private.
--   [READS FIRST], before any write, so counts are deterministic.
-- =====================================================================
-- BLOCK A-READ (authenticated A).
select _rls.set_tenant(:'ta'::uuid);
-- (a1) non-vacuous positive: A reads its 2 own manual valuations on a_manual.
select is(
  (select count(*) from pfin.eod_price where asset_id = :a_manual and source = 'manual_valuation')::bigint, 2::bigint,
  '(a1) owner reads own: authenticated A reads exactly its 2 manual_valuation rows on a_manual (asset-JOIN read scope not over-restrictive)'
);
-- (a2) HYBRID: A reads the shared GLOBAL market row (asset users_id NULL).
select is(
  (select count(*) from pfin.eod_price where asset_id = :g_equity)::bigint, 1::bigint,
  '(a2) HYBRID global-readable: A reads the GLOBAL market_feed row on g_equity (the SELECT `asset users_id IS NULL` disjunct exposes shared market prices)'
);
select set_config('role', 'postgres', true);

-- BLOCK B-READ (authenticated B) — same shared global; zero of A's per-user manuals.
select _rls.set_tenant(:'tb'::uuid);
-- (a3) cross-tenant read fails closed: B sees 0 of A's manual valuations (asset-JOIN read fence).
select is(
  (select count(*) from pfin.eod_price where asset_id = :a_manual)::bigint, 0::bigint,
  '(a3) cross-tenant read fails closed: authenticated B sees 0 of A''s manual_valuation rows on a_manual (asset-JOIN read RLS — a_manual is owned by A, invisible to B)'
);
-- (a4) HYBRID: B reads the SAME shared global row A did (shared, not per-tenant).
select is(
  (select count(*) from pfin.eod_price where asset_id = :g_equity)::bigint, 1::bigint,
  '(a4) HYBRID global-readable: B reads the SAME GLOBAL market_feed row on g_equity (shared reference data — RED if the `users_id IS NULL` disjunct were dropped, which a vanilla isolation battery would miss)'
);
-- (a5) non-vacuous positive: B reads its own manual valuation on b_manual.
select is(
  (select count(*) from pfin.eod_price where asset_id = :b_manual and source = 'manual_valuation')::bigint, 1::bigint,
  '(a5) owner reads own: authenticated B reads its 1 manual_valuation row on b_manual (fail-closed both directions)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (c) eod_price WRITE-AUTHZ (INSERT) — source-pin + own-asset WITH CHECK fence.
-- =====================================================================
-- BLOCK B-WRITE (authenticated B).
select _rls.set_tenant(:'tb'::uuid);
-- (c1) LOAD-BEARING no-market-write: B cannot write a market_feed row even on its OWN asset
--      (source pin excludes non-manual sources → WITH CHECK false → 42501).
select throws_ok(
  format($$ insert into pfin.eod_price (asset_id, price_date, source, price)
              values (%s, '2026-04-01', 'market_feed', 42.0000) $$, :b_manual),
  '42501', null,
  '(c1) LOAD-BEARING no-market-write: B inserting a market_feed row on its OWN asset is REJECTED by WITH CHECK (source pin: authenticated may write ONLY manual_valuation) — a user cannot forge a market price'
);
-- (c2) LOAD-BEARING no-global-forge: B cannot write a manual_valuation on the GLOBAL asset
--      (g_equity users_id NULL ≠ auth.uid() → own-asset predicate false → 42501).
select throws_ok(
  format($$ insert into pfin.eod_price (asset_id, price_date, source, price)
              values (%s, '2026-04-01', 'manual_valuation', 42.0000) $$, :g_equity),
  '42501', null,
  '(c2) LOAD-BEARING no-global-forge: B inserting a manual_valuation on the GLOBAL asset g_equity (users_id NULL) is REJECTED by WITH CHECK (own-asset predicate: NULL ≠ auth.uid()) — cannot plant a valuation onto the shared registry'
);
-- (c3) no-cross-tenant-write: B cannot write a manual_valuation on A's asset a_manual.
select throws_ok(
  format($$ insert into pfin.eod_price (asset_id, price_date, source, price)
              values (%s, '2026-04-01', 'manual_valuation', 42.0000) $$, :a_manual),
  '42501', null,
  '(c3) no-cross-tenant-write: B inserting a manual_valuation on A''s asset a_manual is REJECTED by WITH CHECK (asset.users_id = A ≠ auth.uid()=B) — cannot price another tenant''s asset'
);
-- (c5) non-vacuous control: B writes a manual_valuation on its OWN asset → ACCEPTED.
select lives_ok(
  format($$ insert into pfin.eod_price (asset_id, price_date, source, price)
              values (%s, '2026-04-01', 'manual_valuation', 31000.0000) $$, :b_manual),
  '(c5) control: B inserts a manual_valuation on its OWN asset b_manual → ACCEPTED (proves (c1)/(c2)/(c3) are source/owner-mismatch-driven, not a blanket authenticated-B INSERT block)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (d) eod_price NO CROSS-TENANT MUTATE (UPDATE + DELETE) + NO-GLOBAL/MARKET DELETE — the USING
--   fence. Executed under authenticated B (RLS USING filters the row out → 0 rows AFFECTED, no raise);
--   asserted by a PRIVILEGED re-read that the target survived UNCHANGED.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);
update pfin.eod_price set price = 1.0000 where asset_id = :a_manual and price_date = '2026-01-31'; -- (d1)
delete from pfin.eod_price               where asset_id = :a_manual and price_date = '2026-01-31'; -- (d2)
delete from pfin.eod_price               where asset_id = :g_equity and source = 'market_feed' and price_date = '2026-01-31'; -- (d3)
select set_config('role', 'postgres', true);

-- (d1) cross-tenant UPDATE had NO effect: A's manual valuation price is unchanged.
select is(
  (select price from pfin.eod_price where asset_id = :a_manual and price_date = '2026-01-31'),
  250000.0000::numeric,
  '(d1) no cross-tenant UPDATE: B''s UPDATE of A''s manual valuation affected 0 rows (USING source=manual AND owned excludes it) — A''s price is UNCHANGED (250000)'
);
-- (d2) cross-tenant DELETE had NO effect: A's manual valuation still exists.
select is(
  (select count(*) from pfin.eod_price where asset_id = :a_manual and price_date = '2026-01-31')::bigint, 1::bigint,
  '(d2) no cross-tenant DELETE: B''s DELETE of A''s manual valuation affected 0 rows (USING excludes it) — A''s row still PRESENT'
);
-- (d3) DELETE source-pin: B's DELETE of a GLOBAL market_feed row had NO effect (the DELETE USING
--      requires source=manual_valuation AND owned — both fail for a global market row → 0 rows).
select is(
  (select count(*) from pfin.eod_price where asset_id = :g_equity and source = 'market_feed' and price_date = '2026-01-31')::bigint, 1::bigint,
  '(d3) DELETE source-pin: authenticated B''s DELETE of the GLOBAL market_feed row affected 0 rows (DELETE USING source=manual_valuation AND owned — a market/global row satisfies NEITHER) — the shared market price still PRESENT (symmetric with c1''s no-market-INSERT)'
);

-- =====================================================================
-- LEG (e) eod_price NO-REPOINT-ESCAPE + OWNER CRUD — the UPDATE WITH CHECK post-image fence.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (e1) LOAD-BEARING no-repoint-to-global: A cannot re-point its own manual row's asset_id to the
--      GLOBAL asset (post-image asset not owned by A → WITH CHECK false → 42501).
select throws_ok(
  format($$ update pfin.eod_price set asset_id = %s
              where asset_id = %s and price_date = '2026-01-31' $$, :g_equity, :a_manual),
  '42501', null,
  '(e1) LOAD-BEARING no-repoint-escape: A re-pointing its own manual row''s asset_id to the GLOBAL g_equity is REJECTED by the UPDATE WITH CHECK (post-image asset users_id NULL ≠ auth.uid()) — cannot escape the fence into the shared registry'
);
-- (e2) no-repoint-to-other-tenant: A cannot re-point asset_id to B's asset.
select throws_ok(
  format($$ update pfin.eod_price set asset_id = %s
              where asset_id = %s and price_date = '2026-01-31' $$, :b_manual, :a_manual),
  '42501', null,
  '(e2) no-repoint-escape: A re-pointing its own manual row''s asset_id to B''s asset b_manual is REJECTED by the UPDATE WITH CHECK (post-image asset owned by B ≠ auth.uid()=A)'
);
-- (e3) non-vacuous positive: A UPDATEs its own manual valuation price in place → ACCEPTED.
select lives_ok(
  format($$ update pfin.eod_price set price = 275000.0000
              where asset_id = %s and price_date = '2026-01-31' $$, :a_manual),
  '(e3) owner UPDATE: A edits its OWN manual valuation price in place (USING + WITH CHECK source=manual AND owned) → ACCEPTED (owner write path not over-restrictive; MUTABLE OWD-E)'
);
-- (e4) non-vacuous positive: A DELETEs its own (dedicated 2026-02-28) manual valuation → ACCEPTED.
select lives_ok(
  format($$ delete from pfin.eod_price
              where asset_id = %s and price_date = '2026-02-28' $$, :a_manual),
  '(e4) owner DELETE: A deletes its OWN manual valuation (USING source=manual AND owned) → ACCEPTED (owner delete path works)'
);
-- (f1) NaN price REJECTED by the finite CHECK (constraint-name-precise; role-agnostic value invariant).
select throws_like(
  format($$ insert into pfin.eod_price (asset_id, price_date, source, price)
              values (%s, '2026-05-01', 'manual_valuation', 'NaN'::numeric) $$, :a_manual),
  '%eod_price_price_finite%',
  '(f1) NaN fence: price = NaN is REJECTED by the eod_price_price_finite CHECK (constraint-name-precise; a NaN would poison every fn_compute_nav SUM — role-agnostic, RLS-independent)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (g) service_role GLOBAL WRITE — the C6-gated non-vacuous control (grant WORKS).
-- =====================================================================
-- service_role holds USAGE on pfin (008) + SELECT/INSERT/UPDATE on eod_price (019) — no in-test
-- grant needed; (g1) exercises exactly the shipped 019 grant.
select set_config('role', 'service_role', true);
-- (g1) service_role INSERT of a GLOBAL market row SUCCEEDS (bypasses RLS; the C6-gated writer).
select lives_ok(
  format($$ insert into pfin.eod_price (asset_id, price_date, source, price)
              values (%s, '2026-04-30', 'market_feed', 151.0000) $$, :g_equity),
  '(g1) C6-gated control: service_role INSERT of a GLOBAL market_feed row on g_equity SUCCEEDS (RLS-bypassing global writer; proves the 019 service_role grant is LIVE — a green write-fence is not a vacuously-absent grant)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (h) GRANT posture (ACL facts, run as postgres — role-agnostic).
-- =====================================================================
-- (h1) non-vacuous ACL positive: authenticated HOLDS INSERT (active V1 manual-valuation write path).
select ok(
  has_table_privilege('authenticated', 'pfin.eod_price', 'INSERT'),
  '(h1) ACL positive: authenticated HOLDS INSERT on pfin.eod_price (the active V1 manual-valuation write path; grant not vacuously absent — a 42501 in (c1..c3) is RLS, not a missing grant)'
);
-- (h2) service_role HOLDS INSERT (the global market/spot/fx writer).
select ok(
  has_table_privilege('service_role', 'pfin.eod_price', 'INSERT'),
  '(h2) ACL positive: service_role HOLDS INSERT on pfin.eod_price (the global market/spot/fx writer — the C6-gated grant is live)'
);
-- (h3) service_role does NOT hold DELETE (least privilege — market rows corrected via upsert).
select ok(
  not has_table_privilege('service_role', 'pfin.eod_price', 'DELETE'),
  '(h3) least-privilege: service_role holds NO DELETE on pfin.eod_price (market rows are corrected via upsert, never deleted — RED if a DELETE grant were added)'
);
-- (h4) anon zero-grant by construction.
select ok(
  not has_table_privilege('anon', 'pfin.eod_price', 'SELECT'),
  '(h4) anon zero-grant: anon holds NO SELECT on pfin.eod_price (internet-facing anon fenced at the schema-usage layer + no table grant — by construction)'
);

-- =====================================================================
-- LEG (i) account_balance_checkpoint_latest VIEW — security_invoker isolation + DISTINCT ON latest.
-- =====================================================================
-- (i1) LOAD-BEARING security_invoker: B reads the view → 0 of A's rows. B holds its OWN balance row,
--      so a NON-invoker (owner/definer) view would leak A's cash balances here → RED.
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from pfin.account_balance_checkpoint_latest where account_id = :accta)::bigint, 0::bigint,
  '(i1) security_invoker view cross-tenant fail-closed: authenticated B reads account_balance_checkpoint_latest → 0 of A''s rows (the view inherits the CALLER''s RLS; RED iff NOT security_invoker — B holds its own row so a definer view would leak A''s cash balances)'
);
select set_config('role', 'postgres', true);

-- (i2)/(i3) non-vacuous positive + DISTINCT ON latest: A reads its OWN latest cash balance via the view.
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*) from pfin.account_balance_checkpoint_latest where account_id = :accta)::bigint, 1::bigint,
  '(i2) security_invoker view owner-read: A reads exactly 1 row for acct-A through the view (DISTINCT ON (account_id, source) collapses A''s 2 seeded rows to one current snapshot)'
);
select is(
  (select balance from pfin.account_balance_checkpoint_latest where account_id = :accta),
  999.0000::numeric,
  '(i3) DISTINCT ON latest: the view returns A''s NEWER balance (999 @ 2026-02-28), NOT the older 111 @ 2026-01-31 (ordered by as_of_date desc, balance_id desc) — the current-snapshot contract has teeth'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (j) fn_holdings_as_of — INVOKER cross-tenant scope + the NEW 3-COL signature.
-- =====================================================================
-- (j1) LOAD-BEARING: B's call returns 0 of A's holdings (INVOKER + account_trans rd_access-JOIN).
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from pfin.fn_holdings_as_of('2026-06-30') where account_id = :accta)::bigint, 0::bigint,
  '(j1) fn_holdings_as_of INVOKER cross-tenant fail-closed: B''s call returns 0 rows for A''s account (the function runs as the CALLER; account_trans rd_access-JOIN scopes it — RED if the function were DEFINER)'
);
select set_config('role', 'postgres', true);

-- (j2)/(j3) non-vacuous positive + 3-COL signature: A's call returns its 1 own holding as
--   (account_id, asset_id, quantity) with quantity = 3.
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select quantity from pfin.fn_holdings_as_of('2026-06-30') where account_id = :accta and asset_id = :g_equity),
  3::numeric,
  '(j2) 3-COL signature + owner-read: A''s fn_holdings_as_of returns its own holding row keyed (account_id, asset_id, quantity) with quantity = 3 (RED if the return signature regressed/renamed — selecting asset_id would error/shift)'
);
select is(
  (select count(*) from pfin.fn_holdings_as_of('2026-06-30') where account_id = :accta)::bigint, 1::bigint,
  '(j3) owner-read count: A''s fn_holdings_as_of returns exactly 1 live holding for acct-A (HAVING sum<>0; the single seeded qty=3 security-leg row)'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;

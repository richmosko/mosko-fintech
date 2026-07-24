-- =====================================================================
-- Per-Wave battery — M1-evt Slice B (SELF-293): pfin.lot_match — the append-only,
--   immutable securities lot-matching many-to-many junction (which buy lot(s) a sell
--   closes). Decision-3 #14 fence fn_lot_match_matched_tenant_security (matched-TENANT
--   non-negotiable + matched-SECURITY correctness; BEFORE INSERT, INVOKER, NULL-safe
--   fail-closed) + 004/031-mirror immutability triple-fence. WRITE-DORMANT (029 pattern
--   — SELECT-only, no write grant; matching logic + INSERT grant land at M4-GL).
--   V1-SHIP-BLOCK; JOINT-REVIEW-MANDATORY (Decision-3 family + money/tax basis).
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/032_lot_match.sql
--   - table lot_match (id PK; sell_trans_id + buy_trans_id -> account_trans ON DELETE
--       RESTRICT, both per-tenant refs = the #14 fence targets; quantity_matched numeric
--       CHECK >0 & <>NaN & <>Infinity; match_seq int; UNIQUE(sell,buy,match_seq)).
--   - policy lot_match_select ONLY (owner-only parent-chain α via the SELL leg). NO write
--       policy (write-dormant). grant SELECT only; anon zero; service_role ungranted.
--   - fn_lot_match_matched_tenant_security() — BEFORE INSERT; INVOKER; NULL-safe: raises
--       on unresolved leg, sell-tenant<>buy-tenant, or security mismatch/NULL.
--   - fn_lot_match_block_mutation()/_block_truncate() — INVOKER immutability fences.
-- Prereqs on the reset stack: 001 (pfin), 003 (account + creator-grant rd=t/wr=t), 004
--   (account_trans + immutability pattern), 006 (account_users rd_access), 016/017
--   (pfin.asset + account_trans.security_id/quantity + the global-OR-owned #7 fence).
--
-- ┌─ ROLE MODEL (write-dormant → admin seed; the #14 fence teeth under RLS-bypass) ────────┐
-- │ lot_match is WRITE-DORMANT — authenticated has NO write grant, so lot_match rows are    │
-- │ seeded PRIVILEGED (role=postgres), like 029. Under postgres RLS is BYPASSED, so the #14  │
-- │ fence's chain-resolved subqueries SEE both tenants' rows and the explicit tenant/security │
-- │ predicates are the SOLE gate — the strongest proof they have teeth (023 LEG-F / 022 #9    │
-- │ discipline). The write-dormant grant denial (AC4) + read isolation (AC8) run under        │
-- │ authenticated; the service_role immutability (AC3d) holds grants open test-only so the    │
-- │ trigger (not the ACL) is the proven gate (the 004/031 lesson). Roles restored to postgres │
-- │ between phases. NOTE: label order (AC1..AC8) != execution order — a lot_match row must    │
-- │ EXIST (AC1c) before it can be attacked (AC3); pgTAP numbers sequentially.                 │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (1a) foreign-sell × own-buy RAISES cross-tenant — RED if the #14 tenant fence (or its
--        explicit predicate) were removed (another tenant's basis leaks into this tax compute).
--   (1b) own-sell × foreign-buy RAISES cross-tenant — the mirror direction.
--   (1c) same-tenant same-security INSERT SUCCEEDS — non-vacuous control.
--   (2a) same-tenant AAPL-sell × MSFT-buy RAISES security mismatch — RED if the correctness
--        fold-in were absent (a sell closing the wrong security's lot).
--   (2b) NULL security_id on a leg (non-securities trade) RAISES (fail-closed) — RED if a
--        NULL slipped the equality (`<>` returns NULL → IF skipped → leak).
--   (2c) same-tenant same-security partial-lot (a 2nd buy lot) SUCCEEDS — non-vacuous control.
--   (3a)/(3b)/(3c) UPDATE / DELETE / TRUNCATE RAISE (append-only immutability).
--   (3d) a service_role UPDATE (RLS-bypass, grant held open) is STILL blocked by the trigger.
--   (4a) authenticated holds SELECT; (4b) authenticated holds NO INSERT grant.
--   (4c) a direct authenticated INSERT fails at the GRANT layer (write-dormant).
--   (5a)/(5b)/(5c) quantity_matched <=0 / NaN / Infinity RAISE 23514 (the finite/positive CHECK).
--   (6a) a non-existent sell_trans_id RAISES 'cannot resolve%' (NULL-safe fail-closed, before FK).
--   (7a) a duplicate (sell,buy,match_seq) RAISES 23505 (UNIQUE).
--   (7b) a NEW match_seq batch for the same sell/buy SUCCEEDS (the append-only re-match path).
--   (8a) two-tenant read isolation: B reads 0 of A's lot_matches (parent-chain via the sell leg).
--   (8b) owner-reads-own: A reads its own lot_matches.
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22 + RT-26 + RT-27). Decision-3 family
--   delta +1 → provisional #14 (lot_match.sell_trans_id + buy_trans_id, matched-tenant,
--   chain-resolved; ONE relationship covering both FKs — Sec pins 1-vs-2 at joint-review).
--   DEFINER allowlist UNCHANGED at 4 (all three lot_match fns are INVOKER; lot_match self-
--   versions via match_seq — no 031 change, no new DEFINER). This battery is the pgTAP proof
--   the #14 fence catches a REAL cross-tenant / cross-security violation, incl. under RLS-bypass.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants _rls.tenant_a()/_b(); NO PII /
--   NO real account numbers / NO prod data. A + B each own an investment account + securities
--   trades on two GLOBAL assets (users_id NULL, legal for any tenant); cash txn (NULL security)
--   for the fail-closed leg. lot_match rows seeded PRIVILEGED (write-dormant). Rolled-back txn.
--
-- ⟦WIRE-VALIDATE⟧ authored against 032's firmed contract; authoritative run is the 001->032
--   reset stack. Locally the DB is at 027, so a net-zero rolled-back harness \i's 032 transiently
--   (032 depends only on 001/003/004/006/016/017 — already applied); CI (pg_prove directory-mode)
--   is the green gate. plan(21).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(21);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres). A owns acct-alpha, B owns acct-beta (003 creator-grant
-- rd=t/wr=t). Two GLOBAL securities (users_id NULL). Securities trades reference them;
-- one cash txn (NULL security) for the fail-closed leg.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-alpha', 'investment', 'household', 'taxable') returning account_id as accta \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'acct-beta', 'investment', 'household', 'taxable') returning account_id as acctb \gset

insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'ZQATSTA', 'QA Test Sec A') returning asset_id as g_aapl \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'ZQATSTB', 'QA Test Sec B') returning asset_id as g_msft \gset

-- A's securities trades (security A = "AAPL"; security B = "MSFT").
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:accta, '2026-05-01',  500, 'vSELLA', 'A sell secA', :g_aapl, -5) returning trans_id as sell_a \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:accta, '2026-05-02', -500, 'vBUYA',  'A buy secA',  :g_aapl,  5) returning trans_id as buy_a \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:accta, '2026-05-03', -300, 'vBUYA2', 'A buy secA #2',:g_aapl,  3) returning trans_id as buy_a2 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:accta, '2026-05-04', -400, 'vBUYAM', 'A buy secB',  :g_msft,  4) returning trans_id as buy_a_msft \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-05-05', -100, 'vCASHA', 'A cash (no security)') returning trans_id as cash_a \gset

-- B's securities trades (same global security A).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:acctb, '2026-05-06',  500, 'vSELLB', 'B sell secA', :g_aapl, -5) returning trans_id as sell_b \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:acctb, '2026-05-07', -500, 'vBUYB',  'B buy secA',  :g_aapl,  5) returning trans_id as buy_b \gset

-- =====================================================================
-- AC1 — MATCHED-TENANT both directions (postgres/RLS-bypass → explicit predicate sole gate).
-- =====================================================================
-- (1a) foreign sell (B) × own buy (A) -> cross-tenant RAISE.
select throws_like(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,5,1) $$, :sell_b, :buy_a),
  '%cross-tenant lot-match rejected%',
  '(1a) #14 matched-tenant (LOAD-BEARING, RLS-bypass): B''s sell × A''s buy RAISES cross-tenant (would pull A''s basis into B''s tax compute)'
);
-- (1b) own sell (A) × foreign buy (B) -> cross-tenant RAISE (mirror direction).
select throws_like(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,5,1) $$, :sell_a, :buy_b),
  '%cross-tenant lot-match rejected%',
  '(1b) #14 matched-tenant: A''s sell × B''s buy RAISES cross-tenant (mirror direction)'
);
-- (1c) same-tenant same-security -> SUCCEEDS (non-vacuous control). Capture the row id.
select lives_ok(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,5,1) $$, :sell_a, :buy_a),
  '(1c) matched control: A''s sell × A''s buy (same security) SUCCEEDS'
);
select id as lm_id from pfin.lot_match where sell_trans_id = :sell_a and buy_trans_id = :buy_a and match_seq = 1 \gset

-- =====================================================================
-- AC2 — MATCHED-SECURITY.
-- =====================================================================
-- (2a) same tenant, AAPL sell × MSFT buy -> security mismatch RAISE.
select throws_like(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,4,1) $$, :sell_a, :buy_a_msft),
  '%security mismatch%',
  '(2a) #14 matched-security: A''s secA sell × A''s secB buy RAISES security mismatch (can''t close AAPL with an MSFT lot)'
);
-- (2b) NULL security on a leg (cash/non-securities) -> fail-closed RAISE.
select throws_like(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,1,1) $$, :sell_a, :cash_a),
  '%security mismatch%',
  '(2b) #14 fail-closed: a NULL security_id leg (non-securities trade) RAISES (must be equal and non-null — no NULL <> leak)'
);
-- (2c) same-tenant same-security partial lot (2nd buy) -> SUCCEEDS (non-vacuous control).
select lives_ok(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,3,1) $$, :sell_a, :buy_a2),
  '(2c) matched-security control: A''s secA sell × a 2nd secA buy lot (partial lot) SUCCEEDS'
);

-- =====================================================================
-- AC5 — quantity_matched CHECK (fence passes first; the CHECK is the gate). Distinct
--   match_seq values avoid UNIQUE collision with the valid (sell_a,buy_a,1) row.
-- =====================================================================
select throws_ok(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,0,10) $$, :sell_a, :buy_a),
  '23514', null,
  '(5a) quantity CHECK: quantity_matched = 0 RAISES 23514 (must be > 0)'
);
select throws_ok(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,'NaN'::numeric,11) $$, :sell_a, :buy_a),
  '23514', null,
  '(5b) quantity CHECK: quantity_matched = NaN RAISES 23514'
);
select throws_ok(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,'Infinity'::numeric,12) $$, :sell_a, :buy_a),
  '23514', null,
  '(5c) quantity CHECK: quantity_matched = Infinity RAISES 23514'
);

-- =====================================================================
-- AC6 — NULL-safe fail-closed (non-existent leg; fence fires BEFORE the FK check).
-- =====================================================================
select throws_like(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,1,1) $$, 9999999, :buy_a),
  '%cannot resolve%',
  '(6a) NULL-safe fail-closed: a non-existent sell_trans_id RAISES ''cannot resolve'' (BEFORE the FK check)'
);

-- =====================================================================
-- AC7 — UNIQUE(sell,buy,match_seq) + the re-match batch path.
-- =====================================================================
-- (7a) duplicate (sell_a,buy_a,1) -> 23505 (the fence passes; UNIQUE is the gate).
select throws_ok(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,5,1) $$, :sell_a, :buy_a),
  '23505', null,
  '(7a) UNIQUE: a duplicate (sell,buy,match_seq) RAISES unique_violation (23505)'
);
-- (7b) a NEW match_seq batch for the same sell/buy -> SUCCEEDS (append-only re-match).
select lives_ok(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,5,2) $$, :sell_a, :buy_a),
  '(7b) re-match path: a new match_seq batch (seq 2) for the same sell/buy SUCCEEDS (append-only correction)'
);

-- =====================================================================
-- AC3 — APPEND-ONLY IMMUTABILITY (attacks the valid lm_id row; each RAISES).
-- =====================================================================
-- (3a) UPDATE (postgres/owner — triggers fire for owner too).
select throws_like(
  format($$ update pfin.lot_match set quantity_matched = 999 where id = %s $$, :lm_id),
  '%is immutable%UPDATE blocked%',
  '(3a) append-only: an UPDATE on a lot_match row RAISES (block_mutation — a re-match lands as a new match_seq batch)'
);
-- (3b) DELETE.
select throws_like(
  format($$ delete from pfin.lot_match where id = %s $$, :lm_id),
  '%is immutable%DELETE blocked%',
  '(3b) append-only: a DELETE on a lot_match row RAISES (block_mutation)'
);
-- (3c) TRUNCATE (statement-level; distinct message).
select throws_like(
  'truncate pfin.lot_match',
  '%is immutable%TRUNCATE blocked%',
  '(3c) append-only: TRUNCATE RAISES (statement-level block_truncate — the lot-matching history cannot be wiped)'
);

-- =====================================================================
-- AC4 — WRITE-DORMANT (2a/2b catalog privilege facts under postgres).
-- =====================================================================
select ok(
  has_table_privilege('authenticated', 'pfin.lot_match', 'SELECT'),
  '(4a) write-dormant: authenticated holds SELECT on lot_match (owner-only read via the parent-chain policy)'
);
select ok(
  not has_table_privilege('authenticated', 'pfin.lot_match', 'INSERT'),
  '(4b) write-dormant: authenticated holds NO INSERT grant on lot_match (writes land at M4-GL)'
);

-- =====================================================================
-- AC3d (service_role immutability) — grants held OPEN test-only so the TRIGGER (not the
--   ACL) is the proven gate. SELECT needed for the UPDATE ... WHERE read (004/031 lesson).
-- =====================================================================
grant usage on schema pfin to service_role;
grant select, update on pfin.lot_match to service_role;
select set_config('role', 'service_role', true);
select throws_like(
  format($$ update pfin.lot_match set quantity_matched = 999 where id = %s $$, :lm_id),
  '%is immutable%UPDATE blocked%',
  '(3d) cross-tier: a service_role UPDATE (RLS bypassed, grant held open) is STILL blocked by the immutability TRIGGER'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- AC4c + AC8 — the REAL authenticated path.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (4c) a direct authenticated INSERT fails closed at the GRANT layer (write-dormant).
select throws_like(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,5,99) $$, :sell_a, :buy_a),
  '%permission denied for table lot_match%',
  '(4c) write-dormant: a direct authenticated INSERT into lot_match fails at the GRANT layer (SELECT-only; no write policy)'
);
-- (8b) owner-reads-own: A reads its 3 own valid lot_matches for sell_a (seq1 + seq2 + buy_a2).
select is(
  (select count(*) from pfin.lot_match where sell_trans_id = :sell_a)::bigint, 3::bigint,
  '(8b) owner-reads-own: A reads its 3 own lot_matches via the parent-chain rd_access policy (sell-leg anchor)'
);
select set_config('role', 'postgres', true);

-- (8a) two-tenant read isolation: B reads 0 of A's lot_matches.
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from pfin.lot_match where sell_trans_id = :sell_a)::bigint, 0::bigint,
  '(8a) two-tenant read isolation: B reads 0 of A''s lot_matches (parent-chain rd_access via the sell leg)'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;

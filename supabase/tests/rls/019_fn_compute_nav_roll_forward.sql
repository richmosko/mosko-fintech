-- =====================================================================
-- Per-Wave battery (correctness) — pfin.fn_compute_nav UNIFORM ROLL-FORWARD valuation
--   (ADR-027 / 019 uniform-model amendment — F/CTO-ratified 2026-07-15; supersedes Rule A)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/019_eod_price_and_valuation.sql (the uniform roll-forward
--   rewrite). Tokens bound to the LANDED DDL: fn_holdings_as_of(date) → (account_id, ASSET_ID,
--   quantity); fn_compute_nav(date) = Σ(qty × eod_price[D-first] × fx) + Σ(rolled-forward cash × fx);
--   eod_price.source ∈ {market_feed, spot_feed, fx_feed, manual_valuation, provider_implied};
--   source-priority CASE manual_valuation=1 > exact_feed(market/spot/fx)=2 > provider_implied=3;
--   holdings_checkpoint.security_id (nullable FK → pfin.asset). This is the CORRECTNESS fixture
--   (not a security assertion); isolation lives in 019_eod_price_and_valuation_rls.sql (+ the fence in
--   019_holdings_checkpoint_security_fence_rls.sql).
--
-- THE RATIFIED MODEL (V-1..V-6; verified against the landed 019):
--   qty(as_of) per (account, security_id) = latest holdings_checkpoint.quantity (≤ as_of; ANCHOR)
--     + Σ(account_trans.quantity WHERE security_id=asset AND transaction_date > anchor.as_of_date AND
--     ≤ as_of); NO checkpoint → anchor_date = -inf → Σ all txns. Cash rolls forward SYMMETRICALLY
--     (account_balance_checkpoint anchor + Σ amount strictly-after; no-checkpoint → Σ all amount).
--   value = qty × eod_price(D-FIRST: latest price_date ≤ as_of; SAME-DATE tie → source rank
--     manual_valuation > exact_feed > provider_implied) × fx (USD ≡ 1.0). ONE formula (V-1); no
--     balance-direct, no COALESCE either/or. Liabilities R-7 signed (owed = negative). Unpriced
--     asset → NULL term → SUM drops → 0 ("needs valuation"), never NULL/NaN.
--
-- ┌─ WHY SCENARIO-TENANT ISOLATION (one behavior per tenant → one fn_compute_nav scalar) ─────────┐
-- │ fn_compute_nav returns ONE scalar over ALL the caller's accounts (INVOKER, RLS-scoped). Giving  │
-- │ each behavior its OWN synthetic tenant makes a call return exactly that scenario's net worth —   │
-- │ deterministic PINPOINTING (a RED names the broken behavior) + doubles as an INVOKER-isolation    │
-- │ proof. Security-leg txns carry amount = 0 so they do NOT leak into the all-accounts CASH leg.    │
-- └────────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- SCENARIO MATRIX (as_of = 2026-06-30; each = one tenant unless noted; expected NAV in USD):
--   S1  anchor+delta+same-date-excl  checkpoint qty 10 @ 01-31; +5 txn @ 02-15 (after); +3 txn @ 01-31
--                                    (ON anchor date → EXCLUDED). qty = 10+5 = 15 × price 200 = 3000.
--   S2  no-checkpoint → full ledger  no checkpoint; +7 txn. qty = 7 × price 150 = 1050.
--   S3a same-date rank: manual wins  qty 1; manual 120 + feed 110 + provider_implied 100 @ same date → 120.
--   S3b same-date rank: feed wins    qty 1; feed 110 + provider_implied 100 @ same date → 110.
--   S3c provider_implied FLOOR       qty 1; provider_implied 100 only → 100.
--   S4  LOCF DATE DOMINANCE          qty 1; manual 90 @ 02-25 vs market_feed 100 @ 06-29 → 100 (later
--                                    date wins across sources; rank only breaks a SAME-date tie). THE trap.
--   S5  cash roll-forward            cash acct: anchor 1000 @ 01-31 + 500 @ 02-15 (after); -200 @ 01-15
--                                    (PRE-anchor → EXCLUDED) → 1500.
--   S5b cash no-checkpoint→ledger    cash acct: no anchor; +300 amount → 300 (full-ledger cash path).
--   S6  liability sign (uniform)     liability acct: anchor balance -2000 (owed negative) → -2000 (no
--                                    account_type branch; reduces NAV).
--   S7  unpriced → 0 (+never-NULL)   security with NO eod_price ≤ as_of, qty 5 → 0.
--   + fn_holdings_as_of 3-col (account_id, ASSET_ID, quantity) signature exercised under S1 (qty 15).
--
-- FAILS-CLOSED (each guards a REAL regression):
--   S1  RED if the anchor were ignored (→1050 ledger-only or 3600 anchor+all-txns incl the same-date row)
--       or the strictly-after boundary were `>=` (→ the +3 same-date row double-counts → qty 18 → 3600).
--   S2  RED if no-checkpoint didn't fall to full-ledger (→ 0).
--   S3a RED if the source-rank CASE were wrong/absent (→ 110 or 100 instead of manual 120).
--   S3b RED if exact_feed didn't outrank provider_implied (→ 100).
--   S3c RED if provider_implied weren't a valid resolvable source (→ unpriced 0).
--   S4  RED if rank beat date (→ stale manual 90 instead of the fresher feed 100) — the exact trap V-4 forbids.
--   S5  RED if cash didn't roll forward (→ 300 ledger-only, or 800 if the pre-anchor -200 leaked in, or
--       1300 if the +500 delta were dropped).
--   S5b RED if the no-checkpoint cash path didn't sum the ledger (→ 0).
--   S6  RED if a liability sign-flip/abs were applied (→ +2000) — proves uniform R-7 signing.
--   S7  RED (or NULL/NaN) if an unpriced asset didn't drop to 0 via the SUM-NULL fence.
--
-- §10 / DECISION 3: no ledger change here (correctness fixture). The holdings_checkpoint.security_id
--   fence (D3 #11) is proven in the sibling fence battery; this file only CONSUMES resolved holdings.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed scenario UUIDs; NO PII / real account numbers / prod
--   data; all seeds PRIVILEGED (postgres, RLS-bypassed INSERT) in a rolled-back txn. The 003 creator-
--   grant trigger (keyed on new.users_id) seeds account_users rd=t so each tenant's INVOKER call reads
--   its own rows. GLOBAL market securities carry users_id NULL (readable by all; pass the 017/019 fences).
--
-- ⟦WIRE-VALIDATE⟧ authored + smoke-verified GREEN against the 001→019 landed stack (transient
--   apply+rollback) 2026-07-15. CI pg_prove directory-mode after Backend's apply is the green gate. plan(12).
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

select plan(12);

-- Fixed synthetic scenario tenants (deterministic; one behavior each).
\set t_s1  '00000000-0000-0000-0000-0000000f0011'
\set t_s2  '00000000-0000-0000-0000-0000000f0012'
\set t_s3a '00000000-0000-0000-0000-0000000f0013'
\set t_s3b '00000000-0000-0000-0000-0000000f0014'
\set t_s3c '00000000-0000-0000-0000-0000000f0015'
\set t_s4  '00000000-0000-0000-0000-0000000f0016'
\set t_s5  '00000000-0000-0000-0000-0000000f0017'
\set t_s5b '00000000-0000-0000-0000-0000000f0018'
\set t_s6  '00000000-0000-0000-0000-0000000f0019'
\set t_s7  '00000000-0000-0000-0000-0000000f001a'

insert into auth.users (id) values
  (:'t_s1'), (:'t_s2'), (:'t_s3a'), (:'t_s3b'), (:'t_s3c'),
  (:'t_s4'), (:'t_s5'), (:'t_s5b'), (:'t_s6'), (:'t_s7');

-- GLOBAL market securities (users_id NULL → 017/019 fences pass; readable by every tenant's INVOKER).
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'RFSX', 'RF Sec X') returning asset_id as sx \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'RFSY', 'RF Sec Y') returning asset_id as sy \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'RFSZA', 'RF Sec ZA') returning asset_id as sza \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'RFSZB', 'RF Sec ZB') returning asset_id as szb \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'RFSZC', 'RF Sec ZC') returning asset_id as szc \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'RFSW', 'RF Sec W') returning asset_id as sw \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'RFSN', 'RF Sec N (unpriced)') returning asset_id as sn \gset

-- eod_price observations (privileged seed; source spellings bound to 019's CHECK).
insert into pfin.eod_price (asset_id, price_date, source, price) values
  (:sx,  '2026-01-31', 'market_feed',      200.0000),
  (:sy,  '2026-01-15', 'market_feed',      150.0000),
  (:sza, '2026-03-01', 'manual_valuation', 120.0000),  -- S3a: manual (rank 1) wins same date
  (:sza, '2026-03-01', 'market_feed',      110.0000),
  (:sza, '2026-03-01', 'provider_implied', 100.0000),
  (:szb, '2026-03-01', 'market_feed',      110.0000),  -- S3b: feed (rank 2) beats provider_implied
  (:szb, '2026-03-01', 'provider_implied', 100.0000),
  (:szc, '2026-03-01', 'provider_implied', 100.0000),  -- S3c: provider_implied floor only
  (:sw,  '2026-02-25', 'manual_valuation',  90.0000),  -- S4: earlier manual — must LOSE to the later feed
  (:sw,  '2026-06-29', 'market_feed',      100.0000);  -- S4: later date wins across sources (D-first)
-- SN (S7): intentionally NO eod_price row.

-- ---------------------------------------------------------------------
-- S1 (t_s1) — roll-forward anchor + strictly-after delta + same-date exclusion → 3000.
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'t_s1', 's1', 'investment', 'household', 'taxable') returning account_id as a_s1 \gset
insert into pfin.holdings_checkpoint (account_id, security_id, symbol, as_of_date, quantity, balance)
  values (:a_s1, :sx, 'RFSX', '2026-01-31', 10, 2000);          -- ANCHOR qty 10 @ 01-31
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, vendor)
  values (:a_s1, '2026-02-15', 0, 5, :sx, 's1-after');         -- AFTER anchor → +5
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, vendor)
  values (:a_s1, '2026-01-31', 0, 3, :sx, 's1-onanchor');      -- ON anchor date → EXCLUDED

-- S2 (t_s2) — no checkpoint → full ledger → 1050.
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'t_s2', 's2', 'investment', 'household', 'taxable') returning account_id as a_s2 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, vendor)
  values (:a_s2, '2026-02-01', 0, 7, :sy, 's2-ledger');        -- no checkpoint → qty 7

-- S3a/S3b/S3c — same-date source-priority ladder (qty 1 each).
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'t_s3a', 's3a', 'investment', 'household', 'taxable') returning account_id as a_s3a \gset
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, vendor)
  values (:a_s3a, '2026-02-01', 0, 1, :sza, 's3a');
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'t_s3b', 's3b', 'investment', 'household', 'taxable') returning account_id as a_s3b \gset
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, vendor)
  values (:a_s3b, '2026-02-01', 0, 1, :szb, 's3b');
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'t_s3c', 's3c', 'investment', 'household', 'taxable') returning account_id as a_s3c \gset
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, vendor)
  values (:a_s3c, '2026-02-01', 0, 1, :szc, 's3c');

-- S4 (t_s4) — LOCF date dominance → 100.
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'t_s4', 's4', 'investment', 'household', 'taxable') returning account_id as a_s4 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, vendor)
  values (:a_s4, '2026-02-01', 0, 1, :sw, 's4');

-- S5 (t_s5) — cash roll-forward: anchor + strictly-after delta; pre-anchor excluded → 1500.
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'t_s5', 's5', 'depository', 'household', 'taxable') returning account_id as a_s5 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a_s5, 1000.0000, 'USD', '2026-01-31', 'seed');       -- cash ANCHOR 1000 @ 01-31
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, vendor)
  values (:a_s5, '2026-02-15', 500.0000, 0, 's5-after');        -- AFTER anchor → +500
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, vendor)
  values (:a_s5, '2026-01-15', -200.0000, 0, 's5-preanchor');   -- BEFORE anchor → EXCLUDED

-- S5b (t_s5b) — cash no-checkpoint → full ledger → 300.
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'t_s5b', 's5b', 'depository', 'household', 'taxable') returning account_id as a_s5b \gset
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, vendor)
  values (:a_s5b, '2026-02-01', 300.0000, 0, 's5b-ledger');     -- no anchor → full ledger 300

-- S6 (t_s6) — liability uniform sign → -2000.
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'t_s6', 's6', 'liability', 'household', 'taxable') returning account_id as a_s6 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a_s6, -2000.0000, 'USD', '2026-01-31', 'seed');      -- owed = negative (R-7 uniform)

-- S7 (t_s7) — unpriced security → 0.
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'t_s7', 's7', 'investment', 'household', 'taxable') returning account_id as a_s7 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, vendor)
  values (:a_s7, '2026-02-01', 0, 5, :sn, 's7-unpriced');       -- SN has NO eod_price → 0

-- =====================================================================
-- ASSERTIONS — one fn_compute_nav('2026-06-30') scalar per scenario tenant.
-- =====================================================================
select _rls.set_tenant(:'t_s1'::uuid);
select is(pfin.fn_compute_nav('2026-06-30'::date), 3000.0000::numeric,
  '(S1) roll-forward anchor+delta+same-date-exclusion: NAV = 3000 (qty 10 anchor + 5 strictly-after − 0 same-date × price 200). RED at 1050 (anchor ignored) / 3600 (same-date txn double-counted via a >= boundary)');
-- (H) fn_holdings_as_of 3-col signature (account_id, ASSET_ID, quantity) + roll-forward qty, under S1.
select is(
  (select quantity from pfin.fn_holdings_as_of('2026-06-30') where account_id = :a_s1 and asset_id = :sx),
  15::numeric,
  '(H) fn_holdings_as_of 3-col signature: returns (account_id, asset_id, quantity) with the roll-forward qty = 15 for RFSX (RED if the return col were not asset_id, or the roll-forward miscomputed)');
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'t_s2'::uuid);
select is(pfin.fn_compute_nav('2026-06-30'::date), 1050.0000::numeric,
  '(S2) no-checkpoint → full ledger: NAV = 1050 (qty 7 all-txns × price 150). RED at 0 if no-checkpoint did not fall through to the full ledger');
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'t_s3a'::uuid);
select is(pfin.fn_compute_nav('2026-06-30'::date), 120.0000::numeric,
  '(S3a) same-date source-priority: NAV = 120 — manual_valuation (rank 1) beats feed (110) and provider_implied (100) on the same date. RED if the source-rank CASE were wrong/absent');
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'t_s3b'::uuid);
select is(pfin.fn_compute_nav('2026-06-30'::date), 110.0000::numeric,
  '(S3b) same-date source-priority: NAV = 110 — exact_feed (rank 2) beats provider_implied (rank 3, 100). RED at 100 if the floor were not outranked');
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'t_s3c'::uuid);
select is(pfin.fn_compute_nav('2026-06-30'::date), 100.0000::numeric,
  '(S3c) provider_implied FLOOR: NAV = 100 — provider_implied is a valid resolvable source when it is the only one. RED at 0 if provider_implied were not honored');
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'t_s4'::uuid);
select is(pfin.fn_compute_nav('2026-06-30'::date), 100.0000::numeric,
  '(S4) LOCF DATE DOMINANCE: NAV = 100 — the later market_feed @ 06-29 wins over the earlier (higher-rank) manual 90 @ 02-25. Rank only breaks a SAME-date tie. RED at 90 if rank beat date (the exact V-4 trap)');
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'t_s5'::uuid);
select is(pfin.fn_compute_nav('2026-06-30'::date), 1500.0000::numeric,
  '(S5) cash roll-forward: NAV = 1500 (anchor 1000 + 500 strictly-after; pre-anchor -200 EXCLUDED). RED at 300 (anchor ignored) / 800 (pre-anchor -200 leaked) / 1300 (delta dropped)');
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'t_s5b'::uuid);
select is(pfin.fn_compute_nav('2026-06-30'::date), 300.0000::numeric,
  '(S5b) cash no-checkpoint → full ledger: NAV = 300 (Σ amount, no anchor). RED at 0 if the no-checkpoint cash path did not sum the ledger');
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'t_s6'::uuid);
select is(pfin.fn_compute_nav('2026-06-30'::date), -2000.0000::numeric,
  '(S6) liability uniform sign: NAV = -2000 (owed balance is naturally negative — no account_type branch). RED at +2000 if a sign-flip/abs were applied');
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'t_s7'::uuid);
select is(pfin.fn_compute_nav('2026-06-30'::date), 0::numeric,
  '(S7) unpriced → 0: NAV = 0 (RFSN has no eod_price ≤ as_of → NULL term dropped by SUM → 0 "needs valuation"). RED (or NULL/NaN) if the unpriced asset did not fence to 0');
select isnt(pfin.fn_compute_nav('2026-06-30'::date), null,
  '(S7b) never-NULL: the unpriced-security NAV is 0, NOT NULL (both legs COALESCE to 0) — a NULL/NaN would break every downstream net-worth read');
select set_config('role', 'postgres', true);

select * from finish();
rollback;

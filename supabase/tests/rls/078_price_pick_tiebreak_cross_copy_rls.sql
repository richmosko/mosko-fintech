-- =====================================================================
-- Per-Wave battery — the price-pick same-date tie-break made TOTAL, across
--   every live copy of the kernel (Sec joint-review ruling (1), PR #480 /
--   SELF-237; V1-SHIP-BLOCK). Read-only fix: NO new table, NO new DEFINER,
--   NO new FK-shaped column, NO signature/grant/comment change.
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/078_price_pick_tiebreak_cross_copy.sql
--   Appends `ep.price_id desc` as a FINAL tiebreak (after price_date desc, then
--   the source-rank CASE) to the price-pick site in THREE live kernel copies:
--     · pfin.fn_account_unrealized_gl(date)
--     · pfin.fn_compute_nav(date, boolean)
--     · pfin.fn_subcat_market_value(date, boolean)
--   `eod_price` is unique on (asset_id, price_date, source) but the CASE
--   assigns rank 2 to THREE sources (market_feed / spot_feed / fx_feed), so an
--   asset with two same-date rank-2 observations was previously a genuine tie
--   — `limit 1` resolved it nondeterministically. price_id is a bigint identity
--   PK (019), so appending it makes the order TOTAL: the tie now resolves,
--   repeatably, to the MOST RECENTLY INSERTED observation (highest price_id).
--
-- ┌─ WHY A TOTALS-ONLY BATTERY WOULD PASS EITHER WAY (078''s own header) ───┐
-- │ "On data with no same-date same-rank tie the output is identical, which │
-- │ is most fixtures — so a battery that only asserts totals will go green  │
-- │ whether or not this migration applied. The assertion that discriminates │
-- │ is a fixture that PLANTS the tie ... and asserts the higher price_id    │
-- │ wins, repeatably. Without that leg the fix has no watcher."             │
-- │ The fixture below plants EXACTLY that shape, ANTI-CORRELATED with price │
-- │ magnitude on purpose: the HIGHER-price row is inserted FIRST (lower     │
-- │ price_id) and the LOWER-price row SECOND (higher price_id). The correct │
-- │ (post-fix) answer is the LOWER price — a regression that fell back to   │
-- │ "highest price wins" or any other plausible-looking heuristic would go  │
-- │ RED here, not silently agree by coincidence.                            │
-- └───────────────────────────────────────────────────────────────────────┘
--
-- Prereqs exercised (on the 001->078 stack): 016/017 (global asset registry,
--   currency assets); 019 (eod_price unique(asset_id,price_date,source) +
--   price_id identity PK + fn_holdings_as_of); 041 (seeded taxonomy
--   vocabulary, reused for the fn_subcat_market_value leg); 076
--   (fn_subcat_market_value, the third live kernel copy).
--
-- §10 / DECISION 3: §10 ledger UNCHANGED (078 changes an ORDER BY inside three
--   read-only SQL functions — no credential surface, no code-layer fence, no
--   network/config surface; read ADR-011 Decision 4 live). Decision-3 family
--   UNCHANGED — `ep.price_id` is eod_price''s own PK read inside an ORDER BY,
--   not a stored reference. This battery introduces no catalogued instance.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants (raw literals,
--   suffixed '78'). NO PII / NO real account numbers / NO prod data. All seeds
--   PRIVILEGED (role=postgres) with users_id set EXPLICITLY. Whole file in one
--   rolled-back txn.
--
-- ⟦WIRE-VALIDATE⟧ authored + fixture-verified GREEN via a transient apply of
--   001->078 against a scratch DB (NON-destructive). plan(7): 1 structural
--   (S1) + 3 cross-copy value (K1-K3) + 1 cross-copy identity (K4) + 1
--   repeatability (REPEAT1) + 1 isolation (I1) = 7. One fixture mistake caught
--   this way before landing: an EARLY DRAFT left a_inv/b_inv UNFUNDED (no
--   checkpoint) — fn_account_cash_as_of sums account_trans.amount back to
--   -infinity with no checkpoint to bound it, so the buy''s own -100.00/-60.00
--   cash debit exactly cancelled the security value in K1/K2/K4/I1 (all read
--   0.00, measured, not assumed), while K3 (fn_subcat_market_value) passed
--   regardless because its cash leg lands in a DIFFERENT, unclassified row.
--   Fixed the same way 076 was: fund each account to net exactly zero.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

select plan(7);

\set ta '00000000-0000-0000-0000-00000000a078'
\set tb '00000000-0000-0000-0000-00000000b078'

insert into auth.users (id) values (:'ta'), (:'tb');

-- ---------------------------------------------------------------------
-- STRUCTURAL (S1) — the `ep.price_id desc` tiebreak text is present in the
--   prosrc of all THREE live kernel copies. Scoped to a substring that can
--   ONLY appear in the executable ORDER BY (062''s lesson: a bare grep can
--   hit header prose, but these function bodies carry no inline comments).
-- ---------------------------------------------------------------------
select ok(
  (select p.prosrc ilike '%ep.price_id desc%'
     from pg_proc p
    where p.proname = 'fn_account_unrealized_gl' and p.pronamespace = 'pfin'::regnamespace)
  and
  (select p.prosrc ilike '%ep.price_id desc%'
     from pg_proc p
    where p.proname = 'fn_compute_nav' and p.pronargs = 2 and p.pronamespace = 'pfin'::regnamespace)
  and
  (select p.prosrc ilike '%ep.price_id desc%'
     from pg_proc p
    where p.proname = 'fn_subcat_market_value' and p.pronamespace = 'pfin'::regnamespace),
  '(S1) STRUCTURAL: `ep.price_id desc` is present in prosrc of all THREE live kernel copies (fn_account_unrealized_gl, fn_compute_nav(date,boolean), fn_subcat_market_value) — a future CREATE OR REPLACE that silently drops the tiebreak text goes RED here even on fixtures with no planted tie'
);

-- ---------------------------------------------------------------------
-- FIXTURE. Tenant A: one investment account (a_inv) holding ONE security
--   (secT, qty 1) with a PLANTED same-date tie: 'market_feed' @150.00
--   inserted FIRST (lower price_id), 'spot_feed' @100.00 inserted SECOND
--   (higher price_id). Both source ranks = 2 (tied on price_date AND rank).
--   Correct post-fix answer: 100.00 (highest price_id), NOT 150.00.
--   Classified to Equity for the fn_subcat_market_value leg. a_inv is FUNDED
--   via a checkpoint dated BEFORE the trade, to EXACTLY offset the buy''s cash
--   debit (076''s own convention: fn_account_cash_as_of sums account_trans
--   amounts back to -infinity when NO checkpoint bounds them, so an unfunded
--   buy would net the security''s value to ZERO against its own -100.00 cash
--   debit — measured while drafting this fixture, then fixed the same way 076
--   was; see 076''s header, "funded to net exactly zero... so the arithmetic
--   stays legible").
-- Tenant B: isolation control — one DIFFERENT security (secB, qty 1,
--   single UNTIED price 60.00) in its own account, funded the same way.
--   Real, non-vacuous value, distinct from A''s 100.00.
-- ---------------------------------------------------------------------
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SBT78','Sec T tie-planted') returning asset_id as sect \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SBB78','Sec B isolation control') returning asset_id as secb \gset

-- planted tie: higher price first (lower price_id), lower price second
-- (higher price_id) — anti-correlates price magnitude with price_id so a
-- "highest price wins" regression cannot pass by coincidence.
insert into pfin.eod_price (asset_id, price_date, source, price) values
  (:sect,'2026-08-01','market_feed',150.00);
insert into pfin.eod_price (asset_id, price_date, source, price) values
  (:sect,'2026-08-01','spot_feed',100.00);
insert into pfin.eod_price (asset_id, price_date, source, price) values
  (:secb,'2026-08-01','market_feed',60.00);

insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat) values
  (:'ta','asset','Equity','US-06-Financials') returning id as a_eq \gset

insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta','a-inv-78','investment','household','taxable') returning account_id as a_inv \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:a_inv, 100.00, 'USD', '2026-07-25', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor) values
  (:a_inv,'2026-08-01',-100.00,1,:sect,100.00,'standard','buy-t');
insert into pfin.user_asset_category (users_id, asset_id, sub_cat_id) values
  (:'ta', :sect, :a_eq);

insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'tb','b-inv-78','investment','household','taxable') returning account_id as b_inv \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:b_inv, 60.00, 'USD', '2026-07-25', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor) values
  (:b_inv,'2026-08-01',-60.00,1,:secb,60.00,'standard','buy-b');

-- =====================================================================
-- CROSS-COPY VALUE (K1-K3) — same planted tie, same expected winner
-- (100.00 = the higher price_id row), asserted through all THREE live
-- kernel copies independently.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

select is(
  (select current_market_value from pfin.fn_account_unrealized_gl('2026-08-05'::date) where account_id = :a_inv),
  100.00::numeric,
  '(K1) fn_account_unrealized_gl: current_market_value = EXACTLY 100.00 (the higher-price_id observation, spot_feed@100.00 inserted SECOND) — NOT 150.00 (market_feed, inserted first, still lower price_id)'
);
select is(
  pfin.fn_compute_nav('2026-08-05'::date, false),
  100.00::numeric,
  '(K2) fn_compute_nav(date,boolean), the SECOND live kernel copy: NAV = EXACTLY 100.00 (identical tie-break result to K1, cash leg netted to 0 by construction — no checkpoint seeded)'
);
select is(
  (select market_value from pfin.fn_subcat_market_value('2026-08-05'::date, true) where sub_cat_id = :a_eq),
  100.00::numeric,
  '(K3) fn_subcat_market_value, the THIRD live kernel copy: the classified Equity Sub-Cat''s market_value = EXACTLY 100.00 (identical tie-break result to K1/K2)'
);

-- =====================================================================
-- (K4) CROSS-COPY IDENTITY — the point of "cross_copy" in the migration''s
--   own name: all three copies resolve the SAME tie to the SAME value, not
--   merely each individually matching 100.00 by chance of independent bugs.
-- =====================================================================
select ok(
  (select current_market_value from pfin.fn_account_unrealized_gl('2026-08-05'::date) where account_id = :a_inv)
    = pfin.fn_compute_nav('2026-08-05'::date, false)
  and
  pfin.fn_compute_nav('2026-08-05'::date, false)
    = (select market_value from pfin.fn_subcat_market_value('2026-08-05'::date, true) where sub_cat_id = :a_eq),
  '(K4) ⭐ CROSS-COPY IDENTITY: fn_account_unrealized_gl, fn_compute_nav(date,boolean) and fn_subcat_market_value resolve the SAME planted tie to the IDENTICAL value — the textual-identity protected property (076: "copies that read identically can be diffed; copies that read differently cannot") holds for this fix specifically, not just in the abstract'
);

-- =====================================================================
-- (REPEAT1) REPEATABILITY — 078''s header: "asserting the higher price_id
--   wins repeatably". Two consecutive calls, same statement, same txn,
--   return the IDENTICAL value — guards against a plan that happens to be
--   deterministic once but not on re-evaluation.
-- =====================================================================
select is(
  (select current_market_value from pfin.fn_account_unrealized_gl('2026-08-05'::date) where account_id = :a_inv),
  (select current_market_value from pfin.fn_account_unrealized_gl('2026-08-05'::date) where account_id = :a_inv),
  '(REPEAT1) repeatability: two consecutive calls to fn_account_unrealized_gl over the SAME planted tie return the IDENTICAL value (100.00) within the same transaction'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (I1) ISOLATION — tenant B''s own (untied) value is unaffected by, and does
--   not include, A''s tie-planted value. Real, non-vacuous companion.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select current_market_value from pfin.fn_account_unrealized_gl('2026-08-05'::date) where account_id = :b_inv),
  60.00::numeric,
  '(I1) isolation, non-vacuous: tenant B''s current_market_value = EXACTLY 60.00 (B''s OWN untied holding) — does not include A''s 100.00, and the tie-break fix does not perturb an unrelated tenant''s unrelated data'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;

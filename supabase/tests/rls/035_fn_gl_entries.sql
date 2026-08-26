-- =====================================================================
-- Per-Wave battery — M4-GL (SELF-297): pfin.fn_gl_entries(p_as_of date) — the book-value
--   double-entry / trial-balance SECURITY INVOKER read helper (ADR-031 Decision 5 GL engine;
--   Lock 11, cloning the fn_compute_nav / 019 posture). The LAST Double-Entry GL read migration.
--   TWO axes in one battery: (1) cross-tenant read FAILS CLOSED (INVOKER + RLS composition — the
--   isolation proof, SECURITY §4.5 two-tenant posture), and (2) the CORRECT-BY-CONSTRUCTION
--   balance property (Σ(amount_book) = 0 globally + per-currency; the derived Suspense line
--   captures exactly the deferred residual). V1-SHIP-BLOCK; paired with the migration in the SAME
--   PR (verify-paired-artifacts discipline — a migration merging without its battery = vacuous CI).
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/035_fn_gl_entries.sql
--   - pfin.fn_gl_entries(p_as_of date) RETURNS TABLE(users_id, as_of, source_trans_id, split_id,
--       journal_id, account_id, entry_account, security_id, entry_class, side, currency,
--       amount_book) — SECURITY INVOKER, STABLE, set search_path=''. Images every RLS-visible
--       account_trans fact <= p_as_of (+ its 023 overlay, 029 splits, 033 journal grouping, 034
--       basis_adjust reason) into BALANCED book-value Dr/Cr entry rows via the 11 imputation
--       branches P1..P11 + the Unrealized-Gains USD memo pair. amount_book SIGNED (debit+/credit-),
--       in the leg's NATIVE currency; zero-magnitude postings suppressed. grant execute to
--       authenticated only; public REVOKED.
-- Prereqs exercised (on the 001->035 reset stack): 001 (pfin schema, auth.uid(), fn_refresh_updated_at);
--   003 (pfin.account + the fn_grant_creator_access DEFINER trigger — seeds account_users rd=t/wr=t
--   on each account insert, so each tenant's INVOKER call reads its OWN account_trans via the Lock-3
--   rd_access-JOIN); 004 (pfin.account_trans immutable ledger); 006 (account_trans rd/wr RLS); 015
--   (account.currency, default 'USD' — the native-currency axis); 016/017 (pfin.asset + security_id/
--   quantity/cost_basis + the #7 global-OR-owned fence); 019 (fn_compute_nav — REUSED verbatim for
--   the Unrealized memo, not reimplemented); 023 (account_trans_annotation — sub_cat_id overlay + the
--   #10 matched-tenant fence); 028 (user_taxonomy.cat cashflow enum Revenue/Expense/Transfer/Equity/
--   Trade); 029 (account_trans_split — per-child cat, Σ=parent); 030 (transaction_type vocab
--   {standard,acct_setup,basis_adjust,corp_action} + metadata jsonb); 033 (pfin.journal + the #12
--   matched-tenant leg fence); 034 (basis_adjust metadata.reason ∈ {depreciation,return_of_capital,
--   wash_sale} + the reason trigger); 084 (GL split — cashflow taxonomy rows now live in
--   pfin.posting_prototype, no domain column; fn_gl_entries re-issued to join it, alias ut→pp).
--   auth.jwt() reads request.jwt.claims (PG 17 stack).
--
-- ┌─ WHY THE FIXTURE IS NON-VACUOUS (the isolation + Suspense teeth) ────────────────────────────┐
-- │ ISOLATION: tenant A owns a RICH GL-producing ledger (3 accounts, 2 currencies, a BUY + a       │
-- │ depreciation basis_adjust + a SELL, two OPEN journal groups, a split). So when B               │
-- │ calls fn_gl_entries and sees ZERO of A's rows (1a), that 0 is a REAL cross-tenant denial — A   │
-- │ demonstrably HAS rows (1b > 0). B also owns its OWN minimal ledger so its call is non-empty     │
-- │ (1c) — B's INVOKER read works; it just cannot cross the tenant boundary. A DEFINER regression   │
-- │ (or a dropped set search_path / RLS) would flip 1a from 0 to A's-row-count (RED).                │
-- │ SUSPENSE: the standard SELL (qty<0) parks its proceeds as Dr Cash / Cr Suspense in V1 (the      │
-- │ position basis-removal + realized-gain deferred to 036), so the derived Suspense line carries   │
-- │ a REAL −900 residual (3a), from a REAL source row (3b) — not an empty pass. Grouped Transfer     │
-- │ legs route to Journal Clearing (4b), NOT Suspense — so a dropped journal_id branch that spilled  │
-- │ the transfers into Suspense would break BOTH 3a/3b AND 4b (cross-checked RED).                    │
-- └─────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- CORRECT-BY-CONSTRUCTION note: Σ(amount_book)=0 is guaranteed by construction (every source emits a
--   real leg + an equal-and-opposite contra; misclassification only ROUTES a contra to Suspense, never
--   unbalances). So (2a) global Σ=0 is not a weak tautology-over-empty — (2c) proves real nonzero
--   postings EXIST, and (2b) per-currency Σ=0 is the STRONGER fence: a contra emitted in the WRONG
--   currency (e.g. a hard-coded 'USD' contra) leaves EUR at −80 and USD at +80 — global might still
--   net, but the per-currency group count of nonzero sums goes >0 (RED). Each source-branch positive
--   control (4a depreciation / 4b journal-clearing / 4c opening-equity / 4d trade-position) fails
--   closed if its branch is dropped or mis-signed.
--
-- INVERSION-PROVEN (per the M3-basis 034 plan(19) standard — each assertion names the REAL violation
--   it catches; the RED condition is stated inline, mirroring 019/033/034):
--   (1a) cross-tenant read: RED if fn_gl_entries were DEFINER / lost set search_path / lost RLS
--        composition — B would see A's GL rows (1b proves those rows exist).
--   (1b) non-vacuous isolation: A sees its OWN GL rows (>0) — the anchor that makes 1a's 0 meaningful.
--   (1c) non-vacuous isolation: B sees its OWN GL rows (>0) — B's INVOKER read works; the 0 in 1a is a
--        boundary denial, not an empty function.
--   (2a) global trial balance: RED if any contra sign flipped or any contra branch dropped (e.g. P8
--        removed → the SELL's +900 cash has no counter → Σ = +900).
--   (2b) per-currency trial balance: RED if a contra took the wrong currency (EUR leg's contra hard-
--        coded USD → EUR group −80, USD group +80 → nonzero-group count = 2).
--   (2c) non-vacuous balance: real nonzero postings exist (Σ|amount_book| > 0) — 2a is a cancellation,
--        not an empty-set 0.
--   (2d) per-tenant balance under B: B's own GL also balances to 0 — the invariant holds per RLS scope.
--   (3a) Suspense residual = −900: RED if the SELL counter didn't route to Suspense (mis-labeled) → 0,
--        or if a clean BUY / return_of_capital leaked a nonzero residual → ≠ −900.
--   (3b) Suspense non-vacuous: EXACTLY one Suspense line, deriving from the SELL's source_trans_id — RED
--        if Suspense were empty (vacuous) or if a stray branch (e.g. grouped transfers) leaked in.
--   (4a) depreciation_expense contra = +500: RED if P6 dropped/mis-signed (basis_adjust depreciation).
--   (4b) journal_clearing rows = 2 (the two grouped Transfer legs): RED if the Transfer+journal_id
--        branch were dropped and the transfers fell to Suspense (would also break 3a/3b).
--   (4c) opening_equity contra = −5000: RED if P5 (acct_setup → Opening-Balance-Equity) dropped/mis-signed.
--   (4d) trade_position sum = +1500 (BUY +2000 − depreciation 500): RED if P2 (position book leg) dropped
--        or mis-signed.
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22 + RT-26 + RT-27; 035 introduces ZERO catalogued
--   §10 instances — a single authenticated-tier INVOKER READ function, no service_role grant, no
--   credential, no admission channel). Decision-3 family UNCHANGED (no new FK-shaped reference column —
--   fn_gl_entries READS existing FKs; the lot-match buy-reference #14 stays DORMANT until its write
--   path lands at 036). SECURITY DEFINER allowlist UNCHANGED (this is INVOKER; authored DEFINER fns
--   stay 3). This battery introduces no catalogued instance; it is the pgTAP proof the helper fails
--   closed cross-tenant AND balances by construction.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants _rls.tenant_a()/_b(); NO PII / NO real
--   account numbers / NO prod data. GLOBAL securities carry users_id NULL (016/017 #7 — readable by any
--   tenant's INVOKER). All seeds PRIVILEGED (role=postgres; RLS + ACL bypassed) so the assertions
--   exercise the helper ONLY under the authenticated tenant contexts under test; users_id set EXPLICITLY
--   on every seed (auth.uid() is NULL under postgres). All in a rolled-back txn. The annotation #10
--   sub_cat fence + #12 journal fence fire on the fixture inserts and PASS (matched-tenant), exactly as
--   033 (3f) proves a matched attach commits; the 034 reason trigger fires on the depreciation
--   annotation and PASSES (depreciation ⟺ amount=0).
--
-- ⟦WIRE-VALIDATE⟧ authored against 035's landed contract. The authoritative run is the 001->035 reset
--   stack under CI (pg_prove directory-mode, db-tests.yml, AFTER Backend's clean-apply of 035 —
--   Architect authors the migration + QA authors this battery; Backend runs `supabase migration up` +
--   the full-suite directory-mode gate). The committed file does NOT self-apply the migration (CI
--   applies migrations on bring-up). fn_gl_entries is invoked ONLY under authenticated A / B (never
--   postgres — auth.uid() NULL + RLS-bypass would image every tenant). plan(13).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(13);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

insert into auth.users (id) values (:'ta'), (:'tb');

-- ---------------------------------------------------------------------
-- GLOBAL securities (users_id NULL → 016/017 #7 fence: legal for any tenant). Unpriced (no
-- eod_price) — fn_compute_nav values the positions at 0 in the memo, which is a balanced USD pair
-- regardless, so the Σ=0 invariant is untouched.
-- ---------------------------------------------------------------------
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'GLSEC1', 'Global Sec 1') returning asset_id as sec1 \gset

-- ---------------------------------------------------------------------
-- Tenant A taxonomy (cashflow vocabulary, post-084 split; cat ∈ the 028 5-class enum, now on
-- pfin.posting_prototype). A-owned (matched-tenant for the #10 sub_cat fence + the 029 split
-- fence — leg tenant chain-resolves to A == posting_prototype.users_id).
-- ---------------------------------------------------------------------
-- is_tax_payment added (SELF-245/091, boolean not null no default) — false throughout.
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Revenue',  'Salary', false)    returning id as tx_a_rev  \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Expense',  'Groceries', false) returning id as tx_a_exp  \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Transfer', 'Move', false)      returning id as tx_a_xfer \gset

-- Tenant B taxonomy (the minimal control ledger).
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'tb', 'Revenue', 'Salary', false) returning id as tx_b_rev \gset

-- ---------------------------------------------------------------------
-- Tenant A accounts: USD cash + USD investment + EUR cash (the per-currency axis).
-- ---------------------------------------------------------------------
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-cash-usd', 'depository', 'household', 'taxable') returning account_id as a_cash \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-inv-usd', 'investment', 'household', 'taxable') returning account_id as a_inv \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment, currency)
  values (:'ta', 'a-cash-eur', 'depository', 'household', 'taxable', 'EUR') returning account_id as a_eur \gset

-- Tenant A journals: two OPEN transfer groups (035 images grouped legs regardless of status).
-- NOTE (037 collision fix): the second journal was 'closed' pre-037. 037's freeze_closed trigger
-- (BEFORE INSERT on account_trans_annotation) now REJECTS attaching a leg to a CLOSED journal, so
-- the t_xf_in attach below would RAISE under the 001→037 reset. Flipped to 'open' — 035 asserts
-- nothing status-specific ((4b) only counts the 2 grouped-transfer journal_clearing legs), so
-- plan(13) is unchanged. Close-time enforcement + the freeze guard are exercised in 037's battery.
insert into pfin.journal (users_id, group_type, status, description)
  values (:'ta', 'transfer', 'open', 'A open journal')   returning journal_id as j_open  \gset
insert into pfin.journal (users_id, group_type, status, description)
  values (:'ta', 'transfer', 'open', 'A open journal 2') returning journal_id as j_open2 \gset

-- ---------------------------------------------------------------------
-- Tenant A facts (transaction_type defaults 'standard' where omitted).
-- ---------------------------------------------------------------------
-- Revenue cash flow (+1000) → P1 Cash +1000 / P3 Revenue -1000.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:a_cash, '2026-05-01', 1000, 'vREV', 'salary') returning trans_id as t_rev \gset
-- Expense cash flow (-200) → P1 Cash -200 / P3 Expense +200.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:a_cash, '2026-05-02', -200, 'vEXP', 'groceries') returning trans_id as t_exp \gset
-- Transfer OUT (-300), grouped in the OPEN journal → P1 Cash -300 / P3 Journal Clearing +300.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:a_cash, '2026-05-03', -300, 'vXFO', 'transfer out') returning trans_id as t_xf_out \gset
-- Transfer IN (+300), grouped in the 2nd open journal → P1 Cash +300 / P3 Journal Clearing -300.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:a_inv, '2026-05-03', 300, 'vXFI', 'transfer in') returning trans_id as t_xf_in \gset
-- acct_setup opening cash (+5000) → P1 Cash +5000 / P5 Opening-Balance-Equity -5000.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type)
  values (:a_inv, '2026-05-04', 5000, 'vAS', 'opening balance', 'acct_setup') returning trans_id as t_setup \gset
-- Security BUY (qty +10, amount -2000, cost_basis +2000) → P1 Cash -2000 / P2 Position +2000 /
--   P10 residual 0 (suppressed) — a clean buy.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
  values (:a_inv, '2026-05-05', -2000, 'vBUY', 'buy sec1', 'standard', :sec1, 10, 2000) returning trans_id as t_buy \gset
-- basis_adjust DEPRECIATION (qty 0, cost_basis -500, amount 0) → P2 Position -500 / P6 Depreciation
--   Expense +500. (034 shape CHECK: qty=0 + security set + cost_basis set; reason ⟺ amount=0.)
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
  values (:a_inv, '2026-05-06', 0, 'vDEP', 'depreciation', 'basis_adjust', :sec1, 0, -500) returning trans_id as t_dep \gset
-- Security SELL (qty -5, amount +900) → P1 Cash +900 / P8 Suspense -900 (basis-removal + realized
--   gain DEFERRED to 036 — the non-vacuous Suspense residual). cost_basis NULL (ignored on a sell).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity)
  values (:a_inv, '2026-05-07', 900, 'vSELL', 'sell sec1', 'standard', :sec1, -5) returning trans_id as t_sell \gset
-- Split parent (-220), 2 Expense children summing to -220 → P1 Cash -220 / P4 Expense +150,+70.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:a_cash, '2026-05-08', -220, 'vSPL', 'costco split') returning trans_id as t_split \gset
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount)
  values (:t_split, :tx_a_exp, -150);
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount)
  values (:t_split, :tx_a_exp, -70);
-- EUR Expense (-80) → P1 Cash -80 (EUR) / P3 Expense +80 (EUR) — the per-currency axis.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:a_eur, '2026-05-09', -80, 'vEUR', 'eur groceries') returning trans_id as t_eur \gset

-- A annotations (privileged seed; the #10 sub_cat fence + #12 journal fence + 034 reason trigger
-- fire and PASS — all matched-tenant / amount-consistent).
insert into pfin.account_trans_annotation (trans_id, sub_cat_id)             values (:t_rev,   :tx_a_rev);
insert into pfin.account_trans_annotation (trans_id, sub_cat_id)             values (:t_exp,   :tx_a_exp);
insert into pfin.account_trans_annotation (trans_id, sub_cat_id, journal_id) values (:t_xf_out, :tx_a_xfer, :j_open);
insert into pfin.account_trans_annotation (trans_id, sub_cat_id, journal_id) values (:t_xf_in,  :tx_a_xfer, :j_open2);
insert into pfin.account_trans_annotation (trans_id, metadata)               values (:t_dep,   '{"reason":"depreciation"}'::jsonb);
insert into pfin.account_trans_annotation (trans_id, sub_cat_id)             values (:t_eur,   :tx_a_exp);

-- ---------------------------------------------------------------------
-- Tenant B minimal control ledger: one Revenue cash flow (+500) → the cross-tenant NON-VACUOUS
-- proof (B's own call returns rows; it just sees none of A's).
-- ---------------------------------------------------------------------
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'b-cash-usd', 'depository', 'household', 'taxable') returning account_id as b_cash \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:b_cash, '2026-05-10', 500, 'vBREV', 'b salary') returning trans_id as t_b_rev \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_b_rev, :tx_b_rev);

-- =====================================================================
-- BLOCK A (authenticated tenant A) — the isolation ANCHOR (1b) + the full trial-balance +
--   Suspense + source-branch battery. A reads its OWN rich ledger via the Lock-3 rd_access-JOIN.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (1b) non-vacuous isolation anchor: A sees its OWN GL rows (>0) — makes 1a's 0 a real denial.
select cmp_ok(
  (select count(*) from pfin.fn_gl_entries('2026-06-30'::date) where users_id = :'ta'::uuid),
  '>', 0::bigint,
  '(1b) non-vacuous: authenticated A sees its OWN GL entry rows (>0) via fn_gl_entries — the anchor that makes the cross-tenant 0 in (1a) a REAL boundary denial, not an empty function');

-- (2a) global trial balance: Σ(amount_book) = 0 over A's whole result (real legs + contras + memo pair).
select is(
  (select coalesce(sum(amount_book), 0) from pfin.fn_gl_entries('2026-06-30'::date)),
  0::numeric,
  '(2a) global trial balance: SUM(amount_book) = 0 over A''s full GL. RED if any contra sign flipped or any contra branch dropped (e.g. P8 removed → the SELL''s +900 cash has no counter → Σ = +900)');

-- (2b) per-currency trial balance: NO currency group has a nonzero sum (USD nets 0, EUR nets 0).
select is(
  (select count(*)::bigint from (
     select currency, sum(amount_book) as s
     from pfin.fn_gl_entries('2026-06-30'::date)
     group by currency
   ) g where g.s <> 0),
  0::bigint,
  '(2b) per-currency trial balance: every currency group sums to 0 (USD + EUR each net to zero natively — each contra shares its real leg''s currency). RED (nonzero-group count > 0) if a contra were emitted in the WRONG currency (a hard-coded USD contra leaves EUR at -80, USD at +80)');

-- (2c) non-vacuous balance: real nonzero postings EXIST (the 0 in 2a is a cancellation, not empty-set).
select cmp_ok(
  (select coalesce(sum(abs(amount_book)), 0) from pfin.fn_gl_entries('2026-06-30'::date)),
  '>', 0::numeric,
  '(2c) non-vacuous balance: SUM(|amount_book|) > 0 — A''s GL has real nonzero postings, so (2a)''s Σ=0 is a genuine debit/credit cancellation, not a vacuous sum over an empty set');

-- (3a) Suspense residual = -900: exactly the SELL''s parked proceeds (position basis-removal + realized
--      gain deferred to 036). A real, non-empty Suspense amount.
select is(
  (select coalesce(sum(amount_book), 0) from pfin.fn_gl_entries('2026-06-30'::date) where entry_class = 'suspense'),
  -900::numeric,
  '(3a) Suspense residual: SUM over entry_class=''suspense'' = -900 — exactly the standard SELL''s Cr Suspense (proceeds parked; basis-removal + realized gain DEFERRED to 036). RED at 0 if the SELL counter didn''t route to Suspense; RED at ≠ -900 if a clean BUY / return_of_capital leaked a residual');

-- (3b) Suspense non-vacuous: EXACTLY one Suspense line, deriving from the SELL''s source_trans_id.
select is(
  (select count(*) from pfin.fn_gl_entries('2026-06-30'::date)
     where entry_class = 'suspense' and source_trans_id = :t_sell),
  1::bigint,
  '(3b) Suspense non-vacuous: EXACTLY one Suspense line, and it derives from the SELL''s source_trans_id — a REAL residual, not an empty pass. RED if Suspense were empty (vacuous) or if a stray branch (e.g. grouped transfers) leaked a second Suspense line in');

-- (4a) depreciation_expense contra = +500 (P6: basis_adjust reason=depreciation → Dr Depreciation-Expense).
select is(
  (select coalesce(sum(amount_book), 0) from pfin.fn_gl_entries('2026-06-30'::date) where entry_class = 'depreciation_expense'),
  500::numeric,
  '(4a) depreciation contra: SUM over entry_class=''depreciation_expense'' = +500 (Dr, from the basis_adjust reason=depreciation cost_basis -500). RED if P6 dropped/mis-signed');

-- (4b) journal_clearing rows = 2 (the two grouped Transfer legs route to Journal Clearing, NOT Suspense).
select is(
  (select count(*) from pfin.fn_gl_entries('2026-06-30'::date) where entry_class = 'journal_clearing'),
  2::bigint,
  '(4b) grouped Transfer → Journal Clearing: EXACTLY 2 journal_clearing rows (the open-journal + closed-journal Transfer legs). RED at 0 if the Transfer+journal_id branch were dropped and the transfers fell to Suspense (would also break 3a/3b)');

-- (4c) opening_equity contra = -5000 (P5: acct_setup → Opening-Balance-Equity, offsets the +5000 cash).
select is(
  (select coalesce(sum(amount_book), 0) from pfin.fn_gl_entries('2026-06-30'::date) where entry_class = 'opening_equity'),
  -5000::numeric,
  '(4c) acct_setup contra: SUM over entry_class=''opening_equity'' = -5000 (Cr, offsetting the +5000 opening cash). RED if P5 dropped/mis-signed');

-- (4d) trade_position sum = +1500 (P2: BUY +2000 book leg − depreciation 500 book delta).
select is(
  (select coalesce(sum(amount_book), 0) from pfin.fn_gl_entries('2026-06-30'::date) where entry_class = 'trade_position'),
  1500::numeric,
  '(4d) trade_position book legs: SUM over entry_class=''trade_position'' = +1500 (BUY cost_basis +2000 − depreciation delta 500). RED if P2 (the position book leg) dropped or mis-signed');

select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK B (authenticated tenant B) — cross-tenant read FAILS CLOSED (the isolation proof) +
--   B''s own GL is non-empty (non-vacuous) + B''s own trial balance also zeroes.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);

-- (1a) cross-tenant read fails closed: B sees ZERO of A''s GL rows (INVOKER + RLS composition).
select is(
  (select count(*) from pfin.fn_gl_entries('2026-06-30'::date) where users_id = :'ta'::uuid),
  0::bigint,
  '(1a) cross-tenant read FAILS CLOSED: tenant B calling fn_gl_entries sees 0 rows owned by A (users_id = A) — INVOKER composes ENTIRELY under B''s RLS, so A''s account_trans are invisible → the helper images none of them. RED (>0) if the fn were SECURITY DEFINER / lost set search_path / lost RLS composition');

-- (1c) non-vacuous isolation: B sees its OWN GL rows (>0) — B''s INVOKER read works; 1a is a boundary denial.
select cmp_ok(
  (select count(*) from pfin.fn_gl_entries('2026-06-30'::date) where users_id = :'tb'::uuid),
  '>', 0::bigint,
  '(1c) non-vacuous: B sees its OWN GL entry rows (>0) — B''s INVOKER read is functional; the 0 in (1a) is a cross-tenant BOUNDARY denial, not a globally empty function');

-- (2d) per-tenant balance under B: B''s own GL also balances to 0 (the invariant holds per RLS scope).
select is(
  (select coalesce(sum(amount_book), 0) from pfin.fn_gl_entries('2026-06-30'::date)),
  0::numeric,
  '(2d) per-tenant trial balance: B''s OWN GL sums to 0 — the correct-by-construction Σ=0 invariant holds independently within each RLS scope (B''s Cash +500 / Revenue -500)');

select set_config('role', 'postgres', true);

select * from finish();
rollback;

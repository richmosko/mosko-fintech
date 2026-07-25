-- ============================================================================
-- Migration: pfin.fn_gl_entries — the M4-GL book-value double-entry / trial-balance
--   read helper. The LAST Double-Entry GL migration (Linear SELF-297; ADR-031
--   Decision 5 GL engine). A SINGLE SECURITY INVOKER function (Lock 11, cloning the
--   fn_compute_nav posture, 019) that IMAGES every RLS-visible account_trans fact
--   (+ its 023 mutable overlay, 029 splits, 033 journal grouping, 034 basis_adjust)
--   into BALANCED book-value Dr/Cr entry rows. Read-only over existing tables:
--   NO new base table, NO writes, NO new SECURITY DEFINER.
--   F/CTO-ratified 2026-07-24 — Option A (Narrow), flat GL entry rows. Design memo
--   temp/m4-gl-design.md.
--
-- Numbering: 035 follows 034 (M3-basis basis_adjust constraints). Pure read helper
--   over already-landed tables — order-independent among helpers, sequenced last in
--   the GL track. Depends on: 003 (pfin.account — account_id/users_id/currency/name),
--   004+017 (pfin.account_trans — trans_id/amount/quantity/cost_basis/security_id/
--   transaction_type facts), 015 (account.currency), 019 (pfin.fn_compute_nav — reused
--   for the market/Unrealized-Gains reconciliation memo; NOT reimplemented), 023
--   (account_trans_annotation — sub_cat_id overlay), 028 (user_taxonomy cashflow-class
--   enum Revenue/Expense/Transfer/Equity/Trade), 029 (account_trans_split), 030
--   (transaction_type lean vocab {standard,acct_setup,basis_adjust,corp_action} +
--   metadata jsonb), 033 (pfin.journal + account_trans_annotation.journal_id), 034
--   (basis_adjust metadata.reason ∈ {depreciation,return_of_capital,wash_sale}).
--
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT SECURITY
--   DEFINER. fn_gl_entries reads pfin base tables and needs NO elevated privilege: it
--   composes ENTIRELY under the caller's RLS, exactly like fn_compute_nav /
--   fn_holdings_as_of (019). Every base read (account direct-owner; account_trans /
--   account_trans_annotation / account_trans_split via the account_users rd_access-JOIN
--   chain; user_taxonomy owner-scoped; journal direct-owner; eod_price/asset
--   global-OR-owned via the reused fn_compute_nav) is filtered to the caller because
--   INVOKER runs as the caller. A cross-tenant caller sees NO rows → the helper returns
--   an empty/own-only entry set (fails closed). set search_path = '' is the privesc
--   fence. DEFINER would BREAK tenant isolation here (it would read every tenant's
--   ledger) — INVOKER is load-bearing, not stylistic. → DEFINER allowlist UNCHANGED.
--
-- ----------------------------------------------------------------------------
-- CORRECT-BY-CONSTRUCTION BALANCE (the load-bearing invariant): every source fact
--   emits book-value postings that sum to EXACTLY zero (a real leg + an imputed/real
--   contra, or a self-netting group). Therefore Σ(amount_book) over the whole result =
--   0 BY CONSTRUCTION — the trial balance zeroes regardless of whether a contra is
--   correctly classified. Misclassification only MISPLACES a contra among the pseudo-
--   accounts (or routes it to Suspense); it can NEVER unbalance. Book value only —
--   market value plays NO role in the balancing entries (ADR-031 Decision 4); the
--   market lens is the separate Unrealized-Gains reconciliation MEMO (below), emitted
--   as its own balanced pair so the Σ=0 invariant holds for ALL rows including the memo.
--   amount_book is SIGNED: debit-positive / credit-negative, in the account's NATIVE
--   currency (each imputed contra shares its real leg's currency, so the set nets to
--   zero per-currency); the `currency` output column lets consumers/QA group by unit.
--
-- V1 IMPUTATION RULES (fully-specified → proper contra):
--   - standard cash flow (security_id NULL), by user_taxonomy.cat on the 023 overlay:
--       Revenue → Cr Revenue · Expense → Dr Expense · Equity → Cr/Dr Equity ·
--       Transfer → per-journal Journal-Clearing IF grouped (033 journal_id) else Suspense.
--   - split parent (029, Σ children = parent.amount): ONE real cash leg + per-child
--       contra by each child's cat (the parent cat is not consulted).
--   - acct_setup → Opening-Balance-Equity contra (offsets cash + any opening position).
--   - standard security BUY (quantity>0) → Dr Position(cost_basis) / Cr Cash(amount),
--       any residual plugged to Suspense.
--   - basis_adjust reason=depreciation → Dr Depreciation-Expense / Cr Position(book).
--   - basis_adjust reason=return_of_capital → Dr Cash / Cr Position(book), residual → Suspense.
--
-- DEFERRED to 036 ("M4-GL-write") — routed to per-tenant SUSPENSE (the design's
--   should-be-zero to-do bucket), NEVER silently dropped, always balanced:
--   - standard security SELL (quantity<0): proceeds land as Dr Cash; the position-basis
--       REMOVAL + realized-gain plug (proceeds − effective_cost_basis → Equity/Retained
--       Earnings) is LOT-MATCH-dependent (032 lot_match writes land at 036) → Cr Suspense
--       for now. Recapture = min(gain, accumulated_depreciation) is authored-logic-ready
--       but VACUOUS until 036 populates lot_match (034 M4-GL CONTRACT).
--   - corp_action (030/034 GL handling deferred) → Suspense.
--   - basis_adjust reason=wash_sale (P&L deferral not yet specified) → Suspense.
--   Also deferred to 036 (NOT this read helper): the Σ=0-AT-CLOSE ENFORCEMENT TRIGGER on
--   pfin.journal status→'closed' (033 M4-GL CONTRACT — a constraint trigger that CALLS
--   this helper's group projection and RAISEs on imbalance), the lot_match INSERT grant +
--   wr_access WITH CHECK write policy (032 — activates the already-labeled Decision-3 #14),
--   and any closed_at / book-value close-snapshot storage column (033 B-ii). 035 ships the
--   READ engine only; 036 is joint-review-mandatory (write surfaces over money data).
--
-- Unrealized-Gains reconciliation MEMO (V1-IN, ADR-031 Decision 4): market net worth
--   (fn_compute_nav, 019, USD) − book NAV (fx-normalized Σ of the real legs, USD),
--   emitted as a balanced USD pair (entry_class='unrealized_gains'). EXACT for positions
--   with no realized sells; for positions WITH sells the book value is OVERSTATED (the
--   basis-removal parks in Suspense until 036), so the memo understates unrealized by a
--   bound equal to the parked Suspense residual on those positions. Documented, not hidden.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list. Decision 4 read verbatim before drafting.) This migration
--   introduces ZERO catalogued §10 instances; the ledger STAYS at 3 (RT-22 + RT-26 +
--   RT-27 per ADR-011 Decision 4).
--   (i)   Instance-numbering: RT-22 first, RT-26 second, RT-27 third — unchanged.
--   (ii)  Layer-attribution: no infrastructure-credential-presence surface (RT-22 =
--         PDF-worker container), no code-layer SUPABASE_SERVICE_ROLE_KEY allowlist
--         surface (RT-26 = web-app/worker SOURCE grep fence), no network-exposure/config
--         admission surface (RT-27 = the SELF-212 admission-app inbound fence) is touched.
--         This is a single authenticated-tier INVOKER READ function — no service_role
--         grant, no credential, no admission channel: nothing becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated. 035 is not the
--         canonical §10 anchor.
--   DE-CONFLATION GUARD: fn_gl_entries adds NO FK-shaped reference column (it READS
--   existing FKs) → Decision-3 family UNCHANGED, no new instance; the already-labeled
--   lot-match buy-reference #14 stays DORMANT until its write path lands at 036. The
--   Unrealized memo's reuse of fn_compute_nav is a read composition, NOT a new surface.
--
-- LEDGER DELTAS (confirmed): §10 catalogued instances = 3 (unchanged) · SECURITY DEFINER
--   allowlist = unchanged (this is INVOKER; authored DEFINER fns stay 3 —
--   fn_refresh_updated_at @001, fn_grant_creator_access @003, fn_reclass_history_insert
--   @031) · Decision-3 family = unchanged (no new FK-shaped column; #14 dormant → 036).
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_gl_entries(p_as_of date) RETURNS TABLE(...) — SECURITY INVOKER, STABLE,
--     set search_path = ''. Returns the flat book-value GL entry rows for every
--     transaction with transaction_date <= p_as_of visible under the caller's RLS.
--     Columns:
--       users_id        uuid    — owning tenant (from the real leg's account; NULL on the memo)
--       as_of           date    — echoes p_as_of
--       source_trans_id bigint  — the account_trans row this entry derives from (NULL on memo)
--       split_id        bigint  — the 029 split child, when the contra derives from a split line
--       journal_id      bigint  — the 033 group, when the leg is grouped (drives Journal-Clearing)
--       account_id      bigint  — the REAL account (NULL for imputed/derived contra + memo lines)
--       entry_account   text    — human label: real account name OR the pseudo-account name
--       security_id     bigint  — the (account, security) position sub-account, when applicable
--       entry_class     text    — asset_liability | trade_position | revenue | expense | equity |
--                                 opening_equity | depreciation_expense | journal_clearing |
--                                 suspense | unrealized_gains
--       side            text    — 'dr' (amount_book > 0) | 'cr' (amount_book < 0)
--       currency        text    — native currency of the leg ('USD' for the memo)
--       amount_book     numeric — SIGNED book value, debit-positive / credit-negative
--     Zero-magnitude postings are suppressed. Trial balance: SUM(amount_book) = 0
--     (globally and per currency). Suspense residual: SUM over entry_class='suspense'
--     = the reconciliation to-do (0 when everything classifies).
--   Security-load-bearing edges: INVOKER (cross-tenant caller → empty set, fails closed);
--     reversal rows (is_reverse) are summed naturally (NO special-casing — matches the
--     fn_compute_nav precedent, reversals carry negating amounts). GRANT to authenticated
--     only; public REVOKED.
-- ============================================================================

create schema if not exists pfin;

create or replace function pfin.fn_gl_entries(p_as_of date)
returns table (
  users_id        uuid,
  as_of           date,
  source_trans_id bigint,
  split_id        bigint,
  journal_id      bigint,
  account_id      bigint,
  entry_account   text,
  security_id     bigint,
  entry_class     text,
  side            text,
  currency        text,
  amount_book     numeric
)
language sql
security invoker
set search_path = ''
as $$
  with txn as (
    -- Every RLS-visible transaction <= as_of, joined to its mutable 023 overlay + class.
    select
      t.trans_id,
      t.account_id,
      t.amount,
      t.security_id,
      t.quantity,
      t.cost_basis,
      t.transaction_type,
      a.users_id       as users_id,
      a.currency       as currency,
      a.name           as account_name,
      ann.journal_id   as journal_id,
      (ann.metadata ->> 'reason') as reason,
      ut.cat           as flow_class,
      (select count(*) from pfin.account_trans_split s where s.account_trans_id = t.trans_id) as split_count
    from pfin.account_trans t
    join pfin.account a on a.account_id = t.account_id
    left join pfin.account_trans_annotation ann on ann.trans_id = t.trans_id
    left join pfin.user_taxonomy ut on ut.id = ann.sub_cat_id
    where t.transaction_date <= p_as_of
  ),

  -- REAL LEGS (P1 cash + P2 position) — the stored account movements, book value.
  real_leg as (
    -- P1: cash leg — every row carrying a cash amount (flows, acct_setup cash, buy/sell
    --     cash, return-of-capital cash, corp_action cash). Signed: +inflow / −outflow.
    select
      t.users_id, t.trans_id as source_trans_id, null::bigint as split_id, t.journal_id,
      t.account_id, t.account_name as entry_account, null::bigint as security_id,
      'asset_liability'::text as entry_class, t.currency, t.amount as amount_book
    from txn t
    where t.amount <> 0
    union all
    -- P2: position leg — book-value change of an (account, security) holding: security
    --     BUY / acct_setup opening position / any basis_adjust delta. Standard non-buys
    --     (SELL or zero-qty) excluded — no position leg is emitted; their entire real
    --     side (the P1 cash proceeds) routes to Suspense (basis removal + realized gain
    --     deferred to 036 → the sell's Suspense counter carries it).
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      t.account_id, t.account_name, t.security_id,
      'trade_position'::text, t.currency, t.cost_basis
    from txn t
    where t.security_id is not null
      and t.cost_basis is not null
      and t.cost_basis <> 0
      and not (t.transaction_type = 'standard' and t.quantity <= 0)
  ),

  -- CONTRA LEGS (P3..P12) — imputed / derived counter-legs, each equal-and-opposite to
  -- its source's real leg(s), tagged with a class-derived pseudo-account (or Suspense).
  contra as (
    -- P3: standard cash-flow contra (non-split), by the 023 overlay cat.
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint as account_id,
      case
        when t.flow_class = 'Revenue'  then 'Revenue'
        when t.flow_class = 'Expense'  then 'Expense'
        when t.flow_class = 'Equity'   then 'Equity'
        when t.flow_class = 'Transfer' and t.journal_id is not null then 'Journal Clearing'
        else 'Suspense'
      end as entry_account,
      null::bigint,
      case
        when t.flow_class = 'Revenue'  then 'revenue'
        when t.flow_class = 'Expense'  then 'expense'
        when t.flow_class = 'Equity'   then 'equity'
        when t.flow_class = 'Transfer' and t.journal_id is not null then 'journal_clearing'
        else 'suspense'
      end as entry_class,
      t.currency, (- t.amount) as amount_book
    from txn t
    where t.transaction_type = 'standard'
      and t.security_id is null
      and t.split_count = 0
      and t.amount <> 0

    union all
    -- P4: split-child contras — one per 029 child, by the CHILD's cat (parent cat unused).
    select
      t.users_id, t.trans_id, s.id, t.journal_id,
      null::bigint,
      case
        when ut.cat = 'Revenue'  then 'Revenue'
        when ut.cat = 'Expense'  then 'Expense'
        when ut.cat = 'Equity'   then 'Equity'
        when ut.cat = 'Transfer' and t.journal_id is not null then 'Journal Clearing'
        else 'Suspense'
      end,
      null::bigint,
      case
        when ut.cat = 'Revenue'  then 'revenue'
        when ut.cat = 'Expense'  then 'expense'
        when ut.cat = 'Equity'   then 'equity'
        when ut.cat = 'Transfer' and t.journal_id is not null then 'journal_clearing'
        else 'suspense'
      end,
      t.currency, (- s.amount)
    from txn t
    join pfin.account_trans_split s on s.account_trans_id = t.trans_id
    left join pfin.user_taxonomy ut on ut.id = s.sub_cat_id
    where t.split_count > 0

    union all
    -- P5: acct_setup contra → Opening-Balance-Equity (offsets cash + opening position).
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint, 'Opening Balance Equity', null::bigint, 'opening_equity',
      t.currency,
      - ( coalesce(t.amount, 0)
          + coalesce(case when t.security_id is not null then t.cost_basis else 0 end, 0) )
    from txn t
    where t.transaction_type = 'acct_setup'

    union all
    -- P6: basis_adjust depreciation contra → Dr Depreciation-Expense.
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint, 'Depreciation Expense', null::bigint, 'depreciation_expense',
      t.currency, (- t.cost_basis)
    from txn t
    where t.transaction_type = 'basis_adjust'
      and t.reason = 'depreciation'
      and t.cost_basis is not null and t.cost_basis <> 0

    union all
    -- P7: basis_adjust wash_sale / unknown-reason contra → Suspense (P&L deferral, 036).
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint, 'Suspense', null::bigint, 'suspense',
      t.currency, (- t.cost_basis)
    from txn t
    where t.transaction_type = 'basis_adjust'
      and (t.reason is null or t.reason not in ('depreciation', 'return_of_capital'))
      and t.cost_basis is not null and t.cost_basis <> 0

    union all
    -- P8: standard security non-buy (SELL or zero-qty) counter → Suspense. Offsets the
    --     P1 cash leg; position basis-removal + realized gain deferred to 036. (For a
    --     zero-amount row the counter is 0 and is suppressed by the final filter.)
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint, 'Suspense', null::bigint, 'suspense',
      t.currency, (- t.amount)
    from txn t
    where t.transaction_type = 'standard'
      and t.security_id is not null
      and t.quantity <= 0

    union all
    -- P9: corp_action counter → Suspense (GL handling deferred, 030/034 → 036).
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint, 'Suspense', null::bigint, 'suspense',
      t.currency,
      - ( coalesce(t.amount, 0)
          + coalesce(case when t.security_id is not null then t.cost_basis else 0 end, 0) )
    from txn t
    where t.transaction_type = 'corp_action'

    union all
    -- P10: standard BUY residual plug → Suspense (0 for a clean buy: amount = −cost_basis).
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint, 'Suspense', null::bigint, 'suspense',
      t.currency, - ( coalesce(t.amount, 0) + coalesce(t.cost_basis, 0) )
    from txn t
    where t.transaction_type = 'standard'
      and t.security_id is not null
      and t.quantity > 0

    union all
    -- P11: return_of_capital residual plug → Suspense (0 when cash-in = basis-out).
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint, 'Suspense', null::bigint, 'suspense',
      t.currency, - ( coalesce(t.amount, 0) + coalesce(t.cost_basis, 0) )
    from txn t
    where t.transaction_type = 'basis_adjust'
      and t.reason = 'return_of_capital'
  ),

  postings as (
    select * from real_leg
    union all
    select * from contra
  ),

  -- Book NAV in USD: fx-normalized Σ of the real legs (cash + position at book cost),
  -- using the SAME fx pattern as fn_compute_nav (019). Feeds the Unrealized memo.
  book_nav as (
    select coalesce(sum(
      rl.amount_book
      * case when rl.currency = 'USD' then 1.0
             else coalesce((
               select fx.price from pfin.eod_price fx
               join pfin.asset ca on ca.asset_id = fx.asset_id
               where ca.users_id is null and ca.asset_type = 'currency'
                 and ca.symbol = rl.currency and fx.source = 'fx_feed'
                 and fx.price_date <= p_as_of
               order by fx.price_date desc limit 1), 1.0) end
    ), 0) as v
    from real_leg rl
  ),

  -- Unrealized-Gains reconciliation MEMO (USD, balanced pair): market − book.
  memo as (
    select
      auth.uid() as users_id,
      null::bigint as source_trans_id, null::bigint as split_id, null::bigint as journal_id,
      null::bigint as account_id,
      'Market Value Adjustment'::text as entry_account, null::bigint as security_id,
      'unrealized_gains'::text as entry_class, 'USD'::text as currency,
      (pfin.fn_compute_nav(p_as_of) - (select v from book_nav)) as amount_book
    union all
    select
      auth.uid(),
      null::bigint, null::bigint, null::bigint,
      null::bigint, 'Unrealized Gains (Equity)', null::bigint,
      'unrealized_gains', 'USD',
      - (pfin.fn_compute_nav(p_as_of) - (select v from book_nav))
  ),

  all_rows as (
    select * from postings
    union all
    select * from memo
  )

  select
    ar.users_id,
    p_as_of as as_of,
    ar.source_trans_id,
    ar.split_id,
    ar.journal_id,
    ar.account_id,
    ar.entry_account,
    ar.security_id,
    ar.entry_class,
    case when ar.amount_book >= 0 then 'dr' else 'cr' end as side,
    ar.currency,
    ar.amount_book
  from all_rows ar
  where ar.amount_book <> 0
  order by ar.source_trans_id nulls last, ar.entry_class;
$$;

revoke execute on function pfin.fn_gl_entries(date) from public;
grant execute on function pfin.fn_gl_entries(date) to authenticated;

comment on function pfin.fn_gl_entries(date) is
  'SECURITY INVOKER book-value GL / trial-balance read helper (M4-GL; ADR-031 Decision 5 / '
  'Lock 11 — clones the fn_compute_nav posture, 019). Images every RLS-visible '
  'account_trans fact <= as_of (+ its 023 overlay, 029 splits, 033 journal grouping, 034 '
  'basis_adjust reason) into BALANCED book-value Dr/Cr entry rows. CORRECT-BY-CONSTRUCTION: '
  'every source emits postings summing to exactly 0, so SUM(amount_book)=0 (global + per '
  'currency) by construction; misclassification only routes a contra to the derived '
  'Suspense line, never unbalances. amount_book is SIGNED (debit+/credit−) in native '
  'currency. Fully-specified: cash flows by user_taxonomy.cat (Revenue/Expense/Equity/'
  'Transfer-via-Journal-Clearing), splits per-child, acct_setup→Opening-Balance-Equity, '
  'security BUY→Dr Position/Cr Cash, basis_adjust depreciation→Dr Depreciation-Expense, '
  'return_of_capital→cash+basis. DEFERRED to 036 (routed to Suspense, balanced, never '
  'dropped): security SELL realized-gain/basis-removal (lot-match 032→036), corp_action, '
  'wash_sale; also 036: the Σ=0-at-close enforcement trigger (033), the lot_match write '
  'path activating Decision-3 #14 (dormant here), any close-snapshot column. Unrealized-'
  'Gains MEMO = fn_compute_nav(as_of) − book NAV (USD balanced pair, entry_class='
  '''unrealized_gains''); exact w/o realized sells, understated (book overstated) where '
  'sells park in Suspense until 036. INVOKER → cross-tenant caller sees no rows (fails '
  'closed); reversal rows summed naturally (fn_compute_nav precedent). set search_path=''''; '
  'NOT a DEFINER allowlist entry (INVOKER) — allowlist unchanged; §10 ledger unchanged at 3 '
  '(RT-22 + RT-26 + RT-27); Decision-3 unchanged (no new FK column).';

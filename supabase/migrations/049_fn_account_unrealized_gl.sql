-- ============================================================================
-- Migration: pfin.fn_account_unrealized_gl — per-account unrealized G/L aggregation
--   primitive (V1.1 "Net worth full"; PRD §2.1.5.a; structurally shared with §2.2
--   asset-allocation, V1.2). A SINGLE SECURITY INVOKER read helper (Lock 11, cloning
--   the fn_compute_nav / fn_gl_entries posture, 019 / 035 / 037) that returns, per
--   non-inactive account in the caller's tenant, its current market value + (for
--   investment-class accounts) cost basis + unrealized gain/loss. Read-only over
--   already-landed tables + fns: NO new base table, NO writes, NO new SECURITY DEFINER,
--   NO new FK-shaped column.
--   Linear SELF-224 (first V1.1 build feature). Design brief temp/self-224-design-brief
--   (in-message). F/CTO-ratified 2026-08-01/02.
--
-- ----------------------------------------------------------------------------
-- RATIFY-ASSUMPTION FLAG (post-ratify cross-check hook — verify before finalize):
--   F/CTO ratified 2026-08-01/02:
--     (R1) COST-BASIS PATH = GL-derived carried book — reuse fn_gl_entries `trade_position`
--          rows (the first-ratify "Option A"; ORTHOGONAL to the market-value SCOPE in R5).
--          Ratified CONTINGENT on the lot-split forward-path answer (see LOT-SPLIT FORWARD
--          PATH below — GL-derived is sound; per-lot decomposition is an additive future
--          migration, NOT a switch to the lot_match direct path).
--     (R2) DROP p_scope (the drafted `pfin.scope[]` type does not exist; `scope` is a
--          free-text account label per ADR-004 Decision B). Deferred to a later filter.
--     (R3) MECHANICAL SIG FIXES: account_id bigint (not UUID); DROP p_users_id (INVOKER +
--          RLS scopes by auth.uid() by-construction — a p_users_id param is a confused-
--          deputy foot-gun; mirrors fn_compute_nav / fn_holdings_as_of / fn_gl_entries,
--          all p_as_of-only). 4-COLUMN CONTRACT (F/CTO ratify 2026-08-02): account_type was
--          considered as a returned branch discriminator and DECLINED — the NULL-vs-zero on
--          cost_basis already encodes investment vs non-investment; a consumer needing the
--          specific type joins pfin.account.
--     (R4) USD-fx NORMALIZATION (consistency with fn_compute_nav / the "Net worth full"
--          milestone — the AC's bare qty×eod_price omits fx; NAV consistency requires it).
--     (R5) MARKET-VALUE SCOPE = DESIGN C (account-total, symmetric) — F/CTO ratified
--          2026-08-02 after consumer analysis (SELF-225 foots current_market_value to NAV;
--          a positions-only view UNDERSTATES a brokerage's account value by its cash sweep).
--          See MARKET-VALUE SCOPE — DESIGN C below. This SUPERSEDES the earlier design-brief
--          §B / the "securities-only" (Design A) draft that this file previously implemented.
--
-- ----------------------------------------------------------------------------
-- MARKET-VALUE SCOPE — DESIGN C (account-total, symmetric; F/CTO-ratified; ADR-038):
--   The choice is column SEMANTICS, not correctness (both A and C give correct
--   unrealized_gl). The governing arithmetic: `unrealized_gl = mv − cost_basis` is correct
--   AND consumer-verifiable ONLY when mv and cost_basis are at the SAME scope. F/CTO chose
--   the ACCOUNT-TOTAL scope so current_market_value equals each account's NAV contribution
--   (aggregating to fn_compute_nav OVER ACTIVE ACCOUNTS — see FOOT-TO-NAV PRECISION; the
--   SELF-225 consumer requirement); the SCOPE-MATCHING principle then forces cost_basis to carry the
--   SAME cash term so it cancels:
--     current_market_value = securities MV (qty × price × fx) + cash (roll-forward × fx)
--                          = the account's fn_compute_nav contribution → Σ over 049's
--                            (active-account) rows = fn_compute_nav OVER ACTIVE ACCOUNTS
--                            ONLY (see FOOT-TO-NAV PRECISION below).
--     cost_basis (investment) = securities carried book (GL trade_position × fx)
--                             + the SAME cash term (identical expression → cancels).
--     unrealized_gl (investment) = mv − cost_basis = securities MV − securities book
--                                = the securities G/L (cash cancels exactly).
--   COST_BASIS REDEFINITION (documented, load-bearing): under C, cost_basis is the
--     ACCOUNT-TOTAL BOOK (securities carried book + cash at face), NOT the AC#2-literal
--     "securities cost basis" alone. This is the deliberate price of a NAV-footing
--     current_market_value. unrealized_gl remains the pure securities G/L (the cash term is
--     book=market for cash, so it contributes zero gain and cancels). Consumers reading
--     cost_basis get total book cost; the securities-only cost basis is derivable as
--     (cost_basis − cash) if ever needed, or via a future per-lot helper.
--   CASH-TERM IDENTITY (the cancellation guarantee — why NOT fn_gl_entries asset_liability):
--     the cash term MUST be byte-identical in mv and cost_basis to cancel. fn_gl_entries's
--     cash leg (entry_class='asset_liability') is a PURE-LEDGER Σ(amount) with NO checkpoint
--     anchor, whereas the NAV-footing cash figure is the CHECKPOINT-ANCHORED roll-forward
--     (fn_compute_nav cash_leg). These DIVERGE whenever an account_balance_checkpoint
--     exists. So cost_basis's cash term reuses the SAME roll-forward cash_bal CTE as
--     current_market_value (NOT asset_liability) → cancellation holds by construction, and
--     current_market_value foots to NAV. cost_basis therefore consumes only fn_gl_entries
--     `trade_position` (securities book); the cash comes from the shared cash_bal CTE.
--
-- ----------------------------------------------------------------------------
-- BROKERAGE-CASH MODELING (confirmed against fn_compute_nav / 019 — the foot-to-NAV +
--   no-double-count check): brokerage cash is modeled as a BALANCE (account_balance_
--   checkpoint roll-forward = the cash_leg), NOT as a currency-type HOLDING. fn_holdings_as_of
--   returns securities only — cash rows carry security_id NULL / quantity 0 per the 017 CHECK,
--   so they never enter the security leg; and eod_price currency-type rows are FX rates
--   (source='fx_feed'), not cash positions. Therefore securities MV (fn_holdings_as_of) and
--   cash (account_balance_checkpoint) are DISJOINT by construction — current_market_value =
--   sec_mv + cash_bal counts each dollar exactly once and equals the account's fn_compute_nav
--   contribution (Σ over ACTIVE accounts = fn_compute_nav restricted to active accounts — see
--   FOOT-TO-NAV PRECISION below). No double-count, no omission. (Mirrors fn_compute_nav's own
--   two-leg split precisely; 049 shares the same double-count edge profile as NAV — V-6
--   sync-lag edges → V1.3 reconciliation, not this primitive.)
--
-- ----------------------------------------------------------------------------
-- FOOT-TO-NAV PRECISION (QA finding, verified): 049 filters `where acc.is_active` (PRD
--   §2.4.2 — inactive accounts are excluded from the current-state view), but fn_compute_nav
--   (019) has NO is_active filter — it sums ALL accounts. So the invariant is precisely:
--     Σ(049.current_market_value) = fn_compute_nav OVER ACTIVE ACCOUNTS ONLY.
--   The two equal fn_compute_nav exactly UNLESS a tenant holds a value-bearing INACTIVE
--   account, in which case fn_compute_nav is larger by that account's value. 049's is_active
--   filter is CORRECT as-is (current-state semantics, PRD §2.4.2); the fn_compute_nav scope
--   gap is a pre-existing 019 issue tracked separately as SELF-322 (fn_compute_nav is_active
--   scope gap — blocks SELF-225 per its AC).
--
-- ----------------------------------------------------------------------------
-- LOT-SPLIT FORWARD PATH (F/CTO ratify contingency — the GL-derived-basis-path answer):
--   Q: can the GL-derived `trade_position` book value be decomposed to per-lot
--      granularity via a future migration, or does per-lot REQUIRE the lot_match direct
--      path (Option B) — i.e. does choosing A now foreclose lot-level UI later?
--   A: A does NOT foreclose it. Per-lot decomposition is an ADDITIVE future read helper
--      over the SAME immutable inputs, reconcilable to this primitive by construction:
--      (1) The BUY / acquisition side is ALREADY per-lot: each buy account_trans row IS a
--          lot, and fn_gl_entries emits its P2 `trade_position` row keyed on
--          source_trans_id (= the buy trans_id) carrying that lot's cost_basis.
--      (2) The REMOVAL side aggregates per-SELL (037 sell_book sums matched lots into one
--          `- matched_book` row per sell_trans_id) — BUT the per-lot detail is fully
--          preserved in pfin.lot_match (append-only immutable, current max(match_seq)
--          batch: which buy_trans_id, how much quantity_matched). Nothing is lost; it is
--          only aggregated in the OUTPUT projection.
--      (3) So a future `fn_position_lots_as_of`-style helper reconstructs per-lot residual
--          basis = Σ over held lots of (remaining_qty × buy.cost_basis/buy.quantity) +
--          pro-rata basis_adjust, where remaining_qty = buy.quantity − Σ(lot_match
--          .quantity_matched, current batch, buy_trans_id = lot). It SUMS to the SAME
--          per-account total this primitive produces — in BOTH regimes:
--            • fully-matched sells → per-account Σ(per-lot residual) == Σ(trade_position)
--              EXACTLY.
--            • UNMATCHED sells → both leave the unremoved basis on the books (037's
--              graceful-degradation Suspense floor: an unmatched sell parks proceeds in
--              Suspense and removes NO position basis; a per-lot helper likewise sees no
--              lot_match rows → no lot's remaining_qty reduced), so they STILL agree with
--              each other. Consistency holds even in the degraded case.
--      (4) The ONE reconciliation invariant a future per-lot helper must preserve: the
--          SAME lot_match-driven removal + the SAME pro-rata basis_adjust allocation
--          convention (037 allocates position-level basis_adjust deltas to sold shares
--          PRO-RATA by share count). Strict per-lot basis_adjust attribution is the one
--          documented future REFINEMENT (037 V1 CONVENTION NOTE) that would introduce a
--          BOUNDED, deliberate divergence on basis_adjust'd securities — not accidental
--          drift.
--   CONCLUSION: A keeps ONE basis truth now (== GL == tax fn_compute_tax_liability ==
--     reports) and admits a finer per-lot projection later with zero rearchitecture.
--     This REINFORCES A over B — B would have committed the direct path prematurely and
--     forked a second basis truth. Lot-level UI is V2 anyway (schema captures lots from
--     day one; lot-level UI is V2 — the standing project line).
--
-- ----------------------------------------------------------------------------
-- Numbering: 049 follows 048 (drop_account_sub_cat). Pure read helper over already-landed
--   tables + fns — order-independent among helpers, sequenced after the GL track. Depends
--   on: 003 (pfin.account — account_id/account_type/currency/is_active + direct-owner RLS),
--   019 (fn_holdings_as_of + fn_compute_nav's fx/cash idioms, reproduced verbatim for
--   consistency; eod_price D-first LOCF; account_balance_checkpoint), 035+037 (fn_gl_entries
--   — the `trade_position` basis source), 015 (account.currency), 016 (pfin.asset —
--   currency/asset_type/symbol/users_id the fx leg joins). No downstream migration depends
--   on 049.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT SECURITY
--   DEFINER. fn_account_unrealized_gl reads pfin base tables + INVOKER fns and needs NO
--   elevated privilege: it composes ENTIRELY under the caller's RLS, exactly like
--   fn_compute_nav / fn_holdings_as_of / fn_gl_entries. Every base read (pfin.account
--   direct-owner; fn_holdings_as_of + fn_gl_entries already RLS-scoped INVOKER;
--   account_balance_checkpoint / account_trans rd_access-JOIN; eod_price / asset
--   global-OR-owned) is filtered to the caller because INVOKER runs as the caller. A
--   cross-tenant caller sees NO account rows → the driving `from pfin.account` yields
--   nothing → empty result set (fails closed). set search_path = '' is the privesc fence.
--   DEFINER would BREAK tenant isolation here (it would read every tenant's positions) —
--   INVOKER is load-bearing, not stylistic. → DEFINER allowlist UNCHANGED at 4.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list. Decision 4 read verbatim before drafting.) 049 introduces
--   ZERO catalogued §10 instances; the ledger STAYS at 3 (RT-22 + RT-26 + RT-27).
--   (i)   Instance-numbering: RT-22 first, RT-26 second, RT-27 third — unchanged.
--   (ii)  Layer-attribution: a single authenticated-tier INVOKER READ function — no
--         service_role grant, no credential, no admission/network-exposure/config surface.
--         RT-22 (PDF-worker container), RT-26 (SUPABASE_SERVICE_ROLE_KEY source grep fence),
--         RT-27 (admission inbound fence) untouched. Nothing becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated. 049 is not the anchor.
--   DE-CONFLATION GUARD: this helper READS existing FKs (via the composed fns) — it adds
--   no reference column → Decision-3 family UNCHANGED, no new instance.
--
-- LEDGER DELTAS (confirmed): §10 catalogued instances = 3 (unchanged) · SECURITY DEFINER
--   allowlist = 4 (unchanged; this is INVOKER — authored DEFINER fns stay 3:
--   fn_refresh_updated_at @001, fn_grant_creator_access @003, fn_reclass_history_insert
--   @031) · Decision-3 family = unchanged (no new FK-shaped column).
--
-- ----------------------------------------------------------------------------
-- JOINT-REVIEW-MANDATORY (Sec veto surface): this is a FINANCIAL CALCULATION over
--   MULTI-TENANT-ISOLATED data — Sec joint-review is required even though no DEFINER / no
--   Decision-3 extension / no §10 ledger change. Security-load-bearing edge = INVOKER
--   cross-tenant caller → empty/own-only set (fails closed). RLS verification routes to the
--   SELF-228 two-tenant RLS battery (AC#5). QA pgTAP pairing ships same-PR (SECURITY §4.5).
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_account_unrealized_gl(p_as_of date default current_date)
--     RETURNS TABLE(account_id bigint, current_market_value numeric, cost_basis numeric,
--                   unrealized_gl numeric) — SECURITY INVOKER, STABLE, set search_path=''.
--     One row per NON-INACTIVE (account.is_active) account visible to the caller.
--     current_market_value (ALL account types — uniform, DESIGN C, foots to NAV):
--         = securities MV [Σ(fn_holdings_as_of qty × best-available eod_price[D-first
--           source-priority LOCF, V-3/V-4] × fx→USD)] + cash [roll-forward balance × fx→USD].
--           = the account's fn_compute_nav contribution → Σ over 049's rows = fn_compute_nav
--           OVER ACTIVE ACCOUNTS ONLY (049 filters is_active; fn_compute_nav/019 does not —
--           see FOOT-TO-NAV PRECISION). For a
--           depository/liability account securities MV = 0 (no holdings) → value = the cash
--           balance (liabilities R-7 signed naturally negative). Securities & cash are
--           disjoint (BROKERAGE-CASH MODELING above) → each dollar counted once.
--     INVESTMENT-CLASS accounts — account_type ∈ ('investment','retirement','crypto')
--       (ADR-002 §1.9 / 003 CHECK):
--         cost_basis    = securities carried book [Σ(fn_gl_entries `trade_position` × fx→USD)
--           — acquisition + basis_adjust − FIFO/specific-lot matched-sell removal; single
--           basis truth == GL == tax == reports; unmatched sells leave basis on the books
--           per 037's Suspense floor] + the SAME cash term as current_market_value (the
--           shared cash_bal CTE — identical expression → cancels). DESIGN C REDEFINITION:
--           cost_basis is the ACCOUNT-TOTAL BOOK (securities book + cash at face), NOT the
--           AC#2-literal securities-only cost basis (see MARKET-VALUE SCOPE — DESIGN C).
--         unrealized_gl = current_market_value − cost_basis = securities MV − securities
--           book = the pure securities G/L (the identical cash term cancels exactly).
--     NON-INVESTMENT — depository / manual_other / real_estate / liability (003 CHECK
--       values; NB the AC's "manual"/"liabilities" are loose — actual: manual_other /
--       liability):
--         cost_basis = NULL, unrealized_gl = NULL  (NULL, NOT zero — discriminates
--           "concept does not apply" from "$0"; AC#3). An investment account with no
--           holdings returns (cash, cash, 0): concept applies; securities G/L is zero.
--     AS-OF (AC#4 / Lock 15 Decision 19 app-layer threading; server-derived-only per Lock
--       15 mod #2 — V1.1 consumers always pass CURRENT_DATE): p_as_of < current_date reads
--       historical eod_price (LOCF ≤ as_of) + account_trans / lot_match history ≤ as_of, by
--       construction of the composed fns (all thread p_as_of).
--   Security-load-bearing edges: INVOKER (cross-tenant caller → empty set, fails closed);
--     unpriced asset → NULL price term → SUM drops it → 0 ("needs valuation"), never NaN
--     (fn_compute_nav precedent); cost_basis via fn_gl_entries is the single basis truth
--     (== GL == tax == reports). GRANT to authenticated only; public REVOKED.
-- ============================================================================

create schema if not exists pfin;

create or replace function pfin.fn_account_unrealized_gl(p_as_of date default current_date)
returns table (
  account_id            bigint,
  current_market_value  numeric,
  cost_basis            numeric,
  unrealized_gl         numeric
)
language sql
security invoker
set search_path = ''
as $$
  with
  -- SECURITIES MARKET value per account (USD): fn_holdings_as_of qty × best-available
  -- price × fx. Reproduces fn_compute_nav's security-leg valuation VERBATIM (V-1..V-4):
  -- price = D-FIRST (latest price_date ≤ as_of; same-date tie → source rank
  -- manual_valuation(1) > market_feed/spot_feed/fx_feed(2) > provider_implied(3) — the
  -- actual CASE ranks below); fx via the asset's currency-asset
  -- fx_feed (USD ≡ 1.0). Unpriced asset → NULL term → SUM drops it → 0, never NaN.
  sec_mv as (
    select
      h.account_id,
      coalesce(sum(
        h.quantity
        * (select ep.price
           from pfin.eod_price ep
           where ep.asset_id = h.asset_id and ep.price_date <= p_as_of
           order by ep.price_date desc,
                    case ep.source
                      when 'manual_valuation' then 1
                      when 'market_feed'      then 2
                      when 'spot_feed'        then 2
                      when 'fx_feed'          then 2
                      when 'provider_implied' then 3
                      else 4
                    end
           limit 1)
        * case when a.currency = 'USD' then 1.0
               else coalesce((
                 select fx.price from pfin.eod_price fx
                 join pfin.asset ca on ca.asset_id = fx.asset_id
                 where ca.users_id is null and ca.asset_type = 'currency'
                   and ca.symbol = a.currency and fx.source = 'fx_feed'
                   and fx.price_date <= p_as_of
                 order by fx.price_date desc limit 1), 1.0) end
      ), 0) as mv_usd
    from pfin.fn_holdings_as_of(p_as_of) h
    join pfin.asset a on a.asset_id = h.asset_id
    group by h.account_id
  ),

  -- SECURITIES CARRIED BOOK per account (USD): the GL-derived cost-basis path —
  -- Σ(fn_gl_entries `trade_position` amount_book) per account, fx-normalized to USD (the
  -- GL amount_book is in the account's NATIVE currency). This is the current carried book
  -- (acquisition + basis_adjust − matched-sell removal, FIFO/specific-lot via lot_match),
  -- balanced-by-construction. SINGLE BASIS TRUTH (== GL == tax == reports). Design C adds
  -- the shared cash_bal term to this at the projection (so cost_basis = account-total book).
  sec_basis as (
    select
      g.account_id,
      coalesce(sum(
        g.amount_book
        * case when g.currency = 'USD' then 1.0
               else coalesce((
                 select fx.price from pfin.eod_price fx
                 join pfin.asset ca on ca.asset_id = fx.asset_id
                 where ca.users_id is null and ca.asset_type = 'currency'
                   and ca.symbol = g.currency and fx.source = 'fx_feed'
                   and fx.price_date <= p_as_of
                 order by fx.price_date desc limit 1), 1.0) end
      ), 0) as basis_usd
    from pfin.fn_gl_entries(p_as_of) g
    where g.entry_class = 'trade_position'
    group by g.account_id
  ),

  -- CASH BALANCE per account (USD): roll-forward (account_balance_checkpoint anchor ≤
  -- as_of + Σ amounts strictly-after) × fx. Reproduces fn_compute_nav's cash_leg VERBATIM
  -- (per account, not summed). Liabilities R-7 signed naturally negative (no branch).
  -- DESIGN C: this SAME figure feeds BOTH current_market_value (all types) AND the
  -- investment cost_basis cash term — the shared expression is what makes them cancel and
  -- what makes current_market_value foot to NAV (NOT fn_gl_entries asset_liability, which is
  -- a pure-ledger Σ that diverges when a checkpoint exists — see CASH-TERM IDENTITY above).
  cash_bal as (
    select
      acc.account_id,
      (
        coalesce((select cbc.balance
                  from pfin.account_balance_checkpoint cbc
                  where cbc.account_id = acc.account_id and cbc.as_of_date <= p_as_of
                  order by cbc.as_of_date desc, cbc.balance_id desc
                  limit 1), 0)
        + coalesce((select sum(at.amount)
                    from pfin.account_trans at
                    where at.account_id = acc.account_id
                      and at.transaction_date <= p_as_of
                      and at.transaction_date > coalesce((
                        select cbc2.as_of_date
                        from pfin.account_balance_checkpoint cbc2
                        where cbc2.account_id = acc.account_id and cbc2.as_of_date <= p_as_of
                        order by cbc2.as_of_date desc, cbc2.balance_id desc
                        limit 1), '-infinity'::date)), 0)
      )
      * case when acc.currency = 'USD' then 1.0
             else coalesce((
               select fx.price from pfin.eod_price fx
               join pfin.asset ca on ca.asset_id = fx.asset_id
               where ca.users_id is null and ca.asset_type = 'currency'
                 and ca.symbol = acc.currency and fx.source = 'fx_feed'
                 and fx.price_date <= p_as_of
               order by fx.price_date desc limit 1), 1.0) end
      as bal_usd
    from pfin.account acc
  )

  -- One row per NON-INACTIVE account visible to the caller (pfin.account is INVOKER-scoped
  -- → cross-tenant caller sees no rows → empty set, fails closed). DESIGN C (account-total,
  -- symmetric): current_market_value = securities MV + cash for ALL types (foots to NAV over
  -- active accounts — 049 filters is_active, 019 does not; see FOOT-TO-NAV PRECISION header);
  -- for investments cost_basis = securities book + the SAME cash term (cancels) and
  -- unrealized_gl = securities MV − securities book (= mv − cost_basis by construction);
  -- non-investments get NULL cost_basis/unrealized_gl (NULL ≠ 0 — concept-does-not-apply).
  select
    acc.account_id,
    -- UNIFORM (all types): securities MV + cash → the account's fn_compute_nav contribution.
    coalesce(smv.mv_usd, 0) + coalesce(cb.bal_usd, 0) as current_market_value,
    case
      when acc.account_type in ('investment', 'retirement', 'crypto')
        -- securities carried book + the SAME cash term as current_market_value (cancels).
        then coalesce(sb.basis_usd, 0) + coalesce(cb.bal_usd, 0)
      else null
    end as cost_basis,
    case
      when acc.account_type in ('investment', 'retirement', 'crypto')
        -- = current_market_value − cost_basis (the identical cash term cancels exactly).
        then coalesce(smv.mv_usd, 0) - coalesce(sb.basis_usd, 0)
      else null
    end as unrealized_gl
  from pfin.account acc
  left join sec_mv    smv on smv.account_id = acc.account_id
  left join sec_basis sb  on sb.account_id  = acc.account_id
  left join cash_bal  cb  on cb.account_id  = acc.account_id
  where acc.is_active
  order by acc.account_id;
$$;

revoke execute on function pfin.fn_account_unrealized_gl(date) from public;
grant execute on function pfin.fn_account_unrealized_gl(date) to authenticated;

comment on function pfin.fn_account_unrealized_gl(date) is
  'SECURITY INVOKER per-account unrealized-G/L aggregation primitive (V1.1 "Net worth full"; '
  'PRD §2.1.5.a / SELF-224; shared with §2.2 asset-allocation V1.2; Lock 11 read-composition — '
  'clones the fn_compute_nav / fn_gl_entries posture). One row per non-inactive account visible '
  'to the caller. DESIGN C (account-total, symmetric; ADR-038, F/CTO 2026-08-02). '
  'current_market_value (ALL types, uniform) = securities MV [Σ(fn_holdings_as_of qty × '
  'best-available eod_price[D-first LOCF] × fx→USD)] + cash [roll-forward balance × fx→USD] = '
  'the account''s fn_compute_nav contribution → Σ over ACTIVE accounts = fn_compute_nav OVER '
  'ACTIVE ACCOUNTS ONLY (049 filters is_active per PRD §2.4.2; fn_compute_nav/019 does not — '
  'they diverge only on a value-bearing inactive account; that 019 scope gap is tracked as '
  'SELF-322, 049''s is_active filter is correct). (securities & cash '
  'disjoint per the 017 CHECK — counted once). INVESTMENT-class (account_type ∈ investment/'
  'retirement/crypto, 003 CHECK): cost_basis = securities carried book [Σ(fn_gl_entries '
  '`trade_position` × fx→USD) — acquisition + basis_adjust − FIFO/specific-lot matched-sell '
  'removal; single basis truth == GL == tax == reports; unmatched sells leave basis on the '
  'books per 037 Suspense floor] + the SAME roll-forward cash term as mv (the shared cash '
  'figure → cancels; NOT fn_gl_entries asset_liability, a pure-ledger Σ that diverges when a '
  'checkpoint exists). REDEFINITION: cost_basis is the ACCOUNT-TOTAL BOOK (securities book + '
  'cash face), not AC#2-literal securities-only. unrealized_gl = current_market_value − '
  'cost_basis = securities MV − securities book (pure securities G/L; cash cancels exactly). '
  'NON-INVESTMENT (depository/manual_other/real_estate/liability): cost_basis = unrealized_gl = '
  'NULL (NOT 0 — concept-does-not-apply discriminator; a zero-everything investment account '
  'returns 0/0/0). AS-OF (Lock 15 Decision 19; server-derived-only per Lock 15 mod #2, V1.1 '
  'consumers pass CURRENT_DATE): the composed fns thread p_as_of → historical eod_price + '
  'account_trans / lot_match ≤ as_of. INVOKER → cross-tenant caller sees no rows (fails closed); '
  'unpriced asset → NULL term → dropped → 0, never NaN. Per-lot decomposition is an additive '
  'future helper (buy side already per-lot; removal detail preserved in immutable lot_match), '
  'reconcilable by construction — the GL-derived basis path does not foreclose lot-level UI (V2). '
  'set search_path=''''; NOT a DEFINER allowlist entry (INVOKER) — allowlist stays 4; §10 ledger '
  'stays 3; Decision-3 unchanged (no new FK column). Sec joint-review-mandatory (financial calc + '
  'multi-tenant); RLS verification → SELF-228 two-tenant battery.';

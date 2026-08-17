-- ============================================================================
-- Migration: the price-pick kernel's same-date tie-break made TOTAL, applied to
-- every live copy of the kernel in ONE migration.
-- Phase 6 Build Loop. Sec joint-review ruling (1) on PR #480 / SELF-237, quoted
-- in the DEFECT block below. Closes no SD/RT; extends no lock.
--
-- ----------------------------------------------------------------------------
-- THE DEFECT, AS THE CANONICAL RECORD STATES IT.
--   `pfin.eod_price` is unique on (asset_id, price_date, source) — deliberately,
--   so sources coexist and stay provenance-distinct (019, OWD-A). The price pick
--   is therefore a `limit 1` over a set that can hold SEVERAL rows for one
--   (asset_id, price_date), ordered by:
--       price_date desc, then a source-rank CASE.
--   That CASE assigns rank 2 to THREE distinct sources — 'market_feed',
--   'spot_feed' and 'fx_feed'. So an asset carrying two of them on the SAME
--   price_date has two rows tied on both ordering keys, the order is not total,
--   and `limit 1` resolves NONDETERMINISTICALLY: two runs of the same query
--   against the same unchanged data can return two different prices, hence two
--   different NAVs.
--   076's header flagged this and deliberately did NOT alter it, because a fix in
--   one copy would fork the kernel. Sec's joint-review ruling (1) on PR #480
--   rejected accept-with-record as "a promise with no watcher" and set the
--   vehicle and the shape: "one PR adding a final `price_id desc` tiebreak to ALL
--   copies atomically — the only form preserving the protected property; owner
--   Architect; sequenced BEFORE SELF-238/240 ship (the first surfaces where two
--   runs producing two numbers becomes product-visible)."
--   This migration is that PR's DDL half. The shape is Sec's, not a redesign:
--   `ep.price_id` is a `bigint generated always as identity primary key` (019),
--   so appending `ep.price_id desc` makes the ordering TOTAL by construction —
--   there is no remaining tie it cannot break — and resolves a same-date
--   same-rank tie to the most recently INSERTED observation.
--
-- ----------------------------------------------------------------------------
-- WHY ALL COPIES IN ONE MIGRATION — the protected property.
--   The house treats TEXTUAL IDENTITY of the kernel as the correctness mechanism
--   (076: "copies that read identically can be diffed; copies that read
--   differently cannot"). Fixing one copy would destroy exactly that property and
--   leave two valuation surfaces silently disagreeing on the same portfolio. So
--   the fix is atomic across copies or it is a regression.
--
--   ⚠ WHICH COPIES — and the distinction that matters. Sec's independent
--   measurement extracted and whitespace-normalized the kernel block from EVERY
--   occurrence in migration text — EIGHT blocks across SIX files (019 / 049 /
--   050 / 056×2 / 059×2 / 076) — and got ONE hash. (Sec's PR #480 record states
--   this as "ALL SIX copies"; that count and its enumeration were both wrong and
--   are corrected here at Sec's own instruction — 056 carries two kernel blocks,
--   not one, so SIX is the FILE count, not the COPY count. The ONE-hash result
--   held over all eight, re-measured 2026-08-17 by Sec and independently by
--   Architect.)
--   That count is over MIGRATION TEXT — the history of the kernel.
--   The count over LIVE CATALOG DEFINITIONS is smaller, because 019 / 049 / 050 /
--   056 were each superseded by a later CREATE OR REPLACE of the same signature.
--   Only these carry the kernel in the catalog today, and they are exactly the
--   three recreated below:
--     · pfin.fn_account_unrealized_gl(date)            — live definition from 059
--     · pfin.fn_compute_nav(date, boolean)             — live definition from 059
--     · pfin.fn_subcat_market_value(date, boolean)     — live definition from 076
--   The superseded copies are APPLIED HISTORY and are NOT edited — editing an
--   applied migration's SQL is out under every framing. Verified before drafting
--   by whitespace-normalized hash of the three live kernel blocks: ONE hash,
--   matching Sec's.
--   NOT kernel-bearing, checked rather than assumed: pfin.fn_compute_nav(date)
--   is a pure delegation to the 2-arg form (050), and pfin.fn_nav_composition(date)
--   composes on fn_account_unrealized_gl (059). Neither re-derives a price, so
--   both inherit this fix for free and neither is touched here.
--
-- ----------------------------------------------------------------------------
-- WHAT ELSE WAS CHECKED FOR THE SAME DEFECT CLASS, AND FOUND TOTAL. Stated as a
--   negative result, because "we fixed the one we were told about" is not the
--   same claim as "the selectors in these functions are now deterministic".
--   The FX sub-select — `order by fx.price_date desc limit 1` with no tie-break —
--   is ALSO a limit-1 over a filtered set, and it is total for two independent
--   reasons, either sufficient: (a) it pins `fx.source = 'fx_feed'`, and
--   eod_price is unique on (asset_id, price_date, source), so at most one row
--   survives per (asset, date); (b) it resolves the currency asset through
--   `asset_global_symbol_uniq` — `unique(symbol) where users_id is null` (016) —
--   so at most one global currency asset answers a given symbol. It is therefore
--   left EXACTLY as shipped, in every copy, and the kernel's textual identity is
--   preserved there too.
--
-- ----------------------------------------------------------------------------
-- SCOPE — mechanically bounded, so the review can be about the fix rather than
--   about what else moved. Each function below is the byte-for-byte live
--   definition, with ONE two-line substitution at its price-pick site:
--       ...  else 4                        ...  else 4
--            end                 becomes        end,
--       limit 1)                                ep.price_id desc
--                                          limit 1)
--   Three sites, three identical substitutions, nothing else changed — not a
--   comment, not a predicate, not a whitespace column. The PR body carries the
--   diff proof.
--   CREATE OR REPLACE (never DROP): grants and catalog comments are attributes of
--   the function and survive a REPLACE, so the 072 lesson — a DROP+recreate
--   destroys the ACL surface and lands PUBLIC-executable — does not apply and no
--   ACL or comment is re-issued here. Re-issuing them would be the risk, not the
--   safeguard.
--
-- ⚠ ORDER DEPENDENCY WITH 079 (this same branch). 079 pins these functions
--   STABLE via ALTER FUNCTION. CREATE OR REPLACE replaces the WHOLE definition
--   including its volatility, so 078 MUST run BEFORE 079 or the pin is erased.
--   The general form, for whoever writes the next one: any future CREATE OR
--   REPLACE of these functions must carry `stable` in its own body, or re-ALTER.
--   QA's structural provolatile pin is the watcher for that; this note is not.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT
--   SECURITY DEFINER. Unchanged from the definitions being replaced: all three
--   are read-composition primitives whose tenant isolation is INHERITED from the
--   RLS on every relation they read, evaluated under the caller's own session.
--   `set search_path` is carried through verbatim from each source definition.
--   The SECURITY DEFINER allowlist is UNCHANGED — no function is authored, only
--   re-bodied; read the allowlist live at ADR-011 Decision 9.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — ADR-011 Decision 4 referenced, NOT restated;
-- no count carried, deliberately). Decision 4 read verbatim and live before
-- drafting. This migration introduces ZERO catalogued §10 instances: it changes
-- an ORDER BY inside three read-only SQL functions — no credential surface, no
-- code-layer fence, no network/config surface.
--   (i)   Instance-numbering: UNCHANGED — nothing added, removed, or reordered.
--   (ii)  Layer-attribution: UNCHANGED — no catalogued instance's layer moves; no
--         surface becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is LINKED, not restated.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED set are different sets; neither is
--   changed here and they are not reconciled. The kernel-identity CI fence Sec
--   proposed is a DevOps item that lands after this — see the note below.
--
--   FORWARD NOTE FOR THE KERNEL-IDENTITY FENCE (DevOps, separate item). Sec's
--   proposed control extracts the price-pick block "from every migration
--   containing the manual_valuation rank clause" and asserts ONE distinct hash.
--   After this migration that predicate spans two kernel generations — the
--   superseded copies in applied history and the fixed copies here — so a fence
--   scoped to "every migration" would go red on correct code. The fence must be
--   scoped to the LIVE definition of each kernel-bearing function (latest
--   CREATE OR REPLACE wins), which is the set this migration establishes.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family UNCHANGED (+0),
--   in the honest form: no column exists to check. This migration creates,
--   alters and drops nothing — no table, no column, no FK, no INTEGER[] array.
--   The one identifier it adds to a query, `ep.price_id`, is eod_price's own
--   primary key read inside an ORDER BY; it is not a stored reference and cannot
--   cross a tenant boundary. Read ADR-011 Decision 3 live for the family; this
--   file carries no tally.
--
-- ----------------------------------------------------------------------------
-- CONTRACT — no signature, return type, posture, grant or comment changes on any
--   of the three functions. The ONE behavioural change, stated precisely because
--   it is the kind that hides:
--     BEFORE — for an asset with two or more same-price_date observations whose
--       sources share rank 2, the price returned was one of them, unspecified.
--     AFTER  — it is the one with the greatest price_id, i.e. the most recently
--       inserted, deterministically.
--   ⚠ THIS IS NOT VALUE-NEUTRAL, AND SAYING SO IS THE POINT. On data with no
--   same-date same-rank tie the output is identical, which is most fixtures —
--   so a battery that only asserts totals will go green whether or not this
--   migration applied. The assertion that discriminates is a fixture that PLANTS
--   the tie (one asset, one price_date, two rank-2 sources, two different prices)
--   and asserts the higher price_id wins, repeatably. Without that leg the fix
--   has no watcher.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- (1) pfin.fn_account_unrealized_gl(date) — live definition from 059, price-pick
-- site made total. Everything else byte-identical.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pfin.fn_account_unrealized_gl(p_as_of date DEFAULT CURRENT_DATE)
 RETURNS TABLE(account_id bigint, current_market_value numeric, cost_basis numeric, unrealized_gl numeric)
 LANGUAGE sql
 SET search_path TO ''
AS $function$
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
                    end,
                    ep.price_id desc
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

  -- CASH BALANCE per account (USD): pfin.fn_account_cash_as_of(p_as_of) x fx.
  -- The roll-forward itself now lives in ONE place (056); this CTE only
  -- fx-normalizes it. LEFT JOIN + coalesce so a totality breach degrades to 0
  -- (the pre-extraction behaviour) rather than to a missing account. Liabilities R-7 signed naturally negative (no branch).
  -- DESIGN C: this SAME figure feeds BOTH current_market_value (all types) AND the
  -- investment cost_basis cash term — the shared expression is what makes them cancel and
  -- what makes current_market_value foot to NAV (NOT fn_gl_entries asset_liability, which is
  -- a pure-ledger Σ that diverges when a checkpoint exists — see CASH-TERM IDENTITY above).
  cash_bal as (
    select
      acc.account_id,
      coalesce(c.balance_native, 0)
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
    left join pfin.fn_account_cash_as_of(p_as_of) c
      on c.account_id = acc.account_id
  )

  -- One row per NON-INACTIVE account visible to the caller (pfin.account is INVOKER-scoped
  -- → cross-tenant caller sees no rows → empty set, fails closed). DESIGN C (account-total,
  -- symmetric): current_market_value = securities MV + cash for ALL types (foots to NAV over
  -- active accounts — 049 filters by closed_at as-of (the retired boolean flag, dropped at 059), 019 does not; see FOOT-TO-NAV PRECISION header);
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
  where (acc.closed_at is null or acc.closed_at::date > p_as_of)
  order by acc.account_id;
$function$

;

-- ----------------------------------------------------------------------------
-- (2) pfin.fn_compute_nav(date, boolean) — live definition from 059, price-pick
-- site made total. Everything else byte-identical.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pfin.fn_compute_nav(p_as_of date, p_active_only boolean)
 RETURNS numeric
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  with security_leg as (
    select coalesce(sum(
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
                  end,
                  ep.price_id desc
         limit 1)
      * case when a.currency = 'USD' then 1.0
             else coalesce((
               select fx.price from pfin.eod_price fx
               join pfin.asset ca on ca.asset_id = fx.asset_id
               where ca.users_id is null and ca.asset_type = 'currency'
                 and ca.symbol = a.currency and fx.source = 'fx_feed'
                 and fx.price_date <= p_as_of
               order by fx.price_date desc limit 1), 1.0) end
    ), 0) as v
    from pfin.fn_holdings_as_of(p_as_of) h
    join pfin.asset a on a.asset_id = h.asset_id
    left join pfin.account acc2 on acc2.account_id = h.account_id
    where (not p_active_only or (acc2.account_id is not null and (acc2.closed_at is null or acc2.closed_at::date > p_as_of)))
  ),
  cash_leg as (
    select coalesce(sum(
      coalesce(c.balance_native, 0)
      * case when acc.currency = 'USD' then 1.0
             else coalesce((
               select fx.price from pfin.eod_price fx
               join pfin.asset ca on ca.asset_id = fx.asset_id
               where ca.users_id is null and ca.asset_type = 'currency'
                 and ca.symbol = acc.currency and fx.source = 'fx_feed'
                 and fx.price_date <= p_as_of
               order by fx.price_date desc limit 1), 1.0) end
    ), 0) as v
    from pfin.account acc
    left join pfin.fn_account_cash_as_of(p_as_of) c
      on c.account_id = acc.account_id
    where (not p_active_only or (acc.closed_at is null or acc.closed_at::date > p_as_of))
  )
  select (select v from security_leg) + (select v from cash_leg);
$function$

;

-- ----------------------------------------------------------------------------
-- (3) pfin.fn_subcat_market_value(date, boolean) — live definition from 076,
-- price-pick site made total. Everything else byte-identical, `stable` included.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_subcat_market_value(
  p_as_of               date    default current_date,
  p_include_real_estate boolean default false
)
returns table (
  sub_cat_id   bigint,
  cat          text,
  sub_cat      text,
  market_value numeric
)
language sql
security invoker
stable
set search_path = ''
as $$
  with sec_leg as (
    -- Securities: fn_holdings_as_of per-(account, asset) quantity × price × fx.
    -- Kernel copied verbatim from 059's fn_compute_nav securities leg.
    -- CLOSURE PREDICATE (059): pfin.account is reached by LEFT JOIN here, so the
    -- three-conjunct form is mandatory — acc2.account_id is not null AND the
    -- dated test. A bare closed_at-is-null would fail OPEN on a join miss.
    -- CLASSIFICATION: LEFT JOIN the junction and the taxonomy, so an unclassified
    -- (or non-asset-classified) holding keeps its value and lands under a NULL key.
    select
      ut.id                                                as k_id,
      ut.cat                                               as k_cat,
      ut.sub_cat                                           as k_sub_cat,
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
                  end,
                  ep.price_id desc
         limit 1)
      * case when a.currency = 'USD' then 1.0
             else coalesce((
               select fx.price from pfin.eod_price fx
               join pfin.asset ca on ca.asset_id = fx.asset_id
               where ca.users_id is null and ca.asset_type = 'currency'
                 and ca.symbol = a.currency and fx.source = 'fx_feed'
                 and fx.price_date <= p_as_of
               order by fx.price_date desc limit 1), 1.0) end   as v
    from pfin.fn_holdings_as_of(p_as_of) h
    join pfin.asset a on a.asset_id = h.asset_id
    left join pfin.account acc2 on acc2.account_id = h.account_id
    left join pfin.user_asset_category uac on uac.asset_id = h.asset_id
    left join pfin.user_taxonomy ut
      on ut.id = uac.sub_cat_id and ut.domain = 'asset'
    where acc2.account_id is not null
      and (acc2.closed_at is null or acc2.closed_at::date > p_as_of)
  ),
  cash_leg as (
    -- Cash: per-account balance × fx, classified through the GLOBAL
    -- currency-asset's per-user junction row (the 022 cash-via-currency-asset
    -- model). See L1 in the header — this yields ONE Sub-Cat per user per
    -- currency; it cannot distinguish cash Sub-Cats per account.
    -- pfin.account is joined DIRECTLY here (not left-joined), so the bare
    -- two-clause 059 predicate is correct and the three-conjunct form is not
    -- needed — the 049 / 059 cash-leg shape.
    select
      ut.id       as k_id,
      ut.cat      as k_cat,
      ut.sub_cat  as k_sub_cat,
      coalesce(c.balance_native, 0)
      * case when acc.currency = 'USD' then 1.0
             else coalesce((
               select fx.price from pfin.eod_price fx
               join pfin.asset ca on ca.asset_id = fx.asset_id
               where ca.users_id is null and ca.asset_type = 'currency'
                 and ca.symbol = acc.currency and fx.source = 'fx_feed'
                 and fx.price_date <= p_as_of
               order by fx.price_date desc limit 1), 1.0) end   as v
    from pfin.account acc
    left join pfin.fn_account_cash_as_of(p_as_of) c
      on c.account_id = acc.account_id
    left join pfin.asset cur
      on cur.users_id is null
     and cur.asset_type = 'currency'
     and cur.symbol = acc.currency
    left join pfin.user_asset_category uac on uac.asset_id = cur.asset_id
    left join pfin.user_taxonomy ut
      on ut.id = uac.sub_cat_id and ut.domain = 'asset'
    where (acc.closed_at is null or acc.closed_at::date > p_as_of)
      -- ZERO-CASH ACCOUNTS EMIT NO ROW. fn_account_cash_as_of is TOTAL over
      -- pfin.account, so without this every open account would contribute a
      -- 0-valued row. Harmless when summed to a scalar (fn_compute_nav), NOT
      -- harmless here: those rows group under the NULL key and manufacture a
      -- phantom UNCLASSIFIED row of 0.00 for any caller who has an account and
      -- nothing unclassified — which SELF-238 would render as an "Unsorted"
      -- line for essentially every user. Measured on the scratch chain before
      -- this filter existed. It also restores the contract's empty-portfolio
      -- promise (empty set, not a row of zeros).
      and coalesce(c.balance_native, 0) <> 0
  ),
  both_legs as (
    select k_id, k_cat, k_sub_cat, v from sec_leg
    union all
    select k_id, k_cat, k_sub_cat, v from cash_leg
  )
  select
    b.k_id                     as sub_cat_id,
    b.k_cat                    as cat,
    b.k_sub_cat                as sub_cat,
    coalesce(sum(b.v), 0)      as market_value
  from both_legs b
  -- REAL-ESTATE EXCLUSION (AC3): `is distinct from` rather than `<>` so the
  -- UNCLASSIFIED group (k_cat IS NULL) survives — an unknown cat cannot be known
  -- to be Real Estate, and dropping it here would re-open the R2 money leak
  -- through the back door.
  where p_include_real_estate or b.k_cat is distinct from 'Real Estate'
  group by b.k_id, b.k_cat, b.k_sub_cat
$$;

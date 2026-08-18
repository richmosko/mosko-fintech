-- ============================================================================
-- Migration: pfin.fn_subcat_market_value — route LIABILITY-type accounts' cash to
-- the Liabilities catch-all Sub-Cat instead of the per-currency raw-cash bucket.
-- Phase 6 Build Loop. Account-type-aware cash routing, F/CTO-ratified 2026-08-17
-- (Option B of the Architect design pass). Closes no SD/RT; extends no lock.
--
-- ----------------------------------------------------------------------------
-- THE DEFECT. A connected credit card's negative balance reaches this function's
--   cash leg like any other account's, and the cash leg classifies through the
--   GLOBAL currency-asset's single per-user 022 junction row. That yields ONE
--   classification per user per currency (the L1 model), so card debt NETS INTO
--   the raw-cash row rather than surfacing under Liabilities.
--   The GL beneath is correct and is NOT touched here: per-account signed
--   balances are right, and fn_nav_composition already groups by account_type,
--   so its Debt subtotal was never wrong. The defect is confined to the
--   ALLOCATION-CLASSIFICATION layer, which was account-type-blind for cash.
--   041's own seed is the tell that this was never intended: 'Credit-Balance' is
--   described as "Credit Card or other Revolving Credit Balance" — a home the
--   taxonomy promised card balances and the substrate could not deliver them to.
--
-- ----------------------------------------------------------------------------
-- THE RULE, AND WHAT IT DELIBERATELY IS NOT.
--   Cash of an account whose account_type = 'liability' routes to the seeded
--   'Liabilities' / 'Liability Balances' row in the caller's OWN taxonomy (080).
--   Every other account keeps the currency-asset classification, unchanged.
--   ⚠ MECHANICAL — no user choice, no UI, no per-account decision, no new
--   column. PRD §2.2.1 defers USER-DECIDED per-account cash classification to V2
--   ("bank cash → FDIC, brokerage cash → SPIC, decided account-by-account");
--   F/CTO ratified 2026-08-17 that the fence defers that decision, not a
--   mechanical correctness rule. This migration adds no way for a user to choose
--   anything, which is what keeps it on the V1 side of that line.
--   ⚠ DISCRIMINATED ON account_type, NOT ON SIGN, and the rejection is the
--   interesting half: sign-routing would move an account between categories
--   across a single payment — an overpaid card would leave Liabilities and
--   re-enter it next month. An overpaid card is still a liability account, so its
--   positive balance lands in the SAME row and simply makes the Liabilities
--   subtotal less negative. Liabilities are R-7 naturally signed with no branch
--   (059), so the routed value carries its own sign and nothing here negates.
--
-- WHY A NEW ROW RATHER THAN 'Credit-Balance': account_type CONFLATES revolving
--   credit with loans and nothing in the schema separates them (the string
--   `subtype` appears in NO migration; pfin.account carries no column finer than
--   account_type). Routing every liability account to Credit-Balance would file a
--   mortgage under "Revolving Credit Balance". See 080's header for the full
--   argument and for why pfin.account.sub_cat_id (dropped at 048 with ADR-011
--   Decision 3 canonical instance #5) is not available as an alternative.
--
-- ----------------------------------------------------------------------------
-- Numbering: 081 follows 080; taken at authoring time against the live listing,
--   not reserved.
--   ⚠ ORDER-DEPENDENT ON 080, and the failure mode is SOFT rather than loud. The
--   route matches its target BY NAME. With 080 absent the LEFT JOIN finds
--   nothing, k_* go NULL, and every liability account's cash lands in the
--   unclassified row — value intact, no error, no log line. That is correct
--   fail-soft behaviour (see CONTRACT below) and it is precisely why the ordering
--   is stated here instead of being left to the file numbers to imply.
--   Depends further on 078 (the live definition being replaced), 076 (the
--   contract), 056 (fn_account_cash_as_of), 022 (the junction) and 003
--   (account_type).
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT
--   SECURITY DEFINER, and unchanged from the definition being replaced. Tenant
--   isolation is INHERITED from the RLS on every relation read, evaluated under
--   the caller's own session. `set search_path = ''` carried through verbatim.
--   The SECURITY DEFINER allowlist is UNCHANGED — no function is authored, one is
--   re-bodied; read the allowlist live at ADR-011 Decision 9.
--   ⚠ ISOLATION NOTE, stated because Sec carried it forward at the #480 review:
--   "any future change that reduces the read set to a single gating relation
--   removes that redundancy, and that change would need to come back to me." This
--   change moves in the OPPOSITE direction — it ADDS a gating relation
--   (a second pfin.user_taxonomy reference), and that relation carries an
--   EXPLICIT users_id conjunct on top of its own RLS. Redundancy increases; no
--   gate is removed.
--
-- ----------------------------------------------------------------------------
-- ⚠ TWO MECHANICAL TRAPS THIS FILE THREADS BY CONSTRUCTION, NOT BY CARE.
--   (1) VOLATILITY. CREATE OR REPLACE replaces the WHOLE definition including its
--       volatility class, which is how 079's STABLE pin would be silently erased
--       (the 078-before-079 class). This body carries `stable` INLINE, exactly as
--       the definition it replaces does, so the pin survives the replacement and
--       NO new ALTER and no new ordering dependency is created. 079's battery
--       carries the companion leg that watches precisely this.
--   (2) THE SELF-328 KERNEL-IDENTITY FENCE. The price-pick rank clause lives ONLY
--       in sec_leg; the cash leg contains none of it. sec_leg is reproduced
--       BYTE-IDENTICAL here, so all three fence legs hold by construction:
--       FENCE1a population stays 3, FENCE1b distinct-hash stays 1, FENCE1c
--       extraction stays 3. GOLDEN1/GOLDEN2 and ACL1/ACL2 are likewise untouched —
--       CREATE OR REPLACE never drops grants, so the EXECUTE ACL surface is
--       preserved and is deliberately NOT re-issued here (re-issuing it would be
--       the risk, not the safeguard).
--   SCOPE, mechanically bounded so review can be about the routing: this file is
--   the byte-for-byte live definition with changes CONFINED TO cash_leg — its
--   leading comment, its three key expressions, and one added LEFT JOIN. Not a
--   predicate elsewhere, not the fx expression, not sec_leg, not the projection.
--
-- ----------------------------------------------------------------------------
-- BLAST RADIUS — measured, not assumed. pfin.fn_subcat_market_value is the ONLY
--   live function that consumes pfin.user_asset_category for rollup
--   classification. fn_compute_nav sums a scalar; fn_account_unrealized_gl is
--   per-account; fn_nav_composition groups by account_type and was already
--   correct. NAV IS UNCHANGED at every signature. One function, one leg.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — ADR-011 Decision 4 referenced, NOT restated;
-- no count carried, deliberately). Decision 4 read verbatim and live before
-- drafting. This migration introduces ZERO catalogued §10 instances: it changes a
-- classification join inside one read-only SQL function — no credential surface,
-- no code-layer fence, no network/config surface.
--   (i)   Instance-numbering: UNCHANGED — nothing added, removed, or reordered.
--   (ii)  Layer-attribution: UNCHANGED — no catalogued instance's layer moves; no
--         surface becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is LINKED, not restated.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED set are different sets; neither is
--   changed here and they are not reconciled.
--   LEDGER STATUS: FLAT.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family UNCHANGED (+0),
--   in the honest form: no column exists to check. This migration creates, alters
--   and drops nothing — no table, no column, no FK, no INTEGER[] array. The new
--   relation reference is a JOIN PREDICATE inside a query, not a stored
--   reference, and it is matched by (users_id, domain, cat, sub_cat) rather than
--   by a foreign key, so there is no planted-id surface to fence. Read ADR-011
--   Decision 3 live for the family; this file carries no tally.
--
-- ----------------------------------------------------------------------------
-- CONTRACT — no signature, return type, posture, grant or comment change. R1 (no
--   tenant parameter) and R2 (the unclassified row exists) both hold unchanged,
--   and R2 is what makes the missing-target case safe:
--     BEFORE — a liability account's cash was classified by the caller's single
--       per-currency currency-asset junction row, netting into that row.
--     AFTER  — it is classified by the caller's own 'Liabilities' /
--       'Liability Balances' row. If the caller does not have that row, the LEFT
--       JOIN yields NULL and the value lands in the R2 unclassified row WITH ITS
--       VALUE INTACT. Never an INNER JOIN, never dropped, never silently zeroed.
--   ⚠ VALUE-NEUTRAL ON THE TOTAL, NOT ON THE ROW SET — and saying so is the
--   point. Routing moves a value BETWEEN rows; the sum over all returned rows is
--   unchanged, so the table still foots exactly as before and any assertion that
--   only compares totals will pass whether or not this migration applied. The
--   legs that discriminate are row-level: a liability account with non-zero cash
--   produces a row under the target Sub-Cat carrying the SIGNED value; the
--   raw-cash row no longer contains it; an OVERPAID (positive-balance) liability
--   account routes to the same row rather than back to cash; and a caller missing
--   the target row finds the value in the unclassified row.
--   Unchanged and worth stating so nobody re-derives it: the zero-balance filter
--   still suppresses a row for an account with no cash, so a paid-off card
--   contributes nothing rather than a 0.00 Liabilities row; and the Real-Estate
--   exclusion tests the TAXONOMY Cat, so 'Liabilities' rows surface regardless of
--   p_include_real_estate — a real_estate-TYPE account's cash is out of this
--   migration's scope and keeps the currency-asset route.
-- ============================================================================

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
    -- Cash: per-account balance × fx. TWO classification routes, chosen by
    -- account_type and by nothing else (081):
    --   · account_type = 'liability' → the seeded 'Liabilities' /
    --     'Liability Balances' row in the CALLER'S OWN taxonomy (080), matched by
    --     NAME. Mechanical: no user choice, no UI, no per-account decision.
    --   · every other account_type   → the GLOBAL currency-asset's per-user
    --     junction row (the 022 cash-via-currency-asset model), which yields ONE
    --     Sub-Cat per user per currency and cannot distinguish per account.
    -- pfin.account is joined DIRECTLY here (not left-joined), so the bare
    -- two-clause 059 predicate is correct and the three-conjunct form is not
    -- needed — the 049 / 059 cash-leg shape.
    select
      case when acc.account_type = 'liability' then lut.id      else ut.id      end as k_id,
      case when acc.account_type = 'liability' then lut.cat     else ut.cat     end as k_cat,
      case when acc.account_type = 'liability' then lut.sub_cat else ut.sub_cat end as k_sub_cat,
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
    -- LIABILITY ROUTE TARGET, matched by NAME because there is no id to follow:
    -- no junction row points at it, and pfin.account.sub_cat_id was dropped at
    -- 048. At most one row can match — 009's unique (users_id, domain, cat,
    -- sub_cat) — so this cannot multiply rows. LEFT JOIN, never INNER: a caller
    -- missing the 080 row gets NULL keys and the value lands in the R2
    -- unclassified row with its value intact.
    -- ⚠ THE users_id CONJUNCT IS LOAD-BEARING, NOT DECORATIVE — do not strike it
    -- for consistency with the `ut` joins above. Those key on `ut.id =
    -- uac.sub_cat_id`, a TENANT-BOUND surrogate: if RLS ever admitted a foreign
    -- row, a foreign id cannot match the caller's own ids, so they fail CLOSED.
    -- This join keys on `cat`/`sub_cat` STRING LABELS, which are SHARED
    -- VOCABULARY — every tenant's row reads 'Liabilities'/'Liability Balances' —
    -- so without `lut.users_id = acc.users_id` it fails OPEN: a leaked foreign
    -- row would match by name and attach a foreign sub_cat_id to this caller's
    -- liability cash. The conjunct is redundant against a CORRECTLY FUNCTIONING
    -- RLS and is the SOLE tenant discriminator against an RLS regression. That
    -- asymmetry is why this join carries one and its id-keyed siblings do not.
    left join pfin.user_taxonomy lut
      on lut.users_id = acc.users_id
     and lut.domain   = 'asset'
     and lut.cat      = 'Liabilities'
     and lut.sub_cat  = 'Liability Balances'
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

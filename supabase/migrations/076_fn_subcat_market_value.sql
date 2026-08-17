-- ============================================================================
-- Migration: pfin.fn_subcat_market_value — per-Sub-Cat market-value rollup.
-- Phase 6 Build Loop (SELF-237; PRD §2.2.2.a). Read-only over existing
-- relations: NO new base table, NO writes, NO new SECURITY DEFINER, NO new
-- FK-shaped column. Shared primitive: §2.2.2 Non-RE allocation (SELF-238) and
-- §2.2.3 US Equity sub-allocation (SELF-240) consume it at different filters.
--
-- WHAT THIS DOES: one row per asset-domain pfin.user_taxonomy Sub-Cat the caller
-- holds value in, carrying (sub_cat_id, cat, sub_cat, market_value), PLUS one
-- UNCLASSIFIED row (all three taxonomy columns NULL) carrying value the caller
-- holds but has not classified. Composition is the 019/050/056/059 uniform-NAV
-- kernel, decomposed per Sub-Cat instead of summed to a scalar.
--
-- ----------------------------------------------------------------------------
-- RATIFY RECORD (durable) — the AC set is F/CTO-ratified 2026-08-16 (V1.2
-- reconciliation, DDL-anchored). Recorded here because three of these were
-- decided against a plausible alternative, and the alternative is what a future
-- author re-derives if only the code survives.
--
--   R1. NO TENANT PARAMETER. Signature is (p_as_of, p_include_real_estate) and
--       nothing else. Tenant scope comes from SECURITY INVOKER + the caller's
--       RLS via auth.uid(). A p_users_id would be the confused-deputy foot-gun
--       that 049 R3 and 051 A1 both name and drop; a p_scope was ratified out at
--       049/051 (scope is an ATTRIBUTE, not a partition — ADR-004 Decision B,
--       full-household default).
--   R2. THE UNCLASSIFIED ROW EXISTS, AND ITS ABSENCE WOULD BE A SILENT MONEY
--       LEAK. In V1 an unclassified holding is the ABSENCE of a
--       pfin.user_asset_category row — there is no placeholder Sub-Cat and no
--       sentinel, and nothing in the schema guarantees a junction row per
--       asset. An INNER JOIN to the junction would therefore drop that value
--       from the rollup with no signal at all: the table would foot to a total
--       lower than NAV and look perfectly well-formed. This function emits the
--       unclassified value as its own NULL-taxonomy row so the loss is
--       IMPOSSIBLE to not see. SELF-238 renders it as the derived "Unsorted"
--       row (PRD §2.4.1 (e): never blocking); the DERIVATION is 238's, the
--       VISIBILITY is this function's, and that split is deliberate — a
--       consumer cannot derive what the producer has already discarded.
--   R3. MARKET_VALUE COALESCES TO 0, AND THAT IS A KNOWN INFORMATION LOSS
--       (stated, not hidden). Consistency with fn_compute_nav's leg-level
--       coalesce is what lets the allocation table foot to NAV (SELF-238 AC4).
--       The cost: a Sub-Cat whose constituents are ALL unpriced renders 0.00,
--       which is indistinguishable here from "holds nothing of value". That
--       distinction is NOT re-invented locally — it belongs to the existing
--       non-silent-staleness framework (ADR-049 Decision 5), which is the
--       surface that already owns "the data is stale/absent" reporting. Do not
--       add a second mechanism in this function.
--
-- ----------------------------------------------------------------------------
-- ⚠ TWO SUBSTRATE LIMITS THIS FUNCTION INHERITS AND CANNOT FIX. Both are stated
-- because a reader will otherwise assume the output is finer-grained than it is.
--
--   L1. CASH RESOLVES TO ONE SUB-CAT PER USER PER CURRENCY — it CANNOT be
--       classified per account. The cash leg has no asset_id (cash is a
--       per-account balance from fn_account_cash_as_of, and 017's CHECK keeps
--       cash rows at security_id IS NULL, so fn_holdings_as_of never returns
--       it). The only classification route the schema offers is the 022
--       cash-via-currency-asset model: account.currency → the GLOBAL
--       currency-asset (asset.users_id IS NULL, asset_type = 'currency',
--       symbol = the ISO code) → that asset's single per-user junction row.
--       Since the junction is unique (users_id, asset_id), a user has exactly
--       ONE classification for USD cash. **Consequence: the seeded Cash Sub-Cats
--       (CD / FDIC / SPIC / T-Bill) cannot be distinguished — every USD cash
--       balance in every account lands in whichever ONE the user picked, and a
--       user who has not classified the USD currency-asset gets all cash in the
--       unclassified row.** This is a product-visible limitation of the ratified
--       model, not a defect in this function; it is routed, not solved here.
--       ⚠ NARROWED AT `081` (2026-08-17). The claim being narrowed is "every USD
--       cash balance in every account lands in whichever ONE the user picked":
--       it held for EVERY account type when 076 shipped, and now holds for every
--       account type EXCEPT `liability`, whose cash 081 routes mechanically to
--       the seeded Liabilities / 'Liability Balances' row (080). The
--       once-per-currency grammar above is itself unchanged — liability cash
--       does not get a second classification, it never enters classification.
--   L2. THE UNCLASSIFIED POPULATION IS NOT THE SAME SET AS pendingSymbols.
--       api/src/lib/server/queries/pendingSymbols.ts computes EVER-TRANSACTED
--       minus classified (no quantity filter; a sold-to-zero symbol still
--       appears). This function's population is LIVE NON-ZERO POSITIONS, because
--       fn_holdings_as_of filters quantity <> 0. The two are DIFFERENT SETS on
--       purpose and must not be assumed to agree: a symbol fully sold before
--       p_as_of is pending-classification there and absent here. Naming it so a
--       future reconciliation does not "fix" one to match the other.
--
-- ----------------------------------------------------------------------------
-- Numbering: 076 follows 075 (user_settings_comment_supersession); taken at
--   authoring time against the live listing, not reserved ahead. Depends on 009
--   (user_taxonomy: id/cat/sub_cat/domain), 016 (the hybrid pfin.asset registry
--   + the global currency-asset rows), 019 (fn_holdings_as_of + eod_price + the
--   valuation kernel), 022 (user_asset_category junction), 041 (the seeded
--   taxonomy, incl. cat = 'Real Estate'), 056 (fn_account_cash_as_of), 059 (the
--   dated closure predicate). No downstream migration depends on 076.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT
--   SECURITY DEFINER. The function only READS, and every relation it reads is
--   already RLS-fenced to the caller (holdings via fn_holdings_as_of's own
--   INVOKER composition, account/asset/user_taxonomy/user_asset_category via
--   their own policies). It needs no privilege the caller lacks; DEFINER would
--   convert a read-composition helper into a confused deputy for no benefit.
--   `set search_path = ''` applied. → SECURITY DEFINER allowlist UNCHANGED
--   (adds no entry; ADR-011 Decision 9 — read the allowlist there).
--   `stable` IS DECLARED, deliberately: the function reads tables and returns
--   the same result within a statement for fixed arguments. ⚠ Noting rather than
--   copying a known divergence — 049 and 051 CLAIM "STABLE" in their CONTRACT
--   text while their DDL omits the modifier (leaving them VOLATILE). 056 and
--   062/071/073 declare it. This file follows the newer, correct convention and
--   does not reproduce the older mismatch.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; the catalogued
-- numbered list is NOT restated here and no count is carried, deliberately).
-- Decision 4 was read verbatim and live before drafting. This migration
-- introduces ZERO catalogued §10 instances: it is a read-only SQL function with
-- no write path, no credential surface, and no network/config surface.
--   (i)   Instance-numbering: unchanged — nothing added, reordered, renumbered.
--   (ii)  Layer-attribution: unchanged — no catalogued instance's layer moves and
--         no surface becomes "four-layer". No grant to service_role, no ACL move.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated.
-- DE-CONFLATION GUARD: this function is a READ surface. The Lock 14
-- user-facing-direct-DB-write class does not apply to it, and no §10 class
-- membership is claimed here.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family UNCHANGED, +0.
--   This migration creates NO table and NO column of any kind, FK-shaped or
--   otherwise. It only reads existing relations through existing fences. Read
--   ADR-011 Decision 3's numbered list live for the family's shape; nothing here
--   extends it, and no label is taken. (Stated explicitly per the mandatory
--   FK-shaped-column check, which is answered by "no column exists to check".)
--
-- LEDGER DELTAS (confirmed FLAT): §10 catalogued instances unchanged ·
--   SECURITY DEFINER allowlist unchanged · Decision-3 family unchanged ·
--   RT-26 allowlist untouched (no service_role surface) · RT catalog unchanged.
--
-- ----------------------------------------------------------------------------
-- JOINT-REVIEW-MANDATORY (Sec veto surface): a FINANCIAL CALCULATION on a
--   MULTI-TENANT READ PATH. The tenant fence here is entirely INHERITED — this
--   function adds no predicate of its own for isolation and relies on the
--   callee/relation RLS. That inheritance is the thing to review: if any relation
--   it reads were to lose its policy, this function would silently widen.
--
-- ----------------------------------------------------------------------------
-- VALUATION KERNEL — COPIED VERBATIM, NOT RE-DERIVED. The price-pick and FX
--   expressions below are character-for-character the 059 fn_compute_nav
--   securities-leg kernel (itself reproduced verbatim from 019 through
--   049/050/056). The house treats textual identity as the correctness
--   mechanism: five copies that read identically can be diffed; five that read
--   differently cannot. Two properties are therefore reproduced AS SHIPPED and
--   deliberately NOT "fixed" here:
--     · Price pick is LATEST-ON-OR-BEFORE (not exact-date), date dominating
--       source; the source CASE is only a same-date tie-break.
--     · ⚠ That tie-break is NOT total — 'market_feed', 'spot_feed' and 'fx_feed'
--       share rank 2, so an asset carrying two of them on the SAME price_date
--       resolves nondeterministically (no final price_id tie-break). This is
--       pre-existing behaviour in every copy; changing it here would fork the
--       kernel and silently disagree with fn_compute_nav. Flagged for the
--       reviewer, not altered.
--       ⚠ SUPERSEDED AT `078` (2026-08-17). The claim being replaced is "This is
--       pre-existing behaviour in every copy" — true when 076 shipped, not true
--       now: Sec's PR #480 joint-review ruling (1) appended a final
--       `ep.price_id desc` to EVERY LIVE copy of the kernel in one migration, so
--       the tie-break is total and this function's own copy carries it.
--
-- ----------------------------------------------------------------------------
-- AC6 PERFORMANCE — MEASURED, AND THE VENUE IS PART OF THE MEASUREMENT.
--   Budget: ≤300ms p95 at ~20 accounts / ~30 Sub-Cats. Measured on the LOCAL
--   DEV STACK (supabase/postgres 17.6 in Docker on the developer machine) at the
--   AC shape — 20 accounts × 30 classified assets = 605 live positions, 32 groups
--   returned — over 7 consecutive EXPLAIN ANALYZE runs: 13.2–14.2 ms execution,
--   worst case ~21× inside budget.
--   ⚠ THE VENUE IS NOT THE DEPLOY TARGET AND THIS NUMBER DOES NOT TRANSFER.
--   cax21 is the REFERENCE INCUMBENT, not the V1 deploy target, so no production
--   figure exists yet for anything; re-measure at the Phase-7 venue rather than
--   citing this line as a production characteristic. Recorded so a later
--   regression has a baseline of the right SHAPE to compare against — a timing
--   measured over one group would not have been that, which is why the first
--   run of this measurement was discarded when its fixture failed to classify.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_subcat_market_value(p_as_of date default current_date,
--                               p_include_real_estate boolean default false)
--     RETURNS TABLE (sub_cat_id bigint, cat text, sub_cat text,
--                    market_value numeric)
--     SECURITY INVOKER · STABLE · set search_path = ''
--
--     - One row per asset-domain user_taxonomy Sub-Cat in which the caller holds
--       value, plus AT MOST ONE unclassified row (sub_cat_id / cat / sub_cat all
--       NULL). Sub-Cats the caller holds NO value in are absent — this returns
--       what is held, not the taxonomy. SELF-238 supplies target-only rows by
--       joining planning_target (074); that is the consumer's join, not this
--       function's job.
--     - sub_cat_id is bigint: pfin.user_taxonomy.id is a bigint identity (009).
--       The INTEGER of the original draft is dead per the DDL-anchored ACs.
--     - EMPTY PORTFOLIO RETURNS ZERO ROWS, not a row of zeros and not NULL. A
--       set-returning function's empty answer is the empty set; a synthesized
--       zero row would assert a Sub-Cat the caller does not hold.
--     - p_include_real_estate = FALSE (default) excludes cat = 'Real Estate'
--       Sub-Cats ENTIRELY — no row, not a zeroed row (AC3). ⚠ The match is
--       EXACT on the asset-class taxonomy: 'Alternatives'/'REIT' is a DIFFERENT
--       cat and is NOT swept in, and account_type = 'real_estate' (003) is a
--       DIFFERENT taxonomy entirely (051 groups by that one; this groups by
--       user_taxonomy). The unclassified row is NEVER excluded by this flag —
--       its cat is NULL, so it cannot be known to be Real Estate.
--     - Closed accounts are excluded on the 059 dated predicate, in its
--       LEFT-JOIN-safe three-conjunct form (see the body comment): a bare
--       closed_at-is-null fails OPEN by asserting "not closed" from no
--       information.
--     - domain = 'asset' is enforced IN THE JOIN CONDITION, not the WHERE
--       clause, so a junction row pointing at a cash-flow Sub-Cat degrades to
--       the UNCLASSIFIED row rather than vanishing. (022 leaves domain matching
--       app-layer; 074's fence is the only DB-level domain enforcement and it
--       governs planning_target, not this junction.)
--   Security-load-bearing edges: no tenant predicate is written here — isolation
--     is INHERITED from the RLS on every relation read, under SECURITY INVOKER.
--     The function writes nothing, grants nothing to service_role, and adds no
--     fence of its own. EXECUTE is revoked from public and granted to
--     authenticated only.
-- ============================================================================

create schema if not exists pfin;

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
                  end
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

revoke execute on function pfin.fn_subcat_market_value(date, boolean) from public;
grant  execute on function pfin.fn_subcat_market_value(date, boolean) to authenticated;

comment on function pfin.fn_subcat_market_value(date, boolean) is
  'Per-Sub-Cat market-value rollup (PRD §2.2.2.a; SELF-237). Shared primitive for '
  'the §2.2.2 Non-RE allocation table and the §2.2.3 US Equity drill-down. '
  'SECURITY INVOKER + STABLE + set search_path = ''''; NO tenant or scope '
  'parameter — isolation is INHERITED from the RLS on every relation read, via '
  'auth.uid() under the caller''s own session (the 049/051 convention; a '
  'p_users_id would be a confused-deputy foot-gun, and scope is an attribute, not '
  'a partition, per ADR-004 Decision B full-household default). Returns one row '
  'per asset-domain user_taxonomy Sub-Cat the caller HOLDS VALUE IN — Sub-Cats '
  'with no holdings are absent, and an empty portfolio returns the EMPTY SET, not '
  'a zero row. ⚠ PLUS AT MOST ONE UNCLASSIFIED ROW (sub_cat_id / cat / sub_cat all '
  'NULL): in V1 an unclassified holding is the ABSENCE of a user_asset_category '
  'row, so an inner join would DROP that value silently and the table would foot '
  'below NAV while looking well-formed. The consumer (SELF-238) renders it as the '
  'derived Unsorted row; a consumer cannot derive what the producer discarded. ⚠ '
  'Its population is LIVE NON-ZERO POSITIONS (fn_holdings_as_of filters quantity '
  '<> 0) and is therefore NOT the same set as the app-layer pendingSymbols query, '
  'which is ever-transacted-minus-classified — do not reconcile them. ⚠ CASH '
  'resolves to ONE Sub-Cat per user per currency, via the global currency-asset''s '
  'single junction row (022 cash-via-currency-asset): the seeded CD / FDIC / SPIC '
  '/ T-Bill Sub-Cats CANNOT be distinguished per account, because the cash leg '
  'carries no asset_id. market_value COALESCES TO 0 for footing consistency with '
  'fn_compute_nav, which means an all-unpriced Sub-Cat renders 0.00 '
  'indistinguishably from holding nothing — that distinction belongs to the '
  'existing non-silent-staleness framework (ADR-049 Decision 5), not to a second '
  'mechanism here. p_include_real_estate = FALSE excludes cat = ''Real Estate'' '
  'ENTIRELY (no row); the match is exact on the ASSET-CLASS taxonomy, so '
  'Alternatives/REIT is not swept in and account_type = ''real_estate'' is a '
  'different taxonomy; the unclassified row is never excluded by the flag. Closed '
  'accounts excluded on the 059 dated predicate, three-conjunct on the '
  'LEFT-JOINed securities leg (a bare closed_at-is-null fails OPEN). The price and '
  'FX kernel is copied VERBATIM from 059''s fn_compute_nav so the two cannot drift; '
  'latest-on-or-before, date dominating source. Reads only: no write path, no new '
  'FK-shaped column, no DEFINER entry, no service_role grant.';

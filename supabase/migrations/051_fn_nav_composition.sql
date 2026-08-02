-- ============================================================================
-- Migration: pfin.fn_nav_composition — §2.1.5 NAV-composition backend aggregation
--   (V1.1 "Net worth full"; PRD §2.1.5; Linear SELF-225). A SINGLE SECURITY INVOKER
--   read helper (Lock 11) that returns the §2.1.5 composition tree as JSONB: per-category
--   account groups → per-account leaf rows → category subtotals → buildup subtotals →
--   final NAV. COMPOSES ON 049 (fn_account_unrealized_gl) — it does NOT re-derive market
--   value or unrealized G/L; 049 is the single leaf-row substrate. Read-only over 049 +
--   pfin.account: NO new base table, NO writes, NO new SECURITY DEFINER, NO new FK column.
--   Design brief in-message (team-lead dispatch 2026-08-01). apply-migration applied.
--
-- ----------------------------------------------------------------------------
-- RATIFY RECORD (durable) — RATIFIED AS-IS by F/CTO 2026-08-02; A1–A5 post-ratify
--   cross-check confirmed NO-DELTA (all four ratified items ① signature drop / ② debt-sign
--   D-1 / ③ JSONB shape + empty-category omission / ④ Option A tax placeholders match the
--   drafted body verbatim; zero surgical fixes). A1–A5 kept below as the durable record.
--   Mirrors the 049 RATIFY-ASSUMPTION convention:
--     (A1) SIGNATURE = fn_nav_composition(p_as_of date default current_date). DROP the AC's
--          `p_users_id UUID` (confused-deputy foot-gun — INVOKER + RLS scope by auth.uid()
--          by construction; mirrors 049 R3 / fn_compute_nav) AND DROP `p_scope pfin.scope[]`
--          (the `pfin.scope` TYPE DOES NOT EXIST — `scope` is a free-text account label per
--          ADR-004 Decision B, 003 line 100; identical to the 049 R2 finding). Per-scope
--          filtering is V2+ (PRD §2.1.7 — "per-scope reporting … V2+"). See SCOPE-DEFER.
--     (A2) AC#6 INACTIVE-FILTER RECONCILIATION: the AC prose says `pfin.account.inactive =
--          FALSE`, but the real column is `is_active boolean NOT NULL default true` (003
--          line 104; no `inactive` column exists). "inactive = FALSE" ≡ "is_active = TRUE".
--          049 ALREADY filters `where acc.is_active`, so composing on 049 inherits the
--          correct current-state filter FOR FREE — this function adds NO is_active predicate
--          of its own (it never touches an account 049 excluded). MECHANICAL, not a design
--          choice.
--     (A3) DEBT SIGN (Design D-1, lean): liability leaf `current_market_value` + the
--          liability group `subtotal` carry 049's NATURAL NEGATIVE sign (a debt reduces the
--          running total); buildups.debt = −(liability subtotal) = a POSITIVE MAGNITUDE so
--          AC#4's `nav = gross_total − debt` reads literally. See DEBT-SIGN below. Alt D-2
--          (magnitude-everywhere) was NOT taken — it would fork the leaf sign away from 049
--          and break the natural-sum foot-to-NAV invariant.
--     (A4) JSONB SHAPE = exactly AC#1 ({groups:[{category,accounts,subtotal}], buildups:{5
--          keys}, nav}); category carries the asset/RE/liability discriminator (no extra
--          `half` key). EMPTY categories are OMITTED (a group appears only if it has ≥1
--          active account); buildups are computed over the FULL active-account set
--          regardless of which groups are emitted. See JSONB-SHAPE.
--     (A5) TAX PLACEHOLDERS = Option A V1.1 form (AC#5; Wave-1 precedent): realized_tax_liab
--          = 0::numeric, unrealized_tax_liab = 0::numeric, both documented as V1.4 ramp.
--
-- ----------------------------------------------------------------------------
-- FOOT-TO-NAV EXACT (ADR-038 tightened by ADR-039/SELF-322 — the load-bearing invariant):
--   nav = gross_total − debt − realized_tax_liab − unrealized_tax_liab
--       = (total_non_re + real_estate) − (−Σ liability_signed) − 0 − 0
--       = total_non_re + real_estate + Σ liability_signed          [tax placeholders = 0]
--       = Σ over ALL active accounts of 049.current_market_value (natural signs)
--       = fn_compute_nav(p_as_of, p_active_only => true)            [ADR-038/039, EXACT].
--   The reconciliation is STRUCTURAL, not a re-call: 049.current_market_value IS each
--   account's fn_compute_nav contribution (049 header FOOT-TO-NAV PRECISION), and 050 makes
--   fn_compute_nav(as_of,true) = Σ over active accounts EXACTLY. Composing the buildups by
--   NATURAL SUMMATION of the same active-account leaf values therefore foots to the §2.1.1
--   headline by construction. This function does NOT separately call fn_compute_nav (a second
--   call could only introduce divergence risk; the single-substrate compose guarantees EXACT).
--
-- DEBT-SIGN (D-1, load-bearing): 049 returns liability current_market_value NATURALLY SIGNED
--   negative (liability cash balance is negative; 049 header R-7). The composition preserves
--   that sign in leaf rows + the liability group subtotal (so the tree sums naturally to NAV),
--   and defines buildups.debt = −(liability group subtotal) = a positive magnitude. Identity:
--   debt ≡ −(Σ liability_signed). AC#4's `nav = gross_total − debt` is then literally correct
--   AND foots to fn_compute_nav (which sums liabilities with their natural negative sign).
--
-- SCOPE-DEFER (A1): dropping p_scope is ADDITIVE-REVERSIBLE (a future filter param is a
--   non-breaking signature addition), NOT a one-way door. PRD §2.1.7 fixes per-scope reporting
--   as V2+; the account.scope column already carries the data (ADR-004 Decision B) so the V2
--   expansion ships without data migration. V1.1 default = full-household NAV (§2.1.7).
--
-- JSONB-SHAPE (A4): top-level {groups, buildups, nav}. groups[] in CANONICAL category order
--   (depository, investment, retirement, crypto, manual_other, real_estate, liability); each
--   = {category, accounts:[{account_id, account_name, current_market_value, unrealized_gl}],
--   subtotal}. Leaf unrealized_gl is NULL for non-investment accounts (straight from 049 —
--   AC#3). accounts[] ordered by account_id (deterministic). Empty categories omitted.
--
-- ----------------------------------------------------------------------------
-- Numbering: 051 follows 050. Pure read helper over 049 + pfin.account — order-independent
--   among helpers, sequenced after the NAV/composition track. Depends on: 049
--   (fn_account_unrealized_gl — the leaf substrate: per-active-account current_market_value +
--   unrealized_gl), 003 (pfin.account — name / account_type CHECK / is_active + direct-owner
--   RLS). No downstream migration depends on 051.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT SECURITY DEFINER.
--   fn_nav_composition composes 049 (itself INVOKER) + a direct-owner read of pfin.account and
--   needs NO elevated privilege — it runs ENTIRELY under the caller's RLS. A cross-tenant
--   caller sees no account rows (pfin.account direct-owner RLS) and 049 returns no rows →
--   empty groups, zero buildups, nav 0 (fails closed). set search_path = '' is the privesc
--   fence. DEFINER would BREAK tenant isolation (it would read every tenant's composition) —
--   INVOKER is load-bearing. → DEFINER allowlist UNCHANGED at 4 (authored 3).
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list. Decision 4 read verbatim before drafting.) 051 introduces
--   ZERO catalogued §10 instances; the ledger STAYS at 3 (RT-22 + RT-26 + RT-27).
--   (i)   Instance-numbering: RT-22 first, RT-26 second, RT-27 third — unchanged.
--   (ii)  Layer-attribution: a single authenticated-tier INVOKER READ function — no
--         service_role grant, no credential, no admission/network-exposure/config surface.
--         RT-22 (PDF-worker container), RT-26 (SUPABASE_SERVICE_ROLE_KEY grep fence), RT-27
--         (app→worker admission network-exposure/config layer) untouched. Nothing four-layer.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated. 051 is not the anchor.
--   DE-CONFLATION GUARD: this helper READS existing FKs (via 049 + the account join) — it adds
--   no reference column → Decision-3 family UNCHANGED, no new instance.
--
-- LEDGER DELTAS (confirmed FLAT): §10 catalogued instances = 3 (unchanged) · SECURITY DEFINER
--   allowlist = 4 (unchanged; this is INVOKER — authored DEFINER fns stay 3: fn_refresh_updated_at
--   @001 + fn_grant_creator_access @003 + fn_reclass_history_insert @031) · Decision-3 family =
--   unchanged (15 labeled / 12 DDL-realized; no new FK-shaped column) · RT-26 allowlist = 4.
--
-- ----------------------------------------------------------------------------
-- JOINT-REVIEW-MANDATORY (Sec veto surface): this is a FINANCIAL CALCULATION over
--   MULTI-TENANT-ISOLATED data (the NAV foot + per-account composition) — Sec joint-review is
--   required even though no DEFINER / no Decision-3 extension / no §10 ledger change.
--   Security-load-bearing edge = INVOKER cross-tenant caller → empty groups + nav 0 (fails
--   closed). RLS verification routes to the SELF-225 two-tenant RLS battery. QA pgTAP pairing
--   ships same-PR (SECURITY §4.5). Architect does NOT author tests/.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_nav_composition(p_as_of date default current_date) RETURNS jsonb — SECURITY
--     INVOKER, STABLE, set search_path=''. The §2.1.5 composition tree for the caller's tenant:
--       { "groups": [ { "category": <account_type>,
--                       "accounts": [ { "account_id", "account_name",
--                                       "current_market_value", "unrealized_gl" }, … ],
--                       "subtotal": <Σ current_market_value in category> }, … ],
--         "buildups": { "total_non_re":       Σ asset-half (excl. real_estate),
--                       "gross_total":        total_non_re + real_estate,
--                       "debt":               −(liability subtotal) = positive magnitude,
--                       "realized_tax_liab":  0  (Option A V1.1; V1.4 ramp),
--                       "unrealized_tax_liab":0  (Option A V1.1; V1.4 ramp) },
--         "nav": gross_total − debt − realized_tax_liab − unrealized_tax_liab }
--     groups[] in canonical category order, empties omitted; accounts[] by account_id; leaf
--     unrealized_gl NULL for non-investment (from 049, AC#3). nav foots EXACT to
--     fn_compute_nav(p_as_of, true) by construction (FOOT-TO-NAV EXACT above). p_as_of<today
--     reads historical values via 049's as-of threading (Lock 15; V1.1 consumers pass today).
--   Security-load-bearing edges: INVOKER (cross-tenant caller → empty tree / nav 0, fails
--     closed); all valuation delegated to 049 (single basis/market-value truth, never NaN).
--     GRANT to authenticated only; public REVOKED.
-- ============================================================================

create schema if not exists pfin;

create or replace function pfin.fn_nav_composition(p_as_of date default current_date)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  with
  -- LEAF rows: 049 (single substrate — per active account current_market_value + unrealized_gl,
  -- naturally signed) joined to pfin.account for name + account_type (grouping key). 049 already
  -- filters is_active (A2) → no is_active predicate needed here.
  leaf as (
    select
      g.account_id,
      a.name          as account_name,
      a.account_type  as category,
      g.current_market_value,
      g.unrealized_gl
    from pfin.fn_account_unrealized_gl(p_as_of) g
    join pfin.account a on a.account_id = g.account_id
  ),

  -- CANONICAL category ordering (asset half → real_estate → liability; PRD §2.1.5 / AC#2).
  cat_order (category, ord) as (
    values ('depository', 1), ('investment', 2), ('retirement', 3), ('crypto', 4),
           ('manual_other', 5), ('real_estate', 6), ('liability', 7)
  ),

  -- Per-category group: leaf array (ordered by account_id) + category subtotal (natural sign).
  grp as (
    select
      l.category,
      jsonb_agg(
        jsonb_build_object(
          'account_id',           l.account_id,
          'account_name',         l.account_name,
          'current_market_value', l.current_market_value,
          'unrealized_gl',        l.unrealized_gl        -- NULL for non-investment (049, AC#3)
        ) order by l.account_id
      )                       as accounts,
      sum(l.current_market_value) as subtotal            -- liability subtotal is naturally negative
    from leaf l
    group by l.category
  ),

  -- groups[] JSON in canonical order; empty categories omitted (A4). '[]' if no accounts.
  groups_json as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object('category', grp.category, 'accounts', grp.accounts, 'subtotal', grp.subtotal)
        order by co.ord
      ),
      '[]'::jsonb
    ) as groups
    from grp join cat_order co on co.category = grp.category
  ),

  -- BUILDUP components over the FULL active-account leaf set (independent of emitted groups).
  -- total_non_re = asset-half excl. real_estate; real_estate + liability split out for the foot.
  sums as (
    select
      coalesce(sum(l.current_market_value)
               filter (where l.category not in ('real_estate', 'liability')), 0) as total_non_re,
      coalesce(sum(l.current_market_value)
               filter (where l.category = 'real_estate'), 0)                     as real_estate,
      coalesce(sum(l.current_market_value)
               filter (where l.category = 'liability'), 0)                       as liability_signed
    from leaf l
  )

  -- Assemble. DEBT-SIGN (A3): debt = −(liability_signed) = positive magnitude. FOOT-TO-NAV
  -- EXACT: nav = gross_total − debt − 0 − 0 = total_non_re + real_estate + liability_signed
  -- = Σ 049(active) = fn_compute_nav(p_as_of, true).
  select jsonb_build_object(
    'groups',   (select groups from groups_json),
    'buildups', jsonb_build_object(
      'total_non_re',        s.total_non_re,
      'gross_total',         s.total_non_re + s.real_estate,
      'debt',                -s.liability_signed,
      'realized_tax_liab',   0::numeric,      -- Option A V1.1 (AC#5); V1.4 ramp
      'unrealized_tax_liab', 0::numeric       -- Option A V1.1 (AC#5); V1.4 ramp
    ),
    'nav', (s.total_non_re + s.real_estate) - (-s.liability_signed) - 0::numeric - 0::numeric
  )
  from sums s;
$$;

revoke execute on function pfin.fn_nav_composition(date) from public;
grant execute on function pfin.fn_nav_composition(date) to authenticated;

comment on function pfin.fn_nav_composition(date) is
  'SECURITY INVOKER §2.1.5 NAV-composition aggregation (V1.1 "Net worth full"; PRD §2.1.5 / '
  'SELF-225; Lock 11 read-composition). Returns the composition tree as JSONB: '
  '{groups:[{category, accounts:[{account_id, account_name, current_market_value, unrealized_gl}], '
  'subtotal}], buildups:{total_non_re, gross_total, debt, realized_tax_liab, unrealized_tax_liab}, '
  'nav}. COMPOSES ON 049 fn_account_unrealized_gl (single leaf substrate — per active account '
  'current_market_value + unrealized_gl, naturally signed) joined to pfin.account for name + '
  'account_type; 049 already filters is_active (AC#6: the real column is is_active, not the AC-prose '
  '"inactive"). groups[] in canonical category order (depository/investment/retirement/crypto/'
  'manual_other → real_estate → liability; §2.1.5/AC#2), empty categories omitted; accounts[] by '
  'account_id; leaf unrealized_gl NULL for non-investment (049, AC#3). DEBT SIGN (D-1): liability '
  'leaves + subtotal carry 049''s natural negative sign; buildups.debt = −(liability subtotal) = '
  'positive magnitude so AC#4 nav = gross_total − debt reads literally. TAX PLACEHOLDERS = Option A '
  'V1.1 (AC#5): realized/unrealized_tax_liab = 0::numeric, V1.4 ramp. FOOT-TO-NAV EXACT (ADR-038/'
  '039): nav = total_non_re + real_estate + Σ liability_signed = Σ 049(active) = '
  'fn_compute_nav(p_as_of, true) BY CONSTRUCTION (single-substrate natural summation; no separate '
  'fn_compute_nav call). p_scope DROPPED (pfin.scope type does not exist; scope is a free-text '
  'ADR-004 label — per-scope reporting is V2+, PRD §2.1.7); p_users_id DROPPED (INVOKER + RLS scope '
  'by auth.uid()). AS-OF via 049 threading (Lock 15; V1.1 consumers pass CURRENT_DATE). INVOKER → '
  'cross-tenant caller sees no rows → empty groups / nav 0 (fails closed). set search_path=''''; NOT '
  'a DEFINER allowlist entry (stays 4); §10 ledger stays 3; Decision-3 unchanged (no new FK column). '
  'Sec joint-review-mandatory (financial calc + multi-tenant); RLS verification → SELF-225 '
  'two-tenant battery.';

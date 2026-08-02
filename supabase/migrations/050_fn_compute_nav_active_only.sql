-- ============================================================================
-- Migration: pfin.fn_compute_nav — parameterize with p_active_only (current-state
--   is_active scoping) so the §2.1.1 headline NAV excludes soft-deleted (inactive)
--   accounts and reconciles with the §2.1.5 composition (049, active-only). Fixes the
--   SELF-322 scope gap. CREATE OR REPLACE only — NO new base table, NO writes, NO new
--   SECURITY DEFINER, NO new FK-shaped column.
--   Linear SELF-322 (V1.1 "Net worth full"; blocks SELF-225). F/CTO-ratified 2026-08-02
--   (Option C — parameterize; A blanket + D temporal rejected — see ADR-039). Analysis
--   brief in-message. apply-migration procedure applied.
--
-- ----------------------------------------------------------------------------
-- WHY (the bug — SELF-322): pfin.fn_compute_nav (019) filters NO is_active on either leg,
--   so it counts INACTIVE accounts. PRD §2.4.2: an account is marked inactive "when closed
--   or sold; inactive accounts retain their transaction history … but are EXCLUDED from
--   current-state surfaces by default." Soft-delete flips is_active only (003 — no DELETE
--   path; 042 reactivates by flipping back) → an inactive account retains a nonzero value.
--   The §2.1.1 headline (api/.../netWorth.ts) calls fn_compute_nav(as_of) DIRECTLY for the
--   NAV number → it over-counts a value-bearing inactive account and DISAGREES with §2.1.5
--   composition (049, which filters `where acc.is_active`). Documented convention (012):
--   "current-state / net-worth aggregation filters WHERE is_active = TRUE." LIVE bug.
--
-- ----------------------------------------------------------------------------
-- SHAPE (Option C — parameterize, ratified; NOT the A blanket / D temporal alternatives):
--   TWO functions, both SECURITY INVOKER:
--     (1) fn_compute_nav(p_as_of date, p_active_only boolean) — the 2-arg IMPL. Reproduces
--         019's uniform roll-forward valuation VERBATIM and adds is_active scoping GATED on
--         p_active_only: when TRUE, both legs restrict to active accounts; when FALSE, the
--         result is BYTE-IDENTICAL to 019 (the predicates short-circuit / the LEFT JOIN
--         drops no rows). NO DEFAULT on p_active_only (see NO-DEFAULT NOTE).
--     (2) fn_compute_nav(p_as_of date) — the 1-arg WRAPPER, CREATE OR REPLACE in place
--         (same signature as 019 → NO DROP, NO dependency break). Delegates to
--         fn_compute_nav(p_as_of, false) = all-accounts. So EVERY existing caller of the
--         1-arg is UNCHANGED — critically 037 fn_gl_entries' Unrealized memo
--         (fn_compute_nav(p_as_of) − book_nav), which is a book-domain reconciliation that
--         legitimately images ALL accounts (its book_nav leg is all-accounts; matching it
--         keeps the memo internally consistent — the F/CTO-ratified "037 untouched").
--   The §2.1.1 headline (Backend, netWorth.ts — NOT this migration) switches to the 2-arg
--   with p_active_only => true. That's the ONLY behavior change; the DB default path (1-arg)
--   is unchanged.
--
-- NO-DEFAULT NOTE (correctness — a deviation from the literal "p_active_only default false"
--   phrasing, flagged for cross-check): the 2-arg CANNOT carry `default false` while the
--   1-arg wrapper exists — a call `fn_compute_nav(<date>)` would then be AMBIGUOUS between
--   the explicit 1-arg and the defaulted 2-arg (PG raises "function ... is not unique").
--   So the "default false" semantic is delivered BY the 1-arg wrapper (which supplies false),
--   not by a parameter default. Net effect for callers is identical: 1-arg = all-accounts.
--
-- ORDERING (SQL-language body validation): the 2-arg IMPL is created FIRST; the 1-arg
--   wrapper (which references it) is created SECOND. Supabase runs with check_function_bodies
--   on → a forward reference would fail, so order is load-bearing.
--
-- TEMPORAL CONSTRAINT (documented, load-bearing): is_active is a CURRENT-STATE boolean
--   (no deactivated_at), but fn_compute_nav(p_as_of) is an AS-OF query. p_active_only => true
--   is only SOUND at p_as_of = current_date — filtering CURRENT is_active into a HISTORICAL
--   as-of computation retroactively rewrites history (an account deactivated today would drop
--   from a past-dated NAV). V1.1 consumers pass current_date. FORWARD-FLAG: §2.1.2 NAV
--   trajectory / a future pfin.nav_daily (Wave 2, not yet built) must derive history from
--   APPEND-ONLY PRECOMPUTED checkpoints (frozen at compute-time), NOT on-the-fly
--   fn_compute_nav(<past>, true). A blanket is_active (rejected Option A) would have imposed
--   this rewrite on the all-accounts path too; Option C confines active-only to opt-in.
--
-- ----------------------------------------------------------------------------
-- Numbering: 050 follows 049. CREATE OR REPLACE over pfin.fn_compute_nav (append-only
--   migration discipline — 019 is NOT edited). Depends on 019 (the function being
--   replaced + fn_holdings_as_of + the eod_price D-first LOCF / fx idioms + account_
--   balance_checkpoint roll-forward, all reproduced verbatim), 003 (pfin.account.is_active
--   [NOT NULL default true] + currency + account_id PK), 016 (pfin.asset — currency/
--   asset_type/symbol/users_id the fx leg joins). No downstream migration depends on 050.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (Lock 11 default); NO new SECURITY DEFINER. Both
--   functions run as the caller and compose entirely under the caller's RLS (pfin.account
--   direct-owner; fn_holdings_as_of / account_balance_checkpoint / account_trans rd_access-
--   JOIN; eod_price / asset global-OR-owned) — exactly as 019. A cross-tenant caller sees no
--   rows → 0 (fails closed). DEFINER would break tenant isolation. set search_path = '' on
--   both (privesc fence). → DEFINER allowlist UNCHANGED at 4 (authored 3: fn_refresh_updated_at
--   @001 + fn_grant_creator_access @003 + fn_reclass_history_insert @031 + 1 reserved).
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list. Decision 4 read verbatim before drafting.) ZERO catalogued
--   §10 instances; the ledger STAYS at 3 (RT-22 + RT-26 + RT-27).
--   (i)   Instance-numbering: RT-22 first, RT-26 second, RT-27 third — unchanged.
--   (ii)  Layer-attribution: two authenticated-tier INVOKER READ functions — no service_role
--         grant, no credential, no admission/network-exposure/config surface. RT-22/RT-26/
--         RT-27 untouched. Nothing becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 linked, not restated. 050 is not the anchor.
--   DE-CONFLATION GUARD: adds NO FK-shaped reference column (reads existing FKs) → Decision-3
--   family UNCHANGED, no new instance.
--
-- LEDGER DELTAS (confirmed): §10 catalogued instances = 3 (unchanged) · SECURITY DEFINER
--   allowlist = 4 (unchanged; both INVOKER) · Decision-3 family = unchanged (no new FK column).
--
-- ----------------------------------------------------------------------------
-- JOINT-REVIEW-MANDATORY (Sec veto surface): FINANCIAL CALCULATION over MULTI-TENANT-ISOLATED
--   data. Security-load-bearing edge = INVOKER cross-tenant caller → 0 (fails closed),
--   preserved from 019. QA two-tenant battery ships same-PR.
--
-- ----------------------------------------------------------------------------
-- CONSISTENCY AC (SELF-322): after this fix, §2.1.1 headline NAV (fn_compute_nav(as_of,
--   true)) and §2.1.5 composition NAV (Σ 049.current_market_value over active accounts)
--   reconcile for ANY tenant, including one holding a value-bearing INACTIVE account. This
--   makes the ADR-038 foot-to-NAV invariant EXACT: Σ 049.current_market_value (active) =
--   fn_compute_nav(as_of, p_active_only => true). (ADR-038 footnote updated accordingly.)
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_compute_nav(p_as_of date, p_active_only boolean) RETURNS numeric — SECURITY
--     INVOKER, set search_path=''. Net worth in USD as of p_as_of. p_active_only=false →
--     identical to 019 (ALL accounts; the book/as-of engine — 037 memo + historical trend).
--     p_active_only=true → CURRENT-STATE (active accounts only; §2.1.1 headline) — sound only
--     at p_as_of=current_date (see TEMPORAL CONSTRAINT). Both legs (securities via
--     fn_holdings_as_of joined to pfin.account; cash via pfin.account) gate on is_active only
--     when p_active_only. Unpriced asset → NULL term → dropped → 0, never NaN (019 precedent).
--   pfin.fn_compute_nav(p_as_of date) RETURNS numeric — SECURITY INVOKER wrapper; delegates
--     to fn_compute_nav(p_as_of, false). Signature-identical to 019 (no DROP; 037 untouched).
--   Security-load-bearing edges: INVOKER cross-tenant → 0 (fails closed); p_active_only=false
--     byte-identical to 019 (037 memo consistency preserved); EXECUTE to authenticated only,
--     public REVOKED (both signatures).
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- (1) 2-arg IMPL — 019's uniform roll-forward valuation, VERBATIM, + is_active scoping
--     GATED on p_active_only. p_active_only=false ⇒ byte-identical to 019.
--       cash_leg:     `where (not p_active_only or acc.is_active)` — `not false` short-
--                     circuits to TRUE (all accounts); `not true` ⇒ `acc.is_active` (active
--                     only). acc.is_active is NOT NULL (003) — no coalesce needed.
--       security_leg: LEFT JOIN pfin.account on the holdings' account_id (PK, 1:1 — no
--                     multiplicity change) + `where (not p_active_only or coalesce(acc2
--                     .is_active,false))`. LEFT JOIN + false-path where=TRUE ⇒ drops no rows
--                     (identical to 019); true-path keeps active-account holdings only
--                     (coalesce false fail-closed if no account row).
-- Created BEFORE the wrapper (SQL-body forward-reference validation).
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_compute_nav(p_as_of date, p_active_only boolean)
returns numeric
language sql
security invoker
set search_path = ''
as $$
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
    ), 0) as v
    from pfin.fn_holdings_as_of(p_as_of) h
    join pfin.asset a on a.asset_id = h.asset_id
    left join pfin.account acc2 on acc2.account_id = h.account_id
    where (not p_active_only or coalesce(acc2.is_active, false))
  ),
  cash_leg as (
    select coalesce(sum(
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
    ), 0) as v
    from pfin.account acc
    where (not p_active_only or acc.is_active)
  )
  select (select v from security_leg) + (select v from cash_leg);
$$;

revoke execute on function pfin.fn_compute_nav(date, boolean) from public;
grant execute on function pfin.fn_compute_nav(date, boolean) to authenticated;

comment on function pfin.fn_compute_nav(date, boolean) is
  'SECURITY INVOKER uniform roll-forward net-worth read (ADR-027 §5 / Lock 11; SELF-322 / '
  'ADR-039). 019''s valuation VERBATIM + is_active scoping GATED on p_active_only. '
  'p_active_only=FALSE → byte-identical to 019 (ALL accounts — the book/as-of engine: 037 GL '
  'memo + historical trend). p_active_only=TRUE → CURRENT-STATE (active accounts only; the '
  '§2.1.1 headline via netWorth.ts) — SOUND ONLY at p_as_of=current_date (is_active is '
  'current-state, not temporal; filtering it into a past as_of rewrites history — see 050 '
  'TEMPORAL CONSTRAINT; §2.1.2 trajectory/nav_daily must use frozen precomputed checkpoints). '
  'securities leg filters via LEFT JOIN pfin.account on holdings.account_id; cash leg via '
  'pfin.account — both gate on is_active ONLY when p_active_only. Makes the ADR-038 foot-to-NAV '
  'invariant EXACT: Σ 049.current_market_value(active) = fn_compute_nav(as_of, true). INVOKER '
  '(cross-tenant → 0, fails closed); unpriced asset → NULL → dropped → 0, never NaN. set '
  'search_path=''''; NOT a DEFINER allowlist entry (stays 4); §10 ledger 3; Decision-3 unchanged. '
  'EXECUTE revoked from PUBLIC, granted to authenticated.';

-- ----------------------------------------------------------------------------
-- (2) 1-arg WRAPPER — CREATE OR REPLACE in place (019 signature; NO DROP → 037 dependency
--     intact). Delegates to the 2-arg with false = all-accounts. Every existing 1-arg caller
--     (037 fn_gl_entries memo; any other) is UNCHANGED. The "default false" semantic lives
--     here, not as a parameter default (NO-DEFAULT NOTE — avoids the 1-arg overload ambiguity).
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_compute_nav(p_as_of date)
returns numeric
language sql
security invoker
set search_path = ''
as $$
  select pfin.fn_compute_nav(p_as_of, false);
$$;

revoke execute on function pfin.fn_compute_nav(date) from public;
grant execute on function pfin.fn_compute_nav(date) to authenticated;

comment on function pfin.fn_compute_nav(date) is
  'SECURITY INVOKER 1-arg wrapper (SELF-322 / ADR-039) — delegates to fn_compute_nav(p_as_of, '
  'false) = ALL accounts (the 019 semantic, unchanged). Signature-identical to 019 (CREATE OR '
  'REPLACE in place, NO DROP) so 037 fn_gl_entries'' Unrealized memo — a book-domain '
  'reconciliation that legitimately images all accounts — is UNTOUCHED. Callers needing '
  'current-state (active-only) net worth call the 2-arg with p_active_only => true (the §2.1.1 '
  'headline). set search_path=''''; INVOKER; DEFINER allowlist stays 4; §10 ledger 3; '
  'Decision-3 unchanged. EXECUTE revoked from PUBLIC, granted to authenticated.';

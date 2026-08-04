-- ============================================================================
-- 059_drop_is_active.sql — retire pfin.account.is_active (ADR-042 Decision 1;
--   the final slice). Re-point every reader to the as-of predicate, prove the
--   two representations agreed, then remove the column and the machinery that
--   kept them in step.
--
-- ORDERED BY PREFIX-SAFETY, NOT BY CONVENIENCE (Sec, 059 pre-spec):
--
--     >> Order the steps so that EVERY PREFIX IS A VALID STATE. <<
--
--   The usual argument is "the runner wraps each file in a transaction, so
--   partial application is impossible." THAT PREMISE IS NOT RELIED ON HERE AND
--   IS NOT MEASURED — stated plainly rather than asserted, because an unmeasured
--   premise carrying a financial-correctness guarantee is the exact shape this
--   review kept finding. Prefix-safety makes it NOT MATTER: if the wrapper
--   holds nothing is exposed; if it does not, every intermediate state is still
--   coherent. (Measuring the wrapper once, for every migration after this one,
--   is a DevOps item and deliberately NOT a dependency of this file.)
--
--   THE REJECTED ORDER — validate, drop trigger, drop CHECK, drop column, THEN
--   re-point — has an unsafe prefix ON THE NAV PATH: between dropping the
--   biconditional and re-pointing, a row can carry closed_at set with is_active
--   still true, and fn_compute_nav COUNTS IT AS ACTIVE. A closed account
--   contributing to net worth, silently, reporting green.
--
-- WHY A CLEAN APPLY IS NOT EVIDENCE OF A COMPLETE RE-POINT (Sec, measured):
--   every SQL reader of is_active uses an OLD-STYLE text body (`as $$ … $$`,
--   not BEGIN ATOMIC), and old-style bodies carry NO DEPENDENCY RECORDS.
--     views / RLS policies / constraints → tracked   → DROP COLUMN FAILS LOUD
--     old-style sql + plpgsql bodies     → untracked → DROP SUCCEEDS, breaks
--                                                      at first call
--   Step (3) exists because of that, and RAISES rather than reporting.
--
-- BARE `DROP COLUMN`. NEVER `CASCADE` (Sec: standing veto). CASCADE would turn
--   the one LOUD half of that table silent, dropping dependent views and RLS
--   policies without enumerating them. If the bare drop ever fails, THE FAILURE
--   IS THE FINDING.
--
-- SCOPE — DERIVED, THEN NARROWED TWICE. Both narrowings matter:
--   (a) `prosrc ilike '%is_active%'` returns SEVEN functions, and four are
--       permanently legitimate: is_active is NOT ONE COLUMN. It exists on
--       pfin.account, asset, linked_source, linked_source_connection_state and
--       user_taxonomy. fn_aggregation_has_stale_constituent reads
--       linked_source_connection_state; the view reads linked_source;
--       fn_create_manual_account matches a COMMENT; fn_land_linked_accounts is
--       clean post-058. The first reading of that list was "the ADR's 059 list
--       is incomplete, same root cause as 058" — dramatic, consistent with the
--       day's pattern, and WRONG. A finding that fits the prevailing pattern
--       deserves MORE scrutiny, not less.
--   (b) ADR-042 names 049/050/051. **051 needs NO change** — fn_nav_composition
--       mentions is_active only in a comment and inherits filtering from 049.
--       Two functions are re-pointed here, three predicates in total.
--
-- HOW THE TWO BODIES BELOW WERE PRODUCED — this is a control, not a note.
--   They are `pg_get_functiondef()` output from the live catalog with ONLY the
--   predicate lines substituted, and the substitution was proved by diff:
--     fn_account_unrealized_gl : 1 predicate + 1 stale comment
--     fn_compute_nav           : 2 predicates
--   NOTHING ELSE CHANGED. The first draft of this file had these bodies written
--   FROM RECALL, and they were fabrications — wrong return types, wrong column
--   counts, a missing overload, and invented valuation logic. It would have
--   applied clean and silently replaced three financial functions. Regenerate
--   from the catalog and diff; never retype a body you are re-pointing.
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- (1) VALIDATE — first, and alone. 058 added the biconditional NOT VALID, so
--   pre-existing rows were never checked; the OPERATOR STEP between 058 and 059
--   dispositioned each one through the real gated control. This is the only
--   step that can discover a mismatch, and it must run while BOTH columns exist
--   — afterwards the evidence needed to diagnose one is gone.
--
--   TWO DIFFERENT FAILURES SHARE SQLSTATE 23514 AND DIFFER ONLY IN MESSAGE:
--     row-level violation → "new row for relation … violates check constraint"
--     failed VALIDATE     → "check constraint … is violated by some row"
--   Any assertion about THIS step must match the MESSAGE TEXT, not the SQLSTATE.
-- ----------------------------------------------------------------------------
alter table pfin.account validate constraint account_closure_biconditional;

-- ----------------------------------------------------------------------------
-- (2) RE-POINT, before anything is removed. Prefix state: nothing reads
--   is_active, and BOTH the sync trigger and the biconditional are still
--   maintaining the two columns in step — the safest state in the file.
--
--   THE PREDICATE: is_active answered "open NOW"; closed_at answers "open AS OF
--   a date", which is strictly more information and is the point of ADR-042:
--       (acc.closed_at is null or acc.closed_at > p_as_of)
--   A NAV for a past date now correctly includes an account open then and since
--   closed — which is_active could never express.
--
--   THE SHORT-CIRCUIT IS PRESERVED LITERALLY. `where (not p_active_only or …)`
--   means that when p_active_only is false there is NO PREDICATE, not a
--   universally-true one. Collapsing it changes 037's memo to show a phantom
--   imbalance. Do not "simplify" it.
--
--   THE SECURITIES-LEG CONJUNCT IS LOAD-BEARING. `coalesce(acc2.is_active,
--   false)` failed CLOSED on a LEFT JOIN miss. Its replacement must too:
--   `acc2.account_id is not null and (acc2.closed_at is null or …)`. The naive
--   `acc2.closed_at is null` alone fails OPEN — NULL-from-no-row asserts "not
--   closed" from no information. Under V1 both forms behave identically, so
--   dropping the conjunct FLIPS THE DEFAULT SILENTLY and a too-high NAV looks
--   exactly like a correct one.
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
  where (acc.closed_at is null or acc.closed_at > p_as_of)
  order by acc.account_id;
$function$

;
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
    where (not p_active_only or (acc2.account_id is not null and (acc2.closed_at is null or acc2.closed_at > p_as_of)))
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
    where (not p_active_only or (acc.closed_at is null or acc.closed_at > p_as_of))
  )
  select (select v from security_leg) + (select v from cash_leg);
$function$

;

-- ----------------------------------------------------------------------------
-- (3) FAIL-CLOSED GATE — refuse to CREATE the breakage rather than report it.
--   Step (6) will succeed however incomplete step (2) was, because old-style
--   bodies are not dependency-tracked. This block is the only thing between an
--   incomplete re-point and a NAV path that breaks at first call.
--
--   ALLOWLIST, NOT DENYLIST: it names the functions PERMITTED to mention
--   is_active and fires on anything else. A denylist of known-bad patterns
--   would pass a consumer nobody thought of — precisely the failure guarded.
--
--   THE NAIVE FORM OF THIS CHECK CANNOT EVER PASS. A zero-rows criterion on
--   `prosrc ilike '%is_active%'` returns SEVEN rows on a CORRECT 059, because
--   other tables legitimately have that column. A gate that can never go green
--   is waived the first time it is hit, and then it is gone. Each exemption
--   below is justified individually, and the two re-pointed functions are
--   deliberately NOT exempt — their comments were reworded to drop the literal
--   so the gate stays tight. An exemption costs more than a word.
--
--   THIS CHECK DECLARES ITS OWN BLIND SPOT: prosrc is EMPTY for new-style
--   BEGIN ATOMIC bodies (they live in prosqlbody). Measured today: zero such
--   functions in pfin, so it is complete NOW. It silently under-reports the
--   moment anyone writes one.
-- ----------------------------------------------------------------------------
do $$
declare
  v_left text;
begin
  select string_agg(p.proname, ', ' order by p.proname) into v_left
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'pfin'
    -- COMMENT-STRIPPED: match CODE, not prose. Measured — without this the gate
    -- also reports fn_land_linked_accounts, fn_nav_composition and
    -- fn_create_manual_account, every one of which mentions the column ONLY in
    -- a comment. That would be three more exemptions, each needing its own
    -- justification and each widening the hole. Distinguishing code from prose
    -- removes them instead of excusing them.
    -- DECLARED BLIND SPOTS, measured not assumed: handles `--` only (there are
    -- ZERO /* */ block comments in pfin today), and a match inside a STRING
    -- LITERAL would false-positive (three pfin functions carry one somewhere;
    -- none of them survives step (2) as a code reference).
    and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ilike '%is_active%'
    and p.proname not in (
      'fn_aggregation_has_stale_constituent', -- reads linked_source_connection_state.is_active (a DIFFERENT table)
      'fn_account_sync_is_active'             -- dropped at step (5); legitimate at this prefix
    );

  if v_left is not null then
    raise exception
      'pfin.account.is_active still referenced IN CODE by: % — re-point BEFORE dropping. Old-style SQL bodies carry no dependency records, so the DROP would SUCCEED and these would fail at first call, on the NAV path. If one of these legitimately reads a DIFFERENT table''s is_active, add it to this allowlist WITH a justification rather than widening the pattern.',
      v_left;
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- (4) Drop the biconditional. Prefix: the columns may now diverge and NOTHING
--   READS EITHER for correctness — step (2) already re-pointed.
--   4 BEFORE 5 deliberately: dropping the CHECK first leaves the sync trigger
--   harmlessly maintaining a column nobody reads. Dropping the TRIGGER first
--   leaves the CHECK in force with nothing maintaining it, and EVERY CLOSE
--   FAILS until step (4) runs — broken-and-loud, but needlessly.
-- ----------------------------------------------------------------------------
alter table pfin.account drop constraint account_closure_biconditional;

-- ----------------------------------------------------------------------------
-- (5) Drop the transitional sync machinery. Trigger first: the function cannot
--   be dropped while a trigger references it.
-- ----------------------------------------------------------------------------
drop trigger if exists account_sync_is_active on pfin.account;
drop function if exists pfin.fn_account_sync_is_active();

-- ----------------------------------------------------------------------------
-- (6) The column. BARE — see the header.
-- ----------------------------------------------------------------------------
alter table pfin.account drop column is_active;

comment on column pfin.account.closed_at is
  'THE ONLY representation of open/closed (ADR-042). The boolean flag was retired at 059: it answered "open NOW" where closed_at answers "open AS OF a date" — strictly more information, and the two coexisting was the three-way overloading ADR-042 exists to remove. Readers use (closed_at is null or closed_at > p_as_of); NEVER a bare `closed_at is null` in an as-of context, and never a LEFT-JOINed `closed_at is null` without an accompanying `account_id is not null`, which fails OPEN by asserting "not closed" from no information.';

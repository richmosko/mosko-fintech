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
--   The step (7) SMOKE INVOCATION exists because of that. A static text check
--   was tried first and WITHDRAWN — see (7) for why no refinement of it could
--   have worked.
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
--   (b) ADR-042 names 049/050/051. **051 needs no CODE change** —
--       fn_nav_composition composes on 049 and adds no predicate of its own.
--       It IS re-emitted at (2b), COMMENT-ONLY, because the comment explaining
--       WHY it safely omits a predicate goes false when step (6) lands.
--       Two functions re-pointed, three predicates; one comment-only re-emit.
--
-- HOW THE THREE BODIES BELOW WERE PRODUCED — this is a control, not a note.
--   They are `pg_get_functiondef()` output from the live catalog with ONLY the
--   intended lines substituted, and every substitution was PROVED BY DIFF:
--     fn_account_unrealized_gl : 1 predicate + 1 stale comment
--     fn_compute_nav           : 2 predicates
--     fn_nav_composition       : 1 comment → 6, plus one trailing blank line
--                                consumed by extraction (no code change)
--   NOTHING ELSE CHANGED, and that claim is CHECKABLE — re-run the diff rather
--   than trusting this sentence. (Independently verified by team-lead and QA
--   against the live catalog before merge.)
--
--   THE FIRST DRAFT OF THIS FILE HAD THESE BODIES WRITTEN FROM RECALL, AND THEY
--   WERE FABRICATIONS — wrong return types, wrong column counts, a missing
--   overload, invented valuation logic. `create or replace` would have accepted
--   every one: it would have APPLIED CLEAN and silently replaced three
--   financial functions, green migration, wrong NAV, no signal anywhere.
--   ***Regenerate from the catalog and diff; never retype a body you are
--   re-pointing.*** Retyping yields a body whose correctness can only be
--   trusted; regenerating yields one whose correctness can be SHOWN.
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
-- (2b) fn_nav_composition — COMMENT-ONLY re-emit. No behaviour changes.
--
--   051 needs no CODE change: it composes on 049 and adds no predicate of its
--   own, so it inherits the as-of filter for free. ADR-042's "049/050/051" was
--   one too many.
--
--   BUT IT IS BEHAVIOURALLY AFFECTED WHILE TEXTUALLY UNCHANGED, and its body
--   comment goes FALSE the moment step (6) lands (Sec flag). The comment said
--   "049 already filters is_active" — which is THE REASON 051 SAFELY OMITS A
--   PREDICATE. After the drop a reader is sent to find `where acc.is_active` in
--   049, finds nothing, and cannot verify why the omission is safe. That is the
--   precise state in which someone "helpfully" adds a predicate and
--   DOUBLE-FILTERS. Documentation, but documentation that justifies a
--   safety-relevant omission — so it rides here rather than as a follow-up.
--
--   SCOPE NOTE — two different surfaces, and only one is reachable. Sec cited
--   three sites; those are line numbers in the MERGED 051 FILE. Only ONE lives
--   in the function body, and only that one is a live database object that
--   `create or replace` can correct. The other two are `--` comments in a
--   merged migration: unreachable by any migration, correctly stale as dated
--   artifacts, and NOT rewritten here — editing merged text is the §7.6 S3
--   scoping-guard violation.
--
--   Produced the same way as the bodies above: pg_get_functiondef() output with
--   the comment substituted, DIFF-PROVED as comment-only (1 line → 6, nothing
--   else). The control applies to prose too.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pfin.fn_nav_composition(p_as_of date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  with
  -- LEAF rows: 049 (single substrate — per active account current_market_value + unrealized_gl,
  -- naturally signed) joined to pfin.account for name + account_type (grouping key). 049 already
  -- filters by the as-of predicate (closed_at is null or closed_at > p_as_of) — the
  -- boolean flag it used to filter on was RETIRED at 059 — so composing on 049
  -- inherits the correct filter for free. This function adds NO predicate of its
  -- own, and MUST NOT: adding one here would double-filter. If you came looking
  -- for 'where acc.is_active' in 049 because an older comment sent you, that is
  -- what this note replaces.
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
$function$
;

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

-- ----------------------------------------------------------------------------
-- (7) ACCEPTANCE GATE — SMOKE INVOCATION. The modality is the point.
--
--   THE WITHDRAWN GATE, AND WHY NO REFINEMENT OF IT COULD HAVE WORKED. The
--   first design was a static `pg_proc.prosrc ilike '%is_active%'` check
--   asserting zero rows. Two reasons it is gone; only the second is the disease:
--     (a) IT CAN NEVER RETURN ZERO ON A CORRECT 059. `is_active` is declared on
--         FIVE pfin tables — account (003) · user_taxonomy (009) ·
--         linked_source (015) · asset (016) ·
--         linked_source_connection_state (043) — and a text match cannot tell
--         which table a reference belongs to, so legitimate residue is
--         permanent. A GATE THAT CAN NEVER GO GREEN IS WAIVED THE FIRST TIME IT
--         IS HIT, and then it occupies the slot a working one would have had.
--     (b) MODALITY MISMATCH. The failure guarded is a RUNTIME one: an old-style
--         SQL body is not parsed at DDL time and breaks at FIRST CALL. A STATIC
--         TEXT SEARCH CANNOT DECIDE A RUNTIME PROPERTY, and no refinement of
--         that query could have. (a) was a symptom of (b).
--         Discovery finds candidates; only EXECUTION proves absence.
--
--   WHY ONE CALL PER FUNCTION SUFFICES — and the condition EXPIRES, so it is
--   stated rather than assumed. These are `language sql` with OLD-STYLE text
--   bodies, parsed AS A WHOLE at execution. A missing column therefore raises
--   regardless of argument values — including fn_compute_nav(_, false), where
--   the predicate branch might look skippable. It is not; it is parsed anyway.
--   ⚠ THIS DOES NOT HOLD FOR plpgsql, where statements parse LAZILY PER BRANCH
--     at first execution — one call would prove only the branch it took.
--     Measured today: zero plpgsql among these. IF ANY IS EVER CONVERTED TO
--     plpgsql THIS GATE SILENTLY STOPS PROVING WHAT IT CLAIMS, and needs
--     per-branch coverage instead.
--     >> DIRECTION OF THAT FAILURE: **FAIL-OPEN.** The gate keeps passing and
--        stops detecting. Nothing goes red at the moment it is defeated. <<
--
--   ON DECLARING LIMITATIONS AT ALL (Sec, and it applies to this very block):
--     twice today an artifact's own stated rationale turned out to be the
--     argument someone would use to weaken it later — 057's deliberately
--     inconsistent guards, and the withdrawn static gate's "string literals
--     false-positive" note, which invited extending the stripper to literals
--     and would have made it fail OPEN on dynamic SQL.
--     >> So: PAIR EVERY DECLARED LIMITATION WITH ITS FAILURE DIRECTION. A
--        limitation that fails CLOSED is an inconvenience worth documenting
--        plainly. One that fails OPEN is a prohibition, and must be written as
--        one — because the person "fixing" it will be reading your own
--        explanation of why it is imperfect. <<
--
--   Sited AFTER the drop because that is the only point at which the runtime
--   failure is reachable at all. Under the CLI's per-file transaction a raise
--   here aborts the migration, making it a genuine fail-closed gate; if that
--   wrapper is ever absent it still fails loudly in the same run, and the
--   prefix-safe ORDERING above is what keeps intermediate states coherent
--   independently of it.
-- ----------------------------------------------------------------------------
do $$
declare
  v_num  numeric;
  v_rows bigint;
  v_json jsonb;
begin
  select pfin.fn_compute_nav(current_date)        into v_num;
  select pfin.fn_compute_nav(current_date, true)  into v_num;
  select pfin.fn_compute_nav(current_date, false) into v_num;
  select count(*) into v_rows from pfin.fn_account_unrealized_gl(current_date);
  select count(*) into v_rows from pfin.fn_account_cash_as_of(current_date);
  select pfin.fn_nav_composition(current_date)    into v_json;
exception
  when undefined_column then
    raise exception
      'POST-DROP SMOKE FAILED — a function still references the dropped column: %. The re-point at step (2) was INCOMPLETE. Old-style SQL bodies carry no dependency records, so the DROP above succeeded regardless; this call is the only thing that detects it. Re-point the function — do NOT re-add the column.', sqlerrm;
end $$;

comment on column pfin.account.closed_at is
  'THE ONLY representation of open/closed (ADR-042). The boolean flag was retired at 059: it answered "open NOW" where closed_at answers "open AS OF a date" — strictly more information, and the two coexisting was the three-way overloading ADR-042 exists to remove. Readers use (closed_at is null or closed_at > p_as_of); NEVER a bare `closed_at is null` in an as-of context, and never a LEFT-JOINed `closed_at is null` without an accompanying `account_id is not null`, which fails OPEN by asserting "not closed" from no information.';

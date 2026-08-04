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
-- IF THIS MIGRATION FAILS PART-WAY — READ THIS FIRST.
--   Written for an OPERATOR MID-INCIDENT, not for a test. Under the CLI's
--   per-file transaction none of these states is reachable; this is for the
--   paths that are not the CLI, and for the person who has one anyway.
--
--     failed at (1) VALIDATE      Nothing has changed. The failure IS the
--                                 finding: the operator step left a row where
--                                 is_active and closed_at disagree. Both
--                                 columns still exist, so the mismatch is
--                                 diagnosable — find it before re-running.
--                                 Match the MESSAGE, not SQLSTATE 23514.
--     failed inside (2) or (2b)   Some functions re-pointed, some not. SAFE:
--                                 both columns exist AND both the sync trigger
--                                 and the biconditional are still maintaining
--                                 them, so re-pointed and un-re-pointed
--                                 functions agree. FIX AND RE-RUN THE WHOLE
--                                 FILE — verified re-runnable from this prefix
--                                 (VALIDATE is repeatable while the constraint
--                                 exists, and every re-point is CREATE OR
--                                 REPLACE).
--     failed at (4) itself        Constraint still present (the drop is what
--                                 failed), everything re-pointed. SAFE, and
--                                 re-running the whole file still works.
--     failed at (5) or (6)        Constraint ALREADY DROPPED, column still
--                                 present, everything re-pointed. SAFE —
--                                 nothing reads is_active. ⚠ BUT DO NOT re-run
--                                 the whole file: step (1) will fail with
--                                 `constraint "account_closure_biconditional"
--                                 of relation "account" does not exist`.
--                                 MEASURED, not assumed. Resume from the
--                                 statement that failed. (The drops are NOT
--                                 written `if exists`, deliberately: a guard
--                                 there would make a re-run silently skip a
--                                 step that had not actually happened, which is
--                                 the 057 trap in the other direction.)
--     failed at (6) DROP COLUMN   If it failed, something TRACKED depends on the
--                                 column (a view, policy or constraint). That
--                                 is the good outcome. Enumerate the dependent
--                                 and handle it explicitly. DO NOT reach for
--                                 CASCADE — see below.
--     failed at (7) SMOKE         ⚠ THE ONLY STATE NEEDING JUDGEMENT. The column
--                                 is gone and a function still references it.
--                                 **DO NOT RE-ADD is_active.** Re-adding
--                                 restores a column nothing maintains — the
--                                 sync trigger and the biconditional are
--                                 already gone at this point — so the two
--                                 representations would silently diverge and
--                                 the NAV path would read a stale flag. The
--                                 raise names the function: RE-POINT IT.
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


-- The CATALOG comment is a separate object from the body comment above and
-- survives CREATE OR REPLACE (comments attach by signature), so re-pointing the
-- body does NOT correct it (Sec flag at d773006). Left alone, \df+ and
-- obj_description() would keep reporting "049 already filters is_active" after
-- step (6) — false, on the surface most tooling actually shows, and for many
-- readers MORE reachable than the in-body comment. Same reasoning as the body
-- fix: this is the documentation that justifies a safety-relevant omission.
-- Regenerated from obj_description() and diff-proved: ONE substitution.
comment on function pfin.fn_nav_composition(date) is
  'SECURITY INVOKER §2.1.5 NAV-composition aggregation (V1.1 "Net worth full"; PRD §2.1.5 / SELF-225; Lock 11 read-composition). Returns the composition tree as JSONB: {groups:[{category, accounts:[{account_id, account_name, current_market_value, unrealized_gl}], subtotal}], buildups:{total_non_re, gross_total, debt, realized_tax_liab, unrealized_tax_liab}, nav}. COMPOSES ON 049 fn_account_unrealized_gl (single leaf substrate — per active account current_market_value + unrealized_gl, naturally signed) joined to pfin.account for name + account_type; 049 already filters by the AS-OF predicate (closed_at is null or closed_at > p_as_of) — the boolean flag it used to filter on was RETIRED at 059 per ADR-042, and this function still adds NO predicate of its own and MUST NOT (adding one double-filters). groups[] in canonical category order (depository/investment/retirement/crypto/manual_other → real_estate → liability; §2.1.5/AC#2), empty categories omitted; accounts[] by account_id; leaf unrealized_gl NULL for non-investment (049, AC#3). DEBT SIGN (D-1): liability leaves + subtotal carry 049''s natural negative sign; buildups.debt = −(liability subtotal) = positive magnitude so AC#4 nav = gross_total − debt reads literally. TAX PLACEHOLDERS = Option A V1.1 (AC#5): realized/unrealized_tax_liab = 0::numeric, V1.4 ramp. FOOT-TO-NAV EXACT (ADR-038/039): nav = total_non_re + real_estate + Σ liability_signed = Σ 049(active) = fn_compute_nav(p_as_of, true) BY CONSTRUCTION (single-substrate natural summation; no separate fn_compute_nav call). p_scope DROPPED (pfin.scope type does not exist; scope is a free-text ADR-004 label — per-scope reporting is V2+, PRD §2.1.7); p_users_id DROPPED (INVOKER + RLS scope by auth.uid()). AS-OF via 049 threading (Lock 15; V1.1 consumers pass CURRENT_DATE). INVOKER → cross-tenant caller sees no rows → empty groups / nav 0 (fails closed). set search_path=''''; NOT a DEFINER allowlist entry (stays 4); §10 ledger stays 3; Decision-3 unchanged (no new FK column). Sec joint-review-mandatory (financial calc + multi-tenant); RLS verification → SELF-225 two-tenant battery. §2.1.6 MV-vs-COST-BASIS AUDIT-TRACE (SELF-227, comment-only — no body/signature/logic change): investment-account contributions to NAV use CURRENT MARKET VALUE (eod_price × qty × fx), NOT cost basis; cost basis is confined to 049.cost_basis / unrealized_gl (+ future §2.2.x cost-basis-display surfaces). PRD §2.1.6 / SELF-227.';


-- ----------------------------------------------------------------------------
-- (2c) CATALOG COMMENTS THIS MIGRATION FALSIFIES (Sec ruling).
--
--   >> A migration must not leave behind documentation that its own change
--      falsifies. << Split by FALSIFIER, not by convenience: the two comments
--   058 broke ride with 058; these two ride here.
--
--   A `comment on function` is a SEPARATE OBJECT from the body comments above
--   and survives CREATE OR REPLACE — comments attach by signature. So the
--   re-points at (2) did NOT correct these, and \df+ / obj_description() are
--   what most readers actually see.
--
--   ⚠ fn_compute_nav's comment is corrected ONLY IN PART, deliberately. Its
--     "SOUND ONLY at p_as_of=current_date" clause is a FILED DECISION — the
--     ADR-039 amendment that ADR-042 strikes, booked in BACKLOG §7.7 as its own
--     comment-only migration. It is left INTACT with an explicit
--     known-stale-and-why marker beside it. 059 corrects what 059 falsifies and
--     does not absorb work booked elsewhere. YOU MAY FIX HALF A COMMENT.
--
--   Both regenerated from obj_description(), ONE substitution each, diff-proved.
--   Residual `is_active` is EXPECTED and non-zero in fn_compute_nav: one
--   historical back-reference and the deliberately-preserved ADR-039 clause.
-- ----------------------------------------------------------------------------
comment on function pfin.fn_account_unrealized_gl(date) is
  'SECURITY INVOKER per-account unrealized-G/L aggregation primitive (V1.1 "Net worth full"; PRD §2.1.5.a / SELF-224; shared with §2.2 asset-allocation V1.2; Lock 11 read-composition — clones the fn_compute_nav / fn_gl_entries posture). One row per account OPEN AS OF p_as_of visible to the caller (was: non-inactive; the boolean was RETIRED at 059 per ADR-042). DESIGN C (account-total, symmetric; ADR-038, F/CTO 2026-08-02). current_market_value (ALL types, uniform) = securities MV [Σ(fn_holdings_as_of qty × best-available eod_price[D-first LOCF] × fx→USD)] + cash [roll-forward balance × fx→USD] = the account''s fn_compute_nav contribution → Σ over ACTIVE accounts = fn_compute_nav OVER ACTIVE ACCOUNTS ONLY (049 filters by the as-of open/closed predicate per PRD §2.4.2 — closed_at is null or closed_at > p_as_of; fn_compute_nav/019 does not — they diverge only on a value-bearing inactive account; that 019 scope gap is tracked separately, and 049''s open/closed filter is correct). (securities & cash disjoint per the 017 CHECK — counted once). INVESTMENT-class (account_type ∈ investment/retirement/crypto, 003 CHECK): cost_basis = securities carried book [Σ(fn_gl_entries `trade_position` × fx→USD) — acquisition + basis_adjust − FIFO/specific-lot matched-sell removal; single basis truth == GL == tax == reports; unmatched sells leave basis on the books per 037 Suspense floor] + the SAME roll-forward cash term as mv (the shared cash figure → cancels; NOT fn_gl_entries asset_liability, a pure-ledger Σ that diverges when a checkpoint exists). REDEFINITION: cost_basis is the ACCOUNT-TOTAL BOOK (securities book + cash face), not AC#2-literal securities-only. unrealized_gl = current_market_value − cost_basis = securities MV − securities book (pure securities G/L; cash cancels exactly). NON-INVESTMENT (depository/manual_other/real_estate/liability): cost_basis = unrealized_gl = NULL (NOT 0 — concept-does-not-apply discriminator; a zero-everything investment account returns 0/0/0). AS-OF (Lock 15 Decision 19; server-derived-only per Lock 15 mod #2, V1.1 consumers pass CURRENT_DATE): the composed fns thread p_as_of → historical eod_price + account_trans / lot_match ≤ as_of. INVOKER → cross-tenant caller sees no rows (fails closed); unpriced asset → NULL term → dropped → 0, never NaN. Per-lot decomposition is an additive future helper (buy side already per-lot; removal detail preserved in immutable lot_match), reconcilable by construction — the GL-derived basis path does not foreclose lot-level UI (V2). set search_path=''''; NOT a DEFINER allowlist entry (INVOKER) — allowlist stays 4; §10 ledger stays 3; Decision-3 unchanged (no new FK column). Sec joint-review-mandatory (financial calc + multi-tenant); RLS verification → SELF-228 two-tenant battery. §2.1.6 MV-vs-COST-BASIS AUDIT-TRACE (SELF-227, comment-only — no body/signature/logic change): investment-account contributions to NAV use CURRENT MARKET VALUE (eod_price × qty × fx), NOT cost basis; cost basis is confined to 049.cost_basis / unrealized_gl (this function''s own investment-class output columns) + future §2.2.x cost-basis-display surfaces. PRD §2.1.6 / SELF-227.';

comment on function pfin.fn_compute_nav(date, boolean) is
  'SECURITY INVOKER uniform roll-forward net-worth read (ADR-027 §5 / Lock 11; SELF-322 / ADR-039). 019''s valuation VERBATIM + AS-OF OPEN/CLOSED scoping GATED on p_active_only (was is_active; the boolean was RETIRED at 059 per ADR-042 and the predicate is now closed_at is null or closed_at > p_as_of). p_active_only=FALSE → byte-identical to 019 (ALL accounts — the book/as-of engine: 037 GL memo + historical trend). p_active_only=TRUE → CURRENT-STATE (active accounts only; the §2.1.1 headline via netWorth.ts) — SOUND ONLY at p_as_of=current_date (is_active is current-state, not temporal; filtering it into a past as_of rewrites history — see 050 TEMPORAL CONSTRAINT; §2.1.2 trajectory/nav_daily must use frozen precomputed checkpoints). ⚠ THE PRECEDING SOUND-ONLY-AT-CURRENT_DATE CLAUSE IS KNOWN STALE AND DELIBERATELY LEFT INTACT BY 059: ADR-042 STRIKES it, because closed_at IS temporal and an as-of predicate does not rewrite history. It is NOT corrected here because it is a FILED DECISION (the ADR-039 amendment, booked in BACKLOG §7.7 as its own comment-only migration) and 059 does not get to absorb work booked elsewhere. 059 corrects only what 059 falsifies. Do not read the clause as current. securities leg filters via LEFT JOIN pfin.account on holdings.account_id; cash leg via pfin.account — both gate on the as-of open/closed predicate ONLY when p_active_only, and the securities leg carries the FAIL-CLOSED conjunct acc2.account_id is not null (a LEFT JOIN miss must EXCLUDE, not include; the naive closed_at is null alone fails OPEN). Makes the ADR-038 foot-to-NAV invariant EXACT: Σ 049.current_market_value(active) = fn_compute_nav(as_of, true). INVOKER (cross-tenant → 0, fails closed); unpriced asset → NULL → dropped → 0, never NaN. set search_path=''''; NOT a DEFINER allowlist entry (stays 4); §10 ledger 3; Decision-3 unchanged. EXECUTE revoked from PUBLIC, granted to authenticated. §2.1.6 MV-vs-COST-BASIS AUDIT-TRACE (SELF-227, comment-only — no body/signature/logic change): investment-account contributions to NAV use CURRENT MARKET VALUE (eod_price × qty × fx), NOT cost basis; cost basis is confined to 049.cost_basis / unrealized_gl (+ future §2.2.x cost-basis-display surfaces). PRD §2.1.6 / SELF-227.';


-- ----------------------------------------------------------------------------
-- (2d) THE ONE COMMENT THAT MUST *NOT* BE RE-POINTED — qualified instead.
--
--   fn_aggregation_has_stale_constituent (046) reads linked_source.is_active,
--   the CONNECTION-level lifecycle column, which ADR-042 PRESERVES. Its scoping
--   is CORRECT and is NOT changed here. It appears in the sweep only because its
--   catalog comment said a BARE `is_active` with no qualifier.
--
--   >> IT IS NAMED HERE RATHER THAN SILENTLY SKIPPED. A sweep that quietly
--      passes over one of five is indistinguishable from a sweep that missed
--      one. (team-lead) <<
--
--   WHY A QUALIFIER-ONLY EDIT BELONGS IN 059 UNDER THE FALSIFIER RULE — the
--   argument, because 059 does not falsify this comment and the rule would
--   otherwise exclude it. 059 removes ONE OF THE TWO REFERENTS of a bare
--   `is_active`. Before 059 the term was ambiguous between two live columns;
--   after 059 it is ambiguous-BY-ABSENCE — a reader meets a bare `is_active`,
--   knows the account column was just dropped, and reasonably concludes this
--   comment is stale. So 059 does not make the sentence FALSE; it makes the
--   sentence MISREAD. That is a consequence of this migration and belongs to it.
--   ⚠ Sec: if you read the falsifier rule as excluding this, say so and it moves
--     out — the edit is comment-only and independent of everything else here.
--
--   The token collision cost roughly five misclassifications in one day,
--   including one of mine that nearly reported ADR-042's own 059 scope as
--   incomplete. Qualifying the source is cheaper than every future sweep having
--   to be careful: put the disambiguation where the confusion happens.
--
--   A catalog object, so it needs its own re-emit — it cannot ride a function
--   redefinition. Regenerated from obj_description(), ONE substitution,
--   diff-proved. NO behaviour change and NO scoping change.
-- ----------------------------------------------------------------------------
comment on function pfin.fn_aggregation_has_stale_constituent() is
  'SECURITY INVOKER staleness-detection primitive (SELF-208 §2.4.4.c; ADR-013 D1 non-silent staleness framework; RT-13). Returns ONE aggregate row (is_stale boolean, stale_items jsonb) for the calling user: is_stale = TRUE iff the caller owns >=1 ACTIVE linked_source whose connection_status <> ''healthy''; stale_items = jsonb array of {linked_source_id, institution_name, provider, connection_status, status_class} for those sources (''[]'' when none). Composes over the 043 pfin.linked_source_connection_state INVOKER view (Lock 11 read-composition) — owner isolation + the 025 aal2 gate are INHERITED via linked_source RLS (auth.uid() scope; RT-13 requesting-tenant-scoped credential-state resolution satisfied structurally). Scopes to the 043 view linked_source_connection_state''s is_active=TRUE — a PLAIN PROJECTION of linked_source.is_active (verified: ls.is_active, no CASE, no coalesce, no derivation), which is THE CONNECTION-LEVEL LIFECYCLE COLUMN, NOT pfin.account.is_active, WHICH WAS RETIRED AT 059 (ADR-042). This column SURVIVES and this scoping is CORRECT AND UNCHANGED; the qualifier is here because a bare ''is_active'' in a pfin comment became ambiguous-by-absence once the account column was dropped — to match the NAV constituent contract (netWorth.ts connection filter) — an inactive/suspended source feeds nothing into the number so flagging it would be a false positive (NOT a D1 violation: D1 governs the honesty of the number the user sees). D1-FORWARD: the §2.4.4 surface list is illustrative-not-exhaustive; this framework applies to every aggregation consuming Plaid-sourced data — V1.0 wires NAV (§2.1.1), ramp at V1.1+ (§2.1.2/§2.1.5/§2.2.2/§2.3.2/§2.3.4/§2.6). Per-status affordance (Frontend): key on connection_status — Re-authenticate for IN (login_required,revoked,disconnected), informational for institution_down (marked-but-not-reauth); provider dispatches reauth() per adapter; status_class is context not driver. Authors no function with DEFINER (allowlist stays 4), no FK column (Decision-3 unchanged 15/13), no service_role (RT-26 stays 4), no catalogued §10 instance (stays 3).';

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

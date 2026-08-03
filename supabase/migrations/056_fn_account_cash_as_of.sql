-- ============================================================================
-- 056_fn_account_cash_as_of.sql — extract the per-account NATIVE cash
--   roll-forward into one named function, and re-point 049 + 050 onto it.
--
-- Numbering: 056 follows 055. FIRST of the ADR-042 slice set (056 / 058 / 059);
--   057 (pfin.account_event) and 058/059 (the closure model) depend on nothing
--   here except that 058's gate calls this function.
--
-- WHAT THIS IS: a PURE BEHAVIOUR-PRESERVING REFACTOR. No semantic change, no
--   signature change, no new grant, no new table. It exists so that the ADR-042
--   close gate and the NAV path consume ONE definition of "this account's cash"
--   rather than two copies that can drift apart silently.
--
-- WHY (ADR-042 Decision 3, the "measure" paragraph): the closure gate must test
--   a zero cash balance. Three ways to get that were considered:
--     (a) reuse 049's current_market_value  — REJECTED: it multiplies by an FX
--         rate, and eod_price carries ONLY a NaN fence (019:220-223, no
--         positivity constraint), so a zero-or-negative fx_feed rate zeroes or
--         SIGN-FLIPS a foreign-currency cash leg. A fence whose correctness
--         depends on price data is not a fence. (The unconstrained rate is a
--         live NAV defect independent of closure — BACKLOG.md §7.7.)
--     (b) inline the roll-forward inside the gate — REJECTED: a THIRD copy
--         (after 049 and 050), inside a security fence, where drift is silent.
--         Worse, the fence would then measure a quantity the app does not
--         report: it could be green while NAV is wrong, and wrong while NAV is
--         right. It fails APART from NAV; nothing catches that.
--     (c) EXTRACT — CHOSEN. Fence and NAV consume one definition, so they can
--         only fail TOGETHER — and failing together is exactly what the ADR-038
--         foot-to-NAV invariant already detects.
--
-- NATIVE, NOT USD — load-bearing. This function applies NO fx multiplier. The
--   callers keep their own fx term (unchanged, per-caller), so this refactor
--   moves no FX behaviour. The gate consumes the native figure precisely so it
--   depends on no price row at all.
--
-- EXACT-ZERO: the roll-forward is numeric(20,4) addition only — no division,
--   no multiplier — so zero is exactly representable and the gate needs no
--   tolerance. That property is why the extraction is native (ADR-042 D3).
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE
--   SECURITY INVOKER. This is a read primitive over tenant-scoped data; it must
--   compose with RLS as the caller, exactly as 019 / 049 / 050 do (Lock 11
--   INVOKER read-composition). It needs no elevation: every table it touches is
--   reachable by the owner under existing policies. NOT a DEFINER allowlist
--   entry — the allowlist stays 4 (3 authored).
--   Reads pfin.account (direct-owner RLS), pfin.account_balance_checkpoint and
--   pfin.account_trans (both rd_access-JOIN + the 025 aal2 conjunct). A
--   cross-tenant caller sees no rows -> empty set, fails closed.
--   set search_path = '' is the injection fence; all refs fully qualified.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_account_cash_as_of(p_as_of date)
--     RETURNS TABLE (account_id bigint, balance_native numeric)
--     SECURITY INVOKER, STABLE, set search_path = ''.
--     TOTALITY IS A CONTRACT, NOT AN INCIDENT (Sec, at the 056 review — the one
--       thing a text-diff of the extraction CANNOT see):
--       Inline, this roll-forward was a CORRELATED SUBQUERY evaluated per outer
--       account row, so an account with neither checkpoint nor transactions
--       still produced a row, valued coalesce(...,0)+coalesce(...,0) = 0.
--       Extracted, it is a SET-RETURNING FUNCTION joined at the call site — and
--       an account ABSENT from its output DISAPPEARS from the result rather
--       than contributing zero. Absent-row vs zero-row: the same failure class
--       the project has named elsewhere, here reached through a refactor.
--       THEREFORE: this function returns EXACTLY ONE ROW PER pfin.account ROW
--       VISIBLE TO THE CALLER, ALWAYS — including accounts with no checkpoint
--       and no transactions, and INCLUDING inactive/closed accounts. That is
--       structural (`from pfin.account acc` drives the projection; both legs
--       hang off it and coalesce to 0), not incidental to every account
--       happening to have data.
--       DO NOT "optimize" this by skipping accounts with no activity. It would
--       be invisible at the call sites and would silently drop those accounts
--       from NAV.
--     CALL SITES MUST **LEFT JOIN**, NOT INNER — belt to the above braces. If
--       totality is ever broken, an inner join turns it into MISSING accounts
--       (silent); a left join + coalesce turns it into 0, which is exactly the
--       pre-extraction behaviour. One degrades to the old semantics, the other
--       to a wrong number.
--     Filtering is the CALLER's job (050 gates on p_active_only; the 058 gate is
--     called for one specific account). A function that filtered here could not
--     serve the gate, which must measure an account precisely when it is about
--     to stop being current-state.
--     balance_native = checkpoint-anchored roll-forward in the ACCOUNT'S OWN
--     currency: the latest account_balance_checkpoint at or before p_as_of,
--     plus the sum of account_trans amounts strictly after that checkpoint's
--     date and at or before p_as_of. No checkpoint -> anchor 0 and sum all
--     transactions <= p_as_of ('-infinity' sentinel, 019/050 idiom).
--     Never NULL: both legs coalesce to 0, so an account with no checkpoint and
--     no transactions returns exactly 0.
--   Security-load-bearing edges: INVOKER (cross-tenant -> empty set);
--     no fx term, therefore no dependency on eod_price; EXECUTE revoked from
--     PUBLIC, granted to authenticated only.
--
-- DUPLICATION CONFIRMED BEFORE EXTRACTING (the precondition that makes this a
--   refactor rather than a rewrite): the roll-forward at 049:314-330 and the one
--   at 050:175-191 are the SAME expression, character for character — same
--   checkpoint anchor, same '-infinity' sentinel, same strict > on the
--   post-checkpoint sum. Both files then apply their own fx multiplier
--   separately. So the extraction is exact by inspection, not by intent, and
--   the two call sites can be re-pointed without behavioural change.
--
-- PERFORMANCE NOTE (behaviour-neutral, stated so it is not mistaken for a
--   regression): 050's cash_leg previously computed the roll-forward only for
--   rows surviving `where (not p_active_only or acc.is_active)`. Consuming this
--   function computes it for every visible account and filters after. Identical
--   results; more work on a large account set. Acceptable at V1 scale and
--   revisitable by pushing a predicate in, which would then have to be pushed
--   into the gate's call path too — the single-definition property is worth
--   more than the saved rows.
--
-- PREDICATE DELIBERATELY UNTOUCHED HERE. This migration reproduces
--   `(not p_active_only or acc.is_active)` VERBATIM. 056 is the EXTRACTION; the
--   as-of predicate swap (`closed_at is null or closed_at > p_as_of`) is 059's.
--   Reading 056 alone, the absence of the dated form is a deliberate scope
--   boundary, NOT an oversight.
--
-- WHO VERIFIES THIS IS PART OF THE CONTROL. Byte-identity is NOT to be run by
--   the author of the refactor against a fixture of the author's choosing: that
--   tests the author's understanding of what they meant, not what the code does.
--   The fixture belongs to QA — someone who was not in the room when the
--   refactor was designed. A future maintainer under time pressure who
--   "helpfully" verifies their own change here will produce something that
--   looks exactly like diligence and is not.
--
-- ----------------------------------------------------------------------------
-- VERIFICATION REQUIRED BEFORE MERGE (ADR-040 assembled-sequence discipline,
--   and it applies to the PAIR 056+059, not per-file — 049/050 are edited
--   TWICE across this slice set, so verifying 056 alone against a 059-shaped
--   assumption is exactly the seam that B9 hid in):
--     (1) NAV byte-identical before/after, PER LEG, on a fixture carrying FX +
--         a checkpoint + post-checkpoint transactions (the three interacting
--         paths);
--     (2) the ADR-038 foot-to-NAV invariant re-asserted (exact per ADR-039);
--     (3) run the assembled statement sequence against a live database in a
--         ROLLED-BACK transaction, as the deploying identity, using the exact
--         production statement text.
--   Do NOT `supabase db reset` to verify — it destroys the F/CTO's active local
--   test data (feedback_migration_verify_resets_local_db).
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- (1) The extracted primitive. The body is 050's cash_leg roll-forward
--     VERBATIM, with the fx multiplier REMOVED (it stays at the call sites) and
--     the per-account grouping made explicit in the projection.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_account_cash_as_of(p_as_of date)
returns table (account_id bigint, balance_native numeric)
language sql
security invoker
stable
set search_path = ''
as $$
  select
    acc.account_id,
    (
      coalesce((select cbc.balance
                from pfin.account_balance_checkpoint cbc
                where cbc.account_id = acc.account_id
                  and cbc.as_of_date <= p_as_of
                order by cbc.as_of_date desc, cbc.balance_id desc
                limit 1), 0)
      + coalesce((select sum(at.amount)
                  from pfin.account_trans at
                  where at.account_id = acc.account_id
                    and at.transaction_date <= p_as_of
                    and at.transaction_date > coalesce((
                      select cbc2.as_of_date
                      from pfin.account_balance_checkpoint cbc2
                      where cbc2.account_id = acc.account_id
                        and cbc2.as_of_date <= p_as_of
                      order by cbc2.as_of_date desc, cbc2.balance_id desc
                      limit 1), '-infinity'::date)), 0)
    ) as balance_native
  from pfin.account acc;
$$;

revoke execute on function pfin.fn_account_cash_as_of(date) from public;
grant execute on function pfin.fn_account_cash_as_of(date) to authenticated;

comment on function pfin.fn_account_cash_as_of(date) is
  'SECURITY INVOKER per-account NATIVE cash roll-forward (ADR-042 Decision 3; '
  'Lock 11 read-composition). One row per caller-visible pfin.account row, '
  'INCLUDING inactive/closed accounts — filtering is the caller''s job, because '
  'the ADR-042 close gate must measure an account exactly when it is about to '
  'stop being current-state. balance_native = latest account_balance_checkpoint '
  'at or before p_as_of + sum(account_trans.amount) strictly after that '
  'checkpoint date and at or before p_as_of; no checkpoint => anchor 0 over all '
  'transactions <= p_as_of (''-infinity'' sentinel, the 019/050 idiom). Never '
  'NULL (both legs coalesce to 0). NO FX MULTIPLIER — deliberately native: '
  'eod_price carries only a NaN fence (019:220-223, no positivity constraint), '
  'so a zero-or-negative fx_feed rate would zero or SIGN-FLIP the leg, and a '
  'fence whose correctness depends on price data is not a fence. Callers keep '
  'their own fx term unchanged. numeric(20,4) addition only — no division, no '
  'multiplier — so exact zero is exactly representable and the gate needs no '
  'tolerance. Extracted from 050''s cash_leg so the close gate and the NAV path '
  'share ONE definition and can only fail TOGETHER (the ADR-038 foot-to-NAV '
  'invariant is the detector); a third inline copy inside the fence would fail '
  'APART from NAV, green while NAV is wrong and wrong while NAV is right. '
  'INVOKER: cross-tenant caller sees no rows => empty set, fails closed. '
  'set search_path = ''''; NOT a DEFINER allowlist entry (stays 4). EXECUTE '
  'revoked from PUBLIC, granted to authenticated only.';

-- ============================================================================
-- (2) RE-POINT — `050`'s cash_leg consumes the extracted function.
--
-- CREATE OR REPLACE in place: signature identical to `050`, so the 1-arg wrapper
--   and `037 fn_gl_entries`' Unrealized memo are untouched (no DROP, dependency
--   intact). The securities leg is reproduced VERBATIM from `050` — only the
--   cash leg changes.
--
-- WHAT CHANGED, precisely: the inline roll-forward at `050:175-191` is replaced
--   by `c.balance_native` from a LEFT JOIN. The fx multiplier, the
--   `(not p_active_only or acc.is_active)` filter, and the `coalesce(sum(...),0)`
--   wrapper are all unchanged.
--
-- LEFT JOIN, NOT INNER — required, and it is not redundant with the function's
--   totality contract. It changes what a breach COSTS: an inner join turns a
--   totality failure into MISSING accounts (silent, wrong number); a left join
--   plus `coalesce(...,0)` turns it into 0, which is exactly the pre-extraction
--   behaviour. One degrades to the old semantics, the other to a wrong one.
--
-- SHORT-CIRCUIT IS LOAD-BEARING (do not "improve" this):
--   `p_active_only = false` means NO predicate — `not false` short-circuits and
--   `acc.is_active` is never evaluated. It does NOT mean "a predicate that
--   happens to be true for everything". `037`'s Unrealized memo is
--   fn_compute_nav − book_nav with BOTH legs all-accounts, and `fn_gl_entries`
--   carries no account filter at all, so narrowing the false-branch produces a
--   PHANTOM IMBALANCE that ships green (nothing asserts the two legs share a
--   scope). The 1-arg wrapper inherits this silently — its meaning would change
--   without one character of its own text changing. At `059`, substitute the
--   PREDICATE only; keep this `(not p_active_only or …)` structure literally.
-- ============================================================================

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
    where (not p_active_only or acc.is_active)
  )
  select (select v from security_leg) + (select v from cash_leg);
$$;

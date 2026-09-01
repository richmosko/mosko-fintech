-- ============================================================================
-- Migration: pfin.fn_historical_expenditures — the PRD §2.3.4 Historical
--            Expenditures series, inflation-normalized.
-- Phase 6 Build Loop (SELF-255; PRD §2.3.4). The THIRD surface to compose on the
-- ONE extracted §2.3 reader, and the first §2.3 surface to compose on the
-- ratified CPI-U resolver as well — it sits on the intersection of the §2.3
-- money path and the §2.1.2 deflator path, and restates the rules of neither.
--
-- Numbering: next free number at authoring time; the live tail was 095. Depends
-- on 093 (pfin.fn_cashflow_items — THE reader this function composes on, and the
-- sole home of the six reader rules) · 091 (posting_prototype.is_tax_payment,
-- the marker the §2.3.4 scope subtracts on) · 084 (the posting_prototype the
-- reader resolves cat/sub_cat through, and which this function re-reads for one
-- further attribute) · 066 (pfin.fn_cpi_u_index_for_period — the sanctioned
-- CPI-U resolver; the carry-forward and gap policy live there and ONLY there)
-- · 067 (the §2.1.2 inflation-adjusted series whose basis choice and cpi_*
-- projection this function mirrors deliberately) · 095 (the additive
-- finite-and-strictly-positive CHECK on pfin.cpi_u_index.cpi_value).
--
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT
-- SECURITY DEFINER. This function reads two relations: the SECURITY INVOKER
-- reader pfin.fn_cashflow_items and pfin.posting_prototype, both under the
-- caller's own session, plus the SECURITY INVOKER CPI resolver over the
-- global-shared-read pfin.cpi_u_index. Tenant isolation is INHERITED, never
-- asserted here — the reader's own composition gates pfin.account_trans /
-- account_trans_annotation / account_trans_split on pfin.account_users.rd_access
-- under auth.uid(), and pfin.posting_prototype gates on users_id = auth.uid().
-- This function takes NO tenant parameter, so there is no tenant argument to
-- forge; a cross-tenant caller sees zero rows and fails closed. ⚠ SECURITY
-- DEFINER here would be a defect rather than a convenience: it would sever the
-- posting_prototype join below from the RLS that makes it safe, and the
-- is_tax_payment lookup would then read another tenant's marker. The SECURITY
-- DEFINER allowlist (ADR-011 Decision 9, read live before drafting) is
-- UNCHANGED by this migration.
--
-- LEDGERS. §10 catalogued-instance ledger UNCHANGED — ADR-011 Decision 4 read
-- verbatim and live before drafting, 2026-08-30; three axes clean (no
-- catalogued instance added, removed, reordered or renumbered; no layer
-- re-attributed; no surface becomes "four-layer"). Path B — Decision 4 is
-- linked, not restated, and no count is carried here. ⚠ The §10 CATALOGUED set
-- and the CI-FENCED set are different sets and are not reconciled here.
-- ADR-011 Decision 3 cross-tenant FK-bypass family UNCHANGED — this migration
-- creates, alters and drops no column of any kind, FK-shaped or otherwise, and
-- no INTEGER[]; its references are join predicates inside a query, not stored
-- ones (the 081/086 precedent). No label is taken; read Decision 3's body live,
-- where the labels are non-contiguous and *labeled* versus *DDL-realized*
-- diverge.
--
-- SEC JOINT-REVIEW — MANDATORY, on two independent triggers (SELF-255 Sec gate).
--   (i)  financial calculation on the §2.3 money path.
--   (ii) a DEFLATOR — a second financial calculation, layered over the first.
--        The failure mode is not a wrong row set but a right row set divided by
--        the wrong number, which no cross-tenant leg can see. The DIVISION
--        SAFETY and BASIS blocks below are the load-bearing text.
-- ⚠ Written expecting Sec to read the SQL, not the comments.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--
--   pfin.fn_historical_expenditures(p_as_of date)
--     -> TABLE(month_end date, expense_monthly_nominal numeric,
--              expense_monthly_inflation_adjusted numeric,
--              rolling_12mo_avg_inflation_adjusted numeric,
--              cpi_period date, cpi_value numeric, cpi_is_carried boolean,
--              cpi_carried_from date, cpi_period_was_due boolean,
--              cpi_nonpublication_on_record boolean, cpi_coverage_through date)
--
--   The FIRST FOUR columns are the surface's own; the SEVEN cpi_* columns are
--   066's row for that month, prefixed, MINUS gap_class. Both halves are
--   required: without the cpi_* columns a NULL adjusted figure is illegible and
--   the PRD §2.4.4 rendering rule cannot be executed by any consumer. Stated
--   here because the four-column core and the eleven-column shape are easy to
--   read as a disagreement, and they are not one.
--
--   SIGNATURE. p_as_of date, threaded by the app. NO DEFAULT (ADR-044's
--   in-function CURRENT_DATE variant is ruled out). p_users_id and p_scope are
--   absent BY RULING, not by omission: tenancy rides RLS, and pfin.scope is not
--   a type and does not exist. §2.3.4 renders the FULL-HOUSEHOLD default per
--   ADR-004 Decision B; per-scope filtering is V2+ and no parameter anticipates
--   it. A NULL p_as_of returns zero rows — every date comparison below is NULL,
--   so it fails closed, matching the reader.
--
--   SHAPING + DEFLATION ONLY. It composes on pfin.fn_cashflow_items(p_as_of)
--   and restates NONE of the six reader rules, and it composes on
--   pfin.fn_cpi_u_index_for_period and restates NONE of the carry-forward or
--   gap-classification policy. ⚠ A reader rule appearing in this body IS the
--   drift defect the shared-reader extraction exists to prevent; a CPI carry
--   rule appearing here is the drift ADR-049 Decision 4 exists to prevent. Both
--   are standing requirements on anyone editing this body. This function
--   contains NO date predicate over pfin.account_trans — the as-of semantics are
--   the reader's rule 6 (dual-column, half-open) in full. The date arithmetic
--   below derives a MONTH GRID from p_as_of, which is arithmetic on this
--   function's own parameter and not a property of any item (the 093/094
--   `started` precedent), and buckets each emitted item by its own
--   transaction_date.
--
-- ----------------------------------------------------------------------------
-- THE WINDOW — trailing 60 COMPLETE calendar months ending at the last
-- month-end on or before p_as_of. Rolling 5-year; NOT calendar-year-aligned.
--
-- The last emitted month is the last month whose month_end is <= p_as_of. A
-- mid-month p_as_of therefore emits NOTHING for its own month, and that is the
-- decision rather than an off-by-one:
--   · Every emitted month is COMPLETE BY CONSTRUCTION. Because month_end
--     <= p_as_of for every row, the reader's rule-6 upper bound cannot truncate
--     any emitted bucket, so no bar is a partial month wearing a full month's
--     label. The alternative — emitting the current month-to-date — puts a bar
--     on the chart that is short for a reason the chart cannot show, and drags
--     the 12-month rolling average down with it on every single day of the
--     month except the last.
--   · month_end is then always a TRUE claim about the data behind the bar.
-- ⚠ The consequence, stated so nobody reads it as a gap: month-to-date expense
-- is NOT on this surface. §2.3.2's `in_month` flag is where the partial current
-- month lives, and it is a different question deliberately asked elsewhere.
--
-- The reader's rule 5 period flags (in_month / in_q1..q4 / in_ytd) are NOT
-- consumed here and MUST NOT be: every one of them is anchored to year(p_as_of)
-- and to a single month, so none of them can express a 60-month rolling window.
-- 093's own comment records that rows outside year(p_as_of) are emitted with
-- every flag false FOR THIS SURFACE. Consuming the same row set with our own
-- bucketing is therefore the designed path, not a workaround.
--
-- ----------------------------------------------------------------------------
-- ZERO ROW vs NO ROW — DECIDED HERE, and the two are different claims.
-- Default-and-notify per ADR-063 Decision 3; reported to team-lead at delivery.
--
--   DECISION: DENSE INTERIOR, NO LEADING PAD.
--     · The series starts at the FIRST MONTH IN THE WINDOW THAT HAS A
--       QUALIFYING EXPENSE, and runs to the last complete month-end, with EVERY
--       intervening month emitted — a month with no qualifying expense emits a
--       row whose expense_monthly_nominal is 0.
--     · No row is emitted before that first month. A user with less than five
--       years of history gets fewer than 60 rows; a user with no qualifying
--       expense at all in the window gets ZERO ROWS.
--
--   WHY AN INTERIOR ZERO IS A ROW. It sits between two real observations, so it
--   is a MEASUREMENT — "nothing was spent in this scope that month" — and it is
--   the answer to the question the chart asks. Omitting it would let a bar
--   chart close the gap and a line overlay draw straight through a month that
--   had a real, known value of zero. Worse, it would make the rolling average
--   silently short: see the ROLLING WINDOW block.
--
--   WHY A LEADING ZERO IS NOT A ROW. Before the user's first expense, a zero is
--   NOT a measurement — it is the absence of a book, and it renders
--   identically to frugality. A five-year axis padded back to a floor the data
--   never reached tells the user they spent nothing in 2022 when the truth is
--   that we know nothing about 2022. The two states must not render the same,
--   and the honest rendering of "no data" is no bar.
--
--   AND THE TRAILING END IS NOT SYMMETRIC WITH THE LEADING END, deliberately.
--   Zero months AFTER the user's last recorded expense ARE emitted, up to the
--   last complete month. They are not the mirror of a leading pad: the upper
--   edge is anchored to a p_as_of the caller chose, so "you recorded no
--   qualifying expense last month" is a direct answer to the question asked,
--   whereas "you recorded nothing before you had a book" answers a question
--   nobody asked. It is also the convention §2.3 already runs on — 093's and
--   094's em-dash rule renders a STARTED period with no rows as $0 and only an
--   UNSTARTED one as absent, and this is the same distinction on a monthly axis.
--
--   WHY NOT SPARSE THROUGHOUT (the rejected option). It is the smaller result
--   set and it needs no anchor logic. Rejected because it makes a missing month
--   and a zero month indistinguishable at the consumer — the exact conflation
--   this decision exists to avoid — and because it silently shortens the
--   rolling window (below). Sparsity would be defensible only if the consumer
--   re-densified, which moves a §2.3 shaping rule app-side.
--
--   WHY NOT DENSE-TO-THE-FLOOR (the other rejected option). Always 60 rows is
--   the simplest contract and the easiest chart axis. Rejected on the leading-
--   zero argument above: it manufactures up to 59 rows of fabricated history.
--
-- ----------------------------------------------------------------------------
-- THE ROLLING WINDOW — and why it cannot go silently short.
--
-- rolling_12mo_avg_inflation_adjusted is the mean of the 12 inflation-adjusted
-- values at this row's month_end and the 11 month-ends before it. It is NULL in
-- exactly two cases, and both are AC-mandated:
--   (a) fewer than 12 constituent months exist at or before this row — the
--       first 11 rows of any series;
--   (b) ANY of the 12 constituents is NULL — a CPI-unresolvable month poisons
--       every window containing it, and the average is withheld rather than
--       computed over the survivors.
-- ⚠ (b) is the load-bearing half. Averaging 9 of 12 months and labelling it a
-- 12-month average is a silently-short window, which is a wrong number wearing
-- a correct name — strictly worse than an absent one.
--
-- THE FRAME IS `RANGE` OVER AN INTEGER MONTH ORDINAL, not `ROWS`. Both are
-- identical while the interior is dense, and they diverge the moment it is not:
-- a ROWS frame counts twelve ROWS and would happily span fifteen calendar
-- months across a gap, producing exactly the silently-short window (b) forbids
-- — and it would do so with count(*) = 12, so the guard would not fire either.
-- The RANGE frame counts twelve MONTHS, so a gap yields count(*) < 12 and the
-- guard NULLs the row. The density decision above and this frame choice are
-- therefore independent fences over the same hazard, and neither is redundant:
-- density makes the gap not happen, RANGE makes a gap detectable if it ever
-- does. The ordinal is integer month arithmetic (year*12 + month) rather than a
-- date interval offset, so no calendar clamping (Jan 31 minus 11 months) can
-- move a frame edge.
--
-- ----------------------------------------------------------------------------
-- THE BASIS — coverage_through, resolved through the sanctioned helper.
--
-- Every month is restated into the purchasing power of the LATEST CPI-COVERED
-- PERIOD, matching pfin.fn_nav_series_inflation_adjusted (067) and therefore
-- §2.1.2, which PRD §2.3.4 names as the basis this surface matches. There is NO
-- "CPI today": the CPI-U publication lag means the newest available level is
-- always one to two months old, and PRD §2.4.4 requires that the basis be
-- DISCLOSED BY DATE rather than described as current. cpi_coverage_through is
-- that date, and it is identical on every row because coverage is a property of
-- the STORE, not of the requested period.
--
-- ⚠ NO aggregate over pfin.cpi_u_index is written in this file and none may be
-- added. A `max(cpi_period)` here would be a second home for the coverage edge;
-- the carry-forward and gap-classification policy has ONE home by standing
-- requirement (066), and re-deriving it locally is precisely what ADR-049
-- Decision 4 exists to prevent. The coverage edge is obtained by calling 066
-- with a FIXED argument at the CPI-U series epoch — fixed, not derived from
-- p_as_of, because coverage is store-scoped (067's argument, unchanged).
--
-- DIVISION SAFETY. The ratio is computed only when BOTH legs are strictly
-- positive; otherwise the adjusted figure is NULL — never 0. "We cannot deflate
-- this month" and "the real-terms spend was zero" must not render identically,
-- and a zero denominator raises while a negative one would silently flip the
-- sign of a money figure. pfin.cpi_u_index carries the finiteness CHECK
-- (053, cpi_u_index_value_finite) barring NaN and infinities, and 095 added the
-- additive finite-and-strictly-positive CHECK. This guard is NOT a third local
-- positivity re-check of the store: it is the guard over what 066 RETURNS,
-- which on the absent paths is NULL and is not constrained by any CHECK on the
-- table. Sufficiency comes from the store's CHECKs for stored values and from
-- this guard for resolved-but-absent ones; neither alone covers both.
--
-- gap_class is DELIBERATELY NOT PROJECTED, following 067: it is OPERATOR-axis,
-- and forwarding it would put a forbidden user-visible branch one dereference
-- from the consumer. period_was_due and nonpublication_on_record are what a
-- consumer tiers on.
--
-- ⚠ THE INFORMATIONAL MARKER IS SERIES-LEVEL ON THIS SURFACE (PRD §2.4.4:
-- "one series-level mark, not one per point"). The per-row cpi_* columns are
-- the INPUTS to that reduction — the consumer ORs cpi_is_carried AND
-- cpi_period_was_due across the emitted rows and marks the SERIES once. They
-- are not an instruction to mark each bar. Recorded because a per-row column
-- set invites the per-row rendering the PRD rules out.
--
-- ----------------------------------------------------------------------------
-- THE SCOPE — Expense minus tax payments, and where each half comes from.
--
-- The row set is PRD §2.3.4's: the Expenses scope of §2.3.2 MINUS the buckets
-- marked as tax payments (ADR-062). Mechanically:
--   · `cat = 'Expense'` is read off the READER's projection. Trade, Transfer
--     and Equity are excluded by that class filter; Revenue likewise. AcctSetup
--     rows never reach here at all — the reader's rule 1 admits only
--     transaction_type = 'standard', so acct_setup is excluded UPSTREAM (012),
--     not by anything in this file.
--   · `is_tax_payment` is read off pfin.posting_prototype (091). The reader
--     does not project it, so this function joins the SAME prototype the reader
--     already resolved, on the SAME surrogate key, for ONE further attribute.
--     That is an attribute lookup, not a restatement of a reader rule: no
--     predicate of the reader's is re-expressed, and `cat` is deliberately
--     taken from the reader rather than from this join, so the two cannot
--     disagree about the class.
-- ⚠ There is NO skip_flag and no exclusion primitive — the column does not
-- exist and ADR-032 is why. Nothing here filters on one.
--
-- ⚠ KNOWN SCOPE RESIDUAL, not introduced here and not fixed here: is_tax_payment
-- is carried on Expense-class prototypes, and the tax buckets a household
-- actually books against may be Transfer-class, which this surface's `cat`
-- filter already excludes for a different reason. The subtraction this file
-- performs is therefore exact over the Expense class and says nothing about
-- rows outside it. Recorded so a reader does not conclude the marker has been
-- proven to reach every tax row.
--
-- SIGN CONVENTION — OUTFLOW-POSITIVE, negated ONCE, at one place.
-- pfin.account_trans carries expense as NEGATIVE (093's Part B states the same
-- convention for the same reason). PRD §2.3.4 renders "monthly bars" of expense
-- totals, and 093/094 both normalize the Expenses section to outflow-positive
-- before it leaves SQL, so this surface does too — a §2.3.4 bar must not be the
-- sign-flip of the §2.3.2 Expenses total the user reads on the same page.
-- ⚠ The multiplier is applied ONCE, at the series, and NEVER as abs() per row.
-- A refund-heavy month is reachable and must render NEGATIVE — a month whose
-- refunds exceed its spending is a real, informative bar, and abs() would flip
-- it into a spending spike. Reachable states:
--   ordinary month, net spend      -> POSITIVE
--   refund-dominated month         -> NEGATIVE
--   no qualifying expense at all   -> 0 (a measurement; see ZERO ROW vs NO ROW)
-- ⚠ DEFAULT-AND-NOTIFY WINDOW: SELF-255 AC3 states the figure as the raw
-- Σ amount_net, which is outflow-NEGATIVE. The normalization above is a
-- deliberate departure taken under ADR-063 Decision 3 for cross-surface
-- consistency with §2.3.2/§2.3.3 and with the PRD's bar-chart rendering. It is
-- reversible in ONE place — the `sign_convention` CTE below — and reversing it
-- flips both the nominal and the adjusted series and every rolling average,
-- with no other edit.
--
-- ROUNDING. None. Full numeric precision is returned on all three money
-- columns, exactly as 067 does; presentation rounding is the consumer's.
-- ============================================================================

create schema if not exists pfin;

create or replace function pfin.fn_historical_expenditures(p_as_of date)
returns table (
  month_end                            date,
  expense_monthly_nominal              numeric,
  expense_monthly_inflation_adjusted   numeric,
  rolling_12mo_avg_inflation_adjusted  numeric,
  cpi_period                           date,
  cpi_value                            numeric,
  cpi_is_carried                       boolean,
  cpi_carried_from                     date,
  cpi_period_was_due                   boolean,
  cpi_nonpublication_on_record         boolean,
  cpi_coverage_through                 date
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
-- Several RETURNS TABLE output names (month_end / cpi_period / cpi_value)
-- collide with column names produced below and by the functions being called.
-- Every reference is alias-qualified, and this directive makes the resolution
-- explicit rather than incidental: an ambiguous bare name resolves to the
-- COLUMN, never to the output variable. Without it a future unqualified
-- reference would fail at runtime with "column reference is ambiguous" instead
-- of doing the obvious thing. The p_* parameter and the two v_* locals match no
-- column name, so they are unaffected. (067's directive, same reasons.)
#variable_conflict use_column
declare
  -- The CPI store's trailing coverage edge, and the index level at that edge.
  -- Together they are the NUMERATOR of the deflator: every month below is
  -- restated into the purchasing power of this one period. Named v_cpi_basis,
  -- not v_cpi_today — there is no "today" in a lagged series.
  v_coverage  date;
  v_cpi_basis numeric;
begin
  -- ---------------------------------------------------------------------
  -- (1) RESOLVE THE COVERAGE EDGE through the sanctioned helper. No aggregate
  -- over pfin.cpi_u_index is written here and none may be added. The argument
  -- is FIXED at the CPI-U series epoch rather than derived from p_as_of:
  -- coverage is a property of the STORE, not of the requested period, and 066
  -- raises on a NULL period, so a derived argument would turn a NULL p_as_of
  -- into an exception instead of the empty result this function's contract
  -- promises.
  -- ---------------------------------------------------------------------
  select h.coverage_through into v_coverage
  from pfin.fn_cpi_u_index_for_period(date '1913-01-01') h;

  -- ---------------------------------------------------------------------
  -- (2) RESOLVE THE BASIS LEVEL — GUARDED. On an empty store the coverage edge
  -- is NULL and 066 RAISES on a NULL period, so this call must not be reached
  -- in that state. v_cpi_basis then stays NULL and every adjusted figure below
  -- resolves to NULL — the reported outcome, not a swallowed error. The nominal
  -- series is still emitted in full, so an empty CPI store degrades the surface
  -- to nominal-only rather than to nothing.
  -- ---------------------------------------------------------------------
  if v_coverage is not null then
    select h.cpi_value into v_cpi_basis
    from pfin.fn_cpi_u_index_for_period(v_coverage) h;
  end if;

  -- ---------------------------------------------------------------------
  -- (3) EMIT.
  -- ---------------------------------------------------------------------
  return query
  with
  -- The month grid's upper edge: the first-of-month of the LAST COMPLETE month
  -- at or before p_as_of. The (p_as_of + 1) form is what makes a p_as_of that
  -- IS a month-end keep its own month, while any earlier day in the month drops
  -- it. ⚠ The ::timestamp cast is LOAD-BEARING throughout this function: that
  -- type is zone-free, so nothing here is evaluated in the session TimeZone
  -- (066's hazard, and ADR-044's). Do not "simplify" any of them away.
  bounds as (
    select
      (date_trunc('month', (p_as_of + 1)::timestamp) - interval '1 month')::date as ms_last
  ),

  -- The 60-month floor, in first-of-month space. 59 months back from ms_last
  -- inclusive of both endpoints = 60 months.
  span as (
    select
      b.ms_last,
      (b.ms_last::timestamp - interval '59 months')::date as ms_floor
    from bounds b
  ),

  -- THE ONLY READ OF THE LEDGER. One invocation of the shared reader; no
  -- predicate of ours is pushed into it and no predicate of its own is repeated
  -- here. `cat` comes from the reader; the join to pfin.posting_prototype
  -- supplies ONE column the reader does not project.
  -- ⚠ The join is INNER and its key is a SURROGATE ID. `cat` is non-NULL only
  -- when the reader itself resolved a prototype for i.sub_cat_id, so this join
  -- drops nothing the `cat = 'Expense'` filter has not already dropped. If that
  -- ever ceases to hold it drops the ITEM — understating expenditure, which
  -- shows as a visible dip — rather than admitting a row whose tax marker could
  -- not be read. An id key also fails CLOSED under an RLS regression, unlike a
  -- shared-vocabulary string key.
  qualifying as (
    select
      date_trunc('month', i.transaction_date::timestamp)::date as ms,
      i.amount_net
    from pfin.fn_cashflow_items(p_as_of) i
    join pfin.posting_prototype pp on pp.id = i.sub_cat_id
    where i.cat = 'Expense'
      and pp.is_tax_payment = false
  ),

  -- Bucket by the ITEM's own transaction_date, clipped to the window. Items
  -- older than the floor and items in the current INCOMPLETE month are dropped
  -- here — the second is the partial-month exclusion documented in THE WINDOW.
  monthly as (
    select
      q.ms,
      sum(q.amount_net)::numeric as amt_signed
    from qualifying q
    cross join span s
    where q.ms >= s.ms_floor
      and q.ms <= s.ms_last
    group by q.ms
  ),

  -- THE ANCHOR — the no-leading-pad half of the ZERO ROW vs NO ROW decision.
  -- ms_first is the earliest month IN THE WINDOW that actually has a qualifying
  -- expense. It is NULL when the window holds none, and generate_series with a
  -- NULL start emits zero rows, so the empty-series case falls out of the same
  -- expression rather than needing a guard beside it.
  anchor as (
    select
      s.ms_last,
      (select min(m.ms) from monthly m) as ms_first
    from span s
  ),

  -- The DENSE grid. generate_series steps in first-of-month space, where
  -- start + n * '1 month' is always a first-of-month — month-end space would
  -- put the step at the mercy of Postgres' end-of-month clamping.
  grid as (
    select g::date as month_start
    from anchor a
    cross join lateral generate_series(
      a.ms_first::timestamp, a.ms_last::timestamp, interval '1 month'
    ) g
  ),

  -- The section multiplier, as data. ONE place, per SIGN CONVENTION; this CTE
  -- is the single edit that reverses the outflow-positive default-and-notify.
  sign_convention(sign) as (
    values (-1::numeric)
  ),

  -- The LEFT JOIN is the dense-interior half of the decision: a grid month with
  -- no `monthly` row becomes 0, not a dropped row.
  nominal_rows as (
    select
      (g.month_start + interval '1 month' - interval '1 day')::date   as month_end,
      -- The integer month ordinal the RANGE frame orders on. Integer
      -- arithmetic, so no interval offset can be clamped by month length.
      (extract(year from g.month_start)::int * 12
        + extract(month from g.month_start)::int)                     as month_ord,
      (sc.sign * coalesce(m.amt_signed, 0))::numeric                  as nominal
    from grid g
    cross join sign_convention sc
    left join monthly m on m.ms = g.month_start
  ),

  -- The deflator, one lateral call per emitted month. 066 returns exactly one
  -- row for any non-NULL period and month_end is non-NULL on every grid row, so
  -- the lateral can neither drop a month nor duplicate one. 066 normalizes to
  -- the CPI grain and RETURNS the normalized period as cpi_period, so passing a
  -- month-end is answered by that month's CPI period and the caller is told
  -- which period answered.
  adjusted as (
    select
      r.month_end,
      r.month_ord,
      r.nominal,
      -- BOTH legs strictly positive or NULL. Never 0. See DIVISION SAFETY.
      case
        when v_cpi_basis is null or v_cpi_basis <= 0 then null::numeric
        when c.cpi_value  is null or c.cpi_value  <= 0 then null::numeric
        else r.nominal * (v_cpi_basis / c.cpi_value)
      end                                    as adj,
      c.cpi_period,
      c.cpi_value,
      c.is_carried,
      c.carried_from,
      c.period_was_due,
      c.nonpublication_on_record,
      c.coverage_through
    from nominal_rows r
    cross join lateral pfin.fn_cpi_u_index_for_period(r.month_end) c
  )

  -- The rolling overlay. Both guards are required and neither implies the
  -- other: count(*) = 12 proves TWELVE CALENDAR MONTHS are in frame (the RANGE
  -- frame is over month_ord, so this cannot be satisfied by twelve rows
  -- spanning more months); count(a.adj) = 12 proves none of them is NULL, since
  -- count ignores NULLs. Fail one and the average is withheld.
  select
    a.month_end,
    a.nominal,
    a.adj,
    case
      when count(*) over w = 12 and count(a.adj) over w = 12
        then avg(a.adj) over w
      else null::numeric
    end,
    a.cpi_period,
    a.cpi_value,
    a.is_carried,
    a.carried_from,
    a.period_was_due,
    a.nonpublication_on_record,
    a.coverage_through
  from adjusted a
  window w as (order by a.month_ord range between 11 preceding and current row)
  order by a.month_end;
end;
$$;

-- ⚠ REVOKE FIRST, AND NOT AS BOILERPLATE. PostgreSQL grants EXECUTE to PUBLIC
-- by default on a freshly created function, so without the revoke this
-- migration would ship a financial read surface executable by every role — and
-- it would look exactly like a successful no-op. The grant that follows is then
-- the whole of the access rather than an addition on top of an implicit one
-- (054's discipline). anon is denied earlier by schema USAGE, but that is a
-- second fence, not this one.
revoke execute on function pfin.fn_historical_expenditures(date) from public;
grant  execute on function pfin.fn_historical_expenditures(date) to authenticated;

comment on function pfin.fn_historical_expenditures(date) is
  'The PRD §2.3.4 Historical Expenditures series (SELF-255): inflation-normalized '
  'monthly expenditure with a 12-month rolling-average overlay, over a rolling '
  '5-year window. SECURITY INVOKER + STABLE + set search_path = ''''; NO tenant '
  'and NO scope parameter — isolation is INHERITED from the RLS on every relation '
  'read, under the caller''s own session, and a cross-tenant caller gets zero '
  'rows. Full-household by default (ADR-004 Decision B); per-scope filtering is '
  'V2+. A NULL p_as_of returns zero rows: it fails closed. '
  'COMPOSITION, and it is the whole design: this function composes on '
  'pfin.fn_cashflow_items (093) for every ledger row and on '
  'pfin.fn_cpi_u_index_for_period (066) for every CPI-U level, and restates the '
  'rules of NEITHER. STANDING REQUIREMENT: the six reader rules live in 093 and '
  'the CPI carry-forward and gap-classification policy lives in 066; a rule from '
  'either restated in this body re-creates the drift both extractions exist to '
  'prevent. This function contains no date predicate over pfin.account_trans and '
  'no aggregate over pfin.cpi_u_index. '
  'WINDOW: the trailing 60 COMPLETE calendar months ending at the last month_end '
  '<= p_as_of. ⚠ A mid-month p_as_of emits NOTHING for its own month — every '
  'emitted month is complete by construction, so month_end is always a true claim '
  'about the data behind it and no bar is a partial month wearing a full month''s '
  'label. Month-to-date expense is a DIFFERENT question, answered by §2.3.2''s '
  'in_month flag. '
  'ROW SET — dense interior, no leading pad: the series starts at the first month '
  'in the window holding a qualifying expense and runs densely to the end. ⚠ A '
  'month with no qualifying expense INSIDE that span emits a row with '
  'expense_monthly_nominal = 0, because an interior zero is a MEASUREMENT and '
  'omitting it would let a chart draw straight through it. Before the first '
  'qualifying expense NO row is emitted, because a leading zero is the absence of '
  'a book and would render identically to frugality. Fewer than 60 rows means '
  'less history, not missing data; ZERO rows means no qualifying expense in the '
  'window at all. '
  'SCOPE: reader items with cat = ''Expense'' whose resolved posting prototype '
  'has is_tax_payment = false (ADR-062). Trade / Transfer / Equity / Revenue are '
  'excluded by the class filter; acct_setup rows are excluded UPSTREAM by the '
  'reader''s rule 1 and by nothing in this function. Nothing here filters on a '
  'skip or exclusion flag — ADR-032 rules that the data layer carries no such '
  'primitive. ⚠ The tax subtraction is applied ONLY within the Expense class; it '
  'makes no claim about tax rows booked under another class. '
  'SIGN: expense_monthly_nominal is OUTFLOW-POSITIVE — pfin.account_trans carries '
  'expense as negative and the section multiplier is applied ONCE, matching the '
  '§2.3.2 and §2.3.3 Expenses sections so the same month cannot read with '
  'opposite signs on two surfaces of one page. ⚠ NEVER abs(): a refund-dominated '
  'month is reachable and renders NEGATIVE, which is the honest bar. UNROUNDED on '
  'all three money columns; presentation rounding is the consumer''s. '
  'DEFLATOR: expense_monthly_inflation_adjusted = expense_monthly_nominal x '
  '(CPI-U at cpi_coverage_through / CPI-U at cpi_period). cpi_coverage_through is '
  'a property of the CPI STORE, identical on every row, and is the period whose '
  'purchasing power every figure is stated in — the SAME basis as '
  'pfin.fn_nav_series_inflation_adjusted (067) and therefore as §2.1.2, which PRD '
  '§2.3.4 requires this surface to match. There is no "CPI today": the CPI-U '
  'publication lag means the newest level is always one to two months old, which '
  'PRD §2.4.4 requires be disclosed as a DATED basis line naming '
  'cpi_coverage_through rather than described as current. '
  'DIVISION SAFETY: the ratio is computed only when BOTH CPI legs are strictly '
  'positive; otherwise expense_monthly_inflation_adjusted is NULL — NEVER 0, '
  'because "cannot be deflated" and "real-terms spend was zero" must not render '
  'identically. This guard covers what 066 RETURNS, including its absent paths, '
  'which no CHECK on pfin.cpi_u_index constrains; the stored values are separately '
  'fenced by that table''s own finiteness and positivity CHECKs. Neither covers '
  'both, and the guard is not a re-check of the store. '
  'ROLLING OVERLAY: rolling_12mo_avg_inflation_adjusted is the mean of the 12 '
  'inflation-adjusted values ending at this row''s month_end, and is NULL in '
  'exactly two cases — fewer than 12 constituent MONTHS are in frame (the first '
  '11 rows), or ANY constituent is NULL. ⚠ It is never averaged over the '
  'survivors: a mean of 9 months labelled a 12-month average is a wrong number '
  'wearing a correct name. The window frame is RANGE over an integer month '
  'ordinal, not ROWS, so twelve rows spanning fifteen calendar months cannot '
  'satisfy the count. '
  'CPI PROVENANCE: the seven cpi_* columns are 066''s row for each month, '
  'prefixed, MINUS gap_class — which is OPERATOR-axis and is deliberately not '
  'projected (067''s ruling), because forwarding it would put a forbidden '
  'user-visible branch one dereference from the consumer. They exist so a NULL '
  'adjusted figure is legible and so a consumer can execute the PRD §2.4.4 '
  'rendering rule; narrowing this return would force a consumer to abandon that '
  'rule or to re-derive CPI policy locally. ⚠ On THIS surface the informational '
  'marker is SERIES-LEVEL — "one series-level mark, not one per point" (PRD '
  '§2.4.4). The per-row columns are the INPUTS to that reduction (OR '
  'cpi_is_carried AND cpi_period_was_due across the emitted rows), NOT an '
  'instruction to mark each bar. '
  'Reads only: no write path, no new FK-shaped column, no SECURITY DEFINER entry, '
  'no service_role grant. EXECUTE revoked from PUBLIC and granted to authenticated '
  'only.';

-- ============================================================================
-- Migration: pfin.fn_compute_tax_liability — the §2.5 keystone read helper.
-- Phase 6 Build Loop (SELF-262). Realizes PRD §2.5.1 decomposition, §2.5.2
-- routing, §2.5.3 quarterly computation and §2.5.4's two NAV-component
-- scalars behind ONE SECURITY INVOKER function returning ONE JSONB payload.
-- Sec joint-review MANDATORY (financial calculation + money figures +
-- multi-tenant read composition).
--
-- WHAT THIS DOES: creates exactly one function. NO table, NO column, NO index,
--   NO policy, NO grant on any table, NO trigger, NO enum, NO DEFAULT. It reads
--   and it composes; it writes nothing.
--
-- Numbering: 104, taken against the live listing at authoring time and NOT
--   reserved ahead. Order-dependent — every one of its five callees must exist
--   first: 093 (fn_cashflow_items), 049 as re-issued at 056 and pinned at 079
--   (fn_account_unrealized_gl), 084 (posting_prototype), 003 (account),
--   101 (tax_bracket_schedule / tax_bracket_row + tax_schedule_type_enum),
--   102 (fn_ytd_paid_per_jurisdiction + tax_jurisdiction_enum), 103 (the seeded
--   schedules). It is INDEPENDENT of 100 in the DDL sense — 100 changes values,
--   not shape — but 100's corrected tax_relevant / tax_character values are what
--   make this function's output right, which is a different kind of dependency
--   and is stated so a reader does not read "no DDL dependency" as "no
--   dependency."
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT
--   SECURITY DEFINER, and the SECURITY DEFINER allowlist is UNCHANGED — read it
--   live at ADR-011 Decision 9; this file states no count.
--
--   Every table this function touches is owner-scoped by RLS, and every figure
--   it emits is a figure about the CALLER. INVOKER is not merely sufficient, it
--   is the only correct posture: a DEFINER form would compute one user's tax
--   position with another user's row visibility, which is the whole of the
--   hazard. A cross-tenant caller sees no rows, no ledgers and no schedules and
--   therefore receives the empty / unavailable shape — it FAILS CLOSED, and it
--   fails closed into a shape that says so rather than into zeros.
--
--   Carries `set search_path = ''`; EXECUTE revoked from PUBLIC and granted to
--   `authenticated`. ⚠ For an INVOKER function the EXECUTE grant is the WEAKEST
--   of the fences — RLS on every underlying table still applies to the caller
--   regardless of it. It is stated because every shipped reader carries the pair
--   and a missing one is a silent divergence, not because it is what makes this
--   safe.
--
-- ----------------------------------------------------------------------------
-- VOLATILITY — `stable`, DECLARED IN THE BODY, PER SIGNATURE.
--   `create or replace` RESETS volatility to the language default, so the
--   declaration cannot live in a later `alter function` (that is exactly the
--   silent-un-pin 102's header records for 051).
--
--   ⚠ PREMISE CORRECTION, carried at E26 and stated here because three drafted
--   ACs repeat it: SELF-262 AC 11, SELF-268 AC 4c and sitting-log R3 rider 7 all
--   say "051 and 049 carry none and default VOLATILE." That is FALSIFIED on the
--   tree — 079_volatility_pin_stable.sql pinned fn_account_unrealized_gl(date),
--   fn_compute_nav(date), fn_compute_nav(date, boolean) and fn_nav_composition(date)
--   to `stable`, and 102 re-declares `stable` explicitly when it re-creates
--   fn_nav_composition. The INSTRUCTION those ACs give is right and is followed
--   here; only the stated reason is stale, and it is corrected by amendment
--   rather than by dropping the instruction.
--
--   `stable` is HONEST here rather than asserted: a `stable` caller of a
--   `volatile` callee is an unbacked promise, and all five callees were measured
--   `provolatile = 's'` in the catalog on a clean 001..103 apply —
--   fn_cashflow_items(date), fn_account_unrealized_gl(date),
--   fn_ytd_paid_per_jurisdiction(date, pfin.tax_jurisdiction_enum),
--   fn_tax_authority_ledgers() and fn_server_today(). A battery leg pins all six.
--
-- ----------------------------------------------------------------------------
-- LEDGERS — nothing moves.
--   §10: ADR-011 Decision 4 was read VERBATIM and LIVE before drafting. Three
--     axes clean: no catalogued instance is added, removed, reordered or
--     renumbered; no layer attribution moves; no surface becomes "four-layer".
--     Path B (drop-enumeration-let-link-carry) — this file carries NO count and
--     NO enumeration of the catalogued set. Read Decision 4 live.
--     ⚠ The §10 CATALOGUED set and the CI-FENCED set are DIFFERENT SETS and are
--     not reconciled here or anywhere.
--   ADR-011 Decision 3: FLAT. This migration creates no table, no column and no
--     FK-shaped reference of any kind, so it neither extends the family nor
--     re-targets a member. (101 extends it and says so in its own header.)
--   ADR-011 Decision 9: DEFINER allowlist UNCHANGED.
--
-- ----------------------------------------------------------------------------
-- CONTRACT — pfin.fn_compute_tax_liability(p_data_as_of date default current_date)
--   returns jsonb. ONE payload, read by SELF-264 (§2.5.1), SELF-266 (§2.5.3) and
--   SELF-268 (§2.5.4 → 051). ADR-067 Decision 5 is its canonical home; this
--   header does not restate the key list, it states the edges.
--
--   SEAM C — ONE as-of, threaded. p_data_as_of is passed unchanged to every
--     callee that takes one. Nothing inside derives its own date; there is no
--     current_date and no fn_server_today() call in the body. fn_server_today()
--     is the CALLER's clock — the same value is threaded to fn_compute_nav on
--     the same request (R3 rider 4), or the §2.1.5 foot reconciles to nothing.
--     The payload echoes it back as `as_of` so a consumer can prove the
--     threading rather than assume it.
--
--   TAX YEAR — extract(year from p_data_as_of), DB-derived (ADR-044; SELF-264
--     AC 2). Calendar year, Federal default, CA FTB aligned (PRD §2.5.1 θ-1).
--
--   ENVELOPES — every genuinely-unknowable figure is a {status, ...} OBJECT and
--     never a nullable scalar: both nav_components scalars, both jurisdictions'
--     ytd_paid and funds_due, and capital_gains. This is Sec B3's enforcement
--     BY CONSTRUCTION, not decoration: a consumer writing `… ?? 0` receives an
--     object, so the forbidden collapse of "not set up" into "nothing paid"
--     fails at the first arithmetic instead of rendering a plausible number.
--     Two states that must mean one thing belong in the TYPE, not in consumer
--     discipline. Losing side, named: three consumers unwrap `.amount`
--     everywhere and the JSON is wordier than a nullable scalar.
--     `reason` is a STABLE MACHINE CODE, never prose — copy is the surfaces'.
--     The codes: no_sale_recording_capability · no_schedule_any_year ·
--     no_ledger_designated · ytd_paid_unavailable.
--
--   REVENUE-CLASS SCOPE (PM R-1 / Sec 263 F-4) — the Ordinary Income reader
--     filters `pp.tax_relevant AND pp.cat = 'Revenue'`. BOTH conjuncts are
--     load-bearing. Trade / STC and Trade / BTC also carry tax_relevant = true
--     with tax_character NULL by design — they are disposition events whose
--     character comes from the holding period — so a reader filtering on the
--     FLAG ALONE sums SALE PROCEEDS into Ordinary Income. 100's comment on
--     column states this on all four tables; the fence is here.
--
--   M-5, THE READER HALF — for rows the SELF-263 inventory reached (seeded up to
--     100), `false` on tax_relevant IS a determination; for any row inserted
--     afterwards, `false` is the fail-open DEFAULT. This reader INFERS NOTHING
--     FROM `false`: it selects on `true`, and it never renders or reports an
--     exclusion as an examined determination. R10 constrains the column; it does
--     not constrain the reader, and this is the reader's half.
--
--   ADR-062 Decision 2 — `is_tax_payment` is NOT a source anywhere in this
--     function. It is Expense-scoped and the seeded tax buckets are
--     Transfer-class, so it cannot reach them. YTD Paid comes from 102's
--     fn_ytd_paid_per_jurisdiction and nowhere else.
--
--   THE POSTING_PROTOTYPE JOIN IS ON THE SURROGATE ID (pp.id = i.sub_cat_id,
--     the key 093 itself uses), never on (cat, sub_cat) text. A surrogate-id
--     join fails CLOSED under an RLS regression; a shared-vocabulary string join
--     fails OPEN and would need an explicit users_id conjunct to be safe.
--
--   NOT READ, DELIBERATELY — nav_daily, fn_compute_nav, fn_nav_composition,
--     fn_tax_authority_ledgers (reached only THROUGH 102), transaction_annotation
--     (does not exist). SELF-262 AC 1 strikes the first two by name: §2.5.4's
--     Unrealized reads current market value and cost basis through 049, not the
--     checkpointed series. 051 calls THIS function; the reverse is never true. A
--     nav_daily read here would be an AC 1 change routed back to Sec, and would
--     move Sec 10.5e's SELECT-policy obligation off the 051 read-time path where
--     R3 placed it.
--
--   (π) TAX-ADVANTAGED EXCLUSION — Seam F Option B: the predicate
--     `pfin.account.tax_treatment = 'taxable'` is written INLINE in the
--     Unrealized leg as a join condition over 049's rows. Query layer, one
--     consumer, one copy. tax_treatment is NOT NULL with a three-value CHECK
--     (003), so unlike the nullable tax_jurisdiction there is no unmarked state
--     and no silent-omission hazard — stated because the two attributes look
--     alike and are not.
--     EXTRACT-ON-SECOND-CONSUMER (AC 6): the moment a second surface wants the
--     taxable-only aggregate, this predicate is EXTRACTED into a shared helper,
--     not copied — the fn_tax_authority_ledgers() shape. ⚠ It is a DIFFERENT
--     predicate from fn_tax_authority_ledgers()'s and must NOT be folded into
--     it: designated-ledger exclusion and tax-advantaged-account exclusion are
--     different concepts that happen to both be exclusions.
--
--   LOCK 15 / ADR-011 Decision 19 — the dual-column as-of filter is applied
--     ONCE, inside 093's fn_cashflow_items, in the half-open form its rule 6
--     states (`transaction_date <= $1 AND created_at < ($1 + 1)`). This function
--     adds NO second as-of predicate of its own on the cash-flow path; adding
--     one would double-filter.
--
-- ----------------------------------------------------------------------------
-- NAMED RESIDUAL — recorded so a reader does not conclude the case is handled.
--   (Seam I; ruled at sitting-log R6 (A); 093's shape. It ships in this header
--   AND on the issue AC, because a header alone is not read at the moment it
--   matters.)
--
--   While `wash_sale` basis_adjust and substantive `corp_action` remain
--   Suspense-parked at 035 / 037, cost_basis is UNDERSTATED → 049's
--   unrealized_gl is OVERSTATED → the §2.5.4 Unrealized Tax Liability this
--   function emits is OVERSTATED; and on the §2.5.1 side the disallowed loss is
--   unrecognized.
--
--   ⚠ Under R1 the §2.5.1 half is CURRENTLY VACUOUS ON THE TREE — no sale writer
--   and no basis_adjust writer exist, so the Suspense parking's domain is empty
--   today. The residual is recorded precisely so it does not become INVISIBLE
--   when SELF-302 / SELF-303 land. The rejected third state — this function
--   shipping with no residual at all — is named at R6 so it is seen to have been
--   weighed.
--
-- ----------------------------------------------------------------------------
-- DORMANT CLAUSE — the unmatched sell's ST/LT disposition (sitting-log R11).
--   Written here as PROSE and not as SQL, and that is deliberate: under R1 there
--   is no sale writer and zero lot_match writers, so `capital_gains` carries
--   {status, reason} and NO rows (E26 ruling 4). Live SQL for a row set that
--   cannot exist would be dead code contradicting that ruling; the citing
--   milestone needs the RULE, which is what this block is.
--
--   THE DISPOSITION: an unmatched sell routes to ST / ORDINARY, fail-closed on
--   tax (it overstates rather than understates), footnoted "holding period
--   unresolved — treated as short-term".
--
--   TWO MECHANICS TRAVEL WITH IT, so the citing milestone gets the rule together
--   with what makes it correct (Sec M-1 second half + Sec §4 SELF-264 item 1):
--     (i)  APPORTIONMENT IS PER lot_match ROW, NOT PER TRANSACTION. One sell can
--          match buys on both sides of the one-year line, so a per-transaction
--          split is wrong even when every row resolves.
--     (ii) THE HOLDING-PERIOD LEFT JOIN'S NULL IS TESTED FOR NULL *BEFORE* ANY
--          MEMBERSHIP TEST — the shipped 099 pattern. A NULL entering a
--          membership predicate is neither in nor out, and the row disappears
--          silently.
--   ⚠ lot_match carries no users_id — tenancy inherits through two account_trans
--   FKs. Any future §2.5.1 reader HONORS that rather than assumes it.
--   ⚠ Holding period is MORE THAN ONE YEAR → LT (the drafted ">365 days" was
--   corrected at the sitting's default-and-notify item 7); §1256 60/40 rides the
--   user-classified Volatility-60/40 Sub-Cat. Both are recorded for the same
--   milestone and are likewise unbuilt here.
--   ⚠ WASH SALE: nothing is built (R2 (A)). No V1 flag, no adjustment.
--
-- ----------------------------------------------------------------------------
-- THE SCHEDULE FALLBACK — E22, and the basis is RENDERED, never silent.
--   A schedule_type resolves to the CURRENT-YEAR schedule when one is present,
--   ELSE to the LATEST PRIOR-YEAR schedule of that same schedule_type. The
--   resolved year travels in the payload as `basis_year`, per jurisdiction and
--   per schedule, so every consumer can render it ("California on the 2025
--   schedule — FTB has not published 2026"). THE PRINCIPLE IS PRD §2.4.4's
--   NON-SILENT-STALENESS RULE per ADR-013 — ADR-049 Decision 5 routes
--   carried-forward values to it and explicitly records the mis-citation
--   hazard, so it is named by its home here rather than by the ADR that
--   consumes it.
--   Never $0, never silent. FTB had not published its 2026 schedule on
--   2026-09-04, which is why 103 seeds california_ordinary at tax_year 2025.
--
--   ⚠ AN EMPTY SCHEDULE IS TREATED AS ABSENT FOR SELECTION, AND THE PAYLOAD SAYS
--   SO. A schedule row carrying ZERO tax_bracket_row children would otherwise
--   consume the current-year key and SUPPRESS THE FALLBACK SILENTLY, computing
--   $0 tax off a schedule that has no brackets — the exact failure 103's header
--   names as its rejected option (b). Selection therefore requires at least one
--   bracket row, and the payload carries `current_year_schedule_empty` per
--   schedule type so the suppression is visible rather than inferred from a
--   basis_year that moved.
--
--   `no_schedule_any_year` means: NO schedule of that type WITH BRACKET ROWS
--   exists for the tax year or any prior year. A jurisdiction in that state is
--   `unavailable` — never zeros (Sec M-11).
--
-- ----------------------------------------------------------------------------
-- INSTALLMENTS AND FLOORS — E25.
--   Taxable income FLOORS AT ZERO per jurisdiction, applied BEFORE the bracket
--   walk (Sec M-9). A standard deduction exceeding income yields zero tax, never
--   a negative one.
--   The annual liability is computed at the schedules' full numeric precision.
--   Each installment is rounded to CENTS; Q1..Q3 are equal; Q4 carries the
--   rounding residual, so the four sum EXACTLY to round(annual, 2) (Sec M-8).
--   Losing side: an equal-cents split with the residual on Q1 — Q1 is the
--   installment already due before most of the year's income exists.
--   ÷4 is V1's SOLE installment-sizing approach (μ-2). No safe-harbor floor is
--   computed; tax_balance_prior_year is emitted as INFORMATIONAL REFERENCE ONLY
--   and drives nothing.
--
--   FOUR DUE DATES, THE SAME FOR BOTH JURISDICTIONS: Apr 15 / Jun 15 / Sep 15 of
--   the tax year and Jan 15 of the following year (E26 ruling 3). PRD §2.5.3 and
--   SELF-266 AC 2 both say CA "aligns on Q1/Q2/Q4 and differs on Q3" without
--   naming the difference; a due date invented here would be a date rule with no
--   source, and PM books the PRD sentence for correction.
--
--   ESTIMATED FUNDS DUE, PRD §2.5.3 verbatim: (installment × quarters_elapsed)
--   − YTD Paid. `quarters_elapsed` is read here as THE NUMBER OF DUE DATES ON OR
--   BEFORE p_data_as_of — the PRD does not define it more precisely, and the
--   reading is stated rather than left to be inferred. Because Q4's due date
--   falls in the FOLLOWING calendar year, quarters_elapsed is at most 3 inside
--   the tax year itself. Overpayment surfaces as a NEGATIVE funds_due on the
--   same line (ν-1); it is not clamped.
--
-- ----------------------------------------------------------------------------
-- THE R8 RENDER-WINDOW BOUNDARY IS COMPUTED HERE AND NOWHERE ELSE.
--   Between Jan 1 and the Federal Q4 due date (Jan 15, INCLUSIVE) the §2.5.3
--   tables also show the PRIOR tax year's Q4 row. SELF-266 AC 2a and SELF-267
--   AC 4(c) CITE this one boundary (ADR-063 — which numbers its protocols as
--   ITEMS inside one Decision block, not as Decisions). Two copies of a date
--   rule is how they diverge.
--   ⚠ IT KEYS ON THE DATE ALONE and carries NO paid-ness field (E26 ruling 2).
--   PRD §2.5.3 says the row shows "until it is paid or the date passes", but
--   under Seam B Option A YTD Paid is the designated ledger's balance SINCE
--   INCEPTION (E19 B1) — it cannot separate prior-year payments from
--   current-year ones, so "is it paid?" has no answer in V1. No consumer may
--   invent one, which is why no field offers it. PM reconciles the PRD sentence.
--   ⚠ Sec M-4's UTC-pin year boundary (a Pacific user flips year ~7h early) is
--   BROADER than §2.5, stays UNOWNED per R8, and is NOT discharged here.
--
-- ----------------------------------------------------------------------------
-- THE ZERO CLAMP ON UNREALIZED — R9 (A), and WHY, so it is not "tidied".
--   §2.5.4 defines Unrealized as "the estimated tax that would be owed"; a tax
--   that would be REFUNDED is not that. An unclamped negative would make 051
--   ADD to NAV — inflating the headline by an unrealized, capital-loss-capped,
--   possibly-never-realized benefit. The clamp is stated in the catalog comment
--   with this rationale attached SO A LATER READER DOES NOT RESTORE SYMMETRY BY
--   REMOVING IT (Sec M-2's paired requirement). A clamp with no recorded
--   rationale reads as an asymmetry to tidy up, and the tidying is silent.
--   ⚠ It is DELIBERATELY ASYMMETRIC with 102's fn_ytd_paid_per_jurisdiction,
--   which is NOT clamped (E11 item 4). The two must not be reconciled.
--
-- ----------------------------------------------------------------------------
-- WHAT 051 DOES WITH THIS (SELF-268's seam, stated so it is not re-derived).
--   051's fn_nav_composition still carries FOUR 0::numeric literals — two in
--   `buildups` and two inside the `nav` arithmetic. SELF-268's whole DB-side
--   change is replacing those four with this function's two nav_components
--   scalars, threaded with 051's OWN p_as_of. ONE composed value, ONE reader
--   (R3 rider 0); no second composition path, and the §2.1.1 headline moves its
--   read to 051 rather than composing its own.
--   ⚠ Under the envelope a scalar can be `unavailable`, and 051's `nav`
--   expression cannot subtract a JSON null without turning the whole NAV to
--   NULL. RULED at E26 (1): 051 subtracts 0 and §2.1.5 renders the row
--   UNAVAILABLE-WITH-REASON. That is the BOOTSTRAP default, not an edge case —
--   no ledger is designated at signup — and NAV then reads HIGH until the user
--   designates one, the same direction as R3 rider 0b, so the rendered reason
--   must be VISIBLE, not merely present. This is a new SELF-268 AC and is not
--   discharged here.
-- ============================================================================

create or replace function pfin.fn_compute_tax_liability(p_data_as_of date default current_date)
returns jsonb
language sql
security invoker
stable
set search_path = ''
as $$
with
  params as (
    select
      p_data_as_of                                as d,
      extract(year from p_data_as_of)::smallint   as tax_year
  ),

  -- --------------------------------------------------------------------------
  -- §2.5.1 — ONE scan of the cash-flow reader, YTD-scoped. Both the summed rows
  -- and the unclassified count come from THIS CTE (SELF-264 AC 3b: the count
  -- must come from the same query that sums, or the consumer needs a second
  -- query and forfeits the property the extraction exists to deliver).
  -- LEFT JOIN to posting_prototype, for the reason 093's own join is left: an
  -- inner join drops every UNCLASSIFIED item and silently zeroes the count.
  -- --------------------------------------------------------------------------
  items as (
    select
      i.sub_cat_id,
      pp.cat            as pp_cat,
      pp.sub_cat        as pp_sub_cat,
      pp.tax_relevant   as pp_tax_relevant,
      pp.tax_character  as pp_tax_character,
      i.amount_net
    from pfin.fn_cashflow_items(p_data_as_of) i
    left join pfin.posting_prototype pp on pp.id = i.sub_cat_id
    where i.in_ytd
  ),

  -- Revenue-class scope: BOTH conjuncts. See the header — the flag alone admits
  -- Trade / STC and Trade / BTC, which are sale PROCEEDS, not income.
  inc as (
    select
      it.sub_cat_id,
      it.pp_cat                     as cat,
      it.pp_sub_cat                 as sub_cat,
      it.pp_tax_character           as tax_character,
      sum(it.amount_net)::numeric(20,4) as amount
    from items it
    where it.pp_tax_relevant
      and it.pp_cat = 'Revenue'
    group by it.sub_cat_id, it.pp_cat, it.pp_sub_cat, it.pp_tax_character
  ),

  unclassified as (
    select count(*)::bigint as count_ytd
    from items it
    where it.sub_cat_id is null
  ),

  -- §2.5.2 routing, PRD-verbatim. tax_exempt_interest is excluded from BOTH
  -- jurisdictions. qualified_dividend routes to the Federal LT CG schedule and
  -- to the CA ordinary schedule (CA collapses to one schedule per (κ)).
  -- A NULL tax_character on a tax-relevant Revenue row is the PRD's "default"
  -- row and routes to ordinary — `is distinct from` is required so NULL is not
  -- silently dropped by a plain <>.
  -- ST CG / LT CG columns contribute NOTHING: they are structurally empty under
  -- R1 (no sale writer), and their absence is reported as a STATUS, not a zero.
  inputs as (
    select
      coalesce(sum(inc.amount) filter (
        where inc.tax_character is distinct from 'qualified_dividend'
          and inc.tax_character is distinct from 'tax_exempt_interest'), 0)::numeric as fed_ord_input,
      coalesce(sum(inc.amount) filter (
        where inc.tax_character = 'qualified_dividend'), 0)::numeric                 as fed_ltcg_input,
      coalesce(sum(inc.amount) filter (
        where inc.tax_character is distinct from 'tax_exempt_interest'), 0)::numeric as ca_input
    from inc
  ),

  -- --------------------------------------------------------------------------
  -- §2.5.2 SCHEDULE RESOLUTION — E22 fallback, with the empty-schedule rule.
  -- --------------------------------------------------------------------------
  sched as (
    select
      s.id, s.schedule_type, s.tax_year, s.standard_deduction,
      s.tax_balance_prior_year,
      (select count(*) from pfin.tax_bracket_row r where r.schedule_id = s.id) as row_count
    from pfin.tax_bracket_schedule s
  ),

  -- A current-year schedule that exists but holds ZERO bracket rows. Selected
  -- separately from `pick` precisely because `pick` cannot see it — that is the
  -- whole point: it must not suppress the fallback, and it must not vanish.
  empty_current as (
    select sc.schedule_type
    from sched sc
    cross join params p
    where sc.tax_year = p.tax_year
      and sc.row_count = 0
  ),

  -- Current year if usable, else the latest usable PRIOR year. Never a future
  -- year. "Usable" = at least one bracket row.
  pick as (
    select distinct on (sc.schedule_type)
      sc.id, sc.schedule_type, sc.tax_year as basis_year,
      sc.standard_deduction, sc.tax_balance_prior_year
    from sched sc
    cross join params p
    where sc.row_count > 0
      and sc.tax_year <= p.tax_year
    order by sc.schedule_type, sc.tax_year desc
  ),

  -- The income each picked schedule walks, floored at zero AFTER the standard
  -- deduction and BEFORE the walk (E25 / Sec M-9).
  targets as (
    select
      pk.id as schedule_id, pk.schedule_type, pk.basis_year,
      pk.standard_deduction, pk.tax_balance_prior_year,
      (case pk.schedule_type
         when 'federal_ordinary'    then i.fed_ord_input
         when 'federal_lt_cg'       then i.fed_ltcg_input
         when 'california_ordinary' then i.ca_input
       end)                                                          as gross_input,
      greatest(
        (case pk.schedule_type
           when 'federal_ordinary'    then i.fed_ord_input
           when 'federal_lt_cg'       then i.fed_ltcg_input
           when 'california_ordinary' then i.ca_input
         end) - pk.standard_deduction, 0)                            as taxable
    from pick pk
    cross join inputs i
  ),

  -- The progressive walk. `next_floor` is the next bracket's lower bound;
  -- NULL on the top bracket, where the slice runs to the taxable income itself.
  -- greatest(..., 0) makes every bracket above the income contribute exactly 0
  -- rather than a negative slice.
  brackets as (
    select
      r.schedule_id, r.bracket_floor, r.bracket_rate,
      lead(r.bracket_floor) over (partition by r.schedule_id order by r.bracket_floor) as next_floor
    from pfin.tax_bracket_row r
    where r.schedule_id in (select t.schedule_id from targets t)
  ),

  walked as (
    select
      t.schedule_type, t.schedule_id, t.basis_year, t.standard_deduction,
      t.tax_balance_prior_year, t.gross_input, t.taxable,
      coalesce(sum(
        b.bracket_rate
        * greatest(least(t.taxable, coalesce(b.next_floor, t.taxable)) - b.bracket_floor, 0)
      ), 0)                                                                    as tax,
      -- The rate of the highest bracket whose floor the taxable income reaches.
      -- Taken by ORDERING rather than by max(rate), so it stays correct without
      -- depending on 101's monotonicity fence being the thing that makes it true.
      (array_agg(b.bracket_rate order by b.bracket_floor desc)
         filter (where b.bracket_floor <= t.taxable))[1]                       as applied_rate,
      -- The TOP-bracket rate, independent of income — §2.5.4's ο-a inputs.
      (array_agg(b.bracket_rate order by b.bracket_floor desc))[1]             as top_rate,
      (select true from empty_current ec where ec.schedule_type = t.schedule_type) as current_year_empty
    from targets t
    join brackets b on b.schedule_id = t.schedule_id
    group by t.schedule_type, t.schedule_id, t.basis_year, t.standard_deduction,
             t.tax_balance_prior_year, t.gross_input, t.taxable
  ),

  -- --------------------------------------------------------------------------
  -- PER-JURISDICTION ASSEMBLY. Two jurisdictions, one code path — federal
  -- carries a second (LT CG) schedule and california does not, and the LEFT JOIN
  -- on a NULL ltcg_type is what expresses that without a second branch.
  -- --------------------------------------------------------------------------
  jur_def as (
    select *
    from (values
      ('federal',    'irs'::pfin.tax_jurisdiction_enum,
       'federal_ordinary'::pfin.tax_schedule_type_enum,
       'federal_lt_cg'::pfin.tax_schedule_type_enum),
      ('california', 'ftb'::pfin.tax_jurisdiction_enum,
       'california_ordinary'::pfin.tax_schedule_type_enum,
       null::pfin.tax_schedule_type_enum)
    ) as v(jurisdiction, authority, ord_type, ltcg_type)
  ),

  jur as (
    select
      j.jurisdiction,
      j.authority,
      j.ord_type,
      j.ltcg_type,
      wo.schedule_id            as ord_schedule_id,
      wo.basis_year             as ord_basis_year,
      wo.gross_input            as ord_input,
      wo.taxable                as ord_taxable,
      wo.tax                    as ord_tax,
      wo.applied_rate           as ord_applied_rate,
      wo.top_rate               as ord_top_rate,
      wo.standard_deduction     as standard_deduction,
      wo.tax_balance_prior_year as tax_balance_prior_year,
      coalesce(wo.current_year_empty, false) as ord_current_year_empty,
      wl.basis_year             as ltcg_basis_year,
      wl.gross_input            as ltcg_input,
      wl.taxable                as ltcg_taxable,
      wl.tax                    as ltcg_tax,
      wl.applied_rate           as ltcg_applied_rate,
      wl.top_rate               as ltcg_top_rate,
      coalesce(wl.current_year_empty, false) as ltcg_current_year_empty,
      -- COMPUTED requires EVERY schedule the jurisdiction needs. Fail-closed:
      -- a federal half with no LT CG schedule does not silently report the
      -- ordinary half as the whole liability.
      (wo.schedule_id is not null
        and (j.ltcg_type is null or wl.schedule_id is not null))     as computed,
      pfin.fn_ytd_paid_per_jurisdiction(p_data_as_of, j.authority)   as ytd_paid,
      -- Whether a current-year schedule exists at all but was skipped as empty
      (exists (select 1 from empty_current ec where ec.schedule_type = j.ord_type)
        and wo.schedule_id is null)                                  as ord_empty_no_fallback
    from jur_def j
    left join walked wo on wo.schedule_type = j.ord_type
    left join walked wl on wl.schedule_type = j.ltcg_type
  ),

  -- Annual liability, the cent-rounded installment split, and the elapsed-quarter
  -- count that drives Estimated Funds Due.
  jur_calc as (
    select
      jr.*,
      p.tax_year,
      (jr.ord_tax + coalesce(jr.ltcg_tax, 0))                         as annual_raw,
      round(jr.ord_tax + coalesce(jr.ltcg_tax, 0), 2)                 as annual,
      round(round(jr.ord_tax + coalesce(jr.ltcg_tax, 0), 2) / 4, 2)   as q123,
      least(jr.ord_basis_year, coalesce(jr.ltcg_basis_year, jr.ord_basis_year)) as basis_year,
      make_date(p.tax_year::int,     4, 15)                           as due_q1,
      make_date(p.tax_year::int,     6, 15)                           as due_q2,
      make_date(p.tax_year::int,     9, 15)                           as due_q3,
      make_date(p.tax_year::int + 1, 1, 15)                           as due_q4,
      (  (make_date(p.tax_year::int,     4, 15) <= p.d)::int
       + (make_date(p.tax_year::int,     6, 15) <= p.d)::int
       + (make_date(p.tax_year::int,     9, 15) <= p.d)::int
       + (make_date(p.tax_year::int + 1, 1, 15) <= p.d)::int )        as quarters_elapsed
    from jur jr
    cross join params p
  ),

  jur_final as (
    select
      jc.*,
      (jc.annual - 3 * jc.q123)                                       as q4_amount,
      (case when jc.quarters_elapsed >= 4 then jc.annual
            else jc.quarters_elapsed * jc.q123 end)                   as obligation_to_date
    from jur_calc jc
  ),

  jur_json as (
    select
      jf.jurisdiction,
      jf.ytd_paid,
      jf.computed,
      (case when jf.computed and jf.ytd_paid is not null
            then jf.obligation_to_date - jf.ytd_paid end)             as funds_due_amount,
      jsonb_strip_nulls(jsonb_build_object(
        'status', case when jf.computed then 'computed' else 'unavailable' end,
        'reason', case when jf.computed then null else 'no_schedule_any_year' end
      ))
      ||
      jsonb_build_object(
        'basis_year',   jf.basis_year,
        'schedules',
          jsonb_build_object(
            jf.ord_type::text, jsonb_build_object(
              'present',                    (jf.ord_schedule_id is not null),
              'basis_year',                 jf.ord_basis_year,
              'current_year_schedule_empty', jf.ord_current_year_empty or jf.ord_empty_no_fallback)
          )
          || (case when jf.ltcg_type is null then '{}'::jsonb
                   else jsonb_build_object(
                     jf.ltcg_type::text, jsonb_build_object(
                       'present',                     (jf.ltcg_basis_year is not null),
                       'basis_year',                  jf.ltcg_basis_year,
                       'current_year_schedule_empty', jf.ltcg_current_year_empty))
              end),
        'inputs', jsonb_build_object(
          'ordinary_input',     jf.ord_input,
          'lt_cg_input',        jf.ltcg_input,
          'standard_deduction', jf.standard_deduction),
        'taxable_income', jsonb_build_object(
          'ordinary', jf.ord_taxable,
          'lt_cg',    jf.ltcg_taxable),
        'annual_liability',       case when jf.computed then jf.annual_raw end,
        'tax_balance_prior_year', jf.tax_balance_prior_year,
        'installments',
          case when jf.computed then jsonb_build_array(
            jsonb_build_object('quarter', 1, 'due_date', jf.due_q1, 'amount', jf.q123),
            jsonb_build_object('quarter', 2, 'due_date', jf.due_q2, 'amount', jf.q123),
            jsonb_build_object('quarter', 3, 'due_date', jf.due_q3, 'amount', jf.q123),
            jsonb_build_object('quarter', 4, 'due_date', jf.due_q4, 'amount', jf.q4_amount)
          ) end,
        'quarters_elapsed',  jf.quarters_elapsed,
        'ytd_paid',
          case when jf.ytd_paid is null
               then jsonb_build_object('status', 'unavailable', 'reason', 'no_ledger_designated')
               else jsonb_build_object('status', 'designated',  'amount', jf.ytd_paid) end,
        'funds_due',
          case when not jf.computed
                 then jsonb_build_object('status', 'unavailable', 'reason', 'no_schedule_any_year')
               when jf.ytd_paid is null
                 then jsonb_build_object('status', 'unavailable', 'reason', 'ytd_paid_unavailable')
               else jsonb_build_object('status', 'computed',
                                       'amount', jf.obligation_to_date - jf.ytd_paid) end
      )
      -- applied_marginal_rate is OMITTED ENTIRELY on an unavailable jurisdiction
      -- (E26 ruling 5) — not null, not 0 — so SELF-266's δ-2 caption renders
      -- unavailable BY THE ABSENCE rather than by interpreting a zero as a 0%
      -- bracket.
      || (case when jf.computed
               then jsonb_build_object('applied_marginal_rate',
                      jsonb_strip_nulls(jsonb_build_object(
                        'ordinary', jf.ord_applied_rate,
                        'lt_cg',    jf.ltcg_applied_rate)))
               else '{}'::jsonb end)                                  as payload
    from jur_final jf
  ),

  -- --------------------------------------------------------------------------
  -- §2.5.4 UNREALIZED — (π) applied at the query layer, inline, one copy.
  -- 049 already filters is_active and applies its own as-of predicate; this
  -- function adds NO second predicate of its own beyond tax_treatment.
  -- --------------------------------------------------------------------------
  unreal as (
    select coalesce(sum(g.unrealized_gl), 0)::numeric as agg
    from pfin.fn_account_unrealized_gl(p_data_as_of) g
    join pfin.account a on a.account_id = g.account_id
    where a.tax_treatment = 'taxable'
  ),

  rates as (
    select
      (select w.top_rate from walked w where w.schedule_type = 'federal_lt_cg')      as fed_ltcg_top,
      (select w.top_rate from walked w where w.schedule_type = 'california_ordinary') as ca_top
  ),

  nav_components as (
    select
      -- REALIZED = the two Estimated Funds Due gaps summed, one combined value
      -- per (ρ). Unavailable if EITHER jurisdiction is — a half-sum reported as
      -- the whole is the silent-understatement this envelope exists to prevent.
      case when exists (select 1 from jur_json jj where not jj.computed)
             then jsonb_build_object('status', 'unavailable', 'reason', 'no_schedule_any_year')
           when exists (select 1 from jur_json jj where jj.ytd_paid is null)
             then jsonb_build_object('status', 'unavailable', 'reason', 'ytd_paid_unavailable')
           else jsonb_build_object('status', 'computed',
                  'amount', (select sum(jj.funds_due_amount) from jur_json jj)) end as realized,
      -- UNREALIZED = (Federal LT CG top rate + CA ordinary top rate) × aggregate
      -- taxable unrealized G/L, CLAMPED AT ZERO. See the header for why the clamp
      -- is not an asymmetry to tidy up.
      case when r.fed_ltcg_top is null or r.ca_top is null
             then jsonb_build_object('status', 'unavailable', 'reason', 'no_schedule_any_year')
           else jsonb_build_object('status', 'computed',
                  'amount', greatest((r.fed_ltcg_top + r.ca_top) * u.agg, 0)) end   as unrealized
    from rates r cross join unreal u
  )

select jsonb_build_object(
  'as_of',    p.d,
  'tax_year', p.tax_year,

  'decomposition', jsonb_build_object(
    'ordinary_income', jsonb_build_object(
      'rows', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'sub_cat_id',    inc.sub_cat_id,
                 'cat',           inc.cat,
                 'sub_cat',       inc.sub_cat,
                 'tax_character', inc.tax_character,
                 'amount',        inc.amount)
               order by inc.cat, inc.sub_cat)
        from inc), '[]'::jsonb),
      'total', coalesce((select sum(inc.amount) from inc), 0)
    ),
    -- R1 rider 1: the unavailable state keys on the STRUCTURAL fact — no
    -- sale-recording capability exists — and NEVER on a lot_match row count for
    -- the tax year. A count reads as "you had no gains" the day the writer
    -- lands. There is deliberately no `rows` key at all (E26 ruling 4): an empty
    -- array beside a status is a second way to say the same thing and invites a
    -- consumer to render it.
    'capital_gains', jsonb_build_object(
      'status', 'unavailable',
      'reason', 'no_sale_recording_capability'),
    'unclassified', jsonb_build_object(
      'count_ytd', (select uc.count_ytd from unclassified uc))
  ),

  'jurisdictions', (select jsonb_object_agg(jj.jurisdiction, jj.payload) from jur_json jj),

  'nav_components', (select jsonb_build_object(
                              'realized_tax_liab',   nc.realized,
                              'unrealized_tax_liab', nc.unrealized)
                     from nav_components nc),

  -- R8, computed ONCE, here. Date-only; no paid-ness field, by ruling.
  'prior_year_q4_window', jsonb_build_object(
    'open',     (extract(month from p.d) = 1 and extract(day from p.d) <= 15),
    'tax_year', p.tax_year - 1,
    'due_date', make_date(p.tax_year::int, 1, 15))
)
from params p;
$$;

revoke execute on function pfin.fn_compute_tax_liability(date) from public;
grant execute on function pfin.fn_compute_tax_liability(date) to authenticated;

comment on function pfin.fn_compute_tax_liability(date) is
  'SECURITY INVOKER §2.5 estimated-tax read helper — the single composed source for PRD §2.5.1 decomposition, §2.5.2 routing, §2.5.3 quarterly computation and §2.5.4''s two NAV-component scalars (SELF-262; Lock 11 read-composition; ADR-067 Decision 1 ratifies the ONE-unified-helper shape over per-surface readers). Returns ONE jsonb payload with top-level keys as_of, tax_year, decomposition, jurisdictions, nav_components, prior_year_q4_window; ADR-067 Decision 5 is the canonical home of that contract and SELF-264 / SELF-266 / SELF-268 read it there. AS-OF (Lock 15): p_data_as_of is threaded UNCHANGED into every callee — fn_cashflow_items (093), fn_account_unrealized_gl (049 as re-issued at 056), fn_ytd_paid_per_jurisdiction (102) — and NOTHING here derives its own date; the caller''s fn_server_today() value is the clock and must be the SAME value passed to fn_compute_nav on the same request, or the §2.1.5 foot reconciles to nothing. The payload echoes as_of back so a consumer can PROVE the threading rather than assume it. The Lock 15 dual-column filter (transaction_date <= D and created_at < D+1) is applied ONCE inside 093; no second as-of predicate is added here. WHAT THE TAX YEAR IS: extract(year from p_data_as_of) — calendar year, Federal default, CA FTB aligned; and note that YTD Paid, which it composes, is NOT year-scoped — 102''s figure is the designated ledger''s balance SINCE INCEPTION, so from the second tax year onward it carries prior years'' payments forward unless the user rolls the ledger over (CLOSE the old ledger, CLEAR its designation, DESIGNATE a fresh one — 102 states the precondition that closing requires draining first). That overstates YTD Paid and therefore UNDERSTATES Funds Due, the under-reserving direction. ENVELOPES, AND WHY THEY ARE THE TYPE AND NOT A CONVENTION: every genuinely-unknowable figure is a {status, ...} OBJECT — both nav_components scalars, both jurisdictions'' ytd_paid and funds_due, and capital_gains — so a consumer writing `... ?? 0` receives an object and fails at the first arithmetic instead of rendering "not set up" as "nothing paid". reason is a STABLE MACHINE CODE, never prose: no_sale_recording_capability, no_schedule_any_year, no_ledger_designated, ytd_paid_unavailable. CAPITAL GAINS IS UNAVAILABLE ON A STRUCTURAL FACT, NOT A COUNT: no sale writer and no lot_match writer exist, so the CG columns cannot be populated; the status keys on the missing CAPABILITY, never on a row count for the tax year, because a count reads as "you had no gains" the day the writer lands. There is no rows key under capital_gains at all. ORDINARY INCOME SCOPE: rows are posting_prototype rows with tax_relevant = true AND cat = ''Revenue'' — BOTH conjuncts, because Trade/STC and Trade/BTC are also tax_relevant with a NULL character and are sale PROCEEDS; a reader filtering on the flag alone sums proceeds into income. The join is on the SURROGATE ID (pp.id = sub_cat_id), never on (cat, sub_cat) text: a surrogate-id join fails CLOSED under an RLS regression, a shared-vocabulary string join fails OPEN. NOTHING IS INFERRED FROM tax_relevant = false: for rows the SELF-263 inventory reached it is a determination, for rows inserted afterwards it is the fail-open DEFAULT, and this reader selects on true and never reports an exclusion as an examined determination. is_tax_payment is NOT a source here — ADR-062 Decision 2 scopes it to Expense-class prototypes while the seeded tax buckets are Transfer-class, so it cannot reach them. SCHEDULE SELECTION AND ITS BASIS FIELD: a schedule_type resolves to the CURRENT-YEAR schedule when one is present, ELSE to the LATEST PRIOR-YEAR schedule of the same type, and the resolved year travels in the payload as basis_year (per jurisdiction, and per schedule under `schedules`) so every consumer RENDERS the basis — "California on the 2025 schedule" — rather than presenting a stale figure as current. Never $0, never silent. A SCHEDULE HOLDING ZERO BRACKET ROWS IS TREATED AS ABSENT FOR SELECTION and the payload says so via current_year_schedule_empty, because an empty current-year schedule would otherwise consume the current-year key, SUPPRESS THE FALLBACK SILENTLY and compute $0 off a schedule with no brackets. no_schedule_any_year therefore means: no schedule of that type WITH BRACKET ROWS exists for the tax year or any prior year — and such a jurisdiction is UNAVAILABLE, never zeros. A jurisdiction is COMPUTED only when EVERY schedule it needs resolved (federal needs both the ordinary and the LT CG schedule), so a missing half never reports as the whole. COMPUTATION: taxable income FLOORS AT ZERO per jurisdiction, applied after the standard deduction and BEFORE the bracket walk — a deduction exceeding income yields zero tax, never a negative one. The annual liability is computed at full numeric precision; installments are rounded to CENTS with Q1..Q3 equal and Q4 carrying the residual, so the four sum EXACTLY to round(annual, 2). Annual divided by four is V1''s SOLE installment-sizing approach; no safe-harbor floor is computed and tax_balance_prior_year is INFORMATIONAL REFERENCE ONLY, driving nothing. THE FOUR DUE DATES ARE THE SAME FOR BOTH JURISDICTIONS (Apr 15 / Jun 15 / Sep 15 of the tax year, Jan 15 of the next) — the PRD says California differs on Q3 without naming the difference, and a due date invented here would be a date rule with no source. ESTIMATED FUNDS DUE = (installment x quarters_elapsed) - YTD Paid, where quarters_elapsed is READ AS the number of due dates on or before p_data_as_of; the PRD does not define it more precisely and the reading is stated rather than inferred. Because Q4 falls in the following calendar year, quarters_elapsed is at most 3 inside the tax year. Overpayment surfaces as a NEGATIVE funds_due on the same line and is NOT clamped. applied_marginal_rate is OMITTED ENTIRELY on an unavailable jurisdiction — not null, not zero — so an absent caption is not read as a 0% bracket. THE PRIOR-YEAR Q4 RENDER WINDOW IS COMPUTED HERE AND NOWHERE ELSE: open between Jan 1 and Jan 15 INCLUSIVE, keyed on the DATE ALONE with NO paid-ness field, because YTD Paid is a since-inception balance and cannot answer "is it paid?" in V1; SELF-266 and SELF-267 CITE this boundary rather than copying it, since two copies of a date rule is how they diverge. Sec M-4''s UTC year-boundary flag is broader than §2.5 and is NOT discharged here. UNREALIZED TAX LIABILITY = (Federal LT CG top-bracket rate + CA ordinary top-bracket rate) x aggregate unrealized G/L over TAXABLE accounts only ((π), applied inline at the query layer over 049''s rows; tax_treatment is NOT NULL with a three-value CHECK so there is no unmarked state), CLAMPED AT ZERO. ⚠ THE CLAMP''S RATIONALE IS RECORDED HERE SO A LATER READER DOES NOT RESTORE SYMMETRY BY REMOVING IT: §2.5.4 defines the figure as "the estimated tax that would be owed", and a tax that would be REFUNDED is not that; an unclamped negative would make 051 ADD to NAV, inflating the headline by an unrealized, capital-loss-capped, possibly-never-realized benefit. It is DELIBERATELY ASYMMETRIC with 102''s fn_ytd_paid_per_jurisdiction, which is NOT clamped, and the two must not be reconciled. NAMED RESIDUAL — recorded so a reader does not conclude the case is handled: while wash_sale basis_adjust and substantive corp_action remain Suspense-parked at 035/037, cost_basis is UNDERSTATED, so 049''s unrealized_gl is OVERSTATED and the §2.5.4 Unrealized figure emitted here is OVERSTATED; on the §2.5.1 side the disallowed loss is unrecognized. That §2.5.1 half is currently VACUOUS on the tree (no sale writer, no basis_adjust writer), and the residual is recorded precisely so it does not become INVISIBLE when those writers land. NOT READ, DELIBERATELY: nav_daily, fn_compute_nav and fn_nav_composition. 051 calls THIS function, never the reverse, and §2.5.4''s Unrealized reads market value and cost basis through 049 rather than the checkpointed series — a nav_daily read here would be a SELF-262 AC 1 change routed back to Sec, and would move the nav_daily SELECT-policy obligation off the §2.1.5 read-time path at 051 where it belongs. INVOKER: a cross-tenant caller sees no rows, no ledgers and no schedules, so it returns the empty/unavailable shape and FAILS CLOSED. set search_path = ''''; NOT a SECURITY DEFINER allowlist entry (read ADR-011 Decision 9 live; no count is stated here). §10 catalogued ledger UNCHANGED BY THIS OBJECT and NO COUNT IS STATED — a ledger-impact claim is authoring-time provenance and belongs in a migration header, which is dated, not in a catalog comment, which reads as live state; read ADR-011 Decision 4 live. Decision 3 unchanged (no table, no column, no FK-shaped reference). Volatility STABLE, declared in the body per signature because CREATE OR REPLACE resets it; all five callees were measured stable. Sec joint-review MANDATORY (financial calculation + money figures + multi-tenant); two-tenant pgTAP pairing ships same-PR (SELF-269).';

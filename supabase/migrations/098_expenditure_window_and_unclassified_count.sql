-- ============================================================================
-- Migration: the §2.3.4 trailing-5-year WINDOW gets a single home, and the
--   surface gains the AC9 UNCLASSIFIED-ITEM COUNT that annotates its bars.
--   Three objects, all SECURITY INVOKER read-composition (Lock 11):
--     pfin.fn_expenditure_window            NEW  — the window bound, extracted
--     pfin.fn_expenditures_unclassified_count NEW — AC9's N
--     pfin.fn_historical_expenditures       CoR  — 096, now consuming the above
--   Linear SELF-256 (V1.3; PRD §2.3.4). Option B F/CTO-delegated to team-lead
--   and taken 2026-08-31; noted to F/CTO in the consolidated update and
--   reversible at PR review. apply-migration procedure applied.
--   JOINT-REVIEW-MANDATORY (Sec veto surface) — see the routing note below;
--   this migration does NOT inherit SELF-256's render-only mapping.
--
-- ----------------------------------------------------------------------------
-- ⚠ SEC ROUTING — SELF-256 WAS MAPPED RENDER-ONLY / NOT-MANDATORY, AND THAT
--   MAPPING PREDATES THIS MIGRATION. It was correct for a chart-UI item and is
--   not correct for a new DB surface on the §2.3 money path. Two independent
--   grounds, either sufficient:
--     (1) This migration `create or replace`s pfin.fn_historical_expenditures,
--         a FINANCIAL CALCULATION (CPI deflation + a rolling 12-month average)
--         on a multi-tenant read path.
--     (2) N is the COMPLETENESS SIGNAL ON A MONEY SURFACE. The whole S-2 "loud
--         exclusion" ruling is that the bars are trustworthy only because N
--         discloses what they omit. An N that undercounts tells the reader the
--         chart is complete when it is not — a wrong money figure delivered
--         through a different column.
--   The ledger deltas below are a CLAIM FOR SEC TO VERIFY, not the answer to
--   whether review is required.
--
-- ----------------------------------------------------------------------------
-- ⚠ THE PREDICATE AC9 CALLS `in_queue` DOES NOT EXIST AS DDL, AND THIS FILE IS
--   NOT WHERE IT GETS BUILT. Measured 2026-08-31: `in_queue` and
--   `effective_sub_cat_id` have ZERO occurrences under supabase/ and api/;
--   every occurrence in the repo is in docs/records/v13-preflight/. It is a
--   RATIFIED NAME WITH NO IMPLEMENTATION.
--   >> BUT THE SEMANTICS ARE BUILT — only the name is not, and the equivalence
--      is PROVEN FROM THE EMISSION BRANCHES rather than assumed, because the
--      split-child grain is exactly where it would break if it broke. <<
--   The ratified definition is
--       in_queue(row) := classifiable(row) AND effective_sub_cat_id IS NULL
--   and both halves fall out of pfin.fn_cashflow_items (093) by construction:
--     · classifiable() = MEMBERSHIP in that function's output. Mechanically-
--       excluded rows never appear; 096's header already states this.
--     · effective_sub_cat_id = the EMITTED sub_cat_id. The two emission
--       branches resolve it per grain — an unsplit transaction projects
--       `c.ann_sub_cat_id` (the annotation's), a split child projects its OWN
--       `s.sub_cat_id`, and split PARENTS are never emitted at all (the split
--       XOR). There is no grain at which emitted and effective differ.
--   Therefore, and this is the line a reviewer should check rather than take:
--       in_queue(row) ≡ row ∈ pfin.fn_cashflow_items(p_as_of)
--                       AND row.sub_cat_id IS NULL
--   093's `unclassified.count_ytd` is FAITHFUL to the ratified predicate, not a
--   re-derived variant competing with it. This migration uses the same form for
--   the same reason, and adds no second definition.
--   ⚠ WHAT IS STILL WRONG, AND IS DELIBERATELY NOT FIXED HERE: the predicate is
--   SPELLED INLINE IN EACH CONSUMER with no shared home. 093 has one copy, this
--   file adds a second, and SELF-251 + SELF-254 will each want another. Four
--   hand-copies of a ratified predicate is the same drift shape that produced
--   SELF-344, and it deserves its own vehicle rather than a rider on this one.
--   BOOKED for close-out with the equivalence proof above attached, so the
--   implementer inherits the proof and not just the name.
--
-- ----------------------------------------------------------------------------
-- WHY THE WINDOW IS EXTRACTED (Option B) RATHER THAN RE-SPELLED (Option A).
--   The count must annotate the bars it sits beside, so it must use the SAME
--   window — not an equal one. 096 derived that window in two inline CTEs
--   exposed to nobody, so a standalone count could only re-spell them.
--   >> "THE SAME WINDOW DERIVATION, COPIED" IS NOT THE SAME WINDOW DERIVATION.
--      A second copy is correct on the day it is written and drifts silently
--      afterwards, and the failure it produces is worse than a missing banner:
--      the caption reports items the chart cannot display, and the reader
--      concludes the classify queue is broken. <<
--   The subtlety that makes a copy specifically dangerous is the (p_as_of + 1)
--   form — see fn_expenditure_window's own CONTRACT. It is not self-evident,
--   it has no comment obliging a future editor to mirror it, and getting it
--   wrong shifts the window by a whole month without raising anything.
--   ⚠ THE COUNT CANNOT INSTEAD COMPOSE ON 096's OUTPUT, which is the obvious
--   cheaper route and is closed: 096 filters `cat = 'Expense'` and INNER-JOINs
--   pfin.posting_prototype on sub_cat_id, so an unclassified row — NULL
--   sub_cat_id, hence NULL cat — is DOUBLY excluded from it. That is the S-2
--   ruling working correctly, not a gap.
--
-- ----------------------------------------------------------------------------
-- ⚠ THE COUNT IS UNSCOPED TO cat, AND THE SYMMETRY WITH 096 IS A TRAP.
--   Per the S-2 ruling: an unclassified item CARRIES NO Cat, so the §2.3.4
--   Expenses/non-tax filter cannot apply to it. A reader comparing this
--   function to 096 will notice the missing `cat = 'Expense'` and the missing
--   posting_prototype join and may "restore" them for symmetry.
--   >> DOING SO MAKES N PERMANENTLY ZERO. `cat` is NULL exactly when
--      sub_cat_id is NULL, so `cat = 'Expense'` is NULL for every row this
--      function counts, and the INNER join drops every one of them. The banner
--      would then never render, on every dataset, and NOTHING WOULD RAISE —
--      a fail-OPEN silence dressed as consistency. <<
--   This is why the filters are absent rather than commented out, and why
--   their absence is stated here and in the catalog comment.
--   ⚠ AND THE COPY MUST NOT CLAIM THE ITEMS ARE EXPENSES (AC9 verbatim): the
--   count is of items that MAY be expenses. That is a consumer obligation, but
--   it follows from this shape, so it is recorded at the source of the number.
--
-- ----------------------------------------------------------------------------
-- HOW "COMPUTED IN THE SAME QUERY AS THE SERIES" IS DELIVERED — stated so AC9's
--   sentence has a CHECKABLE REFERENT rather than an aspiration.
--   The property is delivered AT THE LOADER, in ONE STATEMENT that calls both
--   functions, of the shape:
--       select
--         (select jsonb_agg(to_jsonb(h)) from pfin.fn_historical_expenditures($1) h) as series,
--         u.unclassified_count, u.ms_floor, u.ms_last
--       from pfin.fn_expenditures_unclassified_count($1) u;
--   ⚠ ONE STATEMENT IS NOT WHAT MAKES THE TWO AGREE — that is the point most
--   likely to be lost. Both functions are STABLE and both derive their window
--   from pfin.fn_expenditure_window($1), so they agree because they share ONE
--   DERIVATION FROM ONE ARGUMENT, and they would still agree in two statements
--   in the same transaction. What the single statement buys is that the caller
--   cannot pass two different p_as_of values by accident.
--   >> AND THE AGREEMENT IS CHECKABLE FROM THE OUTPUT, not only by reading two
--      bodies: the count returns ms_floor and ms_last alongside N, so a
--      consumer — or a battery — can assert that the window N was taken over
--      is the window the series was bucketed into. This is 071's
--      provenance-column precedent (anchor_checkpoint_date /
--      current_checkpoint_date), where the columns added for the UI turned out
--      to be what made the battery deterministic. <<
--
-- ----------------------------------------------------------------------------
-- Numbering: 098, taken at authoring time and NOT reserved ahead. `git ls-tree`
--   over origin/main (at aa9410d, carrying 096 and 097) and over every remote
--   branch shows 098 unused. ⚠ That check cannot see an unpushed local branch
--   in another worktree, so it is RE-RUN in the commit turn — the 097 precedent,
--   where 096 was free on main and already allocated on an unmerged branch.
--   Depends on 093 (fn_cashflow_items — the sole ledger read, and the tenant
--   fence for both new objects), 066 (CPI, via 096 only), and on 096 having
--   created fn_historical_expenditures. ⚠ ORDER-DEPENDENT: the `create or
--   replace` requires that function to already exist with a matching signature,
--   so this migration MUST apply after 096.
--
-- ----------------------------------------------------------------------------
-- ⚠ WHY THE 096 RE-ISSUE IS `create or replace` AND NOT DROP + CREATE. Its
--   return shape is UNCHANGED — eleven columns, same names, same types, same
--   order — so CoR is accepted and is the correct vehicle: the OID survives, so
--   096's battery shape pin and every `regprocedure`-shaped assertion elsewhere
--   keep pointing at the same object. A DROP + CREATE would mint a new OID and
--   burn those for no gain. This is the 097 pattern.
--   THE THREE THINGS CoR DOES *NOT* DO FOR YOU, each handled below:
--     (i)   VOLATILITY IS RE-PARSED. `stable` is restated; an omitted clause
--           silently defaults to VOLATILE and no behavioural test would see it.
--     (ii)  THE CATALOG COMMENT SURVIVES — so 096's, which describes the window
--           as derived in this function, is re-issued to say where it now lives.
--           The window SEMANTICS do not change, so the old text is not false;
--           it is INCOMPLETE in a way that would send the next editor to the
--           wrong file. Re-issued under the 052 shape (regenerate-and-diff, one
--           anchored contiguous span, prefix and suffix proven byte-identical).
--     (iii) THE ACL SURVIVES. The revoke/grant pair below is an IDEMPOTENT
--           RESTATEMENT, not a repair — unlike a DROP + CREATE, where it would
--           be load-bearing. Stated because the two look identical in a diff.
--   ⚠ 096's BODY IS OTHERWISE CARRIED FORWARD EXPRESSION-FOR-EXPRESSION. The
--   only change is that the `bounds` + `span` CTE pair becomes a single `span`
--   CTE selecting from pfin.fn_expenditure_window(p_as_of). The CTE KEEPS ITS
--   NAME so that no downstream reference moves, and the extracted arithmetic is
--   byte-identical to what it replaces — verified differentially, not by
--   inspection: see the QA note.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER on all three objects (Lock 11
--   read-composition default); NOT SECURITY DEFINER. Each runs as the caller and
--   inherits their RLS context exactly as 049 / 051 / 062 / 067 / 069 / 093 /
--   096 do. Every value returned derives from rows the caller may already read.
--   DEFINER would detach the read from the caller's RLS context and from the
--   025 aal2 step-up backstop that reaches these surfaces through 093's
--   policies. THE SECURITY DEFINER ALLOWLIST IS NOT TOUCHED. Read ADR-011
--   Decision 9 live; no count is restated here.
--   ⚠ fn_expenditure_window READS NO RELATION AT ALL — it is pure calendar
--   arithmetic on its argument. It is INVOKER for consistency with the family
--   rather than out of necessity, and it is deliberately NOT marked IMMUTABLE:
--   see its CONTRACT.
--
-- ----------------------------------------------------------------------------
-- TENANT FENCE — INHERITED, NOT RESTATED, and UNCHANGED by this migration.
--   fn_expenditures_unclassified_count gains no `users_id = auth.uid()`
--   predicate and MUST NOT. Isolation comes entirely from pfin.fn_cashflow_items
--   (093), whose own reads are fenced by the RLS policies on the underlying
--   ledger, reached through the INVOKER posture; the 025 aal2 backstop reaches
--   this surface through those same policies. QA MEASURED on 062 that a
--   redundant local predicate keeps the cross-tenant battery GREEN over a policy
--   broken open with `using (true)` — so the omission is load-bearing, not tidy.
--   A cross-tenant caller sees no items and the count is 0, which is the
--   fail-closed direction for a DISCLOSURE signal: it can only under-report
--   another tenant's unclassified items, never reveal them.
--   ⚠ fn_expenditure_window crosses no tenant boundary — it reads nothing.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; the catalogued
--   numbered list is NOT restated, not even to negate it, and no count is
--   stated. Decision 4 read VERBATIM at the canonical anchor before drafting,
--   2026-08-31, at aa9410d.)
--   (i)   Instance-numbering: nothing appended, reordered, or renumbered.
--   (ii)  Layer-attribution: two new INVOKER read helpers and one re-issued
--         INVOKER read helper, all reached by `authenticated` over PostgREST.
--         No catalogued instance's layer attribution moves; no surface becomes
--         "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is REFERENCED, not restated.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED set are DIFFERENT SETS and are
--   NOT reconciled here.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — +0. No table, no column, no
--   FK-shaped reference of any kind is created, altered or dropped; this
--   migration authors no DDL beyond two new functions and one function body
--   replacement. Read Decision 3's body live — it grows and its labels are
--   non-contiguous. No authoring-time tally is recorded here: a migration that
--   adds no column cannot join the family.
--
-- ----------------------------------------------------------------------------
-- LEDGER DELTAS (all FLAT, and offered as a claim for Sec to verify): §10
--   catalogued +0 · SECURITY DEFINER allowlist +0 · Decision 3 family +0 · SD
--   matrix NO expansion · RLS unchanged · policies unchanged · triggers
--   unchanged · grants on EXISTING objects unchanged (096's pair is a
--   restatement; the two new functions take their own fresh REVOKE/GRANT).
--
-- ----------------------------------------------------------------------------
-- QA TEST-PAIRING (QA-owned). Ships SAME-PR.
--   1. ⭐ THE CRUX LEG — THE EXTRACTION IS BEHAVIOUR-PRESERVING, PROVEN
--      DIFFERENTIALLY AND NOT BY READING. Assert
--        fn_expenditure_window(d) = the pre-096 inline arithmetic, for EVERY d
--      over a generated date range that INCLUDES: month-ends, the 1st, mid-month
--      days, 28/29/30/31 Feb boundaries in a leap and a non-leap year, 31
--      December and 1 January, and NULL. A spot-check on today's date cannot
--      distinguish a correct extraction from one that shifted the window by a
--      month, because the two agree on most days.
--      ⚠ Do NOT compute the expected bound with the NEW function's expression —
--      that tests the implementation against itself. Use the arithmetic as it
--      stood in 096 at aa9410d, or an independent derivation.
--   2. 096's OUTPUT IS UNCHANGED BY THE CoR: same rows, same values, over a
--      fixture with data on both window edges. This is the leg that catches a
--      botched CTE splice, which a green apply looks identical to.
--   3. THE COUNT USES THE SAME WINDOW AS THE SERIES, asserted FROM THE OUTPUT:
--      the count's ms_floor / ms_last equal the window the series was bucketed
--      into. Include an item just OUTSIDE each edge and assert it is excluded —
--      an all-inside fixture passes under a wrong bound.
--   4. ⚠ THE PARTIAL-MONTH EDGE, BOTH SIDES: an unclassified item dated in the
--      CURRENT INCOMPLETE month is NOT counted, because the chart shows no bar
--      for that month. A count that includes it reports items the reader cannot
--      find. Assert with a mid-month p_as_of, which is the only p_as_of that
--      distinguishes this.
--   5. THE COUNT IS UNSCOPED TO cat, NON-VACUOUSLY: a fixture holding
--      unclassified items that WOULD fail `cat = 'Expense'` still counts them.
--      ⚠ A fixture whose unclassified items happen to be expense-shaped cannot
--      distinguish this function from one carrying the 096 filters — and the
--      filtered variant returns 0 always, so the vacuous fixture passes it.
--   6. GRAIN: split children count INDIVIDUALLY and a split PARENT is never
--      counted (the 093 split XOR). Assert on a split with an unclassified
--      child and a classified sibling.
--   7. NULL p_as_of RETURNS NULL, NOT 0 — and the difference is the whole
--      point: 0 asserts "nothing is unclassified" and NULL says "this could not
--      be computed". 096 returns zero rows on NULL; the count must not turn
--      that into a reassuring number. See the CONTRACT.
--   8. TWO-TENANT, NON-VACUOUSLY: identical dates, DIFFERENT unclassified
--      populations; A's call returns A's count. A same-population fixture
--      passes under a broken predicate.
--   9. CROSS-TENANT: count 0, not an error, not the other tenant's.
--  10. AAL2 BACKSTOP, BOTH LEGS — aal1 gets 0 / no rows, aal2 gets the real
--      figures. The negative alone passes vacuously on an empty fixture.
--  11. POSTURE, ALL THREE: prosecdef false, provolatile 's', proconfig pins
--      search_path empty. ⚠ For 096 this is not ceremony — an omitted
--      volatility clause in a CoR silently re-creates it VOLATILE.
--  12. ACL, ALL THREE: EXECUTE revoked from PUBLIC, granted to `authenticated`,
--      NOT held by service_role. Assert on pg_proc.proacl.
--  13. 096's CATALOG COMMENT renders and now names fn_expenditure_window;
--      read back via obj_description.
--   ⚠ THE BANNED CLI RESET SUBCOMMAND IS PROHIBITED — it destroys F/CTO's local
--   test data. Verify non-destructively (apply-in-txn + rollback, or a scratch
--   database built with createdb).
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- pfin.fn_expenditure_window — THE §2.3.4 TRAILING-5-YEAR WINDOW, EXTRACTED SO
-- IT HAS EXACTLY ONE HOME. Previously two inline CTEs inside 096, visible to
-- nobody; now the single source both 096 and the AC9 count derive from.
--
-- CONTRACT
--   pfin.fn_expenditure_window(p_as_of date)
--     RETURNS TABLE (ms_floor date, ms_last date)
--     — SECURITY INVOKER, STABLE, set search_path = ''. Reads NO relation.
--   · EXACTLY ONE ROW, ALWAYS — including for a NULL argument, where both
--     columns are NULL. ⚠ THE CARDINALITY IS PART OF THE CONTRACT, not an
--     incidental property: 096 consumes this through a CROSS JOIN, so a
--     zero-row return would silently empty its result and a two-row return
--     would silently double it. The single-row shape is what the CTE pair it
--     replaces had (a SELECT with no FROM), and it is preserved deliberately.
--   · Both bounds are FIRST-OF-MONTH dates, not month-ends. The consumer
--     buckets by date_trunc('month', ...) and compares in that space.
--   · ms_last = the first-of-month of the LAST COMPLETE month at or before
--     p_as_of. ms_floor = 59 months before ms_last — inclusive of BOTH
--     endpoints, which is 60 months, not 59 and not 61.
--
--   ⚠⚠ THE (p_as_of + 1) FORM IS THE SUBTLE PART, AND IT IS THE WHOLE REASON
--   THIS FUNCTION EXISTS RATHER THAN A SECOND COPY OF THE EXPRESSION.
--     date_trunc('month', (p_as_of + 1)) - 1 month
--   is what makes a p_as_of that IS a month-end KEEP its own month, while any
--   earlier day in that month DROPS it. Work it: for 2026-08-31, p_as_of + 1 is
--   2026-09-01, truncating to 2026-09-01, minus one month = 2026-08-01 — August
--   is in. For 2026-08-30, p_as_of + 1 is 2026-08-31, truncating to 2026-08-01,
--   minus one month = 2026-07-01 — August is out, because August is not over.
--   >> DROP THE `+ 1` AND EVERY MONTH-END QUERY SILENTLY LOSES ITS MOST RECENT
--      MONTH. Nothing raises; the chart is simply one bar short, and the bar it
--      is short of is the one the reader came to see. <<
--   This is the property a second hand-written copy would eventually get wrong,
--   and it is why "the same window derivation, copied" is not the same window
--   derivation.
--
--   ⚠ A MID-MONTH p_as_of THEREFORE EMITS NOTHING FOR ITS OWN MONTH, and that
--   is correct rather than a truncation bug: every emitted month is COMPLETE by
--   construction, so no bar is a partial month wearing a full month's label,
--   and no count reports items sitting in a month the chart does not draw.
--
--   ⚠ THE ::timestamp CASTS ARE LOAD-BEARING and must not be "simplified" away.
--   `timestamp without time zone` is zone-free, so nothing here is evaluated in
--   the session TimeZone — 066's hazard and ADR-044's. Carried verbatim from
--   096, where the same note stood over the same arithmetic.
--
--   · NULL p_as_of yields (NULL, NULL) rather than raising. This is what makes
--     096's "a NULL p_as_of returns zero rows" contract hold WITHOUT a guard:
--     every downstream comparison against a NULL bound is NULL, so the rows
--     filter out. Fails closed, quietly and by construction.
--
--   ⚠ STABLE, NOT IMMUTABLE, DELIBERATELY. The arithmetic is in fact immutable
--   today, so the stronger marking would be accepted. It is declined because
--   IMMUTABLE is a PROMISE ABOUT THE FUTURE that buys nothing measurable here —
--   the function is evaluated once per query — while PRD §2.3.4 already names a
--   user-configurable horizon as a V2 candidate, which would falsify it. Under-
--   promising is the safe direction, and it keeps the posture leg uniform
--   across this family so QA asserts one value, not two.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_expenditure_window(p_as_of date)
returns table (
  ms_floor date,
  ms_last  date
)
language sql
stable
security invoker
set search_path = ''
as $$
  -- ⚠ ms_last is written ONCE and ms_floor derives FROM IT. Spelling the upper
  -- bound twice inside the very function that exists to stop it being spelled
  -- twice would be self-defeating, and the two copies could then drift by a
  -- month against each other with nothing raised.
  -- Neither CTE nor SELECT has a FROM clause, so this is exactly one row,
  -- always. See the CONTRACT — 096 cross-joins this, so cardinality is
  -- load-bearing. The structure is 096's own `bounds` + `span` pair, carried
  -- over expression-for-expression rather than rewritten.
  with bounds as (
    select
      (date_trunc('month', (p_as_of + 1)::timestamp) - interval '1 month')::date as ms_last
  )
  select
    (b.ms_last::timestamp - interval '59 months')::date as ms_floor,
    b.ms_last
  from bounds b;
$$;

revoke execute on function pfin.fn_expenditure_window(date) from public;
grant  execute on function pfin.fn_expenditure_window(date) to authenticated;

comment on function pfin.fn_expenditure_window(date) is
  'SECURITY INVOKER calendar-arithmetic helper: THE §2.3.4 trailing-5-year window bound, extracted at 098 so it '
  'has exactly ONE home. Returns (ms_floor, ms_last) as FIRST-OF-MONTH dates — consumers bucket by '
  'date_trunc(''month'', ...) and compare in that space. ms_last = the first-of-month of the LAST COMPLETE month at '
  'or before p_as_of; ms_floor = 59 months earlier, inclusive of BOTH endpoints, which is 60 months. '
  'EXACTLY ONE ROW ALWAYS, including for a NULL argument, where both columns are NULL. THE CARDINALITY IS PART OF '
  'THE CONTRACT: pfin.fn_historical_expenditures consumes this through a CROSS JOIN, so a zero-row return would '
  'silently empty its result and a two-row return would silently double it. '
  'THE (p_as_of + 1) FORM IS THE SUBTLE PART and is why this is a function rather than a copied expression: it is '
  'what makes a p_as_of that IS a month-end keep its own month while any earlier day in that month drops it. For '
  '2026-08-31 the window ends 2026-08-01; for 2026-08-30 it ends 2026-07-01, because August is not over. Drop the '
  'plus-one and every month-end query silently loses its most recent month, with nothing raised. A mid-month '
  'p_as_of therefore emits nothing for its own month, which is correct: every emitted month is COMPLETE by '
  'construction, so no bar is a partial month wearing a full month''s label. '
  'A NULL p_as_of yields (NULL, NULL) rather than raising — that is what makes the caller''s zero-rows-on-NULL '
  'contract hold with no guard, since every comparison against a NULL bound is NULL. Fails closed by construction. '
  'The ::timestamp casts are LOAD-BEARING: that type is zone-free, so nothing here is evaluated in the session '
  'TimeZone. Do not simplify them away. '
  'STABLE and NOT IMMUTABLE, deliberately: the arithmetic is immutable today, but IMMUTABLE is a promise about the '
  'future that buys nothing measurable for a function evaluated once per query, and a user-configurable horizon is '
  'already a named V2 candidate that would falsify it. '
  'SECURITY INVOKER — NOT a DEFINER allowlist entry; read ADR-011 Decision 9 live. Reads NO relation, so it crosses '
  'no tenant boundary and carries no fence of its own. EXECUTE revoked from PUBLIC, granted to authenticated.';

-- ----------------------------------------------------------------------------
-- pfin.fn_expenditures_unclassified_count — AC9's N: the unclassified-item
-- count over the SAME trailing-5-year window the §2.3.4 bars are bucketed into.
--
-- CONTRACT
--   pfin.fn_expenditures_unclassified_count(p_as_of date)
--     RETURNS TABLE (unclassified_count bigint, ms_floor date, ms_last date)
--     — SECURITY INVOKER, STABLE, set search_path = ''.
--   · EXACTLY ONE ROW, ALWAYS.
--   · unclassified_count counts ITEMS — rows of pfin.fn_cashflow_items — whose
--     sub_cat_id IS NULL and whose transaction_date falls in the window. That
--     is the ratified in_queue predicate; see the header for why the name has
--     no DDL and why this form is faithful to it rather than a variant.
--   · GRAIN IS THE ITEM, NOT THE TRANSACTION. A split transaction contributes
--     one count per unclassified CHILD, and never contributes for its parent —
--     093 emits children XOR parent, so a split parent is not a countable row
--     at all. This matches AC9's "N items", and it means N can exceed the
--     number of transactions a user recognises. That is intended: the classify
--     queue works at the same grain, so N and the queue agree.
--   · ms_floor / ms_last are RETURNED, not merely used. ⚠ THIS IS WHAT MAKES
--     "the same window as the series" CHECKABLE FROM THE OUTPUT rather than by
--     reading two function bodies — a consumer or a battery asserts that the
--     window N was taken over is the window the bars were bucketed into. It is
--     071's provenance-column precedent, where the columns added for the UI
--     turned out to be what made the battery deterministic.
--
--   ⚠⚠ NULL p_as_of RETURNS unclassified_count = NULL, NOT 0, AND THE
--   DIFFERENCE IS THE POINT. 0 asserts "nothing is unclassified" — a
--   reassurance — where NULL says "this could not be computed". The sibling
--   surface returns ZERO ROWS on a NULL argument; a count that turned that into
--   0 would hand a consumer a confident all-clear derived from no data, and the
--   banner would correctly not render for a reason that is wrong. This mirrors
--   the delta-panel ruling that "no change" and "cannot be expressed" must not
--   render alike. count(*) over an empty set is 0, so the NULL is produced by
--   an explicit CASE and cannot arise on its own.
--
--   ⚠ NO cat FILTER AND NO posting_prototype JOIN, DELIBERATELY — and their
--   absence is load-bearing, not an oversight to be tidied for symmetry with
--   pfin.fn_historical_expenditures. An unclassified item carries NO Cat (cat
--   is NULL exactly when sub_cat_id is NULL), so `cat = 'Expense'` is NULL for
--   every row this function counts and the INNER join drops every one of them.
--   >> ADDING THEM MAKES N PERMANENTLY ZERO ON EVERY DATASET, the banner never
--      renders, and NOTHING RAISES. A fail-OPEN silence dressed as consistency.
--      This is the S-2 ruling: the Expenses/non-tax filter cannot apply to an
--      item that has no Cat to filter on. <<
--   ⚠ CONSUMER OBLIGATION, recorded at the source of the number because it
--   follows from this shape: the copy MUST NOT claim the counted items ARE
--   expenses. They are items that MAY be expenses (AC9 verbatim).
--
--   · Security-load-bearing edges: the tenant fence is 093's, inherited whole
--     through the INVOKER posture — no users_id predicate here and none may be
--     added. A cross-tenant caller sees no items and gets 0, which is the
--     fail-closed direction for a DISCLOSURE signal: it can only under-report
--     another tenant's unclassified items, never reveal them.
--   · KNOWN COST, stated rather than discovered: in the loader's single
--     statement pfin.fn_cashflow_items is invoked TWICE — once here and once
--     inside the series function. Sharing one invocation would mean returning
--     the count from that function, i.e. a return-shape change and a DROP +
--     CREATE, which is what this migration exists to avoid. Correctness is
--     unaffected; both invocations take the same p_as_of and both are STABLE.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_expenditures_unclassified_count(p_as_of date)
returns table (
  unclassified_count bigint,
  ms_floor           date,
  ms_last            date
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    -- Explicit NULL on a NULL argument. count(*) over an empty set is 0, and 0
    -- is the one answer this must not give when it has no basis for it.
    case when p_as_of is null then null::bigint
         else (
           select count(*)::bigint
           from pfin.fn_cashflow_items(p_as_of) i
           -- THE RATIFIED in_queue PREDICATE. Membership in the reader IS
           -- classifiable(); the emitted sub_cat_id IS the effective one (093
           -- resolves it per grain and never emits a split parent). No second
           -- definition is introduced here — see the header's equivalence.
           where i.sub_cat_id is null
             -- Bucket the ITEM by its own transaction_date and clip to the
             -- window, in the SAME first-of-month space and with the SAME
             -- inclusive form the series uses. The bounds themselves come from
             -- the shared window function, so only this comparison is local.
             -- ⚠ The ::timestamp cast is zone-free and load-bearing.
             and date_trunc('month', i.transaction_date::timestamp)::date >= w.ms_floor
             and date_trunc('month', i.transaction_date::timestamp)::date <= w.ms_last
         )
    end as unclassified_count,
    w.ms_floor,
    w.ms_last
  from pfin.fn_expenditure_window(p_as_of) w;
$$;

revoke execute on function pfin.fn_expenditures_unclassified_count(date) from public;
grant  execute on function pfin.fn_expenditures_unclassified_count(date) to authenticated;

comment on function pfin.fn_expenditures_unclassified_count(date) is
  'SECURITY INVOKER §2.3.4 AC9 backend: the UNCLASSIFIED-ITEM COUNT over the same trailing-5-year window the '
  'expenditure bars are bucketed into (V1.3; PRD §2.3.4 / SELF-256; ADR-011 Lock 11 read-composition). Returns '
  'EXACTLY ONE ROW ALWAYS. STABLE, set search_path = ''''. '
  'GRAIN IS THE ITEM, NOT THE TRANSACTION: a split transaction contributes one count per unclassified CHILD and '
  'never for its parent, because pfin.fn_cashflow_items emits children XOR parent. N can therefore exceed the '
  'number of transactions a user recognises — intended, because the classify queue works at the same grain, so N '
  'and the queue agree. '
  'ms_floor and ms_last are RETURNED, not merely used: that is what makes "the same window as the series" '
  'checkable FROM THE OUTPUT rather than by reading two bodies, so a consumer or a battery can assert the window N '
  'was taken over is the window the bars were bucketed into. Both bounds come from pfin.fn_expenditure_window, the '
  'single home shared with the series, so the banner cannot describe a different window than the bars. '
  'A NULL p_as_of returns unclassified_count NULL, NOT 0 — 0 asserts "nothing is unclassified" where NULL says '
  '"this could not be computed", and the series function returns zero rows on a NULL argument. Turning that into 0 '
  'would hand a consumer a confident all-clear derived from no data. count(*) over an empty set is 0, so the NULL '
  'is produced by an explicit CASE and cannot arise on its own. '
  'NO cat FILTER AND NO posting_prototype JOIN, and their absence is LOAD-BEARING rather than an oversight to be '
  'tidied for symmetry with pfin.fn_historical_expenditures. An unclassified item carries no Cat — cat is NULL '
  'exactly when sub_cat_id is NULL — so cat = ''Expense'' is NULL for every row counted here and an INNER join to '
  'posting_prototype drops every one of them. ADDING THEM MAKES N PERMANENTLY ZERO on every dataset, the banner '
  'never renders, and nothing raises: a fail-OPEN silence dressed as consistency. This is the S-2 ruling — the '
  'Expenses/non-tax filter cannot apply to an item that has no Cat to filter on. '
  'CONSUMER OBLIGATION, recorded at the source of the number: the copy MUST NOT claim the counted items ARE '
  'expenses; they are items that MAY be expenses. '
  'TENANT FENCE: pfin.fn_cashflow_items (093) is the SOLE mechanism, inherited whole through the INVOKER posture — '
  'no users_id predicate of its own and it MUST NOT GAIN ONE. A cross-tenant caller sees no items and gets 0, the '
  'fail-closed direction for a disclosure signal: it can only under-report another tenant''s unclassified items, '
  'never reveal them. The 025 aal2 backstop is inherited through those same policies. '
  'SECURITY INVOKER — NOT a DEFINER allowlist entry; read ADR-011 Decision 9 live. §10 catalogued ledger UNCHANGED '
  'BY THIS OBJECT and NO COUNT IS STATED HERE; read ADR-011 Decision 4 live. Decision-3 unchanged. EXECUTE revoked '
  'from PUBLIC, granted to authenticated. Sec joint-review-mandatory (completeness signal on a multi-tenant money '
  'path); RLS verification -> the SELF-256 battery.';

-- ----------------------------------------------------------------------------
-- pfin.fn_historical_expenditures — RE-ISSUED by `create or replace`. The ONLY
-- change is that the inline `bounds` + `span` CTE pair becomes a single `span`
-- CTE selecting from pfin.fn_expenditure_window(p_as_of). Return shape, column
-- names, types, order and every other expression are carried from 096's live
-- text unaltered. `security invoker`, `stable` and `set search_path = ''` are
-- restated because CoR re-parses the whole definition and an omitted volatility
-- clause would silently default to VOLATILE.
-- ----------------------------------------------------------------------------
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
  -- THE WINDOW, FROM ITS SINGLE HOME (098). The `bounds` + `span` CTE pair that
  -- stood here derived the trailing-5-year edge inline and exposed it to
  -- nobody, so the §2.3.4 unclassified-item count could only have re-spelled
  -- it. The arithmetic is UNCHANGED — it was MOVED, not rewritten — and it now
  -- lives in pfin.fn_expenditure_window, which both this function and that
  -- count derive from. The (p_as_of + 1) subtlety and the load-bearing
  -- zone-free ::timestamp casts are documented there, at the arithmetic.
  -- ⚠ THE CTE KEEPS THE NAME `span` so that no downstream reference moves: this
  -- is a one-CTE substitution, not a refactor, and the diff should show exactly
  -- that. ⚠ The window function returns EXACTLY ONE ROW ALWAYS, including for a
  -- NULL p_as_of where both bounds are NULL — that cardinality is what keeps
  -- the CROSS JOIN below sound, and it is what preserves this function's
  -- zero-rows-on-NULL contract without needing a guard.
  span as (
    select w.ms_last, w.ms_floor
    from pfin.fn_expenditure_window(p_as_of) w
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

-- The ACL is PRESERVED by `create or replace` — the revoke-first discipline
-- quoted at 096 applies to a FRESHLY CREATED function, which this is not. The
-- pair is re-issued as an idempotent restatement so the intended ACL is
-- asserted at this file rather than inferred two migrations back; it is NOT
-- repairing a widening here, and the two cases look identical in a diff.
revoke execute on function pfin.fn_historical_expenditures(date) from public;
grant  execute on function pfin.fn_historical_expenditures(date) to authenticated;

-- The catalog comment SURVIVES a `create or replace`, so 096's must be
-- overwritten explicitly or it goes on describing the window as derived inside
-- this function. The window SEMANTICS are unchanged, so the old text is not
-- false — it is INCOMPLETE in the one way that sends the next editor to the
-- wrong file. Regenerated from the live text with one anchored contiguous
-- substitution; not retyped.
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
  '<= p_as_of. ⚠ THE BOUND IS NOT DERIVED HERE — since 098 it comes from '
  'pfin.fn_expenditure_window(p_as_of), the single home shared with the §2.3.4 unclassified-item count, so the '
  'banner cannot describe a different window than the bars. The arithmetic was MOVED, not changed; the '
  '(p_as_of + 1) subtlety that keeps a month-end''s own month is documented there. '
  '⚠ A mid-month p_as_of emits NOTHING for its own month — every '
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

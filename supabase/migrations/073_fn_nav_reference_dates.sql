-- ============================================================================
-- Migration: pfin.fn_nav_reference_dates — the §2.1.4 NAV-at-three-reference-
--   dates backend. SECURITY INVOKER read-composition (Lock 11) over
--   pfin.nav_daily (054) for the levels and pfin.fn_cpi_u_index_for_period (066)
--   for every CPI observation, with today's date from pfin.fn_server_today
--   (070). V1.1; PRD §2.1.4. F/CTO-ratified 2026-08-14 on the joint
--   Architect/PM reconciliation package. apply-migration procedure applied.
--   JOINT-REVIEW-MANDATORY (Sec veto surface): financial calculation +
--   multi-tenant read path.
--
-- ----------------------------------------------------------------------------
-- ⭐ THIS SURFACE IS THE LEVELS VIEW OF THE ANCHORS 072 ALREADY SHOWS AS DELTAS,
--   and that is the single most important thing to know before changing either.
--     this_month     = 072's CURRENT ENDPOINT (LOCF at-or-before today)
--     prior_month    = 072's `month` horizon ANCHOR (v_base)
--     prior_year_end = 072's `ytd`   horizon ANCHOR (31 December, prior year)
--   PRD Appendix C composes §2.1.4, §2.1.3 and §2.1.2 into ONE report section
--   with rendering order matching the incumbent layout, so this table and the
--   delta panel render ADJACENT. Under the anchors above, a reader subtracting
--   two cells in this table lands EXACTLY on a figure in the panel below it:
--       (this_month nav) - (prior_month nav)    = 072's 'month' delta_nominal
--       (this_month nav) - (prior_year_end nav) = 072's 'ytd'   delta_nominal
--   >> THE DERIVATIONS BELOW ARE THE SAME EXPRESSIONS 072 USES, NOT MERELY
--      SIMILAR ONES. If you change one, the two panels disagree on screen and
--      the surface that looks broken will be whichever one the reader checked
--      second. <<
--
--   ⚠ "PRIOR MONTH" WAS GENUINELY AMBIGUOUS AND IS NOW RULED, so it is not
--   re-opened by the next reader: it means THE MOST RECENT COMPLETED MONTH-END,
--   not the month-end before that. The competing reading — "the month-end
--   at-or-before (today - 1 month)" — lands up to six weeks back and would break
--   the reconciliation above; 071's header records the same ambiguity being
--   resolved the same way for the delta panel. F/CTO-ratified 2026-08-14.
--
-- ----------------------------------------------------------------------------
-- Numbering: 073 is next-free, taken at authoring time and verified against
--   origin/main at 4270495 (git ls-tree, not a local listing — main had moved
--   twice during this item). Depends on 054 (nav_daily — the sole relation read;
--   its RLS SELECT policy and inherited 025 aal2 backstop are what fence this
--   function), 066 (every CPI observation), and 070 (today). Order-independent:
--   a plpgsql body is not resolved against the catalog at create time, and this
--   migration drops nothing.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (Lock 11 read-composition default); NOT
--   SECURITY DEFINER. Runs as the caller and inherits their RLS context exactly
--   as 049 / 051 / 062 / 067 / 069 / 071 do. Every value it returns derives from
--   rows the caller may already read. DEFINER would detach the read from the
--   caller's RLS context and from the 025 aal2 step-up backstop nav_daily's
--   policy carries, and would break 070's guarantee, whose whole basis is that
--   the function and its caller share a session.
--   THE SECURITY DEFINER ALLOWLIST IS NOT TOUCHED. Read ADR-011 Decision 9 live;
--   no count is restated here.
--
-- ----------------------------------------------------------------------------
-- TENANT FENCE — INHERITED, NOT RESTATED. No `users_id = auth.uid()` predicate
--   of its own, and it MUST NOT GAIN ONE. Isolation comes entirely from
--   nav_daily's `nav_daily_select` policy (054) through the INVOKER posture; the
--   025 aal2 backstop reaches this surface through that same policy. QA MEASURED
--   on 062 that a redundant local predicate keeps the cross-tenant battery GREEN
--   over a policy broken open with `using (true)` — so the omission is
--   load-bearing, not tidy. A cross-tenant caller sees no rows and gets three
--   all-NULL rows: fails closed. The CPI legs cross no tenant boundary (066
--   reads global `using (true)` reference tables).
--   ⚠ THE PARAMETER LIST IS EMPTY, DELIBERATELY. `p_users_id` was struck on the
--   same grounds recorded in 071's header (which enumerates the family: 049 R2 /
--   051 / 067) — tenant comes from session RLS, and a uid parameter is either
--   redundant or a cross-tenant read shape. NO ORDINAL IS STATED HERE: an
--   ordinal is a claim that goes stale, an enumeration of instances stays
--   checkable, and 071's own enumeration contains the indexical "here", which
--   re-points when the text is copied. Read 071's header for the list.
--   `p_scope` was struck because THE TYPE DOES NOT EXIST — verified at 4270495,
--   the schema declares no `create type` at all — so it is not a deferral;
--   scope aggregation is a separate item's.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_nav_reference_dates()
--     RETURNS TABLE (reference text, reference_date date,
--                    reference_checkpoint_date date,
--                    nav numeric, nav_prior_yr_dollars numeric,
--                    cpi_period date, cpi_basis_period date,
--                    cpi_any_carried boolean, cpi_unavailable boolean)
--     — SECURITY INVOKER, STABLE, set search_path = ''. No parameters.
--   · EXACTLY THREE ROWS, ALWAYS, in fixed order: 'this_month', 'prior_month',
--     'prior_year_end'. A reference is NEVER absent — an uncomputable one returns
--     its row with NULL values. "The query dropped it" and "it is not computable"
--     must not render identically (071's ruling).
--   · reference_date is the CALENDAR reference. reference_checkpoint_date is the
--     checkpoint that actually served it, which is EARLIER when carried. BOTH are
--     returned so "measured on the reference date" stays distinguishable from
--     "carried from before it" — 062's carry-forward-with-provenance pattern.
--   · nav_prior_yr_dollars = nav x (cpi_basis / cpi_at_reference_date). NULL
--     whenever nav is NULL or the CPI legs do not resolve; nav STANDS in the
--     latter case, because the nominal figure never depended on CPI.
--   · cpi_any_carried is an OR over THIS ROW'S TWO LEGS — the basis leg and the
--     row's own reference-date leg. 071's same-named column ORs three. "Any" is
--     doing real work; it is not a synonym for "the CPI was carried".
--   · cpi_basis_period is CALENDAR-DERIVED, never an observation: December of the
--     prior year, computed from fn_server_today by date arithmetic with no call
--     to 066. Carrying changes WHICH OBSERVATION SUPPLIES A VALUE for a period;
--     it never changes THE PERIOD LABEL. It is therefore identical on all three
--     rows and NON-NULL even when cpi_unavailable is true — so a consumer can
--     still render "in <year> dollars" as a column header over a blank cell.
--     ⚠ "Identical on all three rows" is a WITHIN-ONE-CALL claim. Two sessions in
--     different zones straddling 31 December / 1 January can derive different
--     values for today, moving the basis BY A FULL YEAR — the residual 072's
--     header documents. Not a defect and not to be "fixed" in code.
--
--   ⚠ TWO NULL CAUSES HERE, NOT THREE — AND THE DIFFERENCE FROM 072 IS THE TRAP.
--     072 has a third, NOT APPLICABLE, because its month and ytd rows carry no
--     real-terms figure at all. EVERY ROW OF THIS SURFACE IS CPI-ELIGIBLE, so
--     that cause DOES NOT EXIST HERE and cpi_* columns are never all-NULL:
--       INSUFFICIENT HISTORY  reference_date NOT NULL, reference_checkpoint_date
--                             NULL -> no observation reaches this reference date.
--                             nav AND nav_prior_yr_dollars both NULL. This is the
--                             row the UI renders as "Insufficient history".
--       CPI UNRESOLVABLE      cpi_unavailable = true, nav PRESENT -> the nominal
--                             figure stands; only the prior-year-dollar cell is
--                             blank.
--     >> DO NOT COPY 072'S THREE-CAUSE LANGUAGE ONTO THIS SURFACE. <<
--   · The history predicate is PER ROW — the caller's earliest checkpoint is
--     at-or-before THAT ROW'S reference_date. It is NOT a global "one year of
--     history" rule: in December the prior year-end is twelve months back, in
--     January about one. A fixture built on the global rule never exercises the
--     row that actually fails.
--   · Security-load-bearing edges: RLS on nav_daily is the SOLE tenant fence;
--     cross-tenant callers get three all-NULL rows and fail closed; the 025 aal2
--     backstop is inherited; CPI legs are strictly-positive-guarded so a poisoned
--     print can neither raise nor flip a sign; every CPI value comes from 066, so
--     the gap policy is not re-derived here; `set search_path = ''` with every
--     reference schema-qualified.
--   · NO ROUNDING IS APPLIED. nav_prior_yr_dollars carries `numeric` division
--     residue on the two non-basis rows exactly as 072's real-terms columns do.
--     Presentation rounding belongs to the consumer; assertions need a tolerance.
--     THE prior_year_end ROW IS THE EXCEPTION — see below, it is exact.
--
-- ----------------------------------------------------------------------------
-- CPI COMPOSITION — every observation through 066, never an inline lookup (066's
--   standing requirement: the carry-forward and gap-classification policy is not
--   re-derived in a consumer).
--     basis (all rows) : DECEMBER of the prior calendar year — the denomination
--                        the whole table is expressed in.
--     this_month       : the print at 066's coverage_through — the SAME
--                        observation 067 and 072 use for "now", so the chart, the
--                        delta panel and this table cannot disagree about what
--                        today's dollars are.
--     prior_month      : first-of-month of the CALENDAR reference month.
--     prior_year_end   : first-of-month of ITS calendar reference month, which IS
--                        December of the prior year — the basis period itself.
--   ⚠ PINNING TO THE CALENDAR REFERENCE — NOT TO THE SERVING CHECKPOINT — is what
--   stops the basis reference drifting when carry-forward reaches back. 067's
--   deflate-at-the-point precedent, and 072's ratified pinning, unchanged.
--
--   ⭐ THE PRIOR-YEAR-END ROW IS EXACT BY CONSTRUCTION, AND IT IS A FENCE.
--   That row's CPI period IS the basis period, so both the numerator's basis leg
--   and the denominator's reference leg are THE SAME REQUEST to 066 — same period
--   argument, STABLE function, one snapshot, therefore the same value. The ratio
--   is v/v = 1 and nav_prior_yr_dollars = nav EXACTLY, with no residue.
--     · The CARRIED case is safe. In January and February the December print does
--       not exist yet (CPI publishes one to two months in arrears) and 066 serves
--       it carried, so cpi_any_carried comes back TRUE table-wide for roughly two
--       months a year — structurally correct, correctly signalled, and the SAME
--       carried value sits in numerator and denominator, so exactness survives.
--     · The ONE exception is CPI-UNRESOLVABLE, where nav stands and
--       nav_prior_yr_dollars is NULL. ⚠ THE EQUALITY CLAIM IS SCOPED TO
--       `cpi_unavailable = false` AND IS FALSE WITHOUT THAT SCOPE. An
--       unconditional form would send a future corrector hunting in the column
--       that is working correctly.
--     · WHY IT IS A FENCE AND NOT A TAUTOLOGY: the proof fails only if the two
--       legs stop being the same request — which is exactly what "simplifying"
--       all three rows onto coverage_through (correct only for this_month) would
--       do. The battery leg reds immediately if anyone tries it.
--   ⚠ STRICTLY-POSITIVE GUARD on both legs: 053 bars NaN and +/-Infinity but NOT
--   zero or negative (BACKLOG §7.14). Unguarded, a poisoned 0 raises `division by
--   zero` and a negative silently flips the sign of a net-worth figure.
--
-- ----------------------------------------------------------------------------
-- ⚠ A STRUCTURAL COINCIDENCE IN JANUARY, stated so it is not read as a fault and
--   NOT "FIXED". For the whole of January, prior_month and prior_year_end ARE
--   THE SAME REFERENCE DATE — 31 December of the prior year — because the most
--   recent COMPLETED month-end IS the prior year-end. The two rows then return
--   identical values in EVERY column, by construction.
--   MEASURED, not predicted: scratch DB, run day 2026-01-15, both rows returned
--   reference_date 2025-12-31 with the same checkpoint, nav, cpi_period and flags.
--   THREE CONSEQUENCES, none of them defects:
--     · THE UI RENDERS TWO ROWS WITH THE SAME DATE AND THE SAME FIGURES for one
--       month a year. That is correct — "one month ago" and "the most recent
--       December close" genuinely coincide in January — and it is the consumer's
--       copy, not this function's, that must make it read as intentional.
--     · prior_month IS ALSO EXACT IN JANUARY. Its CPI period is that same
--       December, so its deflator is v/v = 1 as well. >> ANY TEST ASSERTING THAT
--       prior_year_end IS THE ONLY EXACT ROW WILL RED EVERY JANUARY. << The
--       exactness property belongs to "the row whose CPI period is the basis
--       period" — NOT to a particular row.
--       ⚠⚠ AND UNDER REALISTIC CPI ARREARS IT CAN BE ALL THREE. CPI publishes
--       one to two months behind, so on a JANUARY run 066's coverage_through is
--       itself December of the prior year — which makes this_month's CPI period
--       the basis period too. MEASURED (scratch DB, run day 2026-01-15,
--       coverage_through 2025-12-01): all three rows returned cpi_period =
--       cpi_basis_period and nav_prior_yr_dollars = nav EXACTLY.
--       >> SO FOR PART OF JANUARY THE ENTIRE PRIOR-YEAR-DOLLAR COLUMN EQUALS THE
--          NOMINAL COLUMN. That is arithmetically correct — in December-of-last-
--          year dollars, December-of-last-year figures are themselves — and it is
--          a RENDERING consequence the consumer must not present as an error or
--          as a data problem. <<
--       ⚠ A FIXTURE THAT PINS CPI COVERAGE TO THE CURRENT MONTH CANNOT SEE THIS,
--       because it removes the arrears that cause it. Arrears is the production
--       case, not the exceptional one.
--     · A PER-ROW INSUFFICIENT-HISTORY CASE CANNOT BE CONSTRUCTED BETWEEN THOSE
--       TWO ROWS IN JANUARY: identical reference dates resolve identically, so no
--       checkpoint can serve one and not the other. A battery leg proving the
--       per-row predicate must use this_month against the other two, or accept
--       that the prior_month/prior_year_end pairing is unprovable for one month
--       a year. ⚠ A fixture that derives its floor checkpoint from `base` minus a
--       fixed offset is run-day-dependent for the same reason — measured across
--       twelve run months, a `base - 4 months` floor lands at-or-before the prior
--       year-end for every run day from JANUARY THROUGH MAY.
--
-- ----------------------------------------------------------------------------
-- WHY THE LEVELS ARE READ DIRECTLY AND NOT COMPOSED.
--   · 072 CANNOT be composed, and this is structural rather than a preference:
--     IT RETURNS NO NAV LEVEL AT ALL, by design — that property is why its
--     real-terms percent had to be computed there instead of derived by
--     consumers. This surface needs levels; the delta surface cannot supply them.
--   · 062 / 067 answer "a bucketed series over a range"; this needs "the NAV as
--     of three specific dates". Composing would mean reasoning AROUND period-end
--     bucketing and two-sided clamping at every reference. >> BORROWING A
--     FUNCTION WHOSE SEMANTICS YOU MUST THEN WORK AROUND IS A WORSE DEPENDENCY
--     THAN NOT BORROWING IT. << What is reused is 062's IDIOM — the at-or-before
--     LOCF lateral — not its function. No valuation function is reached, so 062's
--     NO-RECOMPUTE fence is not crossed.
--   ⚠ THE COST, STATED BECAUSE IT IS REAL AND WAS ACCEPTED KNOWINGLY: this is the
--   THIRD embedding of the at-or-before LOCF idiom (062 -> 071/072 -> here). If
--   the idiom is ever wrong it is wrong in three places. Extracting a shared
--   point-read helper was considered and REJECTED for V1 — it would insert a new
--   function into the read path of two already-shipped surfaces for no
--   behavioural gain.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; the catalogued
--   numbered list is NOT restated and no count is stated. Decision 4 read
--   VERBATIM at the canonical anchor before drafting, 2026-08-14, at 4270495.)
--   (i)   Instance-numbering: nothing appended, reordered, or renumbered.
--   (ii)  Layer-attribution: an INVOKER read helper reached by `authenticated`
--         over PostgREST. NOT the PDF-worker container credential audit, NOT the
--         code-layer SUPABASE_SERVICE_ROLE_KEY allowlist fence, NOT the
--         app->worker credential-admission network surface. No catalogued
--         instance's layer attribution moves; no surface becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is REFERENCED, not restated.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED set are DIFFERENT SETS and are
--   NOT reconciled here.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — +0. No table, no column, no
--   FK-shaped reference of any kind. AUTHORING-TIME PROVENANCE (dated, not live
--   state — read Decision 3's body live; it grows and its labels are
--   non-contiguous): read verbatim at the canonical anchor on 2026-08-14 at
--   4270495, the family stood at SIXTEEN LABELED INSTANCES (#1-#16), THIRTEEN
--   DDL-REALIZED. Recorded as a dated observation ONLY.
--
-- ----------------------------------------------------------------------------
-- LEDGER DELTAS (all FLAT): §10 catalogued +0 · SECURITY DEFINER allowlist +0 ·
--   Decision 3 family +0 · SD matrix NO expansion · RLS unchanged · triggers
--   unchanged · grants on existing objects unchanged. The grant below is on a
--   NEW object: EXECUTE revoked from PUBLIC, granted to `authenticated`, NOT to
--   service_role (the 069 precedent, identical to 071/072). Sec joint-review
--   MANDATORY: financial calculation on a multi-tenant read path.
--
-- ----------------------------------------------------------------------------
-- QA TEST-PAIRING (QA-owned). Ships SAME-PR.
--   1. ⭐ THE PRIOR-YEAR-END EXACTNESS LEG. nav_prior_yr_dollars = nav on that
--      row, and cpi_period = cpi_basis_period as the provenance form of the same
--      invariant. ⚠ ASSERT WITH NUMERIC `=`, NEVER A TEXT OR DISPLAY COMPARISON:
--      nav x (v/v) renders with trailing zeros and is textually different while
--      being numerically equal. ⚠ SCOPE THE LEG to a fixture where
--      cpi_unavailable is false — the equality is FALSE on the unresolvable row,
--      and that scope is load-bearing, not tidiable.
--   2. ⭐ THE ARITHMETIC on this_month and prior_month, independently computed,
--      ASSERTED WITH cpi_basis <> cpi_at_reference so the deflation is actually
--      exercised. An equal-CPI fixture cannot distinguish a real deflation from
--      returning the nominal figure unchanged.
--   3. THE TWO-PANEL RECONCILIATION, which is the reason the anchors were chosen:
--      on a fixture with BOTH functions callable, assert
--        (this_month nav) - (prior_month nav)    = 072's 'month' delta_nominal
--        (this_month nav) - (prior_year_end nav) = 072's 'ytd'   delta_nominal
--      ⚠ THE FIXTURE MUST GIVE this_month AND prior_month DIFFERENT CHECKPOINTS.
--      If the latest checkpoint IS the month-end, the two rows coincide and the
--      leg passes without exercising anything.
--   4. THREE ROWS ALWAYS, fixed order, including a tenant with zero checkpoints.
--   5. THE TWO NULL CAUSES ARE DISTINGUISHABLE, asserted on the FULL row:
--      insufficient history (reference_date present, reference_checkpoint_date
--      NULL, both value columns NULL) and CPI unresolvable (cpi_unavailable true
--      WITH nav present). ⚠ Prove insufficient history ON THE prior_year_end ROW
--      specifically — the per-row predicate means a tenant can have enough history
--      for this_month and not for prior_year_end, which is the case the UI's
--      "Insufficient history" string exists for.
--   6. cpi_basis_period is NON-NULL AND IDENTICAL on all three rows even when
--      cpi_unavailable is true — it is a calendar label, not an observation.
--   7. cpi_any_carried ORs BOTH legs: a fixture where only the basis leg is
--      carried must still return true.
--   8. ZERO / NEGATIVE CPI yields NULL, never `division by zero` and never a
--      sign-flipped figure. See the strictly-positive guard.
--   9. TWO-TENANT, NON-VACUOUSLY: identical dates, DIFFERENT nav_values; A's call
--      returns A's levels. A same-value fixture passes under a broken predicate.
--  10. CROSS-TENANT: three all-NULL rows, not an error, not the other tenant's.
--  11. AAL2 BACKSTOP, BOTH LEGS — aal1 gets all-NULL, aal2 gets real levels. The
--      negative alone passes vacuously on an empty fixture.
--  12. PST1-SHAPE POSTURE LEG: prosecdef false, provolatile 's', proconfig pins
--      search_path empty. Behaviour cannot distinguish INVOKER from DEFINER; only
--      the catalog can.
--  13. ACL: EXECUTE revoked from PUBLIC, granted to `authenticated`, NOT held by
--      service_role, and NOT held by `anon` (the 064 idiom). Assert on proacl.
--  14. ⚠ SEC'S FULL-STATE-TUPLE CRITERION: assert the WHOLE returned tuple, not
--      only the field under test, so a neighbouring field silently changing is
--      caught.
--   ⚠ Determinism without a p_as_of parameter — the 071 argument applies
--   unchanged: `current_date` is transaction-stable and 070 is STABLE, so inside
--   one rolled-back test transaction "today" cannot move; and this function
--   RETURNS the reference dates and checkpoints it used, so the arithmetic legs
--   can read the fixture by the dates the function REPORTS. Derive expected
--   reference dates by DIFFERENT arithmetic than the body uses — computing them
--   with the body's own expression tests the implementation against itself.
--   ⚠ `supabase db reset` is PROHIBITED — it destroys F/CTO's local test data.
--   Verify non-destructively on a hand-built scratch DB (createdb + psql -f).
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- pfin.fn_nav_reference_dates — three fixed reference dates, each in nominal and
-- prior-year-end dollars. See the header for the full contract; inline notes
-- cover only what is not obvious from the code.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_nav_reference_dates()
returns table (
  reference                  text,
  reference_date             date,
  reference_checkpoint_date  date,
  nav                        numeric,
  nav_prior_yr_dollars       numeric,
  cpi_period                 date,
  cpi_basis_period           date,
  cpi_any_carried            boolean,
  cpi_unavailable            boolean
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
-- Output names collide with column names on the relations read below. Every
-- reference is table-qualified and this directive makes the resolution explicit:
-- an ambiguous bare name resolves to the COLUMN, never the output variable.
#variable_conflict use_column
declare
  v_today      date;      -- 070's answer; the ONLY clock read in this function
  v_base       date;      -- month-end at-or-before today (the last month close)
  v_ye_period  date;      -- 1 December of the prior year — the CPI basis PERIOD
  v_ye_date    date;      -- 31 December of the prior year — the reference DATE
  v_coverage   date;      -- 066's coverage_through: the "now" CPI observation
  v_cpi_ye     numeric;   -- basis CPI value
  v_cpi_ye_c   boolean;   -- basis CPI was carried
  r            record;    -- per-reference row
  v_nav        numeric;
  v_cp         date;
  v_cpi_r      numeric;   -- this row's own reference-date CPI
  v_cpi_r_c    boolean;
  v_real       numeric;
  v_unavail    boolean;
  v_carried    boolean;
begin
  -- ONE clock read, via 070, so both sides of every comparison below use the
  -- same day (ADR-044 R2). Everything downstream is date arithmetic on a `date`
  -- and is therefore zone-free.
  v_today := pfin.fn_server_today();

  -- The most recent COMPLETED month-end — the SAME expression 072 uses for its
  -- `month` anchor. `::timestamp` is zone-free (WITHOUT time zone), the 062
  -- idiom. If today IS a month-end it is its own base.
  v_base := case
              when v_today = (date_trunc('month', v_today::timestamp)
                              + '1 mon'::interval - '1 day'::interval)::date
                then v_today
              else (date_trunc('month', v_today::timestamp) - '1 day'::interval)::date
            end;

  -- Basis PERIOD (1 December, prior year) and prior-year-end reference DATE (31
  -- December, prior year). Both are pure calendar arithmetic — no 066 call — so
  -- carry-forward can move the VALUE served for the period but never the period
  -- itself. v_ye_period matches 072's basis expression exactly.
  v_ye_period := (date_trunc('year', v_today::timestamp) - '1 year'::interval
                  + '11 mon'::interval)::date;
  v_ye_date   := (date_trunc('year', v_today::timestamp) - '1 day'::interval)::date;

  -- coverage_through is a property of the STORE, so any non-NULL argument yields
  -- it; the CPI-U epoch is a fixed, never-NULL, zone-free probe (the 067 idiom).
  select h.coverage_through into v_coverage
  from pfin.fn_cpi_u_index_for_period(date '1913-01-01') h;

  -- The basis leg, read ONCE for the whole table.
  select h.cpi_value, h.is_carried into v_cpi_ye, v_cpi_ye_c
  from pfin.fn_cpi_u_index_for_period(v_ye_period) h;

  for r in
    -- Fixed order. The CPI period per row: "now" for this_month (066's
    -- coverage_through — the same observation 067/072 call now), and the
    -- first-of-month of the CALENDAR reference for the other two. Note that
    -- prior_year_end's calendar reference month IS the basis period, which is
    -- what makes that row's deflator exactly 1 — it falls out of the pinning
    -- rule and is NOT special-cased here.
    select * from (values
      ('this_month'::text,     v_today,   v_coverage),
      ('prior_month'::text,    v_base,    date_trunc('month', v_base::timestamp)::date),
      ('prior_year_end'::text, v_ye_date, v_ye_period)
    ) as t(name, ref_date, cpi_per)
  loop
    -- The level at this reference date by at-or-before carry-forward (the 062
    -- idiom). No row = no observation reaches this reference date: insufficient
    -- history, reported as NULLs rather than computed against the earliest
    -- available checkpoint.
    select nd.nav_value, nd.nav_date into v_nav, v_cp
    from pfin.nav_daily nd
    where nd.nav_date <= r.ref_date
    order by nd.nav_date desc
    limit 1;

    -- Reset every per-row carrier: these are function-scoped variables in a
    -- loop, so a value left behind would be attributed to the next reference.
    v_cpi_r := null; v_cpi_r_c := null; v_real := null;

    -- CPI pinned to the CALENDAR reference, never to the serving checkpoint —
    -- this is what keeps the basis reference from drifting when carry-forward
    -- reaches back (see the header). A NULL period means 066 has no coverage at
    -- all, which resolves to unavailable below rather than to an error.
    if r.cpi_per is not null then
      select h.cpi_value, h.is_carried into v_cpi_r, v_cpi_r_c
      from pfin.fn_cpi_u_index_for_period(r.cpi_per) h;
    end if;

    -- Strictly positive on BOTH legs: 053 bars NaN/+-Infinity but not zero or
    -- negative, so this is the only thing standing between a poisoned print and
    -- either a raise or a sign-flipped net-worth figure.
    v_unavail := not (v_cpi_ye is not null and v_cpi_ye > 0
                  and v_cpi_r  is not null and v_cpi_r  > 0);

    -- An OR over THIS ROW'S TWO LEGS — basis and reference. Never NULL: every
    -- row of this surface is CPI-eligible, so there is no not-applicable case.
    v_carried := coalesce(v_cpi_ye_c, false) or coalesce(v_cpi_r_c, false);

    if not v_unavail and v_nav is not null then
      -- Level deflation into prior-year-end dollars — the 067 / 072 shape. On
      -- the prior_year_end row both legs are the SAME request to 066, so this
      -- is nav x (v/v) = nav exactly. Do NOT "simplify" the three rows onto a
      -- single coverage_through observation: that is correct only for
      -- this_month, and it would silently destroy that exactness.
      v_real := v_nav * (v_cpi_ye / v_cpi_r);
    end if;

    return query select
      r.name,
      r.ref_date,
      v_cp,
      v_nav,
      v_real,
      r.cpi_per,
      v_ye_period,   -- calendar-derived; identical on all rows, never NULL
      v_carried,
      v_unavail;
  end loop;
end;
$$;

revoke execute on function pfin.fn_nav_reference_dates() from public;
grant  execute on function pfin.fn_nav_reference_dates() to authenticated;

comment on function pfin.fn_nav_reference_dates() is
  'SECURITY INVOKER §2.1.4 NAV-at-three-reference-dates backend (V1.1; PRD §2.1.4; ADR-011 Lock 11 '
  'read-composition). Returns EXACTLY THREE ROWS, ALWAYS, in fixed order this_month/prior_month/prior_year_end — a '
  'reference is never absent; an uncomputable one returns NULL values, because "the query dropped it" and "it is not '
  'computable" must not render identically. No parameters: tenant derives from session RLS. STABLE, set search_path '
  '= ''''. READS pfin.nav_daily (054) DIRECTLY by at-or-before carry-forward — the 062 IDIOM, not the 062 function, '
  'because 062 answers "a bucketed series over a range" and this needs "the NAV as of three specific dates". No '
  'valuation function is reached. Today comes from pfin.fn_server_today (070, ADR-044 R2), never current_date. '
  '⭐ THIS IS THE LEVELS VIEW OF THE ANCHORS pfin.fn_nav_delta_panel SHOWS AS DELTAS: this_month is that function''s '
  'current endpoint, prior_month its month anchor, prior_year_end its ytd anchor — the SAME expressions, not merely '
  'similar ones, because PRD Appendix C renders the two surfaces adjacent and a reader subtracting two cells here '
  'must land exactly on a figure there. "Prior Month" means THE MOST RECENT COMPLETED MONTH-END (F/CTO-ratified '
  '2026-08-14); the competing reading lands up to six weeks back and would break that reconciliation. '
  'FORMULA: nav_prior_yr_dollars = nav x (cpi_basis / cpi_at_reference_date) — level deflation, the 067 shape. CPI '
  'LEGS, all via pfin.fn_cpi_u_index_for_period (066) and never re-derived inline: basis = DECEMBER of the prior '
  'calendar year; this_month = the print at 066''s coverage_through (the same observation 067 uses, so chart, delta '
  'panel and this table cannot disagree about now); the other two = first-of-month of their CALENDAR reference. '
  '⚠ Pinning to the calendar reference rather than to the serving checkpoint is what stops the basis drifting when '
  'carry-forward reaches back. Both legs are guarded STRICTLY POSITIVE: 053 bars NaN and the infinities but NOT zero '
  'or negative, so unguarded a poisoned print would raise or silently flip a sign. '
  '⭐ THE prior_year_end ROW IS EXACT BY CONSTRUCTION AND THAT IS A FENCE: its CPI period IS the basis period, so '
  'both legs are the SAME REQUEST to a STABLE function in one snapshot, the ratio is v/v = 1, and '
  'nav_prior_yr_dollars EQUALS nav with no residue. The carried case is safe — in January and February the December '
  'print does not exist yet and 066 serves it carried, table-wide, which is correct and correctly signalled, and the '
  'same carried value sits in numerator and denominator. ⚠ THE EQUALITY IS SCOPED TO cpi_unavailable = false and is '
  'FALSE without that scope, because an unresolvable CPI leaves nav present and nav_prior_yr_dollars NULL. The proof '
  'fails only if the two legs stop being the same request — which is what "simplifying" all three rows onto '
  'coverage_through would do, so do not. '
  '⚠ EXACTNESS BELONGS TO "THE ROW WHOSE CPI PERIOD IS THE BASIS PERIOD", NOT TO A PARTICULAR ROW, and in January '
  'that can be MORE THAN ONE. In January the most recent completed month-end IS the prior year-end, so prior_month '
  'and prior_year_end are THE SAME REFERENCE DATE and return identical values in every column; and because CPI '
  'publishes one to two months in arrears, a January coverage_through is itself December of the prior year, which '
  'makes this_month''s CPI period the basis period too — so for part of January ALL THREE ROWS are exact and the '
  'entire prior-year-dollar column equals the nominal column. Measured, run day 2026-01-15. That is arithmetically '
  'correct (in last-December dollars, last-December figures are themselves) and it is a RENDERING consequence: a '
  'consumer must not present duplicate rows or duplicate columns as an error or as missing data, and a test '
  'asserting prior_year_end is the ONLY exact row will red every January. '
  'TWO NULL CAUSES, NOT THREE — the delta panel has a third (not-applicable) because its month and ytd rows carry no '
  'real-terms figure; EVERY row here is CPI-eligible, so that cause does not exist and the cpi_* columns are never '
  'all-NULL. INSUFFICIENT HISTORY = reference_date present with reference_checkpoint_date NULL, both value columns '
  'NULL (the row a UI renders as "Insufficient history"). CPI UNRESOLVABLE = cpi_unavailable true WITH nav still '
  'present. The history predicate is PER ROW — the earliest checkpoint is at-or-before THAT row''s reference_date — '
  'not a global one-year rule: in December the prior year-end is twelve months back, in January about one. '
  'cpi_any_carried ORs THIS ROW''S TWO LEGS, the basis leg and the reference leg; it is not a synonym for "the CPI '
  'was carried". cpi_basis_period is CALENDAR-DERIVED, never an observation — carrying changes which observation '
  'supplies a value for a period, never the period label — so it is identical on all three rows and NON-NULL even '
  'when cpi_unavailable is true, letting a consumer render the basis in a column header over a blank cell. ⚠ That '
  '"identical" is a WITHIN-ONE-CALL claim: two sessions in different zones straddling 31 December can derive basis '
  'periods a full year apart, the residual ADR-044 R2 does not close. NO ROUNDING IS APPLIED; numeric division '
  'residue means assertions need a tolerance, except on the exact prior_year_end row. '
  'TENANT FENCE: RLS on nav_daily is the SOLE mechanism — no users_id predicate of its own and it MUST NOT GAIN ONE; '
  'QA measured on 062 that a redundant local predicate keeps the cross-tenant battery green over a policy broken '
  'open. Cross-tenant callers get three all-NULL rows and fail closed; the 025 aal2 backstop is inherited through '
  'that same policy. The CPI legs cross no tenant boundary. p_users_id was struck on the grounds recorded in the '
  'fn_nav_delta_panel migration header, which enumerates the family; p_scope was struck because pfin.scope DOES NOT '
  'EXIST. SECURITY INVOKER — NOT a DEFINER allowlist entry; read ADR-011 Decision 9 live. §10 catalogued ledger '
  'UNCHANGED BY THIS OBJECT and NO COUNT IS STATED HERE. Read ADR-011 Decision 4 live. Decision-3 unchanged. EXECUTE '
  'revoked from PUBLIC, granted to authenticated, not to service_role and not to anon. Sec joint-review-mandatory '
  '(financial calculation + multi-tenant read path).';

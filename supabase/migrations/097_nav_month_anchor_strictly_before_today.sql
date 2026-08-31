-- ============================================================================
-- Migration: the MONTH ANCHOR becomes the month-end STRICTLY BEFORE today, in
--   BOTH pfin.fn_nav_delta_panel (live text issued by 072, not 071) and
--   pfin.fn_nav_reference_dates (073). Two SECURITY INVOKER read-composition
--   functions (Lock 11), re-issued by `create or replace` with NO shape change.
--   Linear SELF-344. F/CTO-ratified 2026-08-30 (SELF-344 sitting), amending the
--   2026-08-14 ruling: 'completed' means completed BEFORE today.
--   apply-migration procedure applied. JOINT-REVIEW-MANDATORY (Sec veto
--   surface): financial calculation + multi-tenant read path, on both objects.
--
-- ----------------------------------------------------------------------------
-- ⚠ THE DEFECT. It was LATENT FROM AUTHORING AND FIRED ON A WALL-CLOCK
--   COINCIDENCE — 2026-08-31 — which is the reason it is written up at this
--   length rather than fixed quietly.
--   `v_base` carried a CASE whose true-branch made TODAY ITS OWN BASE when today
--   IS a month-end, and the `month` horizon anchored on `v_base`. The current
--   endpoint and every anchor endpoint resolve through the IDENTICAL at-or-before
--   LOCF query over pfin.nav_daily. So when v_base = today the two predicates are
--   not merely similar, they are the SAME PREDICATE — one row, served twice.
--       delta_nominal  = 0   (not NULL)
--       delta_percent  = 0   (not NULL)
--   for EVERY tenant, on EVERY month-end day: all twelve of them a year. The
--   panel read "Month: $0" all day on each month's closing day.
--   >> AND 0 IS THE ONE VALUE THIS CONTRACT SAYS IT MUST NOT BE. The ratified
--      shape holds that "no change" and "cannot be expressed" must never render
--      alike; a tenant whose only checkpoint IS the month-end has no month-ago
--      observation at all, and was shown a confident $0 where the contract owes
--      an INSUFFICIENT-HISTORY row. The defect did not merely report a wrong
--      number — it reported it in the register reserved for a true one. <<
--
--   ⚠ 073 CARRIED THE SAME CASE AND THE SAME DEFECT, and that half was NOT in
--   the original diagnosis. 073 re-derived `v_base` with a byte-identical
--   expression and bound `prior_month` to it, so on the same twelve days
--   `this_month` and `prior_month` resolved to the same checkpoint and the levels
--   table showed TWO IDENTICAL NAV ROWS. 073's own header is what makes this
--   non-optional: it states that its derivations "are the SAME EXPRESSIONS 072
--   USES, NOT MERELY SIMILAR ONES. If you change one, the two panels disagree on
--   screen and the surface that looks broken will be whichever one the reader
--   checked second." Fixing one function alone would have satisfied the bug
--   report and broken the reconciliation. Both are re-issued here, same PR.
--
-- ----------------------------------------------------------------------------
-- WHAT CHANGES, AND WHAT DELIBERATELY DOES NOT.
--   CHANGES — exactly one derived date per function:
--     fn_nav_delta_panel    : the 'month' horizon's anchor is now the month-end
--                             STRICTLY BEFORE today, written inline exactly as
--                             the neighbouring 'ytd' anchor already is.
--     fn_nav_reference_dates: `prior_month` is the same date, and its CPI period
--                             follows it (first-of-month of the NEW anchor).
--   DOES NOT CHANGE — return shape, column names, column order, types, posture
--   (INVOKER), volatility (STABLE), search_path, parameter list (still empty),
--   tenant fence, CPI composition, the deflation arithmetic, the NULL-cause
--   discrimination, or the EXECUTE ACL. Every other expression is carried
--   forward from the live text unaltered.
--
--   ⚠ `v_base` IS UNTOUCHED AND ITS CASE IS STILL LOAD-BEARING — for 1y/3y/5y
--   ONLY. This is the trap in the obvious fix, so it is recorded rather than
--   left to be rediscovered. Making `v_base` itself strictly-before would move
--   the 1-Year anchor on those same twelve days:
--       today 2026-08-31 -> v_base 2026-07-31 -> 1y anchor 2025-07-31
--   which is THIRTEEN MONTHS back, on a row labelled "1-Year". The global fix
--   repairs one horizon by breaking three. The 'month' horizon was the only
--   degenerate one because it was the only horizon stepping back ZERO months
--   from base; every other horizon steps back 12/36/60 and cannot collide with
--   the current endpoint by construction.
--
-- ----------------------------------------------------------------------------
-- ⚠ WHY THIS IS `create or replace` AND NOT DROP + CREATE — and what that does
--   and does not preserve. 072 is DROP + CREATE because it ADDED an output
--   column, and PostgreSQL treats the RETURNS TABLE list as the result type.
--   THIS migration changes no column, so `create or replace` is accepted, and it
--   is the correct vehicle for three reasons, each of which is a hazard avoided:
--     (i)   THE OID SURVIVES. A DROP + CREATE mints a new OID, which silently
--           invalidates every `regprocedure`-shaped catalog assertion in OTHER
--           files that pins this function. Replacing in place breaks none.
--     (ii)  GRANTS SURVIVE. 072's header records that its DROP destroyed them
--           and that its `revoke` + `grant` pair was therefore load-bearing.
--           ⚠ THAT REASONING DOES NOT TRANSFER: `create or replace` preserves
--           the ACL, so the pair below is NOT repairing a widening. It is
--           re-issued as an idempotent restatement so the ACL is asserted at
--           this file rather than inferred from two files back — and so that a
--           later reader who converts this to DROP + CREATE does not have to
--           notice the difference. Stated because "carried decoration" and
--           "load-bearing" look identical in the diff.
--     (iii) THE COMMENT SURVIVES — WHICH IS THE PROBLEM, NOT THE RELIEF.
--           `create or replace` leaves the OLD catalog comment in place, and
--           both old comments describe the SUPERSEDED anchor. 072's says
--           "month = base"; 073's says '"Prior Month" means THE MOST RECENT
--           COMPLETED MONTH-END (F/CTO-ratified 2026-08-14)'. Left alone, this
--           migration would correct the arithmetic and leave the catalog
--           asserting the arithmetic it just removed, to a reader at \d+ with
--           no repo in front of them. BOTH comments are re-issued in full below.
--
-- ----------------------------------------------------------------------------
-- ⚠ THE RULING THIS AMENDS, AND HOW FAR IT REOPENS — stated at length because
--   the ratified text lives in TWO PLACES AT TWO DIFFERENT STATUSES, and the
--   weaker copy is the one a reader meets first.
--     071's header calls the anchor "A PRODUCT CALL IMPLEMENTED AS A DEFAULT,
--       NOT AN ARCHITECTURAL RULING ... a body change with no contract impact."
--     073's header calls the SAME question "GENUINELY AMBIGUOUS AND ... NOW
--       RULED ... THE MOST RECENT COMPLETED MONTH-END ... F/CTO-ratified
--       2026-08-14."
--   The ratified text is 073's. Anyone sizing this change from 071's copy would
--   conclude nothing ratified was being touched, and would be wrong.
--
--   >> THE AMENDMENT IS A BOUNDARY CLARIFICATION, NOT A REVERSAL. "The most
--      recent COMPLETED month-end" is kept verbatim as the rule; what is fixed
--      is that the superseded code treated the CURRENT day's month-end as
--      already completed. August does not complete until the end of 31 August.
--      F/CTO-ratified 2026-08-30 (SELF-344 sitting), amending the 2026-08-14
--      ruling: 'completed' means completed BEFORE today. <<
--
--   ⚠ AND THE COMPETING READING 071 REJECTED IS *NOT* REOPENED — check this
--   rather than take it, because it looks like it should be. 071 rejected
--   "month-end at-or-before (today - 1 month)" on the ground that it "puts the
--   Month anchor up to six weeks back, which is not what 'one month ago'
--   conveys." Evaluate that rejected reading ON A MONTH-END:
--       today 2026-08-31 -> today - 1 month = 2026-07-31
--                        -> month-end at-or-before that = 2026-07-31
--   which is exactly what this migration produces, exactly 31 days back, with
--   ZERO excess. The two readings COINCIDE on precisely the twelve days where
--   the old rule was degenerate, and DIVERGE on the other ~353, where this
--   migration keeps the current answer and the rejected reading does not
--   (2026-08-15 -> here 2026-07-31; rejected reading 2026-06-30, the six weeks).
--   >> So the rejected reading's ANSWER is adopted only where its stated COST is
--      nil, and its rejection stands intact everywhere the cost is real. A
--      rejection is a judgement about a cost; where the cost measurably vanishes
--      at a boundary, the rejection does not reach that boundary. <<
--
-- ----------------------------------------------------------------------------
-- ⚠ TWO COINCIDENCES THIS RULE CREATES, NAMED SO NEITHER IS LATER READ AS A
--   REGRESSION. Both are consequences of the anchor being correct, not faults.
--   (1) IN JANUARY, 'month' AND 'ytd' NOW NAME THE SAME ANCHOR FOR THE WHOLE
--       MONTH. On any January day the month-end strictly before today is 31
--       December of the prior year, which is also the ytd anchor. This was
--       already true 1-30 January under the old rule and false ONLY on 31
--       January; the change makes January internally uniform rather than
--       introducing something new. The same holds for 073's `prior_month` and
--       `prior_year_end`.
--       ⚠ CONSEQUENTLY 073's CATALOG COMMENT BECOMES TRUE WHERE IT WAS NOT.
--       It already asserted, unconditionally of the day, that "In January the
--       most recent completed month-end IS the prior year-end, so prior_month
--       and prior_year_end are THE SAME REFERENCE DATE" — which the superseded
--       code made FALSE on 31 January. The sentence is carried forward unchanged
--       and is now true for every January day. A latent inaccuracy closed by the
--       fix rather than by an edit; recorded because a reviewer diffing the two
--       comments will see that sentence unchanged and should know it was checked.
--   (2) A GENUINE ZERO IS STILL POSSIBLE AND IS NOT THIS DEFECT RETURNING. If a
--       tenant has posted no checkpoint since the month close, the current
--       endpoint and the month anchor legitimately resolve to the same carried
--       observation and the delta is 0 because NOTHING CHANGED. That zero is a
--       fact about the data; the one removed here was a fact about the code.
--       A tenant with NO observation at or before the new anchor now correctly
--       returns anchor_checkpoint_date NULL and NULL deltas — the
--       INSUFFICIENT-HISTORY cause the contract already defines, which the
--       defect was overwriting with 0.
--
-- ----------------------------------------------------------------------------
-- ⚠ WHY THIS STAYED LATENT FOR EIGHTEEN DAYS, recorded because the cause is
--   reusable and the fix does not address it. The 071 battery pins its expected
--   `:base` with a VERBATIM COPY of the body's CASE expression. 071's own header
--   forbids exactly that, in rule (c): "Do NOT compute the expected anchor with
--   the body's own expression — a shared mistake in month-end derivation would
--   then be invisible, which is testing the implementation against itself."
--   Fixture and body agreed BY CONSTRUCTION, so no leg could fail, and the suite
--   was green every day including the days it was wrong. >> A DEFECT COPIED INTO
--   ITS OWN ORACLE IS NOT UNDER TEST. << Re-deriving that pin by an independent
--   route is QA's, in the paired battery work, and is a larger job than this
--   migration; it is named here so the migration is not mistaken for the whole
--   remedy.
--
-- ----------------------------------------------------------------------------
-- Numbering: 097, taken at authoring time against the tree and NOT reserved
--   ahead. `git ls-tree origin/main supabase/migrations/` ends at 095, so 096 is
--   free ON MAIN — but 096 is ALREADY ALLOCATED on the unmerged
--   feature/self-255 (096_fn_historical_expenditures.sql, verified by ls-tree on
--   that branch, not by a local directory listing). Taking 096 here would
--   collide on merge; 097 is next-free across the branches in flight. Depends on
--   054 (nav_daily — the sole relation read on both functions; its RLS SELECT
--   policy and the inherited 025 aal2 backstop are what fence them), 066 (every
--   CPI observation), 070 (today), and on 072 + 073 having created the objects
--   this replaces. ⚠ ORDER-DEPENDENT, unlike most of this family: `create or
--   replace` requires the function to already exist with a matching signature,
--   so this migration MUST apply after 072 and 073. It creates nothing new.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER on both objects (Lock 11 read-composition
--   default); NOT SECURITY DEFINER, and unchanged from 072 / 073. Both run as the
--   caller and inherit their RLS context exactly as 049 / 051 / 062 / 067 / 069
--   do. Every value returned derives from rows the caller may already read.
--   DEFINER would detach the read from the caller's RLS context and from the 025
--   aal2 step-up backstop nav_daily's policy carries, and would break 070's
--   guarantee, whose whole basis is that the function and its caller share a
--   session. ⚠ `security invoker` and `stable` are RESTATED in both bodies
--   below: `create or replace` re-parses the full definition, and an omitted
--   volatility clause would silently default to VOLATILE.
--   THE SECURITY DEFINER ALLOWLIST IS NOT TOUCHED. Read ADR-011 Decision 9 live;
--   no count is restated here.
--
-- ----------------------------------------------------------------------------
-- TENANT FENCE — INHERITED, NOT RESTATED, and UNCHANGED by this migration.
--   Neither function gains a `users_id = auth.uid()` predicate and neither MAY.
--   Isolation comes entirely from nav_daily's `nav_daily_select` policy (054)
--   through the INVOKER posture; the 025 aal2 backstop reaches both surfaces
--   through that same policy. QA MEASURED on 062 that a redundant local predicate
--   keeps the cross-tenant battery GREEN over a policy broken open with
--   `using (true)` — so the omission is load-bearing, not tidy. A cross-tenant
--   caller sees no rows and gets all-NULL rows: fails closed. The CPI legs cross
--   no tenant boundary (066 reads global `using (true)` reference tables).
--   ⚠ THE ANCHOR IS A CALENDAR DERIVATION, NOT A READ. Moving it changes WHICH
--   date the LOCF predicate is evaluated at; it does not change WHOSE rows that
--   predicate can see. No isolation surface moves in this migration.
--
-- ----------------------------------------------------------------------------
-- CONTRACT — UNCHANGED. Both signatures, both return shapes, and every
--   column's meaning are exactly as 072 and 073 state them, and those blocks are
--   NOT restated here (Path B: this file is not their canonical anchor). The one
--   contract-adjacent sentence that moves is the anchor definition, and its
--   canonical home is ADR-065 — the first DECISIONS.md home this rule has had.
--   The rule, stated as a PROPERTY so it does not depend on that document being
--   in front of the reader: the 'month' / `prior_month` anchor is the LAST
--   MONTH-END STRICTLY BEFORE TODAY; the 1y/3y/5y anchors are the month-end
--   AT-OR-BEFORE today minus 12/36/60 months; ytd / `prior_year_end` is 31
--   December of the prior calendar year.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; the catalogued
--   numbered list is NOT restated and no count is stated. Decision 4 read
--   VERBATIM at the canonical anchor before drafting, 2026-08-30, at 65e0a33.)
--   (i)   Instance-numbering: nothing appended, reordered, or renumbered.
--   (ii)  Layer-attribution: two INVOKER read helpers reached by `authenticated`
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
--   FK-shaped reference of any kind is created, altered or dropped; this
--   migration authors no DDL beyond replacing two function bodies. Read
--   Decision 3's body live — it grows and its labels are non-contiguous. No
--   authoring-time tally is recorded here, because none is needed: a migration
--   that adds no column cannot join the family.
--
-- ----------------------------------------------------------------------------
-- LEDGER DELTAS (all FLAT): §10 catalogued +0 · SECURITY DEFINER allowlist +0 ·
--   Decision 3 family +0 · SD matrix NO expansion · RLS unchanged · policies
--   unchanged · triggers unchanged · grants unchanged (see (ii) above — the ACL
--   pair is a restatement, not a change). Sec joint-review MANDATORY: a
--   financial calculation on a multi-tenant read path changes its arithmetic.
--
-- ----------------------------------------------------------------------------
-- QA TEST-PAIRING (QA-owned). Ships SAME-PR. The batteries for 071 and 073 are
--   RED on main today and this migration is what makes them addressable; the
--   fixture work is NOT done here.
--   1. ⭐ THE CRUX LEG — RE-DERIVE `:base` BY AN INDEPENDENT ROUTE. The existing
--      pin copies the body's expression verbatim and is why this was latent; a
--      fix that leaves the copy in place leaves the surface untested against the
--      next month-end derivation mistake. This is the leg that matters most and
--      it is the one the old suite did not have.
--   2. THE DEGENERATE DAY, ASSERTED POSITIVELY: on a month-end, `month`'s
--      anchor_date is the PRIOR month-end and delta_nominal is NOT 0 over a
--      fixture whose two endpoints differ. ⚠ A fixture whose month-ago and
--      current values COINCIDE cannot distinguish the fix from the defect —
--      the same trap 072 records for equal-CPI fixtures.
--   3. THE HORIZONS THAT MUST NOT MOVE: on that same month-end, 1y/3y/5y anchors
--      are today minus 12/36/60 months exactly. This is the leg that catches the
--      global-`v_base` fix; without it that wrong fix passes.
--   4. 073 RECONCILIATION, CROSS-FUNCTION AND ON A MONTH-END:
--          (this_month nav) - (prior_month nav) = the panel's 'month'
--          delta_nominal, and prior_month <> this_month.
--      Assert it across BOTH functions in one transaction, or the half that
--      drifts is the half nothing watches.
--   5. INSUFFICIENT HISTORY OVER THE NEW ANCHOR: a tenant whose only checkpoint
--      IS the month-end now gets anchor_checkpoint_date NULL and NULL deltas —
--      NOT 0. This is the case the defect was silently answering with a number.
--   6. JANUARY UNIFORMITY: on 31 January, 'month' and 'ytd' name the same anchor,
--      and 073's prior_month and prior_year_end are the same reference date.
--      Previously true on 1-30 January only.
--   7. POSTURE UNMOVED, BOTH FUNCTIONS, AFTER A `create or replace`: prosecdef
--      false, provolatile 's', proconfig pins search_path empty. ⚠ This leg is
--      not ceremony here — an omitted volatility clause in a CoR silently
--      re-creates the function as VOLATILE and no behavioural test would see it.
--   8. ACL UNMOVED, BOTH: EXECUTE revoked from PUBLIC, granted to `authenticated`,
--      NOT held by service_role. Assert on pg_proc.proacl.
--   9. THE CATALOG COMMENTS RENDER CORRECTLY AND NO LONGER CARRY THE SUPERSEDED
--      ANCHOR: read back via obj_description and assert the new anchor sentence
--      is present and the phrase "month = base" is absent.
--   ⚠ `supabase db reset` is PROHIBITED — it destroys F/CTO's local test data.
--   Verify non-destructively (apply-in-txn + rollback, or a scratch database).
--
-- ----------------------------------------------------------------------------
-- COMMENT RE-ISSUE — the 052 shape, applied to BOTH comments. Each was
--   REGENERATED FROM THE LIVE TEXT AND DIFFED, never retyped: these are multi-KB
--   single-quoted literals where a botched edit is a syntax error rather than a
--   wording problem, and retyping is how the correct halves get silently altered
--   alongside the wrong one. Each replacement is ONE CONTIGUOUS SPAN, anchored on
--   a string asserted to match EXACTLY ONCE, with the prefix before it and the
--   suffix after it proven byte-identical to the live text. The proofs are in
--   the PR body; what is recorded here is WHICH CLAIM EACH REPLACES, so a reader
--   who remembers the old text learns it changed rather than doubting their
--   memory:
--     fn_nav_delta_panel     — replaces "base = the month-end at-or-before today;
--       month = base" and the sentence calling the reading "a PRODUCT default
--       ... not an architectural ruling", which is no longer true of it.
--     fn_nav_reference_dates — replaces '"Prior Month" means THE MOST RECENT
--       COMPLETED MONTH-END (F/CTO-ratified 2026-08-14)' with the amended
--       reading, keeping the 2026-08-14 ruling visible as the thing amended.
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- pfin.fn_nav_delta_panel — re-issued in full by `create or replace`. Only the
-- 'month' anchor changes; every other expression is carried from 072's live
-- text unaltered. `security invoker`, `stable` and `set search_path = ''` are
-- restated because CoR re-parses the whole definition and an omitted volatility
-- clause would silently default to VOLATILE.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_nav_delta_panel()
returns table (
  horizon                   text,
  anchor_date               date,
  anchor_checkpoint_date    date,
  current_checkpoint_date   date,
  delta_nominal             numeric,
  delta_percent             numeric,
  delta_inflation_adjusted  numeric,
  delta_inflation_adjusted_percent numeric,
  cpi_basis_period          date,
  cpi_any_carried           boolean,
  cpi_unavailable           boolean
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
  v_today       date;      -- 070's answer; the ONLY clock read in this function
  v_base        date;      -- month-end AT-OR-BEFORE today. The grain anchor for
                           -- 1y/3y/5y ONLY -- NOT the month anchor; see below.
  v_cur_nav     numeric;   -- current endpoint value
  v_cur_cp      date;      -- checkpoint that served the current endpoint
  v_ye_period   date;      -- December of the prior calendar year
  v_cpi_ye      numeric;   -- basis CPI
  v_cpi_ye_c    boolean;   -- basis CPI was carried
  v_cpi_cur     numeric;   -- CPI at coverage_through ("now")
  v_cpi_cur_c   boolean;
  v_coverage    date;
  h             record;    -- per-horizon anchor
  v_a_nav       numeric;
  v_a_cp        date;
  v_cpi_a       numeric;
  v_cpi_a_c     boolean;
  v_real_base   numeric;   -- the anchor endpoint IN PRIOR-YEAR-END DOLLARS;
                           -- bound once and used by BOTH real-terms outputs
  v_adj         numeric;
  v_adj_pct     numeric;
  v_unavail     boolean;
  v_carried     boolean;
begin
  -- ONE clock read, via 070, so both sides of every comparison below use the
  -- same day (ADR-044 R2). Everything downstream is date arithmetic on a `date`
  -- and is therefore zone-free; the residual across containers is in the header.
  v_today := pfin.fn_server_today();

  -- The month-end AT-OR-BEFORE today, today included. `::timestamp` is
  -- zone-free (WITHOUT time zone) — the 062 idiom.
  -- ⚠ THIS FEEDS 1y/3y/5y ONLY. Its true-branch (today IS a month-end -> today
  -- is its own base) is what keeps those three anchors at EXACTLY 12/36/60
  -- months on a month-end day, and it is why this CASE is kept. The `month`
  -- horizon must NOT use it: month = base would then make the anchor and the
  -- current endpoint the same LOCF predicate and force delta 0. See the header.
  v_base := case
              when v_today = (date_trunc('month', v_today::timestamp)
                              + '1 mon'::interval - '1 day'::interval)::date
                then v_today
              else (date_trunc('month', v_today::timestamp) - '1 day'::interval)::date
            end;

  v_ye_period := (date_trunc('year', v_today::timestamp) - '1 year'::interval
                  + '11 mon'::interval)::date;   -- 1 December of the prior year

  -- Current endpoint: the caller's latest checkpoint at-or-before today.
  select nd.nav_value, nd.nav_date into v_cur_nav, v_cur_cp
  from pfin.nav_daily nd
  where nd.nav_date <= v_today
  order by nd.nav_date desc
  limit 1;

  -- Basis and "now" CPI, both through 066. coverage_through is a property of the
  -- STORE, so any non-NULL argument yields it; the CPI-U epoch is a fixed,
  -- never-NULL, zone-free probe (the 067 idiom).
  select h2.coverage_through into v_coverage
  from pfin.fn_cpi_u_index_for_period(date '1913-01-01') h2;

  select h2.cpi_value, h2.is_carried into v_cpi_ye, v_cpi_ye_c
  from pfin.fn_cpi_u_index_for_period(v_ye_period) h2;

  if v_coverage is not null then
    select h2.cpi_value, h2.is_carried into v_cpi_cur, v_cpi_cur_c
    from pfin.fn_cpi_u_index_for_period(v_coverage) h2;
  end if;

  for h in
    -- Fixed order. All anchors are month-ends, so every one lands on the
    -- imported decade's grain (ADR-053 D7). 'adj' marks the horizons that carry
    -- an inflation-adjusted figure at all — month/ytd do not, BY DESIGN.
    -- ⚠ 'month' is the month-end STRICTLY BEFORE today, written INLINE rather
    -- than off v_base — deliberately, and in the same shape as the 'ytd' row
    -- directly below it, which has always been written this way. Off v_base it
    -- degenerates to the current endpoint on a month-end (delta 0 every time);
    -- 1y/3y/5y keep v_base because they need its at-or-before branch. The
    -- expression is the CASE's else-branch, now unconditional.
    select * from (values
      ('month'::text, (date_trunc('month', v_today::timestamp)
                       - '1 day'::interval)::date,                         false),
      ('ytd'::text,   (date_trunc('year', v_today::timestamp)
                       - '1 day'::interval)::date,                          false),
      ('1y'::text,    (v_base::timestamp - '12 mon'::interval)::date,       true),
      ('3y'::text,    (v_base::timestamp - '36 mon'::interval)::date,       true),
      ('5y'::text,    (v_base::timestamp - '60 mon'::interval)::date,       true)
    ) as t(name, anchor, adj)
  loop
    -- Anchor endpoint by at-or-before carry-forward (the 062 idiom). No row =
    -- the anchor predates every observation this caller has: insufficient
    -- history, reported as NULLs rather than computed against the earliest
    -- available checkpoint (which would label a two-month change "1-Year").
    select nd.nav_value, nd.nav_date into v_a_nav, v_a_cp
    from pfin.nav_daily nd
    where nd.nav_date <= h.anchor
    order by nd.nav_date desc
    limit 1;

    -- Reset EVERY per-horizon carrier each iteration — these are function-scoped
    -- variables in a loop, so a value left behind would be attributed to the
    -- next horizon.
    v_adj := null; v_adj_pct := null; v_real_base := null;
    v_unavail := null; v_carried := null;

    if h.adj then
      -- CPI pinned to the CALENDAR anchor month, never to the serving
      -- checkpoint — this is what keeps the basis reference from drifting when
      -- carry-forward reaches back (see the header).
      select h2.cpi_value, h2.is_carried into v_cpi_a, v_cpi_a_c
      from pfin.fn_cpi_u_index_for_period(
             date_trunc('month', h.anchor::timestamp)::date) h2;

      -- Strictly positive on ALL THREE legs: 053 bars NaN/±Infinity but not zero
      -- or negative, so this is the only thing standing between a poisoned print
      -- and either a raise or a sign-flipped net-worth figure.
      v_unavail := not (v_cpi_ye  is not null and v_cpi_ye  > 0
                    and v_cpi_cur is not null and v_cpi_cur > 0
                    and v_cpi_a   is not null and v_cpi_a   > 0);
      v_carried := coalesce(v_cpi_ye_c, false)
                or coalesce(v_cpi_cur_c, false)
                or coalesce(v_cpi_a_c, false);

      if not v_unavail and v_cur_nav is not null and v_a_nav is not null then
        -- THE RATIFIED FORMULA: deflate EACH endpoint into prior-year-end
        -- dollars, then subtract. Do NOT "simplify" this to a single ratio over
        -- the nominal delta — that form never deflates the current endpoint and
        -- is the defect 071 corrected.
        -- The anchor term is BOUND, not re-spelled: it is the dollar delta's
        -- subtrahend AND the percent's denominator, and binding it is what
        -- makes the two columns incapable of disagreeing about the anchor.
        v_real_base := v_a_nav * (v_cpi_ye / v_cpi_a);
        v_adj := v_cur_nav * (v_cpi_ye / v_cpi_cur) - v_real_base;

        -- The percent of the DEFLATED anchor — numerator and denominator both
        -- in prior-year-end dollars. NULL, never 0, on a non-positive base:
        -- same alike-rendering principle as delta_percent, and a negative base
        -- would invert the sign of a real-terms figure. The guard is written on
        -- THE DENOMINATOR ITSELF rather than on v_a_nav, which it is currently
        -- equivalent to under the strictly-positive CPI guard above — so it
        -- stays sound if that guard is ever reshaped.
        if v_real_base > 0 then
          v_adj_pct := v_adj / v_real_base * 100;
        end if;
      end if;
    end if;

    return query select
      h.name,
      h.anchor,
      v_a_cp,
      v_cur_cp,
      case when v_cur_nav is not null and v_a_nav is not null
           then v_cur_nav - v_a_nav end,
      -- NULL, never 0, on a zero, NEGATIVE or absent anchor. A NEGATIVE base
      -- INVERTS THE SIGN — improving from -100 to +100 would report -200%,
      -- a negative percentage for a positive improvement — which is the
      -- alike-rendering the ratified principle bars. Nominal and adjusted are
      -- arithmetically sound over a negative base and are NOT guarded here.
      case when v_cur_nav is not null and v_a_nav is not null and v_a_nav > 0
           then (v_cur_nav - v_a_nav) / v_a_nav * 100 end,
      v_adj,
      v_adj_pct,
      case when h.adj then v_ye_period end,
      v_carried,
      v_unavail;
  end loop;
end;
$$;

-- The ACL is PRESERVED by `create or replace` — unlike 072's DROP + CREATE,
-- where this pair repaired a real widening. Re-issued here as an idempotent
-- restatement so the intended ACL is asserted at this file, not inferred.
revoke execute on function pfin.fn_nav_delta_panel() from public;
grant  execute on function pfin.fn_nav_delta_panel() to authenticated;

-- The catalog comment SURVIVES a `create or replace`, so 072's — which still
-- describes the superseded anchor — must be overwritten explicitly. Regenerated
-- from the live text with one anchored contiguous substitution; not retyped.
comment on function pfin.fn_nav_delta_panel() is
  'SECURITY INVOKER §2.1.3.a multi-horizon NAV-delta backend (V1.1; PRD §2.1.3 / SELF-221; ADR-011 Lock 11 '
  'read-composition). Returns EXACTLY FIVE ROWS, ALWAYS, in fixed order month/ytd/1y/3y/5y — a horizon is never '
  'absent; an uncomputable one returns NULL deltas, because "the query dropped it" and "it is not computable" must not '
  'render identically. No parameters: tenant derives from session RLS. STABLE, set search_path = ''''. '
  'READS pfin.nav_daily (054) DIRECTLY by at-or-before carry-forward — the 062 IDIOM, not the 062 function, because '
  '062 answers "a bucketed series over a range" and this needs "the NAV as of five specific dates". No valuation '
  'function is reached, so no unpriced-asset zero-fabrication path exists here. Today comes from pfin.fn_server_today '
  '(070, ADR-044 R2). '
  '⚠ THE FORMULA, and why the drafted one was a correctness defect: delta_inflation_adjusted = nav_current x '
  '(cpi_ye / cpi_current) MINUS nav_anchor x (cpi_ye / cpi_anchor) — each endpoint deflated into prior-year-end '
  'dollars, THEN differenced; THREE CPI observations, not two. The drafted form scaled the nominal delta by a single '
  'ratio, which never deflates the current endpoint at all and is arithmetically identical to asserting the whole NAV '
  'change happened at the anchor date. Its error scales with TOTAL PORTFOLIO VALUE rather than with the delta, always '
  'overstates under normal inflation, and vanishes only when CPI did not move — precisely when the adjustment was '
  'pointless. STANDING REQUIREMENT: do not "simplify" the expression back to a single ratio. '
  '⚠ THE REAL-TERMS PERCENT (added at 072, the §2.1.3.b AC3 amendment; F/CTO-ratified 2026-08-14). '
  'delta_inflation_adjusted_percent = delta_inflation_adjusted / real_base x 100, where real_base = nav_anchor x '
  '(cpi_ye / cpi_anchor) — the DEFLATED ANCHOR, which is the second term of the dollar formula above. Numerator and '
  'denominator are therefore both in prior-year-end dollars; a ratio between two differently-denominated figures is '
  'not a percentage of anything. The body BINDS real_base once and uses it for both outputs, so the dollar figure and '
  'the percent cannot disagree about what the anchor was worth. It is NOT consumer-derivable, which is checkable from '
  'this signature: NO NAV LEVEL IS RETURNED, so neither base appears in the output, and the available back-derivation '
  '(delta_inflation_adjusted over delta_nominal / delta_percent) reconstructs the NOMINAL anchor and divides a REAL '
  'numerator by it — the mixed-basis defect class described above, reached from the consumer side. NULL WHEREVER '
  'delta_inflation_adjusted is NULL, so no row carries a percent without the figure it derives from — a ONE-WAY '
  'implication and NOT a biconditional: the percent is ADDITIONALLY NULL — never 0 — when real_base is NOT STRICTLY '
  'POSITIVE, and on those rows delta_inflation_adjusted itself STAYS PRESENT and sound. Under the CPI guard that is equivalent to a zero or negative anchor '
  'NAV, but the guard is written on the denominator actually divided by, not on the NAV, so it survives a reshaping of '
  'the CPI guard. '
  '⚠ 072 REPLACED THIS FUNCTION BY DROP + CREATE, because adding an output column is a return-type change that '
  'create-or-replace refuses. The DROP destroyed the grants and this comment and 072 re-issued both: EXECUTE revoked '
  'from PUBLIC, granted to authenticated, NOT to service_role — the net ACL against the pre-072 catalog is unchanged. '
  'A future amendment to the return shape inherits the same obligation, and a fresh function is EXECUTABLE BY PUBLIC '
  'by default if the revoke is forgotten. '
  'CPI LEGS, all via pfin.fn_cpi_u_index_for_period (066) and never re-derived inline: basis = DECEMBER of the prior '
  'calendar year; "now" = the print at 066''s coverage_through (the same observation 067 uses, so chart and panel '
  'cannot disagree about now); anchor = first-of-month of the CALENDAR anchor month. ⚠ Pinning the anchor CPI to the '
  'calendar month rather than to the serving checkpoint is what stops the basis reference drifting when carry-forward '
  'reaches back. All three legs are guarded STRICTLY POSITIVE: 053 bars NaN and the infinities but NOT zero or '
  'negative, so unguarded a poisoned print would raise or silently flip a sign. '
  'ANCHORS are month-ends on the imported decade''s grain. month = THE MONTH-END STRICTLY BEFORE TODAY. ytd = 31 '
  'December of the prior year. 1y/3y/5y = the month-end AT-OR-BEFORE today, today included, minus 12/36/60 months. '
  '⚠ THE TWO READINGS OF "month-end" ARE BOTH DELIBERATE AND MUST NOT BE UNIFIED: STRICTLY-BEFORE for month, '
  'AT-OR-BEFORE for the multi-year grain. Unify downward and the month anchor collapses onto the current endpoint on '
  'every month-end day — both endpoints resolve through the same at-or-before LOCF predicate over nav_daily, so '
  'delta_nominal and delta_percent are forced to 0 (not NULL) on each of the twelve month-end days a year, which is '
  'the register this contract reserves for a true no-change. Unify upward and the 1-Year anchor lands THIRTEEN '
  'months back on those same days. ⚠ "COMPLETED" MEANS COMPLETED BEFORE TODAY: F/CTO-ratified 2026-08-30 '
  '(SELF-344), amending the 2026-08-14 ruling, under which the current day''s month-end counted as already '
  'completed. The competing reading — month-end at-or-before (today minus one month) — stays REJECTED for landing '
  'up to six weeks back; it coincides with the ruled reading ONLY on month-end days, which is why this amendment '
  'does not reopen it. This anchor is no longer a product default; its canonical home is ADR-065. '
  'THREE DISTINCT NULL CAUSES, discriminated STRUCTURALLY rather than by a flag the consumer must interpret (PRD '
  '§2.4.4 two-independent-signals): INSUFFICIENT HISTORY = anchor_date present with anchor_checkpoint_date NULL; CPI '
  'UNRESOLVABLE = cpi_unavailable true WITH delta_nominal still present; NOT APPLICABLE = all cpi_* NULL, which is '
  'month/ytd, where the adjusted column does not exist by design (PRD verbatim, parity-grounded). They can co-occur '
  'and live in different columns, so no two are confusable. cpi_any_carried and cpi_unavailable stay SEPARATE '
  'booleans: a carried figure is shown WITH A MARKER, an unavailable one is NOT SHOWN AT ALL. '
  'delta_percent is NULL — never 0 — when the anchor NAV is zero, NEGATIVE or absent; no division is attempted. A '
  'NEGATIVE base INVERTS THE SIGN (improving from -100 to +100 would report -200%, a negative percentage for a '
  'positive improvement), which is the alike-rendering the ratified principle bars. delta_nominal and '
  'delta_inflation_adjusted are arithmetically sound over a negative base and are NOT guarded. ⚠ The two NULL '
  'causes here — zero base and negative base — render IDENTICALLY and are deliberately NOT discriminated; no '
  'fourth NULL-cause signal exists for them. '
  'anchor_date is the CALENDAR anchor and anchor_checkpoint_date is the checkpoint that actually served it, EARLIER '
  'when carried — both returned so "measured on the anchor" stays distinguishable from "carried from before it" '
  '(062''s carry-forward-with-provenance pattern). ⚠ current_checkpoint_date discloses the SAME property for the '
  'OTHER endpoint (F/CTO ratify 2026-08-13, return-shape option A): every delta has TWO endpoints and until now '
  'only one carried its provenance. During a cron outage the "now" side is itself carried, so EVERY horizon''s '
  'delta is measured against a stale present — and without this column a consumer could not tell, because the '
  'anchor side would look perfectly fresh. It is identical on all five rows (a property of the store, not of a '
  'horizon), like cpi_basis_period. '
  '⚠ TWO-CLOCK RESIDUAL, stated because 070 does NOT close it: ADR-044 R2 guarantees both sides of ONE COMPARISON use '
  'the same day and guarantees NOTHING ACROSS CONTAINERS — and nav_daily.nav_date is current_date in the ETL worker''s '
  'session, a different container. The residual is bounded to a one-day boundary effect at a month-end, moves which '
  'checkpoint serves an anchor by at most one, and the served date is RETURNED rather than hidden. Do NOT "fix" it by '
  'harmonizing the ETL worker onto 070 — ADR-044 names that as the sweep that would be wrong. '
  'TENANT FENCE: RLS on nav_daily is the SOLE mechanism — no users_id predicate of its own and it MUST NOT GAIN ONE; '
  'QA measured on 062 that a redundant local predicate keeps the cross-tenant battery green over a policy broken open. '
  'Cross-tenant callers get five all-NULL rows and fail closed; the 025 aal2 backstop is inherited through that same '
  'policy. The CPI legs cross no tenant boundary. p_users_id struck for the fourth time in this family (049/051/067); '
  'p_scope struck because pfin.scope DOES NOT EXIST — scope aggregation is SELF-228''s. '
  'SECURITY INVOKER — NOT a DEFINER allowlist entry; read ADR-011 Decision 9 live. §10 catalogued ledger UNCHANGED BY '
  'THIS OBJECT and NO COUNT IS STATED HERE. Read ADR-011 Decision 4 live. Decision-3 unchanged. EXECUTE revoked from '
  'PUBLIC, granted to authenticated. Sec joint-review-mandatory (financial calculation + multi-tenant read path + a '
  'new clock primitive); RLS verification -> the SELF-221 battery.';

-- ----------------------------------------------------------------------------
-- pfin.fn_nav_reference_dates — re-issued in full. Only `prior_month` and its
-- CPI period change; the at-or-before CASE is gone because this function has no
-- multi-year row that needs it. Same CoR restatement rules as above.
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
  v_prior_mth  date;      -- month-end STRICTLY BEFORE today = the prior-month
                          -- reference date. Was v_base, an at-or-before CASE.
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

  -- The most recent COMPLETED month-end, where COMPLETED means completed
  -- BEFORE today — the SAME expression 072 uses for its `month` anchor, which
  -- is the property that keeps the two panels reconcilable on screen.
  -- `::timestamp` is zone-free (WITHOUT time zone), the 062 idiom.
  -- ⚠ THE CASE THAT USED TO STAND HERE IS GONE, NOT SIMPLIFIED AWAY. Its
  -- true-branch made today its own base on a month-end, which collapsed
  -- prior_month onto this_month for the whole of those twelve days. 072 keeps
  -- an equivalent CASE (its `v_base`) because its 1y/3y/5y anchors need the
  -- at-or-before reading; this function has no multi-year row, so nothing here
  -- needs it and the variable is gone rather than left unused.
  v_prior_mth := (date_trunc('month', v_today::timestamp)
                  - '1 day'::interval)::date;

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
      ('prior_month'::text,    v_prior_mth,
                               date_trunc('month', v_prior_mth::timestamp)::date),
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
  'must land exactly on a figure there. "Prior Month" means THE MOST RECENT COMPLETED MONTH-END, where COMPLETED '
  'means completed BEFORE today — so on a month-end day prior_month is the PRECEDING month-end, never today itself. '
  'F/CTO-ratified 2026-08-14, AMENDED 2026-08-30 (SELF-344) on that boundary and nothing else: the superseded '
  'reading made today its own prior month on every month-end day, collapsing prior_month onto this_month so the two '
  'rows returned identical values. The competing reading — month-end at-or-before (today minus one month) — remains '
  'REJECTED: it lands up to six weeks back and would break the reconciliation above. It coincides with the ruled '
  'reading only on month-end days, which is why the amendment does not reopen it. Canonical home: ADR-065. '
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

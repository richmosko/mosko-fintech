-- ============================================================================
-- Migration: pfin.fn_nav_delta_panel — the §2.1.3.a multi-horizon NAV-delta
--   backend. SECURITY INVOKER read-composition (Lock 11) over pfin.nav_daily
--   (054) for the endpoints and pfin.fn_cpi_u_index_for_period (066) for every
--   CPI observation, with today's date from pfin.fn_server_today (070, same PR).
--   Linear SELF-221 (V1.1; PRD §2.1.3); downstream consumer is the SELF-222
--   panel UI. F/CTO-ratified 2026-08-13 on the Architect/PM reconciliation
--   package (temp/architect-self221-reconciliation.md +
--   temp/pm-self221-ac-rewrite.md). apply-migration procedure applied.
--   JOINT-REVIEW-MANDATORY (Sec veto surface): financial calculation +
--   multi-tenant read path.
--
-- ----------------------------------------------------------------------------
-- ⚠ THE DRAFTED AC3 FORMULA WAS A CORRECTNESS DEFECT, and it is recorded here
--   because it is the kind a reviewer waves through and a careless test suite
--   passes. It read:
--       delta_inflation_adjusted = delta_nominal × (cpi_ye / cpi_anchor)
--   >> THAT NEVER DEFLATES THE CURRENT ENDPOINT AT ALL. Scaling the whole
--      nominal delta by one CPI ratio is arithmetically identical to asserting
--      the entire NAV change occurred AT THE ANCHOR DATE. <<
--   WORKED EXAMPLE (synthetic; no real figures appear in this repo). NAV
--   1,000 -> 1,100 while CPI 100 -> 110, basis cpi_ye = 105. NAV rose exactly
--   with inflation, so the TRUE real-terms change is ZERO.
--       drafted : (1100 - 1000) × 105/100            = +105
--       correct : 1100 × 105/110 - 1000 × 105/100    =    0
--   ERROR TERM IN CLOSED FORM, which is what makes it a defect rather than a
--   rounding quibble:
--       drafted - correct = cpi_ye × nav_current × (cpi_current - cpi_anchor)
--                           ----------------------------------------------
--                                    cpi_anchor × cpi_current
--   It scales with nav_current — THE WHOLE PORTFOLIO — not with the delta. On a
--   large portfolio with a small real change the reported figure is dominated by
--   the error; under normal inflation it always OVERSTATES; and it agrees with
--   the truth only when cpi_current = cpi_anchor, i.e. exactly when the
--   adjustment was pointless.
--
--   THE RATIFIED FORMULA — deflate EACH ENDPOINT into prior-year-end dollars,
--   then subtract. THREE CPI observations, not two:
--       delta_inflation_adjusted
--         = nav_current × (cpi_ye / cpi_current) - nav_anchor × (cpi_ye / cpi_anchor)
--
-- ----------------------------------------------------------------------------
-- WHY THE ENDPOINTS ARE READ DIRECTLY AND NOT THROUGH fn_nav_series (062).
--   062 answers "a bucketed series over a range"; this function needs "the NAV
--   as of five specific dates". Composing would mean requesting a 60-month
--   series and then reasoning AROUND 062's period-end bucketing and two-sided
--   clamping at every anchor. >> BORROWING A FUNCTION WHOSE SEMANTICS YOU MUST
--   THEN WORK AROUND IS A WORSE DEPENDENCY THAN NOT BORROWING IT. << What is
--   reused is 062's IDIOM — the at-or-before LOCF lateral — not its function.
--   This is NOT a recompute: 062's NO-RECOMPUTE fence forbids reaching the
--   VALUATION engine, and no valuation function is reached here. The 069
--   precedent is the same shape.
--
-- ----------------------------------------------------------------------------
-- ⚠ THE TWO-CLOCK RESIDUAL, stated because 070 explicitly does NOT close it.
--   070 (ADR-044 R2) guarantees that both sides of ONE COMPARISON use the same
--   day. It guarantees NOTHING ACROSS CONTAINERS — and ADR-044's own worked
--   example is exactly this surface's dependency: pfin.nav_daily.nav_date is
--   `current_date` in the ETL WORKER's session, a different container and login
--   role from the web app. So comparing an anchor derived HERE against nav_date
--   spans two clocks, and R2 does not cover it.
--   BOUNDED, AND WHY IT IS ACCEPTABLE: the residual is a one-day boundary effect
--   at a month-end, and every anchor in this function is a MONTH-END resolved by
--   AT-OR-BEFORE carry-forward — so a one-day disagreement moves which
--   checkpoint serves an anchor by at most one checkpoint, and the served date
--   is RETURNED (anchor_checkpoint_date) rather than hidden. It does not change
--   which month the anchor names.
--   >> DO NOT "FIX" THIS BY HARMONIZING THE ETL WORKER ONTO 070. ADR-044 names
--      that as the natural sweep that would be wrong. <<
--
-- ----------------------------------------------------------------------------
-- ⚠ ONE PRODUCT AMBIGUITY RESOLVED BY DEFAULT, AND FLAGGED RATHER THAN BURIED.
--   PRD §2.1.3 says "Month = vs. one month ago", which does not by itself fix a
--   month-end anchor. THIS FUNCTION ANCHORS ALL FIVE HORIZONS ON MONTH-END GRAIN
--   stepping back in whole months from the most recent COMPLETED month-end:
--     base   = the month-end at-or-before today
--     Month  = base            (the last month close)
--     1/3/5Y = base - 12/36/60 months
--     YTD    = 31 December of the prior calendar year
--   Rationale: it makes all five horizons commensurable, lands every anchor on
--   the imported decade's month-end grain (ADR-053 D7), and matches how a
--   monthly-review panel is read. The alternative reading — "month-end at-or-
--   before (today - 1 month)" — puts the Month anchor up to six weeks back,
--   which is not what "one month ago" conveys.
--   >> THIS IS A PRODUCT CALL IMPLEMENTED AS A DEFAULT, NOT AN ARCHITECTURAL
--      RULING. If PM/F-CTO want the other reading, it is a body change with no
--      contract impact. <<
--
-- ----------------------------------------------------------------------------
-- Numbering: 071 follows 070 (fn_server_today, this same PR), taken at authoring
--   time and verified against the tree at 8fd9f8e. Depends on 054 (nav_daily —
--   the sole relation read; its RLS SELECT policy and inherited 025 aal2
--   backstop are what fence this function), 066 (every CPI observation), and
--   070 (today). Creation is order-independent — a plpgsql body is not resolved
--   against the catalog at create time — but it is sequenced after 070
--   deliberately so a clean apply reaches an immediately-callable state.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (Lock 11 read-composition default); NOT
--   SECURITY DEFINER. Runs as the caller and inherits their RLS context exactly
--   as 049 / 051 / 062 / 067 / 069 do. Every value it returns derives from rows
--   the caller may already read. DEFINER would detach the read from the caller's
--   RLS context and from the 025 aal2 step-up backstop nav_daily's policy
--   carries — and would additionally break 070's guarantee, whose whole basis is
--   that the function and its caller share a session.
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
--   load-bearing, not tidy. A cross-tenant caller sees no rows and gets five
--   all-NULL rows: fails closed. The CPI legs cross no tenant boundary (066
--   reads global `using (true)` reference tables).
--   ⚠ THE PARAMETER LIST IS EMPTY, DELIBERATELY. `p_users_id` was struck for the
--   FOURTH time in this family (049 R2 / 051 / 067 / here) — tenant comes from
--   session RLS, and a uid parameter is either redundant or a cross-tenant read
--   shape. `p_scope pfin.scope[]` was struck because THE TYPE DOES NOT EXIST
--   (verified at 8fd9f8e: the schema declares no `create type` at all); scope
--   aggregation is SELF-228's, deferred as a plain deferral.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_nav_delta_panel()
--     RETURNS TABLE (horizon text, anchor_date date, anchor_checkpoint_date date,
--                    delta_nominal numeric, delta_percent numeric,
--                    delta_inflation_adjusted numeric, cpi_basis_period date,
--                    cpi_any_carried boolean, cpi_unavailable boolean)
--     — SECURITY INVOKER, STABLE, set search_path = ''. No parameters.
--   · EXACTLY FIVE ROWS, ALWAYS, in fixed order: 'month','ytd','1y','3y','5y'.
--     A horizon is NEVER absent — an uncomputable horizon returns its row with
--     NULL deltas. "The query dropped it" and "it is not computable" must not
--     render identically.
--   · anchor_date = the CALENDAR anchor (a month-end). anchor_checkpoint_date =
--     the checkpoint that actually served it, which is EARLIER when carried.
--     BOTH are returned so "measured on the anchor" stays distinguishable from
--     "carried from before it" — 062's carry-forward-with-provenance pattern.
--   · delta_percent is NULL — never 0 — when the anchor NAV is zero or NULL. No
--     division is attempted. "No change" and "cannot be expressed" must not
--     render alike.
--   · delta_inflation_adjusted applies to 1y/3y/5y ONLY. Month and YTD carry
--     NULL BY DESIGN (PRD §2.1.3 verbatim, parity-grounded).
--
--   ⚠ THREE DISTINCT NULL CAUSES, AND THE SHAPE DISCRIMINATES THEM STRUCTURALLY
--     rather than by a flag the consumer must interpret (§2.4.4's
--     two-independent-signals ruling; the UI must never collapse them):
--       INSUFFICIENT HISTORY  anchor_date NOT NULL, anchor_checkpoint_date NULL
--                             -> we know which anchor we wanted; no observation
--                                reaches it. Deltas NULL.
--       CPI UNRESOLVABLE      cpi_unavailable = true, delta_nominal PRESENT
--                             -> the nominal figure stands; only the real-terms
--                                one cannot be formed.
--       NOT APPLICABLE        cpi_* columns ALL NULL (month / ytd)
--                             -> the adjusted column does not exist for this
--                                horizon; it is not missing, it is not asked for.
--     These can co-occur and live in different columns, so no two are confusable.
--   · cpi_any_carried and cpi_unavailable are SEPARATE BOOLEANS on purpose: a
--     carried figure is SHOWN WITH A MARKER, an unavailable one is NOT SHOWN AT
--     ALL. Collapsing them into one quality enum would force the consumer to
--     learn a vocabulary instead of reading two flags (066's precedent).
--   · Security-load-bearing edges: RLS on nav_daily is the SOLE tenant fence;
--     cross-tenant callers get five all-NULL rows and fail closed; the 025 aal2
--     backstop is inherited; CPI legs are strictly-positive-guarded so a poisoned
--     print can neither raise nor flip a sign; every CPI value comes from 066, so
--     the gap policy is not re-derived here; `set search_path = ''` with every
--     reference schema-qualified.
--
-- ----------------------------------------------------------------------------
-- CPI COMPOSITION — three legs, ALL through 066, never an inline lookup (066's
--   standing requirement: the carry-forward and gap-classification policy is not
--   re-derived in a consumer).
--     cpi_ye      : DECEMBER of the prior calendar year — the denomination the
--                   whole panel is expressed in, common to every horizon.
--     cpi_current : the print at 066's coverage_through — the SAME observation
--                   067 uses for "today's dollars", so the chart and the panel
--                   cannot disagree about what "now" means. CPI publishes one to
--                   two months in arrears, so the current month is normally
--                   absent and would be carried anyway.
--     cpi_anchor  : first-of-month of the CALENDAR anchor month.
--   ⚠ PINNING cpi_anchor TO THE CALENDAR ANCHOR — NOT TO THE SERVING CHECKPOINT
--   — IS WHAT SATISFIES PM'S BINDING CONSTRAINT that no resolution rule may
--   silently shift an anchor across the prior-year-end boundary. However far
--   carry-forward reaches back, cpi_anchor does not move, so AC3's reference
--   cannot drift. That is 067's deflate-at-the-point precedent doing real work.
--   ⚠ STRICTLY-POSITIVE GUARD on every leg: 053 bars NaN and ±Infinity but NOT
--   zero or negative (BACKLOG §7.14). Unguarded, a poisoned 0 raises `division
--   by zero` and a negative silently flips the sign of a net-worth figure.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; the catalogued
--   numbered list is NOT restated and no count is stated. Decision 4 read
--   VERBATIM at the canonical anchor before drafting, 2026-08-13, at 8fd9f8e.)
--   (i)   Instance-numbering: nothing appended, reordered, or renumbered.
--   (ii)  Layer-attribution: an INVOKER read helper reached by `authenticated`
--         over PostgREST. NOT the PDF-worker container credential audit, NOT the
--         code-layer SUPABASE_SERVICE_ROLE_KEY allowlist fence, NOT the
--         app→worker credential-admission network surface. No catalogued
--         instance's layer attribution moves; no surface becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is REFERENCED, not restated.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED set are DIFFERENT SETS and are
--   NOT reconciled here.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — +0. No table, no column, no
--   FK-shaped reference of any kind. AUTHORING-TIME PROVENANCE (dated, not live
--   state — read Decision 3's body live; it grows and its labels are
--   non-contiguous): read verbatim at the canonical anchor on 2026-08-13 at
--   8fd9f8e, the family stood at SIXTEEN LABELED INSTANCES (#1–#16), THIRTEEN
--   DDL-REALIZED. Recorded as a dated observation ONLY.
--
-- ----------------------------------------------------------------------------
-- LEDGER DELTAS (all FLAT): §10 catalogued +0 · SECURITY DEFINER allowlist +0 ·
--   Decision 3 family +0 · SD matrix NO expansion · grants on existing objects
--   unchanged · RLS unchanged · triggers unchanged. Sec joint-review MANDATORY:
--   financial calculation on a multi-tenant read path, consuming a brand-new
--   clock primitive.
--
-- ----------------------------------------------------------------------------
-- QA TEST-PAIRING (QA-owned). Ships SAME-PR.
--   1. ⭐ THE CRUX LEG — THE ARITHMETIC, ASSERTED WITH cpi_current ≠ cpi_anchor.
--      Independently-computed expected values. ⚠ AN EQUAL-CPI FIXTURE CANNOT
--      DISTINGUISH THE RATIFIED FORMULA FROM THE DEFECTIVE DRAFT — they coincide
--      exactly when CPI did not move. A suite built on equal-CPI fixtures would
--      have passed the defect this migration exists to correct.
--   2. FIVE ROWS ALWAYS, in fixed order, including the all-NULL uncomputable
--      case and a tenant with zero checkpoints.
--   3. THE THREE NULL CAUSES ARE DISTINGUISHABLE: insufficient history
--      (anchor_date present, anchor_checkpoint_date NULL); CPI unresolvable
--      (cpi_unavailable true WITH delta_nominal present); not-applicable
--      (month/ytd, all cpi_* NULL). Assert each on the full row.
--   4. CARRY PROVENANCE: an anchor with no exact checkpoint returns
--      anchor_checkpoint_date < anchor_date and the carried value.
--   5. delta_percent NULL — not 0, not a raise — when the anchor NAV is zero.
--   6. ZERO / NEGATIVE CPI yields NULL, never `division by zero` and never a
--      sign-flipped figure. See the strictly-positive guard.
--   7. TWO-TENANT, NON-VACUOUSLY: identical dates, DIFFERENT nav_values; A's
--      call returns A's deltas. A same-value fixture passes under a broken
--      predicate.
--   8. CROSS-TENANT: five all-NULL rows, not an error, not the other tenant's.
--   9. AAL2 BACKSTOP, BOTH LEGS — aal1 gets all-NULL, aal2 gets real deltas.
--      The negative alone passes vacuously on an empty fixture.
--  10. PST1-SHAPE POSTURE LEG for BOTH 070 and 071: prosecdef false, provolatile
--      's', proconfig pins search_path empty. Behaviour cannot distinguish
--      INVOKER from DEFINER; only the catalog can.
--  11. ACL for both: EXECUTE revoked from PUBLIC, granted to `authenticated`,
--      NOT held by service_role. Assert on pg_proc.proacl.
--  12. ⚠ SEC'S FULL-STATE-TUPLE CRITERION applies wherever this consumes another
--      helper's row: assert the WHOLE returned tuple, not only the field under
--      test, so a neighbouring field silently changing is caught.
--   ⚠ `supabase db reset` is PROHIBITED — it destroys F/CTO's local test data.
--   Verify non-destructively (apply-in-txn + rollback).
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- pfin.fn_nav_delta_panel — five fixed horizons, nominal and real-terms.
-- See the header for the full contract; inline notes cover only what is not
-- obvious from the code.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_nav_delta_panel()
returns table (
  horizon                   text,
  anchor_date               date,
  anchor_checkpoint_date    date,
  delta_nominal             numeric,
  delta_percent             numeric,
  delta_inflation_adjusted  numeric,
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
  v_base        date;      -- month-end at-or-before today (the last month close)
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
  v_adj         numeric;
  v_unavail     boolean;
  v_carried     boolean;
begin
  -- ONE clock read, via 070, so both sides of every comparison below use the
  -- same day (ADR-044 R2). Everything downstream is date arithmetic on a `date`
  -- and is therefore zone-free; the residual across containers is in the header.
  v_today := pfin.fn_server_today();

  -- The most recent COMPLETED month-end. `::timestamp` is zone-free (WITHOUT
  -- time zone) — the 062 idiom. If today IS a month-end it is its own base.
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
    select * from (values
      ('month'::text, v_base,                                              false),
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

    v_adj := null; v_unavail := null; v_carried := null;

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
        -- is the defect this migration corrects.
        v_adj := v_cur_nav * (v_cpi_ye / v_cpi_cur)
               - v_a_nav   * (v_cpi_ye / v_cpi_a);
      end if;
    end if;

    return query select
      h.name,
      h.anchor,
      v_a_cp,
      case when v_cur_nav is not null and v_a_nav is not null
           then v_cur_nav - v_a_nav end,
      -- NULL, never 0, on a zero or absent anchor: no division is attempted, and
      -- "no change" must not render like "cannot be expressed".
      case when v_cur_nav is not null and v_a_nav is not null and v_a_nav <> 0
           then (v_cur_nav - v_a_nav) / v_a_nav * 100 end,
      v_adj,
      case when h.adj then v_ye_period end,
      v_carried,
      v_unavail;
  end loop;
end;
$$;

revoke execute on function pfin.fn_nav_delta_panel() from public;
grant  execute on function pfin.fn_nav_delta_panel() to authenticated;

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
  'CPI LEGS, all via pfin.fn_cpi_u_index_for_period (066) and never re-derived inline: basis = DECEMBER of the prior '
  'calendar year; "now" = the print at 066''s coverage_through (the same observation 067 uses, so chart and panel '
  'cannot disagree about now); anchor = first-of-month of the CALENDAR anchor month. ⚠ Pinning the anchor CPI to the '
  'calendar month rather than to the serving checkpoint is what stops the basis reference drifting when carry-forward '
  'reaches back. All three legs are guarded STRICTLY POSITIVE: 053 bars NaN and the infinities but NOT zero or '
  'negative, so unguarded a poisoned print would raise or silently flip a sign. '
  'ANCHORS are month-ends on the imported decade''s grain: base = the month-end at-or-before today; month = base; '
  '1y/3y/5y = base minus 12/36/60 months; ytd = 31 December of the prior year. ⚠ The "Month = vs. one month ago" '
  'reading is a PRODUCT default implemented here, not an architectural ruling — changing it is a body change with no '
  'contract impact. '
  'THREE DISTINCT NULL CAUSES, discriminated STRUCTURALLY rather than by a flag the consumer must interpret (PRD '
  '§2.4.4 two-independent-signals): INSUFFICIENT HISTORY = anchor_date present with anchor_checkpoint_date NULL; CPI '
  'UNRESOLVABLE = cpi_unavailable true WITH delta_nominal still present; NOT APPLICABLE = all cpi_* NULL, which is '
  'month/ytd, where the adjusted column does not exist by design (PRD verbatim, parity-grounded). They can co-occur '
  'and live in different columns, so no two are confusable. cpi_any_carried and cpi_unavailable stay SEPARATE '
  'booleans: a carried figure is shown WITH A MARKER, an unavailable one is NOT SHOWN AT ALL. '
  'delta_percent is NULL — never 0 — when the anchor NAV is zero or absent; no division is attempted. '
  'anchor_date is the CALENDAR anchor and anchor_checkpoint_date is the checkpoint that actually served it, EARLIER '
  'when carried — both returned so "measured on the anchor" stays distinguishable from "carried from before it" '
  '(062''s carry-forward-with-provenance pattern). '
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

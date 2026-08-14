-- ============================================================================
-- Migration: pfin.fn_nav_delta_panel — the §2.1.3.a multi-horizon NAV-delta
--   backend, AMENDED to return a REAL-TERMS PERCENT alongside the real-terms
--   dollar delta (the §2.1.3.b AC3 amendment). SECURITY INVOKER
--   read-composition (Lock 11) over pfin.nav_daily (054) for the endpoints and
--   pfin.fn_cpi_u_index_for_period (066) for every CPI observation, with today's
--   date from pfin.fn_server_today (070). V1.1; PRD §2.1.3; the downstream
--   consumer is the §2.1.3.b panel UI. F/CTO-ratified 2026-08-14 (Option B on
--   the AC3 gap). apply-migration procedure applied. JOINT-REVIEW-MANDATORY
--   (Sec veto surface): financial calculation + multi-tenant read path.
--
-- ----------------------------------------------------------------------------
-- WHAT THIS MIGRATION CHANGES, AND WHAT IT DELIBERATELY DOES NOT.
--   CHANGES — exactly one thing: the return shape gains
--   `delta_inflation_adjusted_percent numeric`, positioned immediately after
--   `delta_inflation_adjusted`. Every other column keeps its name, type and
--   meaning; the arithmetic of every pre-existing column is unchanged
--   expression-for-expression, and the deflated-anchor term is now BOUND TO A
--   VARIABLE and reused rather than re-spelled, so the dollar figure cannot
--   drift from the percent that denominates against it.
--   DOES NOT CHANGE — posture (INVOKER), volatility (STABLE), search_path,
--   parameter list (still empty), tenant fence, CPI composition, anchor
--   derivation, NULL-cause discrimination, or the EXECUTE ACL's intent.
--
--   WHY IT IS A CORRECTION AND NOT AN ENHANCEMENT: the incumbent panel's
--   Inflation Adjusted cells are PERCENTS, and PRD §3.3 clause (ii) makes those
--   cells a ratified parity-compared surface. Shipping the dollar figure alone
--   leaves a parity-load-bearing V1 column unimplemented, not merely plainer.
--
-- ----------------------------------------------------------------------------
-- ⚠ THE RETURN SHAPE CHANGES, SO THIS IS DROP + CREATE — NOT `create or
--   replace`. PostgreSQL treats the RETURNS TABLE column list as the function's
--   result type, and adding a column to it is a return-type change, which
--   `create or replace` REFUSES ("cannot change return type of existing
--   function"). Three consequences, each handled explicitly below because DROP
--   discards them SILENTLY and a green apply looks identical either way:
--     (i)   GRANTS ARE DESTROYED. A freshly created function carries the
--           PostgreSQL default of EXECUTE to PUBLIC. The `revoke ... from
--           public` + `grant ... to authenticated` pair below is therefore
--           LOAD-BEARING, not carried decoration: without it this migration
--           leaves the function EXECUTABLE BY PUBLIC — a widening no
--           behavioural test would notice.
--     (ii)  THE CATALOG COMMENT IS DESTROYED. It is re-issued in full below,
--           carried from 071 with named additions only.
--     (iii) A DEPENDENT OBJECT WOULD BLOCK THE DROP. `drop function` without
--           CASCADE fails rather than cascading, which is the fail-closed
--           direction: should some later view or function come to depend on
--           this signature, this migration STOPS instead of quietly removing
--           it. ⚠ Do NOT "fix" such a failure by adding CASCADE.
--
--   `drop function if exists` is used so a clean apply and a re-apply behave
--   alike; the empty argument list makes the signature unambiguous.
--
--   071 IS LEFT UNEDITED — it is applied history, and its header records the
--   reasoning that produced this object. This file supersedes 071's CONTRACT
--   block and nothing else; the narrative below is carried from it because this
--   file is now the one a reader reaches for, and all of it remains true.
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
-- THE AC3 AMENDMENT — WHAT THE REAL-TERMS PERCENT DENOMINATES AGAINST.
--   F/CTO-ratified 2026-08-14. The percent expresses the real-terms delta as a
--   fraction of the ANCHOR ENDPOINT MEASURED IN THE SAME DOLLARS — that is, the
--   deflated anchor, the SECOND TERM the formula above already computes:
--       real_base = nav_anchor × (cpi_ye / cpi_anchor)
--       delta_inflation_adjusted_percent
--         = delta_inflation_adjusted / real_base × 100
--   >> NUMERATOR AND DENOMINATOR ARE BOTH IN PRIOR-YEAR-END DOLLARS. That is
--      the whole point: a ratio between two differently-denominated figures is
--      not a percentage of anything. <<
--   The body binds `real_base` ONCE and uses it in BOTH the dollar delta and
--   this percent, so the two cannot disagree about what the anchor was worth.
--
--   ⚠ IT IS NOT DERIVABLE BY A CONSUMER, and that is checkable from the
--   signature rather than taken on trust: THIS FUNCTION RETURNS NO NAV LEVEL AT
--   ALL — only deltas — so neither base exists in the output. The tempting
--   back-derivation, delta_inflation_adjusted ÷ (delta_nominal ÷ delta_percent),
--   reconstructs the NOMINAL anchor and divides a REAL numerator by it. That is
--   the mixed-basis defect class 071's header exists to document, arrived at
--   from the consumer side instead of the producer side. A column the consumer
--   would otherwise compute WRONG is a column the producer owes them.
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
--
--   ⚠ YTD IS THE EXCEPTION TO THAT BOUND, AND THE EXPOSURE IS A DIFFERENT ONE.
--   The paragraph above bounds the CROSS-CONTAINER residual. YTD surfaces R2's
--   OTHER non-guarantee — WHICH day. Two sessions in different zones can get
--   different fn_server_today() values, and ACROSS A YEAR BOUNDARY that changes
--   extract(year from today), moving ytd's anchor and cpi_basis_period BY A
--   FULL YEAR — not by a day. Because cpi_basis_period denominates EVERY
--   adjusted figure, 1y/3y/5y move with it, not just the ytd row.
--   >> SO "it does not change which month the anchor names" IS TRUE OF THE
--      MONTH AND NOT OF THE YEAR. The month is stable; on 31 December / 1
--      January the year is not. <<
--   ⚠⚠ DOCUMENTATION ONLY — DO NOT "FIX" THIS IN CODE. The computation is
--   RIGHT; the bound sentence was overstated. Pinning ytd's year would make the
--   panel disagree with the caller's own calendar, and would correctly RED the
--   (P3)/(P4) battery legs, which assert the derivation against make_date.
--   Practical exposure is small — one user, one session, one panel load is
--   self-consistent; divergence needs two sessions in different zones on the
--   same boundary — but the bound as written understated it.
--
--   ⚠ A STRUCTURAL CONSEQUENCE OF THE SAME ANCHOR, stated so it is not read as
--   a fault: in JANUARY AND FEBRUARY, cpi_basis_period is the December that has
--   just ended, whose CPI print does not exist yet — CPI publishes one to two
--   months in arrears. 066 therefore serves it CARRIED, and cpi_any_carried
--   comes back TRUE PANEL-WIDE for roughly two months every year. That is
--   correct behaviour, correctly signalled. A consumer must distinguish "the
--   basis is carried because the year just turned" from "the basis is carried
--   because ingest is behind" — the copy is the panel UI's, the signal is here.
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
-- Numbering: 072 is the next free number, taken at authoring time and verified
--   against the tree at d0f66eb — both `supabase/migrations/` on main and the
--   only other live branch, which carries no migration beyond 071. Depends on
--   054 (nav_daily — the sole relation read; its RLS SELECT policy and inherited
--   025 aal2 backstop are what fence this function), 066 (every CPI
--   observation), and 070 (today). ⚠ UNLIKE ITS PREDECESSORS THIS MIGRATION IS
--   ORDER-DEPENDENT IN ONE DIRECTION: it drops an object 071 creates, so it must
--   apply after 071. A plpgsql body is still not resolved against the catalog at
--   create time, so the 054/066/070 dependencies remain order-independent.
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
--                    current_checkpoint_date date,
--                    delta_nominal numeric, delta_percent numeric,
--                    delta_inflation_adjusted numeric,
--                    delta_inflation_adjusted_percent numeric,
--                    cpi_basis_period date,
--                    cpi_any_carried boolean, cpi_unavailable boolean)
--     — SECURITY INVOKER, STABLE, set search_path = ''. No parameters.
--   · EXACTLY FIVE ROWS, ALWAYS, in fixed order: 'month','ytd','1y','3y','5y'.
--     A horizon is NEVER absent — an uncomputable horizon returns its row with
--     NULL deltas. "The query dropped it" and "it is not computable" must not
--     render identically.
--   · current_checkpoint_date = the checkpoint that served the CURRENT endpoint.
--     Identical on all five rows (a property of the store, not of a horizon).
--     ⚠ WHY IT EARNS ITS PLACE (F/CTO ratify 2026-08-13, option A): every delta
--     has TWO endpoints and only the anchor side disclosed its provenance.
--     During a cron outage the "now" side is itself carried, so EVERY horizon
--     is measured against a stale present — and the anchor side would look
--     perfectly fresh while it happened. This column is how a consumer sees it.
--   · anchor_date = the CALENDAR anchor (a month-end). anchor_checkpoint_date =
--     the checkpoint that actually served it, which is EARLIER when carried.
--     BOTH are returned so "measured on the anchor" stays distinguishable from
--     "carried from before it" — 062's carry-forward-with-provenance pattern.
--   · delta_percent is NULL — never 0 — when the anchor NAV is zero, NEGATIVE
--     or NULL (a negative base inverts the sign: -100 -> +100 would report
--     -200%). Nominal and adjusted are sound over a negative base and keep it. No
--     division is attempted. "No change" and "cannot be expressed" must not
--     render alike.
--   · delta_inflation_adjusted applies to 1y/3y/5y ONLY. Month and YTD carry
--     NULL BY DESIGN (PRD §2.1.3 verbatim, parity-grounded).
--   · delta_inflation_adjusted_percent is that same figure as a PERCENT of the
--     DEFLATED ANCHOR — base = nav_anchor × (cpi_ye / cpi_anchor), the second
--     term of the dollar formula, bound once in the body and shared. It rides
--     the dollar column ONE-WAY: NULL on every row where
--     delta_inflation_adjusted is NULL (month / ytd by design, either NAV
--     endpoint absent, any CPI leg unresolvable), so no row can carry a percent
--     without the dollar figure it derives from.
--     ⚠ AND NULL — NEVER 0 — WHEN THE DEFLATED ANCHOR BASE IS NON-POSITIVE,
--     the same alike-rendering principle already ratified for delta_percent:
--     "no real-terms change" and "cannot be expressed in real terms" must not
--     render identically. Under the strictly-positive CPI guard this is
--     equivalent to a zero-or-negative anchor NAV, but the guard is written on
--     THE DENOMINATOR THAT IS ACTUALLY DIVIDED BY, not on the NAV it is
--     equivalent to — so it stays sound if the CPI guard is ever reshaped.
--     ⚠ NOT CONSUMER-DERIVABLE: no NAV level is returned, so neither base
--     exists in the output; the available back-derivation divides a REAL
--     numerator by a NOMINAL base. See the AC3 AMENDMENT block above.
--   · NO ROUNDING IS APPLIED TO ANY COLUMN, and both real-terms columns carry
--     `numeric` DIVISION RESIDUE at the scale PostgreSQL selects — a real delta
--     of exactly 52.5 surfaces as 52.4999…, and the percent derived from it as
--     4.9999…. This is 071 behaviour on the dollar column, inherited by the
--     percent. Presentation rounding belongs to the consumer. ⚠ ANY ASSERTION
--     OR COMPARISON ON THESE TWO COLUMNS MUST USE A TOLERANCE OR ROUND FIRST —
--     exact equality against a hand-computed decimal will be RED and the
--     function will be right.
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
--   VERBATIM at the canonical anchor before drafting, 2026-08-14, at d0f66eb.)
--   (i)   Instance-numbering: nothing appended, reordered, or renumbered.
--   (ii)  Layer-attribution: an INVOKER read helper reached by `authenticated`
--         over PostgREST. NOT the PDF-worker container credential audit, NOT the
--         code-layer SUPABASE_SERVICE_ROLE_KEY allowlist fence, NOT the
--         app→worker credential-admission network surface. No catalogued
--         instance's layer attribution moves; no surface becomes "four-layer".
--         ⚠ THE DROP+CREATE DOES NOT MOVE AN ATTRIBUTION EITHER: the EXECUTE
--         ACL re-issued below restores the SAME grant to the SAME role, so no
--         fence changes layer, strength, or owner — it is re-asserted, not
--         re-designed.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is REFERENCED, not restated.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED set are DIFFERENT SETS and are
--   NOT reconciled here.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — +0. No table, no column, no
--   FK-shaped reference of any kind. AUTHORING-TIME PROVENANCE (dated, not live
--   state — read Decision 3's body live; it grows and its labels are
--   non-contiguous): read verbatim at the canonical anchor on 2026-08-14 at
--   d0f66eb, the family stood at SIXTEEN LABELED INSTANCES (#1–#16), THIRTEEN
--   DDL-REALIZED. Recorded as a dated observation ONLY.
--
-- ----------------------------------------------------------------------------
-- LEDGER DELTAS (all FLAT): §10 catalogued +0 · SECURITY DEFINER allowlist +0 ·
--   Decision 3 family +0 · SD matrix NO expansion · RLS unchanged · triggers
--   unchanged. GRANTS: the only grant statement here re-establishes what the
--   DROP destroys — EXECUTE revoked from PUBLIC, granted to `authenticated`,
--   NOT to service_role (the 069 precedent). Net ACL delta against the
--   pre-migration catalog is ZERO; the statements are present because DROP made
--   them necessary, not because anything widened. Sec joint-review MANDATORY:
--   financial calculation on a multi-tenant read path, plus a re-issued ACL on a
--   dropped-and-recreated object.
--
-- ----------------------------------------------------------------------------
-- QA TEST-PAIRING (QA-owned). Ships SAME-PR.
--   1. ⭐ THE CRUX LEG — THE ARITHMETIC, ASSERTED WITH cpi_current ≠ cpi_anchor.
--      Independently-computed expected values. ⚠ AN EQUAL-CPI FIXTURE CANNOT
--      DISTINGUISH THE RATIFIED FORMULA FROM THE DEFECTIVE DRAFT — they coincide
--      exactly when CPI did not move. A suite built on equal-CPI fixtures would
--      have passed the defect this migration exists to correct.
--      ⭐ SAME LEG, THE AMENDED COLUMN: assert delta_inflation_adjusted_percent
--      against an independently-computed expected value on the SAME fixture.
--      ⚠ THE FIXTURE MUST MAKE THE REAL PERCENT DIFFER FROM delta_percent — pick
--      NAV and CPI values where nominal and real percentages are distinguishable
--      at the asserted precision. A fixture where they coincide cannot tell the
--      ratified base (deflated anchor) from the nominal anchor, which is the
--      exact substitution a future "simplification" would make.
--      ⚠ ROUND OR USE A TOLERANCE. `numeric` division leaves residue: a real
--      delta of exactly 52.5 comes back as 52.4999… and its percent as 4.9999…
--      (MEASURED, not predicted — Architect smoke, scratch DB, 2026-08-14). An
--      exact-equality leg against a hand-computed decimal REDS on a correct
--      function. A worked fixture that exercises the distinguishing case:
--      current 1155 at cpi 110, anchor 950 at cpi 90, basis cpi 105 gives
--      delta_percent ≈ +21.58 while delta_inflation_adjusted_percent ≈ -0.53 —
--      OPPOSITE SIGNS, which no nominal-base substitution can reproduce.
--      ⚠ AND ASSERT TWO INVARIANTS THAT NEED NOTHING BUT THE RETURNED ROWS, so
--      they cannot be satisfied by re-deriving the body's own expression in the
--      fixture: (a) the percent is NULL on every row where the DOLLAR column is
--      NULL — a ONE-WAY implication, NOT "NULL together". ⚠ DO NOT WIDEN THIS TO
--      A BICONDITIONAL: on a non-positive real_base (item 14) the dollar column
--      is PRESENT while the percent is NULL, so the biconditional is FALSE and
--      the leg must be scoped to a fixture whose base is strictly positive —
--      which is why the battery's (INV1) is scoped to tenant A and must stay so;
--      (b) where both are non-NULL they have THE SAME SIGN, which is what fails
--      first if the base is ever allowed non-positive.
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
--
--   THE FOUR LEGS THIS MIGRATION ADDS (beyond amending 1 and 11 above):
--  13. RETURN SHAPE — ELEVEN COLUMNS, asserted by NAME, TYPE and ORDINAL against
--      the catalog, with delta_inflation_adjusted_percent immediately after
--      delta_inflation_adjusted. ⚠ THE POSITIONS OF cpi_basis_period,
--      cpi_any_carried AND cpi_unavailable ALL SHIFT BY ONE. Any existing leg
--      that reads the row POSITIONALLY must be re-derived, not just extended —
--      a positional test that still passes after this change is reading the
--      wrong column. This leg is what makes a future accidental drop or reorder
--      of the column loud.
--  14. NULL — NOT 0 — ON A NON-POSITIVE DEFLATED BASE, both sub-cases, and each
--      asserted ON THE FULL ROW so the neighbours are pinned at the same time:
--      (a) anchor NAV zero, (b) anchor NAV NEGATIVE with a positive current NAV
--      — the case where a percentage would come back with the WRONG SIGN if the
--      guard were dropped. delta_nominal and delta_inflation_adjusted MUST both
--      still be present on those rows; only the two percent columns go NULL.
--  15. THE NULL-CAUSE ROWS CARRY IT TOO: month and ytd (not-applicable — the
--      new column NULL alongside every other cpi_*), the CPI-unresolvable row
--      (cpi_unavailable true, delta_nominal present, BOTH real-terms columns
--      NULL), and insufficient history (anchor_checkpoint_date NULL).
--  16. ⚠ THE ACL AND POSTURE LEGS ARE NO LONGER MERELY CONFIRMATORY — RE-RUN
--      THEM AGAINST THIS MIGRATION AND TREAT THEM AS PRIMARY. The DROP destroys
--      the grants and the comment, and a fresh function is EXECUTABLE BY PUBLIC
--      by default, so legs 10 and 11 are now the things that catch a botched
--      re-issue: proacl shows no PUBLIC entry, `authenticated` holds EXECUTE,
--      service_role does not; prosecdef false; provolatile 's'; proconfig pins
--      search_path empty. Add an obj_description leg — the comment is destroyed
--      with the function and its absence is otherwise invisible.
--
--   ⚠⚠ HOW THE BATTERY PINS "TODAY" WHEN THIS FUNCTION DERIVES IT INTERNALLY.
--   QA asked, having assumed a `p_as_of` parameter. THERE IS NONE AND THERE MUST
--   NOT BE: a client-suppliable as-of is precisely the two-clock hazard ADR-044
--   exists to pin, and a test-only override would be that same surface wearing a
--   different name — Sec-reviewable, and it would make the battery exercise a
--   code path production never takes. The determinism comes from three
--   properties that already exist, not from a new mechanism:
--     (a) TRANSACTION-SCOPED STABILITY. `current_date` is fixed for the lifetime
--         of a transaction and 070 is STABLE, so INSIDE ONE ROLLED-BACK TEST
--         TRANSACTION this function's "today" CANNOT MOVE. Read
--         pfin.fn_server_today() ONCE at the top of the transaction into a
--         variable and every later call in that transaction agrees with it —
--         including a suite that straddles midnight, which is the case a
--         read-at-the-start-of-the-file approach would silently get wrong.
--     (b) ⭐ THE ARITHMETIC NEEDS NO PREDICTED ANCHOR, because this function
--         RETURNS the anchor it used. Seed month-end checkpoints densely enough
--         to cover all five horizons, then assert
--             delta_nominal = nav_at(anchor_checkpoint_date) - nav_at(current cp)
--         reading BOTH from the fixture by the dates the function REPORTS. The
--         crux arithmetic leg is then fully deterministic and INDEPENDENT OF WHAT
--         DAY IT IS. >> The provenance columns added for the UI turn out to be
--         what makes the battery deterministic; that was not the reason for them,
--         and it is a reason to keep them. <<
--     (c) ANCHOR DERIVATION IS TESTED SEPARATELY AND BY AN INDEPENDENT ROUTE.
--         A small number of legs assert anchor_date itself against month-ends
--         computed in the TEST by different arithmetic than the body uses.
--         ⚠ Do NOT compute the expected anchor with the body's own expression —
--         a shared mistake in month-end derivation would then be invisible,
--         which is testing the implementation against itself.
--   ⚠ `supabase db reset` is PROHIBITED — it destroys F/CTO's local test data.
--   Verify non-destructively (apply-in-txn + rollback).
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- pfin.fn_nav_delta_panel — five fixed horizons, nominal and real-terms, each
-- real-terms figure in dollars AND as a percent of the deflated anchor.
-- See the header for the full contract; inline notes cover only what is not
-- obvious from the code.
--
-- DROP + CREATE, not `create or replace`: the added output column is a
-- return-type change, which `create or replace` refuses. No CASCADE — a
-- dependent object must stop this migration, not be removed by it. The grants
-- and the comment below are re-issued because the DROP destroys both.
-- ----------------------------------------------------------------------------
drop function if exists pfin.fn_nav_delta_panel();

create function pfin.fn_nav_delta_panel()
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

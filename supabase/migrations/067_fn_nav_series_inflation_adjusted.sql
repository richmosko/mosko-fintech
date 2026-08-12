-- ============================================================================
-- Migration: pfin.fn_nav_series_inflation_adjusted — the §2.1.2.c real-terms
--   overlay on the net-worth trend. SECURITY INVOKER read-composition (Lock 11)
--   over TWO existing INVOKER helpers: pfin.fn_nav_series (062) for the nominal
--   series and pfin.fn_cpi_u_index_for_period (066) for every CPI-U level.
--   Linear SELF-218 (V1.1; PRD §2.1.2.c / §2.4.4). apply-migration procedure
--   applied. JOINT-REVIEW-MANDATORY (Sec veto surface): financial calculation +
--   a read path composing a multi-tenant surface. Design brief:
--   temp/architect-self218.md.
--
-- ----------------------------------------------------------------------------
-- RATIFIED SHAPE (F/CTO 2026-08-12), three rulings:
--   (1) RETURN SHAPE = the ELEVEN-column composition-faithful option, gap_class
--       DELIBERATELY EXCLUDED (see EXCLUDED: gap_class).
--   (2) THE DEFLATOR IS EVALUATED AT point_date, not at checkpoint_date.
--   (3) The numerator is resolved through 066's helper, never an inline
--       aggregate over pfin.cpi_u_index.
--
-- ----------------------------------------------------------------------------
-- THE DRAFTED SIGNATURE WAS UNIMPLEMENTABLE, AND THE RECONCILIATION IS RECORDED
--   HERE because AC #1 as written ("signature matches") named three things that
--   do not exist, and a future reader will otherwise re-propose them:
--     · `p_users_id UUID`   — DROPPED. Tenant comes from RLS via auth.uid().
--       Identical disposition to 049 (R2) and 051, whose re-issued comment reads
--       "p_users_id DROPPED (INVOKER + RLS scope by auth.uid())". 062's TENANT
--       FENCE adds the sharper reason: a local tenant predicate makes QA's
--       cross-tenant battery VACUOUS — it stays green over a policy broken open,
--       which QA MEASURED rather than argued.
--     · `p_scope pfin.scope[]` — DROPPED. 049 (R2) and 051 both record that the
--       `pfin.scope` TYPE DOES NOT EXIST; `scope` is a free-text account label
--       per ADR-004, and per-scope reporting is V2+ (PRD §2.1.7).
--     · `pfin.nav_granularity` — DROPPED as a TYPE, kept as the `text` parameter.
--       062's CONTRACT records the F/CTO ratify of 2026-08-07: "NOT an enum type:
--       this schema declares no enum types at all — vocabularies are CHECK
--       constraints or free-text labels".
--   The parameter list is therefore IDENTICAL to 062's, which is the property
--   that makes the pass-through below checkable rather than merely intended.
--
-- ----------------------------------------------------------------------------
-- Numbering: 067 follows 066 (the fn_cpi_u_index_for_period due+coverage
--   reshape), taken at authoring time. Depends AT CALL TIME on 062
--   (pfin.fn_nav_series) and 066 (pfin.fn_cpi_u_index_for_period), and
--   transitively on the relations THOSE read — this file reads NO relation of
--   its own. CREATION is order-independent (a plpgsql body is not resolved
--   against the catalog at create time), but the file is sequenced after 066
--   deliberately so that a clean apply reaches a state where the function is
--   immediately callable. No downstream migration depends on 067.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (Lock 11 read-composition default);
--   NOT SECURITY DEFINER. The function runs as the calling user and inherits
--   their RLS context, exactly as 049 / 051 / 062 / 066 do. It needs no elevated
--   privilege: every row it returns is a row the caller may already obtain by
--   calling 062 and 066 directly, and this function only multiplies two numbers
--   they can already both see. DEFINER would be strictly worse — it would detach
--   the nominal leg from the caller's RLS context and from the 025 aal2 step-up
--   backstop that pfin.nav_daily's SELECT policy carries into 062.
--   THE SECURITY DEFINER ALLOWLIST IS NOT TOUCHED BY THIS MIGRATION — this file
--   authors ONE function and it is INVOKER. Read ADR-011 Decision 9 live for the
--   allowlist's membership; no count is restated here.
--
-- ----------------------------------------------------------------------------
-- TENANT FENCE — INHERITED THROUGH 062, AND NOT RESTATED AS A LOCAL PREDICATE.
--   This function adds NO `users_id = auth.uid()` predicate of its own and MUST
--   NOT GAIN ONE. Isolation comes entirely from pfin.nav_daily's
--   `nav_daily_select` policy (054), reached through 062 under the INVOKER
--   posture. A cross-tenant caller sees ZERO ROWS rather than an error — fails
--   closed, matching 051 / 062.
--   The reason a redundant predicate is FORBIDDEN rather than merely unnecessary
--   is measured, and it was measured on 062 rather than argued: QA built the
--   counterfactual — the same function plus redundant `users_id = auth.uid()`
--   predicates — and ran both under the same sabotage (policy replaced with
--   `using (true)`). The predicate-free function went RED; the redundant-
--   predicate variant stayed GREEN over the removed fence. Adding a "harmless"
--   local predicate HERE would blind the battery in exactly the same way, one
--   function further out.
--   The CPI leg crosses no tenant boundary at all: both tables 066 reads are
--   global public reference with `using (true)` SELECT policies, so there is no
--   tenant predicate on that side to get wrong.
--
--   AAL2 STEP-UP BACKSTOP — INHERITED, NOT RESTATED (C3 standing obligation /
--   ADR-029 / 025). This migration creates NO table and NO policy, so it has no
--   policy of its own to clause. The backstop reaches this surface through
--   nav_daily's SELECT policy, two calls down: a reader whose own mfa_policy is
--   totp/passkey and whose session is not aal2 sees zero rows THROUGH THIS
--   FUNCTION TOO. That is A PROPERTY TO BE ASSERTED, NOT A CLAIM THIS FILE MAY
--   MAKE ON ITS OWN BEHALF — the QA battery below requires the POSITIVE leg
--   (aal2 session returns N > 0) precisely because the negative leg alone passes
--   vacuously on an empty fixture.
--
-- ----------------------------------------------------------------------------
-- COMPOSE, DO NOT EXTEND — why this is a new function and not a wider 062.
--   Adding columns to pfin.fn_nav_series is a RETURN-TYPE change, and PostgreSQL
--   cannot `create or replace` across one. It would require drop-and-recreate,
--   which — as 066 records from performing exactly that — takes the ACL and the
--   catalog comment with it, and it would break 062's published contract for
--   every existing consumer of the nominal series. A second function costs one
--   more object and breaks nothing.
--   THE NOMINAL LEG IS A PURE PASS-THROUGH. nav_nominal and checkpoint_date are
--   062's nav_value and checkpoint_date, unmodified: no re-read of nav_daily, no
--   re-derivation of the bucketing, the carry-forward, or the series bounds.
--   Every property 062's contract states — Option A frozen-checkpoint reads,
--   period-end bucketing, carry-forward-with-provenance, the two-sided evidence
--   bounds, the zero-rows-not-zero-value rule, the fail-loud argument
--   validation — reaches this surface unchanged BECAUSE it is the same code
--   path, not because this file re-implements it faithfully.
--
--   ⚠ WHAT HOLDS THAT, STATED PRECISELY, because 062's own comment had to be
--   corrected for over-claiming the analogous thing. 062 carries a NO-RECOMPUTE
--   FENCE greping ITS OWN prosrc, and 062's comment already concedes that the
--   TRANSITIVE half is "HELD BY REVIEW, NOT BY THE FENCE" — a source grep over
--   one function structurally cannot observe a call through a helper. 067 is
--   precisely the case that concession anticipated: it calls 062, and 062's
--   fence cannot see 067 at all. So the claim "no valuation function is reached
--   on this surface" is TRUE and is held by THIS REVIEW plus the QA
--   passthrough-equality leg — NOT by 062's fence, which does not reach here.
--   Whoever adds a relation read or a helper call to the body below owes that
--   review, because nothing will fail if they skip it.
--
-- ----------------------------------------------------------------------------
-- THE DEFLATOR — WHAT IS DIVIDED BY WHAT, AND WHERE EACH LEG COMES FROM.
--   nav_inflation_adjusted = nav_nominal × (basis CPI ÷ point-period CPI)
--
--   · DENOMINATOR — the CPI-U level for the period containing point_date,
--     obtained by calling 066 with point_date. 066 normalizes to the CPI grain
--     (first-of-month) and RETURNS the normalized period as cpi_period, so the
--     caller is told which month answered rather than having to know.
--   · NUMERATOR — the CPI-U level at the store's trailing coverage edge. AC
--     wording is "the latest CPI-U observation as of invocation time, NOT a
--     user-requested as-of date", and 066 already exposes exactly that edge as
--     coverage_through.
--
--   ⚠ EVALUATED AT point_date, NOT AT checkpoint_date — F/CTO-ratified, and the
--   alternative is defensible enough to be worth recording. When a checkpoint is
--   carried across a cron outage the value was MEASURED at checkpoint_date but
--   is PLOTTED at point_date. Deflating at checkpoint_date matches the economics
--   of that single point better; deflating at point_date keeps every point on
--   the series in the same real-terms basis as its x-axis neighbours, which is
--   what a trend chart is FOR. The second was chosen. The mismatch is not
--   hidden: checkpoint_date is in the return, so a consumer who cares can see
--   exactly which points carry it. Reversible by `create or replace` with no
--   data migration — this is NOT a one-way door.
--
-- ----------------------------------------------------------------------------
-- WHY THE NUMERATOR IS RESOLVED THROUGH 066 AND NEVER BY AN INLINE AGGREGATE.
--   066's comment carries a STANDING REQUIREMENT: "a consumer needing a CPI-U
--   level calls this function; the carry-forward and gap-classification policy
--   MUST NOT be re-derived inline in a consumer (the 019 eod_price
--   LOCF-in-one-helper precedent)." A `max(cpi_period)` written here would be
--   exactly that re-derivation, in the first consumer 066 was built for.
--
--   THE COVERAGE PROBE PASSES A FIXED DATE, AND THAT IS DELIBERATE. 066's own
--   comment states that coverage_through "is the LATEST period present in
--   pfin.cpi_u_index (NULL on an empty store) — a property of the STORE, not of
--   the requested period, and the only such column here." Any non-NULL argument
--   therefore yields the same coverage edge. The body passes the CPI-U series
--   epoch (1913-01) because it is fixed, never NULL, zone-free, and cannot be
--   mistaken for a caller-supplied value. NAMING WHERE THE SUFFICIENCY COMES
--   FROM, per the apply-migration rule: this probe is correct ONLY because
--   coverage_through is store-scoped. That is a change-controlled property of
--   066 (any column-set change there requires Sec re-review + F/CTO ratify + an
--   ADR-049 amendment + a re-granting migration), not an incidental one — but if
--   it ever became period-relative, THIS PROBE SILENTLY BECOMES WRONG and
--   nothing here would fail. That is the standing exposure, stated rather than
--   left for someone to discover.
--
--   ⚠ AND IT IS ALSO WHAT KEEPS THE ARGUMENT-VALIDATION ERRORS HONEST. Passing
--   p_end_date to the probe instead would raise from 066 ("p_period is
--   required") when the caller passed NULL bounds, naming the CPI helper for a
--   defect in the NAV arguments. With a fixed probe argument, 062 remains the
--   sole validator of p_granularity and the date bounds, and the caller gets the
--   error that names their actual mistake.
--
--   ⚠ THE SECOND CALL IS GUARDED, AND THE GUARD IS LOAD-BEARING. On an empty CPI
--   store coverage_through is NULL, and 066 RAISES on a NULL p_period. Calling
--   it unguarded would throw on the empty-store fixture — failing the AC's
--   never-throw requirement through the one path most likely to exist in a fresh
--   environment and least likely to exist in a seeded one.
--
-- ----------------------------------------------------------------------------
-- ZONE NEUTRALITY — NO CLOCK IS CONSULTED, AT ANY DEPTH.
--   The function body performs no date arithmetic whatsoever: it passes dates
--   through and multiplies two numerics. It contains no clock function, no
--   zone-aware timestamp type in EITHER spelling, and no date-literal cast of
--   the kind Sec catalogued as fence evasions on 062. The two callees are
--   likewise clock-free by construction — 066's period_was_due is data-derived
--   rather than calendar-derived precisely so that it "consults no clock at all"
--   (ADR-049 amendment, 2026-08-10), and 062's bounds are expressed against the
--   caller's own max(nav_date).
--   >> "AS OF INVOCATION TIME" IN THE AC IS SATISFIED BY DATA, NOT BY A CLOCK. <<
--   The trailing coverage edge moves when the ETL writes a new print; that is
--   what makes the numerator current, and it needs no notion of today.
--   THIS IS WHY 067 IS NOT A PARTY TO THE OPEN nav_date ZONE ONE-WAY DOOR. 062's
--   header carries an explicit instruction to a future editor: introducing
--   `current_date`, `now()`, `localtimestamp`, or any zone-aware cast makes the
--   surface a party to that still-open decision. 067 only READS nav_date through
--   062 and imprints no convention. KEEP IT THAT WAY.
--
--   ⚠ A NAMING CHOICE MADE FOR THE FENCE, recorded because it looks arbitrary
--   otherwise. The numerator local is named `v_cpi_basis`, NOT `v_cpi_today`.
--   062's near-miss (2) is a body comment that put a forbidden token into prosrc
--   while ARGUING AGAINST that token, and Sec later catalogued `'today'::date`
--   as a live zone-fence evasion. An identifier containing that substring would
--   match a reasonably-written fence and cost someone an investigation to clear.
--   A FILE THAT MUST SURVIVE A TOKEN GREP SHOULD NOT SPEND ITS IDENTIFIERS ON
--   THAT TOKEN. All such discussion lives in this header, which is not prosrc.
--
-- ----------------------------------------------------------------------------
-- THE ELEVEN-COLUMN RETURN, AND WHY THE THREE-COLUMN AC SHAPE WAS RECONCILED UP.
--   SELF-218's AC asks for nominal + adjusted in the same row. Taken literally
--   that is three columns, and three columns would discard BOTH detectability
--   mechanisms this surface sits on top of, at the one place they matter most:
--     · 062's checkpoint_date — "THE DETECTABILITY MECHANISM" for a NAV value
--       carried across a cron outage, in 062's own words.
--     · 066's composite row — whose comment carries a STANDING REQUIREMENT that
--       the return "MUST stay a ROW and MUST NOT be narrowed to a bare scalar:
--       CPI-U is supposed to be monthly-complete, so carrying a value forward
--       silently understates inflation, and the row return is the
--       by-construction mechanism forcing a consumer to project carried-ness
--       away deliberately and visibly rather than merely forget it."
--   A three-column return performs that projection FOR every consumer, silently,
--   inside the function whose entire subject is inflation. F/CTO ratified the
--   wider shape on that ground.
--   EVERY CPI COLUMN IS LOAD-BEARING FOR A RULE THAT ALREADY EXISTS. 066 states
--   the §2.4.4 rendering rule in full — cpi_value NULL renders UNAVAILABLE with
--   a reason; is_carried AND period_was_due renders an INFORMATIONAL marker
--   asserting the span (cpi_period from carried_from) with a cause clause IFF
--   nonpublication_on_record; otherwise the plain figure; and the dated basis
--   line names coverage_through on every path. Without these columns a consumer
--   can neither execute that rule nor legally re-derive it.
--   HONEST COST: eleven columns is a wide contract, and per 066's change-control
--   requirement narrowing it later is a drop-and-recreate plus Sec re-review plus
--   F/CTO ratify. That cost was accepted knowingly, not overlooked.
--
--   EXCLUDED: gap_class — A DECISION, NOT AN OMISSION. 066's contract is
--   explicit that "gap_class IS OPERATOR-AXIS, NOT USER-AXIS" and that "a
--   consumer MUST NOT branch user-visible tiering on gap_class; that is what
--   period_was_due and nonpublication_on_record are for." Passing it through a
--   user-facing read surface would put the branch it forbids one dereference
--   away. An operator who needs the classification calls 066 directly, where it
--   is documented alongside the caveat. Adding gap_class to this return would
--   need the same change-control 066's own column set does.
--
-- ----------------------------------------------------------------------------
-- FAIL-QUIET ON AN UNUSABLE CPI LEG — A DELIBERATE DEPARTURE, AND ITS PRICE.
--   062 and 066 both FAIL LOUD on a caller error, on the stated ground that an
--   empty result is indistinguishable from "this tenant has no data". This
--   function returns NULL nav_inflation_adjusted instead of raising when the CPI
--   leg is unusable, and the two positions are consistent for a reason worth
--   stating: 062/066 fail loud about THE REQUEST; this fails quiet about ONE
--   COLUMN OF ONE ROW, and the row carries its own explanation.
--   >> A NULL IS ONLY ALLOWED TO BE QUIET BECAUSE IT ARRIVES NEXT TO THE REASON
--      IT IS NULL. << cpi_value, cpi_period, cpi_period_was_due,
--      cpi_nonpublication_on_record and cpi_coverage_through are all present on
--      the same row. Strip the CPI columns and this NULL becomes exactly the
--      indistinguishable silence the other two files forbid — which is a second,
--      independent reason the eleven-column shape is not decoration.
--   The row is ALWAYS emitted: nav_nominal survives even when the real-terms
--   figure cannot be computed. Dropping the row would make an unadjustable
--   period vanish from the nominal series too.
--   NEVER A FABRICATED ZERO. ADR-042's "absence is not a value" applies with
--   full force: 0 and "we cannot deflate this point" must not render alike.
--
--   ⚠ THE DUAL — what this makes UNSAFE for a reader elsewhere, asked because
--   the apply-migration procedure requires asking it of every reassurance.
--   nav_inflation_adjusted is NULLABLE BY DESIGN, so a consumer that SUMs, AVGs
--   or MAXes it across the series gets an aggregate that SILENTLY SKIPS the
--   un-deflatable points and reads as though the series were complete. That is
--   the same shape as the hazard 062's header records about the valuation engine
--   (a missing input yielding a confident, plausible, wrong number), one layer
--   up. A consumer aggregating this column MUST decide explicitly what a NULL
--   point means to the aggregate; this function cannot decide it for them, and
--   nothing here will fail if they do not.
--
-- ----------------------------------------------------------------------------
-- DIVISION SAFETY — AND A FENCE GAP IN 053 THAT THIS FILE ROUTES AROUND.
--   The ratio divides by the point-period CPI level. 053's
--   `cpi_u_index_value_finite` CHECK bars NaN and ±Infinity on cpi_value, and
--   053 declares the column NOT NULL — but IT DOES NOT BAR ZERO OR NEGATIVE
--   VALUES. A poisoned `0` print is therefore admissible today, and an
--   unguarded ratio would raise `division by zero`, breaking the never-throw
--   requirement through a path no existing fence closes.
--   The body computes the ratio ONLY when BOTH CPI legs are strictly positive,
--   and returns NULL otherwise. A negative level is barred by the same guard:
--   it is not a division hazard but it would silently flip the sign of a
--   net-worth figure, which is worse than an error.
--   >> THIS IS A ROUTE-AROUND, NOT A FIX. The authoritative repair is a
--      positivity CHECK on pfin.cpi_u_index.cpi_value, which cannot be added by
--      editing a merged file and touches a table the ETL writes — it needs its
--      own migration and its own review. Recorded as a follow-up rather than
--      bundled here. The guard below is correct with or without it. <<
--   ⚠ INSTRUCTION TO WHOEVER LANDS THAT CHECK: keep the QA leg that asserts a
--   zero print yields NULL rather than a raise. It becomes unreachable-by-
--   construction, which is a reason to keep it, not to delete it — deleting it
--   is how the guard silently stops being tested if the CHECK is ever relaxed.
--
-- ----------------------------------------------------------------------------
-- COST SHAPE — ONE HELPER CALL PER POINT, AND WHY THAT IS ACCEPTED RATHER THAN
--   UNNOTICED. The lateral invokes 066 once per emitted point, and each
--   invocation scans the CPI store's min/max. The work is therefore
--   O(points × |cpi_u_index|), and the CPI grain is MONTHLY while 'daily'
--   granularity emits one point per day — so a daily request re-resolves the
--   same month up to thirty-one times.
--   WHAT BOUNDS IT: the point count is not caller-controlled. 062's expansion
--   clamp (its Sec joint-review Condition 1) restricts the series to the
--   CALLER'S OWN checkpoint extent, so an adversarial millennium-wide request
--   cannot inflate this loop — it is bounded by rows that tenant actually owns,
--   and the series is forward-only from the first cron run.
--   THE OPTIMIZATION DELIBERATELY NOT TAKEN, so it is not mistaken for an
--   oversight: resolving 066 once per DISTINCT MONTH instead of once per point
--   would require normalizing point_date to first-of-month HERE, which means a
--   date_trunc and a cast in this body — re-deriving a piece of the helper's own
--   grain logic and putting date arithmetic back into a function that currently
--   has none. The trade was refused at this size and SHOULD BE REVISITED if the
--   daily series grows long enough to matter; revisiting it re-opens the zone
--   question for this file, which is the real cost, not the SQL.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_nav_series_inflation_adjusted(p_granularity text, p_start_date date,
--                                         p_end_date date)
--     RETURNS TABLE (point_date date, nav_nominal numeric, checkpoint_date date,
--                    nav_inflation_adjusted numeric, cpi_period date,
--                    cpi_value numeric, cpi_is_carried boolean,
--                    cpi_carried_from date, cpi_period_was_due boolean,
--                    cpi_nonpublication_on_record boolean,
--                    cpi_coverage_through date)
--     — SECURITY INVOKER, STABLE, set search_path = ''.
--   · Parameters are 062's, unchanged, and are validated BY 062: p_granularity ∈
--     {'monthly','weekly','daily'} or RAISE; NULL or inverted date bounds RAISE.
--     This function adds no validation of its own — re-validating would put the
--     granularity vocabulary in a second place, which is the drift 066's
--     period_was_due column exists to prevent one level down.
--   · ONE ROW PER POINT of 062's series, in 062's order (ascending point_date),
--     never more and never fewer. 066 returns exactly one row for any non-NULL
--     period, so the lateral cannot drop or duplicate a point.
--   · point_date / nav_nominal / checkpoint_date — 062's point_date / nav_value /
--     checkpoint_date, passed through unmodified. Consumers SHOULD surface NAV
--     staleness when checkpoint_date <> point_date, exactly as on 062.
--   · nav_inflation_adjusted — nav_nominal restated in the purchasing power of
--     cpi_coverage_through. UNROUNDED: full numeric precision is returned and
--     presentation rounding is the consumer's. NULL — never zero — when either
--     CPI leg is absent or non-positive.
--   · cpi_* — 066's row for point_date, prefixed, MINUS gap_class (see EXCLUDED).
--     cpi_period is point_date normalized to first-of-month.
--   · cpi_coverage_through is a property of the CPI STORE, identical on every
--     row, and is the period whose price level the adjusted figure is expressed
--     in. It carries §2.4.4's dated basis line. IT IS A DISCLOSURE, NOT A
--     FRESHNESS MONITOR — 066 is explicit that it "does not substitute for" ingest
--     freshness monitoring, and composing it into a wider row does not upgrade it.
--   · Ordering: ascending by point_date. Callers may rely on it.
--   · Security-load-bearing edges: RLS on pfin.nav_daily, reached through 062, is
--     the SOLE tenant fence (no local predicate — see TENANT FENCE); a
--     cross-tenant caller gets zero rows, fails closed; the 025 aal2 backstop is
--     inherited through that same policy; the CPI leg crosses no tenant boundary;
--     the strictly-positive guard is what keeps a poisoned CPI print from
--     raising or from flipping a sign; NULL is the fail-quiet outcome and is
--     legible only because the CPI provenance columns accompany it; no clock is
--     consulted at any depth; `set search_path = ''` fences search_path
--     injection and every object reference below is schema-qualified.
--   ⚠ WHAT THIS FUNCTION DELIBERATELY DOES NOT DO: it does not read any relation
--     directly; it does not extend, backfill or interpolate 062's series; it does
--     not detect a stalled ingest; it does not decide what the USER sees — it
--     supplies the signals the presentation layer renders under §2.4.4's rule.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; the catalogued
--   numbered list is NOT restated here and no count is stated. Decision 4 read
--   VERBATIM at the canonical anchor before drafting, 2026-08-12.)
--   (i)   Instance-numbering: nothing appended, reordered, or renumbered.
--   (ii)  Layer-attribution: fn_nav_series_inflation_adjusted is an INVOKER read
--         helper reached by `authenticated` over PostgREST. It is NOT the
--         PDF-worker container credential audit (it is not a container), NOT the
--         code-layer SUPABASE_SERVICE_ROLE_KEY allowlist fence (it holds and
--         needs no key — it runs as the caller, which is the point of INVOKER),
--         and NOT the app→worker credential-admission network surface (there is
--         no worker in this path). No catalogued instance's layer attribution
--         moves; no surface becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is REFERENCED, not restated. This
--         file is not the canonical anchor and never will be.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED set are DIFFERENT SETS and are
--   NOT reconciled here. This migration touches neither.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — +0. This migration creates NO
--   table, NO column, and NO FK-shaped reference of any kind (single FK, self-FK,
--   or INTEGER[] array element). A function has nothing to matched-tenant-
--   validate. Non-membership also holds on the second, independent ground ADR-049
--   Decision 1 records for the CPI surfaces: the reference tables are global, so
--   there is no tenant boundary to bypass even if such a column existed.
--   AUTHORING-TIME PROVENANCE (dated, not live state — read ADR-011 Decision 3's
--   body live, it grows and its labels are non-contiguous): read verbatim at the
--   canonical anchor on 2026-08-12, the family stood at SIXTEEN LABELED
--   INSTANCES (#1–#16), THIRTEEN DDL-REALIZED — #5 DROPPED at 048, #3 + #4
--   canonically-locked but DDL-deferred, #17 never allocated. That figure is
--   recorded here as a dated observation ONLY; it is NOT restated in the
--   `comment on` below, and it must not be copied forward.
--
-- ----------------------------------------------------------------------------
-- LEDGER DELTAS (all confirmed FLAT, stated as deltas): §10 catalogued instances
--   +0 · SECURITY DEFINER allowlist +0 · ADR-011 Decision 3 family +0 · SD matrix
--   — NO expansion (no new relation, no new credential surface, no new write
--   path). Sec joint-review is MANDATORY notwithstanding the flat ledgers, on the
--   two grounds 066 recorded for itself and which both apply here with more
--   force: this IS the inflation-adjusted financial figure 066 only supplied an
--   input to, and it composes a MULTI-TENANT read path (062 over pfin.nav_daily)
--   that 066 did not touch.
--
-- ----------------------------------------------------------------------------
-- QA TEST-PAIRING (QA-owned — Architect does not author supabase/tests/). Ships
--   SAME-PR. Each item names the negative that would ACTUALLY FIRE; a fixture
--   that cannot fail is not a test.
--   1. TWO-TENANT, NON-VACUOUSLY: seed tenants A and B with checkpoints on the
--      SAME nav_date carrying DIFFERENT nav_value; assert A's call returns A's
--      adjusted figures. A same-value or single-tenant fixture passes under a
--      BROKEN predicate — the varied value is the entire test.
--   2. Cross-tenant call returns ZERO ROWS, not an error (fails closed).
--   3. AAL2 BACKSTOP FIRES — BOTH legs. Seed a tenant with mfa_policy 'totp' AND
--      real checkpoints; assert an aal1 session gets 0 rows AND an aal2 session
--      gets N > 0. Without the N > 0 leg the assertion passes on an empty
--      fixture and proves nothing.
--   4. THE ARITHMETIC IS REAL: a fixture where the basis CPI and the point CPI
--      DIFFER, with the expected adjusted value computed independently of the
--      function. ⚠ A fixture whose CPI levels are equal cannot distinguish a
--      correct implementation from one that returns nav_nominal unchanged — it
--      is the CPI analogue of the same-value tenant fixture in item 1.
--   5. MISSING CPI YIELDS NULL, NOT A THROW AND NOT A ZERO: a point_date before
--      CPI coverage returns nav_inflation_adjusted IS NULL with nav_nominal
--      INTACT on the same row. ⚠ ASSERT THE ROW EXISTS — an implementation that
--      dropped the row would pass a NULL-only assertion vacuously.
--   6. EMPTY CPI STORE: every row returns NULL adjusted and no raise. This is
--      the leg that fires if the coverage-probe NULL guard is ever removed, and
--      it is the state a fresh environment is actually in.
--   7. ZERO / NEGATIVE CPI DOES NOT RAISE: insert a 0 print (053 admits one
--      today) and assert NULL rather than `division by zero`; likewise a
--      negative print yields NULL rather than a sign-flipped figure. See
--      DIVISION SAFETY for why this leg must SURVIVE a future positivity CHECK
--      on 053 rather than be retired by it.
--   8. CARRIED CPI IS SURFACED, NOT SILENTLY APPLIED: a point_date inside a CPI
--      gap returns cpi_is_carried true with cpi_carried_from < cpi_period, and
--      the adjusted value uses the carried print. This is the leg that fires
--      when a future "simplification" narrows the return.
--   9. NOMINAL PASS-THROUGH IS EXACT: nav_nominal and checkpoint_date are
--      IDENTICAL to pfin.fn_nav_series(...) over the same arguments, row for row
--      and in the same order. This is the leg that catches a re-implementation
--      of the checkpoint read in place of a call into 062 — the property 062's
--      own prosrc fence structurally cannot observe from where it sits.
--  10. FAIL-LOUD IS INHERITED: an unknown p_granularity and NULL or inverted
--      date bounds still RAISE, and the raise names fn_nav_series. Assert on the
--      raise, not merely on emptiness.
--  11. ZONE INVARIANCE — THE PROPERTY, NOT A TOKEN PROXY. Run the function twice
--      over the SAME fixture under two extreme session TimeZones and assert the
--      output is BYTE-IDENTICAL. 062's near-miss (9) establishes that a token
--      deny-list is "exhortation wearing a regex"; keep token legs (either
--      spelling of the zone-aware type, and the clock functions) only as the
--      cheap secondary that localises a failure.
--  12. ACL: EXECUTE is revoked from PUBLIC and granted to `authenticated`, and
--      is NOT held by service_role. Assert on pg_proc.proacl, not on a
--      successful call.
--  13. ADR-040 ASSEMBLED-STATEMENT DISCIPLINE: execute the EXACT production
--      statement text — the real PostgREST-shaped call under the real
--      `authenticated` role with a real JWT claim — against a live database in a
--      ROLLED-BACK transaction. Not an approximation.
--   ⚠ `supabase db reset` is PROHIBITED here — it destroys the F/CTO's active
--   local test data. Verify non-destructively (apply-in-txn + rollback).
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- pfin.fn_nav_series_inflation_adjusted — §2.1.2.c real-terms overlay
-- (SELF-218). Composes 062 (nominal series) with 066 (CPI-U levels); reads no
-- relation directly. See the header for the full contract; the notes inline
-- below cover only what is not obvious from the code itself.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_nav_series_inflation_adjusted(
  p_granularity text,
  p_start_date  date,
  p_end_date    date
)
returns table (
  point_date                    date,
  nav_nominal                   numeric,
  checkpoint_date               date,
  nav_inflation_adjusted        numeric,
  cpi_period                    date,
  cpi_value                     numeric,
  cpi_is_carried                boolean,
  cpi_carried_from              date,
  cpi_period_was_due            boolean,
  cpi_nonpublication_on_record  boolean,
  cpi_coverage_through          date
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
-- Several RETURNS TABLE output names (point_date / checkpoint_date / cpi_period /
-- cpi_value) collide with output column names of the two functions being called.
-- Every reference below is alias-qualified, and this directive makes the
-- resolution explicit rather than incidental: an ambiguous bare name resolves to
-- the COLUMN, never to the output variable. Without it a future unqualified
-- reference would fail at runtime with "column reference is ambiguous" instead of
-- doing the obvious thing. The three p_* parameters and the two v_* locals match
-- no column name, so they are unaffected.
#variable_conflict use_column
declare
  -- The CPI store's trailing coverage edge, and the index level at that edge.
  -- Together they are the numerator of the deflator: every point in the series
  -- is restated into the purchasing power of this one period.
  v_coverage  date;
  v_cpi_basis numeric;
begin
  -- ---------------------------------------------------------------------
  -- (1) RESOLVE THE COVERAGE EDGE through the sanctioned helper. No aggregate
  -- over the CPI table is written here, and none may be added: the carry-forward
  -- and gap policy lives in exactly one place by standing requirement.
  -- The argument is FIXED at the CPI-U series epoch, not derived from the
  -- caller's bounds, for two reasons stated fully in the header: coverage is a
  -- property of the STORE rather than of the requested period, and a fixed
  -- argument leaves 062 as the sole validator of the caller's parameters, so a
  -- NULL date bound raises an error that names the right function.
  -- ---------------------------------------------------------------------
  select h.coverage_through into v_coverage
  from pfin.fn_cpi_u_index_for_period(date '1913-01-01') h;

  -- ---------------------------------------------------------------------
  -- (2) RESOLVE THE BASIS LEVEL — GUARDED. On an empty store the coverage edge
  -- is NULL and the helper RAISES on a NULL period, so this call must not be
  -- reached in that state. v_cpi_basis then stays NULL and every adjusted figure
  -- below resolves to NULL, which is the reported outcome, not a swallowed
  -- error.
  -- ---------------------------------------------------------------------
  if v_coverage is not null then
    select h.cpi_value into v_cpi_basis
    from pfin.fn_cpi_u_index_for_period(v_coverage) h;
  end if;

  -- ---------------------------------------------------------------------
  -- (3) EMIT. One row per point of 062's series, in 062's order. The lateral
  -- call returns exactly one row for any non-NULL period, so it can neither drop
  -- a point nor duplicate one; point_date is non-NULL for every row 062 emits.
  -- If the caller's arguments are invalid, 062 raises here and this function
  -- never returns — which is the intended, inherited fail-loud behaviour.
  -- ---------------------------------------------------------------------
  return query
  select
    s.point_date,
    s.nav_value,
    s.checkpoint_date,
    -- THE DEFLATOR. Both legs must be strictly positive: zero would raise, and a
    -- negative would flip the sign of a net-worth figure silently, which is
    -- worse. 053 bars NaN and infinities on cpi_value but NOT zero or negatives,
    -- so this guard is load-bearing rather than defensive-by-habit — see
    -- DIVISION SAFETY. NULL, never 0: "we cannot deflate this point" and "the
    -- real-terms value is zero" must not render identically.
    case
      when v_cpi_basis is null or v_cpi_basis <= 0 then null::numeric
      when c.cpi_value  is null or c.cpi_value  <= 0 then null::numeric
      else s.nav_value * (v_cpi_basis / c.cpi_value)
    end,
    -- The CPI provenance the consumer needs to render §2.4.4's rule. gap_class is
    -- deliberately not projected: it is operator-axis, and forwarding it here
    -- would put a forbidden user-visible branch one dereference away.
    c.cpi_period,
    c.cpi_value,
    c.is_carried,
    c.carried_from,
    c.period_was_due,
    c.nonpublication_on_record,
    c.coverage_through
  from pfin.fn_nav_series(p_granularity, p_start_date, p_end_date) s
  cross join lateral pfin.fn_cpi_u_index_for_period(s.point_date) c
  order by s.point_date;
end;
$$;

-- ⚠ REVOKE FIRST, AND NOT AS BOILERPLATE. PostgreSQL grants EXECUTE to PUBLIC by
-- default on a freshly created function, so without the revoke this migration
-- would ship a financial read surface executable by every role — and it would
-- look exactly like a successful no-op. The grant that follows is then the whole
-- of the access rather than an addition on top of an implicit one (054's
-- discipline). anon is denied earlier by schema USAGE, but that is a second
-- fence, not this one.
--
-- ⚠ service_role IS DELIBERATELY NOT GRANTED, and here that is stronger than a
-- least-privilege preference: BOTH CALLEES ARE `authenticated`-ONLY. A
-- service_role grant on this function would be a promise the composition cannot
-- keep — the call would reach the body and then fail inside 062 or 066 with
-- `permission denied for function`, which is a worse outcome than being denied at
-- the door. The fix for a caller hitting that is `set role authenticated` (the
-- worker identity is a member of both roles and is NOINHERIT, so it must set the
-- role explicitly), NOT widening this grant. Per ADR-023's ETL read-role
-- amendment Step 0, pure-global reads execute under `authenticated`; the nominal
-- leg is tenant-scoped and belongs under the caller's own identity for the same
-- reason. Widening EXECUTE on a function producing an inflation-adjusted
-- net-worth figure is an ACL change on a financial surface and routes to Sec
-- re-review; it does not ride along with an unrelated migration.
revoke execute on function pfin.fn_nav_series_inflation_adjusted(text, date, date) from public;
grant  execute on function pfin.fn_nav_series_inflation_adjusted(text, date, date) to authenticated;

comment on function pfin.fn_nav_series_inflation_adjusted(text, date, date) is
  'SECURITY INVOKER §2.1.2.c inflation-adjusted net-worth-trend read surface (V1.1; PRD §2.1.2.c + §2.4.4 / SELF-218; '
  'ADR-011 Lock 11 read-composition). Returns TABLE(point_date date, nav_nominal numeric, checkpoint_date date, '
  'nav_inflation_adjusted numeric, cpi_period date, cpi_value numeric, cpi_is_carried boolean, cpi_carried_from date, '
  'cpi_period_was_due boolean, cpi_nonpublication_on_record boolean, cpi_coverage_through date), ordered ascending by '
  'point_date. STABLE, set search_path = ''''. '
  'COMPOSES TWO EXISTING INVOKER HELPERS AND READS NO RELATION DIRECTLY: pfin.fn_nav_series (062) supplies the nominal '
  'series, pfin.fn_cpi_u_index_for_period (066) supplies every CPI-U level. nav_nominal and checkpoint_date are 062''s '
  'nav_value and checkpoint_date PASSED THROUGH UNMODIFIED — Option A frozen-checkpoint reads, period-end bucketing, '
  'carry-forward-with-provenance, the two-sided evidence bounds and the fail-loud argument validation all reach this '
  'surface because it is the same code path, not because this function re-implements them. Consumers SHOULD surface NAV '
  'staleness when checkpoint_date <> point_date, exactly as on 062. '
  'PARAMETERS ARE 062''s, UNCHANGED, AND ARE VALIDATED BY 062: p_granularity is one of ''monthly'' / ''weekly'' / ''daily'' '
  'and raises otherwise; NULL or inverted date bounds raise. This function adds no validation of its own, deliberately — a '
  'second copy of the granularity vocabulary is the drift 066''s period_was_due column exists to prevent one level down. '
  'THE DRAFTED SIGNATURE WAS RECONCILED AT F/CTO RATIFY 2026-08-12 and the three dropped items are recorded so they are not '
  're-proposed: p_users_id DROPPED (INVOKER + RLS scope by auth.uid(); the 049 / 051 disposition), p_scope DROPPED (the '
  'pfin.scope TYPE DOES NOT EXIST — scope is a free-text account label per ADR-004, and per-scope reporting is V2+), and the '
  'granularity enum DROPPED as a type but kept as text (this schema declares no enum types; vocabularies are CHECK '
  'constraints or free-text labels). '
  'THE DEFLATOR: nav_inflation_adjusted = nav_nominal x (CPI-U at cpi_coverage_through / CPI-U at cpi_period), UNROUNDED — '
  'full numeric precision is returned and presentation rounding is the consumer''s. EVALUATED AT point_date, NOT at '
  'checkpoint_date (F/CTO-ratified): a carried checkpoint was measured earlier than it is plotted, and keeping every point '
  'on one x-axis-aligned basis is what makes a trend chart comparable; the mismatch stays visible because checkpoint_date '
  'is returned. THE NUMERATOR IS THE STORE''S TRAILING COVERAGE EDGE, resolved through 066 and never by an inline aggregate '
  'over pfin.cpi_u_index — 066 carries the STANDING REQUIREMENT that the carry-forward and gap-classification policy MUST '
  'NOT be re-derived in a consumer. NO CLOCK IS CONSULTED AT ANY DEPTH: "as of invocation time" is satisfied by DATA (the '
  'coverage edge moves when the ETL writes a new print), which is what keeps this surface off the open one-way door over '
  'which zone pfin.nav_daily.nav_date derives in. A future editor MUST NOT introduce current_date, now(), localtimestamp, '
  'or any zone-aware cast here. '
  'nav_inflation_adjusted IS NULL — NEVER ZERO, AND NEVER A RAISE — when either CPI leg is absent or non-positive; the row '
  'is still emitted with nav_nominal intact, because dropping it would make an un-deflatable period vanish from the nominal '
  'series too. THE NULL IS ONLY LEGIBLE BECAUSE THE CPI PROVENANCE COLUMNS ARRIVE WITH IT: strip them and this becomes the '
  'indistinguishable silence 062 and 066 both fail loud to avoid. ⚠ CONSEQUENCE FOR CONSUMERS, since nothing enforces it: '
  'the column is NULLABLE BY DESIGN, so SUM / AVG / MAX over the series SILENTLY SKIPS un-deflatable points and reads as if '
  'the series were complete. A consumer aggregating it MUST decide explicitly what a NULL point means to the aggregate. '
  'STANDING REQUIREMENT — the CPI columns MUST NOT be narrowed away. They are 066''s row minus gap_class, and they exist to '
  'let a consumer execute the PRD §2.4.4 rendering rule 066 states in full (cpi_value NULL renders UNAVAILABLE with a '
  'reason; cpi_is_carried AND cpi_period_was_due renders an INFORMATIONAL marker asserting the span, cpi_period from '
  'cpi_carried_from, with a cause clause IFF cpi_nonpublication_on_record; otherwise the plain figure; the dated basis line '
  'names cpi_coverage_through on every path). Narrowing this return would force a consumer either to abandon that rule or '
  'to re-derive the gap policy locally, which 066 forbids. '
  'gap_class IS DELIBERATELY NOT PROJECTED: 066''s contract states it is OPERATOR-AXIS, NOT USER-AXIS, and that a consumer '
  'MUST NOT branch user-visible tiering on it. An operator who needs the classification calls 066 directly. '
  'cpi_coverage_through is a property of the CPI STORE, identical on every row, and is the period whose price level the '
  'adjusted figures are expressed in. It is a DISCLOSURE, NOT a freshness monitor — 066 is explicit that the dated basis '
  'line does not substitute for ingest-freshness monitoring, and composing it into a wider row does not upgrade it. '
  'DIVISION SAFETY: the ratio is computed only when BOTH CPI legs are strictly positive. pfin.cpi_u_index''s finiteness '
  'CHECK bars NaN and the infinities but NOT zero or negative values, so this guard closes a real path — a zero print '
  'would raise, and a negative one would flip the sign of a net-worth figure silently. A positivity CHECK on that column '
  'is the authoritative repair and is a separate vehicle; this guard is correct with or without it, and the paired QA leg '
  'MUST survive it rather than be retired by it. '
  'TENANT FENCE: RLS on pfin.nav_daily, inherited through 062, is the SOLE mechanism — this function adds no users_id '
  'predicate of its own and MUST NOT GAIN ONE. QA MEASURED on 062 that a redundant local predicate keeps the cross-tenant '
  'battery GREEN over a policy broken open with using(true), so the omission is load-bearing rather than merely tidy. '
  'Cross-tenant caller sees zero rows (fails closed). The 025 aal2 step-up backstop is INHERITED through that same policy '
  'and reaches this surface too; the paired battery is required to assert BOTH legs, since the negative alone passes '
  'vacuously on an empty fixture. The CPI leg crosses no tenant boundary — both tables 066 reads are global public '
  'reference with using(true) SELECT policies. '
  'REACHES NO VALUATION FUNCTION, so no unpriced-asset zero-fabrication path exists here. ⚠ MIND WHAT HOLDS THAT: 062''s '
  'no-recompute fence greps 062''s OWN prosrc and structurally cannot observe this function, which 062''s own comment '
  'anticipates in conceding that the transitive half is HELD BY REVIEW, NOT BY THE FENCE. Whoever adds a relation read or a '
  'helper call to this body owes that review, because nothing will fail if they skip it. '
  'COMPOSE, DO NOT EXTEND: widening 062 instead would have been a return-type change, which cannot be a create-or-replace '
  'and whose drop-and-recreate takes the ACL and the catalog comment with it while breaking 062''s published contract. '
  'SECURITY INVOKER — NOT a DEFINER allowlist entry, and this migration authors no DEFINER function; read ADR-011 '
  'Decision 9 live for the allowlist. §10 catalogued ledger UNCHANGED BY THIS OBJECT — and NO COUNT IS STATED HERE, '
  'deliberately; a ledger-impact claim is AUTHORING-TIME PROVENANCE and belongs in a migration header, which is a dated '
  'artifact, not in a catalog comment, which reads as LIVE STATE. Read ADR-011 Decision 4 live. Decision-3 unchanged (this '
  'migration creates no table, column, or FK-shaped reference). EXECUTE revoked from PUBLIC, granted to authenticated; '
  'service_role deliberately NOT granted — both callees are authenticated-only, so the grant would be a promise this '
  'composition cannot keep, and the fix for a blocked caller is `set role authenticated`, not a wider grant. '
  'Sec joint-review-mandatory: this IS the inflation-adjusted financial figure 066 only supplied an input to, and it '
  'composes a multi-tenant read path 066 did not touch. RLS verification -> SELF-218 two-tenant battery.';

-- ============================================================================
-- Migration: pfin.cpi_u_index positivity fence + the 067 deflator-guard
--   hardening it stands behind. Linear SELF-343 (V1.3). Source of record:
--   BACKLOG.md §7.14, first entry ("053 positivity CHECK on
--   pfin.cpi_u_index.cpi_value") and its two later sub-bullets. Sec's FOUR
--   BINDING CONDITIONS are discharged here, all four, no substitutions.
--   JOINT-REVIEW-MANDATORY (Sec veto surface): this is a financial-correctness
--   constraint on the DIVISOR of every inflation-adjusted figure in V1.
--
-- Numbering: 095 — next free number at authoring time, not reserved ahead.
--   Order-dependent on TWO merged migrations and must sort after both:
--   053 creates pfin.cpi_u_index and its cpi_u_index_value_finite CHECK, and
--   067 creates pfin.fn_nav_series_inflation_adjusted, whose body and catalog
--   comment this file replaces. Neither merged file is edited — the vehicle for
--   a constraint change and for text WITH a database representation is a new
--   migration (apply-migration Step 1.6 case (A)).
--
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT
--   SECURITY DEFINER. This migration authors no function. It RE-ISSUES one
--   existing INVOKER function unchanged in signature, posture, volatility and
--   search_path, and adds one table CHECK. The SECURITY DEFINER allowlist is
--   untouched — read ADR-011 Decision 9 live.
--
-- CONTRACT
--   pfin.cpi_u_index.cpi_value — gains one table CHECK,
--     cpi_u_index_value_positive_finite: FINITE AND STRICTLY POSITIVE.
--     ADDITIVE. cpi_u_index_value_finite survives BY NAME, untouched.
--   pfin.fn_nav_series_inflation_adjusted(text, date, date) — create-or-replace.
--     Signature, return shape, ordering, STABLE volatility, SECURITY INVOKER,
--     `set search_path = ''` and ACL all UNCHANGED. The ONLY behavioural change
--     is inside the deflator CASE: the two strictly-positive legs gain explicit
--     NaN and +Infinity clauses. Output moves for exactly one class of input —
--     a NaN or +Infinity CPI level, which this migration's own CHECK now makes
--     unreachable through the table — and moves it from a poisoned or
--     collapsed figure to NULL, which is the surface's documented "cannot
--     deflate" state. No row is added or dropped.
--
-- ----------------------------------------------------------------------------
-- SEC'S FOUR BINDING CONDITIONS — where each is discharged in this file.
--   (1) FINITE AND STRICTLY POSITIVE, not a bare `> 0`. STEP 2's predicate is
--       `cpi_value > 0 AND cpi_value <> 'NaN' AND cpi_value <> 'Infinity'`.
--       A bare `> 0` re-admits both: PostgreSQL numeric ordering places NaN
--       and +Infinity ABOVE every finite value, so `NaN > 0` and
--       `'Infinity' > 0` are both TRUE. -Infinity needs no clause — it sorts
--       BELOW every finite value and `> 0` rejects it.
--   (2) ADDITIVE. STEP 2 issues `drop constraint if exists` for the NEW name
--       ONLY (the 011 / 028 / 085 re-apply idiom). cpi_u_index_value_finite is
--       never dropped, never replaced, never folded in, and this file contains
--       no statement naming it as a drop target.
--       ⚠ The widening on record (Sec, SELF-221) names 054's
--       nav_daily_value_finite under the same additive requirement. THIS
--       MIGRATION DOES NOT TOUCH 054, pfin.nav_daily, or that constraint, and
--       states nothing about them beyond what 054's own file states.
--   (3) SAME MIGRATION: the 067 guard gains its explicit NaN clause AND its
--       `comment on function` is RE-ISSUED. create-or-replace preserves BOTH
--       the ACL and the comment. The first is desirable and is why no grant is
--       re-issued here. The second is a HAZARD: without STEP 4 the catalog
--       would keep a DIVISION SAFETY paragraph describing a guard the function
--       no longer has, and naming a "separate vehicle" that is this file.
--   (4) QA owns the corrupt-the-control leg (drop-in-savepoint / seed poison /
--       assert NULL / rollback) — NOT authored here; supabase/tests/ is
--       QA-owned. What this file owes QA is stated in the QA TEST-PAIRING
--       block below, including the one detail that silently degrades the leg.
--
-- ----------------------------------------------------------------------------
-- BLAST RADIUS — the three dependents of 053's finiteness CHECK, plus one
--   finding this migration CREATES and does not fix.
--   Every dependent guards its CPI legs with a strictly-positive test, which is
--   a NaN/+Infinity guard ONLY because a finiteness CHECK stands behind it.
--   This migration is ADDITIVE, so that CHECK still stands and every
--   dependent's guard remains sound — strengthened, never weakened.
--     · 067 fn_nav_series_inflation_adjusted — guard hardened here; catalog
--       comment re-issued here. Assumptions TRUE at the end of this file.
--     · 071 fn_nav_delta_panel — `> 0` on all three CPI legs; sound, unchanged.
--     · 073 fn_nav_reference_dates — `> 0` on both legs; sound, unchanged.
--   ⚠ FINDING THIS MIGRATION CREATES, RECORDED HERE BECAUSE IT IS NOT FIXED
--     HERE. Three catalog comments state their guards' soundness with the
--     clause "053 bars NaN and the infinities but NOT zero or negative values."
--     One of them (067's) is corrected in STEP 4. The other two are on
--     pfin.fn_nav_delta_panel (live text issued by 072, not 071 — 072
--     drop-and-recreates that function) and on pfin.fn_nav_reference_dates
--     (073). Their CONCLUSIONS stay true; the PREMISE goes stale the moment
--     this file applies. Correcting them is the 052 comment-only shape on two
--     objects this migration otherwise does not touch, and the §7.16 precedent
--     for exactly this class is to FOLD the correction into the next
--     comment-touching migration on the object rather than spend a migration
--     on it alone — 072 already carries a booked correction waiting on that
--     same vehicle. Booked, not silently left: routed to team-lead in the
--     SELF-343 hand-off. No runtime effect.
--   ⚠ SECOND, SMALLER: 067's own file-header DIVISION SAFETY block still reads
--     "IT DOES NOT BAR ZERO OR NEGATIVE VALUES ... admissible today". That text
--     has NO database representation, so this migration cannot reach it; under
--     apply-migration Step 1.6 case (B) it is correctable in place at the next
--     touch of that file, and under the point-in-time reading it is a dated
--     authoring-time record that stays true of its own moment. The choice
--     between those two dispositions is not this file's to make. Also routed.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (ADR-011 Decision 4 read VERBATIM and LIVE before
--   drafting). Instance-numbering: no catalogued instance added, reordered or
--   renumbered. Layer-attribution: nothing re-attributed; no surface becomes
--   "four-layer". Verbatim-vs-paraphrase: the catalogued list is LINKED, never
--   restated (Path B) — and no count appears in any comment this file issues.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED set are different sets and are
--   not reconciled here. ADR-011 Decision 3 family: +0 — this migration creates
--   no table, no column, and no FK-shaped reference of any kind (single FK,
--   self-FK, or INTEGER[]), so no matched-tenant validation is owed and none is
--   authored. RLS surface UNEXTENDED: no policy is created, altered or dropped;
--   pfin.cpi_u_index keeps its using(true) global-reference SELECT policy and
--   its 025 aal2 EXCLUSION under reason (i), global shared-read. No GRANT or
--   REVOKE is issued.
--
-- ----------------------------------------------------------------------------
-- QA TEST-PAIRING (QA-owned — Architect does not author supabase/tests/).
--   1. THE CHECK REJECTS AND ACCEPTS. Poison values, each on its own attempt:
--      0, -1, 'NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric — every
--      one must raise 23514. Then a normal print (e.g. 300.000) must INSERT.
--      ⚠ The accepting leg is not optional: a constraint that rejects
--      everything passes every rejection assertion.
--      ⚠ MEASURED, AND IT CHANGES WHAT AN ASSERTION ON THE CONSTRAINT NAME
--      PROVES: with both constraints in place, NaN and ±Infinity are rejected
--      by cpi_u_index_value_finite, NOT by the constraint this migration adds
--      — it is evaluated first. A leg asserting "the new constraint rejects
--      NaN" by name therefore FAILS on correct DDL. To attribute those three
--      values to the NEW constraint, drop cpi_u_index_value_finite inside a
--      savepoint first; measured then, all three are rejected by
--      cpi_u_index_value_positive_finite (-Infinity via `> 0`).
--      ⚠ Dropping a constraint on this table requires TABLE OWNERSHIP, which
--      the `postgres` role does not hold here — the owner is supabase_admin.
--      Any corrupt-the-control leg must run under a role that owns the table.
--   2. THE CORRUPT-THE-CONTROL LEG on 067, per condition (4) and 067's own
--      header rule that unreachable-by-construction is a reason to KEEP a leg.
--      ⚠ THE DETAIL THAT SILENTLY DEGRADES IT: drop BOTH
--      cpi_u_index_value_positive_finite AND cpi_u_index_value_finite inside
--      the savepoint. Dropping only the new one leaves the finiteness CHECK
--      blocking the NaN and Infinity poison, and the leg then proves nothing
--      about the two clauses this migration adds to the guard — while still
--      passing, because 0 and -1 are seedable and do yield NULL.
--   3. The five poison values above must each yield nav_inflation_adjusted
--      NULL (never a raise, never 0, never a sign-flip) with nav_nominal INTACT
--      on the same row. Assert the ROW EXISTS — a NULL-only assertion passes
--      vacuously against an implementation that dropped the row.
--   4. The 067 battery's (ZN1)/(ZN2)/(ZN3) prosrc legs run against the REPLACED
--      body. They were checked against this file's new body text before commit
--      and pass; they are re-asserted by the battery, not by this file.
-- ============================================================================

create schema if not exists pfin;

-- ---------------------------------------------------------------------------
-- STEP 1 — PRE-FLIGHT. Count existing rows that the new predicate would reject,
-- and RAISE with the count rather than letting ADD CONSTRAINT fail with a bare
-- 23514 that names no number. Expected: zero. The column is NOT NULL, so the
-- predicate is two-valued here and the count is exact.
-- ---------------------------------------------------------------------------

do $preflight$
declare
  v_violations bigint;
begin
  select count(*) into v_violations
  from pfin.cpi_u_index
  where not (cpi_value > 0
         and cpi_value <> 'NaN'::numeric
         and cpi_value <> 'Infinity'::numeric);

  if v_violations > 0 then
    raise exception
      'SELF-343 pre-flight: % row(s) in pfin.cpi_u_index fail the finite-and-positive predicate on cpi_value. Disposition them before applying 095 — this migration will not silently narrow around them.',
      v_violations;
  end if;

  raise notice 'SELF-343 pre-flight: 0 violating rows in pfin.cpi_u_index.';
end
$preflight$;

-- ---------------------------------------------------------------------------
-- STEP 2 — THE ADDITIVE CHECK. drop-if-exists-then-add on the NEW NAME ONLY
-- (the 011 / 028 / 085 idiom), so a re-apply onto a database already carrying
-- it is a no-op rather than a duplicate-object error.
-- ⚠ cpi_u_index_value_finite IS NOT DROPPED HERE. That is Sec's binding
-- condition (2), and it is enforced by the absence of the statement rather than
-- by this sentence. The reviewer's check is mechanical: this file issues
-- EXACTLY ONE `drop constraint` STATEMENT — filter the comment lines out
-- (`grep 'drop constraint' | grep -v -- '--'`) and one line remains, naming the
-- NEW constraint. Every occurrence of the finiteness constraint's name in this
-- file is prose.
-- ---------------------------------------------------------------------------

alter table pfin.cpi_u_index
  drop constraint if exists cpi_u_index_value_positive_finite;

alter table pfin.cpi_u_index
  add constraint cpi_u_index_value_positive_finite
    check (cpi_value > 0
       and cpi_value <> 'NaN'::numeric
       and cpi_value <> 'Infinity'::numeric);

comment on constraint cpi_u_index_value_positive_finite on pfin.cpi_u_index is
  'FINITE AND STRICTLY POSITIVE on cpi_value — the authoritative fence on the DIVISOR of every '
  'inflation-adjusted figure V1 derives from this table (SELF-343; BACKLOG §7.14 first entry; Sec-conditioned, '
  'joint-review-mandatory). '
  'WHY THIS IS NOT A BARE `> 0`: PostgreSQL numeric ordering places NaN and +Infinity ABOVE every finite value, '
  'so `NaN > 0` and `''Infinity'' > 0` are both TRUE and a bare positivity test would re-admit exactly the two '
  'states a finiteness fence exists to bar. This CHECK therefore states finiteness explicitly as well. -Infinity '
  'carries no clause of its own DELIBERATELY: it sorts BELOW every finite value, so `> 0` already rejects it, and '
  'a clause that cannot fire is a fence that cannot be tested. '
  'ADDITIVE, NEVER A REPLACEMENT: cpi_u_index_value_finite MUST survive by name. The two constraints OVERLAP on '
  'NaN and the infinities and THAT OVERLAP IS DELIBERATE, not an oversight to tidy — read surfaces over this '
  'column guard themselves with a strictly-positive test, which is a NaN and +Infinity guard ONLY because a '
  'finiteness CHECK stands behind it, and those surfaces name the FINITENESS constraint rather than this one. '
  'Dropping either constraint is a Sec joint-review decision on a financial surface, not a cleanup. '
  'Role-agnostic table CHECK — service_role bypasses RLS but NOT CHECK — and the column is NOT NULL, so there is '
  'no NULL-passes gap. Belt-and-suspenders with the ETL''s app-layer filter; this DB CHECK is the authoritative '
  'fence.';

-- ---------------------------------------------------------------------------
-- STEP 3 — column comment RE-ISSUED so the reader at \d+ is not told the column
-- is finiteness-fenced only. Regenerated from 053's committed text by ONE
-- anchored substitution; every other byte is carried verbatim.
-- ---------------------------------------------------------------------------

comment on column pfin.cpi_u_index.cpi_value is
  'The CPI-U index level for cpi_period (numeric, unrounded — BLS publishes to 3 '
  'decimals but the raw value is stored as-provided). CHECK-fenced at the table, and the '
  'fences are CUMULATIVE rather than redundant: cpi_u_index_value_finite rejects NaN AND '
  '±Infinity; cpi_u_index_value_positive_finite, added at 095, rejects zero, negatives, '
  'and the same special values. Read the live constraint list on the table; neither may '
  'be dropped as redundant. A rejected state would poison downstream '
  'real/inflation-adjusted SUMs, and a zero print would raise inside a deflator '
  'division. Revisable (BLS restates prints) → '
  'the table is MUTABLE.';
-- ---------------------------------------------------------------------------
-- STEP 4 — THE 067 GUARD, HARDENED. create-or-replace: signature, return shape,
-- ordering, STABLE volatility, SECURITY INVOKER and `set search_path = ''` are
-- all re-declared explicitly, because create-or-replace RESETS volatility and
-- posture to whatever this statement says rather than preserving them.
-- The ACL is NOT re-issued: create-or-replace preserves it, and re-issuing a
-- grant on a financial read surface inside an unrelated migration is how an ACL
-- change rides along unreviewed. The catalog comment is preserved by the same
-- mechanism, which is exactly why STEP 5 must re-issue it.
-- Regenerated from 067's committed text by ONE anchored substitution inside the
-- deflator CASE; every other byte of the function is carried verbatim.
-- ---------------------------------------------------------------------------

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
    -- THE DEFLATOR. Both legs must be FINITE AND STRICTLY POSITIVE, and each
    -- rejected state is rejected for its own reason. NULL: the level is not
    -- known. Zero: the division would raise. Negative: the sign of a net-worth
    -- figure would flip silently, which is worse than an error. NaN: the
    -- product is poisoned. +Infinity: the basis leg yields an infinite figure
    -- and the point leg collapses every figure to a flat zero — and "the
    -- real-terms value is zero" must not render identically to "we cannot
    -- deflate this point".
    -- ⚠ NaN AND +Infinity NEED CLAUSES OF THEIR OWN, and -Infinity DOES NOT.
    -- numeric ordering places NaN and +Infinity ABOVE every finite value, so
    -- neither is caught by `<= 0`; -Infinity sorts below every finite value and
    -- is caught by it. A reviewer removing the two explicit clauses as noise
    -- re-opens exactly the two states the sibling table CHECK exists to bar.
    -- This guard is DEFENSE-IN-DEPTH BEHIND that CHECK, not a route-around —
    -- see DIVISION SAFETY. NULL, never 0, on every rejected path.
    case
      when v_cpi_basis is null
        or v_cpi_basis = 'NaN'::numeric
        or v_cpi_basis = 'Infinity'::numeric
        or v_cpi_basis <= 0 then null::numeric
      when c.cpi_value is null
        or c.cpi_value = 'NaN'::numeric
        or c.cpi_value = 'Infinity'::numeric
        or c.cpi_value <= 0 then null::numeric
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
-- ---------------------------------------------------------------------------
-- STEP 5 — THE CATALOG COMMENT, RE-ISSUED. Without this the catalog would keep
-- describing a guard the function no longer has, and would keep naming a
-- "separate vehicle" for a positivity CHECK that is this file. Regenerated from
-- 067's committed text by ONE anchored substitution of the DIVISION SAFETY
-- paragraph; every other byte is carried verbatim.
-- ---------------------------------------------------------------------------

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
  'DIVISION SAFETY: the ratio is computed only when BOTH CPI legs are FINITE AND STRICTLY POSITIVE. NULL, NaN, '
  '+Infinity, and any value <= 0 (which includes -Infinity) each yield NULL — never a raise, never a sign-flipped '
  'figure, never a silent zero. NaN and +Infinity carry clauses of their own because numeric ordering places both '
  'ABOVE every finite value, so neither is caught by a <= 0 test; -Infinity sorts below every finite value and is. '
  'pfin.cpi_u_index.cpi_value carries the CHECK constraints cpi_u_index_value_finite and '
  'cpi_u_index_value_positive_finite — read them on the table. The second landed at 095, which is the separate '
  'vehicle this paragraph previously named as pending; it does NOT retire the first, which MUST survive by name, and '
  'that constraint''s own comment states why. This guard is DEFENSE-IN-DEPTH BEHIND those CHECKs rather than the only '
  'fence, and the paired QA leg MUST survive them rather than be retired by them: it corrupts the control by dropping '
  'BOTH constraints inside a savepoint, because dropping either one alone leaves the other blocking the poison. '
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
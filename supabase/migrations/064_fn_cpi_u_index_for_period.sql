-- ============================================================================
-- Migration: pfin.fn_cpi_u_index_for_period — THE single CPI-U consumption
--   helper. Realizes ADR-049 Decision 4 (F/CTO-ratified Option C, 2026-08-10):
--   "the CPI gap policy is implemented in a single SECURITY INVOKER composition
--   helper, and never inline in a consumer."
--   SECURITY INVOKER read-composition (ADR-011 Lock 11) over pfin.cpi_u_index
--   (053) and pfin.cpi_u_nonpublication (063).
--   JOINT-REVIEW-MANDATORY (Sec veto surface): ADR-011 Decision 1 — this helper
--   is the read path by which a recorded non-publication reaches an
--   inflation-adjusted financial figure.
--
-- ----------------------------------------------------------------------------
-- Numbering: 064 follows 063 (cpi_u_nonpublication). Next free number taken AT
--   AUTHORING TIME, never reserved ahead (ADR-049 Consequences).
--   Depends on: 001 (pfin schema) + 053 (cpi_u_index) + 063
--   (cpi_u_nonpublication). This migration MUST apply after both tables exist —
--   it reads both. Order-DEPENDENT, unlike a pure helper.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT
--   SECURITY DEFINER. The helper reads two GLOBAL public reference tables whose
--   SELECT policies are `using (true)`, so it needs no elevated privilege and
--   INVOKER gives the caller exactly the rows their own policies already permit.
--   This migration authors NO SECURITY DEFINER function, so the ADR-011
--   Decision 9 DEFINER allowlist is UNCHANGED by it (+0). Stated as a DELTA, not
--   as a level: the allowlist's size is read live from Decision 9, never copied
--   into a file that cannot maintain it.
--   ADR-023 Step 0: both tables are PURE-GLOBAL, so reads execute under
--   `authenticated` — this helper composes with that rule rather than excepting
--   it.
--
-- ----------------------------------------------------------------------------
-- WHY A HELPER AT ALL — and why NOW, at zero consumers.
--   PRECEDENT (ADR-049 Decision 4): pfin.eod_price (019) is declared SPARSE →
--   last-observation-carried-forward, and that LOCF is implemented ONCE, inside
--   fn_compute_nav's source-priority composition — not re-derived per consumer.
--   That is the Lock 11 INVOKER read-composition pattern doing exactly this job.
--   ADR-049 recorded ZERO built consumers of cpi_u_index at ratify (2026-08-10),
--   which is precisely why the contract was settled then: the question was never
--   "fix N consumers" but "what does the FIRST consumer inherit". With zero
--   consumers the cost of centralizing is nil; with two, we would have two
--   answers to the same question.
--   >> STANDING REQUIREMENT: a consumer needing a CPI-U level for a period calls
--   THIS function. Do NOT re-derive carry-forward or gap classification inline. <<
--
-- ----------------------------------------------------------------------------
-- ⚠ WHY THE RETURN IS A ROW AND NEVER A BARE SCALAR — the crux of Decision 4.
--   CPI-U is NOT eod_price, and the difference is the whole point. Price
--   sparsity is EXPECTED; CPI-U is supposed to be MONTHLY-COMPLETE, so carrying
--   a value forward SILENTLY UNDERSTATES INFLATION for the gap month. Carry-
--   forward is defensible arithmetic; SILENT carry-forward is not — for a
--   financial figure the defect IS the silence.
--   ADR-049 fences that BY CONSTRUCTION rather than by documentation: the helper
--   returns a ROW, never a scalar. A consumer that wants only the number must
--   EXPLICITLY PROJECT THE OTHER COLUMNS AWAY, which converts "don't ignore
--   carried-ness" from a rule someone must REMEMBER into a step someone must
--   TAKE — and a deliberate projection is VISIBLE IN A DIFF, where an unread
--   boolean is not. Same principle as the pure-append proof and `WHERE false`
--   elsewhere in this schema: a property enforced by construction beats one
--   enforced by review.
--   >> DO NOT "simplify" this to `returns numeric`. That single change removes
--   the only mechanism enforcing non-silence, and it removes it invisibly. <<
--   Shape note: `returns table (...)` is the house form for a multi-column
--   return in this schema (017 / 019 / 035 / 037 / 042 / 045 / 046 / 049 / 056 /
--   058 / 062); no named composite type is introduced, because none is needed to
--   get the by-construction property and a bare `create type` has no idempotent
--   form.
--
-- ----------------------------------------------------------------------------
-- CARRY-FORWARD + EXPOSE PROVENANCE — the 062 (iii) shape, second application.
--   062 (fn_nav_series) faced the identical three-way choice for a missing NAV
--   checkpoint and F/CTO ratified option (iii): carry the value forward but ALSO
--   return the date it came from. (i) omit-the-period is honest but leaves the
--   consumer nothing to explain the hole with; (ii) carry SILENTLY draws a flat
--   line that reads as "nothing moved" when the truth is "we have not measured".
--   The provenance column IS the detectability mechanism; without it, (ii) is
--   what you have whether or not you intended it. `carried_from` here is the
--   same column doing the same job, and `is_carried` states the fact directly
--   rather than requiring the consumer to compare two dates.
--
-- ----------------------------------------------------------------------------
-- ⚠ THE TRAILING-EDGE RULE — and a DELIBERATE DEVIATION from the shape ADR-049
--   Decision 3 sketched. FLAGGED FOR SEC / F/CTO, not slipped in.
--   Decision 3's requirement: "Any gap detector MUST bound itself to periods
--   that are actually due", because "not yet published" and "missing" are
--   indistinguishable by contiguity — an unbounded contiguity check false-
--   positives EVERY MONTH, FOREVER. Its sketched shape compares against
--   `date_trunc('month', <server today>) - interval '1 month'` OR A STRICTER
--   BOUND, with the exact lag constant to be VERIFIED against BLS's published
--   release schedule at implementation, never assumed.
--   >> THIS HELPER TAKES THE STRICTER BOUND, AND IT IS DATA-DERIVED RATHER THAN
--   CALENDAR-DERIVED: a period is treated as a GAP only if a LATER period is
--   PRESENT in cpi_u_index. <<
--   Why that is stricter, and why it is preferable here:
--     · It needs NO lag constant. A guessed constant reproduces the false
--       positive one month later instead of removing it, and a verified one is
--       a dated external fact this file would then have to keep true.
--     · It needs NO "today" AT ALL, so it is entirely outside ADR-044's
--       two-clock hazard — no client-supplied date, no session-TimeZone-
--       evaluated `current_date`, and no dependency on fn_server_today(), which
--       ADR-049 Decision 3 correctly warns is BOOKED, NOT BUILT (verified: it
--       appears in no migration in this tree).
--     · The evidence is stronger than a calendar rule's: "a later print exists"
--       is positive proof the period was due, not an inference about when it
--       should have been due.
--   >> AND ITS COST, STATED RATHER THAN DISCOVERED LATER: this bound CANNOT
--   DETECT A STALLED INGEST. If the ETL dies after 2026-06 and is never re-run,
--   every subsequent period classifies as `beyond_coverage` — indistinguishable
--   from "BLS has not published yet" — where a calendar lag rule would
--   eventually have flagged them. That is a NECESSARY-NOT-SUFFICIENT boundary:
--   INGEST-FRESHNESS MONITORING IS NOT THIS HELPER'S JOB and must not be
--   inferred from its output. ADR-049 Decision 2 already collapses (b)/(c)/(d)
--   and points at a RUN LOG as what narrows them; `beyond_coverage` is exactly
--   that collapsed class, named honestly.
--   Complementarity worth noting: the 063 RECORD works at the trailing edge
--   where this contiguity test cannot — a period BLS published valueless as the
--   most recent period classifies `recorded_nonpublication`, not
--   `beyond_coverage`, because the record is checked FIRST.
--
-- ----------------------------------------------------------------------------
-- gap_class — the CLOSED set, and what each member means. TEXT, not an enum
--   (the 062 `p_granularity text` precedent, F/CTO-ratified 2026-08-07).
--     'published'                — cpi_u_index holds this period's own print.
--                                  is_carried = false.
--     'recorded_nonpublication'  — absent from cpi_u_index AND recorded in
--                                  cpi_u_nonpublication: the source published
--                                  the period with no usable value. This is
--                                  ADR-049 Decision 2 state (a) — the ONLY
--                                  positively-recorded absence.
--     'unrecorded_gap'           — absent, and a LATER period IS present, so the
--                                  period was due and nothing explains it.
--                                  States (c)/(d) collapsed; (b) is impossible
--                                  here.
--     'beyond_coverage'          — absent, and NO later period is present. States
--                                  (b)/(c)/(d) collapsed. NOT an alarm — see the
--                                  trailing-edge block above.
--   ⚠ These are ABSENCE REASONS. They are ORTHOGONAL to the carry outcome:
--   cpi_value / is_carried / carried_from report what could be RESOLVED, and a
--   period can be `recorded_nonpublication` with NO carry available (nothing at
--   or before it). Read both, never one as a proxy for the other.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — ADR-011 Decision 4 is LINKED, not restated;
--   read verbatim live before drafting this file. This migration is not the
--   canonical anchor, so the catalogued numbered list is deliberately NOT
--   reproduced and NO count appears.)
--   (i)   Instance-numbering: catalogues NO new §10 instance, reorders none.
--         Ledger DELTA = 0.
--   (ii)  Layer-attribution: this is a DB-LAYER read helper over two global
--         public reference tables. It is NOT the code-layer
--         SUPABASE_SERVICE_ROLE_KEY allowlist grep fence, NOT the PDF-worker
--         container credential audit, NOT the app->worker admission network/
--         config surface. It touches no credential, no container and no
--         endpoint.
--   (iii) Verbatim-vs-paraphrase: Decision 4 linked, not restated (Path B).
--   DE-CONFLATION GUARD: no FK-shaped column, no credential-presence surface, no
--   admission endpoint — none is a §10 catalogued instance.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED set are DIFFERENT SETS; neither
--   is reconciled to the other here, and neither should be "tidied" to match.
--
-- ----------------------------------------------------------------------------
-- ADR-011 DECISION 3 — family UNCHANGED (+0). This migration creates no column
--   at all, hence no FK-shaped reference column; and both tables it reads are
--   GLOBAL, so there is no tenant boundary to bypass. Both ADR-049 Decision 1
--   grounds carry through unchanged. The family's size is read live from
--   Decision 3's body — this file carries no tally.
--
-- ----------------------------------------------------------------------------
-- LEDGER DELTAS (all confirmed FLAT, stated as deltas): §10 catalogued
--   instances +0 · SECURITY DEFINER allowlist +0 · ADR-011 Decision 3 family +0
--   · SD matrix — NO expansion (reads public reference data only). Sec review is
--   MANDATORY notwithstanding the flat ledgers: ADR-011 Decision 1, the read
--   path into an inflation-adjusted financial figure.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_cpi_u_index_for_period(p_period date)
--     returns table (cpi_period date, cpi_value numeric, is_carried boolean,
--                    carried_from date, gap_class text)
--     — resolves the CPI-U index level to use for p_period, and says how it was
--       resolved. Exactly ONE row, always. SECURITY INVOKER, STABLE,
--       set search_path = ''.
--     p_period is NORMALIZED to first-of-month (the CPI grain) and the
--       normalized value is RETURNED as cpi_period, so a caller passing a
--       mid-month date is TOLD which period answered rather than having to know.
--       NULL p_period raises — an empty result would be indistinguishable from
--       "no CPI data", which on a financial surface is the silence Decision 4
--       forbids.
--     cpi_value is NULL only when nothing at or before the period is present in
--       cpi_u_index (no carry source). It is NEVER a fabricated zero.
--   Security-load-bearing edges: INVOKER over two `using (true)` global tables —
--     NO tenant isolation surface is crossed and no tenant predicate exists to
--     get wrong; `set search_path = ''` fences search_path injection, and every
--     object reference below is schema-qualified accordingly; the row return is
--     itself security-load-bearing in the FINANCIAL-CORRECTNESS sense (it is the
--     mechanism that prevents a silently-carried CPI value from entering a real-
--     terms figure); the p_period NULL raise is fail-loud, not fail-quiet.
--   ⚠ WHAT THIS FUNCTION DELIBERATELY DOES NOT DO — recorded so no consumer
--     infers it: it does NOT detect a stalled ingest (see the trailing-edge
--     block); it does NOT separate "our ingest dropped it" from "backfill never
--     covered the span" (ADR-049 Decision 2 keeps (c)/(d) collapsed, and C' was
--     rejected as the heavier alternative); it does NOT decide what the USER
--     sees — the presentation half routes to the EXISTING non-silent-staleness
--     framework (PRD §2.4.4 per ADR-013, and NOT "INV-1", which is an unrelated
--     §2.6 injection invariant), whose extension to a stale REFERENCE SERIES is
--     an open PM/UX scope question per ADR-049 Decision 5; and it does NOT
--     compute an inflation adjustment — it supplies the input to one.
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- pfin.fn_cpi_u_index_for_period — the ONE place the CPI-U gap policy lives.
-- See the header for the full contract; the notes inline cover only what is not
-- obvious from the code itself.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_cpi_u_index_for_period(p_period date)
returns table (
  cpi_period    date,
  cpi_value     numeric,
  is_carried    boolean,
  carried_from  date,
  gap_class     text
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
-- The RETURNS TABLE output names (cpi_period / cpi_value) collide with column
-- names on the tables being read. Every column reference below is table-
-- qualified, and this directive makes the resolution explicit rather than
-- incidental: an ambiguous bare name resolves to the COLUMN, never to the output
-- variable. Without it a future unqualified reference would fail at runtime with
-- "column reference is ambiguous" instead of doing the obvious thing. The p_*
-- parameter and the v_* locals match no column name, so they are unaffected.
#variable_conflict use_column
declare
  v_period date;     -- p_period normalized to the CPI grain (first-of-month)
  v_from   date;     -- period the carried value came from; NULL if none exists
  v_val    numeric;  -- the carried value itself
  v_max    date;     -- latest period present in cpi_u_index (the trailing edge)
  v_class  text;     -- resolved gap_class
begin
  -- FAIL LOUD on a missing period. Deliberately NOT a silent empty result: an
  -- empty set is indistinguishable from "there is no CPI data", and this
  -- function feeds inflation-adjusted figures where that ambiguity is exactly
  -- the silence ADR-049 Decision 4 exists to prevent. Same fail-loud principle
  -- as 062's granularity guard and 054's immutability fences.
  if p_period is null then
    raise exception
      'pfin.fn_cpi_u_index_for_period: p_period is required (got NULL). A CPI-U lookup with no period is a caller error, not an empty series.';
  end if;

  -- Normalize to the CPI grain. NON-SILENT: v_period is RETURNED as cpi_period
  -- in every branch below, so a caller passing a mid-month date is told which
  -- period answered.
  -- ⚠ The ::timestamp cast is LOAD-BEARING: that type is zone-free, so nothing
  -- in this function is evaluated in the session TimeZone. The zone-AWARE
  -- variant would put the resolved period at the mercy of the session zone
  -- (ADR-044's hazard). Do not "simplify" the cast away.
  v_period := date_trunc('month', p_period::timestamp)::date;

  -- ---------------------------------------------------------------------
  -- (1) EXACT PRINT. The period has its own row — nothing is carried and no
  -- classification is needed. carried_from is set to the period itself rather
  -- than NULL so that "where did this value come from?" has the same answer
  -- shape in every row a consumer receives.
  -- ---------------------------------------------------------------------
  return query
  select v_period, c.cpi_value, false, v_period, 'published'::text
  from pfin.cpi_u_index c
  where c.cpi_period = v_period;

  if found then
    return;
  end if;

  -- ---------------------------------------------------------------------
  -- (2) ABSENT. Resolve the carry source: the latest print STRICTLY BEFORE the
  -- period (equality was already excluded by (1)). This is the 019 LOCF idiom —
  -- order-desc-limit-1 over the at-or-before window — applied once, here, so no
  -- consumer re-derives it.
  -- Both v_from and v_val stay NULL when nothing precedes the period; that is
  -- the "no carry source" case, and it is reported, never papered over with a
  -- zero. 053 declares cpi_value NOT NULL, so a found row always carries a
  -- value: v_from IS NOT NULL is the authoritative "we carried something" test.
  -- ---------------------------------------------------------------------
  select c.cpi_period, c.cpi_value into v_from, v_val
  from pfin.cpi_u_index c
  where c.cpi_period < v_period
  order by c.cpi_period desc
  limit 1;

  -- ---------------------------------------------------------------------
  -- (3) TRAILING EDGE. The data-derived bound that replaces a calendar lag
  -- constant — see the trailing-edge block in the header for why this is the
  -- "stricter bound" ADR-049 Decision 3 permits, and for the stalled-ingest
  -- cost it accepts. No "today" is consulted anywhere in this function.
  -- ---------------------------------------------------------------------
  select max(c.cpi_period) into v_max from pfin.cpi_u_index c;

  -- ---------------------------------------------------------------------
  -- (4) CLASSIFY THE ABSENCE. Order matters: the RECORD is consulted FIRST, so
  -- a period the source published valueless is named as such even when it sits
  -- at the trailing edge, where the contiguity test alone could not tell.
  -- ---------------------------------------------------------------------
  if exists (
    select 1 from pfin.cpi_u_nonpublication n
    where n.cpi_period = v_period
  ) then
    v_class := 'recorded_nonpublication';
  elsif v_max is not null and v_max > v_period then
    -- A LATER period is present, so this one was due and nothing explains it.
    v_class := 'unrecorded_gap';
  else
    -- Nothing later is present. NOT an alarm: (b)/(c)/(d) collapsed.
    v_class := 'beyond_coverage';
  end if;

  -- ---------------------------------------------------------------------
  -- (5) EMIT. Exactly one row, always — a consumer never has to distinguish
  -- "the function returned nothing" from "the answer is nothing".
  -- ---------------------------------------------------------------------
  return query
  select v_period, v_val, (v_from is not null), v_from, v_class;
end;
$$;

-- EXECUTE is granted to PUBLIC by default in Postgres. Revoke it explicitly so
-- the grant below is the whole of the access, rather than a redundant addition
-- on top of an implicit one (054's discipline). anon is denied earlier by schema
-- USAGE, but that is a second fence, not this one.
revoke execute on function pfin.fn_cpi_u_index_for_period(date) from public;
grant execute on function pfin.fn_cpi_u_index_for_period(date) to authenticated;

comment on function pfin.fn_cpi_u_index_for_period(date) is
  'THE single CPI-U consumption helper (ADR-049 Decision 4). Resolves the CPI-U '
  'index level to use for a period AND says how it was resolved. SECURITY INVOKER '
  '(ADR-011 Lock 11 read-composition; not a DEFINER allowlist entry — this '
  'migration adds none), STABLE, set search_path = ''''. Reads pfin.cpi_u_index '
  '(053) and pfin.cpi_u_nonpublication (063), both global public reference tables '
  'with `using (true)` SELECT policies, so no tenant boundary is crossed. '
  'Returns EXACTLY ONE ROW: (cpi_period, cpi_value, is_carried, carried_from, '
  'gap_class). p_period is normalized to first-of-month and the normalized value '
  'is returned, so a caller passing a mid-month date is told which period '
  'answered; NULL p_period raises rather than returning an empty set. '
  'STANDING REQUIREMENT — a consumer needing a CPI-U level calls this function; '
  'the carry-forward and gap-classification policy MUST NOT be re-derived inline '
  'in a consumer (the 019 eod_price LOCF-in-one-helper precedent). '
  'STANDING REQUIREMENT — the return MUST stay a ROW and MUST NOT be narrowed to '
  'a bare scalar: CPI-U is supposed to be monthly-complete, so carrying a value '
  'forward silently understates inflation, and the row return is the '
  'by-construction mechanism forcing a consumer to project carried-ness away '
  'deliberately and visibly rather than merely forget it. '
  'gap_class is a closed TEXT set: ''published'' (own print) / '
  '''recorded_nonpublication'' (source published the period with no usable value; '
  'ADR-049 Decision 2 state (a), the only positively-recorded absence) / '
  '''unrecorded_gap'' (absent and a LATER period is present, so it was due and '
  'nothing explains it) / ''beyond_coverage'' (absent and nothing later is '
  'present — NOT an alarm). gap_class reports the ABSENCE REASON and is '
  'ORTHOGONAL to the carry outcome: cpi_value is NULL when no period at or before '
  'the requested one exists, never a fabricated zero. '
  'BOUNDED BY CONSTRUCTION — the due-period test is DATA-DERIVED (is a later '
  'period present?), not calendar-derived, which is the stricter bound ADR-049 '
  'Decision 3 permits; it consults no clock, so it is outside ADR-044''s two-clock '
  'hazard. ITS COST: it CANNOT detect a stalled ingest — a dead ETL yields '
  '''beyond_coverage'' indefinitely, indistinguishable from "not yet published". '
  'Ingest-freshness monitoring is NOT this function''s job and must not be '
  'inferred from its output. This function also does not decide what the USER '
  'sees: that routes to the existing non-silent-staleness framework per ADR-049 '
  'Decision 5.';

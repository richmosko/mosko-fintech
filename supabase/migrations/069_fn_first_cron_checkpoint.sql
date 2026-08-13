-- ============================================================================
-- Migration: pfin.fn_first_cron_checkpoint — the §2.1.2.d boundary-date signal.
--   Exposes WHERE THE CRON ERA BEGINS in pfin.nav_daily (054), so the chart can
--   gate (a) pre-boundary staleness-marker suppression and (b) the
--   "Monthly resolution before <date>" disclosure. SECURITY INVOKER
--   read-composition (Lock 11). Linear SELF-220 (V1.1; PRD §2.1.2).
--   F/CTO-ratified 2026-08-12 (ADR-054 Decision 7(b) follow-on; three-field row
--   as proposed). apply-migration procedure applied. JOINT-REVIEW-MANDATORY
--   (Sec veto surface): new read-surface function over a multi-tenant financial
--   table. Design note: temp/architect-boundary-date-exposure.md.
--
-- ----------------------------------------------------------------------------
-- WHY A FUNCTION AND NOT A COLUMN ON 067. The boundary is a STORE-level property
--   and a consumer needing only the disclosure line must not have to invoke an
--   entire NAV series to obtain it. 067's own change-control prices a column-set
--   change at drop-and-recreate + ACL re-issue + Sec re-review + battery update;
--   that price should buy something only a column can do, and this is not it.
--   (Recorded honestly: 067 DOES carry a store-level constant, cpi_coverage_through.
--   The difference is that one is an INPUT TO the per-row figure; this one is not.)
--   Also rejected: STORING the boundary (duplicates derivable state — ADR-011
--   Decision 4's derive-by-looking test, which ADR-053 Decision 4 already applied
--   to this exact family), and a per-row `is_imported` flag on 067 (solves the
--   marker suppression but NOT the disclosure, since deriving the date from the
--   returned rows is precisely the client-side inference PM's binding condition
--   forbids).
--
-- ----------------------------------------------------------------------------
-- Numbering: 069 follows 068 (the nav_daily backfill-amendment comment), taken
--   at authoring time and verified against the tree at dba7bf1 — 068 is the
--   highest on main AND on the SELF-220 branch this file is handed to. Depends
--   on 054 (pfin.nav_daily — the sole relation read; its owner-only RLS SELECT
--   policy and the 025 aal2 backstop it carries are what fence this function).
--   No downstream migration depends on 069. Order-independent after 054.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (Lock 11 read-composition default); NOT
--   SECURITY DEFINER. Runs as the caller and inherits their RLS context, exactly
--   as 049 / 051 / 062 / 067 do. Every row it aggregates is a row the caller may
--   already SELECT from pfin.nav_daily directly. DEFINER would be strictly worse:
--   it would detach the read from the caller's RLS context and from the 025 aal2
--   step-up backstop that nav_daily's SELECT policy carries.
--   THE SECURITY DEFINER ALLOWLIST IS NOT TOUCHED — this file authors ONE
--   function and it is INVOKER. Read ADR-011 Decision 9 live for the allowlist's
--   membership; no count is restated here.
--
-- ----------------------------------------------------------------------------
-- ⚠ THE ZONE QUESTION, WHICH IS THE WHOLE DESIGN RISK IN THIS FILE.
--   The cron/imported classification compares created_at (timestamptz) against
--   nav_date (date). `nav_date + interval` yields `timestamp WITHOUT time zone`,
--   and comparing a timestamptz to it COERCES USING THE SESSION TimeZone. So the
--   effective threshold instant MOVES with the caller's session zone.
--
--   AND 061 DOES NOT CLOSE THIS — it is a DEFAULT, NOT A FENCE. 061's own header
--   records the measurement: with the pin active and PGTZ=Asia/Tokyo, the session
--   TimeZone is Asia/Tokyo, "source = client". Any client can move its own
--   session zone while the database default stays UTC.
--
--   >> WHAT MAKES THE CLASSIFICATION SAFE IS THE MARGIN, NOT THE PIN. <<
--   The session-zone offset range is UTC-12 .. UTC+14 — a 26-HOUR SPAN. The two
--   populations this predicate separates are not close to each other:
--     · CRON rows are written at day close: created_at - nav_date is 0-24 hours.
--     · IMPORTED rows carry a historical nav_date with a backfill-run created_at:
--       the smallest real gap is MONTHS (the most recent importable row precedes
--       the first cron checkpoint by construction, ADR-053).
--   A SEVEN-DAY margin therefore sits about 6.5x above the maximum zone span and
--   orders of magnitude below the smallest real import gap. NO SESSION ZONE CAN
--   MOVE A ROW ACROSS IT. The classification is zone-INVARIANT by margin — a
--   property, not a hope, and QA asserts it directly (item 1 below) rather than
--   inspecting tokens.
--
--   ⚠⚠ STANDING CONDITION, and it is the one thing here that could go false.
--   The margin's soundness depends on imported rows being separated from their
--   write time BY MORE THAN THE MARGIN. ADR-053's admissibility rule (an imported
--   row must precede the first cron checkpoint) makes a near-dated import
--   impossible TODAY, but it guarantees NO MINIMUM DISTANCE. An import of rows
--   dated within seven days of their own write would be silently reclassified as
--   CRON rows — no error, no warning, a wrong boundary. Whoever widens the import
--   path owes this predicate a re-check.
--
-- ----------------------------------------------------------------------------
-- TENANT FENCE — INHERITED, NOT RESTATED. This function adds NO
--   `users_id = auth.uid()` predicate of its own and MUST NOT GAIN ONE. Isolation
--   comes entirely from nav_daily's `nav_daily_select` policy (054), inherited
--   through the INVOKER posture, and the 025 aal2 step-up backstop reaches this
--   surface through that same policy.
--   QA MEASURED the reason on 062 rather than arguing it: a redundant local
--   predicate keeps the cross-tenant battery GREEN over a policy broken open with
--   `using (true)`. Adding a "harmless" predicate here would blind the battery
--   the same way.
--   A cross-tenant caller therefore sees no rows and gets the EMPTY-STORE answer
--   (NULL / false / false) — which is correct from that caller's position and
--   fails closed.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_first_cron_checkpoint()
--     RETURNS TABLE (first_cron_checkpoint date,
--                    has_cron_rows boolean,
--                    has_imported_rows boolean)
--     — SECURITY INVOKER, STABLE, set search_path = ''. Takes no argument: the
--       answer is a property of the caller's own store, not of any period.
--   · EXACTLY ONE ROW, ALWAYS — by construction, since an aggregate over an empty
--     set still returns a row. A consumer never has to distinguish "the function
--     returned nothing" from "the answer is nothing".
--   · first_cron_checkpoint = the earliest nav_date among rows classified CRON;
--     NULL when the caller has no cron rows. NEVER a fabricated date.
--
--   ⚠ WHY THREE FIELDS AND NOT A BARE DATE — this is the substance of the shape,
--   and a scalar return would have been actively wrong. FOUR states exist and a
--   date alone collapses two of them:
--     · no rows at all ............ NULL / false / false -> render nothing
--     · IMPORTED ONLY, no cron yet  NULL / false / TRUE  -> disclose monthly
--                                                            resolution for the
--                                                            WHOLE series
--     · cron only ................. date / TRUE  / false -> no suppression, no
--                                                            disclosure
--     · mixed ..................... date / TRUE  / TRUE  -> suppress + disclose
--                                                            below the boundary
--   >> "IMPORTED ONLY" IS NOT HYPOTHETICAL: it is the state between the seeding
--      run and the first cron night, so it is GUARANTEED to occur for at least a
--      day. Under a bare `date` return it is indistinguishable from an empty
--      store, and the chart would render "no data" over a fully-populated
--      decade. << Same reasoning 066 records for its own row-not-scalar
--      requirement: the composite return is what forces a consumer to handle the
--      distinction deliberately rather than by forgetting it.
--   · Security-load-bearing edges: RLS on pfin.nav_daily is the SOLE tenant fence
--     (no local predicate); cross-tenant callers get the empty-store answer and
--     fail closed; the 025 aal2 backstop is inherited through that policy; the
--     classification is zone-invariant BY MARGIN (see THE ZONE QUESTION) rather
--     than by relying on 061's default; `set search_path = ''` fences search_path
--     injection and every object reference is schema-qualified.
--
-- ----------------------------------------------------------------------------
-- GRANTS — and service_role's exclusion here is STRUCTURAL, not stylistic.
--   revoke from PUBLIC + grant to `authenticated`, matching 062 / 067.
--   ⚠ service_role is NOT granted, and it could not use the grant if it had one:
--   054 gives service_role a COLUMN-LEVEL `select (users_id, nav_date)` only, so
--   it cannot read created_at at all. An EXECUTE grant would produce a function
--   that fails on `permission denied for column created_at` — a broken path
--   rather than a wider one. Recorded because the next person to hit a permission
--   error will otherwise read the omission as an oversight and "fix" it.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; the catalogued
--   numbered list is NOT restated here and no count is stated. Decision 4 read
--   VERBATIM at the canonical anchor before drafting, 2026-08-12, at dba7bf1.)
--   (i)   Instance-numbering: nothing appended, reordered, or renumbered.
--   (ii)  Layer-attribution: an INVOKER read helper reached by `authenticated`
--         over PostgREST. NOT the PDF-worker container credential audit (no
--         container), NOT the code-layer SUPABASE_SERVICE_ROLE_KEY allowlist
--         fence (holds and needs no key — it runs as the caller), NOT the
--         app->worker credential-admission network surface (no worker in this
--         path). No catalogued instance's layer attribution moves; no surface
--         becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is REFERENCED, not restated. This
--         file is not the canonical anchor and never will be.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED set are DIFFERENT SETS and are
--   NOT reconciled here. This migration touches neither.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — +0. This migration creates NO
--   table, NO column, and NO FK-shaped reference of any kind (single FK, self-FK,
--   or INTEGER[] array element). A function has nothing to matched-tenant-validate.
--   AUTHORING-TIME PROVENANCE (dated, not live state — read ADR-011 Decision 3's
--   body live; it grows and its labels are non-contiguous): read verbatim at the
--   canonical anchor on 2026-08-12 at dba7bf1, the family stood at SIXTEEN LABELED
--   INSTANCES (#1-#16), THIRTEEN DDL-REALIZED, #5 DROPPED at 048. Recorded here as
--   a dated observation ONLY; NOT restated in the comment below.
--
-- ----------------------------------------------------------------------------
-- LEDGER DELTAS (all confirmed FLAT, stated as deltas): §10 catalogued instances
--   +0 · SECURITY DEFINER allowlist +0 · ADR-011 Decision 3 family +0 · SD matrix
--   NO expansion · grants on existing objects unchanged · RLS policies unchanged
--   · triggers unchanged. Sec joint-review MANDATORY notwithstanding: a new read
--   surface over a multi-tenant financial table.
--
-- ----------------------------------------------------------------------------
-- QA TEST-PAIRING (QA-owned — Architect does not author supabase/tests/). Ships
--   SAME-PR. Each item names the negative that would ACTUALLY FIRE.
--   1. ZONE INVARIANCE — THE PROPERTY, NOT A TOKEN PROXY. Run the function twice
--      over the SAME fixture under two extreme session TimeZones (e.g. Pacific/
--      Kiritimati at UTC+14 and Pacific/Midway at UTC-11) and assert the output is
--      BYTE-IDENTICAL. This is the leg that fails if someone narrows the margin,
--      and it observes the actual property rather than grepping for tokens — 062's
--      near-miss (9): an enumeration is exhortation wearing a regex.
--   2. THE FOUR-STATE MATRIX, all four, each asserted on the FULL row:
--      (a) no rows -> (NULL, false, false); (b) imported only -> (NULL, false,
--      true); (c) cron only -> (min date, true, false); (d) mixed -> (first cron
--      date, true, true). ⚠ (b) is the one that matters most — it is the state a
--      bare `date` return would have collapsed into (a), and the only leg that
--      would catch a future "simplification" back to a scalar.
--   3. THE MARGIN DISCRIMINATES, NON-VACUOUSLY: seed a cron-shaped row
--      (created_at within hours of nav_date) and an import-shaped row (historical
--      nav_date, created_at now) and assert they classify differently. A fixture
--      whose rows all look the same cannot tell a working predicate from one that
--      returns a constant.
--   4. TWO-TENANT, NON-VACUOUSLY: tenants A and B with DIFFERENT boundary dates;
--      assert A's call returns A's. A same-boundary fixture passes under a broken
--      predicate.
--   5. CROSS-TENANT gets the EMPTY-STORE answer (NULL, false, false), not an
--      error and not the other tenant's boundary.
--   6. AAL2 BACKSTOP, BOTH LEGS: a totp/passkey tenant on an aal1 session gets
--      (NULL, false, false); the same tenant at aal2 gets their real boundary.
--      Without the positive leg the negative passes vacuously on an empty fixture.
--   7. ACL: EXECUTE revoked from PUBLIC, granted to `authenticated`, NOT held by
--      service_role. Assert on pg_proc.proacl, not on a successful call.
--   ⚠ `supabase db reset` is PROHIBITED here — it destroys the F/CTO's active
--   local test data. Verify non-destructively (apply-in-txn + rollback).
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- pfin.fn_first_cron_checkpoint — where the cron era begins for THIS caller.
-- Reads pfin.nav_daily ONLY. See the header for the full contract; the notes
-- inline cover only what is not obvious from the code itself.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_first_cron_checkpoint()
returns table (
  first_cron_checkpoint  date,
  has_cron_rows          boolean,
  has_imported_rows      boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  -- ONE aggregate over the caller's RLS-scoped rows. An aggregate over an empty
  -- set still returns a row, so "exactly one row, always" holds by construction
  -- rather than by a guard.
  --
  -- THE CLASSIFIER: a row is CRON iff it was written within the margin of the day
  -- it measures. Imported rows carry a historical nav_date against a backfill-run
  -- created_at, so they fall far outside it. The margin is SEVEN DAYS and it is
  -- load-bearing: it exceeds the maximum session-zone span (26 hours) by ~6.5x,
  -- which is what makes this comparison give the same answer to every caller
  -- regardless of their session TimeZone. Do NOT narrow it. See THE ZONE QUESTION
  -- in the header for why 061's database pin does not substitute for this.
  select
    min(nd.nav_date) filter (
      where nd.created_at < nd.nav_date + interval '7 days'
    ),
    count(*) filter (
      where nd.created_at < nd.nav_date + interval '7 days'
    ) > 0,
    count(*) filter (
      where nd.created_at >= nd.nav_date + interval '7 days'
    ) > 0
  from pfin.nav_daily nd;
$$;

revoke execute on function pfin.fn_first_cron_checkpoint() from public;
grant  execute on function pfin.fn_first_cron_checkpoint() to authenticated;

comment on function pfin.fn_first_cron_checkpoint() is
  'SECURITY INVOKER §2.1.2 boundary-date signal (V1.1; PRD §2.1.2 / SELF-220; ADR-054 Decision 7(b) follow-on; '
  'ADR-011 Lock 11 read-composition). Returns EXACTLY ONE ROW: (first_cron_checkpoint date, has_cron_rows boolean, '
  'has_imported_rows boolean) — where the cron era begins in pfin.nav_daily (054) FOR THE CALLING TENANT, so a consumer '
  'can gate pre-boundary staleness-marker suppression and the "Monthly resolution before <date>" disclosure. STABLE, '
  'set search_path = ''''. Takes no argument: the answer is a property of the caller''s store, not of any period. '
  'THREE FIELDS AND NOT A BARE DATE, because FOUR states exist and a scalar collapses two: no rows (NULL/false/false); '
  'IMPORTED ONLY with no cron yet (NULL/false/true); cron only (date/true/false); mixed (date/true/true). The '
  'imported-only state is GUARANTEED to occur — it is the state between a seeding run and the first cron night — and a '
  'bare date return makes it indistinguishable from an empty store, which would render "no data" over a fully-populated '
  'series. STANDING REQUIREMENT: the return MUST NOT be narrowed to a scalar (the 066 row-not-scalar precedent — a '
  'composite return is what forces a consumer to handle a distinction deliberately rather than by forgetting it). '
  'CLASSIFICATION: a row is CRON iff created_at falls within SEVEN DAYS of nav_date; imported rows carry a historical '
  'nav_date against a backfill-run created_at and fall far outside. ⚠ THE MARGIN IS LOAD-BEARING AND MUST NOT BE '
  'NARROWED: this comparison coerces a timestamp using the SESSION TimeZone, and migration 061 pins only the DATABASE '
  'default — a client setting PGTZ moves its own session zone. The margin exceeds the maximum session-zone span '
  '(UTC-12..UTC+14, 26 hours) by roughly 6.5x, which is what makes the classification identical for every caller. It is '
  'zone-invariant BY MARGIN, not by the pin, and QA asserts byte-identical output under two extreme session zones. '
  '⚠ STANDING CONDITION — the one thing here that can go false: the margin is sound only while imported rows are '
  'separated from their write time by MORE than seven days. ADR-053''s admissibility rule (an import must precede the '
  'first cron checkpoint) makes a near-dated import impossible today but guarantees NO MINIMUM DISTANCE; an import of '
  'rows dated within seven days of their own write would be silently reclassified as CRON — no error, a wrong boundary. '
  'Whoever widens the import path owes this predicate a re-check. '
  'TENANT FENCE: RLS on pfin.nav_daily is the SOLE mechanism — this function adds no users_id predicate of its own and '
  'MUST NOT GAIN ONE; QA measured on 062 that a redundant local predicate keeps the cross-tenant battery green over a '
  'policy broken open with using(true). A cross-tenant caller gets the empty-store answer (NULL/false/false) and fails '
  'closed. The 025 aal2 step-up backstop is INHERITED through that same policy. '
  'EXECUTE revoked from PUBLIC, granted to authenticated; service_role deliberately NOT granted — and it could not use '
  'the grant, since 054 gives it a column-level select on (users_id, nav_date) only and this function reads created_at. '
  'An EXECUTE grant would produce a broken path, not a wider one. '
  'SECURITY INVOKER — NOT a DEFINER allowlist entry, and this migration authors no DEFINER function; read ADR-011 '
  'Decision 9 live for the allowlist. §10 catalogued ledger UNCHANGED BY THIS OBJECT, and NO COUNT IS STATED HERE: a '
  'ledger-impact claim is authoring-time provenance and belongs in a migration header, which is dated, not in a catalog '
  'comment, which reads as live state. Read ADR-011 Decision 4 live. Decision-3 unchanged (this migration creates no '
  'table, column, or FK-shaped reference). Sec joint-review-mandatory (new read surface over a multi-tenant financial '
  'table); RLS verification -> the SELF-220 battery.';

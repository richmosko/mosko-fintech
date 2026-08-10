-- =====================================================================
-- Per-Wave battery — pfin.fn_cpi_u_index_for_period(date)
--   THE single CPI-U consumption helper (ADR-049 Decision 4 / migration 064)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/064_fn_cpi_u_index_for_period.sql
--   - pfin.fn_cpi_u_index_for_period(p_period date)
--       returns table (cpi_period date, cpi_value numeric, is_carried boolean,
--                      carried_from date, gap_class text)
--       SECURITY INVOKER · STABLE · set search_path = ''  (ADR-011 Lock 11 read-composition
--       over pfin.cpi_u_index (053) and pfin.cpi_u_nonpublication (063), both GLOBAL with
--       `using (true)` SELECT policies)
--   - revoke execute ... from public   (EXECUTE is granted to PUBLIC by default — the revoke
--                                      is the whole of the access control, and its removal is
--                                      SILENT: every behavioural leg here would stay green)
--   - grant execute ... to authenticated
--   - gap_class closed TEXT set: published / recorded_nonpublication / unrecorded_gap /
--                                beyond_coverage
--
-- ┌─ ⚠ WHAT "TWO-TENANT" MEANS FOR A HELPER OVER TWO TENANT-LESS TABLES ───────────────────────┐
-- │ Both tables this function reads are GLOBAL: no users_id, no FK-shaped column, no tenant     │
-- │ anchor. A per-tenant isolation assertion has no subject here, and porting one mechanically  │
-- │ would report coverage while proving nothing. The two-tenant fixture is still used, with its │
-- │ POLARITY INVERTED — leg (D) asserts the helper returns IDENTICAL rows under two DISTINCT    │
-- │ authenticated identities (global shared-read through an INVOKER helper), with (D0) pinning  │
-- │ that the identities really differ so the invariance is evidence rather than blindness.      │
-- │ THE ISOLATION QUESTION THAT DOES BITE HERE IS THE **ROLE**: who may execute this function   │
-- │ at all. Leg (A) proves that both ways for every role — authenticated yes, PUBLIC / anon /   │
-- │ service_role no — by ACL fact AND by attempted call.                                        │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ ⚠ THE FIXTURE DELETES pfin.cpi_u_index ROWS, AND WHY THAT IS THE HONEST CHOICE ───────────┐
-- │ This helper classifies an absence by asking "is a LATER period present?" — a question about │
-- │ the GLOBAL contents of cpi_u_index. So `beyond_coverage` vs `unrecorded_gap` for any given  │
-- │ probe date depends on EVERY row in that table, including rows this file did not write.      │
-- │ A battery that seeded on top of ambient data would pass in CI (empty table) and mean        │
-- │ something different on a developer machine (137 real BLS prints) — the same assertions,     │
-- │ silently testing a different question. The fixture therefore DELETEs the table's rows       │
-- │ inside the rolled-back transaction and pins the resulting shape in (z1)/(z2), so the        │
-- │ classification legs mean exactly one thing on any DB this runs against.                     │
-- │ SAFETY: the delete is inside `begin … rollback` and cpi_u_index has NO inbound FK (verified │
-- │ against pg_constraint), so nothing cascades. It is NOT `supabase db reset` — a local run    │
-- │ leaves the developer's data untouched, re-counted after every authoring run.                │
-- │ cpi_u_nonpublication is NOT cleared the same way: it is IMMUTABLE, so there is no delete    │
-- │ path at any tier. (z3) pins it empty instead — an assumption that has to be checked because │
-- │ it cannot be enforced.                                                                      │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ THE FOUR gap_class OUTCOMES ARE REACHED BY REAL DATA STATE, NOT BY ARGUMENT SHAPE ────────┐
-- │   published               (B1)  2025-09-01 — its own print exists                           │
-- │   unrecorded_gap          (B2)  2025-10-01 — absent, 2025-11 present, NO record yet         │
-- │   recorded_nonpublication (B3)  2025-10-01 — THE SAME PERIOD, after the 063 record lands    │
-- │   beyond_coverage         (B4)  2026-01-01 — absent, nothing later present                  │
-- │ (B2)/(B3) are the load-bearing pair: same function, same argument, same table contents      │
-- │ EXCEPT the one row 063 exists to hold. A suite that reached the two classes from two        │
-- │ different periods would pass without ever showing that the RECORD is what changed the       │
-- │ answer. Varying exactly one variable is the whole design of this leg.                       │
-- │ (B5) then pins the TRAILING-EDGE COMPLEMENTARITY the migration calls out: a record at a      │
-- │ period beyond the trailing edge classifies `recorded_nonpublication`, not `beyond_coverage`, │
-- │ because the record is consulted at all and consulted ahead of the `else`. (V3b) removes the  │
-- │ consultation and watches (B5) flip.                                                          │
-- │ ⚠ THE ORDER OF THE RECORD CHECK RELATIVE TO THE CONTIGUITY CHECK IS A SEPARATE PROPERTY, and │
-- │ (B5) CANNOT SEE IT — measured, not assumed: at the trailing edge the two branches are        │
-- │ mutually exclusive, so swapping them changes nothing there. The order is observable only at  │
-- │ the INTERIOR gap, i.e. at (B3), and (V3a) is where it is measured. Recorded because the      │
-- │ first draft of this file asserted the opposite and the run refuted it.                       │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ NON-VACUITY IS ENCODED, NOT REPORTED — leg (V) ───────────────────────────────────────────┐
-- │ Each (V) leg breaks the property inside a savepoint, asserts the fence FLIPS, rolls back.   │
-- │ Each was also reproduced by hand at authoring (broken, watched RED, restored); the (V) legs │
-- │ are the durable half. The two SOURCE-TEXT/CATALOG assertions (E1)-(E4) need this most:      │
-- │ catalog inspection has no natural failure mode to calibrate against, so without (V1)/(V2)   │
-- │ a reader cannot tell a real fence from an assertion whose subject never varies.             │
-- │   (V1) grant EXECUTE to service_role        -> (A4)/(A6) flip                                │
-- │   (V2) narrow the return to `returns numeric` -> (E4) flips: the by-construction non-silence │
-- │                                                mechanism is gone and NOTHING ELSE notices    │
-- │  (V3a) classify contiguity BEFORE the record  -> (B3) flips. ⚠ THIS WAS A REFUTED           │
-- │        HYPOTHESIS: the leg was first written against (B5), the trailing-edge probe, and the  │
-- │        run showed NO change — at the trailing edge the two swapped branches are mutually     │
-- │        exclusive. The order is observable ONLY at the interior gap. The refutation is kept   │
-- │        in place at the leg, because "which probe can see this property" is the finding.      │
-- │  (V3b) remove the record consultation entirely -> (B5) flips to beyond_coverage: the         │
-- │        trailing edge is where the record is the ONLY evidence, and (V3a) cannot reach it     │
-- │   (V4) fabricate 0 where the value is unknown -> (C4)/(C5) flip: the $0 defect, made real    │
-- │   (V5) structural, OUTSIDE any savepoint: the function is back, and the plan counter with it │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ HARNESS NOTE — a rolled-back savepoint REWINDS pgTAP's plan counter ──────────────────────┐
-- │ …while the emitted test NUMBERING marches on from a non-transactional sequence (rls/        │
-- │ DESIGN.md §9; the 062 idiom, re-measured here). ⚠ DO NOT reconcile a "planned N but ran M"  │
-- │ diagnostic by LOWERING the plan: pg_prove compares the PRINTED plan against the PRINTED     │
-- │ test lines, so lowering it converts a cosmetic diagnostic into a real failure. (V5) sits    │
-- │ OUTSIDE every savepoint and runs LAST, which re-sets the counter to its own emitted number. │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (the REAL defect each assertion would catch):
--   (z1)/(z2)/(z3) -> a battery silently classifying against ambient data. Every (B)/(C) leg is
--            an assertion about "is a later period present", which is a property of the WHOLE
--            table; these pin the exact shape those legs assume.
--   (A1)/(A7) -> the helper being unreachable by the only role meant to call it (ADR-023 Step 0:
--            both tables are PURE-GLOBAL, so reads execute under `authenticated`).
--   (A2)  -> the `revoke execute from public` being dropped. Postgres grants EXECUTE to PUBLIC
--            BY DEFAULT, so this is not a belt-and-braces line: without it every role in the
--            cluster can call the function, and NO behavioural assertion in this file would go
--            red. The silence is the hazard.
--   (A3)/(A5) -> anon reachability on a function that reads two `using (true)` tables.
--   (A4)/(A6) -> a broad `grant execute on all functions in schema pfin to service_role` (the
--            plausible drift). Pinned as MEASURED CURRENT POSTURE, not as a security claim:
--            service_role is rolbypassrls, but both tables here are global with no tenant
--            predicate to bypass, so this is least-privilege rather than an isolation fence.
--            ⚠ Flagged for Architect/Sec rather than assumed: if a server-side or ETL path ever
--            needs this helper, that is a grant change and a review, not a silent widening.
--   (B1)-(B4) -> a misclassification in any of the four states. Each is reached by real data.
--   (B3)  -> the 063 record NOT being consulted at all: (B2) would still pass, and a recorded
--            non-publication would read as an unexplained gap forever.
--   (B5)  -> the 063 record dropping out of the classification entirely (the shape 064 would
--            have had if written against 053 alone). The trailing edge is exactly where the
--            contiguity test has nothing to see, so the record is the ONLY evidence available.
--            ⚠ It does NOT catch a record-vs-contiguity REORDER — (B3) is the probe that does.
--   (B6)  -> the "exactly one row, always" contract breaking. A consumer would then have to
--            distinguish "the function returned nothing" from "the answer is nothing" — the
--            ambiguity ADR-049 Decision 4 exists to prevent.
--   (C1)  -> a NULL period returning an EMPTY SET instead of raising: indistinguishable from
--            "there is no CPI data" on a surface that feeds inflation-adjusted figures.
--   (C2)/(C3) -> silent normalization. The caller passing a mid-month date must be TOLD which
--            period answered; (C3) additionally proves normalization happens BEFORE
--            classification, so a mid-month probe in a gap month is not misclassified.
--   (C4)/(C5) -> a FABRICATED ZERO where no carry source exists. This is the $0-chart defect:
--            0 is a plausible-looking number that silently understates a real-terms figure by
--            100%, where NULL forces the consumer to handle the unknown.
--   (C6)  -> a session-TimeZone dependency creeping into the period normalization (ADR-044's
--            two-clock hazard). 064 makes the `::timestamp` cast load-bearing for exactly this.
--   (D0)-(D2) -> a tenant predicate being introduced into a helper over two tenant-less tables,
--            or the two-identity fixture silently collapsing to one identity.
--   (E1)  -> conversion to SECURITY DEFINER. That is an ADR-011 Decision 9 allowlist change and
--            a Sec-veto surface; 064 declares the allowlist delta as +0 and this pins it.
--   (E2)  -> loss of STABLE (a VOLATILE marking would defeat per-statement plan caching and,
--            more importantly, signals the author thinks this function has side effects).
--   (E3)  -> loss of `set search_path = ''`, the search_path-injection fence.
--   (E4)  -> ⭐ narrowing the return to a bare scalar. 064: the ROW return is the BY-CONSTRUCTION
--            mechanism that forces a consumer to project carried-ness away DELIBERATELY AND
--            VISIBLY rather than merely forget it. Every behavioural leg in this file would
--            still pass against `returns numeric` — (V2) measures that. This assertion is the
--            only thing standing between a silently-carried CPI value and a real-terms figure.
--   (V1)-(V4) -> the fences above having quietly stopped being fences.
--   (V5)  -> the (V) block leaving the function replaced or a grant open.
--
-- §10 / DECISION 3 (Path B — ADR-011 Decision 4 is LINKED, not restated; read it live. This file
--   is not the canonical anchor, so NO count appears). §10 catalogued instances: DELTA = 0 —
--   a DB-layer read helper over two global public reference tables, touching no credential, no
--   container and no admission endpoint. ADR-011 Decision 3 family: DELTA = 0 — this migration
--   creates no column at all, and both tables are GLOBAL. SECURITY DEFINER allowlist: DELTA = 0
--   — the helper is SECURITY INVOKER, pinned by (E1). This battery changes no ledger.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY. The fixed-UUID tenants supply the authenticated
--   execution CONTEXT only (no per-tenant data exists on either table). NO PII / NO real account
--   numbers / NO production data. The seeded CPI levels are synthetic macro reference values;
--   the 2025-10 gap is used because it is the period ADR-049 was written for, but the fixture is
--   authored here, not copied from production. No auth.users rows are needed (no auth.users FK;
--   `using (true)` never dereferences auth.uid()). All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so no
--   `_rls.*` call runs while switched to authenticated; every _rls.set_tenant is called at
--   role=postgres and each block restores role=postgres. \gset var names are ALL-LOWERCASE.
--   anon / service_role denials are probed with _rls.stmt_denied_as (called and asserted at
--   postgres) rather than by running pgTAP under a role that may hold no EXECUTE on it.
--
-- ⟦WIRE-VALIDATE⟧ VERIFIED LOCALLY, NON-DESTRUCTIVELY: 063 + 064 + this file applied inside a
--   single psql transaction that was ROLLED BACK (no `supabase db reset`; the developer's 137
--   real cpi_u_index rows were re-counted intact after every run). The authoritative run is CI's
--   001->064 reset stack (pg_prove directory-mode).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(35);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- FIXTURE — normalize cpi_u_index to a KNOWN shape, then seed it. See the header block for
-- why the delete is here and why it is safe. The shape is deliberate:
--     2025-08 present · 2025-09 present · 2025-10 ABSENT (the real ADR-049 gap) · 2025-11
--     present (so 2025-10 has a LATER period and is therefore "due") · nothing after.
-- That single shape reaches all four gap classes plus the below-coverage edge.
-- ---------------------------------------------------------------------
delete from pfin.cpi_u_index;
insert into pfin.cpi_u_index (cpi_period, cpi_value) values
  ('2025-08-01', 323.976),
  ('2025-09-01', 324.800),
  ('2025-11-01', 326.100);

-- (z1) the trailing edge is where the fixture says it is — every `beyond_coverage` /
--      `unrecorded_gap` assertion below is a claim ABOUT this value.
select is(
  (select max(cpi_period) from pfin.cpi_u_index), '2025-11-01'::date,
  '(z1) fixture pin: the trailing edge of cpi_u_index is 2025-11-01 — the boundary that decides `unrecorded_gap` (a later period exists) from `beyond_coverage` (none does) for every probe below'
);
-- (z2) the gap is a real absence, not a row with a NULL value (053 forbids that anyway).
select is(
  (select count(*) from pfin.cpi_u_index where cpi_period = '2025-10-01')::bigint, 0::bigint,
  '(z2) fixture pin: 2025-10-01 is ABSENT from cpi_u_index — the schema-forced drop ADR-049 was written for. (B2)/(B3) both probe this period, so its absence is the premise of the load-bearing pair'
);
-- (z3) the record table starts empty — it is IMMUTABLE, so this is checked, not enforced.
select is(
  (select count(*) from pfin.cpi_u_nonpublication)::bigint, 0::bigint,
  '(z3) fixture pin: cpi_u_nonpublication is EMPTY before (B2). It cannot be cleared (immutable at every tier), so a pre-existing record on the DB under test would silently turn (B2) into a second (B3) — this is the assumption that has to be checked because it cannot be enforced'
);

-- =====================================================================
-- LEG (A) WHO MAY EXECUTE — the isolation question that actually bites on a global helper.
--   ACL facts AND attempted calls, each role proven both ways.
-- =====================================================================
select ok(
  has_function_privilege('authenticated', 'pfin.fn_cpi_u_index_for_period(date)', 'execute'),
  '(A1) ACL positive: authenticated HOLDS EXECUTE — the ADR-023 Step 0 read path (both tables are PURE-GLOBAL, so reads execute under authenticated). RED if the grant were dropped, which would break every consumer of the ONE helper the CPI gap policy is allowed to live in'
);
select ok(
  not has_function_privilege('public', 'pfin.fn_cpi_u_index_for_period(date)', 'execute'),
  '(A2) LOAD-BEARING: PUBLIC does NOT hold EXECUTE. `create function` grants EXECUTE to PUBLIC by default, so 064''s explicit revoke is the whole of the access control — and its removal is SILENT: every behavioural leg in this file would stay green while the function became callable by every role in the cluster'
);
select ok(
  not has_function_privilege('anon', 'pfin.fn_cpi_u_index_for_period(date)', 'execute'),
  '(A3) anon holds NO EXECUTE — a second fence in front of anon''s lack of USAGE on schema pfin'
);
select ok(
  not has_function_privilege('service_role', 'pfin.fn_cpi_u_index_for_period(date)', 'execute'),
  '(A4) service_role holds NO EXECUTE — MEASURED CURRENT POSTURE (064 revokes from PUBLIC and grants only to authenticated), pinned so a broad `grant execute on all functions in schema pfin to service_role` cannot land silently. ⚠ Stated as least-privilege, NOT as an isolation fence: both tables read here are global with `using (true)`, so service_role''s rolbypassrls has no tenant boundary to bypass. If a server-side or ETL path ever needs this helper, that is a deliberate grant change and a review'
);
select ok(
  _rls.stmt_denied_as('anon', $q$ select 1 from pfin.fn_cpi_u_index_for_period('2025-09-01') $q$),
  '(A5) anon behavioural: an actual call AS anon is REFUSED with insufficient_privilege (42501). Probed via _rls.stmt_denied_as (called and asserted at postgres) because anon holds no USAGE on the pgTAP schema either — asserting under anon would fail for the wrong reason'
);
select ok(
  _rls.stmt_denied_as('service_role', $q$ select 1 from pfin.fn_cpi_u_index_for_period('2025-09-01') $q$),
  '(A6) service_role behavioural: an actual call AS service_role is REFUSED with insufficient_privilege — (A4) exercised rather than inspected. (V1) proves both have teeth'
);
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  $$ select 1 from pfin.fn_cpi_u_index_for_period('2025-09-01') $$,
  '(A7) non-vacuous positive: an authenticated caller CAN execute the helper — so (A2)-(A6) are real fences around a live function, not the uniform silence of a function nobody can call'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (B) THE FOUR gap_class OUTCOMES — each reached by real data state.
--   Full-row results_eq: cardinality AND all five columns in one assertion, so a leg cannot
--   pass on the right class with a wrong value (or the right value with a wrong provenance).
-- =====================================================================
-- (B1) EXACT PRINT.
select results_eq(
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class
       from pfin.fn_cpi_u_index_for_period('2025-09-01') $$,
  $$ values ('2025-09-01'::date, 324.800::numeric, false, '2025-09-01'::date, 'published'::text) $$,
  '(B1) published: a period with its own print returns that print, is_carried = false, and carried_from set to the period ITSELF rather than NULL — so "where did this value come from?" has the same answer SHAPE in every row a consumer receives. Asserted on all five columns at once'
);
-- (B2) ABSENT, LATER PERIOD PRESENT, NO RECORD YET.
select results_eq(
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class
       from pfin.fn_cpi_u_index_for_period('2025-10-01') $$,
  $$ values ('2025-10-01'::date, 324.800::numeric, true, '2025-09-01'::date, 'unrecorded_gap'::text) $$,
  '(B2) unrecorded_gap: 2025-10 is absent and 2025-11 IS present, so the period was due and nothing explains it. The value is CARRIED from 2025-09 and says so — is_carried = true with carried_from naming the source. Silent carry-forward on a monthly-complete series understates inflation for the gap month; the provenance columns are the mechanism that makes it non-silent'
);

-- ⭐ THE ONE VARIABLE CHANGES HERE — and only this one. Same function, same argument, same
--    cpi_u_index contents. The 063 record is the entire difference between (B2) and (B3).
insert into pfin.cpi_u_nonpublication (cpi_period, published_value_raw)
  values ('2025-10-01', '-');

-- (B3) THE SAME PERIOD, AFTER THE RECORD LANDS.
select results_eq(
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class
       from pfin.fn_cpi_u_index_for_period('2025-10-01') $$,
  $$ values ('2025-10-01'::date, 324.800::numeric, true, '2025-09-01'::date, 'recorded_nonpublication'::text) $$,
  '(B3) ⭐ recorded_nonpublication: the SAME period as (B2), with the ONLY difference being the 063 record. This is the pair that proves the record is consulted at all — a suite reaching the two classes from two different periods would pass without ever showing that. Note the carry outcome is IDENTICAL to (B2): gap_class reports the ABSENCE REASON and is orthogonal to what could be resolved, exactly as 064 documents. This is also the ONLY probe sensitive to the record-vs-contiguity ORDER — the interior gap is where both branches are true at once (see (V3a))'
);
-- (B4) TRAILING EDGE — nothing later is present.
select results_eq(
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class
       from pfin.fn_cpi_u_index_for_period('2026-01-01') $$,
  $$ values ('2026-01-01'::date, 326.100::numeric, true, '2025-11-01'::date, 'beyond_coverage'::text) $$,
  '(B4) beyond_coverage: absent with NO later period present. NOT an alarm — 064''s bound is data-derived rather than calendar-derived, so it consults no clock and is outside ADR-044''s two-clock hazard. ITS STATED COST, which this leg does NOT and cannot cover: a stalled ingest yields this same class indefinitely, indistinguishable from "not yet published"'
);

-- (B5) PRECEDENCE — the record is consulted FIRST, so it works where contiguity cannot.
insert into pfin.cpi_u_nonpublication (cpi_period, published_value_raw)
  values ('2026-02-01', '-');
select is(
  (select gap_class from pfin.fn_cpi_u_index_for_period('2026-02-01')),
  'recorded_nonpublication',
  '(B5) TRAILING-EDGE COMPLEMENTARITY: a period BEYOND the trailing edge that HAS a record classifies recorded_nonpublication, NOT beyond_coverage — the record is consulted, and consulted ahead of the `else` branch that would otherwise swallow it. ⚠ PRECISE ABOUT WHAT THIS DOES AND DOES NOT SEE: it is sensitive to the record being consulted AT ALL (proven in (V3b)), but NOT to the record-vs-contiguity ORDER — at the trailing edge those two branches are mutually exclusive. The order is observable only at the interior gap, which is (B3), and (V3a) measures it there'
);

-- (B6) EXACTLY ONE ROW, ALWAYS — across every class plus the below-coverage edge.
select is(
  (select count(*) from (
     select * from pfin.fn_cpi_u_index_for_period('2025-09-01')
     union all select * from pfin.fn_cpi_u_index_for_period('2025-10-01')
     union all select * from pfin.fn_cpi_u_index_for_period('2026-01-01')
     union all select * from pfin.fn_cpi_u_index_for_period('2026-02-01')
     union all select * from pfin.fn_cpi_u_index_for_period('2014-01-01')
   ) s)::bigint,
  5::bigint,
  '(B6) exactly ONE row per call, across all four gap classes plus the below-coverage edge (5 calls, 5 rows). A consumer must never have to distinguish "the function returned nothing" from "the answer is nothing" — that ambiguity on a financial surface is the silence ADR-049 Decision 4 exists to prevent'
);

-- =====================================================================
-- LEG (C) FAIL-CLOSED INPUTS.
-- =====================================================================
-- (C1) NULL raises rather than returning an empty set.
select throws_like(
  $$ select * from pfin.fn_cpi_u_index_for_period(null) $$,
  '%p_period is required%',
  '(C1) fail-LOUD on NULL: a CPI-U lookup with no period raises, message-precise. A silent empty result would be indistinguishable from "there is no CPI data" on a surface feeding inflation-adjusted figures — the same class of defect as the silent carry-forward the row return exists to prevent'
);
-- (C2) mid-month normalizes AND says which period answered.
select results_eq(
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class
       from pfin.fn_cpi_u_index_for_period('2025-09-17') $$,
  $$ values ('2025-09-01'::date, 324.800::numeric, false, '2025-09-01'::date, 'published'::text) $$,
  '(C2) NON-SILENT normalization: a mid-month date resolves to the CPI grain AND the normalized period is RETURNED as cpi_period, so the caller is TOLD which period answered instead of having to know. RED if the normalization were dropped (no row) or made silent (the input date echoed back)'
);
-- (C3) normalization happens BEFORE classification.
select is(
  (select gap_class from pfin.fn_cpi_u_index_for_period('2025-10-20')),
  'recorded_nonpublication',
  '(C3) normalization precedes classification: a mid-month probe INSIDE the gap month resolves to 2025-10-01 and picks up that period''s record. RED if classification ran against the raw input, which would never match a first-of-month key and would misclassify every mid-month probe as an unrecorded gap'
);
-- (C4) below coverage — NULL, never a fabricated zero.
select results_eq(
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class
       from pfin.fn_cpi_u_index_for_period('2014-01-01') $$,
  $$ values ('2014-01-01'::date, null::numeric, false, null::date, 'unrecorded_gap'::text) $$,
  '(C4) below coverage: nothing at or before the period exists, so cpi_value is NULL, is_carried is false and carried_from is NULL — the "no carry source" case, REPORTED rather than papered over. ⚠ NULL and not 0: a zero is a plausible-looking number that would silently understate a real-terms figure by 100%, where NULL forces the consumer to handle the unknown. (V4) makes that world real'
);

-- (C5) the empty-table edge — savepoint-scoped, since it removes the fixture.
savepoint c_empty_index;
delete from pfin.cpi_u_index;
select results_eq(
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class
       from pfin.fn_cpi_u_index_for_period('2025-09-01') $$,
  $$ values ('2025-09-01'::date, null::numeric, false, null::date, 'beyond_coverage'::text) $$,
  '(C5) empty-source edge: with cpi_u_index holding NO rows at all, the helper still returns EXACTLY ONE row, with a NULL value and beyond_coverage — it does not return an empty set, does not raise, and does not fabricate a zero. This is the state a fresh deploy is in before the first ETL run, so a consumer meets it on day one'
);
rollback to savepoint c_empty_index;

-- (C6) zone-invariance differential (ADR-044). 064 makes the ::timestamp cast load-bearing so
--      nothing here is evaluated in the session TimeZone. ⚠ HONEST SCOPE: this leg asserts
--      INVARIANCE; its calibration — the proof that a zone-differential probe of this shape can
--      DETECT a zone-dependent body at all — lives in 062's (V10b) and is not repeated here.
--      Two zones a full day apart at the month boundary; the probe date is chosen so a zone
--      fold would move it into the PREVIOUS month and change the answer.
set local TimeZone = 'Pacific/Kiritimati';
select gap_class as zone_east from pfin.fn_cpi_u_index_for_period('2025-10-01') \gset
set local TimeZone = 'Pacific/Midway';
select gap_class as zone_west from pfin.fn_cpi_u_index_for_period('2025-10-01') \gset
reset TimeZone;
select is(
  :'zone_east'::text, :'zone_west'::text,
  '(C6) zone-invariance (ADR-044): the same probe on a first-of-month boundary classifies identically under Pacific/Kiritimati and Pacific/Midway (a full day apart), so the period normalization is not evaluated in the session TimeZone. A zone fold here would push the probe into the previous month and change the class. Calibration of this probe shape lives in 062 (V10b) — not repeated, and not claimed as proven here'
);

-- =====================================================================
-- LEG (D) TENANT-INVARIANCE — the two-tenant fixture, polarity inverted.
-- =====================================================================
-- (D0) the identities really differ (without this, (D1) is blindness, not robustness).
select _rls.set_tenant(:'ta'::uuid);
select is((select auth.uid()), :'ta'::uuid,
  '(D0) identity anchor: the tenant A execution context really IS tenant A — so (D1)''s equality is INVARIANCE over a variable that actually varied'
);
select md5(coalesce(string_agg(r::text, '|' order by r.cpi_period), '')) as diga from (
  select * from pfin.fn_cpi_u_index_for_period('2025-09-01')
  union all select * from pfin.fn_cpi_u_index_for_period('2025-10-01')
  union all select * from pfin.fn_cpi_u_index_for_period('2026-01-01')
  union all select * from pfin.fn_cpi_u_index_for_period('2026-02-01')
  union all select * from pfin.fn_cpi_u_index_for_period('2014-01-01')
) r \gset
select count(*) as rowsa from (
  select * from pfin.fn_cpi_u_index_for_period('2025-09-01')
  union all select * from pfin.fn_cpi_u_index_for_period('2014-01-01')
) r \gset
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'tb'::uuid);
select md5(coalesce(string_agg(r::text, '|' order by r.cpi_period), '')) as digb from (
  select * from pfin.fn_cpi_u_index_for_period('2025-09-01')
  union all select * from pfin.fn_cpi_u_index_for_period('2025-10-01')
  union all select * from pfin.fn_cpi_u_index_for_period('2026-01-01')
  union all select * from pfin.fn_cpi_u_index_for_period('2026-02-01')
  union all select * from pfin.fn_cpi_u_index_for_period('2014-01-01')
) r \gset
select set_config('role', 'postgres', true);

select isnt(
  :'rowsa'::bigint, 0::bigint,
  '(D1) non-vacuity for (D2): tenant A''s probe returns rows at all — so the digest compared below is over real content, not over two identically-empty results'
);
select is(
  :'diga'::text, :'digb'::text,
  '(D2) SECURITY INVOKER over two GLOBAL tables: tenant A and tenant B receive byte-identical output across all five probe periods. The INVOKER posture gives each caller exactly what their own policies permit, and both `using (true)` policies permit the same thing — so RED here means a tenant predicate was introduced into a helper reading two tables that have no tenant column'
);

-- =====================================================================
-- LEG (E) POSTURE PINS — catalog facts that no behavioural assertion can see.
-- =====================================================================
select ok(
  (select not p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_cpi_u_index_for_period'),
  '(E1) SECURITY INVOKER, not DEFINER (ADR-011 Lock 11 read-composition). 064 declares the Decision 9 DEFINER allowlist delta as +0 and this is what holds it: a conversion to DEFINER is an allowlist change and a Sec-veto surface, and it would change WHOSE policies the two reads run under while every behavioural leg in this file stayed green'
);
select is(
  (select p.provolatile::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_cpi_u_index_for_period'),
  's',
  '(E2) STABLE: the function is declared STABLE (provolatile = s) — it reads tables and consults no clock, which is exactly the volatility class 064''s data-derived bound argues for. A VOLATILE marking would signal side effects this function must never have'
);
select ok(
  (select 'search_path=""' = any(p.proconfig) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_cpi_u_index_for_period'),
  '(E3) `set search_path = ''''` is in force — the search_path-injection fence. Every object reference in the body is schema-qualified accordingly, so its removal would not break the function; it would only remove the fence, silently'
);
select is(
  (select pg_get_function_result(p.oid) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_cpi_u_index_for_period'),
  'TABLE(cpi_period date, cpi_value numeric, is_carried boolean, carried_from date, gap_class text)',
  '(E4) ⭐ THE RETURN IS A ROW, AND STAYS A ROW. 064: a consumer wanting only the number must EXPLICITLY PROJECT THE OTHER COLUMNS AWAY, which turns "don''t ignore carried-ness" from a rule someone must REMEMBER into a step someone must TAKE — and a deliberate projection is visible in a diff where an unread boolean is not. Narrowing this to `returns numeric` removes the only mechanism enforcing non-silence, and removes it invisibly: every behavioural leg above would still pass. (V2) measures exactly that'
);

-- =====================================================================
-- LEG (V) INVERSION — each fence broken on purpose, inside a savepoint.
-- =====================================================================

-- ---- (V1) do the EXECUTE negatives have teeth? ----
savepoint v_exec_grant;
grant execute on function pfin.fn_cpi_u_index_for_period(date) to service_role;
select ok(
  has_function_privilege('service_role', 'pfin.fn_cpi_u_index_for_period(date)', 'execute')
  and not _rls.stmt_denied_as('service_role', $q$ select 1 from pfin.fn_cpi_u_index_for_period('2025-09-01') $q$),
  '(V1-EXECUTE-NEGATIVES-HAVE-TEETH) (A4)/(A6) are not vacuous: one `grant execute` flips BOTH the ACL fact and the attempted call. Needed because an absence assertion whose subject can never appear proves nothing — `not has_function_privilege` against a role that simply never holds grants looks identical to a real revoke'
);
rollback to savepoint v_exec_grant;

-- ---- (V2) does the row-return assertion have teeth, and is it really the only fence? ----
savepoint v_scalar_return;
drop function pfin.fn_cpi_u_index_for_period(date);
create function pfin.fn_cpi_u_index_for_period(p_period date)
returns numeric
language plpgsql stable security invoker set search_path = '' as $qa$
begin
  -- The "simplification" 064 forbids: the number, and nothing else.
  return (select c.cpi_value from pfin.cpi_u_index c
           where c.cpi_period <= date_trunc('month', p_period::timestamp)::date
           order by c.cpi_period desc limit 1);
end;
$qa$;
select is(
  (select pg_get_function_result(p.oid) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_cpi_u_index_for_period'),
  'numeric',
  '(V2-ROW-RETURN-HAS-TEETH) ⚠ (E4) is not vacuous — and the replacement above is the POINT, not the mechanism: it carries 2025-09''s value into the 2025-10 gap and returns it as a bare number, with the carried-ness and the gap class GONE. That is a defensible piece of arithmetic and a silent understatement of inflation at the same time, and (E4) is the ONLY assertion in this file that would notice. Behaviourally it still answers every question the (B) legs ask'
);
rollback to savepoint v_scalar_return;

-- ---- (V3) does the classification ORDER matter, and does (B5) detect it? ----
savepoint v_class_order;
create or replace function pfin.fn_cpi_u_index_for_period(p_period date)
returns table (cpi_period date, cpi_value numeric, is_carried boolean,
               carried_from date, gap_class text)
language plpgsql stable security invoker set search_path = '' as $qa$
#variable_conflict use_column
declare v_period date; v_from date; v_val numeric; v_max date; v_class text;
begin
  v_period := date_trunc('month', p_period::timestamp)::date;
  return query select v_period, c.cpi_value, false, v_period, 'published'::text
    from pfin.cpi_u_index c where c.cpi_period = v_period;
  if found then return; end if;
  select c.cpi_period, c.cpi_value into v_from, v_val from pfin.cpi_u_index c
   where c.cpi_period < v_period order by c.cpi_period desc limit 1;
  select max(c.cpi_period) into v_max from pfin.cpi_u_index c;
  -- THE ONLY CHANGE: contiguity is tested BEFORE the record. Reads as a harmless reordering.
  if v_max is not null and v_max > v_period then
    v_class := 'unrecorded_gap';
  elsif exists (select 1 from pfin.cpi_u_nonpublication n where n.cpi_period = v_period) then
    v_class := 'recorded_nonpublication';
  else
    v_class := 'beyond_coverage';
  end if;
  return query select v_period, v_val, (v_from is not null), v_from, v_class;
end;
$qa$;
-- ⚠ REFUTED HYPOTHESIS, KEPT AS THE FINDING. This leg was first written to assert that the
--   reordering flips (B5) — the TRAILING-EDGE probe. THE RUN SAID recorded_nonpublication, i.e.
--   unchanged. The reason is worth more than the assertion was: at the trailing edge the two
--   swapped branches are MUTUALLY EXCLUSIVE (no later period exists, so the contiguity arm is
--   false either way) and the record arm still wins over the `else`. The ordering is therefore
--   load-bearing at the INTERIOR gap — the one period where BOTH conditions are true at once —
--   and that is 2025-10-01, the (B3) probe. So the ordering mutation is asserted against (B3)
--   here, and (B5)'s own teeth are proven by a DIFFERENT mutation in (V3b).
select is(
  (select gap_class from pfin.fn_cpi_u_index_for_period('2025-10-01')),
  'unrecorded_gap',
  '(V3a-CLASSIFICATION-ORDER-HAS-TEETH) (B3) is not vacuous: with contiguity tested before the record — a reordering that reads as harmless and that (B1)/(B2)/(B4)/(B5) all still pass — the ONE period the source actually published valueless silently reclassifies as an unrecorded gap. The interior gap is where the two branches are both true, so it is the only place the ORDER can be observed at all'
);
rollback to savepoint v_class_order;

-- ---- (V3b) does (B5) detect the record being consulted at all, at the trailing edge? ----
savepoint v_record_dropped;
create or replace function pfin.fn_cpi_u_index_for_period(p_period date)
returns table (cpi_period date, cpi_value numeric, is_carried boolean,
               carried_from date, gap_class text)
language plpgsql stable security invoker set search_path = '' as $qa$
#variable_conflict use_column
declare v_period date; v_from date; v_val numeric; v_max date; v_class text;
begin
  v_period := date_trunc('month', p_period::timestamp)::date;
  return query select v_period, c.cpi_value, false, v_period, 'published'::text
    from pfin.cpi_u_index c where c.cpi_period = v_period;
  if found then return; end if;
  select c.cpi_period, c.cpi_value into v_from, v_val from pfin.cpi_u_index c
   where c.cpi_period < v_period order by c.cpi_period desc limit 1;
  select max(c.cpi_period) into v_max from pfin.cpi_u_index c;
  -- THE ONLY CHANGE: the cpi_u_nonpublication consultation is gone entirely — the shape 064
  -- would have had if the helper had been written against 053 alone.
  if v_max is not null and v_max > v_period then
    v_class := 'unrecorded_gap';
  else
    v_class := 'beyond_coverage';
  end if;
  return query select v_period, v_val, (v_from is not null), v_from, v_class;
end;
$qa$;
select is(
  (select gap_class from pfin.fn_cpi_u_index_for_period('2026-02-01')),
  'beyond_coverage',
  '(V3b-TRAILING-EDGE-RECORD-CONSULTATION-HAS-TEETH) (B5) is not vacuous: with the record consultation removed, a period the source PUBLISHED VALUELESS at the trailing edge reclassifies as beyond_coverage — "not yet published". THE POINT: at the trailing edge the contiguity test has nothing to see, so the 063 record is the ONLY evidence that exists, and its loss is invisible to every other leg in this file'
);
rollback to savepoint v_record_dropped;

-- ---- (V4) can the no-fabricated-zero assertion actually fire? ----
savepoint v_zero_fill;
create or replace function pfin.fn_cpi_u_index_for_period(p_period date)
returns table (cpi_period date, cpi_value numeric, is_carried boolean,
               carried_from date, gap_class text)
language plpgsql stable security invoker set search_path = '' as $qa$
#variable_conflict use_column
declare v_period date; v_from date; v_val numeric;
begin
  v_period := date_trunc('month', p_period::timestamp)::date;
  select c.cpi_period, c.cpi_value into v_from, v_val from pfin.cpi_u_index c
   where c.cpi_period <= v_period order by c.cpi_period desc limit 1;
  -- The $0 defect: an unknown, rendered as a number.
  return query select v_period, coalesce(v_val, 0::numeric), (v_from is not null and v_from <> v_period),
                      v_from, 'unrecorded_gap'::text;
end;
$qa$;
select is(
  (select cpi_value from pfin.fn_cpi_u_index_for_period('2014-01-01')),
  0::numeric,
  '(V4-ZERO-FABRICATION-HAS-TEETH) (C4)/(C5) are not vacuous: a one-word `coalesce(v_val, 0)` — the kind of change made to stop a NULL propagating through a SUM downstream — turns "we have no CPI level for this period" into "the CPI level was zero". A real-terms figure computed against it is understated by 100% and looks entirely normal. Nothing but an explicit NULL assertion catches this'
);
rollback to savepoint v_zero_fill;

-- ---- (V5) STRUCTURAL, DELIBERATELY LAST + OUTSIDE ANY SAVEPOINT ----
--   Two jobs: it asserts the (V) block put the function back exactly as authored (three of the
--   legs above REPLACED it, and a battery that left a stub behind would invalidate everything
--   after it), and it re-arms pgTAP's plan counter after the savepoint rewinds. Moving this leg
--   off the end, or inside a savepoint, silently re-breaks the plan arithmetic.
select ok(
  (select pg_get_function_result(p.oid) = 'TABLE(cpi_period date, cpi_value numeric, is_carried boolean, carried_from date, gap_class text)'
      and not p.prosecdef and p.provolatile = 's'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_cpi_u_index_for_period')
  and not has_function_privilege('service_role', 'pfin.fn_cpi_u_index_for_period(date)', 'execute'),
  '(V5-FUNCTION-RESTORED-AND-PLAN-COUNTER-REARMED) structural: after the inversion block the function is back to its authored shape (row return, INVOKER, STABLE) and the EXECUTE grant it opened did not survive — so nothing above was evaluated against a stub this file left behind. It also re-arms pgTAP''s plan counter after the savepoint rewinds, so this file cannot emit a spurious "planned N but ran M" that would train a reader to discount the one diagnostic distinguishing a genuinely aborted run'
);

select * from finish();
rollback;

-- =====================================================================
-- Per-Wave battery — pfin.fn_cpi_u_index_for_period(date)
--   THE single CPI-U consumption helper (ADR-049 Decision 4 / migration 064)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/064_fn_cpi_u_index_for_period.sql
--   - pfin.fn_cpi_u_index_for_period(p_period date)
--       returns table (cpi_period date, cpi_value numeric, is_carried boolean,
--                      carried_from date, gap_class text, nonpublication_on_record boolean)
--       SECURITY INVOKER · STABLE · set search_path = ''  (ADR-011 Lock 11 read-composition
--       over pfin.cpi_u_index (053) and pfin.cpi_u_nonpublication (063), both GLOBAL with
--       `using (true)` SELECT policies)
--   - revoke execute ... from public   (EXECUTE is granted to PUBLIC by default — the revoke
--                                      is the whole of the access control, and its removal is
--                                      SILENT: every behavioural leg here would stay green)
--   - grant execute ... to authenticated
--   - gap_class TEXT set (FIVE members): published / recorded_nonpublication / unrecorded_gap /
--                                before_coverage / beyond_coverage
--
-- ⚠ THIS BATTERY PINS A SIGNATURE 064 ITSELF CALLS PROVISIONAL. 064's `comment on function`
--   states the gap_class MEMBER SET is provisional pending the ADR-049 Decision 5 product
--   ruling (the PRD §2.4.4 non-silent-staleness amendment plus the two-tier marker, PM-owned
--   and not yet F/CTO-ratified), because Decision 4 locked the composite return and left the
--   SIGNATURE to the implementing PR. So (B8a) and (E4) are STATE PINS, not fences: when that
--   ruling lands they are EXPECTED to go red and are to be updated, not defended. Stated here
--   so a future reader does not read a red (B8a) as a regression and "fix" the function back.
--   What is NOT provisional, per the same comment, and IS a fence: both coverage edges are
--   bounded — (C4)/(B8b)/(V7) hold that independently of any product ruling.
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
-- ┌─ THE FIVE gap_class OUTCOMES ARE REACHED BY REAL DATA STATE, NOT BY ARGUMENT SHAPE ────────┐
-- │   published               (B1)  2025-09-01 — its own print exists                           │
-- │   unrecorded_gap          (B2)  2025-10-01 — absent, STRICTLY INTERIOR, no record yet       │
-- │                           (B2b) 2025-07-01 — a second interior gap NO leg ever records, so   │
-- │                                  the alarm class stays reachable after (B3) converts 2025-10 │
-- │   recorded_nonpublication (B3)  2025-10-01 — THE SAME PERIOD, after the 063 record lands    │
-- │   before_coverage         (C4)  2014-01-01 — earlier than the leading edge. NOT an alarm    │
-- │   beyond_coverage         (B4)  2026-01-01 — later than the trailing edge. NOT an alarm     │
-- │ (B2)/(B3) are the load-bearing pair: same function, same argument, same table contents      │
-- │ EXCEPT the one row 063 exists to hold. A suite that reached the two classes from two        │
-- │ different periods would pass without ever showing that the RECORD is what changed the       │
-- │ answer. Varying exactly one variable is the whole design of this leg.                       │
-- │ (B5) pins the EDGE COMPLEMENTARITY: a record beyond the trailing edge classifies             │
-- │ recorded_nonpublication, because at an edge the extent test has nothing to see and the       │
-- │ record is the only evidence there is. (V3b) removes the consultation and watches it flip.    │
-- │ (B7) pins the AUDIT TRAIL — record present AND the period later published — which reads      │
-- │ gap_class = 'published' AND nonpublication_on_record = true. That pairing is NOT derivable   │
-- │ from gap_class, and (V6) is the proof: the derived form is correct in all four other states. │
-- │ (B8a)/(B8b) pin the closed set and ALARM UNIQUENESS. Bounding both edges is what makes       │
-- │ `unrecorded_gap` mean STRICTLY INTERIOR — bracketed by prints on both sides — and therefore  │
-- │ the one class worth alarming on. (V7) restores the unbounded-leading-edge world, in which    │
-- │ every period back to year zero raises the alarm and the alarm gets trained away.             │
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
-- │  (V3a) DEMOTE the record below the edge rules -> (B5) flips; (V3a2) …and (B3) does NOT.      │
-- │ (V3b)  REMOVE the record from classification  -> (B5) flips; (V3b2) …and (B3) DOES.          │
-- │        ⚠ TWO MUTATIONS, DIFFERENT BLAST RADII, AND THE CONCLUSION INVERTED ONCE ALREADY.     │
-- │        Against the original THREE-branch shape, precedence was observable at the interior    │
-- │        and not at the edge. Under the FIVE-branch exhaustive shape it is the reverse — the   │
-- │        interior case IS the final `else`, so a demotion cannot move it and only a removal    │
-- │        can. Both the flip and the NON-flip are asserted in each pair: an instrument's limit  │
-- │        is worth as much as its reach, and asserting only the half that moved would leave     │
-- │        the other half looking covered. Two drafts of these legs were refuted by the run.     │
-- │   (V4) fabricate 0 where the value is unknown -> (C4)/(C5) flip: the $0 defect, made real    │
-- │   (V6) derive nonpublication_on_record from gap_class -> (B7) flips: correct in four states  │
-- │        out of five, wrong in exactly the one the column exists for                           │
-- │   (V7) unbound the leading edge -> (C4)/(B8b) flip: reproduces the pre-fix alarm defect      │
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
--   (B2b) -> the alarm class becoming unreachable by any probe once (B3) records 2025-10. A
--            second, never-recorded interior gap keeps (B8b) meaningful.
--   (B5)  -> the 063 record dropping out of the classification, OR being demoted below the edge
--            rules. At an edge the extent test has nothing to see, so the record is the ONLY
--            evidence available. ⚠ (B5) catches BOTH mutations; (B3) catches only removal —
--            measured in (V3a2)/(V3b2), not assumed.
--   (B7)  -> the audit trail becoming unreachable. A period in BOTH tables short-circuits to
--            gap_class = 'published', so without the sixth column the "unpublished when we
--            looked, published later" case cannot be seen through the one helper consumers may
--            call — and 063 retains those rows specifically so it can be.
--   (B8a) -> a branch emitting something outside the closed set, or a period falling through
--            with a NULL class. ⚠ STATE PIN, not a fence — see the provisional-signature note.
--   (B8b) -> the alarm firing on more than the one class that earns it. This is the assertion
--            that would have caught the pre-fix leading-edge defect in production terms: an
--            alarm that fires on all of history is an alarm nobody reads.
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
--            100%, where NULL forces the consumer to handle the unknown. (C4) ALSO catches the
--            leading edge going unbounded again, which would classify a pre-coverage period as
--            the alarm — (V7) reproduces that world.
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

select plan(44);

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
  ('2025-06-01', 322.500),
  ('2025-08-01', 323.976),
  ('2025-09-01', 324.800),
  ('2025-11-01', 326.100);

-- (z1) the trailing edge is where the fixture says it is — every `beyond_coverage` assertion
--      below is a claim ABOUT this value.
select is(
  (select max(cpi_period) from pfin.cpi_u_index), '2025-11-01'::date,
  '(z1) fixture pin: the trailing edge of cpi_u_index is 2025-11-01 — the boundary above which a period is `beyond_coverage` rather than interior'
);
-- (z1b) the LEADING edge, added when 064 gained `before_coverage`. Both edges are now bounded,
--       so `unrecorded_gap` means STRICTLY INTERIOR and both edges must be pinned, not just one.
select is(
  (select min(cpi_period) from pfin.cpi_u_index), '2025-06-01'::date,
  '(z1b) fixture pin: the LEADING edge of cpi_u_index is 2025-06-01 — the boundary below which a period is `before_coverage` rather than an alarm. Pinned because 064 now bounds BOTH edges: with only the trailing edge pinned, every pre-coverage assertion below would be a claim about an unstated value'
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
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class, nonpublication_on_record
       from pfin.fn_cpi_u_index_for_period('2025-09-01') $$,
  $$ values ('2025-09-01'::date, 324.800::numeric, false, '2025-09-01'::date, 'published'::text, false) $$,
  '(B1) published: a period with its own print returns that print, is_carried = false, and carried_from set to the period ITSELF rather than NULL — so "where did this value come from?" has the same answer SHAPE in every row a consumer receives. nonpublication_on_record is false: this period was never observed valueless. Asserted on all six columns at once'
);
-- (B2) ABSENT, STRICTLY INTERIOR, NO RECORD YET.
select results_eq(
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class, nonpublication_on_record
       from pfin.fn_cpi_u_index_for_period('2025-10-01') $$,
  $$ values ('2025-10-01'::date, 324.800::numeric, true, '2025-09-01'::date, 'unrecorded_gap'::text, false) $$,
  '(B2) unrecorded_gap: 2025-10 is absent and is BRACKETED BY PRINTS ON BOTH SIDES (2025-09 and 2025-11), so it was demonstrably due and nothing explains it. That bracketing is what makes this the one class worth alarming on. The value is CARRIED from 2025-09 and says so — silent carry-forward on a monthly-complete series understates inflation for the gap month, and the provenance columns are what make it non-silent'
);
-- (B2b) THE PERMANENT ALARM PROBE. (B2) stops being an unrecorded gap the moment (B3) records
--       it, so a second interior gap is seeded that NO leg ever records — otherwise every later
--       leg would be reasoning about a class no probe still reaches.
select results_eq(
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class, nonpublication_on_record
       from pfin.fn_cpi_u_index_for_period('2025-07-01') $$,
  $$ values ('2025-07-01'::date, 322.500::numeric, true, '2025-06-01'::date, 'unrecorded_gap'::text, false) $$,
  '(B2b) unrecorded_gap, permanent probe: 2025-07 is interior (bracketed by 2025-06 and 2025-08) and is never recorded by any leg in this file, so the ALARM class stays reachable after (B3) converts 2025-10. (B8b) depends on this probe existing'
);

-- ⭐ THE ONE VARIABLE CHANGES HERE — and only this one. Same function, same argument, same
--    cpi_u_index contents. The 063 record is the entire difference between (B2) and (B3).
insert into pfin.cpi_u_nonpublication (cpi_period, published_value_raw)
  values ('2025-10-01', '-');

-- (B3) THE SAME PERIOD, AFTER THE RECORD LANDS.
select results_eq(
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class, nonpublication_on_record
       from pfin.fn_cpi_u_index_for_period('2025-10-01') $$,
  $$ values ('2025-10-01'::date, 324.800::numeric, true, '2025-09-01'::date, 'recorded_nonpublication'::text, true) $$,
  '(B3) ⭐ recorded_nonpublication: the SAME period as (B2), with the ONLY difference being the 063 record. This is the pair that proves the record is consulted at all — a suite reaching the two classes from two different periods would pass without ever showing that. Note the carry outcome is IDENTICAL to (B2): gap_class reports the ABSENCE REASON and is orthogonal to what could be resolved, exactly as 064 documents. This is also the ONLY probe sensitive to the record-vs-contiguity ORDER — the interior gap is where both branches are true at once (see (V3a))'
);
-- (B4) TRAILING EDGE — nothing later is present.
select results_eq(
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class, nonpublication_on_record
       from pfin.fn_cpi_u_index_for_period('2026-01-01') $$,
  $$ values ('2026-01-01'::date, 326.100::numeric, true, '2025-11-01'::date, 'beyond_coverage'::text, false) $$,
  '(B4) beyond_coverage: absent, later than the trailing edge. NOT an alarm — 064''s bound is data-derived rather than calendar-derived, so it consults no clock and is outside ADR-044''s two-clock hazard. ITS STATED COST, which this leg does NOT and cannot cover: a stalled ingest yields this same class indefinitely, indistinguishable from "not yet published"'
);

-- (B5) PRECEDENCE — the record is consulted FIRST, so it works where contiguity cannot.
insert into pfin.cpi_u_nonpublication (cpi_period, published_value_raw)
  values ('2026-02-01', '-');
select is(
  (select gap_class from pfin.fn_cpi_u_index_for_period('2026-02-01')),
  'recorded_nonpublication',
  '(B5) TRAILING-EDGE COMPLEMENTARITY: a period BEYOND the trailing edge that HAS a record classifies recorded_nonpublication, NOT beyond_coverage — the record is consulted, and consulted ahead of the `else` branch that would otherwise swallow it. ⚠ PRECISE ABOUT WHAT THIS DOES AND DOES NOT SEE: it is sensitive to the record being consulted AT ALL (proven in (V3b)), but NOT to the record-vs-contiguity ORDER — at the trailing edge those two branches are mutually exclusive. The order is observable only at the interior gap, which is (B3), and (V3a) measures it there'
);

-- (B6) EXACTLY ONE ROW, ALWAYS — across all five classes.
select is(
  (select count(*) from (
     select * from pfin.fn_cpi_u_index_for_period('2025-09-01')
     union all select * from pfin.fn_cpi_u_index_for_period('2025-07-01')
     union all select * from pfin.fn_cpi_u_index_for_period('2025-10-01')
     union all select * from pfin.fn_cpi_u_index_for_period('2014-01-01')
     union all select * from pfin.fn_cpi_u_index_for_period('2026-01-01')
     union all select * from pfin.fn_cpi_u_index_for_period('2026-02-01')
   ) s)::bigint,
  6::bigint,
  '(B6) exactly ONE row per call, across all five gap classes (6 calls, 6 rows). A consumer must never have to distinguish "the function returned nothing" from "the answer is nothing" — that ambiguity on a financial surface is the silence ADR-049 Decision 4 exists to prevent'
);

-- ---------------------------------------------------------------------
-- (B7) ⭐ THE AUDIT TRAIL, AND WHY IT NEEDED A SIXTH COLUMN.
--   063 retains a record after the period is later published — a period present in BOTH tables
--   reads as "unpublished when we looked, published later", and 063 calls that the audit trail.
--   But the helper short-circuits on the exact print, so gap_class reads 'published' in exactly
--   that case and the audit trail was UNREACHABLE through the only helper consumers are
--   permitted to use. nonpublication_on_record is what makes it reachable, and it is
--   DELIBERATELY NOT DERIVABLE from gap_class — (V6) is the proof of the non-derivability.
--   Savepoint-scoped: filling the 2025-10 gap would change what (C3) and (B8b) probe.
-- ---------------------------------------------------------------------
savepoint b_published_later;
insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2025-10-01', 325.400);
select results_eq(
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class, nonpublication_on_record
       from pfin.fn_cpi_u_index_for_period('2025-10-01') $$,
  $$ values ('2025-10-01'::date, 325.400::numeric, false, '2025-10-01'::date, 'published'::text, true) $$,
  '(B7) ⭐ "unpublished when we looked, published later": with BOTH a 063 record and a later 053 print for the same period, gap_class reads `published` — correctly, the print is real — AND nonpublication_on_record reads TRUE. That pairing IS the audit trail 063 exists to preserve, and before the sixth column existed it was unreachable through the one helper consumers are allowed to call. RED if the column were dropped, or wired to gap_class'
);
rollback to savepoint b_published_later;

-- (B8a)/(B8b) THE CLOSED SET AND THE ALARM. 064 now classifies exhaustively with every branch
--   positive, and `unrecorded_gap` means STRICTLY INTERIOR — which is what makes it the ONE
--   class worth alarming on. Both halves are asserted: membership, and alarm-uniqueness.
select is(
  (select count(*) from (
     select gap_class from pfin.fn_cpi_u_index_for_period('2025-09-01')
     union all select gap_class from pfin.fn_cpi_u_index_for_period('2025-07-01')
     union all select gap_class from pfin.fn_cpi_u_index_for_period('2025-10-01')
     union all select gap_class from pfin.fn_cpi_u_index_for_period('2014-01-01')
     union all select gap_class from pfin.fn_cpi_u_index_for_period('2026-01-01')
     union all select gap_class from pfin.fn_cpi_u_index_for_period('2026-02-01')
   ) s where gap_class not in
     ('published', 'recorded_nonpublication', 'unrecorded_gap', 'before_coverage', 'beyond_coverage')
  )::bigint,
  0::bigint,
  '(B8a) closed set: every one of the six probes returns a member of the five-element gap_class set — no NULL, no empty string, no unclassified fall-through. RED if a branch were added that emits something outside the set, or if a period fell through the classification with a NULL class'
);
select is(
  (select count(*) from (
     select gap_class from pfin.fn_cpi_u_index_for_period('2025-09-01')
     union all select gap_class from pfin.fn_cpi_u_index_for_period('2025-07-01')
     union all select gap_class from pfin.fn_cpi_u_index_for_period('2025-10-01')
     union all select gap_class from pfin.fn_cpi_u_index_for_period('2014-01-01')
     union all select gap_class from pfin.fn_cpi_u_index_for_period('2026-01-01')
     union all select gap_class from pfin.fn_cpi_u_index_for_period('2026-02-01')
   ) s where gap_class = 'unrecorded_gap')::bigint,
  1::bigint,
  '(B8b) ALARM UNIQUENESS: of the six probes — one published, one interior gap, one recorded, one before the leading edge, one beyond the trailing edge, one recorded beyond the edge — EXACTLY ONE returns the alarm class. That is the whole point of bounding both edges: before the fix, every pre-coverage period reported as an unrecorded gap, so the alarm fired on spans nobody ever claimed to hold and would have been trained away. (V7) restores that world and watches this go to 2'
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
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class, nonpublication_on_record
       from pfin.fn_cpi_u_index_for_period('2025-09-17') $$,
  $$ values ('2025-09-01'::date, 324.800::numeric, false, '2025-09-01'::date, 'published'::text, false) $$,
  '(C2) NON-SILENT normalization: a mid-month date resolves to the CPI grain AND the normalized period is RETURNED as cpi_period, so the caller is TOLD which period answered instead of having to know. RED if the normalization were dropped (no row) or made silent (the input date echoed back)'
);
-- (C3) normalization happens BEFORE classification.
select is(
  (select gap_class from pfin.fn_cpi_u_index_for_period('2025-10-20')),
  'recorded_nonpublication',
  '(C3) normalization precedes classification: a mid-month probe INSIDE the gap month resolves to 2025-10-01 and picks up that period''s record. RED if classification ran against the raw input, which would never match a first-of-month key and would misclassify every mid-month probe as an unrecorded gap'
);
-- (C4) BEFORE the leading edge — NULL, never a fabricated zero, and NOT the alarm class.
select results_eq(
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class, nonpublication_on_record
       from pfin.fn_cpi_u_index_for_period('2014-01-01') $$,
  $$ values ('2014-01-01'::date, null::numeric, false, null::date, 'before_coverage'::text, false) $$,
  '(C4) before_coverage: earlier than anything held, so cpi_value is NULL, is_carried is false and carried_from is NULL — the "no carry source" case, REPORTED rather than papered over. ⚠ TWO fences in one row. (i) NULL and not 0: a zero is a plausible-looking number that would silently understate a real-terms figure by 100%, where NULL forces the consumer to handle the unknown ((V4) makes that world real). (ii) `before_coverage` and NOT `unrecorded_gap`: a period the backfill never claimed to cover is not an unexplained gap, and classifying it as one fires the alarm on all of history ((V7) restores that world)'
);

-- (C5) the empty-table edge — savepoint-scoped, since it removes the fixture.
savepoint c_empty_index;
delete from pfin.cpi_u_index;
select results_eq(
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class, nonpublication_on_record
       from pfin.fn_cpi_u_index_for_period('2025-09-01') $$,
  $$ values ('2025-09-01'::date, null::numeric, false, null::date, 'beyond_coverage'::text, false) $$,
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
  'TABLE(cpi_period date, cpi_value numeric, is_carried boolean, carried_from date, gap_class text, nonpublication_on_record boolean)',
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

-- ---- (V3a) is the RECORD-vs-INTERIOR order load-bearing, and which probe can see it? ----
savepoint v_class_order;
create or replace function pfin.fn_cpi_u_index_for_period(p_period date)
returns table (cpi_period date, cpi_value numeric, is_carried boolean,
               carried_from date, gap_class text, nonpublication_on_record boolean)
language plpgsql stable security invoker set search_path = '' as $qa$
#variable_conflict use_column
declare v_period date; v_from date; v_val numeric; v_min date; v_max date;
        v_class text; v_recorded boolean;
begin
  v_period := date_trunc('month', p_period::timestamp)::date;
  v_recorded := exists (select 1 from pfin.cpi_u_nonpublication n where n.cpi_period = v_period);
  return query select v_period, c.cpi_value, false, v_period, 'published'::text, v_recorded
    from pfin.cpi_u_index c where c.cpi_period = v_period;
  if found then return; end if;
  select c.cpi_period, c.cpi_value into v_from, v_val from pfin.cpi_u_index c
   where c.cpi_period < v_period order by c.cpi_period desc limit 1;
  select min(c.cpi_period), max(c.cpi_period) into v_min, v_max from pfin.cpi_u_index c;
  -- THE ONLY CHANGE: the classification is made purely EDGE-BASED, with the record consulted
  -- only where no edge rule applies. Reads as a tidy-up — every branch is still positive and
  -- the set is still closed — and it is the shape a reviewer would most plausibly wave through.
  if v_max is null then
    v_class := 'beyond_coverage';
  elsif v_period < v_min then
    v_class := 'before_coverage';
  elsif v_period > v_max then
    v_class := 'beyond_coverage';
  elsif v_recorded then
    v_class := 'recorded_nonpublication';
  else
    v_class := 'unrecorded_gap';
  end if;
  return query select v_period, v_val, (v_from is not null), v_from, v_class, v_recorded;
end;
$qa$;
-- ⚠ TWO REFUTATIONS AND AN INVERSION, RECORDED BECAUSE THE CONCLUSION FLIPPED WITH THE CODE.
--   Against the ORIGINAL three-branch shape (record / contiguity / else) this leg was written to
--   flip the TRAILING-EDGE probe and was refuted: the order was observable only at the INTERIOR.
--   Re-aimed at the interior against the FIVE-branch shape, it was refuted AGAIN — and the reason
--   is the inversion. In the exhaustive form the interior case IS the final `else`, so demoting
--   the record below the edge rules cannot change an interior answer: the record branch is still
--   the last thing before the else and still claims it. What the demotion DOES change is the
--   EDGES, where an explicit `v_period > v_max` branch now claims the period first.
--   >> SO PRECEDENCE MOVED HOUSE: under the old shape it was observable at the interior and not
--   at the edge; under the new shape it is observable at the edge and not at the interior. <<
--   Both directions are asserted below — the flip AND the non-flip — because an instrument's
--   limit is worth exactly as much as its reach, and asserting only the half that moved would
--   leave the other half looking covered.
select is(
  (select gap_class from pfin.fn_cpi_u_index_for_period('2026-02-01')),
  'beyond_coverage',
  '(V3a-EDGE-PRECEDENCE-HAS-TEETH) (B5) is not vacuous: with the record DEMOTED below the edge rules — still consulted, just later — a period the source published valueless beyond the trailing edge is claimed by the `> v_max` branch first and reports as "not yet published". The demotion reads as a pure tidy-up: every branch stays positive, the set stays closed, and nothing is deleted'
);
select is(
  (select gap_class from pfin.fn_cpi_u_index_for_period('2025-10-01')),
  'recorded_nonpublication',
  '(V3a2-…AND-THE-INTERIOR-CANNOT-SEE-IT) ⚠ THE LIMIT OF (V3a), ASSERTED RATHER THAN ASSUMED: the SAME demotion leaves the interior gap UNCHANGED, because in the exhaustive five-branch form the interior case is the final `else` and the record branch still precedes it. So (B3) is blind to a demotion and (B5) is not — the exact reverse of the three-branch shape, where the first draft of this leg measured the opposite. This is why (V3b) exists: removing the record is a different mutation from demoting it, and only removal reaches the interior'
);
rollback to savepoint v_class_order;

-- ---- (V3b) does (B5) detect the record being consulted at all, at the trailing edge? ----
savepoint v_record_dropped;
create or replace function pfin.fn_cpi_u_index_for_period(p_period date)
returns table (cpi_period date, cpi_value numeric, is_carried boolean,
               carried_from date, gap_class text, nonpublication_on_record boolean)
language plpgsql stable security invoker set search_path = '' as $qa$
#variable_conflict use_column
declare v_period date; v_from date; v_val numeric; v_min date; v_max date;
        v_class text; v_recorded boolean;
begin
  v_period := date_trunc('month', p_period::timestamp)::date;
  v_recorded := exists (select 1 from pfin.cpi_u_nonpublication n where n.cpi_period = v_period);
  return query select v_period, c.cpi_value, false, v_period, 'published'::text, v_recorded
    from pfin.cpi_u_index c where c.cpi_period = v_period;
  if found then return; end if;
  select c.cpi_period, c.cpi_value into v_from, v_val from pfin.cpi_u_index c
   where c.cpi_period < v_period order by c.cpi_period desc limit 1;
  select min(c.cpi_period), max(c.cpi_period) into v_min, v_max from pfin.cpi_u_index c;
  -- THE ONLY CHANGE: the record no longer participates in CLASSIFICATION at all — the shape 064
  -- would have had if written against 053 alone. Note the sixth column is still populated, so
  -- the mutation is isolated to the classification and nothing else can account for the flip.
  if v_max is null then v_class := 'beyond_coverage';
  elsif v_period < v_min then v_class := 'before_coverage';
  elsif v_period > v_max then v_class := 'beyond_coverage';
  else v_class := 'unrecorded_gap';
  end if;
  return query select v_period, v_val, (v_from is not null), v_from, v_class, v_recorded;
end;
$qa$;
select is(
  (select gap_class from pfin.fn_cpi_u_index_for_period('2026-02-01')),
  'beyond_coverage',
  '(V3b-TRAILING-EDGE-RECORD-CONSULTATION-HAS-TEETH) (B5) is not vacuous: with the record removed from the classification, a period the source PUBLISHED VALUELESS beyond the trailing edge reclassifies as beyond_coverage — "not yet published". At an edge the extent test has nothing to see, so the 063 record is the ONLY evidence that exists'
);
select is(
  (select gap_class from pfin.fn_cpi_u_index_for_period('2025-10-01')),
  'unrecorded_gap',
  '(V3b2-INTERIOR-RECORD-CONSULTATION-HAS-TEETH) …and (B3) flips too — which (V3a)''s demotion could NOT achieve. REMOVING the record and DEMOTING it are different mutations with different blast radii, and this is the one that reaches the interior: the period the source actually published valueless raises the alarm class, so the table 063 exists to fill would be written, read, and then ignored'
);
rollback to savepoint v_record_dropped;

-- ---- (V4) can the no-fabricated-zero assertion actually fire? ----
savepoint v_zero_fill;
create or replace function pfin.fn_cpi_u_index_for_period(p_period date)
returns table (cpi_period date, cpi_value numeric, is_carried boolean,
               carried_from date, gap_class text, nonpublication_on_record boolean)
language plpgsql stable security invoker set search_path = '' as $qa$
#variable_conflict use_column
declare v_period date; v_from date; v_val numeric;
begin
  v_period := date_trunc('month', p_period::timestamp)::date;
  select c.cpi_period, c.cpi_value into v_from, v_val from pfin.cpi_u_index c
   where c.cpi_period <= v_period order by c.cpi_period desc limit 1;
  -- The $0 defect: an unknown, rendered as a number.
  return query select v_period, coalesce(v_val, 0::numeric), (v_from is not null and v_from <> v_period),
                      v_from, 'before_coverage'::text, false;
end;
$qa$;
select is(
  (select cpi_value from pfin.fn_cpi_u_index_for_period('2014-01-01')),
  0::numeric,
  '(V4-ZERO-FABRICATION-HAS-TEETH) (C4)/(C5) are not vacuous: a one-word `coalesce(v_val, 0)` — the kind of change made to stop a NULL propagating through a SUM downstream — turns "we have no CPI level for this period" into "the CPI level was zero". A real-terms figure computed against it is understated by 100% and looks entirely normal. Nothing but an explicit NULL assertion catches this'
);
rollback to savepoint v_zero_fill;

-- ---- (V6) is nonpublication_on_record really NOT derivable from gap_class? ----
--   064 states the column is deliberately not derivable. That is a claim about INFORMATION, and
--   the only way to test it is to build the derived version and find a state where it is wrong.
--   The state is the audit trail: record present AND the period later published.
savepoint v_derived_flag;
insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2025-10-01', 325.400);
create or replace function pfin.fn_cpi_u_index_for_period(p_period date)
returns table (cpi_period date, cpi_value numeric, is_carried boolean,
               carried_from date, gap_class text, nonpublication_on_record boolean)
language plpgsql stable security invoker set search_path = '' as $qa$
#variable_conflict use_column
declare v_period date; v_from date; v_val numeric; v_min date; v_max date;
        v_class text; v_recorded boolean;
begin
  v_period := date_trunc('month', p_period::timestamp)::date;
  v_recorded := exists (select 1 from pfin.cpi_u_nonpublication n where n.cpi_period = v_period);
  -- THE ONLY CHANGE: the sixth column is DERIVED from gap_class instead of read from the table.
  -- This is the "simplification" the column's own contract warns against, and it looks correct
  -- in every state except one.
  return query select v_period, c.cpi_value, false, v_period, 'published'::text,
                      ('published' = 'recorded_nonpublication')
    from pfin.cpi_u_index c where c.cpi_period = v_period;
  if found then return; end if;
  select c.cpi_period, c.cpi_value into v_from, v_val from pfin.cpi_u_index c
   where c.cpi_period < v_period order by c.cpi_period desc limit 1;
  select min(c.cpi_period), max(c.cpi_period) into v_min, v_max from pfin.cpi_u_index c;
  if v_recorded then v_class := 'recorded_nonpublication';
  elsif v_max is null then v_class := 'beyond_coverage';
  elsif v_period < v_min then v_class := 'before_coverage';
  elsif v_period > v_max then v_class := 'beyond_coverage';
  else v_class := 'unrecorded_gap';
  end if;
  return query select v_period, v_val, (v_from is not null), v_from, v_class,
                      (v_class = 'recorded_nonpublication');
end;
$qa$;
select is(
  (select nonpublication_on_record from pfin.fn_cpi_u_index_for_period('2025-10-01')),
  false,
  '(V6-SIXTH-COLUMN-IS-NOT-DERIVABLE) ⭐ (B7) is not vacuous, and the column earns its existence: with nonpublication_on_record DERIVED from gap_class, the audit-trail state — record present, period later published — reports FALSE, because gap_class correctly reads `published` there. The derived version is right in all four other states, which is exactly what makes it the change someone would make. The audit trail 063 exists to preserve would be silently unreachable through the only helper consumers may call'
);
rollback to savepoint v_derived_flag;

-- ---- (V7) does bounding the LEADING edge have teeth — i.e. was there a real alarm defect? ----
savepoint v_leading_edge;
create or replace function pfin.fn_cpi_u_index_for_period(p_period date)
returns table (cpi_period date, cpi_value numeric, is_carried boolean,
               carried_from date, gap_class text, nonpublication_on_record boolean)
language plpgsql stable security invoker set search_path = '' as $qa$
#variable_conflict use_column
declare v_period date; v_from date; v_val numeric; v_max date;
        v_class text; v_recorded boolean;
begin
  v_period := date_trunc('month', p_period::timestamp)::date;
  v_recorded := exists (select 1 from pfin.cpi_u_nonpublication n where n.cpi_period = v_period);
  return query select v_period, c.cpi_value, false, v_period, 'published'::text, v_recorded
    from pfin.cpi_u_index c where c.cpi_period = v_period;
  if found then return; end if;
  select c.cpi_period, c.cpi_value into v_from, v_val from pfin.cpi_u_index c
   where c.cpi_period < v_period order by c.cpi_period desc limit 1;
  select max(c.cpi_period) into v_max from pfin.cpi_u_index c;
  -- THE ONLY CHANGE: the leading edge is unbounded again — the pre-fix shape, in which any
  -- period earlier than coverage falls through to the alarm class.
  if v_recorded then v_class := 'recorded_nonpublication';
  elsif v_max is not null and v_max > v_period then v_class := 'unrecorded_gap';
  else v_class := 'beyond_coverage';
  end if;
  return query select v_period, v_val, (v_from is not null), v_from, v_class, v_recorded;
end;
$qa$;
select is(
  (select gap_class from pfin.fn_cpi_u_index_for_period('2014-01-01')),
  'unrecorded_gap',
  '(V7-LEADING-EDGE-BOUND-HAS-TEETH) ⚠ (C4)/(B8b) are not vacuous, and this reproduces the DEFECT the bound was added to fix: with the leading edge unbounded, a period a decade before anything the store ever claimed to cover reports as an unrecorded gap — the ALARM class. Every period in history back to year zero would do the same, which is how an alarm gets trained away. This is the world before the fix, kept runnable so the fix cannot silently regress'
);
rollback to savepoint v_leading_edge;

-- ---- (V5) STRUCTURAL, DELIBERATELY LAST + OUTSIDE ANY SAVEPOINT ----
--   Two jobs: it asserts the (V) block put the function back exactly as authored (five of the
--   legs above REPLACED it, and a battery that left a stub behind would invalidate everything
--   after it), and it re-arms pgTAP's plan counter after the savepoint rewinds. Moving this leg
--   off the end, or inside a savepoint, silently re-breaks the plan arithmetic.
select ok(
  (select pg_get_function_result(p.oid) = 'TABLE(cpi_period date, cpi_value numeric, is_carried boolean, carried_from date, gap_class text, nonpublication_on_record boolean)'
      and not p.prosecdef and p.provolatile = 's'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_cpi_u_index_for_period')
  and not has_function_privilege('service_role', 'pfin.fn_cpi_u_index_for_period(date)', 'execute'),
  '(V5-FUNCTION-RESTORED-AND-PLAN-COUNTER-REARMED) structural: after the inversion block the function is back to its authored shape (row return, INVOKER, STABLE) and the EXECUTE grant it opened did not survive — so nothing above was evaluated against a stub this file left behind. It also re-arms pgTAP''s plan counter after the savepoint rewinds, so this file cannot emit a spurious "planned N but ran M" that would train a reader to discount the one diagnostic distinguishing a genuinely aborted run'
);

select * from finish();
rollback;

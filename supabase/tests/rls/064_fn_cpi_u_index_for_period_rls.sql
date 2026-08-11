-- =====================================================================
-- Per-Wave battery — pfin.fn_cpi_u_index_for_period(date)
--   THE single CPI-U consumption helper (ADR-049 Decision 4 / migration 064)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/066_fn_cpi_u_index_for_period_due_and_coverage.sql
--   (which DROPPED + RECREATED the function first authored at 064; 064 carries a supersession
--    banner. The binding moved to 066 because the RETURN TYPE changed, and `create or replace`
--    cannot change a return type — see the (V)-block note below, which this file learned the
--    hard way.)
--   - pfin.fn_cpi_u_index_for_period(p_period date)
--       returns table (cpi_period date, cpi_value numeric, is_carried boolean,
--                      carried_from date, gap_class text, nonpublication_on_record boolean,
--                      period_was_due boolean, coverage_through date)
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
-- ┌─ ⚠ THE C4 PROVISIONALITY IS CLEARED — AND A STANDING REQUIREMENT REPLACED IT ─────────────┐
-- │ THIS BLOCK PREVIOUSLY SAID the signature was provisional pending the ADR-049 Decision 5    │
-- │ product ruling, and that (B8a)/(E4) were therefore STATE PINS rather than fences. THAT IS  │
-- │ NO LONGER TRUE, and leaving it would be worse than saying nothing: a caveat naming no live │
-- │ dependency tells a reader the surface is someone else's problem. BOTH inputs it named are  │
-- │ discharged — PRD §2.4.4 was F/CTO-ratified 2026-08-10, and 066 supplied the result shape   │
-- │ §2.4.4 routed onward as architecture-layer detail.                                        │
-- │ SO (B8a) AND (E4) ARE NOW FENCES, NOT STATE PINS. A red (B8a) is a regression to diagnose, │
-- │ NOT an expected update to wave through — the exact reverse of what this block used to say. │
-- │ WHAT REPLACES THE PROVISIONALITY (standing, not expiring): the gap_class member set and    │
-- │ the return shape are a CHANGE-CONTROLLED surface. Extending either is an ADR-049 amendment │
-- │ plus a Sec joint-review, because this is the ONE helper consumers may resolve the gap      │
-- │ policy through — a member added here silently changes what every consuming surface renders.│
-- │ The still-open residue is per-surface signal threading (how §2.4.4's two signals reach the │
-- │ presentation layer). That is NOT a survival of the old caveat and does not touch this      │
-- │ signature; recorded so the two are not conflated.                                          │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
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
-- ┌─ ⚠ THE TWO COLUMNS 066 ADDED, AND THE ROW ON WHICH THEY DISAGREE ─────────────────────────┐
-- │ period_was_due — §2.4.4's MARKER GATE: "The informational marker therefore fires only where │
-- │   the period was actually due, and never where the absence is explained by the edge of      │
-- │   coverage alone." A consumer's rule is `is_carried AND period_was_due`.                    │
-- │   TRUE  on published / recorded_nonpublication / unrecorded_gap.                            │
-- │   FALSE at BOTH coverage edges and on an empty store.                                       │
-- │                                                                                             │
-- │ ⭐ WHY (B9) IS THE HIGHEST-VALUE LEG IN THIS FILE. §2.4.4 says, in as many words: "The       │
-- │   trigger is whether a value could be resolved, not why the period is absent — the two are  │
-- │   INDEPENDENT, and a reason-for-absence must never be read as a proxy for the carry         │
-- │   outcome." The collapse that sentence forbids is `period_was_due := is_carried`, and it is │
-- │   invisible on every row where the two agree. (B9) is the reachable row where they          │
-- │   DISAGREE: a recorded_nonpublication with NOTHING at or before it returns period_was_due   │
-- │   TRUE, is_carried FALSE, cpi_value NULL — §2.4.4's "uncomputable is not stale" case, which │
-- │   renders UNAVAILABLE WITH A REASON rather than as a marked number. (V8) makes the collapse │
-- │   real and watches (B9) flip. Without that pair the alias passes the whole battery.         │
-- │                                                                                             │
-- │ ⚠ (B4) IS NOT AN EDGE CASE — IT IS THE DEFAULT PATH. CPI-U publishes one to two months in   │
-- │   arrears, so EVERY current-month figure is `beyond_coverage` with is_carried TRUE. Its     │
-- │   period_was_due is FALSE, so it draws NO marker. A consumer reading is_carried alone as    │
-- │   the trigger marks every figure it ever renders, always — which §2.4.4 rules out by name   │
-- │   ("A marker present on every figure at all times would carry no information").             │
-- │                                                                                             │
-- │ coverage_through — §2.4.4's DATED BASIS LINE ("real terms, CPI-U through March 2026"),      │
-- │   which must "name the period it runs through". The latest print held, ON EVERY PATH        │
-- │   INCLUDING 'published', NULL only on an empty store. That "including published" is the     │
-- │   whole of rider A′ and the one control-flow change 066 made: under 064 the trailing edge   │
-- │   was recoverable only on the beyond_coverage path, and a basis line renderable only when   │
-- │   the data is stale is not a basis line. (V9) is its regression guard.                      │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ ⚠ WHY EVERY (V) MUTANT DECLARES ALL EIGHT COLUMNS — MEASURED, NOT ANTICIPATED ───────────┐
-- │ `create or replace function` CANNOT change a return type, and `returns table (...)` IS the  │
-- │ return type. When 066 widened the return 6 -> 8, the five (V) legs that rebuild the function│
-- │ via create-or-replace at the OLD six-column shape did not fail as assertions — they raised  │
-- │ `cannot change return type of existing function`, which ABORTS THE TRANSACTION and cascades │
-- │ every following statement into "current transaction is aborted".                            │
-- │ MEASURED on the unmodified battery against 066 (scratch DB, 2026-08-10): 35 passed, 2 failed│
-- │ ((E4) and (V5)), 5 hard aborts, SEVEN ASSERTIONS NEVER RAN, "planned 44 but ran 37" —       │
-- │ ⚠ AND psql EXITED 0. The plan mismatch was the only signal, and it is exactly the diagnostic│
-- │ the harness note below warns a reader not to be trained into discounting.                   │
-- │ THIS IS THE SAME HAZARD THE LEG-ORDER NOTE BELOW RECORDS AT (E)/(B), REACHED BY A DIFFERENT │
-- │ MECHANISM: there a dropped COLUMN aborted the txn, here a changed RETURN TYPE does. So the  │
-- │ rule generalizes past the fix that was applied to it — ANY future change to this function's │
-- │ return shape must update all five (V) mutants IN THE SAME PR, or the battery loses seven    │
-- │ assertions while reporting a zero exit code.                                                │
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
-- │   (V8) ⭐ collapse period_was_due into an alias for is_carried -> (B9) flips, and NOTHING     │
-- │        ELSE in this file does. The one-line "simplification" §2.4.4 forbids by name           │
-- │   (V9) move the coverage extent back BELOW the exact-print branch (the 064 shape) ->          │
-- │        (B1)/(C2) flip: coverage_through goes NULL on 'published', so the dated basis line     │
-- │        is renderable only when the data is stale. The rider-A′ regression, made real          │
-- │   (V5) structural, OUTSIDE any savepoint: the function is back, and the plan counter with it │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ DISCRIMINATOR RUNS — the battery mutated AGAINST THE REAL MIGRATION, measured 2026-08-10 ─┐
-- │ The (V) legs mutate a function this file replaced itself. That proves the primary legs have │
-- │ teeth against a mutant, which is NOT the same as proving they track the SHIPPED contract.   │
-- │ So the migration itself was mutated in a scratch copy and the battery re-run. Recorded here │
-- │ because a green suite cannot tell you any of it, and re-runnable by the same method.        │
-- │   D1  remove the `v_period < v_min` branch (pre-coverage falls back to the alarm — Sec's C1 │
-- │       defect, exactly) -> RED at (B8b) and (C4). Two legs, both naming the leading edge.    │
-- │   D2  drop the sixth column from the return  -> RED at (E4), the leg that names the cause.  │
-- │   D3  make the empty-store branch alarm      -> RED at (C5). The zero-row branch IS reached.│
-- │  ── added for 066, measured the same way against a scratch copy of 066 itself ──             │
-- │   D4  collapse period_was_due into `v_from is not null` on the gap path                      │
-- │                                             -> RED at (B4), (B8c), (B9). 45 pass.            │
-- │   D5  move the min/max BELOW the exact-print branch (revert rider A′)                        │
-- │                                             -> RED at (B1), (B7), (C2). 45 pass. Every GAP   │
-- │       path still reports the edge correctly — the defect is visible only where data is fresh.│
-- │   D6  declare `unrecorded_gap` NOT due (narrow the marker gate)                              │
-- │                                             -> RED at (B2), (B2b), (B8c). 45 pass.           │
-- │   D7  delete 066's `revoke execute … from public` — THE HAZARD THE DROP CREATED               │
-- │                                             -> RED at (A2), (A3), (A4), (A6), (V5). 43 pass. │
-- │       ⚠ (A5) STAYS GREEN, and that is correct, not a miss: anon holds no USAGE on schema     │
-- │       pfin, so the behavioural call is still refused by a SECOND, independent fence even     │
-- │       though the ACL went wide. The ACL assertion (A3) is what sees it. This is the concrete │
-- │       demonstration that (A3)'s "second fence" wording is load-bearing and that an ACL fact  │
-- │       and a behavioural probe are not substitutes for one another.                           │
-- │   D8  ⭐ THE MUTATION ONLY (B9) CATCHES. `v_due and (v_from is not null)` on the gap path —   │
-- │       the defensive-looking edit "don't claim the period was due if we carried nothing".      │
-- │                                             -> RED at (B9) ALONE. 47 pass.                   │
-- │       D4 reddens three legs, so D4 alone would NOT prove (B9) is individually necessary.     │
-- │       D8 is the one that does: strip (B9) and this defect ships with a fully green battery.  │
-- │       ⚠ SO BE PRECISE ABOUT (B9)'s CLAIM. It is NOT "the only leg that catches an alias" —   │
-- │       (B4) and (B8c) catch the symmetric collapse too. It is the only leg that catches the   │
-- │       collapse in the direction due=TRUE / carried=FALSE, because it is the only row in the  │
-- │       file where the two disagree in that direction. Measured, not reasoned.                 │
-- │ ⚠ D2 IS WHY LEG (E) RUNS BEFORE LEG (B). With the catalog pins last, D2's first six-column  │
-- │ results_eq raised `column "nonpublication_on_record" does not exist`, ABORTED the txn, and  │
-- │ cascaded ~40 "current transaction is aborted" lines — the run still failed, so the fence    │
-- │ held, but the reader got no diagnosis and (E4) never ran. Reordered; D2 now names itself.   │
-- │                                                                                             │
-- │ ⚠ AND A PREDICTION THAT NAMED THE WRONG LEG — kept because the distinction is reusable.     │
-- │ Running the PRE-EXTENSION battery against the POST-e1c68f7 migration was expected to turn   │
-- │ (V2) — the `returns numeric` inversion — red. IT DID NOT, and could not: (V2) replaces the  │
-- │ function with its OWN mutant and asserts THAT mutant's signature, so it is invariant to     │
-- │ what the real function does. The legs that actually went red were (C4), (E4) and (V5) — the │
-- │ ones whose subject is the SHIPPED object. THE GENERAL RULE: an inversion leg calibrates a   │
-- │ primary assertion; it never tracks the contract, because its subject is something the test  │
-- │ built. Do not read a green (V) leg as evidence the contract is unchanged.                   │
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
--   (B8c) -> the MARKER GATE widening. §2.4.4: the informational marker fires "only where the
--            period was actually due, and never where the absence is explained by the edge of
--            coverage alone". This asserts the not-due set is EXACTLY the two coverage-edge
--            probes — the complement of (B8b), and the assertion that would catch a future
--            branch quietly marking itself due.
--   (B9)  -> ⭐ period_was_due being collapsed into an alias for is_carried. This is the ONLY
--            reachable row where the two DISAGREE (recorded_nonpublication with nothing at or
--            before it: due TRUE, carried FALSE, value NULL), so it is the only leg an alias
--            would redden. §2.4.4 forbids the collapse in as many words — "a reason-for-absence
--            must never be read as a proxy for the carry outcome" — and this row is also
--            §2.4.4's "uncomputable is not stale" case, which renders UNAVAILABLE rather than
--            as a marked number. (V8) proves the leg has teeth. It ALSO pins that the record
--            branch outranks `before_coverage`, the leading-edge twin of what (B5) pins at the
--            trailing edge.
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
--   (V8)  -> ⭐ (B9) being vacuous. The collapse `period_was_due := is_carried` is a plausible
--            one-line tidy-up that agrees with the truth on every OTHER row in this file, so
--            without a leg that reddens on it the alias ships green. This is the "invariance is
--            not robustness" check for the marker gate: (B9) is made to fail once, on purpose.
--   (V9)  -> (B1)/(C2)'s coverage_through being vacuous. Restores 064's control flow, where the
--            min/max sat BELOW the exact-print branch and 'published' therefore returned a NULL
--            trailing edge. That is the rider-A′ defect: the §2.4.4 basis line would render only
--            on surfaces whose data is stale, which is precisely where a basis line is not what
--            the user needs. One statement moved; nothing else in the battery notices.
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
--   authored here, not copied from production. The 2019-01 non-publication record (B9)/(V8) seed
--   is likewise INVENTED — chosen only because it sits below the fixture's leading edge, which is
--   what makes the carry window empty; it corresponds to no real BLS event. No auth.users rows
--   are needed (no auth.users FK; `using (true)` never dereferences auth.uid()). All in a
--   rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so no
--   `_rls.*` call runs while switched to authenticated; every _rls.set_tenant is called at
--   role=postgres and each block restores role=postgres. \gset var names are ALL-LOWERCASE.
--   anon / service_role denials are probed with _rls.stmt_denied_as (called and asserted at
--   postgres) rather than by running pgTAP under a role that may hold no EXECUTE on it.
--
-- ⟦WIRE-VALIDATE⟧ VERIFIED LOCALLY, NON-DESTRUCTIVELY. For 066 the method changed, because the
--   migration DROPS and RECREATES the function and a rolled-back transaction cannot exercise a
--   drop-and-regrant honestly. A THROWAWAY SCRATCH DATABASE was created on the local cluster
--   (roles are cluster-level, so authenticated/anon/service_role are the real ones), the auth
--   schema mirrored, all 66 migrations applied in order, this battery run, and the database
--   DROPPED afterwards. ⚠ NO `supabase db reset` AT ANY POINT — that wipes the developer's live
--   test data; the 137 real cpi_u_index rows in the working database were counted before and
--   after and were untouched. The battery itself still runs inside `begin … rollback`.
--   The authoritative run is CI's 001->066 reset stack (pg_prove directory-mode).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

-- PLAN = 48. Was 44 through 064; 066 adds (B8c), (B9), (V8), (V9).
-- ⚠ MEASURED, NOT COUNTED BY GREP: a naive `grep -c` over assertion names lands on 43 because
--   several legs open their call on a continuation line. Both a call-site count and a distinct
--   leg-label count were run against this file and both return the same number. If you change
--   this plan, re-measure both ways — pg_prove compares the PRINTED plan against the PRINTED
--   test lines, and a plan that is merely plausible fails the run.
select plan(48);

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
--
-- ⚠⚠ DO NOT PRUNE THIS LEG AS REDUNDANT — 066 PROMOTED IT FROM PIN TO FENCE. These four ACL
--   assertions passed unchanged across 064 -> 066, and a reader who diffs the battery will see
--   an untouched block and conclude it is inert. THE OPPOSITE HAPPENED. 066 could not use
--   `create or replace` (the return type changed), so it had to `DROP FUNCTION` and CREATE.
--   ⚠ `drop function` TAKES THE ACL WITH IT, and PostgreSQL grants EXECUTE **to PUBLIC** by
--   default on every freshly created function. So the revoke/grant pair in 066 is not
--   boilerplate carried over from 064 — it is the only thing standing between this drop-and-
--   recreate and a function feeding financial figures being callable by every role in the
--   cluster. Omitting it would have widened access WHILE LOOKING EXACTLY LIKE SUCCESS: the
--   function works, every behavioural leg in this file stays green, and nothing says a word.
--   (A2) is the assertion that would have caught it. It is now load-bearing for a hazard that
--   did not exist when it was written, and it will be load-bearing again for the NEXT migration
--   that changes this function's return shape — because that one will have to DROP as well.
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

-- ⚠ RUN ORDER IS DELIBERATE: the CATALOG pins run BEFORE the behavioural legs. Measured
--   2026-08-10 against a mutated migration with the sixth column dropped — with leg (E)
--   last, the first six-column results_eq raised `column "nonpublication_on_record" does
--   not exist`, which ABORTS the transaction and cascades every later assertion into
--   "current transaction is aborted". The run still fails, so the fence held — but the
--   reader is handed forty error lines and no diagnosis, and (E4), the leg that actually
--   NAMES the cause, never got to run. Ordering the signature pin first converts an abort
--   cascade into one named red. Same principle as message-precise throws_like: a fence
--   that fires is worth less than a fence that says which fence it was.
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
  'TABLE(cpi_period date, cpi_value numeric, is_carried boolean, carried_from date, gap_class text, nonpublication_on_record boolean, period_was_due boolean, coverage_through date)',
  '(E4) ⭐ THE RETURN IS A ROW, AND STAYS A ROW — now EIGHT columns (066). A consumer wanting only the number must EXPLICITLY PROJECT THE OTHER COLUMNS AWAY, which turns "don''t ignore carried-ness" from a rule someone must REMEMBER into a step someone must TAKE — and a deliberate projection is visible in a diff where an unread boolean is not. Narrowing this to `returns numeric` removes the only mechanism enforcing non-silence, and removes it invisibly: every behavioural leg above would still pass. (V2) measures exactly that. ⚠ THIS ASSERTION IS ALSO THE BATTERY''S ONLY LOUD DETECTOR OF A RETURN-SHAPE CHANGE: when 066 widened the return 6 -> 8, this leg and (V5) were the only two that failed as assertions — the nine full-row results_eq legs below kept passing because they PROJECT their columns explicitly, and five (V) legs did not fail at all but ABORTED the transaction. Measured, not assumed'
);

-- =====================================================================
-- LEG (B) THE FOUR gap_class OUTCOMES — each reached by real data state.
--   Full-row results_eq: cardinality AND all five columns in one assertion, so a leg cannot
--   pass on the right class with a wrong value (or the right value with a wrong provenance).
-- =====================================================================
-- (B1) EXACT PRINT.
select results_eq(
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class, nonpublication_on_record,
            period_was_due, coverage_through
       from pfin.fn_cpi_u_index_for_period('2025-09-01') $$,
  $$ values ('2025-09-01'::date, 324.800::numeric, false, '2025-09-01'::date, 'published'::text, false, true, '2025-11-01'::date) $$,
  '(B1) published: a period with its own print returns that print, is_carried = false, and carried_from set to the period ITSELF rather than NULL — so "where did this value come from?" has the same answer SHAPE in every row a consumer receives. nonpublication_on_record is false: this period was never observed valueless. Asserted on all six columns at once'
);
-- (B2) ABSENT, STRICTLY INTERIOR, NO RECORD YET.
select results_eq(
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class, nonpublication_on_record,
            period_was_due, coverage_through
       from pfin.fn_cpi_u_index_for_period('2025-10-01') $$,
  $$ values ('2025-10-01'::date, 324.800::numeric, true, '2025-09-01'::date, 'unrecorded_gap'::text, false, true, '2025-11-01'::date) $$,
  '(B2) unrecorded_gap: 2025-10 is absent and is BRACKETED BY PRINTS ON BOTH SIDES (2025-09 and 2025-11), so it was demonstrably due and nothing explains it. That bracketing is what makes this the one class worth alarming on. The value is CARRIED from 2025-09 and says so — silent carry-forward on a monthly-complete series understates inflation for the gap month, and the provenance columns are what make it non-silent'
);
-- (B2b) THE PERMANENT ALARM PROBE. (B2) stops being an unrecorded gap the moment (B3) records
--       it, so a second interior gap is seeded that NO leg ever records — otherwise every later
--       leg would be reasoning about a class no probe still reaches.
select results_eq(
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class, nonpublication_on_record,
            period_was_due, coverage_through
       from pfin.fn_cpi_u_index_for_period('2025-07-01') $$,
  $$ values ('2025-07-01'::date, 322.500::numeric, true, '2025-06-01'::date, 'unrecorded_gap'::text, false, true, '2025-11-01'::date) $$,
  '(B2b) unrecorded_gap, permanent probe: 2025-07 is interior (bracketed by 2025-06 and 2025-08) and is never recorded by any leg in this file, so the ALARM class stays reachable after (B3) converts 2025-10. (B8b) depends on this probe existing'
);

-- ⭐ THE ONE VARIABLE CHANGES HERE — and only this one. Same function, same argument, same
--    cpi_u_index contents. The 063 record is the entire difference between (B2) and (B3).
insert into pfin.cpi_u_nonpublication (cpi_period, published_value_raw)
  values ('2025-10-01', '-');

-- (B3) THE SAME PERIOD, AFTER THE RECORD LANDS.
select results_eq(
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class, nonpublication_on_record,
            period_was_due, coverage_through
       from pfin.fn_cpi_u_index_for_period('2025-10-01') $$,
  $$ values ('2025-10-01'::date, 324.800::numeric, true, '2025-09-01'::date, 'recorded_nonpublication'::text, true, true, '2025-11-01'::date) $$,
  '(B3) ⭐ recorded_nonpublication: the SAME period as (B2), with the ONLY difference being the 063 record. This is the pair that proves the record is consulted at all — a suite reaching the two classes from two different periods would pass without ever showing that. Note the carry outcome is IDENTICAL to (B2): gap_class reports the ABSENCE REASON and is orthogonal to what could be resolved, exactly as 064 documents. This is also the ONLY probe sensitive to the record-vs-contiguity ORDER — the interior gap is where both branches are true at once (see (V3a))'
);
-- (B4) TRAILING EDGE — nothing later is present.
select results_eq(
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class, nonpublication_on_record,
            period_was_due, coverage_through
       from pfin.fn_cpi_u_index_for_period('2026-01-01') $$,
  $$ values ('2026-01-01'::date, 326.100::numeric, true, '2025-11-01'::date, 'beyond_coverage'::text, false, false, '2025-11-01'::date) $$,
  '(B4) ⭐ beyond_coverage: absent, later than the trailing edge. NOT an alarm — 064''s bound is data-derived rather than calendar-derived, so it consults no clock and is outside ADR-044''s two-clock hazard. ⚠ THIS IS THE PUBLICATION-LAG ROW, AND IT IS THE DEFAULT PATH RATHER THAN AN EDGE CASE: CPI-U publishes one to two months in arrears, so EVERY current-month figure lands exactly here. Note is_carried is TRUE while period_was_due is FALSE — so the consumer rule `is_carried AND period_was_due` draws NO marker, which is §2.4.4''s "the publication lag is disclosed, not marked". A consumer reading is_carried ALONE as the trigger would mark every figure it ever renders, at all times, which §2.4.4 rules out by name: "A marker present on every figure at all times would carry no information and would dilute the actionable tier beside it." coverage_through still names the trailing edge, because the dated basis line renders here too. ITS STATED COST, which this leg does NOT and cannot cover: a stalled ingest yields this same class indefinitely, indistinguishable from "not yet published"'
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
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class, nonpublication_on_record,
            period_was_due, coverage_through
       from pfin.fn_cpi_u_index_for_period('2025-10-01') $$,
  $$ values ('2025-10-01'::date, 325.400::numeric, false, '2025-10-01'::date, 'published'::text, true, true, '2025-11-01'::date) $$,
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

-- (B8c) THE MARKER GATE, stated as a SET rather than a count. §2.4.4: the informational marker
--   fires "only where the period was actually due, and never where the absence is explained by
--   the edge of coverage alone". This NAMES the not-due periods instead of counting them, so a
--   future branch that quietly flips its own due-ness reddens here with a diff a reader can act
--   on. It is the complement of (B8b): (B8b) bounds the OPERATOR alarm, this bounds the USER
--   marker, and the two sets are deliberately different.
select results_eq(
  $$ select cpi_period from (
       select * from pfin.fn_cpi_u_index_for_period('2025-09-01')
       union all select * from pfin.fn_cpi_u_index_for_period('2025-07-01')
       union all select * from pfin.fn_cpi_u_index_for_period('2025-10-01')
       union all select * from pfin.fn_cpi_u_index_for_period('2014-01-01')
       union all select * from pfin.fn_cpi_u_index_for_period('2026-01-01')
       union all select * from pfin.fn_cpi_u_index_for_period('2026-02-01')
     ) s where not period_was_due order by cpi_period $$,
  $$ values ('2014-01-01'::date), ('2026-01-01'::date) $$,
  '(B8c) MARKER-GATE SET: of the six probes, EXACTLY the two whose absence is explained by an edge of coverage alone — 2014-01 before the leading edge, 2026-01 beyond the trailing one — report period_was_due = false. The other four are due. ⚠ NOTE WHAT IS NOT IN THIS LIST: 2026-02 is ALSO beyond the trailing edge, and it IS due — because it has a 063 record, and the source having spoken about a period is positive evidence it was due, which outranks the edge. So being at an edge is not what makes a period not-due; the ABSENCE OF ANY EVIDENCE is. Asserted as a named set rather than a count so that a branch flipping its own due-ness produces an actionable diff instead of an off-by-one'
);

-- ---------------------------------------------------------------------
-- (B9) ⭐⭐ THE DISAGREEMENT ROW — the single highest-value assertion in this file.
--   Savepoint-scoped: cpi_u_nonpublication is IMMUTABLE, so a record cannot be deleted at any
--   tier and a savepoint is the ONLY way to keep this probe from altering the legs below.
--   A recorded_nonpublication with NOTHING at or before it: the record makes it DUE, and the
--   empty carry window makes it UNCARRIED. period_was_due TRUE, is_carried FALSE, cpi_value
--   NULL. Every other row in this battery has the two columns agreeing, which is exactly why
--   an alias would survive without this one.
-- ---------------------------------------------------------------------
savepoint b_due_disagreement;
insert into pfin.cpi_u_nonpublication (cpi_period, published_value_raw)
  values ('2019-01-01', '-');
select results_eq(
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class, nonpublication_on_record,
            period_was_due, coverage_through
       from pfin.fn_cpi_u_index_for_period('2019-01-01') $$,
  $$ values ('2019-01-01'::date, null::numeric, false, null::date, 'recorded_nonpublication'::text, true, true, '2025-11-01'::date) $$,
  '(B9) ⭐⭐ THE ROW WHERE period_was_due AND is_carried DISAGREE. 2019-01 is before the leading edge (nothing at or before it, so no carry source) AND has a 063 record. Result: period_was_due TRUE — the source published the period valueless, which is positive evidence it was due — while is_carried is FALSE and cpi_value is NULL, because there is nothing to carry. THIS IS THE LEG THAT CATCHES `period_was_due := is_carried`. §2.4.4 forbids that collapse in as many words: "The trigger is whether a value could be resolved, not why the period is absent — the two are independent, and a reason-for-absence must never be read as a proxy for the carry outcome." On every OTHER row in this file the two agree, so the alias passes the entire battery except here — (V8) proves it. RENDERING: this row is §2.4.4''s "uncomputable is not stale" case — no value resolves, so the figure is NOT a marked number but is rendered UNAVAILABLE with a one-line reason, and the cause clause is available because a cause IS on record. SECOND FENCE IN THE SAME ROW: gap_class is recorded_nonpublication, NOT before_coverage — the record branch outranks the LEADING edge, the twin of what (B5) pins at the trailing edge, and neither leg covers the other'
);
rollback to savepoint b_due_disagreement;

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
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class, nonpublication_on_record,
            period_was_due, coverage_through
       from pfin.fn_cpi_u_index_for_period('2025-09-17') $$,
  $$ values ('2025-09-01'::date, 324.800::numeric, false, '2025-09-01'::date, 'published'::text, false, true, '2025-11-01'::date) $$,
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
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class, nonpublication_on_record,
            period_was_due, coverage_through
       from pfin.fn_cpi_u_index_for_period('2014-01-01') $$,
  $$ values ('2014-01-01'::date, null::numeric, false, null::date, 'before_coverage'::text, false, false, '2025-11-01'::date) $$,
  '(C4) before_coverage: earlier than anything held, so cpi_value is NULL, is_carried is false and carried_from is NULL — the "no carry source" case, REPORTED rather than papered over. ⚠ TWO fences in one row. (i) NULL and not 0: a zero is a plausible-looking number that would silently understate a real-terms figure by 100%, where NULL forces the consumer to handle the unknown ((V4) makes that world real). (ii) `before_coverage` and NOT `unrecorded_gap`: a period the backfill never claimed to cover is not an unexplained gap, and classifying it as one fires the alarm on all of history ((V7) restores that world)'
);

-- (C5) the empty-table edge — savepoint-scoped, since it removes the fixture.
savepoint c_empty_index;
delete from pfin.cpi_u_index;
select results_eq(
  $$ select cpi_period, cpi_value, is_carried, carried_from, gap_class, nonpublication_on_record,
            period_was_due, coverage_through
       from pfin.fn_cpi_u_index_for_period('2025-09-01') $$,
  $$ values ('2025-09-01'::date, null::numeric, false, null::date, 'beyond_coverage'::text, false, false, null::date) $$,
  '(C5) empty-source edge: with cpi_u_index holding NO rows at all, the helper still returns EXACTLY ONE row, with a NULL value and beyond_coverage — it does not return an empty set, does not raise, and does not fabricate a zero. This is the state a fresh deploy is in before the first ETL run, so a consumer meets it on day one. ⚠ BOTH NEW COLUMNS TAKE THEIR ONLY NULL/FALSE-BY-EMPTINESS VALUES HERE: period_was_due is FALSE because with no coverage window at all NO period can be SHOWN to have been due (an empty store must not report all of history as due), and coverage_through is NULL because there is no latest print to name. This is the one row in the file where coverage_through is NULL, so it is the sole guard on a consumer that would render the §2.4.4 basis line as "through (blank)" rather than suppressing it'
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
               carried_from date, gap_class text, nonpublication_on_record boolean,
               period_was_due boolean, coverage_through date)
language plpgsql stable security invoker set search_path = '' as $qa$
#variable_conflict use_column
declare v_period date; v_from date; v_val numeric; v_min date; v_max date;
        v_class text; v_recorded boolean; v_due boolean;
begin
  v_period := date_trunc('month', p_period::timestamp)::date;
  v_recorded := exists (select 1 from pfin.cpi_u_nonpublication n where n.cpi_period = v_period);
  select min(c.cpi_period), max(c.cpi_period) into v_min, v_max from pfin.cpi_u_index c;
  return query select v_period, c.cpi_value, false, v_period, 'published'::text, v_recorded,
                      true, v_max
    from pfin.cpi_u_index c where c.cpi_period = v_period;
  if found then return; end if;
  select c.cpi_period, c.cpi_value into v_from, v_val from pfin.cpi_u_index c
   where c.cpi_period < v_period order by c.cpi_period desc limit 1;
  -- THE ONLY CHANGE: the classification is made purely EDGE-BASED, with the record consulted
  -- only where no edge rule applies. Reads as a tidy-up — every branch is still positive and
  -- the set is still closed — and it is the shape a reviewer would most plausibly wave through.
  -- period_was_due travels with its branch exactly as 066 assigns it, so this mutant differs
  -- from the shipped function in CLASSIFICATION ORDER AND NOTHING ELSE.
  if v_max is null then
    v_class := 'beyond_coverage';        v_due := false;
  elsif v_period < v_min then
    v_class := 'before_coverage';        v_due := false;
  elsif v_period > v_max then
    v_class := 'beyond_coverage';        v_due := false;
  elsif v_recorded then
    v_class := 'recorded_nonpublication'; v_due := true;
  else
    v_class := 'unrecorded_gap';         v_due := true;
  end if;
  return query select v_period, v_val, (v_from is not null), v_from, v_class, v_recorded,
                      v_due, v_max;
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
               carried_from date, gap_class text, nonpublication_on_record boolean,
               period_was_due boolean, coverage_through date)
language plpgsql stable security invoker set search_path = '' as $qa$
#variable_conflict use_column
declare v_period date; v_from date; v_val numeric; v_min date; v_max date;
        v_class text; v_recorded boolean; v_due boolean;
begin
  v_period := date_trunc('month', p_period::timestamp)::date;
  v_recorded := exists (select 1 from pfin.cpi_u_nonpublication n where n.cpi_period = v_period);
  select min(c.cpi_period), max(c.cpi_period) into v_min, v_max from pfin.cpi_u_index c;
  return query select v_period, c.cpi_value, false, v_period, 'published'::text, v_recorded,
                      true, v_max
    from pfin.cpi_u_index c where c.cpi_period = v_period;
  if found then return; end if;
  select c.cpi_period, c.cpi_value into v_from, v_val from pfin.cpi_u_index c
   where c.cpi_period < v_period order by c.cpi_period desc limit 1;
  -- THE ONLY CHANGE: the record no longer participates in CLASSIFICATION at all — the shape 064
  -- would have had if written against 053 alone. Note the sixth column is still populated, so
  -- the mutation is isolated to the classification and nothing else can account for the flip.
  if v_max is null then v_class := 'beyond_coverage';   v_due := false;
  elsif v_period < v_min then v_class := 'before_coverage'; v_due := false;
  elsif v_period > v_max then v_class := 'beyond_coverage'; v_due := false;
  else v_class := 'unrecorded_gap';                      v_due := true;
  end if;
  return query select v_period, v_val, (v_from is not null), v_from, v_class, v_recorded,
                      v_due, v_max;
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
               carried_from date, gap_class text, nonpublication_on_record boolean,
               period_was_due boolean, coverage_through date)
language plpgsql stable security invoker set search_path = '' as $qa$
#variable_conflict use_column
declare v_period date; v_from date; v_val numeric; v_max date;
begin
  v_period := date_trunc('month', p_period::timestamp)::date;
  select c.cpi_period, c.cpi_value into v_from, v_val from pfin.cpi_u_index c
   where c.cpi_period <= v_period order by c.cpi_period desc limit 1;
  select max(c.cpi_period) into v_max from pfin.cpi_u_index c;
  -- The $0 defect: an unknown, rendered as a number.
  return query select v_period, coalesce(v_val, 0::numeric), (v_from is not null and v_from <> v_period),
                      v_from, 'before_coverage'::text, false, false, v_max;
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
               carried_from date, gap_class text, nonpublication_on_record boolean,
               period_was_due boolean, coverage_through date)
language plpgsql stable security invoker set search_path = '' as $qa$
#variable_conflict use_column
declare v_period date; v_from date; v_val numeric; v_min date; v_max date;
        v_class text; v_recorded boolean; v_due boolean;
begin
  v_period := date_trunc('month', p_period::timestamp)::date;
  v_recorded := exists (select 1 from pfin.cpi_u_nonpublication n where n.cpi_period = v_period);
  select min(c.cpi_period), max(c.cpi_period) into v_min, v_max from pfin.cpi_u_index c;
  -- THE ONLY CHANGE: the sixth column is DERIVED from gap_class instead of read from the table.
  -- This is the "simplification" the column's own contract warns against, and it looks correct
  -- in every state except one.
  return query select v_period, c.cpi_value, false, v_period, 'published'::text,
                      ('published' = 'recorded_nonpublication'), true, v_max
    from pfin.cpi_u_index c where c.cpi_period = v_period;
  if found then return; end if;
  select c.cpi_period, c.cpi_value into v_from, v_val from pfin.cpi_u_index c
   where c.cpi_period < v_period order by c.cpi_period desc limit 1;
  if v_recorded then v_class := 'recorded_nonpublication'; v_due := true;
  elsif v_max is null then v_class := 'beyond_coverage';   v_due := false;
  elsif v_period < v_min then v_class := 'before_coverage'; v_due := false;
  elsif v_period > v_max then v_class := 'beyond_coverage'; v_due := false;
  else v_class := 'unrecorded_gap';                         v_due := true;
  end if;
  return query select v_period, v_val, (v_from is not null), v_from, v_class,
                      (v_class = 'recorded_nonpublication'), v_due, v_max;
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
               carried_from date, gap_class text, nonpublication_on_record boolean,
               period_was_due boolean, coverage_through date)
language plpgsql stable security invoker set search_path = '' as $qa$
#variable_conflict use_column
declare v_period date; v_from date; v_val numeric; v_max date;
        v_class text; v_recorded boolean; v_due boolean;
begin
  v_period := date_trunc('month', p_period::timestamp)::date;
  v_recorded := exists (select 1 from pfin.cpi_u_nonpublication n where n.cpi_period = v_period);
  select max(c.cpi_period) into v_max from pfin.cpi_u_index c;
  return query select v_period, c.cpi_value, false, v_period, 'published'::text, v_recorded,
                      true, v_max
    from pfin.cpi_u_index c where c.cpi_period = v_period;
  if found then return; end if;
  select c.cpi_period, c.cpi_value into v_from, v_val from pfin.cpi_u_index c
   where c.cpi_period < v_period order by c.cpi_period desc limit 1;
  -- THE ONLY CHANGE: the leading edge is unbounded again — the pre-fix shape, in which any
  -- period earlier than coverage falls through to the alarm class.
  if v_recorded then v_class := 'recorded_nonpublication'; v_due := true;
  elsif v_max is not null and v_max > v_period then v_class := 'unrecorded_gap'; v_due := true;
  else v_class := 'beyond_coverage';                       v_due := false;
  end if;
  return query select v_period, v_val, (v_from is not null), v_from, v_class, v_recorded,
                      v_due, v_max;
end;
$qa$;
select is(
  (select gap_class from pfin.fn_cpi_u_index_for_period('2014-01-01')),
  'unrecorded_gap',
  '(V7-LEADING-EDGE-BOUND-HAS-TEETH) ⚠ (C4)/(B8b) are not vacuous, and this reproduces the DEFECT the bound was added to fix: with the leading edge unbounded, a period a decade before anything the store ever claimed to cover reports as an unrecorded gap — the ALARM class. Every period in history back to year zero would do the same, which is how an alarm gets trained away. This is the world before the fix, kept runnable so the fix cannot silently regress'
);
rollback to savepoint v_leading_edge;

-- ---- (V8) ⭐ is period_was_due really NOT a proxy for is_carried? ----
--   THE MUTATION IS ONE EXPRESSION. 066's contract says in as many words "Do NOT refactor v_due
--   into a derived expression", and §2.4.4 says "a reason-for-absence must never be read as a
--   proxy for the carry outcome". This builds the forbidden alias and finds the state where it
--   is wrong — the same method (V6) uses for the sixth column, applied to the seventh.
--   The 2019-01 record is re-seeded here because (B9) rolled its own savepoint back.
savepoint v_due_alias;
insert into pfin.cpi_u_nonpublication (cpi_period, published_value_raw)
  values ('2019-01-01', '-');
create or replace function pfin.fn_cpi_u_index_for_period(p_period date)
returns table (cpi_period date, cpi_value numeric, is_carried boolean,
               carried_from date, gap_class text, nonpublication_on_record boolean,
               period_was_due boolean, coverage_through date)
language plpgsql stable security invoker set search_path = '' as $qa$
#variable_conflict use_column
declare v_period date; v_from date; v_val numeric; v_min date; v_max date;
        v_class text; v_recorded boolean;
begin
  v_period := date_trunc('month', p_period::timestamp)::date;
  v_recorded := exists (select 1 from pfin.cpi_u_nonpublication n where n.cpi_period = v_period);
  select min(c.cpi_period), max(c.cpi_period) into v_min, v_max from pfin.cpi_u_index c;
  -- THE ONLY CHANGE: period_was_due is no longer carried by the classification chain; it is
  -- DERIVED from is_carried. On the exact-print path is_carried is false, so the alias says
  -- "not due" for a period whose print we are literally returning — already wrong, and still
  -- invisible to every leg that does not assert the column.
  return query select v_period, c.cpi_value, false, v_period, 'published'::text, v_recorded,
                      false, v_max
    from pfin.cpi_u_index c where c.cpi_period = v_period;
  if found then return; end if;
  select c.cpi_period, c.cpi_value into v_from, v_val from pfin.cpi_u_index c
   where c.cpi_period < v_period order by c.cpi_period desc limit 1;
  if v_recorded then v_class := 'recorded_nonpublication';
  elsif v_max is null then v_class := 'beyond_coverage';
  elsif v_period < v_min then v_class := 'before_coverage';
  elsif v_period > v_max then v_class := 'beyond_coverage';
  else v_class := 'unrecorded_gap';
  end if;
  return query select v_period, v_val, (v_from is not null), v_from, v_class, v_recorded,
                      (v_from is not null), v_max;
end;
$qa$;
select is(
  (select period_was_due from pfin.fn_cpi_u_index_for_period('2019-01-01')),
  false,
  '(V8-DUE-IS-NOT-A-PROXY-FOR-CARRIED) ⭐ (B9) is not vacuous, and this is the change someone actually makes: `period_was_due := is_carried` deletes a variable and a five-branch assignment, and it AGREES WITH THE TRUTH ON EVERY ROW IN THIS FILE EXCEPT ONE. On the disagreement row — a recorded non-publication with nothing at or before it — the alias reports NOT DUE for a period the source itself published valueless. Downstream that is not a cosmetic slip: §2.4.4 gates the informational marker on this column, so the one case where the app can say "the source published no value for this month, and no action will fix it" silently loses its explanation. (B9) is the only leg in the battery that reddens on this'
);
rollback to savepoint v_due_alias;

-- ---- (V9) is coverage_through on the 'published' path really load-bearing (rider A′)? ----
--   The mutation is ONE STATEMENT MOVED — the exact control flow 064 had, which 066 changed for
--   exactly this reason. It is the most plausible "revert the noise" edit in the whole function:
--   the min/max looks pointless above a branch that does not read it.
savepoint v_coverage_late;
create or replace function pfin.fn_cpi_u_index_for_period(p_period date)
returns table (cpi_period date, cpi_value numeric, is_carried boolean,
               carried_from date, gap_class text, nonpublication_on_record boolean,
               period_was_due boolean, coverage_through date)
language plpgsql stable security invoker set search_path = '' as $qa$
#variable_conflict use_column
declare v_period date; v_from date; v_val numeric; v_min date; v_max date;
        v_class text; v_recorded boolean; v_due boolean;
begin
  v_period := date_trunc('month', p_period::timestamp)::date;
  v_recorded := exists (select 1 from pfin.cpi_u_nonpublication n where n.cpi_period = v_period);
  -- THE ONLY CHANGE: the coverage extent is resolved BELOW the exact-print branch again (064's
  -- shape), so v_max is still NULL when the 'published' row is emitted. Every gap path is
  -- unaffected, which is what makes this survive review: the column still works everywhere the
  -- data is stale, and fails only where it is fresh.
  return query select v_period, c.cpi_value, false, v_period, 'published'::text, v_recorded,
                      true, v_max
    from pfin.cpi_u_index c where c.cpi_period = v_period;
  if found then return; end if;
  select c.cpi_period, c.cpi_value into v_from, v_val from pfin.cpi_u_index c
   where c.cpi_period < v_period order by c.cpi_period desc limit 1;
  select min(c.cpi_period), max(c.cpi_period) into v_min, v_max from pfin.cpi_u_index c;
  if v_recorded then v_class := 'recorded_nonpublication'; v_due := true;
  elsif v_max is null then v_class := 'beyond_coverage';   v_due := false;
  elsif v_period < v_min then v_class := 'before_coverage'; v_due := false;
  elsif v_period > v_max then v_class := 'beyond_coverage'; v_due := false;
  else v_class := 'unrecorded_gap';                         v_due := true;
  end if;
  return query select v_period, v_val, (v_from is not null), v_from, v_class, v_recorded,
                      v_due, v_max;
end;
$qa$;
select ok(
  (select coverage_through is null from pfin.fn_cpi_u_index_for_period('2025-09-01')),
  '(V9-COVERAGE-ON-PUBLISHED-HAS-TEETH) (B1)/(C2)''s coverage_through column is not vacuous, and this reproduces the defect rider A′ was added to fix. With the min/max moved back below the exact-print branch, a period WITH its own print returns coverage_through NULL — so §2.4.4''s dated basis line ("real terms, CPI-U through March 2026") is renderable only on surfaces whose data is STALE, and disappears precisely where the series is healthy. A basis line that only exists when there is a gap is not a basis line; §2.4.4 requires it on every surface, statically, so the user is never told "current" while it is not. ⚠ NOTE THE BLAST RADIUS: every gap path still reports the edge correctly, so a reviewer sees a passing suite and one deleted-looking line'
);
rollback to savepoint v_coverage_late;

-- ---- (V5) STRUCTURAL, DELIBERATELY LAST + OUTSIDE ANY SAVEPOINT ----
--   Two jobs: it asserts the (V) block put the function back exactly as authored (five of the
--   legs above REPLACED it, and a battery that left a stub behind would invalidate everything
--   after it), and it re-arms pgTAP's plan counter after the savepoint rewinds. Moving this leg
--   off the end, or inside a savepoint, silently re-breaks the plan arithmetic.
select ok(
  (select pg_get_function_result(p.oid) = 'TABLE(cpi_period date, cpi_value numeric, is_carried boolean, carried_from date, gap_class text, nonpublication_on_record boolean, period_was_due boolean, coverage_through date)'
      and not p.prosecdef and p.provolatile = 's'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_cpi_u_index_for_period')
  and not has_function_privilege('service_role', 'pfin.fn_cpi_u_index_for_period(date)', 'execute'),
  '(V5-FUNCTION-RESTORED-AND-PLAN-COUNTER-REARMED) structural: after the inversion block the function is back to its authored shape (row return, INVOKER, STABLE) and the EXECUTE grant it opened did not survive — so nothing above was evaluated against a stub this file left behind. It also re-arms pgTAP''s plan counter after the savepoint rewinds, so this file cannot emit a spurious "planned N but ran M" that would train a reader to discount the one diagnostic distinguishing a genuinely aborted run'
);

select * from finish();
rollback;

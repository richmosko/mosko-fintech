-- ============================================================================
-- Migration: pfin.cpi_u_nonpublication — the record of periods the CPI-U source
--   published WITHOUT a usable value. Global public reference data (NOT tenant-
--   owned), append-only, immutable. Realizes ADR-049 Decision 1 (Option C,
--   F/CTO-ratified 2026-08-10). Companion migration 064 authors the single
--   consumption helper required by ADR-049 Decision 4.
--   JOINT-REVIEW-MANDATORY (Sec veto surface): ADR-011 Decision 1 — a new table
--   feeding financial figures (inflation-adjusted / real-terms surfaces).
--
-- ----------------------------------------------------------------------------
-- WHAT FORCED THIS (ADR-049, read verbatim before drafting). MEASURED AT RATIFY
--   and carried here rather than re-derived: over the full 2015-2026 range the
--   BLS series returned 138 periods, 137 were stored, and exactly ONE was
--   dropped — 2025 M10, published with `value = '-'`. All returned codes were
--   M-prefixed, M01-M12 only. The live table at ratify held 137 rows spanning
--   2015-01 .. 2026-06 with exactly one gap and no non-first-of-month periods —
--   so 137-of-138 is ONE REAL GAP, not a coincidental total.
--   053 declares
--   `cpi_value NOT NULL` plus a finiteness CHECK, so a valueless period CANNOT
--   be stored — the ETL's drop is FORCED BY THE SCHEMA, not an importer defect.
--   Absence therefore carried no explanation, and a CPI-U gap propagates into
--   inflation-adjusted financial figures. ADR-049 rejected making cpi_value
--   nullable (Option B — pays the largest consumer-side cost and weakens the
--   exact invariant 053 was built around) and rejected recording nothing
--   (Option A — "you cannot retrospectively classify a gap you did not record";
--   reversible in schema, IRREVERSIBLE IN DATA). This table is the purely
--   additive third option.
--
-- ----------------------------------------------------------------------------
-- Numbering: 063 follows 062 (fn_nav_series). Next free number taken AT
--   AUTHORING TIME, never reserved ahead (ADR-049 Consequences states this
--   explicitly; the 058->059 slip is the precedent for why).
--   Depends on: 001 (pfin schema). Deliberately does NOT depend on 053 —
--   see NO FK, BY CONSTRUCTION below. Paired with: 064 (the consumption
--   helper), which reads BOTH this table and 053 and must apply after both.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — the two functions authored here are SECURITY INVOKER
--   (default per ADR-011 Lock 11). They are immutability trigger fences: they
--   read no table and need no elevated privilege — the raise is the entire body.
--   NO SECURITY DEFINER function is authored or proposed by this migration, so
--   the ADR-011 Decision 9 DEFINER allowlist is UNCHANGED by it (+0). Stated as
--   a DELTA, not as a level: the allowlist's size is read live from Decision 9,
--   never copied into a file that cannot maintain it.
--
-- ----------------------------------------------------------------------------
-- IMMUTABLE + APPEND-ONLY — and WHY RESTATEMENT IS A FEATURE (ADR-049 D1).
--   053 is MUTABLE because BLS revises published prints: a period can go
--   absent -> present. This table is the opposite posture. A row records what
--   was observed at observation time, and it is RETAINED even after the period
--   is later published — a period present in BOTH tables reads as "unpublished
--   when we looked, published later", which IS the audit trail.
--   >> NO `resolved` FLAG, DELIBERATELY. <<  A reader derives resolution by
--   joining this table to 053 on cpi_period; per the ADR-011 Decision 4
--   derive-by-looking test, anything derivable by looking is not stored. A
--   later reader who "notices the gap" and adds a status column would be
--   re-introducing exactly what Option B was rejected for, one table over.
--
--   STANDING REQUIREMENT ON THE WRITER: the ingest MUST append with
--   `on conflict (cpi_period) do nothing`. `do update` reaches the UPDATE fence
--   below and fails loud. First observation wins; a re-run is a no-op. This is
--   what makes a monthly re-fetch of the same series bounded rather than
--   accumulating one duplicate row per run, forever.
--
-- ----------------------------------------------------------------------------
-- ⚠⚠ STANDING REQUIREMENT ON WHATEVER FIRST POPULATES THIS TABLE.
--   Sec ruling (b), 2026-08-10.
--   ⚠ THIS BLOCK IS THE SOLE DURABLE RECORD OF THAT RULING IN CANON. PR #386,
--   which would have carried it as an ADR amendment, was deliberately CLOSED
--   UNMERGED — a decision whose whole content is two code comments records the
--   thread rather than the decision. There is no other copy. Edit accordingly.
--
--   THE REQUIREMENT. A period may be recorded here only if it came from an
--   EXPLICITLY MONTHLY-PROJECTED source: filtered to a real calendar month
--   (`month` non-null and 1..12) BEFORE any date is constructed from it,
--   REUSING the projection the CPI-U mapper (PFinBackend._map_cpi_u_index_df)
--   already applies rather than adding a new fence. It constrains what the
--   writer READS, not what any parser REJECTS.
--   Why the grain matters: BLS period codes are not all calendar months (M13 is
--   the annual average, S01/S02 are semiannual), and the transport returns raw
--   codes with no grain filter BY DESIGN, saying so in its own input contract
--   and stating that A NEW CONSUMER DOES NOT INHERIT THE LIVE CONSUMER'S GUARD
--   AND MUST APPLY ITS OWN. The CPI-U request payload asks for neither
--   `annualaverage` nor `aspects`, which is why only M01-M12 come back today —
--   but THE REQUEST IS THE GUARANTEE AND THE RESPONSE IS ONLY AN OBSERVATION.
--
--   ⚠ TWO OBSTACLES STAND IN THE WAY, IN THIS ORDER — and an earlier draft of
--   this block named only the second. That made the requirement CORRECT BUT
--   UNEXECUTABLE, which is worse than an omission and is the SAME FAILURE MODE
--   THIS TABLE EXISTS TO PREVENT: a writer that does exactly what it was told,
--   gets an EMPTY record, and has therefore DISCHARGED THE STATED OBLIGATION HAS
--   NO REASON TO LOOK FURTHER. An omission invites a question; a false sense of
--   completion answers it in advance. Corrected at Sec joint-review (C3).
--
--     OBSTACLE 1 — THE TRANSPORT DROPS THESE ROWS BEFORE ANY CONSUMER SEES THEM.
--       `utils.fetch_cpi_df` removes value-null rows from its OWN RETURN VALUE:
--       it logs each one and discards it, then returns only the kept rows. The
--       2025-10 row NEVER LEAVES that function. So a writer following this
--       block to the letter — reuse the month projection, skip the value filter
--       — HAS NOTHING TO APPLY THE PROJECTION TO, and still records nothing.
--       >> THIS OBSTACLE IS FIRST, AND SOLVING IT IS NOT OPTIONAL. <<
--     OBSTACLE 2 — THE MAPPER'S FILTER WOULD DROP THEM AGAIN. That projection's
--       five conjuncts include `series_value` non-null AND finite, and THOSE TWO
--       ARE PRECISELY THE ROWS THIS TABLE EXISTS TO RECORD. Reuse the MONTH
--       conjuncts only. Applying the mapper wholesale filters the subject away
--       and yields an empty record indistinguishable from a clean run.
--
--   ⚠ THE ENFORCEABLE HALF — A COUNT RECONCILIATION, NOT A REMEMBERED RULE.
--   The transport's own note already states the principle: "THE RECONCILIATION
--   IS THE LOAD-BEARING HALF, NOT THE PER-ROW LINE" — a per-row warning says
--   nothing about a SYSTEMATIC drop, whereas counting in and out catches the
--   class. So the writer's run MUST ASSERT:
--       periods returned by transport
--         = rows for pfin.cpi_u_index
--         + rows for pfin.cpi_u_nonpublication
--         + periods that are not calendar months
--   and FAIL LOUD on any imbalance. It converts a rule someone must REMEMBER
--   into an assertion that CANNOT PASS QUIETLY — which is the only form that
--   survives this file being skimmed.
--
--   ⚠ THE THIRD TERM IS REQUIRED, NOT DEFENSIVE. This block previously stated
--   the assertion with TWO terms, and in that form IT CANNOT BALANCE. The
--   transport is deliberately grain-agnostic and returns raw BLS period codes;
--   an M13 (annual average) or S01/S02 (semiannual) belongs to NEITHER table, so
--   under the two-term form a single M13 row fails the assertion FALSELY and
--   kills the nightly ingest. That today's CPI-U payload requests neither
--   `annualaverage` nor `aspects` is no defence: THE REQUEST IS THE GUARANTEE
--   AND THE RESPONSE IS ONLY AN OBSERVATION (stated above), so the assertion
--   must not be built on the observation. The third term must be computed
--   DIRECTLY FROM THE TRANSPORT'S RETURN by an expression that calls NEITHER
--   mapper — that independence is what lets the sum come up short, and therefore
--   fail, when a mapper grows a filter for some future reason nobody has
--   thought of.
--
--   ⚠ AND WHAT THE RECONCILIATION CANNOT SEE — corrected here because an earlier
--   draft of this block claimed the assertion "catches BOTH obstacles above
--   without either having to be individually remembered", and that claim is
--   FALSE for OBSTACLE 1. The first term is "periods returned by transport", so
--   a row discarded BEFORE the return is absent from EVERY term and the sum
--   still balances. The gate is therefore STRUCTURALLY BLIND to the exact
--   regression it was specified to catch. This was DEMONSTRATED, not argued:
--   with the transport drop re-armed, the gate did NOT raise. Coverage for
--   OBSTACLE 1 BELONGS ONE LAYER EARLIER — it is a STANDING REQUIREMENT on the
--   transport, not a report of an existing test: the transport MUST carry a
--   contract test asserting the valueless period is RETAINED in its return
--   value. ⚠ PHRASED AS AN OBLIGATION RATHER THAN AS A LOCATION, DELIBERATELY.
--   Saying that coverage "lives" in a particular test asserts a fence EXISTS,
--   which is a present-tense claim about another component's tree that this file
--   cannot check and that goes false the moment that test is renamed, moved, or
--   never lands. Saying where it BELONGS stays true either way, and — unlike a
--   location claim — it still reads as UNMET work if nothing satisfies it. Same
--   correction as the standing-property rewrite two paragraphs above; an earlier
--   draft applied it there and missed it here.
--   NEITHER SUBSTITUTES FOR THE OTHER, and a reader who takes this reconciliation
--   as covering both obstacles will delete that contract test as redundant. What the reconciliation DOES cover:
--   OBSTACLE 2 (a mapper filtering the subject away) and a future drop
--   introduced at mapper level for some third reason — because those shrink a
--   term that IS counted.
--
--   ⚠ ROUTED, OWNED, AND OUT OF SCOPE FOR THIS MIGRATION — stated as an item,
--   not left as an implication: making value-null periods reachable by a
--   consumer that wants them (lifting the transport-level drop, or making it
--   opt-out) is BACKEND'S, in `workers/etl/src/pfin_back_etl/utils.py`.
--   STANDING PROPERTY, stated as a property rather than as a merge-order state
--   so it does not go stale the moment that work lands: THIS TABLE CAN ONLY BE
--   POPULATED FROM A TRANSPORT RETURN THAT CARRIES VALUE-NULL PERIODS. No
--   writer, however correct, can record a row the transport discarded before
--   returning — the writer's correctness is not the binding constraint, the
--   transport's return is.
--
--   ⚠ AND THE SECOND-CONSUMER TRIGGER — Sec's reasoning, recorded because it is
--   SHARPER THAN THE ONE IT REPLACES. The transport's note says to replace it
--   with a fence "when a SECOND LIVE CONSUMER of this function exists", and a
--   writer for this table would be that consumer. It is tempting to dismiss the
--   trigger by citing the note's own points 2 and 4 (the transport is
--   deliberately grain-agnostic; a new consumer must bring its own guard) — but
--   THOSE POINTS WERE ALREADY TRUE WHEN THE TRIGGER WAS WRITTEN, by the same
--   author, who knew them and wrote the trigger anyway. A reading that disposes
--   of a trigger using facts that PREDATE it makes the trigger dead on arrival,
--   and must not be adopted.
--   What the trigger actually misses is that it conflates TWO DIMENSIONS which
--   the second consumer SPLITS APART. The two consumers AGREE on grain (both
--   want month 1..12) and are EXACTLY OPPOSED on value (053's writer wants only
--   valued rows; this table's writer wants only the valueless ones). Hence:
--       · GRAIN fence — PERMITTED. Both consumers want it. Optional, not
--         required; nothing breaks either way.
--       · VALUE fence — FORBIDDEN. It would destroy this table's subject.
--       · The EXISTING value DROP — MUST BE LIFTED OR MADE OPT-OUT. This is the
--         mandatory work, and note that it runs OPPOSITE to "add a fence": the
--         second consumer's arrival calls for REMOVING a filter, not adding one.
--
--   ⚠ THE DDL BELOW CANNOT SUBSTITUTE FOR ANY OF THIS. The first-of-month CHECK
--   fences the DAY component of an already-constructed date; it cannot tell a
--   real calendar month from a non-monthly code some writer mapped onto a
--   first-of-month date, and it cannot conjure a row the transport discarded.
--   Necessary, not sufficient: the sufficiency lives in the writer.
--
-- ----------------------------------------------------------------------------
-- SHAPE — the resemblance a later reader will reach for DOES NOT HOLD, and
--   ADR-049 D1 records it so nobody "aligns" this table to a family it does not
--   belong to. The `*_state_history` family (linked_source_state_history 015,
--   account_trans_annotation_history 031) are HISTORIES OF A TENANT-OWNED ROW
--   THAT EXISTS, FK-anchored to it. This table is the opposite on both axes: it
--   is GLOBAL (no tenant) and it describes a period for which NO ROW EXISTS —
--   that absence is its entire subject. Closest in PURPOSE is a sync-audit
--   record; that is tenant-scoped, so it is not precedent either. The append-
--   only POSTURE is precedent; the SHAPE is new.
--
--   >> NO FK, BY CONSTRUCTION. <<  No FK to pfin.cpi_u_index is POSSIBLE: the
--   subject of a row here is precisely a cpi_period for which cpi_u_index holds
--   no row. A future reader adding `references pfin.cpi_u_index` would make the
--   table unable to store the only thing it exists to store.
--
-- ----------------------------------------------------------------------------
-- SINGLE-SERIES KEY — INHERITED, and the coupling is stated rather than hidden.
--   The PRIMARY KEY is cpi_period alone, mirroring 053. `source` is carried as a
--   column for provenance, exactly as 053 carries it. The two tables are joined
--   on cpi_period, so their key grains MUST match; a composite (cpi_period,
--   source) key here would resolve a limitation 053 does not resolve and would
--   put the join grain in question for no present benefit (one series is
--   ingested). STANDING REQUIREMENT: if 053's key ever widens to admit a second
--   series, THIS TABLE'S KEY MUST WIDEN WITH IT, and 064's join with it.
--
-- ----------------------------------------------------------------------------
-- aal2 STEP-UP BACKSTOP (C3 / ADR-029 / 025) — EXCLUDED, reason (i) GLOBAL
--   SHARED-READ. cpi_u_nonpublication is public macro reference read by every
--   authenticated user via `using (true)` — it is NOT a sensitive tenant-owned
--   pfin table, so the per-user-conditional aal2 clause does NOT apply (same
--   class as tax_character and 053 itself). Stated here per the 025 in-header
--   convention.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — ADR-011 Decision 4 is LINKED, not restated;
--   read verbatim live before drafting this file. This migration is not the
--   canonical anchor, so the catalogued numbered list is deliberately NOT
--   reproduced here and NO count appears — a derived surface that copies a
--   count acquires a maintenance obligation it will not honour.)
--   (i)   Instance-numbering: this migration catalogues NO new §10 instance and
--         reorders none. Ledger DELTA = 0.
--   (ii)  Layer-attribution: the service_role SELECT+INSERT grant below is a
--         DB-LAYER ACL. It is NOT the code-layer SUPABASE_SERVICE_ROLE_KEY
--         allowlist grep fence, NOT the PDF-worker container credential audit,
--         NOT the app->worker admission network/config surface. Identical
--         reasoning to 053's and eod_price/019's global-writer grants. The BLS
--         ETL writer is an already-sanctioned service_role consumer and this
--         migration adds no new file to any code-layer fence.
--   (iii) Verbatim-vs-paraphrase: Decision 4 linked, not restated (Path B).
--   DE-CONFLATION GUARD: no FK-shaped column, no credential-presence surface,
--   no admission endpoint — none of the three is a §10 catalogued instance.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED set are DIFFERENT SETS. Neither
--   is reconciled to the other here, and neither should be "tidied" to match.
--
-- ----------------------------------------------------------------------------
-- ADR-011 DECISION 3 (cross-tenant FK-bypass family) — family UNCHANGED (+0).
--   ADR-049 D1 pins NON-MEMBERSHIP on TWO INDEPENDENT GROUNDS, both recorded so
--   a later reader who re-derives only one does not conclude the other was
--   missed:
--     (i)  there is NO FK-SHAPED REFERENCE COLUMN AT ALL — the four columns are
--          cpi_period DATE PK / source TEXT / published_value_raw TEXT /
--          observed_at TIMESTAMPTZ; none references another pfin row, there is
--          no self-FK and no INTEGER[] array; and per NO FK, BY CONSTRUCTION
--          above, none is even possible; and
--     (ii) both this table and 053 are GLOBAL, so there is NO TENANT BOUNDARY
--          TO BYPASS EVEN IF SUCH A COLUMN EXISTED — no users_id, no tenant
--          anchor, nothing to matched-tenant-validate.
--   Either ground alone is sufficient; neither is load-bearing on the other.
--   Same "global shared reference, not a family member" class as tax_character.
--   The family's size is read live from ADR-011 Decision 3's body — this file
--   carries no tally, by the same rule that governs the §10 block above.
--
-- ----------------------------------------------------------------------------
-- ADR-023 STEP 0 CLASSIFICATION — PURE-GLOBAL. The SELECT policy is
--   `using (true)` with no tenant discrimination, so reads execute under
--   `authenticated`, composing with the ETL read-role amendment's Step 0 rule
--   rather than creating an exception to it. Writes execute under service_role,
--   the write role-of-record.
--
-- ----------------------------------------------------------------------------
-- WHAT THIS TABLE DOES **NOT** DISTINGUISH (ADR-049 Decision 2, stated because
--   "C fixes the ambiguity" is the natural misreading and it is WRONG).
--   Absence of a cpi_u_index row collapses FOUR states:
--     (a) published with no value   (b) not yet published
--     (c) our ingest dropped it     (d) backfill never covered the span
--   This table positively records (a) ONLY. It converts a four-way ambiguity
--   into a TWO-WAY one; it does not eliminate it. (c) and (d) STAY COLLAPSED
--   WITH EACH OTHER and are separated from (b) only BY CONVENTION (064's
--   coverage-edge rule), never by record.
--   Rejected as the heavier alternative, so the boundary reads as CHOSEN rather
--   than overlooked: C' — record the outcome of EVERY fetched period, making
--   absence mean "never fetched" and separating (c) from (d). That is a full
--   ingest log; at V1 single-user scale its cost exceeds the value of
--   distinguishing two operational states a run log already narrows. If (c)/(d)
--   separation is later wanted, C' IS ADDITIVE ON TOP OF C — no rework.
--
-- ----------------------------------------------------------------------------
-- LEDGER DELTAS (all confirmed FLAT, stated as deltas): §10 catalogued
--   instances +0 · SECURITY DEFINER allowlist +0 (two INVOKER trigger fences
--   authored) · ADR-011 Decision 3 family +0 · SD matrix — NO expansion (public
--   read-only reference data; ADR-011 Decision 12 class). Sec review is
--   MANDATORY here notwithstanding the flat ledgers: ADR-011 Decision 1, new
--   table feeding financial figures.
--
-- ----------------------------------------------------------------------------
-- ⚠ WHAT ACTUALLY HOLDS THE LINE — MEASURED PER ROLE, because an earlier draft
--   of this header got it BACKWARDS in both directions and the wrong reason for
--   a correct outcome is the thing that rots. Corrected at Sec joint-review
--   2026-08-10 (findings F1 + F2), re-measured independently before the edit.
--
--     authenticated   — no write grant and no write policy. The ACL refuses.
--     service_role    — holds SELECT + INSERT only. UPDATE / DELETE / TRUNCATE /
--                       `on conflict … do update` all fail with `permission
--                       denied for table`. >> THE ACL REFUSES FIRST AND THE
--                       TRIGGERS NEVER FIRE AT ALL. << Plain INSERT succeeds —
--                       the sanctioned append path is unaffected.
--     table owner /
--     superuser       — the ACL does NOT refuse, so the triggers fire and fail
--                       loud. But the owner can `alter table … disable trigger`
--                       and then mutate; measured, it succeeds. The triggers are
--                       therefore NOT un-bypassable by the owner.
--
--   >> SO: the WITHHELD service_role UPDATE/DELETE grants are the OPERATIVE
--   fence in production, and the triggers are a BACKSTOP — not the reverse. <<
--   The backstop is still worth its keep, for two reasons that do not depend on
--   the false one: (1) it becomes load-bearing the moment a future migration
--   WIDENS the service_role grant, which is exactly the drift an ACL cannot
--   defend against; and (2) it fails LOUD in owner context, catching the
--   realistic error — a migration or maintenance script that mutates this table
--   by accident — even though it does not stop an owner who means to.
--
--   ⚠ METHOD NOTE, recorded because the error was in the VERIFICATION, not the
--   design: a superuser smoke test observed these triggers firing and concluded
--   they were the guarantee everywhere. They fired precisely BECAUSE the owner's
--   ACL does not refuse — i.e. in the one context where the trigger is reachable
--   at all. Under the roles that exist in production it never fires. A fence
--   observed in the only context that can reach it tells you nothing about the
--   contexts that cannot.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.cpi_u_nonpublication — global public record of CPI-U periods the
--     source published WITHOUT a usable value.
--     Columns: cpi_period DATE PK (first-of-month, CHECK-fenced),
--       source TEXT DEFAULT 'BLS_CUUR0000SA0',
--       published_value_raw TEXT NULL (what the source actually emitted, e.g.
--       '-'; length-bounded), observed_at TIMESTAMPTZ DEFAULT NOW().
--     IMMUTABLE + APPEND-ONLY: UPDATE + DELETE + TRUNCATE are refused for every
--       role that exists in production. INSERT is the only mutation,
--       service_role-only, first-observation-wins. WHICH LAYER REFUSES IS
--       ROLE-DEPENDENT — see the WHAT ACTUALLY HOLDS THE LINE block below; do
--       not summarize it as "the trigger blocks everyone".
--     RLS: SELECT to authenticated `using (true)` (public reference);
--       INSERT/UPDATE/DELETE default-deny at authenticated (no policy) → writes
--       are service_role-only via DB-ACL grant.
--   Security-load-bearing edges: NO tenant isolation surface (global public
--     data, no users_id); authenticated holds SELECT only and therefore cannot
--     forge or erase a non-publication record; the WITHHELD service_role
--     UPDATE/DELETE grants are the operative append-only fence in production and
--     the triggers are the backstop behind them (again: see WHAT ACTUALLY HOLDS
--     THE LINE); the first-of-month CHECK
--     is role-agnostic (service_role bypasses RLS but NOT CHECK) and keeps a
--     mis-keyed row from silently never joining 053 — a record that cannot be
--     joined is indistinguishable from a record that was never written, which
--     would defeat this table's entire purpose.
--   ⚠ NECESSARY, NOT SUFFICIENT: this table records (a) only, and only for
--     periods the ingest actually observed and wrote. It is not a completeness
--     guarantee and cannot detect a stalled ingest — see 064's coverage-edge
--     limitation and Decision 2's four-state list above.
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- pfin.cpi_u_nonpublication — global, append-only, immutable. PK = cpi_period
-- (mirrors 053's grain so the two join cleanly; see SINGLE-SERIES KEY above).
-- ----------------------------------------------------------------------------
create table if not exists pfin.cpi_u_nonpublication (
  cpi_period           date        not null primary key,                 -- first-of-month period the source published with no usable value
  source               text        not null default 'BLS_CUUR0000SA0',   -- BLS series id provenance (mirrors 053)
  published_value_raw  text        null,                                 -- what the source actually emitted (e.g. '-'); NULL if not captured
  observed_at          timestamptz not null default now(),               -- when WE observed the non-publication (first observation wins)
  constraint cpi_u_nonpublication_period_first_of_month
    check (extract(day from cpi_period) = 1),                            -- zone-free by construction: extract(day from date) involves no TimeZone
  constraint cpi_u_nonpublication_raw_bounded
    check (published_value_raw is null or length(published_value_raw) <= 64)
);

comment on table pfin.cpi_u_nonpublication is
  'Global public record of CPI-U periods (BLS series CUUR0000SA0) that the source '
  'PUBLISHED WITHOUT A USABLE VALUE — ADR-049 Decision 1, Option C. Exists because '
  'pfin.cpi_u_index (053) declares cpi_value NOT NULL plus a finiteness CHECK, so a '
  'valueless period CANNOT be stored there; the ingest drop is forced by the schema, '
  'not an importer defect. NOT tenant-owned — public macro reference read by all '
  'authenticated users (RLS SELECT using(true)); NO users_id, NO FK-shaped column '
  '→ NOT an ADR-011 Decision-3 family member, on two independent grounds (no '
  'FK-shaped column at all; and both tables are global, so there is no tenant '
  'boundary to bypass even if one existed). Same class as tax_character. '
  'IMMUTABLE + APPEND-ONLY (unlike 053, which is MUTABLE because BLS revises '
  'prints): UPDATE + DELETE + TRUNCATE are refused for every role that exists in '
  'production — but WHICH LAYER refuses is role-dependent. Measured 2026-08-10: for '
  'service_role the ACL refuses first (no UPDATE/DELETE grant) and the immutability '
  'triggers never fire; the triggers fire only where the ACL does not refuse, i.e. '
  'owner/superuser context, and an owner can disable them. The withheld grants are '
  'the operative fence; the triggers are the backstop that becomes load-bearing if '
  'a future migration widens that grant. A '
  'row is RETAINED after the period is later published — a cpi_period present in '
  'BOTH tables reads as "unpublished when we looked, published later", which is the '
  'audit trail. There is deliberately NO resolved flag: resolution is derived by '
  'joining this table to pfin.cpi_u_index on cpi_period, and per the ADR-011 '
  'Decision 4 derive-by-looking test anything derivable by looking is not stored. '
  'STANDING REQUIREMENT — the ingest MUST append with `on conflict (cpi_period) do '
  'nothing`; `do update` reaches the immutability fence and fails loud. STANDING '
  'REQUIREMENT — whatever populates this table MUST read from an EXPLICITLY '
  'MONTHLY-PROJECTED source: the period must be filtered to a real calendar month '
  '(month non-null and 1..12) BEFORE a date is constructed from it, reusing the '
  'projection the CPI-U mapper already applies rather than adding a new fence. BLS '
  'period codes are not all calendar months (M13 is the annual average, S01/S02 are '
  'semiannual) and the transport function returns raw codes with no grain filter by '
  'design, so a new consumer inherits no guard. ⚠ TWO OBSTACLES, IN THIS ORDER. '
  'FIRST, the transport (utils.fetch_cpi_df) removes value-null rows from its OWN '
  'RETURN VALUE — it logs and discards them — so those periods never reach any '
  'consumer at all and a writer following only the projection rule has NOTHING to '
  'project and still records nothing. Lifting or making that drop opt-out is '
  'Backend-owned work, and until it lands this table cannot be populated by any '
  'writer, however correct. SECOND, the mapper''s filter also requires series_value '
  'non-null and finite — exactly the rows this table exists to record — so reuse '
  'its MONTH conjuncts only; applying it wholesale yields an empty record '
  'indistinguishable from a clean run. ⚠ THE ENFORCEABLE FORM IS A COUNT '
  'RECONCILIATION, not a remembered rule: the writer''s run MUST assert that '
  'periods returned by transport = rows upserted to pfin.cpi_u_index + rows '
  'recorded here, and FAIL LOUD on imbalance. That catches both obstacles without '
  'either being individually remembered, and catches a future drop added for some '
  'third reason. The first-of-month '
  'CHECK on this table fences the DAY of an already-constructed date, cannot '
  'conjure a row the transport discarded, and CANNOT '
  'substitute for any of this — necessary, not sufficient. STANDING '
  'REQUIREMENT — if 053''s key ever widens to admit a second series, this table''s '
  'key and pfin.fn_cpi_u_index_for_period''s join MUST widen with it. Consumption '
  'policy lives in ONE helper (ADR-049 Decision 4): pfin.fn_cpi_u_index_for_period. '
  'Do NOT re-derive the carry/gap policy inline in a consumer. This table records '
  'only "published with no value" — it does not distinguish "not yet published" '
  'from "our ingest dropped it" from "backfill never covered the span" (ADR-049 '
  'Decision 2). aal2 step-up backstop EXCLUDED (reason (i) global shared-read).';

comment on column pfin.cpi_u_nonpublication.cpi_period is
  'PRIMARY KEY = the calendar month the source published with no usable value, '
  'normalized to first-of-month (DATE), CHECK-fenced. Same grain as '
  'pfin.cpi_u_index.cpi_period so the two tables join on it directly. A period '
  'appearing in BOTH tables is not a contradiction — it is the "unpublished when we '
  'looked, published later" case that this table exists to preserve.';
comment on column pfin.cpi_u_nonpublication.source is
  'BLS series-id provenance (DEFAULT ''BLS_CUUR0000SA0'' = CPI-U, all urban '
  'consumers, US city average, all items, not seasonally adjusted). Mirrors '
  'pfin.cpi_u_index.source. Carried for provenance; it is NOT part of the key — see '
  'the SINGLE-SERIES KEY block in this migration''s header for why the grain is '
  'deliberately coupled to 053''s.';
comment on column pfin.cpi_u_nonpublication.published_value_raw is
  'What the source actually emitted in the value field for this period — the '
  'evidence for the record. The observed real-world case was the single character '
  '''-''. NULL is permitted: it means the ingest did not capture the raw token, NOT '
  'that the source emitted an empty value. Length-bounded (<= 64) so a global '
  'service_role-writable table carries no unbounded-text write vector.';
comment on column pfin.cpi_u_nonpublication.observed_at is
  'Wall-clock of the INSERT that recorded this non-publication (DEFAULT now()). '
  'FIRST-observation time, not latest: the writer appends with `on conflict do '
  'nothing`, and UPDATE is trigger-blocked, so this value never moves. '
  'Ingest-provenance, NOT the CPI observation date (that is cpi_period).';

comment on constraint cpi_u_nonpublication_period_first_of_month on pfin.cpi_u_nonpublication is
  'Fences cpi_period to a first-of-month DATE, matching pfin.cpi_u_index''s '
  'documented grain. Load-bearing rather than cosmetic: a mis-keyed row (say '
  '2025-10-15) would silently never join 053 or match a consumer''s period lookup, '
  'making a WRITTEN record indistinguishable from a record that was NEVER WRITTEN — '
  'which defeats the table''s entire purpose. Role-agnostic (service_role bypasses '
  'RLS but NOT CHECK). Written as `extract(day from cpi_period) = 1` deliberately: '
  'it is zone-free by construction, whereas a date_trunc formulation invites a '
  'timestamptz variant that would be evaluated in the session TimeZone (ADR-044).';
comment on constraint cpi_u_nonpublication_raw_bounded on pfin.cpi_u_nonpublication is
  'Bounds published_value_raw to 64 characters. The column is written by '
  'service_role on a GLOBAL table (no tenant scoping to limit blast radius), so the '
  'bound removes an unbounded-text write vector by construction. 64 is far above any '
  'plausible BLS value token (the observed case is one character).';

-- ----------------------------------------------------------------------------
-- IMMUTABILITY — Surface 1: row-level UPDATE + DELETE fence.
-- The 004 / 054 append-only pattern. ⚠ READ THE "WHAT ACTUALLY HOLDS THE LINE"
-- BLOCK IN THE HEADER BEFORE REASONING ABOUT THIS TRIGGER. In production it does
-- NOT fire: service_role holds no UPDATE/DELETE grant, so the ACL refuses first.
-- This is a BACKSTOP, load-bearing exactly when a future migration widens that
-- grant, plus a fail-loud guard against an accidental owner-context mutation.
-- It is NOT the operative fence today and it is NOT un-bypassable by the owner,
-- who can disable it.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_cpi_u_nonpublication_block_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Fail LOUD (raise, NOT return null — return null would silently no-op the row
  -- and read as "succeeded"). Reached only when the ACL did not refuse first —
  -- in practice, owner/superuser context. See the header block.
  raise exception
    'pfin.cpi_u_nonpublication is immutable (append-only; ADR-049 Decision 1 / ADR-011 Decision 2). % blocked — a recorded non-publication was true at observation time and is retained even after the period is later published. Append with `on conflict (cpi_period) do nothing`, never `do update`.', tg_op;
end;
$$;

revoke execute on function pfin.fn_cpi_u_nonpublication_block_mutation() from public;

comment on function pfin.fn_cpi_u_nonpublication_block_mutation() is
  'BEFORE UPDATE OR DELETE immutability fence on pfin.cpi_u_nonpublication '
  '(ADR-049 Decision 1; ADR-011 Decision 2 / Lock 10 append-only class). SECURITY '
  'INVOKER — touches nothing, needs no elevated privilege, and is NOT a DEFINER '
  'allowlist entry (this migration adds none). raise exception (fail loud). ⚠ THIS '
  'IS A BACKSTOP, NOT THE OPERATIVE FENCE — measured 2026-08-10: service_role holds '
  'no UPDATE/DELETE grant, so those statements fail with `permission denied for '
  'table` and this trigger NEVER FIRES for it; and the table owner, for whom the '
  'ACL does not refuse, can `alter table ... disable trigger` and then mutate. What '
  'this earns: it becomes load-bearing if a future migration WIDENS the '
  'service_role grant, and it fails loud on an accidental owner-context mutation. '
  'Do not cite it as proof that mutation is impossible. INSERT is NOT blocked here: '
  'it is the ingest append path, and '
  'first-observation-wins is enforced by the primary key plus the writer''s '
  '`on conflict do nothing`, not by a trigger.';

create trigger cpi_u_nonpublication_block_mutation
  before update or delete on pfin.cpi_u_nonpublication
  for each row execute function pfin.fn_cpi_u_nonpublication_block_mutation();

-- ----------------------------------------------------------------------------
-- IMMUTABILITY — Surface 2: statement-level TRUNCATE fence.
-- Row-level triggers do NOT fire on TRUNCATE (Postgres runs only STATEMENT-level
-- BEFORE TRUNCATE triggers), so a role holding TRUNCATE could wipe the whole
-- record without tripping Surface 1. Statement-level fence (holds regardless of
-- grant) plus a defensive REVOKE.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_cpi_u_nonpublication_block_truncate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.cpi_u_nonpublication is immutable (append-only; ADR-049 Decision 1 / ADR-011 Decision 2). TRUNCATE blocked — the non-publication record cannot be wiped; per ADR-049 a gap you did not record cannot be retrospectively classified.';
end;
$$;

revoke execute on function pfin.fn_cpi_u_nonpublication_block_truncate() from public;

comment on function pfin.fn_cpi_u_nonpublication_block_truncate() is
  'BEFORE TRUNCATE (statement-level) immutability fence on '
  'pfin.cpi_u_nonpublication (ADR-049 Decision 1; ADR-011 Decision 2 / Lock 10). '
  'SECURITY INVOKER (touches nothing; not a DEFINER allowlist entry). raise '
  'exception (fail loud). Closes the TRUNCATE bypass: row-level UPDATE/DELETE '
  'triggers do NOT fire on TRUNCATE, so a role holding TRUNCATE would not trip the '
  'row-level fence. ⚠ SAME BACKSTOP CAVEAT as the row-level fence — measured '
  '2026-08-10: service_role holds no TRUNCATE privilege, so TRUNCATE fails with '
  '`permission denied for table` and this trigger never fires for it; it fires '
  'where the ACL does not refuse, and an owner can disable it. Message deliberately '
  'distinct from the row-level fence so a battery can tell which surface fired.';

create trigger cpi_u_nonpublication_block_truncate
  before truncate on pfin.cpi_u_nonpublication
  for each statement execute function pfin.fn_cpi_u_nonpublication_block_truncate();

-- Defense-in-depth: PUBLIC holds no TRUNCATE by default, but revoke explicitly so
-- a broad platform/default grant cannot reintroduce it. Note this REVOKE is the
-- layer that actually refuses in production — the statement-level trigger above
-- is reached only where the ACL does not (see WHAT ACTUALLY HOLDS THE LINE).
revoke truncate on pfin.cpi_u_nonpublication from public;

-- ----------------------------------------------------------------------------
-- RLS — public reference read; service_role-only append.
-- grant-before-RLS shape (PR #106): the table ACL is checked BEFORE RLS, so the
-- authenticated SELECT grant is required even with RLS enabled (RLS filters rows;
-- the GRANT lets the role reach the table at all). authenticated gets SELECT only
-- (no write grant → cannot INSERT/UPDATE/DELETE regardless of policy).
-- service_role gets SELECT + INSERT ONLY — no UPDATE, no DELETE. ⚠ THAT
-- WITHHOLDING IS THE OPERATIVE APPEND-ONLY FENCE, not a secondary layer:
-- measured 2026-08-10, service_role UPDATE / DELETE / TRUNCATE / `on conflict …
-- do update` all fail with `permission denied for table` and the immutability
-- triggers never fire. The triggers stand BEHIND this line, and they become
-- load-bearing precisely if someone later widens it. Treat any widening of this
-- grant as a security change, not a convenience.
-- anon: nothing (schema USAGE denies before ACL).
-- ----------------------------------------------------------------------------
alter table pfin.cpi_u_nonpublication enable row level security;

create policy cpi_u_nonpublication_select on pfin.cpi_u_nonpublication
  for select to authenticated
  using (true);

comment on policy cpi_u_nonpublication_select on pfin.cpi_u_nonpublication is
  'SELECT: every authenticated user reads every non-publication row — public macro '
  'reference data (using(true), the global shared-read class, same as 053 and '
  'tax_character). NO tenant predicate (there is no users_id). This is the ONLY '
  'authenticated policy: INSERT / UPDATE / DELETE have no policy → default-deny for '
  'authenticated, so a user can neither forge nor erase a non-publication record. '
  'service_role writes bypass RLS but are still bounded by the ACL (INSERT only) '
  '(the triggers stand behind that ACL, not in front of it). aal2 backstop '
  'excluded (global shared-read) — '
  'no per-user-conditional clause.';

grant select on pfin.cpi_u_nonpublication to authenticated;
grant select, insert on pfin.cpi_u_nonpublication to service_role;

-- ============================================================================
-- Migration: comment-only corrections to `063`'s cpi_u_nonpublication table
--   comment and `064`'s fn_cpi_u_index_for_period function comment. NO DDL, NO
--   grant, NO policy, NO trigger, NO function body. The `052` comment-only
--   shape.
--   JOINT-REVIEW-MANDATORY (Sec veto surface): both corrected comments sit on
--   ADR-011 Decision 1 surfaces (the record feeding, and the read path into,
--   inflation-adjusted financial figures), and `063` is ADR-011 Decision 2
--   audit-class. Sec gates this migration.
--
-- ----------------------------------------------------------------------------
-- WHY A MIGRATION AND NOT AN EDIT — the vehicle follows WHERE THE TEXT LIVES
--   (Sec ruling 2026-08-10 at `055`). A `comment on ...` string HAS a database
--   representation: it ships into pg_description and is read at `\d+` by someone
--   with NO REPO IN FRONT OF THEM. It can only change by issuing new SQL, so a
--   merged migration's catalog comment is corrected by a NEW comment-only
--   migration, never by editing the merged file.
--   ⚠ THE SAME CORRECTIONS ALSO LAND IN `063`'s AND `064`'s FILE-HEADER `--`
--   BLOCKS, IN PLACE, IN THE SAME PR — and that is not a duplicate vehicle, it
--   is the OTHER half of the same rule. A `--` header has NO database
--   representation, so no migration could correct it; a no-op "correction
--   migration" would leave the false text exactly where readers look. Two
--   surfaces, two vehicles, one PR.
--
-- ----------------------------------------------------------------------------
-- Numbering: 065 follows 064. Next free number taken AT AUTHORING TIME, never
--   reserved ahead (ADR-049 Consequences; the 058->059 slip is the precedent).
--   Depends on: 053 + 063 (the table) + 064 (the function). Order-DEPENDENT —
--   both objects must exist before their comments can be replaced.
--
-- ----------------------------------------------------------------------------
-- METHOD — regenerate-and-diff, NEVER retype. These are multi-KB single-quoted
--   literals where a botched edit is a SYNTAX ERROR, not a wording problem, and
--   retyping is how the correct halves get silently altered alongside the wrong
--   one. Each comment below was produced by extracting the merged literal
--   verbatim and applying ONE anchored substitution, with:
--     (1) the anchor asserted to match EXACTLY ONCE (>1 = not unique; 0 = the
--         source drifted);
--     (2) a CONTAINMENT PROOF — the prefix before the replaced span and the
--         suffix after it are byte-identical to the merged original, with ONE
--         contiguous replaced span. Preferred to counting diff regions: a region
--         count characterises only what CHANGED, whereas containment makes a
--         positive claim about everything that did NOT.
--           063 table comment ....... prefix 2871B / suffix  787B byte-identical
--           064 function comment .... prefix 1515B / suffix 3110B byte-identical
--     (3) parse-in-rollback, and
--     (4) render-verify via obj_description — the catalog string is what
--         actually ships, and a doubled '' leaking into rendered text is
--         INVISIBLE in source.
--
-- ----------------------------------------------------------------------------
-- WHAT IS CORRECTED, AND WHY EACH WAS FALSE. Each correction NAMES THE CLAIM IT
--   REPLACES, so a reader who remembers the old text learns it CHANGED rather
--   than doubting their memory.
--
--   (A) `063` — THE RECONCILIATION FORMULA HAD TWO TERMS AND CANNOT BALANCE.
--       It read: "periods returned by transport = rows upserted to
--       pfin.cpi_u_index + rows recorded here". The transport is DELIBERATELY
--       grain-agnostic and returns raw BLS period codes; an M13 (annual average)
--       or S01/S02 (semiannual) belongs to NEITHER table, so under the two-term
--       form ONE such row fails the assertion FALSELY and kills the nightly
--       ingest. That today's CPI-U payload requests neither `annualaverage` nor
--       `aspects` is no defence — `063`'s own header already rules that THE
--       REQUEST IS THE GUARANTEE AND THE RESPONSE IS ONLY AN OBSERVATION, so an
--       assertion must not be built on the observation. A THIRD TERM (periods
--       that are not calendar months) is REQUIRED, and it must be computed
--       directly from the transport return by an expression calling NEITHER
--       mapper — that independence is what lets the sum come up short, and
--       therefore FAIL, when a mapper grows a filter nobody anticipated.
--
--   (B) `063` — "THAT CATCHES BOTH OBSTACLES" WAS OVER-CLAIMED, AND THIS IS THE
--       FALSIFIABLE ONE. The formula's leading term is periods RETURNED by
--       transport, so a row discarded BEFORE the return is absent from EVERY
--       term and the sum still balances. The reconciliation is therefore
--       STRUCTURALLY BLIND to the exact regression it was specified to catch.
--       DEMONSTRATED, NOT ARGUED: with the transport drop re-armed, the gate did
--       NOT raise. Coverage for that obstacle lives ONE LAYER EARLIER, in a
--       transport contract test asserting the valueless period is RETAINED in
--       the return value. ⚠ The consequence that makes this worth a migration:
--       a reader who believes the reconciliation covers both obstacles will
--       DELETE THAT CONTRACT TEST AS REDUNDANT, and the two worlds are identical
--       at every other layer.
--
--   (C) `063` — "UNTIL IT LANDS THIS TABLE CANNOT BE POPULATED BY ANY WRITER"
--       WAS A MERGE-ORDER STATE CLAIM IN A CATALOG COMMENT. It was true when
--       written and goes false the moment the transport lift merges, and a
--       reader at `\d+` has no repo with which to check it. Rewritten as the
--       STANDING PROPERTY underneath it, which is true before and after that
--       work lands: this table can only be populated from a transport return
--       that CARRIES value-null periods. The writer's correctness was never the
--       binding constraint; the transport's return is. ⚠ Deliberately NO
--       reference to the branch or PR that lifts the drop: a document may
--       forward-reference a document, but a CORRECTNESS CLAIM must not
--       forward-reference the mechanism that makes it true.
--
--   (D) `064` — "PM-OWNED AND NOT YET F/CTO-RATIFIED" IS FALSE AT `main`. F/CTO
--       ratified the ADR-049 Decision 5 product question 2026-08-10, and the PRD
--       §2.4.4 amendment (one marker system, two tiers — actionable and
--       informational) merged the same day. ⚠ THE SHAPE NEVERTHELESS STAYS
--       PROVISIONAL AND THE CAVEAT IS NOT WEAKENED — the REASON changed rather
--       than lapsed. §2.4.4 routes the mapping of its product distinctions onto
--       this helper's result shape onward as architecture-layer detail, so what
--       remains open is an ARCHITECT ruling pending F/CTO ratify, not a PM one.
--       Clearing the caveat outright would have converted a discharged blocker
--       into a frozen signature, which is the opposite of what the ruling did.
--
--   ⚠ WHAT IS **NOT** TOUCHED, so this is not read as license: `064`'s LOCKED
--   properties (the composite/row return and the non-silence it enforces) and
--   the C1 both-coverage-edges-bounded correction, which is INDEPENDENT of the
--   product ruling. `063`'s two obstacles, the second-consumer trigger, the
--   grain requirement, the WHAT ACTUALLY HOLDS THE LINE role measurements, and
--   every STANDING REQUIREMENT are preserved byte-identically — see the
--   containment proof above.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — NOT APPLICABLE BY CONSTRUCTION. This migration authors NO
--   function of either posture, so the ADR-011 Decision 9 SECURITY DEFINER
--   allowlist is UNCHANGED by it (+0). Stated as a DELTA, not as a level: the
--   allowlist's size is read live from Decision 9, never copied into a file that
--   cannot maintain it. `064`'s helper remains SECURITY INVOKER (Lock 11);
--   `063`'s two trigger fences remain SECURITY INVOKER. No function body, no
--   signature, no grant and no policy is altered here — ⚠ the SQL below is
--   replay-equivalent to `063` + `064` in every respect EXCEPT the two comment
--   literals, which is a stronger claim than "it parses".
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — ADR-011 Decision 4 is LINKED, not restated;
--   read verbatim live before drafting this file. This migration is not the
--   canonical anchor, so the catalogued numbered list is deliberately NOT
--   reproduced and NO count appears — a derived surface that copies a count
--   acquires a maintenance obligation it will not honour.)
--   (i)   Instance-numbering: catalogues NO new §10 instance and reorders none.
--         Ledger DELTA = 0.
--   (ii)  Layer-attribution: this migration replaces two catalog comment strings
--         on global public reference objects. It is NOT the code-layer
--         SUPABASE_SERVICE_ROLE_KEY allowlist grep fence, NOT the PDF-worker
--         container credential audit, NOT the app->worker admission network/
--         config surface. It touches no credential, no container, no endpoint
--         and no ACL.
--   (iii) Verbatim-vs-paraphrase: Decision 4 linked, not restated (Path B).
--   DE-CONFLATION GUARD: no FK-shaped column, no credential-presence surface, no
--   admission endpoint — none of the three is a §10 catalogued instance.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED set are DIFFERENT SETS. Neither
--   is reconciled to the other here, and neither should be "tidied" to match;
--   that cleanup would destroy a real distinction.
--
-- ----------------------------------------------------------------------------
-- ADR-011 DECISION 3 (cross-tenant FK-bypass family) — family UNCHANGED (+0).
--   This migration creates no table and no column, hence no FK-shaped reference
--   column; and both objects it comments on are GLOBAL, so there is no tenant
--   boundary to bypass. Both ADR-049 Decision 1 non-membership grounds carry
--   through unchanged. The family's size is read live from ADR-011 Decision 3's
--   body — this file carries no tally, by the same rule that governs the §10
--   block above.
--
-- ----------------------------------------------------------------------------
-- LEDGER DELTAS (all confirmed FLAT, stated as deltas): §10 catalogued
--   instances +0 · SECURITY DEFINER allowlist +0 (no function authored) ·
--   ADR-011 Decision 3 family +0 · SD matrix — NO expansion. Sec review is
--   MANDATORY notwithstanding the flat ledgers: ADR-011 Decision 1 + Decision 2
--   surfaces.
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- (A) pfin.cpi_u_nonpublication — corrections (A) + (B) + (C) above.
-- Regenerated from the `063` literal; containment proven (prefix 2871B / suffix
-- 787B byte-identical, one contiguous replaced span).
-- ----------------------------------------------------------------------------
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
  'Backend-owned work. STANDING PROPERTY, stated as a property rather than as a '
  'merge-order state: this table can ONLY be populated from a transport return that '
  'CARRIES value-null periods — no writer, however correct, can record a row the '
  'transport discarded before returning. SECOND, the mapper''s filter also requires '
  'series_value non-null and finite — exactly the rows this table exists to record '
  '— so reuse its MONTH conjuncts only; applying it wholesale yields an empty record '
  'indistinguishable from a clean run. ⚠ THE ENFORCEABLE FORM IS A COUNT '
  'RECONCILIATION, not a remembered rule: the writer''s run MUST assert that '
  'periods returned by transport = rows for pfin.cpi_u_index + rows for '
  'pfin.cpi_u_nonpublication + periods that are NOT CALENDAR MONTHS, and FAIL LOUD '
  'on imbalance. ⚠ THE THIRD TERM IS REQUIRED, NOT DEFENSIVE: this comment '
  'previously stated the assertion with only the first two terms, and in that form '
  'IT CANNOT BALANCE — the transport is deliberately grain-agnostic and returns raw '
  'BLS period codes, so an M13 (annual average) or S01/S02 (semiannual) belongs to '
  'NEITHER table and would fail the assertion FALSELY, killing the ingest. The third '
  'term must be computed directly from the transport return by an expression calling '
  'NEITHER mapper — that independence is what lets the sum come up short, and '
  'therefore fail, when a mapper grows a filter for some future reason. ⚠ AND THE '
  'RECONCILIATION DOES NOT CATCH BOTH OBSTACLES: this comment previously claimed it '
  'caught both, and that claim was FALSE for the FIRST. Its leading term is periods '
  'RETURNED by transport, so a row discarded BEFORE the return is absent from every '
  'term and the sum still balances — the gate is STRUCTURALLY BLIND to the exact '
  'regression it was specified to catch (demonstrated, not argued: with the '
  'transport drop re-armed, the gate did NOT raise). Coverage for the FIRST obstacle '
  'lives one layer earlier, in a transport contract test asserting the valueless '
  'period is RETAINED in the return value; NEITHER SUBSTITUTES FOR THE OTHER, and a '
  'reader who takes this assertion as covering both will delete that contract test '
  'as redundant. What the reconciliation DOES cover: the SECOND obstacle, and a '
  'future drop introduced at mapper level. The first-of-month '
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

-- ----------------------------------------------------------------------------
-- (B) pfin.fn_cpi_u_index_for_period(date) — correction (D) above.
-- Regenerated from the `064` literal; containment proven (prefix 1515B / suffix
-- 3110B byte-identical, one contiguous replaced span). The signature, body,
-- posture and grants are untouched — this statement replaces a comment only.
-- ----------------------------------------------------------------------------
comment on function pfin.fn_cpi_u_index_for_period(date) is
  'THE single CPI-U consumption helper (ADR-049 Decision 4). Resolves the CPI-U '
  'index level to use for a period AND says how it was resolved. SECURITY INVOKER '
  '(ADR-011 Lock 11 read-composition; not a DEFINER allowlist entry — this '
  'migration adds none), STABLE, set search_path = ''''. Reads pfin.cpi_u_index '
  '(053) and pfin.cpi_u_nonpublication (063), both global public reference tables '
  'with `using (true)` SELECT policies, so no tenant boundary is crossed. '
  'Returns EXACTLY ONE ROW: (cpi_period, cpi_value, is_carried, carried_from, '
  'gap_class, nonpublication_on_record). p_period is normalized to first-of-month '
  'and the normalized value '
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
  '⚠ THE RETURN SHAPE IS PROVISIONAL — BOTH the column set and the gap_class '
  'member set. ⚠ THE PRODUCT RULING THIS WAS PENDING ON HAS LANDED: this comment '
  'previously read "PM-owned and not yet F/CTO-ratified" of the ADR-049 Decision 5 '
  'question, and that is SUPERSEDED — F/CTO ratified it 2026-08-10 and the PRD 2.4.4 '
  'amendment (one marker system, two tiers: actionable and informational) was merged '
  'the same day. THE SHAPE NEVERTHELESS STAYS PROVISIONAL, and the reason CHANGED '
  'rather than lapsed: PRD 2.4.4 carries the mapping of its product distinctions '
  'onto this helper''s result shape as architecture-layer detail, so what remains '
  'open is an ARCHITECT ruling pending F/CTO ratify, not a PM one. Read PRD 2.4.4 '
  'verbatim rather than any summary of it. ADR-049 Decision 4 locks the '
  'composite return and the non-silence it enforces, and explicitly leaves THE '
  'SIGNATURE to the implementing PR "pending the product ruling" — and the column '
  'set and member set are both part of that signature. The sixth column '
  '(nonpublication_on_record) was added after D4 was written, so the shape '
  'sits further from what D4 contemplated, which sharpens this caveat rather than '
  'relieving it. Do NOT inherit it as frozen; it may move when the ARCHITECTURE '
  'ruling lands. What is NOT provisional: both coverage edges are bounded, which '
  'is independent of any product ruling. '
  'gap_class is a TEXT set: ''published'' (own print) / '
  '''recorded_nonpublication'' (source published the period with no usable value; '
  'ADR-049 Decision 2 state (a), the only positively-recorded absence) / '
  '''unrecorded_gap'' (absent and STRICTLY INTERIOR to the coverage window, so it '
  'was demonstrably due and nothing explains it — THE ONLY ALARM CLASS) / ''before_coverage'' (absent and '
  'earlier than anything the store holds) / ''beyond_coverage'' (absent and later '
  'than anything the store holds; also the empty-store case) — the last two are '
  'NOT alarms. Both coverage edges are bounded: a period is called a gap only '
  'when prints bracket it on BOTH sides. gap_class reports the ABSENCE REASON and '
  'is ORTHOGONAL to the carry outcome: cpi_value is NULL when no period at or '
  'before the requested one exists, never a fabricated zero. '
  'nonpublication_on_record is TRUE iff a non-publication record exists for the '
  'period REGARDLESS of whether a print now exists — it is the only way the '
  '"unpublished when we looked, published later" audit trail is readable through '
  'this helper, and it is NOT derivable from gap_class, which reads ''published'' '
  'in exactly that case. '
  'BOUNDED BY CONSTRUCTION — the due-period test is DATA-DERIVED (is the period '
  'bracketed by prints on BOTH sides?), not calendar-derived, which is the '
  'stricter bound ADR-049 '
  'Decision 3 permits; it consults no clock, so it is outside ADR-044''s two-clock '
  'hazard. ITS COST: it CANNOT detect a stalled ingest — a dead ETL yields '
  '''beyond_coverage'' indefinitely, indistinguishable from "not yet published". '
  'Ingest-freshness monitoring is NOT this function''s job and must not be '
  'inferred from its output. This function also does not decide what the USER '
  'sees: that routes to the existing non-silent-staleness framework per ADR-049 '
  'Decision 5. '
  '⚠ EXECUTE IS GRANTED TO authenticated ONLY, DELIBERATELY — service_role is not '
  'granted EXECUTE and that is a decision, not an oversight. Both tables read here '
  'are pure-global, and ADR-023 Step 0 assigns pure-global reads to authenticated; '
  'a service_role grant would open a second read path for the same data and would '
  'buy nothing, since service_role''s distinguishing power is BYPASSRLS and '
  '`using (true)` leaves no RLS restriction to bypass. A privileged-context caller '
  'must SET ROLE authenticated — note the worker identity is NOINHERIT, so it must '
  'do so EXPLICITLY. Measured end-to-end 2026-08-10: under that identity, '
  'service_role context gives `permission denied for function`, and bare context '
  'with no SET ROLE fails EARLIER still with `permission denied for schema pfin` '
  '(schema USAGE is checked before the function ACL) — two different messages, '
  'same cause, same fix. SET ROLE authenticated then succeeds. THE '
  'FIX FOR EITHER ERROR IS SET ROLE, NOT WIDENING THIS GRANT. Widening it is a grant '
  'change on a function feeding financial figures and requires Sec re-review.';

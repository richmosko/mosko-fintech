-- ============================================================================
-- Migration: pfin.tax_bracket_schedule + pfin.tax_bracket_row — the V1.4
-- estimated-tax bracket substrate. Phase 6 Build Loop (SELF-259). Realizes two
-- members of the ADR-011 Decision 18 / Lock 14 per-domain settings store, lands
-- the Seam A grain ruling, and ALLOCATES ADR-011 Decision 3 canonical instance
-- #18. Sec joint-review MANDATORY (Lock 14 surface + a Decision-3 family
-- extension + financial-calculation inputs).
--
-- WHAT THIS DOES: creates the enum pfin.tax_schedule_type_enum, the parent
-- table pfin.tax_bracket_schedule (one row per user per tax_year per schedule
-- type, carrying the standard deduction and the informational prior-year tax
-- balance) and the child table pfin.tax_bracket_row (one row per bracket,
-- carrying a lower-bound threshold and a marginal rate). Owner-only RLS on all
-- four verbs on BOTH tables, each policy carrying the 025 aal2 step-up clause.
-- Authors THREE functions, all SECURITY INVOKER: two trigger fences and the
-- replace-all write body fn_tax_bracket_schedule_replace_all.
--
-- ----------------------------------------------------------------------------
-- THE GRAIN — R4 (Seam A: bracket-table storage grain + the Decision-3
--   sub-part), F/CTO RULING (C), 2026-09-03, ONE-WAY DOOR (sub-part). Cited by
--   name, not restated: read the sitting log's R4 entry live.
--   THE GRAIN BUILT HERE IS (C): two tables as Lock 14 names them, with the
--   CHILD CARRYING ITS OWN users_id BESIDE schedule_id. Two tenant facts exist
--   on pfin.tax_bracket_row and THEY CAN DISAGREE. That is the point of (C):
--   it is what makes the matched-tenant fence below a fence that CAN FAIL.
--   Option (A) (child references the parent only) NOT taken — under it the row
--   is not a Decision-3 member at all and a matched-tenant fence would be a leg
--   that cannot fail (the ADR-062 Decision 2 rejected shape). Option (B) (one
--   denormalized table) NOT taken — the standard-deduction scalar has no home
--   and Lock 14's enumeration would need amending.
--
-- ----------------------------------------------------------------------------
-- ADR-011 DECISION 3 — ONE CANONICAL LABEL ALLOCATED HERE: #18.
--   Decision 3 was read LIVE from DECISIONS.md before drafting, per its own
--   standing discipline and per Decision 18's amendment barring any label being
--   drafted in advance. The sentence that fixes this allocation, quoted from
--   Decision 3's `084` re-target resolution, consequence (a):
--     "The next genuine FK-bypass instance still takes #18."
--   The same sentence stands in Decision 3's #10 entry ("No new label is
--   allocated and the next genuine FK-bypass instance still takes #18"). This
--   file carries NO tally of the family — read Decision 3's body live for its
--   current shape.
--
--   PER-COLUMN DISPOSITION — every FK-shaped column on both tables, stated
--   individually rather than in aggregate:
--     (1) pfin.tax_bracket_schedule.users_id -> auth.users(id)
--         NOT a Decision-3 instance. This IS the table's tenant anchor, not a
--         cross-tenant reference — the disposition Decision 3's own body
--         records for the same column shape, and the one 090 records for
--         pfin.cashflow_target.users_id.
--     (2) pfin.tax_bracket_row.users_id -> auth.users(id)
--         NOT a Decision-3 instance, on the same ground as (1). Under grain (C)
--         it is the child's LOCAL ANCHOR — the thing the fence in (3) compares
--         AGAINST — which is what makes (3) a P1 instance rather than a CR one.
--     (3) pfin.tax_bracket_row.schedule_id -> pfin.tax_bracket_schedule(id)
--         *** ADR-011 DECISION 3 CANONICAL INSTANCE #18 ***
--         Fence pattern P1 (matched-tenant, LOCAL ANCHOR — the 012 shape): the
--         referring row carries its own users_id and the fence asserts
--         new.users_id equals the referenced schedule's users_id. A DECLARED FK
--         (references ... on delete cascade). Realized at this migration.
--         Structurally the twin of #8 (022) and #17 (074): both sides per-user,
--         referring row carries its own users_id. BEFORE INSERT OR UPDATE — the
--         012 / 022 / 074 MUTABLE-settings shape, NOT the 019 / 044 / 057
--         immutable-audit INSERT-only shape: this table is rewritten by the
--         replace-all path, so an INSERT-only fence would leave the repoint
--         path open. ONE predicate only (matched-tenant); the #14 / #17
--         "one fence, two predicates" precedent is NOT extended here, because
--         the referenced TABLE already expresses everything a second predicate
--         would (a tax_bracket_schedule row is a tax_bracket_schedule row).
--
--   ⚠ THE FOLD-IN INTO DECISION 3's ENUMERATION IS OWED BY THIS PR AND IS NOT
--     IN THIS FILE. Decision 3's own rule, written at the ADR-042 fold-in and
--     recorded as honoured at the SELF-324 / 074 fold-in, is that the fold-in
--     is due in the PR THAT DDL-REALIZES THE INSTANCE, not at the next
--     reconciliation — and #16 is on the record as having "asserted a canonical
--     label in a live catalog object while this list still read fifteen." This
--     branch is scoped to this one migration file, so the DECISIONS.md edge of
--     that obligation is carried by the PR, not by this file. #18 is not
--     invented here: Decision 3's live text already directs the next instance
--     to take it, in two separate places quoted above.
--
--   ⚠ Decision 18's locked "NOT a new instance ... settings writes are
--     user-session-bounded" clause argued from the WRITE PATH; Decision 3 turns
--     on COLUMN SHAPE, and R4 records Architect and Sec reaching that
--     independently. The TAIL of that Decision 18 sentence — the V2+
--     live-tax-API ingestion trigger, the mandatory Sec re-consult at that
--     adoption, and the Lock 12 mod #2-pattern fence going V1-SHIP-BLOCK then —
--     is UNTOUCHED and LIVE.
--
--   ⚠ SUFFICIENCY, AND WHERE IT COMES FROM (this fence is necessary, not
--     sufficient). Per ADR-011 Decision 4's 2026-09-03 amendment, a Decision-3
--     matched-tenant trigger and the FOREIGN KEY it backstops go inert TOGETHER
--     under session_replication_role = 'replica' — referential integrity is
--     itself implemented as internal triggers. That GUC is superuser-context
--     and is denied to both authenticated and service_role, so it is not
--     tenant-reachable; the consequence is operational, and any restore or
--     bulk-load runbook that sets it owes an explicit post-load validation of
--     this pair. Policy-backed controls survive that GUC; trigger-backed
--     controls do not.
--
-- ----------------------------------------------------------------------------
-- THE TWO SET PROPERTIES, AND WHY A BEFORE ROW TRIGGER CANNOT OBSERVE EITHER
--   (R4 rider 1 + R4 rider 8; Sec §3 trap 1 + Sec §10.2 item 5).
--
--   A BEFORE ROW trigger fires once per row, BEFORE that row is visible to any
--   read and BEFORE the later rows of the same statement exist at all. The
--   replace-all write path sends the whole schedule as ONE multi-row INSERT.
--   So a per-row fence evaluates each row against an INCOMPLETE set: row 1 sees
--   nothing, row 2 sees nothing (row 1 is not yet visible), and a batch that is
--   collectively invalid passes row-by-row. ⚠ That is a fence written in a form
--   that CANNOT OBSERVE THE PROPERTY IT NAMES — worse than no fence, because it
--   reads to a reviewer as a live guarantee.
--
--   Both properties below are therefore carried by ONE
--   `create constraint trigger ... after insert or update or delete ...
--   deferrable initially deferred`, which evaluates at COMMIT, once the whole
--   set exists. ⚠ `create constraint trigger` REQUIRES `for each row` — a
--   statement-level trigger cannot be declared deferrable — so the function
--   re-reads the whole schedule set on each firing rather than relying on a
--   transition table. For a schedule of a handful of brackets that is the right
--   trade; it is recorded so a later reader does not read the row-level
--   declaration as a row-level CHECK.
--
--   LEG A — ZERO FLOOR. The LOWEST bracket_floor of a non-empty schedule MUST
--     be exactly 0. Monotonicity cannot catch this: a schedule whose lowest
--     floor is 11000 is perfectly monotone and silently taxes the first $11,000
--     at zero. A DIFFERENT property from ordering, needing its own control.
--     An EMPTY schedule PASSES, deliberately: replace-all deletes and re-inserts
--     inside one transaction, and a schedule that has been cleared but not yet
--     repopulated is the ABSENCE of brackets, not a malformed set. Absence is
--     the unset representation on this pair throughout (see standard_deduction).
--
--   LEG B — RATE MONOTONICITY. Reading the schedule's rows in ascending
--     bracket_floor order, bracket_rate MUST be NON-DECREASING.
--     ⚠ WHY THE RATE AND NOT THE FLOOR, stated because the obvious reading is
--     the wrong one. `unique (schedule_id, bracket_floor)` already makes the
--     floors of one schedule pairwise DISTINCT, and any set of distinct
--     numerics is totally ordered — so "the floors ascend" is true BY
--     CONSTRUCTION and a trigger leg asserting it COULD NEVER FIRE. Shipping
--     that leg would be the same defect this rider exists to remove, one level
--     up: a control over a guaranteed property, which cannot fail and which
--     turns a future regression into an outage instead of a rejection. The
--     falsifiable set property in a bracket schedule is the PAIRING — a batch
--     of (0, 0.10) and (11000, 0.05) is a genuinely non-monotone schedule, no
--     unique constraint sees it, and no per-row check can either.
--     NON-DECREASING rather than STRICTLY increasing: two adjacent brackets at
--     the same rate are unusual but not malformed, and refusing them would
--     invent a constraint no jurisdiction's schedule owes us.
--     ⚠ This leg COMMITS the pair to PROGRESSIVE schedules. All three V1
--     schedule types are progressive. A regressive schedule would be refused
--     and would need this leg amended.
--
--   ⚠ SERIALIZABLE IS NOT A SUBSTITUTE FOR EITHER LEG, AND NEITHER IS A
--     SUBSTITUTE FOR IT (Sec D-5, confirmed at R4 rider 2, which struck
--     SELF-259's companion claim). SERIALIZABLE guarantees equivalence to SOME
--     serial order; it says nothing whatever about whether one transaction
--     leaves the rows monotone. Two independent controls.
--
--   ⚠ WHERE THIS FENCE'S SUFFICIENCY COMES FROM. It is SECURITY INVOKER, so its
--     read of the schedule's row set composes with RLS. Its claim to see "the
--     whole set" therefore rests on every row of one schedule belonging to one
--     tenant — which is exactly what the #18 matched-tenant fence enforces. The
--     two fences are not independent: strike #18 and this one silently narrows.
--
-- ----------------------------------------------------------------------------
-- RULING — bracket_rate's UNIT IS A FRACTION (0.22), BOUND 0 <= rate <= 1.
--   R4 rider 8 (Sec §10.2 item 4; Sec M-7) requires a unit + domain CHECK with
--   the unit stated IN WORDS in the column comment, and leaves the choice open:
--   percent (22, bound <= 100) or fraction (0.22, bound <= 1). Ruled FRACTION by
--   team-lead under F/CTO delegation at this migration.
--   REASON: the PRD's estimated-tax arithmetic MULTIPLIES by the rate. A
--   fraction multiplies directly; a percent needs a /100 at every call site, and
--   a unit that has to be divided out is a unit some call site will forget.
--   THE LOSING SIDE, named rather than omitted: percent reads more naturally to
--   a human filling the settings editor ("22", not "0.22"), matches how the IRS
--   and FTB publish their tables, and would have made a mis-typed 0.22 (meaning
--   22%) fail LOUDLY at the <= 100 bound instead of silently storing a 0.22%
--   rate. Under FRACTION, the reverse mis-type — entering 22 meaning 0.22 — is
--   the one that fails loudly, at the <= 1 bound. The presentation layer owes
--   the x100 for display either way; only one of the two directions can fail
--   loudly, and this ruling puts the loud failure on the entry a settings editor
--   is most likely to send (a human typing the published percent).
--   ⚠ A unit that lives only in the seed data is a unit the next writer gets
--   wrong, which is why it is stated in words in the column comment and NOT
--   left to be inferred from SELF-260's seed.
--
-- ----------------------------------------------------------------------------
-- NUMERIC FENCE — TWO-SIDED, AND THE TYPMOD IS PART OF IT.
--   R4 rider 8 (Sec §10.2 item 3; Sec M-10) requires two-sided NaN CHECKs on
--   all three numerics — standard_deduction, bracket_floor, bracket_rate. NaN
--   IS storable in a numeric column and sorts ABOVE every non-NaN numeric, so a
--   one-sided `>= 0` ADMITS IT. The explicit `<> 'NaN'::numeric` literal is the
--   014 / 053 / 090 idiom and is what refuses it. Copied rather than re-derived,
--   because the inverse form used elsewhere does not reject NaN.
--   ⚠ DEPARTURE FROM THE AC's LITERAL `numeric`, AND THE REASON. The AC writes
--     these columns as bare `numeric`. A BARE numeric ACCEPTS ±Infinity:
--     'Infinity'::numeric is storable, `Infinity >= 0` is TRUE and
--     `Infinity <> 'NaN'::numeric` is TRUE, so the rider-8 CHECK as written
--     admits it. A TYPMOD refuses ±Infinity at coercion (precision overflow —
--     measured at 014, restated at 090), so the columns are declared
--     numeric(20,4) / numeric(12,8) and the typmod carries the Infinity half
--     while the CHECK carries the NaN half. The AC fixes the grain and the
--     tenancy shape and says the rest of the column list is the migration
--     author's; the precision is taken under that clause. Neither half alone
--     closes the non-finite surface.
--   ⚠ bracket_rate's typmod is numeric(12,8), DELIBERATELY LOOSER than the
--     domain needs. numeric(9,8) would cap the integer part at one digit and a
--     mis-typed `22` would fail as a NUMERIC OVERFLOW — a correct rejection
--     with a useless message. At (12,8) the value coerces and the `<= 1` CHECK
--     is what refuses it, with the unit named in the constraint. The fence that
--     fires should be the one that can explain itself.
--   ⚠ tax_balance_prior_year is NOT one of rider 8's three and carries NO SIGN
--     BOUND, deliberately: a prior-year balance can be an overpayment, which is
--     legitimately negative. It carries the NaN literal anyway, and its typmod
--     carries Infinity, because neither of those is ever a balance.
--   This is the DB half of the Lock 14 mod #2 numeric-input discipline. It does
--   NOT replace the app-layer adversarial battery (Zod .strict() +
--   NaN/Inf/currency-string/overflow/scientific-notation/locale rejection),
--   which remains the first line and is owed at the write surface.
--
-- ----------------------------------------------------------------------------
-- standard_deduction IS NOT NULL, AND THE REASON IS RECORDED SO A LATER READER
--   DOES NOT "FIX" IT. Under replace-all a schedule and its rows are written as
--   ONE unit, so THE UNSET STATE IS THE ABSENCE OF THE SCHEDULE ROW, not a NULL
--   inside it. That is what makes PM's "never coalesce to 0" (Sec M-11)
--   enforceable AT THE READER rather than a convention: a reader that finds no
--   row has nothing to coalesce, whereas a reader that finds a row with a NULL
--   deduction is one `coalesce(x, 0)` away from silently deducting nothing.
--   ⚠ This is the OPPOSITE ruling to 090's cashflow_target, and the difference
--   is the write path, not a change of mind: cashflow_target carries two
--   INDEPENDENT scalars in one row, so clearing one must not delete the row and
--   NULL is its unset. Here the row and its brackets are one replace-all unit.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER on ALL THREE functions (default per
--   ADR-011 Lock 11); NOT SECURITY DEFINER, and the third one is the interesting
--   case. The two TRIGGER FENCES read tenant-scoped pfin tables and need no
--   elevated privilege: the explicit users_id equality in the #18 fence is
--   authoritative regardless of what RLS lets the caller see, and the set fence
--   is deliberately RLS-composed (see its sufficiency note above).
--   ⚠ fn_tax_bracket_schedule_replace_all IS INVOKER TOO, AND THAT IS THE WHOLE
--     DESIGN, NOT A DEFAULT LEFT UNEXAMINED. It is a directly-callable write
--     body reached from the app, which is exactly the shape that usually
--     acquires DEFINER. It must NOT: under INVOKER its very first statement —
--     the FOR UPDATE lock — runs under the caller's own RLS, so another tenant's
--     schedule_id resolves to ZERO ROWS and the function refuses. That refusal
--     IS the tenant fence. Under DEFINER the same SELECT would find every
--     tenant's row and the function would have to re-implement ownership
--     checking by hand, replacing a fence the database applies with one a
--     reviewer has to verify. The function also takes NO TENANT PARAMETER (R4
--     rider 4; Sec D-2): users_id comes from auth.uid(), never from an argument,
--     so there is nothing for a caller to forge.
--   The SECURITY DEFINER allowlist is UNCHANGED by this migration — read
--   ADR-011 Decision 9 live for its contents. Any DEFINER proposal on this
--   surface would route to Sec joint-review; none is made.
--   All three carry `set search_path = ''`, explicit VOLATILE, an explicit
--   `revoke execute ... from public`, and a `comment on function`.
--   ⚠ EXECUTE IS GRANTED TO `authenticated` ON THE REPLACE-ALL FUNCTION ONLY,
--     and withheld from BOTH TRIGGER FENCES. The split is not stylistic.
--     PostgreSQL does not check EXECUTE privilege on a trigger function when
--     firing a trigger — only on a direct call — so a grant on a fence would buy
--     it nothing and would hand `authenticated` a callable entry point that can
--     only ever error outside trigger context (074's fence sets that precedent).
--     The replace-all function is the opposite: a direct call IS its only use,
--     so without the grant the surface does not work at all. AC 9's requirement
--     is `revoke execute ... from public` BEFORE any grant, and that ordering is
--     what the file does in all three cases.
--     ⚠ For an INVOKER function EXECUTE is the weakest of the fences and RLS
--     still stands behind it; this is NOT the DEFINER case where the ACL would
--     be the entire perimeter.
--
-- ----------------------------------------------------------------------------
-- aal2 STEP-UP BACKSTOP (ADR-029 / 025; C3 standing obligation; R4 rider 3).
--   BOTH tables are new sensitive tenant-owned pfin tables, so BOTH inherit the
--   per-user-conditional backstop clause on EVERY authenticated policy — AND-ed
--   into the read USING and into the write WITH CHECK / USING. NEITHER is one of
--   025's named exclusions: neither is a global shared-read table, neither is a
--   service_role-only / default-deny table, and neither is the user_settings
--   substrate. ⚠ 025 names pfin.user_settings as a NON-NEGOTIABLE exclusion for
--   policy-recursion reasons (the clause's own subquery reads user_settings),
--   and THAT REASON DOES NOT GENERALIZE TO SIBLINGS. The clause below is copied
--   byte-faithfully from 025, inline and never via a helper (025 ratified inline
--   because `set search_path = ''` disables SQL-function inlining, so a helper
--   would evaluate per row).
--
-- DELETE POLICY — SHIPS WITH ITS OWN TENANT CLAUSE ON BOTH TABLES, NEVER
--   TRIMMED (SECURITY §4.6 "Lock-14 settings-family DELETE-policy fence"). No
--   DELETE policy in the Lock 14 family may be trimmed, weakened or omitted on
--   the reasoning that the SELECT policy already covers it: Postgres consults
--   the SELECT policy during a DELETE only when the statement reads or filters
--   by a column, so for an unqualified `delete from pfin.tax_bracket_row;` the
--   DELETE policy's own USING clause is the SOLE DB-layer fence. QA measured
--   that at 074 on 2026-08-20; the reasoning is confirmed false, not merely
--   unproven. ⚠ DELETE is load-bearing here rather than incidental — the
--   replace-all path deletes the schedule's rows before re-inserting them.
--
-- ----------------------------------------------------------------------------
-- THE REPLACE-ALL IS ONE FUNCTION, SERIALIZED BY A ROW LOCK — AND THE REASON IS
--   A TRANSPORT LIMIT, NOT A PREFERENCE (execution-log E8, 2026-09-03).
--   ADR-011 Decision 18 locks the schedule + its rows as a REPLACE-ALL UNDER
--   SERIALIZABLE. That phrase names a guarantee, and on this transport the
--   client cannot deliver it:
--     - PostgREST runs EACH .from() / .rpc() call as its OWN transaction and
--       cannot hold a client-side `BEGIN SERIALIZABLE` across several — the
--       limit `045`'s header already records for the webhook-apply pair, which
--       is why that surface also moved its atomic body into one function.
--     - `SET TRANSACTION ISOLATION LEVEL` CANNOT be issued inside a function
--       body: the calling statement has already taken its snapshot.
--   So the atomic body is ONE plpgsql function whose body is one transaction,
--   and the serialization comes from an explicit `FOR UPDATE` lock on the
--   caller's own schedule row rather than from the isolation level.
--
--   ⚠ WHAT THE LOCK IS FOR — MEASURED AT AUTHORING, AND IT IS NOT THE FAILURE
--     THE RULING ANTICIPATED. Execution-log E8 (2026-09-03) states the unlocked
--     hazard as the schedule ending as **A ∪ B**, T2's DELETE having missed T1's
--     freshly-inserted rows. That is the correct general account of a
--     delete-then-insert race under READ COMMITTED, and on THIS pair it does not
--     occur. The lock-struck body was run against a live two-session race at
--     authoring and produced two DIFFERENT failures:
--       (i) BOTH SETS NON-EMPTY -> T2 aborts with a DUPLICATE KEY violation on
--           `tax_bracket_row_schedule_id_bracket_floor_key`. A ∪ B is
--           UNREACHABLE here: leg A forces bracket_floor 0 into every non-empty
--           schedule, so any two non-empty sets collide at 0, and the unique key
--           turns the union into an error instead. T2's write is lost, and the
--           error names a constraint that has nothing to do with the real cause.
--      (ii) T2 SENDS AN EMPTY SET (clearing the schedule) -> no error at all,
--           and the schedule is left holding T1's rows. A SILENT LOST UPDATE:
--           the caller is told the clear succeeded and it did not. This is the
--           worse of the two, because nothing surfaces.
--     The FOR UPDATE removes both: T2 blocks until T1 commits, then its DELETE
--     sees T1's rows and removes them, and its own set lands whole.
--     ⚠ RECORDED THIS WAY DELIBERATELY. The lock is load-bearing either way and
--     E8's ruling stands unchanged — but a header asserting a failure mode this
--     schema cannot produce would send the paired battery hunting a union that
--     never appears, and neither real failure would be covered. The two
--     mechanisms are not interchangeable just because both argue for the lock.
--   ⚠ THE LOCK IS ALSO THE TENANT FENCE, which is why it is the FIRST statement.
--     It runs under the caller's own RLS (INVOKER), so another tenant's or an
--     absent schedule_id resolves to ZERO ROWS and the function RAISES. It never
--     creates a schedule: creation is an ordinary INSERT under RLS, and an empty
--     schedule is legal here (see the set fence's empty-set note).
--   ⚠ LOSING SIDE, named rather than omitted. True SERIALIZABLE would ALSO catch
--     write skew across DIFFERENT schedules of one user. Nothing on this surface
--     reads across schedules, so the lock's narrower guarantee covers every
--     hazard the surface actually has — but it is narrower, and a future reader
--     composing two schedules in one decision must re-open this. The rejected
--     alternative was setting `default_transaction_isolation` on the PostgREST
--     role: global, and untestable per surface.
--   ⚠ THIS DOES NOT RETIRE THE SET FENCE. SERIALIZABLE never guaranteed
--     monotonicity and neither does the lock (Sec D-5 / R4 rider 2): the lock
--     orders the writers, the set fence judges what they wrote. Independent
--     controls, and the deferred fence still fires at commit inside this body.
--
--   ⚠ `p_rows jsonb` IS A TRANSPORT PARAMETER AND IS NOT A BREACH OF DECISION
--     18's FORWARD-COMPAT FENCE. That fence bars *"no JSONB blobs in the
--     settings store"* — it governs STORAGE, and every value here lands in a
--     typed column (`bracket_floor numeric`, `bracket_rate numeric`) with its
--     own CHECKs. No JSONB is stored, no JSONB column exists on either table,
--     and nothing reads settings back out of a document. Stated explicitly
--     because a reader meeting `jsonb` in a Lock 14 surface should be able to
--     resolve the apparent conflict here rather than having to relitigate it.
--     The function validates the document's SHAPE precisely so that it cannot
--     become a de-facto blob: exactly two numeric keys per element, nothing
--     else admitted.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; the catalogued
--   list is NOT restated here and no count is carried, deliberately). Decision 4
--   was read VERBATIM AND LIVE from DECISIONS.md before drafting. This migration
--   introduces ZERO catalogued §10 instances: it is a Lock 14
--   user-facing-direct-DB-write surface, and class membership is not a
--   catalogued instance (ADR-042's ruling for the 058 fences). It touches no
--   infrastructure-credential-presence surface, no service_role-key /
--   code-layer allowlist surface, and no network-exposure/config surface.
--     (i)   Instance-numbering: unchanged — no catalogued instance is added,
--           reordered, or renumbered.
--     (ii)  Layer-attribution: unchanged — no catalogued instance's layer is
--           re-attributed, and no surface becomes "four-layer".
--     (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED RT set are DIFFERENT SETS and are
--     not reconciled here or anywhere. A Decision-3 label is allocated by this
--     migration (#18 above); that is the Decision 3 family, which is a DIFFERENT
--     enumeration again from both.
--
-- ----------------------------------------------------------------------------
-- SETTINGS ARE NOT AUDIT-CLASS (ADR-011 Decision 18, carried BY CITATION at R4
--   rather than restated): UPSERT-in-place with updated_at, no edit-history
--   rows, no versioned sibling. NO JSONB in the settings store, under this or
--   any future surface — typed named columns only. Read Decision 18's riders
--   live rather than from this line.
--
-- ----------------------------------------------------------------------------
-- Numbering: 101 follows 099 (100 and 102 are held by sibling branches of the
--   same milestone). Order-dependent — must run AFTER 001 (pfin schema +
--   fn_refresh_updated_at), AFTER 024 (pfin.user_settings, which the aal2 clause
--   reads) and AFTER 025 (which authored the clause). SELF-260's bracket seed
--   and SELF-262's fn_compute_tax_liability both depend on this landing first.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.tax_schedule_type_enum — 'federal_ordinary' | 'federal_lt_cg' |
--     'california_ordinary'. The FIRST enum type in this schema; every prior
--     migration used text + CHECK or a lookup table.
--
--   pfin.tax_bracket_schedule — one row per (users_id, tax_year, schedule_type),
--     which is the unique key and the ON CONFLICT target for the UPSERT.
--     tax_year smallint NOT NULL, CHECK (tax_year >= 1913) — named
--       tax_bracket_schedule_tax_year_check. 1913 is the first US federal
--       income-tax year, so the bound refuses a transposed or zero year while
--       refusing no real one; the smallint's own ceiling carries the upper end.
--     standard_deduction     numeric(20,4) NOT NULL, >= 0, non-NaN.
--     tax_balance_prior_year numeric(20,4) NULL — INFORMATIONAL ONLY; MUST NOT
--       enter the computation. NULL renders as an em dash.
--     users_id — DEFAULT auth.uid(), load-bearing: it lets an authenticated
--       INSERT omit the column and still satisfy the INSERT policy's WITH CHECK.
--       The write path MUST derive the tenant from the session, never from the
--       request body (Lock 14 mod #1; R4 rider 4).
--     Trigger: BEFORE UPDATE FOR EACH ROW -> pfin.fn_refresh_updated_at() (001).
--
--   pfin.tax_bracket_row — one row per bracket; unique (schedule_id,
--     bracket_floor).
--     users_id     — the child's OWN tenant fact (grain C). Same DEFAULT and
--                    same Lock 14 mod #1 obligation as the parent's.
--     schedule_id  — Decision 3 canonical #18. Declared FK, ON DELETE CASCADE.
--     bracket_floor numeric(20,4) NOT NULL, >= 0, non-NaN — the bracket's
--                    LOWER-BOUND threshold. Upper bound is implicit: the next
--                    row's floor, or unbounded for the top bracket. There is no
--                    ceiling column and none is owed.
--     bracket_rate  numeric(12,8) NOT NULL, 0 <= rate <= 1, non-NaN — a
--                    FRACTION (0.22 means 22%). See the unit ruling above.
--     Fence 1: BEFORE INSERT OR UPDATE FOR EACH ROW ->
--              pfin.fn_tax_bracket_row_matched_schedule() (Decision 3 #18).
--     Fence 2: CONSTRAINT TRIGGER AFTER INSERT OR UPDATE OR DELETE, DEFERRABLE
--              INITIALLY DEFERRED, FOR EACH ROW ->
--              pfin.fn_tax_bracket_row_schedule_invariants() (legs A + B).
--
--   RLS on both: SELECT / INSERT / UPDATE / DELETE, each `users_id = auth.uid()`
--     AND the 025 aal2 clause. The CHILD's predicate is a DIRECT users_id
--     equality, NOT a join to its schedule — under grain (C) the child holds its
--     own tenant fact, and the join form the drafted (A) grain implied is
--     superseded. Grants: authenticated only; anon zero-grant; service_role
--     ungranted (008 grants per table and establishes no default privileges, so
--     this records that rather than effecting it).
--
--   pfin.fn_tax_bracket_schedule_replace_all(p_schedule_id bigint,
--     p_tax_year smallint, p_schedule_type pfin.tax_schedule_type_enum,
--     p_standard_deduction numeric, p_tax_balance_prior_year numeric,
--     p_rows jsonb) returns void — the atomic replace-all write body.
--     SECURITY INVOKER, set search_path = '', VOLATILE, EXECUTE revoked from
--     PUBLIC and granted to authenticated. NO TENANT PARAMETER: users_id comes
--     from auth.uid() (R4 rider 4; Sec D-2).
--     Order is load-bearing: (1) FOR UPDATE lock on the caller's own schedule
--     row — zero rows RAISES, and that refusal is the tenant fence; (2) validate
--     p_rows' shape; (3) DELETE the schedule's rows; (4) INSERT the new set;
--     (5) UPDATE the three scalars, which fires the updated_at trigger. The
--     deferred set fence and the #18 matched-tenant fence fire at COMMIT, after
--     the function returns.
--     p_rows: a JSON ARRAY of OBJECTS each carrying EXACTLY the keys
--     bracket_floor and bracket_rate, both JSON numbers. An empty array is
--     legal and clears the schedule. Anything else RAISES.
-- ============================================================================

create schema if not exists pfin;
grant usage on schema pfin to authenticated;

-- ----------------------------------------------------------------------------
-- ENUM — `create type` has NO `if not exists` form (noted at 064), so the
-- idempotence this file's `create table if not exists` statements get for free
-- is written out explicitly here.
-- ----------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1
      from pg_type t
      join pg_namespace n on n.oid = t.typnamespace
     where n.nspname = 'pfin'
       and t.typname = 'tax_schedule_type_enum'
  ) then
    create type pfin.tax_schedule_type_enum as enum (
      'federal_ordinary',
      'federal_lt_cg',
      'california_ordinary'
    );
  end if;
end
$$;

comment on type pfin.tax_schedule_type_enum is
  'The jurisdiction-and-character key of a tax bracket schedule (PRD §2.5.2; '
  'SELF-259). federal_ordinary = the US federal ordinary-income table; '
  'federal_lt_cg = the US federal long-term capital-gains table (PRD §2.5.2 (λ)); '
  'california_ordinary = the California FTB ordinary-income table (PRD §2.5.2 '
  '(κ)). An enum rather than text + CHECK because the value is a closed '
  'vocabulary read by name at three separate call sites, and a typo must be a '
  'type error rather than a row that silently matches nothing. Adding a '
  'jurisdiction is an ALTER TYPE ... ADD VALUE in its own migration, which is '
  'the intended growth path; removing one is not, and a schedule_type that '
  'stops being offered stays in the type so existing rows remain readable.';

-- ============================================================================
-- PARENT TABLE — pfin.tax_bracket_schedule
-- ============================================================================
create table if not exists pfin.tax_bracket_schedule (
  id                      bigint generated always as identity primary key,
  users_id                uuid not null default auth.uid()
                            references auth.users (id) on delete cascade,
  tax_year                smallint not null
                            constraint tax_bracket_schedule_tax_year_check
                            check (tax_year >= 1913),
  schedule_type           pfin.tax_schedule_type_enum not null,
  standard_deduction      numeric(20, 4) not null
                            check (standard_deduction >= 0
                                   and standard_deduction <> 'NaN'::numeric),
  tax_balance_prior_year  numeric(20, 4)
                            check (tax_balance_prior_year is null
                                   or tax_balance_prior_year <> 'NaN'::numeric),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  unique (users_id, tax_year, schedule_type)
);

comment on table pfin.tax_bracket_schedule is
  'Per-user, per-tax-year, per-jurisdiction tax bracket schedule (PRD §2.5.2; '
  'ADR-011 Decision 18 / Lock 14 per-domain settings store; SELF-259). The '
  'PARENT of pfin.tax_bracket_row, which holds the individual brackets. '
  'unique (users_id, tax_year, schedule_type) is the ON CONFLICT target for the '
  'UPSERT write path. STORAGE GRAIN (C), ruled by F/CTO at the V1.4 pre-flight '
  'sitting R4: two tables, with the CHILD carrying its own users_id beside '
  'schedule_id, so the two tenant facts CAN disagree and the matched-tenant '
  'fence on the child is a fence that can fail. WRITE SEMANTICS: the schedule '
  'and its rows are replaced as ONE unit under SERIALIZABLE isolation, so the '
  'unset state of a schedule is the ABSENCE OF THIS ROW, never a NULL inside '
  'it — which is what lets a reader refuse to coalesce a missing standard '
  'deduction to zero. Settings are not audit-class (Decision 18): '
  'UPSERT-in-place with updated_at, no edit-history rows. No JSONB, per '
  'Decision 18''s forward-compat fence. MUTABLE, full authenticated CRUD, RLS '
  'direct-owner (users_id = auth.uid()) with the ADR-029 / 025 aal2 step-up '
  'clause on every policy, the DELETE policy included and never trimmed '
  '(SECURITY §4.6 Lock-14 settings-family DELETE-policy fence). Carries NO '
  'ADR-011 Decision 3 instance: users_id is this table''s tenant anchor, not a '
  'cross-tenant reference, and no other FK-shaped column exists on it. anon '
  'zero-grant; service_role ungranted (the app writes as the user, under the '
  'user''s own JWT).';

comment on column pfin.tax_bracket_schedule.users_id is
  'SOLE tenant anchor of this table (users_id = auth.uid()). DEFAULT auth.uid() '
  'so an authenticated INSERT that omits it lands owned and satisfies the INSERT '
  'policy''s WITH CHECK; FK -> auth.users(id) ON DELETE CASCADE with the tenant. '
  'NOT a cross-tenant reference (it IS the anchor) -> ADR-011 Decision 3 does '
  'not apply to this column. The write path MUST derive this from the session '
  '(auth.uid()), never from the request body (Lock 14 mod #1): a schedule id '
  'arriving in a request URL is a client-supplied object reference and therefore '
  'an IDOR surface, and the replace-all endpoint is scoped to the caller''s own '
  'schedule or refuses.';

comment on column pfin.tax_bracket_schedule.tax_year is
  'The tax year this schedule states, as a smallint (ADR-011 Decision 18 rider, '
  'carried by citation at the V1.4 sitting R4). Part of the unique key, so one '
  'user holds at most one schedule of each type per year and a new year is a new '
  'row rather than an edit — brackets are re-entered at rollover, they are not '
  'migrated. CHECK (tax_year >= 1913), named '
  'tax_bracket_schedule_tax_year_check: 1913 is the first US federal income-tax '
  'year, so the bound refuses a transposed or zero year while refusing no real '
  'one. The smallint''s own ceiling carries the upper end; no upper CHECK is '
  'invented, because a future tax year is a legitimate entry.';

comment on column pfin.tax_bracket_schedule.schedule_type is
  'Which published table this row states — see the type comment on '
  'pfin.tax_schedule_type_enum for the vocabulary. Part of the unique key: the '
  'three schedule types are independent facts and a user may hold any subset of '
  'them for a given year.';

comment on column pfin.tax_bracket_schedule.standard_deduction is
  'The standard deduction for this jurisdiction and tax year, in account '
  'currency. NOT NULL, DELIBERATELY: the schedule and its rows are written as '
  'one replace-all unit, so the unset state is the ABSENCE OF THIS ROW, not a '
  'NULL inside it. A reader that finds no schedule has nothing to coalesce; a '
  'reader that found a row with a NULL deduction would be one coalesce(x, 0) '
  'away from silently deducting nothing. MUST NOT be coalesced to 0 by any '
  'reader. numeric(20,4). THE CHECK IS TWO-SIDED FOR A REASON THAT IS NOT '
  'RANGE-CHECKING: the typmod refuses ±Infinity at coercion (a numeric(20,4) '
  'field cannot hold an infinite value, measured at 014), so the non-finite '
  'value that still reaches a CHECK is NaN — which IS storable in a constrained '
  'numeric and sorts ABOVE every non-NaN numeric, so a one-sided `>= 0` would '
  'ADMIT IT. The explicit `<> ''NaN''::numeric` literal (the 014 / 053 / 090 '
  'idiom) is what refuses it. No upper bound: a deduction has no natural '
  'ceiling. DB half of the Lock 14 mod #2 numeric-input discipline; does not '
  'replace the app-layer adversarial battery, which remains the first line.';

comment on column pfin.tax_bracket_schedule.tax_balance_prior_year is
  'INFORMATIONAL ONLY. The prior year''s closing tax balance for this '
  'jurisdiction, entered at rollover on the brackets'' own cadence and rendered '
  'as an em dash when unset (PRD §2.5.3). ⚠ THIS VALUE MUST NOT ENTER THE '
  'ESTIMATED-TAX COMPUTATION under the μ-2 lock. It is displayed beside the '
  'computed figures and is not one of them. Stated as a standing requirement '
  'because a nullable numeric sitting beside the standard deduction is one '
  'coalesce away from being summed into it. NULL means not entered, and is the '
  'only unset representation. numeric(20,4), NULLABLE. CARRIES NO SIGN BOUND, '
  'deliberately: a prior-year balance can be an OVERPAYMENT and is then '
  'legitimately negative, so a `>= 0` CHECK would refuse a real state. It does '
  'carry the explicit `<> ''NaN''::numeric` literal, and its typmod refuses '
  '±Infinity at coercion — neither of those is ever a balance.';

-- ============================================================================
-- CHILD TABLE — pfin.tax_bracket_row
-- ============================================================================
create table if not exists pfin.tax_bracket_row (
  id             bigint generated always as identity primary key,
  users_id       uuid not null default auth.uid()
                   references auth.users (id) on delete cascade,
  schedule_id    bigint not null
                   references pfin.tax_bracket_schedule (id) on delete cascade,
  bracket_floor  numeric(20, 4) not null
                   check (bracket_floor >= 0
                          and bracket_floor <> 'NaN'::numeric),
  bracket_rate   numeric(12, 8) not null
                   check (bracket_rate >= 0
                          and bracket_rate <= 1
                          and bracket_rate <> 'NaN'::numeric),
  created_at     timestamptz not null default now(),
  unique (schedule_id, bracket_floor)
);

comment on table pfin.tax_bracket_row is
  'One marginal tax bracket of one pfin.tax_bracket_schedule (PRD §2.5.2; '
  'ADR-011 Decision 18 / Lock 14; SELF-259). STORAGE GRAIN (C), ruled by F/CTO '
  'at the V1.4 pre-flight sitting R4: this row carries ITS OWN users_id BESIDE '
  'schedule_id, so TWO TENANT FACTS EXIST ON IT AND THEY CAN DISAGREE. That is '
  'the point of the grain — it is what makes the matched-tenant fence on '
  'schedule_id (ADR-011 Decision 3 canonical instance #18, P1 local anchor, '
  'fn_tax_bracket_row_matched_schedule) a fence that CAN FAIL. Under the '
  'rejected grain (A) the row would not be a Decision-3 member at all and the '
  'fence would be a leg that cannot fail. RLS is therefore a DIRECT '
  'users_id = auth.uid() equality, not a join to the parent schedule. TWO SET '
  'PROPERTIES are carried by a DEFERRED CONSTRAINT TRIGGER '
  '(fn_tax_bracket_row_schedule_invariants) rather than by a per-row check, '
  'because a BEFORE ROW trigger cannot see later rows of the same statement and '
  'the replace-all path writes the whole schedule in one multi-row INSERT: '
  '(A) the lowest bracket_floor of a non-empty schedule MUST be 0, and (B) '
  'bracket_rate MUST be non-decreasing in ascending bracket_floor order. Floor '
  'ORDERING is not among them: unique (schedule_id, bracket_floor) already makes '
  'the floors pairwise distinct and any distinct numeric set is totally ordered, '
  'so a floor-ordering leg could never fire and is deliberately not written. '
  'WRITE SEMANTICS: replace-all under SERIALIZABLE — the schedule''s rows are '
  'deleted and re-inserted as one unit, which is why DELETE is granted and '
  'fenced. SERIALIZABLE and the set fence are INDEPENDENT controls and neither '
  'substitutes for the other. Settings are not audit-class (Decision 18). '
  'MUTABLE, full authenticated CRUD, RLS direct-owner with the ADR-029 / 025 '
  'aal2 step-up clause on every policy, the DELETE policy included and never '
  'trimmed (SECURITY §4.6). anon zero-grant; service_role ungranted.';

comment on column pfin.tax_bracket_row.users_id is
  'THE CHILD''S OWN TENANT FACT — grain (C), ruled at the V1.4 pre-flight '
  'sitting R4. It sits BESIDE schedule_id rather than instead of it, so this '
  'row carries two tenant facts that CAN disagree, and '
  'fn_tax_bracket_row_matched_schedule asserts their agreement. NOT a '
  'cross-tenant reference (it IS this table''s local anchor) -> ADR-011 '
  'Decision 3 does not apply to this column; it is what makes the fence on '
  'schedule_id a P1 LOCAL-ANCHOR instance rather than a chain-resolved one. '
  'DEFAULT auth.uid() so an authenticated INSERT that omits it lands owned and '
  'satisfies the INSERT policy''s WITH CHECK; FK -> auth.users(id) ON DELETE '
  'CASCADE. The write path MUST derive this from the session, never from the '
  'request body (Lock 14 mod #1).';

comment on column pfin.tax_bracket_row.schedule_id is
  'ADR-011 DECISION 3 CANONICAL INSTANCE #18 — the FK-shaped reference this '
  'table''s matched-tenant fence exists for. Fence pattern P1 (matched-tenant, '
  'LOCAL ANCHOR — the 012 shape): pfin.fn_tax_bracket_row_matched_schedule(), '
  'BEFORE INSERT OR UPDATE, SECURITY INVOKER, set search_path = '''', NULL-safe '
  'fail-closed. BEFORE INSERT **OR UPDATE** because this table is mutable '
  'settings data (the 012 / 022 / 074 shape, not the 019 / 044 / 057 '
  'immutable-audit INSERT-only shape) — an INSERT-only fence would leave the '
  'repoint path open. ⚠ A PostgreSQL FOREIGN KEY IS SILENT ON RLS: it validates '
  'that the referenced row EXISTS, never that it is within the referring '
  'tenant''s isolation scope. That is this Decision''s entire premise, and it is '
  'why the declared FK below does not discharge the fence. Declared as '
  'references pfin.tax_bracket_schedule (id) ON DELETE CASCADE — cascade rather '
  'than 074''s restrict, because a bracket has no meaning without its schedule '
  'and orphaning one would leave an unreadable row rather than surface a '
  'problem. Read ADR-011 Decision 3 LIVE for the family''s current shape; this '
  'comment carries no tally, deliberately.';

comment on column pfin.tax_bracket_row.bracket_floor is
  'The bracket''s LOWER-BOUND threshold, in account currency: income at or above '
  'this amount (and below the next row''s floor) is taxed at bracket_rate. There '
  'is deliberately NO ceiling column — the upper bound is the next row''s floor, '
  'or unbounded for the top bracket, and storing both ends would let them '
  'disagree. THE LOWEST FLOOR OF A NON-EMPTY SCHEDULE MUST BE 0, enforced by the '
  'deferred constraint trigger fn_tax_bracket_row_schedule_invariants and NOT by '
  'monotonicity, which cannot see it: a schedule whose lowest floor is 11000 is '
  'perfectly monotone and silently taxes the first $11,000 at zero. '
  'unique (schedule_id, bracket_floor) makes the floors of one schedule pairwise '
  'distinct. numeric(20,4). THE CHECK IS TWO-SIDED FOR A REASON THAT IS NOT '
  'RANGE-CHECKING: the typmod refuses ±Infinity at coercion (measured at 014), '
  'so the non-finite value that still reaches a CHECK is NaN — storable in a '
  'constrained numeric and sorting ABOVE every non-NaN numeric, so a one-sided '
  '`>= 0` would ADMIT IT; the explicit `<> ''NaN''::numeric` literal (the 014 / '
  '053 / 090 idiom) is what refuses it.';

comment on column pfin.tax_bracket_row.bracket_rate is
  'The marginal tax rate applied between this row''s bracket_floor and the next '
  'row''s. ⚠ THE UNIT IS A FRACTION, NOT A PERCENT: 0.22 MEANS TWENTY-TWO '
  'PERCENT. Stated in words because a unit that lives only in the seed data is a '
  'unit the next writer gets wrong (Sec M-7). The domain CHECK bounds it '
  '0 <= rate <= 1, which follows from that unit and is what makes the common '
  'mis-entry — typing the published percent, 22, for twenty-two percent — fail '
  'LOUDLY at write time rather than silently multiplying every liability by 22. '
  'The presentation layer owes the x100 for display. Ruled FRACTION over PERCENT '
  'at this migration because the estimated-tax arithmetic MULTIPLIES by this '
  'value: a fraction multiplies directly, while a percent needs a /100 at every '
  'call site and a unit that must be divided out is a unit some call site will '
  'forget. RATE MUST BE NON-DECREASING in ascending bracket_floor order across a '
  'schedule, enforced by the deferred constraint trigger '
  'fn_tax_bracket_row_schedule_invariants — a set property no per-row check and '
  'no unique constraint can observe. numeric(12,8), a typmod deliberately looser '
  'than the domain needs so that a mis-typed 22 coerces and is refused by the '
  'domain CHECK, which can explain itself, rather than by a numeric-overflow '
  'error, which cannot. The typmod refuses ±Infinity at coercion and the '
  'explicit `<> ''NaN''::numeric` literal refuses NaN, which a one-sided bound '
  'would admit.';

-- ----------------------------------------------------------------------------
-- INDEX — the child's RLS predicate is a DIRECT users_id equality, and the
-- unique (schedule_id, bracket_floor) btree does NOT lead with users_id, so it
-- cannot serve that predicate. This index does. ⚠ This is a DEPARTURE from
-- 090 / 074's "no separate users_id index" note, and the reason is exactly that
-- their unique keys lead with users_id and this one does not. schedule_id needs
-- no index of its own: the unique above leads with it, which serves both the FK
-- and the set fence's per-schedule read.
-- ----------------------------------------------------------------------------
create index if not exists tax_bracket_row_users_id_idx
  on pfin.tax_bracket_row (users_id);

-- ============================================================================
-- FENCE 1 — ADR-011 DECISION 3 CANONICAL #18: matched-tenant on schedule_id.
--
-- P1, local anchor (the 012 shape): the referring row carries its own users_id,
-- and the fence asserts it equals the referenced schedule's. BEFORE INSERT OR
-- UPDATE, SECURITY INVOKER, set search_path = '', NULL-safe fail-closed.
--
-- TWO DISTINCT FAILURE LEGS, deliberately not collapsed into one NOT EXISTS:
-- the diagnostics differ, and so does WHO can reach them.
--   (1) UNRESOLVABLE — the schedule row does not exist, or RLS does not let this
--       caller see it. Under `authenticated`, naming ANOTHER TENANT's
--       schedule_id lands HERE, not on leg (2), because tax_bracket_schedule's
--       SELECT policy filters it away before this read can see it. A caller
--       whose mfa_policy is totp/passkey but whose JWT is below aal2 also lands
--       here on their OWN schedule — the 025 clause is AND-ed into that same
--       SELECT policy. That is fail-closed and correct, but it means leg 1 is
--       not by itself evidence of a bad schedule_id.
--   (2) CROSS-TENANT — the row resolved and its users_id differs. Reachable by
--       TWO distinct writers, and stating only the second under-states the leg:
--         (a) a PLAIN `authenticated` caller performing an OWNERSHIP FORGE —
--             their OWN real schedule_id submitted with a foreign users_id. The
--             row resolves (they own it), the forged new.users_id does not
--             match, leg 2 raises, and it does so BEFORE RLS's WITH CHECK is
--             reached, because a BEFORE trigger precedes WITH CHECK evaluation.
--             This is the shape 022's fence exercises for canonical #8 and
--             074's for #17, this instance's structural twins.
--         (b) a writer that is RLS-EXEMPT (the migration role, a superuser, any
--             future service_role path) — ADR-042 Decision 5a's rationale for
--             #16: the fence earns its keep against the writer no policy
--             catches. ⚠ For such a writer this trigger is the ONLY applicable
--             layer, so under session_replication_role = 'replica' the layer
--             count for it goes to ZERO, not to one (ADR-011 Decision 4's
--             2026-09-03 amendment) — and the FK goes inert in the same
--             statement, because referential integrity is itself internal
--             triggers. That GUC is superuser-context and denied to both
--             authenticated and service_role, so this is an OPERATIONAL bound,
--             not a tenant-reachable one: a restore or bulk-load path that sets
--             it owes an explicit post-load validation of this pair.
--       ⚠ Recording (a) matters in a specific direction: claiming (b) is the
--       only route under-states the fence and points a battery away from the
--       route an actual attacker has. ADR-042 and ADR-056 each record that
--       overclaim being corrected; it is not inherited here.
-- ============================================================================
create or replace function pfin.fn_tax_bracket_row_matched_schedule()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_users_id uuid;
begin
  -- NULL-SAFE FAIL-CLOSED: resolve first, then test. NEVER
  -- `(subquery) <> new.users_id` — that yields NULL on a missing row, the IF is
  -- skipped, and the write leaks through.
  select s.users_id
    into v_users_id
    from pfin.tax_bracket_schedule s
   where s.id = new.schedule_id;

  if not found then
    raise exception
      'tax bracket row rejected: schedule_id % does not resolve to a tax_bracket_schedule row readable by users_id % (ADR-011 Decision 3 canonical instance #18 / matched-tenant fence, leg 1 unresolvable)',
      new.schedule_id, new.users_id;
  end if;

  if v_users_id is distinct from new.users_id then
    raise exception
      'cross-tenant tax bracket row rejected: schedule_id % is owned by another tenant, not by users_id % (ADR-011 Decision 3 canonical instance #18 / matched-tenant fence, leg 2 cross-tenant)',
      new.schedule_id, new.users_id;
  end if;

  return new;
end;
$$;

revoke execute on function pfin.fn_tax_bracket_row_matched_schedule() from public;

comment on function pfin.fn_tax_bracket_row_matched_schedule() is
  'BEFORE INSERT OR UPDATE matched-tenant fence on '
  'pfin.tax_bracket_row.schedule_id — ADR-011 Decision 3 CANONICAL INSTANCE '
  '#18, fence pattern P1 (matched-tenant, LOCAL ANCHOR; the 012 shape). '
  'Asserts that the referenced pfin.tax_bracket_schedule row''s users_id equals '
  'the referring row''s OWN users_id. ⚠ A PostgreSQL FOREIGN KEY validates that '
  'the referenced row EXISTS and is SILENT ON RLS — it never validates that the '
  'row is within the referring tenant''s isolation scope — which is this '
  'Decision''s entire premise and why the declared FK does not discharge this '
  'fence. Two legs, deliberately not collapsed: leg 1 UNRESOLVABLE (no such row, '
  'or RLS hides it — where another tenant''s schedule_id lands, and where a '
  'totp/passkey caller below aal2 lands on their own), leg 2 CROSS-TENANT (the '
  'row resolved and its owner differs). Leg 2 is reachable BOTH by a plain '
  'authenticated caller performing an ownership forge — their own real '
  'schedule_id with a foreign users_id, which raises BEFORE RLS''s WITH CHECK is '
  'reached — AND by an RLS-exempt writer. Naming only the second would '
  'under-state the fence and point a battery away from the route a real caller '
  'has. BEFORE INSERT OR UPDATE, not INSERT-only: this table is mutable settings '
  'data, so an INSERT-only fence would leave the repoint path open. SECURITY '
  'INVOKER + set search_path = '''' — the read composes with RLS, and the '
  'explicit users_id equality is authoritative regardless of what RLS lets the '
  'caller see. Trigger rather than a bare CHECK because it subqueries the '
  'referenced row, which PostgreSQL cannot express declaratively. NULL-safe '
  'fail-closed: the referenced row is resolved into a local and then tested, '
  'never compared inside a subquery expression that returns NULL on a miss. '
  'INVOKER: adds no SECURITY DEFINER allowlist entry.';

create trigger tax_bracket_row_matched_schedule
  before insert or update on pfin.tax_bracket_row
  for each row
  execute function pfin.fn_tax_bracket_row_matched_schedule();

-- ============================================================================
-- FENCE 2 — the TWO SET PROPERTIES of a schedule's bracket rows.
--
-- Carried by a DEFERRED CONSTRAINT TRIGGER because a BEFORE ROW trigger CANNOT
-- OBSERVE EITHER: it fires before the row is visible and before the later rows
-- of the same statement exist, so a per-row fence evaluates each row against an
-- incomplete set and passes a collectively-invalid multi-row INSERT — which is
-- exactly what the replace-all path sends. Evaluating at COMMIT is what makes
-- the whole set visible. `create constraint trigger` requires `for each row`
-- (a statement-level trigger cannot be declared deferrable), so this function
-- re-reads the schedule's set on each firing; for a schedule of a handful of
-- brackets that is the right trade, and it is stated so the row-level
-- declaration is not misread as a row-level check.
--
--   LEG A — ZERO FLOOR. The lowest bracket_floor of a NON-EMPTY schedule must be
--     exactly 0. Monotonicity cannot catch this. An EMPTY schedule PASSES: the
--     replace-all path deletes then re-inserts inside one transaction, and a
--     cleared-but-not-yet-repopulated schedule is the ABSENCE of brackets, not
--     a malformed set — the same absence-is-unset semantics the parent's
--     standard_deduction rests on.
--   LEG B — RATE MONOTONICITY. In ascending bracket_floor order, bracket_rate
--     must be NON-DECREASING. ⚠ The FLOOR ordering is NOT checked and that is
--     deliberate: unique (schedule_id, bracket_floor) already makes the floors
--     pairwise distinct, and any distinct numeric set is totally ordered, so a
--     floor-ordering leg COULD NEVER FIRE. Shipping it would be a control over a
--     guaranteed property — it turns a future regression into an outage instead
--     of a rejection, and it reads to a reviewer as a live guarantee. The
--     falsifiable set property is the PAIRING: (0, 0.10) with (11000, 0.05) is a
--     genuinely non-monotone schedule that no unique constraint and no per-row
--     check can see. NON-DECREASING rather than strictly increasing: two
--     adjacent brackets at one rate are unusual but not malformed.
--     ⚠ This leg COMMITS the pair to PROGRESSIVE schedules. All three V1
--     schedule types are progressive; a regressive one would be refused and
--     would need this leg amended.
--
-- ⚠ SUFFICIENCY. SECURITY INVOKER, so the set read composes with RLS. The claim
--   to see "the whole set" therefore rests on every row of one schedule
--   belonging to one tenant — which is what fence 1 (#18) enforces. The two
--   fences are NOT independent: strike #18 and this one silently narrows.
-- ⚠ SERIALIZABLE is NOT a substitute for this fence and this fence is not a
--   substitute for SERIALIZABLE (Sec D-5 / R4 rider 2): SERIALIZABLE guarantees
--   equivalence to SOME serial order and says nothing about whether one
--   transaction leaves the rows monotone.
-- ============================================================================
create or replace function pfin.fn_tax_bracket_row_schedule_invariants()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_schedule_id  bigint;
  v_row_count    bigint;
  v_min_floor    numeric;
  v_bad_floor    numeric;
  v_bad_rate     numeric;
  v_prev_rate    numeric;
begin
  -- DELETE has no NEW; INSERT/UPDATE have no OLD on the row that matters here.
  -- Resolve the schedule under scrutiny from whichever record exists.
  if tg_op = 'DELETE' then
    v_schedule_id := old.schedule_id;
  else
    v_schedule_id := new.schedule_id;
  end if;

  select count(*), min(r.bracket_floor)
    into v_row_count, v_min_floor
    from pfin.tax_bracket_row r
   where r.schedule_id = v_schedule_id;

  -- An empty schedule is the ABSENCE of brackets, not a malformed set.
  if v_row_count = 0 then
    return null;
  end if;

  -- LEG A — the lowest floor of a non-empty schedule must be exactly zero.
  if v_min_floor is distinct from 0 then
    raise exception
      'tax bracket schedule % rejected: its lowest bracket_floor is %, not 0 — a schedule that does not start at zero silently taxes the first % of income at no rate, and monotonicity cannot observe that (SELF-259 set fence, leg A zero-floor)',
      v_schedule_id, v_min_floor, v_min_floor;
  end if;

  -- LEG B — rate must be non-decreasing in ascending floor order.
  select f.bracket_floor, f.bracket_rate, f.prev_rate
    into v_bad_floor, v_bad_rate, v_prev_rate
    from (
      select r.bracket_floor,
             r.bracket_rate,
             lag(r.bracket_rate) over (order by r.bracket_floor) as prev_rate
        from pfin.tax_bracket_row r
       where r.schedule_id = v_schedule_id
    ) f
   where f.prev_rate is not null
     and f.bracket_rate < f.prev_rate
   order by f.bracket_floor
   limit 1;

  if found then
    raise exception
      'tax bracket schedule % rejected: the bracket at floor % carries rate %, below the preceding bracket''s rate % — bracket_rate must be non-decreasing in ascending bracket_floor order (SELF-259 set fence, leg B rate monotonicity)',
      v_schedule_id, v_bad_floor, v_bad_rate, v_prev_rate;
  end if;

  return null;
end;
$$;

revoke execute on function pfin.fn_tax_bracket_row_schedule_invariants() from public;

comment on function pfin.fn_tax_bracket_row_schedule_invariants() is
  'DEFERRED CONSTRAINT TRIGGER function carrying the TWO SET PROPERTIES of a '
  'pfin.tax_bracket_schedule''s bracket rows (SELF-259; V1.4 pre-flight sitting '
  'R4 riders 1 and 8). LEG A: the lowest bracket_floor of a non-empty schedule '
  'MUST be exactly 0 — a schedule whose lowest floor is 11000 is perfectly '
  'monotone and silently taxes the first $11,000 at no rate, so this is a '
  'different property from ordering and needs its own control. An EMPTY schedule '
  'passes, deliberately: replace-all deletes then re-inserts in one transaction, '
  'and a cleared schedule is the absence of brackets, not a malformed set. '
  'LEG B: bracket_rate MUST be non-decreasing in ascending bracket_floor order. '
  '⚠ FLOOR ordering is deliberately NOT a leg — unique (schedule_id, '
  'bracket_floor) makes the floors pairwise distinct and any distinct numeric '
  'set is totally ordered, so such a leg could never fire, and a control over a '
  'guaranteed property turns a future regression into an outage while reading to '
  'a reviewer as a live guarantee. ⚠ WHY DEFERRED AND NOT BEFORE ROW: a BEFORE '
  'ROW trigger fires before its row is visible and before the later rows of the '
  'same statement exist, so it evaluates each row against an incomplete set and '
  'PASSES a collectively-invalid multi-row INSERT — which is exactly the shape '
  'the replace-all path sends. Evaluating at COMMIT is what makes the set '
  'visible. FOR EACH ROW is forced: create constraint trigger admits no '
  'statement-level form, so the whole set is re-read per firing. ⚠ SERIALIZABLE '
  'is NOT a substitute for this and this is not a substitute for SERIALIZABLE — '
  'SERIALIZABLE guarantees equivalence to some serial order and says nothing '
  'about whether a transaction leaves the rows monotone. ⚠ SECURITY INVOKER, so '
  'the set read composes with RLS: this function''s claim to see the whole set '
  'rests on every row of one schedule belonging to one tenant, which is what '
  'fn_tax_bracket_row_matched_schedule (ADR-011 Decision 3 #18) enforces — the '
  'two fences are not independent. set search_path = ''''. INVOKER: adds no '
  'SECURITY DEFINER allowlist entry.';

create constraint trigger tax_bracket_row_schedule_invariants
  after insert or update or delete on pfin.tax_bracket_row
  deferrable initially deferred
  for each row
  execute function pfin.fn_tax_bracket_row_schedule_invariants();

-- ============================================================================
-- RLS — owner-only on all four verbs, on BOTH tables. Each policy is
-- `(users_id = auth.uid()) and (<025 aal2 backstop clause>)`, the clause copied
-- byte-faithfully from 025 (COALESCE null-safe, inline — never a helper: 025
-- ratified inline because `set search_path = ''` disables SQL-function
-- inlining, so a helper would evaluate per row).
-- ⚠ The CHILD's predicate is a DIRECT users_id equality, NOT a join to its
-- schedule: under grain (C) the child holds its own tenant fact, and the join
-- form the drafted (A) grain implied is superseded.
-- ============================================================================
alter table pfin.tax_bracket_schedule enable row level security;
alter table pfin.tax_bracket_row      enable row level security;

create policy tax_bracket_schedule_select on pfin.tax_bracket_schedule
  for select to authenticated
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

create policy tax_bracket_schedule_insert on pfin.tax_bracket_schedule
  for insert to authenticated
  with check (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

create policy tax_bracket_schedule_update on pfin.tax_bracket_schedule
  for update to authenticated
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  )
  with check (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

-- The DELETE policy carries its OWN tenant clause and is never trimmed on the
-- reasoning that tax_bracket_schedule_select covers it — that reasoning is
-- confirmed false (SECURITY §4.6; QA-measured at 074, 2026-08-20). For a
-- statement with no column reference the SELECT policy is not consulted at all,
-- and this USING clause is the sole DB-layer fence.
create policy tax_bracket_schedule_delete on pfin.tax_bracket_schedule
  for delete to authenticated
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

create policy tax_bracket_row_select on pfin.tax_bracket_row
  for select to authenticated
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

create policy tax_bracket_row_insert on pfin.tax_bracket_row
  for insert to authenticated
  with check (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

create policy tax_bracket_row_update on pfin.tax_bracket_row
  for update to authenticated
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  )
  with check (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

-- Same standing constraint as the parent's DELETE policy, and load-bearing
-- rather than incidental here: the replace-all path DELETEs this table's rows
-- before re-inserting them, so the DELETE verb is on the hot path.
create policy tax_bracket_row_delete on pfin.tax_bracket_row
  for delete to authenticated
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

-- ----------------------------------------------------------------------------
-- GRANTS — ACL-before-RLS (PR #106 gotcha): the role needs table-level GRANTs
-- even with RLS on. RLS filters rows; the GRANT is what lets the role reach the
-- table at all. Full V1 CRUD to authenticated on both tables, as the replace-all
-- path requires. No service_role grant (008 grants per table and establishes no
-- default privileges, so service_role is ungranted by construction — this line
-- records that, it does not effect it). anon zero-grant (pfin schema USAGE is
-- authenticated-only).
-- ----------------------------------------------------------------------------
grant select, insert, update, delete on pfin.tax_bracket_schedule to authenticated;
grant select, insert, update, delete on pfin.tax_bracket_row      to authenticated;

-- updated_at auto-refresh via the EXISTING fn_refresh_updated_at (001), on the
-- PARENT only: pfin.tax_bracket_row carries created_at and no updated_at, since
-- a bracket row is written by replace-all and never edited in place. Adds no
-- SECURITY DEFINER allowlist entry.
create trigger tax_bracket_schedule_set_updated_at
  before update on pfin.tax_bracket_schedule
  for each row execute function pfin.fn_refresh_updated_at();

-- ============================================================================
-- REPLACE-ALL WRITE BODY — pfin.fn_tax_bracket_schedule_replace_all
--
-- ADR-011 Decision 18 locks the schedule + its rows as a replace-all "under
-- SERIALIZABLE". On this transport the client cannot deliver that isolation
-- level (PostgREST runs each call as its own transaction; SET TRANSACTION
-- cannot run inside a function body), so the guarantee is realized as THIS
-- function — one plpgsql body, therefore one transaction — serialized by an
-- explicit FOR UPDATE lock on the caller's own schedule row. See the header's
-- transport-and-lock section for the failure the lock prevents (A ∪ B under
-- READ COMMITTED), the losing side, and why this does not retire the set fence.
--
-- ⚠ THE FIRST STATEMENT IS BOTH THE LOCK AND THE TENANT FENCE. Under SECURITY
--   INVOKER the SELECT ... FOR UPDATE runs with the caller's RLS, so another
--   tenant's schedule_id — or an absent one — yields ZERO ROWS and raises. The
--   function NEVER creates a schedule: creation is an ordinary INSERT under RLS.
--   The two cases are deliberately NOT distinguished in the raise message: a
--   caller must not be able to tell "someone else's schedule" from "no such
--   schedule", or the error becomes an existence oracle over other tenants' ids.
--
-- ⚠ THE APP PRE-VALIDATES p_rows; THIS FUNCTION IS THE FENCE. The shape check
--   below is not a duplicate of the app's Zod layer — it is the layer that still
--   holds when a caller reaches PostgREST directly with their own JWT, which is
--   the whole premise of the Lock 14 direct-DB-write surface. Exactly two keys,
--   both JSON numbers, nothing else admitted.
-- ============================================================================
create or replace function pfin.fn_tax_bracket_schedule_replace_all(
  p_schedule_id            bigint,
  p_tax_year               smallint,
  p_schedule_type          pfin.tax_schedule_type_enum,
  p_standard_deduction     numeric,
  p_tax_balance_prior_year numeric,
  p_rows                   jsonb
)
returns void
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_locked_id bigint;
  v_elem      jsonb;
  v_keys      text[];
begin
  -- (1) LOCK + TENANT FENCE. Under the caller's own RLS: another tenant's
  -- schedule, or none, is zero rows. Deliberately one message for both cases.
  select s.id
    into v_locked_id
    from pfin.tax_bracket_schedule s
   where s.id = p_schedule_id
     for update;

  if not found then
    raise exception
      'tax bracket replace-all refused: schedule_id % is not a schedule this caller owns (SELF-259 replace-all; the caller''s own RLS is what resolves it, and this function never creates a schedule)',
      p_schedule_id;
  end if;

  -- (2) SHAPE VALIDATION. The app pre-validates; this is the layer that holds
  -- for a caller reaching PostgREST directly with their own JWT.
  if p_rows is null or pg_catalog.jsonb_typeof(p_rows) <> 'array' then
    raise exception
      'tax bracket replace-all refused: p_rows must be a JSON array of bracket objects, got % (SELF-259 replace-all, p_rows shape)',
      pg_catalog.coalesce(pg_catalog.jsonb_typeof(p_rows), 'null');
  end if;

  for v_elem in select value from pg_catalog.jsonb_array_elements(p_rows) loop
    if pg_catalog.jsonb_typeof(v_elem) <> 'object' then
      raise exception
        'tax bracket replace-all refused: every p_rows element must be an object, got % (SELF-259 replace-all, p_rows shape)',
        pg_catalog.jsonb_typeof(v_elem);
    end if;

    select pg_catalog.array_agg(k order by k)
      into v_keys
      from pg_catalog.jsonb_object_keys(v_elem) as k;

    if v_keys is distinct from array['bracket_floor', 'bracket_rate']::text[] then
      raise exception
        'tax bracket replace-all refused: every p_rows element must carry EXACTLY the keys bracket_floor and bracket_rate, got % (SELF-259 replace-all, p_rows shape)',
        v_keys;
    end if;

    if pg_catalog.jsonb_typeof(v_elem -> 'bracket_floor') <> 'number'
       or pg_catalog.jsonb_typeof(v_elem -> 'bracket_rate') <> 'number' then
      raise exception
        'tax bracket replace-all refused: bracket_floor and bracket_rate must both be JSON numbers (a quoted numeric string is refused deliberately) (SELF-259 replace-all, p_rows shape)';
    end if;
  end loop;

  -- (3) DELETE the schedule's existing rows. Safe to delete before inserting
  -- because the lock above guarantees no concurrent writer is mid-replace.
  delete from pfin.tax_bracket_row r
   where r.schedule_id = p_schedule_id;

  -- (4) INSERT the new set. users_id from auth.uid(), NEVER from a parameter —
  -- there is no tenant parameter to forge (R4 rider 4). The #18 matched-tenant
  -- fence still checks each row against the schedule's owner.
  insert into pfin.tax_bracket_row (users_id, schedule_id, bracket_floor, bracket_rate)
  select auth.uid(),
         p_schedule_id,
         (e.value ->> 'bracket_floor')::numeric,
         (e.value ->> 'bracket_rate')::numeric
    from pg_catalog.jsonb_array_elements(p_rows) as e;

  -- (5) UPDATE the scalars. Fires tax_bracket_schedule_set_updated_at.
  update pfin.tax_bracket_schedule s
     set tax_year               = p_tax_year,
         schedule_type          = p_schedule_type,
         standard_deduction     = p_standard_deduction,
         tax_balance_prior_year = p_tax_balance_prior_year
   where s.id = p_schedule_id;

  -- The deferred set fence (zero-floor + rate monotonicity) and the #18
  -- matched-tenant fence fire at COMMIT, after this function returns. A caller
  -- that gets no exception here has NOT yet been told the write is valid.
  return;
end;
$$;

revoke execute on function pfin.fn_tax_bracket_schedule_replace_all(
  bigint, smallint, pfin.tax_schedule_type_enum, numeric, numeric, jsonb) from public;

grant execute on function pfin.fn_tax_bracket_schedule_replace_all(
  bigint, smallint, pfin.tax_schedule_type_enum, numeric, numeric, jsonb) to authenticated;

comment on function pfin.fn_tax_bracket_schedule_replace_all(
  bigint, smallint, pfin.tax_schedule_type_enum, numeric, numeric, jsonb) is
  'Atomic replace-all write body for one pfin.tax_bracket_schedule and its '
  'pfin.tax_bracket_row set (PRD §2.5.2; ADR-011 Decision 18 / Lock 14; '
  'SELF-259). Decision 18 locks this write as replace-all UNDER SERIALIZABLE; '
  'that isolation level is not reachable from this transport — PostgREST runs '
  'each call as its own transaction and cannot hold a client-side BEGIN, and '
  'SET TRANSACTION cannot be issued inside a function body because the calling '
  'statement has already taken its snapshot — so the guarantee is realized as '
  'this function (one plpgsql body, therefore one transaction) serialized by an '
  'explicit FOR UPDATE lock on the caller''s own schedule row. WHAT THE LOCK '
  'PREVENTS, MEASURED against a live two-session race with the lock struck at '
  'this migration''s authoring: (i) when both callers send a non-empty set, the '
  'second aborts with a duplicate-key violation on '
  'tax_bracket_row_schedule_id_bracket_floor_key — the zero-floor set fence '
  'forces bracket_floor 0 into every non-empty schedule, so two sets always '
  'collide there and the second caller''s write is lost behind an error naming '
  'a constraint unrelated to the real cause; and (ii) when the second caller '
  'sends an EMPTY set to clear the schedule, there is no error at all and the '
  'schedule is left holding the first caller''s rows — a silent lost update, '
  'the worse case because nothing surfaces. A union of the two sets is NOT '
  'reachable on this pair, and a reader expecting one will look for the wrong '
  'symptom. ⚠ THE LOCK IS ALSO THE TENANT FENCE and is therefore the '
  'FIRST statement: SECURITY INVOKER means the SELECT ... FOR UPDATE runs under '
  'the caller''s own RLS, so another tenant''s schedule_id — or an absent one — '
  'resolves to zero rows and raises. The two cases share one message '
  'deliberately, so the error cannot be used as an existence oracle over other '
  'tenants'' ids. This function NEVER creates a schedule; creation is an '
  'ordinary INSERT under RLS, and an empty schedule is legal. TAKES NO TENANT '
  'PARAMETER: users_id comes from auth.uid(), never from an argument, so there '
  'is nothing for a caller to forge. p_rows is a JSON array of objects carrying '
  'EXACTLY the keys bracket_floor and bracket_rate, both JSON numbers; an empty '
  'array is legal and clears the schedule; anything else raises. ⚠ p_rows is a '
  'TRANSPORT parameter and is NOT a breach of Decision 18''s no-JSONB-blobs '
  'forward-compat fence, which governs STORAGE: every value lands in a typed '
  'numeric column with its own CHECKs and no JSONB is stored anywhere on this '
  'pair. ⚠ THE LOCK DOES NOT RETIRE THE SET FENCE and never could: it orders '
  'the writers, while fn_tax_bracket_row_schedule_invariants judges what they '
  'wrote (Sec D-5) — that deferred fence and the ADR-011 Decision 3 #18 '
  'matched-tenant fence both fire at COMMIT, after this function returns, so a '
  'caller that gets no exception from it has not yet been told the write is '
  'valid. SECURITY INVOKER deliberately, not by default: under DEFINER the '
  'first SELECT would see every tenant''s row and ownership would have to be '
  're-implemented by hand, replacing a fence the database applies with one a '
  'reviewer must verify. Adds no SECURITY DEFINER allowlist entry. '
  'set search_path = ''''. EXECUTE revoked from PUBLIC, granted to '
  'authenticated — a direct call is this function''s only use, unlike the two '
  'trigger fences on this pair, which are granted to nobody.';

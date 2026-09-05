-- ============================================================================
-- Migration: pfin.monthly_report — the Lock 11 monthly-report HEADER table, and
--   the carrier of the R1 frozen rendered payload. Phase 6 Build Loop, Linear
--   SELF-345 / A1. Realizes [ADR-011](DECISIONS.md#adr-011) Decision 15 / Lock 11
--   and the V1.5 pre-flight sitting's rulings R1 / R4 / R5 / R11 / R12.
--   apply-migration procedure applied.
--   JOINT-REVIEW-MANDATORY (Sec veto surface). ⚠ Reviewed as ONE design unit with
--   `109` (A2) and `110`/`111` (A3 + the R7 audit helper) under ONE Sec
--   joint-review — R1 rider 8, R13 step 6. Do not review this file alone.
--
-- ----------------------------------------------------------------------------
-- WHAT THIS TABLE IS, IN ONE PARAGRAPH. One row per (user, target month,
--   generation attempt). The cron — or the A10 on-demand endpoint — writes a
--   `draft`. Authoring (or an explicit skip) promotes it to `final`, and THAT is
--   the moment the composed report is FROZEN into `rendered_payload`. A later
--   regeneration writes a NEW row and moves the old one to `superseded`. Every
--   read of a `final` report — in-app and PDF alike — reads the stored payload,
--   never a recomposition (R1 (A)).
--
-- ----------------------------------------------------------------------------
-- ⚠ THE FROZEN RENDERED PAYLOAD — R1 (A), AND THE DDL CALL R1 DELEGATED.
--   R1 ruled the freeze and left the storage shape to Architect. Taken: **columns
--   on this header**, not a payload child. Reasons, in the ruling's own terms:
--     (i)   the item-6 immutability trigger already governs this row WHOLE-ROW, so
--           the payload inherits the wave's canonical Decision 2 fence with no
--           second surface to fence;
--     (ii)  a payload child would be a third table owing its own RLS, grants,
--           immutability trigger AND an explicit Decision 3 disposition on its
--           parent FK — cost with no queryability gain, because nothing queries
--           *into* the payload (`109` is the queryable index, per R1);
--     (iii) one row, one artifact, one lock.
--   **LOSING SIDE, NAMED:** the header row grows large and every `select *` over it
--   carries the payload. Readers that need only status / `generated_at` MUST
--   project columns. Accepted — the alternative buys narrow rows at the price of a
--   fourth fenced surface.
--
--   ⚠⚠ R1's PARENTHETICAL SKETCH SAYS `rendered_payload JSONB NOT NULL`, AND THAT
--   FORM IS NOT BUILDABLE. The cron writes a `draft` row BEFORE any payload exists
--   (R9 rider 1; A7 item 4; R4 (c)), so an unconditional NOT NULL would make the
--   cron's own INSERT fail. **Realized as:** both columns NULLable, with
--   `monthly_report_payload_by_status` enforcing the conditional — `draft` permits
--   NULL; `final` and `superseded` require BOTH `rendered_payload` and
--   `payload_schema_version` NOT NULL. That is R1's *"written once, at
--   finalization"* stated as a constraint that CAN FAIL. **This is the DDL call R1
--   assigned, not a re-opening of R1**, and it is recorded in the consolidated ADR
--   so the ruling's sketch and the shipped shape do not read as divergent.
--   (Default-and-notify item 1 at the amendment batch; reversal window open until
--   this PR.)
--
--   FROZEN IN (R1 rider 1), as rendered at generation: every `{status, reason}` and
--     `{status, amount}` envelope · `basis_year` · the tax-authority exclusion
--     line's state · the unclassified count · the owner header (which is why
--     `owner_header_at_generation` is a column here and not a live join).
--   FROZEN OUT (R1 rider 2): the §2.6.5 staleness markers, read LIVE at every
--     render and export. They are deliberately NOT in the payload; a consumer that
--     finds no staleness key has not found a defect.
--   ⚠ THE STORED ARTIFACT IS RENDERED VALUES (JSON), NEVER PDF BYTES (R1 rider 7).
--     PDFs are regenerated from the payload on every export and are never
--     persisted (PRD §2.6.4, *"no PDF caching V1"*). **Sec M-6's standing condition
--     survives verbatim: the first AC that persists PDF bytes creates a
--     storage-class surface and is joint-review-mandatory at that PR.**
--   ⚠ A FROZEN PAYLOAD FREEZES ITS DEFECTS (R1 rider 6). The "Regenerate"
--     affordance (P5 item 4) and the pre-finalize no-tax-ledger prompt (P4 item 4)
--     are LOAD-BEARING, not optional. This table cannot enforce that; it is
--     recorded here because this is the file that makes the freeze permanent.
--   ⚠ `payload_schema_version` IS BUMPED BY THE RENDERER, NEVER RE-DERIVED FROM THE
--     PAYLOAD'S SHAPE (R1 rider 4). A §2.x rendering change keeps reading old
--     payloads — the `nav_daily` lesson (ADR-040 / ADR-067 Decision 3).
--   ⚠ JSONB HERE DOES NOT TOUCH LOCK 14's NO-JSONB FORWARD-COMPAT FENCE (R1 rider
--     5). That fence governs the SETTINGS STORE (the `101` precedent).
--     `monthly_report` is a Lock 11 audit-class artifact, not a settings table.
--     Recorded so it is not re-litigated at this file's review.
--
-- ----------------------------------------------------------------------------
-- ⚠ DECISION 2 ON THIS SURFACE — WHICH HALF APPLIES, RATIFIED AT R4, AND THE COST
--   STATED RATHER THAN SOFTENED. [ADR-011](DECISIONS.md#adr-011) Decision 2 has two
--   halves and this table takes ONE of them.
--     THE INSERT-NEW-VERSION HALF GOVERNS THIS HEADER. Regeneration is a new row
--       plus a `final → superseded` transition on the old one; it is never a
--       hard-overwrite UPDATE (which would lose `included_reconciliation_event_ids`
--       and `owner_header_at_generation` history — Lock 11's own reason).
--     THE IMMUTABLE HALF GOVERNS `109` (the child) AND THE FROZEN PAYLOAD, which is
--       read-only once written.
--   ⚠⚠ **`draft → final` PROMOTION IS ITSELF AN UPDATE, SO DECISION 2's BLANKET
--   "UPDATE BLOCKED" WAS NEVER LITERALLY TRUE OF THIS TABLE UNDER ITS OWN LOCKED
--   VOCABULARY.** That is Sec's named cost and it is not softened here: D2's
--   blanket append-only claim stops being true of this table. **The mitigation is
--   that the exemption is a MONOTONE TRANSITION ON ONE COLUMN — checkable in the
--   trigger and in a battery leg — and NOT a column allowlist.** The consolidated
--   ADR says so and names where the mutability window closes: at the moment
--   `generation_status` leaves `draft`.
--
-- ----------------------------------------------------------------------------
-- THE IMMUTABILITY TRIGGER — R4 (B) WITH SEC'S FOUR CONDITIONS, ALL FOUR BUILT.
--   No SECURITY DEFINER supersession function; the Decision 9 allowlist is
--   UNTOUCHED BY THIS FILE. The drafted `fn_supersede_monthly_report` is struck.
--   ONE trigger, NOT role-conditional, permitting exactly:
--     (i)   any column while `generation_status = 'draft'`;
--     (ii)  `generation_status` only on the single monotone transition
--           `final → superseded`, with NOTHING ELSE changing in the same statement;
--     (iii) nothing else, ever.
--   and fencing `users_id` + `target_month` in EVERY state, `draft` included
--   (Lock 12's Sec catch: a parent re-tenant orphans `109`'s children from their
--   original tenant; Decision 3 label #4's own text names this parent-immutability
--   extension as part of that instance, and `109` verifies it from the other side).
--
--   **(a) DELETE STAYS BLOCKED on every non-`draft` row**, by the same trigger.
--     Decision 2 is a TWO-VERB rule and clauses (i)–(iii) govern only UPDATE — Sec
--     names the shape: *"enumeration-stops-one-short, applied to a two-verb rule
--     restated with one verb."* `authenticated` holds INSERT for the A10 on-demand
--     path and **never DELETE**; PRD §2.6.4 commits to indefinite retention, with
--     user-initiated deletion explicitly V2+.
--     ⚠ HONEST RESIDUAL ON THE PERMITTED BRANCH: the trigger permits DELETE of a
--       `draft` row, exactly as R4 (a) words it — but **no role holds a DELETE
--       grant on this table**, so that branch is DORMANT BY GRANT and unreachable
--       today. It is left as ruled rather than tightened to block-all-DELETE,
--       because narrowing it here would diverge from R4 silently. **Revival
--       condition: the first DELETE grant on this table.** ⚠ A battery leg
--       asserting "draft DELETE succeeds" would need that grant and would therefore
--       be testing a path V1.5 does not have.
--   **(b) THE TRIGGER IS NOT ROLE-CONDITIONAL.** The same monotone rule binds
--     `authenticated` and `service_role` IDENTICALLY, and the battery proves
--     refusal UNDER BOTH. ⚠ The realistic later defect is named so a reviewer can
--     watch for it: the cron performs the `final → superseded` UPDATE under
--     `service_role`, so someone adds an early return for `service_role` to make it
--     work — **and a leg run only as `authenticated` passes with that exemption in
--     place.** There is no role test anywhere in the trigger body, by design.
--   **(c) LEGAL INSERT STATES ARE CONSTRAINED, NOT ONLY LEGAL TRANSITIONS.** A
--     transition guard governs UPDATE and is SILENT on a row written directly in
--     the target state: with `authenticated` holding INSERT, a row could be POSTed
--     straight in as `final`, **taking the month's single `final` slot without ever
--     passing the author-before-generate gate.** A separate BEFORE INSERT trigger
--     admits `draft` only. (A10 rider 1 states the same rule from the write path's
--     side.)
--   **(d) `superseded` IS TERMINAL** — stated in the trigger, in this header, and in
--     the catalog, so the battery has an obvious leg.
--     **RUNBOOK LINE, REQUIRED (R4 (d)):** this trigger is the ONLY APPLICABLE LAYER
--     for an RLS-exempt writer and, per [ADR-011](DECISIONS.md#adr-011) Decision 4's
--     2026-09-03 amendment, **goes inert under `session_replication_role =
--     replica`** — that amendment states the applicable-layer count for such a
--     writer goes to ZERO, not to one. **Any bulk-load or restore path touching this
--     table owes an explicit post-load validation step.**
--   ⚠ `service_role` IS FENCED ON THIS TABLE TOO. Decision 2 verbatim requires
--     append-only *"across both `authenticated` AND `service_role` roles"*; `109`
--     item 4(iii) carries a `service_role` bypass DB-trigger for the child, and **a
--     child fenced against a role its parent is not is a fence with a door beside
--     it.** `service_role` carries `rolbypassrls`, so on this surface the trigger is
--     its only applicable layer — there is no RLS behind it to catch a miss.
--
--   HOW "NOTHING ELSE CHANGED" IS TESTED, AND WHY THE FORM MATTERS. The trigger
--   compares `to_jsonb(new) - 'generation_status'` against
--   `to_jsonb(old) - 'generation_status'`. That is a STRUCTURAL test over the whole
--   row rather than a column allowlist, and the difference is not stylistic: **a
--   column added to this table by a future migration is fenced automatically**,
--   where an allowlist would silently admit it. It is the same reasoning R4 gives
--   for preferring a monotone transition over a column allowlist, applied to the
--   implementation.
--
--   ⚠ `updated_at` + `fn_refresh_updated_at` ARE LEGITIMATE ONLY WITHIN THE `draft`
--     WINDOW (PM D-6, ratified at R4). On a final-immutable row the refresh is
--     either dead code or a hole. **Realized as a `when (old.generation_status =
--     'draft')` clause on the refresh trigger**, so it is neither: it cannot fire
--     outside the window, and the window is where it is meaningful.
--     CONSEQUENCE, stated so it is not read as a bug: on a `superseded` row
--     `updated_at` holds the time of the LAST DRAFT EDIT, not the time of
--     supersession. The supersession instant is not recorded on this table by
--     design — the successor row's `created_at` is when it happened.
--     TRIGGER ORDER: BEFORE UPDATE triggers fire in ALPHABETICAL trigger-name order,
--     so `monthly_report_immutability` runs before `monthly_report_refresh_updated_at`
--     — the fence raises before `updated_at` is touched. Verified at authoring.
--
-- ----------------------------------------------------------------------------
-- ⚠ ADR-011 DECISION 3 — THIS MIGRATION **REALIZES** LABEL #3 AND **ALLOCATES
--   NOTHING** (R5 (a)). Decision 3's body read LIVE at authoring (2026-09-05).
--   **NO COUNT IS CARRIED IN THIS FILE.**
--
--   PER-COLUMN DISPOSITION (Sec F-1 requires this stated per column, with the
--   fence-pattern class named):
--     · `included_reconciliation_event_ids INTEGER[]` → `pfin.reconciliation_event`
--       — **CANONICAL LABEL #3**, carried UNREALIZED since ADR-011 authoring and
--       DDL-realized here. Array-element matched-tenant BEFORE INSERT OR UPDATE
--       trigger, which is the form Decision 3 reserves for arrays because
--       PostgreSQL cannot express an element-wise FK declaratively. There is
--       therefore NO declared FK on this column, by construction and not by
--       omission.
--     · `users_id uuid` → `auth.users(id)` — **NOT a Decision 3 instance.** It is
--       this table's sole tenant anchor under a direct RLS predicate (`users_id =
--       auth.uid()`), the `024` / `054` / `107` disposition: the anchor IS the
--       reference, so there is no second tenant fact to mismatch. ⚠ R5's
--       consequences make this explicit for a reason — **a matched-tenant fence on
--       the tenant anchor is *the leg that cannot fail*** (`007` / `015`;
--       [ADR-062](DECISIONS.md#adr-062) Decision 2), and drafting one here would
--       have added a fence that can only ever pass.
--
--   ⚠⚠ **FINDING, ROUTED TO SEC AT THIS UNIT'S REVIEW — LABEL #3's ENTRY DESCRIBES
--   A COLUMN THAT DOES NOT EXIST, AND THE FENCE IS BUILT TO THE TABLE RATHER THAN
--   TO THE ENTRY.** Decision 3's #3 entry reads *"validates every array element's
--   `reconciliation_event.users_id` = row's `users_id`"*. **`pfin.reconciliation_event`
--   HAS NO `users_id` COLUMN.** It was created at `005` with `account_id` as its
--   sole anchor and resolves its tenant through `account_id → pfin.account.users_id`
--   — which is exactly why label **#1** (`reconciliation_event_trans`) is classed
--   **CR matched-ACCOUNT** rather than matched-tenant. The entry's parenthetical
--   predates `005`. **The fence below therefore chain-resolves each array element
--   through `reconciliation_event.account_id → pfin.account.users_id` and compares
--   THAT to `new.users_id`.** The instance, its label and its target are unchanged;
--   what is corrected is the entry's description of the mechanism, and it is
--   corrected by an AMENDMENT beneath the entry in the same PR — never by editing
--   the dated entry, which records what was believed at ADR-011 authoring.
--   ⚠ **CONSEQUENTLY THE FENCE-PATTERN CLASS IS NOT THE `P1` THE ENTRY NAMES.** The
--   REFERRING row (`monthly_report`) has its own `users_id`, which is P1's
--   condition; but the REFERENCED row has no tenant column, so its tenant must be
--   chain-resolved, which is CR's mechanism. **This instance is the first in the
--   family to need BOTH halves — P1 on the referring side, chain resolution on the
--   referenced side — and no existing class name describes it.** It is recorded in
--   the amendment as **P1/CR (hybrid)**, on the #12 precedent, which is the family's
--   existing name for a fence whose two legs resolve tenant differently. Sec's to
--   confirm the naming; the DDL is the same either way.
--
--   **THE FENCE IS CORRECT, MANDATORY AND DORMANT (R5) — BUT THE DORMANCY IS A
--   PROPERTY OF THE PRODUCT PATH, NOT OF THE GRANTS, AND THE DIFFERENCE MATTERS.**
--   ⚠⚠ **SECOND FINDING, ROUTED TO SEC AND TO F/CTO: R5's rider rests on a premise
--   that is FALSE AT THE DATABASE LAYER, MEASURED HERE RATHER THAN INHERITED.** The
--   natural way to state this fence's dormancy is *"`pfin.reconciliation_event` has
--   no writer at this sha"*, and the DB does not support it. **Measured 2026-09-05
--   against a clean `001`–`109` apply: `pfin.reconciliation_event` carries an INSERT
--   GRANT to `authenticated` AND an `reconciliation_event_insert` RLS POLICY for
--   `authenticated`.** A plain authenticated caller can therefore POST a
--   reconciliation event for their own account through PostgREST today.
--   WHAT **IS** ABSENT, verified by grep over `supabase/migrations/`, `api/`, `web/`
--   and `workers/`: **no database function and no application surface writes
--   `pfin.reconciliation_event`, and no V1.5 surface writes
--   `included_reconciliation_event_ids` at all.** So in the SHIPPED PRODUCT the
--   array is empty on every row and this fence never fires.
--   **CONSEQUENCE FOR QA, STATED PLAINLY: the fence IS behaviourally reachable from
--   a test, because a battery is not the product.** A two-tenant fixture can insert
--   a reconciliation event under each tenant and then attempt to place tenant B's
--   `event_id` into tenant A's array — and the fence raises. **Verified at authoring
--   on the scratch apply: a bogus element id is rejected by this fence, so it is
--   constructed and functional, not merely present.**
--   **REVIVAL CONDITION, NAMED — and it is the PRODUCT-PATH one:** the first
--   application or worker surface that writes `pfin.reconciliation_event` and the
--   first surface that populates this array, expected together at the V1.6 statement
--   tie-out ([ADR-035](DECISIONS.md#adr-035)). The instance is
--   deferred-WITH-A-CONSUMER, not orphaned, which is why R5 declined option (b)
--   (retire or re-defer by a Decision 3 amendment).
--   ⚠ **THE PAIRED QA LEG IS CONSTRUCTION-ONLY AND MUST SAY SO IN ITS OWN TEXT**
--   (R5 rider, and it is RULED, so it ships as ruled). It asserts the trigger
--   EXISTS, is ATTACHED to this column, and CARRIES the matched-tenant body.
--   ⚠ **BUT THE RIDER'S OWN REASON — *"it does not assert firing, because nothing
--   can populate the array in V1.5"* — IS THE PREMISE JUST FALSIFIED.** The rider's
--   PURPOSE (no later reader mistakes a leg that cannot fail for behavioural
--   coverage) is served BETTER by a leg that actually fires than by one that cannot.
--   **This file therefore ships the fence as ruled and RECOMMENDS a firing leg
--   ALONGSIDE the construction-only one, and does not substitute for it.** Whether
--   the rider is amended is Sec's and F/CTO's, not this migration's.
--
-- ----------------------------------------------------------------------------
-- R11 — THE COMMENTARY COLUMN IDENTIFIER. The fourth commentary column is
--   `commentary_marketable_securities`, not `commentary_equity`. The four
--   sub-section headings are **Cash / Bonds / Marketable Securities /
--   Alternatives** per PRD §2.6.2 verbatim (F/CTO-ratified 2026-08-19 following
--   [ADR-058](DECISIONS.md#adr-058) Decision 7, migration `082`). Option (b) (keep
--   `commentary_equity`, change only the heading) was not taken: a column on an
--   audit-class table is permanent, and the rename is free before this migration
--   lands and a migration after.
--   ⚠ **R11 rider 1: the rename is recorded as a CORRECTION TO GATE B's RATIFY TEXT
--   inside the consolidated ADR, never by migration alone.** It must not arrive as
--   a schema fact with no register entry. That correction ships in this PR.
--
--   FOUR NAMED TEXT COLUMNS, NOT A JSONB COMMENTARY BLOB — Wave 6 Gate B option C.
--   The Lock 14 forward-compat fence is the reason, and it is a different fence
--   from R1 rider 5's: **Gate B is about the COMMENTARY, which is user-authored
--   settings-shaped data; R1 rider 5 is about the PAYLOAD, which is a rendered
--   artifact.** The two JSONB questions on this table have opposite answers and
--   that is not an inconsistency.
--
--   ⚠ EACH COMMENTARY COLUMN CARRIES A CHECK-ENFORCED LENGTH BOUND (Sec N-5),
--   mirrored in P3's Zod schema. Bare TEXT would leave P3's length-bounds battery a
--   SINGLE-LAYER APP CONTROL on a Lock 14 write path, and Decision 4's
--   user-facing-surface class is explicitly a multi-layer commitment. The consumer
--   is a browser engine rendering a PDF, where unbounded prose is a memory and
--   render-time cost it is not on a scrollable web page.
--   **CATCH CRITERION (Sec): a body ONE BYTE OVER is rejected 400 at the app layer
--   AND the same value is rejected by the DB when submitted directly through
--   PostgREST — two facts that can disagree, which is what makes it a real second
--   layer.** A battery that only exercises the app layer proves nothing about this
--   constraint.
--   **THE BOUND IS 4000 CHARACTERS PER COLUMN — PM's PRODUCT RULING, taken
--   2026-09-05**, closing the default-and-notify item the sitting recorded
--   (*"commentary CHECK-enforced length bound mirrored in Zod, PM picks the
--   number"*). PM's reasoning, recorded because the number will otherwise look
--   arbitrary to whoever meets it: a sub-section's commentary is a few sentences to
--   a short paragraph, so 4000 is roughly **one PDF page per sub-section at the
--   worst case** — and a tighter bound such as 2000 **risks refusing a heavy month's
--   commentary inside the draft window**, which is the wrong failure for an
--   authoring surface.
--
--   ⚠⚠ **THE MIRROR RULE, AND IT IS A UNIT QUESTION BEFORE IT IS A NUMBER
--   QUESTION.** Sec **N-5**'s catch criterion is that *the same value* is rejected at
--   both layers — an EQUALITY, not merely "the app is at least as strict". The two
--   layers do not count the same thing by default:
--     · PostgreSQL `length()` counts **CODE POINTS**;
--     · JavaScript `String.prototype.length` counts **UTF-16 CODE UNITS**, so every
--       character outside the BMP (an emoji, many CJK extension characters) counts
--       as **TWO**.
--   **So a `.length`-based Zod bound of 4000 is STRICTER than this CHECK, and a body
--   of 2001 astral characters would be refused by the app and ACCEPTED by the
--   database — the two layers disagreeing on exactly the input N-5 asks them to
--   agree on.** **P3's Zod bound must therefore count CODE POINTS:
--   `Array.from(s).length`, not `s.length`.**
--   ⚠ **This deliberately differs from the `106` / P7 precedent, and the difference
--   is not an inconsistency.** There the app used `.length` — the stricter direction
--   — and Sec accepted it, because that obligation was *"the app must not admit what
--   the DB refuses"*. **N-5 asks for EQUALITY here**, and stricter-in-one-direction
--   does not satisfy an equality. Recorded so nobody "aligns" this back to the `106`
--   idiom on the grounds that it is the house style.
--
-- ----------------------------------------------------------------------------
-- `commentary_disposition` — R12 rider 1. A durable authored-vs-skipped fact per
--   report. *"A skip must be distinguishable from four empty strings"*, and **four
--   empty strings are a legitimate AUTHORED state** (P3 item 8) — which is why this
--   cannot be derived by looking at the four columns and must be stored. P4 item 5
--   is the affordance that writes it.
--   **R12 (A) MAKES IT LOAD-BEARING BEYOND V1.5:** a month whose commentary was
--   explicitly SKIPPED does not count toward SELF-365's N = 2, so this column is
--   the fact that gate reads. (SELF-365's own AC wording is PM's; this file owes it
--   the column, not the definition.)
--   ⚠ IT IS ALSO THE DB-LAYER HALF OF P4's COMPLETE-OR-EXPLICITLY-SKIP GATE: the
--   status CHECK requires it NON-NULL on `final` and `superseded`. A report cannot
--   be finalized without the author having either written or explicitly skipped —
--   and that is a fact the database enforces, not only the app.
--
-- ----------------------------------------------------------------------------
-- `target_month` IS FENCED TO THE FIRST OF THE MONTH, AND THE FENCE IS
--   LOAD-BEARING RATHER THAN TIDY. Lock 11's partial UNIQUE is
--   `(users_id, target_month) WHERE generation_status = 'final'`. **Without a
--   day-anchor CHECK that index does not enforce one final report PER MONTH** — it
--   enforces one per (user, DATE), so `2026-08-01` and `2026-08-15` would be two
--   distinct finals for August and the lock's stated guarantee would be false. The
--   CHECK is what makes the ratified index mean what it says.
--
-- ----------------------------------------------------------------------------
-- UNIQUENESS — LOCK 11's PARTIAL INDEX, VERBATIM AND UNMODIFIED:
--     UNIQUE (users_id, target_month) WHERE generation_status = 'final'
--   It keeps firing under R4: the trigger permits at most one `final → superseded`
--   transition per row, and a regeneration inserts a new `draft` that is promoted
--   only after the incumbent has been superseded.
--   ⚠ **SEC D-5's CATCH CRITERION IS THE SHARP ONE AND MUST BE HONOURED BY THE
--   BATTERY: REGENERATE THE SAME MONTH THREE TIMES, NOT TWICE.** A two-regeneration
--   leg PASSES against the defective three-column form of this index (one that
--   included `generation_status` in the key), so a two-regeneration battery cannot
--   tell the ratified index from the broken one. Three regenerations → three rows,
--   exactly one `final`.
--
-- ----------------------------------------------------------------------------
-- STATUS VOCABULARY BRIDGE (A1 item 8; authorized at R10, PM A-8; worded to hold
--   under R4), stated once against the transition and repeated in the consolidated
--   ADR: **pending = `draft`; generated = the current `final`; a `superseded`
--   version is never rendered in V1.** The cron writes `draft`; completing OR
--   EXPLICITLY SKIPPING authoring promotes to `final`; regeneration supersedes.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (default per Lock 11); NOT SECURITY
--   DEFINER. This migration authors FOUR functions and ALL FOUR are SECURITY
--   INVOKER with `set search_path = ''`: the immutability trigger, the INSERT-state
--   trigger, the TRUNCATE fence, and the Decision 3 #3 array fence. Each either
--   inspects OLD/NEW and raises, or performs an RLS-scoped existence read and
--   raises; none needs elevated privilege. **The Decision 9 allowlist is UNCHANGED
--   BY THIS FILE — R4 (B) struck the drafted `fn_supersede_monthly_report`
--   outright.** Read Decision 9 live for the allowlist's contents; no size is
--   stated here. (⚠ `111` — the R7 general audit-log helper riding this same PR —
--   IS a Decision 9 event; its posture and the amendment it carries are stated in
--   that file, not here.)
--   `fn_refresh_updated_at` (`001`) is a pre-existing DEFINER allowlist entry that
--   this file ATTACHES; attaching an existing entry is not an allowlist event.
--
-- ----------------------------------------------------------------------------
-- RLS — the `090` standard (USING **and** WITH CHECK per verb; `users_id =
--   auth.uid()`; explicit grants) PLUS the [ADR-029](DECISIONS.md#adr-029) / `025`
--   aal2 step-up backstop clause on the `authenticated` READ AND WRITE policies
--   (Sec F-9; default-and-notify, taken). None of 025's three documented exclusions
--   applies — in particular **NOT** the `user_settings` exclusion, which exists
--   only because that table is the clause's own subquery target.
--   **CATCH CRITERION (Sec F-9): a totp/passkey-enrolled caller presenting a
--   BELOW-aal2 JWT lands on the refusal leg — a DIFFERENT LEG from the cross-tenant
--   leg. A battery testing only cross-tenant passes with the clause absent.**
--   ⚠ NO DELETE POLICY AND NO DELETE GRANT for `authenticated` (R4 (a)).
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK ([ADR-011](DECISIONS.md#adr-011) Decision 4 read VERBATIM
--   and LIVE before drafting, 2026-09-05. Path B — the catalogued numbered list is
--   NOT restated and NO COUNT is carried; this migration is not the canonical
--   anchor).
--   (i)   INSTANCE-NUMBERING — no catalogued instance is added, removed, reordered
--         or renumbered. Realizing a Decision 3 label is a DIFFERENT ledger and is
--         not a §10 event (the SELF-187 de-conflation precedent).
--   (ii)  LAYER-ATTRIBUTION — nothing moves. This table's grants are DB-LAYER ACLs;
--         they are not the code-layer service-role-key allowlist grep fence, not the
--         PDF-worker container credential audit, and not the app→worker admission
--         network/config surface. The per-surface layer-composition language is
--         UNCHANGED and no surface becomes "four-layer".
--   (iii) VERBATIM-VS-PARAPHRASE — Decision 4 is LINKED, never restated.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED RT set are DIFFERENT SETS and are not
--   reconciled here or anywhere.
--   DE-CONFLATION GUARD: none of the four fences authored here is a §10 catalogued
--   instance. Three are Decision 2 audit-class mechanisms; one is a Decision 3
--   family member. All compose with Decision 4's defense-in-depth DISCIPLINE and
--   none adds an entry to its catalogued list.
--
-- ----------------------------------------------------------------------------
-- Numbering: 108 follows 107. Order-dependent — must run AFTER 001 (pfin schema +
--   `fn_refresh_updated_at`), 003 (pfin.account — the array fence's tenant-resolution
--   target, and the auth.users FK target), 005 (pfin.reconciliation_event — the
--   array fence's read target), 024 (pfin.user_settings, which the aal2 clause
--   subqueries) and 025 (the aal2 backstop this table inherits). `109` (the child)
--   and `110` (the composition helper) depend on THIS file.
--
-- ----------------------------------------------------------------------------
-- QA PAIRING LIST for this file (two-tenant pgTAP battery, same PR):
--   1. cross-tenant read → fail closed; owner reads own rows → pass.
--   2. **aal2 leg as a SEPARATE leg** — a totp/passkey-enrolled caller with a
--      below-aal2 JWT is refused (Sec F-9's catch criterion).
--   3. **regenerate one month THREE times** → three rows, exactly one `final`
--      (Sec D-5; a two-regeneration leg cannot distinguish the ratified index).
--   4. UPDATE a `final` row (any column but the transition) → refused, **as
--      `authenticated` AND as `service_role`** (R4 (b), two legs).
--   5. DELETE a `final` and a `superseded` row → refused under both roles.
--   6. INSERT directly as `final` → refused; INSERT as `draft` → accepted.
--   7. `superseded` is terminal: `superseded → final` and `superseded → draft` →
--      both refused.
--   8. `users_id` or `target_month` UPDATE → refused **in the `draft` state too**.
--   9. `final` with NULL `rendered_payload` / NULL `payload_schema_version` /
--      NULL `commentary_disposition` → refused by the status CHECK; the same row
--      as `draft` → accepted.
--  10. commentary one character over the bound → refused **through PostgREST**, not
--      only in the app (Sec N-5).
--  11. `target_month` not the 1st → refused.
--  11b. **ONE LIVE DRAFT:** a second INSERT in `draft` for the same
--      (users_id, target_month) → refused 23505 on
--      `monthly_report_one_live_draft_per_month`. ⚠ And the leg that proves the index
--      is PARTIAL rather than over-broad: with a `final` and a `superseded` row
--      already present for that month, inserting a draft still SUCCEEDS. A leg
--      testing only the refusal cannot tell this index from one keyed on all three
--      states, which would make regeneration impossible.
--  12. **CONSTRUCTION-ONLY (R5 rider — RULED; label the leg as such in its own
--      text):** the `#3` array fence EXISTS, is attached to
--      `included_reconciliation_event_ids`, and carries the matched-tenant body.
--  12b. **RECOMMENDED FIRING LEG, ALONGSIDE 12 AND NEVER INSTEAD OF IT** — see the
--      DECISION 3 header block's second finding. `pfin.reconciliation_event` carries
--      an INSERT grant AND an INSERT policy for `authenticated` (measured), so a
--      two-tenant fixture CAN insert an event under each tenant and then put tenant
--      B's `event_id` into tenant A's array; the fence raises. **A battery is not the
--      product, and the rider's stated reason — that nothing can populate the array
--      — does not hold at the DB layer.** Whether R5's rider is amended is Sec's and
--      F/CTO's; this list offers the leg rather than assuming it.
--  13. the `updated_at` refresh fires on a `draft` UPDATE and does NOT fire on the
--      `final → superseded` transition.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.monthly_report — one row per (user, target month, generation attempt).
--     report_id (surrogate PK) · users_id uuid (sole tenant anchor; → auth.users
--     ON DELETE CASCADE) · target_month date (fenced to the 1st) ·
--     generation_status pfin.report_generation_status_enum (`draft` / `final` /
--     `superseded`; INSERT admits `draft` only) · data_as_of date ·
--     generated_at timestamptz · owner_header_at_generation text (NULLable; stays
--     NULL for a report generated before the user set a header — PM A-13,
--     authorized at R10) · commentary_cash / commentary_bonds /
--     commentary_marketable_securities / commentary_alternatives text (each bounded
--     at 4000 by CHECK) · commentary_disposition text (`authored` / `skipped`) ·
--     rendered_payload jsonb + payload_schema_version smallint (the R1 frozen
--     artifact; NULL only while `draft`) · included_reconciliation_event_ids
--     integer[] (Decision 3 #3, dormant) · created_at · updated_at.
--     UNIQUE (users_id, target_month) WHERE generation_status = 'final' — Lock 11
--     verbatim. PLUS a SECOND partial UNIQUE on the same key WHERE
--     generation_status = 'draft' — NOT Lock 11; the product invariant that at most
--     ONE LIVE DRAFT exists per (user, month), so a concurrent Generate cannot
--     silently orphan an author's in-progress commentary on a row nothing will ever
--     finalize or delete.
--   ⚠ COMMENTARY LENGTH — THE MIRROR RULE, a UNIT question before it is a number
--     question. The CHECK bound is 4000 and `length()` counts CODE POINTS.
--     JavaScript `.length` counts UTF-16 CODE UNITS, so an astral character counts
--     TWICE there. **P3's Zod bound must count code points — `Array.from(s).length`,
--     never `s.length`** — because Sec N-5's criterion is that the SAME VALUE is
--     rejected at both layers, an EQUALITY rather than "the app is at least as
--     strict". A `.length` mirror would refuse 2001 astral characters that this
--     CHECK accepts. ⚠ This differs from the `106` precedent on purpose: there the
--     obligation was one-directional and the stricter unit was accepted; here it is
--     an equality, and stricter does not satisfy it.
--   MUTATION SURFACE, per role:
--     · authenticated — SELECT / INSERT / UPDATE on own rows, aal2-claused. **NO
--       DELETE grant and NO DELETE policy.** Every write additionally passes the
--       INSERT-state and immutability triggers.
--     · service_role — SELECT / INSERT / UPDATE (the cron writes the draft,
--       promotes, and supersedes). **NO DELETE, NO TRUNCATE.** It bypasses RLS but
--       NOT the triggers, and is neither owner nor superuser so it cannot suppress
--       them.
--     · any owner-class role — blocked by the same triggers, which fire for the
--       owner too. KNOWN LIMIT: an owner-class role can suppress them; see the
--       runbook line at R4 (d).
--   pfin.fn_monthly_report_immutability() — INVOKER; BEFORE UPDATE OR DELETE
--     (row-level); the R4 (a)–(d) rule; NOT role-conditional. set search_path = ''.
--   pfin.fn_monthly_report_assert_insert_state() — INVOKER; BEFORE INSERT
--     (row-level); admits `draft` only (R4 (c)). set search_path = ''.
--   pfin.fn_monthly_report_block_truncate() — INVOKER; BEFORE TRUNCATE
--     (statement-level); raise. set search_path = ''. + REVOKE TRUNCATE FROM PUBLIC.
--   pfin.fn_monthly_report_matched_event_tenants() — INVOKER; BEFORE INSERT OR
--     UPDATE (row-level); Decision 3 label #3, array-element matched-tenant,
--     chain-resolved through the referenced event's account. DORMANT.
--     set search_path = ''.
--   RLS: SELECT / INSERT / UPDATE to authenticated on `users_id = auth.uid()` AND
--     the aal2 backstop, USING and WITH CHECK per verb. DELETE has NO policy and no
--     grant → default-deny.
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- The Lock 11 status vocabulary as a real ENUM (Lock 11 says ENUM; the `101`
-- idempotent-guard idiom). A closed vocabulary read by name at the trigger, the
-- partial index predicate, the status CHECK and every consumer — a typo must be a
-- type error, not a row that silently matches nothing.
-- ----------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
     where n.nspname = 'pfin' and t.typname = 'report_generation_status_enum'
  ) then
    create type pfin.report_generation_status_enum as enum ('draft', 'final', 'superseded');
  end if;
end
$$;

comment on type pfin.report_generation_status_enum is
  'The Lock 11 monthly-report generation vocabulary ([ADR-011](DECISIONS.md#adr-011) Decision 15, verbatim): draft / final / superseded. PRESENTATION BRIDGE (authorized at R10, PM A-8): pending = draft; generated = the current final; a superseded version is NEVER rendered in V1. LIFECYCLE: the cron (or the on-demand endpoint) INSERTs a draft — and a row may be INSERTed in NO OTHER STATE; completing OR EXPLICITLY SKIPPING authoring promotes it to final, which is the moment the composed report is FROZEN into rendered_payload; a regeneration INSERTs a new draft and moves the incumbent final to superseded. superseded is TERMINAL. The only UPDATE this vocabulary permits outside the draft window is the single monotone transition final -> superseded, enforced by pfin.fn_monthly_report_immutability, which is not role-conditional.';

-- ----------------------------------------------------------------------------
-- pfin.monthly_report — the Lock 11 header + the R1 frozen payload carrier.
-- users_id is the sole tenant anchor (direct-owner RLS; NOT a Decision 3 instance).
-- ON DELETE CASCADE: a user's reports are dependent data, removed with the user.
-- ----------------------------------------------------------------------------
create table if not exists pfin.monthly_report (
  report_id                          bigint      generated always as identity primary key,
  users_id                           uuid        not null default auth.uid()
                                                   references auth.users (id) on delete cascade,
  target_month                       date        not null,
  generation_status                  pfin.report_generation_status_enum not null default 'draft',
  data_as_of                         date        not null,
  generated_at                       timestamptz,
  owner_header_at_generation         text,
  commentary_cash                    text,
  commentary_bonds                   text,
  commentary_marketable_securities   text,
  commentary_alternatives            text,
  commentary_disposition             text,
  rendered_payload                   jsonb,
  payload_schema_version             smallint,
  included_reconciliation_event_ids  integer[]   not null default '{}'::integer[],
  created_at                         timestamptz not null default now(),
  updated_at                         timestamptz not null default now(),

  -- target_month names a MONTH, so it is fenced to that month's first day. Without
  -- this, the Lock 11 partial UNIQUE below enforces one final per (user, DATE) and
  -- NOT one final per month, and the lock's stated guarantee would be false.
  constraint monthly_report_target_month_is_month_start
    check (target_month = date_trunc('month', target_month)::date),

  -- R1, realized as the buildable form of its NOT NULL sketch. A draft may carry
  -- nothing; a final or superseded row must carry the frozen artifact, its version,
  -- the generation instant, and the authored-vs-skipped fact (the DB half of P4's
  -- complete-or-explicitly-skip gate).
  constraint monthly_report_payload_by_status
    check (
      generation_status = 'draft'
      or (rendered_payload       is not null
      and payload_schema_version is not null
      and generated_at           is not null
      and commentary_disposition is not null)
    ),

  constraint monthly_report_commentary_disposition_vocab
    check (commentary_disposition is null
        or commentary_disposition in ('authored', 'skipped')),

  -- 4000 characters, PM's product ruling (2026-09-05): roughly one PDF page per
  -- sub-section at the worst case, where a tighter bound risks refusing a heavy
  -- month's commentary inside the draft window. ⚠ P3's Zod bound must be the SAME
  -- number AND must count CODE POINTS (Array.from(s).length) — length() here counts
  -- code points while JS .length counts UTF-16 units, so a .length bound would be
  -- STRICTER and the two layers would disagree on astral characters, which is
  -- exactly the input Sec N-5 requires them to agree on.
  constraint monthly_report_commentary_cash_len
    check (commentary_cash is null or length(commentary_cash) <= 4000),
  constraint monthly_report_commentary_bonds_len
    check (commentary_bonds is null or length(commentary_bonds) <= 4000),
  constraint monthly_report_commentary_marketable_securities_len
    check (commentary_marketable_securities is null
        or length(commentary_marketable_securities) <= 4000),
  constraint monthly_report_commentary_alternatives_len
    check (commentary_alternatives is null or length(commentary_alternatives) <= 4000),

  -- 120 characters, per the sitting's default-and-notify block ("owner header
  -- 120-character bound"). Unlike the commentary bound this number IS ruled.
  constraint monthly_report_owner_header_len
    check (owner_header_at_generation is null
        or length(owner_header_at_generation) <= 120),

  constraint monthly_report_payload_schema_version_positive
    check (payload_schema_version is null or payload_schema_version >= 1)
);

-- Lock 11's partial UNIQUE, verbatim. At most one `final` report per user per
-- month; superseded rows are unconstrained, which is what makes regeneration
-- expressible at all.
create unique index if not exists monthly_report_one_final_per_month
  on pfin.monthly_report (users_id, target_month)
  where generation_status = 'final';

-- ----------------------------------------------------------------------------
-- ⚠ AT MOST ONE **LIVE DRAFT** PER (user, month) — ruled 2026-09-05 on PM's
-- objection, REVERSING an earlier ruling that declined this index. It is NOT part of
-- Lock 11 and it is recorded as a product invariant with its own reason.
--
-- THE FALSIFYING CASE PM SUPPLIED, which is why "multiple drafts are just the
-- audit-class shape" does not survive: tab A is editing draft #1; tab B clicks
-- Generate and INSERTs draft #2; tab A's Save lands on #1, which is still `draft`
-- and therefore still writable; P4 then finalizes #2 — **blank**. The author's
-- commentary is silently lost, and #1 **persists forever**, because clause 6(a)
-- blocks DELETE on everything and no role holds a DELETE grant even for drafts.
-- ⚠ **Silent, permanent, and invisible to every existing fence** — the immutability
-- trigger is working exactly as designed in that story.
--
-- WHAT THIS INDEX DOES NOT DO: it does not constrain `final` or `superseded`, so the
-- full regeneration history still coexists under one month. It fences only the
-- LIVE-EDIT slot.
-- CONSEQUENCES FOR THE WRITE PATHS, which is where the behaviour actually changes:
-- **Generate on a month that already has a live draft OPENS that draft; it never
-- INSERTs.** **Regenerate becomes a FINAL-ONLY affordance** (the final -> superseded
-- path). Copy is PM's.
-- LOSING SIDE, RECORDED — it is the earlier ruling's position, now the minority one:
-- a second Generate click **can now raise 23505** where before it silently created a
-- row, so the app owes that path a real handler rather than an error toast; and this
-- is a uniqueness fence on an audit-class table, which is a shape this project
-- otherwise reserves for Lock 11's own index.
-- ⚠ It also makes the read-composition helper's *"highest `report_id` in draft"* rule
-- degenerate — with at most one live draft there is nothing to choose between. That
-- rule and its echoed `source_report_id` are KEPT as written: the echo is what lets a
-- caller ASSERT it composed from the row it is about to write, and an assertion that
-- can no longer fail is still the thing that proves this index is holding.
-- ----------------------------------------------------------------------------
create unique index if not exists monthly_report_one_live_draft_per_month
  on pfin.monthly_report (users_id, target_month)
  where generation_status = 'draft';

comment on table pfin.monthly_report is
  'The Lock 11 monthly-report HEADER and the carrier of the R1 frozen rendered '
  'payload ([ADR-011](DECISIONS.md#adr-011) Decision 15; SELF-345 / A1; V1.5 '
  'pre-flight rulings R1 / R4 / R5 / R11 / R12). ONE ROW per (user, target month, '
  'generation attempt): the cron — or the on-demand endpoint — INSERTs a `draft`; '
  'completing OR EXPLICITLY SKIPPING authoring promotes it to `final`, which is the '
  'moment the composed report is FROZEN into rendered_payload; a regeneration '
  'INSERTs a new draft and moves the incumbent to `superseded`, which is TERMINAL. '
  'EVERY READ OF A `final` REPORT — in-app view and PDF export alike — READS THE '
  'STORED PAYLOAD, never a recomposition: a historical read takes the report row, '
  'it does not re-enter (month, as_of) into the composition helper. FROZEN IN: '
  'every {status, reason} and {status, amount} envelope, basis_year, the '
  'tax-authority exclusion line''s state, the unclassified count, and the owner '
  'header (which is why owner_header_at_generation is a column here and not a live '
  'join). FROZEN OUT: the PRD §2.6.5 staleness markers, read LIVE at every render '
  'and export — a consumer that finds no staleness key in the payload has not found '
  'a defect. THE STORED ARTIFACT IS RENDERED VALUES (JSON), NEVER PDF BYTES; PDFs '
  'are regenerated on every export and never persisted (PRD §2.6.4). '
  'payload_schema_version is BUMPED BY THE RENDERER and never re-derived from the '
  'payload''s shape, so a later rendering change keeps reading old payloads. '
  '⚠ A FROZEN PAYLOAD FREEZES ITS DEFECTS: the Regenerate affordance and the '
  'pre-finalize no-tax-ledger prompt are load-bearing, not optional. '
  'DECISION 2 ON THIS SURFACE — the INSERT-NEW-VERSION half governs this header '
  '(regeneration is a new row, never a hard-overwrite UPDATE, which would lose '
  'included_reconciliation_event_ids and owner_header_at_generation history); the '
  'IMMUTABLE half governs pfin.monthly_report_account_snapshot and the frozen '
  'payload. ⚠ `draft -> final` promotion is itself an UPDATE, so Decision 2''s '
  'blanket "UPDATE blocked" was NEVER LITERALLY TRUE of this table under its own '
  'locked vocabulary. That cost is stated rather than softened; the mitigation is '
  'that the exemption is a MONOTONE TRANSITION ON ONE COLUMN — checkable in the '
  'trigger and in a battery leg — and not a column allowlist. The mutability window '
  'closes the moment generation_status leaves `draft`. '
  'pfin.fn_monthly_report_immutability is the whole rule and is NOT ROLE-CONDITIONAL: '
  'it binds `authenticated` and `service_role` identically, and it fences users_id '
  'and target_month in EVERY state including draft (a parent re-tenant would orphan '
  'the child snapshot rows from their original tenant — the Lock 12 catch). DELETE '
  'is blocked on every non-draft row; the draft branch it permits is DORMANT BY '
  'GRANT, because no role holds a DELETE grant here, and its revival condition is '
  'the first such grant. ⚠ RUNBOOK: this trigger is the ONLY APPLICABLE LAYER for an '
  'RLS-exempt writer and goes inert under session_replication_role = replica '
  '(ADR-011 Decision 4''s 2026-09-03 amendment puts the applicable-layer count at '
  'ZERO, not one, for such a writer), so any bulk-load or restore path touching this '
  'table OWES an explicit post-load validation step. A row may be INSERTed in the '
  '`draft` state ONLY (pfin.fn_monthly_report_assert_insert_state): a transition '
  'guard governs UPDATE and is silent on a row written straight into the target '
  'state, which would take the month''s single final slot without passing the '
  'authoring gate. UNIQUENESS is Lock 11''s partial index verbatim — UNIQUE '
  '(users_id, target_month) WHERE generation_status = ''final''. ⚠ A battery must '
  'REGENERATE THE SAME MONTH THREE TIMES, not twice: a two-regeneration leg passes '
  'against a defective three-column form of that index. target_month is CHECK-fenced '
  'to the first of its month, WITHOUT WHICH that index enforces one final per (user, '
  'DATE) rather than per MONTH. COMMENTARY is four NAMED TEXT COLUMNS, not a JSONB '
  'blob (Wave 6 Gate B option C; the Lock 14 forward-compat fence) — and that is a '
  'DIFFERENT question from the payload''s JSONB, which is a rendered artifact rather '
  'than settings-shaped user data; the two have opposite answers and that is not an '
  'inconsistency. Each commentary column is CHECK-length-bounded so P3''s bound is a '
  'real second layer rather than a single app-layer control, and the catch criterion '
  'is that a body one character over is rejected by the DB when submitted directly '
  'through PostgREST, not only by the app. commentary_disposition stores the '
  'authored-vs-skipped fact because FOUR EMPTY STRINGS ARE A LEGITIMATE AUTHORED '
  'STATE and a skip must be distinguishable from them; it is also the DB half of the '
  'complete-or-explicitly-skip gate, since the status CHECK requires it non-null on '
  'final and superseded. ADR-011 DECISION 3: this table REALIZES existing label #3 '
  'on included_reconciliation_event_ids and ALLOCATES NOTHING — read Decision 3 live; '
  'no count is stated here. users_id is NOT a Decision 3 instance (sole tenant anchor '
  'under a direct RLS predicate; a matched-tenant fence on the tenant anchor is the '
  'leg that cannot fail). RLS is the 090 standard — USING and WITH CHECK per verb, '
  'users_id = auth.uid(), with the ADR-029 / 025 aal2 step-up clause on the read AND '
  'write policies; there is NO DELETE policy and NO DELETE grant for authenticated. '
  'PRESENTATION BRIDGE: pending = draft; generated = the current final; a superseded '
  'version is never rendered in V1. JOINT-REVIEW-MANDATORY, and reviewed as ONE '
  'design unit with pfin.monthly_report_account_snapshot and the read-composition '
  'helper.';

comment on column pfin.monthly_report.users_id is
  'Sole tenant anchor. uuid NOT NULL DEFAULT auth.uid(), FK -> auth.users(id) ON '
  'DELETE CASCADE. Direct-owner RLS (users_id = auth.uid(), no JOIN). NOT an '
  'ADR-011 Decision 3 instance — the anchor IS the reference, so there is no second '
  'tenant fact to mismatch, and a matched-tenant fence here would be the leg that '
  'cannot fail (ADR-062 Decision 2). ⚠ IMMUTABLE IN EVERY STATE, draft included, '
  'enforced by pfin.fn_monthly_report_immutability: re-tenanting a parent would '
  'orphan its pfin.monthly_report_account_snapshot children from their original '
  'tenant, which is the Lock 12 chain-attack catch and is named inside Decision 3 '
  'label #4''s own text as part of that instance.';

comment on column pfin.monthly_report.target_month is
  'The month the report is ABOUT, stored as that month''s FIRST DAY and CHECK-fenced '
  'to it (monthly_report_target_month_is_month_start). ⚠ THE FENCE IS LOAD-BEARING, '
  'not tidiness: Lock 11''s partial UNIQUE keys on (users_id, target_month), so '
  'without a day anchor it would enforce one final report per (user, DATE) rather '
  'than per MONTH, and two dates inside one month would each take a final slot. '
  'IMMUTABLE IN EVERY STATE, draft included — it is an audit-load-bearing column '
  'under Lock 12''s parent-immutability extension, not a value column.';

comment on column pfin.monthly_report.generation_status is
  'The Lock 11 vocabulary. A row may be INSERTed as `draft` ONLY. The only UPDATE '
  'permitted outside the draft window is the single monotone transition `final -> '
  'superseded`, with nothing else changing in the same statement; `superseded` is '
  'TERMINAL. Enforced by pfin.fn_monthly_report_immutability, which is NOT '
  'role-conditional. The partial UNIQUE index reads this column, so its value '
  'decides whether a row occupies the month''s single final slot.';

comment on column pfin.monthly_report.data_as_of is
  'The as-of date the whole report was composed at — SERVER-DERIVED, never '
  'client-asserted (Lock 15; the on-demand path refuses a client-supplied as-of '
  'rather than ignoring it). It is the value threaded UNCHANGED into every callee of '
  'the composition helper: ONE CALL, ONE CLOCK. The payload echoes it back so a '
  'consumer can prove the threading. Distinct from generated_at (the wall-clock '
  'instant the payload was frozen) and from target_month (the month the report is '
  'about).';

comment on column pfin.monthly_report.generated_at is
  'The wall-clock instant the rendered payload was FROZEN. NULL while `draft` — a '
  'draft has no payload and therefore no generation instant — and NOT NULL on final '
  'and superseded, enforced by monthly_report_payload_by_status. ⚠ Distinct from '
  'updated_at, which stops moving when the draft window closes, and from created_at, '
  'which is when the draft row was written.';

comment on column pfin.monthly_report.owner_header_at_generation is
  'The owner-identification header string AS IT STOOD when this report was '
  'generated, copied here rather than joined live — it is part of R1''s frozen '
  'content, and the Lock 14 settings store carries no edit history, so a live join '
  'could not reproduce what the report actually said. REQUIRED as a column, NULLable '
  'as a value: it STAYS NULL for a report generated before the user set a header, '
  'and that state and its rendering are ruled (PM A-13, authorized at R10) — an '
  'unset header produces an in-app prompt and NO PDF line, never an empty line or a '
  'placeholder. Bounded at 120 characters, matching the settings-side bound.';

comment on column pfin.monthly_report.commentary_cash is
  'PRD §2.6.2 author commentary for the Cash sub-section. One of FOUR NAMED TEXT '
  'COLUMNS (Cash / Bonds / Marketable Securities / Alternatives) rather than a JSONB '
  'commentary blob — Wave 6 Gate B option C, under the Lock 14 forward-compat fence. '
  'CHECK-length-bounded so the app-layer bound has a real second layer beneath it: '
  'the catch criterion is that a body one character over is rejected by the DATABASE '
  'when submitted directly through PostgREST, not only 400ed by the app. The bound '
  'counts CHARACTERS (length()), and the app-side schema must count the same unit or '
  'the two layers disagree on multi-byte prose. An EMPTY STRING is a legitimate '
  'authored value — see commentary_disposition, which is what distinguishes it from '
  'a skip.';

comment on column pfin.monthly_report.commentary_bonds is
  'PRD §2.6.2 author commentary for the Bonds sub-section. See '
  'pfin.monthly_report.commentary_cash for the shared rules (four named columns, the '
  'CHECK bound and its catch criterion, empty-string-is-authored).';

comment on column pfin.monthly_report.commentary_marketable_securities is
  'PRD §2.6.2 author commentary for the Marketable Securities sub-section. ⚠ THE '
  'IDENTIFIER IS RULED: `commentary_marketable_securities`, not `commentary_equity` '
  '(V1.5 pre-flight ruling R11 (a)); the heading text is "Marketable Securities" per '
  'PRD §2.6.2 verbatim, F/CTO-ratified 2026-08-19 following ADR-058 Decision 7. The '
  'app-side key and the text-area heading follow this name. The rename is recorded '
  'as a CORRECTION TO GATE B''s RATIFY TEXT in the consolidated ADR that ships with '
  'this migration — it does not arrive as a schema fact with no register entry. See '
  'pfin.monthly_report.commentary_cash for the shared rules.';

comment on column pfin.monthly_report.commentary_alternatives is
  'PRD §2.6.2 author commentary for the Alternatives sub-section. See '
  'pfin.monthly_report.commentary_cash for the shared rules.';

comment on column pfin.monthly_report.commentary_disposition is
  'AUTHORED vs EXPLICITLY SKIPPED, per report. ⚠ IT CANNOT BE DERIVED BY LOOKING AT '
  'THE FOUR COMMENTARY COLUMNS, which is why it is stored: FOUR EMPTY STRINGS ARE A '
  'LEGITIMATE AUTHORED STATE, so a skip must be distinguishable from them. NULL '
  'while the author has done neither; required non-null on final and superseded '
  '(monthly_report_payload_by_status), which makes this column the DB-LAYER HALF of '
  'the complete-or-explicitly-skip gate — a report cannot be finalized without the '
  'author having either written or explicitly skipped, and that is enforced here, '
  'not only in the app. IT IS ALSO LOAD-BEARING BEYOND V1.5: a month whose '
  'commentary was explicitly SKIPPED does not count toward the V1.final '
  '"month of operation" gate, and this column is the fact that gate reads.';

comment on column pfin.monthly_report.rendered_payload is
  'THE FROZEN RENDERED REPORT (V1.5 pre-flight ruling R1 (A)) — the composition '
  'helper''s return, written ONCE at finalization. Every later read of a final '
  'report, in-app and PDF alike, reads THIS, never a recomposition. ⚠ The ruling''s '
  'own sketch said NOT NULL and that form is NOT BUILDABLE: the cron writes a draft '
  'row before any payload exists, so an unconditional NOT NULL would make the cron''s '
  'own INSERT fail. Realized as NULLable + monthly_report_payload_by_status, which '
  'permits NULL only while `draft` and requires this column, payload_schema_version, '
  'generated_at and commentary_disposition together on final and superseded — R1''s '
  '"written once, at finalization" stated as a constraint that CAN FAIL. Read-only '
  'once written: the immutability trigger governs this row whole-row, which is why '
  'the payload lives on the header rather than in a payload child that would owe its '
  'own RLS, grants, immutability trigger and Decision 3 disposition. LOSING SIDE, '
  'NAMED: the header row grows large and every `select *` carries the payload — '
  'readers needing only status or generated_at MUST project columns. ⚠ THE STORED '
  'ARTIFACT IS RENDERED VALUES, NEVER PDF BYTES; the first surface that persists PDF '
  'bytes creates a storage-class surface and is joint-review-mandatory at that PR. '
  '⚠ JSONB here does NOT touch Lock 14''s no-JSONB forward-compat fence, which '
  'governs the SETTINGS STORE; this is a Lock 11 audit-class artifact.';

comment on column pfin.monthly_report.payload_schema_version is
  'The rendering-contract version of rendered_payload. ⚠ BUMPED BY THE RENDERER, '
  'NEVER RE-DERIVED FROM THE PAYLOAD''S SHAPE — a §2.x rendering change keeps reading '
  'old payloads by branching on this number, which is the pfin.nav_daily lesson '
  '(a checkpoint series with no definition-version column cannot say which '
  'definition it froze). Required together with rendered_payload on final and '
  'superseded; NULL only while draft.';

comment on column pfin.monthly_report.included_reconciliation_event_ids is
  '⚠ ADR-011 DECISION 3 CANONICAL INSTANCE #3, carried UNREALIZED since ADR-011 '
  'authoring and DDL-REALIZED HERE. This migration REALIZES that label and ALLOCATES '
  'NOTHING; read Decision 3 live, no count is stated here. The reconciliation events '
  'included in this report''s tie-out. An INTEGER[] cannot carry an FK constraint on '
  'its elements, so there is NO declared FK on this column BY CONSTRUCTION, and '
  'matched-tenant validation is supplied by the BEFORE INSERT OR UPDATE trigger '
  'pfin.fn_monthly_report_matched_event_tenants — the array form Decision 3 reserves '
  'for exactly this case. ⚠ THE FENCE CHAIN-RESOLVES: pfin.reconciliation_event has '
  'NO users_id column (it was created with account_id as its sole anchor, which is '
  'why Decision 3 label #1 on its junction table is classed matched-ACCOUNT), so each '
  'element''s tenant is resolved through reconciliation_event.account_id -> '
  'pfin.account.users_id and compared to this row''s users_id. ⚠ THE FENCE IS '
  'CORRECT, MANDATORY AND DORMANT — BUT NOT BECAUSE THE WRITE PATH IS CLOSED: a '
  'plain authenticated caller can INSERT into pfin.reconciliation_event through '
  'PostgREST TODAY, because that table carries an INSERT '
  'grant AND an INSERT policy for authenticated (measured 2026-09-05). WHAT IS '
  'ABSENT is an application path: no database function and no app or worker surface '
  'writes pfin.reconciliation_event, and no V1.5 surface populates THIS column, so '
  'in the shipped product the array is empty on every row and the fence never fires. '
  '⚠ THE DORMANCY IS THEREFORE A PROPERTY OF THE PRODUCT PATH, NOT OF THE GRANTS, '
  'and the fence IS behaviourally reachable from a two-tenant battery, which is not '
  'the product. REVIVAL CONDITION: the first application or worker surface that '
  'writes pfin.reconciliation_event together with the first surface that populates '
  'this column, expected at the V1.6 statement tie-out (ADR-035) — the instance is '
  'deferred WITH a consumer, not orphaned. Defaults to the empty array rather than '
  'NULL, so the fence validates a guaranteed-non-null array and needs no NULL branch.';

comment on column pfin.monthly_report.created_at is
  'When the draft row was written. On a regeneration chain this is how the '
  'supersession instant is recoverable: the SUCCESSOR row''s created_at is when the '
  'incumbent was superseded — this table records no supersession timestamp of its '
  'own, by design.';

comment on column pfin.monthly_report.updated_at is
  '⚠ MEANINGFUL ONLY WITHIN THE DRAFT WINDOW. pfin.fn_refresh_updated_at is attached '
  'with a `when (old.generation_status = ''draft'')` clause, so it CANNOT fire once '
  'the row leaves draft — on a final-immutable row an unconditional refresh would be '
  'either dead code or a hole, and this is neither. CONSEQUENCE, so it is not read '
  'as a bug: on a final or superseded row this column holds the time of the LAST '
  'DRAFT EDIT, not the time of finalization (see generated_at) or of supersession '
  '(see the successor row''s created_at).';

comment on constraint monthly_report_payload_by_status on pfin.monthly_report is
  'The buildable realization of V1.5 pre-flight ruling R1''s `rendered_payload JSONB '
  'NOT NULL` sketch. `draft` permits NULL on all four; `final` and `superseded` '
  'require rendered_payload, payload_schema_version, generated_at AND '
  'commentary_disposition together. The unconditional NOT NULL the ruling sketched '
  'is not buildable because the cron writes a draft row before any payload exists, '
  'so its own INSERT would fail. This states the same guarantee — written once, at '
  'finalization — as a constraint that CAN FAIL. Its commentary_disposition leg is '
  'the DB half of the complete-or-explicitly-skip gate. Role-agnostic table CHECK: '
  'service_role bypasses RLS but not CHECK.';

comment on constraint monthly_report_target_month_is_month_start on pfin.monthly_report is
  'target_month must be the first day of its month. LOAD-BEARING, not tidiness: Lock '
  '11''s partial UNIQUE keys on (users_id, target_month), so without this fence it '
  'would enforce one final report per (user, DATE) instead of per MONTH and two '
  'dates inside one month would each take a final slot. This constraint is what '
  'makes the ratified index mean what Lock 11 says it means.';

-- ----------------------------------------------------------------------------
-- RLS — the 090 standard: USING **and** WITH CHECK per verb, users_id = auth.uid(),
-- explicit grants, with the 025 aal2 step-up backstop clause AND-ed into the read
-- AND write policies (Sec F-9). grant-before-RLS shape (PR #106): the role needs
-- the table GRANT even with RLS enabled — RLS filters rows, the GRANT lets the role
-- reach the table at all.
-- ⚠ NO DELETE POLICY AND NO DELETE GRANT (R4 (a)): `authenticated` holds INSERT for
-- the on-demand path and NEVER DELETE. PRD §2.6.4 commits to indefinite retention;
-- user-initiated deletion is explicitly V2+.
-- ----------------------------------------------------------------------------
alter table pfin.monthly_report enable row level security;

create policy monthly_report_select on pfin.monthly_report
  for select to authenticated
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

create policy monthly_report_insert on pfin.monthly_report
  for insert to authenticated
  with check (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

create policy monthly_report_update on pfin.monthly_report
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

comment on policy monthly_report_select on pfin.monthly_report is
  'SELECT: owner-only, users_id = auth.uid() (direct anchor, no JOIN) AND the ADR-029 '
  '/ 025 aal2 step-up backstop. The aal2 conjunct requires a reader who DECLARED '
  'mfa_policy totp/passkey to present an aal2 JWT; a ''none'' or missing-settings-row '
  'reader is unaffected (coalesce(...,''none'') — the lazy-provisioning null-lockout '
  'guard). It gates on the READER''s own declared policy, never on the row, and is '
  'never a blanket aal2. ⚠ CATCH CRITERION: a totp/passkey-enrolled caller presenting '
  'a BELOW-aal2 JWT lands on a refusal leg that is DIFFERENT from the cross-tenant '
  'leg — a battery testing only cross-tenant passes with this clause absent, which is '
  'the specific way an omitted aal2 clause stays invisible.';

comment on policy monthly_report_insert on pfin.monthly_report is
  'INSERT: WITH CHECK users_id = auth.uid() AND the 025 aal2 clause (the 090 standard '
  '— USING and WITH CHECK per verb; INSERT has no USING). authenticated needs INSERT '
  'for the on-demand generation path, which runs under the user''s own session so the '
  'session IS the tenant binding. ⚠ THE POLICY DOES NOT CONSTRAIN THE STATE: a row '
  'POSTed straight in as `final` would satisfy this policy and take the month''s '
  'single final slot without passing the authoring gate. That is closed by '
  'pfin.fn_monthly_report_assert_insert_state, which admits `draft` only — a policy '
  'and a trigger answering two different questions, deliberately.';

comment on policy monthly_report_update on pfin.monthly_report is
  'UPDATE: USING and WITH CHECK both carrying users_id = auth.uid() AND the 025 aal2 '
  'clause (the 090 standard). USING decides which rows are visible to update; WITH '
  'CHECK decides what the updated row may look like — the pair is what stops an '
  'owner-visible row being updated INTO another tenant. ⚠ THE POLICY IS NOT THE '
  'IMMUTABILITY RULE. It says WHOSE rows may be updated; '
  'pfin.fn_monthly_report_immutability says WHICH updates are legal, and the trigger '
  'is NOT role-conditional, so service_role — which bypasses this policy entirely — '
  'is bound by exactly the same monotone rule. There is deliberately NO DELETE '
  'POLICY: authenticated holds no DELETE grant either, so DELETE default-denies at '
  'the ACL before RLS is consulted.';

grant select, insert, update on pfin.monthly_report to authenticated;
grant select, insert, update on pfin.monthly_report to service_role;

-- No DELETE and no TRUNCATE to any role. The immutability trigger permits a draft
-- DELETE (R4 (a) words it that way), but no grant reaches that branch — DORMANT BY
-- GRANT, revival condition = the first DELETE grant on this table.
revoke truncate on pfin.monthly_report from public;

-- ----------------------------------------------------------------------------
-- Fence 1 — THE IMMUTABILITY TRIGGER (R4 (B), Sec's four conditions (a)–(d)).
-- ONE trigger, NOT role-conditional. There is no role test anywhere in this body,
-- by design: the realistic later defect is an early return for service_role added
-- to make the cron's supersession UPDATE work, and a battery leg run only as
-- `authenticated` would pass with that exemption in place.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_monthly_report_immutability()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_old_rest jsonb;
  v_new_rest jsonb;
begin
  -- ---- DELETE (condition (a)) -------------------------------------------------
  -- Decision 2 is a TWO-VERB rule. Clauses (i)-(iii) below govern UPDATE only, so
  -- DELETE is handled first and explicitly — restating a two-verb rule with one
  -- verb is the enumeration-stops-one-short shape this branch exists to avoid.
  if tg_op = 'DELETE' then
    if old.generation_status <> 'draft' then
      raise exception
        'pfin.monthly_report DELETE refused: a % report is retained indefinitely (PRD §2.6.4; ADR-011 Decision 2). Only a draft may be deleted, and no role holds a DELETE grant on this table.',
        old.generation_status;
    end if;
    return old;
  end if;

  -- ---- The tenant anchor and the audit-load-bearing month, EVERY state --------
  -- Lock 12's parent-immutability extension, named inside Decision 3 label #4's own
  -- text. Re-tenanting a parent orphans its snapshot children from their original
  -- tenant, so this is fenced in the draft window too — it is NOT a value column.
  if new.users_id is distinct from old.users_id
     or new.target_month is distinct from old.target_month
  then
    raise exception
      'pfin.monthly_report UPDATE refused: users_id and target_month are immutable in EVERY state including draft (Lock 12 parent-immutability extension; ADR-011 Decision 3 label #4). Re-tenanting a report would orphan its account-snapshot children from their original tenant.';
  end if;

  -- ---- (i) the draft window: anything else goes -------------------------------
  if old.generation_status = 'draft' then
    return new;
  end if;

  -- ---- (d) superseded is TERMINAL ---------------------------------------------
  if old.generation_status = 'superseded' then
    raise exception
      'pfin.monthly_report UPDATE refused: `superseded` is TERMINAL (V1.5 pre-flight ruling R4 (d)). A superseded report is never revived, re-finalized or re-drafted; regeneration writes a NEW row.';
  end if;

  -- ---- (ii) the ONE permitted transition, and NOTHING ELSE in the statement ----
  -- old.generation_status is `final` here, by elimination.
  if new.generation_status is distinct from 'superseded' then
    raise exception
      'pfin.monthly_report UPDATE refused: a `final` report admits exactly ONE transition, final -> superseded (V1.5 pre-flight ruling R4 (ii)). Attempted target: %.',
      new.generation_status;
  end if;

  -- STRUCTURAL, not a column allowlist: compare the whole row minus the one column
  -- the transition is allowed to move. A column added to this table by a future
  -- migration is therefore fenced automatically, where an allowlist would silently
  -- admit it. (updated_at cannot drift here either — its refresh trigger carries a
  -- `when (old.generation_status = 'draft')` clause and does not fire on this path.)
  v_old_rest := to_jsonb(old) - 'generation_status';
  v_new_rest := to_jsonb(new) - 'generation_status';
  if v_new_rest is distinct from v_old_rest then
    raise exception
      'pfin.monthly_report UPDATE refused: the final -> superseded transition may change generation_status and NOTHING ELSE (V1.5 pre-flight ruling R4 (iii)). The frozen payload, the commentary, the owner header and every other column are read-only once the draft window closes.';
  end if;

  return new;
end;
$$;

revoke execute on function pfin.fn_monthly_report_immutability() from public;

comment on function pfin.fn_monthly_report_immutability() is
  'BEFORE UPDATE OR DELETE immutability fence on pfin.monthly_report — the whole of V1.5 pre-flight ruling R4 (B) with Sec''s four conditions (SELF-345 / A1; ADR-011 Decision 2 / Lock 11; Lock 12''s parent-immutability extension). SECURITY INVOKER, set search_path = '''' — inspects OLD/NEW and raises; NOT a SECURITY DEFINER allowlist entry (read ADR-011 Decision 9 live; no size is stated here). ⚠ IT IS NOT ROLE-CONDITIONAL, AND THERE IS NO ROLE TEST ANYWHERE IN THE BODY, BY DESIGN: the same monotone rule binds `authenticated` and `service_role` identically, and the battery proves refusal UNDER BOTH. The realistic later defect is an early return for service_role added to make the cron''s supersession UPDATE work — and a leg run only as authenticated PASSES with that exemption in place. THE RULE: (a) DELETE is refused on every non-draft row — Decision 2 is a TWO-VERB rule and the UPDATE clauses below govern only UPDATE, so restating it with one verb is the enumeration-stops-one-short shape this branch exists to avoid; the draft DELETE it permits is DORMANT BY GRANT, since no role holds DELETE here, and its revival condition is the first such grant. (b) users_id and target_month are refused in EVERY state INCLUDING DRAFT — re-tenanting a parent orphans its pfin.monthly_report_account_snapshot children from their original tenant, which is the Lock 12 chain-attack catch and is named inside Decision 3 label #4''s own text as half of that instance. (i) inside the draft window any other column may change. (ii) on a `final` row the ONLY permitted UPDATE is generation_status -> ''superseded'', with NOTHING ELSE changing in the same statement. (iii) `superseded` is TERMINAL. ⚠ "NOTHING ELSE" IS TESTED STRUCTURALLY, NOT AS A COLUMN ALLOWLIST: the body compares to_jsonb(new) - ''generation_status'' against to_jsonb(old) - ''generation_status'', so A COLUMN ADDED TO THIS TABLE BY A FUTURE MIGRATION IS FENCED AUTOMATICALLY where an allowlist would silently admit it. ⚠ THE COST DECISION 2 PAYS HERE, STATED RATHER THAN SOFTENED: `draft -> final` promotion is itself an UPDATE, so Decision 2''s blanket "UPDATE blocked" was never literally true of this table under its own locked vocabulary. The mitigation is that the exemption is a MONOTONE TRANSITION ON ONE COLUMN — checkable here and in a battery leg — and not a column allowlist. ⚠ RUNBOOK LINE, REQUIRED: for an RLS-exempt writer this trigger is the ONLY APPLICABLE LAYER, and per ADR-011 Decision 4''s 2026-09-03 amendment it goes INERT under session_replication_role = replica — that amendment puts the applicable-layer count for such a writer at ZERO, not at one. ANY BULK-LOAD OR RESTORE PATH TOUCHING THIS TABLE OWES AN EXPLICIT POST-LOAD VALIDATION STEP. The GUC is superuser-context and is denied to both authenticated and service_role, so the exposure is operational rather than adversarial.';

create trigger monthly_report_immutability
  before update or delete on pfin.monthly_report
  for each row execute function pfin.fn_monthly_report_immutability();

-- ----------------------------------------------------------------------------
-- Fence 2 — LEGAL INSERT STATES (R4 (c)). A transition guard governs UPDATE and is
-- SILENT on a row written directly in the target state. With authenticated holding
-- INSERT, a row could be POSTed straight in as `final`, taking the month's single
-- final slot without ever passing the author-before-generate gate.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_monthly_report_assert_insert_state()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.generation_status <> 'draft' then
    raise exception
      'pfin.monthly_report INSERT refused: a report row may be INSERTed in the `draft` state ONLY (V1.5 pre-flight ruling R4 (c)). Attempted: %. A row written straight in as `final` would take the month''s single final slot without passing the author-before-generate gate; finalization is an UPDATE from draft, and supersession is an UPDATE from final.',
      new.generation_status;
  end if;
  return new;
end;
$$;

revoke execute on function pfin.fn_monthly_report_assert_insert_state() from public;

comment on function pfin.fn_monthly_report_assert_insert_state() is
  'BEFORE INSERT state fence on pfin.monthly_report (V1.5 pre-flight ruling R4 (c); SELF-345 / A1). SECURITY INVOKER, set search_path = '''' — NOT a SECURITY DEFINER allowlist entry (read ADR-011 Decision 9 live). Admits generation_status = ''draft'' and NOTHING ELSE. ⚠ WHY A SEPARATE FENCE FROM THE IMMUTABILITY TRIGGER, WHICH IS THE WHOLE POINT: a transition guard constrains UPDATE and is SILENT on a row written directly in the target state. `authenticated` holds INSERT for the on-demand generation path, so without this a caller could POST a row straight in as `final` — satisfying the RLS WITH CHECK, satisfying the immutability trigger (which never runs on INSERT), and TAKING THE MONTH''S SINGLE `final` SLOT under the Lock 11 partial UNIQUE without ever passing the author-before-generate gate. Legal STATES and legal TRANSITIONS are two different constraints and both are needed. NOT role-conditional: the cron and the on-demand endpoint both write drafts, so neither needs an exemption, and there is no role test here.';

create trigger monthly_report_assert_insert_state
  before insert on pfin.monthly_report
  for each row execute function pfin.fn_monthly_report_assert_insert_state();

-- ----------------------------------------------------------------------------
-- Fence 3 — statement-level TRUNCATE block. Row-level triggers do NOT fire on
-- TRUNCATE, so a role holding it could wipe every report without tripping Fence 1.
-- ⚠ Convention-inherited (004 / 031 / 054 / 107), not named by this issue's AC —
-- recorded so a reviewer does not read it as an undocumented addition.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_monthly_report_block_truncate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.monthly_report TRUNCATE blocked (ADR-011 Decision 2 / Lock 11). PRD §2.6.4 commits to indefinite retention; the report history cannot be wiped.';
end;
$$;

revoke execute on function pfin.fn_monthly_report_block_truncate() from public;

comment on function pfin.fn_monthly_report_block_truncate() is
  'BEFORE TRUNCATE (statement-level) fence on pfin.monthly_report (ADR-011 Decision 2 / Lock 10 mod #8 pattern; SELF-345 / A1). SECURITY INVOKER, set search_path = '''' — NOT a SECURITY DEFINER allowlist entry (read ADR-011 Decision 9 live). Closes the TRUNCATE bypass: row-level UPDATE/DELETE triggers do NOT fire on TRUNCATE, so the row-level immutability fence cannot see a table-wipe. Paired with REVOKE TRUNCATE FROM PUBLIC so a broad platform default cannot reintroduce the privilege; the trigger is the regardless-of-grant guarantee. The message is deliberately distinct from the row-level fence''s so a battery can assert which fired. ⚠ CONVENTION-INHERITED (004 / 031 / 054 / 107) rather than named by this issue''s AC — recorded so it is not read as an undocumented addition; PRD §2.6.4''s indefinite-retention commitment is the substantive reason it belongs here.';

create trigger monthly_report_block_truncate
  before truncate on pfin.monthly_report
  for each statement execute function pfin.fn_monthly_report_block_truncate();

-- ----------------------------------------------------------------------------
-- Fence 4 — ADR-011 DECISION 3 LABEL #3, DDL-realized here, DORMANT.
-- Array-element matched-tenant. An INTEGER[] cannot carry an FK on its elements, so
-- this trigger is the whole of the referential AND the tenant guarantee.
-- ⚠ It chain-resolves each element through reconciliation_event.account_id ->
-- pfin.account.users_id, because pfin.reconciliation_event HAS NO users_id column —
-- see the DECISION 3 header block for the finding this corrects.
-- ⚠ SECURITY INVOKER, so `not exists` is true both when an element genuinely
-- belongs to another tenant and when the referenced row is merely INVISIBLE under
-- the caller's RLS. Both outcomes are refusals, and the message says so rather than
-- claiming to have distinguished them.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_monthly_report_matched_event_tenants()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_event_id integer;
begin
  -- The column is NOT NULL DEFAULT '{}', so there is no NULL-array branch to get
  -- wrong. An empty array iterates zero times and passes — which is the V1.5 state
  -- for every row, and is exactly why this fence is DORMANT rather than merely
  -- untested.
  foreach v_event_id in array new.included_reconciliation_event_ids loop
    if not exists (
      select 1
        from pfin.reconciliation_event e
        join pfin.account a on a.account_id = e.account_id
       where e.event_id = v_event_id
         and a.users_id = new.users_id
    ) then
      raise exception
        'cross-tenant monthly_report reconciliation reference rejected: reconciliation_event_id % does not resolve to an account owned by users_id % (ADR-011 Decision 3 #3 array-element matched-tenant fence). The element is either absent, owned by another tenant, or invisible under this caller''s RLS.',
        v_event_id, new.users_id;
    end if;
  end loop;
  return new;
end;
$$;

revoke execute on function pfin.fn_monthly_report_matched_event_tenants() from public;

comment on function pfin.fn_monthly_report_matched_event_tenants() is
  'BEFORE INSERT OR UPDATE array-element matched-tenant fence on pfin.monthly_report.included_reconciliation_event_ids — ADR-011 DECISION 3 CANONICAL INSTANCE #3, carried UNREALIZED since ADR-011 authoring and DDL-REALIZED at this migration (V1.5 pre-flight ruling R5 (a)). THIS REALIZES AN EXISTING LABEL AND ALLOCATES NOTHING; read Decision 3 live, no count is stated here. An INTEGER[] cannot carry an FK constraint on its elements, so this trigger is the WHOLE of both the referential and the tenant guarantee — the array form Decision 3 reserves for precisely this case, which is why the column carries no declared FK by construction rather than by omission. FENCE PATTERN: the referring row has its own users_id (P1''s condition) but the REFERENCED row has no tenant column, so each element''s tenant is CHAIN-RESOLVED through reconciliation_event.account_id -> pfin.account.users_id and compared to new.users_id. ⚠ THAT IS NOT WHAT LABEL #3''s ENTRY DESCRIBES, AND THE DIVERGENCE IS DELIBERATE: the entry says "validates every array element''s reconciliation_event.users_id" — pfin.reconciliation_event HAS NO users_id COLUMN. It was created with account_id as its sole anchor, which is why Decision 3 label #1 on its junction table is classed matched-ACCOUNT rather than matched-tenant. The entry''s parenthetical predates that table. The instance, its label and its target are unchanged; the mechanism description is corrected by an AMENDMENT beneath the entry in this same PR, never by editing the dated entry itself. ⚠ THE FENCE IS CORRECT, MANDATORY AND DORMANT — BUT THE DORMANCY IS A PROPERTY OF THE PRODUCT PATH, NOT OF THE GRANTS, AND THE DIFFERENCE DECIDES WHAT A BATTERY CAN ASSERT. MEASURED 2026-09-05 rather than inherited: pfin.reconciliation_event carries an INSERT GRANT to authenticated AND an INSERT POLICY for authenticated, so a plain authenticated caller can POST a reconciliation event for their own account through PostgREST today. What is ABSENT is an application path — no database function and no app or worker surface writes that table, and no V1.5 surface populates included_reconciliation_event_ids at all — so in the shipped product the array is empty on every row and this fence never fires. CONSEQUENTLY THE FENCE IS BEHAVIOURALLY REACHABLE FROM A TEST, because a battery is not the product: a two-tenant fixture can insert an event under each tenant and attempt to place tenant B''s event_id into tenant A''s array, and this fence raises (verified at authoring against a clean scratch apply — a bogus element id is rejected, so the fence is functional and not merely present). REVIVAL CONDITION, and it is the PRODUCT-PATH one: the first application or worker surface that writes pfin.reconciliation_event together with the first surface that populates the array, expected at the V1.6 statement tie-out (ADR-035) — the instance is deferred WITH a consumer, not orphaned, which is why retiring it was declined. ⚠ ITS PAIRED TEST LEG IS RULED CONSTRUCTION-ONLY AND SHIPS THAT WAY: it asserts this trigger exists, is attached to that column, and carries the matched-tenant body. ⚠ THAT RIDER''S OWN STATED REASON — that nothing can populate the array — IS THE PREMISE FALSIFIED ABOVE, and its PURPOSE (no later reader mistakes a leg that cannot fail for coverage) is served better by a leg that actually fires. A firing leg is RECOMMENDED ALONGSIDE the construction-only one, never as a substitute for it; amending the rider is Sec''s and F/CTO''s, not this migration''s. ⚠ RUNNING SECURITY INVOKER, `not exists` is true both when an element genuinely belongs to another tenant AND when the referenced row is merely invisible under the caller''s RLS; both are refusals and the message says so rather than claiming to have distinguished them. When the revival condition arrives, whoever adds the writer should re-derive this comment rather than re-read it.';

create trigger monthly_report_matched_event_tenants
  before insert or update on pfin.monthly_report
  for each row execute function pfin.fn_monthly_report_matched_event_tenants();

-- ----------------------------------------------------------------------------
-- updated_at refresh — attached WITH A WHEN CLAUSE so it can fire only inside the
-- draft window (PM D-6, ratified at R4). On a final-immutable row an unconditional
-- refresh would be dead code or a hole; this is neither.
-- ⚠ BEFORE UPDATE triggers fire in ALPHABETICAL trigger-name order, so
-- `monthly_report_immutability` runs BEFORE `monthly_report_refresh_updated_at` —
-- the fence raises before updated_at is touched. Verified at authoring.
-- fn_refresh_updated_at (001) is a PRE-EXISTING SECURITY DEFINER allowlist entry;
-- ATTACHING an existing entry is not an allowlist event.
-- ----------------------------------------------------------------------------
create trigger monthly_report_refresh_updated_at
  before update on pfin.monthly_report
  for each row
  when (old.generation_status = 'draft')
  execute function pfin.fn_refresh_updated_at();

-- ----------------------------------------------------------------------------
-- No separate users_id index: the partial UNIQUE above is partial and cannot serve
-- the RLS predicate on draft or superseded rows, so a plain btree on
-- (users_id, target_month) carries the owner-scoped reads and the P5 report list.
-- ----------------------------------------------------------------------------
create index if not exists monthly_report_users_id_target_month_idx
  on pfin.monthly_report (users_id, target_month);

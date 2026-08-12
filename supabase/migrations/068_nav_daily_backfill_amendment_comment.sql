-- ============================================================================
-- Migration: COMMENT-ONLY correction to pfin.nav_daily's table comment (054).
--   Amends the one clause the SELF-217 ratify falsifies — "no historical
--   backfill in V1.1" — and states, in the catalog, the distinction that
--   amendment turns on. Authors NO function, NO table, NO column, NO policy,
--   NO grant, NO trigger. The only executable statement below is one
--   `comment on table`.
--   Linear SELF-217 (V1.1; PRD §2.1.2.a + Appendix B flag (c); §2.1.3 is the
--   requirement it serves). F/CTO-ratified 2026-08-12. ADR-053 (this PR).
--   apply-migration procedure applied. JOINT-REVIEW-MANDATORY (Sec veto
--   surface): it edits 054's own surface — which 054's text requires — on a
--   financial-calculation table, ahead of a new write path into it.
--
-- ----------------------------------------------------------------------------
-- WHY A MIGRATION AT ALL, AND WHY ONLY HALF THE CORRECTION LIVES HERE.
--   The same FORWARD-ONLY claim appears TWICE in 054, in two representations,
--   and the vehicle follows WHERE THE TEXT LIVES:
--     · `comment on table pfin.nav_daily` — HAS a database representation. It
--       ships to pg_description and is read at `\d+` by someone with NO REPO IN
--       FRONT OF THEM. It can only change by issuing new SQL. THAT IS THIS FILE.
--       054 is merged and applied; its file is NOT edited.
--     · 054's file-header block (its FORWARD-ONLY paragraph) — has NO database
--       representation, so no migration could correct it. It is corrected IN
--       PLACE in the same PR, as a DATED SUPERSESSION NOTE PLACED BESIDE the
--       original rather than a rewrite of it: that line records a RATIFIED
--       position, and rewriting a ratified record destroys the evidence of what
--       was believed when. A no-op "correction migration" would have left the
--       false text exactly where readers actually look.
--   ⚠ ONE LINE IN 054 IS DELIBERATELY LEFT UNTOUCHED BY BOTH HALVES: the dated
--   "F/CTO-ratified 2026-08-02: Option B ... + forward-only + numbering 054"
--   summary. That is a DATED RECORD OF A RATIFY, not a live claim, and the
--   don't-retro-edit-dated-blocks rule applies to it exactly as ADR-016
--   Decision 4 applies it elsewhere. Do not "finish the job" by editing it.
--
-- ----------------------------------------------------------------------------
-- Numbering: 068 follows 067 (fn_nav_series_inflation_adjusted), taken at
--   authoring time. Depends on 054 (the table whose comment it replaces) and on
--   nothing else. No downstream migration depends on 068. Order-independent
--   after 054. Replay onto a tree without 054 fails loud on the missing
--   relation, which is correct — there would be no comment to correct.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — NOT APPLICABLE IN THE USUAL SENSE, stated rather than
--   omitted so the omission is not read as an oversight. This migration authors
--   NO function, so there is no INVOKER-vs-DEFINER choice to make. THE SECURITY
--   DEFINER ALLOWLIST IS NOT TOUCHED — read ADR-011 Decision 9 live for its
--   membership; no count is restated here. No ACL changes: 054's grants
--   (`select` to authenticated, `insert` + column-level `select (users_id,
--   nav_date)` to service_role) are untouched, and `comment on` requires
--   ownership, never a grant.
--
-- ----------------------------------------------------------------------------
-- WHAT CHANGED IN THE CLAIM, AND — MORE IMPORTANTLY — WHAT DID NOT.
--   FALSIFIED, and replaced: "FORWARD-ONLY (ratified): accumulates from first
--     run; no historical backfill in V1.1."
--   STANDS, UNCHANGED, and is restated in the new text so it cannot be lost in
--     the amendment: the prohibition on RECOMPUTED history. 050's TEMPORAL
--     CONSTRAINT — historical NAV must not be recomputed on the fly — is quoted
--     immediately above the amended clause in the same comment and is not
--     touched. A seeded all-accounts backfill via fn_compute_nav(d, false) is
--     STILL not authorized by anything in this PR.
--   >> THE AMENDMENT IS ABOUT PROVENANCE, NOT ABOUT DATES. The forward-only rule
--      was a rule against FABRICATION, not against IMPORT. 062's header records
--      why fabrication is the hazard: the valuation path values an unpriced
--      asset at zero silently, so a recomputed historical point is "a CONFIDENT,
--      PLAUSIBLE, WRONG NUMBER" — indistinguishable from genuine wealth
--      accumulation and invisible to every assertion on the value. An imported
--      figure has none of that pathology: it was measured contemporaneously, by
--      the system that actually held the positions, against prices current at
--      the time. <<
--   AND THE SUBSTRATE ALREADY EXPECTED THIS, which is why this is an amendment
--     and not a reversal. 054's own write-path block names "future backfills" as
--     a sanctioned INSERT path; so does the `comment on function
--     fn_nav_daily_assert_computed_for` — a CATALOG comment, already shipped.
--     062's header states the temporally-sound path "is a BOUNDED backfill that
--     WRITES checkpoints, not an on-read recompute", and that its own contract is
--     UNCHANGED by that decision. Nothing in 062 or 067 is touched by this PR.
--
-- ----------------------------------------------------------------------------
-- ⚠ THE IMPORT PATH INHERITS A FENCE THAT IS VACUOUS ON IT — recorded HERE, in
--   the migration that authorizes the path, because the fence's own comment
--   claims a property that would otherwise become false for a class of rows.
--   fn_nav_daily_assert_computed_for compares the transaction-local GUC
--   `app.nav_computed_for` to new.users_id. Its catalog comment states what that
--   buys: the GUC is "captured from auth.uid() AS THE DATABASE RESOLVED IT,
--   never from the application's own variable ... it proves the row's tenant IS
--   the tenant whose data was actually served".
--   >> A BACKFILL SERVES NO READ. There is no impersonated block and no
--      auth.uid() for the GUC to be captured FROM, so a script that sets it from
--      its own target-user variable passes the trigger as a TAUTOLOGY — it
--      asserts its own variable against itself — while the catalog goes on
--      claiming a property that no longer holds for those rows. <<
--   REMEDY, BOUND INTO THE SELF-217 AC (AC7) rather than into this file, because
--   it is a property of the WRITER and this migration authors no writer: the
--   import script must establish an impersonation binding for the target user,
--   READ auth.uid() BACK FROM THE DATABASE, and set the GUC from THAT value —
--   the sequence run_nav_daily.py already performs. Then the fence means the
--   same thing on both paths and the catalog claim stays true for every row.
--   ⚠ NOTHING IN THE DATABASE ENFORCES THIS. The trigger cannot tell a
--   DB-resolved GUC from an app-supplied one; that is precisely why the
--   obligation is written down in two places and asserted by QA.
--
-- ----------------------------------------------------------------------------
-- IRREVERSIBILITY IS UNCHANGED AND NOW REACHES A SECOND WRITER (one-way door).
--   054's fn_nav_daily_block_mutation blocks UPDATE and DELETE for EVERY role
--   including service_role — a DB trigger, which service_role does NOT bypass
--   the way it bypasses RLS — and TRUNCATE is blocked besides. 054's own
--   reasoning ("(1) IRREVERSIBILITY ... The blast radius of a write-tenant bug
--   is permanent") is not weakened by this amendment; it now covers the import
--   path too. An imported row written at a wrong value, date, or tenant is
--   removable ONLY by a migration.
--   That is why the SELF-217 AC binds dry-run-by-default, a single transaction,
--   an explicitly bounded date range with no defaults, and
--   ON CONFLICT (users_id, nav_date) DO NOTHING so a re-run can never overwrite
--   a cron checkpoint. None of those make it reversible; they reduce the chance
--   of needing reversal.
--
-- ----------------------------------------------------------------------------
-- REGENERATE-AND-DIFF PROVENANCE (the 052 shape; the comment literal below was
--   NOT retyped). The statement was extracted verbatim from 054, ONE anchored
--   substitution was applied, and the result was proven to contain the original
--   byte-for-byte outside the replaced span:
--     · anchor matched EXACTLY ONCE in 054 (asserted; more than one match would
--       mean the anchor is not unique, zero would mean the source drifted);
--     · CONTAINMENT: 518 bytes of prefix and 2149 bytes of suffix are
--       byte-identical to 054's statement, with ONE contiguous replaced region;
--     · single-quote parity is even on every line of the regenerated literal.
--   ⚠ Containment is asserted rather than a diff-region count, deliberately: a
--   region count characterises only what CHANGED, while containment makes a
--   positive claim about everything that did NOT.
--   REMAINING VERIFICATION IS BACKEND'S AND QA'S, and neither is discharged
--   here: apply-in-transaction-and-roll-back proves the literal PARSES, and
--   reading it back through obj_description proves what the CATALOG RENDERS —
--   which is what actually ships, and where a doubled '' leaking into rendered
--   text would be invisible in source.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; the catalogued
--   numbered list is NOT restated here and no count is stated. Decision 4 read
--   VERBATIM at the canonical anchor before drafting, 2026-08-12, at 58ca6ed.)
--   (i)   Instance-numbering: nothing appended, reordered, or renumbered.
--   (ii)  Layer-attribution: this migration issues one catalog comment. It is
--         NOT the PDF-worker container credential audit, NOT the code-layer
--         SUPABASE_SERVICE_ROLE_KEY allowlist fence, and NOT the app→worker
--         credential-admission network surface. No catalogued instance's layer
--         attribution moves; no surface becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is REFERENCED, not restated. This
--         file is not the canonical anchor and never will be.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED set are DIFFERENT SETS and are
--   NOT reconciled here. This migration touches neither.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — +0. This migration creates NO
--   table, NO column, and NO FK-shaped reference of any kind. A comment has
--   nothing to matched-tenant-validate, and 054's own non-membership is
--   unchanged: users_id remains its SOLE tenant anchor under a direct-owner RLS
--   predicate, with no second anchor to mismatch.
--   AUTHORING-TIME PROVENANCE (dated, not live state — read ADR-011 Decision 3's
--   body live, it grows and its labels are non-contiguous): read verbatim at the
--   canonical anchor on 2026-08-12, the family stood at SIXTEEN LABELED
--   INSTANCES (#1–#16), THIRTEEN DDL-REALIZED — #5 DROPPED at 048, #3 + #4
--   canonically-locked but DDL-deferred. Recorded here as a dated observation
--   ONLY; NOT restated in the comment below, and not to be copied forward.
--
-- ----------------------------------------------------------------------------
-- LEDGER DELTAS (all confirmed FLAT, stated as deltas): §10 catalogued
--   instances +0 · SECURITY DEFINER allowlist +0 (no function authored) ·
--   ADR-011 Decision 3 family +0 · SD matrix — NO expansion · grants unchanged ·
--   RLS policies unchanged · triggers unchanged. Sec joint-review is MANDATORY
--   notwithstanding the flat ledgers: this edits 054's surface, which 054's own
--   text makes a joint-review trigger, and it is the authorizing artifact for a
--   new write path into a multi-tenant financial table.
--
-- ----------------------------------------------------------------------------
-- QA TEST-PAIRING (QA-owned — Architect does not author supabase/tests/). The
--   052 precedent applies: that migration's comment changes were paired with an
--   obj_description machine-check, and the same shape fits here. Each item names
--   the negative that would ACTUALLY FIRE.
--   1. RENDER-VERIFY THE CATALOG, NOT THE FILE:
--      obj_description('pfin.nav_daily'::regclass, 'pg_class') CONTAINS
--      'SELF-217'. Fires if 068 was never applied, or applied to the wrong
--      object. ⚠ Assert against obj_description and NOT against the .sql text —
--      the catalog string is what ships, and a doubled '' leaking into rendered
--      text is invisible in source.
--   2. THE FALSIFIED CLAIM IS GONE — the same obj_description does NOT contain
--      'no historical backfill in V1.1'. This is the leg that fires if a future
--      edit reinstates it, and it is the whole point of the migration.
--   3. THE SURVIVING PROHIBITION IS STILL STATED — the same obj_description
--      still contains 'must NOT be' (050's TEMPORAL CONSTRAINT clause). ⚠ Without
--      this, an over-eager future "simplification" could drop the recompute
--      prohibition while item 2 stayed green, which would be the exact
--      misreading this amendment exists to prevent.
--   4. NOTHING ELSE MOVED: 054's policies, grants and triggers are unchanged —
--      assert the nav_daily grant set and the presence of both mutation-block
--      triggers, so a comment migration that quietly did more would fail.
--   ⚠ `supabase db reset` is PROHIBITED here — it destroys the F/CTO's active
--   local test data. Verify non-destructively (apply-in-txn + rollback).
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- pfin.nav_daily — table comment REPLACED IN FULL (a `comment on` has no partial
-- form; the whole literal is re-issued and only the FORWARD-ONLY clause differs
-- from what 054 shipped). See REGENERATE-AND-DIFF PROVENANCE in the header for
-- the containment proof that everything outside that clause is byte-identical.
-- ----------------------------------------------------------------------------
comment on table pfin.nav_daily is
  'Append-only per-user daily net-worth checkpoint — the §2.1.2 net-worth-trend '
  'substrate (ADR-040; SELF-214; Option B precomputed table). One row per '
  '(users_id, nav_date) = the frozen NAV computed at that day''s close by the cron '
  'worker via fn_compute_nav(current_date, true) (050 active-only). FROZEN '
  'checkpoints, per 050''s TEMPORAL CONSTRAINT: historical NAV must NOT be '
  'recomputed on-the-fly (active-only + a past as_of rewrites history) — it is read '
  'from these rows. FORWARD-ONLY FOR COMPUTED CHECKPOINTS: the cron trajectory accumulates from its first run and NEVER '
  'recomputes a past date — 050''s TEMPORAL CONSTRAINT above is what forbids that, and it is UNCHANGED. AMENDED at '
  'SELF-217 (F/CTO ratify 2026-08-12; ADR-053): externally-measured NAV may be IMPORTED at nav_dates preceding the '
  'first cron checkpoint, landing at month-end. THE DISTINCTION IS THE WHOLE CONTENT OF THAT AMENDMENT: the '
  'prohibition was always on FABRICATING history by RECOMPUTATION (a past active-only NAV is unsound, and the '
  'valuation path values an unpriced asset at zero silently), never on importing a figure MEASURED '
  'contemporaneously by the system that held the positions. IMPORTED-ROW PROVENANCE IS DERIVED, NOT STORED (no '
  'source column, deliberately — ADR-011 Decision 4''s derive-by-looking test): because the cron wrote nothing '
  'before its first run, a checkpoint whose nav_date PRECEDES the first cron-written checkpoint is an imported '
  'historical row. users_id is the SOLE tenant anchor (direct-owner '
  'RLS users_id = auth.uid(), 024 precedent) → NOT a Decision-3 cross-tenant '
  'FK-bypass instance. WRITE PATH (ADR-023 credential model, F/CTO-ratified '
  '2026-08-02): the W-1 cron worker LOGS IN as `pfin_etl` (the dedicated NOINHERIT '
  'broker; service_role is rolcanlogin=f and can NEVER be a login identity) and '
  'WRITES AS `service_role` via SET LOCAL ROLE, over TenantBoundConnection; INSERT '
  '... ON CONFLICT (users_id, nav_date) DO NOTHING for idempotent re-runs — the '
  'TARGETED form, which is why service_role additionally holds a COLUMN-LEVEL '
  'select (users_id, nav_date): a targeted ON CONFLICT requires SELECT on its '
  'arbiter columns (Sec joint-review B9, 2026-08-02; without it the cron raises '
  '42501 on EVERY run). service_role CANNOT read nav_value and CANNOT select * — '
  'both denied, and QA asserts both negatives, since a positive assertion alone '
  'cannot distinguish a column grant from a table grant. Widening that grant (any '
  'extra column, or a move to table-level) is SEC JOINT-REVIEW-MANDATORY. '
  '`authenticated` holds SELECT only — no write grant and no write policy, so its '
  'writes are denied at the ACL before RLS (it cannot forge a checkpoint). '
  'Append-only audit-class (Decision 2 / Lock 10 mod #8): UPDATE + DELETE + TRUNCATE '
  'fenced for ALL roles; service_role bypasses RLS but not triggers, and is neither '
  'owner nor superuser so it cannot suppress them. WRITE-TENANT BINDING FENCE (B7 '
  '(c′)): a BEFORE INSERT trigger requires new.users_id to equal the transaction-'
  'local GUC app.nav_computed_for, which the worker sets from auth.uid() as the DB '
  'resolved it — so the row''s tenant is proven to BE the tenant served. Every INSERT '
  'path (incl. QA fixtures + seeds) must set that GUC. aal2 step-up backstop '
  'INHERITED on the SELECT policy (C3 / 025). JOINT-REVIEW-MANDATORY (tenant-scoped '
  'financial data). §10 ledger stays 3; DEFINER allowlist stays 4 (all three fences '
  'here are INVOKER; W-1 authors no fn); Decision-3 family stays 15 labeled / 12 '
  'DDL-realized. SECURITY: SD-24 (high) + RT-31 — both landed by Sec 2026-08-02.';

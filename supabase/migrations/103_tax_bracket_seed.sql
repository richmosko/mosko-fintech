-- ============================================================================
-- Migration: pfin.fn_tax_bracket_seed_template + pfin.fn_provision_tax_brackets
-- — the Federal + California bracket and standard-deduction TEMPLATE, its
-- signup provisioning path, and its explicit backfill to already-provisioned
-- users. Phase 6 Build Loop (SELF-260). Consumes the 101 substrate (SELF-259);
-- realizes no new table and no new column.
-- Sec joint-review MANDATORY — AC 5, which STRIKES the drafted "data-only, no
-- Sec review": bracket rates and standard deductions are FINANCIAL-CALCULATION
-- INPUTS, and every dollar PRD §2.5.3 / §2.5.4 render is a function of them.
-- "Data-only" describes the CHANGE SHAPE, not the SURFACE, and the trigger is
-- the surface.
--
-- WHAT THIS DOES: authors ONE immutable template function holding every seeded
-- figure exactly once; ONE SECURITY INVOKER provisioning function that writes
-- that template for auth.uid() at signup, existence-guarded per schedule KEY;
-- and ONE backfill statement that writes the same template for every user who
-- already exists. Both writers derive their values from the template function —
-- there is no second copy of any number in this file.
--
-- Numbering: 103, taken against the live listing at authoring time and NOT
--   reserved ahead. Order-dependent: must run AFTER 101 (SELF-259), which
--   creates pfin.tax_schedule_type_enum, pfin.tax_bracket_schedule,
--   pfin.tax_bracket_row, their RLS, and BOTH fences this file's writes pass
--   through. 100 (SELF-263) and 102 (SELF-267) are sibling-branch migrations
--   that touch neither of these tables; this file is independent of both and
--   states no dependency on either.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — BOTH functions are SECURITY INVOKER (default per ADR-011
--   Lock 11); NEITHER is SECURITY DEFINER, and the SECURITY DEFINER allowlist is
--   UNCHANGED — read it live at ADR-011 Decision 9; this file states no count.
--
--   fn_tax_bracket_seed_template() reads NO TABLE. It is a constant VALUES list
--   with a name, so it needs no privilege of any kind and INVOKER is not merely
--   sufficient but vacuous — there is nothing for a security context to change.
--   IMMUTABLE for the same reason.
--
--   fn_provision_tax_brackets() writes ONLY the caller's own rows and must
--   therefore compose with the caller's own RLS, which is exactly what INVOKER
--   gives. Making it DEFINER would let it write rows the caller could not write
--   directly — including past the 025 aal2 backstop clause on both tables'
--   INSERT policies — which is a privilege this surface has no reason to hold.
--   It takes NO TENANT PARAMETER (users_id comes from auth.uid()), following
--   fn_tax_bracket_schedule_replace_all at 101 (R4 rider 4 / Sec D-2): a tenant
--   parameter on a SECURITY INVOKER settings writer is a forgeable input that
--   buys nothing RLS does not already give.
--
--   Both carry `set search_path = ''` and both have EXECUTE revoked from PUBLIC
--   and granted to `authenticated`. ⚠ For an INVOKER function the EXECUTE grant
--   is the WEAKEST of the three fences (RLS and the two triggers still apply to
--   whatever it does); it is stated here so that a later reader does not read
--   the grant as the perimeter. On a DEFINER function it would BE the perimeter,
--   which is a further reason neither of these is one.
--
-- ----------------------------------------------------------------------------
-- ADR-011 DECISION 3 — FAMILY UNCHANGED, +0. Read Decision 3's body live before
--   citing it; this file carries no tally.
--   This migration creates, alters and drops NO COLUMN, and adds no FK-shaped
--   reference of any kind. It WRITES pfin.tax_bracket_row.schedule_id, which is
--   canonical instance #18, realized at 101 — so this file is a CONSUMER of that
--   instance's fence, not an extension of the family. Every schedule_id written
--   below is an id returned by this same statement's own INSERT into
--   pfin.tax_bracket_schedule, so the matched-tenant fence's leg 2 is passed by
--   construction rather than by luck: the users_id on the child is the same
--   expression that produced the parent.
--
-- ADR-011 DECISION 4 (§10) — LEDGER EFFECTS: NONE. Decision 4 read verbatim and
--   live before drafting (2026-09-04); the three axes are clean — no catalogued
--   instance added, removed, reordered or renumbered; no layer re-attributed; no
--   surface becomes "four-layer". Path B: linked, not restated, no count carried
--   here or in any comment this file emits. ⚠ The §10 CATALOGUED set and the
--   CI-FENCED set remain DIFFERENT SETS and are not reconciled here.
--
-- ----------------------------------------------------------------------------
-- ⚠ PRIVILEGED-CONTEXT WRITE — Sec joint-review item, stated rather than
--   assumed. Statement (3) below writes rows into pfin.tax_bracket_schedule and
--   pfin.tax_bracket_row, TENANT-OWNED tables, from the migration role. No pfin
--   table carries FORCE ROW LEVEL SECURITY, so the owning/migrating role is not
--   subject to those tables' RLS policies, and the 025 aal2 backstop conjunct on
--   their INSERT policies is likewise not evaluated. That is precisely WHY a
--   backfill reaches users the app path cannot — and why it belongs in front of
--   Sec rather than inside a convenience.
--   ⚠ CLASS, stated precisely because the loose form weakens ADR-011 Decision 1:
--   this is a MIGRATION-ROLE write — D1-ADJACENT, not a D1 instance. It meets
--   D1 (a) and (c), and meets NEITHER (b) — the writer is the schema owner, not
--   service_role — NOR (d): no audit-log row is emitted. Its tenant-resolution
--   record is the version-controlled, joint-reviewed migration file plus the
--   applied-migrations ledger. Do not cite 103 as precedent for a service_role
--   surface shipping without (d). This is the 077 / 091 disposition, unchanged.
--
--   ⚠ THE TENANT BINDING IS DERIVED, NOT INHERITED — and that is a DEPARTURE
--   from 077 / 080 / 091, stated because a reader who knows those files will
--   expect the other shape. Those backfills derive their user set from the
--   TARGET table itself, which makes a zero-row user unreachable BY
--   CONSTRUCTION. That derivation is impossible here — pfin.tax_bracket_schedule
--   is greenfield at this migration, holds zero rows, and a user set derived from
--   it would reach NOBODY, which is the 077 defect this rule exists to prevent
--   rather than a conservative reading of it. The set is therefore derived from
--   auth.users, the FK TARGET of both tables' users_id. The statement still
--   cannot MINT a users_id (the FK refuses one that does not exist) and still
--   cannot cross one tenant's rows into another's (users_id is carried through
--   the CTE unchanged, and the child's users_id is the parent's).
--
--   ⚠ AND THE HAZARD THE 077 SHAPE GUARDS AGAINST DOES NOT EXIST HERE, which is
--   the load-bearing half — the derivation changed because the guard did.
--   ADR-057 forbids reaching a zero-row user because 041's first-access
--   provisioning is guarded on ANY ROW EXISTING: handing such a user one row
--   would satisfy that guard and strand them forever with one Sub-Cat instead of
--   the full set. THIS surface's guard is PER SCHEDULE KEY —
--   `unique (users_id, tax_year, schedule_type)` with `on conflict do nothing`,
--   in the backfill and in fn_provision_tax_brackets() alike. A user who holds
--   the three seeded schedules is skipped for those three and remains fully
--   reachable for every other (tax_year, schedule_type) pair, including next
--   year's. Reaching a zero-row user is therefore the INTENDED effect and
--   strands nobody. ⚠ Do not "restore" an any-row existence guard on this
--   surface: it would convert a per-key idempotence into exactly the 041 trap,
--   and it would do so silently.
--
-- ----------------------------------------------------------------------------
-- REACH DECISION (ADR-057, as generalized at ADR-062 Decision 5; AC 7).
--
--   THIS SEED REACHES ALREADY-PROVISIONED USERS BY EXPLICIT BACKFILL, in this
--   migration, because the signup path CANNOT deliver it to them.
--
--   THE MECHANISM. fn_provision_tax_brackets() is called by the app at signup /
--   first access (Backend wires it where provisionDefaultTaxonomy is called,
--   api/src/lib/server/queries/taxonomy.ts). That path runs for a session and
--   writes for auth.uid() only — it has no reach to a user who is not the caller,
--   by construction and by design. A user who already existed when this
--   migration applied would receive the seed only on their next first-access
--   call, which for an existing account has already happened. Statement (3) is
--   what reaches them, and without it this seed would silently deliver nothing
--   to anyone who already exists — the 077 case again.
--
--   ⚠ THE TWO WRITERS SHARE ONE SOURCE OF VALUES AND THEREFORE CANNOT DRIFT.
--   Both read pfin.fn_tax_bracket_seed_template(). This is the single property
--   that makes the pair maintainable: a figure corrected in the template is
--   corrected for signup and for backfill in one edit, and there is no second
--   place to forget. A future correction to a published figure is a NEW
--   migration that replaces the template function and backfills the delta; it is
--   NOT an edit to this file.
--
--   RE-RUN: statement (3) is idempotent. `on conflict (users_id, tax_year,
--   schedule_type) do nothing` returns zero rows for a schedule that already
--   exists, and the row INSERT is driven off that RETURNING set, so a second
--   apply inserts zero schedules AND zero rows. ⚠ That coupling is deliberate
--   and is what keeps a re-run from duplicating brackets under
--   `unique (schedule_id, bracket_floor)`; do not rewrite the row INSERT to read
--   the schedule table directly.
--
--   ⚠ WHAT A RE-RUN DELIBERATELY DOES NOT DO: it does not repair a schedule the
--   user has since edited, and it does not add rows to a seeded schedule the user
--   has since emptied. An empty schedule is a LEGAL state at 101 (the set fence
--   passes it — absence is unset), and re-populating it would silently overwrite
--   a deliberate act. Settings are the user's.
--
-- ----------------------------------------------------------------------------
-- THE TEMPLATE IS A TEMPLATE — AC 6 / PM's A-6.
--
--   FILING STATUS IS SINGLE, and every schedule's label says so. The seeded set
--   is a STARTING POINT the user revises in the §2.5.2 editor (SELF-265), not a
--   determination about anybody's return. The drafted "fixed at seed time per
--   the F/CTO's filing status" is founding-user framing that does not survive
--   general multi-user software, and it is not what this file implements.
--   Reversal is an ordinary edit through the replace-all endpoint — no migration,
--   no data repair. This is NOT a one-way door.
--
--   ⚠ Filing status is NOT a column on either table and this file does not add
--   one. It is carried in the schedule's own label text, which is where AC 6
--   places it — and that label is a STORED COLUMN, pfin.tax_bracket_schedule.
--   schedule_label, added to 101 at Sec's SELF-260 V-2 under ruling E27 and
--   written by both writers below, so the assumption reaches the user rather
--   than stopping at the template function's return value. A filing-status column is a real future question (it would let the
--   editor re-seed on a status change) and it is deliberately not opened here.
--
-- ----------------------------------------------------------------------------
-- THE FIGURES — MEASURED FROM PRIMARY SOURCES, NOT RECALLED. Every number below
--   traces to one cited row of one cited publication. Rates are FRACTIONS with
--   at most 8 decimal places, per E1 and pfin.tax_bracket_row.bracket_rate's
--   numeric(12,8) domain: 0.22, never 22.
--
--   FEDERAL — tax year 2026. IRS Revenue Procedure 2025-32 (the tax-year-2026
--     inflation adjustments, including the OBBBA amendments).
--     https://www.irs.gov/pub/irs-drop/rp-25-32.pdf
--     · ordinary brackets — §3.01 TABLE 3, "Section 1(j)(2)(C) – Unmarried
--       Individuals (other than Surviving Spouses and Heads of Households)".
--     · standard deduction $16,100 — §3.14(1), "Unmarried Individuals (other
--       than Surviving Spouses and Heads of Households) (§ 1(j)(2)(C))".
--     · long-term capital gains — §3.03 "Maximum Capital Gains Rate", row
--       "All Other Individuals": maximum zero rate amount $49,450, maximum
--       15-percent rate amount $545,500.
--
--   CALIFORNIA — tax year 2025. California Franchise Tax Board.
--     · brackets — 2025 California Tax Rate Schedules, "Schedule X – Use if your
--       filing status is Single or Married/RDP Filing Separately".
--       https://www.ftb.ca.gov/forms/2025/2025-540-tax-rate-schedules.pdf
--     · standard deduction $5,706 — 2025 Form 540 booklet, "California Standard
--       Deduction Chart for Most People", filing status 1 – Single (Form 540
--       line 18). https://www.ftb.ca.gov/forms/2025/2025-540-booklet.pdf
--
--   ⚠ CALIFORNIA IS SEEDED AT tax_year 2025, NOT 2026, AND THAT IS A DEPARTURE
--   FROM AC 1's "current tax year" — declared, not silent, and it has a
--   consequence a reader must know.
--     WHY: the FTB indexes its brackets annually and had NOT PUBLISHED the tax
--     year 2026 schedule when this migration was authored. Measured, not
--     assumed: both https://www.ftb.ca.gov/forms/2026/2026-540-tax-rate-schedules.pdf
--     and https://www.ftb.ca.gov/forms/2026/2026-540-booklet.pdf returned HTTP
--     404 on 2026-09-04. 2025 is the latest published year and the schedule is
--     labelled with the year it is actually FOR.
--     CONSEQUENCE, and it is RESOLVED AT THE READER RATHER THAN AT THE SEED
--     (E22, team-lead under F/CTO delegation, 2026-09-04). Decision 18 has V1
--     read §2.5.3 at `EXTRACT(YEAR FROM CURRENT_DATE)`, so a naive current-year
--     read finds NO california_ordinary schedule during calendar 2026. SELF-262's
--     helper therefore takes the CURRENT-YEAR schedule of a type WHEN PRESENT and
--     otherwise the LATEST PRIOR-YEAR schedule of that type, and carries THE
--     BASIS YEAR IT USED in its payload, so every consumer renders "California on
--     the 2025 schedule" — never $0, and never a silent substitution. ⚠ THE
--     FALLBACK IS THE READER'S, NOT THIS FILE'S: nothing here makes a 2025 row
--     answer a 2026 question, and a consumer that reads these tables directly
--     without that helper still sees exactly what is stored — a 2025 schedule and
--     no 2026 one. A follow-up issue seeds California 2026 when the FTB
--     publishes. ⚠ Do NOT "fix" this by relabelling the row: see (a) below.
--     ⚠ THE TWO REJECTED ALTERNATIVES, named so neither is reached for later.
--       (a) Seed the 2025 FIGURES under tax_year 2026. That is a confident,
--           plausible, WRONG number — indistinguishable from a correct one at
--           every surface that reads it and invisible to every assertion on the
--           value. It is the same hazard class 062 documents for recomputed
--           historical NAV, arrived at from the other direction.
--       (b) Seed an EMPTY california_ordinary schedule at tax_year 2026 so the
--           year "exists". WORSE THAN (a), and worse in a way that is easy to
--           miss: standard_deduction is NOT NULL, so an empty schedule must
--           still carry a made-up deduction; and a schedule that EXISTS with no
--           rows makes the reader compute a tax of zero rather than render
--           UNSET, which is precisely the coalesce-to-zero failure the AC forbids
--           — it silently overstates nothing and understates the tax owed. It
--           would also consume the (users_id, 2026, california_ordinary) key, so
--           a later migration seeding the real published figures would be
--           skipped by its own `on conflict do nothing`.
--           ⚠ E22's reader fallback makes (b) WORSE, not safer, and that is worth
--           stating because the fallback reads like it would absorb the problem.
--           A PRESENT-but-empty 2026 schedule SUPPRESSES the fallback — the
--           current-year schedule exists, so the helper never reaches 2025 — and
--           the zero it then computes is indistinguishable from a real one. The
--           ABSENCE of the 2026 row is exactly what makes the fallback fire.
--
--   ⚠ THE CALIFORNIA SCHEDULE CARRIES A TENTH BRACKET THAT IS NOT IN SCHEDULE X,
--   AND ITS SOURCE IS A SECOND CITATION — ruled at E23 (team-lead under F/CTO
--   delegation, 2026-09-04). The 1% BEHAVIORAL HEALTH SERVICES TAX, Cal.
--   Revenue & Taxation Code §17043 (Proposition 63, 2004), applies on
--   California taxable income above a threshold and is imposed IN ADDITION TO
--   the Schedule X rates.
--     ⚠ THE NAME IS THE CURRENT ONE, DELIBERATELY. For taxable years beginning
--     on or after 2025-01-01 the Act was renamed the Behavioral Health Services
--     Act and the tax was renamed with it (FTB 2025 Form 540 booklet, What's
--     New; Form 540 LINE 62 is titled "Behavioral Health Services Tax"). The
--     California year seeded here IS 2025, the first year of that rename, so the
--     superseded popular name appears NOWHERE in this file — including in this
--     sentence, deliberately, so that a grep for it remains a clean instrument.
--     R&TC §17043 itself is unchanged and un-renamed — which is why the
--     STATUTORY citation does not move (Sec SELF-260 F-1).
--   It is seeded here as floor 1000000.0000 at rate 0.13300000 — the 12.3% top
--   Schedule X rate PLUS the 1% surtax, which is the correct MARGINAL rate above
--   the threshold and therefore the right shape for this table, whose rows are
--   marginal rates on a lower-bound floor.
--     ⚠ THIS IS THE ONE ROW THAT DOES NOT TRACE TO FTB SCHEDULE X — the cited
--     schedule ends at 12.3% — so it carries its own citation rather than
--     borrowing the schedule's, in this header and in the schedule's label.
--     Every number in this file still traces to a cited source; two sources now
--     compose one schedule, and saying so is what keeps that checkable.
--     ⚠ THE THRESHOLD IS FLAT ACROSS FILING STATUSES AND IS NOT INFLATION-
--     INDEXED — R&TC §17043(c)(2), which provides that the provisions of §17041
--     "relating to filing status and recomputation of the income tax brackets"
--     SHALL NOT APPLY to the tax imposed by §17043; §17043(c)(3) likewise
--     disapplies §17045 (joint returns). The statute does not merely omit a
--     filing-status split — it switches off the mechanism by which one could
--     exist, and that same disapplication is why there is no indexed variant of
--     this figure to go looking for. The 2025 Form 540 line 62 worksheet
--     subtracts the flat threshold from line 19 with no filing-status branch, on
--     the one Form 540 that Single and Married/RDP-filing-separately both use.
--     ⚠ NOTHING IN THIS FILE INSTRUCTS A USER TO MOVE THIS FLOOR ON A FILING-
--     STATUS CHANGE, and the supersession is named so a reader who remembers
--     otherwise learns it changed: an earlier revision of THIS block, of the
--     inline comment above the California VALUES list, of that schedule's label
--     and of the template's `comment on function` all stated that the floor was
--     halved for a married/RDP filer filing separately and told the user to
--     revise it. That was FALSE — Sec SELF-260 V-1 — and is corrected at all
--     four sites. It is corrected in ruling E23 too; a migration that fixed the
--     text while the ruling still carried the false premise would leave the next
--     surface to inherit it.
--     ⚠ WHAT THE SINGLE ASSUMPTION DOES GOVERN on this schedule is the STANDARD
--     DEDUCTION. FTB Schedule X is SHARED by Single and Married/RDP-filing-
--     separately, so the RATE rows are identical for both; the deduction taken
--     from the Form 540 chart at status 1 is not, and that is the value a user
--     revising the filing status must revisit.
--
--   ⚠ federal_lt_cg CARRIES standard_deduction = 0, AND THAT ZERO MEANS
--   "THIS SCHEDULE TAKES NO DEDUCTION" — NOT "not yet entered" (AC 1;
--   PRD §2.5.3's "no standard deduction applied to this schedule"). It is the one
--   place on this surface where a literal zero is the right answer, and saying so
--   is what keeps 101's absence-is-unset rule readable: on every OTHER schedule
--   an unset deduction is the ABSENCE OF THE SCHEDULE ROW, because the column is
--   NOT NULL. The same point is carried in that schedule's own stored label, so
--   a reader meeting the row in the editor sees it too.
--
-- ----------------------------------------------------------------------------
-- 101'S DEFERRED SET FENCE — THIS IS ITS FIRST EXERCISE ON A MULTI-ROW BATCH
--   (AC 3), and the AC asks that the claim be stated here so a reviewer knows
--   what a green apply is evidence OF.
--
--   Every schedule this file writes arrives as ONE multi-row INSERT — several
--   rows per schedule, the largest being california_ordinary — which is exactly
--   the shape a BEFORE ROW fence CANNOT judge: it fires before
--   the later rows of its own statement exist and evaluates each row against an
--   incomplete set. 101 ships the DEFERRED CONSTRAINT TRIGGER form ruled at R4
--   rider 1 (fn_tax_bracket_row_schedule_invariants, `deferrable initially
--   deferred`), which evaluates at COMMIT with the whole set visible.
--   ⚠ A GREEN APPLY OF THIS FILE IS EVIDENCE ONLY BECAUSE OF THAT FORM. Under
--   the BEFORE ROW shape the same apply would be green over an unjudged set, and
--   the two greens are indistinguishable from here. The falsifying probe belongs
--   in the PR body, not in a comment that cannot run: a deliberately non-monotone
--   copy of one schedule's rows, sent as one multi-row INSERT inside a
--   transaction, must be REJECTED AT COMMIT by leg B.
--
--   BOTH SEEDED PROPERTIES HOLD BY CONSTRUCTION IN THE TEMPLATE, and the fence
--   is the independent check on that claim rather than a restatement of it:
--   every schedule's lowest bracket_floor is 0 (leg A) and every schedule's
--   rates are non-decreasing as floors ascend (leg B) — including federal_lt_cg,
--   whose first rate is 0.00 and which is therefore non-decreasing rather than
--   flat-then-rising in some other sense.
--
-- ----------------------------------------------------------------------------
-- 40P01 / THE TWO-SCHEDULE DEADLOCK PREMISE — Sec R-2 / execution-log E20.
--
--   ADR-011 Decision 18's amendment records the two-parent-lock deadlock as
--   RECORDED, NOT TESTED, resting on the premise that NO V1 WRITER TOUCHES TWO
--   SCHEDULES IN ONE TRANSACTION. This file is the first surface that does, so
--   the premise is extended here rather than left to be discovered:
--
--     · STATEMENT (3), the backfill, writes THREE schedules per user for EVERY
--       existing user in ONE MIGRATION TRANSACTION, and therefore takes many
--       parent-row locks. It cannot deadlock, for a reason that needs no
--       ordering argument at all: A LONE TRANSACTION CANNOT DEADLOCK AGAINST
--       ITSELF, and a migration runs with nothing else writing this greenfield
--       surface. The locks are re-entrant within the transaction, so the N
--       deferred firings of one schedule's rows cost one acquisition.
--     · fn_provision_tax_brackets() writes THREE schedules per call and CAN run
--       concurrently — two sessions of the same account, or a double-submitted
--       signup. It takes its locks in a DETERMINISTIC ORDER: the schedule INSERT
--       is ordered by schedule_type and the row INSERT by (schedule_id,
--       bracket_floor), so the deferred firings queue in the same order in every
--       call. Two callers taking the same locks in the same order cannot
--       deadlock; the second waits.
--     · And on this surface the second caller does not even reach the locks:
--       `on conflict do nothing` returns ZERO schedules for an account that
--       already holds them, the row INSERT is driven off that empty set, and a
--       transaction that inserts no rows fires no deferred trigger and takes no
--       parent lock. The ordering argument above is therefore the BACKSTOP, not
--       the primary reason — stated in both forms because the primary one stops
--       holding the moment a future writer seeds a schedule the caller lacks.
--
--   ⚠ This EXTENDS the E20 premise; it does not retire the 40P01 mode. A future
--   writer that touches two schedules of one user in a transaction with a
--   different lock order can still deadlock, and Postgres still aborts one with
--   an error rather than a corrupt set.
-- ============================================================================

create schema if not exists pfin;

-- ============================================================================
-- (1) THE TEMPLATE — the single home of every seeded figure.
--
-- Returned FLAT (the schedule scalars repeat on each of that schedule's rows)
-- rather than as two functions, and the flatness is SELF-POLICING rather than
-- merely convenient: statement (3) and fn_provision_tax_brackets() both build
-- the schedule row with `select distinct schedule_type, tax_year,
-- standard_deduction, schedule_label`, so if one row of a schedule carried a
-- DIFFERENT standard_deduction OR a different label the distinct would yield
-- TWO schedule rows for one (users_id, tax_year, schedule_type) and `unique`
-- would ABORT the migration. A transcription slip in any repeated scalar is
-- therefore a loud failure at apply time, not a silent divergence. The label
-- joined that set when 101 gained the schedule_label column (Sec SELF-260 V-2;
-- ruling E27), so it is policed on exactly the same terms as the deduction.
-- ============================================================================
create or replace function pfin.fn_tax_bracket_seed_template()
returns table (
  schedule_type       pfin.tax_schedule_type_enum,
  tax_year            smallint,
  standard_deduction  numeric,
  schedule_label      text,
  bracket_floor       numeric,
  bracket_rate        numeric
)
language sql
immutable
security invoker
set search_path = ''
as $$
  -- FEDERAL ORDINARY — tax year 2026, filing status SINGLE.
  -- IRS Rev. Proc. 2025-32 §3.01 TABLE 3 (§ 1(j)(2)(C), Unmarried Individuals);
  -- standard deduction §3.14(1), same filing status.
  select 'federal_ordinary'::pfin.tax_schedule_type_enum, 2026::smallint, 16100.0000::numeric,
         'US Federal — ordinary income — tax year 2026 — SINGLE filer TEMPLATE; revise to match your filing status. Source: IRS Rev. Proc. 2025-32 §3.01 Table 3; standard deduction §3.14(1).'::text,
         f, r
    from (values (      0.0000::numeric, 0.10000000::numeric),
                 (  12400.0000,          0.12000000),
                 (  50400.0000,          0.22000000),
                 ( 105700.0000,          0.24000000),
                 ( 201775.0000,          0.32000000),
                 ( 256225.0000,          0.35000000),
                 ( 640600.0000,          0.37000000)) as t(f, r)

  union all

  -- FEDERAL LONG-TERM CAPITAL GAINS — tax year 2026, filing status SINGLE.
  -- IRS Rev. Proc. 2025-32 §3.03, row "All Other Individuals": maximum zero rate
  -- amount 49,450 and maximum 15-percent rate amount 545,500 are the TOPS of the
  -- 0% and 15% bands, so they are the FLOORS of the 15% and 20% bands here.
  -- standard_deduction 0 means THIS SCHEDULE TAKES NO DEDUCTION (PRD §2.5.3) —
  -- it does not mean "not yet entered". Unset, on every other schedule, is the
  -- absence of the schedule row.
  select 'federal_lt_cg'::pfin.tax_schedule_type_enum, 2026::smallint, 0.0000::numeric,
         'US Federal — long-term capital gains — tax year 2026 — SINGLE filer TEMPLATE. Deduction 0 means this schedule takes NO deduction; a value, not an unset. Source: IRS Rev. Proc. 2025-32 §3.03.'::text,
         f, r
    from (values (      0.0000::numeric, 0.00000000::numeric),
                 (  49450.0000,          0.15000000),
                 ( 545500.0000,          0.20000000)) as t(f, r)

  union all

  -- CALIFORNIA ORDINARY — tax year 2025, filing status SINGLE.
  -- FTB 2025 California Tax Rate Schedules, Schedule X (Single or Married/RDP
  -- Filing Separately); standard deduction from the 2025 Form 540 booklet,
  -- California Standard Deduction Chart for Most People, status 1 – Single.
  -- ⚠ 2025 AND NOT 2026: the FTB had not published the 2026 schedule when this
  -- migration was authored (both 2026 form URLs returned 404 on 2026-09-04). The
  -- label carries the year so nobody reads it as the current one.
  -- ⚠ THE TENTH ROW IS NOT FROM SCHEDULE X. floor 1000000 / rate 0.133 is the
  -- 1% Behavioral Health Services Tax (R&TC §17043) composed with the 12.3% top
  -- Schedule X rate, giving the correct MARGINAL rate above the threshold. Its
  -- threshold is FLAT ACROSS FILING STATUSES and is not inflation-indexed:
  -- §17043(c)(2) disapplies §17041's filing-status recomputation to this tax and
  -- (c)(3) disapplies §17045, so NO row on this schedule has a floor that moves
  -- with filing status. See this file's header (E23; Sec SELF-260 V-1).
  select 'california_ordinary'::pfin.tax_schedule_type_enum, 2025::smallint, 5706.0000::numeric,
         'California FTB — ordinary income — 2025 basis (FTB 2026 unpublished) — SINGLE filer TEMPLATE. Top bracket composes R&TC §17043 (1%) with Schedule X (12.3%) = 13.3% above $1,000,000; that floor is FLAT across filing statuses and un-indexed, so it does NOT move if you change status. Sources: FTB 2025 California Tax Rate Schedules, Schedule X (Single or Married/RDP filing separately); standard deduction from the 2025 Form 540 booklet chart, status 1 - Single; R&TC §17043.'::text,
         f, r
    from (values (      0.0000::numeric, 0.01000000::numeric),
                 (  11079.0000,          0.02000000),
                 (  26264.0000,          0.04000000),
                 (  41452.0000,          0.06000000),
                 (  57542.0000,          0.08000000),
                 (  72724.0000,          0.09300000),
                 ( 371479.0000,          0.10300000),
                 ( 445771.0000,          0.11300000),
                 ( 742953.0000,          0.12300000),
                 (1000000.0000,          0.13300000)) as t(f, r)
$$;

revoke execute on function pfin.fn_tax_bracket_seed_template() from public;
grant  execute on function pfin.fn_tax_bracket_seed_template() to authenticated;

comment on function pfin.fn_tax_bracket_seed_template() is
  'The SINGLE HOME of every figure the SELF-260 bracket seed writes — Federal '
  'ordinary and long-term-capital-gains schedules and the California FTB '
  'ordinary schedule, with their standard deductions and their labels. Read by '
  'BOTH writers of that seed (pfin.fn_provision_tax_brackets for a signing-up '
  'user, and 103''s backfill statement for users who already existed), which is '
  'what makes it impossible for the two to drift apart. Reads NO TABLE: it is a '
  'constant VALUES list with a name, so IMMUTABLE and SECURITY INVOKER are both '
  'vacuous rather than merely sufficient, and it adds no SECURITY DEFINER '
  'allowlist entry. Rates are FRACTIONS (0.22, never 22), matching '
  'pfin.tax_bracket_row.bracket_rate. Returned FLAT — a schedule''s scalars '
  'repeat on each of its rows — and that shape is SELF-POLICING: both writers '
  'build the parent row with SELECT DISTINCT over (schedule_type, tax_year, '
  'standard_deduction, schedule_label), so a scalar that disagreed across one '
  'schedule''s rows would yield two parent rows for one unique key and ABORT '
  'rather than diverge quietly. ⚠ The FEDERAL schedules are for tax year 2026 and the CALIFORNIA '
  'schedule is for tax year 2025 — the FTB had not published its 2026 schedule '
  'when this function was authored, and labelling a 2025 table as 2026 would '
  'produce a confident, plausible, wrong number rather than a basis a reader can '
  'see. SELF-262''s helper falls back to the latest prior-year schedule of a type '
  'and reports the basis year it used (E22), so the missing 2026 row is rendered '
  'as a stated basis rather than as a zero. ⚠ THE CALIFORNIA SCHEDULE COMPOSES '
  'TWO SOURCES: its top bracket (13.3% above $1,000,000) is FTB Schedule X''s '
  '12.3% plus the 1% Behavioral Health Services Tax of R&TC 17043, which is NOT '
  'in Schedule X. That threshold is FLAT ACROSS FILING STATUSES and is not '
  'inflation-indexed, because R&TC 17043(c)(2) disapplies 17041''s filing-status '
  'recomputation to this tax and (c)(3) disapplies 17045 — so no row on this '
  'schedule has a floor that moves with filing status, and nothing here tells a '
  'user to move one. What the SINGLE assumption governs on that schedule is its '
  'STANDARD DEDUCTION, taken from the Form 540 chart at status 1. '
  'Each schedule''s label states its own basis year and its own SINGLE-filer '
  'assumption, which is where PM''s A-6 places that assumption — and since 101 '
  'gained the schedule_label COLUMN (Sec SELF-260 V-2; ruling E27) both writers '
  'STORE that label on the schedule row, so it reaches the user in the §2.5.2 '
  'editor rather than stopping at this function''s return value. ⚠ The seeded set '
  'is a TEMPLATE the user revises, never a determination about anyone''s return. '
  'Correcting a published figure is a NEW migration that replaces this function '
  'and backfills the delta — never an edit to the merged one.';

-- ============================================================================
-- (2) THE SIGNUP PATH — pfin.fn_provision_tax_brackets()
--
-- Backend calls this where provisionDefaultTaxonomy is called today
-- (api/src/lib/server/queries/taxonomy.ts). It is idempotent per schedule KEY,
-- takes no tenant parameter, and returns the number of schedules it created so
-- the caller can distinguish "provisioned now" from "already had them" without
-- a second read.
-- ============================================================================
create or replace function pfin.fn_provision_tax_brackets()
returns integer
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_users_id  uuid := auth.uid();
  v_created   integer;
begin
  -- FAIL CLOSED AND LOUD on an unauthenticated call. Without this the INSERT
  -- would fail on the NOT NULL anyway, but with a message that names a column
  -- rather than the cause.
  if v_users_id is null then
    raise exception
      'tax bracket provisioning refused: no authenticated caller (auth.uid() is null). This function provisions the CALLER''s own schedules and takes no tenant parameter (SELF-260)';
  end if;

  with tpl as (
    select * from pfin.fn_tax_bracket_seed_template()
  ),
  parent_src as (
    select distinct t.schedule_type, t.tax_year, t.standard_deduction, t.schedule_label
      from tpl t
  ),
  sched as (
    insert into pfin.tax_bracket_schedule
      (users_id, tax_year, schedule_type, schedule_label, standard_deduction)
    select v_users_id, p.tax_year, p.schedule_type, p.schedule_label, p.standard_deduction
      from parent_src p
     -- DETERMINISTIC LOCK ORDER (see this file's 40P01 block): the parent rows
     -- are created in enum order, so the deferred set fence's FOR UPDATE locks
     -- queue in the same order in every concurrent call.
     order by p.schedule_type
    on conflict (users_id, tax_year, schedule_type) do nothing
    returning id, tax_year, schedule_type
  ),
  child as (
    insert into pfin.tax_bracket_row
      (users_id, schedule_id, bracket_floor, bracket_rate)
    select v_users_id, s.id, t.bracket_floor, t.bracket_rate
      from sched s
      join tpl  t
        on t.tax_year = s.tax_year
       and t.schedule_type = s.schedule_type
     order by s.id, t.bracket_floor
    returning 1
  )
  -- ⚠ The child INSERT is driven off sched's RETURNING set, NOT off a read of
  -- the schedule table. That coupling is what makes a re-run a true no-op: a
  -- conflicting parent returns nothing, so no rows are offered for it and
  -- `unique (schedule_id, bracket_floor)` is never tested. Do not rewrite this
  -- to look the schedule up.
  select count(*) into v_created from sched;

  return v_created;
end;
$$;

revoke execute on function pfin.fn_provision_tax_brackets() from public;
grant  execute on function pfin.fn_provision_tax_brackets() to authenticated;

comment on function pfin.fn_provision_tax_brackets() is
  'Provisions the CALLING user''s SELF-260 tax bracket template — the three '
  'schedules held by pfin.fn_tax_bracket_seed_template() and their bracket rows '
  '— and returns the number of SCHEDULES it created (0 when the caller already '
  'holds all three). SECURITY INVOKER and NO TENANT PARAMETER: users_id comes '
  'from auth.uid(), and every write composes with the caller''s own RLS, '
  'including the 025 aal2 backstop conjunct on both tables'' INSERT policies. '
  'That is deliberate — DEFINER here would let this function write rows the '
  'caller could not write directly, past a step-up fence, for no gain. Same '
  'shape as pfin.fn_tax_bracket_schedule_replace_all (R4 rider 4 / Sec D-2). '
  '⚠ IDEMPOTENT PER SCHEDULE KEY, not per user: `on conflict (users_id, '
  'tax_year, schedule_type) do nothing`, and the bracket-row INSERT is driven '
  'off that statement''s RETURNING set rather than off a read of the schedule '
  'table — so a caller who already holds a schedule has its rows left alone, '
  'while remaining fully reachable for any other (tax_year, schedule_type) pair. '
  '⚠ A per-USER any-row existence guard MUST NOT be added: it would strand a '
  'user who holds one schedule and needs the others, which is the 041 trap '
  'ADR-057 exists to name. ⚠ This function REPLACES NOTHING. It never updates '
  'or deletes, so it cannot overwrite a schedule the user has edited or '
  'repopulate one they emptied — an empty schedule is a legal state and a '
  'deliberate one. Editing is pfin.fn_tax_bracket_schedule_replace_all''s job. '
  '⚠ REACH: this path writes for the CALLER ONLY and can never reach a user who '
  'already existed when the seed landed; that reach is 103''s backfill statement '
  '(ADR-057). A caller whose mfa_policy is totp or passkey but whose JWT is '
  'below aal2 is REFUSED by the 025 clause on the INSERT policies — fail-closed '
  'and correct, and the reason the app-side call is fail-soft. SECURITY '
  'INVOKER + set search_path = ''''; adds no SECURITY DEFINER allowlist entry.';

-- ============================================================================
-- (3) THE BACKFILL — reach for users who already exist (ADR-057; AC 7).
--
-- Derived from auth.users rather than from the target table, because the target
-- table is greenfield: see this file's PRIVILEGED-CONTEXT WRITE block for why
-- that departure from 077 / 080 / 091 is safe HERE and what would make it
-- unsafe elsewhere.
-- ============================================================================
with tpl as (
  select * from pfin.fn_tax_bracket_seed_template()
),
parent_src as (
  select distinct u.id as users_id, t.schedule_type, t.tax_year, t.standard_deduction,
                  t.schedule_label
    from auth.users u
   cross join tpl t
),
sched as (
  insert into pfin.tax_bracket_schedule
    (users_id, tax_year, schedule_type, schedule_label, standard_deduction)
  select p.users_id, p.tax_year, p.schedule_type, p.schedule_label, p.standard_deduction
    from parent_src p
   order by p.users_id, p.schedule_type
  on conflict (users_id, tax_year, schedule_type) do nothing
  returning id, users_id, tax_year, schedule_type
)
insert into pfin.tax_bracket_row
  (users_id, schedule_id, bracket_floor, bracket_rate)
select s.users_id, s.id, t.bracket_floor, t.bracket_rate
  from sched s
  join tpl  t
    on t.tax_year = s.tax_year
   and t.schedule_type = s.schedule_type
 order by s.id, t.bracket_floor;

-- ============================================================================
-- Migration: pfin.posting_prototype + pfin.posting_prototype_default — add
-- `is_tax_payment`, seed the two Equity posting prototypes, and backfill both
-- into every already-provisioned user.
-- Phase 6 Build Loop. SELF-245. Realizes ADR-062 Decisions 1 / 2 / 4 / 5.
-- Closes no SD/RT; extends no lock; authors no function, policy, grant or
-- trigger.
--
-- ----------------------------------------------------------------------------
-- Numbering: 091 follows 090 (cashflow_target); taken at authoring time against
--   the live listing, not reserved. Order-dependent: must run AFTER 084 (which
--   created both tables, the (users_id, cat, sub_cat) and (cat, sub_cat) uniques
--   the statements below conflict-target, and the 5-class CHECK that admits
--   'Equity'). Independent of 085 / 086 / 087 / 088 / 089 / 090 — those touch
--   the storage-taxonomy pair, functions, or other tables. No later migration
--   depends on 091 landing first.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — NO function is created, replaced or dropped, so neither
--   SECURITY INVOKER nor SECURITY DEFINER applies and `set search_path = ''` is
--   N/A: this file is two ALTERs per table, two UPDATEs, two INSERTs and two
--   `comment on column` statements. The SECURITY DEFINER allowlist is UNCHANGED
--   — read it live at ADR-011 Decision 9; this file states no count.
--   No RLS policy is added or altered. pfin.posting_prototype already carries
--   the 025 aal2 step-up backstop conjunct on both of its authenticated policies
--   (084); pfin.posting_prototype_default is 025-EXCLUDED under exclusion (i) as
--   global shared-read. Adding a column to an existing table changes neither, so
--   no aal2 obligation is triggered — that obligation attaches to a NEW
--   sensitive tenant-owned table, and no table is created here.
--
-- ----------------------------------------------------------------------------
-- WHY THE SHAPE IS `boolean not null`, NO DEFAULT, NO CHECK (ADR-062 Decision 2).
--
--   NO DEFAULT is what delivers fail-closed. `is_tax_payment` marks the buckets
--   PRD §2.3.4 EXCLUDES from "discretionary monthly expenses". A `DEFAULT FALSE`
--   would be fail-OPEN on exactly the axis that matters: an unmarked tax-payment
--   Sub-Cat would enter the discretionary chart silently, with no error and no
--   marker. With no default, every INSERT must state the value, so a prototype
--   authored outside the seed path — 084 already grants `authenticated` INSERT,
--   and the V2 taxonomy-CRUD path will use it — ERRORS rather than landing
--   silently discretionary.
--
--   NO CHECK is deliberate and is NOT a relaxation of the 085 discipline this
--   migration otherwise follows. "085-shaped" means the DISCIPLINE — NOT NULL,
--   no DEFAULT, total backfill before the NOT NULL, mirrored pair, `comment on
--   column` on each — not a literal instruction to emit a CHECK. 085's `element`
--   is `text`, and its named CHECK is what bounds a text column to two values.
--   On a boolean, `not null` already makes the domain exactly {true, false}, so
--   a named CHECK here COULD NOT FIRE. A constraint over a by-construction
--   property reads to a later reviewer as a live guarantee and is not one.
--
--   ⚠ IF A THIRD CLASS EVER BECOMES A REQUIREMENT (e.g. withholding vs estimated
--   payment), ADR-062's Alternatives records the migration path: a boolean → text
--   widening with a bounding CHECK, NOT an in-place CHECK edit. Recorded here so
--   that author finds it from the file rather than only from the ADR.
--
-- ----------------------------------------------------------------------------
-- ⚠ PRIVILEGED-CONTEXT WRITE — Sec joint-review item, stated rather than assumed.
--   Statements (5) and (6) below write rows into pfin.posting_prototype, a
--   TENANT-OWNED table, from the migration role. No pfin table carries FORCE ROW
--   LEVEL SECURITY, so the owning/migrating role is not subject to that table's
--   RLS policies, and the 025 aal2 backstop conjunct on posting_prototype_select
--   / posting_prototype_insert is likewise not evaluated. That is precisely WHY a
--   backfill can reach users the app path cannot — and why it belongs in front of
--   Sec rather than inside a convenience.
--   ⚠ CLASS, stated precisely because the loose form weakens ADR-011 Decision 1:
--   this is a MIGRATION-ROLE write — D1-ADJACENT, not a D1 instance. It meets
--   D1 (a) and (c), and meets NEITHER (b) — the writer is the schema owner, not
--   service_role — NOR (d): no audit-log row is emitted. Its tenant-resolution
--   record is the version-controlled, joint-reviewed migration file plus the
--   applied-migrations ledger. Do not cite 091 as precedent for a service_role
--   surface shipping without (d). This is the 077 disposition, unchanged.
--   The tenant binding is not asserted here; it is INHERITED: every users_id
--   written comes from a users_id already present in pfin.posting_prototype. The
--   statement cannot mint a users_id, cannot cross one tenant's row into
--   another's, and cannot reach a user who has no prototypes at all.
--
-- ----------------------------------------------------------------------------
-- REACH DECISION (ADR-057, stated ONCE and covering the COLUMN and the SEED
-- TOGETHER, per ADR-062 Decision 5).
--
--   THIS CHANGE REACHES ALREADY-PROVISIONED USERS BY EXPLICIT BACKFILL, because
--   first-access provisioning CANNOT deliver it.
--
--   THE MECHANISM, MEASURED NOT ASSUMED. `provisionCashflowPrototypes`
--   (api/src/lib/server/queries/taxonomy.ts) is EXISTENCE-GUARDED on its own
--   table: it reads pfin.posting_prototype for the caller and returns early when
--   any row exists (084 / Sec F3 made the guard split per table). A user holding
--   even ONE posting_prototype row therefore NEVER receives a later default-set
--   addition through that path. New signups are fine; existing users are reached
--   by nothing the seed alone does.
--
--   ⚠ ADR-057's RULE, GENERALIZED. ADR-057 was authored with 077, BEFORE the 084
--   split, and its text scopes to the pfin.taxonomy_default → pfin.user_taxonomy
--   STORAGE pair. The split created a second default/per-user pair on the POSTING
--   side, and the rule generalizes to it unchanged. ADR-062 Decision 5 records
--   that generalization; 077 is the precedent for shipping the delta WITH its
--   backfill.
--
--   THE COLUMN half of the reach question is answered by the DDL itself: an
--   ALTER TABLE reaches every existing row in both tables, so statements (1)–(4)
--   are total over the current population by construction. The SEED half is what
--   needs statement (6).
--
--   ⚠ THE RESTRICTION ON (6) IS LOAD-BEARING, NOT TIDINESS. Its user set is
--   `select distinct users_id from pfin.posting_prototype` — the already-
--   provisioned set BY CONSTRUCTION. Inserting these rows for a user with ZERO
--   prototypes would be actively harmful: it would satisfy the app-side existence
--   guard, and that user would then be SKIPPED by first-access provisioning
--   forever — permanently stranded with two Sub-Cats instead of the full set. A
--   zero-row user is absent by construction rather than excluded by a predicate
--   someone could later "simplify" away. If you are editing statement (6), that
--   is the property to preserve.
--
--   WHY NOT A LOCAL DATABASE RESET. The Supabase CLI's reset subcommand is BANNED
--   for all agents under any flags — standing order, permanent, after the
--   2026-08-14 shared-DB wipe (docs/records/2026-08-14-db-reset-incident.md).
--   Beyond the order it is the wrong instrument: destructive of local test data,
--   F/CTO-executed rather than agent-executable, and inert for any environment
--   that is not a throwaway.
--
-- ----------------------------------------------------------------------------
-- ⚠ PAIRED APP-SOURCE CHANGE — SHIPS IN THE SAME PR (ADR-062 Decision 6). This
--   is NOT housekeeping, and a migration author reading only supabase/migrations/
--   will not find it; it is recorded here because that is the reader who breaks
--   it.
--
--   api/src/lib/server/queries/taxonomy.ts builds its provisioning INSERT from an
--   EXPLICIT column list. `is_tax_payment` is NOT NULL with no DEFAULT. Omit the
--   pairing and a fresh signup receives ZERO cash-flow prototypes, with nothing
--   but a `console.error` line to say so — the branch is fail-soft. The identical
--   hazard was caught once already when 085 added `element` on the asset side.
--
--   ⚠ AND THE FIX IS NOT "widen the shared constant." At authoring time the
--   cash-flow branch selects DEFAULT_PROVISION_COLUMNS, which the ASSET branch
--   also consumes (as the base of ASSET_DEFAULT_PROVISION_COLUMNS). Widening the
--   SHARED constant would make the asset branch ask pfin.taxonomy_default for a
--   column this migration does not put there, breaking the OTHER branch — the
--   mirror image of the 085 hazard. The cash-flow branch needs its OWN column
--   set, exactly as the asset branch got one at 085. Backend owns that edit;
--   this file states the obligation, it does not perform it.
--
-- ----------------------------------------------------------------------------
-- ⚠ THE MARKING PASS IS A HARD PRECONDITION ON THE §2.3.4 SURFACE SHIPPING —
--   NOT A FOLLOW-UP (ADR-062 Decision 3). This migration delivers the column and
--   sets every existing row false; it does not and cannot decide WHICH
--   Expense-class prototypes are tax payments. That enumeration is F/CTO's, it
--   covers Expense-class prototypes ONLY, and until it is applied the
--   discretionary-expenses filter would silently include every tax payment.
--   ⚠ The gate is a SEQUENCING COMMITMENT, NOT A MECHANISM: nothing in this
--   schema prevents the surface being built against an unmarked column, so the
--   gate must live in the consuming issue's acceptance criteria and not only in
--   an ADR or in this header.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — ADR-011 Decision 4 REFERENCED, not restated;
-- no count is carried here, deliberately). Decision 4 was read VERBATIM and LIVE
-- before drafting. This migration introduces ZERO catalogued §10 instances — it
-- has no credential surface, no code-layer fence, and no network/config surface.
--   (i)   Instance-numbering: UNCHANGED — nothing added, removed, reordered or
--         renumbered.
--   (ii)  Layer-attribution: UNCHANGED — no catalogued instance's layer moves and
--         no surface becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is LINKED, not restated.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED set are DIFFERENT SETS; this
--   migration changes neither and reconciles neither.
--
-- ----------------------------------------------------------------------------
-- ADR-011 DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family
-- UNCHANGED (+0). Stated PER COLUMN, per 085's rule, because 084's Amendment 1
-- records the check not actually having been run on the second table of a pair.
--   pfin.posting_prototype.is_tax_payment — `boolean`. Not FK-shaped: no FK, no
--     reference to any relation, not an array of ids. There is no referenced row,
--     therefore no tenant to match; no matched-tenant validation is owed and none
--     is authored.
--   pfin.posting_prototype_default.is_tax_payment — `boolean`. Same evaluation,
--     run independently. Additionally, that table carries NO users_id at all, so
--     it has no tenant anchor a matched-tenant fence could compare against.
--   The Equity rows added by (5) and (6) introduce no column and no reference.
--   (6) writes pfin.posting_prototype.users_id, which is that table's TENANT
--     ANCHOR — not a cross-tenant reference — and copies it from an existing row
--     of the SAME table, so there is no second anchor that could mismatch.
--   Read ADR-011 Decision 3 LIVE for the family; this file carries no tally.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.posting_prototype gains        is_tax_payment boolean NOT NULL, no DEFAULT.
--   pfin.posting_prototype_default gains is_tax_payment boolean NOT NULL, no DEFAULT.
--     No CHECK on either — see the shape rationale above.
--     Meaning is SCOPED TO Expense-class prototypes; see the column comments.
--   pfin.posting_prototype_default gains exactly TWO rows, closing the gap where
--     §2.3.3's ruled Transfer-union-Equity section had no seeded Equity rows at
--     all (041 seeded none) against ADR-031's ratified class map:
--       cat='Equity', sub_cat='Contribution',
--         tax_relevant=true, tax_character=null, is_tax_payment=false,
--         notes='potentially deductible; resolve per account type at the V1.4 tax inventory'
--       cat='Equity', sub_cat='Distribution',
--         tax_relevant=false, tax_character=null, is_tax_payment=false
--     tax_relevant=true on Contribution is the SAFE DIRECTION UNDER UNCERTAINTY,
--     not a determination: a retirement contribution may be deductible or not
--     (Roth / non-deductible), and one seeded value covers both cases. `true`
--     makes the row SURFACE FOR REVIEW in the V1.4 tax computation rather than
--     disappear from it — a false negative there is silent, a false positive is
--     merely examined. ⚠ The notes rider is PART OF THE ROW, not a comment on it,
--     so the flag reads flag-for-review, never always-deductible.
--     Both Equity rows are pre-marked is_tax_payment=false: an owner capital
--     movement is not a tax payment, so the value is TRUE rather than merely
--     inert, and it is additionally unreachable by an Expense-scoped consumer.
--   pfin.posting_prototype gains those same two rows per already-provisioned
--     user, via (6). Idempotent on re-run — unique (users_id, cat, sub_cat) plus
--     `on conflict do nothing`.
--   Security-load-bearing edges: no DEFAULT on either column (fail-closed on
--     INSERT); (6)'s user set derived from posting_prototype itself (tenant
--     binding inherited, zero-row users unreachable by construction); no policy,
--     grant, trigger or function added or altered.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- (1) Add the column, NULLABLE, on BOTH tables. Nullable first so the backfill
-- has something to write into; the NOT NULL arrives at (3).
-- ----------------------------------------------------------------------------
alter table pfin.posting_prototype
  add column if not exists is_tax_payment boolean;

alter table pfin.posting_prototype_default
  add column if not exists is_tax_payment boolean;

-- ----------------------------------------------------------------------------
-- (2) TOTAL backfill of the existing population on both tables. `false` is the
-- correct pre-marking value and NOT a default: it says "not marked as a tax
-- payment", which is the state every existing row is in until F/CTO's marking
-- enumeration runs. The predicate is `is null` so a re-run is a no-op and so a
-- value already set by hand is never overwritten.
-- ----------------------------------------------------------------------------
update pfin.posting_prototype
   set is_tax_payment = false
 where is_tax_payment is null;

update pfin.posting_prototype_default
   set is_tax_payment = false
 where is_tax_payment is null;

-- ----------------------------------------------------------------------------
-- (3) Make the column total on both tables. This IS the zero-NULL assertion:
-- `set not null` scans the table and FAILS LOUDLY if (2) missed a row. There is
-- no separate count check because there is nothing a count could add.
-- ----------------------------------------------------------------------------
alter table pfin.posting_prototype
  alter column is_tax_payment set not null;

alter table pfin.posting_prototype_default
  alter column is_tax_payment set not null;

-- ----------------------------------------------------------------------------
-- (4) No CHECK constraint is added. Deliberate — see the shape rationale in the
-- header. `not null` on a boolean already bounds the domain to exactly
-- {true, false}; a named CHECK here could not fire.
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- (5) The Equity seed pair. Every value is stated explicitly, including
-- is_tax_payment — which is the fail-closed shape working as intended: this
-- INSERT would ERROR if the column were omitted. `on conflict do nothing` so a
-- re-run is a no-op and so this is safe against a hand-seeded environment.
--
-- display_order: 280 / 290 continues the existing decade grid past its current
-- maximum, so no existing row is renumbered. Nothing ratified fixes where the
-- Equity class sorts relative to Trade; if F/CTO wants class-order placement
-- instead, that is a later display_order-only migration and touches no other
-- column.
-- ----------------------------------------------------------------------------
insert into pfin.posting_prototype_default
  (cat, sub_cat, tax_relevant, tax_character, display_order, notes, is_tax_payment)
values
  ('Equity', 'Contribution', true,  null, 280,
   'potentially deductible; resolve per account type at the V1.4 tax inventory',
   false),
  ('Equity', 'Distribution', false, null, 290,
   'Owner capital distribution — value moved out of the portfolio to the owner',
   false)
on conflict (cat, sub_cat) do nothing;

-- ----------------------------------------------------------------------------
-- (6) Backfill the two Equity rows into every ALREADY-PROVISIONED user's
-- posting_prototype row-set. See the REACH DECISION in the header: first-access
-- provisioning is existence-guarded and cannot deliver a later default-set
-- addition to a user who already holds prototypes.
--
-- The user set is `select distinct users_id from pfin.posting_prototype` — which
-- IS the already-provisioned set, by construction. A user with no prototype rows
-- contributes no users_id and therefore cannot be reached; see the load-bearing
-- note in the header for why that matters.
--
-- The row VALUES are read from pfin.posting_prototype_default rather than
-- repeated, so statement (5) is the single source and the two cannot drift apart.
-- ----------------------------------------------------------------------------
insert into pfin.posting_prototype
  (users_id, cat, sub_cat, tax_relevant, tax_character, display_order, notes,
   is_tax_payment)
select
  provisioned.users_id,
  d.cat, d.sub_cat, d.tax_relevant, d.tax_character, d.display_order, d.notes,
  d.is_tax_payment
from pfin.posting_prototype_default d
cross join (select distinct pp.users_id from pfin.posting_prototype pp) provisioned
where d.cat = 'Equity'
  and d.sub_cat in ('Contribution', 'Distribution')
on conflict (users_id, cat, sub_cat) do nothing;

-- ----------------------------------------------------------------------------
-- (7) Catalog comments — one per column, per the mirrored-pair discipline.
-- ----------------------------------------------------------------------------
comment on column pfin.posting_prototype.is_tax_payment is
  'Marks a posting prototype as a TAX PAYMENT — the flag PRD §2.3.4 reads to '
  'EXCLUDE a bucket from "discretionary monthly expenses" (ADR-062 Decisions 1 + '
  '2, realized at 091). '
  '⚠ SCOPED TO Expense-class prototypes. The question this flag answers is asked '
  'only where cat = ''Expense''. On any other class the value MUST NOT be read as '
  'an answered question — it is the value the NOT NULL requires, not a '
  'determination about that class. A reader who drops the class scope will draw '
  'a conclusion this column does not support. '
  'NOT NULL with NO DEFAULT, deliberately: every INSERT must state the value, so '
  'a prototype authored outside the seed path errors rather than landing silently '
  'discretionary. Fail-closed by ABSENCE of a default — re-adding a DEFAULT would '
  'remove that fence. '
  'NO CHECK, also deliberately: not null already bounds a boolean to exactly '
  '{true, false}, so a named CHECK here could not fire. A boolean → text widening '
  'is the recorded path if a third class is ever required (ADR-062 Alternatives). '
  '⚠ NOT SUFFICIENT ALONE. This column CARRIES the marks; it does not PRODUCE '
  'them and cannot report whether the marking pass over Expense-class prototypes '
  '(ADR-062 Decision 3) has been applied. Consumers MUST NOT infer from a false '
  'that the question was asked. '
  'Mirrored on pfin.posting_prototype_default, which is the provisioning source '
  'for this column (ADR-058 Decision 3 pair discipline). '
  'Not FK-shaped — no FK, no relation reference, not an array of ids — so no '
  'matched-tenant validation is owed; read ADR-011 Decision 3 live for the '
  'family.';

comment on column pfin.posting_prototype_default.is_tax_payment is
  'Marks a default posting prototype as a TAX PAYMENT — the provisioning-source '
  'mirror of pfin.posting_prototype.is_tax_payment (ADR-062 Decisions 1 + 2, '
  'realized at 091). '
  '⚠ SCOPED TO Expense-class prototypes. The question this flag answers is asked '
  'only where cat = ''Expense''. On any other class the value MUST NOT be read as '
  'an answered question — it is the value the NOT NULL requires, not a '
  'determination about that class. '
  'NOT NULL with NO DEFAULT, deliberately: every INSERT must state the value, so '
  'a seed delta that forgets this column errors rather than landing a row that '
  'silently reads discretionary. Fail-closed by ABSENCE of a default. '
  'NO CHECK, also deliberately: not null already bounds a boolean to exactly '
  '{true, false}, so a named CHECK here could not fire. '
  '⚠ REACH: a value seeded here is copied to users provisioned AFTER it lands. '
  'First-access provisioning is existence-guarded, so it reaches an '
  'ALREADY-provisioned user only by an explicit backfill shipped with the change '
  '(ADR-057, generalized to this posting-side pair by ADR-062 Decision 5). Any '
  'future change to this column''s content MUST make that reach decision '
  'explicitly rather than assume provisioning delivers it. '
  '⚠ A PAIRED APP-SOURCE OBLIGATION rides this column: the cash-flow provisioning '
  'INSERT is built from an explicit column list, so this column MUST appear in '
  'that list — and in the CASH-FLOW-side list only, never in one shared with the '
  'asset branch, whose source table has no such column (ADR-062 Decision 6). '
  'Not FK-shaped, and this table carries no users_id at all — no tenant anchor '
  'exists to match against; read ADR-011 Decision 3 live for the family.';

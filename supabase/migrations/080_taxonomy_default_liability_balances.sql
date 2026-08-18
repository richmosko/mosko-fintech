-- ============================================================================
-- Migration: pfin.taxonomy_default — seed delta adding the raw liability-balance
-- catch-all asset Sub-Cat 'Liability Balances' under Cat 'Liabilities', plus the
-- matching backfill for already-provisioned pfin.user_taxonomy rows.
-- Phase 6 Build Loop. Account-type-aware cash routing, F/CTO-ratified 2026-08-17
-- (Option B of the Architect design pass). Closes no SD/RT; extends no lock.
--
-- WHY: a liability-type account's balance routes through 076's cash leg into the
--   tenant's single per-currency classification, netting card debt into the
--   raw-cash row instead of surfacing under Liabilities. The GL beneath is
--   correct — per-account signed balances, and fn_nav_composition's Debt subtotal
--   groups by account_type — but the ALLOCATION-CLASSIFICATION layer is
--   account-type-blind for cash. The tell that this was never intended is in the
--   seed itself: 041's 'Credit-Balance' row is described as "Credit Card or other
--   Revolving Credit Balance", so the taxonomy promised card balances a home the
--   substrate could not deliver them to.
--
-- WHY A NEW ROW RATHER THAN ROUTING TO 'Credit-Balance'. Because account_type
--   CONFLATES revolving credit with loans, and nothing in the schema separates
--   them: the string `subtype` appears in NO migration, and pfin.account carries
--   no column finer than account_type (whose domain is depository / investment /
--   retirement / crypto / manual_other / real_estate / liability). 041 itself
--   distinguishes Credit-Balance from Loan-Balance and EstTax-Pending, so routing
--   every liability account to Credit-Balance would file a mortgage under
--   "Revolving Credit Balance" — trading a VISIBLE classification error for a
--   quieter one of the same class. This row asserts NO instrument, which is the
--   honest statement of what the substrate can determine.
--   ⚠ The alternative that looks natural and is closed: pfin.account.sub_cat_id
--   was DROPPED at 048 (SELF-319) as dead schema, taking ADR-011 Decision 3
--   canonical instance #5 and its fn_account_matched_sub_cat fence with it. A
--   per-account classification column is not available and re-introducing one is
--   a V2 question (PRD §2.2.1 defers USER-DECIDED per-account classification;
--   F/CTO ratified 2026-08-17 that a mechanical rule is not what that fence
--   defers).
--
-- WHAT THIS DOES NOT DO: it prunes nothing and renames nothing. The three
--   existing Liabilities Sub-Cats keep their labels, their notes, and their
--   display_order. It authors no function, no policy, no grant, no trigger and
--   no column, and it changes no routing — 081 does that.
--
-- ----------------------------------------------------------------------------
-- Numbering: 080 follows 079 (volatility pins); taken at authoring time against
--   the live listing, not reserved. Order-dependent: must run AFTER 041
--   (pfin.taxonomy_default and its seed) and AFTER 009 (pfin.user_taxonomy and
--   its unique (users_id, domain, cat, sub_cat) — the backfill's conflict
--   target). ⚠ MUST run BEFORE 081, which routes liability cash to the row this
--   migration creates: 081 matches that row BY NAME, so with 080 absent every
--   liability account's cash would land in the unclassified row instead. That is
--   fail-soft rather than fail-loud, which is exactly why the ordering is stated
--   here rather than left to the numbering.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — NO function authored, so neither SECURITY INVOKER nor
--   SECURITY DEFINER applies and `set search_path = ''` is N/A. This migration is
--   two INSERTs. The SECURITY DEFINER allowlist is UNCHANGED — read it live at
--   ADR-011 Decision 9; this file states no count.
--
-- ----------------------------------------------------------------------------
-- ⚠ PRIVILEGED-CONTEXT WRITE — Sec joint-review item, and the CLASS is stated
--   precisely because the loose form weakens D1. The backfill writes rows into
--   pfin.user_taxonomy, a TENANT-OWNED table, from the migration role. No pfin
--   table carries FORCE ROW LEVEL SECURITY, so the owning role is not subject to
--   the policies on it and the 025 aal2 backstop clause on user_taxonomy_insert
--   is not evaluated — which is WHY a backfill reaches users the app path cannot.
--   This is a MIGRATION-ROLE write — D1-ADJACENT, not a D1 instance. It meets
--   D1 (a) and (c), and it meets NEITHER (b) — the writer is the schema owner,
--   not service_role — NOR (d): no audit-log row is emitted. Its
--   tenant-resolution record is the version-controlled, joint-reviewed migration
--   file plus the applied-migrations ledger, which is a STRONGER forensic record
--   than (d) provides for a runtime writer, not a waiver of it. Do not cite this
--   migration as precedent for a service_role surface shipping without (d). D1's
--   four clauses bind unchanged at every runtime privileged context.
--   The tenant binding is not asserted here; it is INHERITED: every users_id
--   written comes from a users_id already present in pfin.user_taxonomy.
--
-- ----------------------------------------------------------------------------
-- REACH DECISION — ADR-057, applied rather than re-derived. This is the second
--   instance of the pattern that ADR names, and the decision is the same one:
--   a TARGETED BACKFILL INSERT, restricted BY CONSTRUCTION to users who already
--   hold at least one pfin.user_taxonomy row.
--   041's first-access provisioning is EXISTENCE-GUARDED, so an already-
--   provisioned user receives no default-set addition through it. New users take
--   the unchanged provision statement, which reads this table.
--   ⚠ THE RESTRICTION IS LOAD-BEARING, NOT TIDINESS. Inserting this row for a
--   user with ZERO taxonomy rows would satisfy 041's existence guard and strand
--   them without the rest of the default set, permanently. The backfill therefore
--   derives its user set from `select distinct users_id from pfin.user_taxonomy`
--   so a zero-row user is absent BY CONSTRUCTION rather than excluded by a
--   predicate someone could later "simplify" away. If you are editing this
--   statement, that is the property to preserve.
--   A full local database reset is not a reach mechanism: the Supabase CLI's
--   reset subcommand is BANNED for all agents under any flags (standing order,
--   permanent, after the 2026-08-14 shared-DB wipe —
--   docs/records/2026-08-14-db-reset-incident.md), it is destructive of F/CTO's
--   local test data, and it would do nothing for any environment that is not a
--   throwaway.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — ADR-011 Decision 4 referenced, NOT restated;
-- no count is carried here, deliberately). Decision 4 was read verbatim and live
-- before drafting. This migration introduces ZERO catalogued §10 instances — it
-- has no credential surface, no code-layer fence, and no network/config surface.
--   (i)   Instance-numbering: UNCHANGED — nothing added, removed, reordered or
--         renumbered.
--   (ii)  Layer-attribution: UNCHANGED — no catalogued instance's layer moves and
--         no surface becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is LINKED, not restated.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED set are different sets; this
--   migration changes neither and reconciles neither.
--   LEDGER STATUS: FLAT.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family UNCHANGED (+0),
--   in the honest form: no column is created, altered or dropped by this
--   migration, so there is no FK-shaped column to evaluate. pfin.taxonomy_default
--   remains global, users_id-free reference data. The backfill writes
--   pfin.user_taxonomy.users_id, which is that table's TENANT ANCHOR — not a
--   cross-tenant reference — and it is copied from an existing row of the same
--   table, so there is no second anchor that could mismatch. Read ADR-011
--   Decision 3 live for the family; this file carries no tally.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.taxonomy_default gains exactly ONE row:
--     domain='asset', cat='Liabilities', sub_cat='Liability Balances',
--     tax_relevant=false, tax_character=null  (tax-neutral, as every asset row is
--       in V1 — ADR-006 Axis 2 dormant),
--     display_order=285  (FIRST among the Liabilities rows, which run 290/300/310;
--       slotting BELOW the existing floor is what makes "first" true without
--       renumbering a single existing row — the 077 idiom),
--     notes= the raw liability-balance catch-all statement, including that it
--       asserts NO instrument.
--   pfin.user_taxonomy gains that same row, per already-provisioned user, via the
--     backfill. Idempotent on re-run (unique (users_id, domain, cat, sub_cat) +
--     on conflict do nothing).
--   Security-load-bearing edges: the backfill's user set is derived from
--     user_taxonomy itself (tenant binding inherited, zero-row users unreachable);
--     no policy, grant or trigger is added or altered; taxonomy_default remains
--     read-only to every application tier.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- (1) The seed delta itself. `on conflict do nothing` so a re-run is a no-op and
-- so this is safe against an environment that already added the row by hand.
-- ----------------------------------------------------------------------------
insert into pfin.taxonomy_default
  (domain, cat, sub_cat, tax_relevant, tax_character, display_order, notes)
values
  ('asset', 'Liabilities', 'Liability Balances', false, null, 285,
   'Raw balance of a liability-type account — the catch-all for account-level '
   'debt. Asserts NO instrument: where the instrument IS known, the balance '
   'belongs in Credit-Balance (revolving credit), Loan-Balance (a loan) or '
   'EstTax-Pending (taxes due) instead. Naturally signed, so a balance owed is '
   'negative and an overpayment is positive.')
on conflict (domain, cat, sub_cat) do nothing;

-- ----------------------------------------------------------------------------
-- (2) Backfill for already-provisioned users. See REACH DECISION above.
--
-- The user set is `select distinct users_id from pfin.user_taxonomy` — which IS
-- the set of already-provisioned users, by construction. A user with no taxonomy
-- rows contributes no users_id and therefore cannot be reached; see the
-- load-bearing note in the header for why that matters.
--
-- The row VALUES are read from pfin.taxonomy_default rather than repeated, so
-- statement (1) is the single source and the two cannot drift apart.
-- ----------------------------------------------------------------------------
insert into pfin.user_taxonomy
  (users_id, domain, cat, sub_cat, tax_relevant, tax_character, display_order, notes)
select
  provisioned.users_id,
  d.domain, d.cat, d.sub_cat, d.tax_relevant, d.tax_character, d.display_order, d.notes
from pfin.taxonomy_default d
cross join (select distinct ut.users_id from pfin.user_taxonomy ut) provisioned
where d.domain = 'asset' and d.cat = 'Liabilities' and d.sub_cat = 'Liability Balances'
on conflict (users_id, domain, cat, sub_cat) do nothing;

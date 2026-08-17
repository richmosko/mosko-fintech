-- ============================================================================
-- Migration: pfin.taxonomy_default — seed delta adding the raw-cash catch-all
-- asset Sub-Cat 'Cash Balances' under Cat 'Cash', plus the matching backfill for
-- already-provisioned pfin.user_taxonomy rows.
-- Phase 6 Build Loop. BACKLOG §7.20 item 1 (F/CTO-ratified 2026-08-17, the L1
-- cash-granularity ruling). Closes no SD/RT; extends no lock.
--
-- WHY: the ruling is instrument-routed cash — raw cash classifies ONCE PER USER
--   PER CURRENCY into a bucket that must be labeled 'Cash' (or equivalent),
--   never FDIC/SPIC, because those names assert an insurance regime a catch-all
--   does not honor. The 041 seed's asset 'Cash' Cat carries FDIC / SPIC /
--   T-Bill / CD only — every one of which asserts an instrument or an insurance
--   regime — so the bucket the ruling requires does not exist for any user. V1
--   taxonomy is SEED-ONLY (Lock 7 / 009 / 041: no CRUD UI; the sole V1 caller of
--   the INSERT path is the existence-guarded provisioning bootstrap), so the
--   bucket cannot be created by a user either. A seed delta is therefore
--   REQUIRED, not merely convenient.
--   The label is 'Cash Balances', F/CTO-fixed 2026-08-17. 'Cash Equivalents' was
--   considered and rejected: in accounting usage that term denotes exactly the
--   short-dated instruments this bucket EXCLUDES (T-Bill / CD already have their
--   own rows).
--
-- WHAT THIS DOES NOT DO: it prunes nothing. The four existing Cash Sub-Cats are
--   untouched — the ruling says none pruned, and PRD §3.3's strict Sub-Cat
--   enumeration equality forbids pruning independently of the ruling. It authors
--   no function, no policy, no grant, no trigger, and no column.
--
-- ----------------------------------------------------------------------------
-- Numbering: 077 follows 076 (fn_subcat_market_value); taken at authoring time
--   against the live listing, not reserved. Order-dependent: must run AFTER
--   041 (pfin.taxonomy_default and its seed) and AFTER 009 (pfin.user_taxonomy
--   and its unique (users_id, domain, cat, sub_cat) — the conflict target the
--   backfill relies on). No later migration depends on 077 landing first.
--   Independent of 078 / 079 in this same branch: they touch functions, this
--   touches rows.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — NO function authored, so neither SECURITY INVOKER nor
--   SECURITY DEFINER applies and `set search_path = ''` is N/A. This migration
--   is two INSERTs and one `comment on table`. The SECURITY DEFINER allowlist is
--   UNCHANGED — read it live at ADR-011 Decision 9; this file states no count.
--
-- ----------------------------------------------------------------------------
-- ⚠ PRIVILEGED-CONTEXT WRITE — Sec joint-review item, stated rather than
--   assumed. The backfill below writes rows into pfin.user_taxonomy, a
--   TENANT-OWNED table, from the migration role. No pfin table carries FORCE ROW
--   LEVEL SECURITY, so the owning/migrating role is not subject to the RLS
--   policies on it, and the 025 aal2 backstop clause on user_taxonomy_insert is
--   likewise not evaluated. That is precisely WHY a backfill can reach users the
--   app path cannot — and it is also why it is a privileged-context write in the
--   ADR-011 Decision 1 sense and belongs in front of Sec rather than inside a
--   convenience.
--   The tenant binding is not asserted by this migration; it is INHERITED: every
--   users_id written comes from a users_id already present in pfin.user_taxonomy.
--   The statement cannot mint a users_id, cannot cross one tenant's row into
--   another's, and cannot reach a user who has no taxonomy at all.
--
-- ----------------------------------------------------------------------------
-- REACH DECISION (the item BACKLOG §7.20 AC-3 assigns to Architect).
--
--   THE PROBLEM. 041's first-access provisioning is EXISTENCE-GUARDED — the
--   bootstrap runs `select 1 from pfin.user_taxonomy where users_id = auth.uid()
--   limit 1` and SKIPS the INSERT if any row exists. 041's own GROWTH NOTE draws
--   the consequence: an already-provisioned user does not receive default-set
--   additions through that path AT ALL, under either policy shape, regardless of
--   aal. New users are fine (they take the unchanged provision statement, which
--   reads this table). Existing users are not reached by anything 041 does.
--
--   DECISION: a TARGETED BACKFILL INSERT, in this migration, restricted BY
--   CONSTRUCTION to users who already hold at least one pfin.user_taxonomy row.
--
--   WHY NOT A FULL LOCAL DATABASE RESET. The Supabase CLI's reset subcommand is
--   BANNED for all agents under any flags — standing order, permanent, after the
--   2026-08-14 shared-DB wipe (docs/records/2026-08-14-db-reset-incident.md).
--   Beyond the order it is the wrong instrument here: it is destructive of
--   F/CTO's local test data, it is an F/CTO-EXECUTED path rather than an
--   agent-executable one, and it would do nothing at all for any environment
--   that is not a throwaway. A backfill is
--   agent-authorable, non-destructive, idempotent, and is the vehicle 041 itself
--   names for exactly this case ("a future set-growth that must reach existing
--   users would be its own data-migration/backfill decision").
--
--   WHY NOT "do nothing, the project is greenfield". True today and worthless
--   tomorrow: the moment a user exists whose provisioning predates 077, the
--   §2.2.2 Cash rendering assumes a bucket that user does not have, and nothing
--   in the system would ever give it to them. The defect would be invisible in a
--   fresh database and permanent in an old one — the worst combination to debug.
--
--   ⚠ THE RESTRICTION IS LOAD-BEARING, NOT A FILTER FOR TIDINESS. Inserting this
--   row for a user with ZERO taxonomy rows would be actively harmful: it would
--   satisfy 041's existence guard, and that user would then be SKIPPED by
--   first-access provisioning forever — permanently stranded with one Sub-Cat
--   instead of the full default set. The backfill therefore derives its user set
--   from `select distinct users_id from pfin.user_taxonomy`, so a zero-row user
--   is absent BY CONSTRUCTION rather than excluded by a predicate someone could
--   later "simplify" away. If you are editing this statement, that is the
--   property to preserve.
--
--   The GENERALISED rule — every future change to this table's content owes the
--   same explicit reach decision — is recorded at ADR-057. This header carries
--   the instance; that entry carries the rule and the rejected alternatives.
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
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family UNCHANGED (+0).
--   Stated explicitly per the mandatory FK-shaped-column check, and in the honest
--   form: no column is created, altered, or dropped by this migration, so there is
--   no FK-shaped column to evaluate. pfin.taxonomy_default remains global,
--   users_id-free reference data. The backfill writes pfin.user_taxonomy.users_id,
--   which is that table's TENANT ANCHOR — not a cross-tenant reference — and it is
--   copied from an existing row of the same table, so there is no second anchor
--   that could mismatch. Read ADR-011 Decision 3 live for the family; this file
--   carries no tally.
--
-- ----------------------------------------------------------------------------
-- CATALOG-COMMENT CORRECTION carried by this migration (the 052 vehicle rule:
--   text WITH a database representation can only change by issuing new SQL).
--   041's `comment on table pfin.taxonomy_default` carries a ROW COUNT and a
--   per-domain split. This migration is the thing that makes them false. Rather
--   than increment a number that the next seed delta will falsify again, the
--   count clause is REMOVED and the comment says where to look instead. The
--   supersession is named in the comment itself so a reader who remembers the old
--   text learns it changed rather than doubting their memory.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.taxonomy_default gains exactly ONE row:
--     domain='asset', cat='Cash', sub_cat='Cash Balances',
--     tax_relevant=false, tax_character=null  (tax-neutral, as every asset row is
--       in V1 — ADR-006 Axis 2 dormant),
--     display_order=5  (FIRST among the Cash rows, which run 10/20/30/40; slotting
--       BELOW the existing floor is what makes "first" true without renumbering a
--       single existing row),
--     notes= the per-currency raw-cash catch-all statement, including that it
--       asserts NO insurance regime.
--   pfin.user_taxonomy gains that same row, per already-provisioned user, via the
--     backfill. Idempotent on re-run (unique (users_id, domain, cat, sub_cat) +
--     on conflict do nothing).
--   Security-load-bearing edges: the backfill's user set is derived from
--     user_taxonomy itself (tenant binding inherited, zero-row users unreachable);
--     no policy, grant, or trigger is added or altered; taxonomy_default remains
--     read-only to every application tier.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- (1) The seed delta itself. `on conflict do nothing` so a re-run is a no-op and
-- so this is safe against a hand-seeded environment that already added the row.
-- ----------------------------------------------------------------------------
insert into pfin.taxonomy_default
  (domain, cat, sub_cat, tax_relevant, tax_character, display_order, notes)
values
  ('asset', 'Cash', 'Cash Balances', false, null, 5,
   'Raw cash balance catch-all — one classification per user per currency. '
   'Asserts NO insurance regime and names no instrument: cash covered by a '
   'specific regime or held as a specific instrument belongs in FDIC / SPIC / '
   'T-Bill / CD instead.')
on conflict (domain, cat, sub_cat) do nothing;

-- ----------------------------------------------------------------------------
-- (2) Backfill for already-provisioned users. See REACH DECISION above.
--
-- The user set is `select distinct users_id from pfin.user_taxonomy` — which IS
-- the set of already-provisioned users, by construction. A user with no taxonomy
-- rows contributes no users_id and therefore cannot be reached; see the
-- load-bearing note in the header for why that matters (giving such a user one
-- row would trip 041's existence guard and strand them permanently).
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
where d.domain = 'asset' and d.cat = 'Cash' and d.sub_cat = 'Cash Balances'
on conflict (users_id, domain, cat, sub_cat) do nothing;

-- ----------------------------------------------------------------------------
-- (3) Catalog-comment correction on pfin.taxonomy_default — the count clause 041
-- carried is removed rather than incremented. See the header.
-- ----------------------------------------------------------------------------
comment on table pfin.taxonomy_default is
  'Global canonical default two-level Cat x Sub-Cat taxonomy (ADR-036 / SELF-311, '
  'B1+A1). The single committed source for default-taxonomy provisioning — the '
  'asset (§2.2.1) + cashflow (§2.3.1) default set, ported verbatim at 041 from the '
  'pre-041 gitignored seed.sql (which now seeds the dev user FROM this table). '
  'Columns mirror pfin.user_taxonomy MINUS users_id. GLOBAL SHARED-READ (RLS '
  'using(true), authenticated SELECT; anon zero; service_role none) — non-tenant '
  'reference data (category names + notes; no $-figures), so EXCLUDED from the 025 '
  'aal2 backstop per exclusion (i). NO users_id / NO FK — Decision 3 family '
  'UNCHANGED. Content is migration-authored; changing the default set later is a '
  'data migration, and such a change MUST decide separately whether it reaches '
  'already-provisioned users — never assume first-access provisioning delivers it. '
  'SUPERSEDES the row-count clause this comment carried at 041: the set grew '
  'at 077 and a catalog comment cannot carry a figure that a later migration '
  'invalidates — count the table.';

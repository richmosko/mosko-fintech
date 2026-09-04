-- ============================================================================
-- Migration: pfin.posting_prototype{,_default} + pfin.user_taxonomy /
-- pfin.taxonomy_default — the V1.4 tax-value inventory SEED DELTA: value
-- corrections on both pairs with explicit backfill, the `Revenue /
-- Dividend - Qualified` row add, and a `comment on column` on every table
-- carrying `tax_relevant`.
-- Phase 6 Build Loop. SELF-263. Realizes the V1.4 execution-log rulings E4 and
-- E5. Discharges ADR-062 Decision 3's hard precondition (see AC 5 below) and
-- ADR-062 Decision 4's `notes` rider. Closes no SD/RT; extends no lock; authors
-- no function, policy, grant or trigger.
--
-- ----------------------------------------------------------------------------
-- Numbering: 100 follows 099 (fn_cashflow_contributors), taken against the live
--   listing at authoring time. 101 (SELF-259 bracket tables) and 102 (SELF-267)
--   are sibling branches of the same milestone and are independent of this file
--   in both directions — they touch no table this one touches.
--   Order-dependent: must run AFTER 091 (which seeded the two Equity rows and
--   added `is_tax_payment`, the NOT-NULL-no-DEFAULT column every INSERT below
--   must therefore state), AFTER 085 (`element`, likewise NOT NULL with no
--   DEFAULT on the asset pair — not written here because no asset row is added),
--   AFTER 084 (which created the posting pair, its two uniques, and dropped
--   `domain` from the asset pair so the asset natural key is (cat, sub_cat)),
--   and AFTER 082 (the `Equity` → `Marketable Securities` Cat rename, whose
--   post-rename spellings are the ones this file names). No later migration
--   depends on 100 landing first.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — NO function is created, replaced or dropped, so neither
--   SECURITY INVOKER nor SECURITY DEFINER applies and `set search_path = ''` is
--   N/A: this file is UPDATEs, one INSERT per table of one pair, and four
--   `comment on column` statements. The SECURITY DEFINER allowlist is UNCHANGED
--   — read it live at ADR-011 Decision 9; this file states no count.
--   No RLS policy is added or altered. pfin.posting_prototype and
--   pfin.user_taxonomy already carry the 025 aal2 step-up backstop conjunct on
--   their authenticated policies (084 / 025); pfin.posting_prototype_default and
--   pfin.taxonomy_default are 025-EXCLUDED under exclusion (i) as global
--   shared-read. Writing VALUES into existing tables changes neither, and no
--   table is created here, so no aal2 obligation is triggered — that obligation
--   attaches to a NEW sensitive tenant-owned table.
--
-- ----------------------------------------------------------------------------
-- WHAT THIS FILE IS, AND WHAT AUTHORITY IT CARRIES.
--
--   SELF-263's deliverable is an INVENTORY of already-seeded values, not a new
--   surface. Every row of both default tables was dispositioned row by row in
--   PM's proposal (docs/records/v14-execution/self263-inventory.md §1 for the
--   29 cash-flow prototype rows, §2 for the 38 asset rows — both figures
--   measured by PM against the migration files and re-measured against a live
--   post-099 database at this file's verification run, 2026-09-03), and the
--   dispositions were RULED at the V1.4 execution log entries E4 and E5
--   (docs/records/v14-execution/log.md, provenance TEAM-LEAD RULING UNDER
--   DELEGATION per ADR-063). This file encodes the CHANGES only; a row that was
--   confirmed rather than corrected is deliberately absent from the statements
--   below, because a no-op UPDATE would misrepresent a confirmation as an edit.
--
--   ⚠ THE CONFIRMATIONS ARE NOT RECORDED IN THE DATABASE AND CANNOT BE. There is
--   no per-row "inventoried at" column, and E4 declined to add one. The record of
--   WHICH rows were examined is the proposal document plus the execution-log
--   entry, both version-controlled. The column comments at the foot of this file
--   are written so that a reader at `\d+` is not misled into treating a `false`
--   as an answered question in general — see the comment text.
--
--   THE FIVE RULED CHANGES, by execution-log entry:
--     E4 D-i    Equity / Contribution: tax_relevant true → FALSE, tax_character
--               stays NULL, and ADR-062 Decision 4's `notes` rider is REMOVED and
--               replaced with a user-facing description. A contribution of
--               capital is not income; deductibility is per RECEIVING ACCOUNT
--               (pfin.account.tax_treatment, 003), which no prototype row can
--               carry. Losing side: keeping `true` as flag-for-review, with no
--               reviewer after this session and an Income reader that may not be
--               class-scoped — a capital deposit would sum as Ordinary Income.
--     E4 D-ii   Revenue / Bond Premium: value CONFIRMED `ordinary` (§171 premium
--               amortization and market-discount accretion adjust INTEREST, never
--               capital); `notes` corrected, because the seeded note names
--               mark-to-market, which is the §1256 concept the asset-side
--               Volatility-60/40 row owns.
--     E4 D-ii   Revenue / Dividend: tax_character qualified_dividend → ORDINARY,
--               and a NEW Revenue / Dividend - Qualified row = true /
--               qualified_dividend is added (PM's option C′). One row cannot say
--               both characters; the generic bucket takes the FAIL-CLOSED value
--               and the qualified case gets its own row, so the §2.5.3 Federal
--               LT-CG walk stays live (SELF-264 AC 3a's premise holds).
--               Losing side: (C) — generic = qualified — is fail-OPEN for an
--               unsorted user: money-market / REIT / bond-fund distributions
--               would route to LT-CG rates and understate Federal tax. C′'s only
--               cost is re-sorting an existing user's dividend history, which is
--               ZERO on a greenfield deployment.
--               ⚠ E4 flags an F/CTO REVERSAL WINDOW on this one specifically: the
--               better default depends on the actual dividend mix, which F/CTO
--               knows. Reversing it is one value on this row plus one on the new
--               row — no DDL, no data migration.
--     E4 D-iii  Asset-side marking principle, stated once: an asset Sub-Cat is
--     + D-iv    tax_relevant iff a holding under it is disposed of through the
--               §2.4.3 lot machinery AND that disposition is a taxable event
--               §2.5.1 must place in the ST CG / LT CG columns. Realized as 24 ×
--               long_term_capital_gain_eligible + 1 × short_term_only
--               (Cash / T-Bill), everything else staying false / NULL. Real
--               Estate stays false EXPLICITLY — its disposition is UNMODELLED,
--               not tax-free. A sixth `section_1256` code was weighed and NOT
--               taken (no consumer on the tree); the 60/40 split is carried by
--               the Volatility-60/40 Sub-Cat's identity, not by the enum.
--     E5        All of the above plus the four column comments ship in ONE
--               migration: AC 3 / 4 / 6 already co-locate the delta, the backfill
--               and the comments, and the row add is the same backfill shape and
--               the same Sec review.
--
--   ⚠ THE ASSET HALF HAS NO V1.4 CONSUMER (AC 1, R1-A). The capital-gains
--   surface renders UNAVAILABLE while no sale writer exists, so nothing reads
--   these 25 values today. They land here because it is the same act and the
--   delta is cheap. Do not read their presence as evidence a CG path is live.
--
-- ----------------------------------------------------------------------------
-- AC 7 — NO NEW VOCABULARY. Every tax_character value written below is one of
--   the five codes seeded on pfin.tax_character by 011. Membership is enforced
--   two different ways on the two pairs, and BOTH were checked rather than one
--   assumed from the other:
--     · pfin.posting_prototype.tax_character and
--       pfin.posting_prototype_default.tax_character carry FOREIGN KEYs to
--       pfin.tax_character(code) ON DELETE RESTRICT (084).
--     · pfin.user_taxonomy.tax_character carries fk_user_taxonomy_tax_character
--       to the same registry (011, ADR-024 Option C).
--     · pfin.taxonomy_default.tax_character still carries 041's INLINE five-value
--       CHECK (taxonomy_default_tax_character_check) — it was never converted to
--       the FK. That asymmetry is pre-existing, is NOT changed here, and is
--       stated because a reader who checks one table and generalizes will be
--       wrong about the other. Both admit exactly the same five values today.
--   pfin.tax_character_enum is NOT created. A sixth value would be a seed row on
--   011, never a CHECK edit — recorded, not exercised.
--
-- ----------------------------------------------------------------------------
-- REACH DECISION (ADR-057 as generalized to the posting pair by ADR-062
-- Decision 5) — stated ONCE and covering the value corrections, the row add and
-- the asset-side delta TOGETHER.
--
--   THIS CHANGE REACHES ALREADY-PROVISIONED USERS BY EXPLICIT BACKFILL, because
--   first-access provisioning CANNOT deliver it.
--
--   THE MECHANISM, MEASURED NOT ASSUMED. `provisionCashflowPrototypes` and its
--   asset-side sibling in api/src/lib/server/queries/taxonomy.ts are
--   EXISTENCE-GUARDED per table (`if (existing) return;`, split per table at 084
--   / Sec F3). A user holding even ONE pfin.posting_prototype row NEVER receives
--   a later default-set change through that path, and the same holds for
--   pfin.user_taxonomy. Correcting pfin.posting_prototype_default or
--   pfin.taxonomy_default ALONE therefore reaches nobody who already exists — it
--   reaches future signups only.
--
--   ⚠ SO EVERY VALUE STATEMENT BELOW IS WRITTEN TWICE, ONCE PER TABLE OF THE
--   PAIR, AND THE CHECK IS STATED PER TABLE — not once for the pair. 084's
--   Amendment 1 records the per-table check NOT actually having been run on the
--   second table of a pair; that is the failure this discipline exists to
--   prevent, and it is why statements (2), (4) and (6) are separate statements
--   rather than one clever join. Per-table checks:
--     · pfin.posting_prototype_default — corrected by (1); natural key
--       (cat, sub_cat), unique. CHECKED.
--     · pfin.posting_prototype — corrected by (2); natural key
--       (users_id, cat, sub_cat), unique; the (cat, sub_cat) half is the join to
--       the default table. CHECKED.
--     · pfin.taxonomy_default — corrected by (3); natural key (cat, sub_cat)
--       post-084 (`domain` was DROPPED at the split — do not write it). CHECKED.
--     · pfin.user_taxonomy — corrected by (4); natural key
--       (users_id, cat, sub_cat), likewise post-084. CHECKED.
--
--   WHY NOT A LOCAL DATABASE RESET. The Supabase CLI's reset subcommand is BANNED
--   for all agents under any flags — standing order, permanent, after the
--   2026-08-14 shared-DB wipe (docs/records/2026-08-14-db-reset-incident.md).
--   Verification for this file ran on a throwaway clone of the pfin_tmpl
--   template (scripts/db-template-clone.sh), not on any shared database.
--
-- ----------------------------------------------------------------------------
-- WHY EVERY STATEMENT IS GUARDED ON THE VALUE IT REPLACES.
--
--   Each UPDATE below carries, in addition to its natural key, a predicate on the
--   CURRENT value — `tax_relevant is true`, `tax_character = 'qualified_dividend'`,
--   `notes = '<the exact seeded string>'`. Three things follow, and all three are
--   load-bearing:
--     (a) IDEMPOTENCE. A second apply of this file matches zero rows and writes
--         nothing. There is no ON CONFLICT available on an UPDATE, so the guard
--         IS the idempotence mechanism.
--     (b) NON-CLOBBERING. No V1 code path lets a user edit these columns (there
--         is no taxonomy-CRUD surface yet; ADR-062 records it as V2), so equality
--         against the seeded value is exact TODAY. The day a CRUD path lands, a
--         hand-edited row is left ALONE by these predicates rather than silently
--         reverted — which is the behaviour a seed delta should have.
--     (c) A MISS IS SILENT. That is the cost, and it is stated rather than
--         mitigated by a constraint: if a row's current value is not what this
--         file expects, the UPDATE affects zero rows and says nothing. The
--         watcher is QA's paired battery asserting the POST state row by row, not
--         anything in this file. A `get diagnostics` row-count assertion was
--         weighed and not taken: it would fire on a legitimately hand-edited row
--         and turn a correct skip into a failed deploy.
--
--   ⚠ THE ADR-062 DECISION 4 RIDER STRING IS QUOTED EXACTLY, ONCE PER TABLE, and
--   is the guard for the Contribution notes update:
--     'potentially deductible; resolve per account type at the V1.4 tax inventory'
--   It was read verbatim from ADR-062 Decision 4 and from the live row in both
--   tables before this file was written. If a future reader changes that string
--   anywhere, this file's guard is what stops matching — by design.
--
-- ----------------------------------------------------------------------------
-- ⚠ PRIVILEGED-CONTEXT WRITE — Sec joint-review item, stated rather than assumed.
--   Statements (2), (4) and (6) write rows in pfin.posting_prototype and
--   pfin.user_taxonomy, both TENANT-OWNED tables, from the migration role. No
--   pfin table carries FORCE ROW LEVEL SECURITY, so the owning/migrating role is
--   not subject to those tables' RLS policies and the 025 aal2 backstop conjunct
--   is not evaluated. That is precisely WHY a backfill can reach users the app
--   path cannot — and why it belongs in front of Sec rather than inside a
--   convenience.
--   ⚠ CLASS, stated precisely because the loose form weakens ADR-011 Decision 1:
--   this is a MIGRATION-ROLE write — D1-ADJACENT, not a D1 instance. It meets
--   D1 (a) and (c), and meets NEITHER (b) — the writer is the schema owner, not
--   service_role — NOR (d): no audit-log row is emitted. Its tenant-resolution
--   record is the version-controlled, joint-reviewed migration file plus the
--   applied-migrations ledger. This is 091's disposition, unchanged; do not cite
--   100 as precedent for a service_role surface shipping without (d).
--   The tenant binding is not asserted here; it is INHERITED. (2) and (4) UPDATE
--   rows in place and touch no users_id at all. (6)'s users_id comes from a
--   users_id already present in pfin.posting_prototype, so the statement cannot
--   mint a users_id, cannot cross one tenant's row into another's, and cannot
--   reach a user who has no prototypes at all.
--
--   ⚠ THE RESTRICTION ON (6) IS LOAD-BEARING, NOT TIDINESS — 091's note, repeated
--   because it applies verbatim to the identical shape. Its user set is
--   `select distinct users_id from pfin.posting_prototype`: the already-
--   provisioned set BY CONSTRUCTION. Inserting this row for a user with ZERO
--   prototypes would be actively harmful — it would satisfy the app-side
--   existence guard, and that user would then be SKIPPED by first-access
--   provisioning forever, permanently stranded with one Sub-Cat instead of the
--   full set. A zero-row user is absent by construction rather than excluded by a
--   predicate someone could later "simplify" away. If you are editing (6), that
--   is the property to preserve.
--
-- ----------------------------------------------------------------------------
-- ⚠ NO PAIRED APP-SOURCE CHANGE IS OWED BY THIS FILE, and that is a MEASURED
--   claim rather than an omission. ADR-062 Decision 6's hazard is a NEW COLUMN:
--   the provisioning INSERTs are built from explicit column lists, so a column
--   this migration adds must be added to the matching list or a fresh signup
--   receives zero rows through a fail-soft branch. THIS FILE ADDS NO COLUMN. It
--   changes VALUES and adds one ROW, and both provisioning INSERTs read their
--   rows from the default tables with a column list that is unchanged by either.
--   A new default ROW therefore propagates to new signups with no app edit.
--
-- ----------------------------------------------------------------------------
-- AC 5 — ADR-062 DECISION 3's HARD PRECONDITION IS DISCHARGED BY THIS ISSUE,
--   and the discharge is narrower than the sentence sounds, so it is stated
--   precisely.
--
--   Decision 3 commits that the F/CTO marking enumeration runs BEFORE the §2.3.4
--   discretionary-expenses surface ships, and warns that the gate is a SEQUENCING
--   COMMITMENT WITH NO MECHANISM — nothing in the schema prevents the surface
--   being built against an unmarked column. The V1.4 inventory session is that
--   enumeration. It ran over EVERY row of both default tables, which is WIDER
--   than Decision 3's Expense-class scope, because tax_relevant / tax_character
--   are read on Revenue rows too.
--
--   ITS OUTCOME ON THE is_tax_payment AXIS IS ZERO MARKS. All twelve Expense-class
--   prototypes were examined and every one stays is_tax_payment = false: an
--   expense bucket is not a tax payment. So this file changes NO is_tax_payment
--   value, and the absence of an is_tax_payment statement below is a RESULT, not
--   an oversight.
--   ⚠ RESIDUAL, NAMED NOT FIXED: the two Sub-Cats that ARE tax payments —
--   Transfer / Tax - US Federal and Transfer / Tax - California — are
--   TRANSFER-class, and ADR-062 Decision 2 scopes the flag's meaning to
--   Expense-class prototypes. The flag therefore cannot reach the rows it would
--   most obviously describe. This is a pre-existing scope gap, it is unchanged
--   here, and §2.5.3's YTD Paid reads the tax-authority ACCOUNT LEDGER
--   (SELF-267's tax_jurisdiction route), never this flag. Sec's M-6 and F-6(b)
--   are the same obligation as Decision 3's and are discharged with it.
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
-- records the check not having been run on the second table of a pair.
--   ⚠ The loose form of this statement — "no FK-shaped column is touched" —
--   would be FALSE here and is deliberately not used: `tax_character` IS
--   FK-shaped on three of the four tables. The correct evaluation is that its
--   REFERENT carries no tenant anchor.
--     pfin.posting_prototype.tax_character — FOREIGN KEY to
--       pfin.tax_character(code). pfin.tax_character is a GLOBAL value registry
--       (011): it has no users_id column, so there is no second tenant anchor a
--       matched-tenant fence could compare the row's users_id against. No
--       matched-tenant validation is owed and none is authored. The column is
--       WRITTEN here, not created, and its shape is unchanged.
--     pfin.posting_prototype_default.tax_character — same FK, same registry, same
--       evaluation, run independently. Additionally this table carries NO users_id
--       at all, so it has no tenant anchor on either side.
--     pfin.user_taxonomy.tax_character — fk_user_taxonomy_tax_character to the
--       same global registry. Same evaluation, run independently.
--     pfin.taxonomy_default.tax_character — NOT FK-shaped: it carries 041's
--       inline five-value CHECK, references no relation, and the table carries no
--       users_id. Evaluated separately precisely because it differs from its three
--       siblings.
--     tax_relevant (all four tables) — `boolean`. Not FK-shaped: no FK, no
--       relation reference, not an array of ids.
--     notes (posting_prototype, posting_prototype_default) — `text`, free-form.
--       Not FK-shaped.
--     (6) writes pfin.posting_prototype.users_id, which is that table's TENANT
--       ANCHOR — not a cross-tenant reference — copied from an existing row of the
--       SAME table, so there is no second anchor that could mismatch.
--   No column is added, no reference is created, and no existing fence is
--   removed or weakened. Read ADR-011 Decision 3 LIVE for the family; this file
--   carries no tally.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.posting_prototype_default — three rows corrected in place:
--     ('Equity','Contribution')   tax_relevant true → false; tax_character stays
--                                 NULL; notes: ADR-062 D4 rider → user-facing
--                                 description.
--     ('Revenue','Dividend')      tax_character qualified_dividend → ordinary;
--                                 notes name the ordinary/qualified split.
--     ('Revenue','Bond Premium')  value unchanged (ordinary, CONFIRMED); notes
--                                 corrected off the mark-to-market wording.
--   pfin.posting_prototype — the same three corrections per already-provisioned
--     user, keyed on (cat, sub_cat) within each user's row set.
--   pfin.posting_prototype_default gains exactly ONE row:
--     cat='Revenue', sub_cat='Dividend - Qualified', tax_relevant=true,
--     tax_character='qualified_dividend', display_order=65, is_tax_payment=false.
--     display_order 65 is a HALF-STEP inside 041's decade grid, deliberately NOT
--     091's "continue past the current maximum". 091 was adding a new CLASS with
--     no natural neighbour; this row exists to be chosen INSTEAD OF its
--     neighbour (Dividend, 60), so a picker that sorts it after Equity would put
--     the two mutually-exclusive choices at opposite ends of the list. 65 is
--     unoccupied and renumbers nothing. display_order carries no unique
--     constraint on this table (checked in the catalog, not assumed).
--   pfin.posting_prototype gains that same row per already-provisioned user, via
--     (6). Idempotent on re-run — unique (users_id, cat, sub_cat) plus
--     `on conflict do nothing`.
--   pfin.taxonomy_default — 25 rows corrected in place: 24 to
--     tax_relevant=true / tax_character='long_term_capital_gain_eligible' and
--     ('Cash','T-Bill') to tax_relevant=true /
--     tax_character='short_term_only'. The other 13 rows are CONFIRMED false /
--     NULL and are not touched. No row is added or removed.
--   pfin.user_taxonomy — the same 25 corrections per user, keyed on
--     (cat, sub_cat) within each user's row set. No row is added or removed.
--   Four `comment on column ... .tax_relevant` statements — pfin.user_taxonomy
--     (column from 009), pfin.taxonomy_default (041), pfin.posting_prototype
--     (084) and pfin.posting_prototype_default (084). AC 6's enumeration; the
--     pre-sitting draft of that AC said "three tables" and was one short.
--   Security-load-bearing edges: every UPDATE guarded on the value it replaces
--     (idempotent, non-clobbering, silent on a miss — see above); (6)'s user set
--     derived from posting_prototype itself (tenant binding inherited, zero-row
--     users unreachable by construction); no column, policy, grant, trigger or
--     function added or altered; no DEFAULT added or removed.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- (1) CASH-FLOW VALUE CORRECTIONS — pfin.posting_prototype_default.
-- Per-table check: natural key (cat, sub_cat), unique (084). CHECKED.
-- Each statement is guarded on the value it replaces; see the header for why.
-- ----------------------------------------------------------------------------

-- E4 D-i — Equity / Contribution is not income.
update pfin.posting_prototype_default
   set tax_relevant = false,
       notes = 'Owner capital contribution — value moved into the portfolio from the owner. Not income; retirement-contribution deductibility is per account and is not modelled in V1.'
 where cat = 'Equity'
   and sub_cat = 'Contribution'
   and tax_relevant is true
   and notes = 'potentially deductible; resolve per account type at the V1.4 tax inventory';

-- E4 D-ii — Revenue / Dividend becomes the ORDINARY (fail-closed) bucket.
update pfin.posting_prototype_default
   set tax_character = 'ordinary',
       notes = 'Dividend from a Stock or ETF — ORDINARY (non-qualified): REIT, bond-fund and money-market distributions. A dividend that meets the qualified payer and holding-period tests belongs in Dividend - Qualified.'
 where cat = 'Revenue'
   and sub_cat = 'Dividend'
   and tax_character = 'qualified_dividend';

-- E4 D-ii — Revenue / Bond Premium: value CONFIRMED ordinary; notes corrected.
-- The seeded note named mark-to-market, which is the §1256 concept the
-- asset-side Volatility-60/40 row owns, not a bond-premium concept.
update pfin.posting_prototype_default
   set notes = 'Bond premium amortization / market-discount accretion — an ordinary-interest adjustment (1099-INT / OID), never a capital item.'
 where cat = 'Revenue'
   and sub_cat = 'Bond Premium'
   and notes = 'Mark-to-Market Gain for Tax Purposes';

-- ----------------------------------------------------------------------------
-- (2) THE SAME THREE CORRECTIONS, BACKFILLED INTO pfin.posting_prototype.
-- Per-table check: natural key (users_id, cat, sub_cat), unique (084); the
-- (cat, sub_cat) half is what these predicates use, so every already-provisioned
-- user's copy of each row is reached. CHECKED — separately from (1), per 085's
-- rule and 084's Amendment 1.
--
-- Statement (1) alone reaches NOBODY who already exists: provisioning is
-- existence-guarded. See the REACH DECISION in the header.
-- ----------------------------------------------------------------------------

update pfin.posting_prototype
   set tax_relevant = false,
       notes = 'Owner capital contribution — value moved into the portfolio from the owner. Not income; retirement-contribution deductibility is per account and is not modelled in V1.'
 where cat = 'Equity'
   and sub_cat = 'Contribution'
   and tax_relevant is true
   and notes = 'potentially deductible; resolve per account type at the V1.4 tax inventory';

update pfin.posting_prototype
   set tax_character = 'ordinary',
       notes = 'Dividend from a Stock or ETF — ORDINARY (non-qualified): REIT, bond-fund and money-market distributions. A dividend that meets the qualified payer and holding-period tests belongs in Dividend - Qualified.'
 where cat = 'Revenue'
   and sub_cat = 'Dividend'
   and tax_character = 'qualified_dividend';

update pfin.posting_prototype
   set notes = 'Bond premium amortization / market-discount accretion — an ordinary-interest adjustment (1099-INT / OID), never a capital item.'
 where cat = 'Revenue'
   and sub_cat = 'Bond Premium'
   and notes = 'Mark-to-Market Gain for Tax Purposes';

-- ----------------------------------------------------------------------------
-- (3) ASSET-SIDE VALUE CORRECTIONS — pfin.taxonomy_default.
-- Per-table check: natural key (cat, sub_cat), unique — `domain` was DROPPED
-- from this table at the 084 split and must not be written. CHECKED.
--
-- E4 D-iii's marking principle, applied: 24 Sub-Cats whose disposition runs
-- through the §2.4.3 lot machinery as a taxable capital event, plus Cash /
-- T-Bill, whose discount gain is legally interest on paper that cannot be held
-- long enough to be long-term. The VALUES list is written out in full rather
-- than expressed as `cat in (...)` so that a future Sub-Cat added to one of these
-- Cats does NOT silently inherit a tax character nobody decided for it.
--
-- The guard is the baseline state (false / NULL, which is what 041 seeded and
-- what every one of these rows still held at authoring time).
-- ----------------------------------------------------------------------------

update pfin.taxonomy_default d
   set tax_relevant = true,
       tax_character = v.tax_character
  from (values
    ('Cash',                  'T-Bill',                       'short_term_only'),
    ('Bonds',                 'IGL',                          'long_term_capital_gain_eligible'),
    ('Bonds',                 'IGI',                          'long_term_capital_gain_eligible'),
    ('Bonds',                 'HYI',                          'long_term_capital_gain_eligible'),
    ('Bonds',                 'INTL',                         'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'UNKNOWN',                      'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-01-Basic_Materials',        'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-02-Telecom',                'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-03-Consumer_Discretionary', 'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-04-Consumer_Staples',       'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-05-Energy',                 'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-06-Financials',             'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-07-Health_Care',            'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-08-Industrials',            'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-09-Information_Technology', 'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-10-Utilities',              'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-Index-Non_Sector',          'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-Growth-Non_Sector',         'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'ExUS-Developed_Market',        'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'ExUS-Emerging_Market',         'long_term_capital_gain_eligible'),
    ('Alternatives',          'REIT',                         'long_term_capital_gain_eligible'),
    ('Alternatives',          'Crypto-Fx',                    'long_term_capital_gain_eligible'),
    ('Alternatives',          'Commodities-Other',            'long_term_capital_gain_eligible'),
    ('Alternatives',          'Volatility-Hedges',            'long_term_capital_gain_eligible'),
    ('Alternatives',          'Volatility-60/40',             'long_term_capital_gain_eligible')
  ) as v (cat, sub_cat, tax_character)
 where d.cat = v.cat
   and d.sub_cat = v.sub_cat
   and d.tax_relevant is false
   and d.tax_character is null;

-- ----------------------------------------------------------------------------
-- (4) THE SAME 25 CORRECTIONS, BACKFILLED INTO pfin.user_taxonomy.
-- Per-table check: natural key (users_id, cat, sub_cat), unique (009, post-084
-- with `domain` dropped); the (cat, sub_cat) half is what these predicates use.
-- CHECKED — separately from (3).
--
-- The asset-side provisioning branch is existence-guarded exactly as the
-- cash-flow one is, so (3) alone reaches nobody who already exists.
-- ----------------------------------------------------------------------------

update pfin.user_taxonomy u
   set tax_relevant = true,
       tax_character = v.tax_character
  from (values
    ('Cash',                  'T-Bill',                       'short_term_only'),
    ('Bonds',                 'IGL',                          'long_term_capital_gain_eligible'),
    ('Bonds',                 'IGI',                          'long_term_capital_gain_eligible'),
    ('Bonds',                 'HYI',                          'long_term_capital_gain_eligible'),
    ('Bonds',                 'INTL',                         'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'UNKNOWN',                      'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-01-Basic_Materials',        'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-02-Telecom',                'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-03-Consumer_Discretionary', 'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-04-Consumer_Staples',       'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-05-Energy',                 'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-06-Financials',             'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-07-Health_Care',            'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-08-Industrials',            'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-09-Information_Technology', 'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-10-Utilities',              'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-Index-Non_Sector',          'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-Growth-Non_Sector',         'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'ExUS-Developed_Market',        'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'ExUS-Emerging_Market',         'long_term_capital_gain_eligible'),
    ('Alternatives',          'REIT',                         'long_term_capital_gain_eligible'),
    ('Alternatives',          'Crypto-Fx',                    'long_term_capital_gain_eligible'),
    ('Alternatives',          'Commodities-Other',            'long_term_capital_gain_eligible'),
    ('Alternatives',          'Volatility-Hedges',            'long_term_capital_gain_eligible'),
    ('Alternatives',          'Volatility-60/40',             'long_term_capital_gain_eligible')
  ) as v (cat, sub_cat, tax_character)
 where u.cat = v.cat
   and u.sub_cat = v.sub_cat
   and u.tax_relevant is false
   and u.tax_character is null;

-- ----------------------------------------------------------------------------
-- (5) THE ROW ADD — Revenue / Dividend - Qualified on the default table.
-- E4 D-ii option C′. Every value is stated explicitly, including is_tax_payment
-- — which is 091's fail-closed shape working as intended: this INSERT would
-- ERROR if that column were omitted, rather than landing a row that silently
-- reads discretionary. `on conflict do nothing` so a re-run is a no-op and so
-- this is safe against a hand-seeded environment.
-- ----------------------------------------------------------------------------
insert into pfin.posting_prototype_default
  (cat, sub_cat, tax_relevant, tax_character, display_order, notes, is_tax_payment)
values
  ('Revenue', 'Dividend - Qualified', true, 'qualified_dividend', 65,
   'Qualified dividend from a Stock or ETF — the payer and holding-period tests are met, so it is taxed at long-term capital-gain rates Federally (California taxes it as ordinary income).',
   false)
on conflict (cat, sub_cat) do nothing;

-- ----------------------------------------------------------------------------
-- (6) BACKFILL THE NEW ROW into every ALREADY-PROVISIONED user's
-- pfin.posting_prototype row-set. 091's statement (6) shape, unchanged.
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
where d.cat = 'Revenue'
  and d.sub_cat = 'Dividend - Qualified'
on conflict (users_id, cat, sub_cat) do nothing;

-- ----------------------------------------------------------------------------
-- (7) CATALOG COMMENTS — AC 6, one per table carrying `tax_relevant`. All four:
-- pfin.user_taxonomy (009), pfin.taxonomy_default (041), pfin.posting_prototype
-- (084), pfin.posting_prototype_default (084).
--
-- These carry NO count and NO enumeration, deliberately (a copied count is a
-- maintenance obligation the copy will not honour), and no present-tense claim
-- about repo or data state that a reader at `\d+` cannot check from where they
-- are standing. What they DO carry is a dated past event (the inventory ran at
-- 100) and a standing structural fact (the DEFAULT is false, so an unstated
-- value lands unmarked).
-- ----------------------------------------------------------------------------

comment on column pfin.posting_prototype_default.tax_relevant is
  'Marks a default posting prototype as TAX-RELEVANT — the flag PRD §2.5.1 reads '
  'to decide whether a cash-flow bucket enters the tax computation at all '
  '(ADR-006 Axis 2; the V1.4 inventory applied at 100). '
  '⚠ WHAT `false` MEANS DEPENDS ON THE ROW, and the column cannot tell you which '
  'kind you are looking at. The V1.4 tax-value inventory (SELF-263) examined '
  'every row seeded up to 100 and recorded a determination for each; on those '
  'rows `false` is a decision. On any row inserted afterwards `false` may simply '
  'be the DEFAULT — see below — meaning NOT MARKED / NOT YET INVENTORIED, never '
  '"examined and found not tax-relevant". A consumer MUST NOT infer from a '
  '`false` that the question was asked. The per-row record of what was examined '
  'is the version-controlled inventory document and the V1.4 execution log, not '
  'this table. '
  'DEFAULT false, and that default is FAIL-OPEN on the axis that matters: a row '
  'inserted without stating this column enters the tax model as not-relevant, '
  'silently. The default was KEPT deliberately — it is load-bearing for the '
  'provisioning INSERT — and the fence lives at the CONSUMER instead. Contrast '
  'is_tax_payment on this same table, which is NOT NULL with NO DEFAULT and is '
  'therefore fail-closed by absence; the two columns are deliberately shaped '
  'differently and the difference is not an oversight. '
  '⚠ REACH: a value seeded here is copied to users provisioned AFTER it lands. '
  'First-access provisioning is existence-guarded, so it reaches an '
  'ALREADY-provisioned user only by an explicit backfill shipped with the change '
  '(ADR-057, generalized to this posting-side pair by ADR-062 Decision 5). Any '
  'future change to this column''s content MUST make that reach decision '
  'explicitly rather than assume provisioning delivers it. '
  'Mirrored on pfin.posting_prototype, for which this table is the provisioning '
  'source (ADR-058 Decision 3 pair discipline). '
  'Not FK-shaped — boolean, no relation reference — and this table carries no '
  'users_id at all, so no tenant anchor exists to match against; read ADR-011 '
  'Decision 3 live for the family.';

comment on column pfin.posting_prototype.tax_relevant is
  'Marks a posting prototype as TAX-RELEVANT — the per-user mirror of '
  'pfin.posting_prototype_default.tax_relevant (ADR-006 Axis 2; the V1.4 '
  'inventory applied at 100). '
  '⚠ WHAT `false` MEANS DEPENDS ON THE ROW. The V1.4 tax-value inventory '
  '(SELF-263) examined every seeded prototype and recorded a determination for '
  'each, and 100 backfilled those determinations onto every already-provisioned '
  'user. On a row inserted afterwards — including one a future taxonomy-CRUD path '
  'lets a user author — `false` may simply be the DEFAULT, meaning NOT MARKED / '
  'NOT YET INVENTORIED, never "examined and found not tax-relevant". A consumer '
  'MUST NOT infer from a `false` that the question was asked. '
  'DEFAULT false, which is FAIL-OPEN: a prototype authored without stating this '
  'column enters the tax model as not-relevant, silently. The default was KEPT '
  'deliberately (it is load-bearing for the provisioning INSERT) and the fence '
  'lives at the CONSUMER. '
  '⚠ CLASS-SCOPE THE READ. PRD §2.5.1 sources Ordinary Income from the Income '
  'side of §2.3.1. Trade-class prototypes (STC / BTC) also carry '
  'tax_relevant = true — they are disposition events whose character comes from '
  'the holding period, not from tax_character, which is NULL on them by design. '
  'A reader that filters on this flag ALONE, without also scoping to '
  'cat = ''Revenue'', will sum sale proceeds into Ordinary Income. '
  'Not FK-shaped — boolean, no relation reference — so no matched-tenant '
  'validation is owed; read ADR-011 Decision 3 live for the family.';

comment on column pfin.taxonomy_default.tax_relevant is
  'Marks a default STORAGE-taxonomy Sub-Cat as TAX-RELEVANT — true iff a holding '
  'classified under it is disposed of through the §2.4.3 lot machinery AND that '
  'disposition is a taxable event PRD §2.5.1 must place in the short-term / '
  'long-term capital-gain columns (the marking principle ruled at the V1.4 '
  'inventory, applied at 100). '
  '⚠ WHAT `false` MEANS DEPENDS ON THE ROW. The inventory examined every row '
  'seeded up to 100 and recorded a determination for each; on those rows `false` '
  'is a decision, and it is NOT a claim that the disposition is tax-free. Real '
  'Estate is the case that makes the difference concrete: those rows are `false` '
  'because a property sale is a taxable event the lot machinery does not model, '
  'not because it is untaxed. On any row inserted after 100, `false` may simply '
  'be the DEFAULT — NOT MARKED / NOT YET INVENTORIED. A consumer MUST NOT infer '
  'from a `false` that the question was asked. '
  'DEFAULT false, deliberately KEPT (load-bearing for the provisioning INSERT); '
  'the fence lives at the CONSUMER. '
  '⚠ NOT SUFFICIENT ALONE, and dormant besides: the capital-gains surface these '
  'values feed renders UNAVAILABLE while no sale writer exists, so a true here '
  'reaches no V1 consumer. Do not read a populated tax_character on this table as '
  'evidence that a capital-gains path is live. '
  '⚠ REACH: a value seeded here is copied to users provisioned AFTER it lands; '
  'first-access provisioning is existence-guarded, so an ALREADY-provisioned user '
  'is reached only by an explicit backfill shipped with the change (ADR-057). '
  'Mirrored on pfin.user_taxonomy, for which this table is the provisioning '
  'source (ADR-058 Decision 3 pair discipline). '
  'Not FK-shaped — boolean, no relation reference — and this table carries no '
  'users_id at all; read ADR-011 Decision 3 live for the family.';

comment on column pfin.user_taxonomy.tax_relevant is
  'Marks a user''s STORAGE-taxonomy Sub-Cat as TAX-RELEVANT — the per-user mirror '
  'of pfin.taxonomy_default.tax_relevant (ADR-006 Axis 2; the V1.4 inventory '
  'applied and backfilled at 100). '
  '⚠ WHAT `false` MEANS DEPENDS ON THE ROW. The inventory examined every seeded '
  'Sub-Cat and recorded a determination for each, and 100 backfilled those onto '
  'every already-provisioned user. `false` on such a row is a decision and NOT a '
  'claim that the disposition is tax-free (Real Estate: a property sale is a '
  'taxable event the §2.4.3 lot machinery does not model). On a row inserted '
  'afterwards — including one a future taxonomy-CRUD path lets a user author — '
  '`false` may simply be the DEFAULT, meaning NOT MARKED / NOT YET INVENTORIED. '
  'A consumer MUST NOT infer from a `false` that the question was asked. '
  'DEFAULT false, deliberately KEPT (load-bearing for the provisioning INSERT); '
  'the fence lives at the CONSUMER. '
  '⚠ THIS TABLE HOLDS NO CASH-FLOW ROWS. ADR-058''s split moved the posting '
  'vocabulary to pfin.posting_prototype at 084 and dropped `domain`; this column '
  'therefore answers the ASSET-side question only, and its answers are dormant '
  'while no sale writer exists. '
  'Not FK-shaped — boolean, no relation reference — so no matched-tenant '
  'validation is owed; read ADR-011 Decision 3 live for the family.';

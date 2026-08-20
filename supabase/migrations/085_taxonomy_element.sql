-- ============================================================================
-- Migration: pfin.user_taxonomy + pfin.taxonomy_default — add `element`
-- Phase 6 Build Loop. The THIRD and last migration of ADR-058's ratified build
-- order (rename `082` → split `084` → element, here). Closes ADR-058 Decision 3
-- and Sec finding F4. Extends no RLS policy and adds no function.
--
-- Numbering: next free number at authoring time. Depends on `084` (the GL split)
-- for the shape it lands on: after `084` both tables are the STORAGE-
-- classification half only, `domain` is dropped, and the posting vocabulary
-- lives in pfin.posting_prototype / pfin.posting_prototype_default — which is
-- why `element` can be a plain two-valued column here instead of a conditional
-- one. ADR-058 Decision 6 ratifies the order and forbids bundling: three
-- migrations, three PRs.
--
-- POSTURE RATIONALE — no function is created, replaced or dropped by this
--   migration, so it establishes no SECURITY posture and changes none. The
--   SECURITY DEFINER allowlist is untouched (read ADR-011 Decision 9 live).
--   ⚠ The three `comment on function` / `comment on table` re-emissions in
--   STEP 5 are COMMENT statements only: they do not `create or replace` a body,
--   so no volatility marking is reset and `079`'s per-signature STABLE pin on
--   pfin.fn_subcat_market_value(date, boolean) stands untouched. A comment
--   re-emission and a body re-issue look similar in a diff and are not the same
--   act; this file performs only the first.
--
-- CONTRACT
--   pfin.user_taxonomy.element   text NOT NULL, no DEFAULT,
--   pfin.taxonomy_default.element text NOT NULL, no DEFAULT,
--     both constrained by a named CHECK `element in ('asset','liability')`.
--   `element` classifies a MANAGEMENT-REPORTING bucket — the storage class a
--   thing holds book value in. It is NOT the GL's element and must not be read
--   as one (ADR-058 Decision 3: the storage taxonomy and the GL's ledger-account
--   dimension are orthogonal, neither derives from the other, and the binding
--   contract at their seam is TOTALS, never row-by-row slices).
--   Security-load-bearing edges:
--     · NULL — a CHECK is fail-OPEN on NULL (a NULL `in (...)` evaluates NULL
--       and is therefore not a violation). The CHECK does NOT make the column
--       total; `set not null` does. Both ship here, in this migration, and
--       neither substitutes for the other. This is Sec F4 condition (2).
--     · The column carries no FK and references no relation — see the
--       Decision-3 per-column check below.
--     · Tenant isolation is unchanged: `element` is a value column on tables
--       whose RLS, grants and aal2 posture this migration does not touch.
--
-- ---------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK — PERFORMED BEFORE DRAFTING, against ADR-011
-- Decision 4 read verbatim and live (never from recall).
--   · instance-numbering — no catalogued instance is added, reordered or
--     renumbered by this migration.
--   · layer-attribution — no catalogued instance changes the layer it operates
--     at; no surface gains or loses a layer.
--   · verbatim-vs-paraphrase — the catalogued list is NOT restated here. This
--     file is not the canonical anchor and never is; the link carries it
--     (Path B). No count appears anywhere in this file.
-- Result: NO §10 ledger change. This migration is therefore not a §10 Sec
-- trigger — it routes to Sec joint-review on other grounds (below).
--
-- ---------------------------------------------------------------------------
-- ADR-011 DECISION 3 — PER-COLUMN CHECK, RUN ON EACH NEW COLUMN SEPARATELY.
-- Read Decision 3's body live: the family GROWS, its labels are NON-CONTIGUOUS,
-- one has been DROPPED, and *labeled* versus *DDL-realized* are two counts that
-- diverge. This file states no tally and adds no label.
--   · pfin.user_taxonomy.element — `text`, no FK, no reference to any relation,
--     no array of ids. It is a two-valued vocabulary constrained by a CHECK.
--     There is no referenced row, therefore no tenant to match. NOT a family
--     member; no matched-tenant validation is owed and none is authored.
--   · pfin.taxonomy_default.element — same shape, on a table that carries no
--     `users_id` at all (global shared-read reference data). Same disposition.
-- ⚠ Stated per column rather than once for the migration, because `084`'s own
-- header adopted the per-column form specifically so a reviewer could check
-- each claim against the DDL — and then Amendment 1 item 3 records that the
-- check was not actually run on the second table in that same file. Adopting a
-- checkable form is not the same as running the check. It was run on both here.
-- The next genuine FK-bypass instance still takes the next unallocated label;
-- read Decision 3 live for which one that is.
--
-- ---------------------------------------------------------------------------
-- PROVENANCE OF EVERY FIGURE AND SHAPE BELOW — stated once, so no reader has
-- to wonder which of them were inherited. Each was measured at authoring time
-- against the TREE (`origin/main` at the base of this migration's branch) or
-- against the LIVE CATALOG on a clean `001..084` scratch database. None was
-- carried from a working note, a prior summary, or a design document — ADR-058
-- included. That is a method rule and not a courtesy: a design document
-- describes the world at the moment it was written, and this migration is the
-- third of three, so the two before it moved the world the ADR describes. The
-- consequence-list measurement below is the demonstration — the catalog and the
-- ADR return different sets, and the catalog is right.
--
-- ---------------------------------------------------------------------------
-- THE BACKFILL MAP, AND WHY IT IS TOTAL.
-- Derived from the live seed on a clean `001..084` scratch database, not from
-- any prose description of it.
--   Command:  select cat, count(*) from pfin.taxonomy_default group by cat;
--   Predicate: which Cats exist on the storage side after `041` + `077` + `080`
--              + the `082` rename + the `084` split, and which of them are
--              places a thing holds NEGATIVE book value?
--   Result:   Alternatives 5 · Bonds 4 · Cash 5 · Liabilities 4 ·
--             Marketable Securities 15 · Real Estate 5  (38 rows, six Cats).
--   The four Liabilities rows are Credit-Balance / EstTax-Pending /
--   Loan-Balance (`041`) + Liability Balances (`080`) — every one a liability,
--   and no liability-shaped Sub-Cat hides under any of the other five Cats.
-- So the map is at CAT grain and it is:
--     cat = 'Liabilities'  ->  'liability'
--     everything else      ->  'asset'
-- ⚠ The `else` branch is a JUDGEMENT on pfin.user_taxonomy, not a tautology.
-- That table is per-user and `084` records that it constrains no `cat` at all
-- while `authenticated` holds INSERT, so a user-authored Cat outside the six is
-- expressible. V1 is SEED-ONLY (no taxonomy-CRUD UI) and the only writer is the
-- ADR-036 B1 provisioning path copying from pfin.taxonomy_default, so today the
-- else-branch can only ever see seeded Cats. Recorded as a judgement because
-- the V2 taxonomy-CRUD PR inherits it: whoever opens Cat authorship to users
-- must decide how a user-authored Cat acquires its element, and must not
-- discover this `case` by reading it.
-- ⚠ Totality is what makes `set not null` in the same migration safe rather
-- than hopeful: a `case` with an unconditional `else` cannot produce NULL. No
-- separate NULL-guard block is authored — `set not null` IS that assertion, and
-- a guard over a by-construction property is a control that cannot fire.
--
-- ---------------------------------------------------------------------------
-- WHY `not null` WITH NO DEFAULT — F/CTO-CONFIRMED, and stated at length here
-- specifically so a later simplification pass does not helpfully add the
-- default back.
-- A `default 'asset'` would leave every existing writer compiling untouched.
-- That convenience IS the defect: a row written without an element would be
-- silently classified as an asset — the fail-OPEN direction for the §2.2.2
-- assets-only row set, and the exact failure this column exists to remove. A
-- default would restore, in one word, the property that a bucket's class is
-- REMEMBERED rather than DECLARED.
-- No default is the fail-CLOSED direction, and the cost lands where it should:
-- every INSERT into either table must now say what it means. That cost is real
-- and is paid in this PR — the paired battery's fixtures are that population
-- and are updated alongside this migration.
-- ⚠ REVERSIBLE, AND THAT IS NOT AN INVITATION. Adding a default later is
-- mechanically one ALTER against rows that cannot violate it, so this is not a
-- one-way door and is not presented as one. But it is a DECISION on the same
-- footing as widening the CHECK below: whoever adds a default is choosing that
-- an unstated element should be filled in silently, on a financial
-- classification surface, in the fail-OPEN direction — and should say so, here,
-- in the header of the migration that does it. **A reviewer meeting a `default`
-- on this column with no such statement should treat it as a defect, not as
-- tidying.**
--
-- ---------------------------------------------------------------------------
-- THE VALUE SET, AND THE WIDENING PATH — recorded as a DECISION a future
-- author must make and state, never as a repair.
-- `check (element in ('asset','liability'))` is F/CTO-RATIFIED for V1
-- (2026-08-18; ADR-058 Decision 3). Standard accounting recognises five
-- elements — Asset / Liability / Equity / Revenue / Expense — and that is the
-- frame these decisions are written in; which of them THIS column may hold is a
-- separate question and was answered narrowly, on the evidence that no V1
-- storage class holds owner capital (owner capital appears in this system only
-- as derived contras — Opening-Balance-Equity, retained earnings, the
-- unrealized-gains overlay — which are not rows in this table).
-- ⚠ ADDING 'equity' LATER IS A DECISION, NOT AN OVERSIGHT BEING CORRECTED.
-- Mechanically it is one `alter table ... drop constraint / add constraint`
-- against rows that cannot violate it — a CHECK is cheap to widen and
-- expensive to narrow, which is why narrow was the safer proposal. But whoever
-- widens it is asserting that a storage class can represent owner capital, and
-- SHOULD SAY SO — in their migration header, in the same place this paragraph
-- sits. The trigger to look for is evidence that a user models owner capital as
-- a HOLDING PLACE rather than as a derived contra. Nothing in the current seed
-- does. Treating this CHECK as a bug to be fixed is the failure mode this
-- paragraph exists to prevent.
-- ⚠ `Transfer` and `Trade` are NOT elements and never acquire one. They are the
-- balance-sheet-internal members of `028`'s cashflow class enum, they live in
-- pfin.posting_prototype since `084`, and any design requiring all five class
-- values to carry an element is wrong at the vocabulary level, not here.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS MIGRATION DOES NOT DO — stated where a reader would otherwise
-- wonder, because the capability lands here and the consumption does not.
--   · pfin.fn_subcat_market_value(date, boolean) is UNCHANGED. It CAN now
--     express a row set as `element = 'asset'`; it DOES NOT, and a naive future
--     edit that adds that predicate INSIDE the function would BREAK the seam
--     invariant `Σ fn_subcat_market_value(as_of, include_real_estate := true)
--     = fn_compute_nav(as_of)` (`076` header; SELF-238 AC4), because the
--     liability cash route added at `081` contributes rows the invariant
--     counts. The assets-only row set belongs to the §2.2.2 CONSUMER, not to
--     this producer. SELF-239's rework owns that change. The function's catalog
--     comment is re-emitted below to say exactly this, and nothing else.
--   · No fence acquires an `element` predicate. In particular the Decision-3
--     #17 fence on pfin.planning_target.sub_cat_id is NOT re-armed. Measured
--     rather than assumed: the second predicate `084` retired from it was
--     `domain = 'asset'`, and every Liabilities row in the seed carried
--     `domain = 'asset'` — so `element = 'liability'` names a set that the
--     retired predicate NEVER excluded. Nothing was lost at `084` that an
--     element predicate would restore. Whether a %Target should be expressible
--     against a liability bucket at all is a product question and is not
--     answered by a migration.
--   · No RLS policy, no GRANT and no aal2 clause changes. The grants on both
--     tables are TABLE-level with no column list (`009`, `041`), so the new
--     column is covered by the existing ACL by construction; a column-list
--     grant would not have been, which is why this was checked rather than
--     assumed. Neither table's `025` posture moves: pfin.user_taxonomy keeps
--     its clause, pfin.taxonomy_default keeps its exclusion (i) as global
--     shared-read non-tenant reference data.
--   · No consumer is re-pointed. `element` has no reader in this PR other than
--     the provisioning column list, which must carry it or new signups are
--     provisioned with nothing (Sec F3's fail-INVISIBLY class).
--
-- ROUTING: Sec joint-review is a MERGE GATE for this migration — tenant-owned
-- financial-classification tables, a data migration over an already-fenced
-- surface, and a re-emitted catalog comment on a function Sec has reviewed.
-- QA pairing ships in the same PR (Sec F4 condition (2)).
-- ============================================================================


-- ---------------------------------------------------------------------------
-- STEP 1 — add the column, nullable, on BOTH tables.
--
-- ⚠ BOTH TABLES, IN THE SAME MIGRATION, IS SEC CONDITION F4 AND OMITTING THE
-- DEFAULT TABLE FAILS IN THE DIRECTION THAT LOOKS CORRECT. Provisioning is a
-- COLUMN-LISTED copy from pfin.taxonomy_default; without `element` on the
-- source, provisioned rows cannot carry one, and then either `not null` blocks
-- provisioning — silently, because that path is fail-soft by contract — or the
-- column is nullable and a later `element = 'asset'` filter silently drops
-- those rows. The second branch is a row set and a denominator derived from
-- different predicates on a financial surface: it fails OPEN.
-- ---------------------------------------------------------------------------

alter table pfin.user_taxonomy
  add column if not exists element text;

alter table pfin.taxonomy_default
  add column if not exists element text;


-- ---------------------------------------------------------------------------
-- STEP 2 — backfill both, at Cat grain, per the derived map in the header.
-- Unconditional `else`, therefore total, therefore STEP 3 cannot fail for a
-- row this statement touched.
-- ---------------------------------------------------------------------------

update pfin.user_taxonomy
   set element = case when cat = 'Liabilities' then 'liability' else 'asset' end
 where element is null;

update pfin.taxonomy_default
   set element = case when cat = 'Liabilities' then 'liability' else 'asset' end
 where element is null;


-- ---------------------------------------------------------------------------
-- STEP 3 — make the column total. This IS the zero-NULL assertion: `set not
-- null` scans the table and aborts the migration if STEP 2 left anything
-- behind. No redundant guard block is authored above it.
-- ---------------------------------------------------------------------------

alter table pfin.user_taxonomy
  alter column element set not null;

alter table pfin.taxonomy_default
  alter column element set not null;


-- ---------------------------------------------------------------------------
-- STEP 4 — the named CHECK, drop-if-exists-then-add (the `011` / `028`
-- pattern), so a re-apply onto a database that already carries it is a no-op
-- rather than a duplicate-object error.
-- ⚠ This constraint does NOT make the column total — see the CONTRACT block: a
-- CHECK is fail-OPEN on NULL. STEP 3 is the other half.
-- ---------------------------------------------------------------------------

alter table pfin.user_taxonomy
  drop constraint if exists user_taxonomy_element_chk;

alter table pfin.user_taxonomy
  add constraint user_taxonomy_element_chk
    check (element in ('asset', 'liability'));

alter table pfin.taxonomy_default
  drop constraint if exists taxonomy_default_element_chk;

alter table pfin.taxonomy_default
  add constraint taxonomy_default_element_chk
    check (element in ('asset', 'liability'));

comment on constraint user_taxonomy_element_chk on pfin.user_taxonomy is
  'The V1 storage-class element vocabulary, F/CTO-ratified 2026-08-18 '
  '(ADR-058 Decision 3): asset or liability, and nothing else. Widening this '
  'set — the named candidate is ''equity'' — is a DECISION whoever makes it '
  'must state, not a repair of an oversight: it asserts that a storage class '
  'can represent owner capital, which nothing in the V1 seed does (owner '
  'capital appears only as derived contras, which are not rows in this table). '
  'A CHECK is cheap to widen and expensive to narrow, which is why the set was '
  'ratified narrow. This constraint is fail-OPEN on NULL by SQL semantics; the '
  'column''s NOT NULL, added in the same migration, is what makes it total.';

comment on constraint taxonomy_default_element_chk on pfin.taxonomy_default is
  'Mirror of user_taxonomy_element_chk on the global default set. It exists '
  'because provisioning is a COLUMN-LISTED copy from this table into '
  'pfin.user_taxonomy (ADR-036 B1): a default set that cannot carry an element '
  'provisions rows that cannot carry one either, and that failure is silent '
  'because the provisioning path is fail-soft by contract (Sec F4). Same value '
  'set, same widening discipline, same NULL semantics — read '
  'user_taxonomy_element_chk''s comment for all three.';


-- ---------------------------------------------------------------------------
-- STEP 5 — catalog comments: the new columns, plus every existing comment this
-- column falsifies or extends.
--
-- Scope rule, and it is the instrument that set this list rather than the ADR's
-- own consequence list: the live catalog was queried on a clean `001..084`
-- scratch database for every pfin function whose `prosrc` references
-- pfin.user_taxonomy or pfin.taxonomy_default. Result: exactly three functions,
-- all SECURITY INVOKER — fn_subcat_market_value(date, boolean),
-- fn_planning_target_matched_sub_cat(), fn_user_asset_category_matched_sub_cat().
-- ⚠ pfin.fn_gl_entries is NOT among them: `084` re-pointed it at
-- pfin.posting_prototype and it no longer reads either of these tables. A
-- consequence list inherited from the ADR would have carried it, because the
-- ADR was written before the split existed. Re-measuring over the catalog
-- rather than over the design document is what removed it.
-- Of the three, ONE is re-emitted below. The two matched-tenant fences are
-- left exactly as `084` authored them: their comments describe the retirement
-- of a `domain = 'asset'` predicate, and `element` neither restores nor
-- contradicts that — see the header's measured note on why `element` does not
-- re-arm #17.
-- ---------------------------------------------------------------------------

comment on column pfin.user_taxonomy.element is
  'The storage class this Cat x Sub-Cat bucket is: asset or liability '
  '(ADR-058 Decision 3, F/CTO-ratified 2026-08-18; CHECK-constrained by '
  'user_taxonomy_element_chk, NOT NULL with no DEFAULT). It classifies a '
  'MANAGEMENT-REPORTING bucket — the place a thing holds book value. ⚠ It is '
  'NOT the GL''s element and must not be read as one. The storage taxonomy and '
  'the GL''s ledger-account dimension are ORTHOGONAL: neither derives from the '
  'other, they are two partitions of one total, and the binding contract at '
  'their seam is TOTALS, never row-by-row slices. A future ledger-account '
  'element will carry the same NAME on a different object type; that is one '
  'concept applied to two object types, which is normal — what must never '
  'happen is a later change "reconciling" them by joining. The worked example '
  'is a short position: a bucket whose element is asset AND a ledger account '
  'whose element is liability, the same position, two correct answers. NO '
  'DEFAULT is deliberate — a defaulted element would classify silently, and '
  '''asset'' is the fail-OPEN direction for an assets-only row set. This column '
  'makes the constraint that Liabilities do not belong in the asset domain '
  'ENFORCEABLE rather than remembered: an assets-only row set is expressible '
  'as element = ''asset'' instead of as "exclude the Cat named Liabilities", '
  'which makes a negative-denominator hazard unreachable by definition rather '
  'than by list. ⚠ It constrains the ELEMENT only. It does NOT constrain `cat`, '
  'which remains unconstrained free text on this table since 028''s class '
  'CHECK left with the posting rows at 084.';

comment on column pfin.taxonomy_default.element is
  'The storage class of a default Cat x Sub-Cat bucket: asset or liability '
  '(ADR-058 Decision 3; CHECK-constrained by taxonomy_default_element_chk, NOT '
  'NULL with no DEFAULT). Read pfin.user_taxonomy.element''s comment for what '
  'the value MEANS and for the GL-orthogonality warning — this column is the '
  'provisioning SOURCE of that one and carries identical semantics. It exists '
  'on this table for a structural reason, not for symmetry: provisioning is a '
  'column-listed copy, so an element the default set cannot hold is an element '
  'a provisioned user never receives (Sec F4).';

-- The spine's own comment. `084` named the element CHECK as one of the two
-- instruments for closing the cat asymmetry it records — that instrument now
-- exists, and a reader meeting the old text would reasonably ask whether it
-- closed the asymmetry. It did not, and this re-emission says which half it
-- closed. Base text is `084`'s; the change is additive and is named as such.
comment on table pfin.user_taxonomy is
  'Per-user two-level Cat × Sub-Cat STORAGE-CLASSIFICATION spine (ADR-011 '
  'Decision 11 / Lock 7, Option A single-table; SELF-231, narrowed by ADR-058 '
  'Decision 1 at 084). It covers the §2.2.1 asset domain ONLY. 084 moved the '
  '§2.3.1 posting vocabulary out to pfin.posting_prototype and DROPPED the '
  'domain column, so the table now expresses what the column used to: an '
  'element is intrinsic to a storage class, whereas a posting prototype has no '
  'intrinsic element and its legs touch element-bearing accounts. Rows that '
  'moved kept their original ids, and this table''s identity is capped below '
  'the reserved range pfin.posting_prototype mints from, so no id resolves in '
  'more than one table. 085 made that intrinsic element EXPLICIT: the element '
  'column, NOT NULL and CHECK-constrained to asset or liability. ⚠ THAT CLOSES '
  'ONE HALF OF THE ASYMMETRY THIS COMMENT HAS RECORDED SINCE 084 AND NOT THE '
  'OTHER. 028''s accounting-class CHECK LEFT WITH THE POSTING ROWS: this table '
  'still constrains no cat at all, while authenticated holds INSERT — a user '
  'can still create a storage class named like an accounting class. What 085 '
  'added is that every such row must now DECLARE which element it is, which '
  'means an assets-only row set is expressible as a predicate instead of as an '
  'exclusion list. The remaining instrument for the cat half is a cat-set '
  'assertion, never an appeal to table identity. Carries the ADR-006 Axis 2 '
  'tax_relevant boolean + tax_character enum (5 V1 values). V1 is SEED-ONLY (no '
  'taxonomy-CRUD UI; V2+ expansion) and V1-MUTATE-DORMANT: authenticated holds '
  'SELECT + INSERT. 041 added the INSERT grant and the user_taxonomy_insert '
  'policy (with check users_id = auth.uid(), carrying the 025 aal2 backstop '
  'clause) so a user can provision their own default taxonomy on first access; '
  '085 changed no grant and no policy — its grants are table-level with no '
  'column list, so the new column is covered by the existing ACL. UPDATE and '
  'DELETE carry no grant and no policy, so they are default-denied at BOTH the '
  'ACL layer and the RLS layer; un-deferring them is the V2 taxonomy-CRUD-UI PR '
  'decision and needs its own review — and that PR inherits an open question '
  '085 names rather than answers: how a USER-authored Cat acquires its element, '
  'since 085''s backfill could only ever see seeded Cats. SUPERSESSION: this '
  'comment previously read "V1-WRITE-DORMANT ... authenticated holds SELECT '
  'ONLY ... Write policies + write grants are DEFERRED to the V2 '
  'taxonomy-CRUD-UI PR" -- true when 009 shipped, falsified by 041 on the '
  'INSERT half, corrected at 083. ⚠ That last word read "corrected here" through '
  '083 and 084: true of 083, which made the correction, and re-pointed by 084''s '
  're-emission without an edit — an indexical carried verbatim changes referent '
  'silently, which is why it is named at 085 rather than fixed quietly. anon '
  'zero-grant; service_role ungranted (the '
  'default set is seeded by the migration chain under the schema-owning role, '
  'not by service_role; the CLI reset subcommand named by the original wording '
  'is BANNED for all agents -- see docs/records/2026-08-14-db-reset-incident.md). '
  'This is the sub_cat_id FK target that 004 deferred — that future FK is a '
  'separate Decision-3 evaluation (referencing row users_id must match '
  'user_taxonomy.users_id), added with the FK, not here. Since 084 the '
  'referents that remain pointed here are the STORAGE-side ones: '
  'pfin.user_asset_category.sub_cat_id (canonical #8) and '
  'pfin.planning_target.sub_cat_id (canonical #17). The two posting-side '
  'referents (#10 at 023, #13 at 029) re-targeted to pfin.posting_prototype, '
  'keeping their labels, their DDL-realized status and their fence pattern. '
  '085 added no FK-shaped column and no Decision-3 instance. AC-vs-convention '
  'corrections: AC SERIAL→identity, AC INTEGER users_id→uuid (auth.users.id is '
  'uuid) — see 009 header.';

-- The default set. Its "columns mirror user_taxonomy MINUS users_id" clause
-- stays TRUE only because element landed on both tables in one migration —
-- which is the whole of Sec F4's argument, so the comment now says why.
comment on table pfin.taxonomy_default is
  'Global canonical default two-level Cat x Sub-Cat taxonomy (ADR-036 / '
  'SELF-311, B1+A1). The single committed source for default '
  'STORAGE-CLASSIFICATION provisioning — the §2.2.1 asset default set, ported '
  'verbatim at 041 from the pre-041 gitignored seed.sql (which now seeds the '
  'dev user FROM this table). 084 moved the §2.3.1 cashflow half to '
  'pfin.posting_prototype_default and dropped the domain column, so '
  'provisioning now copies from TWO default tables into two per-user tables; an '
  'existence guard that checks only one of them marks a half-provisioned user '
  'as done. Columns mirror pfin.user_taxonomy MINUS users_id, as they did '
  'before the split — and 085 kept that true ON PURPOSE by adding element to '
  'BOTH tables in one migration. ⚠ THE MIRROR IS A LOAD-BEARING PROPERTY OF '
  'THIS TABLE, NOT A TIDINESS: provisioning is a COLUMN-LISTED copy, so any '
  'column the per-user table requires and this one lacks is a column '
  'provisioned rows cannot carry, and the provisioning path is fail-soft by '
  'contract — it logs and returns. A future column added to pfin.user_taxonomy '
  'alone would therefore break new-user provisioning SILENTLY. GLOBAL '
  'SHARED-READ (RLS using(true), authenticated SELECT; anon zero; service_role '
  'none) — non-tenant reference data (category names + notes; no $-figures), so '
  'EXCLUDED from the 025 aal2 backstop per exclusion (i); 085 changed no policy '
  'and no grant. NO users_id / NO FK — Decision 3 family UNCHANGED, and '
  'element is a value column that adds none. Content is migration-authored; '
  'changing the default set later is a data migration, and such a change MUST '
  'decide separately whether it reaches already-provisioned users — never '
  'assume first-access provisioning delivers it. SUPERSEDES the row-count '
  'clause this comment carried at 041: the set grew at 077 and a catalog '
  'comment cannot carry a figure that a later migration invalidates — count the '
  'table.';

-- The one function comment `element` extends. The function BODY is untouched;
-- this is a comment statement only, so its STABLE marking (079, pinned per
-- signature) is not reset.
comment on function pfin.fn_subcat_market_value(date, boolean) is
  'Per-Sub-Cat market-value rollup (PRD §2.2.2.a; SELF-237). Shared primitive '
  'for the §2.2.2 Non-RE allocation table and the §2.2.3 US Equity drill-down. '
  'SECURITY INVOKER + STABLE + set search_path = ''''; NO tenant or scope '
  'parameter — isolation is INHERITED from the RLS on every relation read, via '
  'auth.uid() under the caller''s own session (the 049/051 convention; a '
  'p_users_id would be a confused-deputy foot-gun, and scope is an attribute, '
  'not a partition, per ADR-004 Decision B full-household default). Returns one '
  'row per user_taxonomy Sub-Cat the caller HOLDS VALUE IN — Sub-Cats with no '
  'holdings are absent, and an empty portfolio returns the EMPTY SET, not a '
  'zero row. ⚠ 085 ADDED pfin.user_taxonomy.element AND THIS FUNCTION DOES NOT '
  'READ IT. That is deliberate and it is not an omission to be tidied: this '
  'producer returns BOTH elements, because the liability cash route added at '
  '081 contributes rows that the seam invariant counts — Σ '
  'fn_subcat_market_value(as_of, include_real_estate := true) = '
  'fn_compute_nav(as_of) (076 header; SELF-238 AC4). Adding an element = '
  '''asset'' predicate INSIDE this function would therefore BREAK that '
  'invariant. The assets-only row set is a CONSUMER-side predicate belonging to '
  '§2.2.2, and when it moves to element = ''asset'' the row set and the '
  'denominator must derive from the SAME predicate in the SAME query, or a '
  'paired assertion must prove the rendered rows sum to the denominator — the '
  'named failure class is COVERAGE DIVERGENCE, and it fails OPEN. ⚠ PLUS AT '
  'MOST ONE UNCLASSIFIED ROW (sub_cat_id / cat / sub_cat all NULL): in V1 an '
  'unclassified holding is the ABSENCE of a user_asset_category row, so an '
  'inner join would DROP that value silently and the table would foot below NAV '
  'while looking well-formed. The consumer (SELF-238) renders it as the derived '
  'Unsorted row; a consumer cannot derive what the producer discarded. ⚠ That '
  'row carries NO element either, for the same reason it carries no cat — there '
  'is no taxonomy row to read one from. ⚠ Its population is LIVE NON-ZERO '
  'POSITIONS (fn_holdings_as_of filters quantity <> 0) and is therefore NOT the '
  'same set as the app-layer pendingSymbols query, which is '
  'ever-transacted-minus-classified — do not reconcile them. ⚠ CASH resolves to '
  'ONE Sub-Cat per user per currency, via the global currency-asset''s single '
  'junction row (022 cash-via-currency-asset): the seeded CD / FDIC / SPIC / '
  'T-Bill Sub-Cats CANNOT be distinguished per account, because the cash leg '
  'carries no asset_id. market_value COALESCES TO 0 for footing consistency '
  'with fn_compute_nav, which means an all-unpriced Sub-Cat renders 0.00 '
  'indistinguishably from holding nothing — that distinction belongs to the '
  'existing non-silent-staleness framework (ADR-049 Decision 5), not to a '
  'second mechanism here. p_include_real_estate = FALSE excludes cat = ''Real '
  'Estate'' ENTIRELY (no row); the match is exact on the ASSET-CLASS '
  'taxonomy, so Alternatives/REIT is not swept in and account_type = '
  '''real_estate'' is a different taxonomy; the unclassified row is never '
  'excluded by the flag. Closed accounts excluded on the 059 dated predicate, '
  'three-conjunct on the LEFT-JOINed securities leg (a bare closed_at-is-null '
  'fails OPEN). The price and FX kernel is copied VERBATIM from 059''s '
  'fn_compute_nav so the two cannot drift; latest-on-or-before, date dominating '
  'source. Reads only: no write path, no new FK-shaped column, no DEFINER '
  'entry, no service_role grant. SUPERSESSION: this comment previously opened '
  'its return description with "one row per asset-domain user_taxonomy Sub-Cat" '
  '— accurate when the domain column existed, and after 085 that phrase would '
  'read as a claim that this function filters on element. It does not.';

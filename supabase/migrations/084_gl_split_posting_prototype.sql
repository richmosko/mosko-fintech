-- ============================================================================
-- Migration: the GL split — pfin.user_taxonomy sheds its posting vocabulary to a
--   new pfin.posting_prototype, keeps its name / its ids / its asset rows, and
--   drops `domain`. Phase 6 Build Loop.
--
-- Lands ADR-058 Decisions 1 (the asymmetric split), 2 (id preservation), 4 (028's
-- CHECK moves and loses its domain disjunct) and 5 (the Decision-3 referents
-- re-target). Second of the three ratified migrations — the order is
-- rename (082/083) -> SPLIT (here) -> `element` — and they are three separate PRs
-- by ADR-058 Decision 6's no-bundling line.
--
-- Numbering: 084 follows 083 (the user_taxonomy comment supersession that closed
-- this work's first migration obligation). Depends on 009 (user_taxonomy), 010
-- (notes), 022/023/029/074 (the four FK-shaped referents), 028 (the CHECK that
-- moves), 030 (the Trade-constraints fence), 031 (the FK-less audit snapshot whose
-- ids this migration protects), 035/037 (fn_gl_entries), 041 (taxonomy_default +
-- the INSERT policy whose aal2 clause is copied verbatim), 076/081
-- (fn_subcat_market_value).
--
-- ----------------------------------------------------------------------------
-- WHAT THIS DOES
--
--   pfin.user_taxonomy      keeps its name, its ids and its asset rows; drops
--                           `domain`; unique becomes (users_id, cat, sub_cat).
--                           It is now, unambiguously, the storage-classification
--                           spine.
--   pfin.posting_prototype  NEW. Receives the cashflow rows WITH THEIR ORIGINAL
--                           ID VALUES. Per-user, tenant-owned, RLS + WITH CHECK +
--                           the 025 aal2 backstop clause; select + insert to
--                           authenticated only.
--   pfin.taxonomy_default   splits symmetrically: its cashflow rows move to a new
--                           pfin.posting_prototype_default; drops `domain`;
--                           unique becomes (cat, sub_cat).
--
--   Every FK-shaped referent of the cashflow half re-targets; every reader of the
--   cashflow half re-targets; every catalog comment falsified by either is
--   re-emitted. NOTHING on the asset side moves — that is the whole point of the
--   asymmetric shape (ADR-058 Decision 1).
--
-- ----------------------------------------------------------------------------
-- SEC F2 — THE FOUR ROW COUNTS, RUN BEFORE THIS FILE EXISTED
--
-- Sec's touchpoint made four counts a PRECONDITION ON AUTHORING (not on landing),
-- because ADR-058 Decision 5's referent partition was measured over migration TEXT
-- — what the authors intended — and three of the four domain rules are recorded in
-- that same table as APP-LAYER ONLY, not enforced. An unenforced rule is exactly
-- the rule the data can violate.
--
--   Venue: the local dev stack, container supabase_db_mosko-fintech, database
--   `postgres`, read-only SELECT as `postgres`. Run 2026-08-19, before this file
--   was created.
--
--   1. account_trans_annotation rows whose sub_cat_id resolves to an asset-domain
--      row .................................................................. 0
--        select count(*) from pfin.account_trans_annotation a
--          join pfin.user_taxonomy ut on ut.id = a.sub_cat_id
--         where ut.domain = 'asset';
--   2. account_trans_split rows, same predicate ............................. 0
--   3. user_asset_category rows whose sub_cat_id resolves to a cashflow-domain
--      row .................................................................. 0
--   4. account_trans_annotation_history snapshot ids resolving to an
--      asset-domain row ..................................................... 0
--
--   >> ALL FOUR DENOMINATORS ARE ALSO ZERO. <<
--
--   account_trans_annotation, account_trans_split, user_asset_category,
--   account_trans_annotation_history, pfin.account and pfin.account_trans were ALL
--   EMPTY at that venue. These are VACUOUS ZEROS — not observed absences of
--   violations. Sec's condition names "production-shaped data rather than a fresh
--   stack", and no such dataset exists: there is no V1 deployment, and the
--   incumbent is reference-only. The dev stack is the most-populated V1 instance
--   in existence and it is a fresh stack with respect to all four referent tables.
--
--   Stated in full rather than as "0, 0, 0, 0" because a bare row of zeros in a
--   migration header reads as evidence and would be cited that way later. What the
--   counts establish and what they do not:
--     - counts 1-3 fail CLOSED (every live FK is `on delete restrict`), so the
--       deploy-time-abort risk is NOT retired by a zero here — it is deferred to
--       the first populated instance, which will be an import path, not this file;
--     - count 4 fails SILENTLY. Sec: a non-zero there would mean the id-preservation
--       invariant is doing real work rather than hypothetical work. Zero-over-empty
--       leaves that UNDEMONSTRATED, not disproven. The requirement below is
--       ratified on the hazard's structure, and nothing about it changes.
--   By F2's letter no F/CTO disposition is triggered: that trigger is a NON-ZERO
--   count.
--
--   >> THE DISCHARGE IS RE-ARMED, NOT CLOSED. <<
--
--   These four counts are a PRECONDITION ON THE FIRST POPULATED INSTANCE, and that
--   instance is the incumbent-import path, not this migration. **Re-run all four
--   there, before the import, with the same predicates and the same F/CTO
--   disposition rule for any non-zero result.** A vacuous zero recorded as
--   "checked" is precisely how the deferred abort-risk on counts 1-3 gets
--   discovered in production instead of in a schedule. Booked to BACKLOG so it has
--   a home outside this header, where nobody re-reads it.
--
--   COUNT 4, in one sentence so it is not softened by summary: **ADR-058 Decision
--   2's invariant is ratified on the HAZARD'S STRUCTURE and remains empirically
--   UNDEMONSTRATED** — supported by neither this zero-over-empty nor by anything
--   else yet. Nothing about the mechanism below changes as a result; what changes
--   is what may be claimed for it.
--
-- ----------------------------------------------------------------------------
-- ID PRESERVATION IS A REQUIREMENT OF THIS MIGRATION, NOT A NOTE ON IT
--
-- Every row that moves to pfin.posting_prototype carries its ORIGINAL
-- pfin.user_taxonomy.id. ADR-058 Decision 2, ratified.
--
-- WHY, and the rationale is a hazard with no constraint able to catch it:
-- pfin.account_trans_annotation_history.sub_cat_id (031) is a PLAIN BIGINT
-- SNAPSHOT WITH NO FOREIGN KEY, and that is deliberate — 031's own comment on
-- table records the reason (audit-truthful if the taxonomy row is later deleted).
-- Because there is no FK, nothing follows this split and nothing objects to it. If
-- posting_prototype began its identity at 1, every historical snapshot id would
-- silently resolve to a DIFFERENT row: no constraint fires, no test fails, and the
-- audit trail quietly lies about what a transaction was once classified as.
--
-- With ids preserved, this is a CHANGE OF HOME, NOT A RE-KEY.
--
-- THE BINDING INVARIANT: >> NO ID RESOLVES IN MORE THAN ONE TABLE. << A reader
-- looks in both and gets exactly one hit.
--
-- The stronger form — "the id names its table without a lookup" — is UNDELIVERABLE
-- for pre-split ids (they were all minted by one sequence before any partition
-- existed) and MUST NOT be designed against. A reclass-history reader built on the
-- stronger form is wrong for exactly the historical rows the audit trail exists to
-- serve.
--
-- MECHANISM (ratified: Sec option (B), disjoint reserved ranges, both tables
-- `generated always`). It has TWO halves and only both together deliver the
-- invariant:
--   (i)  pfin.posting_prototype.id starts at a HIGH RESERVED OFFSET (1000000000)
--        and the copy-INSERT uses `overriding system value` to carry the source
--        ids in below it;
--   (ii) pfin.user_taxonomy.id's identity sequence gains MAXVALUE 999999999.
--
-- >> (ii) IS THE HALF THAT MAKES DISJOINTNESS REAL, AND IT IS NOT DECORATION. <<
-- An offset alone does not partition anything: two sequences with a gap between
-- them are disjoint only until the lower one advances into the upper one. That is
-- precisely the failure Sec's F1 vetoed on this ADR's first draft — two sequences
-- set past the same maximum advance in parallel from the same point, so the very
-- next insert on each side mints the same value. With the MAXVALUE, user_taxonomy
-- HARD-ERRORS at the boundary instead of colliding.
--
-- >> THE OFFSET IS A SECURITY INVARIANT, NOT A STYLE CHOICE. << An unexplained
-- magic constant is the first thing a later simplification removes; removing this
-- one re-opens a silent audit-trail corruption that no constraint would catch.
-- Same for the MAXVALUE: it is not a capacity limit, it is the fence.
--
-- Moved rows sit BELOW posting_prototype's own range. That is intended, and it is
-- why the strong form is undeliverable: a pre-split id resolves in exactly one
-- table, but which table cannot be read off the number.
--
-- The paired battery asserts the CONSTRUCTION (Sec F1's condition) — the two
-- identity ranges are disjoint BY DEFINITION, read from pg_sequence, plus the
-- directly checkable half, at least one moved row retaining its pre-split id.
-- "The two id spaces do not overlap" is the WRONG leg: on a fresh stack it is true
-- because nothing has been inserted, which is an assertion with nothing watching
-- what falsifies it.
--
-- ----------------------------------------------------------------------------
-- ORDERING — PREFIX-SAFE, AND IT DEVIATES FROM SEC F11. STATED, NOT SUBSTITUTED.
--
-- 059 established the governing discipline, and it is stronger than the runner's
-- transaction wrapper: >> ORDER THE STEPS SO THAT EVERY PREFIX IS A VALID STATE. <<
-- The wrapper is not relied on here and is not measured. If it holds, nothing is
-- exposed; if it does not, every intermediate state is still coherent.
--
--   1. create posting_prototype + posting_prototype_default (RLS, policies,
--      grants, CHECK, trigger). Prefix valid: nothing references them.
--   2. GUARD: raise unless user_taxonomy's identity has already advanced past the
--      maximum id being moved.
--   3. copy the cashflow rows out with `overriding system value`. Prefix valid:
--      both tables carry the same rows under the same ids, so every path resolves.
--   4. re-issue the readers and fences AT posting_prototype — fn_gl_entries,
--      fn_account_trans_annotation_matched_sub_cat,
--      fn_account_trans_split_matched_sub_cat,
--      fn_account_trans_annotation_trade_constraints. Prefix valid: rows are in
--      both tables.
--   5. ADD the new FKs to posting_prototype, THEN DROP the old FKs to
--      user_taxonomy. Prefix valid: for one moment the column carries two FKs and
--      both validate.
--   6. delete the cashflow rows from user_taxonomy and taxonomy_default. Prefix
--      valid: everything already points at the new home.
--   7. re-issue the two remaining `domain`-reading functions
--      (fn_subcat_market_value, fn_planning_target_matched_sub_cat) BEFORE the
--      column disappears under them.
--   8. drop 028's CHECK; drop column `domain` on both tables; re-create the
--      uniques (the old uniques are dropped WITH the column, not preserved).
--   9. re-emit every catalog comment the split falsifies.
--
-- THE DEVIATION, AND THE LOSING SIDE NAMED. Sec F11 specifies:
-- drop-constraint -> copy -> delete -> re-add against posting_prototype, on the
-- ground that 023/029's FKs are `on delete restrict` so the rows cannot be deleted
-- while those constraints point at user_taxonomy. That reasoning is correct and is
-- honoured — the delete here still happens after the FKs have moved. The
-- difference is that F11's order DROPS the old constraint first, leaving a prefix
-- in which the column is unfenced; this order ADDS the new FK first, so there is
-- never such a window. What F11's order buys that this one does not: nothing I can
-- identify. What this one costs: a transient state in which one column carries two
-- FK constraints, which is legal and in which both validate (the rows are in both
-- tables at that moment).
-- >> Sec ruled the ordering, so this deviation travels to the merge-gate
--    joint-review AS A DEVIATION, not as an implementation detail. <<
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER throughout (default per ADR-011 Lock 11);
-- NOT SECURITY DEFINER.
--
-- This migration authors no new function. It RE-ISSUES six existing ones, every
-- one of which is and stays SECURITY INVOKER with `set search_path = ''`:
--   fn_gl_entries (037) · fn_account_trans_annotation_matched_sub_cat (023) ·
--   fn_account_trans_split_matched_sub_cat (029) ·
--   fn_account_trans_annotation_trade_constraints (030) ·
--   fn_planning_target_matched_sub_cat (074) · fn_subcat_market_value (076/081).
-- The SECURITY DEFINER allowlist (ADR-011 Decision 9) is UNCHANGED by this file;
-- read it live if that ever changes. No count of it is carried here.
--
-- >> `create or replace function` RESETS VOLATILITY AND RESTORES NO POSTURE. <<
-- Every re-issue below re-states its own `security invoker`, its own
-- `set search_path = ''` and, where one is pinned, its own volatility. In
-- particular fn_subcat_market_value is declared STABLE (076, standing rule at 079:
-- "any future CREATE OR REPLACE of these MUST carry `stable` in its own text") and
-- re-states it here. A posture that survives only because nobody re-issued the
-- function is not a posture.
--
-- ----------------------------------------------------------------------------
-- ADR-011 DECISION 3 — RE-TARGET, AND THE FAMILY GAINS NO NEW MEMBER
--
-- Read Decision 3's body LIVE before reading this block: the family grows, its
-- labels are non-contiguous, and *labeled* versus *DDL-realized* diverge. No count
-- is carried here.
--
-- NO NEW FK-SHAPED COLUMN CROSSING AN ISOLATION BOUNDARY IS CREATED. The
-- mandatory check is performed here per column rather than asserted in one line,
-- because the columns are not all the same shape:
--
--   posting_prototype.users_id -> auth.users(id) on delete cascade. An FK, but it
--     IS the tenant anchor — the thing other columns would be matched AGAINST. It
--     crosses no isolation boundary because it defines the boundary. The 009
--     shape, copied.
--   posting_prototype.tax_character -> pfin.tax_character(code) on delete
--     restrict. A NEW FK-SHAPED COLUMN, and it is named here rather than passed
--     over. It references a GLOBAL REGISTRY (ADR-024 / 011 Option C) that carries
--     NO users_id and no tenant dimension of any kind, so there is no tenant to
--     match: every tenant legitimately references every row. It is therefore not a
--     Decision-3 family member — the same disposition user_taxonomy's own
--     fk_user_taxonomy_tax_character already carries, and this column is a copy of
--     that one. ⚠ Contrast the (P2) pattern, which exists precisely for a
--     referenced table that is global for SOME rows and tenant-owned for others;
--     pfin.tax_character has no such second case.
--   posting_prototype_default carries neither a users_id nor any FK at all.
--
-- >> The per-column form is deliberate. << "No new FK-shaped column" would have
-- been FALSE as a bare sentence — tax_character is one — and a reviewer checking
-- it against the DDL would have found the discrepancy and been right to.
--
-- TWO EXISTING INSTANCES RE-TARGET. Sec's numbering pin (transcribed VERBATIM into
-- ADR-058 Decision 5; that transcription is the only text this file may assert on
-- label treatment) rules: canonical instances #10
-- (account_trans_annotation.sub_cat_id, 023) and #13 (account_trans_split.sub_cat_id,
-- 029) KEEP THEIR EXISTING LABELS, keep their status DDL-realized, and keep their
-- fence pattern CR (chain-resolved matched-tenant). No new label is allocated, no
-- label is retired, and no fourth status class is created — the next genuine
-- FK-bypass instance still takes #18.
--
-- A status class tracks the EXISTENCE of the fenced column; the instance entry's
-- body tracks its TARGET. A change of target is an amendment to the entry — never
-- a change of class, never a change of label.
--
-- Instance #17 (planning_target.sub_cat_id, 074) LOSES ITS SECOND PREDICATE here:
-- the `domain = 'asset'` leg becomes structurally redundant, since after the split
-- a prototype is not in user_taxonomy at all and the fence's resolving read finds
-- nothing. Leg 3's coverage does not disappear — it MOVES TO LEG 1 (unresolvable).
--
-- >> The amendments to Decision 3's #10 / #13 / #17 entries ride THIS PR. << That
-- is Decision 3's own rule (its 2026-08-04 fold-in resolution, consequence (c):
-- the fold-in is due in the PR that DDL-realizes the instance, not at the next
-- reconciliation). A migration asserting a target that Decision 3's live text does
-- not carry reproduces the #15/#16 failure exactly: a reviewer obeying the
-- read-Decision-3-live discipline finds the old target and correctly concludes the
-- migration invented one. #8's entry is untouched.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate
-- the catalogued list, and carry no count).
--
-- Decision 4 read verbatim and live before this file was drafted. Three axes
-- clean: no catalogued instance added, removed, reordered or renumbered; no layer
-- re-attributed; no surface becomes "four-layer". This migration introduces no new
-- multi-layer surface — it removes an app-layer rule by making it structural.
-- ⚠ The §10 CATALOGUED set and the CI-FENCED set are DIFFERENT SETS and are not
-- reconciled here or anywhere in this work.
--
-- Incidental and it goes the right way: 028's `comment on constraint` carries two
-- copied counts (a DEFINER-allowlist figure and a §10-ledger figure). That
-- constraint is DROPPED here and its comment goes with it; the replacement on
-- posting_prototype carries no count of anything. A stale figure leaves the
-- catalog as a side effect. Nothing is tidied and no ledger changes.
--
-- ----------------------------------------------------------------------------
-- AAL2 BACKSTOP (025 / ADR-029 C3 standing obligation)
--
-- pfin.posting_prototype is a NEW SENSITIVE TENANT-OWNED pfin TABLE with a live
-- authenticated write path, so it inherits the per-user-conditional aal2 backstop
-- clause on BOTH SIDES — AND-ed into the read USING and the write WITH CHECK,
-- exactly as 025 does for the tables it covers. The clause is copied VERBATIM
-- (Shape A) — not paraphrased, not re-derived — from the two places that already
-- carry it for the table this one is splitting off: 041's user_taxonomy_insert
-- WITH CHECK, and 025's `alter policy user_taxonomy_select ... using (...)`.
--
-- >> The read side is stated because it is the half a migration author skips. <<
-- 009 created user_taxonomy_select WITHOUT the clause and 025 added it later by
-- ALTER POLICY, so a reader copying 009's policy — the obvious source, since it is
-- the CREATE — inherits an UNCLAUSED read policy and opens an aal1 read gap on the
-- direct PostgREST API. Both halves of this table's posture are written here, in
-- one file, so there is no later ALTER for anyone to miss.
--
-- pfin.posting_prototype_default is EXCLUDED under 025 exclusion (i) — global
-- shared-read (`using(true)`), non-tenant reference data (category names and
-- notes; no $-figures), exactly as taxonomy_default is excluded. The exclusion is
-- stated here rather than left to inference, per 025's own convention.
--
-- ----------------------------------------------------------------------------
-- GRANTS RATIONALE — PRESERVING, and every item is one this migration could
-- plausibly get wrong in the direction of "easier" (Sec F5)
--
--   authenticated: SELECT + INSERT on posting_prototype. NO UPDATE, NO DELETE.
--     >> The split is a change of home, not an occasion to un-defer
--        mutate-dormancy. << Un-deferring is the V2 CRUD PR's decision and needs
--        its own review; Sec will veto an UPDATE/DELETE grant arriving here.
--     SELECT on posting_prototype_default (read-only reference data; no write
--     grant for any tier — content is migration-authored).
--   anon: ZERO grant, by construction — the pfin schema ACL grants USAGE only to
--     authenticated, so anon cannot reach the schema at all (ADR-023 C2 outer
--     fence). This migration adds no anon grant.
--   service_role: NO grant, and none is needed. 008 grants explicitly per table
--     with no `alter default privileges`, so both new tables are
--     service_role-ungranted BY CONSTRUCTION. The requirement is only that this
--     migration not add one.
--
-- ACL-before-RLS (PR #106): Postgres checks the table ACL before RLS. Every policy
-- below is paired with the matching GRANT — RLS filters rows, the GRANT is what
-- lets the role reach the table at all.
--
-- ----------------------------------------------------------------------------
-- BLAST RADIUS BEYOND ADR-058's CONSEQUENCE LIST — THREE LIVE CONSUMERS IT DOES
-- NOT NAME
--
-- Measured before authoring, over the LIVE CATALOG rather than over migration
-- text: pg_proc.prosrc across schema pfin matched for `user_taxonomy` and for
-- `domain`, plus pg_policy quals, pg_constraint definitions and pg_index
-- definitions matched for `domain`; cross-checked against the source tree for the
-- objects the measured instance was behind on. ADR-058 Decision 5 measured the
-- FK-shaped referents; Sec F7 measured the battery files; NEITHER measured the
-- function catalog, and that is where these three were.
--
--   CLEAN: no RLS policy on any pfin relation references user_taxonomy (0 rows).
--   The only `domain`-bearing constraints and indexes are on user_taxonomy and
--   taxonomy_default themselves, and are dropped-and-recreated here.
--
--   (1) fn_account_trans_annotation_trade_constraints (030) — HARD BREAK, fails
--       CLOSED. It resolves new.sub_cat_id on account_trans_annotation against
--       pfin.user_taxonomy and is NULL-safe fail-closed, so once the cashflow rows
--       move it resolves to nothing and EVERY annotation write carrying a
--       sub_cat_id raises. Re-targeted below.
--   (2) fn_subcat_market_value (076, live definition at 081) — HARD BREAK on the
--       §2.2.2 money surface. Its body carries THREE `domain = 'asset'` predicates;
--       after `drop column domain` they reference a column that does not exist.
--       Re-issued below with those predicates removed — they become true BY TABLE
--       IDENTITY, which is Decision 5 Finding (b)'s improvement landing on a third
--       surface — and re-stating `stable`.
--   (3) fn_user_asset_category_matched_sub_cat (022) — comment only, NO code
--       change. Its body carries no `domain` reference, so the fence is correct
--       unchanged; its `comment on function` and user_asset_category.sub_cat_id's
--       `comment on column` both assert the app-layer matched-DOMAIN rule, which
--       after this migration names a column that does not exist. Both re-emitted.
--
-- ----------------------------------------------------------------------------
-- PRE-REPOINT FAILURE MODE, PER OBJECT — because a blanket characterization is
-- wrong in one direction or the other, and one of these directions is silent.
--
-- Two reports of this work characterized the un-repointed readers differently:
-- one said the taxonomy reads fail LOUD, the other said they fail SILENT-WRONG.
-- **Both were right about different objects.** Stated per object, measured, since
-- a silent failure described as loud is the dangerous direction to be wrong in.
--
--   fn_gl_entries (037) ....................................... SILENT-WRONG
--     Its two taxonomy reads are LEFT JOINs. Un-repointed they simply MISS, so
--     `ut.cat` is NULL, every branch of both CASE expressions falls through, and
--     the `else` arms post the entry to **Suspense / 'suspense'**. Balanced by
--     construction, no error, no NULL surfaced — every classified cash flow
--     silently reclassified. THIS is the object the loud/quiet distinction
--     matters for, and it is why the re-point rides the same file as the delete.
--   fn_account_trans_annotation_trade_constraints (030) ............... LOUD
--     Resolves the class with a plain SELECT then tests `v_has_tax is null` and
--     RAISES. Un-repointed it rejects every annotation write carrying a
--     sub_cat_id. Fail-closed, and it announces itself.
--   fn_account_trans_annotation_matched_sub_cat (023) ................. LOUD
--   fn_account_trans_split_matched_sub_cat (029) ...................... LOUD
--     `if not exists (...) then raise` — same shape, same direction.
--   fn_subcat_market_value (076/081) ................................. LOUD
--     Not a miss at all: its predicates name a column that no longer exists, so
--     the function errors at runtime on the §2.2.2 surface.
--   fn_planning_target_matched_sub_cat (074) ................ NOT AFFECTED
--     Its target never moved; it loses a predicate, it does not lose a table.
--   the 023/029 FOREIGN KEYS ........................ LOUD, AT MIGRATION TIME
--     `on delete restrict`, so an un-moved FK aborts the delete rather than
--     orphaning anything (Sec F11's reasoning, and it holds).
--
-- ----------------------------------------------------------------------------
-- WHICH FENCE RAISES FIRST, AND WITH WHAT SQLSTATE — measured on a scratch stack
-- carrying the full 001..084 chain, not reasoned.
--
-- A BEFORE-row trigger fires before FK constraint checking, so on every one of
-- these paths the FENCE raises first and the FK never gets to. **The observed
-- SQLSTATE is `P0001` with the fence's own message — never a bare `23503`.**
--   - annotation given a storage-side id -> P0001 from the 023 fence
--   - split child given a storage-side id -> P0001 from the 029 fence
--   - user_asset_category given a PROTOTYPE id -> P0001 from the 022 fence
--     (its message reads "not a taxonomy row owned by users_id …", which stays
--     literally true of a prototype id — the fence is correct, its diagnostic
--     just names tenancy where the cause is vocabulary)
--
-- ⚠ On pfin.account_trans_annotation the BEFORE-row triggers fire in NAME order,
-- so `..._matched_sub_cat` precedes `..._trade_constraints`: **030's fence never
-- sees a storage-side id — 023's raises first.** Anything asserting 030's message
-- on that path is asserting a leg that cannot fire.
--
-- ⚠ 022's and 029's `--` HEADER BLOCKS STAY AS AUTHORED. They are historically
-- true of those migrations and a merged migration's header is not edited to
-- describe a later world. Only the CATALOG text changes, and it changes by
-- re-emission — Sec's routed item (iii) ruling, applied to (3) as well as to the
-- two instances it named.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--
--   pfin.posting_prototype (id, users_id, cat, sub_cat, tax_relevant,
--     tax_character, display_order, is_active, notes, created_at, updated_at)
--     — per-user posting-rule vocabulary. unique (users_id, cat, sub_cat).
--     cat constrained to the ratified accounting-class enum, UNCONDITIONALLY.
--     RLS: SELECT own rows; INSERT own rows AND the 025 aal2 clause. Grants:
--     select + insert to authenticated. Identity: generated always, reserved
--     range starting 1000000000.
--   pfin.posting_prototype_default (id, cat, sub_cat, tax_relevant, tax_character,
--     display_order, notes) — global shared-read default prototype set.
--     unique (cat, sub_cat). RLS using(true); select to authenticated.
--   pfin.user_taxonomy — `domain` REMOVED; unique (users_id, cat, sub_cat);
--     identity capped at 999999999. Asset rows and their ids untouched.
--   pfin.taxonomy_default — `domain` REMOVED; unique (cat, sub_cat).
--   Re-targeted FKs: account_trans_annotation.sub_cat_id and
--     account_trans_split.sub_cat_id -> pfin.posting_prototype(id) on delete
--     restrict. user_asset_category.sub_cat_id and planning_target.sub_cat_id are
--     UNCHANGED — their target did not move.
--   Security-load-bearing edges: id preservation (silent audit corruption if
--     violated); the identity MAXVALUE (the disjointness fence); the verbatim aal2
--     clause; the absence of UPDATE/DELETE grants; NULL-safe fail-closed on every
--     re-issued fence.
-- ============================================================================

create schema if not exists pfin;

-- ============================================================================
-- STEP 1 — the new tables. Prefix valid: nothing references them yet.
-- ============================================================================

-- Column set mirrors pfin.user_taxonomy MINUS `domain` (the table IS the domain).
-- tax_character carries the same FK to the ADR-024 global registry that
-- user_taxonomy carries (011, Option C) — see the Decision 3 per-column check in
-- the header for why that FK is not a family member.
--
-- IDENTITY: `generated always`, reserved range. The offset is a SECURITY
-- INVARIANT (see header) — it keeps newly-minted prototype ids out of
-- user_taxonomy's range so that no id ever resolves in more than one table.
create table if not exists pfin.posting_prototype (
  id             bigint generated always as identity
                   (start with 1000000000 minvalue 1000000000 no cycle)
                   primary key,
  users_id       uuid not null default auth.uid()
                   references auth.users (id) on delete cascade,
  cat            text not null,
  sub_cat        text not null,
  tax_relevant   boolean not null default false,
  tax_character  text
                   references pfin.tax_character (code) on delete restrict,
  display_order  integer,
  is_active      boolean not null default true,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (users_id, cat, sub_cat)
);

comment on table pfin.posting_prototype is
  'Per-user POSTING-RULE vocabulary — the GL journal-entry prototypes a transaction '
  'is classified into (ADR-058 Decisions 1 + 2; the cashflow half of what '
  'pfin.user_taxonomy carried through 083). A prototype names a Cat x Sub-Cat whose '
  'Cat IS the enforced accounting class (Revenue/Expense/Transfer/Equity/Trade — '
  'ADR-031 Decision 3 as amended by Amendment 1 item 1: no flow_class column and no '
  'normal_balance column, because both derive from the class). Carries NO element '
  'and no balance-sheet classification: a prototype has no intrinsic element, and '
  'any element on one would be a derived property of its distinguished contra leg '
  '(ADR-058 Decision 3). Rows moved here from pfin.user_taxonomy KEEP THEIR ORIGINAL '
  'ID VALUES — pfin.account_trans_annotation_history.sub_cat_id is a plain-bigint '
  'snapshot with NO foreign key, so nothing follows a re-key and nothing would '
  'object to one; the audit trail would simply resolve historical ids to different '
  'rows. The id ranges of this table and pfin.user_taxonomy are disjoint BY '
  'CONSTRUCTION (this identity is floored at a reserved offset; user_taxonomy''s is '
  'capped below it), which delivers the invariant NO ID RESOLVES IN MORE THAN ONE '
  'TABLE. It does NOT deliver "the id names its table without a lookup" — that is '
  'undeliverable for pre-split ids, which were all minted by one sequence before any '
  'partition existed, and a reader designed against it is wrong for exactly the '
  'historical rows the audit trail exists to serve. RLS: owner-scoped SELECT and '
  'INSERT, both AND-ed with the 025 aal2 step-up backstop clause. Grants: '
  'authenticated SELECT + INSERT only — UPDATE and DELETE stay deferred to the V2 '
  'taxonomy-CRUD PR, unchanged by this split; anon zero-grant (pfin schema USAGE is '
  'authenticated-only); service_role ungranted by construction (008 grants per table '
  'with no default privileges). The posting-TEMPLATE construct — template header, '
  'legs, amount rules — is NOT built here: this table is the home it will attach to, '
  'and it needs its own ADR and its own Sec surface.';

-- Global default prototype set — the taxonomy_default posture, mirrored.
-- NO users_id, NO FK: Decision-3-neutral. Ids are minted fresh and carry no
-- reserved range, because nothing references a default row's id (no FK, no
-- snapshot; provisioning matches on (cat, sub_cat)), so the audit-truth hazard
-- that makes id preservation load-bearing on the per-user pair has no analogue
-- here. An unexplained reserved range is what a later simplification correctly
-- deletes.
create table if not exists pfin.posting_prototype_default (
  id             bigint generated always as identity primary key,
  cat            text not null,
  sub_cat        text not null,
  tax_relevant   boolean not null default false,
  tax_character  text
                   references pfin.tax_character (code) on delete restrict,
  display_order  integer,
  notes          text,
  unique (cat, sub_cat)
);

comment on table pfin.posting_prototype_default is
  'Global canonical default POSTING-PROTOTYPE set — the provisioning source for '
  'pfin.posting_prototype (ADR-058 Decision 1; the cashflow half of what '
  'pfin.taxonomy_default carried through 083, moved here at 084). Columns mirror '
  'pfin.posting_prototype MINUS users_id. GLOBAL SHARED-READ (RLS using(true), '
  'authenticated SELECT; anon zero; service_role none) — non-tenant reference data '
  '(category names and notes; no $-figures), so EXCLUDED from the 025 aal2 backstop '
  'per exclusion (i), the same disposition pfin.taxonomy_default carries. NO users_id '
  'and NO FK to any tenant-owned table — ADR-011 Decision 3 family UNCHANGED. Ids are '
  'minted fresh here and are NOT range-reserved: nothing references a default row''s '
  'id, so the id-preservation requirement that binds the per-user pair does not reach '
  'this table. Content is migration-authored; changing the default set later is a '
  'data migration, and such a change MUST decide separately whether it reaches '
  'already-provisioned users — never assume first-access provisioning delivers it '
  '(ADR-057).';

-- ----------------------------------------------------------------------------
-- 028's CHECK, moved and UNCONDITIONAL (ADR-058 Decision 4).
--
-- 028 read `domain <> 'cashflow' or cat in (...)`. The disjunct disappears because
-- THE TABLE IS THE DOMAIN. ⚠ Do NOT read its removal as a relaxation: under 028 an
-- asset-domain row was EXEMPT from the class enum; here there are no asset rows to
-- exempt. Coverage is identical and enforcement is STRICTER, because a row can no
-- longer reach this table without being subject to the enum. Sec verified the
-- coverage reading at the touchpoint.
alter table pfin.posting_prototype
  drop constraint if exists posting_prototype_class_chk;

alter table pfin.posting_prototype
  add constraint posting_prototype_class_chk check (
    cat in ('Revenue', 'Expense', 'Transfer', 'Equity', 'Trade')
  );

comment on constraint posting_prototype_class_chk on pfin.posting_prototype is
  'Unconditional accounting-class CHECK on the posting vocabulary (ADR-058 Decision '
  '4; successor to 028''s user_taxonomy_cashflow_class_chk, which was '
  'domain-conditional and is dropped at 084). Constrains top-level cat to the '
  'ratified 5-class accounting enum (Revenue/Expense/Transfer/Equity/Trade) so that '
  'the Category IS the enforced accounting class — no flow_class column, no '
  'normal_balance column, both derive (ADR-031 Decision 3 as amended by Amendment 1 '
  'item 1, which stands exactly as ratified). sub_cat is free text. The predecessor '
  'constraint''s disjunct is GONE because the table is the domain: pre-split an '
  'asset-domain row was exempt from this enum, and there are no asset rows here to '
  'exempt — coverage identical, enforcement stricter. Not an FK (ADR-011 Decision 3 '
  'family unchanged); no elevated privilege.';

-- ----------------------------------------------------------------------------
-- RLS + policies + grants. ACL-before-RLS (PR #106): the GRANT is what lets the
-- role reach the table at all; RLS filters rows.
--
-- ⚠ BOTH policies carry the 025 aal2 backstop clause, copied VERBATIM (Shape A).
-- The SELECT side is written here rather than inherited: 009 created
-- user_taxonomy_select WITHOUT the clause and 025 added it later by ALTER POLICY,
-- so copying the CREATE alone would ship an unclaused read policy and open an aal1
-- read gap on the direct PostgREST API.
alter table pfin.posting_prototype enable row level security;

create policy posting_prototype_select on pfin.posting_prototype
  for select to authenticated
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

create policy posting_prototype_insert on pfin.posting_prototype
  for insert to authenticated
  with check (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

-- SELECT + INSERT only. NO update, NO delete — mutate-dormancy is PRESERVED across
-- the split. Un-deferring it is the V2 CRUD PR's decision and needs its own review;
-- a grant added here would be a scope change wearing a migration's clothes.
grant select, insert on pfin.posting_prototype to authenticated;

-- No separate users_id index: the unique (users_id, cat, sub_cat) btree is
-- users_id-leading and serves the owner-scoped lookups (the 003/009 precedent).

create trigger posting_prototype_set_updated_at
  before update on pfin.posting_prototype
  for each row execute function pfin.fn_refresh_updated_at();

alter table pfin.posting_prototype_default enable row level security;

-- Global shared-read: any authenticated user reads the whole default set (it is the
-- provisioning source). using(true) — no tenant predicate. EXCLUDED from the 025
-- aal2 backstop under exclusion (i), global-shared-read, stated rather than
-- inferred (025's own convention).
create policy posting_prototype_default_select on pfin.posting_prototype_default
  for select to authenticated using (true);

-- Read-only: no insert/update/delete grant for any tier (content is
-- migration-authored).
grant select on pfin.posting_prototype_default to authenticated;

-- ============================================================================
-- STEP 2 — the guard. The disjointness argument becomes STRUCTURAL here rather
-- than inherited from an assumption about how the rows got their ids.
-- ============================================================================

-- The invariant needs user_taxonomy's identity to have ALREADY advanced past every
-- id being moved — otherwise a future user_taxonomy insert could mint an id that a
-- moved prototype row already holds, and the reserved-range fence above would not
-- catch it (both values sit below the offset). On any instance where those rows
-- were minted by that sequence this holds trivially; it is asserted rather than
-- assumed because the failure is silent and the check costs one query.
do $$
declare
  v_max_moved bigint;
  v_seq_last  bigint;
  v_seq       regclass := pg_get_serial_sequence('pfin.user_taxonomy', 'id');
begin
  select max(id) into v_max_moved
    from pfin.user_taxonomy where domain = 'cashflow';

  if v_max_moved is null then
    return;  -- nothing to move; the invariant is vacuous but not violated
  end if;

  execute format('select last_value from %s', v_seq) into v_seq_last;

  if v_seq_last < v_max_moved then
    raise exception
      'GL split aborted: pfin.user_taxonomy identity is at % but the maximum id being moved is % — a future user_taxonomy insert could re-mint an id a moved posting_prototype row already holds (ADR-058 Decision 2, no id resolves in more than one table)',
      v_seq_last, v_max_moved;
  end if;
end;
$$;

-- ============================================================================
-- STEP 3 — copy the rows out, IDS PRESERVED. Prefix valid: both tables now carry
-- the same rows under the same ids, so every path resolves either way.
-- ============================================================================

-- `overriding system value` is what carries the source ids past a
-- `generated always` identity. It is the mechanism the whole audit-truth argument
-- rests on — see the ID PRESERVATION block in the header.
insert into pfin.posting_prototype
  (id, users_id, cat, sub_cat, tax_relevant, tax_character,
   display_order, is_active, notes, created_at, updated_at)
overriding system value
select id, users_id, cat, sub_cat, tax_relevant, tax_character,
       display_order, is_active, notes, created_at, updated_at
  from pfin.user_taxonomy
 where domain = 'cashflow';

-- The default set splits the same way, and it HAS to: provisioning copies the
-- default set into the per-user table, so the cashflow half of the defaults must
-- live in the table whose per-user counterpart is posting_prototype. Ids are not
-- preserved here (see the table comment).
insert into pfin.posting_prototype_default
  (cat, sub_cat, tax_relevant, tax_character, display_order, notes)
select cat, sub_cat, tax_relevant, tax_character, display_order, notes
  from pfin.taxonomy_default
 where domain = 'cashflow';

-- ============================================================================
-- STEP 4 — re-issue the readers and fences AT posting_prototype, BEFORE the FKs
-- move and before any row is deleted. Prefix valid: the rows are in both tables.
--
-- ⚠ Every function below is RE-ISSUED IN FULL with its posture RE-STATED.
-- `create or replace function` resets volatility and restores nothing that is not
-- written again in the new text.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 4a — pfin.fn_gl_entries(date). Re-issued from 037 with ONE change: the two
-- taxonomy joins re-target to pfin.posting_prototype and the alias becomes `pp`.
-- Body otherwise byte-identical to 037's.
--
-- ⚠ THIS RE-TARGET IS WHAT CLOSES SEC'S B1 HAZARD BY CONSTRUCTION, and the
-- direction matters. 082's header records the finding: fn_gl_entries joined
-- pfin.user_taxonomy with NO domain predicate, and 023/029 each record in their own
-- DOMAIN NOTE that matched-DOMAIN is app-layer only in V1 — so an asset-domain row
-- was a permissible sub_cat_id target at the DB layer. In the direction 082 met it,
-- the effect was fail-safe (an unmatched Cat falls through to Suspense). The
-- reusable half was the REVERSE direction: an asset Cat renamed INTO a
-- cashflow-class name would traverse the identical unfenced join and MIS-POST
-- SILENTLY. After this re-target the join can only resolve a posting prototype,
-- because the FK target enforces it. The hazard is not narrowed here; it is
-- removed. Per Sec, no battery leg was owed at the rename PR — the leg belongs
-- with this one.
--
-- Alias renamed ut -> pp deliberately: an alias reading `ut` over
-- pfin.posting_prototype in a money-path function is exactly the kind of stale
-- vocabulary this split exists to remove, and the substitution is mechanical and
-- countable (11 sites).

create or replace function pfin.fn_gl_entries(p_as_of date)
returns table (
  users_id        uuid,
  as_of           date,
  source_trans_id bigint,
  split_id        bigint,
  journal_id      bigint,
  account_id      bigint,
  entry_account   text,
  security_id     bigint,
  entry_class     text,
  side            text,
  currency        text,
  amount_book     numeric
)
language sql
security invoker
set search_path = ''
as $$
  with txn as (
    select
      t.trans_id, t.account_id, t.amount, t.security_id, t.quantity, t.cost_basis,
      t.transaction_type, t.transaction_date,
      a.users_id     as users_id,
      a.currency     as currency,
      a.name         as account_name,
      ann.journal_id as journal_id,
      (ann.metadata ->> 'reason') as reason,
      pp.cat         as flow_class,
      (select count(*) from pfin.account_trans_split s where s.account_trans_id = t.trans_id) as split_count
    from pfin.account_trans t
    join pfin.account a on a.account_id = t.account_id
    left join pfin.account_trans_annotation ann on ann.trans_id = t.trans_id
    left join pfin.posting_prototype pp on pp.id = ann.sub_cat_id
    where t.transaction_date <= p_as_of
  ),

  -- SELL completion (Component 1): the current re-match batch per sell, its matched
  -- acquisition basis (FIFO/specific-lot), and the pro-rata basis_adjust term → the
  -- matched lots' CURRENT CARRIED BOOK value. Only sells WITH lot_match rows appear here;
  -- unmatched sells fall through to the Suspense floor (P8).
  sell_curr_batch as (
    select lm.sell_trans_id, lm.buy_trans_id, lm.quantity_matched
    from pfin.lot_match lm
    where lm.match_seq = (
      select max(lm2.match_seq) from pfin.lot_match lm2 where lm2.sell_trans_id = lm.sell_trans_id
    )
  ),
  sell_agg as (
    select
      t.trans_id as sell_trans_id, t.users_id, t.account_id, t.account_name, t.security_id,
      t.journal_id, t.currency, t.amount, t.transaction_date,
      coalesce(sum(scb.quantity_matched * (coalesce(b.cost_basis, 0) / nullif(b.quantity, 0))), 0) as matched_acq,
      coalesce(sum(scb.quantity_matched), 0) as matched_qty
    from txn t
    join sell_curr_batch scb on scb.sell_trans_id = t.trans_id
    join pfin.account_trans b on b.trans_id = scb.buy_trans_id
    where t.transaction_type = 'standard' and t.security_id is not null and t.quantity < 0
    group by t.trans_id, t.users_id, t.account_id, t.account_name, t.security_id,
             t.journal_id, t.currency, t.amount, t.transaction_date
  ),
  sell_book as (
    select
      sa.users_id, sa.sell_trans_id, sa.account_id, sa.account_name, sa.security_id,
      sa.journal_id, sa.currency, sa.amount,
      sa.matched_acq
      + coalesce(
          (select coalesce(sum(ba.cost_basis), 0)
             from pfin.account_trans ba
            where ba.account_id = sa.account_id and ba.security_id = sa.security_id
              and ba.transaction_type = 'basis_adjust'
              and ba.transaction_date <= sa.transaction_date)
          * (sa.matched_qty / nullif(
              (select sum(bq.quantity)
                 from pfin.account_trans bq
                where bq.account_id = sa.account_id and bq.security_id = sa.security_id
                  and bq.quantity > 0 and bq.transaction_date <= sa.transaction_date), 0)),
          0) as matched_book
    from sell_agg sa
  ),

  -- REAL LEGS: P1 cash + P2 position adds + the SELL position removal (Component 1).
  real_leg as (
    -- P1: cash leg — every cash-bearing row (incl. the sell's proceeds).
    select
      t.users_id, t.trans_id as source_trans_id, null::bigint as split_id, t.journal_id,
      t.account_id, t.account_name as entry_account, null::bigint as security_id,
      'asset_liability'::text as entry_class, t.currency, t.amount as amount_book
    from txn t
    where t.amount <> 0
    union all
    -- P2: position book add — BUY / acct_setup position / basis_adjust delta. Standard
    --     non-buys (sell / zero-qty) excluded (the sell removes position via sell_book).
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      t.account_id, t.account_name, t.security_id,
      'trade_position'::text, t.currency, t.cost_basis
    from txn t
    where t.security_id is not null
      and t.cost_basis is not null and t.cost_basis <> 0
      and not (t.transaction_type = 'standard' and t.quantity <= 0)
    union all
    -- SELL position removal (Component 1): remove the matched lots at current carried book.
    select
      sb.users_id, sb.sell_trans_id, null::bigint, sb.journal_id,
      sb.account_id, sb.account_name, sb.security_id,
      'trade_position'::text, sb.currency, (- sb.matched_book)
    from sell_book sb
  ),

  contra as (
    -- P3: standard cash-flow contra (non-split), by the 023 overlay cat.
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint as account_id,
      case
        when t.flow_class = 'Revenue'  then 'Revenue'
        when t.flow_class = 'Expense'  then 'Expense'
        when t.flow_class = 'Equity'   then 'Equity'
        when t.flow_class = 'Transfer' and t.journal_id is not null then 'Journal Clearing'
        else 'Suspense'
      end as entry_account,
      null::bigint,
      case
        when t.flow_class = 'Revenue'  then 'revenue'
        when t.flow_class = 'Expense'  then 'expense'
        when t.flow_class = 'Equity'   then 'equity'
        when t.flow_class = 'Transfer' and t.journal_id is not null then 'journal_clearing'
        else 'suspense'
      end as entry_class,
      t.currency, (- t.amount) as amount_book
    from txn t
    where t.transaction_type = 'standard' and t.security_id is null
      and t.split_count = 0 and t.amount <> 0

    union all
    -- P4: split-child contras — one per 029 child, by the CHILD's cat.
    select
      t.users_id, t.trans_id, s.id, t.journal_id, null::bigint,
      case
        when pp.cat = 'Revenue'  then 'Revenue'
        when pp.cat = 'Expense'  then 'Expense'
        when pp.cat = 'Equity'   then 'Equity'
        when pp.cat = 'Transfer' and t.journal_id is not null then 'Journal Clearing'
        else 'Suspense'
      end,
      null::bigint,
      case
        when pp.cat = 'Revenue'  then 'revenue'
        when pp.cat = 'Expense'  then 'expense'
        when pp.cat = 'Equity'   then 'equity'
        when pp.cat = 'Transfer' and t.journal_id is not null then 'journal_clearing'
        else 'suspense'
      end,
      t.currency, (- s.amount)
    from txn t
    join pfin.account_trans_split s on s.account_trans_id = t.trans_id
    left join pfin.posting_prototype pp on pp.id = s.sub_cat_id
    where t.split_count > 0

    union all
    -- P5: acct_setup contra → Opening-Balance-Equity (offsets cash + opening position).
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint, 'Opening Balance Equity', null::bigint, 'opening_equity',
      t.currency,
      - ( coalesce(t.amount, 0)
          + coalesce(case when t.security_id is not null then t.cost_basis else 0 end, 0) )
    from txn t
    where t.transaction_type = 'acct_setup'

    union all
    -- P6: basis_adjust depreciation contra → Dr Depreciation-Expense.
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint, 'Depreciation Expense', null::bigint, 'depreciation_expense',
      t.currency, (- t.cost_basis)
    from txn t
    where t.transaction_type = 'basis_adjust' and t.reason = 'depreciation'
      and t.cost_basis is not null and t.cost_basis <> 0

    union all
    -- P7: basis_adjust wash_sale / unknown-reason contra → Suspense (DEFERRED D1, 037).
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint, 'Suspense', null::bigint, 'suspense',
      t.currency, (- t.cost_basis)
    from txn t
    where t.transaction_type = 'basis_adjust'
      and (t.reason is null or t.reason not in ('depreciation', 'return_of_capital'))
      and t.cost_basis is not null and t.cost_basis <> 0

    union all
    -- P8: UNMATCHED standard security non-buy (sell w/o lot_match, or zero-qty) → Suspense
    --     (the park-if-unmatched floor). Matched sells are completed via sell_book, so they
    --     are excluded here by the NOT EXISTS.
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint, 'Suspense', null::bigint, 'suspense',
      t.currency, (- t.amount)
    from txn t
    where t.transaction_type = 'standard' and t.security_id is not null and t.quantity <= 0
      and not exists (select 1 from pfin.lot_match lm where lm.sell_trans_id = t.trans_id)

    union all
    -- SELL realized-gain (Component 1): the single equity line = proceeds − matched book.
    -- (matched_book − amount): a GAIN (proceeds > book) is negative → credit to equity.
    select
      sb.users_id, sb.sell_trans_id, null::bigint, sb.journal_id,
      null::bigint, 'Realized Gain/(Loss)', null::bigint, 'realized_gain',
      sb.currency, (sb.matched_book - sb.amount)
    from sell_book sb

    union all
    -- P9: corp_action counter → Suspense (book-neutral nets 0 & drops; SUBSTANTIVE deferred D2).
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint, 'Suspense', null::bigint, 'suspense',
      t.currency,
      - ( coalesce(t.amount, 0)
          + coalesce(case when t.security_id is not null then t.cost_basis else 0 end, 0) )
    from txn t
    where t.transaction_type = 'corp_action'

    union all
    -- P10: standard BUY residual plug → Suspense (0 for a clean buy).
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint, 'Suspense', null::bigint, 'suspense',
      t.currency, - ( coalesce(t.amount, 0) + coalesce(t.cost_basis, 0) )
    from txn t
    where t.transaction_type = 'standard' and t.security_id is not null and t.quantity > 0

    union all
    -- P11: return_of_capital residual plug → Suspense (0 when cash-in = basis-out).
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint, 'Suspense', null::bigint, 'suspense',
      t.currency, - ( coalesce(t.amount, 0) + coalesce(t.cost_basis, 0) )
    from txn t
    where t.transaction_type = 'basis_adjust' and t.reason = 'return_of_capital'
  ),

  postings as (
    select * from real_leg
    union all
    select * from contra
  ),

  book_nav as (
    select coalesce(sum(
      rl.amount_book
      * case when rl.currency = 'USD' then 1.0
             else coalesce((
               select fx.price from pfin.eod_price fx
               join pfin.asset ca on ca.asset_id = fx.asset_id
               where ca.users_id is null and ca.asset_type = 'currency'
                 and ca.symbol = rl.currency and fx.source = 'fx_feed'
                 and fx.price_date <= p_as_of
               order by fx.price_date desc limit 1), 1.0) end
    ), 0) as v
    from real_leg rl
  ),

  memo as (
    select
      auth.uid() as users_id,
      null::bigint as source_trans_id, null::bigint as split_id, null::bigint as journal_id,
      null::bigint as account_id,
      'Market Value Adjustment'::text as entry_account, null::bigint as security_id,
      'unrealized_gains'::text as entry_class, 'USD'::text as currency,
      (pfin.fn_compute_nav(p_as_of) - (select v from book_nav)) as amount_book
    union all
    select
      auth.uid(),
      null::bigint, null::bigint, null::bigint,
      null::bigint, 'Unrealized Gains (Equity)', null::bigint,
      'unrealized_gains', 'USD',
      - (pfin.fn_compute_nav(p_as_of) - (select v from book_nav))
  ),

  all_rows as (
    select * from postings
    union all
    select * from memo
  )

  select
    ar.users_id,
    p_as_of as as_of,
    ar.source_trans_id,
    ar.split_id,
    ar.journal_id,
    ar.account_id,
    ar.entry_account,
    ar.security_id,
    ar.entry_class,
    case when ar.amount_book >= 0 then 'dr' else 'cr' end as side,
    ar.currency,
    ar.amount_book
  from all_rows ar
  where ar.amount_book <> 0
  order by ar.source_trans_id nulls last, ar.entry_class;
$$;

-- ACL re-stated rather than assumed. `create or replace` preserves an existing
-- ACL, so these two are idempotent — they are written because a posture that
-- survives only by not being touched is not a posture.
revoke execute on function pfin.fn_gl_entries(date) from public;
grant execute on function pfin.fn_gl_entries(date) to authenticated;

comment on function pfin.fn_gl_entries(date) is
  'SECURITY INVOKER book-value GL / trial-balance read helper (M4-GL; ADR-031 Decision 5 / '
  'Lock 11). 037 completes the SELL: a matched sell (lot_match current batch, FIFO/specific-'
  'lot) posts Dr Cash / Cr Position(current carried book = FIFO acquisition + pro-rata '
  'basis_adjust) / one Realized-Gain line to equity (proceeds − book) — balanced-by-'
  'construction; ST/LT + recapture character is DERIVED in the tax layer, not posted (Option '
  'A). Unmatched sells park in Suspense (035 floor). Book-neutral corp_actions are no-ops; '
  'substantive corp_action + basis_adjust wash_sale stay Suspense-parked (deferred). Signature '
  'unchanged from 035; SUM(amount_book)=0 by construction; INVOKER (cross-tenant → no rows); '
  'set search_path=''''. RE-TARGETED at 084 (ADR-058 Decisions 1 + 5): the two taxonomy joins '
  'now resolve pfin.posting_prototype, not pfin.user_taxonomy. That is a CORRECTNESS change, '
  'not a rename — before it, the join carried no domain predicate and 023/029 record '
  'matched-DOMAIN as app-layer only, so a storage-classification row was a permissible '
  'sub_cat_id target at the DB layer and an asset Cat bearing a cashflow-class name would '
  'have mis-posted silently; the FK target now makes that unreachable. SUPERSEDES the '
  'ledger-count clause this comment carried at 037 (it named a §10 figure and a DEFINER '
  'figure): a catalog comment cannot carry a count it will not maintain — read ADR-011 '
  'Decision 4 and Decision 9 live. ADR-011 Decision 3 family unchanged by 084.';

-- ----------------------------------------------------------------------------
-- 4b — the two CHAIN-RESOLVED matched-tenant fences, ADR-011 Decision 3 canonical
-- instances #10 (023) and #13 (029). RE-TARGETED, not re-labelled.
--
-- Per Sec's numbering pin (transcribed verbatim into ADR-058 Decision 5): both
-- KEEP their existing labels, KEEP status DDL-realized, and KEEP fence pattern CR.
-- No new label is allocated, no label is retired, no fourth status class is
-- created. A status class tracks whether the fenced column EXISTS; the entry's
-- body tracks its target. Decision 3's #10 and #13 entries are amended in THIS PR.
--
-- ⚠ THE FK IS TENANT-BLIND — that is Decision 3's entire premise — so nothing
-- about re-targeting carries the matched-tenant property forward. Both fences
-- still resolve the owning tenant via trans_id -> account_trans -> account.users_id
-- and still compare it explicitly; the only thing that changed is which table the
-- referenced row is read from.
--
-- Error-message text changed with the target ("taxonomy row" -> "posting
-- prototype"): a fence that no longer touches the taxonomy must not say it does.
-- Flagged to QA explicitly because the paired battery asserts on these strings.

create or replace function pfin.fn_account_trans_annotation_matched_sub_cat()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Trigger WHEN clause guarantees new.sub_cat_id IS NOT NULL.
  -- CHAIN-RESOLVED matched-tenant: resolve the annotation's owning tenant via
  -- trans_id → account_trans.account_id → account.users_id, then require the referenced
  -- posting_prototype row to share it.
  -- NULL-SAFE FAIL-CLOSED: a missing prototype row, a missing/unreadable transaction, a
  -- missing account, OR a users_id mismatch yields NOT EXISTS → raise. (Never
  -- `(subquery) <> ...` — that returns NULL on a missing row, the IF is skipped, and the
  -- write would leak.)
  -- LOAD-BEARING regardless of writer (C-NOTE (a)): the explicit pp.users_id =
  -- acc.users_id predicate is authoritative even if RLS is bypassed (a hypothetical
  -- service_role annotation writer under §6A Option A). Under authenticated it composes
  -- with posting_prototype_select + the account-chain RLS as belt-and-suspenders.
  if not exists (
    select 1
    from pfin.posting_prototype pp
    join pfin.account_trans t on t.trans_id = new.trans_id
    join pfin.account acc on acc.account_id = t.account_id
    where pp.id = new.sub_cat_id
      and pp.users_id = acc.users_id
  ) then
    raise exception
      'Sub-Cat reference rejected: sub_cat_id % is not a posting prototype owned by and visible to the tenant of trans_id % — not found, not visible under current AAL, or cross-tenant (ADR-011 Decision 3 canonical instance #10 / matched-tenant fence, chain-resolved)',
      new.sub_cat_id, new.trans_id;
  end if;
  return new;
end;
$$;

revoke execute on function pfin.fn_account_trans_annotation_matched_sub_cat() from public;

comment on function pfin.fn_account_trans_annotation_matched_sub_cat() is
  'BEFORE INSERT OR UPDATE matched-tenant fence on pfin.account_trans_annotation.sub_cat_id (ADR-011 Decision 3 canonical instance #10 / 012 Pattern 1, CHAIN-RESOLVED; ADR-027 R-17; SELF-283). RE-TARGETED at 084 (ADR-058 Decisions 1 + 5) from pfin.user_taxonomy to pfin.posting_prototype: the referenced row now has to be a POSTING PROTOTYPE owned by the annotation''s OWNING tenant — resolved via trans_id → account_trans.account_id → account.users_id (this table has NO own users_id; contrast 012/022 which match a local new.users_id). The label, the DDL-realized status and the CR fence pattern are RETAINED — a re-target is an amendment to the instance entry, never a change of class or label, and the next genuine FK-bypass instance is unaffected. NULL-safe fail-closed (NOT EXISTS → raise). SECURITY INVOKER + set search_path = '''' — the explicit pp.users_id = acc.users_id predicate is authoritative regardless of RLS; under authenticated it composes with posting_prototype_select (auth.uid()-scoped) + the account-chain RLS as belt-and-suspenders. Covers UPDATE (re-categorization), not just INSERT. Trigger rather than a bare CHECK because it subqueries and JOINs the referenced vocabulary and account chain. Not a DEFINER allowlist entry (INVOKER); read ADR-011 Decision 9 live rather than any count. SUPERSEDES the clause this comment carried from 023, that matched-DOMAIN (domain=''cashflow'') is app-layer in V1: after 084 there is no domain column and no cross-vocabulary reference is possible — the FK target enforces it.';

create or replace function pfin.fn_account_trans_split_matched_sub_cat()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Trigger WHEN clause guarantees new.sub_cat_id IS NOT NULL.
  -- CHAIN-RESOLVED matched-tenant: resolve the split child's owning tenant via
  -- account_trans_id → account_trans.account_id → account.users_id, then require the
  -- referenced posting_prototype row to share it. NULL-SAFE FAIL-CLOSED: a missing prototype
  -- row, a missing/unreadable transaction/account, OR a users_id mismatch → NOT EXISTS →
  -- raise (never `(subquery) <> ...`, which returns NULL on a missing row → the IF is
  -- skipped → the write would leak). LOAD-BEARING regardless of writer: the explicit
  -- pp.users_id = acc.users_id predicate is authoritative even if RLS is bypassed (a
  -- hypothetical service_role split writer); under authenticated it composes with
  -- posting_prototype_select + the account-chain RLS as belt-and-suspenders.
  if not exists (
    select 1
    from pfin.posting_prototype pp
    join pfin.account_trans t on t.trans_id = new.account_trans_id
    join pfin.account acc on acc.account_id = t.account_id
    where pp.id = new.sub_cat_id
      and pp.users_id = acc.users_id
  ) then
    raise exception
      'cross-tenant Sub-Cat rejected: sub_cat_id % is not a posting prototype owned by the tenant of account_trans_id % (ADR-011 Decision 3 matched-tenant fence, chain-resolved; M2.5 / SELF-294)',
      new.sub_cat_id, new.account_trans_id;
  end if;
  return new;
end;
$$;

revoke execute on function pfin.fn_account_trans_split_matched_sub_cat() from public;

comment on function pfin.fn_account_trans_split_matched_sub_cat() is
  'BEFORE INSERT OR UPDATE matched-tenant fence on pfin.account_trans_split.sub_cat_id (ADR-011 Decision 3 canonical instance #13, CHAIN-RESOLVED; verbatim mirror of 023 #10; M2.5 / SELF-294). RE-TARGETED at 084 (ADR-058 Decisions 1 + 5) from pfin.user_taxonomy to pfin.posting_prototype: the referenced row now has to be a POSTING PROTOTYPE owned by the split child''s OWNING tenant — resolved via account_trans_id → account_trans.account_id → account.users_id (this table has NO own users_id). Label, DDL-realized status and CR fence pattern RETAINED; a re-target amends the instance entry, never its class or label. NULL-safe fail-closed (NOT EXISTS → raise). SECURITY INVOKER + set search_path='''' — the explicit pp.users_id = acc.users_id predicate is authoritative regardless of RLS; under authenticated it composes with posting_prototype_select (auth.uid()-scoped) + the account-chain RLS. Covers UPDATE as well as INSERT. SUPERSEDES the clause this comment carried from 029, that matched-DOMAIN is app-layer in V1: after 084 there is no domain column and the FK target makes a cross-vocabulary reference unreachable.';

-- ----------------------------------------------------------------------------
-- 4c — pfin.fn_account_trans_annotation_trade_constraints (030). NOT named in
-- ADR-058's consequence list; found by measuring the live function catalog.
--
-- It resolves the annotation's sub_cat_id to read (cat, sub_cat) and is NULL-safe
-- fail-closed, so once the prototypes leave user_taxonomy this read finds nothing
-- and EVERY annotation write carrying a sub_cat_id raises. Re-targeted here. The
-- fence's own semantics are untouched: consistency (security_id present <=>
-- cat='Trade') and sign-alignment are unchanged, and it stays Decision-3-neutral —
-- #10 fences the cross-tenant dimension on the same write.

create or replace function pfin.fn_account_trans_annotation_trade_constraints()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_has_txn      boolean;
  v_security_id  bigint;
  v_quantity     numeric;
  v_has_tax      boolean;
  v_cat          text;
  v_sub_cat      text;
begin
  -- Trigger WHEN clause guarantees new.sub_cat_id IS NOT NULL (a NULL/Unsorted-pending
  -- cat is allowed → Suspense downstream; only categorized rows are Trade-checked).

  -- Resolve the FROZEN FACT (immutable ledger, 004/017).
  select true, t.security_id, t.quantity
    into v_has_txn, v_security_id, v_quantity
    from pfin.account_trans t
   where t.trans_id = new.trans_id;

  -- Resolve the CLASS (the posting vocabulary, 084). cat is NOT NULL; a
  -- cross-tenant sub_cat_id is already rejected by the #10 matched-tenant fence
  -- (fires on the same write), so under INVOKER this read sees the caller's own row.
  select true, pp.cat, pp.sub_cat
    into v_has_tax, v_cat, v_sub_cat
    from pfin.posting_prototype pp
   where pp.id = new.sub_cat_id;

  -- NULL-SAFE FAIL-CLOSED: a missing/unreadable transaction OR prototype row → raise
  -- (never a silent skip that would let an unvalidated Trade row through).
  if v_has_txn is null or v_has_tax is null then
    raise exception
      'Trade constraint: cannot resolve fact (trans_id %) or class (sub_cat_id %) — not found or not visible under current AAL; fail-closed (M1-evt / SELF-293)',
      new.trans_id, new.sub_cat_id;
  end if;

  -- (a) CONSISTENCY: security_id present  ⟺  cat = 'Trade'. (Biconditional via XOR;
  -- both operands are non-null booleans — v_cat is NOT NULL.)
  if (v_security_id is not null) <> (v_cat = 'Trade') then
    raise exception
      'Trade consistency violation (ADR-031 Amendment 1 s2a): security_id % and cat=% must satisfy (security_id present <=> cat=''Trade'') (M1-evt / SELF-293)',
      v_security_id, v_cat;
  end if;

  -- (b) SIGN-ALIGNMENT (cat='Trade' only): BTO/BTC ⟹ quantity > 0; STC/STO ⟹ < 0.
  -- quantity is NOT NULL (004 default 0), so the comparisons are NULL-safe. A Trade
  -- sub_cat outside the four is consistency-checked (above) but not sign-checked.
  if v_cat = 'Trade' then
    if v_sub_cat in ('BTO', 'BTC') and not (v_quantity > 0) then
      raise exception
        'Trade sign-alignment (ADR-031 Amendment 1 s2b): sub_cat % requires quantity > 0 (buy), got % (M1-evt / SELF-293)',
        v_sub_cat, v_quantity;
    elsif v_sub_cat in ('STC', 'STO') and not (v_quantity < 0) then
      raise exception
        'Trade sign-alignment (ADR-031 Amendment 1 s2b): sub_cat % requires quantity < 0 (sell), got % (M1-evt / SELF-293)',
        v_sub_cat, v_quantity;
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function pfin.fn_account_trans_annotation_trade_constraints() from public;

comment on function pfin.fn_account_trans_annotation_trade_constraints() is
  'Combined Trade-constraint fence on pfin.account_trans_annotation (Sec Condition A; '
  'ADR-031 Amendment 1 §2; M1-evt Slice A1 / SELF-293). BEFORE INSERT OR UPDATE WHEN '
  '(new.sub_cat_id IS NOT NULL). Resolves the FROZEN FACT (security_id, quantity) via '
  'trans_id → account_trans (004/017) + the CLASS (cat, sub_cat) via sub_cat_id → '
  'pfin.posting_prototype, then enforces BOTH: (a) CONSISTENCY — security_id present '
  '<=> cat=''Trade'' (a securities row must be a Trade; a Trade must carry a '
  'security_id); (b) SIGN-ALIGNMENT — BTO/BTC ⟹ quantity>0 (buy), STC/STO ⟹ '
  'quantity<0 (sell). RE-TARGETED at 084 (ADR-058 Decisions 1 + 5): the class read '
  'was pfin.user_taxonomy through 083. It is NULL-safe fail-closed, so leaving it '
  'pointed at the storage spine would have rejected every categorized annotation '
  'write rather than failing quietly — the direction that announces itself, but a '
  'break either way. Cross-table (facts on the immutable ledger, class on the '
  'posting vocabulary) → a trigger, not a single-table CHECK. UPDATE path '
  'load-bearing: re-validates on every overlay edit (BTO→STO on a frozen-quantity '
  'row). SECURITY INVOKER + set search_path='''' — Decision-3-NEUTRAL (no '
  'cross-tenant dimension; #10 fences a cross-tenant sub_cat on the same write); '
  'NOT a DEFINER allowlist entry — read ADR-011 Decision 9 live rather than the '
  'figure this comment carried at 030. The UI is not the integrity boundary — this '
  'trigger is (Amendment 1 §2b). A NULL sub_cat (Suspense-pending) is WHEN-skipped; '
  'a non-BTO/BTC/STC/STO Trade sub_cat is consistency-checked but not sign-checked.';

-- ============================================================================
-- STEP 5 — move the FKs. ADD the new ones FIRST, then drop the old ones, so the
-- column is never unfenced. See the ORDERING block in the header for why this
-- deviates from Sec F11 and what the deviation costs.
--
-- Both constraints validate at this point because the rows are in BOTH tables.
-- ============================================================================

alter table pfin.account_trans_annotation
  add constraint account_trans_annotation_sub_cat_id_prototype_fkey
  foreign key (sub_cat_id) references pfin.posting_prototype (id) on delete restrict;

alter table pfin.account_trans_split
  add constraint account_trans_split_sub_cat_id_prototype_fkey
  foreign key (sub_cat_id) references pfin.posting_prototype (id) on delete restrict;

alter table pfin.account_trans_annotation
  drop constraint if exists account_trans_annotation_sub_cat_id_fkey;

alter table pfin.account_trans_split
  drop constraint if exists account_trans_split_sub_cat_id_fkey;

-- ⚠ user_asset_category.sub_cat_id (022, canonical #8) and planning_target.sub_cat_id
-- (074, canonical #17) are DELIBERATELY UNTOUCHED. Their FK target did not move —
-- that is the whole dividend of the asymmetric shape (ADR-058 Decision 1): the
-- referents partition two-and-two along the cut seam, so half of them need no
-- change at all.

-- ============================================================================
-- STEP 6 — delete the moved rows from their old home. Prefix valid: every reader
-- and every FK already points at the new home.
-- ============================================================================

delete from pfin.user_taxonomy where domain = 'cashflow';
delete from pfin.taxonomy_default where domain = 'cashflow';

-- ============================================================================
-- STEP 7 — re-issue the two remaining functions that READ user_taxonomy.domain,
-- BEFORE the column disappears under them.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 7a — pfin.fn_subcat_market_value. NOT named in ADR-058's consequence list;
-- found by measuring the live function catalog. Its body carried THREE
-- `domain = 'asset'` predicates, so after `drop column domain` it would reference
-- a column that does not exist — on the §2.2.2 money surface.
--
-- The three predicates are REMOVED, not replaced: after the split
-- pfin.user_taxonomy holds only storage-classification rows, so `domain = 'asset'`
-- is true by TABLE IDENTITY. That is ADR-058 Decision 5 Finding (b)'s improvement
-- (a property enforced by construction beats one enforced by review) landing on a
-- third surface it did not name.
--
-- ⚠ `stable` IS RE-STATED, not inherited. 079's standing rule: any future CREATE
-- OR REPLACE of these functions must carry `stable` in its own text, because
-- create-or-replace resets volatility and the loss is invisible to every value
-- assertion.
--
-- ⚠ The load-bearing users_id conjunct on the `lut` name-keyed join is KEPT
-- exactly as authored. It is the sole tenant discriminator on a SHARED-VOCABULARY
-- string key, which fails OPEN under an RLS regression — unlike its id-keyed
-- siblings, which fail closed. Its at-most-one-row argument is re-pointed at the
-- new unique key rather than left asserting the dropped one.

create or replace function pfin.fn_subcat_market_value(
  p_as_of               date    default current_date,
  p_include_real_estate boolean default false
)
returns table (
  sub_cat_id   bigint,
  cat          text,
  sub_cat      text,
  market_value numeric
)
language sql
security invoker
stable
set search_path = ''
as $$
  with sec_leg as (
    -- Securities: fn_holdings_as_of per-(account, asset) quantity × price × fx.
    -- Kernel copied verbatim from 059's fn_compute_nav securities leg.
    -- CLOSURE PREDICATE (059): pfin.account is reached by LEFT JOIN here, so the
    -- three-conjunct form is mandatory — acc2.account_id is not null AND the
    -- dated test. A bare closed_at-is-null would fail OPEN on a join miss.
    -- CLASSIFICATION: LEFT JOIN the junction and the taxonomy, so an unclassified
    -- (or non-asset-classified) holding keeps its value and lands under a NULL key.
    select
      ut.id                                                as k_id,
      ut.cat                                               as k_cat,
      ut.sub_cat                                           as k_sub_cat,
      h.quantity
      * (select ep.price
         from pfin.eod_price ep
         where ep.asset_id = h.asset_id and ep.price_date <= p_as_of
         order by ep.price_date desc,
                  case ep.source
                    when 'manual_valuation' then 1
                    when 'market_feed'      then 2
                    when 'spot_feed'        then 2
                    when 'fx_feed'          then 2
                    when 'provider_implied' then 3
                    else 4
                  end,
                  ep.price_id desc
         limit 1)
      * case when a.currency = 'USD' then 1.0
             else coalesce((
               select fx.price from pfin.eod_price fx
               join pfin.asset ca on ca.asset_id = fx.asset_id
               where ca.users_id is null and ca.asset_type = 'currency'
                 and ca.symbol = a.currency and fx.source = 'fx_feed'
                 and fx.price_date <= p_as_of
               order by fx.price_date desc limit 1), 1.0) end   as v
    from pfin.fn_holdings_as_of(p_as_of) h
    join pfin.asset a on a.asset_id = h.asset_id
    left join pfin.account acc2 on acc2.account_id = h.account_id
    left join pfin.user_asset_category uac on uac.asset_id = h.asset_id
    left join pfin.user_taxonomy ut
      on ut.id = uac.sub_cat_id
    where acc2.account_id is not null
      and (acc2.closed_at is null or acc2.closed_at::date > p_as_of)
  ),
  cash_leg as (
    -- Cash: per-account balance × fx. TWO classification routes, chosen by
    -- account_type and by nothing else (081):
    --   · account_type = 'liability' → the seeded 'Liabilities' /
    --     'Liability Balances' row in the CALLER'S OWN taxonomy (080), matched by
    --     NAME. Mechanical: no user choice, no UI, no per-account decision.
    --   · every other account_type   → the GLOBAL currency-asset's per-user
    --     junction row (the 022 cash-via-currency-asset model), which yields ONE
    --     Sub-Cat per user per currency and cannot distinguish per account.
    -- pfin.account is joined DIRECTLY here (not left-joined), so the bare
    -- two-clause 059 predicate is correct and the three-conjunct form is not
    -- needed — the 049 / 059 cash-leg shape.
    select
      case when acc.account_type = 'liability' then lut.id      else ut.id      end as k_id,
      case when acc.account_type = 'liability' then lut.cat     else ut.cat     end as k_cat,
      case when acc.account_type = 'liability' then lut.sub_cat else ut.sub_cat end as k_sub_cat,
      coalesce(c.balance_native, 0)
      * case when acc.currency = 'USD' then 1.0
             else coalesce((
               select fx.price from pfin.eod_price fx
               join pfin.asset ca on ca.asset_id = fx.asset_id
               where ca.users_id is null and ca.asset_type = 'currency'
                 and ca.symbol = acc.currency and fx.source = 'fx_feed'
                 and fx.price_date <= p_as_of
               order by fx.price_date desc limit 1), 1.0) end   as v
    from pfin.account acc
    left join pfin.fn_account_cash_as_of(p_as_of) c
      on c.account_id = acc.account_id
    left join pfin.asset cur
      on cur.users_id is null
     and cur.asset_type = 'currency'
     and cur.symbol = acc.currency
    left join pfin.user_asset_category uac on uac.asset_id = cur.asset_id
    left join pfin.user_taxonomy ut
      on ut.id = uac.sub_cat_id
    -- LIABILITY ROUTE TARGET, matched by NAME because there is no id to follow:
    -- no junction row points at it, and pfin.account.sub_cat_id was dropped at
    -- 048. At most one row can match — 084's unique (users_id, cat,
    -- sub_cat) — so this cannot multiply rows. LEFT JOIN, never INNER: a caller
    -- missing the 080 row gets NULL keys and the value lands in the R2
    -- unclassified row with its value intact.
    -- ⚠ THE users_id CONJUNCT IS LOAD-BEARING, NOT DECORATIVE — do not strike it
    -- for consistency with the `ut` joins above. Those key on `ut.id =
    -- uac.sub_cat_id`, a TENANT-BOUND surrogate: if RLS ever admitted a foreign
    -- row, a foreign id cannot match the caller's own ids, so they fail CLOSED.
    -- This join keys on `cat`/`sub_cat` STRING LABELS, which are SHARED
    -- VOCABULARY — every tenant's row reads 'Liabilities'/'Liability Balances' —
    -- so without `lut.users_id = acc.users_id` it fails OPEN: a leaked foreign
    -- row would match by name and attach a foreign sub_cat_id to this caller's
    -- liability cash. The conjunct is redundant against a CORRECTLY FUNCTIONING
    -- RLS and is the SOLE tenant discriminator against an RLS regression. That
    -- asymmetry is why this join carries one and its id-keyed siblings do not.
    left join pfin.user_taxonomy lut
      on lut.users_id = acc.users_id
     and lut.cat      = 'Liabilities'
     and lut.sub_cat  = 'Liability Balances'
    where (acc.closed_at is null or acc.closed_at::date > p_as_of)
      -- ZERO-CASH ACCOUNTS EMIT NO ROW. fn_account_cash_as_of is TOTAL over
      -- pfin.account, so without this every open account would contribute a
      -- 0-valued row. Harmless when summed to a scalar (fn_compute_nav), NOT
      -- harmless here: those rows group under the NULL key and manufacture a
      -- phantom UNCLASSIFIED row of 0.00 for any caller who has an account and
      -- nothing unclassified — which SELF-238 would render as an "Unsorted"
      -- line for essentially every user. Measured on the scratch chain before
      -- this filter existed. It also restores the contract's empty-portfolio
      -- promise (empty set, not a row of zeros).
      and coalesce(c.balance_native, 0) <> 0
  ),
  both_legs as (
    select k_id, k_cat, k_sub_cat, v from sec_leg
    union all
    select k_id, k_cat, k_sub_cat, v from cash_leg
  )
  select
    b.k_id                     as sub_cat_id,
    b.k_cat                    as cat,
    b.k_sub_cat                as sub_cat,
    coalesce(sum(b.v), 0)      as market_value
  from both_legs b
  -- REAL-ESTATE EXCLUSION (AC3): `is distinct from` rather than `<>` so the
  -- UNCLASSIFIED group (k_cat IS NULL) survives — an unknown cat cannot be known
  -- to be Real Estate, and dropping it here would re-open the R2 money leak
  -- through the back door.
  where p_include_real_estate or b.k_cat is distinct from 'Real Estate'
  group by b.k_id, b.k_cat, b.k_sub_cat
$$;

-- ----------------------------------------------------------------------------
-- 7b — pfin.fn_planning_target_matched_sub_cat (074), ADR-011 Decision 3 canonical
-- instance #17. The SECOND PREDICATE goes; the instance does not.
--
-- 074 carried matched-tenant AND matched-domain in one fence, on the #14
-- one-fence-two-predicates precedent, because planning_target has no second side
-- to narrow the referenced row. After the split it HAS one: table identity. A
-- prototype is not in pfin.user_taxonomy at all, so the fence's resolving read
-- finds nothing and the write lands on LEG 1 (unresolvable).
--
-- >> LEG 3's COVERAGE DOES NOT DISAPPEAR — IT MOVES TO LEG 1. << That is why the
-- paired battery's (L3)/(L3u) legs RE-TARGET rather than being deleted: tenant A
-- submits A's OWN posting_prototype id, on INSERT and on UPDATE, and both must
-- still RAISE — the message assertion moving to the leg-1 text. Deleting those two
-- legs is the tempting repair (they stop compiling the moment `domain` leaves the
-- fixture) and it would silently remove the watcher for the very property this
-- split is claimed to strengthen. Sec's routed item (ii) ruling.
--
-- The v_domain local and its select target are removed ENTIRELY. An
-- assigned-but-never-read local is a dropped output column in disguise.
--
-- ⚠ The comment and the header enumeration go from three raise legs to two, and
-- plan() moves with them. A `comment on function` left asserting a leg that can no
-- longer fire is exactly the class of stale catalog text this project has already
-- had to correct once.

create or replace function pfin.fn_planning_target_matched_sub_cat()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_users_id  uuid;
begin
  -- NULL-SAFE FAIL-CLOSED: resolve first, then test. Never
  -- `(subquery) <> new.users_id` — that yields NULL on a missing row, the IF is
  -- skipped, and the write leaks through.
  select t.users_id
    into v_users_id
    from pfin.user_taxonomy t
   where t.id = new.sub_cat_id;

  if not found then
    raise exception
      'planning target rejected: sub_cat_id % does not resolve to a taxonomy row readable by users_id % (ADR-011 Decision 3 canonical instance #17 / matched-tenant fence, leg 1 unresolvable)',
      new.sub_cat_id, new.users_id;
  end if;

  if v_users_id is distinct from new.users_id then
    raise exception
      'cross-tenant planning target rejected: sub_cat_id % is owned by another tenant, not by users_id % (ADR-011 Decision 3 canonical instance #17 / matched-tenant fence, leg 2 cross-tenant)',
      new.sub_cat_id, new.users_id;
  end if;

  return new;
end;
$$;

revoke execute on function pfin.fn_planning_target_matched_sub_cat() from public;

comment on function pfin.fn_planning_target_matched_sub_cat() is
  'BEFORE INSERT OR UPDATE matched-tenant fence on pfin.planning_target.sub_cat_id '
  '(ADR-011 Decision 3 canonical instance #17; 012 Pattern 1, local anchor; '
  'SELF-324). Rejects a %Target that points at a Sub-Cat which does not resolve, or '
  'at one owned by another tenant. TWO distinct raise legs — (1) unresolvable, (2) '
  'cross-tenant — because the diagnostics differ AND because the legs have '
  'different reachability. The cross-tenant leg is reachable BY A PLAIN '
  'authenticated CALLER via an OWNERSHIP FORGE (their OWN real sub_cat_id submitted '
  'with a foreign users_id: the row resolves, the forged users_id does not match, '
  'and this raises BEFORE RLS''s WITH CHECK is reached — the shape 022''s fence '
  'already exercises for canonical #8, this instance''s structural twin), AND '
  'ADDITIONALLY by an RLS-EXEMPT writer (migration role, superuser, any future '
  'service_role path). Naming another tenant''s Sub-Cat instead lands on the '
  'unresolvable leg, because RLS hides that row from the INVOKER read. NULL-safe '
  'fail-closed: the referenced row is resolved into a local and tested, never '
  'compared inside a subquery expression that returns NULL on a miss. SECURITY '
  'INVOKER + set search_path=''''. AMENDED at 084 (ADR-058 Decisions 1 + 5): this '
  'fence carried a SECOND predicate through 083, restricting the referent to the '
  'storage half of what was then one table. That predicate is GONE because the '
  'referenced TABLE now expresses it — pfin.user_taxonomy holds storage '
  'classifications only, and a posting prototype lives in pfin.posting_prototype, '
  'so aiming a %Target at one lands on leg 1 rather than on a predicate. The '
  'retired leg''s COVERAGE did not disappear; it moved to leg 1, which is why the '
  'paired battery re-targets those cases instead of dropping them.';

-- ============================================================================
-- STEP 8 — retire `domain`. Everything that read it has been re-pointed above.
-- ============================================================================

-- 028's CHECK goes with the rows it constrained; its successor is
-- posting_prototype_class_chk, created in STEP 1. Its `comment on constraint` —
-- which carried two copied ledger figures — is dropped with it.
alter table pfin.user_taxonomy
  drop constraint if exists user_taxonomy_cashflow_class_chk;

-- ⚠ `drop column` also drops the unique constraint that contains it. The
-- replacement is re-created explicitly below — it is NOT preserved, and a
-- migration that assumed otherwise would leave the storage spine with no
-- uniqueness on (users_id, cat, sub_cat) and provisioning silently duplicating
-- rows on every visit.
alter table pfin.user_taxonomy   drop column domain;
alter table pfin.taxonomy_default drop column domain;

alter table pfin.user_taxonomy
  add constraint user_taxonomy_users_id_cat_sub_cat_key unique (users_id, cat, sub_cat);

alter table pfin.taxonomy_default
  add constraint taxonomy_default_cat_sub_cat_key unique (cat, sub_cat);

-- ----------------------------------------------------------------------------
-- THE OTHER HALF OF THE ID MECHANISM. See the header: a reserved offset alone does
-- not partition anything — two sequences with a gap between them are disjoint only
-- until the lower one advances into the upper one, which is exactly the
-- parallel-advance failure Sec F1 vetoed. This cap is what makes the ranges
-- disjoint BY DEFINITION rather than by distance.
--
-- >> SECURITY INVARIANT, NOT A CAPACITY LIMIT. << Raising or removing it re-opens
-- a silent audit-trail corruption: pfin.account_trans_annotation_history.sub_cat_id
-- is an FK-less snapshot, so an id that came to resolve in both tables would make
-- historical rows quietly report a classification they never had, with no
-- constraint firing and no test failing. If pfin.user_taxonomy ever genuinely
-- approaches this ceiling, the answer is a new partition scheme decided with Sec —
-- never a larger number written here.
alter table pfin.user_taxonomy
  alter column id set maxvalue 999999999;

-- ============================================================================
-- STEP 9 — re-emit every CATALOG comment this migration falsifies.
--
-- Scope rule, and it is Sec's routed item (iii) ruling generalized: a `comment on`
-- has a DATABASE representation and is read at \d+ by someone with no repo in
-- front of them, so it can only be corrected by issuing new SQL. A file-header
-- `--` block has no database representation and stays as authored — 022's, 023's
-- and 029's DOMAIN NOTE headers are historically true of those migrations and are
-- NOT edited here. Only the catalog text changes, and it changes by re-emission.
--
-- Each re-emission below also DROPS the copied ledger figures its predecessor
-- carried (a DEFINER-allowlist count, a §10 count), with the supersession named in
-- the text so a reader who remembers the old wording learns it changed rather than
-- doubting their memory. A catalog comment cannot carry a count it will not
-- maintain.
-- ============================================================================

-- The overlay table: its Decision-3 fence target moved, and two copied ledger
-- figures go with the re-emission.
comment on table pfin.account_trans_annotation is
  'Per-transaction MUTABLE annotation overlay (ADR-027 R-17 / §6A Rev 7; SELF-283). The '
  'user''s editable layer over the immutable account_trans ledger (004): sub_cat_id (the '
  '§2.3 expense category — a POSTING PROTOTYPE, in pfin.posting_prototype since 084) + '
  'note. PK = trans_id enforces the 1:1 (one annotation per transaction). Editing a '
  'category/note is an overlay UPDATE — it does NOT pollute the append-only ledger with '
  'reverse-and-replace rows. Full authenticated CRUD. RLS via the PARENT account_users '
  'FK-chain (trans_id → account_trans.account_id → account_users rd/wr_access-JOIN — the '
  '006/005 parent-chain shape) since the annotation carries NO own users_id. Carries ONE '
  'Decision-3 fence: sub_cat_id → posting_prototype = CANONICAL #10 (matched-tenant, '
  'chain-resolved per the §6A C-NOTE (a) recommendation — tenant resolved via the account '
  'chain, NOT a local users_id which this table lacks). trans_id is the sole anchor (NOT '
  'D3). Cross-vocabulary REFERENCE became STRUCTURAL at 084 (ADR-058 Decisions 1 + 5): the '
  'FK target IS the posting vocabulary, so what was an app-layer matched-DOMAIN rule (012 '
  'DOMAIN NOTE) is now enforced by table identity. Matched-TENANT stays DB-enforced by the '
  'fence — an FK is tenant-blind, which is ADR-011 Decision 3''s entire premise, so nothing '
  'about the re-target carries tenant matching forward. anon zero-grant; service_role '
  'ungranted (no service_role annotation writer in V1 — R-18 lazy). Neither the SECURITY '
  'DEFINER allowlist nor the §10 catalogued-instance ledger is changed by 084. SUPERSEDES '
  'the two figures this comment carried at 023 — read ADR-011 Decision 9 and Decision 4 '
  'live; a catalog comment cannot carry a count it will not maintain.';

comment on column pfin.account_trans_annotation.sub_cat_id is
  'FK → pfin.posting_prototype(id) ON DELETE RESTRICT, RE-TARGETED at 084 from '
  'pfin.user_taxonomy (ADR-058 Decisions 1 + 5) — the §2.3 expense category, i.e. the '
  'posting prototype this transaction is classified into. NULLABLE: NULL = Unsorted-pending '
  '(SELF-200; a txn lands uncategorized and the user assigns later). Decision-3 CANONICAL '
  '#10: matched-tenant fence (012 Pattern 1), but CHAIN-RESOLVED — the referenced '
  'posting_prototype row must share the annotation''s owning tenant, resolved via trans_id '
  '→ account_trans → account.users_id (this table has no local users_id; contrast 012/022 '
  'which match a local new.users_id). Fenced by fn_account_trans_annotation_matched_sub_cat '
  '(BEFORE INSERT OR UPDATE). §6A C-NOTE shape (a) [chain-resolved]. The label, the '
  'DDL-realized status and the CR fence pattern are RETAINED across the re-target — a '
  'change of target amends the instance entry, never its class or label. SUPERSEDES the '
  'clause this comment carried at 023, that matched-DOMAIN is app-layer in V1: after 084 a '
  'storage-classification row cannot be referenced here at all.';

-- Sec F9: 031 is a Decision-2 audit-class table, so a re-emitted comment here is
-- itself a joint-review surface. Both comments name the new resolution target and
-- the id-space invariant that makes the snapshots keep working.
comment on table pfin.account_trans_annotation_history is
  'Append-only, immutable reclassification-history over the 023 overlay''s GL-routing '
  'columns (sub_cat_id + metadata). M1-evt Slice A2 / SELF-293; ADR-011 Decision 2 '
  'audit-class. F/CTO REOPENED the ADR-031 Amendment 1 §9 V2-deferral to V1 (Sec Condition '
  'B satisfied by building the audit trail). Every routing-relevant 023 change (birth '
  'INSERT + each sub_cat_id/metadata edit) writes ONE full-snapshot version row '
  '(version_seq monotonic per trans_id). SOLE writer = the DEFINER helper '
  'fn_reclass_history_insert (authenticated has NO direct INSERT grant → history is '
  'un-forgeable). 004-mirror immutability triple-fence (UPDATE/DELETE/TRUNCATE blocked all '
  'roles). Owner-only read (parent-chain α: trans_id → account_trans → account_users '
  'rd_access). NO own users_id (tenancy via the chain). sub_cat_id is a plain-bigint '
  'SNAPSHOT (no FK — audit-truthful if the referenced row is later deleted; Decision-3 +0). '
  'Its resolution target is pfin.posting_prototype since 084: the GL split moved the '
  'posting vocabulary out of pfin.user_taxonomy and PRESERVED EVERY ID IT MOVED, precisely '
  'so these snapshots keep resolving to the row they recorded. Because there is no FK, '
  'nothing followed that split and nothing would have objected to a re-key — the ids were '
  'preserved by requirement, not by constraint. The two tables'' identity ranges are '
  'disjoint by construction, so a snapshot id resolves in at most one of them; it does NOT '
  'tell you which one without a lookup, and a reader built on the stronger reading is wrong '
  'for exactly the historical rows this table exists to serve. Lot-match column = add-later '
  '(Slice B). This helper was the authored 4th SECURITY DEFINER entry and the '
  'general-audit-log slot stays reserved. SUPERSEDES the two ledger figures this comment '
  'carried at 031 — read ADR-011 Decision 9 and Decision 4 live rather than a copied count. '
  'anon zero-grant; service_role ungranted.';

comment on column pfin.account_trans_annotation_history.sub_cat_id is
  'SNAPSHOT of the routing class (023.sub_cat_id) at this version. PLAIN BIGINT — NO FK, by '
  'design: an audit snapshot records the value-as-of-then and must stay valid even if the '
  'referenced row is later deleted. Its resolution target is pfin.posting_prototype since '
  '084, and the GL split preserved every id it moved, so a snapshot taken before the split '
  'still resolves to the row it recorded. Not a Decision-3 reference.';

-- The split child's reference: same re-target, same label treatment.
comment on column pfin.account_trans_split.sub_cat_id is
  'FK → pfin.posting_prototype(id) ON DELETE RESTRICT, RE-TARGETED at 084 from '
  'pfin.user_taxonomy (ADR-058 Decisions 1 + 5) — this split line''s posting prototype. '
  'NULLABLE: NULL = Unsorted-pending line (→ Suspense downstream). Decision-3 '
  'matched-tenant fence, CHAIN-RESOLVED (012 Pattern 1 / 023 #10 shape) — the referenced '
  'posting_prototype row must share the split child''s owning tenant, resolved via '
  'account_trans_id → account_trans → account.users_id (this table has no local users_id). '
  'Fenced by fn_account_trans_split_matched_sub_cat (BEFORE INSERT OR UPDATE). Canonical '
  '#13, Sec-pinned at the M2.5 joint-review; the label, the DDL-realized status and the CR '
  'fence pattern are all RETAINED across the re-target, because a change of target amends '
  'the instance entry and never its class or label. SUPERSEDES the clause this comment '
  'carried at 029, that matched-DOMAIN is app-layer in V1: after 084 a '
  'storage-classification row cannot be referenced here at all.';

-- 022 / canonical #8: the asset side. Its FK TARGET DID NOT MOVE and its fence is
-- unchanged — only the catalog text, which names a domain column that no longer
-- exists. Not in ADR-058's consequence list; found by measuring the live catalog.
comment on table pfin.user_asset_category is
  'Per-user asset→Sub-Cat allocation junction (ADR-027 R-19 / Option J1; SELF-282). Solves '
  'the global-asset knot: a global asset (users_id NULL) cannot carry a per-user sub_cat '
  'column, so §2.2 asset-level allocation is per-(user, asset) via a junction row — uniform '
  'for global + per-user assets. MUTABLE, full authenticated CRUD, RLS direct-owner '
  '(users_id = auth.uid()). Carries TWO Decision-3 fences: sub_cat_id → user_taxonomy = '
  'CANONICAL #8 (matched-tenant, 012 Pattern 1); asset_id → pfin.asset = CANONICAL #9 '
  '(novel global-OR-matched-tenant, Pattern 2 site 2 — tenant resolved directly via '
  'new.users_id, no JOIN, contrast 017 which JOINs account). users_id is the sole anchor '
  '(NOT D3). unique(users_id, asset_id) = one categorization per user per asset. '
  'Matched-DOMAIN was app-layer in V1 (mirroring the 012 DOMAIN NOTE) and is STRUCTURAL '
  'since 084: pfin.user_taxonomy holds storage classifications ONLY, so the FK target '
  'itself is the rule and there is no domain column left to check. Matched-TENANT stays '
  'DB-enforced by the fence — an FK is tenant-blind. anon zero-grant; service_role '
  'ungranted (no service_role write path in V1). Neither the SECURITY DEFINER allowlist nor '
  'the §10 catalogued-instance ledger is changed by 084. SUPERSEDES the two figures this '
  'comment carried at 022 — read ADR-011 Decision 9 and Decision 4 live; a catalog comment '
  'cannot carry a count it will not maintain.';

comment on column pfin.user_asset_category.sub_cat_id is
  'FK → pfin.user_taxonomy(id) ON DELETE RESTRICT — the assigned storage-classification '
  'Sub-Cat. The target is UNCHANGED by 084: the GL split moved only the posting vocabulary '
  'out, which is why this instance needed no re-point at all. Decision-3 CANONICAL #8: '
  'matched-tenant fence (012 Pattern 1) — the referenced user_taxonomy row must share this '
  'row''s users_id. Fenced by fn_user_asset_category_matched_sub_cat (BEFORE INSERT OR '
  'UPDATE). SUPERSEDES the clause this comment carried at 022, that matched-DOMAIN is '
  'app-layer in V1 (012 DOMAIN NOTE): since 084 pfin.user_taxonomy holds storage '
  'classifications only, so the rule is enforced by table identity and the column it named '
  'is gone. ⚠ What did NOT become structural is vocabulary MEMBERSHIP on this side — 028''s '
  'class CHECK left with the posting rows, so the storage table constrains no cat at all.';

-- 022's fence: re-emitted for its TEXT only. The function body is untouched — it
-- carries no domain reference and its target did not move.
comment on function pfin.fn_user_asset_category_matched_sub_cat() is
  'BEFORE INSERT OR UPDATE matched-tenant fence on pfin.user_asset_category.sub_cat_id '
  '(ADR-011 Decision 3 canonical instance #8 / 012 Pattern 1; ADR-027 R-19; SELF-282). '
  'Rejects categorizing an asset with another tenant''s Sub-Cat: the referenced '
  'user_taxonomy row must share this row''s users_id. NULL-safe fail-closed (NOT EXISTS → '
  'raise). SECURITY INVOKER + set search_path = '''' — the read composes with RLS '
  '(user_taxonomy_select scopes to auth.uid() under authenticated, and 025 AND-s the aal2 '
  'step-up clause into it) and the explicit users_id equality makes it authoritative '
  'regardless. Covers UPDATE (re-categorization), not just INSERT (contrast 017 INSERT-only '
  'on the immutable ledger; matches 012 which covers UPDATE on mutable pfin.account). '
  'Trigger (not a bare CHECK) because it subqueries the referenced row — Decision 3 permits '
  'a trigger where PG cannot express the constraint declaratively. Not a DEFINER allowlist '
  'entry (INVOKER) — read ADR-011 Decision 9 live rather than the figure this comment '
  'carried at 022. THE FUNCTION ITSELF IS UNCHANGED BY 084: it never read the domain '
  'column, and its FK target did not move. SUPERSEDES only the clause stating that '
  'matched-DOMAIN (domain=''asset'') is app-layer in V1 (012 DOMAIN NOTE) — since 084 '
  'pfin.user_taxonomy holds storage classifications only, so that rule is enforced by table '
  'identity and the column it named no longer exists.';

-- 074 / canonical #17: the FK target did not move, but the fence lost its second
-- predicate, so the column comment must stop advertising it.
comment on column pfin.planning_target.sub_cat_id is
  'FK -> pfin.user_taxonomy(id) ON DELETE RESTRICT — the Sub-Cat this target applies to. '
  'ADR-011 Decision 3 CANONICAL #17: matched-tenant fence in the 012 Pattern-1 shape (local '
  'anchor; the referenced taxonomy row MUST share this row''s users_id), It ALSO carried a '
  'second, matched-DOMAIN predicate through 083; that predicate was REMOVED at 084 (ADR-058 '
  'Decisions 1 + 5) because the referenced table now expresses it — pfin.user_taxonomy '
  'holds storage classifications only, and a posting prototype lives in '
  'pfin.posting_prototype, so aiming a %Target at one no longer resolves at all. The '
  'retired predicate''s COVERAGE did not disappear: it moved to the fence''s unresolvable '
  'leg. Fenced by pfin.fn_planning_target_matched_sub_cat (BEFORE INSERT OR UPDATE). '
  'RESTRICT rather than CASCADE: a taxonomy row that a user has targeted MUST NOT be '
  'deletable out from under the target silently — the delete is refused and the orphaning '
  'surfaces. user_taxonomy carried no DELETE grant or policy when this column was authored, '
  'so RESTRICT constrained no existing path; 084 did not add one.';

comment on table pfin.planning_target is
  'Per-user, per-Sub-Cat allocation target (PRD §2.2.2 "% Target"; ADR-011 Decision 18 / '
  'Lock 14 settings store, first member realized; SELF-324, which absorbed SELF-232). ONE '
  'row per (users_id, sub_cat_id). UNSET IS REPRESENTED AS ROW ABSENT — never NULL, never a '
  'seeded zero; read paths coalesce a missing row to 0, and an explicit 0.00 is a storable '
  'and different fact (the user asserted a zero target). That is why DELETE is granted here '
  'and is not on user_settings: clearing a target must remove the row. Targets are '
  'user-authored and start empty — 041 seeds the taxonomy, nothing seeds this. '
  'UPSERT-in-place on the (users_id, sub_cat_id) unique key per Decision 18 (settings are '
  'not audit-class; no edit-history rows). MUTABLE, full authenticated CRUD, RLS '
  'direct-owner (users_id = auth.uid()) with the ADR-029 / 025 aal2 step-up clause on every '
  'policy. Carries ONE Decision-3 fence: sub_cat_id -> user_taxonomy = CANONICAL #17, '
  'matched-tenant. It carried a matched-DOMAIN predicate in the same fence through 083 (the '
  '#14 two-predicate precedent); 084 removed it, because after the GL split the referenced '
  'TABLE holds storage classifications only. A posting prototype can no more carry a '
  '%Target than another tenant''s Sub-Cat can — the first is now refused by the fence''s '
  'unresolvable leg rather than by a predicate. users_id is the sole anchor and is NOT a '
  'Decision-3 instance. Real-Estate exclusion is a §2.2.2 READ-LAYER rule over '
  'user-editable cat text and is deliberately not fenced here. anon zero-grant; '
  'service_role ungranted (the app writes as the user, under the user''s own JWT). No '
  'JSONB, per Decision 18''s forward-compat fence.';

-- 011's column comment: it describes the column by the domain of the rows that
-- carry it, and one of those domains has left the table.
comment on column pfin.user_taxonomy.tax_character is
  'Nullable tax-routing character (ADR-006 Axis 2). CHANGED at 011 (ADR-024, Option C): was '
  'inline `text CHECK (5 values)` (009); now `text` FK REFERENCES pfin.tax_character(code) '
  'ON DELETE RESTRICT — membership enforced by FK instead of CHECK (equivalent integrity + '
  'joinable). NULL stays valid (storage-classification rows are dormant-NULL; before 084 '
  'this table also held the posting vocabulary, and the GL split moved that half to '
  'pfin.posting_prototype, which carries a copy of this column and this FK). FK target is '
  'GLOBAL reference data → Decision 3 CLEARED (no tenant anchor on the global side, so '
  'there is no tenant to match). SUPERSEDES the family figure this comment carried at 011 — '
  'read ADR-011 Decision 3''s body live; the family grows, its labels are non-contiguous, '
  'and labeled versus DDL-realized diverge. Distinct from the pending SELF-201 sub_cat_id '
  'FK (per-user target → matched-tenant MANDATORY).';

-- The spine itself. Base text is 083's, which had already superseded 009's
-- write-dormancy clause; this re-emission supersedes the two-domain description.
comment on table pfin.user_taxonomy is
  'Per-user two-level Cat × Sub-Cat STORAGE-CLASSIFICATION spine (ADR-011 Decision 11 / '
  'Lock 7, Option A single-table; SELF-231, narrowed by ADR-058 Decision 1 at 084). It '
  'covers the §2.2.1 asset domain ONLY. 084 moved the §2.3.1 posting vocabulary out to '
  'pfin.posting_prototype and DROPPED the domain column, so the table now expresses what '
  'the column used to: an element is intrinsic to a storage class, whereas a posting '
  'prototype has no intrinsic element and its legs touch element-bearing accounts. Rows '
  'that moved kept their original ids, and this table''s identity is capped below the '
  'reserved range pfin.posting_prototype mints from, so no id resolves in more than one '
  'table. ⚠ 028''s accounting-class CHECK LEFT WITH THE POSTING ROWS: this table now '
  'constrains no cat at all, while authenticated holds INSERT — a user can still create a '
  'storage class named like an accounting class. That is not a regression (the asset half '
  'was unconstrained free text before the split) but it IS an asymmetry, and the '
  'instruments for closing it are a cat-set assertion and the element CHECK, never an '
  'appeal to table identity. Carries the ADR-006 Axis 2 tax_relevant boolean + '
  'tax_character enum (5 V1 values). V1 is SEED-ONLY (no taxonomy-CRUD UI; V2+ expansion) '
  'and V1-MUTATE-DORMANT: authenticated holds SELECT + INSERT. 041 added the INSERT grant '
  'and the user_taxonomy_insert policy (with check users_id = auth.uid(), carrying the 025 '
  'aal2 backstop clause) so a user can provision their own default taxonomy on first '
  'access. UPDATE and DELETE carry no grant and no policy, so they are default-denied at '
  'BOTH the ACL layer and the RLS layer; un-deferring them is the V2 taxonomy-CRUD-UI PR '
  'decision and needs its own review. SUPERSESSION: this comment previously read '
  '"V1-WRITE-DORMANT ... authenticated holds SELECT ONLY ... Write policies + write grants '
  'are DEFERRED to the V2 taxonomy-CRUD-UI PR" -- true when 009 shipped, falsified by 041 '
  'on the INSERT half, corrected here. anon zero-grant; service_role ungranted (the default '
  'set is seeded by the migration chain under the schema-owning role, not by service_role; '
  'the CLI reset subcommand named by the original wording is BANNED for all agents -- see '
  'docs/records/2026-08-14-db-reset-incident.md). This is the sub_cat_id FK target that 004 '
  'deferred — that future FK is a separate Decision-3 evaluation (referencing row users_id '
  'must match user_taxonomy.users_id), added with the FK, not here. Since 084 the referents '
  'that remain pointed here are the STORAGE-side ones: pfin.user_asset_category.sub_cat_id '
  '(canonical #8) and pfin.planning_target.sub_cat_id (canonical #17). The two posting-side '
  'referents (#10 at 023, #13 at 029) re-targeted to pfin.posting_prototype, keeping their '
  'labels, their DDL-realized status and their fence pattern. AC-vs-convention corrections: '
  'AC SERIAL→identity, AC INTEGER users_id→uuid (auth.users.id is uuid) — see 009 header.';

-- The default set splits the same way, and provisioning is why it has to.
comment on table pfin.taxonomy_default is
  'Global canonical default two-level Cat x Sub-Cat taxonomy (ADR-036 / SELF-311, B1+A1). '
  'The single committed source for default STORAGE-CLASSIFICATION provisioning — the §2.2.1 '
  'asset default set, ported verbatim at 041 from the pre-041 gitignored seed.sql (which '
  'now seeds the dev user FROM this table). 084 moved the §2.3.1 cashflow half to '
  'pfin.posting_prototype_default and dropped the domain column, so provisioning now copies '
  'from TWO default tables into two per-user tables; an existence guard that checks only '
  'one of them marks a half-provisioned user as done. Columns mirror pfin.user_taxonomy '
  'MINUS users_id, as they did before the split. GLOBAL SHARED-READ (RLS using(true), '
  'authenticated SELECT; anon zero; service_role none) — non-tenant reference data '
  '(category names + notes; no $-figures), so EXCLUDED from the 025 aal2 backstop per '
  'exclusion (i). NO users_id / NO FK — Decision 3 family UNCHANGED. Content is '
  'migration-authored; changing the default set later is a data migration, and such a '
  'change MUST decide separately whether it reaches already-provisioned users — never '
  'assume first-access provisioning delivers it. SUPERSEDES the row-count clause this '
  'comment carried at 041: the set grew at 077 and a catalog comment cannot carry a figure '
  'that a later migration invalidates — count the table.';

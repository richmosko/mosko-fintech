-- ============================================================================
-- Migration: pfin.tax_character — GLOBAL value-registry reference table +
-- user_taxonomy.tax_character CHECK→FK conversion (Option C hybrid).
-- Phase 6 Build Loop (SELF-231 follow-up / manual-entry cluster foundation).
-- F/CTO-ratified Option C 2026-07-04 (over A keep-CHECK / B full-metadata-table;
-- D native-enum rejected). See DECISIONS.md ADR-024 + temp working paper
-- temp/self-231-tax-character-shape-options.md.
--
-- WHAT THIS DOES: promotes the 009 inline `tax_character text CHECK (5 values)`
-- to a GLOBAL shared-read value-registry table `pfin.tax_character` (the value
-- string IS the natural-key PK — `code`), FK'd from `pfin.user_taxonomy`. This
-- is the Option C **value registry** shape: the table exists NOW for FK
-- integrity + a joinable value list + a committed non-personal home for
-- label/notes, while the **routing-metadata columns stay UNBUILT** — the §2.5.1
-- tax_character → §2.5.2 schedule routing remains **hardcoded (PRD flag g-1)**
-- in the (unbuilt) §2.5.3 engine. The data-driven routing columns are the
-- deferred **V2 (g-2)** additive `ALTER TABLE ADD COLUMN`; ADR-024 documents
-- that deferral. Mirrors the incumbent `pfin.tax_cat` global reference shape
-- (../pfin_dash/sql/schema/schema.sql — `RLS ... USING (true)` shared-read,
-- INSERTed seed in-schema) MINUS the incumbent's routing booleans
-- (tax_as_ordinary / tax_as_cap_gain / tax_as_sec_1246), which are the exact
-- V2 (g-2) metadata columns Option C defers.
--
-- ----------------------------------------------------------------------------
-- Numbering: 011 follows 010 (both ALTER pfin.user_taxonomy — 010 ADD COLUMN
-- notes, 011 swap the tax_character CHECK for an FK — DIFFERENT columns, no
-- conflict; 011 MUST land after 010). Depends on: 009 (user_taxonomy table +
-- its inline tax_character CHECK, which this migration drops) and 001
-- (pfin schema + pfin.fn_refresh_updated_at, reused for the updated_at trigger).
-- FORWARD-ONLY: 009 is merged to main → immutable; this migration does NOT
-- re-baseline it. The CHECK→FK swap is a clean ALTER with NO backfill precisely
-- because user_taxonomy carries zero data at migration time (seed runs at
-- `db reset`, post-migration) — that no-data property is why the conversion is
-- cheap NOW, not a license to edit 009.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — NO function authored with elevated privilege.
--   This migration creates no SECURITY DEFINER and no SECURITY INVOKER function.
--   It is CREATE TABLE + a committed reference-data seed + RLS policy + GRANT +
--   one updated_at trigger wired to the EXISTING pfin.fn_refresh_updated_at
--   (001, already DEFINER allowlist entry #1) + an ALTER on user_taxonomy
--   (drop CHECK, add FK). The SECURITY DEFINER allowlist is UNCHANGED at 3
--   (ADR-011 Decision 9): no new DEFINER entry, no Sec-DEFINER-review trigger.
--   `set search_path = ''` is N/A (a function-body guard; this migration defines
--   no function). The routing that a DEFINER/INVOKER helper might one day JOIN
--   against does NOT exist here — routing stays hardcoded (g-1) per Option C.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate
-- the catalogued numbered list). This migration introduces ZERO catalogued §10
-- instances; the ledger stays at 2 (RT-22 + RT-26 per ADR-011 Decision 4). A
-- global authenticated-tier shared-read reference table touches no
-- infrastructure-credential-presence surface (RT-22) and no service_role-key /
-- code-layer allowlist surface (RT-26).
--   (i)   Instance-numbering: unchanged (not touched) — RT-22, RT-26.
--   (ii)  Layer-attribution: unchanged — no infra-credential and no code-layer
--         service_role-key surface is touched; service_role is NOT granted here
--         (see GRANTS RATIONALE), so 008's DB-ACL posture is unchanged — and
--         that would be a DB-ACL change, NOT an RT-26 change, regardless.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family count +0
-- (stays 7). This migration adds ONE FK-shaped column reference:
--   pfin.user_taxonomy.tax_character (per-user row) → pfin.tax_character.code
--   (GLOBAL reference row).
--   RULING: CLEARED — NO matched-tenant obligation. Decision 3 fences
--   cross-*tenant* FK bypass (a user's row referencing ANOTHER tenant's row).
--   pfin.tax_character carries NO users_id / tenant anchor — it is global
--   shared reference data every tenant legitimately references. There is no
--   second tenant anchor to mismatch, so there is nothing to validate; a
--   matched-tenant WITH CHECK / trigger would be meaningless (no column to
--   match against). Family UNCHANGED at 7. Sec sign-off on this clearance is
--   requested (new FK-shaped column + new RLS posture — see EXPOSURE / C6).
--   NOT-THIS-FK: the pending SELF-201 `account.sub_cat_id → user_taxonomy(id)`
--   FK is a SEPARATE Decision-3 instance and IS matched-tenant-MANDATORY (both
--   sides per-user; family 7→8) — evaluated at THAT migration, not here. Two
--   different FKs, two different rulings; do not conflate.
--
-- ----------------------------------------------------------------------------
-- GRANTS / RLS RATIONALE — GLOBAL shared-read; authenticated SELECT only.
--   pfin.tax_character is GLOBAL reference data (canonical, non-personal): every
--   authenticated user reads the SAME 5 rows. RLS is ENABLED with a
--   `using (true)` SELECT policy for authenticated + `grant select` — the
--   shared-read shape (mirrors the incumbent pfin.tax_cat `USING (true)`
--   precedent). This is the **FIRST global `using (true)` shared-read table in
--   the greenfield pfin schema** — every pfin table 001–010 is users_id-scoped.
--   That posture precedent + the Decision-3 clearance are the two Sec
--   joint-review triggers for this migration (advisory; low veto-likelihood).
--   NO write grant / NO write policy: the 5 values are code-coupled canonical
--   reference data, bootstrap-seeded IN this migration; authenticated never
--   writes them in V1 (no taxonomy-CRUD UI; V2+ expansion adds enum values as a
--   CODE event — a new seed row in a new migration + the routing code — not a
--   user data event). Writes are default-denied at BOTH the ACL layer (no
--   grant) AND the RLS layer (no write policy).
--   anon: ZERO grant — by construction. The pfin schema ACL grants USAGE only
--   to authenticated (001/003); anon holds no USAGE on pfin and is denied at the
--   schema-usage layer before any table ACL is consulted (ADR-023 C2 outer
--   fence). This migration adds no anon grant.
--   service_role: NO grant. The seed runs at `db reset` under the admin/
--   superuser migration connection (which bypasses GRANTs), NOT under
--   service_role; there is no runtime service_role path to tax_character in V1.
--
-- ----------------------------------------------------------------------------
-- EXPOSURE / C6 RLS-COVERAGE NOTE (ADR-023 C6 standing obligation — pfin is in
-- [api] schemas, so this table is internet-facing the moment it is granted):
--   - RLS ENABLED on pfin.tax_character (below).
--   - POLICY PRESENT: tax_character_select only — `using (true)` (shared-read;
--     every authenticated tenant sees all 5 rows — this is INTENDED for global
--     reference data, NOT an isolation leak: there is no per-tenant data here).
--   - GRANT: authenticated SELECT only. anon ZERO-grant (schema-usage denial).
--   - The paired QA pgTAP battery for this table asserts SHARED-READ, not
--     isolation: (a) two distinct tenants each SELECT all 5 rows (same rows,
--     shared) PASS; (b) authenticated INSERT/UPDATE/DELETE on tax_character
--     fails closed at the GRANT layer (no write grant) + RLS layer (no write
--     policy); (c) FK integrity — a user_taxonomy row with a bogus
--     tax_character code fails closed (FK violation), a valid code (or NULL)
--     succeeds; (d) user_taxonomy's OWN users_id = auth.uid() RLS is unaffected
--     by the FK add (a tenant still reads only its own taxonomy rows). QA
--     authors the battery (Architect does not edit tests/); Sec sign-off gates
--     merge.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.tax_character — GLOBAL value-registry for the ADR-006 Axis-2
--   tax_character enumeration (5 V1 values). Value-list registry ONLY in V1
--   (Option C): FK integrity + joinable list + label/notes home. Routing stays
--   hardcoded (g-1); routing-metadata columns are the deferred V2 (g-2) add.
--     - code (text PK): the canonical value string; the natural key. IS the FK
--       target for pfin.user_taxonomy.tax_character.
--     - label (text NOT NULL): human display string.
--     - notes (text NULL): definitional note (describes the LOCKED PRD §2.5.2
--       Federal routing for human reference — this is DOCUMENTATION, not a
--       machine-consumed routing column; the engine does not read `notes`).
--     - display_order (int NULL) / created_at / updated_at: convention columns.
--   pfin.user_taxonomy.tax_character — CHANGED: was `text CHECK (5 values)`
--     (009); now `text` (nullable, unchanged type/nullability) with an FK
--     REFERENCES pfin.tax_character(code) ON DELETE RESTRICT. Membership is now
--     enforced by the FK instead of the inline CHECK (equivalent integrity;
--     plus joinability). NULL stays valid (asset-domain rows are dormant-NULL).
--   Seed compatibility: the gitignored user_taxonomy seed already writes the
--     same 5 code strings as tax_character literals — under the natural-key PK
--     they become valid FK references with ZERO seed rework (a deliberate
--     property of choosing `code text PK` over a surrogate id).
--   Security-load-bearing edges: the FK enforces value membership; the
--     `using (true)` shared-read policy is the first global-reference posture in
--     pfin (Sec-reviewed); no privilege, no per-tenant data, no §10 surface.
-- ============================================================================

create schema if not exists pfin;
grant usage on schema pfin to authenticated;

-- ----------------------------------------------------------------------------
-- pfin.tax_character — GLOBAL value-registry reference table (Option C).
-- Natural-key PK = the canonical value string. NO routing-metadata columns in
-- V1 (deferred to V2 g-2 per ADR-024). Mirrors incumbent pfin.tax_cat shape.
-- ----------------------------------------------------------------------------
create table if not exists pfin.tax_character (
  code           text primary key,
  label          text not null,
  notes          text,
  display_order  integer,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

comment on table pfin.tax_character is
  'GLOBAL value-registry for the ADR-006 Axis-2 tax_character enumeration (5 V1 '
  'values; SELF-231 / ADR-024, Option C). Shared reference data — every '
  'authenticated tenant reads the same rows (RLS using(true); the FIRST global '
  'shared-read table in greenfield pfin, mirrors incumbent pfin.tax_cat). V1 is '
  'a VALUE REGISTRY only: FK integrity + joinable list + label/notes home. '
  'Routing (§2.5.1 tax_character → §2.5.2 schedule) stays HARDCODED (PRD flag '
  'g-1) in the §2.5.3 engine; the data-driven routing-metadata columns are the '
  'deferred V2 (g-2) additive ALTER. Bootstrap-seeded in migration 011 '
  '(committed, non-personal canonical data); no authenticated write path in V1 '
  '(adding a value is a CODE event — new seed row + routing code — not a user '
  'data event). anon zero-grant (pfin schema-usage denial); service_role '
  'ungranted (seed runs under the admin migration connection). FK target for '
  'pfin.user_taxonomy.tax_character(code).';

comment on column pfin.tax_character.code is
  'Canonical tax_character value string; natural-key PK. FK target for '
  'pfin.user_taxonomy.tax_character. Chosen over a surrogate id so the existing '
  'user_taxonomy seed literals become valid FK references with zero rework.';
comment on column pfin.tax_character.notes is
  'Definitional note describing the LOCKED PRD §2.5.2 Federal routing for human '
  'reference. DOCUMENTATION only — the (unbuilt) §2.5.3 engine does NOT read '
  'this column; routing is hardcoded (g-1). The machine-consumed routing '
  'columns are the deferred V2 (g-2) addition (ADR-024).';

alter table pfin.tax_character enable row level security;

-- GLOBAL shared-read: every authenticated tenant reads all rows. NO write
-- policy (bootstrap-seeded canonical data; V2 adds values as a code event).
-- Mirrors incumbent pfin.tax_cat `USING (true)`; FIRST such posture in pfin.
create policy tax_character_select on pfin.tax_character
  for select to authenticated using (true);

-- ACL-before-RLS (PR #106 gotcha): the role needs a table-level GRANT even with
-- RLS on. SELECT only — no write grant (writes default-denied at ACL + RLS).
grant select on pfin.tax_character to authenticated;

-- updated_at auto-refresh via the existing DEFINER allowlist entry #1 (001).
-- Dormant in V1 (no write path); wired for V2 convention consistency. Adds NO
-- new DEFINER entry (allowlist stays 3).
create trigger tax_character_set_updated_at
  before update on pfin.tax_character
  for each row execute function pfin.fn_refresh_updated_at();

-- ----------------------------------------------------------------------------
-- Committed canonical seed — the 5 V1 tax_character values (ADR-006 Axis-2).
-- Non-personal reference data → lives in the committed migration (contrast the
-- gitignored user_taxonomy personal seed). Idempotent via ON CONFLICT. `notes`
-- describe the LOCKED PRD §2.5.2 Federal routing for human reference only.
-- ----------------------------------------------------------------------------
insert into pfin.tax_character (code, label, notes, display_order) values
  ('ordinary',
   'Ordinary income',
   'Taxed on the Federal ordinary-income bracket schedule (and CA ordinary). '
   'Default character for cash-flow income Sub-Cats without a more specific '
   'character.', 10),
  ('qualified_dividend',
   'Qualified dividend',
   'Routes to the Federal LT capital-gains bracket schedule (PRD §2.5.2, '
   'locked); California treats as ordinary income.', 20),
  ('tax_exempt_interest',
   'Tax-exempt interest',
   'Excluded from Federal computation (PRD §2.5.2, locked). California V1: '
   'excluded uniformly (in-state / out-of-state issuer differentiation is V2+).',
   30),
  ('long_term_capital_gain_eligible',
   'Long-term capital gain eligible',
   'Long-term realized capital-gain character; routes to the Federal LT CG '
   'schedule. Also carries V1 forward-compat purpose for V2+ Unrealized '
   'bracket-aware refinements (rejected ο-b / ο-c).', 40),
  ('short_term_only',
   'Short-term only',
   'Short-term realized gains; taxed at Federal ordinary rates. Forward-compat '
   'for V2+ Unrealized bracket-aware refinements.', 50)
on conflict (code) do nothing;

-- ----------------------------------------------------------------------------
-- Convert pfin.user_taxonomy.tax_character: drop the 009 inline CHECK, add the
-- FK. Column stays `text` + nullable (asset-domain rows are dormant-NULL). The
-- FK enforces membership (equivalent to the CHECK) AND adds joinability. Clean
-- ALTER — user_taxonomy has zero data at migration time, so no rows to validate
-- or backfill. ON DELETE RESTRICT mirrors the incumbent tax_cat FK (a referenced
-- code cannot be deleted out from under a user_taxonomy row).
-- The 009 inline column CHECK auto-names to `user_taxonomy_tax_character_check`;
-- drop IF EXISTS for idempotency / defensiveness.
-- ----------------------------------------------------------------------------
alter table pfin.user_taxonomy
  drop constraint if exists user_taxonomy_tax_character_check;

alter table pfin.user_taxonomy
  add constraint fk_user_taxonomy_tax_character
    foreign key (tax_character) references pfin.tax_character (code)
    on delete restrict;

comment on column pfin.user_taxonomy.tax_character is
  'Nullable tax-routing character (ADR-006 Axis 2). CHANGED at 011 (ADR-024, '
  'Option C): was inline `text CHECK (5 values)` (009); now `text` FK '
  'REFERENCES pfin.tax_character(code) ON DELETE RESTRICT — membership enforced '
  'by FK instead of CHECK (equivalent integrity + joinable). NULL stays valid '
  '(asset-domain rows dormant-NULL). FK target is GLOBAL reference data → '
  'Decision 3 CLEARED (no tenant anchor on the global side; family unchanged at '
  '7). Distinct from the pending SELF-201 sub_cat_id FK (per-user target → '
  'matched-tenant MANDATORY).';

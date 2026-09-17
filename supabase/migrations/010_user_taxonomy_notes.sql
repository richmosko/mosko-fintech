-- ============================================================================
-- Migration: pfin.user_taxonomy — add nullable `notes text` column
-- Phase 6 Build Loop (SELF-231 follow-up / manual-entry cluster foundation).
-- Restores the incumbent asset_cat/tax_cat/trans_cat `notes` definitional
-- content that 009 omitted. F/CTO-disposed 2026-07-03: restore via a standalone
-- 010 migration (over folding into SELF-201's later migration, over omitting).
--
-- WHY THIS COLUMN: the incumbent schema (../pfin_dash/sql/schema/schema.sql)
-- carried a `notes` column on pfin.asset_cat / tax_cat / trans_cat holding real
-- per-category definitional content (e.g. T-Bill = "Treasury Bill (less than
-- 1 year duration)"; US-05-Energy = "US (GICS) Energy Sector"). 009 built its
-- DDL from the ADR-006 Axis-2 column list, which never named `notes` — so the
-- column was dropped by oversight, not by decision. The gitignored-local seed
-- (supabase/seed.sql, F/CTO's personal taxonomy; not committed) writes `notes`,
-- so it fails to apply until this column exists. This migration unblocks it.
--
-- Numbering: 010 follows 009 (pfin.user_taxonomy base table). Depends ONLY on
-- 009's table existing (ALTER TABLE ... ADD COLUMN IF NOT EXISTS). No other
-- migration depends on 010 landing first; a purely additive, nullable column.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — NO function authored (no elevated privilege surface).
--   This migration authors NO function — no SECURITY DEFINER and no SECURITY
--   INVOKER. It is a single additive ALTER TABLE + a column comment. The
--   SECURITY DEFINER allowlist is UNCHANGED at 3 (ADR-011 Decision 9): no new
--   DEFINER entry, no Sec-DEFINER-review trigger. `set search_path = ''` is N/A
--   (that guard is a function-body concern; this migration defines no function).
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate
-- the catalogued numbered list). This migration introduces ZERO catalogued §10
-- instances; the ledger stays at 2 (RT-22 + RT-26 per ADR-011 Decision 4). A
-- nullable free-text column touches no infrastructure-credential-presence
-- surface (RT-22) and no service_role-key / code-layer allowlist surface
-- (RT-26).
--   (i)   Instance-numbering: unchanged (not touched) — RT-22, RT-26.
--   (ii)  Layer-attribution: unchanged — no infra-credential and no code-layer
--         allowlist surface is touched; this is an authenticated-tier column add.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated.
--
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family count +0 (flat).
--   `notes` is a plain nullable `text` column. It is NOT an FK-shaped reference:
--   no FOREIGN KEY, no INTEGER[]/array element, no cross-table or self reference.
--   It carries no tenant anchor and no matched-tenant obligation. The Decision 3
--   family count is UNCHANGED.
--
-- GRANTS / RLS RATIONALE — no change required.
--   A new column inherits the table's existing ACL and RLS posture. 009 already
--   grants `select on pfin.user_taxonomy to authenticated` and defines the
--   `user_taxonomy_select` policy (`using (users_id = auth.uid())`). The new
--   column is covered by that SELECT grant + SELECT policy automatically — a
--   tenant reads `notes` for its own rows and nothing else. No new grant, no new
--   policy. V1-write-dormancy is unchanged: authenticated holds SELECT only;
--   writes remain default-denied at BOTH the ACL layer (no write grant) and the
--   RLS layer (no write policy). anon: unchanged zero-grant (pfin schema-usage
--   denial). service_role: unchanged (ungranted; seed runs under the admin
--   migration connection at db reset, which bypasses GRANTs). This migration
--   adds no grant of any kind.
--
-- EXPOSURE / C6 NOTE (ADR-023 C6 standing obligation): no new exposure surface.
--   No new table and no new policy — the existing two-layer fence (anon zero
--   pfin grant outer; RLS users_id = auth.uid() inner) already covers this
--   column. The QA pairing is a lightweight extension of the existing 009
--   two-tenant battery, not a new battery (see QA PAIRING below).
--
-- CONTRACT
--   pfin.user_taxonomy.notes  text  NULL  (no default)
--     - Optional per-row category definitional note (free text). Seeded from the
--       incumbent asset_cat/tax_cat/trans_cat `notes` content (gitignored-local
--       seed). NULL = no note supplied for that taxonomy row.
--   Security-load-bearing edges: NONE new — the column is fenced by the existing
--     user_taxonomy_select RLS policy (users_id = auth.uid()) and the table
--     SELECT grant; it introduces no reference, no privilege, no write path.
-- ============================================================================

-- Idempotent additive column: nullable, no default (notes are optional).
-- ----------------------------------------------------------------------------
-- ⚠ PFIN-LANE OWNERSHIP PAIR — opener. ADR-072 Amendment 5 (Decisions F1, G3).
-- DO NOT SPLIT, REORDER OR CONVERT THIS PAIR. Every object this file creates
-- must be owned by pfin_owner, whichever identity applies the file.
--   · The transaction-scoped variant of this statement is FORBIDDEN here and is
--     a CI-fence RED: measured, the Supabase CLI runs a migration file OUTSIDE a
--     transaction, so that variant warns 25P01 and does NOTHING. It is the shape
--     that looks correct and silently no-ops. The tokens are deliberately NOT
--     spelled out in this comment, so a fence counting them over source stays
--     exact — read the statement itself, below.
--   · The closing statement at the foot of this file is LOAD-BEARING, not
--     tidiness: the CLI writes its ledger row on this same session immediately
--     after the file, and pfin_owner cannot write supabase_migrations — without
--     the close, the push FAILS on the ledger INSERT.
--   · Fail-closed backstop: migrator holds no CREATE on schema pfin, so a file
--     that loses this pair errors 42501 rather than quietly creating a
--     migrator-owned object. The backstop is the control; the pair is the path.
-- ----------------------------------------------------------------------------
set role pfin_owner;
alter table pfin.user_taxonomy
  add column if not exists notes text;

comment on column pfin.user_taxonomy.notes is
  'Optional per-row category definitional note (free text; nullable, no default). '
  'Restores the incumbent asset_cat/tax_cat/trans_cat `notes` content that 009 '
  'omitted (built from the ADR-006 Axis-2 column list, which never named notes); '
  'F/CTO-disposed 2026-07-03 as a standalone additive 010 migration. Populated by '
  'the gitignored-local seed (supabase/seed.sql). Inherits the table SELECT grant '
  '+ user_taxonomy_select RLS policy (users_id = auth.uid()); no new grant/policy. '
  'Not an FK-shaped column (Decision 3 family unchanged); no §10 surface (ledger '
  'stays at 2).';

-- ----------------------------------------------------------------------------
-- ⚠ PFIN-LANE OWNERSHIP PAIR — closer. ADR-072 Amendment 5 (Decisions F1, G3).
-- This statement is SESSION-scoped and there is no transaction to roll it back,
-- so it MUST be the last statement in the file: the CLI's ledger INSERT runs
-- next, on this session, and must run as migrator. NOTHING MAY FOLLOW IT.
-- ----------------------------------------------------------------------------
reset role;

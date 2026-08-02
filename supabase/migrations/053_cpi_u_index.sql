-- ============================================================================
-- Migration: pfin.cpi_u_index — CPI-U (BLS series CUUR0000SA0) reference store.
--   Global public macro reference data (NOT tenant-owned): one row per calendar
--   month = the CPI-U index level for that period. Feeds §2.1.x real/inflation-
--   adjusted views + the SELF-214 net-worth-trend surface. Ingested by the
--   pfin_back_etl BLS module (workers/etl/) via service_role.
--   Linear SELF-230 (V1.1 Platform substrate). F/CTO-ratified 2026-08-02 (design
--   package temp/self214-230-design-package.md; batch confirm: mutable/no-
--   immutability-trigger, minimal/global audit, numbering 053, uuid-nav_daily
--   deferred to 054). apply-migration procedure applied. Sec-ADVISORY only
--   (ADR-011 Decision 12 — public read-only data; NO SD-matrix expansion).
--
-- ----------------------------------------------------------------------------
-- Numbering: 053 follows 052 (self227 audit-trace comments). SELF-230 is
--   sequenced FIRST (before SELF-214 nav_daily @ 054): cpi_u_index is a clean
--   GLOBAL table reusing the proven incumbent BLS CPI fetch logic, written under
--   TenantBoundConnection.system() (no per-tenant activation), with zero SD/RT/
--   §10/Decision-3/DEFINER deltas — it validates the migration→apply→worker loop
--   at low risk before the heavier nav_daily loop. Depends on: 001 (pfin schema).
--   No downstream migration depends on 053. Standalone base table.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — NO functions authored; NO SECURITY DEFINER; NO INVOKER
--   helper. This is a pure base-table migration (table + finiteness CHECK + RLS + GRANT).
--   The SECURITY DEFINER allowlist STAYS 4 (ADR-011 Decision 9 — authored 3:
--   fn_refresh_updated_at @001 + fn_grant_creator_access @003 +
--   fn_reclass_history_insert @031; + 1 reserved audit-log helper). Deliberately
--   NO updated_at trigger: AC pins the 4-column set (no updated_at column), and a
--   fn_refresh_updated_at trigger would add nothing here — the worker stamps
--   ingested_at on each upsert.
--
-- ----------------------------------------------------------------------------
-- MUTABLE — NO append-only/immutability trigger (deliberate; F/CTO-ratified).
--   Unlike the audit-class ledgers (account_trans @004 / linked_source_sync_audit),
--   CPI-U is CORRECTED reference data: BLS revises published index prints, so the
--   worker UPSERTs on cpi_period (INSERT new months + UPDATE revised values). This
--   is the eod_price/019 global-reference posture (MUTABLE OWD-E), NOT the Lock 10
--   mod #8 append-only posture. service_role holds INSERT + UPDATE (no DELETE —
--   least privilege; a revision is an UPDATE, never a delete).
--
-- ----------------------------------------------------------------------------
-- aal2 STEP-UP BACKSTOP (C3 / ADR-029 / 025) — EXCLUDED, reason (i) GLOBAL
--   SHARED-READ. cpi_u_index is public macro reference read by every authenticated
--   user via `using (true)` — it is NOT a sensitive tenant-owned pfin table, so the
--   per-user-conditional aal2 clause does NOT apply (same class as tax_character).
--   Stated here per the 025 in-header convention.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate
--   the catalogued numbered list. Decision 4 read verbatim before drafting.) ZERO
--   catalogued §10 instances; the ledger STAYS at 3 (RT-22 + RT-26 + RT-27).
--   (i)   Instance-numbering: RT-22 first, RT-26 second, RT-27 third — untouched.
--   (ii)  Layer-attribution: the cpi_u_index service_role SELECT+INSERT+UPDATE
--         grant is a DB-LAYER ACL — NOT the RT-26 code-layer
--         SUPABASE_SERVICE_ROLE_KEY allowlist grep fence, NOT the RT-22 PDF-worker
--         container credential audit, NOT the RT-27 app→worker admission network/
--         config surface. Identical reasoning to eod_price/019's service_role
--         global-writer grant. The ETL writer (system-mode TBC) is an already-
--         sanctioned service_role code consumer — adds NO new RT-26 file.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated. 053 is not
--         the anchor.
--   DE-CONFLATION GUARD: no FK-shaped column, no credential-presence surface, no
--   admission endpoint — none is a §10 catalogued instance.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — family UNCHANGED (+0). cpi_u_index
--   is GLOBAL reference data: NO users_id column, NO FK-shaped reference column
--   (cpi_period DATE PK / cpi_value NUMERIC / source TEXT / ingested_at TIMESTAMPTZ
--   — none references another pfin row; no self-FK; no INTEGER[] array). There is
--   no tenant anchor and nothing to matched-tenant-validate. Same "global shared
--   reference, not a family member" class as tax_character.
--
-- ----------------------------------------------------------------------------
-- LEDGER DELTAS (confirmed FLAT): §10 catalogued instances = 3 (unchanged) ·
--   SECURITY DEFINER allowlist = 4 (unchanged; no functions) · Decision-3 family =
--   unchanged (no FK column / no users_id) · SD matrix = NO expansion (public data,
--   ADR-011 Decision 12 advisory). Sec review = ADVISORY.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.cpi_u_index — global public CPI-U (BLS CUUR0000SA0) monthly index store.
--     Columns: cpi_period DATE PK (first-of-month), cpi_value NUMERIC (finiteness-
--     fenced: NaN + ±Infinity), source TEXT DEFAULT 'BLS_CUUR0000SA0', ingested_at
--     TIMESTAMPTZ DEFAULT NOW().
--     MUTABLE (service_role upsert on cpi_period; BLS revisions). RLS: SELECT to
--     authenticated `using (true)` (public reference); INSERT/UPDATE/DELETE
--     default-deny at authenticated (no policy) → writes are service_role-only via
--     DB-ACL grant.
--   Security-load-bearing edges: NO tenant isolation surface (global public data);
--     the finiteness CHECK (NaN + ±Infinity) is role-agnostic (service_role bypasses
--     RLS but NOT CHECK) and
--     keeps a poisoned index level out of downstream real/inflation-adjusted SUMs;
--     authenticated cannot write (no INSERT/UPDATE/DELETE policy) so a user cannot
--     forge a CPI print; EXECUTE/DML grants are least-privilege (no authenticated
--     write, no service_role DELETE).
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- pfin.cpi_u_index — global public CPI-U reference store (MUTABLE; eod_price/019
-- global-reference posture). PK = cpi_period (one row per month; the upsert key).
-- ----------------------------------------------------------------------------
create table if not exists pfin.cpi_u_index (
  cpi_period   date        not null primary key,                    -- first-of-month for the CPI-U print
  cpi_value    numeric     not null,                                -- CPI-U index level (finiteness-fenced)
  source       text        not null default 'BLS_CUUR0000SA0',      -- BLS series id provenance
  ingested_at  timestamptz not null default now(),                  -- worker stamps on each upsert
  constraint cpi_u_index_value_finite
    check (cpi_value <> 'NaN'::numeric
       and cpi_value <> 'Infinity'::numeric
       and cpi_value <> '-Infinity'::numeric)  -- 014 finiteness idiom (NaN + ±Infinity)
);

comment on table pfin.cpi_u_index is
  'Global public CPI-U reference store (BLS series CUUR0000SA0; SELF-230). One row '
  '= the CPI-U index level for a calendar month (cpi_period = first-of-month). NOT '
  'tenant-owned — public macro reference read by all authenticated users (RLS '
  'SELECT using(true)); NO users_id, NO FK-shaped column → NOT a Decision-3 family '
  'member (same class as tax_character). MUTABLE (eod_price/019 global-reference '
  'posture, NOT the Lock 10 append-only audit-class posture): BLS revises published '
  'prints, so the pfin_back_etl BLS module UPSERTs on cpi_period (INSERT new months '
  '+ UPDATE revised values) under service_role via TenantBoundConnection.system() '
  '(global write, no tenant). Write-authz: service_role holds INSERT + UPDATE (no '
  'DELETE — least privilege); authenticated holds SELECT only (cannot forge a CPI '
  'print — no write policy). Historical backfill Dec-2015 -> current is a one-shot '
  'idempotent worker run (SELF-230 AC4). aal2 step-up backstop EXCLUDED (reason (i) '
  'global shared-read). Sec-ADVISORY (ADR-011 Decision 12, public read-only data; '
  'NO SD-matrix expansion). §10 ledger stays 3; DEFINER allowlist stays 4.';

comment on column pfin.cpi_u_index.cpi_period is
  'PRIMARY KEY = the calendar month of the CPI-U print, normalized to first-of-month '
  '(DATE). Also the UPSERT key for the worker (INSERT new / UPDATE revised). One row '
  'per month.';
comment on column pfin.cpi_u_index.cpi_value is
  'The CPI-U index level for cpi_period (numeric, unrounded — BLS publishes to 3 '
  'decimals but the raw value is stored as-provided). Finiteness-fenced '
  '(cpi_u_index_value_finite: NaN AND ±Infinity rejected) — any of the three would '
  'poison downstream real/inflation-adjusted SUMs. Revisable (BLS restates prints) → '
  'the table is MUTABLE.';
comment on column pfin.cpi_u_index.source is
  'BLS series-id provenance (DEFAULT ''BLS_CUUR0000SA0'' = CPI-U, all urban '
  'consumers, US city average, all items, not seasonally adjusted). A column (not a '
  'constant) so a future series (e.g. seasonally-adjusted CUUS...) can coexist '
  'without a schema change.';
comment on column pfin.cpi_u_index.ingested_at is
  'Wall-clock of the worker upsert that last wrote this row (DEFAULT now()). Stamped '
  'by the ETL on both INSERT and revision-UPDATE. Ingest-provenance, NOT the CPI '
  'observation date (that is cpi_period).';

comment on constraint cpi_u_index_value_finite on pfin.cpi_u_index is
  'Rejects the numeric special values NaN AND +Infinity AND -Infinity on cpi_value — '
  'a true finiteness guard (014-pattern DB-layer defense-in-depth). CORRECTION '
  '(SELF-230 N1 / Sec-flagged): unbounded `numeric` does NOT reject +/-Infinity — '
  'PostgreSQL numeric admits ''Infinity'' / ''-Infinity'' — so the CHECK bars all '
  'three special values EXPLICITLY (an earlier comment overstated coverage). Any of '
  'the three would poison downstream real/inflation-adjusted SUMs exactly as NaN '
  'would. Role-agnostic table CHECK (service_role bypasses RLS but NOT CHECK); NOT '
  'NULL column, so no NULL-passes gap. Belt-and-suspenders with the worker''s '
  'is_finite() filter (app-layer) — this DB CHECK is the authoritative fence.';

-- ----------------------------------------------------------------------------
-- RLS — public reference read; service_role-only write.
-- grant-before-RLS shape (PR #106): the table ACL is checked BEFORE RLS, so the
-- authenticated SELECT grant is required even with RLS enabled (RLS filters rows;
-- the GRANT lets the role reach the table at all). authenticated gets SELECT only
-- (no write grant → cannot INSERT/UPDATE/DELETE regardless of policy). service_role
-- gets SELECT + INSERT + UPDATE (upsert; no DELETE — least privilege) and bypasses
-- RLS. anon: nothing (schema USAGE denies before ACL).
-- ----------------------------------------------------------------------------
alter table pfin.cpi_u_index enable row level security;

create policy cpi_u_index_select on pfin.cpi_u_index
  for select to authenticated
  using (true);

comment on policy cpi_u_index_select on pfin.cpi_u_index is
  'SELECT: every authenticated user reads every CPI-U row — public macro reference '
  'data (using(true), the global shared-read class, same as tax_character). NO tenant '
  'predicate (there is no users_id). This is the ONLY authenticated policy: INSERT / '
  'UPDATE / DELETE have no policy → default-deny for authenticated, so a user cannot '
  'write a CPI print. service_role writes bypass RLS. aal2 backstop excluded (global '
  'shared-read) — no per-user-conditional clause.';

grant select on pfin.cpi_u_index to authenticated;
grant select, insert, update on pfin.cpi_u_index to service_role;

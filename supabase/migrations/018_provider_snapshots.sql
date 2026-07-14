-- ============================================================================
-- Migration: pfin provider snapshot write-paths — (A) holdings_checkpoint (005)
--            provider-write-path activation + latest-snapshot view; (B) NEW
--            pfin.account_balance_checkpoint (the §7 cash analog).
-- Phase 6 Build Loop (ADR-027 ingest/valuation substrate, migration 018 of 015–021;
--   design CLOSED + Sec-cleared 2026-07-14: temp/015-architect-design-spec.md PART B
--   (the 018 row: BOTH provider snapshot write-paths) + PART C (the NOT-D3 sole-anchor
--   exclusions) + PART D.3 item 8 (merge-block #8 detail) + temp/015-ingest-substrate-
--   design.md §16 SEC CASH-DELTA-PASS (merge-block #8) + GRAIN/CASH RESOLVED (§7 dual-
--   path). JOINT-REVIEW-MANDATORY — the new pfin.account_balance_checkpoint is a new
--   service_role write path (Sec merge-block #8) + both latest views are merge-block #2.
--
-- WHAT THIS DOES (both provider snapshot landing paths for D-3 = B "aggregator/
--   incomplete → snapshot" per the §7 dual-path):
--   (A) ACTIVATES the 005 pfin.holdings_checkpoint provider write-path:
--       - RELAX symbol NOT NULL → nullable (provider positions / money-market /
--         blank-symbol sweep can lack a symbol — SELF-200 blank-symbol line).
--       - service_role SELECT+INSERT grant (append-only writer; UPDATE/DELETE/TRUNCATE
--         stay trigger-blocked for ALL roles — 005's immutability triple-fence holds).
--       - a latest-snapshot view (security_invoker = true) — per-(account, symbol)
--         latest-by-as_of_date row, RLS-inherited from the caller (merge-block #2).
--       - security_id FK STAYS DEFERRED to V1.3 (PART B): V1 keeps the symbol-only shape.
--   (B) CREATES pfin.account_balance_checkpoint — the cash analog of holdings_checkpoint
--       (§7 GRAIN/CASH RESOLVED): provider-reported cash balances land here when an
--       account is aggregator-sourced/incomplete (complete/backfilled accounts derive
--       cash as Σ(account_trans.amount) instead — 019 fn_compute_nav cash leg). Append-
--       only immutability triple-fence (merge-block #8) + 014-style NaN fence on balance
--       + account_users rd_access-JOIN RLS + service_role SELECT+INSERT-only grant + C6
--       two-tenant battery gate before merge.
--
-- Numbering: 018 follows 017 (account_trans investment cols). Depends on 005
--   (pfin.holdings_checkpoint — the ALTER target; its immutability triple-fence +
--   SELECT-only-to-authenticated grant + rd_access-JOIN SELECT policy — READ IN FULL
--   before authoring, per the PART B B-note), 003 (pfin.account — the sole-anchor FK
--   target + the account_users JOIN target that resolves tenancy), 006 (the account_users
--   rd_access-JOIN RLS shape mirrored for the cash table's SELECT), 014 (the NaN CHECK
--   pattern), 008 (the least-privilege service_role grant idiom; service_role already
--   holds schema USAGE from 008). Downstream: 019 fn_compute_nav's cash + security legs
--   consume account_balance_checkpoint and holdings_checkpoint_latest.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list). Read Decision 4 verbatim before drafting (done). This
--   migration introduces ZERO catalogued §10 instances; the ledger STAYS at 2
--   (RT-22 + RT-26 per ADR-011 Decision 4).
--   (i)   Instance-numbering: RT-22 first, RT-26 second — unchanged (not touched).
--   (ii)  Layer-attribution: the two service_role SELECT+INSERT grants (on
--         holdings_checkpoint and account_balance_checkpoint) are DB-LAYER ACLs — NOT
--         the RT-26 code-layer SUPABASE_SERVICE_ROLE_KEY allowlist grep fence (which
--         governs WHERE the service key is used in web-app/worker SOURCE), and NOT the
--         RT-22 PDF-worker container infra-credential fence. Identical reasoning to
--         008 lines 49–57 / 015 lines 44–52 / 017 lines 43–54. The service_role CODE
--         consumers (the provider-sync snapshot-writer routes) live in web-app/worker
--         source and are governed by RT-26 THERE, not by this migration.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated. 018 is not the
--         canonical §10 anchor.
--   DE-CONFLATION GUARD: the append-only immutability fences (block-mutation + block-
--   truncate + REVOKE TRUNCATE) are Decision-2 audit-class mechanisms on a separate
--   ledger — NOT §10 catalogued instances (the same separation as SELF-187's DEFINER-
--   allowlist 2→3 being distinct from §10).
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family count +0 (stays 7).
--   018 adds ZERO new Decision-3 instances. Every FK-shaped column here is a SOLE
--   tenant anchor (tenancy derives via an account_users JOIN — no second anchor to
--   mismatch), which is NOT a matched-tenant instance (same reasoning as 004/005's
--   account_id, ADR-011 Decision 4 forward-flag (a)):
--     - holdings_checkpoint.account_id → pfin.account  : SOLE anchor (005; unchanged).
--     - holdings_checkpoint.security_id                : NOT added — DEFERRED to V1.3
--       (V1 keeps symbol text). Its future addition would be the 3rd novel-fence site
--       → canonical 11 at V1.3 (PART C), NOT here.
--     - account_balance_checkpoint.account_id → pfin.account : SOLE anchor (this table
--       carries NO own users_id; scope derives via account_id → account_users.rd_access-
--       JOIN, mirroring 005/006). No second anchor to mismatch → NOT a Decision-3
--       instance.
--     - account_balance_checkpoint.currency (text R-16 code) : not an FK → NOT D3.
--     - account_balance_checkpoint.source (text provider discriminator) : not an FK → NOT D3.
--   The canonical Decision-3 running enumeration is UNCHANGED by 018 (family stays 7 at
--   this point in the batch: #1–#5 baseline + #6 [015] + #7 [017]; #8/#9 [020] + #10
--   [021] are later migrations). Sec numbering sign-off at joint-review.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — ALL functions are SECURITY INVOKER (NOT DEFINER); allowlist
--   STAYS 3 (ADR-011 Decision 9: fn_refresh_updated_at + fn_grant_creator_access + the
--   still-unauthored audit-log helper; authored-so-far = 2). ZERO new SECURITY DEFINER
--   in 018. The two immutability fence functions on account_balance_checkpoint touch
--   nothing (they just raise) → INVOKER, not allowlist entries (004/005/015 posture).
--   The latest-snapshot view(s) are security_invoker = true (merge-block #2): they
--   inherit the CALLER's RLS context, so an authenticated read sees only rows the
--   caller's account_users rd_access-JOIN admits (no owner-semantics leak — distinct
--   from 015's decrypted_source_credential, which is deliberately owner-semantics for
--   the vault join). service_role reachability is DB-ACL grant only (no function).
--
-- ----------------------------------------------------------------------------
-- APPEND-ONLY POSTURE — why triggers, not just RLS/grants (005/017 reasoning).
--   Both snapshot tables are append-only audit-class: a provider snapshot is a point-in-
--   time fact that is never edited, only superseded by a newer snapshot row. service_role
--   BYPASSES RLS but NOT triggers, and TRUNCATE bypasses ROW-level triggers (fires only
--   STATEMENT-level BEFORE TRUNCATE) — so the immutability fence is a TRIGGER pair
--   (row-level BEFORE UPDATE OR DELETE + statement-level BEFORE TRUNCATE) + a defensive
--   REVOKE TRUNCATE, covering UPDATE + DELETE + TRUNCATE across ALL roles incl.
--   service_role. holdings_checkpoint already carries this fence from 005 (shared
--   fn_reconciliation_family_block_mutation/_block_truncate); account_balance_checkpoint
--   gets its own dedicated pair (it is NOT part of the reconciliation family — it is an
--   ADR-027 cash-analog; per-table functions mirror 015's linked_source audit tables).
--   Grants are SELECT+INSERT only — append-only holds even with INSERT granted.
--
-- ----------------------------------------------------------------------------
-- ONE-WAY DOORS realized in 018 (flagged for F/CTO; all pre-ratified):
--   (1) RELAX pfin.holdings_checkpoint.symbol NOT NULL → nullable. ALTER COLUMN DROP NOT
--       NULL is DDL — safe on the EMPTY greenfield table (005's block-mutation trigger is
--       BEFORE UPDATE OR DELETE row-op only; block-truncate is BEFORE TRUNCATE — neither
--       fires on ALTER TABLE). Loosening a NOT NULL is itself reversible while empty, but
--       once provider snapshots with NULL symbols land it becomes a data one-way-door
--       (re-tightening would require backfilling/removing the null-symbol rows). Realized
--       now while empty. TEST-IMPACT: see the note below.
--   (2) The pfin.account_balance_checkpoint TABLE SHAPE (columns, the unique grain
--       (account_id, as_of_date, source), append-only posture). Once provider cash-
--       balance snapshots land, reshaping it is a data migration. Realized now while
--       empty (greenfield), which is exactly why the shape is ratified before backfill.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.holdings_checkpoint (existing, 005) — CHANGES:
--     - symbol: NOT NULL → NULLABLE (provider positions can lack a symbol).
--     - GRANT select, insert to service_role (append-only provider-write path; the
--       005 authenticated SELECT-only grant + rd_access-JOIN SELECT policy stand).
--     - NO security_id column (DEFERRED V1.3); NO change to the 005 immutability fence.
--   pfin.holdings_checkpoint_latest — VIEW, security_invoker = true (merge-block #2).
--     DISTINCT ON (account_id, symbol) latest-by (as_of_date desc, checkpoint_id desc).
--     RLS-inherited from caller; SELECT to authenticated. Consumed by 019 fn_compute_nav
--     / fn_holdings_as_of (the snapshot leg of the §7 dual-path).
--   pfin.account_balance_checkpoint — NEW append-only audit-class cash-balance snapshot.
--     - balance_id bigint generated always as identity PK.
--     - account_id → pfin.account(account_id) ON DELETE RESTRICT (SOLE anchor; 005 posture).
--     - balance numeric(20,4) NOT NULL (the payload; 014-style NaN CHECK).
--     - currency text NOT NULL DEFAULT 'USD' (R-16 code; mirrors account.currency).
--     - as_of_date date NOT NULL.
--     - source text NOT NULL (provider discriminator; unconstrained like
--       account_trans.source_provider — aggregator-pivot provider-agnostic intent).
--     - created_at timestamptz NOT NULL default now() (no updated_at — immutable).
--     - unique(account_id, as_of_date, source) — one balance per account/date/provider.
--     - RLS: SELECT to authenticated via account_users rd_access-JOIN (mirrors 006);
--       NO authenticated write policy (service_role sole writer). GRANT select to
--       authenticated (RLS-gated) + select, insert to service_role (append-only).
--     - Append-only immutability triple-fence for ALL roles.
--   pfin.fn_account_balance_checkpoint_block_mutation() — BEFORE UPDATE OR DELETE (row); raises.
--   pfin.fn_account_balance_checkpoint_block_truncate() — BEFORE TRUNCATE (statement); raises.
--   Security-load-bearing edges: append-only holds under service_role via TRIGGERS (not
--     RLS/grant); NaN fence is role-agnostic (service_role bypasses RLS, not CHECK);
--     tenancy of the cash table derives via the account_users JOIN (sole anchor); the
--     latest views inherit the caller's RLS (security_invoker). C6-GATED: both service_
--     role grants require QA's §4.5 two-tenant RLS battery (cross-tenant read+write fail
--     closed) BEFORE V1-SHIP-BLOCK merge (merge-block #8 / ADR-023).
--   FORWARD-FLAG (Sec merge-block #2): 018 does NOT author a cash latest-balance view —
--     it is DEFERRED to 019 (where fn_compute_nav owns the per-account-vs-per-source
--     grouping + the §7 dual-path). WHEN authored there it MUST be security_invoker = true
--     (exactly as holdings_checkpoint_latest here) so it inherits the caller's RLS; a
--     non-invoker (owner-semantics) view over account_balance_checkpoint would leak EVERY
--     tenant's cash balance to any authenticated reader.
-- ============================================================================

create schema if not exists pfin;
-- service_role schema USAGE + authenticated schema USAGE persist from 008 / 001.

-- ----------------------------------------------------------------------------
-- (A) pfin.holdings_checkpoint (005) — provider write-path activation.
-- ----------------------------------------------------------------------------

-- (A.1) RELAX symbol NOT NULL. DDL (does not fire the 005 row-level/statement-level
-- immutability triggers). Provider positions / money-market / blank-symbol sweeps can
-- carry no symbol (SELF-200 blank-symbol line); the symbol-only V1 shape holds (the
-- securities-master security_id FK is DEFERRED to V1.3 per PART B — NOT added here).
alter table pfin.holdings_checkpoint
  alter column symbol drop not null;

comment on column pfin.holdings_checkpoint.symbol is
  'Per-asset ticker/identifier (TEXT; securities-master security_id FK DEFERRED to V1.3). '
  'NULLABLE as of 018 (relaxed from the 005 NOT NULL): provider position snapshots, money-'
  'market/sweep balances, and the SELF-200 blank-symbol fallback can lack a symbol. The '
  'V1 shape stays symbol-only. Once null-symbol snapshots land this relax becomes a data '
  'one-way-door (ADR-027 / 018).';

-- (A.2) service_role provider-write grant (append-only). The 005 immutability triple-
-- fence already blocks UPDATE/DELETE (row trigger) + TRUNCATE (statement trigger +
-- REVOKE TRUNCATE) for ALL roles incl. service_role, so SELECT+INSERT is safe and
-- append-only holds by-construction (008/015 idiom). The 005 authenticated SELECT-only
-- grant + rd_access-JOIN SELECT policy are untouched. C6-gated (merge-block #8 sibling).
grant select, insert on pfin.holdings_checkpoint to service_role;

-- (A.3) Latest-snapshot view — security_invoker = true (Sec merge-block #2). Per-
-- (account_id, symbol) latest row by (as_of_date desc, checkpoint_id desc tie-break).
-- security_invoker → the view runs under the CALLER's RLS, so an authenticated read is
-- filtered by holdings_checkpoint_select (rd_access-JOIN) to owned rows; service_role
-- (RLS-bypassing) sees all. Consumed by 019 fn_holdings_as_of / fn_compute_nav (the
-- snapshot leg of the §7 dual-path for aggregator/incomplete accounts).
-- NOTE (V1 grouping semantics): NULL symbols group together under DISTINCT ON
-- (account_id, symbol) — Postgres treats NULLs as equal for DISTINCT ON — so multiple
-- distinct null-symbol positions on one account collapse to their single latest row.
-- Acceptable under the symbol-only V1 shape; distinct instrument-real cash-likes carry
-- distinct symbols (MMFs/sweeps). Revisit when the security_id FK lands at V1.3.
create or replace view pfin.holdings_checkpoint_latest
  with (security_invoker = true) as
  select distinct on (account_id, symbol)
    checkpoint_id,
    account_id,
    symbol,
    as_of_date,
    quantity,
    balance,
    created_at
  from pfin.holdings_checkpoint
  order by account_id, symbol, as_of_date desc, checkpoint_id desc;

comment on view pfin.holdings_checkpoint_latest is
  'Latest per-(account, symbol) holdings snapshot (ADR-027 / 018; Sec merge-block #2). '
  'DISTINCT ON (account_id, symbol) ordered by as_of_date desc, checkpoint_id desc — one '
  'current-position row per account/symbol. security_invoker = true: inherits the '
  'CALLER''s RLS, so authenticated reads are scoped by the 005 holdings_checkpoint_select '
  'rd_access-JOIN (owned rows only); service_role sees all. Consumed by 019 '
  'fn_holdings_as_of / fn_compute_nav as the snapshot leg of the §7 dual-path '
  '(aggregator/incomplete accounts). V1 NULL-symbol positions collapse to one latest row '
  'per account (DISTINCT ON treats NULLs as equal); acceptable under the symbol-only V1 '
  'shape (security_id FK deferred V1.3).';

grant select on pfin.holdings_checkpoint_latest to authenticated;

-- ----------------------------------------------------------------------------
-- (B) pfin.account_balance_checkpoint — the §7 cash analog (Sec merge-block #8).
-- Append-only provider cash-balance snapshot. SOLE tenant anchor account_id (tenancy
-- via account_users rd_access-JOIN — this table has no own users_id). NOT a Decision-3
-- instance. NOT part of the reconciliation family — an ADR-027 cash-analog with its own
-- dedicated immutability fence pair.
-- ----------------------------------------------------------------------------
create table if not exists pfin.account_balance_checkpoint (
  balance_id   bigint generated always as identity primary key,
  account_id   bigint not null references pfin.account (account_id) on delete restrict,
  balance      numeric(20,4) not null,                  -- provider-reported cash balance (the payload; NaN-fenced)
  currency     text not null default 'USD',             -- R-16 denomination code; mirrors account.currency (not an FK)
  as_of_date   date not null,                           -- provider snapshot date
  source       text not null,                           -- provider discriminator (unconstrained; like account_trans.source_provider)
  created_at   timestamptz not null default now(),      -- IMMUTABLE post-INSERT (append-only; no updated_at)
  constraint account_balance_checkpoint_balance_finite check (balance <> 'NaN'::numeric),
  unique (account_id, as_of_date, source)
);

comment on table pfin.account_balance_checkpoint is
  'Provider-reported cash-balance snapshot — the §7 cash analog of holdings_checkpoint '
  '(ADR-027 amendment (c-cash); 018; Sec merge-block #8). Landing table for D-3 = B: when '
  'an account is aggregator-sourced/incomplete, its cash balance lands here; complete/'
  'backfilled accounts derive cash as Σ(account_trans.amount) instead (019 fn_compute_nav '
  'cash leg, §7 dual-path). Append-only audit-class: UPDATE + DELETE + TRUNCATE blocked '
  'for ALL roles (fn_account_balance_checkpoint_block_mutation + _block_truncate + REVOKE '
  'TRUNCATE); a stale balance is superseded by a newer snapshot row, never edited. SOLE '
  'tenant anchor account_id (NO own users_id; scope derives via account_id → account_users.'
  'rd_access-JOIN, mirroring 005/006 — NOT a Decision-3 instance). balance numeric(20,4) '
  'NOT NULL NaN-fenced (014-pattern; a NaN would poison SUM/NAV and can never be UPDATEd '
  'out of the immutable ledger). currency = R-16 text code (not an FK). source = provider '
  'discriminator (unconstrained text, aggregator-pivot provider-agnostic intent). '
  'unique(account_id, as_of_date, source) = one balance per account/date/provider. '
  'Writes are service_role (privileged-context-write, Decision 1); authenticated holds '
  'RLS-gated SELECT only, never write. C6 exposure-gated (ADR-023 / merge-block #8): the '
  '§4.5 two-tenant RLS battery must prove cross-tenant read+write fail closed BEFORE the '
  'grants merge.';

comment on constraint account_balance_checkpoint_balance_finite on pfin.account_balance_checkpoint is
  'Rejects the numeric special value NaN on balance (014-pattern DB-layer defense-in-'
  'depth). Role-agnostic table CHECK (service_role bypasses RLS but not CHECK). NOT NULL '
  'column, so no NULL-passes gap. ±Infinity already rejected by numeric(20,4) coercion.';

alter table pfin.account_balance_checkpoint enable row level security;

-- RLS SELECT: rd_access-JOIN to account_users (mirrors 005 holdings_checkpoint_select /
-- 006 account_trans_select). A user reads a cash-balance snapshot only for an account on
-- which they hold rd_access. NO INSERT/UPDATE/DELETE policy — service_role (RLS-bypassing)
-- is the sole writer (Decision 1 privileged-context-write); UPDATE/DELETE are additionally
-- trigger-blocked for ALL roles (append-only).
create policy account_balance_checkpoint_select on pfin.account_balance_checkpoint
  for select to authenticated
  using (exists (
    select 1 from pfin.account_users au
    where au.account_id = account_balance_checkpoint.account_id
      and au.users_id = auth.uid()
      and au.rd_access
  ));

comment on policy account_balance_checkpoint_select on pfin.account_balance_checkpoint is
  'SELECT policy: rd_access-JOIN to pfin.account_users (mirrors 005 holdings_checkpoint_'
  'select / 006 account_trans_select). A user reads a cash-balance snapshot only for an '
  'account on which they hold an account_users grant with rd_access = true. No write '
  'policy — service_role is the sole (RLS-bypassing) writer; UPDATE/DELETE/TRUNCATE are '
  'trigger-blocked for all roles (append-only).';

-- ACL-before-RLS (PR #106 gotcha): the role needs the table-level GRANT even with RLS on.
-- authenticated: SELECT only (RLS-gated). service_role: SELECT + INSERT only — append-only
-- (NO update/delete/truncate grant; merge-block #8 "INSERT-only"). anon: nothing.
grant select on pfin.account_balance_checkpoint to authenticated;
grant select, insert on pfin.account_balance_checkpoint to service_role;

create index if not exists account_balance_checkpoint_account_id_idx
  on pfin.account_balance_checkpoint (account_id);
create index if not exists account_balance_checkpoint_account_asof_idx
  on pfin.account_balance_checkpoint (account_id, as_of_date);

-- Append-only immutability triple-fence (Sec merge-block #8). Dedicated per-table
-- functions (this table is NOT part of the reconciliation family; mirrors 015's
-- linked_source audit-table fences). Both INVOKER + set search_path = '' + touch nothing
-- (just raise) → not DEFINER allowlist entries.
create or replace function pfin.fn_account_balance_checkpoint_block_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Fail LOUD (raise, not return null). Blocks UPDATE + DELETE for ALL roles; service_role
  -- bypasses RLS but NOT triggers, so this — not RLS/grant — is the authoritative
  -- immutability fence (ADR-011 Decision 2 append-only audit-class; ADR-027 018).
  raise exception
    'pfin.account_balance_checkpoint is immutable (append-only audit-class; ADR-011 Decision 2 / ADR-027 018). % blocked — a cash-balance snapshot is superseded by a newer row, never edited.', tg_op;
end;
$$;

revoke execute on function pfin.fn_account_balance_checkpoint_block_mutation() from public;

comment on function pfin.fn_account_balance_checkpoint_block_mutation() is
  'BEFORE UPDATE OR DELETE immutability fence on pfin.account_balance_checkpoint (ADR-011 Decision 2 / ADR-027 018; Sec merge-block #8). SECURITY INVOKER (touches nothing; not a DEFINER allowlist entry — allowlist stays 3). raise exception (fail loud). Blocks UPDATE + DELETE for ALL roles incl. service_role (which bypasses RLS but not triggers). INSERT unblocked (append-only). tg_op embedded for QA test-matching.';

create or replace function pfin.fn_account_balance_checkpoint_block_truncate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Row-level UPDATE/DELETE triggers do NOT fire on TRUNCATE (Postgres runs it through
  -- STATEMENT-level BEFORE TRUNCATE only), so a role holding TRUNCATE could wipe the
  -- append-only ledger without tripping the row-level fence. This + REVOKE TRUNCATE close
  -- that path for ALL roles.
  raise exception
    'pfin.account_balance_checkpoint is immutable (append-only audit-class; ADR-011 Decision 2 / ADR-027 018). TRUNCATE blocked — the cash-balance snapshot ledger cannot be wiped.';
end;
$$;

revoke execute on function pfin.fn_account_balance_checkpoint_block_truncate() from public;

comment on function pfin.fn_account_balance_checkpoint_block_truncate() is
  'BEFORE TRUNCATE (statement-level) immutability fence on pfin.account_balance_checkpoint (ADR-011 Decision 2 / ADR-027 018; Sec merge-block #8). SECURITY INVOKER. raise exception (fail loud). Row-level triggers do NOT fire on TRUNCATE, so this statement-level fence + the REVOKE TRUNCATE below close the audit-retention-wipe path for ALL roles regardless of grant state. Message distinct from the row-level fence for test-matching.';

create trigger account_balance_checkpoint_block_mutation
  before update or delete on pfin.account_balance_checkpoint
  for each row execute function pfin.fn_account_balance_checkpoint_block_mutation();
create trigger account_balance_checkpoint_block_truncate
  before truncate on pfin.account_balance_checkpoint
  for each statement execute function pfin.fn_account_balance_checkpoint_block_truncate();
revoke truncate on pfin.account_balance_checkpoint from public;

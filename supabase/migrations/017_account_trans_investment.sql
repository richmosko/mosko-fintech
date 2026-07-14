-- ============================================================================
-- Migration: pfin.account_trans — investment columns + novel global-OR-matched-
--   tenant security_id fence + fn_ingest_transactions bulk INVOKER RPC.
-- Phase 6 Build Loop (ADR-027 ingest/valuation substrate, migration 017 of 015–021;
--   design CLOSED + Sec-cleared 2026-07-14: temp/015-architect-design-spec.md PART B
--   (the 017 row) + PART C (Decision-3 family; Pattern 2 novel fence, site 1 = #7)
--   + PART D (D-c ingest batch shape / OWD-D all-or-nothing; D.2 plaid_transaction_id
--   drop one-way-door) + temp/015-ingest-substrate-design.md §16 R-6 / R-7 / R-12 /
--   R-15 / R-18 + OWD-D + the GRAIN/CASH THREAD RESOLVED block (the 017 quantity
--   convention). JOINT-REVIEW-MANDATORY — this is the batch's HEAVIEST Sec surface:
--   the security_id fence is the FIRST global-OR-owned fence that must hold under a
--   service_role write path (RLS bypassed), so the trigger is the SOLE gate there.
--
-- WHAT THIS DOES:
--   (A) ALTERs pfin.account_trans (004, immutable ledger) with the V1 investment
--       columns: security_id (nullable FK → pfin.asset), signed quantity, cost_basis,
--       price (each 014-style NaN-fenced) + the uniform cash-as-asset CHECK
--       (quantity = 0 OR security_id IS NOT NULL); the generic provider-dedup pair
--       source_provider + provider_txn_id (+ partial-unique index) replacing the
--       Plaid-specific plaid_transaction_id (DROPPED per R-12); and provider_category
--       (immutable display hint only — R-18, all txns land Unsorted, NO auto-map V1).
--   (B) Authors the NOVEL global-OR-matched-tenant fence fn_account_trans_security_asset
--       (Decision-3 CANONICAL instance #7 / Pattern 2 site 1) — the SOLE gate on the
--       service_role ingest path.
--   (C) Authors fn_ingest_transactions(jsonb) — the SECURITY INVOKER (R-15) bulk-ingest
--       RPC: all-or-nothing set-based insert…select…on conflict do nothing (OWD-D).
--
-- Numbering: 017 follows 016 (pfin.asset registry). Depends on 004 (account_trans
--   immutable ledger — the ALTER target; its block-mutation/block-truncate triggers,
--   the plaid/hash dedup indexes, import_hash, INSERT-only posture), 006 (account_trans
--   rd/wr_access-JOIN RLS + GRANT select,insert — the RLS the RPC composes under), 016
--   (pfin.asset — the FK target + the hybrid global-OR-owned RLS the fence mirrors), 014
--   (the NaN/finite CHECK pattern), 008 (service_role already holds SELECT,INSERT on
--   account_trans — the fenced ingest path), 003 (pfin.account — the JOIN target that
--   resolves the tenant for the security_id fence). Downstream: 019 fn_holdings_as_of /
--   fn_compute_nav consume the quantity/security_id/price columns.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list). Read Decision 4 verbatim before drafting. This
--   migration introduces ZERO catalogued §10 instances; the ledger STAYS at 2
--   (RT-22 + RT-26 per ADR-011 Decision 4).
--   (i)   Instance-numbering: RT-22 first, RT-26 second — unchanged (not touched).
--   (ii)  Layer-attribution: no infrastructure-credential-presence surface (RT-22 =
--         PDF-worker container) and no code-layer SUPABASE_SERVICE_ROLE_KEY allowlist
--         surface (RT-26 = web-app/worker SOURCE grep fence) is touched. This is
--         authenticated-tier column/RLS/trigger DDL + one INVOKER RPC.
--         fn_ingest_transactions is SECURITY INVOKER / authenticated / RLS-enforced
--         (R-15) — it uses NO service_role, so it adds NO RT-26 code-layer surface.
--         The service_role write path INTO account_trans PRE-EXISTS from 008 (the
--         Plaid-transaction-sync grant, SELECT+INSERT) and is UNCHANGED here — 017
--         adds no service_role grant. That pre-existing service_role code consumer
--         (provider-sync routes / ETL) is governed by RT-26 in web-app/worker source,
--         NOT in this migration. §10 ledger stays 2.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated. 017 is not the
--         canonical §10 anchor.
--   DE-CONFLATION GUARD: the novel global-OR-matched-tenant fence (below) is a
--   Decision-3 mechanism, and the quantity/security_id CHECK + NaN CHECKs are
--   Decision-2-adjacent value invariants — NEITHER is a §10 catalogued instance, the
--   same separation as SELF-187's DEFINER-allowlist 2→3 being distinct from §10.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — CANONICAL INSTANCE #7 (family 6 → 7).
--   pfin.account_trans.security_id → pfin.asset(asset_id) is the NOVEL
--   global-OR-matched-tenant fence (Pattern 2, site 1 of 2; site 2 =
--   user_asset_category.asset_id @ 020, #9). Under 016's G1 hybrid registry
--   (nullable asset.users_id), a referenced asset is valid IFF it is GLOBAL
--   (users_id IS NULL — market securities/currencies, legal for ANY tenant) OR
--   OWNED by the referencing row's tenant (a per-user physical/custom asset).
--   account_trans carries NO own users_id, so the tenant is resolved via
--   account_id → pfin.account.users_id (the JOIN below). This is NOT the familiar
--   012 matched-tenant equality — it is the wider global-OR-owned predicate, hence
--   "novel" and a Sec-designed pattern.
--
--   ENUMERATION — already recorded; NO DECISIONS.md touch in this PR.
--     The ADR-027 atomic amendment (g) (landed in the 015 PR, DECISIONS.md — "the
--     015–021 batch adds +5 … account_trans.security_id [#7, 017]") ALREADY
--     enumerates the whole Decision-3 5 → 10 family delta and maps instance #7 to
--     THIS migration. Per that amendment's "per-migration Decision-3 evaluation +
--     Sec joint-review at each of 015–021" instruction, 017's obligation is this
--     in-header evaluation (family count moves 6 → 7 as the pre-enumerated #7 is
--     REALIZED) + Sec numbering sign-off at joint-review — NOT a new ADR/amendment.
--     This mirrors the 015 precedent exactly (015 realized #6 under the same atomic
--     amendment; it authored no separate per-instance enumeration note). Canonical
--     running enumeration for Sec to verify:
--       #1 reconciliation_event_trans (event_id, account_trans_id)     [Lock 9]
--       #2 account_trans.replaces_trans_id self-FK                      [004]
--       #3 monthly_report.included_reconciliation_event_ids INTEGER[]   [Lock 11]
--       #4 monthly_report_account_snapshot.account_id                   [Lock 12]
--       #5 account.sub_cat_id → user_taxonomy(id)                       [012 / ADR-025]
--       #6 account.linked_source_id → linked_source                     [015]
--       #7 account_trans.security_id → pfin.asset  ← THIS (novel fence, Pattern 2/1)
--     (#8 user_asset_category.sub_cat_id @020, #9 user_asset_category.asset_id @020,
--      #10 account_trans_annotation.sub_cat_id @021 — later migrations.)
--
--   OTHER FK-shaped columns on account_trans — evaluated, NOT new D3 instances:
--     - account_id → pfin.account: SOLE tenant anchor (no second anchor to mismatch);
--       evaluated at 004. NOT D3.
--     - replaces_trans_id (self-FK): the already-catalogued #2 (004's
--       fn_account_trans_matched_account). Not re-counted.
--     - source_provider / provider_txn_id / provider_category / import_hash: external
--       keys / text hints, not pfin FKs. NOT D3.
--     - security_id realization mechanism = BEFORE INSERT trigger (a single-row CHECK
--       cannot subquery the referenced asset+account; Decision 3 permits a trigger
--       where PG cannot express the constraint declaratively).
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — both functions are SECURITY INVOKER (NOT DEFINER); allowlist
--   STAYS 3 (ADR-011 Decision 9: fn_refresh_updated_at + fn_grant_creator_access +
--   the still-unauthored audit-log helper). ZERO new SECURITY DEFINER in 017.
--
--   fn_account_trans_security_asset (the fence) — SECURITY INVOKER, set search_path=''.
--     ***LOAD-BEARING UNDER service_role (the critical property).*** account_trans is
--     written under service_role by the provider-sync path (008 grant; RLS BYPASSED).
--     Triggers FIRE regardless of RLS/BYPASSRLS — service_role bypasses RLS but NOT
--     triggers — so THIS TRIGGER IS THE SOLE FENCE on the service_role ingest path.
--     It therefore MUST NOT rely on RLS to scope the asset read: the fence is the
--     EXPLICIT JOIN-to-account predicate (asset is global OR asset.users_id =
--     account.users_id), authoritative under service_role. Under authenticated the
--     predicate composes with 016's asset RLS (global-OR-owned) as belt-and-suspenders
--     — same INVOKER-composes-with-RLS reasoning as 004/012, with the added
--     service_role-ingest bite that makes the explicit predicate non-optional.
--     NULL-safe fail-closed (NOT EXISTS → raise). No elevation needed → INVOKER →
--     not a DEFINER allowlist entry.
--     TRIGGER EVENT = BEFORE INSERT only (matches 004's sibling fence on the same
--     immutable table): account_trans is append-only (004 blocks UPDATE/DELETE for
--     ALL roles incl. service_role), so INSERT is the only path a security_id can
--     arrive on. An UPDATE fence would be dead — the 004 block-mutation trigger
--     rejects the UPDATE first. (Contrast 012, which covers UPDATE because
--     pfin.account is MUTABLE.)
--
--   fn_ingest_transactions (the bulk RPC) — SECURITY INVOKER (R-15: authenticated,
--     RLS-enforced, NOT service_role). Every row it inserts is one the caller is
--     entitled to insert: account_trans_insert WITH CHECK (006, wr_access-JOIN)
--     validates each row as the caller; the security_id fence (above), the NaN CHECKs,
--     the quantity/security_id CHECK, and 004's matched-account fence all evaluate
--     per-row. Provider *credential* writes stay service_role (linked_source); this is
--     the txn-row ingest path only (R-15). No elevation → INVOKER → allowlist stays 3.
--     set search_path='' injection fence; all refs schema-qualified. EXECUTE revoked
--     from PUBLIC (denies anon), granted to authenticated only (mirrors 013).
--     API-SURFACE NOTE (mild one-way door, same as 013): pfin is [api]-exposed
--     (ADR-023), so this RPC is callable via PostgREST /rpc/fn_ingest_transactions;
--     its (p_rows jsonb) signature is an API contract.
--
-- ----------------------------------------------------------------------------
-- ONE-WAY DOORS realized in 017 (flagged for F/CTO; all pre-ratified):
--   (1) DROP account_trans.plaid_transaction_id + its dedup index (R-12; PART D.2).
--       A column-drop on the IMMUTABLE ledger — safe ONLY because the table is EMPTY
--       (greenfield; Plaid never launched). ADD/DROP COLUMN + DROP INDEX are DDL, not
--       row ops, so the 004 block-mutation trigger (UPDATE/DELETE rows only) does not
--       fire. import_hash is KEPT (the content-hash dedup for the spreadsheet-import
--       path). Once transaction data lands, this becomes a data one-way-door; it is
--       realized now while empty. TEST-IMPACT: any test referencing
--       plaid_transaction_id / account_trans_plaid_dedup_idx breaks — flagged to
--       QA/Backend (mirrors the 007-test-retirement lesson from 015). Architect does
--       NOT edit tests/.
--   (2) The quantity convention (R-7 + GRAIN/CASH RESOLVED, one-way-door): signed
--       quantity numeric(28,8) NOT NULL DEFAULT 0 (+buy / −sell), amount
--       positive=inflow/negative=outflow, and CHECK (quantity = 0 OR security_id IS
--       NOT NULL). Once backfill data imprints this sign/cash convention, reversing it
--       is a data migration. Realized now while empty.
--   (3) The NOVEL global-OR-matched-tenant fence PATTERN (Pattern 2) sets the
--       precedent for EVERY future FK into the hybrid pfin.asset registry (site 2 =
--       020 #9). Not data-reversible once shipped — all asset-referencing FKs inherit
--       it. Sec joint-review is the gate.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.account_trans gains:
--     - security_id (bigint NULL → pfin.asset(asset_id) ON DELETE RESTRICT): the held
--       security for a share movement; NULL = pure-cash txn. Novel global-OR-matched-
--       tenant fenced (fn_account_trans_security_asset). D3 CANONICAL instance #7.
--     - quantity (numeric(28,8) NOT NULL DEFAULT 0): signed share count (+buy/−sell,
--       R-7). 0 = cash. NaN-fenced.
--     - cost_basis (numeric(20,4) NULL): per-lot/aggregate cost. NaN-fenced.
--     - price (numeric(20,4) NULL): per-share transaction price. NaN-fenced.
--       cost_basis/price mirror amount's numeric(20,4) money precision.
--     - CHECK account_trans_qty_requires_security (quantity = 0 OR security_id IS NOT
--       NULL): uniform cash-as-asset invariant. A share movement REQUIRES a security;
--       pure-cash carries quantity=0/security_id=NULL; a securities BUY carries BOTH
--       amount=−cash AND quantity=+shares. Holdings/security-leg filters on
--       security_id IS NOT NULL (019 fn_holdings_as_of — no qty=0 special-handling).
--     - source_provider (text NULL) + provider_txn_id (text NULL): generic provider
--       dedup pair (replaces plaid_transaction_id, R-12). Partial-unique
--       account_trans_provider_dedup_idx(source_provider, provider_txn_id) WHERE
--       provider_txn_id IS NOT NULL — one row per provider transaction, table-wide.
--     - provider_category (text NULL): IMMUTABLE display hint only (R-18). All txns
--       land Unsorted; NO auto-map / NO provider_category→sub_cat routing in V1.
--     - CHECK account_trans_{quantity,cost_basis,price}_finite: 014-style NaN
--       rejection (numeric bounded-precision already rejects ±Infinity at coercion).
--   pfin.account_trans DROPS: plaid_transaction_id + account_trans_plaid_dedup_idx
--     (R-12). import_hash + account_trans_hash_dedup_idx KEPT.
--   pfin.fn_account_trans_security_asset() — BEFORE INSERT WHEN (security_id IS NOT
--     NULL); SECURITY INVOKER; set search_path=''; NULL-safe fail-closed; global-OR-
--     owned predicate resolving tenant via account JOIN. Sole fence under service_role.
--   pfin.fn_ingest_transactions(p_rows jsonb) RETURNS TABLE(inserted int, skipped int)
--     — SECURITY INVOKER (R-15); set search_path=''; all-or-nothing set-based
--     insert…select…on conflict (provider dedup) do nothing (OWD-D). Cash rows →
--     quantity=0/security_id NULL; security rows → quantity=±shares/security_id set.
--     Inserts under the caller's RLS (wr_access-JOIN). EXECUTE granted to authenticated.
--   Security-load-bearing edges: the security_id fence is the SOLE gate on the
--     service_role ingest path (explicit predicate, not RLS); NaN + quantity/security
--     CHECKs are role-agnostic (service_role bypasses RLS, not CHECK/triggers); the RPC
--     composes every fence per-row and aborts the whole batch on any hard error.
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- (A) Investment columns on the immutable ledger (ADD COLUMN is DDL — the 004
-- block-mutation trigger fires on UPDATE/DELETE row ops, not ALTER TABLE; the table
-- is EMPTY/greenfield so existing-row backfill is a no-op).
-- ----------------------------------------------------------------------------
alter table pfin.account_trans
  add column if not exists security_id bigint
    references pfin.asset (asset_id) on delete restrict;

alter table pfin.account_trans
  add column if not exists quantity numeric(28,8) not null default 0;

alter table pfin.account_trans
  add column if not exists cost_basis numeric(20,4);

alter table pfin.account_trans
  add column if not exists price numeric(20,4);

alter table pfin.account_trans
  add column if not exists source_provider text;

alter table pfin.account_trans
  add column if not exists provider_txn_id text;

alter table pfin.account_trans
  add column if not exists provider_category text;

comment on column pfin.account_trans.security_id is
  'Nullable FK → pfin.asset(asset_id) ON DELETE RESTRICT (ADR-027 / R-6). The held '
  'security for a share movement; NULL = a pure-cash transaction (uniform cash-as-'
  'asset model — cash carries no security). Decision-3 CANONICAL instance #7: the '
  'NOVEL global-OR-matched-tenant fence (Pattern 2, site 1) — a referenced asset is '
  'valid IFF global (asset.users_id IS NULL) OR owned by the account''s tenant '
  '(asset.users_id = account.users_id). Fenced by fn_account_trans_security_asset '
  '(BEFORE INSERT), which is the SOLE gate under the service_role ingest path '
  '(RLS bypassed). NOT the familiar 012 equality fence — it is the wider global-OR-'
  'owned predicate.';
comment on column pfin.account_trans.quantity is
  'Signed share count (R-7: +buy / −sell). numeric(28,8) NOT NULL DEFAULT 0 — 0 = a '
  'cash transaction. A securities BUY carries BOTH amount=−cash AND quantity=+shares. '
  'Holdings/security-leg reads (019 fn_holdings_as_of) filter on security_id IS NOT '
  'NULL, cleanly excluding cash without qty=0 special-handling. NaN-fenced '
  '(account_trans_quantity_finite). Governed by CHECK account_trans_qty_requires_'
  'security (quantity ≠ 0 ⇒ security_id present).';
comment on column pfin.account_trans.cost_basis is
  'Aggregate/per-lot cost basis for a security movement (numeric(20,4), mirrors '
  'amount''s money precision). Nullable (cash / unknown-basis). NaN-fenced. V1 stores '
  'it; lot-level cost-basis tracking UI is V2.';
comment on column pfin.account_trans.price is
  'Per-share transaction price for a security movement (numeric(20,4)). Nullable '
  '(cash). NaN-fenced. Distinct from 019 eod_price valuation-per-date: this is the '
  'as-transacted price on the ledger row.';
comment on column pfin.account_trans.source_provider is
  'Ingest-source discriminator (R-12): ''manual'' / ''import'' / a provider name '
  '(''plaid''/''snaptrade''/''simplefin''/…). Text (not an FK) → NOT Decision 3. '
  'Half of the generic provider-dedup key that replaces plaid_transaction_id.';
comment on column pfin.account_trans.provider_txn_id is
  'Provider-native transaction id (R-12): the external dedup handle. Text (not a pfin '
  'FK) → NOT Decision 3. Paired with source_provider in account_trans_provider_dedup_'
  'idx (partial-unique WHERE provider_txn_id IS NOT NULL) — one row per provider '
  'transaction, table-wide. Replaces the Plaid-specific plaid_transaction_id (DROPPED '
  'below, R-12). import_hash (KEPT) remains the content-hash dedup for the '
  'spreadsheet-import path.';
comment on column pfin.account_trans.provider_category is
  'Provider-supplied category string — DISPLAY HINT ONLY (R-18). V1 does NO auto-'
  'mapping: every txn lands Unsorted and the user assigns a Sub-Cat manually (SELF-200 '
  'flow); provider_category→user_taxonomy auto-categorization is DEFERRED to V1.x. '
  'Immutable per-row (account_trans is append-only). Text hint → NOT Decision 3.';

-- 014-style NaN fences on the new numeric columns. numeric(28,8)/numeric(20,4) reject
-- ±Infinity at coercion (bounded precision — verified in 014), so NaN is the only
-- non-finite gap. `<> 'NaN'` (not `= col`) because numeric NaN = NaN is TRUE. For the
-- nullable columns a NULL row yields NULL (not FALSE) → CHECK passes, as intended.
-- Role-agnostic (a table CHECK; service_role bypasses RLS but not CHECK constraints).
-- Idempotent add (pg_constraint guard — PG has no ADD CONSTRAINT IF NOT EXISTS).
do $$
begin
  if not exists (select 1 from pg_constraint
    where conname = 'account_trans_quantity_finite'
      and conrelid = 'pfin.account_trans'::regclass) then
    alter table pfin.account_trans
      add constraint account_trans_quantity_finite check (quantity <> 'NaN'::numeric);
  end if;
  if not exists (select 1 from pg_constraint
    where conname = 'account_trans_cost_basis_finite'
      and conrelid = 'pfin.account_trans'::regclass) then
    alter table pfin.account_trans
      add constraint account_trans_cost_basis_finite check (cost_basis <> 'NaN'::numeric);
  end if;
  if not exists (select 1 from pg_constraint
    where conname = 'account_trans_price_finite'
      and conrelid = 'pfin.account_trans'::regclass) then
    alter table pfin.account_trans
      add constraint account_trans_price_finite check (price <> 'NaN'::numeric);
  end if;
end $$;

comment on constraint account_trans_quantity_finite on pfin.account_trans is
  'Rejects the numeric special value NaN on quantity (014-pattern DB-layer defense-in-'
  'depth; a NaN would poison every SUM/holdings aggregation and can never be UPDATEd '
  'out of the immutable ledger). Role-agnostic. ±Infinity already rejected by '
  'numeric(28,8) coercion.';
comment on constraint account_trans_cost_basis_finite on pfin.account_trans is
  'Rejects NaN on cost_basis (014-pattern). NULL passes (nullable column). ±Infinity '
  'already rejected by numeric(20,4) coercion.';
comment on constraint account_trans_price_finite on pfin.account_trans is
  'Rejects NaN on price (014-pattern). NULL passes (nullable column). ±Infinity '
  'already rejected by numeric(20,4) coercion.';

-- Uniform cash-as-asset invariant: a share movement REQUIRES a security; pure-cash
-- txns carry quantity=0 / security_id=NULL. Idempotent add (pg_constraint guard).
do $$
begin
  if not exists (select 1 from pg_constraint
    where conname = 'account_trans_qty_requires_security'
      and conrelid = 'pfin.account_trans'::regclass) then
    alter table pfin.account_trans
      add constraint account_trans_qty_requires_security
      check (quantity = 0 or security_id is not null);
  end if;
end $$;

comment on constraint account_trans_qty_requires_security on pfin.account_trans is
  'Uniform cash-as-asset invariant (GRAIN/CASH RESOLVED; one-way-door): a nonzero '
  'quantity (a share movement) REQUIRES a security_id; pure-cash txns carry '
  'quantity=0 / security_id=NULL. A securities BUY carries BOTH amount=−cash AND '
  'quantity=+shares. Lets 019 fn_holdings_as_of split cash from securities purely on '
  'security_id IS NOT NULL. Role-agnostic table CHECK.';

-- Generic provider-dedup index (R-12): one row per provider transaction, table-wide.
-- provider_txn_id is provider-assigned and globally unique within a provider, so the
-- (source_provider, provider_txn_id) grain is stricter than the incumbent per-account
-- (account_id, plaid_transaction_id) — it also blocks the same provider txn landing on
-- two accounts. This index is the ON CONFLICT arbiter fn_ingest_transactions targets.
create unique index if not exists account_trans_provider_dedup_idx
  on pfin.account_trans (source_provider, provider_txn_id)
  where provider_txn_id is not null;

-- DROP the Plaid-specific dedup (R-12; one-way-door, safe because greenfield/empty).
-- Drop the index first (explicit), then the column. import_hash + its index are KEPT.
drop index if exists pfin.account_trans_plaid_dedup_idx;
alter table pfin.account_trans drop column if exists plaid_transaction_id;

-- ----------------------------------------------------------------------------
-- (B) The NOVEL global-OR-matched-tenant fence (Decision-3 CANONICAL instance #7 /
-- Pattern 2 site 1). SOLE gate on the service_role ingest path (triggers fire under
-- service_role, which bypasses RLS but NOT triggers) — the explicit JOIN-to-account
-- predicate is the whole fence; it does NOT rely on RLS to scope the asset read.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_account_trans_security_asset()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Trigger WHEN clause guarantees new.security_id IS NOT NULL.
  -- GLOBAL-OR-OWNED predicate (Pattern 2). account_trans has no own users_id, so the
  -- tenant is resolved via account_id → pfin.account.users_id (the JOIN). The asset is
  -- valid iff GLOBAL (a.users_id IS NULL — legal for any tenant) OR OWNED by the
  -- account's tenant (a.users_id = acc.users_id).
  -- NULL-SAFE FAIL-CLOSED: a missing asset, a missing account, or an asset that is
  -- neither global nor tenant-owned yields NOT EXISTS → raise. (Never
  -- `(subquery) <> ...` — that returns NULL on a missing row, the IF is skipped, and
  -- the write would leak.)
  -- LOAD-BEARING UNDER service_role: this predicate is authoritative regardless of RLS
  -- — it is the SOLE fence when the provider-sync path writes under service_role
  -- (008 grant; RLS bypassed). Under authenticated it composes with 016's asset RLS
  -- as belt-and-suspenders.
  if not exists (
    select 1
    from pfin.asset a
    join pfin.account acc on acc.account_id = new.account_id
    where a.asset_id = new.security_id
      and (a.users_id is null or a.users_id = acc.users_id)
  ) then
    raise exception
      'cross-tenant security rejected: security_id % is not a global or account-owned asset for account_id % (ADR-011 Decision 3 canonical instance #7 / novel global-OR-matched-tenant fence, Pattern 2 site 1)',
      new.security_id, new.account_id;
  end if;
  return new;
end;
$$;

revoke execute on function pfin.fn_account_trans_security_asset() from public;

comment on function pfin.fn_account_trans_security_asset() is
  'BEFORE INSERT novel global-OR-matched-tenant fence on pfin.account_trans.security_id (ADR-011 Decision 3 CANONICAL instance #7 / Pattern 2 site 1; ADR-027). A referenced asset is valid iff GLOBAL (pfin.asset.users_id IS NULL — market securities/currencies, legal for any tenant) OR OWNED by the account''s tenant (asset.users_id = account.users_id, resolved via account_id JOIN since account_trans has no own users_id). NULL-safe fail-closed (NOT EXISTS → raise). SECURITY INVOKER + set search_path = '''' — but the fence does NOT rely on RLS: it is the SOLE gate on the service_role provider-sync ingest path (008 grants service_role INSERT; service_role bypasses RLS but NOT triggers), so the explicit JOIN-to-account predicate is authoritative there; under authenticated it composes with 016''s asset RLS as belt-and-suspenders. BEFORE INSERT only (matches 004''s sibling fence on this immutable table — UPDATE/DELETE are 004-blocked for all roles, so an UPDATE fence would be dead). Trigger (not a bare CHECK) because it subqueries asset+account. NOT a DEFINER allowlist entry (INVOKER); allowlist stays 3.';

create trigger account_trans_security_asset
  before insert on pfin.account_trans
  for each row
  when (new.security_id is not null)
  execute function pfin.fn_account_trans_security_asset();

-- ----------------------------------------------------------------------------
-- (C) fn_ingest_transactions — the bulk-ingest INVOKER RPC (R-15 + OWD-D).
-- SECURITY INVOKER / authenticated / RLS-enforced (NOT service_role). All-or-nothing:
-- a single set-based insert…select from jsonb_to_recordset with ON CONFLICT (provider
-- dedup) DO NOTHING; a hard error (NaN / security fence / any CHECK) aborts the WHOLE
-- batch (fix-the-mapper-and-re-run, R-7). One round-trip, atomic. Inserts under the
-- caller's RLS (account_trans_insert wr_access-JOIN, 006) + the security_id fence +
-- the NaN/quantity CHECKs per row.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_ingest_transactions(p_rows jsonb)
returns table (inserted integer, skipped integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_total    integer;
  v_inserted integer;
begin
  -- Total input rows (a non-array p_rows raises here — bad input aborts, correct).
  select count(*)::integer into v_total
  from jsonb_array_elements(p_rows);

  -- Set-based insert. jsonb_to_recordset shreds the array into typed rows. COALESCE the
  -- NOT-NULL-with-DEFAULT columns because an explicit NULL from the jsonb bypasses the
  -- column DEFAULT (the DEFAULT only applies when the column is OMITTED from the INSERT
  -- target list — here it is present). Cash rows → quantity=0/security_id NULL; security
  -- rows → quantity=±shares/security_id set (the qty_requires_security CHECK enforces).
  with parsed as (
    select *
    from jsonb_to_recordset(p_rows) as x(
      account_id        bigint,
      transaction_date  date,
      amount            numeric,
      vendor            text,
      description       text,
      transaction_type  text,
      security_id       bigint,
      quantity          numeric,
      cost_basis        numeric,
      price             numeric,
      source_provider   text,
      provider_txn_id   text,
      provider_category text,
      import_hash       text
    )
  ),
  ins as (
    insert into pfin.account_trans (
      account_id, transaction_date, amount, vendor, description,
      transaction_type, security_id, quantity, cost_basis, price,
      source_provider, provider_txn_id, provider_category, import_hash
    )
    select
      p.account_id, p.transaction_date, p.amount, p.vendor, p.description,
      coalesce(p.transaction_type, 'standard'),
      p.security_id,
      coalesce(p.quantity, 0),
      p.cost_basis, p.price,
      p.source_provider, p.provider_txn_id, p.provider_category, p.import_hash
    from parsed p
    -- Dedup on the provider key (account_trans_provider_dedup_idx). Rows with
    -- provider_txn_id IS NULL bypass this arbiter and always insert (their dedup, if
    -- any, is the KEPT import_hash unique index — a HARD constraint that aborts the
    -- batch on a dup, consistent with all-or-nothing / fix-and-re-run).
    on conflict (source_provider, provider_txn_id) where provider_txn_id is not null
    do nothing
    returning 1
  )
  select count(*)::integer into v_inserted from ins;

  return query select v_inserted, (v_total - v_inserted);
end;
$$;

-- Functions grant EXECUTE to PUBLIC by default — revoke (denies anon), grant to
-- authenticated only (mirrors 013). Ingest is authenticated-tier; anon must not reach it.
revoke execute on function pfin.fn_ingest_transactions(jsonb) from public;
grant execute on function pfin.fn_ingest_transactions(jsonb) to authenticated;

comment on function pfin.fn_ingest_transactions(jsonb) is
  'SECURITY INVOKER bulk-ingest RPC (ADR-027 / R-15 + OWD-D). Atomically inserts a jsonb array of transaction rows into pfin.account_trans under the caller''s RLS (account_trans_insert wr_access-JOIN, 006), RETURNING (inserted, skipped). ALL-OR-NOTHING: set-based insert…select from jsonb_to_recordset with ON CONFLICT (source_provider, provider_txn_id) WHERE provider_txn_id IS NOT NULL DO NOTHING (the provider-dedup index); a hard error (NaN / the security_id global-OR-owned fence / the quantity_requires_security CHECK / matched-account) aborts the WHOLE batch — fix the mapper and re-run (R-7). inserted = rows actually landed; skipped = rows deduped by ON CONFLICT. Cash rows → quantity=0/security_id NULL; security rows → quantity=±shares/security_id set. NOT service_role (R-15 — this is the txn-row ingest path only; provider credential writes stay service_role on linked_source); NOT a DEFINER allowlist entry (INVOKER) → allowlist stays 3. set search_path = '''' injection fence; all refs schema-qualified. EXECUTE revoked from PUBLIC, granted to authenticated (anon denied). Signature is an API contract (PostgREST /rpc; pfin is [api]-exposed per ADR-023). NOTE: rows with provider_txn_id IS NULL are not deduped by ON CONFLICT — import_hash (KEPT) is their hard-unique guard (aborts on dup, per all-or-nothing).';

-- ============================================================================
-- Migration: pfin.eod_price (best-available price-observation store) + the UNIFORM
--            ROLL-FORWARD valuation core: holdings_checkpoint.security_id FK un-defer
--            (+ novel fence, Decision-3 #11) + fn_holdings_as_of (roll-forward) +
--            fn_compute_nav (uniform qty × eod_price × fx) + the cash latest view.
-- Phase 6 Build Loop (ADR-027 ingest/valuation substrate, migration 019 of 015–021;
--   design CLOSED + Sec-cleared 2026-07-14, then the valuation MODEL re-ratified by F/CTO
--   2026-07-15 through THREE amendments: (1) FMP-free [superseded]; (2) Rule A either/or
--   [superseded]; (3) UNIFORM ROLL-FORWARD [current, ratified 2026-07-15] — see the
--   ADR-027 "2026-07-15 / 019 — uniform roll-forward" amendment). JOINT-REVIEW-MANDATORY:
--   the eod_price write-authz WITH CHECK (Sec-classified) + the NEW holdings_checkpoint
--   .security_id novel global-OR-matched-tenant fence (Decision-3 instance #11, site 3 —
--   load-bearing under the service_role provider-sync write path) + C6 exposure-gating.
--
-- THE RATIFIED VALUATION MODEL (uniform roll-forward, F/CTO 2026-07-15 — "the durable
--   model, won't rearchitect"):
--   (1) QUANTITY = latest holdings_checkpoint (per (account, security_id), ≤ as_of) as a
--       SCOPING ANCHOR + Σ(account_trans strictly AFTER that checkpoint's as_of_date, ≤
--       as_of). No checkpoint → Σ all txns. Same pattern for cash (account_balance_
--       checkpoint anchor + Σ later amounts).
--   (2) VALUE = quantity × eod_price(as_of) UNIFORMLY for every account type — NO
--       balance-direct path, NO aggregator-vs-ledger special case, ONE formula everywhere.
--   (3) eod_price is populated from the PROVIDER-IMPLIED price (balance÷quantity from
--       holdings_checkpoint; the WORKER writes it — task #12) + manual + future FMP/APIs.
--       When multiple sources price the same (asset, date), a SOURCE-PRIORITY heuristic
--       selects one. The priority mechanism IS the accuracy-upgrade path: provider-implied
--       is the always-available FLOOR (NOT a true EOD close — providers snapshot mid-day);
--       dropping in an exact source later at higher priority upgrades every asset it covers
--       with ZERO rearchitecture.
--
-- WHAT THIS DOES:
--   (A) CREATEs pfin.eod_price — the best-available price-observation store (the 005-named
--       NAV prerequisite). OWD-A grain UNCHANGED: surrogate price_id PK +
--       unique(asset_id, price_date, source). Source vocab EXTENDED (+provider_implied,
--       additive ADR-022). MUTABLE (OWD-E). 014 NaN fence. Hybrid RLS (read: asset
--       global-OR-owned; write: authenticated manual_valuation on OWNED assets only +
--       service_role global/provider writer).
--   (E) UN-DEFERS pfin.holdings_checkpoint.security_id (nullable FK → pfin.asset) + its
--       NOVEL global-OR-matched-tenant fence (Decision-3 #11, site 3; mirrors 017's
--       account_trans.security_id #7). Was slated V1.3; SD-A1 pulls it into V1 so the
--       uniform model can key checkpoint quantity by asset (no read-time symbol→asset
--       join). The WORKER resolves symbol→security_id at ingest.
--   (B) fn_holdings_as_of(date) — INVOKER ROLL-FORWARD read (Lock 11): per (account, asset)
--       = latest checkpoint qty (≤ as_of) + Σ(strictly-after txn qty-deltas). No checkpoint
--       → Σ all. Returns (account_id, asset_id, quantity).
--   (C) fn_compute_nav(date) — INVOKER uniform valuation read (Lock 11; the 005-named
--       helper): net worth = Σ(qty × eod_price(D-FIRST priority) × fx) [securities] +
--       Σ(rolled-forward cash balance × fx) [cash]. ONE formula; liabilities R-7 signed.
--   (D) pfin.account_balance_checkpoint_latest — the 018 forward-flagged cash latest-
--       balance view. security_invoker = true (merge-block #2/#8).
--
-- Numbering: 019 follows 018. Depends on 016 (pfin.asset — eod_price + holdings_checkpoint
--   .security_id FK target; the hybrid RLS the read/fence mirror; the currency-asset seed
--   the FX leg joins), 017 (account_trans investment cols + the 017 novel-fence PRECEDENT
--   this fence mirrors), 018 (both provider snapshots — the roll-forward anchors), 006
--   (account_trans rd_access-JOIN RLS), 005 (holdings_checkpoint — the ALTER target; its
--   append-only immutability triple-fence means the new security fence is BEFORE INSERT
--   only), 003 (pfin.account — direct-owner RLS + the JOIN target resolving tenancy for the
--   fence), 014 (NaN idiom), 001 (pfin schema + fn_refresh_updated_at). config.toml exposes
--   pfin to [api] (ADR-023) → C6 exposure-gating binds. Downstream: the WORKER (task #12,
--   Backend/Worker) writes provider_implied eod_price rows via the existing service_role
--   grant; 020/021 (categorization) do NOT depend on 019.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list). Read Decision 4 verbatim before drafting (done). ZERO
--   catalogued §10 instances; the ledger STAYS at 2 (RT-22 + RT-26).
--   (i)   Instance-numbering: RT-22 first, RT-26 second — unchanged (not touched).
--   (ii)  Layer-attribution: the eod_price service_role SELECT+INSERT+UPDATE grant (the
--         global/provider-implied writer) is a DB-LAYER ACL — NOT the RT-26 code-layer
--         SUPABASE_SERVICE_ROLE_KEY allowlist grep fence, NOT the RT-22 container fence.
--         Identical reasoning to 007/008/015/017/018. The WORKER that writes provider_implied
--         rows (task #12) is an ALREADY-allowlisted service_role code consumer (the
--         provider-sync path that already writes holdings_checkpoint) — it adds NO new RT-26
--         file. The two read fns are INVOKER/authenticated → touch NO service_role surface.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated. 019 is not the anchor.
--   DE-CONFLATION GUARD: the holdings_checkpoint.security_id novel fence is a Decision-3
--   mechanism; the eod_price write-authz WITH CHECK is Decision-3-ADJACENT (Sec-classified);
--   the NaN CHECK is a Decision-2-adjacent value invariant — NONE is a §10 catalogued
--   instance (same separation as SELF-187's DEFINER-allowlist 2→3 being distinct from §10).
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — family COUNT 7 → 8. This migration
--   REALIZES canonical instance #11 (NOT #8 — see the numbering note):
--     - pfin.holdings_checkpoint.security_id → pfin.asset(asset_id) = the NOVEL
--       global-OR-matched-tenant fence, Pattern-2 SITE 3 (site 1 = account_trans.security_id
--       #7 @017; site 2 = user_asset_category.asset_id #9 @020). Under 016's G1 hybrid
--       registry a referenced asset is valid IFF GLOBAL (users_id IS NULL) OR OWNED by the
--       account's tenant (asset.users_id = account.users_id, resolved via account_id JOIN —
--       holdings_checkpoint has no own users_id). Fenced by fn_holdings_checkpoint_security_
--       asset (BEFORE INSERT), the SOLE gate under the service_role provider-sync write path
--       (005/008 grant; RLS bypassed). Mirrors 017 fn_account_trans_security_asset exactly.
--     NUMBERING NOTE (ledger-drift avoidance): this instance's CANONICAL LABEL is #11, NOT
--       #8. 018's committed header + ADR-027 (g) already pre-label holdings_checkpoint
--       .security_id as "canonical 11 / 3rd novel-fence site (deferred V1.3)"; 015/017/018
--       all forward-enumerate #8/#9/#10 as the 020/021 instances. SD-A1 pulls this fence
--       from its V1.3 slot into V1 — so the family COUNT moves 7 → 8 (8 realized: baseline
--       5 + #6[015] + #7[017] + #11[019]) while the LABEL stays #11 and the 020/021 labels
--       (#8/#9/#10) are UNCHANGED (no committed-header renumber, no drift). Canonical
--       enumeration for Sec to verify:
--         #1 reconciliation_event_trans          [Lock 9]
--         #2 account_trans.replaces_trans_id     [004]
--         #3 monthly_report.included_..._ids[]   [Lock 11]
--         #4 monthly_report_account_snapshot     [Lock 12]
--         #5 account.sub_cat_id                  [012]
--         #6 account.linked_source_id            [015]
--         #7 account_trans.security_id           [017, novel site 1]
--         #8 user_asset_category.sub_cat_id      [020, future]
--         #9 user_asset_category.asset_id        [020, novel site 2, future]
--        #10 account_trans_annotation.sub_cat_id [021, future]
--        #11 holdings_checkpoint.security_id     ← THIS [019, novel site 3; was V1.3]
--     NOT Decision-3 (evaluated): eod_price.asset_id = SOLE anchor (tenancy via asset-JOIN
--       RLS; write-authz WITH CHECK Sec-CLASSIFIED but not a family member); holdings_
--       checkpoint.account_id = SOLE anchor (evaluated 005); the read fns author no FK.
--   Sec numbering sign-off at joint-review (D3 extension → mandatory).
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — allowlist STAYS 3 (ADR-011 Decision 9). ZERO new SECURITY DEFINER.
--   fn_holdings_checkpoint_security_asset (the fence) — SECURITY INVOKER, set search_path
--     = ''. ***LOAD-BEARING UNDER service_role*** (holdings_checkpoint is written by the
--     provider-sync worker under service_role; triggers FIRE regardless of BYPASSRLS, so
--     this trigger — not RLS — is the SOLE fence). Explicit JOIN-to-account predicate
--     (asset global OR asset.users_id = account.users_id); NULL-safe fail-closed. BEFORE
--     INSERT only (005 blocks UPDATE/DELETE for all roles → an UPDATE fence would be dead;
--     matches 017). Touches only a read → no elevation → INVOKER → not a DEFINER entry.
--   fn_holdings_as_of / fn_compute_nav — INVOKER (Lock 11 read-composition): run as the
--     CALLER, every base read scoped to the caller's tenant by-construction.
--   The eod_price updated_at trigger reuses the EXISTING fn_refresh_updated_at (001,
--     allowlist entry #1) — no new entry. The latest-balance VIEW is security_invoker = true
--     (merge-block #2 — a non-invoker view would leak every tenant's cash balances).
--
-- ----------------------------------------------------------------------------
-- ONE-WAY DOORS (flagged for F/CTO; all pre-ratified 2026-07-15):
--   (1) eod_price GRAIN (OWD-A) — surrogate price_id PK + unique(asset_id, price_date,
--       source). UNCHANGED by the uniform-model amendment (provider_implied slots in by
--       source). Data one-way-door once backfill/provider rows land.
--   (2) eod_price MUTABLE (OWD-E) — manual rows editable; provider/market rows upserted.
--   (3) NEW — holdings_checkpoint.security_id FK UN-DEFER (SD-A1, was V1.3). Adding the
--       nullable FK is DDL-safe on the empty append-only table (ADD COLUMN does not fire
--       005's block-mutation/block-truncate triggers). Once provider snapshots with resolved
--       security_id land it becomes a data one-way-door. The load-bearing durable commitment
--       is the WORKER symbol→asset_id resolution invariant (unresolved symbol → security_id
--       NULL → that position is unvalued, drops from NAV until resolved).
--   (4) source-vocab +provider_implied (additive CHECK per ADR-022). Once provider_implied
--       rows land, the "best-available, source-priority-resolved" semantic is imprinted.
--
-- ----------------------------------------------------------------------------
-- RATIFIED VALUATION DECISIONS (uniform roll-forward; F/CTO 2026-07-15 — SUPERSEDES the
--   earlier Rule A / FMP-free decisions of this file's prior drafts):
--   (V-1) UNIFORM qty × eod_price. No balance-direct, no COALESCE either/or, no aggregator
--       special case. qty = roll-forward (V-2); value = qty × best-available price × fx.
--   (V-2) ROLL-FORWARD. Quantity/balance = latest checkpoint (SCOPING ANCHOR, ≤ as_of) +
--       Σ(txns STRICTLY AFTER the checkpoint's as_of_date, ≤ as_of). No checkpoint → Σ all.
--       Per (account, asset) for securities (fn_holdings_as_of); per account for cash.
--   (V-3) SOURCE-PRIORITY = manual_valuation > exact_feed (market_feed/spot_feed/fx_feed) >
--       provider_implied (floor). HARDCODED rank (ORDER BY CASE) — no registry (a source
--       carries no per-value metadata → does not clear the ADR-024 promote-to-table bar; a
--       registry, if ever, is global shared-read reference like tax_character → NOT D3).
--   (V-4) SELECTION = D-FIRST: latest price_date ≤ as_of wins ACROSS all sources; a
--       SAME-DATE tie is broken by the source rank (V-3). So an exact price on date D beats
--       a provider_implied on date D, but the freshest observation wins across dates.
--   (V-5) LIABILITIES R-7 signed (owed = negative; the rolled-forward balance is naturally
--       negative — no account_type branch). FX: USD ≡ 1.0; non-USD via the currency-asset's
--       fx_feed eod_price (LOCF), COALESCE 1.0 on a missing rate (V1 USD-dominant).
--   (V-6) DOUBLE-COUNT EDGES (documented, NOT built): a txn dated ≤ the checkpoint the
--       balance does not yet reflect (posted-before-cleared) → transient under-count; a txn
--       dated > the checkpoint the balance already reflects (provider clock-skew/forward-
--       dating) → transient double-count. Self-corrects at the next sync for pure-aggregator.
--       Audit-robust fix = V1.3 RECONCILIATION (Lock 9 — txn↔checkpoint-date matching). Not
--       V1. An unpriced asset (no eod_price ≤ as_of, and no provider_implied yet) → NULL
--       term → SUM drops it → 0 ("needs valuation"), never NaN.
--   (V-7) eod_price SEMANTIC = "best-available price observation per (asset, date, source),
--       source-priority-resolved." provider_implied rows are balance÷qty (an implied average,
--       NOT a true EOD close); manual/seed/FMP rows are as-entered/as-traded.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.eod_price — best-available price-observation store (ADR-027 §5). MUTABLE (OWD-E).
--     Columns (price_id PK, asset_id → pfin.asset ON DELETE CASCADE [SOLE anchor], price_date,
--     source CHECK [+provider_implied], price numeric(20,4) [NaN-fenced], created_at,
--     updated_at). unique(asset_id, price_date, source). RLS: read = asset global-OR-owned;
--     write = authenticated manual_valuation on OWNED assets only (WITH CHECK) + service_role
--     global/provider writer (DB-ACL). C6 exposure-gated.
--   pfin.holdings_checkpoint (existing, 005/018) — GAINS security_id (nullable FK → pfin.asset
--     ON DELETE RESTRICT). Novel global-OR-matched-tenant fenced (Decision-3 #11). symbol KEPT
--     (display/audit); the WORKER resolves symbol→security_id.
--   pfin.fn_holdings_checkpoint_security_asset() — BEFORE INSERT WHEN (security_id IS NOT
--     NULL); INVOKER; set search_path=''; NULL-safe fail-closed; global-OR-owned predicate
--     resolving tenant via account JOIN. SOLE fence under service_role. Mirrors 017.
--   pfin.fn_holdings_as_of(p_as_of date) RETURNS TABLE(account_id bigint, asset_id bigint,
--     quantity numeric) — SECURITY INVOKER; set search_path=''; ROLL-FORWARD (V-2): latest
--     checkpoint qty per (account, security_id) + Σ strictly-after txn qty; live holdings
--     (qty <> 0). RLS-scoped (holdings_checkpoint + account_trans rd_access-JOIN).
--   pfin.fn_compute_nav(p_as_of date) RETURNS numeric — SECURITY INVOKER; set search_path='';
--     UNIFORM net worth in USD = Σ(fn_holdings_as_of qty × eod_price[D-first, V-3/V-4] × fx)
--     + Σ(rolled-forward cash balance × fx). Liabilities R-7 signed. EXECUTE to authenticated.
--   pfin.account_balance_checkpoint_latest — VIEW, security_invoker = true (018 forward-flag).
--   Security-load-bearing edges: the holdings_checkpoint.security_id fence is the SOLE gate on
--     the service_role provider-sync path; the eod_price write-authz WITH CHECK is the SOLE
--     gate keeping a user from injecting a fake global/provider price; all valuation reads
--     compose under the caller's RLS (INVOKER); NaN fence role-agnostic; the latest view
--     inherits caller RLS. C6-GATED: the eod_price grants + the new fence require QA's §4.5
--     two-tenant battery (cross-tenant read + write fail-closed) BEFORE V1-SHIP-BLOCK merge.
-- ============================================================================

create schema if not exists pfin;
-- service_role + authenticated schema USAGE persist from 008 / 001.

-- ----------------------------------------------------------------------------
-- (A) pfin.eod_price — best-available price-observation store (OWD-A grain; MUTABLE OWD-E).
-- ----------------------------------------------------------------------------
create table if not exists pfin.eod_price (
  price_id    bigint generated always as identity primary key,
  asset_id    bigint not null references pfin.asset (asset_id) on delete cascade,  -- SOLE anchor (tenancy via asset-JOIN RLS)
  price_date  date not null,                                                        -- observation date; LOCF key
  source      text not null
                check (source in (
                  'market_feed', 'spot_feed', 'fx_feed',
                  'manual_valuation', 'provider_implied')),                         -- R-9 vocab + provider_implied (uniform-model amendment)
  price       numeric(20,4) not null,                                               -- native-currency price observation (NaN-fenced)
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint eod_price_price_finite check (price <> 'NaN'::numeric),                -- 014 idiom
  unique (asset_id, price_date, source)                                             -- OWD-A: sources coexist, provenance-distinct
);

comment on table pfin.eod_price is
  'Best-available price-observation store (ADR-027 §5; the 005-named NAV prerequisite). One '
  'row = a price observation for an asset on a date FROM a source. Consumed by fn_compute_nav '
  'via D-FIRST source-priority LOCF (latest price_date ≤ as_of; same-date tie → source rank '
  'manual_valuation > exact_feed > provider_implied). SPARSE → last-observation-carried-'
  'forward. OWD-A grain (RATIFIED, one-way-door once rows land): surrogate price_id PK + '
  'unique(asset_id, price_date, source) so sources coexist provenance-distinct. NO currency '
  'column — currency is an asset-level property (016 asset.currency); USD-base valuation = '
  'native price × fx_rate (§5A). asset_id = SOLE tenant anchor (tenancy via the asset-JOIN '
  'read RLS; no own users_id) → NOT a matched-tenant Decision-3 instance. MUTABLE (OWD-E): '
  'manual valuations user-editable; market/provider rows upserted — deliberately NO '
  'immutability fence. V1 POPULATION (uniform-model amendment 2026-07-15): PROVIDER-IMPLIED '
  '(balance÷qty from holdings_checkpoint — the WORKER writes it, task #12) + MANUAL '
  '(authenticated) + F/CTO seed; FMP is a FUTURE higher-priority source (zero rearchitecture '
  'to add). Semantic (V-7): "best-available price observation, source-priority-resolved" — '
  'provider_implied rows are an implied average, NOT a true EOD close. Write-authz '
  '(Sec-classified): authenticated may CRUD only manual_valuation rows on assets they OWN '
  '(cannot inject a fake global/provider price); service_role writes global market/fx + '
  'provider_implied rows. C6 exposure-gated (ADR-023). Privileged-write posture note: the '
  'manual-owned WITH CHECK fence constrains AUTHENTICATED only — the superuser seed and '
  'service_role bypass RLS (trusted, Decision 1), the same posture as global market rows.';

comment on column pfin.eod_price.asset_id is
  'Nullable-free FK → pfin.asset(asset_id) ON DELETE CASCADE. SOLE tenant anchor: eod_price '
  'has no own users_id; tenancy derives via the asset-JOIN read RLS (a price is readable iff '
  'its asset is global OR owned by the caller). NOT a matched-tenant Decision-3 instance '
  '(no second anchor to mismatch — same reasoning as holdings_checkpoint.account_id). '
  'CASCADE: prices are dependent data.';
comment on column pfin.eod_price.source is
  'Price-observation source: market_feed / spot_feed / fx_feed (exact feeds, global) / '
  'manual_valuation (per-user) / provider_implied (balance÷qty from an aggregator '
  'holdings_checkpoint — the always-available FLOOR, global). Part of unique(asset_id, '
  'price_date, source) so sources coexist. Drives the D-FIRST priority tiebreak (V-3/V-4: '
  'manual_valuation > exact_feed > provider_implied) and the write-authz (authenticated may '
  'write ONLY manual_valuation; service_role writes the rest).';
comment on column pfin.eod_price.price is
  'A price observation for the asset on price_date in the asset''s NATIVE currency '
  '(numeric(20,4)). SEMANTIC (V-7, F/CTO 2026-07-15): "best-available price observation, '
  'source-priority-resolved" — NOT necessarily a true EOD close. provider_implied rows = '
  'balance÷quantity (an implied mid-day average). manual/seed/FMP rows = as-entered / '
  'as-traded (non-split-adjusted; split-adjusted series + split-as-ledger-event → V2 Stock '
  'Research, derivable then from as-traded + split events, never stored). For a currency-type '
  'asset (fx_feed) price is the USD-per-unit FX rate (§5A; USD ≡ 1.0 constant, not stored). '
  'NaN-fenced. Multiplied by quantity (securities) or applied as an FX multiplier (currencies) '
  'in fn_compute_nav.';

comment on constraint eod_price_price_finite on pfin.eod_price is
  'Rejects the numeric special value NaN on price (014-pattern DB-layer defense-in-depth; a '
  'NaN would poison every valuation SUM in fn_compute_nav). Role-agnostic table CHECK '
  '(service_role bypasses RLS but not CHECK). NOT NULL column, so no NULL-passes gap. '
  '±Infinity already rejected by numeric(20,4) coercion.';

-- LOCF lookup index (asset_id, price_date desc) — serves the D-FIRST "latest price_date ≤
-- as_of per asset" correlated subquery in fn_compute_nav (the source-rank tiebreak is applied
-- after the date ordering, in-memory over the few same-date rows).
create index if not exists eod_price_asset_date_idx
  on pfin.eod_price (asset_id, price_date desc);

alter table pfin.eod_price enable row level security;

-- READ RLS — asset global-OR-owned (mirrors 016 asset_select via a JOIN to the asset).
create policy eod_price_select on pfin.eod_price
  for select to authenticated
  using (exists (
    select 1 from pfin.asset a
    where a.asset_id = eod_price.asset_id
      and (a.users_id is null or a.users_id = auth.uid())
  ));

comment on policy eod_price_select on pfin.eod_price is
  'SELECT: read a price iff its asset is GLOBAL (users_id IS NULL — market/fx/provider_implied '
  'reference shared by all authenticated) OR OWNED by the caller (per-user manual valuation). '
  'Mirrors 016 asset_select via an asset JOIN (eod_price has no own users_id → asset-anchored). '
  'security_invoker consumers (fn_compute_nav) inherit this scope.';

-- WRITE RLS (OWD-E — Sec-classified cross-tenant-write gate). authenticated may INSERT /
-- UPDATE / DELETE ONLY manual_valuation rows on assets they OWN (excludes global + provider
-- rows structurally: global/provider assets have users_id IS NULL ≠ auth.uid()).
create policy eod_price_insert on pfin.eod_price
  for insert to authenticated
  with check (
    source = 'manual_valuation'
    and exists (select 1 from pfin.asset a
                where a.asset_id = eod_price.asset_id and a.users_id = auth.uid())
  );

create policy eod_price_update on pfin.eod_price
  for update to authenticated
  using (
    source = 'manual_valuation'
    and exists (select 1 from pfin.asset a
                where a.asset_id = eod_price.asset_id and a.users_id = auth.uid())
  )
  with check (
    source = 'manual_valuation'
    and exists (select 1 from pfin.asset a
                where a.asset_id = eod_price.asset_id and a.users_id = auth.uid())
  );

create policy eod_price_delete on pfin.eod_price
  for delete to authenticated
  using (
    source = 'manual_valuation'
    and exists (select 1 from pfin.asset a
                where a.asset_id = eod_price.asset_id and a.users_id = auth.uid())
  );

comment on policy eod_price_insert on pfin.eod_price is
  'INSERT (OWD-E; Sec-classified write gate): a user may write ONLY a manual_valuation row on '
  'an asset they OWN. The own-asset predicate excludes global/provider rows (users_id NULL ≠ '
  'auth.uid()) → cannot inject a fake market/provider_implied price; source pin excludes the '
  'service_role sources. Sole-anchor → NOT a matched-tenant Decision-3 instance; an FK-shaped '
  'cross-tenant-WRITE fence Sec classifies at joint-review.';
comment on policy eod_price_update on pfin.eod_price is
  'UPDATE (OWD-E; MUTABLE manual rows): owner edits own manual valuations. USING scopes to own '
  'manual rows; WITH CHECK re-validates the post-image (blocks re-pointing asset_id or flipping '
  'source off manual_valuation). The own-manual-asset JOIN structurally excludes global rows.';
comment on policy eod_price_delete on pfin.eod_price is
  'DELETE (OWD-E): owner deletes own manual valuations only (own-manual-asset JOIN; global/'
  'provider rows structurally excluded).';

-- ACL-before-RLS (PR #106 gotcha). authenticated: full CRUD (RLS/policy-gated to manual-owned).
-- service_role: SELECT + INSERT + UPDATE (global market/fx + provider_implied upsert; no DELETE
-- — least privilege). anon: nothing (schema USAGE denies before ACL).
grant select, insert, update, delete on pfin.eod_price to authenticated;
grant select, insert, update on pfin.eod_price to service_role;

comment on column pfin.eod_price.updated_at is
  'Auto-refreshed via pfin.fn_refresh_updated_at (001, DEFINER allowlist entry #1) on UPDATE — '
  'manual re-valuations and market/provider upserts stamp it. Adds NO new DEFINER entry.';

create trigger eod_price_set_updated_at
  before update on pfin.eod_price
  for each row execute function pfin.fn_refresh_updated_at();

-- ----------------------------------------------------------------------------
-- (E) pfin.holdings_checkpoint.security_id — UN-DEFER the FK (SD-A1) + the NOVEL
--   global-OR-matched-tenant fence (Decision-3 #11, novel-fence site 3). ADD COLUMN is DDL
--   (does not fire the 005 append-only immutability triggers; the table is empty/greenfield).
--   Nullable: an unresolved provider symbol (SELF-200 blank-symbol / unmatched) lands
--   security_id NULL → that position is unvalued (drops from NAV) until the worker resolves it.
-- ----------------------------------------------------------------------------
alter table pfin.holdings_checkpoint
  add column if not exists security_id bigint
    references pfin.asset (asset_id) on delete restrict;

comment on column pfin.holdings_checkpoint.security_id is
  'Nullable FK → pfin.asset(asset_id) ON DELETE RESTRICT (ADR-027 uniform-model amendment '
  '2026-07-15; SD-A1 un-defer from V1.3). The resolved asset for a provider-reported position '
  '— the WORKER resolves symbol→security_id at ingest (auto-registering global assets); '
  'unresolved → NULL → unvalued. Decision-3 CANONICAL instance #11 / NOVEL global-OR-matched-'
  'tenant fence (Pattern-2 site 3): a referenced asset is valid IFF GLOBAL (users_id IS NULL) '
  'OR OWNED by the account''s tenant (asset.users_id = account.users_id, via account_id JOIN). '
  'Fenced by fn_holdings_checkpoint_security_asset (BEFORE INSERT), the SOLE gate under the '
  'service_role provider-sync write path (RLS bypassed). symbol is KEPT (display/audit). '
  'fn_holdings_as_of keys checkpoint quantity by security_id (no read-time symbol→asset join).';

create or replace function pfin.fn_holdings_checkpoint_security_asset()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Trigger WHEN clause guarantees new.security_id IS NOT NULL.
  -- GLOBAL-OR-OWNED predicate (Pattern 2). holdings_checkpoint has no own users_id → the
  -- tenant is resolved via account_id → pfin.account.users_id (the JOIN). NULL-safe
  -- fail-closed (NOT EXISTS → raise). LOAD-BEARING UNDER service_role: the provider-sync
  -- path writes checkpoints under service_role (RLS bypassed), so this trigger is the SOLE
  -- fence; the explicit JOIN-to-account predicate is authoritative there. Mirrors 017.
  if not exists (
    select 1
    from pfin.asset a
    join pfin.account acc on acc.account_id = new.account_id
    where a.asset_id = new.security_id
      and (a.users_id is null or a.users_id = acc.users_id)
  ) then
    raise exception
      'cross-tenant security rejected: security_id % is not a global or account-owned asset for account_id % (ADR-011 Decision 3 canonical instance #11 / novel global-OR-matched-tenant fence, Pattern 2 site 3)',
      new.security_id, new.account_id;
  end if;
  return new;
end;
$$;

revoke execute on function pfin.fn_holdings_checkpoint_security_asset() from public;

comment on function pfin.fn_holdings_checkpoint_security_asset() is
  'BEFORE INSERT novel global-OR-matched-tenant fence on pfin.holdings_checkpoint.security_id (ADR-011 Decision 3 canonical instance #11 / Pattern 2 site 3; ADR-027 uniform-model amendment 2026-07-15). A referenced asset is valid iff GLOBAL (pfin.asset.users_id IS NULL) OR OWNED by the account''s tenant (asset.users_id = account.users_id, resolved via account_id JOIN — holdings_checkpoint has no own users_id). NULL-safe fail-closed (NOT EXISTS → raise). SECURITY INVOKER + set search_path='''' — the fence does NOT rely on RLS: it is the SOLE gate on the service_role provider-sync ingest path (005/008 grant; service_role bypasses RLS but NOT triggers). BEFORE INSERT only (005 blocks UPDATE/DELETE for all roles → an UPDATE fence would be dead). Trigger (not a bare CHECK) because it subqueries asset+account. Mirrors 017 fn_account_trans_security_asset. NOT a DEFINER allowlist entry (INVOKER); allowlist stays 3.';

create trigger holdings_checkpoint_security_asset
  before insert on pfin.holdings_checkpoint
  for each row
  when (new.security_id is not null)
  execute function pfin.fn_holdings_checkpoint_security_asset();

-- ----------------------------------------------------------------------------
-- (B) fn_holdings_as_of — INVOKER ROLL-FORWARD quantity read (Lock 11; V-2).
-- Per (account, asset): latest checkpoint qty (≤ as_of, keyed by security_id) as the scoping
-- ANCHOR + Σ(account_trans.quantity strictly AFTER the anchor checkpoint's as_of_date, ≤
-- as_of). No checkpoint → anchor_date = -infinity → Σ all txns (pure ledger). Cash excluded
-- (cash rows carry security_id NULL / quantity 0 per the 017 CHECK). RLS-scoped to the caller
-- (holdings_checkpoint + account_trans rd_access-JOIN); INVOKER → runs as the caller.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_holdings_as_of(p_as_of date)
returns table (account_id bigint, asset_id bigint, quantity numeric)
language sql
security invoker
set search_path = ''
as $$
  with anchors as (
    -- latest resolved checkpoint per (account, security_id) ≤ as_of (the roll-forward anchor)
    select distinct on (hc.account_id, hc.security_id)
      hc.account_id, hc.security_id, hc.quantity as anchor_qty, hc.as_of_date as anchor_date
    from pfin.holdings_checkpoint hc
    where hc.security_id is not null and hc.as_of_date <= p_as_of
    order by hc.account_id, hc.security_id, hc.as_of_date desc, hc.checkpoint_id desc
  ),
  keys as (
    -- every (account, asset) pair that has an anchor OR any txn ≤ as_of
    select account_id, security_id from anchors
    union
    select at.account_id, at.security_id
    from pfin.account_trans at
    where at.security_id is not null and at.transaction_date <= p_as_of
  ),
  rolled as (
    select
      k.account_id,
      k.security_id as asset_id,
      coalesce(an.anchor_qty, 0)
      + coalesce((
          select sum(at.quantity)
          from pfin.account_trans at
          where at.account_id = k.account_id
            and at.security_id = k.security_id
            and at.transaction_date <= p_as_of
            and at.transaction_date > coalesce(an.anchor_date, '-infinity'::date)
        ), 0) as quantity
    from keys k
    left join anchors an
      on an.account_id = k.account_id and an.security_id = k.security_id
  )
  select account_id, asset_id, quantity
  from rolled
  where quantity <> 0;
$$;

revoke execute on function pfin.fn_holdings_as_of(date) from public;
grant execute on function pfin.fn_holdings_as_of(date) to authenticated;

comment on function pfin.fn_holdings_as_of(date) is
  'SECURITY INVOKER ROLL-FORWARD holdings read (ADR-027 §5 / Lock 11; uniform-model V-2). '
  'RETURNS (account_id, asset_id, quantity): per (account, security_id), the LATEST '
  'holdings_checkpoint quantity ≤ as_of (the scoping ANCHOR) + Σ(account_trans.quantity '
  'STRICTLY AFTER that checkpoint''s as_of_date, ≤ as_of); no checkpoint → Σ all txns (pure '
  'ledger). Live holdings only (qty <> 0). Keyed by security_id (018 un-deferred the FK, #11) '
  '— no read-time symbol→asset join. Cash naturally excluded (cash rows carry security_id '
  'NULL / quantity 0 per 017). RLS-scoped to the caller (holdings_checkpoint + account_trans '
  'rd_access-JOIN) — INVOKER runs as the caller. STRICTLY-AFTER boundary (> anchor_date) '
  'assumes the checkpoint reflects same-and-earlier-dated txns; residual sync-lag/skew edges '
  '(V-6) → V1.3 reconciliation. Consumed by fn_compute_nav''s security leg. set search_path '
  '= ''''; NOT a DEFINER allowlist entry (INVOKER) → allowlist stays 3.';

-- ----------------------------------------------------------------------------
-- (C) fn_compute_nav — INVOKER UNIFORM roll-forward valuation (Lock 11; 005-named; V-1..V-5).
-- net_worth(USD) = Σ(security qty × best-available price × fx) + Σ(rolled-forward cash × fx).
-- ONE formula; no balance-direct, no COALESCE either/or. Every base read composes under the
-- caller's RLS (INVOKER): pfin.account (direct-owner), account_trans / holdings_checkpoint /
-- account_balance_checkpoint (rd_access-JOIN), eod_price / asset (global-OR-owned).
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_compute_nav(p_as_of date)
returns numeric
language sql
security invoker
set search_path = ''
as $$
  with security_leg as (
    -- Uniform qty × best-available price × fx. qty = roll-forward (fn_holdings_as_of, V-2).
    -- price = D-FIRST (V-4): latest price_date ≤ as_of; SAME-DATE tie broken by source rank
    -- (V-3: manual_valuation 1 > exact_feed 2 > provider_implied 3). An asset with no priced
    -- row ≤ as_of → NULL → SUM drops it → 0 ("needs valuation"). Never NaN.
    select coalesce(sum(
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
                  end
         limit 1)
      * case when a.currency = 'USD' then 1.0
             else coalesce((
               select fx.price from pfin.eod_price fx
               join pfin.asset ca on ca.asset_id = fx.asset_id
               where ca.users_id is null and ca.asset_type = 'currency'
                 and ca.symbol = a.currency and fx.source = 'fx_feed'
                 and fx.price_date <= p_as_of
               order by fx.price_date desc limit 1), 1.0) end
    ), 0) as v
    from pfin.fn_holdings_as_of(p_as_of) h
    join pfin.asset a on a.asset_id = h.asset_id
  ),
  cash_leg as (
    -- Uniform: cash = the currency-asset; qty = ROLLED-FORWARD balance (account_balance_
    -- checkpoint anchor ≤ as_of + Σ amounts strictly AFTER the anchor's as_of_date; no
    -- checkpoint → Σ all amounts ≤ as_of), price = fx rate (USD ≡ 1.0). Liabilities R-7
    -- signed (owed = negative; the rolled-forward balance is naturally negative — no branch).
    select coalesce(sum(
      (
        coalesce((select cbc.balance
                  from pfin.account_balance_checkpoint cbc
                  where cbc.account_id = acc.account_id and cbc.as_of_date <= p_as_of
                  order by cbc.as_of_date desc, cbc.balance_id desc
                  limit 1), 0)
        + coalesce((select sum(at.amount)
                    from pfin.account_trans at
                    where at.account_id = acc.account_id
                      and at.transaction_date <= p_as_of
                      and at.transaction_date > coalesce((
                        select cbc2.as_of_date
                        from pfin.account_balance_checkpoint cbc2
                        where cbc2.account_id = acc.account_id and cbc2.as_of_date <= p_as_of
                        order by cbc2.as_of_date desc, cbc2.balance_id desc
                        limit 1), '-infinity'::date)), 0)
      )
      * case when acc.currency = 'USD' then 1.0
             else coalesce((
               select fx.price from pfin.eod_price fx
               join pfin.asset ca on ca.asset_id = fx.asset_id
               where ca.users_id is null and ca.asset_type = 'currency'
                 and ca.symbol = acc.currency and fx.source = 'fx_feed'
                 and fx.price_date <= p_as_of
               order by fx.price_date desc limit 1), 1.0) end
    ), 0) as v
    from pfin.account acc
  )
  select (select v from security_leg) + (select v from cash_leg);
$$;

revoke execute on function pfin.fn_compute_nav(date) from public;
grant execute on function pfin.fn_compute_nav(date) to authenticated;

comment on function pfin.fn_compute_nav(date) is
  'SECURITY INVOKER UNIFORM roll-forward net-worth read (ADR-027 §5 / Lock 11; the 005-named '
  'fn_compute_nav; uniform-model amendment 2026-07-15, SUPERSEDES the prior Rule A draft). '
  'RETURNS net worth in USD as of p_as_of = Σ(security qty × best-available price × fx) '
  '[securities] + Σ(rolled-forward cash balance × fx) [cash]. ONE formula, no balance-direct, '
  'no COALESCE either/or, no aggregator special case (V-1). QUANTITY = roll-forward (V-2: '
  'latest checkpoint anchor + Σ strictly-after txns; fn_holdings_as_of for securities, inline '
  'for cash). PRICE = D-FIRST source-priority (V-3/V-4): latest price_date ≤ as_of; same-date '
  'tie → rank manual_valuation > exact_feed(market/spot/fx) > provider_implied (floor). '
  'provider_implied (balance÷qty, worker-written) is the always-available floor; exact sources '
  'upgrade it with zero rearchitecture. LIABILITIES R-7 signed (V-5; owed = negative — no '
  'account_type branch). FX (§5A): USD ≡ 1.0; non-USD via the currency-asset''s fx_feed '
  'eod_price (LOCF), COALESCE 1.0 on a missing rate. An unpriced asset → NULL term → SUM drops '
  'it → 0 ("needs valuation"), never NaN. DOUBLE-COUNT EDGES (V-6): the strictly-after '
  'boundary has residual sync-lag/clock-skew edges (transient over/under-count) → audit-robust '
  'fix = V1.3 reconciliation (Lock 9); NOT built. All base reads compose under the CALLER''s '
  'RLS (INVOKER): pfin.account direct-owner; account_trans / holdings_checkpoint / '
  'account_balance_checkpoint rd_access-JOIN; eod_price / asset global-OR-owned. set '
  'search_path = ''''; NOT a DEFINER allowlist entry (INVOKER) → allowlist stays 3. EXECUTE '
  'revoked from PUBLIC, granted to authenticated. READ function (CREATE OR REPLACE-reversible).';

-- ----------------------------------------------------------------------------
-- (D) pfin.account_balance_checkpoint_latest — the 018 forward-flagged cash latest-balance
-- view. security_invoker = true (Sec merge-block #2/#8): inherits the CALLER's RLS so an
-- authenticated read sees only owned rows; a non-invoker view would leak every tenant's cash
-- balances. Mirrors 018's holdings_checkpoint_latest. Current-snapshot convenience surface
-- (app/reports); fn_compute_nav's as-of path LOCFs the base table directly.
-- ----------------------------------------------------------------------------
create or replace view pfin.account_balance_checkpoint_latest
  with (security_invoker = true) as
  select distinct on (account_id, source)
    balance_id,
    account_id,
    balance,
    currency,
    as_of_date,
    source,
    created_at
  from pfin.account_balance_checkpoint
  order by account_id, source, as_of_date desc, balance_id desc;

comment on view pfin.account_balance_checkpoint_latest is
  'Latest per-(account, source) provider cash-balance snapshot (ADR-027 / 019; the 018 '
  'forward-flag deferral — Sec merge-block #2/#8). DISTINCT ON (account_id, source) ordered '
  'by as_of_date desc, balance_id desc. security_invoker = true: inherits the CALLER''s RLS, '
  'so authenticated reads are scoped by 018 account_balance_checkpoint_select (rd_access-JOIN, '
  'owned rows only); service_role sees all. A non-invoker (owner-semantics) view would leak '
  'EVERY tenant''s cash balances. Current-snapshot convenience surface (app/reports); '
  'fn_compute_nav''s roll-forward cash leg LOCFs the base account_balance_checkpoint directly '
  '(as_of_date ≤ p_as_of) for as-of-date correctness (the view cannot express ≤ as_of).';

grant select on pfin.account_balance_checkpoint_latest to authenticated;

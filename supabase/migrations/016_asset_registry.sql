-- ============================================================================
-- Migration: pfin.asset — UNIVERSAL asset registry (hybrid global + per-user).
-- Phase 6 Build Loop (ADR-027 ingest/valuation substrate, migration 016 of 015–021;
--   design CLOSED + Sec-cleared 2026-07-14: temp/015-architect-design-spec.md PART B
--   (the 016 row) + PART C (NOT-D3 exclusions) + PART D (D-f currency-asset seed home)
--   + temp/015-ingest-substrate-design.md §16 R-9 / R-10 / R-16 + the GRAIN/CASH THREAD
--   RESOLVED block). JOINT-REVIEW-MANDATORY (hybrid global-OR-owned RLS — the novel
--   posture; the batch's merge-block 6).
--
-- WHAT THIS DOES:
--   Creates pfin.asset, the universal asset-definition registry — EVERY asset kind
--   (securities, funds, real estate, vehicles, metals, collectibles, crypto,
--   currencies, custom/private) — carrying identity + an asset_type discriminator +
--   a pricing_source discriminator (HOW eod_price is populated at 019). It is a
--   HYBRID table: users_id NULLABLE — NULL rows are GLOBAL (market securities,
--   currencies — shared reference data), non-NULL rows are PER-USER (this user's
--   house / boat / custom asset). The two populations coexist under one hybrid RLS
--   posture (global-OR-owned SELECT; owner-only write).
--   CASH MODEL (R-16 / GRAIN-CASH-RESOLVED): cash is NOT a distinct asset_type — it
--   is the global USD currency-asset (asset_type='currency', pricing_source='fx_feed').
--   'cash' is therefore DROPPED from the R-9 asset_type CHECK vocab (redundant with
--   'currency'; greenfield, nothing references it). 'currency' is the canonical
--   unit-of-account type. See asset_type CHECK below (R-9 delta stated inline).
--   This migration also COMMITS the canonical currency-asset identity rows
--   (USD + majors) — non-personal global reference data, 011-style (OWD open-choice
--   (c) / PART D D-f). It seeds NO securities and NO physical assets (those await
--   F/CTO's registry export — a DATA blocker; 016's DDL is data-independent).
--
-- Numbering: 016 follows 015 (linked_source fold). Depends on 001 (pfin schema +
--   fn_refresh_updated_at, reused for the updated_at trigger) and auth.users (the
--   users_id anchor). References no other pfin table. Downstream: 017
--   (account_trans.security_id → pfin.asset, the novel global-OR-matched-tenant
--   fence), 019 (eod_price.asset_id → pfin.asset), 020 (user_asset_category.asset_id
--   → pfin.asset) all depend on 016 landing first. config.toml already exposes pfin
--   to [api] schemas (ADR-023) — pfin.asset is internet-facing the moment it is
--   granted, so C6 exposure-gating binds (see GRANTS + EXPOSURE below).
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list). Read Decision 4 verbatim before drafting. This
--   migration introduces ZERO catalogued §10 instances; the ledger STAYS at 2
--   (RT-22 + RT-26 per ADR-011 Decision 4).
--   (i)   Instance-numbering: RT-22 first, RT-26 second — unchanged (not touched).
--   (ii)  Layer-attribution: no infrastructure-credential-presence surface (RT-22)
--         and no code-layer SUPABASE_SERVICE_ROLE_KEY allowlist surface (RT-26) is
--         touched. pfin.asset is an authenticated-tier RLS/GRANT base table +
--         committed reference seed. service_role is NOT granted here (see GRANTS
--         RATIONALE), so 008's DB-ACL posture is unchanged — and even a service_role
--         grant would be a DB-ACL change, NOT an RT-26 code-layer change, regardless.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated. 016 is not the
--         canonical §10 anchor.
--   DE-CONFLATION GUARD: the hybrid global-OR-owned RLS is a Decision-2/Decision-3-
--   adjacent tenancy mechanism, NOT a §10 catalogued instance (same separation as
--   SELF-187's DEFINER-allowlist 2→3 being distinct from §10). The FKs INTO
--   pfin.asset (the novel global-OR-matched-tenant fences) are authored at 017/020,
--   NOT here — see DECISION 3 below.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family count +0
--   (stays 6). This table has exactly ONE reference column:
--     pfin.asset.users_id → auth.users(id)
--   which IS the tenant anchor itself (a SOLE/direct owner anchor), not a
--   cross-tenant reference to another pfin row — so it carries NO matched-tenant
--   obligation (there is no second anchor to mismatch). NULL is legitimate (= a
--   global row owned by no tenant). No INTEGER[]/array FK, no self-FK, no
--   cross-table pfin FK on this table. Decision 3 family UNCHANGED at 6.
--   asset.currency is a TEXT ISO code (R-16: joined to the currency-asset for
--   valuation, but deliberately NOT an FK) → NOT D3. asset.symbol/name/cusip/figi/
--   isin/metadata are identity/text → NOT D3.
--   FORWARD-POINTER (per PART C): the FKs INTO pfin.asset are the novel
--   global-OR-matched-tenant fences and land with THEIR migrations, evaluated
--   THERE — NOT here:
--     • 017 account_trans.security_id → pfin.asset  = novel fence, site 1 (D3 #7)
--     • 020 user_asset_category.asset_id → pfin.asset = novel fence, site 2 (D3 #9)
--     • 019 eod_price.asset_id → pfin.asset          = SOLE anchor; write-authz
--                                                       Sec-classified (not classic
--                                                       matched-tenant)
--   The novel predicate (asset is valid iff global OR owned by the referencing
--   tenant) is a Sec-reviewed pattern; 016 defines only the referenced table, so it
--   adds no D3 instance — it merely establishes the hybrid registry those later
--   fences reference.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — NO function authored with elevated privilege.
--   This migration creates NO SECURITY DEFINER and NO SECURITY INVOKER function.
--   It is CREATE TABLE + partial-unique indexes + RLS policies + GRANTs + one
--   updated_at trigger wired to the EXISTING pfin.fn_refresh_updated_at (001,
--   already DEFINER allowlist entry #1) + a committed reference-data seed. The
--   SECURITY DEFINER allowlist is UNCHANGED at 3 (ADR-011 Decision 9): no new
--   DEFINER entry, no Sec-DEFINER-review trigger. `set search_path = ''` is N/A (a
--   function-body guard; this migration defines no function).
--
-- ----------------------------------------------------------------------------
-- GRANTS / RLS RATIONALE — HYBRID global-OR-owned; authenticated CRUD on OWN rows.
--   pfin.asset holds two populations under one table:
--     • GLOBAL rows (users_id IS NULL): market securities, currencies — canonical
--       reference data every authenticated tenant legitimately reads.
--     • PER-USER rows (users_id = a uuid): a user's physical/custom assets (house,
--       vehicle, collectible) — private to the owning tenant.
--   RLS (the novel hybrid posture — the Sec joint-review surface):
--     - SELECT: using (users_id IS NULL OR users_id = auth.uid()) — global rows
--       readable by all authenticated; per-user rows readable ONLY by their owner.
--     - INSERT: with check (users_id = auth.uid()) — a user may create ONLY OWN
--       (non-global) rows. A user CANNOT create a global row: users_id = NULL fails
--       `NULL = auth.uid()`, and users_id = <other uuid> fails the equality. Global
--       rows are authored by the committed migration seed (admin connection) and,
--       later, by service_role registry-enrichment (deferred — see below).
--     - UPDATE: using (users_id = auth.uid()) with check (users_id = auth.uid()) —
--       owner may edit OWN rows; the USING clause excludes global rows (NULL =
--       auth.uid() is not true, so global rows are invisible to the update path),
--       the WITH CHECK blocks repointing a row to global/another tenant.
--     - DELETE: using (users_id = auth.uid()) — owner may delete OWN rows only;
--       global rows are not user-deletable.
--   This is the R-9/§4 "users add own custom/physical rows; global rows =
--   seed/service_role-enrichment" contract, enforced at the RLS layer.
--   GRANT: authenticated SELECT, INSERT, UPDATE, DELETE (ACL-before-RLS, PR #106
--   gotcha — RLS filters rows; the GRANT lets the role reach the table). Per-user
--   asset CRUD IS a V1 authenticated write path (SELF-201 manual-asset onboarding
--   materializes the user's pfin.asset row), so unlike 009 user_taxonomy (V1-write-
--   dormant) this table ships the write policies + write grants active in V1.
--   anon: ZERO grant — by construction. The pfin schema ACL grants USAGE only to
--   authenticated (001/003); anon holds no USAGE on pfin and is denied at the
--   schema-usage layer before any table ACL is consulted (ADR-023 C2 outer fence).
--   This migration adds no anon grant.
--   service_role: NO grant in 016. The committed currency seed runs at `db reset`
--   under the admin/superuser migration connection (which bypasses GRANTs), NOT
--   under service_role. The runtime service_role GLOBAL-securities write path
--   (pfin_back_etl FMP registry-enrichment; provider-sync auto-registering unknown
--   securities as global asset rows) is a LATER worker-build surface (SELF-197+),
--   NOT a V1-016 need. Per the 008/009 least-privilege-per-table discipline that
--   grant lands with the migration/PR that actually introduces the service_role
--   writer — and that grant is C6-GATED: it does not ship without the paired QA
--   two-tenant pgTAP battery (ADR-023 C6 standing obligation) + Sec joint-review.
--   Noting it here so the deferral is explicit, not an oversight.
--
-- EXPOSURE / C6 RLS-COVERAGE NOTE (ADR-023 C6 standing obligation — pfin is in
--   [api] schemas, so this table is internet-facing the moment it is granted):
--   - RLS ENABLED on pfin.asset (below).
--   - POLICIES PRESENT: asset_select (global-OR-owned) + asset_insert / asset_update
--     / asset_delete (each owner-scoped, WITH CHECK users_id = auth.uid()).
--   - GRANT: authenticated SELECT/INSERT/UPDATE/DELETE. anon ZERO-grant.
--   - This table does NOT ship without the paired QA two-tenant pgTAP battery
--     (SECURITY §4.5, EXPOSURE-gating per C6). The battery must assert the HYBRID
--     posture, not vanilla isolation: (a) tenant A and tenant B BOTH read all GLOBAL
--     rows (users_id NULL — same rows, shared) PASS; (b) tenant B reads 0 of tenant
--     A's PER-USER rows (RLS-filtered) PASS; (c) tenant B cannot INSERT a global row
--     (users_id NULL fails WITH CHECK) nor a row owned by A (fails WITH CHECK);
--     (d) tenant B cannot UPDATE/DELETE A's rows nor any global row (USING excludes
--     them); (e) owner reads/writes own per-user rows PASS. QA authors the battery
--     (Architect does not edit tests/); Sec sign-off gates merge.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.asset — universal asset-definition registry (ADR-027 §4; R-9 vocab).
--     - asset_id (bigint identity PK): surrogate; the stable ref target for the
--       FKs authored at 017/019/020.
--     - users_id (uuid NULLABLE → auth.users, ON DELETE CASCADE): NULL = GLOBAL
--       (market/currency reference); non-NULL = PER-USER (physical/custom). Sole
--       tenant anchor; default auth.uid() so an authenticated per-user INSERT that
--       omits it lands owned + passes the WITH CHECK. The committed global seed
--       passes NULL explicitly.
--     - asset_type (text NOT NULL, CHECK): the INSTRUMENT-kind discriminator
--       (R-9 vocab MINUS 'cash'; see below). Distinct grain from 003 account_type
--       (CONTAINER kind). Additive-extend per ADR-022.
--     - pricing_source (text NOT NULL, CHECK): HOW eod_price (019) is populated —
--       market_feed / spot_feed / fx_feed / manual_valuation (R-9/R-16).
--     - symbol (text NULL): ticker / ISO currency code / NULL for physical. Global
--       dedup key (partial unique where users_id is null).
--     - name (text NULL): display name (VOO / "123 Main St" / "US Dollar"). Per-user
--       dedup key (partial unique where users_id is not null; R-19 follow-up (b)).
--     - cusip / figi / isin (text NULL): security identifiers (NULL for physical /
--       currencies).
--     - currency (text NOT NULL DEFAULT 'USD'): the asset's native denomination
--       (R-16 — an ASSET-level property; a currency-asset's own code). NOT an FK
--       (deliberate, R-16) → NOT D3.
--     - metadata (jsonb NULL): extensible per-asset-type attributes (contract
--       multiplier/expiry for derivatives; purchase details for physical).
--     - is_active (boolean NOT NULL DEFAULT true): soft-active UI hint (§4 line 55).
--     - created_at / updated_at (timestamptz): updated_at auto-refreshed via
--       fn_refresh_updated_at BEFORE UPDATE trigger.
--   Partial uniques: unique(symbol) where users_id IS NULL (global securities/
--     currencies deduped by symbol) + unique(users_id, name) where users_id IS NOT
--     NULL (per-user assets deduped by name — handles the "House" collision, R-19).
--   Security-load-bearing edges: the hybrid RLS (global-OR-owned read; owner-only
--     write) is the isolation contract; NULL users_id is the global-row sentinel;
--     no privilege, no §10 surface, no new D3 instance (016 is the referenced table,
--     not a referencing one).
-- ============================================================================

create schema if not exists pfin;
grant usage on schema pfin to authenticated;

-- ----------------------------------------------------------------------------
-- pfin.asset — universal asset registry (hybrid global + per-user; ADR-027 §4).
-- ----------------------------------------------------------------------------
create table if not exists pfin.asset (
  asset_id        bigint generated always as identity primary key,
  users_id        uuid default auth.uid()
                    references auth.users (id) on delete cascade,
  asset_type      text not null
                    check (asset_type in (
                      'equity', 'etf', 'fund', 'money_market', 'bond',
                      'future', 'option', 'crypto', 'real_estate', 'vehicle',
                      'metal', 'collectible', 'currency', 'private')),
  pricing_source  text not null
                    check (pricing_source in (
                      'market_feed', 'spot_feed', 'fx_feed', 'manual_valuation')),
  symbol          text,
  name            text,
  cusip           text,
  figi            text,
  isin            text,
  currency        text not null default 'USD',
  metadata        jsonb,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

comment on table pfin.asset is
  'Universal asset-definition registry (ADR-027 §4; R-9/R-16). HYBRID: users_id '
  'NULLABLE — NULL rows are GLOBAL (market securities, currencies — shared '
  'reference data readable by all authenticated); non-NULL rows are PER-USER '
  '(physical/custom assets, private to the owner). Carries asset_type (INSTRUMENT '
  'kind, distinct from 003 account_type CONTAINER kind) + pricing_source (HOW '
  'eod_price @ 019 is populated). CASH = the global USD currency-asset '
  '(asset_type=''currency'', pricing_source=''fx_feed''); ''cash'' is DROPPED from '
  'the R-9 asset_type vocab (redundant with ''currency''; greenfield). RLS is the '
  'novel hybrid posture (global-OR-owned SELECT; owner-only write) — the batch '
  'Sec joint-review merge-block 6. Decision 3 UNCHANGED at 6 (users_id is a SOLE '
  'anchor; the FKs INTO this table are the novel global-OR-matched-tenant fences '
  'authored at 017/020, evaluated there). Committed currency-asset identity rows '
  'seeded below (011-style global reference data); securities + physical assets '
  'await F/CTO''s registry export (DATA blocker; DDL is data-independent). anon '
  'zero-grant; service_role ungranted in 016 (global registry-enrichment write '
  'path is a later worker-build surface, C6-gated + Sec joint-review then).';

comment on column pfin.asset.users_id is
  'SOLE tenant anchor. NULL = GLOBAL row (market/currency reference, owned by no '
  'tenant, never cascade-deleted); non-NULL = PER-USER row (cascades on user '
  'delete). DEFAULT auth.uid() so an authenticated per-user INSERT that omits it '
  'lands owned + passes the asset_insert WITH CHECK; the committed global seed '
  'passes NULL explicitly. NOT a cross-tenant reference (it IS the anchor) → '
  'Decision 3 does not apply (family unchanged at 6).';
comment on column pfin.asset.asset_type is
  'INSTRUMENT-kind discriminator (R-9 vocab). ''cash'' is intentionally ABSENT — '
  'cash = the global USD ''currency'' asset (R-16 / GRAIN-CASH-RESOLVED); '
  '''currency'' is the canonical unit-of-account type. Distinct grain from 003 '
  'account_type (CONTAINER kind). Additive-extend only (ADR-022); '
  'depreciation_model + full derivatives math = V2.';
comment on column pfin.asset.pricing_source is
  'HOW eod_price (019) is populated: market_feed (stocks/ETFs/funds via FMP ETL, '
  'global) / spot_feed (metals, global) / fx_feed (currencies → USD-base FX rate, '
  'global) / manual_valuation (real estate/vehicle/collectible → user per-user '
  'entries). R-9/R-16.';
comment on column pfin.asset.currency is
  'The asset''s native denomination (R-16 — an ASSET-level property). For a '
  'currency-type asset it is its own ISO code. Deliberately NOT an FK to the '
  'currency-asset (R-16) — a text code joined for valuation, so NOT a Decision 3 '
  'instance. Distinct from account.currency (015; the account''s cash denomination).';
comment on column pfin.asset.symbol is
  'Ticker / ISO 4217 currency code / NULL for physical assets. Global dedup key: '
  'unique(symbol) where users_id is null.';
comment on column pfin.asset.metadata is
  'Extensible per-asset-type attributes (e.g. contract multiplier/expiry for '
  'futures/options; purchase details for physical). Unconstrained jsonb.';

-- Partial-unique indexes (Postgres requires an index, not a table constraint, for
-- partial uniqueness). Global securities/currencies dedup by symbol; per-user
-- assets dedup by name (the "House" collision, R-19 follow-up (b)).
create unique index if not exists asset_global_symbol_uniq
  on pfin.asset (symbol) where users_id is null;
create unique index if not exists asset_user_name_uniq
  on pfin.asset (users_id, name) where users_id is not null;

alter table pfin.asset enable row level security;

-- HYBRID RLS (the novel global-OR-owned posture — Sec joint-review merge-block 6).
-- SELECT: global rows (users_id NULL) readable by all authenticated; per-user rows
-- readable only by owner.
create policy asset_select on pfin.asset
  for select to authenticated
  using (users_id is null or users_id = auth.uid());

-- INSERT: a user may create ONLY own (non-global) rows. users_id = NULL (a global
-- row) fails `NULL = auth.uid()`; users_id = <other uuid> fails the equality.
create policy asset_insert on pfin.asset
  for insert to authenticated
  with check (users_id = auth.uid());

-- UPDATE: owner edits own rows only. USING excludes global rows (NULL = auth.uid()
-- is not true → invisible to the update path); WITH CHECK blocks repointing a row
-- to global/another tenant.
create policy asset_update on pfin.asset
  for update to authenticated
  using (users_id = auth.uid())
  with check (users_id = auth.uid());

-- DELETE: owner deletes own rows only; global rows are not user-deletable.
create policy asset_delete on pfin.asset
  for delete to authenticated
  using (users_id = auth.uid());

-- ACL-before-RLS (PR #106 gotcha): the role needs table-level GRANTs even with RLS
-- on. Per-user asset CRUD is a V1 authenticated write path (SELF-201), so SELECT +
-- INSERT + UPDATE + DELETE are all granted (contrast 009's SELECT-only dormancy).
-- No service_role grant here (global registry-enrichment path deferred; C6-gated).
grant select, insert, update, delete on pfin.asset to authenticated;

-- updated_at auto-refresh via the existing DEFINER allowlist entry #1 (001).
-- Adds NO new DEFINER entry (allowlist stays 3).
create trigger asset_set_updated_at
  before update on pfin.asset
  for each row execute function pfin.fn_refresh_updated_at();

-- ----------------------------------------------------------------------------
-- Committed canonical currency-asset identity seed (OWD open-choice (c) / PART D
-- D-f). Non-personal GLOBAL reference data → lives in the committed migration
-- (contrast the gitignored personal registry seed). users_id = NULL (global),
-- asset_type = 'currency', pricing_source = 'fx_feed'. USD is REQUIRED (the base
-- unit; account.currency default 'USD' + the cash model depend on it). This commits
-- IDENTITY ONLY — no eod_price (that table is 019; USD's rate ≡ 1.0 and the FX
-- majors are priced at 019/via fx_feed, not here). Idempotent via ON CONFLICT on
-- the global-symbol partial-unique index. F/CTO's specific held-currency additions
-- can ride the gitignored seed.sql later.
-- ----------------------------------------------------------------------------
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name, currency)
values
  (null, 'currency', 'fx_feed', 'USD', 'US Dollar',          'USD'),
  (null, 'currency', 'fx_feed', 'EUR', 'Euro',               'EUR'),
  (null, 'currency', 'fx_feed', 'GBP', 'Pound Sterling',     'GBP'),
  (null, 'currency', 'fx_feed', 'JPY', 'Japanese Yen',       'JPY'),
  (null, 'currency', 'fx_feed', 'CAD', 'Canadian Dollar',    'CAD'),
  (null, 'currency', 'fx_feed', 'CHF', 'Swiss Franc',        'CHF'),
  (null, 'currency', 'fx_feed', 'AUD', 'Australian Dollar',  'AUD')
on conflict (symbol) where users_id is null do nothing;

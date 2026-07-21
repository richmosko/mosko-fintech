-- ============================================================================
-- Migration: pfin.user_asset_category — the R-19 per-user asset→taxonomy allocation
--   junction (§2.2 asset-level allocation). Uniform per-user categorization of ANY
--   asset (global OR user-owned) into an asset-domain Sub-Cat.
-- Phase 6 Build Loop (ADR-027 ingest/valuation substrate; Linear SELF-282). Design
--   CLOSED + Sec-cleared (v1.71): temp/015-ingest-substrate-design.md §6B Option J1
--   (line 156) + §12/§13 D3 5→10 delta (line 207) + §16 R-19 ratify (line 295) +
--   OWD-B novel-fence pattern (line 301); temp/015-architect-design-spec.md PART B
--   (the junction row, line 113) + PART C (Pattern 1 #8 + Pattern 2 #9). §16 RENUMBER
--   NOTE (2026-07-18): the allocation-junction moved 020→022 (021 took the account-
--   mapping dedup index; migrations are append-only). JOINT-REVIEW-MANDATORY — this
--   migration carries BOTH Decision-3 fence patterns in one table (the matched-tenant
--   #8 + the novel global-OR-owned #9, the 2nd and final site of Pattern 2).
--
-- WHAT THIS DOES:
--   Creates pfin.user_asset_category — a MUTABLE per-user junction that assigns an
--   asset (securities / physical / cash-via-the-currency-asset) to a user's asset-
--   domain user_taxonomy Sub-Cat. Solves the GLOBAL-ASSET KNOT (R-19): a global asset
--   (VOO, users_id NULL) cannot carry a per-user sub_cat column — different users
--   allocate VOO differently — so categorization is per-(user, asset) via a junction
--   row, uniform for global and per-user assets alike. unique(users_id, asset_id) =
--   one categorization per user per asset. Full authenticated CRUD (the user edits
--   their own allocation); RLS direct-owner (users_id = auth.uid()). C5 user-write
--   surface.
--
-- Numbering: 022 follows 021 (account_linked_source_dedup index). Depends on 016
--   (pfin.asset — the asset_id FK target + the hybrid global-OR-owned RLS the novel
--   fence mirrors) and 009 (pfin.user_taxonomy — the sub_cat_id FK target) and 001
--   (pfin schema + fn_refresh_updated_at, reused for the updated_at trigger) and
--   auth.users (the users_id anchor). References no other pfin table. config.toml
--   already exposes pfin to [api] (ADR-023) — this table is internet-facing the
--   moment it is granted, so C6 exposure-gating binds (see EXPOSURE / C6 below).
--   No downstream migration depends on 022 landing first.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list. Read Decision 4 verbatim before drafting.) This
--   migration introduces ZERO catalogued §10 instances; the ledger STAYS at 3
--   (RT-22 + RT-26 + RT-27 per ADR-011 Decision 4 — RT-27 appended third at SELF-212,
--   F/CTO-ratified 2026-07-19; earlier 015–021 migration headers that read "stays 2"
--   predate that move — the current canonical count is 3).
--   (i)   Instance-numbering: RT-22 first, RT-26 second, RT-27 third — unchanged
--         (not touched).
--   (ii)  Layer-attribution: no infrastructure-credential-presence surface (RT-22 =
--         PDF-worker container), no code-layer SUPABASE_SERVICE_ROLE_KEY allowlist
--         surface (RT-26 = web-app/worker SOURCE grep fence), and no network-
--         exposure/config surface (RT-27 = the SELF-212 admission-app inbound fence)
--         is touched. This is authenticated-tier RLS/FK/trigger DDL only — no
--         service_role grant (see GRANTS RATIONALE), so 008's DB-ACL posture is
--         unchanged, and a DB-ACL grant would in any case be a DB-ACL change, NOT an
--         RT-26 code-layer change. No surface becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated. 022 is not the
--         canonical §10 anchor.
--   DE-CONFLATION GUARD: the two Decision-3 fences below (the matched-tenant sub_cat
--   fence + the novel global-OR-owned asset fence) are Decision-3 mechanisms, NOT §10
--   catalogued instances — the same separation the SELF-187 DEFINER-allowlist 2→3
--   drew against §10, and the same guard 012/017 drew.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — CANONICAL INSTANCES #8 + #9 (+2).
--   This table carries THREE reference columns; the ledger moves on TWO of them:
--     - users_id → auth.users(id): the SOLE tenant anchor itself (no second anchor to
--       mismatch) → NOT D3.
--     - sub_cat_id → pfin.user_taxonomy(id): BOTH sides per-user (user_asset_category.
--       users_id and user_taxonomy.users_id) → CANONICAL INSTANCE #8, a GENUINE
--       matched-tenant fence (the familiar 012 Pattern 1 shape) — a PG FK is
--       existence-only and would let a user tag an asset with ANOTHER tenant's
--       Sub-Cat, the exact chain attack Decision 3 fences.
--     - asset_id → pfin.asset(asset_id): global-OR-owned under 016's G1 hybrid
--       registry (nullable asset.users_id) → CANONICAL INSTANCE #9, the NOVEL
--       global-OR-matched-tenant fence (Pattern 2, site 2 of 2; site 1 =
--       account_trans.security_id @ 017 #7). A referenced asset is valid IFF GLOBAL
--       (asset.users_id IS NULL — market securities/currencies, legal for ANY tenant)
--       OR OWNED by the referencing row's tenant (asset.users_id = new.users_id).
--
--   ENUMERATION — already recorded; NO new DECISIONS.md ADR/amendment in this PR.
--     The ADR-027 atomic amendment (g) (landed in the 015 PR) ALREADY enumerates the
--     whole Decision-3 canonical 5 → 10 family delta and maps #8 + #9 to THIS
--     migration (formerly 020, renumbered 022 per §16). Per that amendment's
--     "per-migration Decision-3 evaluation + Sec joint-review at each of 015–021[→022]"
--     instruction, 022's obligation is this in-header evaluation (the two pre-
--     enumerated instances #8 + #9 are REALIZED here) + Sec numbering sign-off at
--     joint-review — NOT a new ADR. This mirrors the 015 (#6) and 017 (#7)
--     precedent exactly. Canonical running enumeration for Sec to verify:
--       #1 reconciliation_event_trans (event_id, account_trans_id)     [Lock 9]
--       #2 account_trans.replaces_trans_id self-FK                      [004]
--       #3 monthly_report.included_reconciliation_event_ids INTEGER[]   [Lock 11]
--       #4 monthly_report_account_snapshot.account_id                   [Lock 12]
--       #5 account.sub_cat_id → user_taxonomy(id)                       [012 / ADR-025]
--       #6 account.linked_source_id → linked_source                     [015]
--       #7 account_trans.security_id → pfin.asset (novel fence, site 1) [017]
--       #8 user_asset_category.sub_cat_id → user_taxonomy  ← THIS (matched-tenant)
--       #9 user_asset_category.asset_id → pfin.asset       ← THIS (novel fence, site 2)
--     (#10 account_trans_annotation.sub_cat_id → user_taxonomy @023 — later migration.)
--
--   OPERATIONAL-vs-CANONICAL DUAL-COUNT (Sec OQ-2; ADR-011 D3 enumeration mid-
--     reconciliation, task #13 — both figures stated cleanly so Sec/QA have a hook):
--       • CANONICAL enumeration (the clean deduplicated #1..#N list): realized
--         instances go 7 → 9 (highest realized was #7 @ 017; 022 realizes #8 + #9).
--       • OPERATIONAL running tally (the pre-reconciliation count the 015/021 slices
--         carried, which runs +1 over canonical-realized due to the historical Lock-14
--         settings-family count-grain conflation flagged in the 012 header + the
--         2026-07-02 annotation): 8 → 10.
--     Both move +2. Sec pins the authoritative figure at joint-review; the canonical
--     enumeration (9 realized, 10 total when #10 @023 lands) is the clean anchor.
--
--   REALIZATION MECHANISM — TWO separate BEFORE INSERT OR UPDATE triggers (one per
--     fence, mirroring the one-function-per-fence precedent of 012 fn_account_matched_
--     sub_cat + 017 fn_account_trans_security_asset; each is a distinct canonical
--     instance Sec verifies separately). BOTH cover UPDATE as well as INSERT because
--     user_asset_category is MUTABLE (the user re-categorizes: sub_cat_id and, less
--     commonly, asset_id are editable) — contrast 017's INSERT-only fence on the
--     immutable ledger; this matches 012, which covers UPDATE because pfin.account is
--     mutable. A single-row CHECK cannot subquery the referenced row, so Decision 3's
--     "trigger where PG cannot express the constraint declaratively" applies to both.
--
--   NOVEL-FENCE ADAPTATION vs 017 (stated, not silent): 017's fence resolves the
--     tenant via account_id → pfin.account.users_id (a JOIN) because account_trans has
--     NO own users_id. user_asset_category DOES carry its own users_id, so the novel
--     fence resolves the tenant DIRECTLY (asset.users_id = new.users_id) — no JOIN.
--     Same OWD-B predicate SHAPE (asset is valid iff global OR owned-by-tenant),
--     simpler tenant resolution. Also: 017's fence is LOAD-BEARING UNDER service_role
--     (account_trans is written under the 008 provider-sync service_role grant, so the
--     trigger is the SOLE ingest-path gate there). user_asset_category has NO
--     service_role writer in V1 (pure authenticated user-CRUD, like the 023 annotation
--     overlay), so here the explicit predicate is genuine belt-and-suspenders with
--     016's asset RLS rather than a sole gate — but it is authored identically (fail-
--     closed, authoritative) because OWD-B is the ratified precedent for EVERY FK into
--     hybrid pfin.asset regardless of the writer.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — both fence functions are SECURITY INVOKER (NOT DEFINER); the
--   SECURITY DEFINER allowlist STAYS 3 (ADR-011 Decision 9: fn_refresh_updated_at +
--   fn_grant_creator_access + the still-unauthored audit-log helper). ZERO new
--   SECURITY DEFINER in 022. Both fences read a single referenced row and need no
--   elevated privilege → INVOKER → not allowlist entries. The updated_at trigger
--   reuses the EXISTING pfin.fn_refresh_updated_at (001, allowlist entry #1) — no new
--   entry. set search_path = '' on both authored functions (injection fence).
--
--   fn_user_asset_category_matched_sub_cat (Pattern 1, #8) — SECURITY INVOKER. Under
--     authenticated, user_taxonomy_select (users_id = auth.uid(), 009) scopes the read
--     to the caller's own taxonomy — a cross-tenant sub_cat_id is INVISIBLE → NOT
--     EXISTS → raise (the desired fence); the explicit and users_id = new.users_id
--     predicate makes it authoritative regardless of RLS. NULL-safe fail-closed.
--   fn_user_asset_category_asset (Pattern 2, #9 — the novel global-OR-owned fence) —
--     SECURITY INVOKER. global-OR-owned predicate, tenant resolved directly via
--     new.users_id (see ADAPTATION above). NULL-safe fail-closed.
--
-- ----------------------------------------------------------------------------
-- DOMAIN NOTE (mirrors the 012 DOMAIN NOTE): matched-DOMAIN (user_taxonomy.domain =
--   'asset' — allocation is an asset-domain categorization) is NOT enforced in the
--   trigger for V1; it is left to the app-layer Sub-Cat dropdown filter (the junction
--   UI offers only asset-domain rows). The matched-TENANT check is non-negotiable +
--   DB-enforced; the matched-DOMAIN check is a value-correctness constraint left
--   flexible in V1 (a one-line `and domain = 'asset'` addition later if desired).
--
-- ----------------------------------------------------------------------------
-- ONE-WAY DOORS: none new. R-19 (the junction shape) + OWD-B (the novel-fence
--   pattern, both sites) were ratified 2026-07-13; 022 realizes the pre-ratified
--   design. The asset_id ON DELETE disposition is the one authoring-surfaced choice
--   (see the ON DELETE flag in the return note) — reversible via ALTER, not a data
--   one-way-door while greenfield/empty.
--
-- ----------------------------------------------------------------------------
-- EXPOSURE / C6 RLS-COVERAGE NOTE (ADR-023 C6 standing obligation — pfin is in [api]
--   schemas, so this table is internet-facing the moment it is granted):
--   - RLS ENABLED on pfin.user_asset_category (below).
--   - POLICIES PRESENT: uac_select / uac_insert / uac_update / uac_delete, each
--     owner-scoped (users_id = auth.uid(); write policies carry WITH CHECK
--     users_id = auth.uid()). Direct-owner posture (NOT the 016 hybrid — this table
--     holds only per-user rows; there are no global junction rows).
--   - GRANT: authenticated SELECT/INSERT/UPDATE/DELETE (full V1 CRUD; the user edits
--     their own allocation). anon ZERO-grant (schema-usage-layer denial — anon holds
--     no USAGE on pfin per ADR-023 C2). service_role UNGRANTED (no service_role write
--     path to this user-owned table in V1).
--   - This table does NOT ship without the paired QA two-tenant pgTAP battery
--     (SECURITY §4.5, EXPOSURE-gating per C6). The battery must assert: (a) owner
--     reads/writes own rows PASS; (b) tenant B reads 0 of tenant A's rows (RLS-
--     filtered) PASS; (c) tenant B cannot INSERT/UPDATE a row owned by A (WITH CHECK);
--     (d) the #8 matched-tenant fence — a user cannot categorize with ANOTHER tenant's
--     sub_cat_id (cross-tenant taxonomy → raise); (e) the #9 novel fence — a user can
--     categorize a GLOBAL asset (users_id NULL) PASS and an OWN asset PASS, but CANNOT
--     categorize ANOTHER tenant's per-user asset (cross-tenant asset → raise). QA
--     authors the battery (Architect does not edit tests/); Sec sign-off gates merge.
--     Not a vacuous green — the fixture must populate two tenants + a global asset.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.user_asset_category — per-user asset→Sub-Cat allocation junction (R-19 / J1).
--     - id (bigint identity PK): surrogate.
--     - users_id (uuid NOT NULL DEFAULT auth.uid() → auth.users ON DELETE CASCADE):
--       SOLE tenant anchor; cascades on user delete. NOT D3.
--     - asset_id (bigint NOT NULL → pfin.asset(asset_id) ON DELETE RESTRICT): the
--       categorized asset (global OR user-owned). Decision-3 CANONICAL #9, novel
--       global-OR-matched-tenant fence (fn_user_asset_category_asset).
--     - sub_cat_id (bigint NOT NULL → pfin.user_taxonomy(id) ON DELETE RESTRICT): the
--       assigned asset-domain Sub-Cat. Decision-3 CANONICAL #8, matched-tenant fence
--       (fn_user_asset_category_matched_sub_cat).
--     - created_at / updated_at (timestamptz): updated_at auto-refreshed via
--       fn_refresh_updated_at BEFORE UPDATE trigger.
--     - UNIQUE (users_id, asset_id): one categorization per user per asset (VOO is one
--       allocation class per user regardless of which account holds it); also the
--       users_id-leading index that serves the RLS predicate.
--   pfin.fn_user_asset_category_matched_sub_cat() — BEFORE INSERT OR UPDATE WHEN
--     (new.sub_cat_id IS NOT NULL); SECURITY INVOKER; set search_path=''; NULL-safe
--     fail-closed; rejects a sub_cat_id whose user_taxonomy.users_id != new.users_id.
--   pfin.fn_user_asset_category_asset() — BEFORE INSERT OR UPDATE WHEN (new.asset_id
--     IS NOT NULL); SECURITY INVOKER; set search_path=''; NULL-safe fail-closed;
--     global-OR-owned predicate (asset is global OR owned by new.users_id).
--   Security-load-bearing edges: BOTH fences fail-closed (NOT EXISTS → raise) + NULL-
--     safe + INVOKER-composes-with-RLS; the matched-tenant fence blocks cross-tenant
--     taxonomy tagging; the novel fence blocks referencing another tenant's per-user
--     asset while permitting global assets; RLS direct-owner + WITH CHECK bounds every
--     verb to the caller.
-- ============================================================================

create schema if not exists pfin;
grant usage on schema pfin to authenticated;

-- ----------------------------------------------------------------------------
-- pfin.user_asset_category — per-user asset→taxonomy allocation junction (R-19 / J1).
-- ----------------------------------------------------------------------------
create table if not exists pfin.user_asset_category (
  id          bigint generated always as identity primary key,
  users_id    uuid not null default auth.uid()
                references auth.users (id) on delete cascade,
  asset_id    bigint not null
                references pfin.asset (asset_id) on delete restrict,
  sub_cat_id  bigint not null
                references pfin.user_taxonomy (id) on delete restrict,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (users_id, asset_id)
);

comment on table pfin.user_asset_category is
  'Per-user asset→Sub-Cat allocation junction (ADR-027 R-19 / Option J1; SELF-282). '
  'Solves the global-asset knot: a global asset (users_id NULL) cannot carry a '
  'per-user sub_cat column, so §2.2 asset-level allocation is per-(user, asset) via a '
  'junction row — uniform for global + per-user assets. MUTABLE, full authenticated '
  'CRUD, RLS direct-owner (users_id = auth.uid()). Carries TWO Decision-3 fences: '
  'sub_cat_id → user_taxonomy = CANONICAL #8 (matched-tenant, 012 Pattern 1); '
  'asset_id → pfin.asset = CANONICAL #9 (novel global-OR-matched-tenant, Pattern 2 '
  'site 2 — tenant resolved directly via new.users_id, no JOIN, contrast 017 which '
  'JOINs account). users_id is the sole anchor (NOT D3). unique(users_id, asset_id) = '
  'one categorization per user per asset. Matched-DOMAIN (user_taxonomy.domain=''asset'') '
  'is app-layer in V1 (mirrors 012 DOMAIN NOTE); matched-TENANT is DB-enforced. anon '
  'zero-grant; service_role ungranted (no service_role write path in V1). DEFINER '
  'allowlist unchanged at 3; §10 ledger unchanged at 3 (RT-22 + RT-26 + RT-27).';

comment on column pfin.user_asset_category.users_id is
  'SOLE tenant anchor (users_id = auth.uid()). DEFAULT auth.uid() so an authenticated '
  'INSERT that omits it lands owned + passes the WITH CHECK; ON DELETE CASCADE with '
  'the tenant. NOT a cross-tenant reference (it IS the anchor) → Decision 3 does not '
  'apply.';
comment on column pfin.user_asset_category.asset_id is
  'FK → pfin.asset(asset_id) ON DELETE RESTRICT — the categorized asset (global OR '
  'user-owned). Decision-3 CANONICAL #9: the NOVEL global-OR-matched-tenant fence '
  '(Pattern 2 site 2) — valid IFF asset is GLOBAL (asset.users_id IS NULL) OR OWNED '
  'by this row''s tenant (asset.users_id = new.users_id). Fenced by '
  'fn_user_asset_category_asset (BEFORE INSERT OR UPDATE). Tenant resolved directly '
  'via new.users_id (no account JOIN — contrast 017''s security_id fence).';
comment on column pfin.user_asset_category.sub_cat_id is
  'FK → pfin.user_taxonomy(id) ON DELETE RESTRICT — the assigned asset-domain Sub-Cat. '
  'Decision-3 CANONICAL #8: matched-tenant fence (012 Pattern 1) — the referenced '
  'user_taxonomy row must share this row''s users_id. Fenced by '
  'fn_user_asset_category_matched_sub_cat (BEFORE INSERT OR UPDATE). Matched-DOMAIN '
  '(domain=''asset'') is app-layer in V1 (012 DOMAIN NOTE).';

alter table pfin.user_asset_category enable row level security;

-- Direct-owner RLS (NOT the 016 hybrid — this table holds only per-user rows).
-- SELECT/INSERT/UPDATE/DELETE all owner-scoped; write policies carry WITH CHECK so a
-- row cannot be created/repointed to another tenant.
create policy uac_select on pfin.user_asset_category
  for select to authenticated
  using (users_id = auth.uid());

create policy uac_insert on pfin.user_asset_category
  for insert to authenticated
  with check (users_id = auth.uid());

create policy uac_update on pfin.user_asset_category
  for update to authenticated
  using (users_id = auth.uid())
  with check (users_id = auth.uid());

create policy uac_delete on pfin.user_asset_category
  for delete to authenticated
  using (users_id = auth.uid());

-- ACL-before-RLS (PR #106 gotcha): the role needs table-level GRANTs even with RLS
-- on. Full V1 CRUD (the user edits their own allocation) — contrast 009's SELECT-only
-- dormancy. No service_role grant (no service_role writer in V1). anon zero-grant.
grant select, insert, update, delete on pfin.user_asset_category to authenticated;

-- updated_at auto-refresh via the existing DEFINER allowlist entry #1 (001).
-- Adds NO new DEFINER entry (allowlist stays 3).
create trigger user_asset_category_set_updated_at
  before update on pfin.user_asset_category
  for each row execute function pfin.fn_refresh_updated_at();

-- ----------------------------------------------------------------------------
-- Decision-3 CANONICAL #8 — matched-tenant fence on sub_cat_id (012 Pattern 1).
-- BEFORE INSERT OR UPDATE (mutable table — the user re-categorizes). SECURITY INVOKER.
-- The WHEN clause is belt-and-suspenders (sub_cat_id is NOT NULL, so the fence always
-- fires — stronger than 012/017 where a NULL FK was a legitimate skip).
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_user_asset_category_matched_sub_cat()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- NULL-SAFE FAIL-CLOSED: a missing OR (under RLS) unreadable taxonomy row yields
  -- NOT EXISTS → raise. (Never `(subquery) <> new.users_id` — that returns NULL on a
  -- missing row, the IF is skipped, and the write would leak.)
  if not exists (
    select 1 from pfin.user_taxonomy
    where id = new.sub_cat_id
      and users_id = new.users_id
  ) then
    raise exception
      'cross-tenant Sub-Cat rejected: sub_cat_id % is not a taxonomy row owned by users_id % (ADR-011 Decision 3 canonical instance #8 / matched-tenant fence)',
      new.sub_cat_id, new.users_id;
  end if;
  return new;
end;
$$;

revoke execute on function pfin.fn_user_asset_category_matched_sub_cat() from public;

comment on function pfin.fn_user_asset_category_matched_sub_cat() is
  'BEFORE INSERT OR UPDATE matched-tenant fence on pfin.user_asset_category.sub_cat_id (ADR-011 Decision 3 canonical instance #8 / 012 Pattern 1; ADR-027 R-19; SELF-282). Rejects categorizing an asset with another tenant''s Sub-Cat: the referenced user_taxonomy row must share this row''s users_id. NULL-safe fail-closed (NOT EXISTS → raise). SECURITY INVOKER + set search_path = '''' — the read composes with RLS (user_taxonomy_select scopes to auth.uid() under authenticated) and the explicit users_id equality makes it authoritative regardless. Covers UPDATE (re-categorization), not just INSERT (contrast 017 INSERT-only on the immutable ledger; matches 012 which covers UPDATE on mutable pfin.account). Trigger (not a bare CHECK) because it subqueries the referenced row — Decision 3 permits a trigger where PG cannot express the constraint declaratively. Not a DEFINER allowlist entry (INVOKER); allowlist stays 3. Matched-DOMAIN (domain=''asset'') is app-layer in V1 (012 DOMAIN NOTE).';

create trigger user_asset_category_matched_sub_cat
  before insert or update on pfin.user_asset_category
  for each row
  when (new.sub_cat_id is not null)
  execute function pfin.fn_user_asset_category_matched_sub_cat();

-- ----------------------------------------------------------------------------
-- Decision-3 CANONICAL #9 — the NOVEL global-OR-matched-tenant fence on asset_id
-- (Pattern 2, site 2 of 2; OWD-B, ratified 2026-07-13). SAME predicate shape as 017's
-- account_trans.security_id fence; tenant resolved DIRECTLY via new.users_id (no
-- account JOIN — this table carries its own users_id). NOT load-bearing under
-- service_role here (no service_role writer to this user-owned table in V1) — the
-- explicit predicate is genuine belt-and-suspenders with 016's asset RLS, authored
-- identically because OWD-B is the ratified precedent for EVERY FK into hybrid
-- pfin.asset. BEFORE INSERT OR UPDATE (mutable table). SECURITY INVOKER.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_user_asset_category_asset()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- GLOBAL-OR-OWNED predicate (Pattern 2): the asset is valid iff GLOBAL
  -- (a.users_id IS NULL — legal for any tenant) OR OWNED by this row's tenant
  -- (a.users_id = new.users_id). Tenant resolved directly (new.users_id) — no JOIN.
  -- NULL-SAFE FAIL-CLOSED: a missing asset, or an asset that is neither global nor
  -- tenant-owned, yields NOT EXISTS → raise.
  if not exists (
    select 1
    from pfin.asset a
    where a.asset_id = new.asset_id
      and (a.users_id is null or a.users_id = new.users_id)
  ) then
    raise exception
      'cross-tenant asset rejected: asset_id % is not a global or tenant-owned asset for users_id % (ADR-011 Decision 3 canonical instance #9 / novel global-OR-matched-tenant fence, Pattern 2 site 2)',
      new.asset_id, new.users_id;
  end if;
  return new;
end;
$$;

revoke execute on function pfin.fn_user_asset_category_asset() from public;

comment on function pfin.fn_user_asset_category_asset() is
  'BEFORE INSERT OR UPDATE novel global-OR-matched-tenant fence on pfin.user_asset_category.asset_id (ADR-011 Decision 3 canonical instance #9 / Pattern 2 site 2; ADR-027 OWD-B / R-19; SELF-282). A referenced asset is valid iff GLOBAL (pfin.asset.users_id IS NULL — market securities/currencies, legal for any tenant) OR OWNED by this row''s tenant (asset.users_id = new.users_id, resolved DIRECTLY since this table carries its own users_id — contrast 017''s security_id fence which JOINs account because account_trans has no own users_id). NULL-safe fail-closed (NOT EXISTS → raise). SECURITY INVOKER + set search_path = ''''. NOT load-bearing under service_role here (no service_role writer to this user-owned table in V1) — genuine belt-and-suspenders with 016''s asset RLS, authored identically because OWD-B is the ratified precedent for EVERY FK into the hybrid pfin.asset registry. Covers UPDATE (mutable table), not just INSERT. Trigger (not a bare CHECK) because it subqueries the referenced asset. Not a DEFINER allowlist entry (INVOKER); allowlist stays 3.';

create trigger user_asset_category_asset
  before insert or update on pfin.user_asset_category
  for each row
  when (new.asset_id is not null)
  execute function pfin.fn_user_asset_category_asset();

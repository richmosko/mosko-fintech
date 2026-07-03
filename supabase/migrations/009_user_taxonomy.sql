-- ============================================================================
-- Migration: pfin.user_taxonomy — per-user two-level Cat × Sub-Cat taxonomy
-- Phase 6 Build Loop (SELF-231 / V1.0 manual-entry cluster foundation).
-- Lands Lock 7 (ADR-011 Decision 11, Option A) — single per-user user-editable
-- taxonomy table for asset (§2.2.1) + cash-flow (§2.3.1) domains, carrying the
-- ADR-006 Axis 2 tax_relevant boolean + tax_character enum. V1 is SEED-ONLY
-- (no taxonomy-CRUD UI; V2+ expansion) and V1-WRITE-DORMANT: authenticated holds
-- SELECT only — the sole V1 consumer (SELF-201 manual-account form) READS the
-- taxonomy for Sub-Cat dropdowns; there is no V1 authenticated write caller
-- (SELF-236 reassigns an account's sub_cat, SELF-200 auto-Unsorted is a
-- backend/worker path — neither creates taxonomy rows). Mirrors the 003
-- account_users V1-dormancy precedent (SELECT policy + SELECT grant only; write
-- policies + grants DEFERRED to the V2 taxonomy-CRUD-UI PR). This is the
-- sub_cat_id FK target that 004 explicitly deferred ("FK → user_taxonomy, not
-- yet created"); it unblocks the SELF-201/202 manual-entry cluster.
--
-- Numbering: 009 follows 008 (pfin service_role grants). Depends on 001
-- (pfin schema + fn_refresh_updated_at) only; references no other pfin table.
-- No downstream migration depends on 009 landing before them EXCEPT the future
-- sub_cat_id → user_taxonomy FK (deferred at 004) — see the DECISION 3
-- FORWARD-POINTER below; that FK is a separate migration and a separate
-- Decision-3 evaluation, NOT introduced here.
--
-- ----------------------------------------------------------------------------
-- AC-vs-CONVENTION CORRECTIONS (SELF-231 issue AC predates the greenfield
-- as-built type convention established at 003; reconciled here, F/CTO-flagged):
--   (1) id — AC said `SERIAL PRIMARY KEY`. CORRECTED to
--       `bigint generated always as identity primary key` — matches 003
--       account.account_id (the greenfield PK convention); SERIAL is the legacy
--       pre-identity idiom and is not used anywhere in 001–008.
--   (2) users_id — AC said `INTEGER NOT NULL REFERENCES auth.users(id)`. This is
--       WRONG on the type: auth.users.id is `uuid`, not integer. CORRECTED to
--       `uuid not null default auth.uid() references auth.users(id) on delete
--       cascade` — matches 003 account.users_id exactly (the RLS isolation
--       anchor + creator-attribution DEFAULT + tenant-cascade on user delete).
--   Both corrections are convention-conformance, not scope changes; Option A
--   single-table shape (Decision 11) is unchanged.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference Decision 4; do NOT restate the
-- catalogued numbered list). This migration introduces ZERO catalogued §10
-- instances; the ledger stays at 2 (RT-22 + RT-26 per ADR-011 Decision 4).
--   (i) Instance-numbering: RT-22 first, RT-26 second — unchanged (not touched).
--   (ii) Layer-attribution: no infrastructure-credential-presence (RT-22) or
--        code-layer service_role-key allowlist (RT-26) surface is touched — this
--        is an authenticated-tier RLS/GRANT base table. service_role is NOT
--        granted here (see GRANTS RATIONALE), so 008's DB-ACL posture is
--        unchanged too; that would be a DB-ACL change, NOT an RT-26 change,
--        regardless.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated.
--
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family count +0
-- (stays 7 at Phase 4 close). This table has exactly ONE reference column,
-- users_id → auth.users(id), which IS the tenant anchor itself — not a
-- cross-tenant reference to another pfin row — so it carries no matched-tenant
-- obligation (there is no second anchor to mismatch). No INTEGER[]/array FK, no
-- self-FK, no cross-table FK. Decision 3 family UNCHANGED.
--   FORWARD-POINTER: the sub_cat_id → user_taxonomy(id) FK that 004 deferred
--   (to be added by a later migration/ALTER on the manual-entry write path) WILL
--   be a Decision-3 evaluation at THAT migration — the referencing row's users_id
--   must be validated equal to user_taxonomy.users_id (WITH CHECK / trigger),
--   because a user must not tag their transaction with another tenant's Sub-Cat.
--   That obligation lands with that FK, not here.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — NO function authored with elevated privilege.
--   This migration creates no SECURITY DEFINER and no SECURITY INVOKER function;
--   it is CREATE TABLE + RLS policies + GRANTs + one updated_at trigger wired to
--   the EXISTING fn_refresh_updated_at (001, already the DEFINER allowlist entry
--   #1). The SECURITY DEFINER allowlist is UNCHANGED at 3 (ADR-011 Decision 9);
--   no new DEFINER entry, no Sec-DEFINER-review trigger. Decision 11 Sec posture
--   is ADVISORY (user-scoped RLS standard; "no novel surface") — but the C6
--   exposure-gating obligation (ADR-023 / SELF-196) still routes the RLS-coverage
--   to Sec's eyes because pfin is now Data-API-exposed (see EXPOSURE / C6 below).
--
-- GRANTS RATIONALE — V1-WRITE-DORMANT: authenticated gets SELECT ONLY.
--   F/CTO-disposed (2026-07-03): grant SELECT only in V1; DEFER INSERT/UPDATE/
--   DELETE (both the grants AND the write policies) to the V2 taxonomy-CRUD-UI PR.
--   Least-privilege rationale: Decision 11 locks V1 as seed-only / no-CRUD-UI, and
--   there is NO V1 authenticated write caller — the only V1 consumer (SELF-201
--   manual-account form) READS the taxonomy for Sub-Cat dropdowns; SELF-236
--   reassigns an account's sub_cat (does not create taxonomy rows) and SELF-200
--   auto-Unsorted is a backend/worker path. So V1 needs read-only.
--   DORMANCY SHAPE (mirrors 003 account_users): we ship the SELECT policy + SELECT
--   grant only and DEFER the write policies entirely (no INSERT/UPDATE/DELETE
--   policy in V1). This is strictly MORE locked-down than a present-but-ungranted
--   write policy: V1 writes are blocked at BOTH the ACL layer (no grant) AND the
--   RLS layer (default-deny, no policy). The V2 CRUD-UI PR adds the write policies
--   + the write grants together (each write policy carries WITH CHECK
--   users_id = auth.uid() — the standard C5 WITH-CHECK user-write shape, safe under
--   exposure; nothing here touches an ACL-isolation pivot, unlike account_users).
--   anon: ZERO grant — by construction. The pfin schema ACL grants USAGE only to
--   authenticated (001/003); anon holds no USAGE on pfin and is denied at the
--   schema-usage layer before any table ACL is consulted (ADR-023 C2 outer
--   fence). This migration adds no anon grant.
--   service_role: NO grant. V1 is seed-only and the seed runs at `db reset` under
--   the admin/superuser migration connection (which bypasses GRANTs), NOT under
--   service_role — so there is no runtime service_role write path to user_taxonomy
--   (contrast plaid_items @ 008, where service_role IS the Plaid-sync writer).
--   If a future per-user server-side seed/bootstrap path emerges (e.g. V2
--   onboarding seeding a new user's taxonomy under service_role), THAT is a new
--   service_role write path → add the grant then + Sec joint-review (mirrors the
--   008 least-privilege-per-table discipline). Not needed for V1.
--
-- EXPOSURE / C6 RLS-COVERAGE NOTE (ADR-023 C6 standing obligation — pfin is in
-- [api] schemas, so this table is internet-facing the moment it is granted):
--   - RLS ENABLED on pfin.user_taxonomy (below).
--   - POLICY PRESENT: user_taxonomy_select only (gated users_id = auth.uid()).
--     Write policies are DEFERRED (V1-write-dormant, per GRANTS RATIONALE) — so
--     writes are default-denied at the RLS layer in addition to the ACL layer.
--   - GRANT: authenticated SELECT only. anon ZERO-grant (schema-usage-layer
--     denial, per GRANTS RATIONALE).
--   - Two-layer fence intact: outer = anon zero pfin grant; inner = RLS
--     users_id = auth.uid() on read.
--   This table does NOT ship without the paired QA two-tenant pgTAP battery
--   (SECURITY §4.5, now EXPOSURE-gating per C6). NOTE the V1-write-dormant shape
--   changes the write-side assertion: a tenant-B INSERT/UPDATE/DELETE now fails at
--   the GRANT layer (`permission denied`) — NOT the WITH CHECK — because there is
--   no write grant or write policy in V1. Battery asserts: owner reads own rows
--   PASS / tenant B reads 0 of A's rows (RLS-filtered SELECT) / tenant B
--   INSERT/UPDATE/DELETE fails closed at the grant layer. QA authors the battery
--   (Architect does not edit tests/); Sec sign-off gates merge.
--
-- CONTRACT
--   pfin.user_taxonomy — per-user Cat × Sub-Cat taxonomy row.
--     - domain: 'asset' | 'cashflow' (CHECK) — which §2.2.1/§2.3.1 taxonomy.
--     - cat / sub_cat: the two taxonomy levels (free-text, user-defined).
--     - tax_relevant (bool, default false) + tax_character (nullable enum, 5
--       ADR-006 Axis 2 values) — the tax-routing attributes.
--     - display_order (nullable int) / is_active (bool, default true) — UI hints.
--     - UNIQUE (users_id, domain, cat, sub_cat): one row per user per
--       domain/cat/sub-cat; also the users_id-leading index that serves the RLS
--       predicate (no separate uid index needed — mirrors 003 account_users where
--       the leading-column unique already served its lookups).
--   Security-load-bearing edges: RLS users_id = auth.uid() fences reads to the
--   owner; V1 is read-only for authenticated (writes deferred), so the users_id
--   DEFAULT auth.uid() + WITH CHECK write shape is scaffolded for V2 but not yet
--   an active write path; the CHECKs on domain + tax_character constrain the value
--   domains; updated_at auto-refresh via fn_refresh_updated_at (wired for V2 writes).
-- ============================================================================

create schema if not exists pfin;
grant usage on schema pfin to authenticated;

-- ----------------------------------------------------------------------------
-- pfin.user_taxonomy — per-user two-level asset + cash-flow taxonomy
-- (ADR-011 Decision 11 / Lock 7, Option A single-table; ADR-006 Axis 2 tax attrs).
-- ----------------------------------------------------------------------------
create table if not exists pfin.user_taxonomy (
  id             bigint generated always as identity primary key,
  users_id       uuid not null default auth.uid()
                   references auth.users (id) on delete cascade,
  domain         text not null
                   check (domain in ('asset', 'cashflow')),
  cat            text not null,
  sub_cat        text not null,
  tax_relevant   boolean not null default false,
  tax_character  text
                   check (tax_character in (
                     'ordinary', 'qualified_dividend', 'tax_exempt_interest',
                     'long_term_capital_gain_eligible', 'short_term_only')),
  display_order  integer,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (users_id, domain, cat, sub_cat)
);

comment on table pfin.user_taxonomy is
  'Per-user two-level Cat × Sub-Cat taxonomy (ADR-011 Decision 11 / Lock 7, Option A single-table; SELF-231). Covers asset (§2.2.1) + cash-flow (§2.3.1) domains via the domain CHECK. Carries the ADR-006 Axis 2 tax_relevant boolean + tax_character enum (5 V1 values). V1 is SEED-ONLY (no taxonomy-CRUD UI; V2+ expansion) and V1-WRITE-DORMANT (F/CTO-disposed 2026-07-03, mirrors 003 account_users): authenticated holds SELECT ONLY (the V1 consumer reads Sub-Cat dropdowns; no V1 authenticated write caller). Write policies + write grants are DEFERRED to the V2 taxonomy-CRUD-UI PR (V1 writes are default-denied at BOTH the ACL layer (no grant) and the RLS layer (no write policy)). anon zero-grant; service_role ungranted (seed runs at db reset under admin, not service_role). This is the sub_cat_id FK target that 004 deferred — that future FK is a separate Decision-3 evaluation (referencing row users_id must match user_taxonomy.users_id), added with the FK, not here. AC-vs-convention corrections: AC SERIAL→identity, AC INTEGER users_id→uuid (auth.users.id is uuid) — see 009 header.';

alter table pfin.user_taxonomy enable row level security;

-- RLS: directly tenant-owned. V1-WRITE-DORMANT — SELECT policy only (a user reads
-- only their own taxonomy rows). Write policies (INSERT/UPDATE/DELETE, each with
-- WITH CHECK users_id = auth.uid()) are DEFERRED to the V2 taxonomy-CRUD-UI PR,
-- landing together with the write grants (mirrors 003 account_users dormancy).
-- V1 writes are default-denied at BOTH layers: no grant (ACL) AND no policy (RLS).
create policy user_taxonomy_select on pfin.user_taxonomy
  for select to authenticated using (users_id = auth.uid());

-- ACL-before-RLS (PR #106 gotcha): the role needs table-level GRANTs even with
-- RLS on. SELECT only in V1-write-dormant — no insert/update/delete grant.
grant select on pfin.user_taxonomy to authenticated;

-- No separate users_id index: the unique (users_id, domain, cat, sub_cat) btree
-- leads with users_id and already serves the RLS predicate (users_id = auth.uid()).
-- (Mirrors 003 account_users, where the leading-column unique served its lookups.)

create trigger user_taxonomy_set_updated_at
  before update on pfin.user_taxonomy
  for each row execute function pfin.fn_refresh_updated_at();

-- ============================================================================
-- Migration: pfin.user_settings — per-user own-row settings substrate.
-- Phase 6 Build Loop (SELF-286 / Auth-3 — MFA substrate ONLY). Lands the
-- per-user `mfa_policy` column (the ratified auth model's per-user MFA choice)
-- plus the general-minimal own-row settings home. F/CTO-ratified 2026-07-21
-- (Option B split): this migration is the Auth-3 SUBSTRATE only. The real
-- DB-enforced TOTP step-up (the per-user-conditional aal2 RLS backstop) + the
-- on-signup provisioning trigger + the TOTP enrollment/step-up flow are the
-- Auth-3b fast-follow (SELF-291) — NOT here. email-2FA was DROPPED from the
-- ratified model, so `mfa_policy` domain excludes 'email'.
--
-- WHAT THIS DOES: creates `pfin.user_settings`, ONE row per user (PK = users_id,
-- the tenant anchor itself), carrying `mfa_policy text NOT NULL DEFAULT 'none'
-- CHECK IN ('none','totp','passkey')`. Owner-only RLS (SELECT/INSERT/UPDATE);
-- no DELETE (settings rows are not user-deletable — lifecycle is tied to the
-- auth.users ON DELETE CASCADE). authenticated gets SELECT+INSERT+UPDATE grants
-- (a LIVE write path — the user self-selects mfa_policy at account setup, unlike
-- 009 user_taxonomy which is V1-write-dormant). anon zero; service_role none
-- (the app upserts under the user's OWN JWT via the authenticated INSERT policy;
-- there is no worker/server-role writer to user_settings in V1).
--
-- PROVISIONING TIMING (ratified D3 = LAZY app-upsert; NO on-signup DEFINER):
--   The user's row is created lazily by the app (SELF-286 Backend) via an
--   RLS-scoped `insert ... on conflict (users_id) do nothing` under the user's
--   own JWT — NOT by an auth.users AFTER-INSERT SECURITY DEFINER trigger. This
--   keeps the SECURITY DEFINER allowlist UNCHANGED at 3 (no 3->4 growth). A
--   missing row is read as the DEFAULT policy 'none' by every consumer (a user
--   who has not chosen a factor is not force-stepped-up; the universal tenant
--   RLS still fully fences them — see ISOLATION INVARIANT below). Also fulfills
--   SELF-285 AC#5's deferred profile/settings row.
--
-- SELF-232 COORDINATION — ⚠ SUPERSEDED 2026-08-16 (ADR-056; realized at 074).
--   THIS BLOCK PREVIOUSLY READ that this table is SELF-232's future home and that
--   the deferred SELF-232 settings work (planning-target / display / preference
--   columns) would land ADDITIVELY here as `ALTER TABLE pfin.user_settings ADD
--   COLUMN ...` — NOT a second per-user own-row table, NOT a rebuild. THAT IS NO
--   LONGER THE DESIGN. It was also, as written, in conflict with ADR-011 Decision
--   18 / Lock 14 ("four per-domain tables"), and leaving that conflict
--   unadjudicated is what produced SELF-324.
--   The %Target half of SELF-232 is a per-Sub-Cat VECTOR, which no additive scalar
--   ALTER can express; it lands at 074 as pfin.planning_target, one row per
--   (users_id, sub_cat_id). Two further reasons it could not be sited here, both
--   independent of the vector shape: Decision 18 fences JSONB out of the settings
--   store by name, and 025 excludes pfin.user_settings from the aal2 step-up
--   backstop as a NON-NEGOTIABLE exclusion (clausing it recurses into the policy
--   that reads it) — so tenant planning data sited here could never carry the
--   step-up fence every other tenant-owned pfin table carries.
--   WHAT IS UNCHANGED: the grain of THIS table (one row per user, PK = users_id),
--   and every executable line in this file — no DDL, policy, grant or trigger is
--   affected by this correction. mfa_policy remains the only functional column in
--   V1. Whether some FUTURE non-vector preference column lands here is left open;
--   ADR-056 does not decide it.
--   The `comment on table` below carries the same superseded claim. It has a
--   database representation, so it is NOT edited here — it is corrected by the
--   comment-only migration 075 (the 052 shape), because a correction has to land
--   where the reader is, and a `\d+` reader has no repo in front of them.
--
-- ----------------------------------------------------------------------------
-- Numbering: 024 follows 023 (account_trans_annotation). Depends ONLY on 001
--   (pfin schema + pfin.fn_refresh_updated_at, reused for the updated_at
--   trigger). References no other pfin table. No downstream migration depends on
--   024 landing before it. Order-dependent only on 001.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — NO function authored with elevated privilege.
--   This migration creates NO SECURITY DEFINER and NO SECURITY INVOKER function.
--   It is CREATE TABLE + RLS policies + GRANTs + one updated_at trigger wired to
--   the EXISTING pfin.fn_refresh_updated_at (001, already DEFINER allowlist
--   entry #1). The SECURITY DEFINER allowlist is UNCHANGED at 3 (ADR-011
--   Decision 9 / SELF-187 amendment: fn_refresh_updated_at + the audit-log
--   insert helper + fn_grant_creator_access). No new DEFINER entry → no
--   Sec-DEFINER-review trigger. `set search_path = ''` is N/A (a function-body
--   guard; this migration defines no function). The ratified on-signup DEFINER
--   provisioning trigger was REJECTED (D3 = lazy app-upsert) precisely to avoid
--   a 4th allowlist entry.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate
-- the catalogued numbered list). This migration introduces ZERO catalogued §10
-- instances; the ledger stays at 2 (RT-22 + RT-26 per ADR-011 Decision 4). An
-- authenticated-tier own-row RLS/GRANT base table touches no
-- infrastructure-credential-presence surface (RT-22) and no service_role-key /
-- code-layer allowlist surface (RT-26).
--   (i)   Instance-numbering: unchanged (not touched) — RT-22 first, RT-26 second.
--   (ii)  Layer-attribution: unchanged — no infra-credential (RT-22) and no
--         code-layer service_role-key (RT-26) surface is touched. service_role is
--         NOT granted here (see GRANTS RATIONALE), so 008's DB-ACL posture is
--         unchanged — and that would be a DB-ACL change, NOT an RT-26 change,
--         regardless.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family count +0
-- (UNCHANGED). This table has exactly ONE reference column,
--   users_id -> auth.users(id), which IS the tenant anchor itself (and the PK) —
--   NOT a cross-tenant reference to another pfin row. Identical shape to 009
--   user_taxonomy.users_id: there is no second anchor to mismatch, so it carries
--   NO matched-tenant obligation. No INTEGER[]/array FK, no self-FK, no
--   cross-table FK, no cross-tenant reference of any kind. Decision 3 family
--   UNCHANGED. (Stated explicitly per the mandatory FK-shaped-column check.)
--
-- ----------------------------------------------------------------------------
-- EXPOSURE / C6 RLS-COVERAGE NOTE (ADR-023 C6 standing obligation — pfin is in
-- [api] schemas, so this table is internet-facing the moment it is granted):
--   - RLS ENABLED on pfin.user_settings (below).
--   - POLICIES PRESENT: SELECT + INSERT + UPDATE, each owner-gated
--     (users_id = auth.uid()). No DELETE policy (writes-that-remove are
--     default-denied at BOTH the ACL layer (no delete grant) and the RLS layer
--     (no delete policy)). This IS a live write path (contrast 009's
--     write-dormant read-only shape): INSERT/UPDATE grants + policies ship now.
--   - GRANT: authenticated SELECT+INSERT+UPDATE. anon ZERO-grant (pfin
--     schema-usage denial, ADR-023 C2 outer fence). service_role NOT granted.
--   - Two-layer fence intact: outer = anon zero pfin grant; inner = RLS
--     users_id = auth.uid() on read AND write (WITH CHECK). A tenant can only
--     ever see/insert/update its OWN row (PK = users_id = auth.uid()).
--   This table does NOT ship without the paired QA two-tenant pgTAP battery
--   (SECURITY §4.5, EXPOSURE-gating per C6): owner reads/writes own row PASS;
--   tenant B reads 0 of A's rows (RLS-filtered SELECT); tenant B INSERT/UPDATE of
--   A's users_id fails closed (WITH CHECK); a bad mfa_policy value fails closed
--   (CHECK). QA authors the battery (Architect does not edit tests/); Sec
--   sign-off gates merge.
--
-- ----------------------------------------------------------------------------
-- ISOLATION INVARIANT (SELF-286 AC#6 — documented here as the canonical anchor):
--   Tenant isolation = the UNIVERSAL RLS predicate users_id = auth.uid(),
--   enforced on every pfin table INDEPENDENT of MFA. `mfa_policy` is per-user and
--   bounds ONLY that user's OWN impersonation risk (whether their own session
--   must be stepped-up to aal2 — enforced app-layer in V1, DB-backstopped in
--   Auth-3b). A user's factor choice can NEVER weaken another tenant's RLS fence:
--   'none' still carries the full users_id = auth.uid() tenant fence. MFA strength
--   is orthogonal to tenant isolation.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.user_settings — per-user own-row settings; ONE row per user.
--     - users_id (uuid PK): the tenant anchor AND the primary key (structurally
--       enforces single-row-per-user; no surrogate id). DEFAULT auth.uid();
--       REFERENCES auth.users(id) ON DELETE CASCADE (tenant-cascade on user del).
--     - mfa_policy (text NOT NULL DEFAULT 'none' CHECK IN
--       ('none','totp','passkey')): the per-user MFA choice. 'email' DROPPED from
--       the ratified model. TEXT+CHECK per ADR-022 (behavior lives in code — the
--       app-layer guard + the Auth-3b aal2 backstop — no per-value metadata → a
--       registry would be an empty abstraction; ADR-024 promote-to-registry path
--       remains available if per-value metadata ever appears). 'passkey' is
--       forward-compat (Auth-6 V1.x); the app UI gates which values are
--       selectable (only 'none'|'totp' offered until Auth-6). Additive values are
--       a cheap CHECK alter (ADR-022 additive) — NOT a one-way door.
--     - created_at / updated_at (timestamptz): convention columns; updated_at
--       auto-refreshed by the existing fn_refresh_updated_at trigger.
--   Security-load-bearing edges: RLS users_id = auth.uid() fences reads AND
--     writes (WITH CHECK) to the owner; PK = users_id enforces one row per tenant;
--     the CHECK constrains the mfa_policy domain; ON DELETE CASCADE ties row
--     lifecycle to the user. No elevated privilege; no §10 surface; no
--     cross-tenant FK.
-- ============================================================================

create schema if not exists pfin;
grant usage on schema pfin to authenticated;

-- ----------------------------------------------------------------------------
-- pfin.user_settings — per-user own-row settings substrate (SELF-286 Auth-3).
-- PK = users_id (one row per user). SELF-232's future settings columns ADD
-- ADDITIVELY here. mfa_policy is the only functional column in V1.
-- ----------------------------------------------------------------------------
create table if not exists pfin.user_settings (
  users_id     uuid primary key default auth.uid()
                 references auth.users (id) on delete cascade,
  mfa_policy   text not null default 'none'
                 check (mfa_policy in ('none', 'totp', 'passkey')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table pfin.user_settings is
  'Per-user own-row settings substrate (SELF-286 / Auth-3, MFA substrate only; '
  'F/CTO-ratified 2026-07-21 Option B split). ONE row per user (PK = users_id, '
  'the tenant anchor itself). Carries the per-user mfa_policy MFA choice; this is '
  'also SELF-232''s future settings home (planning-target/display/preference '
  'columns land ADDITIVELY via ALTER ADD COLUMN — not a second table, not a '
  'rebuild) and fulfills SELF-285 AC#5''s deferred profile row. LIVE write path '
  '(contrast 009 user_taxonomy write-dormant): authenticated holds '
  'SELECT+INSERT+UPDATE; the app lazily upserts the row under the user''s own JWT '
  '(insert ... on conflict (users_id) do nothing) — NO on-signup DEFINER trigger '
  '(ratified D3; DEFINER allowlist stays 3). No DELETE policy/grant (settings '
  'rows are not user-deletable; lifecycle tied to auth.users ON DELETE CASCADE). '
  'anon zero-grant (pfin schema-usage denial); service_role ungranted (no '
  'server-role writer — the app writes as the user). ISOLATION INVARIANT '
  '(AC#6): tenant isolation = universal RLS users_id = auth.uid(), independent of '
  'MFA; mfa_policy bounds only the user''s OWN step-up/impersonation risk and can '
  'never weaken another tenant''s fence. The real DB-enforced aal2 step-up '
  'backstop is Auth-3b (SELF-291), NOT here.';

comment on column pfin.user_settings.users_id is
  'Tenant anchor AND primary key (one row per user; no surrogate id). DEFAULT '
  'auth.uid(); FK -> auth.users(id) ON DELETE CASCADE. This is the ONLY reference '
  'column and it IS the tenant anchor — Decision 3 family UNCHANGED (no '
  'cross-tenant FK; identical shape to 009 user_taxonomy.users_id).';

comment on column pfin.user_settings.mfa_policy is
  'Per-user MFA choice: text NOT NULL DEFAULT ''none'' CHECK IN '
  '(''none'',''totp'',''passkey''). ''email'' DROPPED from the ratified auth '
  'model. TEXT+CHECK per ADR-022 (behavior lives in code — app-layer guard + the '
  'Auth-3b aal2 backstop — no per-value metadata; ADR-024 promote-to-registry '
  'available if that changes). ''passkey'' is forward-compat (Auth-6 V1.x); the '
  'app UI gates selectable values (only none|totp until Auth-6). A missing row is '
  'read as ''none'' by consumers (lazy provisioning). Adding values later is a '
  'cheap additive CHECK alter — not a one-way door.';

alter table pfin.user_settings enable row level security;

-- RLS: directly tenant-owned, LIVE write path. Owner-only SELECT/INSERT/UPDATE
-- (users_id = auth.uid()). NO DELETE policy — settings rows are not
-- user-deletable (lifecycle tied to the auth.users ON DELETE CASCADE); deletes
-- are default-denied at BOTH layers (no delete grant + no delete policy).
create policy user_settings_select on pfin.user_settings
  for select to authenticated using (users_id = auth.uid());

create policy user_settings_insert on pfin.user_settings
  for insert to authenticated with check (users_id = auth.uid());

create policy user_settings_update on pfin.user_settings
  for update to authenticated
  using (users_id = auth.uid()) with check (users_id = auth.uid());

-- ACL-before-RLS (PR #106 gotcha): the role needs table-level GRANTs even with
-- RLS on. SELECT+INSERT+UPDATE (live write path); NO delete grant. anon: zero
-- (schema-usage-layer denial). service_role: none (the app writes as the user).
grant select, insert, update on pfin.user_settings to authenticated;

-- No separate users_id index: users_id is the PK, whose backing unique btree
-- already serves the RLS predicate (users_id = auth.uid()).

-- updated_at auto-refresh via the existing DEFINER allowlist entry #1 (001).
-- Adds NO new DEFINER entry (allowlist stays 3).
create trigger user_settings_set_updated_at
  before update on pfin.user_settings
  for each row execute function pfin.fn_refresh_updated_at();

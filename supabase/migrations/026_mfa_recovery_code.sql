-- ============================================================================
-- Migration: pfin.mfa_recovery_code — one-time MFA backup codes + the recovery
-- downgrade grant. Phase 6 Build Loop (SELF-291 / Auth-3b Slice 2a — the STORE
-- ONLY; the /mfa/recover endpoint + issuance/redemption flow are Slice 2b, NOT
-- here). F/CTO-ratified 2026-07-22 (Opt A: service_role self-service backup-code
-- recovery). Delivers SELF-288's MFA-recovery-codes portion (SELF-288's
-- password-reset portion stays open, per F/CTO #7).
--
-- WHAT THIS DOES:
--   (1) creates pfin.mfa_recovery_code — one row per issued backup code, storing
--       only the app-side bcrypt/argon2 HASH (never plaintext), grouped by
--       batch_id, with used_at as the one-time double-spend guard. It is a
--       SERVICE_ROLE-ONLY table (RLS enabled, ZERO authenticated policy →
--       default-deny at the authenticated tier; mirrors linked_source_sync_audit)
--       — the hashes must NEVER reach the direct PostgREST API, and both issuance
--       and redemption are privileged server-side operations.
--   (2) grants service_role the least-privilege reach the Slice-2b recovery
--       endpoint needs to DOWNGRADE mfa_policy at recovery: select(users_id) +
--       update(mfa_policy) on pfin.user_settings. This is what lets the recovery
--       endpoint flip mfa_policy->'none' for a locked-out (authenticated aal1)
--       user — the MB-1 downgrade guard (025) exempts service_role
--       (current_user <> 'authenticated'), so the privileged downgrade passes.
--
-- No function is authored. DEFINER allowlist UNCHANGED at 3. §10 catalogued ledger
-- UNCHANGED at 3 (RT-22/RT-26/RT-27) — see the §10 block (a service_role DB-ACL
-- grant is NOT an RT-26 code-layer change). Decision-3 family UNCHANGED.
--
-- ----------------------------------------------------------------------------
-- WHY service_role (the recovery flow is a privileged surface BY CONSTRUCTION —
-- capability-verified 2026-07-22 on the local stack, GoTrue v2.189 + PG 17.6):
--   1. The MB-1 guard (025) blocks an authenticated aal1 session from lowering
--      mfa_policy out of the aal2-capable set; a recovering user IS authenticated
--      + aal1 (lost authenticator) → the downgrade cannot run on their JWT; only
--      service_role/postgres are guard-exempt.
--   2. CV-R1 = BLOCKED (observed): an aal1 session mfa.unenroll() of a VERIFIED
--      factor returns 422 insufficient_aal ("AAL2 required to unenroll verified
--      factor"). The factor MUST be removed (else GoTrue keeps nextLevel=aal2 and
--      the Slice-1 fail-closed app guard still blocks the user) — and only
--      service_role admin deleteFactor can remove it (observed SUCCESS).
--   3. The hashes are service_role-only (this table), so even reading a code to
--      verify it is service_role.
--   => The Slice-2b recovery endpoint is a 4th RT-26 allowlist surface. THAT change
--      (the api/src service_role use + scripts/ci/rt26-allowlist.txt + the ADR-016
--      amendment) lands with Slice 2b — NOT this migration (026 adds no api/src
--      service_role code). §10 count STAYS 3 (intra-RT-26-instance amendment).
--
-- ----------------------------------------------------------------------------
-- Numbering: 026 follows 025. Depends on 024 (grants on pfin.user_settings) and on
--   auth.users (the tenant-anchor FK). 008 already granted service_role USAGE on
--   schema pfin (relied on here; not re-granted). Order-dependent: after 024/008.
--   No later migration depends on 026 landing first.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — pure base-table + GRANTs; NO function authored.
--   No SECURITY DEFINER and no SECURITY INVOKER function is defined → the DEFINER
--   allowlist is UNCHANGED at 3 (ADR-011 Decision 9). `set search_path=''` is N/A
--   (a function-body guard; no function here). The service_role grants are DB-ACL
--   privileged-context-write grants (ADR-011 Decision 1) — least-privilege, scoped
--   to exactly the recovery write paths — the SAME layer-attribution as 008's
--   service_role grants, NOT a new function surface.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
-- catalogued numbered list; Decision 4 read VERBATIM before drafting). 026
-- introduces ZERO catalogued §10 instances; the ledger stays at 3 (RT-22 first /
-- RT-26 second / RT-27 third). A service_role DB-ACL GRANT can LOOK RT-26-adjacent
-- but is NOT — stated explicitly (same reasoning as 008):
--   (i)   Instance-numbering: unchanged — RT-22 / RT-26 / RT-27.
--   (ii)  Layer-attribution: unchanged —
--           · RT-22 = PDF-worker infra-credential-presence (untouched);
--           · RT-26 = the CODE-layer SUPABASE_SERVICE_ROLE_KEY literal allowlist
--             (grep fence over api/src). THIS migration is a DB-layer ACL grant to
--             the service_role ROLE — it references no service_role KEY and touches
--             no api/src code surface. Broadening service_role's DB reach does not
--             add/move an RT-26 instance (identical to 008's reasoning). The RT-26
--             ALLOWLIST grows 3→4 only when the Slice-2b ENDPOINT code lands (an
--             ADR-016 amendment + rt26-allowlist.txt edit), and even then the §10
--             catalogued COUNT stays 3 (intra-instance allowlist growth);
--           · RT-27 = app→worker credential-admission network surface (untouched).
--   (iii) Verbatim-vs-paraphrase: Decision 4 linked, not restated.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family count +0
-- (UNCHANGED). pfin.mfa_recovery_code has exactly ONE reference column,
--   users_id -> auth.users(id), which IS the tenant anchor itself — NOT a
--   cross-tenant reference to another pfin row (identical shape to user_settings /
--   user_taxonomy). No INTEGER[]/array FK, no self-FK, no cross-table FK. Family
--   UNCHANGED; no matched-tenant obligation. (Stated per the mandatory
--   FK-shaped-column check.)
--
-- ----------------------------------------------------------------------------
-- C6 EXPOSURE / RLS-COVERAGE NOTE (ADR-023 C6). pfin is in the [api] schemas, so a
--   table is internet-facing THE MOMENT it is granted to authenticated/anon. This
--   table is granted to NEITHER — RLS is ENABLED with ZERO authenticated policy and
--   ZERO authenticated/anon GRANT → default-deny at the authenticated tier at BOTH
--   layers (ACL + RLS). Only service_role (BYPASSRLS + the explicit grants below)
--   reaches it. So there is NO authenticated read/write path to the hashes via the
--   data API. QA's pairing is a DEFAULT-DENY assertion (an authenticated session
--   reads/writes 0 rows / is refused), NOT a two-tenant cross-read battery (there is
--   no authenticated grant to cross). Sec sign-off gates the merge (service_role
--   grant surface = Decision-1 joint-review territory).
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.mfa_recovery_code — one row per issued one-time MFA backup code.
--     - code_id (bigint identity PK): surrogate row id.
--     - users_id (uuid NOT NULL DEFAULT auth.uid()): the tenant anchor AND the ONLY
--       reference column; FK -> auth.users(id) ON DELETE CASCADE (codes die with the
--       user). Decision-3 family UNCHANGED (tenant anchor, not a cross-tenant FK).
--     - code_hash (text NOT NULL): the APP-SIDE bcrypt/argon2 hash of the plaintext
--       code. Plaintext is shown to the user ONCE at issuance and NEVER stored/logged;
--       the DB holds only the hash. Redemption verifies via an app-side constant-time
--       compare (the hash never leaves the service_role endpoint).
--     - batch_id (uuid NOT NULL): groups an issued set; regenerate issues a new
--       batch and supersedes the prior one (old live codes marked used_at).
--     - used_at (timestamptz NULL): NULL = unspent. Set once on redemption — the
--       one-time-use / double-spend guard (redeem UPDATE keys on `used_at IS NULL`).
--     - created_at (timestamptz NOT NULL DEFAULT now()).
--   Security-load-bearing edges: SERVICE_ROLE-ONLY (RLS on + no authenticated
--     policy/grant → default-deny at the authenticated tier; hashes never reach the
--     data API); one-time-use via used_at; tenant-cascade via ON DELETE CASCADE.
--   Grants on pfin.user_settings (the recovery downgrade path):
--     - service_role select(users_id) + update(mfa_policy) — LEAST-PRIVILEGE. The
--       update(mfa_policy) lets recovery flip mfa_policy->'none' (guard-exempt as
--       service_role); select(users_id) is REQUIRED for the UPDATE's WHERE
--       users_id=$1 (Postgres needs SELECT on columns read in the WHERE — verified:
--       update(mfa_policy) alone raises `permission denied for table user_settings`).
--       service_role CANNOT read mfa_policy or any other column, and CANNOT write any
--       column other than mfa_policy.
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- pfin.mfa_recovery_code — service_role-only one-time backup-code store.
-- ----------------------------------------------------------------------------
create table if not exists pfin.mfa_recovery_code (
  code_id     bigint generated always as identity primary key,
  users_id    uuid not null default auth.uid()
                references auth.users (id) on delete cascade,
  code_hash   text not null,
  batch_id    uuid not null,
  used_at     timestamptz,
  created_at  timestamptz not null default now()
);

comment on table pfin.mfa_recovery_code is
  'One-time MFA backup (recovery) codes (SELF-291 / Auth-3b Slice 2a; F/CTO Opt A '
  '2026-07-22). One row per issued code; stores ONLY the app-side bcrypt/argon2 hash '
  '(plaintext shown once at issuance, never persisted). SERVICE_ROLE-ONLY: RLS '
  'enabled with NO authenticated policy and NO authenticated/anon grant → default-deny '
  'at the authenticated tier (mirrors linked_source_sync_audit); the hashes never '
  'reach the direct PostgREST API. Issuance (INSERT) + redemption (SELECT the live '
  'hashes, UPDATE used_at to consume) are privileged Slice-2b server operations under '
  'service_role. one-time-use via used_at (redeem keys on used_at IS NULL). batch_id '
  'groups an issued set (regenerate supersedes). users_id is the sole tenant-anchor FK '
  '(Decision-3 UNCHANGED). Recovery mints NO aal2 — it consumes a code, downgrades '
  'mfa_policy->none, and admin-removes the dead factor so the user is aal1-sufficient, '
  'then re-enrolls (ADR-029/ADR-030 reframe). The /mfa/recover endpoint is Slice 2b.';

comment on column pfin.mfa_recovery_code.code_hash is
  'App-side bcrypt/argon2 hash of the one-time code. DB stores ONLY the hash; '
  'plaintext is displayed to the user once at issuance and never stored/logged. '
  'Verification is an app-side constant-time compare inside the service_role endpoint.';

comment on column pfin.mfa_recovery_code.used_at is
  'NULL = unspent. Set once on redemption — the one-time-use / double-spend guard '
  '(the redeem UPDATE keys on used_at IS NULL so a replay is a no-op). Regenerate also '
  'sets used_at on superseded live codes.';

alter table pfin.mfa_recovery_code enable row level security;

-- SERVICE_ROLE-ONLY: NO authenticated/anon policy (default-deny at the authenticated
-- tier). service_role is BYPASSRLS but ACL is checked independently, so it still needs
-- the explicit table grants below. Redemption reads live hashes (SELECT) + consumes
-- (UPDATE used_at); issuance writes the batch (INSERT). No DELETE grant (regenerate
-- supersedes via used_at; row lifecycle otherwise via the auth.users ON DELETE CASCADE).
grant select, insert, update on pfin.mfa_recovery_code to service_role;
-- anon: zero. authenticated: zero. (No grant → no data-API reach to the hashes.)

-- Index for the redemption hot path: live codes for a user.
create index if not exists mfa_recovery_code_user_live_idx
  on pfin.mfa_recovery_code (users_id) where used_at is null;

-- ----------------------------------------------------------------------------
-- Recovery downgrade grant on pfin.user_settings (Decision-1 privileged-write,
-- least-privilege). Lets the Slice-2b recovery endpoint flip mfa_policy->'none' for
-- a locked-out authenticated-aal1 user; the MB-1 guard (025) exempts service_role.
--   update(mfa_policy): the ONLY column service_role may write here.
--   select(users_id):   REQUIRED for the UPDATE's WHERE users_id=$1 (Postgres needs
--                       SELECT on WHERE-referenced columns; update(mfa_policy) ALONE
--                       raises `permission denied for table user_settings` — verified
--                       empirically). service_role still cannot read mfa_policy/any
--                       other column, nor write any column but mfa_policy.
-- ----------------------------------------------------------------------------
grant select (users_id), update (mfa_policy) on pfin.user_settings to service_role;

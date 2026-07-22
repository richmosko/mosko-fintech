-- ============================================================================
-- Migration: pfin.mfa_recovery_attempt — append-only recovery-redemption attempt
-- log (the rate-limit / lockout substrate). Phase 6 Build Loop (SELF-291 / Auth-3b
-- Slice 2b — the STORE ONLY; the /mfa/recover endpoint + the rate-gate logic are
-- the Slice-2b app PR, NOT here). F/CTO-ratified 2026-07-22 (Opt 1: DB-backed
-- rate-limit table — multi-instance-correct, since the app may run multi-instance
-- behind Coolify and in-memory per-instance state would not share the limit).
--
-- WHAT THIS DOES: creates pfin.mfa_recovery_attempt — one append-only row per
--   recovery-code redemption attempt (users_id + attempted_at + succeeded). The
--   Slice-2b recovery endpoint INSERTs a row per attempt and reads the trailing-hour
--   FAILURE count to enforce the ratified rate-limit (5 failures / hour / user →
--   temporary lockout). SERVICE_ROLE-ONLY (RLS enabled, ZERO authenticated policy →
--   default-deny at the authenticated tier; mirrors 026 / linked_source_sync_audit):
--   the attempt log is written+read only by the privileged recovery endpoint under
--   service_role. APPEND-ONLY: service_role gets SELECT + INSERT only (NO UPDATE /
--   DELETE) — rows age out of relevance via the trailing-hour window query; a bulk
--   prune of stale rows is a V1.x maintenance follow-up (see RETENTION note).
--
-- No function is authored. DEFINER allowlist UNCHANGED at 3. §10 catalogued ledger
-- UNCHANGED at 3 (RT-22/RT-26/RT-27) — a service_role DB-ACL grant is NOT an RT-26
-- code-layer change (see §10 block). Decision-3 family UNCHANGED.
--
-- ----------------------------------------------------------------------------
-- Numbering: 027 follows 026. Depends only on auth.users (the tenant-anchor FK) and
--   on 008 (service_role USAGE on schema pfin, relied on; not re-granted). References
--   no pfin table. Order-dependent only on 008/auth.users. No later migration depends
--   on 027. (Slice-2b's RT-26 4th surface — the api/src supabase-admin.ts factory +
--   the ADR-016 amendment + the scripts/ci/rt26-allowlist.txt append — lands with the
--   APP PR, NOT here: 027 adds no api/src code and NO SUPABASE_SERVICE_ROLE_KEY ref,
--   so it touches neither RT-26 nor the allowlist nor ADR-016.)
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — pure base-table + GRANTs; NO function authored.
--   No SECURITY DEFINER and no SECURITY INVOKER function is defined → the DEFINER
--   allowlist is UNCHANGED at 3 (ADR-011 Decision 9). `set search_path=''` is N/A
--   (no function here). The service_role grants are DB-ACL privileged-context-write
--   grants (ADR-011 Decision 1) — least-privilege (SELECT + INSERT only), the SAME
--   layer-attribution as 008's / 026's service_role grants, NOT a function surface
--   and NOT the RT-26 code-layer key allowlist.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
-- catalogued numbered list; Decision 4 read VERBATIM before drafting). 027
-- introduces ZERO catalogued §10 instances; the ledger stays at 3 (RT-22 first /
-- RT-26 second / RT-27 third). A service_role DB-ACL GRANT can LOOK RT-26-adjacent
-- but is NOT (same reasoning as 008 / 026):
--   (i)   Instance-numbering: unchanged — RT-22 / RT-26 / RT-27.
--   (ii)  Layer-attribution: unchanged —
--           · RT-22 = PDF-worker infra-credential-presence (untouched);
--           · RT-26 = the CODE-layer SUPABASE_SERVICE_ROLE_KEY literal allowlist
--             (grep fence over api/src). THIS migration is a DB-layer ACL grant to
--             the service_role ROLE — it references no service_role KEY and touches
--             no api/src code surface. The RT-26 allowlist 3→4 growth + the ADR-016
--             amendment land with the Slice-2b APP PR (the supabase-admin.ts factory),
--             NOT here; even then the §10 catalogued COUNT stays 3 (intra-instance);
--           · RT-27 = app→worker credential-admission network surface (untouched).
--   (iii) Verbatim-vs-paraphrase: Decision 4 linked, not restated.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family count +0
-- (UNCHANGED). pfin.mfa_recovery_attempt has exactly ONE reference column,
--   users_id -> auth.users(id), which IS the tenant anchor itself — NOT a
--   cross-tenant reference to another pfin row (identical shape to 026
--   mfa_recovery_code / user_settings / user_taxonomy). No INTEGER[]/array FK, no
--   self-FK, no cross-table FK. Family UNCHANGED; no matched-tenant obligation.
--   (Stated per the mandatory FK-shaped-column check.)
--
-- ----------------------------------------------------------------------------
-- C6 EXPOSURE / RLS-COVERAGE NOTE (ADR-023 C6). pfin is in the [api] schemas, so a
--   table is internet-facing the moment it is granted to authenticated/anon. This
--   table is granted to NEITHER — RLS ENABLED with ZERO authenticated policy and
--   ZERO authenticated/anon grant → default-deny at the authenticated tier at BOTH
--   layers (ACL + RLS). Only service_role (BYPASSRLS + the explicit grants below)
--   reaches it. QA's pairing is a DEFAULT-DENY assertion (an authenticated session
--   reads/writes 0 rows / is refused), NOT a two-tenant cross-read battery (no
--   authenticated grant to cross). Sec sign-off gates the merge (service_role grant
--   surface = Decision-1 joint-review territory). Tenant correctness for the
--   service_role reads/writes is bound IN CODE (the endpoint filters users_id =
--   <uid> on every query — service_role BYPASSRLS, so the WHERE is the tenant fence;
--   the Decision-1 code-side-binding discipline).
--
-- ----------------------------------------------------------------------------
-- RETENTION: append-only; no service_role UPDATE/DELETE. The rate-gate reads only a
--   trailing-hour window, so stale rows are irrelevant to correctness but accumulate.
--   A bulk prune (delete rows older than a small retention window, run under a
--   maintenance role — NOT service_role, which holds no DELETE here) is a V1.x
--   follow-up; V1.0 tolerates the growth (one narrow row per redemption attempt).
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.mfa_recovery_attempt — one append-only row per recovery-code redemption
--     attempt; the rate-limit / lockout substrate.
--     - attempt_id (bigint identity PK): surrogate row id.
--     - users_id (uuid NOT NULL DEFAULT auth.uid()): the tenant anchor AND the ONLY
--       reference column; FK -> auth.users(id) ON DELETE CASCADE. Decision-3
--       UNCHANGED (tenant anchor, not a cross-tenant FK).
--     - succeeded (boolean NOT NULL): TRUE = the attempt redeemed a valid code;
--       FALSE = a miss. The rate-gate counts FAILURES (succeeded = false) in the
--       trailing hour.
--     - attempted_at (timestamptz NOT NULL DEFAULT now()): attempt time; the
--       trailing-hour window key.
--   Hot query: count(*) WHERE users_id = $uid AND succeeded = false
--              AND attempted_at > now() - interval '1 hour'  >= 5  → locked.
--   Security-load-bearing edges: SERVICE_ROLE-ONLY (RLS on + no authenticated
--     policy/grant → default-deny at the authenticated tier); APPEND-ONLY
--     (service_role SELECT + INSERT only — no UPDATE/DELETE); tenant-cascade via
--     ON DELETE CASCADE; tenant scope bound in code (users_id filter under
--     service_role BYPASSRLS).
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- pfin.mfa_recovery_attempt — service_role-only append-only redemption-attempt log.
-- ----------------------------------------------------------------------------
create table if not exists pfin.mfa_recovery_attempt (
  attempt_id    bigint generated always as identity primary key,
  users_id      uuid not null default auth.uid()
                  references auth.users (id) on delete cascade,
  succeeded     boolean not null,
  attempted_at  timestamptz not null default now()
);

comment on table pfin.mfa_recovery_attempt is
  'Append-only recovery-code redemption-attempt log (SELF-291 / Auth-3b Slice 2b; '
  'F/CTO Opt 1 2026-07-22). Backs the ratified rate-limit: 5 FAILURES / hour / user '
  '→ temporary lockout. One row per attempt (users_id, succeeded, attempted_at). '
  'SERVICE_ROLE-ONLY: RLS enabled with NO authenticated policy and NO '
  'authenticated/anon grant → default-deny at the authenticated tier (mirrors 026 / '
  'linked_source_sync_audit); the Slice-2b recovery endpoint is the sole writer/reader '
  'under service_role. APPEND-ONLY: service_role holds SELECT + INSERT only (no '
  'UPDATE/DELETE). DB-backed (not in-memory) so the lockout is correct across a '
  'multi-instance deploy. Rate-gate query counts succeeded=false in the trailing hour. '
  'users_id is the sole tenant-anchor FK (Decision-3 UNCHANGED); tenant scope is bound '
  'in code (users_id filter under service_role BYPASSRLS). Retention: stale rows age '
  'out of the window; a prune is a V1.x follow-up.';

comment on column pfin.mfa_recovery_attempt.succeeded is
  'TRUE = the attempt redeemed a valid one-time code; FALSE = a miss. The rate-gate '
  'counts FAILURES (succeeded = false) in the trailing hour.';

alter table pfin.mfa_recovery_attempt enable row level security;

-- SERVICE_ROLE-ONLY: NO authenticated/anon policy (default-deny at the authenticated
-- tier). service_role is BYPASSRLS but ACL is checked independently, so it still needs
-- the explicit grants below. APPEND-ONLY: SELECT (read the trailing-hour count) +
-- INSERT (log each attempt); NO UPDATE/DELETE grant.
grant select, insert on pfin.mfa_recovery_attempt to service_role;
-- anon: zero. authenticated: zero. (No grant → no data-API reach.)

-- Partial index for the rate-gate hot query (failures per user, time-ordered). The
-- WHERE succeeded IS FALSE partial keeps it tight — only failing attempts are counted.
create index if not exists mfa_recovery_attempt_user_fail_idx
  on pfin.mfa_recovery_attempt (users_id, attempted_at) where succeeded = false;

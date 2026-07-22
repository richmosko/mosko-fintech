-- =====================================================================
-- Per-Wave battery — 027 mfa_recovery_attempt (rate-limit / lockout substrate)
--   (SELF-291 / Auth-3b Slice 2b — the STORE only; the /mfa/recover endpoint +
--   rate-gate logic are the Slice-2b app PR). V1-SHIP-BLOCK. Sec sign-off gates merge.
--
--   DEFAULT-DENY battery (same shape as the 026 store): pfin.mfa_recovery_attempt has
--   RLS enabled, ZERO authenticated policy, ZERO authenticated/anon grant, and
--   service_role SELECT+INSERT ONLY (APPEND-ONLY — no UPDATE/DELETE). The proof:
--   the authenticated tier is refused at BOTH layers, service_role can append + read,
--   the append-only posture holds (service_role UPDATE/DELETE denied), and the DB half
--   of the 5-failures/hour/user rate-gate query discriminates correctly.
--   (SECURITY §4.5 posture on a service_role-only surface; ADR-023 C6.)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/027_mfa_recovery_attempt.sql
--   pfin.mfa_recovery_attempt (attempt_id bigint identity PK; users_id uuid NOT NULL
--     DEFAULT auth.uid() -> auth.users ON DELETE CASCADE; succeeded boolean NOT NULL;
--     attempted_at timestamptz NOT NULL DEFAULT now()). RLS ENABLED, NO authenticated
--     policy. GRANT select,insert TO service_role (NO update/delete); anon/
--     authenticated ZERO. Partial index (users_id, attempted_at) WHERE succeeded=false.
--   Rate-gate hot query: count(*) WHERE users_id=$uid AND succeeded=false
--     AND attempted_at > now() - interval '1 hour'  >= 5 → locked.
--
-- Prereqs exercised (001->027 reset stack): 001 (pfin schema, auth.uid()); 008
--   (service_role USAGE on schema pfin); 027 (the surface under test). auth.users
--   supplies the tenant-anchor FK target.
--
-- Idiom (mirrors 026): \ir shared verbs; role restored to postgres between blocks
--   (PR #121). Fixtures at role=postgres (superuser → bypasses RLS + ACL). Positive
--   service_role CAPABILITY cases run as BARE statements under _rls.set_service_role()
--   (a denied one would raise and fail the file — the 025 case-F idiom), asserted by
--   effect at postgres. DENIAL cases use _rls.stmt_denied_as(role, sql) + ok() at
--   postgres, so no pgTAP runs under service_role/anon.
--
-- ┌─ WHY EACH ASSERTION CATCHES A REAL VIOLATION (no vacuous green) ──────────────────────┐
-- │ (1a-b)/(2a): otherwise-VALID statements → an added authenticated/anon grant would      │
-- │   SUCCEED → stmt_denied_as returns FALSE → ok() RED. Green ONLY because ACL denies.    │
-- │ (3a-b): run as service_role — drop the select/insert grant and the bare statement      │
-- │   raises → file fails. postgres-side effect check proves it landed.                    │
-- │ (4a/4b): the UPDATE/DELETE target a REAL row (:aid) — if the append-only posture were   │
-- │   widened to grant update/delete, the statement would affect 1 row (denied=FALSE) → RED.│
-- │ (5a): the gate query returns 2 with a success row AND an out-of-window failure present  │
-- │   — RED if the succeeded=false filter OR the trailing-hour window were wrong.           │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22/RT-26/RT-27 — a service_role DB-ACL
--   grant is not an RT-26 code-layer change; the RT-26 allowlist 3->4 growth lands with
--   the Slice-2b app PR). Decision-3 family UNCHANGED (users_id is the tenant anchor FK).
--   No function authored; DEFINER allowlist 3.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants; NO PII / NO prod data.
--   All in a rolled-back txn. No test-only grant added (service_role already holds the
--   027 SELECT+INSERT grants; the append-only proof needs NONE — it asserts the ABSENCE
--   of update/delete).
--
-- ⟦WIRE-VALIDATE⟧ authored against 027's DDL; authoritative run = the 001->027 reset
--   stack under CI (pg_prove directory-mode, db-tests.yml). Roles authenticated / anon /
--   service_role name-checked in the blocks. plan(8).
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

select plan(8);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- FIXTURE (PRIVILEGED postgres). Tenants A + B in auth.users. B carries the rate-gate
-- fixture (block 5): 2 recent failures + 1 recent success + 1 out-of-window (2h-old)
-- failure → the trailing-hour FAILURE count for B must be exactly 2. A is used by the
-- service_role append/read capability (block 3) so B's gate count stays isolated.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.mfa_recovery_attempt (users_id, succeeded, attempted_at) values
  (:'tb', false, now()),                        -- recent failure #1  (counted)
  (:'tb', false, now()),                        -- recent failure #2  (counted)
  (:'tb', true,  now()),                        -- recent SUCCESS     (excluded: succeeded=true)
  (:'tb', false, now() - interval '2 hours');   -- OLD failure        (excluded: outside window)

-- =====================================================================
-- BLOCK 1 — authenticated DEFAULT-DENIED on mfa_recovery_attempt at the ACL layer
--   (no authenticated grant → table unreachable before RLS). Probed statements carry
--   valid values/columns, so a grant regression flips green→red.
-- =====================================================================
select ok(
  _rls.stmt_denied_as('authenticated', 'select count(*) from pfin.mfa_recovery_attempt'),
  '(1a) authenticated SELECT on pfin.mfa_recovery_attempt is DENIED (no authenticated grant; ACL denies table reach) — the attempt log is unreachable via the direct data API'
);
select ok(
  _rls.stmt_denied_as('authenticated', format($$ insert into pfin.mfa_recovery_attempt (users_id, succeeded) values (%L, false) $$, :'ta')),
  '(1b) authenticated INSERT is DENIED (no authenticated insert grant) — a tenant cannot forge attempt rows to poison/evade the rate-gate (statement is otherwise valid → non-vacuous)'
);

-- =====================================================================
-- BLOCK 2 — anon DEFAULT-DENIED at the schema-USAGE layer (no USAGE on schema pfin).
-- =====================================================================
select ok(
  _rls.stmt_denied_as('anon', 'select count(*) from pfin.mfa_recovery_attempt'),
  '(2a) anon SELECT is DENIED (anon holds no USAGE on schema pfin; denied at the schema layer, before table ACL/RLS)'
);

-- =====================================================================
-- BLOCK 3 — service_role CAN append + read (the endpoint capability). Bare statements
--   under service_role; a missing grant would raise and fail the file.
-- =====================================================================
select _rls.set_service_role();
insert into pfin.mfa_recovery_attempt (users_id, succeeded)
  values (:'ta', false)
  returning attempt_id as aid \gset
-- service_role SELECT (captures sc):
select count(*) as sc from pfin.mfa_recovery_attempt where attempt_id = :aid \gset
select set_config('role', 'postgres', true);

select is(
  (select count(*) from pfin.mfa_recovery_attempt where attempt_id = :aid)::bigint, 1::bigint,
  '(3a) service_role INSERT persisted an attempt row (append capability; insert grant works)'
);
select is(
  :sc::bigint, 1::bigint,
  '(3b) service_role SELECT returned the row (rate-gate read capability; ran under service_role — a missing select grant would have raised)'
);

-- =====================================================================
-- BLOCK 4 — APPEND-ONLY enforced: service_role has NO update/delete grant. Both target
--   the REAL row (:aid) so a widened grant would actually mutate → non-vacuous.
-- =====================================================================
select ok(
  _rls.stmt_denied_as('service_role', format($$ update pfin.mfa_recovery_attempt set succeeded = true where attempt_id = %s $$, :aid)),
  '(4a) service_role UPDATE is DENIED (append-only: only select+insert granted) — a logged attempt cannot be rewritten (e.g. a failure flipped to success); RED if update were granted'
);
select ok(
  _rls.stmt_denied_as('service_role', format($$ delete from pfin.mfa_recovery_attempt where attempt_id = %s $$, :aid)),
  '(4b) service_role DELETE is DENIED (append-only: no delete grant) — attempts cannot be erased to reset the rate-gate; RED if delete were granted'
);

-- =====================================================================
-- BLOCK 5 — rate-gate discrimination (DB half of the ratified 5/hr/user lockout). The
--   trailing-hour FAILURE count for B must exclude the success row AND the out-of-window
--   failure → exactly 2 (of B's 4 fixture rows).
-- =====================================================================
select is(
  (select count(*) from pfin.mfa_recovery_attempt
     where users_id = :'tb' and succeeded = false
       and attempted_at > now() - interval '1 hour')::bigint,
  2::bigint,
  '(5a) rate-gate query returns 2 for B: the recent SUCCESS is excluded (succeeded=false filter) and the 2h-old failure is excluded (trailing-hour window) — the DB half of the 5-failures/hour/user lockout discriminates correctly'
);

select * from finish();
rollback;

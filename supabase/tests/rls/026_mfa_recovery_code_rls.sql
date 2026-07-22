-- =====================================================================
-- Per-Wave battery — 026 mfa_recovery_code + recovery downgrade grant
--   (SELF-291 / Auth-3b Slice 2a — the STORE only; the /mfa/recover endpoint is 2b).
--   V1-SHIP-BLOCK. Sec sign-off gates the 2a merge.
--
--   This is a DEFAULT-DENY battery, NOT a two-tenant cross-read: pfin.mfa_recovery_code
--   has RLS enabled with ZERO authenticated policy and ZERO authenticated/anon GRANT,
--   so there is no authenticated grant to cross — the proof is that the authenticated
--   tier is refused at BOTH layers (ACL denies table reach before RLS is consulted),
--   that service_role CAN operate the store, that the used_at consumption predicate
--   discriminates spent-vs-unspent, and that the user_settings recovery grant is
--   EXACTLY column-scoped select(users_id)+update(mfa_policy).
--   (SECURITY §4.5 posture EXTENDED to a service_role-only surface; ADR-023 C6.)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/026_mfa_recovery_code.sql
--   pfin.mfa_recovery_code (code_id bigint identity PK; users_id uuid NOT NULL DEFAULT
--     auth.uid() -> auth.users ON DELETE CASCADE; code_hash text NOT NULL; batch_id
--     uuid NOT NULL; used_at timestamptz NULL = unspent; created_at). RLS ENABLED, NO
--     authenticated policy. GRANT select,insert,update TO service_role; anon/
--     authenticated ZERO. Partial index (users_id) WHERE used_at IS NULL.
--   pfin.user_settings: GRANT select(users_id), update(mfa_policy) TO service_role
--     (the recovery downgrade path; least-privilege, column-scoped).
--
-- Prereqs exercised (001->026 reset stack): 001 (pfin schema, auth.uid()); 008
--   (service_role USAGE on schema pfin); 024 (pfin.user_settings + its CHECK, now
--   ('none','totp') after 025 PART 3); 025 (the MB-1 guard that exempts service_role);
--   026 (the surface under test). auth.users supplies the tenant-anchor FK target.
--
-- Idiom: \ir shared verbs; role restored to postgres between blocks (PR #121). Fixtures
--   built at role=postgres (superuser → bypasses RLS + ACL). Positive service_role
--   CAPABILITY cases run as BARE statements under _rls.set_service_role() (a denied one
--   would raise and fail the file — the 025 case-F idiom), asserted by their EFFECT at
--   postgres. DENIAL cases use _rls.stmt_denied_as(role, sql) + ok() at postgres, so no
--   pgTAP runs under service_role/anon.
--
-- ┌─ WHY EACH ASSERTION CATCHES A REAL VIOLATION (no vacuous green) ──────────────────────┐
-- │ (1a-c)/(2a): the probed statements are otherwise-VALID (real values, real columns),   │
-- │   so if any authenticated/anon GRANT were added the statement would SUCCEED →          │
-- │   stmt_denied_as returns FALSE → ok() RED. They go green ONLY because the ACL denies.  │
-- │ (3a-c): run as service_role — remove any of the select/insert/update grants and the    │
-- │   bare statement raises → file fails. The postgres-side effect check proves it landed. │
-- │ (4a/4b): the SAME redeem UPDATE affects 1 row then 0 rows — RED if used_at IS NULL      │
-- │   weren't the arbiter (a missing predicate would let the replay re-consume → 1,1).     │
-- │ (5a-d): prove the grant is EXACTLY select(users_id)+update(mfa_policy): mfa_policy      │
-- │   write OK + users_id read OK, but a non-granted column write (created_at) AND a        │
-- │   non-granted column read (mfa_policy) are both DENIED. Widen the grant → (5b)/(5d) RED.│
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22/RT-26/RT-27 — a service_role DB-ACL
--   grant is not an RT-26 code-layer change; the RT-26 allowlist 3->4 growth lands with
--   the Slice-2b endpoint, not here). Decision-3 family UNCHANGED (users_id is the tenant
--   anchor FK, not a cross-tenant reference). No function authored; DEFINER allowlist 3.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenant + synthetic hashes; NO PII /
--   NO real recovery codes / NO prod data. All in a rolled-back txn. No test-only grant is
--   added (none needed — service_role already holds the 026 grants).
--
-- ⟦WIRE-VALIDATE⟧ authored against 026's DDL; authoritative run = the 001->026 reset stack
--   under CI (pg_prove directory-mode, db-tests.yml). Roles authenticated / anon /
--   service_role name-checked in the blocks. plan(13).
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

select plan(13);

select _rls.tenant_a() as ta \gset

-- ---------------------------------------------------------------------
-- FIXTURE (PRIVILEGED postgres). Tenant A in auth.users + a user_settings row at
-- 'totp' (the recovery-downgrade target for block 5). mfa_recovery_code rows are
-- created by service_role in blocks 3/4 (that IS the capability under test).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta');
insert into pfin.user_settings (users_id, mfa_policy) values (:'ta', 'totp');

-- =====================================================================
-- BLOCK 1 — authenticated is DEFAULT-DENIED on mfa_recovery_code at the ACL layer
--   (no authenticated grant → table unreachable before RLS is even consulted). The
--   probed statements carry valid values/columns, so a grant regression flips them
--   green→red.
-- =====================================================================
select ok(
  _rls.stmt_denied_as('authenticated', 'select count(*) from pfin.mfa_recovery_code'),
  '(1a) authenticated SELECT on pfin.mfa_recovery_code is DENIED (no authenticated grant; ACL denies table reach) — the hashes are unreachable via the direct data API'
);
select ok(
  _rls.stmt_denied_as('authenticated', format($$ insert into pfin.mfa_recovery_code (users_id, code_hash, batch_id) values (%L, 'x', '00000000-0000-0000-0000-0000000000bf') $$, :'ta')),
  '(1b) authenticated INSERT is DENIED (no authenticated insert grant) — a tenant cannot mint recovery-code rows via the data API (statement is otherwise valid → non-vacuous)'
);
select ok(
  _rls.stmt_denied_as('authenticated', 'update pfin.mfa_recovery_code set used_at = now() where code_id = 1'),
  '(1c) authenticated UPDATE is DENIED (no authenticated update grant) — a tenant cannot consume/alter codes via the data API'
);

-- =====================================================================
-- BLOCK 2 — anon is DEFAULT-DENIED at the schema-USAGE layer (anon holds no USAGE on
--   schema pfin), a layer even further out than the table ACL.
-- =====================================================================
select ok(
  _rls.stmt_denied_as('anon', 'select count(*) from pfin.mfa_recovery_code'),
  '(2a) anon SELECT is DENIED (anon holds no USAGE on schema pfin; denied at the schema layer, before table ACL/RLS)'
);

-- =====================================================================
-- BLOCK 3 — service_role CAN operate the store (issuance + redemption capability).
--   Bare statements under service_role; a missing grant would raise and fail the file.
-- =====================================================================
select _rls.set_service_role();
insert into pfin.mfa_recovery_code (users_id, code_hash, batch_id)
  values (:'ta', 'hash-3', '00000000-0000-0000-0000-0000000000b1')
  returning code_id as cid3 \gset
-- service_role SELECT (captures sc3) then service_role UPDATE (consume):
select count(*) as sc3 from pfin.mfa_recovery_code where code_id = :cid3 \gset
update pfin.mfa_recovery_code set used_at = now() where code_id = :cid3;
select set_config('role', 'postgres', true);

select is(
  (select count(*) from pfin.mfa_recovery_code where code_id = :cid3)::bigint, 1::bigint,
  '(3a) service_role INSERT persisted a code row (issuance capability; insert grant works)'
);
select is(
  :sc3::bigint, 1::bigint,
  '(3b) service_role SELECT returned the row (redemption read capability; the select ran under service_role — a missing select grant would have raised)'
);
select is(
  (select used_at is not null from pfin.mfa_recovery_code where code_id = :cid3), true,
  '(3c) service_role UPDATE set used_at (consume capability; update grant works)'
);

-- =====================================================================
-- BLOCK 4 — the used_at IS NULL consumption arbiter (DB half of the atomic
--   check-and-consume; the endpoint TOCTOU test is Slice 2b). The SAME redeem UPDATE
--   affects 1 row while unspent, 0 rows once spent.
-- =====================================================================
select _rls.set_service_role();
insert into pfin.mfa_recovery_code (users_id, code_hash, batch_id)
  values (:'ta', 'hash-4', '00000000-0000-0000-0000-0000000000b2')
  returning code_id as cid4 \gset
with u as (
  update pfin.mfa_recovery_code set used_at = now()
   where code_id = :cid4 and used_at is null returning 1
) select count(*) as n1 from u \gset
with u as (
  update pfin.mfa_recovery_code set used_at = now()
   where code_id = :cid4 and used_at is null returning 1
) select count(*) as n2 from u \gset
select set_config('role', 'postgres', true);

select is(:n1::bigint, 1::bigint,
  '(4a) unspent code: redeem UPDATE ... WHERE used_at IS NULL affects 1 row (the code is consumed)');
select is(:n2::bigint, 0::bigint,
  '(4b) already-spent code: the SAME redeem UPDATE affects 0 rows (used_at IS NULL no longer matches — the DB double-spend guard); RED if used_at IS NULL weren''t the arbiter');

-- =====================================================================
-- BLOCK 5 — the user_settings recovery grant is EXACTLY select(users_id)+update(mfa_policy).
--   (5a) service_role flips mfa_policy->'none' (the guard-exempt recovery downgrade); the
--   MB-1 guard (025) does not fire because current_user='service_role', not 'authenticated'.
-- =====================================================================
select _rls.set_service_role();
update pfin.user_settings set mfa_policy = 'none' where users_id = :'ta';  -- OK: update(mfa_policy)+select(users_id)
select set_config('role', 'postgres', true);
select is(
  (select mfa_policy from pfin.user_settings where users_id = :'ta'), 'none',
  '(5a) service_role UPDATE mfa_policy->''none'' SUCCEEDS (guard-exempt recovery downgrade; column update(mfa_policy) grant) — row is now ''none'''
);

select ok(
  not _rls.stmt_denied_as('service_role', format($$ select users_id from pfin.user_settings where users_id = %L $$, :'ta')),
  '(5c) service_role SELECT users_id SUCCEEDS (select(users_id) grant present — required for the recovery UPDATE''s WHERE)'
);
select ok(
  _rls.stmt_denied_as('service_role', format($$ update pfin.user_settings set created_at = now() where users_id = %L $$, :'ta')),
  '(5b) service_role UPDATE of a NON-granted column (created_at) is DENIED — the grant is column-scoped to update(mfa_policy) only; RED if it were widened to a table-level update'
);
select ok(
  _rls.stmt_denied_as('service_role', format($$ select mfa_policy from pfin.user_settings where users_id = %L $$, :'ta')),
  '(5d) service_role SELECT of a NON-granted column (mfa_policy) is DENIED — the grant is select(users_id) only; service_role cannot read the factor choice back'
);

select * from finish();
rollback;

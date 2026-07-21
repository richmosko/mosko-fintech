-- =====================================================================
-- Per-Wave battery — pfin.user_settings: per-user own-row settings substrate
--   (SELF-286 / Auth-3, MFA substrate only). Two-tenant RLS isolation + the
--   mfa_policy CHECK domain + no-DELETE two-layer fail-closed + anon zero-grant.
--   (SECURITY §4.5 two-tenant posture; C6 EXPOSURE-GATING per ADR-023; V1-SHIP-BLOCK)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/024_user_settings.sql
--   - pfin.user_settings (users_id uuid PRIMARY KEY DEFAULT auth.uid() -> auth.users
--       ON DELETE CASCADE; mfa_policy text NOT NULL DEFAULT 'none'
--       CHECK (mfa_policy in ('none','totp','passkey')); created_at / updated_at).
--     ONE row per user (PK = users_id, the tenant anchor itself). LIVE write path:
--     authenticated holds SELECT+INSERT+UPDATE (owner-gated users_id = auth.uid()
--     on read AND write). NO DELETE grant + NO DELETE policy. anon zero-grant.
--     service_role UNGRANTED. updated_at via the 001 DEFINER allowlist entry #1.
-- Prereqs exercised (on the 001->024 reset stack): 001 (pfin schema +
--   fn_refresh_updated_at + auth.uid()); auth.users (the users_id anchor + FK target).
-- Reuses the 022/023 idiom: \ir verbs, lowercase \gset literals, MESSAGE-precise
--   throws (004 all-42501 false-green lesson), role restored to postgres between
--   blocks (PR #121 _rls-USAGE root-cause).
--
-- ┌─ WHY EACH REJECTION MATCHES A DISTINCT SIGNAL (no fence passes for another) ──────────┐
-- │  • cross-tenant INSERT/UPDATE forge (users_id = A under B) -> RLS WITH CHECK:           │
-- │       'new row violates row-level security policy%'  (42501, MESSAGE-precise)          │
-- │  • bad mfa_policy value ('email')  -> check_violation 23514                             │
-- │  • DELETE by owner OR intruder (no delete grant) -> 'permission denied%' (42501, ACL)  │
-- │  • anon (no schema USAGE)          -> 'permission denied%' (42501, ACL, before RLS)     │
-- │ RLS-forge raises are matched on the RLS MESSAGE (NOT a bare 42501 — ACL denial is also  │
-- │ 42501); ACL denials are matched on 'permission denied' (NOT the RLS message). So a      │
-- │ WITH CHECK failure can never be mistaken for an ACL denial, nor a 23514 for either.     │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ WHY THE RLS FORGE FIRES BEFORE THE PK COLLISION (honest note on (3c)/(3d)) ──────────┐
-- │ A already owns a row (PK users_id = A). When B forges users_id = A, Postgres evaluates  │
-- │ the RLS WITH CHECK (ExecWithCheckOptions) BEFORE the unique-index insertion, so the     │
-- │ 42501 RLS violation is raised first — the assertion sees the RLS message, not 23505.    │
-- │ Both would block; the RLS fence intercepts. The CHECK constraint (ExecConstraints)      │
-- │ fires earlier still, so the forge uses a VALID mfa_policy ('totp') to isolate RLS as    │
-- │ the sole gate (a bad value would surface 23514 first and mask the RLS proof).           │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ NO-DELETE IS DEFAULT-DENIED AT BOTH LAYERS — proven independently ───────────────────┐
-- │ The migration removes deletes at TWO layers: (outer) no DELETE grant -> ACL denies;     │
-- │ (inner) no DELETE policy -> RLS default-deny. They are proven separately:               │
-- │   (4b)/(4c) OUTER: owner AND intruder DELETE -> 'permission denied' (ACL, before RLS).  │
-- │   (4d) INNER: a TEST-ONLY `grant delete to authenticated` (rolled back; 024 grants NO   │
-- │        delete) opens the ACL layer so the RLS layer is the sole remaining gate — the    │
-- │        owner's DELETE of its OWN row then matches 0 rows (no DELETE policy = default-    │
-- │        deny) and the row SURVIVES. This is the belt-and-suspenders isolation (mirrors    │
-- │        022 BLOCK 6): it asserts the inner fence has teeth, not a prod path.             │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (1a) -> owner INSERT own row (users_id DEFAULT auth.uid() = A) COMMITS (the live write path).
--   (1b) -> default mfa_policy = 'none' when omitted; RED if the DEFAULT were dropped/changed.
--   (1c)/(1d) -> owner UPDATE own row to 'passkey' / 'totp' COMMITS; RED if the UPDATE policy
--          over-restricted the owner OR if a valid domain value were rejected (non-vacuous CHECK).
--   (1e) -> owner UPDATE to 'email' REJECTED (23514); RED if the CHECK domain were widened.
--   (2a) -> owner reads exactly its 1 own row; RED if the SELECT policy were over-restrictive.
--   (2b) -> intruder B sees 0 of A's rows; RED if the SELECT USING owner-scoping leaked.
--   (3a) -> INSERT with 'email' REJECTED (23514) on the INSERT path (CHECK covers insert too).
--   (3b) -> B INSERTs its OWN row (users_id DEFAULT = B) -> COMMITS (non-vacuous: B is not blanket-blocked).
--   (3c) -> B INSERT forging users_id = A -> RLS WITH CHECK REJECTS; RED if the INSERT WITH CHECK
--          were dropped -> B could create a row owned by A.
--   (3d) -> B UPDATE of its OWN row SET users_id = A -> RLS WITH CHECK REJECTS; RED if the UPDATE
--          WITH CHECK were dropped -> B could re-home its row onto A.
--   (4a) -> B UPDATE targeting A's row touches 0 rows (UPDATE USING owner-scoping); A UNCHANGED
--          ('totp'). RED if the UPDATE USING leaked -> B could mutate A's settings.
--   (4b)/(4c) -> owner AND intruder DELETE -> 'permission denied' (no delete grant; OUTER layer).
--          RED if a DELETE grant were added -> settings rows would become user-deletable.
--   (4d) -> INNER layer: even WITH a test-only delete grant, owner DELETE of own row matches 0
--          rows (no DELETE policy = RLS default-deny); the row SURVIVES. RED if a DELETE policy
--          were ever added.
--   (5a) -> anon SELECT -> 'permission denied' (no schema USAGE, ACL before RLS). RED if anon
--          were granted any reach into pfin.
--
-- §10 / DECISION 3: §10 ledger UNCHANGED (024 introduces ZERO catalogued §10 instances —
--   authenticated-tier own-row RLS/GRANT DDL; adds no service_role grant, no infra-credential
--   surface). Decision-3 family UNCHANGED: users_id -> auth.users(id) IS the tenant anchor AND
--   the PK (identical shape to 009 user_taxonomy.users_id) — NOT a cross-tenant reference, so
--   NO matched-tenant obligation and no fence to prove. This battery is the pgTAP proof of the
--   RLS isolation + CHECK domain + two-layer no-DELETE for the own-row table.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b();
--   NO PII / NO real account numbers / NO prod data. Both tenants own their OWN row so every
--   owner PASS and every cross-tenant FAIL has a real referent (non-vacuous). All in a
--   rolled-back txn. The TEST-ONLY delete grant (4d) is rolled back; 024 grants delete to no one.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so NO
--   `_rls.*` call runs under authenticated. Tenant UUIDs are resolved to psql LITERALS via
--   \gset at role=postgres; every _rls.set_tenant is called at role=postgres and each block
--   restores role=postgres before the next. \gset var names are ALL-LOWERCASE.
--
-- ⟦WIRE-VALIDATE⟧ authored against 024's firmed contract; the authoritative run is the
--   001->024 reset stack under CI (pg_prove directory-mode, db-tests.yml, after Backend's
--   clean-apply). Roles `authenticated` / `anon` name-checked in the blocks. plan(16).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(16);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session): just the two tenants in auth.users.
-- Each tenant creates its OWN user_settings row via the authenticated write
-- path inside its block (this table's rows are owner-inserted, not seeded).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

-- =====================================================================
-- BLOCK 1 (authenticated A) — owner write path + the DEFAULT + the CHECK domain.
--   A owns exactly ONE row (PK = users_id = A). users_id lands via DEFAULT auth.uid().
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (1a) owner INSERT own row: mfa_policy omitted -> DEFAULT 'none'; users_id -> auth.uid() = A.
select lives_ok(
  $$ insert into pfin.user_settings default values $$,
  '(1a) owner INSERT: authenticated A inserts its OWN row (users_id DEFAULT auth.uid() = A, mfa_policy omitted) -> COMMITS (the live owner write path)'
);

-- (1b) DEFAULT applied: the omitted mfa_policy is 'none'.
select is(
  (select mfa_policy from pfin.user_settings where users_id = auth.uid()),
  'none',
  '(1b) DEFAULT mfa_policy = ''none'' when omitted (a user who has chosen no factor reads as ''none'')'
);

-- (1c) owner UPDATE own row to a valid domain value -> COMMITS (proves ''passkey'' is in-domain).
select lives_ok(
  $$ update pfin.user_settings set mfa_policy = 'passkey' where users_id = auth.uid() $$,
  '(1c) owner UPDATE own row -> ''passkey'' COMMITS (owner UPDATE path + ''passkey'' is a valid CHECK value; non-vacuous domain)'
);

-- (1d) owner UPDATE own row to another valid value -> COMMITS (A ends at 'totp', the (4a) baseline).
select lives_ok(
  $$ update pfin.user_settings set mfa_policy = 'totp' where users_id = auth.uid() $$,
  '(1d) owner UPDATE own row -> ''totp'' COMMITS (''totp'' is a valid CHECK value; A now sits at ''totp'' — the (4a) tamper baseline)'
);

-- (1e) CHECK domain on UPDATE: an out-of-domain value ('email', DROPPED from the ratified model).
select throws_ok(
  $$ update pfin.user_settings set mfa_policy = 'email' where users_id = auth.uid() $$,
  '23514', null,
  '(1e) CHECK domain (UPDATE): mfa_policy = ''email'' is REJECTED (check_violation 23514) — ''email'' was dropped from the ratified auth model; the domain is exactly (none,totp,passkey)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 2 (postgres — _rls verbs) — RLS SELECT isolation, two-tenant.
--   A owns exactly 1 row; B owns 0 (B has not created its row yet).
-- =====================================================================
-- (2a) owner-reads-own: A sees exactly its 1 row (guards an over-restrictive SELECT policy).
select _rls.expect_owner_can_read('pfin.user_settings'::regclass, :'ta'::uuid, 1::bigint);

-- (2b) cross-tenant read fails closed: B sees 0 of A's rows (SELECT USING owner-scoping).
select _rls.expect_cross_tenant_read_empty('pfin.user_settings'::regclass, :'ta'::uuid, :'tb'::uuid);

-- =====================================================================
-- BLOCK 3 (authenticated B) — CHECK-on-INSERT, B's own write path, and the
--   cross-tenant ownership forge on BOTH INSERT and UPDATE (RLS WITH CHECK).
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);

-- (3a) CHECK domain on INSERT: a bad value is rejected on the insert path too (before RLS —
--      users_id DEFAULTs to B so RLS WITH CHECK would pass; the CHECK is the gate).
select throws_ok(
  $$ insert into pfin.user_settings (mfa_policy) values ('email') $$,
  '23514', null,
  '(3a) CHECK domain (INSERT): inserting mfa_policy = ''email'' is REJECTED (check_violation 23514) — the CHECK covers the INSERT path, not only UPDATE'
);

-- (3b) B INSERTs its OWN valid row (users_id DEFAULT = B) -> COMMITS. Non-vacuous control: B is
--      not blanket-blocked; the (3c)/(3d) rejections below are cross-tenant-MISMATCH-driven.
select lives_ok(
  $$ insert into pfin.user_settings default values $$,
  '(3b) control: B inserts its OWN row (users_id DEFAULT auth.uid() = B) -> COMMITS (proves B is not blanket-blocked; the forges below are ownership-mismatch-driven)'
);

-- (3c) cross-tenant INSERT forge: B inserts users_id = A with a VALID mfa_policy -> the INSERT
--      WITH CHECK (users_id = auth.uid() = B) rejects new.users_id = A. RLS fires BEFORE the PK
--      collision with A's existing row (see the honest note above), so the message is the RLS one.
select throws_like(
  format($$ insert into pfin.user_settings (users_id, mfa_policy) values (%L, 'totp') $$, :'ta'),
  '%violates row-level security policy%',
  '(3c) cross-tenant INSERT forge: B inserts users_id = A -> RLS INSERT WITH CHECK REJECTS (new.users_id != auth.uid()); B cannot create a row owned by A (a real violation, not a silent pass)'
);

-- (3d) cross-tenant UPDATE forge: B re-homes its OWN row onto A (SET users_id = A). USING
--      (users_id = auth.uid() = B) matches B's own row; the UPDATE WITH CHECK then rejects
--      new.users_id = A -> RLS violation (again before the PK collision).
select throws_like(
  format($$ update pfin.user_settings set users_id = %L where users_id = auth.uid() $$, :'ta'),
  '%violates row-level security policy%',
  '(3d) cross-tenant UPDATE forge: B re-homes its own row onto A (SET users_id = A) -> RLS UPDATE WITH CHECK REJECTS; B cannot re-home its row onto another tenant'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 4 (cross-tenant UPDATE USING isolation + the two-layer no-DELETE).
--   A owns 1 row ('totp'); B owns 1 row ('none').
-- =====================================================================
-- B UPDATE targeting A's row: USING (users_id = auth.uid() = B) filters A's row out -> 0 rows
-- affected silently (no matching row). No fence needed — A's row is invisible to B's UPDATE.
select _rls.set_tenant(:'tb'::uuid);
update pfin.user_settings set mfa_policy = 'passkey' where users_id = :'ta';  -- 0 rows (RLS hides A's row)
select set_config('role', 'postgres', true);

-- (4a) cross-tenant UPDATE blocked: A's row is UNCHANGED (still 'totp'); B's UPDATE touched 0 rows.
select is(
  (select mfa_policy from pfin.user_settings where users_id = :'ta'),
  'totp',
  '(4a) cross-tenant UPDATE blocked: after B''s UPDATE targeting A''s row, A is UNCHANGED (still ''totp'') — the UPDATE USING policy scoped B to its own rows (0 rows affected), not ''passkey'''
);

-- (4b) OUTER no-DELETE (owner): even the owner cannot delete its own row — there is NO delete
--      grant, so the ACL layer denies (permission denied) before RLS is consulted.
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  $$ delete from pfin.user_settings where users_id = auth.uid() $$,
  '%permission denied%',
  '(4b) OUTER no-DELETE (owner): authenticated A cannot delete its OWN row -> ''permission denied'' (no delete grant; ACL denies before RLS) — settings rows are not user-deletable'
);
select set_config('role', 'postgres', true);

-- (4c) OUTER no-DELETE (intruder): B deleting A's row is denied at the ACL layer too (before RLS).
select _rls.set_tenant(:'tb'::uuid);
select throws_like(
  format($$ delete from pfin.user_settings where users_id = %L $$, :'ta'),
  '%permission denied%',
  '(4c) OUTER no-DELETE (intruder): B''s DELETE of A''s row -> ''permission denied'' (no delete grant; ACL denies before RLS ever filters) — deletes are unreachable for every authenticated tenant'
);
select set_config('role', 'postgres', true);

-- (4d) INNER no-DELETE (RLS default-deny): open the ACL layer with a TEST-ONLY delete grant
--      (rolled back; 024 grants delete to NO ONE) so the RLS layer is the sole remaining gate.
--      The owner's DELETE of its OWN row then matches 0 rows (no DELETE policy = default-deny)
--      and the row SURVIVES — proving the inner fence has teeth independent of the ACL layer.
grant delete on pfin.user_settings to authenticated;  -- TEST-ONLY (rolled back)
select _rls.set_tenant(:'ta'::uuid);
delete from pfin.user_settings where users_id = auth.uid();  -- 0 rows (no DELETE policy -> RLS default-deny)
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.user_settings where users_id = :'ta')::bigint,
  1::bigint,
  '(4d) INNER no-DELETE: WITH a test-only delete grant (ACL opened), the owner''s DELETE of its OWN row matches 0 rows (no DELETE policy = RLS default-deny) and the row SURVIVES — the inner layer denies deletes independently of the ACL layer'
);

-- =====================================================================
-- BLOCK 5 (anon) — zero-grant: no USAGE on schema pfin -> denied at the ACL layer.
-- =====================================================================
select set_config('role', 'anon', true);
-- (5a) anon holds no USAGE on schema pfin -> even SELECT is denied (permission denied), before RLS.
select throws_like(
  $$ select count(*) from pfin.user_settings $$,
  '%permission denied%',
  '(5a) anon zero-grant: anon holds no USAGE on schema pfin -> SELECT is denied at the ACL layer (permission denied), before RLS — pfin.user_settings is not anon-reachable'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;

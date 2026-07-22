-- =====================================================================
-- Per-Wave battery — 025 aal2 step-up backstop (SELF-291 / Auth-3b, Slice 1).
--   V1-SHIP-BLOCK. Sec C1 (expanded). Two parts, both under test here:
--     PART A — the per-user-conditional aal2 BACKSTOP CLAUSE ANDed into the RLS of
--       the 14 tenant tables (reads + writes). Tested on a representative sample of
--       the claused shapes: account (direct-owner), account_trans (rd/wr_access
--       JOIN), asset (hybrid global-OR-owned), eod_price (asset-anchored).
--     PART B — the MB-1 GUARD: pfin.fn_user_settings_block_mfa_downgrade() BEFORE
--       UPDATE trigger on pfin.user_settings (Sec's exact A–F list + a no-op-change
--       control G).
--   (SECURITY §4.5 two-tenant posture, EXTENDED with the aal dimension; C6
--   EXPOSURE-gating — the backstop is the ONLY layer enforcing step-up on the direct
--   PostgREST API. Architect authors the migration; QA authors this battery; Sec
--   sign-off gates the merge.)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/025_aal2_step_up_backstop.sql
--   PART A backstop clause (per policy, COALESCE null-safe — the ratified form):
--     ( coalesce((select s.mfa_policy from pfin.user_settings s
--                  where s.users_id = auth.uid()), 'none') not in ('totp','passkey')
--       or (auth.jwt() ->> 'aal') = 'aal2' )
--     ANDed with (never replacing) each policy's pre-existing tenant predicate.
--     Gates the READER's own mfa_policy, never the row → NEVER a blanket aal2.
--   PART B guard: RAISES insufficient_privilege (42501) iff current_user =
--     'authenticated' AND old.mfa_policy in ('totp','passkey') AND new.mfa_policy
--     not in ('totp','passkey') AND coalesce(auth.jwt()->>'aal','') <> 'aal2'.
--
-- Prereqs exercised (on the 001->025 reset stack): 001 (pfin schema, auth.uid(),
--   fn_refresh_updated_at); 003 (account + fn_grant_creator_access DEFINER trigger
--   → auto account_users rd+wr on account insert); 006 (account_trans); 016 (asset);
--   019 (eod_price); 024 (user_settings + mfa_policy); 025 (the surface under test).
--   auth.jwt() reads request.jwt.claims (verified on the local PG 17 stack) — the
--   harness sets the 'aal' claim there via _rls.set_tenant_aal.
--
-- Reuses the 022/023/024 idiom: \ir shared verbs, \gset lowercase literals, role
--   restored to postgres between blocks (PR #121 _rls-USAGE root-cause). Fixtures
--   are built at role=postgres (superuser → bypasses RLS AND table ACL), so the
--   backstop is exercised ONLY on the authenticated read/write paths under test,
--   never during setup. The aal dimension rides _rls.set_tenant_aal / _rls.count_as
--   / _rls.set_service_role (added to the shared verbs for this + SELF-289 passkey).
--
-- ┌─ WHY EACH ASSERTION CATCHES A REAL VIOLATION (no vacuous green) ──────────────────────┐
-- │ PART A reads (R*): a totp user OWNS the rows counted (R2/R8/R12/R16 see them at aal2), │
-- │   so the aal1 → 0 assertions (R1/R7/R11/R15) are non-vacuous — they go RED if the      │
-- │   backstop clause were dropped from a USING (the rows would become aal1-visible). The  │
-- │   none/missing-row PASS rows (R3/R4/R9/R13) go RED if the clause became a BLANKET aal2 │
-- │   (they would wrongly be blocked). The cross-tenant-at-BOTH-aal rows (R5/R6/R10/R14/   │
-- │   R17) go RED if the aal conjunct had REPLACED (not ANDed with) the tenant predicate.  │
-- │ PART A writes (W*): W1/W5 assert the RLS-violation MESSAGE (not a bare 42501 — an ACL  │
-- │   denial is also 42501; authenticated HOLDS the write grants, so the only 42501 here   │
-- │   is the WITH CHECK). W3 proves the UPDATE-USING backstop by a 0-rows-mutated check.   │
-- │ PART B (MB-1): the blocked cases (A/E) assert BOTH errcode 42501 AND the EXACT guard   │
-- │   message (004 all-42501 false-green lesson) — a different 42501 cannot pass for it.   │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- ISOLATION ⟂ MFA (AC#6). Tenant isolation (users_id = auth.uid() / its JOIN form) is
--   enforced INDEPENDENT of MFA. R5/R6/R10/R14/R17 prove cross-tenant reads fail closed
--   at aal1 AND aal2; W5 proves a cross-tenant WRITE fails closed even when the backstop
--   is satisfied (aal2). MFA strength never weakens another tenant's fence.
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22/RT-26/RT-27); Decision-3 family
--   UNCHANGED — 025 adds no reference column, only ANDs a predicate + adds one SECURITY
--   INVOKER trigger fn (NOT a DEFINER allowlist entry; allowlist stays 3). This battery
--   is the pgTAP proof the backstop + guard catch real violations; it introduces no
--   catalogued instance.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants; NO PII / NO real account
--   numbers / NO prod data. All in a rolled-back txn. The case-F test-only grant to
--   service_role (mirrors 024 (4d)) is rolled back; 025/024 grant service_role nothing.
--
-- ⟦WIRE-VALIDATE⟧ authored against 025's DDL; authoritative run = the 001->025 reset
--   stack under CI (pg_prove directory-mode, db-tests.yml). Roles authenticated /
--   service_role name-checked in the blocks. plan(29).
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

select plan(29);

-- Resolve fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset

-- ---------------------------------------------------------------------
-- FIXTURE (PRIVILEGED postgres — bypasses RLS + ACL; the backstop is NOT exercised
-- here, only on the authenticated paths asserted below).
--   Read-matrix tenants:  A = 'totp' (owns data)      → the stepped-up user
--                         B = 'none' (owns data)      → not-blanket + intruder
--                         M = tenant_c, NO settings row → lazy-provision / coalesce case
--   MB-1 guard tenants c1..c7 (one per case; own only a user_settings row).
-- ---------------------------------------------------------------------
insert into auth.users (id) values
  (:'ta'), (:'tb'), (:'tc'),
  ('00000000-0000-0000-0000-0000000000c1'),
  ('00000000-0000-0000-0000-0000000000c2'),
  ('00000000-0000-0000-0000-0000000000c3'),
  ('00000000-0000-0000-0000-0000000000c4'),
  ('00000000-0000-0000-0000-0000000000c5'),
  ('00000000-0000-0000-0000-0000000000c6'),
  ('00000000-0000-0000-0000-0000000000c7');

-- user_settings: A totp, B none, M (tenant_c) NO ROW (missing-row case);
-- guard tenants: c1 totp, c2 totp, c3 none, c4 totp, c5 none, c6 totp, c7 totp.
--   (c5 seeds 'none' — 025 PART 3 tightened the CHECK to ('none','totp'), so 'passkey'
--    is no longer a storable value; the repurposed case E asserts that rejection.)
insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta', 'totp'), (:'tb', 'none'),
  ('00000000-0000-0000-0000-0000000000c1', 'totp'),
  ('00000000-0000-0000-0000-0000000000c2', 'totp'),
  ('00000000-0000-0000-0000-0000000000c3', 'none'),
  ('00000000-0000-0000-0000-0000000000c4', 'totp'),
  ('00000000-0000-0000-0000-0000000000c5', 'none'),
  ('00000000-0000-0000-0000-0000000000c6', 'totp'),
  ('00000000-0000-0000-0000-0000000000c7', 'totp');

-- accounts (insert auto-creates account_users rd+wr via fn_grant_creator_access):
--   A owns 2, B owns 1, M owns 1.
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'A-Checking', 'depository', 'personal', 'taxable')
  returning account_id as acct_a \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'A-Savings', 'depository', 'personal', 'taxable');
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'B-Checking', 'depository', 'personal', 'taxable')
  returning account_id as acct_b \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tc', 'M-Checking', 'depository', 'personal', 'taxable');

-- account_trans: one on A's account, one on B's account (quantity 0 → no security_id needed).
insert into pfin.account_trans (account_id, transaction_date, amount)
  values (:acct_a, '2026-01-15', 100.00);
insert into pfin.account_trans (account_id, transaction_date, amount)
  values (:acct_b, '2026-01-16', 50.00);

-- assets: one GLOBAL (users_id null, visible to all authenticated) + one A-owned.
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'GLOB', 'Global Equity')
  returning asset_id as asset_glob \gset
insert into pfin.asset (users_id, asset_type, pricing_source, name)
  values (:'ta', 'real_estate', 'manual_valuation', 'A House')
  returning asset_id as asset_a \gset

-- eod_price: one on the global asset, one on the A-owned asset.
insert into pfin.eod_price (asset_id, price_date, source, price)
  values (:asset_glob, '2026-01-15', 'market_feed', 10.00);
insert into pfin.eod_price (asset_id, price_date, source, price)
  values (:asset_a, '2026-01-15', 'manual_valuation', 500000.00);

-- =====================================================================
-- PART A.1 — BACKSTOP READ MATRIX: account (direct-owner). Full 6-case matrix.
--   Every probe is SCOPED to fixture rows (by users_id / account_id / asset_id) so
--   the assertion is deterministic regardless of any seed data (the local stack
--   carries 7 seed GLOBAL assets). No _rls.* is referenced inside the executed SQL
--   (authenticated has no _rls USAGE — PR #121); tenant literals come via :'ta' etc.
-- =====================================================================
select is(_rls.count_as(:'ta'::uuid, 'aal1', format('select count(*) from pfin.account where users_id = %L', :'ta')),
  0::bigint,
  '(R1) account/read: totp user + aal1 -> 0 of its OWN rows (backstop blocks the aal1 direct-API read); RED if the backstop were dropped from account_select USING');

select is(_rls.count_as(:'ta'::uuid, 'aal2', format('select count(*) from pfin.account where users_id = %L', :'ta')),
  2::bigint,
  '(R2) account/read: SAME totp user + aal2 -> its 2 own rows VISIBLE (proves R1 is non-vacuous: the user really owns rows); RED if the backstop over-blocked aal2');

select is(_rls.count_as(:'tb'::uuid, 'aal1', format('select count(*) from pfin.account where users_id = %L', :'tb')),
  1::bigint,
  '(R3) account/read NOT-BLANKET: none-policy user + aal1 -> own row VISIBLE; RED if the clause became a blanket aal2 (it would lock out a none user)');

select is(_rls.count_as(:'tc'::uuid, 'aal1', format('select count(*) from pfin.account where users_id = %L', :'tc')),
  1::bigint,
  '(R4) account/read COALESCE-not-lockout: MISSING user_settings row (lazy provisioning) + aal1 -> own row VISIBLE; RED if the subselect were not coalesced to ''none'' (NULL not in (...) would filter the row)');

select is(_rls.count_as(:'tb'::uuid, 'aal1', format('select count(*) from pfin.account where users_id = %L', :'ta')),
  0::bigint,
  '(R5) account/read CROSS-TENANT @aal1: intruder B sees 0 of A''s rows (isolation independent of MFA)');

select is(_rls.count_as(:'tb'::uuid, 'aal2', format('select count(*) from pfin.account where users_id = %L', :'ta')),
  0::bigint,
  '(R6) account/read CROSS-TENANT @aal2 TOO: B stepped-up to aal2 STILL sees 0 of A''s rows — the aal conjunct is ANDed with, never replaces, the tenant predicate; RED if aal had replaced tenant isolation');

-- =====================================================================
-- PART A.2 — BACKSTOP READ MATRIX: account_trans (rd/wr_access JOIN). Scoped by account_id.
-- =====================================================================
select is(_rls.count_as(:'ta'::uuid, 'aal1', format('select count(*) from pfin.account_trans where account_id = %s', :acct_a)),
  0::bigint,
  '(R7) account_trans/read (JOIN shape): totp user + aal1 -> 0 rows (backstop ANDed into the rd_access JOIN policy)');

select is(_rls.count_as(:'ta'::uuid, 'aal2', format('select count(*) from pfin.account_trans where account_id = %s', :acct_a)),
  1::bigint,
  '(R8) account_trans/read: SAME totp user + aal2 -> its 1 trans VISIBLE (R7 non-vacuous)');

select is(_rls.count_as(:'tb'::uuid, 'aal1', format('select count(*) from pfin.account_trans where account_id = %s', :acct_b)),
  1::bigint,
  '(R9) account_trans/read NOT-BLANKET: none user + aal1 -> its own trans VISIBLE');

select is(_rls.count_as(:'tb'::uuid, 'aal2', format('select count(*) from pfin.account_trans where account_id = %s', :acct_a)),
  0::bigint,
  '(R10) account_trans/read CROSS-TENANT @aal2: B at aal2 sees 0 of A''s-account trans (JOIN tenant fence holds under aal2)');

-- =====================================================================
-- PART A.3 — BACKSTOP READ MATRIX: asset (HYBRID global-OR-owned). Scoped to the
--   fixture's two assets (asset_glob = global, asset_a = A-owned) so the 7 seed
--   globals don't perturb the count.
--   The clause gates the READER: a totp reader at aal1 sees NOTHING — including the
--   global (users_id null) rows — so there is no partial-leak path via global rows.
-- =====================================================================
select is(_rls.count_as(:'ta'::uuid, 'aal1', format('select count(*) from pfin.asset where asset_id in (%s, %s)', :asset_glob, :asset_a)),
  0::bigint,
  '(R11) asset/read (hybrid): totp user + aal1 -> 0 rows INCLUDING the fixture global (users_id null) row — no partial-leak via global rows at aal1');

select is(_rls.count_as(:'ta'::uuid, 'aal2', format('select count(*) from pfin.asset where asset_id in (%s, %s)', :asset_glob, :asset_a)),
  2::bigint,
  '(R12) asset/read: SAME totp user + aal2 -> fixture global + own = 2 VISIBLE (R11 non-vacuous)');

select is(_rls.count_as(:'tb'::uuid, 'aal1', format('select count(*) from pfin.asset where asset_id in (%s, %s)', :asset_glob, :asset_a)),
  1::bigint,
  '(R13) asset/read NOT-BLANKET: none user + aal1 -> the fixture global row VISIBLE (1; the A-owned one is not B''s)');

select is(_rls.count_as(:'tb'::uuid, 'aal2', format('select count(*) from pfin.asset where users_id = %L', :'ta')),
  0::bigint,
  '(R14) asset/read CROSS-TENANT @aal2: B at aal2 sees 0 of A''s OWNED assets (own-row tenant fence holds under aal2; global rows excluded from this probe)');

-- =====================================================================
-- PART A.4 — BACKSTOP READ MATRIX: eod_price (asset-anchored). Scoped to fixture assets.
-- =====================================================================
select is(_rls.count_as(:'ta'::uuid, 'aal1', format('select count(*) from pfin.eod_price where asset_id in (%s, %s)', :asset_glob, :asset_a)),
  0::bigint,
  '(R15) eod_price/read (asset-anchored): totp user + aal1 -> 0 price rows');

select is(_rls.count_as(:'ta'::uuid, 'aal2', format('select count(*) from pfin.eod_price where asset_id in (%s, %s)', :asset_glob, :asset_a)),
  2::bigint,
  '(R16) eod_price/read: SAME totp user + aal2 -> prices for fixture global + own asset = 2 VISIBLE (R15 non-vacuous)');

select is(_rls.count_as(:'tb'::uuid, 'aal2', format('select count(*) from pfin.eod_price where asset_id = %s', :asset_a)),
  0::bigint,
  '(R17) eod_price/read CROSS-TENANT @aal2: B at aal2 sees 0 prices on A''s OWNED asset (asset-ownership fence holds under aal2)');

-- =====================================================================
-- PART A.5 — BACKSTOP WRITE MATRIX (account, the direct authenticated write path).
-- =====================================================================
-- (W1) totp user + aal1 INSERT -> blocked by INSERT WITH CHECK (backstop false).
--   MESSAGE-precise: authenticated HOLDS the insert grant, so the only 42501 is the
--   RLS WITH CHECK — matched on the RLS message, not a bare code (004 lesson).
select _rls.set_tenant_aal(_rls.tenant_a(), 'aal1');
select throws_like(
  $$ insert into pfin.account (name, account_type, scope, tax_treatment) values ('W1-blocked', 'depository', 'personal', 'taxable') $$,
  '%violates row-level security policy%',
  '(W1) write BLOCKED: totp user + aal1 INSERT -> RLS WITH CHECK rejects (backstop false); RED if the backstop were dropped from account_insert WITH CHECK'
);
select set_config('role', 'postgres', true);

-- (W2) SAME totp user + aal2 INSERT -> COMMITS (users_id defaults auth.uid() = A).
select _rls.set_tenant_aal(_rls.tenant_a(), 'aal2');
select lives_ok(
  $$ insert into pfin.account (name, account_type, scope, tax_treatment) values ('W2-ok', 'depository', 'personal', 'taxable') $$,
  '(W2) write ALLOWED: SAME totp user + aal2 INSERT COMMITS (backstop satisfied) — proves W1 blocks on aal, not on the user being write-incapable'
);
select set_config('role', 'postgres', true);

-- (W3) totp user + aal1 UPDATE of own rows -> UPDATE USING backstop false hides all
--   A rows -> 0 rows mutated (no error). Assert no row took the tampered name.
select _rls.set_tenant_aal(_rls.tenant_a(), 'aal1');
update pfin.account set name = 'HACKED-aal1' where users_id = auth.uid();  -- 0 rows (USING backstop false)
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.account where name = 'HACKED-aal1')::bigint,
  0::bigint,
  '(W3) update BLOCKED: totp user + aal1 UPDATE of own rows matched 0 rows (UPDATE USING backstop false) -> nothing mutated; RED if the backstop were dropped from account_update USING'
);

-- (W4) none user + aal1 INSERT -> COMMITS (not-blanket on the write side).
select _rls.set_tenant_aal(_rls.tenant_b(), 'aal1');
select lives_ok(
  $$ insert into pfin.account (name, account_type, scope, tax_treatment) values ('W4-none-ok', 'depository', 'personal', 'taxable') $$,
  '(W4) write NOT-BLANKET: none-policy user + aal1 INSERT COMMITS (backstop true for none) — aal1 is not a blanket write-block'
);
select set_config('role', 'postgres', true);

-- (W5) ISOLATION ⟂ MFA on write: A at aal2 (backstop satisfied) forging users_id = B
--   is STILL RLS-rejected -> the aal conjunct is ANDed with, never replaces, tenant.
select _rls.set_tenant_aal(:'ta'::uuid, 'aal2');
select throws_like(
  format($$ insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values (%L, 'W5-forge', 'depository', 'personal', 'taxable') $$, :'tb'),
  '%violates row-level security policy%',
  '(W5) isolation ⟂ MFA on write: A at aal2 inserting users_id = B is RLS-rejected even though the backstop is satisfied — the tenant WITH CHECK still fences'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- PART B — MB-1 DOWNGRADE-GUARD (Sec's exact A–F + a no-op-change control G).
--   Guard message asserted EXACTLY on the blocked cases (A/E) alongside 42501, so a
--   different 42501 (e.g. ACL) cannot pass for the MB-1 raise (004 false-green lesson).
-- =====================================================================
-- (A) authenticated aal1 totp->none -> BLOCKED (42501, MB-1).
select _rls.set_tenant_aal('00000000-0000-0000-0000-0000000000c1'::uuid, 'aal1');
select throws_ok(
  $$ update pfin.user_settings set mfa_policy = 'none' where users_id = auth.uid() $$,
  '42501',
  'mfa_policy downgrade out of a step-up factor requires an aal2 session (MB-1 backstop-integrity guard)',
  '(MB-1 A) authenticated aal1 totp->none is BLOCKED (42501 + exact MB-1 message) — a stolen-password aal1 attacker cannot disable the backstop control variable'
);
select set_config('role', 'postgres', true);

-- (B) authenticated aal2 totp->none -> OK.
select _rls.set_tenant_aal('00000000-0000-0000-0000-0000000000c2'::uuid, 'aal2');
select lives_ok(
  $$ update pfin.user_settings set mfa_policy = 'none' where users_id = auth.uid() $$,
  '(MB-1 B) authenticated aal2 totp->none SUCCEEDS — the legitimate stepped-up self-service disable passes'
);
select set_config('role', 'postgres', true);

-- (C) authenticated aal1 none->totp -> OK (enrollment is free — old not in the gated set).
select _rls.set_tenant_aal('00000000-0000-0000-0000-0000000000c3'::uuid, 'aal1');
select lives_ok(
  $$ update pfin.user_settings set mfa_policy = 'totp' where users_id = auth.uid() $$,
  '(MB-1 C) authenticated aal1 none->totp SUCCEEDS — enrollment is free (a user must turn MFA on before they can ever reach aal2)'
);
select set_config('role', 'postgres', true);

-- (D) authenticated aal1 totp->passkey -> REJECTED (23514, CHECK) after 025 PART 3.
--   The lateral flip is no longer OK: the MB-1 guard sees new='passkey' IN the
--   {totp,passkey} aal2-capable set → it does NOT raise (not a weakening) → the
--   TIGHTENED CHECK ('none','totp') then rejects 'passkey' with 23514, at the SCHEMA
--   layer BELOW the guard. Key the assertion on 23514 (NOT the guard's 42501).
select _rls.set_tenant_aal('00000000-0000-0000-0000-0000000000c4'::uuid, 'aal1');
select throws_ok(
  $$ update pfin.user_settings set mfa_policy = 'passkey' where users_id = auth.uid() $$,
  '23514', null,
  '(MB-1 D) authenticated aal1 totp->passkey is REJECTED (check_violation 23514) — 025 PART 3 tightened the domain to (none,totp); the guard falls through (passkey is not a weakening) and the CHECK catches it BELOW the guard'
);
select set_config('role', 'postgres', true);

-- (E) DOMAIN-REJECTION guard (repurposed — the old passkey->none anti-chaining case is
--   now UNREACHABLE: no row can ever hold 'passkey' post-025 PART 3). Positively assert
--   that writing mfa_policy='passkey' on the normal authenticated path fails 23514.
--   ANTI-CHAINING is now FORECLOSED AT THE SCHEMA LAYER by the tightened CHECK, so the
--   guard's {totp,passkey} set-membership predicate is forward-compat-only in V1 (it
--   re-arms with ZERO change when Auth-6/SELF-289 re-adds 'passkey' additively).
select _rls.set_tenant_aal('00000000-0000-0000-0000-0000000000c5'::uuid, 'aal1');
select throws_ok(
  $$ update pfin.user_settings set mfa_policy = 'passkey' where users_id = auth.uid() $$,
  '23514', null,
  '(MB-1 E) domain rejection: an authenticated UPDATE to mfa_policy=''passkey'' is REJECTED (check_violation 23514) — 025 PART 3 tighten holds; ''passkey'' is not a storable V1 value. RED if the domain were widened back before Auth-6'
);
select set_config('role', 'postgres', true);

-- (F) service_role aal1 totp->none -> OK (Slice-2 recovery channel is deliberately UNGATED).
--   The guard keys off current_user='authenticated'; service_role is not gated. Open the ACL
--   layer with a TEST-ONLY grant (024 (4d) idiom; rolled back — 024/025 grant service_role
--   nothing) so the MB-1 trigger is the SOLE remaining gate, then assert the row downgraded.
grant select, update on pfin.user_settings to service_role;  -- TEST-ONLY (rolled back; UPDATE...WHERE needs SELECT on the qual column)
select _rls.set_service_role();
update pfin.user_settings set mfa_policy = 'none' where users_id = '00000000-0000-0000-0000-0000000000c6';
select set_config('role', 'postgres', true);
select is(
  (select mfa_policy from pfin.user_settings where users_id = '00000000-0000-0000-0000-0000000000c6'::uuid),
  'none',
  '(MB-1 F) service_role totp->none SUCCEEDS (row is now ''none'') — the guard keys off current_user=authenticated, so the server-side recovery channel is deliberately ungated; RED if the guard also fired for service_role'
);

-- (G) authenticated aal1 totp->totp (no-op / non-downgrade change) -> OK. Proves the guard
--   fires only on LEAVING the aal2-capable set, not on any update touching mfa_policy.
select _rls.set_tenant_aal('00000000-0000-0000-0000-0000000000c7'::uuid, 'aal1');
select lives_ok(
  $$ update pfin.user_settings set mfa_policy = 'totp' where users_id = auth.uid() $$,
  '(MB-1 G) authenticated aal1 totp->totp SUCCEEDS — a non-downgrade update (new still in the gated set) is not blocked; RED if the guard over-fired on any mfa_policy update'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;

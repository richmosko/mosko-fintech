-- =====================================================================
-- Per-Wave battery — pfin.fn_land_linked_accounts INVOKER write-composition RPC
--   (SELF-199 / 042 — §2.4.1.d per-account attribute capture; ADR-037 provider-agnostic
--    linked_source substrate; C6 EXPOSURE-GATING per ADR-023 / SECURITY §4.5;
--    V1-SHIP-BLOCK; sec-joint-review-mandatory — money-adjacent account-creation RPC +
--    Decision-3 #6-fence exercise)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/042_fn_land_linked_accounts.sql
--   - pfin.fn_land_linked_accounts(p_linked_source_id bigint, p_accounts jsonb)
--       RETURNS TABLE(account_id bigint, provider_account_id text) —
--       SECURITY INVOKER, set search_path = '', VOLATILE. Atomic body (one txn): for
--       each element of the p_accounts jsonb ARRAY, INSERT pfin.account
--         (users_id DEFAULT auth.uid() — NOT a param; name/account_type/scope/
--          tax_treatment from the object; linked_source_id = p_linked_source_id;
--          provider_account_id from the object)
--         ON CONFLICT (linked_source_id, provider_account_id)
--           WHERE linked_source_id IS NOT NULL
--           DO UPDATE SET provider_account_id = excluded.provider_account_id
--             (a NO-OP self-assignment; 058 re-authored this from `SET is_active = true`
--              per ADR-042 D1b — a re-land must not reopen a closed account)
--         RETURNING (account_id, provider_account_id) appended to the result set.
--       Fail-closed input guards: p_accounts must be a JSON array (else raise 22023);
--       each element must carry a non-null provider_account_id (else raise 22023).
--   - REVOKE EXECUTE FROM PUBLIC (denies anon) + GRANT EXECUTE TO authenticated only.
-- Prereqs exercised (all on main):
--   003 — pfin.account (users_id DEFAULT auth.uid() + account_insert WITH CHECK
--         users_id=auth.uid()) + the account_type / tax_treatment CHECK domains +
--         name/scope NOT NULL + is_active DEFAULT true + fn_grant_creator_access
--         (AFTER INSERT DEFINER creator-grant trigger — fires ONE account_users(rd,wr)
--         row per REAL account INSERT; the referent (4)/(9) rest on).
--   015 STEP 7/8 — account.linked_source_id + account.provider_account_id columns +
--         fn_account_matched_linked_source (SECURITY INVOKER; BEFORE INSERT OR UPDATE
--         WHEN new.linked_source_id IS NOT NULL; NULL-safe fail-closed NOT EXISTS ->
--         raise 'cross-tenant linked_source rejected%'; Decision-3 CANONICAL instance #6).
--   pfin.linked_source (015) — FK target + tenant anchor; provider='plaid' (SELF-199
--         primary; ADR-037), credential_secret_id NULL (credential-less -> NO Vault
--         secret, nothing real enters CI; SD-03 posture).
--   021 — account_linked_source_provider_uidx partial UNIQUE (linked_source_id,
--         provider_account_id) WHERE linked_source_id IS NOT NULL = the ON CONFLICT
--         arbiter the RPC reuses (idempotent re-land).
--   024/025 — pfin.user_settings.mfa_policy + the aal2 step-up backstop clause ANDed
--         into pfin.account's authenticated policies (INSERT WITH CHECK). This RPC is
--         INVOKER -> it INHERITS that clause (Block 5).
-- Reuses the SELF-187..231 / 013 / 021 idiom: \ir verbs, ALL-LOWERCASE \gset literals
--   (005 case-fold lesson), SQLSTATE-precise throws_ok + message-precise throws_like (004
--   all-42501 false-green lesson), role restored to postgres between blocks (PR #121
--   _rls-USAGE root-cause). Every landing runs under authenticated (INVOKER, via /rpc) so
--   the fences are proven to COMPOSE with RLS, not fire as raw constraints under postgres.
--
-- ┌─ WHAT THIS RPC BATTERY PROVES BEYOND THE 013 SINGLE-ACCOUNT + 021 DEDUP BATTERIES ──────┐
-- │ 013 proved single-row atomic write-composition; 021 proved the partial-index dedup +    │
-- │ the #6 fence on a bare DO-NOTHING mapping write. 042 is the MULTI-ROW landing RPC whose  │
-- │ ON CONFLICT is DO UPDATE (not DO NOTHING), so this battery proves the properties 042     │
-- │ introduces:                                                                             │
-- │  • MULTI-ROW: ONE call lands N pfin.account rows (one per selected AccountRef), each     │
-- │    caller-bound (users_id DEFAULT auth.uid() — NOT a param), is_active, attrs-as-passed. │
-- │  • RE-LAND = NO-OP, NEVER a 2nd row: the DO UPDATE arbiter is a self-assignment on the   │
-- │    canonical (source, provider_account) row — it does NOT reopen a closed account        │
-- │    (ADR-042 D1b; 058 re-authored it) — and — the 042-                                    │
-- │    specific contract — RETURNS its id (DO UPDATE, so RETURNING yields existing rows too, │
-- │    unlike 021's DO NOTHING), and does NOT overwrite the user's stored attributes.        │
-- │  • ATOMICITY / ALL-OR-NOTHING: a batch with one invalid element lands NONE (the forcing- │
-- │    function the RPC exists for — client-side compensation is structurally blocked;       │
-- │    authenticated has no account DELETE, 003).                                            │
-- │  • the 015 #6 fence + the inherited 025 aal2 clause still fire THROUGH the RPC.          │
-- │  • anon cannot execute (EXECUTE revoked from PUBLIC, granted to authenticated only).     │
-- └─────────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (1)  -> non-vacuous positive + MULTI-ROW + RETURNING shape: ONE call lands the 2 selected
--           accounts and RETURNS one row per landed account. RED if the RPC dropped a write or
--           RETURNING mis-counted.
--   (2)  -> caller-bound ownership: exactly 2 A-owned rows under a_src1 (users_id DEFAULT
--           auth.uid() = A — NOT a forgeable param, so a caller cannot land for another tenant).
--   (3)  -> attrs-as-passed + is_active: the ext-a-1 row carries the passed name/account_type/
--           scope/tax_treatment AND is_active=true. RED if the RPC mis-mapped an attribute.
--   (4)  -> creator-grant PER ROW: fn_grant_creator_access minted exactly one account_users(rd,wr)
--           row for EACH of the 2 landed accounts (the AFTER INSERT DEFINER trigger fired per row
--           in-txn). RED if the grant were not seeded (landed accounts would be read-invisible).
--   (5)  -> RE-LAND RETURNING (042-specific, DO UPDATE not DO NOTHING): a re-land of the SAME
--           (a_src1, ext-a-1) RETURNS exactly 1 row (the existing account's id) — the caller gets
--           an id for an already-landed account too. RED if the arbiter were DO NOTHING (returns 0).
--   (6)  -> LOAD-BEARING no-2nd-row: after the re-land, (a_src1, ext-a-1) still resolves to exactly
--           1 pfin.account row. RED if the 021 arbiter were dropped/mis-keyed -> duplicate landing.
--   (7)  -> LOAD-BEARING no-silent-reopen (INVERTED at ADR-042): the re-land did NOT clear
--           closed_at. RED if the conflict clause ever regained a closure-state write.
--   (8)  -> no-clobber semantics: the re-land did NOT overwrite the stored attributes (name is
--           STILL the original 'A Brokerage', not the re-land payload). RED if DO UPDATE also SET
--           attrs -> a re-land would silently clobber user edits (attr edits are a separate path).
--   (9)  -> creator-grant NO-REFIRE: the re-land (DO UPDATE, no INSERT) did NOT re-fire the AFTER
--           INSERT trigger -> account_users for the account is UNCHANGED at 1 (no grant inflation).
--   (10) -> LOAD-BEARING cross-tenant THROUGH the RPC: A calls the RPC with B's p_linked_source_id
--           -> fn_account_matched_linked_source (015 #6) RAISES 'cross-tenant linked_source rejected%'
--           (NOT a bare 42501, NOT a 23503 FK, NOT a silent pass). The (1) own-source ACCEPT is the
--           non-vacuous control proving the raise is MISMATCH-driven — inversion-proved.
--   (11) -> LOAD-BEARING atomicity of the fence path: the (10) raise left NO orphan account under
--           b_src1 (all-or-nothing; the account INSERT rolled back with the failing call).
--   (12) -> malformed input: a non-array p_accounts fails closed at 22023 (the RPC's array guard) —
--           no write attempted. RED if the guard were dropped (a scalar/object would silently no-op).
--   (13) -> malformed input: an element missing provider_account_id fails closed at 22023 (the dedup-
--           key guard). RED if absent -> a NULL key would be insert-always (silent duplicate on re-land).
--   (14) -> malformed input: an invalid account_type fails closed at 23514 (the 003 CHECK) — the whole
--           txn aborts (no partial landing). RED if the enum CHECK were absent on the RPC write path.
--   (15) -> malformed input: an invalid tax_treatment fails closed at 23514 (the 003 CHECK).
--   (16) -> malformed input: a missing NOT NULL key (name) resolves to NULL via ->> and fails closed
--           at 23502 (the 003 NOT NULL). RED if the RPC coalesced a NULL to a default (silent landing).
--   (17) -> empty-array is VALID (not malformed): p_accounts=[] is a clean no-op (no error, no rows).
--           Non-vacuous control that the fail-closed guards (12)-(16) are malformed-driven.
--   (18) -> LOAD-BEARING ATOMICITY (all-or-nothing): a batch [valid, invalid] lands NEITHER row —
--           the invalid element aborts the whole call. RED if the RPC committed per-element -> a
--           partial account set on the immutable-adjacent entity (client compensation is blocked).
--   (19) -> LOAD-BEARING inherited 025 aal2 posture (FENCE-ORDER FINDING): a totp-policy caller at aal1
--           landing via the RPC FAILS CLOSED — but for a PROVIDER-LINKED landing the fence that fires
--           FIRST is the 015 #6 fence, NOT the account WITH CHECK: pfin.linked_source's SELECT policy
--           ALSO carries the 025 aal2 clause, so the caller's OWN source is RLS-invisible at aal1 ->
--           fn_account_matched_linked_source raises 'cross-tenant linked_source rejected%' before the
--           account WITH CHECK is reached (the account-level clause is defense-in-depth behind it; the
--           025 battery W1 proves it directly on a bare insert). RED if a sub-aal2 totp caller could
--           land via the RPC. ⚠ Sec/Backend (RESOLVED at the app layer): Backend's pre-RPC requireStepUp
--           guard on the persist action intercepts a legit aal1 owner WITH A VERIFIED GoTrue FACTOR →
--           303 /mfa/step-up (proven end-to-end in api/tests/attributesPersistTwoTenant.dbit case 4).
--           The guard keys off GoTrue AAL while THIS clause keys off the pfin.user_settings.mfa_policy
--           COLUMN — a user with mfa_policy='totp' but NO verified factor would hit this #6 fence with
--           the misleading 403, BUT the app's own MFA flows cannot create that state (disable +
--           recovery both downgrade mfa_policy FIRST — Backend-verified), so it is out-of-band-only +
--           recovery-covered, and this DB fence is its fail-closed backstop (dbit case 3, defense-in-
--           depth). (20) is the non-vacuous aal2 control (source visible + WITH CHECK passes).
--   (20) -> non-vacuous aal control: the SAME totp caller at aal2 lands successfully -> proves (19)
--           is aal-driven, not a blanket block of that tenant.
--   (21) -> anon holds NO EXECUTE on the RPC (revoked from PUBLIC, granted to authenticated only) —
--           the write RPC is not internet-facing-anon-callable (ADR-023 exposure fence).
--   (22) -> anon call fails closed at 42501 (no schema-USAGE / no EXECUTE) — behavior-level backstop.
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22 / RT-26 / RT-27; 042 is authenticated-tier
--   INVOKER write-composition — no infra-credential (RT-22), no SUPABASE_SERVICE_ROLE_KEY code-layer
--   (RT-26 — the landing path uses NO service_role), no app->worker admission surface (RT-27); per the
--   042 header §10 3-axis, Path B). Decision-3 family UNCHANGED (042 adds NO FK-shaped column; it
--   PASSES p_linked_source_id THROUGH to the 015 canonical instance #6 fence — EXERCISED here, not a
--   new obligation; provider_account_id is TEXT provider-native id, NOT a pfin FK). THIS battery is the
--   pgTAP proof that (a) the landing composes correctly AND (b) the #6 fence + the 025 aal2 clause catch
--   REAL violations through the RPC (per the 042 header QA TEST-PAIRING; Sec joint-review-mandatory).
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b()/_c(); NO PII /
--   NO real account numbers / NO real credentials (SD-03) / NO prod data. linked_source rows carry
--   provider='plaid' with credential_secret_id NULL (credential-less -> no Vault secret created).
--   linked_source + user_settings rows are seeded PRIVILEGED (role=postgres; the credential store has no
--   authenticated write path, Decision 1 — users_id set explicitly since auth.uid() is NULL under
--   postgres); pfin.account rows are landed via the APP PATH under authenticated (users_id DEFAULT
--   auth.uid()) exactly as the SELF-199 persist action runs. All in a rolled-back txn.
--   Tenant A carries NO user_settings row (coalesce->'none' -> aal-ungated: A's normal landing works at
--   aal1); a dedicated tenant C carries mfa_policy='totp' so the inherited aal2 clause has a real referent.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so NO `_rls.*`
--   runs under authenticated. Tenant UUIDs + source ids are resolved to psql LITERALS via \gset at
--   role=postgres; every _rls.set_tenant[_aal] is called at role=postgres and each block restores
--   role=postgres before the next. \gset var names are ALL-LOWERCASE. psql :var is interpolated only in
--   plain SQL context; inside a throws_*/lives_ok string-literal the source id is injected via format(%s)
--   (a :var inside a $tag$…$tag$ dollar-quote is NOT interpolated — 021 idiom); the jsonb payloads carry
--   no :var so they are safely dollar-quoted ($j$…$j$).
--
-- ⟦WIRE-VALIDATE⟧ authored against 042's firmed contract; the authoritative run is against the
--   001->042 reset stack. Roles authenticated / anon name-checked in the blocks. RED-until-042-applied is
--   expected on any pre-042 stack (the function would not exist).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(23);  -- 22 numbered assertions + the (18a) atomicity-setup throws_ok

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session). Three tenants in auth.users; A owns ONE source,
-- B owns ONE source, C owns ONE source. provider='plaid' + credential_secret_id NULL
-- (credential-less -> no Vault secret); external_connection_id distinct per row. C carries a
-- user_settings mfa_policy='totp' row for the inherited-aal2 block; A/B carry none (coalesce
-- -> 'none' -> aal-ungated normal landing). users_id set explicitly (auth.uid() is NULL under
-- postgres).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc');

insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name)
  values (:'ta', 'plaid', 'conn-a-1', 'Synthetic Brokerage A')
  returning source_id as a_src1 \gset
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name)
  values (:'tb', 'plaid', 'conn-b-1', 'Synthetic Brokerage B')
  returning source_id as b_src1 \gset
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name)
  values (:'tc', 'plaid', 'conn-c-1', 'Synthetic Brokerage C')
  returning source_id as c_src1 \gset

-- C declares MFA policy 'totp' -> the 025 backstop requires an aal2 session for C's writes.
insert into pfin.user_settings (users_id, mfa_policy) values (:'tc', 'totp');

-- =====================================================================
-- BLOCK 1 (authenticated A; plain set_tenant = aal1, mfa_policy coalesces to 'none' -> ungated)
--   Owner lands 2 selected accounts in ONE call: MULTI-ROW + RETURNING shape + caller-bound
--   ownership + attrs-as-passed + is_active + creator-grant PER ROW.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (1) MULTI-ROW + RETURNING: ONE call lands the 2 selected accounts and RETURNS one row each.
--     Selecting from the set-returning RPC executes the landing (all writes commit in-txn).
select is(
  (select count(*) from pfin.fn_land_linked_accounts(
     :a_src1,
     $j$[
       {"provider_account_id":"ext-a-1","name":"A Brokerage","account_type":"investment","scope":"household","tax_treatment":"taxable"},
       {"provider_account_id":"ext-a-2","name":"A Roth","account_type":"retirement","scope":"household","tax_treatment":"tax_free"}
     ]$j$::jsonb))::bigint,
  2::bigint,
  '(1) MULTI-ROW landing: ONE fn_land_linked_accounts call lands the 2 selected provider accounts and RETURNS one row per landed account (non-vacuous positive; RED if a write were dropped or RETURNING mis-counted)'
);

-- (2) caller-bound ownership: exactly 2 A-owned rows under a_src1 (users_id DEFAULT auth.uid()=A;
--     NOT a forgeable param -> a caller cannot land for another tenant).
select is(
  (select count(*) from pfin.account where linked_source_id = :a_src1 and users_id = :'ta')::bigint,
  2::bigint,
  '(2) caller-bound ownership: exactly 2 A-owned accounts under a_src1 (users_id DEFAULT auth.uid()=A — NOT a parameter, so the caller cannot land an account for another tenant)'
);

-- (3) attrs-as-passed + is_active: the ext-a-1 row carries every passed attribute AND is_active=true.
select is(
  (select count(*) from pfin.account
     where linked_source_id = :a_src1 and provider_account_id = 'ext-a-1'
       and name = 'A Brokerage' and account_type = 'investment'
       and scope = 'household' and tax_treatment = 'taxable' and is_active)::bigint,
  1::bigint,
  '(3) attrs-as-passed: the ext-a-1 landed row carries the passed name/account_type/scope/tax_treatment AND is_active=true (RED if the RPC mis-mapped a per-account attribute)'
);

-- capture the canonical ext-a-1 account_id (authenticated A; RLS-visible) for (5)-(9).
select account_id as acct_a1 from pfin.account
  where linked_source_id = :a_src1 and provider_account_id = 'ext-a-1' \gset

-- (4) creator-grant PER ROW: fn_grant_creator_access seeded exactly one account_users(rd,wr) row
--     for EACH landed account (the AFTER INSERT DEFINER trigger fired per row in the same txn).
select is(
  (select count(*) from pfin.account_users au
     join pfin.account a on a.account_id = au.account_id
     where a.linked_source_id = :a_src1 and au.users_id = :'ta'
       and au.rd_access and au.wr_access)::bigint,
  2::bigint,
  '(4) creator-grant PER ROW: fn_grant_creator_access minted exactly one account_users(rd,wr) row for EACH of the 2 landed accounts (the AFTER INSERT DEFINER trigger fired per landed row in-txn; RED if a landed account were left read-invisible)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 2 (authenticated A) — RE-LAND semantics: a re-land of a CLOSED account, DO UPDATE
--   RETURNING (042-specific), no 2nd row, no reopen, no attribute overwrite, creator-grant
--   no-refire. Setup: close ext-a-1 through the gate (owner UPDATE; A ungated at aal1), then
--   re-land the SAME (a_src1, ext-a-1) with DIFFERENT attrs to prove no-clobber semantics.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- CLOSE the canonical ext-a-1 row — the re-land target. Written as closed_at, never is_active:
-- the 058 sync trigger is ONE-DIRECTIONAL (closed_at -> is_active), so an is_active-only write
-- leaves closed_at NULL and the account_closure_biconditional CHECK rejects it. The account
-- carries no value, so it passes the close gate's zero-value legs.
-- reason_code is MANDATORY on the into-closed transition and has NO other carrier — 058's audit
-- writer cannot invent one and must not. Transaction-local, mirroring the 058 battery.
select set_config('pfin.reason_code', 'no_longer_used', true);
update pfin.account set closed_at = '2026-06-30'::timestamptz where account_id = :acct_a1;

-- (5) RE-LAND RETURNING (DO UPDATE, not DO NOTHING): re-landing the SAME (a_src1, ext-a-1) RETURNS
--     exactly 1 row (the existing account's id). The 042-specific contract choice — the caller gets
--     an id for an already-landed account too (021's DO NOTHING would return 0). The DO UPDATE is
--     now a NO-OP SELF-ASSIGNMENT (058 re-authored it from `set is_active = true`), so what is
--     being asserted here is the RETURNING contract alone, not any state change.
select is(
  (select count(*) from pfin.fn_land_linked_accounts(
     :a_src1,
     $j$[{"provider_account_id":"ext-a-1","name":"RELAND MUST NOT OVERWRITE","account_type":"depository","scope":"personal","tax_treatment":"tax_deferred"}]$j$::jsonb))::bigint,
  1::bigint,
  '(5) re-land RETURNING (DO UPDATE not DO NOTHING): a re-land of the SAME (a_src1, ext-a-1) RETURNS exactly 1 row (the existing account id) — the caller receives an id for an already-landed account too (021 DO NOTHING would return 0)'
);

-- (6) LOAD-BEARING no-2nd-row: (a_src1, ext-a-1) still resolves to exactly 1 pfin.account row.
select is(
  (select count(*) from pfin.account where linked_source_id = :a_src1 and provider_account_id = 'ext-a-1')::bigint,
  1::bigint,
  '(6) LOAD-BEARING no-2nd-row: after the re-land, (a_src1, ext-a-1) still resolves to exactly 1 pfin.account row (the 021 partial-UNIQUE arbiter prevented a duplicate landing)'
);

-- (7) INVERTED at ADR-042. This assertion previously proved the re-land REACTIVATED a
--     soft-deleted account (`DO UPDATE SET is_active = true`). ADR-042 Decision 1b removed that
--     behaviour deliberately: *ignored* and *closed* are different facts, reopening is a
--     bookkeeping event belonging to the account's own close control, and a connect flow must not
--     perform one as a side effect. 058 re-authored the conflict clause to a no-op
--     self-assignment. The assertion is INVERTED rather than deleted, because "a re-land does not
--     silently reopen a closed account" is the property that now carries the load — and deleting
--     it would leave the reopen path unfenced at exactly the site that used to perform it.
select isnt(
  (select closed_at from pfin.account where account_id = :acct_a1),
  null,
  '(7) LOAD-BEARING no-silent-reopen: the re-land did NOT clear closed_at — a connect-time re-land never reopens a closed account (ADR-042 D1b; 058 made the conflict clause a no-op self-assignment). Reopening is done from the account close control, which produces an account_event row'
);

-- (8) no-clobber: the re-land did NOT overwrite stored attributes — name is STILL the original.
select is(
  (select name from pfin.account where account_id = :acct_a1),
  'A Brokerage',
  '(8) no-clobber semantics: the re-land did NOT overwrite the stored attributes (name is STILL ''A Brokerage'', not the re-land payload) — attribute edits are a separate update path, RED if DO UPDATE also SET attrs (silent clobber of user edits)'
);

-- (9) creator-grant NO-REFIRE: the re-land (DO UPDATE, no INSERT) did not re-fire the AFTER INSERT
--     trigger -> account_users for the account is UNCHANGED at 1.
select is(
  (select count(*) from pfin.account_users where account_id = :acct_a1)::bigint,
  1::bigint,
  '(9) creator-grant NO-REFIRE: the re-land is a DO UPDATE (no row inserted) -> the AFTER INSERT creator-grant trigger did not fire -> account_users for the account is UNCHANGED at 1 (no grant-row inflation)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 3 (authenticated A) — THE #6 FENCE THROUGH THE RPC (inversion-proved). A calls the RPC
--   with B's p_linked_source_id -> fn_account_matched_linked_source RAISES; and no orphan lands.
--   The (1) own-source ACCEPT is the non-vacuous control -> the raise is mismatch-driven.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (10) LOAD-BEARING cross-tenant landing fails closed: A passes B's source_id -> the BEFORE INSERT
--      #6 fence reads linked_source(source_id=B's, users_id=A) -> NOT EXISTS (B's row is users_id=B
--      AND RLS-invisible to A) -> RAISE. Assert the raise MESSAGE (not a bare 42501/23503/silent pass).
select throws_like(
  format($$ select pfin.fn_land_linked_accounts(%s,
             $j$[{"provider_account_id":"ext-b-steal","name":"A steals B source","account_type":"investment","scope":"household","tax_treatment":"taxable"}]$j$::jsonb) $$, :b_src1),
  'cross-tenant linked_source rejected%',
  '(10) LOAD-BEARING cross-tenant THROUGH the RPC: A calls fn_land_linked_accounts with B''s p_linked_source_id -> fn_account_matched_linked_source (015 Decision-3 #6) RAISES (the RPC does NOT bypass the matched-tenant fence; inversion-proved against the (1) own-source ACCEPT)'
);

-- (11) atomicity of the fence path: the (10) raise left NO orphan account under b_src1.
select is(
  (select count(*) from pfin.account where linked_source_id = :b_src1)::bigint,
  0::bigint,
  '(11) atomicity (fence path): the (10) cross-tenant raise left NO orphan account under b_src1 (all-or-nothing — the account INSERT rolled back with the failing call)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 4 (authenticated A) — MALFORMED INPUT fails closed + empty-array positive control +
--   LOAD-BEARING all-or-nothing atomicity (a batch with one invalid element lands NONE).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (12) non-array p_accounts -> the RPC's array guard raises 22023 (invalid_parameter_value).
select throws_ok(
  format($$ select pfin.fn_land_linked_accounts(%s, $j${"provider_account_id":"x","name":"n","account_type":"investment","scope":"household","tax_treatment":"taxable"}$j$::jsonb) $$, :a_src1),
  '22023', null,
  '(12) malformed: a non-array p_accounts (a bare object) fails closed at 22023 (the RPC array guard) — no write attempted; RED if the guard were dropped (a scalar/object would silently no-op)'
);

-- (13) an element missing provider_account_id -> the dedup-key guard raises 22023.
select throws_ok(
  format($$ select pfin.fn_land_linked_accounts(%s, $j$[{"name":"no pai","account_type":"investment","scope":"household","tax_treatment":"taxable"}]$j$::jsonb) $$, :a_src1),
  '22023', null,
  '(13) malformed: an element missing provider_account_id fails closed at 22023 (the dedup-key guard) — RED if absent, a NULL key is insert-always in the 021 partial index (silent duplicate on re-land)'
);

-- (14) invalid account_type -> the 003 CHECK aborts the whole txn at 23514 (check_violation).
select throws_ok(
  format($$ select pfin.fn_land_linked_accounts(%s, $j$[{"provider_account_id":"ext-a-bad-t","name":"bad type","account_type":"NOT_A_TYPE","scope":"household","tax_treatment":"taxable"}]$j$::jsonb) $$, :a_src1),
  '23514', null,
  '(14) malformed: an invalid account_type fails closed at 23514 (the 003 CHECK) — the whole txn aborts (no partial landing) through the RPC write path'
);

-- (15) invalid tax_treatment -> the 003 CHECK aborts at 23514.
select throws_ok(
  format($$ select pfin.fn_land_linked_accounts(%s, $j$[{"provider_account_id":"ext-a-bad-x","name":"bad tax","account_type":"investment","scope":"household","tax_treatment":"NOPE"}]$j$::jsonb) $$, :a_src1),
  '23514', null,
  '(15) malformed: an invalid tax_treatment fails closed at 23514 (the 003 CHECK) — the whole txn aborts through the RPC write path'
);

-- (16) a missing NOT NULL key (name) resolves to NULL via ->> -> the 003 NOT NULL raises 23502.
select throws_ok(
  format($$ select pfin.fn_land_linked_accounts(%s, $j$[{"provider_account_id":"ext-a-noname","account_type":"investment","scope":"household","tax_treatment":"taxable"}]$j$::jsonb) $$, :a_src1),
  '23502', null,
  '(16) malformed: a missing NOT NULL key (name) resolves to NULL via ->> and fails closed at 23502 (the 003 NOT NULL) — RED if the RPC coalesced a NULL to a default (silent landing of an under-specified account)'
);

-- (17) empty-array is VALID (not malformed) -> a clean no-op (no error). Non-vacuous control that
--      (12)-(16) fail on the malformation, not on the call shape.
select lives_ok(
  format($$ select pfin.fn_land_linked_accounts(%s, $j$[]$j$::jsonb) $$, :a_src1),
  '(17) empty-array positive control: p_accounts=[] is a clean no-op (no error) — non-vacuous control proving (12)-(16) fail on the malformation, not on the RPC call shape'
);

-- (18) LOAD-BEARING all-or-nothing: a batch [valid ext-a-9, invalid account_type ext-a-10] aborts
--      the whole call -> NEITHER row lands. First the raise (23514)...
select throws_ok(
  format($$ select pfin.fn_land_linked_accounts(%s, $j$[
             {"provider_account_id":"ext-a-9","name":"valid one","account_type":"investment","scope":"household","tax_treatment":"taxable"},
             {"provider_account_id":"ext-a-10","name":"invalid one","account_type":"NOT_A_TYPE","scope":"household","tax_treatment":"taxable"}
           ]$j$::jsonb) $$, :a_src1),
  '23514', null,
  '(18a) atomicity setup: a batch whose 2nd element has an invalid account_type raises 23514 (the invalid element aborts the call)'
);

-- ...then neither the valid nor the invalid provider_account_id persisted (all-or-nothing).
select is(
  (select count(*) from pfin.account
     where linked_source_id = :a_src1 and provider_account_id in ('ext-a-9', 'ext-a-10'))::bigint,
  0::bigint,
  '(18) LOAD-BEARING ATOMICITY: the [valid, invalid] batch landed NEITHER row (the valid ext-a-9 did NOT commit before the invalid ext-a-10 aborted) — all-or-nothing on the immutable-adjacent account entity; RED if the RPC committed per element (partial landing, client compensation blocked — no account DELETE)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 5 (authenticated C, mfa_policy='totp') — the INHERITED 025 aal2 posture fires THROUGH the
--   INVOKER RPC. FENCE-ORDER FINDING (surfaced to Sec/Backend, see below): for a PROVIDER-LINKED
--   landing the sub-aal2 totp caller is stopped at the 015 #6 fence (its OWN aal2-gated
--   linked_source is RLS-invisible at aal1), BEFORE the account WITH CHECK aal2 clause is reached.
--   Still fail-closed. The account-level aal2 clause is defense-in-depth behind it (025 W1 proves it
--   directly on a bare insert). C at aal2 lands (source visible + WITH CHECK passes).
-- =====================================================================

-- (19) LOAD-BEARING inherited 025 aal2 posture (fence-order): a totp caller at aal1 landing via the
--      RPC FAILS CLOSED. The mechanism that fires FIRST is the 015 #6 fence, NOT the account WITH
--      CHECK: pfin.linked_source's SELECT policy ALSO carries the 025 aal2 clause, so at aal1 the
--      caller's OWN source is RLS-INVISIBLE; the BEFORE INSERT fn_account_matched_linked_source
--      (INVOKER) reads NOT EXISTS -> raises 'cross-tenant linked_source rejected%' before the account
--      WITH CHECK. A sub-aal2 totp caller cannot land — RED if it could (aal2-bypass on the linked
--      write path). ⚠ NOTE (Sec/Backend — RESOLVED at the app layer): Backend's pre-RPC requireStepUp
--      guard sends a legit aal1 owner WITH a verified GoTrue factor to /mfa/step-up before the RPC
--      (app-path proof: attributesPersistTwoTenant.dbit case 4). The guard keys off GoTrue AAL and this
--      clause keys off the pfin mfa_policy COLUMN; a mfa_policy='totp' user with NO verified factor
--      would hit this #6 fence, but the app's MFA flows cannot create that state (disable + recovery
--      downgrade mfa_policy FIRST — Backend-verified) → out-of-band-only + recovery-covered, with this
--      DB fence as its fail-closed backstop (dbit case 3). The migration header's "fails the INSERT
--      WITH CHECK closed" is imprecise for the provider-linked case (it fails at #6 first).
select _rls.set_tenant_aal(:'tc'::uuid, 'aal1');
select throws_like(
  format($$ select pfin.fn_land_linked_accounts(%s, $j$[{"provider_account_id":"ext-c-1","name":"C aal1","account_type":"investment","scope":"household","tax_treatment":"taxable"}]$j$::jsonb) $$, :c_src1),
  'cross-tenant linked_source rejected%',
  '(19) LOAD-BEARING inherited 025 aal2 (fence-order): a totp caller at aal1 landing via the RPC FAILS CLOSED at the 015 #6 fence — its OWN aal2-gated linked_source is RLS-invisible at aal1 so fn_account_matched_linked_source raises before the account WITH CHECK (which is defense-in-depth behind it; 025 W1 proves it directly). RED if a sub-aal2 totp caller could land via the RPC'
);
select set_config('role', 'postgres', true);

-- (20) non-vacuous aal control: the SAME totp caller at aal2 lands successfully -> (19) is aal-driven.
select _rls.set_tenant_aal(:'tc'::uuid, 'aal2');
select lives_ok(
  format($$ select pfin.fn_land_linked_accounts(%s, $j$[{"provider_account_id":"ext-c-1","name":"C aal2","account_type":"investment","scope":"household","tax_treatment":"taxable"}]$j$::jsonb) $$, :c_src1),
  '(20) non-vacuous aal control: the SAME totp caller at aal2 lands successfully via the RPC -> proving (19) is aal-driven (the inherited backstop gates on the caller''s own session assurance), not a blanket block of tenant C'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 6 (anon + catalog) — anon cannot execute the write RPC (EXECUTE revoked from PUBLIC,
--   granted to authenticated only; internet-facing exposure fence per ADR-023).
-- =====================================================================
-- (21) grant-layer: anon holds NO EXECUTE on the RPC (role-independent catalog assertion).
select ok(
  not has_function_privilege('anon', 'pfin.fn_land_linked_accounts(bigint, jsonb)', 'EXECUTE'),
  '(21) anon holds NO EXECUTE on fn_land_linked_accounts (revoked from PUBLIC, granted to authenticated only — the write RPC is not anon-callable)'
);

-- (22) behavior: an actual anon call fails closed at 42501 (no schema-USAGE / no EXECUTE).
select set_config('role', 'anon', true);  -- superuser session can SET ROLE
select throws_ok(
  format($$ select pfin.fn_land_linked_accounts(%s, $j$[{"provider_account_id":"ext-anon","name":"anon try","account_type":"investment","scope":"household","tax_treatment":"taxable"}]$j$::jsonb) $$, :a_src1),
  '42501', null,
  '(22) anon call fails closed: an anon invocation of fn_land_linked_accounts is denied at 42501 (no schema-USAGE / no EXECUTE) — the landing path is authenticated-tier only'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;

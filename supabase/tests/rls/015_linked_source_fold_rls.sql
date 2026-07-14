-- =====================================================================
-- Per-Wave battery — pfin.linked_source R-14 credential-store fold (ADR-027 / 015 —
--   C6 EXPOSURE-GATING per ADR-023 / SECURITY §4.5; V1-SHIP-BLOCK; sec-joint-review GREEN)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/015_linked_source_fold.sql
--   - pfin.linked_source                     (SD-03 credential store; RLS direct-owner
--                                              users_id = auth.uid(); column-level SELECT to
--                                              authenticated EXCLUDING credential_secret_id;
--                                              NO authenticated write path — service_role sole
--                                              writer, Decision 1; generalizes plaid_items)
--   - pfin.decrypted_source_credential       (service_role-ONLY decrypt view; JOIN
--                                              vault.decrypted_secrets -> linked_source;
--                                              Sec merge-block 5; generalizes
--                                              decrypted_plaid_access_token)
--   - pfin.linked_source_state_history        (append-only credential-error audit; RLS
--                                              EXISTS-JOIN via source_id -> linked_source;
--                                              immutability triple-fence; generalizes
--                                              plaid_item_state_history)
--   - pfin.linked_source_sync_audit           (append-only multi-provider sync audit;
--                                              service_role-ONLY default-deny for authenticated;
--                                              immutability triple-fence; generalizes plaid_sync_audit)
--   - fn_account_matched_linked_source        (SECURITY INVOKER; BEFORE INSERT OR UPDATE ON
--                                              pfin.account WHEN (new.linked_source_id IS NOT NULL);
--                                              NULL-safe fail-closed NOT EXISTS -> raise
--                                              'cross-tenant linked_source rejected%'; Decision-3
--                                              CANONICAL instance #6 — the fence on
--                                              account.linked_source_id; mirrors 012
--                                              fn_account_matched_sub_cat)
-- Prereqs exercised (already on main): 001 (pfin schema + fn_refresh_updated_at), 003 (pfin.account
--   RLS/GRANT + fn_grant_creator_access creator-grant trigger — the app-path account write),
--   008 (service_role schema USAGE + config.toml [api] += "pfin"; pfin is internet-facing),
--   012 (account.sub_cat_id fence — skipped here since sub_cat_id is never set), platform
--   supabase_vault (vault.secrets / vault.decrypted_secrets — for the RT-02 containment asserts).
--   015 DROPs the 4 empty Plaid objects (007) and recreates them generalized; this battery
--   GENERALIZES supabase/tests/rls/007_plaid_platform_schema_rls.sql onto the new objects.
-- Reuses the SELF-187/189/190/196/231/012 idiom: \ir verbs, ALL-LOWERCASE \gset literals (005
--   case-fold lesson), SQLSTATE-precise throws_ok + message-precise throws_like (004 all-42501
--   false-green lesson), role restored to postgres between blocks (PR #121 _rls-USAGE root-cause).
--
-- ┌─ WHY EACH REJECTION MATCHES A DIFFERENT SIGNAL (no fence passes for another) ─────────┐
-- │  • cross-tenant linked_source read (B on A)   -> RLS filters -> 0 rows (is, not throw)  │
-- │  • withheld credential column                  -> has_column_privilege = FALSE (ACL)    │
-- │  • authenticated write on credential store     -> 42501 permission denied (no write grant)│
-- │  • decrypt-view / sync_audit reach             -> has_table_privilege = FALSE (grant absent)│
-- │  • sync_audit SELECT under authenticated       -> 42501 hard ACL deny (stronger than 0-rows)│
-- │  • state_history/sync_audit UPDATE|DELETE      -> P0001 '<tbl> is immutable%<OP> blocked%'│
-- │  • state_history/sync_audit TRUNCATE           -> P0001 '<tbl> is immutable%TRUNCATE blocked%'│
-- │  • cross-tenant account->source link (D3 #6)   -> P0001 'cross-tenant linked_source rejected%'│
-- │ SQLSTATE-precise (42501) + message-precise (per-table immutability + the fence text) keeps  │
-- │ one fence from ever passing for another (the 004 all-42501 discipline).                     │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (1a)/(1c+)   -> non-vacuous positives (owner reads OWN rows; a non-credential column IS
--                     granted) — guard an over-restrictive RLS / a blanket column denial.
--   (1b)         -> RED if the linked_source SELECT policy were dropped/widened (B sees A's sources).
--   (1c)         -> RED if the column grant leaked credential_secret_id to authenticated (the Vault
--                     handle would be client-reachable — defeats the withholding + belt REVOKE).
--   (1d)/(1e)/(1f)-> RED if authenticated ever gained INSERT/UPDATE/DELETE on the credential store
--                     (service_role is the SOLE writer per Decision 1 — a client write path would be
--                     a credential-tamper surface; C6 write-fails-closed for the credential table).
--   (2a)         -> non-vacuous positive: service_role HOLDS SELECT on the decrypt view (grant not
--                     vacuously absent) — RED if the intended consumer role lost reach.
--   (2b)/(2c)    -> LOAD-BEARING: RED if the decrypt view were granted beyond service_role (default
--                     decrypt perms would defeat RT-02 — authenticated/anon could read plaintext).
--   (2d)/(2e)    -> RT-02 containment as a TESTED invariant: RED if authenticated ever gained SELECT
--                     on the RAW vault surfaces (vault.secrets / vault.decrypted_secrets).
--   (3a)         -> non-vacuous positive: owner A reads its OWN state-history via the EXISTS-JOIN.
--   (3b)         -> RED if the state_history EXISTS-JOIN SELECT policy leaked (B reads A's history).
--   (3c)/(3d)/(3e)-> RED if any state_history immutability trigger (or its wiring) were removed: a
--                     privileged UPDATE/DELETE/TRUNCATE would SUCCEED (audit-tamper / audit-wipe).
--   (4a)/(4b)    -> RED if sync_audit were granted to authenticated/anon (it is service_role-only;
--                     Architect flagged the sync-audit as the silent-leak-risk table under ADR-023).
--   (4c)         -> RED if authenticated gained reach to sync_audit: a HARD 42501 ACL deny (no grant
--                     => no row can EVER surface), strictly stronger than a 0-rows RLS filter.
--   (4d)/(4e)/(4f)-> RED if any sync_audit immutability trigger were removed (same battery as (3)).
--   (5a)/(5b)/(5c)/(5d)/(5e) -> non-vacuous positives: A links OWN account to OWN source (INSERT +
--                     re-link UPDATE) SUCCEEDS; the tag is persisted+readable; NULL link allowed;
--                     B links OWN->OWN SUCCEEDS. RED if the fence over-broadly blocked matched tenants.
--   (5f)         -> LOAD-BEARING: RED if fn_account_matched_linked_source (or its trigger) were
--                     removed, or the users_id predicate dropped -> B's cross-tenant INSERT link
--                     would COMMIT (the exact chain-attack Decision-3 instance #6 fences).
--   (5g)         -> RED if the fence did not cover UPDATE (BEFORE INSERT OR UPDATE) -> a re-link
--                     could pivot an account to another tenant's source.
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 2 (RT-22 + RT-26; 015 introduces ZERO catalogued §10
--   instances — the decrypt-view/service_role GRANTs are DB-LAYER ACLs, NOT the RT-26 code-layer
--   SERVICE_ROLE_KEY allowlist grep nor the RT-22 PDF-worker infra fence; per the 015 header §10
--   3-axis + Decision-3 eval, Path B). Decision-3 family: 015 lands CANONICAL instance #6
--   (account.linked_source_id -> linked_source) — THIS battery is the pgTAP proof its matched-tenant
--   fence catches a REAL cross-tenant violation (Sec joint-review; family 5 -> 6).
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b(); NO PII /
--   NO real account numbers / NO real credentials (SD-03) / NO prod data. linked_source rows carry
--   provider='manual' with credential_secret_id NULL (credential-less) — no Vault secret is created;
--   the RT-02 containment asserts (2d)/(2e) are ACL facts, not a decrypt round-trip, so nothing real
--   enters CI. linked_source + audit rows are seeded PRIVILEGED (role=postgres) — the credential
--   store has NO authenticated write path (service_role sole writer, Decision 1). All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so NO
--   `_rls.*` call runs under authenticated. Tenant UUIDs + row ids are resolved to psql LITERALS via
--   \gset at role=postgres; every _rls.set_tenant is called at role=postgres and each block restores
--   role=postgres before the next. \gset var names are ALL-LOWERCASE. Immutability + privilege probes
--   run as the postgres OWNER so the TRIGGER / ACL — not a missing grant — is the sole gate.
--
-- ⟦WIRE-VALIDATE⟧ authored against 015's firmed contract; the authoritative run is against the
--   001->015 reset stack. Roles authenticated / service_role / anon name-checked; vault.secrets /
--   vault.decrypted_secrets require the platform supabase_vault extension (present if 015 applies —
--   the decrypt view's JOIN would not create otherwise). RED-until-015-applied is expected on any
--   pre-015 stack (linked_source / account.linked_source_id absent).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(30);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed; the sole linked_source write path).
-- A owns TWO sources; B owns ONE. users_id set explicitly (auth.uid() is NULL under postgres).
-- provider='manual' + credential_secret_id NULL (credential-less) -> no Vault secret created;
-- external_connection_id values are distinct to satisfy the (provider, external id) unique index.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name)
  values (:'ta', 'manual', 'conn-a-1', 'Synthetic Bank A')
  returning source_id as a_src1 \gset
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name)
  values (:'ta', 'manual', 'conn-a-2', 'Synthetic Bank A2')
  returning source_id as a_src2 \gset
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name)
  values (:'tb', 'manual', 'conn-b-1', 'Synthetic Bank B')
  returning source_id as b_src1 \gset

-- state_history rows for A's first source (A-owned via source_id -> linked_source.users_id).
insert into pfin.linked_source_state_history (source_id, status_class, provider_error_code)
  values (:a_src1, 'login_required', 'ITEM_LOGIN_REQUIRED'),
         (:a_src1, 'healthy', null);

-- one sync_audit row (service_role-only table; seeded privileged) for the immutability probes.
insert into pfin.linked_source_sync_audit (provider, source, users_id, external_connection_id, provider_event_id, event_type)
  values ('manual', 'scheduled_poll', :'ta', 'conn-a-1', 'evt-idem-1', 'SYNC');

-- Hold pfin USAGE open to service_role (test setup, rolled back) — parity with 007; the
-- has_table_privilege probes below are ACL facts independent of schema usage, but keep the grant.
grant usage on schema pfin to service_role;

-- =====================================================================
-- OBJECT 1 — pfin.linked_source: direct-owner RLS + credential-column withholding +
--   NO authenticated write path (service_role sole writer, Decision 1).
-- =====================================================================
-- (1a) owner A reads exactly its 2 own sources (RLS not over-restrictive — positive).
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*) from pfin.linked_source where users_id = :'ta')::bigint, 2::bigint,
  '(1a) two-tenant core: owner A reads exactly its 2 own linked_source rows (direct-owner RLS users_id = auth.uid())'
);
select set_config('role', 'postgres', true);

-- (1b) cross-tenant read fails closed: B sees ZERO of A's sources.
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from pfin.linked_source where users_id = :'ta')::bigint, 0::bigint,
  '(1b) cross-tenant read fails closed: B sees 0 of A''s linked_source rows (RLS direct-owner isolation)'
);
select set_config('role', 'postgres', true);

-- (1c) the Vault credential handle is WITHHELD from authenticated (column grant excludes it + belt REVOKE).
select ok(
  not has_column_privilege('authenticated', 'pfin.linked_source', 'credential_secret_id', 'SELECT'),
  '(1c) credential_secret_id is WITHHELD from authenticated (Vault handle not client-reachable — column grant excludes it + belt REVOKE)'
);
-- (1c+) NON-vacuous control: a non-credential column IS granted (withholding is column-specific).
select ok(
  has_column_privilege('authenticated', 'pfin.linked_source', 'provider', 'SELECT'),
  '(1c+) control: authenticated DOES hold SELECT on the non-credential provider column (withholding is column-specific, not a blanket table denial)'
);

-- (1d) authenticated INSERT fails closed: no write grant -> 42501 (service_role is the sole writer).
select _rls.set_tenant(:'ta'::uuid);
select throws_ok(
  format($$ insert into pfin.linked_source (users_id, provider) values (%L, 'manual') $$, :'ta'),
  '42501', null,
  '(1d) NO authenticated write path: an authenticated INSERT into linked_source raises permission denied (42501) — service_role sole writer (Decision 1)'
);
select set_config('role', 'postgres', true);

-- (1e) authenticated UPDATE fails closed: no update grant -> 42501.
select _rls.set_tenant(:'ta'::uuid);
select throws_ok(
  format($$ update pfin.linked_source set institution_name = 'tampered' where source_id = %s $$, :a_src1),
  '42501', null,
  '(1e) NO authenticated write path: an authenticated UPDATE of linked_source raises permission denied (42501) — no update grant, credential-store is service_role-only'
);
select set_config('role', 'postgres', true);

-- (1f) authenticated DELETE fails closed: no delete grant -> 42501.
select _rls.set_tenant(:'ta'::uuid);
select throws_ok(
  format($$ delete from pfin.linked_source where source_id = %s $$, :a_src1),
  '42501', null,
  '(1f) NO authenticated write path: an authenticated DELETE of linked_source raises permission denied (42501) — deletion forced through the service_role revoke-then-delete path'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- OBJECT 2 — pfin.decrypted_source_credential: service_role-ONLY decrypt view (Sec merge-block 5)
--   + RT-02 containment (raw Vault surfaces closed to authenticated).
-- =====================================================================
-- (2a) POSITIVE: service_role holds SELECT on the decrypt view (grant not vacuously absent).
select ok(
  has_table_privilege('service_role', 'pfin.decrypted_source_credential', 'SELECT'),
  '(2a) decrypt view SELECT is GRANTED to service_role (the intended consumer role — grant not vacuously absent)'
);
-- (2b) LOAD-BEARING: authenticated is DENIED SELECT on the decrypt view.
select ok(
  not has_table_privilege('authenticated', 'pfin.decrypted_source_credential', 'SELECT'),
  '(2b) decrypt view SELECT is DENIED to authenticated (Sec merge-block 5 — default decrypt perms would defeat RT-02)'
);
-- (2c) LOAD-BEARING: anon is DENIED SELECT on the decrypt view.
select ok(
  not has_table_privilege('anon', 'pfin.decrypted_source_credential', 'SELECT'),
  '(2c) decrypt view SELECT is DENIED to anon (Sec merge-block 5 — internet-facing anon fenced)'
);
-- (2d) RT-02 containment: authenticated holds NO SELECT on the raw vault.secrets ciphertext store.
select ok(
  not has_table_privilege('authenticated', 'vault.secrets', 'SELECT'),
  '(2d) RT-02 containment: authenticated holds NO SELECT on vault.secrets (raw ciphertext store unreachable — platform-default containment as a tested invariant)'
);
-- (2e) RT-02 containment: authenticated holds NO SELECT on the whole-vault decrypt surface.
select ok(
  not has_table_privilege('authenticated', 'vault.decrypted_secrets', 'SELECT'),
  '(2e) RT-02 containment: authenticated holds NO SELECT on vault.decrypted_secrets (whole-vault decrypt surface unreachable — only the service_role-scoped pfin view exposes a credential)'
);

-- =====================================================================
-- OBJECT 3 — pfin.linked_source_state_history: EXISTS-JOIN tenant isolation + append-only immutability.
--   Immutability probes run as the postgres OWNER so the TRIGGER (not an ACL) is the sole gate.
-- =====================================================================
-- (3a) POSITIVE: owner A reads its 2 state-history rows via the EXISTS-JOIN to linked_source.
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*) from pfin.linked_source_state_history where source_id = :a_src1)::bigint, 2::bigint,
  '(3a) state_history RLS positive: owner A reads its 2 state-history rows via the EXISTS-JOIN to linked_source (read path not over-restrictive)'
);
select set_config('role', 'postgres', true);
-- (3b) cross-tenant read fails closed: B sees ZERO of A's state-history.
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from pfin.linked_source_state_history where source_id = :a_src1)::bigint, 0::bigint,
  '(3b) state_history cross-tenant read fails closed: B sees 0 of A''s state-history (EXISTS-JOIN to linked_source yields no match for a non-owner)'
);
select set_config('role', 'postgres', true);

-- Resolve one state_history row id (privileged) for the immutability UPDATE/DELETE probes.
select history_id as sh1 from pfin.linked_source_state_history where source_id = :a_src1 order by history_id limit 1 \gset

-- (3c) state_history UPDATE blocked by the immutability trigger (fires for ALL roles).
select throws_like(
  format($$ update pfin.linked_source_state_history set status_class = 'healthy' where history_id = %s $$, :sh1),
  'pfin.linked_source_state_history is immutable%UPDATE blocked%',
  '(3c) state_history append-only: UPDATE blocked by the immutability TRIGGER (audit-tamper fenced for ALL roles incl. the owner)'
);
-- (3d) state_history DELETE blocked.
select throws_like(
  format($$ delete from pfin.linked_source_state_history where history_id = %s $$, :sh1),
  'pfin.linked_source_state_history is immutable%DELETE blocked%',
  '(3d) state_history append-only: DELETE blocked by the immutability TRIGGER'
);
-- (3e) state_history TRUNCATE blocked by the statement-level trigger (row triggers don't fire on TRUNCATE).
select throws_like(
  $$ truncate pfin.linked_source_state_history $$,
  'pfin.linked_source_state_history is immutable%TRUNCATE blocked%',
  '(3e) state_history append-only: TRUNCATE blocked by the statement-level immutability TRIGGER (bulk audit-wipe path fenced)'
);

-- =====================================================================
-- OBJECT 4 — pfin.linked_source_sync_audit: service_role-ONLY default-deny + append-only immutability.
-- =====================================================================
-- (4a) service_role-only: sync_audit is NOT granted to authenticated (internal audit log — default-deny).
select ok(
  not has_table_privilege('authenticated', 'pfin.linked_source_sync_audit', 'SELECT'),
  '(4a) sync_audit is service_role-only: authenticated holds NO SELECT (internal audit of privileged writes — default-deny)'
);
-- (4b) ...and anon holds NO SELECT either (the silent-leak-risk table fenced against internet-facing anon).
select ok(
  not has_table_privilege('anon', 'pfin.linked_source_sync_audit', 'SELECT'),
  '(4b) sync_audit deny-by-default: anon holds NO SELECT (silent-leak-risk table fenced against the internet-facing anon role too)'
);
-- (4c) BEHAVIORAL hard ACL deny: under authenticated the SELECT raises 42501 (no grant => no row can
--      EVER surface — strictly stronger than a 0-rows RLS filter).
select _rls.set_tenant(:'ta'::uuid);
select throws_ok(
  $$ select count(*) from pfin.linked_source_sync_audit $$,
  '42501', null,
  '(4c) sync_audit deny-by-default (behavioral): authenticated SELECT raises permission denied (42501) — hard ACL deny, stronger than 0-rows (no grant => no row can ever leak)'
);
select set_config('role', 'postgres', true);

-- Resolve one sync_audit row id (privileged) for its immutability probes.
select audit_id as sa1 from pfin.linked_source_sync_audit order by audit_id limit 1 \gset

-- (4d) sync_audit UPDATE blocked — SAME immutability battery as state_history.
select throws_like(
  format($$ update pfin.linked_source_sync_audit set event_type = 'TAMPERED' where audit_id = %s $$, :sa1),
  'pfin.linked_source_sync_audit is immutable%UPDATE blocked%',
  '(4d) sync_audit append-only: UPDATE blocked by the immutability TRIGGER (same battery as state_history)'
);
-- (4e) sync_audit DELETE blocked.
select throws_like(
  format($$ delete from pfin.linked_source_sync_audit where audit_id = %s $$, :sa1),
  'pfin.linked_source_sync_audit is immutable%DELETE blocked%',
  '(4e) sync_audit append-only: DELETE blocked by the immutability TRIGGER'
);
-- (4f) sync_audit TRUNCATE blocked (statement-level; no inbound FK -> plain TRUNCATE is the honest probe).
select throws_like(
  $$ truncate pfin.linked_source_sync_audit $$,
  'pfin.linked_source_sync_audit is immutable%TRUNCATE blocked%',
  '(4f) sync_audit append-only: TRUNCATE blocked by the statement-level immutability TRIGGER (audit-wipe path fenced)'
);

-- =====================================================================
-- OBJECT 5 — fn_account_matched_linked_source (Decision-3 CANONICAL instance #6): the cross-tenant
--   WRITE fence on account.linked_source_id. Accounts are created via the APP PATH under authenticated
--   (users_id DEFAULT auth.uid()); the 003 creator-grant trigger fires harmlessly; the fence is the
--   sole gate. Mirrors 012 fn_account_matched_sub_cat exactly (matched PASS + cross-tenant RAISE + NULL).
-- =====================================================================
-- BLOCK 5A (authenticated A) — matched-tenant PASS (INSERT + re-link UPDATE) + NULL-link allowed.
select _rls.set_tenant(:'ta'::uuid);

-- (5a) matched-tenant INSERT positive: A links a fresh account to its OWN source -> accepted.
select lives_ok(
  format($$ insert into pfin.account (name, account_type, scope, tax_treatment, linked_source_id)
              values ('A linked acct 1', 'depository', 'household', 'taxable', %s) $$, :a_src1),
  '(5a) matched-tenant INSERT: A links its OWN account to its OWN linked_source -> fn_account_matched_linked_source ACCEPTS (owner-links-own INSERT, non-vacuous positive)'
);

-- fixture: a second linked account, captured for the read (5b) + re-link UPDATE (5c).
insert into pfin.account (name, account_type, scope, tax_treatment, linked_source_id)
  values ('A linked acct 2', 'depository', 'household', 'taxable', :a_src1)
  returning account_id as acct_a \gset

-- (5b) owner-reads-own: A reads its account carrying its own linked_source_id under RLS.
select is(
  (select linked_source_id from pfin.account where account_id = :acct_a),
  :a_src1::bigint,
  '(5b) owner-reads-own: A reads its own account carrying its own linked_source_id under RLS (the link is really persisted + visible)'
);

-- (5c) matched-tenant UPDATE positive: A re-links the account to ANOTHER of ITS OWN sources -> accepted.
select lives_ok(
  format($$ update pfin.account set linked_source_id = %s where account_id = %s $$, :a_src2, :acct_a),
  '(5c) matched-tenant UPDATE: A re-links its account to another of ITS OWN sources -> fence ACCEPTS (BEFORE INSERT OR UPDATE covers the re-link path, not just INSERT)'
);

-- (5d) NULL linked_source_id INSERT allowed: WHEN(new.linked_source_id IS NOT NULL) skips the fence.
select lives_ok(
  $$ insert into pfin.account (name, account_type, scope, tax_treatment)
       values ('A unlinked acct', 'depository', 'household', 'taxable') $$,
  '(5d) NULL linked_source_id: an INSERT omitting linked_source_id SUCCEEDS — fence WHEN(new.linked_source_id IS NOT NULL) skips (manual/unlinked account stays insertable)'
);
select set_config('role', 'postgres', true);

-- BLOCK 5B (authenticated B) — THE LOAD-BEARING cross-tenant fence + a non-vacuous positive control.
select _rls.set_tenant(:'tb'::uuid);

-- (5e) NON-VACUOUS CONTROL: B links its OWN account to its OWN source -> accepted. Proves the (5f)/(5g)
--      raises are cross-tenant-MISMATCH-driven, not a blanket authenticated-B block.
select lives_ok(
  format($$ insert into pfin.account (name, account_type, scope, tax_treatment, linked_source_id)
              values ('B links own', 'depository', 'household', 'taxable', %s) $$, :b_src1),
  '(5e) control: B links its OWN account to its OWN linked_source -> ACCEPTED (proves the cross-tenant raises below are mismatch-driven, not a blanket authenticated-B block)'
);

-- (5f) LOAD-BEARING cross-tenant INSERT fails closed: B links its own account to A's source_id. The
--      BEFORE INSERT fence reads linked_source(source_id=A's, users_id=B) -> NOT EXISTS (A's row is
--      users_id=A AND RLS-invisible to B) -> RAISE. Assert the RAISE (not a silent pass, not a bare
--      42501, not a 23503 FK violation).
select throws_like(
  format($$ insert into pfin.account (name, account_type, scope, tax_treatment, linked_source_id)
              values ('B steals A source', 'depository', 'household', 'taxable', %s) $$, :a_src1),
  'cross-tenant linked_source rejected%',
  '(5f) LOAD-BEARING cross-tenant INSERT: B links its own account to A''s linked_source_id -> fn_account_matched_linked_source RAISES (NOT EXISTS matched-tenant row; the exact chain-attack Decision-3 instance #6 fences — a real violation, not a silent pass)'
);

-- fixture: B's own unlinked account (NULL link -> WHEN skips -> inserts), captured for (5g).
insert into pfin.account (name, account_type, scope, tax_treatment)
  values ('B unlinked acct', 'depository', 'household', 'taxable')
  returning account_id as acct_b \gset

-- (5g) cross-tenant UPDATE fails closed: B re-links its own account to A's source -> BEFORE UPDATE RAISES.
select throws_like(
  format($$ update pfin.account set linked_source_id = %s where account_id = %s $$, :a_src1, :acct_b),
  'cross-tenant linked_source rejected%',
  '(5g) cross-tenant UPDATE: B re-links its own account to A''s linked_source_id -> fence RAISES (covers the UPDATE/re-link path — a re-link cannot pivot to another tenant''s source)'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;

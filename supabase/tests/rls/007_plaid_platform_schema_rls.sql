-- =====================================================================
-- Per-Wave battery — pfin Plaid platform schema (SELF-196 / 007 — V1-SHIP-BLOCK,
--   sec-joint-review-mandatory)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/007_plaid_platform_schema.sql
--   - pfin.plaid_items                        (RLS: direct-owner users_id = auth.uid();
--                                              column-level SELECT to authenticated EXCLUDING
--                                              access_token_secret_id; UNIQUE(plaid_item_id);
--                                              access_token_secret_id uuid NOT NULL — Vault handle)
--   - pfin.decrypted_plaid_access_token       (service_role-ONLY view; JOIN vault.decrypted_secrets
--                                              -> plaid_items; Lock 4 mod #1)
--   - pfin.plaid_item_state_history           (append-only 4-class enum audit; RLS EXISTS-JOIN
--                                              to plaid_items; immutability triple-fence)
--   - pfin.plaid_sync_audit                   (append-only; service_role-ONLY default-deny;
--                                              plaid_webhook_id UNIQUE idempotency gate — mod #3;
--                                              immutability triple-fence)
--   - fn_plaid_items_cleanup_vault_secret       (v3; AFTER DELETE ON pfin.plaid_items; SECURITY
--                                              INVOKER; if the deleting role holds DELETE on
--                                              vault.secrets it deletes the backing secret,
--                                              else RAISES a by-design fail-closed exception —
--                                              closes the auth.users cascade orphan; AC #6)
-- ALSO BINDS TO: supabase/migrations/008_pfin_service_role_grants.sql (+ config.toml [api]
--   schemas += "pfin", ADR-023 Option A — pfin is now INTERNET-FACING via PostgREST/anon).
--   008 grants service_role scoped writes (plaid_items S/I/U/D; state_history + sync_audit +
--   account_trans S/I; account S) and RE-ASSERTS `revoke (access_token_secret_id) from
--   authenticated` (Sec C3). Exercised here by: C2 anon outer-fence (C2a/C2b), C3 re-confirm
--   (existing (2c) column-withhold now runs POST-008), plaid_sync_audit deny-by-default
--   (4e/4f/4g), and the cascade fail-closed ACL fact (6f).
-- Reuses the SELF-187/188/189/190 idiom: \ir verbs, ALL-LOWERCASE \gset literals
--   (the 005 case-fold lesson), message-precise throws_like / SQLSTATE-precise throws_ok
--   (the 004 all-42501 false-green lesson), role restored to postgres between blocks.
--
-- ┌─ WHY EACH REJECTION MATCHES A DIFFERENT SIGNAL (no fence passes for another) ─────┐
-- │  • cross-tenant plaid_items read (B on A)      -> RLS filters -> 0 rows (is, not throw)│
-- │  • withheld credential column                  -> has_column_privilege = FALSE (ACL)   │
-- │  • duplicate plaid_item_id                      -> 23505 unique_violation               │
-- │  • unknown 5th error code                       -> 23514 check_violation                │
-- │  • state_history/sync_audit UPDATE|DELETE       -> P0001 '<tbl> is immutable%<OP> blocked%'│
-- │  • state_history/sync_audit TRUNCATE            -> P0001 '<tbl> is immutable%TRUNCATE blocked%'│
-- │ SQLSTATE-precise (23505/23514) + message-precise (per-table immutability text) keeps  │
-- │ one fence from ever passing for another (the 004 all-42501 discipline).               │
-- └────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (2a)/(3d)/(4a)/(4d)/(5a)/(5c) -> non-vacuous POSITIVES (guard over-restrictive RLS /
--                     a broken decrypt view / a broken idempotent path / an over-broad
--                     enum-block / an over-restrictive audit-read policy).
--   (2b)         -> RED if the plaid_items SELECT policy were dropped/widened (B sees A's Items).
--   (2c)         -> RED if the column-level grant leaked access_token_secret_id to authenticated
--                     (the Vault handle would be client-reachable — defeats the withholding).
--   (2d)/(2e)    -> RED if the NOT NULL / UNIQUE(plaid_item_id) constraints were dropped.
--   (3a)/(3b)/(3c)-> RED if the decrypt view were granted beyond service_role (mod #1 —
--                     default decrypt perms would defeat RT-02). (3b)/(3c) are the load-bearing
--                     denials; (3a) is the positive that proves the grant is not vacuously absent.
--   (3e)/(3f)    -> RED if authenticated ever gained SELECT on the RAW vault surfaces
--                     (vault.secrets / vault.decrypted_secrets) — Sec advisory golden asserts
--                     turning the platform-default RT-02 containment into a TESTED invariant.
--   (6a..6d)     -> RED if the AFTER DELETE retention trigger were removed/broken: the
--                     referenced vault.secrets row would SURVIVE plaid_items deletion (orphaned
--                     credential leak) — direct delete AND the auth.users ON DELETE CASCADE path.
--   (6e)         -> RED if service_role lost DELETE on vault.secrets (the INVOKER trigger's
--                     inner delete would fail under the real /item/remove removal role).
--   (6f)         -> RED if supabase_auth_admin GAINED DELETE on vault.secrets (the auth-cascade
--                     fail-closed guarantee would break — a GoTrue user-deletion could then
--                     silently orphan an un-revocable Plaid credential instead of aborting).
--   (C2a)/(C2b)  -> RED if anon gained USAGE on pfin OR SELECT on any pfin relation (the
--                     ADR-023 internet-facing OUTER fence — now load-bearing since pfin joined
--                     [api] schemas). (C2b) is dynamic ⇒ a FUTURE leaking pfin table auto-REDs.
--   (4f)/(4g)    -> RED if anon/authenticated gained reach to plaid_sync_audit (the
--                     silent-leak-risk audit table; (4g) proves a HARD ACL deny, not 0-rows).
--   (4b)/(4c)    -> RED if plaid_webhook_id UNIQUE were dropped (mod #3): the double-webhook
--                     would double-book (4b) OR a non-idempotent path would silently pass (4c).
--   (4e)         -> RED if plaid_sync_audit were granted to authenticated (it is service_role-only).
--   (5b)         -> RED if the 4-class CHECK were dropped (an unknown code would commit).
--   (5d)         -> RED if the state_history EXISTS-JOIN SELECT policy leaked (B reads A's history).
--   (5e..5j)     -> RED if any immutability trigger (or its trigger wiring) were removed: a
--                     privileged UPDATE/DELETE/TRUNCATE would SUCCEED (audit-tamper / audit-wipe).
--
-- §10 / DECISION 3: ledger UNCHANGED at 2 (RT-22 + RT-26); Decision-3 family UNCHANGED
--   (007 adds no matched-tenant FK-shaped column — plaid_items.users_id is a SOLE direct-owner
--   anchor; access_token_secret_id is NOT a pfin FK; the deferred account.plaid_item_id linkage
--   lands with SELF-197). Per the migration header §10 3-axis + Decision-3 eval.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b();
--   NO PII / NO real account numbers / NO real Plaid tokens (SD-03) / NO prod data. The
--   decrypt round-trip (3d) uses a SYNTHETIC sandbox-shaped token string created in-test via
--   vault.create_secret and rolled back with the txn — nothing persists, nothing real enters CI.
--   plaid_items rows are seeded PRIVILEGED (role=postgres): plaid_items has NO authenticated
--   write path (service_role is the sole writer per Decision 1); access_token_secret_id has no
--   pfin FK, so non-round-trip rows use gen_random_uuid() synthetic handles.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so NO
--   `_rls.*` call runs while switched to authenticated. Tenant UUIDs + object ids are resolved to
--   psql LITERALS via \gset at role=postgres; every _rls.set_tenant is called at role=postgres and
--   each block restores role=postgres before the next. \gset var names are ALL-LOWERCASE.
--
-- ⟦WIRE-VALIDATE⟧ (per the W3-A grounding discipline — authored against the firmed contract;
--   not claimed green until the first live `supabase test db` run on the 001→007 stack):
--   (i)  Vault: (3d) depends on the platform `supabase_vault` extension being installed +
--        functional in the test stack (vault.create_secret / vault.decrypted_secrets). If 007
--        applies on `supabase db reset` the extension is present (the view's JOIN would not
--        create otherwise). postgres is superuser locally, so it can execute vault.create_secret.
--   (ii) Roles: (3a)/(3b)/(3c)/(4e)/(4f)/(C2*) name-check `service_role` / `authenticated` /
--        `anon`; (6f) name-checks `supabase_auth_admin` (a platform role created at DB init,
--        independent of the GoTrue CONTAINER — so it exists even in the -x gotrue db-only CI
--        lane; if absent, that is THE adjustment point for (6f)). The immutability blocks
--        (5e..5j) run as the postgres OWNER so the TRIGGER — not an ACL — is the sole gate (a
--        removed trigger => the privileged write SUCCEEDS => RED).
--   (iii) 008/exposure: the C2 + deny-by-default asserts assume the 001→008 reset stack (008
--        grants + config.toml [api]+="pfin"). RED-until-008-applied is expected on a v1/v2 stack.
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(37);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed; the sole plaid_items write path).
-- A owns TWO Plaid Items; B owns ONE. users_id is set explicitly (auth.uid() is NULL under
-- postgres). A's first Item (itema1) is backed by a REAL synthetic Vault secret for the (3d)
-- decrypt round-trip; the other rows use synthetic gen_random_uuid() handles (no pfin FK on
-- access_token_secret_id, so any uuid is structurally valid).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

-- Synthetic sandbox-shaped token -> a real Vault secret (rolled back with the txn).
select vault.create_secret(
         'sbx-plaid-access-token-ROUNDTRIP-synthetic',
         'plaid_item_token_plaid-A-1',
         'SELF-196 battery — synthetic; rolled back') as secret_a \gset

insert into pfin.plaid_items (users_id, plaid_item_id, access_token_secret_id, institution_name)
  values (:'ta', 'plaid-A-1', :'secret_a', 'Synthetic Bank A')
  returning item_id as itema1 \gset
insert into pfin.plaid_items (users_id, plaid_item_id, access_token_secret_id, institution_name)
  values (:'ta', 'plaid-A-2', gen_random_uuid(), 'Synthetic Bank A2');
insert into pfin.plaid_items (users_id, plaid_item_id, access_token_secret_id, institution_name)
  values (:'tb', 'plaid-B-1', gen_random_uuid(), 'Synthetic Bank B');

-- Hold pfin USAGE open to service_role (test setup, rolled back) so the (3d) service_role
-- read of the decrypt view is gated by the view GRANT (mod #1) — not a missing schema usage.
grant usage on schema pfin to service_role;

-- =====================================================================
-- AC #2 — pfin.plaid_items shape + RLS + credential-column withholding.
-- =====================================================================
-- (2a) owner A reads exactly its 2 own Plaid Items (RLS not over-restrictive — positive).
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*) from pfin.plaid_items where users_id = :'ta')::bigint, 2::bigint,
  '(2a) two-tenant core: owner A reads exactly its 2 own plaid_items (direct-owner RLS users_id = auth.uid())'
);
select set_config('role', 'postgres', true);

-- (2b) cross-tenant read fails closed: B sees ZERO of A's Plaid Items.
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from pfin.plaid_items where users_id = :'ta')::bigint, 0::bigint,
  '(2b) cross-tenant read fails closed: B sees 0 of A''s plaid_items (RLS direct-owner isolation)'
);
select set_config('role', 'postgres', true);

-- (2c) the credential handle is WITHHELD from authenticated (column-level grant excludes it).
select ok(
  not has_column_privilege('authenticated', 'pfin.plaid_items', 'access_token_secret_id', 'SELECT'),
  '(2c) access_token_secret_id is WITHHELD from authenticated (Vault handle not client-reachable — column grant excludes it + REVOKE)'
);
-- (2c+) NON-vacuous control: a non-credential column IS granted (the withholding is column-
--       specific, not a blanket table denial that would make (2c) trivially true).
select ok(
  has_column_privilege('authenticated', 'pfin.plaid_items', 'plaid_item_id', 'SELECT'),
  '(2c+) control: authenticated DOES hold SELECT on the non-credential plaid_item_id column (withholding is column-specific, not a blanket denial)'
);

-- (2d) access_token_secret_id is NOT NULL (constraint present).
select col_not_null(
  'pfin', 'plaid_items', 'access_token_secret_id',
  '(2d) plaid_items.access_token_secret_id is NOT NULL (every Item row references a Vault secret)'
);

-- (2e) plaid_item_id is UNIQUE — a duplicate raises 23505 (behavioral; catches a dropped UNIQUE).
select throws_ok(
  format($$ insert into pfin.plaid_items (users_id, plaid_item_id, access_token_secret_id)
              values (%L, 'plaid-A-1', gen_random_uuid()) $$, :'ta'),
  '23505', null,
  '(2e) UNIQUE(plaid_item_id): a duplicate plaid_item_id raises unique_violation (23505)'
);

-- =====================================================================
-- AC #3 — pfin.decrypted_plaid_access_token: service_role-ONLY + decrypt round-trip (mod #1).
-- =====================================================================
-- (3a) POSITIVE: service_role holds SELECT on the decrypt view (grant not vacuously absent).
select ok(
  has_table_privilege('service_role', 'pfin.decrypted_plaid_access_token', 'SELECT'),
  '(3a) decrypt view SELECT is GRANTED to service_role (mod #1 — the intended consumer role)'
);
-- (3b) LOAD-BEARING: authenticated is DENIED SELECT on the decrypt view.
select ok(
  not has_table_privilege('authenticated', 'pfin.decrypted_plaid_access_token', 'SELECT'),
  '(3b) decrypt view SELECT is DENIED to authenticated (mod #1 — default decrypt perms would defeat RT-02)'
);
-- (3c) LOAD-BEARING: anon is DENIED SELECT on the decrypt view.
select ok(
  not has_table_privilege('anon', 'pfin.decrypted_plaid_access_token', 'SELECT'),
  '(3c) decrypt view SELECT is DENIED to anon (mod #1)'
);
-- (3d) ROUND-TRIP: under service_role, the view decrypts A's Item token back to the plaintext
--      (JOIN vault.decrypted_secrets -> plaid_items resolves via the view owner). Proves the
--      encrypt-at-rest / decrypt-under-service_role contract end-to-end.
select set_config('role', 'service_role', true);
select is(
  (select decrypted_access_token from pfin.decrypted_plaid_access_token where item_id = :itema1),
  'sbx-plaid-access-token-ROUNDTRIP-synthetic',
  '(3d) decrypt round-trip: service_role reads A''s Item token back via the view (vault.create_secret -> handle -> decrypt view returns the plaintext)'
);
select set_config('role', 'postgres', true);

-- (3e)/(3f) Sec advisory GOLDEN asserts — RT-02 containment as a TESTED invariant: the RAW
--   Vault surfaces are NOT reachable by authenticated. The service_role-scoped pfin decrypt
--   view is the ONLY path to a token; the whole-vault ciphertext + decrypt surfaces stay closed.
select ok(
  not has_table_privilege('authenticated', 'vault.secrets', 'SELECT'),
  '(3e) RT-02 containment: authenticated holds NO SELECT on vault.secrets (raw ciphertext store unreachable — platform-default containment turned into a tested invariant)'
);
select ok(
  not has_table_privilege('authenticated', 'vault.decrypted_secrets', 'SELECT'),
  '(3f) RT-02 containment: authenticated holds NO SELECT on vault.decrypted_secrets (whole-vault decrypt surface unreachable — only the service_role-scoped pfin view exposes a token)'
);

-- =====================================================================
-- C2 — ADR-023 INTERNET-FACING EXPOSURE OUTER FENCE (008 adds "pfin" to [api] schemas,
--   so every pfin relation is now reachable via PostgREST/anon). The two-layer fence is:
--   OUTER = anon holds ZERO pfin privileges; INNER = per-table RLS (users_id=auth.uid()/JOIN).
--   These assert the OUTER layer as a TESTED invariant now that it is load-bearing.
-- =====================================================================
-- (C2a) primary fence: anon is denied at the pfin SCHEMA-USAGE layer (008 CONTRACT: "anon is
--       denied at the schema-usage layer") — anon cannot reach ANY pfin object at all.
select ok(
  not has_schema_privilege('anon', 'pfin', 'USAGE'),
  '(C2a) ADR-023 outer fence: anon holds NO USAGE on schema pfin — no pfin object is anon-reachable at the schema layer (the primary internet-facing fence)'
);
-- (C2b) defense-in-depth + FUTURE-PROOF: NO pfin relation (table OR view) grants anon SELECT.
--       Dynamic over pg_class so a FUTURE pfin table that leaks to anon REDs automatically;
--       the failure message names the offending relation(s). Covers plaid_items / decrypt view /
--       plaid_item_state_history / plaid_sync_audit / account / account_trans / account_users /
--       reconciliation_event / reconciliation_event_trans / holdings_checkpoint — every pfin rel.
select is(
  (select coalesce(string_agg(c.relname, ', ' order by c.relname), '(none)')
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'pfin' and c.relkind in ('r','v','m','p')
       and has_table_privilege('anon', c.oid, 'SELECT')),
  '(none)',
  '(C2b) ADR-023 outer fence (table-grant sweep, future-proof): anon holds SELECT on ZERO pfin relations — offending relations listed if any leak'
);

-- =====================================================================
-- AC #4 — pfin.plaid_sync_audit: plaid_webhook_id UNIQUE idempotency gate (mod #3) +
--   service_role-only default-deny. All writes PRIVILEGED (service_role-only table).
-- =====================================================================
-- Seed the first webhook row (not an assertion).
insert into pfin.plaid_sync_audit (source, users_id, plaid_item_id, plaid_webhook_id, webhook_type)
  values ('webhook', :'ta', 'plaid-A-1', 'wh-idem-1', 'DEFAULT_UPDATE');

-- (4a) POSITIVE / idempotency: re-inserting the SAME plaid_webhook_id with ON CONFLICT DO
--      NOTHING is a CLEAN no-op (does not raise) — the webhook-replay path.
select lives_ok(
  $$ insert into pfin.plaid_sync_audit (source, users_id, plaid_item_id, plaid_webhook_id, webhook_type)
       values ('webhook', '00000000-0000-0000-0000-00000000000a', 'plaid-A-1', 'wh-idem-1', 'DEFAULT_UPDATE')
       on conflict (plaid_webhook_id) do nothing $$,
  '(4a) idempotency: re-INSERT of the same plaid_webhook_id ON CONFLICT DO NOTHING is a clean no-op (webhook replay does not raise)'
);
-- (4b) ...and it did NOT double-book: exactly ONE row carries that webhook id.
select is(
  (select count(*) from pfin.plaid_sync_audit where plaid_webhook_id = 'wh-idem-1')::bigint, 1::bigint,
  '(4b) idempotency: exactly 1 row for plaid_webhook_id = wh-idem-1 (the ON CONFLICT re-insert added no duplicate — UNIQUE gate holds)'
);
-- (4c) WITHOUT ON CONFLICT, the same webhook id raises 23505 (proves the UNIQUE is real, not
--      merely swallowed by the DO NOTHING clause).
select throws_ok(
  $$ insert into pfin.plaid_sync_audit (source, users_id, plaid_item_id, plaid_webhook_id, webhook_type)
       values ('webhook', '00000000-0000-0000-0000-00000000000a', 'plaid-A-1', 'wh-idem-1', 'DEFAULT_UPDATE') $$,
  '23505', null,
  '(4c) UNIQUE(plaid_webhook_id): a duplicate webhook id WITHOUT ON CONFLICT raises unique_violation (23505) — the idempotency gate is a real constraint'
);
-- (4d) POSITIVE: two poll rows with NULL plaid_webhook_id COEXIST (UNIQUE treats NULLs as
--      distinct) — the scheduled-poll path is not spuriously deduped.
insert into pfin.plaid_sync_audit (source, users_id, plaid_item_id, plaid_webhook_id)
  values ('scheduled_poll', :'ta', 'plaid-A-1', null),
         ('scheduled_poll', :'ta', 'plaid-A-2', null);
select is(
  (select count(*) from pfin.plaid_sync_audit where plaid_webhook_id is null and source = 'scheduled_poll')::bigint,
  2::bigint,
  '(4d) two NULL-webhook_id scheduled_poll rows COEXIST (UNIQUE treats NULLs as distinct — poll path not spuriously deduped)'
);
-- (4e) service_role-only: plaid_sync_audit is NOT granted to authenticated (internal audit log).
select ok(
  not has_table_privilege('authenticated', 'pfin.plaid_sync_audit', 'SELECT'),
  '(4e) plaid_sync_audit is service_role-only: authenticated holds NO SELECT (internal audit of privileged writes — default-deny)'
);
-- (4f) ...and anon holds NO SELECT either (Architect flagged plaid_sync_audit as the
--      silent-leak-risk table under ADR-023 exposure — both untrusted roles are fenced).
select ok(
  not has_table_privilege('anon', 'pfin.plaid_sync_audit', 'SELECT'),
  '(4f) plaid_sync_audit deny-by-default: anon holds NO SELECT (silent-leak-risk table fenced against the internet-facing anon role too)'
);
-- (4g) BEHAVIORAL (honest "0 rows" layer): under authenticated the SELECT is DENIED at the
--      table ACL (42501) — a HARD deny (table unreachable), strictly stronger than "returns 0
--      rows": no grant means no row can EVER surface, not merely that RLS filters them today.
select _rls.set_tenant(:'ta'::uuid);
select throws_ok(
  $$ select count(*) from pfin.plaid_sync_audit $$,
  '42501', null,
  '(4g) plaid_sync_audit deny-by-default (behavioral): authenticated SELECT raises permission denied (42501) — hard ACL deny, stronger than 0-rows (no grant ⇒ no row can ever leak)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- AC #5 — append-only + 4-class enum on plaid_item_state_history, and the SAME immutability
--   battery on plaid_sync_audit. Immutability blocks run as the postgres OWNER so the TRIGGER
--   (not an ACL) is the sole gate — a removed trigger => the privileged write SUCCEEDS => RED.
-- =====================================================================
-- (5a) POSITIVE: each of the 4 valid credential-error codes INSERTs (guards an over-broad block).
select lives_ok(
  format($$ insert into pfin.plaid_item_state_history (item_id, plaid_error_code, plaid_webhook_code)
              values (%s, 'ITEM_LOGIN_REQUIRED', 'ITEM_LOGIN_REQUIRED'),
                     (%s, 'INSTITUTION_DOWN', 'INSTITUTION_DOWN'),
                     (%s, 'INSTITUTION_GRANT_REVOKED', 'PENDING_DISCONNECT'),
                     (%s, 'USER_GRANT_REVOKED', 'USER_PERMISSION_REVOKED') $$,
         :itema1, :itema1, :itema1, :itema1),
  '(5a) all 4 valid credential-error codes INSERT into plaid_item_state_history (enum accepts the §2.4.4 4-class set — not over-restrictive)'
);
-- (5b) an unknown 5th code raises 23514 (the CHECK enum is real — catches a dropped constraint).
select throws_ok(
  format($$ insert into pfin.plaid_item_state_history (item_id, plaid_error_code)
              values (%s, 'TOTALLY_UNKNOWN_ERROR_CODE') $$, :itema1),
  '23514', null,
  '(5b) 4-class enum CHECK: an unknown 5th plaid_error_code raises check_violation (23514) — the enum fails closed on drift'
);

-- (5c)/(5d) state_history RLS EXISTS-JOIN read (new policy — two-tenant coverage).
--   A reads its 4 rows (via item ownership); B reads 0 of A's (join yields no match).
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*) from pfin.plaid_item_state_history where item_id = :itema1)::bigint, 4::bigint,
  '(5c) state_history RLS positive: owner A reads its 4 state-history rows via the EXISTS-JOIN to plaid_items (rd path not over-restrictive)'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from pfin.plaid_item_state_history where item_id = :itema1)::bigint, 0::bigint,
  '(5d) state_history cross-tenant read fails closed: B sees 0 of A''s state-history (EXISTS-JOIN to plaid_items yields no match for a non-owner)'
);
select set_config('role', 'postgres', true);

-- Resolve one state_history row id (privileged) for the immutability UPDATE/DELETE probes.
select history_id as sh1 from pfin.plaid_item_state_history where item_id = :itema1 order by history_id limit 1 \gset

-- (5e) state_history UPDATE blocked by the immutability trigger (fires for the owner too).
select throws_like(
  format($$ update pfin.plaid_item_state_history set plaid_error_code = 'INSTITUTION_DOWN' where history_id = %s $$, :sh1),
  'pfin.plaid_item_state_history is immutable%UPDATE blocked%',
  '(5e) state_history append-only: UPDATE blocked by the immutability TRIGGER (audit-tamper fenced for ALL roles incl. the owner)'
);
-- (5f) state_history DELETE blocked.
select throws_like(
  format($$ delete from pfin.plaid_item_state_history where history_id = %s $$, :sh1),
  'pfin.plaid_item_state_history is immutable%DELETE blocked%',
  '(5f) state_history append-only: DELETE blocked by the immutability TRIGGER'
);
-- (5g) state_history TRUNCATE blocked by the statement-level trigger (row triggers don't fire on
--      TRUNCATE; no inbound FK on state_history, so a plain TRUNCATE is the honest probe).
select throws_like(
  $$ truncate pfin.plaid_item_state_history $$,
  'pfin.plaid_item_state_history is immutable%TRUNCATE blocked%',
  '(5g) state_history append-only: TRUNCATE blocked by the statement-level immutability TRIGGER (bulk audit-wipe path fenced)'
);

-- Resolve one sync_audit row id (privileged) for its immutability probes.
select audit_id as sa1 from pfin.plaid_sync_audit order by audit_id limit 1 \gset

-- (5h) sync_audit UPDATE blocked — SAME immutability battery as state_history.
select throws_like(
  format($$ update pfin.plaid_sync_audit set webhook_type = 'TAMPERED' where audit_id = %s $$, :sa1),
  'pfin.plaid_sync_audit is immutable%UPDATE blocked%',
  '(5h) sync_audit append-only: UPDATE blocked by the immutability TRIGGER (same battery as state_history)'
);
-- (5i) sync_audit DELETE blocked.
select throws_like(
  format($$ delete from pfin.plaid_sync_audit where audit_id = %s $$, :sa1),
  'pfin.plaid_sync_audit is immutable%DELETE blocked%',
  '(5i) sync_audit append-only: DELETE blocked by the immutability TRIGGER'
);
-- (5j) sync_audit TRUNCATE blocked (statement-level; no inbound FK -> plain TRUNCATE).
select throws_like(
  $$ truncate pfin.plaid_sync_audit $$,
  'pfin.plaid_sync_audit is immutable%TRUNCATE blocked%',
  '(5j) sync_audit append-only: TRUNCATE blocked by the statement-level immutability TRIGGER (audit-wipe path fenced)'
);

-- =====================================================================
-- AC #6 (retention HARD-GATE) — the v2 AFTER DELETE ON pfin.plaid_items SECURITY INVOKER
--   trigger deletes the referenced vault.secrets row, closing the cascade-orphan credential
--   leak. Behavior-tested (trigger name-agnostic): the Vault secret must be GONE after the
--   owning plaid_items row is deleted — DIRECTLY and via the auth.users ON DELETE CASCADE path
--   (the actual leak scenario). Run as the postgres OWNER so the TRIGGER is the sole gate
--   (trigger removed => the secret SURVIVES => RED). Fresh tenant D + dedicated synthetic
--   secrets so nothing earlier is perturbed (this block runs last).
-- =====================================================================
\set td '00000000-0000-0000-0000-00000000000d'
insert into auth.users (id) values (:'td');

-- direct-delete vehicle
select vault.create_secret(
         'sbx-retention-direct-synthetic', 'plaid_item_token_retn-1',
         'SELF-196 retention test — synthetic; rolled back') as secret_r1 \gset
insert into pfin.plaid_items (users_id, plaid_item_id, access_token_secret_id)
  values (:'td', 'retn-D-1', :'secret_r1')
  returning item_id as item_r1 \gset
-- cascade vehicle
select vault.create_secret(
         'sbx-retention-cascade-synthetic', 'plaid_item_token_retn-2',
         'SELF-196 retention test — synthetic; rolled back') as secret_r2 \gset
insert into pfin.plaid_items (users_id, plaid_item_id, access_token_secret_id)
  values (:'td', 'retn-D-2', :'secret_r2')
  returning item_id as item_r2 \gset

-- (6a) precondition (non-vacuous): the referenced Vault secret EXISTS pre-deletion.
select is(
  (select count(*) from vault.secrets where id = :'secret_r1')::bigint, 1::bigint,
  '(6a) retention precondition: the referenced vault.secrets row EXISTS before the plaid_items row is deleted (non-vacuous control so (6b) is not trivially green)'
);
-- (6b) DIRECT delete: deleting the plaid_items row fires the AFTER DELETE trigger which
--      removes the referenced Vault secret -> no orphan.
delete from pfin.plaid_items where item_id = :item_r1;
select is(
  (select count(*) from vault.secrets where id = :'secret_r1')::bigint, 0::bigint,
  '(6b) retention HARD-GATE (direct): deleting plaid_items removes the referenced vault.secrets row (AFTER DELETE trigger closes the orphan) — RED if the trigger were removed'
);
-- (6c) precondition for the cascade path.
select is(
  (select count(*) from vault.secrets where id = :'secret_r2')::bigint, 1::bigint,
  '(6c) retention precondition (cascade): the referenced vault.secrets row EXISTS before the auth.users cascade (non-vacuous control)'
);
-- (6d) CASCADE path under a PRIVILEGED deleter (THE leak scenario, clean branch): deleting the
--      auth.users row cascades the plaid_items row (FK ON DELETE CASCADE); the AFTER DELETE
--      trigger fires on the cascaded delete and — because postgres HOLDS DELETE on vault.secrets
--      — removes the Vault secret -> orphan closed. (This is the DBA/service_role-initiated
--      cascade. The GoTrue supabase_auth_admin cascade takes the FAIL-CLOSED branch instead —
--      asserted via ACL in (6f), since supabase_auth_admin cannot be SET ROLE'd locally.)
delete from auth.users where id = :'td';
select is(
  (select count(*) from vault.secrets where id = :'secret_r2')::bigint, 0::bigint,
  '(6d) retention HARD-GATE (cascade, privileged deleter): deleting auth.users cascades plaid_items and the AFTER DELETE trigger removes the Vault secret when the deleting role holds DELETE on vault.secrets — the cascade-orphan leak is closed'
);
-- (6e) golden invariant behind the SECURITY INVOKER choice: service_role holds DELETE on
--      vault.secrets, so the real /item/remove (SELF-197) inner delete succeeds under the
--      actual removal role (the postgres-owner runs above isolate the trigger wiring; this
--      asserts the privilege assumption for the production removal role).
select ok(
  has_table_privilege('service_role', 'vault.secrets', 'DELETE'),
  '(6e) INVOKER contract (clean branch): service_role holds DELETE on vault.secrets (the AFTER DELETE trigger''s inner delete succeeds under the real /item/remove removal role)'
);
-- (6f) INVOKER contract (FAIL-CLOSED branch, ACL fact — cannot SET ROLE supabase_auth_admin
--      locally): the GoTrue role that owns auth.users and runs the user-deletion cascade LACKS
--      DELETE on vault.secrets. So the SECURITY INVOKER cleanup trigger's inner delete would be
--      denied ⇒ the cascade RAISES (by-design fail-closed) ⇒ the user-deletion transaction
--      ABORTS rather than silently orphaning an un-revocable Plaid credential (007 Sec ruling).
select ok(
  not has_table_privilege('supabase_auth_admin', 'vault.secrets', 'DELETE'),
  '(6f) INVOKER contract (fail-closed): supabase_auth_admin (owns auth.users; runs the GoTrue user-deletion cascade) holds NO DELETE on vault.secrets ⇒ the cleanup trigger fail-closes the auth cascade (deletion forced through /item/remove revoke-then-delete; no orphaned un-revocable credential)'
);

select * from finish();
rollback;
